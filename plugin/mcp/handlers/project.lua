-- Project handlers — build, run, stop, settings, logs, batch.

local util = require "mcp.lib.util"

local M = {}

-- ============ In-memory log buffer ============
local LOG_BUFFER = {}
local MAX_LOG_LINES = 500

local function log_line(level, source, text)
  table.insert(LOG_BUFFER, { level = level, source = source, text = text, t = os.time() })
  while #LOG_BUFFER > MAX_LOG_LINES do
    table.remove(LOG_BUFFER, 1)
  end
  print("[" .. source .. "] " .. text)
end

-- ============ Build helpers ============

-- Parse bob output for compile errors (one per file:line).
local function extract_bob_errors(output)
  if not output or output == "" then return {} end
  local errors = {}
  -- Pattern: "ERROR <file>:<line> <message>" lines.
  for path, line, msg in output:gmatch("ERROR%s+([%S]+):(%d+)%s+([^\n]+)") do
    table.insert(errors, { file = path, line = tonumber(line), message = msg })
  end
  -- Also catch generic ERROR lines without file:line.
  if #errors == 0 then
    for line in output:gmatch("[^\n]+") do
      if line:find("^ERROR") or line:find("CompileExceptionError") or line:find("The build failed") then
        table.insert(errors, { message = line })
      end
    end
  end
  return errors
end

-- Run a headless bob build. Returns a structured response.
local function bob_build(variant)
  variant = variant or "debug"
  local tc = util.find_defold_toolchain()
  if not tc.java or not tc.bob_jar then
    return util.error_response("BOB_NOT_FOUND",
      "Could not locate Defold's bundled JDK or bob.jar. " ..
      "Searched /Applications/Defold.app (macOS) and ~/.Defold (Linux). " ..
      "Set DEFOLD_AI_JAVA + DEFOLD_AI_BOB_JAR env vars to override.",
      { hints = tc })
  end
  local java = os.getenv("DEFOLD_AI_JAVA") or tc.java
  local jar  = os.getenv("DEFOLD_AI_BOB_JAR") or tc.bob_jar
  log_line("info", "defold-ai", "build via bob: " .. java .. " ... --variant=" .. variant)
  -- Pass args directly to editor.execute (no shell wrapping). This avoids
  -- quoting bugs and lets editor.execute capture both stdout and stderr.
  local output, ok = util.run_shell({
    java, "-cp", jar, "com.dynamo.bob.Bob", "--variant=" .. variant, "build",
  })
  local errors = extract_bob_errors(output or "")
  if not ok or #errors > 0 or (output and output:find("The build failed")) then
    return util.error_response("BUILD_ERROR", "Bob build failed", {
      errors = errors,
      output_tail = output and output:sub(math.max(1, #output - 2000)) or "",
    })
  end
  return {
    ok = true,
    variant = variant,
    output_tail = output and output:sub(math.max(1, #output - 1500)) or "",
  }
end

-- ============ Tool registry handle (filled in by mcp.editor_script) ============
-- batch_execute needs the full tool table to dispatch. We expose a setter the
-- entry point calls right after `local h_project = require ...`.
local TOOLS_REF = nil
function M._set_tools_registry(tools) TOOLS_REF = tools end

-- ============ Public ops ============

function M.run(body)
  local mode = body.mode or "main"
  local variant = body.variant or "debug"
  log_line("info", "defold-ai", "project_run (mode=" .. mode .. ", variant=" .. variant .. ")")

  -- Step 1: build
  local build_result = bob_build(variant)
  if not build_result.ok then
    build_result.stage = "build"
    return build_result
  end

  -- Step 2: spawn dmengine in the background, redirecting output to log.txt
  local tc = util.find_defold_toolchain()
  if not tc.dmengine then
    return util.error_response("ENGINE_NOT_FOUND",
      "Built OK, but could not locate dmengine binary to launch. " ..
      "Set DEFOLD_AI_DMENGINE env var to override.",
      { build_output_tail = build_result.output_tail })
  end
  local engine = os.getenv("DEFOLD_AI_DMENGINE") or tc.dmengine
  -- Launch detached: a sub-shell forks the engine then exits, so editor.execute
  -- returns immediately without waiting on dmengine.
  local launch_cmd = string.format(
    '( "%s" >> dmengine.log 2>&1 < /dev/null & ) ; sleep 0.1',
    engine
  )
  local _, _ = util.run_shell({ "/bin/sh", "-c", launch_cmd })
  log_line("info", "defold-ai", "dmengine launched: " .. engine)
  return {
    ok = true,
    stage = "launched",
    engine = engine,
    note = "Game launched. Stdout/stderr captured in ./dmengine.log inside the project.",
  }
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}

  if op == "stop" then
    -- Best-effort: SIGTERM the dmengine processes spawned by this project.
    local out, _ = util.run_shell("pkill -TERM -f dmengine")
    log_line("info", "defold-ai", "stop requested (pkill dmengine)")
    return { ok = true, note = "Sent SIGTERM to any running dmengine process(es).", killed_output = out }

  elseif op == "build" then
    local variant = params.variant or "debug"
    return bob_build(variant)

  elseif op == "settings_get" then
    local key = params.key or ""
    if key == "" then return util.error_response("MISSING_PARAM", "settings_get needs key") end
    local content, err = util.read_file("game.project")
    if not content then return util.error_response("READ_ERROR", err) end
    local section, prop = key:match("^([^.]+)%.(.+)$")
    if not section then return util.error_response("INVALID_KEY", "key must be 'section.prop'") end
    local pattern = "%[" .. section .. "%]([^%[]*)"
    local section_body = content:match(pattern)
    if not section_body then return { ok = true, key = key, value = nil } end
    local value = section_body:match(prop .. "%s*=%s*([^\n]+)")
    return { ok = true, key = key, value = value and value:match("^%s*(.-)%s*$") }

  elseif op == "settings_set" then
    local key = params.key or ""
    local value = params.value
    if key == "" or value == nil then
      return util.error_response("MISSING_PARAM", "settings_set needs key + value")
    end
    local section, prop = key:match("^([^.]+)%.(.+)$")
    if not section then return util.error_response("INVALID_KEY", "key must be 'section.prop'") end
    local content, rerr = util.read_file("game.project")
    if not content then return util.error_response("READ_ERROR", rerr) end
    local value_str = tostring(value)
    -- Parse the INI into a structured form (preserves blank lines + key order).
    -- Sections: list of { name = "...", lines = { "key = value", "", ... } }.
    local sections = {}
    local current = { name = "__preamble", lines = {} }
    table.insert(sections, current)
    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
      local sec_name = line:match("^%s*%[([^%]]+)%]%s*$")
      if sec_name then
        current = { name = sec_name, lines = {} }
        table.insert(sections, current)
      else
        table.insert(current.lines, line)
      end
    end
    -- Find or create the target section.
    local target
    for _, s in ipairs(sections) do
      if s.name == section then target = s; break end
    end
    if not target then
      target = { name = section, lines = { prop .. " = " .. value_str } }
      table.insert(sections, target)
    else
      -- Update or insert prop. Match `<prop>` exactly at line start (ignore whitespace).
      local found = false
      for i, line in ipairs(target.lines) do
        local lkey = line:match("^%s*([%w_%-%.]+)%s*=")
        if lkey == prop then
          target.lines[i] = prop .. " = " .. value_str
          found = true
          break
        end
      end
      if not found then
        -- Append, trimming trailing blank lines first so the section stays tight.
        while #target.lines > 0 and target.lines[#target.lines]:match("^%s*$") do
          table.remove(target.lines)
        end
        table.insert(target.lines, prop .. " = " .. value_str)
      end
    end
    -- Re-render: preamble (no header), then each section.
    local out = {}
    for i, s in ipairs(sections) do
      if s.name ~= "__preamble" then
        if i > 1 then table.insert(out, "") end
        table.insert(out, "[" .. s.name .. "]")
      end
      for _, line in ipairs(s.lines) do
        table.insert(out, line)
      end
    end
    local new_content = table.concat(out, "\n")
    -- Trim duplicate trailing newlines, leave exactly one.
    new_content = new_content:gsub("\n+$", "\n")
    if not new_content:match("\n$") then new_content = new_content .. "\n" end
    local wok, werr = util.write_file("game.project", new_content)
    if not wok then return util.error_response("WRITE_ERROR", tostring(werr)) end
    return { ok = true, key = key, value = value_str }

  elseif op == "info" then
    local caps = {
      io_popen = type(io.popen) == "function",
      os_execute = type(os.execute) == "function",
      editor_execute = type(editor) == "table" and type(editor.execute) == "function",
    }
    -- editor.execute is the only one Defold's sandbox reliably allows in 1.12+.
    local cwd
    pcall(function() cwd = require("lfs").currentdir() end)
    if not cwd then
      -- io.open(".defold_ai_url","r") works → cwd is whatever Defold set on launch.
      -- Best-effort: read PWD env var.
      cwd = os.getenv("PWD") or "."
    end
    return {
      ok = true,
      project_root = cwd,
      version = sys and sys.get_engine_info and sys.get_engine_info().version or "unknown",
      toolchain = util.find_defold_toolchain(),
      sandbox_capabilities = caps,
    }
  end
  return util.error_response("UNKNOWN_OP", "Unknown project_manage op: " .. op)
end

function M.logs_read(body)
  local source = body.source or "editor"
  local count = body.count or 50
  local offset = body.offset or 0

  if source == "game" then
    -- Tail dmengine.log produced by project_run.
    local content = util.read_file("dmengine.log") or ""
    local lines = {}
    for line in content:gmatch("[^\n]+") do
      table.insert(lines, { source = "game", text = line })
    end
    local total = #lines
    local start_i = math.max(1, total - offset - count + 1)
    local end_i = math.max(1, total - offset)
    local out = {}
    for i = start_i, end_i do
      table.insert(out, lines[i])
    end
    return { ok = true, source = source, lines = out, total_count = total }
  end

  local out = {}
  local start_i = math.max(1, #LOG_BUFFER - offset - count + 1)
  local end_i = math.max(1, #LOG_BUFFER - offset)
  for i = start_i, end_i do
    local entry = LOG_BUFFER[i]
    if entry and (source == "all" or source == entry.source or
                 (source == "editor" and entry.source == "defold-ai")) then
      table.insert(out, entry)
    end
  end
  return { ok = true, source = source, lines = out, total_count = #LOG_BUFFER }
end

function M.batch_execute(body)
  local steps = body.steps or {}
  local results = {}
  if not TOOLS_REF then
    return util.error_response("INTERNAL", "batch_execute: tool registry not bound")
  end
  for i, step in ipairs(steps) do
    local tool = step.tool or ""
    local params = step.params or {}
    local handler = TOOLS_REF[tool]
    if not handler then
      table.insert(results, {
        index = i, tool = tool,
        ok = false, error = "UNKNOWN_TOOL",
        message = "No handler for tool: " .. tool,
      })
      if not step.ignore_errors then break end
    else
      local ok, res = pcall(handler, params)
      if not ok then
        table.insert(results, {
          index = i, tool = tool,
          ok = false, error = "HANDLER_ERROR", message = tostring(res),
        })
        if not step.ignore_errors then break end
      else
        if type(res) ~= "table" then res = { value = res } end
        if res.ok == nil then res.ok = true end
        res.index = i; res.tool = tool
        table.insert(results, res)
        if not res.ok and not step.ignore_errors then break end
      end
    end
  end
  return { ok = true, results = results }
end

-- Expose for other handlers to log into the same buffer.
M._log = log_line

return M
