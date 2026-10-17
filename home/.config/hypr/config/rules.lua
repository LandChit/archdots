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



-- Games open in their own scratchpad, special:games (SUPER+G shows or hides
-- it), whatever workspace their launcher is on: the game shows over it, and
-- hiding it leaves the game running. Launchers (Steam, Prism) are not
-- matched and stay where they open. A game ruled there shows the scratchpad
-- on the focused screen by itself, and it closes when the last game exits.
steam_games = "^(?i)steam_app_.*"

hl.window_rule({
    name = "steam",
    match = {
        class = steam_games
    },
    fullscreen = true,
    workspace = "special:games",
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
    workspace = "special:games",
})

-- More games, from settings.json: "games": { "classes": ["^Albion Online$"] }.
-- Windows sent there by hand (SUPER+SHIFT+G) are noted in
-- ~/.config/simplychit/games-to-review.txt to pick these from.
local game_classes = require("config.helpers.settings").get("games.classes", {})
if type(game_classes) == "table" then
    for i, class in ipairs(game_classes) do
        if type(class) == "string" and class ~= "" then
            hl.window_rule({
                name = "game-" .. i,
                match = { class = class },
                fullscreen = true,
                workspace = "special:games",
            })
        end
    end
end

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
