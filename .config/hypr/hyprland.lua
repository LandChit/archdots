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

-- Machine-specific overrides.
--
-- Every module above has a twin in config/custom/ which is loaded here, after
-- all the defaults, so whatever it sets wins. Those files are untracked: the
-- configs above stay the committed defaults, and each machine adjusts only what
-- differs (monitor layout, GPU env, input device names, ...).
-- See config/custom/README.md.
local custom = os.getenv("HOME") .. "/.config/hypr/config/custom/"
local error_log = os.getenv("HOME") .. "/.cache/hypr-custom.log"

local function quote(text)
    -- single-quote for sh, escaping any embedded quote the hard way
    return "'" .. (tostring(text):gsub("'", "'\\''")) .. "'"
end

local function report(module, err)
    -- Never take the session down over an override, and never hide the failure
    -- either. io.stderr from here does not reach Hyprland's log (checked), so
    -- write somewhere durable and raise a notification for the reload case.
    local message = "custom/" .. module .. ".lua: " ..
        (tostring(err):gsub("%s+", " "))

    local log = io.open(error_log, "a")
    if log then
        log:write(os.date("%Y-%m-%d %H:%M:%S ") .. message .. "\n")
        log:close()
    end

    hl.exec_cmd("notify-send -u critical 'Hyprland override failed' " ..
        quote(message))
end

for _, module in ipairs(modules) do
    local path = custom .. module .. ".lua"

    -- loadfile, not require: Hyprland's require does NOT raise on a broken
    -- module — it returns a table and reports success, so pcall(require, ...)
    -- can never notice a syntax error. loadfile returns nil + message instead,
    -- and running the chunk under pcall catches runtime errors too. A missing
    -- file is not an error: it just means this machine needs no overrides.
    local chunk, load_err = loadfile(path)

    if chunk then
        local ok, run_err = pcall(chunk)
        if not ok then
            report(module, run_err)
        end
    else
        local exists = io.open(path, "r")
        if exists then
            exists:close()
            report(module, load_err) -- the file is there but will not compile
        end
    end
end
