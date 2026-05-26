-- Shared utilities for defold-ai handlers.

local M = {}

-- Count entries in a (sparse) table.
function M.count_tools(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Persist the editor's HTTP URL so the Python MCP server can find it.
-- Note: io.* in editor scripts is restricted to the project directory in
-- recent Defold versions. We write to the project root as a fallback when
-- writing to $HOME is not permitted.
function M.write_url_file(url)
  -- Try $HOME first (editor scripts in 1.10.4+ have some absolute-path access
  -- for explicitly-listed safe locations).
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
  if home then
    local path = home .. "/.defold_ai_url"
    local f, err = io.open(path, "w")
    if f then
      f:write(url)
      f:close()
      return path
    end
  end
  -- Fallback: write into the project so the URL is at least discoverable.
  local f, err = io.open(".defold_ai_url", "w")
  if f then
    f:write(url)
    f:close()
    return ".defold_ai_url"
  end
  error("could not write URL file: " .. tostring(err))
end

-- Build a Vector3-like dict from {x, y, z} table or array.
function M.parse_vec3(v, default)
  default = default or { 0, 0, 0 }
  if type(v) ~= "table" then return default end
  if v.x ~= nil then return { v.x, v.y or 0, v.z or 0 } end
  return { v[1] or 0, v[2] or 0, v[3] or 0 }
end

-- Vector4 / quaternion. Default identity.
function M.parse_quat(v, default)
  default = default or { 0, 0, 0, 1 }
  if type(v) ~= "table" then return default end
  if v.x ~= nil then return { v.x, v.y or 0, v.z or 0, v.w or 1 } end
  return { v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 1 }
end

-- Safe property getter — returns nil instead of throwing if not gettable.
function M.try_get(node, prop)
  if editor.can_get(node, prop) then
    return editor.get(node, prop)
  end
  return nil
end

-- Standardized error response for handler functions.
function M.error_response(code, message, extra)
  local r = { ok = false, error = code, message = message }
  if extra then
    for k, v in pairs(extra) do r[k] = v end
  end
  return r
end

-- Ensure a resource path looks like a Defold res:// path.
function M.norm_resource_path(path)
  if not path or path == "" then return path end
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end
  return path
end

-- ============ Filesystem helpers ============

-- Read a project-relative file (path may start with "/" — that prefix is stripped).
function M.read_file(path)
  local relative = path:gsub("^/", "")
  local f, err = io.open(relative, "r")
  if not f then return nil, tostring(err) end
  local content = f:read("*a")
  f:close()
  return content
end

-- Write a project-relative file. Overwrites.
function M.write_file(path, content)
  local relative = path:gsub("^/", "")
  local f, err = io.open(relative, "w")
  if not f then return false, tostring(err) end
  f:write(content)
  f:close()
  return true
end

-- Compatible unpack (Lua 5.1 / LuaJIT have global `unpack`; 5.2+ moved to table.unpack).
local _unpack = table.unpack or unpack

-- Run a command via Defold's editor.execute (preferred — works in the
-- editor-script sandbox where io.popen / os.execute may be blocked).
-- Falls back to io.popen on older Defold versions.
--
-- Returns (output_string, ok_bool). editor.execute raises on non-zero exit;
-- we pcall it and surface the captured stderr inside the error message.
function M.run_shell(cmd_or_args)
  if type(editor) == "table" and type(editor.execute) == "function" then
    -- editor.execute is variadic: (arg1, arg2, ..., optsTable).
    local args
    if type(cmd_or_args) == "table" then
      args = {}
      for i, v in ipairs(cmd_or_args) do args[i] = v end
    else
      args = { "/bin/sh", "-c", tostring(cmd_or_args) }
    end
    -- Wrap in /bin/sh -c "...; exit 0" so non-zero exit codes still let us
    -- capture stdout+stderr. editor.execute raises on non-zero exit and
    -- discards captured output in that case, so forcing exit 0 + redirecting
    -- stderr→stdout is the only way to surface bob compile-error text.
    local cmd_pieces = {}
    for i = 1, #args do
      cmd_pieces[i] = "'" .. tostring(args[i]):gsub("'", "'\\''") .. "'"
    end
    local sh_cmd = table.concat(cmd_pieces, " ") .. " 2>&1; __ec=$?; printf \"\\n__EXIT_CODE=%d\" \"$__ec\"; exit 0"
    local sh_args = {
      "/bin/sh", "-c", sh_cmd,
      { reload_resources = false, out = "capture" }
    }
    local ok, out = pcall(editor.execute, _unpack(sh_args))
    if not ok then
      return tostring(out), false
    end
    out = tostring(out or "")
    -- Pull the exit code marker we appended.
    local exit_str = out:match("__EXIT_CODE=(%-?%d+)%s*$")
    local exit_code = tonumber(exit_str) or 0
    if exit_str then
      out = out:gsub("\n?__EXIT_CODE=" .. exit_str .. "%s*$", "")
    end
    return out, exit_code == 0
  end
  -- Legacy fallback
  if io.popen then
    local p = io.popen(tostring(cmd_or_args) .. " 2>&1", "r")
    if not p then return nil, false end
    local out = p:read("*a") or ""
    local ok = p:close()
    return out, ok == true or ok == 0
  end
  return nil, false
end

-- ============ Bob / Java discovery (for headless builds) ============

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local function glob_first(pattern)
  -- Preferred path: editor.execute("/bin/sh", "-c", "ls -1d <pat> 2>/dev/null").
  -- Defold's editor-script sandbox blocks os.execute and most io.popen
  -- invocations in 1.12+, but exposes editor.execute as the supported channel.
  if type(editor) == "table" and type(editor.execute) == "function" then
    local ok, out = pcall(editor.execute,
      "/bin/sh", "-c", "ls -1d " .. pattern .. " 2>/dev/null",
      { reload_resources = false, out = "capture" })
    if ok and type(out) == "string" then
      local line = out:match("([^\n]+)")
      if line and line ~= "" then return line end
    end
    return nil
  end
  -- Legacy fallback (Defold < 1.10)
  if io.popen then
    local ok, p = pcall(io.popen, "/bin/ls -1d " .. pattern .. " 2>/dev/null", "r")
    if ok and p then
      local line
      pcall(function() line = p:read("*l") end)
      pcall(function() p:close() end)
      if line and line ~= "" then return line end
    end
  end
  return nil
end

-- Locate Defold's bundled JDK + bob jar on the host. macOS / Linux / Windows
-- (best-effort). Returns { java=..., bob_jar=..., dmengine=... } or nil.
function M.find_defold_toolchain()
  local hits = {}
  -- macOS
  hits.java = glob_first("/Applications/Defold.app/Contents/Resources/packages/jdk-*/bin/java")
  hits.bob_jar = glob_first("/Applications/Defold.app/Contents/Resources/packages/defold-*.jar")
  -- macOS unpack (for dmengine — version-pinned by editor sha)
  local home = os.getenv("HOME") or ""
  hits.dmengine = glob_first(home .. "/Library/Application*Support/Defold/unpack/*-arm64/arm64-macos/bin/dmengine")
                or glob_first(home .. "/Library/Application*Support/Defold/unpack/*-x86_64/x86_64-macos/bin/dmengine")
  -- Linux fallback
  if not hits.java then
    hits.java = glob_first(home .. "/.Defold/packages/jdk-*/bin/java")
                or glob_first("/opt/Defold/jdk-*/bin/java")
  end
  if not hits.bob_jar then
    hits.bob_jar = glob_first(home .. "/.Defold/packages/defold-*.jar")
                  or glob_first("/opt/Defold/defold-*.jar")
  end
  if not hits.dmengine then
    hits.dmengine = glob_first(home .. "/.Defold/unpack/*/x86_64-linux/bin/dmengine")
  end
  -- Windows (rough)
  if not hits.java and package.config:sub(1, 1) == "\\" then
    hits.java = glob_first("C:/Program*Files/Defold/jdk-*/bin/java.exe")
    hits.bob_jar = glob_first("C:/Program*Files/Defold/defold-*.jar")
  end
  return hits
end

return M
