-- Vendor Crafter End-to-End Verification Suite (Pure Lua 5.1)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"

MerchantMasterDB = {
	superListColumns = { hidden = { wowheadURL = true }, order = { "name", "profit" } },
}

local ns, frames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local app = ns.app
local VC = ns.VendorCrafterModel
local Theme = ns.Theme

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("VENDOR CRAFTER FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local function approx(a, b, eps, msg)
	eps = eps or 1e-6
	check(type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps,
		string.format("%s (got %s, expected %s)", tostring(msg), tostring(a), tostring(b)))
end

local function plain(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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

check(type(VC) == "table" and type(VC.ResolveLegacy) == "function" and type(VC.EvaluateRecipe) == "function"
	and type(VC.EvaluateBuyMoat) == "function" and type(VC.Start) == "function" and type(VC.FilterSort) == "function",
	"ns.VendorCrafterModel public API exported")

local econKey = ns.CurrentEconomyInfo().effectiveKey
local mockVendorSell = hostEnv.mockVendorSell

local function setAHItem(itemID, minBuyout, marketVal, numListed, lots)
	MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
	MerchantMasterDB.ahPrices[econKey] = MerchantMasterDB.ahPrices[econKey] or { _scannedAt = time() }
	if minBuyout ~= nil then
		MerchantMasterDB.ahPrices[econKey][itemID] = { price = minBuyout, qty = numListed or 50, at = time() }
	else
		MerchantMasterDB.ahPrices[econKey][itemID] = nil
	end
	MerchantMasterDB.ahLots = MerchantMasterDB.ahLots or {}
	MerchantMasterDB.ahLots[econKey] = MerchantMasterDB.ahLots[econKey] or {}
	if lots ~= nil then
		MerchantMasterDB.ahLots[econKey][itemID] = { at = time(), lots = lots }
	else
		MerchantMasterDB.ahLots[econKey][itemID] = nil
	end
end

local function clearAHItem(itemID)
	setAHItem(itemID, nil, nil, nil, nil)
end

---------------------------------------------------------------------------------------------------
-- 1. Legacy Math: Master Chef 0..5, Non-Cooking Isolation, Bartering 0..2 + Honored Stacking,
--    Zero Leakage into GetVendorBuyPrice / Super List, and Fractional Avg Profit
---------------------------------------------------------------------------------------------------
do
	-- Synthetic items strictly outside real catalog IDs
	local OUT_COOK_1 = 998101
	local OUT_COOK_2 = 998102
	local OUT_BS = 998103
	local OUT_FRAC = 998104
	local MAT_AH = 998201
	local MAT_VEND = 998202
	local MAT_FRAC = 998203

	mockVendorSell[OUT_COOK_1] = 100
	mockVendorSell[OUT_COOK_2] = 150
	mockVendorSell[OUT_BS] = 200
	mockVendorSell[OUT_FRAC] = 15 -- at MC 5/5: 15 * 1.5 = 22.5; cost 22 -> +0.5; at MC 3/5: 15 * 1.3 = 19.5; cost 19.2? Wait: use unitSell=3, MC=1 -> 3.3 - 3 = 0.3
	local OUT_FRAC_LT05 = 998105
	mockVendorSell[OUT_FRAC_LT05] = 3

	ns.ITEM_VENDOR_SELL[OUT_COOK_1] = 100
	ns.ITEM_VENDOR_SELL[OUT_COOK_2] = 150
	ns.ITEM_VENDOR_SELL[OUT_BS] = 200
	ns.ITEM_VENDOR_SELL[OUT_FRAC] = 15
	ns.ITEM_VENDOR_SELL[OUT_FRAC_LT05] = 3

	ns.VENDOR_REAGENTS[MAT_VEND] = 100
	setAHItem(MAT_AH, 50, 55, 100, { { price = 50, qty = 100 } })
	setAHItem(MAT_FRAC, 22, 22, 100, { { price = 22, qty = 100 } })
	local MAT_FRAC_3 = 998204
	setAHItem(MAT_FRAC_3, 3, 3, 100, { { price = 3, qty = 100 } })
	ns.InvalidatePriceCache()

	local cookOne = {
		spellID = 998501,
		outputItemID = OUT_COOK_1,
		name = "Synthetic Wolf Steak",
		prof = "cooking",
		skill = 100,
		numMade = 1,
		reagents = { { MAT_AH, 1 } },
	}
	local cookTwo = {
		spellID = 998502,
		outputItemID = OUT_COOK_2,
		name = "Synthetic Kodo Stew",
		prof = "cooking",
		skill = 200,
		numMade = 2,
		reagents = { { MAT_AH, 2 } },
	}
	local bsRec = {
		spellID = 998503,
		outputItemID = OUT_BS,
		name = "Synthetic Copper Blade",
		prof = "blacksmithing",
		skill = 50,
		numMade = 1,
		reagents = { { MAT_AH, 1 } },
	}

	-- Master Chef 0..5 exact EV for numMade = 1 and numMade > 1
	for mc = 0, 5 do
		local legacy = VC.ResolveLegacy({ masterChefMode = mc, barteringMode = 0, honoredDiscount = false })
		check(legacy.masterChef == mc, "ResolveLegacy masterChef==" .. mc)
		approx(legacy.cookingProcChance, 0.10 * mc, 1e-9, "cookingProcChance for MC " .. mc)

		local r1 = VC.EvaluateRecipe(cookOne, { economy = econKey, subCraftMode = "buy" }, legacy, {})
		check(r1 ~= nil, "cookOne profitable at MC " .. mc)
		approx(r1.minVendor, 100, 1e-9, "cookOne minVendor MC " .. mc)
		approx(r1.avgVendor, 100 * (1 + 0.10 * mc), 1e-9, "cookOne avgVendor MC " .. mc)
		approx(r1.maxVendor, mc > 0 and 200 or 100, 1e-9, "cookOne maxVendor MC " .. mc)
		approx(r1.avgProfit, 100 * (1 + 0.10 * mc) - 50, 1e-9, "cookOne avgProfit MC " .. mc)

		local r2 = VC.EvaluateRecipe(cookTwo, { economy = econKey, subCraftMode = "buy" }, legacy, {})
		check(r2 ~= nil, "cookTwo profitable at MC " .. mc)
		approx(r2.minVendor, 300, 1e-9, "cookTwo minVendor (numMade=2) MC " .. mc)
		approx(r2.avgVendor, 300 * (1 + 0.10 * mc), 1e-9, "cookTwo avgVendor (numMade=2) MC " .. mc)
		approx(r2.maxVendor, mc > 0 and 600 or 300, 1e-9, "cookTwo maxVendor (numMade=2) MC " .. mc)
		approx(r2.avgProfit, 300 * (1 + 0.10 * mc) - 100, 1e-9, "cookTwo avgProfit (numMade=2) MC " .. mc)

		-- Non-Cooking ignores Master Chef completely
		local rbs = VC.EvaluateRecipe(bsRec, { economy = econKey, subCraftMode = "buy" }, legacy, {})
		check(rbs ~= nil, "bsRec profitable at MC " .. mc)
		approx(rbs.procChance, 0, 1e-9, "non-Cooking procChance == 0 at MC " .. mc)
		approx(rbs.minVendor, 200, 1e-9, "non-Cooking minVendor == 200")
		approx(rbs.avgVendor, 200, 1e-9, "non-Cooking avgVendor ignores MC " .. mc)
		approx(rbs.maxVendor, 200, 1e-9, "non-Cooking maxVendor ignores MC " .. mc)
		approx(rbs.avgProfit, 150, 1e-9, "non-Cooking avgProfit == 150")
	end

	-- Bartering 0..2 + Honored (-10%) multiplicative stacking (0.90 * 0.90 = 0.81)
	local expectedVendorPrice = {
		[0] = { [false] = 100, [true] = 90 },
		[1] = { [false] = 95,  [true] = 86 }, -- 100 * 0.95 * 0.90 = 85.5 -> 86
		[2] = { [false] = 90,  [true] = 81 }, -- 100 * 0.90 * 0.90 = 81
	}
	local vendorCookRec = {
		spellID = 998504,
		outputItemID = OUT_COOK_1,
		name = "Synthetic Spiced Dish",
		prof = "cooking",
		skill = 10,
		numMade = 1,
		reagents = { { MAT_VEND, 1 } },
	}
	local baselineBuyBefore = ns.GetVendorBuyPrice(MAT_VEND, 100, false)
	for barter = 0, 2 do
		for _, honored in ipairs({ false, true }) do
			local expected = expectedVendorPrice[barter][honored]
			local directPrice = ns.GetVendorBuyPrice(MAT_VEND, 100, false, barter, honored)
			check(directPrice == expected,
				string.format("GetVendorBuyPrice(barter=%d, honored=%s) expected %d, got %s",
					barter, tostring(honored), expected, tostring(directPrice)))

			local leg = VC.ResolveLegacy({ masterChefMode = 5, barteringMode = barter, honoredDiscount = honored })
			approx(leg.vendorMult, (1 - 0.05 * barter) * (honored and 0.90 or 1.0), 1e-9,
				"ResolveLegacy vendorMult stacking")
			local r = VC.EvaluateRecipe(vendorCookRec, { economy = econKey, subCraftMode = "buy" }, leg, {})
			check(r ~= nil, "vendorCookRec profitable at barter=" .. barter .. " honored=" .. tostring(honored))
			approx(r.craftCost, expected, 1e-9, "vendorCookRec craftCost matches stacked vendor price")
			approx(r.avgProfit, 150 - expected, 1e-9, "vendorCookRec avgProfit matches stacked vendor price")
		end
	end

	-- Toggling Vendor Crafter Bartering/Honored DB fields must NOT leak into nil-5th-param GetVendorBuyPrice or Super List
	MerchantMasterDB.vendorCrafterBartering = 2
	MerchantMasterDB.vendorCrafterHonored = true
	local baselineBuyAfter = ns.GetVendorBuyPrice(MAT_VEND, 100, false)
	check(baselineBuyAfter == baselineBuyBefore and baselineBuyAfter == 100,
		"Vendor Crafter Bartering/Honored toggles do not leak into ns.GetVendorBuyPrice(id, static, false), got " .. tostring(baselineBuyAfter))
	local slUnitCost = ns.GetReagentUnitCost(MAT_VEND)
	check(slUnitCost == 100, "Super List reagent unit cost unaffected by Vendor Crafter toggles, got " .. tostring(slUnitCost))
	MerchantMasterDB.vendorCrafterBartering = "auto"
	MerchantMasterDB.vendorCrafterHonored = false

	-- Fractional avgProfit: both 22.5 - 22 = +0.5 and 3.3 - 3 = +0.3 (strictly 0 < avgProfit < 0.5) are included
	local fracRec05 = {
		spellID = 998505,
		outputItemID = OUT_FRAC,
		name = "Synthetic Half Copper Brew",
		prof = "cooking",
		skill = 1,
		numMade = 1,
		reagents = { { MAT_FRAC, 1 } },
	}
	local legMC5 = VC.ResolveLegacy({ masterChefMode = 5, barteringMode = 0, honoredDiscount = false })
	local rFrac05 = VC.EvaluateRecipe(fracRec05, { economy = econKey, subCraftMode = "buy" }, legMC5, {})
	check(rFrac05 ~= nil, "Fractional +0.5c profit recipe IS included by EvaluateRecipe")
	approx(rFrac05.avgVendor, 22.5, 1e-9, "fracRec05 avgVendor == 22.5")
	approx(rFrac05.avgProfit, 0.5, 1e-9, "fracRec05 avgProfit == 0.5")

	local fracRec03 = {
		spellID = 998506,
		outputItemID = OUT_FRAC_LT05,
		name = "Synthetic Sub-Half Copper Dish",
		prof = "cooking",
		skill = 1,
		numMade = 1,
		reagents = { { MAT_FRAC_3, 1 } },
	}
	local legMC1 = VC.ResolveLegacy({ masterChefMode = 1, barteringMode = 0, honoredDiscount = false })
	local rFrac03 = VC.EvaluateRecipe(fracRec03, { economy = econKey, subCraftMode = "buy" }, legMC1, {})
	check(rFrac03 ~= nil, "Fractional +0.3c (0 < avgProfit < 0.5) profit recipe IS included by EvaluateRecipe")
	approx(rFrac03.avgVendor, 3.3, 1e-9, "fracRec03 avgVendor == 3.3")
	approx(rFrac03.avgProfit, 0.3, 1e-9, "fracRec03 avgProfit == 0.3")
	local filteredFrac = VC.FilterSort({ rFrac05, rFrac03 }, {}, { key = "avgProfit", ascending = false })
	check(#filteredFrac == 2 and filteredFrac[1] == rFrac05 and filteredFrac[2] == rFrac03,
		"FilterSort retains fractional positive avgProfit rows in descending order")

	-- Cleanup synthetic items
	for _, id in ipairs({ OUT_COOK_1, OUT_COOK_2, OUT_BS, OUT_FRAC, OUT_FRAC_LT05 }) do
		mockVendorSell[id] = nil
		ns.ITEM_VENDOR_SELL[id] = nil
	end
	ns.VENDOR_REAGENTS[MAT_VEND] = nil
	clearAHItem(MAT_AH)
	clearAHItem(MAT_FRAC)
	clearAHItem(MAT_FRAC_3)
	ns.InvalidatePriceCache()
end

---------------------------------------------------------------------------------------------------
-- 2. Strict avgProfit > 0 Gate
---------------------------------------------------------------------------------------------------
do
	local OUT_ZERO = 998301
	local OUT_NEG = 998302
	local OUT_NOSELL = 998303
	local MAT_100 = 998311
	local MAT_UNPRICED = 998312

	mockVendorSell[OUT_ZERO] = 100
	mockVendorSell[OUT_NEG] = 90
	ns.ITEM_VENDOR_SELL[OUT_ZERO] = 100
	ns.ITEM_VENDOR_SELL[OUT_NEG] = 90
	ns.ITEM_VENDOR_SELL[OUT_NOSELL] = nil
	mockVendorSell[OUT_NOSELL] = nil

	setAHItem(MAT_100, 100, 100, 50, { { price = 100, qty = 50 } })
	clearAHItem(MAT_UNPRICED)
	ns.InvalidatePriceCache()

	local leg0 = VC.ResolveLegacy({ masterChefMode = 0, barteringMode = 0, honoredDiscount = false })

	local rZero = VC.EvaluateRecipe({
		spellID = 998601, outputItemID = OUT_ZERO, name = "Zero Profit", prof = "blacksmithing", skill = 1,
		reagents = { { MAT_100, 1 } },
	}, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rZero == nil, "avgProfit == 0 never enters Vendor Crafter rows")

	local rNeg = VC.EvaluateRecipe({
		spellID = 998602, outputItemID = OUT_NEG, name = "Negative Profit", prof = "blacksmithing", skill = 1,
		reagents = { { MAT_100, 1 } },
	}, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rNeg == nil, "avgProfit < 0 never enters Vendor Crafter rows")

	local rNoSell = VC.EvaluateRecipe({
		spellID = 998603, outputItemID = OUT_NOSELL, name = "No Vendor Sell", prof = "blacksmithing", skill = 1,
		reagents = { { MAT_100, 1 } },
	}, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rNoSell == nil, "Missing vendor sell never enters Vendor Crafter rows")

	local rNoMat = VC.EvaluateRecipe({
		spellID = 998604, outputItemID = OUT_ZERO, name = "Missing Reagent Price", prof = "blacksmithing", skill = 1,
		reagents = { { MAT_UNPRICED, 1 } },
	}, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rNoMat == nil, "Missing reagent price never enters Vendor Crafter rows")

	local rEnch = VC.EvaluateRecipe({
		spellID = 998605, outputItemID = OUT_ZERO, name = "Enchant Test", prof = "enchanting", skill = 1, isEnchant = true,
		reagents = { { MAT_100, 1 } },
	}, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rEnch == nil, "Enchant recipes never enter Vendor Crafter rows")

	-- FilterSort also enforces strict avgProfit > 0
	local fsOut = VC.FilterSort({
		{ key = "a", name = "A", prof = "cooking", avgProfit = 0 },
		{ key = "b", name = "B", prof = "cooking", avgProfit = -5 },
		{ key = "c", name = "C", prof = "cooking", avgProfit = nil },
		{ key = "d", name = "D", prof = "cooking", avgProfit = 0.2 },
	}, {}, { key = "avgProfit", ascending = false })
	check(#fsOut == 1 and fsOut[1].key == "d", "FilterSort drops <= 0 and nil avgProfit rows")

	mockVendorSell[OUT_ZERO], mockVendorSell[OUT_NEG] = nil, nil
	ns.ITEM_VENDOR_SELL[OUT_ZERO], ns.ITEM_VENDOR_SELL[OUT_NEG] = nil, nil
	clearAHItem(MAT_100)
	ns.InvalidatePriceCache()
end

---------------------------------------------------------------------------------------------------
-- 3. Buy Moat Evaluation: Infinite, Multi-Tier db.ahLots, Snapshot DEPTH, Tiers & moatFilter
---------------------------------------------------------------------------------------------------
do
	-- 3A. All-vendor -> infinite
	local infMoat = VC.EvaluateBuyMoat({
		[2678] = { itemID = 2678, name = "Mild Spices", qty = 2, unitCost = 2, isVendor = true, source = "Vendor" },
		[159]  = { itemID = 159,  name = "Refreshing Spring Water", qty = 1, unitCost = 5, isVendor = true, source = "Vendor" },
	}, 9, 30, econKey, {})
	check(infMoat.tier == "infinite" and infMoat.isAllVendor == true
		and infMoat.profitableCrafts == math.huge and infMoat.totalProfitCap == math.huge,
		"All-vendor reagents yield infinite Buy Moat with math.huge crafts & cap")

	-- 3B. Multi-tier db.ahLots: exact profitableCrafts, totalProfitCap, bottleneck, breakEvenPrice
	-- Recipe needs 2x MAT_A + 1x MAT_B + 50c vendor; avgVendor = 400
	-- MAT_A lots: 10 @ 100 (5 crafts), 5 @ 120 (straddles: 2 crafts + 1 leftover), 5 @ 160 (next craft uses 1@120 + 1@160 = 280; + 50 vendor + 80 MAT_B = 410 > 400 -> price wall!)
	-- MAT_B lots: 20 @ 80
	-- Craft 1..5: 2*100 + 80 + 50 = 330 -> profit 70 each -> 350
	-- Craft 6..7: 2*120 + 80 + 50 = 370 -> profit 30 each -> 60
	-- Craft 8 (straddle): (1*120 + 1*160) + 80 + 50 = 410 > 400 -> stops!
	-- Total: 7 profitableCrafts, totalProfitCap = 410, bottleneck = MAT_A (price_wall), breakEvenPrice(MAT_A) = floor((400 - (330 - 200)) / 2) = floor(270/2) = 135
	local MAT_A, MAT_B = 998401, 998402
	setAHItem(MAT_A, 100, 105, 20, { { price = 100, qty = 10 }, { price = 120, qty = 5 }, { price = 160, qty = 5 } })
	setAHItem(MAT_B, 80, 82, 20, { { price = 80, qty = 20 } })
	ns.InvalidatePriceCache()

	local multiMoat = VC.EvaluateBuyMoat({
		[MAT_A] = { itemID = MAT_A, name = "Reagent A", qty = 2, unitCost = 100, isVendor = false, source = "AH" },
		[MAT_B] = { itemID = MAT_B, name = "Reagent B", qty = 1, unitCost = 80,  isVendor = false, source = "AH" },
		[2678]  = { itemID = 2678,  name = "Vendor Spice", qty = 1, unitCost = 50, isVendor = true, source = "Vendor" },
	}, 330, 400, econKey, {})
	check(multiMoat.depthSource == "live_lots", "Multi-tier db.ahLots uses live_lots depthSource")
	check(multiMoat.profitableCrafts == 7, "Multi-tier db.ahLots exact profitableCrafts == 7, got " .. tostring(multiMoat.profitableCrafts))
	approx(multiMoat.totalProfitCap, 410, 1e-6, "Multi-tier db.ahLots exact totalProfitCap == 410")
	check(multiMoat.bottleneck and multiMoat.bottleneck.itemID == MAT_A and multiMoat.bottleneckReason == "price_wall",
		"Multi-tier db.ahLots identifies MAT_A as price_wall bottleneck")
	check(multiMoat.bottleneck.breakEvenPrice == 135,
		"Multi-tier db.ahLots exact breakEvenPrice == 135, got " .. tostring(multiMoat.bottleneck.breakEvenPrice))
	check(multiMoat.tier == "thin", "7 crafts without flash dip classifies as thin, got " .. tostring(multiMoat.tier))

	-- 3C. Snapshot DEPTH fallback (Pricing.GetItemSnapshotDepth) when db.ahLots is absent
	local MAT_SNAP = 998403
	clearAHItem(MAT_SNAP)
	setAHItem(MAT_SNAP, 100, 100, 100, nil) -- no db.ahLots!
	local priorSnapRaw = ns.snapshotRaw
	local priorSnapParsed = ns.snapshotParsed
	local priorSnapHeat = ns.snapshotHeatmapCache
	ns.snapshotRaw = {}
	ns.snapshotParsed = {}
	ns.snapshotHeatmapCache = {}
	-- 60 @ 100 + 20 @ 140 + 30 @ 250; avgVendor = 200 -> 60*(200-100) + 20*(200-140) = 6000 + 1200 = 7200, 80 crafts -> Deep!
	local depthPayload = string.format("%d:%s,%s|%s,%s|%s,%s",
		MAT_SNAP, encodeB32(100), encodeB32(60), encodeB32(140), encodeB32(20), encodeB32(250), encodeB32(30))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econKey,
		string.format([[return {v=1,updatedAt=%d,source="tsm_csv",windowDays=30,itemCount=1,depthCount=1}]], time() - 300))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("DEPTH", econKey, depthPayload)
	ns.InvalidatePriceCache()

	local snapDepthCheck = ns.Pricing.GetItemSnapshotDepth(MAT_SNAP, econKey)
	check(type(snapDepthCheck) == "table" and #snapDepthCheck == 3 and snapDepthCheck[1].price == 100 and snapDepthCheck[1].qty == 60,
		"Pricing.GetItemSnapshotDepth decodes 3 multi-tier lots")

	local deepMoat = VC.EvaluateBuyMoat({
		[MAT_SNAP] = { itemID = MAT_SNAP, name = "Snap Ore", qty = 1, unitCost = 100, isVendor = false, source = "Snapshot" },
	}, 100, 200, econKey, {})
	check(deepMoat.depthSource == "snapshot_depth", "Snapshot DEPTH fallback sets depthSource == snapshot_depth")
	check(deepMoat.profitableCrafts == 80, "Snapshot DEPTH exact profitableCrafts == 80, got " .. tostring(deepMoat.profitableCrafts))
	approx(deepMoat.totalProfitCap, 7200, 1e-6, "Snapshot DEPTH exact totalProfitCap == 7200")
	check(deepMoat.tier == "deep", "80 crafts with >=25 at current classifies as deep, got " .. tostring(deepMoat.tier))
	check(deepMoat.bottleneck and deepMoat.bottleneck.itemID == MAT_SNAP and deepMoat.bottleneck.breakEvenPrice == 200,
		"Snapshot DEPTH tracks bottleneck and breakEvenPrice")

	-- 3D. Steady tier (20 crafts, not flash dip)
	local MAT_STEADY = 998404
	setAHItem(MAT_STEADY, 100, 105, 20, { { price = 100, qty = 20 } })
	ns.InvalidatePriceCache()
	local steadyMoat = VC.EvaluateBuyMoat({
		[MAT_STEADY] = { itemID = MAT_STEADY, name = "Steady Herb", qty = 1, unitCost = 100, isVendor = false, source = "AH" },
	}, 100, 180, econKey, {})
	check(steadyMoat.tier == "steady" and steadyMoat.profitableCrafts == 20 and steadyMoat.bottleneckReason == "supply",
		"20 crafts supply-limited classifies as steady, got " .. tostring(steadyMoat.tier))

	-- 3E. Moment tier: (< 5 crafts) AND flash dip (< 88% of 24h median when baseline unprofitable)
	local MAT_MOMENT_TINY = 998405
	setAHItem(MAT_MOMENT_TINY, 100, 100, 3, { { price = 100, qty = 3 } })
	local momentTiny = VC.EvaluateBuyMoat({
		[MAT_MOMENT_TINY] = { itemID = MAT_MOMENT_TINY, name = "Tiny Lot", qty = 1, unitCost = 100, isVendor = false, source = "AH" },
	}, 100, 160, econKey, {})
	check(momentTiny.tier == "moment" and momentTiny.profitableCrafts == 3,
		"<5 crafts classifies as moment, got " .. tostring(momentTiny.tier))

	-- Flash dip via HEAT24 medianPrice = 220 (baseline 220 >= avgVendor 180, current 100 < 220 * 0.88 = 193.6, 12 crafts < 25 -> moment + isFlashDip)
	local MAT_FLASH = 998406
	setAHItem(MAT_FLASH, 100, 220, 12, { { price = 100, qty = 12 } })
	local h24Parts = {}
	for hr = 1, 24 do h24Parts[hr] = encodeB32(220) end
	local heat24Line = string.format("%d:%s,%s,%s,%s,%s,%d,%s,%d,%s|%s",
		MAT_FLASH, encodeB32(220), encodeB32(220), encodeB32(15), encodeB32(10), encodeB32(100),
		0, encodeB32(200), 12, encodeB32(240), table.concat(h24Parts, ","))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", econKey, heat24Line)
	ns.InvalidatePriceCache()

	local flashMoat = VC.EvaluateBuyMoat({
		[MAT_FLASH] = { itemID = MAT_FLASH, name = "Flash Herb", qty = 1, unitCost = 100, isVendor = false, source = "AH" },
	}, 100, 180, econKey, {})
	check(flashMoat.isFlashDip == true and flashMoat.tier == "moment" and flashMoat.stability == "flash_dip",
		"Flash dip (<88% 24h median while baseline unprofitable) classifies as moment/flash_dip, got tier="
		.. tostring(flashMoat.tier) .. " flash=" .. tostring(flashMoat.isFlashDip))

	-- 3F. moatFilter: all, deep, steady, moment
	local moatRows = {
		{ key = "inf",    name = "Inf",    prof = "cooking", avgProfit = 50, moatTier = "infinite", moatScore = infMoat.score },
		{ key = "deep",   name = "Deep",   prof = "cooking", avgProfit = 40, moatTier = "deep",     moatScore = deepMoat.score },
		{ key = "steady", name = "Steady", prof = "cooking", avgProfit = 30, moatTier = "steady",   moatScore = steadyMoat.score },
		{ key = "thin",   name = "Thin",   prof = "cooking", avgProfit = 20, moatTier = "thin",     moatScore = multiMoat.score },
		{ key = "moment", name = "Moment", prof = "cooking", avgProfit = 10, moatTier = "moment",   moatScore = flashMoat.score },
	}
	check(#VC.FilterSort(moatRows, { moatFilter = "all" }) == 5, "moatFilter=all keeps all 5 tiers")
	local fDeep = VC.FilterSort(moatRows, { moatFilter = "deep" })
	check(#fDeep == 2 and fDeep[1].key == "inf" and fDeep[2].key == "deep", "moatFilter=deep keeps infinite + deep")
	local fSteady = VC.FilterSort(moatRows, { moatFilter = "steady" })
	check(#fSteady == 3 and fSteady[3].key == "steady", "moatFilter=steady keeps infinite + deep + steady")
	local fMoment = VC.FilterSort(moatRows, { moatFilter = "moment" })
	check(#fMoment == 1 and fMoment[1].key == "moment", "moatFilter=moment keeps moment only")

	-- Restore snapshot tables and clear synthetic items
	ns.snapshotRaw = priorSnapRaw
	ns.snapshotParsed = priorSnapParsed
	ns.snapshotHeatmapCache = priorSnapHeat
	for _, id in ipairs({ MAT_A, MAT_B, MAT_SNAP, MAT_STEADY, MAT_MOMENT_TINY, MAT_FLASH }) do
		clearAHItem(id)
	end
	ns.InvalidatePriceCache()
end

---------------------------------------------------------------------------------------------------
-- 3B. Phase 2: Order-Book Buy Ceiling, Safe 0-Proc Crafts, Shared-Reagent Top-N Portfolio,
--     BUG 1 (Vendor Backstop on AH Undercuts) & BUG 2 (GetVendorBuyPrice allowLimited Gate)
---------------------------------------------------------------------------------------------------
do
	-- 3B-1. Order-book ceiling scenario: 1s (100c) -> 1s 95c (195c) -> 3s (300c) loss wall vs 2s (200c) vendor sell
	local OUT_CEIL = 998701
	local OUT_COOK_SAFE = 998702
	local MAT_CEIL = 998711
	mockVendorSell[OUT_CEIL] = 200
	ns.ITEM_VENDOR_SELL[OUT_CEIL] = 200
	mockVendorSell[OUT_COOK_SAFE] = 150 -- at MC 5/5: minVendor=150, avgVendor=225
	ns.ITEM_VENDOR_SELL[OUT_COOK_SAFE] = 150

	setAHItem(MAT_CEIL, 100, 110, 35, {
		{ price = 100, qty = 10 },
		{ price = 195, qty = 5 },
		{ price = 300, qty = 20 },
	})
	ns.InvalidatePriceCache()

	local leg0 = VC.ResolveLegacy({ masterChefMode = 0, barteringMode = 0, honoredDiscount = false })
	local recCeil = {
		spellID = 998801, outputItemID = OUT_CEIL, name = "Synthetic Ceiling Blade",
		prof = "blacksmithing", skill = 50, numMade = 1, reagents = { { MAT_CEIL, 1 } },
	}
	local rowCeil = VC.EvaluateRecipe(recCeil, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rowCeil ~= nil and rowCeil.moat ~= nil, "Ceiling recipe evaluates cleanly")
	local cm = rowCeil.moat
	check(cm.profitableCrafts == 15, "Ceiling profitableCrafts == 15 (10@1s + 5@1s95c), got " .. tostring(cm.profitableCrafts))
	approx(cm.totalSpendCap, 1975, 1e-6, "Ceiling totalSpendCap == 1975")
	approx(cm.totalProfitCap, 1025, 1e-6, "Ceiling totalProfitCap == 1025")
	approx(cm.lastProfitableCraftCost, 195, 1e-6, "Ceiling lastProfitableCraftCost == 195")
	approx(cm.stopWallCraftCost, 300, 1e-6, "Ceiling stopWallCraftCost == 300")
	check(cm.bottleneckReason == "price_wall", "Ceiling stops at price_wall")
	check(cm.reagents and cm.reagents[1] and cm.reagents[1].maxBuyQty == 15, "Reagent maxBuyQty == 15")
	check(cm.reagents[1].minLotPrice == 100 and cm.reagents[1].maxProfitableUnitPrice == 195 and cm.reagents[1].wallUnitPrice == 300,
		"Reagent minLotPrice=100, maxProfitableUnitPrice=195, wallUnitPrice=300")
	approx(cm.reagents[1].avgBuyUnitPrice, 1975 / 15, 1e-4, "Reagent avgBuyUnitPrice == 1975/15")
	approx(rowCeil.buyCeiling, 195, 1e-6, "row.buyCeiling == 195")
	approx(rowCeil.stopWallCost, 300, 1e-6, "row.stopWallCost == 300")
	check(rowCeil.safeProfitCrafts == 15, "Non-cooking safeProfitCrafts matches profitableCrafts == 15")

	-- Cooking 0-proc safeProfitCrafts: minVendor=150 (only 10@100c are safe), avgVendor=225 (15 crafts profitable)
	local leg5 = VC.ResolveLegacy({ masterChefMode = 5, barteringMode = 0, honoredDiscount = false })
	local recCookSafe = {
		spellID = 998802, outputItemID = OUT_COOK_SAFE, name = "Synthetic Safe Feast",
		prof = "cooking", skill = 100, numMade = 1, reagents = { { MAT_CEIL, 1 } },
	}
	local rowSafe = VC.EvaluateRecipe(recCookSafe, { economy = econKey, subCraftMode = "buy" }, leg5, {})
	check(rowSafe ~= nil, "Cooking safeProfitCrafts recipe evaluates cleanly at MC 5/5")
	check(rowSafe.profitableCrafts == 15, "Cooking MC 5/5 avg profitableCrafts == 15, got " .. tostring(rowSafe.profitableCrafts))
	check(rowSafe.safeProfitCrafts == 10 and rowSafe.moat.safeProfitCrafts == 10,
		"Cooking 0-proc safeProfitCrafts == 10 (only 100c < 150c minVendor), got " .. tostring(rowSafe.safeProfitCrafts))

	-- 3B-2. Shared-reagent Top-N Portfolio Maximizer: no double-counting, Pass 2 reclamation, craft cap, budget cap
	local MAT_SH = 998712
	local MAT_R1, MAT_R2, MAT_R3 = 998713, 998714, 998715
	local OUT_R1, OUT_R2, OUT_R3 = 998703, 998704, 998705
	mockVendorSell[OUT_R1], ns.ITEM_VENDOR_SELL[OUT_R1] = 400, 400
	mockVendorSell[OUT_R2], ns.ITEM_VENDOR_SELL[OUT_R2] = 260, 260
	mockVendorSell[OUT_R3], ns.ITEM_VENDOR_SELL[OUT_R3] = 600, 600

	setAHItem(MAT_SH, 100, 125, 20, { { price = 100, qty = 10 }, { price = 150, qty = 10 } })
	setAHItem(MAT_R1, 10, 10, 8,  { { price = 10, qty = 8 } })
	setAHItem(MAT_R2, 10, 10, 10, { { price = 10, qty = 10 } })
	setAHItem(MAT_R3, 10, 10, 2,  { { price = 10, qty = 2 } })
	ns.InvalidatePriceCache()

	local rowR1 = VC.EvaluateRecipe({ spellID = 998803, outputItemID = OUT_R1, name = "Port R1", prof = "blacksmithing", skill = 50, reagents = { { MAT_SH, 1 }, { MAT_R1, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	local rowR2 = VC.EvaluateRecipe({ spellID = 998804, outputItemID = OUT_R2, name = "Port R2", prof = "blacksmithing", skill = 50, reagents = { { MAT_SH, 1 }, { MAT_R2, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	local rowR3 = VC.EvaluateRecipe({ spellID = 998805, outputItemID = OUT_R3, name = "Port R3", prof = "blacksmithing", skill = 50, reagents = { { MAT_SH, 1 }, { MAT_R3, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rowR1 and rowR2 and rowR3, "All 3 competing shared-reagent recipes evaluated")

	-- All-3 plan: R3 (eff 4.45) takes 2 cheap @100 (profit 980), R1 (eff 2.64) takes 8 cheap @100 (profit 2320), R2 takes 10 mid @150 (profit 1000) -> total 20 shared units (no double-counting!)
	local planAll = VC.OptimizePortfolio({ rowR1, rowR2, rowR3 }, { topN = "all", econKey = econKey })
	check(planAll.recipeCount == 3 and planAll.totalCrafts == 20, "Shared-reagent plan allocates 20 total crafts with zero double-counting, got " .. tostring(planAll.totalCrafts))
	check(planAll.buyList[MAT_SH] and planAll.buyList[MAT_SH].qty == 20, "Consolidated buyList[MAT_SH].qty == 20")
	approx(planAll.byKey[rowR1.key].profit, 2320, 1e-6, "Pass1 R1 profit == 2320")
	approx(planAll.byKey[rowR2.key].profit, 1000, 1e-6, "Pass1 R2 profit == 1000")
	approx(planAll.byKey[rowR3.key].profit, 980, 1e-6, "Pass1 R3 profit == 980")
	check(planAll.entries[1].key == rowR1.key and planAll.entries[2].key == rowR2.key and planAll.entries[3].key == rowR3.key,
		"Pass1 ranks by total profit DESC: R1 > R2 > R3")

	-- Top-2 plan: Pass 2 drops R3 (#3) and RECLAIMS its 2 cheap 100c lots into R2 (R2 profit rises 1000 -> 1100!)
	local planTop2 = VC.OptimizePortfolio({ rowR1, rowR2, rowR3 }, { topN = 2, econKey = econKey })
	check(planTop2.recipeCount == 2 and planTop2.byKey[rowR3.key] == nil, "Top-2 plan keeps only R1 and R2")
	approx(planTop2.byKey[rowR1.key].profit, 2320, 1e-6, "Top-2 R1 profit == 2320")
	approx(planTop2.byKey[rowR2.key].profit, 1100, 1e-6, "Pass 2 reclamation lifts R2 profit from 1000 to 1100")
	approx(planTop2.totalProfit, 3420, 1e-6, "Top-2 totalProfit == 3420")

	-- Budget cap: 550c allows 5 crafts @ 110c (totalSpend <= 550)
	local planBudget = VC.OptimizePortfolio({ rowR1, rowR2, rowR3 }, { topN = "all", budgetCopper = 550, econKey = econKey })
	check(planBudget.totalSpend <= 550 and planBudget.totalCrafts == 5,
		"budgetCopper=550 caps totalSpend <= 550 and crafts == 5, got spend=" .. tostring(planBudget.totalSpend) .. " crafts=" .. tostring(planBudget.totalCrafts))

	-- maxCraftsPerRecipe = 500 cap on deep AH supply (800 units)
	local MAT_BIG, OUT_BIG = 998716, 998706
	mockVendorSell[OUT_BIG], ns.ITEM_VENDOR_SELL[OUT_BIG] = 200, 200
	setAHItem(MAT_BIG, 100, 100, 800, { { price = 100, qty = 800 } })
	ns.InvalidatePriceCache()
	local rowBig = VC.EvaluateRecipe({ spellID = 998806, outputItemID = OUT_BIG, name = "Big Craft", prof = "blacksmithing", skill = 50, reagents = { { MAT_BIG, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	local planCap500 = VC.OptimizePortfolio({ rowBig }, { topN = 10, maxCraftsPerRecipe = 500, econKey = econKey })
	check(planCap500.totalCrafts == 500 and planCap500.entries[1].stopReason == "craft_cap",
		"maxCraftsPerRecipe=500 caps deep AH recipe at 500 crafts, got " .. tostring(planCap500.totalCrafts))

	-- vendor_loop and ah_only moat filters
	local loopFilterRows = {
		{ key = "vl", name = "Vendor Loop", prof = "cooking", avgProfit = 50, moatTier = "infinite" },
		{ key = "ah1", name = "AH Deep", prof = "cooking", avgProfit = 40, moatTier = "deep" },
		{ key = "ah2", name = "AH Moment", prof = "cooking", avgProfit = 30, moatTier = "moment" },
	}
	local onlyVL = VC.FilterSort(loopFilterRows, { moatFilter = "vendor_loop" })
	check(#onlyVL == 1 and onlyVL[1].key == "vl", "moatFilter='vendor_loop' keeps only infinite vendor loops")
	local onlyAH = VC.FilterSort(loopFilterRows, { moatFilter = "ah_only" })
	check(#onlyAH == 2 and onlyAH[1].key == "ah1" and onlyAH[2].key == "ah2", "moatFilter='ah_only' excludes infinite vendor loops")

	-- 3B-3. BUG 1 Regressions: vendor backstop when AH undercuts vendor price
	local MAT_VBACK = 998720
	local MAT_AHMIX = 998721
	local OUT_MIX, OUT_VLOOP, OUT_VDIP = 998707, 998708, 998709
	ns.VENDOR_REAGENTS[MAT_VBACK] = 100
	mockVendorSell[OUT_MIX], ns.ITEM_VENDOR_SELL[OUT_MIX] = 300, 300
	mockVendorSell[OUT_VLOOP], ns.ITEM_VENDOR_SELL[OUT_VLOOP] = 150, 150
	mockVendorSell[OUT_VDIP], ns.ITEM_VENDOR_SELL[OUT_VDIP] = 90, 90

	-- 2 cheap undercut AH units @ 80c (plus 5 overpriced @ 150c), and 20 AH units of MAT_AHMIX @ 50c
	setAHItem(MAT_VBACK, 80, 100, 7, { { price = 80, qty = 2 }, { price = 150, qty = 5 } })
	setAHItem(MAT_AHMIX, 50, 50, 20, { { price = 50, qty = 20 } })
	ns.InvalidatePriceCache()

	-- BUG 1a: Mixed vendor-backed AH undercut falls back to infinite vendor backstop instead of truncating at 2
	local rowMix = VC.EvaluateRecipe({ spellID = 998807, outputItemID = OUT_MIX, name = "Mixed Backstop", prof = "blacksmithing", skill = 50, reagents = { { MAT_VBACK, 1 }, { MAT_AHMIX, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rowMix ~= nil and rowMix.profitableCrafts == 20,
		"BUG 1a: mixed vendor-backed AH undercut continues past 2 cheap units to 20 crafts via vendor backstop, got " .. tostring(rowMix and rowMix.profitableCrafts))
	approx(rowMix.totalSpendCap, 2 * 130 + 18 * 150, 1e-6, "BUG 1a: totalSpendCap uses 2@80c AH + 18@100c vendor")
	local foundBackstopFlag = false
	for _, rg in ipairs(rowMix.moat.reagents or {}) do
		if rg.itemID == MAT_VBACK and rg.hasVendorBackstop == true then foundBackstopFlag = true end
	end
	check(foundBackstopFlag, "BUG 1a: vendor-backed reagent marks hasVendorBackstop == true")

	-- BUG 1b: All-vendor loop with cheap AH undercut stays infinite (isAllVendor == true)
	local rowVLoop = VC.EvaluateRecipe({ spellID = 998808, outputItemID = OUT_VLOOP, name = "Undercut Vendor Loop", prof = "blacksmithing", skill = 50, reagents = { { MAT_VBACK, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rowVLoop ~= nil and rowVLoop.moatTier == "infinite" and rowVLoop.isAllVendor == true and rowVLoop.profitableCrafts == math.huge,
		"BUG 1b: all-vendor loop with cheap AH undercut stays infinite/isAllVendor, got tier=" .. tostring(rowVLoop and rowVLoop.moatTier))

	-- BUG 1c: Dip-below-vendor-cost (pureVendorCost 100 >= avgVendor 90) stops finitely at vendorUnit wall (100c)
	local rowVDip = VC.EvaluateRecipe({ spellID = 998809, outputItemID = OUT_VDIP, name = "Dip Below Vendor", prof = "blacksmithing", skill = 50, reagents = { { MAT_VBACK, 1 } } }, { economy = econKey, subCraftMode = "buy" }, leg0, {})
	check(rowVDip ~= nil and rowVDip.moatTier ~= "infinite" and rowVDip.isAllVendor == false
		and rowVDip.profitableCrafts == 2 and rowVDip.moat.bottleneckReason == "price_wall"
		and rowVDip.moat.stopWallCraftCost == 100 and rowVDip.moat.reagents[1].wallUnitPrice == 100,
		"BUG 1c: dip-below-vendor-cost stops finitely at 2 crafts against 100c vendorUnit wall")

	-- 3B-4. BUG 2 Regression: GetVendorBuyPrice allowLimited gate on limited-stock vendor items
	local NON_VR_ID = 998950
	ns.VENDOR_REAGENTS[NON_VR_ID] = nil
	MerchantMasterDB.liveVendorBuyGlobal = MerchantMasterDB.liveVendorBuyGlobal or {}
	MerchantMasterDB.liveVendorBuyGlobal[NON_VR_ID] = { price = 500, at = time(), limited = true }
	ns.InvalidatePriceCache()
	check(ns.GetVendorBuyPrice(NON_VR_ID, nil, false) == nil,
		"BUG 2: GetVendorBuyPrice(nonVR, nil, false) skips limited-stock vendor entry when allowLimited == false")
	check(ns.GetVendorBuyPrice(NON_VR_ID, nil, true) == 500,
		"BUG 2: GetVendorBuyPrice(nonVR, nil, true) returns limited-stock vendor entry when allowLimited == true")
	check((ns.GetVendorBuyPrice(3713, nil, false) or 0) > 0,
		"BUG 2: known VENDOR_REAGENTS item (3713 Soothing Spices) still resolves with allowLimited == false")
	MerchantMasterDB.liveVendorBuyGlobal[NON_VR_ID] = nil

	-- Cleanup Phase 2 synthetic items
	for _, id in ipairs({ OUT_CEIL, OUT_COOK_SAFE, OUT_R1, OUT_R2, OUT_R3, OUT_BIG, OUT_MIX, OUT_VLOOP, OUT_VDIP }) do
		mockVendorSell[id] = nil
		ns.ITEM_VENDOR_SELL[id] = nil
	end
	ns.VENDOR_REAGENTS[MAT_VBACK] = nil
	for _, id in ipairs({ MAT_CEIL, MAT_SH, MAT_R1, MAT_R2, MAT_R3, MAT_BIG, MAT_VBACK, MAT_AHMIX }) do
		clearAHItem(id)
	end
	ns.InvalidatePriceCache()
end

---------------------------------------------------------------------------------------------------
-- 4. UI & Host Integration
---------------------------------------------------------------------------------------------------
do
	-- Seed real catalog recipes so Vendor Crafter table renders realistic profitable rows
	-- Heavy Kodo Stew (12215, Cooking, numMade=2, sell=300 -> 900 avg at MC 5/5): 12204 x2 + 3713 x1 + 159 x1
	-- Tender Wolf Steak (18045, Cooking, numMade=1, sell=300 -> 450 avg at MC 5/5): 12208 x1 + 3713 x1
	-- Undermine Clam Chowder (16766, Cooking, numMade=2, sell=100 -> 300 avg at MC 5/5): 7974 x2 + 2692 x1 + 1179 x1
	-- Patterned Bronze Bracers (2868, Blacksmithing, sell=507): 2841 x5 + 3478 x2
	setAHItem(12204, 180, 190, 200, { { price = 180, qty = 120 }, { price = 240, qty = 80 } })
	setAHItem(12208, 160, 175, 40,  { { price = 160, qty = 25 },  { price = 250, qty = 15 } })
	setAHItem(7974,  60,  200, 6,   { { price = 60,  qty = 6 } })
	setAHItem(2841,  45,  48,  400, { { price = 45,  qty = 350 }, { price = 90,  qty = 50 } })
	setAHItem(3478,  25,  28,  200, { { price = 25,  qty = 180 }, { price = 60,  qty = 20 } })
	ns.InvalidatePriceCache()
	VC.ClearCache()

	local searchCalls = 0
	local origSearchAH = app.searchAH
	app.searchAH = function(...)
		searchCalls = searchCalls + 1
		if origSearchAH then return origSearchAH(...) end
	end

	app.panel:Show()
	local navBtn = app.ui.navBtns and app.ui.navBtns.vendor_crafter
	check(navBtn ~= nil, "app.ui.navBtns.vendor_crafter exists")
	navBtn:Click("LeftButton")
	check(app.activeTab == "vendor_crafter", "Clicking navBtns.vendor_crafter activates vendor_crafter tab")
	local view = app.ui.vendorCrafterView
	local tbl = app.ui.vendorCrafterTable
	local provider = app.vendorCrafterProvider or ns.VendorCrafter
	check(view ~= nil and view:IsShown(), "app.ui.vendorCrafterView is shown")
	check(tbl ~= nil and tbl.scrollBox ~= nil, "app.ui.vendorCrafterTable is created")
	check(provider ~= nil, "Vendor Crafter provider registered")

	-- Confirm rows are populated and every single displayed row satisfies strict avgProfit > 0
	local col = tbl.scrollBox._dp and tbl.scrollBox._dp:GetCollection() or {}
	check(#col >= 3, "Vendor Crafter displays seeded profitable recipes, got " .. tostring(#col))
	for _, row in ipairs(col) do
		check(type(row.avgProfit) == "number" and row.avgProfit > 0,
			"Every rendered Vendor Crafter row has strict avgProfit > 0: " .. tostring(row.name))
	end

	-- Verify fractional +0.3c displays "+<1c" in rendered table cell
	local firstFrame = tbl.scrollBox._frames and tbl.scrollBox._frames[1]
	check(firstFrame ~= nil and tbl.scrollBox._view and tbl.scrollBox._view._initFn,
		"Vendor Crafter scrollBox renders row frames via initializer")
	do
		local savedRow = firstFrame.data
		local fracRow = {}
		for k, v in pairs(savedRow) do fracRow[k] = v end
		fracRow.avgProfit = 0.3
		fracRow.minProfit = -2
		fracRow.maxProfit = 4
		tbl.scrollBox._view._initFn(firstFrame, fracRow)
		local avgCell = firstFrame.cellGroup and firstFrame.cellGroup.cellsByKey and firstFrame.cellGroup.cellsByKey.avgProfit
		check(avgCell ~= nil and avgCell.fs ~= nil, "avgProfit cell exists on rendered Vendor Crafter row")
		local avgText = plain(avgCell.fs:GetText())
		check(avgText == "+<1c", "Fractional avgProfit (0 < avgProfit < 0.5) renders as '+<1c', got '" .. tostring(avgText) .. "'")
		tbl.scrollBox._view._initFn(firstFrame, savedRow)
	end

	-- Legacy controls (masterChefBtn, barteringBtn, honoredBtn, moatFilterBtn) update DB & refresh rows
	check(view.masterChefBtn ~= nil, "view.masterChefBtn exists")
	check(view.barteringBtn ~= nil, "view.barteringBtn exists")
	check(view.honoredBtn ~= nil, "view.honoredBtn exists")
	check(view.moatFilterBtn ~= nil, "view.moatFilterBtn exists")

	local lastDDOpts, lastDDSelect
	local origOpenDD = Theme.OpenDropDown
	Theme.OpenDropDown = function(anchor, opts, cur, onSelect, width)
		lastDDOpts = opts
		lastDDSelect = onSelect
		if origOpenDD then return origOpenDD(anchor, opts, cur, onSelect, width) end
	end

	view.masterChefBtn:Click("LeftButton")
	check(type(lastDDOpts) == "table" and #lastDDOpts == 7 and type(lastDDSelect) == "function",
		"masterChefBtn opens dropdown with Auto + 0..5 options")
	lastDDSelect(5)
	check(MerchantMasterDB.vendorCrafterMasterChef == 5,
		"Selecting 5/5 in masterChefBtn updates MerchantMasterDB.vendorCrafterMasterChef == 5")
	view.masterChefBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterMasterChef == "auto",
		"Right-clicking masterChefBtn resets MerchantMasterDB.vendorCrafterMasterChef to 'auto'")

	lastDDOpts, lastDDSelect = nil, nil
	view.barteringBtn:Click("LeftButton")
	check(type(lastDDOpts) == "table" and #lastDDOpts == 4 and type(lastDDSelect) == "function",
		"barteringBtn opens dropdown with Auto + 0..2 options")
	lastDDSelect(2)
	check(MerchantMasterDB.vendorCrafterBartering == 2,
		"Selecting 2/2 in barteringBtn updates MerchantMasterDB.vendorCrafterBartering == 2")
	view.barteringBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterBartering == "auto",
		"Right-clicking barteringBtn resets MerchantMasterDB.vendorCrafterBartering to 'auto'")

	local prevHonored = MerchantMasterDB.vendorCrafterHonored == true
	view.honoredBtn:Click("LeftButton")
	check((MerchantMasterDB.vendorCrafterHonored == true) == (not prevHonored),
		"Clicking honoredBtn toggles MerchantMasterDB.vendorCrafterHonored")

	lastDDOpts, lastDDSelect = nil, nil
	view.moatFilterBtn:Click("LeftButton")
	check(type(lastDDOpts) == "table" and #lastDDOpts >= 6 and type(lastDDSelect) == "function",
		"moatFilterBtn opens dropdown with >=6 Buy Moat filter options (incl. vendor_loop & ah_only)")
	local sawVL, sawAH = false, false
	for _, opt in ipairs(lastDDOpts) do
		if opt.key == "vendor_loop" then sawVL = true end
		if opt.key == "ah_only" then sawAH = true end
	end
	check(sawVL and sawAH, "moatFilterBtn dropdown exposes vendor_loop and ah_only options")
	lastDDSelect("deep")
	check(MerchantMasterDB.vendorCrafterMoatFilter == "deep",
		"Selecting 'deep' in moatFilterBtn updates MerchantMasterDB.vendorCrafterMoatFilter")
	view.moatFilterBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterMoatFilter == "all",
		"Right-clicking moatFilterBtn resets MerchantMasterDB.vendorCrafterMoatFilter to 'all'")

	-- Stage B: 17 default columns including profitableCrafts & buyCeiling, minWidth + 268 <= 1320
	check(#tbl.columns == 17, "Vendor Crafter exposes 17 default columns, got " .. tostring(#tbl.columns))
	local colByKey = {}
	local sumMinW = 4
	for _, c in ipairs(tbl.columns) do
		colByKey[c.key] = c
		sumMinW = sumMinW + (c.minWidth or c.width or 0) + 5
	end
	check(colByKey.profitableCrafts ~= nil and colByKey.buyCeiling ~= nil,
		"17 default columns include profitableCrafts and buyCeiling")
	check(sumMinW + 268 <= 1320,
		"Default 17-column minimum width + 268px chrome fits <= 1320px, got " .. tostring(sumMinW + 268))

	-- Stage B: Row 3 Profit Maximizer controls (topNBtn, maxCraftsBtn, budgetBtn, topOnlyBtn, queuePlanBtn, planSummaryFs)
	check(view.planBar ~= nil and view.planBar:IsShown(), "Row 3 view.planBar exists and is shown")
	check(view.topNBtn ~= nil and view.maxCraftsBtn ~= nil and view.budgetBtn ~= nil
		and view.topOnlyBtn ~= nil and view.queuePlanBtn ~= nil and view.planSummaryFs ~= nil,
		"Row 3 Profit Maximizer controls and planSummaryFs exposed")

	lastDDOpts, lastDDSelect = nil, nil
	view.topNBtn:Click("LeftButton")
	check(type(lastDDOpts) == "table" and #lastDDOpts == 4 and type(lastDDSelect) == "function",
		"topNBtn opens dropdown with Top 5/10/20/All options")
	lastDDSelect(5)
	check(MerchantMasterDB.vendorCrafterTopN == 5, "Selecting Top 5 persists vendorCrafterTopN == 5")
	view.topNBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterTopN == 10, "Right-clicking topNBtn resets vendorCrafterTopN == 10")

	lastDDOpts, lastDDSelect = nil, nil
	view.maxCraftsBtn:Click("LeftButton")
	check(type(lastDDOpts) == "table" and #lastDDOpts >= 4 and type(lastDDSelect) == "function",
		"maxCraftsBtn opens craft cap dropdown")
	lastDDSelect(250)
	check(MerchantMasterDB.vendorCrafterMaxCrafts == 250, "Selecting Cap 250x persists vendorCrafterMaxCrafts == 250")
	view.maxCraftsBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterMaxCrafts == 0, "Right-clicking maxCraftsBtn resets vendorCrafterMaxCrafts == 0")

	lastDDOpts, lastDDSelect = nil, nil
	view.budgetBtn:Click("LeftButton")
	check(type(lastDDOpts) == "table" and #lastDDOpts >= 4 and type(lastDDSelect) == "function",
		"budgetBtn opens budget dropdown")
	lastDDSelect(500000)
	check(MerchantMasterDB.vendorCrafterBudget == 500000, "Selecting 50g persists vendorCrafterBudget == 500000")
	view.budgetBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterBudget == 0, "Right-clicking budgetBtn resets vendorCrafterBudget == 0")

	Theme.OpenDropDown = origOpenDD
	if Theme.CloseDropDown then Theme.CloseDropDown() end

	-- Top N Only toggle filters displayed table strictly to activePlan.byKey
	local activePlan = (provider.GetActivePlan and provider.GetActivePlan()) or view.activePlan
	check(type(activePlan) == "table" and activePlan == view.activePlan and (activePlan.recipeCount or 0) >= 1,
		"GetActivePlan / view.activePlan exposes populated live portfolio plan")
	check((view.planSummaryFs:GetText() or "") ~= "" and view.planSummaryFs:GetText() ~= "No active plan",
		"planSummaryFs displays populated plan summary: " .. tostring(view.planSummaryFs:GetText()))

	MerchantMasterDB.vendorCrafterTopN = 2
	app.refresh()
	view.topOnlyBtn:Click("LeftButton")
	check(MerchantMasterDB.vendorCrafterTopOnly == true, "Clicking topOnlyBtn enables vendorCrafterTopOnly")
	local topOnlyPlan = provider.GetActivePlan and provider.GetActivePlan() or view.activePlan
	local topOnlyCol = tbl.scrollBox._dp and tbl.scrollBox._dp:GetCollection() or {}
	check(#topOnlyCol == topOnlyPlan.recipeCount and #topOnlyCol <= 2,
		"topOnlyBtn filters rows strictly to Top-N activePlan entries, got " .. tostring(#topOnlyCol))
	for _, r in ipairs(topOnlyCol) do
		check(topOnlyPlan.byKey[r.key] ~= nil, "Every visible row under Top N Only belongs to activePlan.byKey")
	end

	-- + Queue Plan populates shared Shopping List cleanly & idempotently
	app.clearCraftingOrderQueue()
	if app.ui.shopModal then app.ui.shopModal:Hide() end
	view.queuePlanBtn:Click("LeftButton")
	check(app.ui.shopModal and app.ui.shopModal:IsShown(), "Clicking + Queue Plan opens Shopping List modal")
	local expectedQueued = {}
	for _, entry in ipairs(topOnlyPlan.entries) do
		local cdInfo = ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(entry.row.recipe or entry.row) or nil
		local isLongCD = cdInfo and (cdInfo.nominalSeconds or 0) >= 82800
		local want = isLongCD and math.min(1, math.floor(entry.crafts)) or math.floor(entry.crafts)
		expectedQueued[entry.key] = want
		check(app.getRecipeShoppingQty(entry.row) == want,
			string.format("Queue Plan queues exact craft count (%d) for %s, got %s",
				want, tostring(entry.row.name), tostring(app.getRecipeShoppingQty(entry.row))))
	end
	-- Second click is idempotent (quantities stay identical, not doubled)
	view.queuePlanBtn:Click("LeftButton")
	for _, entry in ipairs(topOnlyPlan.entries) do
		check(app.getRecipeShoppingQty(entry.row) == expectedQueued[entry.key],
			"Second + Queue Plan click is idempotent for " .. tostring(entry.row.name))
	end
	-- Also verify multi-craft (>1) queuing directly via queueVendorCrafterPlan on a non-cooldown seeded recipe
	app.clearCraftingOrderQueue()
	local multiRow = nil
	for _, r in ipairs(col) do
		local cdInfo = ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(r.recipe or r) or nil
		if not (cdInfo and (cdInfo.nominalSeconds or 0) >= 82800) then multiRow = r; break end
	end
	check(multiRow ~= nil, "Non-cooldown profitable recipe available for multi-craft queueVendorCrafterPlan check")
	local rq, cq = app.queueVendorCrafterPlan({ { row = multiRow, crafts = 12 } }, { silent = true })
	check(rq == 1 and cq == 12 and app.getRecipeShoppingQty(multiRow) == 12,
		"queueVendorCrafterPlan queues 12 crafts on non-cooldown recipe cleanly")
	local rq2, cq2 = app.queueVendorCrafterPlan({ { row = multiRow, crafts = 12 } }, { silent = true })
	check(rq2 == 1 and cq2 == 12 and app.getRecipeShoppingQty(multiRow) == 12,
		"Repeated queueVendorCrafterPlan call is idempotent (stays at 12, not 24)")
	if app.ui.shopModal then app.ui.shopModal:Hide() end
	app.clearCraftingOrderQueue()

	-- app.resetVendorCrafterFilters() restores all Phase 1 + Phase 2 defaults
	MerchantMasterDB.vendorCrafterMasterChef = 5
	MerchantMasterDB.vendorCrafterBartering = 2
	MerchantMasterDB.vendorCrafterHonored = true
	MerchantMasterDB.vendorCrafterMoatFilter = "deep"
	MerchantMasterDB.vendorCrafterYieldMode = "uniform"
	MerchantMasterDB.vendorCrafterSkillMin = 50
	MerchantMasterDB.vendorCrafterSkillMax = 250
	MerchantMasterDB.vendorCrafterTopN = 5
	MerchantMasterDB.vendorCrafterMaxCrafts = 500
	MerchantMasterDB.vendorCrafterBudget = 1000000
	MerchantMasterDB.vendorCrafterTopOnly = true
	app.resetVendorCrafterFilters()
	check(view.yieldModeBtn ~= nil, "Vendor Crafter Row 2 exposes yieldModeBtn")
	check(MerchantMasterDB.vendorCrafterMasterChef == "auto", "resetVendorCrafterFilters restores masterChef='auto'")
	check(MerchantMasterDB.vendorCrafterBartering == "auto", "resetVendorCrafterFilters restores bartering='auto'")
	check(MerchantMasterDB.vendorCrafterHonored == false, "resetVendorCrafterFilters restores honored=false")
	check(MerchantMasterDB.vendorCrafterMoatFilter == "all", "resetVendorCrafterFilters restores moatFilter='all'")
	check(MerchantMasterDB.vendorCrafterYieldMode == "auto", "resetVendorCrafterFilters restores yieldMode='auto'")
	MerchantMasterDB.vendorCrafterYieldMode = "min"
	view.yieldModeBtn:Click("RightButton")
	check(MerchantMasterDB.vendorCrafterYieldMode == "auto", "Right-click on yieldModeBtn resets vendorCrafterYieldMode to 'auto'")
	check(MerchantMasterDB.vendorCrafterSkillMin == nil and MerchantMasterDB.vendorCrafterSkillMax == nil,
		"resetVendorCrafterFilters clears skill min/max")
	check(MerchantMasterDB.vendorCrafterTopN == 10, "resetVendorCrafterFilters restores vendorCrafterTopN == 10")
	check(MerchantMasterDB.vendorCrafterMaxCrafts == 0, "resetVendorCrafterFilters restores vendorCrafterMaxCrafts == 0")
	check(MerchantMasterDB.vendorCrafterBudget == 0, "resetVendorCrafterFilters restores vendorCrafterBudget == 0")
	check(MerchantMasterDB.vendorCrafterTopOnly == false, "resetVendorCrafterFilters restores vendorCrafterTopOnly == false")

	-- Sorting triggers zero AH searches
	for _, sortCol in ipairs({ "avgProfit", "marginPct", "craftCost", "moatScore", "profitableCrafts", "totalProfitCap" }) do
		app.sortState.vendor_crafter.col = sortCol
		app.sortState.vendor_crafter.asc = false
		app.refresh()
	end
	app.sortState.vendor_crafter = { col = "avgProfit", asc = false }
	app.refresh()
	check(searchCalls == 0, "Opening, filtering, and sorting Vendor Crafter triggers 0 AH searches, got " .. tostring(searchCalls))

	-- Shift Quick-Add stepper adds/removes from shared Shopping List with 0 AH searches
	app.clearCraftingOrderQueue()
	local rowFrame, rowData
	for _, rf in ipairs((tbl.scrollBox and tbl.scrollBox._frames) or {}) do
		local rd = rf and rf.data
		if rd and not (ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(rd.recipe or rd)) then
			rowFrame, rowData = rf, rd
			break
		end
	end
	if not rowFrame then
		rowFrame = tbl.scrollBox._frames and tbl.scrollBox._frames[1]
		rowData = rowFrame and rowFrame.data
	end
	check(rowFrame ~= nil and rowData ~= nil, "First rendered non-cooldown Vendor Crafter row available for Shift Quick-Add")
	local origShift = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	if provider.SetShiftMode then provider.SetShiftMode(true) end
	check(rowFrame.shiftStepper ~= nil and rowFrame.shiftStepper:IsShown(), "Shift Quick-Add stepper shows in Shift mode")
	rowFrame.shiftStepper.plusBtn:Click("LeftButton")
	check(app.getRecipeShoppingQty(rowData) == 1, "Shift stepper + LeftClick adds 1 to shared Shopping List")
	rowFrame.shiftStepper.plusBtn:Click("RightButton")
	check(app.getRecipeShoppingQty(rowData) == 6, "Shift stepper + RightClick adds 5 to shared Shopping List")
	rowFrame.shiftStepper.minusBtn:Click("LeftButton")
	check(app.getRecipeShoppingQty(rowData) == 5, "Shift stepper - LeftClick subtracts 1")
	rowFrame.shiftStepper.minusBtn:Click("RightButton")
	check(app.getRecipeShoppingQty(rowData) == 0, "Shift stepper - RightClick removes all")
	_G.IsShiftKeyDown = origShift
	if provider.SetShiftMode then provider.SetShiftMode(false) end
	check(searchCalls == 0, "Shift Quick-Add triggers 0 AH searches, got " .. tostring(searchCalls))

	-- Right-clicking a Vendor Crafter row opens Deep Analysis with '< Back to Vendor Crafter'
	if rowData and rowData.recipe and ns.DeepAnalysis then
		rowFrame:Click("RightButton")
		check(app.activeTab == "deep_analysis" and app.ui.deepAnalysisView and app.ui.deepAnalysisView:IsShown(),
			"Right-click on Vendor Crafter row opens Deep Analysis tab")
		local retBtn = ns.DeepAnalysis.header and ns.DeepAnalysis.header.returnBtn
		local retTxt = retBtn and (retBtn.GetText and retBtn:GetText() or "") or ""
		check(retTxt:find("Vendor Crafter", 1, true) ~= nil,
			"Deep Analysis return button shows '< Back to Vendor Crafter', got: " .. tostring(retTxt))
		app.returnFromDeepAnalysis()
		check(app.activeTab == "vendor_crafter", "Returning from Deep Analysis restores Vendor Crafter tab")
		app.refresh()
	end

	-- Column customization persists to vendorCrafterColumns WITHOUT touching superListColumns
	local slHiddenBefore = MerchantMasterDB.superListColumns and MerchantMasterDB.superListColumns.hidden and MerchantMasterDB.superListColumns.hidden.wowheadURL
	local slOrder1Before = MerchantMasterDB.superListColumns and MerchantMasterDB.superListColumns.order and MerchantMasterDB.superListColumns.order[1]
	check(type(provider.SetColumnVisible) == "function" and type(provider.MoveColumn) == "function"
		and type(provider.ResetColumns) == "function", "Vendor Crafter column customization API exposed")
	local origColCount = #tbl.columns
	local hideKey = tbl.columns[origColCount].key
	check(provider.SetColumnVisible(hideKey, false), "SetColumnVisible hides last column")
	check(#tbl.columns == origColCount - 1, "Visible column count decremented after hide")
	check(MerchantMasterDB.vendorCrafterColumns and MerchantMasterDB.vendorCrafterColumns.hidden
		and MerchantMasterDB.vendorCrafterColumns.hidden[hideKey] == true,
		"Hidden column persisted to MerchantMasterDB.vendorCrafterColumns")
	local moveKey = tbl.columns[2].key
	check(provider.MoveColumn(moveKey, 1), "MoveColumn reorders column")
	check(MerchantMasterDB.vendorCrafterColumns and type(MerchantMasterDB.vendorCrafterColumns.order) == "table",
		"Column order persisted to MerchantMasterDB.vendorCrafterColumns")
	check(provider.ResetColumns(), "ResetColumns restores all default columns")
	check(#tbl.columns == origColCount, "Visible column count restored after ResetColumns")
	check(MerchantMasterDB.superListColumns.hidden.wowheadURL == slHiddenBefore
		and MerchantMasterDB.superListColumns.order[1] == slOrder1Before,
		"Vendor Crafter column customization does NOT touch MerchantMasterDB.superListColumns")

	-- Regression: Phase 1 saved 15-col order (collision in float colSum) aligns headers & cells on Refresh without column add/remove
	do
		local box = tbl.scrollBox
		local origBoxW = box.GetWidth
		local origHdrW = tbl.headerBar.GetWidth
		local origParentW = app.ui.mainArea and app.ui.mainArea.GetWidth
		box.GetWidth = function() return 1576 end
		tbl.headerBar.GetWidth = function() return 1576 end
		if app.ui.mainArea then app.ui.mainArea.GetWidth = function() return 1600 end end
		local okAlign, errAlign = pcall(function()
			provider.ResetColumns()
			provider.Layout(1600, 760)
			MerchantMasterDB.vendorCrafterColumns = {
				order = {
					"name", "knownSort", "cdSort", "craftCost", "minVendor", "avgVendor", "maxVendor",
					"avgProfit", "marginPct", "moatScore", "totalProfitCap", "requiredSkill",
					"sourceLabel", "buyCostCopper", "wowheadURL",
				},
				hidden = {},
			}
			app.refresh()
			check(#tbl.columns == 17 and tbl.columns[16].key == "profitableCrafts" and tbl.columns[17].key == "buyCeiling",
				"Saved 15-col Phase 1 config appends Phase 2 columns to 16..17 cleanly")
			check(tbl.columns[1].width > 128,
				"Reordered 17-col Vendor Crafter expands columns rather than keeping base width")
			local checkedRow = false
			for i = 1, #tbl.columns do
				local hb = tbl.headerBtns[i]
				local _, _, _, hx = hb:GetPoint(1)
				check(hx == tbl.colX[i] and hb:GetWidth() == tbl.columns[i].width,
					"Vendor Crafter header " .. i .. " aligns to colX and computed width after startup config sync")
			end
			for _, rf in ipairs(box._frames or {}) do
				if rf:IsShown() and rf.cells then
					checkedRow = true
					for i = 1, #tbl.columns do
						local cell = rf.cells[i]
						local _, _, _, cx = cell:GetPoint(1)
						check(cx == tbl.colX[i] and cell:GetWidth() == tbl.columns[i].width,
							"Vendor Crafter row cell " .. i .. " aligns to colX and header width without toggling columns")
					end
				end
			end
			check(checkedRow, "At least one rendered Vendor Crafter row verified for header/cell alignment")
		end)
		box.GetWidth = origBoxW
		tbl.headerBar.GetWidth = origHdrW
		if app.ui.mainArea then app.ui.mainArea.GetWidth = origParentW end
		provider.ResetColumns()
		if not okAlign then error(errAlign, 0) end
	end

	-- Dark / Light / Warcraft skin switching works cleanly
	Theme.SetMode("light")
	app.refresh()
	check(Theme.GetMode() == "light" and view:IsShown(), "Light mode renders Vendor Crafter cleanly")
	Theme.SetMode("dark")
	app.refresh()
	check(Theme.GetMode() == "dark" and view:IsShown(), "Dark mode renders Vendor Crafter cleanly")
	if _G.MerchantMasterAPI and _G.MerchantMasterAPI.SetSkin then
		for _, sk in ipairs({ "human", "goblin", "night_elf", "standard" }) do
			_G.MerchantMasterAPI.SetSkin(sk)
			app.refresh()
			check(Theme.GetSkin() == sk and view:IsShown(), "Warcraft skin '" .. sk .. "' switches cleanly on Vendor Crafter")
		end
	end

	-- Variable yield range + Ledger measured yields + End-to-end buy-cap flow to Shopping Cart & CartBuyer
	do
		local Store = _G.MerchantMasterAnalytics and _G.MerchantMasterAnalytics.Store
		check(Store and type(Store.RecordCraftYield) == "function", "Analytics Store.RecordCraftYield exposed")
		local oldLedger = _G.MerchantMasterLedgerDB
		_G.MerchantMasterLedgerDB = {}
		Store.Init()
		MerchantMasterDB.craftOrderQueue = {}

		local hdRec
		for _, rec in ipairs(ns.RECIPES or {}) do
			if rec.spellID == 3946 then hdRec = rec; break end
		end
		check(hdRec and hdRec.outputItemID == 4378, "Heavy Dynamite (spell 3946 -> item 4378) exists in RECIPES")
		ns.RecordRecipeYieldRange(3946, 1, 5)
		local rLo, rHi = ns.ResolveRecipeYieldRange(hdRec)
		check(rLo == 1 and rHi == 5, "RecordRecipeYieldRange stores 1..5 yield range on spell 3946")

		-- Powder (4377): 2x/craft; Wool Cloth (2592): 1x/craft; Heavy Dynamite (4378) sells 350c
		-- Cheap lots support 10 crafts @ 400c (1050c avg vendor); next tier jumps to 2*500 + 600 = 1600c (loss)
		setAHItem(4377, 150, 150, 40, { { price = 150, qty = 20 }, { price = 500, qty = 20 } })
		setAHItem(2592, 100, 100, 20, { { price = 100, qty = 10 }, { price = 600, qty = 10 } })
		ns.InvalidatePriceCache()
		VC.ClearCache()

		local rVar = VC.EvaluateRecipe(hdRec, { economy = econKey, subCraftMode = "buy", yieldMode = "auto" }, { masterChef = 0, bartering = 0, honored = false }, {})
		check(rVar ~= nil, "Heavy Dynamite variable-yield evaluation returns row")
		check(rVar.isVariableYield == true and rVar.minMade == 1 and rVar.maxMade == 5,
			"Variable yield metadata sets isVariableYield=true and minMade=1..maxMade=5")
		check(rVar.yieldSource == "uniform", "0 Ledger casts (<10) falls back to uniform yieldSource")
		check(rVar.minVendor == 350 and rVar.avgVendor == 1050 and rVar.maxVendor == 1750,
			string.format("1..5 range yields min=350 avg=1050 max=1750 (got %s/%s/%s)",
				tostring(rVar.minVendor), tostring(rVar.avgVendor), tostring(rVar.maxVendor)))
		check(rVar.reagentBuyCaps and rVar.reagentBuyCaps[4377] and rVar.reagentBuyCaps[2592],
			"EvaluateRecipe populates reagentBuyCaps for Powder (4377) and Cloth (2592)")
		check(rVar.reagentBuyCaps[4377].maxBuyUnit == 150 and (rVar.reagentBuyCaps[4377].breakEvenUnit or 0) > 150,
			"Powder buy cap captures profitable ceiling 150c and higher breakEvenUnit")
		check(rVar.reagentBuyCaps[2592].maxBuyUnit == 100 and (rVar.reagentBuyCaps[2592].breakEvenUnit or 0) > 100,
			"Wool Cloth buy cap captures profitable ceiling 100c and higher breakEvenUnit")

		-- Record 10 casts in Ledger with measured avg 2.6 (26 items / 10 casts)
		Store.RecordCraftYield(3946, 4378, 26, 10, { 1, 2, 2, 2, 2, 3, 3, 3, 4, 4 })
		VC.ClearCache()

		local rMeas = VC.EvaluateRecipe(hdRec, { economy = econKey, subCraftMode = "buy", yieldMode = "auto" }, { masterChef = 0, bartering = 0, honored = false }, {})
		check(rMeas and rMeas.yieldSource == "measured" and rMeas.yieldSamples == 10,
			"10 Ledger casts activates yieldSource='measured'")
		approx(rMeas.yieldMeasuredAvg, 2.6, 0.001, "Measured yield avg is 2.6")
		check(rMeas.avgVendor == 910, "Measured avgVendor is floor(2.6 * 350 + 0.5) = 910c (got " .. tostring(rMeas.avgVendor) .. ")")
		check(rMeas.minVendor == 350 and rMeas.maxVendor == 1750, "Measured mode preserves 1..5 minVendor/maxVendor range")
		check(rMeas.yieldHist and rMeas.yieldHist[2] == 4, "Row exposes Ledger yieldHist histogram")

		-- UI row cell check: variable yield inline badge [1-5x 2.60x (10)] and red minVendor when minProfit < 0
		if app.ui and app.ui.searchBox and app.ui.searchBox.SetText then
			app.ui.searchBox:SetText("Heavy Dynamite")
		end
		MerchantMasterDB.vendorCrafterYieldMode = "auto"
		app.refresh()
		local hdFrame
		for _, rf in ipairs(tbl.scrollBox._frames or {}) do
			if rf:IsShown() and rf.data and rf.data.spellID == 3946 then hdFrame = rf; break end
		end
		if hdFrame and hdFrame.cells then
			local nameIdx, minIdx
			for idx, c in ipairs(tbl.columns or {}) do
				if c.key == "name" then nameIdx = idx
				elseif c.key == "minVendor" then minIdx = idx end
			end
			if nameIdx then
				local nTxt = hdFrame.cells[nameIdx].fs:GetText() or ""
				check(nTxt:find("[1-5x 2.60x (10)]", 1, true) ~= nil,
					"Vendor Crafter UI name cell shows measured variable-yield badge [1-5x 2.60x (10)]: " .. tostring(nTxt))
			end
			if minIdx and hdFrame.data.minProfit < 0 then
				local pal = Theme.GetActivePalette and Theme.GetActivePalette() or nil
				local expRed = (pal and pal.accentRed) or { 1.0, 0.26, 0.27 }
				local tc = hdFrame.cells[minIdx]._textColor
				check(tc and math.abs(tc[1] - expRed[1]) < 0.05 and math.abs(tc[2] - expRed[2]) < 0.05,
					"Min Vendor cell tints red when 1x roll loses gold (minProfit < 0)")
			end
		end
		if app.ui and app.ui.searchBox and app.ui.searchBox.SetText then
			app.ui.searchBox:SetText("")
		end

		local rUni = VC.EvaluateRecipe(hdRec, { economy = econKey, subCraftMode = "buy", yieldMode = "uniform" }, { masterChef = 0, bartering = 0, honored = false }, {})
		check(rUni and rUni.yieldSource == "uniform" and rUni.avgVendor == 1050, "yieldMode='uniform' forces uniform 3.0x avgVendor=1050c")
		local rMinNil = VC.EvaluateRecipe(hdRec, { economy = econKey, subCraftMode = "buy", yieldMode = "min" }, { masterChef = 0, bartering = 0, honored = false }, {})
		check(rMinNil == nil, "yieldMode='min' filters out unprofitable craft (-50c at 350c minVendor vs 400c craftCost)")
		setAHItem(4377, 100, 100, 40)
		setAHItem(2592, 50, 50, 20)
		ns.InvalidatePriceCache()
		VC.ClearCache()
		local rMin = VC.EvaluateRecipe(hdRec, { economy = econKey, subCraftMode = "buy", yieldMode = "min" }, { masterChef = 0, bartering = 0, honored = false }, {})
		check(rMin and rMin.yieldSource == "min" and rMin.avgVendor == 350, "yieldMode='min' forces conservative 1.0x avgVendor=350c when profitable")
		setAHItem(4377, 150, 150, 40, { { price = 150, qty = 20 }, { price = 500, qty = 20 } })
		setAHItem(2592, 100, 100, 20, { { price = 100, qty = 10 }, { price = 600, qty = 10 } })
		ns.InvalidatePriceCache()
		VC.ClearCache()

		-- Cooking + Master Chef 5/5 (masterChef=5 -> +50% proc chance) with measured yields must NOT double-multiply Master Chef
		local cookRec
		for _, rec in ipairs(ns.RECIPES or {}) do
			if rec.prof == "cooking" and rec.spellID and rec.spellID > 0 and rec.outputItemID
				and type(rec.reagents) == "table" and #rec.reagents == 1 then
				local v = ns.GetVendorSellPrice(rec.outputItemID) or 0
				local q = rec.reagents[1][2] or rec.reagents[1].qty or 1
				if v > q then
					cookRec = rec
					break
				end
			end
		end
		check(cookRec ~= nil, "Found 1-reagent cooking recipe")
		if cookRec then
			local vSell = ns.GetVendorSellPrice(cookRec.outputItemID)
			local rItemID = cookRec.reagents[1][1] or cookRec.reagents[1].itemID
			setAHItem(rItemID, 1, 1, 100, { { price = 1, qty = 100 } })
			ns.InvalidatePriceCache()
			Store.RecordCraftYield(cookRec.spellID, cookRec.outputItemID, 12, 10, { 1, 1, 1, 1, 1, 1, 1, 1, 2, 2 })
			VC.ClearCache()
			local rCookUni = VC.EvaluateRecipe(cookRec, { economy = econKey, subCraftMode = "buy", yieldMode = "uniform" }, { masterChef = 5, bartering = 0, honored = false }, {})
			local rCookMeas = VC.EvaluateRecipe(cookRec, { economy = econKey, subCraftMode = "buy", yieldMode = "auto" }, { masterChef = 5, bartering = 0, honored = false }, {})
			local cookBase = tonumber(cookRec.numMade) or 1
			check(rCookUni ~= nil, "Cooking uniform evaluation returns profitable row")
			approx(rCookUni.avgVendor, cookBase * 1.5 * vSell, 0.01,
				"Cooking uniform mode applies Master Chef 5/5 (+50%) proc multiplier")
			check(rCookMeas and rCookMeas.yieldSource == "measured",
				"Cooking auto mode uses Ledger measured yields at >=10 casts")
			approx(rCookMeas.avgVendor, 1.2 * vSell, 0.01,
				"Cooking measured mode uses 1.2x Ledger avg without double-applying Master Chef")
			clearAHItem(rItemID)
		end

		-- End-to-end: OptimizePortfolio -> queueVendorCrafterPlan -> BuildUnifiedShoppingList -> sendShoppingRowsToAuctionator -> CartBuyer
		local plan = VC.OptimizePortfolio({ rVar }, { topN = 10, econKey = econKey })
		check(plan and plan.buyCapsByItemID and plan.buyCapsByItemID[4377]
			and plan.buyCapsByItemID[4377].maxBuyUnit == 150,
			"OptimizePortfolio aggregates buyCapsByItemID[4377].maxBuyUnit == 150")
		check(plan.entries and plan.entries[1] and plan.entries[1].crafts == 10
			and plan.entries[1].reagentBuyCaps and plan.entries[1].reagentBuyCaps[4377].maxBuyUnit == 150,
			"OptimizePortfolio entry preserves per-reagent buy caps")

		local rqCount, craftCount = app.queueVendorCrafterPlan(plan.entries, { replace = true, silent = true })
		check(rqCount == 1 and craftCount == 10, "queueVendorCrafterPlan queues 1 recipe / 10 crafts")
		check(MerchantMasterDB.craftOrderQueue[1] and MerchantMasterDB.craftOrderQueue[1].buyCaps
			and MerchantMasterDB.craftOrderQueue[1].buyCaps[4377].maxBuyUnit == 150,
			"craftOrderQueue persists buyCaps metadata")

		-- delta == 0 re-queue refreshes buyCaps
		local updatedCapEntry = {
			row = rVar,
			crafts = 10,
			reagentBuyCaps = {
				[4377] = { maxBuyUnit = 140, breakEvenUnit = 475, wallUnit = 500, avgBuyUnit = 140, source = "vendor_crafter" },
				[2592] = rVar.reagentBuyCaps[2592],
			},
		}
		app.queueVendorCrafterPlan({ updatedCapEntry }, { replace = false, silent = true })
		check(MerchantMasterDB.craftOrderQueue[1].buyCaps[4377].maxBuyUnit == 140,
			"Re-queuing existing recipe with delta == 0 refreshes buyCaps")

		-- Restore 150 cap cleanly and trace through BuildUnifiedShoppingList -> CartBuyer
		app.queueVendorCrafterPlan(plan.entries, { replace = true, silent = true })
		local shopRows = ns.BuildUnifiedShoppingList(MerchantMasterDB, { subCraftMode = "buy" })
		local powderRow
		for _, sr in ipairs(shopRows or {}) do
			if sr.itemID == 4377 and not sr.makeMyself then powderRow = sr; break end
		end
		check(powderRow ~= nil, "BuildUnifiedShoppingList emits leaf row for Heavy Blasting Powder (4377)")
		check(powderRow.maxBuyUnit == 150 and (powderRow.breakEvenUnit or 0) > 150,
			"Shopping row carries maxBuyUnit == 150 and breakEvenUnit > 150 from buyCaps")

		local origAHFrame = _G.AuctionHouseFrame
		local origC_AH = _G.C_AuctionHouse
		local origCBSrc = app.searchAH
		local mockAHShown = { IsShown = function() return true end, IsVisible = function() return true end, Show = function() end }
		local mockCommResults = { [4377] = { { unitPrice = 600, quantity = 40 } } }
		_G.AuctionHouseFrame = mockAHShown
		_G.C_AuctionHouse = {
			GetNumCommoditySearchResults = function(id) return mockCommResults[id] and #mockCommResults[id] or 0 end,
			GetCommoditySearchResultInfo = function(id, idx) return mockCommResults[id] and mockCommResults[id][idx] or nil end,
		}
		app.searchAH = function() return true end
		app.sendShoppingRowsToBuyer(shopRows, "Vendor Crafter Plan")
		local cbState = app.cartBuyer and app.cartBuyer.GetState and app.cartBuyer.GetState()
		local cbPowder, cbPowderIdx
		for idx, ci in ipairs((cbState and cbState.items) or {}) do
			if ci.itemID == 4377 then cbPowder = ci; cbPowderIdx = idx; break end
		end
		check(cbPowder and cbPowderIdx and cbPowder.maxBuyUnit == 150 and (cbPowder.breakEvenUnit or 0) > 150,
			"CartBuyer item inherits maxBuyUnit == 150 and breakEvenUnit > 150")

		app.cartBuyer.SelectItem(cbPowderIdx)
		ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 4377)
		check(cbPowder.liveUnit == 600 and cbPowder.overBuyCap == true and cbPowder.buyCapMarginCopper == -450,
			"CartBuyer flags overBuyCap=true and margin=-450 when live AH (600c) exceeds maxBuyUnit (150c)")

		mockCommResults[4377] = { { unitPrice = 120, quantity = 40 } }
		ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 4377)
		check(cbPowder.liveUnit == 120 and cbPowder.overBuyCap == false and cbPowder.buyCapMarginCopper == 30,
			"CartBuyer flags overBuyCap=false and margin=+30 when live AH (120c) is within maxBuyUnit (150c)")

		if app.ui and app.ui.cartBuyerModal and app.ui.cartBuyerModal.Hide then
			app.ui.cartBuyerModal:Hide()
		end
		app.searchAH = origCBSrc
		_G.C_AuctionHouse = origC_AH
		_G.AuctionHouseFrame = origAHFrame
		_G.MerchantMasterLedgerDB = oldLedger
		Store.Init()
		MerchantMasterDB.craftOrderQueue = {}
		clearAHItem(4377)
		clearAHItem(2592)
		ns.InvalidatePriceCache()
		VC.ClearCache()
	end

	check(searchCalls == 0, "Full Vendor Crafter UI & skin pass triggers 0 AH searches")
	app.searchAH = origSearchAH
	for _, id in ipairs({ 12204, 12208, 7974, 2841, 3478 }) do clearAHItem(id) end
	ns.InvalidatePriceCache()
	VC.ClearCache()

	-- Regressions: Bug 1 (reconcilePending + Cancel hang), Bug 2 (3-tier priority + mid-scan reprioritization), Bug 3 (reset-to-0 immunity & in-place item repair)
	do
		local vcProv = app.vendorCrafterProvider
		check(vcProv ~= nil, "vendorCrafterProvider registered for regression checks")
		local savedGetProfs = ns.GetPlayerProfessions
		local savedAfter = C_Timer.After
		local savedStart = VC.Start
		local savedEval = VC.EvaluateRecipe
		local savedRepair = VC.RepairItems
		local savedProfFilter = MerchantMasterDB.profFilter
		local savedKnownOnly = MerchantMasterDB.knownRecipesOnly
		local savedUnlock = MerchantMasterDB.unlockFilter
		local savedSearch = app.ui.searchBox and app.ui.searchBox:GetText() or ""

		local mockProfs = { alchemy = 280, enchanting = 300 }
		ns.GetPlayerProfessions = function()
			local copy = {}
			for k, v in pairs(mockProfs) do copy[k] = v end
			return copy
		end

		local vcQueued = {}
		C_Timer.After = function(_, fn) vcQueued[#vcQueued + 1] = fn end
		local function drainVC(limit)
			local steps = 0
			local cap = limit or 20000
			while #vcQueued > 0 do
				local fn = table.remove(vcQueued, 1)
				fn()
				steps = steps + 1
				assert(steps < cap, "VC regression runaway timer queue")
			end
			return steps
		end

		local vcStarts, repairCalls = 0, 0
		local evalOrder = {}
		local evalSeen = {}
		VC.Start = function(...)
			vcStarts = vcStarts + 1
			return savedStart(...)
		end
		VC.EvaluateRecipe = function(rec, ...)
			if rec then
				evalOrder[#evalOrder + 1] = rec.prof or "?"
				evalSeen[rec] = (evalSeen[rec] or 0) + 1
			end
			return savedEval(rec, ...)
		end
		VC.RepairItems = function(...)
			repairCalls = repairCalls + 1
			return savedRepair(...)
		end

		local ok, err = pcall(function()
			-- Seed profitable craft so VC has rows
			setAHItem(2841, 1, 1, 200, { { price = 1, qty = 200 } })
			setAHItem(3478, 1, 1, 200, { { price = 1, qty = 200 } })
			ns.InvalidatePriceCache()

			-- 1. Bug 3: Mid-scan invalidation storm (items, ownership, skills, known, rep, cooldown, trainer, snapshot) NEVER resets scan to 0!
			MerchantMasterDB.profFilter = "all"
			MerchantMasterDB.knownRecipesOnly = false
			MerchantMasterDB.unlockFilter = "all"
			if app.ui.searchBox then app.ui.searchBox:SetText("") end
			app.panel:Hide()
			vcProv.Invalidate()
			drainVC()
			vcStarts, evalOrder, evalSeen = 0, {}, {}
			app.activeTab = "vendor_crafter"
			app.panel:Show()
			-- Step until scan has started partially
			local guard = 0
			while #vcQueued > 0 and #evalOrder == 0 and guard < 200 do
				table.remove(vcQueued, 1)()
				guard = guard + 1
			end
			check(vcStarts == 1 and #evalOrder > 0 and #evalOrder < #ns.RecipeStats.GetCatalog(),
				"VC scan started partially (" .. tostring(#evalOrder) .. " evals)")
			local midCount = #evalOrder
			vcProv.Invalidate("items", { [2841] = true })
			vcProv.Invalidate("ownership")
			vcProv.Invalidate("skills")
			vcProv.Invalidate("known")
			vcProv.Invalidate("rep")
			vcProv.Invalidate("cooldown")
			vcProv.Invalidate("trainer")
			vcProv.Invalidate("snapshot")
			drainVC()
			check(vcStarts == 1, "Mid-scan non-economic invalidations cause 0 VC.Start restarts (starts=" .. tostring(vcStarts) .. ")")
			check(#evalOrder >= midCount, "Mid-scan non-economic invalidations do not reset scan progress")
			check(repairCalls >= 1, "Deferred items invalidation ran VC.RepairItems in-place after scan completed (calls=" .. tostring(repairCalls) .. ")")

			-- 2. Bug 3: knownRecipesOnly toggle, profMap rank bump, and non-yield Ledger writes do NOT restart VC.Start
			local startsSteady = vcStarts
			MerchantMasterDB.knownRecipesOnly = true
			app.refresh(); drainVC()
			MerchantMasterDB.knownRecipesOnly = false
			app.refresh(); drainVC()
			check(vcStarts == startsSteady, "knownRecipesOnly toggle does not restart Vendor Crafter scan")

			mockProfs.alchemy = 300
			vcProv.Invalidate("skills")
			app.refresh(); drainVC()
			check(vcStarts == startsSteady, "Profession rank bump 280->300 does not restart Vendor Crafter scan")

			local Store = ns.Analytics and ns.Analytics.Store
			if Store then
				if not Store.initialized then Store.Init() end
				Store.AddLoot(2447, "Mob", "VC Test", 1)
				Store.AddBasis(econKey, 2447, 1, 10)
				Store.Append({ type = "VENDOR_SELL", itemID = 2447, qty = 1, unit = 10, total = 10, where = "VC Test" })
				Store.Append({ type = "AH_BUY", itemID = 2447, qty = 1, unit = 10, total = 10, where = "VC Test" })
				app.refresh(); drainVC()
				check(vcStarts == startsSteady, "Non-yield Ledger writes (AddLoot/AddBasis/VENDOR_SELL/AH_BUY) do not restart Vendor Crafter scan")
			end

			-- Post-scan items invalidation runs VC.RepairItems without restarting VC.Start
			local repairsBefore = repairCalls
			vcProv.Invalidate("items", { [2841] = true })
			drainVC()
			check(vcStarts == startsSteady and repairCalls == repairsBefore + 1,
				"Post-scan Invalidate('items') repairs Vendor Crafter in-place with 0 full scan restarts")

			-- Learning a new profession key DOES trigger 1 clean rebuild
			mockProfs.tailoring = 300
			app.refresh(); drainVC()
			check(vcStarts == startsSteady + 1, "Learning a new profession key triggers 1 clean Vendor Crafter rebuild")
			mockProfs.tailoring = nil

			-- 3. Bug 1: reconcilePending + Cancel() (panel Hide/Show) never hangs Vendor Crafter on stale search
			app.ui.searchBox._text = "zzzz-no-match"
			app.ui.searchBox:GetScript("OnTextChanged")(app.ui.searchBox, false)
			drainVC()
			local vcBox = app.ui.vendorCrafterTable.scrollBox
			check(vcBox._dp and #vcBox._dp:GetCollection() == 0, "VC search filters to 0 rows")
			app.setTab("dashboard"); drainVC()
			app.ui.searchBox._mmClearBtn:GetScript("OnClick")(app.ui.searchBox._mmClearBtn)
			vcProv.Invalidate("ownership")
			app.panel:Hide()
			app.panel:Show()
			app.setTab("vendor_crafter")
			drainVC()
			check(vcBox._dp and #vcBox._dp:GetCollection() > 0,
				"VC Invalidate('ownership') + panel Hide/Show never hangs on stale search")

			-- 4. Bug 2: 3-tier priority (selected profFilter -> my profs -> rest) + mid-scan reprioritization with 0 duplicates
			MerchantMasterDB.profFilter = "tailoring"
			app.panel:Hide()
			vcProv.Invalidate(); drainVC()
			vcStarts, evalOrder, evalSeen = 0, {}, {}
			app.activeTab = "vendor_crafter"
			app.panel:Show()
			drainVC()
			local tailCount = 0
			for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
				if entry.recipe.prof == "tailoring" then tailCount = tailCount + 1 end
			end
			check(tailCount > 0 and #evalOrder == #ns.RecipeStats.GetCatalog(), "VC 3-tier scan evaluated full catalog")
			for i = 1, tailCount do
				check(evalOrder[i] == "tailoring", "VC Tier 1 evaluates selected profFilter='tailoring' first at " .. i)
			end
			local mineSet = { alchemy = true, enchanting = true }
			local mineCnt = 0
			for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
				if mineSet[entry.recipe.prof] then mineCnt = mineCnt + 1 end
			end
			for i = tailCount + 1, tailCount + mineCnt do
				check(mineSet[evalOrder[i]] == true, "VC Tier 2 evaluates my profs second at " .. i)
			end

			-- Mid-scan profFilter switch reprioritizes without restarting or duplicating
			MerchantMasterDB.profFilter = "all"
			app.panel:Hide()
			vcProv.Invalidate(); drainVC()
			vcStarts, evalOrder, evalSeen = 0, {}, {}
			app.activeTab = "vendor_crafter"
			app.panel:Show()
			guard = 0
			while #vcQueued > 0 and #evalOrder == 0 and guard < 200 do
				table.remove(vcQueued, 1)()
				guard = guard + 1
			end
			local beforeMid = #evalOrder
			MerchantMasterDB.profFilter = "blacksmithing"
			app.refresh()
			drainVC()
			check(vcStarts == 1, "VC mid-scan profFilter switch reprioritizes with 0 restarts")
			check(evalOrder[beforeMid + 1] == "blacksmithing", "VC next eval after mid-scan switch is blacksmithing")
			for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
				check(evalSeen[entry.recipe] == 1, "VC mid-scan reprioritization evaluates every recipe exactly once")
			end

			-- 5. Background pre-warming, CancelPresentation demotion, and 8-entry LRU filter cache (Vendor Crafter & All Recipes)
			do
				local savedVCFilterSort = VC.FilterSort
				local savedVCOptimize = VC.OptimizePortfolio
				local savedSLFilterSort = ns.SuperListModel.FilterSort
				local savedOnSLWarmComplete = app.onSuperListWarmComplete
				local vcSorts, vcPlans, slSorts, slWarmHookCalls = 0, 0, 0, 0
				VC.FilterSort = function(...) vcSorts = vcSorts + 1; return savedVCFilterSort(...) end
				VC.OptimizePortfolio = function(...) vcPlans = vcPlans + 1; return savedVCOptimize(...) end
				ns.SuperListModel.FilterSort = function(...) slSorts = slSorts + 1; return savedSLFilterSort(...) end
				app.onSuperListWarmComplete = function(...)
					slWarmHookCalls = slWarmHookCalls + 1
					if savedOnSLWarmComplete then return savedOnSLWarmComplete(...) end
				end

				local okSpeed, errSpeed = pcall(function()
					-- (a) vcProvider.WarmInBackground warms buildState + pre-populates retainedResult & retainedPlan
					MerchantMasterDB.profFilter = "all"
					MerchantMasterDB.knownRecipesOnly = false
					MerchantMasterDB.unlockFilter = "all"
					if app.ui.searchBox then app.ui.searchBox:SetText("") end
					app.panel:Hide()
					vcProv.Invalidate()
					drainVC()
					vcStarts, evalOrder, evalSeen = 0, {}, {}
					vcSorts, vcPlans = 0, 0
					app.activeTab = "dashboard"
					app.panel:Show()
					vcQueued = {}
					check(type(vcProv.WarmInBackground) == "function" and type(vcProv.IsWarming) == "function"
						and type(vcProv.HasWarmData) == "function",
						"vcProvider exposes WarmInBackground, IsWarming, and HasWarmData")
					vcProv.WarmInBackground(app.buildVendorCrafterContext())
					check(vcProv.IsWarming() == true and vcProv.HasWarmData() == true,
						"vcProvider.WarmInBackground starts background build (IsWarming & HasWarmData true)")
					drainVC()
					check(vcProv.HasWarmData() == true and vcProv.IsWarming() == false,
						"vcProvider finishes background warm cleanly")
					check(vcSorts > 0 and vcPlans == 1,
						"vcProvider.WarmInBackground pre-runs FilterSort and OptimizePortfolio in background")
					check(vcProv.GetActivePlan() ~= nil,
						"vcProvider.WarmInBackground pre-populates active portfolio plan")

					-- First open of Vendor Crafter binds synchronously in 1 call (zero Loading/Filtering delay)
					vcBox._dp = nil
					local sortsBeforeOpen, plansBeforeOpen = vcSorts, vcPlans
					vcQueued = {}
					app.activeTab = "vendor_crafter"
					vcProv.Refresh(app.buildVendorCrafterContext())
					check(#vcQueued == 0, "First Vendor Crafter Refresh after WarmInBackground queues 0 timers (synchronous)")
					check(vcSorts == sortsBeforeOpen and vcPlans == plansBeforeOpen,
						"First Vendor Crafter Refresh after WarmInBackground runs 0 extra FilterSort/OptimizePortfolio calls")
					check(vcBox._dp ~= nil and #vcBox._dp:GetCollection() > 0,
						"First Vendor Crafter Refresh after WarmInBackground binds rows synchronously in 1 call")
					local sumTxt = (view.summary and view.summary:GetText()) or ""
					check(not sumTxt:find("Scanning", 1, true) and not sumTxt:find("Filtering", 1, true) and not sumTxt:find("Loading", 1, true),
						"First Vendor Crafter open has no Scanning/Filtering/Loading status text: " .. tostring(sumTxt))

					-- (b) vcProvider.CancelPresentation() keeps background build running instead of discarding it
					app.panel:Hide()
					vcProv.Invalidate()
					drainVC()
					vcStarts, evalOrder, evalSeen = 0, {}, {}
					app.activeTab = "vendor_crafter"
					app.panel:Show()
					guard = 0
					while #vcQueued > 0 and #evalOrder == 0 and guard < 200 do
						table.remove(vcQueued, 1)()
						guard = guard + 1
					end
					check(vcProv.IsWarming() == true and #evalOrder > 0 and #evalOrder < #ns.RecipeStats.GetCatalog(),
						"VC scan is mid-flight before CancelPresentation")
					app.activeTab = "dashboard"
					vcProv.CancelPresentation()
					check(vcProv.IsWarming() == true and vcProv.HasWarmData() == true and #vcQueued > 0,
						"vcProvider.CancelPresentation keeps background build running instead of cancelling progress")
					drainVC()
					check(vcStarts == 1 and vcProv.HasWarmData() == true and vcProv.IsWarming() == false,
						"Demoted VC build finishes in background with 0 restarts")
					for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
						check(evalSeen[entry.recipe] == 1, "Demoted VC build evaluates every recipe once")
					end
					vcQueued = {}
					vcBox._dp = nil
					app.activeTab = "vendor_crafter"
					vcProv.Refresh(app.buildVendorCrafterContext())
					check(#vcQueued == 0 and vcBox._dp ~= nil and #vcBox._dp:GetCollection() > 0,
						"Returning to Vendor Crafter after demoted build completes binds synchronously in 1 call")

					-- (c) 8-entry LRU filter cache: Vendor Crafter instant synchronous toggle between two filters
					local allVCCount = #vcBox._dp:GetCollection()
					MerchantMasterDB.profFilter = "blacksmithing"
					vcProv.Refresh(app.buildVendorCrafterContext())
					drainVC()
					local bsVCCount = vcBox._dp and #vcBox._dp:GetCollection() or 0
					check(bsVCCount ~= allVCCount, "VC blacksmithing filter produces distinct count from all")
					local vcSortsLRU, vcPlansLRU = vcSorts, vcPlans
					vcQueued = {}
					MerchantMasterDB.profFilter = "all"
					vcProv.Refresh(app.buildVendorCrafterContext())
					check(#vcQueued == 0 and vcSorts == vcSortsLRU and vcPlans == vcPlansLRU
						and vcBox._dp and #vcBox._dp:GetCollection() == allVCCount,
						"VC LRU cache returns instant synchronous hit when toggling back to 'all'")
					MerchantMasterDB.profFilter = "blacksmithing"
					vcProv.Refresh(app.buildVendorCrafterContext())
					check(#vcQueued == 0 and vcSorts == vcSortsLRU and vcPlans == vcPlansLRU
						and vcBox._dp and #vcBox._dp:GetCollection() == bsVCCount,
						"VC LRU cache returns instant synchronous hit when toggling back to 'blacksmithing'")

					-- (c) 8-entry LRU filter cache & background prewarm: All Recipes
					local slProv = app.superListProvider or ns.SuperList
					local slBox = app.ui.recipesTable and app.ui.recipesTable.scrollBox
					if slProv and slBox then
						MerchantMasterDB.profFilter = "all"
						app.activeTab = "dashboard"
						slProv.Invalidate()
						drainVC()
						slSorts, slWarmHookCalls = 0, 0
						vcQueued = {}
						slProv.WarmInBackground(app.buildSuperListContext())
						drainVC()
						check(slWarmHookCalls >= 1,
							"All Recipes WarmInBackground invokes app.onSuperListWarmComplete once prewarming finishes")
						check(slSorts > 0, "All Recipes WarmInBackground pre-filters/pre-sorts in background")
						local slSortsBeforeOpen = slSorts
						vcQueued = {}
						slBox._dp = nil
						app.activeTab = "recipes"
						slProv.Refresh(app.buildSuperListContext())
						check(#vcQueued == 0 and slSorts == slSortsBeforeOpen
							and slBox._dp ~= nil and #slBox._dp:GetCollection() == #ns.RecipeStats.GetCatalog(),
							"First All Recipes open after WarmInBackground binds synchronously in 1 call")

						-- Toggle All Recipes to alchemy (miss -> caches) then back to all & alchemy (instant synchronous LRU hits)
						MerchantMasterDB.profFilter = "alchemy"
						slProv.Refresh(app.buildSuperListContext())
						drainVC()
						local slAlchCount = slBox._dp and #slBox._dp:GetCollection() or 0
						check(slAlchCount > 0 and slAlchCount < #ns.RecipeStats.GetCatalog(),
							"All Recipes alchemy filter narrows list")
						local slSortsLRU = slSorts
						vcQueued = {}
						MerchantMasterDB.profFilter = "all"
						slProv.Refresh(app.buildSuperListContext())
						check(#vcQueued == 0 and slSorts == slSortsLRU
							and slBox._dp and #slBox._dp:GetCollection() == #ns.RecipeStats.GetCatalog(),
							"All Recipes LRU cache returns instant synchronous hit toggling back to 'all'")
						MerchantMasterDB.profFilter = "alchemy"
						slProv.Refresh(app.buildSuperListContext())
						check(#vcQueued == 0 and slSorts == slSortsLRU
							and slBox._dp and #slBox._dp:GetCollection() == slAlchCount,
							"All Recipes LRU cache returns instant synchronous hit toggling back to 'alchemy'")
					end

					-- (d) Store.RecordCraftYield triggers 0 full VC.Start rebuilds and repairs only affected recipe via VC.RepairItems
					local Store = ns.Analytics and ns.Analytics.Store
					MerchantMasterDB.profFilter = "all"
					MerchantMasterDB.craftableFilter = "all"
					app.activeTab = "vendor_crafter"
					vcProv.Refresh(app.buildVendorCrafterContext())
					drainVC()
					local vcRowsNow = vcBox._dp and vcBox._dp:GetCollection() or {}
					local sampleVC = nil
					for _, r in ipairs(vcRowsNow) do
						if r.spellID and r.outputItemID and r.outputItemID > 0 then sampleVC = r; break end
					end
					check(sampleVC ~= nil, "Found profitable Vendor Crafter row for yield/ownership/cooldown checks")
					if Store and type(Store.RecordCraftYield) == "function" and sampleVC then
						if not Store.initialized then Store.Init() end
						local startsPreYield, repairsPreYield = vcStarts, repairCalls
						Store.RecordCraftYield(sampleVC.spellID, sampleVC.outputItemID, 2, 1, { 2 })
						vcProv.Refresh(app.buildVendorCrafterContext())
						drainVC()
						check(vcStarts == startsPreYield,
							"Store.RecordCraftYield triggers 0 full VC.Start rebuilds (starts=" .. tostring(vcStarts - startsPreYield) .. ")")
						check(repairCalls == repairsPreYield + 1,
							"Store.RecordCraftYield repairs only affected recipe via VC.RepairItems (repairs=" .. tostring(repairCalls - repairsPreYield) .. ")")

						-- Non-item enchant spell (outputItemID=0) triggers 0 Vendor Crafter full rebuilds
						local enchantSpellID = nil
						for _, entry in ipairs(ns.RecipeStats.GetCatalog()) do
							local r = entry and entry.recipe
							if r and r.isEnchant and r.spellID and r.spellID > 0 and not r.outputItemID then
								enchantSpellID = r.spellID
								break
							end
						end
						enchantSpellID = enchantSpellID or 7418
						local startsPreEnchant = vcStarts
						Store.RecordCraftYield(enchantSpellID, 0, 1, 1)
						vcProv.Refresh(app.buildVendorCrafterContext())
						drainVC()
						check(vcStarts == startsPreEnchant,
							"Store.RecordCraftYield for non-item enchant spell triggers 0 VC full rebuilds (starts=" .. tostring(vcStarts - startsPreEnchant) .. ")")
					end

					-- (e) Targeted Invalidate('ownership', { ids, names }) updates ONLY affected row(s) with 0 FilterSort re-runs
					local origPatchTargeted = ns.RecipeStats.PatchMetaTargeted
					local targetedCalls, lastTargetedPatched = 0, 0
					ns.RecipeStats.PatchMetaTargeted = function(...)
						targetedCalls = targetedCalls + 1
						local cnt = origPatchTargeted(...)
						lastTargetedPatched = cnt
						return cnt
					end
					local okMeta, errMeta = pcall(function()
						-- Refresh sampleVC reference after RepairItems
						vcRowsNow = vcBox._dp and vcBox._dp:GetCollection() or {}
						local targetVC = nil
						for _, r in ipairs(vcRowsNow) do
							if r.spellID == sampleVC.spellID and r.outputItemID == sampleVC.outputItemID then targetVC = r; break end
						end
						check(targetVC ~= nil, "Located repaired VC row for targeted ownership/cooldown checks")
						local savedBagName = app.char.bags and app.char.bags[targetVC.name]
						local savedCachedBagName = app.cachedBagCounts and app.cachedBagCounts[targetVC.name]
						local savedBagByID = app.cachedBagCountsByID and app.cachedBagCountsByID[targetVC.outputItemID]
						app.char.bags = app.char.bags or {}
						app.cachedBagCounts = app.cachedBagCounts or {}
						app.cachedBagCountsByID = app.cachedBagCountsByID or {}
						app.bagCountsDirty = false
						app.char.bags[targetVC.name] = 77
						app.cachedBagCounts[targetVC.name] = 77
						app.cachedBagCountsByID[targetVC.outputItemID] = 77
						app.ownershipRev = (app.ownershipRev or 0) + 1
						local vcSortsPreOwn, vcStartsPreOwn, targPreOwn = vcSorts, vcStarts, targetedCalls
						vcProv.Invalidate("ownership", { ids = { [targetVC.outputItemID] = true }, names = { [targetVC.name] = true } })
						vcProv.Refresh(app.buildVendorCrafterContext())
						drainVC()
						check(vcStarts == vcStartsPreOwn and vcSorts == vcSortsPreOwn,
							"VC targeted ownership invalidation runs 0 full rebuilds and 0 FilterSort re-runs")
						check(targetedCalls > targPreOwn and lastTargetedPatched >= 1 and lastTargetedPatched < 50,
							"VC targeted ownership patched only affected rows (" .. tostring(lastTargetedPatched) .. ")")
						check(targetVC.ownedOutputQty == 77,
							"VC targeted ownership updated affected row ownedOutputQty in place to 77 (got " .. tostring(targetVC.ownedOutputQty) .. ")")
						app.char.bags[targetVC.name] = savedBagName
						app.cachedBagCounts[targetVC.name] = savedCachedBagName
						app.cachedBagCountsByID[targetVC.outputItemID] = savedBagByID
						app.ownershipRev = (app.ownershipRev or 0) + 1

						-- (f) Targeted Invalidate('cooldown', { [spellID] = true }) on Vendor Crafter
						local vcSortsPreCD, vcStartsPreCD, targPreCD = vcSorts, vcStarts, targetedCalls
						vcProv.Invalidate("cooldown", { [targetVC.spellID] = true })
						vcProv.Refresh(app.buildVendorCrafterContext())
						drainVC()
						check(vcStarts == vcStartsPreCD and vcSorts == vcSortsPreCD,
							"VC targeted cooldown invalidation runs 0 full rebuilds and 0 FilterSort re-runs")
						check(targetedCalls > targPreCD and lastTargetedPatched >= 1 and lastTargetedPatched <= 5,
							"VC targeted cooldown patched only affected spell row(s) (" .. tostring(lastTargetedPatched) .. ")")

						-- Targeted ownership & cooldown on All Recipes
						if slProv and slBox then
							MerchantMasterDB.profFilter = "all"
							MerchantMasterDB.craftableFilter = "all"
							app.activeTab = "recipes"
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							local slRowsNow = slBox._dp and slBox._dp:GetCollection() or {}
							local targetSL = nil
							for _, r in ipairs(slRowsNow) do
								if r.spellID == 17187 and r.outputItemID then targetSL = r; break end
							end
							check(targetSL ~= nil, "Found Transmute: Arcanite (17187) row in All Recipes")
							local savedSLBagName = app.char.bags[targetSL.name]
							local savedSLCachedBag = app.cachedBagCounts[targetSL.name]
							local savedSLBagID = app.cachedBagCountsByID[targetSL.outputItemID]
							app.bagCountsDirty = false
							app.char.bags[targetSL.name] = 55
							app.cachedBagCounts[targetSL.name] = 55
							app.cachedBagCountsByID[targetSL.outputItemID] = 55
							app.ownershipRev = (app.ownershipRev or 0) + 1
							local slSortsPreOwn, targSLPreOwn = slSorts, targetedCalls
							slProv.Invalidate("ownership", { ids = { [targetSL.outputItemID] = true }, names = { [targetSL.name] = true } })
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							check(slSorts == slSortsPreOwn,
								"All Recipes targeted ownership invalidation runs 0 FilterSort re-runs")
							check(targetedCalls > targSLPreOwn and lastTargetedPatched >= 1 and lastTargetedPatched < 100,
								"All Recipes targeted ownership patched only affected rows (" .. tostring(lastTargetedPatched) .. " of " .. tostring(#slRowsNow) .. ")")
							check(targetSL.ownedOutputQty == 55,
								"All Recipes targeted ownership updated ownedOutputQty in place to 55 (got " .. tostring(targetSL.ownedOutputQty) .. ")")
							app.char.bags[targetSL.name] = savedSLBagName
							app.cachedBagCounts[targetSL.name] = savedSLCachedBag
							app.cachedBagCountsByID[targetSL.outputItemID] = savedSLBagID
							app.ownershipRev = (app.ownershipRev or 0) + 1

							local slSortsPreCD, targSLPreCD = slSorts, targetedCalls
							slProv.Invalidate("cooldown", { [17187] = true })
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							check(slSorts == slSortsPreCD,
								"All Recipes targeted cooldown invalidation runs 0 FilterSort re-runs")
							check(targetedCalls > targSLPreCD and lastTargetedPatched >= 1 and lastTargetedPatched <= 5,
								"All Recipes targeted cooldown patched only affected spell row(s) (" .. tostring(lastTargetedPatched) .. ")")

							-- Visiting craftable_now -> returning to all -> targeted ownership keeps 'all' instant (0 sorts) while evicting stale craftable_now LRU entry
							MerchantMasterDB.craftableFilter = "craftable_now"
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							MerchantMasterDB.craftableFilter = "all"
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							app.bagCountsDirty = false
							app.char.bags[targetSL.name] = 66
							app.cachedBagCounts[targetSL.name] = 66
							app.cachedBagCountsByID[targetSL.outputItemID] = 66
							app.ownershipRev = (app.ownershipRev or 0) + 1
							local slSortsPreEvict = slSorts
							slProv.Invalidate("ownership", { ids = { [targetSL.outputItemID] = true }, names = { [targetSL.name] = true } })
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							check(slSorts == slSortsPreEvict,
								"Targeted ownership while browsing 'all' keeps 'all' instant (0 sorts)")
							local slSortsBeforeCraftable = slSorts
							MerchantMasterDB.craftableFilter = "craftable_now"
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
							check(slSorts > slSortsBeforeCraftable,
								"Previously cached 'craftable_now' LRU entry was evicted by targeted ownership and recomputed cleanly")
							MerchantMasterDB.craftableFilter = "all"
							app.char.bags[targetSL.name] = savedSLBagName
							app.cachedBagCounts[targetSL.name] = savedSLCachedBag
							app.cachedBagCountsByID[targetSL.outputItemID] = savedSLBagID
							app.ownershipRev = (app.ownershipRev or 0) + 1
							slProv.Refresh(app.buildSuperListContext())
							drainVC()
						end
					end)
					ns.RecipeStats.PatchMetaTargeted = origPatchTargeted
					if not okMeta then error(errMeta, 0) end
				end)

				VC.FilterSort = savedVCFilterSort
				VC.OptimizePortfolio = savedVCOptimize
				ns.SuperListModel.FilterSort = savedSLFilterSort
				app.onSuperListWarmComplete = savedOnSLWarmComplete
				if not okSpeed then error(errSpeed, 0) end
			end
		end)

		ns.GetPlayerProfessions = savedGetProfs
		C_Timer.After = savedAfter
		VC.Start = savedStart
		VC.EvaluateRecipe = savedEval
		VC.RepairItems = savedRepair
		MerchantMasterDB.profFilter = savedProfFilter
		MerchantMasterDB.knownRecipesOnly = savedKnownOnly
		MerchantMasterDB.unlockFilter = savedUnlock
		if app.ui.searchBox then app.ui.searchBox:SetText(savedSearch) end
		clearAHItem(2841)
		clearAHItem(3478)
		ns.InvalidatePriceCache()
		VC.ClearCache()
		if not ok then error(err, 0) end
	end
end

print(string.format("PASS: Vendor Crafter (%d assertions, 0 failures)", n))
