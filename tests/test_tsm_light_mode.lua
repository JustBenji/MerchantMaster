-- Verification suite for Opt-In TSM Light Mode + 1440p Window Auto-Scaling Wiring (Pure ASCII)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, _, hostEnv = dofile(testsDir .. "host_fixture.lua")
local check = hostEnv.check
local app = ns.app

-- Clear any synthetic snapshots so we test pure TSM Light Mode without local snapshots
if hostEnv.clearSyntheticSnapshots then hostEnv.clearSyntheticSnapshots() end
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local ECON_ACTIVE = ns.CurrentEconomyInfo().effectiveKey
local ECON_OTHER = (ECON_ACTIVE == "Normal-Horde") and "Normal-Alliance" or "Normal-Horde"
local ITEM_MIN = 4304   -- Thick Leather (DBMinBuyout + DBMarket + DBRegionSoldPerDay)
local ITEM_MKT = 7912   -- Solid Stone (nil DBMinBuyout -> DBMarket fallback)
local ITEM_NONE = 99988 -- No TSM data

-- Install strict spy proxy on _G.TSM_API BEFORE testing default OFF behavior
local tsmSpyHits = 0
local tsmSpyEnabled = false
local tsmMockLastUpdateFn = nil
local tsmMockAltLastUpdateFn = nil
local tsmMockData = {
    ["i:" .. tostring(ITEM_MIN)] = {
        DBMinBuyout = 650,
        DBMarket = 800,
        DBHistorical = 820,
        DBNumAuctions = 14,
        DBRegionSoldPerDay = 42.5,
    },
    ["i:" .. tostring(ITEM_MKT)] = {
        DBMinBuyout = nil,
        DBMarket = 320,
        DBHistorical = 350,
        DBNumAuctions = 9,
        DBRegionSoldPerDay = 18.0,
    },
}

local spyProxy = setmetatable({}, {
    __index = function(_, key)
        tsmSpyHits = tsmSpyHits + 1
        if tsmSpyEnabled then
            if key == "GetCustomPriceValue" then
                return function(expr, itemStr)
                    local rec = tsmMockData[itemStr]
                    return rec and rec[expr] or nil
                end
            elseif key == "GetAuctionDBLastUpdate" then
                return tsmMockLastUpdateFn
            elseif key == "GetLastUpdate" then
                return tsmMockAltLastUpdateFn
            end
        end
        return nil
    end,
})

local origTSM = rawget(_G, "TSM_API")
rawset(_G, "TSM_API", spyProxy)

local function hasSourceKey(list, key)
    for _, s in ipairs(list or {}) do
        if s and s.key == key then return true end
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- (a) Default OFF: 0 reads on _G.TSM_API spy proxy, GetAvailablePriceSources() omits "tsm"
---------------------------------------------------------------------------------------------------
do
    MerchantMasterDB.useTSMPrices = false
    MerchantMasterDB.priceSource = "auto"
    MerchantMasterDB.economy = "auto"
    MerchantMasterDB.ahPrices = {}
    MerchantMasterDB.lastRefreshAt = nil
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

    tsmSpyHits = 0
    tsmSpyEnabled = false

    check(ns.IsTSMOptInEnabled() == false, "IsTSMOptInEnabled() is false by default")
    check(ns.IsTSMAvailable() == false, "IsTSMAvailable() is false when opted out")
    check(not hasSourceKey(ns.GetAvailablePriceSources(), "tsm"), "GetAvailablePriceSources() omits 'tsm' when OFF")

    local p1, s1 = ns.GetItemMarketPrice(ITEM_MIN)
    local p2, s2 = ns.GetFallbackMarketPrice(ITEM_MIN)
    local p3 = ns.QueryTSMPrice(ITEM_MIN)
    local b3 = ns.QueryTSMMarketBundle(ITEM_MIN)
    local d1 = ns.GetMultiSourceDemand(ITEM_MIN, ECON_ACTIVE)
    local tOff = ns.GetTSMLastUpdateTime()
    local _ = p1, s1, p2, s2, p3, b3, d1
    check(tOff == nil, "GetTSMLastUpdateTime() returns nil when TSM Light Mode is OFF")

    app.panel:Show()
    app.setTab("dashboard")
    app.refresh()

    check(tsmSpyHits == 0, "Zero _G.TSM_API reads when TSM Light Mode is OFF (got " .. tostring(tsmSpyHits) .. ")")
end

---------------------------------------------------------------------------------------------------
-- (b) Toggle ON: DBMinBuyout -> DBMarket fallback, numAuctions, DBRegionSoldPerDay,
--     active-economy-only isolation, HasSnapshots() == false, heatmaps & depth remain nil
---------------------------------------------------------------------------------------------------
do
    tsmSpyEnabled = true
    tsmSpyHits = 0
    MerchantMasterDB.useTSMPrices = true
    MerchantMasterDB.priceSource = "tsm"
    MerchantMasterDB.economy = "auto"
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

    check(ns.IsTSMOptInEnabled() == true, "IsTSMOptInEnabled() is true when useTSMPrices=true")
    check(ns.IsTSMAvailable() == true, "IsTSMAvailable() is true when opted in and TSM_API present")
    check(hasSourceKey(ns.GetAvailablePriceSources(), "tsm"), "GetAvailablePriceSources() includes 'tsm' when ON")
    check(ns.GetEffectivePriceSource() == "tsm", "GetEffectivePriceSource() returns 'tsm' when available")

    -- DBMinBuyout -> "TSM (Light)" + numAuctions
    local pMin, srcMin, qtyMin = ns.GetItemMarketPrice(ITEM_MIN)
    check(pMin == 650, "DBMinBuyout returns 650c (got " .. tostring(pMin) .. ")")
    check(srcMin == "TSM (Light)", "DBMinBuyout source label is 'TSM (Light)' (got " .. tostring(srcMin) .. ")")
    check(qtyMin == 14, "DBNumAuctions returns 14 (got " .. tostring(qtyMin) .. ")")

    -- DBMinBuyout nil -> DBMarket fallback "TSM Market" + numAuctions
    local pMkt, srcMkt, qtyMkt = ns.GetItemMarketPrice(ITEM_MKT)
    check(pMkt == 320, "DBMarket fallback returns 320c (got " .. tostring(pMkt) .. ")")
    check(srcMkt == "TSM Market", "DBMarket fallback source label is 'TSM Market' (got " .. tostring(srcMkt) .. ")")
    check(qtyMkt == 9, "DBMarket fallback preserves DBNumAuctions=9 (got " .. tostring(qtyMkt) .. ")")

    -- Missing item returns nil cleanly
    local pNone = ns.GetItemMarketPrice(ITEM_NONE)
    check(pNone == nil, "Item with no TSM values returns nil")

    -- Memoization check: repeated lookup in same epoch makes 0 extra _G.TSM_API calls
    local hitsBeforeMemo = tsmSpyHits
    local pMin2 = ns.QueryTSMPrice(ITEM_MIN)
    check(pMin2 == 650 and tsmSpyHits == hitsBeforeMemo, "QueryTSMMarketBundle memoizes per priceCacheEpoch")

    -- ns.GetTSMLastUpdateTime(): _tsmLastSeenAt fallback when TSM_API has no timestamp API,
    -- and direct GetAuctionDBLastUpdate() / GetLastUpdate() when exposed
    local now = hostEnv.getFixtureNow()
    tsmMockLastUpdateFn = nil
    tsmMockAltLastUpdateFn = nil
    local fallbackTs = ns.GetTSMLastUpdateTime()
    check(type(fallbackTs) == "number" and fallbackTs > 0 and fallbackTs <= now and fallbackTs == ns._tsmLastSeenAt,
        "GetTSMLastUpdateTime() falls back to valid _tsmLastSeenAt timestamp when TSM exposes no update API (got "
            .. tostring(fallbackTs) .. ")")

    local mockUpdatedAt = now - 900
    tsmMockLastUpdateFn = function() return mockUpdatedAt end
    local apiTs = ns.GetTSMLastUpdateTime()
    check(apiTs == mockUpdatedAt,
        "GetTSMLastUpdateTime() returns mocked GetAuctionDBLastUpdate() timestamp (got " .. tostring(apiTs) .. ")")

    -- Future or throwing GetAuctionDBLastUpdate safely falls back to GetLastUpdate / _tsmLastSeenAt
    tsmMockLastUpdateFn = function() return now + 7200 end
    tsmMockAltLastUpdateFn = function() return now - 1200 end
    check(ns.GetTSMLastUpdateTime() == (now - 1200),
        "GetTSMLastUpdateTime() rejects future timestamp and falls back to GetLastUpdate()")
    tsmMockLastUpdateFn = function() error("boom") end
    tsmMockAltLastUpdateFn = nil
    check(ns.GetTSMLastUpdateTime() == ns._tsmLastSeenAt,
        "GetTSMLastUpdateTime() catches pcall error and falls back to _tsmLastSeenAt")
    tsmMockLastUpdateFn = nil
    tsmMockAltLastUpdateFn = nil

    -- DBRegionSoldPerDay fallback in GetMultiSourceDemand (active economy)
    local dem = ns.GetMultiSourceDemand(ITEM_MIN, ECON_ACTIVE)
    check(type(dem) == "table" and dem.dailySold == 42.5 and dem.demandSource == "TSM",
        "GetMultiSourceDemand falls back to DBRegionSoldPerDay=42.5 labeled 'TSM'")

    -- Active-economy-only isolation: cross-economy MUST NEVER leak TSM prices or TSM demand!
    MerchantMasterDB.economy = ECON_OTHER
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
    local pCross, srcCross = ns.GetItemMarketPrice(ITEM_MIN)
    local pCrossFb = ns.GetFallbackMarketPrice(ITEM_MIN)
    local demCross = ns.GetMultiSourceDemand(ITEM_MIN, ECON_OTHER)
    check(pCross == nil and srcCross == nil, "Cross-economy GetItemMarketPrice never returns TSM prices")
    check(pCrossFb == nil, "Cross-economy GetFallbackMarketPrice never returns TSM prices")
    check(demCross == nil or demCross.demandSource ~= "TSM", "Cross-economy GetMultiSourceDemand never leaks TSM demand")

    -- Restore active economy
    MerchantMasterDB.economy = "auto"
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

    -- CRITICAL GUARANTEE: HasSnapshots() stays false, heatmaps & depth stay nil
    check(ns.HasSnapshots() == false, "HasSnapshots() remains false when only TSM Light Mode is active")
    check(ns.Pricing.GetItemHeatStrip24h(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemHeatStrip24h stays nil in TSM Light Mode")
    check(ns.Pricing.GetItemHeatmap(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemHeatmap stays nil in TSM Light Mode")
    if ns.Pricing.GetItemSnapshotDepth then
        check(ns.Pricing.GetItemSnapshotDepth(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemSnapshotDepth stays nil in TSM Light Mode")
    end
    if ns.Pricing.GetItemSnapshotVelocity then
        check(ns.Pricing.GetItemSnapshotVelocity(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemSnapshotVelocity stays nil in TSM Light Mode")
    end

    -- Top status capsule displays TSM <age> with fresh green indicator (NOT "No AH Scan Yet")
    app.setTab("dashboard")
    app.refresh()
    check(app.ui._statusUsingTSM == true, "status capsule flags _statusUsingTSM=true")
    check(app.ui._statusNoScanYet == false, "status capsule clears _statusNoScanYet when TSM Light Mode active")
    check(app.ui._statusTsmAt == ns._tsmLastSeenAt,
        "status capsule stores _statusTsmAt from GetTSMLastUpdateTime() fallback")
    local syncTxt = app.ui.statusSyncFs and app.ui.statusSyncFs:GetText() or ""
    check(syncTxt:find("TSM", 1, true) ~= nil and syncTxt:find("just now", 1, true) ~= nil,
        "status capsule displays TSM <age> (got '" .. tostring(syncTxt) .. "')")

    -- With mocked GetAuctionDBLastUpdate (15m ago), status capsule shows "TSM 15m" and tooltip reflects it
    local ts15m = hostEnv.getFixtureNow() - 900
    tsmMockLastUpdateFn = function() return ts15m end
    app.refresh()
    local syncTxt15m = app.ui.statusSyncFs and app.ui.statusSyncFs:GetText() or ""
    check(app.ui._statusTsmAt == ts15m, "status capsule updates _statusTsmAt from GetAuctionDBLastUpdate()")
    check(syncTxt15m:find("TSM", 1, true) ~= nil and syncTxt15m:find("15m", 1, true) ~= nil,
        "status capsule displays 'TSM 15m' when TSM last update was 15m ago (got '" .. tostring(syncTxt15m) .. "')")
    GameTooltip:Hide()
    if app.ui.statusCapsule and app.ui.statusCapsule:GetScript("OnEnter") then
        app.ui.statusCapsule:GetScript("OnEnter")(app.ui.statusCapsule)
        local joined = table.concat(GameTooltip._lines or {}, "\n")
        check(joined:find("TSM Light Mode", 1, true) ~= nil and joined:find("heatmaps", 1, true) ~= nil
            and joined:find("15m", 1, true) ~= nil,
            "status capsule tooltip notes TSM Light Mode timestamp and without heatmaps/depth")
        GameTooltip:Hide()
    end
    tsmMockLastUpdateFn = nil
end

---------------------------------------------------------------------------------------------------
-- (c) "auto" mode precedence: TSM beats stale (>30m) AH scan, but respects recent (<=30m) Live AH scan
---------------------------------------------------------------------------------------------------
do
    local now = hostEnv.getFixtureNow()
    MerchantMasterDB.useTSMPrices = true
    MerchantMasterDB.priceSource = "auto"
    MerchantMasterDB.economy = "auto"

    -- Stale Saved AH scan (2 hours old) -> TSM Light Mode wins!
    MerchantMasterDB.ahPrices = {
        [ECON_ACTIVE] = {
            _scannedAt = now - 7200,
            [ITEM_MIN] = { price = 999, qty = 5, at = now - 7200, absent = false },
        },
    }
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
    local pStale, srcStale = ns.GetItemMarketPrice(ITEM_MIN)
    check(pStale == 650 and srcStale == "TSM (Light)",
        "auto mode prefers TSM Light Mode ahead of stale (>30m) Saved AH scan (got " .. tostring(pStale) .. ", " .. tostring(srcStale) .. ")")

    -- Recent Live AH scan (5 minutes old) -> Live AH wins over TSM!
    MerchantMasterDB.ahPrices = {
        [ECON_ACTIVE] = {
            _scannedAt = now - 300,
            [ITEM_MIN] = { price = 580, qty = 7, at = now - 300, absent = false },
        },
    }
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
    local pFresh, srcFresh = ns.GetItemMarketPrice(ITEM_MIN)
    check(pFresh == 580 and srcFresh == "Live AH",
        "auto mode respects recent (<=30m) Live AH scan over TSM (got " .. tostring(pFresh) .. ", " .. tostring(srcFresh) .. ")")
end

---------------------------------------------------------------------------------------------------
-- (d) Toggle OFF: resets "tsm" back to "auto" and touches _G.TSM_API 0 times
---------------------------------------------------------------------------------------------------
do
    -- When TSM_API is absent even with priceSource="tsm", GetEffectivePriceSource falls back to "auto"
    rawset(_G, "TSM_API", nil)
    MerchantMasterDB.useTSMPrices = true
    MerchantMasterDB.priceSource = "tsm"
    check(ns.IsTSMAvailable() == false and ns.GetEffectivePriceSource() == "auto",
        "GetEffectivePriceSource() falls back to 'auto' when TSM_API is absent")
    rawset(_G, "TSM_API", spyProxy)

    MerchantMasterDB.useTSMPrices = false
    MerchantMasterDB.priceSource = "tsm"
    -- With useTSMPrices=false and priceSource="tsm", toggling OFF in UI resets priceSource -> "auto":
    if not MerchantMasterDB.useTSMPrices and MerchantMasterDB.priceSource == "tsm" then
        MerchantMasterDB.priceSource = "auto"
    end
    MerchantMasterDB.ahPrices = {}
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

    tsmSpyHits = 0
    check(ns.GetEffectivePriceSource() == "auto", "effective priceSource resets to 'auto' when toggled OFF")
    check(ns.IsTSMOptInEnabled() == false and ns.IsTSMAvailable() == false, "TSM helpers return false after toggle OFF")
    check(not hasSourceKey(ns.GetAvailablePriceSources(), "tsm"), "GetAvailablePriceSources() omits 'tsm' after toggle OFF")

    local pOff = ns.GetItemMarketPrice(ITEM_MIN)
    local pOffFb = ns.GetFallbackMarketPrice(ITEM_MIN)
    local dOff = ns.GetMultiSourceDemand(ITEM_MIN, ECON_ACTIVE)
    local tOff2 = ns.GetTSMLastUpdateTime()
    local _ = pOff, pOffFb, dOff
    check(tOff2 == nil, "GetTSMLastUpdateTime() returns nil after toggling TSM Light Mode OFF")
    app.refresh()

    check(tsmSpyHits == 0, "Zero _G.TSM_API reads after toggling TSM Light Mode OFF (got " .. tostring(tsmSpyHits) .. ")")
end

---------------------------------------------------------------------------------------------------
-- (e) 1440p Auto-Scaling Wiring Verification (UI_Theme.DecorateMainWindow -> Window.Attach)
---------------------------------------------------------------------------------------------------
do
    local origW, origH = UIParent.GetWidth, UIParent.GetHeight
    UIParent.GetWidth = function() return 2560 end
    UIParent.GetHeight = function() return 1440 end

    local testPanel = CreateFrame("Frame", "TestTSM1440Panel", UIParent)
    testPanel.GetLeft = function() return 100 end
    testPanel.GetTop = function() return 1380 end
    local savedWin = {}
    local prevWinDB = MerchantMasterDB.window
    MerchantMasterDB.window = savedWin

    local chrome = ns.Theme.DecorateMainWindow(testPanel, {
        fableShell = true,
        refreshAH = false,
        defaultW = 1840,
        defaultH = 730,
        adaptiveLargeDefault = true,
        comfortableZoom = true,
    })
    chrome.window:ApplyFull()
    check(testPanel:GetWidth() == 2240 and testPanel:GetHeight() == 1300,
        "DecorateMainWindow forwards adaptiveLargeDefault -> 2240x1300 on 1440p (got "
            .. tostring(testPanel:GetWidth()) .. "x" .. tostring(testPanel:GetHeight()) .. ")")
    chrome.window:SetSize(1600, 900)
    chrome.window:ToggleZoom()
    check(testPanel:GetWidth() == 2240 and testPanel:GetHeight() == 1300,
        "DecorateMainWindow forwards comfortableZoom -> 2240x1300 on 1440p")
    chrome.window:ToggleZoom()
    check(testPanel:GetWidth() == 1600 and testPanel:GetHeight() == 900,
        "1440p ToggleZoom restores previous 1600x900 size")

    MerchantMasterDB.window = prevWinDB
    UIParent.GetWidth, UIParent.GetHeight = origW, origH
end

---------------------------------------------------------------------------------------------------
-- (f) 3-Way Background Price Mode Mutual Exclusivity (Both Local Snapshots & TSM_API Loaded)
---------------------------------------------------------------------------------------------------
do
    rawset(_G, "TSM_API", spyProxy)
    tsmSpyEnabled = true
    MerchantMasterDB.ahPrices = {}
    MerchantMasterDB.lastRefreshAt = nil
    MerchantMasterDB.economy = "auto"

    hostEnv.loadSyntheticSnapshots({
        econ = ECON_ACTIVE,
        items = {
            [ITEM_MIN] = {
                minBuyout = 500,
                marketValue = 550,
                historical = 560,
                qty = 30,
                numAuctions = 6,
                dailySold = 12.5,
                obsHours = 24,
                confidence = 3,
            },
        },
        depth = tostring(ITEM_MIN) .. ":FM,A|G0,K",
        heat24 = tostring(ITEM_MIN) .. ":FM,FM,K,5,A,0,FM,12,G0|FM,FM,G0",
        heat7x24 = tostring(ITEM_MIN) .. ":0=FM,FM,K,5|12=G0,FM,A,3",
        heatmapCount = 1,
        depthCount = 1,
        system = [[return {v=1,exportedAt=1794360000,region="eu",credsSet=true,dbBytes=1024,totalRuns=3}]],
    })

    -- 1. SetBackgroundPriceMode("tsm"): suppresses Local Snapshot while TSM Light serves prices
    check(ns.SetBackgroundPriceMode("tsm") == true, "SetBackgroundPriceMode('tsm') succeeds")
    check(ns.GetBackgroundPriceMode() == "tsm", "GetBackgroundPriceMode() returns 'tsm'")
    check(ns.IsLocalSnapshotSuppressed() == true, "IsLocalSnapshotSuppressed() is true in 'tsm' mode")
    check(ns.IsTSMOptInEnabled() == true and ns.IsTSMAvailable() == true, "TSM opt-in and availability true in 'tsm' mode")
    check(ns.HasRawSnapshots() == true, "HasRawSnapshots() remains true on disk in 'tsm' mode")
    check(ns.HasSnapshots() == false, "HasSnapshots() returns false when suppressed by 'tsm' mode")
    check(ns.QueryLocalSnapshot(ITEM_MIN, ECON_ACTIVE) == nil, "QueryLocalSnapshot() returns nil in 'tsm' mode")
    check(ns.Pricing.GetAllAuctionHousesForItem(ITEM_MIN, ECON_ACTIVE) == nil, "GetAllAuctionHousesForItem() returns nil in 'tsm' mode")
    check(ns.Pricing.GetSnapshotMeta(ECON_ACTIVE) == nil, "GetSnapshotMeta() returns nil in 'tsm' mode")
    check(ns.Pricing.IsSnapshotFresh(ECON_ACTIVE) == false, "IsSnapshotFresh() returns false in 'tsm' mode")
    check(ns.Pricing.GetItemSnapshotDepth(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemSnapshotDepth() returns nil in 'tsm' mode")
    check(ns.Pricing.GetItemSnapshotVelocity(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemSnapshotVelocity() returns nil in 'tsm' mode")
    check(ns.Pricing.GetItemHeatStrip24h(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemHeatStrip24h() returns nil in 'tsm' mode")
    check(ns.Pricing.GetItemHeatmap(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemHeatmap() returns nil in 'tsm' mode")
    check(type(ns.Pricing.GetSnapshotSystemMeta()) == "table", "GetSnapshotSystemMeta() remains unsuppressed in 'tsm' mode")
    check(not hasSourceKey(ns.GetAvailablePriceSources(), "snapshot") and hasSourceKey(ns.GetAvailablePriceSources(), "tsm"),
        "GetAvailablePriceSources() omits 'snapshot' and includes 'tsm' in 'tsm' mode")

    local pTsm, srcTsm = ns.GetItemMarketPrice(ITEM_MIN)
    check(pTsm == 650 and srcTsm == "TSM (Light)",
        "GetItemMarketPrice uses TSM (650c) and never Local Snapshot (500c) in 'tsm' mode (got "
            .. tostring(pTsm) .. ", " .. tostring(srcTsm) .. ")")
    local dTsm = ns.GetMultiSourceDemand(ITEM_MIN, ECON_ACTIVE)
    check(type(dTsm) == "table" and dTsm.demandSource == "TSM",
        "GetMultiSourceDemand uses TSM and never suppressed Local velocity in 'tsm' mode")

    app.refresh()
    GameTooltip:Hide()
    if app.ui.statusCapsule and app.ui.statusCapsule:GetScript("OnEnter") then
        app.ui.statusCapsule:GetScript("OnEnter")(app.ui.statusCapsule)
        local joinedTsm = table.concat(GameTooltip._lines or {}, "\n")
        check(joinedTsm:find("Refresh Mode: TSM Light", 1, true) ~= nil
            and joinedTsm:find("Last Snapshot (Snap): Paused (TSM Light)", 1, true) ~= nil,
            "Status capsule tooltip reports Refresh Mode: TSM Light and Paused snapshot line")
        GameTooltip:Hide()
    end

    -- 2. SetBackgroundPriceMode("none"): suppresses BOTH Local Snapshot and TSM with 0 _G.TSM_API reads
    check(ns.SetBackgroundPriceMode("none") == true, "SetBackgroundPriceMode('none') succeeds")
    tsmSpyHits = 0
    check(ns.GetBackgroundPriceMode() == "none", "GetBackgroundPriceMode() returns 'none'")
    check(ns.IsLocalSnapshotSuppressed() == true, "IsLocalSnapshotSuppressed() is true in 'none' mode")
    check(ns.IsTSMOptInEnabled() == false and ns.IsTSMAvailable() == false, "TSM disabled in 'none' mode")
    check(ns.HasRawSnapshots() == true and ns.HasSnapshots() == false, "HasSnapshots() suppressed in 'none' mode while HasRawSnapshots() stays true")
    check(ns.QueryLocalSnapshot(ITEM_MIN, ECON_ACTIVE) == nil, "QueryLocalSnapshot() returns nil in 'none' mode")
    check(ns.Pricing.GetAllAuctionHousesForItem(ITEM_MIN, ECON_ACTIVE) == nil, "GetAllAuctionHousesForItem() returns nil in 'none' mode")
    check(ns.Pricing.GetSnapshotMeta(ECON_ACTIVE) == nil, "GetSnapshotMeta() returns nil in 'none' mode")
    check(ns.Pricing.IsSnapshotFresh(ECON_ACTIVE) == false, "IsSnapshotFresh() returns false in 'none' mode")
    check(ns.Pricing.GetItemSnapshotDepth(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemSnapshotDepth() returns nil in 'none' mode")
    check(ns.Pricing.GetItemSnapshotVelocity(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemSnapshotVelocity() returns nil in 'none' mode")
    check(ns.Pricing.GetItemHeatStrip24h(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemHeatStrip24h() returns nil in 'none' mode")
    check(ns.Pricing.GetItemHeatmap(ITEM_MIN, ECON_ACTIVE) == nil, "GetItemHeatmap() returns nil in 'none' mode")
    check(type(ns.Pricing.GetSnapshotSystemMeta()) == "table", "GetSnapshotSystemMeta() remains unsuppressed in 'none' mode")
    check(not hasSourceKey(ns.GetAvailablePriceSources(), "snapshot") and not hasSourceKey(ns.GetAvailablePriceSources(), "tsm"),
        "GetAvailablePriceSources() omits both 'snapshot' and 'tsm' in 'none' mode")

    local pNoneMode, srcNoneMode = ns.GetItemMarketPrice(ITEM_MIN)
    local dNoneMode = ns.GetMultiSourceDemand(ITEM_MIN, ECON_ACTIVE)
    check(pNoneMode == nil and srcNoneMode == nil, "GetItemMarketPrice returns nil in 'none' mode without manual AH scan")
    check(dNoneMode == nil or (dNoneMode.demandSource ~= "TSM" and dNoneMode.demandSource ~= "Blizz"),
        "GetMultiSourceDemand suppresses both TSM and Local Snapshot in 'none' mode")
    app.refresh()
    GameTooltip:Hide()
    if app.ui.statusCapsule and app.ui.statusCapsule:GetScript("OnEnter") then
        app.ui.statusCapsule:GetScript("OnEnter")(app.ui.statusCapsule)
        local joinedNone = table.concat(GameTooltip._lines or {}, "\n")
        check(joinedNone:find("Refresh Mode: None (Manual AH)", 1, true) ~= nil
            and joinedNone:find("Last Snapshot (Snap): Paused (None (Manual AH))", 1, true) ~= nil,
            "Status capsule tooltip reports Refresh Mode: None (Manual AH) and Paused snapshot line")
        GameTooltip:Hide()
    end
    check(tsmSpyHits == 0, "Zero _G.TSM_API reads in 'none' mode (got " .. tostring(tsmSpyHits) .. ")")

    -- 3. SetBackgroundPriceMode("local"): re-enables Local Snapshot and keeps 0 _G.TSM_API reads
    check(ns.SetBackgroundPriceMode("local") == true, "SetBackgroundPriceMode('local') succeeds")
    tsmSpyHits = 0
    check(ns.GetBackgroundPriceMode() == "local", "GetBackgroundPriceMode() returns 'local'")
    check(ns.IsLocalSnapshotSuppressed() == false, "IsLocalSnapshotSuppressed() is false in 'local' mode")
    check(ns.IsTSMOptInEnabled() == false and ns.IsTSMAvailable() == false, "TSM stays disabled in 'local' mode")
    check(ns.HasRawSnapshots() == true and ns.HasSnapshots() == true, "HasSnapshots() returns true in 'local' mode")
    local qLocal = ns.QueryLocalSnapshot(ITEM_MIN, ECON_ACTIVE)
    check(qLocal == 500, "QueryLocalSnapshot() returns 500c in 'local' mode (got " .. tostring(qLocal) .. ")")
    check(type(ns.Pricing.GetAllAuctionHousesForItem(ITEM_MIN, ECON_ACTIVE)) == "table", "GetAllAuctionHousesForItem() works in 'local' mode")
    check(type(ns.Pricing.GetSnapshotMeta(ECON_ACTIVE)) == "table", "GetSnapshotMeta() works in 'local' mode")
    check(ns.Pricing.IsSnapshotFresh(ECON_ACTIVE) == true, "IsSnapshotFresh() returns true in 'local' mode")
    check(type(ns.Pricing.GetItemSnapshotDepth(ITEM_MIN, ECON_ACTIVE)) == "table", "GetItemSnapshotDepth() works in 'local' mode")
    check(type(ns.Pricing.GetItemSnapshotVelocity(ITEM_MIN, ECON_ACTIVE)) == "table", "GetItemSnapshotVelocity() works in 'local' mode")
    check(type(ns.Pricing.GetItemHeatStrip24h(ITEM_MIN, ECON_ACTIVE)) == "table", "GetItemHeatStrip24h() works in 'local' mode")
    check(type(ns.Pricing.GetItemHeatmap(ITEM_MIN, ECON_ACTIVE)) == "table", "GetItemHeatmap() works in 'local' mode")
    check(hasSourceKey(ns.GetAvailablePriceSources(), "snapshot") and not hasSourceKey(ns.GetAvailablePriceSources(), "tsm"),
        "GetAvailablePriceSources() includes 'snapshot' and omits 'tsm' in 'local' mode")

    local pLoc, srcLoc = ns.GetItemMarketPrice(ITEM_MIN)
    check(pLoc == 500 and srcLoc == "Snapshot",
        "GetItemMarketPrice uses Local Snapshot (500c) in 'local' mode (got " .. tostring(pLoc) .. ", " .. tostring(srcLoc) .. ")")
    app.refresh()
    GameTooltip:Hide()
    if app.ui.statusCapsule and app.ui.statusCapsule:GetScript("OnEnter") then
        app.ui.statusCapsule:GetScript("OnEnter")(app.ui.statusCapsule)
        local joinedLoc = table.concat(GameTooltip._lines or {}, "\n")
        check(joinedLoc:find("Refresh Mode: Local Snapshot", 1, true) ~= nil
            and joinedLoc:find("Paused", 1, true) == nil,
            "Status capsule tooltip reports Refresh Mode: Local Snapshot without Paused")
        GameTooltip:Hide()
    end
    check(tsmSpyHits == 0, "Zero _G.TSM_API reads in 'local' mode (got " .. tostring(tsmSpyHits) .. ")")

    -- Clean up synthetic snapshots & mode state
    MerchantMasterDB.backgroundPriceMode = nil
    MerchantMasterDB.useTSMPrices = false
    MerchantMasterDB.priceSource = "auto"
    if hostEnv.clearSyntheticSnapshots then hostEnv.clearSyntheticSnapshots() end
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end

---------------------------------------------------------------------------------------------------
-- (g) Finding #2 Regression: Pre-hydrated ns.snapshotParsed MUST NOT leak into SniperEngine
--     (BuildGapShortlist / ScanSnapshotForVendorDeals / ScanSnapshotForDEDeals) once suppressed
---------------------------------------------------------------------------------------------------
do
    local SE = ns.SniperEngine
    check(type(SE) == "table", "SniperEngine loaded for hydrated-snapshot suppression regression")
    local ITEM_GAP = ITEM_MIN
    local ITEM_VEND = 98761
    local ITEM_DE = 98762

    rawset(_G, "TSM_API", spyProxy)
    tsmSpyEnabled = true
    MerchantMasterDB.ahPrices = {}
    MerchantMasterDB.lastRefreshAt = nil
    MerchantMasterDB.economy = "auto"

    local origGetItemInfo = _G.GetItemInfo
    local origCGetItemInfo = _G.C_Item and _G.C_Item.GetItemInfo
    local origGetItemInfoInstant = _G.GetItemInfoInstant
    local origCGetItemInfoInstant = _G.C_Item and _G.C_Item.GetItemInfoInstant
    local origDEBreakdown = ns.GetItemDEBreakdown
    local function mockItemInfo(id)
        if id == ITEM_VEND then
            return "Synthetic Vendor Blade", "|cffffffff|Hitem:98761|h[Synthetic Vendor Blade]|h|r", 1, 20, 1, "Weapon", "Swords", 1, "INVTYPE_WEAPON", 134400, 5000, 2, 7
        elseif id == ITEM_DE then
            return "Synthetic Green Axe", "|cff1eff00|Hitem:98762|h[Synthetic Green Axe]|h|r", 2, 45, 40, "Weapon", "Axes", 1, "INVTYPE_WEAPON", 134400, 400, 2, 0
        end
        if origGetItemInfo then return origGetItemInfo(id) end
    end
    local function mockItemInfoInstant(id)
        if id == ITEM_DE then
            return ITEM_DE, "Weapon", "Axes", "INVTYPE_WEAPON", 134400, 2, 0
        end
        if origGetItemInfoInstant then return origGetItemInfoInstant(id) end
    end
    _G.GetItemInfo = mockItemInfo
    if _G.C_Item then _G.C_Item.GetItemInfo = mockItemInfo end
    _G.GetItemInfoInstant = mockItemInfoInstant
    if _G.C_Item then _G.C_Item.GetItemInfoInstant = mockItemInfoInstant end
    ns.GetItemDEBreakdown = function(id, ...)
        if id == ITEM_DE then
            return {
                netCopper = 15000,
                grossCopper = 15800,
                quality = 2,
                ilvl = 45,
                primarySummary = "2x Vision Dust",
            }
        end
        if origDEBreakdown then return origDEBreakdown(id, ...) end
    end

    hostEnv.loadSyntheticSnapshots({
        econ = ECON_ACTIVE,
        items = {
            [ITEM_GAP] = {
                minBuyout = 500,
                marketValue = 4000,
                historical = 4000,
                qty = 30,
                numAuctions = 6,
                dailySold = 12.5,
                obsHours = 24,
                confidence = 3,
            },
            [ITEM_VEND] = {
                minBuyout = 1000,
                marketValue = 5000,
                historical = 5000,
                qty = 3,
                numAuctions = 2,
            },
            [ITEM_DE] = {
                minBuyout = 500,
                marketValue = 2000,
                historical = 2000,
                qty = 2,
                numAuctions = 2,
            },
        },
        system = [[return {v=1,exportedAt=1794360000,region="eu",credsSet=true,dbBytes=1024,totalRuns=3}]],
    })

    local function countSnapshotSourced(list)
        local n = 0
        for _, row in ipairs(list or {}) do
            if type(row) == "table" and row.source == "Snapshot" then
                n = n + 1
            end
        end
        return n
    end

    -- 1. Hydrate ns.snapshotParsed[ECON_ACTIVE] in Local Snapshot mode first and confirm SniperEngine finds deals
    check(ns.SetBackgroundPriceMode("local") == true, "Regression setup enters 'local' mode")
    local hydratedPrice = ns.QueryLocalSnapshot(ITEM_GAP, ECON_ACTIVE)
    check(hydratedPrice == 500, "QueryLocalSnapshot hydrates ns.snapshotParsed in 'local' mode")
    check(type(ns.snapshotParsed) == "table" and type(ns.snapshotParsed[ECON_ACTIVE]) == "table"
        and type(ns.snapshotParsed[ECON_ACTIVE].items) == "table"
        and ns.snapshotParsed[ECON_ACTIVE].items[ITEM_GAP] ~= nil,
        "ns.snapshotParsed['" .. tostring(ECON_ACTIVE) .. "'] is hydrated in memory before mode switch")

    SE.ClearVendorDeals()
    SE.ClearDEDeals()
    local localGap = SE.BuildGapShortlist({
        econ = ECON_ACTIVE,
        minDailySales = 1,
        minProfitCopper = 100,
        ignorePlayerGold = true,
        maxItems = 20,
    })
    local localVend = SE.ScanSnapshotForVendorDeals(ECON_ACTIVE, { minProfitCopper = 100 })
    local localDE = SE.ScanSnapshotForDEDeals(ECON_ACTIVE, { deMinProfitCopper = 100 })
    check(countSnapshotSourced(localGap) >= 1,
        "Baseline 'local' mode BuildGapShortlist returns >=1 Snapshot item (got " .. tostring(countSnapshotSourced(localGap)) .. ")")
    check(countSnapshotSourced(localVend) >= 1,
        "Baseline 'local' mode ScanSnapshotForVendorDeals returns >=1 Snapshot deal (got " .. tostring(countSnapshotSourced(localVend)) .. ")")
    check(countSnapshotSourced(localDE) >= 1,
        "Baseline 'local' mode ScanSnapshotForDEDeals returns >=1 Snapshot deal (got " .. tostring(countSnapshotSourced(localDE)) .. ")")

    -- 2. Switch to "tsm" (TSM Light) and "none" (None (Manual AH)) WITHOUT wiping ns.snapshotParsed
    for _, supMode in ipairs({ "tsm", "none" }) do
        check(ns.SetBackgroundPriceMode(supMode) == true, "Switch hydrated state to '" .. supMode .. "' mode")
        check(type(ns.snapshotParsed[ECON_ACTIVE]) == "table" and ns.snapshotParsed[ECON_ACTIVE].items[ITEM_GAP] ~= nil,
            "ns.snapshotParsed['" .. tostring(ECON_ACTIVE) .. "'] remains cached in memory during '" .. supMode .. "' mode")

        SE.ClearVendorDeals()
        SE.ClearDEDeals()
        local supGap = SE.BuildGapShortlist({
            econ = ECON_ACTIVE,
            minDailySales = 1,
            minProfitCopper = 100,
            ignorePlayerGold = true,
            maxItems = 20,
        })
        local supVend = SE.ScanSnapshotForVendorDeals(ECON_ACTIVE, { minProfitCopper = 100 })
        local supDE = SE.ScanSnapshotForDEDeals(ECON_ACTIVE, { deMinProfitCopper = 100 })

        check(countSnapshotSourced(supGap) == 0,
            "BuildGapShortlist returns 0 Snapshot items when suppressed in '" .. supMode .. "' mode (got "
                .. tostring(countSnapshotSourced(supGap)) .. ")")
        check(countSnapshotSourced(supVend) == 0,
            "ScanSnapshotForVendorDeals returns 0 Snapshot deals when suppressed in '" .. supMode .. "' mode (got "
                .. tostring(countSnapshotSourced(supVend)) .. ")")
        check(countSnapshotSourced(supDE) == 0,
            "ScanSnapshotForDEDeals returns 0 Snapshot deals when suppressed in '" .. supMode .. "' mode (got "
                .. tostring(countSnapshotSourced(supDE)) .. ")")
    end

    -- Restore mocks, SniperEngine deals, and DB/snapshot state
    SE.ClearVendorDeals()
    SE.ClearDEDeals()
    _G.GetItemInfo = origGetItemInfo
    if _G.C_Item then _G.C_Item.GetItemInfo = origCGetItemInfo end
    _G.GetItemInfoInstant = origGetItemInfoInstant
    if _G.C_Item then _G.C_Item.GetItemInfoInstant = origCGetItemInfoInstant end
    ns.GetItemDEBreakdown = origDEBreakdown
    MerchantMasterDB.backgroundPriceMode = nil
    MerchantMasterDB.useTSMPrices = false
    MerchantMasterDB.priceSource = "auto"
    if hostEnv.clearSyntheticSnapshots then hostEnv.clearSyntheticSnapshots() end
    if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end

-- Restore original _G.TSM_API
rawset(_G, "TSM_API", origTSM)

print("PASS tsm_light_mode: " .. tostring(hostEnv.assertions()) .. " assertions, 0 failures")
