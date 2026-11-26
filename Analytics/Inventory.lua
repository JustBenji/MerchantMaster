local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
_G.MerchantMasterAnalytics = ns
local Inventory = { version=1 }
ns.Inventory = Inventory
local function db()
    local store = ns.Store
    if store and store.db then return store.db end
    local root = _G.MerchantMasterLedgerDB
    if type(root) ~= "table" then root = {}; _G.MerchantMasterLedgerDB = root end
    return root
end
local function safe(v)
    return not ((_G.issecrettable and type(v)=="table" and _G.issecrettable(v)) or (_G.issecretvalue and _G.issecretvalue(v)))
end
local function now()
    local value=_G.time and _G.time()
    if safe(value) and tonumber(value) then return tonumber(value) end
    return (os and os.time and os.time()) or 0
end
local function counts(t)
    local out = {}
    for id, qty in pairs(type(t) == "table" and t or {}) do
        id, qty = tonumber(id), tonumber(qty)
        if id and id > 0 and qty and qty > 0 then out[id] = qty end
    end
    return out
end
local function equal(a,b)
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function writable() local st=ns.Store; return not (st and st.readOnly) end
local function ensure(t, key)
    t[key] = type(t[key]) == "table" and t[key] or {}
    return t[key]
end
function Inventory.RecordInTransitMail(toChar, items, money, at, fromChar, econ)
    if not writable() or type(toChar) ~= "string" or toChar == "" then return nil end
    local root = db(); root.inTransitMail = type(root.inTransitMail) == "table" and root.inTransitMail or {}
    local packed = {}
    for _, item in pairs(type(items) == "table" and items or {}) do
        if type(item) == "table" then
            local id, qty = tonumber(item.itemID or item.id), tonumber(item.qty or item.count)
            if id and id > 0 and qty and qty > 0 then packed[id] = (packed[id] or 0) + qty end
        end
    end
    at = tonumber(at) or now()
    root.inventorySeq = (tonumber(root.inventorySeq) or 0) + 1
    local id = tostring(fromChar or "") .. ":" .. toChar .. ":" .. tostring(at) .. ":" .. tostring(root.inventorySeq)
    local entry = { id=id, fromChar=fromChar, toChar=toChar, econ=econ, sentAt=at, expiresAt=at+30*86400, items=packed, money=tonumber(money) or 0 }
    root.inTransitMail[#root.inTransitMail+1] = entry
    Inventory.version=Inventory.version+1
    return entry
end
function Inventory.ReceiveTransitMail(toChar, items)
    if not writable() then return 0 end
    local root = db(); local list = root.inTransitMail or {}; local want = counts(items); local removed = 0; local expired=false
    for i = #list, 1, -1 do
        local e = list[i]
        if e.toChar == toChar then
            if not items then table.remove(list, i); removed = removed + 1
            else
                for id, qty in pairs(want) do
                    local n = math.min(qty, (e.items and e.items[id]) or 0)
                    if n > 0 then e.items[id] = e.items[id] - n; want[id] = qty - n; removed = removed + n end
                end
                local remaining = false
                for _, qty in pairs(e.items or {}) do if qty > 0 then remaining = true; break end end
                if not remaining then table.remove(list, i) end
            end
        elseif (tonumber(e.expiresAt) or 0) <= now() then table.remove(list, i); expired=true end
    end
    if removed>0 or expired then Inventory.version=Inventory.version+1 end
    return removed
end
local function charEconomy(char)
    local store = ns.Store
    return store and store.DeriveEcon and store.DeriveEcon(char) or tostring(char):match("^[^-]+%-[^-]+") or ""
end
local legacyCache = { invVer = -1, hostRev = -1, idsRef = nil, idsCount = -1, reverse = nil, byChar = {} }
local function legacySnapshot(char, econ)
    local hostDB = _G.MerchantMasterDB or {}; local c = hostDB.chars and hostDB.chars[char]
    if type(c) ~= "table" then return nil end
    local ids = hostDB.itemIDs or {}
    local hostRev = (host and host.app and host.app.ownershipRev) or 0
    if legacyCache.invVer ~= Inventory.version or legacyCache.hostRev ~= hostRev or legacyCache.idsRef ~= ids then
        legacyCache.invVer = Inventory.version
        legacyCache.hostRev = hostRev
        legacyCache.idsRef = ids
        legacyCache.reverse = nil
        legacyCache.byChar = {}
    end
    local hit = legacyCache.byChar[char]
    if hit and hit._charRef == c and hit.econ == econ then
        return hit
    end
    local reverse = legacyCache.reverse
    if not reverse then
        reverse = {}
        for name, id in pairs(ids) do reverse[name] = tonumber(id) end
        legacyCache.reverse = reverse
    end
    local function mapped(src)
        local out = {}
        for name, value in pairs(type(src) == "table" and src or {}) do
            local id = tonumber(name) or reverse[name]
            local qty = tonumber(type(value) == "table" and (value.count or value.qty) or value)
            if id and id > 0 and qty and qty > 0 then out[id] = (out[id] or 0) + qty end
        end
        return out
    end
    local snap = { _charRef = c, updatedAt=0, econ=econ, faction=c.faction, bags=mapped(c.bags), bank=mapped(c.bank), mail=mapped(c.mail), gear=mapped(c.gear), boundBags={}, boundBank={} }
    legacyCache.byChar[char] = snap
    return snap
end
local function getBagContainerIDs()
    local numBags = tonumber(_G.NUM_BAG_SLOTS) or 4
    local list, seen = {}, {}
    for bag = 0, numBags do
        list[#list + 1] = bag
        seen[bag] = true
    end
    local totalEquipped = tonumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 0
    local bagIdx = _G.Enum and _G.Enum.BagIndex
    local reagentBag = type(bagIdx) == "table" and tonumber(bagIdx.ReagentBag) or nil
    local bankBag1 = type(bagIdx) == "table" and tonumber(bagIdx.BankBag_1) or nil
    if reagentBag and reagentBag > numBags and totalEquipped > numBags and reagentBag ~= bankBag1 and not seen[reagentBag] then
        list[#list + 1] = reagentBag
        seen[reagentBag] = true
    end
    return list, seen
end
local function getBankContainerIDs()
    local bagList, bagSet = getBagContainerIDs()
    local lastBag = bagList[#bagList] or (tonumber(_G.NUM_BAG_SLOTS) or 4)
    local numBankBags = tonumber(_G.NUM_BANKBAGSLOTS) or 7
    local list, seen = {}, {}
    local function add(bag)
        if type(bag) == "number" and not seen[bag] and not bagSet[bag] then
            seen[bag] = true
            list[#list + 1] = bag
        end
    end
    add(-1)
    local bagIdx = _G.Enum and _G.Enum.BagIndex
    if type(bagIdx) == "table" then add(bagIdx.Bank) end
    if type(_G.IsReagentBankUnlocked) == "function" then
        local ok, unlocked = pcall(_G.IsReagentBankUnlocked)
        if ok and safe(unlocked) and unlocked then add(-3) end
    end
    local first = lastBag + 1
    local last = first + numBankBags - 1
    for bag = first, last do add(bag) end
    return list
end
Inventory.GetBagContainerIDs = getBagContainerIDs
Inventory.GetBankContainerIDs = getBankContainerIDs
local function scanContainerIndices(indices, wantBound)
    local out, boundOut, totalSlots = {}, wantBound and {} or nil, 0
    local c = _G.C_Container
    local api = wantBound and _G.C_Item or nil
    local itemLoc = (api and api.ItemLocation) or _G.ItemLocation
    local canBound = api and type(api.IsBound) == "function" and itemLoc and type(itemLoc.CreateFromBagAndSlot) == "function"
    for _, bag in ipairs(indices or {}) do
        local n = nil
        if c and c.GetContainerNumSlots then n = c.GetContainerNumSlots(bag) end
        if not safe(n) then return out, boundOut or {}, totalSlots end
        if n == nil and _G.GetContainerNumSlots then n = _G.GetContainerNumSlots(bag) end
        if not safe(n) then return out, boundOut or {}, totalSlots end
        n = tonumber(n) or 0
        totalSlots = totalSlots + n
        for slot = 1, n do
            local id, qty
            if c and c.GetContainerItemInfo then
                local info = c.GetContainerItemInfo(bag, slot)
                if type(info) == "table" and safe(info) and safe(info.itemID) and safe(info.stackCount) and safe(info.hyperlink) then
                    id = tonumber(info.itemID) or tonumber(type(info.hyperlink) == "string" and info.hyperlink:match("item:(%d+)"))
                    qty = tonumber(info.stackCount)
                    if wantBound and id and id > 0 then
                        local isBound = safe(info.isBound) and info.isBound == true
                        if not isBound and info.isBound == nil and canBound then
                            local ok, loc
                            if itemLoc == _G.ItemLocation then
                                ok, loc = pcall(itemLoc.CreateFromBagAndSlot, itemLoc, bag, slot)
                            else
                                ok, loc = pcall(itemLoc.CreateFromBagAndSlot, bag, slot)
                            end
                            if ok and safe(loc) then
                                local boundOk, bound = pcall(api.IsBound, loc)
                                if boundOk and safe(bound) and bound then isBound = true end
                            end
                        end
                        if isBound then
                            boundOut[id] = (boundOut[id] or 0) + (qty or 1)
                        end
                    end
                end
            elseif _G.GetContainerItemInfo then
                local _, count, _, _, _, _, link = _G.GetContainerItemInfo(bag, slot)
                if safe(count) and safe(link) then id = tonumber(type(link) == "string" and link:match("item:(%d+)")); qty = tonumber(count) end
            end
            if id and id > 0 then out[id] = (out[id] or 0) + (qty or 1) end
        end
    end
    return out, boundOut or {}, totalSlots
end
local function scanContainerWithBound(first, last, wantBound)
    local indices = {}
    for bag = first, last do indices[#indices + 1] = bag end
    return scanContainerIndices(indices, wantBound)
end
local function scanContainer(first, last)
    local out = scanContainerWithBound(first, last, false)
    return out
end
local function scanBound(first, last)
    local _, boundOut = scanContainerWithBound(first, last, true)
    return boundOut
end
function Inventory.IsBankOpen()
    local cap = ns.Capture
    local h = host
    local bankFrameShown = false
    if _G.BankFrame and _G.BankFrame.IsShown then
        local ok, shown = pcall(_G.BankFrame.IsShown, _G.BankFrame)
        if ok and safe(shown) and shown then bankFrameShown = true end
    end
    local flagged = (cap and cap._bankOpen == true) or (h and h.app and h.app.atBank == true) or bankFrameShown
    if not flagged then return false end
    local c = _G.C_Container
    local slotFn = (c and c.GetContainerNumSlots) or _G.GetContainerNumSlots
    if type(slotFn) == "function" then
        local slots = 0
        for _, bag in ipairs(getBankContainerIDs()) do
            local n = slotFn(bag)
            if safe(n) and tonumber(n) then slots = slots + tonumber(n) end
        end
        if slots <= 0 then return false end
    end
    return true
end
function Inventory.ScanBank(opts)
    if not writable() then return nil end
    local store=ns.Store; local char,econ
    if store and store.CurrentCharAndEcon then char,econ=store.CurrentCharAndEcon() end
    if not char then return nil end
    local bank, bound, totalSlots = scanContainerIndices(getBankContainerIDs(), true)
    local root=db(); local inv=ensure(root,"inventory")
    local existing = inv[char]
    if totalSlots == 0 and not (opts and opts.allowEmpty) and existing and type(existing.bank) == "table" and next(existing.bank) ~= nil then
        return existing
    end
    local legacy = not existing and legacySnapshot(char, econ) or nil
    local snap = existing or {
        econ = econ,
        faction = legacy and legacy.faction or nil,
        bags = legacy and counts(legacy.bags) or {},
        mail = legacy and counts(legacy.mail) or {},
        gear = legacy and counts(legacy.gear) or {},
        boundBags = legacy and counts(legacy.boundBags) or {},
        boundBank = {},
    }
    local priorBank, priorBound = snap.bank, snap.boundBank
    snap.bank=bank; snap.boundBank=bound; snap.bankAt=now(); snap.updatedAt=now(); snap.econ=econ; inv[char]=snap
    if not existing or not equal(priorBank, bank) or not equal(priorBound, bound) then Inventory.version=Inventory.version+1 end
    return snap
end
function Inventory.AcceptMailboxSnapshot(snapshot)
    local store=ns.Store; local char,econ
    if store and store.CurrentCharAndEcon then char,econ=store.CurrentCharAndEcon() end
    if not writable() or not char or not snapshot or not snapshot.items then return end
    local root=db(); local inv=ensure(root,"inventory")
    local snap=inv[char] or {econ=econ,bags={},bank={},gear={},boundBags={},boundBank={}}
    local arrived={}
    for id,qty in pairs(snapshot.items) do local n=qty-((snap.mail and snap.mail[id]) or 0); if n>0 then arrived[id]=n end end
    local stamp=now()
    local changed=not equal(snap.mail,snapshot.items) or snap.mailAt~=stamp or snap.updatedAt~=stamp or snap.econ~=econ
    snap.mail=counts(snapshot.items); snap.mailAt=stamp; snap.updatedAt=stamp; snap.econ=econ; inv[char]=snap
    if changed then Inventory.version=Inventory.version+1 end
    return snap,arrived
end
function Inventory.ScanMailbox()
    local store=ns.Store; local char
    if store and store.CurrentCharAndEcon then char=store.CurrentCharAndEcon() end
    if not writable() or not char or not _G.GetInboxNumItems or not _G.GetInboxItem then return nil end
    local mail={}; local n=_G.GetInboxNumItems(); if not safe(n) then return nil end
    local maxAtt=tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 12
    for i=1,tonumber(n) or 0 do
        for slot=1,maxAtt do
            local name,id,_,qty=_G.GetInboxItem(i,slot)
            local link=_G.GetInboxItemLink and _G.GetInboxItemLink(i,slot)
            if not safe(name) or not safe(id) or not safe(qty) or not safe(link) then return nil end
            id=tonumber(id) or tonumber(type(link)=="string" and link:match("item:(%d+)"))
            if id and id>0 then mail[id]=(mail[id] or 0)+(tonumber(qty) or 1) elseif slot==1 and not name then break end
        end
    end
    return Inventory.AcceptMailboxSnapshot({items=mail})
end
function Inventory.ClearInTransitForChar(toChar)
    if not writable() or type(toChar) ~= "string" or toChar == "" then return 0 end
    local root = db()
    local list = root.inTransitMail or {}
    local removed = 0
    for i = #list, 1, -1 do
        local e = list[i]
        if e and (e.toChar == toChar or (tonumber(e.expiresAt) or 0) <= now()) then
            table.remove(list, i)
            removed = removed + 1
        end
    end
    if removed > 0 then Inventory.version = Inventory.version + 1 end
    return removed
end
function Inventory.ScanCurrentChar(opts)
    if not writable() then return nil end
    opts = opts or {}
    local store = ns.Store
    local currentChar, currentEcon
    if store and store.CurrentCharAndEcon then currentChar, currentEcon = store.CurrentCharAndEcon() end
    local char = opts.char or currentChar
    if type(char) ~= "string" or char == "" then return nil end
    local econ = opts.econ or currentEcon or charEconomy(char)
    local root = db(); local inv = ensure(root, "inventory")
    if type(root.inTransitMail)=="table" then for i=#root.inTransitMail,1,-1 do if (tonumber(root.inTransitMail[i].expiresAt) or 0)<=now() then table.remove(root.inTransitMail,i) end end end
    local existing = inv[char]
    local legacy = not existing and legacySnapshot(char, econ) or nil
    local prior = existing or legacy or {}
    local bagIDs = getBagContainerIDs()
    local bags, boundBags
    if opts.bags and opts.boundBags then
        bags, boundBags = counts(opts.bags), counts(opts.boundBags)
    elseif opts.bags then
        bags = counts(opts.bags)
        local _, bOut = scanContainerIndices(bagIDs, true)
        boundBags = bOut
    elseif opts.boundBags then
        local bItems = scanContainerIndices(bagIDs, false)
        bags = bItems
        boundBags = counts(opts.boundBags)
    else
        bags, boundBags = scanContainerIndices(bagIDs, true)
    end
    local gear=opts.gear and counts(opts.gear) or (opts.skipGear and prior.gear and counts(prior.gear)) or {}
    if not opts.gear and not opts.skipGear and _G.GetInventoryItemID then for slot=1,19 do local id=_G.GetInventoryItemID("player",slot); if safe(id) and tonumber(id) and id>0 then gear[tonumber(id)]=(gear[tonumber(id)] or 0)+1 end end end
    local faction; if _G.UnitFactionGroup then local token,value=_G.UnitFactionGroup("player"); if safe(token) and type(token)=="string" then faction=token elseif safe(value) and type(value)=="string" then faction=value end end
    local result = { updatedAt=now(), econ=econ, faction=opts.faction or faction or prior.faction, bags=bags, bank=counts(prior.bank), bankAt=prior.bankAt, mail=counts(prior.mail), mailAt=prior.mailAt, gear=gear, boundBags=boundBags, boundBank=counts(opts.boundBank or prior.boundBank) }
    if opts.bank then result.bank=counts(opts.bank); result.bankAt=now() end
    if opts.mail then result.mail=counts(opts.mail); result.mailAt=now() end
    inv[char] = result
    if not existing or not equal(existing,result) then Inventory.version=Inventory.version+1 end
    return result
end
local function transitFor(char, id, econFilter)
    local qty = 0
    for _, e in ipairs(db().inTransitMail or {}) do
        if e.toChar == char and (tonumber(e.expiresAt) or 0)>now() and (not econFilter or e.econ == econFilter) then qty = qty + ((e.items and e.items[id]) or 0) end
    end
    return qty
end
local function canonicalInventoryChars(rawChars, explicitChar)
    local root = db()
    local inventories = root.inventory or {}
    local hostChars = _G.MerchantMasterDB and _G.MerchantMasterDB.chars or {}
    local h = host
    local activeKey = h and h.app and h.app.charKey
    local hasRealNH = false
    for c in pairs(rawChars or {}) do
        if c ~= "Normal-Horde-Forever-Player" then
            local econ = (inventories[c] and inventories[c].econ) or charEconomy(c)
            if econ == "Normal-Horde" then hasRealNH = true; break end
        end
    end
    local groups, groupMeta, twoWordByFirst = {}, {}, {}
    for c in pairs(rawChars or {}) do
        if c == "Normal-Horde-Forever-Player" and hasRealNH and explicitChar ~= "Normal-Horde-Forever-Player" then
            -- Skip fallback placeholder when real Normal-Horde characters exist.
        else
            local inv = inventories[c]
            local econ = (inv and inv.econ) or charEconomy(c)
            local legacy = hostChars[c]
            local short = (type(legacy) == "table" and safe(legacy.name) and legacy.name ~= "" and legacy.name)
                or tostring(c):match("%-([^%-]+)$") or tostring(c)
            local econLow, shortLow = tostring(econ):lower(), tostring(short):lower()
            local gk = econLow .. "|" .. shortLow
            if not groupMeta[gk] then
                local firstW, restW = shortLow:match("^([^%s]+)%s+(.+)$")
                local isTwo = (firstW ~= nil and restW ~= nil and restW ~= "")
                groupMeta[gk] = { econLow = econLow, shortLow = shortLow, isTwoWord = isTwo }
                if isTwo then
                    local fk = econLow .. "|" .. firstW
                    twoWordByFirst[fk] = twoWordByFirst[fk] or {}
                    twoWordByFirst[fk][#twoWordByFirst[fk] + 1] = gk
                end
            end
            local cur = groups[gk]
            local cAct = (activeKey and c == activeKey) and 1 or 0
            local cSpace = shortLow:find("%s") and 1 or 0
            local cInv = inv and 1 or 0
            local cUpd = (inv and tonumber(inv.updatedAt)) or 0
            local cHost = legacy and 1 or 0
            local better = false
            if not cur then
                better = true
            elseif cAct ~= cur.act then better = cAct > cur.act
            elseif cSpace ~= cur.space then better = cSpace > cur.space
            elseif cInv ~= cur.inv then better = cInv > cur.inv
            elseif cUpd ~= cur.upd then better = cUpd > cur.upd
            elseif cHost ~= cur.host then better = cHost > cur.host
            else better = c < cur.char end
            if better then
                groups[gk] = { char = c, act = cAct, space = cSpace, inv = cInv, upd = cUpd, host = cHost }
            end
        end
    end
    -- Drop unambiguous single-word Forever alias when exactly one two-word match exists in same economy.
    for gk, meta in pairs(groupMeta) do
        if not meta.isTwoWord and groups[gk] then
            local cands = twoWordByFirst[meta.econLow .. "|" .. meta.shortLow]
            if cands and #cands == 1 and groups[cands[1]] then
                local oldRec = hostChars[groups[gk].char]
                local newRec = hostChars[groups[cands[1]].char]
                if not (type(oldRec) == "table" and type(newRec) == "table" and oldRec.guid and newRec.guid and oldRec.guid ~= newRec.guid) then
                    groups[gk] = nil
                end
            end
        end
    end
    local out = {}
    for _, grp in pairs(groups) do out[grp.char] = true end
    return out
end
function Inventory.GetItemBreakdown(itemID, econFilter)
    itemID = tonumber(itemID); if not itemID or itemID <= 0 then return nil end
    local root=db(); local inventories=root.inventory or {}; local total={total=0,bags=0,bank=0,mail=0,inTransit=0,ah=0,gear=0,guild=0,byChar={},guildUpdatedAt=0}
    local rawChars={}; for char in pairs(inventories) do rawChars[char]=true end
    local old=_G.MerchantMasterDB and _G.MerchantMasterDB.chars or {}; for char in pairs(old) do rawChars[char]=true end
    for _, pending in ipairs(root.inTransitMail or {}) do if pending.toChar then rawChars[pending.toChar]=true end end
    local chars = canonicalInventoryChars(rawChars)
    for char in pairs(chars) do
        local inv=inventories[char]; local econ=(inv and inv.econ) or charEconomy(char)
        if not econFilter or econ==econFilter then
            inv=inv or legacySnapshot(char,econ) or {}
            local ah=0; local store=ns.Store
            if store and store.Lots then for _, lot in ipairs(store.Lots(char,itemID) or {}) do ah=ah+(tonumber(lot.qty) or 0) end end
            local legacy=_G.MerchantMasterDB and _G.MerchantMasterDB.chars and _G.MerchantMasterDB.chars[char]
            local short=(type(legacy)=="table" and safe(legacy.name) and legacy.name) or char:match("%-([^%-]+)$") or char
            local hasBank=(inv.bank and inv.bank[itemID] or 0)>0
            local hasMail=(inv.mail and inv.mail[itemID] or 0)>0
            local stale=not inv.updatedAt or now()-(inv.updatedAt or 0)>86400
            if hasBank and (not inv.bankAt or now()-(inv.bankAt or 0)>86400) then stale=true end
            if hasMail and (not inv.mailAt or now()-(inv.mailAt or 0)>86400) then stale=true end
            local b={char=char,shortName=short,bags=(inv.bags and inv.bags[itemID]) or 0,bank=(inv.bank and inv.bank[itemID]) or 0,mail=(inv.mail and inv.mail[itemID]) or 0,inTransit=transitFor(char,itemID,econFilter),ah=ah,gear=(inv.gear and inv.gear[itemID]) or 0,updatedAt=inv.updatedAt or 0,stale=stale}
            total.byChar[#total.byChar+1]=b
            for _, k in ipairs({"bags","bank","mail","inTransit","ah","gear"}) do total[k]=total[k]+b[k] end
        end
    end
    table.sort(total.byChar,function(a,b) return a.char<b.char end)
    for _, g in pairs(root.guildInventory or {}) do if not econFilter or g.econ==econFilter then total.guild=total.guild+((g.tabItems and g.tabItems[itemID]) or 0); total.guildUpdatedAt=math.max(total.guildUpdatedAt,tonumber(g.updatedAt) or 0) end end
    total.total=total.bags+total.bank+total.mail+total.inTransit+total.ah+total.gear+total.guild
    return total
end
function Inventory.GetAllItems(filters)
    filters=filters or {}; local ids={}; local root=db(); local invs=root.inventory or {}; local hostChars=_G.MerchantMasterDB and _G.MerchantMasterDB.chars or {}
    local allowedChars=nil
    if not filters.char then
        local rawChars={}
        for c in pairs(invs) do rawChars[c]=true end
        for c in pairs(hostChars) do rawChars[c]=true end
        allowedChars=canonicalInventoryChars(rawChars)
    end
    local function gather(t) for id, qty in pairs(type(t)=="table" and t or {}) do if tonumber(id) and (tonumber(qty) or 0)>0 then ids[tonumber(id)]=true end end end
    for char, inv in pairs(invs) do if (not allowedChars or allowedChars[char]) and (not filters.econ or inv.econ==filters.econ) and (not filters.char or filters.char==char) then for _, k in ipairs({"bags","bank","mail","gear"}) do gather(inv[k]) end end end
    if filters.includeOffline ~= false then for char in pairs(hostChars) do if (not allowedChars or allowedChars[char]) and (not filters.char or filters.char==char) then local old=legacySnapshot(char,charEconomy(char)); if old then for _,k in ipairs({"bags","bank","mail","gear"}) do gather(old[k]) end end end end end
    for char in pairs(root.lots or {}) do if not filters.char or filters.char==char then for id in pairs(root.lots[char]) do ids[tonumber(id)]=true end end end
    for _, pending in ipairs(root.inTransitMail or {}) do if (not filters.char or pending.toChar==filters.char) and (not filters.econ or pending.econ==filters.econ) then for id in pairs(pending.items or {}) do ids[tonumber(id)]=true end end end
    for _, guild in pairs(root.guildInventory or {}) do if not filters.econ or guild.econ==filters.econ then for id in pairs(guild.tabItems or {}) do ids[tonumber(id)]=true end end end
    local out={}; for id in pairs(ids) do local d=Inventory.GetItemBreakdown(id,filters.econ); if filters.char and d then local kept={}; for _,b in ipairs(d.byChar) do if b.char==filters.char then kept[#kept+1]=b end end; d.byChar=kept; d.bags=0; d.bank=0; d.mail=0; d.inTransit=0; d.ah=0; d.gear=0; for _,b in ipairs(kept) do for _,k in ipairs({"bags","bank","mail","inTransit","ah","gear"}) do d[k]=d[k]+b[k] end end; d.total=d.bags+d.bank+d.mail+d.inTransit+d.ah+d.gear end; if filters.char and d then d.guild=0 end; if d and d.total>0 then
        local name; local h=host
        if h and h.ItemName then local ok,v=pcall(h.ItemName,id); if ok and safe(v) then name=v end end
        name=name or ("Item #"..id); if not filters.search or name:lower():find(tostring(filters.search):lower(),1,true) then local updatedAt=0; for _,b in ipairs(d.byChar) do updatedAt=math.max(updatedAt,b.updatedAt or 0) end; out[#out+1]={itemID=id,name=name,bags=d.bags,bank=d.bank,mail=d.mail,inTransit=d.inTransit,ah=d.ah,gear=d.gear,guild=d.guild,total=d.total,byChar=d.byChar,updatedAt=updatedAt,guildUpdatedAt=d.guildUpdatedAt} end
    end end
    table.sort(out,function(a,b) return a.itemID<b.itemID end); return out
end
function Inventory.CaptureGuildSnapshot(guildKey, econ, tabs, gold)
    if not writable() or type(guildKey)~="string" or guildKey=="" then return nil end
    local root=db(); root.guildInventory=type(root.guildInventory)=="table" and root.guildInventory or {}
    local items={}; for _, tab in pairs(type(tabs)=="table" and tabs or {}) do for id, qty in pairs(type(tab)=="table" and tab or {}) do id,qty=tonumber(id),tonumber(qty); if id and qty and id>0 and qty>0 then items[id]=(items[id] or 0)+qty end end end
    local snap={updatedAt=now(),econ=econ,tabItems=items,gold=tonumber(gold) or 0}; root.guildInventory[guildKey]=snap; Inventory.version=Inventory.version+1; return snap
end

-- Portfolio Audit & Sync Engine (scoped to consume 0 top-level locals)
do
    local function itemNameOf(id, fallback)
        if type(fallback) == "string" and fallback ~= "" then return fallback end
        local n = tonumber(id)
        if not n or n <= 0 then return "Unknown Item" end
        local h = host
        if h and h.ItemName then
            local ok, v = pcall(h.ItemName, n)
            if ok and safe(v) and type(v) == "string" and v ~= "" then return v end
        end
        if ns.Model and ns.Model.ItemName then
            local ok, v = pcall(ns.Model.ItemName, n)
            if ok and safe(v) and type(v) == "string" and v ~= "" then return v end
        end
        return "Item #" .. tostring(n)
    end

    local function resolveNameMapToIDs(src)
        local out = {}
        local hostDB = _G.MerchantMasterDB or {}
        local ids = hostDB.itemIDs or {}
        local h = host
        local byName = h and h.ITEM_IDS_BY_NAME or {}
        for key, value in pairs(type(src) == "table" and src or {}) do
            local qty = tonumber(type(value) == "table" and (value.count or value.qty) or value) or 0
            if qty > 0 then
                local id = tonumber(key) or tonumber(ids[key]) or tonumber(byName[key])
                if not id and ns.Store and ns.Store.ResolveItemIDByName then
                    local curChar = ns.Store.CurrentCharAndEcon and ns.Store.CurrentCharAndEcon() or ""
                    local r = ns.Store.ResolveItemIDByName(curChar, tostring(key))
                    if r and r > 0 then id = r end
                end
                if id and id > 0 then out[id] = (out[id] or 0) + qty end
            end
        end
        return out
    end

    local function wealthCatToIDs(list)
        local out = {}
        local hostDB = _G.MerchantMasterDB
        local ids = (type(hostDB) == "table" and type(hostDB.itemIDs) == "table") and hostDB.itemIDs or nil
        for _, it in ipairs(type(list) == "table" and list or {}) do
            if type(it) == "table" then
                local id = tonumber(it.id)
                if (not id or id <= 0) and ids and type(it.name) == "string" then
                    id = tonumber(ids[it.name])
                end
                local qty = tonumber(it.qty) or 0
                if id and id > 0 and qty > 0 then out[id] = (out[id] or 0) + qty end
            end
        end
        return out
    end

    local function scanLiveBagsByName()
        local byName, boundByName, byID, boundByID, totalSlots = {}, {}, {}, {}, 0
        local c = _G.C_Container
        local api = _G.C_Item
        local itemLoc = (api and api.ItemLocation) or _G.ItemLocation
        local canBound = api and type(api.IsBound) == "function" and itemLoc and type(itemLoc.CreateFromBagAndSlot) == "function"
        local indices = getBagContainerIDs()
        for _, bag in ipairs(indices) do
            local n = nil
            if c and c.GetContainerNumSlots then n = c.GetContainerNumSlots(bag) end
            if not safe(n) then return byName, boundByName, byID, boundByID, totalSlots end
            if n == nil and _G.GetContainerNumSlots then n = _G.GetContainerNumSlots(bag) end
            if not safe(n) then return byName, boundByName, byID, boundByID, totalSlots end
            n = tonumber(n) or 0
            totalSlots = totalSlots + n
            for slot = 1, n do
                local id, qty, link, isBound
                if c and c.GetContainerItemInfo then
                    local info = c.GetContainerItemInfo(bag, slot)
                    if type(info) == "table" and safe(info) and safe(info.itemID) and safe(info.stackCount) and safe(info.hyperlink) then
                        link = info.hyperlink
                        id = tonumber(info.itemID) or tonumber(type(link) == "string" and link:match("item:(%d+)"))
                        qty = tonumber(info.stackCount) or 1
                        isBound = safe(info.isBound) and info.isBound == true
                        if not isBound and info.isBound == nil and canBound and id and id > 0 then
                            local ok, loc
                            if itemLoc == _G.ItemLocation then
                                ok, loc = pcall(itemLoc.CreateFromBagAndSlot, itemLoc, bag, slot)
                            else
                                ok, loc = pcall(itemLoc.CreateFromBagAndSlot, bag, slot)
                            end
                            if ok and safe(loc) then
                                local bOk, bVal = pcall(api.IsBound, loc)
                                if bOk and safe(bVal) and bVal then isBound = true end
                            end
                        end
                    end
                elseif _G.GetContainerItemInfo then
                    local _, count, _, _, _, _, l, _, _, _, bound = _G.GetContainerItemInfo(bag, slot)
                    if safe(count) and safe(l) then
                        link = l
                        id = tonumber(type(l) == "string" and l:match("item:(%d+)"))
                        qty = tonumber(count) or 1
                        isBound = safe(bound) and bound == true
                    end
                end
                if id and id > 0 then
                    qty = qty or 1
                    byID[id] = (byID[id] or 0) + qty
                    if isBound then boundByID[id] = (boundByID[id] or 0) + qty end
                    local nm = (type(link) == "string" and link:match("%[(.-)%]")) or itemNameOf(id)
                    if nm and nm ~= "" then
                        byName[nm] = (byName[nm] or 0) + qty
                        if isBound then boundByName[nm] = (boundByName[nm] or 0) + qty end
                    end
                end
            end
        end
        return byName, boundByName, byID, boundByID, totalSlots
    end

    local function scanLiveBankByName()
        local byName, boundByName, byID, boundByID, totalSlots = {}, {}, {}, {}, 0
        local c = _G.C_Container
        local api = _G.C_Item
        local itemLoc = (api and api.ItemLocation) or _G.ItemLocation
        local canBound = api and type(api.IsBound) == "function" and itemLoc and type(itemLoc.CreateFromBagAndSlot) == "function"
        local indices = getBankContainerIDs()
        for _, bag in ipairs(indices) do
            local n = nil
            if c and c.GetContainerNumSlots then n = c.GetContainerNumSlots(bag) end
            if not safe(n) then return byName, boundByName, byID, boundByID, totalSlots end
            if n == nil and _G.GetContainerNumSlots then n = _G.GetContainerNumSlots(bag) end
            if not safe(n) then return byName, boundByName, byID, boundByID, totalSlots end
            n = tonumber(n) or 0
            totalSlots = totalSlots + n
            for slot = 1, n do
                local id, qty, link, isBound
                if c and c.GetContainerItemInfo then
                    local info = c.GetContainerItemInfo(bag, slot)
                    if type(info) == "table" and safe(info) and safe(info.itemID) and safe(info.stackCount) and safe(info.hyperlink) then
                        link = info.hyperlink
                        id = tonumber(info.itemID) or tonumber(type(link) == "string" and link:match("item:(%d+)"))
                        qty = tonumber(info.stackCount) or 1
                        isBound = safe(info.isBound) and info.isBound == true
                        if not isBound and info.isBound == nil and canBound and id and id > 0 then
                            local ok, loc
                            if itemLoc == _G.ItemLocation then
                                ok, loc = pcall(itemLoc.CreateFromBagAndSlot, itemLoc, bag, slot)
                            else
                                ok, loc = pcall(itemLoc.CreateFromBagAndSlot, bag, slot)
                            end
                            if ok and safe(loc) then
                                local bOk, bVal = pcall(api.IsBound, loc)
                                if bOk and safe(bVal) and bVal then isBound = true end
                            end
                        end
                    end
                elseif _G.GetContainerItemInfo then
                    local _, count, _, _, _, _, l, _, _, _, bound = _G.GetContainerItemInfo(bag, slot)
                    if safe(count) and safe(l) then
                        link = l
                        id = tonumber(type(l) == "string" and l:match("item:(%d+)"))
                        qty = tonumber(count) or 1
                        isBound = safe(bound) and bound == true
                    end
                end
                if id and id > 0 then
                    qty = qty or 1
                    byID[id] = (byID[id] or 0) + qty
                    if isBound then boundByID[id] = (boundByID[id] or 0) + qty end
                    local nm = (type(link) == "string" and link:match("%[(.-)%]")) or itemNameOf(id)
                    if nm and nm ~= "" then
                        byName[nm] = (byName[nm] or 0) + qty
                        if isBound then boundByName[nm] = (boundByName[nm] or 0) + qty end
                    end
                end
            end
        end
        return byName, boundByName, byID, boundByID, totalSlots
    end

    local function scanLiveGearByID(opts)
        if type(opts) == "table" and type(opts.liveGear) == "table" then
            return counts(opts.liveGear), 19
        end
        if type(_G.GetInventoryItemID) ~= "function" then
            return nil, 0
        end
        local out = {}
        for slot = 1, 19 do
            local ok, id = pcall(_G.GetInventoryItemID, "player", slot)
            if ok and safe(id) and tonumber(id) and tonumber(id) > 0 then
                local nid = tonumber(id)
                out[nid] = (out[nid] or 0) + 1
            end
        end
        return out, 19
    end

    local function dedupeWealthTableInPlace(wealthChar)
        if type(wealthChar) ~= "table" or type(wealthChar.cats) ~= "table" then return 0 end
        local merged = 0
        local hostDB = _G.MerchantMasterDB
        local itemIDs = (type(hostDB) == "table" and type(hostDB.itemIDs) == "table") and hostDB.itemIDs or nil
        for _, catKey in ipairs({ "bags", "bank", "mail", "gear" }) do
            local list = wealthChar.cats[catKey]
            if type(list) == "table" and #list > 1 then
                local out, byKey = {}, {}
                for _, it in ipairs(list) do
                    if type(it) == "table" then
                        local numID = tonumber(it.id)
                        if catKey == "gear" and (not numID or numID <= 0) and itemIDs and type(it.name) == "string" then
                            numID = tonumber(itemIDs[it.name])
                        end
                        local base = (numID and numID > 0 and ("i:" .. tostring(numID)) or ("n:" .. tostring(it.name or "")))
                        local key = (catKey == "gear") and base or (base .. "|" .. (it.bound and "B" or "T"))
                        local existing = byKey[key]
                        if existing then
                            if (not existing.id or tonumber(existing.id) <= 0) and numID and numID > 0 then existing.id = numID end
                            existing.qty = (tonumber(existing.qty) or 0) + (tonumber(it.qty) or 0)
                            existing.total = (tonumber(existing.total) or 0) + (tonumber(it.total) or 0)
                            if existing.qty > 0 then existing.unit = math.floor(existing.total / existing.qty + 0.5) end
                            merged = merged + 1
                        else
                            if (not it.id or tonumber(it.id) <= 0) and numID and numID > 0 then it.id = numID end
                            if catKey == "gear" then it.bound = nil end
                            byKey[key] = it
                            out[#out + 1] = it
                        end
                    end
                end
                wealthChar.cats[catKey] = out
            end
        end
        return merged
    end

    local function shortPlayerName(charKey, hostChars)
        local c = hostChars and hostChars[charKey]
        if type(c) == "table" and type(c.name) == "string" and c.name ~= "" then return c.name end
        return tostring(charKey):match("%-([^%-]+)$") or tostring(charKey)
    end

    local function formatReportText(report)
        local lines = {}
        local s = report.summary or {}
        lines[#lines + 1] = "Portfolio Audit Report  |  Char: " .. tostring(report.char or "-")
        lines[#lines + 1] = "Bank Status: " .. tostring(report.bankStatus or "-")
        lines[#lines + 1] = string.format("Issues Found: %d total (Duplicates: %d, Bag/Bank Drift: %d, Stale AH/Transit: %d, Basis/Ledger: %d)",
            s.totalIssues or 0, s.duplicates or 0, s.drift or 0, s.stale or 0, s.ledger or 0)
        lines[#lines + 1] = "------------------------------------------------------------------------"
        if #(report.findings or {}) == 0 then
            lines[#lines + 1] = "No discrepancies detected. Bags, bank snapshots, and ledger are aligned."
        else
            for idx, f in ipairs(report.findings) do
                if idx > 80 then
                    lines[#lines + 1] = string.format("... and %d more findings (click Sync to resolve snapshot issues).", #report.findings - 80)
                    break
                end
                local tag = "[" .. tostring(f.code or "INFO") .. "]"
                local subject = f.name or f.char or "Portfolio"
                lines[#lines + 1] = string.format("%d. %s %s -- %s", idx, tag, tostring(subject), tostring(f.reason or ""))
            end
        end
        return table.concat(lines, "\n")
    end

    function Inventory.AnalyzePortfolio(opts)
        opts = opts or {}
        local store = ns.Store
        local root = db()
        local hostDB = _G.MerchantMasterDB or {}
        local hostChars = type(hostDB.chars) == "table" and hostDB.chars or {}
        local curChar, curEcon = "Normal-Horde-Forever-Player", "Normal-Horde"
        if store and store.CurrentCharAndEcon then curChar, curEcon = store.CurrentCharAndEcon() end
        local char = opts.char or curChar
        local econ = opts.econ or curEcon or charEconomy(char)
        local ts = tonumber(opts.now) or now()
        local bankOpen = (opts.bankOpen ~= nil) and (opts.bankOpen == true) or Inventory.IsBankOpen()

        local liveBags, liveBoundBags, liveBagSlots
        if type(opts.liveBags) == "table" then
            liveBags, liveBoundBags, liveBagSlots = counts(opts.liveBags), counts(opts.liveBoundBags), 1
        else
            liveBags, liveBoundBags, liveBagSlots = scanContainerIndices(getBagContainerIDs(), true)
        end
        local liveBank, liveBoundBank, liveBankSlots = nil, nil, 0
        if bankOpen then
            if type(opts.liveBank) == "table" then
                liveBank, liveBoundBank, liveBankSlots = counts(opts.liveBank), counts(opts.liveBoundBank), 1
            else
                liveBank, liveBoundBank, liveBankSlots = scanContainerIndices(getBankContainerIDs(), true)
                if liveBankSlots == 0 then bankOpen = false end
            end
        end
        local liveGear, liveGearSlots = scanLiveGearByID(opts)

        local findings = {}
        local summary = { totalIssues = 0, error = 0, warn = 0, info = 0, duplicates = 0, drift = 0, stale = 0, ledger = 0 }
        local function push(f)
            findings[#findings + 1] = f
            summary.totalIssues = summary.totalIssues + 1
            local sev = f.severity or "warn"
            summary[sev] = (summary[sev] or 0) + 1
            if f.code == "DUP" or f.code == "ALIAS" then summary.duplicates = summary.duplicates + 1
            elseif f.code == "BAG_DRIFT" or f.code == "BANK_DRIFT" or f.code == "GEAR_DRIFT" then summary.drift = summary.drift + 1
            elseif f.code == "STALE_LOT" or f.code == "STALE_TRANSIT" then summary.stale = summary.stale + 1
            else summary.ledger = summary.ledger + 1 end
        end

        -- 1. [DUP] Duplicate rows inside DB.wealth[c].cats.{bags,bank,mail,gear}
        local hostItemIDs = type(hostDB.itemIDs) == "table" and hostDB.itemIDs or nil
        for cKey, w in pairs(root.wealth or {}) do
            if type(w) == "table" and type(w.cats) == "table" and charEconomy(cKey) == econ then
                for _, catKey in ipairs({ "bags", "bank", "mail", "gear" }) do
                    local seen = {}
                    for _, it in ipairs(w.cats[catKey] or {}) do
                        if type(it) == "table" then
                            local id = tonumber(it.id)
                            if catKey == "gear" and (not id or id <= 0) and hostItemIDs and type(it.name) == "string" then
                                id = tonumber(hostItemIDs[it.name])
                            end
                            local base = (id and id > 0 and ("i:" .. tostring(id)) or ("n:" .. tostring(it.name or "")))
                            local k = (catKey == "gear") and base or (base .. "|" .. (it.bound and "B" or "T"))
                            local rec = seen[k]
                            if rec then
                                rec.count = rec.count + 1
                                rec.qty = rec.qty + (tonumber(it.qty) or 0)
                            else
                                seen[k] = { count = 1, id = id, name = it.name or itemNameOf(id), qty = tonumber(it.qty) or 0, bound = it.bound }
                            end
                        end
                    end
                    for _, rec in pairs(seen) do
                        if rec.count > 1 then
                            push({
                                severity = "error", code = "DUP", char = cKey, itemID = rec.id, name = rec.name, category = catKey,
                                storedQty = rec.qty,
                                reason = string.format("Duplicate snapshot row in Wealth Breakdown (%s on %s): %s appears %dx (total qty %d)",
                                    catKey, shortPlayerName(cKey, hostChars), rec.name, rec.count, rec.qty),
                            })
                        end
                    end
                end
            end
        end

        -- 2. [ALIAS] Duplicate / ghost character keys for same (econ, shortPlayerName)
        local allCharKeys = {}
        for cKey in pairs(root.snaps or {}) do if type(cKey) == "string" and not cKey:match("^%d%d%d%d%-%d%d%-%d%d$") then allCharKeys[cKey] = true end end
        for cKey in pairs(root.wealth or {}) do if type(cKey) == "string" then allCharKeys[cKey] = true end end
        for cKey in pairs(root.inventory or {}) do if type(cKey) == "string" then allCharKeys[cKey] = true end end
        for cKey in pairs(root.lots or {}) do if type(cKey) == "string" then allCharKeys[cKey] = true end end
        for cKey in pairs(hostChars) do if type(cKey) == "string" then allCharKeys[cKey] = true end end
        local byEconPlayer, bucketMeta, twoWordBucketsByFirst = {}, {}, {}
        local realCharsInEcon = 0
        for cKey in pairs(allCharKeys) do
            local cEcon = charEconomy(cKey)
            if cEcon == econ then
                local short = shortPlayerName(cKey, hostChars)
                local shortLow = short:lower()
                local bucketKey = cEcon .. "|" .. shortLow
                if not byEconPlayer[bucketKey] then
                    byEconPlayer[bucketKey] = { name = short, keys = {} }
                    local firstW, restW = shortLow:match("^([^%s]+)%s+(.+)$")
                    local isTwo = (firstW ~= nil and restW ~= nil and restW ~= "")
                    bucketMeta[bucketKey] = { econ = cEcon, shortLow = shortLow, isTwoWord = isTwo }
                    if isTwo then
                        local fk = cEcon .. "|" .. firstW
                        twoWordBucketsByFirst[fk] = twoWordBucketsByFirst[fk] or {}
                        twoWordBucketsByFirst[fk][#twoWordBucketsByFirst[fk] + 1] = bucketKey
                    end
                end
                byEconPlayer[bucketKey].keys[#byEconPlayer[bucketKey].keys + 1] = cKey
                if cKey ~= "Normal-Horde-Forever-Player" then realCharsInEcon = realCharsInEcon + 1 end
            end
        end
        for bk, meta in pairs(bucketMeta) do
            if not meta.isTwoWord and byEconPlayer[bk] then
                local cands = twoWordBucketsByFirst[meta.econ .. "|" .. meta.shortLow]
                if cands and #cands == 1 and byEconPlayer[cands[1]] then
                    local dst = byEconPlayer[cands[1]]
                    local dstGuid = nil
                    for _, dc in ipairs(dst.keys) do
                        local dh = hostChars[dc]
                        if type(dh) == "table" and dh.guid then dstGuid = dh.guid; break end
                    end
                    local conflict = false
                    if dstGuid then
                        for _, sc in ipairs(byEconPlayer[bk].keys) do
                            local sh = hostChars[sc]
                            if type(sh) == "table" and sh.guid and sh.guid ~= dstGuid then conflict = true; break end
                        end
                    end
                    if not conflict then
                        for _, sc in ipairs(byEconPlayer[bk].keys) do
                            dst.keys[#dst.keys + 1] = sc
                        end
                        byEconPlayer[bk] = nil
                    end
                end
            end
        end
        for _, grp in pairs(byEconPlayer) do
            table.sort(grp.keys)
            if #grp.keys > 1 then
                push({
                    severity = "error", code = "ALIAS", char = grp.keys[1], name = grp.name,
                    reason = string.format("Multiple character keys share '%s' in %s (%s) - causes duplicated bag/bank rows and inflated wealth",
                        grp.name, econ, table.concat(grp.keys, " vs ")),
                })
            end
        end
        if allCharKeys["Normal-Horde-Forever-Player"] and realCharsInEcon > 0 and char ~= "Normal-Horde-Forever-Player" then
            push({
                severity = "warn", code = "ALIAS", char = "Normal-Horde-Forever-Player", name = "Fallback Player",
                reason = "Fallback placeholder character key 'Normal-Horde-Forever-Player' exists alongside real character records",
            })
        end

        -- 3. [BAG_DRIFT] Live Bags vs DB.inventory, MerchantMasterDB.chars, and DB.wealth
        local invSnap = root.inventory and root.inventory[char] or nil
        local hostChar = hostChars[char]
        local wealthChar = root.wealth and root.wealth[char] or nil
        local invBags = invSnap and counts(invSnap.bags) or nil
        local hostBags = hostChar and resolveNameMapToIDs(hostChar.bags) or nil
        local wealthBags = wealthChar and wealthChar.cats and wealthCatToIDs(wealthChar.cats.bags) or nil
        local storedBankForOverlap = (invSnap and counts(invSnap.bank)) or (hostChar and resolveNameMapToIDs(hostChar.bank)) or {}

        if liveBagSlots > 0 then
            local bagUnion = {}
            for id in pairs(liveBags) do bagUnion[id] = true end
            for id in pairs(invBags or {}) do bagUnion[id] = true end
            for id in pairs(hostBags or {}) do bagUnion[id] = true end
            for id in pairs(wealthBags or {}) do bagUnion[id] = true end
            local bagIDsSorted = {}
            for id in pairs(bagUnion) do bagIDsSorted[#bagIDsSorted + 1] = id end
            table.sort(bagIDsSorted)
            for _, id in ipairs(bagIDsSorted) do
                local lq = liveBags[id] or 0
                local iq = invBags and (invBags[id] or 0) or nil
                local hq = hostBags and (hostBags[id] or 0) or nil
                local wq = wealthBags and (wealthBags[id] or 0) or nil
                local mismatch = (iq ~= nil and iq ~= lq) or (hq ~= nil and hq ~= lq) or (wq ~= nil and wq ~= lq)
                if mismatch then
                    local parts = {}
                    if iq ~= nil and iq ~= lq then parts[#parts + 1] = "Item Inventory=" .. tostring(iq) end
                    if hq ~= nil and hq ~= lq then parts[#parts + 1] = "Host Cache=" .. tostring(hq) end
                    if wq ~= nil and wq ~= lq then parts[#parts + 1] = "Wealth Breakdown=" .. tostring(wq) end
                    local bankHint = ""
                    if (storedBankForOverlap[id] or 0) > 0 and lq > (iq or hq or wq or 0) and not bankOpen then
                        bankHint = " (item also in stored bank - open Bank and Sync to clear transfer double-count)"
                    end
                    push({
                        severity = "error", code = "BAG_DRIFT", char = char, itemID = id, name = itemNameOf(id), category = "bags",
                        liveQty = lq, storedQty = iq or wq or hq or 0,
                        reason = string.format("Bag snapshot drift: live bags=%d vs %s%s", lq, table.concat(parts, ", "), bankHint),
                    })
                end
            end
        end

        -- 4. [BANK_DRIFT] Live Bank (ONLY when bankOpen) OR cross-store consistency when closed
        local invBank = invSnap and counts(invSnap.bank) or nil
        local hostBank = hostChar and resolveNameMapToIDs(hostChar.bank) or nil
        local wealthBank = wealthChar and wealthChar.cats and wealthCatToIDs(wealthChar.cats.bank) or nil
        local bankUnion = {}
        for id in pairs(liveBank or {}) do bankUnion[id] = true end
        for id in pairs(invBank or {}) do bankUnion[id] = true end
        for id in pairs(hostBank or {}) do bankUnion[id] = true end
        for id in pairs(wealthBank or {}) do bankUnion[id] = true end
        local bankIDsSorted = {}
        for id in pairs(bankUnion) do bankIDsSorted[#bankIDsSorted + 1] = id end
        table.sort(bankIDsSorted)
        for _, id in ipairs(bankIDsSorted) do
            local iq = invBank and (invBank[id] or 0) or nil
            local hq = hostBank and (hostBank[id] or 0) or nil
            local wq = wealthBank and (wealthBank[id] or 0) or nil
            if bankOpen and liveBank then
                local lq = liveBank[id] or 0
                local mismatch = (iq ~= nil and iq ~= lq) or (hq ~= nil and hq ~= lq) or (wq ~= nil and wq ~= lq)
                if mismatch then
                    local parts = {}
                    if iq ~= nil and iq ~= lq then parts[#parts + 1] = "Item Inventory=" .. tostring(iq) end
                    if hq ~= nil and hq ~= lq then parts[#parts + 1] = "Host Cache=" .. tostring(hq) end
                    if wq ~= nil and wq ~= lq then parts[#parts + 1] = "Wealth Breakdown=" .. tostring(wq) end
                    push({
                        severity = "error", code = "BANK_DRIFT", char = char, itemID = id, name = itemNameOf(id), category = "bank",
                        liveQty = lq, storedQty = iq or wq or hq or 0,
                        reason = string.format("Bank snapshot drift: live bank=%d vs %s (stale bank-bag transfer or missed bank close)",
                            lq, table.concat(parts, ", ")),
                    })
                end
            else
                -- Bank is closed: NEVER flag stored bank items against 0; check only internal store mismatch
                local ref = wq or hq or iq
                local storeMismatch = (iq ~= nil and ref ~= nil and iq ~= ref) or (hq ~= nil and wq ~= nil and hq ~= wq)
                if storeMismatch then
                    push({
                        severity = "warn", code = "BANK_DRIFT", char = char, itemID = id, name = itemNameOf(id), category = "bank",
                        storedQty = ref or 0,
                        reason = string.format("Bank snapshot mismatch across stores (Wealth=%s, Host=%s, Inventory=%s) - open Bank and click Sync to verify live slots",
                            tostring(wq or "-"), tostring(hq or "-"), tostring(iq or "-")),
                    })
                end
            end
        end

        -- 4b. [GEAR_DRIFT] Live Equipped Gear vs DB.inventory, MerchantMasterDB.chars, and DB.wealth
        if liveGearSlots > 0 and liveGear then
            local invGear = invSnap and counts(invSnap.gear) or nil
            local hostGear = hostChar and resolveNameMapToIDs(hostChar.gear) or nil
            local wealthGear = wealthChar and wealthChar.cats and wealthCatToIDs(wealthChar.cats.gear) or nil
            local gearUnion = {}
            for id in pairs(liveGear) do gearUnion[id] = true end
            for id in pairs(invGear or {}) do gearUnion[id] = true end
            for id in pairs(hostGear or {}) do gearUnion[id] = true end
            for id in pairs(wealthGear or {}) do gearUnion[id] = true end
            local gearIDsSorted = {}
            for id in pairs(gearUnion) do gearIDsSorted[#gearIDsSorted + 1] = id end
            table.sort(gearIDsSorted)
            for _, id in ipairs(gearIDsSorted) do
                local lq = liveGear[id] or 0
                local iq = invGear and (invGear[id] or 0) or nil
                local hq = hostGear and (hostGear[id] or 0) or nil
                local wq = wealthGear and (wealthGear[id] or 0) or nil
                local mismatch = (iq ~= nil and iq ~= lq) or (hq ~= nil and hq ~= lq) or (wq ~= nil and wq ~= lq)
                if mismatch then
                    local parts = {}
                    if iq ~= nil and iq ~= lq then parts[#parts + 1] = "Item Inventory=" .. tostring(iq) end
                    if hq ~= nil and hq ~= lq then parts[#parts + 1] = "Host Cache=" .. tostring(hq) end
                    if wq ~= nil and wq ~= lq then parts[#parts + 1] = "Wealth Breakdown=" .. tostring(wq) end
                    push({
                        severity = "error", code = "GEAR_DRIFT", char = char, itemID = id, name = itemNameOf(id), category = "gear",
                        liveQty = lq, storedQty = iq or wq or hq or 0,
                        reason = string.format("Equipped gear snapshot drift: live gear=%d vs %s", lq, table.concat(parts, ", ")),
                    })
                end
            end
        end

        -- 5. [STALE_LOT] & [STALE_TRANSIT]
        local lotsByItem = root.lots and root.lots[char] or {}
        for id, lots in pairs(lotsByItem) do
            local staleQty, oldestAge = 0, 0
            for _, lot in ipairs(lots or {}) do
                local postedAt = tonumber(lot.postedAt) or 0
                local age = postedAt > 0 and (ts - postedAt) or 0
                if age > 48 * 3600 then
                    staleQty = staleQty + (tonumber(lot.qty) or 0)
                    if age > oldestAge then oldestAge = age end
                end
            end
            if staleQty > 0 then
                push({
                    severity = "warn", code = "STALE_LOT", char = char, itemID = tonumber(id), name = itemNameOf(id), category = "listed",
                    storedQty = staleQty,
                    reason = string.format("Open AH lot (%dx) posted %dh ago exceeds 48h max auction duration - likely expired/sold offline and double-counted",
                        staleQty, math.floor(oldestAge / 3600)),
                })
            end
        end
        for _, tr in ipairs(root.inTransitMail or {}) do
            if type(tr) == "table" and (not tr.econ or tr.econ == econ) then
                local expired = (tonumber(tr.expiresAt) or 0) <= ts
                local stuckAfterMail = tr.toChar == char and invSnap and (tonumber(invSnap.mailAt) or 0) > (tonumber(tr.sentAt) or 0)
                if expired or stuckAfterMail then
                    for id, qty in pairs(tr.items or {}) do
                        if (tonumber(qty) or 0) > 0 then
                            local stillInMail = invSnap and invSnap.mail and (invSnap.mail[tonumber(id)] or 0) > 0
                            if expired or not stillInMail then
                                push({
                                    severity = "warn", code = "STALE_TRANSIT", char = tr.toChar, itemID = tonumber(id), name = itemNameOf(id), category = "mail",
                                    storedQty = tonumber(qty) or 0,
                                    reason = expired and string.format("Expired in-transit mail (%dx) still counted in Transit", tonumber(qty) or 0)
                                        or string.format("Stuck in-transit mail (%dx to %s) after mailbox was already checked - double-counted in Transit + Bags",
                                            tonumber(qty) or 0, shortPlayerName(tr.toChar, hostChars)),
                                })
                            end
                        end
                    end
                end
            end
        end

        -- 6. [BASIS_EXCESS] / [BASIS_DEFICIT] & [DUP_LEDGER]
        local econBasis = root.basis and root.basis[econ] or {}
        local econStats = root.itemStats and root.itemStats[econ] or {}
        local basisCheckIDs = {}
        for id, b in pairs(econBasis) do
            if tonumber(id) and tonumber(id) > 0 and (tonumber(b.qty) or 0) > 0 then basisCheckIDs[tonumber(id)] = true end
        end
        for id in pairs(econStats) do
            if tonumber(id) and tonumber(id) > 0 then basisCheckIDs[tonumber(id)] = true end
        end
        local basisSorted = {}
        for id in pairs(basisCheckIDs) do basisSorted[#basisSorted + 1] = id end
        table.sort(basisSorted)
        local basisDiffs = {}
        for _, id in ipairs(basisSorted) do
            local b = econBasis[id]
            local basisQty = b and (tonumber(b.qty) or 0) or 0
            local basisAvg = b and (tonumber(b.avg) or 0) or 0
            local bd = Inventory.GetItemBreakdown(id, econ)
            local phys = 0
            if bd then
                for _, entry in ipairs(bd.byChar or {}) do
                    if entry.char == char then
                        local bq = liveBagSlots > 0 and (liveBags[id] or 0) or (entry.bags or 0)
                        local bkq = (bankOpen and liveBank) and (liveBank[id] or 0) or (entry.bank or 0)
                        phys = phys + bq + bkq + (entry.mail or 0) + (entry.inTransit or 0) + (entry.ah or 0)
                    else
                        phys = phys + (entry.bags or 0) + (entry.bank or 0) + (entry.mail or 0) + (entry.inTransit or 0) + (entry.ah or 0)
                    end
                end
            end
            if basisQty > phys then
                local excess = basisQty - phys
                basisDiffs[id] = { basisQty = basisQty, physQty = phys, avg = basisAvg, excess = excess }
                push({
                    severity = "warn", code = "BASIS_EXCESS", char = char, itemID = id, name = itemNameOf(id), category = "basis",
                    liveQty = phys, storedQty = basisQty,
                    reason = string.format("Ledger cost-basis excess: basis tracks %d units vs %d in inventory (+%d) - likely consumed, mailed out, guild-banked, deleted, or missing a sale/craft posting",
                        basisQty, phys, excess),
                })
            elseif phys > basisQty and (basisQty > 0 or econStats[id] ~= nil) then
                local deficit = phys - basisQty
                local boundCur = (liveBoundBags and liveBoundBags[id] or 0) + (liveBoundBank and liveBoundBank[id] or 0)
                if deficit > boundCur then
                    push({
                        severity = "info", code = "BASIS_DEFICIT", char = char, itemID = id, name = itemNameOf(id), category = "basis",
                        liveQty = phys, storedQty = basisQty,
                        reason = string.format("Untracked stock above ledger basis: inventory has %d units vs %d in basis (+%d) - looted, quested, guild-withdrawn, or owned pre-tracking (future sales estimate COGS)",
                            phys, basisQty, deficit),
                    })
                end
            end
        end

        if store and store.IterDays and store.DayKey then
            local fromDay = store.DayKey(ts - 30 * 86400)
            local toDay = store.DayKey(ts)
            local recentBySig = {}
            store.IterDays(fromDay, toDay, function(day, dayRows)
                for idx, r in ipairs(dayRows or {}) do
                    if type(r) == "table" and r.type ~= "ADJUST" and (r.econ == econ or charEconomy(r.char) == econ) and (tonumber(r.itemID) or 0) > 0 then
                        local e = r.extra or {}
                        local cp = tostring(e.buyer or e.seller or e.counterparty or "")
                        local sig = table.concat({ tostring(r.char), tostring(r.type), tostring(r.itemID), tostring(r.qty), tostring(r.total), cp }, "|")
                        local prev = recentBySig[sig]
                        local rTime = tonumber(r.time) or 0
                        if prev and math.abs(rTime - prev.time) <= 10 then
                            local suspicious = (e.tsmCatchup or prev.tsmCatchup or e.offlineInvoice or prev.offlineInvoice or e.mailFallback or prev.mailFallback) ~= nil
                                or (rTime == prev.time and (tonumber(r.total) or 0) ~= 0)
                            if suspicious then
                                local eid = store.EventID and store.EventID(r, day, idx) or (day .. ":" .. tostring(idx))
                                push({
                                    severity = "warn", code = "DUP_LEDGER", char = r.char, itemID = tonumber(r.itemID), name = itemNameOf(r.itemID), category = "ledger",
                                    storedQty = tonumber(r.qty) or 0,
                                    reason = string.format("Suspected duplicate %s posting (%dx, %dc within %ds; eids %s & %s) - likely live capture + TSM catchup/mail fallback overlap",
                                        tostring(r.type), tonumber(r.qty) or 0, tonumber(r.total) or 0, math.abs(rTime - prev.time), tostring(prev.eid), tostring(eid)),
                                })
                            end
                        end
                        recentBySig[sig] = {
                            time = rTime,
                            eid = store.EventID and store.EventID(r, day, idx) or (day .. ":" .. tostring(idx)),
                            tsmCatchup = e.tsmCatchup,
                            offlineInvoice = e.offlineInvoice,
                            mailFallback = e.mailFallback,
                        }
                    end
                end
            end)
        end

        local bankStatus = bankOpen and "OPEN (live bank containers verified)"
            or "CLOSED (bank snapshot preserved - open Bank to verify bank slots)"
        local report = {
            at = ts,
            char = char,
            econ = econ,
            bankOpen = bankOpen,
            bankStatus = bankStatus,
            summary = summary,
            findings = findings,
            basisDiffs = basisDiffs,
            liveBags = liveBags,
            liveBank = liveBank,
        }
        report.text = formatReportText(report)
        return report
    end

    local function cleanupAliasChars(root, hostDB, char, econ)
        local removed = {}
        local hostChars = type(hostDB.chars) == "table" and hostDB.chars or {}
        local allKeys = {}
        for k in pairs(root.snaps or {}) do if type(k) == "string" and not k:match("^%d%d%d%d%-%d%d%-%d%d$") then allKeys[k] = true end end
        for k in pairs(root.wealth or {}) do if type(k) == "string" then allKeys[k] = true end end
        for k in pairs(root.inventory or {}) do if type(k) == "string" then allKeys[k] = true end end
        for k in pairs(root.lots or {}) do if type(k) == "string" then allKeys[k] = true end end
        for k in pairs(hostChars) do if type(k) == "string" then allKeys[k] = true end end

        local targetShort = shortPlayerName(char, hostChars):lower()
        local hasRealNH = char ~= "Normal-Horde-Forever-Player" and econ == "Normal-Horde"
        if not hasRealNH then
            for k in pairs(allKeys) do
                if k ~= "Normal-Horde-Forever-Player" and charEconomy(k) == "Normal-Horde" then hasRealNH = true; break end
            end
        end

        local function purgeKey(k)
            if root.snaps then root.snaps[k] = nil end
            if root.wealth then root.wealth[k] = nil end
            if root.inventory then root.inventory[k] = nil end
            if root.lots then root.lots[k] = nil end
            if hostDB.chars then hostDB.chars[k] = nil end
            if root.stats and type(root.stats.chars) == "table" then root.stats.chars[k] = nil end
        end

        if allKeys["Normal-Horde-Forever-Player"] and hasRealNH and char ~= "Normal-Horde-Forever-Player" then
            purgeKey("Normal-Horde-Forever-Player")
            removed[#removed + 1] = "Normal-Horde-Forever-Player"
            allKeys["Normal-Horde-Forever-Player"] = nil
        end

        local aliases = {}
        for k in pairs(allKeys) do
            if k ~= char and charEconomy(k) == econ and shortPlayerName(k, hostChars):lower() == targetShort then
                aliases[#aliases + 1] = k
            end
        end
        table.sort(aliases)
        for _, otherKey in ipairs(aliases) do
            if root.snaps and type(root.snaps[otherKey]) == "table" then
                local dstSnaps = ensure(ensure(root, "snaps"), char)
                for day, snap in pairs(root.snaps[otherKey]) do
                    if dstSnaps[day] == nil then dstSnaps[day] = snap end
                end
            end
            if root.lots and type(root.lots[otherKey]) == "table" then
                local dstCharLots = ensure(ensure(root, "lots"), char)
                for itemID, lots in pairs(root.lots[otherKey]) do
                    if type(lots) == "table" then
                        if not dstCharLots[itemID] then
                            dstCharLots[itemID] = lots
                        else
                            local seenAuction, seenSig = {}, {}
                            for _, l in ipairs(dstCharLots[itemID]) do
                                if type(l) == "table" then
                                    if l.auctionID then seenAuction[l.auctionID] = true end
                                    seenSig[tostring(l.postedAt or 0) .. "|" .. tostring(l.qty or 0) .. "|" .. tostring(l.unit or 0)] = true
                                end
                            end
                            for _, l in ipairs(lots) do
                                if type(l) == "table" then
                                    local sig = tostring(l.postedAt or 0) .. "|" .. tostring(l.qty or 0) .. "|" .. tostring(l.unit or 0)
                                    if (not l.auctionID or not seenAuction[l.auctionID]) and not seenSig[sig] then
                                        dstCharLots[itemID][#dstCharLots[itemID] + 1] = l
                                        if l.auctionID then seenAuction[l.auctionID] = true end
                                        seenSig[sig] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
            purgeKey(otherKey)
            removed[#removed + 1] = otherKey
        end
        return removed
    end

    function Inventory.SyncPortfolio(opts)
        if not writable() then return { ok = false, err = "store is read-only" } end
        opts = opts or {}
        local store = ns.Store
        local root = db()
        local hostDB = _G.MerchantMasterDB or {}
        local curChar, curEcon = "Normal-Horde-Forever-Player", "Normal-Horde"
        if store and store.CurrentCharAndEcon then curChar, curEcon = store.CurrentCharAndEcon() end
        local char = opts.char or curChar
        local econ = opts.econ or curEcon or charEconomy(char)
        local ts = tonumber(opts.now) or now()
        local bankOpen = (opts.bankOpen ~= nil) and (opts.bankOpen == true) or Inventory.IsBankOpen()

        local before = Inventory.AnalyzePortfolio({ char = char, econ = econ, bankOpen = bankOpen, now = ts, liveBags = opts.liveBags, liveBoundBags = opts.liveBoundBags, liveBank = opts.liveBank, liveBoundBank = opts.liveBoundBank, liveGear = opts.liveGear })
        local actions = {}

        -- 0. Migrate any unambiguous legacy single-word Forever character keys across LedgerDB & hostDB
        if store and store.MigrateForeverSurnames then
            local mCnt = store.MigrateForeverSurnames(hostDB.chars, char)
            if (tonumber(mCnt) or 0) > 0 then
                actions[#actions + 1] = string.format("Migrated %d legacy single-word Forever character key(s)", mCnt)
            end
        end

        -- 1. Authoritative live bag (+ gear) rescan into both DB.inventory and MerchantMasterDB.chars
        local h = host
        local hostChar = (h and h.app and h.app.charKey == char and h.app.char) or (hostDB.chars and hostDB.chars[char]) or nil
        local liveGear, liveGearSlots = scanLiveGearByID(opts)
        local function syncHostGear()
            if type(hostChar) ~= "table" or liveGearSlots <= 0 then return end
            if type(opts.liveGear) == "table" then
                local g = {}
                for id, q in pairs(liveGear or {}) do
                    if q > 0 then local nm = itemNameOf(id); g[nm] = (g[nm] or 0) + q end
                end
                hostChar.gear = g
            elseif h and h.app and h.app.scanGear then
                pcall(h.app.scanGear)
            end
        end
        if type(opts.liveBags) == "table" then
            Inventory.ScanCurrentChar({ char = char, econ = econ, bags = opts.liveBags, boundBags = opts.liveBoundBags or {}, gear = liveGear, skipGear = (liveGearSlots == 0) })
            syncHostGear()
            actions[#actions + 1] = liveGearSlots > 0 and "Rescanned live bags and gear into DB.inventory" or "Rescanned live bags into DB.inventory"
        else
            local bagNames, boundBagNames, bagIDs, boundBagIDs, bagSlots = scanLiveBagsByName()
            if bagSlots > 0 then
                Inventory.ScanCurrentChar({ char = char, econ = econ, bags = bagIDs, boundBags = boundBagIDs, gear = liveGear, skipGear = (liveGearSlots == 0) })
                if type(hostChar) == "table" then
                    hostChar.bags = bagNames
                    hostChar.boundBags = boundBagNames
                    syncHostGear()
                    if h and h.app then
                        h.app.bagCountsDirty = true
                        h.app.ownershipRev = (h.app.ownershipRev or 0) + 1
                    end
                end
                actions[#actions + 1] = "Rescanned live bags and gear"
            elseif liveGearSlots > 0 and liveGear then
                local inv = ensure(root, "inventory")
                local snap = inv[char] or { econ = econ, bags = {}, bank = {}, mail = {}, gear = {}, boundBags = {}, boundBank = {} }
                snap.gear = counts(liveGear); snap.updatedAt = ts; inv[char] = snap
                syncHostGear()
                actions[#actions + 1] = "Rescanned live equipped gear"
            end
        end

        -- 2. Live bank rescan ONLY when bank is verified open (NEVER wipe when closed!)
        if bankOpen then
            if type(opts.liveBank) == "table" then
                local inv = ensure(root, "inventory")
                local snap = inv[char] or { econ = econ, bags = {}, mail = {}, gear = {}, boundBags = {}, boundBank = {} }
                snap.bank = counts(opts.liveBank)
                snap.boundBank = counts(opts.liveBoundBank)
                snap.bankAt = ts; snap.updatedAt = ts; snap.econ = econ
                inv[char] = snap
                actions[#actions + 1] = "Rescanned live bank (Bank Open)"
            else
                local bankNames, boundBankNames, bankIDs, boundBankIDs, bankSlots = scanLiveBankByName()
                if bankSlots > 0 then
                    local inv = ensure(root, "inventory")
                    local snap = inv[char] or { econ = econ, bags = {}, mail = {}, gear = {}, boundBags = {}, boundBank = {} }
                    snap.bank = bankIDs
                    snap.boundBank = boundBankIDs
                    snap.bankAt = ts; snap.updatedAt = ts; snap.econ = econ
                    inv[char] = snap
                    if type(hostChar) == "table" then
                        hostChar.bank = bankNames
                        hostChar.boundBank = boundBankNames
                        if h and h.app then h.app.ownershipRev = (h.app.ownershipRev or 0) + 1 end
                    end
                    actions[#actions + 1] = "Rescanned live bank (Bank Open)"
                else
                    bankOpen = false
                    actions[#actions + 1] = "Preserved stored bank snapshot (bank slots unreadable)"
                end
            end
        else
            -- Backfill empty DB.inventory.bank from hostChar.bank without ever wiping
            local inv = ensure(root, "inventory")
            local snap = inv[char]
            if snap and (type(snap.bank) ~= "table" or next(snap.bank) == nil) and type(hostChar) == "table" and type(hostChar.bank) == "table" and next(hostChar.bank) ~= nil then
                snap.bank = resolveNameMapToIDs(hostChar.bank)
                snap.boundBank = resolveNameMapToIDs(hostChar.boundBank)
                actions[#actions + 1] = "Backfilled missing DB.inventory bank from host snapshot (Bank Closed)"
            else
                actions[#actions + 1] = "Preserved stored bank snapshot (Bank Closed)"
            end
        end

        -- 3. Remove alias/placeholder character keys and deduplicate DB.wealth + rebuild active char snapshot
        local removedAliases = cleanupAliasChars(root, hostDB, char, econ)
        if #removedAliases > 0 then
            actions[#actions + 1] = string.format("Merged and removed %d alias/placeholder character key(s): %s",
                #removedAliases, table.concat(removedAliases, ", "))
        end
        local mergedRows = 0
        for _, w in pairs(root.wealth or {}) do
            mergedRows = mergedRows + dedupeWealthTableInPlace(w)
        end
        if mergedRows > 0 then
            actions[#actions + 1] = string.format("Merged %d duplicate Wealth Breakdown row(s)", mergedRows)
        end
        if ns.Capture and ns.Capture.QueueWealthSnapshot and h and h.app and h.app.char and h.app.charKey == char then
            ns.Capture._snapshotSignature = nil
            pcall(ns.Capture.QueueWealthSnapshot, { sync = true, force = true })
            actions[#actions + 1] = "Rebuilt authoritative wealth snapshot"
        end

        -- 4. Prune expired/stuck inTransitMail and >52h stale open AH lots
        if opts.pruneTransit ~= false and type(root.inTransitMail) == "table" then
            local prunedTransit = 0
            local invSnap = root.inventory and root.inventory[char]
            for i = #root.inTransitMail, 1, -1 do
                local tr = root.inTransitMail[i]
                local expired = type(tr) == "table" and (tonumber(tr.expiresAt) or 0) <= ts
                local stuck = type(tr) == "table" and tr.toChar == char and invSnap and (tonumber(invSnap.mailAt) or 0) > (tonumber(tr.sentAt) or 0)
                if expired then
                    table.remove(root.inTransitMail, i)
                    prunedTransit = prunedTransit + 1
                elseif stuck then
                    local anyStillInMail = false
                    for id, qty in pairs(tr.items or {}) do
                        if (tonumber(qty) or 0) > 0 and invSnap.mail and (invSnap.mail[tonumber(id)] or 0) > 0 then
                            anyStillInMail = true; break
                        end
                    end
                    if not anyStillInMail then
                        table.remove(root.inTransitMail, i)
                        prunedTransit = prunedTransit + 1
                    end
                end
            end
            if prunedTransit > 0 then
                actions[#actions + 1] = string.format("Pruned %d expired/stuck in-transit mail entry(ies)", prunedTransit)
            end
        end

        if opts.pruneStaleLots ~= false and root.lots and root.lots[char] then
            local prunedLotUnits = 0
            for _, lots in pairs(root.lots[char]) do
                for i = #lots, 1, -1 do
                    local lot = lots[i]
                    local postedAt = tonumber(lot.postedAt) or 0
                    if postedAt > 0 and (ts - postedAt) > 52 * 3600 then
                        prunedLotUnits = prunedLotUnits + (tonumber(lot.qty) or 0)
                        table.remove(lots, i)
                    end
                end
            end
            if prunedLotUnits > 0 then
                if store and store.UpdateTodayListedSnap then store.UpdateTodayListedSnap(char) end
                actions[#actions + 1] = string.format("Pruned %d stale open AH lot unit(s) older than 52h", prunedLotUnits)
            end
        end

        -- 5. Optional basis qty alignment (preserves avg unit cost, never deletes trade history)
        local basisAdjusted = 0
        if opts.reconcileBasis == true then
            local invSnap = root.inventory and root.inventory[char]
            local hasBankKnowledge = bankOpen or (invSnap and (tonumber(invSnap.bankAt) or 0) > 0) or (type(hostChar) == "table" and type(hostChar.bank) == "table")
            if not hasBankKnowledge then
                actions[#actions + 1] = "Skipped basis qty alignment (open Bank once first so bank stock is known)"
            else
                local econBasis = root.basis and root.basis[econ] or {}
                local postSnap = Inventory.AnalyzePortfolio({ char = char, econ = econ, bankOpen = bankOpen, now = ts, liveBags = opts.liveBags, liveBoundBags = opts.liveBoundBags, liveBank = opts.liveBank, liveBoundBank = opts.liveBoundBank, liveGear = opts.liveGear })
                for id, diff in pairs(postSnap.basisDiffs or {}) do
                    local b = econBasis[id]
                    if b and (tonumber(b.qty) or 0) > diff.physQty then
                        local drop = (tonumber(b.qty) or 0) - diff.physQty
                        local savedAvg = tonumber(b.avg) or 0
                        if drop > 0 then
                            local costRemoved = math.floor(drop * savedAvg + 0.5)
                            b.qty = diff.physQty
                            b.avg = b.qty > 0 and savedAvg or 0
                            root.basisEvents = type(root.basisEvents) == "table" and root.basisEvents or {}
                            root.stats = type(root.stats) == "table" and root.stats or {}
                            root.stats.nextReplayOrder = (tonumber(root.stats.nextReplayOrder) or 0) + 1
                            root.basisEvents[#root.basisEvents + 1] = {
                                time = ts,
                                econ = econ,
                                itemID = id,
                                qty = -drop,
                                paid = -costRemoved,
                                known = drop,
                                order = root.stats.nextReplayOrder,
                                portfolioSync = true,
                            }
                            basisAdjusted = basisAdjusted + 1
                        end
                    end
                end
                if basisAdjusted > 0 then
                    actions[#actions + 1] = string.format("Aligned ledger basis qty on %d item(s) (preserved unit avg cost)", basisAdjusted)
                end
            end
        end

        Inventory.version = Inventory.version + 1
        if store then
            store.version = (store.version or 1) + 1
            if basisAdjusted > 0 then
                store.accountingVersion = (store.accountingVersion or 1) + 1
                store._trackedAccountingVersion = store.accountingVersion
            end
        end
        if ns.Model and ns.Model.Invalidate then ns.Model.Invalidate() end
        local after = Inventory.AnalyzePortfolio({ char = char, econ = econ, bankOpen = bankOpen, now = ts, liveBags = opts.liveBags, liveBoundBags = opts.liveBoundBags, liveBank = opts.liveBank, liveBoundBank = opts.liveBoundBank, liveGear = opts.liveGear })

        local stats = ensure(root, "stats")
        local auditLog = ensure(stats, "portfolioAuditLog")
        local auditEntry = {
            at = ts,
            char = char,
            econ = econ,
            bankOpen = bankOpen,
            reconcileBasis = opts.reconcileBasis == true,
            beforeIssues = before.summary.totalIssues,
            afterIssues = after.summary.totalIssues,
            mergedRows = mergedRows,
            removedAliases = removedAliases,
            basisAdjusted = basisAdjusted,
            actions = actions,
        }
        auditLog[#auditLog + 1] = auditEntry
        while #auditLog > 25 do table.remove(auditLog, 1) end

        local summaryLines = {
            string.format("Sync Complete (%s)  |  Issues: %d -> %d", bankOpen and "Bank Open" or "Bank Closed", before.summary.totalIssues, after.summary.totalIssues),
            "Actions taken:",
        }
        for _, a in ipairs(actions) do summaryLines[#summaryLines + 1] = "  - " .. a end
        summaryLines[#summaryLines + 1] = ""
        summaryLines[#summaryLines + 1] = after.text

        return {
            ok = true,
            before = before,
            after = after,
            actions = actions,
            auditEntry = auditEntry,
            summaryText = table.concat(summaryLines, "\n"),
        }
    end
end

return Inventory

