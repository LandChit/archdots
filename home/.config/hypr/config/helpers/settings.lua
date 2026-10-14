-- ~/.config/archdots/settings.json, for the Hyprland config: the same file
-- the shell and its settings app read and write. Displays, input, keybinds and
-- the default apps are kept there, as data, and applied by the config modules.
--
--   local settings = require("config.helpers.settings")
--   local apps = settings.get("apps", {})
--
-- A missing file is no settings; a broken one is reported (notification and
-- ~/.cache/hypr-custom.log) and treated as no settings, so the defaults apply.
local json = require("config.helpers.json")

local M = {}

local path = os.getenv("HOME") .. "/.config/archdots/settings.json"
local cache = nil

local function report(message)
    local log = io.open(os.getenv("HOME") .. "/.cache/hypr-custom.log", "a")
    if log then
        log:write(os.date("%Y-%m-%d %H:%M:%S ") .. "settings.json: " .. message .. "\n")
        log:close()
    end
    hl.exec_cmd("notify-send -u critical 'settings.json could not be read' '"
        .. message:gsub("'", "'\\''") .. "'")
end

function M.load()
    if cache then
        return cache
    end
    cache = {}
    local file = io.open(path, "r")
    if not file then
        return cache
    end
    local text = file:read("a")
    file:close()
    if text:match("^%s*$") then
        return cache
    end
    local ok, data = pcall(json.decode, text)
    if ok and type(data) == "table" then
        cache = data
    else
        report(ok and "not a JSON object" or tostring(data))
    end
    return cache
end

-- settings.get("displays.active", default): a dotted path into the file
function M.get(key, default)
    local node = M.load()
    for part in key:gmatch("[^.]+") do
        if type(node) ~= "table" then
            return default
        end
        node = node[part]
    end
    if node == nil then
        return default
    end
    return node
end

return M
