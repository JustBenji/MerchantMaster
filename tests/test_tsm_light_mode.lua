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

-- Restore original _G.TSM_API
rawset(_G, "TSM_API", origTSM)

print("PASS tsm_light_mode: " .. tostring(hostEnv.assertions()) .. " assertions, 0 failures")
