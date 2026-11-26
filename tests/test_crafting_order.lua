local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames = dofile(S .. "host_fixture.lua")
local TOTAL_RECIPES = #ns.RecipeStats.GetCatalog()

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local app = ns.app
local provider = ns.SuperList
local tbl = app.ui.recipesTable
check(app.ui.craftingView == nil and app.ui.writProfitView == nil and app.ui.crateMatsView == nil,
	"Retired crafting, writ profit and crate materials frames are absent")
check(app.ui.profitSubBar == nil and app.ui.tabBtns.crafting == nil and app.ui.tabBtns.writ_profit == nil and app.ui.tabBtns.crate_mats == nil,
	"Retired profit strip and leaf tab buttons are absent")
check(type(app.openCraftingOrder) == "function", "app.openCraftingOrder defined")
check(type(_G.MerchantMasterAPI.OpenCraftingOrder) == "function", "MerchantMasterAPI.OpenCraftingOrder exposed")

-- 1. Prepare All Recipes scroll pool and build catalog rows with clean filters
MerchantMasterDB.profFilter = "all"
MerchantMasterDB.unlockFilter = "all"
MerchantMasterDB.knownRecipesOnly = false
MerchantMasterDB.bisOnly = false
MerchantMasterDB.superListSources = {}
MerchantMasterDB.superListSkillMin = nil
MerchantMasterDB.superListSkillMax = nil
MerchantMasterDB.craftableFilter = "all"
MerchantMasterDB.demandFilter = "all"
MerchantMasterDB.useBuiltInAHBuyer = false
if app.ui.searchBox then app.ui.searchBox:SetText("") end
local savedGetProfsInit = ns.GetPlayerProfessions
ns.GetPlayerProfessions = function() return {} end
app.setTab("recipes")
app.panel:Show()
provider.Invalidate()

local box = tbl.scrollBox
local pool, capacity = {}, 16
box._frames = pool
box.GetHeight = function() return capacity * app.ui.ROW_H end
local function renderSuper()
	if not box._dp then return end
	local items = box._dp:GetCollection()
	for i = 1, math.min(capacity, #items) do
		local r = pool[i]
		if not r then
			r = CreateFrame("Button", nil, box)
			pool[i] = r
		end
		r:Show()
		box._view._initFn(r, items[i])
	end
end
function box:SetDataProvider(dp)
	self._dp = dp
	renderSuper()
end
function box:FullUpdate() renderSuper() end

local queued = {}
local oldAfter = C_Timer.After
C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
local function drain()
	local guard = 0
	while #queued > 0 do
		local fn = table.remove(queued, 1)
		fn()
		guard = guard + 1
		assert(guard < 10000, "runaway timer queue")
	end
end

app.refresh()
drain()
local superRows = box._dp:GetCollection()
check(#superRows == TOTAL_RECIPES, "All Recipes loaded 2057 non-gather recipes")

-- 2. Verify plain Left-Click vs SHIFT + Left-Click on All Recipes row
local searches = 0
local oldSearch = app.searchAH
app.searchAH = function(...) searches = searches + 1 end

local shiftHeld = false
local oldShift = _G.IsShiftKeyDown
_G.IsShiftKeyDown = function() return shiftHeld end

-- Plain Left-Click stays on All Recipes and triggers normal single-item AH search
pool[1].cells[1]:Click("LeftButton")
drain()
check(app.activeTab == "recipes", "Plain Left-Click stays on All Recipes")
check(searches == 1, "Plain Left-Click searches output once")

-- SHIFT + Left-Click on All Recipes queues in craftOrderQueue without switching away or searching AH
searches = 0
shiftHeld = true
provider.SetShiftMode(true)
local clickedRow = pool[1].data
check(clickedRow ~= nil, "First All Recipes row bound")
pool[1].cells[1]:Click("LeftButton")
drain()

check(app.activeTab == "recipes", "SHIFT + Left-Click stays on 'recipes' tab")
check(app.ui.recipesView:IsShown(), "recipesView remains shown during SHIFT + Left-Click")
check(searches == 0, "SHIFT + Left-Click issues zero AH searches")
check(#MerchantMasterDB.craftOrderQueue == 1 and app.getRecipeShoppingQty(clickedRow) == 1,
	"SHIFT + Left-Click adds clicked All Recipes recipe to craftOrderQueue")
check(pool[1].shiftStepper ~= nil and pool[1].shiftStepper:IsShown() and pool[1].shiftStepper.qtyFs:GetText() == "1",
	"Shift stepper shows queued qty 1")
pool[1].shiftStepper.minusBtn:Click("LeftButton")
drain()
check(#MerchantMasterDB.craftOrderQueue == 0 and app.getRecipeShoppingQty(clickedRow) == 0,
	"Stepper minusBtn removes queued item back to 0")
shiftHeld = false
provider.SetShiftMode(false)

-- The compatibility API opens All Recipes and forces the modern quick look.
local quickLookCalls, savedQuickLook = {}, provider.OpenQuickLook
provider.OpenQuickLook = function(itemID, force) quickLookCalls[#quickLookCalls + 1] = {itemID, force} end
check(app.openCraftingOrder(clickedRow) == true, "Direct app.openCraftingOrder succeeds")
drain()
check(app.activeTab == "recipes" and app.ui.recipesView:IsShown(), "Compatibility API opens All Recipes")
check(app.selectedRecipeItemID == clickedRow.recipe.outputItemID, "Compatibility API selects recipe output")
check(#quickLookCalls == 1 and quickLookCalls[1][1] == clickedRow.recipe.outputItemID and quickLookCalls[1][2] == true,
	"Compatibility API forces modern quick look")
app.panel:Hide()
check(_G.MerchantMasterAPI.OpenCraftingOrder(clickedRow, 4) == true and app.panel:IsShown(), "Public API reopens a hidden main panel")
provider.OpenQuickLook = function() error("quick look unavailable") end
check(app.openCraftingOrder(clickedRow) == true, "Quick look failure is isolated")
provider.OpenQuickLook = nil
check(app.openCraftingOrder(clickedRow) == true, "Compatibility API tolerates a missing quick look")
provider.OpenQuickLook = savedQuickLook
check(app.openCraftingOrder(77777777) == false, "Compatibility API rejects unknown recipe")
local undeathToWater = ns.ResolveCraftingOrderRecipe({ spellID = 17563 })
local earthToWater = ns.ResolveCraftingOrderRecipe({ spellID = 17561 })
check(undeathToWater and earthToWater and undeathToWater.outputItemID == earthToWater.outputItemID,
	"Distinct transmutes share one output item")
check(app.openCraftingOrder(undeathToWater) == true, "Compatibility API opens the requested transmute")
local transmuteHud = provider.GetQuickLookFrame()
check(transmuteHud and transmuteHud.row.recipe == undeathToWater,
	"Quick-Look shows the requested transmute when another recipe has the same output")
provider.CloseQuickLook()
local eventFrame
for _, frame in ipairs(frames) do
	if frame._events and frame._events.ADDON_LOADED and frame._scripts.OnEvent then eventFrame = frame; break end
end
check(eventFrame ~= nil, "Addon event frame available for persisted-route checks")
for oldTab, target in pairs({crafting="recipes", writ_profit="writs", crate_mats="crates"}) do
	MerchantMasterDB.v3HomeMigrated = true
	MerchantMasterDB.activeTab, MerchantMasterDB.prevFullTab = oldTab, oldTab
	eventFrame._scripts.OnEvent(eventFrame, "ADDON_LOADED", "MerchantMaster")
	check(app.activeTab == target and MerchantMasterDB.activeTab == target and MerchantMasterDB.prevFullTab == target,
		"Persisted legacy route " .. oldTab .. " redirects to " .. target)
	app.setTab(oldTab)
	check(app.activeTab == target and MerchantMasterDB.activeTab == target, "Legacy route " .. oldTab .. " redirects to " .. target)
	check(not app.ui.subStrip:IsShown(), "Canonical destination has no sub-tab strip")
end
for _, route in ipairs({
	{"crafting", "recipes"}, {"order", "recipes"}, {"orders", "recipes"},
	{"writprofit", "writs"}, {"writ_profit", "writs"}, {"wprofit", "writs"},
	{"demand", "writs"}, {"writdemand", "writs"}, {"writ_demand", "writs"},
	{"cratemats", "crates"}, {"crate_mats", "crates"}, {"mats", "crates"}, {"gather", "crates"},
}) do
	app.panel:Hide()
	SlashCmdList.MERCHANTMASTER(route[1])
	check(app.activeTab == route[2] and app.panel:IsShown(), "Slash alias " .. route[1] .. " opens " .. route[2])
end
app.setTab("recipes")
drain()

-- Planning remains independent of the removed crafting window.
local planRecipe, planQty, currentPlan
local function rebuildPlan()
	local ctx = app.buildSuperListContext()
	ns.BeginEval(app.getUIPriceBank())
	currentPlan = ns.BuildCraftingOrderPlan(planRecipe, planQty, MerchantMasterDB.craftOrderQueue, {
		profMap = ctx.profMap, repState = ctx.repState, ownedCounts = ctx.counts,
		subCraftMode = MerchantMasterDB.subCraftMode, subCraftOverrides = MerchantMasterDB.subCraftOverrides,
		deductOwned = MerchantMasterDB.craftOrderDeductOwned == true, applyAHCut = MerchantMasterDB.applyAHCut ~= false,
		priceBank = app.getUIPriceBank(), statsContext = app.getRecipeStatsContext(),
	})
	ns.EndEval()
	return currentPlan
end
local function buildOrder(rec, qty)
	planRecipe = rec
	planQty = qty or rec.numMade or 1
	return rebuildPlan()
end

-- 3. Multi-output batch math on Goblin Rocket Fuel (outputItemID = 9061, numMade = 2)
local grfRec
for _, rec in ipairs(ns.RECIPES) do
	if rec.outputItemID == 9061 and ns.GetRecipeSourceBucket(rec) ~= "gather" then
		grfRec = rec
		break
	end
end
check(grfRec ~= nil, "Located Goblin Rocket Fuel recipe (9061)")

local econ = ns.CurrentEconomyInfo().effectiveKey
MerchantMasterDB.ahPrices[econ] = MerchantMasterDB.ahPrices[econ] or {}
MerchantMasterDB.ahPrices[econ][9061] = { price = 18000, qty = 40, at = time() } -- 1g 80s each
for _, pair in ipairs(ns.ResolveRecipeReagents(grfRec)) do
	if not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[pair[1]]) then
		MerchantMasterDB.ahPrices[econ][pair[1]] = { price = 3500, qty = 100, at = time() }
	end
end
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local defaultPlan = buildOrder(grfRec)
check(defaultPlan.numMade == (grfRec.numMade or 1), "numMade matches Goblin Rocket Fuel")
buildOrder(grfRec, 5)
local grfPlan = currentPlan
check(grfPlan.reqQty == 5, "Requested quantity updated to 5")
if grfPlan.numMade == 2 then
	check(grfPlan.batches == 3 and grfPlan.actualOutput == 6, "5 units of 2x-per-craft recipe requires 3 batches = 6 output")
else
	check(grfPlan.batches == math.ceil(5 / grfPlan.numMade), "Batch ceiling computed accurately")
end
check(grfPlan.orderCost ~= nil and grfPlan.orderCost > 0, "Goblin Rocket Fuel order cost priced")
check(grfPlan.grossSale == 18000 * grfPlan.actualOutput, "Goblin Rocket Fuel gross sale matches unitAH * actualOutput")
check(grfPlan.netSale == math.floor(18000 * grfPlan.actualOutput * 0.95 + 0.5), "Goblin Rocket Fuel net sale applies 5% AH cut once")
check(grfPlan.netProfit == grfPlan.netSale - grfPlan.orderCost, "Goblin Rocket Fuel net profit equals netSale minus orderCost")

-- 4. Craft-Yourself vs Buy-AH comparison on a recipe with a craftable sub-material
local parentRec, subMatID, subRec
for _, rec in ipairs(ns.RECIPES) do
	if ns.GetRecipeSourceBucket(rec) ~= "gather" and rec.outputItemID and rec.reagents and #rec.reagents >= 1 then
		for _, pair in ipairs(rec.reagents) do
			local rid = pair[1]
			if not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[rid]) then
				local sr = ns.SelectBestRecipeForItem(rid, rec.prof, {})
				if sr and sr.reagents and #sr.reagents >= 1 and sr.outputItemID ~= rec.outputItemID then
					parentRec, subMatID, subRec = rec, rid, sr
					break
				end
			end
		end
	end
	if parentRec then break end
end
check(parentRec ~= nil and subMatID ~= nil and subRec ~= nil, "Found recipe with craftable intermediate sub-material")

-- Price leaf mats cheaply (10s) and intermediate sub-mat expensively on AH (90s) so Crafting Yourself is cheaper!
MerchantMasterDB.ahPrices[econ][parentRec.outputItemID] = { price = 50000, qty = 15, at = time() }
for _, pair in ipairs(parentRec.reagents) do
	if pair[1] == subMatID then
		MerchantMasterDB.ahPrices[econ][pair[1]] = { price = 9000, qty = 50, at = time() }
	elseif not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[pair[1]]) then
		MerchantMasterDB.ahPrices[econ][pair[1]] = { price = 1500, qty = 50, at = time() }
	end
end
for _, pair in ipairs(subRec.reagents) do
	if not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[pair[1]]) then
		MerchantMasterDB.ahPrices[econ][pair[1]] = { price = 1000, qty = 200, at = time() }
	end
end
-- Also price any 2nd-level sub-reagents if present
for _, pair in ipairs(subRec.reagents) do
	local sr2 = ns.SelectBestRecipeForItem(pair[1], subRec.prof, {})
	if sr2 and sr2.reagents then
		for _, p2 in ipairs(sr2.reagents) do
			if not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[p2[1]]) then
				MerchantMasterDB.ahPrices[econ][p2[1]] = { price = 500, qty = 200, at = time() }
			end
		end
	end
end
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

-- Case A: Player has NO professions -> craftCanDo must be false ([Need]), Buy All AH vs Best Price (All)
local oldGetProfs = ns.GetPlayerProfessions
ns.GetPlayerProfessions = function() return {} end
wipe(MerchantMasterDB.subCraftOverrides)
MerchantMasterDB.subCraftMode = "buy_only"
buildOrder(parentRec, 4)
drain()

local buyPlan = currentPlan
check(buyPlan.buyAllCost ~= nil and buyPlan.bestAllSubCost ~= nil, "Both Buy-All-AH and Best-Sub-Craft totals computed")
check(buyPlan.bestAllSubCost < buyPlan.buyAllCost, "Crafting sub-mat is cheaper than buying sub-mat on AH (" .. tostring(buyPlan.bestAllSubCost) .. " < " .. tostring(buyPlan.buyAllCost) .. ")")
check(buyPlan.orderCost == buyPlan.buyAllCost, "In buy_only mode, active orderCost equals buyAllCost")

local subRowInBuy
for _, r in ipairs(buyPlan.orderRows) do
	if r.itemID == subMatID and not r.isSubRow then subRowInBuy = r; break end
end
check(subRowInBuy ~= nil, "Intermediate sub-material row present in orderRows")
check(subRowInBuy.ahTotalPrice ~= nil and subRowInBuy.craftTotalPrice ~= nil, "Both AH price and Craft price shown side-by-side")
check(subRowInBuy.craftCanDo == false, "Without profession skill, craftCanDo is false")
check(subRowInBuy.makeMyself == false, "In buy_only mode, makeMyself is false")

-- Render embedded shopping table row to verify [Need] badge in cell 7
local shopTbl = app.ui.shopPanel.table
local testCellRow = CreateFrame("Button", nil, shopTbl.scrollBox)
shopTbl.scrollBox._view._initFn(testCellRow, subRowInBuy)
check(testCellRow.cells[7]:GetText():find("%[Need%]", 1, false) ~= nil, "Cell 7 displays [Need] when player lacks sub-craft profession")

-- Click [Best Price (All)] -> automatically switches sub-mat to Craft Yourself and expands + Sub-Mat rows!
MerchantMasterDB.subCraftMode = "all_sub"
rebuildPlan()
drain()
local allSubPlan = currentPlan
check(allSubPlan.orderCost == allSubPlan.bestAllSubCost, "Best Price (All) selects cheapest sub-craft option automatically")
check(allSubPlan.savingsVsBuyAll == (allSubPlan.buyAllCost - allSubPlan.bestAllSubCost) and allSubPlan.savingsVsBuyAll > 0, "Exact savings vs Buy All AH reported")
local expandedSubCount = 0
for _, r in ipairs(allSubPlan.orderRows) do
	if r.isSubRow then expandedSubCount = expandedSubCount + 1 end
end
check(expandedSubCount > 0, "Sub-crafting expands indented + Sub-Mat requirement rows")

-- Case B1: Player has skill 300, while non-starter sub-recipe is still UNLEARNED -> [Need], NOT [You]
ns.GetPlayerProfessions = function()
	return { [subRec.prof] = 300, [parentRec.prof] = 300 }
end
local oldIsKnown = ns.IsRecipeKnown
ns.IsRecipeKnown = function(rec)
	if rec == subRec or rec == parentRec then return false end
	return oldIsKnown(rec)
end
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
MerchantMasterDB.subCraftMode = "smart"
rebuildPlan()
drain()
local unlearnedSubRow
for _, r in ipairs(currentPlan.orderRows) do
	if r.itemID == subMatID and not r.isSubRow then unlearnedSubRow = r; break end
end
check(unlearnedSubRow ~= nil and unlearnedSubRow.craftCanDo == false, "Unlearned recipe with sufficient skill reports craftCanDo=false ([Need])")
check(not currentPlan.row.craftAbility.ableToCraft, "Unlearned parent recipe is not ready to craft")

-- Case B2: Player HAS learned both subRec and parentRec -> craftCanDo=true ([You]) and [Ready to Craft]!
ns.IsRecipeKnown = function(rec)
	if rec == subRec or rec == parentRec then return true end
	return oldIsKnown(rec)
end
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
app.refresh()
drain()
rebuildPlan()
local smartPlan = currentPlan
check(currentPlan.row.craftAbility.ableToCraft, "Learned parent recipe is ready to craft")
local subRowCanDo
for _, r in ipairs(smartPlan.orderRows) do
	if r.itemID == subMatID and not r.isSubRow then subRowCanDo = r; break end
end
check(subRowCanDo ~= nil and subRowCanDo.craftCanDo == true and subRowCanDo.makeMyself == true, "With recipe learned, craftCanDo=true and Best (My Profs) crafts sub-mat")
shopTbl.scrollBox._view._initFn(testCellRow, subRowCanDo)
check(testCellRow.cells[7]:GetText():find("%[You%]", 1, false) ~= nil, "Cell 7 displays [You] when player knows recipe")

-- Per-row click override on [Action] cell toggles Craft -> Buy AH, and Reset Auto clears it
testCellRow.cells[8]:Click("LeftButton")
drain()
rebuildPlan()
check(MerchantMasterDB.subCraftOverrides[subMatID] == "buy", "Clicking [Action] overrides sub-mat to Buy AH")
local subRowAfterOverride
for _, r in ipairs(currentPlan.orderRows) do
	if r.itemID == subMatID and not r.isSubRow then subRowAfterOverride = r; break end
end
check(subRowAfterOverride ~= nil and subRowAfterOverride.makeMyself == false, "Overridden sub-mat switches makeMyself to false")
check(currentPlan.orderCost > currentPlan.bestAllSubCost and currentPlan.orderCost <= currentPlan.buyAllCost,
	"Manual Buy override increases active orderCost above bestAllSubCost and at most buyAllCost")
wipe(MerchantMasterDB.subCraftOverrides)
rebuildPlan()
drain()
check(next(MerchantMasterDB.subCraftOverrides) == nil, "Reset Auto clears manual per-row overrides")
check(currentPlan.orderCost == smartPlan.orderCost, "After Reset Auto, smart mode restores optimal sub-craft cost")

-- 5. Deduct Owned Materials toggle
local subMatName = ns.ItemName(subMatID)
local prevIncludeBank = MerchantMasterDB.includeBank
MerchantMasterDB.includeBank = true
app.char.bank[subMatName] = 999
if app.invalidateRecipeStats then app.invalidateRecipeStats("ownership") else app.ownershipRev = (app.ownershipRev or 0) + 1 end
MerchantMasterDB.craftOrderDeductOwned = true
rebuildPlan()
drain()
check(MerchantMasterDB.craftOrderDeductOwned == true, "Use Owned persisted in DB")
local ownedPlan = currentPlan
local subRowOwned
for _, r in ipairs(ownedPlan.orderRows) do
	if r.itemID == subMatID and not r.isSubRow then subRowOwned = r; break end
end
check(subRowOwned ~= nil and subRowOwned.qty == 0 and subRowOwned.ownedUsed == subRowOwned.rawQty, "Owned sub-mat deducted to 0 net needed")
check(ownedPlan.orderCost < smartPlan.orderCost, "Deducting owned stock lowers active orderCost")
app.char.bank[subMatName] = nil
MerchantMasterDB.includeBank = prevIncludeBank
if app.invalidateRecipeStats then app.invalidateRecipeStats("ownership") else app.ownershipRev = (app.ownershipRev or 0) + 1 end
MerchantMasterDB.craftOrderDeductOwned = false
rebuildPlan()
drain()

-- 6. Shared queue APIs populate the modern shopping basket.
app.clearCraftingOrderQueue()
drain()
check(#MerchantMasterDB.craftOrderQueue == 0, "Order queue starts empty")
app.adjustRecipeShoppingQty(grfRec, 4)
app.adjustRecipeShoppingQty(parentRec, 2)
drain()
check(#MerchantMasterDB.craftOrderQueue == 2, "Two recipes added through shared quantity API")
local basketRows, _, _, basketMeta = app.syncUnifiedShoppingList()
check(#basketRows > 0 and #app.activeShoppingRows == #basketRows and basketMeta.mainCount == 2,
	"Active Shopping List holds merged multi-recipe basket")
app.toggleShoppingWindow(true)
check(app.ui.shopModal:IsShown(), "Shared shopping basket opens")
app.panel:SetSize(1600, 900)
app.layoutWindow()
app.clearCraftingOrderQueue()
drain()
check(#MerchantMasterDB.craftOrderQueue == 0 and #app.activeShoppingRows == 0, "Clear queue empties shared shopping basket")
app.toggleShoppingWindow(false)

-- 7. Deep 4-level expansion regression (Ornate Spyglass -> Bronze Tube -> Bronze Bar -> Tin Bar -> Tin Ore)
local spyglassRec
for _, rec in ipairs(ns.RECIPES) do
	if rec.name == "Ornate Spyglass" and ns.GetRecipeSourceBucket(rec) ~= "gather" then
		spyglassRec = rec
		break
	end
end
if spyglassRec then
	-- Price ores cheaply (10c) and bars/tubes expensively (5000c) so every level crafts down to Tin Ore (2771) / Copper Ore (2770)
	local function priceTreeCheaperToCraft(rec, depth)
		if not rec or depth > 5 then return end
		for _, pair in ipairs(rec.reagents or {}) do
			local rid = pair[1]
			if not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[rid]) then
				local sr = ns.SelectBestRecipeForItem(rid, rec.prof, {})
				if sr and sr.reagents and #sr.reagents > 0 then
					MerchantMasterDB.ahPrices[econ][rid] = { price = 5000, qty = 50, at = time() }
					priceTreeCheaperToCraft(sr, depth + 1)
				else
					MerchantMasterDB.ahPrices[econ][rid] = { price = 10, qty = 500, at = time() }
				end
			end
		end
	end
	priceTreeCheaperToCraft(spyglassRec, 1)
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	local spyPlan = ns.BuildCraftingOrderPlan(spyglassRec, 1, nil, {
		profMap = {},
		subCraftMode = "all_sub",
		deductOwned = false,
	})
	local tinBarCrafted, tinOrePresent = false, false
	for _, r in ipairs(spyPlan.orderRows) do
		if r.name == "Tin Bar" and r.makeMyself then tinBarCrafted = true end
		if r.name == "Tin Ore" and not r.makeMyself and r.qty > 0 then tinOrePresent = true end
	end
	check(tinBarCrafted and tinOrePresent, "Ornate Spyglass expands crafted Tin Bar all the way down to leaf Tin Ore")
end

-- 8. Recursive batch rounding & owned-deduction Best Price regression
local synLeaf, synMid, synTop = 990001, 990002, 990003
local recMid = { idx = 99991, spellID = 999991, name = "Syn Batch2 Sub", prof = "alchemy", skill = 1, numMade = 2, outputItemID = synMid, sellable = true, reagents = { { synLeaf, 1 } } }
local recTop = { idx = 99992, spellID = 999992, name = "Syn Top", prof = "alchemy", skill = 1, numMade = 1, outputItemID = synTop, sellable = true, reagents = { { synMid, 1 } } }
ns.RECIPES_BY_OUTPUT[synMid] = { recMid }
ns.RECIPES_BY_OUTPUT[synTop] = { recTop }
MerchantMasterDB.ahPrices[econ][synLeaf] = { price = 60, qty = 50, at = time() } -- 1 batch of recMid makes 2 for 60c (30c nominal unit, 60c actual for 1 needed!)
MerchantMasterDB.ahPrices[econ][synMid] = { price = 50, qty = 50, at = time() }  -- Buying 1 synMid on AH is 50c < 60c rounded batch!
MerchantMasterDB.ahPrices[econ][synTop] = { price = 200, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local roundPlan = ns.BuildCraftingOrderPlan(recTop, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(roundPlan.orderCost == 50 and roundPlan.orderRows[1].makeMyself == false and roundPlan.orderRows[1].craftTotalPrice == 60,
	"Best Price buys synMid for 50c instead of crafting 1 rounded batch for 60c")

local synLeafName = ns.ItemName(synLeaf)
local ownedFlipPlan = ns.BuildCraftingOrderPlan(recTop, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [synLeafName] = 5 },
	deductOwned = true,
})
check(ownedFlipPlan.orderCost == 0 and ownedFlipPlan.orderRows[1].makeMyself == true,
	"Owning leaf ingredient with Use Owned flips Best Price from Buy AH (50c) to Craft (0c)")

-- 9. Cyclic multi-output visited cache isolation regression (50c under visited={cycA} vs 25c fresh!)
local cycA, cycB = 990011, 990012
local recCycA = { idx = 99993, spellID = 999993, name = "CycA", prof = "alchemy", skill = 1, numMade = 2, outputItemID = cycA, sellable = true, reagents = { { cycB, 1 } } }
local recCycB = { idx = 99994, spellID = 999994, name = "CycB", prof = "alchemy", skill = 1, numMade = 2, outputItemID = cycB, sellable = true, reagents = { { cycA, 1 } } }
ns.RECIPES_BY_OUTPUT[cycA] = { recCycA }
ns.RECIPES_BY_OUTPUT[cycB] = { recCycB }
MerchantMasterDB.ahPrices[econ][cycA] = { price = 100, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][cycB] = { price = 100, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
ns.BeginEval()
do
	local optBRestricted = ns.GetItemCraftOption(cycB, { profMap = { alchemy = 300 }, subCraftMode = "all_sub" }, { [cycA] = true }, 0)
	check(optBRestricted ~= nil and optBRestricted.unitCraftCost == 50, "Depth-zero restricted visited={cycA} evaluates cycB to 50c")
end
local optAFirst = ns.GetItemCraftOption(cycA, { profMap = { alchemy = 300 }, subCraftMode = "all_sub" })
local optBAfterA = ns.GetItemCraftOption(cycB, { profMap = { alchemy = 300 }, subCraftMode = "all_sub" })
ns.EndEval()
ns.InvalidatePriceCache()
ns.BeginEval()
local optBFresh = ns.GetItemCraftOption(cycB, { profMap = { alchemy = 300 }, subCraftMode = "all_sub" })
ns.EndEval()
check(optAFirst ~= nil and optAFirst.unitCraftCost == 25, "Cyclic multi-output A evaluates to 25c")
check(optBAfterA ~= nil and optBFresh ~= nil and optBAfterA.unitCraftCost == 25 and optBAfterA.unitCraftCost == optBFresh.unitCraftCost,
	"GetItemCraftOption cache isolates visited cycle context (25c fresh vs 50c restricted)")

-- Clean up synthetic output recipes
ns.RECIPES_BY_OUTPUT[synMid] = nil
ns.RECIPES_BY_OUTPUT[synTop] = nil
ns.RECIPES_BY_OUTPUT[cycA] = nil
ns.RECIPES_BY_OUTPUT[cycB] = nil

-- 10. Stale explicit reference rejection in ResolveCraftingOrderRecipe & craftOrderQueue
check(ns.ResolveCraftingOrderRecipe({ idx = 999999, spellID = 88888888, outputItemID = 77777777, prof = "alchemy" }, {}) == nil,
	"Unresolved explicit table reference returns nil instead of falling back to first recipe")
check(ns.ResolveCraftingOrderRecipe(77777777, {}) == nil,
	"Unresolved explicit numeric itemID returns nil")
check(ns.BuildCraftingOrderPlan({ spellID = 88888888 }, 5, nil, {}) == nil,
	"BuildCraftingOrderPlan rejects stale explicit activeRef")
local staleQueuePlan = ns.BuildCraftingOrderPlan(grfRec, 2, {
	{ idx = 999999, spellID = 88888888, outputItemID = 77777777, prof = "alchemy", qty = 10 },
}, { profMap = {} })
check(#staleQueuePlan.queueEntries == 0 and #staleQueuePlan.queueRows == 0,
	"Stale persisted craftOrderQueue entry is ignored instead of buying unrelated materials")

-- 11. Distinct recipes sharing outputItemID + prof (e.g. Transmute: Earth to Water vs Undeath to Water) stay separate in basket
local sameOutA, sameOutB
local seenByOut = {}
for _, rec in ipairs(ns.RECIPES) do
	if ns.GetRecipeSourceBucket(rec) ~= "gather" and rec.outputItemID and rec.spellID and rec.spellID > 0 then
		local k = tostring(rec.prof) .. ":" .. tostring(rec.outputItemID)
		if seenByOut[k] and seenByOut[k].spellID ~= rec.spellID then
			sameOutA, sameOutB = seenByOut[k], rec
			break
		end
		seenByOut[k] = rec
	end
end
if sameOutA and sameOutB then
	app.clearCraftingOrderQueue()
	local oldCooldownInfo, oldCooldownGroup = ns.GetRecipeCooldownInfo, ns.GetRecipeCooldownGroup
	ns.GetRecipeCooldownInfo = function() return { nominalSeconds=86400, sharedGroup="test_transmute", windowLabel="day" } end
	ns.GetRecipeCooldownGroup = function() return "test_transmute" end
	check(app.adjustRecipeShoppingQty(sameOutA, 4) == 1, "Daily cooldown recipe queue caps at one craft")
	check(app.adjustRecipeShoppingQty(sameOutA, 1) == 1, "Repeated increment respects daily cooldown cap")
	check(app.adjustRecipeShoppingQty(sameOutB, 1) == 0 and app.getRecipeShoppingQty(sameOutB) == 0,
		"Shared cooldown blocks a second queued recipe")
	check(app.adjustRecipeShoppingQty(sameOutA, -1) == 0, "Cooldown queue permits removal")
	ns.GetRecipeCooldownInfo = function() return nil end
	app.adjustRecipeShoppingQty(sameOutA, 1)
	app.adjustRecipeShoppingQty(sameOutB, 2)
	ns.GetRecipeCooldownInfo, ns.GetRecipeCooldownGroup = oldCooldownInfo, oldCooldownGroup
	drain()
	check(#MerchantMasterDB.craftOrderQueue == 2
		and MerchantMasterDB.craftOrderQueue[1].spellID == sameOutA.spellID
		and MerchantMasterDB.craftOrderQueue[2].spellID == sameOutB.spellID,
		"Distinct recipes sharing outputItemID keep distinct basket entries")
	app.clearCraftingOrderQueue()
end

-- 12. Competing direct requirement reserves owned stock so Best Price never exceeds Buy All
local compLeaf, compMid, compParent = 990021, 990022, 990023
local recCompMid = { idx = 99996, spellID = 999996, name = "CompMid", prof = "alchemy", skill = 1, numMade = 1, outputItemID = compMid, sellable = true, reagents = { { compLeaf, 1 } } }
local recCompParent = { idx = 99997, spellID = 999997, name = "CompParent", prof = "alchemy", skill = 1, numMade = 1, outputItemID = compParent, sellable = true, reagents = { { compMid, 1 }, { compLeaf, 1 } } }
ns.RECIPES_BY_OUTPUT[compMid] = { recCompMid }
ns.RECIPES_BY_OUTPUT[compParent] = { recCompParent }
MerchantMasterDB.ahPrices[econ][compMid] = { price = 50, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][compLeaf] = { price = 80, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][compParent] = { price = 300, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local compPlan = ns.BuildCraftingOrderPlan(recCompParent, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(compLeaf)] = 1 },
	deductOwned = true,
})
check(compPlan.orderCost == 50 and compPlan.orderCost <= compPlan.buyAllCost,
	"Best Price reserves owned leaf for direct requirement (50c) instead of consuming it in sub-craft (80c)")

-- 13. Batch surplus from multi-output intermediate carries forward across branches + renders Surplus UI badge
local surpLeaf, surpMid, surpBranchA, surpBranchB, surpRoot = 990031, 990032, 990033, 990034, 990035
local recSurpMid = { idx = 99998, spellID = 999998, name = "SurpMid2x", prof = "alchemy", skill = 1, numMade = 2, outputItemID = surpMid, sellable = true, reagents = { { surpLeaf, 1 } } }
local recBranchA = { idx = 99999, spellID = 999999, name = "SurpBranchA", prof = "alchemy", skill = 1, numMade = 1, outputItemID = surpBranchA, sellable = true, reagents = { { surpMid, 1 } } }
local recBranchB = { idx = 100000, spellID = 1000000, name = "SurpBranchB", prof = "alchemy", skill = 1, numMade = 1, outputItemID = surpBranchB, sellable = true, reagents = { { surpMid, 1 } } }
local recSurpRoot = { idx = 100001, spellID = 1000001, name = "SurpRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = surpRoot, sellable = true, reagents = { { surpBranchA, 1 }, { surpBranchB, 1 } } }
ns.RECIPES_BY_OUTPUT[surpMid] = { recSurpMid }
ns.RECIPES_BY_OUTPUT[surpBranchA] = { recBranchA }
ns.RECIPES_BY_OUTPUT[surpBranchB] = { recBranchB }
ns.RECIPES_BY_OUTPUT[surpRoot] = { recSurpRoot }
MerchantMasterDB.ahPrices[econ][surpLeaf] = { price = 40, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][surpMid] = { price = 100, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][surpBranchA] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][surpBranchB] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][surpRoot] = { price = 500, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local surpPlan = ns.BuildCraftingOrderPlan(recSurpRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(surpPlan.orderCost == 40, "Surplus from 2x intermediate batch supplies second branch at 0 extra cost (40c total, not 80c)")

-- 13b. Shared 2x batch threshold across branches: 1 batch makes 2 for 60c vs AH 50c each -> 2 branches choose 60c craft instead of 100c AH buys
MerchantMasterDB.ahPrices[econ][surpLeaf] = { price = 60, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][surpMid] = { price = 50, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local singleBranchPlan = ns.BuildCraftingOrderPlan(recBranchA, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(singleBranchPlan.orderCost == 50, "Single branch needing 1 unit buys on AH for 50c instead of crafting 2x batch for 60c")
local sharedBatchPlan = ns.BuildCraftingOrderPlan(recSurpRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(sharedBatchPlan.orderCost == 60, "Two branches needing 1 unit each share 2x batch for 60c total instead of buying twice for 100c")

-- 13c. Shopping List UI renders Surplus (1x) badge and 0/1 qty instead of Buy AH on surplus-covered row
app.ui.shopPanel.setShoppingData(sharedBatchPlan.orderRows, "Surplus Test")
local shopBox = app.ui.shopPanel.table.scrollBox
local foundSurplusBadge = false
for _, rowData in ipairs(sharedBatchPlan.orderRows or {}) do
	local rFrame = CreateFrame("Button", nil, shopBox)
	shopBox._view._initFn(rFrame, rowData)
	if (rowData.surplusUsed or 0) > 0 and rowData.qty == 0 then
		local cell8Txt = rFrame.cells[8].fs:GetText() or ""
		local cell3Txt = rFrame.cells[3]:GetText() or ""
		if cell8Txt:find("Surplus", 1, true) and not cell8Txt:find("Buy AH", 1, true) and cell3Txt:find("0", 1, true) and cell3Txt:find("/1", 1, true) then
			foundSurplusBadge = true
		end
	end
end
check(foundSurplusBadge, "Surplus-covered row renders Surplus badge and 0/1 qty in Shopping List UI instead of Buy AH")

-- 13d. Rounded downstream batch counterexample (120c direct buy vs 130c false fractional credit):
-- BranchA needs 1x surpMid (AH=50c, 2x batch=60c). BranchB (AH=70c) needs 1x surpMid + 1x surpOther (numMade=2, 2x batch=80c, fractional unit=40c, AH=80c).
-- Even with free surplus surpMid, BranchB craft costs 0 + 80 = 80c > 70c AH, so BranchB buys on AH for 70c anyway!
-- Best Price MUST buy 1x surpMid (50c) + BranchB (70c) = 120c, NEVER craft 2x surpMid (60c) + BranchB (70c) = 130c!
local surpOtherLeaf, surpOther = 990036, 990037
local recSurpOther = { idx = 100003, spellID = 1000003, name = "SurpOther2x", prof = "alchemy", skill = 1, numMade = 2, outputItemID = surpOther, sellable = true, reagents = { { surpOtherLeaf, 1 } } }
local recTrapBranchB = { idx = 100004, spellID = 1000004, name = "TrapBranchB", prof = "alchemy", skill = 1, numMade = 1, outputItemID = 990038, sellable = true, reagents = { { surpMid, 1 }, { surpOther, 1 } } }
local recTrapRoot = { idx = 100005, spellID = 1000005, name = "TrapRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = 990039, sellable = true, reagents = { { surpBranchA, 1 }, { 990038, 1 } } }
ns.RECIPES_BY_OUTPUT[surpOther] = { recSurpOther }
ns.RECIPES_BY_OUTPUT[990038] = { recTrapBranchB }
ns.RECIPES_BY_OUTPUT[990039] = { recTrapRoot }
MerchantMasterDB.ahPrices[econ][surpOtherLeaf] = { price = 80, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][surpOther] = { price = 80, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][990038] = { price = 70, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][990039] = { price = 500, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local trapPlan = ns.BuildCraftingOrderPlan(recTrapRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(trapPlan.orderCost == 120,
	"Downstream rounded batch trap chooses 120c (50c + 70c) instead of 130c false fractional surplus credit")
ns.RECIPES_BY_OUTPUT[surpOther] = nil
ns.RECIPES_BY_OUTPUT[990038] = nil
ns.RECIPES_BY_OUTPUT[990039] = nil

-- 14. Unpriced queued basket reports queueCost=nil and (+N unpriced) header warning
local unpricedLeaf, unpricedOut = 990041, 990042
local recUnpriced = { idx = 100002, spellID = 1000002, name = "UnpricedRec", prof = "alchemy", skill = 1, numMade = 1, outputItemID = unpricedOut, sellable = true, reagents = { { unpricedLeaf, 1 } } }
table.insert(ns.RECIPES, recUnpriced)
MerchantMasterDB.ahPrices[econ][unpricedLeaf] = nil
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
app.clearCraftingOrderQueue()
app.adjustRecipeShoppingQty(recUnpriced, 1)
drain()
buildOrder(recUnpriced, 1)
check(currentPlan.queueMissing == 1 and currentPlan.queueCost == nil,
	"Unpriced basket sets queueMissing=1 and queueCost=nil")
check(app.activeShoppingSummary:find("unpriced", 1, true) ~= nil,
	"Queued basket header warns (+1 unpriced) when prices are missing")
app.clearCraftingOrderQueue()
table.remove(ns.RECIPES)

-- 15. sendShoppingRowsToBuyer deduplicates repeated leaf items + mixed owned/surplus/crafted/vendor rows
local oldEnterFlow = app.enterOrderFlowMode
app.enterOrderFlowMode = function() return true end
local sentDup = app.sendShoppingRowsToBuyer({
	{ itemID = 2840, name = "Copper Bar", qty = 2, rawQty = 2, makeMyself = true, isVendor = false, isSubRow = false },          -- crafted parent (excluded)
	{ itemID = 2770, name = "Copper Ore", qty = 3, rawQty = 5, ownedUsed = 2, makeMyself = false, isVendor = false, isSubRow = true }, -- partially owned leaf (3 needed)
	{ itemID = 3371, name = "Empty Vial", qty = 4, rawQty = 4, makeMyself = false, isVendor = true, isSubRow = false },           -- vendor reagent (excluded)
	{ itemID = 2771, name = "Tin Ore", qty = 0, rawQty = 3, ownedUsed = 3, makeMyself = false, isVendor = false, isSubRow = true },    -- fully owned (excluded)
	{ itemID = 2772, name = "Iron Ore", qty = 0, rawQty = 2, surplusUsed = 2, makeMyself = false, isVendor = false, isSubRow = true }, -- surplus covered (excluded)
	{ itemID = 2775, name = "Silver Ore", qty = 2, rawQty = 2, makeMyself = false, isVendor = false, isSubRow = true },          -- distinct leaf (2 needed)
	{ itemID = 2770, name = "Copper Ore", qty = 5, rawQty = 5, makeMyself = false, isVendor = false, isSubRow = true },          -- duplicate leaf across branch (+5 = 8 total)
}, "Dedup Mixed Test")
app.enterOrderFlowMode = oldEnterFlow
local cbSt15 = app.cartBuyer and app.cartBuyer.GetState and app.cartBuyer.GetState()
local capturedTerms = cbSt15 and cbSt15.items or nil
check(sentDup == true and capturedTerms ~= nil and #capturedTerms == 2,
	"sendShoppingRowsToBuyer excludes crafted/vendor/owned/surplus rows and merges duplicate leaves")
check(capturedTerms[1].itemID == 2770 and (capturedTerms[1].needed or capturedTerms[1].remaining) == 8
	and capturedTerms[2].itemID == 2775 and (capturedTerms[2].needed or capturedTerms[2].remaining) == 2,
	"Merged AH Buyer terms preserve net deducted + summed quantities (8 Copper Ore, 2 Silver Ore)")

-- 16. Canonical routes keep the sidebar available without the retired strip.
for _, tab in ipairs({"recipes", "writs", "crates", "profit_spread", "outliers"}) do
	app.setTab(tab)
	app.panel:SetSize(1320, 730)
	app.layoutWindow()
	check(app.ui.sidebar:IsShown() and not app.ui.subStrip:IsShown(), "Sidebar remains available on " .. tab)
end

-- 17. Shared owned-stock opportunity cost across branches (1c vs 100c in BOTH (A,B) and (B,A) orders)
local ownSharedLeaf, ownCheapA, ownPriceyB, ownRootAB, ownRootBA = 990051, 990052, 990053, 990054, 990055
local recCheapA = { idx = 100006, spellID = 1000006, name = "OwnCheapA", prof = "alchemy", skill = 1, numMade = 1, outputItemID = ownCheapA, sellable = true, reagents = { { ownSharedLeaf, 1 } } }
local recPriceyB = { idx = 100007, spellID = 1000007, name = "OwnPriceyB", prof = "alchemy", skill = 1, numMade = 1, outputItemID = ownPriceyB, sellable = true, reagents = { { ownSharedLeaf, 1 } } }
local recRootAB = { idx = 100008, spellID = 1000008, name = "OwnRootAB", prof = "alchemy", skill = 1, numMade = 1, outputItemID = ownRootAB, sellable = true, reagents = { { ownCheapA, 1 }, { ownPriceyB, 1 } } }
local recRootBA = { idx = 100009, spellID = 1000009, name = "OwnRootBA", prof = "alchemy", skill = 1, numMade = 1, outputItemID = ownRootBA, sellable = true, reagents = { { ownPriceyB, 1 }, { ownCheapA, 1 } } }
ns.RECIPES_BY_OUTPUT[ownCheapA] = { recCheapA }
ns.RECIPES_BY_OUTPUT[ownPriceyB] = { recPriceyB }
ns.RECIPES_BY_OUTPUT[ownRootAB] = { recRootAB }
ns.RECIPES_BY_OUTPUT[ownRootBA] = { recRootBA }
MerchantMasterDB.ahPrices[econ][ownSharedLeaf] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][ownCheapA] = { price = 1, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][ownPriceyB] = { price = 100, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][ownRootAB] = { price = 500, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][ownRootBA] = { price = 500, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local planAB = ns.BuildCraftingOrderPlan(recRootAB, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(ownSharedLeaf)] = 1 },
	deductOwned = true,
})
local planBA = ns.BuildCraftingOrderPlan(recRootBA, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(ownSharedLeaf)] = 1 },
	deductOwned = true,
})
check(planAB.orderCost == 1, "Owned stock opportunity cost (A=1c, B=100c) buys A and crafts B for 1c instead of 100c")
check(planBA.orderCost == 1, "Reversed branch order (B=100c, A=1c) also crafts B and buys A for 1c")
ns.RECIPES_BY_OUTPUT[ownCheapA] = nil
ns.RECIPES_BY_OUTPUT[ownPriceyB] = nil
ns.RECIPES_BY_OUTPUT[ownRootAB] = nil
ns.RECIPES_BY_OUTPUT[ownRootBA] = nil

-- 18. Stale legacy selection cannot replace or hide a valid queued basket.
app.clearCraftingOrderQueue()
app.adjustRecipeShoppingQty(grfRec, 2)
drain()
MerchantMasterDB.craftOrderRef = { idx = 999999, spellID = 88888888, outputItemID = 77777777, prof = "alchemy" }
app.setTab("crafting")
drain()
check(app.activeTab == "recipes" and #MerchantMasterDB.craftOrderQueue == 1 and #app.activeShoppingRows > 0,
	"Legacy route preserves valid basket despite stale saved selection")
check(app.openCraftingOrder(MerchantMasterDB.craftOrderRef) == false and #MerchantMasterDB.craftOrderQueue == 1,
	"Stale compatibility selection is rejected without altering basket")
app.clearCraftingOrderQueue()
check(app.openCraftingOrder({recipe=grfRec, salesPerDay=999}, 4) == true and app.selectedRecipeItemID == 9061,
	"Valid compatibility selection works after stale selection")

-- 19. -- 19. Consumed surplus lookahead across branches (201c vs 300c):
-- Producer makes 2x surpItem (1 used, 1 surplus) for 200c; CheapConsumer (AH=1c) needs 1x surpItem; PriceyConsumer (AH=100c) needs 1x surpItem (surpItem AH=200c).
-- Best Price buys CheapConsumer for 1c and saves the 1 surplus surpItem for PriceyConsumer (0c) -> 201c total, NEVER 300c!
local cSurpLeaf, cSurpItem, cProducer, cCheap, cPricey, cRoot = 990061, 990062, 990063, 990064, 990065, 990066
local recCSurp = { idx = 100010, spellID = 1000010, name = "CSurp2x", prof = "alchemy", skill = 1, numMade = 2, outputItemID = cSurpItem, sellable = true, reagents = { { cSurpLeaf, 1 } } }
local recCProducer = { idx = 100011, spellID = 1000011, name = "CProducer", prof = "alchemy", skill = 1, numMade = 1, outputItemID = cProducer, sellable = true, reagents = { { cSurpItem, 1 } } }
local recCCheap = { idx = 100012, spellID = 1000012, name = "CCheap", prof = "alchemy", skill = 1, numMade = 1, outputItemID = cCheap, sellable = true, reagents = { { cSurpItem, 1 } } }
local recCPricey = { idx = 100013, spellID = 1000013, name = "CPricey", prof = "alchemy", skill = 1, numMade = 1, outputItemID = cPricey, sellable = true, reagents = { { cSurpItem, 1 } } }
local recCRoot = { idx = 100014, spellID = 1000014, name = "CRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = cRoot, sellable = true, reagents = { { cProducer, 1 }, { cCheap, 1 }, { cPricey, 1 } } }
ns.RECIPES_BY_OUTPUT[cSurpItem] = { recCSurp }
ns.RECIPES_BY_OUTPUT[cProducer] = { recCProducer }
ns.RECIPES_BY_OUTPUT[cCheap] = { recCCheap }
ns.RECIPES_BY_OUTPUT[cPricey] = { recCPricey }
ns.RECIPES_BY_OUTPUT[cRoot] = { recCRoot }
MerchantMasterDB.ahPrices[econ][cSurpLeaf] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][cSurpItem] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][cProducer] = { price = 500, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][cCheap] = { price = 1, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][cPricey] = { price = 100, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][cRoot] = { price = 900, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local cSurpPlan = ns.BuildCraftingOrderPlan(recCRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(cSurpPlan.orderCost == 201,
	"Consumed surplus lookahead buys 1c intermediate and preserves surplus for 100c intermediate (201c total, not 300c)")
ns.RECIPES_BY_OUTPUT[cSurpItem] = nil
ns.RECIPES_BY_OUTPUT[cProducer] = nil
ns.RECIPES_BY_OUTPUT[cCheap] = nil
ns.RECIPES_BY_OUTPUT[cPricey] = nil
ns.RECIPES_BY_OUTPUT[cRoot] = nil

-- 20. Sales/day updates dynamically on refresh/economy change instead of freezing clicked row value
local oldDailySold = ns.GetDailySold
local oldStatsGet = ns.RecipeStats and ns.RecipeStats.Get or nil
local dynamicSales = 12.5
ns.GetDailySold = function(id)
	if id == 9061 then return dynamicSales end
	return oldDailySold(id)
end
if ns.RecipeStats then
	ns.RecipeStats.Get = function(rec, ctx)
		local st = oldStatsGet and oldStatsGet(rec, ctx) or {}
		if rec and rec.outputItemID == 9061 then
			local copy = {}
			for k, v in pairs(st) do copy[k] = v end
			copy.salesPerDay = dynamicSales
			return copy
		end
		return st
	end
end
buildOrder({ recipe = grfRec, salesPerDay = 999 }, 2)
drain()
check(currentPlan.dailySold == 12.5, "Core plan uses live economy Sales/day (12.5) instead of stale clicked hint (999)")
dynamicSales = 48.0
MerchantMasterDB.economy = "pvp_horde"
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
app.refresh()
drain()
rebuildPlan()
check(currentPlan.dailySold == 48.0, "Switching economy refreshes plan Sales/day dynamically (48.0)")
MerchantMasterDB.economy = "auto"
ns.GetDailySold = oldDailySold
if ns.RecipeStats and oldStatsGet then ns.RecipeStats.Get = oldStatsGet end

-- 21. 3-branch shared owned-stock permutation invariance (50c, 1c, 100c -> 51c across all 6 permutations + nested parent)
local permLeaf, perm50, perm1, perm100, permRoot, permSuper = 990071, 990072, 990073, 990074, 990075, 990076
ns.RECIPES_BY_OUTPUT[perm50] = { { idx = 100015, spellID = 1000015, name = "Perm50", prof = "alchemy", skill = 1, numMade = 1, outputItemID = perm50, sellable = true, reagents = { { permLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[perm1] = { { idx = 100016, spellID = 1000016, name = "Perm1", prof = "alchemy", skill = 1, numMade = 1, outputItemID = perm1, sellable = true, reagents = { { permLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[perm100] = { { idx = 100017, spellID = 1000017, name = "Perm100", prof = "alchemy", skill = 1, numMade = 1, outputItemID = perm100, sellable = true, reagents = { { permLeaf, 1 } } } }
MerchantMasterDB.ahPrices[econ][permLeaf] = { price = 250, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][perm50] = { price = 50, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][perm1] = { price = 1, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][perm100] = { price = 100, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][permRoot] = { price = 500, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][permSuper] = { price = 900, qty = 50, at = time() }
local perms = {
	{ perm50, perm1, perm100 },
	{ perm50, perm100, perm1 },
	{ perm1, perm50, perm100 },
	{ perm1, perm100, perm50 },
	{ perm100, perm50, perm1 },
	{ perm100, perm1, perm50 },
}
for pIdx, p in ipairs(perms) do
	local rPerm = { idx = 100020 + pIdx, spellID = 1000020 + pIdx, name = "PermRoot" .. pIdx, prof = "alchemy", skill = 1, numMade = 1, outputItemID = permRoot, sellable = true, reagents = { { p[1], 1 }, { p[2], 1 }, { p[3], 1 } } }
	ns.RECIPES_BY_OUTPUT[permRoot] = { rPerm }
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	local pPlan = ns.BuildCraftingOrderPlan(rPerm, 1, nil, {
		profMap = { alchemy = 300 },
		subCraftMode = "all_sub",
		ownedCounts = { [ns.ItemName(permLeaf)] = 1 },
		deductOwned = true,
	})
	check(pPlan.orderCost == 51, "3-branch shared owned-stock permutation #" .. pIdx .. " yields exact global minimum 51c (not 101c)")
end
local rNestedSuper = { idx = 100029, spellID = 1000029, name = "PermNestedSuper", prof = "alchemy", skill = 1, numMade = 1, outputItemID = permSuper, sellable = true, reagents = { { permRoot, 1 } } }
ns.RECIPES_BY_OUTPUT[permRoot] = { { idx = 100028, spellID = 1000028, name = "PermRoot50_1_100", prof = "alchemy", skill = 1, numMade = 1, outputItemID = permRoot, sellable = true, reagents = { { perm50, 1 }, { perm1, 1 }, { perm100, 1 } } } }
ns.RECIPES_BY_OUTPUT[permSuper] = { rNestedSuper }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local nestedPermPlan = ns.BuildCraftingOrderPlan(rNestedSuper, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(permLeaf)] = 1 },
	deductOwned = true,
})
check(nestedPermPlan.orderCost == 51, "Nested sibling 3-branch (50c, 1c, 100c) inside parent sub-craft also yields 51c")
ns.RECIPES_BY_OUTPUT[perm50] = nil
ns.RECIPES_BY_OUTPUT[perm1] = nil
ns.RECIPES_BY_OUTPUT[perm100] = nil
ns.RECIPES_BY_OUTPUT[permRoot] = nil
ns.RECIPES_BY_OUTPUT[permSuper] = nil

-- 22. Detached Shopping List window (shopModal) refreshes live when main panel is closed, allowing repeated Craft <-> Buy AH toggles
local copperRec = nil
for _, rec in ipairs(ns.RECIPES) do
	if ns.GetRecipeSourceBucket(rec) ~= "gather" then
		for _, pair in ipairs(ns.ResolveRecipeReagents(rec) or {}) do
			if pair[1] == 2840 then -- Copper Bar
				copperRec = rec
				break
			end
		end
	end
	if copperRec then break end
end
check(copperRec ~= nil, "Found recipe requiring Copper Bar (2840)")
MerchantMasterDB.subCraftMode = "buy_only"
wipe(MerchantMasterDB.subCraftOverrides)
app.clearCraftingOrderQueue()
app.adjustRecipeShoppingQty(copperRec, 1)
drain()
app.toggleShoppingWindow(true) -- open detached shopping list
app.panel:Hide()               -- close main window!
drain()
check(not app.panel:IsShown() and app.ui.shopModal:IsShown(), "Main panel hidden while detached shopModal stays open")

local function findCopperRowInActive()
	for _, r in ipairs(app.activeShoppingRows or {}) do
		if r.itemID == 2840 and not r.isSubRow then return r end
	end
	return nil
end
local function hasCopperOreSubInActive()
	for _, r in ipairs(app.activeShoppingRows or {}) do
		if r.itemID == 2770 and r.isSubRow then return true end
	end
	return false
end

local cbRow0 = findCopperRowInActive()
check(cbRow0 ~= nil and cbRow0.makeMyself == false and not hasCopperOreSubInActive(),
	"Initial detached Copper Bar row starts in Buy AH mode without Copper Ore sub-row")

-- Click [Action] cell on detached shopPanel row while main panel is closed
local detFrame1 = CreateFrame("Button", nil, shopBox)
shopBox._view._initFn(detFrame1, cbRow0)
detFrame1.cells[8]:GetScript("OnClick")(detFrame1.cells[8], "LeftButton")
drain()

local cbRow1 = findCopperRowInActive()
check(cbRow1 ~= nil and cbRow1.makeMyself == true and hasCopperOreSubInActive(),
	"Clicking Action in detached shopModal while main window is closed switches Copper Bar to Craft and expands Copper Ore")

-- Click [Action] cell a second time while main window is still closed to toggle back to Buy AH
local detFrame2 = CreateFrame("Button", nil, shopBox)
shopBox._view._initFn(detFrame2, cbRow1)
detFrame2.cells[8]:GetScript("OnClick")(detFrame2.cells[8], "LeftButton")
drain()

local cbRow2 = findCopperRowInActive()
check(cbRow2 ~= nil and cbRow2.makeMyself == false and not hasCopperOreSubInActive(),
	"Second click in detached shopModal toggles Copper Bar cleanly back to Buy AH and collapses Copper Ore")

app.toggleShoppingWindow(false)
app.panel:Show()
wipe(MerchantMasterDB.subCraftOverrides)
MerchantMasterDB.subCraftMode = "smart"

-- 23. Parent batch surplus visible inside child lookahead (0c vs 20c):
do
local pExLeaf, pExChild, pExParent, pExWrapB, pExRoot = 990081, 990082, 990083, 990084, 990085
local recPExChild = { idx = 100031, spellID = 1000031, name = "PExChild", prof = "alchemy", skill = 1, numMade = 1, outputItemID = pExChild, sellable = true, reagents = { { pExLeaf, 1 } } }
local recPExParent = { idx = 100032, spellID = 1000032, name = "PExParent2x", prof = "alchemy", skill = 1, numMade = 2, outputItemID = pExParent, sellable = true, reagents = { { pExChild, 1 } } }
local recPExWrapB = { idx = 100033, spellID = 1000033, name = "PExWrapB", prof = "alchemy", skill = 1, numMade = 1, outputItemID = pExWrapB, sellable = true, reagents = { { pExParent, 1 } } }
local recPExRoot = { idx = 100034, spellID = 1000034, name = "PExRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = pExRoot, sellable = true, reagents = { { pExParent, 1 }, { pExWrapB, 1 } } }
ns.RECIPES_BY_OUTPUT[pExChild] = { recPExChild }
ns.RECIPES_BY_OUTPUT[pExParent] = { recPExParent }
ns.RECIPES_BY_OUTPUT[pExWrapB] = { recPExWrapB }
ns.RECIPES_BY_OUTPUT[pExRoot] = { recPExRoot }
MerchantMasterDB.ahPrices[econ][pExLeaf] = { price = 300, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][pExChild] = { price = 20, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][pExParent] = { price = 500, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][pExWrapB] = { price = 400, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][pExRoot] = { price = 900, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local pExAutoPlan = ns.BuildCraftingOrderPlan(recPExRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(pExLeaf)] = 1 },
	deductOwned = true,
})
local pExForcedPlan = ns.BuildCraftingOrderPlan(recPExRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	subCraftOverrides = { [pExChild] = "craft" },
	ownedCounts = { [ns.ItemName(pExLeaf)] = 1 },
	deductOwned = true,
})
check(pExAutoPlan.orderCost == 0 and pExForcedPlan.orderCost == 0,
	"Child lookahead accounts for parent batch surplus (+1 P) and achieves 0c matching forced Craft (not 20c)")
ns.RECIPES_BY_OUTPUT[pExChild] = nil
ns.RECIPES_BY_OUTPUT[pExParent] = nil
ns.RECIPES_BY_OUTPUT[pExWrapB] = nil
ns.RECIPES_BY_OUTPUT[pExRoot] = nil
end

-- 24. Mixed floor-batch Craft + remainder Buy AH (110c vs 120c/150c) at top-level & sub-mat, plus 2-batch surplus win (120c vs 160c)
do
local mixOre, mixBar, mixMid, mixConsumer, mixTopRoot, mixSubRoot, mixSurpRoot = 990091, 990092, 990093, 990094, 990095, 990096, 990097
local recMixBar = { idx = 100035, spellID = 1000035, name = "MixBar2x", prof = "alchemy", skill = 1, numMade = 2, outputItemID = mixBar, sellable = true, reagents = { { mixOre, 1 } } }
local recMixMid = { idx = 100036, spellID = 1000036, name = "MixMid", prof = "alchemy", skill = 1, numMade = 1, outputItemID = mixMid, sellable = true, reagents = { { mixBar, 3 } } }
local recMixConsumer = { idx = 100037, spellID = 1000037, name = "MixConsumer", prof = "alchemy", skill = 1, numMade = 1, outputItemID = mixConsumer, sellable = true, reagents = { { mixBar, 1 } } }
local recMixTopRoot = { idx = 100038, spellID = 1000038, name = "MixTopRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = mixTopRoot, sellable = true, reagents = { { mixBar, 3 } } }
local recMixSubRoot = { idx = 100039, spellID = 1000039, name = "MixSubRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = mixSubRoot, sellable = true, reagents = { { mixMid, 1 } } }
local recMixSurpRoot = { idx = 100040, spellID = 1000040, name = "MixSurpRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = mixSurpRoot, sellable = true, reagents = { { mixMid, 1 }, { mixConsumer, 1 } } }
ns.RECIPES_BY_OUTPUT[mixBar] = { recMixBar }
ns.RECIPES_BY_OUTPUT[mixMid] = { recMixMid }
ns.RECIPES_BY_OUTPUT[mixConsumer] = { recMixConsumer }
ns.RECIPES_BY_OUTPUT[mixTopRoot] = { recMixTopRoot }
ns.RECIPES_BY_OUTPUT[mixSubRoot] = { recMixSubRoot }
ns.RECIPES_BY_OUTPUT[mixSurpRoot] = { recMixSurpRoot }
MerchantMasterDB.ahPrices[econ][mixOre] = { price = 60, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][mixBar] = { price = 50, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][mixMid] = { price = 500, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][mixConsumer] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][mixTopRoot] = { price = 900, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][mixSubRoot] = { price = 900, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][mixSurpRoot] = { price = 900, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local mixTopPlan = ns.BuildCraftingOrderPlan(recMixTopRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(mixTopPlan.orderCost == 110, "Top-level 3x of 2-yield item chooses 1 crafted batch (60c) + 1 AH buy (50c) = 110c (< 120c and < 150c)")
local oldEnterFlowMix = app.enterOrderFlowMode
app.enterOrderFlowMode = function() return true end
app.sendShoppingRowsToBuyer(mixTopPlan.orderRows, "Mix Top Test")
app.enterOrderFlowMode = oldEnterFlowMix
local cbStMix = app.cartBuyer and app.cartBuyer.GetState and app.cartBuyer.GetState()
local mixTerms = cbStMix and cbStMix.items or nil
check(mixTerms ~= nil and #mixTerms == 2 and mixTerms[1].itemID == mixOre and (mixTerms[1].needed or mixTerms[1].remaining) == 1
	and mixTerms[2].itemID == mixBar and (mixTerms[2].needed or mixTerms[2].remaining) == 1,
	"Mixed top-level shopping list sends 1x raw ore + 1x remainder bar to built-in AH Buyer")

local mixSubPlan = ns.BuildCraftingOrderPlan(recMixSubRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(mixSubPlan.orderCost == 110, "Nested sub-mat 3x of 2-yield item also chooses 110c mixed batch + AH top-up")

local mixSurpWinPlan = ns.BuildCraftingOrderPlan(recMixSurpRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(mixSurpWinPlan.orderCost == 120, "When later branch needs +1 unit (3+1=4), DP chooses 2 crafted batches (120c) over mixed+buy (160c)")
ns.RECIPES_BY_OUTPUT[mixBar] = nil
ns.RECIPES_BY_OUTPUT[mixMid] = nil
ns.RECIPES_BY_OUTPUT[mixConsumer] = nil
ns.RECIPES_BY_OUTPUT[mixTopRoot] = nil
ns.RECIPES_BY_OUTPUT[mixSubRoot] = nil
ns.RECIPES_BY_OUTPUT[mixSurpRoot] = nil
end

-- 25. Legacy routes never revive removed UI on repeated navigation.
for i = 1, 2 do
	app.setTab("crafting")
	drain()
	check(app.activeTab == "recipes" and app.ui.craftingView == nil, "Repeated legacy navigation uses All Recipes")
end

-- 26. Partial crafting with owned ingredients across exact multiples, non-multiples, single-output, nested sub-crafts, and large orders
do
local poLeaf, poMid2x, poMid1x, poNestedRoot, poTop4Root, poTop5Root, poSingleRoot, poLargeRoot =
	990101, 990102, 990103, 990104, 990105, 990106, 990107, 990108
ns.RECIPES_BY_OUTPUT[poMid2x] = { { idx = 100041, spellID = 1000041, name = "POMid2x", prof = "alchemy", skill = 1, numMade = 2, outputItemID = poMid2x, sellable = true, reagents = { { poLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[poMid1x] = { { idx = 100042, spellID = 1000042, name = "POMid1x", prof = "alchemy", skill = 1, numMade = 1, outputItemID = poMid1x, sellable = true, reagents = { { poLeaf, 1 } } } }
local recPONested = { idx = 100043, spellID = 1000043, name = "PONestedRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = poNestedRoot, sellable = true, reagents = { { poMid2x, 4 } } }
local recPOTop4 = { idx = 100044, spellID = 1000044, name = "POTop4Root", prof = "alchemy", skill = 1, numMade = 1, outputItemID = poTop4Root, sellable = true, reagents = { { poMid2x, 4 } } }
local recPOTop5 = { idx = 100045, spellID = 1000045, name = "POTop5Root", prof = "alchemy", skill = 1, numMade = 1, outputItemID = poTop5Root, sellable = true, reagents = { { poMid2x, 5 } } }
local recPOSingle = { idx = 100046, spellID = 1000046, name = "POSingleRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = poSingleRoot, sellable = true, reagents = { { poMid1x, 2 } } }
local recPOLarge = { idx = 100047, spellID = 1000047, name = "POLargeRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = poLargeRoot, sellable = true, reagents = { { poMid1x, 50 } } }
ns.RECIPES_BY_OUTPUT[poNestedRoot] = { recPONested }
ns.RECIPES_BY_OUTPUT[poTop4Root] = { recPOTop4 }
ns.RECIPES_BY_OUTPUT[poTop5Root] = { recPOTop5 }
ns.RECIPES_BY_OUTPUT[poSingleRoot] = { recPOSingle }
ns.RECIPES_BY_OUTPUT[poLargeRoot] = { recPOLarge }
MerchantMasterDB.ahPrices[econ][poLeaf] = { price = 200, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poMid2x] = { price = 50, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poMid1x] = { price = 50, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poNestedRoot] = { price = 1000, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poTop4Root] = { price = 1000, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poTop5Root] = { price = 1000, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poSingleRoot] = { price = 1000, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][poLargeRoot] = { price = 5000, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local poPlanTop4 = ns.BuildCraftingOrderPlan(recPOTop4, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(poLeaf)] = 1 },
	deductOwned = true,
})
check(poPlanTop4.orderCost == 100, "Exact-multiple 4x of 2-yield with 1 owned batch crafts 2 (0c) + buys 2 (100c) = 100c (not 200c)")

local poRowsNested, poCostNested = ns.BuildShoppingListRows({ { itemID = poNestedRoot, qty = 1, role = "Reagent", parentProf = "alchemy" } }, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(poLeaf)] = 1 },
	deductOwned = true,
})
check(poCostNested == 100 and #poRowsNested >= 3, "Nested sub-craft 4x of 2-yield with 1 owned batch also achieves 100c (not 200c)")

local poPlanTop5 = ns.BuildCraftingOrderPlan(recPOTop5, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(poLeaf)] = 1 },
	deductOwned = true,
})
check(poPlanTop5.orderCost == 150, "Non-multiple 5x of 2-yield with 1 owned batch crafts 2 (0c) + buys 3 (150c) = 150c (not 250c)")

local poPlanSingle = ns.BuildCraftingOrderPlan(recPOSingle, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(poLeaf)] = 1 },
	deductOwned = true,
})
check(poPlanSingle.orderCost == 50, "Single-output 2x with 1 owned ingredient crafts 1 (0c) + buys 1 (50c) = 50c (not 100c)")

local poPlanLarge = ns.BuildCraftingOrderPlan(recPOLarge, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(poLeaf)] = 3 },
	deductOwned = true,
})
check(poPlanLarge.orderCost == 2350, "Large 50x order with 3 owned leaves finds breakpoint b=3 -> 2350c (not 2500c)")

ns.RECIPES_BY_OUTPUT[poMid2x] = nil
ns.RECIPES_BY_OUTPUT[poMid1x] = nil
ns.RECIPES_BY_OUTPUT[poNestedRoot] = nil
ns.RECIPES_BY_OUTPUT[poTop4Root] = nil
ns.RECIPES_BY_OUTPUT[poTop5Root] = nil
ns.RECIPES_BY_OUTPUT[poSingleRoot] = nil
ns.RECIPES_BY_OUTPUT[poLargeRoot] = nil
end

-- 27. Nested multi-yield batch boundary split (90c vs 120c at qty=4, and 630c vs 660c/930c at qty=31 > 16):
do
local nbLeaf, nbChild3x, nbMid, nbRoot4, nbRoot31 = 990111, 990112, 990113, 990114, 990115
ns.RECIPES_BY_OUTPUT[nbChild3x] = { { idx = 100051, spellID = 1000051, name = "NBChild3x", prof = "alchemy", skill = 1, numMade = 3, outputItemID = nbChild3x, sellable = true, reagents = { { nbLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[nbMid] = { { idx = 100052, spellID = 1000052, name = "NBMid1x", prof = "alchemy", skill = 1, numMade = 1, outputItemID = nbMid, sellable = true, reagents = { { nbChild3x, 1 } } } }
local recNBRoot4 = { idx = 100053, spellID = 1000053, name = "NBRoot4", prof = "alchemy", skill = 1, numMade = 1, outputItemID = nbRoot4, sellable = true, reagents = { { nbMid, 4 } } }
local recNBRoot31 = { idx = 100054, spellID = 1000054, name = "NBRoot31", prof = "alchemy", skill = 1, numMade = 1, outputItemID = nbRoot31, sellable = true, reagents = { { nbMid, 31 } } }
ns.RECIPES_BY_OUTPUT[nbRoot4] = { recNBRoot4 }
ns.RECIPES_BY_OUTPUT[nbRoot31] = { recNBRoot31 }
MerchantMasterDB.ahPrices[econ][nbLeaf] = { price = 60, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][nbChild3x] = { price = 900, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][nbMid] = { price = 30, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][nbRoot4] = { price = 1000, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][nbRoot31] = { price = 5000, qty = 100, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local nbPlan4 = ns.BuildCraftingOrderPlan(recNBRoot4, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(nbPlan4.orderCost == 90, "Nested 3-yield child batch boundary splits 4x into 3 crafted (60c) + 1 bought (30c) = 90c (not 120c)")

local nbPlan31 = ns.BuildCraftingOrderPlan(recNBRoot31, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(nbPlan31.orderCost == 630, "Large 31x nested 3-yield boundary splits into 30 crafted (600c) + 1 bought (30c) = 630c (not 660c)")
ns.RECIPES_BY_OUTPUT[nbChild3x] = nil
ns.RECIPES_BY_OUTPUT[nbMid] = nil
ns.RECIPES_BY_OUTPUT[nbRoot4] = nil
ns.RECIPES_BY_OUTPUT[nbRoot31] = nil
end

-- 28. Missing ingredient price on excess batches still permits valid owned-ingredient partial craft + AH remainder (50c vs 100c)
do
local upLeaf, upMid, upParent, upTopRoot, upSubRoot = 990121, 990122, 990123, 990124, 990125
ns.RECIPES_BY_OUTPUT[upMid] = { { idx = 100055, spellID = 1000055, name = "UPMid", prof = "alchemy", skill = 1, numMade = 1, outputItemID = upMid, sellable = true, reagents = { { upLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[upParent] = { { idx = 100056, spellID = 1000056, name = "UPParent", prof = "alchemy", skill = 1, numMade = 1, outputItemID = upParent, sellable = true, reagents = { { upMid, 2 } } } }
local recUPTopRoot = { idx = 100057, spellID = 1000057, name = "UPTopRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = upTopRoot, sellable = true, reagents = { { upMid, 2 } } }
local recUPSubRoot = { idx = 100058, spellID = 1000058, name = "UPSubRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = upSubRoot, sellable = true, reagents = { { upParent, 1 } } }
ns.RECIPES_BY_OUTPUT[upTopRoot] = { recUPTopRoot }
ns.RECIPES_BY_OUTPUT[upSubRoot] = { recUPSubRoot }
MerchantMasterDB.ahPrices[econ][upLeaf] = nil -- UNPRICED on AH!
MerchantMasterDB.ahPrices[econ][upMid] = { price = 50, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][upParent] = { price = 500, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][upTopRoot] = { price = 900, qty = 50, at = time() }
MerchantMasterDB.ahPrices[econ][upSubRoot] = { price = 900, qty = 50, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local upTopPlan = ns.BuildCraftingOrderPlan(recUPTopRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(upLeaf)] = 1 },
	deductOwned = true,
})
check(upTopPlan.orderCost == 50 and upTopPlan.missingCount == 0 and upTopPlan.craftableMatCount == 1 and upTopPlan.selfCraftCount == 1,
	"Unpriced excess ingredient still crafts 1 owned unit (0c) + buys 1 on AH (50c) = 50c (not 100c)")

local upSubPlan = ns.BuildCraftingOrderPlan(recUPSubRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	ownedCounts = { [ns.ItemName(upLeaf)] = 1 },
	deductOwned = true,
})
check(upSubPlan.orderCost == 50 and upSubPlan.missingCount == 0,
	"Nested sub-craft with unpriced excess ingredient also crafts 1 owned unit (0c) + buys 1 on AH (50c) = 50c")

ns.RECIPES_BY_OUTPUT[upMid] = nil
ns.RECIPES_BY_OUTPUT[upParent] = nil
ns.RECIPES_BY_OUTPUT[upTopRoot] = nil
ns.RECIPES_BY_OUTPUT[upSubRoot] = nil
end

-- 29. Combined multi-yield LCM boundary split (demand=23 requiring A[yield 2 @ 200c] + B[yield 3 @ 300c], AH=230c -> craft 18 + buy 5 = 4750c, not 4760c)
do
local lcmLeafA, lcmLeafB, lcmChildA, lcmChildB, lcmMid, lcmRoot = 990131, 990132, 990133, 990134, 990135, 990136
ns.RECIPES_BY_OUTPUT[lcmChildA] = { { idx = 100061, spellID = 1000061, name = "LCMChildA", prof = "alchemy", skill = 1, numMade = 2, outputItemID = lcmChildA, sellable = true, reagents = { { lcmLeafA, 1 } } } }
ns.RECIPES_BY_OUTPUT[lcmChildB] = { { idx = 100062, spellID = 1000062, name = "LCMChildB", prof = "alchemy", skill = 1, numMade = 3, outputItemID = lcmChildB, sellable = true, reagents = { { lcmLeafB, 1 } } } }
ns.RECIPES_BY_OUTPUT[lcmMid] = { { idx = 100063, spellID = 1000063, name = "LCMMid", prof = "alchemy", skill = 1, numMade = 1, outputItemID = lcmMid, sellable = true, reagents = { { lcmChildA, 1 }, { lcmChildB, 1 } } } }
local recLCMRoot = { idx = 100064, spellID = 1000064, name = "LCMRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = lcmRoot, sellable = true, reagents = { { lcmMid, 23 } } }
ns.RECIPES_BY_OUTPUT[lcmRoot] = { recLCMRoot }
MerchantMasterDB.ahPrices[econ][lcmLeafA] = { price = 200, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][lcmLeafB] = { price = 300, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][lcmChildA] = { price = 900, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][lcmChildB] = { price = 900, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][lcmMid] = { price = 230, qty = 100, at = time() }
MerchantMasterDB.ahPrices[econ][lcmRoot] = { price = 9000, qty = 100, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local lcmPlan = ns.BuildCraftingOrderPlan(recLCMRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
})
check(lcmPlan.orderCost == 4750, "Combined LCM(2,3)=6 boundary crafts 18 (3600c) + buys 5 (1150c) = 4750c (not 4760c)")

ns.RECIPES_BY_OUTPUT[lcmChildA] = nil
ns.RECIPES_BY_OUTPUT[lcmChildB] = nil
ns.RECIPES_BY_OUTPUT[lcmMid] = nil
ns.RECIPES_BY_OUTPUT[lcmRoot] = nil
end

-- 30. Interior batch breakpoints across deep nested multi-yield chains (4x4=16 and 3x3x3=27 at demand=312 -> 270 crafted + 42 bought = 6417c, not 6449c)
do
local ib1, ib2, ib3, ib4, ib5, ib6, ib7, ib8, ibRoot = 990141, 990142, 990143, 990144, 990145, 990146, 990147, 990148, 990149
ns.RECIPES_BY_OUTPUT[ib3] = { { idx = 100071, spellID = 1000071, name = "IB3", prof = "alchemy", skill = 1, numMade = 4, outputItemID = ib3, sellable = true, reagents = { { ib1, 1 } } } }
ns.RECIPES_BY_OUTPUT[ib4] = { { idx = 100072, spellID = 1000072, name = "IB4", prof = "alchemy", skill = 1, numMade = 4, outputItemID = ib4, sellable = true, reagents = { { ib3, 1 } } } }
ns.RECIPES_BY_OUTPUT[ib5] = { { idx = 100073, spellID = 1000073, name = "IB5", prof = "alchemy", skill = 1, numMade = 3, outputItemID = ib5, sellable = true, reagents = { { ib2, 1 } } } }
ns.RECIPES_BY_OUTPUT[ib6] = { { idx = 100074, spellID = 1000074, name = "IB6", prof = "alchemy", skill = 1, numMade = 3, outputItemID = ib6, sellable = true, reagents = { { ib5, 1 } } } }
ns.RECIPES_BY_OUTPUT[ib7] = { { idx = 100075, spellID = 1000075, name = "IB7", prof = "alchemy", skill = 1, numMade = 3, outputItemID = ib7, sellable = true, reagents = { { ib6, 1 } } } }
ns.RECIPES_BY_OUTPUT[ib8] = { { idx = 100076, spellID = 1000076, name = "IB8", prof = "alchemy", skill = 1, numMade = 1, outputItemID = ib8, sellable = true, reagents = { { ib4, 1 }, { ib7, 1 } } } }
local recIBRoot = { idx = 100077, spellID = 1000077, name = "IBRoot", prof = "alchemy", skill = 1, numMade = 1, outputItemID = ibRoot, sellable = true, reagents = { { ib8, 312 } } }
ns.RECIPES_BY_OUTPUT[ibRoot] = { recIBRoot }
MerchantMasterDB.ahPrices[econ][ib1] = { price = 205, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib2] = { price = 205, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib3] = { price = 100000, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib4] = { price = 100000, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib5] = { price = 100000, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib6] = { price = 100000, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib7] = { price = 100000, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ib8] = { price = 21, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][ibRoot] = { price = 99999, qty = 500, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local ibPlanNoDeduct = ns.BuildCraftingOrderPlan(recIBRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = false,
	ownedCounts = {},
})
local ibPlanDeduct = ns.BuildCraftingOrderPlan(recIBRoot, 1, nil, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = true,
	ownedCounts = {},
})
check(ibPlanNoDeduct.orderCost == 6417 and ibPlanDeduct.orderCost == 6417,
	"Interior breakpoint 270 crafted (5535c) + 42 bought (882c) = 6417c chosen over 6449c (deductOwned both false & true)")

for _, id in ipairs({ ib3, ib4, ib5, ib6, ib7, ib8, ibRoot }) do
	ns.RECIPES_BY_OUTPUT[id] = nil
end
end

-- 31. Shared-stock partial allocation across branches is order-independent (A x 100 @ 20c + B x 30 @ 100c, own 100 shared leaf -> 600c in both orders; 3-branch -> 800c in all orders)
do
local shLeaf, shA, shB, shC = 990151, 990152, 990153, 990154
ns.RECIPES_BY_OUTPUT[shA] = { { idx = 100081, spellID = 1000081, name = "SharedA", prof = "alchemy", skill = 1, numMade = 1, outputItemID = shA, sellable = true, reagents = { { shLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[shB] = { { idx = 100082, spellID = 1000082, name = "SharedB", prof = "alchemy", skill = 1, numMade = 1, outputItemID = shB, sellable = true, reagents = { { shLeaf, 1 } } } }
ns.RECIPES_BY_OUTPUT[shC] = { { idx = 100083, spellID = 1000083, name = "SharedC", prof = "alchemy", skill = 1, numMade = 1, outputItemID = shC, sellable = true, reagents = { { shLeaf, 1 } } } }
MerchantMasterDB.ahPrices[econ][shLeaf] = { price = 500, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][shA] = { price = 20, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][shB] = { price = 100, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][shC] = { price = 50, qty = 500, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local own100 = { [ns.ItemName(shLeaf)] = 100 }
local _, costAB = ns.BuildShoppingListRows({ { itemID = shA, qty = 100 }, { itemID = shB, qty = 30 } }, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = true,
	ownedCounts = own100,
})
local _, costBA = ns.BuildShoppingListRows({ { itemID = shB, qty = 30 }, { itemID = shA, qty = 100 } }, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = true,
	ownedCounts = own100,
})
check(costAB == 600 and costBA == 600, "2-branch shared owned stock reserves 30 for B and crafts 70 A + buys 30 A = 600c in both [A,B] and [B,A]")

local _, costABC = ns.BuildShoppingListRows({ { itemID = shA, qty = 60 }, { itemID = shC, qty = 50 }, { itemID = shB, qty = 30 } }, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = true,
	ownedCounts = own100,
})
local _, costCBA = ns.BuildShoppingListRows({ { itemID = shB, qty = 30 }, { itemID = shC, qty = 50 }, { itemID = shA, qty = 60 } }, {
	profMap = { alchemy = 300 },
	subCraftMode = "all_sub",
	deductOwned = true,
	ownedCounts = own100,
})
check(costABC == 800 and costCBA == 800, "3-branch shared owned stock reserves 50+30=80 and crafts 20 A + buys 40 A = 800c regardless of order")

ns.RECIPES_BY_OUTPUT[shA] = nil
ns.RECIPES_BY_OUTPUT[shB] = nil
ns.RECIPES_BY_OUTPUT[shC] = nil
end

-- 32. Cross-profession material merge preserves each demand's profession eligibility in Smart mode
do
local cpCloth, cpBolt, cpEngOut, cpTailorOut = 990161, 990162, 990163, 990164
local recBolt = { idx = 100091, spellID = 1000091, name = "CPBolt", prof = "tailoring", skill = 125, numMade = 1, outputItemID = cpBolt, sellable = true, reagents = { { cpCloth, 4 } } }
local recEng = { idx = 100092, spellID = 1000092, name = "CPEng", prof = "engineering", skill = 150, numMade = 1, outputItemID = cpEngOut, sellable = true, reagents = { { cpBolt, 2 } } }
local recTailor = { idx = 100093, spellID = 1000093, name = "CPTailor", prof = "tailoring", skill = 150, numMade = 1, outputItemID = cpTailorOut, sellable = true, reagents = { { cpBolt, 8 } } }
ns.RECIPES_BY_OUTPUT[cpBolt] = { recBolt }
ns.RECIPES[recEng.idx] = recEng
ns.RECIPES[recTailor.idx] = recTailor
MerchantMasterDB.ahPrices[econ][cpCloth] = { price = 10, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][cpBolt] = { price = 100, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][cpEngOut] = { price = 500, qty = 500, at = time() }
MerchantMasterDB.ahPrices[econ][cpTailorOut] = { price = 1000, qty = 500, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local rowsET, costET = ns.BuildShoppingListRows({
	{ itemID = cpBolt, qty = 2, parentProf = "engineering" },
	{ itemID = cpBolt, qty = 8, parentProf = "tailoring" },
}, { subCraftMode = "smart", profMap = {} })
local rowsTE, costTE = ns.BuildShoppingListRows({
	{ itemID = cpBolt, qty = 8, parentProf = "tailoring" },
	{ itemID = cpBolt, qty = 2, parentProf = "engineering" },
}, { subCraftMode = "smart", profMap = {} })
check(costET == 400 and costTE == 400 and rowsET[1].makeMyself == true and rowsTE[1].makeMyself == true,
	"Cross-profession merged material preserves tailoring eligibility (400c Craft in both engineering-first and tailoring-first)")

local qPlanET = ns.BuildCraftingOrderPlan(recEng, 1, {
	{ idx = recEng.idx, spellID = recEng.spellID, outputItemID = cpEngOut, qty = 1 },
	{ idx = recTailor.idx, spellID = recTailor.spellID, outputItemID = cpTailorOut, qty = 1 },
}, { subCraftMode = "smart", profMap = {} })
local qPlanTE = ns.BuildCraftingOrderPlan(recEng, 1, {
	{ idx = recTailor.idx, spellID = recTailor.spellID, outputItemID = cpTailorOut, qty = 1 },
	{ idx = recEng.idx, spellID = recEng.spellID, outputItemID = cpEngOut, qty = 1 },
}, { subCraftMode = "smart", profMap = {} })
check(qPlanET.queueCost == 400 and qPlanTE.queueCost == 400,
	"Basket queueCost is 400c regardless of engineering-first or tailoring-first queue order")

ns.RECIPES_BY_OUTPUT[cpBolt] = nil
ns.RECIPES[recEng.idx] = nil
ns.RECIPES[recTailor.idx] = nil
end

ns.RECIPES_BY_OUTPUT[compMid] = nil
ns.RECIPES_BY_OUTPUT[compParent] = nil
ns.RECIPES_BY_OUTPUT[surpMid] = nil
ns.RECIPES_BY_OUTPUT[surpBranchA] = nil
ns.RECIPES_BY_OUTPUT[surpBranchB] = nil
ns.RECIPES_BY_OUTPUT[surpRoot] = nil

ns.IsRecipeKnown = oldIsKnown
ns.GetPlayerProfessions = savedGetProfsInit
_G.IsShiftKeyDown = oldShift
app.searchAH = oldSearch
C_Timer.After = oldAfter

print("PASS: Crafting Order suite (" .. n .. " assertions, 0 failures)")
