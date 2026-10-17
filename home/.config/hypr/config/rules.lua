-- WINDOW RULES

hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})
hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})


hl.window_rule({
    name = "fix-xwayland-video-bridge",
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    opacity = 0,
    no_initial_focus = true,
    no_blur = true,
    no_focus = true,
    max_size = { 1, 1 },

})

hl.window_rule({
    name = "Pop ups and stuff",
    match = {
        modal = true
    },
    float = true,
})

hl.window_rule({
    name = "PIP",
    match = {
        title = "(Picture in Picture)"
    },
    float = true,
})

-- The shell's settings app: a dialog-sized window in the middle, not a tile.
hl.window_rule({
    name = "simplychit-settings",
    match = {
        class = "^(org.quickshell)$",
        title = "^(SimplyChit settings)$",
    },
    float = true,
    size = "1000 700",
    center = true,
})

-- The first-run welcome, the same way.
hl.window_rule({
    name = "simplychit-welcome",
    match = {
        class = "^(org.quickshell)$",
        title = "^(SimplyChit welcome)$",
    },
    float = true,
    size = "760 560",
    center = true,
})

-- QOL window rules end

-- My window rules
hl.window_rule({
    name = "prism launcher",
    match = {
        class = "^(org.prismlauncher.PrismLauncher)",
        title = "^Please wait....*"
    },
    float = true,
})

hl.window_rule({
    name = "bauh",
    match = {
        class = "bauh"
    },
    float = true,
})

-- IDE's
hl.window_rule({
    name = "Netbeans IDE",
    match = {
        class = "^(Apache NetBeans IDE)"
    },
    tile = true,
})

hl.window_rule({
    name = "Netbeans IDE Options",
    match = {
        class = "^(Apache NetBeans IDE)",
        title = "^(Options)"
    },
    float = true,
})
hl.window_rule({
    name = "Netbeans IDE floating",
    match = {
        initial_class = "^(Apache NetBeans IDE)",
        title = "^(win\\d+)$"
    },
    float = true,
})

hl.window_rule({
    name = "Pycharm IDE floating",
    match = {
        initial_class = "^(jetbrains-pycharm)",
        title = "^(win\\d+)$"

    },
    float = true,
})



steam_games = "^(?i)steam_app_.*"

-- Games on work 4
hl.window_rule({
    name = "steam",
    match = {
        class = steam_games
    },
    fullscreen = true,
    workspace = "4",
})

-- hl.on("window.close", function(window)
--     if window.class == "steam_app_2225070" then
--         hl.dsp.exec_cmd("pkill steam_app_2225070")

--         hl.notification.create({
--             text = "Window: " .. window.class .. "\n Title: " .. window.title,
--             timeout = 4000,
--             icon = "ok"
--         })
--     end
-- end)

hl.window_rule({
    name = "minecraft",
    match = {
        class = "^Minecraft.*"
    },
    tile = true,
    workspace = "4",
})

-- Frosted glass for the shell's surfaces (namespaces "simplychit-<name>").
-- ignore_alpha 0.5 blurs behind the 0.88-0.94 alpha islands and cards but not
-- behind their soft edges. The wallpaper layer is opaque and left out.
hl.layer_rule(
    {
        name = "simplychit-surfaces",
        match = { namespace = "simplychit-(bar|launcher|clipboard|emoji|calendar|control|notifications|battery|osd|wallpaper|notepad|qr|privacy|media)" },
        blur = true,
        ignore_alpha = 0.5,
    }
)

-- The full-screen menus: the whole scrim is frosted.
hl.layer_rule(
    {
        name = "simplychit-scrims",
        match = { namespace = "simplychit-(powermenu|screenshot|keybinds|polkit|lock-preview)" },
        blur = true,
        ignore_alpha = 0.1,
    }
)
