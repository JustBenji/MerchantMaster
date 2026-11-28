local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames, hostEnv = dofile(S .. "host_fixture.lua")
local db = MerchantMasterDB

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local B32_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
local function encB32(num)
	num = math.floor(num or 0)
	if num <= 0 then return "0" end
	local digits = {}
	while num > 0 do
		local rem = num % 32
		digits[#digits + 1] = string.sub(B32_ALPHABET, rem + 1, rem + 1)
		num = math.floor(num / 32)
	end
	local out = {}
	for i = #digits, 1, -1 do
		out[#out + 1] = digits[i]
	end
	return table.concat(out)
end

-- Save globals/hooks to restore cleanly at end
local origTSM = _G.TSM_API
local origAuctionator = _G.Auctionator
local origAucAdvanced = _G.AucAdvanced
local origTime = _G.time
local origPriceSource = db.priceSource
local origEnableLegacy = db.enableLegacyPriceAddons
local origEconomy = db.economy
local origAhPrices = db.ahPrices
local origEconSnapshots = db.econSnapshots
local origAhLots = db.ahLots
local origAhSnapshots = db.ahSnapshots
local origAhDaily = db.ahDaily
local origAhHistory = db.ahHistory
local origTsmLastUpdate = db.tsmLastUpdate
local origTsmSynced = ns.tsmSyncedEconomies

local nowTs = 1795300000
_G.time = function() return nowTs end

-- Ensure active economy is Normal-Horde (default in host_fixture)
db.economy = "auto"
db.priceSource = "auto"
db.ahPrices = {}
db.econSnapshots = {}
db.ahLots = {}
db.ahSnapshots = {}
db.ahDaily = {}
db.ahHistory = {}
db.tsmLastUpdate = nil
ns.ahPrices = {}
ns.tsmRawAppHelper = {}
ns.tsmParsedEconomies = {}
ns.tsmSyncedEconomies = {}
ns.snapshotRaw = {}
ns.snapshotParsed = {}
ns.snapshotHeatmapCache = {}
ns.InvalidateEconomyDetectCache()
ns.InvalidatePriceCache()

local activeEcon = ns.CurrentEconomyInfo()
check(activeEcon.effectiveKey == "Normal-Horde" and activeEcon.isActive == true,
	"Expected active economy Normal-Horde, got " .. tostring(activeEcon.effectiveKey))

-- 1. Global entrypoint & PRICE_SOURCES registration
check(_G.MERCHANTMASTER_LOAD_SNAPSHOTS == ns.IngestSnapshotData,
	"_G.MERCHANTMASTER_LOAD_SNAPSHOTS must point to ns.IngestSnapshotData")
check(ns.Pricing.IngestSnapshotData == ns.IngestSnapshotData,
	"ns.Pricing.IngestSnapshotData must point to ns.IngestSnapshotData")

local foundSnapshotSource = nil
for _, s in ipairs(ns.PRICE_SOURCES) do
	if s.key == "snapshot" then
		foundSnapshotSource = s
		break
	end
end
check(foundSnapshotSource ~= nil, "ns.PRICE_SOURCES must include key='snapshot'")
check(foundSnapshotSource.label == "Local Snapshot" and foundSnapshotSource.short == "Snapshot",
	"Snapshot price source label/short mismatch")

-- 2. Safe META sandbox: reject global mutation / code execution / bytecode
_G._MM_SANDBOX_PROBE = nil
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", "Evil-Horde", [[_MM_SANDBOX_PROBE = 1; return {v=1,updatedAt=123}]])
check(_G._MM_SANDBOX_PROBE == nil, "META sandbox must not mutate globals")
check(ns.Pricing.GetSnapshotMeta("Evil-Horde") == nil, "Invalid META attempting global write must be rejected or isolated")
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", "Evil-Horde", "\027LuaQ\000")
check(ns.Pricing.GetSnapshotMeta("Evil-Horde") == nil, "Binary Lua bytecode META must be rejected")
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", "Evil-Horde", [[return os.time()]])
check(ns.Pricing.GetSnapshotMeta("Evil-Horde") == nil, "META referencing os global must fail safely")

-- 3. Valid META, multi-chunk LATEST, HEAT24, HEAT7X24 ingestion
local hordeUpdatedAt = 1795296000
local hugePrice = 2500000000 -- > 2^30 (7-char Base32 split decoder test)

_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"META",
	"Normal-Horde",
	string.format([[return {v=1,updatedAt=%d,source="tsm",windowDays=30,itemCount=4,heatmapCount=2}]], hordeUpdatedAt)
)

local metaHorde = ns.Pricing.GetSnapshotMeta()
check(metaHorde ~= nil, "GetSnapshotMeta() should return active economy metadata")
check(metaHorde.updatedAt == hordeUpdatedAt, "meta.updatedAt mismatch")
check(metaHorde.source == "tsm", "meta.source mismatch")
check(metaHorde.windowDays == 30, "meta.windowDays mismatch")
check(metaHorde.itemCount == 4, "meta.itemCount mismatch")
check(metaHorde.heatmapCount == 2, "meta.heatmapCount mismatch")
-- Returned copy must not mutate internal state
metaHorde.itemCount = 999999
check(ns.Pricing.GetSnapshotMeta().itemCount == 4, "GetSnapshotMeta must return an isolated copy")

-- LATEST chunk 1 + chunk 2
local latestChunk1 = table.concat({
	-- Black Lotus (13468): min=87694, mkt=89983, hist=81855, qty=134, num=42, tsDelta=600
	table.concat({ "13468:" .. encB32(87694), encB32(89983), encB32(81855), encB32(134), encB32(42), encB32(600) }, ","),
	-- Test item 95001: min=5400, mkt=6000, hist=5800, qty=77, num=19, tsDelta=0
	table.concat({ "95001:" .. encB32(5400), encB32(6000), encB32(5800), encB32(77), encB32(19), encB32(0) }, ","),
}, ";") .. ";"

local latestChunk2 = table.concat({
	-- Test item 95003: min=0 (absent), mkt=12345, hist=11000, qty=0, num=15, tsDelta=120
	table.concat({ "95003:0", encB32(12345), encB32(11000), "0", encB32(15), encB32(120) }, ","),
	-- Test item 95004: huge > 2^30 price
	table.concat({ "95004:" .. encB32(hugePrice), encB32(hugePrice), "0", encB32(3), encB32(3), "0" }, ","),
	-- Test item 95005: historical only (no minBuyout or marketValue)
	table.concat({ "95005:0", "0", encB32(4321), "0", "0", "0" }, ","),
}, ";")

_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", "Normal-Horde", latestChunk1)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", "Normal-Horde", latestChunk2)

-- Alliance economy snapshot for cross-economy tests
local allianceUpdatedAt = 1795295000
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"META",
	"Normal-Alliance",
	string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=1}]], allianceUpdatedAt)
)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"LATEST",
	"Normal-Alliance",
	table.concat({ "95001:" .. encB32(7100), encB32(7500), encB32(7000), encB32(25), encB32(11), encB32(30) }, ",")
)

-- Verify QueryLocalSnapshot & 6-char Base32 overflow decoding
local pLotus, recLotus = ns.QueryLocalSnapshot(13468)
check(pLotus == 87694, "Black Lotus snapshot minBuyout expected 87694, got " .. tostring(pLotus))
check(recLotus.minBuyout == 87694 and recLotus.marketValue == 89983 and recLotus.historical == 81855,
	"Black Lotus snapshot price fields mismatch")
check(recLotus.qty == 134 and recLotus.numAuctions == 42, "Black Lotus snapshot qty/numAuctions mismatch")
check(recLotus.updatedAt == hordeUpdatedAt - 600, "Black Lotus updatedAt delta mismatch: " .. tostring(recLotus.updatedAt))
check(recLotus.source == "tsm", "Black Lotus source mismatch")

local pNoMin, recNoMin = ns.QueryLocalSnapshot(95003)
check(pNoMin == 12345 and recNoMin.minBuyout == nil and recNoMin.marketValue == 12345,
	"minBuyout=0 must fall back to marketValue (12345), got " .. tostring(pNoMin))

local pHuge = ns.QueryLocalSnapshot(95004)
check(pHuge == hugePrice, "7-char Base32 > 2^30 price mismatch: expected " .. hugePrice .. ", got " .. tostring(pHuge))

local pMiss, recMiss = ns.QueryLocalSnapshot(999888)
check(pMiss == nil and recMiss == nil, "Missing item must return nil, nil")

-- Cross-economy QueryLocalSnapshot override
local pAlli, recAlli = ns.QueryLocalSnapshot(95001, "Normal-Alliance")
check(pAlli == 7100 and recAlli.qty == 25 and recAlli.source == "blizzard",
	"Cross-economy QueryLocalSnapshot failed: got " .. tostring(pAlli))
check(recAlli.updatedAt == allianceUpdatedAt - 30, "Alliance updatedAt delta mismatch")

-- 4. Explicit priceSource = "snapshot" (active + cross-economy)
local mockTSM = { [95001] = { dbminbuyout = 4000, dbmarket = 4500, dbnumauctions = 9 } }
_G.TSM_API = {
	GetCustomPriceValue = function(expr, itemStr)
		local id = tonumber(tostring(itemStr):match("i:(%d+)"))
		local row = id and mockTSM[id]
		return row and row[expr] or nil
	end,
}
local mockAuctionator = { [95001] = 6100, [95002] = 6200 }
_G.Auctionator = {
	API = {
		v1 = {
			GetAuctionPriceByItemID = function(_, id) return mockAuctionator[id] end,
		},
	},
}
_G.AucAdvanced = nil

db.ahPrices["Normal-Horde"] = {
	[95001] = { price = 3000, qty = 5, at = nowTs - 60 },
	[95002] = { price = 6500, qty = 4, at = nowTs - 3600 },
}
db.ahPrices["Normal-Alliance"] = {
	[95001] = { price = 8800, qty = 2, at = allianceUpdatedAt - 600 },
}

db.priceSource = "snapshot"
ns.InvalidatePriceCache()
local sp, ssrc, sstk = ns.GetItemMarketPrice(95001)
check(sp == 5400 and ssrc == "Snapshot" and sstk == 77,
	"Explicit snapshot mode active mismatch: " .. tostring(sp) .. " / " .. tostring(ssrc) .. " / " .. tostring(sstk))

local missP, missSrc, missStk = ns.GetItemMarketPrice(95002)
check(missP == nil and missSrc == nil and missStk == nil, "Explicit snapshot mode missing item must return nil")

-- Explicit snapshot mode on cross-economy
db.economy = "Normal-Alliance"
ns.InvalidatePriceCache()
local cp, csrc, cstk = ns.GetItemMarketPrice(95001)
check(cp == 7100 and csrc == "Snapshot (Normal-Alliance)" and cstk == 25,
	"Explicit snapshot mode cross-economy mismatch: " .. tostring(cp) .. " / " .. tostring(csrc) .. " / " .. tostring(cstk))

-- 5. Freshness helpers & Auto fallback priority (Pure Standalone: Live AH vs Snapshot newest-wins)
-- At nowTs=1795300000 and hordeUpdatedAt=1795296000, ageSec=4000 <= 5400 (90m) -> FRESH!
local isFreshH, ageH, metaFreshH = ns.Pricing.IsSnapshotFresh("Normal-Horde")
check(isFreshH == true and ageH == 4000 and metaFreshH and metaFreshH.updatedAt == hordeUpdatedAt,
	"IsSnapshotFresh should report true at 4000s age, got " .. tostring(isFreshH) .. " / " .. tostring(ageH))
local isFreshTight = ns.Pricing.IsSnapshotFresh("Normal-Horde", 1800)
check(isFreshTight == false, "IsSnapshotFresh with 1800s maxAgeSec should report false at 4000s age")
check(ns.Pricing.ShouldPreferSnapshotOverTSM == nil, "Legacy ShouldPreferSnapshotOverTSM removed in pure standalone mode")
check(ns.Pricing.IsSnapshotFresh("Unknown-Horde") == false, "Missing economy snapshot must not be fresh")

db.economy = "auto"
db.priceSource = "auto"
ns.InvalidatePriceCache()

-- 5a. Fresh Live AH (newer than Snapshot) wins #1
local p1, src1 = ns.GetItemMarketPrice(95001)
check(p1 == 3000 and src1 == "Live AH", "Auto: newer Live AH should win, got " .. tostring(p1) .. " / " .. tostring(src1))

-- 5b. Older Live AH + newer Snapshot -> Snapshot wins (TSM / Auctionator ignored!)
db.ahPrices["Normal-Horde"][95001].at = hordeUpdatedAt - 600
ns.InvalidatePriceCache()
local pFreshSnap, srcFreshSnap, stkFreshSnap = ns.GetItemMarketPrice(95001)
check(pFreshSnap == 5400 and srcFreshSnap == "Snapshot" and stkFreshSnap == 77,
	"Auto: newer Local Snapshot should beat older Live AH & ignore TSM, got " .. tostring(pFreshSnap) .. " / " .. tostring(srcFreshSnap) .. " / " .. tostring(stkFreshSnap))

-- 5b2. Legacy db.priceSource values ("tsm_min", "tsm_market", "auctionator", "auctioneer") normalize cleanly to "auto"
db.priceSource = "tsm_min"
ns.InvalidatePriceCache()
local pExpMin, srcExpMin = ns.GetItemMarketPrice(95001)
check(pExpMin == 5400 and srcExpMin == "Snapshot" and db.priceSource == "auto",
	"Legacy tsm_min normalizes to auto and resolves Snapshot, got " .. tostring(pExpMin) .. " / " .. tostring(db.priceSource))
db.priceSource = "tsm_market"
ns.InvalidatePriceCache()
local pExpMkt, srcExpMkt = ns.GetItemMarketPrice(95001)
check(pExpMkt == 5400 and srcExpMkt == "Snapshot" and db.priceSource == "auto",
	"Legacy tsm_market normalizes to auto and resolves Snapshot, got " .. tostring(pExpMkt) .. " / " .. tostring(db.priceSource))
db.priceSource = "auto"
ns.InvalidatePriceCache()

-- 5b3. Snapshot true qty (77) wins in GetNumListed (TSM ignored)
local nlFreshSnap = ns.GetNumListed(95001)
check(nlFreshSnap == 77, "GetNumListed should return Snapshot true qty (77), got " .. tostring(nlFreshSnap))

-- 5c. Item not in Snapshot -> Saved AH Scan wins (Auctionator ignored)
local origNowTs = nowTs
nowTs = hordeUpdatedAt + 7200 -- 2h old
ns.InvalidatePriceCache()
local p6, src6 = ns.GetItemMarketPrice(95002)
check(p6 == 6500 and src6 == "Saved AH Scan", "Auto: Saved AH should win when Snapshot lacks item (Auctionator ignored), got " .. tostring(p6) .. " / " .. tostring(src6))

-- Restore nowTs for remaining tests
nowTs = origNowTs

-- 5h. Cross-economy Auto fallback: Snapshot beats stale Saved AH
db.economy = "Normal-Alliance"
ns.InvalidatePriceCache()
local pCross, srcCross, stkCross = ns.GetItemMarketPrice(95001)
check(pCross == 7100 and srcCross == "Snapshot (Normal-Alliance)" and stkCross == 25,
	"Auto cross-economy: Snapshot should beat stale Saved AH, got " .. tostring(pCross) .. " / " .. tostring(srcCross))

-- 5i. GetFallbackMarketPrice & GetLastKnownAHPrice
local fbCross, fbCrossSrc = ns.GetFallbackMarketPrice(95001)
check(fbCross == 7100 and fbCrossSrc == "Snapshot (Normal-Alliance)",
	"GetFallbackMarketPrice cross-economy mismatch: " .. tostring(fbCross) .. " / " .. tostring(fbCrossSrc))

db.economy = "auto"
ns.InvalidatePriceCache()
local fbAct, fbActSrc = ns.GetFallbackMarketPrice(95001)
check(fbAct == 5400 and fbActSrc == "Snapshot",
	"GetFallbackMarketPrice active mismatch: " .. tostring(fbAct) .. " / " .. tostring(fbActSrc))

-- Remove ahPrices for 95001 and 95005 to verify GetLastKnownAHPrice falls through to Snapshot
db.ahPrices["Normal-Horde"][95001] = nil
ns.InvalidatePriceCache()
local lk1, lkSrc1 = ns.GetLastKnownAHPrice(95001)
check(lk1 == 5400 and lkSrc1 == "Snapshot",
	"GetLastKnownAHPrice active should resolve Snapshot, got " .. tostring(lk1) .. " / " .. tostring(lkSrc1))
local lkHist, lkHistSrc = ns.GetLastKnownAHPrice(95005)
check(lkHist == 4321 and lkHistSrc == "Snapshot",
	"GetLastKnownAHPrice should use historical-only snapshot record, got " .. tostring(lkHist) .. " / " .. tostring(lkHistSrc))

-- 6. GetNumListed standalone priority: Snapshot qty / numAuctions (TSM ignored)
nowTs = hordeUpdatedAt + 7200
ns.InvalidatePriceCache()
local nlSnap = ns.GetNumListed(95001)
check(nlSnap == 77, "GetNumListed should resolve snapRec.qty (77) and ignore TSM, got " .. tostring(nlSnap))

-- qty=0, numAuctions=15 -> falls back to numAuctions (15)
local nlNumA = ns.GetNumListed(95003)
check(nlNumA == 15, "GetNumListed should use numAuctions (15) when qty is 0, got " .. tostring(nlNumA))

-- Cross-economy GetNumListed falls back to Alliance snapRec.qty (25)
db.economy = "Normal-Alliance"
ns.InvalidatePriceCache()
local nlCross = ns.GetNumListed(95001)
check(nlCross == 25, "Cross-economy GetNumListed should fall back to snapRec.qty (25), got " .. tostring(nlCross))

nowTs = origNowTs
db.economy = "auto"
ns.InvalidatePriceCache()

-- 7. HEAT24 & GetItemHeatStrip24h
local hours24 = {}
for h = 0, 23 do
	if h == 0 then
		hours24[#hours24 + 1] = encB32(82000)
	elseif h == 12 then
		hours24[#hours24 + 1] = encB32(88000)
	elseif h == 23 then
		hours24[#hours24 + 1] = encB32(95000)
	else
		hours24[#hours24 + 1] = ""
	end
end
-- Slot 29 -> dow0 = 1 (dow=2 Tue), hour = 5; Slot 167 -> dow0 = 6 (dow=7 Sun), hour = 23
local heat24Blob = table.concat({
	"13468:" .. table.concat({
		encB32(88000), encB32(88500), encB32(120), encB32(14), encB32(48),
		"29", encB32(80000), "167", encB32(96000),
	}, ",") .. "|" .. table.concat(hours24, ","),
	-- Item 95001 with absent bestBuy/bestSell (-1)
	"95001:" .. table.concat({
		encB32(5400), encB32(5500), encB32(70), encB32(5), encB32(10),
		"-1", "0", "-1", "0",
	}, ",") .. "|" .. encB32(5400) .. ",,,,,,,,,,,,,,,,,,,,,,,",
}, ";")

_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", "Normal-Horde", heat24Blob)

local strip = ns.Pricing.GetItemHeatStrip24h(13468)
check(strip ~= nil, "GetItemHeatStrip24h(13468) must return table")
check(strip.medianPrice == 88000 and strip.avgPrice == 88500 and strip.avgQty == 120, "HEAT24 summary stats mismatch")
check(strip.cvPct == 14 and strip.totalSamples == 48, "HEAT24 cvPct/totalSamples mismatch")
check(strip.updatedAt == hordeUpdatedAt and strip.source == "tsm", "HEAT24 meta fields mismatch")
check(strip.hourly[0] == 82000 and strip.hourly[12] == 88000 and strip.hourly[23] == 95000, "HEAT24 hourly values mismatch")
check(strip.hourly[1] == nil and strip.hourly[22] == nil, "HEAT24 empty hour slots must be nil")
check(strip.bestBuy ~= nil and strip.bestBuy.dow == 2 and strip.bestBuy.hour == 5 and strip.bestBuy.price == 80000,
	"HEAT24 bestBuy slot 29 -> dow=2, hour=5 mismatch")
check(strip.bestSell ~= nil and strip.bestSell.dow == 7 and strip.bestSell.hour == 23 and strip.bestSell.price == 96000,
	"HEAT24 bestSell slot 167 -> dow=7, hour=23 mismatch")

local stripNoBest = ns.Pricing.GetItemHeatStrip24h(95001)
check(stripNoBest ~= nil and stripNoBest.bestBuy == nil and stripNoBest.bestSell == nil,
	"HEAT24 -1 slots must decode to nil bestBuy/bestSell")
check(stripNoBest.hourly[0] == 5400 and stripNoBest.hourly[1] == nil, "HEAT24 single-hour strip mismatch")
check(ns.Pricing.GetItemHeatStrip24h(999888) == nil, "HEAT24 missing item must return nil")

-- 8. HEAT7X24 & GetItemHeatmap (lazy indexing, 7x24 grid, daily/hourly aggregates, pctVsAvg, caching)
-- Slots for 13468:
--   slot 0   (dow=1 Mon, hour=0):  avg=80000, min=78000, qty=150, n=2
--   slot 20  (dow=1 Mon, hour=20): avg=100000, min=95000, qty=100, n=2
--   slot 164 (dow=7 Sun, hour=20): avg=120000, min=115000, qty=50, n=4
-- Sample-weighted overall avg = (80000*2 + 100000*2 + 120000*4) / 8 = 840000 / 8 = 105000
-- Sample-weighted overall qty = (150*2 + 100*2 + 50*4) / 8 = 700 / 8 = 87.5 -> 88
-- Sorted cell avgPrices = {80000, 100000, 120000} -> median = 100000
-- pctVsAvg:
--   slot 0:   (80000 - 105000) / 105000 * 100 = -23.8095... -> -23.8
--   slot 20:  (100000 - 105000) / 105000 * 100 = -4.7619... -> -4.8
--   slot 164: (120000 - 105000) / 105000 * 100 = +14.2857... -> 14.3
-- daily[1]: avg = (80000*2 + 100000*2)/4 = 90000, min = 78000, avgQty = 125, samples = 4
-- daily[7]: avg = 120000, min = 115000, avgQty = 50, samples = 4
-- daily[2..6]: nil
-- hourly[0]: avg = 80000, min = 78000, avgQty = 150, samples = 2
-- hourly[20]: avg = (100000*2 + 120000*4)/6 = 680000/6 = 113333.33 -> 113333, min = 95000, avgQty = 67, samples = 6
local heat7x24Blob = "13468:" .. table.concat({
	"0=" .. table.concat({ encB32(80000), encB32(78000), encB32(150), encB32(2) }, ","),
	"20=" .. table.concat({ encB32(100000), encB32(95000), encB32(100), encB32(2) }, ","),
	"164=" .. table.concat({ encB32(120000), encB32(115000), encB32(50), encB32(4) }, ","),
}, "|") .. ";"

_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", "Normal-Horde", heat7x24Blob)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"HEAT7X24",
	"Normal-Alliance",
	"95001:48=" .. table.concat({ encB32(7000), encB32(6800), encB32(20), encB32(3) }, ",")
)

-- Verify lazy indexing: index must not be built before first GetItemHeatmap call
check(ns.snapshotRaw["Normal-Horde"].heat7x24Index == nil, "HEAT7X24 index must stay nil until lazy GetItemHeatmap call")

local hm = ns.Pricing.GetItemHeatmap(13468)
check(hm ~= nil, "GetItemHeatmap(13468) must return decoded heatmap")
check(ns.snapshotRaw["Normal-Horde"].heat7x24Index ~= nil, "HEAT7X24 index must be built lazily on demand")
check(hm.itemID == 13468 and hm.economy == "Normal-Horde", "Heatmap identity fields mismatch")
check(hm.updatedAt == hordeUpdatedAt and hm.source == "tsm" and hm.windowDays == 30, "Heatmap meta fields mismatch")

-- Verify cells[1..7][0..23] and nil safety
check(hm.cells[1][0] ~= nil and hm.cells[1][0].avgPrice == 80000 and hm.cells[1][0].minPrice == 78000
	and hm.cells[1][0].avgQty == 150 and hm.cells[1][0].samples == 2 and hm.cells[1][0].pctVsAvg == -23.8,
	"Heatmap cell [1][0] mismatch: pct=" .. tostring(hm.cells[1][0] and hm.cells[1][0].pctVsAvg))
check(hm.cells[1][20] ~= nil and hm.cells[1][20].avgPrice == 100000 and hm.cells[1][20].pctVsAvg == -4.8,
	"Heatmap cell [1][20] mismatch: pct=" .. tostring(hm.cells[1][20] and hm.cells[1][20].pctVsAvg))
check(hm.cells[7][20] ~= nil and hm.cells[7][20].avgPrice == 120000 and hm.cells[7][20].pctVsAvg == 14.3,
	"Heatmap cell [7][20] mismatch: pct=" .. tostring(hm.cells[7][20] and hm.cells[7][20].pctVsAvg))
check(hm.cells[1][1] == nil and hm.cells[3][12] == nil and hm.cells[7][0] == nil,
	"Missing heatmap cells must be nil")

-- Verify daily[1..7]
check(hm.daily[1] ~= nil and hm.daily[1].avgPrice == 90000 and hm.daily[1].minPrice == 78000
	and hm.daily[1].avgQty == 125 and hm.daily[1].samples == 4, "Heatmap daily[1] mismatch")
check(hm.daily[7] ~= nil and hm.daily[7].avgPrice == 120000 and hm.daily[7].minPrice == 115000
	and hm.daily[7].avgQty == 50 and hm.daily[7].samples == 4, "Heatmap daily[7] mismatch")
for d = 2, 6 do
	check(hm.daily[d] == nil, "Empty day daily[" .. d .. "] must be nil")
end

-- Verify hourly[0..23]
check(hm.hourly[0] ~= nil and hm.hourly[0].avgPrice == 80000 and hm.hourly[0].samples == 2, "Heatmap hourly[0] mismatch")
check(hm.hourly[20] ~= nil and hm.hourly[20].avgPrice == 113333 and hm.hourly[20].minPrice == 95000
	and hm.hourly[20].avgQty == 67 and hm.hourly[20].samples == 6,
	"Heatmap hourly[20] mismatch: avg=" .. tostring(hm.hourly[20] and hm.hourly[20].avgPrice))
check(hm.hourly[5] == nil, "Empty hour hourly[5] must be nil")

-- Verify overall
check(hm.overall.avgPrice == 105000 and hm.overall.medianPrice == 100000
	and hm.overall.minPrice == 78000 and hm.overall.maxPrice == 120000
	and hm.overall.avgQty == 88 and hm.overall.totalSamples == 8
	and hm.overall.cvPct >= 15 and hm.overall.cvPct <= 17,
	"Heatmap overall mismatch: avg=" .. tostring(hm.overall.avgPrice) .. " cv=" .. tostring(hm.overall.cvPct))

-- Verify bestBuy / bestSell
check(hm.bestBuy ~= nil and hm.bestBuy.dow == 1 and hm.bestBuy.hour == 0
	and hm.bestBuy.avgPrice == 80000 and hm.bestBuy.minPrice == 78000 and hm.bestBuy.pctVsAvg == -23.8,
	"Heatmap bestBuy mismatch")
check(hm.bestSell ~= nil and hm.bestSell.dow == 7 and hm.bestSell.hour == 20
	and hm.bestSell.avgPrice == 120000 and hm.bestSell.minPrice == 115000 and hm.bestSell.pctVsAvg == 14.3,
	"Heatmap bestSell mismatch")

-- Verify caching identity
local hmCached = ns.Pricing.GetItemHeatmap(13468)
check(hmCached == hm, "Second GetItemHeatmap call must return cached table")
check(ns.Pricing.GetItemHeatmap(999888) == nil, "GetItemHeatmap for missing item must return nil")

-- Clear Alliance live AH override before pure-snapshot cross-economy heatmap verification
db.ahPrices["Normal-Alliance"] = {}
-- Cross-economy heatmap via econOverride (slot 48 -> dow=3 Wed, hour=0)
local hmAlli = ns.Pricing.GetItemHeatmap(95001, "Normal-Alliance")
check(hmAlli ~= nil and hmAlli.economy == "Normal-Alliance" and hmAlli.cells[3][0] ~= nil
	and hmAlli.cells[3][0].avgPrice == 7000 and hmAlli.cells[3][0].pctVsAvg == 0,
	"Cross-economy GetItemHeatmap mismatch")

-- 9. Cache invalidation on re-ingest (fresh META replaces old chunks and clears caches)
local epochBefore = ns.priceCacheEpoch
local newUpdatedAt = hordeUpdatedAt + 3600
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"META",
	"Normal-Horde",
	string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=1,depthCount=3,velocityCount=2}]], newUpdatedAt)
)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"LATEST",
	"Normal-Horde",
	table.concat({ "13468:" .. encB32(99000), encB32(101000), encB32(95000), encB32(200), encB32(55), "0" }, ",")
)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"HEAT7X24",
	"Normal-Horde",
	"13468:10=" .. table.concat({ encB32(99000), encB32(98000), encB32(200), encB32(1) }, ",")
)

check(ns.priceCacheEpoch > epochBefore, "Re-ingest must bump ns.priceCacheEpoch")
check(ns.Pricing.GetSnapshotMeta("Normal-Horde").source == "blizzard", "Re-ingest must update META")
check(ns.Pricing.GetSnapshotMeta("Normal-Horde").depthCount == 3
	and ns.Pricing.GetSnapshotMeta("Normal-Horde").velocityCount == 2,
	"GetSnapshotMeta must preserve depthCount and velocityCount")
local pNew, recNew = ns.QueryLocalSnapshot(13468, "Normal-Horde")
check(pNew == 99000 and recNew.qty == 200 and recNew.updatedAt == newUpdatedAt, "Re-ingest must update LATEST")
check(ns.QueryLocalSnapshot(95001, "Normal-Horde") == nil, "Re-ingest with fresh META must drop stale items from old snapshot")
local hmNew = ns.Pricing.GetItemHeatmap(13468, "Normal-Horde")
check(hmNew ~= nil and hmNew ~= hm and hmNew.cells[1][10] ~= nil and hmNew.cells[1][10].avgPrice == 99000
	and hmNew.cells[1][0] == nil, "Re-ingest must invalidate cached heatmap and decode new cells")

-- 10. Conservative Anchor fallback (Snapshot marketValue / historical when TSM absent)
-- In section 9, 13468 has marketValue=101000, historical=95000. Add 95005 (historical-only=4321) into new snapshot.
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"LATEST",
	"Normal-Horde",
	table.concat({ "95005:0", "0", encB32(4321), "0", "0", "0" }, ",")
)
mockTSM[13468] = nil
mockTSM[95005] = nil
ns.InvalidatePriceCache()

local capP1, capped1, capSrc1 = ns.GetConservativeSaleUnitPrice(13468, 250000)
check(capP1 == 101000 and capped1 == true and capSrc1 == "Snapshot Market",
	"Conservative anchor should cap spike against Snapshot marketValue, got " .. tostring(capP1) .. " / " .. tostring(capSrc1))

local capP2, capped2, capSrc2 = ns.GetConservativeSaleUnitPrice(95005, 10000)
check(capP2 == 4321 and capped2 == true and capSrc2 == "Snapshot Historical",
	"Conservative anchor should fall back to Snapshot historical, got " .. tostring(capP2) .. " / " .. tostring(capSrc2))

-- TSM dbmarket is ignored in pure standalone mode (Snapshot Market remains sole anchor)
mockTSM[13468] = { dbmarket = 90000 }
ns.InvalidatePriceCache()
local capP3, capped3, capSrc3 = ns.GetConservativeSaleUnitPrice(13468, 250000)
check(capP3 == 101000 and capped3 == true and capSrc3 == "Snapshot Market",
	"Conservative anchor ignores TSM and uses Snapshot Market, got " .. tostring(capP3) .. " / " .. tostring(capSrc3))
mockTSM[13468] = nil
ns.InvalidatePriceCache()

-- 11. DEPTH & VELOCITY Base32 decoding, lazy parsing, cross-economy, re-ingest clear
local depthChunk1 = table.concat({
	"13468:" .. table.concat({
		encB32(80000) .. "," .. encB32(10),
		encB32(90000) .. "," .. encB32(20),
		encB32(110000) .. "," .. encB32(30),
	}, "|"),
	-- Unsorted input + >2^30 price tier test on 95004
	"95004:" .. table.concat({
		encB32(hugePrice) .. "," .. encB32(2),
		encB32(50000) .. "," .. encB32(4),
	}, "|"),
}, ";") .. ";"

local depthChunk2 = "95001:" .. encB32(5400) .. "," .. encB32(12) .. "|" .. encB32(6000) .. "," .. encB32(25)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("DEPTH", "Normal-Horde", depthChunk1)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("DEPTH", "Normal-Horde", depthChunk2)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("DEPTH", "Normal-Alliance", "95001:" .. encB32(7100) .. "," .. encB32(8))

-- Verify lazy depth indexing before first call
check(ns.snapshotRaw["Normal-Horde"].depthIndex == nil, "DEPTH index must remain nil until lazy GetItemSnapshotDepth call")

local dLotus = ns.Pricing.GetItemSnapshotDepth(13468)
check(ns.snapshotRaw["Normal-Horde"].depthIndex ~= nil, "DEPTH index must be built lazily on demand")
check(dLotus ~= nil and #dLotus == 3, "Expected 3 depth tiers for 13468, got " .. tostring(dLotus and #dLotus))
check(dLotus[1].price == 80000 and dLotus[1].qty == 10
	and dLotus[2].price == 90000 and dLotus[2].qty == 20
	and dLotus[3].price == 110000 and dLotus[3].qty == 30,
	"Depth tiers for 13468 mismatch")
-- Mutating returned copy must not corrupt cached tiers
dLotus[1].qty = 0
local dLotus2 = ns.Pricing.GetItemSnapshotDepth(13468)
check(dLotus2[1].qty == 10, "GetItemSnapshotDepth must return a mutation-safe copy")

local dHuge = ns.Pricing.GetItemSnapshotDepth(95004)
check(dHuge ~= nil and #dHuge == 2 and dHuge[1].price == 50000 and dHuge[2].price == hugePrice,
	"DEPTH must sort ascending and decode >2^30 Base32 prices")
local dChunk2 = ns.Pricing.GetItemSnapshotDepth(95001)
check(dChunk2 ~= nil and #dChunk2 == 2 and dChunk2[1].price == 5400 and dChunk2[2].qty == 25,
	"DEPTH multi-chunk decoding failed")
local dAlli = ns.Pricing.GetItemSnapshotDepth(95001, "Normal-Alliance")
check(dAlli ~= nil and #dAlli == 1 and dAlli[1].price == 7100 and dAlli[1].qty == 8,
	"Cross-economy GetItemSnapshotDepth mismatch")
check(ns.Pricing.GetItemSnapshotDepth(999888) == nil, "Missing item depth must return nil")

-- VELOCITY chunks: estDailyX1000, obsHours, confidence (1..3), raw7d
local velChunk1 = table.concat({
	-- 13468: estDailySold=24.5 (24500), obsHours=48, confidence=3, raw7d=171
	"13468:" .. table.concat({ encB32(24500), encB32(48), encB32(3), encB32(171) }, ","),
	-- 95003: noisy obsHours=2 (<3), estDailySold=12.0 (12000), confidence=1, raw7d=5
	"95003:" .. table.concat({ encB32(12000), encB32(2), encB32(1), encB32(5) }, ","),
}, ";") .. ";"
local velChunk2 = "95001:" .. table.concat({ encB32(6250), encB32(12), encB32(2), encB32(31) }, ",")
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("VELOCITY", "Normal-Horde", velChunk1)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("VELOCITY", "Normal-Horde", velChunk2)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("VELOCITY", "Normal-Alliance",
	"95001:" .. table.concat({ encB32(9500), encB32(24), encB32(2), encB32(40) }, ","))

check(ns.snapshotRaw["Normal-Horde"].velocityParsed == nil, "VELOCITY must stay lazy until first GetItemSnapshotVelocity call")
local vLotus = ns.Pricing.GetItemSnapshotVelocity(13468)
check(vLotus ~= nil and math.abs(vLotus.estDailySold - 24.5) < 1e-6
	and vLotus.obsHours == 48 and vLotus.confidence == 3 and vLotus.raw7d == 171
	and vLotus.updatedAt == newUpdatedAt and vLotus.source == "blizzard",
	"VELOCITY decoding mismatch for 13468")
local vAlli = ns.Pricing.GetItemSnapshotVelocity(95001, "Normal-Alliance")
check(vAlli ~= nil and math.abs(vAlli.estDailySold - 9.5) < 1e-6 and vAlli.obsHours == 24,
	"Cross-economy VELOCITY decoding mismatch")
check(ns.Pricing.GetItemSnapshotVelocity(999888) == nil, "Missing item velocity must return nil")

-- 12. GetMultiSourceDemand velocity integration (TSM-free + noisy <3h filter + TSM blend)
local savedMockTSM = _G.TSM_API
local savedRegionSalesCache = db.regionSalesCache
_G.TSM_API = nil
db.regionSalesCache = nil
ns.InvalidatePriceCache()

local demBlizz = ns.GetMultiSourceDemand(13468, "Normal-Horde")
check(demBlizz ~= nil and demBlizz.snapVel ~= nil and math.abs(demBlizz.snapDailySold - 24.5) < 1e-6
	and demBlizz.snapObsHours == 48 and demBlizz.snapConfidence == 3 and demBlizz.snapRaw7d == 171
	and demBlizz.snapSource == "Blizz" and demBlizz.demandSource == "Blizz" and demBlizz.liquidityScore > 50,
	"TSM-free GetMultiSourceDemand should use Blizzard velocity and produce demand heat, got score="
		.. tostring(demBlizz and demBlizz.liquidityScore) .. " src=" .. tostring(demBlizz and demBlizz.demandSource))

local demNoisy = ns.GetMultiSourceDemand(95003, "Normal-Horde")
check(demNoisy ~= nil and demNoisy.snapVel == nil and demNoisy.snapDailySold == nil
	and demNoisy.snapSource == nil and demNoisy.liquidityScore == 0,
	"GetMultiSourceDemand must ignore snapshot velocity with obsHours < 3")

-- Even when _G.TSM_API is present, GetMultiSourceDemand remains 100% pure standalone Blizzard velocity
_G.TSM_API = savedMockTSM
mockTSM[13468] = {
	["dbregionsoldperday * 1000"] = 40000,
	dbregionsoldperday = 40,
	["dbregionsalerate * 1000"] = 650,
	dbregionsaleavg = 95000,
}
ns.InvalidatePriceCache()
local demStandalone = ns.GetMultiSourceDemand(13468, "Normal-Horde")
check(demStandalone ~= nil and demStandalone.tsmDailySold == nil and demStandalone.tsmRealmDailySold == nil
	and math.abs(demStandalone.snapDailySold - 24.5) < 1e-6
	and math.abs(demStandalone.effectiveDailySold - 24.5) < 1e-6
	and demStandalone.snapSource == "Blizz" and demStandalone.demandSource == "Blizz"
	and demStandalone.confidence == "High",
	"GetMultiSourceDemand ignores TSM completely and uses standalone 48h Blizzard realm velocity")
mockTSM[13468] = nil
db.regionSalesCache = savedRegionSalesCache
ns.InvalidatePriceCache()

-- 13. Calculators.BuildSupplyPool depth fallback (multi-tier cost, peek, consume, hitPriceJump)
db.ahLots = {}
local pool = ns.BuildSupplyPool({ respectStock = true })
local poolLots = pool:getLots(13468)
check(poolLots ~= nil and #poolLots == 3 and poolLots[1].source == "Snapshot Depth"
	and poolLots[1].price == 80000 and poolLots[1].qty == 10
	and poolLots[2].price == 90000 and poolLots[2].qty == 20,
	"BuildSupplyPool should fall back to Snapshot Depth tiers when fresh ahLots absent")

local peekCost = pool:peek({ [13468] = 15 })
check(peekCost == (10 * 80000 + 5 * 90000),
	"SupplyPool peek across depth tiers expected 1250000, got " .. tostring(peekCost))
check(pool:peek({ [13468] = 61 }) == nil,
	"SupplyPool peek exceeding total depth stock (60) must return nil")

local spentCost = pool:consume({ [13468] = 15 })
check(spentCost == 1250000, "SupplyPool consume across depth tiers expected 1250000, got " .. tostring(spentCost))
local spentRec = pool.spent[13468]
check(spentRec ~= nil and spentRec.qty == 15 and spentRec.firstPrice == 80000
	and spentRec.maxPrice == 90000 and spentRec.hitPriceJump == true,
	"SupplyPool consume must flag hitPriceJump across Blizzard depth tiers")

-- Fresh in-game ahLots still takes priority over Snapshot Depth
db.ahLots["Normal-Horde"] = {
	[13468] = {
		at = nowTs - 60,
		lots = { { price = 75000, qty = 5 } },
	},
}
local poolLive = ns.BuildSupplyPool({ respectStock = true })
local liveLots = poolLive:getLots(13468)
check(liveLots ~= nil and #liveLots == 1 and liveLots[1].source == "AH Lot" and liveLots[1].price == 75000,
	"Fresh in-game ahLots must still take priority over Snapshot Depth")
db.ahLots = {}

-- 14. MarketScan.GetItemTrend24h & GetItemTrend7d snapshot fallback
-- Load a 24h heat strip + full 7-day heatmap for 13468 under current newUpdatedAt snapshot
local h24List = {}
for h = 0, 23 do
	h24List[#h24List + 1] = encB32(80000 + h * 1000)
end
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"HEAT24",
	"Normal-Horde",
	"13468:" .. table.concat({ encB32(90000), encB32(91500), encB32(45), encB32(10), encB32(100), "-1", "0", "-1", "0" }, ",")
		.. "|" .. table.concat(h24List, ",")
)
local hm7Segs = {}
for dow0 = 0, 6 do
	-- Populate one slot per day (hour 12) with ascending prices across Mon..Sun
	local slot = dow0 * 24 + 12
	local dayPrice = 70000 + dow0 * 5000
	hm7Segs[#hm7Segs + 1] = tostring(slot) .. "=" .. table.concat({ encB32(dayPrice), encB32(dayPrice - 1000), encB32(50), encB32(4) }, ",")
end
_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", "Normal-Horde", "13468:" .. table.concat(hm7Segs, "|"))

db.ahSnapshots = {}
db.ahDaily = {}
db.ahHistory = {}

-- Align trend24hNow to Sunday 23:30 LOCAL time so local hours 00..23 map monotonically over [startHour, curHour] in any timezone!
-- And align trend7dNow to Sunday 12:00 UTC so UTC day curDay-6..curDay maps Mon..Sun monotonically.
local sundayDay = 20779 -- 2026-11-22 (Sunday: (20779 + 3) % 7 + 1 = 7)
local trend7dNow = sundayDay * 86400 + 12 * 3600
local trendNow = os.time({ year = 2026, month = 11, day = 22, hour = 23, min = 30, sec = 0 })

local t24 = ns.MarketScan.GetItemTrend24h(13468, "Normal-Horde", trendNow)
check(t24 ~= nil and t24.source == "snapshot" and t24.hoursCollected == 24 and t24.hasFullDay == true,
	"GetItemTrend24h should fall back to HEAT24 snapshot when ahSnapshots empty, got source=" .. tostring(t24 and t24.source))
check(t24.startPrice24h == 80000 and t24.currentPrice == 103000 and t24.direction == "up"
	and t24.trendPct and math.abs(t24.trendPct - 28.75) < 0.01,
	"GetItemTrend24h snapshot fallback pricing/trend mismatch: " .. tostring(t24.startPrice24h) .. " -> " .. tostring(t24.currentPrice))

local t7 = ns.MarketScan.GetItemTrend7d(13468, "Normal-Horde", trend7dNow)
check(t7 ~= nil and t7.source == "snapshot" and t7.daysCollected == 7 and t7.hasFullWeek == true,
	"GetItemTrend7d should fall back to HEAT7X24 snapshot when ahDaily empty, got source=" .. tostring(t7 and t7.source))
check(t7.startPrice7d == 70000 and t7.currentPrice == 100000 and t7.direction == "up"
	and t7.trendPct and math.abs(t7.trendPct - ((100000 - 70000) / 70000 * 100)) < 0.01,
	"GetItemTrend7d snapshot fallback pricing/trend mismatch: " .. tostring(t7.startPrice7d) .. " -> " .. tostring(t7.currentPrice))

-- Bidirectional merge in GetItemTrend24h: live ahSnapshots wins on overlapping hours while snapshot fills gaps
db.ahSnapshots["Normal-Horde"] = {
	[13468] = { trendNow - 7200, 120000, 10, trendNow - 3600, 110000, 8 },
	[95002] = { trendNow - 7200, 120000, 10, trendNow - 3600, 110000, 8 },
}
local t24Merged = ns.MarketScan.GetItemTrend24h(13468, "Normal-Horde", trendNow)
check(t24Merged ~= nil and t24Merged.source == "merged" and t24Merged.hoursCollected == 24 and t24Merged.hasFullDay == true,
	"GetItemTrend24h with live + snapshot must return source='merged' and full 24h coverage, got "
		.. tostring(t24Merged and t24Merged.source) .. " / " .. tostring(t24Merged and t24Merged.hoursCollected))
local mergedByH = {}
for _, pt in ipairs(t24Merged.points) do mergedByH[pt.h] = pt end
local hMinus2 = math.floor((trendNow - 7200) / 3600)
local hMinus1 = math.floor((trendNow - 3600) / 3600)
check(mergedByH[hMinus2] and mergedByH[hMinus2].price == 120000
	and mergedByH[hMinus1] and mergedByH[hMinus1].price == 110000,
	"GetItemTrend24h merged mode must let live ahSnapshots win on overlapping hours")

-- Live-only item (no snapshot) stays source='ahSnapshots'
local t24LiveOnly = ns.MarketScan.GetItemTrend24h(95002, "Normal-Horde", trendNow)
check(t24LiveOnly ~= nil and t24LiveOnly.source == "ahSnapshots" and t24LiveOnly.direction == "down" and t24LiveOnly.currentPrice == 110000,
	"Live-only ahSnapshots item must return source='ahSnapshots'")

-- Bidirectional merge in GetItemTrend7d: live ahDaily wins on overlapping days while snapshot fills missing days
db.ahDaily["Normal-Horde"] = {
	[13468] = {
		{ d = sundayDay - 1, lastP = 115000, obsP = 115000, lastQ = 14, at = trend7dNow - 86400 },
		{ d = sundayDay, lastP = 125000, obsP = 125000, lastQ = 12, at = trend7dNow },
	},
}
local t7Merged = ns.MarketScan.GetItemTrend7d(13468, "Normal-Horde", trend7dNow)
check(t7Merged ~= nil and t7Merged.source == "merged" and t7Merged.daysCollected == 7 and t7Merged.hasFullWeek == true,
	"GetItemTrend7d with partial live ahDaily + snapshot must return source='merged' and 7 days, got "
		.. tostring(t7Merged and t7Merged.source) .. " / " .. tostring(t7Merged and t7Merged.daysCollected))
check(t7Merged.startPrice7d == 70000 and t7Merged.currentPrice == 125000 and t7Merged.direction == "up",
	"GetItemTrend7d merged mode must keep snapshot baseline for missing days and live price on today")
db.ahSnapshots = {}
db.ahDaily = {}

-- 15. Non-destructive live-scan overlay on GetItemHeatmap & GetItemHeatStrip24h (local time + dedup!)
local hmBaseBefore = ns.Pricing.GetItemHeatmap(13468, "Normal-Horde")
local stripBaseBefore = ns.Pricing.GetItemHeatStrip24h(13468, "Normal-Horde")
check(hmBaseBefore ~= nil and stripBaseBefore ~= nil and not hmBaseBefore.hasLiveOverlay and not stripBaseBefore.hasLiveOverlay,
	"Base heatmap and 24h strip must start without live overlay")
local baseMon12Avg = hmBaseBefore.cells[1][12].avgPrice
local baseMon12Samples = hmBaseBefore.cells[1][12].samples
local baseStripH14 = stripBaseBefore.hourly[14]
-- Use LOCAL timestamps (Monday 2026-11-23 12:05 and 14:10 local time) so tests pass in any timezone!
local mon12Ts = os.time({ year = 2026, month = 11, day = 23, hour = 12, min = 5, sec = 0 })
local mon14Ts = os.time({ year = 2026, month = 11, day = 23, hour = 14, min = 10, sec = 0 })
check(mon12Ts > newUpdatedAt, "Live overlay test timestamp must be newer than snapshot updatedAt")
-- First verify timestamp deduplication when BOTH ahSnapshots and ahPrices record the exact same mon12Ts!
db.ahSnapshots["Normal-Horde"] = {
	[13468] = { mon12Ts, 120000, 10 },
}
db.ahPrices["Normal-Horde"] = {
	[13468] = { price = 120000, qty = 10, at = mon12Ts },
}
local hmDedup = ns.Pricing.GetItemHeatmap(13468, "Normal-Horde")
check(hmDedup ~= nil and hmDedup.cells[1][12].samples == baseMon12Samples + 1
	and hmDedup.cells[1][12].avgPrice == 80000,
	"Duplicate live timestamp across ahSnapshots + ahPrices must count ONCE (samples="
		.. tostring(hmDedup and hmDedup.cells[1][12].samples) .. ")")

-- Now add distinct ahPrices at local Monday 14:10 -> populates cells[1][14] cleanly
db.ahPrices["Normal-Horde"] = {
	[13468] = { price = 140000, qty = 5, at = mon14Ts },
}
local hmOver = ns.Pricing.GetItemHeatmap(13468, "Normal-Horde")
check(hmOver ~= nil and hmOver ~= hmBaseBefore and hmOver.hasLiveOverlay == true and hmOver.updatedAt == mon14Ts,
	"GetItemHeatmap must return a non-destructive overlaid copy when live scans are newer than meta.updatedAt")
-- Monday 12:00 had avg=70000, samples=4; live added 120000 (n=1) -> weighted avg = (70000*4 + 120000)/5 = 80000
check(hmOver.cells[1][12].avgPrice == 80000 and hmOver.cells[1][12].samples == baseMon12Samples + 1
	and hmOver.cells[1][12].liveOverlay == true,
	"GetItemHeatmap live overlay must blend into matching local (dow, hour) cell, got " .. tostring(hmOver.cells[1][12].avgPrice))
-- Monday 14:00 was empty; live ahPrices populates it cleanly and updates daily[1] & hourly[14]
check(hmOver.cells[1][14] ~= nil and hmOver.cells[1][14].avgPrice == 140000 and hmOver.hourly[14] ~= nil
	and hmOver.hourly[14].avgPrice == 140000 and hmOver.daily[1].samples == baseMon12Samples + 2,
	"GetItemHeatmap live overlay must populate empty local slot and update daily/hourly aggregates")
-- Cached base snapshot MUST remain untouched
check(hmBaseBefore.cells[1][12].avgPrice == baseMon12Avg and hmBaseBefore.cells[1][14] == nil,
	"GetItemHeatmap live overlay must NOT mutate cached base snapshot")

local stripOver = ns.Pricing.GetItemHeatStrip24h(13468, "Normal-Horde")
check(stripOver ~= nil and stripOver ~= stripBaseBefore and stripOver.hasLiveOverlay == true
	and stripOver.hourly[12] == 120000 and stripOver.hourly[14] == 140000 and stripOver.updatedAt == mon14Ts,
	"GetItemHeatStrip24h must overlay fresher live scans onto matching local hour slots without mutating cache")
check(stripBaseBefore.hourly[14] == baseStripH14,
	"GetItemHeatStrip24h live overlay must NOT mutate cached base heat24 strip")
db.ahSnapshots = {}
db.ahPrices = {}

-- 16. Pure Standalone VELOCITY wire ingestion, META velocityObsHours, GetDailySold & REGSALE removal
local regMetaTs = newUpdatedAt + 120
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"META",
	"Normal-Horde",
	string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=2,heatmapCount=0,depthCount=0,velocityCount=1,velocityObsHours=36}]], regMetaTs)
)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"VELOCITY",
	"Normal-Horde",
	"10504:" .. table.concat({ encB32(600), encB32(6), encB32(1), encB32(4) }, ",")
)

local regMeta = ns.Pricing.GetSnapshotMeta("Normal-Horde")
check(regMeta ~= nil and regMeta.velocityObsHours == 36 and regMeta.regSaleCount == nil,
	"GetSnapshotMeta exposes velocityObsHours and omits removed regSaleCount")
check(ns.Pricing.GetItemSnapshotRegionSale == nil and ns.GetRegionSaleDetails == nil,
	"Legacy REGSALE / GetRegionSaleDetails APIs removed in pure standalone mode")

-- GetDailySold returns single-realm Blizzard Snapshot velocity directly (obsHours >= 3)
ns.InvalidatePriceCache()
local dsSnap = ns.GetDailySold(10504)
check(dsSnap ~= nil and math.abs(dsSnap - 0.6) < 1e-6,
	"GetDailySold must return standalone Blizzard Snapshot velocity (0.6/d), got " .. tostring(dsSnap))

-- 17. Standalone GetMultiSourceDemand (Blizzard Snapshot velocity + Personal ledger floor)
local savedAnalytics = ns.Analytics
local mockPersonalSold = 8 -- 8 Green Lenses / 7d = 1.142857/d
ns.Analytics = {
	Store = { version = 101 },
	Model = {
		GetItemDetail = function(id)
			if id == 10504 or id == 95011 then
				return { itemID = id, windows = { d7 = { sold = mockPersonalSold } } }
			end
			return nil
		end,
	},
}
ns.InvalidatePriceCache()
-- Green Lens 10504 has Blizz est=0.6/d, personal = 8/7 = 1.142857/d -> effectiveDailySold = max(0.6, 8/7) = 1.142857, demandSource='Blizz+You'
local mdLens = ns.GetMultiSourceDemand(10504, "Normal-Horde")
check(mdLens ~= nil and mdLens.tsmDailySold == nil and mdLens.tsmRealmDailySold == nil
	and math.abs(mdLens.personalDailySold - (8 / 7)) < 1e-6
	and math.abs(mdLens.effectiveDailySold - (8 / 7)) < 1e-5
	and mdLens.dailySold == mdLens.effectiveDailySold
	and mdLens.demandSource == "Blizz+You" and mdLens.confidence == "High"
	and mdLens.velocityObsHours == 36,
	"Standalone Green Lens 10504 demand mismatch: eff=" .. tostring(mdLens and mdLens.effectiveDailySold)
		.. " src=" .. tostring(mdLens and mdLens.demandSource))

-- Raise personal sales to 21/7d (3.0/d) -> personal floor lifts effectiveDailySold to 3.0!
mockPersonalSold = 21
ns.Analytics.Store.version = 102
local mdLensFloor = ns.GetMultiSourceDemand(10504, "Normal-Horde")
check(mdLensFloor ~= nil and math.abs(mdLensFloor.effectiveDailySold - 3.0) < 1e-6
	and mdLensFloor.demandSource == "Blizz+You" and mdLensFloor.confidence == "High",
	"Personal floor must lift effectiveDailySold to >= personalDailySold (3.0), got "
		.. tostring(mdLensFloor and mdLensFloor.effectiveDailySold))

-- Personal-only item (95011: no Blizz, no Local) -> effectiveDailySold = 3.0, demandSource='Personal'
local mdPersonalOnly = ns.GetMultiSourceDemand(95011, "Normal-Horde")
check(mdPersonalOnly ~= nil and math.abs(mdPersonalOnly.effectiveDailySold - 3.0) < 1e-6
	and mdPersonalOnly.demandSource == "Personal" and mdPersonalOnly.confidence == "High",
	"Personal-only demand must floor at personalDailySold with demandSource='Personal'")

-- 17b. Observed-zero over 48h without TSM/Local -> snapDailySold=0, effectiveDailySold=0, Blizz, Med
local obsZeroMetaTs = regMetaTs + 30
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"META",
	"Normal-Horde",
	string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=2,heatmapCount=0,depthCount=0,velocityCount=1,velocityObsHours=48}]], obsZeroMetaTs)
)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"LATEST",
	"Normal-Horde",
	table.concat({
		-- 95021: listed (qty=12), 0 vanishes over 48h
		table.concat({ "95021:" .. encB32(10000), encB32(10000), encB32(10000), encB32(12), encB32(4), "0" }, ","),
		-- 10504: listed (qty=10)
		table.concat({ "10504:" .. encB32(17000), encB32(17500), encB32(20000), encB32(10), encB32(4), "0" }, ","),
	}, ";")
)
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"VELOCITY",
	"Normal-Horde",
	"10504:" .. table.concat({ encB32(600), encB32(6), encB32(1), encB32(4) }, ",")
)
ns.InvalidatePriceCache()

local mdZeroNoTSM = ns.GetMultiSourceDemand(95021, "Normal-Horde")
check(mdZeroNoTSM ~= nil and mdZeroNoTSM.snapDailySold == 0 and mdZeroNoTSM.snapObsHours == 48
	and mdZeroNoTSM.effectiveDailySold == 0 and mdZeroNoTSM.demandSource == "Blizz"
	and mdZeroNoTSM.confidence == "Med",
	"Observed-zero (48h) must report effectiveDailySold=0, Blizz, Med, got eff="
		.. tostring(mdZeroNoTSM and mdZeroNoTSM.effectiveDailySold) .. " src="
		.. tostring(mdZeroNoTSM and mdZeroNoTSM.demandSource) .. " conf="
		.. tostring(mdZeroNoTSM and mdZeroNoTSM.confidence))

-- 17c. Round 2 regressions: multiDemandCache + personal7dCache invalidation (midnight, Store.db swap, Model.generation, accountingVersion drift)
do
	local soldFlag = 14 -- 2.0/d
	local mockStore = {
		ahSalesVersion = 5,
		accountingVersion = 5,
		_trackedAccountingVersion = 5,
		db = { id = "db1" },
	}
	local mockModel = {
		generation = 1,
		GetItemStats = function() return nil end,
		Compute = function()
			return { byItemID = { [95011] = { itemID = 95011, ahSold = soldFlag } } }
		end,
	}
	ns.Analytics = { Store = mockStore, Model = mockModel }
	local mdA = ns.GetMultiSourceDemand(95011, "Normal-Horde")
	check(mdA ~= nil and math.abs(mdA.personalDailySold - 2.0) < 1e-6, "Cache invalidation baseline must read 2.0/d")

	-- (a) Midnight rollover (+8d) invalidates both caches without bumping versions
	soldFlag = 0
	local prevNow = nowTs
	nowTs = nowTs + 8 * 86400
	local mdDay = ns.GetMultiSourceDemand(95011, "Normal-Horde")
	check(mdDay ~= nil and mdDay.personalDailySold == 0,
		"Midnight rollover must invalidate multiDemandCache & personal7dCache, got " .. tostring(mdDay and mdDay.personalDailySold))

	-- (b) Store.Init() DB table swap invalidates both caches even with unchanged ahSalesVersion
	soldFlag = 21 -- 3.0/d
	mockStore.db = { id = "db2" }
	local mdSwap = ns.GetMultiSourceDemand(95011, "Normal-Horde")
	check(mdSwap ~= nil and math.abs(mdSwap.personalDailySold - 3.0) < 1e-6,
		"Store.db swap must invalidate multiDemandCache & personal7dCache, got " .. tostring(mdSwap and mdSwap.personalDailySold))

	-- (c) Model.Invalidate() generation bump invalidates both caches
	soldFlag = 7 -- 1.0/d
	mockModel.generation = 2
	local mdGen = ns.GetMultiSourceDemand(95011, "Normal-Horde")
	check(mdGen ~= nil and math.abs(mdGen.personalDailySold - 1.0) < 1e-6,
		"Model.generation bump must invalidate multiDemandCache & personal7dCache, got " .. tostring(mdGen and mdGen.personalDailySold))

	-- (d) Direct Store.accountingVersion drift (_trackedAccountingVersion ~= accountingVersion) invalidates both caches
	soldFlag = 28 -- 4.0/d
	mockStore.accountingVersion = 6
	local mdAcc = ns.GetMultiSourceDemand(95011, "Normal-Horde")
	check(mdAcc ~= nil and math.abs(mdAcc.personalDailySold - 4.0) < 1e-6,
		"Store.accountingVersion drift must invalidate multiDemandCache & personal7dCache, got " .. tostring(mdAcc and mdAcc.personalDailySold))

	nowTs = prevNow
end

-- 18. RecipeStats.lua BUG-3 fix: pExp > 0 with 0 sales NEVER wipes market velocity!
local lensRec = {
	idx = 99504, spellID = 12717, name = "Green Lens", prof = "engineering", skill = 245,
	outputItemID = 10504, acqType = "trainer", sellable = true, numMade = 1, reagents = {},
}
ns.Analytics = {
	Store = {
		version = 200,
		db = { stats = { firstLive = { ["Normal-Horde-Test"] = nowTs - 10 * 86400 } } },
		DeriveEcon = function(c) return c:match("^([^%-]+%-[^%-]+)") end,
	},
	Model = {
		Compute = function()
			return {
				rows = {
					{ itemID = 10504, ahSold = 0, sold = 0, expired = 3, ahVelocity = 0, velocity = 0 },
				},
			}
		end,
	},
}
ns.RecipeStats.Invalidate("bug3_test")
local bug3Ctx = {
	profMap = {}, repState = { standing = 4 }, ownedCounts = {}, trainerCosts = {},
	economy = "Normal-Horde", charKey = "Normal-Horde-Test", now = nowTs,
}
local lensStats = ns.RecipeStats.Get(lensRec, bug3Ctx)
check(lensStats ~= nil and lensStats.salesPerDay ~= nil and lensStats.salesPerDay > 0
	and math.abs(lensStats.salesPerDay - 0.6) < 1e-6 and lensStats.salesScope == "Blizzard",
	"BUG-3: expired auctions (pExp=3, pSold=0) must NOT wipe market velocity to 0, got "
		.. tostring(lensStats and lensStats.salesPerDay) .. " / " .. tostring(lensStats and lensStats.salesScope))
check(lensStats.marketSalesPerDay ~= nil and math.abs(lensStats.marketSalesPerDay - 0.6) < 1e-6
	and lensStats.snapDailySold ~= nil and math.abs(lensStats.snapDailySold - 0.6) < 1e-6,
	"RecipeStats must attach marketSalesPerDay and snapDailySold for tooltips & DeepAnalysis")
ns.Analytics = savedAnalytics
ns.RecipeStats.Invalidate("bug3_cleanup")

-- Re-ingest fresh META clears DEPTH and VELOCITY caches cleanly
_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
	"META",
	"Normal-Horde",
	string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=0,heatmapCount=0}]], regMetaTs + 60)
)
check(ns.Pricing.GetItemSnapshotDepth(13468, "Normal-Horde") == nil, "Fresh META re-ingest must clear DEPTH")
check(ns.Pricing.GetItemSnapshotVelocity(13468, "Normal-Horde") == nil, "Fresh META re-ingest must clear VELOCITY")

-- 19. L2 & L4 regressions: lazy HEAT24 indexing, IngestSnapshotData batching, heat24OverlayCache & ShouldPreferSnapshotOverTSM cache invalidation
;(function()
	local l2Econ = "PvP-Horde"
	local l2UpdatedAt = 1795400000
	local epochStart = ns.priceCacheEpoch
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"META",
		l2Econ,
		string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=2,heatmapCount=2}]], l2UpdatedAt)
	)
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"LATEST",
		l2Econ,
		table.concat({
			"13468:" .. table.concat({ encB32(91000), encB32(92000), encB32(90000), encB32(40), encB32(12), "0" }, ","),
			"95001:" .. table.concat({ encB32(6100), encB32(6200), encB32(6000), encB32(25), encB32(8), "0" }, ","),
		}, ";")
	)
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"HEAT24",
		l2Econ,
		table.concat({
			"13468:" .. table.concat({ encB32(91000), encB32(91500), encB32(40), encB32(10), encB32(30), "-1", "0", "-1", "0" }, ",")
				.. "|" .. encB32(91000) .. ",,,,,,,,,,,,,,,,,,,,,,,",
			"95001:" .. table.concat({ encB32(6100), encB32(6200), encB32(25), encB32(5), encB32(15), "-1", "0", "-1", "0" }, ",")
				.. "|" .. encB32(6100) .. ",,,,,,,,,,,,,,,,,,,,,,,",
		}, ";")
	)
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", l2Econ, "13468:0=" .. table.concat({ encB32(91000), encB32(90000), encB32(40), encB32(4) }, ","))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("DEPTH", l2Econ, "13468:" .. encB32(91000) .. "," .. encB32(10))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("VELOCITY", l2Econ, "13468:" .. table.concat({ encB32(12000), encB32(24), encB32(2), encB32(50) }, ","))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("REGSALE", l2Econ, "13468:" .. table.concat({ encB32(92000), encB32(15000), encB32(400) }, ","))

	-- L2a: Fresh batch ingest bumps priceCacheEpoch once on META, not 7 times across every chunk
	check(ns.priceCacheEpoch == epochStart + 1,
		"Batch ingest of META + 6 chunk tags must bump priceCacheEpoch once, got delta=" .. tostring(ns.priceCacheEpoch - epochStart))

	-- L2b: First QueryLocalSnapshot parses LATEST only; HEAT24 index and decoded table remain nil
	local pL2 = ns.QueryLocalSnapshot(13468, l2Econ)
	check(pL2 == 91000, "QueryLocalSnapshot must return LATEST minBuyout (91000), got " .. tostring(pL2))
	local rawL2 = ns.snapshotRaw[l2Econ]
	check(rawL2 ~= nil and rawL2.heat24Index == nil and rawL2.heat24Decoded == nil,
		"QueryLocalSnapshot must NOT build heat24Index or decode HEAT24 items")

	-- L2c: Requesting one item's HEAT24 decodes only that item, leaving unrequested items undecoded
	local sL2 = ns.Pricing.GetItemHeatStrip24h(13468, l2Econ)
	check(sL2 ~= nil and sL2.medianPrice == 91000 and rawL2.heat24Index ~= nil
		and rawL2.heat24Decoded ~= nil and rawL2.heat24Decoded[13468] == sL2
		and rawL2.heat24Decoded[95001] == nil,
		"GetItemHeatStrip24h must lazily decode only requested item 13468 and leave 95001 undecoded")

	-- L4a: heat24OverlayCache caches merged overlay strip and invalidates immediately on newer ahSnapshots or ahPrices
	local ovTs1 = os.time({ year = 2026, month = 11, day = 25, hour = 10, min = 5, sec = 0 })
	local ovTs2 = os.time({ year = 2026, month = 11, day = 25, hour = 11, min = 5, sec = 0 })
	local ovTs3 = os.time({ year = 2026, month = 11, day = 25, hour = 13, min = 5, sec = 0 })
	check(ovTs1 > l2UpdatedAt, "Overlay test timestamps must be newer than snapshot updatedAt")
	db.ahSnapshots[l2Econ] = { [13468] = { ovTs1, 105000, 12 } }
	db.ahPrices[l2Econ] = {}

	local ovStrip1 = ns.Pricing.GetItemHeatStrip24h(13468, l2Econ)
	local ovStrip2 = ns.Pricing.GetItemHeatStrip24h(13468, l2Econ)
	check(ovStrip1 ~= nil and ovStrip1.hasLiveOverlay == true and ovStrip1.hourly[10] == 105000,
		"First overlaid GetItemHeatStrip24h must reflect ahSnapshots entry")
	check(ovStrip2 == ovStrip1 and rawL2.heat24OverlayCache and rawL2.heat24OverlayCache[13468] ~= nil,
		"Repeated GetItemHeatStrip24h with unchanged scans must return cached overlay strip")

	-- Append newer ahSnapshots triplet -> cache must invalidate immediately
	local arr = db.ahSnapshots[l2Econ][13468]
	arr[#arr + 1] = ovTs2
	arr[#arr + 1] = 118000
	arr[#arr + 1] = 7
	local ovStrip3 = ns.Pricing.GetItemHeatStrip24h(13468, l2Econ)
	check(ovStrip3 ~= nil and ovStrip3 ~= ovStrip1 and ovStrip3.hourly[11] == 118000 and ovStrip3.updatedAt == ovTs2,
		"Appending newer ahSnapshots triplet must immediately invalidate heat24OverlayCache")

	-- Newer ahPrices scan -> cache must invalidate immediately
	db.ahPrices[l2Econ][13468] = { price = 125000, qty = 4, at = ovTs3 }
	local ovStrip4 = ns.Pricing.GetItemHeatStrip24h(13468, l2Econ)
	check(ovStrip4 ~= nil and ovStrip4 ~= ovStrip3 and ovStrip4.hourly[13] == 125000 and ovStrip4.updatedAt == ovTs3,
		"Newer ahPrices scan must immediately invalidate heat24OverlayCache")

	-- Marking ahPrices absent -> cache must invalidate immediately
	db.ahPrices[l2Econ][13468].absent = true
	local ovStrip5 = ns.Pricing.GetItemHeatStrip24h(13468, l2Econ)
	check(ovStrip5 ~= nil and ovStrip5 ~= ovStrip4 and ovStrip5.hourly[13] == nil and ovStrip5.updatedAt == ovTs2,
		"Marking ahPrices absent must immediately invalidate heat24OverlayCache")
	db.ahSnapshots[l2Econ] = nil
	db.ahPrices[l2Econ] = nil

	ns.snapshotRaw[l2Econ] = nil
	ns.snapshotParsed[l2Econ] = nil
	ns.snapshotHeatmapCache[l2Econ] = nil
end)()

---------------------------------------------------------------------------------------------------
-- 18. Pure Standalone Pricing & SavedVariables Legacy Migration
---------------------------------------------------------------------------------------------------
;(function()
	local econKey = "Normal-Horde"
	local savedNow = nowTs
	nowTs = 1795500000
	db.economy = "auto"
	db.priceSource = "auto"
	db.ahPrices = {}
	db.ahLots = {}
	db.econSnapshots = {}
	ns.ahPrices = {}
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	ns.snapshotHeatmapCache = {}

	local legacyTSM = {
		[95099] = {
			dbminbuyout = 4100,
			dbmarket = 4400,
			dbnumauctions = 14,
			vendorbuy = 1234,
			vendorsell = 567,
		},
	}
	_G.TSM_API = {
		GetCustomPriceValue = function(expr, itemStr)
			local id = tonumber(tostring(itemStr):match("i:(%d+)"))
			local row = id and legacyTSM[id]
			return row and row[expr] or nil
		end,
	}
	_G.Auctionator = {
		API = {
			v1 = {
				GetAuctionPriceByItemID = function(_, id) return id == 95099 and 5100 or nil end,
				GetAuctionAgeByItemID = function(_, id) return id == 95099 and 1 or nil end,
			},
		},
	}
	_G.AucAdvanced = {
		API = {
			GetMarketValue = function(link)
				local id = tonumber(tostring(link):match("item:(%d+)"))
				return id == 95099 and 5300 or nil
			end,
		},
	}

	local snapTs = nowTs - 600
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"META",
		econKey,
		string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=0,depthCount=0,velocityCount=1,velocityObsHours=36}]], snapTs)
	)
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"LATEST",
		econKey,
		table.concat({ "95098:" .. encB32(8200), encB32(8500), encB32(8000), encB32(30), encB32(12), "0" }, ",")
	)
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
		"VELOCITY",
		econKey,
		"95098:" .. table.concat({ encB32(14500), encB32(36), encB32(3), encB32(95) }, ",")
	)

	ns.InvalidateEconomyDetectCache()
	ns.InvalidatePriceCache()

	check(ns.UseLegacyPriceAddons == nil and ns.IsLegacyPriceSource == nil,
		"Legacy addon gate helpers removed in pure standalone mode")
	check(ns.QueryTSM == nil and ns.QueryAuctionator == nil and ns.QueryAuctioneer == nil
		and ns.GetParsedTSMEconomy == nil and ns.GetTSMConfiguredAltEconomy == nil
		and ns.GetAuctionatorMarketStats == nil,
		"All legacy third-party price/stat bridge functions removed")

	local avail = ns.GetAvailablePriceSources()
	check(type(avail) == "table" and #avail == 3,
		"GetAvailablePriceSources must return strictly 3 standalone sources, got " .. tostring(avail and #avail))
	local availKeys = {}
	for _, s in ipairs(avail) do availKeys[s.key] = true end
	check(availKeys.auto and availKeys.snapshot and availKeys.live_ah and not availKeys.tsm_min,
		"GetAvailablePriceSources exposes only auto, snapshot, live_ah")

	-- SavedVariables migration normalizes legacy priceSource keys to "auto"
	for _, legKey in ipairs({ "tsm_min", "tsm_market", "auctionator", "auctioneer" }) do
		db.priceSource = legKey
		check(ns.GetEffectivePriceSource() == "auto",
			"Legacy priceSource '" .. legKey .. "' normalizes to 'auto'")
		check(ns.CurrentSourceInfo().key == "auto",
			"CurrentSourceInfo reports 'auto' for migrated '" .. legKey .. "'")
		check(db.priceSource == "auto",
			"SavedVariables migration overwrites legacy db.priceSource '" .. legKey .. "' -> 'auto'")
	end
	db.priceSource = "auto"
	ns.InvalidatePriceCache()

	-- Auto pricing never falls back to TSM/Auctionator/Auctioneer
	check(ns.GetVendorBuyPrice(95099, nil, true, 0, false) == nil, "GetVendorBuyPrice never queries TSM vendorbuy")
	check(ns.GetVendorSellPrice(95099) == nil, "GetVendorSellPrice never queries TSM vendorsell")
	local pBlocked, srcBlocked = ns.GetItemMarketPrice(95099)
	check(pBlocked == nil and srcBlocked == nil,
		"GetItemMarketPrice returns nil when no Live AH/Snapshot exists, got " .. tostring(pBlocked) .. " / " .. tostring(srcBlocked))
	check(ns.GetNumListed(95099) == nil, "GetNumListed never reads TSM dbnumauctions")

	-- Legacy economy keys ("tsm_alt", "region") normalize cleanly to "auto"
	for _, legEcon in ipairs({ "tsm_alt", "region" }) do
		db.economy = legEcon
		ns.InvalidatePriceCache()
		local altEconInfo = ns.CurrentEconomyInfo()
		check(altEconInfo.selectedKey == "auto" and altEconInfo.effectiveKey == econKey and db.economy == "auto",
			"Legacy economy '" .. legEcon .. "' normalizes to 'auto', got " .. tostring(altEconInfo.selectedKey) .. " / " .. tostring(db.economy))
	end
	db.economy = "auto"

	-- Blizzard velocity stays preserved in GetRealmAdjustedDailySold & GetMultiSourceDemand
	ns.InvalidatePriceCache()
	local adjVel = ns.GetRealmAdjustedDailySold(95098)
	check(type(adjVel) == "number" and adjVel > 0,
		"GetRealmAdjustedDailySold preserves Blizzard velocity, got " .. tostring(adjVel))
	if ns.GetMultiSourceDemand then
		local msd = ns.GetMultiSourceDemand(95098)
		check(msd ~= nil and msd.tsmDailySold == nil and msd.tsmRealmDailySold == nil
			and msd.snapVel ~= nil and msd.snapDailySold ~= nil and msd.snapDailySold > 0,
			"GetMultiSourceDemand preserves standalone Blizzard velocity with zero TSM fields")
	end

	nowTs = savedNow
end)()

---------------------------------------------------------------------------------------------------
-- 19. Strictly Newest-Wins (Live AH vs Local Snapshot) across all pricing, listing & supply APIs
---------------------------------------------------------------------------------------------------
;(function()
	local econKey = "Normal-Horde"
	local savedNow = nowTs
	nowTs = 1795600000
	db.economy = "auto"
	db.priceSource = "auto"
	db.ahPrices = { [econKey] = {} }
	db.ahLots = { [econKey] = {} }
	db.econSnapshots = {}
	ns.ahPrices = {}
	ns.tsmSyncedEconomies = {}
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	ns.snapshotHeatmapCache = {}

	local function seedSnap(snapUpdatedAt, price, qty, depthPrice)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
			"META",
			econKey,
			string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1,heatmapCount=0,depthCount=1}]], snapUpdatedAt)
		)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
			"LATEST",
			econKey,
			table.concat({ "95111:" .. encB32(price), encB32(price + 200), encB32(price - 200), encB32(qty), encB32(9), "0" }, ",")
		)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS(
			"DEPTH",
			econKey,
			"95111:" .. encB32(depthPrice or price) .. "," .. encB32(qty)
		)
	end

	-- 19a. 5m Blizzard Snapshot beats 20m Live AH (even though 20m Live AH is still <= 30m fresh!) in BOTH legacy OFF and legacy ON
	for _, legacyFlag in ipairs({ false, true }) do
		db.enableLegacyPriceAddons = legacyFlag
		seedSnap(nowTs - 300, 6200, 44, 6200)
		db.ahPrices[econKey][95111] = { price = 5000, qty = 11, at = nowTs - 1200 }
		ns.InvalidatePriceCache()

		local p, src, stk = ns.GetItemMarketPrice(95111)
		check(p == 6200 and src == "Snapshot" and stk == 44,
			string.format("5m Snapshot must beat 20m Live AH (legacy=%s), got %s / %s / %s",
				tostring(legacyFlag), tostring(p), tostring(src), tostring(stk)))

		local fp, fsrc = ns.GetFallbackMarketPrice(95111)
		check(fp == 6200 and fsrc == "Snapshot",
			string.format("GetFallbackMarketPrice: 5m Snapshot must beat 20m Live AH (legacy=%s), got %s / %s",
				tostring(legacyFlag), tostring(fp), tostring(fsrc)))

		local lp, lsrc = ns.GetLastKnownAHPrice(95111)
		check(lp == 6200 and lsrc == "Snapshot",
			string.format("GetLastKnownAHPrice: 5m Snapshot must beat 20m Live AH (legacy=%s), got %s / %s",
				tostring(legacyFlag), tostring(lp), tostring(lsrc)))

		local nl = ns.GetNumListed(95111)
		check(nl == 44,
			string.format("GetNumListed: 5m Snapshot qty (44) must beat 20m Live AH qty (11) (legacy=%s), got %s",
				tostring(legacyFlag), tostring(nl)))
	end

	-- 19b. 2m Live AH beats 10m Blizzard Snapshot (and equal timestamp favors Live AH)
	db.enableLegacyPriceAddons = false
	seedSnap(nowTs - 600, 6200, 44, 6200)
	db.ahPrices[econKey][95111] = { price = 5000, qty = 11, at = nowTs - 120 }
	ns.InvalidatePriceCache()

	local pLive, srcLive, stkLive = ns.GetItemMarketPrice(95111)
	check(pLive == 5000 and srcLive == "Live AH" and stkLive == 11,
		"2m Live AH must beat 10m Snapshot, got " .. tostring(pLive) .. " / " .. tostring(srcLive))
	local fpLive, fsrcLive = ns.GetFallbackMarketPrice(95111)
	check(fpLive == 5000 and fsrcLive == "Live AH",
		"GetFallbackMarketPrice: 2m Live AH must beat 10m Snapshot, got " .. tostring(fpLive) .. " / " .. tostring(fsrcLive))
	local lpLive, lsrcLive = ns.GetLastKnownAHPrice(95111)
	check(lpLive == 5000 and lsrcLive == "Live AH Scan",
		"GetLastKnownAHPrice: 2m Live AH must beat 10m Snapshot, got " .. tostring(lpLive) .. " / " .. tostring(lsrcLive))
	check(ns.GetNumListed(95111) == 11, "GetNumListed: 2m Live AH qty (11) must beat 10m Snapshot qty (44)")

	-- Equal timestamp tie -> Live AH wins (liveAt >= snapAt)
	db.ahPrices[econKey][95111].at = nowTs - 600
	ns.InvalidatePriceCache()
	local pTie, srcTie = ns.GetItemMarketPrice(95111)
	check(pTie == 5000 and srcTie == "Live AH", "Tie timestamp must prefer Live AH, got " .. tostring(pTie) .. " / " .. tostring(srcTie))

	-- 19c. Legacy OFF pure newest-wins beyond 90m / 6h cutoffs
	seedSnap(nowTs - 28800, 6200, 44, 6200) -- 8h old
	db.ahPrices[econKey][95111] = { price = 5000, qty = 11, at = nowTs - 36000 } -- 10h old
	ns.InvalidatePriceCache()
	local pOldSnap, srcOldSnap = ns.GetItemMarketPrice(95111)
	check(pOldSnap == 6200 and srcOldSnap == "Snapshot",
		"Legacy OFF: 8h Snapshot must beat 10h Saved AH, got " .. tostring(pOldSnap) .. " / " .. tostring(srcOldSnap))

	db.ahPrices[econKey][95111].at = nowTs - 18000 -- 5h old > 8h snapshot
	ns.InvalidatePriceCache()
	local pOldLive, srcOldLive = ns.GetItemMarketPrice(95111)
	check(pOldLive == 5000 and srcOldLive == "Saved AH Scan",
		"Legacy OFF: 5h Saved AH must beat 8h Snapshot, got " .. tostring(pOldLive) .. " / " .. tostring(srcOldLive))

	-- 19d. liveRec.absent edge cases (newer vs older vs stale)
	-- Fresh absent (2m) NEWER than 10m Snapshot -> Not listed on AH, numListed == 0
	seedSnap(nowTs - 600, 6200, 44, 6200)
	db.ahPrices[econKey][95111] = { absent = true, qty = 0, at = nowTs - 120, lastPrice = 4900 }
	ns.InvalidatePriceCache()
	local pAbsNew, srcAbsNew, stkAbsNew = ns.GetItemMarketPrice(95111)
	check(pAbsNew == nil and srcAbsNew == "Not listed (Live AH)" and stkAbsNew == 0,
		"Fresh absent scan newer than Snapshot must return Not listed (Live AH), got " .. tostring(pAbsNew) .. " / " .. tostring(srcAbsNew))
	check(ns.GetNumListed(95111) == 0, "GetNumListed: fresh absent scan newer than Snapshot must return 0")
	local fpAbs = ns.GetFallbackMarketPrice(95111)
	check(fpAbs == 6200, "GetFallbackMarketPrice must ignore absent and return Snapshot (6200), got " .. tostring(fpAbs))

	-- Fresh absent (20m) OLDER than 5m Snapshot -> Snapshot wins for price & numListed!
	seedSnap(nowTs - 300, 6200, 44, 6200)
	db.ahPrices[econKey][95111] = { absent = true, qty = 0, at = nowTs - 1200, lastPrice = 4900 }
	ns.InvalidatePriceCache()
	local pAbsOld, srcAbsOld, stkAbsOld = ns.GetItemMarketPrice(95111)
	check(pAbsOld == 6200 and srcAbsOld == "Snapshot" and stkAbsOld == 44,
		"5m Snapshot newer than 20m absent scan must win, got " .. tostring(pAbsOld) .. " / " .. tostring(srcAbsOld))
	check(ns.GetNumListed(95111) == 44,
		"GetNumListed: 5m Snapshot newer than 20m absent scan must return 44, got " .. tostring(ns.GetNumListed(95111)))

	-- Stale absent (2h) does NOT short-circuit Not listed when 4h Snapshot exists
	seedSnap(nowTs - 14400, 6200, 44, 6200)
	db.ahPrices[econKey][95111] = { absent = true, qty = 0, at = nowTs - 7200 }
	ns.InvalidatePriceCache()
	local pAbsStale, srcAbsStale = ns.GetItemMarketPrice(95111)
	check(pAbsStale == 6200 and srcAbsStale == "Snapshot",
		"Stale absent scan must not block Snapshot fallback, got " .. tostring(pAbsStale) .. " / " .. tostring(srcAbsStale))

	-- 19e. BuildSupplyPool newest-wins between ahLots (lotAt) and Snapshot Depth (snapAt)
	seedSnap(nowTs - 300, 6200, 44, 6200)
	db.ahLots[econKey] = {
		[95111] = {
			at = nowTs - 1200, -- 20m old < 5m snapshot
			lots = { { price = 5000, qty = 10 } },
		},
	}
	ns.InvalidatePriceCache()
	local poolSnapWins = ns.BuildSupplyPool({ respectStock = true })
	local lotsSnapWins = poolSnapWins:getLots(95111)
	check(lotsSnapWins ~= nil and #lotsSnapWins >= 1 and lotsSnapWins[1].source == "Snapshot Depth" and lotsSnapWins[1].price == 6200,
		"BuildSupplyPool: 5m Snapshot Depth must beat 20m ahLots, got " .. tostring(lotsSnapWins and lotsSnapWins[1] and lotsSnapWins[1].source))

	db.ahLots[econKey][95111].at = nowTs - 60 -- 1m old > 5m snapshot
	ns.InvalidatePriceCache()
	local poolLiveWins = ns.BuildSupplyPool({ respectStock = true })
	local lotsLiveWins = poolLiveWins:getLots(95111)
	check(lotsLiveWins ~= nil and #lotsLiveWins >= 1 and lotsLiveWins[1].source == "AH Lot" and lotsLiveWins[1].price == 5000,
		"BuildSupplyPool: 1m ahLots must beat 5m Snapshot Depth, got " .. tostring(lotsLiveWins and lotsLiveWins[1] and lotsLiveWins[1].source))

	nowTs = savedNow
end)()

-- 20. GetAllAuctionHousesForItem avoids unpacking non-home economies into ns.snapshotParsed
do
	local savedRaw = ns.snapshotRaw
	local savedParsed = ns.snapshotParsed
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}

	local tsBase = nowTs - 120
	local function loadHouse(ek, minB, mkt, qty, numA, delta)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", ek,
			string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=1}]], tsBase))
		local payload = "95222:" .. table.concat({
			encB32(minB), encB32(mkt), encB32(mkt), encB32(qty), encB32(numA), encB32(delta),
		}, ",")
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", ek, "13468:" .. table.concat({
			encB32(50000), encB32(50000), encB32(50000), encB32(10), encB32(2), encB32(0),
		}, ",") .. ";" .. payload)
	end

	loadHouse("Normal-Horde", 11000, 12000, 15, 3, 10)
	loadHouse("Normal-Alliance", 22000, 24000, 25, 5, 20)
	loadHouse("PvP-Horde", 33000, 35000, 7, 2, 30)
	ns.snapshotParsed = {}
	ns.InvalidatePriceCache()

	local res = ns.Pricing.GetAllAuctionHousesForItem(95222, "Normal-Horde")
	check(type(res) == "table" and res.totalHouses == 3 and type(res.rows) == "table" and #res.rows == 3,
		"GetAllAuctionHousesForItem returns all 3 seeded economies")
	check(ns.snapshotParsed["Normal-Alliance"] == nil and ns.snapshotParsed["PvP-Horde"] == nil,
		"GetAllAuctionHousesForItem leaves non-home economies unparsed in ns.snapshotParsed")

	local byEcon = {}
	for _, r in ipairs(res.rows) do byEcon[r.economy] = r end
	check(byEcon["Normal-Horde"] and byEcon["Normal-Horde"].listed == true
		and byEcon["Normal-Horde"].minBuyout == 11000 and byEcon["Normal-Horde"].marketValue == 12000
		and byEcon["Normal-Horde"].qty == 15 and byEcon["Normal-Horde"].numAuctions == 3
		and byEcon["Normal-Horde"].updatedAt == tsBase - 10,
		"GetAllAuctionHousesForItem exact values for home Normal-Horde")
	check(byEcon["Normal-Alliance"] and byEcon["Normal-Alliance"].listed == true
		and byEcon["Normal-Alliance"].minBuyout == 22000 and byEcon["Normal-Alliance"].marketValue == 24000
		and byEcon["Normal-Alliance"].qty == 25 and byEcon["Normal-Alliance"].numAuctions == 5
		and byEcon["Normal-Alliance"].updatedAt == tsBase - 20,
		"GetAllAuctionHousesForItem exact zero-unpack values for Normal-Alliance")
	check(byEcon["PvP-Horde"] and byEcon["PvP-Horde"].listed == true
		and byEcon["PvP-Horde"].minBuyout == 33000 and byEcon["PvP-Horde"].marketValue == 35000
		and byEcon["PvP-Horde"].qty == 7 and byEcon["PvP-Horde"].numAuctions == 2
		and byEcon["PvP-Horde"].updatedAt == tsBase - 30,
		"GetAllAuctionHousesForItem exact zero-unpack values for PvP-Horde")

	ns.snapshotRaw = savedRaw
	ns.snapshotParsed = savedParsed
	ns.InvalidatePriceCache()
end

-- Restore globals/state
_G.TSM_API = origTSM
_G.Auctionator = origAuctionator
_G.AucAdvanced = origAucAdvanced
_G.time = origTime
db.priceSource = origPriceSource
db.enableLegacyPriceAddons = origEnableLegacy
db.economy = origEconomy
db.ahPrices = origAhPrices
db.econSnapshots = origEconSnapshots
db.ahLots = origAhLots
db.ahSnapshots = origAhSnapshots
db.ahDaily = origAhDaily
db.ahHistory = origAhHistory
db.tsmLastUpdate = origTsmLastUpdate
ns.tsmSyncedEconomies = origTsmSynced
ns.InvalidateEconomyDetectCache()
ns.InvalidatePriceCache()

print("PASS: snapshot_pricing (" .. n .. " assertions)")
