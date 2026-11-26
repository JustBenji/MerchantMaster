local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames, hostEnv = dofile(S .. "host_fixture.lua")

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local app = ns.app

local function stripColors(s)
	return tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function btnText(b)
	if not b then return "" end
	local t = b.GetText and b:GetText() or ""
	if t ~= "" then return t end
	return (b.fs and b.fs.GetText and b.fs:GetText()) or ""
end

local function setupScrollTable(tbl)
	local box = tbl.scrollBox
	local pool = {}
	local capacity = 40
	box._frames = pool
	box.GetHeight = function() return capacity * app.ui.ROW_H end
	local function render()
		local items = box._dp and box._dp:GetCollection() or {}
		for i = 1, math.max(capacity, #pool) do
			local r = pool[i]
			if i <= #items then
				if not r then
					r = CreateFrame("Button", nil, box)
					pool[i] = r
				end
				r:Show()
				box._view._initFn(r, items[i])
			elseif r then
				r:Hide()
			end
		end
	end
	function box:SetDataProvider(dp)
		self._dp = dp
		render()
	end
	function box:FullUpdate() render() end
	function box:ForEachFrame(fn)
		for _, r in ipairs(pool) do
			if r:IsShown() then fn(r) end
		end
	end
	return pool, render
end

local shopPool, renderShop = setupScrollTable(app.ui.shopPanel.table)

-- Clean DB queues and deterministic profession/price stubs
MerchantMasterDB.craftOrderQueue = {}
MerchantMasterDB.writCraftQueue = {}
MerchantMasterDB.spreadQueue = {}
MerchantMasterDB.writTurnInQueue = {}
MerchantMasterDB.shoppingList = {}
MerchantMasterDB.subCraftOverrides = {}
MerchantMasterDB.subCraftMode = "smart"
MerchantMasterDB.craftOrderDeductOwned = false
MerchantMasterDB.shoppingSortScope = "main"
MerchantMasterDB.sort = MerchantMasterDB.sort or {}
app.sortState.shopping_list = { col = "default", asc = true }

local savedGetProfs = ns.GetPlayerProfessions
local savedGetCost = ns.GetReagentUnitCost
local savedGetListed = ns.GetNumListed
local savedGetDaily = ns.GetDailySold
local savedGetOwned = ns.GetOwnedItemCounts
local savedSearchAH = app.searchAH
local savedAuc = _G.Auctionator

local PRICE_TABLE = {
	[6037] = { 999999, "AH", false }, -- Truesilver Bar
	[3860] = { 10, "AH", false }, -- Mithril Bar
	[7910] = { 100, "AH", false }, -- Star Ruby
	[10559] = { 100, "AH", false }, -- Mithril Tube
	[6049] = { 22000, "AH", false }, -- Fire Protection Potion
	[6371] = { 8000,  "AH", false }, -- Fire Oil (cheaper to craft: 2*1500 + 40 = 3040)
	[6359] = { 1500,  "AH", false }, -- Firefin Snapper
	[3371] = { 40,    "Vendor", true }, -- Empty Vial
	[3372] = { 200,   "Vendor", true }, -- Leaded Vial
	[4402] = { 5000,  "AH", false }, -- Small Flame Sac
	[2450] = { 1000,  "AH", false }, -- Briarthorn
	[2453] = { 900,   "AH", false }, -- Bruiseweed
}

ns.GetPlayerProfessions = function()
	return { alchemy = 300 }
end
ns.GetOwnedItemCounts = function() return {} end
ns.GetReagentUnitCost = function(itemID)
	local hit = PRICE_TABLE[itemID]
	if hit then return hit[1], hit[2], hit[3] end
	return savedGetCost(itemID)
end
ns.GetNumListed = function(itemID)
	if PRICE_TABLE[itemID] then return 25 end
	return savedGetListed(itemID)
end
ns.GetDailySold = function(itemID)
	if PRICE_TABLE[itemID] then return 12.5 end
	return savedGetDaily(itemID)
end

local savedAHFrame = _G.AuctionHouseFrame
_G.AuctionHouseFrame = { IsShown = function() return true end, Show = function() end, Hide = function() end, GetHeight = function() return 600 end }
local savedEnterOrderFlow = app.enterOrderFlowMode
app.enterOrderFlowMode = function() return true end

if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

do
	local demand = { { itemID=6037, qty=3, role="Reagent", parentProf="engineering" } }
	local opts = { profMap={alchemy=300,engineering=300}, subCraftMode="smart" }
	local rows, cost = ns.BuildShoppingListRows(demand, opts)
	check(cost==3*999999 and not rows[1].makeMyself, "Smart shopping buys cooldown reagents at the recipe estimate")
	opts.subCraftOverrides = { [6037]="craft" }
	rows, cost = ns.BuildShoppingListRows(demand, opts)
	check(cost==30 and rows[1].makeMyself, "An explicit craft override still makes cooldown reagents")
	opts.subCraftOverrides = nil
	demand[1].forceMakeMyself = true
	rows, cost = ns.BuildShoppingListRows(demand, opts)
	check(cost==30 and rows[1].makeMyself, "A forced demand still makes cooldown reagents")

	demand = { { itemID=10548, qty=1, role="Reagent", forceMakeMyself=true } }
	for _, route in ipairs({ "auto", "craft" }) do
		opts.subCraftOverrides = { [6037]=route=="craft" and route or nil }
		rows = ns.BuildShoppingListRows(demand, opts)
		local silver
		for _, row in ipairs(rows) do
			if row.itemID==6037 then silver=row; break end
		end
		local craft = route=="craft"
		check(silver and silver.isSubRow and silver.makeMyself==craft and silver.lineCost==(craft and 20 or 2*999999),
			"Nested Sniper Scope reagents honor cooldown routing in " .. route .. " mode")
	end
end

-- 1. Unified button labels & modal title check
check(app.ui.shopPanel.buyAllBtn ~= nil, "shopPanel has Send All to Auctionator button")
check(app.ui.shopPanel.clearShopBtn ~= nil, "shopPanel has Clear Shopping List button")
check(app.ui.shopPanel.sortScopeBtn ~= nil, "shopPanel has Sort Main/Sub toggle button")
check(btnText(app.ui.dashShopBtn) == "Shopping List", "Dashboard button says Shopping List")
check(btnText(app.ui.spreadShopBtn) == "Shopping List", "Spread button says Shopping List")
check(btnText(app.ui.writsShopBtn) == "Shopping List", "Writs button says Shopping List")
check(btnText(app.ui.calcOpenShopBtn) == "Shopping List", "Calculator button says Shopping List")
if app.ui.recOpenShopBtn then
	check(btnText(app.ui.recOpenShopBtn) == "Shopping List", "SuperList button says Shopping List")
end

-- 2. Add Fire Protection Potion (6049, spell 7257) and verify 3-level hierarchy
app.panel:Show()
app.setTab("recipes")
MerchantMasterDB.craftOrderQueue = {
	{ spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 1 },
}
app.toggleShoppingWindow(true)
app.refresh()
renderShop()

local rows = app.activeShoppingRows
check(#rows == 6, "Expected 6 rows (1 main Fire Protection Potion + 3 sub + 2 sub-craft under Fire Oil), got " .. tostring(#rows))
check(rows[1].isMainRow == true and rows[1].itemID == 6049, "Row 1 is Main Item Fire Protection Potion")
check(rows[1].canRemoveMain == true, "Main Item has Remove action")
check(rows[1].groupTotalCost == 8240, "Fire Protection Potion leaf cost uses Fire Oil craft cost (3040 + 5000 + 200 = 8240), got " .. tostring(rows[1].groupTotalCost))
check(stripColors(shopPool[1].cells[2]:GetText()):find("Main:", 1, true) ~= nil, "UI Main Item Category col shows Main:")
check(shopPool[1].cells[8]._actionTag == "Remove" and shopPool[1].cells[8].icon and shopPool[1].cells[8].icon:IsShown(), "UI Main Order card shows framed X Remove button")

local fireOilRowIdx
for i, r in ipairs(rows) do
	if not r.isMainRow and r.itemID == 6371 then
		fireOilRowIdx = i
		break
	end
end
check(fireOilRowIdx ~= nil, "Fire Oil present as Level 1 Sub-Item")
local fireOilRow = rows[fireOilRowIdx]
check(fireOilRow.rowKind == "sub" and fireOilRow.indent == 1, "Fire Oil is Level 1 Sub-Item")
check(fireOilRow.categoryName:find("Fire Protection Potion", 1, true) ~= nil, "Fire Oil Category is Fire Protection Potion")
check(fireOilRow.canToggleCraft == true and fireOilRow.makeMyself == true, "Fire Oil defaults to Craft (30s 40c < 80s)")
check(stripColors(shopPool[fireOilRowIdx].cells[2]:GetText()):find("Fire Protection Potion", 1, true) ~= nil, "UI Category cell shows Fire Protection Potion for Fire Oil")
check(stripColors(btnText(shopPool[fireOilRowIdx].cells[8])):find("CRAFT", 1, true) ~= nil, "UI Action pill shows CRAFT when Fire Oil is set to Craft")

local next1 = rows[fireOilRowIdx + 1]
local next2 = rows[fireOilRowIdx + 2]
check(next1 and next1.isSubRow == true and (next1.itemID == 6359 or next1.itemID == 3371), "Fire Oil crafted breakdown appears directly underneath Fire Oil")
check(next2 and next2.isSubRow == true and (next2.itemID == 6359 or next2.itemID == 3371) and next1.itemID ~= next2.itemID, "Both Firefin Snapper and Empty Vial appear under Fire Oil")
check(next1.indent == 2 and next2.indent == 2, "Crafted sub-items are indented Level 2 under Fire Oil")

-- 3. Send to Auction House skips Main Item, crafted Fire Oil, and Vendors -> sends ONLY Firefin Snapper (2) + Small Flame Sac (1)
app.ui.shopPanel.buyAllBtn:Click("LeftButton")
local cbState = app.cartBuyer and app.cartBuyer.GetState and app.cartBuyer.GetState()
check(cbState ~= nil and type(cbState.items) == "table" and #cbState.items > 0, "Send to Auction House loaded items into built-in AH Buyer")
local byName = {}
for _, t in ipairs(cbState.items or {}) do byName[t.name or t.searchString] = t.needed or t.remaining or t.qty or t.quantity end
check(byName[ns.ItemName(6049)] == nil, "Main Item (Fire Protection Potion) skipped from AH Buyer")
check(byName[ns.ItemName(6371)] == nil, "Crafted Sub-Item (Fire Oil) skipped from AH Buyer")
check(byName[ns.ItemName(3371)] == nil and byName[ns.ItemName(3372)] == nil, "NPC Vendor vials skipped from AH Buyer")
check(byName[ns.ItemName(6359)] == 2 and byName[ns.ItemName(4402)] == 1, "Exact leaf AH quantities sent: Firefin Snapper=2, Small Flame Sac=1")

-- 4. Click UI side toggle button on Fire Oil -> Buy -> Craft collapse/expand
shopPool[fireOilRowIdx].cells[8]:Click("LeftButton")
renderShop()
rows = app.activeShoppingRows
check(#rows == 4, "Switching Fire Oil to Buy collapses its 2 sub-reagents (1 main + 3 sub = 4), got " .. tostring(#rows))
check(rows[1].groupTotalCost == 13200, "Switching Fire Oil to Buy updates Main Item total to 8000+5000+200=13200, got " .. tostring(rows[1].groupTotalCost))
local newFireOilIdx
for i, r in ipairs(rows) do
	if not r.isMainRow and r.itemID == 6371 then newFireOilIdx = i; break end
end
check(newFireOilIdx ~= nil and rows[newFireOilIdx].makeMyself == false, "Fire Oil switched to Buy mode")
check(stripColors(btnText(shopPool[newFireOilIdx].cells[8])) == "BUY AH", "UI Action pill shows BUY AH when Fire Oil is in Buy mode")

app.ui.shopPanel.buyAllBtn:Click("LeftButton")
cbState = app.cartBuyer and app.cartBuyer.GetState and app.cartBuyer.GetState()
byName = {}
for _, t in ipairs((cbState and cbState.items) or {}) do byName[t.name or t.searchString] = t.needed or t.remaining or t.qty or t.quantity end
check(byName[ns.ItemName(6371)] == 1 and byName[ns.ItemName(4402)] == 1 and byName[ns.ItemName(6359)] == nil, "Built-in AH Buyer now buys Fire Oil=1 + Small Flame Sac=1 instead of Firefin Snapper")

-- Toggle Fire Oil back to Craft via UI click
shopPool[newFireOilIdx].cells[8]:Click("LeftButton")
renderShop()
check(#app.activeShoppingRows == 6, "Clicking [Buy -> Craft] restores 6-row 3-level tree")

-- 5. Scoped category override isolation + second Main Item + cross-screen persistence
app.addUnifiedShoppingItem({
	key = "custom:alpha_bundle",
	name = "Alpha Fire Bundle",
	qty = 1,
	sourceLabel = "Custom",
	reagents = { { 6371, 2 }, { 2450, 1 } },
})
renderShop()
check(#app.activeShoppingRows == 11, "Adding second craft Main Item gives 11 rows (6 + 5), got " .. tostring(#app.activeShoppingRows))

-- Toggle Fire Oil inside Alpha Fire Bundle ONLY -> Fire Protection Potion Fire Oil MUST remain Craft!
local alphaFireOilIdx, fppFireOilCraft
for i, r in ipairs(app.activeShoppingRows) do
	if not r.isMainRow and r.itemID == 6371 then
		if r.categoryName == "Alpha Fire Bundle" then
			alphaFireOilIdx = i
		elseif r.categoryName == "Fire Protection Potion" then
			fppFireOilCraft = r.makeMyself
		end
	end
end
check(alphaFireOilIdx ~= nil and fppFireOilCraft == true, "Both categories show Fire Oil independently")
shopPool[alphaFireOilIdx].cells[8]:Click("LeftButton")
renderShop()
local postAlphaBuy, postFppCraft = false, false
for _, r in ipairs(app.activeShoppingRows) do
	if not r.isMainRow and r.itemID == 6371 then
		if r.categoryName == "Alpha Fire Bundle" then postAlphaBuy = (r.makeMyself == false) end
		if r.categoryName == "Fire Protection Potion" then postFppCraft = (r.makeMyself == true) end
	end
end
check(postAlphaBuy == true and postFppCraft == true, "Toggling Fire Oil in one category does NOT alter Fire Oil in another category")

-- Add items via writCraftQueue and writTurnInQueue too, then switch across ALL screens
MerchantMasterDB.writCraftQueue = { [2450] = 2 }
app.refresh()
local expectedTitle = stripColors(app.ui.shopModal.titleFs:GetText())
local isCustomSkinNow = ns.Theme.IsCustomSkin and ns.Theme.IsCustomSkin()
local wantModalTitle = isCustomSkinNow and "SHOPPING LIST" or "Shopping List"
check(expectedTitle == wantModalTitle, "Unified shopModal title is " .. wantModalTitle .. ", got: " .. expectedTitle)
local expectedCount = #app.activeShoppingRows
local tabs = { "dashboard", "profit_spread", "outliers", "crates", "writs", "recipes", "rep", "calc_favor", "calc_rep", "prof_path", "an_overview", "bags" }
for _, tab in ipairs(tabs) do
	app.setTab(tab)
	check(stripColors(app.ui.shopModal.titleFs:GetText()) == wantModalTitle, "Modal title stays unified on tab " .. tab)
	check(#app.activeShoppingRows == expectedCount, "Unified activeShoppingRows preserved (" .. expectedCount .. ") when switching to tab " .. tab .. ", got " .. tostring(#app.activeShoppingRows))
	check(btnText(app.ui.openShopBtn) == "Shopping List (3)", "Top-right Shopping List (3) count preserved on tab " .. tab .. ", got " .. tostring(btnText(app.ui.openShopBtn)))
end

-- 6. Sort: Main Items vs Sort: Sub-Items
-- Click Name header (column 1) in Main Items mode -> "Alpha Fire Bundle" comes before "Briarthorn" comes before "Fire Protection Potion"
MerchantMasterDB.shoppingSortScope = "main"
app.sortState.shopping_list = { col = "default", asc = true }
app.ui.shopPanel.table.headerBtns[1]:Click("LeftButton") -- name ascending
renderShop()
local mainOrder = {}
for _, r in ipairs(app.activeShoppingRows) do
	if r.isMainRow then mainOrder[#mainOrder + 1] = r.name end
end
check(#mainOrder == 3 and mainOrder[1] == "Alpha Fire Bundle" and mainOrder[3] == "Fire Protection Potion",
	"Sort Main Items by Name asc orders Main Items while keeping children grouped: " .. table.concat(mainOrder, ", "))

-- Click Line Total header (column 9) -> defaultAsc=false -> descending cost -> Alpha Fire Bundle (170s) > Fire Protection Potion (82s40c) > Briarthorn (10s)
app.ui.shopPanel.table.headerBtns[9]:Click("LeftButton")
renderShop()
mainOrder = {}
for _, r in ipairs(app.activeShoppingRows) do
	if r.isMainRow then mainOrder[#mainOrder + 1] = r.name end
end
check(mainOrder[1] == "Alpha Fire Bundle" and mainOrder[2] == "Fire Protection Potion",
	"Sort Main Items by Line Total desc places costliest Main Item first: " .. table.concat(mainOrder, ", "))

-- Verify children of Fire Protection Potion stay contiguous directly underneath its Main Item
local seenMain = nil
for _, r in ipairs(app.activeShoppingRows) do
	if r.isMainRow then
		seenMain = r.name
	else
		check(r.categoryName == seenMain, "Sub-row " .. tostring(r.name) .. " stayed grouped under Main Item " .. tostring(seenMain))
	end
end

-- Switch to Sort: Sub-Items via UI button
app.ui.shopPanel.sortScopeBtn:Click("LeftButton")
renderShop()
check(MerchantMasterDB.shoppingSortScope == "sub", "Sort toggle switched to sub scope")
check(stripColors(btnText(app.ui.shopPanel.sortScopeBtn)) == "Sort: Sub-Items", "Button text updated to Sort: Sub-Items")
for _, r in ipairs(app.activeShoppingRows) do
	check(not r.isMainRow, "Sort: Sub-Items hides Main headers so all Sub-Items sort globally")
end

-- Click Name header ascending in Sub-Items mode and check Firefin Snapper + Empty Vial follow crafted Fire Oil immediately
app.sortState.shopping_list = { col = "lineCost", asc = false }
app.ui.shopPanel.table.headerBtns[1]:Click("LeftButton") -- Name asc
renderShop()
local foundCraftedFireOil = false
for i, r in ipairs(app.activeShoppingRows) do
	if r.itemID == 6371 and r.categoryName == "Fire Protection Potion" then
		foundCraftedFireOil = true
		local c1, c2 = app.activeShoppingRows[i + 1], app.activeShoppingRows[i + 2]
		check(c1 and c1.isSubRow and c2 and c2.isSubRow, "Sub-Items sort keeps crafted breakdown rows attached directly beneath Fire Oil")
	elseif i > 1 and not r.isSubRow then
		-- Verify global alphabetical order across Level 1 sub-items
		local prevSub
		for j = i - 1, 1, -1 do
			if not app.activeShoppingRows[j].isSubRow then prevSub = app.activeShoppingRows[j]; break end
		end
		if prevSub then
			check((prevSub.name or ""):lower() <= (r.name or ""):lower(), "Sub-Items sorted globally ascending by Name")
		end
	end
end
check(foundCraftedFireOil == true, "Crafted Fire Oil found in Sub-Items sorted list")

-- Switch back to Sort: Main Items
app.ui.shopPanel.sortScopeBtn:Click("LeftButton")
renderShop()
check(MerchantMasterDB.shoppingSortScope == "main", "Sort toggle switched back to main scope")

-- 7. Remove single Main Item & Clear Entire Shopping List
local removeTargetRow
for i, r in ipairs(app.activeShoppingRows) do
	if r.isMainRow and r.name == "Alpha Fire Bundle" then
		removeTargetRow = i
		break
	end
end
check(removeTargetRow ~= nil, "Found Alpha Fire Bundle Main Item row for Remove")
shopPool[removeTargetRow].cells[8]:Click("LeftButton")
renderShop()
local hasAlpha = false
for _, r in ipairs(app.activeShoppingRows) do
	if r.name == "Alpha Fire Bundle" or r.categoryName == "Alpha Fire Bundle" then hasAlpha = true end
end
check(not hasAlpha, "[Remove] removes only clicked Main Item and its children")
check(btnText(app.ui.openShopBtn) == "Shopping List (2)", "Shopping List badge decrements to 2")

-- Click Clear Shopping List button -> wipes ALL 5 sources cleanly across screens
app.ui.shopPanel.clearShopBtn:Click("LeftButton")
renderShop()
check(not app.hasUnifiedShoppingItems(), "Clear Shopping List clears all 5 unified sources")
check(#app.activeShoppingRows == 0, "Shopping List rows emptied to 0")
check(btnText(app.ui.openShopBtn) == "Shopping List (0)", "Top-right Shopping List (0) badge reset")
app.setTab("dashboard")
check(#app.activeShoppingRows == 0, "Empty Shopping List stays empty on Dashboard too")

-- 8. Regression Tests for Astra D-132 Findings
-- 8a. Shared owned & craft batch surplus conservation across two Main Items
local ownedTestName = ns.ItemName(6359)
local prevBagCount = app.char.bags[ownedTestName]
app.char.bags[ownedTestName] = 3
ns.GetOwnedItemCounts = function() return { [ownedTestName] = 3 } end
MerchantMasterDB.craftOrderDeductOwned = true
local hierOwnedRows = ns.BuildHierarchicalShoppingList({
	{ key = "own:g1", mainName = "Fire Oil A", prof = "alchemy", qty = 1, demandList = { { itemID = 6371, qty = 2, role = "Sub-Mat", parentProf = "alchemy" } } },
	{ key = "own:g2", mainName = "Fire Oil B", prof = "alchemy", qty = 1, demandList = { { itemID = 6371, qty = 2, role = "Sub-Mat", parentProf = "alchemy" } } },
}, {
	profMap = { alchemy = 300 },
	repState = ns.GetMerchantReputation(),
	subCraftMode = "smart",
	ownedCounts = { [ownedTestName] = 3 },
	deductOwned = true,
})
local grp1Snap, grp2Snap
for _, r in ipairs(hierOwnedRows) do
	if r.itemID == 6359 and r.isSubRow then
		if r.categoryName == "Fire Oil A" then grp1Snap = r end
		if r.categoryName == "Fire Oil B" then grp2Snap = r end
	end
end
check(grp1Snap and grp1Snap.qty == 0 and grp1Snap.ownedUsed == 2, "Group 1 consumes 2 owned Firefin Snapper (0 left to buy)")
check(grp2Snap and grp2Snap.qty == 1 and grp2Snap.ownedUsed == 1, "Group 2 sees only remaining 1 owned Firefin Snapper (buys 1)")
app.char.bags[ownedTestName] = prevBagCount
ns.GetOwnedItemCounts = savedGetOwned
MerchantMasterDB.craftOrderDeductOwned = false

-- Surplus conservation: crafting 1 Fire Oil in Group 1 makes 2 (1 surplus) reused by Group 2
local hierSurpRows = ns.BuildHierarchicalShoppingList({
	{ key = "surp:g1", mainName = "Surplus A", prof = "alchemy", qty = 1, demandList = { { itemID = 6371, qty = 1, role = "Sub-Mat", parentProf = "alchemy" } } },
	{ key = "surp:g2", mainName = "Surplus B", prof = "alchemy", qty = 1, demandList = { { itemID = 6371, qty = 1, role = "Sub-Mat", parentProf = "alchemy" } } },
}, {
	profMap = { alchemy = 300 },
	repState = ns.GetMerchantReputation(),
	subCraftMode = "smart",
})
local surpGroup2Row
for _, r in ipairs(hierSurpRows) do
	if not r.isMainRow and not r.isSubRow and r.itemID == 6371 and r.categoryName == "Surplus B" then
		surpGroup2Row = r
		break
	end
end
check(surpGroup2Row and surpGroup2Row.qty == 0 and (surpGroup2Row.surplusUsed or 0) == 1, "Group 2 consumes Group 1 leftover Fire Oil batch surplus (qty=0)")

-- 8b. Clearing and removing the last item empty the displayed shopping list.
for _, earlyTab in ipairs({ "bags", "an_items", "recipes", "prof_path" }) do
	app.setTab(earlyTab)
	app.addUnifiedShoppingItem({ key = "clear:test", name = "Clear Target", itemID = 4402, qty = 1, sourceLabel = "Test" })
	check(#app.activeShoppingRows > 0, "Added item populates activeShoppingRows on " .. earlyTab)
	app.clearUnifiedShoppingList()
	check(#app.activeShoppingRows == 0, "clearUnifiedShoppingList empties activeShoppingRows on " .. earlyTab .. ", got " .. tostring(#app.activeShoppingRows))

	app.addUnifiedShoppingItem({ key = "rmlast:test", name = "Remove Last Target", itemID = 4402, qty = 1, sourceLabel = "Test" })
	local rmRef
	for _, r in ipairs(app.activeShoppingRows) do
		if r.isMainRow and r.removeRef then rmRef = r.removeRef; break end
	end
	check(rmRef ~= nil, "Found removeRef for last item on " .. earlyTab)
	app.removeShoppingMainItem(rmRef)
	check(#app.activeShoppingRows == 0, "Removing last item empties activeShoppingRows on " .. earlyTab .. ", got " .. tostring(#app.activeShoppingRows))
end

-- 8c. removeShoppingMainItem deletes exact spellID when two craftOrderQueue recipes share outputItemID
local dupByOut = {}
local dupRec1, dupRec2
for _, rec in ipairs(ns.RECIPES or {}) do
	if rec.outputItemID and rec.outputItemID > 0 and rec.spellID and rec.spellID > 0 and ns.GetRecipeSourceBucket(rec) ~= "gather" then
		local prev = dupByOut[rec.outputItemID]
		if prev and prev.spellID ~= rec.spellID then
			dupRec1, dupRec2 = prev, rec
			break
		elseif not prev then
			dupByOut[rec.outputItemID] = rec
		end
	end
end
check(dupRec1 ~= nil and dupRec2 ~= nil, "Found two distinct spells producing the same outputItemID")
MerchantMasterDB.craftOrderQueue = {
	{ idx = dupRec1.idx, spellID = dupRec1.spellID, outputItemID = dupRec1.outputItemID, prof = dupRec1.prof, qty = 1 },
	{ idx = dupRec2.idx, spellID = dupRec2.spellID, outputItemID = dupRec2.outputItemID, prof = dupRec2.prof, qty = 1 },
}
app.syncUnifiedShoppingList()
local firstSpellRef
for _, r in ipairs(app.activeShoppingRows) do
	if r.isMainRow and r.spellID == dupRec1.spellID then firstSpellRef = r.removeRef; break end
end
check(firstSpellRef ~= nil, "Found removeRef for first shared-output recipe")
app.removeShoppingMainItem(firstSpellRef)
check(#MerchantMasterDB.craftOrderQueue == 1 and MerchantMasterDB.craftOrderQueue[1].spellID == dupRec2.spellID, "removeShoppingMainItem deleted exact spellID recipe, leaving second recipe intact")
app.clearUnifiedShoppingList()

-- 8d. Repeated calculator-bundle addUnifiedShoppingItem accumulates demandList quantities
local repBundle = {
	key = "calc:calc_rep",
	name = "Rep Plan -> Test",
	qty = 1,
	isBundle = true,
	sourceLabel = "Rep Calc",
	demandList = { { itemID = 4402, qty = 3, role = "Calc" } },
}
app.addUnifiedShoppingItem(repBundle)
app.addUnifiedShoppingItem(repBundle)
check(#MerchantMasterDB.shoppingList == 1 and MerchantMasterDB.shoppingList[1].qty == 2, "Bundle qty increments to 2 on repeat add")
check(MerchantMasterDB.shoppingList[1].demandList and MerchantMasterDB.shoppingList[1].demandList[1].qty == 6, "Stored demandList qty accumulates 3 + 3 = 6")
local sumFlameSacQty = 0
for _, r in ipairs(app.activeShoppingRows) do
	if not r.isMainRow and r.itemID == 4402 then sumFlameSacQty = sumFlameSacQty + (r.qty or 0) end
end
check(sumFlameSacQty == 6, "Repeated bundle build shows 6 Small Flame Sac, got " .. tostring(sumFlameSacQty))
app.clearUnifiedShoppingList()

-- 8e. Exception-safe BuildUnifiedShoppingList clears ns._evalCache and respects InvalidatePriceCache
app.addUnifiedShoppingItem({ key = "err:test", name = "Err Probe", itemID = 4402, qty = 1, sourceLabel = "Test" })
local curCostHook = ns.GetReagentUnitCost
ns.GetReagentUnitCost = function(id)
	if id == 4402 then error("injected provider boom") end
	return curCostHook(id)
end
local okErr = pcall(ns.BuildUnifiedShoppingList, MerchantMasterDB, {})
ns.GetReagentUnitCost = curCostHook
check(okErr == false, "Injected error propagates out of BuildUnifiedShoppingList")
check(ns._evalCache == nil, "ns._evalCache cleaned up even when BuildUnifiedShoppingList errors")
PRICE_TABLE[4402][1] = 7777
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local _, errPostCost = ns.BuildUnifiedShoppingList(MerchantMasterDB, {})
check(errPostCost == 7777, "Fresh InvalidatePriceCache price 7777 used after prior error (got " .. tostring(errPostCost) .. ")")
PRICE_TABLE[4402][1] = 5000
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
app.clearUnifiedShoppingList()

-- Nested BeginEval exception safety in BuildCraftingOrderPlan -> BuildRecipeRow & BuildUnifiedShoppingList -> BuildWritRows
local savedEvalUnlock = ns.EvaluateUnlock
ns.EvaluateUnlock = function() error("injected unlock boom (craft)") end
local okCraftErr = pcall(ns.BuildCraftingOrderPlan, { spellID = 7257, outputItemID = 6049, prof = "alchemy" }, 1, MerchantMasterDB.craftOrderQueue, {})
ns.EvaluateUnlock = savedEvalUnlock
check(okCraftErr == false, "Injected EvaluateUnlock error propagates out of BuildCraftingOrderPlan")
check(ns._evalCache == nil, "ns._evalCache cleaned up when nested BuildRecipeRow errors")

local someWrit = ns.WRITS and ns.WRITS[1]
check(someWrit and someWrit.itemID, "Have writ entry for nested BuildWritRows error probe")
MerchantMasterDB.writTurnInQueue[someWrit.itemID] = 1
ns.EvaluateUnlock = function() error("injected unlock boom (writ)") end
local okWritErr = pcall(ns.BuildUnifiedShoppingList, MerchantMasterDB, {})
ns.EvaluateUnlock = savedEvalUnlock
wipe(MerchantMasterDB.writTurnInQueue)
check(okWritErr == false, "Injected EvaluateUnlock error propagates out of BuildUnifiedShoppingList -> BuildWritRows")
check(ns._evalCache == nil, "ns._evalCache cleaned up when nested BuildWritRows errors")
ns.BeginEval()
ns.EndEval()
check(ns._evalCache == nil, "Balanced BeginEval/EndEval after nested errors leaves ns._evalCache == nil")

-- 8f. refreshUnifiedShoppingDisplay sorts fallback Super List preview without wiping it
app.setTab("recipes")
app.setActiveShoppingList({
	{ itemID = 4402, name = "Small Flame Sac", qty = 2, lineCost = 10000, role = "Reagent" },
	{ itemID = 2450, name = "Briarthorn", qty = 1, lineCost = 1000, role = "Reagent" },
}, "Super List Preview", "Shopping List", "recipes")
app.sortState.shopping_list = { col = "name", asc = true }
app.refreshUnifiedShoppingDisplay()
check(#app.activeShoppingRows == 2, "Fallback Super List preview kept non-empty after refreshUnifiedShoppingDisplay, got " .. tostring(#app.activeShoppingRows))
check(app.activeShoppingRows[1].itemID == 2450 and app.activeShoppingRows[2].itemID == 4402, "Fallback preview rows sorted Briarthorn before Small Flame Sac")

-- A visible detached Shopping List refreshes while Recipes handles its own item repair.
do
	local itemID = 4402
	app.addUnifiedShoppingItem({key="item-info-refresh",name="Item info test",reagents={{itemID,1}},qty=1},true)
	app.toggleShoppingWindow(true)
	local before = app.ui.shopPanel.rawRows
	local getItemInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(id,...)
		if id == itemID then return "Loaded Flame Sac" end
		return getItemInfo(id,...)
	end
	ns.pendingItemLoads[itemID] = true
	hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame,"GET_ITEM_INFO_RECEIVED",itemID,true)
	local rows = app.ui.shopPanel.rawRows
	local loadedName
	for _, row in ipairs(rows) do
		if row.itemID == itemID and row.name == "Loaded Flame Sac" then loadedName = true end
	end
	check(app.activeTab == "recipes" and app.ui.shopModal:IsShown() and rows ~= before and loadedName,
		"item info received on Recipes refreshes the visible Shopping List")
	C_Item.GetItemInfo = getItemInfo
end

-- A single-recipe preview refreshes when item data arrives with the window open or closed.
do
	app.clearUnifiedShoppingList()
	local box = app.ui.recipesTable.scrollBox
	local frame = CreateFrame("Button",nil,box)
	local getItemInfo = C_Item.GetItemInfo
	for i, visibility in ipairs({"open", "closed"}) do
		local itemID = 99004400 + i
		box._view._initFn(frame,{
			key="uncached-reagent-preview", name="Test recipe", prof="alchemy", numMade=3,
			craftBreakdown={{itemID=itemID,qty=2}},
		})
		frame:Click("RightButton")
		app.toggleShoppingWindow(visibility=="open")
		local before = app.ui.shopPanel.rawRows
		check(not app.hasUnifiedShoppingItems() and #before==1 and before[1].itemID==itemID
			and before[1].name=="Item #"..itemID and ns.pendingItemLoads[itemID],
			"single recipe with an uncached reagent has an unresolved preview")
		local loadedName = "Loaded " .. visibility .. " reagent"
		C_Item.GetItemInfo = function(id,...)
			if id == itemID then return loadedName end
			return getItemInfo(id,...)
		end
		hostEnv.eventFrame._scripts.OnEvent(hostEnv.eventFrame,"GET_ITEM_INFO_RECEIVED",itemID,true)
		if visibility=="closed" then app.toggleShoppingWindow(true) end
		local rows = app.ui.shopPanel.rawRows
		check(app.activeTab=="recipes" and app.ui.shopModal:IsShown() and rows~=before
			and #rows==1 and rows[1].name==loadedName and rows[1].qty==before[1].qty,
			"item info rebuilds the " .. visibility .. " single-recipe preview and preserves its quantity")
	end
	C_Item.GetItemInfo = getItemInfo
end

-- Exercise the three detached Shopping List click targets against the real AH handler.
do
	local outputID, unresolvedID = 12360, 990071
	local getItemName, requestData = C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID
	local sendBrowse, getBrowse, hasFull, ahFrame = C_AuctionHouse.SendBrowseQuery,
		C_AuctionHouse.GetBrowseResults, C_AuctionHouse.HasFullBrowseResults, AuctionHouseFrame
	local queries, requested = {}, nil
	C_Item.GetItemNameByID = function(id) if id == outputID then return "Arcanite Bar" end end
	C_Item.RequestLoadItemDataByID = function(id) requested = id end
	C_AuctionHouse.SendBrowseQuery = function(query) queries[#queries + 1] = query.searchString end
	C_AuctionHouse.GetBrowseResults = function()
		if queries[#queries] ~= "Arcanite Bar" then return {} end
		return {{itemKey={itemID=outputID}, totalQuantity=11, minPrice=700}}
	end
	C_AuctionHouse.HasFullBrowseResults = function() return true end
	AuctionHouseFrame = {IsShown=function() return true end, SearchBar={
		SetSearchText=function(self, value) self.text=value end,
		StartSearch=function(self) C_AuctionHouse.SendBrowseQuery({searchString=self.text}) end,
	}}
	app.searchAH = savedSearchAH
	local prices = ns.MarketScan.ActiveEconomyPrices()
	local oldOutput, oldReagent = prices[outputID], prices[unresolvedID]
	prices[outputID] = {qty=11, price=700}
	prices[unresolvedID] = {qty=11, price=900}
	app.toggleShoppingWindow(true)
	MerchantMasterDB.craftOrderQueue = {{spellID=17187, outputItemID=outputID, prof="alchemy", qty=1}}
	local getUIPriceBank = app.getUIPriceBank
	app.getUIPriceBank = nil
	app.syncUnifiedShoppingList()
	app.getUIPriceBank = getUIPriceBank
	renderShop()
	local row = shopPool[1]
	check(row.data.isMainRow and row.data.name == "Transmute: Arcanite", "the queued row displays the transmute spell name")
	for _, target in ipairs({row, row.cells[1]}) do
		target:Click()
		ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(queries[#queries] == "Arcanite Bar" and prices[outputID].qty == 11 and not prices[outputID].absent,
			"clicking a transmute output searches for the actual item and preserves its stock")
	end
	MerchantMasterDB.craftOrderQueue = {}
	app.setActiveShoppingList({{name="Item #" .. unresolvedID, itemID=unresolvedID, qty=2}}, "Test")
	renderShop()
	for _, target in ipairs({row.cells[8], row.cells[1], row}) do
		local count = #queries
		target:Click()
		ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(#queries == count and prices[unresolvedID].qty == 11 and not prices[unresolvedID].absent,
			"an unresolved Shopping List reagent cannot dispatch a search or publish absence")
	end
	check(requested == unresolvedID, "the unresolved reagent requests item data")
	prices[outputID], prices[unresolvedID] = oldOutput, oldReagent
	C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID = getItemName, requestData
	C_AuctionHouse.SendBrowseQuery, C_AuctionHouse.GetBrowseResults = sendBrowse, getBrowse
	C_AuctionHouse.HasFullBrowseResults, AuctionHouseFrame = hasFull, ahFrame
end

-- 12. Shopping List Use Owned toolbar button + clean Own / Buy / Craft action chips
do
	check(app.ui.shopPanel.useOwnedBtn ~= nil, "shopPanel exposes Use Owned toggle button")
	app.sortState.shopping_list = { col = "default", asc = true }
	MerchantMasterDB.shoppingSortScope = "main"
	MerchantMasterDB.craftOrderDeductOwned = false
	app.setActiveShoppingList({
		{ itemID = 3575, name = "Iron Bar", qty = 0, rawQty = 31, owned = 135, ownedUsed = 31, surplusUsed = 0, lineCost = 0, canToggleCraft = false, makeMyself = false, isVendor = false, action = "Owned (31x)" },
		{ itemID = 10558, name = "Gold Power Core", qty = 30, rawQty = 30, owned = 0, ownedUsed = 0, surplusUsed = 0, lineCost = 9880, canToggleCraft = true, makeMyself = true, isVendor = false, action = "Craft (Engineering)" },
		{ itemID = 3577, name = "Gold Bar", qty = 10, rawQty = 10, owned = 0, ownedUsed = 0, surplusUsed = 0, lineCost = 9880, canToggleCraft = true, makeMyself = false, isVendor = false, action = "Buy AH" },
	}, "Owned Chip Check")
	renderShop()
	local byID = {}
	for _, rf in ipairs(shopPool) do
		if rf:IsShown() and rf.data and rf.data.itemID then byID[rf.data.itemID] = rf end
	end
	check(btnText(app.ui.shopPanel.useOwnedBtn) == "Use Owned: Off", "Use Owned button shows Off when craftOrderDeductOwned=false")
	check(byID[3575] and stripColors(btnText(byID[3575].cells[8])) == "OWNED", "Fully owned material displays OWNED pill")
	check(byID[10558] and stripColors(btnText(byID[10558].cells[8])):find("CRAFT", 1, true) ~= nil, "Craftable item in craft mode displays CRAFT pill")
	check(byID[3577] and stripColors(btnText(byID[3577].cells[8])) == "BUY AH", "Craftable item in buy mode displays BUY AH pill")
	app.ui.shopPanel.useOwnedBtn:Click("LeftButton")
	check(MerchantMasterDB.craftOrderDeductOwned == true, "Clicking Use Owned button enables craftOrderDeductOwned")
	check(btnText(app.ui.shopPanel.useOwnedBtn) == "Use Owned: On", "Use Owned button updates to On")
	MerchantMasterDB.craftOrderDeductOwned = false
end

-- 13. Option A Sales Cart: meta.buckets accuracy, - / + steppers across all 6 queues, and Empty Cart state
do
	app.clearUnifiedShoppingList()
	renderShop()
	check(app.ui.shopPanel.emptyState and app.ui.shopPanel.emptyState:IsShown() == true, "Empty Cart state overlay shows when cart has 0 rows")
	check(app.ui.shopPanel.summaryRail ~= nil, "Order Summary & Checkout Rail is exposed")

	-- 13a. meta.buckets split accuracy (Craft vs Buy AH vs Vendor vs Owned, zero double-counting)
	MerchantMasterDB.craftOrderQueue = { { spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 2 } }
	local bRows, bCost, _, bMeta = app.syncUnifiedShoppingList()
	renderShop()
	check(app.ui.shopPanel.emptyState:IsShown() == false, "Empty Cart state hides once items are queued")
	local bk = bMeta and bMeta.buckets
	check(bk ~= nil, "BuildHierarchicalShoppingList returns meta.buckets")
	check(bk.craftCount == 1 and bk.craftUnits == 2, "Buckets count 1 crafted sub-item (Fire Oil x2), got " .. tostring(bk.craftCount) .. "/" .. tostring(bk.craftUnits))
	check(bk.ahCount == 2 and bk.vendorCount == 2, "Buckets classify 2 AH leaves + 2 Vendor leaves, got ah=" .. tostring(bk.ahCount) .. " vendor=" .. tostring(bk.vendorCount))
	check((bk.ahCost + bk.vendorCost) == bCost, "Buckets avoid double-counting: ahCost+vendorCost == grandTotalCost (" .. tostring(bk.ahCost + bk.vendorCost) .. " == " .. tostring(bCost) .. ")")
	check(bk.craftSavings > 0, "Craft savings computed positively when Fire Oil is cheaper to craft")

	-- 13b. Inline UI [- / +] steppers on Main Order row
	local mainRow = shopPool[1]
	check(mainRow and mainRow.data and mainRow.data.isMainRow and mainRow.data.qty == 2, "Row 1 starts at qty=2")
	check(mainRow.qtyPlusBtn and mainRow.qtyMinusBtn, "Main row exposes inline - / + stepper buttons")
	mainRow.qtyPlusBtn:Click("LeftButton")
	renderShop()
	check(MerchantMasterDB.craftOrderQueue[1].qty == 3 and app.activeShoppingRows[1].qty == 3, "Clicking [+] increments craft_order qty 2 -> 3 live")
	shopPool[1].qtyMinusBtn:Click("LeftButton")
	renderShop()
	check(MerchantMasterDB.craftOrderQueue[1].qty == 2 and app.activeShoppingRows[1].qty == 2, "Clicking [-] decrements craft_order qty 3 -> 2 live")
	app.adjustShoppingMainQty(app.activeShoppingRows[1].removeRef, -2)
	check(#MerchantMasterDB.craftOrderQueue == 0 and #app.activeShoppingRows == 0, "Decrementing craft_order qty to 0 removes it cleanly")

	-- 13c. adjustShoppingMainQty across remaining 5 queue backends (writ_craft, spread, writ_turnin, forged_turnin, shopping)
	MerchantMasterDB.writCraftQueue = { [2450] = 2 }
	check(app.adjustShoppingMainQty({ sourceKind = "writ_craft", itemID = 2450 }, 3) == true and MerchantMasterDB.writCraftQueue[2450] == 5, "writ_craft +3 -> 5")
	check(app.adjustShoppingMainQty({ sourceKind = "writ_craft", itemID = 2450 }, -5) == true and MerchantMasterDB.writCraftQueue[2450] == nil, "writ_craft -5 -> nil")

	MerchantMasterDB.spreadQueue = { [4402] = 1 }
	check(app.adjustShoppingMainQty({ sourceKind = "spread", queueKey = 4402, itemID = 4402 }, 2) == true and MerchantMasterDB.spreadQueue[4402] == 3, "spread +2 -> 3")
	check(app.adjustShoppingMainQty({ sourceKind = "spread", queueKey = 4402, itemID = 4402 }, -3) == true and MerchantMasterDB.spreadQueue[4402] == nil, "spread -3 -> nil")

	local testWrit = ns.WRITS and ns.WRITS[1]
	if testWrit and testWrit.itemID then
		MerchantMasterDB.writTurnInQueue = { [testWrit.itemID] = 1 }
		check(app.adjustShoppingMainQty({ sourceKind = "writ_turnin", writID = testWrit.itemID }, 2) == true and MerchantMasterDB.writTurnInQueue[testWrit.itemID] == 3, "writ_turnin +2 -> 3")
		check(app.adjustShoppingMainQty({ sourceKind = "writ_turnin", writID = testWrit.itemID }, -3) == true and MerchantMasterDB.writTurnInQueue[testWrit.itemID] == nil, "writ_turnin -3 -> nil")
	end

	local testCrate = ns.CRATES and ns.CRATES[1]
	if testCrate and testCrate.crateID then
		MerchantMasterDB.forgedTurnInQueue = { { crateID = testCrate.crateID, rowKey = "forged:" .. testCrate.crateID, count = 1 } }
		check(app.adjustShoppingMainQty({ sourceKind = "forged_turnin", crateID = testCrate.crateID }, 2) == true and app.getForgedQueuedCount(testCrate.crateID) == 3, "forged_turnin +2 -> 3")
		check(app.adjustShoppingMainQty({ sourceKind = "forged_turnin", crateID = testCrate.crateID }, -3) == true and app.getForgedQueuedCount(testCrate.crateID) == 0, "forged_turnin -3 -> 0")
	end

	app.addUnifiedShoppingItem({ key = "step:bundle", name = "Step Bundle", qty = 2, isBundle = true, demandList = { { itemID = 4402, qty = 4, role = "Test" } } })
	check(app.adjustShoppingMainQty({ sourceKind = "shopping", index = 1, key = "step:bundle" }, 2) == true
		and MerchantMasterDB.shoppingList[1].qty == 4
		and MerchantMasterDB.shoppingList[1].demandList[1].qty == 8, "shopping +2 scales qty 2->4 and demandList 4->8")
	check(app.adjustShoppingMainQty({ sourceKind = "shopping", index = 1, key = "step:bundle" }, -4) == true
		and #MerchantMasterDB.shoppingList == 0, "shopping -4 removes entry cleanly")
	app.clearUnifiedShoppingList()
end

-- 14. V3 Live-Bug Regression Tests: cardMode Window.LayoutTable protection & Responsive Right Rail
do
	-- 14a. Initial-open + Window.LayoutTable MUST NOT clobber cardMode cell anchors or widths
	MerchantMasterDB.craftOrderQueue = { { spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 1 } }
	app.syncUnifiedShoppingList()
	app.ui.shopModal:Show()
	renderShop()

	-- Explicitly exercise Window.LayoutTable and layoutColumns on the cardMode table
	check(app.ui.shopPanel.table.cardMode == true, "shopPanel table sets cardMode=true")
	ns.Window.LayoutTable(app.ui.shopPanel.table, 740, 1)
	app.ui.shopPanel.layoutColumns()

	local mainRow = shopPool[1]
	check(mainRow and mainRow.data and mainRow.data.isMainRow == true, "V3 regression: row 1 is Main Order card")
	check(mainRow.cells[8]:GetWidth() == 24, "V3/V6 regression: crimson remove button stays 24px wide after Window.LayoutTable (not stretched to colWidth)")
	local qPt, qRel, qRelPt = mainRow.cells[3]:GetPoint(1)
	check(qPt == "RIGHT" and qRel == mainRow.card and qRelPt == "RIGHT",
		"V3/V6 regression: stepper qWrap stays right-anchored to card centerline after Window.LayoutTable (got " .. tostring(qPt) .. "/" .. tostring(qRelPt) .. ")")
	check(stripColors(mainRow.cells[1].fs:GetText()) ~= "", "V3 regression: Main Order title is non-empty after initial open + LayoutTable")

	local leafRow = nil
	for _, rf in ipairs(shopPool) do
		if rf:IsShown() and rf.data and not rf.data.isMainRow and not rf.data.makeMyself and not rf.data.canToggleCraft then
			leafRow = rf
			break
		end
	end
	check(leafRow ~= nil, "V3 regression: leaf material row is visible on initial open")
	if leafRow then
		check(stripColors(leafRow.cells[1].fs:GetText()) ~= "", "V3 regression: leaf item name is visible and non-empty without toggling Use Owned")
		check(stripColors(leafRow.cells[9]:GetText()) ~= "", "V3 regression: leaf cost text is non-empty after Window.LayoutTable")
	end

	-- 14b. Responsive Right Rail zero overlap / zero bottom overflow at 660px, 720px, and stale 470px SavedVars upgrade
	app.ui.shopModal:SetSize(1160, 660)
	app.ui.shopPanel.summaryRail:SetHeight(548)
	app.ui.shopPanel.layoutSummaryRail()
	local m660 = app.ui.shopPanel._railMetrics
	check(m660 ~= nil and m660.ctaBottom < m660.emptyTop,
		"V3/V4 regression (660px): Send to AH CTA bottom (" .. tostring(m660 and m660.ctaBottom) .. ") stays strictly above Empty Cart top (" .. tostring(m660 and m660.emptyTop) .. ")")
	check(m660 ~= nil and m660.emptyBottom <= m660.availH,
		"V3/V4 regression (660px): Empty Cart bottom (" .. tostring(m660 and m660.emptyBottom) .. ") stays inside summaryRail height (" .. tostring(m660 and m660.availH) .. ")")

	app.ui.shopModal:SetSize(1160, 720)
	app.ui.shopPanel.summaryRail:SetHeight(608)
	app.ui.shopPanel.layoutSummaryRail()
	local m720 = app.ui.shopPanel._railMetrics
	check(m720 ~= nil and m720.ctaBottom < m720.emptyTop and m720.emptyBottom <= m720.availH,
		"V3/V4 regression (720px): Send to AH CTA and Empty Cart have zero overlap and zero overflow")

	-- Stale pre-redesign saved height (470px) automatically upgrades to 720px on Show
	MerchantMasterDB.shoppingWindowSize = { w = 1096, h = 470 }
	app.ui.shopModal:Hide()
	app.ui.shopModal:Show()
	check(app.ui.shopModal:GetHeight() == 720,
		"V3/V4 regression: stale saved shoppingWindowSize.h=470 upgrades to 720 on OnShow (got " .. tostring(app.ui.shopModal:GetHeight()) .. ")")

	-- Cleanup
	MerchantMasterDB.shoppingWindowSize = nil
	app.ui.shopModal:SetSize(1160, 720)
	app.ui.shopPanel.summaryRail:SetHeight(608)
	app.ui.shopPanel.layoutSummaryRail()
	app.clearUnifiedShoppingList()
end

-- 15. V4 Live Owner Upgrades: No Crest on Shopping Window, Taller Zero-Crop Order Summary, Clickable Inline Quantity Input
do
	-- 15a. Crest hidden on shopModal in Goblin skin (while keeping Goblin chrome intact)
	local prevSkin = ns.Theme.GetSkin and ns.Theme.GetSkin() or "standard"
	if ns.Theme.SetSkin then ns.Theme.SetSkin("goblin") end
	app.ui.shopModal:Show()
	if app.ui.shopModal.warcraftChrome and app.ui.shopModal.warcraftChrome.Layout then
		app.ui.shopModal.warcraftChrome:Layout("goblin")
	end
	check(app.ui.shopModal._mmHideCrest == true, "V4: shopModal sets _mmHideCrest = true")
	check(app.ui.shopModal.warcraftChrome ~= nil and app.ui.shopModal.warcraftChrome.crest ~= nil
		and app.ui.shopModal.warcraftChrome.crest:IsShown() == false,
		"V4: shopModal hides Goblin top crest so top rail sits flush")
	if ns.Theme.SetSkin then ns.Theme.SetSkin(prevSkin) end

	-- 15b. Taller default (1160x720), minH=660, stale h=580 upgrade to 720, and craftCard valFs vs notSentPill gap >= 8px
	check(app.ui.shopModal._mmMinH == 660, "V4: shopModal minH == 660 (got " .. tostring(app.ui.shopModal._mmMinH) .. ")")
	MerchantMasterDB.shoppingWindowSize = { w = 1140, h = 580 }
	app.ui.shopModal:Hide()
	app.ui.shopModal:Show()
	check(app.ui.shopModal:GetHeight() == 720 and MerchantMasterDB.shoppingWindowSize.h == 720,
		"V4: stale saved shoppingWindowSize.h=580 upgrades to 720 on OnShow (got " .. tostring(app.ui.shopModal:GetHeight()) .. ")")

	-- Check craftCard vertical clearance at BOTH minH=660 and default 720
	for _, case in ipairs({ { winH = 660, railH = 548 }, { winH = 720, railH = 608 } }) do
		app.ui.shopModal:SetSize(1160, case.winH)
		app.ui.shopPanel.summaryRail:SetHeight(case.railH)
		app.ui.shopPanel.layoutSummaryRail()
		local m = app.ui.shopPanel._railMetrics
		local cH = app.ui.shopPanel.craftCard:GetHeight()
		local pillH = app.ui.shopPanel.craftCard.tagPillWrap:GetHeight()
		local _, _, _, _, valY = app.ui.shopPanel.craftCard.valFs:GetPoint(1)
		local _, _, _, _, pillY = app.ui.shopPanel.craftCard.tagPillWrap:GetPoint(1)
		local valBottom = math.abs(valY or -7) + 12
		local pillTop = cH - math.abs(pillY or 6) - pillH
		local gap = pillTop - valBottom
		check(cH >= 56 and gap >= 8 and m.craftGap >= 8,
			string.format("V4 (%dpx): craftCard height=%dpx and Saves->NotSent gap=%dpx (>= 8px)", case.winH, cH, gap))
	end

	-- 15c. app.setShoppingMainQty across exact transitions (9 -> 25, 25 -> 1, 1 -> 0 removes) + other queues
	MerchantMasterDB.craftOrderQueue = { { spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 9 } }
	app.syncUnifiedShoppingList()
	renderShop()
	local ref = app.activeShoppingRows[1] and app.activeShoppingRows[1].removeRef
	check(ref ~= nil, "V4: Main Order row exposes removeRef for setShoppingMainQty")
	check(app.setShoppingMainQty(ref, 25) == true and MerchantMasterDB.craftOrderQueue[1].qty == 25,
		"V4: setShoppingMainQty sets craft_order qty 9 -> 25")
	check(app.setShoppingMainQty(ref, 1) == true and MerchantMasterDB.craftOrderQueue[1].qty == 1,
		"V4: setShoppingMainQty sets craft_order qty 25 -> 1")
	check(app.setShoppingMainQty(ref, 0) == true and #MerchantMasterDB.craftOrderQueue == 0,
		"V4: setShoppingMainQty(ref, 0) removes craft_order entry cleanly")

	MerchantMasterDB.writCraftQueue = { [2450] = 3 }
	check(app.setShoppingMainQty({ sourceKind = "writ_craft", itemID = 2450 }, 12) == true and MerchantMasterDB.writCraftQueue[2450] == 12,
		"V4: setShoppingMainQty sets writ_craft qty -> 12")
	check(app.setShoppingMainQty({ sourceKind = "writ_craft", itemID = 2450 }, 0) == true and MerchantMasterDB.writCraftQueue[2450] == nil,
		"V4: setShoppingMainQty(0) removes writ_craft")

	app.addUnifiedShoppingItem({ key = "set:bundle", name = "Set Bundle", qty = 2, isBundle = true, demandList = { { itemID = 4402, qty = 6, role = "Test" } } })
	check(app.setShoppingMainQty({ sourceKind = "shopping", index = 1, key = "set:bundle" }, 5) == true
		and MerchantMasterDB.shoppingList[1].qty == 5
		and MerchantMasterDB.shoppingList[1].demandList[1].qty == 15,
		"V4: setShoppingMainQty scales shopping bundle qty 2->5 and demandList 6->15")
	app.clearUnifiedShoppingList()

	-- 15d. Inline clickable qtyBtn + qtyEdit (Enter applies 15; Escape cancels without hiding shopModal)
	MerchantMasterDB.craftOrderQueue = { { spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 9 } }
	app.syncUnifiedShoppingList()
	app.ui.shopModal:Show()
	renderShop()
	local row1 = shopPool[1]
	local qWrap = row1 and row1.cells[3]
	check(qWrap and qWrap.qtyBtn and qWrap.qtyEdit, "V4: Main Order stepper exposes clickable qtyBtn and inline qtyEdit")
	check(qWrap.qtyBtn:IsShown() == true and qWrap.qtyEdit:IsShown() == false,
		"V4: qtyBtn starts visible and qtyEdit starts hidden")

	-- Click number -> edit to "15" -> Enter commits
	qWrap.qtyBtn:Click("LeftButton")
	check(qWrap.qtyEdit:IsShown() == true and qWrap.qtyEdit:GetText() == "9",
		"V4: clicking qtyBtn shows qtyEdit pre-filled with current qty '9'")
	qWrap.qtyEdit:SetText("15")
	local onEnter = qWrap.qtyEdit:GetScript("OnEnterPressed")
	check(type(onEnter) == "function", "V4: qtyEdit registers OnEnterPressed")
	onEnter(qWrap.qtyEdit)
	renderShop()
	check(MerchantMasterDB.craftOrderQueue[1].qty == 15 and app.activeShoppingRows[1].qty == 15,
		"V4: Enter in qtyEdit commits qty=15 to queued recipe")
	check(qWrap.qtyEdit:IsShown() == false and qWrap.fs:IsShown() == true,
		"V4: Enter hides qtyEdit and restores qty text")

	-- Click number -> type "99" -> Escape cancels without changing qty or closing shopModal
	qWrap.qtyBtn:Click("LeftButton")
	qWrap.qtyEdit:SetText("99")
	local onEscape = qWrap.qtyEdit:GetScript("OnEscapePressed")
	check(type(onEscape) == "function", "V4: qtyEdit registers OnEscapePressed")
	onEscape(qWrap.qtyEdit)
	check(MerchantMasterDB.craftOrderQueue[1].qty == 15,
		"V4: Escape in qtyEdit preserves previous qty=15")
	check(app.ui.shopModal:IsShown() == true and qWrap.qtyEdit:IsShown() == false,
		"V4: Escape closes qtyEdit WITHOUT hiding shopModal")

	-- Cleanup
	MerchantMasterDB.shoppingWindowSize = nil
	app.ui.shopModal:SetSize(1160, 720)
	app.ui.shopPanel.summaryRail:SetHeight(608)
	app.ui.shopPanel.layoutSummaryRail()
	app.clearUnifiedShoppingList()
end

-- 16. V5 Root-Cause Regression: layout-local.txt 1096x470 Recovery, 768px UIParent Fit, Guaranteed Zero-Overflow Rail, Manual Drag Resize Grip & /mm shopsize
do
	local modal = app.ui.shopModal
	local sp = app.ui.shopPanel
	local grip = modal.resizeGrip

	-- 16a. Exact live-WoW root cause: layout-local.txt shrinks named MerchantMasterShoppingWindow to 1096x470 while DB size is nil
	MerchantMasterDB.shoppingWindowSize = nil
	modal:SetSize(1096, 470)
	modal:Hide()
	modal:Show()
	check(modal:GetWidth() == 1160 and modal:GetHeight() == 720,
		string.format("V5 root-cause: OnShow restores 1160x720 even when shoppingWindowSize is nil and layout-local.txt shrank frame to 1096x470 (got %dx%d)",
			modal:GetWidth(), modal:GetHeight()))

	-- 16b. Zero overflow & zero overlap in layoutSummaryRail() across ALL heights (470, 540, 600, 660, 720)
	for _, case in ipairs({
		{ winH = 470, railH = 358, minCraftGap = 1 },
		{ winH = 540, railH = 428, minCraftGap = 8 },
		{ winH = 600, railH = 488, minCraftGap = 8 },
		{ winH = 660, railH = 548, minCraftGap = 8 },
		{ winH = 720, railH = 608, minCraftGap = 8 },
	}) do
		modal:SetSize(1160, case.winH)
		sp.summaryRail:SetHeight(case.railH)
		sp.layoutSummaryRail()
		local m = sp._railMetrics
		local cPt = sp.clearShopBtn:GetPoint(1)
		local dPt = sp.dangerNoteFs:GetPoint(1)
		check(cPt == "BOTTOMLEFT" and dPt == "BOTTOMLEFT",
			string.format("V5 (%dpx): clearShopBtn & dangerNoteFs stay BOTTOM-anchored inside summaryRail (got %s / %s)",
				case.winH, tostring(cPt), tostring(dPt)))
		check(m.ctaBottom < m.emptyTop,
			string.format("V5 (%dpx): Send to AH bottom (%d) stays strictly above Empty Cart top (%d)",
				case.winH, m.ctaBottom, m.emptyTop))
		check(m.emptyBottom <= m.availH and m.clearBottomOff >= 16,
			string.format("V5 (%dpx): Empty Cart bottom (%d) stays strictly inside summaryRail (%d), bottomOff=%d",
				case.winH, m.emptyBottom, m.availH, m.clearBottomOff or -1))
		check(m.craftGap >= case.minCraftGap,
			string.format("V5 (%dpx): craftCard Saves->NotSent gap=%d (>= %d)",
				case.winH, m.craftGap, case.minCraftGap))
	end

	-- 16c. WoW Classic 768px & high-UIScale 640px virtual UIParent viewport-fit scaling
	local origUIGetW, origUIGetH = UIParent.GetWidth, UIParent.GetHeight
	for _, vp in ipairs({ { w = 1365, h = 768 }, { w = 1138, h = 640 } }) do
		UIParent.GetWidth = function() return vp.w end
		UIParent.GetHeight = function() return vp.h end
		MerchantMasterDB.shoppingWindowSize = nil
		modal:Hide()
		modal:Show()
		local sc = modal:GetScale() or 1
		local effW = modal:GetWidth() * sc
		local effH = modal:GetHeight() * sc
		check(effW <= vp.w - 23 and effH <= vp.h - 23,
			string.format("V5 (%dx%d UIParent): shopModal scales cleanly to fit (scale=%.3f, eff=%.1fx%.1f)",
				vp.w, vp.h, sc, effW, effH))
	end
	UIParent.GetWidth, UIParent.GetHeight = origUIGetW, origUIGetH
	modal:Hide()
	modal:Show()

	-- 16d. Visible bottom-right manual drag resize grip (level > warcraftChrome, drag resize + pill + persist + right-click reset)
	check(grip ~= nil and grip:GetWidth() >= 24 and grip:GetHeight() >= 24,
		"V5: shopModal.resizeGrip exists and is >= 24x24")
	local seenGripLevel = grip._mmFrameLevel or 0
	local origSetLvl = grip.SetFrameLevel
	grip.SetFrameLevel = function(self, lvl) seenGripLevel = lvl; if origSetLvl then origSetLvl(self, lvl) end end
	local prevSkin = ns.Theme.GetSkin and ns.Theme.GetSkin() or "standard"
	if ns.Theme.SetSkin then ns.Theme.SetSkin("goblin") end
	grip.SetFrameLevel = origSetLvl
	if ns.Theme.SetSkin then ns.Theme.SetSkin(prevSkin) end
	check(seenGripLevel >= modal:GetFrameLevel() + 35,
		"V5: shopModal.resizeGrip sets frameLevel >= modal+35 (strictly above warcraftChrome +22, got " .. tostring(seenGripLevel) .. ")")

	local origGetCursor = _G.GetCursorPosition
	local curX, curY = 500, 500
	_G.GetCursorPosition = function() return curX, curY end
	modal:SetSize(1160, 720)
	local onDown = grip:GetScript("OnMouseDown")
	local onUp = grip:GetScript("OnMouseUp")
	check(type(onDown) == "function" and type(onUp) == "function", "V5: resizeGrip registers OnMouseDown/OnMouseUp")

	onDown(grip, "LeftButton")
	check(grip._resizing == true and modal.resizeSizePill:IsShown() == true,
		"V5: left-drag starts manual resize and shows live dimensions pill")
	curX, curY = 620, 420 -- +120 wider, +80 taller (Y decreases downward in WoW screen coords)
	local onUpdate = grip:GetScript("OnUpdate")
	check(type(onUpdate) == "function", "V5: left-drag attaches OnUpdate handler")
	onUpdate(grip, 0.016)
	check(modal:GetWidth() == 1280 and modal:GetHeight() == 800,
		string.format("V5: drag resize updates shopModal to 1280x800 (got %dx%d)", modal:GetWidth(), modal:GetHeight()))
	check(modal.resizeSizePill.fs:GetText() == "1280 x 800",
		"V5: live dimensions pill displays '1280 x 800' during drag")
	check(MerchantMasterDB.shoppingWindowSize and MerchantMasterDB.shoppingWindowSize.w == 1280 and MerchantMasterDB.shoppingWindowSize.h == 800,
		"V5: drag resize persists 1280x800 into MerchantMasterDB.shoppingWindowSize")

	onUp(grip, "LeftButton")
	check(grip._resizing == false and modal.resizeSizePill:IsShown() == false and grip:GetScript("OnUpdate") == nil,
		"V5: mouse-up stops resize, hides pill, and clears OnUpdate")
	check(MerchantMasterDB.shoppingWindowSize.scale ~= nil and MerchantMasterDB.shoppingWindowSize.uiH ~= nil,
		"V5: persisted shoppingWindowSize includes scale and uiH telemetry")

	-- Right-click resets to default 1160x720
	onDown(grip, "RightButton")
	check(modal:GetWidth() == 1160 and modal:GetHeight() == 720,
		string.format("V5: right-click on resizeGrip resets shopModal to 1160x720 (got %dx%d)", modal:GetWidth(), modal:GetHeight()))
	check(MerchantMasterDB.shoppingWindowSize.w == 1160 and MerchantMasterDB.shoppingWindowSize.h == 720,
		"V5: right-click reset updates MerchantMasterDB.shoppingWindowSize to 1160x720")
	_G.GetCursorPosition = origGetCursor

	-- 16e. app.getShoppingWindowDiagnostics() (retired /mm shopsize prints usage hint)
	sp.summaryRail:SetHeight(608)
	sp.layoutSummaryRail()
	local diag = app.getShoppingWindowDiagnostics()
	check(diag and diag.winW == 1160 and diag.winH == 720 and diag.emptyInsideRail == true and diag.emptyBottomOffset >= 18,
		string.format("V5: getShoppingWindowDiagnostics reports valid geometry (win=%dx%d, emptyOff=%d)",
			diag and diag.winW or 0, diag and diag.winH or 0, diag and diag.emptyBottomOffset or -999))
	check(diag.summaryLine:find("ShopWindow: 1160x720", 1, true) ~= nil
		and diag.summaryLine:find("EmptyBtnBottomOffset:", 1, true) ~= nil
		and diag.summaryLine:find("UIParent:", 1, true) ~= nil,
		"V5: diagnostics summaryLine includes ShopWindow, EmptyBtnBottomOffset, and UIParent")
	local origAddMsg = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage
	local origPrint = _G.print
	local printed = {}
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) printed[#printed + 1] = tostring(msg) end
	end
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		printed[#printed + 1] = table.concat(parts, " ")
	end
	SlashCmdList.MERCHANTMASTER("shopsize")
	_G.print = origPrint
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME.AddMessage = origAddMsg end
	check(#printed >= 1 and printed[#printed]:find("/mm help", 1, true) ~= nil,
		"V5: retired /mm shopsize prints /mm help usage hint")

	-- Final cleanup
	MerchantMasterDB.shoppingWindowSize = nil
	modal:SetSize(1160, 720)
	sp.summaryRail:SetHeight(608)
	sp.layoutSummaryRail()
	app.clearUnifiedShoppingList()
end

-- 17. V6 Shopping List Code-Parity & V3 Socketed Medallion Verification
do
	local modal, sp = app.ui.shopModal, app.ui.shopPanel
	local prevSkin = ns.Theme.GetSkin and ns.Theme.GetSkin() or "standard"
	local prevMode = ns.Theme.GetMode and ns.Theme.GetMode() or "dark"

	-- 17a. Short title (SHOPPING LIST on Goblin, Shopping List on Standard) + V3 Socketed Medallion on ALL 6 themes
	if ns.Theme.SetSkin then ns.Theme.SetSkin("goblin") end
	modal:Show()
	check(stripColors(modal.titleFs:GetText()) == "SHOPPING LIST",
		"V6: Goblin shopModal displays short uppercase SHOPPING LIST, got: " .. tostring(stripColors(modal.titleFs:GetText())))
	check(modal.hdrPortraitWrap and modal.hdrPortraitWrap:IsShown() == true
		and modal.hdrPortraitSocket and modal.hdrPortraitSocket:IsShown() == false
		and modal.hdrPortraitImg and tostring(modal.hdrPortraitImg:GetTexture()):find("goblin\\cart_medallion", 1, true) ~= nil,
		"V6: Goblin shopModal mounts V3 cart_medallion directly with socket hidden")
	check(modal.hdrSkinTile and modal.hdrSkinTile:IsShown() == true
		and tostring(modal.hdrSkinTile:GetTexture()):find("header_tile", 1, true) ~= nil,
		"V6: Goblin top header displays repeating header_tile.blp")
	check(sp.railHdrTile and sp.railHdrTile:IsShown() == true
		and tostring(sp.railHdrTile:GetTexture()):find("header_tile", 1, true) ~= nil,
		"V6: ORDER SUMMARY header displays repeating header_tile.blp")
	check(sp.summaryRail.goldEdges and sp.summaryRail.goldEdges.top:IsShown() == true
		and sp.summaryRail.goldEdges.bottom:IsShown() == true
		and sp.summaryRail.goldEdges.left:IsShown() == true
		and sp.summaryRail.goldEdges.right:IsShown() == true,
		"V6: ORDER SUMMARY panel displays continuous burnished gold border on all 4 sides")

	-- Empty Cart medallion uses V3 cart_medallion
	app.clearUnifiedShoppingList()
	renderShop()
	check(sp.emptyMedWrap and sp.emptyMedWrap.sock:IsShown() == false
		and tostring(sp.emptyMedWrap.icon:GetTexture()):find("goblin\\cart_medallion", 1, true) ~= nil,
		"V6: Empty Cart hero medallion uses Goblin cart_medallion with socket hidden")

	-- Standard skin: Shopping List title + standard Assets\skins\cart_medallion
	if ns.Theme.SetSkin then ns.Theme.SetSkin("standard") end
	if ns.Theme.SetMode then ns.Theme.SetMode("dark") end
	sp.updateSummaryRail()
	check(stripColors(modal.titleFs:GetText()) == "Shopping List",
		"V6: Standard shopModal displays clean 'Shopping List', got: " .. tostring(stripColors(modal.titleFs:GetText())))
	check(modal.hdrPortraitWrap:IsShown() == true
		and tostring(modal.hdrPortraitImg:GetTexture()):find("skins\\cart_medallion", 1, true) ~= nil,
		"V6: Standard Dark shopModal mounts Assets\\skins\\cart_medallion")
	check(tostring(sp.emptyMedWrap.icon:GetTexture()):find("skins\\cart_medallion", 1, true) ~= nil,
		"V6: Standard Empty Cart uses Assets\\skins\\cart_medallion")

	-- Switch back to Goblin to verify stitched Main Order frames, swapIcon, CRAFTABLE purple badge, zero empty-dash, compact CTA
	if ns.Theme.SetSkin then ns.Theme.SetSkin("goblin") end
	MerchantMasterDB.shoppingSortScope = "main"
	MerchantMasterDB.subCraftOverrides = {}
	MerchantMasterDB.craftOrderQueue = { { spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 2 } }
	local savedDailyV6 = ns.GetDailySold
	ns.GetDailySold = function() return nil end
	app.syncUnifiedShoppingList()
	renderShop()
	ns.GetDailySold = savedDailyV6

	check(stripColors(sp.titleFs:GetText()) == "CART ORDERS & BREAKDOWN", "V6: left subheader shows CART ORDERS & BREAKDOWN")
	check(sp.orderCountFs and stripColors(sp.orderCountFs:GetText()) == "1 Main Order",
		"V6: left subheader pill shows '1 Main Order', got: " .. tostring(sp.orderCountFs and stripColors(sp.orderCountFs:GetText())))
	check(sp.clearShopBtn:GetText() == "Empty Cart (1 Order)",
		"V6: Empty Cart button shows 'Empty Cart (1 Order)', got: " .. tostring(sp.clearShopBtn:GetText()))

	-- Unified stitched Main-Order group frame + sub-craft block + swapIcon + zero "· — ·" artifact
	local mainR = shopPool[1]
	check(mainR and mainR.data._inMainGroup == true and mainR.data._isGroupFirst == true
		and mainR.grpBg:IsShown() == true and mainR.grpTop:IsShown() == true and mainR.grpAccent:IsShown() == true,
		"V6: Main Order row renders unified outer gold group frame top + continuous left bar")
	check(stripColors(mainR.subLineFs:GetText()):find("sub-craft", 1, true) ~= nil
		and stripColors(mainR.subLineFs:GetText()):find("direct mat", 1, true) ~= nil,
		"V6: Main Order subtitle includes sub-craft & direct mat breakdown counts")

	local craftHdrR, nestedLeafR, directLeafR, lastR
	for _, rf in ipairs(shopPool) do
		if rf:IsShown() and rf.data then
			if rf.data._isGroupLast then lastR = rf end
			if not rf.data.isMainRow and rf.data.makeMyself then craftHdrR = rf end
			if not rf.data.isMainRow and rf.data.isSubRow then nestedLeafR = rf end
			if not rf.data.isMainRow and not rf.data.isSubRow and not rf.data.makeMyself and not rf.data.canToggleCraft and not rf.data.isVendor then
				directLeafR = rf
			end
		end
	end
	check(lastR ~= nil and lastR.grpBot:IsShown() == true, "V6: Last row in Main Order group seals unified bottom gold border")
	check(craftHdrR ~= nil and craftHdrR.data._inSubBlock == true and craftHdrR.subAccent:IsShown() == true
		and craftHdrR.cells[8].swapIcon:IsShown() == true
		and craftHdrR.cells[8].fs:GetText():find("|cffffffffCRAFT|r", 1, true) ~= nil,
		"V6: Active SUB-CRAFT renders cyan/violet block, white CRAFT + cyan prof text, and swap icon")
	check(nestedLeafR ~= nil and nestedLeafR.data._inSubBlock == true and nestedLeafR.subAccent:IsShown() == true,
		"V6: Nested leaf inherits seamless cyan/violet sub-craft block")
	check(directLeafR ~= nil and directLeafR.cells[8].swapIcon:IsShown() == false,
		"V6: Non-toggleable leaf hides swap icon")
	if directLeafR then
		local mkt = stripColors(directLeafR.inlineMetaFs:GetText())
		check(mkt:find("· — ·", 1, true) == nil, "V6/V7: Single-line leaf metadata omits empty '· — ·' dash when dailySold is nil, got: " .. mkt)
	end

	-- Toggle Fire Oil to BUY AH -> verify CRAFTABLE badge is rich purple + pure white text AND BUY AH shows swapIcon!
	if craftHdrR then
		craftHdrR.cells[8]:Click("LeftButton")
		renderShop()
		local buySubR
		for _, rf in ipairs(shopPool) do
			if rf:IsShown() and rf.data and rf.data.canToggleCraft and rf.data.makeMyself == false then
				buySubR = rf
				break
			end
		end
		check(buySubR ~= nil and buySubR.tierBadge.fs:GetText():find("|cffffffffCRAFTABLE|r", 1, true) ~= nil,
			"V6: CRAFTABLE badge uses pure white text on rich purple pill in Goblin skin")
		check(buySubR ~= nil and buySubR.cells[8].swapIcon:IsShown() == true,
			"V6: Toggleable BUY AH pill displays right-side swapIcon")
		check(buySubR ~= nil and buySubR.cells[8]:GetWidth() == 96,
			"V7: Toggleable CRAFTABLE BUY AH pill matches uniform 96px width (got " .. tostring(buySubR and buySubR.cells[8]:GetWidth()) .. ")")
	end

	-- 18. V7 14-Point Code-Parity Checks: single-line heights, uniform 96/122px pills, qtyBadge, color icons, skin send_btn, hidden AH Buyer Mode, non-overlapping subHdr
	MerchantMasterDB.subCraftOverrides = {}
	app.syncUnifiedShoppingList()
	renderShop()
	local v7Main, v7Sub, v7Leaf
	for _, rf in ipairs(shopPool) do
		if rf:IsShown() and rf.data then
			if rf.data.isMainRow and not v7Main then v7Main = rf
			elseif (not rf.data.isMainRow) and (rf.data.makeMyself or rf.data.canToggleCraft) and not v7Sub then v7Sub = rf
			elseif (not rf.data.isMainRow) and (not rf.data.makeMyself) and (not rf.data.canToggleCraft) and not v7Leaf then v7Leaf = rf end
		end
	end
	check(v7Main and v7Main:GetHeight() == 48 and v7Main.subLineFs:IsShown() == true and v7Main.qtyBadge:IsShown() == false,
		"V7: Main Order row stays 2-line 48px with subtitle shown and qtyBadge hidden")
	check(v7Sub and v7Sub:GetHeight() == 34 and v7Sub.subLineFs:IsShown() == false and v7Sub.qtyBadge:IsShown() == true and v7Sub.inlineMetaFs:IsShown() == true,
		"V7: Sub-Craft row is single-line 34px with inline qtyBadge + inlineMetaFs")
	check(v7Leaf and (v7Leaf:GetHeight() == 30 or v7Leaf:GetHeight() == 38) and v7Leaf.subLineFs:IsShown() == false and v7Leaf.qtyBadge:IsShown() == true and v7Leaf.inlineMetaFs:IsShown() == true,
		"V7: Leaf row is single-line 30px (+8px if last) with inline qtyBadge + inlineMetaFs")
	check(v7Sub and v7Sub.cells[8]:GetWidth() == 122 and v7Sub.cells[8].gradTex:IsShown() == true and v7Sub.cells[8].topSheen:IsShown() == true,
		"V7: CRAFT pill is fixed 122px wide with vertical gradient + top sheen")
	check(v7Leaf and v7Leaf.cells[8]:GetWidth() == 96 and v7Leaf.cells[8].gradTex:IsShown() == true and v7Leaf.cells[8].topSheen:IsShown() == true,
		"V7: Leaf action pill is fixed 96px wide with vertical gradient + top sheen")
	check(v7Main and v7Main.iconSocket.skinTex:IsShown() == false and v7Main.iconSocket.colorFrame ~= nil and v7Main.iconSocket:GetWidth() == 30,
		"V7: Main Order uses color-coded 30x30 icon frame instead of metallic socket.blp")
	check(v7Leaf and v7Leaf.iconSocket.skinTex:IsShown() == false and v7Leaf.iconSocket:GetWidth() == 20,
		"V7: Leaf row uses color-coded 20x20 icon frame")
	check(v7Main and v7Main.tierBadge:GetHeight() == 16 and v7Sub and v7Sub.tierBadge:GetHeight() == 15,
		"V7: Tier badges use compact square glass_r4 sizing (16px Main / 15px Sub)")
	check(sp.buyAllBtn.skinGem:IsShown() == true and sp.buyAllBtn.gemWrap:GetWidth() == 34 and sp.buyAllBtn.gradTex:IsShown() == true,
		"V7: Goblin Send to Auction House CTA uses 34x34 skin send_btn icon + vertical emerald gradient")
	check(sp.clearShopBtn.gradTex:IsShown() == true, "V7: Empty Cart CTA uses vertical ruby-crimson gradient")
	check(sp.buyerModeSeg == nil and sp.modeHintFs == nil and app.ui.optBuiltInBuyerCheck == nil,
		"V7: Legacy AH Buyer Mode toggle completely removed from Shopping Cart and Settings")
	local hintPt, hintRel, hintRelPt, hintX = sp.subHintFs:GetPoint(1)
	check(hintPt == "LEFT" and hintRel == sp.orderCountPill and hintRelPt == "RIGHT" and (hintX or 0) >= 12,
		"V7: Left subheader hint anchors >= 12px right of orderCountPill (zero overlap!)")

	-- Cleanup
	MerchantMasterDB.subCraftOverrides = {}
	app.clearUnifiedShoppingList()
	if ns.Theme.SetSkin then ns.Theme.SetSkin(prevSkin) end
	if ns.Theme.SetMode then ns.Theme.SetMode(prevMode) end
end

-- Restore hooks
ns.GetPlayerProfessions = savedGetProfs
ns.GetReagentUnitCost = savedGetCost
ns.GetNumListed = savedGetListed
ns.GetDailySold = savedGetDaily
ns.GetOwnedItemCounts = savedGetOwned
app.searchAH = savedSearchAH
app.enterOrderFlowMode = savedEnterOrderFlow
_G.Auctionator = savedAuc
_G.AuctionHouseFrame = savedAHFrame

print(string.format("unified_shopping_list: %d assertions, 0 failures", n))
