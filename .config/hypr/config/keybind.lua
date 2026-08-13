local shell = require("config.helpers.shell")

-- Variables
local terminal = "alacritty"
local filemanager = "dolphin"
local browser = "zen-browser"
local processManager = "flatpak run io.missioncenter.MissionCenter"

local mainMod = "SUPER"

-- `desc` is what the cheatsheet shows (SUPER+SLASH). It is the ONLY way to
-- label a bind: the Lua config provider registers every bind as a `__lua`
-- callback, so `hyprctl binds` sees an opaque index and cannot tell what a bind
-- does. Anything without a desc still shows up, listed as undescribed.
--
-- Convention: "Group: Label". The part before the colon groups the bind on the
-- cheatsheet; binds sharing a group and label collapse into one row, which is
-- how the ten workspace binds show as a single line.


-- Launch programs
hl.bind(mainMod .. "+ RETURN", hl.dsp.exec_cmd(terminal), { desc = "Launch: Terminal" })
hl.bind(mainMod .. "+ E", hl.dsp.exec_cmd(filemanager), { desc = "Launch: File manager" })
hl.bind(mainMod .. "+ B", hl.dsp.exec_cmd(browser), { desc = "Launch: Browser" })
hl.bind("CONTROL + SHIFT + ESCAPE", hl.dsp.exec_cmd(processManager),
    { desc = "Launch: Process manager" })

-- ScreenShot
local region_ss =
"sh -c 'REGION=$(slurp) || exit; grim -g \"$REGION\" - | wl-copy &&  wl-paste > ~/Pictures/screenshots/Screenshot-$(date +%F_%T).png && notify-send -t 2000 \"Screenshot of the region taken\"'"
hl.bind(mainMod .. "+ SHIFT + S", hl.dsp.exec_cmd(region_ss),
    { desc = "Screenshot: Region to clipboard + file" })
hl.bind("PRINT", hl.dsp.exec_cmd(region_ss),
    { desc = "Screenshot: Region to clipboard + file" })
hl.bind("SHIFT + PRINT",
    hl.dsp.exec_cmd(
        "grim - | wl-copy && wl-paste > ~/Pictures/screenshots/Screenshot-$(date +%F_%T).png && notify-send -t 2000 \"Screenshot of the whole screen taken\""),
    { desc = "Screenshot: Whole screen to clipboard + file" })

-- Launcher and tools
hl.bind(mainMod .. "+ SPACE", shell.toggle("launcher"), { desc = "Shell: App launcher" })
hl.bind(mainMod .. "+ PERIOD", shell.toggle("emoji"), { desc = "Shell: Emoji picker" })
hl.bind(mainMod .. "+ V", shell.toggle("clipboard"), { desc = "Shell: Clipboard history" })
hl.bind(mainMod .. "+ ESCAPE", shell.toggle("powermenu"), { desc = "Shell: Power menu" })
hl.bind(mainMod .. "+ N", shell.toggle("notifications"), { desc = "Shell: Notifications" })
hl.bind(mainMod .. "+ C", shell.toggle("control"), { desc = "Shell: Control centre" })
hl.bind(mainMod .. "+ W", shell.toggle("wallpaper"), { desc = "Shell: Wallpaper picker" })
hl.bind(mainMod .. "+ SLASH", shell.toggle("keybinds"), { desc = "Shell: This cheatsheet" })
-- the direct region/full binds above still work; this is the menu with
-- window capture and a delayed shot as well
hl.bind(mainMod .. "+ PRINT", shell.toggle("screenshot"), { desc = "Shell: Screenshot menu" })


-- Other
hl.bind(mainMod .. "+ SHIFT + Q", hl.dsp.window.close(), { desc = "Window: Close" })

hl.bind(mainMod .. "+ left", hl.dsp.focus({ direction = "left" }), { desc = "Window: Move focus" })
hl.bind(mainMod .. "+ right", hl.dsp.focus({ direction = "right" }), { desc = "Window: Move focus" })
hl.bind(mainMod .. "+ up", hl.dsp.focus({ direction = "up" }), { desc = "Window: Move focus" })
hl.bind(mainMod .. "+ down", hl.dsp.focus({ direction = "down" }), { desc = "Window: Move focus" })

hl.bind(mainMod .. "+ SHIFT + left", hl.dsp.window.move({ direction = "left" }),
    { desc = "Window: Move window" })
hl.bind(mainMod .. "+ SHIFT + right", hl.dsp.window.move({ direction = "right" }),
    { desc = "Window: Move window" })
hl.bind(mainMod .. "+ SHIFT + up", hl.dsp.window.move({ direction = "up" }),
    { desc = "Window: Move window" })
hl.bind(mainMod .. "+ SHIFT + down", hl.dsp.window.move({ direction = "down" }),
    { desc = "Window: Move window" })


hl.bind(mainMod .. "+ P", hl.dsp.window.resize({ x = 10, y = 0, relative = true }),
    { repeating = true, desc = "Window: Resize wider" })
hl.bind(mainMod .. "+ U", hl.dsp.window.resize({ x = -10, y = 0, relative = true }),
    { repeating = true, desc = "Window: Resize narrower" })
hl.bind(mainMod .. "+ O", hl.dsp.window.resize({ y = 10, x = 0, relative = true }),
    { repeating = true, desc = "Window: Resize taller" })
hl.bind(mainMod .. "+ I", hl.dsp.window.resize({ y = -10, x = 0, relative = true }),
    { repeating = true, desc = "Window: Resize shorter" })

hl.bind(mainMod .. "+ T", hl.dsp.window.float(), { desc = "Window: Toggle floating" })


hl.bind(mainMod .. "+ F", hl.dsp.window.fullscreen(), { desc = "Window: Fullscreen" })

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }),
        { desc = "Workspace: Switch to workspace" })
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }),
        { desc = "Workspace: Move window to workspace" })
end

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),
    { mouse = true, desc = "Window: Drag to move" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(),
    { mouse = true, desc = "Window: Drag to resize" })

-- Each media key changes the level and then shows the shell's OSD for it.
hl.bind("XF86AudioRaiseVolume",
    shell.with_osd("wpctl set-volume -l 2 @DEFAULT_AUDIO_SINK@ 5%+", "volume"),
    { locked = true, repeating = true, desc = "Media: Volume up" })
hl.bind("XF86AudioLowerVolume",
    shell.with_osd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", "volume"),
    { locked = true, repeating = true, desc = "Media: Volume down" })
hl.bind("XF86AudioMute",
    shell.with_osd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "volume"),
    { locked = true, repeating = true, desc = "Media: Mute output" })
hl.bind("XF86AudioMicMute",
    shell.with_osd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", "mic"),
    { locked = true, repeating = true, desc = "Media: Mute microphone" })
hl.bind("XF86MonBrightnessUp",
    shell.with_osd("brightnessctl -e4 -n2 set 5%+", "brightness"),
    { locked = true, repeating = true, desc = "Media: Brightness up" })
hl.bind("XF86MonBrightnessDown",
    shell.with_osd("brightnessctl -e4 -n2 set 5%-", "brightness"),
    { locked = true, repeating = true, desc = "Media: Brightness down" })

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),
    { locked = true, desc = "Media: Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, desc = "Media: Play / pause" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, desc = "Media: Play / pause" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),
    { locked = true, desc = "Media: Previous track" })


-- RESTART SHELL
hl.bind(mainMod .. "+ SHIFT + CONTROL + ALT + R", function()
    shell.restart()
end, { desc = "Shell: Restart the shell" })
