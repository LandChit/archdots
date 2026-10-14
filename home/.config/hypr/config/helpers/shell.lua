-- Helpers for the fabric_shell (daemon / notifications / bar).
local M = {}

local ROOT = "~/.config/fabric_shell"
local PYTHON = ROOT .. "/.venv/bin/python"

-- Long lived fabric_shell processes. The daemon comes first so the control
-- socket exists before anything tries to talk to it. Notifications used to be
-- a third process; the daemon hosts them now, so the control centre and the
-- popups share one DND flag — and only one process claims the DBus name.
local MODULES = { "daemon", "bar" }

-- Killed but never launched: notifications.py was a separate process before the
-- daemon absorbed it, and a survivor would keep the org.freedesktop.Notifications
-- DBus name the daemon now needs. Safe to drop once no old shell can be running.
local RETIRED = { "notifications" }

-- The bracket in fabric_shel[l] keeps pkill -f from matching the shell that is
-- running this very command. [^ ]* also catches sibling folders such as
-- fabric_shell_copy, so a restart always leaves exactly one shell running.
local KILL_NAMES = table.concat(MODULES, "|") .. "|" .. table.concat(RETIRED, "|")
local KILL = "pkill -f 'fabric_shel[l][^ ]*/(" .. KILL_NAMES .. ")\\.py'"

-- Restart runs kill and launch inside one shell, so that shell's own command
-- line is visible to its own pkill. Spelling the launch paths as $R/... keeps
-- the literal text "fabric_shell/daemon.py" out of that command line, so pkill
-- cannot kill the restart mid-flight. The spawned processes still expand to
-- full paths, so the pattern matches them on the next restart.
-- Do not inline these variables — that reintroduces the self-kill.
local function launch()
    local parts = {}
    for _, module in ipairs(MODULES) do
        parts[#parts + 1] = "$PY $R/" .. module .. ".py &"
    end
    return table.concat(parts, " ")
end

local SYNC_COLORS = "wal -R && cp $HOME/.cache/wal/colors-fabric.css $R/css/colors-fabric.css"

-- Kill whatever fabric_shell is running, refresh the pywal16 colors, start it
-- again. Everything goes through a single exec_cmd so the order is guaranteed.
function M.restart()
    hl.exec_cmd(
        "R=$HOME/.config/fabric_shell; PY=$R/.venv/bin/python; "
        .. KILL .. "; sleep 1; "
        .. SYNC_COLORS .. "; "
        .. launch()
    )
end

local function ctl(...)
    return PYTHON .. " " .. ROOT .. "/ctl.py " .. table.concat({ ... }, " ")
end

-- Show or hide one of the daemon's overlay windows. The daemon keeps them
-- alive in the background, so this only sends it a line over its socket.
-- Valid names live in fabric_shell/windows.py.
function M.toggle(window)
    return hl.dsp.exec_cmd(ctl("toggle", window))
end

-- Run a media-key command and then show the OSD for it. The change has to land
-- first — the OSD reads the new level back itself rather than being told one —
-- so the two are chained inside a single shell.
-- Kinds: volume, mic, brightness.
function M.with_osd(command, kind)
    return hl.dsp.exec_cmd("sh -c '" .. command .. "; " .. ctl("show", "osd", kind) .. "'")
end

return M
