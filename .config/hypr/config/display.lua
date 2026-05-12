local laptopMonitor = "eDP-1"
local externalMonitors = { "HDMI-A-1", "DP-1" }
local mon = externalMonitors[1]

-- function getValues(array)
--     local i = 0
--     return function()
--         i = i + 1; return array[i]
--     end
-- end

-- Monitor rules
hl.monitor({
    output = laptopMonitor,
    mode = "1920x1080@144",
    position = "1080x0",
    scale = 1.0,

})


hl.monitor({
    output = mon,
    mode = "1920x1080@60",
    position = (mon) == "HDMI-A-1" and "3000x200" or "0x200",
    scale = 1.0,
    transform = 1
})


-- Workspace rules

for workspace = 0, 9, 1 do
    if workspace % 2 == 0 then
        hl.workspace_rule({
            workspace = tostring(workspace),
            monitor = laptopMonitor,
        })
    else
        hl.workspace_rule({
            workspace = tostring(workspace),
            monitor = mon,
        })
    end
end

hl.workspace_rule({
    workspace = "2",
    default = true,
    persistent = true,
    monitor = laptopMonitor,
})

hl.workspace_rule({
    workspace = "1",
    monitor = mon,
    persistent = true,
    default = true,
})


-- QOL window rules
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
