# custom/ — old location for Hyprland overrides

Overrides now go in **`~/.config/archdots/hypr/`**, the one folder for
everything you edit. See [CUSTOMIZING.md](../../../../../CUSTOMIZING.md) at
the repo root.

Files here (`monitor.lua`, `keybind.lua`, …) are still loaded, before the ones
in `~/.config/archdots/hypr/`, so a machine set up before the move keeps
working. To move, copy each file across and delete it here. The `.lua` files
are gitignored; this README is tracked so the folder exists in a clone.

One thing this folder's old docs got wrong: re-binding a combo does not
replace the default, it adds a second bind and both fire. Use
`config/helpers/bind.lua` (`bind.rebind`, `bind.remove`).
