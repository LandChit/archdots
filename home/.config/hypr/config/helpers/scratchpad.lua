-- Scratchpads: named special workspaces that drop over the current one and
-- hide again on the same keys (Caelestia's `caelestia toggle <name>`). Each
-- one can own a command, started into it the first time it is opened, or again
-- after its last window closed. The bar shows each one as a chip.
--
-- A scratchpad can be kept on the primary screen (helpers/screens.lua):
-- shown from another screen, or by a window opening in it, it moves there.
--
--   local scratchpad = require("config.helpers.scratchpad")
--   hl.bind("SUPER + GRAVE", scratchpad.toggle("terminal", "alacritty"))
--   scratchpad.keep_on_primary("terminal", true)
local screens = require("config.helpers.screens")

local M = {}

-- names of the scratchpads kept on the primary screen
local on_primary = {}
local subscription = nil

-- Hyprland shows a special workspace on the screen it is toggled on, or, for
-- a window opening in it, on the focused one. Move a kept one to the primary
-- screen as it shows, and focus it there.
local function follow_primary(workspace, monitor)
    if not workspace or not monitor then
        return
    end
    local name = (workspace.name or ""):gsub("^special:", "")
    if not on_primary[name] then
        return
    end
    local primary = screens.primary()
    if not primary or primary.name == monitor.name then
        return
    end
    primary:set_special_workspace(workspace)
    hl.dispatch(hl.dsp.focus({ monitor = primary.name }))
end

function M.keep_on_primary(name, on)
    on_primary[name] = on and true or nil
    if on and subscription == nil then
        subscription = hl.on("workspace.special_active", follow_primary)
    end
end

-- Toggle special:<name> on the focused screen, or on the primary one when it
-- is kept there; after hiding it there, the focus goes back where it was.
local function toggle_on_screen(name)
    if not on_primary[name] then
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
        return
    end
    local primary = screens.primary()
    local active = hl.get_active_monitor()
    if not primary or not active or primary.name == active.name then
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
        return
    end
    local shown = primary.active_special_workspace
    local hiding = shown ~= nil and shown.name == "special:" .. name
    hl.dispatch(hl.dsp.focus({ monitor = primary.name }))
    hl.dispatch(hl.dsp.workspace.toggle_special(name))
    if hiding then
        hl.dispatch(hl.dsp.focus({ monitor = active.name }))
    end
end

-- Show or hide special:<name>, on the focused monitor or the primary one.
-- With a command, an empty scratchpad starts it instead: the window opening
-- there shows the scratchpad. Toggling as well would act before the window
-- exists, on an empty special workspace, and the window would then open
-- hidden.
function M.toggle(name, command)
    return function()
        local workspace = "special:" .. name
        if command ~= nil and command ~= "" and #hl.get_workspace_windows(workspace) == 0 then
            hl.exec_cmd(command, { workspace = workspace })
            return
        end
        toggle_on_screen(name)
    end
end

-- Show special:<name> if no screen shows it yet.
function M.show(name)
    for _, monitor in ipairs(hl.get_monitors() or {}) do
        local shown = monitor.active_special_workspace
        if shown and shown.name == "special:" .. name then
            return
        end
    end
    toggle_on_screen(name)
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
