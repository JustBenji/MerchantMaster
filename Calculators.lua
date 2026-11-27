-- MerchantMaster: Calculators, Order-Book Shopping Lists, Sub-Craft Optimizer,
-- Writ Crafter Profit Explorer & Gatherer Crate-Material Profit Explorer

local _, ns = ...

local LIVE_LOT_FRESH_SECONDS = 1800

ns.POST_DURATIONS = {
	{ idx = 1, hours = 2,  mult = 0.05, label = "2h" },
	{ idx = 2, hours = 8,  mult = 0.20, label = "8h" },
	{ idx = 3, hours = 24, mult = 0.60, label = "24h" },
}

ns.SUBCRAFT_MODES = {
	{ key = "smart",    label = "Sub-Mats: Smart (Same/My Prof)" },
	{ key = "all_sub",  label = "Sub-Mats: Craft All Cheaper" },
	{ key = "buy_only", label = "Sub-Mats: Buy Direct Only" },
}

ns.CRATE_MAT_FILTERS = {
	{ key = "all",     label = "Type: All Crate Mats" },
	{ key = "gather",  label = "Type: Gather / Farm Only" },
	{ key = "crafted", label = "Type: Crafted Mats Only" },
}

---------------------------------------------------------------------------------------------------
-- 1. Output-Item -> Recipe Index & Vendor Sell / AH Listing Deposit Cost
---------------------------------------------------------------------------------------------------

ns.RECIPES_BY_OUTPUT = {}
do
	for _, rec in ipairs(ns.RECIPES or {}) do
		if rec.outputItemID and rec.outputItemID > 0 and not rec.isEnchant then
			local list = ns.RECIPES_BY_OUTPUT[rec.outputItemID]
			if not list then
				list = {}
				ns.RECIPES_BY_OUTPUT[rec.outputItemID] = list
			end
			list[#list + 1] = rec
		end
	end
	for _, list in pairs(ns.RECIPES_BY_OUTPUT) do
		if #list > 1 then
			table.sort(list, function(a, b)
				local ta = (a.source == "trainer") and 0 or 1
				local tb = (b.source == "trainer") and 0 or 1
				if ta ~= tb then return ta < tb end
				return (a.skill or 1) < (b.skill or 1)
			end)
		end
	end
end

local function serializeMapSig(tbl, ec)
	if not tbl or next(tbl) == nil then return "" end
	if ec then
		local cache = ec._mapSig
		if not cache then cache = {}; ec._mapSig = cache end
		local hit = cache[tbl]
		if hit ~= nil then return hit end
	end
	local keys = {}
	for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	local parts = {}
	for i = 1, #keys do
		local k = keys[i]
		local v = tbl[k] or tbl[tonumber(k)]
		parts[i] = k .. "=" .. tostring(v)
	end
	local sig = table.concat(parts, ",")
	if ec and ec._mapSig then ec._mapSig[tbl] = sig end
	return sig
end

local function isSafeVendorNumber(v)
	if issecretvalue and issecretvalue(v) then return false end
	return type(v) == "number" and v == v and v >= 0 and v < math.huge
end

local function isSafeVendorString(v)
	if issecretvalue and issecretvalue(v) then return false end
	return type(v) == "string" and v ~= ""
end

-- Queries the live WoW client for an item's current server vendor sell price (return #11 of GetItemInfo).
-- Returns liveCopper (or nil if uncached), changed (true if it differs from prior cached/static price).
function ns.SyncLiveVendorSell(itemID)
	if not itemID or itemID <= 0 then return nil, false end
	local itemName, _, _, _, _, _, _, itemStackCount, _, _, sellPrice
	if C_Item and C_Item.GetItemInfo then
		itemName, _, _, _, _, _, _, itemStackCount, _, _, sellPrice = C_Item.GetItemInfo(itemID)
	elseif GetItemInfo then
		itemName, _, _, _, _, _, _, itemStackCount, _, _, sellPrice = GetItemInfo(itemID)
	end
	local ec = ns._evalCache
	if ec and ec.maxStack then
		if isSafeVendorNumber(itemStackCount) and itemStackCount >= 1 then
			ec.maxStack[itemID] = math.floor(itemStackCount + 0.5)
		elseif ec.maxStack[itemID] == nil then
			ec.maxStack[itemID] = false
		end
	end
	if not isSafeVendorNumber(sellPrice) then return nil, false end
	local v = math.floor(sellPrice + 0.5)
	local changed = false
	if isSafeVendorString(itemName) then
		local db = ns.GetDB and ns.GetDB()
		if db then
			db.liveVendorSell = db.liveVendorSell or {}
			local prev = db.liveVendorSell[itemID]
			if prev ~= v then
				db.liveVendorSell[itemID] = v
				local staticPrev = (ns.ITEM_VENDOR_SELL and ns.ITEM_VENDOR_SELL[itemID])
					or (_G.MerchantProfessorNS and _G.MerchantProfessorNS.ITEM_INFO
						and _G.MerchantProfessorNS.ITEM_INFO[itemID]
						and _G.MerchantProfessorNS.ITEM_INFO[itemID].sell)
				if prev ~= nil or (staticPrev ~= nil and staticPrev ~= v) then
					changed = true
				end
			end
		end
	end
	if ec and ec.vendorSell then
		if ec.vendorSell[itemID] ~= nil and ec.vendorSell[itemID] ~= false and ec.vendorSell[itemID] ~= v then
			changed = true
		end
		ec.vendorSell[itemID] = v
	end
	return v, changed
end

function ns.GetVendorSellPrice(itemID)
	if not itemID or itemID <= 0 then return nil end
	local ec = ns._evalCache
	if ec then
		local hit = ec.vendorSell[itemID]
		if hit ~= nil then
			return hit ~= false and hit or nil
		end
	end
	-- 1. Live WoW client API (authoritative server-hotfixed vendor sell price, including 0c)
	local liveSell = ns.SyncLiveVendorSell(itemID)
	if liveSell ~= nil then
		return liveSell
	end
	-- 2. Previously captured live WoW client vendor sell price (beats stale static tables after /reload)
	local db = ns.GetDB and ns.GetDB()
	local savedLive = db and db.liveVendorSell and db.liveVendorSell[itemID]
	if isSafeVendorNumber(savedLive) then
		local v = math.floor(savedLive + 0.5)
		if ec then ec.vendorSell[itemID] = v end
		return v
	end
	-- 3. Static catalog fallback (used only before live client caches the item)
	if ns.ITEM_VENDOR_SELL and ns.ITEM_VENDOR_SELL[itemID] ~= nil then
		local v = ns.ITEM_VENDOR_SELL[itemID]
		if ec then ec.vendorSell[itemID] = v end
		return v
	end
	if _G.MerchantProfessorNS and _G.MerchantProfessorNS.ITEM_INFO then
		local inf = _G.MerchantProfessorNS.ITEM_INFO[itemID]
		if inf and type(inf.sell) == "number" and inf.sell >= 0 then
			if ec then ec.vendorSell[itemID] = inf.sell end
			return inf.sell
		end
	end
	local AuctionHouseOpen = AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown()
	if (AuctionHouseOpen or ns.activeChar) and ns.RequestItemDataLoad then
		ns.RequestItemDataLoad(itemID)
	end
	if ec then ec.vendorSell[itemID] = false end
	return nil
end

-- Throttled live vendor-sell warmer: requests uncached WoW: Forever item data in small batches
-- without impacting open/idle frame budgets or combat.
local vendorWarmQueued = {}
local vendorWarmQueue = {}
local vendorWarmRunning = false

local function stepVendorWarmQueue()
	if #vendorWarmQueue == 0 then
		vendorWarmRunning = false
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		if C_Timer and C_Timer.After then
			C_Timer.After(2.0, stepVendorWarmQueue)
		else
			vendorWarmRunning = false
		end
		return
	end
	local sent = 0
	while #vendorWarmQueue > 0 and sent < 20 do
		local id = table.remove(vendorWarmQueue, 1)
		local live = ns.SyncLiveVendorSell(id)
		if live == nil and ns.RequestItemDataLoad then
			if ns.RequestItemDataLoad(id) then
				sent = sent + 1
			end
		end
	end
	if #vendorWarmQueue > 0 and C_Timer and C_Timer.After then
		C_Timer.After(0.25, stepVendorWarmQueue)
	else
		vendorWarmRunning = false
	end
end

function ns.WarmLiveVendorPrices(itemIDs)
	if type(itemIDs) ~= "table" or not (C_Item and C_Item.RequestLoadItemDataByID) then return 0 end
	local added = 0
	for _, id in ipairs(itemIDs) do
		if type(id) == "number" and id > 0 and not vendorWarmQueued[id] then
			vendorWarmQueued[id] = true
			local live = ns.SyncLiveVendorSell(id)
			if live == nil then
				vendorWarmQueue[#vendorWarmQueue + 1] = id
				added = added + 1
			end
		end
	end
	if added > 0 and not vendorWarmRunning and C_Timer and C_Timer.After then
		vendorWarmRunning = true
		C_Timer.After(0.15, stepVendorWarmQueue)
	end
	return added
end

-- Returns depositCopper (number), isExact (boolean), vendorSell (number or nil)
function ns.GetAHListingDeposit(itemID, durationIdx, qty, itemLocation)
	if not itemID or itemID <= 0 then return nil, false, nil end
	durationIdx = tonumber(durationIdx) or 1
	qty = tonumber(qty) or 1
	local dur = ns.POST_DURATIONS[durationIdx] or ns.POST_DURATIONS[1]

	-- Live C_AuctionHouse deposit check when at the Auction House
	if C_AuctionHouse and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		if itemLocation ~= nil and C_AuctionHouse.CalculateItemDeposit then
			local ok, dep = pcall(C_AuctionHouse.CalculateItemDeposit, itemLocation, dur.idx, qty)
			if ok and isSafeVendorNumber(dep) and dep >= 0 then
				return math.floor(dep + 0.5), true, ns.GetVendorSellPrice(itemID)
			end
		elseif C_AuctionHouse.CalculateCommodityDeposit then
			local ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, dur.idx, qty)
			if ok and isSafeVendorNumber(dep) and dep >= 0 then
				return math.floor(dep + 0.5), true, ns.GetVendorSellPrice(itemID)
			end
		end
	end

	local vendorSell = ns.GetVendorSellPrice(itemID)
	if vendorSell ~= nil then
		local dep = math.max(100, math.floor(vendorSell * qty * dur.mult + 0.5))
		return dep, true, vendorSell
	end
	-- Minimum 1s (100c) deposit floor per auction while item info loads asynchronously
	return 100, false, nil
end

-- Per-unit AH deposit using realistic auction stack size (avoids 10x ammo floor distortion and 20x c=1 stackable inflation)
function ns.GetAHUnitDeposit(itemID, durationIdx, craftYield)
	if not itemID or itemID <= 0 then return 5 end
	durationIdx = tonumber(durationIdx) or 1
	local dur = ns.POST_DURATIONS[durationIdx] or ns.POST_DURATIONS[1]
	local yieldN = math.max(1, math.floor(tonumber(craftYield) or 1))
	local vendorSell = ns.GetVendorSellPrice(itemID) or 0
	local maxStack = nil
	local ec = ns._evalCache
	local cachedStack = ec and ec.maxStack and ec.maxStack[itemID]
	if cachedStack ~= nil then
		maxStack = (cachedStack ~= false) and cachedStack or nil
	else
		local stackCnt
		if C_Item and C_Item.GetItemInfo then
			stackCnt = select(8, C_Item.GetItemInfo(itemID))
		elseif GetItemInfo then
			stackCnt = select(8, GetItemInfo(itemID))
		end
		if isSafeVendorNumber(stackCnt) and stackCnt >= 1 then
			maxStack = math.floor(stackCnt + 0.5)
		end
		if ec and ec.maxStack then
			ec.maxStack[itemID] = maxStack or false
		end
	end
	local batch
	if maxStack then
		batch = (maxStack == 1) and 1 or math.max(yieldN, maxStack)
	else
		batch = math.max(yieldN, 20)
	end
	local batchDep = math.max(100, math.floor(vendorSell * batch * dur.mult + 0.5))
	return batchDep / batch
end

---------------------------------------------------------------------------------------------------
-- 2. Recursive Sub-Craft Cost Engine (e.g. Cured Medium Hide, Bolt of Cloth, Smelted Bars, Parts)
---------------------------------------------------------------------------------------------------

local function matchesParentProfession(recProf, parentProf, parentProfs, allowMiningSmelt)
	if not recProf then return false end
	if parentProf then
		if recProf == parentProf then return true end
		if allowMiningSmelt and recProf == "mining" and (parentProf == "blacksmithing" or parentProf == "engineering") then
			return true
		end
	end
	if type(parentProfs) == "table" then
		if parentProfs[recProf] then return true end
		if allowMiningSmelt and recProf == "mining" and (parentProfs["blacksmithing"] or parentProfs["engineering"]) then
			return true
		end
	end
	return false
end

function ns.SelectBestRecipeForItem(itemID, parentProf, profMap, parentProfs)
	local list = ns.RECIPES_BY_OUTPUT[itemID]
	if not list or #list == 0 then return nil end
	if #list == 1 then return list[1] end
	local best, bestScore = nil, 999999
	for _, rec in ipairs(list) do
		local score = (rec.skill or 1)
		if matchesParentProfession(rec.prof, parentProf, parentProfs, false) then
			score = score - 10000
		elseif profMap and profMap[rec.prof] then
			score = score - 5000
		end
		if rec.source == "trainer" then
			score = score - 500
		end
		if (tonumber(rec.cd) or 0) >= 60 then
			score = score + 2000
		end
		if score < bestScore then
			best, bestScore = rec, score
		end
	end
	return best
end

function ns.GetRecipeCraftEligibility(recipe, profMap, parentProf, parentProfs)
	local sameProf = recipe.anyChar == true or matchesParentProfession(recipe.prof, parentProf, parentProfs, false)
	local skill = profMap and profMap[recipe.prof]
	local playerCanCraft = recipe.anyChar == true or (skill ~= nil and skill >= (recipe.skill or 1)) or ns.IsRecipeKnown(recipe)
	return sameProf, playerCanCraft
end

local getItemCraftOptionInner, computeSmartCraftCostInner

local function getCraftOptContextKey(ec, parentProf, parentProfs, profMap, subMode, overrides, allChars)
	local pProfsSig = (parentProfs ~= nil) and serializeMapSig(parentProfs, ec) or ""
	local ovSig = (overrides ~= nil) and serializeMapSig(overrides, ec) or ""
	local profSig = serializeMapSig(profMap, ec)
	return tostring(parentProf or "") .. "|" .. pProfsSig .. "|" .. tostring(subMode) .. "|" .. ovSig .. "|" .. profSig .. "|" .. (allChars and "1" or "0")
end

local function canAutoSubCraft(craftOpt, mode)
	return craftOpt ~= nil
		and (mode == "all_sub" or mode == "always" or (mode == "smart" and (craftOpt.sameProf or craftOpt.playerCanCraft)))
		and (tonumber(craftOpt.recipe and craftOpt.recipe.cd) or 0) < 60
end

function ns.ShouldSubCraft(craftOpt, mode, override, buyCost, craftCost)
	if not craftOpt or craftCost == nil or override == "buy" then return false end
	if override == "craft" then return true end
	return canAutoSubCraft(craftOpt, mode) and (buyCost == nil or craftCost < buyCost)
end

-- Cycle-safe internal evaluator: tracks whether any descendant hit a visited ancestor (hitCycle)
-- or the recursion depth limit (hitDepthLimit), plus craftable subtree dependencies (deps) and
-- relative height (maxSubDepth), so acyclic subtrees can be safely shared across all parents.
getItemCraftOptionInner = function(itemID, parentProf, parentProfs, profMap, subMode, overrides, allChars, visited, inDepth, ctxBucketOverride)
	if not itemID or itemID <= 0 then return nil, false, 0, nil, false end
	local depth = inDepth + 1
	if depth > 4 then return nil, false, 0, nil, true end
	if visited and visited[itemID] then return nil, true, 0, nil, false end

	local list = ns.RECIPES_BY_OUTPUT[itemID]
	if not list or #list == 0 then return nil, false, 0, nil, false end

	local ec = ns._evalCache
	local ctxBucket = ctxBucketOverride
	if ec and not ctxBucket then
		local ctxKey = getCraftOptContextKey(ec, parentProf, parentProfs, profMap, subMode, overrides, allChars)
		ctxBucket = ec.craftOpt[ctxKey]
		if not ctxBucket then
			ctxBucket = {}
			ec.craftOpt[ctxKey] = ctxBucket
		end
	end

	if ctxBucket then
		local entry = ctxBucket[itemID]
		if entry == false then
			return nil, false, 0, nil, false
		elseif entry then
			if inDepth + entry.maxSubDepth <= 4 then
				local usable = true
				local entryDeps = entry.deps
				if visited and entryDeps then
					for i = 1, #entryDeps do
						if visited[entryDeps[i]] then
							usable = false
							break
						end
					end
				end
				if usable then
					return entry.res, false, entry.maxSubDepth, entryDeps, false
				end
			end
		end
	end

	local rec = ns.SelectBestRecipeForItem(itemID, parentProf, profMap, parentProfs)
	if not rec then
		if ctxBucket then ctxBucket[itemID] = false end
		return nil, false, 0, nil, false
	end

	local reagents = ns.ResolveRecipeReagents(rec)
	if not reagents or #reagents == 0 then
		if ctxBucket then ctxBucket[itemID] = false end
		return nil, false, 0, nil, false
	end

	local ownVisited = visited or {}
	ownVisited[itemID] = true

	local childAllChars = (ns.IsAllCharsCraftableActive and ns.IsAllCharsCraftableActive(nil)) and true or false
	local unitCost, breakdown, _, _, _, hitCycle, childMaxSubDepth, childDeps, hitDepthLimit =
		computeSmartCraftCostInner(reagents, rec.numMade or 1, itemID, rec.prof, profMap, subMode, overrides, childAllChars, ownVisited, depth)

	ownVisited[itemID] = nil

	local sameProf, playerCanCraft = ns.GetRecipeCraftEligibility(rec, profMap, parentProf, parentProfs)
	local pObj = ns.PROF_BY_KEY[rec.prof]
	local baseCD = (ns.GetRecipeBaseCooldown and ns.GetRecipeBaseCooldown(rec)) or (tonumber(rec.cd) or 0)
	local cdSec, cdWindowSec, cdLabel = 0, 0, nil
	if baseCD and baseCD >= 60 then
		cdSec = baseCD
		if ns.NormalizeCooldownWindow then
			cdWindowSec, cdLabel = ns.NormalizeCooldownWindow(baseCD)
		else
			cdWindowSec = baseCD
			cdLabel = (baseCD >= 3600) and string.format("%dh", math.floor(baseCD / 3600 + 0.5)) or string.format("%dm", math.max(1, math.floor(baseCD / 60 + 0.5)))
		end
	end

	local result = {
		unitCraftCost = unitCost,
		recipe = rec,
		prof = rec.prof,
		profLabel = (pObj and pObj.label or rec.prof) .. " " .. tostring(rec.skill or 1),
		skill = rec.skill or 1,
		numMade = rec.numMade or 1,
		reagents = reagents,
		breakdown = breakdown,
		sameProf = sameProf,
		playerCanCraft = playerCanCraft,
		cd = cdSec,
		cdWindowSec = cdWindowSec,
		cdLabel = cdLabel,
	}
	local maxSubDepth = 1 + (childMaxSubDepth or 0)
	if ctxBucket and not hitCycle and not hitDepthLimit then
		ctxBucket[itemID] = {
			res = result,
			maxSubDepth = maxSubDepth,
			deps = childDeps,
		}
	end
	return result, hitCycle, maxSubDepth, childDeps, hitDepthLimit
end

-- Evaluates crafting 1 unit of `itemID` via its profession recipe (with cycle protection)
function ns.GetItemCraftOption(itemID, opts, visited, depth)
	if not itemID or itemID <= 0 then return nil end
	local list = ns.RECIPES_BY_OUTPUT[itemID]
	if not list or #list == 0 then return nil end
	local hasOpts = type(opts) == "table"
	local profMap = (hasOpts and opts.profMap) or ns.GetPlayerProfessions()
	local parentProf = hasOpts and opts.parentProf or nil
	local parentProfs = hasOpts and opts.parentProfs or nil
	local subMode = (hasOpts and opts.subCraftMode) or "smart"
	local overrides = hasOpts and opts.subCraftOverrides or nil
	local allChars = (ns.IsAllCharsCraftableActive and ns.IsAllCharsCraftableActive(hasOpts and opts or nil)) and true or false
	local result = getItemCraftOptionInner(itemID, parentProf, parentProfs, profMap, subMode, overrides, allChars, visited, depth or 0, nil)
	return result
end

computeSmartCraftCostInner = function(reagents, numMade, fallbackOutputID, parentProf, profMap, subMode, overrides, allChars, visited, depth)
	local ec = ns._evalCache
	local scSubTbl, scKey
	local ctxKey, childCtxBucket
	if ec then
		ctxKey = getCraftOptContextKey(ec, parentProf, nil, profMap, subMode, overrides, allChars)
		if (depth == nil or depth == 0) and visited == nil and type(reagents) == "table" then
			scSubTbl = ec.smartCraft[reagents]
			if not scSubTbl then
				scSubTbl = {}
				ec.smartCraft[reagents] = scSubTbl
			end
			scKey = tostring(numMade) .. "|" .. tostring(fallbackOutputID or 0) .. "|" .. ctxKey
			local hit = scSubTbl[scKey]
			if hit then
				return hit[1] ~= false and hit[1] or nil,
					hit[2],
					hit[3] ~= false and hit[3] or nil,
					hit[4] ~= false and hit[4] or nil,
					hit[5],
					false, 0, nil, false
			end
		end
	end

	local ownVisited = visited
	local addedFallback = false
	if fallbackOutputID then
		if not ownVisited then ownVisited = {} end
		if not ownVisited[fallbackOutputID] then
			ownVisited[fallbackOutputID] = true
			addedFallback = true
		end
	end

	if reagents and #reagents > 0 then
		local sum = 0
		local directSum = 0
		local directComplete = true
		local complete = true
		local breakdown = {}
		local usedSubCraft = false
		local hitCycle = false
		local hitDepthLimit = false
		local maxSubDepth = 0
		local deps, depsSeen = nil, nil
		local curDepth = depth or 0
		local recipesByOutput = ns.RECIPES_BY_OUTPUT

		for i = 1, #reagents do
			local pair = reagents[i]
			local rid, rqty = pair[1], pair[2]
			local ahUnit, ahSrc, isVendor = ns.GetReagentUnitCost(rid)
			local rawAHUnit, rawAHSrc = ns.GetItemMarketPrice(rid)
			local craftOpt = nil
			if not isVendor and recipesByOutput and recipesByOutput[rid] then
				if ec and not childCtxBucket then
					childCtxBucket = ec.craftOpt[ctxKey]
					if not childCtxBucket then
						childCtxBucket = {}
						ec.craftOpt[ctxKey] = childCtxBucket
					end
				end
				local rCycle, rMaxDepth, rDeps, rDepthLimit
				craftOpt, rCycle, rMaxDepth, rDeps, rDepthLimit = getItemCraftOptionInner(
					rid, parentProf, nil, profMap, subMode, overrides, allChars, ownVisited, curDepth, childCtxBucket
				)
				if rCycle then hitCycle = true end
				if rDepthLimit then hitDepthLimit = true end
				if craftOpt then
					if rMaxDepth > maxSubDepth then maxSubDepth = rMaxDepth end
					if not deps then
						deps = { rid }
						depsSeen = { [rid] = true }
					elseif not depsSeen[rid] then
						depsSeen[rid] = true
						deps[#deps + 1] = rid
					end
					if rDeps then
						for j = 1, #rDeps do
							local d = rDeps[j]
							if not depsSeen[d] then
								depsSeen[d] = true
								deps[#deps + 1] = d
							end
						end
					end
				end
			end

			local craftUnit = craftOpt and craftOpt.unitCraftCost or nil
			local override = overrides and overrides[rid]
			local makeMyself = ns.ShouldSubCraft(craftOpt, subMode, override, ahUnit, craftUnit)

			local chosenUnit = makeMyself and craftUnit or ahUnit
			local chosenSrc = makeMyself and ("Craft (" .. craftOpt.profLabel .. ")") or ahSrc

			if ahUnit then
				directSum = directSum + (ahUnit * rqty)
			else
				directComplete = false
			end

			local lineCost = chosenUnit and (chosenUnit * rqty) or nil
			if lineCost then
				sum = sum + lineCost
				if makeMyself then usedSubCraft = true end
			else
				complete = false
			end

			breakdown[#breakdown + 1] = {
				itemID = rid,
				name = ns.ItemName(rid),
				qty = rqty,
				unitCost = chosenUnit,
				lineCost = lineCost,
				source = chosenSrc,
				isVendor = isVendor,
				ahUnitCost = ahUnit,
				ahSource = ahSrc,
				rawAHUnitCost = rawAHUnit,
				rawAHSource = rawAHSrc,
				craftUnitCost = craftUnit,
				craftOpt = craftOpt,
				makeMyself = makeMyself,
			}
		end

		if addedFallback then ownVisited[fallbackOutputID] = nil end

		if complete then
			local smartUnit = math.floor((sum / numMade) + 0.5)
			local directUnit = directComplete and math.floor((directSum / numMade) + 0.5) or nil
			local srcTag = usedSubCraft and "Smart Sub-Craft" or "Reagents"
			if scSubTbl and scKey then
				scSubTbl[scKey] = { smartUnit, breakdown, srcTag, directUnit ~= nil and directUnit or false, usedSubCraft }
			end
			return smartUnit, breakdown, srcTag, directUnit, usedSubCraft, hitCycle, maxSubDepth, deps, hitDepthLimit
		end
		if scSubTbl and scKey then
			scSubTbl[scKey] = { false, breakdown, false, false, false }
		end
		return nil, breakdown, nil, nil, false, hitCycle, maxSubDepth, deps, hitDepthLimit
	end

	if addedFallback then ownVisited[fallbackOutputID] = nil end

	if scSubTbl and scKey then
		scSubTbl[scKey] = { false, {}, false, false, false }
	end
	return nil, {}, nil, nil, false, false, 0, nil, false
end

-- Computes smart per-unit craft cost, comparing AH/Vendor price vs Sub-Craft price for every reagent
function ns.ComputeSmartCraftCost(reagents, numMade, fallbackOutputID, opts, visited, depth)
	local hasOpts = type(opts) == "table"
	numMade = (type(numMade) == "number" and numMade > 0) and numMade or 1
	local subMode = (hasOpts and opts.subCraftMode) or "smart" -- "smart" | "all_sub" | "buy_only"
	local overrides = hasOpts and opts.subCraftOverrides or nil -- table: [itemID] = "craft" | "buy"
	local profMap = (hasOpts and opts.profMap) or ns.GetPlayerProfessions()
	local parentProf = hasOpts and opts.parentProf or nil
	local allChars = (ns.IsAllCharsCraftableActive and ns.IsAllCharsCraftableActive(nil)) and true or false
	local smartUnit, breakdown, srcTag, directUnit, usedSubCraft =
		computeSmartCraftCostInner(reagents, numMade, fallbackOutputID, parentProf, profMap, subMode, overrides, allChars, visited, depth)
	return smartUnit, breakdown, srcTag, directUnit, usedSubCraft
end

-- Flattens a recipe's leaf reagents (respecting makeMyself sub-crafts) for supply-pool peeking
function ns.CollectLeafReagents(breakdown, batches, outMap)
	outMap = outMap or {}
	batches = batches or 1
	for _, rg in ipairs(breakdown or {}) do
		local totalNeed = rg.qty * batches
		if rg.makeMyself and rg.craftOpt and rg.craftOpt.breakdown and #rg.craftOpt.breakdown > 0 then
			local subMade = rg.craftOpt.numMade or 1
			local subBatches = math.ceil(totalNeed / subMade)
			ns.CollectLeafReagents(rg.craftOpt.breakdown, subBatches, outMap)
		else
			outMap[rg.itemID] = (outMap[rg.itemID] or 0) + totalNeed
		end
	end
	return outMap
end

---------------------------------------------------------------------------------------------------
-- 3. Universal Shopping List Builder (Always Provides Both AH Price AND Craft Price + Sub-Crafts)
---------------------------------------------------------------------------------------------------

local function getQuotedPurchase(item, qty, marketUnit, marketSource)
	local skip, total, source = item.qty - qty, 0, nil
	for _, quote in ipairs(item.purchaseQuotes) do
		local skipped = math.min(skip, quote.qty)
		local buyQty = quote.qty - skipped
		skip = skip - skipped
		if buyQty > 0 then
			local unit = quote.unit or marketUnit
			if unit == nil then return nil, nil, marketSource end
			local src = (quote.unit ~= nil and quote.source) or marketSource or "AH"
			total = total + buyQty * unit
			source = (source and source ~= src) and "Mixed" or src
		end
	end
	return total / qty, total, source
end

-- demandList: array of { itemID, qty, role = "Crate"|"Writ"|"Turn-In"|"Reagent", parentProf = ..., actualTotal = ..., actualUnit = ... }
local function buildShoppingListRowsImpl(demandList, opts)
	opts = opts or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()
	local subMode = opts.subCraftMode or "smart"
	local overrides = opts.subCraftOverrides
	if overrides and opts.overridePrefix then
		local eff = {}
		for k, v in pairs(overrides) do
			if type(k) == "number" then eff[k] = v end
		end
		local pref = tostring(opts.overridePrefix) .. ":"
		local plen = #pref
		for k, v in pairs(overrides) do
			if type(k) == "string" and k:sub(1, plen) == pref then
				local rawKey = k:sub(plen + 1)
				local idKey = tonumber(rawKey) or rawKey
				eff[idKey] = v
			end
		end
		overrides = eff
	end
	local ownedCounts = opts.ownedCounts or {}
	local deductOwned = (opts.deductOwned == true)
	local spentPool = opts.spentPool
	local useAllocationCosts = opts.useAllocationCosts

	local function spentCost(sp, qty)
		if not sp or qty <= 0 then return nil end
		if sp.qty == qty then return sp.copper end
		if useAllocationCosts and sp.qty > qty then return sp.copper * qty / sp.qty end
	end

	local function clonePool(pool)
		if not pool then return nil end
		local out = {}
		for k, v in pairs(pool) do out[k] = v end
		return out
	end

	local canCraftMemo = {}
	local function canCraftRecipeNow(craftOpt)
		if not craftOpt or not craftOpt.recipe then return false end
		local rec = craftOpt.recipe
		local cached = canCraftMemo[rec]
		if cached ~= nil then return cached end
		local res
		if ns.EvaluateCraftAbility then
			local abi = ns.EvaluateCraftAbility(rec, profMap, repState)
			res = (abi and abi.ableToCraft) == true
		else
			res = craftOpt.playerCanCraft == true
		end
		canCraftMemo[rec] = res
		return res
	end

	local nameMemo = {}
	local function cachedItemName(id, fallback)
		if fallback == nil and id then
			local hit = nameMemo[id]
			if hit ~= nil then return hit end
			hit = ns.ItemName(id)
			nameMemo[id] = hit
			return hit
		end
		return ns.ItemName(id, fallback)
	end

	local remOwned
	if deductOwned then
		if opts.sharedOwnedPool then
			remOwned = opts.sharedOwnedPool
		else
			remOwned = {}
			for k, v in pairs(ownedCounts) do
				if type(v) == "number" and v > 0 then
					remOwned[k] = v
				end
			end
		end
	end

	-- Keep allocated purchases separate from crafts of the same item.
	local order = {}
	local byID, purchaseByID = {}, {}
	for _, entry in ipairs(demandList or {}) do
		local id = entry.itemID
		if id and id > 0 and entry.qty and entry.qty > 0 then
			local bucket = entry.forceBuy and purchaseByID or byID
			local agg = bucket[id]
			if not agg then
				agg = {
					itemID = id,
					itemName = entry.itemName,
					qty = 0,
					role = entry.role or "Reagent",
					parentProf = entry.parentProf,
					parentProfs = {},
					actualTotal = 0,
					hasActual = entry.actualTotal ~= nil,
					lotsUsed = entry.lotsUsed or 0,
					hitPriceJump = entry.hitPriceJump or false,
					forceBuy = entry.forceBuy,
					forceMakeMyself = entry.forceMakeMyself or false,
				}
				bucket[id] = agg
				order[#order + 1] = agg
			end
			if entry.actualUnit ~= nil and not agg.purchaseQuotes then
				agg.purchaseQuotes = {}
				if agg.qty > 0 then agg.purchaseQuotes[1] = { qty = agg.qty } end
			end
			if agg.purchaseQuotes then
				agg.purchaseQuotes[#agg.purchaseQuotes + 1] = { qty = entry.qty, unit = entry.actualUnit, source = entry.actualSource }
			end
			agg.qty = agg.qty + entry.qty
			if entry.parentProf and entry.parentProf ~= "" then
				agg.parentProfs[entry.parentProf] = true
				if not agg.parentProf then
					agg.parentProf = entry.parentProf
				end
			end
			if type(entry.parentProfs) == "table" then
				for pk, pv in pairs(entry.parentProfs) do
					if pv then agg.parentProfs[pk] = true end
				end
			end
			if entry.actualTotal ~= nil and agg.hasActual then
				agg.actualTotal = agg.actualTotal + entry.actualTotal
			else
				agg.hasActual = false
			end
			if entry.hitPriceJump then agg.hitPriceJump = true end
			if entry.forceMakeMyself then agg.forceMakeMyself = true end
			if entry.lotsUsed and entry.lotsUsed > agg.lotsUsed then agg.lotsUsed = entry.lotsUsed end
		end
	end

	if spentPool then
		for _, agg in ipairs(order) do
			local sp = spentPool[agg.itemID]
			local actual = not agg.hasActual and spentCost(sp, agg.qty)
			if actual then
				agg.hasActual = true
				agg.actualTotal = actual
				if sp.hitPriceJump then agg.hitPriceJump = true end
			end
		end
	end

	local rows = {}
	local totalCost = 0
	local missingPriceCount = 0
	local remSurplus = opts.sharedSurplusPool or {}

	-- Pass 1: Reserve incoming surplus and owned stock for direct top-level items first so optional sub-crafts never starve direct demand
	for _, item in ipairs(order) do
		local knownName = item.itemName and ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[item.itemID]
		item._name = ns.ItemName(item.itemID, knownName or item.itemName)
		item._owned = ownedCounts[item._name] or 0
		item._usedSurp = 0
		if (remSurplus[item.itemID] or 0) > 0 and item.qty > 0 then
			item._usedSurp = math.min(remSurplus[item.itemID], item.qty)
			remSurplus[item.itemID] = remSurplus[item.itemID] - item._usedSurp
		end
		item._usedOwn = 0
		local afterSurp = item.qty - item._usedSurp
		if deductOwned and remOwned and afterSurp > 0 and (remOwned[item._name] or 0) > 0 then
			item._usedOwn = math.min(remOwned[item._name], afterSurp)
			remOwned[item._name] = remOwned[item._name] - item._usedOwn
		end
	end

	local evalCraftBranch
	local stagedSeq = 0
	local remMemo = {}
	local remMemoCount = 0

	local function buildStackKey(sibStack)
		if not sibStack or #sibStack == 0 then return "" end
		local parts = {}
		for i = 1, #sibStack do
			local f = sibStack[i]
			if f and (f.nextIdx <= #f.staged or (f.parentExtra and f.parentExtra > 0)) then
				parts[#parts + 1] = tostring(f.staged._id or 0) .. ":" .. tostring(f.nextIdx) .. ":" .. tostring(f.parentID or 0) .. ":" .. tostring(f.parentExtra or 0)
			end
		end
		return table.concat(parts, "/")
	end

	local function cloneSibStackAdvance(sibStack)
		local out = {}
		for i = 1, #sibStack do
			local f = sibStack[i]
			if i == #sibStack then
				if f.nextIdx + 1 <= #f.staged or (f.parentExtra and f.parentExtra > 0) then
					out[#out + 1] = {
						staged = f.staged,
						nextIdx = f.nextIdx + 1,
						depth = f.depth,
						parentID = f.parentID,
						parentExtra = f.parentExtra,
					}
				end
			elseif f.nextIdx <= #f.staged or (f.parentExtra and f.parentExtra > 0) then
				out[#out + 1] = {
					staged = f.staged,
					nextIdx = f.nextIdx,
					depth = f.depth,
					parentID = f.parentID,
					parentExtra = f.parentExtra,
				}
			end
		end
		return out
	end

	local function hasChangedSurplus(prevSurp, nextSurp, extraSelf)
		if extraSelf and extraSelf > 0 then return true end
		if nextSurp then
			for sID, sQty in pairs(nextSurp) do
				if sQty ~= (prevSurp and prevSurp[sID] or 0) then
					return true
				end
			end
		end
		if prevSurp then
			for sID, pQty in pairs(prevSurp) do
				if pQty ~= (nextSurp and nextSurp[sID] or 0) then
					return true
				end
			end
		end
		return false
	end

	local function hasConsumedOwned(prevOwn, nextOwn)
		if not deductOwned or not prevOwn then return false end
		for k, v in pairs(prevOwn) do
			if v > ((nextOwn and nextOwn[k]) or 0) then
				return true
			end
		end
		return false
	end

	local function gatherBranchChoiceMap(craftOpt, neededQty, ownPool, surpPool, depth, outChoices, sumAcc, parentStepMul)
		if not craftOpt or depth > 6 or neededQty <= 0 or not craftOpt.breakdown then return end
		local subMade = math.max(1, tonumber(craftOpt.numMade) or 1)
		local ceilB = math.ceil(neededQty / subMade)
		local floorB = math.floor(neededQty / subMade)
		local stepMul = parentStepMul or 1
		for _, sub in ipairs(craftOpt.breakdown) do
			local perB = tonumber(sub.qty) or 0
			if perB > 0 then
				local id = sub.itemID
				local rawNeed = ceilB * perB
				local maxAvail = (surpPool and surpPool[id] or 0)
					+ ((deductOwned and ownPool and ownPool[cachedItemName(id)]) or 0)
				outChoices[id] = outChoices[id] or {}
				outChoices[id][rawNeed] = true
				if sumAcc then
					sumAcc[id] = (sumAcc[id] or 0) + rawNeed
					outChoices[id][sumAcc[id]] = true
				end
				if floorB >= 1 and floorB ~= ceilB then
					outChoices[id][floorB * perB] = true
				end
				if maxAvail > 0 then
					local unitStep = perB * stepMul
					local maxFitB = math.min(ceilB, math.floor(maxAvail / math.max(1, perB)))
					if maxFitB >= 1 then
						if maxFitB <= 128 then
							for b = 1, maxFitB do
								outChoices[id][b * perB] = true
							end
						else
							for b = 1, 32 do outChoices[id][b * perB] = true end
							for b = math.max(1, maxFitB - 32), maxFitB do outChoices[id][b * perB] = true end
							if floorB >= 1 then
								for b = math.max(1, floorB - 8), math.min(maxFitB, floorB + 8) do
									outChoices[id][b * perB] = true
								end
							end
						end
					end
					if unitStep > perB then
						local maxStepFit = math.min(math.ceil(rawNeed / unitStep), math.floor(maxAvail / unitStep))
						for s = 1, math.min(64, maxStepFit) do
							outChoices[id][s * unitStep] = true
						end
					end
				end
				local netNeed = math.max(0, rawNeed - maxAvail)
				if netNeed > 0 and netNeed ~= rawNeed then
					outChoices[id][netNeed] = true
				end
				if not sub.isVendor and sub.craftOpt then
					local childMade = math.max(1, tonumber(sub.craftOpt.numMade) or 1)
					local nextMul = math.max(1, math.ceil((stepMul * perB) / childMade))
					gatherBranchChoiceMap(sub.craftOpt, rawNeed, ownPool, surpPool, depth + 1, outChoices, sumAcc, nextMul)
					if netNeed > 0 and netNeed ~= rawNeed then
						gatherBranchChoiceMap(sub.craftOpt, netNeed, ownPool, surpPool, depth + 1, outChoices, nil, nextMul)
					end
					if floorB >= 1 and floorB ~= ceilB then
						gatherBranchChoiceMap(sub.craftOpt, floorB * perB, ownPool, surpPool, depth + 1, outChoices, nil, nextMul)
					end
				end
			end
		end
	end

	local function collectLaterReserves(curTopIdx, sibStack, ownPool, surpPool)
		local branchMaps = {}
		if sibStack then
			for fIdx = #sibStack, 1, -1 do
				local frame = sibStack[fIdx]
				if frame and frame.staged then
					for sIdx = frame.nextIdx, #frame.staged do
						local st = frame.staged[sIdx]
						if st and st.sub and (st.subQty or 0) > 0 and not st.sub.isVendor and st.sub.craftOpt then
							local bm, sa = {}, {}
							gatherBranchChoiceMap(st.sub.craftOpt, st.subQty, ownPool, surpPool, 1, bm, sa, 1)
							if next(bm) ~= nil then branchMaps[#branchMaps + 1] = bm end
						end
					end
				end
			end
		end
		local startTop = (curTopIdx or #order) + 1
		for k = startTop, #order do
			local nxt = order[k]
			local rawRem = math.max(0, (nxt.qty or 0) - (nxt._usedOwn or 0))
			if rawRem > 0 then
				local bm, sa = {}, {}
				bm[nxt.itemID] = { [rawRem] = true }
				local afterSurp = math.max(0, rawRem - (surpPool and surpPool[nxt.itemID] or 0))
				if afterSurp > 0 and nxt.role ~= "Crate" and nxt.role ~= "Writ" then
					local nOpt = ns.GetItemCraftOption(nxt.itemID, {
						parentProf = nxt.parentProf,
						parentProfs = nxt.parentProfs,
						profMap = profMap,
						subCraftMode = subMode,
						subCraftOverrides = overrides,
					})
					if nOpt then
						gatherBranchChoiceMap(nOpt, afterSurp, ownPool, surpPool, 1, bm, sa, 1)
						if rawRem ~= afterSurp then
							gatherBranchChoiceMap(nOpt, rawRem, ownPool, surpPool, 1, bm, nil, 1)
						end
					end
				end
				branchMaps[#branchMaps + 1] = bm
			end
		end
		if #branchMaps == 0 then return nil end
		local reserves = {}
		local allIDs = {}
		for _, bm in ipairs(branchMaps) do
			for id in pairs(bm) do allIDs[id] = true end
		end
		for id in pairs(allIDs) do
			reserves._laterMentioned = reserves._laterMentioned or {}
			reserves._laterMentioned[id] = true
			local maxAvail = (surpPool and surpPool[id] or 0)
				+ ((deductOwned and ownPool and ownPool[ns.ItemName(id)]) or 0)
			if maxAvail > 0 then
				local sumsSet = { [0] = true }
				local sumList = { 0 }
				for _, bm in ipairs(branchMaps) do
					local choices = bm[id]
					if choices then
						local curLen = #sumList
						for i = 1, curLen do
							local base = sumList[i]
							for ch in pairs(choices) do
								local nsVal = base + ch
								if nsVal > 0 and nsVal < maxAvail and not sumsSet[nsVal] and #sumList < 256 then
									sumsSet[nsVal] = true
									sumList[#sumList + 1] = nsVal
								end
							end
						end
					end
				end
				if #sumList > 1 then
					reserves[id] = sumList
				end
			end
		end
		return next(reserves) ~= nil and reserves or nil
	end

	local function collectSubtreeAvailUnits(craftOpt, maxNeededUnits, ownPool, surpPool, depth, leafRateAcc, leafCountAcc, parentFactor, reserves)
		if not craftOpt or depth > 6 or not craftOpt.breakdown or #craftOpt.breakdown == 0 then
			return {}
		end
		local subMade = math.max(1, tonumber(craftOpt.numMade) or 1)
		local maxSubBatches = math.max(1, math.ceil(math.max(1, tonumber(maxNeededUnits) or 1) / subMade))
		local rateScale = (parentFactor or 1) / subMade
		local batchBreaks, seenB = {}, {}
		local function addB(b)
			if b and b >= 1 and b <= maxSubBatches and not seenB[b] then
				seenB[b] = true
				batchBreaks[#batchBreaks + 1] = b
			end
		end
		if depth > 1 and subMade > 1 then
			-- Batch-rounding optima only occur near the top period (minimal waste) or at stock breakpoints (added below).
			local lo = math.max(1, maxSubBatches - subMade)
			for b = lo, maxSubBatches do addB(b) end
			if lo > 1 then
				for b = 1, math.min(lo - 1, subMade) do addB(b) end
			end
		end
		for _, sub in ipairs(craftOpt.breakdown) do
			local perBatch = tonumber(sub.qty) or 0
			if perBatch > 0 then
				if leafRateAcc then
					leafRateAcc[sub.itemID] = (leafRateAcc[sub.itemID] or 0) + (perBatch * rateScale)
				end
				if leafCountAcc then
					leafCountAcc[sub.itemID] = (leafCountAcc[sub.itemID] or 0) + 1
				end
				local directAvail = (surpPool and surpPool[sub.itemID] or 0)
					+ ((deductOwned and ownPool and ownPool[cachedItemName(sub.itemID)]) or 0)
				local rList = (directAvail > 0 and reserves and reserves[sub.itemID]) or nil
				if directAvail > 0 then
					if rList then
						for _, res in ipairs(rList) do
							local effA = directAvail - res
							if effA > 0 then
								addB(math.floor(effA / perBatch))
								addB(math.ceil(effA / perBatch))
							end
						end
					else
						addB(math.floor(directAvail / perBatch))
						addB(math.ceil(directAvail / perBatch))
					end
				end
				if not sub.isVendor and sub.craftOpt then
					local childMaxNeed = math.max(1, (maxSubBatches + 1) * perBatch)
					local childUnits = collectSubtreeAvailUnits(sub.craftOpt, childMaxNeed, ownPool, surpPool, depth + 1, leafRateAcc, leafCountAcc, perBatch * rateScale, reserves)
					for _, cu in ipairs(childUnits) do
						if rList then
							for _, res in ipairs(rList) do
								local totSub = math.max(0, directAvail - res) + cu
								addB(math.floor(totSub / perBatch))
								addB(math.ceil(totSub / perBatch))
							end
						else
							local totSub = directAvail + cu
							addB(math.floor(totSub / perBatch))
							addB(math.ceil(totSub / perBatch))
						end
					end
				end
			end
		end
		local outID = craftOpt.recipe and craftOpt.recipe.outputItemID
		local shareSurplus = (depth > 1 and subMade > 1 and outID and reserves and reserves._laterMentioned and reserves._laterMentioned[outID]) and true or false
		local outUnits, seenOut = {}, {}
		for _, b in ipairs(batchBreaks) do
			local baseU = b * subMade
			if not seenOut[baseU] then
				seenOut[baseU] = true
				outUnits[#outUnits + 1] = baseU
			end
			if shareSurplus and subMade <= 16 then
				for remS = 1, subMade - 1 do
					local u = baseU - remS
					if u >= 1 and not seenOut[u] then
						seenOut[u] = true
						outUnits[#outUnits + 1] = u
					end
				end
			end
		end
		return outUnits
	end

	local function collectMixCraftQtys(craftOpt, totalQty, ownPool, surpPool, curTopIdx, sibStack)
		if not craftOpt or totalQty <= 1 then return nil end
		local madeStep = math.max(1, tonumber(craftOpt.numMade) or 1)
		local maxB = math.floor((totalQty - 1) / madeStep)
		if maxB < 1 then return nil end
		local cands, seen = {}, {}
		local function addBatch(b)
			if b and b >= 1 and b <= maxB then
				local q = b * madeStep
				if q >= 1 and q < totalQty and not seen[q] then
					seen[q] = true
					cands[#cands + 1] = q
				end
			end
		end
		if madeStep > 1 and totalQty > madeStep and (totalQty % madeStep) ~= 0 then
			addBatch(math.floor(totalQty / madeStep))
		end
		local reserves = collectLaterReserves(curTopIdx, sibStack, ownPool, surpPool)
		local leafRates, leafCounts = {}, {}
		local stockUnits = collectSubtreeAvailUnits(craftOpt, maxB * madeStep, ownPool, surpPool, 1, leafRates, leafCounts, madeStep, reserves)
		for lid, ratePerParentBatch in pairs(leafRates) do
			if ratePerParentBatch > 0 and (leafCounts[lid] or 0) >= 2 then
				local avail = (surpPool and surpPool[lid] or 0)
					+ ((deductOwned and ownPool and ownPool[ns.ItemName(lid)]) or 0)
				if avail > 0 then
					local rList = reserves and reserves[lid]
					if rList then
						for _, res in ipairs(rList) do
							local effAvail = avail - res
							if effAvail > 0 then
								local est = math.floor((effAvail / ratePerParentBatch) + 1e-9)
								for d = -6, 2 do
									addBatch(est + d)
								end
							end
						end
					else
						local est = math.floor((avail / ratePerParentBatch) + 1e-9)
						for d = -6, 2 do
							addBatch(est + d)
						end
					end
				end
			end
		end
		for _, u in ipairs(stockUnits) do
			addBatch(math.floor(u / madeStep))
			addBatch(math.ceil(u / madeStep))
		end
		if #cands == 0 then return nil end
		table.sort(cands)
		return cands
	end

	-- Memoized dynamic programming over remaining sibling & top-level branches (globally optimal across branch permutations)
	local function simRemainingCost(startOwn, startSurp, curTopIdx, sibStack)
		local rOwn = clonePool(startOwn)
		local rSurp = clonePool(startSurp) or {}
		while sibStack and #sibStack > 0 and sibStack[#sibStack].nextIdx > #sibStack[#sibStack].staged do
			local doneFrame = sibStack[#sibStack]
			if doneFrame.parentID and (doneFrame.parentExtra or 0) > 0 then
				rSurp[doneFrame.parentID] = (rSurp[doneFrame.parentID] or 0) + doneFrame.parentExtra
			end
			local trimmed = {}
			for i = 1, #sibStack - 1 do trimmed[i] = sibStack[i] end
			sibStack = trimmed
		end

		local hasSibs = sibStack and #sibStack > 0
		local topIdx = curTopIdx or #order
		if not hasSibs and topIdx >= #order then
			return 0, 0
		end

		local sKey = buildStackKey(sibStack)
		local mKey = tostring(topIdx) .. "|" .. sKey .. "|" .. serializeMapSig(rOwn) .. "|" .. serializeMapSig(rSurp)
		local cached = remMemo[mKey]
		if cached then
			return cached[1], cached[2]
		end

		local allowInner = (remMemoCount < 8192)
		local bestSum, bestMiss

		if hasSibs then
			local frame = sibStack[#sibStack]
			local st = frame.staged[frame.nextIdx]
			local nextStack = cloneSibStackAdvance(sibStack)
			local sub = st.sub
			local subQty = st.subQty
			if subQty > 0 and (rSurp[sub.itemID] or 0) > 0 then
				local uS = math.min(rSurp[sub.itemID], subQty)
				rSurp[sub.itemID] = rSurp[sub.itemID] - uS
				subQty = subQty - uS
			end
			if subQty == 0 then
				bestSum, bestMiss = simRemainingCost(rOwn, rSurp, topIdx, nextStack)
			elseif sub.isVendor then
				local actual = useAllocationCosts and spentCost(spentPool and spentPool[sub.itemID], subQty)
				local vTot = actual or (sub.ahUnitCost and sub.ahUnitCost * subQty)
				local tailSum, tailMiss = simRemainingCost(rOwn, rSurp, topIdx, nextStack)
				if vTot ~= nil then
					bestSum, bestMiss = vTot + tailSum, tailMiss
				else
					bestSum, bestMiss = tailSum, tailMiss + 1
				end
			else
				local subAHUnit = sub.ahUnitCost
				local subAHTotal = subAHUnit and (subAHUnit * subQty) or nil
				local sp = spentPool and spentPool[sub.itemID] or nil
				local actual = spentCost(sp, subQty)
				if actual then
					subAHTotal = actual
					subAHUnit = math.floor((subAHTotal / math.max(1, subQty)) + 0.5)
				end
				local cTotal, cOwn, cSurp, cOk = nil, nil, nil, false
				if sub.craftOpt then
					local cCost, ok, _, nOwn, nSurp = evalCraftBranch(sub.craftOpt, subQty, frame.depth + 1, rOwn, rSurp, topIdx, nextStack, allowInner, sub.itemID, true)
					if ok and cCost ~= nil then cTotal, cOwn, cSurp, cOk = cCost, nOwn, nSurp, true end
				end
				local subOv = useAllocationCosts and (sub.makeMyself and "craft" or "buy") or (overrides and overrides[sub.itemID])
				local subModeOk = canAutoSubCraft(sub.craftOpt, subMode)
				local subElig = cOk and cTotal ~= nil and subModeOk
				local mStep = sub.craftOpt and math.max(1, tonumber(sub.craftOpt.numMade) or 1) or 1
				local mTot = math.ceil(subQty / mStep) * mStep
				local extraSelf = mTot - subQty

				local mixCands, anyMixChanged = nil, false
				if subModeOk and subOv == nil and sub.ahUnitCost ~= nil and not (sp and sp.qty == subQty and sp.hitPriceJump) then
					local mixQtys = collectMixCraftQtys(sub.craftOpt, subQty, rOwn, rSurp, topIdx, nextStack)
					if mixQtys then
						for _, mCraftQty in ipairs(mixQtys) do
							local mc, mok, _, mo, ms = evalCraftBranch(sub.craftOpt, mCraftQty, frame.depth + 1, rOwn, rSurp, topIdx, nextStack, allowInner, sub.itemID, true)
							if mok and mc ~= nil then
								mixCands = mixCands or {}
								local mChanged = hasConsumedOwned(rOwn, mo) or hasChangedSurplus(rSurp, ms, 0)
								if mChanged then anyMixChanged = true end
								mixCands[#mixCands + 1] = {
									cost = mc + (sub.ahUnitCost * (subQty - mCraftQty)),
									own = mo,
									surp = ms,
								}
							end
						end
					end
				end

				local function evalBuyOpt()
					local tSum, tMiss = simRemainingCost(rOwn, rSurp, topIdx, nextStack)
					if subAHTotal ~= nil then return subAHTotal + tSum, tMiss end
					return tSum, tMiss + 1
				end
				local function evalCraftOpt()
					local craftSurp = clonePool(cSurp) or {}
					if extraSelf > 0 then craftSurp[sub.itemID] = (craftSurp[sub.itemID] or 0) + extraSelf end
					local tSum, tMiss = simRemainingCost(cOwn, craftSurp, topIdx, nextStack)
					return cTotal + tSum, tMiss
				end

				if cOk and cTotal ~= nil and subOv == "craft" then
					bestSum, bestMiss = evalCraftOpt()
				elseif subOv == "buy" or not subModeOk then
					bestSum, bestMiss = evalBuyOpt()
				elseif subAHTotal == nil then
					if subElig then
						bestSum, bestMiss = evalCraftOpt()
					else
						bestSum, bestMiss = evalBuyOpt()
					end
				elseif allowInner and ((subElig and (hasConsumedOwned(rOwn, cOwn) or hasChangedSurplus(rSurp, cSurp, extraSelf))) or anyMixChanged) then
					bestSum, bestMiss = evalBuyOpt()
					if subElig then
						local kSum, kMiss = evalCraftOpt()
						if kMiss < bestMiss or (kMiss == bestMiss and kSum < bestSum) then
							bestSum, bestMiss = kSum, kMiss
						end
					end
					if mixCands then
						for _, mcand in ipairs(mixCands) do
							local tSum, tMiss = simRemainingCost(mcand.own, mcand.surp or {}, topIdx, nextStack)
							local mSum = mcand.cost + tSum
							if tMiss < bestMiss or (tMiss == bestMiss and mSum < bestSum) then
								bestSum, bestMiss = mSum, tMiss
							end
						end
					end
				else
					local bestMix = nil
					if mixCands then
						for _, mcand in ipairs(mixCands) do
							if not bestMix or mcand.cost < bestMix.cost then bestMix = mcand end
						end
					end
					if bestMix and bestMix.cost < subAHTotal and (not subElig or bestMix.cost < cTotal) then
						local tSum, tMiss = simRemainingCost(bestMix.own, bestMix.surp or {}, topIdx, nextStack)
						bestSum, bestMiss = bestMix.cost + tSum, tMiss
					elseif subElig and cTotal < subAHTotal then
						bestSum, bestMiss = evalCraftOpt()
					else
						bestSum, bestMiss = evalBuyOpt()
					end
				end
			end
		else
			local k = topIdx + 1
			local nxt = order[k]
			local nid = nxt.itemID
			local nRaw = nxt.qty
			local nQty = nRaw - nxt._usedOwn
			if nQty > 0 and (rSurp[nid] or 0) > 0 then
				local uS = math.min(rSurp[nid], nQty)
				rSurp[nid] = rSurp[nid] - uS
				nQty = nQty - uS
			end
			if nQty == 0 then
				bestSum, bestMiss = simRemainingCost(rOwn, rSurp, k, nil)
			else
				local ahUnit, ahSrc, isVendor = ns.GetReagentUnitCost(nid)
				local hasAllocation = nxt.hasActual and (not isVendor or useAllocationCosts) and nQty == nRaw
				local ahTotal = hasAllocation and nxt.actualTotal or (ahUnit and (ahUnit * nQty) or nil)
				if nxt.purchaseQuotes then
					ahUnit, ahTotal, ahSrc = getQuotedPurchase(nxt, nQty, ahUnit, ahSrc)
					isVendor = isVendor and ahSrc == "Vendor"
				elseif hasAllocation then
					ahUnit = math.floor((ahTotal / nQty) + 0.5)
				end
				if isVendor then
					local tSum, tMiss = simRemainingCost(rOwn, rSurp, k, nil)
					if ahTotal ~= nil then
						bestSum, bestMiss = ahTotal + tSum, tMiss
					else
						bestSum, bestMiss = tSum, tMiss + 1
					end
				else
					local cTotal, cOwn, cSurp, cOk, nOpt = nil, nil, nil, false, nil
					if nxt.role ~= "Crate" and nxt.role ~= "Writ" then
						nOpt = ns.GetItemCraftOption(nid, {
							parentProf = nxt.parentProf,
							parentProfs = nxt.parentProfs,
							profMap = profMap,
							subCraftMode = subMode,
							subCraftOverrides = overrides,
						})
						if nOpt then
							local cCost, ok, _, nextOwn, nextSurp = evalCraftBranch(nOpt, nQty, 1, rOwn, rSurp, k, {}, allowInner, nid, true)
							if ok and cCost ~= nil then cTotal, cOwn, cSurp, cOk = cCost, nextOwn, nextSurp, true end
						end
					end
					local ov = nxt.forceBuy and "buy" or (overrides and overrides[nid])
					local topModeOk = nxt.role ~= "Turn-In" and canAutoSubCraft(nOpt, subMode)
					local elig = cOk and cTotal ~= nil and topModeOk
					local mStep = nOpt and math.max(1, tonumber(nOpt.numMade) or 1) or 1
					local mTot = math.ceil(nQty / mStep) * mStep
					local extraSelf = mTot - nQty

					local mixCands, anyMixChanged = nil, false
					if topModeOk and ov == nil and not nxt.forceMakeMyself and ahUnit ~= nil and not (hasAllocation or nxt.purchaseQuotes) then
						local mixQtys = collectMixCraftQtys(nOpt, nQty, rOwn, rSurp, k, nil)
						if mixQtys then
							for _, mCraftQty in ipairs(mixQtys) do
								local mc, mok, _, mo, ms = evalCraftBranch(nOpt, mCraftQty, 1, rOwn, rSurp, k, {}, allowInner, nid, true)
								if mok and mc ~= nil then
									mixCands = mixCands or {}
									local mChanged = hasConsumedOwned(rOwn, mo) or hasChangedSurplus(rSurp, ms, 0)
									if mChanged then anyMixChanged = true end
									mixCands[#mixCands + 1] = {
										cost = mc + (ahUnit * (nQty - mCraftQty)),
										own = mo,
										surp = ms,
									}
								end
							end
						end
					end

					local function evalBuyTop()
						local tSum, tMiss = simRemainingCost(rOwn, rSurp, k, nil)
						if ahTotal ~= nil then return ahTotal + tSum, tMiss end
						return tSum, tMiss + 1
					end
					local function evalCraftTop()
						local craftSurp = clonePool(cSurp) or {}
						if extraSelf > 0 then craftSurp[nid] = (craftSurp[nid] or 0) + extraSelf end
						local tSum, tMiss = simRemainingCost(cOwn, craftSurp, k, nil)
						return cTotal + tSum, tMiss
					end

					if cOk and cTotal ~= nil and (ov == "craft" or (ov ~= "buy" and nxt.forceMakeMyself)) then
						bestSum, bestMiss = evalCraftTop()
					elseif ov == "buy" or not topModeOk then
						bestSum, bestMiss = evalBuyTop()
					elseif ahTotal == nil then
						if elig then
							bestSum, bestMiss = evalCraftTop()
						else
							bestSum, bestMiss = evalBuyTop()
						end
					elseif allowInner and ((elig and (hasConsumedOwned(rOwn, cOwn) or hasChangedSurplus(rSurp, cSurp, extraSelf))) or anyMixChanged) then
						bestSum, bestMiss = evalBuyTop()
						if elig then
							local kSum, kMiss = evalCraftTop()
							if kMiss < bestMiss or (kMiss == bestMiss and kSum < bestSum) then
								bestSum, bestMiss = kSum, kMiss
							end
						end
						if mixCands then
							for _, mcand in ipairs(mixCands) do
								local tSum, tMiss = simRemainingCost(mcand.own, mcand.surp or {}, k, nil)
								local mSum = mcand.cost + tSum
								if tMiss < bestMiss or (tMiss == bestMiss and mSum < bestSum) then
									bestSum, bestMiss = mSum, tMiss
								end
							end
						end
					else
						local bestMix = nil
						if mixCands then
							for _, mcand in ipairs(mixCands) do
								if not bestMix or mcand.cost < bestMix.cost then bestMix = mcand end
							end
						end
						if bestMix and bestMix.cost < ahTotal and (not elig or bestMix.cost < cTotal) then
							local tSum, tMiss = simRemainingCost(bestMix.own, bestMix.surp or {}, k, nil)
							bestSum, bestMiss = bestMix.cost + tSum, tMiss
						elseif elig and cTotal < ahTotal then
							bestSum, bestMiss = evalCraftTop()
						else
							bestSum, bestMiss = evalBuyTop()
						end
					end
				end
			end
		end

		if remMemoCount < 8192 then
			remMemo[mKey] = { bestSum, bestMiss }
			remMemoCount = remMemoCount + 1
		end
		return bestSum, bestMiss
	end

	-- Recursively evaluates rounded batch counts + owned/surplus deductions before route selection
	evalCraftBranch = function(craftOpt, neededQty, depth, ownPool, surpPool, curTopIdx, sibStack, allowLookahead, parentID, costOnly)
		if not craftOpt or depth > 6 then return nil, false, nil, ownPool, surpPool end
		if neededQty <= 0 then return 0, true, costOnly and nil or {}, clonePool(ownPool), clonePool(surpPool) end
		local subMade = math.max(1, tonumber(craftOpt.numMade) or 1)
		local batches = math.ceil(neededQty / subMade)
		local parentExtra = (batches * subMade) - neededQty
		if not craftOpt.breakdown or #craftOpt.breakdown == 0 then
			if craftOpt.unitCraftCost ~= nil then
				return craftOpt.unitCraftCost * (batches * subMade), true, costOnly and nil or {}, clonePool(ownPool), clonePool(surpPool)
			end
			return nil, false, nil, ownPool, surpPool
		end

		local simOwn = clonePool(ownPool)
		local simSurp = clonePool(surpPool) or {}
		stagedSeq = stagedSeq + 1
		local staged = { _id = stagedSeq }
		-- Pass 1 inside branch: reserve surplus/owned stock across direct sibling sub-reagents first
		for _, sub in ipairs(craftOpt.breakdown) do
			local rawSubQty = sub.qty * batches
			local subName = cachedItemName(sub.itemID)
			local usedSurp = math.min(simSurp[sub.itemID] or 0, rawSubQty)
			if usedSurp > 0 then
				simSurp[sub.itemID] = simSurp[sub.itemID] - usedSurp
			end
			local usedSubOwn = 0
			local afterSurp = rawSubQty - usedSurp
			if deductOwned and simOwn and afterSurp > 0 and (simOwn[subName] or 0) > 0 then
				usedSubOwn = math.min(simOwn[subName], afterSurp)
				simOwn[subName] = simOwn[subName] - usedSubOwn
			end
			staged[#staged + 1] = {
				sub = sub,
				subName = subName,
				rawSubQty = rawSubQty,
				usedSurp = usedSurp,
				usedSubOwn = usedSubOwn,
				subQty = afterSurp - usedSubOwn,
			}
		end

		local outRows = costOnly and nil or {}
		local subSum, subComplete = 0, true
		if allowLookahead then sibStack = sibStack or {} end
		for stIdx, st in ipairs(staged) do
			local sub = st.sub
			local subName = st.subName
			local rawSubQty = st.rawSubQty
			local usedSurp = st.usedSurp
			local usedSubOwn = st.usedSubOwn
			local subOwned = costOnly and 0 or (ownedCounts[subName] or 0)
			local subQty = st.subQty
			-- Any additional batch surplus created by an earlier sibling's sub-craft during Pass 2 can also satisfy subQty
			if subQty > 0 and (simSurp[sub.itemID] or 0) > 0 then
				local extraSurp = math.min(simSurp[sub.itemID], subQty)
				simSurp[sub.itemID] = simSurp[sub.itemID] - extraSurp
				usedSurp = usedSurp + extraSurp
				subQty = subQty - extraSurp
			end

			local subListed = (costOnly or sub.isVendor) and nil or ns.GetNumListed(sub.itemID)
			local subDailySold = (costOnly or sub.isVendor) and nil or ns.GetDailySold(sub.itemID)
			local subAHUnit = sub.ahUnitCost
			local subAHTotal = subAHUnit and (subAHUnit * subQty) or nil
			local subSrc = sub.ahSource
			local sp = (not sub.isVendor or useAllocationCosts) and spentPool and spentPool[sub.itemID]
			local actual = spentCost(sp, subQty)
			if actual then
				subAHTotal = actual
				subAHUnit = math.floor((subAHTotal / math.max(1, subQty)) + 0.5)
			end

			local subCraftUnit = sub.craftUnitCost
			local subCraftTotal, childRows, childOwn, childSurp, childComplete = nil, nil, nil, nil, false
			if allowLookahead then
				sibStack[#sibStack + 1] = {
					staged = staged,
					nextIdx = stIdx + 1,
					depth = depth,
					parentID = parentID,
					parentExtra = parentExtra,
				}
			end
			if not sub.isVendor and sub.craftOpt then
				if subQty == 0 then
					subCraftTotal = 0
					childComplete = true
					childRows = {}
					childOwn = simOwn
					childSurp = simSurp
				else
					local cCost, cOk, cRows, cOwn, cSurp = evalCraftBranch(sub.craftOpt, subQty, depth + 1, simOwn, simSurp, curTopIdx, sibStack, allowLookahead, sub.itemID, costOnly)
					if cOk and cCost ~= nil then
						subCraftTotal = cCost
						subCraftUnit = math.floor((cCost / math.max(1, subQty)) + 0.5)
						childComplete = true
						childRows = cRows
						childOwn = cOwn
						childSurp = cSurp
					end
				end
			end

			local subOv = useAllocationCosts and (sub.makeMyself and "craft" or "buy") or (overrides and overrides[sub.itemID])
			local subModeOk = canAutoSubCraft(sub.craftOpt, subMode)
			local subEligible = childComplete and subCraftTotal ~= nil and subModeOk
			local madeStep = (sub.craftOpt and math.max(1, tonumber(sub.craftOpt.numMade) or 1)) or 1
			local mixSubCands, anySubMixChanged = nil, false
			if subQty > 0 and subModeOk and subOv == nil and not sub.isVendor and sub.ahUnitCost ~= nil and not (sp and sp.qty == subQty and sp.hitPriceJump) then
				local mixQtys = collectMixCraftQtys(sub.craftOpt, subQty, simOwn, simSurp, curTopIdx, sibStack)
				if mixQtys then
					for _, mCraftQty in ipairs(mixQtys) do
						local mc, mok, _, mo, ms = evalCraftBranch(sub.craftOpt, mCraftQty, depth + 1, simOwn, simSurp, curTopIdx, sibStack, allowLookahead, sub.itemID, true)
						if mok and mc ~= nil then
							mixSubCands = mixSubCands or {}
							if hasConsumedOwned(simOwn, mo) or hasChangedSurplus(simSurp, ms, 0) then
								anySubMixChanged = true
							end
							local mBuyQty = subQty - mCraftQty
							local mBuyCost = sub.ahUnitCost * mBuyQty
							mixSubCands[#mixSubCands + 1] = {
								craftQty = mCraftQty,
								buyQty = mBuyQty,
								craftCost = mc,
								buyCost = mBuyCost,
								total = mc + mBuyCost,
								own = mo,
								surp = ms,
							}
						end
					end
				end
			end

			local subRoute, chosenSubMix = "buy", nil
			if subQty > 0 and not sub.isVendor and ((childComplete and subCraftTotal ~= nil) or mixSubCands ~= nil) then
				if subOv == "craft" then
					if childComplete and subCraftTotal ~= nil then subRoute = "craft" end
				elseif subOv == "buy" or not subModeOk then
					subRoute = "buy"
				else
					if subAHTotal == nil then
						if subEligible then subRoute = "craft" end
					elseif not allowLookahead then
						local bestM = nil
						if mixSubCands then
							for _, mcand in ipairs(mixSubCands) do
								if not bestM or mcand.total < bestM.total then bestM = mcand end
							end
						end
						if bestM and bestM.total < subAHTotal and (not subEligible or bestM.total < subCraftTotal) then
							subRoute, chosenSubMix = "mix", bestM
						elseif subEligible and subCraftTotal < subAHTotal then
							subRoute = "craft"
						end
					else
						local madeTotal = math.ceil(subQty / madeStep) * madeStep
						local extraSelf = madeTotal - subQty
						if (subEligible and (hasConsumedOwned(simOwn, childOwn) or hasChangedSurplus(simSurp, childSurp, extraSelf))) or anySubMixChanged then
							local bestRoute = "buy"
							local remBuy, missBuy = simRemainingCost(simOwn, simSurp, curTopIdx, sibStack)
							local bestCost, bestMiss = subAHTotal + remBuy, missBuy
							if subEligible then
								local craftSurp = clonePool(childSurp) or {}
								if extraSelf > 0 then
									craftSurp[sub.itemID] = (craftSurp[sub.itemID] or 0) + extraSelf
								end
								local remCraft, missCraft = simRemainingCost(childOwn, craftSurp, curTopIdx, sibStack)
								local candCraft = subCraftTotal + remCraft
								if missCraft < bestMiss or (missCraft == bestMiss and candCraft < bestCost) then
									bestRoute, bestCost, bestMiss = "craft", candCraft, missCraft
								end
							end
							if mixSubCands then
								for _, mcand in ipairs(mixSubCands) do
									local remMix, missMix = simRemainingCost(mcand.own, mcand.surp or {}, curTopIdx, sibStack)
									local candMix = mcand.total + remMix
									if missMix < bestMiss or (missMix == bestMiss and candMix < bestCost) then
										bestRoute, bestCost, bestMiss, chosenSubMix = "mix", candMix, missMix, mcand
									end
								end
							end
							subRoute = bestRoute
						else
							local bestM = nil
							if mixSubCands then
								for _, mcand in ipairs(mixSubCands) do
									if not bestM or mcand.total < bestM.total then bestM = mcand end
								end
							end
							if bestM and bestM.total < subAHTotal and (not subEligible or bestM.total < subCraftTotal) then
								subRoute, chosenSubMix = "mix", bestM
							elseif subEligible and subCraftTotal < subAHTotal then
								subRoute = "craft"
							end
						end
					end
				end
			end
			if allowLookahead then
				sibStack[#sibStack] = nil
			end

			if subRoute == "mix" and chosenSubMix then
				local mixSubRows
				if not costOnly then
					local _, _, mrows, mo, ms = evalCraftBranch(sub.craftOpt, chosenSubMix.craftQty, depth + 1, simOwn, simSurp, curTopIdx, sibStack, allowLookahead, sub.itemID, false)
					mixSubRows = mrows
					simOwn = mo or chosenSubMix.own
					simSurp = ms or chosenSubMix.surp or simSurp
				else
					simOwn = chosenSubMix.own
					simSurp = chosenSubMix.surp or simSurp
				end
				local mixSubTotal = chosenSubMix.total
				if not costOnly then
					local floorSubQty = chosenSubMix.craftQty
					local remSubBuy = chosenSubMix.buyQty
					local mixSubCraftCost = chosenSubMix.craftCost
					local mixSubBuyCost = chosenSubMix.buyCost
					local mixCraftUnit = math.floor((mixSubCraftCost / math.max(1, floorSubQty)) + 0.5)
					local remIncCraft, remIncCraftUnit = nil, nil
					if subCraftTotal ~= nil then
						remIncCraft = math.max(0, subCraftTotal - mixSubCraftCost)
						remIncCraftUnit = math.floor((remIncCraft / math.max(1, remSubBuy)) + 0.5)
					end
					local canNow = canCraftRecipeNow(sub.craftOpt)
					local isSameP = (sub.craftOpt and sub.craftOpt.sameProf) and true or false
					local iconTex = ns.ItemIcon(sub.itemID, ns.QUESTION_ICON)
					local subCD = (sub.craftOpt and sub.craftOpt.cd) or 0
					local subCDWin = (sub.craftOpt and sub.craftOpt.cdWindowSec) or 0
					local subCDLbl = (sub.craftOpt and sub.craftOpt.cdLabel) or nil
					local subCraftAct = (subCD >= 60 and subCDLbl)
						and ("Craft (" .. sub.craftOpt.profLabel .. ", " .. subCDLbl .. " CD)")
						or ("Craft (" .. sub.craftOpt.profLabel .. ")")
					outRows[#outRows + 1] = {
						itemID = sub.itemID,
						name = subName,
						icon = iconTex,
						role = "Sub-Mat",
						indent = depth,
						qty = floorSubQty,
						rawQty = floorSubQty + usedSubOwn + usedSurp,
						owned = subOwned,
						ownedUsed = usedSubOwn,
						surplusUsed = usedSurp,
						listed = subListed,
						dailySold = subDailySold,
						isVendor = false,
						ahUnitPrice = sub.ahUnitCost,
						ahTotalPrice = sub.ahUnitCost * floorSubQty,
						ahSource = sub.ahSource,
						craftUnitPrice = mixCraftUnit,
						craftTotalPrice = mixSubCraftCost,
						craftProfLabel = sub.craftOpt and sub.craftOpt.profLabel or nil,
						craftCD = subCD,
						craftCDWindow = subCDWin,
						craftCDLabel = subCDLbl,
						craftCanDo = canNow,
						craftSameProf = isSameP,
						canToggleCraft = true,
						makeMyself = true,
						action = subCraftAct,
						lineCost = mixSubCraftCost,
						hitPriceJump = false,
						isSubRow = true,
					}
					if mixSubRows then
						for _, cr in ipairs(mixSubRows) do outRows[#outRows + 1] = cr end
					end
					outRows[#outRows + 1] = {
						itemID = sub.itemID,
						name = subName,
						icon = iconTex,
						role = "Sub-Mat",
						indent = depth,
						qty = remSubBuy,
						rawQty = remSubBuy,
						owned = subOwned,
						ownedUsed = 0,
						surplusUsed = 0,
						listed = subListed,
						dailySold = subDailySold,
						isVendor = false,
						ahUnitPrice = sub.ahUnitCost,
						ahTotalPrice = mixSubBuyCost,
						ahSource = sub.ahSource,
						craftUnitPrice = remIncCraftUnit,
						craftTotalPrice = remIncCraft,
						craftProfLabel = sub.craftOpt and sub.craftOpt.profLabel or nil,
						craftCD = subCD,
						craftCDWindow = subCDWin,
						craftCDLabel = subCDLbl,
						craftCanDo = canNow,
						craftSameProf = isSameP,
						canToggleCraft = (remIncCraft ~= nil),
						makeMyself = false,
						action = "Buy AH",
						lineCost = mixSubBuyCost,
						hitPriceJump = false,
						isSubRow = true,
					}
				end
				subSum = subSum + mixSubTotal
			else
				local subMake = (subRoute == "craft")
				local subLine
				if subQty == 0 and (usedSubOwn + usedSurp) > 0 then
					subMake = false
					subLine = 0
				elseif sub.isVendor then
					subLine = subAHTotal
				elseif subMake then
					subLine = subCraftTotal
					simOwn = childOwn
					simSurp = childSurp or simSurp
					local madeTotal = math.ceil(subQty / madeStep) * madeStep
					if madeTotal > subQty then
						simSurp[sub.itemID] = (simSurp[sub.itemID] or 0) + (madeTotal - subQty)
					end
				else
					subLine = subAHTotal
				end

				if not costOnly then
					local usedMultiLot = (not subMake and sp and sp.qty == subQty and subQty > 0 and sp.hitPriceJump) and true or false
					if usedMultiLot then
						subSrc = (subSrc or "AH") .. " (Multi-Lot)"
					end

					local subCD = (sub.craftOpt and sub.craftOpt.cd) or 0
					local subCDWin = (sub.craftOpt and sub.craftOpt.cdWindowSec) or 0
					local subCDLbl = (sub.craftOpt and sub.craftOpt.cdLabel) or nil
					local subAction
					if subQty == 0 and (usedSubOwn + usedSurp) > 0 then
						if usedSubOwn > 0 and usedSurp > 0 then
							subAction = string.format("Owned (%dx) + Surplus (%dx)", usedSubOwn, usedSurp)
						elseif usedSubOwn > 0 then
							subAction = string.format("Owned (%dx)", rawSubQty)
						else
							subAction = string.format("Surplus (%dx)", rawSubQty)
						end
					elseif sub.isVendor then
						subAction = "Vendor"
					elseif subMake then
						subAction = (subCD >= 60 and subCDLbl)
							and ("Craft (" .. sub.craftOpt.profLabel .. ", " .. subCDLbl .. " CD)")
							or ("Craft (" .. sub.craftOpt.profLabel .. ")")
					else
						subAction = "Buy AH"
					end

					outRows[#outRows + 1] = {
						itemID = sub.itemID,
						name = subName,
						icon = ns.ItemIcon(sub.itemID, ns.QUESTION_ICON),
						role = "Sub-Mat",
						indent = depth,
						qty = subQty,
						rawQty = rawSubQty,
						owned = subOwned,
						ownedUsed = usedSubOwn,
						surplusUsed = usedSurp,
						listed = subListed,
						dailySold = subDailySold,
						isVendor = sub.isVendor,
						ahUnitPrice = subAHUnit,
						ahTotalPrice = subAHTotal,
						ahSource = subSrc,
						craftUnitPrice = subCraftUnit,
						craftTotalPrice = subCraftTotal,
						craftProfLabel = sub.craftOpt and sub.craftOpt.profLabel or nil,
						craftCD = subCD,
						craftCDWindow = subCDWin,
						craftCDLabel = subCDLbl,
						craftCanDo = canCraftRecipeNow(sub.craftOpt),
						craftSameProf = (sub.craftOpt and sub.craftOpt.sameProf) and true or false,
						canToggleCraft = (not sub.isVendor) and (subCraftTotal ~= nil) and (subQty > 0),
						makeMyself = subMake,
						action = subAction,
						lineCost = subLine,
						hitPriceJump = usedMultiLot,
						isSubRow = true,
					}
					if subMake and childRows then
						for _, cr in ipairs(childRows) do outRows[#outRows + 1] = cr end
					end
				end

				if subLine ~= nil then
					subSum = subSum + subLine
				else
					subComplete = false
				end
			end
		end
		return subComplete and subSum or nil, subComplete, outRows, simOwn, simSurp
	end

	for topIdx, item in ipairs(order) do
		local id = item.itemID
		local rawQty = item.qty
		local name = item._name
		local owned = item._owned
		local usedOwn = item._usedOwn
		local usedSurp = item._usedSurp or 0
		if (rawQty - usedOwn - usedSurp) > 0 and (remSurplus[id] or 0) > 0 then
			local extraSurp = math.min(remSurplus[id], rawQty - usedOwn - usedSurp)
			remSurplus[id] = remSurplus[id] - extraSurp
			usedSurp = usedSurp + extraSurp
		end
		local qty = rawQty - usedOwn - usedSurp
		local ahUnit, ahSrc, isVendor = ns.GetReagentUnitCost(id)
		local hasAllocation = item.hasActual and (not isVendor or useAllocationCosts) and qty == rawQty

		-- If order-book solver recorded multi-lot actual spend, reflect exact average & total AH cost
		local ahTotal
		if item.purchaseQuotes and qty > 0 then
			ahUnit, ahTotal, ahSrc = getQuotedPurchase(item, qty, ahUnit, ahSrc)
			isVendor = isVendor and ahSrc == "Vendor"
		elseif hasAllocation and qty > 0 then
			ahTotal = item.actualTotal
			ahUnit = math.floor((ahTotal / math.max(1, qty)) + 0.5)
			if item.hitPriceJump then
				ahSrc = (ahSrc or "AH") .. " (Multi-Lot)"
			end
		else
			ahTotal = ahUnit and (ahUnit * qty) or nil
		end
		local listed = isVendor and nil or ns.GetNumListed(id)
		local dailySold = isVendor and nil or ns.GetDailySold(id)

		-- Check if this shopping list item itself can be crafted (e.g. Cured Medium Hide, Bolt of Silk Cloth, Copper Bar, or a Turn-In item!)
		local craftOpt = (not isVendor and item.role ~= "Crate" and item.role ~= "Writ") and ns.GetItemCraftOption(id, {
			parentProf = item.parentProf,
			parentProfs = item.parentProfs,
			profMap = profMap,
			subCraftMode = subMode,
			subCraftOverrides = overrides,
		}) or nil

		local craftUnit = craftOpt and craftOpt.unitCraftCost or nil
		local craftTotal, branchSubRows, branchOwn, branchSurp, branchComplete = nil, nil, nil, nil, false
		if craftOpt then
			if qty == 0 then
				craftTotal = 0
				branchComplete = true
				branchSubRows = {}
				branchOwn = remOwned
				branchSurp = remSurplus
			else
				local cCost, cOk, cRows, cOwn, cSurp = evalCraftBranch(craftOpt, qty, 1, remOwned, remSurplus, topIdx, {}, true, id)
				if cOk and cCost ~= nil then
					craftTotal = cCost
					craftUnit = math.floor((cCost / math.max(1, qty)) + 0.5)
					branchComplete = true
					branchSubRows = cRows
					branchOwn = cOwn
					branchSurp = cSurp
				end
			end
		end

		local ov = item.forceBuy and "buy" or (overrides and overrides[id])
		-- A Turn-In is bought unless the user overrides it.
		local topModeOk = item.role ~= "Turn-In" and canAutoSubCraft(craftOpt, subMode)
		local eligibleSub = branchComplete and craftTotal ~= nil and topModeOk
		local madeStep = (craftOpt and math.max(1, tonumber(craftOpt.numMade) or 1)) or 1
		local mixTopCands, anyTopMixChanged = nil, false
		if qty > 0 and topModeOk and ov == nil and not item.forceMakeMyself and not isVendor and ahUnit ~= nil and not (hasAllocation or item.purchaseQuotes) then
			local mixQtys = collectMixCraftQtys(craftOpt, qty, remOwned, remSurplus, topIdx, nil)
			if mixQtys then
				for _, mCraftQty in ipairs(mixQtys) do
					local mc, mok, _, mo, ms = evalCraftBranch(craftOpt, mCraftQty, 1, remOwned, remSurplus, topIdx, {}, true, id, true)
					if mok and mc ~= nil then
						mixTopCands = mixTopCands or {}
						if hasConsumedOwned(remOwned, mo) or hasChangedSurplus(remSurplus, ms, 0) then
							anyTopMixChanged = true
						end
						local mBuyQty = qty - mCraftQty
						local mBuyCost = ahUnit * mBuyQty
						mixTopCands[#mixTopCands + 1] = {
							craftQty = mCraftQty,
							buyQty = mBuyQty,
							craftCost = mc,
							buyCost = mBuyCost,
							total = mc + mBuyCost,
							own = mo,
							surp = ms,
						}
					end
				end
			end
		end

		local topRoute, chosenTopMix = "buy", nil
		if qty > 0 and not isVendor and ((branchComplete and craftTotal ~= nil) or mixTopCands ~= nil) then
			if ov == "craft" then
				if branchComplete and craftTotal ~= nil then topRoute = "craft" end
			elseif ov == "buy" then
				topRoute = "buy"
			elseif item.forceMakeMyself then
				if branchComplete and craftTotal ~= nil then topRoute = "craft" end
			elseif topModeOk then
				if ahTotal == nil then
					if eligibleSub then topRoute = "craft" end
				else
					local madeTotal = math.ceil(qty / madeStep) * madeStep
					local extraSelf = madeTotal - qty
					if (eligibleSub and (hasConsumedOwned(remOwned, branchOwn) or hasChangedSurplus(remSurplus, branchSurp, extraSelf))) or anyTopMixChanged then
						local bestRoute = "buy"
						local remBuy, missBuy = simRemainingCost(remOwned, remSurplus, topIdx, nil)
						local bestCost, bestMiss = ahTotal + remBuy, missBuy
						if eligibleSub then
							local craftSurp = clonePool(branchSurp) or {}
							if extraSelf > 0 then
								craftSurp[id] = (craftSurp[id] or 0) + extraSelf
							end
							local remCraft, missCraft = simRemainingCost(branchOwn, craftSurp, topIdx, nil)
							local candCraft = craftTotal + remCraft
							if missCraft < bestMiss or (missCraft == bestMiss and candCraft < bestCost) then
								bestRoute, bestCost, bestMiss = "craft", candCraft, missCraft
							end
						end
						if mixTopCands then
							for _, mcand in ipairs(mixTopCands) do
								local remMix, missMix = simRemainingCost(mcand.own, mcand.surp or {}, topIdx, nil)
								local candMix = mcand.total + remMix
								if missMix < bestMiss or (missMix == bestMiss and candMix < bestCost) then
									bestRoute, bestCost, bestMiss, chosenTopMix = "mix", candMix, missMix, mcand
								end
							end
						end
						topRoute = bestRoute
					else
						local bestM = nil
						if mixTopCands then
							for _, mcand in ipairs(mixTopCands) do
								if not bestM or mcand.total < bestM.total then bestM = mcand end
							end
						end
						if bestM and bestM.total < ahTotal and (not eligibleSub or bestM.total < craftTotal) then
							topRoute, chosenTopMix = "mix", bestM
						elseif eligibleSub and craftTotal < ahTotal then
							topRoute = "craft"
						end
					end
				end
			end
		end

		if topRoute == "mix" and chosenTopMix then
			local floorQty = chosenTopMix.craftQty
			local remBuyQty = chosenTopMix.buyQty
			local mixCraftCost = chosenTopMix.craftCost
			local mixBuyCost = chosenTopMix.buyCost
			local mixTotal = chosenTopMix.total
			local _, _, mixRows, mo, ms = evalCraftBranch(craftOpt, floorQty, 1, remOwned, remSurplus, topIdx, {}, true, id, false)
			remOwned = mo or chosenTopMix.own
			remSurplus = ms or chosenTopMix.surp or remSurplus
			totalCost = totalCost + mixTotal
			local mixCraftUnit = math.floor((mixCraftCost / math.max(1, floorQty)) + 0.5)
			local remIncCraft, remIncCraftUnit = nil, nil
			if craftTotal ~= nil then
				remIncCraft = math.max(0, craftTotal - mixCraftCost)
				remIncCraftUnit = math.floor((remIncCraft / math.max(1, remBuyQty)) + 0.5)
			end
			local canNow = canCraftRecipeNow(craftOpt)
			local isSameP = (craftOpt and craftOpt.sameProf) and true or false
			local iconTex = ns.ItemIcon(id, ns.QUESTION_ICON)
			local topCD = (craftOpt and craftOpt.cd) or 0
			local topCDWin = (craftOpt and craftOpt.cdWindowSec) or 0
			local topCDLbl = (craftOpt and craftOpt.cdLabel) or nil
			local topMixCraftAct = (topCD >= 60 and topCDLbl)
				and ("Craft (" .. craftOpt.profLabel .. ", " .. topCDLbl .. " CD)")
				or ("Craft (" .. craftOpt.profLabel .. ")")
			rows[#rows + 1] = {
				itemID = id,
				name = name,
				icon = iconTex,
				role = item.role,
				indent = 0,
				qty = floorQty,
				rawQty = floorQty + usedOwn + usedSurp,
				owned = owned,
				ownedUsed = usedOwn,
				surplusUsed = usedSurp,
				listed = listed,
				dailySold = dailySold,
				isVendor = false,
				ahUnitPrice = ahUnit,
				ahTotalPrice = ahUnit * floorQty,
				ahSource = ahSrc,
				craftUnitPrice = mixCraftUnit,
				craftTotalPrice = mixCraftCost,
				craftProfLabel = craftOpt and craftOpt.profLabel or nil,
				craftCD = topCD,
				craftCDWindow = topCDWin,
				craftCDLabel = topCDLbl,
				craftCanDo = canNow,
				craftSameProf = isSameP,
				canToggleCraft = true,
				makeMyself = true,
				action = topMixCraftAct,
				lineCost = mixCraftCost,
				hitPriceJump = false,
				isSubRow = false,
			}
			if mixRows then
				for _, sr in ipairs(mixRows) do
					rows[#rows + 1] = sr
				end
			end
			rows[#rows + 1] = {
				itemID = id,
				name = name,
				icon = iconTex,
				role = item.role,
				indent = 0,
				qty = remBuyQty,
				rawQty = remBuyQty,
				owned = owned,
				ownedUsed = 0,
				surplusUsed = 0,
				listed = listed,
				dailySold = dailySold,
				isVendor = false,
				ahUnitPrice = ahUnit,
				ahTotalPrice = mixBuyCost,
				ahSource = ahSrc,
				craftUnitPrice = remIncCraftUnit,
				craftTotalPrice = remIncCraft,
				craftProfLabel = craftOpt and craftOpt.profLabel or nil,
				craftCD = topCD,
				craftCDWindow = topCDWin,
				craftCDLabel = topCDLbl,
				craftCanDo = canNow,
				craftSameProf = isSameP,
				canToggleCraft = (remIncCraft ~= nil),
				makeMyself = false,
				action = "Buy AH",
				lineCost = mixBuyCost,
				hitPriceJump = false,
				isSubRow = false,
			}
		else
			local makeMyself = (topRoute == "craft")
			local topCD = (craftOpt and craftOpt.cd) or 0
			local topCDWin = (craftOpt and craftOpt.cdWindowSec) or 0
			local topCDLbl = (craftOpt and craftOpt.cdLabel) or nil
			local action, lineCost
			if qty == 0 and (usedOwn + usedSurp) > 0 then
				local surpTag = (opts.sharedCartReusedIDs and opts.sharedCartReusedIDs[id]) and "Reused" or "Surplus"
				if usedOwn > 0 and usedSurp > 0 then
					action = string.format("Owned (%dx) + %s (%dx)", usedOwn, surpTag, usedSurp)
				elseif usedOwn > 0 then
					action = string.format("Owned (%dx)", rawQty)
				else
					action = string.format("%s (%dx)", surpTag, rawQty)
				end
				lineCost = 0
			elseif isVendor then
				action = "Vendor"
				lineCost = ahTotal
			elseif makeMyself then
				action = (topCD >= 60 and topCDLbl)
					and ("Craft (" .. craftOpt.profLabel .. ", " .. topCDLbl .. " CD)")
					or ("Craft (" .. craftOpt.profLabel .. ")")
				lineCost = craftTotal
				remOwned = branchOwn
				remSurplus = branchSurp or remSurplus
				local madeTotal = math.ceil(qty / madeStep) * madeStep
				if madeTotal > qty then
					remSurplus[id] = (remSurplus[id] or 0) + (madeTotal - qty)
				end
			else
				action = "Buy AH"
				lineCost = ahTotal
			end

			if lineCost ~= nil then
				totalCost = totalCost + lineCost
			else
				missingPriceCount = missingPriceCount + 1
			end

			local topRow = {
				itemID = id,
				name = name,
				icon = ns.ItemIcon(id, ns.QUESTION_ICON),
				role = item.role,
				indent = 0,
				qty = qty,
				rawQty = rawQty,
				owned = owned,
				ownedUsed = usedOwn,
				surplusUsed = usedSurp,
				listed = listed,
				dailySold = dailySold,
				isVendor = isVendor,
				ahUnitPrice = ahUnit,
				ahTotalPrice = ahTotal,
				ahSource = ahSrc,
				craftUnitPrice = craftUnit,
				craftTotalPrice = craftTotal,
				craftProfLabel = craftOpt and craftOpt.profLabel or nil,
				craftCD = topCD,
				craftCDWindow = topCDWin,
				craftCDLabel = topCDLbl,
				craftCanDo = canCraftRecipeNow(craftOpt),
				craftSameProf = (craftOpt and craftOpt.sameProf) and true or false,
				canToggleCraft = (not isVendor) and (craftTotal ~= nil) and (qty > 0),
				makeMyself = makeMyself,
				action = action,
				lineCost = lineCost,
				hitPriceJump = (not makeMyself and item.hitPriceJump) or false,
				isSubRow = false,
			}
			rows[#rows + 1] = topRow

			if makeMyself and branchSubRows then
				for _, sr in ipairs(branchSubRows) do
					rows[#rows + 1] = sr
				end
			end
		end
	end

	local function syncPoolInPlace(dst, src)
		if not dst or dst == src then return end
		for k in pairs(dst) do dst[k] = nil end
		if src then
			for k, v in pairs(src) do dst[k] = v end
		end
	end
	if opts.sharedOwnedPool and remOwned then
		syncPoolInPlace(opts.sharedOwnedPool, remOwned)
	end
	if opts.sharedSurplusPool and remSurplus then
		syncPoolInPlace(opts.sharedSurplusPool, remSurplus)
	end
	if useAllocationCosts then totalCost = math.floor(totalCost + 0.5) end
	return rows, totalCost, missingPriceCount
end

function ns.BuildShoppingListRows(demandList, opts)
	ns.BeginEval()
	local ok, r1, r2, r3 = pcall(buildShoppingListRowsImpl, demandList, opts)
	ns.EndEval()
	if not ok then error(r1, 0) end
	return r1, r2, r3
end

function ns.ResolveCraftingOrderRecipe(ref, profMap, allowDefault)
	local function mpFallbackRecipe(spID, rProf)
		local mp = ns.MP
		local m = spID and spID > 0 and mp and mp.RECIPES_BY_SPELL and mp.RECIPES_BY_SPELL[spID] or nil
		if not (m and m.src ~= "gather" and type(m.r) == "table" and #m.r > 0) then return nil end
		if rProf and m.prof and m.prof ~= rProf then return nil end
		ns._mpSynthRecipes = ns._mpSynthRecipes or {}
		if not ns._mpSynthRecipes[spID] then
			ns._mpSynthRecipes[spID] = {
				spellID = m.s,
				outputItemID = (m.i and m.i > 0) and m.i or nil,
				recipeItemID = m.ri,
				name = m.n,
				recipeName = m.rn or m.n,
				prof = m.prof,
				skill = m.req or 1,
				numMade = m.c or 1,
				reagents = m.r,
				isEnchant = (m.ench == true),
				sellable = (not m.ench) and (not m.bop) and ((m.i or 0) > 0),
				recipeVendorPrice = m.rbuy,
				favorCost = m.fav or 0,
				rep = m.rep or 0,
				repFactionID = m.repFacID,
				repFaction = m.repFac,
				source = m.src,
				acqType = m.src,
				cd = m.cd,
			}
		end
		return ns._mpSynthRecipes[spID]
	end
	if ref ~= nil then
		if type(ref) == "table" then
			if ref.recipe and type(ref.recipe) == "table" then
				return ref.recipe
			end
			if ref.reagents and ref.prof and not ref.craftBreakdown then
				return ref
			end
			local rIdx = tonumber(ref.idx)
			local spID = tonumber(ref.spellID)
			local outID = tonumber(ref.outputItemID or ref.itemID)
			local rProf = type(ref.prof) == "string" and ref.prof or nil
			if rIdx and ns.RECIPES and ns.RECIPES[rIdx] then
				local cand = ns.RECIPES[rIdx]
				if ns.GetRecipeSourceBucket(cand) ~= "gather"
					and (not rProf or cand.prof == rProf)
					and (not spID or spID <= 0 or cand.spellID == spID)
					and (not outID or outID <= 0 or cand.outputItemID == outID)
					and ((spID and spID > 0) or (outID and outID > 0)) then
					return cand
				end
			end
			if spID and spID > 0 then
				for _, rec in ipairs(ns.RECIPES or {}) do
					if rec.spellID == spID and (not rProf or rec.prof == rProf) and ns.GetRecipeSourceBucket(rec) ~= "gather" then
						return rec
					end
				end
				return mpFallbackRecipe(spID, rProf)
			end
			if outID and outID > 0 then
				local best = ns.SelectBestRecipeForItem(outID, rProf, profMap)
				if best and (not rProf or best.prof == rProf) then return best end
				for _, rec in ipairs(ns.RECIPES or {}) do
					if rec.outputItemID == outID and (not rProf or rec.prof == rProf) and ns.GetRecipeSourceBucket(rec) ~= "gather" then
						return rec
					end
				end
				return nil
			end
			return nil
		elseif type(ref) == "number" and ref > 0 then
			local best = ns.SelectBestRecipeForItem(ref, nil, profMap)
			if best then return best end
			for _, rec in ipairs(ns.RECIPES or {}) do
				if rec.outputItemID == ref and ns.GetRecipeSourceBucket(rec) ~= "gather" then
					return rec
				end
			end
			return nil
		else
			return nil
		end
	end
	if allowDefault == false then
		return nil
	end
	for _, rec in ipairs(ns.RECIPES or {}) do
		if ns.GetRecipeSourceBucket(rec) ~= "gather" and rec.outputItemID and rec.outputItemID > 0 then
			return rec
		end
	end
	return ns.RECIPES and ns.RECIPES[1] or nil
end

---------------------------------------------------------------------------------------------------
-- Unified Hierarchical Shopping List Builders & Sorters
---------------------------------------------------------------------------------------------------

local function shoppingSortVal(r, col)
	if not r then return nil end
	if col == "name" then
		return (r.name or ""):lower()
	elseif col == "category" then
		if r.isMainRow then
			return (r.sourceLabel or r.categoryName or ""):lower()
		elseif r.isSubRow then
			return (r.subCategoryLabel or r.parentSubName or r.categoryName or ""):lower()
		end
		return (r.categoryName or r.role or ""):lower()
	elseif col == "qty" then
		return tonumber(r.qty) or 0
	elseif col == "listed" then
		return tonumber(r.listed)
	elseif col == "dailySold" then
		return tonumber(r.dailySold)
	elseif col == "ahPrice" then
		return tonumber(r.ahUnitPrice)
	elseif col == "craftPrice" then
		return tonumber(r.craftUnitPrice)
	elseif col == "action" then
		return (r.action or ""):lower()
	elseif col == "lineCost" or col == "cost" then
		if r.isMainRow then
			return tonumber(r.groupTotalCost or r.craftTotalPrice)
		end
		return tonumber(r.lineCost)
	end
	return nil
end

local function compareHierarchyRows(ra, rb, col, asc, orderA, orderB)
	local va = shoppingSortVal(ra, col)
	local vb = shoppingSortVal(rb, col)
	if va == nil and vb == nil then
		local na = (ra and ra.name or ""):lower()
		local nb = (rb and rb.name or ""):lower()
		if na ~= nb then return na < nb end
		return (orderA or 0) < (orderB or 0)
	end
	if va == nil then return false end
	if vb == nil then return true end
	if va == vb then
		local na = (ra and ra.name or ""):lower()
		local nb = (rb and rb.name or ""):lower()
		if na ~= nb then return na < nb end
		return (orderA or 0) < (orderB or 0)
	end
	if asc then
		return va < vb
	end
	return va > vb
end

function ns.SortHierarchicalShoppingRows(rows, sortCol, sortAsc, sortScope)
	if type(rows) ~= "table" or #rows == 0 then return {} end
	local scope = (sortScope == "sub") and "sub" or "main"
	local asc = (sortAsc ~= false)
	local col = (sortCol and sortCol ~= "" and sortCol ~= "default") and sortCol or nil

	if scope == "sub" then
		local branches = {}
		local curBranch = nil
		for _, r in ipairs(rows) do
			if not r.isMainRow then
				if not r.isSubRow then
					curBranch = { subRow = r, children = {}, order = #branches + 1 }
					branches[#branches + 1] = curBranch
				elseif curBranch then
					curBranch.children[#curBranch.children + 1] = r
				else
					-- Defensive fallback if an isolated sub-row appears without a Level 1 parent
					branches[#branches + 1] = { subRow = r, children = {}, order = #branches + 1 }
				end
			end
		end
		local effCol = col or "name"
		local effAsc = col and asc or true
		table.sort(branches, function(a, b)
			return compareHierarchyRows(a.subRow, b.subRow, effCol, effAsc, a.order, b.order)
		end)
		local sorted = {}
		for _, b in ipairs(branches) do
			sorted[#sorted + 1] = b.subRow
			for _, c in ipairs(b.children) do
				sorted[#sorted + 1] = c
			end
		end
		return sorted
	end

	-- scope == "main": group rows by Main Item block and keep each block's Sub-Items + crafted sub-reagents together
	local hasAnyMain = false
	for _, r in ipairs(rows) do
		if r.isMainRow then
			hasAnyMain = true
			break
		end
	end
	local blocks = {}
	local curBlock = nil
	for _, r in ipairs(rows) do
		if r.isMainRow or (not hasAnyMain and not r.isSubRow) then
			curBlock = { mainRow = r, subRows = {}, order = #blocks + 1 }
			blocks[#blocks + 1] = curBlock
		elseif curBlock then
			curBlock.subRows[#curBlock.subRows + 1] = r
		else
			curBlock = { mainRow = r, subRows = {}, order = #blocks + 1 }
			blocks[#blocks + 1] = curBlock
		end
	end
	if col then
		table.sort(blocks, function(a, b)
			return compareHierarchyRows(a.mainRow, b.mainRow, col, asc, a.order, b.order)
		end)
	end
	local out = {}
	for _, blk in ipairs(blocks) do
		out[#out + 1] = blk.mainRow
		for _, sr in ipairs(blk.subRows) do
			out[#out + 1] = sr
		end
	end
	return out
end

function ns.BuildCraftOrderGroups(queueEntries)
	local groups = {}
	local seenKeys = {}
	for idx, qe in ipairs(queueEntries or {}) do
		local qRec = qe.recipe
		local qBatches = math.max(1, tonumber(qe.batches) or 1)
		local baseKey = "craft:" .. tostring(qe.spellID or qe.outputItemID or qe.idx or idx)
		local key = baseKey
		if seenKeys[key] then
			seenKeys[key] = seenKeys[key] + 1
			key = baseKey .. ":" .. tostring(qe.queueIndex or idx)
		else
			seenKeys[key] = 1
		end
		local demand = {}
		local qReagents = (type(qe.reagentOverride) == "table" and #qe.reagentOverride > 0) and qe.reagentOverride
			or (qRec and ns.ResolveRecipeReagents(qRec)) or {}
		for _, pair in ipairs(qReagents) do
			local id = type(pair) == "table" and (pair[1] or pair.itemID or pair.id) or nil
			local cnt = type(pair) == "table" and (pair[2] or pair.qty or pair.count) or nil
			if id and cnt and cnt > 0 then
				demand[#demand + 1] = {
					itemID = id,
					qty = cnt * qBatches,
					role = "Reagent",
					parentProf = qe.prof or (qRec and qRec.prof),
				}
			end
		end
		local outQty = qe.actualOutput or qe.reqQty or 1
		local reusedQty = tonumber(qe.reusedQty) or 0
		if reusedQty > 0 then
			reusedQty = math.min(outQty, math.floor(reusedQty + 0.5))
		else
			reusedQty = nil
		end
		groups[#groups + 1] = {
			key = key,
			mainName = qe.name or (qe.outputItemID and ns.ItemName(qe.outputItemID)) or "Craft Order",
			mainItemID = qe.outputItemID,
			spellID = qe.spellID,
			prof = qe.prof,
			qty = outQty,
			batches = qBatches,
			reusedQty = reusedQty,
			buyCaps = (type(qe.buyCaps) == "table") and qe.buyCaps or nil,
			sourceKind = "craft_order",
			sourceLabel = "Crafting Order",
			removeRef = {
				sourceKind = "craft_order",
				queueIndex = qe.queueIndex or idx,
				idx = qe.idx,
				spellID = qe.spellID,
				outputItemID = qe.outputItemID,
				prof = qe.prof,
			},
			demandList = demand,
		}
	end
	return groups
end

function ns.ComputeShoppingBuckets(rows)
	local b = {
		ahCount = 0,
		ahUnits = 0,
		ahCost = 0,
		craftCount = 0,
		craftUnits = 0,
		craftSavings = 0,
		vendorCount = 0,
		vendorCost = 0,
		ownedCount = 0,
	}
	for _, r in ipairs(rows or {}) do
		if type(r) == "table" and not r.isMainRow then
			local qty = tonumber(r.qty) or 0
			local lineCost = tonumber(r.lineCost) or 0
			if r.makeMyself then
				b.craftCount = b.craftCount + 1
				b.craftUnits = b.craftUnits + qty
				if r.ahTotalPrice and r.craftTotalPrice and r.ahTotalPrice > r.craftTotalPrice then
					b.craftSavings = b.craftSavings + (r.ahTotalPrice - r.craftTotalPrice)
				end
			elseif ((r.ownedUsed or 0) > 0 or (r.surplusUsed or 0) > 0) and qty == 0 then
				b.ownedCount = b.ownedCount + 1
			elseif r.isVendor then
				b.vendorCount = b.vendorCount + 1
				b.vendorCost = b.vendorCost + lineCost
			else
				b.ahCount = b.ahCount + 1
				b.ahUnits = b.ahUnits + qty
				b.ahCost = b.ahCost + lineCost
			end
		end
	end
	return b
end

function ns.BuildHierarchicalShoppingList(groups, opts)
	opts = opts or {}
	local deductOwned = (opts.deductOwned == true)
	local sharedOwned
	if deductOwned then
		sharedOwned = {}
		for k, v in pairs(opts.ownedCounts or {}) do
			if type(v) == "number" and v > 0 then
				sharedOwned[k] = v
			end
		end
	end
	local sharedSurplus = {}
	local sharedCartReusedIDs = {}
	local sharedGroupProfs = {}
	for _, grp in ipairs(groups or {}) do
		local rQty = tonumber(grp.reusedQty) or 0
		if rQty > 0 and grp.sourceKind == "craft_order" and grp.mainItemID and grp.mainItemID > 0 then
			local grpOut = math.max(1, tonumber(grp.qty) or 1)
			local credit = math.min(grpOut, math.floor(rQty + 0.5))
			if credit > 0 then
				sharedSurplus[grp.mainItemID] = (sharedSurplus[grp.mainItemID] or 0) + credit
				sharedCartReusedIDs[grp.mainItemID] = true
			end
		end
		if type(grp.prof) == "string" and grp.prof ~= "" then
			sharedGroupProfs[grp.prof] = true
		end
		if type(grp.demandList) == "table" then
			for _, d in ipairs(grp.demandList) do
				if type(d.parentProf) == "string" and d.parentProf ~= "" then
					sharedGroupProfs[d.parentProf] = true
				end
				if type(d.parentProfs) == "table" then
					for pk, pv in pairs(d.parentProfs) do
						if pv and type(pk) == "string" and pk ~= "" then
							sharedGroupProfs[pk] = true
						end
					end
				end
			end
		end
	end

	local outRows = {}
	local grandTotalCost = 0
	local grandMissing = 0
	local mainCount = 0

	for gIdx, grp in ipairs(groups or {}) do
		local groupKey = tostring(grp.key or ("grp:" .. tostring(gIdx)))
		local demandList = grp.demandList
		if (not demandList or #demandList == 0) and grp.mainItemID then
			demandList = {
				{
					itemID = grp.mainItemID,
					qty = math.max(1, tonumber(grp.qty) or 1),
					role = grp.sourceLabel or "Shopping",
					parentProf = grp.prof,
				},
			}
		end

		local subOpts = {
			profMap = opts.profMap,
			repState = opts.repState,
			subCraftMode = opts.subCraftMode,
			subCraftOverrides = opts.subCraftOverrides,
			ownedCounts = opts.ownedCounts,
			deductOwned = deductOwned,
			spentPool = opts.spentPool,
			overridePrefix = groupKey,
			sharedOwnedPool = sharedOwned,
			sharedSurplusPool = sharedSurplus,
			sharedCartReusedIDs = sharedCartReusedIDs,
		}

		local subRows, grpCost, grpMissing = {}, 0, 0
		if demandList and #demandList > 0 then
			local effDemand = {}
			for idx, d in ipairs(demandList) do
				local entry = {}
				for k, v in pairs(d) do
					entry[k] = v
				end
				local mergedProfs = {}
				for pk, pv in pairs(sharedGroupProfs) do
					if pv then mergedProfs[pk] = true end
				end
				if type(d.parentProf) == "string" and d.parentProf ~= "" then
					mergedProfs[d.parentProf] = true
				end
				if type(d.parentProfs) == "table" then
					for pk, pv in pairs(d.parentProfs) do
						if pv and type(pk) == "string" and pk ~= "" then
							mergedProfs[pk] = true
						end
					end
				end
				if next(mergedProfs) ~= nil then
					entry.parentProfs = mergedProfs
				end
				effDemand[idx] = entry
			end
			subRows, grpCost, grpMissing = ns.BuildShoppingListRows(effDemand, subOpts)
		end
		grpMissing = (grpMissing or 0) + (grp.missingDemandCount or 0)

		local grpQty = math.max(1, tonumber(grp.qty) or 1)
		local mainTotalCost = (type(grpCost) == "number") and grpCost or nil
		local mainName = grp.mainName or (grp.mainItemID and ns.ItemName(grp.mainItemID)) or "Item"
		local showMainMarket = grp.mainItemID and (not grp.isBundle)
		local ahUnit = showMainMarket and select(1, ns.GetReagentUnitCost(grp.mainItemID)) or nil

		local mainRow = {
			isMainRow = true,
			rowKind = "main",
			indent = 0,
			mainGroupKey = groupKey,
			key = groupKey,
			itemID = grp.mainItemID,
			spellID = grp.spellID,
			prof = grp.prof,
			name = mainName,
			icon = grp.mainItemID and ns.ItemIcon(grp.mainItemID, ns.QUESTION_ICON) or ns.QUESTION_ICON,
			categoryName = grp.sourceLabel or "Main Item",
			sourceKind = grp.sourceKind or "shopping",
			sourceLabel = grp.sourceLabel or "Main Item",
			role = grp.sourceLabel or "Main Item",
			qty = grpQty,
			batches = grp.batches,
			listed = showMainMarket and ns.GetNumListed(grp.mainItemID) or nil,
			dailySold = showMainMarket and ns.GetDailySold(grp.mainItemID) or nil,
			ahUnitPrice = ahUnit,
			craftUnitPrice = (mainTotalCost and grpQty > 0) and math.floor((mainTotalCost / grpQty) + 0.5) or nil,
			craftTotalPrice = mainTotalCost,
			groupTotalCost = mainTotalCost,
			groupMissingCount = grpMissing or 0,
			lineCost = nil, -- keep nil on Level 0 header so leaf-cost loops never double-count
			makeMyself = false,
			isVendor = false,
			canToggleCraft = false,
			canRemoveMain = (grp.removeRef ~= nil),
			removeRef = grp.removeRef,
			action = "Remove",
		}
		outRows[#outRows + 1] = mainRow
		mainCount = mainCount + 1

		local subIdx = 0
		local currentSubKey, currentSubName
		for _, r in ipairs(subRows or {}) do
			r.mainGroupKey = groupKey
			r.categoryName = mainName
			r.sourceKind = mainRow.sourceKind
			r.sourceLabel = mainRow.sourceLabel
			r.mainRemoveRef = grp.removeRef
			if r.itemID then
				r.overrideKey = groupKey .. ":" .. tostring(r.itemID)
			end
			local cap = (type(grp.buyCaps) == "table" and r.itemID) and grp.buyCaps[r.itemID] or nil
			if type(cap) == "table" then
				local capMax = tonumber(cap.maxBuyUnit)
				if capMax and capMax > 0 then
					local prev = tonumber(r.maxBuyUnit)
					r.maxBuyUnit = (prev and prev > 0) and math.min(prev, capMax) or capMax
				end
				local capBE = tonumber(cap.breakEvenUnit)
				if capBE and capBE > 0 then
					local prev = tonumber(r.breakEvenUnit)
					r.breakEvenUnit = (prev and prev > 0) and math.min(prev, capBE) or capBE
				end
				local capWall = tonumber(cap.wallUnit)
				if capWall and capWall > 0 then
					local prevW = tonumber(r.wallUnit)
					r.wallUnit = (prevW and prevW > 0) and math.min(prevW, capWall) or capWall
				end
				local capAvg = tonumber(cap.avgBuyUnit)
				if capAvg and capAvg > 0 and not r.avgBuyUnit then
					r.avgBuyUnit = capAvg
				end
				if cap.source and not r.buyCapSource then
					r.buyCapSource = cap.source
				end
			end
			if not r.isSubRow then
				subIdx = subIdx + 1
				currentSubKey = groupKey .. ":sub:" .. tostring(subIdx)
				currentSubName = r.name or (r.itemID and ns.ItemName(r.itemID)) or "Item"
				r.subGroupKey = currentSubKey
				r.isSubBranchRoot = true
				r.rowKind = "sub"
				r.indent = 1
				r.role = mainName
			else
				r.subGroupKey = currentSubKey or (groupKey .. ":sub:0")
				r.parentSubName = currentSubName
				r.rowKind = "sub_craft"
				local baseIndent = tonumber(r.indent) or 1
				r.indent = 1 + baseIndent
				r.subCategoryLabel = currentSubName and (mainName .. " -> " .. currentSubName) or mainName
			end
			outRows[#outRows + 1] = r
		end

		grandTotalCost = grandTotalCost + (grpCost or 0)
		grandMissing = grandMissing + (grpMissing or 0)
	end

	return outRows, grandTotalCost, grandMissing, {
		mainCount = mainCount,
		groups = groups or {},
		buckets = ns.ComputeShoppingBuckets(outRows),
	}
end

local function sortedPositiveQueueKeys(tbl)
	local keys = {}
	if type(tbl) ~= "table" then return keys end
	for k, v in pairs(tbl) do
		if (tonumber(v) or 0) > 0 then
			keys[#keys + 1] = k
		end
	end
	table.sort(keys, function(a, b)
		local na, nb = tonumber(a), tonumber(b)
		if na and nb then return na < nb end
		return tostring(a) < tostring(b)
	end)
	return keys
end

function ns.ResolveSpreadQueueRecipe(key, profMap)
	local spellID = type(key) == "string" and tonumber(key:match("^spell:(%d+)$")) or nil
	return ns.ResolveCraftingOrderRecipe(spellID and { spellID = spellID } or tonumber(key), profMap, false)
end

local function resolveDemandFromReagents(reagents, batches, prof)
	local demand = {}
	local b = math.max(1, tonumber(batches) or 1)
	for _, rg in ipairs(reagents or {}) do
		local id = type(rg) == "table" and (rg.itemID or rg.id or rg[1]) or nil
		local qty = type(rg) == "table" and (rg.qty or rg.count or rg[2]) or nil
		if id and qty and qty > 0 then
			demand[#demand + 1] = {
				itemID = id,
				qty = qty * b,
				role = "Reagent",
				parentProf = prof,
			}
		end
	end
	return demand
end

local function crateIDFromRow(row)
	if type(row) == "table" then
		row = row.crateID or row.itemID or (row.crate and row.crate.itemID)
	end
	local id = tonumber(row)
	return id and id > 0 and id or nil
end

local function forgedReceiptTerms(row, opts)
	local receipt = ns.FORGED_RECEIPT or {}
	local favor = tonumber(receipt.favorCost) or tonumber(row.favorRequired) or 15
	local refund = tonumber(receipt.refundCopper) or tonumber(row.forgedRefund) or 100
	local baseRep = tonumber(row.baseRep) or tonumber(receipt.baseRep) or 50
	local racialMult = nil
	if opts.humanDiplomacy ~= nil then
		if ns.GetRacialRepMultiplier then
			racialMult = ns.GetRacialRepMultiplier(opts.humanDiplomacy)
		else
			local hMult = (receipt.racialMultipliers and tonumber(receipt.racialMultipliers.Human)) or 1.1
			racialMult = opts.humanDiplomacy and hMult or 1.0
		end
	end
	local multiplier = tonumber(opts.repMult)
		or racialMult
		or tonumber(row.repMult)
		or (ns.GetRacialRepMultiplier and ns.GetRacialRepMultiplier())
		or 1.0
	local rep = (opts.humanDiplomacy == nil and opts.repMult == nil and tonumber(row.rep))
		or math.floor(baseRep * multiplier + 0.5)
	return favor, refund, multiplier, rep
end

local function forgedTurnInNPC(receipt, faction)
	if faction == "Alliance" then return (receipt.turnInAlliance or {}).name or "Marcy Baker" end
	if faction == "Horde" then return (receipt.turnInHorde or {}).name or "Dokimi" end
	return "Marcy Baker / Dokimi"
end

local function appendCrateTurnInDemand(demand, row, count, crateID)
	local function add(item)
		if not item.itemID or item.itemID <= 0 then return 1 end
		if item.actualUnit ~= nil and ns.GetReagentUnitCost(item.itemID) ~= nil then
			item.actualUnit = nil
		end
		demand[#demand + 1] = item
		return 0
	end

	local missing = add({
		itemID = crateID or crateIDFromRow(row),
		qty = count,
		role = "Crate",
		itemName = row.crateFullName or (row.crate and row.crate.name) or row.name or row.crateName,
		actualUnit = tonumber(row.emptyPrice or row.cratePrice),
		actualSource = row.crateSource or row.source or "Crate Quote",
	})

	local mats = row.matDetails
	if type(mats) ~= "table" or #mats == 0 then
		local bundles = row.bundles or (row.crate and row.crate.bundles)
		mats = {{
			itemID = row.reagentID,
			name = row.reagentName,
			qty = row.reagentQty,
			prof = row.prof,
			mode = row.mode,
			makeMyself = row.makeMyself,
			unitPrice = row.buyEach or row.reagentEach,
			source = row.buySource or row.reagentSource,
		}}
		if not row.reagentID and bundles and bundles[1] then mats = { bundles[1] } end
	end
	for _, mat in ipairs(mats) do
		local qty = tonumber(mat.qty) or 1
		if qty > 0 then
			missing = missing + add({
				itemID = tonumber(mat.itemID),
				itemName = mat.name,
				qty = qty * count,
				role = "Reagent",
				parentProf = mat.prof or row.prof,
				forceMakeMyself = mat.mode == "Craft" or mat.makeMyself == true,
				actualUnit = tonumber(mat.unitPrice),
				actualSource = mat.source or "Material Quote",
			})
		end
	end
	return missing
end

local function buildForgedDemandAndPlan(forgedRow, turnInCount, opts, fallbackCrateID)
	local crateID = crateIDFromRow(forgedRow) or fallbackCrateID
	if not crateID then return nil end
	if type(forgedRow) ~= "table" then forgedRow = { crateID = crateID } end
	opts = opts or {}
	local count = math.max(1, math.floor((tonumber(turnInCount) or 1) + 0.5))
	local mode = opts.forgedMode or forgedRow.forgedMode or "self_funded"
	local favorEach, refundEach, repMult, repEach = forgedReceiptTerms(forgedRow, opts)
	local receiptFavor = count * favorEach
	local favorNeeded = (mode ~= "banked") and receiptFavor or 0
	local forgedRefund, repEarned = count * refundEach, count * repEach
	local crateName = forgedRow.crateFullName or forgedRow.name or forgedRow.crateName
	local emptyPrice, emptySource = tonumber(forgedRow.emptyPrice), forgedRow.source
	if forgedRow.emptyPrice == nil and ns.GetItemMarketPrice then
		emptyPrice, emptySource = ns.GetItemMarketPrice(crateID)
	end
	local demand = {{
		itemID = crateID,
		itemName = crateName,
		qty = count,
		role = "Crate",
		actualUnit = emptyPrice,
		actualSource = emptySource or "Crate Quote",
	}}
	crateName = crateName or ns.ItemName(crateID) or ("Crate #" .. tostring(crateID))

	local feeder, feederCount, leftoverFavor, favorRefund, missingDemand = nil, 0, 0, 0, 0
	local steps = {}
	if mode ~= "banked" then
		feeder = opts.bestFavorCrate or forgedRow.bestFavorCrate
		if not feeder and ns.BuildCrateRows then
			feeder = select(2, ns.BuildCrateRows({
				bestOnly = false,
				crateMode = opts.crateMode or "cheapest",
				subCraftMode = opts.subCraftMode,
				subCraftOverrides = opts.subCraftOverrides,
				profMap = opts.profMap,
				repState = opts.repState,
			}))
		end
		if type(feeder) == "table" then
			local tokens, reward
			if feeder.crate and ns.GetCrateReward then tokens, reward = ns.GetCrateReward(feeder.crate) end
			local feederFavor = tonumber(feeder.favor or feeder.tokens) or tokens
			if feederFavor and feederFavor > 0 then
				feederCount = math.ceil(favorNeeded / feederFavor)
				local earnedFavor = feederCount * feederFavor
				leftoverFavor = earnedFavor - favorNeeded
				favorRefund = feederCount * (tonumber(feeder.rewardCopper or feeder.reward or feeder.cashback) or reward or 0)
				if feederCount > 0 then
					missingDemand = appendCrateTurnInDemand(demand, feeder, feederCount)
					local name = feeder.crateFullName or feeder.name or feeder.crateName or "Favor Crate"
					steps[#steps + 1] = string.format("Turn in %dx %s for %d Favor and +%s cashback.",
						feederCount, name, earnedFavor, ns.FormatMoneyCompact(favorRefund))
				end
			end
		end
	end

	local receipt = ns.FORGED_RECEIPT or {}
	local receiptName = receipt.receiptName or "Forged Delivery Receipt"
	local containerName = receipt.containerName or "Notarized Shipping Container"
	local repState = opts.repState or ns.GetMerchantReputation()
	steps[#steps + 1] = string.format("Buy %dx %s (%d) for %d Favor.", count, receiptName, receipt.receiptItemID or 262902, receiptFavor)
	steps[#steps + 1] = string.format("Apply the receipts to %dx %s -> %dx %s (%d).",
		count, crateName, count, containerName, receipt.containerItemID or 262917)
	steps[#steps + 1] = string.format("Turn in %s (quest %d) at %s for +%d Rep and +%s cashback.",
		receipt.questName or "Crate Return", receipt.questID or 93862, forgedTurnInNPC(receipt, repState and repState.playerFaction),
		repEarned, ns.FormatMoneyCompact(forgedRefund))

	return demand, {
		receiptCount = count,
		crateID = crateID,
		crateName = crateName,
		forgedMode = mode,
		favorNeeded = favorNeeded,
		feederCrate = feeder,
		feederCount = feederCount,
		leftoverFavor = leftoverFavor,
		forgedRefund = forgedRefund,
		favorRefund = favorRefund,
		totalRefund = forgedRefund + favorRefund,
		repMult = repMult,
		repEarned = repEarned,
		turnInSteps = steps,
	}, emptyPrice, missingDemand
end

local function finishForgedPlan(plan, rows, gross, missing, emptyPrice)
	plan.shoppingList = rows
	plan.missingPriceCount = missing
	if missing > 0 or emptyPrice == nil or (plan.forgedMode ~= "banked" and plan.feederCount == 0) then return end
	local forgedQty = plan.receiptCount
	for _, r in ipairs(rows) do
		if not r.isSubRow and r.itemID == plan.crateID then
			forgedQty = math.max(0, forgedQty - ((r.rawQty or r.qty) - r.qty))
			break
		end
	end
	local forgedEmptyTotal = forgedQty * emptyPrice
	local feederNet = gross - forgedEmptyTotal - plan.favorRefund
	local amortizedFeederNet = plan.feederCount > 0 and (feederNet * plan.favorNeeded / (plan.favorNeeded + plan.leftoverFavor)) or 0
	plan.grossCost = gross
	plan.netCost = gross - plan.totalRefund
	plan.amortizedNetCost = forgedEmptyTotal - plan.forgedRefund + amortizedFeederNet
	if plan.repEarned > 0 then
		plan.costPerRep = plan.amortizedNetCost / plan.repEarned
		plan.netCostPerRep = plan.netCost / plan.repEarned
	end
end

local function buildForgedTurnInShoppingListImpl(forgedRow, turnInCount, opts)
	local demand, plan, emptyPrice, missingDemand = buildForgedDemandAndPlan(forgedRow, turnInCount, opts)
	if not plan then return nil end
	local rows, gross, missing = ns.BuildShoppingListRows(demand, opts)
	finishForgedPlan(plan, rows, gross, missing + missingDemand, emptyPrice)

	local buyByID = {}
	plan.buyItems, plan.craftSteps = {}, {}
	for _, r in ipairs(rows) do
		if r.qty > 0 then
			if r.makeMyself == true then
				plan.craftSteps[#plan.craftSteps + 1] = {
					itemID = r.itemID, name = r.name, qty = r.qty, role = r.role,
					profLabel = r.craftProfLabel, unitCraftCost = r.craftUnitPrice,
					totalCraftCost = r.craftTotalPrice, craftCanDo = r.craftCanDo,
				}
			else
				local buy = buyByID[r.itemID]
				if buy then
					buy.qty = buy.qty + r.qty
					buy.rawQty = buy.rawQty + r.rawQty
					buy.ownedUsed = buy.ownedUsed + r.ownedUsed
					buy.totalCost = buy.totalCost and r.lineCost and (buy.totalCost + r.lineCost)
					buy.unitPrice = buy.totalCost and (buy.totalCost / buy.qty)
					if buy.source ~= (r.ahSource or r.action) then buy.source = "Mixed" end
					if buy.ahSource ~= r.ahSource then buy.ahSource = nil end
					buy.isVendor = buy.isVendor and r.isVendor
				else
					buy = {
						itemID = r.itemID, name = r.name, qty = r.qty, rawQty = r.rawQty,
						ownedUsed = r.ownedUsed, role = r.role, unitPrice = r.ahUnitPrice, totalCost = r.lineCost,
						source = r.ahSource or r.action, isVendor = r.isVendor, ahSource = r.ahSource,
					}
					buyByID[r.itemID] = buy
					plan.buyItems[#plan.buyItems + 1] = buy
				end
			end
		end
	end
	return plan
end

function ns.BuildForgedTurnInShoppingList(forgedRow, turnInCount, opts)
	ns.BeginEval(opts and opts.priceBank)
	local ok, result = pcall(buildForgedTurnInShoppingListImpl, forgedRow, turnInCount, opts)
	ns.EndEval()
	if not ok then error(result, 0) end
	return result
end

local function sortedTurnInQueue(queue)
	local targets = {}
	if type(queue) ~= "table" then return targets end
	local arraySize = 0
	for _ in ipairs(queue) do arraySize = arraySize + 1 end
	for key, value in pairs(queue) do
		local entry = type(value) == "table" and value or {}
		local count = tonumber(entry.count or entry.qty or value)
		if count and count >= 1 then
			local index = type(value) == "table" and type(key) == "number" and key >= 1 and key <= arraySize and key or nil
			targets[#targets + 1] = { key = key, index = index, entry = entry, count = math.floor(count + 0.5) }
		end
	end
	table.sort(targets, function(a, b)
		local na, nb = tonumber(a.key), tonumber(b.key)
		if na and nb and na ~= nb then return na < nb end
		if (na ~= nil) ~= (nb ~= nil) then return na ~= nil end
		if tostring(a.key) ~= tostring(b.key) then return tostring(a.key) < tostring(b.key) end
		return type(a.key) < type(b.key)
	end)
	return targets
end

local function queuedCrateID(target)
	local entry = target.entry
	local key = tostring(entry.rowKey or target.key)
	return crateIDFromRow(entry.row) or crateIDFromRow(entry)
		or crateIDFromRow(key:match("^forged:(%d+)") or key:match("^crate_turnin:(%d+)") or key:match("^(%d+):") or target.key)
end

local function findTurnInRow(rows, crateID, rowKey)
	if type(rows) ~= "table" then return nil end
	if rowKey and type(rows[rowKey]) == "table" then return rows[rowKey] end
	local byID = rows[crateID] or rows[tostring(crateID)]
	local id = crateIDFromRow(byID)
	if crateID and type(byID) == "table" and (not id or id == crateID) then return byID end
	local crateMatch
	for _, row in ipairs(rows) do
		if type(row) == "table" then
			if rowKey and row.rowKey == rowKey then return row end
			if not crateMatch and crateID and crateIDFromRow(row) == crateID then crateMatch = row end
		end
	end
	return crateMatch
end

local function appendTurnInQueueGroups(groups, db, opts, planOpts)
	local forgedTargets, forgedByRef, pricedForged, seenForgedKeys = {}, {}, {}, {}
	local forgedQ = (type(db) == "table" and db.forgedTurnInQueue) or opts.forgedTurnInQueue
	for _, target in ipairs(sortedTurnInQueue(forgedQ)) do
		local entry, count = target.entry, target.count
		local crateID = queuedCrateID(target)
		local rowKey = entry.rowKey or (type(target.key) == "string" and target.key)
		local row = entry.row
			or findTurnInRow(opts.forgedRowsByID, crateID, rowKey)
			or findTurnInRow(opts.forgedRows, crateID, rowKey)
		local mode = entry.forgedMode or (type(row) == "table" and row.forgedMode) or opts.forgedMode or db.forgedMode or "self_funded"
		local human = entry.humanDiplomacy
		if human == nil then human = opts.humanDiplomacy end
		local fallbackFeeder = nil
		if not row and crateID and ns.BuildForgedDeliveryRows then
			local cacheKey = mode .. ":" .. tostring(human)
			if not pricedForged[cacheKey] then
				local result = ns.BuildForgedDeliveryRows({
					forgedMode = mode, humanDiplomacy = human, subCraftMode = planOpts.subCraftMode,
					subCraftOverrides = planOpts.subCraftOverrides, ownedCounts = planOpts.ownedCounts,
					profMap = planOpts.profMap, repState = planOpts.repState,
				})
				pricedForged[cacheKey] = result or {}
			end
			row = findTurnInRow(pricedForged[cacheKey].rows, crateID, rowKey)
			fallbackFeeder = pricedForged[cacheKey].bestFavorCrate
		end
		local entryOpts = {}
		for k, v in pairs(planOpts) do entryOpts[k] = v end
		entryOpts.forgedMode = mode
		entryOpts.humanDiplomacy = human
		entryOpts.repMult = entry.repMult or opts.repMult
		entryOpts.bestFavorCrate = entry.bestFavorCrate or opts.bestFavorCrate or fallbackFeeder
		if type(row) ~= "table" then row = { crateID = crateIDFromRow(row) or crateID } end
		local demand, plan, emptyPrice, missingDemand = buildForgedDemandAndPlan(row, count, entryOpts, crateID)
		if plan then
			local removeRef = {
				sourceKind = "forged_turnin", crateID = plan.crateID, rowKey = entry.rowKey or row.rowKey,
				queueKey = target.key, index = target.index,
			}
			local baseKey = "forged_turnin:" .. tostring(entry.rowKey or plan.crateID)
			local grpKey = baseKey
			if seenForgedKeys[grpKey] then
				seenForgedKeys[grpKey] = seenForgedKeys[grpKey] + 1
				grpKey = baseKey .. ":" .. tostring(target.index or target.key or seenForgedKeys[grpKey])
			else
				seenForgedKeys[grpKey] = 1
			end
			groups[#groups + 1] = {
				key = grpKey,
				mainName = (row.crateFullName or row.name or plan.crateName) .. " (Forged)",
				mainItemID = plan.crateID, qty = count,
				sourceKind = "forged_turnin", sourceLabel = mode == "banked" and "Forged (Banked)" or "Forged Delivery",
				removeRef = removeRef, demandList = demand, missingDemandCount = missingDemand,
			}
			local forged = { plan = plan, emptyPrice = emptyPrice, rows = {} }
			forgedTargets[#forgedTargets + 1] = forged
			forgedByRef[removeRef] = forged
		end
	end

	local crateSummary = { feederCount = 0, entries = {} }
	local crateQ = (type(db) == "table" and db.crateTurnInQueue) or opts.crateTurnInQueue
	local crateRows
	for _, target in ipairs(sortedTurnInQueue(crateQ)) do
		local entry, count = target.entry, target.count
		local crateID = queuedCrateID(target)
		local row = type(entry.row) == "table" and entry.row
			or ((entry.matDetails or entry.reagentID) and entry)
			or findTurnInRow(opts.crateRowsByID, crateID, entry.rowKey)
			or findTurnInRow(opts.crateRows, crateID, entry.rowKey)
		crateID = crateIDFromRow(row) or crateID
		if not row and crateID and ns.BuildCrateRows then
			if not crateRows then
				crateRows = ns.BuildCrateRows({
					bestOnly = true, crateMode = planOpts.crateMode,
					subCraftMode = planOpts.subCraftMode, subCraftOverrides = planOpts.subCraftOverrides,
					ownedCounts = planOpts.ownedCounts, profMap = planOpts.profMap, repState = planOpts.repState,
				}) or {}
			end
			row = findTurnInRow(crateRows, crateID, entry.rowKey)
		end
		if crateID then
			row = row or findTurnInRow(ns.CRATES, crateID) or {}
			local demand = {}
			local missing = appendCrateTurnInDemand(demand, row, count, crateID)
			local name = row.crateFullName or row.name or row.crateName or ns.ItemName(crateID)
			local removeRef = {
				sourceKind = "crate_turnin", crateID = crateID, rowKey = entry.rowKey or row.rowKey,
				queueKey = target.key, index = target.index,
			}
			groups[#groups + 1] = {
				key = "crate_turnin:" .. tostring(entry.rowKey or target.key),
				mainName = name, mainItemID = crateID, qty = count, sourceKind = "crate_turnin", sourceLabel = "Crate Turn-In",
				removeRef = removeRef, demandList = demand, missingDemandCount = missing,
			}
			crateSummary.feederCount = crateSummary.feederCount + count
			crateSummary.entries[#crateSummary.entries + 1] = { row = row, crateID = crateID, count = count, removeRef = removeRef }
		end
	end
	return forgedTargets, forgedByRef, crateSummary
end

local function buildUnifiedShoppingListImpl(db, opts)
	opts = opts or {}
	db = (type(db) == "table" and db) or MerchantMasterDB or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()
	local subMode = opts.subCraftMode or db.subCraftMode or "smart"
	local overrides = opts.subCraftOverrides or db.subCraftOverrides
	local ownedCounts = opts.ownedCounts
		or (ns.GetOwnedItemCounts and ns.GetOwnedItemCounts())
		or (_G.MerchantMaster and _G.MerchantMaster.GetOwnedCounts and _G.MerchantMaster.GetOwnedCounts())
		or {}
	local deductOwned = opts.deductOwned
	if deductOwned == nil then
		deductOwned = (db.deductOwnedMats == true)
	end

	local groups = {}

	-- 1. Crafting Orders (ordered queue)
	local craftEntries = {}
	for i, q in ipairs(db.craftOrderQueue or {}) do
		local qQty = math.floor((tonumber(q and q.qty) or 0) + 0.5)
		if qQty > 0 then
			local qRec = ns.ResolveCraftingOrderRecipe(q, profMap, false)
			if qRec then
				local qMade = math.max(1, tonumber(qRec.numMade) or 1)
				local qBatches = math.ceil(qQty / qMade)
				local qOut = qBatches * qMade
				local qReused = tonumber(q.reusedQty) or 0
				craftEntries[#craftEntries + 1] = {
					recipe = qRec,
					queueIndex = i,
					idx = qRec.idx,
					spellID = qRec.spellID,
					outputItemID = qRec.outputItemID,
					prof = qRec.prof,
					name = ns.GetRecipeDisplayName(qRec),
					reqQty = qQty,
					batches = qBatches,
					actualOutput = qOut,
					reagentOverride = (type(q.reagentOverride) == "table" and #q.reagentOverride > 0) and q.reagentOverride or nil,
					reusedQty = (qReused > 0) and math.min(qOut, math.floor(qReused + 0.5)) or nil,
					buyCaps = (type(q.buyCaps) == "table") and q.buyCaps or nil,
				}
			end
		end
	end
	for _, g in ipairs(ns.BuildCraftOrderGroups(craftEntries)) do
		groups[#groups + 1] = g
	end

	-- 2. Writ Craft Queue (map: requiredItemID -> qty)
	local writCraftKeys = sortedPositiveQueueKeys(db.writCraftQueue)
	if #writCraftKeys > 0 then
		local writByReqID = {}
		for _, w in ipairs(ns.WRITS or {}) do
			if w.requiredItemID and not writByReqID[w.requiredItemID] then
				writByReqID[w.requiredItemID] = w
			end
		end
		for _, k in ipairs(writCraftKeys) do
			local reqQty = math.floor((tonumber(db.writCraftQueue[k]) or 0) + 0.5)
			local rowHit = opts.writProfitRowsByItemID and opts.writProfitRowsByItemID[k] or nil
			local writ = rowHit and rowHit.writ or writByReqID[k]
			local reagents, numMade, prof, mainName
			if rowHit and rowHit.craftBreakdown and #rowHit.craftBreakdown > 0 then
				reagents = rowHit.craftBreakdown
				numMade = rowHit.numMade or 1
				prof = rowHit.prof
				mainName = rowHit.name
			elseif writ then
				reagents = writ.reagents
				numMade = writ.numMade or 1
				prof = writ.prof
				mainName = ns.ItemName(k, writ.name)
			else
				local rec = ns.SelectBestRecipeForItem and ns.SelectBestRecipeForItem(tonumber(k), nil, profMap) or nil
				if rec then
					reagents = ns.ResolveRecipeReagents(rec)
					numMade = rec.numMade or 1
					prof = rec.prof
					mainName = ns.ItemName(k, rec.name)
				end
			end
			local made = math.max(1, tonumber(numMade) or 1)
			local batches = math.ceil(reqQty / made)
			local demand = resolveDemandFromReagents(reagents, batches, prof)
			groups[#groups + 1] = {
				key = "writ_craft:" .. tostring(k),
				mainName = mainName or (tonumber(k) and ns.ItemName(tonumber(k))) or ("Writ Craft #" .. tostring(k)),
				mainItemID = tonumber(k),
				prof = prof,
				qty = (#demand > 0) and (batches * made) or reqQty,
				batches = batches,
				sourceKind = "writ_craft",
				sourceLabel = "Writ Craft",
				removeRef = { sourceKind = "writ_craft", itemID = k },
				demandList = demand,
			}
		end
	end

	-- 3. Spread Queue (map: itemID -> qty)
	local spreadKeys = sortedPositiveQueueKeys(db.spreadQueue)
	if #spreadKeys > 0 then
		for _, k in ipairs(spreadKeys) do
			local reqQty = math.floor((tonumber(db.spreadQueue[k]) or 0) + 0.5)
			local rowHit = opts.spreadRowsByID and opts.spreadRowsByID[k] or nil
			local reagents, numMade, prof, mainName, mainItemID
			if rowHit and rowHit.craftBreakdown and #rowHit.craftBreakdown > 0 then
				reagents = rowHit.craftBreakdown
				numMade = rowHit.numMade or 1
				prof = rowHit.prof
				mainName = rowHit.name
				mainItemID = rowHit.itemID
			else
				local rec = ns.ResolveSpreadQueueRecipe(k, profMap)
				if rec then
					reagents = ns.ResolveRecipeReagents(rec)
					numMade = rec.numMade or 1
					prof = rec.prof
					mainName = ns.GetRecipeDisplayName(rec)
					mainItemID = rec.outputItemID
				end
			end
			local made = math.max(1, tonumber(numMade) or 1)
			local batches = math.ceil(reqQty / made)
			local demand = resolveDemandFromReagents(reagents, batches, prof)
			groups[#groups + 1] = {
				key = "spread:" .. tostring(k),
				mainName = mainName or (tonumber(k) and ns.ItemName(tonumber(k))) or ("Spread #" .. tostring(k)),
				mainItemID = mainItemID or tonumber(k),
				prof = prof,
				qty = (#demand > 0) and (batches * made) or reqQty,
				batches = batches,
				sourceKind = "spread",
				sourceLabel = "Spread",
				removeRef = { sourceKind = "spread", itemID = mainItemID or tonumber(k), queueKey = k },
				demandList = demand,
			}
		end
	end

	-- 4. Writ Turn-In Queue (map: writID -> count)
	local turnInKeys = sortedPositiveQueueKeys(db.writTurnInQueue)
	if #turnInKeys > 0 then
		local writRowByID = opts.writRowsByID
		if not writRowByID then
			writRowByID = {}
			local allWrits = opts.writRows or ns.BuildWritRows({
				writMode = db.writMode or "cheapest",
				includeWritPouch = db.includeWritPouch,
				writTurnInQueue = db.writTurnInQueue,
				subCraftMode = subMode,
				subCraftOverrides = overrides,
				ownedCounts = ownedCounts,
				profMap = profMap,
				repState = repState,
			})
			for _, wr in ipairs(allWrits or {}) do
				if wr.writID and not writRowByID[wr.writID] then
					writRowByID[wr.writID] = wr
				end
			end
		end
		for _, wid in ipairs(turnInKeys) do
			local cnt = math.floor((tonumber(db.writTurnInQueue[wid]) or 0) + 0.5)
			local r = writRowByID[wid]
			local demand = {}
			if r then
				demand[#demand + 1] = { itemID = r.writID or wid, qty = cnt, role = "Writ" }
				local reqQtyTotal = cnt * math.max(1, tonumber(r.reqQty) or (r.writ and r.writ.qty) or 1)
				if r.mode == "Craft" and r.craftBreakdown and #r.craftBreakdown > 0 then
					local numMade = math.max(1, (r.writ and r.writ.numMade) or 1)
					local batches = math.ceil(reqQtyTotal / numMade)
					for _, rg in ipairs(r.craftBreakdown) do
						demand[#demand + 1] = {
							itemID = rg.itemID,
							qty = rg.qty * batches,
							role = "Reagent",
							parentProf = r.prof,
						}
					end
				elseif r.reqItemID then
					demand[#demand + 1] = {
						itemID = r.reqItemID,
						qty = reqQtyTotal,
						role = "Turn-In",
						parentProf = r.prof,
					}
				end
			elseif tonumber(wid) then
				demand[#demand + 1] = { itemID = tonumber(wid), qty = cnt, role = "Writ" }
			end
			groups[#groups + 1] = {
				key = "writ_turnin:" .. tostring(wid),
				mainName = (r and r.writName) or (tonumber(wid) and ns.ItemName(tonumber(wid))) or ("Writ #" .. tostring(wid)),
				mainItemID = tonumber(wid),
				prof = r and r.prof or nil,
				qty = cnt,
				sourceKind = "writ_turnin",
				sourceLabel = "Writ Turn-In",
				removeRef = { sourceKind = "writ_turnin", writID = wid },
				demandList = demand,
			}
		end
	end

	-- 5. Unified Manual / Plan / Crate Entries (db.shoppingList)
	for idx, entry in ipairs(db.shoppingList or {}) do
		local eqty = math.max(1, math.floor((tonumber(entry and entry.qty) or 1) + 0.5))
		local demand
		if type(entry.demandList) == "table" and #entry.demandList > 0 then
			demand = {}
			for _, d in ipairs(entry.demandList) do
				demand[#demand + 1] = d
			end
		elseif type(entry.reagents) == "table" and #entry.reagents > 0 then
			local batches = math.max(1, tonumber(entry.batches) or math.ceil(eqty / math.max(1, tonumber(entry.numMade) or 1)))
			demand = resolveDemandFromReagents(entry.reagents, batches, entry.prof)
		elseif entry.spellID or (entry.asCraft and entry.itemID) then
			local rec = ns.ResolveCraftingOrderRecipe({
				spellID = entry.spellID,
				outputItemID = entry.itemID,
				prof = entry.prof,
			}, profMap, false)
			if rec then
				local made = math.max(1, tonumber(rec.numMade) or 1)
				local batches = math.ceil(eqty / made)
				demand = resolveDemandFromReagents(ns.ResolveRecipeReagents(rec), batches, rec.prof or entry.prof)
			end
		end
		if (not demand or #demand == 0) and entry.itemID then
			demand = {
				{
					itemID = entry.itemID,
					qty = eqty,
					role = entry.sourceLabel or "Shopping",
					parentProf = entry.prof,
				},
			}
		end
		if demand and #demand > 0 then
			local key = entry.key or ("shop:" .. tostring(idx) .. ":" .. tostring(entry.itemID or entry.spellID or idx))
			groups[#groups + 1] = {
				key = key,
				mainName = entry.name or (entry.itemID and ns.ItemName(entry.itemID)) or "Shopping Item",
				mainItemID = entry.itemID,
				spellID = entry.spellID,
				prof = entry.prof,
				qty = eqty,
				batches = entry.batches,
				isBundle = (entry.isBundle == true),
				sourceKind = "shopping",
				sourceLabel = entry.sourceLabel or "Shopping",
				removeRef = { sourceKind = "shopping", index = idx, key = entry.key },
				demandList = demand,
			}
		end
	end

	local shopOpts = {
		profMap = profMap,
		repState = repState,
		subCraftMode = subMode,
		subCraftOverrides = overrides,
		ownedCounts = ownedCounts,
		crateMode = opts.crateMode or db.crateMode or "cheapest",
		deductOwned = deductOwned,
		spentPool = opts.spentPool,
	}
	local forgedTargets, forgedByRef, crateSummary = appendTurnInQueueGroups(groups, db, opts, shopOpts)
	local outRows, grandTotalCost, grandMissing, meta = ns.BuildHierarchicalShoppingList(groups, shopOpts)

	meta.buyList, meta.craftQueue = {}, {}
	local active
	for _, row in ipairs(outRows) do
		if row.isMainRow then
			active = forgedByRef[row.removeRef]
			if active then active.gross, active.missing = row.groupTotalCost, row.groupMissingCount end
		else
			if active then active.rows[#active.rows + 1] = row end
			if (row.qty or 0) > 0 then
				local list = row.makeMyself == true and meta.craftQueue or meta.buyList
				list[#list + 1] = row
			end
		end
	end

	local forgedSummary = {
		count = 0, totalRep = 0, forgedRefund = 0, favorRefund = 0, totalRefund = 0,
		grossCost = 0, netCost = 0, leftoverFavor = 0, plans = {},
	}
	for _, target in ipairs(forgedTargets) do
		local plan = target.plan
		finishForgedPlan(plan, target.rows, target.gross, target.missing, target.emptyPrice)
		forgedSummary.plans[#forgedSummary.plans + 1] = plan
		forgedSummary.count = forgedSummary.count + plan.receiptCount
		forgedSummary.totalRep = forgedSummary.totalRep + plan.repEarned
		forgedSummary.forgedRefund = forgedSummary.forgedRefund + plan.forgedRefund
		forgedSummary.favorRefund = forgedSummary.favorRefund + plan.favorRefund
		forgedSummary.totalRefund = forgedSummary.totalRefund + plan.totalRefund
		forgedSummary.grossCost = forgedSummary.grossCost and plan.grossCost and (forgedSummary.grossCost + plan.grossCost)
		forgedSummary.netCost = forgedSummary.netCost and plan.netCost and (forgedSummary.netCost + plan.netCost)
		forgedSummary.leftoverFavor = forgedSummary.leftoverFavor + plan.leftoverFavor
	end
	meta.forgedTurnInQueue = forgedSummary
	meta.crateTurnInQueue = crateSummary
	return outRows, grandTotalCost, grandMissing, meta
end

function ns.BuildUnifiedShoppingList(db, opts)
	ns.BeginEval(opts and opts.priceBank)
	local ok, r1, r2, r3, r4 = pcall(buildUnifiedShoppingListImpl, db, opts)
	ns.EndEval()
	if not ok then error(r1, 0) end
	return r1, r2, r3, r4
end

local function buildCraftingOrderPlanImpl(activeRef, targetQty, orderQueue, opts)
	opts = opts or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()
	local counts = opts.ownedCounts or {}
	local subMode = opts.subCraftMode or "smart"
	local overrides = opts.subCraftOverrides
	local deductOwned = (opts.deductOwned == true)
	local applyAHCut = (opts.applyAHCut ~= false)

	local queueDemand = {}
	local queueEntries = {}
	if type(orderQueue) == "table" then
		for _, q in ipairs(orderQueue) do
			local qQty = math.floor((tonumber(q and q.qty) or 0) + 0.5)
			if qQty > 0 then
				local qRec = ns.ResolveCraftingOrderRecipe(q, profMap, false)
				if qRec then
					local qMade = math.max(1, tonumber(qRec.numMade) or 1)
					local qBatches = math.ceil(qQty / qMade)
					local qOut = qBatches * qMade
					local qReagents = (type(q.reagentOverride) == "table" and #q.reagentOverride > 0) and q.reagentOverride or (ns.ResolveRecipeReagents(qRec) or {})
					for _, pair in ipairs(qReagents) do
						if pair[1] and pair[2] and pair[2] > 0 then
							queueDemand[#queueDemand + 1] = {
								itemID = pair[1],
								qty = pair[2] * qBatches,
								role = "Reagent",
								parentProf = qRec.prof,
							}
						end
					end
					local qReused = tonumber(q.reusedQty) or 0
					queueEntries[#queueEntries + 1] = {
						recipe = qRec,
						idx = qRec.idx,
						spellID = qRec.spellID,
						outputItemID = qRec.outputItemID,
						prof = qRec.prof,
						name = ns.GetRecipeDisplayName(qRec),
						reqQty = qQty,
						batches = qBatches,
						actualOutput = qOut,
						reagentOverride = (type(q.reagentOverride) == "table" and #q.reagentOverride > 0) and q.reagentOverride or nil,
						reusedQty = (qReused > 0) and math.min(qOut, math.floor(qReused + 0.5)) or nil,
					}
				end
			end
		end
	end

	local queueGroups = ns.BuildCraftOrderGroups(queueEntries)
	local queueRows, queueCost, queueMissing = {}, 0, 0
	if #queueGroups > 0 then
		queueRows, queueCost, queueMissing = ns.BuildHierarchicalShoppingList(queueGroups, {
			profMap = profMap,
			repState = repState,
			subCraftMode = subMode,
			subCraftOverrides = overrides,
			ownedCounts = counts,
			deductOwned = deductOwned,
		})
	end

	local completeQueueCost = 0
	if #queueEntries > 0 then
		if queueMissing == 0 then
			completeQueueCost = queueCost
		else
			completeQueueCost = nil
		end
	end

	local recipe
	if activeRef ~= nil then
		recipe = ns.ResolveCraftingOrderRecipe(activeRef, profMap, false)
	else
		recipe = ns.ResolveCraftingOrderRecipe(nil, profMap, true)
	end
	if not recipe then
		if #queueEntries > 0 then
			return {
				recipe = nil,
				row = nil,
				queueEntries = queueEntries,
				queueRows = queueRows,
				queueCost = completeQueueCost,
				rawQueueCost = queueCost,
				queueMissing = queueMissing,
			}
		end
		return nil
	end

	local row = ns.BuildRecipeRow(recipe, {
		profMap = profMap,
		repState = repState,
		ownedCounts = counts,
		applyAHCut = applyAHCut,
		subCraftMode = subMode,
		subCraftOverrides = overrides,
		outlierPrices = opts.outlierPrices,
		priceBank = opts.priceBank,
	})

	local numMade = math.max(1, tonumber(recipe.numMade) or tonumber(row.numMade) or 1)
	local reqQty = math.max(1, math.floor((tonumber(targetQty) or numMade) + 0.5))
	local batches = math.ceil(reqQty / numMade)
	local actualOutput = batches * numMade

	local reagents = ns.ResolveRecipeReagents(recipe) or {}
	local demand = {}
	for _, pair in ipairs(reagents) do
		if pair[1] and pair[2] and pair[2] > 0 then
			demand[#demand + 1] = {
				itemID = pair[1],
				qty = pair[2] * batches,
				role = "Reagent",
				parentProf = recipe.prof,
			}
		end
	end

	local orderRows, orderCost, missingCount = ns.BuildShoppingListRows(demand, {
		profMap = profMap,
		repState = repState,
		subCraftMode = subMode,
		subCraftOverrides = overrides,
		ownedCounts = counts,
		deductOwned = deductOwned,
	})
	local _, buyAllCost, buyMissing = ns.BuildShoppingListRows(demand, {
		profMap = profMap,
		repState = repState,
		subCraftMode = "buy_only",
		subCraftOverrides = nil,
		ownedCounts = counts,
		deductOwned = deductOwned,
	})
	local _, bestAllSubCost, bestAllMissing = ns.BuildShoppingListRows(demand, {
		profMap = profMap,
		repState = repState,
		subCraftMode = "all_sub",
		subCraftOverrides = nil,
		ownedCounts = counts,
		deductOwned = deductOwned,
	})
	local _, smartMyProfCost, smartMissing = ns.BuildShoppingListRows(demand, {
		profMap = profMap,
		repState = repState,
		subCraftMode = "smart",
		subCraftOverrides = nil,
		ownedCounts = counts,
		deductOwned = deductOwned,
	})

	local craftableMatCount, selfCraftCount, canDoSelfCount, needProfSelfCount = 0, 0, 0, 0
	local seenCraftable, seenSelf = {}, {}
	for _, r in ipairs(orderRows) do
		local rKey = r.itemID or r.name
		if rKey and (r.craftUnitPrice ~= nil or r.craftProfLabel ~= nil) and not seenCraftable[rKey] then
			seenCraftable[rKey] = true
			craftableMatCount = craftableMatCount + 1
		end
		if r.makeMyself and rKey and not seenSelf[rKey] then
			seenSelf[rKey] = true
			selfCraftCount = selfCraftCount + 1
			if r.craftCanDo then
				canDoSelfCount = canDoSelfCount + 1
			else
				needProfSelfCount = needProfSelfCount + 1
			end
		end
	end

	local unitGross = row.ahValue or row.unitAH
	local grossSale = (row.sellable and unitGross) and (unitGross * actualOutput) or nil
	local netSale = grossSale and ((applyAHCut and not row.usedVendorFloor) and math.floor(grossSale * 0.95 + 0.5) or grossSale) or nil
	local completeOrderCost = (missingCount == 0 and #demand > 0) and orderCost or (#demand == 0 and 0 or nil)
	local completeBuyAllCost = (buyMissing == 0 and #demand > 0) and buyAllCost or nil
	local completeBestSubCost = (bestAllMissing == 0 and #demand > 0) and bestAllSubCost or nil
	local completeSmartCost = (smartMissing == 0 and #demand > 0) and smartMyProfCost or nil
	local netProfit = (netSale ~= nil and completeOrderCost ~= nil) and (netSale - completeOrderCost) or nil
	local marginPct = (netProfit ~= nil and completeOrderCost and completeOrderCost > 0) and ((netProfit / completeOrderCost) * 100) or nil
	local dailySold = row.dailySold
	if type(opts.salesPerDay) == "number" then
		dailySold = opts.salesPerDay
	elseif opts.statsContext and ns.RecipeStats and ns.RecipeStats.Get then
		local okStat, statRow = pcall(ns.RecipeStats.Get, recipe, opts.statsContext)
		if okStat and type(statRow) == "table" and type(statRow.salesPerDay) == "number" then
			dailySold = statRow.salesPerDay
		end
	end

	return {
		recipe = recipe,
		row = row,
		reqQty = reqQty,
		numMade = numMade,
		batches = batches,
		actualOutput = actualOutput,
		orderRows = orderRows,
		orderCost = completeOrderCost,
		rawOrderCost = orderCost,
		missingCount = missingCount,
		buyAllCost = completeBuyAllCost,
		bestAllSubCost = completeBestSubCost,
		smartMyProfCost = completeSmartCost,
		savingsVsBuyAll = (completeBuyAllCost and completeOrderCost) and (completeBuyAllCost - completeOrderCost) or nil,
		craftableMatCount = craftableMatCount,
		selfCraftCount = selfCraftCount,
		canDoSelfCount = canDoSelfCount,
		needProfSelfCount = needProfSelfCount,
		grossSale = grossSale,
		netSale = netSale,
		netProfit = netProfit,
		marginPct = marginPct,
		dailySold = dailySold,
		queueEntries = queueEntries,
		queueRows = queueRows,
		rawQueueCost = queueCost,
		queueCost = completeQueueCost,
		queueMissing = queueMissing,
	}
end

function ns.BuildCraftingOrderPlan(activeRef, targetQty, orderQueue, opts)
	ns.BeginEval(opts and opts.priceBank)
	local ok, res = pcall(buildCraftingOrderPlanImpl, activeRef, targetQty, orderQueue, opts)
	ns.EndEval()
	if not ok then error(res, 0) end
	return res
end

---------------------------------------------------------------------------------------------------
-- 4. AH Order-Book Supply Pool (Multi-Price Lots + Stock Caps + Vendor + Owned)
---------------------------------------------------------------------------------------------------

function ns.GetSavedItemLots(itemID, econKey)
	local db = ns.GetDB()
	if not (db and db.ahLots) then return nil end
	econKey = econKey or ns.CurrentEconomyInfo().effectiveKey
	local econLots = db.ahLots[econKey]
	local rec = econLots and econLots[itemID]
	if not rec or not rec.lots then return nil end
	if rec.at and (time() - rec.at) > LIVE_LOT_FRESH_SECONDS then
		return nil
	end
	return rec.lots, rec.at
end

function ns.BuildSupplyPool(opts)
	opts = opts or {}
	local respectStock = (opts.respectStock ~= false)
	local useOwned = opts.useOwned and true or false
	local ownedCounts = opts.ownedCounts or {}
	local econ = ns.CurrentEconomyInfo()

	local pool = {
		items = {},
		spent = {},
		respectStock = respectStock,
	}

	function pool:getLots(itemID)
		local existing = self.items[itemID]
		if existing then return existing end

		local lots = {}
		local name = ns.ItemName(itemID)
		if useOwned then
			local own = ownedCounts[name] or 0
			if own > 0 then
				lots[#lots + 1] = { price = 0, qty = own, initialQty = own, source = "Owned" }
			end
		end

		local unitCost, _, isVendor = ns.GetReagentUnitCost(itemID)
		if isVendor and unitCost then
			lots[#lots + 1] = { price = unitCost, qty = math.huge, initialQty = math.huge, source = "Vendor", isVendor = true }
			self.items[itemID] = lots
			return lots
		end

		-- 1. Check exact multi-price Live AH order-book ladder vs Local Snapshot depth (respecting priceSource)
		if respectStock then
			local priceMode = (ns.GetEffectivePriceSource and ns.GetEffectivePriceSource()) or "auto"
			local savedLots, lotAt
			if priceMode ~= "snapshot" then
				savedLots, lotAt = ns.GetSavedItemLots(itemID, econ.effectiveKey)
			end
			local hasSaved = type(savedLots) == "table" and #savedLots > 0
			local snapDepth = (priceMode ~= "live_ah" and ns.Pricing and type(ns.Pricing.GetItemSnapshotDepth) == "function")
				and ns.Pricing.GetItemSnapshotDepth(itemID, econ.effectiveKey) or nil
			local hasSnap = type(snapDepth) == "table" and #snapDepth > 0

			local snapMeta = (type(ns.Pricing) == "table" and type(ns.Pricing.GetSnapshotMeta) == "function")
				and ns.Pricing.GetSnapshotMeta(econ.effectiveKey) or nil
			local snapAt = (snapMeta and type(snapMeta.updatedAt) == "number" and snapMeta.updatedAt > 0)
				and snapMeta.updatedAt or 0
			local liveLotAt = (type(lotAt) == "number" and lotAt > 0) and lotAt or 0
			local can = (type(ns.GetCanonicalItemPrice) == "function")
				and ns.GetCanonicalItemPrice(itemID, econ.effectiveKey) or nil
			local canKind = can and can.kind or nil
			local canTs = (can and type(can.timestamp) == "number" and can.timestamp > 0) and can.timestamp or 0

			if canKind == "absent" and canTs >= liveLotAt then
				self.items[itemID] = lots
				return lots
			end

			local spotOverridesLots = (canKind == "live" or canKind == "tsm")
				and canTs > liveLotAt and canTs > snapAt

			if not spotOverridesLots then
				local preferSnapDepth = hasSnap and (
					(not hasSaved)
					or (snapAt > liveLotAt)
					or (canKind == "snap" and canTs > liveLotAt)
				)

				local function appendLots(srcList, srcTag)
					local added = 0
					for _, entry in ipairs(srcList) do
						if entry.price and entry.price > 0 and entry.qty and entry.qty > 0 then
							lots[#lots + 1] = { price = entry.price, qty = entry.qty, initialQty = entry.qty, source = srcTag }
							added = added + 1
						end
					end
					return added
				end

				if preferSnapDepth then
					if appendLots(snapDepth, "Snapshot Depth") > 0 then
						self.items[itemID] = lots
						return lots
					end
					if hasSaved and appendLots(savedLots, "AH Lot") > 0 then
						self.items[itemID] = lots
						return lots
					end
				elseif hasSaved then
					if appendLots(savedLots, "AH Lot") > 0 then
						self.items[itemID] = lots
						return lots
					end
					if hasSnap and appendLots(snapDepth, "Snapshot Depth") > 0 then
						self.items[itemID] = lots
						return lots
					end
				end
			end
		end

		-- 2. Standard Snapshot / Live AH price + stock quantity
		local mktPrice, mktSrc = ns.GetItemMarketPrice(itemID)
		if mktPrice and mktPrice > 0 then
			local listed = respectStock and ns.GetNumListed(itemID) or nil
			if not respectStock or listed == nil then
				lots[#lots + 1] = { price = mktPrice, qty = math.huge, initialQty = math.huge, source = mktSrc or "AH" }
			elseif listed > 0 then
				lots[#lots + 1] = { price = mktPrice, qty = listed, initialQty = listed, source = mktSrc or "AH" }
			end
		end

		self.items[itemID] = lots
		return lots
	end

	-- Fast-path peek for 1 unit of a single item (avoids table allocation + pairs)
	function pool:peekOne(itemID)
		local lots = self.items[itemID] or self:getLots(itemID)
		for i = 1, #lots do
			local lot = lots[i]
			local q = lot.qty
			if q > 0 then
				if q >= 1 then
					return lot.price
				end
				local total = q * lot.price
				local rem = 1 - q
				for j = i + 1, #lots do
					local l2 = lots[j]
					local q2 = l2.qty
					if q2 > 0 then
						local take = (rem < q2) and rem or q2
						total = total + (take * l2.price)
						rem = rem - take
						if rem <= 0 then return total end
					end
				end
				return nil
			end
		end
		return nil
	end

	-- Fast-path consume for 1 unit of a single item (avoids table allocation + pairs)
	function pool:consumeOne(itemID)
		local lots = self.items[itemID] or self:getLots(itemID)
		local rem = 1
		local stepTotal = 0
		local rec = self.spent[itemID]
		if not rec then
			rec = { qty = 0, copper = 0, firstPrice = nil, maxPrice = nil, hitPriceJump = false }
			self.spent[itemID] = rec
		end
		for i = 1, #lots do
			local lot = lots[i]
			local q = lot.qty
			if q > 0 then
				local take = (rem < q) and rem or q
				local p = lot.price
				local cost = take * p
				lot.qty = q - take
				rem = rem - take
				stepTotal = stepTotal + cost
				rec.qty = rec.qty + take
				rec.copper = rec.copper + cost
				if p > 0 then
					if not rec.firstPrice then rec.firstPrice = p end
					if not rec.maxPrice or p > rec.maxPrice then rec.maxPrice = p end
					if rec.maxPrice > rec.firstPrice then rec.hitPriceJump = true end
				end
				if rem <= 0 then break end
			end
		end
		return stepTotal
	end

	-- Peeks total copper to acquire `{ [itemID] = neededQty }`; returns nil if any item lacks stock
	function pool:peek(needMap)
		local total = 0
		local items = self.items
		for itemID, needQty in pairs(needMap) do
			if needQty > 0 then
				local lots = items[itemID] or self:getLots(itemID)
				local rem = needQty
				for i = 1, #lots do
					local lot = lots[i]
					local q = lot.qty
					if q > 0 then
						local take = (rem < q) and rem or q
						total = total + (take * lot.price)
						rem = rem - take
						if rem <= 0 then break end
					end
				end
				if rem > 0 then
					return nil
				end
			end
		end
		return total
	end

	-- Consumes `{ [itemID] = neededQty }` from the pool and tracks exact per-item spend & price jumps
	function pool:consume(needMap)
		local stepTotal = 0
		local items = self.items
		local spent = self.spent
		for itemID, needQty in pairs(needMap) do
			if needQty > 0 then
				local lots = items[itemID] or self:getLots(itemID)
				local rem = needQty
				local rec = spent[itemID]
				if not rec then
					rec = { qty = 0, copper = 0, firstPrice = nil, maxPrice = nil, hitPriceJump = false }
					spent[itemID] = rec
				end
				for i = 1, #lots do
					local lot = lots[i]
					local q = lot.qty
					if q > 0 then
						local take = (rem < q) and rem or q
						local p = lot.price
						local cost = take * p
						lot.qty = q - take
						rem = rem - take
						stepTotal = stepTotal + cost
						rec.qty = rec.qty + take
						rec.copper = rec.copper + cost
						if p > 0 then
							if not rec.firstPrice then rec.firstPrice = p end
							if not rec.maxPrice or p > rec.maxPrice then rec.maxPrice = p end
							if rec.maxPrice > rec.firstPrice then rec.hitPriceJump = true end
						end
						if rem <= 0 then break end
					end
				end
			end
		end
		return stepTotal
	end

	return pool
end

---------------------------------------------------------------------------------------------------
-- 5. Calculator 1: Merchant's Favor Token Calculator & Stock-Switching Shopping List
---------------------------------------------------------------------------------------------------

local function getFavorCandidates(opts, profMap, repState)
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.unlockFilter or "all"
	local crateMode = opts.crateMode or "cheapest" -- "cheapest" | "craft" | "buy"
	local subMode = opts.subCraftMode or "smart"
	local overrides = opts.subCraftOverrides

	-- Build candidate (crate, bundle) list (evaluating both direct AH buy & sub-crafting craftable crate mats).
	-- Buying empty crates + materials on the AH requires NO profession, so allowBuy is never blocked by profFilter.
	local function buildFavorCandidates(pFilter, uFilter)
		local list = {}
		for _, crate in ipairs(ns.CRATES or {}) do
			local tokens, rewardCopper = ns.GetCrateReward(crate)
			if tokens and tokens > 0 then
				for _, bundle in ipairs(crate.bundles or {}) do
					local craftOpt = (crateMode ~= "buy" and (crateMode == "craft" or subMode ~= "buy_only")) and ns.GetItemCraftOption(bundle.itemID, {
						parentProf = bundle.prof,
						profMap = profMap,
						subCraftMode = subMode,
						subCraftOverrides = overrides,
					}) or nil
					local fakeRec = craftOpt and craftOpt.recipe or nil
					local unlock = ns.EvaluateUnlock(bundle.prof, bundle.skill, 0, 0, fakeRec, profMap, repState)
					local matchesFilter = ns.MatchesGlobalFilters(bundle.prof, unlock, pFilter, uFilter)
					local ov = overrides and overrides[bundle.itemID]
					local allowBuy = (crateMode ~= "craft") and (ov ~= "craft")
					local allowCraft = matchesFilter and (crateMode ~= "buy") and craftOpt ~= nil and craftOpt.unitCraftCost ~= nil and ov ~= "buy" and (
						crateMode == "craft"
						or ov == "craft"
						or subMode == "all_sub"
						or (subMode == "smart" and (craftOpt.sameProf or craftOpt.playerCanCraft))
					)
					if allowBuy or allowCraft then
						local craftNumMade, craftDefaultBatches, craftDefaultNeed, craftNeedByBatches
						if allowCraft and craftOpt and craftOpt.breakdown then
							craftNumMade = math.max(1, craftOpt.numMade or 1)
							craftDefaultBatches = (bundle.qty > 0) and math.ceil(bundle.qty / craftNumMade) or 0
							local zeroNeed = { [crate.itemID] = 1 }
							if craftDefaultBatches > 0 then
								craftDefaultNeed = { [crate.itemID] = 1 }
								ns.CollectLeafReagents(craftOpt.breakdown, craftDefaultBatches, craftDefaultNeed)
								craftNeedByBatches = { [0] = zeroNeed, [craftDefaultBatches] = craftDefaultNeed }
							else
								craftDefaultNeed = zeroNeed
								craftNeedByBatches = { [0] = zeroNeed }
							end
						end
						list[#list + 1] = {
							key = tostring(crate.itemID) .. ":" .. tostring(bundle.itemID),
							crate = crate,
							bundle = bundle,
							tokens = tokens,
							reward = rewardCopper or 0,
							allowBuy = allowBuy,
							allowCraft = allowCraft,
							craftOpt = craftOpt,
							craftNumMade = craftNumMade,
							craftDefaultBatches = craftDefaultBatches,
							craftDefaultNeed = craftDefaultNeed,
							craftNeedByBatches = craftNeedByBatches,
							needMap = {
								[crate.itemID] = 1,
								[bundle.itemID] = bundle.qty,
							},
						}
					end
				end
			end
		end
		return list
	end

	local profFallbackFrom = nil
	local candidates = buildFavorCandidates(profFilter, unlockFilter)
	if #candidates == 0 and (profFilter ~= "all" or unlockFilter ~= "all") then
		profFallbackFrom = profFilter
		candidates = buildFavorCandidates("all", "all")
	end

	-- Pre-build reverse itemID -> candidate watcher indices for incremental dirty invalidation
	local buyWatchers, craftWatchers, surplusWatchers = {}, {}, {}
	for i = 1, #candidates do
		local cand = candidates[i]
		if cand.allowBuy then
			for itemID in pairs(cand.needMap) do
				local w = buyWatchers[itemID]
				if not w then w = {}; buyWatchers[itemID] = w end
				w[#w + 1] = i
			end
		end
		if cand.craftDefaultNeed then
			for itemID in pairs(cand.craftDefaultNeed) do
				local w = craftWatchers[itemID]
				if not w then w = {}; craftWatchers[itemID] = w end
				w[#w + 1] = i
			end
			local bID = cand.bundle.itemID
			local sw = surplusWatchers[bID]
			if not sw then sw = {}; surplusWatchers[bID] = sw end
			sw[#sw + 1] = i
		end
	end
	candidates._buyWatchers = buyWatchers
	candidates._craftWatchers = craftWatchers
	candidates._surplusWatchers = surplusWatchers

	return candidates, profFallbackFrom
end

local function getCandCraftNeed(cand, batches)
	local byB = cand.craftNeedByBatches
	if byB then
		local cached = byB[batches]
		if cached then return cached end
		local cNeed = { [cand.crate.itemID] = 1 }
		if batches > 0 then
			ns.CollectLeafReagents(cand.craftOpt.breakdown, batches, cNeed)
		end
		byB[batches] = cNeed
		return cNeed
	end
	local cNeed = { [cand.crate.itemID] = 1 }
	if batches > 0 then
		ns.CollectLeafReagents(cand.craftOpt.breakdown, batches, cNeed)
	end
	return cNeed
end

local function createFavorStepCache(candidates)
	local buyWatchers = candidates._buyWatchers
	local craftWatchers = candidates._craftWatchers
	local surplusWatchers = candidates._surplusWatchers
	if not buyWatchers then
		buyWatchers, craftWatchers, surplusWatchers = {}, {}, {}
		for i = 1, #candidates do
			local cand = candidates[i]
			if cand.allowBuy and cand.needMap then
				for itemID in pairs(cand.needMap) do
					local w = buyWatchers[itemID]
					if not w then w = {}; buyWatchers[itemID] = w end
					w[#w + 1] = i
				end
			end
			if cand.allowCraft and cand.craftOpt and cand.craftOpt.breakdown then
				local defNeed = cand.craftDefaultNeed
				if not defNeed then
					local numMade = math.max(1, cand.craftOpt.numMade or 1)
					local defB = (cand.bundle.qty > 0) and math.ceil(cand.bundle.qty / numMade) or 0
					defNeed = getCandCraftNeed(cand, defB)
				end
				for itemID in pairs(defNeed) do
					local w = craftWatchers[itemID]
					if not w then w = {}; craftWatchers[itemID] = w end
					w[#w + 1] = i
				end
				local bID = cand.bundle.itemID
				local sw = surplusWatchers[bID]
				if not sw then sw = {}; surplusWatchers[bID] = sw end
				sw[#sw + 1] = i
			end
		end
	end
	local buyGross, craftGross = {}, {}
	return {
		buyGross = buyGross,
		craftGross = craftGross,
		craftBatches = {},
		craftNeed = {},
		invalidateNeedMap = function(_, needMap)
			for itemID, qty in pairs(needMap) do
				if qty > 0 then
					local bw = buyWatchers[itemID]
					if bw then
						for i = 1, #bw do
							local idx = bw[i]
							if buyGross[idx] then buyGross[idx] = nil end
						end
					end
					local cw = craftWatchers[itemID]
					if cw then
						for i = 1, #cw do
							local idx = cw[i]
							if craftGross[idx] then craftGross[idx] = nil end
						end
					end
				end
			end
		end,
		invalidateSurplus = function(_, bundleItemID)
			local sw = surplusWatchers[bundleItemID]
			if sw then
				for i = 1, #sw do
					craftGross[sw[i]] = nil
				end
			end
		end,
	}
end

local function pickFavorStep(pool, candidates, craftedSurplus, remTokens, stepCache)
	local bestCand, bestMode, bestNeedMap, bestBatches, bestNet, bestScore = nil, nil, nil, 0, nil, nil
	local buyGross = stepCache and stepCache.buyGross or nil
	local craftGross = stepCache and stepCache.craftGross or nil
	local craftBatches = stepCache and stepCache.craftBatches or nil
	local craftNeed = stepCache and stepCache.craftNeed or nil

	for i = 1, #candidates do
		local cand = candidates[i]
		if cand.allowBuy then
			local gross
			if buyGross then
				gross = buyGross[i]
				if gross == nil then
					gross = pool:peek(cand.needMap) or false
					buyGross[i] = gross
				end
			else
				gross = pool:peek(cand.needMap)
			end
			if gross then
				local net = gross - cand.reward
				local denom = (net > 0) and math.min(cand.tokens, remTokens) or cand.tokens
				local score = net / denom
				if bestScore == nil
					or score < (bestScore - 0.0001)
					or (math.abs(score - bestScore) <= 0.0001 and (net / cand.tokens) < (bestNet / bestCand.tokens)) then
					bestCand, bestMode, bestNeedMap, bestBatches, bestNet, bestScore = cand, "Buy", cand.needMap, 0, net, score
				end
			end
		end
		if cand.allowCraft and cand.craftOpt and cand.craftOpt.breakdown then
			local gross, batches, cNeed
			if craftGross then
				gross = craftGross[i]
				if gross == nil then
					local surplus = craftedSurplus[cand.bundle.itemID] or 0
					if surplus == 0 and cand.craftDefaultNeed then
						batches = cand.craftDefaultBatches
						cNeed = cand.craftDefaultNeed
					else
						local netMake = cand.bundle.qty - surplus
						local numMade = cand.craftNumMade or math.max(1, cand.craftOpt.numMade or 1)
						batches = (netMake > 0) and math.ceil(netMake / numMade) or 0
						cNeed = getCandCraftNeed(cand, batches)
					end
					gross = pool:peek(cNeed) or false
					craftGross[i] = gross
					craftBatches[i] = batches
					craftNeed[i] = cNeed
				elseif gross then
					batches = craftBatches[i]
					cNeed = craftNeed[i]
				end
			else
				local surplus = craftedSurplus[cand.bundle.itemID] or 0
				if surplus == 0 and cand.craftDefaultNeed then
					batches = cand.craftDefaultBatches
					cNeed = cand.craftDefaultNeed
				else
					local netMake = cand.bundle.qty - surplus
					local numMade = cand.craftNumMade or math.max(1, cand.craftOpt.numMade or 1)
					batches = (netMake > 0) and math.ceil(netMake / numMade) or 0
					cNeed = getCandCraftNeed(cand, batches)
				end
				gross = pool:peek(cNeed)
			end
			if gross then
				local net = gross - cand.reward
				local denom = (net > 0) and math.min(cand.tokens, remTokens) or cand.tokens
				local score = net / denom
				if bestScore == nil
					or score < (bestScore - 0.0001)
					or (math.abs(score - bestScore) <= 0.0001 and (net / cand.tokens) < (bestNet / bestCand.tokens)) then
					bestCand, bestMode, bestNeedMap, bestBatches, bestNet, bestScore = cand, "Craft", cNeed, batches, net, score
				end
			end
		end
	end
	return bestCand, bestMode, bestNeedMap, bestBatches, bestNet
end

local function solveFavorOnPool(pool, netTargetTokens, opts)
	local craftedSurplus = {}
	local tokensAccum = 0
	local cratesFilled = 0
	local grossSpend = 0
	local totalReward = 0
	local comboOrder = {}
	local comboMap = {}
	local switchEvents = 0
	local lastComboKey = nil
	local stepCache = createFavorStepCache(opts.candidates)

	local maxSteps = 5000
	while tokensAccum < netTargetTokens and cratesFilled < maxSteps do
		local bestCand, bestMode, bestNeedMap, bestBatches = pickFavorStep(pool, opts.candidates, craftedSurplus, netTargetTokens - tokensAccum, stepCache)
		if not bestCand then
			break -- All priced/in-stock crates or materials on AH exhausted!
		end

		local actualGross = pool:consume(bestNeedMap)
		stepCache:invalidateNeedMap(bestNeedMap)
		if bestMode == "Craft" and bestCand.craftOpt then
			local produced = bestBatches * (bestCand.craftNumMade or math.max(1, bestCand.craftOpt.numMade or 1))
			craftedSurplus[bestCand.bundle.itemID] = (craftedSurplus[bestCand.bundle.itemID] or 0) + produced - bestCand.bundle.qty
			stepCache:invalidateSurplus(bestCand.bundle.itemID)
		end
		local actualNet = actualGross - bestCand.reward
		tokensAccum = tokensAccum + bestCand.tokens
		cratesFilled = cratesFilled + 1
		grossSpend = grossSpend + actualGross
		totalReward = totalReward + bestCand.reward

		local cKey = bestCand.key .. ":" .. bestMode
		if lastComboKey and lastComboKey ~= cKey then
			switchEvents = switchEvents + 1
		end
		lastComboKey = cKey

		local entry = comboMap[cKey]
		if not entry then
			entry = {
				key = cKey,
				crateID = bestCand.crate.itemID,
				crateName = ns.ItemName(bestCand.crate.itemID, bestCand.crate.name):gsub("^Waylaid Crate:%s*", ""),
				crateFullName = ns.ItemName(bestCand.crate.itemID, bestCand.crate.name),
				crateQuality = bestCand.crate.quality,
				reagentID = bestCand.bundle.itemID,
				reagentName = ns.ItemName(bestCand.bundle.itemID, bestCand.bundle.name),
				reagentQtyPerCrate = bestCand.bundle.qty,
				prof = bestCand.bundle.prof,
				mode = bestMode,
				count = 0,
				tokensEach = bestCand.tokens,
				tokensTotal = 0,
				grossTotal = 0,
				rewardTotal = 0,
				netTotal = 0,
				dailySold = ns.GetDailySold(bestCand.bundle.itemID),
			}
			comboMap[cKey] = entry
			comboOrder[#comboOrder + 1] = entry
		end
		entry.count = entry.count + 1
		entry.tokensTotal = entry.tokensTotal + bestCand.tokens
		entry.grossTotal = entry.grossTotal + actualGross
		entry.rewardTotal = entry.rewardTotal + bestCand.reward
		entry.netTotal = entry.netTotal + actualNet
	end

	for _, entry in ipairs(comboOrder) do
		entry.pricePerToken = (entry.tokensTotal > 0) and (entry.netTotal / entry.tokensTotal) or nil
	end
	return {
		tokensFulfilled = tokensAccum, cratesFilled = cratesFilled, switchEvents = switchEvents,
		grossSpend = grossSpend, totalReward = totalReward, comboPlan = comboOrder,
	}
end

local function appendFavorDemand(demandList, comboOrder, crateSpend)
	local crates, byID = {}, {}
	for _, entry in ipairs(comboOrder) do
		local crate = byID[entry.crateID]
		if not crate then
			crate = { itemID = entry.crateID, qty = 0, role = "Crate" }
			byID[entry.crateID] = crate
			crates[#crates + 1] = crate
		end
		crate.qty = crate.qty + entry.count
	end
	for _, crate in ipairs(crates) do
		local sp = crateSpend and crateSpend[crate.itemID]
		if not crateSpend or (sp and sp.qty > 0) then
			if sp then
				crate.qty, crate.actualTotal, crate.hitPriceJump = sp.qty, sp.copper, sp.hitPriceJump
			end
			demandList[#demandList + 1] = crate
		end
	end
	for _, entry in ipairs(comboOrder) do
		demandList[#demandList + 1] = {
			itemID = entry.reagentID,
			qty = entry.count * entry.reagentQtyPerCrate,
			role = "Reagent",
			parentProf = entry.prof,
			forceBuy = not crateSpend and entry.mode == "Buy",
			forceMakeMyself = entry.mode == "Craft",
		}
	end
end

local function solveFavorShoppingListImpl(targetTokens, opts)
	opts = opts or {}
	targetTokens = math.max(0, math.floor(tonumber(targetTokens) or 0))
	local deductBalance = opts.deductBalance and true or false
	local currentFavor = ns.GetFavorBalance() or 0
	local netTargetTokens = deductBalance and math.max(0, targetTokens - currentFavor) or targetTokens
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()
	local pool = ns.BuildSupplyPool(opts)
	local candidates, profFallbackFrom = getFavorCandidates(opts, profMap, repState)
	local plan = solveFavorOnPool(pool, netTargetTokens, { candidates = candidates })
	local demandList = {}
	appendFavorDemand(demandList, plan.comboPlan, pool.spent)
	local shoppingRows, shoppingSpend = ns.BuildShoppingListRows(demandList, {
		profMap = profMap,
		subCraftMode = opts.subCraftMode or "smart",
		subCraftOverrides = opts.subCraftOverrides,
		ownedCounts = opts.ownedCounts,
		spentPool = pool.spent,
	})

	plan.requestedTokens = targetTokens
	plan.deductBalance = deductBalance
	plan.currentFavor = currentFavor
	plan.netTargetTokens = netTargetTokens
	plan.shortfallTokens = math.max(0, netTargetTokens - plan.tokensFulfilled)
	plan.combosUsed = #plan.comboPlan
	plan.grossSpend = shoppingSpend
	plan.netCost = shoppingSpend - plan.totalReward
	plan.avgPricePerToken = plan.tokensFulfilled > 0 and (plan.netCost / plan.tokensFulfilled) or nil
	plan.shoppingList = shoppingRows
	plan.profFallbackFrom = profFallbackFrom
	return plan
end

function ns.SolveFavorShoppingList(targetTokens, opts)
	ns.BeginEval(opts and opts.priceBank)
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local ok, result = pcall(solveFavorShoppingListImpl, targetTokens, opts)
	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	if not ok then error(result, 0) end
	return result
end

---------------------------------------------------------------------------------------------------
-- 6. Calculator 2: Character Reputation -> Target Stage Calculator & Shopping List
---------------------------------------------------------------------------------------------------

local function cheapestForgedCrate(pool)
	local best, price
	local crates = ns.CRATES
	if not crates then return nil, nil end
	for i = 1, #crates do
		local crate = crates[i]
		local cost = pool:peekOne(crate.itemID)
		if cost ~= nil and (price == nil or cost < price) then best, price = crate, cost end
	end
	return best, price
end

local function solveForgedOnPool(pool, needed, favorEach, favorOpts)
	local function reserve(count, feeder)
		local plan = { count = 0, emptyGross = 0, legs = {} }
		local byID = {}
		for _ = 1, count do
			local crate = cheapestForgedCrate(pool)
			if not crate then break end
			local id = crate.itemID
			local cost = pool:consumeOne(id)
			local leg = byID[id]
			if not leg then
				leg = { crate = crate, count = 0, grossEmptyCost = 0 }
				byID[id] = leg
				plan.legs[#plan.legs + 1] = leg
			end
			leg.count = leg.count + 1
			leg.grossEmptyCost = leg.grossEmptyCost + cost
			plan.count = plan.count + 1
			plan.emptyGross = plan.emptyGross + cost
		end
		plan.feeder = feeder
		if not feeder and favorOpts and plan.count > 0 then
			plan.feeder = solveFavorOnPool(pool, plan.count * favorEach, favorOpts)
		end
		return plan, not plan.feeder or plan.feeder.tokensFulfilled >= plan.count * favorEach
	end
	if not favorOpts or needed <= 0 then return reserve(needed) end

	-- Restore stock before retrying so a smaller plan can use released crates as Favor feeders.
	local baseItems, baseSpent = pool.items, pool.spent
	local function copyRecords(records)
		local copy = {}
		for key, record in pairs(records) do
			local dst = {}
			for k, v in pairs(record) do dst[k] = v end
			copy[key] = dst
		end
		return copy
	end
	local function restoreStock()
		pool.items, pool.spent = {}, copyRecords(baseSpent)
		for id, lots in pairs(baseItems) do pool.items[id] = copyRecords(lots) end
	end
	local function tryCount(count)
		restoreStock()
		local plan, funded = reserve(count)
		if funded or not pool.respectStock then return plan, funded end

		-- A cheap empty crate may be the only viable feeder. Reserve it for Favor first.
		restoreStock()
		local targetFavor = plan.count * favorEach
		local feeder = solveFavorOnPool(pool, targetFavor, favorOpts)
		if feeder.tokensFulfilled >= targetFavor then
			local alternate = reserve(plan.count, feeder)
			if alternate.count == plan.count then return alternate, true end
		end
		return plan, false
	end
	local initial, funded = tryCount(needed)
	if funded then return initial end
	local best, bestItems, bestSpent = reserve(0), baseItems, baseSpent
	local low, high = 1, initial.count - 1
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local plan, canFund = tryCount(mid)
		if canFund then
			best, bestItems, bestSpent = plan, pool.items, pool.spent
			low = mid + 1
		else
			high = mid - 1
		end
	end
	pool.items, pool.spent = bestItems, bestSpent
	return best
end

local function solveRepShoppingListImpl(opts)
	opts = opts or {}
	local repState = opts.repState or ns.GetMerchantReputation()
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local targetStanding = tonumber(opts.targetStanding) or 8 -- default Exalted (42,000)
	local includeShippingLabel = opts.includeShippingLabel and true or false
	local writMode = opts.writMode or "cheapest" -- "cheapest" | "craft" | "buy"
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.unlockFilter or "all"
	local zoneFilter = opts.zoneFilter or (MerchantMasterDB and MerchantMasterDB.writZoneFilter) or "all"
	local respectStock = (opts.respectStock ~= false)
	local subMode = opts.subCraftMode or "smart"
	local overrides = opts.subCraftOverrides
	local repSourceMode = opts.repSourceMode or "writs_only"
	local hybrid = repSourceMode == "hybrid"
	local allowForged = hybrid or repSourceMode == "forged_only"
	local forgedMode = opts.forgedMode or (MerchantMasterDB and MerchantMasterDB.forgedMode) or "self_funded"
	local favorEach, forgedRefundEach, repMult, effectiveRep = forgedReceiptTerms({}, opts)

	local targetThreshold = 42000
	local targetName = "Exalted"
	for _, tier in ipairs(ns.REP_TIERS) do
		if tier.standing == targetStanding then
			targetThreshold = tier.totalRep
			targetName = tier.name
			break
		end
	end

	local startRep = (opts.simStartRep ~= nil) and tonumber(opts.simStartRep) or repState.totalFromNeutral
	local rawDiff = math.max(0, targetThreshold - startRep)
	local shippingBonus = (rawDiff > 0 and includeShippingLabel) and 2000 or 0
	local repNeeded = math.max(0, rawDiff - shippingBonus)

	local pool = ns.BuildSupplyPool({
		respectStock = respectStock,
		useOwned = opts.useOwned,
		ownedCounts = opts.ownedCounts,
	})
	local favorOpts
	if allowForged and forgedMode ~= "banked" and repNeeded > 0 then
		local candidates = getFavorCandidates({
			crateMode = opts.crateMode,
			subCraftMode = subMode, subCraftOverrides = overrides,
		}, profMap, repState)
		favorOpts = { candidates = candidates }
	end

	-- Pre-evaluate Writ crafting trees so inner step loop is instant
	local function buildWritCandidates(pFilter, uFilter, zFilter)
		local list = {}
		for _, writ in ipairs(ns.WRITS) do
			local fakeRecipe = { spellID = writ.spellID, source = "trainer" }
			local unlock = ns.EvaluateUnlock(writ.prof, writ.skill, 0, 0, fakeRecipe, profMap, repState)
			local zMatch = (not ns.MatchesWritZoneFilter) or ns.MatchesWritZoneFilter(writ, zFilter)
			if ns.MatchesGlobalFilters(writ.prof, unlock, pFilter, uFilter) and zMatch then
				local _, craftBreakdown = ns.ComputeSmartCraftCost(writ.reagents, writ.numMade or 1, writ.requiredItemID, {
					parentProf = writ.prof,
					profMap = profMap,
					subCraftMode = subMode,
					subCraftOverrides = overrides,
				})
				local buyNeed = { [writ.itemID] = 1 }
				buyNeed[writ.requiredItemID] = (buyNeed[writ.requiredItemID] or 0) + writ.qty
				local hasReagents = writ.reagents and #writ.reagents > 0 or false
				local writNumMade = math.max(1, writ.numMade or 1)
				local craftDefaultBatches, craftDefaultNeed, craftNeedByBatches
				if hasReagents then
					craftDefaultBatches = (writ.qty > 0) and math.ceil(writ.qty / writNumMade) or 0
					local zeroNeed = { [writ.itemID] = 1 }
					if craftDefaultBatches > 0 then
						craftDefaultNeed = { [writ.itemID] = 1 }
						ns.CollectLeafReagents(craftBreakdown, craftDefaultBatches, craftDefaultNeed)
						craftNeedByBatches = { [0] = zeroNeed, [craftDefaultBatches] = craftDefaultNeed }
					else
						craftDefaultNeed = zeroNeed
						craftNeedByBatches = { [0] = zeroNeed }
					end
				end
				list[#list + 1] = {
					writ = writ,
					unlock = unlock,
					craftBreakdown = craftBreakdown,
					hasReagents = hasReagents,
					buyNeed = buyNeed,
					writNumMade = writNumMade,
					craftDefaultBatches = craftDefaultBatches,
					craftDefaultNeed = craftDefaultNeed,
					craftNeedByBatches = craftNeedByBatches,
					pouchRefund = ns.GetWritPouchRefund and ns.GetWritPouchRefund(writ, opts) or 7480,
					cooldown = hybrid and opts.ignoreWritCooldowns ~= true and ns.GetWritCooldownInfo
						and ns.GetWritCooldownInfo(writ, opts) or nil,
				}
			end
		end
		return list
	end

	local candidates = {}
	local zoneFallbackFrom = nil
	if repSourceMode ~= "forged_only" then
		candidates = buildWritCandidates(profFilter, unlockFilter, zoneFilter)
		if #candidates == 0 and zoneFilter ~= "all" then
			zoneFallbackFrom = zoneFilter
			candidates = buildWritCandidates(profFilter, unlockFilter, "all")
		end
		if #candidates == 0 and (profFilter ~= "all" or unlockFilter ~= "all") then
			candidates = buildWritCandidates("all", "all", "all")
		end
	end

	local craftedSurplus = {} -- tracks extra batch items across multiple identical crafts
	local repAccum = 0
	local writsCompleted = 0
	local grossSpend = 0
	local totalPouchRefund = 0
	local planOrder = {}
	local planMap = {}
	local usedProfCount = {}
	local maxWritsPerProf = tonumber(opts.maxWritsPerProf) or 1

	local hybridFavorCache = (hybrid and favorOpts and favorOpts.candidates) and createFavorStepCache(favorOpts.candidates) or nil
	local maxSteps = 2000
	while #candidates > 0 and repAccum < repNeeded and writsCompleted < maxSteps do
		local remRep = repNeeded - repAccum
		local bestCand, bestMode, bestNeedMap, bestGross, bestNet, bestScore, bestBatches = nil, nil, nil, nil, nil, nil, 0

		for _, cand in ipairs(candidates) do
			local w = cand.writ
			if not hybrid or ((usedProfCount[w.prof] or 0) < maxWritsPerProf
				and not (cand.cooldown and cand.cooldown.onCooldown)) then
				local pouchEach = cand.pouchRefund or 0
				-- Check 1: Buy finished turn-in item on AH
				if writMode ~= "craft" then
					local buyNeed = cand.buyNeed
					local bCost = pool:peek(buyNeed)
					if bCost ~= nil then
						local netCost = bCost - pouchEach
						local denom = (netCost > 0) and math.min(w.rep, remRep) or w.rep
						local sc = netCost / denom
						if bestScore == nil
							or sc < (bestScore - 0.0001)
							or (math.abs(sc - bestScore) <= 0.0001 and (netCost / w.rep) < (bestNet / bestCand.writ.rep)) then
							bestCand, bestMode, bestNeedMap, bestGross, bestNet, bestScore, bestBatches = cand, "Buy", buyNeed, bCost, netCost, sc, 0
						end
					end
				end

				-- Check 2: Craft turn-in item from AH/Vendor reagents
				if writMode ~= "buy" and cand.hasReagents then
					local surplus = craftedSurplus[w.requiredItemID] or 0
					local batches, craftNeed
					if surplus == 0 and cand.craftDefaultNeed then
						batches = cand.craftDefaultBatches
						craftNeed = cand.craftDefaultNeed
					else
						local netItemsToMake = w.qty - surplus
						local numMade = cand.writNumMade or math.max(1, w.numMade or 1)
						batches = (netItemsToMake > 0) and math.ceil(netItemsToMake / numMade) or 0
						local byB = cand.craftNeedByBatches
						craftNeed = byB and byB[batches]
						if not craftNeed then
							craftNeed = { [w.itemID] = 1 }
							if batches > 0 then
								ns.CollectLeafReagents(cand.craftBreakdown, batches, craftNeed)
							end
							if byB then byB[batches] = craftNeed end
						end
					end
					local cCost = pool:peek(craftNeed)
					if cCost ~= nil then
						local netCost = cCost - pouchEach
						local denom = (netCost > 0) and math.min(w.rep, remRep) or w.rep
						local sc = netCost / denom
						if bestScore == nil
							or sc < (bestScore - 0.0001)
							or (math.abs(sc - bestScore) <= 0.0001 and (netCost / w.rep) < (bestNet / bestCand.writ.rep)) then
							bestCand, bestMode, bestNeedMap, bestGross, bestNet, bestScore, bestBatches = cand, "Craft", craftNeed, cCost, netCost, sc, batches
						end
					end
				end
			end
		end

		if not bestCand then
			break -- Available AH Writ scrolls or materials exhausted!
		end
		if hybrid then
			local _, emptyCost = cheapestForgedCrate(pool)
			local favorCost = 0
			if favorOpts and emptyCost ~= nil then
				local cand, _, _, _, net = pickFavorStep(pool, favorOpts.candidates, {}, math.huge, hybridFavorCache)
				favorCost = cand and (favorEach * net / cand.tokens)
			end
			if emptyCost ~= nil and favorCost ~= nil and effectiveRep > 0 then
				local forgedNet = emptyCost - forgedRefundEach + favorCost
				local denom = forgedNet > 0 and math.min(effectiveRep, remRep) or effectiveRep
				if bestScore >= forgedNet / denom then
					if not favorOpts or not respectStock then break end
					local items, spent = pool.items, pool.spent
					local preview = solveForgedOnPool(pool, 1, favorEach, favorOpts)
					pool.items, pool.spent = items, spent
					if preview.count > 0 then break end
				end
			end
		end

		local w = bestCand.writ
		if hybrid then usedProfCount[w.prof] = (usedProfCount[w.prof] or 0) + 1 end
		local pouchEach = bestCand.pouchRefund or 0
		local stepGross = pool:consume(bestNeedMap)
		if hybridFavorCache then hybridFavorCache:invalidateNeedMap(bestNeedMap) end
		local stepNet = stepGross - pouchEach
		if bestMode == "Craft" then
			local produced = bestBatches * math.max(1, w.numMade or 1)
			craftedSurplus[w.requiredItemID] = (craftedSurplus[w.requiredItemID] or 0) + produced - w.qty
		end

		repAccum = repAccum + w.rep
		writsCompleted = writsCompleted + 1
		grossSpend = grossSpend + stepGross
		totalPouchRefund = totalPouchRefund + pouchEach

		local pKey = tostring(w.itemID) .. ":" .. bestMode
		local entry = planMap[pKey]
		if not entry then
			local pObj = ns.PROF_BY_KEY[w.prof]
			local zLabel = ns.GetWritZoneLabel and ns.GetWritZoneLabel(w) or "Unmapped"
			entry = {
				key = pKey,
				writ = w,
				writID = w.itemID,
				writName = ns.ItemName(w.itemID, w.name):gsub("^Craftsman's Writ:%s*", ""),
				writFullName = ns.ItemName(w.itemID, w.name),
				reqItemID = w.requiredItemID,
				reqItemName = ns.ItemName(w.requiredItemID, w.requiredItemName),
				reqQtyEach = w.qty,
				prof = w.prof,
				profSkillLabel = (pObj and pObj.label or w.prof) .. " " .. tostring(w.skill),
				zone = zLabel,
				npc = (w.npc and w.npc ~= "") and w.npc or nil,
				coordText = (w.x and w.y and ((tonumber(w.x) or 0) > 0 or (tonumber(w.y) or 0) > 0))
					and string.format("%.1f, %.1f", tonumber(w.x) or 0, tonumber(w.y) or 0) or nil,
				mode = bestMode,
				count = 0,
				repEach = w.rep,
				repTotal = 0,
				grossCost = 0,
				pouchRefund = 0,
				totalCost = 0,
				craftBreakdown = bestCand.craftBreakdown,
				numMade = w.numMade or 1,
				dailySold = ns.GetDailySold(w.requiredItemID),
			}
			planMap[pKey] = entry
			planOrder[#planOrder + 1] = entry
		end
		entry.count = entry.count + 1
		entry.repTotal = entry.repTotal + w.rep
		entry.grossCost = entry.grossCost + stepGross
		entry.pouchRefund = entry.pouchRefund + pouchEach
		entry.totalCost = entry.totalCost + stepNet
	end

	for _, entry in ipairs(planOrder) do
		entry.pricePerRep = (entry.repTotal > 0) and (entry.totalCost / entry.repTotal) or nil
		entry.grossPricePerRep = (entry.repTotal > 0) and (entry.grossCost / entry.repTotal) or nil
	end

	-- Assemble Shopping List: 1. Writ Scrolls, 2. Bought Turn-In Items, 3. Direct Crafting Reagents (with Sub-Craft tree!)
	local demandList = {}
	local seenWrit = {}
	for _, entry in ipairs(planOrder) do
		if not seenWrit[entry.writID] then
			seenWrit[entry.writID] = true
			local sp = pool.spent[entry.writID]
			if sp and sp.qty > 0 then
				demandList[#demandList + 1] = {
					itemID = entry.writID,
					qty = sp.qty,
					role = "Writ",
					actualTotal = sp.copper,
					hitPriceJump = sp.hitPriceJump,
				}
			end
		end
	end

	for _, entry in ipairs(planOrder) do
		if entry.mode == "Buy" then
			local sp = pool.spent[entry.reqItemID]
			demandList[#demandList + 1] = {
				itemID = entry.reqItemID,
				qty = entry.count * entry.reqQtyEach,
				role = "Turn-In",
				parentProf = entry.prof,
				forceBuy = hybrid,
				actualTotal = sp and sp.copper or nil,
				hitPriceJump = sp and sp.hitPriceJump or false,
			}
		else
			-- Emit top-level crafting reagents for this Writ so Cured Hide / Bolts show BOTH AH Price & Craft Price + Sub-Mats!
			local totalItemsNeeded = entry.count * entry.reqQtyEach
			local batches = math.ceil(totalItemsNeeded / math.max(1, entry.numMade))
			for _, rg in ipairs(entry.craftBreakdown or {}) do
				local rgQty = rg.qty * batches
				local sp = (not rg.makeMyself) and pool.spent[rg.itemID] or nil
				demandList[#demandList + 1] = {
					itemID = rg.itemID,
					qty = rgQty,
					role = "Reagent",
					parentProf = entry.prof,
					forceBuy = hybrid and not rg.makeMyself,
					forceMakeMyself = hybrid and rg.makeMyself,
					actualTotal = (sp and sp.qty == rgQty) and sp.copper or nil,
					hitPriceJump = sp and sp.hitPriceJump or false,
				}
			end
		end
	end

	local neededForgedCount = allowForged and effectiveRep > 0 and math.ceil((repNeeded - repAccum) / effectiveRep) or 0
	local forged = solveForgedOnPool(pool, neededForgedCount, favorEach, favorOpts)
	local forgedCount = forged.count
	local forgedRep = forgedCount * effectiveRep
	local forgedRefund = forgedCount * forgedRefundEach
	local favorNeeded = (forgedMode ~= "banked") and (forgedCount * favorEach) or 0
	local feeder = forged.feeder
	local favorRefund = feeder and feeder.totalReward or 0
	local favorFulfilled = (forgedMode ~= "banked") and (feeder and feeder.tokensFulfilled or 0) or 0
	local leftoverFavor = (forgedMode ~= "banked") and (favorFulfilled - favorNeeded) or 0
	local feederGross = feeder and feeder.grossSpend or 0
	local feederNet = feederGross - favorRefund
	local forgedCost = forged.emptyGross - forgedRefund + feederNet
	local forgedAmortizedCost = forged.emptyGross - forgedRefund
		+ (favorFulfilled > 0 and (feederNet * favorNeeded / favorFulfilled) or 0)
	local totalRefund = totalPouchRefund + forgedRefund + favorRefund

	local forgedRows, repPlan = {}, {}
	for _, entry in ipairs(planOrder) do repPlan[#repPlan + 1] = entry end
	if forgedCount > 0 then
		-- Reconcile actual totals after merging the Writ, Forged and Favor quantities for each item.
		for _, item in ipairs(demandList) do item.actualTotal = nil end
		local receipt = ns.FORGED_RECEIPT or {}
		local npc = forgedTurnInNPC(receipt, repState.playerFaction)
		local countsLeft = forgedCount
		local grossLeft, refundLeft, feedersLeft = feederGross, favorRefund, feeder and feeder.cratesFilled or 0
		for _, leg in ipairs(forged.legs) do
			local crate, count = leg.crate, leg.count
			local id, name = crate.itemID, ns.ItemName(crate.itemID, crate.name)
			demandList[#demandList + 1] = { itemID = id, qty = count, role = "Crate" }

			local share = count / countsLeft
			local grossShare = math.floor(grossLeft * share + 0.5)
			local refundShare = math.floor(refundLeft * share + 0.5)
			local feederShare = math.floor(feedersLeft * share + 0.5)
			countsLeft = countsLeft - count
			grossLeft, refundLeft, feedersLeft = grossLeft - grossShare, refundLeft - refundShare, feedersLeft - feederShare
			local legForgedRefund = count * forgedRefundEach
			local legRefund = legForgedRefund + refundShare
			local legGross = leg.grossEmptyCost + grossShare
			local legNet = legGross - legRefund
			local legRep = count * effectiveRep
			local costPerRep = legNet / legRep
			local row = {
				forged = true, key = "forged:" .. tostring(id), crateID = id, name = name, crateName = name,
				tier = crate.tier, quality = crate.quality, count = count, repEach = effectiveRep, rep = effectiveRep, repTotal = legRep,
				emptyPrice = leg.grossEmptyCost / count, grossEmptyCost = leg.grossEmptyCost, forgedRefund = legForgedRefund,
				favorNeeded = (forgedMode ~= "banked") and (count * favorEach) or 0, feederCrate = feeder and feeder.comboPlan[1], feederCount = feederShare,
				leftoverFavor = countsLeft == 0 and leftoverFavor or 0, favorRefund = refundShare, totalRefund = legRefund,
				grossCost = legGross, netCost = legNet, costPerRep = costPerRep, forgedMode = forgedMode, repMult = repMult,
				writName = receipt.questName or "Crate Return", reqItemName = name, zone = npc, profSkillLabel = "-",
				mode = forgedMode == "banked" and "Banked Favor" or "Self-Funded",
				pouchRefund = legRefund, totalCost = legNet, pricePerRep = costPerRep,
				writID = id, writFullName = name, reqQtyEach = 1,
			}
			forgedRows[#forgedRows + 1] = row
			repPlan[#repPlan + 1] = row
		end
		if feeder then appendFavorDemand(demandList, feeder.comboPlan) end
		grossSpend = grossSpend + forged.emptyGross + feederGross
	end

	local shoppingRows, shoppingSpend = ns.BuildShoppingListRows(demandList, {
		profMap = profMap,
		subCraftMode = subMode,
		subCraftOverrides = overrides,
		ownedCounts = opts.ownedCounts,
		spentPool = pool.spent,
		useAllocationCosts = forgedCount > 0,
	})

	local finalGross = (#shoppingRows > 0) and shoppingSpend or grossSpend
	local finalNet = finalGross - totalRefund
	local repFulfilled = repAccum + forgedRep
	local avgPPR = (repFulfilled > 0) and (finalNet / repFulfilled) or nil
	local avgGrossPPR = (repFulfilled > 0) and (finalGross / repFulfilled) or nil

	return {
		repState = repState,
		startRep = startRep,
		targetStanding = targetStanding,
		targetName = targetName,
		targetThreshold = targetThreshold,
		rawDiff = rawDiff,
		includeShippingLabel = includeShippingLabel,
		shippingBonus = shippingBonus,
		includeWritPouch = (totalPouchRefund > 0) or (ns.GetWritPouchRefund and ns.GetWritPouchRefund(nil, opts) > 0) or false,
		zoneFilter = zoneFilter,
		zoneFallbackFrom = zoneFallbackFrom,
		repNeeded = repNeeded,
		repFulfilled = repFulfilled,
		shortfallRep = math.max(0, repNeeded - repFulfilled),
		writsCompleted = writsCompleted,
		distinctWrits = #planOrder,
		grossSpend = finalGross,
		grossCost = finalGross,
		pouchRefund = totalPouchRefund,
		totalCost = finalNet,
		netCost = finalNet,
		avgPricePerRep = avgPPR,
		avgGrossPricePerRep = avgGrossPPR,
		writPlan = planOrder,
		shoppingList = shoppingRows,
		repSourceMode = repSourceMode,
		forgedMode = forgedMode,
		repMult = repMult,
		effectiveRep = effectiveRep,
		forgedCount = forgedCount,
		forgedRep = forgedRep,
		forgedCost = forgedCost,
		forgedAmortizedCost = forgedAmortizedCost,
		forgedRows = forgedRows,
		repPlan = repPlan,
		forgedRefund = forgedRefund,
		favorRefund = favorRefund,
		crateCashback = favorRefund,
		totalRefund = totalRefund,
		totalCashback = totalRefund,
		favorNeeded = favorNeeded,
		favorFulfilled = favorFulfilled,
		leftoverFavor = leftoverFavor,
	}
end

function ns.SolveRepShoppingList(opts)
	ns.BeginEval(opts and opts.priceBank)
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local ok, result = pcall(solveRepShoppingListImpl, opts)
	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	if not ok then error(result, 0) end
	return result
end

-- Builds a Turn-In Shopping List for queued Writs (or all priced Writs in an active Area filter)
function ns.BuildWritTurnInShoppingList(writRows, writTurnInQueue, opts)
	ns.BeginEval()
	opts = opts or {}
	writRows = writRows or ns.BuildWritRows(opts)
	writTurnInQueue = writTurnInQueue or (MerchantMasterDB and MerchantMasterDB.writTurnInQueue) or {}

	local rowByWritID = {}
	for _, r in ipairs(writRows) do
		if r.writID then
			rowByWritID[r.writID] = r
		end
	end

	-- Always resolve any queued writIDs not in the currently filtered writRows from an unfiltered BuildWritRows
	local needsFullLookup = false
	for writID, cnt in pairs(writTurnInQueue) do
		if (tonumber(cnt) or 0) > 0 and not rowByWritID[writID] then
			needsFullLookup = true
			break
		end
	end
	if needsFullLookup then
		local allWritRows = ns.BuildWritRows({
			writMode = opts.writMode or "cheapest",
			includeWritPouch = opts.includeWritPouch,
			writTurnInQueue = writTurnInQueue,
			subCraftMode = opts.subCraftMode,
			subCraftOverrides = opts.subCraftOverrides,
			ownedCounts = opts.ownedCounts,
			profMap = opts.profMap,
			repState = opts.repState,
		})
		for _, r in ipairs(allWritRows) do
			if r.writID and not rowByWritID[r.writID] then
				rowByWritID[r.writID] = r
			end
		end
	end

	local targets = {}
	local hasQueue = false
	for writID, cnt in pairs(writTurnInQueue) do
		local n = tonumber(cnt) or 0
		if n > 0 and rowByWritID[writID] then
			hasQueue = true
			targets[#targets + 1] = { row = rowByWritID[writID], count = math.floor(n + 0.5) }
		end
	end

	local zoneFilter = opts.zoneFilter or (MerchantMasterDB and MerchantMasterDB.writZoneFilter) or "all"
	if not hasQueue then
		if opts.areaAllPriced or (zoneFilter ~= "all" and zoneFilter ~= "unmapped" and zoneFilter ~= "mapped") then
			for _, r in ipairs(writRows) do
				if r.totalPrice ~= nil then
					targets[#targets + 1] = { row = r, count = 1, isAreaAuto = true }
				end
			end
		end
		if #targets == 0 and opts.fallbackBest ~= false then
			local bestRow = nil
			for _, r in ipairs(writRows) do
				if r.pricePerRep ~= nil and (not bestRow or r.pricePerRep < bestRow.pricePerRep) then
					bestRow = r
				end
			end
			if bestRow then
				targets[#targets + 1] = { row = bestRow, count = 1, isPreview = true }
			end
		end
	end

	table.sort(targets, function(a, b)
		local za, zb = a.row.zone or "Unmapped", b.row.zone or "Unmapped"
		if za ~= zb then return za < zb end
		return (a.row.writName or "") < (b.row.writName or "")
	end)

	local demandList = {}
	local totalRep = 0
	local totalWritCount = 0
	local pouchRefundTotal = 0
	local areaCounts = {}
	local areaOrder = {}

	for _, t in ipairs(targets) do
		local r = t.row
		local cnt = math.max(1, t.count or 1)
		totalWritCount = totalWritCount + cnt
		local z = r.zone or (ns.GetWritZoneLabel and ns.GetWritZoneLabel(r.writ)) or "Unmapped"
		if not areaCounts[z] then
			areaCounts[z] = 0
			areaOrder[#areaOrder + 1] = z
		end
		areaCounts[z] = areaCounts[z] + cnt

		totalRep = totalRep + (tonumber(r.rep) or 0) * cnt
		local pEach = (r.pouchRefund ~= nil) and r.pouchRefund or (ns.GetWritPouchRefund and ns.GetWritPouchRefund(r.writ, opts) or 7480)
		pouchRefundTotal = pouchRefundTotal + (pEach * cnt)

		demandList[#demandList + 1] = {
			itemID = r.writID,
			qty = cnt,
			role = "Writ",
		}

		local reqQtyTotal = cnt * math.max(1, tonumber(r.reqQty) or (r.writ and r.writ.qty) or 1)
		if r.mode == "Craft" and r.craftBreakdown and #r.craftBreakdown > 0 then
			local numMade = math.max(1, (r.writ and r.writ.numMade) or 1)
			local batches = math.ceil(reqQtyTotal / numMade)
			for _, rg in ipairs(r.craftBreakdown) do
				demandList[#demandList + 1] = {
					itemID = rg.itemID,
					qty = rg.qty * batches,
					role = "Reagent",
					parentProf = r.prof,
				}
			end
		else
			demandList[#demandList + 1] = {
				itemID = r.reqItemID,
				qty = reqQtyTotal,
				role = "Turn-In",
				parentProf = r.prof,
			}
		end
	end

	local shoppingRows, shoppingSpend, missingPriceCount = ns.BuildShoppingListRows(demandList, opts)
	missingPriceCount = missingPriceCount or 0
	local hasAllPrices = (#targets > 0 and missingPriceCount == 0)
	local grossSpend = hasAllPrices and (shoppingSpend or 0) or nil
	local netCost = grossSpend and (grossSpend - pouchRefundTotal) or nil

	local areaParts = {}
	for _, z in ipairs(areaOrder) do
		areaParts[#areaParts + 1] = string.format("%s (%d)", z, areaCounts[z])
	end
	local areaSummary = (#areaParts > 0) and table.concat(areaParts, " · ") or "None"

	local turnInOut = {
		hasQueue = hasQueue,
		targets = targets,
		writCount = totalWritCount,
		shoppingList = shoppingRows,
		missingPriceCount = missingPriceCount,
		grossSpend = grossSpend,
		pouchRefundTotal = pouchRefundTotal,
		netCost = netCost,
		totalRep = totalRep,
		areaSummary = areaSummary,
	}
	ns.EndEval()
	return turnInOut
end

---------------------------------------------------------------------------------------------------
-- 7. Craftsman's Writ Crafter Profit Explorer + Craft Queue Shopping List
---------------------------------------------------------------------------------------------------

function ns.BuildWritProfitRows(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.knownRecipesOnly and "known" or (opts.unlockFilter or "all")
	local demandFilter = opts.demandFilter or "all"
	local craftableFilter = opts.craftableFilter or "all"
	local applyAHCut = (opts.applyAHCut ~= false)
	local postDuration = tonumber(opts.postDuration) or 1
	local subMode = opts.subCraftMode or "smart"
	local overrides = opts.subCraftOverrides
	local craftQueue = opts.craftQueue or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()

	local rows = {}
	local bestProfitRow = nil
	local profitableCount, totalMatched = 0, 0
	local summary = {
		canCraftCount = 0,
		monopolyCount = 0,
		highTurnCount = 0,
		hotCount = 0,
		coldCount = 0,
	}

	for idx, writ in ipairs(ns.WRITS) do
		local srcPass = (not ns.MatchesRecipeSourceFilter)
			or ns.MatchesRecipeSourceFilter(writ, opts.recipeSources, opts.merchantVendorOnly, opts.sourceFilter)
		if srcPass then
		local unlock = ns.EvaluateUnlock(writ.prof, writ.skill, 0, 0, writ, profMap, repState)
		if ns.MatchesGlobalFilters(writ.prof, unlock, profFilter, unlockFilter) then
			local craftAbility = ns.EvaluateCraftAbility(writ, profMap, repState)
			if ns.MatchesCraftableFilter(craftAbility, craftableFilter) then
				local listed = ns.GetNumListed(writ.requiredItemID)
				local dailySold = ns.GetDailySold(writ.requiredItemID)
				local demand = ns.EvaluateMarketDemand(listed, dailySold, true)
				if ns.MatchesDemandFilter(demand, demandFilter) then
					local itemName = ns.ItemName(writ.requiredItemID, writ.requiredItemName)
					local writFull = ns.ItemName(writ.itemID, writ.name)
					local writShort = writFull:gsub("^Craftsman's Writ:%s*", "")
					if needle == ""
						or itemName:lower():find(needle, 1, true)
						or writShort:lower():find(needle, 1, true)
						or writ.prof:lower():find(needle, 1, true)
						or (craftAbility.howShort and craftAbility.howShort:lower():find(needle, 1, true))
						or (craftAbility.howDetail and craftAbility.howDetail:lower():find(needle, 1, true))
						or (demand.tierKey and demand.tierKey:lower():find(needle, 1, true)) then
						totalMatched = totalMatched + 1

						local craftCost, breakdown, craftSrc, directCraftCost, usedSubCraft = ns.ComputeSmartCraftCost(
							writ.reagents, writ.numMade or 1, writ.requiredItemID, {
								parentProf = writ.prof,
								profMap = profMap,
								subCraftMode = subMode,
								subCraftOverrides = overrides,
							}
						)
						local listingDeposit, depositExact, vendorSell = ns.GetAHListingDeposit(writ.requiredItemID, postDuration, 1)
						local val = ns.ResolveOutputSaleValuation(
							writ.requiredItemID,
							listed,
							true,
							craftCost,
							applyAHCut,
							opts.outlierPrices
						)
						local ahPrice, ahSource = val.ahValue, val.ahSource
						local ahCut = (ahPrice and not val.usedVendorFloor) and math.floor(ahPrice * 0.05 + 0.5) or nil

						local profitPerItem, marginPct, orderProfit = val.profit, val.marginPct, nil
						if profitPerItem ~= nil then
							orderProfit = profitPerItem * writ.qty
							if profitPerItem > 0 then
								profitableCount = profitableCount + 1
							end
						end

						if craftAbility.ableToCraft then summary.canCraftCount = summary.canCraftCount + 1 end
						if demand.isMonopoly then summary.monopolyCount = summary.monopolyCount + 1 end
						if demand.tierKey == "high_turn" then summary.highTurnCount = summary.highTurnCount + 1 end
						if demand.isHot then summary.hotCount = summary.hotCount + 1 end
						if demand.tierKey == "cold" then summary.coldCount = summary.coldCount + 1 end

						local subSavings = (usedSubCraft and directCraftCost and craftCost and directCraftCost > craftCost)
							and (directCraftCost - craftCost) or 0

						local pObj = ns.PROF_BY_KEY[writ.prof]
						local qQty = craftQueue[writ.requiredItemID] or 0

						local row = {
							idx = idx,
							writ = writ,
							writID = writ.itemID,
							writName = writShort,
							writFullName = writFull,
							itemID = writ.requiredItemID,
							recipeItemID = craftAbility.recipeItemID,
							name = itemName,
							icon = ns.ItemIcon(writ.requiredItemID, ns.QUESTION_ICON),
							writQty = writ.qty,
							rep = writ.rep,
							numMade = writ.numMade or 1,
							prof = writ.prof,
							profLabel = (pObj and pObj.label or writ.prof) .. " " .. tostring(writ.skill),
							profSort = (pObj and pObj.label or writ.prof) .. string.format("%03d", writ.skill),
							skill = writ.skill,
							unlock = unlock,
							craftAbility = craftAbility,
							canCraft = craftAbility.ableToCraft,
							canCraftSort = craftAbility.sortScore,
							demand = demand,
							demandSort = demand.demandScore,
							salesRatio = demand.salesRatio,
							listedSort = demand.listedSort,
							demandState = demand.stateLabel,
							dailySold = dailySold,
							craftCost = craftCost,
							directCraftCost = directCraftCost,
							usedSubCraft = usedSubCraft,
							subSavings = subSavings,
							craftBreakdown = breakdown,
							craftSource = craftSrc,
							listed = listed,
							ahPrice = ahPrice,
							ahValue = ahPrice,
							ahSource = ahSource,
							isUnlisted = val.isUnlisted,
							isCustomPrice = val.isCustomPrice,
							usedVendorFloor = val.usedVendorFloor,
							lastKnownPrice = val.lastKnownPrice,
							lastKnownSource = val.lastKnownSource,
							ahListingCost = listingDeposit,
							depositExact = depositExact,
							vendorSell = vendorSell,
							ahCut = ahCut,
							profit = profitPerItem,
							orderProfit = orderProfit,
							marginPct = marginPct,
							queuedQty = qQty,
						}

						if row.profit ~= nil and (not bestProfitRow or row.profit > bestProfitRow.profit) then
							bestProfitRow = row
						end
						rows[#rows + 1] = row
					end
				end
			end
		end
		end
	end

	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	return rows, bestProfitRow, profitableCount, totalMatched, summary
end

-- Builds the Shopping List for the Writ Profit screen (from Craft Queue, or selected/top Writ item)
function ns.BuildWritCraftShoppingList(writRowsByItemID, craftQueue, selectedItemID, opts)
	opts = opts or {}
	local targets = {}
	local hasQueue = false
	for itemID, qty in pairs(craftQueue or {}) do
		if qty and qty > 0 and writRowsByItemID[itemID] then
			hasQueue = true
			targets[#targets + 1] = { row = writRowsByItemID[itemID], qty = qty }
		end
	end
	table.sort(targets, function(a, b) return a.row.name < b.row.name end)

	if not hasQueue and selectedItemID and writRowsByItemID[selectedItemID] then
		local r = writRowsByItemID[selectedItemID]
		targets[#targets + 1] = { row = r, qty = r.writQty or 1, isPreview = true }
	end

	local demandList = {}
	local estRevenue, estDeposit = 0, 0
	local applyAHCut = (opts.applyAHCut ~= false)
	local postDuration = tonumber(opts.postDuration) or 1

	for _, t in ipairs(targets) do
		local r = t.row
		local batches = math.ceil(t.qty / math.max(1, r.numMade or 1))
		local actualProduced = batches * math.max(1, r.numMade or 1)
		if r.ahPrice then
			local unitNet = applyAHCut and math.floor(r.ahPrice * 0.95 + 0.5) or r.ahPrice
			estRevenue = estRevenue + (unitNet * actualProduced)
		end
		local dep = ns.GetAHListingDeposit(r.itemID, postDuration, actualProduced)
		if dep then estDeposit = estDeposit + dep end

		for _, rg in ipairs(r.craftBreakdown or {}) do
			demandList[#demandList + 1] = {
				itemID = rg.itemID,
				qty = rg.qty * batches,
				role = "Reagent",
				parentProf = r.prof,
			}
		end
	end

	local shoppingRows, totalCraftSpend, missingCount = ns.BuildShoppingListRows(demandList, opts)
	local estProfit = (#targets > 0 and missingCount == 0 and estRevenue > 0) and (estRevenue - totalCraftSpend) or nil

	return {
		hasQueue = hasQueue,
		targets = targets,
		shoppingList = shoppingRows,
		totalCraftCost = totalCraftSpend,
		estNetRevenue = estRevenue,
		estListingDeposit = estDeposit,
		estTotalProfit = estProfit,
	}
end

---------------------------------------------------------------------------------------------------
-- 8. Most Profitable Waylaid Crate Materials Explorer (For Gatherers & Material Suppliers)
---------------------------------------------------------------------------------------------------

function ns.BuildCrateMaterialRows(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.knownRecipesOnly and "known" or (opts.unlockFilter or "all")
	local matTypeFilter = opts.matTypeFilter or "all" -- "all" | "gather" | "crafted"
	local demandFilter = opts.demandFilter or "all"
	local applyAHCut = (opts.applyAHCut ~= false)
	local subMode = opts.subCraftMode or "smart"
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()

	local rows = {}
	local bestRow = nil
	local totalMatched = 0

	for _, crate in ipairs(ns.CRATES) do
		local crateDisplay = ns.ItemName(crate.itemID, crate.name):gsub("^Waylaid Crate:%s*", "")
		local tokens = ns.GetCrateReward(crate)

		-- Find which bundle is currently the #1 cheapest filler for this crate (highest buyer demand!)
		local cheapestBundleID, cheapestBundleCost = nil, nil
		for _, b in ipairs(crate.bundles) do
			local p = ns.GetItemMarketPrice(b.itemID)
			if p then
				local bTot = p * b.qty
				if not cheapestBundleCost or bTot < cheapestBundleCost then
					cheapestBundleCost, cheapestBundleID = bTot, b.itemID
				end
			end
		end

		for _, bundle in ipairs(crate.bundles) do
			local id = bundle.itemID
			local gatherInfo = ns.GATHER_BY_ITEM[id]
			local craftOpt = ns.GetItemCraftOption(id, {
				parentProf = bundle.prof,
				profMap = profMap,
				subCraftMode = subMode,
			})
			local isCraftedMat = (craftOpt ~= nil) and (gatherInfo == nil)
			local isGatherOrFarm = not isCraftedMat

			local passType = (matTypeFilter == "all")
				or (matTypeFilter == "gather" and isGatherOrFarm)
				or (matTypeFilter == "crafted" and isCraftedMat)

			if passType then
				local fakeRec = isGatherOrFarm and { source = "gather" } or (craftOpt and craftOpt.recipe)
				local unlock = ns.EvaluateUnlock(bundle.prof, bundle.skill, 0, 0, fakeRec, profMap, repState)
				if ns.MatchesGlobalFilters(bundle.prof, unlock, profFilter, unlockFilter) then
					local matName = ns.ItemName(id, bundle.name)
					if needle == ""
						or matName:lower():find(needle, 1, true)
						or crateDisplay:lower():find(needle, 1, true)
						or bundle.prof:lower():find(needle, 1, true)
						or (gatherInfo and gatherInfo.note and gatherInfo.note:lower():find(needle, 1, true)) then
						local listed = ns.GetNumListed(id)
						local dailySold = ns.GetDailySold(id)
						local demand = ns.EvaluateMarketDemand(listed, dailySold, true)
						if ns.MatchesDemandFilter(demand, demandFilter) then
							totalMatched = totalMatched + 1
							local unitCraftCost = isCraftedMat and craftOpt.unitCraftCost or 0
							local val = ns.ResolveOutputSaleValuation(
								id,
								listed,
								true,
								unitCraftCost,
								applyAHCut,
								opts.outlierPrices
							)
							local ahPrice, ahSource = val.ahValue, val.ahSource
							local bundleGross = ahPrice and (ahPrice * bundle.qty) or nil
							local bundleNet = bundleGross and (
								(applyAHCut and not val.usedVendorFloor) and math.floor(bundleGross * 0.95 + 0.5) or bundleGross
							) or nil

							local bundleCraftCost = (unitCraftCost ~= nil) and (unitCraftCost * bundle.qty) or nil
							local bundleProfit = (bundleNet ~= nil and bundleCraftCost ~= nil) and (bundleNet - bundleCraftCost) or nil
							local dailyGoldVol = (ahPrice and dailySold) and math.floor(ahPrice * dailySold + 0.5) or nil
							local isBestFiller = (cheapestBundleID == id)
							local craftAbility = (isCraftedMat and craftOpt and craftOpt.recipe)
								and ns.EvaluateCraftAbility(craftOpt.recipe, profMap, repState)
								or nil

							local pObj = ns.PROF_BY_KEY[bundle.prof]
							local profLabel = pObj and (pObj.label .. " " .. tostring(bundle.skill)) or "Farm"

							local row = {
								itemID = id,
								name = matName,
								icon = ns.ItemIcon(id, ns.QUESTION_ICON),
								crateID = crate.itemID,
								crateName = crateDisplay,
								crateQuality = crate.quality,
								tokens = tokens,
								bundleQty = bundle.qty,
								crateLabel = string.format("%s (x%d)", crateDisplay, bundle.qty),
								isBestFiller = isBestFiller,
								isGather = isGatherOrFarm,
								isCraftedMat = isCraftedMat,
								gatherInfo = gatherInfo,
								craftOpt = craftOpt,
								craftAbility = craftAbility,
								prof = bundle.prof,
								profLabel = profLabel,
								profSort = profLabel,
								skill = bundle.skill,
								unlock = unlock,
								ahPrice = ahPrice,
								ahValue = ahPrice,
								ahSource = ahSource,
								isUnlisted = val.isUnlisted,
								isCustomPrice = val.isCustomPrice,
								usedVendorFloor = val.usedVendorFloor,
								lastKnownPrice = val.lastKnownPrice,
								lastKnownSource = val.lastKnownSource,
								vendorSell = val.vendorSell,
								bundleValue = bundleGross,
								craftCost = isCraftedMat and unitCraftCost or 0,
								bundleProfit = bundleProfit,
								listed = listed,
								listedSort = (listed ~= nil) and listed or 999999,
								dailySold = dailySold,
								demand = demand,
								demandSort = demand.demandScore,
								dailyGoldVol = dailyGoldVol,
							}

							if row.dailyGoldVol ~= nil and (not bestRow or row.dailyGoldVol > bestRow.dailyGoldVol) then
								bestRow = row
							end
							rows[#rows + 1] = row
						end
					end
				end
			end
		end
	end

	if #rows == 0 and needle == "" and (profFilter ~= "all" or unlockFilter ~= "all") and not opts._isFallback then
		local fbOpts = {}
		for k, v in pairs(opts) do fbOpts[k] = v end
		fbOpts.profFilter = "all"
		fbOpts.unlockFilter = "all"
		fbOpts._isFallback = true
		local fbRows, fbBest, fbTotal = ns.BuildCrateMaterialRows(fbOpts)
		if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
		ns.EndEval()
		return fbRows, fbBest, fbTotal, profFilter
	end

	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	return rows, bestRow, totalMatched, nil
end

---------------------------------------------------------------------------------------------------
-- 9. v3.0 Profit-Maximizing Engines: Profit Spread, Outliers (Custom Price), Dashboard & Simple View
---------------------------------------------------------------------------------------------------

ns.SPREAD_COUNTS = {
	{ key = 5,  label = "Spread: Top 5 Crafts" },
	{ key = 8,  label = "Spread: Top 8 Crafts" },
	{ key = 12, label = "Spread: Top 12 Crafts" },
	{ key = 20, label = "Spread: Top 20 Crafts" },
}

ns.OUTLIER_SCOPES = {
	{ key = "monopoly", label = "Stock: 0-2 (Monopoly)" },
	{ key = "unlisted", label = "Stock: 0 Only (Unlisted)" },
	{ key = "thin",     label = "Stock: 0-4 (Thin AH)" },
}

ns.OUTLIER_QUALITY_FILTERS = {
	{ key = "good", label = "Filter: Good Products" },
	{ key = "bis",  label = "Filter: Best in Class" },
	{ key = "all",  label = "Filter: All Unlisted/Thin" },
}

ns.DASHBOARD_SCOPES = {
	{ key = "smart",     label = "Advice: Smart (Known -> Potential)" },
	{ key = "known",     label = "Advice: Known Recipes (Can Do)" },
	{ key = "able",      label = "Advice: Able to Craft Now" },
	{ key = "potential", label = "Advice: My Profs (Potential)" },
	{ key = "all",       label = "Advice: All Professions (Max)" },
}

-- Fast lookup maps: which items are demanded by Craftsman's Writs or Waylaid Crates
ns.WRIT_BY_REQ_ITEM = {}
for _, w in ipairs(ns.WRITS or {}) do
	local reqID = w.requiredItemID or w.reqItemID
	if reqID and not ns.WRIT_BY_REQ_ITEM[reqID] then
		ns.WRIT_BY_REQ_ITEM[reqID] = w
	end
end

ns.CRATE_BY_BUNDLE_ITEM = {}
for _, c in ipairs(ns.CRATES or {}) do
	for _, b in ipairs(c.bundles or {}) do
		if b.itemID and not ns.CRATE_BY_BUNDLE_ITEM[b.itemID] then
			ns.CRATE_BY_BUNDLE_ITEM[b.itemID] = { crate = c, bundle = b }
		end
	end
end

-- Parses flexible money text ("2g 50s", "2.5g", "85s", "1g 20s 50c", "500c", or bare gold "3.5") -> copper
function ns.ParseMoneyInput(raw)
	if type(raw) == "number" then
		return raw > 0 and math.floor(raw + 0.5) or nil
	end
	if type(raw) ~= "string" then return nil end
	local s = raw:lower():gsub(",", "."):match("^%s*(.-)%s*$")
	if s == "" then return nil end

	local hasUnit = false
	local totalCopper = 0
	for numStr, unit in s:gmatch("(%d+%.?%d*)%s*([gsc])") do
		local v = tonumber(numStr)
		if v then
			hasUnit = true
			if unit == "g" then
				totalCopper = totalCopper + v * 10000
			elseif unit == "s" then
				totalCopper = totalCopper + v * 100
			else
				totalCopper = totalCopper + v
			end
		end
	end
	if hasUnit then
		local rounded = math.floor(totalCopper + 0.5)
		return rounded > 0 and rounded or nil
	end

	-- Plain number without g/s/c suffix defaults to gold (e.g. "2.5" -> 2g 50s, "4" -> 4g)
	local plain = tonumber(s)
	if plain and plain > 0 then
		return math.floor(plain * 10000 + 0.5)
	end
	return nil
end

function ns.FormatMoneyEdit(copper)
	if not copper or copper <= 0 then return "" end
	local n = math.floor(copper + 0.5)
	local g = math.floor(n / 10000)
	local s = math.floor((n % 10000) / 100)
	local c = n % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

-- Caps wildly inflated single-listing troll prices against Snapshot market value so automated profit plans stay grounded
function ns.GetRealisticSaleUnitPrice(itemID, ahUnit)
	if not ahUnit or ahUnit <= 0 then return nil, false, nil, nil end
	local _, snapRec = ns.QueryLocalSnapshot and ns.QueryLocalSnapshot(itemID)
	local anchor = snapRec and (snapRec.marketValue or snapRec.historical) or nil
	if anchor and anchor >= 300 and ahUnit > anchor * 3.5 then
		local capped = math.floor(math.max(anchor * 2.25, math.min(ahUnit, anchor * 3.0)) + 0.5)
		return capped, true, nil, anchor
	end
	return ahUnit, false, nil, anchor
end

-- Evaluates why an item is a genuinely good product for buyers (BiS, Writ turn-in, Crate filler, or active regional sales)
function ns.EvaluateProductQuality(itemID, recipe, bisInfo, dailySold, saleRate)
	bisInfo = bisInfo or (recipe and ns.EvaluateBestInClass(recipe)) or { isBiS = false }
	local reasons = {}
	local score = 0
	if bisInfo and bisInfo.isBiS then
		score = score + 45
		reasons[#reasons + 1] = "|cffffd200Best: " .. (bisInfo.classLabel or "Class") .. "|r"
	end
	local writ = itemID and ns.WRIT_BY_REQ_ITEM[itemID] or nil
	if writ then
		score = score + 32
		reasons[#reasons + 1] = "|cff66ee66Writ Turn-In|r"
	end
	local crateEntry = itemID and ns.CRATE_BY_BUNDLE_ITEM[itemID] or nil
	if crateEntry then
		score = score + 26
		reasons[#reasons + 1] = "|cff66ccffCrate Mat|r"
	end
	if (dailySold or 0) >= 2.0 then
		score = score + 28
		reasons[#reasons + 1] = string.format("|cff55ff88High Buyer Vol (%.1f/d)|r", dailySold)
	elseif (dailySold or 0) >= 0.4 or ((dailySold or 0) >= 0.15 and (saleRate or 0) >= 0.08) then
		score = score + 16
		reasons[#reasons + 1] = string.format("|cff99ee99Active Buyers (%.1f/d)|r", dailySold or 0)
	end
	local isGood = score > 0
	local primaryLabel = reasons[1] or "|cff888888Niche / Low Vol|r"
	local fullLabel = (#reasons > 0) and table.concat(reasons, " · ") or "|cff888888Low Regional Demand|r"
	return isGood, score, primaryLabel, fullLabel, (writ ~= nil), (crateEntry ~= nil)
end

-- Deduplicated catalog of all tradeable craftable items with smart sub-craft pricing
local function collectEvaluatedCraftCandidates(opts)
	opts = opts or {}
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.knownRecipesOnly and "known" or (opts.unlockFilter or "all")
	local craftableFilter = opts.craftableFilter or "all"
	local merchantOnly = (opts.merchantVendorOnly or opts.sourceFilter == "camp") and true or false
	local sourceFilter = opts.sourceFilter or "all"
	local recipeSources = opts.recipeSources
	local applyAHCut = (opts.applyAHCut ~= false)
	local subMode = opts.subCraftMode or "smart"
	local subOverrides = opts.subCraftOverrides
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()

	local ec = ns._evalCache
	local candSig
	if ec then
		candSig = table.concat({
			needle,
			profFilter,
			unlockFilter,
			craftableFilter,
			merchantOnly and "1" or "0",
			sourceFilter,
			serializeMapSig(recipeSources),
			applyAHCut and "1" or "0",
			subMode,
			serializeMapSig(subOverrides),
			serializeMapSig(profMap),
			tostring(repState and repState.standing or 4),
			tostring(repState and repState.factionsDigest or ""),
			(ns.IsAllCharsCraftableActive and ns.IsAllCharsCraftableActive(opts)) and "1" or "0",
		}, "|")
		local hit = ec.candidates[candSig]
		if hit then
			return hit[1], hit[2], hit[3]
		end
	end

	local byItemID = {}
	for idx, rec in ipairs(ns.RECIPES or {}) do
		local id = rec.outputItemID
		if id and id > 0 then
			local sellable = ns.IsItemSellable(id, rec.sellable, rec.isEnchant)
			local srcOk
			if ns.MatchesRecipeSourceFilter then
				srcOk = ns.MatchesRecipeSourceFilter(rec, recipeSources, merchantOnly, sourceFilter)
			else
				srcOk = (not merchantOnly or rec.source == "camp")
			end
			if sellable and srcOk then
				local unlock = ns.EvaluateUnlock(rec.prof, rec.skill, rec.rep, rec.favorCost, rec, profMap, repState)
				if ns.MatchesGlobalFilters(rec.prof, unlock, profFilter, unlockFilter) then
					local craftAbility = ns.EvaluateCraftAbility(rec, profMap, repState)
					if ns.MatchesCraftableFilter(craftAbility, craftableFilter) then
						local dispName = ns.GetRecipeDisplayName(rec)
						local pObj = ns.PROF_BY_KEY[rec.prof]
						local profLabel = pObj and pObj.label or rec.prof
						if needle == ""
							or dispName:lower():find(needle, 1, true)
							or ns.ItemName(id):lower():find(needle, 1, true)
							or (rec.recipeName and rec.recipeName:lower():find(needle, 1, true))
							or rec.prof:lower():find(needle, 1, true) then

							local reagents = ns.ResolveRecipeReagents(rec)
							local craftCost, breakdown, craftSrc, directCost, usedSub = ns.ComputeSmartCraftCost(
								reagents, rec.numMade or 1, id, {
									parentProf = rec.prof,
									profMap = profMap,
									subCraftMode = subMode,
									subCraftOverrides = subOverrides,
								}
							)
							if craftCost ~= nil then
								local candKey = (type(rec.name) == "string" and rec.name:find("^Transmute:") and rec.spellID)
									and ("spell:" .. tostring(rec.spellID)) or id
								local prev = byItemID[candKey]
								-- Prefer recipe the player already knows, or cheaper craft cost
								local better = (not prev)
									or (craftAbility.ableToCraft and not prev.craftAbility.ableToCraft)
									or (craftAbility.ableToCraft == prev.craftAbility.ableToCraft and craftCost < prev.craftCost)
								if better then
									local reqRep, repSort, repLabel, repFactionName, repMet = ns.BuildRecipeRepFields(rec, repState, unlock)
									byItemID[candKey] = {
										idx = idx,
										itemID = id,
										spreadQueueKey = candKey,
										recipe = rec,
										name = dispName,
										icon = ns.ItemIcon(id, ns.QUESTION_ICON),
										prof = rec.prof,
										profLabel = profLabel,
										profSkillLabel = profLabel .. " " .. tostring(rec.skill or 1),
										skill = rec.skill or 1,
										rep = rec.rep or 0,
										reqRep = reqRep,
										repSort = repSort,
										repLabel = repLabel,
										repFactionName = repFactionName,
										repMet = repMet,
										favorCost = rec.favorCost or 0,
										source = rec.source,
										numMade = math.max(1, rec.numMade or 1),
										unlock = unlock,
										craftAbility = craftAbility,
										canCraft = craftAbility.ableToCraft,
										canCraftSort = craftAbility.sortScore,
										bisInfo = ns.EvaluateBestInClass(rec),
										craftCost = craftCost,
										craftBreakdown = breakdown,
										craftSource = craftSrc,
										usedSubCraft = usedSub,
										directCraftCost = directCost,
										subSavings = (usedSub and directCost and directCost > craftCost) and (directCost - craftCost) or 0,
										applyAHCut = applyAHCut,
									}
								end
							end
						end
					end
				end
			end
		end
	end
	if ec and candSig then
		ec.candidates[candSig] = { byItemID, profMap, repState }
	end
	return byItemID, profMap, repState
end

-- Returns daily sales velocity via ns.GetDailySold (Snapshot hourly velocity or Live AH local velocity),
-- with direct snapshot velocity and Live AH MarketScan.GetLocalVelocity fallbacks.
local function getDailySoldWithSnapshotFallback(itemID)
	local sold = ns.GetDailySold and ns.GetDailySold(itemID) or nil
	if sold ~= nil then return sold end
	local pricing = ns.Pricing
	if pricing and type(pricing.GetItemSnapshotVelocity) == "function" then
		local snapVel = pricing.GetItemSnapshotVelocity(itemID)
		if snapVel and type(snapVel.obsHours) == "number" and snapVel.obsHours >= 3
			and type(snapVel.estDailySold) == "number" and snapVel.estDailySold >= 0 then
			return snapVel.estDailySold
		end
	end
	local ms = ns.MarketScan
	if ms and type(ms.GetLocalVelocity) == "function" then
		local econ = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo()
		local econKey = econ and econ.effectiveKey or nil
		local ok, vel = pcall(ms.GetLocalVelocity, itemID, econKey)
		if ok and type(vel) == "table" and (tonumber(vel.scanPairs) or 0) >= 2
			and type(vel.clearsPerDay) == "number" and vel.clearsPerDay >= 0 then
			return vel.clearsPerDay
		end
	end
	return nil
end

-- 9A. Profit Spread: Highest Sellers (Guaranteed Turnover) + Diversified Daily Expected Profit
function ns.BuildProfitSpreadRows(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local applyAHCut = (opts.applyAHCut ~= false)
	local spreadCount = math.max(1, tonumber(opts.spreadCount) or 8)
	local diversifyProfs = (opts.diversifyProfs ~= false)
	local demandFilter = opts.demandFilter or "all"
	local spreadQueue = opts.spreadQueue or (MerchantMasterDB and MerchantMasterDB.spreadQueue) or nil

	local byItemID, profMap = collectEvaluatedCraftCandidates(opts)
	local customPrices = opts.outlierPrices or (MerchantMasterDB and MerchantMasterDB.outlierPrices) or nil
	local rows = {}
	local velocityCount = 0

	for _, cand in pairs(byItemID) do
		local id = cand.itemID
		local bisInfo = cand.bisInfo or ns.EvaluateBestInClass(cand.recipe)
		local listed = ns.GetNumListed(id)
		local rawAH, rawSrc = ns.GetItemMarketPrice(id)
		local isUnlisted = (listed == 0) or (rawAH == nil and listed == nil)
		local customPrice = customPrices and tonumber(customPrices[id]) or nil
		local ahPrice, ahSource, isCustomPrice = nil, nil, false
		if isUnlisted then
			if customPrice and customPrice > 0 then
				ahPrice = math.floor(customPrice + 0.5)
				ahSource = "Custom Price"
				isCustomPrice = true
			end
		else
			ahPrice, ahSource = rawAH, rawSrc
		end
		local dailySold = getDailySoldWithSnapshotFallback(id)
		if dailySold ~= nil then
			velocityCount = velocityCount + 1
		end
		local demand = ns.EvaluateMarketDemand(listed, dailySold, true)
		local realGross, isCapped, saleRate, saleAvg = ns.GetRealisticSaleUnitPrice(id, ahPrice)

		if (not opts.bisOnly or (bisInfo and bisInfo.isBiS)) and realGross and dailySold and dailySold >= 0.20 and ns.MatchesDemandFilter(demand, demandFilter) then
			local lastKnownPrice, lastKnownSource = ns.GetLastKnownAHPrice(id)
			local netLive = applyAHCut and math.floor(ahPrice * 0.95 + 0.5) or ahPrice
			local netReal = applyAHCut and math.floor(realGross * 0.95 + 0.5) or realGross
			local dep12h = ns.GetAHListingDeposit(id, 1, 1) or 0
			local failProb = math.max(0, math.min(0.65, 1 - (saleRate or 0.35)))
			local realizedUnitProfit = netReal - cand.craftCost - math.floor(dep12h * failProb + 0.5)
			local liveUnitProfit = netLive - cand.craftCost

			if realizedUnitProfit > 0 and liveUnitProfit > 0 then
				-- Market capture share scales with demand heat & prevents flooding a single item
				local captureShare
				if listed == 0 then
					captureShare = 0.42
				elseif listed ~= nil then
					local ratio = dailySold / math.max(1, listed)
					if ratio >= 1.0 then
						captureShare = 0.40
					elseif ratio >= 0.20 then
						captureShare = 0.30
					elseif ratio >= 0.05 then
						captureShare = 0.18
					else
						captureShare = 0.07
					end
				else
					captureShare = 0.22
				end
				if saleRate and saleRate >= 0.35 then
					captureShare = math.min(0.50, captureShare * 1.12)
				end

				local rawUnits = dailySold * captureShare
				local recDailyQty = math.max(1, math.min(40, math.floor(rawUnits + 0.65)))
				local expectedDailySales = math.min(dailySold * 0.60, rawUnits, recDailyQty)
				local cdInfo = ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(cand.recipe) or nil
				if cdInfo then
					if (cdInfo.nominalSeconds or 0) >= 82800 then
						recDailyQty = 1
					else
						recDailyQty = math.max(1, math.min(recDailyQty, math.floor(cdInfo.maxPerDay * (cand.numMade or 1))))
					end
					expectedDailySales = math.min(expectedDailySales, cdInfo.maxPerDay * cand.numMade)
				end
				local expectedDailyProfit = math.max(1, math.floor(realizedUnitProfit * expectedDailySales + 0.5))
				local marginPct = cand.craftCost > 0 and ((realizedUnitProfit / cand.craftCost) * 100) or 999

				local isGood, goodScore, goodShort, goodFull, isWritItem, isCrateMat =
					ns.EvaluateProductQuality(id, cand.recipe, cand.bisInfo, dailySold, saleRate)

				local queueKey = cand.spreadQueueKey
				if queueKey ~= id and spreadQueue and spreadQueue[id] and not byItemID[id]
					and ns.ResolveSpreadQueueRecipe(id, profMap) == cand.recipe then
					queueKey = id
				end
				local queuedQty = (spreadQueue and tonumber(spreadQueue[queueKey])) or 0
				local row = {
					itemID = id,
					recipe = cand.recipe,
					name = cand.name,
					icon = cand.icon,
					prof = cand.prof,
					profLabel = cand.profLabel,
					profSkillLabel = cand.profSkillLabel,
					skill = cand.skill,
					source = cand.source,
					favorCost = cand.favorCost,
					reqRep = cand.reqRep,
					repSort = cand.repSort,
					repLabel = cand.repLabel,
					repFactionName = cand.repFactionName,
					repMet = cand.repMet,
					numMade = cand.numMade,
					unlock = cand.unlock,
					craftAbility = cand.craftAbility,
					canCraft = cand.canCraft,
					canCraftSort = cand.canCraftSort,
					bisInfo = bisInfo,
					bisSort = (bisInfo and bisInfo.hasEval and bisInfo.sortScore) or nil,
					demand = demand,
					demandSort = demand.demandScore,
					listed = listed,
					listedSort = (listed ~= nil) and listed or 999999,
					dailySold = dailySold,
					saleRate = saleRate,
					saleAvg = saleAvg,
					craftCost = cand.craftCost,
					craftBreakdown = cand.craftBreakdown,
					usedSubCraft = cand.usedSubCraft,
					directCraftCost = cand.directCraftCost,
					subSavings = cand.subSavings,
					ahPrice = ahPrice,
					ahValue = ahPrice,
					ahSource = ahSource,
					isUnlisted = isUnlisted,
					isCustomPrice = isCustomPrice,
					lastKnownPrice = lastKnownPrice,
					lastKnownSource = lastKnownSource,
					realisticPrice = realGross,
					isPriceCapped = isCapped,
					profit = liveUnitProfit,
					realizedProfit = realizedUnitProfit,
					marginPct = marginPct,
					recDailyQty = recDailyQty,
					expectedDailySales = expectedDailySales,
					expectedDailyProfit = expectedDailyProfit,
					dailyCraftSpend = cand.craftCost * recDailyQty,
					isGoodProduct = isGood,
					goodScore = goodScore,
					goodShort = goodShort,
					goodFull = goodFull,
					isWritItem = isWritItem,
					isCrateMat = isCrateMat,
					sellable = true,
					queuedQty = queuedQty,
					spreadQueueKey = queueKey,
					inSpreadPlan = false,
					cdInfo = cdInfo,
					onCooldown = cdInfo and cdInfo.onCooldown or false,
					cdAvailable = cdInfo and cdInfo.available or nil,
				}
				rows[#rows + 1] = row
			end
		end
	end

	-- Rank by Expected Profit / Day (tie-breaker: higher dailySold for guaranteed velocity)
	table.sort(rows, function(a, b)
		if a.expectedDailyProfit ~= b.expectedDailyProfit then
			return a.expectedDailyProfit > b.expectedDailyProfit
		end
		return (a.dailySold or 0) > (b.dailySold or 0)
	end)

	-- Select diversified Top N Spread Plan
	local planRows = {}
	local perProfCount, usedCDGroups, usedItemIDs = {}, {}, {}
	local maxPerProf = diversifyProfs and math.max(3, math.ceil(spreadCount * 0.5)) or 999
	for _, r in ipairs(rows) do
		local grp = r.cdInfo and r.cdInfo.sharedGroup
		if #planRows < spreadCount and not usedItemIDs[r.itemID] and r.onCooldown ~= true and (not grp or not usedCDGroups[grp]) then
			local pc = perProfCount[r.prof] or 0
			if pc < maxPerProf then
				r.inSpreadPlan = true
				r.spreadRank = #planRows + 1
				perProfCount[r.prof] = pc + 1
				usedItemIDs[r.itemID] = true
				if grp then usedCDGroups[grp] = true end
				planRows[#planRows + 1] = r
			end
		end
	end
	-- If diversification left slots open, backfill remaining top rows
	if #planRows < spreadCount then
		for _, r in ipairs(rows) do
			if #planRows >= spreadCount then break end
			local grp = r.cdInfo and r.cdInfo.sharedGroup
			if not usedItemIDs[r.itemID] and r.onCooldown ~= true and (not grp or not usedCDGroups[grp]) then
				r.inSpreadPlan = true
				r.spreadRank = #planRows + 1
				usedItemIDs[r.itemID] = true
				if grp then usedCDGroups[grp] = true end
				planRows[#planRows + 1] = r
			end
		end
	end

	local totalExpectedDailyProfit, totalDailySpend, totalDailySales = 0, 0, 0
	for _, pr in ipairs(planRows) do
		totalExpectedDailyProfit = totalExpectedDailyProfit + (pr.expectedDailyProfit or 0)
		totalDailySpend = totalDailySpend + (pr.dailyCraftSpend or 0)
		totalDailySales = totalDailySales + (pr.expectedDailySales or 0)
	end

	local hasSnapshots = (ns.HasSnapshots and ns.HasSnapshots()) == true
	local velocitySource = hasSnapshots and "snapshot" or "live_ah"
	local emptyReason, emptyMessage = nil, nil
	if #rows == 0 and not hasSnapshots and velocityCount == 0 then
		local econ = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo()
		local econKey = econ and econ.effectiveKey or nil
		local db = (ns.GetDB and ns.GetDB()) or _G.MerchantMasterDB
		local ahTbl = db and type(db.ahPrices) == "table" and econKey and db.ahPrices[econKey] or nil
		local histTbl = db and type(db.ahHistory) == "table" and econKey and db.ahHistory[econKey] or nil
		local hasAnyScan = (type(ahTbl) == "table" and type(ahTbl._scannedAt) == "number" and ahTbl._scannedAt > 0)
			or (type(histTbl) == "table" and next(histTbl) ~= nil)
		if not hasAnyScan then
			emptyReason = "no_ah_scan"
			emptyMessage = "No AH scan yet. Open an Auctioneer and click Scan AH, then scan again 15+ minutes later to estimate daily sales."
		else
			emptyReason = "insufficient_live_history"
			emptyMessage = "Live AH velocity warming up: scan the AH at least twice (15+ minutes apart) to measure daily sales for Profit Spread."
		end
	end

	local summary = {
		planRows = planRows,
		planCount = #planRows,
		totalMatched = #rows,
		totalExpectedDailyProfit = totalExpectedDailyProfit,
		totalDailySpend = totalDailySpend,
		totalDailySales = totalDailySales,
		roiPct = totalDailySpend > 0 and ((totalExpectedDailyProfit / totalDailySpend) * 100) or 0,
		bestRow = rows[1],
		profMap = profMap,
		velocitySource = velocitySource,
		velocityCount = velocityCount,
		emptyReason = emptyReason,
		emptyMessage = emptyMessage,
		needsMoreScans = (emptyReason == "no_ah_scan" or emptyReason == "insufficient_live_history"),
	}

	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	return rows, summary
end

function ns.BuildSpreadShoppingList(spreadRows, summary, opts)
	opts = opts or {}
	local spreadQueue = opts.spreadQueue or (MerchantMasterDB and MerchantMasterDB.spreadQueue) or nil
	local hasCustomQueue = false
	if spreadQueue then
		for _, q in pairs(spreadQueue) do
			if type(q) == "number" and q > 0 then hasCustomQueue = true; break end
		end
	end

	local targets = {}
	local demandList = {}
	local estProfit, estDailyProfit = 0, 0

	if hasCustomQueue then
		for _, r in ipairs(spreadRows or {}) do
			local q = tonumber(spreadQueue[r.spreadQueueKey or r.itemID]) or 0
			if q > 0 then
				targets[#targets + 1] = { row = r, qty = q }
			end
		end
	else
		for _, r in ipairs((summary and summary.planRows) or {}) do
			targets[#targets + 1] = { row = r, qty = math.max(1, r.recDailyQty or 1) }
		end
	end

	for _, t in ipairs(targets) do
		local r = t.row
		local batches = math.ceil(t.qty / math.max(1, r.numMade or 1))
		local produced = batches * math.max(1, r.numMade or 1)
		estProfit = estProfit + ((r.realizedProfit or r.profit or 0) * produced)
		estDailyProfit = estDailyProfit + (r.expectedDailyProfit or 0)
		for _, rg in ipairs(r.craftBreakdown or {}) do
			demandList[#demandList + 1] = {
				itemID = rg.itemID,
				qty = rg.qty * batches,
				role = "Reagent",
				parentProf = r.prof,
			}
		end
	end

	local shoppingRows, totalSpend = ns.BuildShoppingListRows(demandList, opts)
	return {
		hasCustomQueue = hasCustomQueue,
		targets = targets,
		shoppingList = shoppingRows,
		totalCraftCost = totalSpend,
		estBatchProfit = estProfit,
		estDailyProfit = estDailyProfit,
	}
end

-- 9B. Outliers: Monopolies (1-2 listed) & Unlisted (0 listed) Good Products + Set Your Own Price
function ns.BuildOutlierRows(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local applyAHCut = (opts.applyAHCut ~= false)
	local outlierScope = opts.outlierScope or "monopoly" -- "unlisted" (0) | "monopoly" (0..2) | "thin" (0..4)
	local qualityFilter = opts.outlierQuality or "good"  -- "good" | "bis" | "all"
	local customPrices = opts.outlierPrices or (MerchantMasterDB and MerchantMasterDB.outlierPrices) or {}

	local maxListed = (outlierScope == "unlisted") and 0 or ((outlierScope == "thin") and 4 or 2)
	local byItemID = collectEvaluatedCraftCandidates(opts)
	local rows = {}
	local unlistedCount, monopolyCount, customCount, bisCount = 0, 0, 0, 0

	for _, cand in pairs(byItemID) do
		local id = cand.itemID
		local listed = ns.GetNumListed(id)
		local dailySold = getDailySoldWithSnapshotFallback(id)
		local saleRate, saleAvg = nil, nil
		local ahPrice, ahSource = ns.GetItemMarketPrice(id)

		-- Qualifies as an Outlier when AH has 0..maxListed items, OR no local AH price exists while buyers exist
		local isOutlierStock = false
		local effectiveListed = listed
		if listed ~= nil and listed <= maxListed then
			isOutlierStock = true
		elseif listed == nil and ahPrice == nil and (dailySold or 0) > 0 then
			isOutlierStock = true
			effectiveListed = 0
		end

		if isOutlierStock then
			local isGood, goodScore, goodShort, goodFull, isWritItem, isCrateMat =
				ns.EvaluateProductQuality(id, cand.recipe, cand.bisInfo, dailySold, saleRate)

			local passQuality = (qualityFilter == "all")
				or (qualityFilter == "good" and isGood)
				or (qualityFilter == "bis" and cand.bisInfo and cand.bisInfo.isBiS)

			if passQuality then
				local isUnlisted = (effectiveListed == 0)
				local lastKnownPrice, lastKnownSource = ns.GetLastKnownAHPrice(id)
				local activeAHPrice = (not isUnlisted) and ahPrice or nil
				local activeAHSource = (not isUnlisted) and ahSource or nil
				local demand = ns.EvaluateMarketDemand(effectiveListed, dailySold, true)
				local refAnchor = math.max(activeAHPrice or 0, lastKnownPrice or 0, saleAvg or 0)
				local costAnchor = math.max(cand.craftCost + 500, math.floor(cand.craftCost * 2.35 + 0.5))
				local mktAnchor = refAnchor > 0 and math.floor(refAnchor * (isUnlisted and 1.35 or 1.15) + 0.5) or 0
				local rawSuggested = math.max(costAnchor, mktAnchor)
				-- Clean rounding to nearest silver when >= 20s
				if rawSuggested >= 2000 then
					rawSuggested = math.floor((rawSuggested + 50) / 100) * 100
				end

				local userPrice = tonumber(customPrices[id])
				local isCustom = (userPrice ~= nil and userPrice > 0)
				local targetPrice = isCustom and math.floor(userPrice + 0.5) or rawSuggested
				local netTarget = applyAHCut and math.floor(targetPrice * 0.95 + 0.5) or targetPrice
				local profit = netTarget - cand.craftCost
				local marginPct = cand.craftCost > 0 and ((profit / cand.craftCost) * 100) or 999

				-- Conservative daily unit realization on monopoly/unlisted items
				local estDailyUnits
				if dailySold and dailySold > 0 then
					estDailyUnits = math.min(8, math.max(0.35, dailySold * (isUnlisted and 0.45 or 0.35)))
				else
					estDailyUnits = cand.bisInfo.isBiS and 0.75 or 0.35
				end
				local cdInfo = ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(cand.recipe) or nil
				if cdInfo then
					estDailyUnits = math.min(estDailyUnits, cdInfo.maxPerDay * cand.numMade)
				end
				local expectedDailyProfit = (profit > 0) and math.floor(profit * estDailyUnits + 0.5) or 0

				if isUnlisted then unlistedCount = unlistedCount + 1 end
				if effectiveListed ~= nil and effectiveListed <= 2 then monopolyCount = monopolyCount + 1 end
				if isCustom then customCount = customCount + 1 end
				if cand.bisInfo and cand.bisInfo.isBiS then bisCount = bisCount + 1 end

				local outlierScore = expectedDailyProfit + (goodScore * 200) + (isUnlisted and 2500 or 1000)

				rows[#rows + 1] = {
					itemID = id,
					recipe = cand.recipe,
					name = cand.name,
					icon = cand.icon,
					prof = cand.prof,
					profLabel = cand.profLabel,
					profSkillLabel = cand.profSkillLabel,
					skill = cand.skill,
					source = cand.source,
					favorCost = cand.favorCost,
					reqRep = cand.reqRep,
					repSort = cand.repSort,
					repLabel = cand.repLabel,
					repFactionName = cand.repFactionName,
					repMet = cand.repMet,
					numMade = cand.numMade,
					unlock = cand.unlock,
					craftAbility = cand.craftAbility,
					canCraft = cand.canCraft,
					canCraftSort = cand.canCraftSort,
					bisInfo = cand.bisInfo,
					bisSort = cand.bisInfo.sortScore,
					demand = demand,
					demandSort = demand.demandScore,
					listed = effectiveListed,
					listedSort = (effectiveListed ~= nil) and effectiveListed or 999,
					isUnlisted = isUnlisted,
					dailySold = dailySold,
					saleRate = saleRate,
					saleAvg = saleAvg,
					craftCost = cand.craftCost,
					craftBreakdown = cand.craftBreakdown,
					usedSubCraft = cand.usedSubCraft,
					directCraftCost = cand.directCraftCost,
					subSavings = cand.subSavings,
					ahPrice = activeAHPrice,
					ahValue = targetPrice,
					ahSource = activeAHSource,
					lastKnownPrice = lastKnownPrice,
					lastKnownSource = lastKnownSource,
					lastKnownSort = lastKnownPrice,
					suggestedPrice = rawSuggested,
					targetPrice = targetPrice,
					isCustomPrice = isCustom,
					profit = profit,
					marginPct = marginPct,
					estDailyUnits = estDailyUnits,
					expectedDailyProfit = expectedDailyProfit,
					isGoodProduct = isGood,
					goodScore = goodScore,
					goodShort = goodShort,
					goodFull = goodFull,
					isWritItem = isWritItem,
					isCrateMat = isCrateMat,
					outlierScore = outlierScore,
					sellable = true,
					cdInfo = cdInfo,
					onCooldown = cdInfo and cdInfo.onCooldown or false,
					cdAvailable = cdInfo and cdInfo.available or nil,
				}
			end
		end
	end

	table.sort(rows, function(a, b)
		if a.outlierScore ~= b.outlierScore then
			return a.outlierScore > b.outlierScore
		end
		return (a.profit or 0) > (b.profit or 0)
	end)

	local summary = {
		totalMatched = #rows,
		unlistedCount = unlistedCount,
		monopolyCount = monopolyCount,
		customCount = customCount,
		bisCount = bisCount,
		bestRow = rows[1],
	}

	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	return rows, summary
end

-- 9C. Executive Profit-Maximizing Dashboard: Top 5 Guaranteed-Sale Crafts + Top 5 Outliers + Advice Shopping List
function ns.BuildDashboardInsights(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts and ns.PushEvalOpts(opts)
	local rawScope = opts.dashboardScope or "smart" -- "smart" | "known" | "able" | "potential" | "all"
	local forceKnown = (opts.knownRecipesOnly == true) or (opts.unlockFilter == "known") or (rawScope == "known")
	local scope = forceKnown and "known" or rawScope
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()
	local hasAnyPlayerProf = (next(profMap) ~= nil)

	local effProfFilter = opts.profFilter or "all"
	local effUnlockFilter = opts.unlockFilter or "all"
	local effCraftableFilter = "all"
	if forceKnown then
		effUnlockFilter = "known"
		effCraftableFilter = "known"
	elseif scope == "able" then
		effCraftableFilter = "yes"
	elseif scope == "potential" then
		if effProfFilter == "all" and hasAnyPlayerProf then effProfFilter = "mine_profs" end
		if effUnlockFilter == "all" then effUnlockFilter = "applies" end
	end

	local baseOpts = {
		profFilter = effProfFilter,
		unlockFilter = effUnlockFilter,
		craftableFilter = effCraftableFilter,
		merchantVendorOnly = opts.merchantVendorOnly,
		recipeSources = opts.recipeSources,
		applyAHCut = (opts.applyAHCut ~= false),
		subCraftMode = opts.subCraftMode or "smart",
		subCraftOverrides = opts.subCraftOverrides,
		outlierPrices = opts.outlierPrices,
		profMap = profMap,
		repState = repState,
		spreadCount = 12,
	}

	local spreadRows, spreadSummary = ns.BuildProfitSpreadRows(baseOpts)
	local outlierRows = ns.BuildOutlierRows({
		profFilter = baseOpts.profFilter,
		unlockFilter = baseOpts.unlockFilter,
		craftableFilter = effCraftableFilter,
		merchantVendorOnly = baseOpts.merchantVendorOnly,
		recipeSources = baseOpts.recipeSources,
		applyAHCut = baseOpts.applyAHCut,
		subCraftMode = baseOpts.subCraftMode,
		subCraftOverrides = baseOpts.subCraftOverrides,
		outlierPrices = baseOpts.outlierPrices,
		outlierScope = "monopoly",
		outlierQuality = "good",
		profMap = profMap,
		repState = repState,
	})

	-- Pick Top 5 Crafts: in "smart" mode, prioritize Known / Able crafts first, then player's learned professions (Potential)
	local topCrafts, usedCraftIDs, usedCDGroups = {}, {}, {}
	local function canRecommendCraft(r)
		local g = r.cdInfo and r.cdInfo.sharedGroup
		return r.onCooldown ~= true and (not g or not usedCDGroups[g])
	end
	local function takeCDGroup(r)
		local g = r and r.cdInfo and r.cdInfo.sharedGroup
		if g then usedCDGroups[g] = true end
	end
	if scope == "smart" then
		for _, r in ipairs(spreadRows) do
			if #topCrafts >= 5 then break end
			if not usedCraftIDs[r.itemID] and canRecommendCraft(r) and (r.canCraft or (r.unlock and r.unlock.known)) then
				r.adviceBadge = (r.unlock and r.unlock.known and r.canCraft) and "|cff33ff66Known · Ready|r"
					or (r.canCraft and "|cff33ff66Ready Now|r" or "|cff66ee88Known Recipe|r")
				topCrafts[#topCrafts + 1] = r
				usedCraftIDs[r.itemID] = true
				takeCDGroup(r)
			end
		end
		if hasAnyPlayerProf and #topCrafts < 5 then
			for _, r in ipairs(spreadRows) do
				if #topCrafts >= 5 then break end
				if canRecommendCraft(r) and not usedCraftIDs[r.itemID] and profMap[r.prof] then
					r.adviceBadge = r.craftAbility and r.craftAbility.cellText or "|cff66eeffYour Potential|r"
					topCrafts[#topCrafts + 1] = r
					usedCraftIDs[r.itemID] = true
					takeCDGroup(r)
				end
			end
		end
	end
	for _, r in ipairs(spreadRows) do
		if #topCrafts >= 5 then break end
	if canRecommendCraft(r) and not usedCraftIDs[r.itemID] and (scope ~= "smart" or not hasAnyPlayerProf or effProfFilter ~= "all" or profMap[r.prof]) then
			r.adviceBadge = (r.unlock and r.unlock.known and r.canCraft) and "|cff33ff66Known · Ready|r"
				or (r.canCraft and "|cff33ff66Ready Now|r" or (r.craftAbility and r.craftAbility.cellText or "|cffffd200Potential|r"))
			topCrafts[#topCrafts + 1] = r
			usedCraftIDs[r.itemID] = true
			takeCDGroup(r)
		end
	end

	-- Pick Top 5 Outliers (excluding items already in Top 5 Spread so all 10 recommendations are distinct!)
	local topOutliers, usedOutlierIDs = {}, {}
	local hasBestKnownFallback = false
	if scope == "smart" then
		for _, r in ipairs(outlierRows) do
			if #topOutliers >= 5 then break end
			if not usedCraftIDs[r.itemID] and not usedOutlierIDs[r.itemID] and canRecommendCraft(r)
				and (r.canCraft or (r.unlock and r.unlock.known) or (hasAnyPlayerProf and profMap[r.prof])) and (r.profit or 0) > 0 then
				topOutliers[#topOutliers + 1] = r
				usedOutlierIDs[r.itemID] = true
				takeCDGroup(r)
			end
		end
	end
	for _, r in ipairs(outlierRows) do
		if #topOutliers >= 5 then break end
	if not usedCraftIDs[r.itemID] and not usedOutlierIDs[r.itemID] and canRecommendCraft(r) and (r.profit or 0) > 0
			and (scope ~= "smart" or not hasAnyPlayerProf or effProfFilter ~= "all" or profMap[r.prof]) then
			topOutliers[#topOutliers + 1] = r
			usedOutlierIDs[r.itemID] = true
			takeCDGroup(r)
		end
	end

	-- When Known Recipes (or Able Now) is active, never leave the 5+5 Dashboard slots empty just because
	-- strict endgame turnover (>=0.20/day) or monopoly (0-2 listed) thresholds filter out learned recipes.
	if (forceKnown or scope == "able") and (#topCrafts < 5 or #topOutliers < 5) then
		if #topOutliers < 5 then
			local thinOutliers = ns.BuildOutlierRows({
				profFilter = baseOpts.profFilter,
				unlockFilter = baseOpts.unlockFilter,
				craftableFilter = effCraftableFilter,
				merchantVendorOnly = baseOpts.merchantVendorOnly,
				recipeSources = baseOpts.recipeSources,
				applyAHCut = baseOpts.applyAHCut,
				subCraftMode = baseOpts.subCraftMode,
				subCraftOverrides = baseOpts.subCraftOverrides,
				outlierPrices = baseOpts.outlierPrices,
				outlierScope = "thin",
				outlierQuality = "all",
				profMap = profMap,
				repState = repState,
			})
			for _, r in ipairs(thinOutliers) do
				if #topOutliers >= 5 then break end
				if not usedCraftIDs[r.itemID] and not usedOutlierIDs[r.itemID] and canRecommendCraft(r) and (r.profit or 0) > 0 then
					topOutliers[#topOutliers + 1] = r
					usedOutlierIDs[r.itemID] = true
					takeCDGroup(r)
				end
			end
		end

		if #topCrafts < 5 or #topOutliers < 5 then
			local candByID = collectEvaluatedCraftCandidates(baseOpts)
			local knownPool = {}
			for _, cand in pairs(candByID) do
				local id = cand.itemID
				local listed = ns.GetNumListed(id)
				local dailySold = getDailySoldWithSnapshotFallback(id)
				local demand = ns.EvaluateMarketDemand(listed, dailySold, true)
				local val = ns.ResolveOutputSaleValuation(
					id,
					listed,
					true,
					cand.craftCost,
					baseOpts.applyAHCut,
					baseOpts.outlierPrices
				)
				local saleRate = nil
				if val and not val.usedVendorFloor then
					local saleUnit = val.unitAH or val.ahValue
					local realistic = ns.GetRealisticSaleUnitPrice(id, saleUnit)
					if realistic and realistic > 0 then
						val.ahValue = realistic
						val.profit = (baseOpts.applyAHCut and math.floor(realistic * 0.95 + 0.5) or realistic) - cand.craftCost
						val.marginPct = cand.craftCost > 0 and (val.profit / cand.craftCost * 100) or 999
					else val.profit = nil end
				end
				if val and not val.usedVendorFloor and val.profit and val.profit > 0 and val.ahValue and val.ahValue > 0 then
					local isGood, goodScore, goodShort, goodFull, isWritItem, isCrateMat =
						ns.EvaluateProductQuality(id, cand.recipe, cand.bisInfo, dailySold, saleRate)
					local estDailyUnits = (dailySold and dailySold > 0)
						and math.min(10, math.max(0.25, dailySold * 0.20))
						or 0
					local recDailyQty = math.max(1, math.min(10, math.floor(estDailyUnits + 0.65)))
					local cdInfo = ns.GetRecipeCooldownInfo and ns.GetRecipeCooldownInfo(cand.recipe) or nil
					if cdInfo then
						if (cdInfo.nominalSeconds or 0) >= 82800 then
							recDailyQty = 1
						else
							recDailyQty = math.max(1, math.min(recDailyQty, math.floor(cdInfo.maxPerDay * (cand.numMade or 1))))
						end
						estDailyUnits = math.min(estDailyUnits, cdInfo.maxPerDay * cand.numMade)
					end
					local expectedDailyProfit = math.floor(val.profit * estDailyUnits + 0.5)
					local thinBonus = (listed ~= nil and listed <= 15) and math.floor(val.profit * 0.25) or 0
					local bestKnownScore = val.profit + thinBonus + (goodScore * 5)
					knownPool[#knownPool + 1] = {
						itemID = id,
						recipe = cand.recipe,
						name = cand.name,
						icon = cand.icon,
						prof = cand.prof,
						profLabel = cand.profLabel,
						profSkillLabel = cand.profSkillLabel,
						skill = cand.skill,
						source = cand.source,
						favorCost = cand.favorCost,
						reqRep = cand.reqRep,
						repSort = cand.repSort,
						repLabel = cand.repLabel,
						repFactionName = cand.repFactionName,
						repMet = cand.repMet,
						numMade = cand.numMade,
						unlock = cand.unlock,
						craftAbility = cand.craftAbility,
						canCraft = cand.canCraft,
						canCraftSort = cand.canCraftSort,
						bisInfo = cand.bisInfo,
						demand = demand,
						listed = listed,
						isUnlisted = val.isUnlisted,
						dailySold = dailySold,
						saleRate = saleRate,
						saleAvg = saleAvg,
						craftCost = cand.craftCost,
						craftBreakdown = cand.craftBreakdown,
						usedSubCraft = cand.usedSubCraft,
						directCraftCost = cand.directCraftCost,
						subSavings = cand.subSavings,
						ahPrice = val.ahValue,
						ahValue = val.ahValue,
						ahSource = val.ahSource,
						targetPrice = val.ahValue,
						suggestedPrice = val.ahValue,
						isCustomPrice = val.isCustomPrice,
						usedVendorFloor = val.usedVendorFloor,
						lastKnownPrice = val.lastKnownPrice,
						lastKnownSource = val.lastKnownSource,
						profit = val.profit,
						realizedProfit = val.profit,
						marginPct = val.marginPct,
						recDailyQty = recDailyQty,
						estDailyUnits = estDailyUnits,
						expectedDailyProfit = expectedDailyProfit,
						isGoodProduct = isGood,
						goodScore = goodScore,
						goodShort = isGood and goodShort or "|cff66ee88Best Known Margin|r",
						goodFull = isGood and goodFull or "Highest per-craft profit among your currently learned recipes",
						isWritItem = isWritItem,
						isCrateMat = isCrateMat,
						bestKnownScore = bestKnownScore,
						sellable = true,
						cdInfo = cdInfo,
						onCooldown = cdInfo and cdInfo.onCooldown or false,
						cdAvailable = cdInfo and cdInfo.available or nil,
					}
				end
			end

			if #topCrafts < 5 and #knownPool > 0 then
				table.sort(knownPool, function(a, b)
					if a.expectedDailyProfit ~= b.expectedDailyProfit then
						return a.expectedDailyProfit > b.expectedDailyProfit
					end
					if a.bestKnownScore ~= b.bestKnownScore then
						return a.bestKnownScore > b.bestKnownScore
					end
					return a.name < b.name
				end)
				for _, r in ipairs(knownPool) do
					if #topCrafts >= 5 then break end
					if canRecommendCraft(r) and not usedCraftIDs[r.itemID] and not usedOutlierIDs[r.itemID] then
						r.adviceBadge = (r.unlock and r.unlock.known and r.canCraft) and "|cff33ff66Known · Ready|r"
							or (r.canCraft and "|cff33ff66Ready Now|r" or "|cff66ee88Known Option|r")
						topCrafts[#topCrafts + 1] = r
						usedCraftIDs[r.itemID] = true
						takeCDGroup(r)
					end
				end
			end

			if #topOutliers < 5 and #knownPool > 0 then
				table.sort(knownPool, function(a, b)
					if (a.expectedDailyProfit > 0) ~= (b.expectedDailyProfit > 0) then return a.expectedDailyProfit > 0 end
					if a.bestKnownScore ~= b.bestKnownScore then
						return a.bestKnownScore > b.bestKnownScore
					end
					if a.profit ~= b.profit then
						return a.profit > b.profit
					end
					return a.name < b.name
				end)
				for _, r in ipairs(knownPool) do
					if #topOutliers >= 5 then break end
					if canRecommendCraft(r) and not usedCraftIDs[r.itemID] and not usedOutlierIDs[r.itemID] then
						r.isBestKnownOption = true
						hasBestKnownFallback = true
						topOutliers[#topOutliers + 1] = r
						usedOutlierIDs[r.itemID] = true
						takeCDGroup(r)
					end
				end
			end
		end
	end

	local spreadProfitPerDay, spreadSpend = 0, 0
	local demandList = {}
	for _, r in ipairs(topCrafts) do
		spreadProfitPerDay = spreadProfitPerDay + (r.expectedDailyProfit or 0)
		local qty = math.max(1, r.recDailyQty or 1)
		local batches = math.ceil(qty / math.max(1, r.numMade or 1))
		spreadSpend = spreadSpend + (r.craftCost * batches * math.max(1, r.numMade or 1))
		for _, rg in ipairs(r.craftBreakdown or {}) do
			demandList[#demandList + 1] = {
				itemID = rg.itemID,
				qty = rg.qty * batches,
				role = "Reagent",
				parentProf = r.prof,
			}
		end
	end

	local outlierProfitPerDay, outlierSpend = 0, 0
	for _, r in ipairs(topOutliers) do
		outlierProfitPerDay = outlierProfitPerDay + (r.expectedDailyProfit or 0)
		local qty = r.isBestKnownOption
			and math.max(1, r.recDailyQty or 1)
			or math.max(1, math.min(3, math.ceil(r.estDailyUnits or 1)))
		local batches = math.ceil(qty / math.max(1, r.numMade or 1))
		outlierSpend = outlierSpend + (r.craftCost * batches * math.max(1, r.numMade or 1))
		for _, rg in ipairs(r.craftBreakdown or {}) do
			demandList[#demandList + 1] = {
				itemID = rg.itemID,
				qty = rg.qty * batches,
				role = "Reagent",
				parentProf = r.prof,
			}
		end
	end

	-- Compute Can-Do (Known Recipes) vs Potential daily gold benchmarks so player sees both side by side!
	local knownProfitPerDay, knownPickCount = 0, 0
	local potentialProfitPerDay = 0
	if forceKnown then
		knownProfitPerDay = spreadProfitPerDay + outlierProfitPerDay
		knownPickCount = #topCrafts + #topOutliers
		local potProf = (opts.profFilter and opts.profFilter ~= "all") and opts.profFilter or (hasAnyPlayerProf and "mine_profs" or "all")
		local potSpread = ns.BuildProfitSpreadRows({
			profFilter = potProf,
			unlockFilter = "applies",
			merchantVendorOnly = baseOpts.merchantVendorOnly,
			applyAHCut = baseOpts.applyAHCut,
			subCraftMode = baseOpts.subCraftMode,
			subCraftOverrides = baseOpts.subCraftOverrides,
			outlierPrices = baseOpts.outlierPrices,
			profMap = profMap,
			repState = repState,
			spreadCount = 5,
		})
		local potOutliers = ns.BuildOutlierRows({
			profFilter = potProf,
			unlockFilter = "applies",
			merchantVendorOnly = baseOpts.merchantVendorOnly,
			applyAHCut = baseOpts.applyAHCut,
			subCraftMode = baseOpts.subCraftMode,
			subCraftOverrides = baseOpts.subCraftOverrides,
			outlierPrices = baseOpts.outlierPrices,
			outlierScope = "monopoly",
			outlierQuality = "good",
			profMap = profMap,
			repState = repState,
		})
		local seenPot = {}
		local psC = 0
		for _, r in ipairs(potSpread) do
			if psC >= 5 then break end
			psC = psC + 1
			seenPot[r.itemID] = true
			potentialProfitPerDay = potentialProfitPerDay + (r.expectedDailyProfit or 0)
		end
		local poC = 0
		for _, r in ipairs(potOutliers) do
			if poC >= 5 then break end
			if not seenPot[r.itemID] and (r.profit or 0) > 0 then
				poC = poC + 1
				potentialProfitPerDay = potentialProfitPerDay + (r.expectedDailyProfit or 0)
			end
		end
		if potentialProfitPerDay < knownProfitPerDay then
			potentialProfitPerDay = knownProfitPerDay
		end
	else
		potentialProfitPerDay = spreadProfitPerDay + outlierProfitPerDay
		local seenKn = {}
		local ksC = 0
		for _, r in ipairs(spreadRows) do
			if ksC >= 5 then break end
			if r.unlock and r.unlock.known then
				ksC = ksC + 1
				knownPickCount = knownPickCount + 1
				seenKn[r.itemID] = true
				knownProfitPerDay = knownProfitPerDay + (r.expectedDailyProfit or 0)
			end
		end
		local koC = 0
		for _, r in ipairs(outlierRows) do
			if koC >= 5 then break end
			if not seenKn[r.itemID] and r.unlock and r.unlock.known and (r.profit or 0) > 0 then
				koC = koC + 1
				knownPickCount = knownPickCount + 1
				knownProfitPerDay = knownProfitPerDay + (r.expectedDailyProfit or 0)
			end
		end
	end

	local adviceShopRows, totalAdviceSpend = ns.BuildShoppingListRows(demandList, {
		profMap = profMap,
		subCraftMode = baseOpts.subCraftMode,
		subCraftOverrides = baseOpts.subCraftOverrides,
		ownedCounts = opts.ownedCounts,
	})

	local crateRows, bestCrate = ns.BuildCrateRows({ bestOnly = true, crateMode = "cheapest", profMap = profMap, repState = repState })
	local writRows, bestWrit = ns.BuildWritRows({ writMode = "cheapest", includeWritPouch = opts.includeWritPouch, profMap = profMap, repState = repState })

	local totalExpectedProfitPerDay = spreadProfitPerDay + outlierProfitPerDay
	local totalMatCost = (totalAdviceSpend and totalAdviceSpend > 0) and totalAdviceSpend or (spreadSpend + outlierSpend)
	local roiPct = totalMatCost > 0 and ((totalExpectedProfitPerDay / totalMatCost) * 100) or 0

	local dashOut = {
		scope = scope,
		forceKnown = forceKnown,
		hasBestKnownFallback = hasBestKnownFallback,
		topCrafts = topCrafts,
		topOutliers = topOutliers,
		spreadProfitPerDay = spreadProfitPerDay,
		outlierProfitPerDay = outlierProfitPerDay,
		expectedProfitPerDay = totalExpectedProfitPerDay,
		knownProfitPerDay = knownProfitPerDay,
		knownPickCount = knownPickCount,
		potentialProfitPerDay = potentialProfitPerDay,
		totalMaterialCost = totalMatCost,
		roiPct = roiPct,
		adviceShoppingList = adviceShopRows,
		bestCrate = bestCrate,
		bestWrit = bestWrit,
		topCrates = { crateRows and crateRows[1], crateRows and crateRows[2] },
		topWrits = { writRows and writRows[1], writRows and writRows[2] },
		spreadEmptyReason = spreadSummary and spreadSummary.emptyReason or nil,
		spreadEmptyMessage = spreadSummary and spreadSummary.emptyMessage or nil,
		needsMoreScans = (spreadSummary and spreadSummary.needsMoreScans == true) or false,
		learnedProfCount = (function()
			local n = 0
			for _ in pairs(profMap) do n = n + 1 end
			return n
		end)(),
	}
	if evalTok and ns.PopEvalOpts then ns.PopEvalOpts(evalTok) end
	ns.EndEval()
	return dashOut
end

function ns.GetDynamicAHCut()
	if type(ns.GetDynamicAuctionCut) == "function" then
		local ok, cut = pcall(ns.GetDynamicAuctionCut)
		local n = ok and tonumber(cut) or nil
		if n and n > 0 and n < 0.99 then
			return n
		end
	end
	if type(ns.SniperEngine) == "table" and type(ns.SniperEngine.GetDynamicAuctionCut) == "function" then
		local ok, cut = pcall(ns.SniperEngine.GetDynamicAuctionCut)
		local n = ok and tonumber(cut) or nil
		if n and n > 0 and n < 0.99 then
			return n
		end
	end
	return 0.05
end

function ns.GetItemCostBasis(itemID)
	local id = tonumber(itemID)
	if not id or id <= 0 then return nil, nil end
	local econ = "default"
	if type(ns.CurrentEconomyInfo) == "function" then
		local okE, info = pcall(ns.CurrentEconomyInfo)
		local ek = (okE and type(info) == "table") and (info.effectiveKey or info.key) or nil
		if type(ek) == "string" and ek ~= "" then
			econ = ek
		end
	end
	local store = (type(ns.Analytics) == "table" and type(ns.Analytics.Store) == "table" and ns.Analytics.Store)
		or (type(_G.MerchantMasterAnalytics) == "table" and type(_G.MerchantMasterAnalytics.Store) == "table" and _G.MerchantMasterAnalytics.Store)
		or (type(ns.AnalyticsStore) == "table" and ns.AnalyticsStore)
		or nil
	if store and type(store.Basis) == "function" then
		local ok, qty, avg = pcall(store.Basis, econ, id)
		local q = ok and tonumber(qty) or 0
		local a = ok and tonumber(avg) or 0
		if q and q > 0 and a and a > 0 then
			return math.floor(a + 0.5), "basis"
		end
	end
	if type(ns.GetItemCraftOption) == "function" then
		local ok, opt = pcall(ns.GetItemCraftOption, id)
		local uc = (ok and type(opt) == "table") and tonumber(opt.unitCraftCost) or nil
		if uc and uc > 0 then
			return math.floor(uc + 0.5), "craft"
		end
	end
	return nil, nil
end
