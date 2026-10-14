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
