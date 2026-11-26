local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local ns, createdFrames, hostEnv = dofile(testsDir .. "host_fixture.lua")
local COUNTS = hostEnv.COUNTS
local addonDir = hostEnv.addonDir
local check = hostEnv.check
local approxEq = hostEnv.approxEq
local makeWidget = hostEnv.makeWidget
local eventFrame = hostEnv.eventFrame
local mockVendorSell = hostEnv.mockVendorSell

-- Opt into deterministic synthetic snapshots (prices + velocity) so host_suite never depends on local SnapshotData.lua
do
	local items = {}
	for id in pairs(ns.ALL_CATALOG_IDS or {}) do
		local base = math.max(50, ((ns.VENDOR_SELL and ns.VENDOR_SELL[id]) or 100) * 3)
		local unlisted = (id % 10 == 0) and id ~= 2447 and id ~= 248682 and id ~= 248702 and id ~= 2996 and id ~= 2589
		items[id] = {
			minBuyout = unlisted and 0 or base,
			marketValue = base,
			historical = base,
			qty = unlisted and 0 or 40,
			numAuctions = unlisted and 0 or 5,
			dailySold = 12.5,
			obsHours = 24,
			confidence = 2,
		}
	end
	hostEnv.loadSyntheticSnapshots({
		econ = "Normal-Horde",
		updatedAt = time() - 300,
		items = items,
	})
end

-- Pure standalone synthetic AH / velocity test helper (writes directly to MerchantMasterDB.ahPrices + GetDailySold)
local mockAHState = { buyout = {}, market = {}, listed = {}, sold = {}, regAvg = {} }
local origGetDailySold = ns.GetDailySold
ns.GetDailySold = function(id)
	if mockAHState.sold[id] ~= nil then return mockAHState.sold[id] end
	return origGetDailySold(id)
end
local function syncStandaloneAH(id)
	local econ = "Normal-Horde"
	MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
	MerchantMasterDB.ahPrices[econ] = MerchantMasterDB.ahPrices[econ] or { _scannedAt = time() }
	local p = mockAHState.buyout[id] or mockAHState.market[id]
	local q = mockAHState.listed[id]
	if p ~= nil then
		MerchantMasterDB.ahPrices[econ][id] = { price = p, qty = q or 50, at = time() }
	elseif q ~= nil and MerchantMasterDB.ahPrices[econ][id] then
		MerchantMasterDB.ahPrices[econ][id].qty = q
	else
		MerchantMasterDB.ahPrices[econ][id] = nil
	end
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end
local function makeAHProxy(field)
	return setmetatable({}, {
		__index = function(_, id) return mockAHState[field][id] end,
		__newindex = function(_, id, val)
			mockAHState[field][id] = val
			if field == "buyout" or field == "market" or field == "listed" then
				syncStandaloneAH(id)
			end
		end,
	})
end
local mockTSMPrices = {
	dbminbuyout = makeAHProxy("buyout"),
	dbmarket = makeAHProxy("market"),
	dbnumauctions = makeAHProxy("listed"),
	dbregionsoldperday = makeAHProxy("sold"),
	dbregionmarketavg = makeAHProxy("regAvg"),
	vendorsell = setmetatable({}, {
		__index = function(_, id) return mockVendorSell[id] end,
		__newindex = function(_, id, val) mockVendorSell[id] = val end,
	}),
}
local function clearMockAH()
	for k in pairs(mockAHState.buyout) do mockAHState.buyout[k] = nil end
	for k in pairs(mockAHState.market) do mockAHState.market[k] = nil end
	for k in pairs(mockAHState.listed) do mockAHState.listed[k] = nil end
	if MerchantMasterDB.ahPrices and MerchantMasterDB.ahPrices["Normal-Horde"] then
		wipe(MerchantMasterDB.ahPrices["Normal-Horde"])
	end
end

do
	local previous = _G._
	local sentinel = {}
	_G._ = sentinel
	ns.EvaluateUnlock("tailoring", 1, 5, 0, { rep = 5, repFactionID = 270 },
		{ tailoring = 300 }, { standing = 5 })
	local unchanged = _G._ == sentinel
	_G._ = previous
	check(unchanged, "EvaluateUnlock keeps its discarded standing return local")
end

-- 2. Verify New Filter #1: Recipes "Merchant Vendor Only" (314 live currency=3402 Camp Recipes Only)
---------------------------------------------------------------------------------------------------
local recAll = ns.BuildRecipeRows({ profFilter = "all", sourceFilter = "all" })
check(#recAll == COUNTS.totalRecipes, "All crafting recipes = " .. COUNTS.totalRecipes .. ", got " .. #recAll)

local recMerchantOnly = ns.BuildRecipeRows({ profFilter = "all", merchantVendorOnly = true })
check(#recMerchantOnly == COUNTS.campRecipes, "Merchant Vendor Only filter must return exact " .. COUNTS.campRecipes .. " Camp vendor recipes, got " .. #recMerchantOnly)
for _, r in ipairs(recMerchantOnly) do
	check(r.source == "camp", "Every recipe in Merchant Vendor Only mode must have source == 'camp'")
end

-- 2b. Live currency=3402 camp sync: 314 camp recipes, 0 duplicates, 0 empty reagents, 0 spellID=0, hidden 250996 gone
do
	local campN, dupN, emptyReag, noSpell, hidden, boots, hammers = 0, 0, 0, 0, 0, nil, 0
	local seenSp, seenRi = {}, {}
	for _, r in ipairs(ns.RECIPES) do
		if r.recipeItemID == 250996 or r.spellID == 1251750 then hidden = hidden + 1 end
		if r.source == "camp" then
			campN = campN + 1
			if not r.spellID then noSpell = noSpell + 1 end
			if not r.reagents or #r.reagents == 0 then emptyReag = emptyReag + 1 end
			if (r.spellID and seenSp[r.spellID]) or (r.recipeItemID and seenRi[r.recipeItemID]) then dupN = dupN + 1 end
			if r.spellID then seenSp[r.spellID] = true end
			if r.recipeItemID then seenRi[r.recipeItemID] = true end
			if r.recipeItemID == 289560 then boots = r end
			if r.recipeItemID == 285289 or r.recipeItemID == 285290 or r.recipeItemID == 285291 then hammers = hammers + 1 end
			check(r.vendorA and r.vendorA ~= "" and r.vendorH and r.vendorH ~= "", "Camp recipe has Alliance + Horde vendor names: " .. tostring(r.name))
		end
	end
	check(campN == COUNTS.campRecipes, "Exactly " .. COUNTS.campRecipes .. " camp recipes in ns.RECIPES, got " .. campN)
	check(dupN == 0, "0 duplicate camp recipes, got " .. dupN)
	check(emptyReag == 0, "0 camp recipes with empty reagents, got " .. emptyReag)
	check(noSpell == 0, "0 camp recipes without spellID, got " .. noSpell)
	check(hidden == 0, "Unobtainable 250996 Disorienting Smog Potion removed, got " .. hidden)
	check(hammers == 3, "3 Blacksmith Hammer plans are camp recipes, got " .. hammers)
	check(boots ~= nil and boots.spellID == 1328948 and boots.rep == 6 and boots.favorCost == 180 and boots.skill == 280 and boots.isEnchant == true
		and #boots.reagents == 4 and boots.vendorA == "Alynsia" and boots.vendorH == "Beneris",
		"289560 Formula: Enchant Boots - Speed present (Honored, 180 Favor, skill 280, 4 reagents, Alynsia/Beneris)")
	local byRep = 0
	for _, b in pairs(ns.CAMP_RECIPES_BY_REP) do byRep = byRep + #b end
	check(byRep == COUNTS.campRecipes, "CAMP_RECIPES_BY_REP holds exactly " .. COUNTS.campRecipes .. " camp recipes, got " .. byRep)
	local mpCamp, mpEnch = 0, {}
	for _, pk in ipairs(ns.MP.PROF_ORDER) do
		for _, m in ipairs(ns.MP.RECIPES[pk] or {}) do
			if m.src == "camp" then mpCamp = mpCamp + 1 end
			if pk == "enchanting" and m.ri then mpEnch[m.ri] = m end
			check(m.ri ~= 250996, "MP.RECIPES no longer lists hidden 250996")
		end
	end
	check(mpCamp == COUNTS.campRecipes, "MP.RECIPES lists exactly " .. COUNTS.campRecipes .. " camp recipes, got " .. mpCamp)
	for _, ri in ipairs({249529, 249530, 249532, 249534, 249536, 289560}) do
		check(mpEnch[ri] and mpEnch[ri].src == "camp", "MP.RECIPES enchanting includes camp recipe " .. ri)
	end
	check(mpEnch[289560] and mpEnch[289560].y == 300 and mpEnch[289560].g == 320 and mpEnch[289560].gr == 340 and mpEnch[289560].rod == 376,
		"MP 289560 skillups 280/300/320/340 with Runed Truesilver Rod")
end

-- 2c. Craftsman's Writ turn-ins: Expert 60/60, Artisan 28/45, 13 zone hints, 15 special Favor unlocks
do
	local want = {
		[264040] = { "Murache", "Ashenvale", 64.5, 79.2 },
		[264059] = { "Greta Mosshoof", "Felwood", 51.1, 82.2 },
		[264070] = { "Ugbert", "Dustwallow Marsh", 40.9, 28.0 },
		[264088] = { "Bullets Bigblast", "Swamp of Sorrows", 69.9, 41.7 },
		[264090] = { "Rhapsody Shindigger", "The Hinterlands", 26.9, 48.6 },
		[264092] = { "Garek", "Badlands", 61.8, 54.2 },
	}
	local mapped, expertZones, expertNPCs, expertExact = 0, 0, 0, 0
	local artisanZones, artisanNPCs, artisanExact = 0, 0, 0
	for _, w in ipairs(ns.WRITS) do
		local e = want[w.itemID]
		if e and w.npc == e[1] and w.zone == e[2] and w.x == e[3] and w.y == e[4] then mapped = mapped + 1 end
		if w.rep == 125 then
			if w.zone then expertZones = expertZones + 1 end
			if w.npc then expertNPCs = expertNPCs + 1 end
			if w.npc and w.zone and w.x and w.y and w.x > 0 and w.y > 0 then expertExact = expertExact + 1 end
		elseif w.rep == 200 then
			if w.zone then artisanZones = artisanZones + 1 end
			if w.npc then artisanNPCs = artisanNPCs + 1 end
			if w.npc and w.zone and w.x and w.y and w.x > 0 and w.y > 0 then artisanExact = artisanExact + 1 end
		end
		if ns.WRIT_ZONE_HINTS[w.itemID] then
			check(not w.zone, "WRIT_ZONE_HINTS only lists writs without an explicit zone: " .. w.itemID)
		end
	end
	check(mapped == 6, "6 newly mapped writs carry exact NPC + zone + coords, got " .. mapped)
	check(expertZones == 60 and expertNPCs == 60 and expertExact == 60,
		string.format("Expert writs have %d/60 confirmed zones, %d/60 NPCs, and %d/60 exact locations", expertZones, expertNPCs, expertExact))
	check(artisanZones == 28 and artisanNPCs == 28 and artisanExact == 28,
		string.format("Artisan writs have %d/28 confirmed zones, %d/28 NPCs, and %d/28 exact locations", artisanZones, artisanNPCs, artisanExact))
	local hints = 0
	for _ in pairs(ns.WRIT_ZONE_HINTS) do hints = hints + 1 end
	check(hints == 13 and ns.WRIT_ZONE_HINTS[264125] == "Azshara" and ns.WRIT_ZONE_HINTS[264132] == "Western Plaguelands"
		and ns.WRIT_ZONE_HINTS[264151] == "Winterspring" and ns.WRIT_ZONE_HINTS[264121] == nil,
		"The 13 Artisan hints retain their catalog slot zones and leave Slot 5 unhinted")
	check(#ns.SPECIAL_REP_UNLOCKS == 15, "15 SPECIAL_REP_UNLOCKS, got " .. #ns.SPECIAL_REP_UNLOCKS)
	local sp = {}
	for _, u in ipairs(ns.SPECIAL_REP_UNLOCKS) do sp[u.itemID] = u end
	check(sp[270887] and sp[270887].faction == "Horde" and sp[270888] and sp[270888].faction == "Alliance" and sp[270888].favorCost == 1200,
		"Advertising License Application split Horde 270887 / Alliance 270888")
	local receipt = sp[262902]
	check(receipt and receipt.favorCost == 15 and receipt.rep == 5 and sp[262896] and sp[262896].favorCost == 15 and sp[262896].rep == 6,
		"Forged Delivery Receipt (Friendly) + Forger's Quill (Honored) at 15 Favor")
	check(receipt.questID == 93862 and receipt.containerItemID == 262917
		and receipt.forgedRefundCopper == 100 and receipt.forgedBaseRep == 50,
		"Forged Delivery unlock records Crate Return, its container, 100c refund, and 50 reputation")
	local certs = 0
	for _, id in ipairs({271621, 271622, 271624, 271625, 271626, 271627}) do
		if sp[id] and sp[id].category == "Certification" and sp[id].favorCost == 1000 and sp[id].rep == 4 then certs = certs + 1 end
	end
	check(certs == 6, "6 Profession Certifications at 1000 Favor, got " .. certs)
end

do
	local rewards = ns.DEFAULT_REWARDS
	local apprentice = rewards.Apprentice[1]
	check(apprentice.tokens == 5 and apprentice.questID == 91899 and apprentice.sealedID == 248765,
		"Apprentice Q1 cashback belongs to the 5-Favor turn-in for sealed crate 248765")
	local cashback = { Apprentice = { 250, 500 }, Journeyman = { 500, 1000 }, Expert = { 750, 1500 }, Artisan = { 1000, 2000 } }
	for tier, qualities in pairs(cashback) do
		for quality, copper in ipairs(qualities) do
			check(rewards[tier][quality].copper == copper, tier .. " Q" .. quality .. " refunds " .. copper .. "c")
		end
	end
end

-- Daily Writ cooldown API, persistence, and table column contract.
do
    local savedWrits = ns.WRITS
    local savedTime = _G.time
    local savedQuestLog = _G.C_QuestLog
    local savedDateTime = _G.C_DateAndTime
    local savedGlobalQuest = _G.IsQuestFlaggedCompleted
    local savedChar = ns.activeChar
    local savedAppChar = ns.app.char
    local savedRefresh = ns.app.refresh
    local panelWasShown = ns.app.panel:IsShown()
    local now, resetSeconds = 200000, 18000
    local completed = {}
    local fixtureChar = { writCooldowns = {} }
    ns.WRITS = { savedWrits[1], savedWrits[2], savedWrits[3] }
    ns.activeChar = fixtureChar
    ns.app.char = fixtureChar
    ns.app.refresh = function() end
    _G.time = function() return now end
    _G.C_QuestLog = { IsQuestFlaggedCompleted = function(qid) return completed[qid] end }
    _G.C_DateAndTime = { GetSecondsUntilDailyReset = function() return resetSeconds end }
    check(ns.app.ui.writsTable.columns[3].key == "zone" and ns.app.ui.writsTable.columns[4].key == "cdSort"
        and ns.app.ui.writsTable.columns[4].label == "CD", "Writ cooldown column follows Turn-In Area")
    local validQuestIDs = true
    for _, writ in ipairs(savedWrits) do
        if type(writ.questID) ~= "number" or writ.questID <= 0 then validQuestIDs = false end
    end
    check(validQuestIDs, "Every Craftsman's Writ has a positive questID")
    local a, b, c = ns.WRITS[1], ns.WRITS[2], ns.WRITS[3]
    completed[a.questID], completed[b.questID], completed[c.questID] = true, true, false
    resetSeconds = 18000
    local aInfo = ns.GetWritCooldownInfo(a, { now = now, char = fixtureChar })
    check(aInfo.shortText == "5h" and aInfo.sortValue == 18000, "Five-hour live Writ cooldown formats and sorts as 5h")
    resetSeconds = 1500
    local bInfo = ns.GetWritCooldownInfo(b, { now = now, char = fixtureChar })
    check(bInfo.shortText == "25m" and bInfo.sortValue == 1500, "Twenty-five-minute live Writ cooldown formats and sorts as 25m")
    local cInfo = ns.GetWritCooldownInfo(c, { now = now, char = fixtureChar })
    check(cInfo.shortText == "R" and cInfo.sortValue == 0, "Uncompleted Writ is Ready today")
    completed[a.questID], completed[b.questID], completed[c.questID] = nil, nil, false
    _G.C_DateAndTime = nil
    fixtureChar.writCooldowns[a.questID] = now + 18000
    fixtureChar.writCooldowns[b.questID] = now + 1500
    local rows = ns.BuildWritRows({ zoneFilter = "all", profFilter = "all", unlockFilter = "all", now = now, char = fixtureChar })
    ns.app.ui.writsTable.setRows(rows)
    local visibleByQuest = {}
    for _, frame in ipairs(ns.app.ui.writsTable.scrollBox._frames) do
        if frame.data then visibleByQuest[frame.data.questID] = frame end
    end
    local rowA, rowB, rowC = visibleByQuest[a.questID], visibleByQuest[b.questID], visibleByQuest[c.questID]
    check(rowA and rowA.cells[4]:GetText():find("5h|r", 1, true), "Writ table renders 5h in the CD cell")
    check(rowB and rowB.cells[4]:GetText():find("25m|r", 1, true), "Writ table renders 25m in the CD cell")
    check(rowC and rowC.cells[4]:GetText():find("R|r", 1, true), "Writ table renders ready Writ in green CD cell")
    check(rowA and rowA.cells[5]:GetText():find(" ", 1, true) and rowA.cells[6]:GetText():find("+", 1, true)
        and rowA.cells[7] and rowA.cells[8] and rowA.cells[9] and rowA.cells[10] and rowA.cells[11]
        and rowA.cells[12] and rowA.cells[13], "Writ table columns 5 through 13 remain correctly populated")
    resetSeconds = 18000
    local persistedQuestID = c.questID
    _G.C_DateAndTime = { GetSecondsUntilDailyReset = function() return resetSeconds end }
    ns.app.panel:Show()
    eventFrame._scripts.OnEvent(eventFrame, "QUEST_TURNED_IN", persistedQuestID)
    check(fixtureChar.writCooldowns[persistedQuestID] == now + 18000, "QUEST_TURNED_IN persists per-character daily reset time")
    completed[persistedQuestID] = nil
    local persisted = ns.GetWritCooldownInfo(c, { now = now, char = fixtureChar })
    check(persisted.onCooldown and persisted.sortValue == 18000, "Persisted turn-in fallback remains on cooldown without live completion")
    completed[persistedQuestID] = false
    _G.C_DateAndTime = { GetSecondsUntilDailyReset = function() return resetSeconds end }
    resetSeconds = 18000
    local refreshed = ns.GetWritCooldownInfo(c, { now = now, char = fixtureChar })
    check(refreshed.available and fixtureChar.writCooldowns[persistedQuestID] == nil,
        "Live incomplete quest clears stale persisted cooldown")
    fixtureChar.writCooldowns[persistedQuestID] = now + 10
    local expired = ns.GetWritCooldownInfo(c, { now = now + 10, char = fixtureChar })
    check(expired.available and fixtureChar.writCooldowns[persistedQuestID] == nil, "Expired persisted cooldown becomes Ready")
    ns.app.refresh = savedRefresh
    ns.app.char = savedAppChar
    ns.activeChar = savedChar
    ns.WRITS = savedWrits
    _G.time = savedTime
    _G.C_QuestLog = savedQuestLog
    _G.C_DateAndTime = savedDateTime
    _G.IsQuestFlaggedCompleted = savedGlobalQuest
    if not panelWasShown then ns.app.panel:Hide() end
end

---------------------------------------------------------------------------------------------------
-- 3. Verify New Filter #2: Waylaid Crates Craft vs Buy AH Filter (crateMode)
---------------------------------------------------------------------------------------------------
-- Green Apprentice Fabrics (itemID=248702, 10 tokens, 500c reward)
-- Bundle 2: 20x Bolt of Linen Cloth (itemID=2996), crafted by Tailoring from 2x Linen Cloth (2589)
mockTSMPrices.dbminbuyout[248702] = 300 -- 3s crate
mockTSMPrices.dbminbuyout[2996]   = 40  -- 40c AH Bolt of Linen Cloth (Buy Total = 800c)
mockTSMPrices.dbminbuyout[2589]   = 8   -- 8c Linen Cloth -> Craft Bolt = 16c ea (Craft Total = 320c)

local cCheapest = ns.BuildCrateRows({ crateMode = "cheapest" })
local cBuyOnly  = ns.BuildCrateRows({ crateMode = "buy" })
local cCraftOnly= ns.BuildCrateRows({ crateMode = "craft" })

check(#cCheapest == 96 and #cBuyOnly == 96, "Cheapest & Buy AH Only return all 96 crate bundles")
check(#cCraftOnly > 0 and #cCraftOnly < 96, "Craft Only filters strictly to craftable crate bundles (" .. #cCraftOnly .. ")")
for _, r in ipairs(cCraftOnly) do
	check(r.hasCraft == true and r.mode == "Craft", "Every Craft Only crate row must be craftable and in Craft mode")
end

local rowCheap, rowBuy
for _, r in ipairs(cCheapest) do
	if r.crateID == 248702 and r.reagentID == 2996 then rowCheap = r; break end
end
for _, r in ipairs(cBuyOnly) do
	if r.crateID == 248702 and r.reagentID == 2996 then rowBuy = r; break end
end
check(rowCheap ~= nil and rowBuy ~= nil, "Found Bolt of Linen Cloth crate rows")
check(rowCheap.mode == "Craft" and rowCheap.reagentTotal == 320, "Cheapest crateMode picks Craft (320c < 800c)")
check(rowCheap.totalPrice == 300 + 320 - 500, "Net total with Craft = 120c (3s + 3s20c - 5s)")
approxEq(rowCheap.pricePerToken, 12, 0.001, "120c / 10 tokens = 12c/tok")

check(rowBuy.mode == "Buy" and rowBuy.reagentTotal == 800, "Buy AH Only forces Buy (800c)")
check(rowBuy.totalPrice == 300 + 800 - 500, "Net total with Buy = 600c")
approxEq(rowBuy.pricePerToken, 60, 0.001, "600c / 10 tokens = 60c/tok")

---------------------------------------------------------------------------------------------------
-- 4. Verify Calculator 1: Favor Token Calculator + AH Stock Exhaustion & Multi-Lot Price-Jump Switching
---------------------------------------------------------------------------------------------------
-- Isolate Live AH stock & prices on Normal-Horde so only controlled crates are in stock:
clearMockAH()
MerchantMasterDB.economy = "auto"
MerchantMasterDB.priceSource = "live_ah"
MerchantMasterDB.ahPrices["Normal-Horde"] = {
	_scannedAt = time(),
	-- Crate 1: White Apprentice Herbs (248682, 5 tokens, 250c cashback), 2 crates on AH.
	[248682] = { price = 100, qty = 2, absent = false, at = time() },
	[2447]   = { price = 5,   qty = 40, absent = false, at = time() }, -- Peacebloom: 200c gross, -50c net.
	-- Crate 2: White Apprentice Ore (248683, 5 tokens, 250c cashback), 20 crates on AH.
	[248683] = { price = 150, qty = 20, absent = false, at = time() },
	[2770]   = { price = 10,  qty = 400, absent = false, at = time() }, -- Copper Ore: 350c gross, 100c net.
}

-- Order 25 tokens:
-- Fill 2 Apprentice Herbs crates (-10c/Favor), then 3 Apprentice Ore crates (20c/Favor).
local favRes = ns.SolveFavorShoppingList(25, { respectStock = true, crateMode = "buy" })
check(favRes.tokensFulfilled == 25, "Fulfilled 25 Favor tokens")
check(favRes.cratesFilled == 5, "Filled 5 crates total")
check(favRes.combosUsed == 2 and favRes.switchEvents == 1, "Automatically switched crate combo when cheap AH stock ran out")
check(favRes.comboPlan[1].crateID == 248682 and favRes.comboPlan[1].count == 2, "Leg 1 bought all 2 cheap Apprentice Herbs crates")
check(favRes.comboPlan[2].crateID == 248683 and favRes.comboPlan[2].count == 3, "Leg 2 switched to 3 Apprentice Ore crates")
check(favRes.grossSpend == (2 * 200) + (3 * 350) and favRes.totalReward == 5 * 250
	and favRes.netCost == (2 * 200) + (3 * 350) - (5 * 250), "Favor plan spends 1,450c and refunds 1,250c for 200c net")
check(#favRes.shoppingList == 4, "Shopping list has 2 crates + 2 materials")

-- Test Multi-Lot Price-Jump Switching (MerchantMasterDB.ahLots):
-- Suppose Apprentice Herbs (248682) now has 10 crates at 100c,
-- Peacebloom (2447) has 20 cheap at 5c, then 100 expensive at 50c (20*50=1000c!),
-- while Silverleaf (765, also in Apprentice Herbs!) has 100 steady at 12c (20*12=240c).
MerchantMasterDB.ahPrices["Normal-Horde"][248682] = { price = 100, qty = 10, absent = false, at = time() }
MerchantMasterDB.ahPrices["Normal-Horde"][2447]   = { price = 5,   qty = 120, absent = false, at = time() }
MerchantMasterDB.ahPrices["Normal-Horde"][765]    = { price = 12,  qty = 100, absent = false, at = time() }
MerchantMasterDB.ahLots["Normal-Horde"] = {
	[2447] = {
		at = time(),
		totalQty = 120,
		lots = {
			{ price = 5,  qty = 20 },  -- Crate #1 Peacebloom = 100c (total 200c)
			{ price = 50, qty = 100 }, -- Crate #2 Peacebloom would jump to 1,000c (total 1,100c)!
		},
	},
}

local lotRes = ns.SolveFavorShoppingList(10, { respectStock = true, crateMode = "buy" })
check(lotRes.tokensFulfilled == 10 and lotRes.combosUsed == 2, "Multi-lot order book switched before the 50c Peacebloom price wall")
check(lotRes.comboPlan[1].reagentID == 2447 and lotRes.comboPlan[1].count == 1, "Crate #1 bought the 20 cheap 5c Peacebloom")
check(lotRes.comboPlan[2].reagentID == 765  and lotRes.comboPlan[2].count == 1, "Crate #2 switched to 20x 12c Silverleaf (340c < 1,100c)")
check(lotRes.grossSpend == 200 + 340 and lotRes.totalReward == 2 * 250
	and lotRes.netCost == (200 + 340) - (2 * 250), "Multi-lot plan spends 540c and refunds 500c for 40c net")
wipe(MerchantMasterDB.ahLots["Normal-Horde"])

---------------------------------------------------------------------------------------------------
-- 5. Verify Calculator 2: Live Character Rep -> Target Stage + Writ Stock Switching & Shopping List
---------------------------------------------------------------------------------------------------
-- Character is at Friendly 1,500/6,000 -> startRep = 4,500. Target Honored = 9,000 -> repNeeded = 4,500 (or 2,500 with +2,000 Shipping Label).
local writA = ns.WRITS[1] -- 75 rep
local writB = ns.WRITS[2]
MerchantMasterDB.ahPrices["Normal-Horde"][writA.itemID] = { price = 100, qty = 10, absent = false, at = time() } -- 10 writs * 75 = 750 rep max
MerchantMasterDB.ahPrices["Normal-Horde"][writA.requiredItemID] = { price = 50, qty = 100, absent = false, at = time() }
MerchantMasterDB.ahPrices["Normal-Horde"][writB.itemID] = { price = 300, qty = 50, absent = false, at = time() }
MerchantMasterDB.ahPrices["Normal-Horde"][writB.requiredItemID] = { price = 80, qty = 200, absent = false, at = time() }

local repRes = ns.SolveRepShoppingList({
	targetStanding = 6, -- Honored (9,000)
	includeShippingLabel = true, -- 9,000 - 4,500 - 2,000 = 2,500 rep needed
	writMode = "buy",
	respectStock = true,
})
check(repRes.startRep == 4500 and repRes.targetThreshold == 9000, "Retrieved live character rep 4,500 -> Honored 9,000")
check(repRes.repNeeded == 2500, "Deducted +2,000 Shipping Label -> 2,500 rep needed")
check(repRes.repFulfilled >= 2500, "Fulfilled >= 2,500 rep")
check(repRes.distinctWrits == 2, "Used all 10 cheap Writ A scrolls then switched to Writ B")
check(#repRes.shoppingList >= 4, "Rep Shopping List generated for Writs + Turn-In Items")

-- Restore auto priceSource for TSM tests
MerchantMasterDB.priceSource = "auto"
wipe(MerchantMasterDB.ahPrices["Normal-Horde"])

---------------------------------------------------------------------------------------------------
-- 6. Verify Writ Crafter Profit Screen + Sub-Craft Shopping List (Cured Hide AH Price & Craft Price)
---------------------------------------------------------------------------------------------------
-- Find a Leatherworking Writ requiring Cured Light/Medium/Heavy/Thick Hide!
local hideItemIDs = { [4231] = true, [4233] = true, [4236] = true, [8172] = true }
local lwWrit, curedHideID
for _, w in ipairs(ns.WRITS) do
	for _, rg in ipairs(w.reagents or {}) do
		if hideItemIDs[rg[1]] then
			lwWrit = w
			curedHideID = rg[1]
			break
		end
	end
	if lwWrit then break end
end
check(lwWrit ~= nil and curedHideID ~= nil, "Found Leatherworking Writ using a Cured Hide (" .. tostring(curedHideID) .. ")")

-- Price all reagents of lwWrit on TSM: make curedHide expensive on AH (3000c = 30s), while its raw hide is cheap (400c = 4s)!
local hideRec = ns.SelectBestRecipeForItem(curedHideID, "leatherworking", ns.GetPlayerProfessions())
check(hideRec ~= nil, "Found Leatherworking recipe to craft Cured Hide " .. tostring(curedHideID))
for _, subRg in ipairs(hideRec.reagents) do
	if not ns.VENDOR_REAGENTS[subRg[1]] then
		mockTSMPrices.dbminbuyout[subRg[1]] = 400 -- 4s raw hide
		mockTSMPrices.dbnumauctions[subRg[1]] = 35
	end
end
for _, rg in ipairs(lwWrit.reagents) do
	if rg[1] == curedHideID then
		mockTSMPrices.dbminbuyout[rg[1]] = 3000 -- 30s on AH!
		mockTSMPrices.dbnumauctions[rg[1]] = 12
	elseif not ns.VENDOR_REAGENTS[rg[1]] then
		mockTSMPrices.dbminbuyout[rg[1]] = 120 -- 1s20c leather
		mockTSMPrices.dbnumauctions[rg[1]] = 80
	end
end
mockTSMPrices.dbminbuyout[lwWrit.requiredItemID] = 9500 -- 95s finished glove/armor on AH
mockTSMPrices.dbnumauctions[lwWrit.requiredItemID] = 6
mockTSMPrices.dbregionsoldperday[lwWrit.requiredItemID] = 14.5
mockTSMPrices.vendorsell[lwWrit.requiredItemID] = 4000 -- 40s vendor sell -> 2h Forever AH deposit = 5% = 200c!

local wpRows, bestWP, wpProfCount = ns.BuildWritProfitRows({
	applyAHCut = true,
	postDuration = 1, -- 2h (5% vendor sell on WoW Forever)
	subCraftMode = "smart",
})
check(#wpRows == 150, "Writ Profit built all 150 Writ items")
local lwRow
for _, r in ipairs(wpRows) do
	if r.writID == lwWrit.itemID then lwRow = r; break end
end
check(lwRow ~= nil, "Found Leatherworking Writ Profit row")
check(lwRow.usedSubCraft == true and lwRow.subSavings > 2000, "Smart Craft Cost automatically sub-crafted Cured Hide to save >20s")
check(lwRow.ahListingCost == 200, "2h Forever AH Listing Deposit = 5% of 4000c = 200c, got " .. tostring(lwRow.ahListingCost))
check(lwRow.dailySold ~= nil and lwRow.dailySold > 0 and lwRow.listed == 6, "Sales/Day and AH Listed populated on Writ Profit row")
check(lwRow.profit == math.floor(9500 * 0.95 + 0.5) - lwRow.craftCost, "Writ Profit per item matches net 95% AH - smart craft cost")

-- Build Shopping List for this Leatherworking Writ item & verify BOTH AH Price and Craft Price appear on Cured Hide!
local byID = { [lwRow.itemID] = lwRow }
local shopOut = ns.BuildWritCraftShoppingList(byID, {}, lwRow.itemID, {
	applyAHCut = true,
	postDuration = 1,
	subCraftMode = "smart",
	subCraftOverrides = MerchantMasterDB.subCraftOverrides,
})
local hideShopRow, subMatCount = nil, 0
for _, sr in ipairs(shopOut.shoppingList) do
	if sr.itemID == curedHideID then hideShopRow = sr end
	if sr.isSubRow then subMatCount = subMatCount + 1 end
end
check(hideShopRow ~= nil, "Cured Hide appears in Writ Profit Shopping List")
check(hideShopRow.ahUnitPrice == 3000, "Shopping List shows Cured Hide AH unit price (3000c)")
check(hideShopRow.craftUnitPrice ~= nil and hideShopRow.craftUnitPrice < 600, "Shopping List ALSO shows Cured Hide Craft unit price (<600c)")
check(hideShopRow.makeMyself == true and subMatCount >= 2, "Cured Hide defaults to Craft Yourself and expands indented Sub-Mat rows (Hide + Salt)")

-- Toggle user override to force Buy AH on Cured Hide:
MerchantMasterDB.subCraftOverrides[curedHideID] = "buy"
local shopOutBuy = ns.BuildWritCraftShoppingList(byID, {}, lwRow.itemID, {
	applyAHCut = true,
	postDuration = 1,
	subCraftMode = "smart",
	subCraftOverrides = MerchantMasterDB.subCraftOverrides,
})
local hideShopBuy, subMatCountBuy = nil, 0
for _, sr in ipairs(shopOutBuy.shoppingList) do
	if sr.itemID == curedHideID then hideShopBuy = sr end
	if sr.isSubRow then subMatCountBuy = subMatCountBuy + 1 end
end
check(hideShopBuy.makeMyself == false and hideShopBuy.lineCost == hideShopBuy.ahTotalPrice and subMatCountBuy == 0,
	"Overriding Cured Hide to 'buy' switches Line Total to AH Price and hides sub-mat rows")
MerchantMasterDB.subCraftOverrides[curedHideID] = nil

---------------------------------------------------------------------------------------------------
-- 7. Verify Crate Mats Explorer (Gatherer Volume, Sales/Day, Best Filler ★)
---------------------------------------------------------------------------------------------------
mockTSMPrices.dbminbuyout[2447] = 18
mockTSMPrices.dbnumauctions[2447] = 420
mockTSMPrices.dbregionsoldperday[2447] = 950.5
local cmAll = ns.BuildCrateMaterialRows({ matTypeFilter = "all" })
local cmGather = ns.BuildCrateMaterialRows({ matTypeFilter = "gather" })
local cmCrafted = ns.BuildCrateMaterialRows({ matTypeFilter = "crafted" })
check(#cmAll == 96, "All 96 crate material bundles listed")
check(#cmGather + #cmCrafted == 96, "Gather (" .. #cmGather .. ") + Crafted (" .. #cmCrafted .. ") partition all 96 crate bundles cleanly")

---------------------------------------------------------------------------------------------------
-- 8. Exercise sidebar views, slash commands, tooltips, sort headers and interactive buttons
---------------------------------------------------------------------------------------------------
for _, cmd in ipairs({
	"", "crates", "cratemats", "writs", "writprofit", "recipes", "rep",
	"calc", "favorcalc", "repcalc", "bags", "econ", "options",
}) do
	SlashCmdList.MERCHANTMASTER(cmd)
end

MerchantMasterDB.economy = "auto"
for _, tab in ipairs({ "crates", "writs", "recipes", "rep", "calc", "bags" }) do
	SlashCmdList.MERCHANTMASTER(tab)
	-- Exercise the tooltip handlers on rendered cells in every ScrollBox.
	for _, f in ipairs(createdFrames) do
		if f._frames and #f._frames > 0 then
			for _, rw in ipairs(f._frames) do
				local cells = rw.cellGroup and rw.cellGroup.cellsByKey or rw.cells or {}
				for _, cell in pairs(cells) do
					local enter = type(cell) == "table" and cell._scripts and cell:GetScript("OnEnter")
					if enter then enter(cell) end
				end
				if rw.linkHit then rw.linkHit:GetScript("OnEnter")(rw.linkHit) end
			end
		end
	end
end

local ldb = LibStub("LibDataBroker-1.1"):GetDataObjectByName("MerchantMaster")
check(ldb ~= nil and type(ldb.OnTooltipShow) == "function", "LDB launcher registered")
ldb.OnTooltipShow(GameTooltip)
check(#GameTooltip._lines >= 3, "Minimap tooltip rendered")

-- Simulate Live AH Browse Scan + Calculator Deep Scan AH Lots at open AuctionHouseFrame
_G.AuctionHouseFrame = makeWidget("Frame", "AuctionHouseFrame", UIParent)
_G.AuctionHouseFrame.SearchBar = makeWidget("Frame", nil, _G.AuctionHouseFrame)
_G.AuctionHouseFrame.SearchBar.FilterButton = makeWidget("Button", nil, _G.AuctionHouseFrame.SearchBar)
_G.AuctionHouseFrame.SearchBar.SearchBox = makeWidget("EditBox", nil, _G.AuctionHouseFrame.SearchBar)
_G.AuctionHouseFrame:Show()

local browseSent, itemSearchSent = false, false
_G.C_AuctionHouse = {
	IsThrottledMessageSystemReady = function() return true end,
	SendBrowseQuery = function() browseSent = true end,
	SendSearchQuery = function() itemSearchSent = true end,
	GetBrowseResults = function()
		return {
			{ itemKey = { itemID = 248682, itemLevel = 1, itemSuffix = 0 }, totalQuantity = 12, minPrice = 280 },
			{ itemKey = { itemID = 2447, itemLevel = 1, itemSuffix = 0 }, totalQuantity = 340, minPrice = 15 },
		}
	end,
	HasFullBrowseResults = function() return true end,
	MakeItemKey = function(id) return { itemID = id } end,
	HasSearchResults = function() return false end,
	GetItemKeyInfo = function(k) return { itemName = ns.ITEM_NAMES_BY_ID[k.itemID] or "Item", isCommodity = true } end,
	GetNumCommoditySearchResults = function() return 2 end,
	GetCommoditySearchResultInfo = function(_, idx)
		if idx == 1 then return { quantity = 20, unitPrice = 14 }
		else return { quantity = 80, unitPrice = 45 } end
	end,
	HasFullCommoditySearchResults = function() return true end,
}

eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_SHOW")
SlashCmdList.MERCHANTMASTER("refresh")
check(browseSent == true, "Refresh AH triggers SendBrowseQuery")
eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")

SlashCmdList.MERCHANTMASTER("favorcalc")
for _, f in ipairs(createdFrames) do
	local lbl = f._text
	if (not lbl or lbl == "") and f._mmLabel then lbl = f._mmLabel._text end
	if lbl == "Deep Scan AH Lots" and f._scripts.OnClick then
		f:Click("LeftButton")
		break
	end
end
check(itemSearchSent == true, "Deep Scan AH Lots button triggers order-book search at AH")
eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_CLOSED")

-- Verify legacy TSM AppHelper ingestion & region sale hooks are completely removed in pure standalone mode
check(ns.IngestTSMAppData == nil and ns.GetParsedTSMEconomy == nil and ns.GetRegionSaleDetails == nil,
	"Legacy TSM AppHelper / GetRegionSaleDetails APIs removed in standalone mode")

---------------------------------------------------------------------------------------------------
-- 9. v2.2.0 Verification: 16 Standalone TGA 2.0 Assets, Sales/Day Everywhere, Calc 1 Fix & OneForAll UI
---------------------------------------------------------------------------------------------------
local expectedTgaAssets = {
	"rr_fill.tga", "window_ring.tga", "pill_fill.tga", "knob.tga",
	"glow_line.tga", "grip_resize.tga", "grip_height.tga",
	"icon_close.tga", "icon_gear.tga",
}
for _, assetName in ipairs(expectedTgaAssets) do
	local af = io.open(addonDir .. "Assets/" .. assetName, "rb")
	check(af ~= nil, "TGA asset exists: " .. assetName)
	local raw = af:read("*a")
	af:close()
	check(#raw > 44, "TGA asset non-empty: " .. assetName)
	local imgType = string.byte(raw, 3)
	local bpp = string.byte(raw, 17)
	local desc = string.byte(raw, 18)
	local footer = raw:sub(#raw - 17, #raw - 1)
	check(imgType == 2 and bpp == 32 and desc == 0x08, "TGA 32-bit RGBA bottom-left header valid: " .. assetName)
	check(footer == "TRUEVISION-XFILE.", "TGA 2.0 footer valid: " .. assetName)
end
for _, blpName in ipairs({ "fade_lr.blp", "shade_v.blp", "header_wash.blp" }) do
	local bf = io.open(addonDir .. "Assets/" .. blpName, "rb")
	check(bf ~= nil, "Glass BLP2 asset exists: " .. blpName)
	local hdr = bf:read(148)
	bf:close()
	check(type(hdr) == "string" and #hdr == 148 and hdr:sub(1, 4) == "BLP2", "BLP2 header valid: " .. blpName)
end

-- Verify Calculator 1 works even when profFilter = "alchemy" across buy, cheapest & craft modes!
wipe(MerchantMasterDB.ahPrices["Normal-Horde"])
wipe(MerchantMasterDB.ahLots["Normal-Horde"])
MerchantMasterDB.priceSource = "auto"
mockTSMPrices.dbminbuyout[248682] = 120
mockTSMPrices.dbnumauctions[248682] = 40
mockTSMPrices.dbminbuyout[2447] = 10
mockTSMPrices.dbnumauctions[2447] = 800
mockTSMPrices.dbminbuyout[248702] = 250
mockTSMPrices.dbnumauctions[248702] = 30
mockTSMPrices.dbminbuyout[2996] = 35
mockTSMPrices.dbnumauctions[2996] = 500
mockTSMPrices.dbminbuyout[2589] = 8
mockTSMPrices.dbnumauctions[2589] = 1000

for _, mode in ipairs({ "buy", "cheapest", "craft" }) do
	local alcFav = ns.SolveFavorShoppingList(150, {
		profFilter = "alchemy",
		unlockFilter = "craftable",
		crateMode = mode,
		respectStock = true,
	})
	check(alcFav.tokensFulfilled >= 150, "Calculator 1 fulfills 150 tokens under profFilter='alchemy' in crateMode=" .. mode)
	check(#alcFav.shoppingList > 0, "Calculator 1 shoppingList non-empty under profFilter='alchemy' in crateMode=" .. mode)
	for _, leg in ipairs(alcFav.comboPlan) do
		check(leg.dailySold ~= nil and leg.dailySold > 0, "Favor Plan leg populates Sales/Day in crateMode=" .. mode)
	end
	for _, sr in ipairs(alcFav.shoppingList) do
		check(sr.dailySold ~= nil and sr.dailySold >= 0, "Favor Shopping List row populates Sales/Day in crateMode=" .. mode)
	end
end

-- Verify Crates & Crate Mats auto-fallback when profFilter = "alchemy"
local alcCrates, _, _, _, cProfFallback = ns.BuildCrateRows({ profFilter = "alchemy", crateMode = "buy" })
check(#alcCrates == 96 and cProfFallback == "alchemy", "BuildCrateRows auto-falls back from alchemy to all 96 crates")
local alcCrateMats, _, _, cmProfFallback = ns.BuildCrateMaterialRows({ profFilter = "alchemy" })
check(#alcCrateMats == 96 and cmProfFallback == "alchemy", "BuildCrateMaterialRows auto-falls back from alchemy to all 96 crate materials")

-- Verify Sales/Day populated across all market & plan builders
local verifyCrates = ns.BuildCrateRows({ crateMode = "buy" })
local crateSalesCount = 0
for _, r in ipairs(verifyCrates) do
	if r.dailySold and r.dailySold > 0 then crateSalesCount = crateSalesCount + 1 end
end
check(crateSalesCount > 50, "BuildCrateRows populates Sales/Day across crate bundles (" .. crateSalesCount .. "/96)")

local verifyWrits = ns.BuildWritRows({ profFilter = "all" })
local writSalesCount = 0
for _, r in ipairs(verifyWrits) do
	if r.dailySold and r.dailySold > 0 then writSalesCount = writSalesCount + 1 end
end
check(writSalesCount > 50, "BuildWritRows populates Sales/Day across writs (" .. writSalesCount .. "/" .. #verifyWrits .. ")")

local verifyRecipes = ns.BuildRecipeRows({ profFilter = "all", sellableOnly = true })
local recSalesCount = 0
for _, r in ipairs(verifyRecipes) do
	if r.dailySold and r.dailySold > 0 then recSalesCount = recSalesCount + 1 end
end
check(recSalesCount > 100, "BuildRecipeRows populates Sales/Day across sellable recipes (" .. recSalesCount .. ")")

-- Verify standalone GetDailySold reads Blizzard Snapshot velocity (legacy CaptureActiveEconomySnapshot removed)
check(ns.CaptureActiveEconomySnapshot == nil and ns.tsmRawAppHelper == nil,
	"Legacy CaptureActiveEconomySnapshot & tsmRawAppHelper removed")
local snapPeacebloomSales = origGetDailySold(2447)
check(snapPeacebloomSales ~= nil and snapPeacebloomSales > 0, "Blizzard Snapshot serves Sales/Day for Peacebloom in standalone mode")

-- Exercise OneForAll UI controls: dropdown buttons, sub-tab switches, Calculate button, presets, gear icon & resize grips
local clickedButtons = 0
for _, f in ipairs(createdFrames) do
	local lbl = (f._mmLabel and f._mmLabel._text) or f._text or ""
	if f._mmDropArrow and f._scripts and f._scripts.OnClick then
		f:Click("LeftButton")
		clickedButtons = clickedButtons + 1
		ns.Theme.CloseDropDown()
	elseif (lbl == "Calculator 1: Favor Tokens" or lbl == "Calculator 2: Reputation Target" or lbl == "Calculate" or lbl == "50" or lbl == "150" or lbl == "500") and f._scripts and f._scripts.OnClick then
		f:Click("LeftButton")
		clickedButtons = clickedButtons + 1
	end
end
check(clickedButtons >= 8, "Exercised OneForAll dropdowns, segmented calculator buttons, Calculate & presets (" .. clickedButtons .. " buttons)")

local mainPanel = _G.MerchantMasterPanel
check(mainPanel ~= nil, "MerchantMasterPanel created")
-- Trigger banner gear button & scale/height grips
for _, f in ipairs(createdFrames) do
	if f:GetParent() == mainPanel and f._scripts and f._scripts.OnClick and f._mmIcon then
		-- Settings gear or close button (only click gear button; close hides panel)
		if f._scripts.OnEnter then
			f._scripts.OnEnter(f)
			local isGear = false
			for _, ln in ipairs(GameTooltip._lines or {}) do
				if ln:find("MerchantMaster Settings", 1, true) then isGear = true end
			end
			if isGear then f:Click("LeftButton") end
		end
	end
	if f:GetParent() == mainPanel and f._scripts and f._scripts.OnMouseDown and f._scripts.OnMouseUp then
		f._scripts.OnMouseDown(f, "LeftButton")
		if f._scripts.OnUpdate then f._scripts.OnUpdate(f, 0.016) end
		f._scripts.OnMouseUp(f, "LeftButton")
		f._scripts.OnMouseDown(f, "RightButton")
	end
end

---------------------------------------------------------------------------------------------------
-- 12. v2.3.0 Verification: Writ Profit Can-Craft/Source, Market Demand Table, Listed Yes/No & Best-in-Class
---------------------------------------------------------------------------------------------------

-- 12a. Market Demand Engine benchmarks (including user's exact 200 sales/day vs 1,000 listed = 0.20x!)
local dmFav = ns.EvaluateMarketDemand(1000, 200, true)
approxEq(dmFav.salesRatio, 0.20, 0.0001, "200 sales/day / 1,000 listed = 0.20 favorable sales ratio")
check(dmFav.tierKey == "favorable" and dmFav.isHot == true and dmFav.isListed == true, "0.20x classified as Hot/Favorable & Listed=Yes")
check(dmFav.heatBadge:find("0.20x", 1, true) ~= nil, "0.20x badge displays '0.20x'")

local dmMono0 = ns.EvaluateMarketDemand(0, 18, true)
check(dmMono0.tierKey == "monopoly" and dmMono0.isMonopoly == true and dmMono0.isListed == false and dmMono0.isUnlisted == true, "0 listed + 18/day sales = Empty-AH Monopoly & Unlisted")
check(dmMono0.listedYesNo:find("UNLISTED", 1, true) ~= nil and dmMono0.listedYesNo:find("|cffffffff", 1, true) ~= nil, "Unlisted monopoly displays white '|cffffffffUNLISTED (0)|r'")

local dmMono1 = ns.EvaluateMarketDemand(1, 4, true)
check(dmMono1.tierKey == "monopoly" and dmMono1.isMonopoly == true and dmMono1.isListed == true, "1 sole listing + 4/day sales = Sole-Seller Monopoly")

local dmHigh = ns.EvaluateMarketDemand(12, 30, true)
approxEq(dmHigh.salesRatio, 2.50, 0.0001, "30 sales/day / 12 listed = 2.50x High Turnaround")
check(dmHigh.tierKey == "high_turn" and dmHigh.isHot == true, "2.50x classified as High Turnaround")

local dmCold = ns.EvaluateMarketDemand(1000, 10, true)
approxEq(dmCold.salesRatio, 0.01, 0.0001, "10 sales/day / 1,000 listed = 0.01x Cold")
check(dmCold.tierKey == "cold" and dmCold.isHot == false, "0.01x classified as Cold / Oversupplied")

local dmBop = ns.EvaluateMarketDemand(nil, nil, false)
check(dmBop.tierKey == "bop" and dmBop.sellable == false, "Soulbound/BoP item classified cleanly as non-tradeable")

-- 12b. Writ Profit: Able to Craft + How to Get (Trainer, Recipe Vendor, Auction House, Quest)
local allWritProfitRows, _, _, wpMatched, wpSummary = ns.BuildWritProfitRows({ profFilter = "all", unlockFilter = "all" })
check(#allWritProfitRows == 150 and wpMatched == 150, "All 150 Writ Profit rows built with v2.3.0 metadata")
local seenAcq = {}
for _, wr in ipairs(allWritProfitRows) do
	check(wr.craftAbility ~= nil and wr.demand ~= nil, "Writ row has craftAbility & demand attached: " .. tostring(wr.name))
	seenAcq[wr.craftAbility.howCategory] = (seenAcq[wr.craftAbility.howCategory] or 0) + 1
end
check((seenAcq.trainer or 0) >= 40 and (seenAcq.vendor or 0) >= 20 and (seenAcq.ah or 0) >= 50,
	string.format("Writ sources span Trainer (%d), Recipe Vendor (%d), and Auction House (%d)",
		seenAcq.trainer or 0, seenAcq.vendor or 0, seenAcq.ah or 0))

-- Simulate syncing a learned Leatherworking recipe via TradeSkill window & verify Able to Craft flips to Yes ✓
local sampleLWSpell = nil
for _, wr in ipairs(allWritProfitRows) do
	if wr.prof == "leatherworking" and wr.writ.spellID and wr.writ.spellID > 0 then
		sampleLWSpell = wr.writ.spellID
		break
	end
end
check(sampleLWSpell ~= nil, "Found sample Leatherworking writ spellID")
_G.C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return { professionID = 165, professionName = "Leatherworking" } end,
	GetAllRecipeIDs = function() return { sampleLWSpell } end,
	GetRecipeInfo = function(id) return { recipeID = id, learned = (id == sampleLWSpell), name = "Synced LW Writ" } end,
}
for _, f in ipairs(createdFrames) do
	if f._events and f._events.TRADE_SKILL_SHOW and f._scripts.OnEvent then
		f._scripts.OnEvent(f, "TRADE_SKILL_SHOW")
	end
end
local ableWrits = ns.BuildWritProfitRows({ craftableFilter = "yes" })
check(#ableWrits == 1 and ableWrits[1].writ.spellID == sampleLWSpell and ableWrits[1].canCraft == true,
	"Synced TradeSkill spell marks Writ Profit item Able to Craft (Yes ✓) and filters cleanly")
check(ableWrits[1].craftAbility.cellText:find("Yes", 1, true) ~= nil, "Able-to-craft cell renders 'Yes ✓'")

local ahSourceWrits = ns.BuildWritProfitRows({ craftableFilter = "ah" })
check(#ahSourceWrits >= 50, "Craftable filter 'Get: Auction House' returns AH-sourced writs (" .. #ahSourceWrits .. ")")

-- Legacy writ-profit and crate-material commands redirect to sidebar views.
MerchantMasterDB.craftableFilter = "all"
MerchantMasterDB.demandFilter = "all"
MerchantMasterDB.profFilter = "all"
MerchantMasterDB.unlockFilter = "all"
for _, alias in ipairs({{"demand", "writs"}, {"writprofit", "writs"}, {"cratemats", "crates"}, {"mats", "crates"}}) do
	ns.app.panel:Hide()
	SlashCmdList.MERCHANTMASTER(alias[1])
	check(ns.app.panel:IsShown() and ns.app.activeTab == alias[2],
		"/mm " .. alias[1] .. " opens " .. alias[2])
end

-- 12c. Recipes: Best in Class Evaluator (100% Alchemy & Enchanting + Elixir of Greater Fortitude +400 HP benchmark)
local alchTotal, alchEval, enchTotal, enchEval, totalBiSCount = 0, 0, 0, 0, 0
local greaterFortRec, regularFortRec = nil, nil
for _, rec in ipairs(ns.RECIPES) do
	local bi = ns.EvaluateBestInClass(rec)
	if bi.isBiS then totalBiSCount = totalBiSCount + 1 end
	if rec.prof == "alchemy" then
		alchTotal = alchTotal + 1
		if bi.hasEval then alchEval = alchEval + 1 end
	elseif rec.prof == "enchanting" then
		enchTotal = enchTotal + 1
		if bi.hasEval then enchEval = enchEval + 1 end
	end
	if rec.outputItemID == 250335 then greaterFortRec = rec end
	if rec.outputItemID == 3825 then regularFortRec = rec end
end
check(alchTotal == 187 and alchEval == 141, "Alchemy recipes evaluated for Best-in-Class (" .. alchEval .. "/" .. alchTotal .. ")")
check(enchTotal == 235 and enchEval == 190, "Enchanting recipes evaluated for Best-in-Class (" .. enchEval .. "/" .. enchTotal .. ")")
check(totalBiSCount == COUNTS.bisRecipes, "Evaluated " .. totalBiSCount .. " #1 Best-in-Class winners")

check(greaterFortRec ~= nil and regularFortRec ~= nil, "Located Elixir of Greater Fortitude (250335) & Elixir of Fortitude (3825)")
local gfBiS = ns.EvaluateBestInClass(greaterFortRec)
check(gfBiS.isBiS == true and gfBiS.classLabel == "Elixir: Max Health" and gfBiS.rank == 1 and gfBiS.total == 3,
	"Elixir of Greater Fortitude is #1 ★ Best in 'Elixir: Max Health'")
check(gfBiS.valText == "+400 Max HP (30m)", "Elixir of Greater Fortitude Forever value is '+400 Max HP (30m)', got " .. tostring(gfBiS.valText))

local rfBiS = ns.EvaluateBestInClass(regularFortRec)
check(rfBiS.isBiS == false and rfBiS.rank == 2 and rfBiS.bestName == "Elixir of Greater Fortitude",
	"Elixir of Fortitude is #2/3 and points to Elixir of Greater Fortitude as strongest")

-- 12d. Recipes: Listed Yes/No, Unlisted (0) Monopoly detection & bisOnly filter
local bisRows, _, _, bisMatched, recSummary = ns.BuildRecipeRows({ bisOnly = true })
check(#bisRows == totalBiSCount and bisMatched == totalBiSCount and recSummary.bisCount == totalBiSCount,
	"bisOnly filter returns exact #1 Best-in-Class recipes (" .. #bisRows .. ")")

local unlistedRows = ns.BuildRecipeRows({ demandFilter = "unlisted" })
check(#unlistedRows > 0, "Recipes 'Demand: Unlisted (0)' filter finds unlisted monopoly opportunities (" .. #unlistedRows .. ")")
for i = 1, math.min(10, #unlistedRows) do
	check(unlistedRows[i].demand.isListed == false, "Unlisted row has demand.isListed == false")
end

SlashCmdList.MERCHANTMASTER("bis")
check(MerchantMasterDB.bisOnly == true, "/mm bis opens Recipes tab with ★ Best in Class Only enabled")
do
	local row = ns.app.ui.recipesTable.scrollBox._frames[1]
	local nameCell = row and row.cellGroup and row.cellGroup.cellsByKey and row.cellGroup.cellsByKey.name
	check(nameCell and nameCell:GetScript("OnEnter"), "Best in Class recipe has an item-name hover handler")
	GameTooltip:ClearLines()
	nameCell:GetScript("OnEnter")(nameCell)
	check(table.concat(GameTooltip._lines, " "):find("Best in Class Evaluation", 1, true),
		"Recipe name tooltip displays Best in Class Evaluation & Forever Effect")
	GameTooltip:Hide()
end

---------------------------------------------------------------------------------------------------
-- 13. v2.4.0 Verification: Vendor Recipe Coin (g/s/c) & Merchant's Favor Token Costs Everywhere
---------------------------------------------------------------------------------------------------
-- 13a. Data Completeness: 34/34 Vendor Writs + 299/299 Vendor Recipes + 314/314 Camp Favor Recipes
local vendorWritTotal, vendorWritPriced = 0, 0
local sampleVendorWrit, sampleVendorAHWrit = nil, nil
for _, w in ipairs(ns.WRITS) do
	if w.acqType == "vendor" or w.acqType == "vendor_ah" then
		vendorWritTotal = vendorWritTotal + 1
		if (w.recipeVendorPrice or 0) > 0 then
			vendorWritPriced = vendorWritPriced + 1
		end
		if w.acqType == "vendor" and not sampleVendorWrit then sampleVendorWrit = w end
		if w.acqType == "vendor_ah" and not sampleVendorAHWrit then sampleVendorAHWrit = w end
	end
end
check(vendorWritTotal == 34 and vendorWritPriced == 34,
	string.format("100%% of vendor Writs carry exact copper buy cost (%d/%d)", vendorWritPriced, vendorWritTotal))

local vendorRecTotal, vendorRecPriced = 0, 0
local campRecTotal, campRecPriced = 0, 0
local sampleVendorRec, sampleCampRec, majorHealRec = nil, nil, nil
for _, r in ipairs(ns.RECIPES) do
	if r.acqType == "vendor" or r.acqType == "vendor_ah" then
		vendorRecTotal = vendorRecTotal + 1
		if (r.recipeVendorPrice or 0) > 0 then
			vendorRecPriced = vendorRecPriced + 1
		end
		if r.acqType == "vendor" and not sampleVendorRec then sampleVendorRec = r end
		if r.recipeItemID == 13480 then majorHealRec = r end
	end
	if r.source == "camp" then
		campRecTotal = campRecTotal + 1
		if (r.favorCost or 0) >= 30 then
			campRecPriced = campRecPriced + 1
		end
		if not sampleCampRec then sampleCampRec = r end
	end
end
check(vendorRecTotal == 397 and vendorRecPriced == 397,
	string.format("100%% of vendor Recipes carry exact copper buy cost (%d/%d)", vendorRecPriced, vendorRecTotal))
check(campRecTotal == COUNTS.campRecipes and campRecPriced == COUNTS.campRecipes,
	string.format("100%% of Camp vendor Recipes carry exact Favor token cost (%d/%d)", campRecPriced, campRecTotal))
check(majorHealRec ~= nil and majorHealRec.recipeVendorPrice == 15000,
	"Classic scroll 13480 (Major Healing Potion) carries exact 1g 50s (15000c) vendor price")

-- 13b. EvaluateCraftAbility preserves coin & Favor token cost across ALL character skill/standing/profession states!
MerchantMasterDB.learnedSpells = {}
local repFriendly = { standing = 5, playerFaction = "Horde" }
local repNeutral  = { standing = 4, playerFaction = "Horde" }
local repHated    = { standing = 3, playerFaction = "Horde" }

-- Vendor recipe (NPC coin): high skill, low skill, wrong profession, fresh character
local profHigh = { [sampleVendorRec.prof] = 300 }
local profLow  = { [sampleVendorRec.prof] = 1 }
local profOther = { mining = 300 }
local profNone = {}

local abVendorHigh  = ns.EvaluateCraftAbility(sampleVendorRec, profHigh, repFriendly)
local abVendorLow   = ns.EvaluateCraftAbility(sampleVendorRec, profLow, repFriendly)
local abVendorOther = ns.EvaluateCraftAbility(sampleVendorRec, profOther, repFriendly)
local abVendorNone  = ns.EvaluateCraftAbility(sampleVendorRec, profNone, repFriendly)
check(abVendorHigh.vendorCopperCost == sampleVendorRec.recipeVendorPrice and abVendorHigh.vendorCostText ~= nil,
	"EvaluateCraftAbility sets vendorCopperCost & vendorCostText")
for stateName, ab in pairs({
	meetsSkill = abVendorHigh,
	lowSkill = abVendorLow,
	otherProf = abVendorOther,
	freshChar = abVendorNone,
}) do
	check(ab.cellText:find(ab.vendorCostText, 1, true) ~= nil,
		"Vendor coin cost '" .. tostring(ab.vendorCostText) .. "' preserved in cellText for state=" .. stateName .. " -> " .. tostring(ab.cellText))
	check(ab.howDetail:find("Cost: " .. ab.vendorCostText, 1, true) ~= nil,
		"Vendor coin cost preserved in howDetail for state=" .. stateName)
end

-- Vendor/AH hybrid writ (both vendor coin and AH):
if sampleVendorAHWrit then
	local abVAH = ns.EvaluateCraftAbility(sampleVendorAHWrit, { [sampleVendorAHWrit.prof] = 300 }, repFriendly)
	check(abVAH.howShort:find("Vendor ", 1, true) ~= nil and abVAH.howShort:find("/ AH", 1, true) ~= nil and abVAH.cellText:find(abVAH.vendorCostText, 1, true) ~= nil,
		"vendor_ah writ preserves Vendor <coin> / AH in howShort & cellText: " .. tostring(abVAH.cellText))
end

-- Camp recipe (Merchant's Favor tokens): meetsSkill+Rep, lowSkill, lowRep, wrongProf, freshChar
local favExpected = tostring(sampleCampRec.favorCost) .. " Favor"
local abCampReady = ns.EvaluateCraftAbility(sampleCampRec, { [sampleCampRec.prof] = 300 }, { standing = 8, playerFaction = "Horde" })
local abCampLowSk = ns.EvaluateCraftAbility(sampleCampRec, { [sampleCampRec.prof] = 1 }, { standing = 8, playerFaction = "Horde" })
local abCampLowRp = ns.EvaluateCraftAbility(sampleCampRec, { [sampleCampRec.prof] = 300 }, repHated)
local abCampOther = ns.EvaluateCraftAbility(sampleCampRec, profOther, repNeutral)
local abCampFresh = ns.EvaluateCraftAbility(sampleCampRec, profNone, repNeutral)
for stateName, ab in pairs({
	ready = abCampReady,
	lowSkill = abCampLowSk,
	lowRep = abCampLowRp,
	otherProf = abCampOther,
	freshChar = abCampFresh,
}) do
	check(ab.vendorFavorCost == sampleCampRec.favorCost and ab.cellText:find(favExpected, 1, true) ~= nil,
		"Camp Favor token cost '" .. favExpected .. "' preserved in cellText for state=" .. stateName .. " -> " .. tostring(ab.cellText))
	check(ab.howDetail:find(tostring(sampleCampRec.favorCost) .. " Favor Tokens", 1, true) ~= nil,
		"Camp Favor token count preserved in howDetail for state=" .. stateName)
end

-- 13c. Live observed vendor buy override check (MerchantMasterDB.liveVendorBuyGlobal)
MerchantMasterDB.liveVendorBuyGlobal = MerchantMasterDB.liveVendorBuyGlobal or {}
MerchantMasterDB.liveVendorBuyGlobal[sampleVendorRec.recipeItemID] = { price = 42500, at = time(), limited = true }
check(ns.GetRecipeVendorBuyPrice(sampleVendorRec.recipeItemID, sampleVendorRec.recipeVendorPrice) == 42500,
	"GetRecipeVendorBuyPrice prefers live observed vendor buy when present")
MerchantMasterDB.liveVendorBuyGlobal[sampleVendorRec.recipeItemID] = nil
check(ns.GetRecipeVendorBuyPrice(sampleVendorRec.recipeItemID, sampleVendorRec.recipeVendorPrice) == sampleVendorRec.recipeVendorPrice,
	"GetRecipeVendorBuyPrice falls back cleanly to static Data_Recipes copper cost")

-- 13d. All Recipes displays NPC vendor coin and Merchant Favor acquisition prices.
do
	MerchantMasterDB.bisOnly = false
	MerchantMasterDB.demandFilter = "all"
	MerchantMasterDB.sourceFilter = "all"
	MerchantMasterDB.craftableFilter = "all"
	local savedSources = MerchantMasterDB.superListSources
	local function showsAcquisitionCost(source, needle)
		MerchantMasterDB.superListSources = { [source] = true }
		SlashCmdList.MERCHANTMASTER("recipes")
		for _, row in ipairs(ns.app.ui.recipesTable.scrollBox._frames or {}) do
			if row.data and row.data.sourceBucket == source then
				local cellsByKey = row.cellGroup and row.cellGroup.cellsByKey
				local nameCell = cellsByKey and cellsByKey.name
				check(row._scripts.OnEnter == nil, "All Recipes row has no item tooltip handler")
				check(nameCell and nameCell:GetScript("OnEnter"), "All Recipes item name has a tooltip handler")
				for key, cell in pairs(cellsByKey) do
					if key ~= "name" and key ~= "demandSort" then
						check(cell:GetScript("OnEnter") == nil, "All Recipes " .. key .. " cell has no item tooltip handler")
					end
				end
				GameTooltip:ClearLines()
				nameCell:GetScript("OnEnter")(nameCell)
				for _, line in ipairs(GameTooltip._lines or {}) do
					if line:find("Actual Source Cost:", 1, true) and line:find(needle, 1, true) then return true end
				end
			end
		end
		return false
	end
	check(showsAcquisitionCost("vendor", "|c"), "All Recipes tooltip displays the NPC vendor coin cost")
	check(showsAcquisitionCost("merchant", "Favor"), "All Recipes tooltip displays the Merchant's Favor cost")
	GameTooltip:Hide()
	MerchantMasterDB.superListSources = savedSources
end

---------------------------------------------------------------------------------------------------
-- 14. v3.0.0 Verification: Executive Dashboard, 4 Menus + Left Sidebar, Profit Spread, Outliers,
--     Simplify Overview, Detachable Shopping Window, Writ Pouch (~40s) & Turn-In Area Multi-Buy
---------------------------------------------------------------------------------------------------

-- 14a. Full Addon Load -> /mm opens Dashboard at 1840x730
_G.MerchantMasterPanel:Hide()
_G.MerchantMasterDB.window = {}
_G.MerchantMasterDB.activeTab = "dashboard"
SlashCmdList.MERCHANTMASTER("")
check(_G.MerchantMasterPanel:IsShown() == true, "/mm shows MerchantMasterPanel")
check(_G.MerchantMasterDB.activeTab == "dashboard", "/mm opens on Executive Dashboard")
local measuredDefault=268+4
for _,column in ipairs(ns.app.ui.recipesTable.columns) do measuredDefault=measuredDefault+column.minWidth+5 end
measuredDefault=math.max(1840,measuredDefault)
check(_G.MerchantMasterPanel:GetWidth() == measuredDefault and _G.MerchantMasterPanel:GetHeight() == 730,
	string.format("Window uses measured default %dx730 (got %dx%d)", measuredDefault, _G.MerchantMasterPanel:GetWidth(), _G.MerchantMasterPanel:GetHeight()))

-- 14b. Profit Spread (Daily Income Plan) + Spread Shopping List
local spreadRows, spreadSummary = ns.BuildProfitSpreadRows({
	spreadCount = 8,
	diversifyProfs = true,
	applyAHCut = true,
})
check(#spreadRows > 0 and spreadSummary.planCount > 0 and spreadSummary.planCount <= 8,
	"BuildProfitSpreadRows builds Top 8 Daily Spread Plan (" .. tostring(spreadSummary.planCount) .. " in plan)")
for _, sr in ipairs(spreadRows) do
	check(sr.recDailyQty >= 1 and sr.recDailyQty <= 40, "recDailyQty clamped in [1..40]")
	check(sr.expectedDailyProfit == math.max(1, math.floor(sr.realizedProfit * sr.expectedDailySales + 0.5)), "expectedDailyProfit matches realizedProfit * expectedDailySales")
end
local spreadShop = ns.BuildSpreadShoppingList(spreadRows, spreadSummary, {})
check(#spreadShop.targets == spreadSummary.planCount and #spreadShop.shoppingList > 0,
	"BuildSpreadShoppingList aggregates materials across Top N daily spread crafts")

-- 14c. Outliers (Set Your Own Price) + ParseMoneyInput / FormatMoneyEdit
check(ns.ParseMoneyInput("12g 50s") == 125000, "ParseMoneyInput('12g 50s') == 125000c")
check(ns.ParseMoneyInput("45s") == 4500, "ParseMoneyInput('45s') == 4500c")
check(ns.ParseMoneyInput("2.5") == 25000, "ParseMoneyInput('2.5') == 2.5g (25000c)")
check(ns.FormatMoneyEdit(125000) == "12g 50s", "FormatMoneyEdit(125000) == '12g 50s'")

local outlierRows, outlierSummary = ns.BuildOutlierRows({
	outlierScope = "monopoly",
	outlierQuality = "good",
	outlierPrices = { [250335] = 185000 }, -- 18g 50s custom price
})
check(#outlierRows > 0 and outlierSummary.totalMatched == #outlierRows, "BuildOutlierRows returns monopoly outliers")
local dashIns = ns.BuildDashboardInsights({
	dashboardScope = "smart",
	outlierPrices = { [250335] = 185000 },
})
check(dashIns ~= nil and type(dashIns.topCrafts) == "table" and type(dashIns.topOutliers) == "table",
	"BuildDashboardInsights returns topCrafts, topOutliers & adviceShoppingList")

-- 14d. Craftsman's Writ Tiered Coin Pouch (3536c Journeyman / 7480c Expert & Artisan) + Turn-In Area Filtering & Multi-Buy
local testWrit = ns.WRITS[1]
do
local sampleWrit75, sampleWrit125, sampleWrit200
for _, w in ipairs(ns.WRITS) do
	if w.rep == 75 and not sampleWrit75 then sampleWrit75 = w end
	if w.rep == 125 and not sampleWrit125 then sampleWrit125 = w end
	if w.rep == 200 and not sampleWrit200 then sampleWrit200 = w end
end
check(sampleWrit75 ~= nil and sampleWrit125 ~= nil and sampleWrit200 ~= nil,
	"Catalog includes Journeyman (+75), Expert (+125), and Artisan (+200) Craftsman's Writs")

local c75, id75, tier75 = ns.GetWritPouchInfo(sampleWrit75)
local c125, id125, tier125 = ns.GetWritPouchInfo(sampleWrit125)
local c200, id200, tier200 = ns.GetWritPouchInfo(sampleWrit200)
check(c75 == 3536 and id75 == 284584 and tier75 == "Journeyman",
	"Journeyman Writ (+75 Rep) maps to Coin Pouch 284584 with 3536c (35s 36c)")
check(c125 == 7480 and id125 == 284585 and tier125 == "Expert",
	"Expert Writ (+125 Rep) maps to Coin Pouch 284585 with 7480c (74s 80c)")
check(c200 == 7480 and id200 == 284586 and tier200 == "Artisan",
	"Artisan Writ (+200 Rep) maps to Coin Pouch 284586 with 7480c (74s 80c)")

check(ns.GetWritPouchRefund(sampleWrit75, { includeWritPouch = true }) == 3536,
	"Journeyman Craftsman's Writ Pouch refund is 3536c (35s 36c)")
check(ns.GetWritPouchRefund(sampleWrit125, { includeWritPouch = true }) == 7480,
	"Expert Craftsman's Writ Pouch refund is 7480c (74s 80c)")
check(ns.GetWritPouchRefund(sampleWrit200, { includeWritPouch = true }) == 7480,
	"Artisan Craftsman's Writ Pouch refund is 7480c (74s 80c)")
check(ns.GetWritPouchRefund(sampleWrit125, { includeWritPouch = false }) == 0,
	"Writ Pouch refund is 0c when includeWritPouch == false")

-- Legacy SavedVariables writPouchCopper = 4000 must never override tiered Coin Pouch values
MerchantMasterDB.writPouchCopper = 4000
check(ns.GetWritPouchRefund(sampleWrit125, { includeWritPouch = true }) == 7480,
	"Legacy MerchantMasterDB.writPouchCopper = 4000 does not override tiered 7480c Expert Coin Pouch")
MerchantMasterDB.writPouchCopper = nil

local writZones = ns.GetWritZones()
check(#writZones >= 2 and writZones[1].key == "all" and writZones[2].key == "mapped",
	"GetWritZones returns Area filter menu options starting with 'all' and 'mapped'")

-- Price a sample Journeyman Writ at 25s scroll + 10s item = 35s (3500c) gross -> -36c NET PROFIT with 35s 36c (3536c) Coin Pouch!
testWrit = sampleWrit75
mockTSMPrices.dbminbuyout[testWrit.itemID] = 2500 -- 25s writ scroll
mockTSMPrices.dbminbuyout[testWrit.requiredItemID] = math.floor(1000 / math.max(1, testWrit.qty or 1))
mockTSMPrices.dbminbuyout[sampleWrit125.itemID] = 4000
mockTSMPrices.dbminbuyout[sampleWrit125.requiredItemID] = math.floor(2000 / math.max(1, sampleWrit125.qty or 1))
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

local wRowsPouch, bestWritPouch, _, _, nearZeroCount = ns.BuildWritRows({
	writMode = "buy",
	includeWritPouch = true,
	writTurnInQueue = { [testWrit.itemID] = 2 },
})
local wRowsNoPouch = ns.BuildWritRows({
	writMode = "buy",
	includeWritPouch = false,
})
local twPouch, twNoPouch, twExpertPouch
for _, r in ipairs(wRowsPouch) do
	if r.writID == testWrit.itemID then twPouch = r end
	if r.writID == sampleWrit125.itemID then twExpertPouch = r end
end
for _, r in ipairs(wRowsNoPouch) do if r.writID == testWrit.itemID then twNoPouch = r; break end end
check(twPouch ~= nil and twNoPouch ~= nil and twExpertPouch ~= nil, "Located Journeyman & Expert Writs in BuildWritRows")
check(twPouch.pouchRefund == 3536 and twPouch.pouchTier == "Journeyman" and twNoPouch.pouchRefund == 0,
	"Journeyman pouchRefund is 3536c when enabled and 0c when disabled")
check(twExpertPouch.pouchRefund == 7480 and twExpertPouch.pouchTier == "Expert",
	"Expert pouchRefund is 7480c (74s 80c) in BuildWritRows")
check(twPouch.totalPrice == twPouch.grossTotal - 3536, "Net totalPrice deducts 3536c Journeyman Coin Pouch refund from grossTotal")
check(twExpertPouch.totalPrice == twExpertPouch.grossTotal - 7480, "Net totalPrice deducts 7480c Expert Coin Pouch refund from grossTotal")
check(twPouch.totalPrice < 0 and twPouch.nearZero == true and nearZeroCount >= 1,
	"35s Gross Journeyman Writ with 35s 36c Pouch refund yields negative Net Total (-36c profit!) and flags nearZero")
check(twPouch.queuedCount == 2, "BuildWritRows populates queuedCount from writTurnInQueue")

local turnInShop = ns.BuildWritTurnInShoppingList(wRowsPouch, { [testWrit.itemID] = 2, [sampleWrit125.itemID] = 1 }, {
	writMode = "buy",
	includeWritPouch = true,
})
check(turnInShop.hasQueue == true and turnInShop.writCount == 3, "BuildWritTurnInShoppingList builds for 3 queued Writs (2 Journeyman + 1 Expert)")
local expectedMixedPouch = (2 * 3536) + 7480
check(turnInShop.pouchRefundTotal == expectedMixedPouch and turnInShop.netCost == turnInShop.grossSpend - expectedMixedPouch,
	"BuildWritTurnInShoppingList sums exact tiered Coin Pouch refunds (2x 3536c + 1x 7480c = 14552c)")
check(turnInShop.totalRep == (2 * testWrit.rep + sampleWrit125.rep) and #turnInShop.shoppingList >= 2,
	"BuildWritTurnInShoppingList computes totalRep and shoppingList rows for Writ scrolls + Turn-In items")

-- Regression #2: Queued writs from another Area/filter never vanish when writRows is filtered!
local testWrit2 = ns.WRITS[2]
mockTSMPrices.dbminbuyout[testWrit2.itemID] = 1800
mockTSMPrices.dbminbuyout[testWrit2.requiredItemID] = 900
local crossAreaShop = ns.BuildWritTurnInShoppingList({ twPouch }, { [testWrit.itemID] = 1, [testWrit2.itemID] = 1 }, {
	writMode = "buy",
	includeWritPouch = true,
})
check(#crossAreaShop.targets == 2 and crossAreaShop.writCount == 2,
	"BuildWritTurnInShoppingList preserves queued Writs outside the currently filtered writRows")

-- Regression #8: Whole-batch craftCost in BuildWritRows when recipe numMade > 1 and writ.qty < numMade (e.g. Silver Skeleton Key)
local multiMadeWrit
for _, w in ipairs(ns.WRITS) do
	if (w.numMade or 1) > 1 and (w.qty or 1) < (w.numMade or 1) then
		multiMadeWrit = w
		break
	end
end
if multiMadeWrit then
	for _, rg in ipairs(multiMadeWrit.reagents or {}) do
		mockTSMPrices.dbminbuyout[rg[1]] = 500
	end
	local mmRows = ns.BuildWritRows({ search = multiMadeWrit.name, writMode = "craft" })
	local mmRow
	for _, r in ipairs(mmRows) do if r.writID == multiMadeWrit.itemID then mmRow = r; break end end
	local unitC = ns.ComputeSmartCraftCost(multiMadeWrit.reagents, multiMadeWrit.numMade, multiMadeWrit.requiredItemID, { parentProf = multiMadeWrit.prof })
	local expectedBatchCost = unitC * multiMadeWrit.numMade * math.ceil((multiMadeWrit.qty or 1) / multiMadeWrit.numMade)
	check(mmRow ~= nil and mmRow.craftCost == expectedBatchCost,
		"BuildWritRows charges whole crafting batch for multi-made Writ item (" .. tostring(mmRow and mmRow.craftCost) .. " == " .. tostring(expectedBatchCost) .. ")")
end

-- Regression #9: Unpriced Writ in BuildWritTurnInShoppingList reports nil grossSpend/netCost (never -4000c)
local unpricedWrit = ns.WRITS[#ns.WRITS]
mockTSMPrices.dbminbuyout[unpricedWrit.itemID] = nil
mockTSMPrices.dbmarket[unpricedWrit.itemID] = nil
-- AppHelper refreshes on disk; this fixture must stay unpriced in every source.
local pricedMarketLookup = ns.GetItemMarketPrice
ns.GetItemMarketPrice = function(itemID, ...)
	if itemID == unpricedWrit.itemID then return nil end
	return pricedMarketLookup(itemID, ...)
end
local unpricedShop = ns.BuildWritTurnInShoppingList(wRowsPouch, { [unpricedWrit.itemID] = 1 }, {
	writMode = "buy",
	includeWritPouch = true,
})
check(unpricedShop.missingPriceCount > 0 and unpricedShop.grossSpend == nil and unpricedShop.netCost == nil,
	"BuildWritTurnInShoppingList sets grossSpend=nil and netCost=nil when prices are missing")
ns.GetItemMarketPrice = pricedMarketLookup

-- Verify SolveRepShoppingList & BuildReputationOverview include tiered Coin Pouch refunds
local repWithPouch = ns.SolveRepShoppingList({ targetStanding = 6, writMode = "buy", includeWritPouch = true, respectStock = false })
local repNoPouch   = ns.SolveRepShoppingList({ targetStanding = 6, writMode = "buy", includeWritPouch = false, respectStock = false })
local expectedPlanPouch = 0
for _, entry in ipairs(repWithPouch.writPlan or {}) do
	expectedPlanPouch = expectedPlanPouch + (entry.count * ns.GetWritPouchRefund(entry.writ, { includeWritPouch = true }))
end
check(repWithPouch.pouchRefund > 0 and repWithPouch.pouchRefund == expectedPlanPouch,
	"SolveRepShoppingList sums exact tiered Coin Pouch refunds across writPlan")
check(repWithPouch.totalCost == repWithPouch.grossSpend - repWithPouch.pouchRefund,
	"SolveRepShoppingList net totalCost = grossSpend - pouchRefund")
check(repNoPouch.pouchRefund == 0 and repNoPouch.totalCost == repNoPouch.grossSpend,
	"SolveRepShoppingList with includeWritPouch=false has 0 pouchRefund")
end

-- 14f. Exercise all 4 Top Menus, all Sub-Tabs, Detachable Shopping Window & Queue Area Writs
for _, nav in ipairs({
	"dash", "profit", "spread", "outliers", "recipes", "writprofit", "cratemats",
	"token", "crates", "favorcalc", "reputation", "writs", "rep", "repcalc", "shop",
}) do
	SlashCmdList.MERCHANTMASTER(nav)
end
check(_G.MerchantMasterShoppingWindow ~= nil and _G.MerchantMasterShoppingWindow:GetWidth() == 1160 and _G.MerchantMasterShoppingWindow:GetHeight() == 720,
	"Detachable MerchantMasterShoppingWindow created at 1160x720")

-- Regression #1, #3, #4, #5, #6: Verify searchBox width, short Src/Area button text, empty Queue text & [Queue Area Writs] guard
wipe(MerchantMasterDB.writTurnInQueue)
MerchantMasterDB.writZoneFilter = "all"
SlashCmdList.MERCHANTMASTER("writs")

local qBtnWidget = nil
for _, f in ipairs(createdFrames) do
	local lbl = (f._mmLabel and f._mmLabel._text) or f._text or ""
	if lbl == "Queue Area Writs" and f._scripts and f._scripts.OnClick then
		qBtnWidget = f
		break
	end
end
check(qBtnWidget ~= nil, "Found [Queue Area Writs] button")
-- With zoneFilter == "all", clicking [Queue Area Writs] refuses to queue all 150 writs:
qBtnWidget:Click("LeftButton")
check(next(MerchantMasterDB.writTurnInQueue or {}) == nil,
	"[Queue Area Writs] refuses 'all' filter without queueing all writs")

-- Now select a specific Turn-In Area (testWrit's zone, or 'Alterac Mountains' fallback) and click [Queue Area Writs]:
local targetZone = (testWrit.zone and testWrit.zone ~= "" and testWrit.zone ~= "Unmapped") and testWrit.zone or "Alterac Mountains"
testWrit.zone = targetZone
MerchantMasterDB.writZoneFilter = targetZone
SlashCmdList.MERCHANTMASTER("writs")
qBtnWidget:Click("LeftButton")
check(MerchantMasterDB.writTurnInQueue[testWrit.itemID] == 1,
	"Clicking [Queue Area Writs] with Area='" .. targetZone .. "' queues priced Writs in that Area")
MerchantMasterDB.writZoneFilter = "all"
wipe(MerchantMasterDB.writTurnInQueue)
SlashCmdList.MERCHANTMASTER("writs")

-- 14g. Verify zero duplicate visible FontStrings on CheckButtons & zero banned Unicode glyphs
for _, f in ipairs(createdFrames) do
	if f:GetObjectType() == "CheckButton" then
		local visCount = 0
		for _, reg in ipairs(f._regions or {}) do
			if reg:GetObjectType() == "FontString" and reg:IsShown() and (reg:GetText() or "") ~= "" then
				visCount = visCount + 1
			end
		end
		check(visCount <= 1, "CheckButton has at most 1 visible non-empty FontString, got " .. visCount)
	end
end

---------------------------------------------------------------------------------------------------
-- 15. Dashboard Hot/Cold + AH Qty, Make Profit AH Qty & Hot/Cold Ratio, and Clickable [WH] Wowhead Links
---------------------------------------------------------------------------------------------------
do
-- 15a. 100% Wowhead Forever URL coverage across all non-gather Recipes (2,043) & all Writs (150)
local nonGatherRecCount, recWithWhUrl, itemUrlCount, spellUrlCount = 0, 0, 0, 0
for _, rec in ipairs(ns.RECIPES) do
	local url, lbl, kind = ns.GetRecipeWowheadURL(rec)
	if rec.source == "gather" or rec.acqType == "gather" then
		check(url == nil, "Gather entry returns nil Wowhead URL")
	else
		nonGatherRecCount = nonGatherRecCount + 1
		if url and url:find("^https://www%.wowhead%.com/forever/") and lbl and lbl ~= "" then
			recWithWhUrl = recWithWhUrl + 1
		end
		if rec.recipeItemID and rec.recipeItemID > 0 then
			check(url == "https://www.wowhead.com/forever/item=" .. tostring(rec.recipeItemID) and kind == "item",
				"Scroll recipe uses forever/item=<recipeItemID>: " .. tostring(url))
			itemUrlCount = itemUrlCount + 1
		elseif rec.spellID and rec.spellID > 0 then
			check(url == "https://www.wowhead.com/forever/spell=" .. tostring(rec.spellID) and kind == "spell",
				"Trainer/Spell recipe uses forever/spell=<spellID>: " .. tostring(url))
			spellUrlCount = spellUrlCount + 1
		end
	end
end
check(nonGatherRecCount == COUNTS.totalRecipes and recWithWhUrl == COUNTS.totalRecipes,
	string.format("100%% of non-gather recipes have valid Wowhead Forever URLs (%d/%d; %d item, %d spell)",
		recWithWhUrl, nonGatherRecCount, itemUrlCount, spellUrlCount))

local writWithWhUrl = 0
for _, w in ipairs(ns.WRITS) do
	local url, lbl, kind = ns.GetRecipeWowheadURL(w)
	if url and url:find("^https://www%.wowhead%.com/forever/") and lbl and lbl ~= "" then
		writWithWhUrl = writWithWhUrl + 1
	end
	local ca = ns.EvaluateCraftAbility(w, {}, { standing = 4 })
	check(ca.wowheadURL == url and ca.wowheadKind == kind, "EvaluateCraftAbility attaches wowheadURL & wowheadKind on Writ")
end
check(writWithWhUrl == 150, "100% of Writs have valid Wowhead Forever URLs (" .. writWithWhUrl .. "/150)")

-- 15b. Crate Materials & Profit Spread attach demand / Hot-Cold ratio & honor demandFilter
local cmAll = ns.BuildCrateMaterialRows({ profFilter = "all", unlockFilter = "all" })
check(#cmAll > 0, "BuildCrateMaterialRows returns rows")
for _, cmr in ipairs(cmAll) do
	check(cmr.demand ~= nil and cmr.demandSort == cmr.demand.demandScore and cmr.listedSort ~= nil,
		"Crate Material row attaches demand, demandSort & listedSort")
end
local cmHot = ns.BuildCrateMaterialRows({ profFilter = "all", unlockFilter = "all", demandFilter = "hot" })
for _, cmr in ipairs(cmHot) do
	check(cmr.demand.isHot == true, "Crate Material demandFilter='hot' keeps only hot/favorable/monopoly rows")
end

local psHot = ns.BuildProfitSpreadRows({ demandFilter = "hot" })
for _, psr in ipairs(psHot) do
	check(psr.demand ~= nil and psr.demand.isHot == true, "Profit Spread demandFilter='hot' keeps only hot rows")
end

-- 15c. Dashboard displays Hot/Cold ratio + Current AH Qty + Sales/Day + [WH] button on missing recipes
MerchantMasterDB.dashboardScope = "all"
SlashCmdList.MERCHANTMASTER("")
local appTbl = ns.app
if appTbl and appTbl.ui and appTbl.ui.dashCraftRows and appTbl.ui.dashCraftRows[1] and appTbl.ui.dashCraftRows[1].data then
	local cRow1 = appTbl.ui.dashCraftRows[1]
	local subTxt = cRow1.subFs:GetText() or ""
	check(subTxt:find("AH", 1, true) ~= nil and subTxt:find("/d", 1, true) ~= nil,
		"Dashboard Top 5 Craft row displays Current AH Qty and Sales/Day: " .. subTxt)
	local d1 = cRow1.data
	if d1.demand and d1.demand.heatBadge then
		check(subTxt:find(d1.demand.heatBadge, 1, true) ~= nil,
			"Dashboard Top 5 Craft row displays Hot/Cold badge: " .. tostring(d1.demand.heatBadge))
	end
end

-- 15d. Click [WH] button to open MerchantMasterWowheadWindow with pre-filled Wowhead Forever URL
check(_G.MerchantMasterWowheadWindow ~= nil, "MerchantMasterWowheadWindow frame created")
SlashCmdList.MERCHANTMASTER("spread")
local clickedWhBtn = false
for _, f in ipairs(createdFrames) do
	if f._regions then
		for _, reg in ipairs(f._regions) do
			if reg.GetText and (reg:GetText() or ""):find("WH", 1, true) and f:IsShown() and f._scripts and f._scripts.OnClick then
				if f._scripts.OnEnter then f._scripts.OnEnter(f) end
				f:Click("LeftButton")
				clickedWhBtn = true
				break
			end
		end
	end
	if clickedWhBtn then break end
end
check(clickedWhBtn == true, "Found and clicked a visible [WH] button on unlearned recipe row")
check(_G.MerchantMasterWowheadWindow:IsShown() == true, "Clicking [WH] opens MerchantMasterWowheadWindow")
local whUrlBoxText = nil
for _, f in ipairs(createdFrames) do
	if f:GetObjectType() == "EditBox" and f:GetParent() == _G.MerchantMasterWowheadWindow.body then
		whUrlBoxText = f:GetText()
		break
	end
end
check(type(whUrlBoxText) == "string" and whUrlBoxText:find("^https://www%.wowhead%.com/forever/") ~= nil,
	"MerchantMasterWowheadWindow EditBox pre-filled with Wowhead Forever URL: " .. tostring(whUrlBoxText))
_G.MerchantMasterWowheadWindow:Hide()

-- 15e. Verify every table stays <= 1,048px and Make Profit exposes AH Qty & Hot/Cold
if appTbl and appTbl.ui then
	local profitTables = {
		{ name = "profitSpreadTable", tbl = appTbl.ui.profitSpreadTable },
		{ name = "outliersTable",     tbl = appTbl.ui.outliersTable },
		{ name = "recipesTable",      tbl = appTbl.ui.recipesTable },
	}
	for _, entry in ipairs(profitTables) do
		local cols = entry.tbl and entry.tbl.columns
		check(type(cols) == "table" and #cols >= 7, entry.name .. " has columns")
		local sumW = 0
		local hasQty, hasHeat = false, false
		for _, c in ipairs(cols) do
			sumW = sumW + c.width
			if c.key == "listed" or c.key == "listedSort" or (entry.name == "recipesTable" and c.key == "ownedOutputQty") then hasQty = true end
			if c.key == "demandSort" then hasHeat = true end
		end
		local totalPx = 4 + sumW + (#cols - 1) * 5
		local viewport=entry.name=='recipesTable' and (appTbl.panel:GetWidth()-268) or 1048
		check(totalPx <= viewport, string.format("%s width %dpx <= viewport %dpx", entry.name, totalPx,viewport))
		check(hasQty and hasHeat, entry.name .. " includes both AH Qty and Hot/Cold columns")
	end
end
end

---------------------------------------------------------------------------------------------------
-- 16. Unlisted Empty Valuation, Last Known AH Price, Bold White UNLISTED & Known Recipes Mode
---------------------------------------------------------------------------------------------------
do
	local appTbl = ns.app
	local econ = ns.CurrentEconomyInfo().effectiveKey
	MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
	local prevEcon = MerchantMasterDB.ahPrices[econ]
	local prevOutliers = MerchantMasterDB.outlierPrices

	-- 16a. ResolveOutputSaleValuation: Unlisted = empty ("" / nil), Vendor ONLY when listed AH net < vendor, Custom Price overrides unlisted
	MerchantMasterDB.ahPrices[econ] = {
		[250335] = { absent = true, qty = 0, lastPrice = 42500, lastAt = _G.time() - 3600, at = _G.time() },
	}
	MerchantMasterDB.outlierPrices = {}
	mockVendorSell[250335] = 1500
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()

	local lkPrice, lkSrc = ns.GetLastKnownAHPrice(250335)
	check(lkPrice == 42500 and lkSrc == "Last Seen AH", "GetLastKnownAHPrice recovers preserved lastPrice (4g 25s) from absent AH scan")

	local uVal = ns.ResolveOutputSaleValuation(250335, 0, true, 15000, true, {})
	check(uVal.isUnlisted == true and uVal.ahValue == nil and uVal.profit == nil and uVal.ahSource == nil,
		"Unlisted item without custom price leaves ahValue & profit nil (never NPC vendor sell!)")
	check(uVal.lastKnownPrice == 42500, "Unlisted valuation attaches lastKnownPrice = 42500")

	-- Custom market price set on unlisted item
	local cVal = ns.ResolveOutputSaleValuation(250335, 0, true, 15000, true, { [250335] = 50000 })
	check(cVal.isCustomPrice == true and cVal.ahValue == 50000 and cVal.ahSource == "Custom Price" and cVal.profit == 32500,
		"Unlisted item with custom price 5g values at 5g gross / +3g 25s net profit after 5% AH cut")

	-- Listed item where AH net < vendorSell -> Vendor applies; when AH net >= vendorSell -> AH applies
	local vendorItemID = nil
	for _, r in ipairs(ns.RECIPES) do
		if r.outputItemID and ns.IsItemSellable(r.outputItemID) then
			vendorItemID = r.outputItemID
			break
		end
	end
	check(vendorItemID ~= nil, "Found tradeable recipe output item")
	mockVendorSell[vendorItemID] = 1200
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()
	local vFloor = ns.GetVendorSellPrice(vendorItemID)
	check(vFloor and vFloor >= 500, "Tradeable recipe output has NPC vendor sell >= 5s")
	MerchantMasterDB.ahPrices[econ][vendorItemID] = { price = math.max(10, math.floor(vFloor * 0.6)), qty = 8, absent = false, at = _G.time() }
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()
	local belowVal = ns.ResolveOutputSaleValuation(vendorItemID, 8, true, 100, true, {})
	check(belowVal.isUnlisted == false and belowVal.usedVendorFloor == true and belowVal.ahSource == "Vendor" and belowVal.ahValue == vFloor,
		"Vendor sale price applies when active AH net price is below vendor floor")

	MerchantMasterDB.ahPrices[econ][vendorItemID] = { price = vFloor * 3, qty = 8, absent = false, at = _G.time() }
	ns.ResetEval()
	ns.InvalidatePriceCache()
	ns.BeginEval()
	local aboveVal = ns.ResolveOutputSaleValuation(vendorItemID, 8, true, 100, true, {})
	check(aboveVal.isUnlisted == false and aboveVal.usedVendorFloor == false and aboveVal.ahSource ~= "Vendor" and aboveVal.ahValue == vFloor * 3,
		"Active AH price applies when AH net price is above vendor floor")
	ns.ResetEval()

	-- 16b. Outliers table Last AH column + [Last AH] quick-fill button + Bold White UNLISTED font flag
	SlashCmdList.MERCHANTMASTER("outliers")
	check(appTbl.ui.outlierLastAHBtn ~= nil, "Outliers custom price bar has [Last AH] quick-fill button")
	local hasLastAHCol = false
	for _, c in ipairs(appTbl.ui.outliersTable.columns) do
		if c.key == "lastKnownSort" and c.label == "Last AH" then hasLastAHCol = true end
	end
	check(hasLastAHCol == true, "Outliers table includes 'Last AH' column")

	-- 16c. Known Recipes menu option across Sidebar, Recipes, Writ Crafts, Crate Mats & Dashboard (Can Do vs Potential)
	check(appTbl.ui.knownRecipesCheck ~= nil, "Left Sidebar has 'Known Recipes' switch")
	SlashCmdList.MERCHANTMASTER("known")
	check(MerchantMasterDB.knownRecipesOnly == true and MerchantMasterDB.unlockFilter == "known",
		"/mm known enables Known Recipes Only mode")
	local knRecRows = ns.BuildRecipeRows({ knownRecipesOnly = true, profFilter = "all" })
	for _, kr in ipairs(knRecRows) do
		check(kr.unlock and kr.unlock.known == true, "BuildRecipeRows(knownRecipesOnly=true) returns only known recipes")
	end
	local knWritRows = ns.BuildWritProfitRows({ knownRecipesOnly = true, profFilter = "all" })
	for _, kw in ipairs(knWritRows) do
		check(kw.canCraft == true, "BuildWritProfitRows(knownRecipesOnly=true) returns only known craftable writs")
	end
	local insKnown = ns.BuildDashboardInsights({ dashboardScope = "known" })
	local insPot = ns.BuildDashboardInsights({ dashboardScope = "potential" })
	check(type(insKnown.knownProfitPerDay) == "number" and type(insKnown.potentialProfitPerDay) == "number",
		"BuildDashboardInsights computes both knownProfitPerDay (Can Do) and potentialProfitPerDay (Potential)")
	check(insPot.potentialProfitPerDay >= insKnown.knownProfitPerDay,
		"Potential daily profit >= Known (Can Do) daily profit")
	SlashCmdList.MERCHANTMASTER("")
	local subProfitTxt = appTbl.ui.dashRoiFs and appTbl.ui.dashRoiFs:GetText() or ""
	check(subProfitTxt:find("Known (Can Do):", 1, true) ~= nil and subProfitTxt:find("Potential:", 1, true) ~= nil,
		"Dashboard KPI card displays side-by-side 'Known (Can Do)' vs 'Potential': " .. subProfitTxt)

	-- Restore state
	SlashCmdList.MERCHANTMASTER("known")
	check(MerchantMasterDB.knownRecipesOnly == false, "Second /mm known disables Known Recipes Only mode")
	mockVendorSell[250335] = nil
	mockVendorSell[vendorItemID] = nil
	MerchantMasterDB.ahPrices[econ] = prevEcon
	MerchantMasterDB.outlierPrices = prevOutliers
	ns.InvalidatePriceCache()
end

-- v3.1.0: zone precedence, confirmed filters, hints, and companion isolation.
do
	local savedLearned, savedHints, savedWrits = MerchantMasterDB.learnedWritZones, ns.WRIT_ZONE_HINTS, ns.WRITS
	local writ = { itemID = 999001, zone = "  Feralas  ", npc = "Static NPC", x = 10, y = 20 }
	MerchantMasterDB.learnedWritZones = { [writ.itemID] = { zone = " Tanaris ", npc = "Learned NPC", x = 30, y = 40 } }
	ns.WRIT_ZONE_HINTS = { [writ.itemID] = " Badlands " }
	local z, src, npc, x, y = ns.GetWritZoneInfo(writ)
	check(z == "Feralas" and src == "static" and npc == "Static NPC" and x == 10 and y == 20,
		"Trimmed static zone and coordinates win over learned zone and hint")
	writ.zone = "Unknown"
	z, src, npc, x, y = ns.GetWritZoneInfo(writ)
	check(z == "Tanaris" and src == "learned" and npc == "Learned NPC" and x == 30 and y == 40,
		"Trimmed learned zone and coordinates win over hint")
	check(ns.GetWritZoneLabel(writ) == "Tanaris" and ns.MatchesWritZoneFilter(writ, "mapped"),
		"Learned zones are confirmed area filters")
	MerchantMasterDB.learnedWritZones[writ.itemID] = { zone = "Tanaris", x = 0 }
	z, src, npc, x, y = ns.GetWritZoneInfo(writ)
	check(npc == "Static NPC" and x == 0 and y == 20, "Missing learned details fall back without replacing zero")
	for _, invalid in ipairs({ "", "   ", " Unknown ", " Unmapped " }) do
		writ.zone = invalid
		MerchantMasterDB.learnedWritZones[writ.itemID] = { zone = invalid }
		z, src = ns.GetWritZoneInfo(writ)
		check(z == "Badlands" and src == "hint", "Invalid static and learned zones fall through to trimmed hint")
	end
	check(ns.GetWritZoneLabel(writ) == "Unmapped" and not ns.MatchesWritZoneFilter(writ, "Badlands"),
		"Hints stay out of confirmed area filters")
	check(ns.MatchesWritZoneFilter(writ, "unmapped"), "Hints remain in the Unmapped filter")
	ns.WRIT_ZONE_HINTS[writ.itemID] = " "
	z, src, npc, x, y = ns.GetWritZoneInfo(writ)
	check(z == "Unmapped" and src == "unmapped" and npc == nil and x == nil and y == nil,
		"Empty hint returns unmapped without location details")
	z, src = ns.GetWritZoneInfo(nil)
	check(z == "Unmapped" and src == "unmapped", "Nil writ resolves to unmapped")
	MerchantMasterDB.learnedWritZones[writ.itemID] = { zone = false }
	ns.WRIT_ZONE_HINTS[writ.itemID] = false
	check(select(2, ns.GetWritZoneInfo(writ)) == "unmapped", "Non-string zone entries are ignored")

	local stoneshield
	for _, w in ipairs(savedWrits) do if w.itemID == 264058 then stoneshield = w end end
	MerchantMasterDB.learnedWritZones[264058] = { zone = "Mulgore", source = "quest_accept" }
	z, src, npc, x, y = ns.GetWritZoneInfo(stoneshield)
	check(z == "Dustwallow Marsh" and src == "static" and npc == "Mudcrush Durtfeet" and x == 35.15 and y == 38.26,
		"Lesser Stoneshield Potion keeps the confirmed area despite a stale learned Mulgore waypoint")
	ns.WRITS = { stoneshield }
	local stoneshieldRows = ns.BuildWritRows({ zoneFilter = "Dustwallow Marsh", profFilter = "all", unlockFilter = "all" })
	check(stoneshieldRows[1] and stoneshieldRows[1].areaDisplay == "|cff88ddffDustwallow Marsh|r",
		"Lesser Stoneshield Potion displays the confirmed area in blue")
	local soulPouch
	for _, w in ipairs(savedWrits) do if w.itemID == 264160 then soulPouch = w end end
	z, src, npc, x, y = ns.GetWritZoneInfo(soulPouch)
	check(z == "Winterspring" and src == "static" and npc == "Zelizax" and x == 57.62 and y == 88.08,
		"Soul Pouch resolves its confirmed Zelizax turn-in in Winterspring")
	local partialWrit = { itemID = 999002, questID = 999002, name = "Partial Fixture", zone = "Winterspring" }
	MerchantMasterDB.learnedWritZones[999002] = { zone = " Winterspring ", npc = "Learned NPC", x = 30, y = 40, source = "turnin" }
	z, src, npc, x, y = ns.GetWritZoneInfo(partialWrit)
	check(z == "Winterspring" and src == "static" and npc == "Learned NPC" and x == 30 and y == 40,
		"Learned details fill missing fields within the confirmed zone")
	MerchantMasterDB.learnedWritZones = true
	check(select(2, ns.GetWritZoneInfo(stoneshield)) == "static", "Non-table learned storage leaves the confirmed zone available")
	MerchantMasterDB.learnedWritZones, ns.WRIT_ZONE_HINTS = savedLearned, savedHints
	ns.WRITS = savedWrits

	local learnedZones = {}
	for _, transitZone in ipairs({ " Mulgore ", "Thunder Bluff", "Orgrimmar", "Durotar", "Stormwind City" }) do
		learnedZones[transitZone] = { zone = transitZone, source = "quest_accept" }
	end
	local turnin = { zone = "Mulgore", source = "turnin" }
	local unsourced = { zone = "Stormwind City", npc = "Learned NPC" }
	learnedZones.destination = { zone = "Dustwallow Marsh", source = "quest_accept" }
	learnedZones.mapPin = { zone = "Feralas", source = "bettermaps" }
	learnedZones.turnin, learnedZones.unsourced = turnin, unsourced
	ns.SanitizeLearnedWritZones(learnedZones)
	for key in pairs(learnedZones) do
		check(key == "turnin" or key == "unsourced", "Sanitizer removes quest-accept and BetterMaps locations " .. key)
	end
	check(learnedZones.turnin == turnin and learnedZones.unsourced == unsourced,
		"Sanitizer preserves turn-ins and unsourced entries")

	local hinted
	for _, w in ipairs(savedWrits) do if w.itemID == 264125 then hinted = w end end
	check(hinted ~= nil, "Known Artisan hint fixture exists")
	local previous = savedLearned[hinted.itemID]
	savedLearned[hinted.itemID] = nil
	ns.WRITS = { hinted }
	local rows = ns.BuildWritRows({ zoneFilter = "all", profFilter = "all", unlockFilter = "all" })
	check(rows[1].zoneSource == "hint" and rows[1].zoneHint == "Azshara" and rows[1].zone == "Unmapped"
		and rows[1].areaDisplay == "|cff888888Azshara (likely)|r", "Hint rows expose gray likely area without confirming it")
	ns.app.ui.writsTable.setRows(rows)
	local rendered = ns.app.ui.writsTable.scrollBox._frames[1]
	check(rendered:GetScript("OnEnter") == nil, "Writ row has no item tooltip handler")
	GameTooltip:ClearLines()
	rendered.cells[1]:GetScript("OnEnter")(rendered.cells[1])
	check(table.concat(GameTooltip._lines, " "):find("Azshara (likely)", 1, true) ~= nil, "Writ tooltip shows likely area")
	GameTooltip:Hide()
	savedLearned[hinted.itemID] = { zone = "Stormwind City", npc = "Learned NPC", x = 30, y = 40 }
	rows = ns.BuildWritRows({ zoneFilter = "Stormwind City", profFilter = "all", unlockFilter = "all" })
	check(rows[1].zoneSource == "learned" and rows[1].zoneHint == nil and rows[1].npc == "Learned NPC"
		and rows[1].coordText == "30.0, 40.0" and rows[1].areaDisplay == "|cff66ee88Stormwind|r",
		"Learned rows use confirmed zone, learned location, green color and short name")
	local zones = ns.GetWritZones()
	check(zones[3].key == "Stormwind City", "Learned zone enters area dropdown")
	savedLearned[hinted.itemID], ns.WRITS = previous, savedWrits
	for id, expected in pairs({ [264060] = "Feralas", [264064] = "Swamp of Sorrows", [264065] = "Tanaris" }) do
		for _, w in ipairs(savedWrits) do
			if w.itemID == id then
				z, src = ns.GetWritZoneInfo(w)
				check(z == expected and src == "static", "Confirmed Expert zone remains static")
			end
		end
	end
end

do
	local app, api = ns.app, MerchantMasterAPI
	check(type(api.RegisterAnalytics) == "function" and not api.RegisterAnalytics(false),
		"RegisterAnalytics exists and rejects non-table providers")
	check(MerchantMasterDB.anChar == "all" and MerchantMasterDB.anType == "all" and MerchantMasterDB.anZone == "all"
		and MerchantMasterDB.anPeriod == "30d" and MerchantMasterDB.anItemMode == "profit"
		and MerchantMasterDB.anKnownCostOnly == true, "Analytics defaults initialized")
	for _, key in ipairs({ "makeSidebarDrop", "makeSidebarCheck", "makeSidebarBtn", "createSortableTable", "applyRowHighlight", "applyListBackground" }) do
		check(type(app.ui[key]) == "function", "Companion UI helper exported: " .. key)
	end
	check(app.ui.ROW_H == 22 and app.ui.COL_GAP == 5, "Companion table dimensions exported")
	SlashCmdList.MERCHANTMASTER("analytics")
	check(app.activeTab == "an_overview" and MerchantMasterDB.activeTab == "an_overview", "/mm analytics opens Overview")
	check(app.ui.analyticsView:IsShown() and app.ui.analyticsSubBar:IsShown() and app.ui.analyticsSubBar:GetWidth() == 528,
		"Analytics view and sub-bar use host layout")
	check(app.ui.analyticsView.emptyFs:IsShown() and app.ui.statusText:GetText() == "Analytics unavailable",
		"Missing Analytics provider displays load-error message and status")
	SlashCmdList.MERCHANTMASTER("ledger")
	check(app.activeTab == "an_ledger", "/mm ledger opens Ledger")
	SlashCmdList.MERCHANTMASTER("analytics")
	check(app.activeTab == "an_ledger", "Analytics menu remembers its leaf tab")
	for _, route in ipairs({ { "stats", "an_ledger" }, { "log", "an_ledger" }, { "portfolio", "an_portfolio" },
		{ "wealth", "an_portfolio" }, { "investments", "an_invest" }, { "invest", "an_invest" } }) do
		SlashCmdList.MERCHANTMASTER(route[1])
		check(app.activeTab == route[2], "Analytics slash route: " .. route[1])
	end
	for _, key in ipairs({ "an_overview", "an_ledger", "an_items", "an_portfolio", "an_invest", "an_writs" }) do
		app.ui.analyticsSubBar.buttons[key]._scripts.OnClick(app.ui.analyticsSubBar.buttons[key])
		check(app.activeTab == key and app.TAB_GROUP_OF[key] == "analytics", "Analytics leaf button routes: " .. key)
	end
	local control = app.ui.makeSidebarBtn("Test Analytics", false, function() end)
	local before, refreshed = #app.allDynamicSidebarControls, 0
	local provider = {
		controls = { control, control },
		sidebarControls = function(tab) check(tab == app.activeTab, "Sidebar callback receives leaf tab"); return { control } end,
		refresh = function(tab, view, status)
			check(tab == app.activeTab and view == app.ui.analyticsView and status == app.ui.statusText,
				"Refresh callback receives leaf, container, and status")
			refreshed = refreshed + 1
			status:SetText("Analytics test ready")
		end,
	}
	app.openSidebarPopover("filters")
	check(api.RegisterAnalytics(provider) and refreshed > 0 and not app.ui.analyticsView.emptyFs:IsShown(),
		"Late registration refreshes visible Analytics immediately")
	check(#app.allDynamicSidebarControls == before + 1 and control:IsShown(), "Provider controls deduplicate and show")
	api.RegisterAnalytics(provider)
	check(#app.allDynamicSidebarControls == before + 1, "Re-registering controls does not grow host list")
	local oldSlots, oldBuild = C_Container.GetContainerNumSlots, ns.BuildRecipeRows
	C_Container.GetContainerNumSlots = function() error("Analytics scanned bags") end
	ns.BuildRecipeRows = function() error("Analytics built recipes") end
	app.bagsDirty = true
	local ok, err = pcall(app.refresh)
	C_Container.GetContainerNumSlots, ns.BuildRecipeRows = oldSlots, oldBuild
	check(ok, "Analytics skips bag scans, owned-count scans and recipe rows: " .. tostring(err))

	provider.refresh = function() error("mock refresh failure") end
	ok, err = pcall(app.refresh)
	check(ok and app.analyticsProvider == nil and app._anErrLogged and not control:IsShown(),
		"Throwing refresh is isolated, disables provider and hides controls")
	check(app.ui.analyticsView.emptyFs:IsShown() and app.ui.analyticsView.emptyFs:GetText():find("mock refresh failure", 1, true),
		"Provider failure is visible in Analytics")
	app.refresh()
	check(app.ui.statusText:GetText() == "Analytics unavailable", "Host remains usable after failure")
	for _, callback in ipairs({ function() error("mock sidebar failure") end, function() return false end }) do
		api.RegisterAnalytics({ controls = { control }, sidebarControls = callback })
		check(app.analyticsProvider == nil and not control:IsShown(), "Throwing or invalid sidebar callback is isolated")
	end
	api.RegisterAnalytics({ getAverages = function() return { perRep = 123, favorPrice = 456 } end })
	check(app._anErrLogged == false, "Registration resets provider error latch")
	for _, tab in ipairs({ "rep", "calc_favor", "calc_rep" }) do
		api.SetTab(tab)
		local fs = tab == "rep" and app.ui.repHintFs or (tab == "calc_favor" and app.ui.favorSummaryFs or app.ui.repSummaryFs)
		check(fs:GetText():find("My Avg:", 1, true) ~= nil, "Actual averages displayed on " .. tab)
	end
	api.RegisterAnalytics({ getAverages = function() error("mock averages failure") end })
	ok, err = pcall(api.SetTab, "rep")
	check(ok and not app.ui.repHintFs:GetText():find("My Avg:", 1, true), "Throwing averages do not affect host")
	app.analyticsProvider = nil
	api.SetTab("dashboard")
	check(not app.ui.analyticsView:IsShown() and not app.ui.analyticsSubBar:IsShown(), "Leaving Analytics hides its view and sub-bar")

	-- Verify Dashboard "Known Recipes" Best Options fallback + Gear/Bound Bag tracking
	local prevKnownSpells = app.char.knownSpells
	local prevAHPool = MerchantMasterDB.ahPrices["Normal-Horde"]
	local prevPriceSource = MerchantMasterDB.priceSource
	local mockKnownSpells = {}
	local mockPool = { _scannedAt = time() }
	local seededKnown, seededOutIDs = 0, {}
	for _, r in ipairs(ns.RECIPES) do
		local outID = r.outputItemID or r.itemID
		if r.prof == "leatherworking" and r.spellID and outID and ns.IsItemSellable(outID) and r.reagents and #r.reagents > 0 then
			seededKnown = seededKnown + 1
			mockKnownSpells[r.spellID] = true
			seededOutIDs[outID] = mockTSMPrices.dbregionsoldperday[outID] or false
			mockTSMPrices.dbregionsoldperday[outID] = 5
			-- Give every known recipe >=15 AH listings (no 0-2 or 0-4 monopolies!) and profitable prices well above vendor sell so fallback must activate!
			local vSell = ns.GetVendorSellPrice and ns.GetVendorSellPrice(outID) or 0
			mockPool[outID] = { price = math.max(15000 + seededKnown * 500, vSell * 3 + 15000), qty = 15 + seededKnown, absent = false, at = time() }
			for _, rg in ipairs(r.reagents) do
				local rgID = rg.itemID or rg[1]
				if rgID and not mockPool[rgID] then mockPool[rgID] = { price = 100, qty = 500, absent = false, at = time() } end
			end
			if seededKnown >= 12 then break end
		end
	end
	check(seededKnown >= 12, "Seeded >=12 known Leatherworking recipes, got " .. tostring(seededKnown))
	app.char.knownSpells = mockKnownSpells
	MerchantMasterDB.ahPrices["Normal-Horde"] = mockPool
	MerchantMasterDB.priceSource = "live"
	ns.InvalidatePriceCache()

	MerchantMasterDB.knownRecipesOnly = true
	MerchantMasterDB.dashboardScope = "smart"
	api.SetTab("dashboard")
	app.refresh()
	check(app.ui.dashLeftHdrFs:GetText():find("KNOWN CRAFTS", 1, true) ~= nil, "Dashboard left header updates for Known Recipes")
	local knownDash = ns.BuildDashboardInsights({ dashboardScope = "smart", knownRecipesOnly = true })
	check(knownDash ~= nil and #knownDash.topCrafts == 5 and #knownDash.topOutliers == 5,
		"Dashboard Known Recipes populates 5/5 Left (" .. #(knownDash and knownDash.topCrafts or {}) .. ") and 5/5 Right Best Known Options (" .. #(knownDash and knownDash.topOutliers or {}) .. ") even with 0 monopolies")
	check(knownDash.hasBestKnownFallback == true, "Best Known Options fallback activates when all known recipes have >=15 AH listings")
	check(app.ui.dashRightHdrFs:GetText():find("BEST KNOWN OPTIONS", 1, true) ~= nil,
		"Dashboard right header switches to TOP 5 BEST KNOWN OPTIONS when monopoly fallback activates")
	check(app.ui.dashOutlierRows[1].actBtn:GetText():find("Buy Mats", 1, true) ~= nil,
		"Right-hand Best Known Option row switches button from Set Price to Buy Mats")

	MerchantMasterDB.knownRecipesOnly = false
	MerchantMasterDB.priceSource = prevPriceSource
	app.char.knownSpells = prevKnownSpells
	MerchantMasterDB.ahPrices["Normal-Horde"] = prevAHPool
	for outID, prevV in pairs(seededOutIDs) do
		mockTSMPrices.dbregionsoldperday[outID] = (prevV ~= false) and prevV or nil
	end
	ns.InvalidatePriceCache()
	app.refresh()
	check(type(app.scanGear) == "function", "app.scanGear exported for wealth tracking")
end

---------------------------------------------------------------------------------------------------
-- 18. v3.2.0 Verification: Unified MerchantProfessor + All Profession Recipes + Multi-Select Source Filter
---------------------------------------------------------------------------------------------------
do
	local appTbl = ns.app
	local MP = ns.MP
	check(type(MP) == "table" and type(_G.MerchantProfessorAPI) == "table", "MerchantProfessor namespace & global API embedded inside MerchantMaster")
	check(#ns.PROFESSIONS == 14, "14 entries in ns.PROFESSIONS including Poisons, got " .. #ns.PROFESSIONS)

	local catalogCount = 0
	for _ in pairs(ns.ALL_CATALOG_IDS or {}) do catalogCount = catalogCount + 1 end
	check(catalogCount == COUNTS.catalogIDs, "Unified ALL_CATALOG_IDS tracks " .. COUNTS.catalogIDs .. " items across Market + Professor, got " .. catalogCount)

	local tradeableRecCount = 0
	local profMap = {}
	for _, r in ipairs(ns.RECIPES) do
		profMap[r.prof] = (profMap[r.prof] or 0) + 1
		if r.sellable and r.outputItemID and ns.IsItemSellable(r.outputItemID) then
			tradeableRecCount = tradeableRecCount + 1
		end
		if r.outputItemID and ns.ITEM_BOP and ns.ITEM_BOP[r.outputItemID] then
			check(ns.IsItemSellable(r.outputItemID) == false, "Offline ITEM_BOP blocks BoP item from AH valuation: " .. tostring(r.name))
		end
	end
	check(tradeableRecCount == 1653, "1653 tradeable crafting recipes across all professions, got " .. tradeableRecCount)
	for pk, expectedCnt in pairs({
		alchemy = 187, blacksmithing = 431, cooking = 123, enchanting = 235, engineering = 241,
		firstaid = 30, leatherworking = 511, mining = 16, tailoring = 415, poisons = 19, others = 4,
	}) do
		check(profMap[pk] == expectedCnt, string.format("Unified catalog %s has %d recipes, got %s", pk, expectedCnt, tostring(profMap[pk])))
	end

	-- Multi-Select Recipe Source Filter: All, Single, and Multi-Select Combinations
	local srcCounts = {
		merchant = 314,
		vendor = 397,
		trainer = 513,
		ah = 650,
		quest_drop = 338,
	}
	for bk, expN in pairs(srcCounts) do
		local singleRows = ns.BuildRecipeRows({ profFilter = "all", recipeSources = { [bk] = true } })
		check(#singleRows == expN, string.format("Single source filter '%s' returns %d recipes, got %d", bk, expN, #singleRows))
		for _, rr in ipairs(singleRows) do
			check(ns.GetRecipeSourceBucket(rr.recipe) == bk, "Filtered recipe matches bucket " .. bk)
		end
	end

	local multiMV = ns.BuildRecipeRows({ profFilter = "all", recipeSources = { merchant = true, vendor = true } })
	check(#multiMV == 314 + 397, "Multi-select {merchant, vendor} returns 711 recipes, got " .. #multiMV)

	local multiMVT = ns.BuildRecipeRows({ profFilter = "all", recipeSources = { merchant = true, vendor = true, trainer = true } })
	check(#multiMVT == 314 + 397 + 513, "Multi-select {merchant, vendor, trainer} returns 1224 recipes, got " .. #multiMVT)

	-- Forever Smelts, Instant Right-Click Essence Conversions & Darkmoon Set Card Decks
	do
		local bySpell = {}
		for _, r in ipairs(ns.RECIPES) do
			if r.spellID then bySpell[r.spellID] = r end
		end
		check(bySpell[1249637] and bySpell[1249637].outputItemID == 249726 and bySpell[1249637].prof == "mining",
			"Smelt Azerothium (1249637) present under Mining")
		check(bySpell[1306126] and bySpell[1306126].outputItemID == 251291 and bySpell[1306126].prof == "mining",
			"Smelt Heavy Thorium (1306126) present under Mining")
		for _, dSpell in ipairs({ 23677, 23678, 23679, 23680 }) do
			local dRec = bySpell[dSpell]
			check(dRec and dRec.prof == "others" and dRec.anyChar == true and #dRec.reagents == 8 and ns.IsRecipeKnown(dRec),
				"Darkmoon Deck spell " .. dSpell .. " has 8 cards under Others and is known on any character")
		end
		local othersRows = ns.BuildRecipeRows({ profFilter = "others" })
		check(#othersRows == 15, "Others filter returns all 15 item-combine/tool exceptions (4 Decks + 10 Essences + Refined Salt), got " .. #othersRows)
		check(ns.app.ui and ns.app.ui.profBtns and ns.app.ui.profBtns.others ~= nil, "Sidebar Filters popover exposes Others button")
		local prevL, prevG = mockTSMPrices.dbminbuyout[16202], mockTSMPrices.dbminbuyout[16203]
		local prevLM, prevGM = mockTSMPrices.dbmarket[16202], mockTSMPrices.dbmarket[16203]
		local prevSrc = MerchantMasterDB.priceSource
		MerchantMasterDB.priceSource = "auto"
		mockTSMPrices.dbminbuyout[16202], mockTSMPrices.dbmarket[16202] = 150000, 150000 -- 15g Lesser
		mockTSMPrices.dbminbuyout[16203], mockTSMPrices.dbmarket[16203] = 600000, 600000 -- 60g Greater
		ns.InvalidatePriceCache()
		local cGreater, _, _, _, usedCombine = ns.ComputeSmartCraftCost({ { 16203, 1 } }, 1, 999991, {
			parentProf = "leatherworking", profMap = { leatherworking = 300 }, subCraftMode = "smart",
		})
		check(usedCombine == true and cGreater == 450000,
			"Smart Sub-Craft combines 3x Lesser Eternal Essence (45g) instead of buying 1x Greater (60g) on non-Enchanter")
		mockTSMPrices.dbminbuyout[16202], mockTSMPrices.dbmarket[16202] = 250000, 250000 -- 25g Lesser
		mockTSMPrices.dbminbuyout[16203], mockTSMPrices.dbmarket[16203] = 450000, 450000 -- 45g Greater (15g/ea split)
		ns.InvalidatePriceCache()
		local cLesser, _, _, _, usedSplit = ns.ComputeSmartCraftCost({ { 16202, 1 } }, 1, 999992, {
			parentProf = "leatherworking", profMap = { leatherworking = 300 }, subCraftMode = "smart",
		})
		check(usedSplit == true and cLesser == 150000,
			"Smart Sub-Craft splits 1x Greater Eternal Essence (45g / 3 = 15g) instead of buying 1x Lesser (25g)")
		mockTSMPrices.dbminbuyout[16202], mockTSMPrices.dbminbuyout[16203] = prevL, prevG
		mockTSMPrices.dbmarket[16202], mockTSMPrices.dbmarket[16203] = prevLM, prevGM
		MerchantMasterDB.priceSource = prevSrc
		ns.InvalidatePriceCache()
	end

	check(ns.FormatRecipeSourcesLabel({}) == "Sources: All", "Empty recipeSources formats as 'Sources: All'")
	check(ns.FormatRecipeSourcesLabel({ merchant = true }) == "Sources: Merchant", "Single merchant formats as 'Sources: Merchant'")
	check(ns.FormatRecipeSourcesLabel({ merchant = true, vendor = true }) == "Src: Merchant + Vendor", "2-selected formats as 'Src: Merchant + Vendor'")
	check(ns.FormatRecipeSourcesLabel({ merchant = true, vendor = true, trainer = true }) == "Sources: 3 Selected", "3-selected formats as 'Sources: 3 Selected'")

	-- Verify Profit Spread, Outliers, Writ Profit, and Dashboard all enforce multi-select recipeSources
	local filterMV = { merchant = true, vendor = true }
	local spMV = ns.BuildProfitSpreadRows({ profFilter = "all", recipeSources = filterMV })
	for _, sr in ipairs(spMV) do
		local b = ns.GetRecipeSourceBucket(sr.recipe)
		check(b == "merchant" or b == "vendor", "Profit Spread row honors {merchant, vendor}, got " .. tostring(b))
	end
	local outMV = ns.BuildOutlierRows({ profFilter = "all", outlierScope = "all_gaps", outlierQuality = "all", recipeSources = filterMV })
	for _, orow in ipairs(outMV) do
		local b = ns.GetRecipeSourceBucket(orow.recipe)
		check(b == "merchant" or b == "vendor", "Outliers row honors {merchant, vendor}, got " .. tostring(b))
	end
	local wpVT = ns.BuildWritProfitRows({ profFilter = "all", recipeSources = { vendor = true, trainer = true } })
	check(#wpVT > 0 and #wpVT < 150, "Writ Profit multi-select {vendor, trainer} filters subset (" .. #wpVT .. "/150)")
	for _, wr in ipairs(wpVT) do
		local b = ns.GetRecipeSourceBucket(wr.writ)
		check(b == "vendor" or b == "trainer", "Writ Profit row honors {vendor, trainer}, got " .. tostring(b))
	end
	local dashT = ns.BuildDashboardInsights({ dashboardScope = "all", recipeSources = { trainer = true } })
	for _, dc in ipairs(dashT.topCrafts or {}) do
		check(ns.GetRecipeSourceBucket(dc.recipe) == "trainer", "Dashboard topCraft honors {trainer}")
	end

	-- Verify Super List Multi-Select Dropdown stays open while toggling multiple options, and resets on All / Right-Click
	SlashCmdList.MERCHANTMASTER("recipes")
	appTbl.openSidebarPopover("filters")
	check(appTbl.ui.recipesView.sourceButton ~= nil and appTbl.ui.recipesView.sourceButton:IsShown(), "recipesView.sourceButton visible on Recipes tab")
	MerchantMasterDB.superListSources = {}
	appTbl.ui.recipesView.sourceButton:Click("LeftButton")
	local ddMenu = ns.Theme.GetDropDownMenu()
	check(ddMenu ~= nil and ddMenu:IsShown() == true, "Clicking recipesView.sourceButton opens multi-select dropdown")
	-- Click Option 2 (Merchant Favor) and Option 3 (Vendor) -> menu MUST stay open!
	ddMenu.rows[2]:Click("LeftButton")
	check(ddMenu:IsShown() == true and MerchantMasterDB.superListSources.merchant == true, "Toggling Merchant Recipes keeps dropdown open")
	ddMenu.rows[3]:Click("LeftButton")
	check(ddMenu:IsShown() == true and MerchantMasterDB.superListSources.vendor == true, "Toggling Vendor Recipes keeps dropdown open with 2 selected")
	check(appTbl.ui.recipesView.sourceButton:GetText() == "Src: Merchant + Vendor", "Button label updates live to 'Src: Merchant + Vendor'")
	-- All Sources clears a legacy restriction before refresh can remigrate it.
    MerchantMasterDB.merchantVendorOnly=true
    ddMenu.rows[1]:Click('LeftButton')
    check(MerchantMasterDB.merchantVendorOnly==false and next(MerchantMasterDB.superListSources)==nil,'All Sources clears hidden legacy flag')
    MerchantMasterDB.superListSources={merchant=true}; MerchantMasterDB.merchantVendorOnly=true
    -- Right-click resets to All
	ns.Theme.CloseDropDown()
	appTbl.ui.recipesView.sourceButton:Click("RightButton")
	check(not ns.HasActiveRecipeSourceFilter(MerchantMasterDB.superListSources) and appTbl.ui.recipesView.sourceButton:GetText() == "Sources: All",
		"Right-clicking recipesView.sourceButton resets to Sources: All")
    check(MerchantMasterDB.merchantVendorOnly==false, "Right-click clears hidden legacy flag")

	-- Verify Embedded Professor Tab, /mp Slash Commands, Shopping Modes & Simultaneous Live AH Refresh!
	SlashCmdList.MERCHANTPROFESSOR("alchemy")
	check(_G.MerchantMasterPanel:IsShown() == true and appTbl.activeTab == "prof_path", "/mp alchemy opens MerchantMaster on Professor Leveling Path")
	check(MP.GetDB().selectedProf == "alchemy", "Professor selectedProf == 'alchemy'")
	check(MP.app.lastPathResult ~= nil and #(MP.app.lastPathResult.steps or {}) > 0, "Alchemy 1->300 path solved and rendered")
	check(#(appTbl.activeShoppingRows or {}) > 0, "Professor syncs activeShoppingRows into MerchantMaster Shopping Basket")

	SlashCmdList.MERCHANTPROFESSOR("bylevel")
	check(appTbl.activeTab == "prof_shop" and MP.GetDB().shoppingGroupMode == "by_level", "/mp bylevel switches to Professor Shopping List (By Level)")
	SlashCmdList.MERCHANTPROFESSOR("consolidated")
	check(MP.GetDB().shoppingGroupMode == "consolidated", "/mp consolidated switches back to Consolidated")
	SlashCmdList.MERCHANTPROFESSOR("browse")
	check(appTbl.activeTab == "prof_browse", "/mp browse opens Professor Browse All Recipes")
	_G.MerchantProfessorAPI.SelectProfession("alchemy")
	check(appTbl.activeTab == "prof_path", "MerchantProfessorAPI.SelectProfession('alchemy') opens prof_path")

	-- Simultaneous Live AH Refresh Proof:
	-- Force Alchemy 1->60 route using Peacebloom (2447) + Silverleaf (765) -> Minor Healing Potion (118)
	MP.GetDB().profTargets.alchemy = { from = 1, to = 60 }
	MP.GetDB().charLevelMode = 60
	MP.GetDB().useOwned = false
	MerchantMasterDB.economy = "auto"
	MerchantMasterDB.priceSource = "live"
	MerchantMasterDB.ahPrices["Normal-Horde"] = {
		_scannedAt = time() - 120,
		[2447] = { price = 10, qty = 500, absent = false, at = time() - 120 }, -- 10c Peacebloom
		[765]  = { price = 10, qty = 500, absent = false, at = time() - 120 }, -- 10c Silverleaf
		[118]  = { price = 50, qty = 200, absent = false, at = time() - 120 },
	}
	ns.InvalidatePriceCache()
	appTbl.refresh()

	local matsBefore = MP.app.lastPathResult and MP.app.lastPathResult.totalGrossMats or 0
	local mhpBefore = nil
	for _, r in ipairs(ns.BuildRecipeRows({ profFilter = "alchemy" })) do
		if r.itemID == 118 then mhpBefore = r.craftCost; break end
	end
	check(matsBefore > 0 and mhpBefore ~= nil, "Recorded pre-scan Professor route mats (" .. tostring(matsBefore) .. ") & Market Minor Healing Potion cost (" .. tostring(mhpBefore) .. ")")

	-- Now simulate Live AH Browse Scan where Peacebloom & Silverleaf spike 50x (10c -> 500c)!
	_G.AuctionHouseFrame:Show()
	_G.C_AuctionHouse.GetBrowseResults = function()
		return {
			{ itemKey = { itemID = 2447, itemLevel = 1, itemSuffix = 0 }, totalQuantity = 500, minPrice = 500 },
			{ itemKey = { itemID = 765,  itemLevel = 1, itemSuffix = 0 }, totalQuantity = 500, minPrice = 500 },
			{ itemKey = { itemID = 118,  itemLevel = 1, itemSuffix = 0 }, totalQuantity = 200, minPrice = 50 },
		}
	end
	eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_SHOW")
	SlashCmdList.MERCHANTMASTER("refresh")
	eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	_G.AuctionHouseFrame:Hide()
	eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_CLOSED")

	-- Immediately read MP.app.lastPathResult (without manually calling refresh!) AND Market BuildRecipeRows:
	local matsAfter = MP.app.lastPathResult and MP.app.lastPathResult.totalGrossMats or 0
	local mhpAfter = nil
	for _, r in ipairs(ns.BuildRecipeRows({ profFilter = "alchemy" })) do
		if r.itemID == 118 then mhpAfter = r.craftCost; break end
	end
	check(matsAfter > matsBefore * 5 and mhpAfter > mhpBefore * 5,
		string.format("Simultaneous AH refresh updated BOTH Professor (mats %d -> %d) AND Market (craftCost %d -> %d) at the exact same instant!",
			matsBefore, matsAfter, mhpBefore, mhpAfter))

	-- Restore defaults
	MP.GetDB().profTargets.alchemy = { from = 1, to = 300 }
	MerchantMasterDB.priceSource = "auto"
	wipe(MerchantMasterDB.ahPrices["Normal-Horde"])
	ns.InvalidatePriceCache()
	SlashCmdList.MERCHANTMASTER("")
end

-- Forever 16001 Alchemy completeness (Viridian Dye + 13 recipes), Sandpaper, crafted VENDOR_REAGENTS removal & Smart Sub-Craft
do
	for _, craftedMatID in ipairs({ 249409, 249430, 249431, 249410, 249432 }) do
		check(ns.VENDOR_REAGENTS[craftedMatID] == nil, "Player-crafted Forever material excluded from VENDOR_REAGENTS: " .. craftedMatID)
	end
	for _, vialID in ipairs({ 3371, 3372, 8925 }) do
		check(ns.VENDOR_REAGENTS[vialID] ~= nil, "Vendor vial preserved in VENDOR_REAGENTS: " .. vialID)
	end

	local recipeBySpell, rowBySpell = {}, {}
	for _, r in ipairs(ns.RECIPES) do
		if r.spellID then recipeBySpell[r.spellID] = r end
	end
	for _, r in ipairs(ns.BuildRecipeRows({ profFilter = "all", sourceFilter = "all" })) do
		local sid = r.recipe and r.recipe.spellID
		if sid then rowBySpell[sid] = r end
	end

	local expectedForever = {
		{ 1249630, "Cerulean Dye", 249409, "alchemy", 40 },
		{ 1249633, "Sulfuric Acid", 249410, "alchemy", 40 },
		{ 1244645, "Lesser Discolored Healing Potion", 247239, "alchemy", 85 },
		{ 2365,    "Draught of Tongues", 2460, "alchemy", 100 },
		{ 1249631, "Magenta Dye", 249430, "alchemy", 120 },
		{ 1244646, "Discolored Healing Potion", 247240, "alchemy", 135 },
		{ 1244647, "Greater Discolored Healing Potion", 247241, "alchemy", 175 },
		{ 1251744, "Greater Mender's Potion", 250947, "alchemy", 180 },
		{ 11447,   "Draught of Water Walking", 8827, "alchemy", 190 },
		{ 1250775, "Revealing Draught", 250326, "alchemy", 205 },
		{ 1249632, "Viridian Dye", 249431, "alchemy", 215 },
		{ 1244648, "Superior Discolored Healing Potion", 247242, "alchemy", 230 },
		{ 1263078, "Alchemy Laboratory", 279990, "alchemy", 300 },
		{ 22430,   "Refined Scale of Onyxia", 17967, "alchemy", 300 },
		{ 1249634, "Sandpaper", 249432, "engineering", 120 },
	}
	for _, spec in ipairs(expectedForever) do
		local sid, ename, eitem, eprof, eskill = spec[1], spec[2], spec[3], spec[4], spec[5]
		local rec, row = recipeBySpell[sid], rowBySpell[sid]
		check(rec ~= nil and row ~= nil, "Forever recipe present in ns.RECIPES and Super List: " .. ename .. " (" .. sid .. ")")
		check(rec.prof == eprof and rec.outputItemID == eitem and rec.skill == eskill,
			"Forever recipe metadata matches: " .. ename)
		check(row.name == ename and row.recipe and row.recipe.reagents and #row.recipe.reagents >= 1,
			"Forever Super List row resolves name & reagents: " .. tostring(row.name))
	end

	local minorDisc = recipeBySpell[4508]
	local minorDiscRow = rowBySpell[4508]
	check(minorDisc ~= nil and minorDisc.recipeItemID == 4597 and minorDisc.name == "Minor Discolored Healing Potion" and minorDiscRow ~= nil,
		"Spell 4508 preserved in-place with updated Minor Discolored Healing Potion scroll 4597")
	local viridianRec = recipeBySpell[1249632]
	check(viridianRec.source == "trainer" and viridianRec.trainerCost == 10000, "Viridian Dye has trainer source and 1g trainerCost")

	local ezRec = recipeBySpell[1266921]
	check(ezRec ~= nil, "Found EZ-Thro Tru-Trigger (1266921) consuming Viridian Dye 249431")
	local savedBuyout, savedMarket = {}, {}
	for _, id in ipairs({ 6037, 249274, 249431 }) do
		savedBuyout[id] = mockTSMPrices.dbminbuyout[id]
		savedMarket[id] = mockTSMPrices.dbmarket[id]
	end
	mockTSMPrices.dbminbuyout[6037] = 1000
	mockTSMPrices.dbminbuyout[249274] = 300
	mockTSMPrices.dbminbuyout[249431] = 100000
	mockTSMPrices.dbmarket[249431] = 100000
	ns.InvalidatePriceCache()
	local unitSub, _, _, directSub, usedSub = ns.ComputeSmartCraftCost(ezRec.reagents, 1, ezRec.outputItemID, {
		parentProf = "engineering",
		profMap = { alchemy = 300, engineering = 300 },
		subCraftMode = "smart",
	})
	check(usedSub == true and unitSub ~= nil and directSub == 101000 and unitSub < directSub,
		"Smart Sub-Craft evaluates crafting Viridian Dye instead of vendor/expensive AH price")

	mockTSMPrices.dbminbuyout[249431] = 50
	mockTSMPrices.dbmarket[249431] = 50
	ns.InvalidatePriceCache()
	local unitBuy, _, _, directBuy, usedBuy = ns.ComputeSmartCraftCost(ezRec.reagents, 1, ezRec.outputItemID, {
		parentProf = "engineering",
		profMap = { alchemy = 300, engineering = 300 },
		subCraftMode = "smart",
	})
	check(usedBuy == false and unitBuy == 1050 and unitBuy == directBuy,
		"Smart Sub-Craft picks cheaper AH Viridian Dye when AH undercuts crafting")

	for _, id in ipairs({ 6037, 249274, 249431 }) do
		mockTSMPrices.dbminbuyout[id] = savedBuyout[id]
		mockTSMPrices.dbmarket[id] = savedMarket[id]
	end
	ns.InvalidatePriceCache()
end

-- Cooldown & Shared Transmute exclusion tests (Sub-Craft, Profit Spread planRows, Dashboard Insights, Live Cooldown Scan)
do
	local MP = ns.MP
	local appTbl = ns.app
	local bySpell = (MP and MP.RECIPES_BY_SPELL) or {}
	local arcaniteRec = bySpell[17187]
	local undeathRec = bySpell[17563]
	local elemFireRec = bySpell[25146]
	local moonclothRec = bySpell[18560]
	check(arcaniteRec and undeathRec and elemFireRec and moonclothRec, "Cooldown planner test recipes present")

	-- 1) Cooldown craft (11480 Mithril->Truesilver, cd=3600) must never be auto-picked as a reagent sub-craft
	local truesilverID = 6037
	local mithrilID = 3860
	local savedB, savedM, savedSold, savedRegAvg, savedNum = {}, {}, {}, {}, {}
	local touchIDs = { truesilverID, mithrilID, 3577, 3575, 2776, 12360, 12359, 12363, 7080, 12808, 7068, 7077, 14342, 14256, 15407, 8171, 15409, 8150 }
	for _, id in ipairs(touchIDs) do
		savedB[id] = mockTSMPrices.dbminbuyout[id]
		savedM[id] = mockTSMPrices.dbmarket[id]
		savedSold[id] = mockTSMPrices.dbregionsoldperday[id]
		savedRegAvg[id] = mockTSMPrices.dbregionmarketavg[id]
		savedNum[id] = mockTSMPrices.dbnumauctions[id]
	end
	local savedPriceSource = MerchantMasterDB.priceSource
	MerchantMasterDB.priceSource = "auto"
	mockTSMPrices.dbminbuyout[mithrilID] = 10
	mockTSMPrices.dbminbuyout[truesilverID] = 999999
	mockTSMPrices.dbmarket[truesilverID] = 999999
	ns.InvalidatePriceCache()
	local unitNoCDSub, _, _, directNoCDSub, usedNoCDSub = ns.ComputeSmartCraftCost({ { truesilverID, 1 } }, 1, 999998, {
		parentProf = "engineering",
		profMap = { alchemy = 300, engineering = 300 },
		subCraftMode = "smart",
	})
	check(usedNoCDSub == false and unitNoCDSub == 999999 and directNoCDSub == 999999,
		"ComputeSmartCraftCost excludes >=60s cooldown recipes (Transmute: Mithril to Truesilver) from auto sub-craft")

	-- 2) Profit Spread & Dashboard Insights: 48h Arcanite batch capped at 1 (0.5/day), at most 1 shared alchemy_transmute
	mockTSMPrices.dbminbuyout[12359] = 1000; mockTSMPrices.dbminbuyout[12363] = 1000 -- Thorium Bar + Arcane Crystal = 20s
	mockTSMPrices.dbminbuyout[12360] = 50000000; mockTSMPrices.dbmarket[12360] = 50000000; mockTSMPrices.dbregionmarketavg[12360] = 50000000 -- Arcanite Bar = 5000g
	mockTSMPrices.dbminbuyout[12808] = 1000 -- Essence of Undeath = 10s
	mockTSMPrices.dbminbuyout[7080]  = 45000000; mockTSMPrices.dbmarket[7080]  = 45000000; mockTSMPrices.dbregionmarketavg[7080]  = 45000000 -- Essence of Water = 4500g
	mockTSMPrices.dbminbuyout[7077]  = 1000 -- Heart of Fire = 10s
	mockTSMPrices.dbminbuyout[7068]  = 50000000; mockTSMPrices.dbmarket[7068]  = 50000000; mockTSMPrices.dbregionmarketavg[7068]  = 50000000 -- Elemental Fire = 5000g (25146)
	mockTSMPrices.dbminbuyout[14256] = 1000 -- Felcloth = 10s
	mockTSMPrices.dbminbuyout[14342] = 50000000; mockTSMPrices.dbmarket[14342] = 50000000; mockTSMPrices.dbregionmarketavg[14342] = 50000000 -- Mooncloth = 5000g (18560)
	mockTSMPrices.dbregionsoldperday[12360] = 10
	mockTSMPrices.dbregionsoldperday[7080]  = 10
	mockTSMPrices.dbregionsoldperday[7068]  = 20
	mockTSMPrices.dbregionsoldperday[14342] = 10
	for _, outID in ipairs({ 12360, 7080, 7068, 14342 }) do
		mockTSMPrices.dbnumauctions[outID] = 5
	end
	local savedSpreadCount = MerchantMasterDB.spreadCount
	MerchantMasterDB.spreadCount = 8
	local ch = ns.activeChar or appTbl.char
	local savedKnown = {}
	for _, sid in ipairs({ 17187, 17563, 25146, 18560 }) do
		savedKnown[sid] = ch.knownSpells and ch.knownSpells[sid]
	end
	local savedCD = ch.cooldowns
	local savedCDGroups = ch.cooldownGroups
	ch.knownSpells = ch.knownSpells or {}
	ch.knownSpells[17187] = true
	ch.knownSpells[17563] = true
	ch.knownSpells[25146] = true
	ch.knownSpells[18560] = true
	ch.cooldowns = {}
	ch.cooldownGroups = {}

	local oldGetSpellCD = _G.GetSpellCooldown
	local simCD = {}
	_G.GetSpellCooldown = function(sid)
		if simCD[sid] then return GetTime() - 10, simCD[sid] + 10 end
		return 0, 0
	end
	ns.InvalidatePriceCache()

	local spreadRows, spreadSummary = ns.BuildProfitSpreadRows({
		profFilter = "mine_profs",
		unlockFilter = "all",
		craftableFilter = "all",
		applyAHCut = true,
		subCraftMode = "off",
		profMap = { alchemy = 300, tailoring = 300 },
		spreadCount = 8,
		diversifyProfs = false,
	})
	local arcRow, elemRow
	for _, r in ipairs(spreadRows) do
		if r.itemID == 12360 then arcRow = r end
		if r.recipe and r.recipe.spellID == 25146 then elemRow = r end
	end
	check(arcRow ~= nil and arcRow.recDailyQty == 1 and (arcRow.expectedDailySales or 99) <= 0.501,
		"BuildProfitSpreadRows caps 48h Arcanite batch at 1 and expectedDailySales <= 0.5/day")
	check(elemRow and elemRow.recDailyQty > 1 and elemRow.recDailyQty <= elemRow.cdInfo.maxPerDay,
		"BuildProfitSpreadRows recommends multiple batches of the independent short-cooldown Elemental Fire")
	local sharedPlanCount, hasElemPlan, hasMoonPlan = 0, false, false
	for _, pr in ipairs((spreadSummary and spreadSummary.planRows) or {}) do
		if pr.cdInfo and pr.cdInfo.sharedGroup == "alchemy_transmute" then sharedPlanCount = sharedPlanCount + 1 end
		if pr.itemID == 7068 then hasElemPlan = true end
		if pr.itemID == 14342 then hasMoonPlan = true end
	end
	check(sharedPlanCount == 1, "Spread Plan selects at most 1 shared alchemy_transmute recipe: got " .. sharedPlanCount)
	check(hasElemPlan and hasMoonPlan, "Independent cooldown crafts (Elemental Fire 25146 & Mooncloth 18560) still qualify for Spread Plan")
	do
		mockTSMPrices.dbminbuyout[3575] = 1000
		mockTSMPrices.dbminbuyout[2776] = 1000
		mockTSMPrices.dbminbuyout[3577] = 1000000
		mockTSMPrices.dbmarket[3577] = 1000000
		mockTSMPrices.dbregionmarketavg[3577] = 1000000
		mockTSMPrices.dbnumauctions[3577] = 1
		mockTSMPrices.dbregionsoldperday[3577] = 100
		ns.InvalidatePriceCache()
		local opts = { search = "Gold Bar", outlierQuality = "all", subCraftMode = "off" }
		for _, build in ipairs({ns.BuildProfitSpreadRows, ns.BuildOutlierRows}) do
			local transmute, smelt
			for _, row in ipairs(build(opts)) do
				if row.itemID == 3577 and row.recipe.spellID == 11479 then transmute = row end
				if row.itemID == 3577 and row.recipe.spellID == 3308 then smelt = row end
			end
			check(transmute and transmute.name == "Transmute: Iron to Gold" and smelt,
				"Gold Bar search retains both Iron to Gold and Smelt Gold as separate recipes")
			if build == ns.BuildProfitSpreadRows then
				check(transmute.recDailyQty > 1 and transmute.recDailyQty <= 24,
					"Daily Crafts recommends multiple Iron to Gold batches with a 24-per-day cooldown limit")
				local previousQueue, previousRefresh = MerchantMasterDB.spreadQueue, appTbl.refresh
				MerchantMasterDB.spreadQueue, appTbl.refresh = {}, function() end
				local tbl = appTbl.ui.profitSpreadTable
				tbl.setRows({ transmute, smelt })
				local frames = tbl.scrollBox._frames
				frames[1].cells[13]:Click("LeftButton")
				frames[1].cells[13]:Click("LeftButton")
				local queue = MerchantMasterDB.spreadQueue
				check(queue[transmute.spreadQueueKey] == 2 * transmute.recDailyQty and not queue[smelt.spreadQueueKey],
					"Daily Crafts queues both short-cooldown batches for Iron to Gold alone")
				queue["spell:999999999"] = 1
				local shopping = ns.BuildUnifiedShoppingList({spreadQueue = queue}, {subCraftMode = "off"})
				queue["spell:999999999"] = nil
				check(_G.mainItemID == nil, "Resolved and unresolved spread recipes leave mainItemID local")
				local hasIron, hasOre = false, false
				for _, row in ipairs(shopping) do
					if row.itemID == 3575 then hasIron = true end
					if row.itemID == 2776 then hasOre = true end
				end
				check(hasIron and not hasOre, "Shopping List queues Iron Bar for Iron to Gold when Gold Ore is used by Smelt Gold")
				MerchantMasterDB.spreadQueue, appTbl.refresh = previousQueue, previousRefresh
			end
		end
	end

	do
		local hideID, hideSpellID = 15407, 19047
		local saltID, saltSpellID = 15409, 19566
		local hideWasKnown = ch.knownSpells[hideSpellID]
		local saltWasKnown = ch.knownSpells[saltSpellID]
		ch.knownSpells[hideSpellID] = true
		ch.knownSpells[saltSpellID] = true
		mockTSMPrices.dbminbuyout[8171], mockTSMPrices.dbminbuyout[8150] = 100, 50
		mockTSMPrices.dbminbuyout[saltID], mockTSMPrices.dbmarket[saltID] = 500000, 500000
		mockTSMPrices.dbregionsoldperday[saltID], mockTSMPrices.dbnumauctions[saltID] = 10, 1
		mockTSMPrices.dbminbuyout[hideID], mockTSMPrices.dbmarket[hideID] = 600000, 600000
		mockTSMPrices.dbregionsoldperday[hideID], mockTSMPrices.dbnumauctions[hideID] = 10, 1
		ns.InvalidatePriceCache()
		local function findByID(rows, id)
			for _, r in ipairs(rows) do if r.itemID == id then return r end end
		end
		local opts = { profFilter="leatherworking", profMap={leatherworking=300}, subCraftMode="smart", outlierQuality="all" }
		local spreadRows = ns.BuildProfitSpreadRows(opts)
		local hideSpread = findByID(spreadRows, hideID)
		check(hideSpread and hideSpread.numMade == 2 and hideSpread.cdInfo == nil and hideSpread.recDailyQty > 1,
			"Cured Rugged Hide has no cooldown and can be crafted freely from bought Refined Deeprock Salt")
		local saltSpread = findByID(spreadRows, saltID)
		check(saltSpread and saltSpread.numMade==1 and saltSpread.recDailyQty==1 and saltSpread.cdInfo,
			"Spread recommends one batch of Refined Deeprock Salt (72h Salt Shaker cooldown)")
		approxEq(saltSpread.cdInfo.maxPerDay,1/3,0.0001,"Spread preserves Refined Deeprock Salt's 1/3 daily cast rate")
		approxEq(saltSpread.expectedDailySales,1/3,0.0001,"Spread uses Refined Deeprock Salt's cooldown item rate")
		check(saltSpread.expectedDailyProfit==math.floor(saltSpread.realizedProfit/3+0.5),
			"Spread daily profit uses Refined Deeprock Salt's 72h rate")
		local saltOutlier = findByID(ns.BuildOutlierRows(opts), saltID)
		check(saltOutlier and math.abs(saltOutlier.estDailyUnits-1/3)<0.0001
			and saltOutlier.expectedDailyProfit==math.floor(saltOutlier.profit/3+0.5),
			"Outliers uses Refined Deeprock Salt's 72h cooldown rate")

		-- Multi-output cooldown item rate check (c = 2 on a 72h recipe)
		local saltRec
		for _, r in ipairs(ns.RECIPES) do if r.spellID == saltSpellID then saltRec = r; break end end
		saltRec.numMade = 2
		ns.InvalidatePriceCache()
		local twoSpread = findByID(ns.BuildProfitSpreadRows(opts), saltID)
		check(twoSpread and twoSpread.numMade==2 and twoSpread.recDailyQty==1
			and math.abs(twoSpread.expectedDailySales-2/3)<0.0001
			and twoSpread.expectedDailyProfit==math.floor(twoSpread.realizedProfit*2/3+0.5),
			"Spread daily profit scales multi-output cooldown by numMade")
		local buildSpread, buildOutliers = ns.BuildProfitSpreadRows, ns.BuildOutlierRows
		ns.BuildProfitSpreadRows, ns.BuildOutlierRows = function() return {} end, function() return {} end
		opts.dashboardScope = "known"
		local fallback = findByID(ns.BuildDashboardInsights(opts).topCrafts, saltID)
		ns.BuildProfitSpreadRows, ns.BuildOutlierRows = buildSpread, buildOutliers
		check(fallback and fallback.recDailyQty==1 and math.abs(fallback.estDailyUnits-2/3)<0.0001
			and fallback.expectedDailyProfit==math.floor(fallback.profit*2/3+0.5),
			"Dashboard known-recipe fallback scales multi-output cooldown by numMade")
		saltRec.numMade = 1
		ch.knownSpells[hideSpellID] = hideWasKnown
		ch.knownSpells[saltSpellID] = saltWasKnown
	end

	-- Mooncloth cannot enter advice through monopoly, thin-market, or known-recipe fallback picks.
	do
		local opts = {profFilter="tailoring", profMap={tailoring=300}, subCraftMode="off"}
		local function hasItem(rows, id)
			for _, row in ipairs(rows) do if row.itemID == id then return true end end
			return false
		end
		local spread, recipes = ns.BuildProfitSpreadRows, ns.RECIPES
		ns.RECIPES = { ns.RECIPES_BY_OUTPUT[14342][1] }
		ns.BuildProfitSpreadRows = function() return {} end
		for _, case in ipairs({{1,"smart"},{1,"all"},{3,"known"},{5,"known"}}) do
			mockTSMPrices.dbnumauctions[14342], opts.dashboardScope = case[1], case[2]
			ns.InvalidatePriceCache()
			local ready = ns.BuildDashboardInsights(opts)
			local readyRows = case[1] == 5 and ready.topCrafts or ready.topOutliers
			check(hasItem(readyRows, 14342) and hasItem(ready.adviceShoppingList, 14256),
				"ready Mooncloth is recommended at stock " .. case[1] .. " in " .. case[2])
			simCD[18560] = 2000
			local active = ns.BuildDashboardInsights(opts)
			check(not hasItem(active.topCrafts, 14342) and not hasItem(active.topOutliers, 14342)
				and not hasItem(active.adviceShoppingList, 14256),
				"Mooncloth on cooldown stays out of advice at stock " .. case[1] .. " in " .. case[2])
			simCD[18560] = nil
		end
		ns.BuildProfitSpreadRows, ns.RECIPES = spread, recipes
	end

	-- 3) Activate Arcanite cooldown -> shared transmutes excluded from Spread Plan & Dashboard Top Crafts; scanPlayerCooldowns reacts
	appTbl.scanPlayerCooldowns()
	simCD[17187] = 50000
	local changedActive = appTbl.scanPlayerCooldowns()
	check(changedActive == true, "scanPlayerCooldowns detects newly active cooldown")
	ns.InvalidatePriceCache()
	local _, cdSummary = ns.BuildProfitSpreadRows({
		profFilter = "all",
		unlockFilter = "all",
		craftableFilter = "all",
		applyAHCut = true,
		subCraftMode = "off",
		profMap = { alchemy = 300, tailoring = 300 },
		spreadCount = 8,
		diversifyProfs = false,
	})
	local sharedActivePlan = 0
	for _, pr in ipairs((cdSummary and cdSummary.planRows) or {}) do
		if pr.cdInfo and pr.cdInfo.sharedGroup == "alchemy_transmute" then sharedActivePlan = sharedActivePlan + 1 end
	end
	check(sharedActivePlan == 0, "Active shared Transmute cooldown excludes all alchemy_transmute recipes from Spread Plan")

	local dash = ns.BuildDashboardInsights({
		profFilter = "all",
		unlockFilter = "all",
		craftableFilter = "all",
		applyAHCut = true,
		subCraftMode = "off",
		profMap = { alchemy = 300, tailoring = 300 },
	})
	for _, r in ipairs((dash and dash.topCrafts) or {}) do
		check(r.onCooldown ~= true, "Dashboard topCrafts excludes active on-cooldown recipe: " .. tostring(r.name))
	end
	local dashSharedCount = 0
	for _, r in ipairs((dash and dash.topCrafts) or {}) do
		if r.cdInfo and r.cdInfo.sharedGroup == "alchemy_transmute" then dashSharedCount = dashSharedCount + 1 end
	end
	for _, r in ipairs((dash and dash.topOutliers) or {}) do
		if r.cdInfo and r.cdInfo.sharedGroup == "alchemy_transmute" then dashSharedCount = dashSharedCount + 1 end
	end
	check(dashSharedCount <= 1, "Dashboard Today's Overview picks at most 1 shared alchemy_transmute across topCrafts + topOutliers")

	simCD[17187] = nil
	local changedExpired = appTbl.scanPlayerCooldowns()
	check(changedExpired == true and ch.cooldownGroups.alchemy_transmute == nil,
		"scanPlayerCooldowns detects cooldown expiration and clears cooldownGroups")
	do
		local oldGetSpellCooldown, oldCSpell, oldTradeSkill = _G.GetSpellCooldown, _G.C_Spell, _G.C_TradeSkillUI
		local oldCooldowns, oldCooldownGroups = ch.cooldowns, ch.cooldownGroups
		local now = time()
		_G.GetSpellCooldown, _G.C_Spell, _G.C_TradeSkillUI = nil, nil, nil
		ch.cooldowns = {
			[11479] = now + 1800,
			[11480] = now + 900,
			[25146] = now + 1200,
		}
		ch.cooldownGroups = { alchemy_transmute = now + 1800 }
		local arcaniteState = ns.GetRecipeCooldownInfo(arcaniteRec, now)
		local legioniteState = ns.GetRecipeCooldownInfo(bySpell[1317279], now)
		check(arcaniteState and arcaniteState.onCooldown == false and legioniteState and legioniteState.onCooldown == false,
			"Legacy Iron-to-Gold group expiry does not contaminate Arcanite or Legionite")
		check(ch.cooldownGroups.alchemy_transmute == nil and ch.cooldowns[11479] == now + 1800
			and ch.cooldowns[11480] == now + 900 and ch.cooldowns[25146] == now + 1200,
			"Shared group rebuild removes independent-spell contamination and preserves all three independent expiries")
		local ironRemaining = ns.GetPlayerRecipeCooldownRemaining(bySpell[11479], now)
		local silverRemaining = ns.GetPlayerRecipeCooldownRemaining(bySpell[11480], now)
		local fireRemaining = ns.GetPlayerRecipeCooldownRemaining(elemFireRec, now)
		check(ironRemaining == 1800 and silverRemaining == 900 and fireRemaining == 1200,
			"Independent transmute spell expiries remain available through their own recipe cooldowns")
		ch.cooldowns[17187] = now + 900
		ch.cooldowns[17563] = now + 1234
		local sharedArcanite = ns.GetPlayerRecipeCooldownRemaining(arcaniteRec, now)
		local sharedLegionite = ns.GetPlayerRecipeCooldownRemaining(bySpell[1317279], now)
		check(sharedArcanite == 900 and sharedLegionite == 1234
			and ch.cooldownGroups.alchemy_transmute == now + 1234,
			"Saved shared-spell fallback preserves per-spell expiry and caches the maximum shared expiry")
		ch.cooldowns, ch.cooldownGroups = oldCooldowns, oldCooldownGroups
		_G.GetSpellCooldown, _G.C_Spell, _G.C_TradeSkillUI = oldGetSpellCooldown, oldCSpell, oldTradeSkill
	end
	do
		local apis = { "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine",
			"GetTradeSkillRecipeLink", "GetTradeSkillCooldown" }
		local original = {}
		for _, name in ipairs(apis) do original[name] = _G[name] end
		local oldTradeSkills, oldProfessions = C_TradeSkillUI, ns.GetPlayerProfessions
		local oldScan, oldAfter = appTbl.scanPlayerCooldowns, C_Timer.After
		local oldScheduled = appTbl.refreshScheduled
		local oldNames, oldScans = ch.knownNames, ch.scannedProfs
		ch.knownNames, ch.scannedProfs = {}, {}
		C_TradeSkillUI = nil
		ns.GetPlayerProfessions = function() return { alchemy = 300 } end
		appTbl.scanPlayerCooldowns, C_Timer.After = nil, function() end
		GetNumTradeSkills = function() return 2 end
		GetTradeSkillInfo = function(i) return i == 1 and "Transmute: Arcanite" or "Transmute: Undeath to Water", "optimal" end
		GetTradeSkillLine = function() return "Alchemy", 300 end
		GetTradeSkillRecipeLink = function(i) return i == 1 and "spell:17187" or "spell:17563" end
		local arcaniteRemaining = 3000
		GetTradeSkillCooldown = function(i) return i == 1 and arcaniteRemaining or 0 end
		appTbl._tsSessionScanned, appTbl._lastTradeSkillScanTime = false, 0
		eventFrame._scripts.OnEvent(eventFrame, "TRADE_SKILL_UPDATE")
		check(ch.cooldowns[17187] > time() and ch.cooldownGroups.alchemy_transmute == ch.cooldowns[17187],
			"A ready shared spell scanned after active Arcanite leaves the shared timer in place")
		arcaniteRemaining = 0
		appTbl._tsSessionScanned, appTbl._lastTradeSkillScanTime = false, 0
		eventFrame._scripts.OnEvent(eventFrame, "TRADE_SKILL_UPDATE")
		check(ch.cooldowns[17187] == nil and ch.cooldownGroups.alchemy_transmute == nil,
			"Trade skill scan clears the shared group after the final active sibling is ready")
		C_TradeSkillUI, ns.GetPlayerProfessions = oldTradeSkills, oldProfessions
		appTbl.scanPlayerCooldowns, C_Timer.After = oldScan, oldAfter
		appTbl.refreshScheduled = oldScheduled
		ch.knownNames, ch.scannedProfs = oldNames, oldScans
		for _, name in ipairs(apis) do _G[name] = original[name] end
	end

	-- 4) UNIT_SPELLCAST_SUCCEEDED combat secret-value guard & shared cooldown stamping
	do
		local secret = setmetatable({}, {
			__eq = function() error("secret compared") end,
			__lt = function() error("secret compared") end,
			__tostring = function() error("secret formatted") end,
			__index = function() error("secret indexed") end,
		})
		local oldIsSecret = _G.issecretvalue
		local oldAfter = C_Timer and C_Timer.After
		_G.issecretvalue = function(v) return rawequal(v, secret) end
		if C_Timer then C_Timer.After = function() end end

		local okUnit = pcall(eventFrame._scripts.OnEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", secret, "cast-0", 17187)
		local okSpell = pcall(eventFrame._scripts.OnEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-0", secret)
		check(okUnit and okSpell, "UNIT_SPELLCAST_SUCCEEDED ignores secret unit/spellID without throwing")

		_G.issecretvalue = oldIsSecret
		appTbl.char.cooldowns = {}
		appTbl.char.cooldownGroups = {}
		eventFrame._scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 17187)
		check(tonumber(appTbl.char.cooldowns[17187]) ~= nil
			and tonumber(appTbl.char.cooldownGroups.alchemy_transmute) ~= nil,
			"UNIT_SPELLCAST_SUCCEEDED stamps char.cooldowns[17187] and char.cooldownGroups.alchemy_transmute")
		if C_Timer then C_Timer.After = oldAfter end
	end

	_G.GetSpellCooldown = oldGetSpellCD
	MerchantMasterDB.priceSource = savedPriceSource
	MerchantMasterDB.spreadCount = savedSpreadCount
	for sid, v in pairs(savedKnown) do ch.knownSpells[sid] = v end
	ch.cooldowns = savedCD
	ch.cooldownGroups = savedCDGroups
	for _, id in ipairs(touchIDs) do
		mockTSMPrices.dbminbuyout[id] = savedB[id]
		mockTSMPrices.dbmarket[id] = savedM[id]
		mockTSMPrices.dbregionsoldperday[id] = savedSold[id]
		mockTSMPrices.dbregionmarketavg[id] = savedRegAvg[id]
		mockTSMPrices.dbnumauctions[id] = savedNum[id]
	end
	ns.InvalidatePriceCache()
end

-- Phase 6: Per-faction reputation gating across Classic & Forever catalog recipes
do
	local byRi = {}
	for _, r in ipairs(ns.RECIPES) do
		if r.recipeItemID then byRi[r.recipeItemID] = r end
	end

	local earthWater = byRi[13484]
	check(earthWater ~= nil and earthWater.rep == 5 and earthWater.repFactionID == 576 and earthWater.repFaction == "Timbermaw Hold",
		"Transmute: Earth to Water (13484) carries Timbermaw Hold Friendly rep")
	local campExalted = { standing = 8, playerFaction = "Horde" }
	local abDenied = ns.EvaluateCraftAbility(earthWater, { alchemy = 300 }, campExalted)
	check(abDenied.meetsRep == false and abDenied.reqRep == 5 and abDenied.repFactionID == 576 and abDenied.repFactionName == "Timbermaw Hold",
		"Camp Exalted alone never unlocks Timbermaw Hold recipe")
	check(abDenied.vendorCopperCost == 15000 and abDenied.vendorCostText ~= nil and abDenied.cellText:find(abDenied.vendorCostText, 1, true) ~= nil and abDenied.howDetail:find("Requires Timbermaw Hold Friendly", 1, true) ~= nil and abDenied.reasonText:find("Timbermaw Hold Friendly", 1, true) ~= nil,
		"Timbermaw denial preserves vendor cost and surfaces faction requirement")

	local abAllowed = ns.EvaluateCraftAbility(earthWater, { alchemy = 300 }, { standing = 4, playerFaction = "Horde", factions = { [576] = 5 } })
	check(abAllowed.meetsRep == true, "Timbermaw Hold Friendly unlocks Transmute: Earth to Water")

	local airFire = byRi[13482]
	check(airFire and airFire.rep == 6 and airFire.repFactionID == 529 and airFire.repFaction == "Argent Dawn",
		"Transmute: Air to Fire (13482) requires Argent Dawn Honored")
	local elemFire = byRi[20761]
	check(elemFire and elemFire.rep == 5 and elemFire.repFactionID == 59 and elemFire.repFaction == "Thorium Brotherhood",
		"Transmute: Elemental Fire (20761) requires Thorium Brotherhood Friendly")
	local dreamless = byRi[20012]
	check(dreamless and dreamless.acqType == "vendor" and dreamless.recipeVendorPrice == 50000 and dreamless.rep == 5 and dreamless.repFactionID == 270 and dreamless.repFaction == "Zandalar Tribe",
		"Greater Dreamless Sleep Potion (20012) is Zandalar Tribe Friendly 5g vendor")
	local trollsBlood = byRi[20014]
	check(trollsBlood and trollsBlood.outputItemID == 20004 and trollsBlood.rep == 6 and trollsBlood.repFactionID == 270,
		"Major Troll's Blood Potion requires Zandalar Tribe Honored")
	local friendly = { standing = 4, factions = { [270] = 5 }, factionsDigest = "270:5" }
	local honored = { standing = 4, factions = { [270] = 6 }, factionsDigest = "270:6" }
	for _, skills in ipairs({ { alchemy = 1 }, { tailoring = 300 }, {} }) do
		local ability = ns.EvaluateCraftAbility(trollsBlood, skills, friendly)
		check(ability.meetsRep == false and ability.cellText:find("Honored", 1, true),
			"Unlearned Major Troll's Blood Potion shows Honored even when the profession or skill is missing")
	end
	do
		local id = trollsBlood.outputItemID
		local priceSource = MerchantMasterDB.priceSource
		MerchantMasterDB.priceSource = "auto"
		local original = {}
		for key, value in pairs({ dbminbuyout = 1000000, dbmarket = 1000000,
			dbregionmarketavg = 1000000, dbnumauctions = 1, dbregionsoldperday = 10 }) do
			original[#original + 1] = { key, mockTSMPrices[key][id] }
			mockTSMPrices[key][id] = value
		end
		ns.InvalidatePriceCache()
		local opts = { search = "Major Troll's Blood", profFilter = "alchemy", profMap = { alchemy = 300 },
			outlierQuality = "all", repState = friendly }
		local function potion(rows)
			for _, row in ipairs(rows) do
				if row.itemID == id then return row end
			end
		end
		local function checkStanding(row, met, view)
			check(row and row.reqRep == 6 and row.repSort == 6 and row.repLabel == "Honored"
				and row.repFactionName == "Zandalar Tribe" and row.repMet == met,
				view .. " exposes Zandalar Tribe Honored with repMet=" .. tostring(met))
		end
		ns.BeginEval()
		local lockedOutlier = potion(ns.BuildOutlierRows(opts))
		local lockedSpread = potion(ns.BuildProfitSpreadRows(opts))
		opts.repState = honored
		local metOutlier = potion(ns.BuildOutlierRows(opts))
		local metSpread = potion(ns.BuildProfitSpreadRows(opts))
		ns.EndEval()
		checkStanding(lockedOutlier, false, "Monopolies")
		checkStanding(lockedSpread, false, "Daily Crafts")
		checkStanding(metOutlier, true, "Monopolies after faction changes in the same evaluation")
		checkStanding(metSpread, true, "Daily Crafts after faction changes in the same evaluation")
		local palette = ns.Theme.PALETTES[ns.Theme.GetMode()]
		for _, view in ipairs({ { ns.app.ui.outliersTable, lockedOutlier, metOutlier },
			{ ns.app.ui.profitSpreadTable, lockedSpread, metSpread } }) do
			view[1].setRows({ view[2], view[3] })
			local frames = view[1].scrollBox._frames
			check(view[1].columns[3].key == "repSort"
				and frames[1].cells[3]:GetText() == "|cff" .. palette.hexDanger .. "Honored|r"
				and frames[2].cells[3]:GetText() == "|cff" .. palette.hexPositive .. "Honored|r",
				"Rep column uses palette danger and positive colors for Honored")
			local lockedName, metName = frames[1].cells[1], frames[2].cells[1]
			lockedName:GetScript("OnEnter")(lockedName)
			check(table.concat(GameTooltip._lines, " "):find("Zandalar Tribe - Honored (Required)", 1, true),
				"Recipe tooltip names the required faction and standing")
			metName:GetScript("OnEnter")(metName)
			check(table.concat(GameTooltip._lines, " "):find("Zandalar Tribe - Honored (Met)", 1, true),
				"Recipe tooltip shows when the faction requirement is met")
		end
		GameTooltip:Hide()
		for _, entry in ipairs(original) do mockTSMPrices[entry[1]][id] = entry[2] end
		MerchantMasterDB.priceSource = priceSource
		ns.InvalidatePriceCache()
	end
	local cenBag = byRi[22310]
	local kaniaFree = byRi[22308]
	check(cenBag and cenBag.rep == 5 and cenBag.repFactionID == 609 and cenBag.repFaction == "Cenarion Circle",
		"Cenarion Herb Bag (22310) requires Cenarion Circle Friendly")
	check(kaniaFree and (kaniaFree.rep or 0) == 0, "Enchanted Runecloth Bag (22308) has no rep gate")
	local earthenHelm = byRi[276976]
	check(earthenHelm and earthenHelm.rep == 5 and earthenHelm.repFactionID == 2787 and earthenHelm.repFaction == "Earthen Ring",
		"Cloudy Skyforged Helm (276976) requires Earthen Ring Friendly (2787)")
	local earthenDenied = ns.EvaluateCraftAbility(earthenHelm, { blacksmithing = 300 }, { standing = 8, playerFaction = "Horde", factions = { ["Earthen Ring"] = 4 } })
	local earthenMet = ns.EvaluateCraftAbility(earthenHelm, { blacksmithing = 300 }, { standing = 4, playerFaction = "Horde", factions = { ["Earthen Ring"] = 5 } })
	check(earthenDenied.meetsRep == false and earthenMet.meetsRep == true,
		"Name-keyed Earthen Ring faction standing gates Cloudy Skyforged Helm")

	local jaggedShield = byRi[22219]
	local obsidianMail = byRi[22221]
	check(jaggedShield and jaggedShield.rep == 7 and jaggedShield.repFactionID == 609 and jaggedShield.repFaction == "Cenarion Circle" and jaggedShield.acqType == "quest",
		"Jagged Obsidian Shield (22219) requires Cenarion Circle Revered via AQ20 quest")
	check(obsidianMail and obsidianMail.rep == 8 and obsidianMail.repFactionID == 609 and obsidianMail.repFaction == "Cenarion Circle" and obsidianMail.acqType == "quest",
		"Obsidian Mail Tunic (22221) requires Cenarion Circle Exalted via AQ20 quest")

	local kirinHelm = byRi[276984]
	check(kirinHelm and kirinHelm.acqType == "vendor" and kirinHelm.recipeVendorPrice == 100000 and kirinHelm.vendorA == "Archmage Alvareaux" and kirinHelm.rep == 5 and kirinHelm.repFactionID == 2740,
		"Kirin Tor recipe (276984) carries vendor source, 10g price, Archmage Alvareaux, Friendly")
	local nightclawWrist = byRi[276929]
	check(nightclawWrist and nightclawWrist.acqType == "vendor" and nightclawWrist.recipeVendorPrice == 950 and nightclawWrist.vendorA == "Vayn Moongaze" and nightclawWrist.rep == 5 and nightclawWrist.repFactionID == 2758,
		"Nightclaw Druids recipe (276929) carries vendor source, 9s 50c price, Vayn Moongaze, Friendly")
	local ccVargus = byRi[275598]
	local ccMishta = byRi[275580]
	check(ccVargus and ccVargus.acqType == "vendor" and ccVargus.recipeVendorPrice == 75000 and ccVargus.vendorA == "Vargus" and ccVargus.rep == 5 and ccVargus.repFactionID == 609,
		"Silithus CC recipe (275598) carries Vargus vendor source and 7g 50s price")
	check(ccMishta and ccMishta.acqType == "vendor" and ccMishta.recipeVendorPrice == 75000 and ccMishta.vendorA == "Mishta" and ccMishta.rep == 5 and ccMishta.repFactionID == 609,
		"Silithus CC recipe (275580) carries Mishta vendor source and 7g 50s price")
end

-- Daily AH history survives the legacy ring cap and reports honest week coverage.
do
	local savedTime = _G.time
	local appForHistory = ns.app
	local savedRefresh, savedWarm = appForHistory.refresh, appForHistory.warmSuperListCache
	local savedBrowseResults = _G.C_AuctionHouse.GetBrowseResults
	local savedThrottleReady = _G.C_AuctionHouse.IsThrottledMessageSystemReady
	local savedSelectResult = _G.AuctionHouseFrame.SelectBrowseResult
	local savedStartSearch = _G.AuctionHouseFrame.SearchBar.StartSearch
	local savedAuctionatorGlobal = _G.Auctionator
	appForHistory.refresh = function() end
	appForHistory.warmSuperListCache = function() end
	local now = math.floor(1794000000/86400)*86400
	_G.time = function() return now end
	local id, econ = 2447, ns.DetectActiveEconomy()
	MerchantMasterDB.ahDaily = MerchantMasterDB.ahDaily or {}
	MerchantMasterDB.ahDaily[econ] = {}
	MerchantMasterDB.ahHistory = MerchantMasterDB.ahHistory or {}
	MerchantMasterDB.ahHistory[econ] = {}
	_G.AuctionHouseFrame:Show()
	local dailyPrice = 100
	_G.C_AuctionHouse.GetBrowseResults = function()
		return {{itemKey={itemID=id,itemLevel=0,itemSuffix=0},totalQuantity=100,minPrice=dailyPrice}}
	end
	for day = 1, 8 do
		dailyPrice = day * 100
		for scan = 1, 5 do
			now = math.floor(1794000000/86400)*86400 + (day-1)*86400 + (scan-1)*3*3600
			appForHistory.refreshAllMarketValues()
			eventFrame._scripts.OnEvent(eventFrame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		end
	end
	local daily = MerchantMasterDB.ahDaily[econ][id]
	check(type(daily)=="table" and #daily==8, "40 AH scans across 8 days preserve all 8 daily buckets (got " .. tostring(daily and #daily) .. ")")
	check(#MerchantMasterDB.ahHistory[econ][id] <= 16, "Legacy AH history ring remains capped at 16 entries")
	local trend = ns.MarketScan.GetItemTrend7d(id,econ,now)
	check(trend and trend.source=="ahDaily" and trend.daysCollected==7 and trend.hasFullWeek==true,
		"Seven day trend counts the 7 in-window daily buckets")
	check(trend.currentPrice==800 and trend.startPrice7d==200 and math.abs(trend.trendPct-300)<0.001 and trend.direction=="up",
		"Seven day trend compares oldest and latest daily prices accurately")
	_G.C_AuctionHouse.GetBrowseResults = function()
		return {{itemKey={itemID=id,itemLevel=0,itemSuffix=0},totalQuantity=0,minPrice=0}}
	end
	appForHistory.refreshAllMarketValues()
	eventFrame._scripts.OnEvent(eventFrame,"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	local sameDay=daily[#daily]
	check(sameDay.minP==800 and sameDay.lastP==800 and sameDay.lastQ==0,
		"An absent scan sets today's quantity to zero and preserves valid daily prices")
	local fallingID=118
	local currentDay=math.floor(now/86400)
	MerchantMasterDB.ahDaily[econ][fallingID]={}
	for age=6,0,-1 do
		local price=(age+1)*100
		MerchantMasterDB.ahDaily[econ][fallingID][#MerchantMasterDB.ahDaily[econ][fallingID]+1]={
			d=currentDay-age,minP=price,maxP=price,lastP=price,maxQ=1,lastQ=1,at=now-age*86400}
	end
	local falling=ns.MarketScan.GetItemTrend7d(fallingID,econ,now)
	check(falling and falling.daysCollected==7 and falling.hasFullWeek and math.abs(falling.trendPct+85.7142857)<0.001 and falling.direction=="down",
		"Seven day trend reports a falling price as a negative percentage")
	local partialID=999765
	MerchantMasterDB.ahDaily[econ][partialID]={
		{d=math.floor(now/86400)-1,minP=300,maxP=300,lastP=300,maxQ=4,lastQ=4,at=now-86400},
		{d=math.floor(now/86400),minP=200,maxP=200,lastP=200,maxQ=5,lastQ=5,at=now},
	}
	MerchantMasterDB.ahHistory[econ][partialID]=nil
	local partial=ns.MarketScan.GetItemTrend7d(partialID,econ,now)
	check(partial and partial.daysCollected==2 and partial.hasFullWeek==false and partial.direction=="insufficient",
		"Partial trend reports 2 of 7 collected days without claiming a full week")
	MerchantMasterDB.ahDaily[econ][partialID]="corrupt"
	MerchantMasterDB.ahHistory[econ][partialID]={
		{t=now-86400,p=300,q=2}, {t=now-86400+60,p=280,q=3}, {t=now,p=200,q=4},
		{t=now-8*86400,p=900,q=9},
	}
	local historyTrend=ns.MarketScan.GetItemTrend7d(partialID,econ,now)
	check(historyTrend and historyTrend.source=="ahHistory" and historyTrend.daysCollected==2
		and historyTrend.points[1].d==math.floor(now/86400)-1 and historyTrend.points[1].price==280,
		"History fallback uses distinct recent days and the latest scan per day")

	local mergeID = 999766
	MerchantMasterDB.ahDaily[econ][mergeID] = {
		{ d = currentDay - 2, lastP = 500, lastQ = 12, at = now - 2 * 86400,
			scanPairs = 2, scanSeconds = 1200, scanUnits = 4 },
		{ d = currentDay, lastP = 300, lastQ = 8, at = now },
	}
	MerchantMasterDB.ahHistory[econ][mergeID] = {
		{ t = now - 3 * 86400, p = 600, q = 10 },
		{ t = now - 3 * 86400 + 600, p = 600, q = 8 },
		{ t = now - 3 * 86400 + 1200, p = 610, q = 6 },
		{ t = now - 2 * 86400 + 60, p = 450, q = 9 },
		{ t = now - 86400, p = 400, q = 7 },
	}
	local merged = ns.MarketScan.GetItemTrend7d(mergeID, econ, now)
	check(merged.daysCollected == 4 and not merged.hasFullWeek and merged.points[1].d == currentDay - 3
		and merged.points[1].price == 610 and merged.points[2].price == 500
		and merged.points[3].price == 400 and merged.points[4].price == 300,
		"Weekly trends merge distinct days in order and prefer daily buckets on overlap")
	check(merged.points[2].salesPerDay == 16 and merged.points[1].salesPerDay > 0,
		"Merged trends preserve velocity for daily buckets and ring-only days")
	MerchantMasterDB.ahDaily[econ][partialID]={}
	MerchantMasterDB.ahHistory[econ][partialID]=nil
	_G.Auctionator={Database={GetPriceHistory=function() error("Forbidden legacy Auctionator.Database:GetPriceHistory called!") end}}
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	local noAucTrend=ns.MarketScan.GetItemTrend7d(partialID,nil,now)
	check(ns.GetAuctionatorMarketStats==nil and noAucTrend and noAucTrend.source=="none" and noAucTrend.daysCollected==0,
		"Standalone GetItemTrend7d ignores legacy Auctionator and returns source='none' when no local/snapshot history exists")
	_G.Auctionator=savedAuctionatorGlobal
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	local selected = false
	_G.AuctionHouseFrame.SelectBrowseResult = function(_, result) selected=result end
	_G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
	_G.AuctionHouseFrame.SearchBar.StartSearch = function()
		_G.C_AuctionHouse.SendBrowseQuery({searchString="Peacebloom"})
	end
	_G.C_AuctionHouse.GetBrowseResults = function()
		return {{itemKey={itemID=id,itemLevel=0,itemSuffix=0},totalQuantity=37,minPrice=950}}
	end
	appForHistory.searchAH("Peacebloom",1,id)
	eventFrame._scripts.OnEvent(eventFrame,"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	check(not selected and sameDay.lastQ==0, "An older browse cannot update daily history while the item search is throttled")
	_G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
	eventFrame._scripts.OnEvent(eventFrame,"AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
	eventFrame._scripts.OnEvent(eventFrame,"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	check(selected and MerchantMasterDB.ahPrices[econ][id].price==950 and MerchantMasterDB.ahPrices[econ][id].qty==37,
		"Dispatched single item browse result updates the live price record")
	local newest=MerchantMasterDB.ahDaily[econ][id][#MerchantMasterDB.ahDaily[econ][id]]
	check(newest.lastP==950 and newest.lastQ==37 and newest.at==now,
		"Single item browse result is recorded in the current daily bucket")
	_G.time = savedTime
	appForHistory.refresh, appForHistory.warmSuperListCache = savedRefresh, savedWarm
	_G.C_AuctionHouse.GetBrowseResults = savedBrowseResults
	_G.C_AuctionHouse.IsThrottledMessageSystemReady = savedThrottleReady
	_G.AuctionHouseFrame.SelectBrowseResult = savedSelectResult
	_G.AuctionHouseFrame.SearchBar.StartSearch = savedStartSearch
end

-- Targeted searches for every turn-in dependency use the same rolling history as recipes.
do
	local seen = {}
	local function verifyItem(id)
		if seen[id] then return end
		seen[id] = true
		check(ns.ALL_CATALOG_IDS[id], "Turn-in dependency is registered for scanning: " .. id)
		for _, recipe in ipairs(ns.RECIPES_BY_OUTPUT[id] or {}) do
			for _, reagent in ipairs(recipe.reagents or {}) do verifyItem(reagent.itemID or reagent[1]) end
		end
	end
	for _, writ in ipairs(ns.WRITS) do
		verifyItem(writ.itemID)
		verifyItem(writ.requiredItemID)
		for _, reagent in ipairs(writ.reagents or {}) do verifyItem(reagent.itemID or reagent[1]) end
	end
	for _, crate in ipairs(ns.CRATES) do
		verifyItem(crate.itemID)
		for _, bundle in ipairs(crate.bundles) do verifyItem(bundle.itemID) end
	end

	local app, oldAH, oldTime = ns.app, _G.C_AuctionHouse, _G.time
	local refresh, warm = app.refresh, app.warmSuperListCache
	app.refresh, app.warmSuperListCache = function() end, function() end
	app.cancelOrderBookScan()
	local econ = ns.DetectActiveEconomy()
	local start = math.floor(1794000000 / 86400) * 86400
	local now, full, count = start, false, 2
	local scroll, required = ns.WRITS[1].itemID, ns.WRITS[1].requiredItemID
	local crate, bundle = ns.CRATES[1].itemID, ns.CRATES[1].bundles[1].itemID
	local events, key = ns.MarketScan.HandleEvent, { itemID = crate }
	local daily = MerchantMasterDB.ahDaily[econ]
	if MerchantMasterDB.ahVariants then MerchantMasterDB.ahVariants[econ] = nil end
	for _, id in ipairs({ scroll, required, crate, bundle }) do daily[id] = nil end
	_G.time = function() return now end
	_G.C_AuctionHouse = setmetatable({
		HasFullCommoditySearchResults = function() return full end,
		GetNumCommoditySearchResults = function() return count end,
		GetCommoditySearchResultInfo = function(_, i) return { unitPrice = 100 * i, quantity = 4 * i, numOwnerItems = i } end,
		HasFullItemSearchResults = function() return full end,
		GetNumItemSearchResults = function() return count end,
		GetItemSearchResultInfo = function(_, i) return { buyoutAmount = i == 1 and 2 or 404, quantity = 2 * i, containsOwnerItem = i == 1 } end,
	}, { __index = oldAH })
	events("COMMODITY_SEARCH_RESULTS_UPDATED", scroll)
	events("ITEM_SEARCH_RESULTS_UPDATED", key)
	check(daily[scroll] == nil and daily[crate] == nil, "Truncated searches leave both histories untouched")
	full = true
	for day = 0, 16 do
		now = start + day * 86400
		for _, id in ipairs({ scroll, required, bundle }) do events("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
		events("ITEM_SEARCH_RESULTS_UPDATED", key)
	end
	for _, id in ipairs({ scroll, required, crate, bundle }) do
		local price, stock = id == crate and 101 or 100, id == crate and 4 or 9
		local marketPrice, marketStock = id == crate and 1 or 100, id == crate and 6 or 12
		local live = MerchantMasterDB.ahPrices[econ][id]
		local trend = ns.MarketScan.GetItemTrend7d(id, econ, now)
		check(live.price == price and live.qty == stock, "Complete search updates competitor-only live prices and stock")
		check(#daily[id] == 14 and daily[id][14].lastQ == marketStock and daily[id][14].lastP == marketPrice
			and #MerchantMasterDB.ahHistory[econ][id] <= 16, "Daily and ring histories preserve market stock including owned lots")
		check(trend.daysCollected == 7 and trend.currentPrice == marketPrice, "Turn-in searches feed weekly market trends")
	end
	count = 0
	local liveCrate, marketCrate = MerchantMasterDB.ahPrices[econ][crate], daily[crate][14]
	events("ITEM_SEARCH_RESULTS_UPDATED", { itemID = crate, itemLevel = 10 })
	check(MerchantMasterDB.ahPrices[econ][crate] == liveCrate and marketCrate.lastQ == 6,
		"Complete empty item-level search preserves base-item stock and history")
	check(not (MerchantMasterDB.ahVariants and MerchantMasterDB.ahVariants[econ] and MerchantMasterDB.ahVariants[econ][crate]),
		"An empty item-level result leaves the variant marker unset")
	full = false
	events("ITEM_SEARCH_RESULTS_UPDATED", key)
	check(marketCrate.lastQ == 6, "Truncated empty item page preserves the last observed supply")
	full = true
	events("ITEM_SEARCH_RESULTS_UPDATED", key)
	check(marketCrate.lastQ == 0, "Complete empty item page records observed zero supply")

	local browseVariantName = "Synthetic Re-Audit Bundle"
	local variantKey = { itemID = bundle, itemLevel = 10, itemSuffix = 0, battlePetSpeciesID = 0 }
	local ah = _G.C_AuctionHouse
	local priorLots = MerchantMasterDB.ahLots[econ][bundle]
	local priorPrice = MerchantMasterDB.ahPrices[econ][bundle]
	local priorHistory = daily[bundle][#daily[bundle]]
	local priorHistoryP, priorHistoryQ, priorHistoryAt = priorHistory.lastP, priorHistory.lastQ, priorHistory.at
	local priorGetTime = _G.GetTime
	local priorHasFullItems = ah.HasFullItemSearchResults
	local priorNumItems = ah.GetNumItemSearchResults
	local priorItemResultInfo = ah.GetItemSearchResultInfo
	_G.GetTime = function() return priorGetTime() + 30 end
	ah.IsThrottledMessageSystemReady = function() return true end
	ah.SendBrowseQuery = function() end
	ah.GetBrowseResults = function()
		return { { itemKey = variantKey, totalQuantity = 0, minPrice = 0 } }
	end
	ah.GetItemKeyInfo = function(k)
		return { itemName = k.itemLevel == 10 and browseVariantName or ns.ITEM_NAMES_BY_ID[k.itemID],
			isCommodity = k.itemID == bundle and (k.itemLevel or 0) == 0 }
	end
	ah.SendSearchQuery = function() end
	ah.HasFullItemSearchResults = function() return true end
	ah.GetNumItemSearchResults = function() return 0 end
	ah.GetItemSearchResultInfo = function() return nil end
	_G.AuctionHouseFrame:Show()
	ns.MarketScan.ScanBagCrates({ { name = "Synthetic crate", bundles = { { name = browseVariantName, count = 1000000 } } } })
	local variantJob, variantQueued = ns.MarketScan.GetBagStatus()
	check(variantJob ~= nil, "Unknown-name bag scan starts a Browse lookup (job=" .. tostring(variantJob)
		.. ", queued=" .. tostring(variantQueued) .. ", shown=" .. tostring(_G.AuctionHouseFrame:IsShown())
		.. ", total=" .. tostring(app.lotScanTotal) .. ")")
	_G.GetTime = function() return priorGetTime() + 32 end
	events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	local activeVariantJob = ns.MarketScan.GetBagStatus()
	for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED" }) do
		events(event)
		check(ns.MarketScan.GetBagStatus() == activeVariantJob and MerchantMasterDB.ahPrices[econ][bundle] == priorPrice
			and priorPrice.qty == 9 and priorHistory.lastQ == 12,
			event .. " without a key cannot complete an item variant or overwrite base stock/history")
	end
	events("ITEM_SEARCH_RESULTS_UPDATED", variantKey)
	check(ns.MarketScan.GetBagStatus() == nil and MerchantMasterDB.ahLots[econ][bundle] == priorLots
		and MerchantMasterDB.ahPrices[econ][bundle] == priorPrice and daily[bundle][#daily[bundle]] == priorHistory
		and priorHistory.lastP == priorHistoryP and priorHistory.lastQ == priorHistoryQ and priorHistory.at == priorHistoryAt
		and app.costs["Synthetic crate"][browseVariantName].short == 1000000,
		"Empty level-10 active bag result serves the request without overwriting base stock or history")
	-- A partial nonempty variant result must obey the same base-cache guard.
	app.itemIDs[browseVariantName] = nil
	_G.GetTime = function() return priorGetTime() + 34 end
	ns.MarketScan.ScanBagCrates({ { name = "Synthetic crate", bundles = { { name = browseVariantName, count = 1000000 } } } })
	_G.GetTime = function() return priorGetTime() + 36 end
	events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	ah.HasFullItemSearchResults = function() return false end
	ah.GetNumItemSearchResults = function() return 1 end
	ah.GetItemSearchResultInfo = function() return { buyoutAmount = 300, quantity = 3, containsOwnerItem = false } end
	events("ITEM_SEARCH_RESULTS_UPDATED", variantKey)
	check(ns.MarketScan.GetBagStatus() == nil and MerchantMasterDB.ahPrices[econ][bundle] == priorPrice
		and MerchantMasterDB.ahLots[econ][bundle] == priorLots and priorHistory.lastQ == 12,
		"Partial nonempty variant results cannot write base prices, lots or history")
	ah.HasFullItemSearchResults = priorHasFullItems
	ah.GetNumItemSearchResults = priorNumItems
	ah.GetItemSearchResultInfo = priorItemResultInfo

	count, now = 2, start + 17 * 86400
	ah.IsThrottledMessageSystemReady = function() return true end
	ah.GetBrowseResults = function()
		return {
			{ itemKey = { itemID = bundle }, totalQuantity = 12, minPrice = 100 },
			{ itemKey = { itemID = crate }, totalQuantity = 3, minPrice = 300 },
		}
	end
	ah.HasFullBrowseResults = function() return true end
	_G.AuctionHouseFrame:Show()
	app.refreshAllMarketValues()
	events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	local browseBidOnlyDaily = daily[crate][#daily[crate]]
	check(browseBidOnlyDaily.lastP == 300 and browseBidOnlyDaily.lastQ == 3,
		"Browse history includes all three listed units at the positive buyout minimum")
	count = 3
	ah.GetItemSearchResultInfo = function(_, i)
		if i == 1 then return { buyoutAmount = 300, quantity = 1, containsOwnerItem = false } end
		return { buyoutAmount = 0, quantity = 1, containsOwnerItem = false }
	end
	events("ITEM_SEARCH_RESULTS_UPDATED", key)
	local bidOnlyLots = MerchantMasterDB.ahLots[econ][crate].lots
	local bidOnlyDaily = daily[crate][#daily[crate]]
	check(MerchantMasterDB.ahPrices[econ][crate].qty == 1 and bidOnlyLots[1].qty == 1
		and bidOnlyDaily.lastP == 300 and bidOnlyDaily.lastQ == 3,
		"Item-search history matches Browse quantity while purchasable stock and lots include buyouts only")
	ah.GetItemSearchResultInfo = priorItemResultInfo
	count = 2
	now = now + 1200
	local oldGetTime = _G.GetTime
	local elapsed = oldGetTime() + 10
	_G.GetTime = function() return elapsed end
	app.scanOrderBookItems({ bundle }, 1)
	_G.GetTime = oldGetTime
	local job = ns.MarketScan.GetBagStatus()
	check(job and job.itemID == bundle, "Order-book job is running for the bundle")
	for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED" }) do
		local previous = MerchantMasterDB.ahPrices[econ][scroll]
		events(event, scroll)
		check(MerchantMasterDB.ahPrices[econ][scroll] ~= previous and daily[scroll][#daily[scroll]].lastQ == 12,
			event .. " records another commodity during an active bag job")
	end
	for _, event in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }) do
		local previous = MerchantMasterDB.ahPrices[econ][crate]
		events(event, key)
		check(MerchantMasterDB.ahPrices[econ][crate] ~= previous and daily[crate][#daily[crate]].lastQ == 6,
			event .. " records an unrelated item key during an active bag job")
	end
	check(ns.MarketScan.GetBagStatus() == job, "Passive searches leave the order-book job active")
	events("COMMODITY_SEARCH_RESULTS_RECEIVED", bundle)
	check(not ns.MarketScan.GetBagStatus(), "Matching result completes the order-book job")
	local bundleMarket = daily[bundle][#daily[bundle]]
	local bundleLots = MerchantMasterDB.ahLots[econ][bundle].lots
	check(bundleMarket.lastQ == 12 and bundleMarket.lastP == 100 and bundleMarket.scanUnits == 0
		and MerchantMasterDB.ahPrices[econ][bundle].qty == 9 and bundleLots[1].qty == 3 and bundleLots[2].qty == 6,
		"Switching from full Browse to an owned-plus-competitor order book creates no false sales")
	check(ns.MarketScan.GetLocalVelocity(bundle, econ).latestQty == 12,
		"Ring velocity uses the same market-wide stock as daily history")

	-- Complete Browse supply is independent of whether any listing has a buyout.
	do
		local priceBefore = MerchantMasterDB.ahPrices[econ][crate]
		local quote, quotedAt = priceBefore.price, priceBefore.at
		local browseRows = { { itemKey = key, totalQuantity = 3, minPrice = 0 } }
		ah.GetBrowseResults = function() return browseRows end
		now = now + 1200
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		local live = MerchantMasterDB.ahPrices[econ][crate]
		check(daily[crate][#daily[crate]].lastQ == 3 and live.qty == 3 and live.absent == false
			and live.price == nil and live.lastPrice == quote and live.lastAt == quotedAt,
			"Full Browse records bid-only supply and preserves the previous positive quote timestamp")
		local browseSnapshot = live
		local oldSecret = _G.issecretvalue
		local secret = {}
		_G.issecretvalue = function(value) return value == secret end
		browseRows[1].minPrice = secret
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(MerchantMasterDB.ahPrices[econ][crate] == browseSnapshot and daily[crate][#daily[crate]].lastQ == 3,
			"Unreadable Browse price leaves verified supply untouched")
		_G.issecretvalue = oldSecret
		browseRows[1].totalQuantity, browseRows[1].minPrice = 0, 999
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(MerchantMasterDB.ahPrices[econ][crate] == browseSnapshot and daily[crate][#daily[crate]].lastQ == 3,
			"Full Browse rejects an empty row claiming a positive buyout minimum")
		browseRows[1].totalQuantity, browseRows[1].minPrice = 3, 0
		browseSnapshot.price = 0 -- Legacy zero quotes must not mask the last positive quote.
		local oldStart = _G.AuctionHouseFrame.SearchBar.StartSearch
		_G.AuctionHouseFrame.SearchBar.StartSearch = function() ah.SendBrowseQuery({ searchString = ns.ItemName(crate) }) end
		now = now + 1200
		app.searchAH(ns.ItemName(crate), 1, crate)
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		live = MerchantMasterDB.ahPrices[econ][crate]
		check(daily[crate][#daily[crate]].at == now and live.qty == 3 and not live.absent
			and live.lastPrice == quote and live.lastAt == quotedAt,
			"Unrestricted wanted Browse records bid-only supply without losing the last quote")
		local bidBucket = daily[crate][#daily[crate]]
		local bidUnits = bidBucket.scanUnits
		browseRows[1].totalQuantity = 1
		now = now + 1200
		app.searchAH(ns.ItemName(crate), 1, crate)
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		live = MerchantMasterDB.ahPrices[econ][crate]
		approxEq(bidBucket.scanUnits - bidUnits, 1.1, 0.00001,
			"Consecutive bid-only Browse snapshots use unchanged-price velocity")
		browseRows[1].totalQuantity, browseRows[1].minPrice = 0, 999
		local previousWanted = live
		app.searchAH(ns.ItemName(crate), 1, crate)
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(MerchantMasterDB.ahPrices[econ][crate] == previousWanted and daily[crate][#daily[crate]].lastQ == 1,
			"Wanted Browse rejects an empty row claiming a positive buyout minimum")
		browseRows[1].minPrice = 0
		app.searchAH(ns.ItemName(crate), 1, crate)
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		live = MerchantMasterDB.ahPrices[econ][crate]
		check(live.absent == true and live.price == nil and live.lastPrice == quote and live.lastAt == quotedAt
			and daily[crate][#daily[crate]].lastQ == 0,
			"Wanted Browse verified zero supply publishes absence and preserves the last positive quote")
		_G.AuctionHouseFrame.SearchBar.StartSearch = oldStart
	end

	-- Positive stack buyouts remain purchasable even below half a copper per unit.
	count = 1
	ah.GetItemSearchResultInfo = function() return { buyoutAmount = 1, quantity = 3, containsOwnerItem = false } end
	_G.GetTime = function() return priorGetTime() + 90 end
	events("ITEM_SEARCH_RESULTS_UPDATED", key)
	check(MerchantMasterDB.ahPrices[econ][crate].price == 1 and MerchantMasterDB.ahPrices[econ][crate].qty == 3
		and MerchantMasterDB.ahPrices[econ][crate].absent == false and MerchantMasterDB.ahLots[econ][crate].lots[1].price == 1
		and MerchantMasterDB.ahLots[econ][crate].lots[1].qty == 3 and daily[crate][#daily[crate]].lastQ == 3,
		"One-copper stack keeps its lot, quantity and non-absent state with a one-copper unit floor")

	do
		local market, db = ns.MarketScan, MerchantMasterDB
		local prices = db.ahPrices[econ]
		local scannedAt, refreshedAt, quote = prices._scannedAt, db.lastRefreshAt, prices[crate]
		local getBrowseResults, oldSecret, oldPrint, oldToast = ah.GetBrowseResults, _G.issecretvalue, _G.print, app.ui.toast
		local secret, chat, toast = {}
		_G.issecretvalue = function(value) return value == secret end
		_G.print = function(message)
			if message:find("Live AH scan", 1, true) then chat = message else oldPrint(message) end
		end
		app.ui.toast = { ShowToast = function(message) toast = message end }
		ah.GetBrowseResults = function() return {
			{ itemKey = key, totalQuantity = 3, minPrice = 100 },
			{ itemKey = { itemID = secret }, totalQuantity = 9, minPrice = 100 },
		} end
		now = now + 1200
		app.refreshAllMarketValues()
		local pendingRefreshAt = db.lastRefreshAt
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		ah.GetBrowseResults, _G.issecretvalue, _G.print, app.ui.toast = getBrowseResults, oldSecret, oldPrint, oldToast
		local state = market.GetState()
		local freshness = ns.AHRefresh.GetFreshness(state.completedAt, now)
		check(pendingRefreshAt == refreshedAt and db.lastRefreshAt == refreshedAt and prices._scannedAt == scannedAt
			and state.completedAt == scannedAt and freshness.age == now - scannedAt and freshness.age > 0,
			"An unreadable Browse item ID preserves both freshness timestamps through start and finish")
		check(not state.active and state.partial and prices[crate] == quote,
			"An unreadable Browse item ID finishes as partial and preserves the prior quote")
		check(chat and chat:find("partial", 1, true) and chat:find("incomplete results", 1, true)
			and toast and toast:find("AH Scan Partial", 1, true),
			"An incomplete Browse reports partial completion in chat and toast")
	end

	-- An item-key search covers only the base key when Browse has shown suffix supply.
	do
		local base = { itemID = crate }
		local suffix = { itemID = crate, itemSuffix = 7 }
		ah.GetBrowseResults = function() return {
			{ itemKey = base, totalQuantity = 3, minPrice = 100 },
			{ itemKey = suffix, totalQuantity = 9, minPrice = 100 },
		} end
		now = now + 1200
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(MerchantMasterDB.ahVariants[econ][crate], "Full Browse persists the observed suffix marker")
		local bucket = daily[crate][#daily[crate]]
		local beforeUnits, beforeAt, beforePairs = bucket.scanUnits, bucket.at, bucket.scanPairs
		local ring = MerchantMasterDB.ahHistory[econ][crate]
		local beforeRing = #ring
		now = now + 1200
		events("ITEM_SEARCH_RESULTS_UPDATED", base)
		check(bucket.lastQ == 12 and bucket.at == beforeAt and bucket.scanUnits == beforeUnits and bucket.scanPairs == beforePairs
			and #ring == beforeRing and ring[#ring].q == 12,
			"Base-only search preserves item-wide history and velocity after Browse shows suffix supply")
		check(MerchantMasterDB.ahPrices[econ][crate].qty == 3 and MerchantMasterDB.ahPrices[econ][crate].price == 1,
			"Known variants do not prevent a valid base-key cache update")
		_G.GetTime = function() return priorGetTime() + 92 end
		app.scanOrderBookItems({ crate }, 1)
		events("ITEM_SEARCH_RESULTS_UPDATED", base)
		check(not ns.MarketScan.GetBagStatus() and bucket.lastQ == 12 and bucket.at == beforeAt
			and bucket.scanUnits == beforeUnits and #ring == beforeRing,
			"Active base-key job also preserves history when suffix supply is known")
		do
			local oldKeys = ns.SellerStats.GetKeys
			ns.SellerStats.GetKeys = function(id, economy)
				if id == scroll and economy == econ then return { { itemID = id }, { itemID = id, itemSuffix = 8 } } end
				return oldKeys(id, economy)
			end
			local scrollBucket = daily[scroll][#daily[scroll]]
			local previousQ, previousAt = scrollBucket.lastQ, scrollBucket.at
			events("ITEM_SEARCH_RESULTS_UPDATED", { itemID = scroll })
			check(scrollBucket.lastQ == previousQ and scrollBucket.at == previousAt,
				"Persisted seller coverage prevents a base-only search from replacing item-wide history")
			ns.SellerStats.GetKeys = oldKeys
		end
		local hood = 7048
		local function checkHoodSuffixSearch()
			local hoodBucket = { d = math.floor(now / 86400), at = now, lastP = 100, obsP = 100, lastQ = 12 }
			local hoodRing = { { t = now, p = 100, q = 12 } }
			daily[hood], MerchantMasterDB.ahHistory[econ][hood] = { hoodBucket }, hoodRing
			local hoodPrice, hoodLots = MerchantMasterDB.ahPrices[econ][hood], MerchantMasterDB.ahLots[econ][hood]
			local oldItemFull, oldItemCount, oldItemResultInfo = ah.HasFullItemSearchResults,
				ah.GetNumItemSearchResults, ah.GetItemSearchResultInfo
			local suffix = { itemID = hood, itemSuffix = 9 }
			check(not MerchantMasterDB.ahVariants[econ][hood], "Azure Silk Hood starts with history and no variant marker")
			ah.HasFullItemSearchResults = function() return false end
			ah.GetNumItemSearchResults = function() return 2 end
			ah.GetItemSearchResultInfo = function(_, i)
				if i == 2 then return { quantity = 9, buyoutAmount = 900 } end
			end
			events("ITEM_SEARCH_RESULTS_UPDATED", suffix)
			check(MerchantMasterDB.ahVariants[econ][hood] == true and MerchantMasterDB.ahPrices[econ][hood] == hoodPrice
				and MerchantMasterDB.ahLots[econ][hood] == hoodLots and hoodBucket.lastQ == 12,
				"Partial Azure Silk Hood suffix search with nine readable units persists its marker without replacing history")
			ah.HasFullItemSearchResults = oldItemFull
			ah.GetNumItemSearchResults = function() return 0 end
			events("ITEM_SEARCH_RESULTS_UPDATED", suffix)
			check(MerchantMasterDB.ahVariants[econ][hood] == true, "Complete empty suffix search preserves an existing variant marker")
			ah.GetNumItemSearchResults = oldItemCount
			ah.GetItemSearchResultInfo = function() return { buyoutAmount = 300, quantity = 3 } end
			now = now + 1200
			events("ITEM_SEARCH_RESULTS_UPDATED", { itemID = hood })
			check(MerchantMasterDB.ahPrices[econ][hood].qty == 3 and hoodBucket.lastQ == 12
				and (hoodBucket.scanUnits or 0) == 0 and #hoodRing == 1 and hoodRing[1].q == 12,
				"Azure Silk Hood base-only search keeps all 12 items in history and adds no fake sales")
			MerchantMasterDB.ahVariants[econ][hood] = nil
			ah.GetNumItemSearchResults = function() return 0 end
			events("ITEM_SEARCH_RESULTS_UPDATED", suffix)
			check(not MerchantMasterDB.ahVariants[econ][hood], "Complete empty suffix search does not create a variant marker")
			ah.GetNumItemSearchResults = oldItemCount
			events("ITEM_SEARCH_RESULTS_UPDATED", suffix)
			check(MerchantMasterDB.ahVariants[econ][hood] == true, "Complete suffix search with listings persists the variant marker")
			ah.GetItemSearchResultInfo = oldItemResultInfo
			daily[hood], MerchantMasterDB.ahHistory[econ][hood], MerchantMasterDB.ahVariants[econ][hood] = nil, nil, nil
		end
		checkHoodSuffixSearch()
		local oldStart = _G.AuctionHouseFrame.SearchBar.StartSearch
		ah.GetBrowseResults = function() return {
			{ itemKey = { itemID = hood }, totalQuantity = 3, minPrice = 100 },
			{ itemKey = { itemID = hood, itemSuffix = 9 }, totalQuantity = 9, minPrice = 100 },
		} end
		_G.AuctionHouseFrame.SearchBar.StartSearch = function() ah.SendBrowseQuery({ searchString = ns.ItemName(hood) }) end
		app.searchAH(ns.ItemName(hood), 1, hood)
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		local wantedBucket = daily[hood][#daily[hood]]
		local wantedAt, wantedUnits = wantedBucket.at, wantedBucket.scanUnits
		local reloadedNS = setmetatable({ SellerStats = false }, { __index = ns })
		assert(loadfile(addonDir .. "MarketScan.lua"))("MerchantMaster", reloadedNS)
		reloadedNS.MarketScan.Initialize({}, {})
		check(#ns.SellerStats.GetKeys(hood, econ) == 2, "Targeted Browse saves both observed SellerStats keys")
		now = now + 1200
		reloadedNS.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = hood })
		check(MerchantMasterDB.ahPrices[econ][hood].qty == 3 and wantedBucket.lastQ == 12
			and wantedBucket.at == wantedAt and wantedBucket.scanUnits == wantedUnits,
			"After a scanner reload, a base-only Search preserves Azure Silk Hood item-wide history and velocity")
		check(MerchantMasterDB.ahVariants and MerchantMasterDB.ahVariants[econ][hood] == true,
			"Targeted Browse persisted the Azure Silk Hood variant marker")
		ah.GetBrowseResults = function() return {} end
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(MerchantMasterDB.ahVariants and MerchantMasterDB.ahVariants[econ][hood],
			"Full Browse without the item preserves the variant marker")
		ah.GetBrowseResults = function()
			return { { itemKey = { itemID = hood }, totalQuantity = 3, minPrice = 100 } }
		end
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(MerchantMasterDB.ahVariants and not MerchantMasterDB.ahVariants[econ][hood],
			"Full Browse observing only the base key clears the marker")
		now = now + 1200
		reloadedNS.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = hood })
		check(wantedBucket.at == now, "Base Search resumes item-wide history after full Browse clears the marker")
		_G.AuctionHouseFrame.SearchBar.StartSearch = oldStart
	end

	-- Only confirmed commodity jobs may use commodity events with no item ID.
	do
		local tick = 100
		_G.GetTime = function() return priorGetTime() + tick end
		ah.GetItemKeyInfo = function(k) return { itemName = ns.ItemName(k.itemID), isCommodity = false } end
		app.scanOrderBookItems({ scroll }, 1)
		local itemJob = ns.MarketScan.GetBagStatus()
		check(itemJob and not itemJob.isCommodity, "A confirmed non-commodity job is active")
		local itemPrice = MerchantMasterDB.ahPrices[econ][scroll]
		for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED" }) do
			events(event)
			check(ns.MarketScan.GetBagStatus() == itemJob, event .. " without an ID leaves a base item-key search active")
			events(event, scroll)
			check(ns.MarketScan.GetBagStatus() == itemJob and MerchantMasterDB.ahPrices[econ][scroll] == itemPrice,
				event .. " with the same ID cannot finish or overwrite a non-commodity search")
		end
		app.cancelOrderBookScan()
		ah.GetItemKeyInfo = function(k) return { itemName = ns.ItemName(k.itemID), isCommodity = true } end
		for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED" }) do
			tick = tick + 2
			app.scanOrderBookItems({ scroll }, 1)
			local commodityJob = ns.MarketScan.GetBagStatus()
			local commodityPrice = MerchantMasterDB.ahPrices[econ][scroll]
			events("ITEM_SEARCH_RESULTS_UPDATED", { itemID = scroll })
			check(ns.MarketScan.GetBagStatus() == commodityJob and MerchantMasterDB.ahPrices[econ][scroll] == commodityPrice,
				"A same-ID item event cannot finish or overwrite a confirmed commodity search")
			events(event)
			check(not ns.MarketScan.GetBagStatus() and MerchantMasterDB.ahPrices[econ][scroll].qty == 3,
				event .. " without an ID completes a confirmed commodity job")
		end
		for _, wrongKindFirst in ipairs({ false, true }) do
			tick = tick + 2
			ah.GetItemKeyInfo = function() return nil end
			app.scanOrderBookItems({ scroll }, 1)
			local unknownJob = ns.MarketScan.GetBagStatus()
			check(unknownJob and unknownJob.isCommodity == nil, "Missing key metadata leaves the search kind unknown")
			ah.GetItemKeyInfo = function() return { isCommodity = true } end
			if wrongKindFirst then
				local previous = MerchantMasterDB.ahPrices[econ][scroll]
				events("ITEM_SEARCH_RESULTS_UPDATED", { itemID = scroll })
				check(ns.MarketScan.GetBagStatus() == unknownJob and unknownJob.isCommodity == true
					and MerchantMasterDB.ahPrices[econ][scroll] == previous,
					"Late commodity metadata rejects a matching item event")
			end
			events("COMMODITY_SEARCH_RESULTS_RECEIVED", scroll)
			check(not ns.MarketScan.GetBagStatus() and MerchantMasterDB.ahPrices[econ][scroll].qty == 3,
				"Late commodity metadata lets a matching result complete the job")
			app.cancelOrderBookScan()
		end
	end
	do
		local hood = 7048
		local base = { itemID = hood }
		local suffix = { itemID = hood, itemSuffix = 9 }
		local row = { outputItemID = hood, recipe = ns.RECIPES_BY_OUTPUT[hood][1] }
		local function quote()
			return ns.RecipeStats.BuildQuickLook(row, { economy = econ }, now).scan
		end
		ah.GetBrowseResults = function()
			return { { itemKey = base, totalQuantity = 12, minPrice = 100 } }
		end
		app.refreshAllMarketValues()
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		local prices = MerchantMasterDB.ahPrices[econ]
		local browseAt = now
		check(prices[hood].itemWide == true and quote().qty == 12 and quote().price == 100,
			"Complete Azure Silk Hood Browse publishes an item-wide Quick Look quote")

		now = now + 1200
		_G.GetTime = function() return priorGetTime() + 200 end
		ah.GetItemKeyInfo = function() return { isCommodity = false } end
		ah.HasFullItemSearchResults = function() return false end
		ah.GetNumItemSearchResults = function() return 1 end
		ah.GetItemSearchResultInfo = function() return { buyoutAmount = 900, quantity = 3 } end
		app.scanOrderBookItems({ hood }, 1)
		events("ITEM_SEARCH_RESULTS_UPDATED", base)
		local partial = prices[hood]
		local scan = quote()
		check(not ns.MarketScan.GetBagStatus() and partial.itemWide == false
			and partial.qty == 3 and partial.price == 300 and partial.at == now
			and scan.at == browseAt and scan.qty == 12 and scan.price == 100,
			"Truncated base order book is scoped to its cache and keeps the complete Browse quote in Quick Look")

		local savedVariants = MerchantMasterDB.ahVariants
		MerchantMasterDB.ahVariants = nil
		prices[hood] = { price = 300, qty = 3, at = now }
		scan = quote()
		check(scan.at == now and scan.qty == 3 and scan.price == 300,
			"Legacy quote with only the base key is eligible for Quick Look")
		ns.SellerStats.RecordBrowse(econ, { base, suffix }, true)
		scan = quote()
		check(#ns.SellerStats.GetKeys(hood, econ) == 2 and scan.at == browseAt and scan.qty == 12 and scan.price == 100,
			"Persisted seller variants keep a newer legacy base quote out of Quick Look")
		MerchantMasterDB.ahVariants = savedVariants
		ns.SellerStats.RecordBrowse(econ, { base }, true)
	end

	local function checkBagBrowseCoverage()
		local market, seller, db = ns.MarketScan, ns.SellerStats, MerchantMasterDB
		local hood, alias = 7048, "Synthetic hood name lookup"
		local base, suffix = { itemID = hood }, { itemID = hood, itemSuffix = 9 }
		local tick = 220
		_G.GetTime = function() return priorGetTime() + tick end
		ah.GetItemKeyInfo = function(k)
			return { itemName = k.itemSuffix and alias .. " of the Owl" or alias, isCommodity = false }
		end
		ah.HasFullItemSearchResults = function() return true end
		ah.GetNumItemSearchResults = function() return 1 end
		ah.GetItemSearchResultInfo = function() return { buyoutAmount = 300, quantity = 3 } end
		for _, scenario in ipairs({ "later suffix", "more pages", "unreadable suffix" }) do
			ah.HasFullBrowseResults = function() return true end
			local rows = { { itemKey = base, totalQuantity = 12, minPrice = 100 } }
			ah.GetBrowseResults = function() return rows end
			app.refreshAllMarketValues()
			events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			local bucket = daily[hood][#daily[hood]]
			local ring = db.ahHistory[econ][hood]
			local at, units, ringLength = bucket.at, bucket.scanUnits, #ring
			now, tick = now + 1200, tick + 4
			rows[1] = { itemKey = base, totalQuantity = 3, minPrice = 100 }
			if scenario == "later suffix" then
				rows[2] = { itemKey = suffix, totalQuantity = 9, minPrice = 100 }
			elseif scenario == "more pages" then
				ah.HasFullBrowseResults = function() return false end
			else
				rows[2] = { itemKey = { itemID = hood, itemSuffix = "unreadable" }, totalQuantity = 9, minPrice = 100 }
			end
			local savedBeforeDispatch
			ah.SendSearchQuery = function(k)
				local markers = db.ahVariants and db.ahVariants[econ]
				savedBeforeDispatch = k.itemID == hood and not k.itemSuffix and (
					scenario == "later suffix" and markers and markers[hood] == true
					or scenario ~= "later suffix" and seller.HasIncompleteCoverage(hood, econ))
			end
			app.itemIDs[alias] = nil
			market.ScanBagCrates({ { name = "Synthetic crate", bundles = { { name = alias, count = 1 } } } })
			tick = tick + 2
			events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			check(savedBeforeDispatch, "Bag-crate Browse records " .. scenario .. " before dispatching the base key")
			events("ITEM_SEARCH_RESULTS_UPDATED", base)
			local quote = db.ahPrices[econ][hood]
			check(not market.GetBagStatus() and quote.qty == 3 and quote.itemWide == false and bucket.lastQ == 12
				and bucket.at == at and bucket.scanUnits == units and #ring == ringLength and ring[#ring].q == 12,
				"Bag-crate search with " .. scenario .. " preserves all 12 confirmed listings and records no sales")
		end

		local function startBagScan(crateName)
			app.itemIDs[alias] = nil
			tick = tick + 2
			market.ScanBagCrates({ { name = crateName, bundles = { { name = alias, count = 1 } } } })
			tick = tick + 2
			events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		end
		local rows, browseFull = {}, true
		ah.GetBrowseResults = function() return rows end
		ah.HasFullBrowseResults = function() return browseFull end
		for _, field in ipairs({ "minPrice", "totalQuantity" }) do
			rows = { { itemKey = base, totalQuantity = 12, minPrice = 100 } }
			app.refreshAllMarketValues()
			events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			local bucket = daily[hood][#daily[hood]]
			now = now + 1200
			rows[1][field] = "unreadable"
			local markedBeforeDispatch
			ah.SendSearchQuery = function(k) markedBeforeDispatch = seller.HasIncompleteCoverage(k.itemID, econ) end
			startBagScan("Unreadable Browse " .. field)
			check(markedBeforeDispatch == false, "Bag Browse with unreadable " .. field .. " still covers its readable key")
			events("ITEM_SEARCH_RESULTS_UPDATED", base)
			local quote = db.ahPrices[econ][hood]
			check(not market.GetBagStatus() and quote.itemWide == true and quote.qty == 3 and bucket.lastQ == 3 and bucket.at == now,
				"A complete Search updates stock after Bag Browse with unreadable " .. field)
		end

		local getKeyInfo = ah.GetItemKeyInfo
		local more, sent = 0, nil
		ah.RequestMoreBrowseResults = function() more = more + 1 end
		ah.SendSearchQuery = function(k) sent = k end
		for _, scenario in ipairs({ "no match", "unreadable suffix" }) do
			local crateName = "Paged Browse " .. scenario
			local candidate = scenario == "no match" and { itemID = bundle } or { itemID = hood, itemSuffix = "unreadable" }
			seller.RecordBrowse(econ, { base }, true)
			ah.GetItemKeyInfo = function(k)
				if k.itemID == bundle then return { itemName = "Different item", isCommodity = false } end
				return getKeyInfo(k)
			end
			rows, browseFull, more, sent = { { itemKey = candidate, totalQuantity = 1, minPrice = 100 } }, false, 0, nil
			startBagScan(crateName)
			check(market.GetBagStatus() and more == 1 and not sent and not app.costs[crateName],
				"Page one with " .. scenario .. " keeps the bag job pending and requests the next page")
			events("ITEM_KEY_ITEM_INFO_RECEIVED", hood)
			check(more == 1, "Metadata events do not request the same Browse page twice")
			browseFull, tick = true, tick + 2
			events("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = base, totalQuantity = 3, minPrice = 100 } })
			check(sent and sent.itemID == hood and not app.costs[crateName], "The added Browse page dispatches the readable match")
			check(seller.HasIncompleteCoverage(hood, econ) == (scenario == "unreadable suffix"),
				"The final Browse page retains the key uncertainty from prior pages")
			events("ITEM_SEARCH_RESULTS_UPDATED", base)
			local cost = app.costs[crateName] and app.costs[crateName][alias]
			check(not market.GetBagStatus() and cost and cost.cost and not cost.short and not cost.failed,
				"A match on page two completes the bag quote without a shortage")
		end

		rows = { { itemKey = { itemID = hood, itemSuffix = "unreadable" } } }
		startBagScan("Unreadable complete Browse")
		check(market.GetBagStatus() and not app.costs["Unreadable complete Browse"],
			"Complete Browse with an unreadable key does not record a shortage")
		app.cancelOrderBookScan()

		rows, more, sent = { { itemKey = base, totalQuantity = 3, minPrice = 100 } }, 0, nil
		ah.GetItemKeyInfo = function() return nil end
		startBagScan("Pending Browse metadata")
		check(market.GetBagStatus() and not app.costs["Pending Browse metadata"] and not sent and more == 0,
			"Complete Browse with pending key metadata does not record a shortage")
		ah.GetItemKeyInfo, tick = getKeyInfo, tick + 2
		events("ITEM_KEY_ITEM_INFO_RECEIVED", hood)
		check(sent and sent.itemID == hood, "Late metadata resumes the bag search")
		events("ITEM_SEARCH_RESULTS_UPDATED", base)

		rows, sent = {}, nil
		local otherCrate = "Slice 14 superseded bag browse"
		app.itemIDs[alias] = nil
		tick = tick + 2
		market.ScanBagCrates({{name=otherCrate, bundles={{name=alias, count=1}}}})
		local job = market.GetBagStatus()
		check(job and job.stage == "browse", "Slice 14 bag browse is dispatched before the external query")
		ah.SendBrowseQuery({searchString="Different manual query"})
		events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		check(market.GetBagStatus() == job and not app.costs[otherCrate] and not sent,
			"Slice 14 manual empty Browse cannot finish the crate's pending quote")
		app.cancelOrderBookScan()
		do
			local covered = "Slice 14 bag variant coverage"
			rows = {
				{itemKey=base, totalQuantity=3, minPrice=100},
				{itemKey=suffix, totalQuantity=9, minPrice=200},
			}
			seller.RecordBrowse(econ, {base}, true)
			local observation = seller.Begin(base, econ)
			seller.Observe(observation, {{owners={"Alice-Realm"}, totalNumberOfOwners=1}}, true, true)
			seller.Publish(observation)
			local sellerAtDispatch, chosen
			ah.SendSearchQuery = function(k)
				chosen, sellerAtDispatch = k, seller.Get(hood, econ)
			end
			startBagScan(covered)
			check(chosen and chosen.itemID == hood and sellerAtDispatch.status == "partial"
				and sellerAtDispatch.count == 1 and #seller.GetKeys(hood, econ) == 2,
				"Slice 14 bag Browse expands seller coverage before the initial Search")
			market.ScanSellers({hood})
			local _, queued = market.GetBagStatus()
			check(queued == 1, "Slice 14 seller refresh queues the distinct suffix while the base is in flight")
			app.cancelOrderBookScan()
		end
		rows, sent = {}, nil
		startBagScan("Empty complete Browse")
		local shortage = app.costs["Empty complete Browse"] and app.costs["Empty complete Browse"][alias]
		check(not market.GetBagStatus() and not sent and shortage and shortage.short == 1 and not shortage.failed,
			"Complete readable empty Browse records a confirmed shortage")
		app.itemIDs[alias] = nil
	end
	checkBagBrowseCoverage()

	local function checkBrowseQuoteFreshness()
		local market, seller, db = ns.MarketScan, ns.SellerStats, MerchantMasterDB
		local prices = db.ahPrices[econ]
		local oldSecret, oldPrint, oldToast = _G.issecretvalue, _G.print, app.ui.toast
		local oldNow, oldScanned, oldRefresh = now, prices._scannedAt, db.lastRefreshAt
		local secret, chat, toast = {}
		local suffix = { itemID = crate, itemSuffix = 7 }
		_G.issecretvalue = function(value) return value == secret end
		_G.print = function(message)
			if message:find("Live AH scan", 1, true) then chat = message else oldPrint(message) end
		end
		app.ui.toast = { ShowToast = function(message) toast = message end }
		for _, field in ipairs({ "minPrice", "totalQuantity" }) do
			now, prices._scannedAt, db.lastRefreshAt = 100, 100, 100
			ah.GetBrowseResults = function()
				return { { itemKey = key, totalQuantity = 12, minPrice = 100 } }
			end
			app.refreshAllMarketValues()
			events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			local confirmed = prices[crate]
			local row = { itemKey = suffix, totalQuantity = 9, minPrice = 100 }
			row[field] = secret
			ah.GetBrowseResults = function() return {
				{ itemKey = key, totalQuantity = 3, minPrice = 100 },
				row,
				{ itemKey = { itemID = scroll }, totalQuantity = 5, minPrice = 225 },
			} end
			now = 2500
			app.refreshAllMarketValues()
			events("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
			local state = market.GetState()
			local keys = seller.GetKeys(crate, econ)
			check(not state.active and state.partial and state.completedAt == 100 and db.lastRefreshAt == 100,
				"Secret Browse " .. field .. " reports partial and preserves both freshness timestamps")
			check(chat and chat:find("partial", 1, true) and toast and toast:find("AH Scan Partial", 1, true),
				"Secret Browse " .. field .. " reports partial in chat and toast")
			check(prices[crate] == confirmed and confirmed.qty == 12 and #keys == 2
				and db.sellerStats[econ].coverageComplete and db.ahVariants[econ][crate] == true,
				"Secret Browse " .. field .. " keeps the quote and publishes complete variant-key coverage")
			check(prices[scroll].price == 225 and prices[scroll].qty == 5 and prices[scroll].at == 2500,
				"Secret Browse " .. field .. " still saves a readable quote for another item")
		end
		now, prices._scannedAt, db.lastRefreshAt = oldNow, oldScanned, oldRefresh
		_G.issecretvalue, _G.print, app.ui.toast = oldSecret, oldPrint, oldToast
	end
	checkBrowseQuoteFreshness()
	_G.GetTime = priorGetTime
	_G.C_AuctionHouse, _G.time = oldAH, oldTime
	app.refresh, app.warmSuperListCache = refresh, warm
end

-- Historical vendor quotes and cheapest acquisition policies must be resolved per day.
do
	local writID, reqID, crateID, childID, fineThreadID = 264049, 7048, 9999202, 9999203, 2321
	local economy, now = ns.DetectActiveEconomy(), time()
	local today = math.floor(now / 86400)
	local prices = {
		[writID] = { [today - 1] = 100, [today] = 100 },
		[reqID] = { [today - 1] = 900, [today] = 900 },
		[crateID] = { [today - 1] = 100, [today] = 100 },
		[childID] = { [today] = 100 },
		[fineThreadID] = { [today] = 1 },
		[9999204] = { [today] = 300 },
	}
	local recipes = ns.RECIPES_BY_OUTPUT
	local priorReq, priorChild = recipes[reqID], recipes[childID]
	local root = { outputItemID = reqID, prof = "tailoring", numMade = 1,
		reagents = { { childID, 1 } } }
	local child = { outputItemID = childID, prof = "tailoring", skill = 1, numMade = 1,
		reagents = { { 9999204, 1 } } }
	local fineThreadRecipe = { outputItemID = reqID, prof = "tailoring", numMade = 1,
		reagents = { { fineThreadID, 1 }, { 9999204, 1 } } }
	recipes[reqID], recipes[childID] = { root }, { child }
	local oldTrend, oldMarket, oldVendor = ns.MarketScan.GetItemTrend7d, ns.GetItemMarketPrice, ns.GetRecipeVendorBuyPrice
	ns.GetItemMarketPrice = function(id)
		local series = prices[id]
		return series and series[today]
	end
	ns.GetRecipeVendorBuyPrice = function(id)
		if id == fineThreadID then return 100 end
	end
	ns.MarketScan.GetItemTrend7d = function(id)
		local points = {}
		for offset = 6, 0, -1 do
			local day = today - offset
			local series = prices[id]
			if series and series[day] then points[#points + 1] = { d = day, price = series[day] } end
		end
		return { points = points }
	end
	local writRow = { writID = writID, reqItemID = reqID, reqQty = 1, mode = "Craft",
		writ = { itemID = writID, requiredItemID = reqID, prof = "tailoring" } }
	local crateRow = { crateID = crateID, reagentID = reqID, reagentQty = 1, mode = "Craft",
		crate = { itemID = crateID, bundles = { { itemID = reqID, qty = 1 } } } }
	local opts = { economy = economy, profMap = { tailoring = 300 }, subCraftMode = "always",
		writMode = "cheapest", crateMode = "cheapest" }
	local writLook = ns.RecipeStats.BuildWritQuickLook(writRow, opts, now)
	local crateLook = ns.RecipeStats.BuildCrateQuickLook(crateRow, opts, now)
	check(writLook.cost.values[6] == 900 and writLook.cost.values[7] == 100,
		"Cheapest Writ history falls back to yesterday's buy quote when craft inputs are missing")
	check(crateLook.cost.values[6] == 900 and crateLook.cost.values[7] == 100,
		"Cheapest Crate history falls back to yesterday's buy quote when craft inputs are missing")
	local fineThreadLook = ns.RecipeStats.BuildWritQuickLook({
		writID = writID, reqItemID = reqID, reqQty = 1, mode = "Craft",
		writ = { itemID = writID, requiredItemID = reqID, prof = "tailoring", reagents = fineThreadRecipe.reagents },
	}, { economy = economy, writMode = "craft", subCraftMode = "never" }, now)
	check(fineThreadLook.cost.values[7] == 301,
		"Writ 264049 historical reagent pricing selects 1c Fine Thread AH over its 100c vendor quote")
	ns.MarketScan.GetItemTrend7d, ns.GetItemMarketPrice, ns.GetRecipeVendorBuyPrice = oldTrend, oldMarket, oldVendor
	recipes[reqID], recipes[childID] = priorReq, priorChild
end

-- Compare the historical subcraft choice against the live calculator on the same quotes.
do
	local crateID, reqID, subID, baseID = 9999100, 9999101, 9999102, 9999103
	local economy, now = ns.DetectActiveEconomy(), time()
	local day = math.floor(now / 86400)
	local prices = { [crateID] = 100, [reqID] = 800, [subID] = 400, [baseID] = 100 }
	local root = { outputItemID = reqID, prof = "tailoring", numMade = 1, reagents = { { subID, 1 } } }
	local sub = { outputItemID = subID, prof = "engineering", skill = 150, numMade = 1, reagents = { { baseID, 1 } } }
	local recipes = ns.RECIPES_BY_OUTPUT
	recipes[reqID], recipes[subID] = { root }, { sub }
	local oldTrend, oldMarket, oldReagent = ns.MarketScan.GetItemTrend7d, ns.GetItemMarketPrice, ns.GetReagentUnitCost
	ns.GetItemMarketPrice = function(id) return prices[id] end
	ns.GetReagentUnitCost = function(id) return prices[id], "AH", false end
	ns.MarketScan.GetItemTrend7d = function(id)
		local points = {}
		for offset = 6, 0, -1 do points[#points + 1] = { d = day - offset, price = prices[id] } end
		return { points = points }
	end
	local row = { crateID = crateID, reagentID = reqID, reagentQty = 2, mode = "Craft", craftTotal = 800,
		crate = { itemID = crateID, bundles = { { itemID = reqID, qty = 2 } } } }
	local cases = {
		{ "smart", "tailoring", 149, 0, nil, 400, 400 },
		{ "smart", "tailoring", 150, 0, nil, 400, 100 },
		{ "smart", "engineering", 0, 0, nil, 400, 100 },
		{ "smart", "engineering", 300, 60, nil, 400, 400 },
		{ "always", "tailoring", 0, 0, nil, 400, 100 },
		{ "always", "tailoring", 0, 0, nil, 50, 50 },
		{ "all_sub", "tailoring", 0, 0, nil, 50, 50 },
		{ "smart", "tailoring", 150, 0, nil, nil, 100 },
		{ "never", "engineering", 300, 0, nil, 400, 400 },
		{ "buy_only", "engineering", 300, 60, "craft", 400, 100 },
		{ "smart", "engineering", 300, 0, "buy", 400, 400 },
	}
	for index, case in ipairs(cases) do
		root.prof, sub.cd, prices[subID] = case[2], case[4], case[6]
		local opts = { economy = economy, parentProf = root.prof, profMap = { engineering = case[3] },
			subCraftMode = case[1], subCraftOverrides = { [subID] = case[5] } }
		opts.crateMode = "craft"
		local unitCost = ns.ComputeSmartCraftCost(root.reagents, 1, reqID, opts)
		local look = ns.RecipeStats.BuildCrateQuickLook(row, opts, now)
		check(unitCost == case[7] and look.chartSeries.bundleCost.values[7] == unitCost * row.reagentQty
			and look.movers[2].series.values[7] == unitCost,
			"Quick Look matches live profession, skill, cooldown, price or override rule " .. index)
	end
	row.mode, row.craftTotal, root.prof = nil, nil, "tailoring"
	local opts = { economy = economy, profMap = {}, subCraftMode = "smart", crateOverrides = { [reqID] = "buy" } }
	local buy = ns.RecipeStats.BuildCrateQuickLook(row, opts, now)
	check(buy.cost.values[7] == 1600 and buy.movers[2].series.values[7] == 800,
		"Crate per-item buy override sets both historical chart and mover")
	prices[reqID] = nil
	local fallback = ns.RecipeStats.BuildCrateQuickLook(row, opts, now)
	check(fallback.cost.values[7] == 800 and fallback.movers[2].series.values[7] == 400,
		"Unavailable override price falls back consistently in the crate chart and mover")
	ns.MarketScan.GetItemTrend7d, ns.GetItemMarketPrice, ns.GetReagentUnitCost = oldTrend, oldMarket, oldReagent
	recipes[reqID], recipes[subID] = nil, nil
end

do
	local app, db = ns.app, MerchantMasterDB
	local ui, search = app.ui, app.ui.searchBox
	local oldClear = search.ClearFocus
	local focusCleared = false
	search.ClearFocus = function(self) focusCleared = true; oldClear(self) end
	local function dirtySearch()
		focusCleared = false
		search:SetText("custom filter")
		search.placeholder:Hide()
		search._mmClearBtn:Show()
	end
	local function assertSearchReset(tab)
		check(search:GetText() == "" and search.placeholder:IsShown() and not search._mmClearBtn:IsShown() and focusCleared,
			tab .. " clears search, focus, and clear-button state and restores its placeholder")
	end
	local function member(list, button)
		for _, entry in ipairs(list) do if entry == button then return true end end
		return false
	end
	local function assertButtons(inline, sidebar, controls, tab)
		local label = inline and ((inline._mmLabel and inline._mmLabel:GetText()) or inline:GetText())
		check(inline and inline:IsShown() and label == "Reset Filters", tab .. " has a visible Reset Filters pill")
		check(sidebar and sidebar:GetText() == "Reset Filters" and member(controls, sidebar), tab .. " has a sidebar Reset Filters control")
	end
	local shared = { profFilter = "all", unlockFilter = "all", sellableFilter = "all", knownRecipesOnly = false,
		bisOnly = false, merchantVendorOnly = false, sourceFilter = "all", craftableFilter = "all", demandFilter = "all" }
	local dirty = { profFilter = "alchemy", unlockFilter = "mine_profs", sellableFilter = "no", knownRecipesOnly = true,
		bisOnly = true, merchantVendorOnly = true, sourceFilter = "vendor", craftableFilter = "yes", demandFilter = "hot" }
	local pages = {
		{ "dashboard", "dash", { dashboardScope = "all" }, { dashboardScope = "smart" }, "dashScopeBtn", ns.DASHBOARD_SCOPES[1].label },
		{ "profit_spread", "spread", { spreadCount = 20, diversifyProfs = false }, { spreadCount = 8, diversifyProfs = true }, "spreadCountBtn", "Spread: Top 8 Crafts" },
		{ "outliers", "outliers", { outlierScope = "thin", outlierQuality = "bis" }, { outlierScope = "monopoly", outlierQuality = "good" }, "outlierScopeBtn", "Stock: 0-2 (Monopoly)" },
		{ "crates", "crates", { crateMode = "buy", bestOnly = true }, { crateMode = "cheapest", bestOnly = false }, "crateModeBtn", "Mode: Best (Craft/Buy)" },
		{ "writs", "writs", { writMode = "craft", writZoneFilter = "mapped", includeWritPouch = false },
			{ writMode = "cheapest", writZoneFilter = "all", includeWritPouch = true }, "writModeBtn", "Mode: Best (Craft/Buy)" },
		{ "rep", "rep", { repRankFilter = 7, includeShippingLabel = true, includeWritPouch = false },
			{ repRankFilter = "all", includeShippingLabel = false, includeWritPouch = true }, "repHintFs" },
		{ "calc_favor", "favor", { calcFavorTarget = 500, calcDeductFavor = true, calcUseOwned = true, crateMode = "buy", calcRespectStock = false },
			{ calcFavorTarget = 150, calcDeductFavor = false, calcUseOwned = false, crateMode = "cheapest", calcRespectStock = true }, "favorInput", "150" },
		{ "calc_rep", "repCalc", { calcRepTarget = 5, writZoneFilter = "mapped", writMode = "craft", calcUseOwned = true, calcRespectStock = false },
			{ calcRepTarget = 8, writZoneFilter = "all", writMode = "cheapest", calcUseOwned = false, calcRespectStock = true }, "calcWritModeBtn", "Mode: Best (Craft/Buy)" },
	}
	local exposesSubCraft = { profit_spread = true, outliers = true, crates = true, writs = true,
		calc_favor = true, calc_rep = true }
	local function setSubCraftBuy()
		db.subCraftMode = "buy_only"
		ui.subCraftBtn:SetText(ns.SUBCRAFT_MODES[3].label)
	end
	local function assertSubCraftReset(tab)
		check(db.subCraftMode == "smart" and ui.subCraftBtn:GetText() == ns.SUBCRAFT_MODES[1].label,
			tab .. " resets sub-material crafting and repaints its control")
	end
	app.panel:Show()
	for _, page in ipairs(pages) do
		local tab, prefix = page[1], page[2]
		app.setTab(tab)
		local inline, sidebar = ui[prefix .. "ResetBtn"], ui[prefix .. "ResetFiltersBtn"]
		assertButtons(inline, sidebar, app.allDynamicSidebarControls, tab)
		for index, button in ipairs({ inline, sidebar }) do
			for key, value in pairs(dirty) do db[key] = value end
			for key, value in pairs(page[3]) do db[key] = value end
			db.recipeSources = { vendor = true }
			dirtySearch()
			setSubCraftBuy()
			button:Click("LeftButton")
			assertSearchReset(tab)
			if exposesSubCraft[tab] then
				assertSubCraftReset(tab)
			else
				check(db.subCraftMode == "buy_only", tab .. " preserves the hidden sub-material setting")
			end
			for key, value in pairs(shared) do check(db[key] == value, tab .. " resets shared filter " .. key) end
			for key, value in pairs(page[4]) do check(db[key] == value, tab .. " resets " .. key) end
			check(next(db.recipeSources) == nil and ui.sellBtn:GetText() == "Sellable: All", tab .. " syncs source and sellability controls")
			if page[6] then check(ui[page[5]]:GetText() == page[6], tab .. " syncs " .. page[5]) end
			if index == 1 and tab == "calc_favor" then
				check(not ui.deductCheck:GetChecked() and not ui.calcUseOwnedCheck:GetChecked() and ui.respectStockCheck:GetChecked(),
					"Favor reset syncs deduction, owned inventory and listing stock")
			elseif index == 1 and tab == "rep" then
				check((ui.repHintFs:GetText() or "") ~= "" and app.simStartIdx == 1
					and not ui.shippingCheck:GetChecked() and ui.writPouchCheck:GetChecked(), "Standing reset refreshes the rank summary and simulation controls")
			end
		end
	end
	app.setTab("bags")
	db.includeMail, db.includeBank, db.includeAlts = false, false, true
	ui.bagsResetBtn:Click("LeftButton")
	check(db.includeMail and db.includeBank and not db.includeAlts and ui.includeMail:GetChecked()
		and ui.includeBank:GetChecked() and not ui.includeAlts:GetChecked(), "Bag reset restores its inventory scopes")

	app.setTab("recipes")
	setSubCraftBuy()
	ui.recipesView.resetButton:Click("LeftButton")
	assertSubCraftReset("recipes")

	local professor, profDB = ns.MP.app, ns.MP.GetDB()
	local oldRefresh = app.refresh
	for _, view in ipairs({ "browse", "shop", "path" }) do
		local tab = "prof_" .. view
		db.profFilter = "all"
		profDB.selectedProf = view == "path" and "leatherworking" or "alchemy"
		app.setTab(tab)
		local widgets = professor.ui
		local inline, sidebar = widgets[view .. "ResetBtn"], widgets.profResetFiltersBtn
		assertButtons(inline, sidebar, professor.GetSidebarControls(), tab)
		professor.activeBracket, profDB.goalMode, profDB.recipeFilter = "artisan", "cheapest", "all"
		profDB.sellDays, profDB.charLevelMode, profDB.overtimeMode = 7, 60, 5
		profDB.useOwned, profDB.knownRecipesOnly = true, true
		profDB.profTargets.alchemy = { from = 80, to = 110 }
		profDB.profTargets.leatherworking = { from = 50, to = 220 }
		profDB.browseTier, profDB.browseProf, profDB.browseOwnedOnly = "expert", "alchemy", true
		profDB.browseSearch, profDB.shopSearch = "recipe filter", "shopping filter"
		profDB.shoppingGroupMode = "by_level"
		professor.sortState.shop = { col = "sortSkill", asc = true }
		widgets.fromBox:SetText("50"); widgets.toBox:SetText("220"); widgets.ownedChk:SetChecked(true)
		dirtySearch()
		setSubCraftBuy()
		local refreshes = 0
		app.refresh = function(...)
			refreshes = refreshes + 1
			return oldRefresh(...)
		end
		inline:Click("LeftButton")
		app.refresh = oldRefresh
		assertSearchReset(tab)
		assertSubCraftReset(tab)
		check(refreshes == 1, tab .. " refreshes once")
		check(profDB.profTargets.alchemy.from == 80 and profDB.profTargets.alchemy.to == 110,
			tab .. " preserves saved Alchemy bounds")
		if view == "path" then
			check(professor.activeBracket == "all" and profDB.goalMode == "smart" and profDB.recipeFilter == "trainer_vendor"
				and profDB.sellDays == 3 and profDB.charLevelMode == "auto" and profDB.overtimeMode == "auto"
				and not profDB.useOwned and not profDB.knownRecipesOnly, tab .. " resets plan options")
			local liveRank = ns.MP.ScanPlayerProfessions().leatherworking.rank
			check(profDB.profTargets.leatherworking.from == liveRank and profDB.profTargets.leatherworking.to == 300
				and widgets.fromBox:GetText() == tostring(liveRank) and widgets.toBox:GetText() == "300"
				and not widgets.ownedChk:GetChecked(), tab .. " restores live skill bounds for the selected profession")
		else
			check(profDB.goalMode == "cheapest" and profDB.recipeFilter == "all" and profDB.useOwned,
				tab .. " preserves Path options")
			check(profDB.profTargets.leatherworking.from == 50 and profDB.profTargets.leatherworking.to == 220,
				tab .. " preserves saved Leatherworking bounds")
		end
		if view == "browse" then
			check(profDB.browseTier == "all" and profDB.browseProf == "all" and not profDB.browseOwnedOnly
				and profDB.browseSearch == "",
				tab .. " resets the browse controls")
		else
			check(profDB.browseTier == "expert" and profDB.browseSearch == "recipe filter", tab .. " preserves Browse options")
		end
		if view == "shop" then
			local sort = professor.sortState.shop
			check(profDB.shoppingGroupMode == "consolidated" and sort.col == "lineCost" and not sort.asc
				and profDB.shopSearch == "",
				tab .. " restores Consolidated grouping, descending line total and blank search")
		else
			check(profDB.shoppingGroupMode == "by_level" and profDB.shopSearch == "shopping filter",
				tab .. " preserves Shopping options")
		end
	end

	local analytics = ns.Analytics.UI
	check(analytics.Register() or MerchantMasterAPI.RegisterAnalytics(analytics.provider), "Restore the real Analytics provider for reset checks")
	for _, tab in ipairs({ "an_overview", "an_ledger", "an_items", "an_portfolio", "an_invest", "an_writs" }) do
		app.setTab(tab)
		assertButtons(analytics.resetButton, analytics.resetFiltersBtn, analytics.GetSidebarControls(tab), tab)
		db.anChar, db.anPeriod, db.anType, db.anProf = "custom", "7d", "sells", "alchemy"
		db.anLedgerPreset, db.anLedgerOffset, db.anCoalesce = "expiredCancelled", 2, true
		db.anItemMode, db.anPortfolioView, db.anInvPriceSource, db.anInvIncludeGuild = "sales", "inventory", "vendor", true
		dirtySearch()
		analytics.resetButton:Click("LeftButton")
		assertSearchReset(tab)
		local state = analytics.Filters()
		check(state.char == "all" and state.period == "30d" and not state.prof and state.search == "",
			tab .. " resets shared Analytics filters")
		check(analytics.charBtn:GetText() == "Char: All" and analytics.periodBtn:GetText() == "30 Days",
			tab .. " repaints shared filter dropdowns")
		if tab == "an_ledger" then
			check(state.type == "all" and state.ledgerPreset == "all" and state.page == 0 and not state.coalesce,
				tab .. " resets transaction filters, pagination, and grouping")
		else
			check(state.type == "sells" and state.ledgerPreset == "expiredCancelled" and state.page == 2 and state.coalesce,
				tab .. " preserves Ledger preferences")
		end
		if tab == "an_portfolio" then
			check(db.anPortfolioView == "breakdown" and db.anInvPriceSource == "market" and not db.anInvIncludeGuild,
				tab .. " resets portfolio view, valuation, and guild inventory")
		else
			check(db.anPortfolioView == "inventory" and db.anInvPriceSource == "vendor" and db.anInvIncludeGuild,
				tab .. " preserves Portfolio preferences")
		end
		check(db.anItemMode == (tab == "an_items" and "profit" or "sales"), tab .. " scopes Items mode reset")
	end
	search.ClearFocus = oldClear
end

do
	local app = ns.app
	local oldModifiedClick = _G.IsModifiedClick
	local oldGetItemInfo = _G.GetItemInfo
	local oldCItem = _G.C_Item
	_G.C_Item = _G.C_Item or {}
	local oldItemInfo = _G.C_Item.GetItemInfo
	local oldInsertLink = _G.ChatEdit_InsertLink
	local insertedLink
	_G.IsModifiedClick = function(key) return key == "CHATLINK" end
	_G.C_Item.GetItemInfo = function() return "Cached item", nil end
	_G.GetItemInfo = function(id) return "Legacy item", "|cffffffff|Hitem:"..tostring(id).."|h[Legacy item]|h|r" end
	_G.ChatEdit_InsertLink = function(link) insertedLink = link; return true end
	check(app.tryQuickLookChatLink(12345) and insertedLink and insertedLink:find("|Hitem:12345|h", 1, true),
		"Legacy item info link is used when C_Item.GetItemInfo returns no link")
	insertedLink = nil
	_G.C_Item.GetItemInfo = function() error("primary item lookup failed") end
	check(app.tryQuickLookChatLink(12346) and insertedLink and insertedLink:find("|Hitem:12346|h", 1, true),
		"Legacy item info link is used when C_Item.GetItemInfo raises")
	_G.IsModifiedClick, _G.GetItemInfo, _G.ChatEdit_InsertLink = oldModifiedClick, oldGetItemInfo, oldInsertLink
	_G.C_Item = oldCItem
	if oldCItem then oldCItem.GetItemInfo = oldItemInfo end
end

do
	local app = ns.app
	local oldTab, oldCrateRows = app.activeTab, ns.BuildCrateRows
	local crate = { crateID = 999001, crateName = "Test Crate", reagentName = "Strange Dust",
		reagentQty = 20, tokens = 10 }
	ns.BuildCrateRows = function() return { crate } end
	app.panel:Show()
	app.activeTab = "dashboard"
	app.refresh()
	local turnin = app.ui.dashTurninRows[1]
	local label = turnin.subFs:GetText()
	check(label:find("Strange Dust 20x", 1, true) and label:find("Price unavailable", 1, true)
		and not label:find("Buy AH", 1, true) and turnin.valFs:GetText() == "--",
		"Dashboard labels an unpriced Crate as Price unavailable")
	ns.BuildCrateRows, app.activeTab = oldCrateRows, oldTab
end

do
	local app, db = ns.app, MerchantMasterDB
	local ui, provider = app.ui, app.superListProvider
	local oldTab, oldAH = app.activeTab, _G.AuctionHouseFrame
	local panelWasShown = app.panel:IsShown()
	_G.AuctionHouseFrame = nil
	app.panel:Show()

	local itemKey = { recipe = "outputItemID", writ = "writID", crate = "crateID" }
	local function checkPinned(row, kind, id, label)
		local hud = provider.GetQuickLookFrame()
		check(hud and hud:IsShown() and hud.pinned == true and hud.owner == row and hud.data
			and hud.data.kind == kind and hud.row and hud.row[itemKey[kind]] == id,
			label .. " shows pinned " .. kind .. " Quick Look for the clicked item")
		return hud
	end
	local function mouseDown(hud, target)
		check(hud._events.GLOBAL_MOUSE_DOWN, "Pinned Quick Look listens for global mouse-down")
		if target then target.mouseOver = true end
		hud:GetScript("OnEvent")(hud, "GLOBAL_MOUSE_DOWN", "LeftButton")
		if target then target.mouseOver = nil end
	end
	local function checkItemTooltip(cell, id, label)
		check(cell and cell:GetScript("OnEnter"), label .. " has an item tooltip handler")
		GameTooltip:Hide()
		GameTooltip:ClearLines()
		cell:GetScript("OnEnter")(cell)
		check(GameTooltip:IsShown() and GameTooltip._lines[1] == "Item:" .. id, label .. " shows the matching item tooltip")
		cell:GetScript("OnLeave")(cell)
		check(not GameTooltip:IsShown(), label .. " hides its tooltip on mouse leave")
	end
	local function checkRow(label, row, kind)
		check(row and row:IsVisible() and row.data, label .. " renders a populated row")
		check(row._scripts.OnEnter == nil, label .. " row has no item tooltip handler")
		local orig = row.data._orig or row.data
		local id = orig[itemKey[kind]] or orig.itemID
		local materialID = orig.reagentID or orig.reqItemID
		local secondName = row.cells and not row.data._orig and materialID
		local name = row.nameHover or row.cells[1]
		checkItemTooltip(name, (row.data._orig and materialID) or id, label .. " item name")
		if secondName then checkItemTooltip(row.cells[2], materialID, label .. " required item name") end
		local cells = row.cells or row._regions
		local firstNonName = row.cells and (secondName and 3 or 2) or 1
		for i = firstNonName, #cells do
			check(cells[i]:GetScript("OnEnter") == nil, label .. " non-name cell " .. i .. " has no item tooltip handler")
		end
		for _, target in ipairs({ row, name }) do
			local clickLabel = label .. (target == row and " row" or " name cell")
			target:Click("LeftButton")
			local hud = checkPinned(row, kind, id, clickLabel)
			-- In WoW the hover guard runs on mouse-down before the next OnClick.
			mouseDown(hud, target)
			check(hud:IsShown(), clickLabel .. " hover keeps Quick Look open on global mouse-down")
			target:Click("LeftButton")
			check(not hud:IsShown(), clickLabel .. " closes Quick Look when clicked for the same item")
		end
	end
	local function recipeRow(recipe)
		return {
			itemID = recipe.outputItemID, name = recipe.name, prof = recipe.prof, recipe = recipe,
			craftCost = 100, ahPrice = 300, targetPrice = 300, profit = 200, listed = 2,
			dailySold = 8, expectedDailyProfit = 1600,
			craftAbility = { ableToCraft = false, howShort = "Vendor", cellText = "Vendor",
				wowheadURL = "https://www.wowhead.com/forever/spell=" .. recipe.spellID },
		}
	end

	local craft, monopoly = recipeRow(regularFortRec), recipeRow(greaterFortRec)
	local buildInsights = ns.BuildDashboardInsights
	ns.BuildDashboardInsights = function() return { topCrafts = { craft }, topOutliers = { monopoly } } end
	app.setTab("dashboard")
	ns.BuildDashboardInsights = buildInsights
	local dashCraft, dashOutlier = ui.dashCraftRows[1], ui.dashOutlierRows[1]
	checkRow("Overview daily craft", dashCraft, "recipe")
	checkRow("Overview monopoly", dashOutlier, "recipe")
	checkRow("Overview crate turn-in", ui.dashTurninRows[1], "crate")
	checkRow("Overview writ turn-in", ui.dashTurninRows[3], "writ")
	dashCraft:Click("LeftButton")
	local hud = checkPinned(dashCraft, "recipe", craft.itemID, "Overview daily craft")
	mouseDown(hud, dashOutlier.nameHover)
	check(hud:IsShown() and hud.owner == dashCraft, "Hovering another item's name keeps the current Quick Look open")
	dashOutlier.nameHover:Click("LeftButton")
	checkPinned(dashOutlier, "recipe", monopoly.itemID, "Overview after clicking a different item")
	provider.CloseQuickLook()

	app.setTab("profit_spread")
	ui.profitSpreadTable.setRows({ craft })
	local spread = ui.profitSpreadTable.scrollBox._frames[1]
	checkRow("Daily Crafts", spread, "recipe")
	local whBtn = spread.cells[2].whBtn
	check(whBtn:IsShown() and whBtn:GetScript("OnEnter"), "Daily Crafts Wowhead button keeps its tooltip handler")
	whBtn:GetScript("OnEnter")(whBtn)
	check(GameTooltip:IsShown() and table.concat(GameTooltip._lines, " "):find(craft.craftAbility.wowheadURL, 1, true),
		"Wowhead button shows its recipe source link")
	whBtn:GetScript("OnLeave")(whBtn)
	spread:Click("LeftButton")
	hud = checkPinned(spread, "recipe", craft.itemID, "Daily Crafts")
	whBtn:Click("LeftButton")
	local modal = ui.wowheadModal
	check(modal:IsShown(), "Wowhead button opens its link modal")
	mouseDown(hud, modal)
	check(hud:IsShown() and hud.owner == spread, "Hovering the Wowhead modal keeps Quick Look open on global mouse-down")
	modal:Hide()
	mouseDown(hud)
	check(not hud:IsShown(), "Clicking outside the rows, HUD, and modal closes Quick Look")

	spread:Click("LeftButton")
	hud = checkPinned(spread, "recipe", craft.itemID, "Daily Crafts before rerendering")
	ui.profitSpreadTable.setRows({ recipeRow(regularFortRec) })
	local rerendered = ui.profitSpreadTable.scrollBox._frames[1]
	mouseDown(hud, rerendered.cells[1])
	check(hud:IsShown(), "Hovering the rerendered recipe keeps Quick Look open")
	rerendered.cells[1]:Click("LeftButton")
	check(not hud:IsShown(), "Clicking the same recipe after a table rerender closes Quick Look")

	app.setTab("outliers")
	ui.outliersTable.setRows({ monopoly })
	checkRow("Monopolies", ui.outliersTable.scrollBox._frames[1], "recipe")
	app.setTab("writs")
	checkRow("Writs", ui.writsTable.scrollBox._frames[1], "writ")
	app.setTab("crates")
	checkRow("Crates", ui.cratesTable.scrollBox._frames[1], "crate")

	_G.AuctionHouseFrame = oldAH
	app.setTab(oldTab)
	app.panel:SetShown(panelWasShown)
end

-- Forged Delivery data, acquisition costs, and reputation plans.
do
	local receipt = ns.FORGED_RECEIPT
	check(receipt and receipt.receiptItemID == 262902 and receipt.receiptName == "Forged Delivery Receipt"
		and receipt.containerItemID == 262917 and receipt.containerName == "Notarized Shipping Container"
		and receipt.questID == 93862 and receipt.questName == "Crate Return", "Forged Delivery item and quest identities")
	check(receipt.favorCost == 15 and receipt.requiredStanding == 5 and receipt.baseRep == 50
		and receipt.refundCopper == 100 and receipt.dailyCap == 0 and receipt.racialMultipliers.Human == 1.1,
		"Forged Delivery costs 15 Favor at Friendly and grants 50 rep plus 100c with no daily cap")
	for key, expected in pairs({ allianceVendor = { "Dianne Softstep", 9.1, 76.5 }, hordeVendor = { "Kurvelk Shadowhoof", 49.8, 30.0 },
		turnInAlliance = { "Marcy Baker", 9.5, 71.1 }, turnInHorde = { "Dokimi", 50.0, 29.2 } }) do
		local npc = receipt[key]
		check(npc and npc.name == expected[1] and npc.mapX == expected[2] and npc.mapY == expected[3],
			"Forged Delivery " .. key .. " is " .. expected[1] .. " at the expected coordinates")
	end

	local db = MerchantMasterDB
	local savedPrices, savedLots, savedRewards = db.ahPrices, db.ahLots, db.rewards
	local savedSource, savedEconomy = db.priceSource, db.economy
	local savedForgedQ, savedForgedMode, savedForgedHuman = db.forgedTurnInQueue, db.forgedMode, db.forgedHumanDiplomacy
	local savedShopping = db.shoppingList
	local savedRace, savedQuestLog = _G.UnitRace, _G.C_QuestLog
	local now = time()
	local market = { _scannedAt = now }
	local function quote(id, price, qty)
		market[id] = { price = price, qty = qty or 1000, at = now }
	end
	local function rowByCrate(result, id)
		for _, row in ipairs(result.rows) do if row.crateID == id then return row end end
		error("Missing Forged row for crate " .. id, 2)
	end
	local options = { crateMode = "buy", priceSource = "live_ah", subCraftMode = "buy_only", humanDiplomacy = false }
	local ok, failure = pcall(function()
		_G.UnitRace = function(unit) assert(unit == "player"); return "Human", "Human" end
		check(ns.GetRacialRepMultiplier() == 1.1 and ns.GetRacialRepMultiplier(false) == 1.0,
			"Human race grants Diplomacy and an explicit false overrides it")
		_G.UnitRace = function(unit) assert(unit == "player"); return "Orc", "Orc" end
		check(ns.GetRacialRepMultiplier() == 1.0 and ns.GetRacialRepMultiplier(true) == 1.1,
			"Orc race uses standard reputation and an explicit true enables Diplomacy")
		_G.UnitRace = savedRace

		db.ahPrices, db.ahLots, db.rewards = { ["Normal-Horde"] = market }, {}, {}
		db.priceSource, db.economy = options.priceSource, "Normal-Horde"
		quote(248682, 250); quote(2447, 10, 10000) -- 450c gross, 250c cashback, 5 Favor.
		quote(248683, 400); quote(248684, 400); quote(248685, 40) -- Price tie and a negative net cost.
		quote(248702, 500); quote(2996, 40) -- 1,300c gross, 500c cashback, 10 Favor.
		ns.InvalidatePriceCache()
		local result = ns.BuildForgedDeliveryRows(options)
		check(result.forgedMode == "self_funded" and result.baseRep == 50 and result.effectiveRep == 50
			and result.repMult == 1.0, "Forged Delivery defaults to Self-Funded at standard reputation")
		check(#result.rows == #ns.CRATES and #result.rows == 30 and result.meta.totalCrates == 30
			and result.meta.availableCount == 5, "Forged Delivery includes the 5 priced and 25 unpriced empty crates")
		local seen, previous = {}, nil
		for _, row in ipairs(result.rows) do
			check(row.forged and row.itemID == row.crateID and row.rowKey == "forged:" .. row.crateID
				and not seen[row.crateID], "Forged row has a unique empty crate identity")
			if previous then
				local prevCost, cost = previous.costPerRep or math.huge, row.costPerRep or math.huge
				local sorted = prevCost < cost or (prevCost == cost and previous.crateID < row.crateID)
				check((previous.available and not row.available) or ((not not previous.available) == (not not row.available) and sorted),
					"Forged rows sort by availability, cost per rep, and crate ID")
			end
			seen[row.crateID], previous = true, row
		end
		local feeder, ordinary, cheap = result.bestFavorCrate, rowByCrate(result, 248683), rowByCrate(result, 248685)
		check(feeder.crateID == 248682 and feeder.reagentID == 2447 and feeder.pricePerToken == 40
			and feeder.favorGrossCostPerFavor == 90 and feeder.favorCashbackPerFavor == 50,
			"The cheapest feeder is Apprentice Herbs at 40c per Favor after cashback")
		check(ordinary.available and ordinary.source == "Self-Funded" and ordinary.favorRequired == 15
			and ordinary.favorGrossCost == 1350 and ordinary.favorCashback == 750 and ordinary.favorCost == 15 * feeder.pricePerToken
			and ordinary.favorCost == 600, "Self-Funded Favor costs 1,350c gross and 600c net after one 750c cashback deduction")
		check(ordinary.emptyPrice == 400 and ordinary.isLiveEmpty and ordinary.forgedRefund == 100 and ordinary.forgedCrateNet == 300
			and ordinary.totalRefund == 850
			and ordinary.selfFundedNetCost == 900 and ordinary.netCost == 900 and ordinary.costPerRep == 900 / 50,
			"Self-Funded cost is 900c for 50 reputation")
		check(cheap.forgedCrateNet == -60 and cheap.bankedNetCost == -60 and cheap.bankedCostPerRep == -60 / 50
			and result.bestSelfFunded.crateID == cheap.crateID and result.bestBanked.crateID == cheap.crateID,
			"A 40c empty crate retains its negative net cost and wins both funding modes")

		options.forgedMode, options.humanDiplomacy = "self_funded", true
		local human = ns.BuildForgedDeliveryRows(options)
		local humanRow = rowByCrate(human, ordinary.crateID)
		check(human.effectiveRep == 55 and human.repMult == 1.1 and humanRow.rep == 55 and humanRow.netCost == ordinary.netCost,
			"Human Diplomacy raises reputation to 55 while preserving the turn-in cost")
		approxEq(humanRow.costPerRep, 900 / 55, 1e-9, "Human Self-Funded unit cost uses 55 rep")

		options.forgedMode, options.humanDiplomacy = "banked", false
		local bankedResult = ns.BuildForgedDeliveryRows(options)
		local banked = rowByCrate(bankedResult, ordinary.crateID)
		check(banked.netCost == 300 and banked.source == "Banked Favor" and banked.costPerRep == 300 / banked.rep,
			"Banked Favor costs only the empty crate net of the Forged refund")
		check(rowByCrate(bankedResult, cheap.crateID).netCost == -60, "Banked Favor keeps the negative net cost of the 40c crate")
		local bankedList = ns.BuildForgedTurnInShoppingList(banked, 3, options)
		check(bankedList.feederCount == 0 and bankedList.favorNeeded == 0,
			"Banked turn-ins need zero Favor from feeder crates, got " .. tostring(bankedList.favorNeeded))
		check(bankedList.receiptCount == 3 and bankedList.forgedRefund == 300 and #bankedList.buyItems == 1
			and bankedList.buyItems[1].itemID == ordinary.crateID and bankedList.buyItems[1].qty == 3,
			"Three banked turn-ins buy three empty crates and refund 300c")
		local queuedRows = ns.BuildUnifiedShoppingList({ forgedMode = "banked", forgedTurnInQueue = { [ordinary.crateID] = 3 } }, options)
		local queuedQty = 0
		for _, item in ipairs(queuedRows) do
			if not item.isMainRow and item.itemID == ordinary.crateID then queuedQty = queuedQty + item.qty end
		end
		check(queuedQty == 3, "The unified shopping list expands the Forged turn-in queue into empty crate purchases")

		db.forgedTurnInQueue, db.forgedMode, db.forgedHumanDiplomacy = {}, "banked", false
		check(ns.app.adjustForgedTurnInQueue(banked, 2) and #db.forgedTurnInQueue == 1
			and db.forgedTurnInQueue[1].row == nil and db.forgedTurnInQueue[1].crateID == ordinary.crateID
			and db.forgedTurnInQueue[1].count == 2,
			"adjustForgedTurnInQueue saves minimal SavedVariables metadata without embedding row tables")
		quote(ordinary.crateID, 620)
		ns.InvalidatePriceCache()
		local repricedRows = ns.BuildUnifiedShoppingList(db, options)
		local repricedItem
		for _, item in ipairs(repricedRows) do
			if not item.isMainRow and item.itemID == ordinary.crateID then repricedItem = item; break end
		end
		check(repricedItem and repricedItem.qty == 2 and repricedItem.ahUnitPrice == 620 and repricedItem.lineCost == 1240,
			"Queued Forged items reprice against live market updates instead of stale queued quotes")
		quote(ordinary.crateID, 400)
		db.forgedTurnInQueue, db.forgedMode = {}, "self_funded"
		options.forgedMode = "self_funded"
		check(ns.app.adjustForgedTurnInQueue(ordinary, 1) and db.forgedTurnInQueue[1].row == nil,
			"Self-Funded Forged queue entry also omits embedded row tables")
		quote(248682, 9000)
		ns.InvalidatePriceCache()
		local feederRepriced = ns.BuildUnifiedShoppingList(db, options)
		local usesNewFeeder = false
		for _, item in ipairs(feederRepriced) do
			if not item.isMainRow and item.itemID == 248702 and item.qty == 2 then usesNewFeeder = true end
		end
		check(usesNewFeeder, "Queued Self-Funded Forged items reselect the cheapest live Favor feeder after market changes")
		quote(248682, 250)
		db.forgedTurnInQueue, options.forgedMode = {}, "banked"
		ns.InvalidatePriceCache()

		options.forgedMode, options.favorCrateID = "self_funded", 248702
		local overridden = ns.BuildForgedDeliveryRows(options)
		check(overridden.bestFavorCrate.crateID == 248702 and overridden.bestFavorCrate.tokens == 10,
			"The selected 10-Favor feeder overrides the cheapest crate")
		local list = ns.BuildForgedTurnInShoppingList(rowByCrate(overridden, ordinary.crateID), 3, options)
		local feederCount = math.ceil(45 / overridden.bestFavorCrate.tokens)
		check(list.receiptCount == 3 and list.crateID == ordinary.crateID and list.favorNeeded == 45 and list.feederCount == feederCount
			and list.leftoverFavor == feederCount * 10 - 45 and list.forgedRefund == 300 and list.repEarned == 3 * ordinary.rep,
			"Three Self-Funded turn-ins consume 45 Favor from five feeders, with 5 Favor left over")
		local quantities = {}
		for _, item in ipairs(list.buyItems) do quantities[item.itemID] = (quantities[item.itemID] or 0) + item.qty end
		check(quantities[ordinary.crateID] == 3 and quantities[248702] == feederCount and quantities[2996] == feederCount * 20
			and #list.turnInSteps > 0, "Self-Funded shopping expands into empty crates, feeder materials, and turn-in steps")
		check(list.grossCost == 7700 and list.favorRefund == 2500 and list.totalRefund == 2800
			and list.netCost == 4900 and list.amortizedNetCost == 4500, "The shopping plan amortizes only the Favor actually consumed")

		options.favorCrateID, options.writMode, options.includeWritPouch = nil, "buy", false
		options.simStartRep, options.targetStanding, options.respectStock = 3000, 6, true
		options.zoneFilter, options.repSourceMode = "all", "forged_only"
		local cheapWrit, priceyWrit, soldOutWrit = ns.WRITS[1], ns.WRITS[2], ns.WRITS[3]
		quote(cheapWrit.itemID, 100, 8); quote(cheapWrit.requiredItemID, 10)
		quote(priceyWrit.itemID, 10000, 8); quote(priceyWrit.requiredItemID, 10)
		quote(soldOutWrit.itemID, 10, 0); quote(soldOutWrit.requiredItemID, 10)
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
		local overview = ns.BuildReputationOverview(options)
		local summary = overview.forgedSummary
		check(summary and summary.bestSelfFundedRow.crateID == cheap.crateID and summary.bestBankedRow.crateID == cheap.crateID
			and summary.bestFavorCrate.crateID == feeder.crateID and overview.bestWrit and #overview.milestones > 0,
			"Reputation Overview includes both Forged estimates alongside Writs and milestones")
		for _, effectiveRep in ipairs({ 50, 55 }) do
			options.humanDiplomacy = effectiveRep == 55
			local plan = ns.SolveRepShoppingList(options)
			check(plan.repNeeded == 6000 and plan.forgedCount == math.ceil(plan.repNeeded / effectiveRep)
				and plan.forgedRep == plan.forgedCount * effectiveRep and plan.forgedRep >= plan.repNeeded
				and plan.repFulfilled == plan.forgedRep and #plan.writPlan == 0 and #plan.forgedRows > 0
				and plan.forgedCost == plan.forgedCount * cheap.selfFundedNetCost,
				"Forged-only reaches Honored using unlimited " .. effectiveRep .. "-rep turn-ins")
		end
		options.repSourceMode, options.humanDiplomacy = "hybrid", false
		local hybrid = ns.SolveRepShoppingList(options)
		check(#hybrid.writPlan == 1 and hybrid.writPlan[1].writID == cheapWrit.itemID and hybrid.writPlan[1].count == 1,
			"Hybrid caps the cheap Writ at one and skips the expensive and sold-out Writs")
		check(hybrid.forgedCount == math.ceil((hybrid.repNeeded - cheapWrit.rep) / 50) and hybrid.forgedRep == hybrid.forgedCount * 50
			and hybrid.forgedCount > 0 and hybrid.repFulfilled == cheapWrit.rep + hybrid.forgedRep and hybrid.repFulfilled >= hybrid.repNeeded,
			"Hybrid fills the remaining reputation with Forged Deliveries")
	end)
	db.ahPrices, db.ahLots, db.rewards = savedPrices, savedLots, savedRewards
	db.priceSource, db.economy = savedSource, savedEconomy
	db.forgedTurnInQueue, db.forgedMode, db.forgedHumanDiplomacy = savedForgedQ, savedForgedMode, savedForgedHuman
	db.shoppingList = savedShopping
	_G.UnitRace, _G.C_QuestLog = savedRace, savedQuestLog
	ns.InvalidatePriceCache()
	if not ok then error(failure, 0) end
end

do
	local db = MerchantMasterDB
	local savedChars, savedCharKey, savedActiveChar = db.chars, ns.app.charKey, ns.activeChar
	local savedKnown, savedUnlock, savedAllChars = db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars
	local savedPrices, savedSource, savedEconomy = db.ahPrices, db.priceSource, db.economy
	local savedQuestLog = _G.C_QuestLog
	local savedGetProfessions, savedGetProfessionInfo = _G.GetProfessions, _G.GetProfessionInfo
	local savedGetNumSkillLines, savedGetSkillLineInfo = _G.GetNumSkillLines, _G.GetSkillLineInfo
	local savedIsPlayerSpell, savedIsSpellKnown, savedTradeSkill, savedUnitName = _G.IsPlayerSpell, _G.IsSpellKnown, _G.C_TradeSkillUI, _G.UnitName
	local alchRec, arcaniteRec, bsRec, tailorRec
	for _, r in ipairs(ns.RECIPES) do
		if r.prof == "alchemy" and r.spellID == 17187 then arcaniteRec = r end
		if not alchRec and r.prof == "alchemy" and r.spellID and r.spellID > 0 and r.outputItemID
			and (r.skill or 1) >= 60 and (r.skill or 1) <= 250 and ns.IsItemSellable(r.outputItemID) and r.reagents and #r.reagents > 0 then
			alchRec = r
		end
		if not bsRec and r.prof == "blacksmithing" and r.spellID and r.spellID > 0 and r.outputItemID and r.reagents and #r.reagents > 0 then
			bsRec = r
		end
		if not tailorRec and r.prof == "tailoring" and r.spellID and r.spellID > 0 and r.outputItemID and r.reagents and #r.reagents > 0 then
			tailorRec = r
		end
	end
	local alchWrit
	for _, w in ipairs(ns.WRITS) do
		if w.prof == "alchemy" and w.spellID and w.questID and w.reagents and #w.reagents > 0 then
			alchWrit = w; break
		end
	end
	check(alchRec and arcaniteRec and bsRec and tailorRec and alchWrit,
		"Catalog provides sample recipes and writs for multi-char Craftable Now tests")

	local ok, err = pcall(function()
		local econ = "Normal-Horde"
		db.economy, db.priceSource = econ, "live"
		db.ahPrices = db.ahPrices or {}
		local now = time()
		local mkt = { _scannedAt = now }
		local function priceObj(r)
			if not r then return end
			if r.outputItemID then mkt[r.outputItemID] = { price = 15000, qty = 1, at = now } end
			if r.requiredItemID then mkt[r.requiredItemID] = { price = 15000, qty = 3, at = now } end
			if r.itemID then mkt[r.itemID] = { price = 500, qty = 5, at = now } end
			for _, rg in ipairs(r.reagents or {}) do
				local id = rg.itemID or rg[1]
				if id then mkt[id] = { price = 100, qty = 200, at = now } end
			end
		end
		priceObj(alchRec); priceObj(bsRec); priceObj(tailorRec); priceObj(alchWrit)
		for _, cr in ipairs(ns.CRATES) do
			if cr.itemID == 248682 then
				mkt[cr.itemID] = { price = 200, qty = 10, at = now }
				for _, b in ipairs(cr.bundles) do mkt[b.itemID] = { price = 150, qty = 50, at = now } end
			end
		end
		db.ahPrices[econ] = mkt

		local bankAlt = {
			name = "Banker", realm = "Forever", faction = "Horde", economy = econ,
			knownSpells = {}, knownOutputs = {}, knownNames = {}, scannedProfs = {},
			cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
		}
		local alchAlt = {
			name = "AlchAlt", realm = "Forever", faction = "Horde", economy = econ,
			-- Deliberately leave .profs == nil to verify skill inference from saved knownSpells!
			knownSpells = { [alchRec.spellID] = true, [arcaniteRec.spellID] = true, [alchWrit.spellID] = true },
			knownOutputs = {}, knownNames = {}, scannedProfs = { alchemy = true },
			cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
		}
		local engAlt = {
			name = "EngAlt", realm = "Forever", faction = "Horde", economy = econ,
			profs = { engineering = 300 },
			knownSpells = {}, knownOutputs = {}, knownNames = {}, scannedProfs = { engineering = true },
			cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
		}
		local alliAlt = {
			name = "AlliAlt", realm = "Forever", faction = "Alliance", economy = "Normal-Alliance",
			profs = { blacksmithing = 300 },
			knownSpells = { [bsRec.spellID] = true }, knownOutputs = {}, knownNames = {}, scannedProfs = { blacksmithing = true },
			cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
		}
		local hcAlt = {
			name = "HCAlt", realm = "ForeverHC", faction = "Horde", economy = "HC-Horde",
			profs = { tailoring = 300 },
			knownSpells = { [tailorRec.spellID] = true }, knownOutputs = {}, knownNames = {}, scannedProfs = { tailoring = true },
			cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
		}
		db.chars = {
			["Normal-Horde-Forever-Banker"] = bankAlt,
			["Normal-Horde-Forever-AlchAlt"] = alchAlt,
			["Normal-Horde-Forever-EngAlt"] = engAlt,
			["Normal-Alliance-Forever-AlliAlt"] = alliAlt,
			["HC-Horde-ForeverHC-HCAlt"] = hcAlt,
		}
		_G.GetProfessions = function() return nil end
		_G.GetProfessionInfo = function() return nil end
		_G.GetNumSkillLines = function() return 0 end
		_G.GetSkillLineInfo = function() return nil end
		_G.IsPlayerSpell = function() return false end
		_G.IsSpellKnown = _G.IsPlayerSpell
		_G.C_TradeSkillUI = nil
		_G.UnitName = function() return "Banker" end
		ns.activeChar = bankAlt
		ns.app.charKey = "Normal-Horde-Forever-Banker"
		ns.InvalidatePriceCache()

		local recSelf = ns.BuildRecipeRows({ profFilter = "all", knownRecipesOnly = true, craftableAllChars = false })
		local nonAnySelf = 0
		for _, r in ipairs(recSelf) do
			if not (r.recipe and r.recipe.anyChar) then nonAnySelf = nonAnySelf + 1 end
		end
		check(#recSelf == 14 and nonAnySelf == 0,
			"Bank alt with Craftable Now + This Char sees only the 14 anyChar right-click combines (0 profession recipes)")

		db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = true, "known", true
		ns.InvalidatePriceCache()
		local mergedProfs = ns.GetPlayerProfessions()
		check((mergedProfs.alchemy or 0) >= (alchRec.skill or 1) and mergedProfs.engineering == 300
			and mergedProfs.blacksmithing == nil and mergedProfs.tailoring == nil,
			"All Chars merges same-economy professions (including inferred alt skills) and isolates other economies/factions")
		local liveOnlyProfs = ns.MP.ScanPlayerProfessions()
		check(next(liveOnlyProfs) == nil, "Professor leveling scan stays scoped to current character")

		local recAll = ns.BuildRecipeRows({ profFilter = "all", knownRecipesOnly = true, craftableAllChars = true })
		local sawAlch, sawCross = false, false
		for _, r in ipairs(recAll) do
			if r.recipe.spellID == alchRec.spellID then
				sawAlch = true
				check(r.unlock.label:find("(AlchAlt)", 1, true) ~= nil
					and r.craftAbility.cellText:find("Yes (AlchAlt)", 1, true) ~= nil,
					"Alt-learned recipe attributes AlchAlt in unlock and craftability columns")
			end
			if r.recipe.spellID == bsRec.spellID or r.recipe.spellID == tailorRec.spellID then
				sawCross = true
			end
		end
		check(sawAlch and not sawCross, "Craftable Now + All Chars shows same-economy alt recipes and hides cross-economy alts")

		local spRows = ns.BuildProfitSpreadRows({ profFilter = "all", knownRecipesOnly = true, craftableAllChars = true })
		local outRows = ns.BuildOutlierRows({ profFilter = "all", outlierQuality = "all", knownRecipesOnly = true, craftableAllChars = true })
		local dashIns = ns.BuildDashboardInsights({ knownRecipesOnly = true, craftableAllChars = true, profFilter = "all" })
		local wpRows = ns.BuildWritProfitRows({ profFilter = "all", knownRecipesOnly = true, craftableAllChars = true })
		local wRows = ns.BuildWritRows({ profFilter = "all", unlockFilter = "known", craftableAllChars = true })
		local cRows = ns.BuildCrateRows({ profFilter = "all", unlockFilter = "known", craftableAllChars = true })
		local function hasID(list, idKey, val)
			for _, x in ipairs(list or {}) do if x[idKey] == val then return true end end
			return false
		end
		check(hasID(outRows, "itemID", alchRec.outputItemID) and hasID(wpRows, "itemID", alchWrit.requiredItemID)
			and hasID(wRows, "writID", alchWrit.itemID) and type(spRows) == "table" and dashIns.knownPickCount >= 0 and type(cRows) == "table",
			"Spread, Outliers, Dashboard, Writ Profit, Writs, and Crates honor All Chars scope")

		-- Multi-char cooldowns: Active char on 40h CD + AlchAlt ready -> Ready; Active 40h + AlchAlt 12h -> 12h.
		_G.GetProfessions = function() return 1, nil, nil, nil, nil, nil end
		_G.GetProfessionInfo = function(idx)
			if idx == 1 then return "Alchemy", 136240, 300, 300, 0, 0, 171 end
		end
		bankAlt.profs = { alchemy = 300 }
		bankAlt.knownSpells = { [arcaniteRec.spellID] = true, [alchWrit.spellID] = true }
		bankAlt.scannedProfs = { alchemy = true }
		bankAlt.cooldowns = { [arcaniteRec.spellID] = now + 40 * 3600 }
		bankAlt.cooldownGroups = { alchemy_transmute = now + 40 * 3600 }
		ns.InvalidatePriceCache()
		local cdSelf = ns.GetRecipeCooldownInfo(arcaniteRec, now)
		db.craftableAllChars = false
		ns.InvalidatePriceCache()
		cdSelf = ns.GetRecipeCooldownInfo(arcaniteRec, now)
		check(cdSelf and cdSelf.onCooldown == true, "Single-char mode reports Arcanite on 40h cooldown")
		db.craftableAllChars = true
		ns.InvalidatePriceCache()
		local cdAltReady = ns.GetRecipeCooldownInfo(arcaniteRec, now)
		check(cdAltReady and cdAltReady.onCooldown == false and cdAltReady.available == true,
			"All Chars marks shared cooldown ready when another alchemist alt is off cooldown")
		alchAlt.cooldowns = { [arcaniteRec.spellID] = now + 12 * 3600 }
		alchAlt.cooldownGroups = { alchemy_transmute = now + 12 * 3600 }
		ns.InvalidatePriceCache()
		local cdAltMin = ns.GetPlayerRecipeCooldownRemaining(arcaniteRec, now)
		check(math.abs(cdAltMin - 12 * 3600) <= 5,
			"All Chars reports minimum remaining cooldown across characters (12h), got " .. tostring(cdAltMin))

		-- Writ daily cooldowns: active char completed today, AlchAlt has not (offline alt ignores live IsQuestFlaggedCompleted).
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return true end }
		db.craftableAllChars = false
		ns.InvalidatePriceCache()
		local wSelf = ns.GetWritCooldownInfo(alchWrit, { now = now })
		check(wSelf.onCooldown == true, "Single-char mode treats writ as on cooldown when IsQuestFlaggedCompleted is true")
		db.craftableAllChars = true
		ns.InvalidatePriceCache()
		local wAll = ns.GetWritCooldownInfo(alchWrit, { now = now })
		check(wAll.onCooldown == false and wAll.available == true,
			"All Chars marks writ Ready when an alt knowing it has not turned it in")
		alchAlt.writCooldowns[alchWrit.questID] = now + 7200
		ns.InvalidatePriceCache()
		local wBothCD = ns.GetWritCooldownInfo(alchWrit, { now = now })
		check(wBothCD.onCooldown == true and wBothCD.remainingSeconds == 7200,
			"All Chars returns shortest writ cooldown (7200s) when every knowing char is on cooldown")

		-- Regression guard: BuildCrateMaterialRows fallback must PopEvalOpts even when #rows == 0 inside an outer BeginEval.
		db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = false, "all", false
		ns.BeginEval()
		ns.BuildCrateMaterialRows({ profFilter = "engineering", unlockFilter = "known", craftableAllChars = true })
		check(ns.IsAllCharsCraftableActive() == false,
			"BuildCrateMaterialRows fallback pops evalOpts cleanly without leaking craftableAllChars")
		ns.EndEval()
	end)

	db.chars, ns.app.charKey, ns.activeChar = savedChars, savedCharKey, savedActiveChar
	db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = savedKnown, savedUnlock, savedAllChars
	db.ahPrices, db.priceSource, db.economy = savedPrices, savedSource, savedEconomy
	_G.C_QuestLog = savedQuestLog
	_G.GetProfessions, _G.GetProfessionInfo = savedGetProfessions, savedGetProfessionInfo
	_G.GetNumSkillLines, _G.GetSkillLineInfo = savedGetNumSkillLines, savedGetSkillLineInfo
	_G.IsPlayerSpell, _G.IsSpellKnown, _G.C_TradeSkillUI, _G.UnitName = savedIsPlayerSpell, savedIsSpellKnown, savedTradeSkill, savedUnitName
	ns.InvalidatePriceCache()
	if not ok then error(err, 0) end
end

-- Waylaid Crate hover tooltip pricing, global GameTooltip hooks, settings toggle & UI hover coverage.
do
	local app, db = ns.app, MerchantMasterDB
	local ui = app.ui
	local function plain(text)
		return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end

	-- 1. Catalog lookup tables & unchanged catalog counts.
	local crateCount = 0
	for id, crate in pairs(ns.CRATE_BY_ID or {}) do
		crateCount = crateCount + 1
		check(type(id) == "number" and crate.itemID == id, "CRATE_BY_ID maps numeric itemID -> crate")
	end
	check(crateCount == 30 and #ns.CRATES == 30, "CRATE_BY_ID contains all 30 crates, got " .. crateCount)
	for _, jid in ipairs({ 248686, 248687, 248688, 248689, 248705, 248706, 248707 }) do
		local jc = ns.CRATE_BY_ID[jid]
		check(jc and jc.tier == "Journeyman" and jc.itemID == jid, "CRATE_BY_ID includes Journeyman crate " .. jid)
	end

	local sealedCount = 0
	for id, sc in pairs(ns.SEALED_CRATE_BY_ID or {}) do
		sealedCount = sealedCount + 1
		check(type(id) == "number" and sc.sealed == true and sc.itemID == id, "SEALED_CRATE_BY_ID maps sealedID -> entry")
	end
	check(sealedCount == 6, "SEALED_CRATE_BY_ID contains all 6 confirmed sealed crates, got " .. sealedCount)
	for _, sid in ipairs({ 248765, 248766, 248767, 248770, 248771, 248772 }) do
		check(ns.SEALED_CRATE_BY_ID[sid] ~= nil, "SEALED_CRATE_BY_ID includes sealed crate " .. sid)
	end
	local allIDsCount = 0
	for _ in pairs(ns.ALL_CATALOG_IDS or {}) do allIDsCount = allIDsCount + 1 end
	check(allIDsCount == COUNTS.catalogIDs and #hostEnv.tocFiles == COUNTS.tocFiles,
		"COUNTS.catalogIDs == " .. COUNTS.catalogIDs .. " (" .. allIDsCount .. ") and COUNTS.tocFiles == " .. COUNTS.tocFiles .. " remain synced")

	-- 2. ns.BuildCrateTooltipData on Journeyman Q1 (248687), Q2 (248707), sealed & non-crate items.
	check(ns.BuildCrateTooltipData(999999) == nil and ns.BuildCrateTooltipData(2775) == nil
		and ns.BuildCrateTooltipData({}) == nil and ns.BuildCrateTooltipData(nil) == nil,
		"BuildCrateTooltipData returns nil immediately for non-crate items")

	local savedPrices, savedLots, savedRewards = db.ahPrices, db.ahLots, db.rewards
	local savedSource, savedEconomy = db.priceSource, db.economy
	local savedCrateMode, savedSubCraft, savedOverrides = db.crateMode, db.subCraftMode, db.subCraftOverrides
	local savedForgedMode, savedHuman, savedCrateTips = db.forgedMode, db.forgedHumanDiplomacy, db.crateTooltips
	local savedShopping, savedForgedQ = db.shoppingList, db.forgedTurnInQueue
	local savedCalcMode, savedCalcFavor, savedCalcRep, savedRepSrc = db.calcMode, db.calcFavorTarget, db.calcRepTarget, db.repSourceMode
	local savedGetItem, savedGetData, savedGetOwner = GameTooltip.GetItem, GameTooltip.GetTooltipData, GameTooltip.GetOwner
	local savedRace = _G.UnitRace
	local savedTab, savedShown = app.activeTab, app.panel:IsShown()

	local now = time()
	local market = { _scannedAt = now }
	local function setQuote(id, price, qty)
		market[id] = { price = price, qty = qty or 500, at = now }
	end
	local function clearTip()
		GameTooltip:ClearLines()
		if GameTooltip._scripts.OnTooltipCleared then
			GameTooltip._scripts.OnTooltipCleared(GameTooltip)
		end
	end

	local ok, err = pcall(function()
		_G.UnitRace = function() return "Orc", "Orc" end
		db.ahPrices, db.ahLots, db.rewards = { ["Normal-Horde"] = market }, {}, {}
		db.priceSource, db.economy = "live_ah", "Normal-Horde"
		db.crateMode, db.subCraftMode, db.subCraftOverrides = "cheapest", "smart", {}
		db.forgedMode, db.forgedHumanDiplomacy = "self_funded", false

		-- Journeyman Q1 (248687 Journeyman Ore): 10F, 500c cashback -> +33.33 equiv rep (50/15 * 10)
		setQuote(248687, 400)
		setQuote(2775, 60) -- 10x Silver Ore = 600c (best)
		setQuote(2772, 40) -- 20x Iron Ore = 800c
		ns.InvalidatePriceCache()

		local q1Opts = {
			economy = "Normal-Horde",
			crateMode = "buy",
			forgedMode = "self_funded",
			humanDiplomacy = false,
			profMap = {},
		}
		local q1 = ns.BuildCrateTooltipData(248687, q1Opts)
		check(q1 and q1.kind == "crate" and q1.crateID == 248687 and q1.tokens == 10 and q1.rewardCopper == 500,
			"248687 Journeyman Ore reports 10 Favor and 500c cashback")
		check(q1.bundles[1].itemID == 2775 and q1.bundles[1].qty == 10 and q1.bundles[1].unitCost == 60
			and q1.bundles[1].bundleTotal == 600 and q1.bundles[1].isBest == true,
			"248687 best bundle is 10x Silver Ore at 60c/ea = 600c")
		check(q1.bundles[2].itemID == 2772 and q1.bundles[2].qty == 20 and q1.bundles[2].unitCost == 40
			and q1.bundles[2].bundleTotal == 800 and q1.bundles[2].isBest == false,
			"248687 second bundle is 20x Iron Ore at 40c/ea = 800c")
		check(q1.emptyPrice == 400 and q1.fillCost == 600 and q1.grossFilledCost == 1000
			and q1.netFilledCost == 500 and q1.pricePerToken == 50,
			"248687 fillCost=600, netFilledCost=500, pricePerToken=50")
		check(q1.forgedRep == 50 and q1.isHuman == false, "248687 base Forged rep is +50 without Human Diplomacy")
		approxEq(q1.equivRepFromFavor, 33.3333, 0.01, "248687 10F -> +33.33 equiv rep")
		approxEq(q1.favorCostPerFavor, 50, 0.01, "248687 feeder favorCostPerFavor = 50c/F")
		approxEq(q1.sfFavorCost, 750, 0.01, "248687 15F self-funded favor cost = 750c")
		check(q1.bankedNetCost == 300 and q1.selfFundedNetCost == 1050,
			"248687 Banked net=300c and Self-Funded net=1050c")
		approxEq(q1.bankedCostPerRep, 6.0, 0.001, "248687 Banked cost/rep = 6.0c")
		approxEq(q1.selfFundedCostPerRep, 21.0, 0.001, "248687 Self-Funded cost/rep = 21.0c")

		-- Memoization returns identical cached table until cache invalidated.
		local q1Cached = ns.BuildCrateTooltipData(248687, q1Opts)
		check(q1Cached == q1, "BuildCrateTooltipData memoizes repeated calls in O(1)")
		ns.InvalidateCrateTooltipCache()
		local q1Fresh = ns.BuildCrateTooltipData(248687, q1Opts)
		check(q1Fresh ~= q1 and q1Fresh.netFilledCost == 500, "InvalidateCrateTooltipCache forces fresh recompute")

		-- Human Diplomacy (1.1x -> +55 rep)
		local q1Human = ns.BuildCrateTooltipData(248687, {
			economy = "Normal-Horde",
			crateMode = "buy",
			forgedMode = "self_funded",
			humanDiplomacy = true,
			profMap = {},
		})
		check(q1Human.forgedRep == 55 and q1Human.isHuman == true, "Human Diplomacy sets Forged rep to +55")
		approxEq(q1Human.equivRepFromFavor, 36.6667, 0.01, "Human Diplomacy 10F -> +36.67 equiv rep")
		approxEq(q1Human.bankedCostPerRep, 300 / 55, 0.001, "Human Diplomacy Banked cost/rep = 300/55")
		approxEq(q1Human.selfFundedCostPerRep, 1050 / 55, 0.001, "Human Diplomacy Self-Funded cost/rep = 1050/55")

		-- < 1s profitable empty crate (emptyPrice = 38c -> bankedNetCost = -62c, bankedCostPerRep = -1.24)
		setQuote(248687, 38)
		ns.InvalidatePriceCache()
		local q1Profit = ns.BuildCrateTooltipData(248687, q1Opts)
		check(q1Profit.emptyPrice == 38 and q1Profit.netFilledCost == 138,
			"38c empty crate sets netFilledCost = 38 + 600 - 500 = 138c")
		approxEq(q1Profit.pricePerToken, 13.8, 0.001, "38c empty crate pricePerToken = 13.8c/F")
		check(q1Profit.bankedNetCost == -62, "38c empty crate Banked net = 38 - 100 = -62c")
		approxEq(q1Profit.bankedCostPerRep, -1.24, 0.001, "38c empty crate Banked cost/rep = -1.24c")
		approxEq(q1Profit.selfFundedNetCost, -62 + 15 * 13.8, 0.01, "38c empty crate Self-Funded net matches formula")
		approxEq(q1Profit.selfFundedCostPerRep, (-62 + 15 * 13.8) / 50, 0.001, "38c empty crate Self-Funded cost/rep matches formula")

		-- Journeyman Q2 (248707 Journeyman Parts): 20F, 1000c cashback -> +66.67 equiv rep, Craft vs Buy
		setQuote(248707, 500)
		setQuote(3577, 90)   -- Gold Bar -> crafts 3x Gold Power Core (10558) at 30c/ea
		setQuote(10558, 200) -- Gold Power Core AH buy = 200c/ea -> 45x = 9000c
		setQuote(4371, 400)  -- Bronze Tube AH buy = 400c/ea -> 8x = 3200c
		ns.InvalidatePriceCache()

		local q2Craft = ns.BuildCrateTooltipData(248707, {
			economy = "Normal-Horde",
			crateMode = "cheapest",
			forgedMode = "self_funded",
			humanDiplomacy = false,
			profMap = { engineering = 200 },
		})
		check(q2Craft and q2Craft.tokens == 20 and q2Craft.rewardCopper == 1000,
			"248707 Journeyman Parts reports 20 Favor and 1000c cashback")
		approxEq(q2Craft.equivRepFromFavor, 66.6667, 0.01, "248707 20F -> +66.67 equiv rep")
		check(q2Craft.bestBundle and q2Craft.bestBundle.itemID == 10558 and q2Craft.bestBundle.mode == "Craft"
			and q2Craft.bestBundle.unitCost == 30 and q2Craft.bestBundle.bundleTotal == 1350,
			"248707 Craft/cheapest mode crafts 45x Gold Power Core at 30c/ea = 1350c")
		check(q2Craft.fillCost == 1350 and q2Craft.netFilledCost == 850 and q2Craft.pricePerToken == 42.5,
			"248707 Craft mode fillCost=1350, netFilledCost=850, pricePerToken=42.5")

		local q2Buy = ns.BuildCrateTooltipData(248707, {
			economy = "Normal-Horde",
			crateMode = "buy",
			forgedMode = "self_funded",
			humanDiplomacy = false,
			profMap = { engineering = 200 },
			ownedCounts = { ["Bronze Tube"] = 3 },
		})
		check(q2Buy.bestBundle and q2Buy.bestBundle.itemID == 4371 and q2Buy.bestBundle.mode == "Buy"
			and q2Buy.bestBundle.unitCost == 400 and q2Buy.bestBundle.bundleTotal == 3200
			and q2Buy.bestBundle.owned == 3 and q2Buy.bestBundle.missing == 5 and q2Buy.bestBundle.missingCost == 2000,
			"248707 Buy mode selects 8x Bronze Tube at 400c/ea = 3200c and computes owned/missing")
		check(q2Buy.fillCost == 3200 and q2Buy.netFilledCost == 2700 and q2Buy.pricePerToken == 135,
			"248707 Buy mode fillCost=3200, netFilledCost=2700, pricePerToken=135")

		local sealedApprentice = ns.BuildCrateTooltipData(248765, q1Opts)
		check(sealedApprentice and sealedApprentice.kind == "sealed" and sealedApprentice.tokens == 5
			and sealedApprentice.rewardCopper == 250 and sealedApprentice.fillCost == 0,
			"Sealed crate 248765 resolves reward and zero fill cost")

		-- 3. Global GameTooltip: OnTooltipSetItem (GetItem link) AND GetTooltipData() without GetItem() link.
		db.crateTooltips = true
		ns.InvalidateCrateTooltipCache()
		local onSetItem = GameTooltip:GetScript("OnTooltipSetItem")
		check(type(onSetItem) == "function", "GameTooltip has OnTooltipSetItem hook")

		clearTip()
		GameTooltip.GetItem = function() return "Waylaid Crate: Journeyman Ore", "item:248687" end
		GameTooltip.GetTooltipData = nil
		GameTooltip:SetItemByID(248687)
		onSetItem(GameTooltip)
		local tipText1 = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(tipText1:find(" ea)", 1, true) and tipText1:find("Fill Cost", 1, true)
			and tipText1:find("Price / Favor", 1, true)
			and tipText1:find("Reputation", 1, true)
			and tipText1:find("Cost / Rep (inc. crate)", 1, true)
			and tipText1:find("Cost / Rep (ex. crate)", 1, true)
			and not tipText1:find(" = ", 1, true),
			"GameTooltip OnTooltipSetItem renders compact plain numbers (ea, Fill Cost, Price / Favor, Reputation, Cost / Rep inc. & ex. crate)")
		local incInfo = ns.BuildCrateTooltipData(248687, { forgedMode = "self_funded" })
		check(incInfo and incInfo.activeCostPerRep ~= nil and incInfo.activeCostPerRepExCrate ~= nil
			and math.abs((incInfo.activeCostPerRep - incInfo.activeCostPerRepExCrate) - (incInfo.emptyPrice / incInfo.forgedRep)) < 1e-6,
			"Cost / Rep inc. crate minus ex. crate equals emptyPrice / forgedRep in self_funded mode")
		local bankedInfo = ns.BuildCrateTooltipData(248687, { forgedMode = "banked" })
		check(bankedInfo and bankedInfo.activeCostPerRepExCrate ~= nil
			and math.abs(bankedInfo.activeCostPerRepExCrate - (-bankedInfo.forgedRefund / bankedInfo.forgedRep)) < 1e-6,
			"Cost / Rep ex. crate equals -forgedRefund / forgedRep in banked mode")
		local countBeforeRepeat = #(GameTooltip._lines or {})
		onSetItem(GameTooltip)
		check(#(GameTooltip._lines or {}) == countBeforeRepeat,
			"Repeated OnTooltipSetItem before OnTooltipCleared produces zero duplicate lines")

		-- GetTooltipData() without GetItem() link
		clearTip()
		GameTooltip.GetItem = function() return nil, nil end
		GameTooltip.GetTooltipData = function() return { itemID = 248687 } end
		GameTooltip:AddLine("Waylaid Crate: Journeyman Ore")
		onSetItem(GameTooltip)
		local tipText2 = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(tipText2:find(" ea)", 1, true) and tipText2:find("Fill Cost", 1, true)
			and tipText2:find("Price / Favor", 1, true)
			and tipText2:find("Reputation", 1, true)
			and tipText2:find("Cost / Rep", 1, true),
			"GameTooltip GetTooltipData() without GetItem() link renders compact crate breakdown")
		local dataRepeatCount = #(GameTooltip._lines or {})
		onSetItem(GameTooltip)
		check(#(GameTooltip._lines or {}) == dataRepeatCount,
			"Repeated GetTooltipData() hover before clear produces zero duplicate lines")

		-- Non-crate item adds 0 crate tooltip lines (both direct AppendCrateTooltip and OnTooltipSetItem)
		clearTip()
		GameTooltip.GetItem = function() return "Hearthstone", "item:6948" end
		GameTooltip.GetTooltipData = function() return { itemID = 6948 } end
		GameTooltip:SetItemByID(6948)
		check(ns.AppendCrateTooltip(GameTooltip) == false and #(GameTooltip._lines or {}) == 1,
			"AppendCrateTooltip returns false and adds 0 lines for non-crate item 6948")
		onSetItem(GameTooltip)
		local nonCrateText = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(not nonCrateText:find("Waylaid Crate", 1, true)
			and not nonCrateText:find("Fill Cost", 1, true)
			and not nonCrateText:find("Price / Favor", 1, true)
			and not nonCrateText:find("Cost / Rep", 1, true),
			"OnTooltipSetItem adds 0 crate tooltip lines on non-crate item")

		-- 4. Settings toggle (MerchantMasterDB.crateTooltips): default true, Blizzard Settings, Gear/Sidebar, /mm cratetooltips, filter resets.
		check(db.crateTooltips == true and ns.IsCrateTooltipEnabled() == true,
			"MerchantMasterDB.crateTooltips defaults to true")
		check(ui.optCrateTooltipCheck and ui.crateTooltipCheck,
			"Both Blizzard Settings optCrateTooltipCheck and in-window crateTooltipCheck exist")

		ui.optCrateTooltipCheck:SetChecked(false)
		ui.optCrateTooltipCheck:Click("LeftButton")
		check(db.crateTooltips == false and ns.IsCrateTooltipEnabled() == false
			and ui.crateTooltipCheck:GetChecked() == false,
			"Unchecking optCrateTooltipCheck sets crateTooltips=false and syncs crateTooltipCheck")

		clearTip()
		GameTooltip.GetItem = function() return "Waylaid Crate: Journeyman Ore", "item:248687" end
		GameTooltip.GetTooltipData = function() return { itemID = 248687 } end
		GameTooltip:SetItemByID(248687)
		check(ns.AppendCrateTooltip(GameTooltip) == false and #(GameTooltip._lines or {}) == 1,
			"AppendCrateTooltip returns false and adds 0 lines when crateTooltips is false")
		onSetItem(GameTooltip)
		local suppressedText = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(not suppressedText:find("Fill Cost", 1, true)
			and not suppressedText:find("Price / Favor", 1, true)
			and not suppressedText:find("Cost / Rep", 1, true),
			"Disabled crateTooltips completely suppresses crate tooltip lines on OnTooltipSetItem")

		ui.crateTooltipCheck:SetChecked(true)
		ui.crateTooltipCheck:Click("LeftButton")
		check(db.crateTooltips == true and ns.IsCrateTooltipEnabled() == true
			and ui.optCrateTooltipCheck:GetChecked() == true,
			"Checking crateTooltipCheck restores crateTooltips=true and syncs optCrateTooltipCheck")

		SlashCmdList.MERCHANTMASTER("cratetooltips")
		check(db.crateTooltips == false and ui.optCrateTooltipCheck:GetChecked() == false
			and ui.crateTooltipCheck:GetChecked() == false,
			"/mm cratetooltips toggles crateTooltips off and syncs both checkboxes")

		-- resetCratesFilters / resetForgedFilters must NOT clear crateTooltips
		app.resetCratesFilters()
		app.resetForgedFilters()
		check(db.crateTooltips == false, "resetCratesFilters and resetForgedFilters preserve crateTooltips=false")

		SlashCmdList.MERCHANTMASTER("cratetooltips")
		check(db.crateTooltips == true and ui.optCrateTooltipCheck:GetChecked() == true
			and ui.crateTooltipCheck:GetChecked() == true,
			"/mm cratetooltips toggles crateTooltips back on and syncs both checkboxes")

		app.resetCratesFilters()
		app.resetForgedFilters()
		check(db.crateTooltips == true, "resetCratesFilters and resetForgedFilters preserve crateTooltips=true")

		clearTip()
		GameTooltip:SetItemByID(248687)
		onSetItem(GameTooltip)
		check(plain(table.concat(GameTooltip._lines or {}, "\n")):find("Fill Cost", 1, true) ~= nil,
			"Re-enabling crateTooltips restores crate tooltip lines on hover")

		-- 5. Hovering favorPlanTable cols 2/3, repPlanTable cols 2/3, dashBasketRows name hover.
		GameTooltip.GetItem, GameTooltip.GetTooltipData, GameTooltip.GetOwner = savedGetItem, savedGetData, savedGetOwner
		app.panel:Show()

		-- favorPlanTable cols 2 (crate) and 3 (reagent)
		db.calcFavorTarget = 10
		app.setTab("calc_favor")
		local favorRow = ui.favorPlanTable.scrollBox._frames[1]
		check(favorRow and favorRow.data and favorRow.data.crateID and favorRow.data.reagentID,
			"favorPlanTable populates a crate plan row")
		clearTip()
		favorRow.cells[2]:GetScript("OnEnter")(favorRow.cells[2])
		local favorCrateTip = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(GameTooltip:IsShown() and GameTooltip._lines[1] == "Item:" .. favorRow.data.crateID
			and favorCrateTip:find("Fill Cost", 1, true) ~= nil,
			"favorPlanTable col 2 hover shows crate item tooltip and crate breakdown")
		favorRow.cells[2]:GetScript("OnLeave")(favorRow.cells[2])
		check(not GameTooltip:IsShown(), "favorPlanTable col 2 OnLeave hides tooltip")

		clearTip()
		favorRow.cells[3]:GetScript("OnEnter")(favorRow.cells[3])
		check(GameTooltip:IsShown() and GameTooltip._lines[1] == "Item:" .. favorRow.data.reagentID,
			"favorPlanTable col 3 hover shows reagent item tooltip")
		favorRow.cells[3]:GetScript("OnLeave")(favorRow.cells[3])
		check(not GameTooltip:IsShown(), "favorPlanTable col 3 OnLeave hides tooltip")

		-- repPlanTable cols 2 (crate) and 3 (receipt) in forged_only mode
		db.calcRepTarget = 50
		db.repSourceMode = "forged_only"
		app.setTab("calc_rep")
		local repRow = ui.repPlanTable.scrollBox._frames[1]
		check(repRow and repRow.data and repRow.data.forged and repRow.data.crateID,
			"repPlanTable populates a forged crate plan row")
		clearTip()
		repRow.cells[2]:GetScript("OnEnter")(repRow.cells[2])
		local repCrateTip = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(GameTooltip:IsShown() and GameTooltip._lines[1] == "Item:" .. repRow.data.crateID
			and repCrateTip:find("Fill Cost", 1, true) ~= nil,
			"repPlanTable col 2 hover shows crate item tooltip and crate breakdown")
		repRow.cells[2]:GetScript("OnLeave")(repRow.cells[2])
		check(not GameTooltip:IsShown(), "repPlanTable col 2 OnLeave hides tooltip")

		clearTip()
		repRow.cells[3]:GetScript("OnEnter")(repRow.cells[3])
		local expectedReceiptID = repRow.data.reqItemID or (ns.FORGED_RECEIPT and ns.FORGED_RECEIPT.receiptItemID)
		check(GameTooltip:IsShown() and GameTooltip._lines[1] == "Item:" .. expectedReceiptID,
			"repPlanTable col 3 hover shows Forged Delivery Receipt tooltip")
		repRow.cells[3]:GetScript("OnLeave")(repRow.cells[3])
		check(not GameTooltip:IsShown(), "repPlanTable col 3 OnLeave hides tooltip")

		-- dashBasketRows name hover (crate + non-crate entries)
		db.forgedTurnInQueue = { { crateID = 248687, count = 1 } }
		db.shoppingList = { { itemID = 248687, name = "Waylaid Crate: Journeyman Ore", qty = 1 } }
		app.setTab("dashboard")
		local basketCrateRow
		for _, br in ipairs(ui.dashBasketRows or {}) do
			if br:IsShown() and br.itemID == 248687 then basketCrateRow = br; break end
		end
		check(basketCrateRow and basketCrateRow.nameHover and basketCrateRow.nameHover:IsShown(),
			"dashBasketRows renders crate item with active nameHover")
		clearTip()
		basketCrateRow.nameHover:GetScript("OnEnter")(basketCrateRow.nameHover)
		local basketTip = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(GameTooltip:IsShown() and GameTooltip._lines[1] == "Item:248687"
			and basketTip:find("Fill Cost", 1, true) ~= nil,
			"dashBasketRows nameHover shows crate item tooltip and crate breakdown")
		basketCrateRow.nameHover:GetScript("OnLeave")(basketCrateRow.nameHover)
		check(not GameTooltip:IsShown(), "dashBasketRows nameHover OnLeave hides tooltip")

		-- 6. Post-review checks (#17):
		-- (a) app.invalidateRecipeStats("skills"/"known") invalidates BuildCrateTooltipData cache
		local savedGetProfs, savedGetProfInfo = _G.GetProfessions, _G.GetProfessionInfo
		local profOk, profErr = pcall(function()
			_G.GetProfessions = function() return nil end
			_G.GetProfessionInfo = function() return nil end
			ns.InvalidateCrateTooltipCache()
			local noEng = ns.BuildCrateTooltipData(248707, {
				economy = "Normal-Horde",
				crateMode = "cheapest",
				forgedMode = "self_funded",
				humanDiplomacy = false,
			})
			check(noEng and noEng.bestBundle and noEng.bestBundle.craftOpt
				and noEng.bestBundle.craftOpt.playerCanCraft == false,
				"Without Engineering, 248707 Gold Power Core craftOpt reports playerCanCraft=false")

			_G.GetProfessions = function() return 1, nil, nil, nil, nil, nil end
			_G.GetProfessionInfo = function(idx)
				if idx == 1 then return "Engineering", 136243, 200, 300, 0, 0, 202 end
			end
			local stillCached = ns.BuildCrateTooltipData(248707, {
				economy = "Normal-Horde",
				crateMode = "cheapest",
				forgedMode = "self_funded",
				humanDiplomacy = false,
			})
			check(stillCached == noEng,
				"BuildCrateTooltipData stays memoized until app.invalidateRecipeStats fires")

			app.invalidateRecipeStats("skills")
			local withEng = ns.BuildCrateTooltipData(248707, {
				economy = "Normal-Horde",
				crateMode = "cheapest",
				forgedMode = "self_funded",
				humanDiplomacy = false,
			})
			check(withEng ~= noEng and withEng.bestBundle and withEng.bestBundle.craftOpt
				and withEng.bestBundle.craftOpt.playerCanCraft == true,
				"app.invalidateRecipeStats('skills') invalidates crate tooltip cache and updates playerCanCraft=true")

			app.invalidateRecipeStats("known")
			local afterKnown = ns.BuildCrateTooltipData(248707, {
				economy = "Normal-Horde",
				crateMode = "cheapest",
				forgedMode = "self_funded",
				humanDiplomacy = false,
			})
			check(afterKnown ~= withEng and afterKnown.bestBundle.craftOpt.playerCanCraft == true,
				"app.invalidateRecipeStats('known') invalidates crate tooltip cache")
		end)
		_G.GetProfessions, _G.GetProfessionInfo = savedGetProfs, savedGetProfInfo
		ns.InvalidateCrateTooltipCache()
		if not profOk then error(profErr, 0) end

		-- (b) Bounded crateTooltipMemo (ownershipRev churn overwrites in place) & missingCost-first bundle sorting
		ns.InvalidateCrateTooltipCache()
		for rev = 1, 50 do
			ns.BuildCrateTooltipData(248687, {
				economy = "Normal-Horde",
				crateMode = "buy",
				ownershipRev = rev,
				profMap = {},
			})
		end
		local memoTable
		for i = 1, 20 do
			local upName, upVal = debug.getupvalue(ns.BuildCrateTooltipData, i)
			if not upName then break end
			if upName == "crateTooltipMemo" then memoTable = upVal; break end
		end
		check(type(memoTable) == "table", "BuildCrateTooltipData exposes module-local crateTooltipMemo")
		local memoKeys = 0
		for _ in pairs(memoTable) do memoKeys = memoKeys + 1 end
		check(memoKeys == 1, "crateTooltipMemo stays bounded to 1 entry per targetKey across 50 ownershipRev changes, got " .. memoKeys)

		local readyRanked = ns.BuildCrateTooltipData(248687, {
			economy = "Normal-Horde",
			crateMode = "buy",
			ownedCounts = { ["Iron Ore"] = 20 },
			ownershipRev = 51,
			profMap = {},
		})
		check(readyRanked and readyRanked.bundles[1].itemID == 2772
			and readyRanked.bundles[1].missing == 0 and readyRanked.bundles[1].missingCost == 0
			and readyRanked.bundles[1].isBest == true,
			"missingCost-first sorting ranks (Ready) Iron Ore bundle first despite higher bundleTotal")
		clearTip()
		GameTooltip.GetItem = function() return "Waylaid Crate: Journeyman Ore", "item:248687" end
		GameTooltip.GetTooltipData = function() return { itemID = 248687 } end
		GameTooltip:SetItemByID(248687)
		ns.AppendCrateTooltip(GameTooltip, 248687, {
			ownedCounts = { ["Iron Ore"] = 20 },
			ownershipRev = 51,
			profMap = {},
		})
		local readyTip = plain(table.concat(GameTooltip._lines or {}, "\n"))
		check(readyTip:find("* 20x Iron Ore (Ready)", 1, true) ~= nil,
			"Hovered tooltip stars (Ready) bundle first when owned")

		-- (c) Crates tab showCrateTooltip with crateTooltips=true and crateTooltips=false on both crate & reagent cells
		GameTooltip.GetItem, GameTooltip.GetTooltipData, GameTooltip.GetOwner = savedGetItem, savedGetData, savedGetOwner
		app.setTab("crates")
		local crateTabRow
		for _, fr in ipairs(ui.cratesTable.scrollBox._frames or {}) do
			if fr.data and fr.data.crateID == 248687 then crateTabRow = fr; break end
		end
		check(crateTabRow and crateTabRow.cells and crateTabRow.cells[1] and crateTabRow.cells[2],
			"cratesTable renders Journeyman Ore row with crate and reagent cells")

		db.crateTooltips = true
		for idx, cellLabel in ipairs({ "crate", "reagent" }) do
			clearTip()
			crateTabRow.cells[idx]:GetScript("OnEnter")(crateTabRow.cells[idx])
			local cTip = plain(table.concat(GameTooltip._lines or {}, "\n"))
			check(GameTooltip:IsShown()
				and cTip:find("Waylaid Crate Breakdown", 1, true) ~= nil
				and cTip:find("Selected Mode:", 1, true) ~= nil
				and cTip:find("Net Price Total", 1, true) ~= nil
				and cTip:find("Reputation", 1, true) ~= nil
				and cTip:find("Cost / Rep", 1, true) ~= nil
				and cTip:find("Fill Cost", 1, true) == nil,
				"cratesTable " .. cellLabel .. " cell with crateTooltips=true shows compact rep/cost-per-rep without contradicting Fill Cost")
			crateTabRow.cells[idx]:GetScript("OnLeave")(crateTabRow.cells[idx])
			check(not GameTooltip:IsShown(), "cratesTable " .. cellLabel .. " cell OnLeave hides tooltip")
		end

		db.crateTooltips = false
		for idx, cellLabel in ipairs({ "crate", "reagent" }) do
			clearTip()
			crateTabRow.cells[idx]:GetScript("OnEnter")(crateTabRow.cells[idx])
			local baseTip = plain(table.concat(GameTooltip._lines or {}, "\n"))
			check(GameTooltip:IsShown()
				and baseTip:find("Waylaid Crate Breakdown", 1, true) ~= nil
				and baseTip:find("Selected Mode:", 1, true) ~= nil
				and baseTip:find("Gross Cost", 1, true) ~= nil
				and baseTip:find("Net Price Total", 1, true) ~= nil
				and baseTip:find("Sales / Day", 1, true) ~= nil
				and baseTip:find("Reputation", 1, true) == nil
				and baseTip:find("Cost / Rep", 1, true) == nil,
				"cratesTable " .. cellLabel .. " cell with crateTooltips=false keeps base breakdown without fill/rep summary lines")
			crateTabRow.cells[idx]:GetScript("OnLeave")(crateTabRow.cells[idx])
			check(not GameTooltip:IsShown(), "cratesTable " .. cellLabel .. " cell OnLeave hides tooltip when crateTooltips=false")
		end
		db.crateTooltips = true
	end)

	GameTooltip.GetItem, GameTooltip.GetTooltipData, GameTooltip.GetOwner = savedGetItem, savedGetData, savedGetOwner
	GameTooltip:Hide()
	clearTip()
	_G.UnitRace = savedRace
	db.ahPrices, db.ahLots, db.rewards = savedPrices, savedLots, savedRewards
	db.priceSource, db.economy = savedSource, savedEconomy
	db.crateMode, db.subCraftMode, db.subCraftOverrides = savedCrateMode, savedSubCraft, savedOverrides
	db.forgedMode, db.forgedHumanDiplomacy, db.crateTooltips = savedForgedMode, savedHuman, savedCrateTips
	db.shoppingList, db.forgedTurnInQueue = savedShopping, savedForgedQ
	db.calcMode, db.calcFavorTarget, db.calcRepTarget, db.repSourceMode = savedCalcMode, savedCalcFavor, savedCalcRep, savedRepSrc
	if ui.optCrateTooltipCheck then ui.optCrateTooltipCheck:SetChecked(ns.IsCrateTooltipEnabled()) end
	if ui.crateTooltipCheck then ui.crateTooltipCheck:SetChecked(ns.IsCrateTooltipEnabled()) end
	ns.InvalidatePriceCache()
	app.setTab(savedTab)
	app.panel:SetShown(savedShown)
	if not ok then error(err, 0) end
end

local allowedUTF8 = {
	["·"] = true, ["—"] = true, ["–"] = true, ["…"] = true, ["×"] = true,
	["é"] = true, ["ê"] = true, ["è"] = true, ["É"] = true, ["ô"] = true, ["à"] = true,
}
for _, fName in ipairs({ "Data_CratesAndWrits.lua", "Data_Recipes.lua", "Pricing.lua", "Calculators.lua", "Professor_Engine.lua", "UI_Theme.lua", "MarketScan.lua", "TrainerServices.lua", "MerchantMaster.lua", "UI_Professor.lua", "UI_SuperList.lua" }) do
	local fh = assert(io.open(addonDir .. fName, "rb"))
	local content = fh:read("*a")
	fh:close()
	local i = 1
	while i <= #content do
		local b = content:byte(i)
		if b >= 128 then
			local seqLen = (b >= 240 and 4) or (b >= 224 and 3) or 2
			local ch = content:sub(i, i + seqLen - 1)
			check(allowedUTF8[ch] == true, fName .. " contains disallowed UTF-8 glyph: " .. ch)
			i = i + seqLen
		else
			i = i + 1
		end
	end
end

print(string.format("PASS: %d/0 failed assertions across MerchantMaster v3.2.0 (Unified Professor, %d Recipes, Multi-Select Sources & Simultaneous AH Sync)!", hostEnv.assertions(), COUNTS.totalRecipes))

