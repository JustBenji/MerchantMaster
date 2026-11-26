-- Best-effort identities are separate from prices, which browse refresh replaces.
local ADDON, ns = ...
local SellerStats = {}
ns.SellerStats = SellerStats
-- Read-only missing-data result avoids per-recipe allocations during cold builds.
local UNAVAILABLE = {status="unavailable", display="n/a", scope="Item variants", reason="No readable item seller search is available."}

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function number(value, signed)
    return readable(value) and type(value) == "number" and value == value and value < math.huge
        and value > -math.huge and (signed or value >= 0) and value or nil
end
local function text(value)
    if not readable(value) or type(value) ~= "string" then return nil end
    return value:match("^%s*(.-)%s*$")
end

function SellerStats.Key(key)
    if not readable(key) or type(key) ~= "table" then return nil end
    local copy = {}
    for _, field in ipairs({"itemID", "itemLevel", "itemSuffix", "battlePetSpeciesID"}) do
        local value = key[field]
        if readable(value) and value == nil and field ~= "itemID" then value = 0 end
        value = number(value, field == "itemSuffix")
        if not value or value ~= math.floor(value) then return nil end
        copy[field] = value
    end
    if copy.itemID == 0 then return nil end
    return string.format("%d:%d:%d:%d", copy.itemID, copy.itemLevel, copy.itemSuffix, copy.battlePetSpeciesID), copy
end

local function bank(economy, create)
    economy = text(economy)
    if not economy or economy == "" or type(MerchantMasterDB) ~= "table" then return nil end
    if create then
        MerchantMasterDB.sellerStats = MerchantMasterDB.sellerStats or {}
        MerchantMasterDB.sellerStats[economy] = MerchantMasterDB.sellerStats[economy] or {keys={}, coverage={}, incompleteItems={}}
        MerchantMasterDB.sellerStats[economy].incompleteItems = MerchantMasterDB.sellerStats[economy].incompleteItems or {}
    end
    local saved = MerchantMasterDB.sellerStats and MerchantMasterDB.sellerStats[economy]
    if saved and not saved.items then
        saved.items = {}
        for signature, record in pairs(saved.keys) do
            local id = record.key.itemID
            saved.items[id] = saved.items[id] or {}
            saved.items[id][signature] = true
        end
    end
    return saved
end

local function unknown(value)
    local lower = value:lower()
    if lower == "?" or lower == "unknown" or lower == "unknownobject" or lower == "retrieving data" then return true end
    for _, label in ipairs({"UNKNOWN", "UNKNOWNOBJECT", "RETRIEVING_DATA"}) do
        local unknown = text(_G[label])
        if unknown and lower == unknown:lower() then return true end
    end
end

local function identity(value)
    value = text(value)
    if not value or value == "" or unknown(value) then return nil end
    local lower = value:lower()
    if lower == "player" then
        local name, realm
        if ns.GetPlayerFullName then
            name = ns.GetPlayerFullName()
            if UnitFullName then
                local _, r = UnitFullName("player")
                realm = r
            end
        elseif UnitFullName then
            name, realm = UnitFullName("player")
        elseif UnitName then
            name, realm = UnitName("player")
        end
        name, realm = text(name), text(realm)
        if not name or name == "" then return nil end
        value = name .. (realm and realm ~= "" and ("-" .. realm) or "")
    end
    local name, realm = value:match("^([^%-]+)%-(.+)$")
    if not name then
        name = value
        realm = GetNormalizedRealmName and text(GetNormalizedRealmName()) or GetRealmName and text(GetRealmName())
    end
    name, realm = text(name), text(realm)
    if name then name = name:match("^%s*(.-)%s*$") end
    if not name or name == "" or unknown(name) or not realm or realm == "" then return nil end
    if name:find("[%p%d]") or name:find("%s%s") then return nil end
    return name:lower() .. "-" .. realm:gsub("%s", ""):lower()
end

function SellerStats.Begin(key, economy)
    local signature, copy = SellerStats.Key(key)
    if not signature then return nil end
    return {signature=signature, key=copy, economy=economy, names={}, observed=false, complete=false}
end

function SellerStats.Observe(observation, rows, full, hasSupply)
    if not observation then return end
    observation.names, observation.observed = {}, true
    observation.hasSupply = observation.hasSupply or hasSupply
    local exposed = true
    for _, row in ipairs(rows) do
        local owners = readable(row) and type(row) == "table" and row.owners
        local total = readable(row) and type(row) == "table" and number(row.totalNumberOfOwners)
        local bucket, count = {}, 0
        if readable(owners) and type(owners) == "table" then
            for _, owner in pairs(owners) do
                local name = identity(owner)
                if name then
                    if not bucket[name] then bucket[name], count = true, count + 1 end
                    observation.names[name] = true
                else exposed = false end
            end
        else exposed = false end
        if not total or total < 1 or count ~= total then exposed = false end
        if readable(row) and type(row) == "table" then
            if not readable(row.containsOwnerItem) then exposed = false
            elseif row.containsOwnerItem then
                local player = identity("player")
                if not player or not bucket[player] then exposed = false end
            end
        end
    end
    observation.complete = readable(full) and full == true and exposed
    local saved = observation.complete and bank(observation.economy)
    observation.browseDiscovery = saved and saved.pendingBrowse and saved.pendingBrowse[observation.signature]
    observation.reason = not exposed and "Some auction owner identities are hidden or truncated."
        or "Item search paging is incomplete."
end

function SellerStats.Publish(observation, reason)
    if not observation then return end
    local saved = bank(observation.economy, true)
    if not saved then return end
    local names, count = {}, 0
    for name in pairs(observation.names) do names[name], count = true, count + 1 end
    local complete = observation.complete and not reason and observation.observed
    if complete and saved.pendingBrowse and saved.pendingBrowse[observation.signature] == observation.browseDiscovery then
        saved.pendingBrowse[observation.signature] = nil
    end
    local coverage = saved.coverage[observation.key.itemID]
    if observation.hasSupply and coverage and not coverage[observation.signature] then
        coverage[observation.signature] = observation.key
        saved.incompleteItems[observation.key.itemID] = true
    end
    saved.keys[observation.signature] = {
        key=observation.key, names=names, count=count, at=time(),
        status=complete and "complete" or count > 0 and "partial" or "unavailable",
        reason=reason or observation.reason, scope="Item variant",
    }
    local id = observation.key.itemID
    saved.items[id] = saved.items[id] or {}
    saved.items[id][observation.signature] = true
    if ns.RecipeStats then ns.RecipeStats.Invalidate("sellers") end
end

function SellerStats.Commodity(key, economy)
    local observation = SellerStats.Begin(key, economy)
    SellerStats.Publish(observation, "Commodity seller identities are unavailable.")
end

local function mergeBrowseKey(coverage, signature, key)
    coverage[key.itemID] = coverage[key.itemID] or {}
    local variants = coverage[key.itemID]
    if variants[signature] then return false end
    variants[signature] = key
    return true
end

local function mergeBrowseKeys(coverage, keys)
    local changed = false
    for _, key in pairs(keys) do
        local signature, copy = SellerStats.Key(key)
        if signature and mergeBrowseKey(coverage, signature, copy) then changed = true end
    end
    return changed
end

local function markBrowsePending(saved, signature, activeVariant)
    local pending = saved.pendingBrowse and saved.pendingBrowse[signature]
    local record = saved.keys[signature]
    if activeVariant or pending or (record and record.status == "complete" and record.count == 0) then
        saved.pendingBrowse = saved.pendingBrowse or {}
        -- Give each discovery its own token so an older observation cannot clear it.
        saved.pendingBrowse[signature] = {}
        return true, not pending
    end
    return false, false
end

function SellerStats.MergeBrowseKeys(economy, keys, stockedKeys)
    local saved = bank(economy, true)
    if not saved then return end
    local changed = mergeBrowseKeys(saved.coverage, keys)
    for signature, activeVariant in pairs(stockedKeys or {}) do
        local _, isNew = markBrowsePending(saved, signature, activeVariant)
        if isNew then changed = true end
    end
    if changed and ns.RecipeStats then ns.RecipeStats.Invalidate("sellers") end
end

function SellerStats.NoteBrowseSupply(economy, stockedKeys, scanKeys)
    local saved = bank(economy)
    if not saved then return end
    local changed = false
    for signature, key in pairs(stockedKeys) do
        local pending, isNew = markBrowsePending(saved, signature)
        if pending then
            scanKeys[signature] = key
            if mergeBrowseKey(saved.coverage, signature, key) or isNew then changed = true end
        end
    end
    if changed and ns.RecipeStats then ns.RecipeStats.Invalidate("sellers") end
end

-- Only a full browse can replace the economy's set of known variants.
function SellerStats.RecordBrowse(economy, keys, complete, incompleteItems)
    local saved = bank(economy, true)
    if not saved then return end
    local coverage = complete == true and {} or saved.coverage or {}
    mergeBrowseKeys(coverage, keys)
    saved.coverage = coverage
    saved.coverageComplete = complete == true
    if saved.coverageComplete then
        saved.incompleteItems = {}
    elseif incompleteItems then
        for itemID in pairs(incompleteItems) do
            saved.incompleteItems[itemID] = true
        end
    end
    if ns.RecipeStats then ns.RecipeStats.Invalidate("sellers") end
end

function SellerStats.NoteIncompleteCoverage(itemID, economy)
    local saved = bank(economy, true)
    if not saved or saved.incompleteItems[itemID] then return end
    saved.incompleteItems[itemID] = true
    if ns.RecipeStats then ns.RecipeStats.Invalidate("sellers") end
end

function SellerStats.HasIncompleteCoverage(itemID, economy)
    local saved = bank(economy)
    return saved ~= nil and saved.incompleteItems ~= nil and saved.incompleteItems[itemID] == true
end

function SellerStats.GetKeys(itemID, economy)
    local saved, result = bank(economy), {}
    for signature, key in pairs(saved and saved.coverage[itemID] or {}) do
        result[#result + 1] = {signature=signature, key=key}
    end
    table.sort(result, function(a,b) return a.signature < b.signature end)
    local keys = {}
    for _, entry in ipairs(result) do keys[#keys + 1] = entry.key end
    return keys
end

function SellerStats.Get(itemID, economy)
    itemID = number(itemID)
    if not itemID or itemID == 0 then return UNAVAILABLE end
    local saved = bank(economy)
    local records = saved and saved.items[itemID]
    if not records then return UNAVAILABLE end
    local coverage = saved.coverage[itemID]
    local names, count, at, found = {}, 0, nil, false
    local complete = saved.coverageComplete and coverage and next(coverage) ~= nil
        and not (saved.incompleteItems and saved.incompleteItems[itemID]) or false
    local reason = complete and nil or "Full item-variant coverage is unavailable."
    for signature in pairs(records) do
        local record = saved.keys[signature]
        if record.key.itemID == itemID and (not coverage or coverage[signature]) then
            found = true
            at = at and math.min(at, record.at) or record.at
            if record.status ~= "complete" then complete, reason = false, record.reason end
            for name in pairs(record.names) do
                if not names[name] then names[name], count = true, count + 1 end
            end
        end
    end
    local pending
    for signature in pairs(coverage or {}) do
        if saved.pendingBrowse and saved.pendingBrowse[signature] then
            complete, pending = false, true
        elseif not saved.keys[signature] then
            complete, reason = false, "Some item variants have not been searched."
        end
    end
    if pending then reason = "Some live item variants are awaiting a fresh seller search." end
    if not found or (count == 0 and not complete and not pending) then
        return {status="unavailable", display="n/a", scope="Item variants", at=at, reason=reason or UNAVAILABLE.reason}
    end
    return {count=count, status=complete and "complete" or "partial", at=at, scope="Item variants",
        display=tostring(count) .. (complete and "" or "+"), reason=not complete and reason or nil}
end
