-- Bloomberg Desk Dashboard Data Engine (Pure ASCII Lua 5.1)
-- Single-pass cached ledger aggregator, stock universe builder, 4-slide broadcast
-- stage models, market headlines generator, and heatmap timing windows.
local _, ns = ...

local Model = {}
ns.DashboardBloombergModel = Model

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local format, tostring, tonumber, type = string.format, tostring, tonumber, type
local tsort, tconcat = table.sort, table.concat
local pcall, ipairs, pairs = pcall, ipairs, pairs

local C = {
    RANGE_DAYS = { ["24h"] = 1, ["7d"] = 7, ["14d"] = 14, ["30d"] = 30 },
    FILTER_ALIASES = {
        all = "all",
        watchlist = "watchlist",
        favs = "watchlist",
        favorites = "watchlist",
        crafts = "crafts",
        recipes = "crafts",
        reagents = "reagents",
        mats = "reagents",
        items = "reagents",
    },
    DOW_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" },
    MAX_LEDGER_CRAFTS = 16,
    MAX_LEDGER_ITEMS = 16,
    MAX_HEADLINES = 16,
    MAX_MOST_ACTIVE = 5,
    MAX_FALLBACK_STOCKS = 6,
    CRAFT_COST_PCT_THRESHOLD = 10.0,
    DEAL_DIP_PCT_THRESHOLD = -10.0,
    WATCH_MOVER_PCT_THRESHOLD = 8.0,
    DE_SPREAD_RATIO = 1.15,
    SURGE_VOL_RATIO = 1.50,
    SHORT_NAME_MAX = 26,
}

local CACHE = {
    ledger = { sig = nil, data = nil },
}

local H = {}

---------------------------------------------------------------------------------------------------
-- Core Safe Primitives & Formatting Helpers
---------------------------------------------------------------------------------------------------
function H.isSecret(v)
    return (_G.issecretvalue and _G.issecretvalue(v))
        or (type(v) == "table" and _G.issecrettable and _G.issecrettable(v))
end

function H.safeNum(v, fallback)
    if H.isSecret(v) then return fallback end
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

function H.posInt(v)
    local n = H.safeNum(v, nil)
    if not n or n <= 0 then return nil end
    return floor(n)
end

function H.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function H.nowSec(override)
    local ov = H.safeNum(override, nil)
    if ov and ov > 0 then return ov end
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and type(Store.Now) == "function" then
        local ok, t = pcall(Store.Now)
        local nt = ok and H.safeNum(t, nil) or nil
        if nt and nt > 0 then return nt end
    end
    if _G.time then
        local ok, t = pcall(_G.time)
        local nt = ok and H.safeNum(t, nil) or nil
        if nt and nt > 0 then return nt end
    end
    if os and os.time then
        return H.safeNum(os.time(), 0) or 0
    end
    return 0
end

function H.fmtDate(fmt, t)
    local fn = _G.date or (os and os.date)
    if type(fn) ~= "function" then return "" end
    local ok, val = pcall(fn, fmt, t)
    if not ok or H.isSecret(val) then return "" end
    return val
end

function H.dayKeyFromSec(t)
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and type(Store.DayKey) == "function" then
        local ok, k = pcall(Store.DayKey, t)
        if ok and type(k) == "string" and #k == 10 then return k end
    end
    local s = H.fmtDate("%Y-%m-%d", t)
    return (type(s) == "string" and #s == 10) and s or "1970-01-01"
end

function H.hourFromSec(t)
    local h = H.safeNum(H.fmtDate("%H", t), nil)
    if not h then
        local tbl = H.fmtDate("*t", t)
        if type(tbl) == "table" then h = H.safeNum(tbl.hour, 0) end
    end
    return H.clamp(floor(h or 0), 0, 23)
end

function H.formatCopper(copper, signed)
    if ns.DashboardBrief and type(ns.DashboardBrief.FormatCopper) == "function" then
        local ok, s = pcall(ns.DashboardBrief.FormatCopper, copper, signed)
        if ok and type(s) == "string" and s ~= "" then return s end
    end
    local v = H.safeNum(copper, 0) or 0
    local neg = v < 0
    local av = floor(abs(v) + 0.5)
    local g = floor(av / 10000)
    local s = floor((av % 10000) / 100)
    local c = av % 100
    local prefix = neg and "-" or ((signed and av > 0) and "+" or "")
    if g >= 1000 then
        return format("%s%dg", prefix, g)
    elseif g > 0 then
        if s > 0 then
            return format("%s%dg %ds", prefix, g, s)
        end
        return format("%s%dg", prefix, g)
    elseif s > 0 then
        if c > 0 and s < 10 then
            return format("%s%ds %dc", prefix, s, c)
        end
        return format("%s%ds", prefix, s)
    end
    return format("%s%dc", prefix, c)
end
Model.FormatCopper = H.formatCopper

function H.resolveEconKey(override)
    if type(override) == "string" and override ~= "" and not H.isSecret(override) then
        return override
    end
    if type(ns.DetectActiveEconomy) == "function" then
        local ok, ek = pcall(ns.DetectActiveEconomy)
        if ok and type(ek) == "string" and ek ~= "" and not H.isSecret(ek) then
            return ek
        end
    end
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and type(Store.CurrentCharAndEcon) == "function" then
        local ok, _, ek = pcall(Store.CurrentCharAndEcon)
        if ok and type(ek) == "string" and ek ~= "" and not H.isSecret(ek) then
            return ek
        end
    end
    return "Normal-Horde"
end

function H.normalizeRange(rangeKey)
    if type(rangeKey) == "string" and C.RANGE_DAYS[rangeKey] then
        return rangeKey
    end
    return "7d"
end

function H.normalizeFilter(filterKey)
    if type(filterKey) == "string" then
        local mapped = C.FILTER_ALIASES[filterKey:lower()]
        if mapped then return mapped end
    end
    return "all"
end

function H.matchesEcon(rowEcon, rowChar, targetEcon, Store)
    if not targetEcon or targetEcon == "all" then return true end
    local eff = rowEcon
    if (not eff or eff == "") and Store and type(Store.DeriveEcon) == "function" then
        local ok, derived = pcall(Store.DeriveEcon, rowChar)
        if ok and type(derived) == "string" and derived ~= "" then
            eff = derived
        end
    end
    return eff == targetEcon
end

function H.makeShortName(name)
    local s = type(name) == "string" and name or "ITEM"
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^[Rr]ecipe:%s*", "")
    s = s:gsub("^[Pp]attern:%s*", "")
    s = s:gsub("^[Pp]lans:%s*", "")
    s = s:gsub("^[Ss]chematic:%s*", "")
    s = s:gsub("^[Ff]ormula:%s*", "")
    s = s:upper()
    if #s > C.SHORT_NAME_MAX then
        s = s:sub(1, C.SHORT_NAME_MAX):gsub("[%s%-]+$", "")
    end
    return (s ~= "") and s or "ITEM"
end

---------------------------------------------------------------------------------------------------
-- Item, Recipe, Icon & Pricing Resolution Helpers
---------------------------------------------------------------------------------------------------
function H.resolveItemName(itemID, fallback)
    if type(fallback) == "string" and fallback ~= "" and not H.isSecret(fallback) then
        return fallback
    end
    local id = H.posInt(itemID)
    if not id then return "Unknown Item" end
    if type(ns.ITEMS) == "table" and type(ns.ITEMS[id]) == "table" and type(ns.ITEMS[id].name) == "string" and ns.ITEMS[id].name ~= "" then
        return ns.ITEMS[id].name
    end
    if type(ns.ITEM_NAMES_BY_ID) == "table" and type(ns.ITEM_NAMES_BY_ID[id]) == "string" and ns.ITEM_NAMES_BY_ID[id] ~= "" then
        return ns.ITEM_NAMES_BY_ID[id]
    end
    if _G.C_Item and type(_G.C_Item.GetItemInfo) == "function" then
        local ok, nm = pcall(_G.C_Item.GetItemInfo, id)
        if ok and type(nm) == "string" and nm ~= "" and not H.isSecret(nm) then return nm end
    end
    if type(_G.GetItemInfo) == "function" then
        local ok, nm = pcall(_G.GetItemInfo, id)
        if ok and type(nm) == "string" and nm ~= "" and not H.isSecret(nm) then return nm end
    end
    if _G.C_Item and type(_G.C_Item.GetItemNameByID) == "function" then
        local ok, nm = pcall(_G.C_Item.GetItemNameByID, id)
        if ok and type(nm) == "string" and nm ~= "" and not H.isSecret(nm) then return nm end
    end
    return "Item #" .. tostring(id)
end

function H.resolveItemIcon(itemID)
    local id = H.posInt(itemID)
    if not id then return ns.QUESTION_ICON end
    if _G.C_Item and type(_G.C_Item.GetItemIconByID) == "function" then
        local ok, ic = pcall(_G.C_Item.GetItemIconByID, id)
        if ok and ic and not H.isSecret(ic) then return ic end
    end
    if type(_G.GetItemIcon) == "function" then
        local ok, ic = pcall(_G.GetItemIcon, id)
        if ok and ic and not H.isSecret(ic) then return ic end
    end
    return ns.QUESTION_ICON
end

function H.lookupRecipeBySpell(spellID)
    local id = H.posInt(spellID)
    if not id then return nil end
    if type(ns.RECIPES_BY_SPELL) == "table" and ns.RECIPES_BY_SPELL[id] then
        return ns.RECIPES_BY_SPELL[id]
    end
    local AModel = ns.Analytics and ns.Analytics.Model
    if AModel and type(AModel.GetIndexes) == "function" then
        local ok, idx = pcall(AModel.GetIndexes)
        if ok and type(idx) == "table" and type(idx.RECIPE_BY_SPELL) == "table" and idx.RECIPE_BY_SPELL[id] then
            return idx.RECIPE_BY_SPELL[id]
        end
    end
    if type(ns.RECIPES) == "table" then
        for i = 1, #ns.RECIPES do
            local r = ns.RECIPES[i]
            if type(r) == "table" and H.posInt(r.spellID) == id then
                return r
            end
        end
    end
    return nil
end

function H.lookupRecipeByOutput(itemID)
    local id = H.posInt(itemID)
    if not id then return nil end
    if type(ns.RECIPES_BY_OUTPUT) == "table" and ns.RECIPES_BY_OUTPUT[id] then
        local entry = ns.RECIPES_BY_OUTPUT[id]
        if type(entry) == "table" then
            if entry.reagents or entry.spellID or entry.outputItemID then
                return entry
            end
            if type(entry[1]) == "table" then
                return entry[1]
            end
        end
    end
    if type(ns.RECIPES) == "table" then
        local best = nil
        for i = 1, #ns.RECIPES do
            local r = ns.RECIPES[i]
            if type(r) == "table" and H.posInt(r.outputItemID) == id and not r.isEnchant then
                if not best then
                    best = r
                else
                    local prevCD = (H.safeNum(best.cd, 0) or 0) > 0
                    local curCD = (H.safeNum(r.cd, 0) or 0) > 0
                    if prevCD and not curCD then
                        best = r
                    elseif prevCD == curCD and (H.safeNum(r.skill, 9999) or 9999) < (H.safeNum(best.skill, 9999) or 9999) then
                        best = r
                    end
                end
            end
        end
        return best
    end
    return nil
end

function H.getMarketPrice(itemID, econKey, priceBank)
    local id = H.posInt(itemID)
    if not id then return nil, nil end
    if type(ns.GetCanonicalItemPrice) == "function" then
        local ok, can = pcall(ns.GetCanonicalItemPrice, id, econKey)
        if ok and type(can) == "table" then
            local np = H.safeNum(can.price, nil)
            if np and np > 0 then
                return floor(np + 0.5), type(can.source) == "string" and can.source or "Market"
            end
            if can.isAbsent then
                return nil, can.source
            end
        end
    end
    if type(ns.GetItemMarketPrice) == "function" then
        local ok, p, src = pcall(ns.GetItemMarketPrice, id)
        local np = ok and H.safeNum(p, nil) or nil
        if np and np > 0 then
            return floor(np + 0.5), type(src) == "string" and src or "Market"
        end
    end
    return nil, nil
end

function H.getListedQty(itemID, econKey)
    local id = H.posInt(itemID)
    if not id then return 0 end
    if type(ns.GetCanonicalItemPrice) == "function" then
        local ok, can = pcall(ns.GetCanonicalItemPrice, id, econKey)
        if ok and type(can) == "table" and can.listed ~= nil then
            local nq = H.safeNum(can.listed, nil)
            if nq and nq >= 0 then
                return floor(nq + 0.5)
            end
        end
    end
    if type(ns.GetNumListed) == "function" then
        local ok, q = pcall(ns.GetNumListed, id)
        local nq = ok and H.safeNum(q, nil) or nil
        if nq and nq >= 0 then
            return floor(nq + 0.5)
        end
    end
    return 0
end

function H.getReagentUnitCost(rgID, econKey, priceBank)
    local id = H.posInt(rgID)
    if not id then return nil, nil, false end
    if type(ns.GetReagentUnitCost) == "function" then
        local ok, cost, src, isVendor = pcall(ns.GetReagentUnitCost, id)
        local nc = ok and H.safeNum(cost, nil) or nil
        if nc and nc > 0 then
            return floor(nc + 0.5), src, isVendor == true
        end
    end
    local p, src = H.getMarketPrice(id, econKey, priceBank)
    return p, src, false
end

function H.isWatchedStock(key, itemID, spellID)
    local WL = ns.Watchlist
    if type(WL) ~= "table" then return false end
    if type(WL.IsFavorite) == "function" then
        local ok, res = pcall(WL.IsFavorite, key)
        if ok and res == true then return true end
        if spellID then
            local ok2, res2 = pcall(WL.IsFavorite, "recipe:" .. tostring(spellID))
            if ok2 and res2 == true then return true end
        end
    end
    if itemID and type(WL.FindFavoriteForItem) == "function" then
        local ok, fav = pcall(WL.FindFavoriteForItem, itemID)
        if ok and fav ~= nil then return true end
    end
    return false
end

function H.formatHeatmapSlot(slot)
    if type(slot) ~= "table" then return "--" end
    local dow = H.posInt(slot.dow)
    local hr = H.safeNum(slot.hour, nil)
    local price = H.safeNum(slot.avgPrice, nil) or H.safeNum(slot.minPrice, nil)
    if not dow or not hr or not price or price <= 0 then return "--" end
    local dayName = C.DOW_NAMES[dow] or "Day"
    return format("%s %02d:00 (%s)", dayName, H.clamp(floor(hr), 0, 23), H.formatCopper(price))
end

function H.getHeatmapMemo(memo, itemID, econKey)
    local id = H.posInt(itemID)
    if not id then return nil end
    local hit = memo.heatmap[id]
    if hit ~= nil then return hit ~= false and hit or nil end
    local res = nil
    if ns.Pricing and type(ns.Pricing.GetItemHeatmap) == "function" then
        local ok, hm = pcall(ns.Pricing.GetItemHeatmap, id, econKey)
        if ok and type(hm) == "table" then
            res = hm
        end
    end
    memo.heatmap[id] = res or false
    return res
end

function H.getHeatStripMemo(memo, itemID, econKey)
    local id = H.posInt(itemID)
    if not id then return nil end
    local hit = memo.heatstrip[id]
    if hit ~= nil then return hit ~= false and hit or nil end
    local res = nil
    if ns.Pricing and type(ns.Pricing.GetItemHeatStrip24h) == "function" then
        local ok, hs = pcall(ns.Pricing.GetItemHeatStrip24h, id, econKey)
        if ok and type(hs) == "table" then
            res = hs
        end
    end
    memo.heatstrip[id] = res or false
    return res
end

function H.getTrend24Memo(memo, itemID, econKey, now)
    local id = H.posInt(itemID)
    if not id then return nil end
    local hit = memo.trend24[id]
    if hit ~= nil then return hit ~= false and hit or nil end
    local res = nil
    if ns.MarketScan and type(ns.MarketScan.GetItemTrend24h) == "function" then
        local ok, tr = pcall(ns.MarketScan.GetItemTrend24h, id, econKey, now)
        if ok and type(tr) == "table" then
            res = tr
        end
    end
    memo.trend24[id] = res or false
    return res
end

function H.getTrend7dMemo(memo, itemID, econKey, now)
    local id = H.posInt(itemID)
    if not id then return nil end
    local hit = memo.trend7d[id]
    if hit ~= nil then return hit ~= false and hit or nil end
    local res = nil
    if ns.MarketScan and type(ns.MarketScan.GetItemTrend7d) == "function" then
        local ok, tr = pcall(ns.MarketScan.GetItemTrend7d, id, econKey, now)
        if ok and type(tr) == "table" then
            res = tr
        end
    end
    memo.trend7d[id] = res or false
    return res
end

---------------------------------------------------------------------------------------------------
-- Single-Pass Cached Ledger Aggregator (30-Day Window)
---------------------------------------------------------------------------------------------------
function Model.InvalidateCache()
    CACHE.ledger.sig = nil
    CACHE.ledger.data = nil
end

function H.computeLedgerActivity(econKey, now)
    local Store = ns.Analytics and ns.Analytics.Store
    local WL = ns.Watchlist
    local todayKey = H.dayKeyFromSec(now)
    local storeVer = (Store and Store.version) or 0
    local ahVer = (Store and Store.ahSalesVersion) or 0
    local wlVer = (WL and type(WL.GetVersion) == "function" and H.safeNum(WL.GetVersion(), 0)) or 0
    local priceVer = (type(ns.GetPriceDataRevision) == "function" and H.safeNum(ns.GetPriceDataRevision(), 0))
        or (type(ns.GetEffectivePriceVersion) == "function" and H.safeNum(ns.GetEffectivePriceVersion(), 0)) or 0
    local hourBucket = floor(now / 3600)

    local sig = format("%s|%s|%s|%s|%s|%s|%d",
        tostring(storeVer), tostring(ahVer), tostring(wlVer),
        tostring(priceVer), todayKey, tostring(econKey or "all"), hourBucket)
    if CACHE.ledger.sig == sig and CACHE.ledger.data then
        return CACHE.ledger.data
    end

    local fromDay30 = H.dayKeyFromSec(now - 29 * 86400)
    local craftBySpell = {}
    local craftByItem = {}
    local sellByItem = {}
    local buyByItem = {}

    if Store and type(Store.IterDays) == "function" then
        pcall(Store.IterDays, fromDay30, todayKey, function(_, rows)
            for i = 1, #(rows or {}) do
                local r = rows[i]
                if type(r) == "table" and H.matchesEcon(r.econ, r.char, econKey, Store) then
                    local rType = r.type
                    local e = type(r.extra) == "table" and r.extra or nil
                    local qty = max(1, H.safeNum(r.qty, 1) or 1)
                    local ts = H.safeNum(r.time, 0) or 0
                    local oid = H.posInt(r.itemID)
                    local rName = (e and type(e.name) == "string" and e.name ~= "" and not H.isSecret(e.name)) and e.name or nil

                    if rType == "CRAFT" then
                        local sp = e and H.posInt(e.spellID) or nil
                        local cost = H.safeNum(r.cogs, nil)
                        if not cost or cost <= 0 then
                            cost = e and H.safeNum(e.reagentCost, nil) or nil
                        end
                        if not cost or cost <= 0 then
                            local ec = e and H.safeNum(e.craftCost, nil) or nil
                            if ec and ec > 0 then cost = ec * qty end
                        end
                        if not cost or cost <= 0 then
                            local tot = H.safeNum(r.total, nil)
                            if tot and tot ~= 0 then cost = abs(tot) end
                        end
                        if not cost or cost <= 0 then
                            local u = H.safeNum(r.unit, nil)
                            if u and u > 0 then cost = u * qty end
                        end
                        local hasCost = (cost ~= nil and cost > 0)

                        if sp then
                            local rec = craftBySpell[sp]
                            if not rec then
                                rec = {
                                    spellID = sp,
                                    itemID = oid,
                                    name = rName,
                                    craftCount = 0,
                                    craftCostSum = 0,
                                    craftCostQty = 0,
                                    lastTime = 0,
                                }
                                craftBySpell[sp] = rec
                            end
                            rec.craftCount = rec.craftCount + qty
                            if hasCost then
                                rec.craftCostSum = rec.craftCostSum + cost
                                rec.craftCostQty = rec.craftCostQty + qty
                            end
                            if oid and not rec.itemID then rec.itemID = oid end
                            if rName and not rec.name then rec.name = rName end
                            if ts > rec.lastTime then rec.lastTime = ts end
                        end

                        if oid then
                            local rec = craftByItem[oid]
                            if not rec then
                                rec = {
                                    itemID = oid,
                                    spellID = sp,
                                    name = rName,
                                    craftCount = 0,
                                    craftCostSum = 0,
                                    craftCostQty = 0,
                                    lastTime = 0,
                                }
                                craftByItem[oid] = rec
                            end
                            rec.craftCount = rec.craftCount + qty
                            if hasCost then
                                rec.craftCostSum = rec.craftCostSum + cost
                                rec.craftCostQty = rec.craftCostQty + qty
                            end
                            if sp and not rec.spellID then rec.spellID = sp end
                            if rName and not rec.name then rec.name = rName end
                            if ts > rec.lastTime then rec.lastTime = ts end
                        end

                    elseif rType == "AH_SELL" and oid then
                        local fee = (e and H.safeNum(e.fee, 0)) or 0
                        local net = H.safeNum(r.total, 0) or 0
                        local gross = (e and H.safeNum(e.gross, nil)) or max(0, net + fee)
                        local cogs = H.safeNum(r.cogs, 0) or 0
                        local profit = (gross - fee) - cogs

                        local rec = sellByItem[oid]
                        if not rec then
                            rec = {
                                itemID = oid,
                                name = rName,
                                sellCount = 0,
                                sellEvents = 0,
                                sellProfitSum = 0,
                                sellNetSum = 0,
                                sellCogsSum = 0,
                                sellCogsQty = 0,
                                lastTime = 0,
                            }
                            sellByItem[oid] = rec
                        end
                        rec.sellCount = rec.sellCount + qty
                        rec.sellEvents = rec.sellEvents + 1
                        rec.sellProfitSum = rec.sellProfitSum + profit
                        rec.sellNetSum = rec.sellNetSum + net
                        if cogs > 0 then
                            rec.sellCogsSum = rec.sellCogsSum + cogs
                            rec.sellCogsQty = rec.sellCogsQty + qty
                        end
                        if rName and not rec.name then rec.name = rName end
                        if ts > rec.lastTime then rec.lastTime = ts end

                    elseif rType == "AH_BUY" and oid then
                        local tot = H.safeNum(r.total, nil)
                        local spend = 0
                        if tot and tot ~= 0 then
                            spend = abs(tot)
                        else
                            local u = H.safeNum(r.unit, nil)
                            if u and u > 0 then spend = u * qty end
                        end

                        local rec = buyByItem[oid]
                        if not rec then
                            rec = {
                                itemID = oid,
                                name = rName,
                                buyCount = 0,
                                buyEvents = 0,
                                buySpendSum = 0,
                                buySpendQty = 0,
                                lastTime = 0,
                            }
                            buyByItem[oid] = rec
                        end
                        rec.buyCount = rec.buyCount + qty
                        rec.buyEvents = rec.buyEvents + 1
                        if spend > 0 then
                            rec.buySpendSum = rec.buySpendSum + spend
                            rec.buySpendQty = rec.buySpendQty + qty
                        end
                        if rName and not rec.name then rec.name = rName end
                        if ts > rec.lastTime then rec.lastTime = ts end
                    end
                end
            end
        end, { desc = true })
    end

    for _, rec in pairs(buyByItem) do
        if rec.buySpendQty > 0 then
            rec.ledgerAvgBuyPrice = floor(rec.buySpendSum / rec.buySpendQty + 0.5)
        end
    end
    for _, rec in pairs(craftBySpell) do
        if rec.craftCostQty > 0 then
            rec.ledgerAvgCraftCost = floor(rec.craftCostSum / rec.craftCostQty + 0.5)
        end
    end
    for _, rec in pairs(craftByItem) do
        if rec.craftCostQty > 0 then
            rec.ledgerAvgCraftCost = floor(rec.craftCostSum / rec.craftCostQty + 0.5)
        end
    end
    for _, rec in pairs(sellByItem) do
        if rec.sellCogsQty > 0 then
            rec.ledgerAvgSellCogs = floor(rec.sellCogsSum / rec.sellCogsQty + 0.5)
        end
    end

    local data = {
        todayKey = todayKey,
        fromDay30 = fromDay30,
        craftBySpell = craftBySpell,
        craftByItem = craftByItem,
        sellByItem = sellByItem,
        buyByItem = buyByItem,
    }
    CACHE.ledger.sig = sig
    CACHE.ledger.data = data
    return data
end

---------------------------------------------------------------------------------------------------
-- Summary & Wealth Series Adapters (Reuse DashboardBrief cleanly with standalone fallbacks)
---------------------------------------------------------------------------------------------------
function H.getAHSalesSummary(econKey, rangeKey, now)
    local Brief = ns.DashboardBrief
    if Brief and type(Brief.ComputeAHSalesSummary) == "function" then
        local ok, res = pcall(Brief.ComputeAHSalesSummary, econKey, rangeKey, now)
        if ok and type(res) == "table" then
            return res
        end
    end
    local todayKey = H.dayKeyFromSec(now)
    local yesterdayKey = H.dayKeyFromSec(now - 86400)
    local curHourFloor = floor(now / 3600) * 3600
    local start24h = curHourFloor - 23 * 3600
    local numDays = C.RANGE_DAYS[rangeKey] or 7
    local hourlyBars, dailyBars = {}, {}
    for i = 1, 24 do
        local ts = start24h + (i - 1) * 3600
        local lbl = format("%02d:00", H.hourFromSec(ts))
        hourlyBars[i] = { day = H.dayKeyFromSec(ts) .. " " .. lbl, label = lbl, value = 0, sortKey = ts }
    end
    for dOff = numDays - 1, 0, -1 do
        local dk = H.dayKeyFromSec(now - dOff * 86400)
        dailyBars[#dailyBars + 1] = { day = dk, label = dk:sub(6), value = 0 }
    end
    return {
        rangeKey = rangeKey,
        todayKey = todayKey,
        yesterdayKey = yesterdayKey,
        todayProfit = 0,
        todaySalesCount = 0,
        yesterdayProfit = 0,
        yesterdaySalesCount = 0,
        avg7dCompleted = 0,
        yesterdayDeltaPct = nil,
        rangeTotalProfit = 0,
        rangeSalesCount = 0,
        dailyBars = dailyBars,
        hourlyBars = hourlyBars,
        profitBars = (rangeKey == "24h") and hourlyBars or dailyBars,
        recentSales = {},
        topItems = {},
        bestItem = nil,
        bestSingleSale = nil,
    }
end

function H.getWealthSeries(wealthMode, rangeKey, econKey, portfolio, now)
    local Brief = ns.DashboardBrief
    if Brief and type(Brief.BuildWealthChartSeries) == "function" then
        local ok, res = pcall(Brief.BuildWealthChartSeries, wealthMode or "auto", rangeKey, econKey, portfolio, now)
        if ok and type(res) == "table" then
            return res
        end
    end
    local liveGold = (_G.GetMoney and H.safeNum(_G.GetMoney(), 0)) or 0
    return {
        mode = "hourly",
        points = {},
        usedFallback = true,
        isLedgerDerived = false,
        latestTotal = liveGold,
        change24h = 0,
        dailyCount = 0,
    }
end

---------------------------------------------------------------------------------------------------
-- Historical Price & Volume Series Builder (24h / 7d / 14d / 30d)
---------------------------------------------------------------------------------------------------
function H.buildItemSeries(itemID, rangeKey, econKey, now, ahPrice, curVol, memo)
    local id = H.posInt(itemID)
    if not id then
        return {}, nil, nil, nil, nil, "none"
    end
    local points = {}
    local source = "none"
    local curDay = floor(now / 86400)
    local curHour = floor(now / 3600)
    local startHour = curHour - 23

    if rangeKey == "24h" then
        local tr24 = H.getTrend24Memo(memo, id, econKey, now)
        if tr24 and type(tr24.points) == "table" and #tr24.points > 0 then
            source = tr24.source or "ahSnapshots"
            for i = 1, #tr24.points do
                local pt = tr24.points[i]
                if type(pt) == "table" then
                    local val = H.safeNum(pt.price, nil) or H.safeNum(pt.observedPrice, nil)
                    if val and val > 0 then
                        local ts = H.safeNum(pt.at, nil) or (H.safeNum(pt.h, nil) and pt.h * 3600) or now
                        local qty = H.safeNum(pt.qty, 0) or 0
                        points[#points + 1] = {
                            label = format("%02d:00", H.hourFromSec(ts)),
                            value = floor(val + 0.5),
                            volume = max(0, floor(qty + 0.5)),
                            ts = ts,
                            h = H.safeNum(pt.h, nil) or floor(ts / 3600),
                            fromSnapshot = (tr24.source == "snapshot"),
                        }
                    end
                end
            end
        end

        if #points == 0 then
            local strip = H.getHeatStripMemo(memo, id, econKey)
            local hm = (not strip or type(strip.hourly) ~= "table") and H.getHeatmapMemo(memo, id, econKey) or nil
            if strip and type(strip.hourly) == "table" then
                source = "snapshot"
                local defQty = max(0, floor((H.safeNum(strip.avgQty, 0) or 0) + 0.5))
                for h = startHour, curHour do
                    local ts = min(now, h * 3600)
                    local clk = H.hourFromSec(ts)
                    local p = H.safeNum(strip.hourly[clk], nil)
                    if p and p > 0 then
                        points[#points + 1] = {
                            label = format("%02d:00", clk),
                            value = floor(p + 0.5),
                            volume = defQty,
                            ts = ts,
                            h = h,
                            fromSnapshot = true,
                        }
                    end
                end
            elseif hm and type(hm.hourly) == "table" then
                source = "snapshot"
                for h = startHour, curHour do
                    local ts = min(now, h * 3600)
                    local clk = H.hourFromSec(ts)
                    local hRec = hm.hourly[clk]
                    local p = type(hRec) == "table" and H.safeNum(hRec.avgPrice, nil) or nil
                    if p and p > 0 then
                        local q = max(0, floor((H.safeNum(hRec.avgQty, 0) or 0) + 0.5))
                        points[#points + 1] = {
                            label = format("%02d:00", clk),
                            value = floor(p + 0.5),
                            volume = q,
                            ts = ts,
                            h = h,
                            fromSnapshot = true,
                        }
                    end
                end
            end
        end

        if #points == 0 then
            local db = _G.MerchantMasterDB
            local MS = ns.MarketScan
            if type(db) == "table" and type(db.ahHistory) == "table"
                and type(db.ahHistory[econKey]) == "table"
                and MS and type(MS.ReadHistory) == "function" then
                local raw = db.ahHistory[econKey][id]
                local ok, ring = pcall(MS.ReadHistory, raw)
                if ok and type(ring) == "table" and #ring > 0 then
                    source = "ahHistory"
                    for i = 1, #ring do
                        local r = ring[i]
                        local ts = type(r) == "table" and H.safeNum(r.t, nil) or nil
                        local p = type(r) == "table" and H.safeNum(r.p, nil) or nil
                        local q = type(r) == "table" and H.safeNum(r.q, 0) or 0
                        if ts and ts >= startHour * 3600 and ts <= now and p and p > 0 then
                            points[#points + 1] = {
                                label = format("%02d:00", H.hourFromSec(ts)),
                                value = floor(p + 0.5),
                                volume = max(0, floor(q + 0.5)),
                                ts = ts,
                                h = floor(ts / 3600),
                            }
                        end
                    end
                    tsort(points, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
                end
            end
        end
    else
        local numDays = C.RANGE_DAYS[rangeKey] or 7
        local fromDay = curDay - (numDays - 1)
        local byDay = {}
        local liveDays = 0
        local snapDays = 0

        local db = _G.MerchantMasterDB
        local MS = ns.MarketScan
        local openByDay, snapMinByDay, snapMaxByDay = {}, {}, {}
        if type(db) == "table" and type(db.ahSnapshots) == "table"
            and type(db.ahSnapshots[econKey]) == "table"
            and MS and type(MS.ReadSnapshots) == "function" then
            local rawSnap = db.ahSnapshots[econKey][id]
            local okS, flat = pcall(MS.ReadSnapshots, rawSnap)
            if okS and type(flat) == "table" and #flat >= 3 then
                local earliestAt = {}
                for k = 1, #flat - 2, 3 do
                    local ts = H.safeNum(flat[k], nil)
                    local sp = H.safeNum(flat[k + 1], nil)
                    if ts and sp and sp > 0 then
                        local sd = floor(ts / 86400)
                        if sd >= fromDay and sd <= curDay then
                            local sf = floor(sp + 0.5)
                            if not earliestAt[sd] or ts < earliestAt[sd] then
                                earliestAt[sd] = ts
                                openByDay[sd] = sf
                            end
                            snapMinByDay[sd] = snapMinByDay[sd] and min(snapMinByDay[sd], sf) or sf
                            snapMaxByDay[sd] = snapMaxByDay[sd] and max(snapMaxByDay[sd], sf) or sf
                        end
                    end
                end
            end
        end

        if type(db) == "table" and type(db.ahDaily) == "table"
            and type(db.ahDaily[econKey]) == "table"
            and MS and type(MS.ReadDaily) == "function" then
            local raw = db.ahDaily[econKey][id]
            local ok, buckets = pcall(MS.ReadDaily, raw)
            if ok and type(buckets) == "table" then
                for i = 1, #buckets do
                    local b = buckets[i]
                    local d = type(b) == "table" and H.safeNum(b.d, nil) or nil
                    if d and d % 1 == 0 and d >= fromDay and d <= curDay then
                        local p = H.safeNum(b.lastP, nil) or H.safeNum(b.price, nil) or H.safeNum(b.obsP, nil)
                        if p and p > 0 then
                            local q = H.safeNum(b.lastQ, nil) or H.safeNum(b.qty, 0) or 0
                            local loP = H.safeNum(b.minP, nil)
                            local hiP = H.safeNum(b.maxP, nil)
                            local fLo = (loP and loP > 0) and floor(loP + 0.5) or snapMinByDay[d]
                            local fHi = (hiP and hiP > 0) and floor(hiP + 0.5) or snapMaxByDay[d]
                            if snapMinByDay[d] then fLo = fLo and min(fLo, snapMinByDay[d]) or snapMinByDay[d] end
                            if snapMaxByDay[d] then fHi = fHi and max(fHi, snapMaxByDay[d]) or snapMaxByDay[d] end
                            byDay[d] = {
                                d = d,
                                value = floor(p + 0.5),
                                volume = max(0, floor(q + 0.5)),
                                open = H.safeNum(b.openP, nil) or openByDay[d],
                                minP = fLo,
                                maxP = fHi,
                                ts = H.safeNum(b.at, nil) or (d * 86400 + 43200),
                                fromSnapshot = false,
                            }
                            liveDays = liveDays + 1
                        end
                    end
                end
            end
        end

        local tr7 = H.getTrend7dMemo(memo, id, econKey, now)
        if tr7 and type(tr7.points) == "table" then
            for i = 1, #tr7.points do
                local pt = tr7.points[i]
                local d = type(pt) == "table" and H.safeNum(pt.d, nil) or nil
                local p = type(pt) == "table" and H.safeNum(pt.price, nil) or nil
                if d and d % 1 == 0 and d >= fromDay and d <= curDay and p and p > 0 and not byDay[d] then
                    local q = H.safeNum(pt.qty, 0) or 0
                    local isSnap = (tr7.source == "snapshot")
                    byDay[d] = {
                        d = d,
                        value = floor(p + 0.5),
                        volume = max(0, floor(q + 0.5)),
                        open = openByDay[d],
                        minP = snapMinByDay[d],
                        maxP = snapMaxByDay[d],
                        ts = H.safeNum(pt.at, nil) or (d * 86400 + 43200),
                        fromSnapshot = isSnap,
                    }
                    if isSnap then
                        snapDays = snapDays + 1
                    else
                        liveDays = liveDays + 1
                    end
                end
            end
        end

        local hm = H.getHeatmapMemo(memo, id, econKey)
        if hm and type(hm.daily) == "table" then
            for d = fromDay, curDay do
                if not byDay[d] then
                    local dow = ((d + 3) % 7) + 1
                    local dayRec = hm.daily[dow]
                    local avgP = type(dayRec) == "table" and H.safeNum(dayRec.avgPrice, nil) or nil
                    if avgP and avgP > 0 then
                        local avgQ = H.safeNum(dayRec.avgQty, 0) or 0
                        byDay[d] = {
                            d = d,
                            value = floor(avgP + 0.5),
                            volume = max(0, floor(avgQ + 0.5)),
                            minP = H.safeNum(dayRec.minPrice, nil),
                            maxP = H.safeNum(dayRec.maxPrice, nil),
                            ts = min(now, d * 86400 + 43200),
                            fromSnapshot = true,
                        }
                        snapDays = snapDays + 1
                    end
                end
            end
        end

        for d = fromDay, curDay do
            local entry = byDay[d]
            if entry then
                -- Anchor daily label at noon UTC of bucket day d so late-night timestamps never shift dates across local midnight
                local dk = H.dayKeyFromSec(d * 86400 + 43200)
                points[#points + 1] = {
                    d = d,
                    day = dk,
                    label = dk:sub(6),
                    value = entry.value,
                    volume = entry.volume,
                    open = entry.open,
                    minP = entry.minP,
                    maxP = entry.maxP,
                    ts = entry.ts,
                    fromSnapshot = entry.fromSnapshot,
                }
            end
        end

        if liveDays > 0 and snapDays > 0 then
            source = "merged"
        elseif liveDays > 0 then
            source = (tr7 and tr7.source and tr7.source ~= "none") and tr7.source or "ahDaily"
        elseif snapDays > 0 then
            source = "snapshot"
        end
    end

    -- Align final chart tip with current canonical AH price so chart headline matches spot price
    if #points > 0 and ahPrice and ahPrice > 0 then
        points[#points].value = ahPrice
        if curVol and curVol > 0 then
            points[#points].volume = curVol
        end
    end

    -- Populate genuine OHLC fields for candlesticks from recorded open / minP / maxP / close
    local prevClose = nil
    for i = 1, #points do
        local pt = points[i]
        local closeV = floor(H.safeNum(pt.value, 0) or 0)
        local openV = H.safeNum(pt.open, nil)
        openV = (openV and openV > 0) and floor(openV + 0.5) or (prevClose or closeV)
        local pLo = H.safeNum(pt.minP, nil)
        local pHi = H.safeNum(pt.maxP, nil)
        local lowV = min(openV, closeV, (pLo and pLo > 0) and floor(pLo + 0.5) or closeV)
        local highV = max(openV, closeV, (pHi and pHi > 0) and floor(pHi + 0.5) or closeV)
        pt.open = openV
        pt.high = highV
        pt.low = lowV
        pt.close = closeV
        prevClose = closeV
    end

    -- Compute hi, lo, avgVol, baseline (mean of prior points when >= 2, else fallback)
    local hi, lo = nil, nil
    local volSum, volCount = 0, 0
    local priorSum, priorCount = 0, 0
    local allSum, allCount = 0, 0
    local nPts = #points
    for i = 1, nPts do
        local pt = points[i]
        local v = pt.value
        if v and v > 0 then
            if not hi or v > hi then hi = v end
            if not lo or v < lo then lo = v end
            allSum = allSum + v
            allCount = allCount + 1
            if i < nPts then
                priorSum = priorSum + v
                priorCount = priorCount + 1
            end
        end
        if pt.volume and pt.volume > 0 then
            volSum = volSum + pt.volume
            volCount = volCount + 1
        end
    end

    if ahPrice and ahPrice > 0 then
        if not hi or ahPrice > hi then hi = ahPrice end
        if not lo or ahPrice < lo then lo = ahPrice end
    end

    local baseline = nil
    if priorCount > 0 then
        baseline = floor(priorSum / priorCount + 0.5)
    elseif allCount > 0 then
        baseline = floor(allSum / allCount + 0.5)
    else
        local hm = H.getHeatmapMemo(memo, id, econKey)
        local hmAvg = hm and type(hm.overall) == "table" and H.safeNum(hm.overall.avgPrice, nil) or nil
        if hmAvg and hmAvg > 0 then
            baseline = floor(hmAvg + 0.5)
        elseif type(ns.QueryLocalSnapshot) == "function" then
            local ok, _, snapRec = pcall(ns.QueryLocalSnapshot, id, econKey)
            if ok and type(snapRec) == "table" then
                local sp = H.safeNum(snapRec.historical, nil) or H.safeNum(snapRec.marketValue, nil)
                if sp and sp > 0 then baseline = floor(sp + 0.5) end
            end
        end
    end

    local avgVol = (volCount > 0) and (volSum / volCount) or nil
    return points, baseline, hi, lo, avgVol, source
end

function H.computeReagentBaseline(rgID, econKey, now, memo)
    local id = H.posInt(rgID)
    if not id then return nil end
    local curDay = floor(now / 86400)

    local tr7 = H.getTrend7dMemo(memo, id, econKey, now)
    if tr7 and type(tr7.points) == "table" and #tr7.points > 0 then
        local sum, cnt = 0, 0
        local allSum, allCnt = 0, 0
        for i = 1, #tr7.points do
            local pt = tr7.points[i]
            local p = type(pt) == "table" and H.safeNum(pt.price, nil) or nil
            local d = type(pt) == "table" and H.safeNum(pt.d, nil) or nil
            if p and p > 0 then
                allSum = allSum + p
                allCnt = allCnt + 1
                if d and d < curDay then
                    sum = sum + p
                    cnt = cnt + 1
                end
            end
        end
        if cnt > 0 then return floor(sum / cnt + 0.5) end
        if allCnt >= 2 then
            local lastP = H.safeNum(tr7.points[#tr7.points].price, 0) or 0
            if allSum > lastP then
                return floor((allSum - lastP) / (allCnt - 1) + 0.5)
            end
        end
    end

    local hs = H.getHeatStripMemo(memo, id, econKey)
    if hs then
        local avgP = H.safeNum(hs.avgPrice, nil) or H.safeNum(hs.medianPrice, nil)
        if avgP and avgP > 0 then return floor(avgP + 0.5) end
    end

    local hm = H.getHeatmapMemo(memo, id, econKey)
    if hm and type(hm.overall) == "table" then
        local avgP = H.safeNum(hm.overall.avgPrice, nil)
        if avgP and avgP > 0 then return floor(avgP + 0.5) end
    end

    if type(ns.QueryLocalSnapshot) == "function" then
        local ok, _, snapRec = pcall(ns.QueryLocalSnapshot, id, econKey)
        if ok and type(snapRec) == "table" then
            local sp = H.safeNum(snapRec.historical, nil) or H.safeNum(snapRec.marketValue, nil)
            if sp and sp > 0 then return floor(sp + 0.5) end
        end
    end
    return nil
end

---------------------------------------------------------------------------------------------------
-- Recipe Economics & Top Cost Driver Evaluator
---------------------------------------------------------------------------------------------------
function H.evaluateRecipeEconomics(recipe, ahPrice, econKey, now, priceBank, memo)
    if type(recipe) ~= "table" then
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    end

    local numMade = max(1, H.safeNum(recipe.numMade, 1) or 1)
    local craftCost = nil
    local breakdown = {}

    if type(ns.EvaluateRecipe) == "function" then
        local ok, ev = pcall(ns.EvaluateRecipe, recipe, { econKey = econKey, priceBank = priceBank })
        if ok and type(ev) == "table" then
            local cc = H.safeNum(ev.craftCost, nil)
            if cc and cc > 0 then craftCost = floor(cc + 0.5) end
        end
    end

    local reagents = nil
    if type(ns.ResolveRecipeReagents) == "function" then
        local ok, res = pcall(ns.ResolveRecipeReagents, recipe)
        if ok and type(res) == "table" then reagents = res end
    end
    if not reagents then reagents = recipe.reagents end

    local topDriverID, topDriverName, topDriverPct = nil, nil, nil
    local topDriverUnit, topDriverBase, topDriverQty = nil, nil, nil
    local topDriverImpact = 0

    if type(reagents) == "table" and #reagents > 0 then
        local sum = 0
        local complete = true
        for i = 1, #reagents do
            local rg = reagents[i]
            local rgID = type(rg) == "table" and H.posInt(rg.itemID or rg[1]) or nil
            local rgQty = type(rg) == "table" and H.safeNum(rg.qty or rg[2], nil) or nil
            if rgID and rgQty and rgQty > 0 then
                local unitCost, src, isVendor = H.getReagentUnitCost(rgID, econKey, priceBank)
                if unitCost and unitCost > 0 then
                    sum = sum + unitCost * rgQty
                else
                    complete = false
                end
                local baseUnit = (not isVendor) and H.computeReagentBaseline(rgID, econKey, now, memo) or nil
                local rgPct = nil
                if unitCost and unitCost > 0 and baseUnit and baseUnit > 0 then
                    rgPct = ((unitCost - baseUnit) / baseUnit) * 100
                    local impact = abs(unitCost - baseUnit) * rgQty
                    if impact > topDriverImpact or (impact == topDriverImpact and topDriverPct and abs(rgPct) > abs(topDriverPct)) then
                        topDriverImpact = impact
                        topDriverID = rgID
                        topDriverName = H.resolveItemName(rgID)
                        topDriverPct = rgPct
                        topDriverUnit = unitCost
                        topDriverBase = baseUnit
                        topDriverQty = rgQty
                    end
                end
                breakdown[#breakdown + 1] = {
                    itemID = rgID,
                    name = H.resolveItemName(rgID),
                    qty = rgQty,
                    unitCost = unitCost,
                    baselineUnit = baseUnit,
                    deltaPct = rgPct,
                    source = src,
                    isVendor = isVendor == true,
                }
            end
        end
        if not craftCost and complete and sum > 0 then
            craftCost = floor((sum / numMade) + 0.5)
        end
    end

    -- Fallback driver: largest single cost share reagent if no baseline shift detected
    if not topDriverName and #breakdown > 0 then
        local maxShare = 0
        for i = 1, #breakdown do
            local b = breakdown[i]
            local share = (b.unitCost or 0) * (b.qty or 0)
            if share > maxShare then
                maxShare = share
                topDriverID = b.itemID
                topDriverName = b.name
                topDriverPct = b.deltaPct
                topDriverUnit = b.unitCost
                topDriverBase = b.baselineUnit
                topDriverQty = b.qty
            end
        end
    end

    local netProfit, marginPct = nil, nil
    if craftCost and craftCost > 0 and ahPrice and ahPrice > 0 then
        local netSale = floor(ahPrice * 0.95 + 0.5)
        netProfit = netSale - craftCost
        marginPct = (netProfit / craftCost) * 100
    end

    return craftCost, netProfit, marginPct, topDriverID, topDriverName, topDriverPct,
        topDriverUnit, topDriverBase, topDriverQty, breakdown
end

---------------------------------------------------------------------------------------------------
-- Stock Universe Builder & Candidate Gathering
---------------------------------------------------------------------------------------------------
function H.gatherCandidates(ledger, econKey)
    local candidates = {}
    local seenKey = {}
    local seenItem = {}

    local function addCandidate(key, kind, spellID, itemID, nameHint, isWatched, sourceRank)
        if not key or seenKey[key] then return end
        seenKey[key] = true
        if itemID and not seenItem[itemID] then
            seenItem[itemID] = key
        end
        candidates[#candidates + 1] = {
            key = key,
            kind = kind,
            spellID = spellID,
            itemID = itemID,
            nameHint = nameHint,
            isWatched = isWatched == true,
            sourceRank = sourceRank or 10,
        }
    end

    -- 1. All Watchlist entries
    local WL = ns.Watchlist
    local watchlistCount = 0
    if WL and type(WL.GetEntries) == "function" then
        local ok, entries = pcall(WL.GetEntries)
        if ok and type(entries) == "table" then
            watchlistCount = #entries
            for i = 1, #entries do
                local ent = entries[i]
                if type(ent) == "table" then
                    local sp = H.posInt(ent.spellID)
                    local id = H.posInt(ent.itemID)
                    local rec = sp and H.lookupRecipeBySpell(sp) or nil
                    if not id and rec then id = H.posInt(rec.outputItemID) end
                    local kind = (ent.kind == "recipe" or sp ~= nil) and "recipe" or "item"
                    local key = (type(ent.key) == "string" and ent.key ~= "") and ent.key
                        or (kind == "recipe" and sp and ("recipe:" .. tostring(sp)))
                        or (id and ("item:" .. tostring(id)))
                    if key then
                        addCandidate(key, kind, sp, id, rec and rec.name or ent.name, true, 1)
                    end
                end
            end
        end
    end

    -- 2. Top crafted recipes/items from ledger (up to 16)
    local craftList = {}
    for _, rec in pairs(ledger.craftBySpell) do
        craftList[#craftList + 1] = rec
    end
    tsort(craftList, function(a, b)
        if a.craftCount ~= b.craftCount then return a.craftCount > b.craftCount end
        return (a.spellID or 0) < (b.spellID or 0)
    end)

    local craftAdded = 0
    for i = 1, #craftList do
        if craftAdded >= C.MAX_LEDGER_CRAFTS then break end
        local cr = craftList[i]
        local sp = cr.spellID
        local recipe = H.lookupRecipeBySpell(sp)
        local oid = cr.itemID or (recipe and H.posInt(recipe.outputItemID))
        local key = "recipe:" .. tostring(sp)
        if not seenKey[key] and (not oid or not seenItem[oid]) then
            addCandidate(key, "recipe", sp, oid, (recipe and recipe.name) or cr.name,
                H.isWatchedStock(key, oid, sp), 2)
            craftAdded = craftAdded + 1
        end
    end

    if craftAdded < C.MAX_LEDGER_CRAFTS then
        local craftItems = {}
        for _, rec in pairs(ledger.craftByItem) do
            craftItems[#craftItems + 1] = rec
        end
        tsort(craftItems, function(a, b)
            if a.craftCount ~= b.craftCount then return a.craftCount > b.craftCount end
            return (a.itemID or 0) < (b.itemID or 0)
        end)
        for i = 1, #craftItems do
            if craftAdded >= C.MAX_LEDGER_CRAFTS then break end
            local cr = craftItems[i]
            local oid = cr.itemID
            if oid and not seenItem[oid] then
                local recipe = (cr.spellID and H.lookupRecipeBySpell(cr.spellID)) or H.lookupRecipeByOutput(oid)
                local sp = cr.spellID or (recipe and H.posInt(recipe.spellID))
                if sp then
                    local key = "recipe:" .. tostring(sp)
                    addCandidate(key, "recipe", sp, oid, (recipe and recipe.name) or cr.name,
                        H.isWatchedStock(key, oid, sp), 2)
                else
                    local key = "item:" .. tostring(oid)
                    addCandidate(key, "item", nil, oid, cr.name, H.isWatchedStock(key, oid, nil), 2)
                end
                craftAdded = craftAdded + 1
            end
        end
    end

    -- 3. Top bought reagents & sold items from ledger (up to 16)
    local tradeMap = {}
    for oid, br in pairs(ledger.buyByItem) do
        tradeMap[oid] = { itemID = oid, score = br.buyCount or 0, buyCount = br.buyCount or 0, sellCount = 0, name = br.name }
    end
    for oid, sr in pairs(ledger.sellByItem) do
        local entry = tradeMap[oid]
        if not entry then
            tradeMap[oid] = { itemID = oid, score = sr.sellCount or 0, buyCount = 0, sellCount = sr.sellCount or 0, name = sr.name }
        else
            entry.sellCount = sr.sellCount or 0
            entry.score = entry.score + (sr.sellCount or 0)
            if not entry.name then entry.name = sr.name end
        end
    end
    local tradeList = {}
    for _, entry in pairs(tradeMap) do
        tradeList[#tradeList + 1] = entry
    end
    tsort(tradeList, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.buyCount ~= b.buyCount then return a.buyCount > b.buyCount end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    local tradeAdded = 0
    for i = 1, #tradeList do
        if tradeAdded >= C.MAX_LEDGER_ITEMS then break end
        local tr = tradeList[i]
        local oid = tr.itemID
        if oid and not seenItem[oid] then
            local key = "item:" .. tostring(oid)
            addCandidate(key, "item", nil, oid, tr.name, H.isWatchedStock(key, oid, nil), 3)
            tradeAdded = tradeAdded + 1
        end
    end

    -- 4. Empty-character fallback ONLY when both Watchlist and Ledger have 0 items
    if #candidates == 0 then
        local topCrafts = ns.app and ns.app.lastDashboardInsights and ns.app.lastDashboardInsights.topCrafts
        if type(topCrafts) == "table" and #topCrafts > 0 then
            for i = 1, min(#topCrafts, C.MAX_FALLBACK_STOCKS) do
                local row = topCrafts[i]
                if type(row) == "table" then
                    local rec = row.recipe or (row.spellID and H.lookupRecipeBySpell(row.spellID))
                        or (row.outputItemID and H.lookupRecipeByOutput(row.outputItemID))
                    local sp = H.posInt(row.spellID) or (rec and H.posInt(rec.spellID))
                    local oid = H.posInt(row.outputItemID or row.itemID) or (rec and H.posInt(rec.outputItemID))
                    if sp then
                        addCandidate("recipe:" .. tostring(sp), "recipe", sp, oid, (rec and rec.name) or row.name, false, 4)
                    elseif oid then
                        addCandidate("item:" .. tostring(oid), "item", nil, oid, row.name, false, 4)
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        local db = _G.MerchantMasterDB
        local pool = (type(db) == "table" and type(db.ahPrices) == "table" and type(db.ahPrices[econKey]) == "table")
            and db.ahPrices[econKey] or nil
        if pool then
            local scanned = {}
            for rawID, rec in pairs(pool) do
                local id = H.posInt(rawID)
                local p = type(rec) == "table" and H.safeNum(rec.price, nil) or nil
                if id and p and p > 0 then
                    scanned[#scanned + 1] = { itemID = id, price = p, qty = H.safeNum(rec.qty, 0) or 0 }
                end
            end
            tsort(scanned, function(a, b)
                if a.qty ~= b.qty then return a.qty > b.qty end
                if a.price ~= b.price then return a.price > b.price end
                return a.itemID < b.itemID
            end)
            for i = 1, min(#scanned, C.MAX_FALLBACK_STOCKS) do
                local sc = scanned[i]
                addCandidate("item:" .. tostring(sc.itemID), "item", nil, sc.itemID, nil, false, 5)
            end
        end
    end

    return candidates, watchlistCount
end

function H.canQueryDEWithoutLoad(itemID)
    local id = H.posInt(itemID)
    if not id then return false end
    if type(ns.GetItemDEProfile) ~= "function" then
        return true
    end
    if type(ns.DE_ITEM_META) == "table" and ns.DE_ITEM_META[id] ~= nil then
        return true
    end
    local db = _G.MerchantMasterDB
    if type(db) == "table" and type(db.deItemMetaCache) == "table" and db.deItemMetaCache[id] ~= nil then
        return true
    end
    local getInfo = (_G.C_Item and type(_G.C_Item.GetItemInfo) == "function" and _G.C_Item.GetItemInfo)
        or (type(_G.GetItemInfo) == "function" and _G.GetItemInfo)
        or nil
    if getInfo then
        local ok, nm, _, q, _, _, _, _, _, _, _, _, cls = pcall(getInfo, id)
        if ok and nm ~= nil and not H.isSecret(nm) then
            local nCls = H.safeNum(cls, nil)
            local nQ = H.safeNum(q, nil)
            if (nCls == 2 or nCls == 4) and nQ and nQ >= 2 and nQ <= 4 then
                return true
            end
        end
    end
    return false
end

function H.buildSingleStock(cand, ledger, econKey, rangeKey, now, priceBank, memo)
    local key = cand.key
    local spellID = cand.spellID
    local itemID = cand.itemID
    local recipe = spellID and H.lookupRecipeBySpell(spellID) or nil
    if not recipe and itemID and cand.kind == "recipe" then
        recipe = H.lookupRecipeByOutput(itemID)
        if recipe and not spellID then spellID = H.posInt(recipe.spellID) end
    end
    if not itemID and recipe then
        itemID = H.posInt(recipe.outputItemID)
    end
    if not recipe and itemID and ledger.craftByItem[itemID] then
        local cr = ledger.craftByItem[itemID]
        recipe = (cr.spellID and H.lookupRecipeBySpell(cr.spellID)) or H.lookupRecipeByOutput(itemID)
        if recipe and not spellID then spellID = H.posInt(recipe.spellID) end
    end

    local kind = (cand.kind == "recipe" or (spellID ~= nil and (ledger.craftBySpell[spellID] ~= nil))) and "recipe" or "item"
    local isWatched = cand.isWatched or H.isWatchedStock(key, itemID, spellID)

    -- Ledger stats (combine spell + output item craft activity without double-counting)
    local crSpell = spellID and ledger.craftBySpell[spellID] or nil
    local crItem = itemID and ledger.craftByItem[itemID] or nil
    local cr = crSpell or crItem
    local sr = itemID and ledger.sellByItem[itemID] or nil
    local br = itemID and ledger.buyByItem[itemID] or nil

    local craftCount = cr and cr.craftCount or 0
    local buyCount = br and br.buyCount or 0
    local sellCount = sr and sr.sellCount or 0
    local sellProfitSum = sr and sr.sellProfitSum or 0
    local activityScore = craftCount + buyCount + sellCount

    local ledgerAvgCraftCost = (cr and cr.ledgerAvgCraftCost) or (sr and sr.ledgerAvgSellCogs) or nil
    local ledgerAvgBuyPrice = br and br.ledgerAvgBuyPrice or nil

    local name = (recipe and type(recipe.name) == "string" and recipe.name ~= "" and recipe.name)
        or (itemID and H.resolveItemName(itemID, cand.nameHint))
        or cand.nameHint
        or (spellID and ("Recipe #" .. tostring(spellID)))
        or "Unknown"
    local shortName = H.makeShortName(name)
    local icon = H.resolveItemIcon(itemID or (recipe and recipe.recipeItemID))

    local ahPrice, priceSource = H.getMarketPrice(itemID, econKey, priceBank)
    local vol = H.getListedQty(itemID, econKey)

    -- Recipe craft cost, net profit, and top driver reagent
    local craftCost, netProfit, marginPct = nil, nil, nil
    local topDriverID, topDriverName, topDriverPct = nil, nil, nil
    local topDriverUnit, topDriverBase, topDriverQty = nil, nil, nil
    local reagentBreakdown = nil
    if recipe then
        craftCost, netProfit, marginPct,
        topDriverID, topDriverName, topDriverPct,
        topDriverUnit, topDriverBase, topDriverQty,
        reagentBreakdown = H.evaluateRecipeEconomics(recipe, ahPrice, econKey, now, priceBank, memo)
    end

    -- Disenchant breakdown (gear / craftable items, strictly non-requesting)
    local deValue, deGross = nil, nil
    if itemID and type(ns.GetItemDEBreakdown) == "function" and H.canQueryDEWithoutLoad(itemID) then
        local ok, bd = pcall(ns.GetItemDEBreakdown, itemID, nil, true)
        if ok and type(bd) == "table" then
            local netC = H.safeNum(bd.netCopper, nil)
            local grossC = H.safeNum(bd.grossCopper, nil)
            if netC and netC > 0 then deValue = floor(netC + 0.5) end
            if grossC and grossC > 0 then deGross = floor(grossC + 0.5) end
        end
    end

    -- Historical price & volume series
    local points, baseline, hi, lo, avgVol, trendSource = H.buildItemSeries(itemID, rangeKey, econKey, now, ahPrice, vol, memo)

    local primaryPrice = ahPrice or 0
    local deltaCopper = 0
    local deltaPct = nil
    if primaryPrice > 0 and baseline and baseline > 0 then
        deltaCopper = floor(primaryPrice - baseline + 0.5)
        deltaPct = ((primaryPrice - baseline) / baseline) * 100
    end

    local craftDeltaCopper, craftDeltaPct = nil, nil
    if craftCost and craftCost > 0 and ledgerAvgCraftCost and ledgerAvgCraftCost > 0 then
        craftDeltaCopper = floor(craftCost - ledgerAvgCraftCost + 0.5)
        craftDeltaPct = ((craftCost - ledgerAvgCraftCost) / ledgerAvgCraftCost) * 100
    end

    local buyDeltaCopper, buyDeltaPct = nil, nil
    if ahPrice and ahPrice > 0 and ledgerAvgBuyPrice and ledgerAvgBuyPrice > 0 then
        buyDeltaCopper = floor(ahPrice - ledgerAvgBuyPrice + 0.5)
        buyDeltaPct = ((ahPrice - ledgerAvgBuyPrice) / ledgerAvgBuyPrice) * 100
    end

    -- Heatmap Best Buy / Best Sell windows
    local hm = H.getHeatmapMemo(memo, itemID, econKey)
    local bestBuyMeta = hm and type(hm.bestBuy) == "table" and hm.bestBuy or nil
    local bestSellMeta = hm and type(hm.bestSell) == "table" and hm.bestSell or nil
    local bestBuyText = H.formatHeatmapSlot(bestBuyMeta)
    local bestSellText = H.formatHeatmapSlot(bestSellMeta)

    return {
        key = key,
        kind = kind,
        itemID = itemID,
        spellID = spellID,
        recipe = recipe,
        name = name,
        shortName = shortName,
        icon = icon,
        isWatched = isWatched,
        craftCount = craftCount,
        buyCount = buyCount,
        sellCount = sellCount,
        sellProfitSum = sellProfitSum,
        activityScore = activityScore,
        ahPrice = ahPrice,
        price = primaryPrice,
        primaryPrice = primaryPrice,
        priceSource = priceSource,
        vol = vol,
        listed = vol,
        craftCost = craftCost,
        netProfit = netProfit,
        profit = netProfit,
        marginPct = marginPct,
        deValue = deValue,
        deGross = deGross,
        topDriverID = topDriverID,
        topDriverName = topDriverName,
        topDriverPct = topDriverPct,
        topDriverUnit = topDriverUnit,
        topDriverBase = topDriverBase,
        topDriverQty = topDriverQty,
        reagentBreakdown = reagentBreakdown,
        ledgerAvgCraftCost = ledgerAvgCraftCost,
        ledgerAvgBuyPrice = ledgerAvgBuyPrice,
        craftDeltaCopper = craftDeltaCopper,
        craftDeltaPct = craftDeltaPct,
        buyDeltaCopper = buyDeltaCopper,
        buyDeltaPct = buyDeltaPct,
        points = points,
        baseline = baseline,
        hi = hi or primaryPrice,
        lo = lo or primaryPrice,
        avgVol = avgVol,
        deltaCopper = deltaCopper,
        deltaPct = deltaPct,
        trendSource = trendSource,
        bestBuyText = bestBuyText,
        bestSellText = bestSellText,
        bestBuy = bestBuyMeta,
        bestSell = bestSellMeta,
    }
end

function H.buildStocks(ledger, econKey, rangeKey, filterKey, now, priceBank, memo)
    local candidates, watchlistCount = H.gatherCandidates(ledger, econKey)
    local allStocks = {}
    local stocksByKey = {}

    local beganEval = false
    if type(ns.BeginEval) == "function" then
        pcall(ns.BeginEval, priceBank)
        beganEval = true
    end

    local okRun = pcall(function()
        for i = 1, #candidates do
            local okStock, st = pcall(H.buildSingleStock, candidates[i], ledger, econKey, rangeKey, now, priceBank, memo)
            if okStock and type(st) == "table" then
                allStocks[#allStocks + 1] = st
                stocksByKey[st.key] = st
            end
        end
    end)

    if beganEval and type(ns.EndEval) == "function" then
        pcall(ns.EndEval)
    end
    if not okRun then
        allStocks = {}
        stocksByKey = {}
    end

    tsort(allStocks, function(a, b)
        if a.isWatched ~= b.isWatched then return a.isWatched end
        if a.activityScore ~= b.activityScore then return a.activityScore > b.activityScore end
        local da = abs(a.deltaPct or 0)
        local db = abs(b.deltaPct or 0)
        if da ~= db then return da > db end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)

    local filtered = {}
    for i = 1, #allStocks do
        local st = allStocks[i]
        local keep = true
        if filterKey == "watchlist" then
            keep = (st.isWatched == true)
        elseif filterKey == "crafts" then
            keep = (st.kind == "recipe" or (st.craftCount or 0) > 0)
        elseif filterKey == "reagents" then
            keep = (st.kind == "item" and (st.buyCount or 0) >= (st.craftCount or 0))
        end
        if keep then
            filtered[#filtered + 1] = st
        end
    end

    local activePool = {}
    for i = 1, #allStocks do activePool[i] = allStocks[i] end
    tsort(activePool, function(a, b)
        if a.activityScore ~= b.activityScore then return a.activityScore > b.activityScore end
        local da = abs(a.deltaPct or 0)
        local db = abs(b.deltaPct or 0)
        if da ~= db then return da > db end
        if a.isWatched ~= b.isWatched then return a.isWatched end
        return a.name < b.name
    end)
    local mostActive = {}
    for i = 1, min(#activePool, C.MAX_MOST_ACTIVE) do
        mostActive[i] = activePool[i]
    end

    return allStocks, filtered, stocksByKey, mostActive, watchlistCount
end

---------------------------------------------------------------------------------------------------
-- Broadcast Stage 4-Slide Builder
---------------------------------------------------------------------------------------------------
function H.buildCraftSpreadPoints(stock, econKey, rangeKey, now, memo)
    local basePts = stock and stock.points or {}
    local out = {}
    if #basePts == 0 then return out end

    local recipe = stock.recipe
    local breakdown = stock.reagentBreakdown
    local numMade = max(1, (recipe and H.safeNum(recipe.numMade, 1)) or 1)
    local rgSeries = nil

    if type(breakdown) == "table" and #breakdown > 0 and #breakdown <= 8 then
        rgSeries = {}
        local anyHist = false
        for i = 1, #breakdown do
            local b = breakdown[i]
            local byKey = {}
            if not b.isVendor and b.itemID then
                local rPts = H.buildItemSeries(b.itemID, rangeKey, econKey, now, b.unitCost, 0, memo)
                for j = 1, #rPts do
                    local rp = rPts[j]
                    local k = (rangeKey == "24h") and rp.h or rp.d
                    if k and rp.value and rp.value > 0 then
                        byKey[k] = rp.value
                        anyHist = true
                    end
                end
            end
            rgSeries[i] = {
                qty = b.qty or 1,
                unitCost = b.unitCost or 0,
                byKey = byKey,
            }
        end
        if not anyHist then rgSeries = nil end
    end

    local fallbackCost = stock.craftCost or stock.ledgerAvgCraftCost
    for i = 1, #basePts do
        local pt = basePts[i]
        local estCost = fallbackCost
        if rgSeries then
            local k = (rangeKey == "24h") and pt.h or pt.d
            local sum = 0
            local okAll = true
            for j = 1, #rgSeries do
                local rs = rgSeries[j]
                local p = (k and rs.byKey[k]) or rs.unitCost
                if p and p > 0 then
                    sum = sum + p * rs.qty
                else
                    okAll = false
                end
            end
            if okAll and sum > 0 then
                estCost = floor((sum / numMade) + 0.5)
            end
        end
        out[i] = {
            label = pt.label,
            day = pt.day,
            value = pt.value,
            value2 = estCost,
            volume = pt.volume or 0,
            ts = pt.ts,
        }
    end
    return out
end

function H.buildSlides(allStocks, pinnedStock, summary, wealthSeries, econKey, rangeKey, now, memo)
    -- 1. Select best reagent / item stock for Slide 1 (vol_price)
    local volStock = nil
    if pinnedStock and (pinnedStock.kind == "item" or not pinnedStock.craftCost) then
        volStock = pinnedStock
    else
        local bestBuy = nil
        local bestVol = nil
        for i = 1, #allStocks do
            local st = allStocks[i]
            if (st.buyCount or 0) > 0 then
                if not bestBuy
                    or (st.kind == "item" and bestBuy.kind ~= "item")
                    or ((st.kind == bestBuy.kind) and (
                        (st.buyCount or 0) > (bestBuy.buyCount or 0)
                        or ((st.buyCount or 0) == (bestBuy.buyCount or 0) and (st.vol or 0) > (bestBuy.vol or 0))
                    )) then
                    bestBuy = st
                end
            end
            if not bestVol
                or (st.vol or 0) > (bestVol.vol or 0)
                or ((st.vol or 0) == (bestVol.vol or 0) and (st.activityScore or 0) > (bestVol.activityScore or 0)) then
                bestVol = st
            end
        end
        volStock = bestBuy or bestVol
    end

    local volPoints = {}
    local volHasVolume = false
    if volStock and type(volStock.points) == "table" then
        for i = 1, #volStock.points do
            local pt = volStock.points[i]
            local v = pt.volume or 0
            if v > 0 then volHasVolume = true end
            volPoints[i] = {
                label = pt.label,
                day = pt.day,
                value = pt.value,
                open = pt.open,
                high = pt.high,
                low = pt.low,
                close = pt.close,
                volume = v,
                ts = pt.ts,
            }
        end
    end

    local volRefVal = volStock and (volStock.ledgerAvgBuyPrice or volStock.baseline) or nil
    local volRefLbl = volStock and (volStock.ledgerAvgBuyPrice and "Your Avg Buy" or (volStock.baseline and "7d Avg" or nil)) or nil
    local volSub = "Star items or buy reagents on AH to track supply vs price"
    if volStock then
        local buyNote = (volStock.buyCount or 0) > 0 and volStock.ledgerAvgBuyPrice
            and format("Bought x%d (avg %s)", volStock.buyCount, H.formatCopper(volStock.ledgerAvgBuyPrice))
            or (volStock.baseline and format("Avg %s", H.formatCopper(volStock.baseline)) or "Market feed")
        volSub = format("Now %s | Listed %d | %s",
            H.formatCopper(volStock.primaryPrice), volStock.vol or 0, buyNote)
    end

    local slideVol = {
        id = "vol_price",
        kind = "vol_price",
        badge = "PRICE & VOL",
        title = volStock and volStock.name or "Price & Supply",
        subtitle = volSub,
        price = volStock and volStock.primaryPrice or nil,
        deltaPct = volStock and volStock.deltaPct or nil,
        deltaCopper = volStock and volStock.deltaCopper or nil,
        listed = volStock and volStock.vol or 0,
        points = volPoints,
        refValue = volRefVal,
        refLabel = volRefLbl,
        series1Label = "Min Price",
        hasVolume = volHasVolume,
        stockKey = volStock and volStock.key or nil,
        itemID = volStock and volStock.itemID or nil,
        spellID = volStock and volStock.spellID or nil,
        pinned = (pinnedStock ~= nil and volStock == pinnedStock),
        emptyText = "Run an AH scan or buy reagents to plot Price & Supply",
    }

    -- 2. Net Worth & Gold Trajectory (wealth)
    local wPts = {}
    local srcWPts = (type(wealthSeries) == "table" and type(wealthSeries.points) == "table") and wealthSeries.points or {}
    for i = 1, #srcWPts do
        local pt = srcWPts[i]
        wPts[i] = {
            label = pt.label or tostring(i),
            day = pt.day,
            value = H.safeNum(pt.value, 0) or 0,
            gold = H.safeNum(pt.gold, nil),
            items = H.safeNum(pt.items, nil),
            listed = H.safeNum(pt.listed, nil),
            delta = H.safeNum(pt.delta, nil),
            ts = H.safeNum(pt.sortKey, nil),
        }
    end
    local wFirst = (#wPts >= 2) and wPts[1].value or nil
    local wLast = (#wPts >= 1) and wPts[#wPts].value or (wealthSeries and wealthSeries.latestTotal) or 0
    local wDelta = (wFirst ~= nil) and (wLast - wFirst) or ((wealthSeries and wealthSeries.change24h) or 0)
    local wPct = (wFirst and wFirst > 0) and ((wDelta / wFirst) * 100) or nil
    local wModeLabel = (wealthSeries and wealthSeries.mode == "hourly") and "24h" or rangeKey

    local slideWealth = {
        id = "wealth",
        kind = "wealth",
        badge = "NET WORTH",
        title = format("Net Worth (%s)", wModeLabel),
        subtitle = format("Total %s | %s (%s)",
            H.formatCopper(wLast),
            H.formatCopper(wDelta, true),
            wPct and format("%+.1f%%", wPct) or "0.0%"),
        points = wPts,
        refValue = wFirst,
        refLabel = wFirst and "Period Start" or nil,
        series1Label = "Net Worth",
        hasVolume = false,
        emptyText = "No wealth snapshots recorded yet",
    }

    -- 3. Realized AH Profit (profit)
    local srcBars = (rangeKey == "24h")
        and ((summary and summary.hourlyBars) or {})
        or ((summary and summary.dailyBars) or {})
    local pPts = {}
    for i = 1, #srcBars do
        local b = srcBars[i]
        pPts[i] = {
            label = b.label or tostring(i),
            day = b.day,
            value = H.safeNum(b.value, 0) or 0,
            ts = H.safeNum(b.sortKey, nil),
        }
    end
    local avg7d = summary and H.safeNum(summary.avg7dCompleted, nil) or nil
    local slideProfit = {
        id = "profit",
        kind = "profit",
        badge = "AH PROFIT",
        title = (rangeKey == "24h")
            and "Realized AH Profit (24h)"
            or format("Realized AH Profit (%s)", rangeKey),
        subtitle = format("Range %s (%d sales) | Today %s (%d)",
            H.formatCopper((summary and summary.rangeTotalProfit) or 0, true),
            (summary and summary.rangeSalesCount) or 0,
            H.formatCopper((summary and summary.todayProfit) or 0, true),
            (summary and summary.todaySalesCount) or 0),
        points = pPts,
        refValue = (rangeKey ~= "24h" and avg7d and avg7d ~= 0) and avg7d or nil,
        refLabel = (rangeKey ~= "24h" and avg7d and avg7d ~= 0) and "7d Daily Avg" or nil,
        series1Label = "AH Profit",
        isBarChart = true,
        hasVolume = false,
        emptyText = "No realized AH sales in this range",
    }

    -- 4. Craft Spread (craft_spread)
    local craftStock = nil
    if pinnedStock and (pinnedStock.craftCost or pinnedStock.kind == "recipe") then
        craftStock = pinnedStock
    else
        local bestCrafted = nil
        local bestRecipe = nil
        for i = 1, #allStocks do
            local st = allStocks[i]
            local isRec = (st.kind == "recipe" or st.recipe ~= nil or st.craftCost ~= nil)
            if isRec then
                if (st.craftCount or 0) > 0 then
                    if not bestCrafted
                        or (st.craftCount or 0) > (bestCrafted.craftCount or 0)
                        or ((st.craftCount or 0) == (bestCrafted.craftCount or 0) and (st.activityScore or 0) > (bestCrafted.activityScore or 0)) then
                        bestCrafted = st
                    end
                end
                if not bestRecipe
                    or (st.isWatched and not bestRecipe.isWatched)
                    or ((st.isWatched == bestRecipe.isWatched) and (st.craftCost ~= nil and bestRecipe.craftCost == nil)) then
                    bestRecipe = st
                end
            end
        end
        craftStock = bestCrafted or bestRecipe
    end

    local cPts = craftStock and H.buildCraftSpreadPoints(craftStock, econKey, rangeKey, now, memo) or {}
    local cHasVol = false
    for i = 1, #cPts do
        if (cPts[i].volume or 0) > 0 then cHasVol = true; break end
    end
    local cRefVal = craftStock and (craftStock.ledgerAvgCraftCost or craftStock.baseline) or nil
    local cRefLbl = craftStock and (craftStock.ledgerAvgCraftCost and "Your Avg Craft Cost" or (craftStock.baseline and "7d Avg" or nil)) or nil
    local cSub = "Craft recipes or star a recipe to plot Sale Price vs Craft Cost"
    if craftStock then
        local cVal = craftStock.craftCost or craftStock.ledgerAvgCraftCost
        cSub = format("AH %s | Craft %s | Net %s",
            H.formatCopper(craftStock.primaryPrice),
            cVal and H.formatCopper(cVal) or "--",
            craftStock.netProfit and H.formatCopper(craftStock.netProfit, true) or "--")
    end

    local slideCraft = {
        id = "craft_spread",
        kind = "craft_spread",
        badge = "CRAFT SPREAD",
        title = craftStock and craftStock.name or "Craft Spread",
        subtitle = cSub,
        points = cPts,
        refValue = cRefVal,
        refLabel = cRefLbl,
        series1Label = "Sale Price",
        series2Label = "Craft Cost",
        hasVolume = cHasVol,
        stockKey = craftStock and craftStock.key or nil,
        itemID = craftStock and craftStock.itemID or nil,
        spellID = craftStock and craftStock.spellID or nil,
        pinned = (pinnedStock ~= nil and craftStock == pinnedStock),
        emptyText = "Craft recipes or star a recipe to plot Sale Price vs Craft Cost",
    }

    if pinnedStock and craftStock == pinnedStock and (pinnedStock.kind == "recipe" or pinnedStock.craftCost) then
        return { slideCraft, slideVol, slideWealth, slideProfit }
    end
    return { slideVol, slideWealth, slideProfit, slideCraft }
end

---------------------------------------------------------------------------------------------------
-- Script-Generated Market News Headlines Engine
---------------------------------------------------------------------------------------------------
function H.buildHeadlines(allStocks, summary, rangeKey, watchlistCount, trackedCraftsCount, snapshotActive)
    local stories = {}
    local seenID = {}

    local function pushStory(story)
        if not story or not story.id or seenID[story.id] then return end
        seenID[story.id] = true
        stories[#stories + 1] = story
    end

    for i = 1, #allStocks do
        local st = allStocks[i]

        -- 1. Craft Cost Spikes / Drops (category = "costs")
        if (st.craftCount or 0) >= 1 and st.craftCost and st.craftCost > 0
            and st.ledgerAvgCraftCost and st.ledgerAvgCraftCost > 0
            and st.craftDeltaPct and abs(st.craftDeltaPct) >= C.CRAFT_COST_PCT_THRESHOLD then
            local pct = st.craftDeltaPct
            local isUp = pct > 0
            local driverStr = ""
            if st.topDriverName then
                if st.topDriverPct then
                    driverStr = format(" Top driver: %s (%+.1f%%).", st.topDriverName, st.topDriverPct)
                else
                    driverStr = format(" Top reagent: %s.", st.topDriverName)
                end
            end
            local profitNote = st.netProfit and format(" Est. net profit now %s.", H.formatCopper(st.netProfit, true)) or ""
            local title = format("%s craft cost %s %+.1f%% (%s avg across %d crafts -> %s now)",
                st.name,
                isUp and "up" or "down",
                pct,
                H.formatCopper(st.ledgerAvgCraftCost),
                st.craftCount,
                H.formatCopper(st.craftCost))
            pushStory({
                id = "cost:" .. st.key,
                category = "costs",
                badge = "COSTS",
                severity = isUp and "alert" or "down",
                tone = isUp and "bad" or "good",
                title = title,
                detail = format("%s%s%s", title, driverStr, profitNote),
                stockKey = st.key,
                itemID = st.itemID,
                spellID = st.spellID,
                cartItemID = st.topDriverID or st.itemID,
                cartQty = st.topDriverQty and max(1, floor(st.topDriverQty * 5 + 0.5)) or 5,
                priority = 100 + abs(pct) + min(40, (st.craftCount or 0) * 0.2),
            })
        end

        -- 2. Heavily Bought Reagent Dips & Supply Surges (category = "deals")
        if (st.buyCount or 0) >= 1 and st.ahPrice and st.ahPrice > 0 then
            if st.ledgerAvgBuyPrice and st.ledgerAvgBuyPrice > 0 and st.buyDeltaPct then
                if st.buyDeltaPct <= C.DEAL_DIP_PCT_THRESHOLD then
                    local title = format("%s dipped %.1f%% below your %s avg buy (now %s, %d listed) - Prime Buy Zone",
                        st.name,
                        st.buyDeltaPct,
                        H.formatCopper(st.ledgerAvgBuyPrice),
                        H.formatCopper(st.ahPrice),
                        st.vol or 0)
                    local winNote = (st.bestBuyText and st.bestBuyText ~= "--") and (" Best window: " .. st.bestBuyText .. ".") or ""
                    pushStory({
                        id = "deal_buy:" .. st.key,
                        category = "deals",
                        badge = "BUY ZONE",
                        severity = "down",
                        tone = "good",
                        title = title,
                        detail = format("Bought x%d over 30d at %s avg. Current AH %s (%d listed).%s Shift-click to queue in Shopping Cart.",
                            st.buyCount, H.formatCopper(st.ledgerAvgBuyPrice), H.formatCopper(st.ahPrice), st.vol or 0, winNote),
                        stockKey = st.key,
                        itemID = st.itemID,
                        spellID = st.spellID,
                        cartItemID = st.itemID,
                        cartQty = max(5, min(200, st.buyCount)),
                        priority = 95 + abs(st.buyDeltaPct) + min(30, st.buyCount * 0.15),
                    })
                elseif st.buyDeltaPct >= 15.0 then
                    local title = format("%s spiked +%.1f%% above your %s avg buy (now %s, %d listed)",
                        st.name,
                        st.buyDeltaPct,
                        H.formatCopper(st.ledgerAvgBuyPrice),
                        H.formatCopper(st.ahPrice),
                        st.vol or 0)
                    pushStory({
                        id = "cost_buy:" .. st.key,
                        category = "costs",
                        badge = "COSTS",
                        severity = "alert",
                        tone = "bad",
                        title = title,
                        detail = format("Frequently bought reagent (x%d in 30d) is trading above your %s avg buy. Consider waiting for %s.",
                            st.buyCount, H.formatCopper(st.ledgerAvgBuyPrice), st.bestBuyText or "--"),
                        stockKey = st.key,
                        itemID = st.itemID,
                        spellID = st.spellID,
                        cartItemID = st.itemID,
                        cartQty = max(5, min(100, st.buyCount)),
                        priority = 82 + st.buyDeltaPct,
                    })
                end
            elseif st.deltaPct and st.deltaPct <= C.DEAL_DIP_PCT_THRESHOLD and st.baseline then
                local title = format("%s dipped %.1f%% vs avg (%s -> %s, %d listed) - Buy Zone",
                    st.name, st.deltaPct, H.formatCopper(st.baseline), H.formatCopper(st.ahPrice), st.vol or 0)
                pushStory({
                    id = "deal_avg:" .. st.key,
                    category = "deals",
                    badge = "BUY ZONE",
                    severity = "down",
                    tone = "good",
                    title = title,
                    detail = format("Trading below %s average (%s). Shift-click to add to Shopping Cart.",
                        rangeKey, H.formatCopper(st.baseline)),
                    stockKey = st.key,
                    itemID = st.itemID,
                    spellID = st.spellID,
                    cartItemID = st.itemID,
                    cartQty = max(5, min(200, st.buyCount)),
                    priority = 80 + abs(st.deltaPct),
                })
            end

            if (st.vol or 0) > 0 and st.avgVol and st.avgVol > 0
                and st.vol >= st.avgVol * C.SURGE_VOL_RATIO
                and (not st.buyDeltaPct or st.buyDeltaPct <= 2.0) then
                local title = format("%s supply surged to %d listed (avg %d) at %s",
                    st.name, st.vol, floor(st.avgVol + 0.5), H.formatCopper(st.ahPrice))
                pushStory({
                    id = "surge:" .. st.key,
                    category = "deals",
                    badge = "BUY ZONE",
                    severity = "down",
                    tone = "good",
                    title = title,
                    detail = format("Heavy AH supply on a reagent you bought x%d recently. Good window to restock.", st.buyCount),
                    stockKey = st.key,
                    itemID = st.itemID,
                    spellID = st.spellID,
                    cartItemID = st.itemID,
                    cartQty = max(5, min(200, st.buyCount)),
                    priority = 72 + min(25, (st.vol / st.avgVol) * 10),
                })
            end
        end

        -- 3. Watchlist Movers & DE Spread Opportunities (category = "movers" / "deals")
        if st.isWatched then
            if st.deltaPct and abs(st.deltaPct) >= C.WATCH_MOVER_PCT_THRESHOLD and st.baseline then
                local isUp = st.deltaPct > 0
                local title = format("%s %s %+.1f%% vs avg (%s -> %s)",
                    st.name,
                    isUp and "rallied" or "pulled back",
                    st.deltaPct,
                    H.formatCopper(st.baseline),
                    H.formatCopper(st.primaryPrice))
                pushStory({
                    id = "mover:" .. st.key,
                    category = "movers",
                    badge = "WATCH",
                    severity = isUp and "up" or "down",
                    tone = "warn",
                    title = title,
                    detail = format("Watchlist mover over %s window. Range Lo %s / Hi %s. Listed: %d.",
                        rangeKey, H.formatCopper(st.lo), H.formatCopper(st.hi), st.vol or 0),
                    stockKey = st.key,
                    itemID = st.itemID,
                    spellID = st.spellID,
                    cartItemID = (not isUp) and st.itemID or nil,
                    cartQty = (not isUp) and 5 or nil,
                    priority = 68 + abs(st.deltaPct),
                })
            end

            if st.deValue and st.ahPrice and st.ahPrice > 0 and st.deValue >= st.ahPrice * C.DE_SPREAD_RATIO then
                local spread = st.deValue - st.ahPrice
                local title = format("%s DE value %s beats AH buyout %s (+%s spread)",
                    st.name, H.formatCopper(st.deValue), H.formatCopper(st.ahPrice), H.formatCopper(spread))
                pushStory({
                    id = "de_spread:" .. st.key,
                    category = "deals",
                    badge = "BUY ZONE",
                    severity = "down",
                    tone = "good",
                    title = title,
                    detail = format("Expected net DE yield %s exceeds current AH buyout %s (%d listed). Shift-click to queue.",
                        H.formatCopper(st.deValue), H.formatCopper(st.ahPrice), st.vol or 0),
                    stockKey = st.key,
                    itemID = st.itemID,
                    spellID = st.spellID,
                    cartItemID = st.itemID,
                    cartQty = 1,
                    priority = 76 + min(30, (spread / st.ahPrice) * 50),
                })
            end
        end
    end

    -- 4. Ledger & Sales Milestones (category = "sales")
    if summary then
        if (summary.todaySalesCount or 0) > 0 then
            local p = summary.todayProfit or 0
            local cnt = summary.todaySalesCount or 0
            pushStory({
                id = "sales:today",
                category = "sales",
                badge = "SALES",
                severity = (p >= 0) and "up" or "alert",
                tone = (p >= 0) and "good" or "bad",
                title = format("Today: %s across %d AH %s",
                    H.formatCopper(p, true), cnt, cnt == 1 and "sale" or "sales"),
                detail = format("Realized net AH profit today after 5%% cut and COGS (%d sales). Range (%s) total: %s.",
                    cnt, rangeKey, H.formatCopper(summary.rangeTotalProfit or 0, true)),
                priority = 88,
            })
        end

        if (summary.yesterdaySalesCount or 0) > 0 and summary.yesterdayDeltaPct ~= nil then
            local pct = summary.yesterdayDeltaPct
            pushStory({
                id = "sales:yesterday",
                category = "sales",
                badge = "SALES",
                severity = (pct >= 0) and "up" or "down",
                tone = (pct >= 0) and "good" or "info",
                title = format("Yesterday: %s (%+.1f%% vs 7d avg %s)",
                    H.formatCopper(summary.yesterdayProfit or 0, true),
                    pct,
                    H.formatCopper(summary.avg7dCompleted or 0, true)),
                detail = format("Completed yesterday with %d AH sales compared to 7-day completed daily average.",
                    summary.yesterdaySalesCount or 0),
                priority = 64,
            })
        end

        local bs = summary.bestSingleSale
        if type(bs) == "table" and (bs.profit or 0) > 0 then
            pushStory({
                id = "sales:best",
                category = "sales",
                badge = "SALES",
                severity = "up",
                tone = "good",
                title = format("Top %s sale: %s x%d for %s profit",
                    rangeKey, bs.name or "Item", bs.qty or 1, H.formatCopper(bs.profit or 0, true)),
                detail = format("Net %s, COGS %s on %s.",
                    H.formatCopper(bs.net or 0), H.formatCopper(bs.cogs or 0), tostring(bs.day or "")),
                itemID = H.posInt(bs.itemID),
                stockKey = H.posInt(bs.itemID) and ("item:" .. tostring(H.posInt(bs.itemID))) or nil,
                priority = 60,
            })
        end
    end

    tsort(stories, function(a, b)
        if (a.priority or 0) ~= (b.priority or 0) then return (a.priority or 0) > (b.priority or 0) end
        return tostring(a.id) < tostring(b.id)
    end)

    -- 5. Clean guidance fallbacks when fewer than 4 stories triggered
    if #stories < 4 then
        local fallbacks = {}
        if (watchlistCount or 0) == 0 then
            fallbacks[#fallbacks + 1] = {
                id = "tip:watchlist",
                category = "movers",
                badge = "WATCH",
                severity = "info",
                tone = "info",
                title = "Star recipes or reagents in Watchlist to lock them onto the right ticker rail",
                detail = "Open Watchlist or click the star icon on any Spotlight stock to track live prices and swings.",
                priority = 10,
            }
        end
        if (trackedCraftsCount or 0) == 0 then
            fallbacks[#fallbacks + 1] = {
                id = "tip:crafts",
                category = "costs",
                badge = "COSTS",
                severity = "info",
                tone = "info",
                title = "Craft items to benchmark live reagent costs against your historical craft average",
                detail = "Once crafts are recorded in the ledger, Bloomberg Desk flags >= 10% craft cost spikes automatically.",
                priority = 9,
            }
        end
        if not summary or (summary.rangeSalesCount or 0) == 0 then
            fallbacks[#fallbacks + 1] = {
                id = "tip:sales",
                category = "sales",
                badge = "SALES",
                severity = "info",
                tone = "info",
                title = "Collect AH mail to stream realized profit bars and top sale highlights",
                detail = "AH_SELL rows populate Today Profit, Yesterday vs 7d average, and the AH Profit broadcast slide.",
                priority = 8,
            }
        end
        if not snapshotActive then
            fallbacks[#fallbacks + 1] = {
                id = "tip:scan",
                category = "deals",
                badge = "BUY ZONE",
                severity = "info",
                tone = "info",
                title = "Run an AH scan or enable Local Snapshot to unlock 7x24 Best Buy and Sell windows",
                detail = "Snapshots and live AH scans power volume bars, price-drop alerts, and best-hour timing windows.",
                priority = 7,
            }
        end
        for i = 1, #fallbacks do
            if #stories >= 4 then break end
            pushStory(fallbacks[i])
        end
    end

    if #stories > C.MAX_HEADLINES then
        local capped = {}
        for i = 1, C.MAX_HEADLINES do capped[i] = stories[i] end
        return capped
    end
    return stories
end

---------------------------------------------------------------------------------------------------
-- KPIs & Timing Footer Summary
---------------------------------------------------------------------------------------------------
function H.buildKpisAndTiming(allStocks, selectedStock, summary, wealthSeries, econKey, watchlistCount, opts)
    local wPts = (type(wealthSeries) == "table" and type(wealthSeries.points) == "table") and wealthSeries.points or {}
    local netWorth = (type(wealthSeries) == "table" and H.safeNum(wealthSeries.latestTotal, nil))
        or ((#wPts > 0) and wPts[#wPts].value) or 0
    local netWorthDeltaCopper = 0
    local netWorthDeltaPct = nil
    if #wPts >= 2 then
        local firstV = H.safeNum(wPts[1].value, 0) or 0
        local lastV = H.safeNum(wPts[#wPts].value, 0) or 0
        netWorthDeltaCopper = lastV - firstV
        if firstV > 0 then
            netWorthDeltaPct = (netWorthDeltaCopper / firstV) * 100
        end
    elseif type(wealthSeries) == "table" and H.safeNum(wealthSeries.change24h, nil) then
        netWorthDeltaCopper = wealthSeries.change24h
        local baseV = netWorth - netWorthDeltaCopper
        if baseV > 0 then
            netWorthDeltaPct = (netWorthDeltaCopper / baseV) * 100
        end
    end

    -- Top mover across all tracked stocks
    local topMover = nil
    local topMag = -1
    for i = 1, #allStocks do
        local st = allStocks[i]
        local pct = st.deltaPct
        local dCop = st.deltaCopper or 0
        if pct == nil and st.craftDeltaPct ~= nil then
            pct = st.craftDeltaPct
            dCop = st.craftDeltaCopper or 0
        end
        if pct ~= nil then
            local mag = abs(pct)
            if mag > topMag or (mag == topMag and topMover and abs(dCop) > abs(topMover.deltaCopper or 0)) then
                topMag = mag
                topMover = {
                    name = st.name,
                    shortName = st.shortName,
                    deltaPct = pct,
                    deltaCopper = dCop,
                    key = st.key,
                    itemID = st.itemID,
                    spellID = st.spellID,
                }
            end
        end
    end

    local kpis = {
        todayProfit = (summary and summary.todayProfit) or 0,
        todaySalesCount = (summary and summary.todaySalesCount) or 0,
        yesterdayProfit = (summary and summary.yesterdayProfit) or 0,
        yesterdaySalesCount = (summary and summary.yesterdaySalesCount) or 0,
        yesterdayDeltaPct = summary and summary.yesterdayDeltaPct or nil,
        rangeTotalProfit = (summary and summary.rangeTotalProfit) or 0,
        rangeSalesCount = (summary and summary.rangeSalesCount) or 0,
        netWorth = netWorth,
        netWorthDeltaCopper = netWorthDeltaCopper,
        netWorthDeltaPct = netWorthDeltaPct,
        topMover = topMover,
    }

    -- Timing windows & desk counts
    local trackedCraftsCount = 0
    local trackedReagentsCount = 0
    local bestSellText = (selectedStock and selectedStock.bestSellText and selectedStock.bestSellText ~= "--")
        and selectedStock.bestSellText or "--"
    local bestBuyText = (selectedStock and selectedStock.bestBuyText and selectedStock.bestBuyText ~= "--")
        and selectedStock.bestBuyText or "--"
    local snapshotActive = (bestSellText ~= "--" or bestBuyText ~= "--")

    for i = 1, #allStocks do
        local st = allStocks[i]
        if (st.craftCount or 0) > 0 then trackedCraftsCount = trackedCraftsCount + 1 end
        if (st.buyCount or 0) > 0 then trackedReagentsCount = trackedReagentsCount + 1 end
        if bestSellText == "--" and st.bestSellText and st.bestSellText ~= "--" then
            bestSellText = st.bestSellText
            snapshotActive = true
        end
        if bestBuyText == "--" and st.bestBuyText and st.bestBuyText ~= "--" then
            bestBuyText = st.bestBuyText
            snapshotActive = true
        end
        if not snapshotActive and (st.trendSource == "snapshot" or st.trendSource == "merged") then
            snapshotActive = true
        end
    end

    if not snapshotActive and ns.Pricing and type(ns.Pricing.IsSnapshotAvailable) == "function" then
        local ok, avail = pcall(ns.Pricing.IsSnapshotAvailable, econKey)
        if ok and avail == true then snapshotActive = true end
    end

    local freshnessText = (type(opts) == "table" and type(opts.freshnessText) == "string" and opts.freshnessText ~= "")
        and opts.freshnessText
        or (snapshotActive and "Snapshot active" or "Live AH")

    local timing = {
        econKey = econKey,
        freshnessText = freshnessText,
        bestSellText = bestSellText,
        bestBuyText = bestBuyText,
        snapshotActive = snapshotActive,
        watchlistCount = watchlistCount,
        trackedCraftsCount = trackedCraftsCount,
        trackedReagentsCount = trackedReagentsCount,
        totalStocksCount = #allStocks,
    }

    return kpis, timing
end

---------------------------------------------------------------------------------------------------
-- Public Entry Point: Model.BuildSnapshot
---------------------------------------------------------------------------------------------------
function Model.BuildSnapshot(econKey, rangeKey, filterKey, selectedKey, nowOverride, opts)
    opts = type(opts) == "table" and opts or {}
    local ek = H.resolveEconKey(econKey)
    local rKey = H.normalizeRange(rangeKey)
    local fKey = H.normalizeFilter(filterKey)
    local now = H.nowSec(nowOverride)

    local ledger = H.computeLedgerActivity(ek, now)
    local summary = H.getAHSalesSummary(ek, rKey, now)
    local wealthSeries = H.getWealthSeries(opts.wealthMode or "auto", rKey, ek, opts.portfolio, now)

    local memo = {
        heatmap = {},
        heatstrip = {},
        trend24 = {},
        trend7d = {},
    }

    local allStocks, stocks, stocksByKey, mostActive, watchlistCount = H.buildStocks(
        ledger, ek, rKey, fKey, now, opts.priceBank, memo
    )

    local effectiveSelectedKey = nil
    local selectedStock = nil
    if type(selectedKey) == "string" and stocksByKey[selectedKey] then
        effectiveSelectedKey = selectedKey
        selectedStock = stocksByKey[selectedKey]
    elseif stocks[1] then
        effectiveSelectedKey = stocks[1].key
        selectedStock = stocks[1]
    elseif allStocks[1] then
        effectiveSelectedKey = allStocks[1].key
        selectedStock = allStocks[1]
    end

    local effectivePinnedKey = nil
    local pinnedStock = nil
    if type(opts.pinnedKey) == "string" and stocksByKey[opts.pinnedKey] then
        effectivePinnedKey = opts.pinnedKey
        pinnedStock = stocksByKey[opts.pinnedKey]
    end

    local slides = H.buildSlides(allStocks, pinnedStock, summary, wealthSeries, ek, rKey, now, memo)
    local kpis, timing = H.buildKpisAndTiming(allStocks, selectedStock, summary, wealthSeries, ek, watchlistCount, opts)
    local headlines = H.buildHeadlines(
        allStocks, summary, rKey, watchlistCount, timing.trackedCraftsCount, timing.snapshotActive
    )

    return {
        econKey = ek,
        rangeKey = rKey,
        filterKey = fKey,
        now = now,
        selectedKey = effectiveSelectedKey,
        selectedStock = selectedStock,
        pinnedKey = effectivePinnedKey,
        pinnedStock = pinnedStock,
        allStocks = allStocks,
        stocks = stocks,
        stocksByKey = stocksByKey,
        mostActive = mostActive,
        slides = slides,
        headlines = headlines,
        kpis = kpis,
        timing = timing,
        summary = summary,
        wealthSeries = wealthSeries,
    }
end
