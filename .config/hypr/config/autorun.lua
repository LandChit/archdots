local shell = require("config.helpers.shell")

hl.on("hyprland.start", function()
    hl.exec_cmd("kwalletmanager5", { workspace = "99", no_initial_focus = true, })
    hl.exec_cmd("sleep 1; /usr/lib/pam_kwallet_init --no-startup-id")
    hl.exec_cmd("sleep 5; killall kwalletmanager5")

    shell.restart()


    hl.exec_cmd("hyprpaper &")
    hl.exec_cmd("hypridle &")   -- dim, lock, screens off, suspend: see ../hypridle.conf
    -- The polkit agent is a systemd user unit that install.sh enables. Starting
    -- it here as well covers a session that never reaches graphical-session.target,
    -- and it has to come after the import: the unit needs WAYLAND_DISPLAY.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
        .. " && systemctl --user start hyprpolkitagent.service")
    hl.exec_cmd("xwaylandvideobridge &")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("solaar --window=hide")
    -- Through $HOME and the stowed path, not the repo: the clone is not always
    -- at ~/archdots, and this file has no business knowing where it is.
    hl.exec_cmd("sh $HOME/.config/hypr/Scripts/fix_dolphin.sh")
end)
