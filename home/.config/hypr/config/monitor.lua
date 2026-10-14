local settings = require("config.helpers.settings")

-- Displays.
--
-- The settings app's Displays page saves a layout per set of connected
-- monitors in ~/.config/simplychit/settings.json ("displays.profiles"), keyed by
-- each monitor's description (make, model, serial) rather than its port name,
-- which changes between docks and cables. "displays.active" names the one in
-- use; the shell picks it when monitors are plugged in or out and applies it
-- live. When there is one, it is all that is applied here; the defaults below
-- are this repo owner's machine and only apply until a layout has been saved.
local profile = settings.get("displays.profiles", {})[settings.get("displays.active", "")]

if type(profile) == "table" and type(profile.monitors) == "table" then
    local keys = { mode = "string", position = "string", scale = "number", transform = "number", vrr = "number", mirror = "string" }
    for description, m in pairs(profile.monitors) do
        if type(m) == "table" then
            local spec = { output = "desc:" .. description }
            if m.enabled == false then
                spec.disabled = true
            else
                for key, kind in pairs(keys) do
                    if type(m[key]) == kind and m[key] ~= "" then
                        spec[key] = m[key]
                    end
                end
            end
            hl.monitor(spec)
        end
    end
    for workspace, description in pairs(type(profile.workspaces) == "table" and profile.workspaces or {}) do
        if type(description) == "string" then
            hl.workspace_rule({ workspace = tostring(workspace), monitor = "desc:" .. description })
        end
    end
    return
end

-- ── defaults: this repo owner's laptop and monitors ─────────────────────────
local laptopMonitor = "eDP-1"
local externalMonitors = { "HDMI-A-1", "DP-1" }
local mon = externalMonitors[1]

hl.monitor({
    output = laptopMonitor,
    mode = "1920x1080@144",
    position = "1080x0",
    scale = 1.0,

})


hl.monitor({
    output = "HDMI-A-1",
    mode = "1920x1080@60",
    position = "3000x-530",
    scale = 1.0,
    transform = 3
})

hl.monitor({
    output = "DP-1",
    mode = "1920x1080@60",
    position = "0x200",
    scale = 1.0,
    transform = 1
})



-- WORKSPACE RULES
for workspace = 1, 10, 1 do
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
