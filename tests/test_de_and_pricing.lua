local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames, hostEnv = dofile(S .. "host_fixture.lua")
local app = ns.app
local db = MerchantMasterDB
local MP = ns.MP

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

-- Helper to stub C_Item.GetItemInfo & market prices cleanly
local origCItem = _G.C_Item
local origGetItemInfo = _G.GetItemInfo
local origGetItemMarketPrice = ns.GetItemMarketPrice
local origGetFallbackMarketPrice = ns.GetFallbackMarketPrice

local stubItems = {
	-- Uncommon ilvl 12 armor (Strange Dust 80% 1-2, Lesser Magic Essence 20% 1-2)
	[90001] = { "Green Chest", nil, 2, 12, 7, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 100, 4, 1 },
	-- Uncommon ilvl 12 weapon (Strange Dust 20% 1-2, Lesser Magic Essence 80% 1-2)
	[90002] = { "Green Sword", nil, 2, 12, 7, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 1, 120, 2, 7 },
	-- Rare ilvl 58 armor (Large Brilliant Shard 99.5%, Nexus Crystal 0.5%)
	[90003] = { "Blue Helm", nil, 3, 58, 53, "Armor", "Plate", 1, "INVTYPE_HEAD", 1, 500, 4, 4 },
	-- Epic ilvl 62 weapon (Nexus Crystal 100% 1-2)
	[90004] = { "Epic Staff", nil, 4, 62, 60, "Weapon", "Staff", 1, "INVTYPE_2HWEAPON", 1, 1000, 2, 10 },
	-- Fishing Pole (classID 2, subclassID 20) -> MUST be rejected
	[90005] = { "Green Pole", nil, 2, 20, 15, "Weapon", "Fishing Poles", 1, "INVTYPE_2HWEAPON", 1, 100, 2, 20 },
	-- Thrown weapon (classID 2, subclassID 16) -> MUST be rejected
	[90006] = { "Green Knife", nil, 2, 20, 15, "Weapon", "Thrown", 1, "INVTYPE_THROWN", 1, 100, 2, 16 },
	-- Trinket (INVTYPE_TRINKET) -> MUST be rejected
	[90007] = { "Green Trinket", nil, 2, 25, 20, "Armor", "Misc", 1, "INVTYPE_TRINKET", 1, 100, 4, 0 },
	-- Shirt (INVTYPE_BODY) -> MUST be rejected
	[90008] = { "Green Shirt", nil, 2, 20, 1, "Armor", "Cloth", 1, "INVTYPE_BODY", 1, 10, 4, 1 },
	-- Consumable (classID 0) -> MUST be rejected
	[90009] = { "Green Potion", nil, 2, 20, 15, "Consumable", "Potion", 5, "", 1, 20, 0, 1 },
	-- Common armor (quality 1) -> MUST be rejected
	[90010] = { "White Chest", nil, 1, 12, 7, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 50, 4, 1 },
-- Uncommon ilvl 24 weapon -> tests Classic/Forever Astral Essence bracket fix (10998, not 10939)
	[90011] = { "Astral Sword", nil, 2, 24, 19, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 1, 200, 2, 7 },
	-- Blacklisted NonDisenchantable item (Worn Shortbow / Shirt id 38 -> Recruit's Shirt)
	[38] = { "Recruit's Shirt", nil, 2, 20, 15, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 1, 4, 1 },
}

_G.C_Item = {
	GetItemInfo = function(arg)
		local id = type(arg) == "number" and arg or (type(arg) == "string" and tonumber(arg:match("item:(%d+)")))
		local row = id and stubItems[id]
		if row then return unpack(row) end
		if origCItem and origCItem.GetItemInfo then return origCItem.GetItemInfo(arg) end
		return nil
	end,
	GetDetailedItemLevelInfo = function(link)
		if type(link) == "string" and link:find("90001:scaled", 1, true) then return 58 end
		return nil
	end,
}

local matPrices = {
	[10940] = 100,   -- Strange Dust = 1s
	[10938] = 500,   -- Lesser Magic Essence = 5s
	[10998] = 900,   -- Lesser Astral Essence = 9s
	[14344] = 40000, -- Large Brilliant Shard = 4g
	[20725] = 100000,-- Nexus Crystal = 10g
	[16204] = 5000,  -- Illusion Dust = 50s
	[16203] = 20000, -- Greater Eternal Essence = 2g
}
ns.GetItemMarketPrice = function(id)
	if matPrices[id] == false then return nil end
	if matPrices[id] ~= nil then
		return matPrices[id], "Live AH"
	end
	return origGetItemMarketPrice(id)
end
ns.GetFallbackMarketPrice = function(id)
	if matPrices[id] == false then return nil end
	if id == 20725 then return 100000, "Fallback" end
	return origGetFallbackMarketPrice(id)
end

ns.InvalidatePriceCache()

-- 1. DE profile eligibility & exclusions
local matsA, errA = ns.GetItemDEProfile(90001)
check(matsA ~= nil and errA == nil, "Uncommon armor ilvl 12 should resolve DE profile")
local matsW, errW = ns.GetItemDEProfile(90002)
check(matsW ~= nil and errW == nil, "Uncommon weapon ilvl 12 should resolve DE profile")
check(ns.GetItemDEProfile(90005) == nil, "Fishing pole must be ineligible for DE")
check(ns.GetItemDEProfile(90006) == nil, "Thrown weapon must be ineligible for DE")
check(ns.GetItemDEProfile(90007) == nil, "Trinket must be ineligible for DE")
check(ns.GetItemDEProfile(90008) == nil, "Shirt must be ineligible for DE")
check(ns.GetItemDEProfile(90009) == nil, "Consumable must be ineligible for DE")
check(ns.GetItemDEProfile(90010) == nil, "Common quality armor must be ineligible for DE")
local _, errUncached = ns.GetItemDEProfile(999999)
check(errUncached == "uncached", "Uncached item must return uncached and not be negative-cached")

-- 2. DE EV math & applyAHCut
-- Armor ilvl 12: 0.80 * 1.5 * 100 + 0.20 * 1.5 * 500 = 120 + 150 = 270 gross; 257 net (95%)
local netA, grossA = ns.GetItemDEValue(90001, nil, true)
check(grossA == 270, "Armor ilvl 12 DE gross should be 270, got " .. tostring(grossA))
check(netA == 257, "Armor ilvl 12 DE net (95%) should be 257, got " .. tostring(netA))
local netANoCut = ns.GetItemDEValue(90001, nil, false)
check(netANoCut == 270, "Armor ilvl 12 DE net (no cut) should be 270, got " .. tostring(netANoCut))

-- Weapon ilvl 12: 0.20 * 1.5 * 100 + 0.80 * 1.5 * 500 = 30 + 600 = 630 gross
local netW, grossW = ns.GetItemDEValue(90002, nil, true)
check(grossW == 630, "Weapon ilvl 12 DE gross should be 630, got " .. tostring(grossW))
check(netW == 599, "Weapon ilvl 12 DE net should be 599, got " .. tostring(netW))

-- Detailed ilvl override via itemLink (90001:scaled -> ilvl 58 armor)
local netScaled, grossScaled = ns.GetItemDEValue(90001, "|Hitem:90001:scaled|h[Scaled]|h", true)
check(grossScaled and grossScaled > grossA, "Scaled ilvl 58 link should produce higher DE gross than ilvl 12")

-- Fallback price cushioning: remove direct price for Nexus Crystal (20725), keep fallback
matPrices[20725] = nil
ns.InvalidatePriceCache()
local netRare, grossRare = ns.GetItemDEValue(90003, nil, true)
check(grossRare ~= nil and grossRare > 39000, "Rare ilvl 58 DE should use fallback for unlisted 0.5% Nexus Crystal")
matPrices[20725] = 100000
ns.InvalidatePriceCache()

-- 3. Professor 3-way recovery (Vendor vs AH vs DE) & BoP guard
local evTest = {
	rec = { i = 90002, ench = false, bop = false },
	vendorUnit = 120,
	deNetUnit = 599,
	canAH = true,
	isUnlisted = true,
	isCustomPrice = false,
	ahGrossUnit = nil,
	ahNetUnit = 0,
	hotnessCap = 0,
}
local totOff, ahOff, vendOff, tagOff = MP.ComputeOutputsResale(evTest, 5, { includeVendorSell = true, useDisenchantRecovery = false, goalMode = "smart" }, 0)
check(totOff == 600 and tagOff == "Vendor (Unlisted)", "DE off should fall back to Vendor (Unlisted): got " .. tostring(totOff) .. " " .. tostring(tagOff))

local totOn, ahOn, vendOn, tagOn = MP.ComputeOutputsResale(evTest, 5, { includeVendorSell = true, useDisenchantRecovery = true, goalMode = "smart" }, 0)
check(totOn == 2995 and tagOn == "DE (est.)", "DE on should pick DE (est.) when 599 > 120: got " .. tostring(totOn) .. " " .. tostring(tagOn))

-- Overflow split: AH cap 2 out of 5, remaining 3 go to DE
evTest.isUnlisted = false
evTest.ahGrossUnit = 1000
evTest.ahNetUnit = 900
evTest.hotnessCap = 2
local totSplit, ahSplit, flSplit, tagSplit = MP.ComputeOutputsResale(evTest, 5, { includeVendorSell = true, useDisenchantRecovery = true, goalMode = "smart" }, 0)
check(totSplit == (2 * 900 + 3 * 599) and ahSplit == 2 and flSplit == 3 and tagSplit == "AH 2 + DE 3",
	"Hotness cap overflow should route remainder to DE: got " .. tostring(totSplit) .. " " .. tostring(tagSplit))

-- 4. Bartering single-owner discount & liveVendorBuyGlobal normalization (zero double-discounting)
db.liveVendorBuy = {}
db.liveVendorBuyGlobal = {}
local testReag = 2320 -- Coarse Thread (static vendor reagent)
local staticBase = ns.VENDOR_REAGENTS[testReag]
check(type(staticBase) == "number" and staticBase > 0, "Coarse Thread must be in VENDOR_REAGENTS")
local p0, live0 = ns.GetVendorBuyPrice(testReag, staticBase, false, 0)
local p2, live2 = ns.GetVendorBuyPrice(testReag, staticBase, false, 2)
check(live0 == false and live2 == false, "Static reagent must report isLiveObserved=false")
check(p0 == staticBase, "Bartering 0 must return full static price")
check(p2 == math.max(1, math.floor(staticBase * 0.90 + 0.5)), "Bartering 2 must apply 10% discount once")

-- Global cache normalization: Character A observes 81c at Bartering 2 + Honored (0.90 * 0.90 = 0.81 -> base 100c)
-- Character B (Bartering 0) must NOT inherit 81c; should receive normalized 100c!
db.liveVendorBuy["OtherChar-Forever"] = { [99123] = { price = 81, limited = false, bartering = 2, repDisc = true } }
db.liveVendorBuyGlobal[99123] = { basePrice = 100, limited = false }
local altB0 = ns.GetVendorBuyPrice(99123, nil, false, 0)
local altB2 = ns.GetVendorBuyPrice(99123, nil, false, 2)
check(altB0 == 100, "Bartering 0 alt should get undiscounted base 100 from liveVendorBuyGlobal, got " .. tostring(altB0))
check(altB2 == 90, "Bartering 2 alt should get 90 from liveVendorBuyGlobal, got " .. tostring(altB2))

-- Character cache invalidation when bartering rank changes
local myKey = (ns.app and ns.app.charKey) or "TestChar-Forever"
db.liveVendorBuy[myKey] = { [99124] = { price = 100, limited = false, bartering = 0, repDisc = false } }
db.liveVendorBuyGlobal[99124] = { basePrice = 100, limited = false }
local sameRank = ns.GetVendorBuyPrice(99124, nil, false, 0)
local newRank = ns.GetVendorBuyPrice(99124, nil, false, 2)
check(sameRank == 100, "Matching bartering rank uses char cache")
check(newRank == 90, "Changed bartering rank ignores stale char entry and applies new rank to basePrice, got " .. tostring(newRank))

-- 5. Tooltip defaults ON for DE Value & DE Breakdown, Craft Cost OFF, blacklist & dedup checks
check(ns.IsTooltipCraftCostEnabled() == false, "tooltipCraftCost must default false")
check(ns.IsTooltipDEValueEnabled() == true, "tooltipDEValue must default true")
check(ns.IsTooltipDEBreakdownEnabled() == true, "tooltipDEBreakdown must default true")

-- Check NonDisenchantable blacklist & Astral Essence fix & Epic ilvl 62 Forever empirical amount (1.666)
local ok38, err38 = ns.IsItemDisenchantable(38)
check(not ok38 and err38 == "blacklisted", "NonDisenchantable item 38 must be rejected as blacklisted")
local bdAstral = ns.GetItemDEBreakdown(90011, nil, true)
check(bdAstral and #bdAstral.outcomes == 3 and bdAstral.outcomes[1].matID == 10998,
	"Uncommon ilvl 24 weapon must yield Lesser Astral Essence (10998) as primary outcome")
local bdEpic = ns.GetItemDEBreakdown(90004, nil, false)
check(bdEpic and bdEpic.grossCopper == 166600 and bdEpic.asGrossCopper == math.floor(166600 * 1.20 + 0.5)
	and bdEpic.minGrossCopper == 100000 and bdEpic.maxGrossCopper == 200000,
	"Epic ilvl 62 weapon must use Forever 1.666 empirical amount and +20% AS bonus")

-- Partial / unpriced outcome mats still return outcome breakdown instead of hiding tooltips
local origDust = matPrices[10940]
local origEss = matPrices[10938]
matPrices[10940] = false
ns.InvalidatePriceCache()
local bdPartial = ns.GetItemDEBreakdown(90002, nil, true)
check(bdPartial and bdPartial.missingPriceCount == 1 and #bdPartial.outcomes == 2 and (bdPartial.netCopper or 0) > 0,
	"Missing price on 1 of 2 DE mats must still return partial DE breakdown")
matPrices[10938] = false
ns.InvalidatePriceCache()
local bdZeroPriced = ns.GetItemDEBreakdown(90002, nil, true)
check(bdZeroPriced and bdZeroPriced.missingPriceCount == 2 and #bdZeroPriced.outcomes == 2 and bdZeroPriced.netCopper == nil,
	"All-unpriced DE mats must still return breakdown outcomes with netCopper == nil")
local valNil, _, valErr = ns.GetItemDEValue(90002, nil, true)
check(valNil == nil and valErr == "missing_price", "GetItemDEValue still returns nil + 'missing_price' when all mats unpriced")
matPrices[10940] = origDust
matPrices[10938] = origEss
ns.InvalidatePriceCache()

local fakeTipLines = {}
local fakeTip = {
	GetItem = function() return "Green Sword", "|Hitem:90002|h[Green Sword]|h" end,
	AddDoubleLine = function(_, l, r) fakeTipLines[#fakeTipLines + 1] = { l, r } end,
	NumLines = function() return #fakeTipLines end,
}
check(ns.AppendEconTooltip(fakeTip) == true and #fakeTipLines == 4,
	"Default-enabled DE tooltip with AS + breakdown must add 4 lines, got " .. tostring(#fakeTipLines))
check(fakeTipLines[1][1] == "DE Value (est.)", "DE tooltip label must match 'DE Value (est.)'")
check(fakeTipLines[2][1] == "DE Value (AS +20%)", "DE tooltip must include 'DE Value (AS +20%)' line")
check(fakeTipLines[3][1]:find("80%%", 1, false) ~= nil and fakeTipLines[4][1]:find("20%%", 1, false) ~= nil,
	"DE breakdown lines must include 80% and 20% outcome chances")
-- Dedup check: calling again on same tooltip without clear must not duplicate
check(ns.AppendEconTooltip(fakeTip) == false and #fakeTipLines == 4, "Duplicate call on same tooltip must not add extra lines")

-- GetTooltipData fallback (when GetItem() is nil, e.g., Retail/Classic TooltipDataProcessor / ShoppingTooltip)
local dataTipLines = {}
local dataTip = {
	GetItem = function() return nil end,
	GetTooltipData = function() return { itemID = 90002 } end,
	AddDoubleLine = function(_, l, r) dataTipLines[#dataTipLines + 1] = { l, r } end,
	NumLines = function() return #dataTipLines end,
}
check(ns.AppendEconTooltip(dataTip) == true and #dataTipLines == 4,
	"GetTooltipData itemID fallback must append DE Value + AS + breakdown lines")

-- One-time SavedVariables migration flips previously saved tooltipDEValue = false to true
MerchantMasterDB.tooltipDEValue = false
MerchantMasterDB.tooltipDEBreakdown = false
MerchantMasterDB.tooltipDEDefaultMigrated = nil
if hostEnv and hostEnv.eventFrame and hostEnv.eventFrame.GetScript then
	local onEv = hostEnv.eventFrame:GetScript("OnEvent")
	if onEv then onEv(hostEnv.eventFrame, "ADDON_LOADED", "MerchantMaster") end
end
check(MerchantMasterDB.tooltipDEValue == true and MerchantMasterDB.tooltipDEBreakdown == true and MerchantMasterDB.tooltipDEDefaultMigrated == true,
	"ADDON_LOADED one-time migration must enable DE tooltips on existing profiles")

-- Turning off DE breakdown only shows header + AS lines
app.setTooltipDEBreakdown(false)
fakeTipLines = {}
fakeTip._mmLastItem = nil
check(ns.AppendEconTooltip(fakeTip) == true and #fakeTipLines == 2,
	"DE tooltip with breakdown disabled must add 2 summary lines (est. + AS), got " .. tostring(#fakeTipLines))

-- Turning off DE value adds 0 lines
app.setTooltipDEValue(false)
fakeTipLines = {}
fakeTip._mmLastItem = nil
check(ns.AppendEconTooltip(fakeTip) == false and #fakeTipLines == 0, "Disabled DE tooltip toggle must add 0 lines")

-- Re-enable and verify ineligible / blacklisted item adds 0 lines
app.setTooltipDEValue(true)
app.setTooltipDEBreakdown(true)
local blockedLines = {}
local blockedTip = {
	GetItem = function() return "Recruit's Shirt", "|Hitem:38|h[Recruit's Shirt]|h" end,
	AddDoubleLine = function(_, l, r) blockedLines[#blockedLines + 1] = { l, r } end,
	NumLines = function() return #blockedLines end,
}
check(ns.AppendEconTooltip(blockedTip) == false and #blockedLines == 0,
	"Blacklisted non-disenchantable item must add 0 tooltip lines")

-- 6. Classic/Forever eligibility parity: Off-hand (INVTYPE_HOLDABLE) allowed, Cosmetic excluded, Forever wands blacklisted
stubItems[90012] = { "Green Orb", nil, 2, 20, 15, "Armor", "Misc", 1, "INVTYPE_HOLDABLE", 1, 100, 4, 0 }
stubItems[90013] = { "Cosmetic Hat", nil, 2, 20, 1, "Armor", "Cosmetic", 1, "INVTYPE_HEAD", 1, 10, 4, 5 }
local okOH, errOH, metaOH = ns.IsItemDisenchantable(90012)
check(okOH == true and errOH == nil and metaOH and metaOH.equipLoc == "INVTYPE_HOLDABLE",
	"Held-in-Off-Hand (INVTYPE_HOLDABLE) uncommon item must be disenchantable")
local okCos, errCos = ns.IsItemDisenchantable(90013)
check(okCos == false and errCos == "ineligible", "Cosmetic armor (class 4, subclass 5) must be ineligible")
local okFwWand, errFwWand = ns.IsItemDisenchantable(249385) -- Brilliant Wand (Forever DB2 NO_DISENCHANT)
check(okFwWand == false and errFwWand == "blacklisted", "WoW Forever crafted Brilliant Wand (249385) must be blacklisted")
local okLowRareWep, errLowRareWep = ns.GetItemDEProfile(90014)
check(okLowRareWep == nil and errLowRareWep == "uncached", "Unknown synthetic 90014 uncached before stub")
stubItems[90014] = { "Low Blue Dagger", nil, 3, 12, 7, "Weapon", "Dagger", 1, "INVTYPE_WEAPON", 1, 200, 2, 15 }
local matsLowRareWep, errLowRareWep2 = ns.GetItemDEProfile(90014)
check(matsLowRareWep ~= nil and errLowRareWep2 == nil and #matsLowRareWep == 2,
	"Rare weapon ilvl 5-15 must resolve symmetric 2-mat DE profile")

-- 7. Static DE_ITEM_META & persistent deItemMetaCache fallback (with itemLink ilvl override)
check(type(ns.DE_ITEM_META) == "table" and ns.DE_ITEM_META[2300] ~= nil,
	"Static ns.DE_ITEM_META catalog must be loaded with Embossed Leather Vest (2300)")
local okStatic, errStatic, metaStatic = ns.IsItemDisenchantable(2300)
check(okStatic == true and errStatic == nil and metaStatic and metaStatic.metaSource == "static"
	and metaStatic.ilvl == 12 and metaStatic.classID == 4 and metaStatic.quality == 2,
	"Uncached craftable item 2300 must fall back to static ns.DE_ITEM_META")
-- Live lookup caches into MerchantMasterDB.deItemMetaCache, then fallback works when GetItemInfo returns nil
local liveCachedID = 90015
stubItems[liveCachedID] = { "Cached Belt", nil, 2, 14, 9, "Armor", "Leather", 1, "INVTYPE_WAIST", 1, 80, 4, 2 }
local okLiveC, _, metaLiveC = ns.IsItemDisenchantable(liveCachedID)
check(okLiveC == true and metaLiveC.metaSource == "live"
	and MerchantMasterDB.deItemMetaCache and MerchantMasterDB.deItemMetaCache[liveCachedID]
	and MerchantMasterDB.deItemMetaCache[liveCachedID].ilvl == 14,
	"Live GetItemInfo hit must populate MerchantMasterDB.deItemMetaCache")
stubItems[liveCachedID] = nil
local okFromCache, errFromCache, metaFromCache = ns.IsItemDisenchantable(liveCachedID)
check(okFromCache == true and errFromCache == nil and metaFromCache
	and metaFromCache.metaSource == "cache" and metaFromCache.ilvl == 14,
	"Uncached item previously seen must fall back to MerchantMasterDB.deItemMetaCache")

-- 8. Live Disenchant Learner: RecordDEObservation, GetDEObservationStats, AS normalization & Bayesian shrinkage
MerchantMasterDB.deObservations = nil
ns.ClearDECache()
local bdBase = ns.GetItemDEBreakdown(90001, nil, false)
check(bdBase and bdBase.learnedCasts == 0 and bdBase.learnedBlended == false
	and bdBase.grossCopper == 270 and bdBase.baselineNetCopper == 270,
	"0 casts must stay 100% equal to TSM/Wowhead baseline (270)")

-- Record 2 casts (< 3 threshold): stats tracked, but breakdown stays unblended baseline
local rec1Ok, rec1Bucket = ns.RecordDEObservation(90001, { { itemID = 10938, qty = 2 } }, { source = "helper" })
local rec2Ok = ns.RecordDEObservation(90001, { [10938] = 2 }, { source = "manual" })
check(rec1Ok == true and rec1Bucket == "4:2:12" and rec2Ok == true, "RecordDEObservation must accept array & map formats")
local st2 = ns.GetDEObservationStats(90001)
check(st2 and st2.casts == 2 and st2.asCasts == 0 and st2.bucketKey == "4:2:12"
	and st2.mats[10938] and st2.mats[10938].drops == 2 and st2.mats[10938].totalQty == 4,
	"GetDEObservationStats must report 2 recorded casts and mat totals")
local bd2 = ns.GetItemDEBreakdown(90001, nil, false)
check(bd2 and bd2.learnedCasts == 2 and bd2.learnedBlended == false and bd2.grossCopper == 270
	and bd2.baselineNetCopper == 270,
	"Below 3 casts must remain unblended baseline")

-- 3rd cast triggers Bayesian shrinkage: w = 3 / (3 + 10) = 3/13
-- Observed: 3 casts of 2x Lesser Magic Essence (10938 @ 500c) -> obsAmt(10938)=2.0, obsAmt(10940)=0
-- Blended gross = (10/13)*270 + (3/13)*(2.0*500) = (2700 + 3000)/13 = 438.46 -> 438
local rec3Ok = ns.RecordDEObservation(90001, { { itemID = 10938, qty = 1 }, { itemID = 10938, qty = 1 } }, { source = "helper" })
check(rec3Ok == true, "3rd cast with split stack must aggregate into single cast")
local st3 = ns.GetDEObservationStats(90001)
check(st3 and st3.casts == 3 and st3.mats[10938].drops == 3 and st3.mats[10938].totalQty == 6
	and st3.mats[10938].minQty == 2 and st3.mats[10938].maxQty == 2,
	"Split stack in one cast must count as 1 drop with qty 2")
local bd3 = ns.GetItemDEBreakdown(90001, nil, false)
check(bd3 and bd3.learnedCasts == 3 and bd3.learnedBlended == true
	and bd3.baselineNetCopper == 270 and bd3.grossCopper == 438,
	"3 casts must apply Bayesian shrinkage w=3/13 (expected 438, got " .. tostring(bd3 and bd3.grossCopper) .. ")")

-- Arcane Salvager (+20%) normalization: 10 AS casts yielding 2.4x Essence each (= 2.0 base) must match 2.0 avgQty
MerchantMasterDB.deObservations = nil
ns.ClearDECache()
for _ = 1, 10 do
	ns.RecordDEObservation(90001, { [10938] = 2.4 }, { arcaneSalvager = true, source = "helper" })
end
local stAS = ns.GetDEObservationStats(90001)
check(stAS and stAS.casts == 10 and stAS.asCasts == 10
	and math.abs(stAS.mats[10938].avgQty - 2.0) < 1e-6,
	"AS casts must normalize qty / 1.20 so baseline avgQty stays 2.0, got " .. tostring(stAS and stAS.mats[10938] and stAS.mats[10938].avgQty))
-- At 10 casts, w = 10/20 = 0.50 -> blended gross = 0.5*270 + 0.5*1000 = 635; AS gross = 635 * 1.20 = 762 (no double-count)
local bdAS = ns.GetItemDEBreakdown(90001, nil, false)
check(bdAS and bdAS.learnedBlended == true and bdAS.grossCopper == 635 and bdAS.asGrossCopper == 762
	and bdAS.baselineNetCopper == 270,
	"AS-normalized 10 casts must yield blended gross 635 and AS gross 762, got " .. tostring(bdAS and bdAS.grossCopper) .. "/" .. tostring(bdAS and bdAS.asGrossCopper))

-- Bucket sharing: item 2300 (static meta: Armor Q=2 ilvl=12, same 4:2:12 bucket) inherits bucket observations
local bdBucketShared = ns.GetItemDEBreakdown(2300, nil, false)
check(bdBucketShared and bdBucketShared.learnedCasts == 10 and bdBucketShared.learnedBlended == true
	and bdBucketShared.grossCopper == 635,
	"Items sharing c:q:ilvl bucket (4:2:12) must share learned bucket statistics")

-- Defensive sanitization against corrupt SavedVariables entries
MerchantMasterDB.deObservations = {
	byBucket = {
		["4:2:12"] = {
			casts = "corrupt",
			asCasts = 999,
			mats = { ["bad"] = "nope", [10940] = { drops = -5, totalQty = 0/0 } },
		},
	},
	byItem = { [90001] = "broken" },
}
ns.ClearDECache()
local stCorrupt = ns.GetDEObservationStats(90001)
local bdCorrupt = ns.GetItemDEBreakdown(90001, nil, false)
check(stCorrupt == nil and bdCorrupt and bdCorrupt.learnedCasts == 0 and bdCorrupt.grossCopper == 270,
	"Corrupt deObservations entries must be safely sanitized back to baseline")

-- 9. Pass 1 review fixes & helpers: base cache isolation, byItem vs byBucket precedence, normalized novel AS bounds, obsVersion & IsDisenchantMaterial
check(ns.IsDisenchantMaterial(10940) == true and ns.IsDisenchantMaterial(20725) == true
	and ns.IsDisenchantMaterial(2589) == false and ns.IsDisenchantMaterial(nil) == false,
	"IsDisenchantMaterial identifies the 24 DE mats and rejects non-DE items")

-- Finding 1: scaled itemLink ilvl must never pollute base deItemMetaCache[itemID]
MerchantMasterDB.deItemMetaCache = {}
stubItems[90016] = { "Scaled Chest", nil, 2, 14, 9, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 80, 4, 1 }
local origGetItemInfoFn = _G.C_Item.GetItemInfo
_G.C_Item.GetItemInfo = function(arg)
	if type(arg) == "string" and arg:find("90016:scaled", 1, true) then
		return "Scaled Chest", nil, 2, 58, 9, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 80, 4, 1
	end
	if type(arg) == "string" and arg:find("90017:scaled", 1, true) then
		return "Link Only Chest", nil, 2, 58, 9, "Armor", "Cloth", 1, "INVTYPE_CHEST", 1, 80, 4, 1
	end
	return origGetItemInfoFn(arg)
end
local ok90016, _, meta90016 = ns.IsItemDisenchantable(90016, "|Hitem:90016:scaled|h[Scaled Chest]|h")
check(ok90016 == true and MerchantMasterDB.deItemMetaCache[90016] and MerchantMasterDB.deItemMetaCache[90016].ilvl == 14,
	"deItemMetaCache stores base bare-itemID ilvl 14 rather than scaled link ilvl (got "
		.. tostring(MerchantMasterDB.deItemMetaCache[90016] and MerchantMasterDB.deItemMetaCache[90016].ilvl) .. ")")
local ok90017 = ns.IsItemDisenchantable(90017, "|Hitem:90017:scaled|h[Link Only Chest]|h")
check(ok90017 == true and MerchantMasterDB.deItemMetaCache[90017] == nil,
	"Link-only GetItemInfo hit without bare itemID must not populate base deItemMetaCache")
_G.C_Item.GetItemInfo = origGetItemInfoFn
stubItems[90016] = nil

-- Finding 2: larger/newer byItem entry must not be shadowed by a smaller byBucket entry
MerchantMasterDB.deObservations = nil
ns.ClearDECache()
local obsVBefore = ns.GetDEObservationVersion()
for _ = 1, 5 do
	ns.RecordDEObservation(90018, { [10938] = 1 }, { source = "manual" }) -- uncached -> byItem only (5 casts)
end
check(ns.GetDEObservationVersion() == obsVBefore + 5,
	"GetDEObservationVersion increments on each RecordDEObservation call")
stubItems[90018] = { "Late Cached Helm", nil, 2, 14, 9, "Armor", "Cloth", 1, "INVTYPE_HEAD", 1, 80, 4, 1 }
stubItems[90019] = { "Sibling Helm", nil, 2, 14, 9, "Armor", "Cloth", 1, "INVTYPE_HEAD", 1, 80, 4, 1 }
ns.RecordDEObservation(90019, { [10940] = 2 }, { source = "manual" }) -- writes 1 cast into bucket 4:2:14
local st90018 = ns.GetDEObservationStats(90018)
check(st90018 and st90018.casts == 5 and st90018.itemCasts == 5,
	"Larger uncached byItem (5 casts) must not be shadowed by smaller byBucket (1 cast), got casts=" .. tostring(st90018 and st90018.casts))
stubItems[90018] = nil
stubItems[90019] = nil

-- Finding 3: novel mat observed under AS (+20%) normalizes minAmount/maxAmount via baseMinQty/baseMaxQty
MerchantMasterDB.deObservations = nil
ns.ClearDECache()
for _ = 1, 3 do
	ns.RecordDEObservation(90001, { [11083] = 2.4 }, { arcaneSalvager = true, source = "helper" })
end
local bdNovelAS = ns.GetItemDEBreakdown(90001, nil, false)
local novelRow
for _, o in ipairs((bdNovelAS and bdNovelAS.outcomes) or {}) do
	if o.matID == 11083 then novelRow = o; break end
end
check(novelRow ~= nil and math.abs((novelRow.minAmount or 0) - 2.0) < 1e-6 and math.abs((novelRow.maxAmount or 0) - 2.0) < 1e-6,
	string.format("Novel AS mat minAmount/maxAmount must normalize to base 2.0 (got %s/%s)",
		tostring(novelRow and novelRow.minAmount), tostring(novelRow and novelRow.maxAmount)))

-- Tooltip displays 'Learned: N casts' when learnedCasts > 0
local learnedTipLines = {}
local learnedTip = {
	GetItem = function() return "Green Chest", "|Hitem:90001|h[Green Chest]|h" end,
	AddDoubleLine = function(_, l, r) learnedTipLines[#learnedTipLines + 1] = { l, r } end,
	NumLines = function() return #learnedTipLines end,
}
check(ns.AppendEconTooltip(learnedTip) == true, "AppendEconTooltip renders learned item tooltip")
local sawLearnedTip = false
for _, pair in ipairs(learnedTipLines) do
	if tostring(pair[2]):find("Learned: 3 casts", 1, true) then sawLearnedTip = true; break end
end
check(sawLearnedTip, "AppendEconTooltip displays 'Learned: 3 casts' when learnedCasts == 3")

-- 10. Pass 3: ns.IsArcaneSalvagerActive(explicitOverride) aura/DB detection & explicit false preservation
do
	local origCUA = _G.C_UnitAuras
	local origUnitBuff = _G.UnitBuff
	local origUnitAura = _G.UnitAura
	local origHelperAS = MerchantMasterDB.disenchantHelperAS
	local origCrafterAS = MerchantMasterDB.disenchantCrafterArcaneSalvager

	_G.C_UnitAuras = nil
	_G.UnitBuff = nil
	_G.UnitAura = nil
	MerchantMasterDB.disenchantHelperAS = false
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false

	check(ns.IsArcaneSalvagerActive(nil) == false, "IsArcaneSalvagerActive(nil) false with no aura and no DB toggles")
	check(ns.IsArcaneSalvagerActive(true) == true, "IsArcaneSalvagerActive(true) honors explicit true")

	-- Explicit false MUST NOT be overwritten by DB flags or active aura
	MerchantMasterDB.disenchantHelperAS = true
	MerchantMasterDB.disenchantCrafterArcaneSalvager = true
	_G.UnitBuff = function(_, idx)
		if idx == 1 then return "Arcane Salvager", 132864, 1, nil, 0, 0, "player", false, false, 999985 end
		return nil
	end
	check(ns.IsArcaneSalvagerActive(false) == false,
		"IsArcaneSalvagerActive(false) preserves explicit false even when DB flags and buff are active")

	-- Automatic buff detection via UnitBuff (with DB flags off)
	MerchantMasterDB.disenchantHelperAS = false
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false
	check(ns.IsArcaneSalvagerActive(nil) == true,
		"IsArcaneSalvagerActive(nil) detects 'Arcane Salvager' via UnitBuff")

	-- Automatic buff detection via C_UnitAuras
	_G.UnitBuff = nil
	_G.C_UnitAuras = {
		GetBuffDataByIndex = function(_, idx)
			if idx == 1 then return { name = "Boosted Disenchanting", spellId = 999986 } end
			return nil
		end,
	}
	check(ns.IsArcaneSalvagerActive(nil) == true,
		"IsArcaneSalvagerActive(nil) detects 'Boosted Disenchanting' via C_UnitAuras")

	-- DB fallback when no aura is active
	_G.C_UnitAuras = nil
	MerchantMasterDB.disenchantCrafterArcaneSalvager = true
	check(ns.IsArcaneSalvagerActive(nil) == true,
		"IsArcaneSalvagerActive(nil) detects disenchantCrafterArcaneSalvager DB toggle")
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false
	MerchantMasterDB.disenchantHelperAS = true
	check(ns.IsArcaneSalvagerActive(nil) == true,
		"IsArcaneSalvagerActive(nil) detects disenchantHelperAS DB toggle")

	_G.C_UnitAuras = origCUA
	_G.UnitBuff = origUnitBuff
	_G.UnitAura = origUnitAura
	MerchantMasterDB.disenchantHelperAS = origHelperAS
	MerchantMasterDB.disenchantCrafterArcaneSalvager = origCrafterAS
end

-- Clean up learner state & restore stubs
MerchantMasterDB.deObservations = nil
MerchantMasterDB.deItemMetaCache = nil
_G.C_Item = origCItem
_G.GetItemInfo = origGetItemInfo
ns.GetItemMarketPrice = origGetItemMarketPrice
ns.GetFallbackMarketPrice = origGetFallbackMarketPrice
ns.InvalidatePriceCache()

print("test_de_and_pricing: PASS (" .. n .. " assertions)")
