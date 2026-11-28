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

	-- Standalone Console UI keeps Snapshot Settings visible with standalone guide,
	-- while still hiding Snapshot Storage KPI and SQLite rows
	app.togglePanel("console_overview")
	assertCheck(app.activeTab == "console_overview" and UI.IsShown() and UI._state.built,
		"Opening Console builds UI lazily and activates console_overview")
	local setupTabBtn = UI._state.subTabBar and UI._state.subTabBar.buttons.console_setup
	assertCheck(setupTabBtn == nil and UI._state.setupView == nil,
		"Standalone Console completely removes legacy Snapshot Builder sub-tab and view")
	local setup2TabBtn = UI._state.subTabBar and UI._state.subTabBar.buttons.console_setup2
	assertCheck(setup2TabBtn and setup2TabBtn:IsShown() and setup2TabBtn.fs and setup2TabBtn.fs:GetText() == "MerchantMasterSync",
		"Standalone Console exposes primary MerchantMasterSync sub-tab button")
	-- Console -> Settings no longer exposes legacyBuilderCheck
	app.setTab("console_settings")
	assertCheck(UI._state.settingsControls and UI._state.settingsControls.legacyBuilderCheck == nil,
		"Console -> Settings removes legacyBuilderCheck")
	app.setTab("console_overview")
	local ovStandalone = UI._state.overviewView
	assertCheck(ovStandalone and ovStandalone.kpis and ovStandalone.kpis[2] and not ovStandalone.kpis[2].frame:IsShown(),
		"Standalone Console Overview hides Snapshot Storage (Disk) KPI card")
	app.setTab("console_database")
	assertCheck(#UI._state.dbItems == 13,
		"Standalone Database inspector lists strictly 13 SavedVariables tables (0 SQLite), got " .. tostring(#UI._state.dbItems))
	local dbViewStandalone = UI._state.databaseView
	assertCheck(dbViewStandalone and dbViewStandalone.snapStorageCard and dbViewStandalone.svStorageCard,
		"Console -> Database exposes dedicated snapStorageCard and svStorageCard")
	assertCheck((dbViewStandalone.snapHeadline:GetText() or ""):find("Not Installed", 1, true) ~= nil,
		"Standalone Database snapStorageCard shows External Disk DB: Not Installed (0 B)")
	assertCheck((dbViewStandalone.sumBody:GetText() or ""):find("External SQLite Disk DB: 0 B", 1, true) ~= nil,
		"Standalone Database svStorageCard notes 0 B external SQLite disk DB")

	-- Legacy console_setup route redirects cleanly to Snapshot Sync (console_setup2)
	app.setTab("console_setup")
	assertCheck(UI.GetActiveSubTab() == "console_setup2" and app.activeTab == "console_setup2",
		"Legacy console_setup route redirects cleanly to console_setup2")
	local su2Standalone = UI._state.setupV2View
	assertCheck(su2Standalone and su2Standalone.statusCard and su2Standalone.statusCard:IsShown()
		and su2Standalone.orbWrap and su2Standalone.orbWrap:IsShown()
		and su2Standalone.installBtn and su2Standalone.installBtn:IsShown()
		and su2Standalone.installBtn.fs and su2Standalone.installBtn.fs:GetText() == "Install"
		and su2Standalone.advPanel and not su2Standalone.advPanel:IsShown(),
		"Standalone console_setup2 shows Apple hero Install card with collapsed Terminal/Advanced drawer")
	assertCheck((su2Standalone.stTitle:GetText() or ""):find("MerchantMasterSync", 1, true) ~= nil,
		"Standalone MerchantMasterSync title shows MerchantMasterSync before install")
	su2Standalone.installBtn:Click("LeftButton")
	assertCheck(su2Standalone.downloadRow and su2Standalone.downloadRow:IsShown()
		and (su2Standalone.downloadUrlBox:GetText() or ""):find("MerchantMaster-Snapshots/releases/latest", 1, true) ~= nil,
		"Clicking Install reveals desktop app release download URL")
	su2Standalone.advToggleBtn:Click("LeftButton")
	assertCheck(su2Standalone.advPanel:IsShown() and su2Standalone.winCard:IsShown() and su2Standalone.unixCard:IsShown(),
		"Expanding Terminal / Advanced reveals split Left Windows and Right Linux/macOS sync cards")
	assertCheck((su2Standalone.winInstallBox:GetText() or ""):find("py -m pip install", 1, true) ~= nil
		and (su2Standalone.winAltBox:GetText() or ""):find("python -m pip install", 1, true) ~= nil
		and (su2Standalone.linuxInstallBox:GetText() or ""):find("install_linux.py --sync-mode github", 1, true) ~= nil
		and (su2Standalone.macInstallBox:GetText() or ""):find("python3 -m pip install", 1, true) ~= nil,
		"Expanded Terminal / Advanced drawer populates Windows, Linux/Steam Deck, and macOS commands")
	su2Standalone.advToggleBtn:Click("LeftButton")
	assertCheck(not su2Standalone.advPanel:IsShown(),
		"Clicking Terminal / Advanced again collapses the drawer cleanly")

	-- Disabled addon state (present in AddOns folder, unchecked for current character) shows clear Esc -> AddOns guidance
	hostEnv.setMockAddon("MerchantMaster_Snapshots", { enabled = false, loaded = false, memKB = 0, version = "1.1.0" })
	assertCheck(CE.GetAddonState("MerchantMaster_Snapshots") == "disabled",
		"GetAddonState reports 'disabled' when MerchantMaster_Snapshots exists but is unloaded")
	UI.Refresh("test_disabled")
	assertCheck((su2Standalone.stTitle:GetText() or ""):find("Enable Pack in WoW", 1, true) ~= nil
		and (su2Standalone.stBody:GetText() or ""):find("Esc -> AddOns", 1, true) ~= nil,
		"Disabled companion shows Enable Pack in WoW and Esc -> AddOns instructions in Snapshot Sync")
	app.setTab("console_database")
	assertCheck((dbViewStandalone.snapHeadline:GetText() or ""):find("Data Pack Unchecked in Esc -> AddOns", 1, true) ~= nil,
		"Disabled companion shows Data Pack Unchecked in Esc -> AddOns in Database -> AH Snapshot Storage card")

	-- Enabled-on-disk but unloaded companion (e.g. restored after deleting folder while WoW was running) shows Restart WoW guidance
	hostEnv.setMockAddon("MerchantMaster_Snapshots", { enabled = true, loaded = false, memKB = 0, version = "1.1.0" })
	assertCheck(CE.GetAddonState("MerchantMaster_Snapshots") == "unloaded",
		"GetAddonState reports 'unloaded' when MerchantMaster_Snapshots is enabled on disk but needs full WoW restart")
	UI.Refresh("test_unloaded")
	assertCheck((dbViewStandalone.snapHeadline:GetText() or ""):find("Restart WoW to Load Data Pack", 1, true) ~= nil,
		"Unloaded enabled companion shows Restart WoW to Load Data Pack in Database tab")
	app.setTab("console_setup2")
	assertCheck((su2Standalone.stTitle:GetText() or ""):find("Restart WoW to Load", 1, true) ~= nil
		and (su2Standalone.stBody:GetText() or ""):find("full game restart", 1, true) ~= nil,
		"Unloaded enabled companion shows Restart WoW to Load instead of falsely claiming Esc -> AddOns unchecked")
	hostEnv.setMockAddon("MerchantMaster_Snapshots", nil)

	-- Standalone fallback presets & OS-aware command builder
	local fallbackPresets = CE.GetServerPresets()
	assertCheck(type(fallbackPresets) == "table" and #fallbackPresets == 13,
		"CE.GetServerPresets() returns 13 default WoW Forever presets standalone, got " .. tostring(fallbackPresets and #fallbackPresets))
	local winCmds = CE.BuildSetupCommands({ osMode = "windows", region = "eu", presetKey = "Normal-Horde" })
	local linCmds = CE.BuildSetupCommands({ osMode = "linux", region = "us", presetKey = "PvP-Alliance" })
	local macCmds = CE.BuildSetupCommands({ osMode = "macos", region = "eu", presetKey = "RP-Horde" })
	assertCheck(winCmds and winCmds.guiCmd:find("python -m snapshot_builder setup-gui", 1, true) ~= nil
		and winCmds.apiKeyCmd:find("setx BLIZZARD_CLIENT_ID", 1, true) ~= nil,
		"Fallback Windows commands use python -m snapshot_builder and setx")
	assertCheck(linCmds and linCmds.guiCmd == "~/.local/bin/mm-snapshots setup-gui"
		and linCmds.configureCmd:find("--prompt-creds", 1, true) ~= nil
		and linCmds.configureCmd:find("1:110=PvP-Alliance", 1, true) ~= nil
		and linCmds.apiKeyCmd:find('--clear-houses --house "1:110=PvP-Alliance" --prompt-creds', 1, true) ~= nil,
		"Fallback Linux commands use ~/.local/bin/mm-snapshots with --prompt-creds and --clear-houses --house")
	assertCheck(macCmds and macCmds.guiCmd == "python3 -m snapshot_builder setup-gui"
		and macCmds.configureCmd:find("--prompt-creds", 1, true) ~= nil
		and macCmds.configureCmd:find("3:120=RP-Horde", 1, true) ~= nil
		and macCmds.apiKeyCmd:find('--clear-houses --house "3:120=RP-Horde" --prompt-creds', 1, true) ~= nil,
		"Fallback macOS commands use python3 -m snapshot_builder with --prompt-creds and --clear-houses --house")

	-- Standalone /mm snapshots, /mm setup, /mm builder, /mm setup1, /mm snapshots2, and /mm github all open console_setup2
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("snapshots")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"/mm snapshots opens console_setup2 standalone")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("setup")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"/mm setup opens console_setup2 standalone")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("builder")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"/mm builder redirects cleanly to console_setup2 standalone")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("setup1")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"/mm setup1 redirects cleanly to console_setup2 standalone")
	SlashCmdList.MERCHANTMASTER("snapshots2")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"/mm snapshots2 opens console_setup2 standalone")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("github")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"/mm github opens console_setup2 standalone")
	local su2 = UI._state.setupV2View
	assertCheck(su2 and su2.frame and su2.frame:IsShown()
		and su2.tsmCard == nil
		and (su2.winInstallBox:GetText() or ""):find("--sync-mode github --apply-task --sync-now", 1, true) ~= nil
		and (su2.linuxInstallBox:GetText() or ""):find("install_linux.py --sync-mode github", 1, true) ~= nil
		and (su2.macInstallBox:GetText() or ""):find("--sync-mode github --apply-task --sync-now", 1, true) ~= nil
		and (su2.winRebuildBox:GetText() or ""):find("sync --source github --force", 1, true) ~= nil
		and (su2.winUninstallBox:GetText() or ""):find("uninstall-task", 1, true) ~= nil
		and (su2.linuxRebuildBox:GetText() or ""):find("sync --source github --force", 1, true) ~= nil
		and (su2.linuxUninstallBox:GetText() or ""):find("uninstall-task", 1, true) ~= nil,
		"MerchantMasterSync hides Price Refresh Mode and keeps CLI commands inside Terminal / Advanced")
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
		dbPath = "~/.local/share/MerchantMaster/snapshots.sqlite3",
		outDir = "<WoW>/_forever_/Interface/AddOns/MerchantMaster_Snapshots",
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
	assertCheck(type(st.diskSummary) == "table"
		and st.diskSummary.addonState == "loaded"
		and st.diskSummary.sqliteBytes == (4194304 + 32768 + 32768)
		and st.diskSummary.dataDirBytes == 4400000
		and st.diskSummary.snapshotDiskTotalBytes == (4400000 + 1048576)
		and st.diskSummary.combinedTotalBytes == (4400000 + 1048576 + st.totalSavedBytes)
		and st.diskSummary.snapshotRuns == 19
		and st.diskSummary.snapshotRows == 19,
		"CollectStorageSnapshot computes accurate diskSummary totals, snapshot runs & row counts")
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
	for _, sub in ipairs({ "console_database", "console_perf", "console_setup2", "console_settings", "console_ui", "console_data", "console_overview" }) do
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

	-- Slash Routing (including /mm snapshots, /mm setup, /mm builder -> console_setup2)
	SlashCmdList.MERCHANTMASTER("snapshots")
	assertCheck(app.activeTab == "console_setup2", "/mm snapshots opens console_setup2")
	SlashCmdList.MERCHANTMASTER("snapshot")
	assertCheck(app.activeTab == "console_setup2", "/mm snapshot opens console_setup2")
	SlashCmdList.MERCHANTMASTER("setup")
	assertCheck(app.activeTab == "console_setup2", "/mm setup opens console_setup2")
	SlashCmdList.MERCHANTMASTER("builder")
	assertCheck(app.activeTab == "console_setup2", "/mm builder redirects to console_setup2")

	-- Connected MerchantMasterSync: In Sync hero + live Disk & Snapshot summary + OS command boxes + 3-way Price Refresh Mode
	local su2Conn = UI._state.setupV2View
	assertCheck(UI._state.setupView == nil and su2Conn ~= nil and su2Conn.frame and su2Conn.frame:IsShown(),
		"Connected console_setup2 is active and setupView is removed")
	assertCheck(su2Conn.advPanel and not su2Conn.advPanel:IsShown() and su2Conn.winCard and su2Conn.unixCard,
		"Connected console_setup2 keeps Terminal / Advanced collapsed by default while keeping CLI cards built")
	assertCheck((su2Conn.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"Connected status title shows In-Sync")
	assertCheck((su2Conn.stBody:GetText() or ""):find("Snapshots: 19", 1, true) ~= nil
		and (su2Conn.stBody:GetText() or ""):find("Disk: " .. CE.FormatBytes(5448576), 1, true) ~= nil,
		"Connected stBody summarizes live snapshot count and total disk size")
	assertCheck((su2Conn.stFeed:GetText() or ""):find("JustBenji/MerchantMaster-SnapshotData", 1, true) ~= nil,
		"Connected stFeed shows public GitHub snapshot feed slug")
	assertCheck((su2Conn.winInstallBox:GetText() or ""):find("snapshot_builder configure --sync-mode github", 1, true) ~= nil
		and (su2Conn.linuxInstallBox:GetText() or ""):find("install_linux.py --sync-mode github", 1, true) ~= nil
		and (su2Conn.macInstallBox:GetText() or ""):find("python3 -m snapshot_builder configure --sync-mode github", 1, true) ~= nil,
		"Connected cards display Windows, Linux, and macOS GitHub auto-sync commands")

	-- Connected Console -> Database dedicated disk storage card
	app.setTab("console_database")
	local dvConn = UI._state.databaseView
	local snapHdrTxt = dvConn and dvConn.snapHeadline and dvConn.snapHeadline:GetText() or ""
	local snapBodyTxt = dvConn and dvConn.snapBody and dvConn.snapBody:GetText() or ""
	local svHdrTxt = dvConn and dvConn.svHeadline and dvConn.svHeadline:GetText() or ""
	assertCheck(snapHdrTxt:find("Total on Disk: " .. CE.FormatBytes(5448576), 1, true) ~= nil
		and snapHdrTxt:find("19 Snapshots", 1, true) ~= nil,
		"Database snapHeadline displays total disk size and snapshot count: " .. snapHdrTxt)
	assertCheck(snapBodyTxt:find("SQLite DB: " .. CE.FormatBytes(4194304), 1, true) ~= nil
		and snapBodyTxt:find("WAL: " .. CE.FormatBytes(32768), 1, true) ~= nil
		and snapBodyTxt:find("AddOn Export: " .. CE.FormatBytes(1048576), 1, true) ~= nil
		and snapBodyTxt:find("snapshots.sqlite3", 1, true) ~= nil,
		"Database snapBody breaks down SQLite DB, WAL, Export & DB path: " .. snapBodyTxt)
	assertCheck(svHdrTxt:find("Combined Total (Disk + WoW):", 1, true) ~= nil,
		"Database svHeadline displays combined Disk + SavedVariables total: " .. svHdrTxt)

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

---------------------------------------------------------------------------------------------------
-- 10. Cold LoadOnDemand /mm snapshots & Live RegisterSnapshotExtension SyncExtensions Regression
---------------------------------------------------------------------------------------------------
do
	local savedExt = app.snapshotExtension
	local savedRaw = ns.snapshotRaw
	local savedParsed = ns.snapshotParsed
	local savedCLoad = _G.C_AddOns and _G.C_AddOns.LoadAddOn
	local savedGLoad = _G.LoadAddOn
	local loadCalls = 0

	-- Part A: Cold /mm snapshots after /reload (panel hidden, LoadOnDemand companion not yet loaded)
	app.panel:Hide()
	UI.Hide()
	app.snapshotExtension = nil
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	if type(ns.ResetSnapshotsLoadAttempt) == "function" then
		ns.ResetSnapshotsLoadAttempt()
	end

	local lazyLoader = function(name)
		if name == "MerchantMaster_Snapshots" then
			loadCalls = loadCalls + 1
			MerchantMasterAPI.RegisterSnapshotExtension({
				apiVersion = 1,
				version = "1.1.0",
				supportsOsMode = true,
			})
			return true
		end
		return false
	end
	if _G.C_AddOns then _G.C_AddOns.LoadAddOn = lazyLoader end
	_G.LoadAddOn = lazyLoader

	SlashCmdList.MERCHANTMASTER("snapshots")
	assertCheck(loadCalls >= 1 and CE.HasSnapshotExtension() == true,
		"Cold /mm snapshots triggers EnsureSnapshotsLoaded and loads LoadOnDemand MerchantMaster_Snapshots")
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2",
		"Cold /mm snapshots opens primary Snapshot Sync (console_setup2)")
	SlashCmdList.MERCHANTMASTER("builder")
	local su2Lazy = UI._state.setupV2View
	assertCheck(app.activeTab == "console_setup2" and UI.GetActiveSubTab() == "console_setup2"
		and su2Lazy and (su2Lazy.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"Connected /mm builder redirects to console_setup2 showing In-Sync status")

	-- Regression: even if app.snapshotExtension wasn't registered at load, raw snapshot data shows In-Sync
	ns.snapshotRaw = savedRaw
	ns.snapshotParsed = savedParsed
	app.snapshotExtension = nil
	UI.SyncExtensions()
	assertCheck((su2Lazy.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"MerchantMasterSync still shows In-Sync when raw snapshot data is loaded without RegisterSnapshotExtension")

	-- Part B: Late RegisterSnapshotExtension while console_setup2 is already open standalone
	if _G.C_AddOns then _G.C_AddOns.LoadAddOn = function() return false end end
	_G.LoadAddOn = function() return false end
	app.snapshotExtension = nil
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	UI.SyncExtensions()
	assertCheck((su2Lazy.stTitle:GetText() or ""):find("MerchantMasterSync", 1, true) ~= nil
		and su2Lazy.installBtn and su2Lazy.installBtn.fs and su2Lazy.installBtn.fs:GetText() == "Install",
		"SyncExtensions switches open MerchantMasterSync back to Install state when extension and raw data are absent")
	MerchantMasterAPI.RegisterSnapshotExtension({
		apiVersion = 1,
		version = "1.1.0",
		supportsOsMode = true,
	})
	assertCheck((su2Lazy.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"RegisterSnapshotExtension calls consoleProvider.SyncExtensions and flips open MerchantMasterSync to In-Sync")

	-- CLEARED marker from Delete Database shows Database Cleared even when companion extension shell stays loaded
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	ns.IngestSnapshotData("CLEARED", "_global", "1")
	UI.SyncExtensions()
	assertCheck((su2Lazy.stTitle:GetText() or ""):find("Database Cleared", 1, true) ~= nil,
		"CLEARED marker shows Database Cleared instead of In-Sync while companion add-on shell stays loaded")
	ns.IngestSnapshotData("META", "Normal-Horde", [[return {v=1,updatedAt=1795825338,source="blizzard",windowDays=30,itemCount=10}]])
	UI.SyncExtensions()
	assertCheck((su2Lazy.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"Ingesting fresh META after CLEARED clears ns.snapshotCleared and restores In-Sync")

	-- Restore environment
	if _G.C_AddOns then _G.C_AddOns.LoadAddOn = savedCLoad end
	_G.LoadAddOn = savedGLoad
	app.snapshotExtension = savedExt
	ns.snapshotRaw = savedRaw
	ns.snapshotParsed = savedParsed
	ns.snapshotCleared = false
	UI.SyncExtensions()
	app.panel:Hide()
end

---------------------------------------------------------------------------------------------------
-- 11. Feature D: Console -> Mail Sub-Tab, Settings Shortcut, Slash Routing & Presets Sync
---------------------------------------------------------------------------------------------------
do
	local savedMailPresets = _G.MerchantMasterDB.mailPresets
	_G.MerchantMasterDB.mailPresets = nil

	-- Slash routing: /mm mail and /mm mailpresets open console_mail
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("mail")
	assertCheck(app.activeTab == "console_mail" and UI.GetActiveSubTab() == "console_mail" and UI.IsShown(),
		"/mm mail opens Console -> Mail")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("mailpresets")
	assertCheck(app.activeTab == "console_mail" and UI.GetActiveSubTab() == "console_mail",
		"/mm mailpresets opens Console -> Mail")

	-- Sub-tab bar layout: console_mail sits right after console_settings and fits cleanly inside 1036px
	local bar = UI._state.subTabBar
	assertCheck(bar and bar.buttons and bar.buttons.console_mail and bar.buttons.console_mail:IsShown(),
		"Console sub-tab bar exposes visible Mail sub-tab button")
	assertCheck((bar.rightStart or 9999) < 860,
		"Console sub-tab bar leaves ample headroom inside 1036px (rightStart=" .. tostring(bar.rightStart) .. ")")
	local settingsIdx, mailIdx
	for idx, d in ipairs(bar._defs or {}) do
		if d.key == "console_settings" then settingsIdx = idx end
		if d.key == "console_mail" then mailIdx = idx end
	end
	assertCheck(settingsIdx and mailIdx and mailIdx == settingsIdx + 1,
		"Console -> Mail sub-tab appears immediately after Settings")

	-- Settings shortcut button jumps to console_mail
	app.setTab("console_settings")
	local mailJump = UI._state.settingsControls and UI._state.settingsControls.mailShortcutBtn
	assertCheck(mailJump ~= nil, "Console -> Settings exposes Mail Recipients & Safety shortcut button")
	mailJump:Click("LeftButton")
	assertCheck(app.activeTab == "console_mail" and UI.GetActiveSubTab() == "console_mail",
		"Clicking Mail Recipients & Safety button in Settings opens Console -> Mail")

	-- Mail view structure, sample preview chips when 0 saved, and EditBox >= 140px
	local mv = UI._state.mailView
	assertCheck(mv ~= nil and mv.leftCard ~= nil and mv.rightCard ~= nil, "Console -> Mail builds 60/40 split cards")
	assertCheck(mv.previewChips[1]:IsShown() and mv.previewChips[2]:IsShown() and not mv.previewChips[3]:IsShown(),
		"Live Mailbox Preview shows 2 sample preview chips when 0 presets are saved")
	assertCheck((mv.previewModeFs:GetText() or ""):find("Sample preview", 1, true) ~= nil,
		"Preview header notes sample preview when 0 presets saved")
	for _, pk in ipairs({ "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "cooking", "firstaid" }) do
		local box = mv.inputs[pk]
		assertCheck(box ~= nil and (box:GetWidth() or 0) >= 126,
			"Profession input " .. pk .. " has width >= 126px (got " .. tostring(box and box:GetWidth()) .. ")")
		local pBtn = mv.pickBtns[pk]
		assertCheck(pBtn ~= nil and (pBtn:GetWidth() or 0) >= 62,
			"Profession Pick button " .. pk .. " has width >= 62px (got " .. tostring(pBtn and pBtn:GetWidth()) .. ")")
	end
	for _, ck in ipairs({ "bank", "investmentStorage", "auction", "mainCrafter" }) do
		local box = mv.inputs[ck]
		assertCheck(box ~= nil and (box:GetWidth() or 0) >= 148,
			"Core input " .. ck .. " exists with width >= 148px (got " .. tostring(box and box:GetWidth()) .. ")")
		local pBtn = mv.pickBtns[ck]
		assertCheck(pBtn ~= nil and (pBtn:GetWidth() or 0) >= 64,
			"Core Pick button " .. ck .. " has width >= 64px (got " .. tostring(pBtn and pBtn:GetWidth()) .. ")")
	end
	mv.inputs.investmentStorage:SetText("VaultHold")
	mv.inputs.investmentStorage:GetScript("OnEnterPressed")(mv.inputs.investmentStorage)
	assertCheck(ns.MailHelper and ns.MailHelper.IsSavedMailRecipient("VaultHold") == true,
		"Investment Storage mail preset input saves recipient cleanly into MerchantMasterDB.mailPresets")
	mv.inputs.investmentStorage:SetText("")
	mv.inputs.investmentStorage:GetScript("OnEnterPressed")(mv.inputs.investmentStorage)
	assertCheck(#mv.previewChips >= 5, "Live Mailbox Preview exposes at least 5 preview chip slots")
	for i = 1, #mv.previewChips do
		assertCheck(mv.previewChips[i]:GetHeight() == 32,
			"Preview chip " .. i .. " uses 32px height (got " .. tostring(mv.previewChips[i]:GetHeight()) .. ")")
	end

	-- Editing bank & alchemy inputs updates MerchantMasterDB.mailPresets and switches preview to live presets
	mv.inputs.bank:SetText("Goldbank")
	mv.inputs.bank:GetScript("OnEnterPressed")(mv.inputs.bank)
	mv.inputs.alchemy:SetText("Elara Vance")
	mv.inputs.alchemy:GetScript("OnEnterPressed")(mv.inputs.alchemy)
	assertCheck(ns.MailHelper and ns.MailHelper.IsSavedMailRecipient("Elara Vance") == true,
		"Editing Mail tab inputs saves WoW Forever surname recipient into MerchantMasterDB.mailPresets")
	assertCheck((mv.previewModeFs:GetText() or ""):find("2 saved preset", 1, true) ~= nil,
		"Live preview switches from sample to 2 saved presets immediately")

	-- Toggling display checkboxes updates MailHelper display options & preview immediately
	mv.showIconCheck:SetChecked(false)
	mv.showIconCheck:GetScript("OnClick")(mv.showIconCheck, "LeftButton")
	mv.showNameCheck:SetChecked(false)
	mv.showNameCheck:GetScript("OnClick")(mv.showNameCheck, "LeftButton")
	mv.showRoleCheck:SetChecked(false)
	mv.showRoleCheck:GetScript("OnClick")(mv.showRoleCheck, "LeftButton")
	assertCheck(mv.previewChips[2].initFs:IsShown() and mv.previewChips[2].initFs:GetText() == "EV",
		"Unchecking all 3 display options renders 2-letter initials in live preview")

	mv.warnUnsavedCheck:SetChecked(false)
	mv.warnUnsavedCheck:GetScript("OnClick")(mv.warnUnsavedCheck, "LeftButton")
	assertCheck(ns.MailHelper.GetDisplayOptions().warnUnsaved == false,
		"Unchecking Send Mail Safety Net updates display.warnUnsaved = false")

	-- Confirm ConsoleEngine savedTables == 13 invariant STILL passes with MerchantMasterDB.mailPresets populated!
	local stAfterMail = CE.CollectStorageSnapshot()
	assertCheck(#stAfterMail.savedTables == 13,
		"savedTables remains strictly 13 after populating MerchantMasterDB.mailPresets, got " .. tostring(#stAfterMail.savedTables))

	-- Theme & skin transitions stay healthy while console_mail is active
	Theme.SetMode("light")
	Theme.SetMode("dark")
	app.applyUiSkin("goblin")
	assertCheck(UI.IsShown() and UI.GetActiveSubTab() == "console_mail",
		"Console -> Mail remains visible and healthy across theme/skin changes")
	app.applyUiSkin("standard")

	_G.MerchantMasterDB.mailPresets = savedMailPresets
	app.panel:Hide()
end

---------------------------------------------------------------------------------------------------
-- 12. 3-Way Price Refresh Mode Selector Card in Console -> Snapshot Settings
---------------------------------------------------------------------------------------------------
do
	local savedBgMode = _G.MerchantMasterDB.backgroundPriceMode
	local savedUseTSM = _G.MerchantMasterDB.useTSMPrices
	local savedPriceSrc = _G.MerchantMasterDB.priceSource
	local savedExt = app.snapshotExtension
	local savedRaw = ns.snapshotRaw
	local savedParsed = ns.snapshotParsed
	local savedTSMAPI = rawget(_G, "TSM_API")

	app.snapshotExtension = nil
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	_G.MerchantMasterDB.backgroundPriceMode = nil
	_G.MerchantMasterDB.useTSMPrices = false
	_G.MerchantMasterDB.priceSource = "auto"
	_G.TSM_API = nil

	-- Check MerchantMasterSync tab layout (collapsed Terminal/Advanced directly under statusCard, zero tsmCard)
	app.togglePanel("console_setup2")
	local su = UI._state.setupV2View
	assertCheck(su ~= nil and su.tsmCard == nil and su.modeBtns == nil,
		"Console -> MerchantMasterSync no longer renders Price Refresh Mode card")
	assertCheck(not su.advPanel:IsShown(), "Terminal / Advanced drawer starts collapsed")
	su.advToggleBtn:Click("LeftButton")
	assertCheck(su.advPanel:IsShown() and su.winCard:IsShown() and su.unixCard:IsShown(),
		"When Terminal / Advanced expands, advPanel reveals winCard and unixCard")
	su.advToggleBtn:Click("LeftButton")
	assertCheck(not su.advPanel:IsShown(),
		"When Terminal / Advanced collapses, advPanel hides cleanly")

	-- Check Console -> Settings -> Database Price Information (Manual, TSM Tool Sync, MerchantMasterSync)
	app.setTab("console_settings")
	local sv = UI._state.settingsControls
	assertCheck(sv ~= nil and sv.dbPriceCard ~= nil and sv.dbPriceStatusFs ~= nil and sv.dbPriceFeedbackFs ~= nil
		and type(sv.modeBtns) == "table" and sv.modeBtns["none"] ~= nil and sv.modeBtns["tsm"] ~= nil and sv.modeBtns["local"] ~= nil,
		"Console -> Settings exposes Database Price Information card with Manual, TSM Tool Sync, and MerchantMasterSync")
	assertCheck(sv.dbPriceCard:GetHeight() == 176,
		"dbPriceCard height is 176px (got " .. tostring(sv.dbPriceCard:GetHeight()) .. ")")
	assertCheck((sv.dbPriceStatusFs:GetText() or ""):find("Active: Manual", 1, true) ~= nil,
		"Standalone default Database Price Information status shows Active: Manual")

	-- Clicking MerchantMasterSync while not synced blocks switch and shows Open MerchantMasterSync button
	sv.modeBtns["local"]:Click("LeftButton")
	assertCheck((_G.MerchantMasterDB.backgroundPriceMode == nil or _G.MerchantMasterDB.backgroundPriceMode == "none"),
		"Clicking MerchantMasterSync when not synced does not enable local snapshot mode")
	assertCheck((sv.dbPriceFeedbackFs:GetText() or ""):find("MerchantMasterSync", 1, true) ~= nil
		and sv.openSyncTabBtn and sv.openSyncTabBtn:IsShown(),
		"Blocked MerchantMasterSync click refers user to MerchantMasterSync tab with quick button")
	sv.openSyncTabBtn:Click("LeftButton")
	assertCheck(app.activeTab == "console_setup2",
		"Open MerchantMasterSync -> button navigates straight to console_setup2")
	app.setTab("console_settings")

	-- Clicking TSM Tool Sync when TSM addon & TSM_API are absent blocks switch and shows error
	sv.modeBtns["tsm"]:Click("LeftButton")
	assertCheck((_G.MerchantMasterDB.backgroundPriceMode == nil or _G.MerchantMasterDB.backgroundPriceMode == "none"),
		"Clicking TSM Tool Sync when TSM is not installed blocks mode switch")
	assertCheck((sv.dbPriceFeedbackFs:GetText() or ""):find("TSM tool is not installed", 1, true) ~= nil
		and (not sv.openSyncTabBtn or not sv.openSyncTabBtn:IsShown()),
		"Blocked TSM Tool Sync click displays TSM tool is not installed error")

	-- When TSM_API is available, TSM Tool Sync succeeds cleanly
	_G.TSM_API = { GetCustomPriceValue = function() return 1000 end }
	sv.modeBtns["tsm"]:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.backgroundPriceMode == "tsm" and _G.MerchantMasterDB.useTSMPrices == true,
		"Clicking TSM Tool Sync when TSM is installed sets backgroundPriceMode='tsm' and useTSMPrices=true")
	assertCheck(_G.MerchantMasterDB.priceSource == "auto",
		"Clicking TSM Tool Sync keeps MerchantMasterDB.priceSource on 'auto'")
	assertCheck((sv.dbPriceStatusFs:GetText() or ""):find("Active: TSM Tool Sync", 1, true) ~= nil,
		"Database Price Information status shows Active: TSM Tool Sync when TSM is installed")

	-- Clicking Manual switches cleanly back to 'none'
	sv.modeBtns["none"]:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.backgroundPriceMode == "none" and _G.MerchantMasterDB.useTSMPrices == false,
		"Clicking Manual sets backgroundPriceMode='none' and useTSMPrices=false")
	assertCheck((sv.dbPriceStatusFs:GetText() or ""):find("Active: Manual", 1, true) ~= nil,
		"Database Price Information status shows Active: Manual")

	-- With MerchantMasterSync installed/synced: switching to MerchantMasterSync succeeds cleanly and MerchantMasterSync tab shows In-Sync
	app.snapshotExtension = savedExt
	ns.snapshotRaw = savedRaw
	ns.snapshotParsed = savedParsed
	sv.modeBtns["local"]:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.backgroundPriceMode == "local" and _G.MerchantMasterDB.useTSMPrices == false,
		"Clicking MerchantMasterSync when synced activates local mode")
	assertCheck((sv.dbPriceStatusFs:GetText() or ""):find("Active: MerchantMasterSync", 1, true) ~= nil,
		"Database Price Information status shows Active: MerchantMasterSync")
	assertCheck((su.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"MerchantMasterSync stTitle shows In-Sync")

	sv.modeBtns["tsm"]:Click("LeftButton")
	assertCheck((sv.dbPriceStatusFs:GetText() or ""):find("Active: TSM Tool Sync", 1, true) ~= nil,
		"Settings switches cleanly from MerchantMasterSync to TSM Tool Sync")
	assertCheck((su.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"MerchantMasterSync hero still shows In-Sync even when TSM is chosen in Settings")

	sv.modeBtns["none"]:Click("LeftButton")
	assertCheck((sv.dbPriceStatusFs:GetText() or ""):find("Active: Manual", 1, true) ~= nil,
		"Settings switches cleanly from TSM Tool Sync back to Manual")
	assertCheck((su.stTitle:GetText() or ""):find("In-Sync", 1, true) ~= nil,
		"MerchantMasterSync hero still shows In-Sync even when Manual is chosen in Settings")

	-- Verify ConsoleEngine settings fields documents backgroundPriceMode & useTSMPrices and keeps savedTables == 13
	local stTsm = CE.CollectStorageSnapshot()
	assertCheck(#stTsm.savedTables == 13,
		"savedTables remains strictly 13 with 3-way backgroundPriceMode setting")
	local foundSettings = nil
	for _, entry in ipairs(stTsm.savedTables) do
		if entry.id == "MerchantMasterDB.settings" then foundSettings = entry; break end
	end
	assertCheck(foundSettings ~= nil
		and (foundSettings.fields or ""):find("backgroundPriceMode", 1, true) ~= nil
		and (foundSettings.fields or ""):find("useTSMPrices", 1, true) ~= nil,
		"MerchantMasterDB.settings fields description includes backgroundPriceMode and useTSMPrices")

	-- Restore environment
	_G.MerchantMasterDB.backgroundPriceMode = savedBgMode
	_G.MerchantMasterDB.useTSMPrices = savedUseTSM
	_G.MerchantMasterDB.priceSource = savedPriceSrc
	app.snapshotExtension = savedExt
	ns.snapshotRaw = savedRaw
	ns.snapshotParsed = savedParsed
	_G.TSM_API = savedTSMAPI
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	app.panel:Hide()
end

---------------------------------------------------------------------------------------------------
-- 13. Console -> Tooltip Setup Sub-Tab (console_tooltips), Slash Routing, Live Preview & Presets
---------------------------------------------------------------------------------------------------
do
	local ttKeys = {
		"ttEnabled", "ttPriceFormat", "ttModifier",
		"ttMarketEnabled", "ttMinBuyout", "ttMarketValue", "ttListedCount", "ttVendorSell",
		"tooltipCraftCost", "ttCraftProfit", "tooltipDEValue", "ttDEArcaneSalvager",
		"tooltipDEBreakdown", "crateTooltips",
		"anTooltips", "ttAccSell", "ttAccBasis", "ttAccProfit", "ttAccLastSold",
		"ttAccSaleRate", "ttAccSlowing", "ttHideEmpty",
		"anTooltipInventory", "ttInvByChar", "ttInvHideZero", "ttInvCompact",
	}
	local savedTT = {}
	for _, k in ipairs(ttKeys) do
		savedTT[k] = _G.MerchantMasterDB[k]
	end
	local savedSample = UI._state.tooltipSampleKey

	-- Slash routing: /mm tooltips and /mm tooltip open console_tooltips
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("tooltips")
	assertCheck(app.activeTab == "console_tooltips" and UI.GetActiveSubTab() == "console_tooltips" and UI.IsShown(),
		"/mm tooltips opens Console -> Tooltip Setup")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("tooltip")
	assertCheck(app.activeTab == "console_tooltips" and UI.GetActiveSubTab() == "console_tooltips",
		"/mm tooltip opens Console -> Tooltip Setup")

	-- Sub-tab bar placement: console_tooltips sits immediately after console_mail, console_mail immediately after console_settings, rightStart < 860
	local bar = UI._state.subTabBar
	assertCheck(bar and bar.buttons and bar.buttons.console_tooltips and bar.buttons.console_tooltips:IsShown(),
		"Console sub-tab bar exposes visible Tooltip Setup sub-tab button")
	assertCheck((bar.rightStart or 9999) < 860,
		"Console sub-tab bar leaves ample headroom inside 1036px with Tooltip Setup (rightStart=" .. tostring(bar.rightStart) .. ")")
	local settingsIdx, mailIdx, ttIdx
	for idx, d in ipairs(bar._defs or {}) do
		if d.key == "console_settings" then settingsIdx = idx end
		if d.key == "console_mail" then mailIdx = idx end
		if d.key == "console_tooltips" then ttIdx = idx end
	end
	assertCheck(settingsIdx and mailIdx and mailIdx == settingsIdx + 1 and ttIdx == mailIdx + 1,
		"Console -> Mail sits immediately after Settings and Tooltip Setup immediately after Mail")

	-- Settings shortcut button jumps to console_tooltips
	app.setTab("console_settings")
	local ttJump = UI._state.settingsControls and UI._state.settingsControls.tooltipShortcutBtn
	assertCheck(ttJump ~= nil, "Console -> Settings exposes Tooltip Setup shortcut button")
	ttJump:Click("LeftButton")
	assertCheck(app.activeTab == "console_tooltips" and UI.GetActiveSubTab() == "console_tooltips",
		"Clicking Tooltip Setup button in Settings opens Console -> Tooltip Setup")

	-- Verify tooltipControls structure
	local tc = UI._state.tooltipControls
	local tv = UI._state.tooltipsView
	assertCheck(tc ~= nil and type(tc.checks) == "table" and type(tc.sampleBtns) == "table"
		and type(tc.presetBtns) == "table" and type(tc.formatBtns) == "table"
		and type(tc.modBtns) == "table" and type(tc.previewRows) == "table",
		"state.tooltipControls exposes checks, sampleBtns, presetBtns, formatBtns, modBtns, and previewRows")
	assertCheck(#tc.previewRows == 36, "Example Tooltip pools 36 preview rows")

	local function findPreviewRow(substr)
		for _, row in ipairs(tc.previewRows) do
			if row.frame and row.frame:IsShown() then
				local txt = row.leftFs and row.leftFs:GetText() or ""
				if txt:find(substr, 1, true) then
					return row
				end
			end
		end
		return nil
	end

	-- Toggling checkboxes updates MerchantMasterDB and immediately updates Example Tooltip (enabled vs dimmed lines)
	tc.sampleBtns.green_lens:Click("LeftButton")
	assertCheck((tc.headerNameFs:GetText() or ""):find("Green Lens", 1, true) ~= nil,
		"Green Lens sample displays Green Lens header")

	local minRowBefore = findPreviewRow("Min Buyout")
	local craftRowBefore = findPreviewRow("Craft Cost (est.)")
	assertCheck(minRowBefore ~= nil and minRowBefore.enabled == true,
		"Min Buyout preview row starts enabled on Green Lens")
	assertCheck(craftRowBefore ~= nil and craftRowBefore.enabled == false,
		"Craft Cost preview row starts dimmed when tooltipCraftCost is false")

	local function setCheck(cb, checkedVal)
		cb:SetChecked(checkedVal)
		local fn = cb:GetScript("OnClick")
		if fn then fn(cb, "LeftButton") end
	end

	-- Toggle Min Buyout OFF -> DB updates and preview row dims
	setCheck(tc.checks.ttMinBuyout, false)
	assertCheck(_G.MerchantMasterDB.ttMinBuyout == false,
		"Unchecking ttMinBuyout updates MerchantMasterDB.ttMinBuyout = false")
	local minRowOff = findPreviewRow("Min Buyout")
	assertCheck(minRowOff ~= nil and minRowOff.enabled == false,
		"Unchecking ttMinBuyout immediately dims Min Buyout in Example Tooltip")
	if minRowOff and minRowOff.leftFs and minRowOff.leftFs.GetTextColor then
		local r, g, b = minRowOff.leftFs:GetTextColor()
		assertCheck(math.abs(r - 0.42) < 0.02 and math.abs(g - 0.45) < 0.02 and math.abs(b - 0.50) < 0.02,
			"Dimmed preview row renders with dimmed slate RGB")
	end

	-- Toggle Craft Cost ON -> DB updates and preview row enables
	setCheck(tc.checks.tooltipCraftCost, true)
	assertCheck(_G.MerchantMasterDB.tooltipCraftCost == true,
		"Checking tooltipCraftCost updates MerchantMasterDB.tooltipCraftCost = true")
	local craftRowOn = findPreviewRow("Craft Cost (est.)")
	assertCheck(craftRowOn ~= nil and craftRowOn.enabled == true,
		"Checking tooltipCraftCost immediately enables Craft Cost in Example Tooltip")

	-- Switching sample items updates Example Tooltip header & rows
	tc.sampleBtns.silk_cloth:Click("LeftButton")
	assertCheck((tc.headerNameFs:GetText() or ""):find("Silk Cloth", 1, true) ~= nil
		and findPreviewRow("Total Inventory") ~= nil,
		"Clicking Silk Cloth sample switches Example Tooltip to Silk Cloth")
	tc.sampleBtns.waylaid_crate:Click("LeftButton")
	assertCheck((tc.headerNameFs:GetText() or ""):find("Waylaid Crate", 1, true) ~= nil
		and findPreviewRow("MerchantMaster Waylaid Crate") ~= nil,
		"Clicking Waylaid Crate sample switches Example Tooltip to Waylaid Crate")

	-- Price format buttons & Modifier buttons update DB and preview
	tc.formatBtns.icons:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.ttPriceFormat == "icons",
		"Clicking Coin Icons format button sets ttPriceFormat = 'icons'")
	local fillRowIcons = findPreviewRow("Fill Cost")
	assertCheck(fillRowIcons and (fillRowIcons.rightFs:GetText() or ""):find("MoneyFrame\\UI-", 1, true) ~= nil,
		"Coin Icons format renders WoW coin texture markup in Example Tooltip")
	tc.formatBtns.colored:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.ttPriceFormat == "colored",
		"Clicking Colored Text format button restores ttPriceFormat = 'colored'")

	tc.modBtns.alt:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.ttModifier == "alt"
		and tv and tv.previewStatusFs and (tv.previewStatusFs:GetText() or ""):find("Alt", 1, true) ~= nil,
		"Clicking Alt modifier button sets ttModifier = 'alt' and updates preview status")
	tc.modBtns.none:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.ttModifier == "none",
		"Clicking Always modifier button restores ttModifier = 'none'")

	-- Presets (Compact / All On / Reset) update preview lines & sync with console_settings / app.ui.optCrateTooltipCheck / crateTooltipCheck
	tc.sampleBtns.green_lens:Click("LeftButton")
	tc.presetBtns.all:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.tooltipCraftCost == true
		and _G.MerchantMasterDB.ttVendorSell == true
		and _G.MerchantMasterDB.ttInvHideZero == false
		and _G.MerchantMasterDB.crateTooltips == true,
		"All On preset enables all tooltip toggles including Craft Cost, Vendor Sell, and zero-count alts")
	local vendorRowAll = findPreviewRow("Vendor Sell Price")
	assertCheck(vendorRowAll ~= nil and vendorRowAll.enabled == true,
		"All On preset enables Vendor Sell Price in Example Tooltip")

	tc.presetBtns.compact:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.tooltipCraftCost == false
		and _G.MerchantMasterDB.tooltipDEBreakdown == false
		and _G.MerchantMasterDB.ttInvByChar == false
		and _G.MerchantMasterDB.ttInvCompact == true,
		"Compact preset hides detailed breakdowns and per-char rows while enabling compact inventory")
	local deBdRowCompact = findPreviewRow("Vision Dust")
	assertCheck(deBdRowCompact ~= nil and deBdRowCompact.enabled == false,
		"Compact preset dims DE material breakdown rows in Example Tooltip")

	-- Uncheck crateTooltips in Tooltip Setup -> syncs app.ui.optCrateTooltipCheck & crateTooltipCheck & console_settings
	setCheck(tc.checks.crateTooltips, false)
	assertCheck(_G.MerchantMasterDB.crateTooltips == false,
		"Unchecking crateTooltips in Tooltip Setup updates MerchantMasterDB.crateTooltips = false")
	if app.ui and app.ui.optCrateTooltipCheck and app.ui.optCrateTooltipCheck.GetChecked then
		assertCheck(app.ui.optCrateTooltipCheck:GetChecked() == false,
			"crateTooltips toggle syncs to app.ui.optCrateTooltipCheck")
	end
	if app.ui and app.ui.crateTooltipCheck and app.ui.crateTooltipCheck.GetChecked then
		assertCheck(app.ui.crateTooltipCheck:GetChecked() == false,
			"crateTooltips toggle syncs to app.ui.crateTooltipCheck")
	end

	-- Reset preset restores defaults including crateTooltips = true and syncs external controls back ON
	tc.presetBtns.reset:Click("LeftButton")
	assertCheck(_G.MerchantMasterDB.crateTooltips == true
		and _G.MerchantMasterDB.tooltipDEValue == true
		and _G.MerchantMasterDB.tooltipDEBreakdown == true
		and _G.MerchantMasterDB.tooltipCraftCost == false,
		"Reset preset restores recommended defaults")
	if app.ui and app.ui.optCrateTooltipCheck and app.ui.optCrateTooltipCheck.GetChecked then
		assertCheck(app.ui.optCrateTooltipCheck:GetChecked() == true,
			"Reset preset syncs crateTooltips = true back to app.ui.optCrateTooltipCheck")
	end
	if app.ui and app.ui.crateTooltipCheck and app.ui.crateTooltipCheck.GetChecked then
		assertCheck(app.ui.crateTooltipCheck:GetChecked() == true,
			"Reset preset syncs crateTooltips = true back to app.ui.crateTooltipCheck")
	end

	-- Restore saved tooltip state
	for _, k in ipairs(ttKeys) do
		_G.MerchantMasterDB[k] = savedTT[k]
	end
	UI._state.tooltipSampleKey = savedSample
	if ns.TooltipPrefs and ns.TooltipPrefs.InvalidateAll then
		ns.TooltipPrefs.InvalidateAll()
	end
	UI.SyncSettings()
	app.panel:Hide()
end

---------------------------------------------------------------------------------------------------
-- 12. Storage Inspector Cache, Live Memory Re-Read & MM1 Packed Ledger Row Counting
---------------------------------------------------------------------------------------------------
do
	local ledgerDB = _G.MerchantMasterLedgerDB
	local hadLedger = (type(ledgerDB) == "table")
	if not hadLedger then
		ledgerDB = { days = {} }
		_G.MerchantMasterLedgerDB = ledgerDB
	end
	local hadDays = (type(ledgerDB.days) == "table")
	if not hadDays then ledgerDB.days = {} end
	local prevDayEntry = ledgerDB.days["2099-01-01"]

	CE.InvalidateStorageCache()
	local baseSnap = CE.CollectStorageSnapshot({ forceFresh = true })
	local function findLedgerRows(snap)
		for _, row in ipairs((snap and snap.savedTables) or {}) do
			if row.id == "MerchantMasterLedgerDB.days" then return row.rows end
		end
		return nil
	end
	local baseLedgerRows = findLedgerRows(baseSnap) or 0

	ledgerDB.days["2099-01-01"] = { s = "MM1:4:row1\nrow2\nrow3\nrow4" }
	CE.InvalidateStorageCache()
	local packedSnap = CE.CollectStorageSnapshot({ forceFresh = true })
	local packedLedgerRows = findLedgerRows(packedSnap)
	assertCheck(packedLedgerRows == baseLedgerRows + 4,
		"CollectStorageSnapshot parses MM1:<count>: packed ledger header (+4 rows), got "
		.. tostring(packedLedgerRows) .. " vs base " .. tostring(baseLedgerRows))

	local origUpdateMem = _G.UpdateAddOnMemoryUsage
	local origCUpdateMem = _G.C_AddOns and _G.C_AddOns.UpdateAddOnMemoryUsage
	local memCalls = 0
	local wrappedUpdateMem = function(...)
		memCalls = memCalls + 1
		if type(origUpdateMem) == "function" then return origUpdateMem(...) end
	end
	_G.UpdateAddOnMemoryUsage = wrappedUpdateMem
	if _G.C_AddOns then _G.C_AddOns.UpdateAddOnMemoryUsage = wrappedUpdateMem end

	local snapA = CE.CollectStorageSnapshot({ useCache = true })
	local snapB = CE.CollectStorageSnapshot({ useCache = true })
	assertCheck(snapA == snapB and snapA.savedTables == snapB.savedTables,
		"CollectStorageSnapshot({ useCache = true }) reuses cached savedTables across rapid calls")
	assertCheck(memCalls == 2,
		"CollectStorageSnapshot({ useCache = true }) still refreshes live UpdateAddOnMemoryUsage every call, got "
		.. tostring(memCalls))

	CE.InvalidateStorageCache()
	local snapC = CE.CollectStorageSnapshot({ useCache = true })
	assertCheck(snapC.savedTables ~= snapA.savedTables and memCalls == 3,
		"InvalidateStorageCache forces fresh CollectStorageSnapshot savedTables scan")

	_G.UpdateAddOnMemoryUsage = origUpdateMem
	if _G.C_AddOns then _G.C_AddOns.UpdateAddOnMemoryUsage = origCUpdateMem end
	ledgerDB.days["2099-01-01"] = prevDayEntry
	if not hadDays then ledgerDB.days = nil end
	if not hadLedger then _G.MerchantMasterLedgerDB = nil end
	CE.InvalidateStorageCache()
end

print(string.format("CONSOLE_TESTS: PASS (%d assertions)", assertions))
