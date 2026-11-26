-- Standalone pure Lua 5.1 unit test suite for SniperEngine.lua.
-- Runnable from MerchantMaster/tests/ or MerchantMaster/ repo root:
--   lua tests/test_sniper.lua

local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local mmDir = testsDir .. "../"

local assertions = 0
local function check(ok, msg)
	assertions = assertions + 1
	if not ok then
		error("FAIL [" .. assertions .. "]: " .. tostring(msg), 2)
	end
end

local function near(a, b, eps)
	eps = eps or 1e-4
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps
end

-------------------------------------------------------------------------------
-- Lightweight Synthetic WoW Forever Environment
-------------------------------------------------------------------------------

local mockNow = 1000
local pendingTimers = {}
local createdFrames = {}
local ahCalls = {}
local ledgerAppendCalls = 0
local mockMoney = 100000000 -- 10,000g
local mockThrottledReady = true
local mockNpcExists = false
local mockNpcFaction = nil
local mockPlayerFaction = "Alliance"
local mockPlayerMapID = 1453 -- Stormwind
local mockCartBuyerPendingExternal = nil
local mockCartBuyerActive = false

local SECRET_SENTINEL = newproxy and newproxy(false) or { __isSecret = true }
local SECRET_TABLE = { __isSecretTable = true, minPrice = 1, unitPrice = 1, quantity = 1 }

_G.issecretvalue = function(v)
	return v == SECRET_SENTINEL
end
_G.issecrettable = function(v)
	return v == SECRET_TABLE
end

_G.GetTime = function() return mockNow end
_G.time = function() return 1760000000 + mockNow end
_G.GetMoney = function() return mockMoney end
_G.UnitExists = function(unit)
	if unit == "npc" then return mockNpcExists end
	return false
end
_G.UnitFactionGroup = function(unit)
	if unit == "npc" then return mockNpcFaction end
	if unit == "player" then return mockPlayerFaction end
	return nil
end

_G.C_Map = {
	GetBestMapForUnit = function()
		return mockPlayerMapID
	end,
}

_G.C_Timer = {
	After = function(delay, fn)
		pendingTimers[#pendingTimers + 1] = { fireAt = mockNow + delay, delay = delay, fn = fn, fired = false }
	end,
}

local function flushTimers(advanceSec)
	mockNow = mockNow + (advanceSec or 0)
	local i = 1
	while i <= #pendingTimers do
		local t = pendingTimers[i]
		if not t.fired and t.fireAt <= mockNow then
			t.fired = true
			t.fn()
		end
		i = i + 1
	end
end

_G.Enum = {
	AuctionHouseSortOrder = { Price = 0 },
}

_G.CreateFrame = function(frameType)
	local f = {
		_type = frameType,
		_events = {},
		_scripts = {},
	}
	function f:RegisterEvent(ev) self._events[ev] = true end
	function f:SetScript(name, fn) self._scripts[name] = fn end
	function f:GetScript(name) return self._scripts[name] end
	function f:FireEvent(ev, ...)
		if self._scripts.OnEvent then
			self._scripts.OnEvent(self, ev, ...)
		end
	end
	createdFrames[#createdFrames + 1] = f
	return f
end

local mockItemInfo = {
	-- [id or link] = { name, link, quality, sellPrice, maxStack }
	[2447] = { "Peacebloom", "|cff9d9d9d|Hitem:2447|h[Peacebloom]|h|r", 1, 10, 20 },
	[2770] = { "Copper Ore", "|cffffffff|Hitem:2770|h[Copper Ore]|h|r", 1, 500, 20 },
	[13464] = { "Golden Sansam", "|cffffffff|Hitem:13464|h[Golden Sansam]|h|r", 1, 1070, 20 },
	[99001] = { "Poor Grey Junk", "|cff9d9d9d|Hitem:99001|h[Poor Grey Junk]|h|r", 0, 50, 20 },
	[55001] = { "Scaled BoE Blade", "|cff1eff00|Hitem:55001|h[Scaled BoE Blade]|h|r", 2, 50000, 1 },
	["|cff1eff00|Hitem:55001::::::100:0:60|h[Scaled BoE Blade of the Bear]|h|r"] = {
		"Scaled BoE Blade of the Bear",
		"|cff1eff00|Hitem:55001::::::100:0:60|h[Scaled BoE Blade of the Bear]|h|r",
		2,
		60000, -- 6g vendor sell
		1,
	},
	["|cff1eff00|Hitem:55001::::::200:0:20|h[Scaled BoE Blade of the Owl]|h|r"] = {
		"Scaled BoE Blade of the Owl",
		"|cff1eff00|Hitem:55001::::::200:0:20|h[Scaled BoE Blade of the Owl]|h|r",
		2,
		20000, -- 2g vendor sell (lower than base 5g!)
		1,
	},
	[55002] = { "NonCatalog BoE Axe", "|cff0070dd|Hitem:55002|h[NonCatalog BoE Axe]|h|r", 3, 85000, 1 },
	[55003] = { "Uncached Relic", "|cff0070dd|Hitem:55003|h[Uncached Relic]|h|r", 3, 40000, 1 },
	[55004] = { "Fast-Selling Runecloth Bag", "|cffffffff|Hitem:55004|h[Fast-Selling Runecloth Bag]|h|r", 1, 2000, 1 },
	[55005] = { "Underpriced Herb Commodity", "|cffffffff|Hitem:55005|h[Underpriced Herb Commodity]|h|r", 1, 5000, 20 },
}
local hideItemInfo = { [55003] = true }
local requestedLoads = {}
local mockItemInstant = {
	-- [id] = { equipLoc, classID }
	[55001] = { "INVTYPE_WEAPON", 2 },
	[55002] = { "INVTYPE_2HWEAPON", 2 },
	[55003] = { "INVTYPE_TRINKET", 4 },
	[55004] = { "INVTYPE_BAG", 1 },
	[55010] = { "INVTYPE_WEAPON", 2 },
	[55011] = { "INVTYPE_HEAD", 4 },
}
local apiCounts = { getItemInfo = 0, getItemInfoInstant = 0, getItemKeyInfo = 0, demand = 0, refPrice = 0 }

_G.C_Item = {
	GetItemInfo = function(query)
		apiCounts.getItemInfo = apiCounts.getItemInfo + 1
		if hideItemInfo[query] then return nil end
		local rec = mockItemInfo[query]
		if not rec then return nil end
		return rec[1], rec[2], rec[3], 60, 1, "Trade Goods", "Herb", rec[5] or 20, "", 134187, rec[4]
	end,
	GetItemInfoInstant = function(query)
		apiCounts.getItemInfoInstant = apiCounts.getItemInfoInstant + 1
		local id = tonumber(query)
		local inst = id and mockItemInstant[id]
		if inst then
			return id, "Equipment", "Item", inst[1], 134187, inst[2], 0
		end
		return nil
	end,
	RequestLoadItemDataByID = function(id)
		requestedLoads[id] = (requestedLoads[id] or 0) + 1
	end,
}

local mockItemSearchResults = {}
local mockCommoditySearchResults = {}

_G.C_AuctionHouse = {
	IsThrottledMessageSystemReady = function()
		return mockThrottledReady
	end,
	MakeItemKey = function(itemID, itemLevel, itemSuffix, petSpecies)
		return {
			itemID = itemID,
			itemLevel = itemLevel or 0,
			itemSuffix = itemSuffix or 0,
			battlePetSpeciesID = petSpecies or 0,
		}
	end,
	GetItemKeyInfo = function(itemKey)
		apiCounts.getItemKeyInfo = apiCounts.getItemKeyInfo + 1
		local id = itemKey and itemKey.itemID
		if id == 2447 or id == 2770 or id == 13464 or id == 55005 then
			return { isCommodity = true }
		elseif id == 55001 or id == 55002 or id == 55003 then
			return { isCommodity = false }
		end
		return nil -- 55004 returns nil to test GetItemInfoInstant / maxStack == 1 fallback!
	end,
	SendSearchQuery = function(itemKey, sorts, separateOwnerItems)
		ahCalls[#ahCalls + 1] = {
			fn = "SendSearchQuery",
			argc = 3,
			itemKey = itemKey,
			sorts = sorts,
			separateOwnerItems = separateOwnerItems,
		}
		return true
	end,
	GetNumItemSearchResults = function(itemKey)
		local list = itemKey and mockItemSearchResults[itemKey.itemID]
		return list and #list or 0
	end,
	GetItemSearchResultInfo = function(itemKey, idx)
		local list = itemKey and mockItemSearchResults[itemKey.itemID]
		return list and list[idx] or nil
	end,
	GetNumCommoditySearchResults = function(itemID)
		local list = mockCommoditySearchResults[itemID]
		return list and #list or 0
	end,
	GetCommoditySearchResultInfo = function(itemID, idx)
		local list = mockCommoditySearchResults[itemID]
		return list and list[idx] or nil
	end,
	HasFullCommoditySearchResults = function() return true end,
	StartCommoditiesPurchase = function(...)
		local argc = select("#", ...)
		local itemID, qty, extra = ...
		ahCalls[#ahCalls + 1] = {
			fn = "StartCommoditiesPurchase",
			argc = argc,
			itemID = itemID,
			qty = qty,
			extra = extra,
		}
		return true
	end,
	ConfirmCommoditiesPurchase = function(...)
		local argc = select("#", ...)
		local itemID, qty, extra = ...
		ahCalls[#ahCalls + 1] = {
			fn = "ConfirmCommoditiesPurchase",
			argc = argc,
			itemID = itemID,
			qty = qty,
			extra = extra,
		}
		return true
	end,
	CancelCommoditiesPurchase = function()
		ahCalls[#ahCalls + 1] = { fn = "CancelCommoditiesPurchase", argc = 0 }
		return true
	end,
	PlaceBid = function(...)
		local argc = select("#", ...)
		local auctionID, amount = ...
		ahCalls[#ahCalls + 1] = {
			fn = "PlaceBid",
			argc = argc,
			auctionID = auctionID,
			amount = amount,
		}
		return true
	end,
	GetQuoteDurationRemaining = function()
		return 30
	end,
}

_G.MerchantMasterDB = {}

-- Mock MerchantMaster namespace with exact Pricing / Analytics / CartBuyer contracts
local snapshotRawItems = {
	[2447]  = { minBuyout = 500,   marketValue = 800,   historical = 750,   qty = 100 },
	[2770]  = { minBuyout = 8000,  marketValue = 15000, historical = 14000, qty = 200 },
	[13464] = { minBuyout = 10000, marketValue = 25000, historical = 24000, qty = 150 },
	[99001] = { minBuyout = 10,    marketValue = 5000,  historical = 5000,  qty = 50  }, -- Poor grey item
	[55002] = { minBuyout = 40000, marketValue = 90000, historical = 88000, qty = 2   }, -- Vendor deal (4g vs 8.5g vendor)
	[55004] = { minBuyout = 15000, marketValue = 30000, historical = 28000, qty = 5   }, -- Fast-selling non-commodity bag (maxStack=1)
}

local mockDemand = {
	[2447]  = { dailySold = 5,   effectiveDailySold = 5,   demandSource = "Blizz", confidence = 2 },
	[2770]  = { dailySold = 120, effectiveDailySold = 120, demandSource = "Blizz", confidence = 3 },
	[13464] = { dailySold = 40,  effectiveDailySold = 40,  demandSource = "Blizz", confidence = 3 },
	[99001] = { dailySold = 200, effectiveDailySold = 200, demandSource = "Blizz", confidence = 3 },
	[55002] = { dailySold = 0.2, effectiveDailySold = 0.2, demandSource = "TSM",   confidence = 1 },
	[55004] = { dailySold = 50,  effectiveDailySold = 50,  demandSource = "Blizz", confidence = 3 },
}

local mockRegSale = {
	[2447]  = { regionSale = 750,   soldPerDay = 5,   saleRate = 0.25 },
	[2770]  = { regionSale = 14000, soldPerDay = 120, saleRate = 0.50 },
	[13464] = { regionSale = 24000, soldPerDay = 40,  saleRate = 0.45 },
	[99001] = { regionSale = 4000,  soldPerDay = 200, saleRate = 0.10 },
	[55004] = { regionSale = 28000, soldPerDay = 50,  saleRate = 0.40 },
}

local mockDepth = {
	[13464] = {
		{ price = 10000, qty = 10 },
		{ price = 11000, qty = 5 },
		{ price = 22000, qty = 80 },
	},
}

local ns = {
	snapshotParsed = {},
	Pricing = {},
	app = {
		cartBuyer = {
			GetState = function()
				return { pendingExternal = mockCartBuyerPendingExternal, active = mockCartBuyerActive }
			end,
		},
	},
	Analytics = {
		Store = {
			Append = function()
				ledgerAppendCalls = ledgerAppendCalls + 1
			end,
		},
	},
}

function ns.DetectActiveEconomy()
	return "Forever-EU"
end

function ns.GetDB()
	return _G.MerchantMasterDB
end

-- Exact namespace: ns.QueryLocalSnapshot hydrates ns.snapshotParsed[resolvedKey]
function ns.QueryLocalSnapshot(itemID, econ)
	local key = econ or "Forever-EU"
	if not ns.snapshotParsed[key] then
		ns.snapshotParsed[key] = {
			meta = { updatedAt = 1760000500, source = "snapshot", itemCount = 5 },
			items = snapshotRawItems,
		}
	end
	local rec = ns.snapshotParsed[key].items[itemID]
	if not rec then
		local rs = mockRegSale[itemID]
		if rs and rs.regionSale and rs.regionSale > 0 then
			rec = { marketValue = rs.regionSale, historical = rs.regionSale, minBuyout = rs.regionSale, qty = 5 }
		else
			return nil, nil
		end
	end
	return rec.minBuyout or rec.marketValue, rec
end

function ns.Pricing.GetItemSnapshotDepth(itemID)
	return mockDepth[itemID]
end

function ns.Pricing.GetItemSnapshotVelocity(itemID)
	local d = mockDemand[itemID]
	if d then
		return { estDailySold = d.dailySold, obsHours = 12, confidence = d.confidence, raw7d = 50, source = "snapshot" }
	end
	local rs = mockRegSale[itemID]
	if rs and rs.soldPerDay then
		return { estDailySold = rs.soldPerDay, obsHours = 12, confidence = 2, raw7d = 20, source = "snapshot" }
	end
	return nil
end

function ns.Pricing.IsSnapshotFresh()
	return true, 300, { updatedAt = 1760000500 }
end

function ns.GetMultiSourceDemand(itemID)
	apiCounts.demand = apiCounts.demand + 1
	return mockDemand[itemID]
end

function ns.GetConservativeSaleUnitPrice(itemID, rawAHUnit)
	local rs = mockRegSale[itemID]
	if rs and rs.regionSale then
		local cap = math.floor(rs.regionSale * 1.25 + 0.5)
		if rawAHUnit > cap then
			return cap, true, "Region Sale x1.25"
		end
	end
	return rawAHUnit, false, nil
end

function ns.GetVendorSellPrice(itemID)
	if hideItemInfo[itemID] then return nil end
	local rec = mockItemInfo[itemID]
	return rec and rec[4] or nil
end

-- Load SniperEngine.lua directly
local chunk, loadErr = loadfile(mmDir .. "SniperEngine.lua")
check(chunk ~= nil, "SniperEngine.lua compiled cleanly: " .. tostring(loadErr))
local SE = chunk("MerchantMaster", ns)
check(SE == ns.SniperEngine, "ns.SniperEngine exported")
check(ns.GetForeverAuctionDeposit == SE.GetForeverAuctionDeposit, "ns.GetForeverAuctionDeposit exported on ns")
check(ns.GetDynamicAuctionCut == SE.GetDynamicAuctionCut, "ns.GetDynamicAuctionCut exported on ns")

-------------------------------------------------------------------------------
-- 1. Forever Deposit Math & Dynamic 5% / 15% AH Cut
-------------------------------------------------------------------------------

-- Verified WoW Forever ledger examples from GoldCapped/Data/AuctionDeposit.lua:
check(SE.GetForeverAuctionDeposit(1070, 1, 8, false) == 214, "Faction 8h deposit: Northern Shortsword 10s70c -> 2s14c")
check(SE.GetForeverAuctionDeposit(2262, 1, 2, false) == 113, "Faction 2h deposit: Battle Slayer 22s62c -> 1s13c")
check(SE.GetForeverAuctionDeposit(10000, 1, 24, false) == 6000, "Faction 24h deposit: 60% of 1g = 60s")
check(SE.GetForeverAuctionDeposit(50, 1, 2, false) == 100, "Forever 1s (100c) deposit floor enforced")
check(SE.GetForeverAuctionDeposit(0, 10, 8, false) == 100, "Zero vendor sell still enforces 1s (100c) floor")

-- Blackwater (Neutral) 25% / 100% / 300%
check(SE.GetForeverAuctionDeposit(1000, 1, 2, true) == 250, "Blackwater 2h deposit: 25% of 10s = 2s50c")
check(SE.GetForeverAuctionDeposit(1000, 1, 8, true) == 1000, "Blackwater 8h deposit: 100% of 10s = 10s")
check(SE.GetForeverAuctionDeposit(1000, 1, 24, true) == 3000, "Blackwater 24h deposit: 300% of 10s = 30s")
check(SE.GetForeverAuctionDeposit(500, 20, 8, false) == 2000, "Multi-unit quantity deposit scales linearly (20 * 500 * 20% = 2000c)")

-- Dynamic AH cut detection + caching per AH visit
mockNpcExists = true
mockNpcFaction = "Alliance"
mockPlayerFaction = "Alliance"
mockPlayerMapID = 1453
SE.OnEvent("AUCTION_HOUSE_SHOW")
check(SE.IsNeutralAH() == false, "Faction auctioneer detected as non-neutral")
check(near(SE.GetDynamicAuctionCut(), 0.05), "Faction AH cut is 5%")

-- Switching to Neutral NPC without AUCTION_HOUSE_SHOW keeps cached value during visit
mockNpcFaction = "Neutral"
check(SE.IsNeutralAH() == false, "Neutral state cached during single AH visit")

-- Closing & reopening AH resets cache and detects Neutral auctioneer
SE.OnEvent("AUCTION_HOUSE_CLOSED")
SE.OnEvent("AUCTION_HOUSE_SHOW")
check(SE.IsNeutralAH() == true, "Neutral NPC auctioneer detected on new AH visit")
check(near(SE.GetDynamicAuctionCut(), 0.15), "Neutral AH cut is 15%")

-- Opposing faction NPC also treated as Neutral/cross-faction
mockNpcFaction = "Horde"
SE.OnEvent("AUCTION_HOUSE_SHOW")
check(SE.IsNeutralAH() == true and near(SE.GetDynamicAuctionCut(), 0.15), "Opposing faction NPC triggers 15% cut")

-- MapID fallback when NPC unit unavailable (Booty Bay Classic = 1434, Gadgetzan Modern = 71)
mockNpcExists = false
mockNpcFaction = nil
mockPlayerMapID = 1434
SE.OnEvent("AUCTION_HOUSE_SHOW")
check(SE.IsNeutralAH() == true and near(SE.GetDynamicAuctionCut(), 0.15), "Booty Bay mapID 1434 fallback triggers 15% cut")
mockPlayerMapID = 71
SE.OnEvent("AUCTION_HOUSE_SHOW")
check(SE.IsNeutralAH() == true, "Tanaris Modern mapID 71 fallback triggers neutral")
mockPlayerMapID = 1453
SE.OnEvent("AUCTION_HOUSE_SHOW")
check(SE.IsNeutralAH() == false and near(SE.GetDynamicAuctionCut(), 0.05), "Stormwind mapID 1453 returns 5% faction cut")

-------------------------------------------------------------------------------
-- 2. Gap Sniper Shortlist & Evaluator Math
-------------------------------------------------------------------------------

-- Defaults & DB persistence (WoW Forever tuned)
local defs = SE.GetDefaults()
check(defs.gapScope == "all", "Default gapScope is 'all' (All AH items)")
check(defs.minGapPct == 15 and defs.minRoiPct == 15 and defs.minProfitCopper == 10000 and defs.maxShortlistItems == 120,
	"WoW Forever defaults match spec (15% gap, 15% ROI, 1g min profit, 120 shortlist cap)")
check(defs.minQty == 2 and defs.maxBuyShareDailyPct == 50 and defs.buyCeilingPct == 95, "Liquidity & anti-bait defaults match spec")
local settings = SE.GetSettings()
check(_G.MerchantMasterDB.sniper == settings, "Settings persisted in MerchantMasterDB.sniper")

-- BuildGapShortlist hydrates snapshotParsed via QueryLocalSnapshot(2447, econ),
-- filters Poor quality (99001) & low dailySales (55002), sorts Fast Sellers First.
-- Default scope = "all" includes BOTH commodities and non-commodity 55004 (dailySold=50).
-- Pass minProfitCopper=100 so low-value 2447 (max profit 520c) stays in sort test; default 1g prunes 2447!
local shortlistAll = SE.BuildGapShortlist({ econ = "Forever-EU", minDailySales = 1, minProfitCopper = 100, maxItems = 10 })
check(ns.snapshotParsed["Forever-EU"] ~= nil, "BuildGapShortlist hydrated ns.snapshotParsed")
check(#shortlistAll == 4, "Default scope='all' kept 3 commodities + 1 fast non-commodity (55004); got " .. #shortlistAll)
check(shortlistAll[1].itemID == 2770 and shortlistAll[2].itemID == 55004
	and shortlistAll[3].itemID == 13464 and shortlistAll[4].itemID == 2447,
	"Shortlist (scope='all') sorted Fast Sellers First (120 -> 50 -> 40 -> 5 dailySold)")

local shortlistDefaultProfit = SE.BuildGapShortlist({ econ = "Forever-EU", minDailySales = 1, maxItems = 10 })
check(#shortlistDefaultProfit == 3 and shortlistDefaultProfit[1].itemID == 2770
	and shortlistDefaultProfit[2].itemID == 55004 and shortlistDefaultProfit[3].itemID == 13464,
	"B2: Default 1g minProfitCopper pruned impossible-profit Peacebloom 2447 (max 5s20c < 1g)")

local shortlist = SE.BuildGapShortlist({ econ = "Forever-EU", gapScope = "commodities", minDailySales = 1, minProfitCopper = 100, maxItems = 10 })
check(#shortlist == 3, "Scope='commodities' filtered out grey Poor (99001), slow BoE (55002), and non-commodity bag (55004); got " .. #shortlist)
check(shortlist[1].itemID == 2770 and shortlist[2].itemID == 13464 and shortlist[3].itemID == 2447,
	"Shortlist (scope='commodities') sorted Fast Sellers First (120 -> 40 -> 5 dailySold)")

local shortlistItems = SE.BuildGapShortlist({ econ = "Forever-EU", gapScope = "items", minDailySales = 1, maxItems = 10 })
check(#shortlistItems == 1 and shortlistItems[1].itemID == 55004 and shortlistItems[1].isCommodity == false,
	"Scope='items' kept ONLY non-commodity 55004")

local cappedShortlist = SE.BuildGapShortlist({ econ = "Forever-EU", maxItems = 2 })
check(#cappedShortlist == 2 and cappedShortlist[1].itemID == 2770, "maxItems cap enforced")

-- EvaluateCommodityGap: multi-tier walk + ladder + exact math
local tiers = {
	{ unitPrice = 10000, quantity = 10 }, -- 1g x 10 = 10g
	{ unitPrice = 11000, quantity = 10 }, -- 1.1g x 10 = 11g (cumulative: 20 units, 21g, avg 10500c)
	{ unitPrice = 20000, quantity = 50 }, -- 2g wall
	{ unitPrice = 25000, quantity = 40 }, -- above wall
}
local deal = SE.EvaluateCommodityGap(13464, tiers, {
	refPrice = 24000,
	dailySold = 40,          -- 50% cap = 20 units -> exactly covers tiers 1+2!
	vendorSell = 1070,
	isNeutral = false,
	minProfitCopper = 100000,
})
check(deal ~= nil, "Valid multi-tier gap deal found")
check(deal.buyQty == 20, "Bought tiers 1+2 (20 units)")
check(deal.totalCost == 210000, "Total cost = 10*10000 + 10*11000 = 210000c")
check(near(deal.avgBuyPrice, 10500), "Average buy price = 10500c")
check(deal.relistPrice == 19999, "Relist price = nextTier(20000) - 1 = 19999c (below refPrice 24000c)")
check(deal.grossRevenue == 19999 * 20, "Gross revenue = 399980c")
check(deal.ahCut == math.floor(399980 * 0.05 + 0.5), "5% AH cut = 19999c")
check(deal.netProfit == (399980 - 19999 - 210000), "Exact netProfit = 169981c")
check(deal.deposit == SE.GetForeverAuctionDeposit(1070, 20, 8, false), "Exact 8h Forever deposit = 4280c")
check(near(deal.estHoursToSell, (20 / 40) * 24), "Est. Hours-to-Sell = (20/40)*24 = 12.0h")
check(near(deal.roiPct, (deal.netProfit / deal.totalCost) * 100), "Exact ROI %")
check(near(deal.gapPct, ((20000 - 10500) / 10500) * 100), "Exact Gap %")
check(#deal.ladder == 4, "Ladder contains bought tiers + wall + context")
check(deal.ladder[1].role == "buy" and deal.ladder[2].role == "buy"
	and deal.ladder[3].role == "wall" and deal.ladder[4].role == "above",
	"Ladder tier roles tagged buy / buy / wall / above")

-- Resale cap at math.min(nextTier - 1, refPrice): fake 500g cliff capped at 12g refPrice!
local fakeCliffDeal = SE.EvaluateCommodityGap(13464, {
	{ unitPrice = 10000, quantity = 10 },
	{ unitPrice = 5000000, quantity = 5 }, -- fake 500g wall!
}, {
	refPrice = 12000,  -- real market is only 1.2g (20% gap, but after 5% cut 11400 vs 10000 -> 14% ROI < 25%)
	dailySold = 40,
	isNeutral = false,
	minRoiPct = 25,
	minProfitCopper = 1000,
})
check(fakeCliffDeal == nil, "Fake 500g cliff capped at 1.2g refPrice fails 25% ROI gate")

local cappedValidDeal = SE.EvaluateCommodityGap(13464, {
	{ unitPrice = 10000, quantity = 10 },
	{ unitPrice = 5000000, quantity = 5 },
}, {
	refPrice = 16000, -- real refPrice 1.6g caps relistPrice at 16000 (not 4999999!)
	dailySold = 40,
	isNeutral = false,
	minRoiPct = 25,
	minProfitCopper = 10000,
})
check(cappedValidDeal ~= nil and cappedValidDeal.relistPrice == 16000,
	"Resale strictly capped at refPrice=16000 when nextTier-1 exceeds refPrice")

-- Flipping Pal liquidity cap (maxBuyShareDailyPct = 50%):
-- Tier 1 has 15 units, dailySold = 20 -> cap = 10 units -> cannot clear tier 1 -> returns nil!
local illiquidDeal = SE.EvaluateCommodityGap(13464, {
	{ unitPrice = 10000, quantity = 15 },
	{ unitPrice = 20000, quantity = 50 },
}, {
	refPrice = 25000,
	dailySold = 20,
	maxBuyShareDailyPct = 50,
	minProfitCopper = 10000,
})
check(illiquidDeal == nil, "Liquidity cap (50% of 20 = 10 < 15 tier qty) prevents partial false gap")

-- Anti-bait minQty = 2: 1-unit cheap bait alone rejected
local baitDeal = SE.EvaluateCommodityGap(13464, {
	{ unitPrice = 10000, quantity = 1 },
	{ unitPrice = 250000, quantity = 50 },
}, {
	refPrice = 260000,
	dailySold = 40,
	minQty = 2,
	minProfitCopper = 1000,
})
check(baitDeal == nil, "Anti-bait minQty=2 rejects 1-unit bait listing")

-- Neutral AH 15% cut disqualifies thin margin that passes at 5% faction cut
-- Buy 10 @ 10000 (100000c), nextTier 13500 (relist 13499, gross 134990):
--   Faction 5%:  netRev = 128240 -> netProfit = 28240 (28.24% ROI >= 25% PASS)
--   Neutral 15%: netRev = 114741 -> netProfit = 14741 (14.74% ROI <  25% FAIL)
local thinTiers = {
	{ unitPrice = 10000, quantity = 10 },
	{ unitPrice = 13500, quantity = 50 },
}
local factionPass = SE.EvaluateCommodityGap(13464, thinTiers, {
	refPrice = 15000, dailySold = 40, isNeutral = false, minRoiPct = 25, minProfitCopper = 10000,
})
local neutralFail = SE.EvaluateCommodityGap(13464, thinTiers, {
	refPrice = 15000, dailySold = 40, isNeutral = true, minRoiPct = 25, minProfitCopper = 10000,
})
check(factionPass ~= nil, "Thin margin qualifies on 5% faction AH")
check(neutralFail == nil, "Same thin margin disqualified on 15% neutral AH")

-- Instant offline Snapshot Gap Preview (uses ns.Pricing.GetItemSnapshotDepth)
local snapGaps = SE.ScanSnapshotForGapDeals("Forever-EU", { minProfitCopper = 50000 })
check(#snapGaps >= 1 and snapGaps[1].itemID == 13464 and snapGaps[1].source == "Snapshot",
	"ScanSnapshotForGapDeals finds offline gap deal from snapshot depth")

-------------------------------------------------------------------------------
-- 3. Vendor Sniper (Browse Batch + Full Snapshot + Live itemLink Verification)
-------------------------------------------------------------------------------

SE.ClearVendorDeals()
local browseFlagged = SE.IngestBrowseBatch({
	{ itemID = 55001, minPrice = 30000, totalQuantity = 1, isCommodity = false }, -- 3g AH vs 5g base vendor -> +2g profit
	{ itemID = 2770,  minPrice = 8000,  totalQuantity = 50, isCommodity = true }, -- 80s AH vs 5s vendor -> NOT vendor deal
	{ itemID = 55003, minPrice = 10000, totalQuantity = 1, isCommodity = false }, -- uncached -> queued for GET_ITEM_INFO_RECEIVED
}, "Forever-EU")
check(browseFlagged == 1, "IngestBrowseBatch flagged 1 profitable vendor deal")
check(SE.browseCache[2770] ~= nil and SE.browseCache[2770].minPrice == 8000, "IngestBrowseBatch updated browseCache for shortlist")
check(requestedLoads[55003] == 1 and SE.unresolvedVendor[55003] ~= nil, "Uncached vendor candidate requested item load")

-- GET_ITEM_INFO_RECEIVED resolves uncached vendor candidate 55003
hideItemInfo[55003] = nil
SE.OnEvent("GET_ITEM_INFO_RECEIVED", 55003, true)
check(SE.unresolvedVendor[55003] == nil and SE.vendorDealsByKey["vendor:55003"] ~= nil,
	"GET_ITEM_INFO_RECEIVED resolved uncached vendor deal 55003 (+3g profit)")

-- ScanSnapshotForVendorDeals catches non-catalog BoE 55002 (4g buyout vs 8.5g vendor = +4.5g profit)
local vDeals = SE.ScanSnapshotForVendorDeals("Forever-EU", { minProfitCopper = 1000, append = true })
check(SE.vendorDealsByKey["vendor:55002"] ~= nil, "ScanSnapshotForVendorDeals caught non-catalog BoE 55002")
check(vDeals[1].itemID == 55002 and vDeals[1].profitPerUnit == 45000,
	"Vendor deals sorted descending by profitPerUnit (55002 +4.5g first)")

-- Live Check: scaled/random-suffix itemLink vendor re-verification!
-- Case A: live listing has "of the Owl" link whose vendor sell is ONLY 2g (20000c) < 3g buyout (30000c)
-- even though base itemID 55001 vendors for 5g -> MUST REJECT!
local boeDeal = SE.vendorDealsByKey["vendor:55001"]
check(boeDeal ~= nil, "BoE deal 55001 present for live verification")
mockItemSearchResults[55001] = {
	{
		auctionID = 7001,
		buyoutAmount = 30000,
		quantity = 1,
		itemLink = "|cff1eff00|Hitem:55001::::::200:0:20|h[Scaled BoE Blade of the Owl]|h|r",
	},
}
local okCheck = SE.HandleVendorAction(boeDeal)
check(okCheck == true and boeDeal.status == "checking", "Click 1 (Check) sent live item search")
SE.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 55001 })
check(boeDeal.status == "unavailable",
	"Live itemLink vendor check rejected lower-vendor suffix BoE (2g link vendor < 3g buyout)")

-- Case B: live listing has "of the Bear" link whose vendor sell is 6g (60000c) > 3g buyout (30000c) -> ACCEPT!
boeDeal.status = "unverified"
mockItemSearchResults[55001] = {
	{
		auctionID = 7002,
		buyoutAmount = 30000,
		quantity = 1,
		itemLink = "|cff1eff00|Hitem:55001::::::100:0:60|h[Scaled BoE Blade of the Bear]|h|r",
	},
}
check(SE.HandleVendorAction(boeDeal) == true, "Re-check sent for higher-vendor suffix BoE")
SE.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 55001 })
check(boeDeal.status == "ready_to_buy" and boeDeal.auctionID == 7002
	and boeDeal.vendorSell == 60000 and boeDeal.profitPerUnit == 30000,
	"Live itemLink verified 6g vendor sell and marked ready_to_buy with auctionID=7002")

-------------------------------------------------------------------------------
-- 4. WoW Forever Two-Click Purchase State Machine & Collision Guards
-------------------------------------------------------------------------------

ahCalls = {}

-- 4a. Non-commodity item Click 2 -> PlaceBid(auctionID, buyoutAmount)
local okBid = SE.HandleVendorAction(boeDeal)
check(okBid == true and boeDeal.status == "buying", "Click 2 (Buy) submitted PlaceBid")
check(#ahCalls == 1 and ahCalls[1].fn == "PlaceBid"
	and ahCalls[1].auctionID == 7002 and ahCalls[1].amount == 30000,
	"PlaceBid called with exact auctionID=7002 and buyoutAmount=30000")
SE.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 7002)
check(boeDeal.status == "bought" and SE.GetPurchaseState() == nil, "Item purchase completed cleanly")
check(SE.GetSessionStats().buys == 1 and SE.GetSessionStats().spent == 30000, "Session stats tracked item buy")

-- 4b. CartBuyer collision guard (B6): refuses purchase while cartBuyer.pendingExternal is non-nil
ahCalls = {}
mockCartBuyerPendingExternal = { itemID = 13464, qty = 5 }
local blocked, blockReason = SE.HandleRowAction(deal)
check(blocked == false and blockReason == "cart_buyer_busy", "B6: CartBuyer pendingExternal blocks sniper buy")
check(#ahCalls == 0, "Zero AH calls made while cartBuyer.pendingExternal is set")
mockCartBuyerPendingExternal = nil

-- 4c. Commodity 2-click happy path:
-- Click 1 -> StartCommoditiesPurchase(itemID, qty) with EXACTLY 2 args!
-- COMMODITY_PRICE_UPDATED within 5% tolerance -> awaiting_confirm
-- Click 2 -> ConfirmCommoditiesPurchase(itemID, qty) -> COMMODITY_PURCHASE_SUCCEEDED
ahCalls = {}
deal.status = "ready"
local okStart = SE.HandleRowAction(deal)
check(okStart == true and SE.GetPurchaseState().state == "quoting", "Click 1 entered quoting state")
check(#ahCalls == 1 and ahCalls[1].fn == "StartCommoditiesPurchase"
	and ahCalls[1].argc == 2 and ahCalls[1].itemID == 13464 and ahCalls[1].qty == 20,
	"StartCommoditiesPurchase called with EXACTLY 2 arguments (itemID, qty)")

-- Quote arrives within 5% tolerance (expected 210000c, maxWithTol 220500c, quoted 215000c)
SE.OnEvent("COMMODITY_PRICE_UPDATED", 10750, 215000)
local ps = SE.GetPurchaseState()
check(ps ~= nil and ps.state == "awaiting_confirm" and ps.verifiedUnitPrice == 10750 and ps.verifiedTotalPrice == 215000,
	"In-tolerance COMMODITY_PRICE_UPDATED transitions to awaiting_confirm")
check(deal.status == "awaiting_confirm", "Deal status updated to awaiting_confirm")

-- Click 2 -> ConfirmCommoditiesPurchase
local okConfirm = SE.HandleRowAction(deal)
check(okConfirm == true and SE.GetPurchaseState().state == "confirming", "Click 2 entered confirming state")
check(#ahCalls == 2 and ahCalls[2].fn == "ConfirmCommoditiesPurchase"
	and ahCalls[2].itemID == 13464 and ahCalls[2].qty == 20,
	"ConfirmCommoditiesPurchase called with exact itemID and qty")

SE.OnEvent("COMMODITY_PURCHASE_SUCCEEDED")
check(deal.status == "bought" and SE.GetPurchaseState() == nil, "Commodity purchase completed cleanly")
check(SE.GetSessionStats().buys == 2 and SE.GetSessionStats().spent == 30000 + 215000, "Session stats tracked commodity buy")

-- 4d. Over-tolerance quote in quoting state cancels purchase cleanly
ahCalls = {}
deal.status = "ready"
check(SE.HandleRowAction(deal) == true, "Started 2nd commodity quote")
SE.OnEvent("COMMODITY_PRICE_UPDATED", 12000, 240000) -- 240000 > 220500 maxWithTol!
check(SE.GetPurchaseState() == nil, "Over-tolerance quote cleared purchase state")
check(#ahCalls == 2 and ahCalls[2].fn == "CancelCommoditiesPurchase",
	"Over-tolerance quote called CancelCommoditiesPurchase")

-- 4e. Late price jump while already in awaiting_confirm cancels purchase cleanly!
ahCalls = {}
deal.status = "ready"
check(SE.HandleRowAction(deal) == true, "Started 3rd commodity quote")
SE.OnEvent("COMMODITY_PRICE_UPDATED", 10500, 210000)
check(SE.GetPurchaseState().state == "awaiting_confirm", "Quote initially accepted")
SE.OnEvent("COMMODITY_PRICE_UPDATED", 13000, 260000) -- late jump!
check(SE.GetPurchaseState() == nil, "Late price jump in awaiting_confirm cancelled purchase")
check(#ahCalls == 2 and ahCalls[2].fn == "CancelCommoditiesPurchase",
	"Late price jump called CancelCommoditiesPurchase")

-- 4f. QUOTE_TIMEOUT (30s) cancels stuck quote
ahCalls = {}
deal.status = "ready"
check(SE.HandleRowAction(deal) == true, "Started 4th commodity quote for timeout test")
flushTimers(29)
check(SE.GetPurchaseState() ~= nil and SE.GetPurchaseState().state == "quoting", "Still quoting at 29s")
flushTimers(2) -- 31s total
check(SE.GetPurchaseState() == nil, "Quote timed out after 30s")
check(#ahCalls == 2 and ahCalls[2].fn == "CancelCommoditiesPurchase", "Timeout called CancelCommoditiesPurchase")

-------------------------------------------------------------------------------
-- 5. Secret-Value Safety, Zero OnUpdate & Zero Double-Ledger Calls
-------------------------------------------------------------------------------

-- Secret values in browse batch, commodity gap tiers, and price update event
local secretOk = pcall(function()
	SE.IngestBrowseBatch({
		SECRET_TABLE,
		{ itemID = SECRET_SENTINEL, minPrice = 100, totalQuantity = 5 },
		{ itemID = 2770, minPrice = SECRET_SENTINEL, totalQuantity = 5 },
	}, "Forever-EU")
	local secretGap = SE.EvaluateCommodityGap(13464, {
		SECRET_TABLE,
		{ unitPrice = SECRET_SENTINEL, quantity = 10 },
		{ unitPrice = 10000, quantity = SECRET_SENTINEL },
	}, { refPrice = 20000, dailySold = 40 })
	check(secretGap == nil, "Secret tiers safely yield nil without throwing")
end)
check(secretOk == true, "Secret values in browse/gap paths handled without Lua error")

-- Secret quote price safely cancels open purchase
ahCalls = {}
deal.status = "ready"
check(SE.HandleRowAction(deal) == true, "Started quote for secret price update test")
SE.OnEvent("COMMODITY_PRICE_UPDATED", SECRET_SENTINEL, SECRET_SENTINEL)
check(SE.GetPurchaseState() == nil and ahCalls[2] and ahCalls[2].fn == "CancelCommoditiesPurchase",
	"Secret COMMODITY_PRICE_UPDATED safely cancels commodity purchase")

-- Dedicated event frame has OnEvent and ZERO OnUpdate scripts
check(SE.eventFrame ~= nil and #createdFrames == 1, "Dedicated event frame created")
check(type(SE.eventFrame:GetScript("OnEvent")) == "function", "Dedicated event frame has OnEvent handler")
check(SE.eventFrame:GetScript("OnUpdate") == nil, "Zero OnUpdate scripts attached to event frame")

-- Double-ledger guard: Analytics.Store.Append must NEVER be called by SniperEngine
check(ledgerAppendCalls == 0, "Analytics.Store.Append called 0 times (no double-ledger)")

-------------------------------------------------------------------------------
-- 6. Review Findings Regressions (#1 MarketScan/Non-Commodity, #2 Watchdogs, #3 Include Commodities)
-------------------------------------------------------------------------------

-- 6a. Finding #1a: BuildGapShortlist skipped non-commodity bag 55004 (maxStack == 1)
local found55004 = false
for i = 1, #shortlist do
	if shortlist[i].itemID == 55004 then found55004 = true end
end
check(not found55004, "BuildGapShortlist skips non-commodity items (55004 with maxStack=1)")

-- 6b. Finding #1b: Direct fallback live Gap Scan advances immediately on ITEM_SEARCH_RESULTS_UPDATED
ahCalls = {}
SE.OnEvent("AUCTION_HOUSE_SHOW")
local okDirectScan = SE.StartGapScan({ econ = "Forever-EU", gapScope = "commodities", minDailySales = 1, maxItems = 2 })
check(okDirectScan == true and SE.scan.active == true, "Direct fallback StartGapScan started")
local firstAwaiting = SE.scan.awaitingItemID
check(firstAwaiting == 2770, "Direct scan awaiting first shortlisted item (2770)")
SE.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2770 })
check(SE.scan.scanned == 1 and SE.scan.awaitingItemID == 13464,
	"ITEM_SEARCH_RESULTS_UPDATED immediately advanced live Gap Scan without 10s stall")
SE.StopGapScan("test done")
check(SE.scan.active == false, "Direct fallback StopGapScan stopped scan")

-- 6c. Finding #1c: MarketScan.StartSniperQueue / CancelSniperQueue / CheckItemLive routing + cartBuyer.active guard
local msCalls = { start = 0, cancel = 0, check = 0, lastItems = nil, lastOnResult = nil, lastCheckOnResult = nil }
ns.MarketScan = {
	StartSniperQueue = function(items, onResult, opts)
		msCalls.start = msCalls.start + 1
		msCalls.lastItems = items
		msCalls.lastOnResult = onResult
		msCalls.lastOpts = opts
		return true, #items
	end,
	CancelSniperQueue = function()
		msCalls.cancel = msCalls.cancel + 1
	end,
	CheckItemLive = function(itemKey, onResult)
		msCalls.check = msCalls.check + 1
		msCalls.lastCheckKey = itemKey
		msCalls.lastCheckOnResult = onResult
		return true
	end,
}

-- cartBuyer.active == true blocks StartGapScan and StartVendorCheck
mockCartBuyerActive = true
local cbScanOk, cbScanErr = SE.StartGapScan({ econ = "Forever-EU" })
check(cbScanOk == false and cbScanErr == "cart_buyer_busy" and msCalls.start == 0,
	"cartBuyer.active blocks StartGapScan")
boeDeal.status = "unverified"
local cbCheckOk, cbCheckErr = SE.StartVendorCheck(boeDeal)
check(cbCheckOk == false and cbCheckErr == "cart_buyer_busy" and msCalls.check == 0,
	"cartBuyer.active blocks StartVendorCheck")
mockCartBuyerActive = false

-- StartGapScan routes through ns.MarketScan.StartSniperQueue and consumes onResult
SE.ClearGapDeals()
local okMsScan = SE.StartGapScan({ econ = "Forever-EU", minProfitCopper = 50000 })
check(okMsScan == true and msCalls.start == 1 and SE.scan.usingMarketScan == true,
	"StartGapScan routed through ns.MarketScan.StartSniperQueue")
msCalls.lastOnResult({
	itemID = 13464,
	isCommodity = true,
	whole = false,
	failed = false,
	rawRows = {
		{ unitPrice = 10000, quantity = 10, competitorQty = 10 },
		{ unitPrice = 22000, quantity = 50, competitorQty = 50 },
	},
})
check(SE.scan.scanned == 1 and SE.scan.dealsFound == 1 and SE.gapDealsByKey["gap:13464"] ~= nil,
	"MarketScan onResult callback evaluated commodity gap deal")
SE.StopGapScan("user stop")
check(msCalls.cancel == 1 and SE.scan.active == false, "StopGapScan invoked ns.MarketScan.CancelSniperQueue")

-- StartVendorCheck routes through ns.MarketScan.CheckItemLive and verifies live itemLink
boeDeal.status = "unverified"
local okMsCheck = SE.StartVendorCheck(boeDeal)
check(okMsCheck == true and msCalls.check == 1 and SE.pendingCheck.usingMarketScan == true,
	"StartVendorCheck routed through ns.MarketScan.CheckItemLive")
msCalls.lastCheckOnResult({
	itemID = 55001,
	isCommodity = false,
	whole = true,
	failed = false,
	rawRows = {
		{
			auctionID = 8001,
			buyoutAmount = 30000,
			quantity = 1,
			itemLink = "|cff1eff00|Hitem:55001::::::100:0:60|h[Scaled BoE Blade of the Bear]|h|r",
			containsOwnerItem = false,
		},
	},
})
check(boeDeal.status == "ready_to_buy" and boeDeal.auctionID == 8001 and boeDeal.vendorSell == 60000,
	"MarketScan.CheckItemLive callback verified live itemLink and marked ready_to_buy")
ns.MarketScan = nil

-- 6d. Finding #2: Watchdog timeouts on confirming (30s) and buying/PlaceBid (15s)
ahCalls = {}
deal.status = "ready"
check(SE.HandleRowAction(deal) == true, "Started commodity buy for confirming watchdog test")
SE.OnEvent("COMMODITY_PRICE_UPDATED", 10500, 210000)
check(SE.HandleRowAction(deal) == true and SE.GetPurchaseState().state == "confirming",
	"Entered confirming state for watchdog test")
flushTimers(29)
check(SE.GetPurchaseState() ~= nil and SE.GetPurchaseState().state == "confirming",
	"Still confirming at 29s")
flushTimers(2) -- 31s total (> QUOTE_TIMEOUT 30s)
check(SE.GetPurchaseState() == nil and deal.status == "ready",
	"Confirming watchdog cleared wedged SE.purchase after 30s and reset deal.status")

-- PlaceBid buying watchdog (15s) when auction is sniped and AUCTION_HOUSE_PURCHASE_COMPLETED never fires
ahCalls = {}
boeDeal.verifiedAt = mockNow
boeDeal.status = "ready_to_buy"
check(SE.HandleVendorAction(boeDeal) == true and SE.GetPurchaseState().state == "buying",
	"Entered buying (PlaceBid) state for 15s watchdog test")
flushTimers(14)
check(SE.GetPurchaseState() ~= nil and SE.GetPurchaseState().state == "buying",
	"Still buying at 14s")
flushTimers(2) -- 16s total (> BUY_WATCHDOG_TIMEOUT 15s)
check(SE.GetPurchaseState() == nil and boeDeal.status == "unverified" and boeDeal.verifiedAt == nil,
	"PlaceBid watchdog cleared wedged SE.purchase after 15s and reset deal to unverified")

-- 6e. Finding #3: Vendor Sniper Include Commodities inferred from maxStack on Snapshot & Browse rows
snapshotRawItems[55005] = { minBuyout = 2000, marketValue = 6000, historical = 6000, qty = 10 } -- 20s AH vs 50s vendor, maxStack=20
SE.ClearVendorDeals()
SE.SetOption("vendorIncludeCommodities", false)
SE.ScanSnapshotForVendorDeals("Forever-EU", { minProfitCopper = 1000 })
check(SE.vendorDealsByKey["vendor:55005"] == nil,
	"Snapshot vendor scan excluded stackable commodity (maxStack=20) when vendorIncludeCommodities=false")
check(SE.vendorDealsByKey["vendor:55002"] ~= nil and SE.vendorDealsByKey["vendor:55002"].isCommodity == false,
	"Snapshot vendor scan kept non-commodity BoE (maxStack=1) with boolean isCommodity=false")

-- Browse row without explicit isCommodity field also infers commodity from maxStack
local browseCommExcluded = SE.IngestBrowseBatch({
	{ itemID = 55005, minPrice = 2000, totalQuantity = 10 }, -- no isCommodity field!
}, "Forever-EU")
check(browseCommExcluded == 0 and SE.vendorDealsByKey["vendor:55005"] == nil,
	"Browse vendor scan inferred commodity from maxStack=20 and excluded when vendorIncludeCommodities=false")

SE.SetOption("vendorIncludeCommodities", true)
local browseCommIncluded = SE.IngestBrowseBatch({
	{ itemID = 55005, minPrice = 2000, totalQuantity = 10 },
}, "Forever-EU")
check(browseCommIncluded == 1 and SE.vendorDealsByKey["vendor:55005"] ~= nil
	and SE.vendorDealsByKey["vendor:55005"].isCommodity == true,
	"Browse vendor scan included commodity when vendorIncludeCommodities=true and tagged boolean isCommodity=true")

-------------------------------------------------------------------------------
-- 7. ALL-ITEMS 2-Stage Gap Sniper (Scope, Browse->Drill, Equipment Evaluator & Sequential PlaceBid)
-------------------------------------------------------------------------------

-- 7a. gapScope option validation & persistence
check(SE.SetOption("gapScope", "commodities") == true and SE.GetSettings().gapScope == "commodities",
	"SetOption persists gapScope='commodities'")
check(SE.SetOption("gapScope", "items") == true and SE.GetSettings().gapScope == "items",
	"SetOption persists gapScope='items'")
check(SE.SetOption("gapScope", "invalid_scope") == false and SE.GetSettings().gapScope == "items",
	"SetOption rejects invalid gapScope value")
check(SE.SetOption("gapScope", "all") == true and SE.GetSettings().gapScope == "all",
	"SetOption restores gapScope='all'")

-- Add synthetic BoE epic + overpriced equipment to mock data for All-Items testing
mockItemInfo[55010] = { "Teebu's Blazing Longsword", "|cffa335ee|Hitem:55010|h[Teebu's Blazing Longsword]|h|r", 4, 150000, 1 }
mockItemInfo[55011] = { "Overpriced Epic Helm", "|cffa335ee|Hitem:55011|h[Overpriced Epic Helm]|h|r", 4, 100000, 1 }
mockDemand[55010] = { dailySold = 6, effectiveDailySold = 6, demandSource = "TSM", confidence = 2 }
mockDemand[55011] = { dailySold = 6, effectiveDailySold = 6, demandSource = "TSM", confidence = 2 }
mockRegSale[55010] = { regionSale = 5000000, soldPerDay = 6, saleRate = 0.25 } -- 500g ref
mockRegSale[55011] = { regionSale = 1000000, soldPerDay = 6, saleRate = 0.25 } -- 100g ref

-- 7b. EvaluateItemGap: multi-listing equipment price ladder, owner/secret filtering, exact math
local equipRows = {
	SECRET_TABLE,
	{ auctionID = SECRET_SENTINEL, buyoutAmount = 100000, quantity = 1 },
	{ auctionID = 9000, buyoutAmount = 1000000, quantity = 1, containsOwnerItem = true }, -- own auction skipped!
	-- Unsorted order on purpose to verify ascending unit-price sort:
	{ auctionID = 9004, buyoutAmount = 4500000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- 450g wall
	{ auctionID = 9002, buyoutAmount = 2000000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- 200g (tier 1b)
	{ auctionID = 9005, buyoutAmount = 6000000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- 600g above wall
	{ auctionID = 9003, buyoutAmount = 2400000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- 240g (tier 2)
	{ auctionID = 9001, buyoutAmount = 2000000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- 200g (tier 1a)
}
local equipDeal = SE.EvaluateItemGap(55010, equipRows, {
	refPrice = 5000000,       -- 500g
	dailySold = 6,            -- 50% cap = 3 units -> covers all 3 cheap listings (9001, 9002, 9003)!
	vendorSell = 150000,      -- 15g
	maxSpend = 10000000,      -- 1000g
	isNeutral = false,
	minProfitCopper = 100000,
})
check(equipDeal ~= nil, "EvaluateItemGap found multi-listing equipment deal")
check(equipDeal.kind == "item" and equipDeal.isCommodity == false, "Equipment deal tagged kind='item' and isCommodity=false")
check(equipDeal.buyQty == 3 and equipDeal.listingCount == 3 and equipDeal.remainingListings == 3,
	"Equipment deal covers 3 units across 3 cheap listings")
check(#equipDeal.buyQueue == 3
	and equipDeal.buyQueue[1].auctionID == 9001
	and equipDeal.buyQueue[2].auctionID == 9002
	and equipDeal.buyQueue[3].auctionID == 9003,
	"buyQueue sorted ascending by unit price / auctionID (9001 -> 9002 -> 9003)")
check(equipDeal.totalCost == 6400000, "Total cost = 200g + 200g + 240g = 640g (6400000c)")
check(near(equipDeal.avgBuyPrice, 6400000 / 3), "Exact average buy price across 3 equipment listings")
check(equipDeal.nextTierPrice == 4500000 and equipDeal.relistPrice == 4499999,
	"Relist price = min(nextTier(450g) - 1, refPrice(500g)) = 4499999c")
local eqGross = 4499999 * 3
local eqCut = math.floor(eqGross * 0.05 + 0.5)
check(equipDeal.netProfit == (eqGross - eqCut - 6400000), "Exact netProfit after 5% AH cut")
check(equipDeal.deposit == SE.GetForeverAuctionDeposit(150000, 3, 8, false), "Exact 8h Forever deposit for 3 equipment units")
check(near(equipDeal.estHoursToSell, (3 / 6) * 24), "Est. Hours-to-Sell = (3/6)*24 = 12.0h")
check(equipDeal.ladder ~= nil and #equipDeal.ladder == 4, "Equipment ladder has 4 tiers (2 buy + 1 wall + 1 above)")
check(equipDeal.ladder[1].role == "buy" and equipDeal.ladder[1].quantity == 2
	and equipDeal.ladder[2].role == "buy" and equipDeal.ladder[2].quantity == 1
	and equipDeal.ladder[3].role == "wall" and equipDeal.ladder[3].unitPrice == 4500000
	and equipDeal.ladder[4].role == "above",
	"Equipment Price Ladder matches EvaluateCommodityGap shape (buy/buy/wall/above)")

-- Single-listing BoE equipment succeeds even though settings.minQty == 2 (anti-bait minQty=2 is commodities-only!)
local singleBoeDeal = SE.EvaluateItemGap(55010, {
	{ auctionID = 9101, buyoutAmount = 2000000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- 1 cheap BoE @ 200g
	{ auctionID = 9102, buyoutAmount = 4500000, quantity = 1, itemLink = mockItemInfo[55010][2] }, -- wall @ 450g
}, {
	refPrice = 5000000,
	dailySold = 1, -- 1/day at 50% allows 1 unit for BoE equipment
	maxSpend = 5000000,
	isNeutral = false,
	minProfitCopper = 100000,
})
check(singleBoeDeal ~= nil and singleBoeDeal.buyQty == 1 and singleBoeDeal.listingCount == 1,
	"Single cheap BoE listing (qty=1) passes EvaluateItemGap even when commodity minQty=2")

-- Neutral 15% cut disqualifies thin equipment flip that passes at 5% faction cut
local thinEquipRows = {
	{ auctionID = 9201, buyoutAmount = 1000000, quantity = 1 }, -- 100g
	{ auctionID = 9202, buyoutAmount = 1350000, quantity = 1 }, -- 135g wall
}
check(SE.EvaluateItemGap(55010, thinEquipRows, {
	refPrice = 1500000, dailySold = 4, isNeutral = false, minRoiPct = 25, minProfitCopper = 50000,
}) ~= nil, "Thin equipment flip passes on 5% faction AH")
check(SE.EvaluateItemGap(55010, thinEquipRows, {
	refPrice = 1500000, dailySold = 4, isNeutral = true, minRoiPct = 25, minProfitCopper = 50000,
}) == nil, "Same thin equipment flip disqualified on 15% neutral AH")

-- 7c. Multi-Listing Equipment Purchase (HandleRowAction -> sequential PlaceBid until buyQueue empty)
ahCalls = {}
SE.OnEvent("AUCTION_HOUSE_SHOW")

-- CartBuyer active guard blocks equipment gap buy
mockCartBuyerActive = true
local eqBlocked, eqBlockReason = SE.HandleRowAction(equipDeal)
check(eqBlocked == false and eqBlockReason == "cart_buyer_busy" and #ahCalls == 0,
	"isCartBuyerActive() blocks equipment gap PlaceBid")
mockCartBuyerActive = false

local buysBefore = SE.GetSessionStats().buys
-- Buy listing #1 (9001 @ 200g)
check(SE.HandleRowAction(equipDeal) == true and equipDeal.status == "buying",
	"Click 1 on equipment deal started PlaceBid for buyQueue[1]")
check(#ahCalls == 1 and ahCalls[1].fn == "PlaceBid"
	and ahCalls[1].auctionID == 9001 and ahCalls[1].amount == 2000000,
	"PlaceBid #1 called with auctionID=9001, buyout=2000000")
SE.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 9001)
check(equipDeal.status == "ready" and #equipDeal.buyQueue == 2
	and equipDeal.listingCount == 2 and equipDeal.remainingListings == 2
	and equipDeal.totalListings == 3 and equipDeal.boughtListings == 1
	and equipDeal.buyQueue[1].auctionID == 9002,
	"Purchase #1 popped buyQueue[1], tracked boughtListings=1 / totalListings=3, kept status='ready'")
-- Verify MEDIUM #4 recalculated remaining economics for 2 remaining lots (200g + 240g = 440g, avg 220g)
local rem2Gross = 4499999 * 2
local rem2Cut = math.floor(rem2Gross * 0.05 + 0.5)
local rem2Net = rem2Gross - rem2Cut - 4400000
check(equipDeal.buyQty == 2 and equipDeal.totalCost == 4400000 and near(equipDeal.avgBuyPrice, 2200000),
	"Purchase #1 recalculated remaining buyQty=2, totalCost=440g, avgBuyPrice=220g")
check(equipDeal.grossRevenue == rem2Gross and equipDeal.ahCut == rem2Cut and equipDeal.netProfit == rem2Net,
	"Purchase #1 recalculated remaining grossRevenue, ahCut, and netProfit")
check(equipDeal.deposit == SE.GetForeverAuctionDeposit(150000, 2, 8, false),
	"Purchase #1 recalculated remaining Forever deposit for 2 lots")
check(near(equipDeal.roiPct, (rem2Net / 4400000) * 100)
	and near(equipDeal.gapPct, ((4500000 - 2200000) / 2200000) * 100)
	and near(equipDeal.estHoursToSell, (2 / 6) * 24),
	"Purchase #1 recalculated remaining roiPct, gapPct, and estHoursToSell")

-- Buy listing #2 (9002 @ 200g)
check(SE.HandleRowAction(equipDeal) == true and equipDeal.status == "buying",
	"Click 2 on equipment deal started PlaceBid for buyQueue[1] (9002)")
check(#ahCalls == 2 and ahCalls[2].fn == "PlaceBid"
	and ahCalls[2].auctionID == 9002 and ahCalls[2].amount == 2000000,
	"PlaceBid #2 called with auctionID=9002, buyout=2000000")
SE.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 9002)
check(equipDeal.status == "ready" and #equipDeal.buyQueue == 1
	and equipDeal.listingCount == 1 and equipDeal.remainingListings == 1
	and equipDeal.totalListings == 3 and equipDeal.boughtListings == 2
	and equipDeal.buyQueue[1].auctionID == 9003,
	"Purchase #2 popped buyQueue[1], tracked boughtListings=2 / totalListings=3, kept status='ready'")
local rem1Gross = 4499999
local rem1Cut = math.floor(rem1Gross * 0.05 + 0.5)
local rem1Net = rem1Gross - rem1Cut - 2400000
check(near(equipDeal.avgBuyPrice, 2400000) and equipDeal.netProfit == rem1Net
	and near(equipDeal.estHoursToSell, (1 / 6) * 24),
	"Purchase #2 recalculated exact single-lot remaining avgBuyPrice=240g, netProfit, estHoursToSell")

-- Buy listing #3 (9003 @ 240g) -> completes and marks status='bought'
check(SE.HandleRowAction(equipDeal) == true and equipDeal.status == "buying",
	"Click 3 started PlaceBid for final listing 9003")
SE.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 9003)
check(equipDeal.status == "bought" and #equipDeal.buyQueue == 0
	and equipDeal.listingCount == 0 and equipDeal.remainingListings == 0,
	"Final purchase emptied buyQueue and transitioned equipment deal to status='bought'")
check(SE.GetSessionStats().buys == buysBefore + 3, "Session stats counted all 3 sequential equipment buys")

-- 7d. True 2-Stage Live Sweep: Stage 1 (Browse ALL AH via EnsureBrowseRunning) -> OnBrowseScanComplete -> Stage 2 (Drill ONLY hits)
local twoStageCalls = { browse = 0, cancelBrowse = 0, startQueue = 0, cancelQueue = 0, queued = nil, onResult = nil }
local mockBrowseActive = false
ns.MarketScan = {
	GetState = function()
		return { active = mockBrowseActive }
	end,
	EnsureBrowseRunning = function()
		twoStageCalls.browse = twoStageCalls.browse + 1
		if mockBrowseActive then
			return true, "already_active"
		end
		mockBrowseActive = true
		return true
	end,
	CancelBrowseScan = function()
		twoStageCalls.cancelBrowse = twoStageCalls.cancelBrowse + 1
		mockBrowseActive = false
	end,
	StartSniperQueue = function(items, onResult, opts)
		twoStageCalls.startQueue = twoStageCalls.startQueue + 1
		twoStageCalls.queued = items
		twoStageCalls.onResult = onResult
		return true, #items
	end,
	CancelSniperQueue = function()
		twoStageCalls.cancelQueue = twoStageCalls.cancelQueue + 1
	end,
}

SE.ClearGapDeals()
SE.scan.lastBrowseAt = nil
mockBrowseActive = false
local okStage1 = SE.StartGapScan({ econ = "Forever-EU", gapScope = "all", maxSpend = 10000000, minProfitCopper = 50000 })
check(okStage1 == true and SE.scan.active == true and SE.scan.phase == "browse" and SE.scan.awaitingBrowse == true,
	"StartGapScan entered Stage 1 (phase='browse', awaitingBrowse=true)")
check(twoStageCalls.browse == 1 and twoStageCalls.startQueue == 0,
	"Stage 1 triggered full AH Browse sweep via MarketScan.EnsureBrowseRunning before Stage 2")

-- Feed fresh Browse rows: cheap epic 55010 (200g vs 500g ref = 40% HIT) + overpriced 55011 (120g vs 100g ref = 120% SKIP)
SE.IngestBrowseBatch({
	{ itemID = 55010, minPrice = 2000000, totalQuantity = 4, quality = 4, isCommodity = false },
	{ itemID = 55011, minPrice = 1200000, totalQuantity = 2, quality = 4, isCommodity = false },
}, "Forever-EU")
check(SE.scan.browseSeen == 2 and SE.GetScanProgress().phase == "browse",
	"IngestBrowseBatch tracked browseSeen during Stage 1")

-- Browse completes -> automatically transitions to Stage 2 drilling ONLY live browse hits from this sweep!
mockBrowseActive = false
SE.OnBrowseScanComplete("Forever-EU", false)
check(SE.scan.awaitingBrowse == false and SE.scan.phase == "drill" and SE.scan.active == true,
	"OnBrowseScanComplete cleared awaitingBrowse and transitioned to Stage 2 (phase='drill')")
check(twoStageCalls.startQueue == 1 and twoStageCalls.queued ~= nil,
	"Stage 2 started MarketScan.StartSniperQueue on browse hits")
check(#twoStageCalls.queued == 1,
	"HIGH #1B: Complete Stage 1 -> Stage 2 drilled ONLY the 1 live browse hit (zero ghost Snapshot/stale items); got " .. #twoStageCalls.queued)

local queued55010, queued55011 = false, false
for i = 1, #twoStageCalls.queued do
	local q = twoStageCalls.queued[i]
	local qid = type(q) == "table" and q.itemID or q
	if qid == 55010 then queued55010 = true end
	if qid == 55011 then queued55011 = true end
end
check(queued55010 == true and queued55011 == false,
	"Stage 2 queued cheap epic hit 55010 and excluded overpriced 55011")

-- Deliver non-commodity rawRows via MarketScan queue callback -> evaluates via EvaluateItemGap!
twoStageCalls.onResult({
	itemID = 55010,
	isCommodity = false,
	whole = true,
	failed = false,
	rawRows = {
		{ auctionID = 9501, buyoutAmount = 2000000, quantity = 1, itemLink = mockItemInfo[55010][2] },
		{ auctionID = 9502, buyoutAmount = 4600000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	},
})
check(SE.gapDealsByKey["gap:55010"] ~= nil and SE.gapDealsByKey["gap:55010"].kind == "item"
	and SE.gapDealsByKey["gap:55010"].listingCount == 1,
	"MarketScan queue callback evaluated non-commodity rawRows via EvaluateItemGap")

SE.StopGapScan("done stage2")
check(SE.scan.active == false and SE.scan.phase == "idle" and SE.scan.awaitingBrowse == false,
	"StopGapScan cleanly cleared phase='idle' and awaitingBrowse=false")

-- Fresh browse (< 60s ago) jumps straight to Stage 2 without re-running Stage 1 Browse (forceRedrill=true to bypass M2 cache)
mockNow = mockNow + 20 -- only 20s since lastBrowseAt (< 60s TTL)
local okFreshJump = SE.StartGapScan({ econ = "Forever-EU", gapScope = "items", forceRedrill = true })
check(okFreshJump == true and SE.scan.phase == "drill" and SE.scan.awaitingBrowse == false
	and twoStageCalls.browse == 1 and twoStageCalls.startQueue == 2 and #twoStageCalls.queued == 1,
	"StartGapScan skipped Stage 1 when browse swept < 60s ago and drilled only fresh browse hits")
SE.StopGapScan("done fresh")

-- forceBrowse=true forces Stage 1 even when < 60s ago; StopGapScan calls MarketScan.CancelBrowseScan
local okForceBrowse = SE.StartGapScan({ econ = "Forever-EU", forceBrowse = true })
check(okForceBrowse == true and SE.scan.phase == "browse" and SE.scan.awaitingBrowse == true
	and twoStageCalls.browse == 2,
	"forceBrowse=true ran Stage 1 even when browse was < 60s old")
SE.StopGapScan("cancel browse")
check(SE.scan.active == false and SE.scan.phase == "idle" and SE.scan.awaitingBrowse == false
	and twoStageCalls.cancelBrowse == 1,
	"StopGapScan during Stage 1 cleared awaitingBrowse, phase='idle', and called MarketScan.CancelBrowseScan")

-- HIGH #1C: AUCTION_HOUSE_BROWSE_FAILURE and AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED unwedge Stage 1 cleanly
check(SE.StartGapScan({ econ = "Forever-EU", forceBrowse = true }) == true and SE.scan.awaitingBrowse == true,
	"Started Stage 1 for AUCTION_HOUSE_BROWSE_FAILURE test")
SE.OnEvent("AUCTION_HOUSE_BROWSE_FAILURE")
check(SE.scan.active == false and SE.scan.phase == "idle" and SE.scan.awaitingBrowse == false,
	"HIGH #1C: AUCTION_HOUSE_BROWSE_FAILURE cleanly stopped Stage 1 without wedging")

check(SE.StartGapScan({ econ = "Forever-EU", forceBrowse = true }) == true and SE.scan.awaitingBrowse == true,
	"Started Stage 1 for AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED test")
SE.OnEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
check(SE.scan.active == false and SE.scan.phase == "idle" and SE.scan.awaitingBrowse == false,
	"HIGH #1C: AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED cleanly stopped Stage 1 without wedging")

-- skipBrowse=true jumps straight to Stage 2 even after browse becomes stale (> 60s)
mockNow = mockNow + 120
local okSkipBrowse = SE.StartGapScan({ econ = "Forever-EU", skipBrowse = true, gapScope = "items" })
check(okSkipBrowse == true and SE.scan.phase == "drill" and SE.scan.awaitingBrowse == false
	and twoStageCalls.browse == 4 and twoStageCalls.startQueue == 3,
	"skipBrowse=true jumped straight to Stage 2 even when browse was stale (> 60s)")
SE.StopGapScan("done skip")

-- 7e. Direct ITEM_SEARCH_RESULTS_UPDATED fallback evaluates equipment rawRows via EvaluateItemGap
ns.MarketScan = nil
SE.ClearGapDeals()
SE.IngestBrowseBatch({
	{ itemID = 55010, minPrice = 2100000, totalQuantity = 3, quality = 4, isCommodity = false },
}, "Forever-EU")
mockItemSearchResults[55010] = {
	{ auctionID = 9601, buyoutAmount = 2100000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	{ auctionID = 9602, buyoutAmount = 4800000, quantity = 1, itemLink = mockItemInfo[55010][2] },
}
local okDirectItem = SE.StartGapScan({ econ = "Forever-EU", gapScope = "items", maxSpend = 10000000, minProfitCopper = 50000 })
check(okDirectItem == true and SE.scan.phase == "drill", "Direct fallback started Stage 2 for scope='items'")
-- Step until awaitingItemID == 55010
local guardStep = 0
while SE.scan.active and SE.scan.awaitingItemID ~= 55010 and guardStep < 10 do
	guardStep = guardStep + 1
	SE.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", SE.scan.awaitingItemKey or { itemID = SE.scan.awaitingItemID })
end
check(SE.scan.awaitingItemID == 55010, "Direct fallback awaiting item 55010")
SE.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 55010 })
check(SE.gapDealsByKey["gap:55010"] ~= nil and SE.gapDealsByKey["gap:55010"].kind == "item"
	and SE.gapDealsByKey["gap:55010"].buyQueue[1].auctionID == 9601,
	"Direct ITEM_SEARCH_RESULTS_UPDATED fallback evaluated equipment via EvaluateItemGap")
SE.StopGapScan("done direct item")

-------------------------------------------------------------------------------
-- 8. Review v2 & Forever Speed Regressions (HIGH #1-#3, MEDIUM #4, Pre-Filter & Priority Sort)
-------------------------------------------------------------------------------

-- 8a. HIGH #1A: Multi-variant itemKey BoEs never overwrite each other in SE.browseCache / shortlist
mockDemand[55001] = { dailySold = 4, effectiveDailySold = 4, demandSource = "TSM", confidence = 2 }
mockRegSale[55001] = { regionSale = 1000000, soldPerDay = 4, saleRate = 0.25 } -- 100g ref
local keyBear = { itemID = 55001, itemLevel = 60, itemSuffix = 100, battlePetSpeciesID = 0 }
local keyOwl = { itemID = 55001, itemLevel = 60, itemSuffix = 200, battlePetSpeciesID = 0 }
local variantStart = mockNow + 50
mockNow = variantStart
SE.IngestBrowseBatch({
	{ itemID = 55001, itemKey = keyBear, minPrice = 200000, totalQuantity = 2, quality = 2, isCommodity = false },  -- 20g cheap Bear (qty=2 cliff possible)!
	{ itemID = 55001, itemKey = keyOwl,  minPrice = 1500000, totalQuantity = 2, quality = 2, isCommodity = false }, -- 150g overpriced Owl!
}, "Forever-EU")
check(SE.browseCache["55001:60:100:0"] ~= nil and SE.browseCache["55001:60:100:0"].minPrice == 200000,
	"HIGH #1A: Bear variant preserved at key '55001:60:100:0' (20g)")
check(SE.browseCache["55001:60:200:0"] ~= nil and SE.browseCache["55001:60:200:0"].minPrice == 1500000,
	"HIGH #1A: Owl variant stored separately at key '55001:60:200:0' (150g)")
local variantList = SE.BuildGapShortlist({
	econ = "Forever-EU", gapScope = "items", browseOnly = true, minUpdatedAt = variantStart,
})
check(#variantList == 1 and variantList[1].itemID == 55001
	and variantList[1].itemKey and variantList[1].itemKey.itemSuffix == 100,
	"HIGH #1A: Shortlist preserved cheap Bear variant (suffix=100) despite expensive Owl variant (suffix=200)")

-- 8b. HIGH #2: Equipment liquidity cap (<1/day rare BoE & odd dailySold=3) + opts.minQty isolation
local rareBoeDeal = SE.EvaluateItemGap(55010, {
	{ auctionID = 9701, buyoutAmount = 2000000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	{ auctionID = 9702, buyoutAmount = 4500000, quantity = 1, itemLink = mockItemInfo[55010][2] },
}, {
	refPrice = 5000000,
	dailySold = 0.2, -- rare <1/day BoE at 50% -> max(1, floor(0.1+0.5)) = 1 lot allowed!
	minQty = 2,      -- commodity minQty=2 must NOT leak into EvaluateItemGap!
	maxSpend = 5000000,
	isNeutral = false,
	minProfitCopper = 10000,
})
check(rareBoeDeal ~= nil and rareBoeDeal.buyQty == 1,
	"HIGH #2: <1/day rare BoE allowed (liqCap >= 1) and commodity opts.minQty=2 ignored by EvaluateItemGap")

local oddDailyDeal = SE.EvaluateItemGap(55010, {
	{ auctionID = 9711, buyoutAmount = 1800000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	{ auctionID = 9712, buyoutAmount = 1900000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	{ auctionID = 9713, buyoutAmount = 4500000, quantity = 1, itemLink = mockItemInfo[55010][2] },
}, {
	refPrice = 5000000,
	dailySold = 3, -- 50% of 3 = 1.5 -> max(1, floor(1.5+0.5)) = 2 lots (matches UI_Sniper!)
	maxBuyShareDailyPct = 50,
	maxSpend = 5000000,
	isNeutral = false,
	minProfitCopper = 10000,
})
check(oddDailyDeal ~= nil and oddDailyDeal.buyQty == 2 and oddDailyDeal.listingCount == 2,
	"HIGH #2: dailySold=3 at 50% allows 2 equipment lots matching UI_Sniper")

local itemMinQtyReject = SE.EvaluateItemGap(55010, {
	{ auctionID = 9721, buyoutAmount = 2000000, quantity = 1 },
	{ auctionID = 9722, buyoutAmount = 4500000, quantity = 1 },
}, {
	refPrice = 5000000, dailySold = 6, itemMinQty = 2, maxSpend = 5000000, minProfitCopper = 10000,
})
check(itemMinQtyReject == nil, "HIGH #2: Explicit opts.itemMinQty=2 still enforced when requested")

-- 8c. HIGH #3: Snapshot equipment deal 2-step Check -> Buy (N) (via MarketScan.CheckItemLive & direct fallback)
mockDepth[55004] = {
	{ price = 15000, qty = 2 },
	{ price = 28000, qty = 10 },
}
SE.ClearGapDeals()
SE.ScanSnapshotForGapDeals("Forever-EU", { gapScope = "items", minProfitCopper = 5000 })
local snapEq = SE.gapDealsByKey["gap:55004"]
check(snapEq ~= nil and snapEq.kind == "item" and snapEq.needsLiveScan == true and snapEq.buyQueue == nil,
	"HIGH #3: ScanSnapshotForGapDeals produced equipment preview with needsLiveScan=true, buyQueue=nil")

local checkMsCalls = { count = 0, cb = nil }
ns.MarketScan = {
	CheckItemLive = function(key, cb)
		checkMsCalls.count = checkMsCalls.count + 1
		checkMsCalls.cb = cb
		return true
	end,
}
ahCalls = {}
-- Click 1 -> CheckItemGapLive via MarketScan.CheckItemLive
local okChk1 = SE.HandleRowAction(snapEq)
check(okChk1 == true and snapEq.status == "checking" and checkMsCalls.count == 1 and #ahCalls == 0,
	"HIGH #3: Click 1 on Snapshot equipment deal dispatched CheckItemGapLive (status='checking')")
checkMsCalls.cb({
	itemID = 55004,
	isCommodity = false,
	whole = true,
	failed = false,
	rawRows = {
		{ auctionID = 9801, buyoutAmount = 15000, quantity = 1, itemLink = mockItemInfo[55004][2] },
		{ auctionID = 9802, buyoutAmount = 15000, quantity = 1, itemLink = mockItemInfo[55004][2] },
		{ auctionID = 9803, buyoutAmount = 28000, quantity = 1, itemLink = mockItemInfo[55004][2] },
	},
})
check(snapEq.status == "ready" and snapEq.needsLiveScan == false
	and snapEq.buyQueue ~= nil and #snapEq.buyQueue == 2 and snapEq.totalListings == 2,
	"HIGH #3: Live check populated buyQueue (2 lots), cleared needsLiveScan, set status='ready'")

-- Click 2 -> synchronous PlaceBid on buyQueue[1]
local okChkBuy = SE.HandleRowAction(snapEq)
check(okChkBuy == true and #ahCalls == 1 and ahCalls[1].fn == "PlaceBid"
	and ahCalls[1].auctionID == 9801 and ahCalls[1].amount == 15000,
	"HIGH #3: Click 2 synchronously called PlaceBid(9801, 15000) after live check")
SE.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 9801)
check(snapEq.status == "ready" and snapEq.remainingListings == 1 and snapEq.boughtListings == 1 and snapEq.totalListings == 2,
	"HIGH #3 + #4: First PlaceBid succeeded, 1/2 lots left")

-- Case when live check finds listings gone -> status='unavailable'
snapEq.needsLiveScan = true
snapEq.buyQueue = nil
check(SE.HandleRowAction(snapEq) == true and snapEq.status == "checking", "Re-check started for gone listing test")
checkMsCalls.cb({
	itemID = 55004,
	isCommodity = false,
	whole = true,
	failed = false,
	rawRows = {
		{ auctionID = 9899, buyoutAmount = 29000, quantity = 1 },
	},
})
check(snapEq.status == "unavailable" and snapEq.buyQueue == nil,
	"HIGH #3: Gone equipment listings set status='unavailable'")
ns.MarketScan = nil

-- 8d. Speed & Pre-Filter Tuning: Stage 1 pre-filter skips <7% tiny discounts & priority sorts by discount % x velocity
mockItemInfo[55012] = { "Tiny Discount Herb", "|cffffffff|Hitem:55012|h[Tiny Discount Herb]|h|r", 1, 100, 20 }
mockItemInfo[55013] = { "Huge Snipe Herb", "|cffffffff|Hitem:55013|h[Huge Snipe Herb]|h|r", 1, 100, 20 }
mockDemand[55012] = { dailySold = 500, effectiveDailySold = 500, demandSource = "Blizz", confidence = 3 }
mockDemand[55013] = { dailySold = 50, effectiveDailySold = 50, demandSource = "Blizz", confidence = 3 }
mockRegSale[55012] = { regionSale = 10000, soldPerDay = 500, saleRate = 0.5 }
mockRegSale[55013] = { regionSale = 10000, soldPerDay = 50, saleRate = 0.5 }
local tuneStart = mockNow + 100
mockNow = tuneStart
SE.IngestBrowseBatch({
	{ itemID = 55012, minPrice = 8500, totalQuantity = 50, quality = 1, isCommodity = true }, -- 85% (> 82% exact faction ceiling at 15%/15%) -> SKIP!
	{ itemID = 55013, minPrice = 2500, totalQuantity = 50, quality = 1, isCommodity = true }, -- 75% discount x 50 = 3750 score -> #1!
	{ itemID = 2447,  minPrice = 600,  totalQuantity = 50, quality = 1, isCommodity = true }, -- 25% discount x 5 = 125 score -> #2 (with low minProfit)!
}, "Forever-EU")
local tunedList = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = tuneStart, minGapPct = 15, minRoiPct = 15, buyCeilingPct = 95, minProfitCopper = 100,
})
check(#tunedList == 2 and tunedList[1].itemID == 55013 and tunedList[2].itemID == 2447,
	"Pre-filter excluded 15%-off item (55012 @ 85% > 82% exact faction ceiling) and sorted by discount% x velocity (55013 before 2447)")

-- 8e. High #29: SavedVariables one-time Wave 1 -> Forever defaults migration + non-zero ceiling at minGapPct=250
local prevSniperDB = _G.MerchantMasterDB.sniper
_G.MerchantMasterDB.sniper = {
	minGapPct = 20,
	minRoiPct = 25,
	minProfitCopper = 100000,
	maxShortlistItems = 250,
}
local migrated = SE.GetSettings()
check(migrated._foreverDefaultsV2 == true
	and migrated.minGapPct == 15 and migrated.minRoiPct == 15
	and migrated.minProfitCopper == 10000 and migrated.maxShortlistItems == 120,
	"SavedVariables one-time migration updated legacy Wave 1 defaults (20/25/10g/250 -> 15/15/1g/120)")
-- Once migrated, explicit user choices (e.g. setting minGapPct back to 20) are NOT overwritten on subsequent GetSettings()
SE.SetOption("minGapPct", 20)
check(SE.GetSettings().minGapPct == 20, "One-time migration does not overwrite post-migration user settings")
_G.MerchantMasterDB.sniper = prevSniperDB

-- Non-zero exact ceiling at extreme minGapPct=250: floor(100 / (1 + 2.5)) = 28% -> keeps 25%-of-ref snipe 55013 (2500 vs 10000)!
local highGapList = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = tuneStart, minGapPct = 250, minRoiPct = 15, buyCeilingPct = 95,
})
check(#highGapList == 1 and highGapList[1].itemID == 55013,
	"High minGapPct=250 keeps positive 28% exact ceiling (never zeros out) and retains 75%-off snipe 55013")

-------------------------------------------------------------------------------
-- 9. EGM Consolidated Review Regressions (B2, B3, B5, B6, B7, M2, M3, M4)
-------------------------------------------------------------------------------

-- 9a. B2: Exact Branch-and-Bound Stage 1 Pruning (zero false negatives, prunes mathematically impossible items)
mockItemInfo[56001] = { "Neutral Fail Herb", "|cffffffff|Hitem:56001|h[Neutral Fail Herb]|h|r", 1, 100, 20 }
mockItemInfo[56002] = { "Single Qty Item", "|cff1eff00|Hitem:56002|h[Single Qty Item]|h|r", 2, 10000, 1 }
mockItemInfo[56003] = { "Two Qty Comm", "|cffffffff|Hitem:56003|h[Two Qty Comm]|h|r", 1, 100, 20 }
mockItemInfo[56004] = { "Expensive Unafford BoE", "|cffa335ee|Hitem:56004|h[Expensive Unafford BoE]|h|r", 4, 50000, 1 }
mockItemInfo[56005] = { "Low Liq Comm", "|cffffffff|Hitem:56005|h[Low Liq Comm]|h|r", 1, 100, 20 }
mockItemInfo[56006] = { "Low Profit Comm", "|cffffffff|Hitem:56006|h[Low Profit Comm]|h|r", 1, 100, 20 }
mockItemInfo[56007] = { "Valid B2 Comm", "|cffffffff|Hitem:56007|h[Valid B2 Comm]|h|r", 1, 100, 20 }
mockDemand[56001] = { dailySold = 50, effectiveDailySold = 50 }
mockDemand[56002] = { dailySold = 10, effectiveDailySold = 10 }
mockDemand[56003] = { dailySold = 50, effectiveDailySold = 50 }
mockDemand[56004] = { dailySold = 10, effectiveDailySold = 10 }
mockDemand[56005] = { dailySold = 3,  effectiveDailySold = 3 }  -- 50% of 3 = floor(1.5) = 1 < minQty(2) -> PRUNE!
mockDemand[56006] = { dailySold = 10, effectiveDailySold = 10 } -- 50% of 10 = 5 units; 5*(950-500)=2250c < 10000c -> PRUNE!
mockDemand[56007] = { dailySold = 50, effectiveDailySold = 50 }
mockRegSale[56001] = { regionSale = 100000, soldPerDay = 50 }   -- 10g ref
mockRegSale[56002] = { regionSale = 500000, soldPerDay = 10 }   -- 50g ref
mockRegSale[56003] = { regionSale = 100000, soldPerDay = 50 }   -- 10g ref
mockRegSale[56004] = { regionSale = 2000000, soldPerDay = 10 }  -- 200g ref
mockRegSale[56005] = { regionSale = 100000, soldPerDay = 3 }    -- 10g ref
mockRegSale[56006] = { regionSale = 1000, soldPerDay = 10 }     -- 10s ref
mockRegSale[56007] = { regionSale = 100000, soldPerDay = 50 }   -- 10g ref

local b2Start = mockNow + 200
mockNow = b2Start
SE.IngestBrowseBatch({
	{ itemID = 56001, minPrice = 78000,  totalQuantity = 20, quality = 1, isCommodity = true },  -- 78% of 10g: passes 82% faction, fails 73% neutral!
	{ itemID = 56002, minPrice = 100000, totalQuantity = 1,  quality = 2, isCommodity = false }, -- totalQty=1 -> impossible cliff!
	{ itemID = 56003, minPrice = 50000,  totalQuantity = 2,  quality = 1, isCommodity = true },  -- totalQty=2 < minQty(2)+1 -> impossible cliff!
	{ itemID = 56004, minPrice = 600000, totalQuantity = 5,  quality = 4, isCommodity = false }, -- 60g > 50g maxSpend -> unaffordable!
	{ itemID = 56005, minPrice = 50000,  totalQuantity = 20, quality = 1, isCommodity = true },  -- dailySold=3 -> liqCap=1 < minQty(2)!
	{ itemID = 56006, minPrice = 500,    totalQuantity = 20, quality = 1, isCommodity = true },  -- max profit 5*450=2250c < 1g minProfit!
	{ itemID = 56007, minPrice = 50000,  totalQuantity = 20, quality = 1, isCommodity = true },  -- valid: 50% off, qty=20, maxProfit=20*45000=90g!
}, "Forever-EU")

local b2Faction = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000,
	minQty = 2, maxBuyShareDailyPct = 50, isNeutral = false,
})
local b2FIds = {}
for i = 1, #b2Faction do b2FIds[b2Faction[i].itemID] = true end
check(#b2Faction == 2 and b2FIds[56001] == true and b2FIds[56007] == true,
	"B2 (Faction): kept 56001 (78% <= 82%) & 56007; pruned qty=1 (56002), comm qty=2 (56003), unafford (56004), low liq (56005), low profit (56006)")

local b2Neutral = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000,
	minQty = 2, maxBuyShareDailyPct = 50, isNeutral = true,
})
check(#b2Neutral == 1 and b2Neutral[1].itemID == 56007,
	"B2 (Neutral 15% cut): tightened 73% ceiling also pruned 78%-of-ref item 56001, leaving only 56007")

-- 9b. B3: OnBrowseScanCancelled, EnsureBrowseRunning(already_active), StartSniperQueue added count, res.cancelled
local b3Calls = { ensure = 0, cancelBrowse = 0, cancelQueue = 0, onResult = nil }
local b3BrowseAlreadyRunning = true
ns.MarketScan = {
	GetState = function() return { active = b3BrowseAlreadyRunning } end,
	EnsureBrowseRunning = function()
		b3Calls.ensure = b3Calls.ensure + 1
		if b3BrowseAlreadyRunning then
			return true, "already_active"
		end
		b3BrowseAlreadyRunning = true
		return true
	end,
	CancelBrowseScan = function()
		b3Calls.cancelBrowse = b3Calls.cancelBrowse + 1
		b3BrowseAlreadyRunning = false
	end,
	StartSniperQueue = function(items, onResult)
		b3Calls.onResult = onResult
		-- Simulate deduplication returning added = 1 even though #items == 2
		return true, 1
	end,
	CancelSniperQueue = function()
		b3Calls.cancelQueue = b3Calls.cancelQueue + 1
	end,
}
SE.OnEvent("AUCTION_HOUSE_SHOW")
SE.scan.lastBrowseAt = nil
check(SE.StartGapScan({ econ = "Forever-EU", forceBrowse = true }) == true
	and SE.scan.awaitingBrowse == true and SE.scan.startedBrowse == false and b3Calls.ensure == 1,
	"B3: EnsureBrowseRunning() returning 'already_active' attached without setting startedBrowse=true")
SE.OnBrowseScanCancelled("Forever-EU", false)
check(SE.scan.active == false and SE.scan.phase == "idle" and SE.scan.awaitingBrowse == false
	and b3Calls.cancelBrowse == 0,
	"B3: OnBrowseScanCancelled cleanly stopped Stage 1 without deadlocking or re-cancelling browse")

-- StartSniperQueue added < #shortlist updates SE.scan.total = added so scan completes cleanly
b3BrowseAlreadyRunning = false
local okB3Drill = SE.StartGapScan({
	econ = "Forever-EU", skipBrowse = true, browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000,
	isNeutral = false, forceRedrill = true,
})
check(okB3Drill == true and SE.scan.total == 1,
	"B3: startGapDrillStage set SE.scan.total = added (1) from StartSniperQueue 2nd return value")
-- Cancel from MarketScan via res.cancelled == true stops cleanly without incrementing scanned
b3Calls.onResult({ cancelled = true, itemID = 56007 })
check(SE.scan.active == false and SE.scan.phase == "idle" and SE.scan.scanned == 0,
	"B3: res.cancelled == true cleanly stopped Stage 2 without incrementing scanned")

-- 9c. M2: Differential Browse Delta-Memoization (skip unchanged within 120s; redrill on change, >120s, or forceRedrill)
SE.ClearDrillCache()
local m2DrillStart = SE.StartGapScan({
	econ = "Forever-EU", skipBrowse = true, browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000,
	isNeutral = true,
})
check(m2DrillStart == true and SE.scan.active == true, "M2: Started Stage 2 drill on 56007")
-- Failed drill must NOT cache
b3Calls.onResult({ itemID = 56007, isCommodity = true, failed = true })
check(SE.drillCache[56007] == nil, "M2: Failed drill did NOT populate SE.drillCache")

-- Successful drill populates SE.drillCache[56007]
SE.StartGapScan({
	econ = "Forever-EU", skipBrowse = true, browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000,
	isNeutral = true,
})
b3Calls.onResult({
	itemID = 56007, isCommodity = true, whole = false, failed = false,
	rawRows = { { unitPrice = 50000, quantity = 10 }, { unitPrice = 51000, quantity = 10 } },
})
check(SE.drillCache[56007] ~= nil and SE.drillCache[56007].minPrice == 50000 and SE.drillCache[56007].totalQuantity == 20,
	"M2: Completed Stage 2 drill recorded (minPrice, totalQuantity, drilledAt) in SE.drillCache")

mockNow = mockNow + 60 -- 60s < 120s TTL
local m2Skipped = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000, isNeutral = true,
})
check(#m2Skipped == 0, "M2: Unchanged (minPrice=50000, totalQuantity=20) skipped within 120s TTL")

local m2Forced = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000, isNeutral = true,
	forceRedrill = true,
})
check(#m2Forced == 1 and m2Forced[1].itemID == 56007, "M2: opts.forceRedrill=true overrides drillCache")

-- Price change breaks delta cache immediately
SE.browseCache[56007].minPrice = 49000
local m2PriceChanged = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000, isNeutral = true,
})
check(#m2PriceChanged == 1 and m2PriceChanged[1].itemID == 56007, "M2: Changed minPrice re-includes item immediately")

-- Restore price and verify TTL expiry after 120s
SE.browseCache[56007].minPrice = 50000
mockNow = mockNow + 65 -- 125s >= 120s TTL
local m2Expired = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = b2Start,
	minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, maxSpend = 500000, isNeutral = true,
})
check(#m2Expired == 1 and m2Expired[1].itemID == 56007, "M2: Expired drillCache (>= 120s) re-includes item")
ns.MarketScan = nil

-- 9d. B5 & M3: Skip RequestLoadItemDataByID > 50g, deferred vendor_deals notify, browseCache pruning, memoization & GetItemInfoInstant
SE.ClearVendorDeals()
local listenerEvents = {}
SE.SetListener(function(ev)
	listenerEvents[ev] = (listenerEvents[ev] or 0) + 1
end)
hideItemInfo[56099] = true -- uncached expensive item
requestedLoads[56099] = nil
local b5Flagged1 = SE.IngestBrowseBatch({
	{ itemID = 56099, minPrice = 600000, totalQuantity = 1, isCommodity = false }, -- 60g (> 50g) uncached -> NO load!
	{ itemID = 55001, minPrice = 30000,  totalQuantity = 1, isCommodity = false }, -- 3g vs 5g vendor -> flagged!
}, "Forever-EU")
local b5Flagged2 = SE.IngestBrowseBatch({
	{ itemID = 55002, minPrice = 40000, totalQuantity = 1, isCommodity = false }, -- 4g vs 8.5g vendor -> flagged!
}, "Forever-EU")
check(b5Flagged1 == 1 and b5Flagged2 == 1, "B5: IngestBrowseBatch flagged deals across 2 pages")
check(requestedLoads[56099] == nil and SE.unresolvedVendor[56099] == nil,
	"B5: Skipped RequestLoadItemDataByID and unresolvedVendor for >50g uncached item (56099)")
check((listenerEvents["vendor_deals"] or 0) == 0,
	"B5: Deferred notify('vendor_deals') during Browse pages (0 fires before OnBrowseScanComplete)")
SE.OnBrowseScanComplete("Forever-EU", false)
check((listenerEvents["vendor_deals"] or 0) == 1,
	"B5: Flushed sorted notify('vendor_deals') exactly ONCE on OnBrowseScanComplete")
check(SE.vendorDeals[1].itemID == 55002 and SE.vendorDeals[2].itemID == 55001,
	"B5: Flushed vendorDeals sorted descending by profitPerUnit (55002 +4.5g before 55001 +2g)")
SE.SetListener(nil)

-- M3: PruneBrowseCache clears active economy while preserving other economies
SE.browseCache["other_econ_item"] = { sig = "other_econ_item", itemID = 2447, minPrice = 500, totalQuantity = 5, economy = "Forever-US", updatedAt = mockNow }
SE.PruneBrowseCache("Forever-EU")
check(SE.browseCache[56007] == nil and SE.browseCache["other_econ_item"] ~= nil,
	"M3: PruneBrowseCache cleared active economy ('Forever-EU') while preserving other economies ('Forever-US')")
SE.browseCache["other_econ_item"] = nil

-- M3: Demand memoization across multiple itemKey variants + pure-Lua filter skips GetItemKeyInfo on pruned items
local m3Start = mockNow + 10
mockNow = m3Start
local kVar1 = { itemID = 55001, itemLevel = 60, itemSuffix = 100, battlePetSpeciesID = 0 }
local kVar2 = { itemID = 55001, itemLevel = 60, itemSuffix = 200, battlePetSpeciesID = 0 }
mockDemand[56010] = { dailySold = 0, effectiveDailySold = 0 } -- fails pure-Lua demand gate!
SE.IngestBrowseBatch({
	{ itemID = 55001, itemKey = kVar1, minPrice = 200000, totalQuantity = 3, quality = 2 }, -- no isCommodity -> uses GetItemInfoInstant!
	{ itemID = 55001, itemKey = kVar2, minPrice = 250000, totalQuantity = 3, quality = 2 },
	{ itemID = 56010, minPrice = 100,   totalQuantity = 10, quality = 1 }, -- fails demand=0 BEFORE GetItemKeyInfo/GetItemInfo!
}, "Forever-EU")
apiCounts.demand = 0
apiCounts.getItemKeyInfo = 0
apiCounts.getItemInfoInstant = 0
local m3List = SE.BuildGapShortlist({
	econ = "Forever-EU", browseOnly = true, minUpdatedAt = m3Start, minDailySales = 1,
})
check(#m3List == 2, "M3: Both 55001 variants shortlisted and 0-demand 56010 pruned")
check(apiCounts.demand == 2,
	"M3: GetItemDemand memoized by itemID (2 calls for 2 unique IDs across 3 rows; got " .. apiCounts.demand .. ")")
check(apiCounts.getItemInfoInstant >= 2 and apiCounts.getItemKeyInfo == 0,
	"M3: GetItemInfoInstant classified 55001 and pure-Lua demand gate skipped GetItemKeyInfo completely (calls=" .. apiCounts.getItemKeyInfo .. ")")

-- 9e. B6: Real CartBuyer.GetState().pendingExternal guard on ConfirmCommodityBuy & COMMODITY_PURCHASE_SUCCEEDED
ahCalls = {}
deal.status = "ready"
mockCartBuyerPendingExternal = nil
mockCartBuyerActive = false
check(SE.HandleRowAction(deal) == true, "B6: Started commodity quote")
SE.OnEvent("COMMODITY_PRICE_UPDATED", 10500, 210000)
mockCartBuyerPendingExternal = { itemID = 9999, qty = 1 }
local b6ConfirmOk, b6ConfirmErr = SE.HandleRowAction(deal)
check(b6ConfirmOk == false and b6ConfirmErr == "cart_buyer_busy",
	"B6: ConfirmCommodityBuy blocked when CartBuyer.pendingExternal ~= nil")
mockCartBuyerPendingExternal = nil
check(SE.HandleRowAction(deal) == true and SE.GetPurchaseState().state == "confirming", "B6: Confirmed after pendingExternal cleared")
-- While confirming, if CartBuyer sets pendingExternal, COMMODITY_PURCHASE_SUCCEEDED must not be stolen
mockCartBuyerPendingExternal = { itemID = 9999, qty = 1 }
SE.OnEvent("COMMODITY_PURCHASE_SUCCEEDED")
check(SE.GetPurchaseState() ~= nil and SE.GetPurchaseState().state == "confirming",
	"B6: COMMODITY_PURCHASE_SUCCEEDED ignored while CartBuyer.pendingExternal is active")
mockCartBuyerPendingExternal = nil
SE.OnEvent("COMMODITY_PURCHASE_SUCCEEDED")
check(SE.GetPurchaseState() == nil and deal.status == "bought", "B6: Purchase completed cleanly once pendingExternal cleared")

-- 9f. B7: Negative Classic itemSuffix vendor keys + cacheKey unresolvedVendor + stacked non-commodity vendor + <2/day snapshot equipment
SE.ClearVendorDeals()
local negSufKeyA = { itemID = 55003, itemLevel = 45, itemSuffix = -18, battlePetSpeciesID = 0 }
local negSufKeyB = { itemID = 55003, itemLevel = 45, itemSuffix = -40, battlePetSpeciesID = 0 }
hideItemInfo[55003] = true
SE.IngestBrowseBatch({
	{ itemID = 55003, itemKey = negSufKeyA, minPrice = 10000, totalQuantity = 1, isCommodity = false },
	{ itemID = 55003, itemKey = negSufKeyB, minPrice = 12000, totalQuantity = 1, isCommodity = false },
}, "Forever-EU")
check(SE.unresolvedVendor["55003:45:-18:0"] ~= nil and SE.unresolvedVendor["55003:45:-40:0"] ~= nil,
	"B7: Negative Classic itemSuffix variants stored separately in SE.unresolvedVendor by cacheKey")
hideItemInfo[55003] = nil
SE.OnEvent("GET_ITEM_INFO_RECEIVED", 55003, true)
check(SE.vendorDealsByKey["vendor:55003:45:-18:0"] ~= nil and SE.vendorDealsByKey["vendor:55003:45:-40:0"] ~= nil,
	"B7: Negative Classic itemSuffix vendor deals got distinct keys and both resolved on GET_ITEM_INFO_RECEIVED")
check(SE.unresolvedVendor["55003:45:-18:0"] == nil and SE.unresolvedVendor["55003:45:-40:0"] == nil,
	"B7: Resolved negative-suffix unresolvedVendor entries cleaned up")

-- Stacked non-commodity vendor listing (qty=5, buyout=5000c, vendorSell=2000c -> 10000c vendor > 5000c buyout = +5000c profit!)
mockItemInfo[56020] = { "Stacked NonComm Scrolls", "|cffffffff|Hitem:56020|h[Stacked NonComm Scrolls]|h|r", 1, 2000, 5 }
mockItemInfo[mockItemInfo[56020][2]] = mockItemInfo[56020]
local stackVendorDeal = {
	idKey = "vendor:56020",
	kind = "item",
	mode = "vendor",
	itemID = 56020,
	itemName = "Stacked NonComm Scrolls",
	isCommodity = false,
	vendorSell = 2000,
	status = "unverified",
}
mockItemSearchResults[56020] = {
	{ auctionID = 8801, buyoutAmount = 5000, quantity = 5, itemLink = mockItemInfo[56020][2] },
}
check(SE.HandleVendorAction(stackVendorDeal) == true and stackVendorDeal.status == "checking",
	"B7: Started live check on stacked non-commodity vendor deal")
SE.OnEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 56020 })
check(stackVendorDeal.status == "ready_to_buy" and stackVendorDeal.quantity == 5 and stackVendorDeal.buyQty == 5
	and stackVendorDeal.totalCost == 5000 and stackVendorDeal.totalProfit == 5000 and stackVendorDeal.profitPerUnit == 1000,
	"B7: applyVendorItemRows supported stacked non-commodity listing (5x @ 20s vendor vs 50s stack buyout = +50s total, +10s/unit)")
ahCalls = {}
check(SE.HandleVendorAction(stackVendorDeal) == true and ahCalls[1] and ahCalls[1].fn == "PlaceBid"
	and ahCalls[1].auctionID == 8801 and ahCalls[1].amount == 5000,
	"B7: ExecuteVendorBuy accepted stacked non-commodity vendor deal (buyout 5000 < vendorSell*qty 10000)")
SE.OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 8801)
check(stackVendorDeal.status == "bought", "B7: Stacked non-commodity vendor purchase completed cleanly")

-- < 2/day snapshot equipment in ScanSnapshotForGapDeals
mockItemInfo[56030] = { "Slow Rare Snapshot BoE", "|cff0070dd|Hitem:56030|h[Slow Rare Snapshot BoE]|h|r", 3, 20000, 1 }
mockItemInstant[56030] = { "INVTYPE_CHEST", 4 }
snapshotRawItems[56030] = { minBuyout = 100000, marketValue = 300000, historical = 290000, qty = 3 }
mockDemand[56030] = { dailySold = 1, effectiveDailySold = 1, demandSource = "TSM", confidence = 2 } -- <2/day: floor(1*0.5)=0 for comm, 1 for equipment!
mockRegSale[56030] = { regionSale = 300000, soldPerDay = 1, saleRate = 0.2 }
mockDepth[56030] = {
	{ price = 100000, qty = 1 },
	{ price = 280000, qty = 2 },
}
SE.ClearGapDeals()
SE.ScanSnapshotForGapDeals("Forever-EU", { gapScope = "items", minDailySales = 1, maxBuyShareDailyPct = 50, minProfitCopper = 10000 })
check(SE.gapDealsByKey["gap:56030"] ~= nil and SE.gapDealsByKey["gap:56030"].kind == "item"
	and SE.gapDealsByKey["gap:56030"].buyQty == 1,
	"B7: ScanSnapshotForGapDeals kept <2/day snapshot equipment (dailySold=1 at 50% -> 1 unit allowed)")
snapshotRawItems[56030] = nil
mockDepth[56030] = nil

-- 9g. M4: abortPurchase calls CancelCommoditiesPurchase during confirming + StartItemGapBuy 15s watchdog pops dead buyQueue[1]
ahCalls = {}
deal.status = "ready"
check(SE.HandleRowAction(deal) == true, "M4: Started commodity buy for confirming failure test")
SE.OnEvent("COMMODITY_PRICE_UPDATED", 10500, 210000)
check(SE.HandleRowAction(deal) == true and SE.GetPurchaseState().state == "confirming", "M4: Entered confirming state")
SE.OnEvent("COMMODITY_PURCHASE_FAILED")
check(SE.GetPurchaseState() == nil and ahCalls[3] and ahCalls[3].fn == "CancelCommoditiesPurchase",
	"M4: COMMODITY_PURCHASE_FAILED during confirming called CancelCommoditiesPurchase()")

-- StartItemGapBuy 15s watchdog: pops dead buyQueue[1] so next click tries lot #2, then marks needsLiveScan when queue empties
local m4EquipDeal = SE.EvaluateItemGap(55010, {
	{ auctionID = 9901, buyoutAmount = 2000000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	{ auctionID = 9902, buyoutAmount = 2200000, quantity = 1, itemLink = mockItemInfo[55010][2] },
	{ auctionID = 9903, buyoutAmount = 4500000, quantity = 1, itemLink = mockItemInfo[55010][2] },
}, { refPrice = 5000000, dailySold = 6, maxSpend = 10000000, minProfitCopper = 100000 })
check(m4EquipDeal ~= nil and #m4EquipDeal.buyQueue == 2, "M4: Built 2-lot equipment deal [9901, 9902]")
ahCalls = {}
check(SE.HandleRowAction(m4EquipDeal) == true and ahCalls[1].auctionID == 9901, "M4: Placed bid on lot #1 (9901)")
flushTimers(16) -- 9901 sniped -> watchdog pops 9901!
check(SE.GetPurchaseState() == nil and m4EquipDeal.status == "ready"
	and m4EquipDeal.buyQueue ~= nil and #m4EquipDeal.buyQueue == 1
	and m4EquipDeal.buyQueue[1].auctionID == 9902 and m4EquipDeal.totalCost == 2200000,
	"M4: 15s watchdog popped dead sniped 9901 and advanced buyQueue[1] to 9902 with recalculated economics")
check(SE.HandleRowAction(m4EquipDeal) == true and ahCalls[2] and ahCalls[2].fn == "PlaceBid" and ahCalls[2].auctionID == 9902,
	"M4: Next click immediately tried lot #2 (9902) instead of retrying dead 9901")
flushTimers(16) -- 9902 also sniped -> queue empty -> needsLiveScan = true!
check(SE.GetPurchaseState() == nil and m4EquipDeal.status == "ready"
	and m4EquipDeal.buyQueue == nil and m4EquipDeal.needsLiveScan == true,
	"M4: 15s watchdog on last lot cleared buyQueue and set needsLiveScan=true, status='ready' for live re-check")

-- 9h. Fresh scan clearing & Snapshot/Live deduplication (no stale/duplicate rows across repeated scans)
SE.ClearGapDeals()
SE.ClearVendorDeals()
-- Seed stale gap deal + stale Snapshot base deal for 55001
SE.gapDeals[1] = { idKey = "gap:999999", itemID = 999999, netProfit = 50000, roiPct = 50, source = "Live" }
SE.gapDealsByKey["gap:999999"] = SE.gapDeals[1]
SE.ScanSnapshotForGapDeals("Forever-EU", { minProfitCopper = 10000 })
check(SE.gapDealsByKey["gap:999999"] == nil, "ScanSnapshotForGapDeals clears stale deals from prior scan")

-- Seed stale vendor deal, verify fresh ScanSnapshotForVendorDeals replaces list cleanly
SE.vendorDeals[1] = { idKey = "vendor:999998", itemID = 999998, profitPerUnit = 99999, totalProfit = 99999, source = "Browse" }
SE.vendorDealsByKey["vendor:999998"] = SE.vendorDeals[1]
SE.ScanSnapshotForVendorDeals("Forever-EU", { minProfitCopper = 1000 })
check(SE.vendorDealsByKey["vendor:999998"] == nil and SE.vendorDealsByKey["vendor:55002"] ~= nil,
	"ScanSnapshotForVendorDeals clears stale deals and keeps only fresh matches")

-- Verify repeated ScanSnapshotForGapDeals produces zero duplicates
local countFirst = #SE.ScanSnapshotForGapDeals("Forever-EU", { minProfitCopper = 10000 })
local countSecond = #SE.ScanSnapshotForGapDeals("Forever-EU", { minProfitCopper = 10000 })
check(countFirst == countSecond, "Repeated ScanSnapshotForGapDeals produces identical count (zero duplicates)")

check(ledgerAppendCalls == 0, "Analytics.Store.Append still called 0 times across all regression & All-Items paths")

print("PASS: test_sniper (" .. assertions .. " assertions)")
