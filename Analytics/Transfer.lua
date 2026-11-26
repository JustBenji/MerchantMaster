local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
local Transfer = {}
ns.Transfer = Transfer

local function db()
    local store = ns.Store
    if not store then return nil end
    if not store.db and store.Init then store.Init() end
    return store.db
end

local function checksum(value)
    local n = 0
    for i = 1, #value do n = (n * 33 + value:byte(i)) % 4294967296 end
    return string.format("%08x", n)
end

local function secret(value)
    for _, name in ipairs({ "issecretvalue", "issecrettable" }) do
        local checker = _G[name]
        if type(checker) == "function" then
            local ok, result = pcall(checker, value)
            if not ok or result then return true end
        end
    end
    return false
end

local function safeText(value, fallback)
    if secret(value) then return fallback end
    if type(value) == "string" and #value <= 256 then return value end
    return fallback
end

local function field(value)
    value = tostring(value or "")
    return tostring(#value) .. ":" .. value
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[clone(key, seen)] = clone(child, seen) end
    return out
end

local function restoreTable(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
end

local function readField(payload, pos, maxLength)
    local colon = payload:find(":", pos, true)
    if not colon then return nil end
    local raw = payload:sub(pos, colon - 1)
    if raw == "" or not raw:match("^%d+$") or #raw > 10 then return nil end
    local size = tonumber(raw)
    if not size or size > maxLength then return nil end
    local first, last = colon + 1, colon + size
    if last > #payload then return nil end
    return payload:sub(first, last), last + 1
end

local function accountID(database)
    local stats = database.stats or {}
    database.stats = stats
    if type(stats.originID) == "string" and stats.originID ~= "" then return stats.originID end
    local now = 0
    if type(_G.time) == "function" then
        local ok, value = pcall(_G.time)
        if ok and not secret(value) and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then now = value end
    elseif os and type(os.time) == "function" then
        local ok, value = pcall(os.time)
        if ok and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then now = value end
    end
    local realm
    if type(_G.GetRealmName) == "function" then
        local ok, value = pcall(_G.GetRealmName)
        if ok then realm = safeText(value, nil) end
    end
    local seed = tostring(now) .. ":" .. tostring(realm or "realm")
    if type(_G.UnitGUID)=="function" then
        local ok,value=pcall(_G.UnitGUID,"player")
        if ok then local guid=safeText(value,nil); if guid then seed=seed..":"..guid end end
    end
    local randomFn=_G.random or (math and math.random)
    if randomFn then
        local ok, random = pcall(randomFn, 1, 2147483646)
        if ok and not secret(random) and type(random) == "number" and random == random and random ~= math.huge and random ~= -math.huge then seed = seed .. ":" .. tostring(random) end
    end
    seed=seed..":"..tostring(database)
    stats.originID = checksum(seed) .. checksum(seed:reverse())
    return stats.originID
end

function Transfer.ExportBundle(filters)
    local store, database = ns.Store, db()
    if not store or not database or store.readOnly then return nil, "store unavailable" end
    local rows
    if store.SelectRows then
        rows = store.SelectRows(filters or {})
    else
        rows = {}
        store.IterDays((filters and filters.from) or "0000-00-00", (filters and filters.to) or "9999-99-99", function(day, dayRows)
            for index, row in ipairs(dayRows or {}) do
                local ok = not filters or not filters.char or row.char == filters.char
                if ok and filters and filters.type then ok = row.type == filters.type end
                if ok then
                    local copy = {}
                    for key, value in pairs(row) do copy[key] = value end
                    rows[#rows + 1] = { row = copy, day = day, index = index }
                end
            end
        end)
        for i, item in ipairs(rows) do rows[i] = item.row end
    end
    if type(rows) ~= "table" then return nil, "row selection failed" end
    local ordered = {}
    for i, row in ipairs(rows) do ordered[i] = { row = row, index = i } end
    table.sort(ordered, function(a, b)
        local at, bt = tonumber(a.row.time) or 0, tonumber(b.row.time) or 0
        if at ~= bt then return at < bt end
        local ao = tonumber(a.row.extra and a.row.extra.replayOrder)
        local bo = tonumber(b.row.extra and b.row.extra.replayOrder)
        if ao and bo and ao ~= bo then return ao < bo end
        return a.index < b.index
    end)
    rows = {}
    for i, entry in ipairs(ordered) do rows[i] = entry.row end
    if type(store.PackRows) ~= "function" then return nil, "row packing unavailable" end
    local ok, packed = pcall(store.PackRows, rows)
    if not ok or type(packed) ~= "string" or packed:sub(1, 4) ~= "MM1:" then return nil, "row packing failed" end
    local origin = accountID(database)
    local origins = {}
    for i, row in ipairs(rows) do
        local eid = row.eid or (row.extra and row.extra.eid) or (store.EventID and store.EventID(row)) or (tostring(store.DayKey(row.time)) .. ":" .. tostring(i))
        origins[i] = (row.extra and row.extra.originID) or (origin .. "/" .. tostring(row.char or "") .. "/" .. tostring(eid))
        database.stats.importedOrigins[origins[i]]=true
    end
    local body = field(origin) .. tostring(#rows) .. ":"
    for _, id in ipairs(origins) do body = body .. field(id) end
    body = body .. field(packed)
    return "MMX1:" .. checksum(body) .. ":" .. #body .. ":" .. body
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validatePacked(packed, expectedRows)
    local count, extras, pos = packed:match("^MM1:(%d+):(%d+):()")
    count, extras = tonumber(count), tonumber(extras)
    if not count or not extras or count ~= expectedRows or count > 100000 or extras > 1024 then return false end
    local function scalar()
        local kind, value, nextPos = packed:match("^([snzft])([^:]*):()", pos)
        if not kind then return false end
        pos = nextPos
        if kind == "s" then
            if not value:match("^%d+$") or #value > 10 then return false end
            local size = tonumber(value)
            if not size or size > #packed or pos + size - 1 > #packed then return false end
            pos = pos + size
        elseif kind == "n" then
            local number = tonumber(value)
            if not finite(number) then return false end
        elseif kind == "z" and value ~= "" then return false end
        return true
    end
    for _ = 1, extras do if not scalar() then return false end end
    local columns = 11 + extras
    for column = 1, columns do
        local mode = packed:sub(pos, pos)
        if mode == "" then return false end
        pos = pos + 1
        if mode == "c" then
            if not scalar() then return false end
        elseif mode == "v" then
            for _ = 1, count do if not scalar() then return false end end
        elseif mode == "s" then
            for _ = 1, count do
                local size, start = packed:match("^(%d+):()", pos)
                if not size or #size > 10 then return false end
                size = tonumber(size)
                if not size or size > #packed or start + size - 1 > #packed then return false end
                pos = start + size
            end
        elseif mode == "n" then
            local finish = packed:find(":", pos, true)
            if not finish then return false end
            local values = packed:sub(pos, finish - 1)
            local seen = 0
            for token in values:gmatch("([^,]+),") do
                local number = tonumber(token)
                if not finite(number) then return false end
                seen = seen + 1
            end
            if seen ~= count or values:sub(-1) ~= "," then return false end
            pos = finish + 1
        else
            return false
        end
    end
    return pos == #packed + 1
end

function Transfer.Import(payload)
    local store, database = ns.Store, db()
    if not store or not database then return { ok = false, err = "store unavailable" } end
    if store.readOnly then return { ok = false, err = "store is read-only" } end
    if type(payload) ~= "string" or #payload > 16777216 then return { ok = false, err = "invalid payload" } end
    local digest, length, start = payload:match("^MMX1:([%da-fA-F]+):(%d+):()")
    length = tonumber(length)
    if not digest or #digest ~= 8 or not length or length > 16777180 or start + length - 1 ~= #payload then
        return { ok = false, err = "malformed or truncated payload" }
    end
    local body = payload:sub(start)
    if checksum(body) ~= digest:lower() then return { ok = false, err = "checksum mismatch" } end
    local pos = 1
    local origin; origin, pos = readField(body, pos, 256)
    local countEnd = body:find(":", pos, true)
    if not origin or not countEnd then return { ok = false, err = "invalid bundle header" } end
    local rawCount = body:sub(pos, countEnd - 1)
    local count = tonumber(rawCount)
    if rawCount == "" or not rawCount:match("^%d+$") or not count or count > 100000 then
        return { ok = false, err = "invalid row count" }
    end
    pos = countEnd + 1
    local origins = {}
    for i = 1, count do
        origins[i], pos = readField(body, pos, 1024)
        if not origins[i] or origins[i] == "" then return { ok = false, err = "invalid event identity" } end
    end
    local packed; packed, pos = readField(body, pos, 16777216)
    if not packed or pos ~= #body + 1 or packed:sub(1, 4) ~= "MM1:" then return { ok = false, err = "invalid row data" } end
    if not validatePacked(packed, count) then return { ok = false, err = "invalid packed structure" } end
    local ok, rows = pcall(store.UnpackDayString, packed)
    if not ok or type(rows) ~= "table" or #rows ~= count then return { ok = false, err = "invalid packed rows" } end
    for i, row in ipairs(rows) do
        if type(row) ~= "table" or type(row.type) ~= "string" or not store.TYPES[row.type]
            or type(row.char) ~= "string" or row.char == "" or type(row.econ) ~= "string"
            or not finite(row.time) or row.time < 0 or row.time > 4102444800
            or not finite(row.total) or not finite(row.itemID) or row.itemID < 0 or row.itemID ~= math.floor(row.itemID)
            or not finite(row.qty) or row.qty < 0 or row.qty ~= math.floor(row.qty)
            or not finite(row.unit) or (row.cogs ~= nil and not finite(row.cogs)) then
            return { ok = false, err = "invalid event row" }
        end
        row.extra = type(row.extra) == "table" and row.extra or {}
        for key, value in pairs(row.extra) do
            if (type(key) ~= "string" and type(key) ~= "number") or (type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean")
                or (type(value) == "number" and not finite(value)) then return { ok = false, err = "unsupported event metadata" } end
        end
    end
    local importedOrigins = database.stats.importedOrigins
    if type(importedOrigins) ~= "table" then importedOrigins = {} end
    local currentOrigins = {}
    local origin = database.stats.originID
    local originPrefix = type(origin) == "string" and origin ~= "" and (origin .. "/") or nil
    local iterOk = pcall(store.IterDays, "0000-00-00", "9999-99-99", function(day, dayRows)
        for index, row in ipairs(dayRows or {}) do
            local eid = row.eid or (row.extra and row.extra.eid)
                or (store.EventID and store.EventID(row, day, index)) or (tostring(day) .. ":" .. tostring(index))
            local id = row.extra and row.extra.originID or (originPrefix and (originPrefix .. tostring(row.char or "") .. "/" .. tostring(eid)))
            if id then currentOrigins[id] = true end
        end
    end)
    if not iterOk then
        return { ok = false, err = "existing rows unavailable" }
    end
    local pending, skipped, pendingIDs = {}, 0, {}
    for i, row in ipairs(rows) do
        local id = origins[i]
        if importedOrigins[id] or currentOrigins[id] or pendingIDs[id] then skipped = skipped + 1
        else pendingIDs[id] = true; pending[#pending + 1] = { id = id, row = row, sequence = i } end
    end
    local prunedBefore = database.prunedBefore
    if prunedBefore then
        for _, entry in ipairs(pending) do
            if store.DayKey(entry.row.time) < prunedBefore then
                return { ok = false, err = "bundle contains transactions before pruned retention cutoff (" .. prunedBefore .. ")", imported = 0, skipped = skipped }
            end
        end
    end
    local dbSnapshot = clone(database)
    local versionSnapshot, accVerSnapshot, salesVerSnapshot, yieldVerSnapshot, trackedVerSnapshot, appendFlagSnapshot, onChangeSnapshot =
        store.version, store.accountingVersion, store.ahSalesVersion, store.craftYieldVersion, store._trackedAccountingVersion, store._appending, store.onChange
    database.stats.importedOrigins = importedOrigins
    table.sort(pending, function(a, b)
        if a.row.time ~= b.row.time then return a.row.time < b.row.time end
        return a.sequence < b.sequence
    end)
    local imported = 0
    local inserted = {}
    local function rollback(err)
        restoreTable(database, dbSnapshot)
        _G.MerchantMasterLedgerDB = database
        store.db = database
        store.version, store.accountingVersion, store.ahSalesVersion, store.craftYieldVersion, store._trackedAccountingVersion, store._appending, store.onChange =
            versionSnapshot, accVerSnapshot, salesVerSnapshot, yieldVerSnapshot, trackedVerSnapshot, appendFlagSnapshot, onChangeSnapshot
        return { ok = false, err = err, imported = 0, skipped = skipped }
    end
    store.onChange=nil
    for _, entry in ipairs(pending) do
        entry.row.extra.originID = entry.id
        entry.row.extra.imported = true
        entry.row.extra.eid = nil
        entry.row.extra.replayOrder = nil
        entry.row.extra.recomputeCost = true
        entry.row.skipRecon = true
        local callOk, appended = pcall(store.Append, entry.row)
        if not callOk or not appended then
            return rollback("append failed")
        end
        inserted[#inserted + 1] = entry.id
        imported = imported + 1
    end
    if imported > 0 then
        if type(store.Rebuild) ~= "function" then
            return rollback("chronological rebuild unavailable")
        end
        local callOk, rebuildResult = pcall(store.Rebuild)
        if not callOk or rebuildResult == false or (type(rebuildResult) == "table" and rebuildResult.ok == false) then
            return rollback("chronological rebuild failed")
        end
        for _, id in ipairs(inserted) do importedOrigins[id] = true end
    end
    store.onChange=onChangeSnapshot
    if imported>0 and onChangeSnapshot then pcall(onChangeSnapshot) end
    return { ok = true, imported = imported, skipped = skipped }
end

