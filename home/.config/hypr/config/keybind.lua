local shell = require("config.helpers.shell")
local settings = require("config.helpers.settings")
local scratchpad = require("config.helpers.scratchpad")

-- Every default bind is an entry in the table below, with a stable id, so the
-- settings app (and you) can change or drop it as data in
-- ~/.config/simplychit/settings.json, without code:
--
--   "keybinds": {
--     "remap":    { "browser": "SUPER + Z" },   -- id -> new keys
--     "disabled": [ "process-manager" ]         -- ids
--   }
--
-- New binds of your own still go in ~/.config/simplychit/hypr/keybind.lua.
--
-- `desc` is what the cheatsheet shows (SUPER+SLASH). It is the ONLY way to
-- label a bind: the Lua config provider registers every bind as a `__lua`
-- callback, so `hyprctl binds` sees an opaque index and cannot tell what a bind
-- does. Convention: "Group: Label". The part before the colon groups the bind
-- on the cheatsheet; binds sharing a group and label collapse into one row.

local apps = {
    terminal = settings.get("apps.terminal", "alacritty"),
    fileManager = settings.get("apps.fileManager", "dolphin"),
    browser = settings.get("apps.browser", "zen-browser"),
    processManager = settings.get("apps.processManager", "missioncenter || flatpak run io.missioncenter.MissionCenter"),
}

local mainMod = "SUPER"

local region_ss =
"sh -c 'REGION=$(slurp) || exit; grim -g \"$REGION\" - | wl-copy &&  wl-paste > ~/Pictures/screenshots/Screenshot-$(date +%F_%T).png && notify-send -t 2000 \"Screenshot of the region taken\"'"
local screen_ss =
"grim - | wl-copy && wl-paste > ~/Pictures/screenshots/Screenshot-$(date +%F_%T).png && notify-send -t 2000 \"Screenshot of the whole screen taken\""

-- { id, keys, action, desc, opts }
local binds = {
    { "terminal", mainMod .. " + RETURN", hl.dsp.exec_cmd(apps.terminal), "Launch: Terminal" },
    { "file-manager", mainMod .. " + E", hl.dsp.exec_cmd(apps.fileManager), "Launch: File manager" },
    { "browser", mainMod .. " + B", hl.dsp.exec_cmd(apps.browser), "Launch: Browser" },
    { "process-manager", "CONTROL + SHIFT + ESCAPE", hl.dsp.exec_cmd(apps.processManager), "Launch: Process manager" },

    { "screenshot-region", mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(region_ss), "Screenshot: Region to clipboard + file" },
    { "screenshot-region-key", "PRINT", hl.dsp.exec_cmd(region_ss), "Screenshot: Region to clipboard + file" },
    { "screenshot-screen", "SHIFT + PRINT", hl.dsp.exec_cmd(screen_ss), "Screenshot: Whole screen to clipboard + file" },

    { "launcher", mainMod .. " + SPACE", shell.toggle("launcher"), "Shell: App launcher" },
    { "emoji", mainMod .. " + PERIOD", shell.toggle("emoji"), "Shell: Emoji picker" },
    { "clipboard", mainMod .. " + V", shell.toggle("clipboard"), "Shell: Clipboard history" },
    { "power-menu", mainMod .. " + ESCAPE", shell.toggle("powermenu"), "Shell: Power menu" },
    { "notifications", mainMod .. " + N", shell.toggle("notifications"), "Shell: Notifications" },
    { "control-centre", mainMod .. " + C", shell.toggle("control"), "Shell: Control centre" },
    { "wallpaper", mainMod .. " + W", shell.toggle("wallpaper"), "Shell: Wallpaper picker" },
    { "cheatsheet", mainMod .. " + SLASH", shell.toggle("keybinds"), "Shell: This cheatsheet" },
    { "notepad", mainMod .. " + SHIFT + N", shell.toggle("notepad"), "Shell: Notepad" },
    -- the direct region/full binds above still work; this is the menu with
    -- window capture and a delayed shot as well
    { "screenshot-menu", mainMod .. " + PRINT", shell.toggle("screenshot"), "Shell: Screenshot menu" },
    { "record", mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(shell.ipc("recording", "toggle")), "Shell: Record a region / stop recording" },
    { "settings", mainMod .. " + COMMA", hl.dsp.exec_cmd(shell.ipc("settings", "open", "''")), "Shell: Settings" },
    { "restart-shell", mainMod .. " + SHIFT + CONTROL + ALT + R", function() shell.restart() end, "Shell: Restart the shell" },

    -- pauses dim/lock/suspend until pressed again
    { "stay-awake", mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("$HOME/.config/hypr/Scripts/idle-inhibit.sh toggle"), "System: Toggle stay awake" },

    { "close", mainMod .. " + SHIFT + Q", hl.dsp.window.close(), "Window: Close" },
    { "focus-left", mainMod .. " + left", hl.dsp.focus({ direction = "left" }), "Window: Move focus" },
    { "focus-right", mainMod .. " + right", hl.dsp.focus({ direction = "right" }), "Window: Move focus" },
    { "focus-up", mainMod .. " + up", hl.dsp.focus({ direction = "up" }), "Window: Move focus" },
    { "focus-down", mainMod .. " + down", hl.dsp.focus({ direction = "down" }), "Window: Move focus" },
    { "move-left", mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }), "Window: Move window" },
    { "move-right", mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }), "Window: Move window" },
    { "move-up", mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }), "Window: Move window" },
    { "move-down", mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }), "Window: Move window" },
    { "resize-wider", mainMod .. " + P", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), "Window: Resize wider", { repeating = true } },
    { "resize-narrower", mainMod .. " + U", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), "Window: Resize narrower", { repeating = true } },
    { "resize-taller", mainMod .. " + O", hl.dsp.window.resize({ y = 10, x = 0, relative = true }), "Window: Resize taller", { repeating = true } },
    { "resize-shorter", mainMod .. " + I", hl.dsp.window.resize({ y = -10, x = 0, relative = true }), "Window: Resize shorter", { repeating = true } },
    { "float", mainMod .. " + T", hl.dsp.window.float(), "Window: Toggle floating" },
    { "fullscreen", mainMod .. " + F", hl.dsp.window.fullscreen(), "Window: Fullscreen" },
    { "drag-move", mainMod .. " + mouse:272", hl.dsp.window.drag(), "Window: Drag to move", { mouse = true } },
    { "drag-resize", mainMod .. " + mouse:273", hl.dsp.window.resize(), "Window: Drag to resize", { mouse = true } },

    { "workspace-next", mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Workspace: Scroll to next workspace" },
    { "workspace-previous", mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), "Workspace: Scroll to previous workspace" },

    -- the shell's OSD shows itself whenever a level changes
    { "volume-up", "XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 2 @DEFAULT_AUDIO_SINK@ 5%+"), "Media: Volume up", { locked = true, repeating = true } },
    { "volume-down", "XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), "Media: Volume down", { locked = true, repeating = true } },
    { "mute", "XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), "Media: Mute output", { locked = true, repeating = true } },
    { "mic-mute", "XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Media: Mute microphone", { locked = true, repeating = true } },
    { "brightness-up", "XF86MonBrightnessUp", shell.brightness("up"), "Media: Brightness up", { locked = true, repeating = true } },
    { "brightness-down", "XF86MonBrightnessDown", shell.brightness("down"), "Media: Brightness down", { locked = true, repeating = true } },
    { "media-next", "XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), "Media: Next track", { locked = true } },
    { "media-pause", "XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), "Media: Play / pause", { locked = true } },
    { "media-play", "XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), "Media: Play / pause", { locked = true } },
    { "media-previous", "XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), "Media: Previous track", { locked = true } },
}

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    binds[#binds + 1] = { "workspace-" .. i, mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), "Workspace: Switch to workspace" }
    binds[#binds + 1] = { "move-to-workspace-" .. i, mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), "Workspace: Move window to workspace" }
end

-- Scratchpads (special workspaces) drop over the current workspace and hide on
-- the same keys. "terminal" starts one the first time; "scratch" holds
-- whatever you send it. More in settings.json, each with the id
-- "scratchpad-<name>":
--   "keybinds": { "scratchpads": { "music": { "keys": "SUPER + M", "command": "spotify" } } }
binds[#binds + 1] = { "scratchpad-terminal", mainMod .. " + GRAVE", scratchpad.toggle("terminal", apps.terminal), "Scratchpad: Drop-down terminal" }
binds[#binds + 1] = { "scratchpad-scratch", mainMod .. " + MINUS", scratchpad.toggle("scratch"), "Scratchpad: Show / hide the scratchpad" }
binds[#binds + 1] = { "scratchpad-send", mainMod .. " + SHIFT + MINUS", scratchpad.send("scratch"), "Scratchpad: Send window to / back from the scratchpad" }
local extra_pads = settings.get("keybinds.scratchpads", {})
if type(extra_pads) ~= "table" then
    extra_pads = {}
end
local pad_names = {}
for name, pad in pairs(extra_pads) do
    local builtin = name == "terminal" or name == "scratch" or name == "send" -- change those with remap
    if not builtin and type(pad) == "table" and type(pad.keys) == "string" and name:match("^[%w_-]+$") then
        pad_names[#pad_names + 1] = name
    end
end
table.sort(pad_names) -- pairs() has no order; keep the list stable
for _, name in ipairs(pad_names) do
    local pad = extra_pads[name]
    local command = type(pad.command) == "string" and pad.command or nil
    binds[#binds + 1] = { "scratchpad-" .. name, pad.keys, scratchpad.toggle(name, command), "Scratchpad: " .. name }
end

-- ── apply, with the user's remaps and removals ───────────────────────────
local remap = settings.get("keybinds.remap", {})
local disabled = {}
for _, id in ipairs(settings.get("keybinds.disabled", {})) do
    disabled[id] = true
end

local catalog = {}
for _, b in ipairs(binds) do
    local id, keys, action, desc, opts = b[1], b[2], b[3], b[4], b[5]
    local current = type(remap[id]) == "string" and remap[id] or keys
    if not disabled[id] then
        local options = { desc = desc }
        for k, v in pairs(opts or {}) do
            options[k] = v
        end
        hl.bind(current, action, options)
    end
    catalog[#catalog + 1] = { id = id, desc = desc, default = keys, keys = current, disabled = disabled[id] == true }
end

-- The list the settings app's Keybinds page reads: every default bind, its
-- id, its default keys and what it is bound to now. Generated, in the cache.
local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return c == '"' and '\\"' or c == "\\" and "\\\\" or ("\\u%04x"):format(c:byte())
    end) .. '"'
end
local dir = os.getenv("HOME") .. "/.cache/simplychit"
os.execute("mkdir -p '" .. dir .. "'")
local out = io.open(dir .. "/keybinds.json", "w")
if out then
    local rows = {}
    for _, c in ipairs(catalog) do
        rows[#rows + 1] = ("  {%s: %s, %s: %s, %s: %s, %s: %s, %s: %s}"):format(
            quote("id"), quote(c.id), quote("desc"), quote(c.desc), quote("default"), quote(c.default),
            quote("keys"), quote(c.keys), quote("disabled"), tostring(c.disabled))
    end
    out:write("[\n" .. table.concat(rows, ",\n") .. "\n]\n")
    out:close()
end
