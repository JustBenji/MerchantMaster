-- Cross-View Single Canonical Latest-Scan-Wins Price Sync Suite (Pure ASCII)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, _, hostEnv = dofile(testsDir .. "host_fixture.lua")

local assertions = 0
local function check(ok, msg)
	assertions = assertions + 1
	if not ok then
		error("PRICE SYNC UNIFIED FAIL [" .. assertions .. "]: " .. tostring(msg), 2)
	end
end

local function plain(s)
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

local b32Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
local function encodeB32(num)
	num = math.floor(tonumber(num) or 0)
	if num <= 0 then return "0" end
	local digits = {}
	while num > 0 do
		local rem = num % 32
		digits[#digits + 1] = string.sub(b32Alphabet, rem + 1, rem + 1)
		num = math.floor(num / 32)
	end
	local out = {}
	for i = #digits, 1, -1 do out[#out + 1] = digits[i] end
	return table.concat(out)
end

local app = assert(ns.app, "ns.app exists")
local db = assert(_G.MerchantMasterDB, "MerchantMasterDB exists")
local Store = assert(ns.Analytics and ns.Analytics.Store, "Analytics.Store exists")
local Capture = assert(ns.Analytics and ns.Analytics.Capture, "Analytics.Capture exists")
local Model = assert(ns.Analytics and ns.Analytics.Model, "Analytics.Model exists")
local DA = assert(ns.DeepAnalysis, "DeepAnalysis exists")
local BModel = assert(ns.DashboardBloombergModel, "DashboardBloombergModel exists")
local W = assert(ns.Watchlist, "Watchlist exists")

local WATER_ID = 7070      -- Elemental Water (reagent & market item)
local LENS_ID = 10504      -- Green Lens (crafted recipe output)
local LENS_SPELL = 12622
local NON_CATALOG_ID = 19019

local ECON = ns.CurrentEconomyInfo().effectiveKey
local OTHER_ECON = (ECON == "Normal-Horde") and "Normal-Alliance" or "Normal-Horde"

local glRecipe
for _, r in ipairs(ns.RECIPES or {}) do
	if r.spellID == LENS_SPELL and r.outputItemID == LENS_ID then
		glRecipe = r
		break
	end
end
check(glRecipe ~= nil, "Located Green Lens recipe (spellID=12622, itemID=10504)")

-- Save environment state so nothing leaks across suites
local origTime = _G.time
local origTSM = rawget(_G, "TSM_API")
local origLedger = _G.MerchantMasterLedgerDB
local origMockVendor = hostEnv.mockVendorSell and hostEnv.mockVendorSell[WATER_ID]
local origMockVendorLens = hostEnv.mockVendorSell and hostEnv.mockVendorSell[LENS_ID]
local origSnapRaw = ns.snapshotRaw
local origSnapParsed = ns.snapshotParsed
local origSnapHeat = ns.snapshotHeatmapCache
local origAhPrices = db.ahPrices
local origAhLots = db.ahLots
local origPriceSource = db.priceSource
local origBgMode = db.backgroundPriceMode
local origUseTsm = db.useTSMPrices
local origLastRefresh = db.lastRefreshAt
local origCharBags = app.char and app.char.bags
local origCharBank = app.char and app.char.bank
local origCharMail = app.char and app.char.mail
local origCharGear = app.char and app.char.gear
local origCharBought = app.char and app.char.bought
local origCharBoundBags = app.char and app.char.boundBags
local origTtEnabled = db.ttMarketEnabled
local origTtMin = db.ttMinBuyout
local origTtListed = db.ttListedCount
local origTtFmt = db.ttPriceFormat
local origTtMod = db.ttModifier

local baseNow = 1796000000
local currentNow = baseNow
_G.time = function() return currentNow end

local tsmUpdateTs = 0
local tsmPrices = {}
local tsmMockAPI = {
	GetCustomPriceValue = function(expr, itemStr)
		local id = tonumber(tostring(itemStr):match("^i:(%d+)$"))
		local rec = id and tsmPrices[id]
		return rec and rec[expr] or nil
	end,
	GetAuctionDBLastUpdate = function()
		return tsmUpdateTs
	end,
}
rawset(_G, "TSM_API", nil)

_G.MerchantMasterLedgerDB = {}
Store.Init()
db.itemIDs = db.itemIDs or {}
db.itemIDs["Elemental Water"] = WATER_ID
db.itemIDs["Green Lens"] = LENS_ID
app.itemIDs["Elemental Water"] = WATER_ID
app.itemIDs["Green Lens"] = LENS_ID
if hostEnv.mockVendorSell then
	hostEnv.mockVendorSell[WATER_ID] = 400
	hostEnv.mockVendorSell[LENS_ID] = 1000
end
db.economy = "auto"
db.priceSource = "auto"
db.backgroundPriceMode = "local"
db.useTSMPrices = false
db.ahPrices = { [ECON] = {} }
db.ahLots = { [ECON] = {} }
db.lastRefreshAt = nil
db.ttMarketEnabled = true
db.ttMinBuyout = true
db.ttListedCount = true
db.ttPriceFormat = "text"
db.ttModifier = "none"

app.char.bags = { ["Elemental Water"] = 2 }
app.char.bank = {}
app.char.mail = {}
app.char.gear = {}
app.char.bought = {}
app.char.boundBags = {}

-- Seed historical accounting ledger rows (must NEVER be mutated by market price scans)
local histSell = Store.Append({
	time = baseNow - 86400,
	type = "AH_SELL",
	char = app.charKey or "TestChar",
	econ = ECON,
	itemID = WATER_ID,
	qty = 2,
	unit = 99999,
	total = 199998,
	extra = { name = "Elemental Water" },
})
local histBuy = Store.Append({
	time = baseNow - 7200,
	type = "AH_BUY",
	char = app.charKey or "TestChar",
	econ = ECON,
	itemID = WATER_ID,
	qty = 2,
	unit = 100,
	total = -200,
	extra = { name = "Elemental Water" },
})
check(histSell ~= nil and histBuy ~= nil, "Seeded immutable historical AH_SELL and AH_BUY ledger rows")

if W.Clear then W.Clear() end
W.Add(WATER_ID)
W.Add({ kind = "recipe", spellID = LENS_SPELL, outputItemID = LENS_ID })

local function seedSnapshot(snapTs, waterPrice, waterQty, lensPrice, lensQty)
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	ns.snapshotHeatmapCache = {}
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", ECON,
		string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=2,heatmapCount=0}]], snapTs))
	local rows = {}
	rows[#rows + 1] = string.format("%d:%s,%s,%s,%s,%s,%s",
		WATER_ID, encodeB32(waterPrice), encodeB32(waterPrice), encodeB32(0), encodeB32(waterQty), encodeB32(1), encodeB32(0))
	rows[#rows + 1] = string.format("%d:%s,%s,%s,%s,%s,%s",
		LENS_ID, encodeB32(lensPrice), encodeB32(lensPrice), encodeB32(0), encodeB32(lensQty), encodeB32(1), encodeB32(0))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", ECON, table.concat(rows, ";"))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", OTHER_ECON,
		string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=0}]], snapTs))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", OTHER_ECON,
		string.format("%d:%s,%s,%s,%s,%s,%s",
			WATER_ID, encodeB32(77700), encodeB32(77700), encodeB32(0), encodeB32(15), encodeB32(1), encodeB32(0)))
	ns.InvalidatePriceCache({ reason = "snapshot" })
end

local probeTip = CreateFrame("GameTooltip", "MMPriceSyncProbeTip", UIParent)
local function findOverviewRow(ovRows, key)
	for _, r in ipairs(ovRows or {}) do
		if r.key == key then return r end
	end
	return nil
end

local function assertAllSurfaces(label, expWater, expWaterListed, expLens)
	-- 1. Core canonical API + GetItemMarketPrice + GetNumListed
	local canW = ns.GetCanonicalItemPrice(WATER_ID)
	local canL = ns.GetCanonicalItemPrice(LENS_ID)
	local mktW = ns.GetItemMarketPrice(WATER_ID)
	local mktL = ns.GetItemMarketPrice(LENS_ID)
	local qtyW = ns.GetNumListed(WATER_ID)
	if expWater == nil then
		check(canW and canW.isAbsent == true and canW.price == nil and mktW == nil and qtyW == 0,
			label .. ": canonical & GetItemMarketPrice report Elemental Water absent (qty=0)")
	else
		check(canW and canW.price == expWater and mktW == expWater and qtyW == expWaterListed,
			string.format("%s: canonical Elemental Water == %s (qty %s), got price=%s mkt=%s qty=%s",
				label, tostring(expWater), tostring(expWaterListed),
				tostring(canW and canW.price), tostring(mktW), tostring(qtyW)))
	end
	check(canL and canL.price == expLens and mktL == expLens,
		string.format("%s: canonical Green Lens == %s, got %s", label, tostring(expLens), tostring(mktL)))

	-- 2. All Auction Houses [HOME]
	local allAH = ns.Pricing.GetAllAuctionHousesForItem(WATER_ID, ECON)
	if ns.IsLocalSnapshotSuppressed() then
		check(allAH == nil, label .. ": All Auction Houses returns nil when local snapshot is suppressed")
	else
		local homeRow
		for _, hr in ipairs(allAH and allAH.rows or {}) do
			if hr.isHome or hr.economy == ECON then homeRow = hr; break end
		end
		check(homeRow ~= nil, label .. ": All Auction Houses includes [HOME] row")
		if expWater == nil then
			check(homeRow.listed == false and homeRow.minBuyout == nil and homeRow.qty == 0,
				label .. ": All AH [HOME] reports unlisted/nil when absent")
		else
			check(homeRow.minBuyout == expWater,
				string.format("%s: All AH [HOME] minBuyout == %s, got %s", label, tostring(expWater), tostring(homeRow.minBuyout)))
		end
	end

	-- 3. Portfolio Capture & Portfolio Model (Wealth Breakdown)
	local valUnit = Capture.ValueWealthItem({
		GetVendorSellPrice = ns.GetVendorSellPrice,
		IsItemSellable = ns.IsItemSellable,
		CurrentEconomyInfo = ns.CurrentEconomyInfo,
		GetItemMarketPrice = ns.GetItemMarketPrice,
		GetNumListed = ns.GetNumListed,
		GetCanonicalItemPrice = ns.GetCanonicalItemPrice,
	}, db, ECON, ECON, WATER_ID, false, "bags")
	Capture.QueueWealthSnapshot({ sync = true })
	Model.Invalidate()
	local port = Model.Compute("portfolio")
	local bagsCat
	for _, cat in ipairs(port and port.categories or {}) do
		if cat.catKey == "bags" then bagsCat = cat; break end
	end
	local portWater
	for _, it in ipairs(bagsCat and bagsCat.items or {}) do
		if it.itemID == WATER_ID then portWater = it; break end
	end
	local expPortUnit = expWater or 400
	check(valUnit == expPortUnit and portWater ~= nil and portWater.unit == expPortUnit and portWater.total == 2 * expPortUnit,
		string.format("%s: Portfolio unit == %s (total %s), got val=%s portUnit=%s",
			label, tostring(expPortUnit), tostring(2 * expPortUnit),
			tostring(valUnit), tostring(portWater and portWater.unit)))

	-- 4. Deep Analysis
	app.panel:Show()
	app.openDeepAnalysis({ kind = "item", itemID = WATER_ID, name = "Elemental Water" })
	local daState = DA.GetState()
	local sellRow = findOverviewRow(daState and daState.data and daState.data.overviewRows, "sellPrice")
	local qtyRow = findOverviewRow(daState and daState.data and daState.data.overviewRows, "ahListed")
	if expWater == nil then
		check(sellRow and sellRow.liveValue == nil and qtyRow and qtyRow.liveValue == 0,
			label .. ": Deep Analysis clears liveValue and shows 0 listed when absent")
	else
		check(sellRow and sellRow.liveValue == expWater and qtyRow and qtyRow.liveValue == expWaterListed,
			string.format("%s: Deep Analysis sellPrice == %s, got %s",
				label, tostring(expWater), tostring(sellRow and sellRow.liveValue)))
	end

	-- 5. GoblinTV (DashboardBloombergModel)
	BModel.InvalidateCache()
	local bSnap = BModel.BuildSnapshot(ECON, "7d", "all", nil, currentNow)
	local bWater = bSnap and bSnap.stocksByKey and bSnap.stocksByKey["item:" .. tostring(WATER_ID)]
	local bLens = bSnap and bSnap.stocksByKey and bSnap.stocksByKey["recipe:" .. tostring(LENS_SPELL)]
	check(bWater ~= nil and bLens ~= nil, label .. ": GoblinTV includes Elemental Water & Green Lens")
	if expWater == nil then
		check(bWater.ahPrice == nil and bWater.primaryPrice == 0,
			label .. ": GoblinTV Elemental Water clears ahPrice when absent")
	else
		check(bWater.ahPrice == expWater and bWater.primaryPrice == expWater,
			string.format("%s: GoblinTV Elemental Water == %s, got %s", label, tostring(expWater), tostring(bWater.ahPrice)))
	end
	check(bLens.ahPrice == expLens,
		string.format("%s: GoblinTV Green Lens == %s, got %s", label, tostring(expLens), tostring(bLens.ahPrice)))

	-- 6. Watchlist
	local wRows = W.EvaluateRows({ db = db, economy = ECON, now = currentNow })
	local wWater, wLens
	for _, r in ipairs(wRows or {}) do
		if r.key == ("item:" .. tostring(WATER_ID)) then wWater = r end
		if r.key == ("recipe:" .. tostring(LENS_SPELL)) then wLens = r end
	end
	check(wWater ~= nil and wLens ~= nil, label .. ": Watchlist evaluates Elemental Water & Green Lens")
	if expWater == nil then
		check(wWater.unitAH == nil and wWater.listed == 0,
			label .. ": Watchlist clears stale snapshot price when absent")
	else
		check(wWater.unitAH == expWater and wWater.listed == expWaterListed,
			string.format("%s: Watchlist Elemental Water == %s, got %s", label, tostring(expWater), tostring(wWater.unitAH)))
	end
	check(wLens.unitAH == expLens,
		string.format("%s: Watchlist Green Lens == %s, got %s", label, tostring(expLens), tostring(wLens.unitAH)))

	-- 7. SuperList (RecipeStats) & All Items
	local rsLens = ns.RecipeStats.Get(glRecipe, app.getRecipeStatsContext())
	check(rsLens and rsLens.unitAH == expLens,
		string.format("%s: RecipeStats Green Lens == %s, got %s", label, tostring(expLens), tostring(rsLens and rsLens.unitAH)))
	local aiWater = ns.AllItemsModel.EvaluateItem(
		{ itemID = WATER_ID, name = "Elemental Water", sell = 400, usedInCount = 0 },
		{ db = db, economy = ECON, counts = {} },
		{}
	)
	if expWater == nil then
		check(aiWater and aiWater.unitAH == nil and aiWater.listed == 0,
			label .. ": AllItems clears unitAH and zeroes listed when absent")
	else
		check(aiWater and aiWater.unitAH == expWater and aiWater.listed == expWaterListed,
			string.format("%s: AllItems Elemental Water == %s, got %s", label, tostring(expWater), tostring(aiWater and aiWater.unitAH)))
	end

	-- 8. Item Tooltip (AppendMarketTooltip)
	probeTip:ClearLines()
	ns.AppendMarketTooltip(probeTip, WATER_ID)
	local minLine, listedLine
	for _, ln in ipairs(probeTip._lines or {}) do
		local p = plain(ln)
		if p:find("Min Buyout", 1, true) then minLine = p end
		if p:find("Listed Supply", 1, true) then listedLine = p end
	end
	if expWater == nil then
		check(minLine == nil and listedLine ~= nil and listedLine:find("0 auctions", 1, true) ~= nil,
			label .. ": Tooltip omits Min Buyout and shows 0 auctions when absent (got min=" .. tostring(minLine) .. ", listed=" .. tostring(listedLine) .. ")")
	else
		local expSilver = tostring(math.floor(expWater / 100) % 100) .. "s"
		check(minLine ~= nil and minLine:find(expSilver, 1, true) ~= nil,
			string.format("%s: Tooltip Min Buyout includes %s (got %s)", label, expSilver, tostring(minLine)))
	end

	-- 9. MM Sell (OrderFlow.ComputeSellUnitPrice)
	local sellP, sellSrc = ns.MarketScan.OrderFlow.ComputeSellUnitPrice({
		itemID = WATER_ID,
		name = "Elemental Water",
		qty = 1,
		vendorSell = 400,
	})
	if expWater == nil then
		check(sellP == 800 and sellSrc == "vendor_fallback",
			label .. ": MM Sell uses vendor_fallback (800c) and never resurrects stale snapshot when absent, got " .. tostring(sellP) .. "/" .. tostring(sellSrc))
	else
		check(sellP == expWater and sellSrc == "market_db",
			string.format("%s: MM Sell == %s (market_db), got %s/%s", label, tostring(expWater), tostring(sellP), tostring(sellSrc)))
	end
end

-- Phase 1: Initial Snapshot (t = baseNow - 600)
seedSnapshot(baseNow - 600, 1000, 14, 250000, 2)
assertAllSurfaces("Phase 1 (Initial Snapshot 10s)", 1000, 14, 250000)

-- Phase 2: Newer Live AH via RecordLiveItemPrice (t = baseNow - 300) + non-catalog item
check(ns.MarketScan.RecordLiveItemPrice(WATER_ID, 1900, 11, { stamp = baseNow - 300, itemWide = true }) ~= false,
	"RecordLiveItemPrice accepts catalog item 7070")
check(ns.MarketScan.RecordLiveItemPrice(LENS_ID, 310000, 3, { stamp = baseNow - 300, itemWide = true }) ~= false,
	"RecordLiveItemPrice accepts crafted item 10504")
check(ns.MarketScan.RecordLiveItemPrice(NON_CATALOG_ID, 44444, 1, { stamp = baseNow - 300, itemWide = true }) ~= false,
	"RecordLiveItemPrice accepts arbitrary non-catalog itemID")
assertAllSurfaces("Phase 2 (Newer Live AH 19s)", 1900, 11, 310000)
local ncCan = ns.GetCanonicalItemPrice(NON_CATALOG_ID)
check(ncCan and ncCan.price == 44444 and ns.GetItemMarketPrice(NON_CATALOG_ID) == 44444,
	"Non-catalog item 19019 resolves to 44444c through canonical pricing")

-- Phase 3: Even Newer Snapshot (t = baseNow - 120) overrides older Live AH (t = baseNow - 300)
seedSnapshot(baseNow - 120, 1200, 18, 275000, 4)
assertAllSurfaces("Phase 3 (Newer Snapshot 12s)", 1200, 18, 275000)

-- Phase 4: Opt-in TSM Light newer (t = baseNow - 60) wins; older TSM (t = baseNow - 1000) loses to Live AH (t = baseNow - 300)
rawset(_G, "TSM_API", tsmMockAPI)
ns.SetBackgroundPriceMode("tsm")
tsmPrices[WATER_ID] = { DBMinBuyout = 1550, DBMarket = 1600, DBNumAuctions = 9 }
tsmPrices[LENS_ID] = { DBMinBuyout = 288000, DBMarket = 290000, DBNumAuctions = 5 }
tsmUpdateTs = baseNow - 60
ns.InvalidatePriceCache({ reason = "tsm" })
assertAllSurfaces("Phase 4A (Newer TSM Light 15s50c)", 1550, 9, 288000)

tsmUpdateTs = baseNow - 1000 -- older than Live AH (baseNow - 300); no 30m cutoff in Pricing!
currentNow = baseNow + 3600    -- simulate 1h passing (>30m after Live AH at baseNow - 300!)
ns.InvalidatePriceCache({ reason = "tsm" })
assertAllSurfaces("Phase 4B (Live AH >1h old still beats older TSM)", 1900, 11, 310000)

-- Phase 5: Recent Live AH 'absent' (t = currentNow) zeros listed & clears spot price everywhere
currentNow = baseNow + 3660
rawset(_G, "TSM_API", nil)
ns.SetBackgroundPriceMode("local")
seedSnapshot(currentNow - 120, 1200, 18, 275000, 4)
ns.MarketScan.RecordLiveItemPrice(WATER_ID, nil, 0, { stamp = currentNow, itemWide = true })
assertAllSurfaces("Phase 5 (Recent Live AH absent beats older Snapshot)", nil, 0, 275000)

-- Phase 6: Historical ledger immutability check
local qRes = Model.QueryLedger({ period = "30d" }, 0, 500)
local ledgerRows = (qRes and qRes.rows) or {}
local foundSell, foundBuy = false, false
for _, lr in ipairs(ledgerRows) do
	if lr.itemID == WATER_ID and lr.type == "AH_SELL" and lr.time == baseNow - 86400 then
		check(lr.unit == 99999 and lr.total == 199998, "Historical AH_SELL ledger row stayed completely immutable")
		foundSell = true
	elseif lr.itemID == WATER_ID and lr.type == "AH_BUY" and lr.time == baseNow - 7200 then
		check(lr.unit == 100 and lr.total == -200, "Historical AH_BUY ledger row stayed completely immutable")
		foundBuy = true
	end
end
check(foundSell and foundBuy, "Both seeded historical ledger rows verified untouched")

-- Cleanup restored state
app.panel:Hide()
_G.time = origTime
rawset(_G, "TSM_API", origTSM)
_G.MerchantMasterLedgerDB = origLedger
Store.Init()
if hostEnv.mockVendorSell then
	hostEnv.mockVendorSell[WATER_ID] = origMockVendor
	hostEnv.mockVendorSell[LENS_ID] = origMockVendorLens
end
ns.snapshotRaw = origSnapRaw
ns.snapshotParsed = origSnapParsed
ns.snapshotHeatmapCache = origSnapHeat
db.ahPrices = origAhPrices
db.ahLots = origAhLots
db.priceSource = origPriceSource
db.backgroundPriceMode = origBgMode
db.useTSMPrices = origUseTsm
db.lastRefreshAt = origLastRefresh
db.ttMarketEnabled = origTtEnabled
db.ttMinBuyout = origTtMin
db.ttListedCount = origTtListed
db.ttPriceFormat = origTtFmt
db.ttModifier = origTtMod
app.char.bags = origCharBags
app.char.bank = origCharBank
app.char.mail = origCharMail
app.char.gear = origCharGear
app.char.bought = origCharBought
app.char.boundBags = origCharBoundBags
if W.Clear then W.Clear() end
ns.InvalidatePriceCache()

print(string.format("PASS: price_sync_unified (%d assertions, 0 failures)", assertions))
