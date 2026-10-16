-- Bibata Modern Classic (AUR, install.sh). No hyprcursor theme is set, so
-- Hyprland draws this XCursor theme, and so do apps that ask it to (Qt,
-- GTK 4) through the cursor-shape protocol.
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_SIZE", "20")


hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")


hl.env("XDG_MENU_PREFIX", "arch-")


hl.env("QT_QPA_PLATFORM", "wayland")

-- "qt5ct", not "qt6ct": Qt 5 and 6 read the same variable, and qt6ct's plugin
-- answers to both names, so Qt 6 apps still get qt6ct (qt6ct.conf) while
-- Qt 5 ones (VLC, sqlitebrowser) get qt5ct (qt5ct.conf) instead of plain
-- Fusion. Both draw with the same Kvantum theme.
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
