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

-- Games on work 4
hl.window_rule({
    name = "steam",
    match = {
        class = "^(?i)steam_app_.*"
    },
    fullscreen = true,
    workspace = "4",
})

hl.window_rule({
    name = "minecraft",
    match = {
        class = "^Minecraft.*"
    },
    tile = true,
    workspace = "4",
})

hl.layer_rule(
    {
        name = "fabric",
        match = { namespace = "fabric*" },
        blur = false,
        ignore_alpha = 0,
    }
)
