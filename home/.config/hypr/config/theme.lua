-- THEME — floating-glass look matching the fabric shell
-- Colors come from pywal16 via ~/.cache/wal/colors-hyprland.lua
-- (template: ~/.config/wal/templates/colors-hyprland.lua).
-- Run `hyprctl reload` after re-running wal to pick up a new palette.

-- Doubles as the whole palette when the cache is missing (`wal = fallback`), so
-- it carries the semantic names the template emits. The colorN entries stay
-- because a cache written by classic pywal has no semantic keys and the `or`
-- chains below walk down to them.
local fallback = {
    background    = "0a0b0b",
    foreground    = "e3e4e2",
    color4        = "727A83",
    color8        = "9e9f9e",
    accent_bright = "8f99a6",
    inactive      = "9e9f9e",
}

local ok, wal = pcall(dofile, os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua")
if not ok or type(wal) ~= "table" then
    wal = fallback
end

-- The active border uses the bright counterpart of the accent (color12), which
-- is a real colour under --cols16 dual. Each name falls back through the
-- palette it came from, so a cache written by classic pywal — no semantic keys,
-- and color12 a copy of color4 — still renders, just with less separation.
local accent   = wal.accent_bright or wal.color12 or wal.color4 or fallback.accent_bright
local inactive = wal.inactive or wal.color8 or fallback.inactive

hl.config({
    general = {
        border_size = 2,
        gaps_in = 3,
        gaps_out = 5,

        col = {
            -- Single colour, not a gradient: Hyprland's native Lua parser
            -- validates this as one colour and rejects the space-separated
            -- "rgba(..) rgba(..) 45deg" gradient form outright, with
            -- "invalid color". Do not reintroduce a gradient here.
            active_border = "rgba(" .. accent .. "ee)",
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
        border_part_of_window = true,

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
