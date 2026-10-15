-- Helpers for the desktop shell: Quickshell, config ~/.config/quickshell/simplychit.
-- Everything goes through `qs -c simplychit`: start it, stop it, and send it IPC
-- calls (`qs -c simplychit ipc show` lists every target).
local M = {}

local QS = "qs -c simplychit"

-- An IPC call as a shell command: M.ipc("panel", "toggle", "launcher").
function M.ipc(...)
    return QS .. " ipc call " .. table.concat({ ... }, " ")
end

-- Stop the running shell, if any, and start a fresh one under the watchdog,
-- which starts it again if it crashes (hypr/Scripts/shell-watchdog.sh). The
-- old watchdog leaves when its shell exits; the new one waits for that, and
-- for the old shell to be gone, since -n refuses a second instance (which is
-- also why a double press cannot leave two shells running).
function M.restart()
    hl.exec_cmd("qs kill -c simplychit >/dev/null 2>&1; "
        .. "exec sh $HOME/.config/hypr/Scripts/shell-watchdog.sh")
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
