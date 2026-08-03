-- Helpers for the fabric_shell (bar / notifications / daemon).
local M = {}

local PYTHON = "~/.config/fabric_shell/.venv/bin/python"
local ROOT = "~/.config/fabric_shell"

-- Long lived fabric_shell processes. ctl.py is short lived and stays untouched.
local MODULES = { "bar", "notifications", "daemon" }

-- The bracket in fabric_shel[l] keeps pkill -f from matching the shell that is
-- running this very command, so only the python processes are killed.
local KILL = "pkill -f 'fabric_shel[l]/(" .. table.concat(MODULES, "|") .. ")\\.py'"

local SYNC_COLORS = "wal -R && cp ~/.cache/wal/colors-fabric.css " .. ROOT .. "/css/colors-fabric.css"

local function launch()
    local parts = {}
    for _, module in ipairs(MODULES) do
        parts[#parts + 1] = PYTHON .. " " .. ROOT .. "/" .. module .. ".py &"
    end
    return table.concat(parts, " ")
end

-- Kill whatever fabric_shell is running, refresh the pywal colors, start it
-- again. Everything goes through a single exec_cmd so the order is guaranteed.
function M.restart()
    hl.exec_cmd(KILL .. "; sleep 0.5; " .. SYNC_COLORS .. "; " .. launch())
end

return M
