-- The primary screen, the same choice as the shell's services/Screens.qml:
-- settings.json displays.primary (Hyprland's description, or a port name
-- written by hand) when it is connected, else the built-in panel (eDP*),
-- else the first screen.
--
--   local screens = require("config.helpers.screens")
--   local monitor = screens.primary()   -- an HL.Monitor, or nil
local settings = require("config.helpers.settings")

local M = {}

function M.primary()
    local key = settings.get("displays.primary", "")
    local monitors = hl.get_monitors() or {}
    if type(key) == "string" and key ~= "" then
        for _, monitor in ipairs(monitors) do
            if monitor.description == key or monitor.name == key then
                return monitor
            end
        end
    end
    for _, monitor in ipairs(monitors) do
        if monitor.name:match("^eDP") then
            return monitor
        end
    end
    return monitors[1]
end

return M
