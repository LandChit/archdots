-- Changing a default keybind from an override file.
--
-- Binding a combo that is already bound does NOT replace it: Hyprland keeps
-- both binds and fires both actions (checked with `hyprctl binds -j`).
-- hl.unbind(combo) removes every bind on a combo, so:
--
--   local bind = require("config.helpers.bind")
--   bind.remove("SUPER + B")                                  -- delete a default
--   bind.rebind("SUPER + E", hl.dsp.exec_cmd("nautilus"),     -- change one
--       { desc = "Launch: File manager" })
local M = {}

function M.remove(combo)
    hl.unbind(combo)
end

function M.rebind(combo, action, opts)
    hl.unbind(combo)
    return hl.bind(combo, action, opts)
end

return M
