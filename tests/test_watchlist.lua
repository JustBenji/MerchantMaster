-- Offline Lua 5.1 verification suite for Feature G: Watchlist (UI_Watchlist.lua)
local ns, _, host = dofile("host_fixture.lua")
local check = host.check

if not ns.Watchlist then
	local chunk = assert(loadfile(host.addonDir .. "UI_Watchlist.lua"))
	chunk("MerchantMaster", ns)
end

local W = ns.Watchlist
local app = ns.app
local Theme = ns.Theme

local function approx(a, b, eps)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 0.005)
end

local function stripColor(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- 1. Exports & NormalizeKey
check(type(W) == "table", "ns.Watchlist exported")
for _, fn in ipairs({
	"NormalizeKey", "Toggle", "Add", "Remove", "IsFavorite", "IsWatched",
	"FindFavoriteForItem", "GetEntries", "GetCount", "GetVersion",
	"RegisterListener", "EvaluateRows", "GetRows", "GetFilteredRows",
	"FilterSort", "Create", "Refresh", "Layout", "SetShiftMode",
	"CloseHeatPopover", "GetSidebarControls", "GetColumnConfig",
	"SetColumnVisible", "MoveColumn", "ResetColumns", "ToggleColumnSettings",
}) do
	check(type(W[fn]) == "function", "ns.Watchlist." .. fn .. " exported")
end

check(W.NormalizeKey({ kind = "recipe", spellID = 2657, outputItemID = 2840 }) == "recipe:2657",
	"NormalizeKey prefers recipe:<spellID> for recipe tables")
check(W.NormalizeKey({ kind = "recipe", outputItemID = 2840 }) == "item:2840",
	"NormalizeKey falls back to item:<outputItemID> when spellID missing")
check(W.NormalizeKey({ kind = "item", itemID = 4304 }) == "item:4304",
	"NormalizeKey returns item:<itemID> for standalone item tables")
check(W.NormalizeKey(4304) == "item:4304", "NormalizeKey normalizes bare number to item:<id>")
check(W.NormalizeKey("4304") == "item:4304", "NormalizeKey normalizes numeric string to item:<id>")
check(W.NormalizeKey("recipe:2657") == "recipe:2657", "NormalizeKey preserves recipe:<id> string")
check(W.NormalizeKey("item:7912") == "item:7912", "NormalizeKey preserves item:<id> string")
check(W.NormalizeKey(nil) == nil and W.NormalizeKey("") == nil, "NormalizeKey returns nil for empty targets")

-- Safe behavior when MerchantMasterDB is temporarily nil
do
	local savedDB = _G.MerchantMasterDB
	_G.MerchantMasterDB = nil
	local okNil, errNil = pcall(function()
		check(W.GetCount() == 0, "GetCount safe when MerchantMasterDB is nil")
		W.Add(4304)
		check(W.IsFavorite(4304) == true, "Fallback store works when MerchantMasterDB is nil")
		W.Remove(4304)
		check(W.GetCount() == 0, "Fallback store remove works cleanly")
	end)
	_G.MerchantMasterDB = savedDB
	check(okNil, "Watchlist must be safe when MerchantMasterDB is nil: " .. tostring(errNil))
end

-- 2. Find two real recipes from ns.RECIPES (one we will make profitable, one unprofitable)
local profRecipe, lossRecipe
for _, r in ipairs(ns.RECIPES or {}) do
	if type(r) == "table" and r.spellID and r.spellID > 0 and r.outputItemID and r.outputItemID > 0
		and not r.isEnchant and type(r.reagents) == "table" and #r.reagents > 0
		and (r.numMade or 1) == 1 then
		local canTrade = not ns.IsItemSellable or ns.IsItemSellable(r.outputItemID, r.sellable, r.isEnchant)
		if canTrade then
			local firstRg = r.reagents[1]
			local rgID = firstRg and (firstRg[1] or firstRg.itemID or firstRg.id)
			if rgID and rgID ~= r.outputItemID and rgID ~= 4304 and rgID ~= 7912 then
				if not profRecipe then
					profRecipe = r
				elseif not lossRecipe and r.outputItemID ~= profRecipe.outputItemID then
					lossRecipe = r
					break
				end
			end
		end
	end
end
check(profRecipe ~= nil and lossRecipe ~= nil, "Found two tradeable test recipes in ns.RECIPES")

-- 3. Persistence, Toggle, IsFavorite, FindFavoriteForItem & RegisterListener notifications
W.Clear()
local events = {}
local unreg = W.RegisterListener(function(ev, key, entry)
	events[#events + 1] = { ev = ev, key = key, entry = entry }
end)
local v0 = W.GetVersion()

local fav1, k1 = W.Toggle({ kind = "item", itemID = 4304 }) -- Thick Leather
check(fav1 == true and k1 == "item:4304", "Toggle adds Thick Leather (4304)")
check(W.IsFavorite(4304) == true and W.IsWatched({ kind = "item", itemID = 4304 }) == true,
	"IsFavorite and IsWatched return true for favorited item")
check(W.GetCount() == 1 and W.GetVersion() == v0 + 1, "Count=1 and version incremented")
check(type(MerchantMasterDB.watchlist) == "table" and MerchantMasterDB.watchlist.version == 1
	and type(MerchantMasterDB.watchlist.items["item:4304"]) == "table",
	"Persisted in MerchantMasterDB.watchlist = { version = 1, items = { ... } }")
check(#events == 1 and events[1].ev == "add" and events[1].key == "item:4304",
	"Listener notified on Add")

local favRec, kRec = W.Toggle({ kind = "recipe", recipe = profRecipe })
check(favRec == true and kRec == ("recipe:" .. tostring(profRecipe.spellID)),
	"Toggle adds recipe by spellID")
local foundItem, foundItemKey = W.FindFavoriteForItem(4304)
check(foundItem ~= nil and foundItemKey == "item:4304", "FindFavoriteForItem finds standalone item 4304")
local foundRec, foundRecKey = W.FindFavoriteForItem(profRecipe.outputItemID)
check(foundRec ~= nil and foundRecKey == kRec,
	"FindFavoriteForItem finds favorited recipe via its outputItemID")

local favOff = W.Toggle(4304)
check(favOff == false and W.IsFavorite(4304) == false and W.GetCount() == 1,
	"Second Toggle removes Thick Leather cleanly")
check(#events == 3 and events[3].ev == "remove" and events[3].key == "item:4304",
	"Listener notified on Remove")

unreg()
W.Add(4304)
check(#events == 3, "Unregistered listener receives no further notifications")

-- 4. Mixed Recipe + Standalone Item Evaluation, 7d Trend, and nil-last Sorting
MerchantMasterDB.enableLegacyPriceAddons = false
W.Clear()
W.Add({ kind = "recipe", recipe = profRecipe })
W.Add({ kind = "recipe", recipe = lossRecipe })
W.Add({ kind = "item", itemID = 4304 }) -- Thick Leather (standalone item)
W.Add({ kind = "item", itemID = 7912 }) -- Solid Stone (standalone item)
check(W.GetCount() == 4, "Watchlist seeded with 2 recipes + 2 standalone items")

-- Configure deterministic prices & 7d baselines via synthetic snapshot + MarketScan trend override
local snapItems = {
	[4304] = { minBuyout = 780,  marketValue = 1000, historical = 1000, qty = 45, dailySold = 18.5 }, -- -22% price drop
	[7912] = { minBuyout = 960,  marketValue = 1000, historical = 1000, qty = 80, dailySold = 12.0 }, -- -4% minor dip
	[profRecipe.outputItemID] = { minBuyout = 50000, marketValue = 45000, historical = 45000, qty = 6, dailySold = 3.5 }, -- +11.1%
	[lossRecipe.outputItemID] = { minBuyout = 1000,  marketValue = 1400,  historical = 1400,  qty = 14, dailySold = 2.0 }, -- -28.6% price drop
}
for _, rg in ipairs(profRecipe.reagents or {}) do
	local rid = rg[1] or rg.itemID or rg.id
	if rid and not snapItems[rid] then
		snapItems[rid] = { minBuyout = 500, marketValue = 500, historical = 500, qty = 100, dailySold = 20 }
	end
end
for _, rg in ipairs(lossRecipe.reagents or {}) do
	local rid = rg[1] or rg.itemID or rg.id
	if rid and not snapItems[rid] then
		snapItems[rid] = { minBuyout = 10000, marketValue = 10000, historical = 10000, qty = 30, dailySold = 5 }
	end
end

host.loadSyntheticSnapshots({ items = snapItems })
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local evalRows = W.EvaluateRows(app.buildSuperListContext and app.buildSuperListContext() or { db = MerchantMasterDB })
check(type(evalRows) == "table" and #evalRows == 4, "EvaluateRows returns all 4 watched entries, got " .. tostring(#evalRows))

local byKey = {}
for _, r in ipairs(evalRows) do byKey[r.key] = r end

local tlRow = byKey["item:4304"]
local ssRow = byKey["item:7912"]
local profRow = byKey["recipe:" .. tostring(profRecipe.spellID)]
local lossRow = byKey["recipe:" .. tostring(lossRecipe.spellID)]

check(tlRow ~= nil and tlRow.kind == "item" and tlRow.kindLabel == "Item",
	"Thick Leather evaluated as standalone Item")
check(tlRow.craftCost == nil and tlRow.profit == nil and tlRow.marginPct == nil and tlRow.knownSort == nil,
	"Standalone Thick Leather has craftCost=nil, profit=nil, marginPct=nil, knownSort=nil")
check(tlRow.unitAH == 780 and tlRow.listed == 45,
	string.format("Thick Leather carries live snapshot AH price & qty (unitAH=%s, listed=%s)",
		tostring(tlRow.unitAH), tostring(tlRow.listed)))
check(type(tlRow.trendPct) == "number" and approx(tlRow.trendPct, -22.0, 0.2),
	"Thick Leather 7d trend reflects -22% drop, got " .. tostring(tlRow.trendPct))

check(ssRow ~= nil and ssRow.kind == "item" and ssRow.craftCost == nil and ssRow.profit == nil,
	"Solid Stone evaluated as standalone item with nil craft metrics")
check(type(ssRow.trendPct) == "number" and approx(ssRow.trendPct, -4.0, 0.2),
	"Solid Stone 7d trend reflects -4% dip, got " .. tostring(ssRow.trendPct))

check(profRow ~= nil and profRow.kind == "recipe" and type(profRow.craftCost) == "number"
	and type(profRow.profit) == "number" and profRow.profit > 0
	and type(profRow.marginPct) == "number" and profRow.marginPct > 0
	and (profRow.knownSort == 0 or profRow.knownSort == 1),
	string.format("Profitable recipe evaluated cleanly (craftCost=%s, profit=%s, margin=%s, known=%s)",
		tostring(profRow and profRow.craftCost), tostring(profRow and profRow.profit),
		tostring(profRow and profRow.marginPct), tostring(profRow and profRow.knownSort)))
check(type(profRow.trendPct) == "number" and profRow.trendPct > 0,
	"Profitable recipe shows positive 7d trend, got " .. tostring(profRow.trendPct))

check(lossRow ~= nil and lossRow.kind == "recipe" and type(lossRow.craftCost) == "number"
	and type(lossRow.profit) == "number" and lossRow.profit < 0,
	string.format("Unprofitable recipe evaluated cleanly (craftCost=%s, profit=%s)",
		tostring(lossRow and lossRow.craftCost), tostring(lossRow and lossRow.profit)))
check(type(lossRow.trendPct) == "number" and lossRow.trendPct <= -10,
	"Unprofitable recipe shows >=10% price drop, got " .. tostring(lossRow.trendPct))

-- 5. Verify nil-last numeric sorting in BOTH ascending & descending!
for _, colKey in ipairs({ "craftCost", "profit", "marginPct", "knownSort" }) do
	for _, asc in ipairs({ true, false }) do
		local sorted = W.FilterSort(evalRows, { filter = "all" }, { key = colKey, ascending = asc })
		check(#sorted == 4, "Sort preserves all 4 rows for " .. colKey)
		-- First 2 rows must be the recipes (non-nil), last 2 rows must be standalone items (nil)
		check(sorted[1][colKey] ~= nil and sorted[2][colKey] ~= nil,
			string.format("Non-nil values come first for %s (asc=%s)", colKey, tostring(asc)))
		check(sorted[3][colKey] == nil and sorted[4][colKey] == nil,
			string.format("Nil values pushed to bottom for %s (asc=%s)", colKey, tostring(asc)))
		if asc then
			check(sorted[1][colKey] <= sorted[2][colKey], "Ascending order holds for " .. colKey)
		else
			check(sorted[1][colKey] >= sorted[2][colKey], "Descending order holds for " .. colKey)
		end
	end
end

-- 6. Mount Watchlist UI View, verify Chrome, Filter Pills, Star Removal, Interactions & Theme Sweep
local qlCalls, daCalls, shopCalls = {}, {}, {}
local sortState = { col = "profit", asc = false }

local function testApplyRowHighlight(r)
	local p = Theme.PALETTE
	r.stripe = r:CreateTexture(nil, "BACKGROUND")
	r.stripe:SetAllPoints()
	r.sep = r:CreateTexture(nil, "BORDER")
	r.sep:SetPoint("BOTTOMLEFT", 16, 0)
	r.sep:SetPoint("BOTTOMRIGHT", -16, 0)
	r.sep:SetHeight(1)
	local sc = (p and (p.glassSep or p.separator)) or { 1, 1, 1, 0.08 }
	r.sep:SetColorTexture(sc[1], sc[2], sc[3], sc[4] or 0.08)
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	local hc = p and p.glassHover or { 1, 1, 1, 0.06 }
	r.hl:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.06)
	-- Register harsh sep callback on r to test the RegisterWidget callback race fix!
	Theme.RegisterWidget(r, function()
		local pal = Theme.PALETTE
		local nsc = pal and (pal.glassSep or pal.separator)
		if r.sep and nsc then
			r.sep:SetColorTexture(nsc[1], nsc[2], nsc[3], nsc[4] or 0.08)
		end
	end)
end

local hostContainer = CreateFrame("Frame", "TestWatchlistHost", app.panel)
hostContainer:SetSize(1040, 620)
hostContainer:Show()

local wlCtx = {
	theme = Theme,
	parent = hostContainer,
	db = MerchantMasterDB,
	rowHeight = 22,
	isActive = function() return hostContainer:IsShown() end,
	getSort = function() return sortState end,
	applyRowHighlight = testApplyRowHighlight,
	openQuickLook = function(kind, row, opts)
		qlCalls[#qlCalls + 1] = { kind = kind, row = row, opts = opts }
		return true
	end,
	openDeepAnalysis = function(spec, ret)
		daCalls[#daCalls + 1] = { spec = spec, ret = ret }
		return true
	end,
	getItemShoppingQty = function(row) return app.getItemShoppingQty and app.getItemShoppingQty(row) or 0 end,
	adjustItemShoppingQty = function(row, delta)
		shopCalls[#shopCalls + 1] = { kind = "item", key = row.key, delta = delta }
		return app.adjustItemShoppingQty and app.adjustItemShoppingQty(row, delta) or 0
	end,
	getRecipeShoppingQty = function(row) return app.getRecipeShoppingQty and app.getRecipeShoppingQty(row) or 0 end,
	adjustRecipeShoppingQty = function(row, delta)
		shopCalls[#shopCalls + 1] = { kind = "recipe", key = row.key or (row.recipe and row.recipe.spellID), delta = delta }
		return app.adjustRecipeShoppingQty and app.adjustRecipeShoppingQty(row, delta) or 0
	end,
}

local view = W.Create(hostContainer, wlCtx)
view:Show()
W.Layout(1040, 620)
W.Refresh(wlCtx)

local tbl = view.table
check(view ~= nil and view:IsShown(), "Watchlist view created and shown")
check(tbl ~= nil and tbl.scrollBox ~= nil, "Watchlist sortable table created")
check(view._mmCard ~= nil, "Watchlist view has NineApple glass_r10 cardBg surface")
check(view.headerBar and view.headerBar:GetHeight() == 40, "Watchlist headerBar height is 40px")
check(view.barSep ~= nil and view.barSep:GetHeight() == 1 and view.barSep._parent == view.headerBar,
	"Watchlist barSep is 1px anchored on headerBar bottom edge (not view top edge)")
local barSepPts = view.barSep._points or {}
check(#barSepPts >= 2 and barSepPts[1][1] == "BOTTOMLEFT" and barSepPts[2][1] == "BOTTOMRIGHT",
	"barSep spans BOTTOMLEFT to BOTTOMRIGHT of headerBar")

-- Verify 5 filter pills (22px)
check(type(view.filterOrder) == "table" and #view.filterOrder == 5,
	"Header renders 5 filter pills, got " .. tostring(view.filterOrder and #view.filterOrder))
for idx, key in ipairs({ "all", "recipes", "items", "profitable", "price_drop" }) do
	local btn = view.filterBtns[key]
	check(btn ~= nil and btn:GetHeight() == 22, "Filter pill '" .. key .. "' exists at 22px height")
	check(view.filterOrder[idx] == btn, "Filter pill order matches spec at index " .. idx)
end

-- Verify 4 right buttons (26px) + ASCII tooltips + shiftBadge CreateBadgePill
local rightBtns = {
	{ btn = view.colSettingsBtn, w = 54, h = 26, name = "Cols" },
	{ btn = view.shopButton,     w = 62, h = 26, name = "Shop" },
	{ btn = view.resetButton,    w = 58, h = 26, name = "Reset" },
	{ btn = view.filtersButton,  w = 66, h = 26, name = "Filters" },
}
for _, spec in ipairs(rightBtns) do
	check(spec.btn and spec.btn:GetWidth() == spec.w and spec.btn:GetHeight() == spec.h,
		string.format("%s button is %dx%d", spec.name, spec.w, spec.h))
	GameTooltip:Hide()
	spec.btn._scripts.OnEnter(spec.btn)
	check(GameTooltip:IsShown(), spec.name .. " tooltip shows on hover")
	spec.btn._scripts.OnLeave(spec.btn)
	check(not GameTooltip:IsShown(), spec.name .. " tooltip hides on leave")
end

check(view.shiftBadge and view.shiftBadge._pill and view.shiftBadge._pill.label ~= nil
	and view.shiftBadge:GetHeight() == 22,
	"shiftBadge uses Theme.CreateBadgePill at 22px height")
W.SetShiftMode(true)
check(view.shiftBadge:IsShown(), "SetShiftMode(true) reveals shiftBadge")
W.SetShiftMode(false)
check(not view.shiftBadge:IsShown(), "SetShiftMode(false) hides shiftBadge")

-- Verify 15 default visible columns + Cols popover toggle
check(#tbl.columns == 15, "Watchlist defaults to 15 visible columns, got " .. tostring(#tbl.columns))
local expectedDefaultCols = {
	"fav", "name", "kindLabel", "knownSort", "ownedQty", "listed",
	"unitAH", "craftCost", "profit", "marginPct", "salesPerDay", "demandSort", "trend24hDelta", "trend24hPct", "trendPct",
}
for i, k in ipairs(expectedDefaultCols) do
	check(tbl.columns[i] and tbl.columns[i].key == k,
		string.format("Default column #%d is %s (got %s)", i, k, tostring(tbl.columns[i] and tbl.columns[i].key)))
end
W.SetColumnVisible("vendorSell", true)
check(#tbl.columns == 16 and MerchantMasterDB.watchlistColumns.hidden.vendorSell == nil,
	"SetColumnVisible('vendorSell', true) shows optional column and persists in watchlistColumns")
check(W.ToggleColumnSettings(true) == true and view.colSettingsPopover:IsShown(), "Cols popover opens")
check(W.ToggleColumnSettings(false) == false and not view.colSettingsPopover:IsShown(), "Cols popover closes")
W.ResetColumns()
check(#tbl.columns == 15, "ResetColumns restores 15 default columns")

-- Verify standalone Thick Leather renders muted "-" for craftCost, profit, marginPct, knownSort
local tlFrame
for _, fr in ipairs(tbl.scrollBox._frames or {}) do
	if fr:IsShown() and fr.data and fr.data.key == "item:4304" then
		tlFrame = fr
		break
	end
end
check(tlFrame ~= nil and tlFrame.cellGroup ~= nil, "Thick Leather row frame bound in Watchlist table")
for _, dashCol in ipairs({ "craftCost", "profit", "marginPct", "knownSort" }) do
	local cell = tlFrame.cellGroup.cellsByKey[dashCol]
	check(cell ~= nil and cell.fs ~= nil, "Thick Leather cell exists for " .. dashCol)
	local txt = stripColor(cell.fs:GetText() or "")
	check(txt == "-", string.format("Standalone Thick Leather renders '-' for %s (got %q)", dashCol, txt))
end

-- 7. Filter Pill Clicks (All, Recipes, Items, Profitable, Price Drop) + Reset
view.filterBtns.recipes:Click("LeftButton")
check(#W.GetFilteredRows() == 2, "Recipes pill shows 2 recipes, got " .. tostring(#W.GetFilteredRows()))
for _, r in ipairs(W.GetFilteredRows()) do check(r.kind == "recipe", "Recipes filter excludes standalone items") end

view.filterBtns.items:Click("LeftButton")
check(#W.GetFilteredRows() == 2, "Items pill shows 2 standalone items, got " .. tostring(#W.GetFilteredRows()))
for _, r in ipairs(W.GetFilteredRows()) do check(r.kind == "item", "Items filter excludes recipes") end

view.filterBtns.profitable:Click("LeftButton")
local profFiltered = W.GetFilteredRows()
check(#profFiltered == 1 and profFiltered[1].key == ("recipe:" .. tostring(profRecipe.spellID)),
	"Profitable pill isolates the 1 profitable recipe, got " .. tostring(#profFiltered))

view.filterBtns.price_drop:Click("LeftButton")
local dropFiltered = W.GetFilteredRows()
check(#dropFiltered == 2, "Price Drop pill shows the 2 entries with <= -10% drop (Thick Leather & lossRecipe), got " .. tostring(#dropFiltered))
local dropKeys = {}
for _, r in ipairs(dropFiltered) do dropKeys[r.key] = true end
check(dropKeys["item:4304"] == true and dropKeys["recipe:" .. tostring(lossRecipe.spellID)] == true
	and not dropKeys["item:7912"] and not dropKeys["recipe:" .. tostring(profRecipe.spellID)],
	"Price Drop pill includes -22% Thick Leather and -28.6% lossRecipe, excludes -4% Solid Stone and +11% profRecipe")

view.resetButton:Click("LeftButton")
check(MerchantMasterDB.watchlistFilter == "all" and #W.GetFilteredRows() == 4,
	"Reset button restores All pill and all 4 watched entries")

-- 8. Row Clicks: Left-Click -> Quick Look, Right-Click -> Deep Analysis, Shift-Click -> Shopping List
local nameCell = tlFrame.cellGroup.cellsByKey.name
nameCell:Click("LeftButton")
check(#qlCalls == 1 and qlCalls[1].kind == "item" and qlCalls[1].row.itemID == 4304,
	"Left-clicking standalone item row opens Item Quick Look")

nameCell:Click("RightButton")
check(#daCalls == 1 and daCalls[1].spec.kind == "item" and daCalls[1].spec.itemID == 4304
	and daCalls[1].ret and daCalls[1].ret.tab == "watchlist",
	"Right-clicking standalone item row opens Deep Analysis with return tab = watchlist")

local origIsShift = _G.IsShiftKeyDown
_G.IsShiftKeyDown = function() return true end
nameCell:Click("LeftButton")
check(#shopCalls == 1 and shopCalls[1].delta == 1, "Shift+LeftClick adds +1 to Shopping List")
_G.IsShiftKeyDown = origIsShift

-- 9. Light/Dark + All 5 Warcraft Skins (including Goblin Baron) Repaint & RegisterWidget Race Check
local savedSkin = Theme.GetSkin()
local savedMode = Theme.GetMode()
local skinSweep = {
	{ skin = "standard",  mode = "dark",  styled = false },
	{ skin = "standard",  mode = "light", styled = false },
	{ skin = "goblin",    mode = "dark",  styled = true  },
	{ skin = "human",     mode = "dark",  styled = true  },
	{ skin = "night_elf", mode = "dark",  styled = true  },
	{ skin = "orc",       mode = "dark",  styled = true  },
	{ skin = "undead",    mode = "dark",  styled = true  },
}
for _, sw in ipairs(skinSweep) do
	Theme.SetSkin(sw.skin, true)
	if sw.skin == "standard" then Theme.SetMode(sw.mode) end
	local pal = Theme.GetActivePalette and Theme.GetActivePalette() or Theme.PALETTE
	local expectedSepA = ((pal and pal.separator and pal.separator[4]) or 0.45) * 0.45
	local sc = tlFrame.sep and tlFrame.sep._colorTexture
	check(sc ~= nil and approx(sc[4], expectedSepA, 0.01),
		string.format("Watchlist row sep wins RegisterWidget race under %s/%s (alpha=%.3f expected=%.3f)",
			sw.skin, sw.mode, tonumber(sc and sc[4]) or -1, expectedSepA))
	local expectedBarSepA = ((pal and pal.separator and pal.separator[4]) or 0.45) * 0.65
	local bsc = view.barSep and view.barSep._colorTexture
	check(bsc ~= nil and approx(bsc[4], expectedBarSepA, 0.01),
		string.format("Watchlist barSep stays soft under %s/%s (alpha=%.3f expected=%.3f)",
			sw.skin, sw.mode, tonumber(bsc and bsc[4]) or -1, expectedBarSepA))
	for i, col in ipairs(tbl.columns or {}) do
		local hbtn = tbl.headerBtns and tbl.headerBtns[i]
		check(hbtn and hbtn:GetHeight() == 26, "Header btn height is 26 under " .. sw.skin)
		if col.key == sortState.col and hbtn.fs then
			local txt = hbtn.fs:GetText() or ""
			check(txt:find("icon_chevron_down", 1, true) ~= nil,
				"Active sort header renders chevron under " .. sw.skin)
			if sw.styled then
				check(txt:find(string.upper(col.label), 1, true) ~= nil,
					"Styled skin uppercases header label under " .. sw.skin)
			end
		end
	end
end
Theme.SetSkin(savedSkin, true)
if savedSkin == "standard" then Theme.SetMode(savedMode) end

-- 10. Clicking Star Cell Removes Item from Watchlist View, 3-Way Quick Look Sync & Empty State
local favCell = tlFrame.cellGroup.cellsByKey.fav
check(favCell ~= nil and favCell.starIcon ~= nil, "Star column cell renders starIcon texture")
favCell:Click("LeftButton")
check(W.IsFavorite(4304) == false and W.GetCount() == 3 and #W.GetFilteredRows() == 3,
	"Clicking star column removes Thick Leather from Watchlist and refreshes view immediately")

-- Verify 3-way sync with real Quick Look hud.favButton
do
	app.panel:Show()
	local ssEvalRow = { key = "item:4304", itemID = 4304, outputItemID = 4304, name = "Thick Leather", sellable = true, unitAH = 780, listed = 45 }
	app.openQuickLook("item", ssEvalRow, { toggle = false })
	local hud = app.superListProvider and app.superListProvider.GetQuickLookFrame and app.superListProvider.GetQuickLookFrame()
	if hud and hud.favButton then
		check(hud.favButton._isFavorite == false, "Quick Look favButton reflects unfavorited Thick Leather")
		hud.favButton:Click("LeftButton")
		check(hud.favButton._isFavorite == true and W.IsFavorite(4304) == true and W.GetCount() == 4 and #W.GetFilteredRows() == 4,
			"Clicking Quick Look favButton adds Thick Leather to Watchlist and live-refreshes Watchlist table")
		W.Remove(4304)
		check(W.IsFavorite(4304) == false and W.GetCount() == 3,
			"Removing Thick Leather from Watchlist keeps count synced")
		if app.superListProvider.CloseQuickLook then app.superListProvider.CloseQuickLook() end
	end
end

-- Verify MarketScan.GetItemTrend7d prior-day mean baseline fallback for trendPct
do
	local origGetTrend7d = ns.MarketScan and ns.MarketScan.GetItemTrend7d
	if ns.MarketScan then
		local curDay = math.floor((host.getFixtureNow and host.getFixtureNow() or time()) / 86400)
		ns.MarketScan.GetItemTrend7d = function(id)
			if id == 7912 then
				return {
					source = "ahDaily",
					daysCollected = 4,
					startPrice7d = 1200,
					points = {
						{ d = curDay - 3, price = 1200 },
						{ d = curDay - 2, price = 1200 },
						{ d = curDay - 1, price = 1200 },
						{ d = curDay,     price = 960 },
					},
				}
			end
			return origGetTrend7d and origGetTrend7d(id) or nil
		end
		local rows7d = W.EvaluateRows(wlCtx)
		local ss7d
		for _, r in ipairs(rows7d) do if r.key == "item:7912" then ss7d = r; break end end
		check(ss7d ~= nil and type(ss7d.trendPct) == "number" and approx(ss7d.trendPct, -20.0, 0.2),
			"GetItemTrend7d prior-day mean baseline computes -20% drop cleanly, got " .. tostring(ss7d and ss7d.trendPct))
		ns.MarketScan.GetItemTrend7d = origGetTrend7d
	end
end

-- Verify 24h Trend (%) and 24h Value Change (copper delta) on Dreamfoil (60s -> 20s drop),
-- plus Price Drop pill coverage, nil-last sorting, and SavedVariables column migration
do
	local origGetTrend24h = ns.MarketScan and ns.MarketScan.GetItemTrend24h
	local origGetTrend7d = ns.MarketScan and ns.MarketScan.GetItemTrend7d
	local dreamID = 13463
	snapItems[dreamID] = { minBuyout = 2000, marketValue = 2000, historical = 2000, qty = 32, dailySold = 40.0 }
	host.loadSyntheticSnapshots({ items = snapItems })
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

	W.Add({ kind = "item", itemID = dreamID })
	if ns.MarketScan then
		ns.MarketScan.GetItemTrend24h = function(id)
			if id == dreamID then
				return {
					source = "ahSnapshots",
					hoursCollected = 12,
					startPrice24h = 6000,
					currentPrice = 2000,
					trendPct = -66.6667,
				}
			end
			return nil
		end
		ns.MarketScan.GetItemTrend7d = function(id)
			if id == dreamID then
				return {
					source = "ahDaily",
					daysCollected = 2,
					startPrice7d = 2000,
					trendPct = 0,
				}
			end
			return origGetTrend7d and origGetTrend7d(id) or nil
		end
	end

	W.Refresh(wlCtx)
	local dreamRow
	for _, r in ipairs(W.GetRows()) do
		if r.key == ("item:" .. tostring(dreamID)) then dreamRow = r; break end
	end
	check(dreamRow ~= nil, "Dreamfoil evaluated in Watchlist")
	check(dreamRow.unitAH == 2000 and dreamRow.trend24hStart == 6000
		and dreamRow.trend24hDelta == -4000 and approx(dreamRow.trend24hPct, -66.67, 0.2),
		string.format("Dreamfoil 24h trend computes start=6000, cur=2000, delta=-4000 (-40s), pct=-66.7%% (got delta=%s, pct=%s)",
			tostring(dreamRow.trend24hDelta), tostring(dreamRow.trend24hPct)))

	-- Find bound Dreamfoil table row frame and inspect 24h Chg, 24h Trend cells & hover tooltip
	local dreamFrame
	for _, fr in ipairs(tbl.scrollBox._frames or {}) do
		if fr:IsShown() and fr.data and fr.data.key == ("item:" .. tostring(dreamID)) then
			dreamFrame = fr
			break
		end
	end
	check(dreamFrame ~= nil and dreamFrame.cellGroup ~= nil, "Dreamfoil row frame bound in Watchlist table")
	local d24Cell = dreamFrame.cellGroup.cellsByKey.trend24hDelta
	local p24Cell = dreamFrame.cellGroup.cellsByKey.trend24hPct
	check(d24Cell ~= nil and p24Cell ~= nil, "24h Chg and 24h Trend cells bound")
	local d24Raw = d24Cell.fs:GetText() or ""
	local d24Txt = stripColor(d24Raw)
	local p24Txt = stripColor(p24Cell.fs:GetText() or "")
	check(d24Txt:find("-40s", 1, true) ~= nil, "24h Chg cell displays '-40s', got: " .. tostring(d24Txt))
	local pal = (ns.Theme and ns.Theme.GetActivePalette and ns.Theme.GetActivePalette()) or {}
	local d24Lower = d24Raw:lower()
	local isGreenBuy = d24Lower:find("|cff34c759", 1, true) ~= nil
		or d24Lower:find("|cff30d158", 1, true) ~= nil
		or d24Lower:find("|cff007a2b", 1, true) ~= nil
		or d24Lower:find("|cff5ff9ad", 1, true) ~= nil
	for _, k in ipairs({ "hexPositive", "hexGreen", "hexSuccess" }) do
		local hv = pal[k]
		if type(hv) == "string" and hv ~= "" then
			if d24Lower:find("|cff" .. hv:lower(), 1, true) ~= nil then
				isGreenBuy = true
			end
		end
	end
	check(isGreenBuy, "24h Chg price drop renders green buy-deal ink, got: " .. tostring(d24Raw))
	check(p24Txt == "-67%", "24h Trend cell displays '-67%', got: " .. tostring(p24Txt))

	GameTooltip:Hide()
	dreamFrame._scripts.OnEnter(dreamFrame)
	check(GameTooltip:IsShown(), "Hovering Dreamfoil row displays tooltip")
	local found24hLine = false
	for _, line in ipairs(GameTooltip._lines or {}) do
		local txt = stripColor(type(line) == "table" and (tostring(line.left or "") .. " " .. tostring(line.right or "")) or tostring(line or ""))
		if txt:find("24h Trend", 1, true) and txt:find("-66.7%", 1, true) and txt:find("-40s", 1, true)
			and txt:find("60s", 1, true) and txt:find("->", 1, true) and txt:find("20s", 1, true) then
			found24hLine = true
			break
		end
	end
	check(found24hLine, "Hover tooltip includes '24h Trend' with '-66.7%', '-40s', and '60s -> 20s'")
	dreamFrame._scripts.OnLeave(dreamFrame)

	-- Price Drop pill catches 24h drop even when Dreamfoil 7d baseline is 0%
	view.filterBtns.price_drop:Click("LeftButton")
	local foundDreamInDrop = false
	for _, r in ipairs(W.GetFilteredRows()) do
		if r.key == ("item:" .. tostring(dreamID)) then foundDreamInDrop = true; break end
	end
	check(foundDreamInDrop, "Price Drop filter includes Dreamfoil via its 24h -66.7% drop even when 7d trend is 0%")
	view.resetButton:Click("LeftButton")

	-- Nil-last numeric sorting works on trend24hDelta and trend24hPct (ascending & descending)
	local allRowsNow = W.GetRows()
	for _, sortKey in ipairs({ "trend24hDelta", "trend24hPct" }) do
		for _, asc in ipairs({ true, false }) do
			local sorted = W.FilterSort(allRowsNow, { filter = "all" }, { key = sortKey, ascending = asc })
			check(#sorted == #allRowsNow and sorted[1].key == ("item:" .. tostring(dreamID)),
				string.format("Single non-nil 24h item (%s asc=%s) sorts first while nils stay at bottom", sortKey, tostring(asc)))
			check(sorted[#sorted][sortKey] == nil,
				string.format("Nil %s rows pushed to bottom (asc=%s)", sortKey, tostring(asc)))
		end
	end

	-- Existing SavedVariables column order migration inserts trend24hDelta & trend24hPct right before trendPct
	MerchantMasterDB.watchlistColumns = {
		order = {
			"fav", "name", "kindLabel", "knownSort", "ownedQty", "listed",
			"unitAH", "craftCost", "profit", "marginPct", "salesPerDay", "demandSort", "trendPct",
		},
		hidden = {},
	}
	local migCfg = W.GetColumnConfig()
	local trendIdx, chg24Idx, pct24Idx
	for idx, k in ipairs(migCfg.order or {}) do
		if k == "trend24hDelta" then chg24Idx = idx end
		if k == "trend24hPct" then pct24Idx = idx end
		if k == "trendPct" then trendIdx = idx end
	end
	check(chg24Idx and pct24Idx and trendIdx and chg24Idx + 1 == pct24Idx and pct24Idx + 1 == trendIdx,
		"Legacy SavedVariables order inserts 24h Chg & 24h Trend immediately before 7d Trend")
	check(migCfg.hidden.trend24hDelta == nil and migCfg.hidden.trend24hPct == nil,
		"Migrated 24h Chg & 24h Trend remain visible by default")

	W.ResetColumns()
	if ns.MarketScan then
		ns.MarketScan.GetItemTrend24h = origGetTrend24h
		ns.MarketScan.GetItemTrend7d = origGetTrend7d
	end
	snapItems[dreamID] = nil
	W.Remove(dreamID)
end

-- Clear remaining favorites to verify empty state
W.Clear()
check(W.GetCount() == 0 and #W.GetFilteredRows() == 0, "Clear removes all remaining favorites")
check(view.emptyText ~= nil and view.emptyText:IsShown()
	and (view.emptyText:GetText() or ""):find("Watchlist is empty", 1, true) ~= nil,
	"Clean empty state message displayed when 0 favorites saved")

-- Cleanup
host.clearSyntheticSnapshots()
MerchantMasterDB.shoppingList = {}
hostContainer:Hide()

print(string.format("PASS: test_watchlist (%d assertions)", host.assertions()))
