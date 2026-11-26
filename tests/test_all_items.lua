local ns, _, host = dofile("host_fixture.lua")
local check = host.check

local AI = ns.AllItemsModel
local app = ns.app
local Theme = ns.Theme

check(type(AI) == "table", "ns.AllItemsModel exported")
check(type(ns.AllItems) == "table", "ns.AllItems UI provider exported")

-- 1. Catalog Completeness (includes non-recipe gather goods like Solid Stone 7912)
local catalog = AI.GetCatalog()
check(type(catalog) == "table" and #catalog >= 1000,
	"AllItems catalog includes full catalog entries, got " .. tostring(catalog and #catalog))

local byID = {}
local dupes = 0
local blanks = 0
local typeCounts = {}
for _, entry in ipairs(catalog) do
	if type(entry.itemID) ~= "number" or entry.itemID <= 0 then
		blanks = blanks + 1
	end
	if type(entry.name) ~= "string" or entry.name == "" then
		blanks = blanks + 1
	end
	if byID[entry.itemID] then
		dupes = dupes + 1
	else
		byID[entry.itemID] = entry
	end
	typeCounts[entry.itemType] = (typeCounts[entry.itemType] or 0) + 1
end
check(dupes == 0, "AllItems catalog has 0 duplicate itemIDs, got " .. tostring(dupes))
check(blanks == 0, "AllItems catalog has 0 missing IDs or blank names, got " .. tostring(blanks))
check((typeCounts.gather or 0) >= 30, "Catalog has >=30 gathering items, got " .. tostring(typeCounts.gather))
check((typeCounts.crafted or 0) >= 500, "Catalog has >=500 crafted items, got " .. tostring(typeCounts.crafted))
check((typeCounts.material or 0) >= 50, "Catalog has >=50 material items, got " .. tostring(typeCounts.material))
check((typeCounts.scroll or 0) >= 10, "Catalog has >=10 scroll items, got " .. tostring(typeCounts.scroll))
check((typeCounts.turnin or 0) >= 10, "Catalog has >=10 crate/writ turn-in items, got " .. tostring(typeCounts.turnin))
check((typeCounts.vendor or 0) >= 10, "Catalog has >=10 vendor items, got " .. tostring(typeCounts.vendor))

local solidStone = byID[7912]
check(solidStone ~= nil, "Solid Stone (7912) is present in AllItems catalog")
check(solidStone and solidStone.name == "Solid Stone", "Item 7912 is named 'Solid Stone', got " .. tostring(solidStone and solidStone.name))
check(solidStone and solidStone.prof == "mining" and solidStone.itemType == "gather",
	"Solid Stone is classified under Mining gathering goods")
check(solidStone and (solidStone.usedInCount or 0) > 0,
	"Solid Stone tracks Used In crafting recipes, count=" .. tostring(solidStone and solidStone.usedInCount))

local copperBar = byID[2840]
check(copperBar ~= nil and copperBar.prof == "mining" and copperBar.itemType == "crafted",
	"Copper Bar (2840) is Mining crafted (smelted) item")

-- Check Herbalism & Skinning representation
local hasHerb, hasSkin = false, false
for _, e in ipairs(catalog) do
	if e.prof == "herbalism" and e.itemType == "gather" then hasHerb = true end
	if e.prof == "skinning" and e.itemType == "gather" then hasSkin = true end
end
check(hasHerb, "Catalog contains Herbalism gathering goods")
check(hasSkin, "Catalog contains Skinning gathering goods")

-- 2. Standalone Blizzard Snapshot Evaluation, Pricing & Filtering (zero TSM dependency)
MerchantMasterDB.enableLegacyPriceAddons = false
do
	local b32 = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
	local function enc32(num)
		num = math.floor(tonumber(num) or 0)
		if num <= 0 then return "0" end
		local d = {}
		while num > 0 do
			local rem = num % 32
			d[#d + 1] = b32:sub(rem + 1, rem + 1)
			num = math.floor(num / 32)
		end
		local out = {}
		for i = #d, 1, -1 do out[#out + 1] = d[i] end
		return table.concat(out)
	end
	local econ = (ns.CurrentEconomyInfo and ns.CurrentEconomyInfo().effectiveKey) or "Normal-Horde"
	local snapTs = ((_G.time and _G.time()) or 1794360000) - 300
	local function snapLine(id, minBuyout, marketVal, hist, qty, recent)
		return string.format("%d:%s,%s,%s,%s,%s,%s",
			id, enc32(minBuyout), enc32(marketVal), enc32(hist), enc32(qty), enc32(snapTs), enc32(recent))
	end
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
		string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=3,heatmapCount=0}]], snapTs))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, table.concat({
		snapLine(7912, 1200, 1400, 1350, 85, 1300),
		snapLine(2840, 2500, 2700, 2600, 40, 2600),
		snapLine(2447, 300,  350,  320,  120, 310),
	}, ";"))
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end
check(MerchantMasterDB.enableLegacyPriceAddons == false, "All Items tests run in strict standalone mode")

local evalRows
local completed = false
AI.Start({
	db = MerchantMasterDB,
	econInfo = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo() or {},
	defer = false,
	applyAHCut = true,
}, nil, function(rows)
	evalRows = rows
	completed = true
end)
check(completed and type(evalRows) == "table" and #evalRows == #catalog,
	"AllItemsModel.Start(defer=false) synchronously evaluates all catalog items")

local rowMap = {}
for _, r in ipairs(evalRows) do rowMap[r.itemID] = r end
local ssRow = rowMap[7912]
check(ssRow ~= nil and ssRow.unitAH == 1200 and ssRow.marketValue == 1400 and ssRow.listed == 85,
	string.format("Solid Stone reflects standalone Blizzard snapshot (unitAH=%s, marketValue=%s, listed=%s)",
		tostring(ssRow and ssRow.unitAH), tostring(ssRow and ssRow.marketValue), tostring(ssRow and ssRow.listed)))

-- Mining filter includes both Solid Stone & Copper Bar
local miningAll = AI.FilterSort(evalRows, { profFilter = "mining" }, { key = "name", ascending = true })
local sawSS, sawCB = false, false
for _, r in ipairs(miningAll) do
	check(r.prof == "mining" or (r.profSet and r.profSet.mining), "Mining filter matches only mining items: " .. tostring(r.name))
	if r.itemID == 7912 then sawSS = true end
	if r.itemID == 2840 then sawCB = true end
end
check(sawSS and sawCB, "Mining filter includes both Solid Stone (7912) and Copper Bar (2840)")

-- Mining + Gathering filter keeps Solid Stone, excludes smelted Copper Bar
local miningGather = AI.FilterSort(evalRows, { profFilter = "mining", itemTypes = { gather = true } }, { key = "name", ascending = true })
local sawSSG, sawCBG = false, false
for _, r in ipairs(miningGather) do
	check(r.itemType == "gather", "Gathering type filter excludes non-gather items: " .. tostring(r.name))
	if r.itemID == 7912 then sawSSG = true end
	if r.itemID == 2840 then sawCBG = true end
end
check(sawSSG and not sawCBG, "Mining + Gathering keeps Solid Stone (7912) and excludes smelted Copper Bar (2840)")

-- Herbalism & Skinning filters
local herbRows = AI.FilterSort(evalRows, { profFilter = "herbalism" }, { key = "name", ascending = true })
local skinRows = AI.FilterSort(evalRows, { profFilter = "skinning" }, { key = "name", ascending = true })
check(#herbRows >= 5, "Herbalism filter returns herb items, count=" .. tostring(#herbRows))
check(#skinRows >= 5, "Skinning filter returns skinning items, count=" .. tostring(#skinRows))
for _, r in ipairs(skinRows) do
	check(r.prof == "skinning" or (r.profSet and r.profSet.skinning), "Skinning filter excludes non-skinning items: " .. tostring(r.name))
end

-- Role, sellable, skill range, and search filters
local reagentRows = AI.FilterSort(evalRows, { roleFilter = "reagent" }, { key = "usedInCount", ascending = false })
check(#reagentRows >= 20, "Role='reagent' returns crafting reagents")
for _, r in ipairs(reagentRows) do check((r.usedInCount or 0) > 0, "Role='reagent' requires usedInCount > 0") end

local ahRows = AI.FilterSort(evalRows, { sellableFilter = "yes" }, { key = "itemID", ascending = true })
local bopRows = AI.FilterSort(evalRows, { sellableFilter = "no" }, { key = "itemID", ascending = true })
check(#ahRows > 0 and #bopRows > 0, "Sellable filter partitions AH sellable (" .. #ahRows .. ") and BoP (" .. #bopRows .. ") items")
for _, r in ipairs(bopRows) do check(not r.sellable, "sellableFilter='no' shows non-sellable/BoP items only") end

local searchSS = AI.FilterSort(evalRows, { search = "Solid Stone" }, { key = "itemID", ascending = true })
check(#searchSS == 1 and searchSS[1].itemID == 7912, "Search 'Solid Stone' isolates item 7912")

local skillSub = AI.FilterSort(evalRows, { profFilter = "mining", itemTypes = { gather = true }, skillMin = 125, skillMax = 200 }, { key = "requiredSkill", ascending = true })
check(#skillSub >= 1, "Skill range filter matches Iron/Mithril/Solid Stone tier")
for _, r in ipairs(skillSub) do
	check(r.requiredSkill and r.requiredSkill >= 125 and r.requiredSkill <= 200, "Skill bounds enforced cleanly")
end

-- 3. UI Navigation, Header Fit, Filters, Columns, QuickLook, Stepper & Isolation
app.panel:Show()
if _G.SlashCmdList and _G.SlashCmdList.MERCHANTMASTER then
	_G.SlashCmdList.MERCHANTMASTER("items")
end
check(app.activeTab == "all_items", "/mm items opens the all_items tab, got " .. tostring(app.activeTab))

local ui = app.ui
local view = ui.allItemsView
local tbl = ui.allItemsTable
check(view ~= nil and view:IsShown(), "app.ui.allItemsView is shown on all_items tab")
check(tbl ~= nil and tbl.scrollBox ~= nil, "app.ui.allItemsTable created")

-- Verify 14 header pills including All, Mine, Herb, Skin, Others
check(type(view.profOrder) == "table" and #view.profOrder == 14,
	"Header renders 14 profession pills, got " .. tostring(view.profOrder and #view.profOrder))
for _, key in ipairs({ "all", "mining", "herbalism", "skinning", "others" }) do
	check(view.profBtns[key] ~= nil, "Header pill exists for " .. key)
end

-- Verify 1320px header pill + right button span does not exceed Goblin min width (1036px mainArea)
local pillRightSum = 6
for _, b in ipairs(view.profOrder) do pillRightSum = pillRightSum + b:GetWidth() + 3 end
local rightCtrlSpan = 4 + view.colSettingsBtn:GetWidth() + 6 + view.shopButton:GetWidth() + 6 + view.resetButton:GetWidth() + 6 + view.filtersButton:GetWidth() + 16
check(pillRightSum + rightCtrlSpan < 900,
	string.format("14 pills (%dpx) + right controls (%dpx) leave >=136px gap at Goblin 1036px mainArea", pillRightSum, rightCtrlSpan))

-- Clicking Mine pill filters All Items WITHOUT touching MerchantMasterDB.profFilter (All Recipes)
MerchantMasterDB.profFilter = "alchemy"
MerchantMasterDB.superListColumns = { order = { "name", "profit" }, hidden = { listed = true } }
view.profBtns.mining:Click("LeftButton")
check(MerchantMasterDB.allItemsProfFilter == "mining", "Clicking Mine pill sets db.allItemsProfFilter = 'mining'")
check(MerchantMasterDB.profFilter == "alchemy", "All Items pill click does not mutate All Recipes db.profFilter")

local aiFiltered = ns.AllItems.GetFilteredRows()
check(type(aiFiltered) == "table" and #aiFiltered > 0, "Filtered Mining rows populated after Mine click")
local foundSSInTable = false
for _, r in ipairs(aiFiltered) do
	if r.itemID == 7912 then foundSSInTable = true end
end
check(foundSSInTable, "Mining table view includes Solid Stone (7912)")

-- Column customization isolation & toggle
ns.AllItems.SetColumnVisible("marketValue", true)
check(type(MerchantMasterDB.allItemsColumns) == "table"
	and MerchantMasterDB.allItemsColumns.hidden.marketValue == nil,
	"SetColumnVisible('marketValue', true) updates db.allItemsColumns")
check(MerchantMasterDB.superListColumns.hidden.listed == true
	and #MerchantMasterDB.superListColumns.order == 2,
	"All Items column customization never modifies db.superListColumns")
ns.AllItems.ResetColumns()

-- Sidebar Controls & Filters Popover (must show All Items filters without global recipe Prof grid)
local sbCtrls = ns.AllItems.GetSidebarControls()
check(type(sbCtrls) == "table" and #sbCtrls == 6, "GetSidebarControls returns 6 filter widgets")
view.filtersButton:Click("LeftButton")
check(ui.sidebarOptionsHost and ui.sidebarOptionsHost:IsShown() and ui.sidebarOptionsHost._mode == "filters",
	"Clicking Filters button opens sidebarOptionsHost in filters mode")
if ui.unlockBtn then
	check(not ui.unlockBtn:IsShown(), "All Items Filters popover hides global All Recipes unlockBtn")
end
ui.sidebarOptionsHost:Hide()

-- Quick Look (kind='item') for Solid Stone + "+ Add to Cart"
MerchantMasterDB.shoppingList = {}
app.openQuickLook("item", ssRow, { toggle = false })
local hud = app.superListProvider and app.superListProvider.GetQuickLookFrame()
check(hud ~= nil and hud:IsShown(), "Item Quick Look HUD opens for Solid Stone")
check(hud.kind == "item", "Quick Look kind is 'item', got " .. tostring(hud.kind))
check(hud.title and hud.title:GetText() == "Solid Stone", "Quick Look title is 'Solid Stone'")
check(hud.whereToBuy and (hud.whereToBuy:GetText() or ""):find("^Source:") ~= nil,
	"Item Quick Look displays 'Source:' line, got " .. tostring(hud.whereToBuy and hud.whereToBuy:GetText()))
check(hud.moverEmpty and not hud.moverEmpty:IsShown(),
	"Solid Stone displays Used In recipe movers in Quick Look")

hud.addButton:Click("LeftButton")
check(app.getItemShoppingQty(ssRow) == 1, "Clicking '+ Add to Cart' in Item Quick Look adds Solid Stone qty=1")
local basketEntry
for _, entry in ipairs(MerchantMasterDB.shoppingList or {}) do
	if entry.key == "item:7912" then basketEntry = entry end
end
check(basketEntry ~= nil and basketEntry.itemID == 7912 and basketEntry.qty == 1,
	"Shopping List records direct buy entry key='item:7912', qty=1")

-- Shift Stepper +1 / -1 adjustments
check(app.adjustItemShoppingQty(ssRow, 2) == 3 and app.getItemShoppingQty(ssRow) == 3,
	"adjustItemShoppingQty(+2) increments Solid Stone to 3")
check(app.adjustItemShoppingQty(ssRow, -3) == 0 and app.getItemShoppingQty(ssRow) == 0,
	"adjustItemShoppingQty(-3) removes Solid Stone cleanly when qty reaches 0")

-- Reset button restores All
view.resetButton:Click("LeftButton")
check(MerchantMasterDB.allItemsProfFilter == "all", "Reset button resets db.allItemsProfFilter to 'all'")

-- Theme switch Light -> Dark renders cleanly without error
Theme.SetMode("light")
check(Theme.GetMode() == "light" and view:IsShown(), "Light mode renders All Items cleanly")
Theme.SetMode("dark")
check(Theme.GetMode() == "dark" and view:IsShown(), "Dark mode renders All Items cleanly")

-- 4. Craft completion (ownership + cooldown + skills) updates ONLY affected row(s) without restarting load or scroll
do
	-- Ensure All Items is active and fully built in default non-ownedQty sort
	view.resetButton:Click("LeftButton")
	app.refresh()
	local sortState = app.sortState.all_items
	check(sortState and sortState.col == "turnoverPerDay", "Default All Items sort is turnoverPerDay")

	local startCalls, filterSortCalls, setRowsCalls = 0, 0, 0
	local origStart = AI.Start
	local origFilterSort = AI.FilterSort
	local origSetRows = tbl.setRows
	AI.Start = function(...)
		startCalls = startCalls + 1
		return origStart(...)
	end
	AI.FilterSort = function(...)
		filterSortCalls = filterSortCalls + 1
		return origFilterSort(...)
	end
	tbl.setRows = function(...)
		setRowsCalls = setRowsCalls + 1
		return origSetRows(...)
	end

	-- Simulate bag state gaining 17 Solid Stone (7912) from a craft via real BAG_UPDATE_DELAYED + cooldown/skills events
	local origNumSlots = C_Container.GetContainerNumSlots
	local origItemInfo = C_Container.GetContainerItemInfo
	local craftedQty = 17
	C_Container.GetContainerNumSlots = function(b)
		if b == 0 then return 3 end
		return origNumSlots(b)
	end
	C_Container.GetContainerItemInfo = function(b, s)
		if b == 0 and s == 3 then
			return {
				itemID = 7912,
				stackCount = craftedQty,
				iconFileID = 135232,
				hyperlink = "|cffffffff|Hitem:7912::::::::20:::::|h[Solid Stone]|h|r",
			}
		end
		return origItemInfo(b, s)
	end

	host.eventFrame._scripts.OnEvent(host.eventFrame, "BAG_UPDATE_DELAYED")
	app.invalidateRecipeStats("cooldown", { [999111] = true })
	app.invalidateRecipeStats("skills")
	app.refresh()

	check(startCalls == 0, "Craft completion does NOT restart AllItemsModel.Start, calls=" .. tostring(startCalls))
	check(filterSortCalls == 0, "Craft completion on default sort does NOT re-run FilterSort, calls=" .. tostring(filterSortCalls))
	check(setRowsCalls == 0, "Craft completion on default sort does NOT call tbl.setRows (preserves scroll), calls=" .. tostring(setRowsCalls))

	local ssUpdated
	for _, r in ipairs(ns.AllItems.GetRows()) do
		if r.itemID == 7912 then ssUpdated = r; break end
	end
	check(ssUpdated ~= nil and ssUpdated.ownedQty == 17,
		"Targeted craft update sets Solid Stone ownedQty == 17 in place, got " .. tostring(ssUpdated and ssUpdated.ownedQty))

	-- Sorting by ownedQty still avoids restarting Start, while allowing FilterSort to re-order cleanly
	app.sortState.all_items = { col = "ownedQty", asc = false }
	craftedQty = 23
	host.eventFrame._scripts.OnEvent(host.eventFrame, "BAG_UPDATE_DELAYED")
	app.refresh()
	check(startCalls == 0, "Craft update while sorted by ownedQty still avoids restarting AllItemsModel.Start")
	check(filterSortCalls >= 1, "Craft update while sorted by ownedQty re-sorts cleanly via FilterSort")
	check(ssUpdated.ownedQty == 23, "Solid Stone ownedQty updates to 23 when sorting by ownedQty")

	-- Mid-load craft completion must NOT reset incremental build index back to 1
	app.sortState.all_items = { col = "turnoverPerDay", asc = false }
	ns.AllItems.Invalidate() -- full reset for fresh incremental load test
	local origAfter = _G.C_Timer.After
	local timerQ = {}
	_G.C_Timer.After = function(_, fn)
		if type(fn) == "function" then timerQ[#timerQ + 1] = fn end
	end
	startCalls, filterSortCalls, setRowsCalls = 0, 0, 0
	local okMid, errMid = pcall(function()
		app.refresh()
		local _, st = nil, nil
		-- Drain first 4 deferred ticks to advance partway through incremental load
		for step = 1, 4 do
			local batch = timerQ
			timerQ = {}
			for _, fn in ipairs(batch) do fn() end
		end
		check(startCalls == 1, "Incremental mid-load triggered exactly 1 Start, got " .. tostring(startCalls))
		local rowsMid = ns.AllItems.GetRows()
		local loadedBeforeCraft = #(rowsMid or {})
		check(loadedBeforeCraft > 0 and loadedBeforeCraft < #catalog,
			string.format("Mid-load partially evaluated (%d / %d rows) before finishing", loadedBeforeCraft, #catalog))

		-- Finish craft mid-load while still loading
		craftedQty = 31
		host.eventFrame._scripts.OnEvent(host.eventFrame, "BAG_UPDATE_DELAYED")
		app.invalidateRecipeStats("cooldown", { [999112] = true })
		app.refresh()

		check(startCalls == 1, "Craft mid-load did NOT restart AllItemsModel.Start, calls=" .. tostring(startCalls))
		local loadedRightAfterCraft = #(ns.AllItems.GetRows() or {})
		check(loadedRightAfterCraft >= loadedBeforeCraft,
			string.format("Craft mid-load kept loaded rows (%d >= %d)", loadedRightAfterCraft, loadedBeforeCraft))

		-- Finish draining all remaining deferred steps
		local guard = 0
		while #timerQ > 0 and guard < 2000 do
			guard = guard + 1
			local fn = table.remove(timerQ, 1)
			fn()
		end
		check(#timerQ == 0, "Incremental load + mid-load patch completed cleanly")
		local ssMidDone
		for _, r in ipairs(ns.AllItems.GetRows()) do
			if r.itemID == 7912 then ssMidDone = r; break end
		end
		check(ssMidDone ~= nil and ssMidDone.ownedQty == 31,
			"Mid-load craft update yields final ownedQty == 31, got " .. tostring(ssMidDone and ssMidDone.ownedQty))

		-- Background warm -> foreground switch does not restart completed warm build
		ns.AllItems.Invalidate()
		_G.C_Timer.After = origAfter
		app.setTab("dashboard")
		ns.AllItems.WarmInBackground(app.buildAllItemsContext({ defer = false }))
		check(ns.AllItems.HasWarmData(), "WarmInBackground completes warm dataset cleanly")
		startCalls = 0
		app.setTab("all_items")
		check(startCalls == 0, "Opening All Items after WarmInBackground avoids restarting Start, calls=" .. tostring(startCalls))
	end)

	-- Restore stubs & bag state cleanly
	_G.C_Timer.After = origAfter
	AI.Start = origStart
	AI.FilterSort = origFilterSort
	tbl.setRows = origSetRows
	C_Container.GetContainerNumSlots = origNumSlots
	C_Container.GetContainerItemInfo = origItemInfo
	app.bagsDirty = true
	app.bagCountsDirty = true
	if not okMid then error(errMid, 0) end
end

app.superListProvider.CloseQuickLook()

-- 5. Exhaustive filter, column sort, stepper parity, Deep Analysis & performance checks
do
	view.resetButton:Click("LeftButton")
	app.refresh()

	local allRows = ns.AllItems.GetRows()
	local totalCount = #allRows
	check(totalCount == #catalog, string.format("Full All Items load matches catalog (%d == %d)", totalCount, #catalog))

	-- 5a. Every one of the 14 header profession pills filters live UI without touching db.profFilter
	local pillCounts = {}
	MerchantMasterDB.profFilter = "tailoring"
	for _, btn in ipairs(view.profOrder or {}) do
		btn:Click("LeftButton")
		check(MerchantMasterDB.allItemsProfFilter == btn.profKey,
			"Header pill sets db.allItemsProfFilter = " .. tostring(btn.profKey))
		local fRows = ns.AllItems.GetFilteredRows()
		pillCounts[btn.profKey] = #fRows
		if btn.profKey == "all" then
			check(#fRows == totalCount, "'All' pill restores full catalog rows")
		else
			check(#fRows > 0 and #fRows < totalCount,
				string.format("Pill '%s' filters to subset (%d / %d)", tostring(btn.profKey), #fRows, totalCount))
		end
	end
	check(MerchantMasterDB.profFilter == "tailoring", "14-pill sweep preserves All Recipes db.profFilter")
	check(pillCounts.mining < 200 and pillCounts.herbalism < 200 and pillCounts.skinning < 200 and pillCounts.others < 1000,
		"Gathering and Others pills stay cleanly scoped")
	view.profBtns.all:Click("LeftButton")
	check(#ns.AllItems.GetFilteredRows() == totalCount, "Clicking All restores all rows")

	-- 5b. Sidebar filter modes (itemTypes single/multi/clear, 6 roles, 3 trade modes, 7 demand modes, skill bounds, searchBox + Reset)
	local gatherOnly = AI.FilterSort(allRows, { profFilter = "all", itemTypes = { gather = true } }, { key = "turnoverPerDay", ascending = false }, {})
	local gatherAndMat = AI.FilterSort(allRows, { profFilter = "all", itemTypes = { gather = true, material = true } }, { key = "turnoverPerDay", ascending = false }, {})
	check(#gatherOnly > 0 and #gatherAndMat > #gatherOnly and #gatherAndMat < totalCount,
		string.format("Multi-select itemTypes accumulates cleanly (%d < %d < %d)", #gatherOnly, #gatherAndMat, totalCount))

	for _, role in ipairs({ "all", "gather", "reagent", "craftable", "crate_writ", "priced" }) do
		local res = AI.FilterSort(allRows, { profFilter = "all", roleFilter = role }, { key = "turnoverPerDay", ascending = false }, {})
		check(type(res) == "table" and #res <= totalCount, "Role filter '" .. role .. "' executes cleanly")
		if role ~= "all" and role ~= "priced" then
			check(#res > 0 and #res < totalCount,
				string.format("Role '%s' produces strict subset (%d)", role, #res))
		end
	end

	local tradeAll = AI.FilterSort(allRows, { profFilter = "all", sellableFilter = "all" }, { key = "turnoverPerDay", ascending = false }, {})
	local tradeYes = AI.FilterSort(allRows, { profFilter = "all", sellableFilter = "yes" }, { key = "turnoverPerDay", ascending = false }, {})
	local tradeNo = AI.FilterSort(allRows, { profFilter = "all", sellableFilter = "no" }, { key = "turnoverPerDay", ascending = false }, {})
	check(#tradeYes > 0 and #tradeNo > 0 and (#tradeYes + #tradeNo == #tradeAll),
		string.format("Sellable filter exact partition (%d + %d == %d)", #tradeYes, #tradeNo, #tradeAll))

	for _, dem in ipairs({ "all", "monopoly", "high_turn", "hot", "unlisted", "listed", "cold" }) do
		local res = AI.FilterSort(allRows, { profFilter = "all", demandFilter = dem }, { key = "turnoverPerDay", ascending = false }, {})
		check(type(res) == "table" and #res <= totalCount, "Demand filter '" .. dem .. "' executes cleanly")
	end

	-- Sidebar skill min/max EditBox wiring + invalid input normalization
	local minBox = view.skillControl and view.skillControl.minBox
	local maxBox = view.skillControl and view.skillControl.maxBox
	check(minBox ~= nil and maxBox ~= nil, "Sidebar skillControl exposes minBox and maxBox")
	minBox:SetText("125")
	maxBox:SetText("200")
	minBox._scripts.OnEnterPressed(minBox)
	check(MerchantMasterDB.allItemsSkillMin == 125 and MerchantMasterDB.allItemsSkillMax == 200,
		"Skill EditBoxes store db.allItemsSkillMin/Max cleanly")
	local skillRows = ns.AllItems.GetFilteredRows()
	check(#skillRows > 0 and #skillRows < totalCount, "Skill range UI filter narrows table rows")
	for _, r in ipairs(skillRows) do
		check(r.requiredSkill and r.requiredSkill >= 125 and r.requiredSkill <= 200, "UI skill bounds hold for every visible row")
	end
	minBox:SetText("abc")
	minBox._scripts.OnEnterPressed(minBox)
	check(MerchantMasterDB.allItemsSkillMin == nil, "Invalid skill input normalizes bound to nil")

	-- Global searchBox live filter + Reset button
	local sb = ui.searchBox
	check(sb ~= nil, "Global ui.searchBox exists")
	sb:SetText("Solid Stone")
	app.onOverviewSearchChanged(sb, false)
	local searchedRows = ns.AllItems.GetFilteredRows()
	check(#searchedRows == 1 and searchedRows[1].itemID == 7912,
		"Global searchBox 'Solid Stone' narrows All Items live view to item 7912")
	view.resetButton:Click("LeftButton")
	check((sb:GetText() or "") == "" and MerchantMasterDB.allItemsProfFilter == "all"
		and MerchantMasterDB.allItemsSkillMin == nil and MerchantMasterDB.allItemsSkillMax == nil,
		"Reset button clears searchBox, prof pill, and skill bounds")
	check(#ns.AllItems.GetFilteredRows() == totalCount, "Reset button restores all catalog rows")

	-- 5c. All 17 columns sort cleanly (both desc and asc) with empty workspace table
	local colKeys = {
		"name", "categoryLabel", "ownedQty", "listed", "goodScore",
		"unitAH", "vendorSell", "salesPerDay", "turnoverPerDay", "demandSort",
		"usedInCount", "sourceLabel", "marketValue", "craftCost", "profit",
		"requiredSkill", "wowheadURL",
	}
	for _, ck in ipairs(colKeys) do
		local dRes = AI.FilterSort(allRows, { profFilter = "all" }, { key = ck, ascending = false }, {})
		local aRes = AI.FilterSort(allRows, { profFilter = "all" }, { key = ck, ascending = true }, {})
		check(#dRes == totalCount and #aRes == totalCount,
			string.format("Sort column '%s' preserves all %d rows desc+asc", ck, totalCount))
	end

	-- 5d. Shift Quick-Add stepper & row click parity (+1, +5, -1, remove all, Shift+RightButton)
	MerchantMasterDB.shoppingList = {}
	ns.AllItems.SetShiftMode(true)
	check(view.shiftBadge and view.shiftBadge:IsShown(), "Shift mode shows header shiftBadge")
	local boundFrame
	for _, fr in ipairs((tbl.scrollBox and tbl.scrollBox._frames) or {}) do
		if fr.data and fr.shiftStepper then boundFrame = fr; break end
	end
	check(boundFrame ~= nil and boundFrame.shiftStepper:IsShown(),
		"Shift mode renders row stepper on visible row")
	local rowData = boundFrame.data
	boundFrame.shiftStepper.plusBtn:Click("LeftButton")
	check(app.getItemShoppingQty(rowData) == 1, "Stepper '+' LeftButton adds +1")
	boundFrame.shiftStepper.plusBtn:Click("RightButton")
	check(app.getItemShoppingQty(rowData) == 6, "Stepper '+' RightButton adds +5 (1 -> 6)")
	boundFrame.shiftStepper.minusBtn:Click("LeftButton")
	check(app.getItemShoppingQty(rowData) == 5, "Stepper '-' LeftButton removes -1 (6 -> 5)")
	boundFrame.shiftStepper.minusBtn:Click("RightButton")
	check(app.getItemShoppingQty(rowData) == 0, "Stepper '-' RightButton removes all (5 -> 0)")

	local origIsShift = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	boundFrame:Click("LeftButton")
	check(app.getItemShoppingQty(rowData) == 1, "Shift+LeftClick row adds +1")
	boundFrame:Click("LeftButton")
	check(app.getItemShoppingQty(rowData) == 2, "Second Shift+LeftClick row increments to 2")
	boundFrame:Click("RightButton")
	check(app.getItemShoppingQty(rowData) == 1, "Shift+RightClick row decrements -1 (2 -> 1)")
	_G.IsShiftKeyDown = origIsShift
	ns.AllItems.SetShiftMode(false)
	MerchantMasterDB.shoppingList = {}
	ns.AllItems.RepaintShoppingQty()

	-- 5e. Deep Analysis round-trip from All Items row
	local okDA = app.openDeepAnalysis({ kind = "item", row = ssRow, itemID = 7912 })
	check(okDA == true and app.activeTab == "deep_analysis"
		and app._deepAnalysisReturn and app._deepAnalysisReturn.tab == "all_items",
		"Deep Analysis opens from All Items item row and records return tab = all_items")
	app.setTab("all_items")

	-- 5f. Performance budget verification (chunked cold build + fast warm refresh + targeted craft patch)
	local perfClock = os and os.clock
	local ciScale = (os and os.getenv and (os.getenv("CI") == "true" or os.getenv("GITHUB_ACTIONS") == "true")) and 2.5 or 1.0
	if perfClock then
		ns.AllItems.Invalidate()
		local origAfter = _G.C_Timer.After
		local q = {}
		_G.C_Timer.After = function(_, fn)
			if type(fn) == "function" then q[#q + 1] = fn end
		end
		local okPerf, errPerf = pcall(function()
			app.refresh()
			local batches, maxCbMs = 0, 0
			local guard = 0
			while #q > 0 and guard < 2000 do
				guard = guard + 1
				local cur = q
				q = {}
				for _, fn in ipairs(cur) do
					local t0 = perfClock()
					fn()
					local dt = (perfClock() - t0) * 1000
					batches = batches + 1
					if dt > maxCbMs then maxCbMs = dt end
				end
			end
			check(batches >= 10, "Cold async All Items load yields across multiple batches (" .. tostring(batches) .. ")")
			check(maxCbMs <= 25.0 * ciScale, string.format("Cold All Items max single callback %.3fms <= 25.0ms", maxCbMs))
		end)
		_G.C_Timer.After = origAfter
		if not okPerf then error(errPerf, 0) end

		local ctxWarm = app.buildAllItemsContext()
		local tWarm = perfClock()
		for _ = 1, 5 do
			ns.AllItems.Refresh(ctxWarm)
		end
		local avgWarmMs = ((perfClock() - tWarm) * 1000) / 5
		check(avgWarmMs <= 3.0 * ciScale, string.format("Warm All Items Refresh avg %.3fms <= 3.0ms", avgWarmMs))

		local tPatch = perfClock()
		local patched = ns.AllItems.PatchMeta(nil, { ids = { [7912] = true }, hasOwnership = true })
		local patchMs = (perfClock() - tPatch) * 1000
		check(patched == 1 and patchMs <= 5.0 * ciScale,
			string.format("Targeted craft PatchMeta patched=%d in %.3fms <= 5.0ms", patched, patchMs))
	end
end

print(string.format("OK: test_all_items (%d assertions)", host.assertions()))
