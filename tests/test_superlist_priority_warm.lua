local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, frames, hostEnv = dofile(S .. "host_fixture.lua")
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
local model = ns.SuperListModel
local stats = ns.RecipeStats
local tbl = app.ui.recipesTable
local box = tbl.scrollBox

local pool, capacity = {}, 16
box._frames = pool
box.GetHeight = function() return capacity * app.ui.ROW_H end
local dpSetCount = 0
local origSetDP = box.SetDataProvider
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
	dpSetCount = dpSetCount + 1
	self._dp = dp
	renderSuper()
end
function box:FullUpdate() renderSuper() end

local queued = {}
local oldAfter = C_Timer.After
C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
local function drain(limit)
	local guard = 0
	local cap = limit or 20000
	while #queued > 0 do
		local fn = table.remove(queued, 1)
		fn()
		guard = guard + 1
		assert(guard < cap, "runaway timer queue")
	end
end
local function fireEvent(event, ...)
	for _, frame in ipairs(frames) do
		if frame._events[event] and frame._scripts.OnEvent then
			frame._scripts.OnEvent(frame, event, ...)
		end
	end
end

-- Drain initial login timers cleanly
drain()

-- Isolate deterministic filters & professions
MerchantMasterDB.profFilter = "all"
MerchantMasterDB.unlockFilter = "all"
MerchantMasterDB.knownRecipesOnly = false
MerchantMasterDB.bisOnly = false
MerchantMasterDB.superListSources = {}
MerchantMasterDB.superListSkillMin = nil
MerchantMasterDB.superListSkillMax = nil
MerchantMasterDB.craftableFilter = "all"
MerchantMasterDB.demandFilter = "all"
MerchantMasterDB.sellableFilter = "all"
if app.ui.searchBox then app.ui.searchBox:SetText("") end

local savedGetProfs = ns.GetPlayerProfessions
local mockProfs = { alchemy = 300, enchanting = 300 }
ns.GetPlayerProfessions = function()
	local copy = {}
	for k, v in pairs(mockProfs) do copy[k] = v end
	return copy
end
app._lastSkillEventProfs = ns.GetPlayerProfessions()

local evalCount, sortCalls, starts = 0, 0, 0
local function stepUntilPartialEval()
	local guard = 0
	while #queued > 0 and evalCount == 0 do
		table.remove(queued, 1)()
		guard = guard + 1
		assert(guard < 1000, "expected partial recipe batch")
	end
end
local evalProfs, seenRecipes = {}, {}
local origGet = stats.Get
local origStart = model.Start
local origFilterSort = model.FilterSort

stats.Get = function(recipe, ctx)
	if not (type(ctx) == "table" and (ctx.masterChefMode ~= nil or ctx.barteringMode ~= nil)) then
		evalCount = evalCount + 1
		evalProfs[#evalProfs + 1] = recipe and recipe.prof or "?"
		if recipe then seenRecipes[recipe] = (seenRecipes[recipe] or 0) + 1 end
	end
	return origGet(recipe, ctx)
end
model.Start = function(...)
	starts = starts + 1
	return origStart(...)
end
model.FilterSort = function(...)
	sortCalls = sortCalls + 1
	return origFilterSort(...)
end

-- 1. 3-Tier Priority Order (Active Filter -> My Professions -> All)
local catalog = stats.GetCatalog()
check(#catalog == TOTAL_RECIPES, "Catalog has 2057 non-gather recipes")
local alchCount, enchCount = 0, 0
for _, entry in ipairs(catalog) do
	if entry.recipe.prof == "alchemy" then alchCount = alchCount + 1
	elseif entry.recipe.prof == "enchanting" then enchCount = enchCount + 1 end
end
check(alchCount > 0 and enchCount > 0 and alchCount + enchCount < #catalog, "Catalog has Tier-1, Tier-2, and Tier-3 slices")

local order = model.BuildPriorityOrder(catalog, { profFilter = "alchemy", profMap = mockProfs, key = "t1_alch" })
check(#order == #catalog, "Priority order covers all 2057 recipes")
for i = 1, alchCount do
	check(catalog[order[i]].recipe.prof == "alchemy", "Tier-1 slice contains active filter recipe at " .. i)
end
for i = alchCount + 1, alchCount + enchCount do
	check(catalog[order[i]].recipe.prof == "enchanting", "Tier-2 slice contains learned non-filter profession at " .. i)
end
for i = alchCount + enchCount + 1, #order do
	local p = catalog[order[i]].recipe.prof
	check(p ~= "alchemy" and p ~= "enchanting", "Tier-3 slice contains remaining professions at " .. i)
end

evalCount, evalProfs, seenRecipes = 0, {}, {}
local tierReadyCount, tierReadyDone = 0, 0
local completedRows = nil
model.Start(
	{
		dataset = "t1_unit",
		priority = { profFilter = "alchemy", profMap = mockProfs, key = "t1_unit" },
	},
	nil,
	function(r) completedRows = r end,
	nil,
	function(_, done, total)
		tierReadyCount = tierReadyCount + 1
		tierReadyDone = done
		check(done == alchCount and total == #catalog, "onTierReady fires once right after Tier-1 finishes")
	end
)
drain()
check(tierReadyCount == 1 and tierReadyDone == alchCount, "Model.Start fired onTierReady exactly once at Tier-1 boundary")
check(completedRows ~= nil and #completedRows == #catalog, "Model.Start completed all 2057 rows after onTierReady")
for i = 1, alchCount do check(evalProfs[i] == "alchemy", "Evaluated Tier-1 alchemy first at " .. i) end
for i = alchCount + 1, alchCount + enchCount do check(evalProfs[i] == "enchanting", "Evaluated Tier-2 enchanting second at " .. i) end

-- 2. Early Tier-1 UI Paint + Flicker-Free Completion
MerchantMasterDB.profFilter = "alchemy"
app.panel:Show()
app.setTab("recipes")
provider.Invalidate()
evalCount, evalProfs, seenRecipes, dpSetCount = 0, {}, {}, 0
app.refresh()
local earlyEvalCount, dpAtEarly = nil, nil
while #queued > 0 do
	table.remove(queued, 1)()
	if dpSetCount > 0 and not earlyEvalCount then
		earlyEvalCount = evalCount
		dpAtEarly = dpSetCount
		local summaryTxt = app.ui.recipesView.summary:GetText() or ""
		check(earlyEvalCount < #catalog, "UI bound Tier-1 before full 2057 evaluation finished (" .. earlyEvalCount .. ")")
		check(summaryTxt:find("(warming ", 1, true) ~= nil, "Early Tier-1 summary indicates background warming")
		local shown = box._dp:GetCollection()
		check(#shown > 0, "Early Tier-1 rendered matching Alchemy rows")
		for _, r in ipairs(shown) do
			check(r.prof == "alchemy", "Early Tier-1 table shows only active Alchemy filter rows")
		end
	end
end
check(earlyEvalCount ~= nil and evalCount == #catalog, "Background Tier-2/3 completed to 2057 after early paint")
check(dpSetCount == dpAtEarly, "Final completion updated summary cleanly without extra SetDataProvider flicker")
check((app.ui.recipesView.summary:GetText() or ""):find("(warming ", 1, true) == nil, "Completed summary clears warming suffix")

-- 3. On-the-Fly Mid-Load Reprioritization with 0 Duplicates
MerchantMasterDB.profFilter = "all"
provider.Invalidate()
evalCount, evalProfs, seenRecipes, dpSetCount = 0, {}, {}, 0
app.refresh()
stepUntilPartialEval()
check(evalCount > 0 and evalCount < #catalog, "Partial progress evaluated before mid-load filter switch")
local tailoringAtSwitch = 0
for _, entry in ipairs(catalog) do
	if entry.recipe.prof == "tailoring" and not seenRecipes[entry.recipe] then
		tailoringAtSwitch = tailoringAtSwitch + 1
	end
end
check(tailoringAtSwitch > 0, "Remaining unevaluated tailoring recipes exist before switch")
MerchantMasterDB.profFilter = "tailoring"
app.refresh()
local idxBeforeEarly = evalCount
local tailoringEarlyHit = false
while #queued > 0 do
	table.remove(queued, 1)()
	if dpSetCount > 0 and not tailoringEarlyHit then
		tailoringEarlyHit = true
		check(evalCount < #catalog, "Mid-load filter switch painted tailoring early before 2057 completion")
	end
end
check(tailoringEarlyHit and evalCount == #catalog, "Mid-load reprioritized run completed cleanly with exact total 2057")
for _, entry in ipairs(catalog) do
	check(seenRecipes[entry.recipe] == 1, "Zero duplicate or skipped evaluations after mid-load reprioritization")
end

-- 4. Keep All Recipes warm when opening the basket or switching sidebar views.
MerchantMasterDB.profFilter = "all"
app.refresh()
drain()
check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES, "Full 2057 dataset presented before Basket round-trip test")

app.toggleShoppingWindow(true)
app.refresh()
drain()

local queuedBefore = #queued
evalCount, sortCalls = 0, 0
app.toggleShoppingWindow(false)
app.refresh()
local queuedAdded = #queued - queuedBefore
check(queuedAdded == 0, "Closing the basket renders All Recipes in 0 frames (" .. queuedAdded .. ")")
check(evalCount == 0 and sortCalls == 0, "Closing the basket does 0 evaluations and 0 re-sorts")
check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES, "Closing the basket preserves all recipe rows")

-- Parent-hide OnHide preserves pool[1].data while shown; recycled row Hide clears data and return restores synchronously in 0 frames
app.setTab("profit_spread")
app.refresh()
drain()
if pool[1] and pool[1]._scripts and pool[1]._scripts.OnHide then
	pool[1]._scripts.OnHide(pool[1])
end
check(pool[1] and pool[1].data ~= nil, "Parent-hide OnHide preserves pool[1].data while row remains shown")
pool[1]:Hide()
check(pool[1] and pool[1].data == nil, "Recycled row Hide clears pool[1].data")
pool[1]._shown = true
queuedBefore = #queued
evalCount, sortCalls = 0, 0
app.setTab("recipes")
app.refresh()
queuedAdded = #queued - queuedBefore
check(queuedAdded == 0 and evalCount == 0 and sortCalls == 0 and pool[1].data ~= nil,
	"Return after stale nil row data restores pool[1].data synchronously in 0 frames with 0 sorts/evals")

app.setTab("bags")
app.refresh()
drain()
queuedBefore = #queued
evalCount, sortCalls = 0, 0
app.setTab("recipes")
app.refresh()
queuedAdded = #queued - queuedBefore
check(queuedAdded == 0 and evalCount == 0 and sortCalls == 0, "Return from Bags renders Super List in 0 frames with 0 sorts/evals")

-- 5a. RecipeStats.RepairItems on real evaluated craftCost == nil rows
local econ = ns.CurrentEconomyInfo().effectiveKey
MerchantMasterDB.ahPrices[econ] = MerchantMasterDB.ahPrices[econ] or {}
local nilCraftRec, nilReagID
for _, entry in ipairs(catalog) do
	local rec = entry.recipe
	local reags = ns.ResolveRecipeReagents and ns.ResolveRecipeReagents(rec) or rec.reagents
	if reags and #reags > 0 then
		for _, pair in ipairs(reags) do
			local rid = pair[1] or pair.itemID
			if rid and not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[rid]) and not (MerchantMasterDB.ahPrices[econ][rid]) then
				local ctxProbe = { economy = econ, charKey = app.charKey, favorCopper = 0, ownedCounts = {}, profMap = mockProfs, repState = {} }
				local probeRow = origGet(rec, ctxProbe)
				if probeRow and probeRow.craftCost == nil then
					nilCraftRec, nilReagID = rec, rid
					break
				end
			end
		end
	end
	if nilCraftRec then break end
end
check(nilCraftRec ~= nil and nilReagID ~= nil, "Found real catalog recipe with craftCost == nil")
local repairCtx = { economy = econ, charKey = app.charKey, favorCopper = 0, ownedCounts = {}, profMap = mockProfs, repState = {} }
local realNilRow = origGet(nilCraftRec, repairCtx)
check(realNilRow.craftCost == nil, "Real evaluated row has craftCost == nil")
check(stats.RepairItems({ realNilRow }, repairCtx, { [nilReagID] = true }) == false,
	"RepairItems returns false for real evaluated craftCost == nil row when reagent prices are unchanged")
local prevAH = MerchantMasterDB.ahPrices[econ][nilReagID]
MerchantMasterDB.ahPrices[econ][nilReagID] = { price = 500, qty = 10, at = time() }
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
check(stats.RepairItems({ realNilRow }, repairCtx, { [nilReagID] = true }) == true,
	"RepairItems returns true when real craftCost == nil row gains a reagent AH price")
MerchantMasterDB.ahPrices[econ][nilReagID] = prevAH
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
local syntheticRow = { recipe = { reagents = { { itemID = nilReagID } } } }
check(stats.RepairItems({ syntheticRow }, repairCtx, { [nilReagID] = true }) == true,
	"RepairItems retains true fallback for unevaluated synthetic nil-craft row")

do
	local ah = MerchantMasterDB.ahPrices[econ]
	local mode, orePrice, barPrice = MerchantMasterDB.priceSource, ah[2770], ah[2840]
	MerchantMasterDB.priceSource = "live_ah"
	ah[2770] = { price = 10, qty = 50, at = time() }
	ah[2840] = { price = 10, qty = 50, at = time() }
	ns.InvalidatePriceCache()
	local smelt = ns.RECIPES_BY_OUTPUT[2840][1]
	local boomstick = ns.RECIPES_BY_OUTPUT[4362][1]
	local ctx = {economy=econ, favorCopper=0, ownedCounts={}, profMap={}, repState={},
		subCraftMode="all_sub", subCraftOverrides={[2840]="craft",[4359]="craft",[4361]="craft"}}
	local rows = {origGet(smelt,ctx), origGet(boomstick,ctx)}
	local oldCost = rows[2].craftCost
	check(rows[1].craftCost==10 and rows[1].unitAH==10 and oldCost, "repair starts with cached live AH prices and a priced sub-craft chain")
	ah[2770] = { price = 20, qty = 50, at = time() }
	ah[2840] = { price = 20, qty = 50, at = time() }
	stats.RepairItemsInPlace(rows,ctx,{[2770]=true})
	check(rows[1].craftCost==20 and rows[1].unitAH==20, "first repair re-queries live AH for the reagent and derived output")
	check(rows[2].craftCost==oldCost+30, "ore changes reach a recipe three links away through bars and engineering sub-crafts")
	MerchantMasterDB.priceSource, ah[2770], ah[2840] = mode, orePrice, barPrice
	ns.InvalidatePriceCache()
end

do
	local recipe = ns.RECIPES_BY_OUTPUT[14342][1] -- Mooncloth
	local ctx = {economy=econ, favorCopper=0, ownedCounts={}, profMap={tailoring=300}, repState={}}
	local oldTime, oldCooldown = time, GetSpellCooldown
	local clock, remaining = 1000, nil
	time = function() return clock end
	GetSpellCooldown = function(spellID)
		if spellID == recipe.spellID and remaining then return GetTime()-10, remaining+10 end
	end
	local rows = {origGet(recipe, ctx)}
	clock, remaining = 2000, 2000
	local repaired, needFull = stats.RepairItemsInPlace(rows, ctx, {[14256]=true})
	local expiry = ns.activeChar.cooldowns[recipe.spellID]
	check(repaired == 1 and not needFull and expiry == 4000,
		"repair records the true live cooldown expiry, got " .. tostring(expiry))
	clock, remaining = 3500, nil
	local info = ns.GetRecipeCooldownInfo(recipe)
	check(info.onCooldown and info.remainingSeconds == 500, "saved cooldown survives loss of the live API")
	ns.activeChar.cooldowns[recipe.spellID] = nil
	time, GetSpellCooldown = oldTime, oldCooldown
end

do
	local crateID, strutID = 248710, 4387
	local mode, previousPrices = MerchantMasterDB.priceSource, MerchantMasterDB.ahPrices[econ]
	local market = {[crateID]={price=400},[strutID]={price=1000}}
	MerchantMasterDB.priceSource, MerchantMasterDB.ahPrices[econ] = "live_ah", market
	local elixir, otherFavor, unrelated
	for _, entry in ipairs(catalog) do
		local recipe = entry.recipe
		if recipe.spellID == 1250794 then elixir=recipe
		elseif recipe.prof == "alchemy" and recipe.source == "camp" and (recipe.favorCost or 0)>0 then otherFavor=recipe
		elseif recipe.spellID == 2657 then unrelated=recipe end
	end
	local ctx = {economy=econ, ownedCounts={}, profMap={}, repState={}}
	while stats.WarmStep(ctx) do end
	local rows = {origGet(elixir,ctx), origGet(otherFavor,ctx), origGet(unrelated,ctx)}
	local initialCost, unrelatedRow = rows[1].buyCostCopper, rows[3]
	check(initialCost and rows[2].buyCostEstimated, "Favor rows start with a crate-based estimate")
	for _, change in ipairs({{crateID,800},{strutID,1200},{crateID,0}}) do
		market[change[1]].price = change[2]
		local repaired, needFull = stats.RepairItemsInPlace(rows,ctx,{[change[1]]=true})
		local fresh = {economy=econ, ownedCounts={}, profMap={}, repState={}}
		local freshCost, freshOther = origGet(elixir,fresh).buyCostCopper, origGet(otherFavor,fresh).buyCostCopper
		check(repaired==2 and not needFull and rows[3]==unrelatedRow,
			"crate and bundle price changes repair all Favor rows without rebuilding unrelated rows")
		check(rows[1].buyCostCopper~=initialCost and rows[1].buyCostCopper==freshCost and rows[2].buyCostCopper==freshOther,
			string.format("Favor item %d: old=%s repaired=%s fresh=%s",change[1],tostring(initialCost),tostring(rows[1].buyCostCopper),tostring(freshCost)))
		initialCost=rows[1].buyCostCopper
	end
	MerchantMasterDB.priceSource, MerchantMasterDB.ahPrices[econ] = mode, previousPrices
end

-- 5b. SKILL_LINES_CHANGED noise vs rank bump (row values + unlock filter threshold) vs new profession
app.toggleShoppingWindow(false)
MerchantMasterDB.profFilter = "alchemy"
MerchantMasterDB.unlockFilter = "unlocked"
mockProfs.alchemy = 280
app._lastSkillEventProfs = ns.GetPlayerProfessions()
app.invalidateRecipeStats("skills")
app.refresh(); drain()
local thresholdKey = nil
for _, entry in ipairs(catalog) do
	local r = entry.recipe
	if r.prof == "alchemy" and (r.skill or 0) >= 285 and (r.skill or 0) <= 300 and (tonumber(r.rep) or 0) == 0 and not ns.IsRecipeKnown(r) then
		thresholdKey = entry.key
		break
	end
end
check(thresholdKey ~= nil, "Found non-known Alchemy threshold recipe in 285..300")
local function findDisplayedRow(key)
	for _, r in ipairs(box._dp and box._dp:GetCollection() or {}) do
		if r.key == key then return r end
	end
	return nil
end
check(findDisplayedRow(thresholdKey) == nil, "Threshold recipe is excluded by Unlocked filter at Alchemy 280")
local startsBefore = starts
evalCount = 0
fireEvent("SKILL_LINES_CHANGED"); drain()
check(starts == startsBefore and evalCount == 0, "Unchanged SKILL_LINES_CHANGED noise triggers 0 rebuilds")
mockProfs.alchemy = 310
fireEvent("SKILL_LINES_CHANGED"); drain()
check(starts == startsBefore and evalCount == 0, "Skill rank bump 280->310 updates metadata without rebuilding 2057 rows")
local unlockedRow = findDisplayedRow(thresholdKey)
check(unlockedRow ~= nil, "Threshold recipe becomes visible under Unlocked filter after SKILL_LINES_CHANGED 280->310")
check(unlockedRow and unlockedRow.craftAbility and unlockedRow.craftAbility.playerSkill == 310 and unlockedRow.craftAbility.meetsSkill == true,
	"Patched row craftAbility reflects playerSkill=310 and meetsSkill=true")
check(unlockedRow and unlockedRow.unlock and unlockedRow.unlock.playerSkill == 310 and unlockedRow.unlock.meetsSkill == true and unlockedRow.unlock.unlockedNow == true,
	"Patched row unlock reflects playerSkill=310, meetsSkill=true, and unlockedNow=true")
-- Mid-replacement-build SKILL_LINES_CHANGED (280->310 while Tier-1 replacement is active over retained old rows)
mockProfs.alchemy = 280
fireEvent("SKILL_LINES_CHANGED"); drain()
check(findDisplayedRow(thresholdKey) == nil, "Threshold recipe excluded again at Alchemy 280 before replacement build")
local savedApplyCut = MerchantMasterDB.applyAHCut
MerchantMasterDB.applyAHCut = (savedApplyCut == false)
evalCount, evalProfs, dpSetCount = 0, {}, 0
local replStartsBefore = starts
app.refresh()
while #queued > 0 and dpSetCount == 0 do
	table.remove(queued, 1)()
end
check(dpSetCount > 0 and evalCount > 0 and evalCount < #catalog, "Tier-1 replacement presented over retained old rows before completion")
check(findDisplayedRow(thresholdKey) == nil, "Threshold recipe excluded in Tier-1 replacement at Alchemy 280")
mockProfs.alchemy = 310
fireEvent("SKILL_LINES_CHANGED"); drain()
check(starts == replStartsBefore + 1 and evalCount == #catalog, "Mid-replacement skill bump patches buildState.rows without extra rebuild")
local replRow = findDisplayedRow(thresholdKey)
check(replRow ~= nil, "Threshold recipe visible under Unlocked filter after mid-replacement SKILL_LINES_CHANGED 280->310")
check(replRow and replRow.craftAbility and replRow.craftAbility.playerSkill == 310,
	"Mid-replacement patched craftAbility reflects playerSkill=310")
check(replRow and replRow.unlock and replRow.unlock.playerSkill == 310 and replRow.unlock.unlockedNow == true,
	"Mid-replacement patched unlock reflects playerSkill=310 and unlockedNow=true")
MerchantMasterDB.applyAHCut = savedApplyCut
MerchantMasterDB.profFilter = "all"
MerchantMasterDB.unlockFilter = "all"
app.refresh(); drain()
startsBefore = starts
evalCount = 0
mockProfs.inscription = 300
fireEvent("SKILL_LINES_CHANGED"); drain()
check(starts == startsBefore + 1 and evalCount == TOTAL_RECIPES, "Learning a new profession triggers 1 clean rebuild")

-- 5c. Ledger ahSalesVersion filtering (non-AH events ignored; AH outcome events bump)
local store = ns.Analytics and ns.Analytics.Store
check(store ~= nil and type(stats.EffectiveLedgerVersion) == "function", "Analytics Store and EffectiveLedgerVersion loaded")
if store and not store.initialized then store.Init() end
-- Initialize firstLive[char] once if unset, then verify steady-state non-AH operations cause 0 rebuilds
store.AddLoot(2447, "Mob", "Test", 1)
app.refresh(); drain()
evalCount = 0
app.refresh(); drain()
check(evalCount == 0, "Steady list before ledger test has 0 evaluations")
local accVer0 = store.accountingVersion
local salesVer0 = store.ahSalesVersion
store.AddLoot(2447, "Mob", "Test", 1)
store.AddBasis(econ, 2447, 1, 10)
for _, typ in ipairs({ "CRAFT", "VENDOR_SELL", "AH_BUY", "WRIT_TURNIN" }) do
	check(store.Append({ type = typ, itemID = 2447, qty = 1, unit = 10, total = 10, where = "Test" }) ~= nil, typ .. " appended")
end
app.refresh(); drain()
check(store.accountingVersion > accVer0, "Non-AH AddLoot/AddBasis/Append events advance accountingVersion")
check(store.ahSalesVersion == salesVer0, "AddLoot/AddBasis/CRAFT/VENDOR_SELL/AH_BUY/WRIT_TURNIN do not advance ahSalesVersion")
check(evalCount == 0, "Non-AH ledger events cause 0 Super List rebuilds")
for i, typ in ipairs({ "AH_SELL", "AH_EXPIRE", "AH_POST", "AH_CANCEL" }) do
	check(store.Append({ type = typ, itemID = 2447, qty = 1, unit = 10, total = 10, where = "Test" }) ~= nil, typ .. " appended")
	check(store.ahSalesVersion == salesVer0 + i, typ .. " advances ahSalesVersion")
end
app.refresh(); drain()
check(evalCount == TOTAL_RECIPES, "AH outcome ledger events refresh Super List once")

-- 6. Background Warmup & Hide Cancellation
app.panel:Hide()
provider.Invalidate()
drain()
app.activeTab = "dashboard"
app.panel:Show()
queued = {}
evalCount, evalProfs, starts = 0, {}, 0
app.warmSuperListCache(0.05)
-- Execute timer fire + initial background warmup slices
stepUntilPartialEval()
check(evalCount > 0 and evalCount < #catalog, "Background warmup began evaluating recipes on dashboard tab")
local isMine = { alchemy = true, enchanting = true, inscription = true }
for i = 1, #evalProfs do
	check(isMine[evalProfs[i]] == true, "Background warmup evaluates My Professions first (" .. tostring(evalProfs[i]) .. ")")
end
-- User switches onto Super List mid-background-warm -> upgrades in-place without restarting
local startsAtOpen = starts
app.setTab("recipes")
app.refresh()
drain()
check(starts == startsAtOpen, "Switching to Super List mid-background-warm upgrades existing job without restarting")
check(evalCount == #catalog and box._dp and #box._dp:GetCollection() == TOTAL_RECIPES, "Upgraded job completes all 2057 rows without duplicates")

-- Panel hide cancels both warmTimer and in-flight background work immediately
provider.Invalidate()
app.activeTab = "dashboard"
app.panel:Show()
queued = {}
evalCount = 0
app.warmSuperListCache(0.05)
stepUntilPartialEval()
local beforeHide = evalCount
check(beforeHide > 0, "Background warm evaluated rows before panel hide")
app.panel:Hide()
drain()
check(evalCount == beforeHide, "panel:Hide cancels warmTimer and active background work with 0 further evaluations")

-- 7. Bug 1 Regressions: reconcilePending + Cancel() permanent hang & mid-warm stale earlyBoundResult
do
	-- 7a. reconcilePending + Cancel() (panel Hide/Show & Invalidate(nil) & WarmInBackground sig change) never hangs All Recipes
	MerchantMasterDB.profFilter = "all"
	MerchantMasterDB.unlockFilter = "all"
	MerchantMasterDB.knownRecipesOnly = false
	app.panel:Show()
	app.setTab("recipes")
	drain()
	app.ui.searchBox._text = "green lens"
	app.ui.searchBox:GetScript("OnTextChanged")(app.ui.searchBox, false)
	drain()
	check(box._dp and #box._dp:GetCollection() == 1, "Search 'green lens' narrows All Recipes to 1 row")

	app.setTab("dashboard")
	drain()
	app.ui.searchBox._mmClearBtn:GetScript("OnClick")(app.ui.searchBox._mmClearBtn)
	provider.Invalidate("ownership")
	app.panel:Hide()
	app.panel:Show()
	app.setTab("recipes")
	drain()
	check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES,
		"Invalidate('ownership') + panel Hide/Show before reconcile never hangs All Recipes on stale search")

	-- Repeat with Invalidate('ownership') + Invalidate(nil) same frame
	app.ui.searchBox._text = "green lens"
	app.ui.searchBox:GetScript("OnTextChanged")(app.ui.searchBox, false)
	drain()
	app.setTab("dashboard")
	drain()
	app.ui.searchBox._mmClearBtn:GetScript("OnClick")(app.ui.searchBox._mmClearBtn)
	provider.Invalidate("ownership")
	provider.Invalidate()
	app.setTab("recipes")
	drain()
	check(box._dp and #box._dp:GetCollection() == TOTAL_RECIPES,
		"Invalidate('ownership') + Invalidate(nil) same frame never orphans reconcilePending")

	-- 7b. Mid-warm stale earlyBoundResult & summary on search clear + return
	MerchantMasterDB.profFilter = "engineering"
	provider.Invalidate()
	drain()
	app.setTab("recipes")
	app.ui.searchBox._text = "green lens"
	app.ui.searchBox:GetScript("OnTextChanged")(app.ui.searchBox, false)
	local guard = 0
	while #queued > 0 and guard < 250 do
		table.remove(queued, 1)()
		guard = guard + 1
		if (app.ui.recipesView.summary:GetText() or ""):find("warming", 1, true) then break end
	end
	check(box._dp and #box._dp:GetCollection() == 1, "Mid-warm Engineering + 'green lens' early-painted 1 row")
	app.setTab("dashboard")
	app.ui.searchBox._mmClearBtn:GetScript("OnClick")(app.ui.searchBox._mmClearBtn)
	app.setTab("recipes")
	local sawStaleOneSummary = false
	for _ = 1, 20 do
		if #queued == 0 then break end
		table.remove(queued, 1)()
		local txt = app.ui.recipesView.summary:GetText() or ""
		if txt:match("^1 / %d+ recipes %(warming") then sawStaleOneSummary = true end
	end
	check(not sawStaleOneSummary, "Clearing 'green lens' mid-warm never prints stale '1 / ... (warming ...)' summary")
	drain()
	check(box._dp and #box._dp:GetCollection() > 50,
		"Clearing 'green lens' mid-warm restores full Engineering list cleanly (" .. tostring(box._dp and #box._dp:GetCollection()) .. ")")
	MerchantMasterDB.profFilter = "all"
	app.refresh()
	drain()
end

-- 8. Bug 2 Regressions: 3-tier priority in background warm, mid-warm reprioritization, pause/resume Tier-1, unlockFilter/knownOnly, and profMap fallback
do
	local tailoringCount, bsCount = 0, 0
	for _, entry in ipairs(catalog) do
		if entry.recipe.prof == "tailoring" then tailoringCount = tailoringCount + 1
		elseif entry.recipe.prof == "blacksmithing" then bsCount = bsCount + 1 end
	end
	check(tailoringCount > 0 and bsCount > 0, "Catalog has tailoring and blacksmithing recipes")

	-- 8a. Background warm respects selected profFilter = 'tailoring' (Tier 1 tailoring -> Tier 2 my profs -> Tier 3 rest)
	MerchantMasterDB.profFilter = "tailoring"
	MerchantMasterDB.unlockFilter = "all"
	MerchantMasterDB.knownRecipesOnly = false
	app.panel:Hide()
	provider.Invalidate()
	drain()
	app.activeTab = "dashboard"
	app.panel:Show()
	queued = {}
	evalCount, evalProfs, seenRecipes, starts = 0, {}, {}, 0
	app.warmSuperListCache(0.05)
	drain()
	check(evalCount == TOTAL_RECIPES, "Background warm with profFilter='tailoring' completes all recipes")
	for i = 1, tailoringCount do
		check(evalProfs[i] == "tailoring", "Background warm Tier 1 evaluates tailoring first at " .. i)
	end
	local mineSet = { alchemy = true, enchanting = true, inscription = true }
	local mineCount = 0
	for _, entry in ipairs(catalog) do
		if mineSet[entry.recipe.prof] then mineCount = mineCount + 1 end
	end
	for i = tailoringCount + 1, tailoringCount + mineCount do
		check(mineSet[evalProfs[i]] == true, "Background warm Tier 2 evaluates my profs second at " .. i)
	end

	-- 8b. Changing profFilter on Dashboard mid-background-warm reprioritizes without restarting (0 restarts, 0 duplicates)
	MerchantMasterDB.profFilter = "all"
	app.panel:Hide()
	provider.Invalidate()
	drain()
	app.activeTab = "dashboard"
	app.panel:Show()
	queued = {}
	evalCount, evalProfs, seenRecipes, starts = 0, {}, {}, 0
	app.warmSuperListCache(0.05)
	stepUntilPartialEval()
	check(provider.IsWarming and provider.IsWarming() == true, "provider.IsWarming() reports true mid-background-warm")
	local startsBeforeSwitch = starts
	local evalsBeforeSwitch = evalCount
	MerchantMasterDB.profFilter = "blacksmithing"
	provider.WarmInBackground(app.buildSuperListContext())
	drain()
	check(starts == startsBeforeSwitch, "Mid-background-warm profFilter change reprioritizes with 0 restarts")
	check(evalCount == TOTAL_RECIPES, "Reprioritized background warm completes exact catalog count")
	local firstAfterSwitch = evalProfs[evalsBeforeSwitch + 1]
	check(firstAfterSwitch == "blacksmithing", "Next evaluation after Dashboard filter switch is blacksmithing (got " .. tostring(firstAfterSwitch) .. ")")
	for _, entry in ipairs(catalog) do
		check(seenRecipes[entry.recipe] == 1, "Zero duplicate evaluations after mid-background-warm reprioritization")
	end

	-- 8c. panel:Hide()/Show() after Tier 1 finishes (with earlyBoundResult == nil) still paints Tier 1 immediately on reopen
	MerchantMasterDB.profFilter = "alchemy"
	app.panel:Hide()
	provider.Invalidate()
	drain()
	app.activeTab = "dashboard"
	app.panel:Show()
	queued = {}
	evalCount, evalProfs, dpSetCount = 0, {}, 0
	app.warmSuperListCache(0.05)
	-- Run past alchemy Tier 1 while in background (onTierReady == nil, earlyBoundResult == nil)
	while #queued > 0 and evalCount <= alchCount + 5 do
		table.remove(queued, 1)()
	end
	check(evalCount > alchCount and evalCount < TOTAL_RECIPES, "Background warm passed Tier-1 alchemy boundary before hide")
	app.panel:Hide()
	queued = {}
	app.activeTab = "recipes"
	dpSetCount = 0
	app.panel:Show()
	local paintedEarlyOnReopen = false
	while #queued > 0 do
		table.remove(queued, 1)()
		if dpSetCount > 0 and evalCount < TOTAL_RECIPES then
			paintedEarlyOnReopen = true
			break
		end
	end
	drain()
	check(paintedEarlyOnReopen, "Reopening panel after paused Tier-1 completion fires early Tier-1 paint immediately before 2057 finish")

	-- 8d. Top-toolbar unlockFilter='mine_profs' and knownRecipesOnly=true with profFilter='all' trigger Tier-1 early paint
	for _, modeSpec in ipairs({
		{ name = "My Profs", unlock = "mine_profs", known = false },
		{ name = "Craftable Now", unlock = "known", known = true },
	}) do
		MerchantMasterDB.profFilter = "all"
		MerchantMasterDB.unlockFilter = modeSpec.unlock
		MerchantMasterDB.knownRecipesOnly = modeSpec.known
		app.panel:Hide()
		provider.Invalidate()
		drain()
		queued = {}
		evalCount, evalProfs, dpSetCount = 0, {}, 0
		app.activeTab = "recipes"
		app.panel:Show()
		local hitEarly = false
		while #queued > 0 do
			table.remove(queued, 1)()
			if dpSetCount > 0 and evalCount < TOTAL_RECIPES then
				hitEarly = true
				break
			end
		end
		drain()
		check(hitEarly, modeSpec.name .. " with profFilter='all' triggers Tier-1 early paint right after my profs complete")
	end

	-- 8e. Startup empty profMap falls back to ns.activeChar.profs for Tier-2 priority ordering
	MerchantMasterDB.profFilter = "all"
	MerchantMasterDB.unlockFilter = "all"
	MerchantMasterDB.knownRecipesOnly = false
	local savedActiveProfs = ns.activeChar and ns.activeChar.profs
	local prevGetProfs = ns.GetPlayerProfessions
	ns.GetPlayerProfessions = function() return {} end
	if ns.activeChar then ns.activeChar.profs = { leatherworking = 300 } end
	app.panel:Hide()
	provider.Invalidate()
	drain()
	app.activeTab = "dashboard"
	app.panel:Show()
	queued = {}
	evalCount, evalProfs = 0, {}
	app.warmSuperListCache(0.05)
	stepUntilPartialEval()
	check(evalCount > 0 and evalProfs[1] == "leatherworking",
		"Empty live profMap falls back to ns.activeChar.profs for Tier-2 priority (got " .. tostring(evalProfs[1]) .. ")")
	app.panel:Hide()
	drain()
	ns.GetPlayerProfessions = prevGetProfs
	if ns.activeChar then ns.activeChar.profs = savedActiveProfs end
end

-- 9. Surgical item price invalidation, standalone 30m freshness fix, single-item AH repair, and Vendor Crafter chained pre-warm
do
	-- 9a. ns.InvalidateItemPrices clears ONLY affected slots without bumping ns.priceCacheEpoch
	check(type(ns.InvalidateItemPrices) == "function", "ns.InvalidateItemPrices is exposed")
	local bank = app.getUIPriceBank()
	ns.BeginEval(bank)
	bank.mktPrice[2447] = { 100, "Live AH" }
	bank.mktPrice[765] = { 200, "Live AH" }
	bank.mktPrice[2449] = { 300, "Live AH" }
	bank.craftOpt["test_key"] = { cost = 50 }
	bank.smartCraft["test_key"] = { cost = 50 }
	local epoch0 = ns.priceCacheEpoch
	check(ns.InvalidateItemPrices({ [2447] = true }) == true, "InvalidateItemPrices accepts { [id] = true } set")
	check(ns.priceCacheEpoch == epoch0, "InvalidateItemPrices does NOT bump ns.priceCacheEpoch")
	check(bank.mktPrice[2447] == nil and ns._evalCache.mktPrice[2447] == nil, "InvalidateItemPrices clears affected item slot in bank and _evalCache")
	check(bank.mktPrice[765] ~= nil and bank.mktPrice[2449] ~= nil, "InvalidateItemPrices preserves unrelated item slots")
	check(next(bank.craftOpt) == nil and next(bank.smartCraft) == nil, "InvalidateItemPrices clears derived craftOpt/smartCraft memos")
	bank.mktPrice[2447] = { 110, "Live AH" }
	check(ns.InvalidateItemPrices({ 2447, 765 }) == true, "InvalidateItemPrices accepts array { id1, id2 }")
	check(ns.priceCacheEpoch == epoch0 and bank.mktPrice[2447] == nil and bank.mktPrice[765] == nil and bank.mktPrice[2449] ~= nil,
		"Array form clears listed items without bumping epoch or touching unrelated items")
	check(ns.InvalidateItemPrices(2449) == true, "InvalidateItemPrices accepts single numeric itemID")
	check(ns.priceCacheEpoch == epoch0 and bank.mktPrice[2449] == nil, "Numeric form clears item without bumping epoch")
	ns.EndEval()

	-- 9b. Standalone GetEffectivePriceVersion never wipes priceCacheEpoch on legacy 30-min boundary
	local savedTime = _G.time
	local savedSrc = MerchantMasterDB.priceSource
	local savedRec2447 = MerchantMasterDB.ahPrices[econ][2447]
	local clock = 2000000
	_G.time = function() return clock end
	MerchantMasterDB.priceSource = "auto"

	MerchantMasterDB.ahPrices[econ][2447] = { price = 150, qty = 5, at = clock - 1795, absent = false }
	local sv1 = ns.GetEffectivePriceVersion()
	clock = clock + 20 -- crosses old 30m boundary (1801s)
	local sv2 = ns.GetEffectivePriceVersion()
	check(sv2 == sv1, "Standalone GetEffectivePriceVersion does NOT wipe priceCacheEpoch at 30m boundary")

	_G.time = savedTime
	MerchantMasterDB.priceSource = savedSrc
	MerchantMasterDB.ahPrices[econ][2447] = savedRec2447

	-- 9c. recordOrderBookLots / single-item AH update preserves warm All Recipes buildState and repairs via "items"
	local savedLegacyC = MerchantMasterDB.enableLegacyPriceAddons
	local savedSrcC = MerchantMasterDB.priceSource
	local savedOre = MerchantMasterDB.ahPrices[econ][2770]
	local savedBar = MerchantMasterDB.ahPrices[econ][2840]
	local savedAH = _G.C_AuctionHouse
	MerchantMasterDB.enableLegacyPriceAddons = false
	MerchantMasterDB.priceSource = "live_ah"
	MerchantMasterDB.ahPrices[econ][2770] = { price = 100, qty = 20, absent = false, at = time(), itemWide = true }
	MerchantMasterDB.ahPrices[econ][2840] = { price = 400, qty = 10, absent = false, at = time(), itemWide = true }
	MerchantMasterDB.profFilter = "all"
	MerchantMasterDB.unlockFilter = "all"
	MerchantMasterDB.knownRecipesOnly = false
	ns.InvalidatePriceCache()
	app.panel:Show()
	app.setTab("recipes")
	app.refresh()
	drain()
	local smeltKey = nil
	for _, r in ipairs(box._dp and box._dp:GetCollection() or {}) do
		if r.recipe and r.recipe.outputItemID == 2840 then smeltKey = r.key; break end
	end
	check(smeltKey ~= nil, "Found Smelt Copper row in warm All Recipes table")
	local beforeSmelt = findDisplayedRow(smeltKey)
	check(beforeSmelt and beforeSmelt.craftCost == 100, "Warm Smelt Copper starts with craftCost=100 (got " .. tostring(beforeSmelt and beforeSmelt.craftCost) .. ")")

	local startsBefore = starts
	local epochBefore = ns.priceCacheEpoch
	evalCount = 0
	_G.C_AuctionHouse = setmetatable({
		HasFullCommoditySearchResults = function(id) return id == 2770 end,
		GetNumCommoditySearchResults = function(id) return id == 2770 and 1 or 0 end,
		GetCommoditySearchResultInfo = function(id, idx)
			if id == 2770 and idx == 1 then
				return { quantity = 12, numOwnerItems = 0, unitPrice = 250, timeLeftSeconds = 7200 }
			end
		end,
		HasFullBrowseResults = function() return true end,
		GetBrowseResults = function()
			return { { itemKey = { itemID = 2770, itemLevel = 0, itemSuffix = 0 }, totalQuantity = 8, minPrice = 320 } }
		end,
	}, { __index = savedAH or {} })

	ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)
	drain()
	check(ns.priceCacheEpoch == epochBefore, "Single-item commodity order-book update does NOT bump ns.priceCacheEpoch")
	check(starts == startsBefore, "Single-item commodity order-book update preserves warm All Recipes buildState (0 full rebuilds)")
	check(evalCount > 0 and evalCount < TOTAL_RECIPES, "Single-item commodity update repairs only affected recipes (" .. evalCount .. "/" .. TOTAL_RECIPES .. ")")
	local afterCommodity = findDisplayedRow(smeltKey)
	check(afterCommodity and afterCommodity.craftCost == 250, "Repaired Smelt Copper reflects new commodity price 250 (got " .. tostring(afterCommodity and afterCommodity.craftCost) .. ")")

	evalCount = 0
	app.wanted = { open = true, itemID = 2770, name = ns.ItemName(2770), unrestricted = true }
	ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	drain()
	check(ns.priceCacheEpoch == epochBefore, "Single-item browse search update does NOT bump ns.priceCacheEpoch")
	check(starts == startsBefore, "Single-item browse search update preserves warm All Recipes buildState (0 full rebuilds)")
	check(evalCount > 0 and evalCount < TOTAL_RECIPES, "Single-item browse search update repairs only affected recipes (" .. evalCount .. "/" .. TOTAL_RECIPES .. ")")
	local afterBrowse = findDisplayedRow(smeltKey)
	check(afterBrowse and afterBrowse.craftCost == 320, "Repaired Smelt Copper reflects new browse search price 320 (got " .. tostring(afterBrowse and afterBrowse.craftCost) .. ")")

	_G.C_AuctionHouse = savedAH
	MerchantMasterDB.enableLegacyPriceAddons = savedLegacyC
	MerchantMasterDB.priceSource = savedSrcC
	MerchantMasterDB.ahPrices[econ][2770] = savedOre
	MerchantMasterDB.ahPrices[econ][2840] = savedBar

	-- 9d. app.warmVendorCrafterCache chains cleanly after All Recipes warm completes, and panel hide preserves VC warm state
	check(type(app.warmVendorCrafterCache) == "function", "app.warmVendorCrafterCache is exposed")
	check(type(app.onSuperListWarmComplete) == "function", "app.onSuperListWarmComplete is exposed")
	local vc = app.vendorCrafterProvider
	check(vc ~= nil, "app.vendorCrafterProvider is registered")
	local origVCWarm = vc.WarmInBackground
	local origVCHasWarm = vc.HasWarmData
	local origVCIsWarming = vc.IsWarming
	local origVCCancelPres = vc.CancelPresentation
	local origVCCancel = vc.Cancel

	local vcWarmCalls, vcLastCtx = 0, nil
	local vcWarmDone, vcWarmRunning = false, false
	local vcCancelPresCalls, vcCancelCalls = 0, 0
	vc.WarmInBackground = function(ctx)
		vcWarmCalls = vcWarmCalls + 1
		vcLastCtx = ctx
		vcWarmDone = true
		vcWarmRunning = false
		return true
	end
	vc.HasWarmData = function() return vcWarmDone or vcWarmRunning end
	vc.IsWarming = function() return vcWarmRunning end
	vc.CancelPresentation = function()
		vcCancelPresCalls = vcCancelPresCalls + 1
		if origVCCancelPres then origVCCancelPres() end
	end
	vc.Cancel = function()
		vcCancelCalls = vcCancelCalls + 1
		if origVCCancel then origVCCancel() end
	end
	app._vcWarmUnsupported = nil

	-- All Recipes is already warm from 9c; calling warmSuperListCache on Dashboard chains VC warm cleanly
	app.activeTab = "dashboard"
	app.panel:Show()
	queued = {}
	vcWarmCalls, vcLastCtx, vcWarmDone = 0, nil, false
	app.warmSuperListCache(0.05)
	drain()
	check(vcWarmCalls == 1, "warmSuperListCache chains app.warmVendorCrafterCache when All Recipes is already warm (calls=" .. vcWarmCalls .. ")")
	check(type(vcLastCtx) == "table" and vcLastCtx.masterChefMode ~= nil and vcLastCtx.barteringMode ~= nil,
		"Chained Vendor Crafter warm receives full buildVendorCrafterContext()")

	-- onSuperListWarmComplete skips when already viewing vendor_crafter, and chains when on another tab
	app.activeTab = "vendor_crafter"
	vcWarmCalls = 0
	queued = {}
	app.onSuperListWarmComplete()
	drain()
	check(vcWarmCalls == 0, "onSuperListWarmComplete does not start background VC warm while vendor_crafter tab is active")

	app.activeTab = "dashboard"
	vcWarmCalls = 0
	queued = {}
	app.onSuperListWarmComplete()
	drain()
	check(vcWarmCalls == 1, "onSuperListWarmComplete chains app.warmVendorCrafterCache(0.05) on non-VC tab")

	-- panel:Hide uses CancelPresentation (not Cancel) so Vendor Crafter warm state is preserved
	vcCancelPresCalls, vcCancelCalls = 0, 0
	app.panel:Hide()
	check(vcCancelPresCalls == 1 and vcCancelCalls == 0,
		"panel:Hide invokes vendorCrafterProvider.CancelPresentation() instead of Cancel()")
	check(vc.HasWarmData() == true, "Vendor Crafter warm state survives panel:Hide")

	vc.WarmInBackground = origVCWarm
	vc.HasWarmData = origVCHasWarm
	vc.IsWarming = origVCIsWarming
	vc.CancelPresentation = origVCCancelPres
	vc.Cancel = origVCCancel
	app._vcWarmUnsupported = nil

	-- 9e. Store.RecordCraftYield log/reset split + targeted BAG_UPDATE_DELAYED & cooldown payloads
	local storeRef = ns.Analytics and ns.Analytics.Store
	check(storeRef ~= nil and type(storeRef.craftYieldResetVersion) == "number", "Store exposes craftYieldResetVersion")
	local cyv0 = storeRef.craftYieldVersion
	local cyrv0 = storeRef.craftYieldResetVersion
	storeRef.RecordCraftYield(2657, 2840, 2, 1)
	check(storeRef.craftYieldVersion == cyv0 + 1, "RecordCraftYield increments craftYieldVersion")
	check(storeRef.craftYieldResetVersion == cyrv0, "RecordCraftYield does NOT bump craftYieldResetVersion")
	local logEntry = storeRef.craftYieldLog and storeRef.craftYieldLog[storeRef.craftYieldVersion]
	check(type(logEntry) == "table" and logEntry.itemID == 2840 and logEntry.spellID == 2657,
		"RecordCraftYield logs { itemID=2840, spellID=2657 } at new craftYieldVersion")
	local firstLoggedVer = storeRef.craftYieldVersion
	for i = 1, 66 do
		storeRef.RecordCraftYield(2657, 2840, 1, 1)
	end
	check(storeRef.craftYieldResetVersion == cyrv0, "66 RecordCraftYield calls still leave craftYieldResetVersion unchanged")
	check(storeRef.craftYieldLog[firstLoggedVer] == nil and storeRef.craftYieldLog[storeRef.craftYieldVersion] ~= nil,
		"craftYieldLog prunes entries <= craftYieldVersion - 64 while retaining recent entries")
	local rebRes = storeRef.Rebuild()
	check(rebRes and rebRes.ok and storeRef.craftYieldResetVersion == cyrv0 + 1,
		"Store.Rebuild (publishReplay) increments craftYieldResetVersion")
	local prevLedgerDB = _G.MerchantMasterLedgerDB
	local cyrvBeforeSwap = storeRef.craftYieldResetVersion
	_G.MerchantMasterLedgerDB = {}
	storeRef.Init()
	check(storeRef.craftYieldResetVersion == cyrvBeforeSwap + 1, "Store.Init DB swap increments craftYieldResetVersion")
	_G.MerchantMasterLedgerDB = prevLedgerDB
	storeRef.Init()

	-- Targeted BAG_UPDATE_DELAYED ownership diff payload
	local origGetSlots = C_Container.GetContainerNumSlots
	local origGetInfo = C_Container.GetContainerItemInfo
	local bagState = {
		{ itemID = 2770, stackCount = 5, hyperlink = "|cffffffff|Hitem:2770::::::::20:::::|h[Copper Ore]|h|r" },
		{ itemID = 2447, stackCount = 3, hyperlink = "|cffffffff|Hitem:2447::::::::20:::::|h[Peacebloom]|h|r" },
	}
	C_Container.GetContainerNumSlots = function(b) return b == 0 and #bagState or 0 end
	C_Container.GetContainerItemInfo = function(b, s) return b == 0 and bagState[s] or nil end
	fireEvent("BAG_UPDATE_DELAYED")
	drain()

	local captured = {}
	local origInvStats = app.invalidateRecipeStats
	app.invalidateRecipeStats = function(reason, payload)
		captured[#captured + 1] = { reason = reason, payload = payload }
		return origInvStats(reason, payload)
	end
	bagState[2].stackCount = 4 -- only Peacebloom (2447) changed; Copper Ore (2770) unchanged
	fireEvent("BAG_UPDATE_DELAYED")
	drain()
	local bagEv = nil
	for _, ev in ipairs(captured) do
		if ev.reason == "ownership" then bagEv = ev end
	end
	check(bagEv ~= nil and type(bagEv.payload) == "table" and type(bagEv.payload.ids) == "table" and type(bagEv.payload.names) == "table",
		"BAG_UPDATE_DELAYED passes targeted { names, ids } payload to invalidateRecipeStats('ownership')")
	check(bagEv.payload.ids[2447] == true and bagEv.payload.ids[2770] == nil,
		"BAG_UPDATE_DELAYED payload.ids contains only changed itemID 2447")
	check(bagEv.payload.names["Peacebloom"] == true and bagEv.payload.names["Copper Ore"] == nil,
		"BAG_UPDATE_DELAYED payload.names contains only changed name Peacebloom")

	-- Targeted cooldown payloads for UNIT_SPELLCAST_SUCCEEDED (single + shared group) and scanPlayerCooldowns
	local moonclothRec = ns.RECIPES_BY_OUTPUT[14342] and ns.RECIPES_BY_OUTPUT[14342][1]
	check(moonclothRec and moonclothRec.spellID, "Found Mooncloth cooldown recipe")
	local transmuteRecs = {}
	for _, r in ipairs(ns.RECIPES or {}) do
		if r.spellID and (tonumber(r.cd) or 0) >= 60 and ns.GetRecipeCooldownGroup and ns.GetRecipeCooldownGroup(r) == "alchemy_transmute" then
			transmuteRecs[#transmuteRecs + 1] = r
		end
	end
	check(#transmuteRecs >= 2, "Found >= 2 shared alchemy_transmute cooldown recipes")

	captured = {}
	queued = {}
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", moonclothRec.spellID)
	local cdEv = nil
	for _, ev in ipairs(captured) do
		if ev.reason == "cooldown" then cdEv = ev end
	end
	check(cdEv ~= nil and type(cdEv.payload) == "table" and cdEv.payload[moonclothRec.spellID] == true
		and cdEv.payload[transmuteRecs[1].spellID] == nil,
		"UNIT_SPELLCAST_SUCCEEDED passes targeted changedSpells containing only Mooncloth")

	captured = {}
	queued = {}
	fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", transmuteRecs[1].spellID)
	local grpEv = nil
	for _, ev in ipairs(captured) do
		if ev.reason == "cooldown" then grpEv = ev end
	end
	check(grpEv ~= nil and type(grpEv.payload) == "table"
		and grpEv.payload[transmuteRecs[1].spellID] == true
		and grpEv.payload[transmuteRecs[2].spellID] == true
		and grpEv.payload[moonclothRec.spellID] == nil,
		"UNIT_SPELLCAST_SUCCEEDED includes shared cooldown group siblings without unrelated cooldowns")

	-- scanPlayerCooldowns flip passes targeted changedSpells
	app.char.cooldowns[moonclothRec.spellID] = nil
	app._lastCooldownSig = nil
	app.scanPlayerCooldowns() -- seed baseline (mooncloth off CD)
	app.char.cooldowns[moonclothRec.spellID] = time() + 3600
	captured = {}
	local flipped = app.scanPlayerCooldowns()
	local scanEv = nil
	for _, ev in ipairs(captured) do
		if ev.reason == "cooldown" then scanEv = ev end
	end
	check(flipped == true and scanEv ~= nil and type(scanEv.payload) == "table"
		and scanEv.payload[moonclothRec.spellID] == true
		and scanEv.payload[transmuteRecs[1].spellID] == nil,
		"app.scanPlayerCooldowns passes targeted changedSpells on cooldown state flip")

	app.char.cooldowns[moonclothRec.spellID] = nil
	app.char.cooldowns[transmuteRecs[1].spellID] = nil
	if app.char.cooldownGroups then app.char.cooldownGroups["alchemy_transmute"] = nil end
	app._lastCooldownSig = nil
	app.invalidateRecipeStats = origInvStats
	C_Container.GetContainerNumSlots = origGetSlots
	C_Container.GetContainerItemInfo = origGetInfo
	queued = {}
end

-- Restore mocks
ns.GetPlayerProfessions = savedGetProfs
stats.Get = origGet
model.Start = origStart
model.FilterSort = origFilterSort
C_Timer.After = oldAfter
box.SetDataProvider = origSetDP

print("PASS: Super List priority + warm cache suite (" .. n .. " assertions, 0 failures)")
