hl.config({
    general = {
        border_size = 2,
        gaps_in = 2,
        gaps_out = 5,

        col = {
            active_border = "rgba(ff5784aa)",
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        rounding_power = 2,

        active_opacity = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },

        blur = {
            enabled = true,
            size = 3,
            passes = 1,

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
