-- Console Diagnostics, Telemetry, Setup & Settings Verification Suite (Pure Lua 5.1)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, createdFrames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local check = hostEnv.check
local app = ns.app
local CE = ns.ConsoleEngine
local UI = ns.UIConsole
local Theme = ns.Theme
local assertions = 0

local function assertCheck(cond, msg)
	assertions = assertions + 1
	check(cond, msg)
end

assertCheck(type(CE) == "table", "ns.ConsoleEngine loaded")
assertCheck(type(UI) == "table", "ns.UIConsole loaded")
assertCheck(app.consoleProvider ~= nil and app.ui.consoleView ~= nil, "Console provider registered and mounted")
assertCheck(not UI.IsShown(), "Console UI stays hidden/lazy-built until opened")
assertCheck(not UI._state.built, "Console UI does not build child frames at startup")

-- Trigger ADDON_LOADED / PLAYER_LOGIN via host_fixture eventFrame if not yet initialized
if not app.charKey and hostEnv.eventFrame and hostEnv.eventFrame._scripts.OnEvent then
	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame, "ADDON_LOADED", "MerchantMaster")
	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame, "PLAYER_LOGIN")
end

---------------------------------------------------------------------------------------------------
-- 1. Standalone Defaults: 13 SavedTables, Hidden Snapshot/SQLite Surfaces, redactNames=true
---------------------------------------------------------------------------------------------------
do
	assertCheck(UI._state.bundleOpts and UI._state.bundleOpts.redactNames == true,
		"Console Debug Bundle defaults to redactNames == true")
	assertCheck(CE.HasSnapshotExtension() == false and CE.HasMapPinsExtension() == false,
		"Standalone starts with no snapshot or map-pins extensions registered")

	local stStandalone = CE.CollectStorageSnapshot()
	assertCheck(type(stStandalone) == "table" and type(stStandalone.ram) == "table",
		"CollectStorageSnapshot returns RAM metrics standalone")
	assertCheck(stStandalone.ram.merchantMasterKB > 2000 and stStandalone.ram.snapshotsKB == 0,
		"Standalone RAM reports MerchantMaster memory and 0 snapshots memory")
	assertCheck(type(stStandalone.savedTables) == "table" and #stStandalone.savedTables == 13,
		"Standalone CollectStorageSnapshot exposes 13 SavedVariables tables, got " .. tostring(stStandalone.savedTables and #stStandalone.savedTables))
	assertCheck(type(stStandalone.sqliteTables) == "table" and #stStandalone.sqliteTables == 0,
		"Standalone CollectStorageSnapshot hides SQLite tables (0 rows)")
	assertCheck(stStandalone.staticCatalog.items > 100 and stStandalone.staticCatalog.recipes > 1000,
		"Static catalog item/recipe counts populated")

	-- Registering MapPins companion adds the 14th SavedVariables table (mapPins)
	local prevMapPins = app.mapPinsProvider
	MerchantMasterAPI.RegisterMapPins({
		apiVersion = 1,
		version = "1.0.0-test",
		Init = function() end,
		OnEvent = function() end,
		InvalidateOwnership = function() end,
		GetPinCount = function() return 42 end,
	})
	local stWithPins = CE.CollectStorageSnapshot()
	assertCheck(#stWithPins.savedTables == 14,
		"CollectStorageSnapshot exposes 14 SavedVariables tables when MapPins companion is registered, got " .. tostring(#stWithPins.savedTables))
	app.mapPinsProvider = prevMapPins

	-- Standalone Console UI hides console_setup, Snapshot Storage KPI, and SQLite rows
	app.togglePanel("console_overview")
	assertCheck(app.activeTab == "console_overview" and UI.IsShown() and UI._state.built,
		"Opening Console builds UI lazily and activates console_overview")
	assertCheck(UI._state.subTabBar and UI._state.subTabBar.buttons.console_setup
		and not UI._state.subTabBar.buttons.console_setup:IsShown(),
		"Standalone Console hides Setup sub-tab button")
	local ovStandalone = UI._state.overviewView
	assertCheck(ovStandalone and ovStandalone.kpis and ovStandalone.kpis[2] and not ovStandalone.kpis[2].frame:IsShown(),
		"Standalone Console Overview hides Snapshot Storage (Disk) KPI card")
	app.setTab("console_database")
	assertCheck(#UI._state.dbItems == 13,
		"Standalone Database inspector lists strictly 13 SavedVariables tables (0 SQLite), got " .. tostring(#UI._state.dbItems))
	app.setTab("console_setup")
	assertCheck(UI.GetActiveSubTab() == "console_overview",
		"Standalone console_setup redirects safely to console_overview")
	app.setTab("dashboard")
end

---------------------------------------------------------------------------------------------------
-- 2. Snapshot Companion Registration & SYSTEM Ingestion Does Not Clobber Item Price Cache
---------------------------------------------------------------------------------------------------
do
	hostEnv.setMockAddon("MerchantMaster_Snapshots", { enabled = true, loaded = true, memKB = 640.0, version = "1.0.0" })
	local okExt = MerchantMasterAPI.RegisterSnapshotExtension({
		apiVersion = 1,
		version = "1.0.0",
		BuildSetupView = function(parent)
			local lbl = parent:CreateFontString(nil, "OVERLAY")
			lbl:SetText("Companion Setup Mounted")
		end,
	})
	assertCheck(okExt == true and CE.HasSnapshotExtension() == true,
		"MerchantMasterAPI.RegisterSnapshotExtension registers snapshot companion cleanly")

	local beforeEcon = "Normal-Horde"
	ns.IngestSnapshotData("META", beforeEcon, [[return {v=1,updatedAt=1794359000,source="blizzard",windowDays=30,itemCount=100,heatmapCount=1}]])
	local priorMeta = ns.Pricing.GetSnapshotMeta(beforeEcon)
	assertCheck(priorMeta ~= nil and priorMeta.itemCount == 100, "Price snapshot meta loaded before SYSTEM ingest")

	ns.IngestSnapshotData("SYSTEM", "_global", [[return {
		v = 1,
		exportedAt = 1794360000,
		region = "eu",
		credsSet = true,
		intervalMin = 15,
		retentionDays = 30,
		exportCapBytes = 8388608,
		exportBytes = 1048576,
		truncated = false,
		taskStatus = "Ready",
		taskEnabled = true,
		houseMap = "2:114=Normal-Horde",
		dbBytes = 4194304,
		walBytes = 32768,
		shmBytes = 32768,
		localDataDirBytes = 4400000,
		pageCount = 1024,
		pageSize = 4096,
		freelist = 2,
		journalMode = "wal",
		logBytes = 8192,
		logPolls = 48,
		log304 = 41,
		logExports = 7,
		logErrors = 0,
		totalRuns = 19,
		blizzRuns = 19,
		tsmRuns = 0,
		errRuns = 0,
		lastError = "",
		tables = {
			{ n = "houses", r = 1, c = 6, f = "house_id, region, realm_slug, faction, economy_key, updated_at" },
			{ n = "snapshots", r = 19, c = 6, f = "snapshot_id, house_id, source, fetched_at, item_count, lot_count" },
			{ n = "item_prices", r = 6400, c = 8, f = "snapshot_id, item_id, min_buyout, market_value, num_auctions" },
		},
	}]])

	local sysMeta = ns.Pricing.GetSnapshotSystemMeta()
	assertCheck(type(sysMeta) == "table" and sysMeta.v == 1, "SYSTEM telemetry parsed into Pricing")
	assertCheck(sysMeta.region == "eu" and sysMeta.credsSet == true, "SYSTEM region & credsSet preserved")
	assertCheck(type(sysMeta.tables) == "table" and #sysMeta.tables == 3, "SYSTEM sqlite table descriptors preserved")
	local afterMeta = ns.Pricing.GetSnapshotMeta(beforeEcon)
	assertCheck(afterMeta ~= nil and afterMeta.itemCount == 100 and (ns.snapshotRaw["_global"] == nil),
		"SYSTEM ingestion does not pollute ns.snapshotRaw or overwrite item snapshot meta")

	local st = CE.CollectStorageSnapshot()
	assertCheck(st.ram.merchantMasterKB > 2000 and st.ram.snapshotsKB >= 600, "CollectStorageSnapshot reads AddOn memory with companion loaded")
	assertCheck(type(st.savedTables) == "table" and #st.savedTables == 13,
		"CollectStorageSnapshot keeps 13 core SavedVariables tables without MapPins, got " .. tostring(st.savedTables and #st.savedTables))
	assertCheck(type(st.sqliteTables) == "table" and #st.sqliteTables == 3, "CollectStorageSnapshot includes 3 SQLite tables when companion registered")
end

---------------------------------------------------------------------------------------------------
-- 3. Persistent Manual AH Scan Counters & Refresh Summary
---------------------------------------------------------------------------------------------------
do
	CE.RecordAHScan("full", { items = 4200, elapsed = 38.4, economy = "Normal-Horde" })
	CE.RecordAHScan("partial", {})
	CE.RecordAHScan("single", { itemID = 2447 })
	CE.RecordAHScan("deep_lot", { items = 12 })

	local ref = CE.GetRefreshSummary()
	assertCheck(ref.manualFullScans >= 1 and ref.manualPartialScans >= 1
		and ref.manualSingleRefreshes >= 1 and ref.manualDeepLotScans >= 1,
		"Manual AH scan counters accumulate in MerchantMasterDB.consoleStats")
	assertCheck(ref.lastFullScanItems == 4200 and math.abs(ref.lastFullScanSec - 38.4) < 0.01,
		"Last full AH scan items and duration recorded")

	-- Exercise MarketScan.CancelMarketScan hook -> partial counter increments
	if ns.MarketScan and ns.MarketScan.CancelMarketScan then
		local prevPartial = MerchantMasterDB.consoleStats.partialScans
		local prevFull = MerchantMasterDB.consoleStats.fullScans
		local ms = ns.MarketScan
		-- Only increments when state.active was true; CE.RecordAHScan directly verified above, ensure safe when idle
		ms.CancelMarketScan()
		assertCheck(MerchantMasterDB.consoleStats.partialScans == prevPartial
			and MerchantMasterDB.consoleStats.fullScans == prevFull,
			"CancelMarketScan when idle is a safe no-op on counters")
	end
end

---------------------------------------------------------------------------------------------------
-- 4. Zero-Overhead Profiler OFF vs ON Verification
---------------------------------------------------------------------------------------------------
do
	CE.SetPerfEnabled(false)
	CE.ResetPerfMetrics()
	assertCheck(not CE.IsPerfEnabled() and ns._consolePerfOn == false, "Profiler defaults to OFF")

	local origDebugStop = _G.debugprofilestop
	local fakeClock = 100.0
	local stopCalls = 0
	_G.debugprofilestop = function()
		stopCalls = stopCalls + 1
		fakeClock = fakeClock + 1.25
		return fakeClock
	end

	local storeMod = ns.Analytics and ns.Analytics.Store
	if storeMod and storeMod.Init then storeMod.Init() end
	app.togglePanel("dashboard")
	app.refresh()
	if storeMod and storeMod.Append and not storeMod.readOnly then
		local r = storeMod.Append({
			char = app.charKey or "StandalonePlayer-Forever",
			econ = "Normal-Horde",
			type = "AH_SELL",
			itemID = 2447,
			qty = 2,
			total = 190,
			unit = 100,
			time = _G.time(),
			extra = { gross = 200, fee = 10 },
		})
		assertCheck(r ~= nil, "Store.Append succeeds with profiler OFF")
	end

	assertCheck(stopCalls == 0,
		"Zero-overhead guarantee: debugprofilestop called 0 times when Console profiler is OFF, got " .. tostring(stopCalls))
	local offSnap = CE.GetPerfSnapshot()
	assertCheck(offSnap.txTotal == 0 and #offSnap.uiByTab == 0,
		"Zero timing buckets recorded when profiler is OFF")

	-- Now opt IN and verify transaction + UI refresh timings record accurately
	CE.SetPerfEnabled(true)
	assertCheck(CE.IsPerfEnabled() and ns._consolePerfOn == true, "Profiler toggled ON")
	app.togglePanel("console_perf")
	app.refresh()
	if storeMod and storeMod.Append and not storeMod.readOnly then
		local r2 = storeMod.Append({
			char = app.charKey or "StandalonePlayer-Forever",
			econ = "Normal-Horde",
			type = "AH_SELL",
			itemID = 2447,
			qty = 3,
			total = 285,
			unit = 100,
			time = _G.time() + 1,
			extra = { gross = 300, fee = 15 },
		})
		assertCheck(r2 ~= nil, "Store.Append succeeds with profiler ON")
	end

	assertCheck(stopCalls >= 4, "debugprofilestop invoked for UI refresh and Tx append when ON, got " .. tostring(stopCalls))
	local onSnap = CE.GetPerfSnapshot()
	assertCheck(onSnap.txTotal >= 1 and onSnap.txMaxMs > 0, "Tx timing captured when profiler ON")
	assertCheck(#onSnap.uiByTab >= 1, "UI refresh timing captured when profiler ON")

	CE.SetPerfEnabled(false)
	CE.ResetPerfMetrics()
	_G.debugprofilestop = origDebugStop
end

---------------------------------------------------------------------------------------------------
-- 5. Support Debugger Copy-Paste Bundle (ASCII, Redaction, Version, Companions & Secret Isolation)
---------------------------------------------------------------------------------------------------
do
	MerchantMasterDB.client_secret = "SHOULD_NEVER_EXPORT_SECRET"
	MerchantMasterDB.authToken = "SHOULD_NEVER_EXPORT_TOKEN"
	MerchantMasterDB.myPassword = "SHOULD_NEVER_EXPORT_PW"

	local expectedVer = ns.GetAddonVersion()
	local plainBundle = CE.BuildDebugBundle({
		includeSettings = true,
		includeDatabase = true,
		includePerf = true,
		includeLogs = true,
		redactNames = false,
	})
	assertCheck(type(plainBundle) == "string" and #plainBundle > 200, "Debug bundle builds non-empty text")
	assertCheck(not plainBundle:find("[^\9\10\13\32-\126]"), "Debug bundle is strictly pure ASCII")
	assertCheck(plainBundle:find("addonVersion=" .. expectedVer, 1, true) ~= nil,
		"Debug bundle reports live ns.GetAddonVersion() (" .. tostring(expectedVer) .. ")")
	assertCheck(plainBundle:find("MerchantMaster_Snapshots=loaded(v=1.0.0,api=1)", 1, true) ~= nil
		and plainBundle:find("MerchantMaster_MapPins=absent", 1, true) ~= nil,
		"Debug bundle reports exact companion status/version/apiVersion lines")
	assertCheck(plainBundle:find("StandalonePlayer", 1, true) ~= nil and plainBundle:find("Forever", 1, true) ~= nil,
		"Unredacted debug bundle includes char/realm")
	assertCheck(plainBundle:find("SHOULD_NEVER_EXPORT", 1, true) == nil,
		"Sensitive secret/token/password keys are stripped from debug bundle")

	local redBundle = CE.BuildDebugBundle({
		includeSettings = true,
		includeDatabase = true,
		includePerf = true,
		includeLogs = true,
		redactNames = true,
	})
	assertCheck(redBundle:find("%[REDACTED%]") ~= nil
		and redBundle:find("char=%[REDACTED%] realm=%[REDACTED%]") ~= nil,
		"Redacted debug bundle masks char and realm names")

	MerchantMasterDB.client_secret = nil
	MerchantMasterDB.authToken = nil
	MerchantMasterDB.myPassword = nil
end

---------------------------------------------------------------------------------------------------
-- 8. UI Navigation, Themes/Skins, Bidirectional Settings Sync, Slash Commands & Two-Click Confirm
---------------------------------------------------------------------------------------------------
do
	app.togglePanel("console_overview")
	assertCheck(app.activeTab == "console_overview" and UI.IsShown() and UI._state.built,
		"Opening Console builds UI lazily and activates console_overview")
	for _, sub in ipairs({ "console_database", "console_perf", "console_setup", "console_settings", "console_ui", "console_data", "console_overview" }) do
		app.setTab(sub)
		assertCheck(app.activeTab == sub and UI.GetActiveSubTab() == sub and UI.IsShown(),
			"Switching to " .. sub .. " activates corresponding Console view")
	end

	app.setTab("console_database")
	assertCheck(#UI._state.dbItems >= 14, "Database inspector lists SQLite + SavedVariables tables")

	app.setTab("console_perf")
	UI._state.perfView.regenerateBundle()
	assertCheck(#(UI._state.perfView.bundleBox:GetText() or "") > 100,
		"Debug bundle viewer generates copyable bundle in EditBox")

	-- Test Dark, Light, and Goblin skin transitions with Console visible
	Theme.SetMode("light")
	Theme.SetMode("dark")
	app.applyUiSkin("goblin")
	assertCheck(Theme.GetSkin() == "goblin" and UI.IsShown(), "Console stays visible and healthy in Goblin skin")
	app.applyUiSkin("standard")

	-- Bidirectional Settings Sync, Minimap Move, & Legacy Removal
	app.setTab("console_settings")
	local coldCtrl = UI._state.settingsControls.coldFilterCheck
	local mmCtrl = UI._state.settingsControls.minimapCheck
	assertCheck(mmCtrl ~= nil and coldCtrl ~= nil and app.ui.optSmartFilterColdCheck ~= nil, "Console Settings and Blizzard Options controls exposed")
	assertCheck(UI._state.settingsControls.legacyCheck == nil and app.ui.optLegacyPriceCheck == nil and app.ui.optBuiltInBuyerCheck == nil,
		"Legacy Price Addons and Auctionator Buyer Mode checkboxes are removed from Console & Blizzard Options")
	assertCheck(app.ui.simpleViewCheck == nil and app.ui.simpleViewPane == nil and ns.EvaluateSimpleRow == nil,
		"Legacy Simplify Overview controls and row adapter are removed")
	assertCheck(MerchantMasterDB.simpleView == nil, "Legacy MerchantMasterDB.simpleView is cleaned up")
	assertCheck(coldCtrl and coldCtrl.label and (coldCtrl.label:GetText() or ""):find("Leveling guide: Smart filter", 1, true) ~= nil,
		"Cold item filter explicitly mentions Leveling guide")

	local origHide = MerchantMasterDB.minimap and MerchantMasterDB.minimap.hide == true
	mmCtrl:SetChecked(origHide)
	mmCtrl:GetScript("OnClick")(mmCtrl, "LeftButton")
	assertCheck(((MerchantMasterDB.minimap and MerchantMasterDB.minimap.hide) == true) == (not origHide),
		"Clicking Minimap Button in Console Settings updates MerchantMasterDB.minimap.hide")
	SlashCmdList.MERCHANTMASTER("minimap")
	assertCheck(mmCtrl:GetChecked() == (not origHide),
		"Running /mm minimap syncs back to Console Settings minimap checkbox")

	-- Addon UI Sub-Tab & Live Hover Preview
	app.setTab("console_ui")
	local uv = UI._state.uiView
	assertCheck(uv ~= nil and UI._state.uiControls.skinBtns.goblin ~= nil, "Addon UI exposes skin preview buttons")
	assertCheck(UI._state.uiControls.minimapCheck == nil and UI._state.uiControls.simpleCheck == nil,
		"Addon UI no longer contains Minimap or removed Simplify Overview checkboxes")
	local goblinBtn = uv.skinBtns.goblin
	assertCheck(Theme.GetSkin() == "standard", "Standard skin active before preview")
	goblinBtn:GetScript("OnEnter")(goblinBtn)
	assertCheck(Theme.GetSkin() == "standard", "Hovering Goblin previews without mutating active skin")
	assertCheck((uv.pHeaderFs:GetText() or ""):find("Hovering", 1, true) ~= nil
		and (uv.pMetaFs:GetText() or ""):find("goblin", 1, true) ~= nil,
		"Live UI preview header/meta reflects hovered Goblin skin")
	goblinBtn:GetScript("OnLeave")(goblinBtn)
	assertCheck((uv.pHeaderFs:GetText() or ""):find("Active", 1, true) ~= nil
		and (uv.pMetaFs:GetText() or ""):find("standard", 1, true) ~= nil,
		"Leaving preview button restores active skin in Live Preview")
	goblinBtn:Click("LeftButton")
	assertCheck(Theme.GetSkin() == "goblin", "Clicking skin button in Addon UI switches live skin")

	local stripsBtn = uv.tableBtns.t3_strips
	local fixedPriceBtn = uv.priceBtns.full_fixed
	stripsBtn:GetScript("OnEnter")(stripsBtn)
	fixedPriceBtn:GetScript("OnEnter")(fixedPriceBtn)
	assertCheck((uv.pMetaFs:GetText() or ""):find("t3_strips", 1, true) ~= nil
		and (uv.pMetaFs:GetText() or ""):find("full_fixed", 1, true) ~= nil,
		"Hovering Table Style and Price Format updates Live Preview")
	stripsBtn:GetScript("OnLeave")(stripsBtn)
	fixedPriceBtn:GetScript("OnLeave")(fixedPriceBtn)
	stripsBtn:Click("LeftButton")
	fixedPriceBtn:Click("LeftButton")
	assertCheck(Theme.GetTableStyle() == "t3_strips" and Theme.GetPriceDisplayMode() == "full_fixed",
		"Clicking Table Style and Price Format applies both settings")

	app.applyUiSkin("standard")
	app.applyTableStyle("t5_ruled")
	app.applyPriceDisplayMode("compact")

	-- Slash Routing (including /mm ui and /mm data)
	SlashCmdList.MERCHANTMASTER("setup")
	assertCheck(app.activeTab == "console_setup", "/mm setup opens console_setup")
	SlashCmdList.MERCHANTMASTER("debug")
	assertCheck(app.activeTab == "console_perf", "/mm debug opens console_perf")
	SlashCmdList.MERCHANTMASTER("db")
	assertCheck(app.activeTab == "console_database", "/mm db opens console_database")
	SlashCmdList.MERCHANTMASTER("ui")
	assertCheck(app.activeTab == "console_ui", "/mm ui opens console_ui")
	SlashCmdList.MERCHANTMASTER("data")
	assertCheck(app.activeTab == "console_data", "/mm data opens console_data")
	SlashCmdList.MERCHANTMASTER("options")
	assertCheck(app.activeTab == "console_settings", "/mm options opens console_settings")
	SlashCmdList.MERCHANTMASTER("console")
	assertCheck(app.activeTab == "console_overview", "/mm console opens console_overview")

	-- Data & Maintenance Tooltips + Two-Click Confirm
	app.setTab("console_data")
	local dv = UI._state.dataView
	assertCheck(dv ~= nil and dv.clearSellerBtn ~= nil, "Data & Maintenance view exposes maintenance buttons")
	local tipTargets = {
		{ "pack_ah_history", dv.actionBtns.pack_ah_history },
		{ "forget_live_ah", dv.actionBtns.forget_live_ah },
		{ "queue_wealth_snapshot", dv.actionBtns.queue_wealth_snapshot },
		{ "clear_seller_stats", dv.actionBtns.clear_seller_stats },
		{ "reset_ledger_errors", dv.actionBtns.reset_ledger_errors },
		{ "clear_sniper_cache", dv.actionBtns.clear_sniper_cache },
		{ "previewBtn", dv.previewBtn },
		{ "pruneBtn", dv.pruneBtn },
		{ "exportCsvBtn", dv.exportCsvBtn },
	}
	for _, pair in ipairs(tipTargets) do
		local name, btn = pair[1], pair[2]
		assertCheck(btn ~= nil and btn:GetScript("OnEnter") ~= nil, "Data button " .. name .. " exposes hover tooltip")
		GameTooltip:ClearLines()
		btn:GetScript("OnEnter")(btn)
		assertCheck(GameTooltip:NumLines() >= 2, "Hovering " .. name .. " populates GameTooltip explanations")
		btn:GetScript("OnLeave")(btn)
	end

	MerchantMasterDB.sellerStats = { ["Normal-Horde"] = { incompleteItems = { [2447] = true } } }
	local clearBtn = dv.clearSellerBtn
	clearBtn:Click("LeftButton")
	assertCheck(UI._state.armedAction == "clear_seller_stats"
		and next(MerchantMasterDB.sellerStats) ~= nil,
		"First click on destructive Clear Seller Cache arms confirmation without wiping data")
	clearBtn:Click("LeftButton")
	assertCheck(UI._state.armedAction == nil and next(MerchantMasterDB.sellerStats) == nil,
		"Second click confirms and clears SellerStats cache")

	-- KPI height (104px), font size (<= 20pt), hover tooltip, and no double-counting of SQLite dir bytes
	app.setTab("console_overview")
	local ov = UI._state.overviewView
	assertCheck(ov ~= nil and #ov.kpis == 4, "Overview exposes 4 KPI cards")
	assertCheck(ov.kpis[2].titleFs:GetText() == "Snapshot Storage (Disk)",
		"KPI 2 clearly labeled Snapshot Storage (Disk)")
	GameTooltip:ClearLines()
	ov.kpis[2].frame:GetScript("OnEnter")(ov.kpis[2].frame)
	assertCheck(GameTooltip:NumLines() >= 2, "Hovering Snapshot Storage KPI explains SQLite disk vs Lua export cap")
	ov.kpis[2].frame:GetScript("OnLeave")(ov.kpis[2].frame)
	for i, kpi in ipairs(ov.kpis) do
		assertCheck(kpi.frame:GetHeight() == 104, "Overview KPI card " .. i .. " uses 104px height")
		if kpi.valueFs and kpi.valueFs.GetFont then
			local _, fsSize = kpi.valueFs:GetFont()
			assertCheck((fsSize or 99) <= 20, "Overview KPI card " .. i .. " value font <= 20pt")
		end
	end
	assertCheck(ov.kpis[2].valueFs:GetText() == CE.FormatBytes(4400000),
		"KPI 2 uses max(sqliteFiles, localDataDirBytes) instead of double-counting: got " .. tostring(ov.kpis[2].valueFs:GetText()))

	-- Static refresh guarantee: app.refresh() (crafts/bag events) does NOT recompute Console;
	-- only Refresh button or opening/re-entering Console refreshes it.
	local memCalls, snapCalls = 0, 0
	local origUpdateMem = _G.UpdateAddOnMemoryUsage
	local origCUpdateMem = _G.C_AddOns and _G.C_AddOns.UpdateAddOnMemoryUsage
	local origCollect = CE.CollectStorageSnapshot
	_G.UpdateAddOnMemoryUsage = function(...)
		memCalls = memCalls + 1
		if origUpdateMem then return origUpdateMem(...) end
	end
	if _G.C_AddOns then
		_G.C_AddOns.UpdateAddOnMemoryUsage = _G.UpdateAddOnMemoryUsage
	end
	CE.CollectStorageSnapshot = function(...)
		snapCalls = snapCalls + 1
		return origCollect(...)
	end

	app.refresh()
	app.refresh()
	assertCheck(memCalls == 0 and snapCalls == 0,
		string.format("Background app.refresh() keeps Console static (memCalls=%d, snapCalls=%d)", memCalls, snapCalls))

	UI._state.refreshBtn:Click("LeftButton")
	assertCheck(memCalls == 1 and snapCalls == 1,
		string.format("Clicking Refresh updates Console once (memCalls=%d, snapCalls=%d)", memCalls, snapCalls))

	app.setTab("dashboard")
	app.setTab("console_overview")
	assertCheck(memCalls == 2 and snapCalls == 2,
		string.format("Opening Console after leaving updates once (memCalls=%d, snapCalls=%d)", memCalls, snapCalls))

	_G.UpdateAddOnMemoryUsage = origUpdateMem
	if _G.C_AddOns then _G.C_AddOns.UpdateAddOnMemoryUsage = origCUpdateMem end
	CE.CollectStorageSnapshot = origCollect

	app.setTab("dashboard")
end

---------------------------------------------------------------------------------------------------
-- 9. CollectStorageSnapshot Ignores Poisoned Global _G.app for MapPins Options
---------------------------------------------------------------------------------------------------
do
	local prevGlobalApp = _G.app
	local prevMapPinsDB = _G.MerchantMaster_MapPinsDB
	local prevProvider = app.mapPinsProvider

	_G.MerchantMaster_MapPinsDB = nil
	_G.app = {
		mapPinsProvider = {
			GetOptions = function()
				return { poisoned = true }
			end,
		},
	}
	app.mapPinsProvider = {
		GetOptions = function()
			return { enabled = true, allProfessions = false, hideKnown = true }
		end,
	}

	local snap = CE.CollectStorageSnapshot()
	local foundMapEntry = nil
	for _, entry in ipairs(snap.savedTables or {}) do
		if entry.id == "MerchantMaster_MapPinsDB.mapPins" then
			foundMapEntry = entry
			break
		end
	end
	assertCheck(foundMapEntry ~= nil and foundMapEntry.rows == 3,
		"CollectStorageSnapshot reads ns.app.mapPinsProvider instead of _G.app (rows="
			.. tostring(foundMapEntry and foundMapEntry.rows) .. ")")

	_G.app = prevGlobalApp
	_G.MerchantMaster_MapPinsDB = prevMapPinsDB
	app.mapPinsProvider = prevProvider
end

print(string.format("CONSOLE_TESTS: PASS (%d assertions)", assertions))
