-- Container-only input override for `runscript.sh --ui`.
--
-- Copied to ~/.config/hypr/config/custom/input.lua inside the test container.
-- NOT part of the repo: custom/*.lua is gitignored precisely so a machine — or
-- a container — can adjust what it needs without touching the committed
-- defaults.
--
-- The problem: in a nested session the HOST compositor sees every SUPER
-- combination first and acts on it, so none of the real binds ever reach the
-- nested Hyprland. Pressing SUPER + SPACE opens the launcher on the host.
--
-- The fix: make Caps Lock an *additional Super* inside the nested session only.
-- The host has no bind on Caps, so it forwards the key through; xkb then turns
-- it into Super before Hyprland sees it. Every one of the 64 real keybinds then
-- works exactly as documented, just pressed with Caps instead of Super — so
-- what gets tested is the actual config, not a set of harness duplicates.
--
-- `caps:super` is a stock xkb option ("Make Caps Lock an additional Super"), so
-- Caps stops latching capitals as a side effect. That matters: a leader key
-- that also toggles Caps Lock would make everything typed into the launcher
-- come out uppercase.
--
-- kb_layout is restated because hl.config replaces the input table wholesale.

hl.config({
    input = {
        kb_layout = "us",
        kb_options = "caps:super",
        follow_mouse = true,
        sensitivity = 0,
        numlock_by_default = true,
    },
})
