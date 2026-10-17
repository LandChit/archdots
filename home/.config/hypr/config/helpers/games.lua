-- The games scratchpad (special:games). Steam games and Minecraft open there
-- by themselves (rules.lua), and so do the classes in settings.json's
-- games.classes. Any other game is sent there by hand (SUPER+SHIFT+G), and
-- its class is noted once in ~/.config/simplychit/games-to-review.txt, so it
-- can be looked over later and added to games.classes.
--
--   local games = require("config.helpers.games")
--   hl.bind("SUPER + SHIFT + G", games.send())
local M = {}

M.workspace = "special:games"
M.review_file = os.getenv("HOME") .. "/.config/simplychit/games-to-review.txt"

local HEADER = [[
# Windows sent to the games scratchpad by hand (SUPER+SHIFT+G), one class each,
# first time only: class, window title, date. To open one there by itself from
# now on, add its class to settings.json:
#   "games": { "classes": ["^Albion Online$"] }
# (a regular expression; ^…$ for the exact class). Delete lines once handled.
]]

-- Note a class in the review file, unless it is listed there already.
function M.note(class, title)
    if class == nil or class == "" then
        return
    end
    local existing = io.open(M.review_file, "r")
    if existing then
        for line in existing:lines() do
            if line:match("^([^\t#]+)") == class then
                existing:close()
                return
            end
        end
        existing:close()
    end
    os.execute("mkdir -p '" .. M.review_file:match("^(.*)/") .. "'")
    local out = io.open(M.review_file, "a")
    if not out then
        return
    end
    if existing == nil then
        out:write(HEADER)
    end
    local clean = (title or ""):gsub("[\t\n]", " ")
    out:write(class .. "\t" .. clean .. "\t" .. os.date("%Y-%m-%d") .. "\n")
    out:close()
end

-- Send the focused window to the games scratchpad and show it, noting its
-- class; or, when it is in there already, back to the workspace under it.
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
        M.note(window.class, window.title)
        hl.dispatch(hl.dsp.window.move({ workspace = M.workspace, follow = false }))
        local shown = hl.get_active_special_workspace()
        if not shown or shown.name ~= M.workspace then
            hl.dispatch(hl.dsp.workspace.toggle_special("games"))
        end
    end
end

return M
