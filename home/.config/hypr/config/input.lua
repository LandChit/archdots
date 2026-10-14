hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = true,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
        },

        numlock_by_default = true,
    }
})


hl.device({
    name = "elan0788:00-04f3:321a-touchpad",
    sensitivity = -0.1,
})

hl.device({
    name = "logitech-g304-1",
    sensitivity = -0.5,
})


-- From ~/.config/archdots/settings.json ("input"), set by the settings app's
-- Input page. Only these keys, and only with the right type: a typo there must
-- never stop the config loading.
local settings = require("config.helpers.settings")
local known = {
    kb_layout = "string", kb_variant = "string", kb_options = "string", kb_model = "string",
    follow_mouse = "number", sensitivity = "number", accel_profile = "string",
    numlock_by_default = "boolean",
}
local known_touchpad = {
    natural_scroll = "boolean", tap_to_click = "boolean", disable_while_typing = "boolean",
    scroll_factor = "number", clickfinger_behavior = "boolean", drag_lock = "boolean",
}
local user = settings.get("input", {})
local input, touchpad = {}, {}
for key, kind in pairs(known) do
    if type(user[key]) == kind then
        input[key] = user[key]
    end
end
for key, kind in pairs(known_touchpad) do
    if type(user.touchpad) == "table" and type(user.touchpad[key]) == kind then
        touchpad[key] = user.touchpad[key]
    end
end
if next(touchpad) then
    input.touchpad = touchpad
end
if next(input) then
    hl.config({ input = input })
end
