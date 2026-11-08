-- Beyond Performance preferences. Data only: never execute configuration text.
local S = {}

local function copy(values)
    local out = {}
    for key, value in pairs(values or {}) do out[key] = value end
    return out
end

local function trim(value) return value:match('^%s*(.-)%s*$') end

local function checked(value, default, rule)
    rule = rule or {}
    local kind = rule.type or type(default)
    if kind == 'boolean' then
        if type(value) == 'boolean' then return value end
        value = tostring(value):lower()
        if value == 'true' or value == '1' or value == 'on' then return true end
        if value == 'false' or value == '0' or value == 'off' then return false end
        return nil
    elseif kind == 'number' then
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
        if rule.min and n < rule.min or rule.max and n > rule.max then return nil end
        if rule.integer and n % 1 ~= 0 then return nil end
        return n
    elseif kind == 'string' then
        local text = tostring(value)
        if #text > (rule.maxLength or 128) or text:find('[\r\n]') then return nil end
        if rule.values then
            for _, allowed in ipairs(rule.values) do if text == allowed then return text end end
            return nil
        end
        return text
    end
end

function S.parse(text, defaults, schema)
    local values, notes = copy(defaults), {}
    if type(text) ~= 'string' then return values, {'No settings text; defaults used.'} end
    if #text > 65536 then return values, {'Settings file exceeds 64 KiB; defaults used.'} end
    text = text:gsub('^\239\187\191', '')
    local lineNumber = 0
    for rawLine in (text .. '\n'):gmatch('(.-)\n') do
        lineNumber = lineNumber + 1
        local line = trim(rawLine)
        if line ~= '' and not line:match('^[#;]') and not line:match('^%[.-%]$') then
            local key, raw = line:match('^([%w_]+)%s*=%s*(.-)%s*$')
            if key and defaults[key] ~= nil then
                local result = checked(raw, defaults[key], schema and schema[key])
                if result ~= nil then values[key] = result
                else notes[#notes + 1] = ('Invalid value for %s on line %d; kept prior/default.'):format(key, lineNumber) end
            elseif not key then
                notes[#notes + 1] = ('Ignored malformed settings line %d.'):format(lineNumber)
            end
        end
    end
    return values, notes
end

function S.encode(values, defaults, schema)
    local keys, lines = {}, {'; Beyond Performance 1.0 preferences', '; Changes in the F10 menu are saved here.', '[BeyondPerformance]'}
    defaults = defaults or values
    for key in pairs(defaults) do
        if not key:match('^[%w_]+$') then return nil, 'Invalid setting name.' end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local result = checked(values[key], defaults[key], schema and schema[key])
        if result == nil then return nil, 'Invalid value for ' .. key end
        lines[#lines + 1] = key .. '=' .. tostring(result)
    end
    return table.concat(lines, '\n') .. '\n'
end

function S.load(path, defaults, schema)
    local file = io.open(path, 'rb')
    local recovered = false
    if not file then
        -- An interrupted Windows replacement may have moved the old file to
        -- .bak before committing the complete temporary file.
        file = io.open(path .. '.bak', 'rb')
        recovered = file ~= nil
    end
    if not file then return copy(defaults), {} end
    local size = file:seek('end')
    if not size or size > 65536 then file:close(); return copy(defaults), {'Settings file is too large or unreadable; defaults used.'} end
    file:seek('set', 0)
    local data = file:read('*a')
    file:close()
    local values, notes = S.parse(data, defaults, schema)
    if recovered then notes[#notes + 1] = 'Recovered preferences from an interrupted save backup.' end
    return values, notes
end

function S.save(path, values, defaults, schema)
    local encoded, why = S.encode(values, defaults, schema)
    if not encoded then return false, why end
    local temp, backup = path .. '.tmp', path .. '.bak'
    local file, err = io.open(temp, 'wb')
    if not file then return false, 'Cannot save preferences: ' .. tostring(err) end
    local wrote, writeErr = file:write(encoded)
    local flushed, flushErr = file:flush()
    local closed, closeErr = file:close()
    if not wrote or not flushed or not closed then
        os.remove(temp)
        return false, 'Cannot write preferences: ' .. tostring(writeErr or flushErr or closeErr)
    end
    -- Windows does not replace an existing file with os.rename. Keep the old
    -- version until the new file is complete, and restore it if commit fails.
    local prior = io.open(path, 'rb')
    local hadPrior = prior ~= nil
    if prior then prior:close() end
    if hadPrior then
        os.remove(backup)
        local moved, moveErr = os.rename(path, backup)
        if not moved then os.remove(temp); return false, 'Cannot replace preferences: ' .. tostring(moveErr) end
    end
    local committed, commitErr = os.rename(temp, path)
    if not committed then
        if hadPrior then os.rename(backup, path) end
        os.remove(temp)
        return false, 'Cannot commit preferences: ' .. tostring(commitErr)
    end
    os.remove(backup)
    return true
end

return S
