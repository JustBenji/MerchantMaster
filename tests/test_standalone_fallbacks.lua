-- Standalone Fallbacks, Onboarding, Extension Contracts, Redaction & Locale Font Suite (Pure Lua 5.1)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, createdFrames, hostEnv = dofile(testsDir .. "host_fixture.lua")

local assertions = 0
local function check(cond, msg)
	assertions = assertions + 1
	if not cond then
		error("STANDALONE FALLBACKS FAIL [" .. assertions .. "]: " .. tostring(msg), 2)
	end
end

local app = ns.app
local ui = app.ui
local Theme = ns.Theme
local SE = ns.SniperEngine
local CE = ns.ConsoleEngine
local UIConsole = ns.UIConsole
local econ = ns.DetectActiveEconomy()
local now = _G.time()

---------------------------------------------------------------------------------------------------
-- 1. Empty Fresh SavedVariables Boot Cleanly (Zero Seeded Records, Zero Personal Migrations)
---------------------------------------------------------------------------------------------------
do
	check(ns.HasSnapshots() == false, "Fresh standalone boot has HasSnapshots() == false")
	check(ns.Pricing.GetSnapshotStatus() == "absent",
		"Fresh standalone boot reports GetSnapshotStatus() == 'absent', got " .. tostring(ns.Pricing.GetSnapshotStatus()))
	check(ns.MapPins == nil and app.mapPinsProvider == nil,
		"Fresh standalone boot has no bundled MapPins module or provider")
	check(app.snapshotExtension == nil, "Fresh standalone boot has no snapshotExtension registered")
	check(ns.Analytics and ns.Analytics.Store and ns.Analytics.Store["Migrate" .. "GreenLensDE" .. "AndB" .. "enji"] == nil,
		"Personal migration helper is completely absent from Analytics.Store")
	local ledgerDB = _G.MerchantMasterLedgerDB
	local dayCount = 0
	for _ in pairs((ledgerDB and ledgerDB.days) or {}) do dayCount = dayCount + 1 end
	check(dayCount == 0, "Fresh MerchantMasterLedgerDB starts with 0 seeded day rows, got " .. tostring(dayCount))
	local ahCount = 0
	for k in pairs((MerchantMasterDB.ahPrices and MerchantMasterDB.ahPrices[econ]) or {}) do
		if k ~= "_scannedAt" then ahCount = ahCount + 1 end
	end
	check(ahCount == 0, "Fresh MerchantMasterDB.ahPrices starts empty, got " .. tostring(ahCount))
end

---------------------------------------------------------------------------------------------------
-- 2. First-Run Header Capsule, 'Scan AH' Button Label & Dismissible 2-Step Onboarding Card
---------------------------------------------------------------------------------------------------
do
	MerchantMasterDB.onboardingDismissed = nil
	MerchantMasterDB.hideWithAH = nil
	MerchantMasterDB.autoOpenAtAH = nil
	MerchantMasterDB.ahPrices = {}
	app.panel:Show()
	app.setTab("dashboard")
	app.refresh()

	check(ui.statusSyncFs and ui.statusSyncFs:GetText() == "No AH Scan Yet",
		"First-run header status capsule displays 'No AH Scan Yet', got '" .. tostring(ui.statusSyncFs and ui.statusSyncFs:GetText()) .. "'")

	local refreshCtrl = ui.winChrome and ui.winChrome.ahRefresh
	check(refreshCtrl ~= nil and refreshCtrl.button ~= nil, "Header ahRefresh control exists")
	refreshCtrl:Update()
	check(refreshCtrl.button:GetText() == "Scan AH" and refreshCtrl.button:GetWidth() == 78,
		"First-run AH refresh button displays 'Scan AH' (width=78), got '"
		.. tostring(refreshCtrl.button:GetText()) .. "' w=" .. tostring(refreshCtrl.button:GetWidth()))

	check(ui.dashOnboardingCard ~= nil and ui.dashOnboardingCard:IsShown(),
		"First-run Dashboard displays 2-step onboarding card before first scan")
	check(ui.dashOnboardNoAutoOpenCheck ~= nil and ui.dashOnboardNoAutoOpenCheck:GetChecked() == false,
		"Onboarding 'Don't auto-open at Auction House' checkbox defaults unchecked")

	-- Toggle checkbox -> updates both hideWithAH and autoOpenAtAH
	ui.dashOnboardNoAutoOpenCheck:SetChecked(true)
	ui.dashOnboardNoAutoOpenCheck:GetScript("OnClick")(ui.dashOnboardNoAutoOpenCheck, "LeftButton")
	check(MerchantMasterDB.hideWithAH == true and MerchantMasterDB.autoOpenAtAH == false,
		"Checking onboarding checkbox sets hideWithAH=true and autoOpenAtAH=false")
	ui.dashOnboardNoAutoOpenCheck:SetChecked(false)
	ui.dashOnboardNoAutoOpenCheck:GetScript("OnClick")(ui.dashOnboardNoAutoOpenCheck, "LeftButton")
	check(MerchantMasterDB.hideWithAH == false and MerchantMasterDB.autoOpenAtAH == true,
		"Unchecking onboarding checkbox sets hideWithAH=false and autoOpenAtAH=true")

	-- Click Dismiss -> sets onboardingDismissed=true and hides card
	check(ui.dashOnboardDismissBtn ~= nil, "Onboarding Dismiss button exists")
	ui.dashOnboardDismissBtn:Click("LeftButton")
	check(MerchantMasterDB.onboardingDismissed == true and not ui.dashOnboardingCard:IsShown(),
		"Dismissing onboarding card persists onboardingDismissed=true and hides card")
	app.refresh()
	check(not ui.dashOnboardingCard:IsShown(), "Onboarding card stays hidden on subsequent refresh once dismissed")
end

---------------------------------------------------------------------------------------------------
-- 3. Live AH Velocity -> computeDailySold -> Profit Spread + Dashboard Daily Velocity Crafts
---------------------------------------------------------------------------------------------------
do
	-- Pick a clean sellable Alchemy recipe (Minor Healing Potion, outputItemID=118, reagents: 2447 Peacebloom + 765 Silverleaf + 3371 Empty Vial)
	local targetItemID = 118
	MerchantMasterDB.ahPrices = {
		[econ] = {
			_scannedAt = now - 60,
			[2447] = { price = 15, qty = 200, at = now - 60 },
			[765]  = { price = 20, qty = 200, at = now - 60 },
			[targetItemID] = { price = 500, qty = 10, at = now - 60 },
		},
	}
	-- Cold start: only 1 scan point (< 2 pairs) -> local velocity nil + Profit Spread surfaces warm-up reason
	MerchantMasterDB.ahHistory = {
		[econ] = {
			[targetItemID] = {
				{ t = now - 60, p = 500, q = 10 },
			},
		},
	}
	ns.InvalidatePriceCache()

	local velCold = ns.MarketScan.GetLocalVelocity(targetItemID, econ)
	check(type(velCold) == "table" and (velCold.scanPairs or 0) < 2 and velCold.clearsPerDay == nil,
		"GetLocalVelocity returns clearsPerDay == nil with < 2 scan pairs")
	local dailyCold = ns.GetDailySold(targetItemID)
	check(dailyCold == nil or dailyCold == 0, "computeDailySold returns nil/0 on cold start without snapshots")

	local coldRows, coldSummary = ns.BuildProfitSpreadRows({ spreadCount = 8, applyAHCut = true })
	check(#coldRows == 0 and coldSummary and coldSummary.emptyReason == "insufficient_live_history"
		and coldSummary.needsMoreScans == true,
		"BuildProfitSpreadRows surfaces emptyReason='insufficient_live_history' on < 2 scan pairs, got "
		.. tostring(coldSummary and coldSummary.emptyReason))

	-- Warm state: 3 scans across >= 15m (2 pairs with qty depletion 30 -> 18 -> 10)
	MerchantMasterDB.ahHistory[econ][targetItemID] = {
		{ t = now - 21600, p = 500, q = 30 },
		{ t = now - 10800, p = 500, q = 18 },
		{ t = now - 60,    p = 500, q = 10 },
	}
	ns.InvalidatePriceCache()

	local velWarm = ns.MarketScan.GetLocalVelocity(targetItemID, econ)
	check(velWarm ~= nil and velWarm.scanPairs >= 2 and (velWarm.clearsPerDay or 0) > 0,
		"GetLocalVelocity computes positive clearsPerDay with >= 2 scan pairs across >= 15m")
	local dailyWarm = ns.GetDailySold(targetItemID)
	check(type(dailyWarm) == "number" and dailyWarm > 0,
		"computeDailySold falls back to MarketScan.GetLocalVelocity clearsPerDay (" .. tostring(dailyWarm) .. ")")

	local warmRows, warmSummary = ns.BuildProfitSpreadRows({ spreadCount = 8, applyAHCut = true })
	check(#warmRows >= 1 and warmSummary and warmSummary.planCount >= 1 and warmSummary.emptyReason == nil,
		"BuildProfitSpreadRows populates profitable crafts from Live AH velocity alone, got count=" .. tostring(#warmRows))
	local foundTarget = false
	for _, r in ipairs(warmRows) do
		if (r.itemID or r.outputItemID) == targetItemID and (r.expectedDailyProfit or 0) > 0 then
			foundTarget = true
			break
		end
	end
	check(foundTarget, "Profit Spread includes Live-AH-priced craft (item 118) with positive expectedDailyProfit")

	-- Dashboard Daily Velocity Crafts card populates without snapshots
	local origDashScope = MerchantMasterDB.dashboardScope
	MerchantMasterDB.dashboardScope = "all"
	app.setTab("dashboard")
	app.refresh()
	local dashPopulated = false
	for _, row in ipairs(ui.dashCraftRows or {}) do
		if row and row.IsShown and row:IsShown() and row.data ~= nil then dashPopulated = true; break end
	end
	MerchantMasterDB.dashboardScope = origDashScope
	check(dashPopulated, "Dashboard Daily Velocity Crafts populates from Live AH velocity alone")
end

---------------------------------------------------------------------------------------------------
-- 4. Live AH Median -> SE.GetReferencePrice -> SE.BuildGapShortlist (Cold Start vs Deals)
---------------------------------------------------------------------------------------------------
do
	local testID = 70991
	local curScanTs = now - 30
	local savedHistory = MerchantMasterDB.ahHistory
	local savedDaily = MerchantMasterDB.ahDaily
	local savedPrices = MerchantMasterDB.ahPrices
	local savedBrowse = SE.browseCache

	MerchantMasterDB.ahPrices = {
		[econ] = {
			_scannedAt = curScanTs,
			[testID] = { price = 10000, qty = 5, at = curScanTs },
		},
	}
	SE.browseCache = {
		[tostring(testID)] = {
			itemID = testID,
			minPrice = 10000,
			totalQuantity = 5,
			economy = econ,
			quality = 2,
			isCommodity = true,
			itemKey = { itemID = testID, itemLevel = 0, itemSuffix = 0 },
			updatedAt = _G.GetTime(),
		},
	}

	-- 4a. Only 1 prior observation (+ current scan) -> strictly excludes currentScanAt -> insufficient (< 2 prior)
	MerchantMasterDB.ahHistory = {
		[econ] = {
			[testID] = {
				{ t = now - 7200, p = 25000, q = 20 },
				{ t = curScanTs,  p = 10000, q = 5 },
			},
		},
	}
	MerchantMasterDB.ahDaily = { [econ] = {} }
	ns.InvalidatePriceCache()

	local refTooFew = SE.GetReferencePrice(testID, econ, { currentScanAt = curScanTs })
	check(refTooFew == nil,
		"SE.GetReferencePrice excludes current scan and returns nil with < 2 prior observations, got " .. tostring(refTooFew))

	local coldShortlist, _, coldMeta = SE.BuildGapShortlist({
		econ = econ,
		currentScanAt = curScanTs,
		scope = "all",
		minDailySales = 0.1,
		minProfitCopper = 5000,
		minGapPct = 20,
		minQuality = 0,
	})
	check(type(coldShortlist) == "table" and #coldShortlist == 0
		and (coldShortlist.reason == "insufficient_live_history" or (coldMeta and coldMeta.reason == "insufficient_live_history")),
		"SE.BuildGapShortlist returns reason='insufficient_live_history' when < 2 prior observations exist")

	-- 4b. >= 2 prior observations strictly before currentScanAt + >= 2 velocity pairs -> median anchor + shortlist deal!
	MerchantMasterDB.ahHistory[econ][testID] = {
		{ t = now - 28800, p = 24000, q = 40 },
		{ t = now - 14400, p = 26000, q = 25 },
		{ t = now - 3600,  p = 25000, q = 14 },
		{ t = curScanTs,   p = 10000, q = 5 },
	}
	MerchantMasterDB.ahDaily[econ][testID] = {
		{ d = "2026-11-24", minP = 24500, avgP = 25000, maxQ = 35, lastQ = 20 },
		{ d = "2026-11-25", minP = 25500, avgP = 26000, maxQ = 30, lastQ = 15 },
	}
	ns.InvalidatePriceCache()

	local refPrice, refSrc = SE.GetReferencePrice(testID, econ, { currentScanAt = curScanTs })
	check(type(refPrice) == "number" and refPrice >= 20000 and refPrice <= 26500,
		"SE.GetReferencePrice computes live-AH median anchor from >= 2 prior observations, got "
		.. tostring(refPrice) .. " (" .. tostring(refSrc) .. ")")

	local warmShortlist = SE.BuildGapShortlist({
		econ = econ,
		currentScanAt = curScanTs,
		scope = "all",
		minDailySales = 0.1,
		minProfitCopper = 5000,
		minGapPct = 20,
		minQuality = 0,
	})
	check(type(warmShortlist) == "table" and #warmShortlist >= 1 and warmShortlist[1].itemID == testID,
		"SE.BuildGapShortlist surfaces discounted item from Live AH history + velocity without snapshots, got count="
		.. tostring(warmShortlist and #warmShortlist))

	SE.browseCache = savedBrowse
	MerchantMasterDB.ahHistory = savedHistory
	MerchantMasterDB.ahDaily = savedDaily
	MerchantMasterDB.ahPrices = savedPrices
	ns.InvalidatePriceCache()
end

---------------------------------------------------------------------------------------------------
-- 5. Non-Destructive 'snapshot' Fallback & GetAvailablePriceSources()
---------------------------------------------------------------------------------------------------
do
	local origSrc = MerchantMasterDB.priceSource
	MerchantMasterDB.priceSource = "snapshot"
	ns.InvalidatePriceCache()

	check(ns.Pricing.GetEffectivePriceSource() == "auto",
		"GetEffectivePriceSource falls back to 'auto' when priceSource=='snapshot' without snapshots, got "
		.. tostring(ns.Pricing.GetEffectivePriceSource()))
	check(MerchantMasterDB.priceSource == "snapshot",
		"Runtime fallback is non-destructive and preserves saved MerchantMasterDB.priceSource == 'snapshot'")
	local p2447, src2447 = ns.GetItemMarketPrice(2447)
	check(p2447 == 15, "Item pricing still resolves Live AH price (15c) under non-destructive snapshot fallback, got "
		.. tostring(p2447) .. " / " .. tostring(src2447))

	local sources = ns.GetAvailablePriceSources()
	local hasSnapshotOpt = false
	for _, s in ipairs(sources or {}) do
		if s.key == "snapshot" then hasSnapshotOpt = true end
	end
	check(not hasSnapshotOpt and #sources == 2,
		"GetAvailablePriceSources() omits 'snapshot' when snapshots are absent (count=" .. tostring(sources and #sources) .. ")")
	MerchantMasterDB.priceSource = origSrc or "auto"
end

---------------------------------------------------------------------------------------------------
-- 6. Snapshot UI Surfaces Standalone Rules (Always-Visible Snapshot Settings vs Hidden Telemetry)
---------------------------------------------------------------------------------------------------
do
	-- 6a. Console Snapshot Sync sub-tab IS visible standalone, Legacy Snapshot Builder is completely removed,
	-- while Overview Snapshot Storage KPI and Database SQLite rows stay hidden
	app.setTab("console_overview")
	local setupBtn = UIConsole._state.subTabBar and UIConsole._state.subTabBar.buttons.console_setup
	check(setupBtn == nil and UIConsole._state.setupView == nil,
		"Console -> Legacy Snapshot Builder sub-tab and view are completely removed")
	local setup2Btn = UIConsole._state.subTabBar and UIConsole._state.subTabBar.buttons.console_setup2
	check(setup2Btn and setup2Btn:IsShown() and setup2Btn.fs and setup2Btn.fs:GetText() == "MerchantMasterSync",
		"Console -> MerchantMasterSync sub-tab is visible standalone")
	check(UIConsole._state.overviewView and UIConsole._state.overviewView.kpis[2]
		and not UIConsole._state.overviewView.kpis[2].frame:IsShown(),
		"Console -> Overview Snapshot Storage card is hidden standalone")
	app.setTab("console_database")
	local hasSqliteRow = false
	for _, entry in ipairs(UIConsole._state.dbItems or {}) do
		if entry.kindTag == "SQLite" then hasSqliteRow = true; break end
	end
	check(not hasSqliteRow, "Console -> Database hides SQLite rows standalone")

	SlashCmdList.MERCHANTMASTER("snapshots")
	local su2 = UIConsole._state.setupV2View
	check(app.activeTab == "console_setup2" and UIConsole.GetActiveSubTab() == "console_setup2"
		and su2 and (su2.winInstallBox:GetText() or ""):find("--sync-mode github --apply-task --sync-now", 1, true) ~= nil
		and (su2.winRebuildBox:GetText() or ""):find("sync --source github --force", 1, true) ~= nil
		and (su2.winUninstallBox:GetText() or ""):find("uninstall-task", 1, true) ~= nil
		and (su2.linuxInstallBox:GetText() or ""):find("install_linux.py --sync-mode github", 1, true) ~= nil
		and (su2.macInstallBox:GetText() or ""):find("--sync-mode github --apply-task --sync-now", 1, true) ~= nil
		and su2.modeBtns and su2.modeBtns["local"] and su2.modeBtns["tsm"] and su2.modeBtns["none"],
		"/mm snapshots opens Snapshot Sync standalone with OS commands and 3-way Price Refresh Mode")
	SlashCmdList.MERCHANTMASTER("github")
	check(app.activeTab == "console_setup2" and UIConsole.GetActiveSubTab() == "console_setup2",
		"/mm github opens Snapshot Sync standalone")
	SlashCmdList.MERCHANTMASTER("builder")
	check(app.activeTab == "console_setup2" and UIConsole.GetActiveSubTab() == "console_setup2",
		"/mm builder redirects cleanly to Snapshot Sync standalone")

	-- 6b. Gap Sniper & Vendor Sniper [Scan Snapshot] buttons hidden
	app.setTab("sniper_gap")
	local gapView = ns.UISniper and ns.UISniper._views and ns.UISniper._views.gap
	if not gapView and ui.sniperGapView then gapView = ui.sniperGapView end
	if gapView and gapView.snapBtn then
		check(not gapView.snapBtn:IsShown(), "Gap Sniper [Scan Snapshot] button is hidden standalone")
	else
		-- Check all buttons created in UI_Sniper labeled 'Scan Snapshot' are hidden
		local anyVisibleSnapBtn = false
		for _, f in ipairs(createdFrames) do
			if f._text == "Scan Snapshot" and f:IsShown() then anyVisibleSnapBtn = true end
		end
		check(not anyVisibleSnapBtn, "All [Scan Snapshot] buttons stay hidden in Gap Sniper standalone")
	end

	app.setTab("sniper_vendor")
	local anyVisibleVendorSnapBtn = false
	for _, f in ipairs(createdFrames) do
		if f._text == "Scan Snapshot" and f:IsShown() then anyVisibleVendorSnapBtn = true end
	end
	check(not anyVisibleVendorSnapBtn, "All [Scan Snapshot] buttons stay hidden in Vendor Sniper standalone")

	app.setTab("sniper_de")
	local anyVisibleDESnapBtn = false
	for _, f in ipairs(createdFrames) do
		if f._text == "Scan Snapshot" and f:IsShown() then anyVisibleDESnapBtn = true end
	end
	check(not anyVisibleDESnapBtn, "All [Scan Snapshot] buttons stay hidden in Disenchant Sniper standalone")

	-- 6b2. Disenchant Sniper view renders deals, cycles Quality, toggles AS +20%, and formats DE tooltip
	do
		local origCItem = _G.C_Item
		local origGetDEBD = ns.GetItemDEBreakdown
		local origAS = SE.GetSettings().deUseArcaneSalvager
		local origQual = SE.GetSettings().deQualityFilter
		local origMinP = SE.GetSettings().deMinProfitCopper
		local origBrowseCache = {}
		for k, v in pairs(SE.browseCache) do origBrowseCache[k] = v end

		_G.C_Item = {
			GetItemInfo = function(arg)
				local id = type(arg) == "number" and arg or (type(arg) == "string" and tonumber(arg:match("item:(%d+)")))
				if id == 99801 then
					return "Synthetic Emerald Mantle", "|cff1eff00|Hitem:99801|h[Synthetic Emerald Mantle]|h|r", 2, 58, 53, "Armor", "Cloth", 1, "INVTYPE_SHOULDER", 132641, 8000, 4, 1
				end
				return origCItem and origCItem.GetItemInfo and origCItem.GetItemInfo(arg) or nil
			end,
			GetItemInfoInstant = function(arg)
				local id = type(arg) == "number" and arg or (type(arg) == "string" and tonumber(arg:match("item:(%d+)")))
				if id == 99801 then return id, "Armor", "Cloth", "INVTYPE_SHOULDER", 132641, 4, 1 end
				return origCItem and origCItem.GetItemInfoInstant and origCItem.GetItemInfoInstant(arg)
			end,
		}
		ns.GetItemDEBreakdown = function(itemID)
			if itemID == 99801 then
				return {
					quality = 2, ilvl = 58, className = "Armor",
					netCopper = 30000, asNetCopper = 36000, grossCopper = 31579, asGrossCopper = 37895,
					minNetCopper = 15000, maxNetCopper = 45000, primarySummary = "75% Illusion Dust",
					outcomes = { { matID = 16204, name = "Illusion Dust", matRate = 0.75, amountOfMats = 1.1, evNetRounded = 22500 } },
				}, nil
			end
			return nil, "ineligible"
		end

		SE.ClearDEDeals()
		SE.SetOption("deMinProfitCopper", 1000)
		SE.SetOption("deUseArcaneSalvager", false)
		SE.SetOption("deQualityFilter", "all")
		SE.IngestBrowseBatch({
			{ itemID = 99801, minPrice = 10000, totalQuantity = 1, quality = 2, isCommodity = false,
				itemLink = "|cff1eff00|Hitem:99801|h[Synthetic Emerald Mantle]|h|r" },
		}, econ)
		SE.OnBrowseScanComplete(econ, false)
		app.panel:Show()
		app.setTab("sniper_de")
		app.refresh()

		local deRow = nil
		for _, f in ipairs(createdFrames) do
			if f._deal and f._deal.idKey == "de:99801" and f:IsShown() then
				deRow = f
				break
			end
		end
		local maxProfTxt = (deRow and deRow.cells and deRow.cells[6] and deRow.cells[6]:GetText() or "")
			:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		check(deRow ~= nil and deRow.cells and deRow.cells[2] and deRow.cells[2]:GetText() == "1"
			and maxProfTxt:find("2g", 1, true) ~= nil
			and deRow.cells[7] and deRow.cells[7]:GetText() == "75% Illusion Dust",
			"Disenchant Sniper UI renders Qty, Max Profit, and Expected Mat columns")

		local asCheck, qualBtn = nil, nil
		for _, f in ipairs(createdFrames) do
			if f.label and f.label.GetText and f.label:GetText() == "AS +20%" then asCheck = f end
			if f._mmLabel and f._mmLabel.GetText and f._mmLabel:GetText() == "All (Green+)" then qualBtn = f end
		end
		check(asCheck ~= nil and qualBtn ~= nil, "Disenchant Sniper filter strip exposes AS +20% and Quality controls")

		asCheck:SetChecked(true)
		asCheck:Click("LeftButton")
		check(SE.GetSettings().deUseArcaneSalvager == true and SE.deDealsByKey["de:99801"].deValue == 36000,
			"Clicking AS +20% updates DE Sniper deal value to 36000c (+20%)")

		GameTooltip:ClearLines()
		deRow:GetScript("OnEnter")(deRow)
		local deTipRaw = table.concat(GameTooltip._lines or {}, "\n")
		local deTip = deTipRaw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		check(deTip:find("Expected DE Value (AS +20%)", 1, true) ~= nil
			and deTip:find("Buy Moat (Qty):", 1, true) ~= nil
			and deTip:find("Max DE Revenue:", 1, true) ~= nil
			and deTip:find("Max Total Profit:", 1, true) ~= nil
			and deTip:find("Expected Disenchant Materials:", 1, true) ~= nil
			and deTip:find("2g 70s", 1, true) ~= nil,
			"Disenchant Sniper row tooltip displays Buy Moat, Max DE Revenue, Max Total Profit, and scaled material EV (2g 70s), got:\n" .. deTip)

		qualBtn:Click("LeftButton")
		check(SE.GetSettings().deQualityFilter == "green", "Quality pill cycles All -> Uncommon")
		qualBtn:Click("LeftButton")
		check(SE.GetSettings().deQualityFilter == "blue", "Quality pill cycles Uncommon -> Rare")
		qualBtn:Click("LeftButton")
		check(SE.GetSettings().deQualityFilter == "epic", "Quality pill cycles Rare -> Epic")
		qualBtn:Click("LeftButton")
		check(SE.GetSettings().deQualityFilter == "all", "Quality pill wraps Epic -> All")

		SE.ClearDEDeals()
		SE.browseCache = origBrowseCache
		SE.SetOption("deUseArcaneSalvager", origAS)
		SE.SetOption("deQualityFilter", origQual)
		SE.SetOption("deMinProfitCopper", origMinP)
		ns.GetItemDEBreakdown = origGetDEBD
		_G.C_Item = origCItem
		app.panel:Hide()
	end

	-- 6c. Deep Analysis heatmap timing drawer stays unmounted / hidden standalone
	app.openDeepAnalysis({ itemID = 2447, name = "Peacebloom" })
	local da = ns.Analytics and ns.Analytics.UI and ns.Analytics.UI.DeepAnalysis
	local drawerShown = da and da.timingDrawer and da.timingDrawer.frame and da.timingDrawer.frame:IsShown()
	check(not drawerShown, "Deep Analysis 7x24 heatmap timing drawer stays hidden standalone")

	-- 6d. Economy Tooltip omits Local Snapshot block standalone
	GameTooltip:ClearLines()
	app.showEconomyTooltip(app.panel)
	local tipText = table.concat(GameTooltip._lines or {}, "\n")
	check(tipText:find("Local Snapshot:", 1, true) == nil,
		"Economy Tooltip omits Local Snapshot block when snapshots are absent")
end

---------------------------------------------------------------------------------------------------
-- 7. MerchantMasterAPI Versioned Contracts (API_VERSION, ns==nil, Eager/Late Registration, Mismatch)
---------------------------------------------------------------------------------------------------
do
	check(_G.MerchantMasterAPI.API_VERSION == 1, "MerchantMasterAPI.API_VERSION == 1")
	check(_G.MerchantMasterAPI.ns == nil, "_G.MerchantMasterAPI.ns == nil (private namespace removed)")

	-- Capture chat prints for apiVersion mismatch warnings
	local origPrint = _G.print
	local printed = {}
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		printed[#printed + 1] = table.concat(parts, " ")
	end

	-- Mismatch warning without crashing (Snapshot Extension)
	app._snapApiWarned = nil
	local badSnapOk = _G.MerchantMasterAPI.RegisterSnapshotExtension({ apiVersion = 99, version = "9.9.9" })
	check(badSnapOk == false and app.snapshotExtension == nil,
		"RegisterSnapshotExtension rejects apiVersion mismatch cleanly without crashing")
	check(#printed >= 1 and printed[#printed]:find("API version mismatch", 1, true) ~= nil,
		"RegisterSnapshotExtension logs API version mismatch warning")

	-- Mismatch warning without crashing (MapPins)
	app._mapPinsApiWarned = nil
	local prevLen = #printed
	local badMapOk = _G.MerchantMasterAPI.RegisterMapPins({ apiVersion = 99, version = "9.9.9" })
	check(badMapOk == false and app.mapPinsProvider == nil,
		"RegisterMapPins rejects apiVersion mismatch cleanly without crashing")
	check(#printed > prevLen and printed[#printed]:find("API version mismatch", 1, true) ~= nil,
		"RegisterMapPins logs API version mismatch warning")

	-- Valid post-login late registration of Snapshot Extension
	local goodSnapOk = _G.MerchantMasterAPI.RegisterSnapshotExtension({
		apiVersion = 1,
		version = "1.0.0-test",
		BuildSetupView = function() end,
	})
	check(goodSnapOk == true and app.snapshotExtension ~= nil and CE.HasSnapshotExtension() == true,
		"Valid RegisterSnapshotExtension (apiVersion=1) succeeds post-login")

	-- GetMapPinsHostContext contract
	local ctx = _G.MerchantMasterAPI.GetMapPinsHostContext()
	check(type(ctx) == "table" and ctx.apiVersion == 1
		and type(ctx.getRecipes) == "function"
		and type(ctx.getProfByKey) == "function"
		and type(ctx.getStandingNames) == "function"
		and type(ctx.getItemBoP) == "function"
		and type(ctx.formatMoneyCompact) == "function"
		and type(ctx.getOwnedCounts) == "function"
		and type(ctx.isKnown) == "function"
		and type(ctx.checkIconPath) == "string" and ctx.checkIconPath:find("icon_check", 1, true) ~= nil,
		"GetMapPinsHostContext returns complete versioned host context contract")

	-- Late post-login registration immediately replays Init(ctx)
	local lateInitCtx = nil
	local lateMapOk = _G.MerchantMasterAPI.RegisterMapPins({
		apiVersion = 1,
		version = "1.0.0-late",
		Init = function(c) lateInitCtx = c end,
		OnEvent = function() end,
		InvalidateOwnership = function() end,
		GetPinCount = function() return 7 end,
	})
	check(lateMapOk == true and lateInitCtx ~= nil and lateInitCtx.apiVersion == 1,
		"Post-login RegisterMapPins immediately replays Init(hostCtx)")

	-- Eager pre-login registration defers Init until PLAYER_LOGIN
	local savedCharKey = app.charKey
	app.charKey = nil
	app.mapPinsProvider = nil
	ns.MapPins = nil
	local eagerInitCount = 0
	local eagerProvider = {
		apiVersion = 1,
		version = "1.0.0-eager",
		Init = function(c) if c and c.apiVersion == 1 then eagerInitCount = eagerInitCount + 1 end end,
		OnEvent = function() end,
		InvalidateOwnership = function() end,
		GetPinCount = function() return 3 end,
	}
	local eagerOk = _G.MerchantMasterAPI.RegisterMapPins(eagerProvider)
	check(eagerOk == true and eagerInitCount == 0,
		"Pre-login eager RegisterMapPins stores provider and defers Init until PLAYER_LOGIN")
	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame, "PLAYER_LOGIN")
	check(eagerInitCount == 1,
		"PLAYER_LOGIN invokes deferred Init(hostCtx) on eagerly registered MapPins provider")

	-- Clean up companion extensions
	app.charKey = savedCharKey or app.charKey
	app.snapshotExtension = nil
	app.mapPinsProvider = nil
	ns.MapPins = nil
	ns.NPC_PINS = nil
	_G.print = origPrint
end

---------------------------------------------------------------------------------------------------
-- 8. redactNames=true Default, /mm help, /mm ?, Unknown /mm <arg> Hint & Non-Latin Font Fallback
---------------------------------------------------------------------------------------------------
do
	check(UIConsole._state.bundleOpts and UIConsole._state.bundleOpts.redactNames == true,
		"Console Debug Bundle defaults to redactNames == true")
	local defaultBundle = CE.BuildDebugBundle(UIConsole._state.bundleOpts)
	check(defaultBundle:find("char=%[REDACTED%] realm=%[REDACTED%]", 1, false) ~= nil
		and defaultBundle:find("StandalonePlayer", 1, true) == nil,
		"Default Console Debug Bundle redacts player and realm names")

	-- Calling CE.BuildDebugBundle() with nil opts also defaults redactNames=true and redacts chars + LastSyncError
	MerchantMasterDB.chars["Normal-Horde-Forever-AltHero"] = { name = "AltHero", firstName = "AltHero", realm = "Forever" }
	local omittedBundle = CE.BuildDebugBundle()
	check(omittedBundle:find("char=%[REDACTED%] realm=%[REDACTED%]", 1, false) ~= nil
		and omittedBundle:find("AltHero", 1, true) == nil,
		"CE.BuildDebugBundle() with omitted opts defaults to redact=true and redacts known chars")
	MerchantMasterDB.chars["Normal-Horde-Forever-AltHero"] = nil

	-- Capture /mm help, /mm ?, and unknown /mm <arg> output
	local origPrint = _G.print
	local lines = {}
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		lines[#lines + 1] = table.concat(parts, " ")
	end

	lines = {}
	SlashCmdList.MERCHANTMASTER("help")
	local helpOut = table.concat(lines, "\n")
	check(helpOut:find("/mm", 1, true) ~= nil and helpOut:find("help", 1, true) ~= nil
		and helpOut:find("fixledger", 1, true) == nil and helpOut:find("migrateledger", 1, true) == nil,
		"/mm help prints public slash command table with zero personal migration commands")

	lines = {}
	SlashCmdList.MERCHANTMASTER("?")
	local qOut = table.concat(lines, "\n")
	check(qOut == helpOut, "/mm ? prints identical help output to /mm help")

	app.panel:Hide()
	lines = {}
	SlashCmdList.MERCHANTMASTER("not_a_real_subcommand_xyz")
	local unkOut = table.concat(lines, "\n")
	check(not app.panel:IsShown() and unkOut:find("/mm help", 1, true) ~= nil,
		"Unknown /mm <arg> prints usage hint mentioning /mm help without toggling window")

	_G.print = origPrint

	-- GetLocale() non-Latin font fallback vs Latin Inter font
	local origGetLocale = _G.GetLocale
	local origStdFont = _G.STANDARD_TEXT_FONT
	_G.STANDARD_TEXT_FONT = "Fonts\\2002.TTF"

	for _, loc in ipairs({ "ruRU", "koKR", "zhCN", "zhTW" }) do
		_G.GetLocale = function() return loc end
		check(Theme.ShouldUseLocaleFallback() == true, "ShouldUseLocaleFallback() == true for " .. loc)
		check(Theme.ResolveFontPath("regular") == _G.STANDARD_TEXT_FONT
			and Theme.ResolveFontPath("semibold") == _G.STANDARD_TEXT_FONT,
			loc .. " falls back to STANDARD_TEXT_FONT")
		local fs = app.panel:CreateFontString(nil, "OVERLAY")
		Theme.ApplyFont(fs, 13, "semibold")
		local fp = fs:GetFont()
		check(fp == _G.STANDARD_TEXT_FONT, "Theme.ApplyFont uses STANDARD_TEXT_FONT under " .. loc)
	end

	for _, loc in ipairs({ "enUS", "deDE" }) do
		_G.GetLocale = function() return loc end
		check(Theme.ShouldUseLocaleFallback() == false, "ShouldUseLocaleFallback() == false for " .. loc)
		check(Theme.ResolveFontPath("regular") == Theme.FONTS.regular
			and Theme.ResolveFontPath("semibold") == Theme.FONTS.semibold,
			loc .. " uses bundled Inter fonts")
		local fs = app.panel:CreateFontString(nil, "OVERLAY")
		Theme.ApplyFont(fs, 13, "semibold")
		local fp = fs:GetFont()
		check(fp == Theme.FONTS.semibold and fp:find("Inter%-SemiBold%.ttf$") ~= nil,
			"Theme.ApplyFont uses Inter-SemiBold.ttf under " .. loc)
	end

	_G.GetLocale = origGetLocale
	_G.STANDARD_TEXT_FONT = origStdFont
end

print(string.format("STANDALONE_FALLBACKS: PASS (%d assertions)", assertions))
