-- THEME — floating-glass look matching the fabric shell
-- Colors come from pywal via ~/.cache/wal/colors-hyprland.lua
-- (template: ~/.config/wal/templates/colors-hyprland.lua).
-- Run `hyprctl reload` after re-running wal to pick up a new palette.

local fallback = {
    background = "0a0b0b",
    foreground = "e3e4e2",
    color4 = "727A83",
    color6 = "C4C2B9",
    color8 = "9e9f9e",
}

local ok, wal = pcall(dofile, os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua")
if not ok or type(wal) ~= "table" then
    wal = fallback
end

local accent   = wal.color4 or fallback.color4
local accent2  = wal.color6 or fallback.color6
local inactive = wal.color8 or fallback.color8

hl.config({
    general = {
        border_size = 2,
        gaps_in = 3,
        gaps_out = 5,

        col = {
            -- accent gradient like the shell's selected-row glow
            active_border = "rgba(" .. accent2 .. "ee)",
            inactive_border = "rgba(" .. inactive .. "55)",
        },

        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        -- matches the shell's row/tile radius
        rounding = 12,
        rounding_power = 2,

        active_opacity = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled = true,
            range = 16,
            render_power = 3,
            color = "rgba(00000066)",
        },

        -- frosted glass behind the ~85%-opaque shell panels
        blur = {
            enabled = true,
            size = 6,
            passes = 3,
            popups = true,

            vibrancy = 0.1696,
        }
    },
    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
        -- pseudotile = true,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
    }
})
