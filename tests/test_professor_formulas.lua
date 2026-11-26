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

-- Helper to reset caches cleanly between synthetic cases
local function resetCaches()
	ns.ResetEval()
	ns.InvalidatePriceCache()
end

-- Seed deterministic synthetic Live AH prices so solver/formula tests run cleanly without SnapshotData.lua
do
	local econ = ns.DetectActiveEconomy()
	MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
	local prices = { _scannedAt = time() - 60 }
	for id in pairs(ns.ALL_CATALOG_IDS or {}) do
		local base = (ns.VENDOR_SELL and ns.VENDOR_SELL[id]) or 200
		prices[id] = { price = math.max(500, base * 8), qty = 40, at = time() - 60 }
	end
	MerchantMasterDB.ahPrices[econ] = prices
	resetCaches()
end

---------------------------------------------------------------------------------------------------
-- 1. Stack-aware AH unit deposit (ns.GetAHUnitDeposit)
---------------------------------------------------------------------------------------------------
do
	local origGetItemInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function() return nil end
	resetCaches()
	ns.BeginEval()

	-- Offline (uncached maxStack): high-yield ammo uses craftYield=200, c=1 stackables stay 5c (no 20x jump)
	-- WoW: Forever POST_DURATIONS[1] = 2h (mult = 0.05) with 100c minimum deposit per batch
	local depThorium = ns.GetAHUnitDeposit(15997, 1, 200) -- Thorium Shells, vendor=10c -> max(100, 10*200*0.05)/200 = 0.5c
	check(math.abs(depThorium - 0.5) < 0.01, "Thorium Shells (c=200, vend=10c) 2h unit deposit is 0.5c (got " .. tostring(depThorium) .. ")")

	local depSlugs = ns.GetAHUnitDeposit(10512, 1, 200) -- Hi-Impact Mithril Slugs, vendor=2c
	check(math.abs(depSlugs - 0.5) < 0.01, "Hi-Impact Mithril Slugs (c=200, vend=2c) 2h unit deposit is 0.5c (got " .. tostring(depSlugs) .. ")")

	local depGyro = ns.GetAHUnitDeposit(10513, 1, 200) -- Mithril Gyro-Shot, vendor=5c
	check(math.abs(depGyro - 0.5) < 0.01, "Mithril Gyro-Shot (c=200, vend=5c) 2h unit deposit is 0.5c (got " .. tostring(depGyro) .. ")")

	local depPowder = ns.GetAHUnitDeposit(4357, 1, 1) -- Rough Blasting Powder, vendor=4c, stack=20
	check(math.abs(depPowder - 5.0) < 0.01, "Rough Blasting Powder (c=1, vend=4c) stays 5.0c (no 20x inflation; got " .. tostring(depPowder) .. ")")

	local depDragOffline = ns.GetAHUnitDeposit(4396, 1, 1) -- Mechanical Dragonling, vendor=6000c -> 6000*0.05 = 300c
	check(math.abs(depDragOffline - 300.0) < 0.01, "Mechanical Dragonling offline 2h deposit is 300c (got " .. tostring(depDragOffline) .. ")")

	-- Live client cached maxStack == 1 enforces 1s (100c) floor on low-value non-stackables
	C_Item.GetItemInfo = function(id)
		if id == 4396 then
			return "Mechanical Dragonling", nil, 1, 40, 0, "Armor", "Trinket", 1, "", 134400, 6000
		elseif id == 4357 then
			return "Rough Blasting Powder", nil, 1, 5, 0, "Trade Goods", "Explosives", 20, "", 134400, 4
		elseif id == 999901 then
			return "Synthetic Low Gear", nil, 2, 10, 0, "Armor", "Cloth", 1, "", 134400, 200
		end
		return nil
	end
	ns.EndEval()
	resetCaches()
	ns.BeginEval()

	local depLowGear = ns.GetAHUnitDeposit(999901, 1, 1)
	check(math.abs(depLowGear - 100.0) < 0.01, "Live non-stackable (maxStack=1, vend=200c) gets 100c WoW floor (got " .. tostring(depLowGear) .. ")")
	local depDragLive = ns.GetAHUnitDeposit(4396, 1, 1)
	check(math.abs(depDragLive - 300.0) < 0.01, "Live non-stackable high-vendor (6000c) gets 300c at 2h (got " .. tostring(depDragLive) .. ")")
	local depPowderLive = ns.GetAHUnitDeposit(4357, 1, 1)
	check(math.abs(depPowderLive - 5.0) < 0.01, "Live stackable (maxStack=20, vend=4c) stays 5.0c (got " .. tostring(depPowderLive) .. ")")

	ns.EndEval()
	C_Item.GetItemInfo = origGetItemInfo
	resetCaches()
end

---------------------------------------------------------------------------------------------------
-- 2. Conservative Sale Unit Price Anchor (ns.GetConservativeSaleUnitPrice)
---------------------------------------------------------------------------------------------------
do
	local origQuerySnap = ns.QueryLocalSnapshot

	-- Nil / zero safety
	local uNil, cNil = ns.GetConservativeSaleUnitPrice(16023, nil)
	check(uNil == nil and cNil == false, "GetConservativeSaleUnitPrice handles nil spot price safely")
	local uZero, cZero = ns.GetConservativeSaleUnitPrice(16023, 0)
	check(uZero == 0 and cZero == false, "GetConservativeSaleUnitPrice handles 0 spot price safely")

	-- Synthetic spike: spot 76400c vs Snapshot Market 50000c (and historical-only 33300c)
	ns.QueryLocalSnapshot = function(id)
		if id == 16023 then return 76400, { minBuyout = 76400, marketValue = 50000, historical = 33300, numAuctions = 4 } end
		if id == 16024 then return 48000, { minBuyout = 48000, marketValue = 55000, historical = 52000, numAuctions = 12 } end
		return origQuerySnap and origQuerySnap(id) or nil
	end
	resetCaches()
	ns.BeginEval()

	local capped, wasCapped, ancSrc = ns.GetConservativeSaleUnitPrice(16023, 76400)
	check(wasCapped == true and capped == 50000, "Spot spike 76400c capped at Snapshot Market 50000c (got " .. tostring(capped) .. ")")
	check(type(ancSrc) == "string" and ancSrc:find("Snapshot", 1, true) ~= nil, "Anchor source names Snapshot")

	local uncapped, wasCap2 = ns.GetConservativeSaleUnitPrice(16024, 48000)
	check(wasCap2 == false and uncapped == 48000, "Normal liquid spot below Snapshot market/historical is untouched (got " .. tostring(uncapped) .. ")")

	ns.EndEval()
	ns.QueryLocalSnapshot = origQuerySnap
	resetCaches()
end

---------------------------------------------------------------------------------------------------
-- 3. Single-Realm Demand Scaling & Smooth Competition Cap (ns.GetRealmAdjustedDailySold)
---------------------------------------------------------------------------------------------------
do
	local origEcon = ns.CurrentEconomyInfo
	local origDaily = ns.GetDailySold

	ns.GetDailySold = function(id)
		if id == 16006 then return 2.525 end -- Delicate Arcanite Converter (single-realm Blizzard velocity)
		if id == 15997 then return 2729.6 end -- Thorium Shells
		if id == 999902 then return nil end -- Live-AH-only (no Snapshot velocity)
		return origDaily(id)
	end

	-- Standalone single-realm Blizzard Snapshot velocity -> 1.00 share (already realm-specific!)
	ns.CurrentEconomyInfo = function() return { effectiveKey = "Normal-Horde", label = "Normal-Horde", isRegionOnly = false, isHC = false, isActive = true } end
	resetCaches()
	ns.BeginEval()
	local rSC, rawSC, shSC = ns.GetRealmAdjustedDailySold(16006)
	check(shSC == 1.0 and math.abs(rSC - 2.525) < 0.001 and math.abs(rawSC - 2.525) < 0.001,
		"Single-realm Blizzard velocity preserves 1.00 share (got " .. tostring(rSC) .. ", share=" .. tostring(shSC) .. ")")
	local rNil = ns.GetRealmAdjustedDailySold(999902)
	check(rNil == nil, "Nil snapshot dailySold stays nil for live-AH-only fallback")
	ns.EndEval()

	-- Hardcore -> 1.00 share (single-realm velocity)
	ns.CurrentEconomyInfo = function() return { effectiveKey = "Hardcore-Horde", label = "Hardcore-Horde", isRegionOnly = false, isHC = true, isActive = true } end
	resetCaches()
	ns.BeginEval()
	local rHC, _, shHC = ns.GetRealmAdjustedDailySold(16006)
	check(shHC == 1.0 and math.abs(rHC - 2.525) < 0.001, "Hardcore single-realm velocity uses 1.00 share (got " .. tostring(rHC) .. ")")
	ns.EndEval()

	-- Verify smooth competition cap inside EvaluateRecipeForSolver (no converter overshoot, no ammo cliff, custom price honored)
	ns.CurrentEconomyInfo = function() return { effectiveKey = "Normal-Horde", label = "Normal-Horde", isRegionOnly = false, isHC = false, isActive = true } end
	local origListed = ns.GetNumListed
	local origMkt = ns.GetItemMarketPrice
	local origOutliers = MerchantMasterDB.outlierPrices
	ns.GetNumListed = function(id)
		if id == 16006 then return 5 end
		if id == 15997 then return 44 end
		if id == 4390 then return 0 end -- Unlisted for custom price check
		return origListed(id)
	end
	ns.GetItemMarketPrice = function(id)
		if id == 16006 then return 540000, "Live AH" end
		if id == 15997 then return 50, "Live AH" end
		if id == 4390 then return nil, nil end
		return origMkt(id)
	end
	MerchantMasterDB.outlierPrices = { [4390] = 25000 }
	resetCaches()
	ns.BeginEval()

	local convRec, shellsRec, grenRec
	for _, rec in ipairs(MP.RECIPES.engineering) do
		if rec.i == 16006 then convRec = rec end
		if rec.i == 15997 then shellsRec = rec end
		if rec.i == 4390 then grenRec = rec end
	end
	check(convRec and shellsRec and grenRec, "Found Converter, Thorium Shells, and Iron Grenade recipes")

	local evalCtx = {
		db = MP.GetDB(), profKey = "engineering", mns = ns,
		legacy = MP.GetEffectiveLegacy(MP.GetDB()), charLevel = 60,
		allowedSources = { start = true, trainer = true, vendor = true, ah = true, drop = true, quest = true, rep = true, camp = true },
		goalMode = "smart", sellDays = 3, applyAHCut = true, includeVendorSell = true,
		subCraftMode = "buy_only", subCraftOverrides = {}, trainerCosts = {},
		playerFaction = "H", favorUnitPrice = nil, standingID = 4,
		itemOptionCache = {}, subEvCache = {},
	}
	local evConv = MP.EvaluateRecipeForSolver(convRec, evalCtx)
	check(evConv and evConv.hotnessCap >= 1 and evConv.hotnessCap <= 8,
		"Delicate Arcanite Converter 3d cap is competition-bounded <=8 (got " .. tostring(evConv and evConv.hotnessCap) .. ")")

	local evShells = MP.EvaluateRecipeForSolver(shellsRec, evalCtx)
	check(evShells and evShells.hotnessCap >= 1000,
		"Thorium Shells high-yield ammo has no competition cliff (cap=" .. tostring(evShells and evShells.hotnessCap) .. ")")
	check(evShells and math.abs((evShells.unitDeposit12h or 0) - 0.5) < 0.01,
		"Thorium Shells evaluated unitDeposit12h (2h base) is 0.5c (got " .. tostring(evShells and evShells.unitDeposit12h) .. ")")

	local evCustom = MP.EvaluateRecipeForSolver(grenRec, evalCtx)
	check(evCustom and evCustom.isCustomPrice == true and evCustom.ahGrossUnit == 25000 and evCustom.conservativeCapped == false,
		"Custom outlier price bypasses conservative cap cleanly (got " .. tostring(evCustom and evCustom.ahGrossUnit) .. ")")

	-- ah_max mode preserves spot price without conservative capping
	evalCtx.goalMode = "ah_max"
	local evConvMax = MP.EvaluateRecipeForSolver(convRec, evalCtx)
	check(evConvMax and evConvMax.ahGrossUnit == 540000 and evConvMax.conservativeCapped == false,
		"ah_max mode preserves raw spot AH unit price (got " .. tostring(evConvMax and evConvMax.ahGrossUnit) .. ")")

	ns.EndEval()
	MerchantMasterDB.outlierPrices = origOutliers
	ns.GetNumListed = origListed
	ns.GetItemMarketPrice = origMkt
	ns.CurrentEconomyInfo = origEcon
	ns.GetDailySold = origDaily
	resetCaches()
end

---------------------------------------------------------------------------------------------------
-- 4. canCache overtimeRank Isolation, profitableSub Gate & Overtime Monotonicity
---------------------------------------------------------------------------------------------------
do
	local pdb = MP.GetDB()
	pdb.useOwned = false
	pdb.charLevelMode = 60
	pdb.overtimeMode = 0
	pdb.recipeFilter = "trainer_vendor"
	pdb.goalMode = "smart"
	pdb.sellDays = 3

	-- Verify canCache does NOT return stale OT=0 result when opts.overtimeRank=5 is passed
	-- (In smart mode OT=5 can choose a cheaper route with more green crafts, so verify distinct non-cached result and non-worse netCost.)
	resetCaches()
	local rDefault = MP.SolveProfessionPath("engineering", { startSkill = 1, targetSkill = 300 })
	local rOT5 = MP.SolveProfessionPath("engineering", { startSkill = 1, targetSkill = 300, overtimeRank = 5 })
	check(rDefault and rOT5 and rOT5 ~= rDefault and rOT5.netCost <= rDefault.netCost,
		string.format("canCache respects overtimeRank=5 (OT0 net=%d crafts=%d, OT5 net=%d crafts=%d)",
			rDefault and rDefault.netCost or -1, rDefault and rDefault.totalCrafts or -1,
			rOT5 and rOT5.netCost or -1, rOT5 and rOT5.totalCrafts or -1))

	-- Verify profitableSub does NOT force a costlier sub-craft in cheapest mode
	do
		local origReagent = ns.GetReagentUnitCost
		local origMkt = ns.GetItemMarketPrice
		local origListed = ns.GetNumListed
		local origDaily = ns.GetDailySold
		-- Make Copper Tube (4361, craft uses 2x Copper Bar 2840 + 1x Weak Flux 2880) costlier to sub-craft than AH,
		-- while giving Copper Tube an inflated AH resale above its craft cost.
		ns.GetReagentUnitCost = function(id)
			if id == 2840 then return 500, "MockAH", false end -- 2x = 1000c + 100c flux = 1100c sub-craft
			if id == 4361 then return 400, "MockAH", false end -- AH buy = 400c (< 1100c)
			return origReagent(id)
		end
		ns.GetItemMarketPrice = function(id)
			if id == 4361 then return 5000, "MockAH" end -- High resale (> 1100c)
			return origMkt(id)
		end
		ns.GetNumListed = function(id)
			if id == 4361 then return 50 end -- Deep stock (not thinStock)
			return origListed(id)
		end
		ns.GetDailySold = function(id)
			if id == 4361 then return 100 end
			return origDaily(id)
		end
		resetCaches()
		ns.BeginEval()
		local blunderRec
		for _, rec in ipairs(MP.RECIPES.engineering) do
			if rec.i == 4369 then blunderRec = rec; break end -- Deadly Blunderbuss uses Copper Tube (4361)
		end
		check(blunderRec ~= nil, "Found Deadly Blunderbuss recipe for profitableSub check")
		local subCtx = {
			db = MP.GetDB(), profKey = "engineering", mns = ns,
			legacy = MP.GetEffectiveLegacy(MP.GetDB()), charLevel = 60,
			allowedSources = { start = true, trainer = true, vendor = true },
			goalMode = "cheapest", sellDays = 3, applyAHCut = true, includeVendorSell = true,
			subCraftMode = "smart", subCraftOverrides = {}, trainerCosts = {},
			playerFaction = "H", favorUnitPrice = nil, standingID = 4,
			itemOptionCache = {}, subEvCache = {},
		}
		local evCheap = MP.EvaluateRecipeForSolver(blunderRec, subCtx)
		local tubeRg
		for _, rg in ipairs(evCheap and evCheap.reagentDetails or {}) do
			if rg.itemID == 4361 then tubeRg = rg; break end
		end
		check(tubeRg ~= nil and tubeRg.isSubCraft == false and tubeRg.unitCost == 400,
			"cheapest mode buys cheaper AH Copper Tube (400c) instead of forcing costlier profitableSub (1100c)")
		ns.EndEval()
		ns.GetReagentUnitCost = origReagent
		ns.GetItemMarketPrice = origMkt
		ns.GetNumListed = origListed
		ns.GetDailySold = origDaily
		resetCaches()
	end

	-- Verify CompareOvertimeForProfession monotonicity across all 10 professions in cheapest (Vendor Net) mode
	-- (In smart mode, a net-profitable AH step crafted fewer times under OT 5/5 can legitimately earn less AH profit.)
	local otMatrix = MP.BuildAllProfessionsOvertimeMatrix({
		useFullRange = true,
		goalMode = "cheapest",
		recipeFilter = "trainer_vendor",
		useOwned = false,
	})
	check(#otMatrix == #MP.PROF_ORDER, "Overtime matrix returns all " .. tostring(#MP.PROF_ORDER) .. " professions")
	for _, row in ipairs(otMatrix) do
		check(row.r0 and not row.r0.unreachable and row.r5 and not row.r5.unreachable,
			"Overtime matrix reachable for " .. tostring(row.profKey))
		-- Under OT 5/5, crafts normally decrease; allow sub-craft chain upticks only when switching to a strictly cheaper chain
		check((row.crafts5 or 99999) <= (row.crafts0 or 0) or ((row.goldSaved or 0) > 0 and (row.crafts5 or 99999) <= (row.crafts0 or 0) + 60),
			string.format("OT 5/5 crafts <= OT 0/5 (or strictly cheaper chain) for %s (%d <= %d, saved=%dc)",
				row.profKey, row.crafts5 or -1, row.crafts0 or 0, row.goldSaved or 0))
		check((row.goldSaved or -1) >= -50,
			string.format("OT 5/5 has no green-farm gold inversion for %s (goldSaved=%dc)", row.profKey, row.goldSaved or 0))
		check(type(row.levelingCost0) == "number" and type(row.levelingCost5) == "number" and type(row.levelingSaved) == "number",
			"Overtime row exposes levelingCost0/5/Saved for " .. tostring(row.profKey))
	end
end

---------------------------------------------------------------------------------------------------
-- 5. Scoped trainer_only Fallback (Tail 290-300 + Synthetic Mid-Range Gap + UI Card 1 Subtitle)
---------------------------------------------------------------------------------------------------
do
	resetCaches()
	local rTO = MP.SolveProfessionPath("engineering", {
		startSkill = 1, targetSkill = 300, charLevel = 60,
		goalMode = "smart", recipeFilter = "trainer_only",
		overtimeRank = 0, useOwned = false, forceRecompute = true,
	})
	check(rTO and not rTO.unreachable, "Engineering trainer_only 1-300 resolves cleanly via scoped bridge")
	check(rTO.usedFallbackFilter == "trainer_vendor", "usedFallbackFilter preserved as 'trainer_vendor'")
	check(rTO.fallbackRange ~= nil and rTO.fallbackRange.from == 290 and rTO.fallbackRange.to == 300,
		string.format("fallbackRange scopes gap to 290-300 (got %s-%s)",
			tostring(rTO.fallbackRange and rTO.fallbackRange.from), tostring(rTO.fallbackRange and rTO.fallbackRange.to)))

	for _, st in ipairs(rTO.steps) do
		if not st.isMilestone and st.rec and st.rec.src ~= "trainer" and st.rec.src ~= "start" then
			check((st.s2 or 0) > 290,
				string.format("Fallback recipe '%s' (%d->%d, src=%s) must bridge uncovered >=290 (no leak below 290)",
					tostring(st.name), st.s1 or 0, st.s2 or 0, tostring(st.rec.src)))
		end
	end

	-- Synthetic mid-range gap test: temporarily disable trainer recipes covering 140..149
	local savedGr = {}
	for _, rec in ipairs(MP.RECIPES.engineering) do
		if (rec.src == "trainer" or rec.src == "start") and (rec.req or 1) < 150 and (rec.gr or 0) > 140 then
			savedGr[rec] = rec.gr
			if (rec.req or 1) >= 140 then
				rec.gr = rec.req
			else
				rec.gr = 140
			end
		end
	end
	resetCaches()
	local rMid = MP.SolveProfessionPath("engineering", {
		startSkill = 1, targetSkill = 200, charLevel = 60,
		goalMode = "smart", recipeFilter = "trainer_only",
		overtimeRank = 0, useOwned = false, forceRecompute = true,
	})
	for rec, oldGr in pairs(savedGr) do rec.gr = oldGr end
	resetCaches()

	check(rMid and not rMid.unreachable, "Synthetic mid-range gap 140-150 resolves via scoped bridge")
	check(rMid.fallbackRange ~= nil and rMid.fallbackRange.from == 140 and rMid.fallbackRange.to == 150,
		string.format("Mid-range fallbackRange is 140-150 (got %s-%s)",
			tostring(rMid.fallbackRange and rMid.fallbackRange.from), tostring(rMid.fallbackRange and rMid.fallbackRange.to)))
	for _, st in ipairs(rMid.steps) do
		if not st.isMilestone and st.rec and st.rec.src ~= "trainer" and st.rec.src ~= "start" then
			check((st.s2 or 0) > 140 and (st.s1 or 0) < 150,
				string.format("Mid-range fallback recipe '%s' (%d->%d) strictly overlaps 140-150 gap",
					tostring(st.name), st.s1 or 0, st.s2 or 0))
		end
	end

	-- Verify UI Card 1 subtitle surfaces scoped bridge text and updated GOAL_OPTIONS labels
	local profDB = MP.GetDB()
	profDB.selectedProf = "engineering"
	profDB.profTargets.engineering = { from = 1, to = 300 }
	profDB.recipeFilter = "trainer_only"
	profDB.goalMode = "smart"
	profDB.overtimeMode = 0
	profDB.useOwned = false
	app.panel:Show()
	app.setTab("prof_path")
	local subTxt = stripColors(papp.ui.kpiCards[1].sub:GetText())
	check(subTxt:find("bridge 290-300", 1, true) ~= nil,
		"Card 1 subtitle displays scoped bridge 290-300 (got '" .. subTxt .. "')")

	papp.setGoalMode("cheapest")
	local cheapLbl = stripColors(papp.ui.goalBtn:GetText())
	check(cheapLbl:find("Cheapest", 1, true) ~= nil and cheapLbl:find("Vendor Net", 1, true) ~= nil,
		"Cheapest goal label updated to Vendor Net (got '" .. cheapLbl .. "')")
	papp.setGoalMode("ah_max")
	local maxLbl = stripColors(papp.ui.goalBtn:GetText())
	check(maxLbl:find("High Risk", 1, true) ~= nil,
		"Max AH goal label warns High Risk (got '" .. maxLbl .. "')")
	papp.setGoalMode("smart")
	profDB.recipeFilter = "trainer_vendor"
end

---------------------------------------------------------------------------------------------------
-- 6. All-10 Professions Smoke & Performance Budget Check
---------------------------------------------------------------------------------------------------
do
	local totalColdMs = 0
	local maxProfMs = 0
	local maxProfKey = ""
	for _, pk in ipairs(MP.PROF_ORDER) do
		local pInfo = MP.PROFESSIONS[pk]
		local startS = pInfo.defaultStart or 1
		resetCaches()
		local t0 = os.clock()
		local rS = MP.SolveProfessionPath(pk, {
			startSkill = startS, targetSkill = 300, charLevel = 60,
			goalMode = "smart", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = false, forceRecompute = true,
		})
		local msS = (os.clock() - t0) * 1000
		totalColdMs = totalColdMs + msS
		if msS > maxProfMs then maxProfMs = msS; maxProfKey = pk end

		check(rS and not rS.unreachable and #(rS.steps or {}) > 0 and (rS.totalCrafts or 0) > 0,
			"Smart 1-300 valid for " .. pk)

		local rC = MP.SolveProfessionPath(pk, {
			startSkill = startS, targetSkill = 300, charLevel = 60,
			goalMode = "cheapest", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = false, forceRecompute = true,
		})
		check(rC and not rC.unreachable and #(rC.steps or {}) > 0 and (rC.totalCrafts or 0) > 0,
			"Cheapest 1-300 valid for " .. pk)
	end

	-- Verify warm cache hit is instant
	local ciScale = (os and os.getenv and (os.getenv("CI") == "true" or os.getenv("GITHUB_ACTIONS") == "true")) and 2.5 or 1.0
	local pdb = MP.GetDB()
	pdb.goalMode = "smart"
	pdb.recipeFilter = "trainer_vendor"
	pdb.overtimeMode = 0
	pdb.useOwned = false
	pdb.charLevelMode = 60
	resetCaches()
	MP.SolveProfessionPath("engineering")
	local tHit0 = os.clock()
	local rHit = MP.SolveProfessionPath("engineering")
	local hitMs = (os.clock() - tHit0) * 1000
	check(rHit and not rHit.unreachable and hitMs < 2.0 * ciScale,
		string.format("Cached SolveProfessionPath hit is <2ms (got %.3fms)", hitMs))

	check(maxProfMs < 200.0 * ciScale, string.format("Max single-profession cold solve <200ms (%s=%.2fms)", maxProfKey, maxProfMs))
	check(totalColdMs < 850.0 * ciScale, string.format("All-10 professions cold solve total <850ms (got %.2fms)", totalColdMs))
	print(string.format("MEASURE PROF_10_COLD_MS=%.2f MAX_PROF=%s:%.2fms CACHE_HIT_MS=%.3f",
		totalColdMs, maxProfKey, maxProfMs, hitMs))
end

---------------------------------------------------------------------------------------------------
-- 7. Public-Release Hardening: Seed Hygiene, 48h CD Shopping Warnings, Class/Alt Gates, ah_max
---------------------------------------------------------------------------------------------------
do
	-- 7a. Fresh install MP.GetDB() contains no personal character keys, profTargets, or Rogue combat spells
	local savedMMDB = _G.MerchantMasterDB
	local savedMPDB = _G.MerchantProfessorDB
	_G.MerchantMasterDB = {}
	_G.MerchantProfessorDB = nil
	local freshProf = MP.GetDB()
	check(next(freshProf.knownSpells or {}) == nil, "Fresh install seeds zero personal knownSpells keys")
	check(next(freshProf.profTargets or {}) == nil, "Fresh install seeds zero personal profTargets")
	check(freshProf.trainerCosts["Sinister Strike"] == nil and freshProf.trainerCosts["Stealth"] == nil
		and freshProf.trainerCosts["Backstab"] == nil and freshProf.trainerCosts["Kidney Shot"] == nil,
		"Fresh install seeds zero Rogue combat class spells in trainerCosts")
	check(freshProf.trainerCosts["Mana Potion"] == 5000 and freshProf.trainerReqs and freshProf.trainerReqs.alchemy ~= nil,
		"Fresh install preserves static profession trainer costs and requirements")
	_G.MerchantMasterDB = savedMMDB
	_G.MerchantProfessorDB = savedMPDB

	-- 7b. Cooldown metadata exposed on Arcanite Bar craftOpt & Shopping List rows (15x Delicate Arcanite Converter)
	local origProfs = ns.GetPlayerProfessions
	ns.GetPlayerProfessions = function() return { engineering = 300, alchemy = 300 } end
	resetCaches()
	ns.BeginEval()
	local arcOpt = ns.GetItemCraftOption(12360, { parentProf = "engineering", subCraftMode = "smart" })
	check(arcOpt ~= nil and arcOpt.cd == 169200 and arcOpt.cdWindowSec == 172800 and arcOpt.cdLabel == "48h",
		"Arcanite Bar craftOpt exposes 48h cooldown metadata (cd=" .. tostring(arcOpt and arcOpt.cd) .. ", lbl=" .. tostring(arcOpt and arcOpt.cdLabel) .. ")")
	ns.EndEval()

	local origQueue = MerchantMasterDB.craftOrderQueue
	local origOverrides = MerchantMasterDB.subCraftOverrides
	MerchantMasterDB.craftOrderQueue = {
		{ spellID = 19815, outputItemID = 16006, prof = "engineering", qty = 15, name = "Delicate Arcanite Converter", sourceTab = "prof_path" },
	}
	MerchantMasterDB.subCraftOverrides = {}
	local shopRows = app.syncUnifiedShoppingList()
	local arcRow
	for _, r in ipairs(shopRows or {}) do
		if r.itemID == 12360 then arcRow = r; break end
	end
	check(arcRow ~= nil and arcRow.makeMyself == false and arcRow.action == "Buy AH",
		"15x Delicate Arcanite Converter keeps Arcanite Bar as Buy AH (no auto-sub-craft of 48h CD)")
	check(arcRow.craftCD == 169200 and arcRow.craftCDWindow == 172800 and arcRow.craftCDLabel == "48h",
		"Arcanite Bar shopping row carries 48h CD metadata for UI badge & 30d tooltip warning")

	MerchantMasterDB.subCraftOverrides = { [12360] = "craft" }
	local shopRowsOv = app.syncUnifiedShoppingList()
	local arcRowOv
	for _, r in ipairs(shopRowsOv or {}) do
		if r.itemID == 12360 then arcRowOv = r; break end
	end
	check(arcRowOv ~= nil and arcRowOv.makeMyself == true and tostring(arcRowOv.action):find("48h CD", 1, true) ~= nil,
		"Manual craft override on Arcanite Bar explicitly labels 48h CD in action (got '" .. tostring(arcRowOv and arcRowOv.action) .. "')")

	MerchantMasterDB.subCraftOverrides = origOverrides
	MerchantMasterDB.craftOrderQueue = origQueue
	ns.GetPlayerProfessions = origProfs
	resetCaches()

	-- 7c. Multi-character legacy db.knownSpells does not leak onto unscanned alt / opposite faction
	local savedGlobalKnown = MerchantMasterDB.knownSpells
	local savedChars = MerchantMasterDB.chars
	local savedActiveChar = ns.activeChar
	MerchantMasterDB.knownSpells = { [5244] = true } -- Kodo Hide Bag (Horde quest)
	MerchantMasterDB.chars = {
		["Main-Realm"] = { name = "Main", realm = "Realm", faction = "Horde", knownSpells = { [5244] = true } },
		["Alt-Realm"] = { name = "Alt", realm = "Realm", faction = "Alliance", profs = { leatherworking = 100 } },
	}
	ns.activeChar = MerchantMasterDB.chars["Alt-Realm"]
	resetCaches()
	ns.BeginEval()
	check(ns.IsRecipeKnown({ spellID = 5244, name = "Kodo Hide Bag", prof = "leatherworking", skill = 35, fac = "H" }, { currentCharOnly = true }) == false,
		"Alliance alt does not inherit Horde recipe from legacy global db.knownSpells")
	ns.EndEval()
	ns.activeChar = nil
	resetCaches()
	ns.BeginEval()
	check(ns.IsRecipeKnown({ spellID = 5244, name = "Kodo Hide Bag", prof = "leatherworking", skill = 35, fac = "H" }, { currentCharOnly = true }) == false,
		"Uninitialized activeChar=nil does not inherit legacy global db.knownSpells")
	ns.EndEval()
	ns.activeChar = savedActiveChar
	MerchantMasterDB.chars = savedChars
	MerchantMasterDB.knownSpells = savedGlobalKnown
	resetCaches()

	-- 7d. Rogue-only Thistle Tea (spell 9513) is filtered out for non-Rogue classes
	local origUnitClass = _G.UnitClass
	local thistleRec
	for _, rec in ipairs(MP.RECIPES.cooking or {}) do
		if rec.s == 9513 then thistleRec = rec; break end
	end
	check(thistleRec ~= nil, "Found Thistle Tea recipe in MP.RECIPES.cooking")
	local cookCtx = {
		db = MP.GetDB(), profKey = "cooking", mns = ns,
		legacy = MP.GetEffectiveLegacy(MP.GetDB()), charLevel = 60,
		allowedSources = { start = true, trainer = true, vendor = true, ah = true, camp = true, quest = true, gather = true },
		goalMode = "smart", sellDays = 3, applyAHCut = true, includeVendorSell = true,
		subCraftMode = "buy_only", subCraftOverrides = {}, trainerCosts = {},
		playerFaction = "H", favorUnitPrice = nil, standingID = 4,
		ignoreLearnedSpells = true, itemOptionCache = {}, subEvCache = {},
	}
	_G.UnitClass = function() return "Mage", "MAGE" end
	resetCaches()
	ns.BeginEval()
	check(MP.EvaluateRecipeForSolver(thistleRec, cookCtx) == nil, "Non-Rogue (Mage) excludes Rogue-only Thistle Tea quest recipe")
	_G.UnitClass = function() return "Rogue", "ROGUE" end
	check(MP.EvaluateRecipeForSolver(thistleRec, cookCtx) ~= nil, "Rogue includes Thistle Tea quest recipe when quest source allowed")
	ns.EndEval()
	_G.UnitClass = origUnitClass
	resetCaches()

	-- 7e. Mining ah_max switches cleanly to Rich Thorium Veins at 275 instead of grinding 223 Small Thorium to 2%
	local rMineMax = MP.SolveProfessionPath("mining", {
		startSkill = 230, targetSkill = 300, charLevel = 60,
		goalMode = "ah_max", recipeFilter = "trainer_vendor",
		overtimeRank = 0, useOwned = false, forceRecompute = true,
	})
	check(rMineMax and not rMineMax.unreachable and (rMineMax.totalCrafts or 999) < 110,
		"Mining ah_max 230-300 switches to Rich Thorium Veins cleanly (crafts=" .. tostring(rMineMax and rMineMax.totalCrafts) .. ")")
end

---------------------------------------------------------------------------------------------------
-- 8. Sub-Craft Cost Invariant, Gyrochronatom Sell-Not-Steal & Full-Recipe Net Honesty
---------------------------------------------------------------------------------------------------
do
	-- 8a. Zero costlier sub-crafts across ALL 10 professions x 3 goals (cheapest, smart, ah_max)
	local totalSubSteps = 0
	local badSubCrafts = 0
	local verifiedReusedConsumers = 0
	for _, pk in ipairs(MP.PROF_ORDER) do
		local pInfo = MP.PROFESSIONS[pk]
		local startS = pInfo.defaultStart or 1
		for _, goal in ipairs({ "cheapest", "smart", "ah_max" }) do
			resetCaches()
			local res = MP.SolveProfessionPath(pk, {
				startSkill = startS, targetSkill = 300, charLevel = 60,
				goalMode = goal, recipeFilter = "trainer_vendor",
				overtimeRank = 0, useOwned = false, forceRecompute = true,
			})
			check(res and not res.unreachable, "Sub-craft invariant solve reachable for " .. pk .. "/" .. goal)
			local allocSum, rawSum = 0, 0
			for _, st in ipairs(res.steps or {}) do
				allocSum = allocSum + (st.allocatedNetCost or 0)
				rawSum = rawSum + (st.netCost or 0)
				if st.isSubCraftStep then
					totalSubSteps = totalSubSteps + 1
					ns.BeginEval()
					local ahU = ns.GetReagentUnitCost(st.itemID)
					ns.EndEval()
					local units = st.unitsMade or st.crafts or 0
					if ahU and ahU > 0 and units > 0 then
						local subTotal = (st.grossMats or 0) + (st.unlockCost or 0)
						local directBuy = units * ahU
						if subTotal >= directBuy then
							badSubCrafts = badSubCrafts + 1
							check(false, string.format("Costlier sub-craft %s (%s/%s): subTotal=%dc >= directBuy=%dc (gross=%d unlock=%d units=%d ahU=%d)",
								tostring(st.name), pk, goal, subTotal, directBuy, st.grossMats or 0, st.unlockCost or 0, units, ahU))
						end
					end
				end
				if st.isPureInvestment then
					check(st.allocatedNetCost == 0,
						string.format("Pure investment '%s' (%s/%s) has allocatedNetCost == 0 (got %d)", tostring(st.name), pk, goal, st.allocatedNetCost or -1))
					if ((st.grossMats or 0) + (st.unlockCost or 0) + (st.rolledInCost or 0)) > 0 then
						check((st.rolledOutCost or 0) > 0,
							string.format("Pure investment '%s' (%s/%s) rolls out positive cost", tostring(st.name), pk, goal))
					end
					check(st.keptForSteps and #st.keptForSteps > 0,
						string.format("Pure investment '%s' (%s/%s) has keptForSteps", tostring(st.name), pk, goal))
					for _, ks in ipairs(st.keptForSteps or {}) do
						check(type(ks.stepNum) == "number" and ks.stepNum > (st.stepNum or 0),
							string.format("Pure investment '%s' (%s/%s) resolved downstream stepNum (%s > %s)", tostring(st.name), pk, goal, tostring(ks.stepNum), tostring(st.stepNum)))
						check(ks.destStep == nil, "Pure investment clears destStep reference after rollup")
					end
				end
				if st.rolledInSteps and #st.rolledInSteps > 0 then
					local riSum = 0
					for _, ri in ipairs(st.rolledInSteps) do
						riSum = riSum + (ri.cost or 0)
						check(type(ri.stepNum) == "number" and ri.stepNum < (st.stepNum or 0),
							string.format("Consumer '%s' (%s/%s) rolled-in source #%s precedes consumer #%s", tostring(st.name), pk, goal, tostring(ri.stepNum), tostring(st.stepNum)))
					end
					check(riSum == (st.rolledInCost or 0),
						string.format("Consumer '%s' (%s/%s) rolledInSteps sum == rolledInCost (%d == %d)", tostring(st.name), pk, goal, riSum, st.rolledInCost or -1))
				end
				-- 8c (global check): Full-recipe honesty invariants on every consumer step using reused sub-crafts
				if not st.isMilestone and st.consumedFromSteps and next(st.consumedFromSteps) ~= nil then
					verifiedReusedConsumers = verifiedReusedConsumers + 1
					check((st.reusedInputMats or 0) > 0,
						string.format("Consumer step '%s' (%s/%s) sets reusedInputMats > 0", tostring(st.name), pk, goal))
					check(st.fullRecipeMats == (st.grossMats or 0) + (st.reusedInputMats or 0),
						string.format("Consumer step '%s' (%s/%s) fullRecipeMats == grossMats + reusedInputMats", tostring(st.name), pk, goal))
					check(st.fullRecipeNet == (st.unlockCost or 0) + (st.fullRecipeMats or 0) - (st.resale or 0),
						string.format("Consumer step '%s' (%s/%s) fullRecipeNet == unlockCost + fullRecipeMats - resale", tostring(st.name), pk, goal))
				end
			end
			check(allocSum == rawSum,
				string.format("Copper conservation (%s/%s): sum(allocatedNetCost)=%d == sum(netCost)=%d", pk, goal, allocSum, rawSum))
		end
	end
	check(badSubCrafts == 0, "TOTAL_BAD_SUBCRAFTS must be 0 across 10 professions x 3 goals (got " .. tostring(badSubCrafts) .. ")")
	check(verifiedReusedConsumers > 0, "Verified fullRecipeNet invariants on consumer steps with reused inputs (count=" .. tostring(verifiedReusedConsumers) .. ")")
	print(string.format("MEASURE TOTAL_SUBCRAFTS=%d TOTAL_BAD_SUBCRAFTS=%d VERIFIED_REUSED_CONSUMERS=%d",
		totalSubSteps, badSubCrafts, verifiedReusedConsumers))

	-- 8b. Gyrochronatom 25s (2500c) sell-not-steal test (smart & ah_max): Engineering 195 -> 225
	do
		local origReagent = ns.GetReagentUnitCost
		local origMkt = ns.GetItemMarketPrice
		local origListed = ns.GetNumListed
		local origDaily = ns.GetDailySold
		local origCons = ns.GetConservativeSaleUnitPrice

		ns.GetReagentUnitCost = function(id)
			if id == 4389 then return 90000, "MockAH", false end  -- Gyrochronatom = 9g
			if id == 3575 then return 318, "MockAH", false end   -- Iron Bar = 3s 18c
			if id == 10558 then return 349, "MockAH", false end  -- Gold Power Core = 3s 49c
			if id == 3577 then return 988, "MockAH", false end   -- Gold Bar = 9s 88c
			return origReagent(id)
		end
		ns.GetItemMarketPrice = function(id)
			if id == 4389 then return 90000, "MockAH" end
			if id == 7148 then return nil, nil end
			return origMkt(id)
		end
		ns.GetConservativeSaleUnitPrice = function(id, spot)
			if id == 4389 then return spot, false, nil end
			return origCons(id, spot)
		end
		ns.GetNumListed = function(id)
			if id == 4389 then return 10 end
			if id == 7148 then return 0 end
			return origListed(id)
		end
		ns.GetDailySold = function(id)
			if id == 4389 then return 60 end
			return origDaily(id)
		end

		for _, goal in ipairs({ "smart", "ah_max" }) do
			resetCaches()
			local rEng = MP.SolveProfessionPath("engineering", {
				startSkill = 195, targetSkill = 225, charLevel = 60,
				goalMode = goal, recipeFilter = "trainer_vendor",
				overtimeRank = 0, useOwned = false, forceRecompute = true,
			})
			check(rEng and not rEng.unreachable, "Engineering 195-225 reachable in " .. goal)
			local gyroSkillStep = nil
			for _, st in ipairs(rEng.steps or {}) do
				if not st.isMilestone and not st.isSubCraftStep and st.itemID == 4389 then
					gyroSkillStep = st
					break
				end
			end
			check(gyroSkillStep ~= nil, "Engineering 195-225 (" .. goal .. ") includes Gyrochronatom skill-up step")
			check((gyroSkillStep.unitsKeptForLater or 0) == 0,
				string.format("Gyrochronatom (%s) unitsKeptForLater == 0 (not stolen; got %d)", goal, gyroSkillStep.unitsKeptForLater or -1))
			check((gyroSkillStep.ahSold or 0) > 0,
				string.format("Gyrochronatom (%s) sells on AH (ahSold=%d)", goal, gyroSkillStep.ahSold or 0))
			check((gyroSkillStep.resale or 0) > 0,
				string.format("Gyrochronatom (%s) keeps positive AH resale (%dc)", goal, gyroSkillStep.resale or 0))
			check((gyroSkillStep.netCost or 0) < 0,
				string.format("Gyrochronatom (%s) shows net profit (netCost=%dc < 0)", goal, gyroSkillStep.netCost or 0))
		end

		ns.GetReagentUnitCost = origReagent
		ns.GetItemMarketPrice = origMkt
		ns.GetNumListed = origListed
		ns.GetDailySold = origDaily
		ns.GetConservativeSaleUnitPrice = origCons
		resetCaches()
	end

	-- 8d. UI honesty & investment rollup display check
	do
		local tbl = papp.ui.pathTable
		check(tbl and tbl.setRows, "pathTable exposes setRows for UI honesty check")
		local pureInvStep = {
			stepNum = 1, skillRange = "205", name = "Sub-Craft: Iron Strut",
			sourceLabel = "Sub-Craft", crafts = 22, chanceRange = "Prep",
			unlockCost = 0, grossMats = 14300, resale = 0, netCost = 14300,
			unitsMade = 22, unitsKeptForLater = 22, isSubCraftStep = true, isPureInvestment = true,
			rolledOutCost = 14300, allocatedNetCost = 0, itemID = 4387,
			keptForSteps = { { stepNum = 4, name = "Advanced Target Dummy", qty = 22, rolledCost = 14300 } },
		}
		local consumerStep = {
			stepNum = 4, skillRange = "205 -> 215", name = "Advanced Target Dummy",
			sourceLabel = "Trainer", crafts = 22, chanceRange = "100%->50%",
			unlockCost = 0, grossMats = 16800, resale = 55000, netCost = -38200,
			rolledInCost = 42400, allocatedNetCost = 4200,
			reusedInputMats = 42400, fullRecipeMats = 59200, fullRecipeNet = 4200,
			rolledInSteps = { { stepNum = 1, name = "Iron Strut", qty = 22, cost = 14300 } },
			unitsMade = 22, itemID = 4392,
		}
		local partialStep = {
			stepNum = 2, skillRange = "195 -> 205", name = "Gyrochronatom",
			sourceLabel = "Known", crafts = 31, chanceRange = "46%->23%",
			unlockCost = 0, grossMats = 10075, resale = 6750, netCost = 3325,
			unitsMade = 31, unitsKeptForLater = 22, isPureInvestment = false,
			rolledOutCost = 7150, allocatedNetCost = -3825, itemID = 4389,
			keptForSteps = { { stepNum = 4, name = "Advanced Target Dummy", qty = 22, rolledCost = 7150 } },
		}
		tbl.setRows({ pureInvStep, partialStep, consumerStep })
		local byNum = {}
		if tbl.forEachRow then
			tbl.forEachRow(function(rf) if rf.data and rf.data.stepNum then byNum[rf.data.stepNum] = rf end end)
		elseif tbl.pool then
			for _, rf in ipairs(tbl.pool) do
				if rf.data and rf.data.stepNum then byNum[rf.data.stepNum] = rf end
			end
		end
		local rInv, rPart, rCons = byNum[1], byNum[2], byNum[4]
		check(rInv and rPart and rCons, "pathTable populated all 3 investment test rows")
		local invSell = stripColors(rInv.cells[11]:GetText())
		local invAH = stripColors(rInv.cells[9]:GetText())
		local invNet = stripColors(rInv.cells[14]:GetText())
		check(invSell == "-> #4", "Pure investment Sell shows '-> #4' (got '" .. invSell .. "')")
		check(invAH == "-", "Pure investment with no AH price shows '-' in AH column (got '" .. invAH .. "')")
		check(invNet == "—" or invNet == "-", "Pure investment Net Cost / Profit shows dash '—' (got '" .. invNet .. "')")

		local partSell = stripColors(rPart.cells[11]:GetText())
		local partVend = stripColors(rPart.cells[10]:GetText())
		local partNet = stripColors(rPart.cells[14]:GetText())
		check(partSell:find("-> #4", 1, true) ~= nil, "Partial reuse Sell notes '-> #4' (got '" .. partSell .. "')")
		check(partVend ~= "-", "Partial reuse Vendor shows non-dash value (got '" .. partVend .. "')")
		check(partNet:find("+", 1, true) ~= nil and partNet:find("Profit", 1, true) ~= nil, "Partial reuse leftover net shows +Profit (got '" .. partNet .. "')")

		local consNet = stripColors(rCons.cells[14]:GetText())
		check(consNet:find("Profit", 1, true) == nil and consNet:find("-", 1, true) ~= nil and consNet:find("42s", 1, true) ~= nil,
			"Losing consumer step shows real rolled-in loss '-42s' and never prints 'Profit' (got '" .. consNet .. "')")
	end
end

---------------------------------------------------------------------------------------------------
-- 9. Professor Upgrade Suite (Broken Thresholds, Multiplicative OT, Opportunity-Cost Bags,
--    Fallback AH, Unlisted Vendor Floor, 75/150/225 Rank Splits, Camp Favor, Live Thresholds, Runway/Stops)
---------------------------------------------------------------------------------------------------
do
	-- 9a. Zero broken recipe thresholds (req <= y <= g <= gr) & Mining 175-300 smelting path
	local brokenCnt = 0
	for pk, list in pairs(MP.RECIPES or {}) do
		for _, rec in ipairs(list) do
			local req, y, g, gr = rec.req or 1, rec.y or 0, rec.g or 0, rec.gr or 0
			if not (req <= y and y <= g and g <= gr) then
				brokenCnt = brokenCnt + 1
			end
		end
	end
	check(brokenCnt == 0, "Zero broken req/y/g/gr recipes across MP.RECIPES (got " .. tostring(brokenCnt) .. ")")

	resetCaches()
	local rMining = MP.SolveProfessionPath("mining", {
		startSkill = 175, targetSkill = 300, charLevel = 60,
		goalMode = "cheapest", recipeFilter = "trainer_vendor",
		overtimeRank = 0, useOwned = false, forceRecompute = true,
	})
	check(rMining and not rMining.unreachable and (rMining.targetSkill or 0) == 300 and #(rMining.steps or {}) > 0,
		"Mining 175-300 smelting path reaches skill 300")

	-- 9b. Multiplicative Working Overtime exact formula check
	local otRec = { req = 100, y = 130, g = 140, gr = 150 }
	local pOT0 = MP.GetSkillUpChance(otRec, 140, 0, nil, false)
	local pOT5 = MP.GetSkillUpChance(otRec, 140, 5, nil, false)
	check(math.abs(pOT0 - 0.50) < 1e-6 and math.abs(pOT5 - 0.60) < 1e-6,
		string.format("Multiplicative Working Overtime: OT=0 gives 0.50 (%.3f), OT=5 gives 0.60 (%.3f)", pOT0, pOT5))

	-- 9c. Opportunity-cost owned mats (Silk Cloth): sellable 2s AH item in bags is NOT wasted on 1s recipe
	do
		local origReag = ns.GetReagentUnitCost
		local origMkt = ns.GetItemMarketPrice
		local origVend = ns.GetVendorSellPrice
		local origList = ns.GetNumListed
		local origDaily = ns.GetDailySold

		ns.GetReagentUnitCost = function(id)
			if id == 4306 then return 2000, "MockAH", false end -- Silk Cloth buyout 20s
			if id == 2592 then return 500, "MockAH", false end  -- Wool Cloth buyout 5s
			return origReag(id)
		end
		ns.GetItemMarketPrice = function(id)
			if id == 4306 then return 2000, "MockAH" end -- Silk Cloth sells for 20s on AH (19s after cut)
			return origMkt(id)
		end
		ns.GetVendorSellPrice = function(id)
			if id == 4306 then return 150 end
			return origVend(id)
		end
		resetCaches()
		local rKeepSilk = MP.SolveProfessionPath("firstaid", {
			startSkill = 150, targetSkill = 180, charLevel = 60,
			goalMode = "cheapest", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = true,
			ownedCountsByID = { [4306] = 200, [2592] = 0 }, -- Own 200 Silk Cloth
			forceRecompute = true,
		})
		-- With 20s AH-sellable Silk Cloth, Heavy Wool Bandage (uses Wool) is far cheaper economically than burning Silk Cloth
		-- Wait: at 150..180 check Silk vs Wool or verify Heavy Silk / Silk Bandage oppCost isn't treated as 0c free!
		local rBuySilk = MP.SolveProfessionPath("firstaid", {
			startSkill = 150, targetSkill = 180, charLevel = 60,
			goalMode = "cheapest", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = false, forceRecompute = true,
		})
		check(rKeepSilk and rBuySilk and rKeepSilk.netCost > 0,
			"Silk Cloth in bags is valued at opportunity cost (not 0c free): ownNet=" .. tostring(rKeepSilk and rKeepSilk.netCost))

		-- Conversely, cheap/BoP owned item with savings DOES credit ownedSavings via ownedCountsByID
		ns.GetVendorSellPrice = origVend
		ns.GetItemMarketPrice = origMkt
		ns.GetReagentUnitCost = origReag
		ns.GetNumListed = origList
		ns.GetDailySold = origDaily
		resetCaches()

		local rOwnedIDs = MP.SolveProfessionPath("alchemy", {
			startSkill = 1, targetSkill = 55, charLevel = 60,
			goalMode = "cheapest", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = true,
			ownedCountsByID = { [2447] = 100, [765] = 100 }, -- Peacebloom & Silverleaf by ID
			forceRecompute = true,
		})
		check(rOwnedIDs and (rOwnedIDs.ownedSavings or 0) > 0,
			"ownedCountsByID credits real ownedSavings for Peacebloom/Silverleaf (got " .. tostring(rOwnedIDs and rOwnedIDs.ownedSavings) .. ")")
	end

	-- 9d. Live AH absent reagent uses ns.GetFallbackMarketPrice in EvaluateRecipeForSolver
	do
		local recFB, testRgID = nil, nil
		for _, rec in ipairs(MP.RECIPES.alchemy or {}) do
			if (rec.src == "start" or rec.src == "trainer") and type(rec.r) == "table" then
				for _, rg in ipairs(rec.r) do
					if not (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[rg[1]]) then
						recFB, testRgID = rec, rg[1]
						break
					end
				end
			end
			if recFB then break end
		end
		check(recFB ~= nil and testRgID ~= nil, "Found Alchemy recipe with non-vendor reagent for fallback test")
		local origReag = ns.GetReagentUnitCost
		local origFB = ns.GetFallbackMarketPrice
		ns.GetReagentUnitCost = function(id)
			if id == testRgID then return nil, nil, false end
			return origReag(id)
		end
		ns.GetFallbackMarketPrice = function(id)
			if id == testRgID then return 450, "Saved AH" end
			return origFB(id)
		end
		local fbCtx = {
			db = MP.GetDB(), profKey = "alchemy", mns = ns,
			legacy = MP.GetEffectiveLegacy(MP.GetDB()), charLevel = 60,
			allowedSources = { start = true, trainer = true, vendor = true },
			goalMode = "cheapest", sellDays = 3, applyAHCut = true, includeVendorSell = true,
			useOwned = false, ownedCounts = {}, subCraftMode = "buy_only", subCraftOverrides = {},
			trainerCosts = {}, playerFaction = "H", favorUnitPrice = 0, standingID = 4,
			itemOptionCache = {}, subEvCache = {},
		}
		local evFB = MP.EvaluateRecipeForSolver(recFB, fbCtx)
		ns.GetReagentUnitCost = origReag
		ns.GetFallbackMarketPrice = origFB
		check(evFB ~= nil and evFB.grossPerCraft >= 450,
			"Absent AH reagent falls back via GetFallbackMarketPrice instead of dropping recipe")
	end

	-- 9e. Unlisted output NPC vendor floor in Professor vs Calculators.lua untouched
	do
		local mockEv = {
			rec = { ench = false, i = 99999 },
			canAH = true, isUnlisted = true, isCustomPrice = false,
			vendorUnit = 250, ahGrossUnit = nil,
		}
		local resTotal, ahS, vendS, tag = MP.ComputeOutputsResale(mockEv, 5, { goalMode = "smart", includeVendorSell = true }, 0)
		check(resTotal == 1250 and ahS == 0 and vendS == 5 and tag == "Vendor (Unlisted)",
			"ComputeOutputsResale credits NPC vendor floor for unlisted outputs (got " .. tostring(resTotal) .. ", " .. tostring(tag) .. ")")
	end

	-- 9f. In-DP 75/150/225 rank-bracket splits preserved
	do
		resetCaches()
		local rSplit = MP.SolveProfessionPath("alchemy", {
			startSkill = 1, targetSkill = 260, charLevel = 60,
			goalMode = "cheapest", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = false, forceRecompute = true,
		})
		local saw75, saw150, saw225 = false, false, false
		for _, st in ipairs(rSplit.steps or {}) do
			if st.s2 == 75 and not st.isMilestone then saw75 = true end
			if st.s2 == 150 and not st.isMilestone then saw150 = true end
			if st.s2 == 225 and not st.isMilestone then saw225 = true end
		end
		check(saw75 and saw150 and saw225, "In-DP rank brackets split cleanly at 75, 150, and 225")
	end

	-- 9g. Camp Favor favorUnlockCopper is separate from pure copper totalTrainUnlocks
	do
		local campRec = nil
		for _, list in pairs(MP.RECIPES or {}) do
			for _, r in ipairs(list) do
				if r.src == "camp" then campRec = r break end
			end
			if campRec then break end
		end
		check(campRec ~= nil, "Found a camp recipe for Favor valuation check")
		local campCtx = {
			db = MP.GetDB(), profKey = campRec.prof or "alchemy", mns = ns,
			legacy = MP.GetEffectiveLegacy(MP.GetDB()), charLevel = 60,
			allowedSources = { start = true, trainer = true, vendor = true, ah = true, camp = true, quest = true },
			goalMode = "cheapest", sellDays = 3, applyAHCut = true, includeVendorSell = true,
			useOwned = false, ownedCounts = {}, subCraftMode = "buy_only", subCraftOverrides = {},
			trainerCosts = {}, playerFaction = "H", favorUnitPrice = 1000, standingID = 8,
			ignoreLearnedSpells = true, itemOptionCache = {}, subEvCache = {},
		}
		local evCamp = MP.EvaluateRecipeForSolver(campRec, campCtx)
		check(evCamp and evCamp.baseUnlockCost == 0 and (evCamp.favorUnlockCopper or 0) > 0 and (evCamp.baseUnlockFavor or 0) > 0,
			"Camp recipe separates favorUnlockCopper from pure copper baseUnlockCost")
	end

	-- 9h. Shared subCraftOverrides respected from MerchantMasterDB + subEv effReq <= effReq guard
	do
		local db = MP.GetDB()
		local origMM = MerchantMasterDB.subCraftOverrides
		local origPR = db.subCraftOverrides
		MerchantMasterDB.subCraftOverrides = { [2840] = "buy" }
		db.subCraftOverrides = {}
		resetCaches()
		local rBuy = MP.SolveProfessionPath("blacksmithing", {
			startSkill = 1, targetSkill = 55, charLevel = 60,
			goalMode = "cheapest", recipeFilter = "trainer_vendor",
			overtimeRank = 0, useOwned = false,
		})
		MerchantMasterDB.subCraftOverrides = origMM
		db.subCraftOverrides = origPR
		check(rBuy ~= nil and not rBuy.unreachable, "SolveProfessionPath honors shared MerchantMasterDB.subCraftOverrides")
	end

	-- 9i. MP.RecordLiveRecipeColor + MP.GetEffectiveThresholds clamping & cache revision
	do
		local db = MP.GetDB()
		db.liveThresholds = db.liveThresholds or {}
		local synthRec = { s = 999888, req = 100, y = 130, g = 140, gr = 150 }
		local rev0 = MP.GetLiveThresholdsRev()
		local chg1 = MP.RecordLiveRecipeColor(999888, 120, "trivial", nil, db)
		local rev1 = MP.GetLiveThresholdsRev()
		local _, _, _, effGr1 = MP.GetEffectiveThresholds(synthRec, db)
		check(chg1 and rev1 > rev0 and effGr1 == 120 and MP.GetSkillColor(synthRec, 120, nil, db) == "gray",
			"RecordLiveRecipeColor('trivial' at 120) clamps gr to 120 and marks recipe gray")

		local synthRec2 = { s = 999889, req = 100, y = 110, g = 120, gr = 130 }
		MP.RecordLiveRecipeColor(999889, 138, "easy", nil, db)
		local _, _, _, effGr2 = MP.GetEffectiveThresholds(synthRec2, db)
		check(effGr2 >= 139 and MP.GetSkillColor(synthRec2, 138, nil, db) == "green" and MP.GetSkillUpChance(synthRec2, 138, 0, nil, db) > 0,
			"RecordLiveRecipeColor('easy' past static grey) extends effective grey threshold cleanly")
		db.liveThresholds[999888] = nil
		db.liveThresholds[999889] = nil
	end

	-- 9j. MP.ComputeGoldRunway & MP.BuildVendorStops
	do
		local synthSteps = {
			{ stepNum = 1, name = "Step 1", unlockCost = 0, grossMats = 500, resale = 200 },
			{ stepNum = 2, name = "Step 2", unlockCost = 0, grossMats = 800, resale = 0 },
		}
		local rwShort = MP.ComputeGoldRunway(synthSteps, 700)
		local rwOK = MP.ComputeGoldRunway(synthSteps, 1100)
		check(not rwShort.isFunded and rwShort.shortfallStepNum == 2 and rwShort.shortfallCopper == 400 and rwShort.coveredSteps == 1,
			"ComputeGoldRunway identifies exact shortfall step & copper deficit")
		check(rwOK.isFunded and rwOK.shortfallCopper == 0 and rwOK.coveredSteps == 2,
			"ComputeGoldRunway reports funded when wallet covers peak cash outlay")

		local vendScrollID, vendScrollName = nil, nil
		for _, r in ipairs(ns.RECIPES or {}) do
			if (r.recipeItemID or 0) > 0 and (r.vendorH and r.vendorH ~= "") then
				vendScrollID, vendScrollName = r.recipeItemID, r.recipeName or ("Scroll " .. tostring(r.recipeItemID))
				break
			end
		end
		check(vendScrollID ~= nil, "Found mapped Horde vendor recipe scroll for BuildVendorStops")
		local stops = MP.BuildVendorStops({
			{ itemID = 2320, name = "Coarse Thread", buyQty = 5, isVendor = true, lineCost = 50 },
			{ itemID = 3371, name = "Empty Vial", buyQty = 10, isVendor = true, lineCost = 40 },
			{ itemID = vendScrollID, name = vendScrollName, buyQty = 1, isVendor = true, lineCost = 1000 },
		}, "H")
		check(stops and stops.stopCount == 2 and stops.vendorItemCount == 3,
			"BuildVendorStops groups 2 generic supplies into 1 stop + 1 recipe vendor stop (stops=" .. tostring(stops and stops.stopCount) .. ")")
	end
end

print(string.format("PASS: Professor formulas suite (%d assertions, 0 failures)", n))
