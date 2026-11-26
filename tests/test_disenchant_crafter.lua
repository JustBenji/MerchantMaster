-- Disenchantment Crafter & Deep Analysis End-to-End Verification Suite (Pure Lua 5.1)
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"

MerchantMasterDB = {
	superListColumns = { hidden = { wowheadURL = true }, order = { "name", "avgProfit" } },
}

local ns, frames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local app = ns.app
local DC = ns.DisenchantCrafterModel
local Theme = ns.Theme

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("DISENCHANT CRAFTER FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local function approx(a, b, eps, msg)
	eps = eps or 1e-6
	check(type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps,
		string.format("%s (got %s, expected %s)", tostring(msg), tostring(a), tostring(b)))
end

check(type(DC) == "table" and type(DC.EvaluateRecipe) == "function"
	and type(DC.RepairItems) == "function" and type(DC.Start) == "function"
	and type(DC.FilterSort) == "function" and type(DC.OptimizePortfolio) == "function",
	"ns.DisenchantCrafterModel public API exported")

local origCItem = _G.C_Item
local origPriceSource = MerchantMasterDB.priceSource
local origApplyAHCut = MerchantMasterDB.applyAHCut
local econKey = ns.CurrentEconomyInfo().effectiveKey
local mockVendorSell = hostEnv.mockVendorSell

-- Pin deterministic live_ah pricing so local on-disk MerchantMaster_Snapshot.lua never overrides stubs
MerchantMasterDB.priceSource = "live_ah"
MerchantMasterDB.applyAHCut = true

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

-- Synthetic IDs cleanly separated from real catalog items and test_de_and_pricing IDs
local OUT_ARMOR_GREEN = 997101 -- Uncommon ilvl 12 Armor: Strange Dust 80% (1.20) + Lesser Magic Essence 20% (0.30)
local OUT_WEAPON_ASTRAL = 997102 -- Uncommon ilvl 24 Weapon: Lesser Astral Essence 75% (1.10) + Strange Dust 15% (0.75) + Small Glimmering 10% (0.10)
local OUT_BOP_GREEN = 997103 -- BoP Uncommon ilvl 12 Armor (craftable -> DE eligible!)
local OUT_POLE_INELIG = 997104 -- Fishing Pole (ineligible for DE)
local OUT_SHIRT_INELIG = 997105 -- Shirt INVTYPE_BODY (ineligible for DE)
local OUT_UNCACHED = 997106 -- Uncached output item (not yet returned by GetItemInfo)

local REAG_BOLT = 997201
local REAG_DYE = 997202
local REAG_GEM = 997203

local stubItemInfo = {
	[OUT_ARMOR_GREEN]   = { "Synthetic Linen Robe", nil, 2, 12, 7, "Armor", "Cloth", 1, "INVTYPE_CHEST", 132641, 150, 4, 1 },
	[OUT_WEAPON_ASTRAL] = { "Synthetic Astral Edge", nil, 2, 24, 19, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 135274, 250, 2, 7 },
	[OUT_BOP_GREEN]     = { "Synthetic Bound Jerkin", nil, 2, 12, 7, "Armor", "Leather", 1, "INVTYPE_CHEST", 132624, 140, 4, 2 },
	[OUT_POLE_INELIG]   = { "Synthetic Fishing Pole", nil, 2, 20, 15, "Weapon", "Fishing Poles", 1, "INVTYPE_2HWEAPON", 132931, 100, 2, 20 },
	[OUT_SHIRT_INELIG]  = { "Synthetic Linen Shirt", nil, 2, 20, 1, "Armor", "Cloth", 1, "INVTYPE_BODY", 132642, 25, 4, 1 },
	[38]                = { "Recruit's Shirt", nil, 2, 20, 15, "Armor", "Cloth", 1, "INVTYPE_CHEST", 132641, 1, 4, 1 }, -- TSM NonDisenchantable
	[10940]             = { "Strange Dust", nil, 1, 10, 0, "Trade Goods", "Enchanting", 20, "", 132858, 1, 7, 12 },
	[10938]             = { "Lesser Magic Essence", nil, 2, 10, 0, "Trade Goods", "Enchanting", 10, "", 132864, 1, 7, 12 },
	[10998]             = { "Lesser Astral Essence", nil, 2, 20, 0, "Trade Goods", "Enchanting", 10, "", 132865, 1, 7, 12 },
	[10978]             = { "Small Glimmering Shard", nil, 3, 20, 0, "Trade Goods", "Enchanting", 20, "", 132875, 1, 7, 12 },
	[REAG_BOLT]         = { "Synthetic Cloth Bolt", nil, 1, 10, 0, "Trade Goods", "Cloth", 20, "", 132889, 50, 7, 5 },
	[REAG_DYE]          = { "Synthetic Blue Dye", nil, 1, 10, 0, "Trade Goods", "Trade Goods", 20, "", 132456, 25, 7, 0 },
	[REAG_GEM]          = { "Synthetic Cut Gem", nil, 2, 20, 0, "Trade Goods", "Jewelcrafting", 20, "", 134101, 200, 7, 4 },
}

_G.C_Item = {
	GetItemInfo = function(arg)
		local id = type(arg) == "number" and arg or (type(arg) == "string" and tonumber(arg:match("item:(%d+)")))
		if id and stubItemInfo[id] then
			return unpack(stubItemInfo[id])
		end
		if id == OUT_UNCACHED then return nil end
		if origCItem and origCItem.GetItemInfo then return origCItem.GetItemInfo(arg) end
		return nil
	end,
	GetDetailedItemLevelInfo = origCItem and origCItem.GetDetailedItemLevelInfo or nil,
}

-- Seed deterministic market prices
setAHItem(10940, 1000, 1000, 200, { { price = 1000, qty = 200 } }) -- Strange Dust = 10s
setAHItem(10938, 2000, 2000, 100, { { price = 2000, qty = 100 } }) -- Lesser Magic Essence = 20s
setAHItem(10998, 5000, 5000, 100, { { price = 5000, qty = 100 } }) -- Lesser Astral Essence = 50s
setAHItem(10978, 8000, 8000, 100, { { price = 8000, qty = 100 } }) -- Small Glimmering Shard = 80s

-- Reagents: Bolt 500c (10 cheap @ 500c, 10 expensive @ 5000c); Dye vendor 50c; Gem 1200c
setAHItem(REAG_BOLT, 500, 500, 20, { { price = 500, qty = 10 }, { price = 5000, qty = 10 } })
setAHItem(REAG_GEM, 1200, 1200, 30, { { price = 1200, qty = 30 } })
ns.VENDOR_REAGENTS[REAG_DYE] = 50
mockVendorSell[OUT_ARMOR_GREEN] = 150
mockVendorSell[OUT_WEAPON_ASTRAL] = 250
mockVendorSell[OUT_BOP_GREEN] = 140
ns.InvalidatePriceCache()

---------------------------------------------------------------------------------------------------
-- 1. DisenchantCrafterModel Core Math, Eligibility, Buy Moat, Portfolio Planner, Repair & FilterSort
---------------------------------------------------------------------------------------------------
local recArmor = {
	spellID = 997501,
	outputItemID = OUT_ARMOR_GREEN,
	name = "Synthetic Linen Robe",
	prof = "tailoring",
	skill = 55,
	numMade = 1,
	reagents = { { REAG_BOLT, 2 }, { REAG_DYE, 2 } }, -- cost = 2*500 + 2*50 = 1100c
}
local recAstral = {
	spellID = 997502,
	outputItemID = OUT_WEAPON_ASTRAL,
	name = "Synthetic Astral Edge",
	prof = "blacksmithing",
	skill = 135,
	numMade = 1,
	reagents = { { REAG_GEM, 2 } }, -- cost = 2*1200 = 2400c
}
local recBoP = {
	spellID = 997503,
	outputItemID = OUT_BOP_GREEN,
	name = "Synthetic Bound Jerkin",
	prof = "leatherworking",
	skill = 60,
	numMade = 1,
	bop = true,
	reagents = { { REAG_BOLT, 1 }, { REAG_DYE, 2 } }, -- cost = 500 + 100 = 600c
}
local recBlacklist = {
	spellID = 997504,
	outputItemID = 38,
	name = "Recruit's Shirt",
	prof = "tailoring",
	skill = 10,
	numMade = 1,
	reagents = { { REAG_BOLT, 1 } },
}
local recPole = {
	spellID = 997505,
	outputItemID = OUT_POLE_INELIG,
	name = "Synthetic Fishing Pole",
	prof = "engineering",
	skill = 80,
	numMade = 1,
	reagents = { { REAG_BOLT, 1 } },
}
local recShirt = {
	spellID = 997506,
	outputItemID = OUT_SHIRT_INELIG,
	name = "Synthetic Linen Shirt",
	prof = "tailoring",
	skill = 20,
	numMade = 1,
	reagents = { { REAG_BOLT, 1 } },
}
local recEnchant = {
	spellID = 997507,
	outputItemID = OUT_ARMOR_GREEN,
	isEnchant = true,
	name = "Enchant Chest",
	prof = "enchanting",
	skill = 50,
	numMade = 1,
	reagents = { { REAG_BOLT, 1 } },
}
local recUncached = {
	spellID = 997508,
	outputItemID = OUT_UNCACHED,
	name = "Uncached Item",
	prof = "tailoring",
	skill = 70,
	numMade = 1,
	reagents = { { REAG_BOLT, 1 } },
}

local legacyBase = DC.ResolveLegacy({ barteringMode = 0, honoredDiscount = false })
local ctxCutOn = { economy = econKey, applyAHCut = true, subCraftMode = "buy" }
local ctxCutOff = { economy = econKey, applyAHCut = false, subCraftMode = "buy" }

-- Uncommon Armor ilvl 12:
-- Gross DE EV = 1.2 * 1000 + 0.3 * 2000 = 1200 + 600 = 1800c
-- Net DE EV (95%) = 1710c; minGross = 1*1000 = 1000 (net 950c); maxGross = 2*2000 = 4000 (net 3800c)
local rowA = DC.EvaluateRecipe(recArmor, ctxCutOn, legacyBase, {})
check(rowA ~= nil, "Uncommon armor craft evaluates profitably")
check(rowA.craftCost == 1100, "Armor craftCost == 1100, got " .. tostring(rowA.craftCost))
check(rowA.avgDE == 1710, "Armor avgDE (95% cut) == 1710, got " .. tostring(rowA.avgDE))
check(rowA.minDE == 950 and rowA.maxDE == 3800,
	string.format("Armor minDE/maxDE expected 950/3800, got %s/%s", tostring(rowA.minDE), tostring(rowA.maxDE)))
check(rowA.avgProfit == 610, "Armor avgProfit == 610, got " .. tostring(rowA.avgProfit))
check(rowA.minProfit == -150 and rowA.maxProfit == 2700,
	string.format("Armor minProfit/maxProfit expected -150/2700, got %s/%s", tostring(rowA.minProfit), tostring(rowA.maxProfit)))
approx(rowA.marginPct, (610 / 1100) * 100, 0.01, "Armor marginPct ~= 55.45%")
check(type(rowA.deSummary) == "string" and rowA.deSummary:find("80%% Strange Dust", 1, false) ~= nil,
	"deSummary identifies 80% Strange Dust, got " .. tostring(rowA.deSummary))
check(type(rowA.deOutcomes) == "table" and #rowA.deOutcomes == 2 and type(rowA.deBreakdown) == "table",
	"Row carries full deOutcomes & deBreakdown")

-- applyAHCut = false raises avgDE to 1800 and avgProfit to 700
local rowANoCut = DC.EvaluateRecipe(recArmor, ctxCutOff, legacyBase, {})
check(rowANoCut and rowANoCut.avgDE == 1800 and rowANoCut.avgProfit == 700,
	"applyAHCut=false computes gross DE EV (1800) and profit (700)")

-- Arcane Salvager (+20% bonus loot) computation & context toggle
check(rowA.avgDEAS == 2052 and rowA.arcaneSalvager == false,
	"Armor row exposes avgDEAS=2052 (1710*1.20) when Arcane Salvager inactive, got " .. tostring(rowA.avgDEAS))
local ctxASOn = { economy = econKey, applyAHCut = true, arcaneSalvager = true, subCraftMode = "buy" }
local rowAAS = DC.EvaluateRecipe(recArmor, ctxASOn, legacyBase, {})
check(rowAAS and rowAAS.arcaneSalvager == true and rowAAS.avgDE == 2052 and rowAAS.avgProfit == 952,
	"arcaneSalvager=true computes avgDE=2052 and avgProfit=952 (2052 - 1100)")

-- Weapon ilvl 24 Astral Essence fix:
-- Gross = 1.10*5000 + 0.75*1000 + 0.10*8000 = 5500 + 750 + 800 = 7050 -> net 95% = 6698
local rowW = DC.EvaluateRecipe(recAstral, ctxCutOn, legacyBase, {})
check(rowW ~= nil and rowW.avgDE == 6698 and rowW.deSummary:find("Lesser Astral Essence", 1, true) ~= nil,
	"Weapon ilvl 24 evaluates using Lesser Astral Essence (6698 net, got " .. tostring(rowW and rowW.avgDE) .. ")")

-- BoP crafted gear IS eligible for Disenchantment Crafter!
local rowBoP = DC.EvaluateRecipe(recBoP, ctxCutOn, legacyBase, {})
check(rowBoP ~= nil and rowBoP.isBoP == true and rowBoP.avgDE == 1710 and rowBoP.avgProfit == 1110,
	"BoP crafted gear is included and marked isBoP=true (profit 1110)")

-- Exclusions & Uncached handling
check(DC.EvaluateRecipe(recBlacklist, ctxCutOn, legacyBase, {}) == nil, "NonDisenchantable item 38 excluded")
check(DC.EvaluateRecipe(recPole, ctxCutOn, legacyBase, {}) == nil, "Fishing pole excluded")
check(DC.EvaluateRecipe(recShirt, ctxCutOn, legacyBase, {}) == nil, "Shirt INVTYPE_BODY excluded")
check(DC.EvaluateRecipe(recEnchant, ctxCutOn, legacyBase, {}) == nil, "isEnchant spell excluded")
local uncScratch = {}
local uncRow, uncErr = DC.EvaluateRecipe(recUncached, ctxCutOn, legacyBase, uncScratch)
check(uncRow == nil and uncErr == "uncached" and uncScratch.uncachedIDs and uncScratch.uncachedIDs[OUT_UNCACHED] == true,
	"Uncached item returns 'uncached' and records uncachedIDs")

-- Buy Moat & Portfolio Planner:
-- recArmor uses 2 Bolts/craft; cheap AH lot has 10 Bolts @ 500c -> 5 profitable crafts (at next lot 5000c, cost=10100 > 1710)
check(rowA.profitableCrafts == 5 and rowA.totalProfitCap == 5 * 610,
	string.format("Armor Buy Moat supports 5 crafts / 3050c profit cap (got %s / %s)",
		tostring(rowA.profitableCrafts), tostring(rowA.totalProfitCap)))
check(rowA.reagentBuyCaps and rowA.reagentBuyCaps[REAG_BOLT] and rowA.reagentBuyCaps[REAG_BOLT].maxBuyUnit == 500,
	"reagentBuyCaps records 500c maxBuyUnit for REAG_BOLT")

-- Shared bottleneck optimization across recArmor (305c/bolt -> 2*500+100 vs 1710 => 610/craft = 305c/bolt) and recBoP (1*500+100 vs 1710 => 1110/craft = 1110c/bolt)
local plan = DC.OptimizePortfolio({ rowA, rowBoP }, { topN = 10, budgetCopper = 0, maxCrafts = 0 })
check(type(plan) == "table" and type(plan.entries) == "table" and #plan.entries == 1,
	"Shared-bolt Portfolio Planner allocates cheap bolts to higher profit/bolt recBoP (" .. tostring(plan and #plan.entries) .. ")")
check(plan.entries[1].row == rowBoP and plan.entries[1].crafts == 10 and plan.totalCrafts == 10 and plan.recipeCount == 1
	and plan.totalProfit == 10 * 1110 and plan.byKey[rowA.key] == nil,
	"recBoP receives all 10 cheap-bolt crafts while recArmor gets 0 in shared allocation")

-- FilterSort tests
local sortedDesc = DC.FilterSort({ rowA, rowW, rowBoP }, {}, { key = "avgProfit", ascending = false })
check(#sortedDesc == 3 and sortedDesc[1] == rowW and sortedDesc[2] == rowBoP and sortedDesc[3] == rowA,
	"FilterSort sorts descending by avgProfit (Astral > BoP > Armor)")
local searchFiltered = DC.FilterSort({ rowA, rowW, rowBoP }, { search = "astral essence" }, { key = "avgProfit", ascending = false })
check(#searchFiltered == 1 and searchFiltered[1] == rowW,
	"FilterSort search matches DE outcome material name ('astral essence')")

-- RepairItems refreshes both reagent price changes and DE material price changes!
do
	local origGetCatalog = ns.RecipeStats.GetCatalog
	ns.RecipeStats.GetCatalog = function()
		return { { recipe = recArmor, key = "rA" }, { recipe = recAstral, key = "rW" } }
	end
	local rowsRep = { DC.EvaluateRecipe(recArmor, ctxCutOn, legacyBase, {}), DC.EvaluateRecipe(recAstral, ctxCutOn, legacyBase, {}) }
	local repairScratch = {}
	-- Bump Strange Dust price 1000c -> 2000c (recArmor avgDE increases from 1710 to 2850!)
	setAHItem(10940, 2000, 2000, 200, { { price = 2000, qty = 200 } })
	ns.InvalidatePriceCache()
	local nRepaired = DC.RepairItems(rowsRep, ctxCutOn, legacyBase, repairScratch, { [10940] = true })
	check(nRepaired == 2, "RepairItems refreshes both recipes affected by DE mat 10940 (got " .. tostring(nRepaired) .. ")")
	local foundArmor
	for _, rr in ipairs(rowsRep) do
		if rr.spellID == recArmor.spellID then foundArmor = rr; break end
	end
	check(foundArmor and foundArmor.avgDE == 2850 and foundArmor.avgProfit == 1750,
		"RepairItems updated recArmor avgDE to 2850 / avgProfit to 1750 (got " .. tostring(foundArmor and foundArmor.avgDE) .. ")")
	-- Revert Strange Dust to 1000c
	setAHItem(10940, 1000, 1000, 200, { { price = 1000, qty = 200 } })
	ns.InvalidatePriceCache()
	ns.RecipeStats.GetCatalog = origGetCatalog
end

---------------------------------------------------------------------------------------------------
-- 2. DisenchantCrafter UI View, Sidebar Controls, Columns, Slash Commands & Shopping Cart Queue
---------------------------------------------------------------------------------------------------
do
	local dcProv = app.disenchantCrafterProvider
	check(dcProv ~= nil and ns.DisenchantCrafter == dcProv, "disenchantCrafterProvider registered cleanly")

	app.panel:Show()
	local dcBtn = app.ui.navBtns and app.ui.navBtns.disenchant_crafter
	check(dcBtn ~= nil and dcBtn.labelFs:GetText() == "Disenchantment Crafter",
		"Sidebar nav button 'disenchant_crafter' labeled 'Disenchantment Crafter'")
	dcBtn:Click("LeftButton")
	check(app.activeTab == "disenchant_crafter" and app.ui.disenchantCrafterView and app.ui.disenchantCrafterView:IsShown(),
		"Clicking sidebar button switches activeTab to 'disenchant_crafter' and shows view")

	local view = app.ui.disenchantCrafterView
	check(view.masterChefBtn == nil, "Disenchantment Crafter Row 2 omits Master Chef control")
	check(view.arcaneSalvagerBtn ~= nil and view.barteringBtn ~= nil and view.honoredBtn ~= nil and view.moatFilterBtn ~= nil,
		"Disenchantment Crafter exposes Arcane Salvager, Bartering, Honored, and Buy Moat controls")

	-- Clicking Arcane Salvager pill toggles DB filter on/off cleanly
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false
	view.arcaneSalvagerBtn:Click("LeftButton")
	check(MerchantMasterDB.disenchantCrafterArcaneSalvager == true,
		"Clicking arcaneSalvagerBtn enables disenchantCrafterArcaneSalvager")
	view.arcaneSalvagerBtn:Click("RightButton")
	check(MerchantMasterDB.disenchantCrafterArcaneSalvager == false,
		"Right-clicking arcaneSalvagerBtn resets disenchantCrafterArcaneSalvager to false")

	local tbl = app.ui.disenchantCrafterTable
	check(tbl and type(tbl.columns) == "table", "Disenchantment Crafter table initialized")
	local colKeys = {}
	for _, col in ipairs(tbl.columns) do colKeys[col.key] = col.label end
	for _, exp in ipairs({
		{ "deSummary", "Primary DE" },
		{ "minDE", "Min DE" },
		{ "avgDE", "Avg DE" },
		{ "avgDEAS", "Avg DE (AS)" },
		{ "maxDE", "Max DE" },
		{ "avgProfit", "Avg Profit" },
		{ "marginPct", "Margin" },
		{ "moatScore", "Buy Moat" },
		{ "profitableCrafts", "Max Crafts" },
		{ "buyCeiling", "Buy Up To" },
		{ "totalProfitCap", "Profit Cap" },
	}) do
		check(colKeys[exp[1]] == exp[2],
			string.format("Column %s labeled '%s', got '%s'", exp[1], exp[2], tostring(colKeys[exp[1]])))
	end

	-- Slash commands route to disenchant_crafter
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("dc")
	check(app.activeTab == "disenchant_crafter" and view:IsShown(), "/mm dc opens disenchant_crafter")
	app.setTab("dashboard")
	SlashCmdList.MERCHANTMASTER("decraft")
	check(app.activeTab == "disenchant_crafter" and view:IsShown(), "/mm decraft opens disenchant_crafter")

	-- Queue Disenchantment Crafter plan into Shopping Cart (including BoP recipe!)
	MerchantMasterDB.craftOrderQueue = {}
	local qRecs, qCrafts = app.queueDisenchantCrafterPlan({
		{ row = rowBoP, crafts = 4, reagentBuyCaps = rowBoP.reagentBuyCaps },
	}, { replace = true, silent = true })
	check(qRecs == 1 and qCrafts == 4, "queueDisenchantCrafterPlan queued 1 recipe / 4 crafts")
	check(app.getRecipeShoppingQty(rowBoP) == 4 and app.hasUnifiedShoppingItems() == true,
		"Queued BoP DE craft reflects qty 4 in unified shopping basket")
	app.clearCraftingOrderQueue()
	check(app.getRecipeShoppingQty(rowBoP) == 0, "clearCraftingOrderQueue clears queued DE crafts cleanly")

	-- Theme & Warcraft skin switching on Disenchantment Crafter
	Theme.SetMode("light")
	app.refresh()
	check(Theme.GetMode() == "light" and view:IsShown(), "Light mode renders Disenchantment Crafter cleanly")
	Theme.SetMode("dark")
	app.refresh()
	check(Theme.GetMode() == "dark" and view:IsShown(), "Dark mode renders Disenchantment Crafter cleanly")
	if _G.MerchantMasterAPI and _G.MerchantMasterAPI.SetSkin then
		_G.MerchantMasterAPI.SetSkin("goblin")
		app.refresh()
		check(Theme.GetSkin() == "goblin" and view:IsShown(), "Goblin Warcraft skin renders Disenchantment Crafter cleanly")
		_G.MerchantMasterAPI.SetSkin("standard")
	end
end

---------------------------------------------------------------------------------------------------
-- 3. Deep Analysis Disenchanting Card, 3-Way Exit Comparison & Click-to-Inspect Material Drilldown
---------------------------------------------------------------------------------------------------
do
	local DA = ns.DeepAnalysis
	check(type(DA) == "table", "ns.DeepAnalysis table exported")

	app.setTab("disenchant_crafter")
	check(app.openDeepAnalysis({ kind = "recipe", recipe = recArmor, row = rowA }) == true,
		"openDeepAnalysis opens crafted armor recipe cleanly")
	check(DA.deCard ~= nil, "ns.DeepAnalysis.deCard constructed on first render")
	local st = DA.GetState()
	check(st.deShown == true and st.deOutcomeCount == 2,
		string.format("DeepAnalysis shows deCard with 2 outcomes (shown=%s, count=%s)",
			tostring(st.deShown), tostring(st.deOutcomeCount)))

	local sumTxt = DA.deCard.summaryFs:GetText() or ""
	local exitTxt = DA.deCard.exitFs:GetText() or ""
	check(sumTxt:find("DE EV", 1, true) ~= nil and sumTxt:find("Craft", 1, true) ~= nil and sumTxt:find("AS (+20%)", 1, true) ~= nil,
		"DeepAnalysis deCard summary includes Craft, DE EV, and AS (+20%) metrics: " .. sumTxt)
	check(exitTxt:find("Best Exit:", 1, true) ~= nil and exitTxt:find("AH Net", 1, true) ~= nil
		and exitTxt:find("Vendor", 1, true) ~= nil,
		"DeepAnalysis deCard shows 3-way exit comparison (AH vs DE vs Vendor): " .. exitTxt)

	-- Find clickable material outcome row on deCard and drill into Deep Analysis for that material
	local matBtn
	for _, ch in ipairs(frames) do
		if ch._parent == DA.deCard and ch.IsShown and ch:IsShown() and ch.clickable and ch.itemID == 10940 then
			matBtn = ch
			break
		end
	end
	check(matBtn ~= nil, "deCard exposes clickable outcome row for Strange Dust (10940)")
	matBtn:Click("LeftButton")
	local stMat = DA.GetState()
	check(stMat.target and stMat.target.kind == "item" and stMat.target.itemID == 10940 and stMat.stackDepth == 1,
		"Clicking DE material outcome drills into Deep Analysis for item 10940 (stackDepth=1)")
	check(stMat.deShown == false and stMat.deOutcomeCount == 0,
		"Strange Dust (non-DE trade good) hides deCard cleanly with 0 outcomes")

	-- Back navigation pops stack cleanly and restores recipe deCard
	check(app.returnFromDeepAnalysis() == true, "returnFromDeepAnalysis pops back to armor recipe")
	local stBack = DA.GetState()
	check(stBack.deShown == true and stBack.deOutcomeCount == 2 and stBack.stackDepth == 0,
		"Back button restores armor recipe deCard cleanly (stackDepth=0)")

	-- Ineligible Fishing Pole hides deCard cleanly
	check(app.openDeepAnalysis({ kind = "item", itemID = OUT_POLE_INELIG }) == true,
		"openDeepAnalysis handles ineligible Fishing Pole cleanly")
	local stPole = DA.GetState()
	check(stPole.deShown == false and stPole.deOutcomeCount == 0,
		"Ineligible Fishing Pole hides deCard cleanly")
end

---------------------------------------------------------------------------------------------------
-- 4. Standalone Top-Bar Disenchant Helper (Checklist, AS +20%, Secure Macrotext, Skip & Advance)
---------------------------------------------------------------------------------------------------
do
	local DH = ns.DisenchantHelper
	check(type(DH) == "table" and type(DH.Toggle) == "function" and type(DH.ScanBags) == "function",
		"ns.DisenchantHelper API exported")

	local topDeBtn = app.ui and app.ui.topDisenchantBtn
	check(topDeBtn ~= nil and topDeBtn:IsShown(), "Top-right topDisenchantBtn exposed and visible")
	check(math.floor((topDeBtn:GetWidth() or 0) + 0.5) == 48 and math.floor((topDeBtn:GetHeight() or 0) + 0.5) == 48,
		"topDisenchantBtn is 48x48")
	check((topDeBtn:GetText() or "") == "" and topDeBtn.hl == nil, "topDisenchantBtn is icon-only without rectangular .hl highlight")

	-- Mock C_Container bags with 2 DE-eligible items + 1 blacklisted (38) + 1 non-DE reagent
	local origContainer = _G.C_Container
	local origNumBags = _G.NUM_BAG_SLOTS
	local bagContents = {
		[1] = { itemID = OUT_ARMOR_GREEN, stackCount = 1, iconFileID = 132641, hyperlink = "|cff1eff00|Hitem:" .. OUT_ARMOR_GREEN .. "|h[Synthetic Linen Robe]|h|r" },
		[2] = { itemID = OUT_WEAPON_ASTRAL, stackCount = 1, iconFileID = 135274, hyperlink = "|cff1eff00|Hitem:" .. OUT_WEAPON_ASTRAL .. "|h[Synthetic Astral Edge]|h|r" },
		[3] = { itemID = 38, stackCount = 1, iconFileID = 132641, hyperlink = "|cff1eff00|Hitem:38|h[Recruit's Shirt]|h|r" },
		[4] = { itemID = REAG_BOLT, stackCount = 5, iconFileID = 132889, hyperlink = "|cffffffff|Hitem:" .. REAG_BOLT .. "|h[Synthetic Cloth Bolt]|h|r" },
	}
	_G.NUM_BAG_SLOTS = 0
	_G.C_Container = {
		GetContainerNumSlots = function(b) return b == 0 and 4 or 0 end,
		GetContainerNumFreeSlots = origContainer and origContainer.GetContainerNumFreeSlots or function() return 10, 0 end,
		GetContainerItemInfo = function(b, s) return (b == 0) and bagContents[s] or nil end,
		GetContainerItemLink = function(b, s) return (b == 0 and bagContents[s]) and bagContents[s].hyperlink or nil end,
	}

	local origGetCVarBool = _G.GetCVarBool
	local origCSpell = _G.C_Spell
	local cvarDown = true
	_G.GetCVarBool = function(k)
		if k == "ActionButtonUseKeyDown" then return cvarDown end
		if origGetCVarBool then return origGetCVarBool(k) end
		return false
	end

	topDeBtn:Click("LeftButton")
	local dst = DH.GetState()
	local deActionBtn = dst.frame and dst.frame.deBtn
	check(dst.shown == true and dst.itemCount == 2 and dst.selectedCount == 0 and dst.macrotext == "",
		string.format("Clicking topDisenchantBtn opens Disenchant Helper with 2 eligible items, 0 pre-selected (got count=%s, sel=%s)",
			tostring(dst.itemCount), tostring(dst.selectedCount)))

	local capturedClicks = {}
	local origRegClicks = deActionBtn.RegisterForClicks
	deActionBtn.RegisterForClicks = function(self, arg)
		capturedClicks[#capturedClicks + 1] = arg
		if origRegClicks then return origRegClicks(self, arg) end
	end
	dst.frame:Hide()
	dst.frame:Show()
	check(capturedClicks[#capturedClicks] == "LeftButtonDown",
		"DisenchantHelper registers LeftButtonDown when ActionButtonUseKeyDown is true (got " .. tostring(capturedClicks[#capturedClicks]) .. ")")
	cvarDown = false
	DH.ScanBags()
	check(capturedClicks[#capturedClicks] == "LeftButtonUp",
		"DisenchantHelper switches to LeftButtonUp when ActionButtonUseKeyDown is false (got " .. tostring(capturedClicks[#capturedClicks]) .. ")")
	cvarDown = true
	DH.ScanBags()

	DH.SelectByQuality(2)
	dst = DH.GetState()
	check(dst.selectedCount == 2 and dst.totalEstCopper == (1710 + 6698),
		"SelectByQuality(2) selects 2 items (totalEstCopper=" .. tostring(dst.totalEstCopper) .. ")")
	check(dst.macrotext == "/cast Disenchant;\n/use 0 1"
		and deActionBtn:GetAttribute("*type1") == "macro"
		and deActionBtn:GetAttribute("type") == "macro"
		and deActionBtn:GetAttribute("*macrotext1") == "/cast Disenchant;\n/use 0 1",
		"Secure DISENCHANT button sets *type1/type=macro and *macrotext1/macrotext for bag 0 slot 1: " .. tostring(dst.macrotext))

	-- PreClick refreshes localized spell macrotext right before SecureActionButton_OnClick runs
	_G.C_Spell = { GetSpellName = function(id) return id == 13262 and "Entzaubern" or nil end }
	local preClickFn = deActionBtn.GetScript and deActionBtn:GetScript("PreClick")
	check(type(preClickFn) == "function", "Secure DISENCHANT button exposes PreClick script")
	if preClickFn then preClickFn(deActionBtn, "LeftButton", true) end
	check(deActionBtn:GetAttribute("*macrotext1") == "/cast Entzaubern;\n/use 0 1"
		and deActionBtn:GetAttribute("macrotext") == "/cast Entzaubern;\n/use 0 1",
		"PreClick refreshes localized *macrotext1 & macrotext ('/cast Entzaubern;\\n/use 0 1'), got: "
			.. tostring(deActionBtn:GetAttribute("*macrotext1")))
	_G.C_Spell = origCSpell

	DH.SetArcaneSalvager(true)
	dst = DH.GetState()
	local expAS = math.floor(1710 * 1.20 + 0.5) + math.floor(6698 * 1.20 + 0.5)
	check(dst.arcaneSalvager == true and dst.totalEstCopper == expAS,
		"AS +20% toggle scales Disenchant Helper totalEstCopper to " .. tostring(expAS) .. ", got " .. tostring(dst.totalEstCopper))
	DH.SetArcaneSalvager(false)

	DH.SkipCurrent()
	dst = DH.GetState()
	check(dst.selectedCount == 1 and dst.macrotext == "/cast Disenchant;\n/use 0 2"
		and deActionBtn:GetAttribute("*macrotext1") == "/cast Disenchant;\n/use 0 2",
		"SkipCurrent advances Secure button macrotext & *macrotext1 to bag 0 slot 2: " .. tostring(dst.macrotext))

	-- Disenchanting slot 2 removes it from bags and ScanBags clears active macrotext
	bagContents[2] = nil
	DH.ScanBags()
	dst = DH.GetState()
	check(dst.itemCount == 1 and dst.selectedCount == 0 and dst.macrotext == ""
		and deActionBtn:GetAttribute("*macrotext1") == "",
		"Removing disenchanted bag slot updates checklist and resets macrotext/*macrotext1 cleanly")

	-- Window alignment (spotCard anchored above footer), full random-enchant suffix name & >7 item scrolling
	local helperF = dst.frame
	check(math.floor((helperF:GetWidth() or 0) + 0.5) == 496 and math.floor((helperF:GetHeight() or 0) + 0.5) == 584,
		"Disenchant Helper resized cleanly to 496x584")
	local spotPts = helperF.spotCard and helperF.spotCard._points or {}
	local anchoredAboveFooter = false
	for _, pt in ipairs(spotPts) do
		if pt[1] == "BOTTOMRIGHT" and pt[2] == helperF.footer and pt[3] == "TOPRIGHT" and (tonumber(pt[5]) or 0) >= 8 then
			anchoredAboveFooter = true
		end
	end
	check(anchoredAboveFooter, "spotCard BOTTOMRIGHT anchors cleanly >=8px above footer so DISENCHANT button is never overlapped")

	for s = 1, 10 do
		local suffix = (s == 1) and " of the Owl" or (" #" .. s)
		bagContents[s] = {
			itemID = OUT_ARMOR_GREEN,
			stackCount = 1,
			iconFileID = 132641,
			hyperlink = "|cff1eff00|Hitem:" .. OUT_ARMOR_GREEN .. ":0:0:0:0:0:42:0|h[Synthetic Linen Robe" .. suffix .. "]|h|r",
		}
	end
	_G.C_Container.GetContainerNumSlots = function(b) return b == 0 and 10 or 0 end
	DH.ScanBags()
	DH.SelectAll()
	dst = DH.GetState()
	check(dst.itemCount == 10 and dst.items[1].name == "Synthetic Linen Robe of the Owl"
		and helperF.spotName:GetText() == "Synthetic Linen Robe of the Owl",
		"Disenchant Helper extracts and displays full suffix item name ('" .. tostring(dst.items[1] and dst.items[1].name) .. "')")
	check(helperF.scrollTrack and helperF.scrollTrack:IsShown() == true
		and helperF.scrollThumb and helperF.scrollThumb:IsShown() == true,
		"Visible scrollbar appears when >7 disenchantable items are queued")
	check((helperF.summaryFs:GetText() or ""):find("Showing 1-7", 1, true) ~= nil,
		"Summary header shows visible scroll range ('Showing 1-7'): " .. tostring(helperF.summaryFs:GetText()))

	-- Simulate mouse-wheel scroll directly over row 1 button and verify offset + clamping
	local firstRow = helperF.rows and helperF.rows[1]
	local rowWheel = firstRow and firstRow.GetScript and firstRow:GetScript("OnMouseWheel")
	check(type(rowWheel) == "function", "Checklist row buttons forward mouse wheel scrolling")
	if rowWheel then rowWheel(firstRow, -1) end
	dst = DH.GetState()
	check(dst.scrollOffset == 1 and (helperF.summaryFs:GetText() or ""):find("Showing 2-8", 1, true) ~= nil,
		"Mouse wheel down on checklist row scrolls to Showing 2-8 (offset=" .. tostring(dst.scrollOffset) .. ")")
	DH.ScrollBy(-1); DH.ScrollBy(-1); DH.ScrollBy(-1)
	dst = DH.GetState()
	check(dst.scrollOffset == 3 and dst.maxScrollOffset == 3
		and (helperF.summaryFs:GetText() or ""):find("Showing 4-10", 1, true) ~= nil,
		"Scroll clamps cleanly at maxScrollOffset=3 ('Showing 4-10')")
	DH.ScrollBy(1); DH.ScrollBy(1); DH.ScrollBy(1)

	SlashCmdList.MERCHANTMASTER("deh")
	check(DH.GetState().shown == false, "/mm deh toggles Disenchant Helper closed cleanly")

	deActionBtn.RegisterForClicks = origRegClicks
	_G.GetCVarBool = origGetCVarBool
	_G.NUM_BAG_SLOTS = origNumBags
	_G.C_Container = origContainer
end

---------------------------------------------------------------------------------------------------
-- 5. Collect Stage "ALT" vs "MAIL" Fix: AH Purchases Record Into Collect as MAIL Instead of ALT
---------------------------------------------------------------------------------------------------
do
	local OF = app.orderFlow
	local CB = app.cartBuyer
	check(type(OF) == "table" and type(CB) == "table" and type(CB.OnCommodityPurchaseConfirmed) == "function",
		"OrderFlow & CartBuyer APIs available for Collect Mail test")

	local origIncludeAlts = MerchantMasterDB.includeAlts
	MerchantMasterDB.chars["Normal-Horde-Forever-AltCollector"] = {
		name = "AltCollector",
		economy = app.char and app.char.economy or "Normal-Horde",
		bags = { ["Synthetic Cloth Bolt"] = 5 },
	}
	MerchantMasterDB.includeAlts = true
	if OF.Reset then OF.Reset() end

	OF.LoadFromShoppingRows({
		{
			isMainRow = true,
			mainGroupKey = "de_collect_test",
			name = "Synthetic Linen Robe",
			itemID = OUT_ARMOR_GREEN,
			spellID = recArmor.spellID,
			prof = recArmor.prof,
			qty = 1,
			sourceKind = "craft_order",
		},
		{
			mainGroupKey = "de_collect_test",
			indent = 1,
			name = "Synthetic Cloth Bolt",
			itemID = REAG_BOLT,
			qty = 3,
			ownedUsed = 2,
			unitPrice = 500,
			lineCost = 1500,
		},
	}, { title = "DE Mail Collect Test" })

	local stPre = OF.GetState()
	local preCur = stPre.stages.collect.items[stPre.stages.collect.activeIndex]
	check(preCur ~= nil and preCur.source == "alt",
		"Before AH purchase, Collect spotlight only sees Alt inventory (source=" .. tostring(preCur and preCur.source) .. ")")

	-- Simulate completing an AH commodity purchase for 3x Synthetic Cloth Bolt
	local origAHFrame = _G.AuctionHouseFrame
	_G.AuctionHouseFrame = { IsShown = function() return true end }
	if app.enterOrderFlowMode then app.enterOrderFlowMode("ah") end
	CB.OnCommodityPurchaseConfirmed(REAG_BOLT, 3)
	ns.MarketScan.HandleEvent("COMMODITY_PURCHASE_SUCCEEDED")

	local stPost = OF.GetState()
	local postCur = stPost.stages.collect.items[stPost.stages.collect.activeIndex]
	check(postCur ~= nil and postCur.source == "mail" and postCur.needed == 3 and postCur.remaining == 3,
		string.format("After AH purchase, Collect stage targets MAIL (source=%s, needed=%s, remaining=%s)",
			tostring(postCur and postCur.source), tostring(postCur and postCur.needed), tostring(postCur and postCur.remaining)))

	if app.ui and app.ui.cartBuyerModal and app.ui.cartBuyerModal.Hide then
		app.ui.cartBuyerModal:Hide()
	end
	if OF.Reset then OF.Reset() end
	_G.AuctionHouseFrame = origAHFrame
	MerchantMasterDB.chars["Normal-Horde-Forever-AltCollector"] = nil
	MerchantMasterDB.includeAlts = origIncludeAlts
end

---------------------------------------------------------------------------------------------------
-- 6. Pass 2: Full Craftable/DE Catalog Coverage, Nil/Negative Sorting, Row 2 Toggles, Live Capture
---------------------------------------------------------------------------------------------------
do
	-- 6A. Full catalog coverage in DisenchantCrafterModel (cold GetItemInfo cache -> static DE_ITEM_META)
	local savedCItem = _G.C_Item
	_G.C_Item = nil
	if ns.ClearDECache then ns.ClearDECache() end
	DC.ClearCache()

	local defRows, profRows, allRows
	local defScratch = {}
	local _, defState = DC.Start({
		economy = econKey,
		applyAHCut = true,
		onlyProfitable = false,
		showNonDE = false,
		subCraftMode = "buy",
		defer = false,
	}, nil, function(rows) defRows = rows end)
	check(type(defRows) == "table" and #defRows == 1268,
		"Default filter (onlyProfitable=false, showNonDE=false) returns all 1268 disenchantable craftables, got " .. tostring(defRows and #defRows))
	check(defState and defState.evalScratch and (defState.evalScratch.uncachedIDs == nil or next(defState.evalScratch.uncachedIDs) == nil),
		"Zero uncached craftable recipes under cold GetItemInfo cache")

	local hasNeg, hasNilCraft, hasNilDE = false, false, false
	for _, r in ipairs(defRows) do
		check(r.deEligible == true, "Default rows must all have deEligible == true")
		if type(r.avgProfit) == "number" and r.avgProfit <= 0 then hasNeg = true end
		if r.craftCost == nil then hasNilCraft = true end
		if r.avgDE == nil then hasNilDE = true end
	end
	check(hasNeg or hasNilCraft or hasNilDE,
		"Default DisenchantCrafter rows include unprofitable / unpriced craftable gear")

	DC.Start({
		economy = econKey,
		applyAHCut = true,
		onlyProfitable = true,
		showNonDE = false,
		subCraftMode = "buy",
		defer = false,
	}, nil, function(rows) profRows = rows end)
	check(type(profRows) == "table" and #profRows < #defRows,
		string.format("onlyProfitable=true returns strict profitable subset (%s < %s)",
			tostring(profRows and #profRows), tostring(#defRows)))
	for _, r in ipairs(profRows) do
		check(r.deEligible ~= false and type(r.avgProfit) == "number" and r.avgProfit > 0,
			"onlyProfitable=true rows must all have deEligible~=false and avgProfit > 0")
	end

	DC.Start({
		economy = econKey,
		applyAHCut = true,
		onlyProfitable = false,
		showNonDE = true,
		subCraftMode = "buy",
		defer = false,
	}, nil, function(rows) allRows = rows end)
	check(type(allRows) == "table" and #allRows == #ns.RECIPES and #allRows == 2212,
		string.format("showNonDE=true returns ALL %d craftable recipes (got %s)",
			#ns.RECIPES, tostring(allRows and #allRows)))
	local nonDECount, enchantCount = 0, 0
	for _, r in ipairs(allRows) do
		if r.deEligible == false then
			nonDECount = nonDECount + 1
			if r.deReason == "Enchant" then enchantCount = enchantCount + 1 end
			check(type(r.deReason) == "string" and r.deReason ~= "",
				"Non-DE rows must expose non-empty deReason")
			check(r.minDE == nil and r.avgDE == nil and r.avgDEAS == nil and r.maxDE == nil
				and r.avgProfit == nil and r.maxProfit == nil and r.marginPct == nil,
				"Non-DE rows must keep DE/profit/margin fields nil")
		end
	end
	check(nonDECount == (#allRows - #defRows) and enchantCount > 0,
		string.format("Non-DE rows count matches delta (%d == %d) with enchants (%d)",
			nonDECount, #allRows - #defRows, enchantCount))

	-- FilterSort consistency over allRows
	local fsDefault = DC.FilterSort(allRows, { onlyProfitable = false, showNonDE = false }, { key = "avgProfit", ascending = false })
	check(#fsDefault == #defRows, "FilterSort(showNonDE=false) matches default DE-eligible count (" .. tostring(#fsDefault) .. ")")
	local fsProf = DC.FilterSort(allRows, { onlyProfitable = true, showNonDE = false }, { key = "avgProfit", ascending = false })
	check(#fsProf == #profRows, "FilterSort(onlyProfitable=true) matches profitable count (" .. tostring(#fsProf) .. ")")
	print(string.format("DISENCHANT_CRAFTER_COUNTS default=%d profitable=%d all=%d nonDE=%d enchants=%d",
		#defRows, #profRows, #allRows, nonDECount, enchantCount))

	_G.C_Item = savedCItem
	if ns.ClearDECache then ns.ClearDECache() end
	DC.ClearCache()

	-- 6B. Negative profit, unpriced craftCost, non-DE evaluation, nil sorting safety & MOAT nil guard
	local recLoss = {
		spellID = 997509,
		outputItemID = OUT_ARMOR_GREEN,
		name = "Overpriced Linen Robe",
		prof = "tailoring",
		skill = 55,
		numMade = 1,
		reagents = { { REAG_GEM, 5 } }, -- cost = 5 * 1200 = 6000c > 1710c avgDE
	}
	local REAG_UNPRICED = 997299
	local recUnpriced = {
		spellID = 997510,
		outputItemID = OUT_ARMOR_GREEN,
		name = "Unpriced Reagent Robe",
		prof = "tailoring",
		skill = 55,
		numMade = 1,
		reagents = { { REAG_UNPRICED, 1 } },
	}
	local rowLoss = DC.EvaluateRecipe(recLoss, ctxCutOn, legacyBase, {})
	check(rowLoss ~= nil and rowLoss.deEligible == true and rowLoss.avgProfit < 0 and rowLoss.marginPct < 0,
		"Negative-profit DE recipe evaluates cleanly with negative avgProfit/marginPct")
	local rowUnpriced = DC.EvaluateRecipe(recUnpriced, ctxCutOn, legacyBase, {})
	check(rowUnpriced ~= nil and rowUnpriced.deEligible == true and rowUnpriced.craftCost == nil
		and rowUnpriced.avgProfit == nil and rowUnpriced.moat == nil,
		"Unpriced-reagent DE recipe evaluates with nil craftCost/avgProfit/moat")
	local rowNonDE = DC.EvaluateRecipe(recEnchant, { economy = econKey, applyAHCut = true, showNonDE = true }, legacyBase, {})
	check(rowNonDE ~= nil and rowNonDE.deEligible == false and rowNonDE.deReason == "Enchant" and rowNonDE.avgDE == nil,
		"Enchant evaluates under showNonDE=true with deEligible=false and deReason='Enchant'")

	-- EvaluateBuyMoat nil safety
	local safeNilMoat = ns.VendorCrafterModel.EvaluateBuyMoat({}, nil, nil, econKey, {}, nil)
	check(type(safeNilMoat) == "table" and safeNilMoat.tier == "unknown" and safeNilMoat.short == "n/a",
		"EvaluateBuyMoat handles nil craftCost/avgOutput without erroring")

	-- Nil numeric sorting always places nil at bottom regardless of sort direction
	local nilSortDesc = DC.FilterSort({ rowUnpriced, rowLoss, rowA, rowNonDE }, {}, { key = "avgProfit", ascending = false })
	check(#nilSortDesc == 4 and nilSortDesc[1] == rowA and nilSortDesc[2] == rowLoss
		and nilSortDesc[3].avgProfit == nil and nilSortDesc[4].avgProfit == nil,
		"Descending numeric sort puts nil avgProfit rows at bottom")
	local nilSortAsc = DC.FilterSort({ rowUnpriced, rowLoss, rowA, rowNonDE }, {}, { key = "avgProfit", ascending = true })
	check(#nilSortAsc == 4 and nilSortAsc[1] == rowLoss and nilSortAsc[2] == rowA
		and nilSortAsc[3].avgProfit == nil and nilSortAsc[4].avgProfit == nil,
		"Ascending numeric sort puts nil avgProfit rows at bottom")

	-- 6C. Row 2 toggle pills, resetDisenchantCrafterFilters & buildDisenchantCrafterContext
	app.setTab("disenchant_crafter")
	local dcView = app.ui.disenchantCrafterView
	check(dcView.onlyProfitableBtn ~= nil and dcView.showNonDEBtn ~= nil,
		"Disenchantment Crafter Row 2 exposes Profitable Only and All Craftable toggle pills")
	check(MerchantMasterDB.disenchantCrafterOnlyProfitable ~= true and MerchantMasterDB.disenchantCrafterShowNonDE ~= true,
		"onlyProfitable and showNonDE default to false")
	dcView.onlyProfitableBtn:Click("LeftButton")
	dcView.showNonDEBtn:Click("LeftButton")
	local ctxToggled = app.buildDisenchantCrafterContext()
	check(MerchantMasterDB.disenchantCrafterOnlyProfitable == true and MerchantMasterDB.disenchantCrafterShowNonDE == true
		and ctxToggled.onlyProfitable == true and ctxToggled.showNonDE == true,
		"Clicking Row 2 pills sets context onlyProfitable & showNonDE true")
	app.resetDisenchantCrafterFilters()
	local ctxReset = app.buildDisenchantCrafterContext()
	check(MerchantMasterDB.disenchantCrafterOnlyProfitable == false and MerchantMasterDB.disenchantCrafterShowNonDE == false
		and ctxReset.onlyProfitable == false and ctxReset.showNonDE == false,
		"resetDisenchantCrafterFilters resets onlyProfitable & showNonDE to false")

	-- Cell formatting & color checks for nil ('-'), negative profit/margin (red), Non-DE ('Non-DE' + '-'), and row tooltips
	do
		-- Ensure all DC columns are visible for cell checks
		local dcProv = app.disenchantCrafterProvider
		if dcProv and dcProv.ResetColumns then dcProv.ResetColumns() end
		local tbl = app.ui.disenchantCrafterTable
		local firstFrame = tbl and tbl.scrollBox and tbl.scrollBox._frames and tbl.scrollBox._frames[1]
		if not firstFrame and tbl and tbl.scrollBox and tbl.scrollBox.GetFrames then
			local fs = tbl.scrollBox:GetFrames()
			firstFrame = fs and fs[1]
		end
		check(firstFrame ~= nil and tbl.scrollBox and tbl.scrollBox._view and tbl.scrollBox._view._initFn,
			"DisenchantCrafter scrollBox exposes row frame and _initFn for cell rendering checks")

		-- Render negative-profit row -> red avgProfit/marginPct and '-xx.x%' margin format
		tbl.scrollBox._view._initFn(firstFrame, rowLoss)
		local byKey = firstFrame.cellGroup and firstFrame.cellGroup.cellsByKey
		check(byKey and byKey.marginPct and byKey.avgProfit, "Loss row renders avgProfit & marginPct cells")
		local lossMarginTxt = byKey.marginPct.fs:GetText() or ""
		local lossColor = byKey.marginPct._textColor
		check(lossMarginTxt:sub(1, 1) == "-" and lossColor and lossColor[1] > 0.6 and lossColor[2] < 0.45 and lossColor[1] > lossColor[2],
			"Negative margin renders with '-' prefix and red tint, got " .. tostring(lossMarginTxt))

		-- Render unpriced-reagent row -> '-' for nil craftCost/avgProfit/marginPct
		tbl.scrollBox._view._initFn(firstFrame, rowUnpriced)
		check(byKey.craftCost.fs:GetText() == "-" and byKey.avgProfit.fs:GetText() == "-" and byKey.marginPct.fs:GetText() == "-",
			"Nil numeric fields render cleanly as '-' in DisenchantCrafter")

		-- Render non-DE row -> 'Non-DE' in deSummary and '-' in DE/Profit columns + deReason in row tooltip
		tbl.scrollBox._view._initFn(firstFrame, rowNonDE)
		check(byKey.deSummary.fs:GetText() == "Non-DE" and byKey.avgDE.fs:GetText() == "-" and byKey.avgProfit.fs:GetText() == "-",
			"Non-DE row renders 'Non-DE' in Primary DE and '-' in DE/Profit columns")
		local nameCell = byKey.name
		if nameCell and nameCell:GetScript("OnEnter") then
			GameTooltip:ClearLines()
			nameCell:GetScript("OnEnter")(nameCell)
			local sawDeReason = false
			for _, ln in ipairs(GameTooltip._lines or {}) do
				local s = tostring(ln or "")
				if s:find("Enchant", 1, true) and s:find("Disenchant Eligible", 1, true) then
					sawDeReason = true
					break
				end
			end
			check(sawDeReason, "Non-DE row tooltip displays Disenchant Eligible + deReason")
		end
	end

	-- 6D. RecordDEObservation -> Bayesian blend -> DisenchantCrafterModel refresh + DeepAnalysis Learned casts
	MerchantMasterDB.deObservations = nil
	ns.ClearDECache()
	DC.ClearCache()
	local preObsRow = DC.EvaluateRecipe(recArmor, ctxCutOn, legacyBase, {})
	local v0 = ns.GetDEObservationVersion()
	for _ = 1, 3 do
		ns.RecordDEObservation(OUT_ARMOR_GREEN, { [10938] = 3 }, { source = "helper" })
	end
	local v1 = ns.GetDEObservationVersion()
	check(v1 == v0 + 3, "RecordDEObservation bumps GetDEObservationVersion")
	local postObsRow = DC.EvaluateRecipe(recArmor, ctxCutOn, legacyBase, {})
	check(postObsRow and postObsRow.deLearnedCasts == 3 and postObsRow.avgDE > preObsRow.avgDE,
		string.format("Bayesian blend increases OUT_ARMOR_GREEN avgDE (%s -> %s) with deLearnedCasts=3",
			tostring(preObsRow and preObsRow.avgDE), tostring(postObsRow and postObsRow.avgDE)))
	app.openDeepAnalysis({ kind = "recipe", recipe = recArmor, row = postObsRow })
	local daLearnedTxt = ns.DeepAnalysis.deCard.summaryFs:GetText() or ""
	check(daLearnedTxt:find("Learned: 3 casts", 1, true) ~= nil,
		"DeepAnalysis deCard summary displays 'Learned: 3 casts': " .. daLearnedTxt)
	app.returnFromDeepAnalysis()

	-- Row tooltip on postObsRow displays 'Learned: 3 casts'
	do
		local tbl = app.ui.disenchantCrafterTable
		local firstFrame = tbl and tbl.scrollBox and tbl.scrollBox._frames and tbl.scrollBox._frames[1]
		if firstFrame and tbl.scrollBox._view and tbl.scrollBox._view._initFn then
			tbl.scrollBox._view._initFn(firstFrame, postObsRow)
			local nameCell = firstFrame.cellGroup and firstFrame.cellGroup.cellsByKey and firstFrame.cellGroup.cellsByKey.name
			if nameCell and nameCell:GetScript("OnEnter") then
				GameTooltip:ClearLines()
				nameCell:GetScript("OnEnter")(nameCell)
				local sawRowLearned = false
				for _, ln in ipairs(GameTooltip._lines or {}) do
					if tostring(ln or ""):find("Learned: 3 casts", 1, true) then
						sawRowLearned = true
						break
					end
				end
				check(sawRowLearned, "DisenchantCrafter row tooltip displays 'Learned: 3 casts'")
			end
		end
	end

	-- 6E. Live UNIT_SPELLCAST_SENT / SUCCEEDED / LOOT_OPENED / LOOT_CLOSED attribution & non-DE loot guard
	MerchantMasterDB.deObservations = nil
	ns.ClearDECache()
	local evFrame = hostEnv.eventFrame
	local onEv = evFrame:GetScript("OnEvent")
	local origNumLoot = _G.GetNumLootItems
	local origLootLink = _G.GetLootSlotLink
	local origLootInfo = _G.GetLootSlotInfo
	local origContainer2 = _G.C_Container

	local mockBag = {
		[1] = { itemID = OUT_ARMOR_GREEN, stackCount = 1, hyperlink = "|cff1eff00|Hitem:" .. OUT_ARMOR_GREEN .. "|h[Synthetic Linen Robe]|h|r" },
	}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end,
		GetContainerItemInfo = function(b, s) return (b == 0) and mockBag[s] or nil end,
		GetContainerItemLink = function(b, s) return (b == 0 and mockBag[s]) and mockBag[s].hyperlink or nil end,
		UseContainerItem = function() end,
	}
	app.ensureDEContainerHooks()

	local mockLoot = {
		{ link = "|cffffffff|Hitem:10940|h[Strange Dust]|h|r", qty = 2 },
		{ link = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r", qty = 4 }, -- Non-DE item MUST be ignored
	}
	_G.GetNumLootItems = function() return #mockLoot end
	_G.GetLootSlotLink = function(i) return mockLoot[i] and mockLoot[i].link or nil end
	_G.GetLootSlotInfo = function(i) return nil, "Loot", mockLoot[i] and mockLoot[i].qty or 0 end

	-- Cast 1: Disenchant via UseContainerItem + UNIT_SPELLCAST_SENT + SUCCEEDED + LOOT_OPENED + LOOT_CLOSED
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-de-1", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-de-1", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")

	local stLive1 = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stLive1 and stLive1.casts == 1 and stLive1.mats[10940] and stLive1.mats[10940].totalQty == 2
		and stLive1.mats[2589] == nil,
		"Live DE event sequence records Strange Dust (2) and excludes non-DE Linen Cloth (2589)")

	-- Guard: non-DE spellcast / mob/chest loot must NOT record into deObservations
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Chest", "cast-chest", 818)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-chest", 818)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:10940|h[Strange Dust]|hx5.")
	onEv(evFrame, "LOOT_CLOSED")
	local stAfterChest = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stAfterChest and stAfterChest.casts == 1,
		"Non-DE spellcast/chest loot must not pollute deObservations (casts stays 1)")

	-- Guard: interrupted DE cast does not open a loot capture session
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-de-int", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_INTERRUPTED", "player", "cast-de-int", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stAfterInt = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stAfterInt and stAfterInt.casts == 1,
		"Interrupted Disenchant cast must not record loot (casts stays 1)")

	-- Fallback: CHAT_MSG_LOOT auto-loot when GetNumLootItems() == 0
	mockLoot = {}
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-de-2", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-de-2", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:10938|h[Lesser Magic Essence]|hx2.")
	onEv(evFrame, "CHAT_MSG_LOOT", "Otherplayer receives loot: |cff1eff00|Hitem:10938|h[Lesser Magic Essence]|hx9.")
	onEv(evFrame, "LOOT_CLOSED")
	local stLive2 = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stLive2 and stLive2.casts == 2 and stLive2.mats[10938] and stLive2.mats[10938].totalQty == 2,
		"CHAT_MSG_LOOT auto-loot fallback records player's 2x Essence and ignores party loot")

	_G.GetNumLootItems = origNumLoot
	_G.GetLootSlotLink = origLootLink
	_G.GetLootSlotInfo = origLootInfo
	_G.C_Container = origContainer2
	MerchantMasterDB.deObservations = nil
	ns.ClearDECache()
end

---------------------------------------------------------------------------------------------------
-- 7. Pass 3 Polisher: All 6 Pass 2 Fixes (Loot >4s, Row 2 800px Layout, AS Detection, Attribution,
--    Status Wording, and Vendor Crafter Parity / DeepAnalysis AS Consistency)
---------------------------------------------------------------------------------------------------
do
	-- 7A. Row 2 non-overlap geometry at 800px and 1050px for DisenchantCrafter and VendorCrafter
	local function checkRow2NonOverlap(view, provider, width, label)
		provider.Layout(width)
		local btns = view.row2LeftBtns or {}
		local infoBtn = view.legacyInfoBtn
		check(#btns >= 5 and infoBtn ~= nil and infoBtn._layoutBox ~= nil,
			label .. " exposes row2LeftBtns and legacyInfoBtn._layoutBox at width=" .. tostring(width))
		for i, b in ipairs(btns) do
			local box = b._layoutBox
			check(box ~= nil and box.left < box.right, label .. " button " .. i .. " has valid _layoutBox")
			check(box.right <= width - 12,
				string.format("%s button %d right=%d fits within width=%d", label, i, box.right, width))
			if box.row == 1 then
				check(box.right <= infoBtn._layoutBox.left - 8,
					string.format("%s subrow 1 button %d (right=%d) leaves >=8px gap to legacyInfoBtn (left=%d) at width=%d",
						label, i, box.right, infoBtn._layoutBox.left, width))
			end
			for j = i + 1, #btns do
				local o = btns[j]._layoutBox
				if o.row == box.row then
					local separated = (box.right + 4 <= o.left) or (o.right + 4 <= box.left)
					check(separated, string.format("%s buttons %d and %d do not overlap on subrow %d at width=%d",
						label, i, j, box.row, width))
				end
			end
		end
		return view._row2Subrows, view._row2Height
	end

	app.setTab("disenchant_crafter")
	local dcView = app.ui.disenchantCrafterView
	local sr800, h800 = checkRow2NonOverlap(dcView, app.disenchantCrafterProvider, 800, "DisenchantCrafter")
	check(sr800 == 2 and h800 >= 60 and dcView.legacyBar:GetHeight() >= 60,
		string.format("DisenchantCrafter wraps cleanly to 2 subrows at 800px (subrows=%s, h=%s)", tostring(sr800), tostring(h800)))
	local sr1050, h1050 = checkRow2NonOverlap(dcView, app.disenchantCrafterProvider, 1050, "DisenchantCrafter")
	check(sr1050 == 1 and h1050 == 36 and dcView.legacyBar:GetHeight() == 36,
		string.format("DisenchantCrafter restores single Row 2 at 1050px (subrows=%s, h=%s)", tostring(sr1050), tostring(h1050)))

	app.setTab("vendor_crafter")
	checkRow2NonOverlap(app.ui.vendorCrafterView, app.vendorCrafterProvider, 800, "VendorCrafter")
	checkRow2NonOverlap(app.ui.vendorCrafterView, app.vendorCrafterProvider, 1050, "VendorCrafter")

	-- 7B. Status bar & warming wording when onlyProfitable=false vs true
	app.setTab("disenchant_crafter")
	MerchantMasterDB.disenchantCrafterOnlyProfitable = false
	MerchantMasterDB.disenchantCrafterShowNonDE = false
	app.refresh()
	local stDefaultTxt = app.ui.statusText and app.ui.statusText:GetText() or ""
	check(stDefaultTxt:find("disenchant crafts", 1, true) ~= nil and stDefaultTxt:find("profitable", 1, true) == nil,
		"onlyProfitable=false statusText uses 'disenchant crafts' without 'profitable': " .. tostring(stDefaultTxt))

	MerchantMasterDB.disenchantCrafterShowNonDE = true
	app.refresh()
	local stAllTxt = app.ui.statusText and app.ui.statusText:GetText() or ""
	check(stAllTxt:find("all crafts", 1, true) ~= nil and stAllTxt:find("profitable", 1, true) == nil,
		"showNonDE=true, onlyProfitable=false statusText uses 'all crafts' without 'profitable': " .. tostring(stAllTxt))

	MerchantMasterDB.disenchantCrafterOnlyProfitable = true
	MerchantMasterDB.disenchantCrafterShowNonDE = false
	app.refresh()
	local stProfTxt = app.ui.statusText and app.ui.statusText:GetText() or ""
	check(stProfTxt:find("profitable disenchant crafts", 1, true) ~= nil,
		"onlyProfitable=true statusText uses 'profitable disenchant crafts': " .. tostring(stProfTxt))

	-- 7B-2. Live Salvager: +20% click updates bound table rows (avgDE == avgDEAS, arcaneSalvager == true)
	MerchantMasterDB.disenchantCrafterOnlyProfitable = false
	MerchantMasterDB.disenchantCrafterShowNonDE = false
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false
	app.refresh()
	local function findBoundRowWithDE(tbl)
		local dp = tbl and tbl.scrollBox and tbl.scrollBox._dp
		local rows = dp and dp.GetCollection and dp:GetCollection() or {}
		for _, r in ipairs(rows) do
			if r and r.deEligible == true and type(r.avgDE) == "number" and r.avgDE > 0 and type(r.avgDEAS) == "number" then
				return r
			end
		end
		return nil
	end
	local dcTbl = app.ui.disenchantCrafterTable
	local preASRow = findBoundRowWithDE(dcTbl)
	check(preASRow ~= nil and preASRow.arcaneSalvager == false and preASRow.avgDE < preASRow.avgDEAS,
		string.format("Before clicking Salvager pill, bound row has arcaneSalvager=false and avgDE (%s) < avgDEAS (%s)",
			tostring(preASRow and preASRow.avgDE), tostring(preASRow and preASRow.avgDEAS)))
	dcView.arcaneSalvagerBtn:Click("LeftButton")
	local postASRow = findBoundRowWithDE(dcTbl)
	check(MerchantMasterDB.disenchantCrafterArcaneSalvager == true
		and postASRow ~= nil and postASRow.arcaneSalvager == true and postASRow.avgDE == postASRow.avgDEAS,
		string.format("Clicking Salvager: +20%% pill re-evaluates bound table row to avgDE==avgDEAS (%s == %s, as=%s)",
			tostring(postASRow and postASRow.avgDE), tostring(postASRow and postASRow.avgDEAS), tostring(postASRow and postASRow.arcaneSalvager)))
	dcView.arcaneSalvagerBtn:Click("RightButton")
	local postOffRow = findBoundRowWithDE(dcTbl)
	check(MerchantMasterDB.disenchantCrafterArcaneSalvager == false
		and postOffRow ~= nil and postOffRow.arcaneSalvager == false and postOffRow.avgDE < postOffRow.avgDEAS,
		"Right-clicking Salvager pill reverts bound table row back to baseline avgDE < avgDEAS")

	-- 7C. vendor_crafter parity (resetCurrentViewFilters + returnFromDeepAnalysis) & DeepAnalysis AS consistency
	app.resetCurrentViewFilters()
	check(MerchantMasterDB.disenchantCrafterOnlyProfitable == false and MerchantMasterDB.disenchantCrafterArcaneSalvager == false,
		"app.resetCurrentViewFilters() on disenchant_crafter invokes resetDisenchantCrafterFilters")

	MerchantMasterDB.disenchantCrafterArcaneSalvager = true
	local rowASCheck = DC.EvaluateRecipe(recArmor, { economy = econKey, applyAHCut = true, arcaneSalvager = true, subCraftMode = "buy" }, legacyBase, {})
	app.openDeepAnalysis({ kind = "recipe", recipe = recArmor, row = rowASCheck })
	local function stripColors(s)
		return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local daASTxt = stripColors(ns.DeepAnalysis.deCard.summaryFs:GetText() or "")
	local daExitTxt = stripColors(ns.DeepAnalysis.deCard.exitFs:GetText() or "")
	check(daASTxt:find("20s 52c", 1, true) ~= nil and daASTxt:find("+9s 52c", 1, true) ~= nil
		and daASTxt:find("86.5%", 1, true) ~= nil and daASTxt:find("AS (+20% Active", 1, true) ~= nil,
		"DeepAnalysis with disenchantCrafterArcaneSalvager=true uses AS EV/profit/margin consistently: " .. daASTxt)
	check(daExitTxt:find("20s 52c", 1, true) ~= nil,
		"DeepAnalysis Best Exit reflects active AS EV (20s 52c): " .. daExitTxt)
	app.returnFromDeepAnalysis()
	check(app.activeTab == "disenchant_crafter", "returnFromDeepAnalysis returns cleanly to disenchant_crafter")
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false

	-- 7D. Live DE Capture fixes: LOOT_OPENED >4s -> LOOT_CLOSED, AS preservation, targetName matching,
	--     interrupted/non-DE clearing, and locale-safe CHAT_MSG_LOOT
	MerchantMasterDB.deObservations = nil
	MerchantMasterDB.disenchantHelperAS = false
	MerchantMasterDB.disenchantCrafterArcaneSalvager = false
	ns.ClearDECache()

	local evFrame = hostEnv.eventFrame
	local onEv = evFrame:GetScript("OnEvent")
	local origGetTime = _G.GetTime
	local origNumLoot = _G.GetNumLootItems
	local origLootLink = _G.GetLootSlotLink
	local origLootInfo = _G.GetLootSlotInfo
	local origContainer2 = _G.C_Container
	local origUnitBuff = _G.UnitBuff
	local origLootSelf = _G.LOOT_ITEM_SELF
	local origLootOther = _G.LOOT_ITEM

	local nowClock = 2000.0
	_G.GetTime = function() return nowClock end

	local BELT_ID = 997199
	local mockBag2 = {
		[1] = { itemID = OUT_ARMOR_GREEN, stackCount = 1, hyperlink = "|cff1eff00|Hitem:" .. OUT_ARMOR_GREEN .. "|h[Synthetic Linen Robe]|h|r" },
		[2] = { itemID = BELT_ID, stackCount = 1, hyperlink = "|cff1eff00|Hitem:" .. BELT_ID .. "|h[Random Green Belt]|h|r" },
	}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
		GetContainerItemInfo = function(b, s) return (b == 0) and mockBag2[s] or nil end,
		GetContainerItemLink = function(b, s) return (b == 0 and mockBag2[s]) and mockBag2[s].hyperlink or nil end,
		UseContainerItem = function() end,
	}
	app.ensureDEContainerHooks()

	local mockLoot2 = { { link = "|cffffffff|Hitem:10940|h[Strange Dust]|h|r", qty = 3 } }
	_G.GetNumLootItems = function() return #mockLoot2 end
	_G.GetLootSlotLink = function(i) return mockLoot2[i] and mockLoot2[i].link or nil end
	_G.GetLootSlotInfo = function(i) return nil, "Loot", mockLoot2[i] and mockLoot2[i].qty or 0 end

	-- (1) LOOT_OPENED inside 4s + LOOT_CLOSED after 25s (>4s) still commits cleanly
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-slow-1", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-slow-1", 13262)
	nowClock = 2001.0
	onEv(evFrame, "LOOT_OPENED")
	nowClock = 2026.0 -- 25s later!
	onEv(evFrame, "LOOT_CLOSED")
	local stSlow = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stSlow and stSlow.casts == 1 and stSlow.mats[10940] and stSlow.mats[10940].totalQty == 3,
		"LOOT_OPENED in-window + LOOT_CLOSED after 25s (>4s) commits DE loot cleanly")

	-- (2) LOOT_OPENED never fired + LOOT_CLOSED after 5s (>4s) discards cleanly
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-expired-1", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-expired-1", 13262)
	nowClock = 2032.0
	onEv(evFrame, "LOOT_CLOSED")
	local stExp = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stExp and stExp.casts == 1, "Unopened DE loot session >4s is discarded on LOOT_CLOSED")

	-- (3) Explicit s.arcaneSalvager=false is NOT overwritten by disenchantHelperAS=true
	MerchantMasterDB.disenchantHelperAS = false
	ns.NotifyDisenchantTarget(0, 1, OUT_ARMOR_GREEN, mockBag2[1].hyperlink, "helper", false)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-as-false", 13262)
	MerchantMasterDB.disenchantHelperAS = true -- flipped mid-cast; explicit false must hold
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-as-false", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stNoOverwrite = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stNoOverwrite and stNoOverwrite.casts == 2 and stNoOverwrite.asCasts == 0,
		"Explicit arcaneSalvager=false is preserved even when disenchantHelperAS=true (asCasts=" .. tostring(stNoOverwrite and stNoOverwrite.asCasts) .. ")")
	MerchantMasterDB.disenchantHelperAS = false

	-- (4) Manual cast WITH UnitBuff 'Arcane Salvager' records asCasts += 1 even when DB flags are false
	_G.UnitBuff = function(_, idx)
		if idx == 1 then return "Arcane Salvager", 132864, 1, nil, 0, 0, "player", false, false, 999985 end
		return nil
	end
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-as-buff", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-as-buff", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stBuffAS = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stBuffAS and stBuffAS.casts == 3 and stBuffAS.asCasts == 1,
		"Manual DE cast with 'Arcane Salvager' aura records asCasts=1 cleanly")
	_G.UnitBuff = origUnitBuff

	-- (5) Random prior UseContainerItem (slot 2 Random Green Belt) does NOT misattribute DE on Synthetic Linen Robe
	_G.C_Container.UseContainerItem(0, 2) -- equip/click unrelated item
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-mismatch", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-mismatch", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stRobe = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	local stBelt = ns.GetDEObservationStats(BELT_ID)
	check(stRobe and stRobe.casts == 4 and stBelt == nil,
		"targetName mismatch rejects unrelated prior UseContainerItem and resolves Synthetic Linen Robe")

	-- (6) Non-DE spell SENT/SUCCEEDED clears any lingering DE lootSession immediately (chest loot cannot attach)
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-de-unlooted", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-de-unlooted", 13262)
	-- Player opens a chest instead within 1s
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Chest", "cast-chest-now", 818)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-chest-now", 818)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stChestClean = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stChestClean and stChestClean.casts == 4,
		"Non-DE spell clears prior unlooted DE lootSession so chest loot cannot attach (casts stays 4)")

	-- (7) UNIT_SPELLCAST_INTERRUPTED clears lastBagTarget so an empty-target SENT cannot reuse it
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-int-clear", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_INTERRUPTED", "player", "cast-int-clear", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "", "cast-empty-target", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-empty-target", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stAfterIntClear = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stAfterIntClear and stAfterIntClear.casts == 4,
		"Interrupted cast clears lastBagTarget so subsequent empty-target cast does not misattribute")

	-- (8) Non-English LOOT_ITEM_SELF / LOOT_ITEM CHAT_MSG_LOOT matching (including spaced '|r xN' locales)
	mockLoot2 = {}
	_G.LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
	_G.LOOT_ITEM = "%s erhaelt Beute: %s."
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-de-locale", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-de-locale", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "CHAT_MSG_LOOT", "Ihr erhaltet Beute: |cff1eff00|Hitem:10938|h[Lesser Magic Essence]|hx2.")
	onEv(evFrame, "CHAT_MSG_LOOT", "Ihr erhaltet Beute: |cff1eff00|Hitem:10938|h[Lesser Magic Essence]|h|r x3.")
	onEv(evFrame, "CHAT_MSG_LOOT", "Mitspieler erhaelt Beute: |cff1eff00|Hitem:10938|h[Lesser Magic Essence]|hx9.")
	onEv(evFrame, "LOOT_CLOSED")
	local stLocale = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stLocale and stLocale.casts == 5 and stLocale.mats[10938] and stLocale.mats[10938].totalQty == 5,
		"Non-English LOOT_ITEM_SELF/LOOT_ITEM patterns capture player 2+3x and ignore party 9x")

	-- (9) Mid-cast UNIT_SPELLCAST_FAILED spam-click with distinct castGUID preserves active DE capture
	mockLoot2 = { { link = "|cffffffff|Hitem:10940|h[Strange Dust]|h|r", qty = 1 } }
	_G.C_Container.UseContainerItem(0, 1)
	onEv(evFrame, "UNIT_SPELLCAST_SENT", "player", "Synthetic Linen Robe", "cast-active-de", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_FAILED", "player", "cast-spam-reject", 13262)
	onEv(evFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-active-de", 13262)
	onEv(evFrame, "LOOT_OPENED")
	onEv(evFrame, "LOOT_CLOSED")
	local stAfterSpamFail = ns.GetDEObservationStats(OUT_ARMOR_GREEN)
	check(stAfterSpamFail and stAfterSpamFail.casts == 6 and stAfterSpamFail.mats[10940]
		and stAfterSpamFail.mats[10940].totalQty == 13,
		string.format("Rejected spam-click UNIT_SPELLCAST_FAILED with distinct castGUID keeps active DE capture intact (casts=%s, qty=%s)",
			tostring(stAfterSpamFail and stAfterSpamFail.casts),
			tostring(stAfterSpamFail and stAfterSpamFail.mats[10940] and stAfterSpamFail.mats[10940].totalQty)))

	_G.LOOT_ITEM_SELF = origLootSelf
	_G.LOOT_ITEM = origLootOther
	_G.GetTime = origGetTime
	_G.GetNumLootItems = origNumLoot
	_G.GetLootSlotLink = origLootLink
	_G.GetLootSlotInfo = origLootInfo
	_G.C_Container = origContainer2
	MerchantMasterDB.deObservations = nil
	ns.ClearDECache()
end

-- Cleanup / restore stubs
app._deepAnalysisStack = nil
app._deepAnalysisTarget = nil
app._deepAnalysisReturn = nil
MerchantMasterDB.craftOrderQueue = {}
MerchantMasterDB.priceSource = origPriceSource
MerchantMasterDB.applyAHCut = origApplyAHCut
for _, id in ipairs({ 10940, 10938, 10998, 10978, REAG_BOLT, REAG_GEM }) do
	clearAHItem(id)
end
ns.VENDOR_REAGENTS[REAG_DYE] = nil
mockVendorSell[OUT_ARMOR_GREEN] = nil
mockVendorSell[OUT_WEAPON_ASTRAL] = nil
mockVendorSell[OUT_BOP_GREEN] = nil
_G.C_Item = origCItem
ns.InvalidatePriceCache()
DC.ClearCache()

print(string.format("PASS: Disenchantment Crafter (%d assertions, 0 failures)", n))
