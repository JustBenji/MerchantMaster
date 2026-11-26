-- Verification suite for Feature F: Morning Brief Dashboard + Hourly Wealth + 1440p Support
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, _, hostEnv = dofile(testsDir .. "host_fixture.lua")
local check = hostEnv.check
local addonDir = hostEnv.addonDir

-- Load UI_DashboardBrief.lua cleanly whether or not TOC already includes it
if not ns.DashboardBrief then
    local chunk, err = loadfile(addonDir .. "UI_DashboardBrief.lua")
    assert(chunk, "load UI_DashboardBrief.lua failed: " .. tostring(err))
    chunk("MerchantMaster", ns)
end

local Brief = ns.DashboardBrief
local Store = ns.Analytics and ns.Analytics.Store
local Model = ns.Analytics and ns.Analytics.Model
local Theme = ns.Theme
local Window = ns.Window
check(type(Brief) == "table", "ns.DashboardBrief loaded")
check(type(Store) == "table", "Analytics.Store available")
check(type(Model) == "table", "Analytics.Model available")

local ECON = "Normal-Horde"
local CHAR_MAIN = "Normal-Horde-Forever-Thrall Ironfist"
local CHAR_ALT = "Normal-Horde-Forever-Banker Bob"
local CHAR_OTHER_ECON = "PvP-Alliance-Forever-Varian Wrynn"

-- Base timestamp: noon UTC on a deterministic day
local BASE_NOW = 1794400000
local DAY_SEC = 86400
local function dayOffset(offsetDays, hourOfDay)
    local baseDayStart = math.floor(BASE_NOW / DAY_SEC) * DAY_SEC
    return baseDayStart + offsetDays * DAY_SEC + (hourOfDay or 12) * 3600
end

local function resetLedger()
    _G.MerchantMasterLedgerDB = {}
    Store.Init()
    Brief.InvalidateCache()
    if Model and Model.Invalidate then Model.Invalidate() end
end

---------------------------------------------------------------------------------------------------
-- 1. Hourly Wealth Snapshot Recording (Store.SaveSnapshot: alt carry-forward, 7d prune, migration, bytes)
---------------------------------------------------------------------------------------------------
do
    resetLedger()
    local bytesEmpty = Store.EstimateBytes()
    local tDay0 = dayOffset(0, 8)
    local d0 = Store.DayKey(tDay0)

    -- Main logs in at 08:00 with 100g (1,000,000c)
    hostEnv.setFixtureNow(tDay0)
    Store.SaveSnapshot(CHAR_MAIN, d0, { gold = 600000, items = 250000, listed = 150000, econ = ECON, time = tDay0 })

    -- Alt logs in at 10:00 with 40g (400,000c) -> MUST carry forward Main's 100g!
    local tDay0H10 = dayOffset(0, 10)
    hostEnv.setFixtureNow(tDay0H10)
    Store.SaveSnapshot(CHAR_ALT, d0, { gold = 300000, items = 100000, listed = 0, econ = ECON, time = tDay0H10 })

    -- Another economy character logs in at 10:00 too
    Store.SaveSnapshot(CHAR_OTHER_ECON, d0, { gold = 900000, items = 0, listed = 0, econ = "PvP-Alliance", time = tDay0H10 })

    -- Main logs back in at 14:00 with 120g -> MUST carry forward Alt's 40g!
    local tDay0H14 = dayOffset(0, 14)
    hostEnv.setFixtureNow(tDay0H14)
    Store.SaveSnapshot(CHAR_MAIN, d0, { gold = 800000, items = 250000, listed = 150000, econ = ECON, time = tDay0H14 })

    local h10Key = string.format("%02d", tonumber(os.date("%H", tDay0H10)) or 10)
    local h14Key = string.format("%02d", tonumber(os.date("%H", tDay0H14)) or 14)
    local intraday = Store.IntradaySnaps()
    check(type(intraday[d0]) == "table" and type(intraday[d0].points) == "table", "intradaySnaps day bucket created")
    local pt10 = intraday[d0].points[h10Key]
    check(type(pt10) == "table" and type(pt10.chars) == "table", "hour 10 intraday point recorded")
    check(pt10.chars[CHAR_ALT] and pt10.chars[CHAR_ALT].gold == 300000, "alt snapshot saved in intraday point")
    check(pt10.chars[CHAR_MAIN] and pt10.chars[CHAR_MAIN].gold == 600000, "main carried forward when alt logs in")
    local pt14 = intraday[d0].points[h14Key]
    check(pt14 and pt14.chars[CHAR_MAIN] and pt14.chars[CHAR_MAIN].gold == 800000, "main updated at hour 14")
    check(pt14 and pt14.chars[CHAR_ALT] and pt14.chars[CHAR_ALT].gold == 300000, "alt carried forward at hour 14")

    -- EstimateBytes includes intradaySnaps
    local bytesWithIntraday = Store.EstimateBytes()
    check(bytesWithIntraday > bytesEmpty + 200, "EstimateBytes accounts for intradaySnaps")

    -- Hourly wealth series filters by econ (excludes PvP-Alliance!) and sums Main + Alt
    local wHourly = Brief.BuildWealthChartSeries("hourly", "24h", ECON, nil, tDay0H14)
    check(wHourly.mode == "hourly" and wHourly.usedFallback == false, "uses real intradaySnaps hourly series")
    check(#wHourly.points == 3, "3 hourly points recorded across 08/10/14 (got " .. tostring(#wHourly.points) .. ")")
    check(wHourly.points[1].value == 1000000, "08:00 total = 100g (Main only before Alt logged)")
    check(wHourly.points[2].value == 1400000, "10:00 total = 140g (Main 100g + Alt 40g, excluding PvP-Alliance)")
    check(wHourly.points[3].value == 1600000, "14:00 total = 160g (Main 120g + Alt 40g)")

    -- 7-day pruning: save 10 distinct days -> only newest 7 survive
    for dIdx = 1, 9 do
        local ts = dayOffset(dIdx, 12)
        local dk = Store.DayKey(ts)
        hostEnv.setFixtureNow(ts)
        Store.SaveSnapshot(CHAR_MAIN, dk, { gold = 800000 + dIdx * 10000, items = 250000, listed = 150000, econ = ECON, time = ts })
    end
    local countDays = 0
    for _ in pairs(Store.IntradaySnaps()) do countDays = countDays + 1 end
    check(countDays == 7, "intradaySnaps pruned to newest 7 days (got " .. tostring(countDays) .. ")")
    check(Store.IntradaySnaps()[d0] == nil, "oldest day pruned from intradaySnaps")

    -- MigrateForeverSurnames migrates char keys inside DB.intradaySnaps
    local singleKey = "Normal-Horde-Forever-Thrall"
    local twoWordKey = "Normal-Horde-Forever-Thrall Ironfist"
    local latestDay = Store.DayKey(dayOffset(9, 12))
    local latestHr = string.format("%02d", tonumber(os.date("%H", dayOffset(9, 12))) or 12)
    Store.db.intradaySnaps[latestDay].points[latestHr].chars[singleKey] = { gold = 50000, items = 0, listed = 0, econ = ECON }
    Store.db.intradaySnaps[latestDay].points[latestHr].chars[twoWordKey] = nil
    Store.MigrateForeverSurnames({ [twoWordKey] = { name = "Thrall Ironfist" } }, twoWordKey)
    check(Store.db.intradaySnaps[latestDay].points[latestHr].chars[singleKey] == nil, "old single-word key removed from intradaySnaps")
    check(Store.db.intradaySnaps[latestDay].points[latestHr].chars[twoWordKey] ~= nil
        and Store.db.intradaySnaps[latestDay].points[latestHr].chars[twoWordKey].gold == 50000,
        "intradaySnaps migrated to two-word Forever key")
end

---------------------------------------------------------------------------------------------------
-- 2. Day-1 Hourly Wealth Reconstruction Fallback vs Daily Wealth Mode
---------------------------------------------------------------------------------------------------
do
    resetLedger()
    local tNow = dayOffset(0, 15)
    hostEnv.setFixtureNow(tNow)
    -- Seed today's ledger cashflows without intradaySnaps (simulating fresh install on Day 1)
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 4304, qty = 5, total = 50000, cogs = 20000, time = dayOffset(0, 11), extra = { gross = 52632, fee = 2632, name = "Thick Leather" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 10504, qty = 1, total = 150000, cogs = 50000, time = dayOffset(0, 14), extra = { gross = 157895, fee = 7895, name = "Green Lens" } })

    local portfolio1 = { series = {}, latestTotal = 500000, latestGold = 500000, latestItems = 0, latestListed = 0 }
    local recon = Brief.BuildWealthChartSeries("auto", "7d", ECON, portfolio1, tNow)
    check(recon.mode == "hourly", "auto selects hourly when < 2 daily snapshots")
    check(recon.usedFallback == true, "Day-1 fallback reconstruction activated")
    check(#recon.points >= 2, "Day-1 fallback produces >= 2 hourly points")
    check(recon.points[#recon.points].value == 500000, "Day-1 reconstructed series ends at latestTotal (50g)")
    check(recon.points[1].value == 300000, "Day-1 backward reconstruction removes +5g and +15g today cashflows -> 30g start (got " .. tostring(recon.points[1].value) .. ")")

    -- Multi-day portfolio -> auto selects daily for 7d, hourly for 24h
    local portfolioMulti = {
        series = {
            { day = "2026-11-10", total = 400000, gold = 300000, items = 50000, listed = 50000 },
            { day = "2026-11-11", total = 460000, gold = 340000, items = 60000, listed = 60000 },
            { day = "2026-11-12", total = 500000, gold = 350000, items = 80000, listed = 70000 },
        },
        latestTotal = 500000, latestGold = 350000, latestItems = 80000, latestListed = 70000,
    }
    local dailySeries = Brief.BuildWealthChartSeries("auto", "7d", ECON, portfolioMulti, tNow)
    check(dailySeries.mode == "daily", "auto selects daily when >= 2 daily snapshots and range=7d")
    check(#dailySeries.points == 3 and dailySeries.points[3].value == 500000, "daily series maps explicit .value fields")
    check(dailySeries.change24h == 40000, "daily 24h change = 50g - 46g = +4g")

    local auto24h = Brief.BuildWealthChartSeries("auto", "24h", ECON, portfolioMulti, tNow)
    check(auto24h.mode == "hourly", "auto selects hourly when range=24h even with multi-day snapshots")
end

---------------------------------------------------------------------------------------------------
-- 3. Strict AH_SELL-Only Profit (Excludes TRADE_SELL Arcanite CD, COD_SELL, VENDOR_SELL, CRAFT)
---------------------------------------------------------------------------------------------------
do
    resetLedger()
    local tNow = dayOffset(0, 16)
    hostEnv.setFixtureNow(tNow)

    -- Today AH_SELL: +30,000c (+3g) and +20,000c (+2g) => todayProfit = 50,000c (2 sales)
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 10504, qty = 1, total = 50000, cogs = 20000, time = dayOffset(0, 10), extra = { gross = 52632, fee = 2632, name = "Green Lens" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 4304, qty = 10, total = 30000, cogs = 10000, time = dayOffset(0, 14), extra = { gross = 31579, fee = 1579, name = "Thick Leather" } })

    -- Today NON-AH noise: HUGE Arcanite CD TRADE_SELL (+500,000c!), COD_SELL (+200,000c), VENDOR_SELL (+80,000c), CRAFT
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "TRADE_SELL", itemID = 12360, qty = 1, total = 500000, cogs = 0, time = dayOffset(0, 15), extra = { name = "Arcanite Bar" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "COD_SELL", itemID = 12360, qty = 1, total = 200000, cogs = 0, time = dayOffset(0, 15), extra = { name = "Arcanite Bar" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "VENDOR_SELL", itemID = 4304, qty = 5, total = 80000, cogs = 0, time = dayOffset(0, 15), extra = { name = "Thick Leather" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "CRAFT", itemID = 10504, qty = 1, total = 0, cogs = 20000, time = dayOffset(0, 9), extra = { spellID = 12717, name = "Green Lens" } })

    -- Yesterday AH_SELL: +70,000c (+7g) plus a TRADE_SELL that must be ignored
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 10504, qty = 1, total = 100000, cogs = 30000, time = dayOffset(-1, 13), extra = { gross = 105263, fee = 5263, name = "Green Lens" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "TRADE_SELL", itemID = 12360, qty = 1, total = 900000, cogs = 0, time = dayOffset(-1, 14), extra = { name = "Arcanite Bar" } })

    -- Completed days -2..-7: put +70,000c on day -3 and +140,000c on day -5
    -- Sum across 7 completed days [-7..-1] = 70000 + 70000 + 140000 = 280000 => avg7d = 40,000c
    -- Yesterday (70,000c) vs avg7d (40,000c) = +75.0%
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 4304, qty = 10, total = 90000, cogs = 20000, time = dayOffset(-3, 12), extra = { gross = 94737, fee = 4737, name = "Thick Leather" } })
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 10504, qty = 2, total = 200000, cogs = 60000, time = dayOffset(-5, 12), extra = { gross = 210526, fee = 10526, name = "Green Lens" } })

    local sum7 = Brief.ComputeAHSalesSummary(ECON, "7d", tNow)
    check(sum7.todayProfit == 50000, "todayProfit is strictly AH_SELL (expected 50000, got " .. tostring(sum7.todayProfit) .. ")")
    check(sum7.todaySalesCount == 2, "todaySalesCount is strictly AH_SELL (expected 2, got " .. tostring(sum7.todaySalesCount) .. ")")
    check(sum7.yesterdayProfit == 70000, "yesterdayProfit excludes Arcanite TRADE_SELL (expected 70000, got " .. tostring(sum7.yesterdayProfit) .. ")")
    check(sum7.avg7dCompleted == 40000, "7d completed-day avg excludes partial today (expected 40000, got " .. tostring(sum7.avg7dCompleted) .. ")")
    check(sum7.yesterdayDeltaPct and math.abs(sum7.yesterdayDeltaPct - 75.0) < 0.01, "yesterday vs 7d avg = +75.0%")
    check(#sum7.dailyBars == 7, "7d dailyBars has 7 zero-filled calendar days")
    check(#sum7.hourlyBars == 24, "24h hourlyBars has 24 hourly buckets")
    check(sum7.bestItem and sum7.bestItem.itemID == 10504 and sum7.bestItem.profit == 240000, "bestItem is Green Lens (+24g)")
    check(sum7.bestSingleSale and sum7.bestSingleSale.itemID == 10504 and sum7.bestSingleSale.profit == 140000, "bestSingleSale is Green Lens x2 (+14g), NOT Arcanite TRADE_SELL")

    -- Verify zero TRADE_SELL rows leak into recentSales
    for _, sale in ipairs(sum7.recentSales) do
        check(sale.itemID ~= 12360, "Arcanite Bar TRADE_SELL/COD_SELL strictly excluded from recentSales")
    end

    -- Zero-division guard when 7d completed avg == 0
    resetLedger()
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "AH_SELL", itemID = 4304, qty = 1, total = 5000, cogs = 1000, time = dayOffset(0, 12), extra = { gross = 5263, fee = 263, name = "Thick Leather" } })
    local sumZero = Brief.ComputeAHSalesSummary(ECON, "7d", tNow)
    check(sumZero.avg7dCompleted == 0 and sumZero.yesterdayDeltaPct == nil, "zero 7d avg guards division by zero -> nil deltaPct")
end

---------------------------------------------------------------------------------------------------
-- 4. Reagent Price-Drop Alerts: Green Lens + Thick Leather (800c -> 600c x8 = -1600c = -16s cost)
---------------------------------------------------------------------------------------------------
do
    resetLedger()
    local tNow = dayOffset(0, 16)
    hostEnv.setFixtureNow(tNow)

    -- Register test recipe: Green Lens (spell 12717, output 10504) using Thick Leather (4304) x8,
    -- Coarse Thread (2320, vendor) x2, and Outlier Gem (99991, >10x single-sample spike) x1.
    local greenLensRec = {
        spellID = 12717,
        outputItemID = 10504,
        name = "Green Lens",
        numMade = 1,
        reagents = {
            { itemID = 4304, qty = 8 },
            { itemID = 2320, qty = 2 },
            { itemID = 99991, qty = 1 },
        },
    }
    local origBySpell = ns.RECIPES_BY_SPELL
    local origByOutput = ns.RECIPES_BY_OUTPUT
    local origGetReagentCost = ns.GetReagentUnitCost
    local origGetNumListed = ns.GetNumListed
    local origTrend7d = ns.MarketScan and ns.MarketScan.GetItemTrend7d
    local origResolveReagents = ns.ResolveRecipeReagents

    ns.RECIPES_BY_SPELL = { [12717] = greenLensRec }
    ns.RECIPES_BY_OUTPUT = { [10504] = { greenLensRec } }
    ns.ResolveRecipeReagents = function(r) return r.reagents end
    ns.GetReagentUnitCost = function(id)
        if id == 4304 then return 600, "Live AH", false end       -- Thick Leather dropped to 6s
        if id == 2320 then return 10, "Vendor", true end          -- Coarse Thread is vendor -> MUST skip!
        if id == 99991 then return 100, "Live AH", false end      -- Outlier test
        return nil, nil, false
    end
    ns.GetNumListed = function(id)
        if id == 4304 or id == 99991 then return 25 end
        return 0
    end
    local curUnixDay = math.floor(tNow / 86400)
    ns.MarketScan = ns.MarketScan or {}
    ns.MarketScan.GetItemTrend7d = function(id)
        if id == 4304 then
            return {
                points = {
                    { d = curUnixDay - 3, price = 800 },
                    { d = curUnixDay - 2, price = 800 },
                    { d = curUnixDay - 1, price = 800 },
                    { d = curUnixDay,     price = 600 },
                },
            }
        elseif id == 2320 then
            return { points = { { d = curUnixDay - 1, price = 100 } } } -- fake vendor drop
        elseif id == 99991 then
            return { points = { { d = curUnixDay - 1, price = 5000 } } } -- single-sample 50x spike -> reject!
        end
        return { points = {} }
    end

    -- Record user crafting Green Lens so it enters personal top crafts
    Store.Append({ char = CHAR_MAIN, econ = ECON, type = "CRAFT", itemID = 10504, qty = 2, total = 0, cogs = 0, time = dayOffset(-1, 10), extra = { spellID = 12717, name = "Green Lens" } })

    local alerts = Brief.ComputeReagentPriceDrops(ECON, tNow)
    check(#alerts == 1, "only Thick Leather triggers alert (vendor + >10x single-sample spike skipped; got " .. tostring(#alerts) .. ")")
    local a = alerts[1]
    check(a.recipeName == "Green Lens", "alert recipe is Green Lens")
    check(a.reagentID == 4304 and a.reagentQty == 8, "alert reagent is Thick Leather x8")
    check(a.baselineUnit == 800 and a.curUnit == 600, "Thick Leather baseline 800c -> 600c")
    check(math.abs(a.dropPct - (-25.0)) < 0.01, "dropPct = -25%")
    check(a.unitSaved == 200 and a.craftSaved == 1600, "unitSaved=200c, craftSaved=1600c (-16s cost)")
    check("-" .. Brief.FormatCopper(a.craftSaved, false) .. " cost" == "-16s cost", "formats exact -16s cost label")

    -----------------------------------------------------------------------------------------------
    -- 5. Full View Rendering, Virtual Scroll (60 -> 50 cap), Interactions, Layout Non-Overlap, & Skins
    -----------------------------------------------------------------------------------------------
    -- Seed 60 AH_SELL rows to test 50-row cap + virtual scroll pagination
    for idx = 1, 60 do
        Store.Append({
            char = CHAR_MAIN,
            econ = ECON,
            type = "AH_SELL",
            itemID = (idx == 60) and 10504 or (10000 + idx),
            qty = (idx % 3) + 1,
            total = 20000 + idx * 1000,
            cogs = 10000,
            time = dayOffset(0, 8) + idx * 120,
            extra = { gross = 21053 + idx * 1053, fee = 1053 + idx * 53, name = "Auction Item " .. tostring(idx) },
        })
    end
    Store.SaveSnapshot(CHAR_MAIN, Store.DayKey(tNow), { gold = 700000, items = 200000, listed = 100000, econ = ECON, time = tNow })

    local modeChanges, deepOpens, cartAdds = {}, {}, {}
    local hostFrame = CreateFrame("Frame", "TestBriefHost", UIParent)
    hostFrame:SetSize(1600, 642)

    local view = Brief.Create(hostFrame, {
        getEconKey = function() return ECON end,
        getPlayerName = function() return "Grommash" end,
        getFreshnessText = function() return "Live" end,
        onModeChange = function(m) modeChanges[#modeChanges + 1] = m end,
        onOpenDeepAnalysis = function(spec) deepOpens[#deepOpens + 1] = spec end,
        onAddToCart = function(id, qty, name) cartAdds[#cartAdds + 1] = { id = id, qty = qty, name = name }; return true end,
    })

    view:Refresh(true, tNow)
    check(view.greetingFs:GetText():find("Grommash", 1, true) ~= nil, "greeting banner includes player name")
    check(Brief.GetGreeting(9, "Grommash") == "Good morning, Grommash", "morning greeting at 09:00")
    check(Brief.GetGreeting(14, "Grommash") == "Good afternoon, Grommash", "afternoon greeting at 14:00")
    check(Brief.GetGreeting(21, "Grommash") == "Good evening, Grommash", "evening greeting at 21:00")

    -- Mode switcher callback
    view.modeSeg:SetActive("classic", false)
    check(modeChanges[#modeChanges] == "classic", "mode switcher calls onModeChange('classic')")
    view.modeSeg:SetActive("brief", false)
    check(modeChanges[#modeChanges] == "brief", "mode switcher calls onModeChange('brief')")

    -- Reagent alert interactions: Left-click -> Recipe, Right-click -> Reagent, Shift-click -> Cart
    local alertRow1 = view.alertsPanel.rows[1]
    check(alertRow1:IsShown() and alertRow1.saveFs:GetText() == "-16s cost", "alert row 1 displays -16s cost")
    alertRow1:GetScript("OnClick")(alertRow1, "LeftButton")
    check(deepOpens[#deepOpens].kind == "recipe" and deepOpens[#deepOpens].spellID == 12717, "alert left-click opens Recipe Deep Analysis")
    alertRow1:GetScript("OnClick")(alertRow1, "RightButton")
    check(deepOpens[#deepOpens].kind == "item" and deepOpens[#deepOpens].itemID == 4304, "alert right-click opens Reagent Deep Analysis")
    local origShift = _G.IsShiftKeyDown
    _G.IsShiftKeyDown = function() return true end
    alertRow1:GetScript("OnClick")(alertRow1, "LeftButton")
    _G.IsShiftKeyDown = origShift
    check(#cartAdds == 1 and cartAdds[1].id == 4304 and cartAdds[1].qty == 8, "alert shift-click adds Thick Leather x8 to cart")

    -- Virtual scroll pagination on Recent AH Sales (capped at 50)
    local st = view:GetState()
    check(#st.summary.recentSales == 50, "recentSales capped at 50 entries")
    local firstBeforeScroll = view.salesPanel.rows[1]._sale.name
    view.salesPanel:ScrollBy(5)
    check(view.salesPanel:GetScrollOffset() == 5, "salesPanel scrolled by 5")
    check(view.salesPanel.rows[1]._sale.name ~= firstBeforeScroll, "virtual scroll updates visible row bindings")
    view.salesPanel:SetScrollOffset(999)
    check(view.salesPanel:GetScrollOffset() == 50 - st.visibleSalesRows, "salesPanel scroll offset clamps cleanly")
    view.salesPanel.rows[1]:GetScript("OnClick")(view.salesPanel.rows[1], "LeftButton")
    check(deepOpens[#deepOpens].kind == "item", "sales log click opens Deep Analysis")

    -- Best Single Sale strip click opens Deep Analysis
    view.bestPanel.bestSaleStrip:GetScript("OnClick")(view.bestPanel.bestSaleStrip, "LeftButton")
    check(deepOpens[#deepOpens].itemID == st.summary.bestSingleSale.itemID, "best single sale click opens Deep Analysis")

    -- Layout non-overlap checks across Goblin min (1036x612), Standard default (1600x642), and 1440p (2252x1298)
    for _, dim in ipairs({
        { label = "1036x612 (Goblin Min)", w = 1036, h = 612, minVisSales = 8 },
        { label = "1600x642 (Standard Default)", w = 1600, h = 642, minVisSales = 9 },
        { label = "2252x1298 (1440p)", w = 2252, h = 1298, minVisSales = 16 },
    }) do
        view:Layout(dim.w, dim.h)
        local g = view._geometry
        check(g.bannerH == 32, dim.label .. " bannerH == 32")
        check(-g.bannerH > g.kpiY, dim.label .. " banner does not overlap KPI row")
        check(g.kpiH >= 86, dim.label .. " kpiH >= 86 (zero internal text/bar overlap)")
        check(g.kpiY - g.kpiH > g.chartY, dim.label .. " KPI row does not overlap charts row")
        check(g.chartY - g.chartH > g.bottomY, dim.label .. " charts row does not overlap bottom bento row")
        check(-(g.bottomY - g.bottomH) <= dim.h + 1, dim.label .. " bottom bento fits inside viewport height")
        check(g.col1W + g.col2W + g.col3W + 2 * g.gap == dim.w, dim.label .. " 3 bento columns fill exact width")
        check(g.col1W >= 300 and g.col2W >= 300 and g.col3W >= 290, dim.label .. " all 3 columns comfortable width")
        check(st.visibleSalesRows >= dim.minVisSales, dim.label .. " visible sales rows scaled (" .. tostring(st.visibleSalesRows) .. ")")
    end

    -- Range selector switch to 24h -> Profit chart switches to hourly bars + Wealth auto-switches to hourly
    view:SetRange("24h", false)
    check(view:GetState().rangeKey == "24h", "range switched to 24h")
    check(view:GetState().effectiveWealthMode == "hourly", "24h range auto-selects hourly wealth chart")

    -- Dark, Light, and ALL 5 Warcraft skins repaint cleanly
    if Theme and Theme.SetMode and Theme.SetSkin then
        Theme.SetSkin("standard", false)
        Theme.SetMode("dark", false)
        view:ApplyTheme()
        Theme.SetMode("light", false)
        view:ApplyTheme()
        Theme.SetMode("dark", false)
        for _, info in ipairs(Theme.UI_SKINS or {}) do
            if info and info.key then
                Theme.SetSkin(info.key, false)
                view:ApplyTheme()
            end
        end
        Theme.SetSkin("standard", false)
        view:ApplyTheme()
        check(true, "Dark, Light, and all Warcraft skins repainted cleanly")
    end

    -- Restore globals
    ns.RECIPES_BY_SPELL = origBySpell
    ns.RECIPES_BY_OUTPUT = origByOutput
    ns.GetReagentUnitCost = origGetReagentCost
    ns.GetNumListed = origGetNumListed
    if ns.MarketScan then ns.MarketScan.GetItemTrend7d = origTrend7d end
    ns.ResolveRecipeReagents = origResolveReagents
end

---------------------------------------------------------------------------------------------------
-- 6. UI_Window.lua 1440p Support (Preserves 1920x1080 Invariants!)
---------------------------------------------------------------------------------------------------
do
    check(Window.IsLargeDisplay(1920, 1080) == false, "1920x1080 is not 1440p+")
    check(Window.IsLargeDisplay(2560, 1440) == true, "2560x1440 is 1440p+")

    local w1080, h1080 = Window.GetPreferredDefaultSize(1840, 730, 1920, 1080)
    check(w1080 == 1840 and h1080 == 730, "1920x1080 default size unchanged (1840x730)")

    local w1440, h1440 = Window.GetPreferredDefaultSize(1840, 730, 2560, 1440)
    check(w1440 == 2240 and h1440 == 1300, "2560x1440 preferred default expands to 2240x1300")

    local w2200, h2200 = Window.GetPreferredDefaultSize(1840, 730, 2200, 1200)
    check(w2200 == 2160 and h2200 == 1160, "2200x1200 caps at sw-40 x sh-40")

    local origGetW, origGetH = UIParent.GetWidth, UIParent.GetHeight
    UIParent.GetWidth = function() return 2560 end
    UIParent.GetHeight = function() return 1440 end
    local p1440 = CreateFrame("Frame", nil, UIParent)
    p1440.GetLeft = function() return 100 end
    p1440.GetTop = function() return 1380 end
    local db1440 = {}
    local ctrl1440 = Window.Attach(p1440, nil, nil, {
        defaultW = 1840, defaultH = 730,
        adaptiveLargeDefault = true,
        comfortableZoom = true,
        getWindowDB = function() return db1440 end,
    })
    ctrl1440:ApplyFull()
    check(p1440:GetWidth() == 2240 and p1440:GetHeight() == 1300, "adaptiveLargeDefault opens at 2240x1300 on 1440p")
    ctrl1440:SetSize(1600, 900)
    ctrl1440:ToggleZoom()
    check(ctrl1440:IsZoomed() and p1440:GetWidth() == 2240 and p1440:GetHeight() == 1300, "comfortableZoom caps 1440p zoom at 2240x1300")
    ctrl1440:ToggleZoom()
    check(not ctrl1440:IsZoomed() and p1440:GetWidth() == 1600 and p1440:GetHeight() == 900, "unzoom restores 1600x900")
    UIParent.GetWidth, UIParent.GetHeight = origGetW, origGetH

    -- Verify 1920x1080 invariant untouched
    local p1080 = CreateFrame("Frame", nil, UIParent)
    local db1080 = {}
    local ctrl1080 = Window.Attach(p1080, nil, nil, {
        defaultW = 1840, defaultH = 730,
        adaptiveLargeDefault = true,
        comfortableZoom = true,
        getWindowDB = function() return db1080 end,
    })
    ctrl1080:ApplyFull()
    check(p1080:GetWidth() == 1840 and p1080:GetHeight() == 730, "1920x1080 opens at exact 1840x730")
    ctrl1080:ToggleZoom()
    check(p1080:GetWidth() == 1896 and p1080:GetHeight() == 1056, "1920x1080 ToggleZoom expands to exact 1896x1056")
    ctrl1080:ToggleZoom()
    check(p1080:GetWidth() == 1840 and p1080:GetHeight() == 730, "1920x1080 unzoom restores exact 1840x730")
end

print("PASS dashboard_brief: " .. tostring(hostEnv.assertions()) .. " assertions, 0 failures")
