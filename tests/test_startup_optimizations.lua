-- Startup Optimization Regression Suite (Lua 5.1)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, frames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local app = ns.app
local ui = app.ui
local db = MerchantMasterDB
local Theme = ns.Theme
local MarketScan = ns.MarketScan

local count = 0
local function check(ok, msg)
	count = count + 1
	if not ok then
		error("STARTUP OPT FAIL [" .. count .. "]: " .. tostring(msg), 2)
	end
end

local function approxEq(a, b, eps, msg)
	eps = eps or 1e-6
	check(type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps,
		string.format("%s (got %s, expected %s)", tostring(msg), tostring(a), tostring(b)))
end

---------------------------------------------------------------------------------------------------
-- 1. Lazy Customize Columns popovers start unbuilt at boot and build on first ToggleColumnSettings
---------------------------------------------------------------------------------------------------
do
	local recipeView = app.superListProvider and app.superListProvider.Create and app.superListProvider.Create(ui.mainArea, app.getSuperListHost and app.getSuperListHost() or nil)
	check(recipeView ~= nil and recipeView.colSettingsPopover ~= nil, "SuperList colSettingsPopover container exists")
	check(recipeView.colSettingsPopover._built == false and #recipeView.colSettingsPopover.rows == 0,
		"SuperList column popover starts unbuilt with 0 rows at boot")

	local vcView = ns.VendorCrafter and ns.VendorCrafter.Create and ns.VendorCrafter.Create(ui.mainArea, app.getVendorCrafterHost and app.getVendorCrafterHost() or nil)
	check(vcView ~= nil and vcView.colSettingsPopover ~= nil, "VendorCrafter colSettingsPopover container exists")
	check(vcView.colSettingsPopover._built == false and #vcView.colSettingsPopover.rows == 0,
		"VendorCrafter column popover starts unbuilt with 0 rows at boot")

	app.superListProvider.ToggleColumnSettings(true)
	check(recipeView.colSettingsPopover._built == true and #recipeView.colSettingsPopover.rows == 20,
		"SuperList ToggleColumnSettings(true) lazily builds all 20 column rows")
	app.superListProvider.ToggleColumnSettings(false)
	check(not recipeView.colSettingsPopover:IsShown(), "SuperList ToggleColumnSettings(false) hides popover")

	ns.VendorCrafter.ToggleColumnSettings(true)
	check(vcView.colSettingsPopover._built == true and #vcView.colSettingsPopover.rows == 17,
		"VendorCrafter ToggleColumnSettings(true) lazily builds all 17 column rows")
	ns.VendorCrafter.ToggleColumnSettings(false)
	check(not vcView.colSettingsPopover:IsShown(), "VendorCrafter ToggleColumnSettings(false) hides popover")
end

---------------------------------------------------------------------------------------------------
-- 2. MerchantMaster_Snapshots LoadOnDemand + EnsureSnapshotsLoaded
---------------------------------------------------------------------------------------------------
do
	local fh = assert(io.open(testsDir .. "../../MerchantMaster_Snapshots/MerchantMaster_Snapshots.toc", "rb"))
	local tocText = fh:read("*a")
	fh:close()
	check(tocText:match("##%s*LoadOnDemand:%s*1") ~= nil, "MerchantMaster_Snapshots.toc declares ## LoadOnDemand: 1")

	local origSnapRaw = ns.snapshotRaw
	local origCAddOns = _G.C_AddOns
	local loadCalls = 0
	ns.snapshotRaw = {}
	ns.ResetSnapshotsLoadAttempt()
	_G.C_AddOns = {
		LoadAddOn = function(name)
			loadCalls = loadCalls + 1
			if name == "MerchantMaster_Snapshots" then
				_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", "Normal-Horde", [[return {v=1,updatedAt=1795400000,source="blizzard",windowDays=30,itemCount=1,heatmapCount=1}]])
				return true
			end
			return false
		end,
	}

	check(ns.EnsureSnapshotsLoaded() == true and loadCalls == 1, "EnsureSnapshotsLoaded calls LoadAddOn once when snapshotRaw empty")
	check(ns.EnsureSnapshotsLoaded() == true and loadCalls == 1, "EnsureSnapshotsLoaded skips LoadAddOn once snapshots are loaded")

	-- Also verify one-shot guard when missing/disabled
	ns.snapshotRaw = {}
	ns.ResetSnapshotsLoadAttempt()
	_G.C_AddOns.LoadAddOn = function()
		loadCalls = loadCalls + 1
		return false
	end
	check(ns.EnsureSnapshotsLoaded() == false and loadCalls == 2, "EnsureSnapshotsLoaded returns false when addon fails to load")
	check(ns.EnsureSnapshotsLoaded() == false and loadCalls == 2, "EnsureSnapshotsLoaded does not retry LoadAddOn repeatedly in same session")

	_G.C_AddOns = origCAddOns
	ns.snapshotRaw = origSnapRaw
	ns.ResetSnapshotsLoadAttempt()
end

---------------------------------------------------------------------------------------------------
-- 3. Theme.ApplySavedSettings deferred repaint on ADDON_LOADED -> flushes on panel:Show()
---------------------------------------------------------------------------------------------------
do
	local savedSkin = MerchantMasterDB.uiSkin
	local savedMode = MerchantMasterDB.uiThemeMode
	local savedStyle = MerchantMasterDB.tableStyle

	Theme.SetSkin("standard", true)
	Theme.SetMode("dark", true)
	Theme.SetTableStyle("t5_ruled", true)
	app.panel:Hide()

	MerchantMasterDB.uiSkin = "goblin"
	MerchantMasterDB.uiThemeMode = "light"
	MerchantMasterDB.tableStyle = "t5_well"
	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame, "ADDON_LOADED", "MerchantMaster")

	check(Theme.GetSkin() == "goblin" and Theme.GetUserMode() == "light" and Theme.GetTableStyle() == "t5_well",
		"ADDON_LOADED updates Theme getters immediately even when panel is hidden")
	check(Theme.HasPendingRepaint() == true,
		"ADDON_LOADED defers full-tree repaint while panel is hidden")

	app.panel:Show()
	check(Theme.HasPendingRepaint() == false,
		"panel:Show() flushes deferred Theme repaint")
	check(app.ui.winChrome and app.ui.winChrome.warcraftChrome and app.ui.winChrome.warcraftChrome.frame:IsShown(),
		"Flushed goblin skin shows Warcraft chrome on panel:Show()")

	-- Restore
	MerchantMasterDB.uiSkin = savedSkin
	MerchantMasterDB.uiThemeMode = savedMode
	MerchantMasterDB.tableStyle = savedStyle
	Theme.ApplySavedSettings(savedMode or "dark", savedStyle or "t5_ruled", savedSkin or "standard", false)
end

---------------------------------------------------------------------------------------------------
-- 4. Lossless Pack / Unpack Codec & Reader Compatibility
---------------------------------------------------------------------------------------------------
do
	local sampleRing = {
		{ t = 1795200000, p = 12345, q = 42 },
		{ t = 1795203600, p = 0, q = 0 },
		{ t = 1795207200, p = 987654, q = 17 },
	}
	local packedHist = MarketScan.PackHistoryRing(sampleRing)
	check(type(packedHist) == "string" and packedHist:sub(1, 3) == "v1:", "PackHistoryRing produces v1: string")
	local unpackedHist = MarketScan.ReadHistory(packedHist)
	check(type(unpackedHist) == "table" and #unpackedHist == 3, "ReadHistory restores all 3 ring entries")
	for i = 1, 3 do
		check(unpackedHist[i].t == sampleRing[i].t and unpackedHist[i].p == sampleRing[i].p and unpackedHist[i].q == sampleRing[i].q,
			"ahHistory round-trip entry " .. i)
	end

	-- Include nil minP/maxP/lastP to verify sparse CSV field positions!
	local sampleDaily = {
		{ d = 20774, minP = nil, maxP = nil, lastP = nil, obsP = 0, lastQ = 0, maxQ = 5, at = 1795273228, scanUnits = 1.65, scanSeconds = 1800, scanPairs = 3 },
		{ d = 20775, minP = 450, maxP = 900, lastP = 600, obsP = 600, lastQ = 12, maxQ = 20, at = 1795359628, scanUnits = 0, scanSeconds = 0, scanPairs = 0 },
	}
	local packedDaily = MarketScan.PackDailyBuckets(sampleDaily)
	check(type(packedDaily) == "string" and packedDaily:sub(1, 3) == "v1:", "PackDailyBuckets produces v1: string")
	local unpackedDaily = MarketScan.ReadDaily(packedDaily)
	check(type(unpackedDaily) == "table" and #unpackedDaily == 2, "ReadDaily restores both daily buckets")
	check(unpackedDaily[1].d == 20774 and unpackedDaily[1].minP == nil and unpackedDaily[1].maxP == nil and unpackedDaily[1].lastP == nil,
		"ReadDaily preserves nil mid-row prices without shifting fields")
	check(unpackedDaily[1].obsP == 0 and unpackedDaily[1].lastQ == 0 and unpackedDaily[1].maxQ == 5 and unpackedDaily[1].at == 1795273228,
		"ReadDaily preserves later fields after nil prices")
	approxEq(unpackedDaily[1].scanUnits, 1.65, 1e-9, "ReadDaily preserves fractional scanUnits")
	check(unpackedDaily[1].scanSeconds == 1800 and unpackedDaily[1].scanPairs == 3, "ReadDaily preserves scanSeconds and scanPairs")
	check(unpackedDaily[2].minP == 450 and unpackedDaily[2].maxP == 900 and unpackedDaily[2].lastP == 600 and unpackedDaily[2].lastQ == 12,
		"ReadDaily restores populated second bucket")

	local sampleSnap = { 1795259175, 1000, 10, 1795262775, 1250, 8 }
	local packedSnap = MarketScan.PackSnapshots(sampleSnap)
	check(type(packedSnap) == "string" and packedSnap:sub(1, 3) == "v1:", "PackSnapshots produces v1: string")
	local unpackedSnap = MarketScan.ReadSnapshots(packedSnap)
	check(type(unpackedSnap) == "table" and #unpackedSnap == 6, "ReadSnapshots restores all 6 flat triplet values")
	for i = 1, 6 do
		check(unpackedSnap[i] == sampleSnap[i], "ahSnapshots round-trip index " .. i)
	end

	check(MarketScan.ReadHistory("corrupt") == nil and MarketScan.ReadDaily("corrupt") == nil and MarketScan.ReadSnapshots("corrupt") == nil,
		"Corrupt strings without v1: prefix safely return nil")
end

---------------------------------------------------------------------------------------------------
-- 5. Packed strings work in Trend7d, Trend24h, Velocity, HeatStrip24h, RecipeStats, and Scan write
---------------------------------------------------------------------------------------------------
do
	local origTime = _G.time
	local origDaily, origHist, origSnaps = db.ahDaily, db.ahHistory, db.ahSnapshots
	local origPrices, origSnapRaw = db.ahPrices, ns.snapshotRaw

	local sundayDay = 20779
	local trend7dNow = sundayDay * 86400 + 12 * 3600
	local trendNow = os.time({ year = 2026, month = 11, day = 22, hour = 23, min = 30, sec = 0 })
	_G.time = function() return trendNow end

	local econ = ns.DetectActiveEconomy()
	local id = 2447
	local dailyRaw = {}
	for age = 6, 0, -1 do
		local p = (7 - age) * 100
		dailyRaw[#dailyRaw + 1] = {
			d = sundayDay - age, minP = p, maxP = p, lastP = p, obsP = p,
			lastQ = 10, maxQ = 10, at = trend7dNow - age * 86400,
			scanUnits = 2.5, scanSeconds = 3600, scanPairs = 2,
		}
	end
	local histRaw = {
		{ t = trendNow - 3600, p = 700, q = 14 },
		{ t = trendNow - 1800, p = 700, q = 10 },
		{ t = trendNow - 600, p = 750, q = 8 },
	}
	local snapRaw = {
		trendNow - 7200, 650, 12,
		trendNow - 3600, 700, 10,
	}

	db.ahDaily = { [econ] = { [id] = MarketScan.PackDailyBuckets(dailyRaw), [99911] = "corrupt" } }
	db.ahHistory = { [econ] = { [id] = MarketScan.PackHistoryRing(histRaw), [99911] = MarketScan.PackHistoryRing({
		{ t = trend7dNow - 86400, p = 300, q = 2 },
		{ t = trend7dNow, p = 200, q = 4 },
	}) } }
	db.ahSnapshots = { [econ] = { [id] = MarketScan.PackSnapshots(snapRaw) } }
	db.ahPrices = { [econ] = {} }

	local t7 = MarketScan.GetItemTrend7d(id, econ, trend7dNow)
	check(t7 and t7.source == "ahDaily" and t7.daysCollected == 7 and t7.startPrice7d == 100 and t7.currentPrice == 700,
		"GetItemTrend7d reads packed ahDaily strings")

	local corruptFallback = MarketScan.GetItemTrend7d(99911, econ, trend7dNow)
	check(corruptFallback and corruptFallback.source == "ahHistory" and corruptFallback.daysCollected == 2,
		"Corrupt ahDaily string safely falls back to packed ahHistory")

	local t24 = MarketScan.GetItemTrend24h(id, econ, trendNow)
	check(t24 and t24.source == "ahSnapshots" and t24.hoursCollected == 4 and t24.currentPrice == 750,
		"GetItemTrend24h reads packed ahSnapshots + ahHistory + ahDaily strings")

	local vel = MarketScan.GetLocalVelocity(id, econ)
	check(vel and vel.scanPairs == 2 and vel.latestQty == 8,
		"GetLocalVelocity reads packed ahHistory strings")

	-- RecipeStats.BuildQuickLook with packed ahDaily/ahHistory/ahSnapshots
	local qlRec
	for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
		if entry.recipe and entry.recipe.outputItemID == id then qlRec = entry.recipe; break end
	end
	if qlRec then
		local ql = ns.RecipeStats.BuildQuickLook({ outputItemID = id, recipe = qlRec, name = qlRec.name, prof = qlRec.prof }, { economy = econ, window = "7d" }, trend7dNow)
		check(ql ~= nil and ql.series ~= nil, "RecipeStats.BuildQuickLook succeeds with packed history")
	end

	-- Pricing.GetItemHeatStrip24h with packed ahSnapshots (miss + cached hit)
	ns.snapshotRaw = {}
	local hrs = {}
	for h = 0, 23 do hrs[#hrs + 1] = "1e" end
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ, string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=1}]], trendNow - 10000))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", econ, string.format("%d:3w,3w,a,1,12,-1,0,-1,0|%s", id, table.concat(hrs, ",")))
	local strip1 = ns.Pricing.GetItemHeatStrip24h(id, econ)
	local strip2 = ns.Pricing.GetItemHeatStrip24h(id, econ)
	local h1 = os.date("*t", trendNow - 3600).hour
	check(strip1 and strip1.hasLiveOverlay and strip1.hourly[h1] == 700,
		"GetItemHeatStrip24h overlays packed ahSnapshots live prices")
	check(strip2 == strip1, "GetItemHeatStrip24h caches packed snapRaw without re-decoding")

	-- PackHistoryForSave packs unpacked entries and skips already-packed entries
	local packedCount1 = MarketScan.PackHistoryForSave(db)
	check(packedCount1 == 0, "PackHistoryForSave returns 0 when all entries are already packed, got " .. tostring(packedCount1))

	-- Unpack on live scan write, then re-pack on PLAYER_LOGOUT
	local origGetBrowse = _G.C_AuctionHouse.GetBrowseResults
	_G.C_AuctionHouse.GetBrowseResults = function()
		return { { itemKey = { itemID = id, itemLevel = 0, itemSuffix = 0 }, totalQuantity = 15, minPrice = 820 } }
	end
	_G.AuctionHouseFrame:Show()
	app.refreshAllMarketValues()
	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	_G.AuctionHouseFrame:Hide()
	_G.C_AuctionHouse.GetBrowseResults = origGetBrowse

	check(type(db.ahDaily[econ][id]) == "table" and type(db.ahHistory[econ][id]) == "table" and type(db.ahSnapshots[econ][id]) == "table",
		"Live AH scan seamlessly decodes packed strings back to mutable tables on write")

	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame, "PLAYER_LOGOUT")
	check(type(db.ahDaily[econ][id]) == "string" and db.ahDaily[econ][id]:sub(1, 3) == "v1:",
		"PLAYER_LOGOUT packs mutated ahDaily back to v1: string")
	check(type(db.ahHistory[econ][id]) == "string" and db.ahHistory[econ][id]:sub(1, 3) == "v1:",
		"PLAYER_LOGOUT packs mutated ahHistory back to v1: string")
	check(type(db.ahSnapshots[econ][id]) == "string" and db.ahSnapshots[econ][id]:sub(1, 3) == "v1:",
		"PLAYER_LOGOUT packs mutated ahSnapshots back to v1: string")
	check(MarketScan.PackHistoryForSave(db) == 0,
		"Second PackHistoryForSave call returns 0 after PLAYER_LOGOUT packed everything")

	_G.time = origTime
	db.ahDaily, db.ahHistory, db.ahSnapshots = origDaily, origHist, origSnaps
	db.ahPrices, ns.snapshotRaw = origPrices, origSnapRaw
end

print("Startup optimizations suite: " .. count .. " assertions passed")
