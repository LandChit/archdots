-- A small JSON decoder, so the Hyprland config can read the same
-- ~/.config/simplychit/settings.json the shell and its settings app write.
-- Hyprland's Lua has no JSON of its own.
--
-- decode(text) returns the value, or raises an error naming the position.
-- Objects become tables, arrays become sequences (1-based), null becomes nil.
local M = {}

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 | (code >> 6), 0x80 | (code & 0x3F))
    elseif code < 0x10000 then
        return string.char(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
    end
    return string.char(0xF0 | (code >> 18), 0x80 | ((code >> 12) & 0x3F), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
end

local function fail(text, pos, what)
    local line = select(2, text:sub(1, pos):gsub("\n", "")) + 1
    error(("JSON: %s at line %d (character %d)"):format(what, line, pos), 0)
end

local function skip(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

local parse

local function parse_string(text, pos)
    local out, i = {}, pos + 1
    while true do
        local c = text:sub(i, i)
        if c == "" then
            fail(text, pos, "unterminated string")
        elseif c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local e = text:sub(i + 1, i + 1)
            if e == "u" then
                local hex = text:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then
                    fail(text, i, "bad \\u escape")
                end
                local code = tonumber(hex, 16)
                i = i + 6
                -- a surrogate pair is two \u escapes making one character
                if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == "\\u" then
                    local low = tonumber(text:sub(i + 2, i + 5), 16)
                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        i = i + 6
                    end
                end
                out[#out + 1] = utf8char(code)
            elseif escapes[e] then
                out[#out + 1] = escapes[e]
                i = i + 2
            else
                fail(text, i, "bad escape")
            end
        else
            local j = text:find('["\\]', i) or #text + 1
            out[#out + 1] = text:sub(i, j - 1)
            i = j
        end
    end
end

parse = function(text, pos)
    pos = skip(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then
        local obj = {}
        pos = skip(text, pos + 1)
        if text:sub(pos, pos) == "}" then
            return obj, pos + 1
        end
        while true do
            if text:sub(pos, pos) ~= '"' then
                fail(text, pos, "expected a key")
            end
            local key
            key, pos = parse_string(text, pos)
            pos = skip(text, pos)
            if text:sub(pos, pos) ~= ":" then
                fail(text, pos, "expected ':'")
            end
            obj[key], pos = parse(text, pos + 1)
            pos = skip(text, pos)
            local sep = text:sub(pos, pos)
            if sep == "}" then
                return obj, pos + 1
            elseif sep ~= "," then
                fail(text, pos, "expected ',' or '}'")
            end
            pos = skip(text, pos + 1)
        end
    elseif c == "[" then
        local arr, n = {}, 0
        pos = skip(text, pos + 1)
        if text:sub(pos, pos) == "]" then
            return arr, pos + 1
        end
        while true do
            n = n + 1
            arr[n], pos = parse(text, pos)
            pos = skip(text, pos)
            local sep = text:sub(pos, pos)
            if sep == "]" then
                return arr, pos + 1
            elseif sep ~= "," then
                fail(text, pos, "expected ',' or ']'")
            end
            pos = pos + 1
        end
    elseif c == '"' then
        return parse_string(text, pos)
    elseif text:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif text:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif text:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    end
    local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if num and num ~= "" and tonumber(num) then
        return tonumber(num), pos + #num
    end
    fail(text, pos, "unexpected '" .. (c == "" and "end of file" or c) .. "'")
end

function M.decode(text)
    local value, pos = parse(text, 1)
    if skip(text, pos) <= #text then
        fail(text, pos, "trailing characters")
    end
    return value
end

return M
