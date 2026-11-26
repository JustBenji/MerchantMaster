-- Craft-Finish Performance Benchmark (Stage 4 Crafting Task Strip — Heavy Realistic Session)
-- Measures wall-clock latency & hot-path API/render call counts across 10 consecutive craft finishes
-- with 300 open TradeSkill recipes, 60 bag items across 5 bags, 6 queued craft tasks, and cbExtended=true.
-- Standalone headless Lua 5.1 benchmark (run with lua51/lua.exe tests/bench_craft_finish.lua).

local S = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local ns, createdFrames, hostEnv = dofile(S .. "host_fixture.lua")

local app = ns.app
local of = assert(app and app.orderFlow, "app.orderFlow missing")
local modal = assert(app and app.ui and app.ui.cartBuyerModal, "app.ui.cartBuyerModal missing")

-- Deterministic virtual clock + C_Timer queue
local simNow = 2000.0
local wallBase = 1794400000
_G.GetTime = function() return simNow end
_G.time = function() return wallBase + math.floor(simNow - 2000.0) end
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.InCombatLockdown = function() return false end
_G.NUM_BAG_SLOTS = 4

local timers = {}
_G.C_Timer = {
	After = function(delay, fn)
		if type(fn) ~= "function" then return end
		timers[#timers + 1] = { due = simNow + (tonumber(delay) or 0), fn = fn, cancelled = false }
	end,
	NewTimer = function(delay, fn)
		local t = { due = simNow + (tonumber(delay) or 0), fn = fn, cancelled = false }
		function t:Cancel() self.cancelled = true end
		timers[#timers + 1] = t
		return t
	end,
}

local function clearTimers()
	timers = {}
end

local function drainTimersTo(targetTime)
	local guard = 0
	while guard < 500 do
		local nextIdx, bestDue = nil, nil
		for i, t in ipairs(timers) do
			if not t.cancelled and t.due <= targetTime then
				if not bestDue or t.due < bestDue then
					bestDue, nextIdx = t.due, i
				end
			end
		end
		if not nextIdx then break end
		local t = table.remove(timers, nextIdx)
		if t.due > simNow then simNow = t.due end
		guard = guard + 1
		t.fn()
	end
	if targetTime > simNow then simNow = targetTime end
end

-- Fire real Blizzard events on EVERY registered addon event frame (MerchantMaster, UI_Professor, Analytics/Capture, MapPins, UI_TrainerStats)
local function fireEvent(ev, ...)
	for _, f in ipairs(createdFrames) do
		if f._events and f._events[ev] and f._scripts and f._scripts.OnEvent then
			f._scripts.OnEvent(f, ev, ...)
		end
	end
end

-- Initialize Analytics/Capture & UI_Professor frames just like real WoW login
if _G.WorldMapFrame and not _G.WorldMapFrame.RemoveAllPinsByTemplate then
	_G.WorldMapFrame.RemoveAllPinsByTemplate = function() end
end
local capFrame = ns.Analytics and ns.Analytics.Capture and ns.Analytics.Capture.frame
if capFrame and capFrame._scripts and capFrame._scripts.OnEvent then
	capFrame._scripts.OnEvent(capFrame, "ADDON_LOADED", "MerchantMaster")
	capFrame._scripts.OnEvent(capFrame, "PLAYER_LOGIN")
end
for _, f in ipairs(createdFrames) do
	if f ~= capFrame and f._events and f._events.PLAYER_LOGIN and f._events.TRADE_SKILL_UPDATE and not f._events.ADDON_LOADED and f._scripts and f._scripts.OnEvent then
		f._scripts.OnEvent(f, "PLAYER_LOGIN")
	end
end
drainTimersTo(simNow + 1.0)

-- Ensure player has Alchemy 300 + Engineering 300 so TradeSkill scanners run fully (never bail on profession mismatch)
ns.GetLivePlayerProfessions = function() return { alchemy = 300, engineering = 300 } end
ns.GetPlayerProfessions = function() return { alchemy = 300, engineering = 300 } end
ns.IsForeignTradeSkill = function() return false end

-- Collect 300 real recipes (Alchemy prioritized first, padded from ns.RECIPES / synthetic to exact 300)
local recipes300 = {}
local recipesById = {}
local recipeIds300 = {}
local alchemyTasks = {}

local function addRecipeEntry(spellID, name, outputID, reagents, numMade)
	if recipesById[spellID] then return end
	local idx = #recipes300 + 1
	local entry = {
		index = idx,
		spellID = spellID,
		name = name or ("Recipe " .. tostring(spellID)),
		outputID = outputID or (80000 + idx),
		reagents = reagents or {},
		numMade = numMade or 1,
		difficulty = "optimal",
		learned = true,
	}
	recipes300[idx] = entry
	recipesById[spellID] = entry
	recipeIds300[idx] = spellID
end

-- First gather Alchemy recipes with real reagents for our 6 queued craft tasks
for _, rec in ipairs(ns.RECIPES or {}) do
	local spID = tonumber(rec.spellID or rec.s)
	local rRaw = rec.reagents or rec.r
	if rec.prof == "alchemy" and spID and spID > 0 and type(rRaw) == "table" and #rRaw >= 1 then
		local rList = {}
		for _, rg in ipairs(rRaw) do
			local id = tonumber(rg[1] or rg.itemID)
			local q = tonumber(rg[2] or rg.qty) or 1
			if id and id > 0 then
				rList[#rList + 1] = { itemID = id, name = (ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[id]) or ("Item " .. id), qty = q }
			end
		end
		if #rList >= 1 then
			addRecipeEntry(spID, rec.name or rec.n, rec.itemID or rec.out, rList, rec.numMade or rec.m or 1)
			if #alchemyTasks < 6 then
				alchemyTasks[#alchemyTasks + 1] = recipesById[spID]
			end
		end
	end
	if #recipes300 >= 300 then break end
end

-- Fill remainder up to exact 300 recipes from ns.RECIPES (any profession)
if #recipes300 < 300 then
	for _, rec in ipairs(ns.RECIPES or {}) do
		local spID = tonumber(rec.spellID or rec.s)
		if spID and spID > 0 and not recipesById[spID] then
			addRecipeEntry(spID, rec.name or rec.n, rec.itemID or rec.out, {}, rec.numMade or rec.m or 1)
			if #recipes300 >= 300 then break end
		end
	end
end
while #recipes300 < 300 do
	local synId = 950000 + #recipes300 + 1
	addRecipeEntry(synId, "Benchmark Elixir " .. tostring(#recipes300 + 1), 960000 + #recipes300 + 1, {}, 1)
end
assert(#recipes300 == 300, "Expected 300 recipes in TradeSkillFrame mock, got " .. tostring(#recipes300))
assert(#alchemyTasks == 6, "Expected 6 Alchemy craft tasks, got " .. tostring(#alchemyTasks))

-- Build 60 bag items distributed across 5 bags (bags 0..4, 12 slots per bag = 60 occupied slots)
local bagState = {}
local bagItemTotals = {}
local bagSlotIndex = {} -- itemID -> { bag, slot }

local function resetBags()
	bagState = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
	bagItemTotals = {}
	bagSlotIndex = {}
	local neededReagents = {}
	local reagentOrder = {}
	for _, task in ipairs(alchemyTasks) do
		for _, rg in ipairs(task.reagents) do
			if not neededReagents[rg.itemID] then
				neededReagents[rg.itemID] = 0
				reagentOrder[#reagentOrder + 1] = rg.itemID
			end
			neededReagents[rg.itemID] = neededReagents[rg.itemID] + (rg.qty * 20)
		end
	end
	local slotCursor = 0
	local function placeNext(itemID, count)
		local b = math.floor(slotCursor / 12)
		local s = (slotCursor % 12) + 1
		slotCursor = slotCursor + 1
		bagState[b][s] = { itemID = itemID, stackCount = count, isLocked = false, isBound = false }
		bagItemTotals[itemID] = (bagItemTotals[itemID] or 0) + count
		if not bagSlotIndex[itemID] then bagSlotIndex[itemID] = { b, s } end
	end
	for _, id in ipairs(reagentOrder) do
		placeNext(id, neededReagents[id])
	end
	-- Pad to exact 60 realistic bag items from catalog
	local padIdx = 0
	for id in pairs(ns.ITEM_NAMES_BY_ID or {}) do
		if slotCursor >= 60 then break end
		if type(id) == "number" and id > 0 and not bagItemTotals[id] then
			padIdx = padIdx + 1
			placeNext(id, 5 + (padIdx % 15))
		end
	end
	while slotCursor < 60 do
		local synItem = 970000 + slotCursor
		placeNext(synItem, 10)
	end
end

local function adjustBagItem(itemID, delta)
	if not itemID or delta == 0 then return end
	local loc = bagSlotIndex[itemID]
	if loc then
		local cell = bagState[loc[1]][loc[2]]
		if cell then
			cell.stackCount = math.max(0, (cell.stackCount or 0) + delta)
			bagItemTotals[itemID] = math.max(0, (bagItemTotals[itemID] or 0) + delta)
			return
		end
	end
	if delta > 0 then
		-- Put newly crafted output into bag 4 slot 13+
		local s = 13
		while bagState[4][s] and bagState[4][s].itemID ~= itemID do s = s + 1 end
		if not bagState[4][s] then
			bagState[4][s] = { itemID = itemID, stackCount = delta, isLocked = false, isBound = false }
		else
			bagState[4][s].stackCount = (bagState[4][s].stackCount or 0) + delta
		end
		bagSlotIndex[itemID] = { 4, s }
		bagItemTotals[itemID] = (bagItemTotals[itemID] or 0) + delta
	end
end

-- Instrumentation counters
local metrics = {}
local function resetMetrics()
	metrics = {
		renderCalls = 0,
		tradeskillApiCalls = 0,
		tsGetAllRecipeIDs = 0,
		tsGetRecipeInfo = 0,
		tsGetRecipeOutput = 0,
		tsGetRecipeSchematic = 0,
		tsGetBaseProf = 0,
		tsClassicCalls = 0,
		readinessCalls = 0,
		destinationsCalls = 0,
		bagScanCalls = 0,
		inventoryScanCalls = 0,
		containerApiCalls = 0,
		phaseMs = {
			spellcast = 0,
			tradeskillUpdate = 0,
			bagUpdate = 0,
			timersDrain = 0,
		},
	}
end
resetMetrics()

-- Mock open TradeSkillFrame + instrumented C_TradeSkillUI & Classic TradeSkill APIs (300 recipes)
local mockTSFrame = CreateFrame("Frame", "BenchTradeSkillFrame", UIParent)
mockTSFrame:SetSize(420, 480)
mockTSFrame:Show()
_G.TradeSkillFrame = mockTSFrame
_G.ProfessionsFrame = nil
_G.CraftFrame = nil

_G.C_TradeSkillUI = {
	GetBaseProfessionInfo = function()
		metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
		metrics.tsGetBaseProf = metrics.tsGetBaseProf + 1
		return { professionID = 171, professionName = "Alchemy", skillLevel = 300, maxSkillLevel = 300 }
	end,
	GetAllRecipeIDs = function()
		metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
		metrics.tsGetAllRecipeIDs = metrics.tsGetAllRecipeIDs + 1
		return recipeIds300
	end,
	GetRecipeInfo = function(id)
		metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
		metrics.tsGetRecipeInfo = metrics.tsGetRecipeInfo + 1
		local r = recipesById[id]
		if not r then return nil end
		return { recipeID = r.spellID, name = r.name, learned = r.learned, difficulty = r.difficulty }
	end,
	GetRecipeOutputItemData = function(id)
		metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
		metrics.tsGetRecipeOutput = metrics.tsGetRecipeOutput + 1
		local r = recipesById[id]
		if not r then return nil end
		return { itemID = r.outputID }
	end,
	GetRecipeSchematic = function(id)
		metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
		metrics.tsGetRecipeSchematic = metrics.tsGetRecipeSchematic + 1
		local r = recipesById[id]
		if not r then return nil end
		return { recipeID = r.spellID, quantityMin = r.numMade, quantityMax = r.numMade }
	end,
	OpenRecipe = function()
		metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
	end,
	CraftRecipe = function() end,
}

_G.GetTradeSkillLine = function()
	metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
	metrics.tsClassicCalls = metrics.tsClassicCalls + 1
	return "Alchemy", 300, 300
end
_G.GetNumTradeSkills = function()
	metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
	metrics.tsClassicCalls = metrics.tsClassicCalls + 1
	return #recipes300
end
_G.GetTradeSkillInfo = function(i)
	metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
	metrics.tsClassicCalls = metrics.tsClassicCalls + 1
	local r = recipes300[i]
	if not r then return nil end
	return r.name, r.difficulty, 10, false
end
_G.GetTradeSkillRecipeLink = function(i)
	metrics.tradeskillApiCalls = metrics.tradeskillApiCalls + 1
	metrics.tsClassicCalls = metrics.tsClassicCalls + 1
	local r = recipes300[i]
	if not r then return nil end
	return "|cffffd000|Henchant:" .. tostring(r.spellID) .. "|h[" .. r.name .. "]|h|r"
end
_G.SelectTradeSkill = function() end
_G.DoTradeSkill = function() end

-- Instrumented bag/container APIs (60 items across 5 bags)
_G.C_Container = {
	GetContainerNumSlots = function(b)
		metrics.containerApiCalls = metrics.containerApiCalls + 1
		if b == 0 then
			metrics.bagScanCalls = metrics.bagScanCalls + 1
		end
		if b >= 0 and b <= 4 then return 16 end
		return 0
	end,
	GetContainerItemInfo = function(b, s)
		metrics.containerApiCalls = metrics.containerApiCalls + 1
		local bag = bagState[b]
		return bag and bag[s] or nil
	end,
	GetContainerItemID = function(b, s)
		metrics.containerApiCalls = metrics.containerApiCalls + 1
		local bag = bagState[b]
		local cell = bag and bag[s]
		return cell and cell.itemID or nil
	end,
	GetContainerItemLink = function(b, s)
		local bag = bagState[b]
		local cell = bag and bag[s]
		if not cell then return nil end
		local nm = (ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[cell.itemID]) or ("Item " .. cell.itemID)
		return "|cffffffff|Hitem:" .. tostring(cell.itemID) .. "::::::::60:::::::|h[" .. nm .. "]|h|r"
	end,
	GetContainerNumFreeSlots = function() return 4, 0 end,
	UseContainerItem = function() end,
}
_G.GetItemCount = function(itemID)
	return bagItemTotals[tonumber(itemID)] or 0
end

-- Wrap hot addon functions cleanly (observe-only, zero behavior change)
-- 1. RENDER_CALLS via cartBuyerModal.progressBar.SetValue (invoked exactly once per renderCartBuyer() call,
--    including both direct modal.Render() calls AND onFlowStateUpdated() / debounced timer callbacks)
local origProgSetValue = assert(modal.progressBar and modal.progressBar.SetValue, "cartBuyerModal.progressBar.SetValue missing")
modal.progressBar.SetValue = function(self, ...)
	metrics.renderCalls = metrics.renderCalls + 1
	return origProgSetValue(self, ...)
end

-- 2. OrderFlow.ComputeTaskReadiness
local origComputeReadiness = assert(of.ComputeTaskReadiness, "OrderFlow.ComputeTaskReadiness missing")
of.ComputeTaskReadiness = function(...)
	metrics.readinessCalls = metrics.readinessCalls + 1
	return origComputeReadiness(...)
end

-- 3. OrderFlow.GetAllDestinations
local origGetAllDestinations = assert(of.GetAllDestinations, "OrderFlow.GetAllDestinations missing")
of.GetAllDestinations = function(...)
	metrics.destinationsCalls = metrics.destinationsCalls + 1
	return origGetAllDestinations(...)
end

-- 4. Analytics.Inventory.ScanCurrentChar
local invMod = ns.Analytics and ns.Analytics.Inventory
if invMod and invMod.ScanCurrentChar then
	local origScanChar = invMod.ScanCurrentChar
	invMod.ScanCurrentChar = function(...)
		metrics.inventoryScanCalls = metrics.inventoryScanCalls + 1
		return origScanChar(...)
	end
end

-- Build 6 queued Stage 4 craft tasks in OrderFlow (3-4 crafts each = 20+ total crafts so 10 finishes span multiple tasks)
local function setupCraftSession()
	resetBags()
	clearTimers()
	app.setBuiltInAHBuyer(true)
	MerchantMasterDB.ahBuyerExtended = true
	if app.panel and app.panel.Hide then app.panel:Hide() end

	local rows = {}
	for i, taskRec in ipairs(alchemyTasks) do
		local gKey = "bench_g" .. tostring(i)
		local neededCrafts = (i <= 2) and 4 or 3
		rows[#rows + 1] = {
			isMainRow = true,
			mainGroupKey = gKey,
			name = taskRec.name,
			itemID = taskRec.outputID,
			spellID = taskRec.spellID,
			prof = "alchemy",
			qty = neededCrafts,
			sourceKind = "craft_order",
			sourceLabel = "Crafting Order",
			reagents = taskRec.reagents,
		}
		for _, rg in ipairs(taskRec.reagents) do
			rows[#rows + 1] = {
				indent = 1,
				mainGroupKey = gKey,
				name = rg.name,
				itemID = rg.itemID,
				qty = 0,
				ownedUsed = rg.qty * neededCrafts,
				categoryName = taskRec.name,
			}
		end
	end

	local counts = of.LoadFromShoppingRows(rows, {
		title = "Bench Craft Session",
		ownershipProvider = function(id)
			return { bags = bagItemTotals[id] or 0, bank = 0, mail = 0, alts = {} }
		end,
	})
	assert(counts.craft == 6, "Expected 6 craft tasks queued, got " .. tostring(counts.craft))

	-- Prime initial state: open TradeSkillFrame + cartBuyerModal on Stage 4 craft with cbExtended=true
	mockTSFrame:Show()
	app.enterOrderFlowMode("craft")
	modal.SetExtended(true, true)
	fireEvent("TRADE_SKILL_SHOW")
	fireEvent("BAG_UPDATE_DELAYED")
	drainTimersTo(simNow + 1.0)

	-- Reset throttle timers cleanly so craft #1 starts cleanly after +4.0s
	app._lastTradeSkillScanTime = simNow
	if ns.ProfessorApp then ns.ProfessorApp._lastTradeSkillCacheTime = simNow end
end

local function runOneBenchmarkPass()
	setupCraftSession()
	resetMetrics()

	local tTotalStart = os.clock()
	for craftNum = 1, 10 do
		-- Advance virtual clock by +4.0s (realistic 3-4s craft cast; expires 3.0s TRADE_SKILL_UPDATE throttle)
		simNow = simNow + 4.0

		local st = of.GetState()
		local crSt = st and st.stages and st.stages.craft
		local activeTask = crSt and crSt.tasks and crSt.tasks[crSt.activeIndex]
		assert(activeTask ~= nil, "Active craft task missing at craft #" .. tostring(craftNum))
		local spellID = activeTask.spellID
		local rec = recipesById[spellID]

		-- Realistic bag mutation on craft completion (consume reagents, produce output item)
		if rec then
			for _, rg in ipairs(rec.reagents or {}) do
				adjustBagItem(rg.itemID, -(rg.qty or 1))
			end
			adjustBagItem(rec.outputID, rec.numMade or 1)
		end

		-- Phase 1: UNIT_SPELLCAST_SUCCEEDED("player", nil, spellID)
		local t0 = os.clock()
		fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "bench-cast-" .. craftNum, spellID)
		metrics.phaseMs.spellcast = metrics.phaseMs.spellcast + (os.clock() - t0) * 1000.0

		-- Phase 2: TRADE_SKILL_UPDATE x3 (real Blizzard burst on craft completion)
		local t1 = os.clock()
		fireEvent("TRADE_SKILL_UPDATE")
		fireEvent("TRADE_SKILL_UPDATE")
		fireEvent("TRADE_SKILL_UPDATE")
		metrics.phaseMs.tradeskillUpdate = metrics.phaseMs.tradeskillUpdate + (os.clock() - t1) * 1000.0

		-- Phase 3: BAG_UPDATE_DELAYED
		local t2 = os.clock()
		fireEvent("BAG_UPDATE_DELAYED")
		metrics.phaseMs.bagUpdate = metrics.phaseMs.bagUpdate + (os.clock() - t2) * 1000.0

		-- Phase 4: Drain any deferred timers scheduled for this craft tick (+0.5s)
		local t3 = os.clock()
		drainTimersTo(simNow + 0.5)
		metrics.phaseMs.timersDrain = metrics.phaseMs.timersDrain + (os.clock() - t3) * 1000.0
	end
	local totalMs = (os.clock() - tTotalStart) * 1000.0

	return {
		totalMs = totalMs,
		avgCraftMs = totalMs / 10.0,
		renderCalls = metrics.renderCalls,
		tradeskillApiCalls = metrics.tradeskillApiCalls,
		tsGetAllRecipeIDs = metrics.tsGetAllRecipeIDs,
		tsGetRecipeInfo = metrics.tsGetRecipeInfo,
		tsGetRecipeOutput = metrics.tsGetRecipeOutput,
		tsGetRecipeSchematic = metrics.tsGetRecipeSchematic,
		tsGetBaseProf = metrics.tsGetBaseProf,
		tsClassicCalls = metrics.tsClassicCalls,
		readinessCalls = metrics.readinessCalls,
		destinationsCalls = metrics.destinationsCalls,
		bagScanCalls = metrics.bagScanCalls,
		inventoryScanCalls = metrics.inventoryScanCalls,
		containerApiCalls = metrics.containerApiCalls,
		phaseMs = {
			spellcast = metrics.phaseMs.spellcast,
			tradeskillUpdate = metrics.phaseMs.tradeskillUpdate,
			bagUpdate = metrics.phaseMs.bagUpdate,
			timersDrain = metrics.phaseMs.timersDrain,
		},
	}
end

-- 3 warmup runs + 3 measured runs
for w = 1, 3 do
	runOneBenchmarkPass()
end

local runs = {}
for r = 1, 3 do
	collectgarbage("collect")
	local res = runOneBenchmarkPass()
	runs[r] = res
	print(string.format(
		"RUN_%d: TOTAL_MS=%.2f AVG_CRAFT_MS=%.2f RENDER_CALLS=%d TRADESKILL_API_CALLS=%d READINESS_CALLS=%d DESTINATIONS_CALLS=%d BAG_SCAN_CALLS=%d (INV_SCAN=%d CONT_API=%d) | PHASES_MS: spellcast=%.2f ts_upd3=%.2f bag_upd=%.2f timers=%.2f",
		r, res.totalMs, res.avgCraftMs, res.renderCalls, res.tradeskillApiCalls,
		res.readinessCalls, res.destinationsCalls, res.bagScanCalls,
		res.inventoryScanCalls, res.containerApiCalls,
		res.phaseMs.spellcast, res.phaseMs.tradeskillUpdate, res.phaseMs.bagUpdate, res.phaseMs.timersDrain
	))
end

-- Compute median by totalMs across the 3 measured runs
local sorted = { runs[1], runs[2], runs[3] }
table.sort(sorted, function(a, b) return a.totalMs < b.totalMs end)
local med = sorted[2]

print(string.format(
	"MEDIAN: TOTAL_MS=%.2f AVG_CRAFT_MS=%.2f RENDER_CALLS=%d TRADESKILL_API_CALLS=%d READINESS_CALLS=%d DESTINATIONS_CALLS=%d BAG_SCAN_CALLS=%d",
	med.totalMs, med.avgCraftMs, med.renderCalls, med.tradeskillApiCalls,
	med.readinessCalls, med.destinationsCalls, med.bagScanCalls
))
print(string.format(
	"BREAKDOWN: PHASE_SPELLCAST_MS=%.2f PHASE_TS_UPDATE_MS=%.2f PHASE_BAG_UPDATE_MS=%.2f PHASE_TIMERS_MS=%.2f | TS_GET_ALL=%d TS_GET_INFO=%d TS_GET_OUT=%d TS_GET_SCHEM=%d TS_BASE_PROF=%d TS_CLASSIC=%d | INV_SCANS=%d CONTAINER_CALLS=%d",
	med.phaseMs.spellcast, med.phaseMs.tradeskillUpdate, med.phaseMs.bagUpdate, med.phaseMs.timersDrain,
	med.tsGetAllRecipeIDs, med.tsGetRecipeInfo, med.tsGetRecipeOutput, med.tsGetRecipeSchematic,
	med.tsGetBaseProf, med.tsClassicCalls, med.inventoryScanCalls, med.containerApiCalls
))
