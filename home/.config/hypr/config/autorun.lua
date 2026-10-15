local shell = require("config.helpers.shell")

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/pam_kwallet_init --no-startup-id")
    hl.exec_cmd("sleep 5; kwalletmanager5", { workspace = "99", no_initial_focus = true, })
    hl.exec_cmd("sleep 5; killall kwalletmanager5")

    -- The shell draws the wallpaper, the bar and every panel, and is the
    -- notification daemon and the polkit agent.
    shell.restart()

    hl.exec_cmd("hypridle &") -- locks before sleep; the idle timeouts are the shell's
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- One polkit agent per session, first to register wins. The shell's is the
    -- one meant to; if it has not registered a few seconds in (shell not
    -- running, or broken), hyprpolkitagent takes the job so authentication
    -- always has somewhere to go.
    hl.exec_cmd("sleep 8; " .. shell.ipc("polkit", "registered")
        .. " 2>/dev/null | grep -qx true || systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("xwaylandvideobridge &")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("solaar --window=hide")
    -- Through $HOME and the stowed path, not the repo: the clone is not always
    -- at ~/simplychit, and this file has no business knowing where it is.
    hl.exec_cmd("sh $HOME/.config/hypr/Scripts/fix_dolphin.sh")
end)
