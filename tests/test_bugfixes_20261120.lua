local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames, hostEnv = dofile(S .. "host_fixture.lua")
local app = ns.app
local db = MerchantMasterDB

local n = 0
local function check(ok, msg)
	n = n + 1
	if not ok then
		error("FAIL [" .. n .. "]: " .. tostring(msg), 2)
	end
end

local function reagentSig(list)
	local map = {}
	for _, rg in ipairs(list or {}) do
		local id, qty = tonumber(rg[1]), tonumber(rg[2])
		if id and qty then map[id] = (map[id] or 0) + qty end
	end
	local ks = {}
	for id in pairs(map) do ks[#ks + 1] = id end
	table.sort(ks)
	local parts = {}
	for i, id in ipairs(ks) do parts[i] = tostring(id) .. ":" .. tostring(map[id]) end
	return table.concat(parts, ",")
end

-- 1. Recipe reagent parity (ns.RECIPES vs MP.RECIPES) + EZ-Thro Dynamite regression
local mpBySpell = ns.MP and ns.MP.RECIPES_BY_SPELL or {}
local mismatched, missingCatalog, missingNames = 0, 0, 0
local ezThro1, ezThro2
for _, rec in ipairs(ns.RECIPES or {}) do
	if rec.spellID == 8339 then ezThro1 = rec end
	if rec.spellID == 23069 then ezThro2 = rec end
	local mpRec = rec.spellID and mpBySpell[rec.spellID]
	if mpRec and mpRec.r and rec.reagents and #rec.reagents > 0 then
		if reagentSig(rec.reagents) ~= reagentSig(mpRec.r) then
			mismatched = mismatched + 1
		end
	end
	for _, rg in ipairs(rec.reagents or {}) do
		local rid = rg[1]
		if not ns.ALL_CATALOG_IDS[rid] then missingCatalog = missingCatalog + 1 end
		if not ns.ITEM_NAMES_BY_ID[rid] then missingNames = missingNames + 1 end
	end
end
check(mismatched == 0, "Zero ns.RECIPES vs MP.RECIPES reagent mismatches (got " .. tostring(mismatched) .. ")")
check(missingCatalog == 0, "All recipe reagent IDs registered in ALL_CATALOG_IDS (missing=" .. tostring(missingCatalog) .. ")")
check(ezThro1 and reagentSig(ezThro1.reagents) == "2589:1,4364:3,260794:1",
	"EZ-Thro Dynamite requires Linen Cloth x1, Coarse Blasting Powder x3, EZ-Thro Wrap x1 (got " .. tostring(ezThro1 and reagentSig(ezThro1.reagents)) .. ")")
check(ezThro2 and reagentSig(ezThro2.reagents) == "4306:1,10505:1,260801:1",
	"EZ-Thro Dynamite II requires Silk Cloth x1, Solid Blasting Powder x1, EZ-Thro Fireproof Fuse x1")

-- Runtime live reagent sync self-healing
local savedEzRg = ezThro1.reagents
local changed = ns.SyncLiveRecipeReagents(8339, { { 4364, 2 }, { 2589, 1 }, { 260794, 1 } }, app.uiPriceBank)
check(changed == true, "SyncLiveRecipeReagents detects live server change")
check(reagentSig(ezThro1.reagents) == "2589:1,4364:2,260794:1", "SyncLiveRecipeReagents updates ns.RECIPES")
check(reagentSig(mpBySpell[8339].r) == "2589:1,4364:2,260794:1", "SyncLiveRecipeReagents updates MP.RECIPES_BY_SPELL")
-- Restore EZ-Thro Dynamite
ns.SyncLiveRecipeReagents(8339, savedEzRg, app.uiPriceBank)
db.liveRecipeReagents = nil

-- 2. Shopping List performance & price-cache preservation on Buy/Craft toggle
local econ = ns.CurrentEconomyInfo().effectiveKey
db.ahPrices = db.ahPrices or {}
db.ahPrices[econ] = db.ahPrices[econ] or {}
for id in pairs(ns.ALL_CATALOG_IDS) do
	db.ahPrices[econ][id] = { price = 1000 + (id % 50) * 100, listed = 50, at = time() }
end
db.craftOrderQueue = {
	{ idx = ezThro1.idx, spellID = ezThro1.spellID, outputItemID = ezThro1.outputItemID, prof = "engineering", qty = 10 },
}
app.panel:Show()
app.setTab("recipes")
app.refresh()
local bankBefore = app.getUIPriceBank()
local epochBefore = ns.priceCacheEpoch
bankBefore.mktPrice[4364] = 1234

-- Opening shopping list when already synced skips redundant BuildUnifiedShoppingList
local buildCalls = 0
local origBuild = ns.BuildUnifiedShoppingList
ns.BuildUnifiedShoppingList = function(...)
	buildCalls = buildCalls + 1
	return origBuild(...)
end
app.toggleShoppingWindow(true)
check(buildCalls == 0, "Opening already-synced shopping list skips redundant rebuild (calls=" .. tostring(buildCalls) .. ")")
ns.BuildUnifiedShoppingList = origBuild

-- Clicking Buy/Craft toggle preserves priceCacheEpoch and raw mktPrice cache
local box = app.ui.shopPanel.table.scrollBox
local items = box._dp and box._dp:GetCollection() or {}
local toggleBtn
for _, it in ipairs(items) do
	if it.canToggleCraft then
		local r = CreateFrame("Button", nil, box)
		box._view._initFn(r, it)
		toggleBtn = r.cells[8]
		break
	end
end
check(toggleBtn ~= nil, "Found toggleable Buy/Craft row for EZ-Thro Dynamite sub-reagent")
toggleBtn:GetScript("OnClick")(toggleBtn, "LeftButton")
check(ns.priceCacheEpoch == epochBefore, "Buy/Craft toggle does not wipe global priceCacheEpoch")
check(app.uiPriceBank == bankBefore and app.uiPriceBank.mktPrice[4364] == 1234,
	"Buy/Craft toggle preserves warm uiPriceBank raw prices")
app.toggleShoppingWindow(false)

-- 3. SuperList selected row & Quick View hover tooltip
local provider = app.superListProvider
local slBox = app.ui.superListView and app.ui.superListView.table and app.ui.superListView.table.scrollBox
local slPool = slBox and slBox._frames
if slBox and slBox._dp and slBox._dp:GetCollection() and #slBox._dp:GetCollection() > 0 then
	local firstRowData = slBox._dp:GetCollection()[1]
	local rowFrame = (slPool and slPool[1]) or CreateFrame("Button", nil, slBox)
	if not (slPool and slPool[1]) then slBox._view._initFn(rowFrame, firstRowData) end
	provider.OpenQuickLook(rowFrame.data or firstRowData, true, nil, { kind = "recipe", owner = rowFrame })
	local hud = provider.GetQuickLookFrame()
	check(hud and hud:IsShown(), "QuickLook opens for selected SuperList recipe")

	-- Hovering the selected SuperList row's name cell while QuickLook is open MUST show GameTooltip
	GameTooltip:Hide()
	local nameCell = rowFrame.cellGroup and rowFrame.cellGroup.cellsByKey and rowFrame.cellGroup.cellsByKey.name
	check(nameCell ~= nil, "SuperList row has name cell")
	nameCell:GetScript("OnEnter")(nameCell)
	check(GameTooltip:IsShown(), "Hovering selected SuperList item name shows tooltip while QuickLook is open")
	nameCell:GetScript("OnLeave")(nameCell)
	check(not GameTooltip:IsShown(), "Leaving SuperList item name hides tooltip")

	-- Hovering the QuickLook title itself ALSO shows GameTooltip
	check(hud.titleHover ~= nil, "QuickLook header has titleHover hit frame")
	hud.titleHover:GetScript("OnEnter")(hud.titleHover)
	check(GameTooltip:IsShown(), "Hovering QuickLook item title shows tooltip")
	hud.titleHover:GetScript("OnLeave")(hud.titleHover)
	check(not GameTooltip:IsShown(), "Leaving QuickLook item title hides tooltip")
	provider.CloseQuickLook()
end

-- 4. Bag/Bank/Mail ownership accuracy (no phantom bought leak, standalone native counts only)
db.includeMail = true
db.includeBank = true
db.includeAlts = false
app.char.bags = {}
app.char.mail = { ["Wool Cloth"] = 12 }
app.char.bank = { ["Wool Cloth"] = 20 }
app.char.bought = { ["Wool Cloth"] = 55 }
app.invalidateRecipeStats("ownership")
local ownedNative = (_G.MerchantMasterAPI and _G.MerchantMasterAPI.GetOwnedCounts and _G.MerchantMasterAPI.GetOwnedCounts()) or {}
check((ownedNative["Wool Cloth"] or 0) == 32,
	"Phantom char.bought=55 is excluded from ownedCounts (expected 12+20=32, got " .. tostring(ownedNative["Wool Cloth"]) .. ")")

-- Even if _G.TSM_API is present, standalone MerchantMaster ignores it and uses native counts
local prevTSM = _G.TSM_API
_G.TSM_API = {
	GetMailQuantity = function() return 0 end,
	GetBankQuantity = function() return 5 end,
}
app.invalidateRecipeStats("ownership")
local ownedIgnoreTSM = (_G.MerchantMasterAPI and _G.MerchantMasterAPI.GetOwnedCounts and _G.MerchantMasterAPI.GetOwnedCounts()) or {}
check((ownedIgnoreTSM["Wool Cloth"] or 0) == 32,
	"Standalone ownedCounts ignores _G.TSM_API (expected 12+20=32, got " .. tostring(ownedIgnoreTSM["Wool Cloth"]) .. ")")
_G.TSM_API = prevTSM

print(string.format("PASS: bugfixes_20261120 (%d assertions, 0 failures)", n))
