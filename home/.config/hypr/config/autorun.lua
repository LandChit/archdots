local shell = require("config.helpers.shell")

hl.on("hyprland.start", function()
    -- Hands the password pam_kwallet5 kept at login to kwalletd, which
    -- unlocks kdewallet. Plasma runs this from /etc/xdg/autostart.
    hl.exec_cmd("/usr/lib/pam_kwallet_init")

    -- The shell draws the wallpaper, the bar and every panel, and is the
    -- notification daemon and the polkit agent.
    shell.restart()

    hl.exec_cmd("hypridle &") -- locks before sleep; the idle timeouts are the shell's
    -- Apps asking to stay awake (a video playing), over D-Bus or logind, for
    -- the shell's idle timers. D-Bus starts it on the first request too; this
    -- start is for logind inhibitors taken before any app has asked.
    hl.exec_cmd("$HOME/.local/bin/simplychit inhibitors")
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
