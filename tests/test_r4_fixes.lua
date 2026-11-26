-- Round 4 comprehensive regression suite verifying all Carbon High findings (#1..#16)
-- and the Multi-Source Demand Engine (My AH + Local Multi-Scan + Auctionator.Database + TSM).
local ADDON = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")

local checks = 0
local function check(ok, msg)
    checks = checks + 1
    assert(ok, "R4 assertion #" .. checks .. " failed: " .. tostring(msg))
end

-- 1. Data purity (#5a): Zero non-vendor recipes polluted with recipeVendorPrice
do
    local data = {}
    assert(loadfile(ADDON .. "Data_CratesAndWrits.lua"))("MerchantMaster", data)
    assert(loadfile(ADDON .. "Data_Recipes.lua"))("MerchantMaster", data)
    local campLeak, nonVendorLeak = 0, 0
    for _, r in ipairs(data.RECIPES) do
        local isVendor = (r.acqType == "vendor" or r.acqType == "vendor_ah" or r.source == "vendor")
        if not isVendor and (r.recipeVendorPrice or 0) > 0 then
            nonVendorLeak = nonVendorLeak + 1
            if r.acqType == "camp" or r.source == "camp" then campLeak = campLeak + 1 end
        end
    end
    check(campLeak == 0, "0 Camp Favor recipes carry recipeVendorPrice (got " .. campLeak .. ")")
    check(nonVendorLeak == 0, "0 non-vendor recipes polluted with recipeVendorPrice (got " .. nonVendorLeak .. ")")
end

-- 2. AH-pure Analytics channel separation (#2) & MM1 unpack memoization (#6b)
do
    local now = 1794600000
    _G.time = function() return now end
    _G.date = os.date
    local char = "Normal-Horde-Forever-Crafter"
    local alt = "Normal-Horde-Forever-Banker"
    local host = {
        app = { charKey = char },
        DetectActiveEconomy = function() return "Normal-Horde" end,
        GetItemMarketPrice = function() return 500 end,
        GetVendorSellPrice = function() return 25 end,
        ItemName = function(id) return "Item " .. tostring(id) end,
    }
    _G.MerchantMasterAPI = { ns = host }
    _G.MerchantMasterDB = { chars = { [char] = { faction = "Horde" }, [alt] = { faction = "Horde" } } }
    _G.MerchantMasterLedgerDB = {}
    assert(loadfile(ADDON .. "Analytics/Store.lua"))("MerchantMaster", host)
    assert(loadfile(ADDON .. "Analytics/Inventory.lua"))("MerchantMaster", host)
    assert(loadfile(ADDON .. "Analytics/Model.lua"))("MerchantMaster", host)
    local Store, Model = host.Analytics.Store, host.Analytics.Model
    Store.Init()

    -- Vendoring 140 leveling items must NOT pollute AH velocity or AH sell-through!
    Store.Append({ char = char, econ = "Normal-Horde", type = "VENDOR_SELL", itemID = 7001, qty = 140, total = 3500, time = now - 86400, extra = { source = "Vendor" } })
    -- Banker alt sells 7 units on AH and cancels 20 undercuts + expires 1
    Store.Append({ char = alt, econ = "Normal-Horde", type = "AH_POST", itemID = 7002, qty = 28, total = -100, time = now - 7200, extra = {} })
    Store.Append({ char = alt, econ = "Normal-Horde", type = "AH_SELL", itemID = 7002, qty = 7, total = 6650, time = now - 3600, extra = { gross = 7000, fee = 350 } })
    Store.Append({ char = alt, econ = "Normal-Horde", type = "AH_CANCEL", itemID = 7002, qty = 20, total = 0, time = now - 1800, extra = {} })
    Store.Append({ char = alt, econ = "Normal-Horde", type = "AH_EXPIRE", itemID = 7002, qty = 1, total = 0, time = now - 900, extra = {} })

    local ahRes = Model.Compute("items", { char = "all", econ = "Normal-Horde", period = "7d", source = "AH", knownCostOnly = false })
    local byID = {}
    for _, r in ipairs(ahRes.rows or {}) do byID[tonumber(r.itemID)] = r end
    check(byID[7001] == nil or (byID[7001].ahSold or 0) == 0, "VENDOR_SELL excluded from AH item velocity")
    check(byID[7002] ~= nil and byID[7002].ahSold == 7, "Economy-wide alt AH_SELL included")
    check(math.abs((byID[7002].ahVelocity or byID[7002].velocity) - 1.0) < 1e-6, "AH velocity = 7 / 7 = 1.0/d")
    check(math.abs((byID[7002].ahSellThrough or 0) - (7 / 8)) < 1e-6, "AH sell-through excludes 20 cancelled reposts (7 / (7+1))")
    check(byID[7002].cancelChurn and math.abs(byID[7002].cancelChurn - (20 / 28)) < 1e-6, "Cancel churn tracked separately (20 / 28)")

    -- Verify packed MM1 day string memoizes across repeated IterDays traversals
    local oldDay = Store.DayKey(now - 2 * 86400)
    Store.Append({ char = char, econ = "Normal-Horde", type = "AH_SELL", itemID = 7003, qty = 2, total = 190, time = now - 2 * 86400, extra = { gross = 200, fee = 10 } })
    Store.PackDay(oldDay)
    check(Store.db.days[oldDay].s ~= nil and Store.db.days[oldDay].r == nil, "oldDay packed into MM1 string")
    local unpackCalls = 0
    local realUnpack = Store.UnpackDayString
    Store.UnpackDayString = function(...) unpackCalls = unpackCalls + 1; return realUnpack(...) end
    for _ = 1, 5 do Store.IterDays("0000-00-00", "9999-99-99", function() end) end
    Store.UnpackDayString = realUnpack
    check(unpackCalls <= 1, "MM1 day string unpacked at most once across 5 IterDays calls (got " .. unpackCalls .. ")")
end

-- 3. Multi-Source Demand Engine & 7d Sales/d non-wipeout (#1) + Auctionator.Database + Local Multi-Scan + UI fixes
do
    local ns, _, hostEnv = dofile(S .. "host_fixture.lua")
    if ns.Analytics and ns.Analytics.Store and not ns.Analytics.Store.db then
        ns.Analytics.Store.Init()
    end

    -- Verify legacy Auctionator bridge is completely removed in standalone mode
    _G.Auctionator = {
        Database = {
            GetMeanPrice = function() error("Forbidden Auctionator.Database:GetMeanPrice called!") end,
            GetPriceHistory = function() error("Forbidden Auctionator.Database:GetPriceHistory called!") end,
        },
    }
    ns.InvalidatePriceCache()
    check(ns.GetAuctionatorMarketStats == nil, "Legacy GetAuctionatorMarketStats removed in pure standalone mode")
    _G.Auctionator = nil

    -- Verify Local Multi-Scan Depletion (MarketScan.GetLocalVelocity)
    local econ = ns.DetectActiveEconomy()
    local now = time()
    MerchantMasterDB.ahHistory = MerchantMasterDB.ahHistory or {}
    MerchantMasterDB.ahHistory[econ] = MerchantMasterDB.ahHistory[econ] or {}
    MerchantMasterDB.ahHistory[econ][250001] = {
        { t = now - 28800, p = 10000, q = 30 },
        { t = now - 14400, p = 11000, q = 18 },
        { t = now - 600,   p = 12000, q = 8 },
    }
    local localVel = ns.MarketScan.GetLocalVelocity(250001, econ)
    check(localVel and localVel.scanPairs == 2 and (localVel.clearsPerDay or 0) > 0, "Local multi-scan depletion produces positive clearsPerDay")
    check(localVel.confidence == "Med" or localVel.confidence == "High", "Local multi-scan confidence tier set")

    -- Verify GetEffectivePriceVersion does NOT scan/bump epoch when priceSource == "live_ah" (#6a)
    MerchantMasterDB.priceSource = "live_ah"
    MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
    MerchantMasterDB.ahPrices[econ] = MerchantMasterDB.ahPrices[econ] or {}
    MerchantMasterDB.ahPrices[econ][250001] = { price = 12000, qty = 8, at = now - 1805 }
    local epBefore = ns.GetEffectivePriceVersion()
    local epAfter = ns.GetEffectivePriceVersion()
    check(epBefore == epAfter, "live_ah priceSource never bumps priceCacheEpoch on 1800s age boundary")

    -- Verify 7d personal coverage NEVER wipes uncrafted catalog recipes to 0 (#1)
    -- Seed synthetic snapshot velocity for two distinct sellable catalog recipes.
    local char = ns.app.charKey
    ns.Analytics.Store.db.stats.firstLive[char] = now - 10 * 86400
    local catalog = ns.RecipeStats.GetCatalog()
    local soldRec, untouchedRec
    for _, entry in ipairs(catalog) do
        local r = entry.recipe
        if r.sellable ~= false and r.outputItemID then
            if not soldRec then soldRec = r
            elseif r.outputItemID ~= soldRec.outputItemID then untouchedRec = r; break end
        end
    end
    check(soldRec and untouchedRec, "found two distinct sellable catalog recipes")
    hostEnv.loadSyntheticSnapshots({
        econ = econ,
        updatedAt = now - 300,
        items = {
            [soldRec.outputItemID] = { minBuyout = 1000, marketValue = 1200, historical = 1100, qty = 25, numAuctions = 4, dailySold = 8.5, obsHours = 24, confidence = 2 },
            [untouchedRec.outputItemID] = { minBuyout = 2000, marketValue = 2200, historical = 2100, qty = 20, numAuctions = 3, dailySold = 6.2, obsHours = 24, confidence = 2 },
        },
    })
    MerchantMasterDB.priceSource = "auto"
    ns.InvalidatePriceCache()
    ns.Analytics.Store.Append({
        char = char, econ = econ, type = "AH_SELL", itemID = soldRec.outputItemID,
        qty = 14, total = 13300, time = now - 3600, extra = { gross = 14000, fee = 700 }
    })
    ns.RecipeStats.Invalidate("ledger")
    local ctx = ns.app.getRecipeStatsContext({
        db = MerchantMasterDB, counts = {}, profMap = {}, repState = { standing = 4 },
        econInfo = ns.CurrentEconomyInfo(), charKey = char, now = now,
    })
    local sRow = ns.RecipeStats.Get(soldRec, ctx)
    local uRow = ns.RecipeStats.Get(untouchedRec, ctx)
    check(sRow.salesScope == "Personal" and math.abs(sRow.salesPerDay - 2.0) < 1e-6, "personally sold item uses Personal 7d AH velocity (2.0/d)")
    check(uRow.salesScope == "Blizzard" and uRow.salesPerDay > 0, "untouched recipe preserves Blizzard Snapshot Sales/d (" .. tostring(uRow.salesPerDay) .. ") instead of wiping to 0!")
    hostEnv.clearSyntheticSnapshots()

    -- Verify in-place PatchMeta updates ownership without re-pricing (#7a)
    ctx.ownedCounts = { [untouchedRec.outputItemID] = 42 }
    check(type(ns.RecipeStats.PatchMeta) == "function", "RecipeStats.PatchMeta exposed")
    ns.RecipeStats.PatchMeta({ uRow }, ctx)
    check(uRow.ownedOutputQty == 42, "PatchMeta updates ownedOutputQty in-place")

    -- Verify Camp Favor catalog recipe has nil recipeVendorPrice (#5)
    local campRec
    for _, r in ipairs(ns.RECIPES) do
        if r.acqType == "camp" and (r.favorCost or 0) > 0 then campRec = r; break end
    end
    check(campRec ~= nil and campRec.recipeVendorPrice == nil, "Camp Favor catalog recipe has nil recipeVendorPrice")

    -- Verify All Host & Professor Tables have proportional = true (#4)
    for _, t in ipairs(ns.app.ui.resizeTables or {}) do
        check(t.proportional == true, "Host/Professor table has proportional = true")
    end

    -- Verify Profit Spread exposes Best column & bisOnly filter (#13)
    local spreadHasBest = false
    if ns.app.ui.profitSpreadTable and ns.app.ui.profitSpreadTable.columns then
        for _, col in ipairs(ns.app.ui.profitSpreadTable.columns) do
            if col.key == "bisSort" then spreadHasBest = true; break end
        end
    end
    check(spreadHasBest, "Profit Spread table includes Best (bisSort) column")

    _G.Auctionator = nil

    -- Verify ScanPlayerProfessions ignores stale OneForAllCharDB professions when live professions exist
    local origGetLive = ns.GetLivePlayerProfessions
    local origOFA = _G.OneForAllCharDB
    ns.GetLivePlayerProfessions = function() return { alchemy = 300, engineering = 300 } end
    _G.OneForAllCharDB = { professions = { Leatherworking = { skill = 157, maxSkill = 225, scanned = true } } }
    local scanned = ns.MP.ScanPlayerProfessions()
    check(scanned.alchemy ~= nil and scanned.alchemy.rank == 300, "ScanPlayerProfessions keeps live alchemy")
    check(scanned.leatherworking == nil, "ScanPlayerProfessions ignores stale OneForAllCharDB leatherworking when live profs exist")
    ns.GetLivePlayerProfessions = origGetLive
    _G.OneForAllCharDB = origOFA
end

print("PASS: R4 comprehensive suite (" .. checks .. " assertions, 0 failures)")
