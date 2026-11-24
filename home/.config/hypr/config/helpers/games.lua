-- The games scratchpad (special:games, SUPER+G). A game opens there by
-- itself, fullscreen, when its class is in one of two lists:
--   · ~/.config/hypr/games.json, shipped with SimplyChit (Steam games,
--     Minecraft, ...); entries can be switched off in settings.json
--     games.disabled, by name;
--   · settings.json games.classes, your own: strings (a class regex) or
--     { "name": …, "class": …, "title": …, "fullscreen": false }.
-- An entry with "fullscreen": false opens windowed; so does a game matched by
-- a rule of your own with fullscreen = false (~/.config/simplychit/hypr/rules.lua
-- loads later and wins).
--
-- The settings app and the shell's "add this game?" dialog change the lists,
-- then run `hyprctl eval 'require("config.helpers.games").refresh()'`, which
-- applies them without a reload. The dialog itself is the shell's
-- (services/Games.qml): it sees every window moved in here, by SUPER+SHIFT+G,
-- the mouse or hyprctl, and asks about the ones in neither list.
--
--   local games = require("config.helpers.games")
--   hl.bind("SUPER + SHIFT + G", games.send())
local json = require("config.helpers.json")
local settings = require("config.helpers.settings")
local scratchpad = require("config.helpers.scratchpad")

local M = {}

M.name = "games"
M.workspace = "special:games"
M.list_file = os.getenv("HOME") .. "/.config/hypr/games.json"
-- the tag a windowed game gets, so send() knows not to make it fullscreen
M.windowed_tag = "game-windowed"

-- the rules made by refresh(), by name, to switch off the ones gone since
local rules = {}

local function report(message)
    local log = io.open(os.getenv("HOME") .. "/.cache/hypr-custom.log", "a")
    if log then
        log:write(os.date("%Y-%m-%d %H:%M:%S ") .. "games.json: " .. message .. "\n")
        log:close()
    end
end

-- The shipped list, as given: { { name = …, class = … }, … }.
function M.shipped()
    local file = io.open(M.list_file, "r")
    if not file then
        return {}
    end
    local text = file:read("a")
    file:close()
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= "table" or type(data.games) ~= "table" then
        report(ok and "no \"games\" list" or tostring(data))
        return {}
    end
    return data.games
end

local function entry_of(value)
    if type(value) == "string" and value ~= "" then
        return { name = value, class = value, fullscreen = true }
    end
    if type(value) == "table" and type(value.class) == "string" and value.class ~= "" then
        return {
            name = type(value.name) == "string" and value.name or value.class,
            class = value.class,
            title = type(value.title) == "string" and value.title ~= "" and value.title or nil,
            fullscreen = value.fullscreen ~= false,
        }
    end
    return nil
end

-- Every game that has a rule: the shipped ones not switched off, then yours.
function M.entries()
    local off = {}
    local disabled = settings.get("games.disabled", {})
    if type(disabled) == "table" then
        for _, name in ipairs(disabled) do
            off[name] = true
        end
    end
    local list = {}
    for _, value in ipairs(M.shipped()) do
        local entry = entry_of(value)
        if entry and not off[entry.name] then
            list[#list + 1] = entry
        end
    end
    local own = settings.get("games.classes", {})
    if type(own) == "table" then
        for _, value in ipairs(own) do
            local entry = entry_of(value)
            if entry then
                list[#list + 1] = entry
            end
        end
    end
    return list
end

-- (Re)make one rule per game, read fresh from both lists. A rule declared
-- again under the same name replaces the old one; names no longer used are
-- switched off.
function M.refresh()
    settings.reload()
    local used = {}
    for i, entry in ipairs(M.entries()) do
        local name = "game-" .. i
        local spec = {
            name = name,
            match = { class = entry.class, title = entry.title },
            workspace = M.workspace,
        }
        if entry.fullscreen then
            spec.fullscreen = true
        else
            spec.tag = "+" .. M.windowed_tag
        end
        local ok, rule = pcall(hl.window_rule, spec)
        if ok and rule then
            rules[name] = rule
            used[name] = true
        else
            report(entry.name .. ": " .. tostring(rule))
        end
    end
    for name, rule in pairs(rules) do
        if not used[name] then
            rule:set_enabled(false)
            rules[name] = nil
        end
    end
    scratchpad.keep_on_primary(M.name, settings.get("games.primaryMonitor", true) ~= false)
end

local function windowed(window)
    for _, tag in ipairs(type(window.tags) == "table" and window.tags or {}) do
        if tostring(tag):gsub("%*$", "") == M.windowed_tag then
            return true
        end
    end
    return false
end

-- Put a window (by address, "0x…") in the games scratchpad, fullscreen
-- unless it is a windowed game, and show it. For the shell's "add to games"
-- answer, as one `hyprctl eval`, so the steps keep their order.
function M.take(address)
    local selector = "address:" .. address
    local window = hl.get_window(selector)
    if not window then
        return
    end
    if not (window.workspace and window.workspace.name == M.workspace) then
        hl.dispatch(hl.dsp.window.move({ workspace = M.workspace, follow = false, window = selector }))
    end
    if not windowed(window) then
        hl.dispatch(hl.dsp.window.fullscreen({ action = "set", window = selector }))
    end
    scratchpad.show(M.name)
end

-- Send the focused window to the games scratchpad, fullscreen, and show it;
-- or, when it is in there already, back to the workspace under it.
function M.send()
    return function()
        local window = hl.get_active_window()
        if not window then
            return
        end
        if window.workspace and window.workspace.name == M.workspace then
            local regular = hl.get_active_workspace()
            hl.dispatch(hl.dsp.window.move({ workspace = regular and regular.id or "e+0" }))
            return
        end
        local address = "address:" .. window.address
        hl.dispatch(hl.dsp.window.move({ workspace = M.workspace, follow = false, window = address }))
        if not windowed(window) then
            hl.dispatch(hl.dsp.window.fullscreen({ action = "set", window = address }))
        end
        scratchpad.show(M.name)
    end
end

return M
