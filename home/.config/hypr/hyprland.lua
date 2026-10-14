-- All config are in their own files
local modules = {
    "environment",
    "monitor",
    "rules",
    "theme",
    "keybind",
    "input",
    "animation",
    "autorun",
}

for _, module in ipairs(modules) do
    require("config." .. module)
end

-- Your overrides.
--
-- Every module above can have a twin in ~/.config/simplychit/hypr/, loaded here
-- after all the defaults, so whatever it sets wins. Those files are yours: not
-- tracked, never written by updates. The configs above stay the committed
-- defaults, and each machine adjusts only what differs (monitor layout, GPU
-- env, input device names, keybinds, ...). See CUSTOMIZING.md.
--
-- config/custom/ is the old location. It is still read, first, so a machine
-- set up before the move keeps working; the new folder wins where both set
-- something.
local home = os.getenv("HOME")
local override_dirs = {
    { dir = home .. "/.config/hypr/config/custom/", label = "config/custom/" },
    { dir = home .. "/.config/simplychit/hypr/", label = "~/.config/simplychit/hypr/" },
}
local error_log = home .. "/.cache/hypr-custom.log"

local function quote(text)
    -- single-quote for sh, escaping any embedded quote the hard way
    return "'" .. (tostring(text):gsub("'", "'\\''")) .. "'"
end

local function report(file, err)
    -- Never take the session down over an override, and never hide the failure
    -- either. io.stderr from here does not reach Hyprland's log (checked), so
    -- write somewhere durable and raise a notification for the reload case.
    local message = file .. ": " .. (tostring(err):gsub("%s+", " "))

    local log = io.open(error_log, "a")
    if log then
        log:write(os.date("%Y-%m-%d %H:%M:%S ") .. message .. "\n")
        log:close()
    end

    hl.exec_cmd("notify-send -u critical 'Hyprland override failed' " ..
        quote(message))
end

for _, module in ipairs(modules) do
    for _, override in ipairs(override_dirs) do
        local path = override.dir .. module .. ".lua"
        local file = override.label .. module .. ".lua"

        -- loadfile, not require: Hyprland's require does NOT raise on a broken
        -- module — it returns a table and reports success, so pcall(require, ...)
        -- can never notice a syntax error. loadfile returns nil + message instead,
        -- and running the chunk under pcall catches runtime errors too. A missing
        -- file is not an error: it just means this machine needs no overrides.
        local chunk, load_err = loadfile(path)

        if chunk then
            local ok, run_err = pcall(chunk)
            if not ok then
                report(file, run_err)
            end
        else
            local exists = io.open(path, "r")
            if exists then
                exists:close()
                report(file, load_err) -- the file is there but will not compile
            end
        end
    end
end
