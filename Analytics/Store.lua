local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
_G.MerchantMasterAnalytics = ns
local function H()
    return host
end

local Store = {}; ns.Store = Store; Store.version = 1; Store.accountingVersion = 1; Store.ahSalesVersion = 1; Store.craftYieldVersion = 1; Store.craftYieldResetVersion = 1; Store.craftYieldLog = {}; Store._trackedAccountingVersion = 1
local ahOutcomeTypes = { AH_SELL = true, AH_EXPIRE = true, AH_POST = true, AH_CANCEL = true }
Store.ARCHIVE_DAY="1970-01-01"
local function secret(v)
    return (_G.issecretvalue and _G.issecretvalue(v)) or (type(v)=="table" and _G.issecrettable and _G.issecrettable(v))
end
local function nowSec()
    local t; if _G.time then t=_G.time() elseif os and os.time then t=os.time() end
    if secret(t) then return 0 end; return tonumber(t) or 0
end
local function fmtDate(fmt, t)
    local df=_G.date or (os and os.date); local value=df and df(fmt,t)
    return not secret(value) and value or "1970-01-01"
end
local DB
local unpackedCache = {}
local suffixedNameIndex = {}
Store.suffixedNameIndex = suffixedNameIndex
function Store.IndexItemName(name, id)
    if secret(name) or secret(id) then return end
    if type(name) ~= "string" or name == "" then return end
    local numID = tonumber(id)
    if not numID or numID <= 0 then return end
    suffixedNameIndex[name] = numID
end
local floor, max, min = math.floor, math.max, math.min
local type, tostring, tonumber = type, tostring, tonumber
local strsub, strfind, tconcat = string.sub, string.find, table.concat
local function ensure(t, k) if not t[k] then t[k] = {} end; return t[k] end
local function copy(t)
    if type(t)~="table" then return t end
    local out={}; for k,v in pairs(t) do if k~="_lot" then out[k]=copy(v) end end; return out
end
local function changed(row,kind,salesChanged)
    Store.version = Store.version + 1
    if kind~="snapshot" then
        Store.accountingVersion=Store.accountingVersion+1
        Store._trackedAccountingVersion=Store.accountingVersion
        if kind=="craft_yield" then
            Store.craftYieldVersion=(Store.craftYieldVersion or 1)+1
        end
        if salesChanged==true or (salesChanged~=false and kind~="loot" and kind~="basis" and (row==nil or ahOutcomeTypes[row.type])) then
            Store.ahSalesVersion=(Store.ahSalesVersion or 1)+1
        end
    end
    if Store.onChange then pcall(Store.onChange,row,kind or "accounting") end
end
local rollFields = { "sold", "gross", "fee", "cogs", "estUnits", "bought", "spent", "posted", "cancelled", "expired", "depLost", "looted", "dtSum", "dtUnits", "relisted", "repriced" }
Store.ROLL_FIELDS = rollFields
Store.TYPES = {}
for _, k in ipairs({ "AH_BUY", "AH_POST", "AH_SELL", "AH_CANCEL", "AH_EXPIRE", "VENDOR_BUY", "VENDOR_SELL", "CRAFT", "WRIT_TURNIN", "CRATE_TURNIN", "POUCH_MONEY", "QUEST_MONEY", "FAVOR_GAIN", "FAVOR_SPEND", "STANDING", "ADJUST" }) do Store.TYPES[k] = true end
Store.TYPE_GROUPS = {
    all = {}, buys = { AH_BUY=true, VENDOR_BUY=true }, sells = { AH_SELL=true, VENDOR_SELL=true },
    auctions = { AH_BUY=true, AH_POST=true, AH_SELL=true, AH_CANCEL=true, AH_EXPIRE=true },
    vendor = { VENDOR_BUY=true, VENDOR_SELL=true, FAVOR_SPEND=true }, loot = { LOOT=true, GATHER=true, MONEY_LOOT=true },
    craft = { CRAFT=true }, quests = { WRIT_TURNIN=true, CRATE_TURNIN=true, POUCH_MONEY=true, QUEST_MONEY=true, STANDING=true },
    favor = { CRATE_TURNIN=true, FAVOR_GAIN=true, FAVOR_SPEND=true },
}
for k in pairs(Store.TYPES) do Store.TYPE_GROUPS.all[k] = true end
for k in pairs(Store.TYPE_GROUPS.loot) do Store.TYPE_GROUPS.all[k] = true end
local buyTypes={AH_BUY=true,VENDOR_BUY=true,COD_BUY=true,TRADE_BUY=true,VENDOR_BUYBACK=true}
local sellTypes={AH_SELL=true,VENDOR_SELL=true,COD_SELL=true,TRADE_SELL=true}
for group,types in pairs({buys={"COD_BUY","TRADE_BUY","VENDOR_BUYBACK"},sells={"COD_SELL","TRADE_SELL"},
    vendor={"REPAIR","VENDOR_BUYBACK","TRAINER_FEE"},expenses={"REPAIR","POSTAGE","TRAINER_FEE"},mail={"POSTAGE","MONEY_TRANSFER","COD_BUY","COD_SELL","AH_OUTBID"},
    transfers={"MONEY_TRANSFER","GUILD_DEPOSIT","GUILD_WITHDRAW"},trade={"TRADE_BUY","TRADE_SELL"},craft={"DESTROY","DISENCHANT_BROKEN","DISENCHANT_RECEIVE"},other={"OTHER_INCOME","OTHER_EXPENSE","GUILD_DEPOSIT","GUILD_WITHDRAW"},auctions={"AUCTION_LOG","AH_BID","AH_OUTBID"}}) do
    for _,typ in ipairs(types) do Store.TYPES[typ]=true; Store.TYPE_GROUPS.all[typ]=true; ensure(Store.TYPE_GROUPS,group)[typ]=true end
end
function Store.MatchesTypeGroup(rowType, groupKey)
    if not groupKey or groupKey == "all" then return not not (Store.TYPE_GROUPS.all[rowType]) end
    if rowType == groupKey and Store.TYPES[rowType] then return true end
    return not not ((Store.TYPE_GROUPS[groupKey] or {})[rowType])
end
function Store.Now() return nowSec() end
function Store.DayKey(t) return fmtDate("%Y-%m-%d", t or Store.Now()) end
function Store.DeriveEcon(char, fallback)
    return type(char) == "string" and (char:match("^([^%-]+%-[^%-]+)%-") or char:match("^([^%-]+)%-")) or fallback or "Normal-Horde"
end
function Store.CurrentCharAndEcon()
    local h = H(); local char = h and h.app and h.app.charKey
    if not char then return "Normal-Horde-Forever-Player", "Normal-Horde" end
    local econ=h.DetectActiveEconomy and h.DetectActiveEconomy()
    if secret(econ) then econ=nil end
    return char, econ or Store.DeriveEcon(char)
end
function Store.Init()
    local prevDB = DB
    unpackedCache = {}
    suffixedNameIndex = {}
    Store.suffixedNameIndex = suffixedNameIndex
    DB = _G.MerchantMasterLedgerDB
    if type(DB) ~= "table" then DB = {}; _G.MerchantMasterLedgerDB = DB end
    Store.db = DB; Store.initialized = true; Store.readOnly = nil
    if prevDB ~= nil and prevDB ~= DB then
        Store.version = (Store.version or 1) + 1
        Store.accountingVersion = (Store.accountingVersion or 1) + 1
        Store._trackedAccountingVersion = Store.accountingVersion
        Store.ahSalesVersion = (Store.ahSalesVersion or 1) + 1
        Store.craftYieldVersion = (Store.craftYieldVersion or 1) + 1
        Store.craftYieldResetVersion = (Store.craftYieldResetVersion or 1) + 1
        Store.craftYieldLog = {}
        if ns.Model and ns.Model.Invalidate then ns.Model.Invalidate() end
    end
    if (tonumber(DB.schema) or 0)>1 then Store.readOnly = true; return DB end
    DB.schema = 1
    DB.subSchema=2
    for _, k in ipairs({ "days", "roll", "loot", "basis", "lots", "ret", "pouches", "snaps", "wealth", "seenMail", "stats", "seed", "probe", "dayStats", "itemStats", "craftYieldStats", "guildSnaps", "warbankSnaps", "archivedRoll", "archivedLoot", "archivedDays", "basisEvents" }) do ensure(DB, k) end
    DB.itemMeta=DB.itemStats
    for _, k in ipairs({ "firstLive", "errors", "disabled", "recon", "lastStanding", "chars", "zones", "tsmSyncedSales", "importedOrigins" }) do ensure(DB.stats, k) end
    DB.stats.favorCostSum = DB.stats.favorCostSum or 0; DB.stats.favorGainSum = DB.stats.favorGainSum or 0
    if DB.probe.enabled == nil then DB.probe.enabled = false end
    ensure(DB.probe, "log")
    if (tonumber(DB.rollupSchema) or 0) < 3 then
        -- Backfill only retained days; archived and roll-only history has no raw evidence.
        Store.IterDays(nil,nil,function(day,rows)
            for _,items in pairs(DB.roll[day] or {}) do for _,r in pairs(items) do r.ahSold=nil end end
            for _,row in ipairs(rows) do if row.type=="AH_SELL" then
                local r=ensure(ensure(ensure(DB.roll,day),row.char),row.itemID)
                r.ahSold=(r.ahSold or 0)+(tonumber(row.qty) or 0)
            end end
        end)
        DB.rollupSchema=3
    end
    if not DB.replayBase and next(DB.days)==nil then
        DB.replayBase={basis=copy(DB.basis),lots=copy(DB.lots),ret=copy(DB.ret),pouches=copy(DB.pouches),itemStats=copy(DB.itemStats),favorCostSum=DB.stats.favorCostSum,favorGainSum=DB.stats.favorGainSum}
    elseif not DB.replayBase and Store.EnsureReplayBase then
        Store.EnsureReplayBase()
    end
    return DB
end
local function writable() if not DB then Store.Init() end; return not Store.readOnly end
local function replayOrder()
    DB.stats.nextReplayOrder=(DB.stats.nextReplayOrder or 0)+1; return DB.stats.nextReplayOrder
end
local function roll(day, char, id)
    local r = ensure(ensure(ensure(DB.roll, day), char), id)
    for _, k in ipairs(rollFields) do r[k] = r[k] or 0 end
    return r
end
function Store.Roll(day) return DB and DB.roll[day] or {} end
function Store.Basis(econ, itemID)
    local b = DB and DB.basis and DB.basis[econ] and DB.basis[econ][itemID]
    return b and b.qty or 0, b and b.avg or 0
end
function Store.AddBasis(econ, itemID, addQty, paid)
    if not writable() or itemID <= 0 or addQty <= 0 then return end
    if not Store._appending and not Store._replaying then DB.basisEvents[#DB.basisEvents+1]={time=Store._basisTime or Store.Now(),econ=econ,itemID=itemID,qty=addQty,paid=paid,order=replayOrder()} end
    local b = ensure(ensure(DB.basis, econ), itemID)
    local old = b.qty or 0; local qty = old + addQty
    b.avg = ((b.avg or 0) * old + paid) / qty; b.qty = qty
    if not Store._appending and not Store._replaying then changed(nil,"basis") end
end
function Store.ConsumeBasis(econ, itemID, takeQty)
    if not writable() then return 0, takeQty end
    local event
    if not Store._appending and not Store._replaying then event={time=Store.Now(),econ=econ,itemID=itemID,qty=-takeQty,order=replayOrder()}; DB.basisEvents[#DB.basisEvents+1]=event end
    local b = ensure(ensure(DB.basis, econ), itemID)
    local known = min(max(0, takeQty), b.qty or 0)
    local cost = floor(known * (b.avg or 0) + 0.5)
    if event then event.paid=-cost; event.known=known end
    b.qty = (b.qty or 0) - known; if b.qty <= 0 then b.avg = 0 end
    if not Store._appending and not Store._replaying and known>0 then changed(nil,"basis") end
    return cost, max(0, takeQty - known)
end
function Store.Lots(char, itemID)
    local lots = DB and DB.lots and DB.lots[char] or {}
    if itemID == nil then return lots end
    return lots[itemID] or {}
end
function Store.UpdateTodayListedSnap(char)
    if not writable() or not char then return end
    local snaps = DB.snaps and DB.snaps[char]
    local snap = snaps and snaps[Store.DayKey()]
    if not snap then return end
    local total = 0
    for _, lots in pairs(Store.Lots(char)) do
        for _, lot in ipairs(lots) do total = total + (lot.qty or 0) * (lot.unit or 0) end
    end
    snap.listed = total
end
function Store.PostLot(char, econ, itemID, qty, unitBuyout, deposit, postedAt, name, auctionID, baseName)
    if not writable() then return 0, 0 end
    postedAt = postedAt or Store.Now()
    local pool = ensure(ensure(DB.ret, char), itemID)
    local left, relisted, repriced = qty, 0, 0
    while left > 0 and #pool > 0 do
        local entry = pool[1]; local take = min(left, entry.qty)
        if entry.reason == "cancel" and postedAt - entry.at <= 3600 then repriced = repriced + take else relisted = relisted + take end
        left = left - take; entry.qty = entry.qty - take
        if entry.qty <= 0 then table.remove(pool, 1) end
    end
    local lots = ensure(ensure(DB.lots, char), itemID)
    local validBase = (type(baseName) == "string" and baseName ~= "") and baseName or nil
    local lot = { qty=qty, unit=unitBuyout or 0, deposit=deposit or 0, postedAt=postedAt, name=name, auctionID=auctionID, baseName=validBase }
    lots[#lots+1] = lot
    if tonumber(itemID) and tonumber(itemID) > 0 then
        if name and name ~= "" then Store.IndexItemName(name, itemID) end
        if validBase then Store.IndexItemName(validBase, itemID) end
    end
    Store.UpdateTodayListedSnap(char)
    if not Store._appending and not Store._replaying then changed() end
    return relisted, repriced, lot
end
function Store.CloseUnits(char, itemID, qty, reason, atTime, opts)
    if not writable() then return 0, 0, 0 end
    atTime = atTime or Store.Now(); opts = opts or {}
    local lots = Store.Lots(char, itemID); local left, matched, dep, dt = max(0, qty), 0, 0, 0
    local function pickLotIndex()
        if opts.auctionID then
            for i, lot in ipairs(lots) do if lot.auctionID == opts.auctionID then return i end end
            local hasUnassigned = false
            for _, lot in ipairs(lots) do if lot.auctionID == nil then hasUnassigned = true; break end end
            if not hasUnassigned then return nil end
        end
        if reason == "sell" then
            if opts.name and opts.name ~= "" then
                if opts.unit and opts.unit > 0 then
                    for i, lot in ipairs(lots) do if lot.name == opts.name and lot.unit == opts.unit and (not opts.auctionID or lot.auctionID == nil) then return i end end
                end
                for i, lot in ipairs(lots) do if lot.name == opts.name and (not opts.auctionID or lot.auctionID == nil) then return i end end
            end
            if opts.unit and opts.unit > 0 then
                for i, lot in ipairs(lots) do if lot.unit == opts.unit and (not opts.auctionID or lot.auctionID == nil) then return i end end
            end
        elseif reason == "cancel" and opts.unit and opts.unit > 0 then
            for i = #lots, 1, -1 do if lots[i].unit == opts.unit and lots[i].qty == left and (not opts.auctionID or lots[i].auctionID == nil) then return i end end
            for i = #lots, 1, -1 do if lots[i].unit == opts.unit and (not opts.auctionID or lots[i].auctionID == nil) then return i end end
            for i = #lots, 1, -1 do if (lots[i].unit or 0) == 0 and (not opts.auctionID or lots[i].auctionID == nil) then return i end end
            return nil
        end
        for i, lot in ipairs(lots) do if not opts.auctionID or lot.auctionID == nil then return i end end
        return nil
    end
    while left > 0 and #lots > 0 do
        local idx = pickLotIndex(); if not idx then break end
        local lot = lots[idx]; local take = min(left, lot.qty)
        local slice = lot.qty > 0 and floor((lot.deposit or 0) * take / lot.qty + 0.5) or 0
        dep = dep + slice; matched = matched + take; left = left - take
        if reason == "sell" then dt = dt + take * max(0, atTime - (lot.postedAt or atTime)) end
        lot.deposit = (lot.deposit or 0) - slice; lot.qty = lot.qty - take
        if lot.qty <= 0 then table.remove(lots, idx) end
    end
    if (reason == "cancel" or reason == "expire") and qty > 0 then
        local pool = ensure(ensure(DB.ret, char), itemID); pool[#pool+1] = { qty=qty, at=atTime, reason=reason }
    end
    Store.UpdateTodayListedSnap(char)
    if not Store._appending and not Store._replaying and matched>0 then changed() end
    return matched, dep, dt
end
function Store.PruneMissingLots(char, activeAuctionIDs, activeCountsByItem, maxPostedAt)
    if not writable() or not char or not DB.lots or not DB.lots[char] then return 0 end
    local pruned = 0
    maxPostedAt = maxPostedAt or (Store.Now() - 60)
    if not Store._appending and not Store._replaying then
        DB.basisEvents[#DB.basisEvents+1]={time=Store.Now(),order=replayOrder(),pruneLots=true,char=char,activeIDs=copy(activeAuctionIDs),activeCounts=copy(activeCountsByItem),maxPostedAt=maxPostedAt}
    end
    for itemID, lots in pairs(DB.lots[char]) do
        for i = #lots, 1, -1 do
            local lot = lots[i]
            if (lot.postedAt or 0) <= maxPostedAt and lot.auctionID and not activeAuctionIDs[lot.auctionID] then
                pruned = pruned + (lot.qty or 0)
                table.remove(lots, i)
            end
        end
        local recentQty, oldQty = 0, 0
        for _, lot in ipairs(lots) do
            if (lot.postedAt or 0) > maxPostedAt then recentQty = recentQty + (lot.qty or 0)
            else oldQty = oldQty + (lot.qty or 0) end
        end
        local allowedOld = max(0, (activeCountsByItem[itemID] or 0) - recentQty)
        local excess = oldQty - allowedOld
        while excess > 0 and #lots > 0 do
            local idx
            for i, lot in ipairs(lots) do if (lot.postedAt or 0) <= maxPostedAt then idx = i; break end end
            if not idx then break end
            local lot = lots[idx]; local take = min(excess, lot.qty or 0)
            local slice = (lot.qty or 0) > 0 and floor((lot.deposit or 0) * take / lot.qty + 0.5) or 0
            lot.deposit = max(0, (lot.deposit or 0) - slice)
            lot.qty = (lot.qty or 0) - take
            excess = excess - take; pruned = pruned + take
            if lot.qty <= 0 then table.remove(lots, idx) end
        end
    end
    if pruned > 0 then Store.UpdateTodayListedSnap(char); changed() end
    return pruned
end
local function resolveExactItemIDByName(char, name)
    if secret(name) or type(name) ~= "string" or name == "" then return 0 end
    local indexed = suffixedNameIndex[name]
    if indexed and indexed > 0 then return indexed end
    local lotBaseMatch = 0
    for id, lots in pairs(Store.Lots(char)) do
        for _, lot in ipairs(lots) do
            if lot.name == name then return id end
            if lotBaseMatch == 0 and type(lot.baseName) == "string" and lot.baseName == name then
                lotBaseMatch = id
            end
        end
    end
    local h, db = H(), _G.MerchantMasterDB
    local found = (h and h.ITEM_IDS_BY_NAME and h.ITEM_IDS_BY_NAME[name]) or (db and db.itemIDs and db.itemIDs[name])
    if not found and _G.C_Item and _G.C_Item.GetItemInfoInstant then
        found=_G.C_Item.GetItemInfoInstant(name); if secret(found) then return 0 end
    end
    if not found and _G.GetItemInfoInstant then found=_G.GetItemInfoInstant(name); if secret(found) then return 0 end end
    if not secret(found) and tonumber(found) and tonumber(found) > 0 then return tonumber(found) end
    if lotBaseMatch > 0 then return lotBaseMatch end
    return 0
end
function Store.ResolveItemIDByName(char, name)
    if secret(name) or type(name) ~= "string" or name == "" then return 0 end
    local exact = resolveExactItemIDByName(char, name)
    if exact > 0 then return exact end
    -- Random-enchant fallback: strip " of ..." / " of the ..." suffix only after exact lookup misses,
    -- so real base items containing "of" (e.g. "Flask of Supreme Power") resolve cleanly via exact match first.
    local baseLast = name:match("^(.+)%s+of%s+")
    if baseLast and baseLast ~= "" then
        baseLast = baseLast:gsub("%s+$", "")
        local resolved = resolveExactItemIDByName(char, baseLast)
        if resolved > 0 then
            Store.IndexItemName(name, resolved)
            return resolved
        end
    end
    local baseFirst = name:match("^(.-)%s+of%s+")
    if baseFirst and baseFirst ~= "" then
        baseFirst = baseFirst:gsub("%s+$", "")
        if baseFirst ~= baseLast then
            local resolved = resolveExactItemIDByName(char, baseFirst)
            if resolved > 0 then
                Store.IndexItemName(name, resolved)
                return resolved
            end
        end
    end
    return 0
end
local function evaluate(fn)
    local h = H(); if not h then return 0 end
    if h.BeginEval then h.BeginEval(h.app and h.app.getUIPriceBank and h.app.getUIPriceBank()) end
    local ok, value = pcall(fn, h)
    if h.EndEval then h.EndEval() end
    if ok and not secret(value) then return tonumber(value) or 0 end
    return 0
end
function Store.EstimateCraftOrMarketCost(itemID)
    return evaluate(function(h)
        local list = h.RECIPES_BY_OUTPUT and h.RECIPES_BY_OUTPUT[itemID]
        local rec = list and (list.reagents and list or list[1])
        local cost = rec and h.ComputeCraftCost and h.ComputeCraftCost(rec.reagents, rec.numMade, itemID)
        if secret(cost) then return 0 end
        if cost~=nil then return cost end
        if h.GetItemMarketPrice then cost=h.GetItemMarketPrice(itemID); if secret(cost) then return 0 end end
        if cost~=nil then return cost end
        if h.GetVendorSellPrice then cost=h.GetVendorSellPrice(itemID); if secret(cost) then return 0 end end
        return cost or 0
    end)
end
local function consumeCost(econ, id, qty, marketOnly)
    id, qty = tonumber(id) or 0, tonumber(qty) or 0
    if id <= 0 or qty <= 0 then return 0, 0 end
    local cost, missing = Store.ConsumeBasis(econ, id, qty)
    if missing>0 then
        local unit
        if marketOnly then unit=evaluate(function(h)
            local value=h.GetItemMarketPrice and h.GetItemMarketPrice(id)
            if secret(value) then return 0 end
            if value~=nil then return value end
            if h.GetVendorSellPrice then value=h.GetVendorSellPrice(id); if secret(value) then return 0 end end
            return value or 0
        end)
        else unit=Store.EstimateCraftOrMarketCost(id) end
        cost=cost+floor(missing*unit+0.5)
    end
    return cost, missing
end
function Store.GetRunningFavorPrice()
    if DB and DB.stats and (DB.stats.favorGainSum or 0) > 0 then return max(0, DB.stats.favorCostSum / DB.stats.favorGainSum) end
    return 0
end
local function popPouch(char, econ, tier)
    local pools = DB.pouches[char]; local pool = pools and pools[tier]
    if pool and #pool > 0 then return table.remove(pool, 1) end
    local oldest, owner
    for c, tiers in pairs(DB.pouches) do
        local p = tiers[tier]
        if Store.DeriveEcon(c) == econ and p and p[1] and (not oldest or p[1].at < oldest.at) then oldest, owner = p[1], p end
    end
    if owner then return table.remove(owner, 1) end
end
local function dailyStats(row, day)
    local d = ensure(ensure(DB.dayStats, day), row.char)
    local function add(k, n) d[k] = (d[k] or 0) + (tonumber(n) or 0) end
    local typ, e = row.type, row.extra
    if sellTypes[typ] then
        local fee = tonumber(e.fee) or 0; local gross = tonumber(e.gross) or max(0, row.total+fee)
        add("salesGross", gross); add("profitDelta", gross - fee - (row.cogs or 0))
    elseif buyTypes[typ] then add("buySpent", math.abs(row.total))
    elseif typ == "AH_CANCEL" or typ == "AH_EXPIRE" then add("depLost", e.depLost); add("profitDelta", -(e.depLost or 0))
    elseif typ == "DISENCHANT_BROKEN" then
        local estVal = tonumber(e.estValue) or 0
        if estVal > 0 then add("profitDelta", estVal - (row.cogs or 0)) end
    elseif typ == "ADJUST" then add("adjustTotal", row.total)
    elseif typ == "WRIT_TURNIN" then
        add("writCost", row.cogs); add("writQuestCash", row.total); add("writRep", e.rep); add("writsDone", row.qty)
        local tier = e.pouchTier
        if not tier and ns.Model and ns.Model.GetIndexes then local w = ns.Model.GetIndexes().WRIT_BY_ITEM[row.itemID]; tier = w and w.tier end
        if not tier then local h = H(); if h and h.WRITS then for _, w in ipairs(h.WRITS) do if w.itemID == row.itemID then tier = w.tier; break end end end end
        if tier then local td = ensure(ensure(d, "tiers"), tier); td.writs=(td.writs or 0)+row.qty; td.cost=(td.cost or 0)+(row.cogs or 0); td.cash=(td.cash or 0)+row.total; td.rep=(td.rep or 0)+(e.rep or 0) end
    elseif typ == "POUCH_MONEY" then
        add("pouchCash", row.total)
        local tier = e.tier or row.ref
        if tier then local td=ensure(ensure(d,"tiers"),tier); td.refund=(td.refund or 0)+row.total end
    elseif typ == "CRATE_TURNIN" then add("crateCost", row.cogs); add("crateCash", max(0,row.total)); add("favorGained", e.favor); add("cratesDone", row.qty)
    elseif typ == "FAVOR_GAIN" then add("favorGained", tonumber(e.favor) or row.qty) end
end
local function itemMeta(row)
    if row.itemID<=0 then return end
    local e=row.extra; local meta=ensure(ensure(DB.itemStats,row.econ),row.itemID)
    local function update(m)
        if buyTypes[row.type] then
            local u=row.qty>0 and math.abs(row.total)/row.qty or row.unit
            m.minBuy=min(m.minBuy or u,u); m.maxBuy=max(m.maxBuy or u,u)
            if row.time>=(m.lastBuyTs or 0) then m.lastBuyTs=row.time; m.lastBuyUnit=u; m.lastBuyFrom=e.seller or e.counterparty end
        elseif sellTypes[row.type] then
            local u=row.qty>0 and (tonumber(e.gross) or (row.total+(tonumber(e.fee) or 0)))/row.qty or row.unit
            m.minSell=min(m.minSell or u,u); m.maxSell=max(m.maxSell or u,u)
            if row.time>=(m.lastSoldTs or 0) then
                m.lastSoldTs=row.time; m.lastSoldUnit=u; m.lastSoldTo=e.buyer or e.counterparty
                m.expSinceSale=0; m.canSinceSale=0
            end
        elseif row.time>=(m.lastSoldTs or 0) then
            if row.type=="AH_EXPIRE" then m.expSinceSale=(m.expSinceSale or 0)+row.qty
            elseif row.type=="AH_CANCEL" then m.canSinceSale=(m.canSinceSale or 0)+row.qty end
        end
    end
    update(meta)
    local variant=e.itemString or e.variant
    if variant then update(ensure(ensure(meta,"variants"),variant)) end
end
function Store.EventID(row,day,index)
    return row.extra and row.extra.eid or ((day or Store.DayKey(row.time))..":"..tostring(index or 0))
end
function Store.Append(row)
    if not writable() or type(row) ~= "table" or not Store.TYPES[row.type] then return nil end
    for _,k in ipairs({"time","itemID","qty","unit","total","cogs"}) do
        local n=row[k]~=nil and tonumber(row[k])
        if row[k]~=nil and (not n or n~=n or n==math.huge or n==-math.huge) then return nil end
    end
    if type(row.extra)=="table" then for _,k in ipairs({"rep","gross","fee","deposit","depositReturned","saleAt","estUnits","unitPrice","reagentCost","bundleCost","favor","favorCopperValue","reqItemID","reqQty","replayOrder","spellID","casts"}) do
        local v=row.extra[k]; if v~=nil and (type(v)~="number" or v~=v or v==math.huge or v==-math.huge) then return nil end
    end end
    local perfT0 = (host._consolePerfOn == true and _G.debugprofilestop) and _G.debugprofilestop() or nil
    local curChar, curEcon = Store.CurrentCharAndEcon()
    row.time = tonumber(row.time) or Store.Now(); row.char = row.char or curChar; row.econ = row.econ or Store.DeriveEcon(row.char, curEcon)
    row.itemID=tonumber(row.itemID) or 0; row.qty=tonumber(row.qty) or 0; row.unit=tonumber(row.unit) or 0
    row.total=floor((tonumber(row.total) or 0)+0.5); row.where=tostring(row.where or ""); row.ref=row.ref and tostring(row.ref) or nil
    row.extra=type(row.extra)=="table" and row.extra or {}; row.cogs=tonumber(row.cogs)
    local day, char, econ, id, qty, total, typ, e = Store.DayKey(row.time), row.char, row.econ, row.itemID, row.qty, row.total, row.type, row.extra
    if not e.eid then DB.stats.nextEventID=(DB.stats.nextEventID or 0)+1; e.eid=day..":e"..DB.stats.nextEventID end
    if not e.replayOrder then e.replayOrder=replayOrder() end
    if typ=="AUCTION_LOG" then e.nonCash=true; if total~=0 then e.logAmount=total end; row.total=0; total=0 end
    Store._appending=true
    DB.stats.chars[char] = true
    if row.where ~= "" then DB.stats.zones[row.where] = true end
    local skipRecon = row.skipRecon == true; row.skipRecon = nil
    if skipRecon then e.reconSkip=true end
    local isHistorical = (e.tsm ~= nil and e.tsm ~= false)
    local firstChanged = false
    if not isHistorical then
        local prevFirst = DB.stats.firstLive[char]
        DB.stats.firstLive[char] = min(prevFirst or row.time, row.time)
        firstChanged = (DB.stats.firstLive[char] ~= prevFirst)
        if typ ~= "ADJUST" and not skipRecon and not e.reconSkip and not e.nonCash then local recon=ensure(DB.stats.recon,char); recon.recorded=(recon.recorded or 0)+total end
    end
    local r = roll(day,char,id)
    if not row.skipLifecycle then
        if isHistorical then
            if buyTypes[typ] then
                r.bought=r.bought+qty; r.spent=r.spent+math.abs(total)
            elseif sellTypes[typ] then
                local fee=tonumber(e.fee) or 0; local gross=tonumber(e.gross) or max(0,total+fee)
                r.sold=r.sold+qty; r.gross=r.gross+gross; r.fee=r.fee+fee; r.cogs=r.cogs+(row.cogs or 0); r.estUnits=r.estUnits+(tonumber(e.estUnits) or 0)
                if typ=="AH_SELL" then r.ahSold=(r.ahSold or 0)+qty end
            elseif typ == "AH_CANCEL" then r.cancelled=r.cancelled+qty
            elseif typ == "AH_EXPIRE" then r.expired=r.expired+qty end
        elseif buyTypes[typ] then
            if id > 0 and qty > 0 then Store.AddBasis(econ,id,qty,math.abs(total)) end
            r.bought=r.bought+qty; r.spent=r.spent+math.abs(total)
        elseif typ == "AH_POST" then
            if id > 0 and qty > 0 then
                local lotBase = (e.variant ~= nil and type(e.baseName) == "string" and e.baseName ~= "") and e.baseName or nil
                local relisted, repriced, lot=Store.PostLot(char,econ,id,qty,row.unit,max(0,-total),row.time,e.name,e.auctionID,lotBase)
                row._lot=lot
                r.posted=r.posted+qty; r.relisted=r.relisted+relisted; r.repriced=r.repriced+repriced
                e.relisted=relisted>0 and relisted or nil; e.repriced=repriced>0 and repriced or nil
            end
        elseif sellTypes[typ] then
            local fee=tonumber(e.fee) or 0; local gross=tonumber(e.gross) or max(0,total+fee)
            if typ=="AH_SELL" then local matched, _, dt=Store.CloseUnits(char,id,qty,"sell",tonumber(e.saleAt) or row.time,{unit=row.unit,name=e.name}); r.dtSum=r.dtSum+dt; r.dtUnits=r.dtUnits+matched end
            if (row.cogs==nil or e.recomputeCost) and id>0 and qty>0 then
                local cost,missing=consumeCost(econ,id,qty); row.cogs=cost
                e.autoCost=true; e.recomputeCost=nil
                if missing>0 then e.est=1; e.estUnits=missing end
            end
            r.sold=r.sold+qty; r.gross=r.gross+gross; r.fee=r.fee+fee; r.cogs=r.cogs+(row.cogs or 0); r.estUnits=r.estUnits+(tonumber(e.estUnits) or 0)
            if typ=="AH_SELL" then r.ahSold=(r.ahSold or 0)+qty end
        elseif typ=="AH_CANCEL" or typ=="AH_EXPIRE" then
            local _,dep=Store.CloseUnits(char,id,qty,typ=="AH_CANCEL" and "cancel" or "expire",row.time,{auctionID=e.auctionID,unit=e.unitPrice or row.unit})
            if typ=="AH_CANCEL" then dep=dep+max(0,-total); r.cancelled=r.cancelled+qty else r.expired=r.expired+qty end
            e.depLost=dep; r.depLost=r.depLost+dep
        elseif typ=="CRAFT" then
            local cost=tonumber(e.reagentCost) or (not e.reagentInputs and tonumber(row.cogs))
            if type(e.reagents)=="table" then
                local encoded={}; for _,v in ipairs(e.reagents) do encoded[#encoded+1]=(v.itemID or v[1])..":"..(v.qty or v[2]) end
                e.reagentInputs=table.concat(encoded,";")
                cost=0
                for _, reagent in ipairs(e.reagents) do cost=cost+consumeCost(econ,reagent.itemID or reagent[1],reagent.qty or reagent[2],true) end
                e.reagents=nil
            end
            if cost then Store.AddBasis(econ,id,max(1,qty),cost); row.cogs=cost end
        elseif typ=="DESTROY" and id>0 and qty>0 then
            local cost=Store.ConsumeBasis(econ,id,qty); row.cogs=cost
            local outputs,weight={},0
            e.outputWeights=e.outputWeights or e.outputs
            for oid,oq,alloc in tostring(e.outputWeights or ""):gmatch("(%d+):(%d+):(%d+)") do
                local o={itemID=tonumber(oid),qty=tonumber(oq),allocCost=tonumber(alloc)}
                outputs[#outputs+1]=o; weight=weight+o.allocCost
            end
            local units=0; for _,o in ipairs(outputs) do units=units+o.qty end
            local used,encoded=0,{}
            -- Proportional integer allocation; the final output receives the copper remainder.
            for i,o in ipairs(outputs) do
                o.allocCost=i==#outputs and cost-used or floor(cost*(weight>0 and o.allocCost/weight or o.qty/max(1,units)))
                used=used+o.allocCost; Store.AddBasis(econ,o.itemID,o.qty,o.allocCost)
                encoded[#encoded+1]=o.itemID..":"..o.qty..":"..o.allocCost
            end
            e.outputs=table.concat(encoded,";"); e.nonCash=true
        elseif typ=="DISENCHANT_BROKEN" and id>0 and qty>0 then
            local cost=Store.ConsumeBasis(econ,id,qty); row.cogs=cost
            local estVal=tonumber(e.estValue) or 0
            if estVal>0 then
                row.profit=estVal-cost
                r.sold=r.sold+qty; r.gross=r.gross+estVal; r.cogs=r.cogs+cost
            else
                row.profit=0
            end
            e.nonCash=true
        elseif typ=="DISENCHANT_RECEIVE" and id>0 and qty>0 then
            local basis=tonumber(e.allocBasis) or tonumber(e.marketValue) or 0
            Store.AddBasis(econ,id,qty,max(0,basis))
            row.profit=0
            e.nonCash=true
        elseif typ=="WRIT_TURNIN" then
            if row.cogs==nil then e.autoCost=true; row.cogs=consumeCost(econ,id,1,true)+consumeCost(econ,e.reqItemID,e.reqQty) end
            if e.pouchTier then local p=ensure(ensure(DB.pouches,char),e.pouchTier); p[#p+1]={writItemID=id,questID=e.questID,at=row.time} end
        elseif typ=="POUCH_MONEY" then
            local tier=e.tier or row.ref
            local popped=tier and popPouch(char,econ,tier); if popped then e.writItemID=popped.writItemID end
        elseif typ=="CRATE_TURNIN" then
            if row.cogs==nil then
                e.autoCost=true
                row.cogs=consumeCost(econ,id,max(1,qty),true)+(tonumber(e.bundleCost) or tonumber(e.reagentCost) or 0)
                if type(e.bundles)=="table" then
                    local inputs={}; for _, b in ipairs(e.bundles) do
                        inputs[#inputs+1]=(b.itemID or b[1])..":"..(b.qty or b[2]); row.cogs=row.cogs+consumeCost(econ,b.itemID or b[1],b.qty or b[2],true)
                    end
                    e.bundleInputs=table.concat(inputs,";"); e.bundles=nil
                end
            end
            DB.stats.favorCostSum=DB.stats.favorCostSum+(row.cogs or 0)-max(0,total); DB.stats.favorGainSum=DB.stats.favorGainSum+(tonumber(e.favor) or 0)
        elseif typ=="FAVOR_GAIN" then DB.stats.favorGainSum=DB.stats.favorGainSum+(tonumber(e.favor) or qty)
        elseif typ=="FAVOR_SPEND" then
            local favor=tonumber(e.favor) or qty
            if e.favorCopperValue==nil then e.favorCopperValue=floor(favor*Store.GetRunningFavorPrice()+0.5) end
            if id>0 and qty>0 then Store.AddBasis(econ,id,qty,max(0,-total)+(tonumber(e.favorCopperValue) or 0)) end
        end
    end
    itemMeta(row)
    dailyStats(row,day)
    local d=ensure(DB.days,day)
    if d.s then d.r=Store.UnpackDayString(d.s); d.s=nil end
    d.r=d.r or {}; d.r[#d.r+1]=row
    Store._appending=nil
    changed(row,nil,firstChanged or nil)
    if perfT0 and host.ConsoleEngine and host.ConsoleEngine.RecordTxTiming then
        host.ConsoleEngine.RecordTxTiming(typ, _G.debugprofilestop() - perfT0)
    end
    return row
end
function Store.AddLoot(itemID, source, zone, qty, opts)
    if not writable() then return end
    opts=opts or {}; local curChar,curEcon=Store.CurrentCharAndEcon()
    local t=opts.time or Store.Now(); local day=Store.DayKey(t); local char=opts.char or curChar; local econ=opts.econ or Store.DeriveEcon(char,curEcon)
    itemID=tonumber(itemID) or 0; qty=tonumber(qty) or 0
    if qty<=0 then return end
    zone=(zone and zone~="") and tostring(zone):gsub("|","/") or "Unknown"; source=(source and source~="") and tostring(source):gsub("|","/") or "Mob"
    DB.stats.chars[char]=true; DB.stats.zones[zone]=true; DB.stats.zones[zone.." ("..source..")"]=true
    local counters=ensure(ensure(DB.loot,day),char); local key
    if itemID==0 or source=="Money" then
        key="0|Money|"..zone; local recon=ensure(DB.stats.recon,char); recon.recorded=(recon.recorded or 0)+qty
        DB.basisEvents[#DB.basisEvents+1]={time=t,char=char,cash=qty,order=replayOrder()}
    else key=tostring(itemID).."|"..source.."|"..zone; Store._basisTime=t; Store.AddBasis(econ,itemID,qty,0); Store._basisTime=nil; local r=roll(day,char,itemID); r.looted=r.looted+qty end
    counters[key]=(counters[key] or 0)+qty
    local prevFirst=DB.stats.firstLive[char]
    DB.stats.firstLive[char]=min(prevFirst or t,t)
    changed(nil,"loot",DB.stats.firstLive[char]~=prevFirst or nil)
end

local unescapes={ ["25"]="%", ["2C"]=",", ["2c"]=",", ["0A"]="\n", ["0a"]="\n", ["0D"]="\r", ["0d"]="\r", ["3B"]=";", ["3b"]=";", ["3D"]="=", ["3d"]="=", ["7C"]="|", ["7c"]="|" }
local function unescape(s)
    -- One pass leaves decoded percent signs untouched (%25 is effectively last).
    if not s:find("%",1,true) then return s end
    return (s:gsub("%%(%x%x)",unescapes))
end
local function numberString(n)
    if n==floor(n) and n>-100000000000000 and n<100000000000000 then return tostring(n) end
    return string.format("%.17g",n)
end
local packedFields={"time","char","econ","type","where","itemID","qty","unit","total","cogs","ref"}
-- Bounded scalar caches avoid repeating CRT float conversion when the same
-- packed history is queried again. They contain no rows or character objects.
local preciseNumbers, preciseCount = {}, 0
local decodedNumbers, decodedCount = {}, 0
local emptyExtra, packValues, lenPrefixCache = {}, {}, {}
local function lengthPrefix(len)
    local prefix=lenPrefixCache[len]
    if not prefix then
        prefix=tostring(len)..":"
        -- Cache only short lengths so arbitrary payloads cannot grow it forever.
        if len<=4096 then lenPrefixCache[len]=prefix end
    end
    return prefix
end
function Store.PackRows(rows)
    local type,tostring,floor=type,tostring,floor
    local pairs,ipairs,strformat=pairs,ipairs,string.format
    local nRows=#rows
    local numCache,numCount=preciseNumbers,preciseCount
    local fields,seen,extraRows={},{},{}
    for _,k in ipairs(packedFields) do fields[#fields+1]=k end
    for i,row in ipairs(rows) do
        row._lot=nil
        local ex=row.extra
        if ex then
            extraRows[i]=ex
            for k,v in pairs(ex) do
                if not seen[k] then
                    local typ=type(v)
                    if typ=="number" or typ=="boolean" or typ=="string" then fields[#fields+1]=k; seen[k]=true end
                end
            end
        else extraRows[i]=emptyExtra end
    end
    local extras={}; for i=#packedFields+1,#fields do extras[#extras+1]=fields[i] end
    table.sort(extras,function(a,b) if type(a)~=type(b) then return type(a)<type(b) end; return a<b end)
    for i,k in ipairs(extras) do fields[#packedFields+i]=k end
    local parts={"MM1:",#rows,":",#fields-#packedFields,":"}; local encoded={}
    local function field(v)
        if v==nil then return "z:" end
        if encoded[v]==nil then
            local typ=type(v)
            encoded[v]=(typ=="number" and "n"..numberString(v)..":") or (typ=="boolean" and (v and "t:" or "f:")) or (typ=="string" and "s"..lengthPrefix(#v)..v) or "z:"
        end
        return encoded[v]
    end
    for col=#packedFields+1,#fields do parts[#parts+1]=field(fields[col]) end
    for col,key in ipairs(fields) do
        local source=col<=#packedFields and rows or extraRows
        local first=source[1] and source[1][key]
        local constant=true
        for i=2,nRows do if source[i][key]~=first then constant=false; break end end
        local kind=type(first); local numeric,strings=kind=="number",kind=="string"
        local integers,large=numeric,false
        local values=packValues
        if not constant then
            for i=1,nRows do
                local value=source[i][key]; values[i]=value
                if type(value)~=kind then numeric=false; strings=false; integers=false
                elseif integers then
                    if value~=floor(value) or value < -9007199254740992 or value > 9007199254740992 then integers=false
                    elseif value<=-100000000000000 or value>=100000000000000 then large=true end
                end
            end
        end
        if constant then parts[#parts+1]="c"..field(first)
        elseif numeric then
            parts[#parts+1]="n"
            if integers then
                -- Lua 5.1 concat uses 14 significant digits for numbers. Format
                -- large exact integers explicitly so this fast path stays lossless.
                for i=1,nRows do
                    local v=values[i]; local s=numCache[v]
                    if not s then
                        s=large and strformat("%.17g",v) or tostring(v)
                        if numCount>=4096 then numCache={}; numCount=0 end
                        numCache[v]=s; numCount=numCount+1
                    end
                    values[i]=s
                end
            else
                for i=1,nRows do
                    local v=values[i]; local s=numCache[v]
                    if not s then
                        s=strformat("%.17g",v)
                        if numCount>=4096 then numCache={}; numCount=0 end
                        if v==v then numCache[v]=s; numCount=numCount+1 end
                    end
                    values[i]=s
                end
            end
            local p=#parts
            parts[p+1]=tconcat(values,",",1,nRows); parts[p+2]=","; parts[p+3]=":"
        elseif strings then
            parts[#parts+1]="s"
            local p=#parts
            for i=1,nRows do
                local value=values[i]
                local len=#value
                local lp=lenPrefixCache[len] or lengthPrefix(len)
                parts[p+1]=lp; parts[p+2]=value; p=p+2
            end
        else
            parts[#parts+1]="v"
            for i=1,nRows do parts[#parts+1]=field(values[i]) end
        end
    end
    -- Constant columns and bulk numeric formatting keep packing within one frame.
    preciseNumbers,preciseCount=numCache,numCount
    return tconcat(parts)
end
function Store.PackDay(day)
    if not writable() then return end
    local d=DB.days[day]; if not d or d.s then return d and d.s end
    d.s=Store.PackRows(d.r or {}); d.r=nil; return d.s
end
function Store.UnpackDayString(str)
    local strfind,strsub,tonumber,strbyte=strfind,strsub,tonumber,string.byte
    local work=Store._prepareCheckpoint
    local numberCache,numberCount=decodedNumbers,decodedCount
    local rows,decoded,scalars={},{},{}
    if str and str:sub(1,4)=="MM1:" then
        local count,extras,pos=str:match("^MM1:(%d+):(%d+):()")
        count,extras=tonumber(count),tonumber(extras)
        local function scalar()
            local typ,value,nextPos=str:match("^([snzft])([^:]*):()",pos)
            pos=nextPos
            if typ=="s" then local finish=pos+tonumber(value); value=str:sub(pos,finish-1); pos=finish
            elseif typ=="n" then value=tonumber(value)
            elseif typ=="t" then value=true elseif typ=="f" then value=false else value=nil end
            return value
        end
        local fields={}
        for _,key in ipairs(packedFields) do fields[#fields+1]=key end
        for i=1,extras do fields[#fields+1]=scalar() end
        local extraRows={}
        -- Nil constructor fields reserve row capacity without adding absent keys.
        if work then
            for i=1,count do
                if i%40==0 then work() end
                local ex={}; rows[i]={extra=ex,time=nil,char=nil,econ=nil,type=nil,where=nil,itemID=nil,qty=nil,unit=nil,total=nil,cogs=nil,ref=nil}
                if extras>0 then extraRows[i]=ex end
            end
        elseif extras>0 then
            for i=1,count do
                local ex={}; extraRows[i]=ex
                rows[i]={extra=ex,time=nil,char=nil,econ=nil,type=nil,where=nil,itemID=nil,qty=nil,unit=nil,total=nil,cogs=nil,ref=nil}
            end
        else
            for i=1,count do rows[i]={extra={},time=nil,char=nil,econ=nil,type=nil,where=nil,itemID=nil,qty=nil,unit=nil,total=nil,cogs=nil,ref=nil} end
        end
        for col,key in ipairs(fields) do
            local targets=col<=#packedFields and rows or extraRows
            local mode=strsub(str,pos,pos); pos=pos+1
            if mode=="c" then
                local value=scalar()
                if work then
                    for i=1,count do if i%40==0 then work() end; targets[i][key]=value end
                elseif value~=nil then
                    for i=1,count do targets[i][key]=value end
                end
            elseif mode=="n" then
                if work then
                    for i=1,count do
                        if i%40==0 then work() end
                        local comma=strfind(str,",",pos,true)
                        local token=strsub(str,pos,comma-1)
                        local value=numberCache[token]
                        if value==nil then
                            value=tonumber(token)
                            if numberCount>=4096 then numberCache={}; numberCount=0 end
                            numberCache[token]=value; numberCount=numberCount+1
                        end
                        targets[i][key]=value; pos=comma+1
                    end
                else
                    for i=1,count do
                        local comma=strfind(str,",",pos,true)
                        local token=strsub(str,pos,comma-1)
                        local value=numberCache[token]
                        if value==nil then
                            value=tonumber(token)
                            if numberCount>=4096 then numberCache={}; numberCount=0 end
                            numberCache[token]=value; numberCount=numberCount+1
                        end
                        targets[i][key]=value; pos=comma+1
                    end
                end
                pos=pos+1
            elseif mode=="s" then
                if work then
                    for i=1,count do
                        if i%40==0 then work() end
                        local len=0; local b=strbyte(str,pos)
                        while b and b~=58 do
                            len=len*10+(b-48); pos=pos+1; b=strbyte(str,pos)
                        end
                        local nextPos=pos+1+len
                        targets[i][key]=strsub(str,pos+1,nextPos-1); pos=nextPos
                    end
                else
                    for i=1,count do
                        local len=0; local b=strbyte(str,pos)
                        while b and b~=58 do
                            len=len*10+(b-48); pos=pos+1; b=strbyte(str,pos)
                        end
                        local nextPos=pos+1+len
                        targets[i][key]=strsub(str,pos+1,nextPos-1); pos=nextPos
                    end
                end
            else
                if work then
                    for i=1,count do if i%40==0 then work() end; targets[i][key]=scalar() end
                else
                    for i=1,count do targets[i][key]=scalar() end
                end
            end
        end
        decodedNumbers,decodedCount=numberCache,numberCount
        return rows
    end
    local function text(s)
        if decoded[s]==nil then decoded[s]=unescape(s) end
        return decoded[s]
    end
    for line in (str or ""):gmatch("[^\n]+") do if work then work() end;
        local t,char,econ,typ,where,id,qty,unit,total,cogs,ref,extra=line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$")
        if t then
            local row={time=tonumber(t),char=text(char),econ=text(econ),type=text(typ),where=text(where),itemID=tonumber(id),qty=tonumber(qty),unit=tonumber(unit),total=tonumber(total),cogs=tonumber(cogs),ref=ref~="" and text(ref) or nil,extra={}}
            for pair in extra:gmatch("[^;]+") do
                local scalarValue=scalars[pair]
                if not scalarValue then
                    local at=pair:find("=",1,true)
                    if at then
                        local k,p,v=pair:sub(1,at-1),pair:sub(at+1,at+1),pair:sub(at+3)
                        local value
                        if p=="n" then value=tonumber(v) elseif p=="b" then value=v=="true" elseif p=="s" then value=text(v) end
                        scalarValue={key=text(k),value=value}; scalars[pair]=scalarValue
                    end
                end
                if scalarValue then row.extra[scalarValue.key]=scalarValue.value end
            end
            rows[#rows+1]=row
        end
    end
    return rows
end
function Store.Chunk(items,perFrame,stepFn,doneFn)
    local idx=1; perFrame=max(1,tonumber(perFrame) or 1)
    if not (_G.C_Timer and _G.C_Timer.After) then for i,item in ipairs(items) do stepFn(item,i) end; if doneFn then doneFn() end; return end
    local function step()
        local last=min(#items,idx+perFrame-1)
        while idx<=last do local i=idx; idx=idx+1; stepFn(items[i],i) end
        if idx<=#items then _G.C_Timer.After(0,step) elseif doneFn then doneFn() end
    end
    step()
end
function Store.PackOldDays(maxDays)
    if not writable() then return end
    local today=Store.DayKey(); local days={}
    for day,d in pairs(DB.days) do if day<today and d.r then days[#days+1]=day end end
    table.sort(days); Store.Chunk(days,maxDays or 1,Store.PackDay)
end
function Store.IterDays(fromDay,toDay,fn,opts)
    if not DB or not DB.days then return end
    opts=opts or {}; local keys={}
    for day in pairs(DB.days) do if day>=(fromDay or "0000-00-00") and day<=(toDay or "9999-99-99") then keys[#keys+1]=day end end
    table.sort(keys,function(a,b) if opts.desc then return a>b end; return a<b end)
    for _,day in ipairs(keys) do
        local d=DB.days[day]; local rows=d.r
        if rows then unpackedCache[day]=nil
        else
            local entry=unpackedCache[day]
            if not entry or entry.raw~=d.s then entry={raw=d.s,rows=Store.UnpackDayString(d.s)}; unpackedCache[day]=entry end
            rows=entry.rows
        end
        if fn(day,rows)==false then break end
    end
end
function Store.SaveSnapshot(char,day,snap,detail)
    if not writable() then return end
    ensure(DB.snaps,char)[day]={
        gold=snap.gold or 0,items=snap.items or 0,listed=snap.listed or 0,
        bags=snap.bags,bank=snap.bank,mail=snap.mail,gear=snap.gear,
        econ=snap.econ,goldOnly=snap.goldOnly or nil,
    }
    if detail then ensure(DB,"wealth")[char]=detail end
    changed(nil,"snapshot")
end
function Store.InitRecon(char,currentGold)
    if not writable() then return end
    if not DB.stats.recon[char] or DB.stats.recon[char].gold==nil then DB.stats.recon[char]={gold=currentGold,recorded=0,at=Store.Now(),order=DB.stats.nextReplayOrder or 0} end
end
function Store.ReconcileGold(char,currentGold,whereLabel)
    if not writable() then return end
    local r=DB.stats.recon[char]; if not r or r.gold==nil then Store.InitRecon(char,currentGold); return end
    local diff=currentGold-r.gold-(r.recorded or 0); DB.stats.recon[char]={gold=currentGold,recorded=0,at=Store.Now(),order=DB.stats.nextReplayOrder or 0}
    if diff~=0 then return Store.Append({char=char,type="ADJUST",total=diff,where=whereLabel or "Session Reconciliation"}) end
end

function Store.NetUnitToGrossFee(netUnit,qty)
    local net=netUnit*qty; local gross=floor(net/0.95+0.5)
    return net,gross,max(0,gross-net)
end
function Store.EstimateBytes()
    if not DB then return 0 end
    if Store._bytesCacheDB==DB and Store._bytesCacheVer==Store.version then return Store._bytesCacheVal end
    local n=256
    for day,d in pairs(DB.days or {}) do
        n=n+#day+16+(d.s and #d.s or (d.r and #d.r*140 or 0))
    end
    for day,chars in pairs(DB.roll or {}) do
        n=n+#day+16
        for ck,items in pairs(chars) do
            n=n+#tostring(ck)+16
            for _ in pairs(items) do n=n+180 end
        end
    end
    for day,chars in pairs(DB.loot or {}) do
        n=n+#day+16
        for ck,counters in pairs(chars) do n=n+#tostring(ck)+16; for k in pairs(counters) do n=n+#k+16 end end
    end
    for _,snaps in pairs(DB.snaps or {}) do for _ in pairs(snaps) do n=n+112 end end
    for _,w in pairs(DB.wealth or {}) do
        n=n+128
        for _,list in pairs(w.cats or {}) do n=n+(#list)*88 end
    end
    for fp in pairs(DB.seenMail or {}) do n=n+#tostring(fp)+16 end
    for _,entry in ipairs(DB.probe and DB.probe.log or {}) do n=n+#tostring(entry.msg or "")+48 end
    Store._bytesCacheDB=DB; Store._bytesCacheVer=Store.version; Store._bytesCacheVal=n
    return n
end
function Store.RecordError(kind,err)
    if not writable() then return end
    DB.stats.errors[kind]=(DB.stats.errors[kind] or 0)+1
    if DB.stats.errors[kind]>=5 then DB.stats.disabled[kind]=true end
    Store.ProbeLog(kind,tostring(err)); changed()
end
function Store.IsDisabled(kind) return Store.readOnly or (DB and DB.stats and DB.stats.disabled and DB.stats.disabled[kind]) or false end
function Store.ResetErrors() if writable() then DB.stats.errors={}; DB.stats.disabled={}; changed() end end
function Store.ProbeLog(tag,msg)
    if not writable() or not DB.probe.enabled then return end
    local log=DB.probe.log; log[#log+1]={at=Store.Now(),tag=tostring(tag),msg=tostring(msg)}; if #log>500 then table.remove(log,1) end
end

local function rowName(row)
    local h=H(); local name=row.extra and row.extra.name
    if not name and h and h.ItemName then name=h.ItemName(row.itemID) end
    if secret(name) then return "" end
    return name or ("Item "..row.itemID)
end
function Store.SelectRows(filters)
    filters=filters or {}; local from,to=filters.from,filters.to
    if filters.period and filters.period~="all" then
        local count=filters.period=="today" and 0 or tonumber(filters.period:match("^(%d+)d$"))
        if count then from=from or Store.DayKey(Store.Now()-max(0,count-1)*86400); to=to or Store.DayKey() end
    end
    local fromDay=type(from)=="number" and Store.DayKey(from) or from
    local toDay=type(to)=="number" and Store.DayKey(to) or to
    local out={}; local needle=string.lower(filters.search or "")
    Store.IterDays(fromDay,toDay,function(day,rows)
        for idx,row in ipairs(rows) do
            local e=row.extra or {}
            local searchable=table.concat({rowName(row),row.type,row.char,row.where or "",e.counterparty or e.buyer or e.seller or ""}," "):lower()
            if (not filters.char or filters.char=="all" or filters.char==row.char)
                and (not filters.econ or filters.econ==row.econ)
                and (not filters.itemID or tonumber(filters.itemID)==row.itemID)
                and (not filters.type or filters.type=="all" or row.type==filters.type or Store.MatchesTypeGroup(row.type,filters.type))
                and (type(from)~="number" or row.time>=from) and (type(to)~="number" or row.time<=to)
                and (needle=="" or searchable:find(needle,1,true)) then
                local r=copy(row); r.extra=r.extra or {}; r.extra.eid=Store.EventID(row,day,idx); out[#out+1]=r
            end
        end
    end)
    table.sort(out,function(a,b) if a.time~=b.time then return a.time<b.time end; return a.extra.eid<b.extra.eid end)
    return out
end
local function csvField(v)
    if v==nil then return "" end
    local s=tostring(v); if s:find('[,"\r\n]') then return '"'..s:gsub('"','""')..'"' end; return s
end
function Store.Export(filters)
    local lines={"time,date,char,econ,type,itemID,itemName,qty,unit,total,cogs,fee,counterparty,where,eid"}
    for _,r in ipairs(Store.SelectRows(filters)) do
        local e=r.extra or {}; local fields={r.time,fmtDate("%Y-%m-%d %H:%M:%S",r.time),r.char,r.econ,r.type,r.itemID,rowName(r),r.qty,r.unit,r.total,r.cogs or "",e.fee or "",e.counterparty or e.buyer or e.seller or "",r.where,e.eid}
        for i=1,15 do fields[i]=csvField(fields[i]) end; lines[#lines+1]=table.concat(fields,",")
    end
    return table.concat(lines,"\n")
end
function Store.CoalesceRows(rows,windowSec)
    local out={}; local window=max(0,tonumber(windowSec) or 300)
    for _,row in ipairs(rows or {}) do
        local e=row.extra or {}; local party=e.counterparty or e.buyer or e.seller or ""
        local last=out[#out]; local le=last and last.extra or {}
        if last and row.char==last.char and row.type==last.type and row.itemID==last.itemID and row.unit==last.unit
            and party==(le.counterparty or le.buyer or le.seller or "") and math.abs(row.time-last.time)<=window then
            last.qty=last.qty+row.qty; last.total=last.total+row.total
            last.cogs=(last.cogs or 0)+(row.cogs or 0); last.fee=last.fee+(tonumber(e.fee) or 0); last.extra.fee=last.fee
            last.rawEventIDs[#last.rawEventIDs+1]=Store.EventID(row)
        else
            local r=copy(row); r.fee=tonumber(e.fee) or 0; r.rawEventIDs={Store.EventID(row)}; out[#out+1]=r
        end
    end
    return out
end

local function stateSnapshot(source)
    return {basis=copy(source.basis),lots=copy(source.lots),ret=copy(source.ret),pouches=copy(source.pouches),itemStats=copy(source.itemStats),
        recon=copy(source.stats.recon),historicalBasis=copy(source.historicalBasis),favorCostSum=source.stats.favorCostSum,favorGainSum=source.stats.favorGainSum}
end
local function allRows()
    local out={}; Store.IterDays(nil,nil,function(day,rows)
        for i,r in ipairs(rows) do local v=copy(r); v.extra=v.extra or {}; v.extra.eid=Store.EventID(r,day,i); out[#out+1]=v end
    end)
    return out
end
function Store.EnsureReplayBase()
    if DB.replayBase then return end
    local base=stateSnapshot(DB); local rows=allRows()
    local positions={}; for i,r in ipairs(rows) do positions[r]=i end
    local function sequence(r) return r.extra.replayOrder or positions[r] end
    table.sort(rows,function(a,b) if a.time~=b.time then return a.time>b.time end; return sequence(a)>sequence(b) end)
    local function undo(econ,id,qty,cost)
        if id<=0 or qty==0 then return end
        local b=ensure(ensure(base.basis,econ),id)
        local value=(b.qty or 0)*(b.avg or 0)+cost; b.qty=max(0,(b.qty or 0)+qty)
        b.avg=b.qty>0 and max(0,value)/b.qty or 0
    end
    if DB.seed.tsm then
        local seeded,already={},{}
        for _,ev in ipairs(DB.basisEvents) do if ev.tsmRemainder then ensure(already,ev.econ)[ev.itemID]=true end end
        for i=#rows,1,-1 do
            local r=rows[i]
            if r.extra.tsm and r.itemID>0 then
                local b=ensure(ensure(seeded,r.econ),r.itemID); b.qty=b.qty or 0; b.avg=b.avg or 0
                if buyTypes[r.type] and r.qty>0 then b.avg=(b.qty*b.avg+math.abs(r.total))/(b.qty+r.qty); b.qty=b.qty+r.qty
                elseif sellTypes[r.type] then b.qty=max(0,b.qty-r.qty) end
            end
        end
        for econ,items in pairs(seeded) do
            local live=false; for c in pairs(DB.stats.firstLive) do if Store.DeriveEcon(c)==econ then live=true; break end end
            if not live then for id,b in pairs(items) do
                if b.qty>0 and not (already[econ] and already[econ][id]) then
                    local seedAt=type(DB.seed.tsm)=="table" and DB.seed.tsm.at or nil
                    DB.basisEvents[#DB.basisEvents+1]={time=seedAt or Store.Now(),econ=econ,itemID=id,qty=b.qty,paid=b.qty*b.avg,tsmRemainder=true,order=replayOrder()}
                end
            end end
        end
    end
    local backwards={}
    for _,r in ipairs(rows) do backwards[#backwards+1]={time=r.time,order=sequence(r),row=r} end
    for _,ev in ipairs(DB.basisEvents) do backwards[#backwards+1]={time=ev.time,order=ev.order or 0,event=ev} end
    table.sort(backwards,function(a,b) if a.time~=b.time then return a.time>b.time end; return a.order>b.order end)
    for _,entry in ipairs(backwards) do
        if entry.event then
            local ev=entry.event
            if ev.econ and ev.itemID and ev.qty then
                local b=base.basis[ev.econ] and base.basis[ev.econ][ev.itemID]
                local paid=ev.paid or ev.qty*(b and b.avg or 0)
                local reverseQty=ev.qty<0 and (ev.known or -ev.qty) or -ev.qty
                undo(ev.econ,ev.itemID,reverseQty,-paid)
            end
        else
        local r=entry.row
        local e=r.extra
        if not e.tsm then
            if buyTypes[r.type] then undo(r.econ,r.itemID,-r.qty,-math.abs(r.total))
            elseif sellTypes[r.type] then
                local known=max(0,r.qty-(tonumber(e.estUnits) or 0))
                local cost=max(0,(r.cogs or 0)-(tonumber(e.estUnits) or 0)*Store.EstimateCraftOrMarketCost(r.itemID))
                undo(r.econ,r.itemID,known,cost)
                e.autoCost=true
            elseif r.type=="CRAFT" then
                undo(r.econ,r.itemID,-r.qty,-(r.cogs or e.reagentCost or 0))
                -- Older rows discarded reagent identities; retain their recorded craft cost.
                if not e.reagentInputs then DB.stats.legacyCraftCosts=true end
            elseif r.type=="DISENCHANT_BROKEN" then
                undo(r.econ,r.itemID,r.qty,r.cogs or 0)
            elseif r.type=="DISENCHANT_RECEIVE" then
                undo(r.econ,r.itemID,-r.qty,-(tonumber(e.allocBasis) or tonumber(e.marketValue) or 0))
            elseif r.type=="WRIT_TURNIN" or r.type=="CRATE_TURNIN" then
                local inputs={{id=r.itemID,qty=r.type=="WRIT_TURNIN" and 1 or max(1,r.qty)}}
                if r.type=="WRIT_TURNIN" and (tonumber(e.reqItemID) or 0)>0 and (tonumber(e.reqQty) or 0)>0 then inputs[#inputs+1]={id=e.reqItemID,qty=e.reqQty} end
                if e.bundleInputs then for id,qty in e.bundleInputs:gmatch("(%d+):([%d%.]+)") do inputs[#inputs+1]={id=tonumber(id),qty=tonumber(qty)} end end
                local sum=0
                for _,v in ipairs(inputs) do
                    local b=base.basis[r.econ] and base.basis[r.econ][v.id]
                    v.weight=v.qty*((b and b.qty>0 and b.avg) or Store.EstimateCraftOrMarketCost(v.id)); sum=sum+v.weight
                end
                local cost=max(0,(r.cogs or 0)-(r.type=="CRATE_TURNIN" and (e.bundleCost or e.reagentCost or 0) or 0)); local assigned=0
                for i,v in ipairs(inputs) do
                    local share=i==#inputs and cost-assigned or floor(cost*(sum>0 and v.weight/sum or 1/#inputs))
                    undo(r.econ,v.id,v.qty,share); assigned=assigned+share
                end
                e.autoCost=true
                if #inputs>1 then e.replayEstimated=1 end
            end
        end
        end
    end
    base.itemStats={}; base.pouches={}; base.ret={}; base.recon={}
    -- Preserve lots created before raw coverage, while replay owns the recorded posts.
    for c,items in pairs(base.lots) do for id,lots in pairs(items) do
        for i=#lots,1,-1 do for _,r in ipairs(rows) do
            if r.type=="AH_POST" and r.char==c and r.itemID==id and ((r.extra.auctionID and r.extra.auctionID==lots[i].auctionID) or r.time==lots[i].postedAt) then table.remove(lots,i); break end
        end end
    end end
    DB.replayBase=base
    if next(DB.itemStats)==nil then
        table.sort(rows,function(a,b) if a.time~=b.time then return a.time<b.time end; return sequence(a)<sequence(b) end)
        for _,r in ipairs(rows) do itemMeta(r) end
    end
    -- Persist identities and inferred auto-cost flags without changing the packed format.
    local derived={}; for _,r in ipairs(rows) do derived[r.extra.eid]=r.extra end
    for day,d in pairs(DB.days) do
        local list=d.r or Store.UnpackDayString(d.s)
        for i,r in ipairs(list) do
            r.extra=r.extra or {}; r.extra.eid=Store.EventID(r,day,i)
            if sellTypes[r.type] and not r.extra.tsm then r.extra.autoCost=true end
            local e=derived[r.extra.eid]
            if e and e.autoCost then r.extra.autoCost=true; r.extra.replayEstimated=e.replayEstimated end
        end
        if d.s then d.s=Store.PackRows(list) else d.r=list end
    end
end
-- Explicit correction runs in a private database; publish only after a complete replay.
local function replay(source,rows,events,base)
    local original,originalStore=DB,Store.db
    local work=copy(source); local b=base or {}
    work.days={}; work.roll={}; work.dayStats={}
    for day in pairs(source.archivedDays or {}) do work.roll[day]=copy(source.roll[day]); work.dayStats[day]=copy(source.dayStats[day]) end
    work.basis=copy(b.basis or {}); work.lots=copy(b.lots or {}); work.ret=copy(b.ret or {}); work.pouches=copy(b.pouches or {})
    work.itemStats=copy(b.itemStats or {}); work.itemMeta=work.itemStats
    work.stats.favorCostSum=b.favorCostSum or 0; work.stats.favorGainSum=b.favorGainSum or 0
    for c,r in pairs(work.stats.recon) do
        local previous=b.recon and b.recon[c]
        r.recorded=(previous and previous.at==r.at and previous.gold==r.gold and previous.order==r.order) and (previous.recorded or 0) or 0
    end
    local timeline={}
    for i,r in ipairs(rows) do timeline[#timeline+1]={time=r.time,row=r,order=r.extra.replayOrder or i,tie=i} end
    for i,event in ipairs(events or {}) do timeline[#timeline+1]={time=event.time,event=event,order=event.order or 0,tie=i} end
    table.sort(timeline,function(a,b)
        if a.time~=b.time then return a.time<b.time end
        if a.order~=b.order then return a.order<b.order end
        if not a.row~=not b.row then return a.event~=nil end
        return a.tie<b.tie
    end)
    DB=work; Store.db=work; Store._replaying=true
    local historicalBasis=copy(b.historicalBasis or {}); work.historicalBasis=historicalBasis
    local notify=Store.onChange; Store.onChange=nil
    local version,accountingVersion,ahSalesVersion,craftYieldVersion,craftYieldResetVersion,trackedAccountingVersion=Store.version,Store.accountingVersion,Store.ahSalesVersion,Store.craftYieldVersion,Store.craftYieldResetVersion,Store._trackedAccountingVersion
    local craftYieldLog=Store.craftYieldLog
    local ok,err=pcall(function()
        for _,entry in ipairs(timeline) do
            if entry.event then
                local ev=entry.event
                if ev.cash then
                    local r=ensure(work.stats.recon,ev.char)
                    if (r.order and (ev.order or 0)>r.order) or (not r.order and (not r.at or ev.time>=r.at)) then r.recorded=(r.recorded or 0)+ev.cash end
                elseif ev.pruneLots then Store.PruneMissingLots(ev.char,ev.activeIDs,ev.activeCounts,ev.maxPostedAt)
                elseif ev.tsmRemainder then
                    local b=historicalBasis[ev.econ] and historicalBasis[ev.econ][ev.itemID]
                    if b and b.qty>0 then Store.AddBasis(ev.econ,ev.itemID,b.qty,b.qty*b.avg) end
                elseif ev.qty>0 then Store.AddBasis(ev.econ,ev.itemID,ev.qty,ev.paid or 0) else Store.ConsumeBasis(ev.econ,ev.itemID,-ev.qty) end
            else
                local row=entry.row; local e=row.extra or {}; row.extra=e
                if e.tsm and row.itemID>0 then
                    local b=ensure(ensure(historicalBasis,row.econ),row.itemID); b.qty=b.qty or 0; b.avg=b.avg or 0
                    if buyTypes[row.type] and row.qty>0 then
                        b.avg=(b.qty*b.avg+math.abs(row.total))/(b.qty+row.qty); b.qty=b.qty+row.qty
                    elseif sellTypes[row.type] then
                        local known=min(row.qty,b.qty); local missing=row.qty-known
                        row.cogs=floor(known*b.avg+0.5)+floor(missing*Store.EstimateCraftOrMarketCost(row.itemID)+0.5)
                        b.qty=b.qty-known; e.est=missing>0 and 1 or nil; e.estUnits=missing>0 and missing or nil
                    end
                end
                if not e.tsm and (e.autoCost or e.recomputeCost) then row.cogs=nil; e.est=nil; e.estUnits=nil end
                if row.type=="CRAFT" and e.reagentInputs then
                    e.reagents={}; for id,qty in e.reagentInputs:gmatch("(%d+):([%d%.]+)") do e.reagents[#e.reagents+1]={itemID=tonumber(id),qty=tonumber(qty)} end
                end
                if row.type=="CRATE_TURNIN" and e.bundleInputs then
                    e.bundles={}; for id,qty in e.bundleInputs:gmatch("(%d+):([%d%.]+)") do e.bundles[#e.bundles+1]={itemID=tonumber(id),qty=tonumber(qty)} end
                end
                local recon=work.stats.recon[row.char]
                if recon and recon.gold~=nil and ((recon.order and (e.replayOrder or 0)<=recon.order) or (not recon.order and recon.at and row.time<recon.at)) then row.skipRecon=true end
                assert(Store.Append(row),"replay rejected event")
            end
        end
        -- Loot counters remain authoritative; basis mutations are replayed from the separate journal.
        for day,chars in pairs(source.roll or {}) do
            if not work.archivedDays[day] then for c,items in pairs(chars) do for id,r in pairs(items) do
                if (r.looted or 0)~=0 then roll(day,c,id).looted=r.looted end
            end end end
        end
    end)
    DB=original; Store.db=originalStore; Store._replaying=nil; Store._appending=nil; Store.onChange=notify; Store.version=version; Store.accountingVersion=accountingVersion; Store.ahSalesVersion=ahSalesVersion; Store.craftYieldVersion=craftYieldVersion; Store.craftYieldResetVersion=craftYieldResetVersion; Store.craftYieldLog=craftYieldLog; Store._trackedAccountingVersion=trackedAccountingVersion
    if not ok then return nil,tostring(err) end
    return work
end
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function publishReplay(work)
    for day,d in pairs(DB.days) do if d.s and work.days[day] then work.days[day]={s=Store.PackRows(work.days[day].r)} end end
    for _,k in ipairs({"days","roll","dayStats","basis","lots","ret","pouches","itemStats"}) do DB[k]=work[k] end
    DB.itemMeta=DB.itemStats; DB.stats.recon=work.stats.recon; DB.stats.favorCostSum=work.stats.favorCostSum; DB.stats.favorGainSum=work.stats.favorGainSum
    DB.stats.nextReplayOrder=max(DB.stats.nextReplayOrder or 0,work.stats.nextReplayOrder or 0)
    for c in pairs(DB.stats.chars) do Store.UpdateTodayListedSnap(c) end
    Store.craftYieldResetVersion=(Store.craftYieldResetVersion or 1)+1
    Store.craftYieldLog={}
    changed()
end
function Store.Rebuild()
    if not writable() then return {ok=false,err="store is read-only"} end
    local work,err=replay(DB,allRows(),DB.basisEvents,DB.replayBase)
    if not work then return {ok=false,err=err} end
    publishReplay(work); return {ok=true}
end
function Store.RecordCraftYield(spellID, itemID, madeQty, castsCount, rolls)
    if not writable() then return nil end
    local sid = tonumber(spellID)
    local made = tonumber(madeQty)
    local casts = tonumber(castsCount) or 1
    if not finite(sid) or sid <= 0 or not finite(made) or made <= 0 or not finite(casts) then return nil end
    sid = floor(sid + 0.5)
    casts = max(1, floor(casts + 0.5))
    DB.craftYieldStats = type(DB.craftYieldStats) == "table" and DB.craftYieldStats or {}
    local rec = DB.craftYieldStats[sid]
    if type(rec) ~= "table" then
        rec = { itemID = 0, casts = 0, totalOutput = 0, hist = {}, lastAt = 0 }
        DB.craftYieldStats[sid] = rec
    end
    local outID = tonumber(itemID)
    if finite(outID) and outID > 0 then rec.itemID = floor(outID + 0.5) end
    rec.casts = (tonumber(rec.casts) or 0) + casts
    rec.totalOutput = (tonumber(rec.totalOutput) or 0) + made
    rec.lastAt = Store.Now()
    rec.hist = type(rec.hist) == "table" and rec.hist or {}
    if type(rolls) == "table" and #rolls > 0 then
        for _, rv in ipairs(rolls) do
            local r = tonumber(rv)
            if finite(r) and r > 0 then
                r = floor(r + 0.5)
                rec.minSeen = rec.minSeen and min(rec.minSeen, r) or r
                rec.maxSeen = rec.maxSeen and max(rec.maxSeen, r) or r
                rec.hist[r] = (tonumber(rec.hist[r]) or 0) + 1
            end
        end
    elseif casts == 1 then
        local r = max(1, floor(made + 0.5))
        rec.minSeen = rec.minSeen and min(rec.minSeen, r) or r
        rec.maxSeen = rec.maxSeen and max(rec.maxSeen, r) or r
        rec.hist[r] = (tonumber(rec.hist[r]) or 0) + 1
    end
    local nextVer = (Store.craftYieldVersion or 1) + 1
    Store.craftYieldLog = Store.craftYieldLog or {}
    local logOutID = (finite(outID) and outID > 0) and floor(outID + 0.5) or (tonumber(rec.itemID) or 0)
    Store.craftYieldLog[nextVer] = { itemID = logOutID, spellID = sid }
    local pruneBefore = nextVer - 64
    for k in pairs(Store.craftYieldLog) do
        if type(k) == "number" and k <= pruneBefore then
            Store.craftYieldLog[k] = nil
        end
    end
    changed(nil, "craft_yield", false)
    return rec
end
function Store.GetCraftYieldStats(spellID)
    local sid = tonumber(spellID)
    if not DB or type(DB.craftYieldStats) ~= "table" or not finite(sid) or sid <= 0 then return nil end
    local rec = DB.craftYieldStats[floor(sid + 0.5)]
    if type(rec) ~= "table" then return nil end
    local casts = tonumber(rec.casts) or 0
    local total = tonumber(rec.totalOutput) or 0
    if casts <= 0 or total <= 0 then return nil end
    return {
        spellID = floor(sid + 0.5),
        itemID = tonumber(rec.itemID) or 0,
        casts = casts,
        totalOutput = total,
        avg = total / casts,
        minSeen = rec.minSeen,
        maxSeen = rec.maxSeen,
        hist = copy(rec.hist or {}),
        lastAt = rec.lastAt,
    }
end
function Store.Correct(eventID,correction)
    if not writable() then return {ok=false,err="store is read-only"} end
    if type(correction)~="table" or (correction.action~="delete" and correction.action~="edit") then return {ok=false,err="invalid correction"} end
    for _,k in ipairs({"qty","unit","total"}) do
        local n=correction[k]; if n~=nil and (not finite(n) or (k~="total" and n<0) or (k=="qty" and n~=floor(n))) then return {ok=false,err="invalid "..k} end
    end
    if correction.extra~=nil then
        if type(correction.extra)~="table" then return {ok=false,err="invalid metadata"} end
        for k,v in pairs(correction.extra) do if k=="eid" or (type(v)~="string" and type(v)~="number" and type(v)~="boolean") or (type(v)=="number" and not finite(v)) then return {ok=false,err="invalid metadata"} end end
    end
    local rows=allRows(); local target
    for i,r in ipairs(rows) do if r.extra.eid==eventID then target=i; break end end
    if not target then
        local day,idx=tostring(eventID):match("^(%d%d%d%d%-%d%d%-%d%d):(%d+)$")
        local d=day and DB.days[day]; local list=d and (d.r or Store.UnpackDayString(d.s))
        local r=list and list[tonumber(idx)]
        if r then local eid=Store.EventID(r,day,tonumber(idx)); for i,v in ipairs(rows) do if v.extra.eid==eid then target=i; break end end end
    end
    if not target then return {ok=false,err="event not found (raw history may have been pruned)"} end
    if correction.action=="delete" then table.remove(rows,target)
    else
        local row=rows[target]
        for _,k in ipairs({"qty","unit","total"}) do if correction[k]~=nil then row[k]=correction[k] end end
        for k,v in pairs(correction.extra or {}) do row.extra[k]=v end
        if sellTypes[row.type] and (correction.total~=nil or correction.unit~=nil or correction.qty~=nil) and not (correction.extra and correction.extra.gross) then row.extra.gross=nil end
    end
    local work,err=replay(DB,rows,DB.basisEvents,DB.replayBase)
    if not work then return {ok=false,err=err} end
    -- Keep the SavedVariables root identity for existing consumers.
    publishReplay(work); return {ok=true,eid=eventID,action=correction.action}
end

local function validDay(day)
    if type(day)~="string" then return false end
    local y,m,d=day:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$"); y,m,d=tonumber(y),tonumber(m),tonumber(d)
    if not y or y<1970 or m<1 or m>12 or d<1 then return false end
    local lengths={31,28,31,30,31,30,31,31,30,31,30,31}
    if y%4==0 and (y%100~=0 or y%400==0) then lengths[2]=29 end
    return d<=lengths[m]
end
function Store.PreviewPrune(beforeDay,options)
    if not DB then Store.Init() end
    if Store.readOnly then return {ok=false,err="store is read-only"} end
    if not validDay(beforeDay) then return {ok=false,err="invalid cutoff day"} end
    local p={daysToPrune=0,rowsToPrune=0,rollDaysToFold=0,estBytesBefore=Store.EstimateBytes(),estBytesAfter=0}
    local saved=0
    for day,d in pairs(DB.days) do if day<beforeDay then
        p.daysToPrune=p.daysToPrune+1; p.rowsToPrune=p.rowsToPrune+#(d.r or Store.UnpackDayString(d.s)); saved=saved+#day+16+(d.s and #d.s or #(d.r or {})*140)
    end end
    for day,chars in pairs(DB.roll) do if day<beforeDay and not DB.archivedDays[day] then p.rollDaysToFold=p.rollDaysToFold+1 end end
    for day,chars in pairs(DB.loot) do if day~=Store.ARCHIVE_DAY and day<beforeDay then
        saved=saved+#day+16; for ck,counters in pairs(chars) do saved=saved+#tostring(ck)+16; for key in pairs(counters) do saved=saved+#key+16 end end
    end end
    p.estBytesAfter=max(0,p.estBytesBefore-saved); return p
end
function Store.PruneBefore(beforeDay,options)
    if not writable() then return {ok=false,err="store is read-only"} end
    local preview=Store.PreviewPrune(beforeDay,options); if preview.ok==false then return preview end
    if DB.prunedBefore and beforeDay<DB.prunedBefore then return {ok=false,err="cutoff precedes archived checkpoint"} end
    local oldRows,oldEvents,keepEvents={},{},{}
    for _,r in ipairs(allRows()) do if Store.DayKey(r.time)<beforeDay then oldRows[#oldRows+1]=r end end
    for _,ev in ipairs(DB.basisEvents) do if Store.DayKey(ev.time)<beforeDay then oldEvents[#oldEvents+1]=ev else keepEvents[#keepEvents+1]=ev end end
    local checkpoint,err=replay(DB,oldRows,oldEvents,DB.replayBase)
    if not checkpoint then return {ok=false,err=err} end
    for day,chars in pairs(DB.roll) do if day<beforeDay and not DB.archivedDays[day] then
        for c,items in pairs(chars) do for id,r in pairs(items) do
            local archived=ensure(ensure(DB.archivedRoll,c),id)
            for _,key in ipairs(rollFields) do archived[key]=(archived[key] or 0)+(r[key] or 0) end
            if (r.ahSold or 0)~=0 then archived.ahSold=(archived.ahSold or 0)+r.ahSold end
        end end
        DB.archivedDays[day]=true
        -- Keep daily aggregates as the compatibility projection used by the pre-WP11 Model.
    end end
    for day in pairs(DB.days) do if day<beforeDay then DB.days[day]=nil end end
    for day,chars in pairs(DB.loot) do if day~=Store.ARCHIVE_DAY and day<beforeDay then
        for c,counters in pairs(chars) do for key,qty in pairs(counters) do
            local dest=ensure(DB.archivedLoot,c); dest[key]=(dest[key] or 0)+qty
        end end
        DB.loot[day]=nil
    end end
    -- A reserved epoch-day aggregate exposes all-time totals to the schema-1 Model.
    -- Real daily counters are removed; rolling periods never include this projection.
    if next(DB.archivedLoot) then DB.loot[Store.ARCHIVE_DAY]=DB.archivedLoot end
    DB.replayBase=stateSnapshot(checkpoint); DB.basisEvents=keepEvents; DB.prunedBefore=beforeDay
    changed(); preview.ok=true; return preview
end

local function splitForeverCharKey(cKey)
    if type(cKey) ~= "string" or cKey == "" then return nil end
    if cKey == "Normal-Horde-Forever-Player" then return nil end
    if cKey:match("^%d%d%d%d%-%d%d%-%d%d$") then return nil end
    local prefix, name = cKey:match("^(.+)%-([^%-]+)$")
    if not prefix or prefix == "" or not name or name == "" then return nil end
    local first, rest = name:match("^([^%s]+)%s+(.+)$")
    if first and rest and rest ~= "" then
        return prefix, name, first, true
    end
    return prefix, name, name, false
end

local function mergeRollItemMap(dstItems, srcItems)
    if type(srcItems) ~= "table" then return end
    for itemID, sr in pairs(srcItems) do
        if type(sr) == "table" then
            local dr = ensure(dstItems, itemID)
            for k, v in pairs(sr) do
                if type(v) == "number" then
                    dr[k] = (tonumber(dr[k]) or 0) + v
                elseif dr[k] == nil then
                    dr[k] = v
                end
            end
        end
    end
end

local function mergeCounterMap(dstMap, srcMap)
    if type(srcMap) ~= "table" then return end
    for k, v in pairs(srcMap) do
        if type(v) == "number" then
            dstMap[k] = (tonumber(dstMap[k]) or 0) + v
        elseif dstMap[k] == nil then
            dstMap[k] = v
        end
    end
end

local function mergeDayStatsChar(dstStats, srcStats)
    if type(srcStats) ~= "table" then return end
    for k, v in pairs(srcStats) do
        if k == "tiers" and type(v) == "table" then
            local dstTiers = ensure(dstStats, "tiers")
            for tier, td in pairs(v) do
                if type(td) == "table" then
                    local dt = ensure(dstTiers, tier)
                    for tk, tv in pairs(td) do
                        if type(tv) == "number" then
                            dt[tk] = (tonumber(dt[tk]) or 0) + tv
                        elseif dt[tk] == nil then
                            dt[tk] = tv
                        end
                    end
                end
            end
        elseif type(v) == "number" then
            dstStats[k] = (tonumber(dstStats[k]) or 0) + v
        elseif dstStats[k] == nil then
            dstStats[k] = v
        end
    end
end

local function copyLiveStateKey(rootTbl, oldKey, newKey, allowEmptyOverwrite)
    if type(rootTbl) ~= "table" or rootTbl[oldKey] == nil then return false end
    local dst = rootTbl[newKey]
    if dst == nil or (allowEmptyOverwrite and type(dst) == "table" and next(dst) == nil) then
        rootTbl[newKey] = rootTbl[oldKey]
    end
    rootTbl[oldKey] = nil
    return true
end

local function packedDayContainsChar(raw, charKey)
    if type(raw) ~= "string" or raw == "" or type(charKey) ~= "string" or charKey == "" then return false end
    if strsub(raw, 1, 4) == "MM1:" then
        return strfind(raw, tostring(#charKey) .. ":" .. charKey, 1, true) ~= nil
    end
    return strfind(raw, "," .. charKey .. ",", 1, true) ~= nil
end

local function rewriteDayContainer(dayTbl, migrationMap, oldKeyList, clearCache)
    if type(dayTbl) ~= "table" then return false end
    local touched = false
    for day, d in pairs(dayTbl) do
        if type(d) == "table" then
            if type(d.r) == "table" then
                local dayChanged = false
                for _, row in ipairs(d.r) do
                    if type(row) == "table" and row.char and migrationMap[row.char] then
                        row.char = migrationMap[row.char]
                        dayChanged = true
                    end
                end
                if dayChanged then
                    touched = true
                    if clearCache then unpackedCache[day] = nil end
                end
            elseif type(d.s) == "string" and d.s ~= "" then
                local maybeHit = false
                for _, oldKey in ipairs(oldKeyList) do
                    if packedDayContainsChar(d.s, oldKey) then
                        maybeHit = true
                        break
                    end
                end
                if maybeHit then
                    local rows = Store.UnpackDayString(d.s)
                    local dayChanged = false
                    for _, row in ipairs(rows) do
                        if type(row) == "table" and row.char and migrationMap[row.char] then
                            row.char = migrationMap[row.char]
                            dayChanged = true
                        end
                    end
                    if dayChanged then
                        d.s = Store.PackRows(rows)
                        touched = true
                        if clearCache then unpackedCache[day] = nil end
                    end
                end
            end
        end
    end
    return touched
end

local function applyCharKeyMigration(migrationMap, oldKeyList, hostChars)
    local changedAny = false
    for _, oldKey in ipairs(oldKeyList) do
        local newKey = migrationMap[oldKey]
        -- 1. Live/current-state tables: copy ONLY if newKey missing, always delete oldKey (never resurrect ghost lots!)
        if copyLiveStateKey(DB.wealth, oldKey, newKey, false) then changedAny = true end
        if copyLiveStateKey(DB.inventory, oldKey, newKey, false) then changedAny = true end
        if copyLiveStateKey(DB.lots, oldKey, newKey, false) then changedAny = true end
        if copyLiveStateKey(DB.seenMail, oldKey, newKey, false) then changedAny = true end
        if copyLiveStateKey(DB.stats and DB.stats.lastStanding, oldKey, newKey, false) then changedAny = true end
        if copyLiveStateKey(DB.stats and DB.stats.recon, oldKey, newKey, false) then changedAny = true end
        if copyLiveStateKey(DB.ret, oldKey, newKey, true) then changedAny = true end
        if copyLiveStateKey(DB.pouches, oldKey, newKey, true) then changedAny = true end

        -- 2. Historical snaps: copy missing days only, delete oldKey
        if type(DB.snaps) == "table" and type(DB.snaps[oldKey]) == "table" then
            local dstSnaps = ensure(DB.snaps, newKey)
            for day, snap in pairs(DB.snaps[oldKey]) do
                if dstSnaps[day] == nil then dstSnaps[day] = snap end
            end
            DB.snaps[oldKey] = nil
            changedAny = true
        end

        -- 3. Historical roll & archivedRoll
        if type(DB.roll) == "table" then
            for _, byChar in pairs(DB.roll) do
                if type(byChar) == "table" and type(byChar[oldKey]) == "table" then
                    mergeRollItemMap(ensure(byChar, newKey), byChar[oldKey])
                    byChar[oldKey] = nil
                    changedAny = true
                end
            end
        end
        if type(DB.archivedRoll) == "table" then
            if type(DB.archivedRoll[oldKey]) == "table" then
                mergeRollItemMap(ensure(DB.archivedRoll, newKey), DB.archivedRoll[oldKey])
                DB.archivedRoll[oldKey] = nil
                changedAny = true
            end
            for day, byChar in pairs(DB.archivedRoll) do
                if type(day) == "string" and day:match("^%d%d%d%d%-%d%d%-%d%d$")
                    and type(byChar) == "table" and type(byChar[oldKey]) == "table" then
                    mergeRollItemMap(ensure(byChar, newKey), byChar[oldKey])
                    byChar[oldKey] = nil
                    changedAny = true
                end
            end
        end

        -- 4. Historical loot & archivedLoot (avoid double-merging Store.ARCHIVE_DAY alias)
        if type(DB.loot) == "table" then
            for _, byChar in pairs(DB.loot) do
                if type(byChar) == "table" and byChar ~= DB.archivedLoot and type(byChar[oldKey]) == "table" then
                    mergeCounterMap(ensure(byChar, newKey), byChar[oldKey])
                    byChar[oldKey] = nil
                    changedAny = true
                end
            end
        end
        if type(DB.archivedLoot) == "table" and type(DB.archivedLoot[oldKey]) == "table" then
            mergeCounterMap(ensure(DB.archivedLoot, newKey), DB.archivedLoot[oldKey])
            DB.archivedLoot[oldKey] = nil
            changedAny = true
        end

        -- 5. Daily summary stats
        if type(DB.dayStats) == "table" then
            for _, byChar in pairs(DB.dayStats) do
                if type(byChar) == "table" and type(byChar[oldKey]) == "table" then
                    mergeDayStatsChar(ensure(byChar, newKey), byChar[oldKey])
                    byChar[oldKey] = nil
                    changedAny = true
                end
            end
        end

        -- 6. Basis (legacy char-keyed basis if present)
        if type(DB.basis) == "table" and type(DB.basis[oldKey]) == "table" then
            local dstBasis = ensure(DB.basis, newKey)
            for itemID, sb in pairs(DB.basis[oldKey]) do
                if type(sb) == "table" then
                    local dbRec = dstBasis[itemID]
                    if type(dbRec) ~= "table" then
                        dstBasis[itemID] = copy(sb)
                    else
                        local q1 = tonumber(dbRec.qty) or 0
                        local q2 = tonumber(sb.qty) or 0
                        local a1 = tonumber(dbRec.avg) or 0
                        local a2 = tonumber(sb.avg) or 0
                        local totQ = q1 + q2
                        dbRec.qty = totQ
                        dbRec.avg = totQ > 0 and ((a1 * q1 + a2 * q2) / totQ) or 0
                    end
                end
            end
            DB.basis[oldKey] = nil
            changedAny = true
        end

        -- 7. Stats chars & firstLive
        if DB.stats.chars[oldKey] ~= nil then
            DB.stats.chars[newKey] = true
            DB.stats.chars[oldKey] = nil
            changedAny = true
        end
        if DB.stats.firstLive[oldKey] ~= nil then
            local oldT = tonumber(DB.stats.firstLive[oldKey])
            local newT = tonumber(DB.stats.firstLive[newKey])
            if oldT then
                DB.stats.firstLive[newKey] = newT and min(newT, oldT) or oldT
            end
            DB.stats.firstLive[oldKey] = nil
            changedAny = true
        end

        -- 8. replayBase consistency
        if type(DB.replayBase) == "table" then
            copyLiveStateKey(DB.replayBase.lots, oldKey, newKey, false)
            copyLiveStateKey(DB.replayBase.ret, oldKey, newKey, true)
            copyLiveStateKey(DB.replayBase.pouches, oldKey, newKey, true)
            copyLiveStateKey(DB.replayBase.recon, oldKey, newKey, false)
        end

        -- 9. Host MerchantMasterDB.chars cleanup (purge stale bags, merge non-bag fields)
        if type(hostChars) == "table" and type(hostChars[oldKey]) == "table" then
            local oldChar = hostChars[oldKey]
            local targetChar = hostChars[newKey]
            local _, newName, newFirst = splitForeverCharKey(newKey)
            if type(targetChar) ~= "table" then
                targetChar = {
                    name = newName or oldChar.name,
                    firstName = newFirst or oldChar.firstName,
                    realm = oldChar.realm,
                    faction = oldChar.faction,
                    economy = oldChar.economy,
                    guid = oldChar.guid,
                    bags = {},
                    boundBags = {},
                }
                hostChars[newKey] = targetChar
            else
                if newName and (type(targetChar.name) ~= "string" or targetChar.name == "") then targetChar.name = newName end
                if newFirst and (type(targetChar.firstName) ~= "string" or targetChar.firstName == "") then targetChar.firstName = newFirst end
                if targetChar.guid == nil and oldChar.guid ~= nil then targetChar.guid = oldChar.guid end
            end
            for _, fld in ipairs({ "bank", "boundBank", "mail", "knownSpells", "knownOutputs", "knownNames", "scannedProfs", "cooldowns", "cooldownGroups", "writCooldowns" }) do
                if type(oldChar[fld]) == "table" then
                    targetChar[fld] = type(targetChar[fld]) == "table" and targetChar[fld] or {}
                    for k, v in pairs(oldChar[fld]) do
                        if targetChar[fld][k] == nil then
                            targetChar[fld][k] = v
                        end
                    end
                end
            end
            hostChars[oldKey] = nil
            changedAny = true
        end
    end

    -- Rewrite raw day rows (unpacked + packed) and basisEvents in a single pass
    if rewriteDayContainer(DB.days, migrationMap, oldKeyList, true) then changedAny = true end
    if rewriteDayContainer(DB.archivedDays, migrationMap, oldKeyList, false) then changedAny = true end
    if type(DB.basisEvents) == "table" then
        for _, ev in ipairs(DB.basisEvents) do
            if type(ev) == "table" and ev.char and migrationMap[ev.char] then
                ev.char = migrationMap[ev.char]
                changedAny = true
            end
        end
    end
    if type(DB.inTransitMail) == "table" then
        for _, m in ipairs(DB.inTransitMail) do
            if type(m) == "table" then
                if m.toChar and migrationMap[m.toChar] then
                    m.toChar = migrationMap[m.toChar]
                    changedAny = true
                end
                if m.fromChar and migrationMap[m.fromChar] then
                    m.fromChar = migrationMap[m.fromChar]
                    changedAny = true
                end
            end
        end
    end

    -- Update saved Analytics character filters (single & multi-select) if pointing at migrated keys
    if type(_G.MerchantMasterDB) == "table" then
        if _G.MerchantMasterDB.anChar and migrationMap[_G.MerchantMasterDB.anChar] then
            _G.MerchantMasterDB.anChar = migrationMap[_G.MerchantMasterDB.anChar]
            changedAny = true
        end
        if type(_G.MerchantMasterDB.anChars) == "table" then
            local toMigrate = {}
            for k, v in pairs(_G.MerchantMasterDB.anChars) do
                if v and migrationMap[k] then
                    toMigrate[#toMigrate + 1] = k
                end
            end
            for _, oldK in ipairs(toMigrate) do
                _G.MerchantMasterDB.anChars[migrationMap[oldK]] = true
                _G.MerchantMasterDB.anChars[oldK] = nil
                changedAny = true
            end
        end
    end
    return changedAny
end

function Store.MigrateForeverSurnames(hostChars, activeKey)
    if not writable() then return 0, {} end
    local h = H()
    if hostChars == nil and type(_G.MerchantMasterDB) == "table" then
        hostChars = _G.MerchantMasterDB.chars
    end
    if activeKey == nil and h and h.app then
        activeKey = h.app.charKey
    end

    local allKeys = {}
    local function addKey(k)
        if type(k) == "string" and k ~= "" then
            allKeys[k] = true
        end
    end
    local function addKeysFrom(tbl)
        if type(tbl) ~= "table" then return end
        for k in pairs(tbl) do addKey(k) end
    end
    local function addNestedCharKeys(byDay)
        if type(byDay) ~= "table" then return end
        for _, byChar in pairs(byDay) do
            if type(byChar) == "table" then
                for cKey in pairs(byChar) do addKey(cKey) end
            end
        end
    end

    addKeysFrom(DB.wealth)
    addKeysFrom(DB.snaps)
    addKeysFrom(DB.inventory)
    addKeysFrom(DB.lots)
    addKeysFrom(DB.ret)
    addKeysFrom(DB.pouches)
    if type(DB.basis) == "table" then
        for k in pairs(DB.basis) do
            if type(k) == "string" then
                local pfx = k:match("^(.+)%-([^%-]+)$")
                if pfx and strfind(pfx, "-", 1, true) then addKey(k) end
            end
        end
    end
    if type(DB.stats) == "table" then
        addKeysFrom(DB.stats.chars)
        addKeysFrom(DB.stats.firstLive)
        addKeysFrom(DB.stats.lastStanding)
        addKeysFrom(DB.stats.recon)
    end
    addNestedCharKeys(DB.roll)
    if type(DB.archivedRoll) == "table" then
        for k, v in pairs(DB.archivedRoll) do
            if type(k) == "string" and k:match("^%d%d%d%d%-%d%d%-%d%d$") and type(v) == "table" then
                for cKey in pairs(v) do addKey(cKey) end
            else
                addKey(k)
            end
        end
    end
    addNestedCharKeys(DB.loot)
    addKeysFrom(DB.archivedLoot)
    addNestedCharKeys(DB.dayStats)
    if type(DB.days) == "table" then
        for _, d in pairs(DB.days) do
            if type(d) == "table" and type(d.r) == "table" then
                for _, row in ipairs(d.r) do
                    if type(row) == "table" then addKey(row.char) end
                end
            end
        end
    end
    if type(DB.basisEvents) == "table" then
        for _, ev in ipairs(DB.basisEvents) do
            if type(ev) == "table" then addKey(ev.char) end
        end
    end
    if type(DB.inTransitMail) == "table" then
        for _, m in ipairs(DB.inTransitMail) do
            if type(m) == "table" then
                addKey(m.toChar)
                addKey(m.fromChar)
            end
        end
    end
    addKeysFrom(hostChars)
    addKey(activeKey)

    local twoWordByBucket = {}
    local singleKeys = {}
    local singleSeen = {}
    for cKey in pairs(allKeys) do
        local prefix, _, first, isTwoWord = splitForeverCharKey(cKey)
        if prefix and first then
            local bucket = prefix:lower() .. "|" .. first:lower()
            if isTwoWord then
                local list = ensure(twoWordByBucket, bucket)
                list[#list + 1] = cKey
            else
                singleKeys[#singleKeys + 1] = cKey
                singleSeen[cKey] = true
            end
        end
    end
    for _, list in pairs(twoWordByBucket) do
        table.sort(list)
        if #list >= 1 and type(DB.days) == "table" then
            local pfx, _, fst = splitForeverCharKey(list[1])
            local synthOld = pfx and fst and (pfx .. "-" .. fst) or nil
            if synthOld and not singleSeen[synthOld] then
                for _, d in pairs(DB.days) do
                    if type(d) == "table" and packedDayContainsChar(d.s, synthOld) then
                        singleKeys[#singleKeys + 1] = synthOld
                        singleSeen[synthOld] = true
                        break
                    end
                end
            end
        end
    end
    table.sort(singleKeys)

    local migrationMap = {}
    local oldKeyList = {}
    for _, oldKey in ipairs(singleKeys) do
        local prefix, name = splitForeverCharKey(oldKey)
        local bucket = prefix and name and (prefix:lower() .. "|" .. name:lower())
        local cands = bucket and twoWordByBucket[bucket] or nil
        if cands and #cands > 0 then
            local oldHost = type(hostChars) == "table" and hostChars[oldKey] or nil
            local oldGuid = type(oldHost) == "table" and oldHost.guid or nil
            local target = nil
            if #cands == 1 then
                local cand = cands[1]
                local candHost = type(hostChars) == "table" and hostChars[cand] or nil
                local candGuid = type(candHost) == "table" and candHost.guid or nil
                if not (oldGuid and candGuid and oldGuid ~= candGuid) then
                    target = cand
                end
            elseif activeKey then
                local activeInCands = false
                for _, c in ipairs(cands) do
                    if c == activeKey then activeInCands = true; break end
                end
                if activeInCands and oldGuid then
                    local actHost = type(hostChars) == "table" and hostChars[activeKey] or nil
                    local actGuid = type(actHost) == "table" and actHost.guid or nil
                    if actGuid and oldGuid == actGuid then
                        target = activeKey
                    end
                end
            end
            if target and target ~= oldKey then
                migrationMap[oldKey] = target
                oldKeyList[#oldKeyList + 1] = oldKey
            end
        end
    end

    if #oldKeyList == 0 then return 0, {} end

    local changedAny = applyCharKeyMigration(migrationMap, oldKeyList, hostChars)
    if changedAny then
        unpackedCache = {}
        if ns.Model and ns.Model.Invalidate then ns.Model.Invalidate() end
        changed(nil, "accounting", true)
        return #oldKeyList, migrationMap
    end
    return 0, {}
end
