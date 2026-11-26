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
local MP = ns.MP
local papp = MP.app

local function stripColors(s)
	return tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function btnText(b)
	if not b then return "" end
	local t = b.GetText and b:GetText() or ""
	if t ~= "" then return stripColors(t) end
	return stripColors((b.fs and b.fs.GetText and b.fs:GetText()) or "")
end

local function setupProfScrollTable(tbl)
	if not (tbl and tbl.scrollBox) then return nil end
	local box = tbl.scrollBox
	local pool = {}
	local capacity = 40
	box._frames = pool
	box.GetHeight = function() return capacity * 34 end
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

setupProfScrollTable(papp.ui.pathTable)
setupProfScrollTable(papp.ui.browseTable)
setupProfScrollTable(app.ui.shopPanel.table)

local shiftHeld = false
_G.IsShiftKeyDown = function() return shiftHeld end

local function drainTimers()
	if hostEnv and hostEnv.drainTimers then
		hostEnv.drainTimers()
	elseif _G._mmFlushTimers then
		_G._mmFlushTimers()
	end
end

-- Seed deterministic synthetic Live AH prices so Professor solves 1->300 without external SnapshotData.lua
do
	local econ = ns.DetectActiveEconomy()
	MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
	local prices = { _scannedAt = time() - 60 }
	for id in pairs(ns.ALL_CATALOG_IDS or {}) do
		local base = (ns.VENDOR_SELL and ns.VENDOR_SELL[id]) or 100
		prices[id] = { price = math.max(50, math.min(300, base)), qty = 40, at = time() - 60 }
	end
	MerchantMasterDB.ahPrices[econ] = prices
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end

-- Clean queues & set deterministic Alchemy 1->300 state
app.clearUnifiedShoppingList()
local profDB = MP.GetDB()
profDB.selectedProf = "alchemy"
profDB.profTargets.alchemy = { from = 1, to = 300 }
profDB.charLevelMode = 60
profDB.overtimeMode = 0
profDB.recipeFilter = "trainer_vendor"
profDB.goalMode = "smart"
profDB.useOwned = false
papp.activeBracket = "all"

app.panel:Show()
app.setTab("prof_path")

-- 1. Verify inline Cheapest / Smart / Max Profit segmented control (Requirement 3)
local goalSeg = papp.ui.goalSeg
check(goalSeg ~= nil and goalSeg.frame:IsShown(), "Inline goalSeg (Cheapest / Smart / Max Profit) is visible on bracketBar")
check(goalSeg.buttons.cheapest and goalSeg.buttons.smart and goalSeg.buttons.ah_max, "All 3 goal buttons exist on goalSeg")

goalSeg.buttons.cheapest:Click("LeftButton")
check(profDB.goalMode == "cheapest", "Clicking Cheapest sets goalMode='cheapest'")
check(btnText(papp.ui.goalBtn):find("Cheapest", 1, true) ~= nil, "Sidebar goalBtn stays synced with Cheapest")

goalSeg.buttons.ah_max:Click("LeftButton")
check(profDB.goalMode == "ah_max", "Clicking Max Profit sets goalMode='ah_max'")

goalSeg.buttons.smart:Click("LeftButton")
check(profDB.goalMode == "smart", "Clicking Smart sets goalMode='smart'")

-- 2. Verify 75-150 Journeyman bracket filter updates top KPI cards & partitions cleanly (Requirement 6)
check(papp.ui.kpiStrip ~= nil and papp.ui.kpiStrip:IsShown(), "Compact KPI strip is visible in top sub-strip on prof_path")
for i = 1, 3 do
	check(math.floor((papp.ui.kpiCards[i]:GetHeight() or 0) + 0.5) == 24, "Compact KPI pill " .. i .. " is 24px tall")
end
local fullStats = {}
for k, v in pairs(papp.lastFilteredStats or {}) do fullStats[k] = v end
check(fullStats.stepCount > 0 and fullStats.totalCrafts > 0, "Full 1-300 stats populated")
check(stripColors(papp.ui.kpiCards[2].lbl:GetText()) == "Est. Leveling Cost", "Default Card 2 title is Est. Leveling Cost")
check(stripColors(papp.ui.kpiCards[3].lbl:GetText()) == "Steps Remaining", "Default Card 3 title is Steps Remaining")

local sumSteps, sumCrafts, sumGross, sumTrain, sumResale, sumNet = 0, 0, 0, 0, 0, 0
local bracketByKey = {}
for _, pill in ipairs(papp.ui.bracketPills or {}) do
	bracketByKey[pill.bracket.key] = pill
end

for _, bKey in ipairs({ "apprentice", "journeyman", "expert", "artisan" }) do
	bracketByKey[bKey]:Click("LeftButton")
	check(papp.activeBracket == bKey, "Activated bracket " .. bKey)
	local st = papp.lastFilteredStats
	local bd = bracketByKey[bKey].bracket
	check(stripColors(papp.ui.kpiCards[2].lbl:GetText()) == string.format("Est. Leveling Cost (%d-%d)", bd.lo, bd.hi),
		"Card 2 title reflects bracket " .. bKey)
	check(stripColors(papp.ui.kpiCards[3].lbl:GetText()) == string.format("Steps (%d-%d)", bd.lo, bd.hi),
		"Card 3 title reflects bracket " .. bKey)
	check(stripColors(papp.ui.kpiCards[3].val:GetText()) == string.format("%d Steps", st.stepCount),
		"Card 3 step count matches filtered steps for " .. bKey)
	check(stripColors(papp.ui.kpiCards[3].unit:GetText()) == string.format("(%d Crafts)", st.totalCrafts),
		"Card 3 craft count matches filtered crafts for " .. bKey)

	-- Ensure no boundary steps leak from adjacent brackets
	for _, row in ipairs(papp.lastVisiblePathSteps or {}) do
		local s1, s2 = row.s1 or 1, row.s2 or row.s1 or 1
		if s2 > s1 then
			check(s2 > bd.lo and s1 < bd.hi, string.format("Range step %d->%d strictly inside %d-%d", s1, s2, bd.lo, bd.hi))
		else
			check(s1 >= bd.lo and (s1 < bd.hi or (bd.hi == 300 and s1 == 300)),
				string.format("Point step at %d strictly inside %d-%d", s1, bd.lo, bd.hi))
		end
	end

	sumSteps = sumSteps + st.stepCount
	sumCrafts = sumCrafts + st.totalCrafts
	sumGross = sumGross + st.totalGrossMats
	sumTrain = sumTrain + st.totalTrainUnlocks
	sumResale = sumResale + st.totalResale
	sumNet = sumNet + (st.netCost or 0)
end

check(sumSteps == fullStats.stepCount, string.format("Bracket step counts sum to full 1-300 (%d == %d)", sumSteps, fullStats.stepCount))
check(sumCrafts == fullStats.totalCrafts, string.format("Bracket craft counts sum to full 1-300 (%d == %d)", sumCrafts, fullStats.totalCrafts))
check(sumGross == fullStats.totalGrossMats, "Bracket gross mats sum to full 1-300")
check(sumTrain == fullStats.totalTrainUnlocks, "Bracket train unlocks sum to full 1-300")
check(sumResale == fullStats.totalResale, "Bracket resale sums to full 1-300")
check(sumNet == (fullStats.netCost or 0), "Bracket net costs sum to full 1-300")

-- 3. Verify "+ Add 75-150 to Cart" and "+ Add All to Cart" overview button (Requirement 2)
bracketByKey.journeyman:Click("LeftButton")
check(btnText(papp.ui.pathAddCartBtn) == "+ Add 75-150 to Cart", "Overview button adapts to 75-150 filter")
local jmCraftableCount = 0
for _, st in ipairs(papp.lastVisiblePathSteps or {}) do
	if not st.isMilestone and st.srcType ~= "gather" then jmCraftableCount = jmCraftableCount + 1 end
end
check(jmCraftableCount > 0, "Journeyman has craftable steps")
papp.ui.pathAddCartBtn:Click("LeftButton")
drainTimers()
app.syncUnifiedShoppingList()
check(#(MerchantMasterDB.craftOrderQueue or {}) > 0 and #(MerchantMasterDB.craftOrderQueue or {}) <= jmCraftableCount,
	"Clicking + Add 75-150 to Cart queues only Journeyman recipes")

app.clearUnifiedShoppingList()
bracketByKey.all:Click("LeftButton")
check(btnText(papp.ui.pathAddCartBtn) == "+ Add All to Cart", "Overview button resets to + Add All to Cart on All (1-300)")

-- 4. Verify per-item "+ Cart" button replacing AH/Mats column (Requirement 1)
check(MP.PATH_COLS[9].label == "AH" and MP.PATH_COLS[10].label == "Vendor" and MP.PATH_COLS[11].label == "Sell",
	"Path columns 9-11 are AH, Vendor, and Sell")
check(MP.PATH_COLS[15].label == "+ Cart", "Column 15 header is '+ Cart'")
local firstCraftRowFrame = nil
papp.ui.pathTable.forEachRow(function(rf)
	if not firstCraftRowFrame and rf.data and not rf.data.isMilestone and rf.data.srcType ~= "gather" then
		firstCraftRowFrame = rf
	end
end)
check(firstCraftRowFrame ~= nil, "Found rendered craftable row frame on Leveling Path")
check(btnText(firstCraftRowFrame.cells[15]) == "+ Cart", "Unqueued row action button displays '+ Cart'")

local targetStep = firstCraftRowFrame.data
local expectedStepCrafts = math.max(1, tonumber(targetStep.crafts) or 1)
firstCraftRowFrame.cells[15]:Click("LeftButton")
drainTimers()
app.syncUnifiedShoppingList()
check(btnText(firstCraftRowFrame.cells[15]):find("Cart: ", 1, true) ~= nil, "Queued row action button displays 'Cart: <qty>'")
check(app.getRecipeShoppingQty({ spellID = targetStep.spellID, outputItemID = targetStep.itemID, prof = "alchemy" }) >= expectedStepCrafts,
	"Per-row + Cart queues step crafts into craftOrderQueue")

-- Right-click removes from cart
firstCraftRowFrame.cells[15]:Click("RightButton")
drainTimers()
check(app.getRecipeShoppingQty({ spellID = targetStep.spellID, outputItemID = targetStep.itemID, prof = "alchemy" }) == 0,
	"Right-clicking per-row Cart button removes step from cart")
check(btnText(firstCraftRowFrame.cells[15]) == "+ Cart", "Row button returns to '+ Cart' after removal")

-- Add entire 1-300 overview
local addedAll = papp.addOverviewToCart()
drainTimers()
app.syncUnifiedShoppingList()
local totalCartMain = #(MerchantMasterDB.craftOrderQueue or {}) + #(MerchantMasterDB.shoppingList or {})
check(addedAll > 1 and totalCartMain >= addedAll, "addOverviewToCart queues all 1-300 craft steps and scrolls")
check(btnText(firstCraftRowFrame.cells[15]):find("Cart: ", 1, true) ~= nil, "All craft rows update to 'Cart: <qty>' after overview add")

app.clearUnifiedShoppingList()

-- 5. Verify Shift Quick-Add Mode & manual +/- stepper (Requirement 4)
shiftHeld = true
papp.SetShiftMode(true)
check(papp.ui.pathShiftBadge == nil or papp.ui.pathShiftBadge:IsShown(), "Quick-Add Mode badge shown when Shift held")
check(firstCraftRowFrame.shiftStepper ~= nil and firstCraftRowFrame.shiftStepper:IsShown(), "Shift stepper shown on craftable row")
check(not firstCraftRowFrame.cells[15]:IsShown(), "Rightmost + Cart cell hidden beneath Shift stepper to prevent overlap")

-- Milestone row must NOT show a dead stepper when non-item trainer milestone
local trainerMilestoneFrame = nil
papp.ui.pathTable.forEachRow(function(rf)
	if not trainerMilestoneFrame and rf.data and rf.data.isMilestone and (rf.data.itemID or 0) <= 0 then
		trainerMilestoneFrame = rf
	end
end)
if trainerMilestoneFrame then
	check(not (trainerMilestoneFrame.shiftStepper and trainerMilestoneFrame.shiftStepper:IsShown()),
		"Trainer milestone row does not show Shift stepper")
end

firstCraftRowFrame.shiftStepper.plusBtn:Click("LeftButton")
check(firstCraftRowFrame.shiftStepper.qtyFs:GetText() == "1", "Stepper + LeftClick sets qty to 1")
firstCraftRowFrame.shiftStepper.plusBtn:Click("RightButton")
check(firstCraftRowFrame.shiftStepper.qtyFs:GetText() == "6", "Stepper + RightClick adds 5 -> 6")
firstCraftRowFrame.shiftStepper.minusBtn:Click("LeftButton")
check(firstCraftRowFrame.shiftStepper.qtyFs:GetText() == "5", "Stepper - LeftClick subtracts 1 -> 5")

-- Shift-clicking row directly adjusts +1 / -1 without opening Quick Look
local hudBefore = app.superListProvider.GetQuickLookFrame and app.superListProvider.GetQuickLookFrame()
firstCraftRowFrame:Click("LeftButton")
check(firstCraftRowFrame.shiftStepper.qtyFs:GetText() == "6", "Shift+LeftClick on row adds 1 -> 6")
check(not (hudBefore and hudBefore:IsShown()), "Shift+LeftClick does not open Quick Look")
firstCraftRowFrame:Click("RightButton")
check(firstCraftRowFrame.shiftStepper.qtyFs:GetText() == "5", "Shift+RightClick on row subtracts 1 -> 5")

firstCraftRowFrame.shiftStepper.minusBtn:Click("RightButton")
check(firstCraftRowFrame.shiftStepper.qtyFs:GetText() == "0", "Stepper - RightClick clears qty to 0")

shiftHeld = false
papp.SetShiftMode(false)
check(not firstCraftRowFrame.shiftStepper:IsShown() and firstCraftRowFrame.cells[15]:IsShown(),
	"Releasing Shift hides stepper and restores + Cart cell")

-- 6. Verify Left Mouse Click opens Quick View on both item & Enchanting recipes (Requirement 5)
firstCraftRowFrame:Click("LeftButton")
local hud = app.superListProvider.GetQuickLookFrame()
check(hud ~= nil and hud:IsShown(), "Left-clicking Professor step row opens Quick View HUD")
check(hud.data and hud.data.kind == "recipe", "Quick View HUD displays recipe kind")

-- Clicking "+ Add to Cart" inside Quick View updates Professor row immediately
hud.addButton:Click("LeftButton")
drainTimers()
check(btnText(firstCraftRowFrame.cells[15]) == "Cart: 1", "Quick View '+ Add to Cart' updates Professor row to 'Cart: 1'")

-- Left-clicking the same row again toggles Quick View closed
firstCraftRowFrame:Click("LeftButton")
check(not hud:IsShown(), "Left-clicking same Professor row toggles Quick View closed")

-- Switch to Enchanting (zero-output ItemID=0 spells) and verify Left-Click Quick View + Cart work cleanly
app.clearUnifiedShoppingList()
_G.MerchantProfessorAPI.SelectProfession("enchanting")
profDB.profTargets.enchanting = { from = 1, to = 300 }
app.refresh()

local enchRowFrame = nil
papp.ui.pathTable.forEachRow(function(rf)
	if not enchRowFrame and rf.data and not rf.data.isMilestone and (rf.data.itemID or 0) == 0 and (rf.data.spellID or 0) > 0 then
		enchRowFrame = rf
	end
end)
check(enchRowFrame ~= nil, "Found zero-output Enchanting spell row on Leveling Path")
enchRowFrame:Click("LeftButton")
hud = app.superListProvider.GetQuickLookFrame()
check(hud ~= nil and hud:IsShown(), "Left-clicking zero-output Enchanting row opens Quick View HUD")
enchRowFrame:Click("LeftButton")
check(not hud:IsShown(), "Left-clicking same Enchanting row closes Quick View HUD")

-- Verify Book Milestone (+ Cart on Cooking Expert Cookbook 16072)
_G.MerchantProfessorAPI.SelectProfession("cooking")
profDB.profTargets.cooking = { from = 1, to = 300 }
app.refresh()
local bookRowFrame = nil
papp.ui.pathTable.forEachRow(function(rf)
	if not bookRowFrame and rf.data and rf.data.isMilestone and (rf.data.itemID or 0) > 0 then
		bookRowFrame = rf
	end
end)
if bookRowFrame then
	check(btnText(bookRowFrame.cells[15]) == "+ Cart", "Book milestone shows '+ Cart'")
	bookRowFrame.cells[15]:Click("LeftButton")
	drainTimers()
	check(btnText(bookRowFrame.cells[15]) == "Cart: 1", "Clicking '+ Cart' on Expert Cookbook adds book to Shopping Cart")
	bookRowFrame.cells[15]:Click("RightButton")
	drainTimers()
	check(btnText(bookRowFrame.cells[15]) == "+ Cart", "Right-clicking Book milestone removes book from Shopping Cart")
end

app.setTab("prof_shop")
check(not papp.ui.kpiStrip:IsShown(), "Compact KPI strip hides on prof_shop")
app.setTab("prof_path")
check(papp.ui.kpiStrip:IsShown(), "Compact KPI strip re-shows on prof_path")
app.setTab("dashboard")
check(not papp.ui.kpiStrip:IsShown(), "Compact KPI strip hides when leaving Professor")

-- 7. Verify cleaned-up Filters & Tools layout + per-screen Filters icon button
do
	local toggles = {
		app.ui.ahCutCheck,
		app.ui.bisOnlyCheck,
		app.ui.knownRecipesCheck,
		app.ui.knownAllCharsCheck,
	}
	local prevY = nil
	for idx, cb in ipairs(toggles) do
		check(cb ~= nil and cb._points and cb._points[1], "Toggle #" .. idx .. " exists and is positioned")
		local pt = cb._points[1]
		local x, y = pt[2], pt[3]
		check(x == 12, "Toggle #" .. idx .. " aligned at x=12, got " .. tostring(x))
		if prevY then
			check(y < prevY - 14, "Toggle #" .. idx .. " stacks strictly below previous toggle (" .. tostring(y) .. " < " .. tostring(prevY) .. ")")
		end
		prevY = y
	end
	check(app.ui.sidebarOptionsBtn ~= nil and app.ui.sidebarOptionsBtn._points[1][1] == "BOTTOMLEFT",
		"Options button is pinned to bottom of Filters & Tools")
	check(app.ui.uiSkinBtn ~= nil and app.ui.uiSkinBtn._points[1][1] == "BOTTOMLEFT"
		and app.ui.uiSkinBtn._points[1][2] == app.ui.sidebarOptionsBtn,
		"UI Theme button sits at the bottom directly above Options")
	check(app.ui.sidebarShopCard == nil and app.ui.sidebarOpenListBtn == nil and app.ui.sidebarAucBtn == nil,
		"Removed basket card, Open List, and Auctionator buttons from Filters & Tools")
	check(app.ui.quickCalcBtn == nil or not app.ui.quickCalcBtn:IsShown(),
		"Legacy Calc quick-link button is hidden")

	local screenFilterBtns = {
		{ tab = "dashboard",     btn = app.ui.dashFiltersBtn,            hasProfs = true },
		{ tab = "profit_spread", btn = app.ui.spreadFiltersBtn,          hasProfs = true },
		{ tab = "outliers",      btn = app.ui.outliersFiltersBtn,        hasProfs = true },
		{ tab = "recipes",       btn = app.ui.recipesView and app.ui.recipesView.filtersButton, hasProfs = true },
		{ tab = "crates",        btn = app.ui.cratesFiltersBtn,          hasProfs = true },
		{ tab = "writs",         btn = app.ui.writsFiltersBtn,           hasProfs = true },
		{ tab = "forged",        btn = app.ui.forgedFiltersBtn,          hasProfs = true },
		{ tab = "rep",           btn = app.ui.repFiltersBtn,             hasProfs = true },
		{ tab = "prof_path",     btn = papp.ui.pathFiltersBtn,           hasProfs = false },
		{ tab = "prof_shop",     btn = papp.ui.shopFiltersBtn,           hasProfs = false },
		{ tab = "prof_browse",   btn = papp.ui.browseFiltersBtn,         hasProfs = false },
	}
	local pop = app.ui.sidebarOptionsHost
	for _, entry in ipairs(screenFilterBtns) do
		app.setTab(entry.tab)
		check(entry.btn ~= nil, "Filters button exists on tab " .. entry.tab)
		check(btnText(entry.btn) == "Filters", "Filters button label is 'Filters' on tab " .. entry.tab)
		entry.btn:Click("LeftButton")
		check(pop:IsShown() and pop._mode == "filters", "Clicking Filters opens popover in filters mode on " .. entry.tab)
		check(app.ui.sidebarPopHdr:GetText() == "FILTERS", "Popover header is 'FILTERS' on " .. entry.tab)
		check(not app.ui.ahCutCheck:IsShown() and not app.ui.uiSkinBtn:IsShown() and not app.ui.sidebarOptionsBtn:IsShown(),
			"Global tools hidden in Filters-only mode on " .. entry.tab)
		check(app.ui.profBtns.all:IsShown() == entry.hasProfs,
			"Professions grid visibility matches tab applicability on " .. entry.tab)
		entry.btn:Click("LeftButton")
		check(not pop:IsShown(), "Clicking Filters again toggles popover closed on " .. entry.tab)
	end

	-- Verify switching tabs closes open Filters popover
	app.setTab("prof_path")
	papp.ui.pathFiltersBtn:Click("LeftButton")
	check(pop:IsShown() and pop._mode == "filters", "Filters popover opens on prof_path")
	app.setTab("dashboard")
	check(not pop:IsShown(), "Switching tabs closes tab-anchored Filters popover")

	-- Verify top cogwheel (Settings & Tools) hides all filters and shrinks cleanly
	app.openSidebarPopover("tools", app.ui.sidebarOptionsBtn)
	check(pop:IsShown() and pop._mode == "tools", "Cogwheel opens popover in tools mode")
	check(app.ui.sidebarPopHdr:GetText() == "SETTINGS & TOOLS", "Cogwheel header is 'SETTINGS & TOOLS'")
	check(pop:GetHeight() == 292, "Cogwheel popover compacts to 292px without filters, got " .. tostring(pop:GetHeight()))
	check(app.ui.ahCutCheck:IsShown() and app.ui.priceFmtBtn:IsShown() and app.ui.uiSkinBtn:IsShown() and app.ui.sidebarOptionsBtn:IsShown(),
		"Cogwheel shows global settings and tools")
	check(not app.ui.profBtns.all:IsShown() and not app.ui.unlockBtn:IsShown() and not app.ui.dashScopeBtn:IsShown(),
		"Cogwheel hides profession grid, Show dropdown, and tab-specific filters")
	pop:Hide()

	-- Verify opening Filters or Cogwheel never triggers a full app.refresh() and stays instant (<50ms)
	app.setTab("recipes")
	local origRefresh = app.refresh
	local refreshCalls = 0
	app.refresh = function(...)
		refreshCalls = refreshCalls + 1
		return origRefresh(...)
	end
	local t0 = os.clock()
	app.ui.recipesView.filtersButton:Click("LeftButton")
	local filtersMs = (os.clock() - t0) * 1000
	app.ui.recipesView.filtersButton:Click("LeftButton")
	local t1 = os.clock()
	app.openSidebarPopover("tools", app.ui.sidebarOptionsBtn)
	local toolsMs = (os.clock() - t1) * 1000
	pop:Hide()
	app.refresh = origRefresh
	check(refreshCalls == 0, "Opening Filters and Cogwheel triggers 0 app.refresh() calls, got " .. tostring(refreshCalls))
	check(filtersMs < 50 and toolsMs < 50, string.format("Popover open stays instant (<50ms): filters=%.3fms tools=%.3fms", filtersMs, toolsMs))
	print(string.format("POPOVER_PERF filters_ms=%.3f tools_ms=%.3f refresh_calls=%d", filtersMs, toolsMs, refreshCalls))

	-- 8. Verify crafting with 1-300 Leveling open triggers 0 synchronous refreshes and defers until casting ends
	app.setTab("prof_path")
	local origCast = _G.UnitCastingInfo
	local origAfter = _G.C_Timer.After
	local queued = {}
	_G.C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
	local craftRefreshes = 0
	local savedRefresh = app.refresh
	app.refresh = function(...)
		craftRefreshes = craftRefreshes + 1
		return savedRefresh(...)
	end
	local function fireEvent(ev)
		for _, f in ipairs(frames) do
			if f._events and f._events[ev] and f._scripts and f._scripts.OnEvent then
				f._scripts.OnEvent(f, ev)
			end
		end
	end
	local function stepTimers()
		local batch = queued
		queued = {}
		for _, fn in ipairs(batch) do fn() end
	end
	_G.UnitCastingInfo = function() return "Rough Blasting Powder" end
	local tc0 = os.clock()
	fireEvent("TRADE_SKILL_UPDATE")
	fireEvent("TRADE_SKILL_UPDATE")
	fireEvent("SKILL_LINES_CHANGED")
	app.scheduleRecipeRefresh("bags")
	app.scheduleRecipeRefresh("skills")
	local craftEventMs = (os.clock() - tc0) * 1000
	check(craftRefreshes == 0, "Crafting events trigger 0 synchronous refreshes on prof_path, got " .. tostring(craftRefreshes))
	check(craftEventMs < 50, string.format("Crafting event storm stays instant (<50ms): %.3fms", craftEventMs))
	-- Drain one timer step while still casting -> must stay deferred (0 refreshes)
	stepTimers()
	check(craftRefreshes == 0, "Refresh stays deferred while player is still casting, got " .. tostring(craftRefreshes))
	-- Stop casting and drain timers -> exactly 1 coalesced refresh runs once idle
	_G.UnitCastingInfo = function() return nil end
	while #queued > 0 do stepTimers() end
	check(craftRefreshes == 1, "Exactly 1 coalesced refresh runs after crafting finishes, got " .. tostring(craftRefreshes))
	print(string.format("CRAFT_PROF_PERF event_ms=%.3f sync_refreshes=0 final_coalesced=%d", craftEventMs, craftRefreshes))
	_G.UnitCastingInfo = origCast
	_G.C_Timer.After = origAfter
	app.refresh = savedRefresh
end

-- 9. Engineering 1-75 Cheapest: Shopping Cart aligns with Leveling Route (no double-counting reused intermediates + exact mpR reagents)
do
	app.clearUnifiedShoppingList()
	profDB.selectedProf = "engineering"
	profDB.profTargets.engineering = { from = 1, to = 75 }
	profDB.goalMode = "cheapest"
	profDB.useOwned = false
	MerchantMasterDB.profFilter = "engineering"
	papp.activeBracket = "apprentice"
	app.setTab("prof_path")
	drainTimers()

	local pathRes = papp.lastPathResult
	check(pathRes ~= nil and #(pathRes.steps or {}) > 0, "Engineering 1-75 Cheapest route computed")

	-- Compute expected raw material buy totals from Professor's own shoppingList (non-scroll, buyQty > 0)
	local expectedRawByID = {}
	for _, it in ipairs(pathRes.shoppingList or {}) do
		if (it.buyQty or 0) > 0 and not (it.source and it.source:find("Scroll")) then
			expectedRawByID[it.itemID] = (expectedRawByID[it.itemID] or 0) + it.buyQty
		end
	end

	local added = papp.addOverviewToCart()
	drainTimers()
	check(added > 0, "addOverviewToCart added Engineering 1-75 steps")

	local shopRows, grandCost, _, meta = app.syncUnifiedShoppingList()
	check(#shopRows > 0, "Unified Shopping List populated for Engineering 1-75")

	-- Sum leaf buy quantities and cross-prof sub-craft quantities from the unified shopping list
	local actualBuyByID, actualCraftByID = {}, {}
	for _, r in ipairs((meta and meta.buyList) or {}) do
		if r.itemID and (r.qty or 0) > 0 then
			actualBuyByID[r.itemID] = (actualBuyByID[r.itemID] or 0) + r.qty
		end
	end
	for _, r in ipairs((meta and meta.craftQueue) or {}) do
		if r.itemID and (r.qty or 0) > 0 then
			actualCraftByID[r.itemID] = (actualCraftByID[r.itemID] or 0) + r.qty
		end
	end

	-- Verify Rough Stone (2835) is NOT double-counted and matches the leveling route exactly
	if expectedRawByID[2835] then
		check(actualBuyByID[2835] == expectedRawByID[2835],
			string.format("Rough Stone buy qty matches leveling route (%s == %s)", tostring(actualBuyByID[2835]), tostring(expectedRawByID[2835])))
	end
	for itemID, expQty in pairs(expectedRawByID) do
		local got = (actualBuyByID[itemID] or 0) + (actualCraftByID[itemID] or 0)
		check(got == expQty,
			string.format("Item %d total buy/sub-craft qty aligns with leveling route (%s == %s)", itemID, tostring(got), tostring(expQty)))
	end

	-- Verify reused intermediate sub-rows show Reused badge, qty=0, lineCost=0
	local reusedRowCount = 0
	for _, r in ipairs(shopRows) do
		if not r.isMainRow and (r.surplusUsed or 0) > 0 and (r.qty or 0) == 0 then
			reusedRowCount = reusedRowCount + 1
			check(tostring(r.action or ""):find("Reused (", 1, true) ~= nil,
				"Reused intermediate shows 'Reused (Nx)' action, got " .. tostring(r.action))
			check((r.lineCost or 0) == 0, "Reused intermediate has 0 lineCost")
		end
	end
	check(reusedRowCount > 0, "At least one reused intermediate row rendered with Reused badge in Engineering 1-75 cart")

	-- Verify removing Rough Blasting Powder (4357) from cart restores demand on downstream consumers
	local rbpQueueIdx = nil
	for idx, q in ipairs(MerchantMasterDB.craftOrderQueue or {}) do
		if q.outputItemID == 4357 then rbpQueueIdx = idx break end
	end
	if rbpQueueIdx then
		table.remove(MerchantMasterDB.craftOrderQueue, rbpQueueIdx)
		local afterRows = app.syncUnifiedShoppingList()
		local rbpDemandRestored = false
		for _, r in ipairs(afterRows) do
			if not r.isMainRow and r.itemID == 4357 and (r.qty or 0) > 0 then
				rbpDemandRestored = true
				break
			end
		end
		check(rbpDemandRestored, "Removing Rough Blasting Powder from cart restores downstream demand cleanly")
	end

	app.clearUnifiedShoppingList()
end

-- 10. Lock View button & "+ Add xxx to Cart" Lock Guide confirmation popup
do
	app.clearUnifiedShoppingList()
	papp.setViewLocked("engineering", false)
	papp.setViewLocked("alchemy", false)
	profDB.selectedProf = "engineering"
	profDB.profTargets.engineering = { from = 1, to = 75 }
	profDB.goalMode = "cheapest"
	MerchantMasterDB.profFilter = "engineering"
	papp.activeBracket = "apprentice"
	app.setTab("prof_path")
	drainTimers()

	check(papp.ui.pathLockBtn ~= nil, "Lock View button exists on pathHead")
	check(not papp.isViewLocked("engineering"), "Engineering starts unlocked")
	check(btnText(papp.ui.pathLockBtn) == "Lock View", "Unlocked button reads 'Lock View'")
	check(not (papp.ui.pathLockBadge and papp.ui.pathLockBadge:IsShown()), "Locked badge hidden when unlocked")

	local origSteps = papp.lastPathResult and papp.lastPathResult.steps or {}
	check(#origSteps > 0, "Engineering route has steps before locking")

	-- Clicking big "+ Add 1-75 to Cart" opens Lock Guide popup
	papp.ui.pathAddCartBtn:Click("LeftButton")
	drainTimers()
	local modal = papp.ui.lockPromptModal
	check(modal ~= nil and modal:IsShown(), "Clicking big + Add to Cart button opens Lock Guide popup")
	check(stripColors(modal.msgFs:GetText()) == "Do you want to lock the guide so crafts don't change on refresh?",
		"Lock Guide popup displays exact prompt question")

	-- Confirming "Lock Guide" locks Engineering and closes modal
	modal.lockBtn:Click("LeftButton")
	check(not modal:IsShown(), "Clicking Lock Guide hides popup")
	check(papp.isViewLocked("engineering"), "Engineering is now locked")
	check(btnText(papp.ui.pathLockBtn) == "Locked", "Locked button reads 'Locked'")
	check(papp.ui.pathLockBadge ~= nil and papp.ui.pathLockBadge:IsShown(), "Locked badge shown when locked")

	-- Refreshing with different AH prices / goal mode must NOT shift locked route
	local lockedRef = papp.lastPathResult
	profDB.goalMode = "ah_max"
	local solveCalls = 0
	local origSolve = MP.SolveProfessionPath
	MP.SolveProfessionPath = function(...)
		solveCalls = solveCalls + 1
		return origSolve(...)
	end
	app.refresh()
	MP.SolveProfessionPath = origSolve
	check(solveCalls == 0, "Locked view skips MP.SolveProfessionPath on refresh (got " .. tostring(solveCalls) .. ")")
	check(papp.lastPathResult == lockedRef, "Locked pathResult reference is preserved unchanged across refresh")

	-- Switching to Alchemy shows Alchemy unlocked; switching back to Engineering keeps Engineering locked
	profDB.selectedProf = "alchemy"
	MerchantMasterDB.profFilter = "alchemy"
	app.refresh()
	check(not papp.isViewLocked("alchemy"), "Lock is per-profession (Alchemy remains unlocked)")
	check(btnText(papp.ui.pathLockBtn) == "Lock View", "Button updates to 'Lock View' for unlocked Alchemy")

	profDB.selectedProf = "engineering"
	MerchantMasterDB.profFilter = "engineering"
	app.refresh()
	check(papp.isViewLocked("engineering"), "Engineering stays locked after switching professions")
	check(btnText(papp.ui.pathLockBtn) == "Locked", "Button returns to 'Locked' for Engineering")

	-- Clicking big + Add to Cart while already locked does NOT reopen popup
	app.clearUnifiedShoppingList()
	papp.ui.pathAddCartBtn:Click("LeftButton")
	drainTimers()
	check(not modal:IsShown(), "Popup does not re-open when guide is already locked")

	-- Clicking Lock button unlocks and resumes live recalculation
	papp.ui.pathLockBtn:Click("LeftButton")
	check(not papp.isViewLocked("engineering"), "Clicking Locked button unlocks Engineering")
	check(btnText(papp.ui.pathLockBtn) == "Lock View", "Button returns to 'Lock View' after unlocking")
	check(not (papp.ui.pathLockBadge and papp.ui.pathLockBadge:IsShown()), "Locked badge hidden after unlocking")

	app.clearUnifiedShoppingList()
end

-- 11. KPI Card 1 renamed to "Skill Filter" & Rank Training Milestones show Trainer Locations (0/75/150/225)
do
	check(stripColors(papp.ui.kpiCards[1].lbl:GetText()) == "Skill Filter",
		"KPI Card 1 title is 'Skill Filter', got " .. tostring(stripColors(papp.ui.kpiCards[1].lbl:GetText())))

	-- Verify MP.GetRankTrainerInfo covers all 9 ranked professions x 4 caps x both factions
	local rankedProfs = { "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "mining", "cooking", "firstaid" }
	for _, pk in ipairs(rankedProfs) do
		for _, cap in ipairs({ 75, 150, 225, 300 }) do
			for _, fac in ipairs({ "Alliance", "Horde" }) do
				local info = MP.GetRankTrainerInfo(pk, cap, fac)
				check(info ~= nil and type(info.short) == "string" and info.short ~= "" and type(info.detail) == "string" and info.detail ~= "",
					string.format("Trainer info present for %s cap %d (%s)", pk, cap, fac))
			end
		end
	end

	-- Verify Engineering 1-300 milestones include Expert (225) and Artisan (300) trainer locations in step name & metadata
	profDB.selectedProf = "engineering"
	profDB.profTargets.engineering = { from = 1, to = 300 }
	MerchantMasterDB.profFilter = "engineering"
	papp.activeBracket = "all"
	app.setTab("prof_path")
	drainTimers()

	local msByCap = {}
	for _, st in ipairs((papp.lastPathResult and papp.lastPathResult.steps) or {}) do
		if st.isMilestone and st.rankCap then
			msByCap[st.rankCap] = st
		end
	end
	check(msByCap[75] ~= nil and msByCap[75].name:find("Capital Cities", 1, true) ~= nil, "Engineering Apprentice milestone shows Capital Cities")
	check(msByCap[150] ~= nil and msByCap[150].name:find("Capital Cities", 1, true) ~= nil, "Engineering Journeyman milestone shows Capital Cities")
	check(msByCap[225] ~= nil and (msByCap[225].name:find("Orgrimmar", 1, true) ~= nil or msByCap[225].name:find("Ironforge", 1, true) ~= nil),
		"Engineering Expert milestone shows trainer city: " .. tostring(msByCap[225] and msByCap[225].name))
	check(msByCap[300] ~= nil and msByCap[300].name:find("Buzzek Bracketswing", 1, true) ~= nil and msByCap[300].name:find("Gadgetzan", 1, true) ~= nil,
		"Engineering Artisan milestone shows Buzzek Bracketswing, Gadgetzan: " .. tostring(msByCap[300] and msByCap[300].name))
end

-- 12. "Optimize for Me" button sets live skill as min filter, enables Use Owned Stock, unlocks, and refreshes
do
	check(papp.ui.pathOptimizeBtn ~= nil, "Optimize for Me button exists on pathHead")
	check(btnText(papp.ui.pathOptimizeBtn) == "Optimize for Me", "Button reads 'Optimize for Me'")

	profDB.selectedProf = "engineering"
	profDB.profTargets.engineering = { from = 1, to = 300 }
	profDB.useOwned = false
	MerchantMasterDB.profFilter = "engineering"
	papp.activeBracket = "apprentice"
	app.setTab("prof_path")
	drainTimers()
	papp.setViewLocked("engineering", true)
	check(papp.isViewLocked("engineering"), "Engineering locked prior to Optimize for Me")

	local origScan = MP.ScanPlayerProfessions
	MP.ScanPlayerProfessions = function()
		return { engineering = { learned = true, rank = 92, maxRank = 150 } }
	end
	papp.ui.pathOptimizeBtn:Click("LeftButton")
	drainTimers()
	MP.ScanPlayerProfessions = origScan

	check(profDB.profTargets.engineering.from == 92, "Optimize for Me sets skill filter start to live rank 92, got " .. tostring(profDB.profTargets.engineering.from))
	check(papp.ui.fromBox:GetText() == "92", "fromBox reflects live rank 92")
	check(profDB.useOwned == true, "Optimize for Me enables Use Owned Stock")
	check(papp.ui.ownedChk:GetChecked() == true, "ownedChk checkbox synced to checked")
	check(papp.activeBracket == "all", "Completed Apprentice bracket auto-switches to All when live skill is 92")
	check(not papp.isViewLocked("engineering"), "Optimize for Me unlocks locked view so route recomputes")
	check(papp.lastPathResult and papp.lastPathResult.startSkill == 92, "Recomputed path starts at skill 92")
end

-- 13. No auto-smelting without Mining & no 24h cooldown Transmute pricing in 1-300 Leveling
do
	-- Case A: Player has Engineering 225 + Alchemy 300, NO Mining
	local noMiningProfMap = { engineering = 225, alchemy = 300 }
	local smeltIronRec = nil
	for _, rec in ipairs(ns.RECIPES_BY_OUTPUT[3575] or {}) do
		if rec.prof == "mining" then smeltIronRec = rec break end
	end
	check(smeltIronRec ~= nil, "Found Smelt Iron recipe for Iron Bar (3575)")
	local sameP, canP = ns.GetRecipeCraftEligibility(smeltIronRec, noMiningProfMap, "engineering")
	check(sameP == false and canP == false, "Smelt Iron is NOT sameProf or craftable for Engineering without Mining")

	-- Shopping list for Iron Grenade (needs Iron Bar 3575) without Mining must default to Buy AH (not Smelt Iron Ore)
	local ironBarOpt = ns.GetItemCraftOption(3575, { parentProf = "engineering", profMap = noMiningProfMap, subCraftMode = "smart" })
	local ironRows = ns.BuildShoppingListRows({
		{ itemID = 3575, qty = 10, role = "Reagent", parentProf = "engineering" },
	}, { profMap = noMiningProfMap, subCraftMode = "smart" })
	local ironRow = ironRows and ironRows[1]
	check(ironRow ~= nil and ironRow.itemID == 3575 and ironRow.makeMyself == false,
		"Without Mining, Iron Bar defaults to Buy AH instead of auto-smelting Iron Ore")

	-- With Mining 225, Smelt Iron IS craftable
	local withMiningProfMap = { engineering = 225, mining = 225 }
	local _, canWithMining = ns.GetRecipeCraftEligibility(smeltIronRec, withMiningProfMap, "engineering")
	check(canWithMining == true, "With Mining 225, Smelt Iron is eligible for auto-smelt when cheaper")

	-- Gold Bar (3577) with Alchemy 300 (no Mining): Professor_Engine must NOT price Gold Power Core using 24h Transmute: Iron to Gold
	local origGetProfs = ns.GetPlayerProfessions
	ns.GetPlayerProfessions = function() return noMiningProfMap end
	local goldAH = ns.GetReagentUnitCost(3577)
	local gpcPath = MP.SolveProfessionPath("engineering", {
		startSkill = 150,
		targetSkill = 175,
		goalMode = "cheapest",
		subCraftMode = "smart",
		useOwned = false,
		liveProfs = { engineering = { learned = true, rank = 150, maxRank = 225 }, alchemy = { learned = true, rank = 300, maxRank = 300 } },
	})
	ns.GetPlayerProfessions = origGetProfs
	local gpcStep = nil
	for _, st in ipairs((gpcPath and gpcPath.steps) or {}) do
		if st.itemID == 10558 then gpcStep = st break end
	end
	if gpcStep and goldAH and goldAH > 0 then
		local goldRg = nil
		for _, rg in ipairs(gpcStep.reagentDetails or {}) do
			if rg.itemID == 3577 then goldRg = rg break end
		end
		check(goldRg ~= nil and goldRg.isSubCraft == false and goldRg.unitCost == goldAH,
			string.format("Gold Power Core prices Gold Bar at AH (%s) instead of 24h Transmute (%s)", tostring(goldAH), tostring(goldRg and goldRg.unitCost)))
	end
end

-- 11. Live WoW: Forever vendor sell/buy prices + Quick Look per-craft cost normalization
do
	-- 11a. Static catalog fallback reflects Nov 10, 2026 WoW: Forever Iron Grenade vendor nerf (500c -> 125c)
	check(ns.ITEM_VENDOR_SELL[4390] == 125 and MP.ITEM_INFO[4390].sell == 125,
		"Iron Grenade (4390) static fallback vendor sell updated to 125c (1s 25c)")

	-- 11b. Live C_Item.GetItemInfo overrides static MP.ITEM_INFO and ITEM_VENDOR_SELL (including 0c hotfixes)
	local origGetItemInfo = C_Item.GetItemInfo
	local origLiveSell = MerchantMasterDB.liveVendorSell
	local origInfoSell = MP.ITEM_INFO[4390].sell
	local origStaticSell = ns.ITEM_VENDOR_SELL[4390]
	MerchantMasterDB.liveVendorSell = {}
	MP.ITEM_INFO[4390].sell = 500
	ns.ITEM_VENDOR_SELL[4390] = 500

	C_Item.GetItemInfo = function(id)
		if id == 4390 then
			return "Iron Grenade", nil, 1, 35, 0, "Trade Goods", "Explosives", 10, "", 133709, 125, 7, 2, 0
		end
		return origGetItemInfo(id)
	end
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()
	check(ns.GetVendorSellPrice(4390) == 125, "ns.GetVendorSellPrice prefers live C_Item.GetItemInfo (125c) over TSM/static (500c)")
	check(MP.GetVendorSell(4390) == 125, "MP.GetVendorSell prefers live C_Item.GetItemInfo (125c) over stale MP.ITEM_INFO (500c)")
	check(MerchantMasterDB.liveVendorSell[4390] == 125, "Live C_Item.GetItemInfo persists observed WoW: Forever sell price into liveVendorSell")

	-- Simulate /reload before client caches item: persisted liveVendorSell still beats stale TSM & static 500c
	C_Item.GetItemInfo = function(id)
		if id == 4390 then return nil end
		return origGetItemInfo(id)
	end
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()
	check(ns.GetVendorSellPrice(4390) == 125 and MP.GetVendorSell(4390) == 125,
		"Persisted liveVendorSell (125c) beats stale TSM/static (500c) before async item load completes")

	-- Live 0c vendor price (unsellable hotfix) is honored as 0, never overwritten by stale 500c
	C_Item.GetItemInfo = function(id)
		if id == 4390 then
			return "Iron Grenade", nil, 1, 35, 0, "Trade Goods", "Explosives", 10, "", 133709, 0, 7, 2, 0
		end
		return origGetItemInfo(id)
	end
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()
	check(ns.GetVendorSellPrice(4390) == 0 and MP.GetVendorSell(4390) == 0,
		"Live 0c vendor sell price is respected instead of falling back to stale 500c")

	-- GET_ITEM_INFO_RECEIVED refreshes liveVendorSell and clears stale uiPriceBank.vendorSell entry
	local bank = app.getUIPriceBank()
	bank.vendorSell[4390] = 500
	C_Item.GetItemInfo = function(id)
		if id == 4390 then
			return "Iron Grenade", nil, 1, 35, 0, "Trade Goods", "Explosives", 10, "", 133709, 125, 7, 2, 0
		end
		return origGetItemInfo(id)
	end
	for _, fr in ipairs(frames) do
		if fr._events and fr._events.GET_ITEM_INFO_RECEIVED and fr._scripts and fr._scripts.OnEvent then
			fr._scripts.OnEvent(fr, "GET_ITEM_INFO_RECEIVED", 4390, true)
		end
	end
	check(MerchantMasterDB.liveVendorSell[4390] == 125 and bank.vendorSell[4390] == nil,
		"GET_ITEM_INFO_RECEIVED syncs live WoW: Forever vendor sell (125c) and clears stale uiPriceBank.vendorSell")

	-- Restore sell mocks
	C_Item.GetItemInfo = origGetItemInfo
	MerchantMasterDB.liveVendorSell = origLiveSell
	MP.ITEM_INFO[4390].sell = origInfoSell
	ns.ITEM_VENDOR_SELL[4390] = origStaticSell
	ns.ResetEval()
	ns.InvalidatePriceCache()

	-- 11c. Live MERCHANT_SHOW vendor buy capture (unlimited reagents, limited scrolls, skip Favor/extended cost)
	local origNumItems = _G.GetMerchantNumItems
	local origMerchInfo = _G.GetMerchantItemInfo
	local origMerchLink = _G.GetMerchantItemLink
	local origMerchAPI = _G.C_MerchantFrame
	local origLiveBuy = MerchantMasterDB.liveVendorBuy
	local origLiveBuyGlob = MerchantMasterDB.liveVendorBuyGlobal
	MerchantMasterDB.liveVendorBuy = {}
	MerchantMasterDB.liveVendorBuyGlobal = {}
	_G.C_MerchantFrame = nil
	local mockShop = {
		{ id = 2320, price = 40, stack = 5, avail = -1, ext = false },   -- Coarse Thread: 8c/unit unlimited
		{ id = 3575, price = 100, stack = 1, avail = 1, ext = false },   -- Iron Bar: limited stock (1) -> must NOT spoof infinite reagent
		{ id = 16041, price = 18000, stack = 1, avail = 1, ext = false },-- Limited vendor schematic -> allowed for recipe scroll buy
		{ id = 2321, price = 999, stack = 1, avail = -1, ext = true },   -- Extended/Favor item -> must be skipped
	}
	_G.GetMerchantNumItems = function() return #mockShop end
	_G.GetMerchantItemInfo = function(slot)
		local m = mockShop[slot]
		return "Item", 134400, m.price, m.stack, m.avail, true, true, m.ext
	end
	_G.GetMerchantItemLink = function(slot) return "|cffffffff|Hitem:" .. tostring(mockShop[slot].id) .. "::::::::60:::::|h[Item]|h|r" end
	local capturedCount = ns.CaptureMerchantVendorPrices()
	check(capturedCount == 3, "CaptureMerchantVendorPrices captures 3 copper items and skips extended/Favor item (got " .. tostring(capturedCount) .. ")")
	local threadPrice, threadLive = ns.GetVendorBuyPrice(2320, 10, false)
	check(threadPrice == 8 and threadLive == true, "Live unlimited merchant unit price (40c / 5 = 8c) overrides static 10c")
	local limReagPrice = ns.GetVendorBuyPrice(3575, nil, false)
	check(limReagPrice == nil, "Limited-stock non-vendor item (Iron Bar, avail=1) does NOT spoof infinite vendor reagent price")
	local limScrollPrice, limScrollLive = ns.GetRecipeVendorBuyPrice(16041, 20000)
	check(limScrollPrice == 18000 and limScrollLive == true, "Limited-stock vendor schematic (avail=1) uses live observed 1g 80s price")
	local skipExtPrice, skipExtLive = ns.GetVendorBuyPrice(2321, 100, false)
	check(skipExtPrice == 100 and skipExtLive == false, "Extended-cost/Favor merchant entry does not overwrite copper vendor buy price")

	-- Restore merchant mocks
	_G.GetMerchantNumItems = origNumItems
	_G.GetMerchantItemInfo = origMerchInfo
	_G.GetMerchantItemLink = origMerchLink
	_G.C_MerchantFrame = origMerchAPI
	MerchantMasterDB.liveVendorBuy = origLiveBuy
	MerchantMasterDB.liveVendorBuyGlobal = origLiveBuyGlob
	ns.ResetEval()
	ns.InvalidatePriceCache()

	-- 11d. Quick Look buildRecipeQuickLookRow must NOT triple-count Professor per-craft grossPerCraft/profitCraft or mutate Browse row
	local igRec = nil
	for _, r in ipairs(ns.RECIPES) do
		if r.outputItemID == 4390 then igRec = r break end
	end
	check(igRec ~= nil and (igRec.numMade or 1) == 3, "Found Iron Grenade recipe (numMade=3)")
	local browseRow = {
		prof = "engineering",
		spellID = igRec.spellID,
		itemID = 4390,
		name = "Iron Grenade",
		craftCost = 875,
		profitCraft = -420,
		ev = { grossPerCraft = 875, ahGrossUnit = 160, vendorUnit = 125 },
	}
	local qlRow = app.buildRecipeQuickLookRow(browseRow)
	check(qlRow ~= nil and qlRow ~= browseRow, "buildRecipeQuickLookRow returns clean view copy without mutating source row")
	check(browseRow.craftCost == 875, "Original Professor Browse row craftCost (875c per craft) remains unmutated")
	local qlCraftPer3 = qlRow.craftCost and math.floor(qlRow.craftCost * 3 + 0.5) or nil
	check(qlCraftPer3 ~= nil and qlCraftPer3 < 1500,
		"Quick Look Craft cost (3x) is per-craft (~8s 75c), NOT triple-counted 26s 25c (got " .. tostring(qlCraftPer3) .. ")")
	local pathStep = {
		prof = "engineering",
		spellID = igRec.spellID,
		itemID = 4390,
		name = "Iron Grenade",
		ev = { grossPerCraft = 875, ahGrossUnit = 160, vendorUnit = 125 },
	}
	local qlPath = app.buildRecipeQuickLookRow(pathStep)
	local qlPathPer3 = qlPath and qlPath.craftCost and math.floor(qlPath.craftCost * 3 + 0.5) or nil
	check(qlPath ~= nil and qlPathPer3 ~= nil and qlPathPer3 < 1500 and pathStep.craftCost == nil,
		"Path step Quick Look normalizes ev.grossPerCraft to per-unit without mutating stepObj (3x=" .. tostring(qlPathPer3) .. ")")
end

-- 12. Persisted Lock across /reload, Reset Filters unlock, AH/Vendor/Sell Browse & Path columns,
--     Bracket-aware Auctionator/Buyer dispatch & Live Color Clamping
do
	-- 12a. Browse 14-col AH, Vendor, Sell layout & unlisted AH '-'
	check(MP.BROWSE_COLS[8].label == "AH" and MP.BROWSE_COLS[9].label == "Vendor" and MP.BROWSE_COLS[10].label == "Sell",
		"Browse columns 8-10 are AH, Vendor, and Sell")
	MerchantMasterDB.profFilter = "alchemy"
	_G.MerchantProfessorAPI.SelectProfession("alchemy")
	app.setTab("prof_path")
	papp.resetFilters()
	papp.sortState.browse = { col = "req", asc = true }
	MP.GetDB().recipeFilter = "trainer_vendor"
	local testAlchID = nil
	for _, r in ipairs(MP.RECIPES.alchemy or {}) do
		if (r.i or 0) > 0 and not r.ench and not r.bop then testAlchID = r.i break end
	end
	check(testAlchID ~= nil, "Found tradeable Alchemy output item for Browse test")
	app.setTab("prof_browse")
	local origMkt = ns.GetItemMarketPrice
	local origList = ns.GetNumListed
	ns.GetItemMarketPrice = function(id)
		if id == testAlchID then return nil, nil end
		return origMkt(id)
	end
	ns.GetNumListed = function(id)
		if id == testAlchID then return 0 end
		return origList(id)
	end
	app.refresh()
	local targetRowData = nil
	for _, r in ipairs(papp.lastBrowseRows or {}) do
		if r.itemID == testAlchID then targetRowData = r break end
	end
	check(targetRowData ~= nil and targetRowData.ahUnit == nil,
		"Unlisted Alchemy item in Browse model sets ahUnit == nil (id=" .. tostring(testAlchID) .. ", rows=" .. tostring(#(papp.lastBrowseRows or {})) .. ")")
	papp.ui.browseTable.setRows({ targetRowData })
	local minorRow = nil
	papp.ui.browseTable.forEachRow(function(rf)
		if rf.data and rf.data.itemID == testAlchID then minorRow = rf end
	end)
	check(minorRow ~= nil, "Found rendered unlisted Alchemy row in browseTable")
	check(stripColors(minorRow.cells[8]:GetText()) == "-", "Unlisted Browse item shows '-' in AH column")
	ns.GetItemMarketPrice = origMkt
	ns.GetNumListed = origList

	-- 12b. Persisted Lock across /reload & Reset Filters unlock (preserving Option A useOwned = false)
	app.setTab("prof_path")
	_G.MerchantProfessorAPI.SelectProfession("alchemy")
	app.refresh()
	papp.setViewLocked("alchemy", true)
	check(papp.isViewLocked("alchemy"), "Alchemy route locked cleanly")
	-- Simulate /reload wiping runtime memory
	papp.lockedRoutes = {}
	app.refresh()
	check(papp.isViewLocked("alchemy") and papp.getLockedSnapshot("alchemy") ~= nil,
		"Lock state rehydrates across simulated /reload from lockedRoutesByChar")
	check(btnText(papp.ui.pathLockBtn) == "Locked", "Lock button shows 'Locked' after rehydration")

	papp.resetFilters()
	check(not papp.isViewLocked("alchemy"), "Reset Filters unlocks active locked profession")
	check(MP.GetDB().useOwned == false, "Option A: Reset Filters leaves db.useOwned == false")

	-- 12c. Bracket-aware sendShoppingToBuyer
	local capturedTitle, capturedRows = nil, nil
	local origOpenBuyer = app.openCartBuyer
	app.openCartBuyer = function(rows, title)
		capturedRows, capturedTitle = rows, title
		return true
	end
	app.refresh()
	papp.activeBracket = "apprentice" -- 1-75
	local okApp = papp.sendShoppingToBuyer()
	local countApp = capturedRows and #capturedRows or 0
	papp.activeBracket = "all"
	local okAll = papp.sendShoppingToBuyer()
	local countAll = capturedRows and #capturedRows or 0
	app.openCartBuyer = origOpenBuyer
	check(okAll and countAll >= countApp and (okApp or countApp == 0),
		string.format("Bracket-aware shopping send respects active bracket (1-75=%d <= all=%d)", countApp, countAll))

	-- 12d. Live TradeSkill scan records color clamping
	local tsRec = MP.RECIPES.alchemy and MP.RECIPES.alchemy[1]
	check(tsRec ~= nil and tsRec.s ~= nil, "Found sample Alchemy recipe for live scan test")
	local origNumTS, origInfoTS, origLineTS = _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillLine
	local origPlayerProfs, origModernTS = ns.GetPlayerProfessions, _G.C_TradeSkillUI
	ns.GetPlayerProfessions = function() return { alchemy = 120 } end
	_G.C_TradeSkillUI = nil
	_G.GetTradeSkillLine = function() return "Alchemy", 120 end
	_G.GetNumTradeSkills = function() return 1 end
	_G.GetTradeSkillInfo = function() return tsRec.n, "trivial" end
	papp.cacheOpenTradeSkills()
	_G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillLine = origNumTS, origInfoTS, origLineTS
	ns.GetPlayerProfessions, _G.C_TradeSkillUI = origPlayerProfs, origModernTS
	local pdb2 = MP.GetDB()
	check(pdb2.liveThresholds and pdb2.liveThresholds[tsRec.s] and (pdb2.liveThresholds[tsRec.s].maxGr or 999) <= 120,
		"cacheOpenTradeSkills records live color bounds via MP.RecordLiveRecipeColor")
	if pdb2.liveThresholds then pdb2.liveThresholds[tsRec.s] = nil end
end

print(string.format("PASS: Professor UX suite (%d assertions, 0 failures)", n))
