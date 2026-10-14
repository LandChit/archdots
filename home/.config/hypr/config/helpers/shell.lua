-- Helpers for the desktop shell: Quickshell, config ~/.config/quickshell/archdots.
-- Everything goes through `qs -c archdots`: start it, stop it, and send it IPC
-- calls (`qs -c archdots ipc show` lists every target).
local M = {}

local QS = "qs -c archdots"

-- An IPC call as a shell command: M.ipc("panel", "toggle", "launcher").
function M.ipc(...)
    return QS .. " ipc call " .. table.concat({ ... }, " ")
end

-- Stop the running shell, if any, and start a fresh one, detached. -n refuses
-- a second instance, so a double press cannot leave two shells running.
function M.restart()
    hl.exec_cmd("qs kill -c archdots >/dev/null 2>&1; " .. QS .. " -n -d")
end

-- Open or close one of the shell's panels. Names: services/Panels.qml.
function M.toggle(panel)
    return hl.dsp.exec_cmd(M.ipc("panel", "toggle", panel))
end

-- Screen brightness up or down on the focused monitor (backlight or DDC/CI);
-- the shell shows its OSD. Volume keys need nothing like this: the OSD reacts
-- to any change of the default device's level by itself.
function M.brightness(direction)
    return hl.dsp.exec_cmd(M.ipc("brightness", direction))
end

return M
