-- Snapshot Freshness UI Status Suite: UI_AHRefresh, Status Capsule, and Economy Tooltip (Lua 5.1)
local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, _, _ = dofile(S .. "host_fixture.lua")
local app = ns.app
local ui = app.ui
local db = MerchantMasterDB
local Theme = ns.Theme

local count = 0
local function check(ok, msg)
	count = count + 1
	if not ok then
		error("SNAPSHOT UI STATUS FAIL [" .. count .. "]: " .. tostring(msg), 2)
	end
end

local function tooltipHas(needle)
	for _, line in ipairs(GameTooltip._lines or {}) do
		if type(line) == "string" and line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function near(col, ref)
	return type(col) == "table" and type(ref) == "table"
		and math.abs((col[1] or -1) - (ref[1] or -2)) < 0.02
		and math.abs((col[2] or -1) - (ref[2] or -2)) < 0.02
		and math.abs((col[3] or -1) - (ref[3] or -2)) < 0.02
end

-- Save original state so nothing leaks
local origTime = _G.time
local origPriceSource = db.priceSource
local origEnableLegacy = db.enableLegacyPriceAddons
local origEconomy = db.economy
local origLastRefresh = db.lastRefreshAt
local origTsmLastUpdate = db.tsmLastUpdate
local origAhPrices = db.ahPrices
local origTsmSynced = ns.tsmSyncedEconomies
local origSnapRaw = ns.snapshotRaw
local origSnapParsed = ns.snapshotParsed
local origSnapHeat = ns.snapshotHeatmapCache
local origPreferFn = ns.Pricing and ns.Pricing.ShouldPreferSnapshotOverTSM

local nowTs = 1795400000
_G.time = function() return nowTs end

local function resetState(legacyOn)
	db.economy = "auto"
	db.priceSource = "auto"
	db.enableLegacyPriceAddons = legacyOn == true
	db.lastRefreshAt = nil
	db.tsmLastUpdate = nil
	db.ahPrices = {}
	ns.tsmSyncedEconomies = {}
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	ns.snapshotHeatmapCache = {}
	if ns.Pricing then ns.Pricing.ShouldPreferSnapshotOverTSM = origPreferFn end
	ns.InvalidateEconomyDetectCache()
	ns.InvalidatePriceCache()
end

local function loadMeta(econKey, updatedAt, source, itemCount, heatmapCount, windowDays)
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"META",
		econKey,
		string.format(
			[[return {v=1,updatedAt=%d,source=%q,windowDays=%d,itemCount=%d,heatmapCount=%d}]],
			updatedAt, source, windowDays or 30, itemCount or 3661, heatmapCount or 1240
		)
	)
end

---------------------------------------------------------------------------------------------------
-- 1. UI_AHRefresh.GetSnapshotFreshness boundaries & labels
---------------------------------------------------------------------------------------------------
do
	local g1 = ns.AHRefresh.GetSnapshotFreshness({ updatedAt = nowTs - 720, source = "blizzard" }, nowTs)
	check(g1.status == "green" and g1.text == "Blizz 12m" and g1.isSnapshot == true,
		"12m blizzard snapshot should be green 'Blizz 12m', got " .. tostring(g1.status) .. " / " .. tostring(g1.text))

	local g2 = ns.AHRefresh.GetSnapshotFreshness({ updatedAt = nowTs - 4499, source = "blizzard+tsm" }, nowTs)
	check(g2.status == "green" and g2.text == "Blizz 74m",
		"4499s (<75m) hybrid snapshot should be green 'Blizz 74m', got " .. tostring(g2.status) .. " / " .. tostring(g2.text))

	local o1 = ns.AHRefresh.GetSnapshotFreshness({ updatedAt = nowTs - 4500, source = "tsm" }, nowTs)
	check(o1.status == "orange" and o1.text == "Snap 75m",
		"4500s (75m) tsm snapshot should be orange 'Snap 75m', got " .. tostring(o1.status) .. " / " .. tostring(o1.text))

	local o2 = ns.AHRefresh.GetSnapshotFreshness({ updatedAt = nowTs - 10800, source = "tsm" }, nowTs)
	check(o2.status == "orange" and o2.text == "Snap 180m",
		"10800s (180m) snapshot should stay orange 'Snap 180m', got " .. tostring(o2.status) .. " / " .. tostring(o2.text))

	local r1 = ns.AHRefresh.GetSnapshotFreshness({ updatedAt = nowTs - 10801, source = "blizzard" }, nowTs)
	check(r1.status == "red" and r1.text == "Blizz 180m",
		"10801s (>180m) snapshot should be red, got " .. tostring(r1.status) .. " / " .. tostring(r1.text))

	local badFuture = ns.AHRefresh.GetSnapshotFreshness({ updatedAt = nowTs + 60, source = "blizzard" }, nowTs)
	check(badFuture.status == "red", "Future snapshot timestamp must be red")
	local badNil = ns.AHRefresh.GetSnapshotFreshness(nil, nowTs)
	check(badNil.status == "red", "Nil snapshot meta must be red")
end

---------------------------------------------------------------------------------------------------
-- 2. UI_AHRefresh controller Update() with & without snapshot loaded
---------------------------------------------------------------------------------------------------
do
	resetState()
	local refresh = ui.winChrome and ui.winChrome.ahRefresh
	check(refresh ~= nil, "winChrome.ahRefresh controller exists")

	-- 2a. No snapshot, no manual scan -> Never scanned (red)
	refresh:Update()
	check(refresh.state.status == "red" and refresh.state.text == "Never scanned" and not refresh.state.isSnapshot,
		"Without snapshot or scan, AHRefresh stays red 'Never scanned', got " .. tostring(refresh.state.text))

	-- 2b. Fresh Blizzard snapshot (12m), no manual scan -> Blizz 12m (green) + tooltip
	loadMeta("Normal-Horde", nowTs - 720, "blizzard", 3661, 1240, 30)
	refresh:Update()
	check(refresh.state.status == "green" and refresh.state.text == "Blizz 12m" and refresh.state.isSnapshot == true,
		"With 12m Blizzard snapshot, AHRefresh should be green 'Blizz 12m', got " .. tostring(refresh.state.status) .. " / " .. tostring(refresh.state.text))
	refresh.button:GetScript("OnEnter")(refresh.button)
	check(tooltipHas("Blizz 12m") and tooltipHas("Last snapshot:"),
		"AHRefresh tooltip should show 'Blizz 12m' and 'Last snapshot:'")
	refresh.button:GetScript("OnLeave")(refresh.button)

	-- 2c. Older manual scan (60m) does NOT beat 12m Blizzard snapshot; tooltip shows both timestamps
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 3600 }
	refresh:Update()
	check(refresh.state.status == "green" and refresh.state.text == "Blizz 12m" and refresh.state.manualAt == nowTs - 3600,
		"12m snapshot should beat 60m manual scan, got " .. tostring(refresh.state.text))
	refresh.button:GetScript("OnEnter")(refresh.button)
	check(tooltipHas("Last snapshot:") and tooltipHas("Last full scan:"),
		"AHRefresh tooltip should include both snapshot and manual full scan times when older manual scan exists")
	refresh.button:GetScript("OnLeave")(refresh.button)

	-- 2d. Fresher manual Live AH scan (2m) beats 12m Blizzard snapshot + symmetric tooltip shows both timestamps
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 120 }
	refresh:Update()
	check(refresh.state.status == "green" and refresh.state.text == "Fresh (120s ago)" and not refresh.state.isSnapshot,
		"Fresher 2m manual AH scan must beat 12m snapshot, got " .. tostring(refresh.state.text))
	check(refresh.state.snapAt == nowTs - 720,
		"Manual-fresher refresh.state.snapAt must record snapshot updatedAt, got " .. tostring(refresh.state.snapAt))
	refresh.button:GetScript("OnEnter")(refresh.button)
	check(tooltipHas("Last full scan:") and tooltipHas("Last snapshot:"),
		"Symmetric AHRefresh tooltip must show both 'Last full scan:' and 'Last snapshot:' when manual scan is newer")
	refresh.button:GetScript("OnLeave")(refresh.button)

	-- 2e. Aging TSM snapshot (90m) with no manual scan -> Snap 90m (orange)
	db.ahPrices["Normal-Horde"] = {}
	loadMeta("Normal-Horde", nowTs - 5400, "tsm", 2500, 900, 30)
	refresh:Update()
	check(refresh.state.status == "orange" and refresh.state.text == "Snap 90m",
		"90m TSM snapshot should be orange 'Snap 90m', got " .. tostring(refresh.state.status) .. " / " .. tostring(refresh.state.text))

	-- 2f. Stale Blizzard snapshot (200m) -> Blizz 200m (red)
	loadMeta("Normal-Horde", nowTs - 12000, "blizzard", 3661, 1240, 30)
	refresh:Update()
	check(refresh.state.status == "red" and refresh.state.text == "Blizz 200m",
		"200m Blizzard snapshot should be red 'Blizz 200m', got " .. tostring(refresh.state.status) .. " / " .. tostring(refresh.state.text))
end

---------------------------------------------------------------------------------------------------
-- 3. Status Capsule text & dot color in MerchantMaster.lua (Default OFF & Opt-in ON)
---------------------------------------------------------------------------------------------------
do
	Theme.SetMode("dark", true)
	app.panel:Show()
	app.setTab("dashboard")

	-- 3A. Default standalone with no snapshot/scan shows 'No AH Scan Yet'
	resetState(false)
	app.refresh()
	check(ui.statusSyncFs:GetText() == "No AH Scan Yet",
		"Default OFF with no snapshot/scan should show 'No AH Scan Yet', got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- Live AH 2m ago (no snapshot) -> "AH 2m"
	resetState(false)
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 120 }
	db.lastRefreshAt = nowTs - 120
	app.refresh()
	check(ui.statusSyncFs:GetText() == "AH 2m",
		"Default OFF with 2m Live AH scan should show 'AH 2m', got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- Live AH 20s ago -> "AH just now"
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 20 }
	db.lastRefreshAt = nowTs - 20
	app.refresh()
	check(ui.statusSyncFs:GetText() == "AH just now",
		"Default OFF with 20s Live AH scan should show 'AH just now', got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- 5m Blizzard snapshot beats 20m Live AH -> "Blizz 5m"
	resetState(false)
	loadMeta("Normal-Horde", nowTs - 300, "blizzard", 3661, 1240, 30)
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 1200 }
	db.lastRefreshAt = nowTs - 1200
	app.refresh()
	check(ui.statusSyncFs:GetText() == "Blizz 5m",
		"Default OFF: 5m Blizzard snapshot must beat 20m Live AH ('Blizz 5m'), got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- 2m Live AH beats 12m Blizzard snapshot -> "AH 2m"
	resetState(false)
	loadMeta("Normal-Horde", nowTs - 720, "blizzard", 3661, 1240, 30)
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 120 }
	db.lastRefreshAt = nowTs - 120
	app.refresh()
	check(ui.statusSyncFs:GetText() == "AH 2m",
		"Default OFF: 2m Live AH must beat 12m Blizzard snapshot ('AH 2m'), got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- 8h Blizzard snapshot with no Live AH (no 90m cutoff, ignores tsmLastUpdate) -> "Blizz 8h"
	resetState(false)
	db.tsmLastUpdate = nowTs - 600
	loadMeta("Normal-Horde", nowTs - 28800, "blizzard", 3661, 1240, 30)
	app.refresh()
	check(ui.statusSyncFs:GetText() == "Blizz 8h",
		"Default OFF: 8h Blizzard snapshot must show 'Blizz 8h' (no 90m cutoff), got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- Legacy db.priceSource = "tsm_min" is automatically normalized to "auto" (SavedVariables migration)
	resetState(false)
	db.priceSource = "tsm_min"
	loadMeta("Normal-Horde", nowTs - 300, "blizzard", 3661, 1240, 30)
	app.refresh()
	check(ui.statusSyncFs:GetText() == "Blizz 5m",
		"Standalone: migrated tsm_min must behave as Auto ('Blizz 5m'), got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")
	check(db.priceSource == "auto", "SavedVariables migration normalizes legacy db.priceSource='tsm_min' -> 'auto'")
	check(ui.sourceBtn:GetText() == "Src: Auto",
		"Standalone: sourceBtn must show 'Src: Auto' after migrating tsm_min, got '" .. tostring(ui.sourceBtn:GetText()) .. "'")

	-- Explicit priceSource="snapshot" -> Blizz even when > 90m old (e.g. 2h)
	resetState(false)
	db.priceSource = "snapshot"
	loadMeta("Normal-Horde", nowTs - 7200, "blizzard", 3661, 1240, 30)
	app.refresh()
	check(ui.statusSyncFs:GetText() == "Blizz 2h",
		"Explicit snapshot mode (2h blizzard) should show 'Blizz 2h', got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- Explicit priceSource="snapshot" with no snapshot loaded -> non-destructive fallback to 'auto' ('No AH Scan Yet')
	resetState(false)
	db.priceSource = "snapshot"
	app.refresh()
	check(ui.statusSyncFs:GetText() == "No AH Scan Yet" and db.priceSource == "snapshot" and ns.GetEffectivePriceSource() == "auto",
		"Explicit snapshot mode without loaded snapshot falls back non-destructively to 'No AH Scan Yet', got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")

	-- Auto + fresh Blizzard snapshot (12m) -> "Blizz 12m" + green status dot
	resetState(false)
	loadMeta("Normal-Horde", nowTs - 720, "blizzard", 3661, 1240, 30)
	app.refresh()
	check(ui.statusSyncFs:GetText() == "Blizz 12m",
		"Auto + fresh Blizzard snapshot should show 'Blizz 12m', got '" .. tostring(ui.statusSyncFs:GetText()) .. "'")
	check(ui.statusServerFs:GetText():find("Blizz 12m", 1, true) ~= nil,
		"statusServerFs should include 'Blizz 12m', got '" .. tostring(ui.statusServerFs:GetText()) .. "'")
	check(near(ui.statusDot._vertexColor, Theme.PALETTES.dark.accentGreen),
		"Status dot should tint green when fresh Blizzard snapshot is active")
end

---------------------------------------------------------------------------------------------------
-- 4. showEconomyTooltip Local Snapshot (Pure Standalone — no TSM AppData section)
---------------------------------------------------------------------------------------------------
do
	-- 4a. Without snapshot -> omits Local Snapshot section
	resetState(false)
	app.showEconomyTooltip(app.panel)
	check(tooltipHas("Auction House Economy Filter"), "Economy tooltip header present")
	check(not tooltipHas("Local Snapshot:"), "Economy tooltip omits Local Snapshot section when no snapshot is loaded")
	check(not tooltipHas("TSM AppData Synced Economies:"),
		"Standalone: economy tooltip never shows 'TSM AppData Synced Economies:'")

	-- 4b. With Blizzard API snapshot alongside Saved Live AH Scans
	resetState(false)
	db.ahPrices["Normal-Horde"] = { _scannedAt = nowTs - 3600 }
	loadMeta("Normal-Horde", nowTs - 720, "blizzard", 3661, 1240, 30)
	app.showEconomyTooltip(app.panel)
	check(not tooltipHas("TSM AppData Synced Economies:"),
		"Standalone: economy tooltip omits TSM AppData section")
	check(tooltipHas("Saved Live AH Scans:"), "Saved Live AH Scans section present")
	check(tooltipHas("Local Snapshot:"), "Local Snapshot section header present")
	check(tooltipHas("Normal-Horde (Blizzard API)"), "Blizzard API source label present")
	check(tooltipHas("12m ago"), "12m ago age present")
	check(tooltipHas("3,661 items"), "Formatted itemCount present")
	check(tooltipHas("1,240 heatmaps"), "Formatted heatmapCount present")
	check(tooltipHas("30d"), "windowDays (30d) present")
end

---------------------------------------------------------------------------------------------------
-- 5. Pure Standalone UI Surface: Legacy Toggles Removed & Clean Dropdowns
---------------------------------------------------------------------------------------------------
do
	resetState(false)
	check(ui.optLegacyPriceCheck == nil, "Legacy ui.optLegacyPriceCheck checkbox removed")
	check(ui.optBuiltInBuyerCheck == nil, "Legacy ui.optBuiltInBuyerCheck checkbox removed")
	check(app.setEnableLegacyPriceAddons == nil, "Legacy app.setEnableLegacyPriceAddons removed")
	check(ns.Pricing.ShouldPreferSnapshotOverTSM == nil, "Legacy ShouldPreferSnapshotOverTSM removed")

	-- Tooltip on sourceBtn does not mention /mm legacy
	ui.sourceBtn:GetScript("OnEnter")(ui.sourceBtn)
	check(tooltipHas("Auction Price Source") and not tooltipHas("/mm legacy"),
		"sourceBtn tooltip shows Auction Price Source without removed /mm legacy hint")
	ui.sourceBtn:GetScript("OnLeave")(ui.sourceBtn)

	-- Dropdowns expose strictly 3 standalone price sources and omit tsm_alt / region
	local origOpenDropDown = Theme.OpenDropDown
	local lastDropOpts, lastDropCur
	Theme.OpenDropDown = function(_, opts, curKey)
		lastDropOpts, lastDropCur = opts, curKey
	end

	db.priceSource = "tsm_min"
	ui.sourceBtn:GetScript("OnClick")(ui.sourceBtn, "LeftButton")
	check(type(lastDropOpts) == "table" and #lastDropOpts == 2 and lastDropCur == "auto",
		"Standalone without snapshots: sourceBtn dropdown has 2 items and normalized key 'auto', got " .. tostring(lastDropOpts and #lastDropOpts) .. " / " .. tostring(lastDropCur))
	ui.optSourceBtn:GetScript("OnClick")(ui.optSourceBtn, "LeftButton")
	check(type(lastDropOpts) == "table" and #lastDropOpts == 2 and lastDropCur == "auto",
		"Standalone without snapshots: optSourceBtn dropdown has 2 items and normalized key 'auto'")
	loadMeta("Normal-Horde", nowTs - 300, "blizzard", 3661, 1240, 30)
	ui.sourceBtn:GetScript("OnClick")(ui.sourceBtn, "LeftButton")
	check(type(lastDropOpts) == "table" and #lastDropOpts == 3 and lastDropCur == "auto",
		"With active snapshot: sourceBtn dropdown exposes 3 items including snapshot, got " .. tostring(lastDropOpts and #lastDropOpts))
	ui.optSourceBtn:GetScript("OnClick")(ui.optSourceBtn, "LeftButton")
	check(type(lastDropOpts) == "table" and #lastDropOpts == 3 and lastDropCur == "auto",
		"With active snapshot: optSourceBtn dropdown exposes 3 items including snapshot")
	ui.econBtn:GetScript("OnClick")(ui.econBtn, "LeftButton")
	local hasLegacyEcon = false
	for _, opt in ipairs(lastDropOpts or {}) do
		if opt.key == "tsm_alt" or opt.key == "region" then hasLegacyEcon = true end
	end
	check(not hasLegacyEcon, "Standalone: economy dropdown omits 'tsm_alt' and 'region'")

	Theme.OpenDropDown = origOpenDropDown
end

-- Restore original globals & state
_G.time = origTime
db.priceSource = origPriceSource
db.enableLegacyPriceAddons = origEnableLegacy
db.economy = origEconomy
db.lastRefreshAt = origLastRefresh
db.tsmLastUpdate = origTsmLastUpdate
db.ahPrices = origAhPrices
ns.tsmSyncedEconomies = origTsmSynced
ns.snapshotRaw = origSnapRaw
ns.snapshotParsed = origSnapParsed
ns.snapshotHeatmapCache = origSnapHeat
if ns.Pricing then ns.Pricing.ShouldPreferSnapshotOverTSM = origPreferFn end
ns.InvalidateEconomyDetectCache()
ns.InvalidatePriceCache()

print(string.format("PASS: snapshot_ui_status (%d assertions, 0 failures)", count))
