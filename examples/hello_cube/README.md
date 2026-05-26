# hello_cube — defold-ai integration smoke test

A minimal Defold project demonstrating defold-ai. Useful for verifying the installation.

## What's in here

Just a `game.project` and `main/main.collection` skeleton. The `mcp/` editor script directory should be copied here (or to your own project) per the [INSTALL.md](../../docs/INSTALL.md) instructions.

## Smoke test prompts

After installing and connecting your MCP client:

1. **Connection test**:
   > "Ping defold-ai and tell me the editor version."

2. **List collections**:
   > "Show me the hierarchy of /main/main.collection."

3. **Spawn a cube**:
   > "Create a game object named TestCube at position (0, 0, 0) in /main/main.collection. Add a model component to it using the built-in cube mesh."

   Expected: Claude calls `gameobject_create` + `component_add`, then you see `TestCube` appear in the editor's collection outline.

4. **Edit a script**:
   > "Create a script at /main/rotator.script with code that rotates the game object on every frame."

   Expected: Claude calls `script_create` with Lua source.

5. **Attach the script**:
   > "Attach /main/rotator.script to /main/main.collection!/TestCube."

   Expected: Claude calls `script_attach`. Rebuild (F5 / Cmd+B in the editor) to see the cube rotate.

## Lua snippet Claude might generate for rotator.script

```lua
go.property("speed", 1.0)

function update(self, dt)
    local r = go.get_rotation()
    local euler = vmath.quat_rotation_y(self.speed * dt)
    go.set_rotation(r * euler)
end
```
