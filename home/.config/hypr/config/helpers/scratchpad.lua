-- Scratchpads: named special workspaces that drop over the current one and
-- hide again on the same keys (Caelestia's `caelestia toggle <name>`). Each
-- one can own a command, started into it the first time it is opened, or again
-- after its last window closed. The bar shows each one as a chip.
--
--   local scratchpad = require("config.helpers.scratchpad")
--   hl.bind("SUPER + GRAVE", scratchpad.toggle("terminal", "alacritty"))
local M = {}

-- Show or hide special:<name> on the focused monitor. With a command, an empty
-- scratchpad starts it instead: the window opening there shows the scratchpad.
-- Toggling as well would act before the window exists, on an empty special
-- workspace, and the window would then open hidden.
function M.toggle(name, command)
    return function()
        local workspace = "special:" .. name
        if command ~= nil and command ~= "" and #hl.get_workspace_windows(workspace) == 0 then
            hl.exec_cmd(command, { workspace = workspace })
            return
        end
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
    end
end

-- Send the focused window to special:<name>, or, when it is already there,
-- back to the regular workspace under it.
function M.send(name)
    return function()
        local window = hl.get_active_window()
        if not window then
            return
        end
        if window.workspace and window.workspace.name == "special:" .. name then
            local regular = hl.get_active_workspace()
            hl.dispatch(hl.dsp.window.move({ workspace = regular and regular.id or "e+0" }))
        else
            hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. name, follow = false }))
        end
    end
end

return M
