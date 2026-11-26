-- Morning Brief Executive Dashboard (Pure ASCII Lua)
-- Side-by-side Profit + Hourly/Daily Wealth charts, strict AH_SELL KPIs,
-- Reagent Price-Drop Alerts for top crafts, scrollable AH Sales log, and Best Items.
local _, ns = ...

local Brief = {}
ns.DashboardBrief = Brief

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format, tostring, tonumber, type = string.format, tostring, tonumber, type
local tsort, tconcat = table.sort, table.concat

local RANGE_OPTIONS = {
    { key = "24h", label = "24h", days = 1 },
    { key = "7d",  label = "7d",  days = 7 },
    { key = "14d", label = "14d", days = 14 },
    { key = "30d", label = "30d", days = 30 },
}
local RANGE_DAYS = { ["24h"] = 1, ["7d"] = 7, ["14d"] = 14, ["30d"] = 30 }

local MAX_POOL_ROWS = 18
local MAX_RECENT_SALES = 50
local MAX_ALERTS = 30
local REAGENT_DROP_THRESHOLD = -10.0

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function isSecret(v)
    return (_G.issecretvalue and _G.issecretvalue(v))
        or (type(v) == "table" and _G.issecrettable and _G.issecrettable(v))
end

local function safeNum(v, fallback)
    if isSecret(v) then return fallback end
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

local function nowSec(override)
    local ov = safeNum(override, nil)
    if ov and ov > 0 then return ov end
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and Store.Now then
        local t = safeNum(Store.Now(), nil)
        if t and t > 0 then return t end
    end
    if _G.time then
        local t = safeNum(_G.time(), nil)
        if t and t > 0 then return t end
    end
    if os and os.time then
        return safeNum(os.time(), 0) or 0
    end
    return 0
end

local function fmtDate(fmt, t)
    local fn = _G.date or (os and os.date)
    if not fn then return "" end
    local ok, val = pcall(fn, fmt, t)
    if not ok or isSecret(val) then return "" end
    return val
end

local function dayKeyFromSec(t)
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and Store.DayKey then
        local k = Store.DayKey(t)
        if type(k) == "string" and #k == 10 then return k end
    end
    local s = fmtDate("%Y-%m-%d", t)
    return (type(s) == "string" and #s == 10) and s or "1970-01-01"
end

local function hourFromSec(t)
    local h = safeNum(fmtDate("%H", t), nil)
    if not h then
        local tbl = fmtDate("*t", t)
        if type(tbl) == "table" then h = safeNum(tbl.hour, 0) end
    end
    h = floor(h or 0)
    return clamp(h, 0, 23)
end

local function getPalette()
    local T = ns.Theme
    if T and T.GetActivePalette then
        local pal = T.GetActivePalette()
        if type(pal) == "table" then return pal end
    end
    return {
        mode = "dark",
        cardBg = { 0.11, 0.12, 0.14, 0.94 },
        cardAltBg = { 0.08, 0.09, 0.11, 0.90 },
        border = { 1, 1, 1, 0.12 },
        separator = { 1, 1, 1, 0.14 },
        text = { 0.96, 0.96, 0.98, 1 },
        textSecondary = { 0.72, 0.74, 0.78, 1 },
        textMuted = { 0.55, 0.57, 0.62, 1 },
        accentBlue = { 0.20, 0.60, 1.00, 1 },
        accentGreen = { 0.19, 0.82, 0.35, 1 },
        accentOrange = { 1.00, 0.62, 0.16, 1 },
        accentRed = { 1.00, 0.27, 0.23, 1 },
        accentPurple = { 0.75, 0.35, 0.95, 1 },
        rowHover = { 1, 1, 1, 0.07 },
        pillTrack = { 1, 1, 1, 0.09 },
        pillThumb = { 1, 1, 1, 0.18 },
    }
end

local function setTextColor(fs, col)
    if not (fs and fs.SetTextColor and type(col) == "table") then return end
    fs:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
end

local function applyFont(fs, size, weight)
    if not fs then return end
    local T = ns.Theme
    if T and T.ApplyFont then
        T.ApplyFont(fs, size or 12, weight or "regular")
    end
end

local function formatCopper(copper, signed)
    local v = safeNum(copper, 0) or 0
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
Brief.FormatCopper = formatCopper

local function resolveItemName(itemID, fallback)
    local id = safeNum(itemID, 0) or 0
    if type(fallback) == "string" and fallback ~= "" and not isSecret(fallback) then
        return fallback
    end
    if id > 0 then
        if ns.GetItemName then
            local nm = ns.GetItemName(id)
            if type(nm) == "string" and nm ~= "" and not isSecret(nm) then return nm end
        end
        if ns.ITEMS and ns.ITEMS[id] and type(ns.ITEMS[id].name) == "string" then
            return ns.ITEMS[id].name
        end
        local Model = ns.Analytics and ns.Analytics.Model
        if Model and Model.ItemName then
            local nm = Model.ItemName(id)
            if type(nm) == "string" and nm ~= "" and not isSecret(nm) then return nm end
        end
        if _G.C_Item and _G.C_Item.GetItemNameByID then
            local ok, nm = pcall(_G.C_Item.GetItemNameByID, id)
            if ok and type(nm) == "string" and nm ~= "" and not isSecret(nm) then return nm end
        end
        if _G.GetItemInfo then
            local ok, nm = pcall(_G.GetItemInfo, id)
            if ok and type(nm) == "string" and nm ~= "" and not isSecret(nm) then return nm end
        end
        return "Item #" .. tostring(id)
    end
    return "Unknown Item"
end

local function resolveItemIcon(itemID)
    local id = safeNum(itemID, 0) or 0
    if id <= 0 then return nil end
    local Model = ns.Analytics and ns.Analytics.Model
    if Model and Model.ItemIcon then
        local ic = Model.ItemIcon(id)
        if ic and not isSecret(ic) then return ic end
    end
    if _G.C_Item and _G.C_Item.GetItemIconByID then
        local ok, ic = pcall(_G.C_Item.GetItemIconByID, id)
        if ok and ic and not isSecret(ic) then return ic end
    end
    if _G.GetItemIcon then
        local ok, ic = pcall(_G.GetItemIcon, id)
        if ok and ic and not isSecret(ic) then return ic end
    end
    return nil
end

local function resolveEconKey(override)
    if type(override) == "string" and override ~= "" then return override end
    if ns.DetectActiveEconomy then
        local ok, ek = pcall(ns.DetectActiveEconomy)
        if ok and type(ek) == "string" and ek ~= "" and not isSecret(ek) then return ek end
    end
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and Store.CurrentCharAndEcon then
        local _, ek = Store.CurrentCharAndEcon()
        if type(ek) == "string" and ek ~= "" then return ek end
    end
    return "Normal-Horde"
end

local function resolvePlayerName(override)
    if type(override) == "string" and override ~= "" and not isSecret(override) then
        return override
    end
    if _G.UnitName then
        local ok, nm = pcall(_G.UnitName, "player")
        if ok and type(nm) == "string" and nm ~= "" and not isSecret(nm) then
            return nm
        end
    end
    local ck = ns.app and ns.app.charKey
    if type(ck) == "string" and ck ~= "" then
        local short = ck:match("([^%-]+)$")
        if short and short ~= "" then return short end
    end
    return "Merchant"
end

function Brief.GetGreeting(hourOverride, playerNameOverride)
    local hr = safeNum(hourOverride, nil)
    if hr == nil then
        local tbl = fmtDate("*t", nowSec())
        hr = (type(tbl) == "table" and safeNum(tbl.hour, nil)) or hourFromSec(nowSec())
    end
    hr = clamp(floor(hr), 0, 23)
    local prefix
    if hr >= 5 and hr < 12 then
        prefix = "Good morning"
    elseif hr >= 12 and hr < 18 then
        prefix = "Good afternoon"
    else
        prefix = "Good evening"
    end
    return prefix .. ", " .. resolvePlayerName(playerNameOverride)
end

---------------------------------------------------------------------------------------------------
-- Single-Pass Cached AH_SELL Aggregator (Strict AH_SELL Only)
---------------------------------------------------------------------------------------------------
local ahCache = { sig = nil, base = nil }

function Brief.InvalidateCache()
    ahCache.sig = nil
    ahCache.base = nil
end

local function matchesEcon(rowEcon, rowChar, targetEcon, Store)
    if not targetEcon or targetEcon == "all" then return true end
    local eff = rowEcon or (Store and Store.DeriveEcon and Store.DeriveEcon(rowChar)) or nil
    return eff == targetEcon
end

local function computeAHBase(econKey, now)
    local Store = ns.Analytics and ns.Analytics.Store
    local todayKey = dayKeyFromSec(now)
    local ver = Store and (Store.version or 0) or 0
    local ahVer = Store and (Store.ahSalesVersion or 0) or 0
    local sig = format("%s|%s|%s|%s|%d", tostring(ver), tostring(ahVer), todayKey, tostring(econKey or "all"), floor(now / 3600))
    if ahCache.sig == sig and ahCache.base then
        return ahCache.base
    end

    local fromDay30 = dayKeyFromSec(now - 29 * 86400)
    local yesterdayKey = dayKeyFromSec(now - 86400)
    local curHourFloor = floor(now / 3600) * 3600
    local start24h = curHourFloor - 23 * 3600

    local dailyProfit = {}
    local dailyCount = {}
    local hourlyProfit = {}
    for i = 1, 24 do hourlyProfit[i] = 0 end

    local allAHRows = {}
    local craftFreq = {}
    local ahItemFreq = {}

    if Store and Store.IterDays then
        Store.IterDays(fromDay30, todayKey, function(day, rows)
            for i = 1, #(rows or {}) do
                local r = rows[i]
                if type(r) == "table" and matchesEcon(r.econ, r.char, econKey, Store) then
                    local rType = r.type
                    if rType == "CRAFT" then
                        local e = type(r.extra) == "table" and r.extra or nil
                        local sp = e and safeNum(e.spellID, nil)
                        local oid = safeNum(r.itemID, 0) or 0
                        local q = max(1, safeNum(r.qty, 1) or 1)
                        if sp and sp > 0 then
                            local key = "spell:" .. tostring(sp)
                            craftFreq[key] = (craftFreq[key] or 0) + q
                        elseif oid > 0 then
                            local key = "item:" .. tostring(oid)
                            craftFreq[key] = (craftFreq[key] or 0) + q
                        end
                    elseif rType == "AH_SELL" then
                        local e = type(r.extra) == "table" and r.extra or nil
                        local qty = max(1, safeNum(r.qty, 1) or 1)
                        local fee = (e and safeNum(e.fee, 0)) or 0
                        local net = safeNum(r.total, 0) or 0
                        local gross = (e and safeNum(e.gross, nil)) or max(0, net + fee)
                        local cogs = safeNum(r.cogs, 0) or 0
                        local profit = (gross - fee) - cogs
                        local ts = safeNum(r.time, 0) or 0
                        local itemID = safeNum(r.itemID, 0) or 0
                        local replayOrder = (e and safeNum(e.replayOrder, 0)) or 0

                        dailyProfit[day] = (dailyProfit[day] or 0) + profit
                        dailyCount[day] = (dailyCount[day] or 0) + 1

                        if ts >= start24h and ts < curHourFloor + 3600 then
                            local slot = floor((ts - start24h) / 3600) + 1
                            if slot >= 1 and slot <= 24 then
                                hourlyProfit[slot] = hourlyProfit[slot] + profit
                            end
                        elseif day == todayKey and ts == 0 then
                            hourlyProfit[24] = hourlyProfit[24] + profit
                        end

                        if itemID > 0 then
                            ahItemFreq[itemID] = (ahItemFreq[itemID] or 0) + max(1, profit > 0 and floor(profit / 100) or qty)
                        end

                        allAHRows[#allAHRows + 1] = {
                            itemID = itemID,
                            name = resolveItemName(itemID, e and e.name),
                            icon = resolveItemIcon(itemID),
                            qty = qty,
                            profit = profit,
                            net = net,
                            gross = gross,
                            fee = fee,
                            cogs = cogs,
                            time = ts,
                            day = day,
                            char = r.char,
                            replayOrder = replayOrder,
                        }
                    end
                end
            end
        end, { desc = true })
    end

    tsort(allAHRows, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        if a.replayOrder ~= b.replayOrder then return a.replayOrder > b.replayOrder end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    local recentSales = {}
    for i = 1, min(#allAHRows, MAX_RECENT_SALES) do
        recentSales[i] = allAHRows[i]
    end

    -- 7 completed calendar days [today - 7d .. yesterday] excluding partial today
    local sum7Completed = 0
    for dOff = 1, 7 do
        local dk = dayKeyFromSec(now - dOff * 86400)
        sum7Completed = sum7Completed + (dailyProfit[dk] or 0)
    end
    local avg7dCompleted = floor(sum7Completed / 7 + 0.5)
    local todayProfit = dailyProfit[todayKey] or 0
    local todaySalesCount = dailyCount[todayKey] or 0
    local yesterdayProfit = dailyProfit[yesterdayKey] or 0
    local yesterdaySalesCount = dailyCount[yesterdayKey] or 0
    local yesterdayDeltaPct = nil
    if avg7dCompleted ~= 0 then
        yesterdayDeltaPct = ((yesterdayProfit - avg7dCompleted) / abs(avg7dCompleted)) * 100
    end

    local hourlyBars = {}
    for i = 1, 24 do
        local slotTs = start24h + (i - 1) * 3600
        local hrStr = format("%02d:00", hourFromSec(slotTs))
        local dk = dayKeyFromSec(slotTs)
        hourlyBars[i] = {
            day = dk .. " " .. hrStr,
            label = hrStr,
            value = hourlyProfit[i] or 0,
            sortKey = slotTs,
        }
    end

    local base = {
        now = now,
        todayKey = todayKey,
        yesterdayKey = yesterdayKey,
        start24h = start24h,
        curHourFloor = curHourFloor,
        dailyProfit = dailyProfit,
        dailyCount = dailyCount,
        hourlyBars = hourlyBars,
        allAHRows = allAHRows,
        recentSales = recentSales,
        craftFreq = craftFreq,
        ahItemFreq = ahItemFreq,
        todayProfit = todayProfit,
        todaySalesCount = todaySalesCount,
        yesterdayProfit = yesterdayProfit,
        yesterdaySalesCount = yesterdaySalesCount,
        avg7dCompleted = avg7dCompleted,
        yesterdayDeltaPct = yesterdayDeltaPct,
    }
    ahCache.sig = sig
    ahCache.base = base
    return base
end

function Brief.ComputeAHSalesSummary(econKey, rangeKey, nowOverride)
    local now = nowSec(nowOverride)
    local rKey = RANGE_DAYS[rangeKey] and rangeKey or "7d"
    local base = computeAHBase(econKey, now)
    local numDays = RANGE_DAYS[rKey] or 7
    local fromDay = dayKeyFromSec(now - (numDays - 1) * 86400)

    local dailyBars = {}
    for dOff = numDays - 1, 0, -1 do
        local dk = dayKeyFromSec(now - dOff * 86400)
        dailyBars[#dailyBars + 1] = {
            day = dk,
            label = dk:sub(6),
            value = base.dailyProfit[dk] or 0,
        }
    end

    local byItem = {}
    local bestSingleSale = nil
    local rangeTotalProfit = 0
    local rangeSalesCount = 0

    for _, row in ipairs(base.allAHRows) do
        local inRange
        if rKey == "24h" then
            inRange = (row.time >= base.start24h) or (row.day == base.todayKey and row.time == 0)
        else
            inRange = (row.day >= fromDay and row.day <= base.todayKey)
        end
        if inRange then
            rangeTotalProfit = rangeTotalProfit + (row.profit or 0)
            rangeSalesCount = rangeSalesCount + 1
            if not bestSingleSale
                or (row.profit or 0) > (bestSingleSale.profit or 0)
                or ((row.profit or 0) == (bestSingleSale.profit or 0) and (row.net or 0) > (bestSingleSale.net or 0)) then
                bestSingleSale = row
            end
            local id = row.itemID or 0
            if id > 0 then
                local agg = byItem[id]
                if not agg then
                    agg = {
                        itemID = id,
                        name = row.name,
                        icon = row.icon,
                        profit = 0,
                        net = 0,
                        qty = 0,
                        salesCount = 0,
                    }
                    byItem[id] = agg
                end
                agg.profit = agg.profit + (row.profit or 0)
                agg.net = agg.net + (row.net or 0)
                agg.qty = agg.qty + (row.qty or 1)
                agg.salesCount = agg.salesCount + 1
            end
        end
    end

    local topItems = {}
    for _, agg in pairs(byItem) do
        topItems[#topItems + 1] = agg
    end
    tsort(topItems, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        if a.net ~= b.net then return a.net > b.net end
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    local maxProfit = (topItems[1] and topItems[1].profit) or 0
    for i = 1, #topItems do
        local it = topItems[i]
        if maxProfit > 0 and it.profit > 0 then
            it.shareRatio = clamp(it.profit / maxProfit, 0.06, 1.0)
        else
            it.shareRatio = 0.08
        end
    end

    return {
        rangeKey = rKey,
        todayKey = base.todayKey,
        yesterdayKey = base.yesterdayKey,
        todayProfit = base.todayProfit,
        todaySalesCount = base.todaySalesCount,
        yesterdayProfit = base.yesterdayProfit,
        yesterdaySalesCount = base.yesterdaySalesCount,
        avg7dCompleted = base.avg7dCompleted,
        yesterdayDeltaPct = base.yesterdayDeltaPct,
        rangeTotalProfit = rangeTotalProfit,
        rangeSalesCount = rangeSalesCount,
        dailyBars = dailyBars,
        hourlyBars = base.hourlyBars,
        profitBars = (rKey == "24h") and base.hourlyBars or dailyBars,
        recentSales = base.recentSales,
        topItems = topItems,
        bestItem = topItems[1],
        bestSingleSale = bestSingleSale,
        craftFreq = base.craftFreq,
        ahItemFreq = base.ahItemFreq,
    }
end

---------------------------------------------------------------------------------------------------
-- Hourly & Daily Wealth Series Builder (with Day-1 Ledger Reconstruction Fallback)
---------------------------------------------------------------------------------------------------
local function readPortfolio(econKey, rangeKey)
    local Model = ns.Analytics and ns.Analytics.Model
    local p = nil
    if Model and Model.Compute then
        local period = (rangeKey == "24h") and "7d" or (RANGE_DAYS[rangeKey] and rangeKey or "7d")
        local ok, res = pcall(Model.Compute, "portfolio", { char = "all", econ = econKey, period = period })
        if ok and type(res) == "table" then p = res end
    end
    if not p then
        p = { series = {}, latestTotal = 0, latestGold = 0, latestItems = 0, latestListed = 0, firstTotal = 0 }
    end
    if #(p.series or {}) == 0 and (p.latestTotal or 0) == 0 then
        local liveGold = (_G.GetMoney and safeNum(_G.GetMoney(), 0)) or 0
        p.latestGold = liveGold
        p.latestTotal = liveGold
    end
    return p
end

function Brief.BuildWealthChartSeries(wealthMode, rangeKey, econKey, portfolioData, nowOverride)
    local now = nowSec(nowOverride)
    local Store = ns.Analytics and ns.Analytics.Store
    local p = portfolioData or readPortfolio(econKey, rangeKey)
    local dailySeries = type(p.series) == "table" and p.series or {}
    local latestTotal = safeNum(p.latestTotal, 0) or 0
    if latestTotal == 0 and #dailySeries == 0 and _G.GetMoney then
        latestTotal = safeNum(_G.GetMoney(), 0) or 0
    end

    local effectiveMode = wealthMode
    if effectiveMode ~= "hourly" and effectiveMode ~= "daily" then
        if rangeKey == "24h" or #dailySeries < 2 then
            effectiveMode = "hourly"
        else
            effectiveMode = "daily"
        end
    end

    if effectiveMode == "daily" and #dailySeries >= 2 then
        local pts = {}
        for i, pt in ipairs(dailySeries) do
            pts[#pts + 1] = {
                day = pt.day or tostring(i),
                label = (type(pt.day) == "string" and #pt.day >= 10) and pt.day:sub(6) or (pt.label or tostring(i)),
                value = safeNum(pt.total, 0) or 0,
                gold = safeNum(pt.gold, 0) or 0,
                items = safeNum(pt.items, 0) or 0,
                listed = safeNum(pt.listed, 0) or 0,
                sortKey = i,
                isReconstructed = false,
            }
        end
        local lastVal = pts[#pts] and pts[#pts].value or latestTotal
        local prevVal = pts[#pts - 1] and pts[#pts - 1].value or lastVal
        return {
            mode = "daily",
            points = pts,
            usedFallback = false,
            latestTotal = latestTotal,
            change24h = lastVal - prevVal,
            dailyCount = #dailySeries,
        }
    end

    -- Hourly Wealth mode (also serves as fallback when < 2 daily snapshots exist)
    local todayKey = dayKeyFromSec(now)
    local yesterdayKey = dayKeyFromSec(now - 86400)
    local curHourFloor = floor(now / 3600) * 3600
    local minTs = curHourFloor - 23 * 3600

    local rawPts = {}
    local intraday = Store and Store.db and Store.db.intradaySnaps
    if type(intraday) == "table" then
        for _, dk in ipairs({ yesterdayKey, todayKey }) do
            local dayRec = intraday[dk]
            local ptsMap = type(dayRec) == "table" and dayRec.points
            if type(ptsMap) == "table" then
                for hKey, pt in pairs(ptsMap) do
                    if type(pt) == "table" and type(pt.chars) == "table" then
                        local ts = safeNum(pt.time, 0) or 0
                        if ts == 0 or (ts >= minTs - 3600 and ts <= curHourFloor + 3600) then
                            local sumGold, sumItems, sumListed, matched = 0, 0, 0, 0
                            for cKey, cSnap in pairs(pt.chars) do
                                if type(cSnap) == "table" and matchesEcon(cSnap.econ, cKey, econKey, Store) then
                                    sumGold = sumGold + (safeNum(cSnap.gold, 0) or 0)
                                    sumItems = sumItems + (safeNum(cSnap.items, 0) or 0)
                                    sumListed = sumListed + (safeNum(cSnap.listed, 0) or 0)
                                    matched = matched + 1
                                end
                            end
                            if matched > 0 then
                                local hr = safeNum(pt.hour, safeNum(hKey, 0)) or 0
                                local label = format("%02d:00", clamp(floor(hr), 0, 23))
                                rawPts[#rawPts + 1] = {
                                    day = dk .. " " .. label,
                                    label = label,
                                    value = sumGold + sumItems + sumListed,
                                    gold = sumGold,
                                    items = sumItems,
                                    listed = sumListed,
                                    sortKey = ts > 0 and ts or (curHourFloor - (23 - hr) * 3600),
                                    isReconstructed = false,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    tsort(rawPts, function(a, b)
        if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
        return tostring(a.day) < tostring(b.day)
    end)

    -- Keep at most 24 newest points
    if #rawPts > 24 then
        local trimmed = {}
        for i = #rawPts - 23, #rawPts do
            trimmed[#trimmed + 1] = rawPts[i]
        end
        rawPts = trimmed
    end

    if #rawPts >= 2 then
        local firstV = rawPts[1].value or 0
        local lastV = rawPts[#rawPts].value or latestTotal
        return {
            mode = "hourly",
            points = rawPts,
            usedFallback = false,
            latestTotal = latestTotal > 0 and latestTotal or lastV,
            change24h = lastV - firstV,
            dailyCount = #dailySeries,
        }
    end

    -- Day-1 fallback: reconstruct today's hourly wealth curve backward from latestTotal
    -- using today's timestamped ledger cashflows so the hourly graph works immediately!
    local curHr = hourFromSec(now)
    local deltaByHr = {}
    local earliestEventHr = curHr
    if Store and Store.IterDays then
        Store.IterDays(todayKey, todayKey, function(_, rows)
            for i = 1, #(rows or {}) do
                local r = rows[i]
                if type(r) == "table" and matchesEcon(r.econ, r.char, econKey, Store) then
                    local totalDelta = safeNum(r.total, 0) or 0
                    if totalDelta ~= 0 then
                        local rTs = safeNum(r.time, 0) or 0
                        local h = rTs > 0 and hourFromSec(rTs) or curHr
                        h = clamp(h, 0, curHr)
                        deltaByHr[h] = (deltaByHr[h] or 0) + totalDelta
                        if h < earliestEventHr then earliestEventHr = h end
                    end
                end
            end
        end)
    end

    local reconPts = {}
    if curHr == 0 then
        local startVal = max(0, latestTotal - (deltaByHr[0] or 0))
        reconPts[1] = {
            day = todayKey .. " 00:00 (Start)",
            label = "Start",
            value = startVal,
            sortKey = curHourFloor - 1800,
            isReconstructed = true,
        }
        reconPts[2] = {
            day = todayKey .. " 00:00",
            label = "00:00",
            value = latestTotal,
            sortKey = curHourFloor,
            isReconstructed = true,
        }
    else
        local startHr = min(earliestEventHr, max(0, curHr - 7))
        if startHr >= curHr then startHr = curHr - 1 end
        local vals = {}
        vals[curHr] = latestTotal
        for h = curHr, startHr + 1, -1 do
            vals[h - 1] = max(0, (vals[h] or 0) - (deltaByHr[h] or 0))
        end
        for h = startHr, curHr do
            local label = format("%02d:00", h)
            reconPts[#reconPts + 1] = {
                day = todayKey .. " " .. label,
                label = label,
                value = vals[h] or 0,
                sortKey = curHourFloor - (curHr - h) * 3600,
                isReconstructed = true,
            }
        end
    end

    local firstV = reconPts[1] and reconPts[1].value or latestTotal
    local lastV = reconPts[#reconPts] and reconPts[#reconPts].value or latestTotal
    return {
        mode = "hourly",
        points = reconPts,
        usedFallback = true,
        latestTotal = latestTotal,
        change24h = lastV - firstV,
        dailyCount = #dailySeries,
    }
end

---------------------------------------------------------------------------------------------------
-- Reagent Price-Drop Impact Alerts (Your Top Crafts)
---------------------------------------------------------------------------------------------------
local function computeReagentBaseline(rgID, econKey, now)
    local curDay = floor(now / 86400)
    local db = _G.MerchantMasterDB

    -- (a) MarketScan.GetItemTrend7d: mean of prior days (pt.d < curDay)
    local MS = ns.MarketScan
    if MS and type(MS.GetItemTrend7d) == "function" then
        local ok, trend = pcall(MS.GetItemTrend7d, rgID, econKey, now)
        if ok and type(trend) == "table" and type(trend.points) == "table" then
            local sum, count = 0, 0
            local allSum, allCount = 0, 0
            for _, pt in ipairs(trend.points) do
                local p = type(pt) == "table" and safeNum(pt.price, nil)
                local d = type(pt) == "table" and safeNum(pt.d, nil)
                if p and p > 0 then
                    allSum = allSum + p
                    allCount = allCount + 1
                    if d and d < curDay then
                        sum = sum + p
                        count = count + 1
                    end
                end
            end
            if count > 0 then
                return sum / count, count, "trend7d"
            elseif allCount >= 2 then
                -- Exclude the newest point if all points share curDay
                local lastPt = trend.points[#trend.points]
                local lastP = type(lastPt) == "table" and safeNum(lastPt.price, 0) or 0
                if allCount > 1 and allSum > lastP then
                    return (allSum - lastP) / (allCount - 1), allCount - 1, "trend7d"
                end
            end
        end
    end

    -- (b) Pricing.GetItemHeatStrip24h.avgPrice/medianPrice or GetItemHeatmap.overall.avgPrice
    if ns.Pricing then
        if type(ns.Pricing.GetItemHeatStrip24h) == "function" then
            local ok, hs = pcall(ns.Pricing.GetItemHeatStrip24h, rgID, econKey)
            if ok and type(hs) == "table" then
                local avgP = safeNum(hs.avgPrice, nil) or safeNum(hs.medianPrice, nil)
                if avgP and avgP > 0 then
                    return avgP, safeNum(hs.sampleCount, 2) or 2, "heat24h"
                end
            end
        end
        if type(ns.Pricing.GetItemHeatmap) == "function" then
            local ok, hm = pcall(ns.Pricing.GetItemHeatmap, rgID, econKey)
            if ok and type(hm) == "table" and type(hm.overall) == "table" then
                local avgP = safeNum(hm.overall.avgPrice, nil)
                if avgP and avgP > 0 then
                    return avgP, safeNum(hm.overall.sampleCount, 2) or 2, "heatmap"
                end
            end
        end
    end

    -- (c) QueryLocalSnapshot .historical or .marketValue
    if type(ns.QueryLocalSnapshot) == "function" then
        local ok, _, snapRec = pcall(ns.QueryLocalSnapshot, rgID, econKey)
        if ok and type(snapRec) == "table" then
            local baseP = safeNum(snapRec.historical, nil)
            if not baseP or baseP <= 0 then baseP = safeNum(snapRec.marketValue, nil) end
            if baseP and baseP > 0 then
                return baseP, 2, "snapshot"
            end
        end
    end

    -- (d) MarketScan.ReadHistory(db.ahHistory[econKey][rgID]) mean of prior samples s.t < latestAt
    if MS and type(MS.ReadHistory) == "function" and type(db) == "table"
        and type(db.ahHistory) == "table" and type(db.ahHistory[econKey]) == "table" then
        local raw = db.ahHistory[econKey][rgID]
        if raw then
            local ok, ring = pcall(MS.ReadHistory, raw)
            if ok and type(ring) == "table" and #ring >= 2 then
                local latestAt = 0
                for _, s in ipairs(ring) do
                    local st = type(s) == "table" and safeNum(s.t, 0) or 0
                    if st > latestAt then latestAt = st end
                end
                local sum, count = 0, 0
                for _, s in ipairs(ring) do
                    local st = type(s) == "table" and safeNum(s.t, 0) or 0
                    local sp = type(s) == "table" and safeNum(s.p, nil)
                    if sp and sp > 0 and st < latestAt then
                        sum = sum + sp
                        count = count + 1
                    end
                end
                if count > 0 then
                    return sum / count, count, "history"
                end
            end
        end
    end

    return nil, 0, nil
end

local function lookupRecipeBySpell(spellID)
    local id = safeNum(spellID, 0) or 0
    if id <= 0 then return nil end
    if ns.RECIPES_BY_SPELL and ns.RECIPES_BY_SPELL[id] then
        return ns.RECIPES_BY_SPELL[id]
    end
    local Model = ns.Analytics and ns.Analytics.Model
    if Model and Model.GetIndexes then
        local ok, idx = pcall(Model.GetIndexes)
        if ok and type(idx) == "table" and type(idx.RECIPE_BY_SPELL) == "table" then
            return idx.RECIPE_BY_SPELL[id]
        end
    end
    if type(ns.RECIPES) == "table" then
        for _, r in ipairs(ns.RECIPES) do
            if r and safeNum(r.spellID, 0) == id then return r end
        end
    end
    return nil
end

local function lookupRecipeByOutput(itemID)
    local id = safeNum(itemID, 0) or 0
    if id <= 0 then return nil end
    if ns.RECIPES_BY_OUTPUT and ns.RECIPES_BY_OUTPUT[id] then
        local list = ns.RECIPES_BY_OUTPUT[id]
        if type(list) == "table" then
            if list.reagents then return list end
            if list[1] then return list[1] end
        end
    end
    if type(ns.RECIPES) == "table" then
        for _, r in ipairs(ns.RECIPES) do
            if r and safeNum(r.outputItemID, 0) == id then return r end
        end
    end
    return nil
end

local function gatherCandidateRecipes(summary)
    local candidates = {}
    local seen = {}
    local function addRec(rec, weight, isSuggested)
        if type(rec) ~= "table" then return end
        local key = rec.spellID and ("s:" .. tostring(rec.spellID))
            or (rec.outputItemID and ("i:" .. tostring(rec.outputItemID)))
            or rec.name
        if not key or seen[key] then return end
        seen[key] = true
        candidates[#candidates + 1] = {
            recipe = rec,
            weight = weight or 1,
            isSuggested = isSuggested == true,
        }
    end

    -- 1. Ledger CRAFT history
    local craftRanked = {}
    for k, w in pairs((summary and summary.craftFreq) or {}) do
        craftRanked[#craftRanked + 1] = { key = k, weight = w }
    end
    tsort(craftRanked, function(a, b) return a.weight > b.weight end)
    for _, entry in ipairs(craftRanked) do
        if #candidates >= 25 then break end
        local sp = entry.key:match("^spell:(%d+)$")
        local oid = entry.key:match("^item:(%d+)$")
        local rec = sp and lookupRecipeBySpell(tonumber(sp)) or (oid and lookupRecipeByOutput(tonumber(oid)))
        if rec then addRec(rec, 1000 + entry.weight, false) end
    end

    -- 2. Ledger AH_SELL output items that are craftable
    local ahRanked = {}
    for id, w in pairs((summary and summary.ahItemFreq) or {}) do
        ahRanked[#ahRanked + 1] = { itemID = id, weight = w }
    end
    tsort(ahRanked, function(a, b) return a.weight > b.weight end)
    for _, entry in ipairs(ahRanked) do
        if #candidates >= 28 then break end
        local rec = lookupRecipeByOutput(entry.itemID)
        if rec then addRec(rec, 500 + entry.weight, false) end
    end

    -- 3. Watchlist favorited recipes
    local WL = ns.Watchlist
    if WL and type(WL.GetEntries) == "function" then
        local ok, entries = pcall(WL.GetEntries)
        if ok and type(entries) == "table" then
            for _, ent in ipairs(entries) do
                if #candidates >= 30 then break end
                if type(ent) == "table" then
                    local rec = (ent.spellID and lookupRecipeBySpell(ent.spellID))
                        or (ent.itemID and lookupRecipeByOutput(ent.itemID))
                    if rec then addRec(rec, 750, false) end
                end
            end
        end
    end

    -- 4. Cold-start fallback ("Suggested")
    if #candidates < 3 then
        local topCrafts = ns.app and ns.app.lastDashboardInsights and ns.app.lastDashboardInsights.topCrafts
        if type(topCrafts) == "table" then
            for _, row in ipairs(topCrafts) do
                if #candidates >= 25 then break end
                local rec = type(row) == "table" and (row.recipe or (row.spellID and lookupRecipeBySpell(row.spellID))
                    or (row.outputItemID and lookupRecipeByOutput(row.outputItemID)))
                if rec then addRec(rec, 100, true) end
            end
        end
    end
    if #candidates < 3 and type(ns.RECIPES) == "table" then
        for i = 1, min(#ns.RECIPES, 25) do
            if #candidates >= 25 then break end
            local rec = ns.RECIPES[i]
            if type(rec) == "table" and rec.reagents then
                addRec(rec, 50, true)
            end
        end
    end

    return candidates
end

function Brief.ComputeReagentPriceDrops(econKey, nowOverride, summaryOverride, priceBankOverride)
    local now = nowSec(nowOverride)
    local ek = resolveEconKey(econKey)
    local summary = summaryOverride or Brief.ComputeAHSalesSummary(ek, "30d", now)
    local candidates = gatherCandidateRecipes(summary)
    if #candidates == 0 then return {} end

    local beganEval = false
    if type(ns.BeginEval) == "function" then
        local bank = priceBankOverride or (ns.app and ns.app.getUIPriceBank and ns.app.getUIPriceBank()) or nil
        pcall(ns.BeginEval, bank)
        beganEval = true
    end

    local alerts = {}
    local okRun, errRun = pcall(function()
        local reagentEval = {}
        local function evalReagent(rgID)
            local cached = reagentEval[rgID]
            if cached ~= nil then
                return cached ~= false and cached or nil
            end
            local curUnit, curSrc, isVendor
            if type(ns.GetReagentUnitCost) == "function" then
                curUnit, curSrc, isVendor = ns.GetReagentUnitCost(rgID)
            elseif type(ns.GetItemMarketPrice) == "function" then
                curUnit, curSrc = ns.GetItemMarketPrice(rgID)
                isVendor = false
            end
            curUnit = safeNum(curUnit, nil)
            if isVendor == true or not curUnit or curUnit <= 0 then
                reagentEval[rgID] = false
                return nil
            end
            if type(ns.GetNumListed) == "function" then
                local listedQty = safeNum(ns.GetNumListed(rgID), nil)
                if listedQty ~= nil and listedQty <= 0 then
                    reagentEval[rgID] = false
                    return nil
                end
            end
            local baselineUnit, sampleCount, baseSrc = computeReagentBaseline(rgID, ek, now)
            baselineUnit = safeNum(baselineUnit, nil)
            if not baselineUnit or baselineUnit <= 0 or curUnit >= baselineUnit then
                reagentEval[rgID] = false
                return nil
            end
            -- Guard single-sample >10x spikes
            if baselineUnit > curUnit * 10 and (sampleCount or 0) <= 1 then
                reagentEval[rgID] = false
                return nil
            end
            local dropPct = ((curUnit - baselineUnit) / baselineUnit) * 100
            if dropPct > REAGENT_DROP_THRESHOLD then
                reagentEval[rgID] = false
                return nil
            end
            local rec = {
                reagentID = rgID,
                reagentName = resolveItemName(rgID),
                reagentIcon = resolveItemIcon(rgID),
                curUnit = floor(curUnit + 0.5),
                baselineUnit = floor(baselineUnit + 0.5),
                unitSaved = baselineUnit - curUnit,
                dropPct = dropPct,
                curSrc = curSrc,
                baseSrc = baseSrc,
            }
            reagentEval[rgID] = rec
            return rec
        end

        local seenPair = {}
        for _, cand in ipairs(candidates) do
            local rec = cand.recipe
            local reagents = (type(ns.ResolveRecipeReagents) == "function" and ns.ResolveRecipeReagents(rec))
                or rec.reagents
            if type(reagents) == "table" then
                local numMade = max(1, safeNum(rec.numMade, 1) or 1)
                local recName = rec.name or resolveItemName(rec.outputItemID)
                for _, rg in ipairs(reagents) do
                    local rgID = type(rg) == "table" and safeNum(rg.itemID or rg[1], 0) or 0
                    local rgQty = type(rg) == "table" and safeNum(rg.qty or rg[2], 0) or 0
                    if rgID > 0 and rgQty > 0 then
                        local pairKey = tostring(rec.spellID or rec.outputItemID or recName) .. ":" .. tostring(rgID)
                        if not seenPair[pairKey] then
                            seenPair[pairKey] = true
                            local ev = evalReagent(rgID)
                            if ev then
                                local craftSaved = floor(ev.unitSaved * rgQty + 0.5)
                                local perItemSaved = floor((ev.unitSaved * rgQty) / numMade + 0.5)
                                alerts[#alerts + 1] = {
                                    recipe = rec,
                                    recipeName = recName,
                                    spellID = safeNum(rec.spellID, nil),
                                    outputItemID = safeNum(rec.outputItemID, nil),
                                    numMade = numMade,
                                    isSuggested = cand.isSuggested,
                                    reagentID = ev.reagentID,
                                    reagentName = ev.reagentName,
                                    reagentIcon = ev.reagentIcon,
                                    reagentQty = rgQty,
                                    curUnit = ev.curUnit,
                                    baselineUnit = ev.baselineUnit,
                                    unitSaved = floor(ev.unitSaved + 0.5),
                                    craftSaved = craftSaved,
                                    perItemSaved = perItemSaved,
                                    dropPct = ev.dropPct,
                                    baseSrc = ev.baseSrc,
                                }
                            end
                        end
                    end
                end
            end
        end
    end)

    if beganEval and type(ns.EndEval) == "function" then
        pcall(ns.EndEval)
    end
    if not okRun then
        return {}
    end

    tsort(alerts, function(a, b)
        if a.isSuggested ~= b.isSuggested then return not a.isSuggested end
        if a.craftSaved ~= b.craftSaved then return a.craftSaved > b.craftSaved end
        if a.dropPct ~= b.dropPct then return a.dropPct < b.dropPct end
        return tostring(a.recipeName or "") < tostring(b.recipeName or "")
    end)

    if #alerts > MAX_ALERTS then
        local capped = {}
        for i = 1, MAX_ALERTS do capped[i] = alerts[i] end
        return capped
    end
    return alerts
end

---------------------------------------------------------------------------------------------------
-- UI Construction Helpers (Zero Unicode, Skin-Aware, host_fixture-Safe)
---------------------------------------------------------------------------------------------------
local function createCardFrame(parent, borderKey)
    local T = ns.Theme
    local frame = CreateFrame("Frame", nil, parent)
    if T and T.NineApple then
        frame._surface = T.NineApple(frame, "glass_r10", "cardBg", borderKey or false, { noSpecular = true })
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        frame._fallbackBg = bg
    end

    -- Custom Warcraft skin surface & edges (matches UI_Theme CreateKpiCard)
    local skinTile = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    skinTile:SetAllPoints()
    skinTile:Hide()
    frame._skinTile = skinTile

    local skinEdges = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local edge = frame:CreateTexture(nil, "BORDER", nil, 2)
        if side == "top" then
            edge:SetPoint("TOPLEFT", 0, 0); edge:SetPoint("TOPRIGHT", 0, 0); edge:SetHeight(1)
        elseif side == "bottom" then
            edge:SetPoint("BOTTOMLEFT", 0, 0); edge:SetPoint("BOTTOMRIGHT", 0, 0); edge:SetHeight(1)
        elseif side == "left" then
            edge:SetPoint("TOPLEFT", 0, 0); edge:SetPoint("BOTTOMLEFT", 0, 0); edge:SetWidth(1)
        else
            edge:SetPoint("TOPRIGHT", 0, 0); edge:SetPoint("BOTTOMRIGHT", 0, 0); edge:SetWidth(1)
        end
        edge:Hide()
        skinEdges[#skinEdges + 1] = edge
    end
    frame._skinEdges = skinEdges

    function frame:PaintCard(pal)
        pal = pal or getPalette()
        if self._surface and self._surface.UpdateTheme then
            self._surface:UpdateTheme("cardBg", borderKey or false)
        elseif self._fallbackBg then
            self._fallbackBg:SetColorTexture(pal.cardBg[1], pal.cardBg[2], pal.cardBg[3], pal.cardBg[4] or 0.94)
        end
        local custom = T and T.IsCustomSkin and T.IsCustomSkin()
        if custom and pal.frameBorder and T.GetSkinAsset and T.GetSkin then
            local tex = T.GetSkinAsset(T.GetSkin(), "surface")
            if tex then
                self._skinTile:SetTexture(tex, "CLAMP", "CLAMP")
                self._skinTile:Show()
            else
                self._skinTile:Hide()
            end
            local fb = pal.frameBorder
            for _, e in ipairs(self._skinEdges) do
                e:SetColorTexture(fb[1], fb[2], fb[3], 0.85)
                e:Show()
            end
        else
            self._skinTile:Hide()
            for _, e in ipairs(self._skinEdges) do e:Hide() end
        end
    end

    return frame
end

local function makeFS(parent, size, weight, justifyH)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH(justifyH or "LEFT")
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    applyFont(fs, size or 12, weight or "regular")
    fs._briefSize = size or 12
    fs._briefWeight = weight or "regular"
    return fs
end

local function createCompactKpi(parent, hasWealthBar)
    local card = createCardFrame(parent, false)
    card.titleFs = makeFS(card, 11, "semibold", "LEFT")
    card.titleFs:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card.titleFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -10)

    card.valueFs = makeFS(card, 20, "semibold", "LEFT")
    card.valueFs:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -26)
    card.valueFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -26)

    if hasWealthBar then
        local barWrap = CreateFrame("Frame", nil, card)
        barWrap:SetHeight(5)
        barWrap:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 26)
        barWrap:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 26)

        local track = barWrap:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        barWrap.track = track

        barWrap.segGold = barWrap:CreateTexture(nil, "ARTWORK")
        barWrap.segItems = barWrap:CreateTexture(nil, "ARTWORK")
        barWrap.segListed = barWrap:CreateTexture(nil, "ARTWORK")
        card.wealthBar = barWrap
    end

    card.subFs = makeFS(card, 11, "regular", "LEFT")
    card.subFs:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 9)
    card.subFs:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 9)

    card._valueColorKey = "text"
    card._subColorKey = "textSecondary"

    function card:PaintKpi(pal)
        pal = pal or getPalette()
        self:PaintCard(pal)
        applyFont(self.titleFs, 11, "semibold")
        applyFont(self.valueFs, 20, "semibold")
        applyFont(self.subFs, 11, "regular")
        setTextColor(self.titleFs, pal.textSecondary)
        setTextColor(self.valueFs, pal[self._valueColorKey] or pal.text)
        setTextColor(self.subFs, pal[self._subColorKey] or pal.textSecondary)
        if self.wealthBar then
            local sep = pal.separator or { 1, 1, 1, 0.14 }
            self.wealthBar.track:SetColorTexture(sep[1], sep[2], sep[3], 0.25)
            local cGold = pal.accentOrange or { 1.0, 0.72, 0.18, 1 }
            local cItems = pal.accentBlue or { 0.20, 0.60, 1.0, 1 }
            local cListed = pal.accentGreen or { 0.19, 0.82, 0.35, 1 }
            self.wealthBar.segGold:SetColorTexture(cGold[1], cGold[2], cGold[3], 0.95)
            self.wealthBar.segItems:SetColorTexture(cItems[1], cItems[2], cItems[3], 0.95)
            self.wealthBar.segListed:SetColorTexture(cListed[1], cListed[2], cListed[3], 0.95)
        end
    end

    function card:SetWealthRatios(goldVal, itemsVal, listedVal)
        local wb = self.wealthBar
        if not wb then return end
        local g = max(0, safeNum(goldVal, 0) or 0)
        local it = max(0, safeNum(itemsVal, 0) or 0)
        local li = max(0, safeNum(listedVal, 0) or 0)
        local tot = g + it + li
        wb._ratios = { g = g, it = it, li = li, tot = tot }
        local w = max(1, (safeNum(self:GetWidth(), 240) or 240) - 24)
        if tot <= 0 then
            wb.segGold:Hide(); wb.segItems:Hide(); wb.segListed:Hide()
            return
        end
        local wG = floor(w * (g / tot) + 0.5)
        local wI = floor(w * (it / tot) + 0.5)
        local wL = max(0, w - wG - wI)
        if g > 0 and wG < 2 then wG = 2 end
        if it > 0 and wI < 2 then wI = 2 end
        if li > 0 and wL < 2 then wL = 2 end
        local sumW = wG + wI + wL
        if sumW > w then
            local over = sumW - w
            if wG >= wI and wG >= wL then wG = max(0, wG - over)
            elseif wI >= wL then wI = max(0, wI - over)
            else wL = max(0, wL - over) end
        end
        local x = 0
        if wG > 0 then
            wb.segGold:ClearAllPoints()
            wb.segGold:SetPoint("TOPLEFT", wb, "TOPLEFT", x, 0)
            wb.segGold:SetSize(wG, 5)
            wb.segGold:Show()
            x = x + wG
        else
            wb.segGold:Hide()
        end
        if wI > 0 then
            wb.segItems:ClearAllPoints()
            wb.segItems:SetPoint("TOPLEFT", wb, "TOPLEFT", x, 0)
            wb.segItems:SetSize(wI, 5)
            wb.segItems:Show()
            x = x + wI
        else
            wb.segItems:Hide()
        end
        if wL > 0 then
            wb.segListed:ClearAllPoints()
            wb.segListed:SetPoint("TOPLEFT", wb, "TOPLEFT", x, 0)
            wb.segListed:SetSize(wL, 5)
            wb.segListed:Show()
        else
            wb.segListed:Hide()
        end
    end

    return card
end

local function createSegmentedFallback(parent, items, opts)
    local T = ns.Theme
    if T and type(T.CreateSegmentedControl) == "function" then
        return T.CreateSegmentedControl(parent, items, opts)
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight((opts and opts.height) or 26)
    local activeKey = (opts and opts.activeKey) or (items[1] and items[1].key)
    local buttons = {}
    local x = 2
    local ctrl = { frame = f, buttons = buttons }
    function ctrl:SetActive(k, silent)
        activeKey = k
        if not silent and opts and opts.onChange then opts.onChange(k) end
    end
    function ctrl:GetActive() return activeKey end
    function ctrl:UpdateTheme() end
    for _, def in ipairs(items or {}) do
        local b = CreateFrame("Button", nil, f)
        local bw = def.width or max(36, #(def.label or "") * 7 + 14)
        b:SetSize(bw, ((opts and opts.height) or 26) - 4)
        b:SetPoint("LEFT", f, "LEFT", x, 0)
        local lbl = makeFS(b, (opts and opts.fontSize) or 11, "semibold", "CENTER")
        lbl:SetAllPoints()
        lbl:SetText(def.label or def.key)
        b._label = lbl
        b:SetScript("OnClick", function() ctrl:SetActive(def.key, false) end)
        buttons[def.key] = b
        x = x + bw + 2
    end
    f:SetWidth(x + 2)
    return ctrl
end

local function createBadgeFallback(parent, text, variant, opts)
    local T = ns.Theme
    if T and type(T.CreateBadgePill) == "function" then
        return T.CreateBadgePill(parent, text, variant, opts)
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(80, (opts and opts.height) or 20)
    local lbl = makeFS(f, (opts and opts.fontSize) or 10, "semibold", "CENTER")
    lbl:SetAllPoints()
    lbl:SetText(text or "")
    local pill = { frame = f, label = lbl }
    function pill:SetVariant(_, newText)
        if newText ~= nil then lbl:SetText(tostring(newText)) end
        f:SetWidth(max(36, #(lbl:GetText() or "") * 6 + 12))
    end
    return pill
end

local function createBentoPanel(parent, titleText)
    local card = createCardFrame(parent, false)
    local hdr = CreateFrame("Frame", nil, card)
    hdr:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    hdr:SetHeight(32)
    card.header = hdr

    local titleFs = makeFS(hdr, 12, "semibold", "LEFT")
    titleFs:SetPoint("LEFT", hdr, "LEFT", 12, 0)
    titleFs:SetText(titleText or "")
    card.titleFs = titleFs

    local badge = createBadgeFallback(hdr, "", "neutral", { height = 18, fontSize = 10, padX = 10 })
    badge.frame:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)
    card.badge = badge

    titleFs:SetPoint("RIGHT", badge.frame, "LEFT", -8, 0)

    local sep = card:CreateTexture(nil, "BORDER")
    sep:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -32)
    sep:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -32)
    sep:SetHeight(1)
    card.headerSep = sep

    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -35)
    body:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 6)
    card.body = body

    local emptyFs = makeFS(body, 11, "regular", "CENTER")
    emptyFs:SetPoint("CENTER", body, "CENTER", 0, 0)
    emptyFs:SetWordWrap(true)
    if emptyFs.SetMaxLines then emptyFs:SetMaxLines(3) end
    emptyFs:Hide()
    card.emptyFs = emptyFs

    -- Lightweight pure-texture scroll track + thumb (works in both WoW 16001 and host_fixture)
    local scrollTrack = body:CreateTexture(nil, "BORDER")
    scrollTrack:SetPoint("TOPRIGHT", body, "TOPRIGHT", -1, -2)
    scrollTrack:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -1, 2)
    scrollTrack:SetWidth(4)
    scrollTrack:Hide()
    card.scrollTrack = scrollTrack

    local scrollThumb = body:CreateTexture(nil, "ARTWORK")
    scrollThumb:SetWidth(4)
    scrollThumb:Hide()
    card.scrollThumb = scrollThumb

    function card:UpdateScrollThumb(totalCount, visibleCount, offset)
        local maxOff = max(0, (totalCount or 0) - (visibleCount or 1))
        if maxOff <= 0 then
            self.scrollTrack:Hide()
            self.scrollThumb:Hide()
            return
        end
        local bodyH = max(24, (safeNum(self.body:GetHeight(), 200) or 200) - 4)
        local thumbH = max(18, floor(bodyH * (visibleCount / totalCount) + 0.5))
        local travel = max(0, bodyH - thumbH)
        local ratio = clamp((offset or 0) / maxOff, 0, 1)
        local yOff = -2 - floor(travel * ratio + 0.5)
        self.scrollTrack:Show()
        self.scrollThumb:ClearAllPoints()
        self.scrollThumb:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", -1, yOff)
        self.scrollThumb:SetSize(4, thumbH)
        self.scrollThumb:Show()
    end

    function card:PaintPanel(pal)
        pal = pal or getPalette()
        self:PaintCard(pal)
        applyFont(self.titleFs, 12, "semibold")
        setTextColor(self.titleFs, pal.text)
        setTextColor(self.emptyFs, pal.textMuted)
        local s = pal.separator or { 1, 1, 1, 0.14 }
        self.headerSep:SetColorTexture(s[1], s[2], s[3], (s[4] or 0.4) * 0.50)
        self.scrollTrack:SetColorTexture(s[1], s[2], s[3], 0.18)
        local tm = pal.textMuted or { 0.6, 0.6, 0.65, 0.65 }
        self.scrollThumb:SetColorTexture(tm[1], tm[2], tm[3], 0.60)
    end

    return card
end

---------------------------------------------------------------------------------------------------
-- Main View Factory: ns.DashboardBrief.Create(parent, opts)
---------------------------------------------------------------------------------------------------
function Brief.Create(parent, opts)
    opts = opts or {}
    local T = ns.Theme
    local Chart = ns.Analytics and ns.Analytics.Chart

    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    local db = function() return type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or {} end
    local savedRange = db().dashboardBriefRange
    if not RANGE_DAYS[savedRange] then savedRange = "7d" end

    local state = {
        rangeKey = savedRange,
        mode = (db().dashboardMode == "classic") and "classic" or "brief",
        wealthMode = "auto", -- "auto" | "hourly" | "daily"
        effectiveWealthMode = "hourly",
        width = max(960, safeNum(parent and parent.GetWidth and parent:GetWidth(), 1080) or 1080),
        height = max(540, safeNum(parent and parent.GetHeight and parent:GetHeight(), 642) or 642),
        salesOffset = 0,
        alertsOffset = 0,
        visibleSalesRows = 8,
        visibleAlertRows = 6,
        visibleBestRows = 6,
        summary = nil,
        portfolio = nil,
        wealthSeries = nil,
        alerts = {},
        lastNowOverride = nil,
    }
    view._state = state

    local function openDeep(targetSpec)
        if not targetSpec then return end
        local fn = opts.onOpenDeepAnalysis or (ns.app and ns.app.openDeepAnalysis)
        if type(fn) == "function" then
            fn(targetSpec, { tab = "dashboard", mode = "brief" })
        end
    end

    local function addReagentToCart(itemID, qty, name)
        local id = safeNum(itemID, 0) or 0
        if id <= 0 then return false end
        local q = max(1, floor(safeNum(qty, 1) or 1))
        if type(opts.onAddToCart) == "function" then
            return opts.onAddToCart(id, q, name) ~= false
        end
        local cur = ns.app
        if cur and type(cur.addUnifiedShoppingItem) == "function" then
            cur.addUnifiedShoppingItem({
                key = "item:" .. tostring(id),
                name = name or resolveItemName(id),
                itemID = id,
                qty = q,
                demandList = { { itemID = id, qty = q, role = "Reagent Deal" } },
                sourceLabel = "Morning Brief",
            })
            return true
        end
        return false
    end

    -----------------------------------------------------------------------------------------------
    -- Row 0: Greeting Banner (height = 32)
    -----------------------------------------------------------------------------------------------
    local banner = CreateFrame("Frame", nil, view)
    banner:SetHeight(32)
    view.banner = banner

    local greetingFs = makeFS(banner, 15, "semibold", "LEFT")
    greetingFs:SetPoint("LEFT", banner, "LEFT", 2, 0)
    greetingFs:SetText(Brief.GetGreeting(nil, opts.getPlayerName and opts.getPlayerName()))
    view.greetingFs = greetingFs

    local metaPill = createBadgeFallback(banner, "Normal-Horde", "neutral", { height = 20, fontSize = 10, padX = 12 })
    metaPill.frame:SetPoint("LEFT", greetingFs, "RIGHT", 10, 0)
    view.metaPill = metaPill

    local modeSeg = createSegmentedFallback(banner, {
        { key = "brief",   label = "Morning Brief", width = 106 },
        { key = "classic", label = "Market Pulse",  width = 100 },
    }, {
        height = 26,
        fontSize = 11,
        activeKey = state.mode,
        onChange = function(k)
            state.mode = (k == "classic") and "classic" or "brief"
            if type(_G.MerchantMasterDB) == "table" then
                _G.MerchantMasterDB.dashboardMode = state.mode
            end
            if type(opts.onModeChange) == "function" then
                opts.onModeChange(state.mode)
            end
        end,
    })
    modeSeg.frame:SetPoint("RIGHT", banner, "RIGHT", -2, 0)
    view.modeSeg = modeSeg

    local rangeSeg = createSegmentedFallback(banner, {
        { key = "24h", label = "24h", width = 36 },
        { key = "7d",  label = "7d",  width = 34 },
        { key = "14d", label = "14d", width = 38 },
        { key = "30d", label = "30d", width = 38 },
    }, {
        height = 26,
        fontSize = 11,
        activeKey = state.rangeKey,
        onChange = function(k)
            if not RANGE_DAYS[k] then return end
            state.rangeKey = k
            if type(_G.MerchantMasterDB) == "table" then
                _G.MerchantMasterDB.dashboardBriefRange = k
            end
            if k == "24h" then
                state.wealthMode = "hourly"
            elseif state.wealthMode ~= "daily" then
                state.wealthMode = "auto"
            end
            view:Refresh(true)
        end,
    })
    rangeSeg.frame:SetPoint("RIGHT", modeSeg.frame, "LEFT", -8, 0)
    view.rangeSeg = rangeSeg

    -----------------------------------------------------------------------------------------------
    -- Row 1: 4 Executive KPI Cards (kpiH = 86..92, zero internal overlap)
    -----------------------------------------------------------------------------------------------
    local kpiToday = createCompactKpi(view, false)
    local kpiYesterday = createCompactKpi(view, false)
    local kpiWealth = createCompactKpi(view, true)
    local kpiBest = createCompactKpi(view, false)
    view.kpis = { kpiToday, kpiYesterday, kpiWealth, kpiBest }
    view.kpiToday = kpiToday
    view.kpiYesterday = kpiYesterday
    view.kpiWealth = kpiWealth
    view.kpiBest = kpiBest

    kpiToday.titleFs:SetText("TODAY'S PROFIT (AH)")
    kpiYesterday.titleFs:SetText("YESTERDAY'S PROFIT (AH)")
    kpiWealth.titleFs:SetText("TOTAL WEALTH")
    kpiBest.titleFs:SetText("BEST AH ITEM (7D)")

    -- Clickable KPI 4 -> Deep Analysis for #1 item
    local bestClickBtn = CreateFrame("Button", nil, kpiBest)
    bestClickBtn:SetAllPoints(kpiBest)
    bestClickBtn:SetScript("OnClick", function()
        local bi = state.summary and state.summary.bestItem
        if bi and bi.itemID and bi.itemID > 0 then
            openDeep({ kind = "item", itemID = bi.itemID, name = bi.name, icon = bi.icon })
        end
    end)
    bestClickBtn:SetScript("OnEnter", function(self)
        local bi = state.summary and state.summary.bestItem
        local bs = state.summary and state.summary.bestSingleSale
        if not (_G.GameTooltip and (bi or bs)) then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        _G.GameTooltip:AddLine("Best AH Performance (" .. tostring(state.rangeKey) .. ")", 1, 1, 1)
        if bi then
            _G.GameTooltip:AddDoubleLine("Top Earning Item", tostring(bi.name))
            _G.GameTooltip:AddDoubleLine("Net AH Profit", formatCopper(bi.profit, true))
            _G.GameTooltip:AddDoubleLine("Units Sold", tostring(bi.qty or 0))
        end
        if bs then
            _G.GameTooltip:AddDoubleLine("Best Single Sale", format("%s x%d (%s)", tostring(bs.name), bs.qty or 1, formatCopper(bs.profit, true)))
        end
        _G.GameTooltip:AddLine("Click to open Deep Analysis.", 0.65, 0.72, 0.80)
        _G.GameTooltip:Show()
    end)
    bestClickBtn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    kpiBest.clickBtn = bestClickBtn

    -----------------------------------------------------------------------------------------------
    -- Row 2: Side-by-Side Financial Charts (50/50)
    -----------------------------------------------------------------------------------------------
    local profitChart, wealthChart
    if Chart and type(Chart.CreateBarChart) == "function" then
        profitChart = Chart.CreateBarChart(view, 500, 176, {
            title = "Daily AH Profit (7d)",
            compact = true,
            emptyText = "No AH sales recorded in this period",
            preserveOrder = true,
        })
    else
        profitChart = createCardFrame(view, false)
        function profitChart:SetData() end
        function profitChart:Layout(w, h) self:SetSize(w, h) end
        function profitChart:ApplyTheme() self:PaintCard() end
    end
    view.profitChart = profitChart

    if Chart and type(Chart.CreateLineChart) == "function" then
        wealthChart = Chart.CreateLineChart(view, 500, 176, {
            title = "Total Wealth (Hourly)",
            compact = true,
            emptyText = "No wealth snapshots yet",
            preserveOrder = true,
        })
    else
        wealthChart = createCardFrame(view, false)
        function wealthChart:SetData() end
        function wealthChart:Layout(w, h) self:SetSize(w, h) end
        function wealthChart:ApplyTheme() self:PaintCard() end
    end
    view.wealthChart = wealthChart

    -- Inline Hourly | Daily toggle placed cleanly on the top-right of Wealth Chart header
    local wealthToggle = createSegmentedFallback(wealthChart, {
        { key = "hourly", label = "Hourly", width = 48 },
        { key = "daily",  label = "Daily",  width = 44 },
    }, {
        height = 20,
        fontSize = 10,
        activeKey = "hourly",
        onChange = function(k)
            state.wealthMode = (k == "daily") and "daily" or "hourly"
            view:Refresh(true)
        end,
    })
    wealthToggle.frame:ClearAllPoints()
    wealthToggle.frame:SetPoint("TOPRIGHT", wealthChart, "TOPRIGHT", -10, -7)
    if wealthChart.GetFrameLevel and wealthToggle.frame.SetFrameLevel then
        wealthToggle.frame:SetFrameLevel(wealthChart:GetFrameLevel() + 4)
    end
    view.wealthToggle = wealthToggle

    local function anchorWealthChartHeader()
        if not (wealthChart and wealthChart.summary and wealthToggle and wealthToggle.frame) then return end
        local cw = max(240, safeNum(wealthChart:GetWidth(), 500) or 500)
        local togW = max(92, safeNum(wealthToggle.frame:GetWidth(), 98) or 98)
        local sumW = max(72, min(140, floor((cw - togW - 36) * 0.34)))
        wealthChart.summary:ClearAllPoints()
        wealthChart.summary:SetPoint("RIGHT", wealthToggle.frame, "LEFT", -8, 0)
        wealthChart.summary:SetWidth(sumW)
        if wealthChart.title then
            wealthChart.title:ClearAllPoints()
            wealthChart.title:SetPoint("TOPLEFT", wealthChart, "TOPLEFT", 12, -9)
            wealthChart.title:SetPoint("TOPRIGHT", wealthChart.summary, "TOPLEFT", -8, 1)
        end
    end

    -----------------------------------------------------------------------------------------------
    -- Row 3: 3-Column Bottom Actionable Bento (36% / 34% / 30%)
    -----------------------------------------------------------------------------------------------
    -- Panel 1: Reagent Price-Drop Alerts (Your Top Crafts)
    local alertsPanel = createBentoPanel(view, "Reagent Price Drops")
    alertsPanel.emptyFs:SetText("No >=10% reagent price drops for your top crafts right now.")
    alertsPanel.rows = {}
    view.alertsPanel = alertsPanel

    local function paintAlertsRows()
        local pal = getPalette()
        local list = state.alerts or {}
        local vis = state.visibleAlertRows or 6
        local maxOff = max(0, #list - vis)
        state.alertsOffset = clamp(state.alertsOffset or 0, 0, maxOff)
        local bodyW = max(180, (safeNum(alertsPanel.body:GetWidth(), 340) or 340) - (maxOff > 0 and 8 or 0))
        local rowH = 38

        alertsPanel.emptyFs:SetShown(#list == 0)
        alertsPanel.badge:SetVariant(#list > 0 and "positive" or "neutral",
            #list > 0 and (tostring(#list) .. " deals") or "0 deals")
        alertsPanel:UpdateScrollThumb(#list, vis, state.alertsOffset)

        for i = 1, MAX_POOL_ROWS do
            local r = alertsPanel.rows[i]
            local item = (i <= vis) and list[state.alertsOffset + i] or nil
            if item then
                r._alert = item
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", alertsPanel.body, "TOPLEFT", 0, -(i - 1) * rowH)
                r:SetSize(bodyW, rowH - 2)
                if item.reagentIcon and r.icon then
                    r.icon:SetTexture(item.reagentIcon)
                    r.icon:Show()
                elseif r.icon then
                    r.icon:Hide()
                end
                local tag = item.isSuggested and " [Suggested]" or ""
                r.topFs:SetText(format("%s <- %s%s", tostring(item.recipeName or "Craft"), tostring(item.reagentName or "Reagent"), tag))
                r.subFs:SetText(format("%s -> %s (%.0f%%) x%d",
                    formatCopper(item.baselineUnit, false),
                    formatCopper(item.curUnit, false),
                    item.dropPct or 0,
                    item.reagentQty or 1))
                r.saveFs:SetText("-" .. formatCopper(item.craftSaved, false) .. " cost")
                setTextColor(r.topFs, pal.text)
                setTextColor(r.subFs, pal.textSecondary)
                setTextColor(r.saveFs, pal.accentGreen)
                local s = pal.separator or { 1, 1, 1, 0.12 }
                r.sep:SetColorTexture(s[1], s[2], s[3], (s[4] or 0.4) * 0.35)
                r:Show()
            else
                r._alert = nil
                r:Hide()
            end
        end
    end

    for i = 1, MAX_POOL_ROWS do
        local row = CreateFrame("Button", nil, alertsPanel.body)
        if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:Hide()
        row.hl = hl

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.icon = icon

        local saveFs = makeFS(row, 11, "semibold", "RIGHT")
        saveFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
        saveFs:SetWidth(92)
        row.saveFs = saveFs

        local topFs = makeFS(row, 11, "semibold", "LEFT")
        topFs:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -3)
        topFs:SetPoint("TOPRIGHT", saveFs, "TOPLEFT", -6, -3)
        row.topFs = topFs

        local subFs = makeFS(row, 10, "regular", "LEFT")
        subFs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 32, 4)
        subFs:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 4)
        row.subFs = subFs

        local sep = row:CreateTexture(nil, "BORDER")
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
        sep:SetHeight(1)
        row.sep = sep

        row:SetScript("OnEnter", function(self)
            local pal = getPalette()
            local hv = pal.rowHover or { 1, 1, 1, 0.07 }
            self.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4] or 0.07)
            self.hl:Show()
            local a = self._alert
            if not (_G.GameTooltip and a) then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:AddLine(tostring(a.recipeName) .. " <- " .. tostring(a.reagentName), 1, 1, 1)
            _G.GameTooltip:AddDoubleLine("Baseline -> Now", format("%s -> %s (%.1f%%)",
                formatCopper(a.baselineUnit, false), formatCopper(a.curUnit, false), a.dropPct or 0))
            _G.GameTooltip:AddDoubleLine("Craft Savings (x" .. tostring(a.reagentQty) .. ")",
                "-" .. formatCopper(a.craftSaved, false) .. " cost (+" .. formatCopper(a.craftSaved, false) .. "/craft)")
            _G.GameTooltip:AddLine("Left-Click: Recipe Deep Analysis", 0.65, 0.78, 0.95)
            _G.GameTooltip:AddLine("Right-Click: Reagent Deep Analysis", 0.65, 0.78, 0.95)
            _G.GameTooltip:AddLine("Shift-Click: Add Reagent to Cart", 0.45, 0.90, 0.55)
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self, button)
            local a = self._alert
            if not a then return end
            if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
                if addReagentToCart(a.reagentID, a.reagentQty, a.reagentName) then
                    self.saveFs:SetText("Added x" .. tostring(a.reagentQty))
                end
                return
            end
            if button == "RightButton" then
                openDeep({ kind = "item", itemID = a.reagentID, name = a.reagentName, icon = a.reagentIcon })
            else
                openDeep({
                    kind = "recipe",
                    recipe = a.recipe,
                    spellID = a.spellID,
                    itemID = a.outputItemID,
                    name = a.recipeName,
                })
            end
        end)
        row:Hide()
        alertsPanel.rows[i] = row
    end

    if alertsPanel.body.EnableMouseWheel then alertsPanel.body:EnableMouseWheel(true) end
    alertsPanel.body:SetScript("OnMouseWheel", function(_, delta)
        alertsPanel:ScrollBy(-(delta or 0))
    end)
    function alertsPanel:ScrollBy(delta)
        state.alertsOffset = (state.alertsOffset or 0) + (delta or 0)
        paintAlertsRows()
    end
    function alertsPanel:SetScrollOffset(off)
        state.alertsOffset = floor(safeNum(off, 0) or 0)
        paintAlertsRows()
    end

    -- Panel 2: Scrollable Recent AH Sales Log (Strict AH_SELL ONLY, <= 50 rows)
    local salesPanel = createBentoPanel(view, "Recent AH Sales")
    salesPanel.emptyFs:SetText("No AH sales recorded in the last 30 days.")
    salesPanel.rows = {}
    view.salesPanel = salesPanel

    local function paintSalesRows()
        local pal = getPalette()
        local list = (state.summary and state.summary.recentSales) or {}
        local vis = state.visibleSalesRows or 8
        local maxOff = max(0, #list - vis)
        state.salesOffset = clamp(state.salesOffset or 0, 0, maxOff)
        local bodyW = max(180, (safeNum(salesPanel.body:GetWidth(), 320) or 320) - (maxOff > 0 and 8 or 0))
        local rowH = 28
        local todayKey = state.summary and state.summary.todayKey or dayKeyFromSec(nowSec(state.lastNowOverride))

        salesPanel.emptyFs:SetShown(#list == 0)
        if #list == 0 then
            salesPanel.badge:SetVariant("neutral", "0 sales")
        elseif maxOff > 0 then
            local lo = state.salesOffset + 1
            local hi = min(#list, state.salesOffset + vis)
            salesPanel.badge:SetVariant("neutral", format("%d-%d / %d", lo, hi, #list))
        else
            salesPanel.badge:SetVariant("neutral", format("%d sales", #list))
        end
        salesPanel:UpdateScrollThumb(#list, vis, state.salesOffset)

        for i = 1, MAX_POOL_ROWS do
            local r = salesPanel.rows[i]
            local sale = (i <= vis) and list[state.salesOffset + i] or nil
            if sale then
                r._sale = sale
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", salesPanel.body, "TOPLEFT", 0, -(i - 1) * rowH)
                r:SetSize(bodyW, rowH - 1)
                if sale.icon and r.icon then
                    r.icon:SetTexture(sale.icon)
                    r.icon:Show()
                elseif r.icon then
                    r.icon:Hide()
                end
                local qtySuffix = (sale.qty and sale.qty > 1) and (" x" .. tostring(sale.qty)) or ""
                r.nameFs:SetText(tostring(sale.name or "Item") .. qtySuffix)
                local whenText
                if sale.day == todayKey and (sale.time or 0) > 0 then
                    whenText = fmtDate("%H:%M", sale.time)
                elseif type(sale.day) == "string" and #sale.day >= 10 then
                    whenText = sale.day:sub(6)
                else
                    whenText = "-"
                end
                r.whenFs:SetText(whenText)
                r.profitFs:SetText(formatCopper(sale.profit, true))
                setTextColor(r.nameFs, pal.text)
                setTextColor(r.whenFs, pal.textMuted)
                setTextColor(r.profitFs, (sale.profit or 0) > 0 and pal.accentGreen
                    or ((sale.profit or 0) < 0 and pal.accentRed or pal.textSecondary))
                local s = pal.separator or { 1, 1, 1, 0.12 }
                r.sep:SetColorTexture(s[1], s[2], s[3], (s[4] or 0.4) * 0.30)
                r:Show()
            else
                r._sale = nil
                r:Hide()
            end
        end
    end

    for i = 1, MAX_POOL_ROWS do
        local row = CreateFrame("Button", nil, salesPanel.body)
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:Hide()
        row.hl = hl

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.icon = icon

        local profitFs = makeFS(row, 11, "semibold", "RIGHT")
        profitFs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        profitFs:SetWidth(74)
        row.profitFs = profitFs

        local whenFs = makeFS(row, 10, "regular", "RIGHT")
        whenFs:SetPoint("RIGHT", profitFs, "LEFT", -6, 0)
        whenFs:SetWidth(40)
        row.whenFs = whenFs

        local nameFs = makeFS(row, 11, "regular", "LEFT")
        nameFs:SetPoint("LEFT", row, "LEFT", 26, 0)
        nameFs:SetPoint("RIGHT", whenFs, "LEFT", -6, 0)
        row.nameFs = nameFs

        local sep = row:CreateTexture(nil, "BORDER")
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
        sep:SetHeight(1)
        row.sep = sep

        row:SetScript("OnEnter", function(self)
            local pal = getPalette()
            local hv = pal.rowHover or { 1, 1, 1, 0.07 }
            self.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4] or 0.07)
            self.hl:Show()
            local s = self._sale
            if not (_G.GameTooltip and s) then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:AddLine(format("%s x%d", tostring(s.name), s.qty or 1), 1, 1, 1)
            _G.GameTooltip:AddDoubleLine("Gross", formatCopper(s.gross, false))
            _G.GameTooltip:AddDoubleLine("AH Cut", "-" .. formatCopper(s.fee, false))
            _G.GameTooltip:AddDoubleLine("COGS", "-" .. formatCopper(s.cogs, false))
            _G.GameTooltip:AddDoubleLine("Net Profit", formatCopper(s.profit, true))
            _G.GameTooltip:AddLine("Click to open Deep Analysis.", 0.65, 0.78, 0.95)
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            local s = self._sale
            if s and s.itemID and s.itemID > 0 then
                openDeep({ kind = "item", itemID = s.itemID, name = s.name, icon = s.icon })
            end
        end)
        row:Hide()
        salesPanel.rows[i] = row
    end

    if salesPanel.body.EnableMouseWheel then salesPanel.body:EnableMouseWheel(true) end
    salesPanel.body:SetScript("OnMouseWheel", function(_, delta)
        salesPanel:ScrollBy(-(delta or 0))
    end)
    function salesPanel:ScrollBy(delta)
        state.salesOffset = (state.salesOffset or 0) + (delta or 0)
        paintSalesRows()
    end
    function salesPanel:SetScrollOffset(off)
        state.salesOffset = floor(safeNum(off, 0) or 0)
        paintSalesRows()
    end
    function salesPanel:GetScrollOffset()
        return state.salesOffset or 0
    end

    -- Panel 3: Best Items & Best Single Sale
    local bestPanel = createBentoPanel(view, "Best AH Items")
    bestPanel.emptyFs:SetText("No AH sales in this period.")
    bestPanel.rows = {}
    view.bestPanel = bestPanel

    local bestSaleStrip = CreateFrame("Button", nil, bestPanel.body)
    bestSaleStrip:SetPoint("TOPLEFT", bestPanel.body, "TOPLEFT", 2, -2)
    bestSaleStrip:SetPoint("TOPRIGHT", bestPanel.body, "TOPRIGHT", -2, -2)
    bestSaleStrip:SetHeight(42)
    bestSaleStrip.bg = bestSaleStrip:CreateTexture(nil, "BACKGROUND")
    bestSaleStrip.bg:SetAllPoints()
    bestSaleStrip.kickerFs = makeFS(bestSaleStrip, 9, "semibold", "LEFT")
    bestSaleStrip.kickerFs:SetPoint("TOPLEFT", bestSaleStrip, "TOPLEFT", 8, -5)
    bestSaleStrip.kickerFs:SetText("BEST SINGLE AH SALE")
    bestSaleStrip.profitFs = makeFS(bestSaleStrip, 12, "semibold", "RIGHT")
    bestSaleStrip.profitFs:SetPoint("BOTTOMRIGHT", bestSaleStrip, "BOTTOMRIGHT", -8, 6)
    bestSaleStrip.profitFs:SetWidth(84)
    bestSaleStrip.itemFs = makeFS(bestSaleStrip, 11, "semibold", "LEFT")
    bestSaleStrip.itemFs:SetPoint("BOTTOMLEFT", bestSaleStrip, "BOTTOMLEFT", 8, 6)
    bestSaleStrip.itemFs:SetPoint("BOTTOMRIGHT", bestSaleStrip.profitFs, "BOTTOMLEFT", -6, 6)
    bestSaleStrip:SetScript("OnClick", function()
        local bs = state.summary and state.summary.bestSingleSale
        if bs and bs.itemID and bs.itemID > 0 then
            openDeep({ kind = "item", itemID = bs.itemID, name = bs.name, icon = bs.icon })
        end
    end)
    bestPanel.bestSaleStrip = bestSaleStrip

    local function paintBestRows()
        local pal = getPalette()
        local sum = state.summary
        local list = (sum and sum.topItems) or {}
        local bs = sum and sum.bestSingleSale
        local vis = state.visibleBestRows or 6
        local bodyW = max(160, safeNum(bestPanel.body:GetWidth(), 290) or 290)
        local rowH = 30
        local listTop = 48

        bestPanel.badge:SetVariant("neutral", tostring(state.rangeKey))

        local accG = pal.accentGreen or { 0.19, 0.82, 0.35, 1 }
        bestSaleStrip.bg:SetColorTexture(accG[1], accG[2], accG[3], pal.mode == "light" and 0.12 or 0.14)
        setTextColor(bestSaleStrip.kickerFs, pal.textSecondary)
        if bs then
            bestSaleStrip.itemFs:SetText(format("%s x%d", tostring(bs.name or "Item"), bs.qty or 1))
            bestSaleStrip.profitFs:SetText(formatCopper(bs.profit, true))
            setTextColor(bestSaleStrip.itemFs, pal.text)
            setTextColor(bestSaleStrip.profitFs, (bs.profit or 0) >= 0 and pal.accentGreen or pal.accentRed)
            bestSaleStrip:Show()
        else
            bestSaleStrip.itemFs:SetText("No single AH sale yet")
            bestSaleStrip.profitFs:SetText("-")
            setTextColor(bestSaleStrip.itemFs, pal.textMuted)
            setTextColor(bestSaleStrip.profitFs, pal.textMuted)
            bestSaleStrip:Show()
        end

        bestPanel.emptyFs:SetShown(#list == 0)
        for i = 1, MAX_POOL_ROWS do
            local r = bestPanel.rows[i]
            local it = (i <= vis) and list[i] or nil
            if it then
                r._item = it
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", bestPanel.body, "TOPLEFT", 0, -listTop - (i - 1) * rowH)
                r:SetSize(bodyW, rowH - 2)
                if it.icon and r.icon then
                    r.icon:SetTexture(it.icon)
                    r.icon:Show()
                elseif r.icon then
                    r.icon:Hide()
                end
                r.nameFs:SetText(format("%d. %s", i, tostring(it.name or "Item")))
                r.valFs:SetText(format("%s (%d)", formatCopper(it.profit, true), it.qty or 0))
                setTextColor(r.nameFs, pal.text)
                setTextColor(r.valFs, (it.profit or 0) >= 0 and pal.accentGreen or pal.accentRed)
                local barTrackW = max(24, bodyW - 32)
                local fillW = max(4, floor(barTrackW * (it.shareRatio or 0.1) + 0.5))
                local s = pal.separator or { 1, 1, 1, 0.14 }
                r.barTrack:SetColorTexture(s[1], s[2], s[3], 0.22)
                local barCol = (it.profit or 0) >= 0 and (pal.accentGreen or accG) or (pal.accentRed or { 1, 0.27, 0.23, 1 })
                r.barFill:SetColorTexture(barCol[1], barCol[2], barCol[3], 0.85)
                r.barFill:SetSize(fillW, 3)
                r:Show()
            else
                r._item = nil
                r:Hide()
            end
        end
    end

    for i = 1, MAX_POOL_ROWS do
        local row = CreateFrame("Button", nil, bestPanel.body)
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:Hide()
        row.hl = hl

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
        row.icon = icon

        local valFs = makeFS(row, 11, "semibold", "RIGHT")
        valFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
        valFs:SetWidth(94)
        row.valFs = valFs

        local nameFs = makeFS(row, 11, "regular", "LEFT")
        nameFs:SetPoint("TOPLEFT", row, "TOPLEFT", 26, -4)
        nameFs:SetPoint("TOPRIGHT", valFs, "TOPLEFT", -6, -4)
        row.nameFs = nameFs

        local barTrack = row:CreateTexture(nil, "BORDER")
        barTrack:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 26, 3)
        barTrack:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 3)
        barTrack:SetHeight(3)
        row.barTrack = barTrack

        local barFill = row:CreateTexture(nil, "ARTWORK")
        barFill:SetPoint("BOTTOMLEFT", barTrack, "BOTTOMLEFT", 0, 0)
        barFill:SetSize(20, 3)
        row.barFill = barFill

        row:SetScript("OnEnter", function(self)
            local pal = getPalette()
            local hv = pal.rowHover or { 1, 1, 1, 0.07 }
            self.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4] or 0.07)
            self.hl:Show()
        end)
        row:SetScript("OnLeave", function(self) self.hl:Hide() end)
        row:SetScript("OnClick", function(self)
            local it = self._item
            if it and it.itemID and it.itemID > 0 then
                openDeep({ kind = "item", itemID = it.itemID, name = it.name, icon = it.icon })
            end
        end)
        row:Hide()
        bestPanel.rows[i] = row
    end

    -----------------------------------------------------------------------------------------------
    -- Responsive Layout Engine (1036x612 Goblin Min .. 1600x642 .. 2296x1328 1440p)
    -----------------------------------------------------------------------------------------------
    function view:Layout(w, h)
        local W = max(960, floor(safeNum(w, safeNum(self:GetWidth(), state.width)) or 1080))
        local H = max(540, floor(safeNum(h, safeNum(self:GetHeight(), state.height)) or 642))
        state.width, state.height = W, H
        self:SetSize(W, H)

        local gap = (H >= 900) and 12 or ((H >= 750) and 10 or 8)
        local bannerH = 32
        local kpiH = (H >= 1000) and 92 or 86
        local chartH = clamp(floor(H * 0.27), 168, 320)
        local bottomH = max(180, H - bannerH - kpiH - chartH - 3 * gap)

        -- Row 0: Greeting Banner
        banner:ClearAllPoints()
        banner:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        banner:SetSize(W, bannerH)

        -- Row 1: 4 Equal Executive KPI Cards
        local kpiY = -(bannerH + gap)
        local baseKpiW = floor((W - 3 * gap) / 4)
        for idx = 1, 4 do
            local card = view.kpis[idx]
            local cw = (idx == 4) and (W - 3 * (baseKpiW + gap)) or baseKpiW
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", self, "TOPLEFT", (idx - 1) * (baseKpiW + gap), kpiY)
            card:SetSize(cw, kpiH)
        end
        if kpiWealth.wealthBar and kpiWealth.wealthBar._ratios then
            local r = kpiWealth.wealthBar._ratios
            kpiWealth:SetWealthRatios(r.g, r.it, r.li)
        end

        -- Row 2: Side-by-Side Charts (50/50)
        local chartY = kpiY - kpiH - gap
        local leftChartW = floor((W - gap) / 2)
        local rightChartW = W - gap - leftChartW

        profitChart:ClearAllPoints()
        profitChart:SetPoint("TOPLEFT", self, "TOPLEFT", 0, chartY)
        profitChart:SetSize(leftChartW, chartH)
        if profitChart.Layout then profitChart:Layout(leftChartW, chartH) end

        wealthChart:ClearAllPoints()
        wealthChart:SetPoint("TOPLEFT", self, "TOPLEFT", leftChartW + gap, chartY)
        wealthChart:SetSize(rightChartW, chartH)
        if wealthChart.Layout then wealthChart:Layout(rightChartW, chartH) end
        anchorWealthChartHeader()

        -- Row 3: 3-Column Bottom Actionable Bento (36% / 34% / 30%)
        local bottomY = chartY - chartH - gap
        local availW = W - 2 * gap
        local col1W = floor(availW * 0.36)
        local col2W = floor(availW * 0.34)
        local col3W = availW - col1W - col2W

        alertsPanel:ClearAllPoints()
        alertsPanel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, bottomY)
        alertsPanel:SetSize(col1W, bottomH)
        alertsPanel.body:SetSize(max(120, col1W - 12), max(100, bottomH - 41))

        salesPanel:ClearAllPoints()
        salesPanel:SetPoint("TOPLEFT", self, "TOPLEFT", col1W + gap, bottomY)
        salesPanel:SetSize(col2W, bottomH)
        salesPanel.body:SetSize(max(120, col2W - 12), max(100, bottomH - 41))

        bestPanel:ClearAllPoints()
        bestPanel:SetPoint("TOPLEFT", self, "TOPLEFT", col1W + col2W + 2 * gap, bottomY)
        bestPanel:SetSize(col3W, bottomH)
        bestPanel.body:SetSize(max(120, col3W - 12), max(100, bottomH - 41))

        local bodyH = max(100, bottomH - 41)
        state.visibleAlertRows = clamp(floor(bodyH / 38), 6, MAX_POOL_ROWS)
        state.visibleSalesRows = clamp(floor(bodyH / 28), 6, MAX_POOL_ROWS)
        state.visibleBestRows = clamp(floor(max(60, bodyH - 48) / 30), 6, MAX_POOL_ROWS)

        view._geometry = {
            W = W, H = H, gap = gap,
            bannerH = bannerH,
            kpiY = kpiY, kpiH = kpiH,
            chartY = chartY, chartH = chartH, leftChartW = leftChartW, rightChartW = rightChartW,
            bottomY = bottomY, bottomH = bottomH, col1W = col1W, col2W = col2W, col3W = col3W,
        }

        paintAlertsRows()
        paintSalesRows()
        paintBestRows()
    end

    -----------------------------------------------------------------------------------------------
    -- Theme & Skin Repaint (Dark, Light, and all 5 Warcraft Skins)
    -----------------------------------------------------------------------------------------------
    function view:ApplyTheme()
        local pal = getPalette()
        applyFont(greetingFs, 15, "semibold")
        setTextColor(greetingFs, pal.text)
        if modeSeg and modeSeg.UpdateTheme then modeSeg:UpdateTheme() end
        if rangeSeg and rangeSeg.UpdateTheme then rangeSeg:UpdateTheme() end
        if wealthToggle and wealthToggle.UpdateTheme then wealthToggle:UpdateTheme() end
        for _, card in ipairs(view.kpis) do
            card:PaintKpi(pal)
        end
        if profitChart and profitChart.ApplyTheme then profitChart:ApplyTheme() end
        if wealthChart and wealthChart.ApplyTheme then wealthChart:ApplyTheme() end
        anchorWealthChartHeader()
        alertsPanel:PaintPanel(pal)
        salesPanel:PaintPanel(pal)
        bestPanel:PaintPanel(pal)
        paintAlertsRows()
        paintSalesRows()
        paintBestRows()
    end

    -----------------------------------------------------------------------------------------------
    -- Full Data Refresh
    -----------------------------------------------------------------------------------------------
    function view:Refresh(force, nowOverride)
        if force then Brief.InvalidateCache() end
        state.lastNowOverride = nowOverride
        local now = nowSec(nowOverride)
        local econKey = resolveEconKey(opts.getEconKey and opts.getEconKey())
        local pal = getPalette()

        greetingFs:SetText(Brief.GetGreeting(nil, opts.getPlayerName and opts.getPlayerName()))
        local freshness = (type(opts.getFreshnessText) == "function" and opts.getFreshnessText())
            or ((ns.Pricing and ns.Pricing.GetSnapshotFreshnessLabel and ns.Pricing.GetSnapshotFreshnessLabel(econKey)) or "Live")
        metaPill:SetVariant("neutral", econKey .. " | " .. tostring(freshness))

        local summary = Brief.ComputeAHSalesSummary(econKey, state.rangeKey, now)
        local portfolio = readPortfolio(econKey, state.rangeKey)
        local wealthSeries = Brief.BuildWealthChartSeries(state.wealthMode, state.rangeKey, econKey, portfolio, now)
        local alerts = Brief.ComputeReagentPriceDrops(econKey, now, summary, opts.getPriceBank and opts.getPriceBank())

        state.summary = summary
        state.portfolio = portfolio
        state.wealthSeries = wealthSeries
        state.effectiveWealthMode = wealthSeries.mode
        state.alerts = alerts

        -- Sync wealth toggle silently
        if wealthToggle and wealthToggle.SetActive then
            wealthToggle:SetActive(wealthSeries.mode, true)
        end

        -- KPI 1: Today's Profit (Running, AH_SELL only)
        kpiToday.valueFs:SetText(formatCopper(summary.todayProfit, true))
        kpiToday._valueColorKey = summary.todayProfit > 0 and "accentGreen"
            or (summary.todayProfit < 0 and "accentRed" or "text")
        kpiToday.subFs:SetText(summary.todaySalesCount > 0
            and format("%d AH %s today", summary.todaySalesCount, summary.todaySalesCount == 1 and "sale" or "sales")
            or "No AH sales yet today")

        -- KPI 2: Yesterday's Profit (AH_SELL only + % vs 7d completed-day avg)
        kpiYesterday.valueFs:SetText(formatCopper(summary.yesterdayProfit, true))
        kpiYesterday._valueColorKey = summary.yesterdayProfit > 0 and "accentGreen"
            or (summary.yesterdayProfit < 0 and "accentRed" or "text")
        if summary.yesterdayDeltaPct ~= nil then
            kpiYesterday.subFs:SetText(format("%+.1f%% vs 7d avg (%s)",
                summary.yesterdayDeltaPct, formatCopper(summary.avg7dCompleted, false)))
            kpiYesterday._subColorKey = summary.yesterdayDeltaPct >= 0 and "accentGreen" or "accentRed"
        else
            kpiYesterday.subFs:SetText("No 7d avg")
            kpiYesterday._subColorKey = "textMuted"
        end

        -- KPI 3: Total Wealth + 3-segment breakdown bar + 24h delta
        local latestTotal = wealthSeries.latestTotal or portfolio.latestTotal or 0
        local latestGold = safeNum(portfolio.latestGold, 0) or 0
        local latestItems = safeNum(portfolio.latestItems, 0) or 0
        local latestListed = safeNum(portfolio.latestListed, 0) or 0
        if latestGold == 0 and latestItems == 0 and latestListed == 0 and latestTotal > 0 then
            latestGold = latestTotal
        end
        kpiWealth.valueFs:SetText(formatCopper(latestTotal, false))
        kpiWealth._valueColorKey = "text"
        kpiWealth:SetWealthRatios(latestGold, latestItems, latestListed)
        local totForPct = max(1, latestGold + latestItems + latestListed)
        local gPct = floor((latestGold / totForPct) * 100 + 0.5)
        local iPct = floor((latestItems / totForPct) * 100 + 0.5)
        local lPct = max(0, 100 - gPct - iPct)
        kpiWealth.subFs:SetText(format("24h %s | G %d%% / Inv %d%% / AH %d%%",
            formatCopper(wealthSeries.change24h or 0, true), gPct, iPct, lPct))
        kpiWealth._subColorKey = (wealthSeries.change24h or 0) > 0 and "accentGreen"
            or ((wealthSeries.change24h or 0) < 0 and "accentRed" or "textSecondary")

        -- KPI 4: Best Item / Best Sale
        kpiBest.titleFs:SetText("BEST AH ITEM (" .. tostring(state.rangeKey):upper() .. ")")
        if summary.bestItem then
            kpiBest.valueFs:SetText(tostring(summary.bestItem.name))
            kpiBest._valueColorKey = "text"
            local bsPart = summary.bestSingleSale
                and (" | Top: " .. formatCopper(summary.bestSingleSale.profit, true))
                or ""
            kpiBest.subFs:SetText(formatCopper(summary.bestItem.profit, true) .. bsPart)
            kpiBest._subColorKey = (summary.bestItem.profit or 0) >= 0 and "accentGreen" or "accentRed"
        else
            kpiBest.valueFs:SetText("No AH sales")
            kpiBest._valueColorKey = "textMuted"
            kpiBest.subFs:SetText("Post & sell on AH to track")
            kpiBest._subColorKey = "textMuted"
        end

        for _, card in ipairs(view.kpis) do
            card:PaintKpi(pal)
        end

        -- Left Chart: Profit Bar Chart
        local profitTitle = (state.rangeKey == "24h")
            and "AH Profit (Hourly)"
            or ("Daily AH Profit (" .. tostring(state.rangeKey) .. ")")
        profitChart:SetData(summary.profitBars, {
            title = profitTitle,
            preserveOrder = true,
            summary = formatCopper(summary.rangeTotalProfit, true),
        })

        -- Right Chart: Wealth Line Chart (Hourly or Daily)
        local wealthTitle = (wealthSeries.mode == "hourly")
            and (wealthSeries.usedFallback and "Total Wealth (Hourly Est.)" or "Total Wealth (Hourly)")
            or ("Total Wealth (" .. tostring(state.rangeKey) .. ")")
        wealthChart:SetData({
            {
                name = "Total Wealth",
                colorKey = "blue",
                points = wealthSeries.points,
            },
        }, {
            title = wealthTitle,
            preserveOrder = true,
            summary = formatCopper(wealthSeries.change24h or 0, true),
        })
        anchorWealthChartHeader()

        paintAlertsRows()
        paintSalesRows()
        paintBestRows()
    end

    function view:SetMode(mode, silent)
        state.mode = (mode == "classic") and "classic" or "brief"
        if modeSeg and modeSeg.SetActive then
            modeSeg:SetActive(state.mode, silent ~= false)
        end
    end

    function view:SetRange(rangeKey, silent)
        if not RANGE_DAYS[rangeKey] then return end
        state.rangeKey = rangeKey
        if type(_G.MerchantMasterDB) == "table" then
            _G.MerchantMasterDB.dashboardBriefRange = rangeKey
        end
        if rangeSeg and rangeSeg.SetActive then
            rangeSeg:SetActive(rangeKey, silent == true)
        elseif not silent then
            self:Refresh(true)
        end
    end

    function view:SetWealthMode(mode, silent)
        state.wealthMode = (mode == "daily" or mode == "hourly") and mode or "auto"
        if wealthToggle and wealthToggle.SetActive and (mode == "daily" or mode == "hourly") then
            wealthToggle:SetActive(mode, silent == true)
        elseif not silent then
            self:Refresh(true)
        end
    end

    function view:Invalidate()
        Brief.InvalidateCache()
    end

    function view:GetState()
        return state
    end

    if T and type(T.RegisterWidget) == "function" then
        T.RegisterWidget(view, function() view:ApplyTheme() end)
    end

    if ns.Watchlist and type(ns.Watchlist.RegisterListener) == "function" then
        ns.Watchlist.RegisterListener(function()
            Brief.InvalidateCache()
            if view:IsShown() then view:Refresh(false) end
        end)
    end

    view:Layout(state.width, state.height)
    view:ApplyTheme()
    return view
end
