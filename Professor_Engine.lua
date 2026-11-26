-- MerchantMaster: Professor Leveling Optimizer & Working Overtime Solver Engine
local _, ns = ...

-- === UNIFIED MERCHANTPROFESSOR OPTIMIZER ENGINE ===
do local _ = (function()
local MP = ns.MP or {}
ns.MP = MP
_G.MerchantProfessorNS = MP

local STATIC_TRAINER_SEED = {
["trainerCosts"] = {
["Mana Potion"] = 5000,
["Fire Oil"] = 1000,
["Lesser Healing Potion"] = 150,
["Swim Speed Potion"] = 1000,
["Elixir of Agility"] = 6500,
["Blackmouth Oil"] = 250,
["Mind-numbing Poison III"] = 45000,
["Elixir of Minor Strength"] = 50,
["Minor Troll's Blood Elixir"] = 50,
["Lesser Mana Potion"] = 1500,
["Wound Poison"] = 13000,
["Anti-Venom"] = 250,
["Mana Well"] = 100,
["Greater Mana Potion"] = 9000,
["Minor Rejuvenation Potion"] = 150,
["Oil of Immolation"] = 8000,
["Draught of Water Breathing"] = 450,
["Viridian Dye"] = 10000,
["Silk Bandage"] = 5000,
["Lesser Troll's Blood Elixir"] = 1500,
["Deadly Poison"] = 9000,
["Elixir of Wisdom"] = 500,
["Cerulean Dye"] = 150,
["Elixir of Lesser Fortitude"] = 6000,
["Mind-numbing Poison II"] = 16000,
["Instant Poison III"] = 15000,
["Minor Mana Potion"] = 100,
["Healing Potion"] = 800,
["Wound Poison III"] = 43000,
["Minor Healing Potion"] = 100,
["Lesser Invisibility Potion"] = 5000,
["Expert Alchemist"] = 5000,
["Elixir of Defense"] = 7500,
["Apprentice Alchemist"] = 10,
["Crippling Poison"] = 4300,
["Instant Poison VI"] = 51000,
["Deadly Poison III"] = 25000,
["Instant Poison IV"] = 23000,
["Catseye Draught"] = 8000,
["Wound Poison IV"] = 48000,
["Elixir of Fire Power"] = 3000,
["Deadly Poison IV"] = 46000,
["Magenta Dye"] = 1500,
["Instant Poison V"] = 45000,
["Elixir of Minor Fortitude"] = 250,
["Draught of Greater Water Breathing"] = 10000,
["Deadly Poison II"] = 16000,
["Instant Poison II"] = 8000,
["Wound Poison II"] = 19000,
["Elixir of Lesser Defense"] = 2000,
["Simple Poultice"] = 250,
["Mind-numbing Poison"] = 6000,
["Crippling Poison II"] = 44000,
["Journeyman Alchemist"] = 500,
["Blinding Powder"] = 14000,
["Sulfuric Acid"] = 150,
},
["trainerReqs"] = {
["alchemy"] = {
[3173] = {
["req"] = 120,
},
[3177] = {
["req"] = 130,
},
[1249631] = {
["req"] = 120,
},
[12609] = {
["req"] = 200,
},
[3176] = {
["req"] = 125,
},
[11448] = {
["req"] = 205,
},
[11449] = {
["req"] = 185,
},
[3171] = {
["req"] = 90,
},
[11451] = {
["req"] = 205,
},
[11450] = {
["req"] = 195,
},
[7837] = {
["req"] = 130,
},
[7841] = {
["req"] = 100,
},
[7845] = {
["req"] = 140,
},
[22808] = {
["req"] = 215,
},
[3448] = {
["req"] = 165,
},
[3450] = {
["req"] = 175,
},
[3452] = {
["req"] = 160,
},
},
["poisons"] = {
[3421] = {
["rlv"] = 50,
["req"] = 230,
},
[8694] = {
["rlv"] = 38,
["req"] = 170,
},
[13228] = {
["rlv"] = 40,
["req"] = 180,
},
[8687] = {
["rlv"] = 28,
["req"] = 120,
},
[6510] = {
["rlv"] = 34,
["req"] = 150,
},
[3420] = {
["rlv"] = 20,
["req"] = 1,
},
[2835] = {
["rlv"] = 30,
["req"] = 130,
},
[5763] = {
["rlv"] = 24,
["req"] = 100,
},
[13230] = {
["rlv"] = 56,
["req"] = 260,
},
[11341] = {
["rlv"] = 44,
["req"] = 200,
},
[11400] = {
["rlv"] = 52,
["req"] = 240,
},
[11357] = {
["rlv"] = 46,
["req"] = 210,
},
[2837] = {
["rlv"] = 38,
["req"] = 170,
},
[11342] = {
["rlv"] = 52,
["req"] = 240,
},
[8691] = {
["rlv"] = 36,
["req"] = 160,
},
[11358] = {
["rlv"] = 54,
["req"] = 250,
},
[13229] = {
["rlv"] = 48,
["req"] = 220,
},
[13220] = {
["rlv"] = 32,
["req"] = 140,
},
},
["firstaid"] = {
[7928] = {
["req"] = 150,
},
[1244431] = {
["req"] = 1,
},
[1244432] = {
["req"] = 55,
},
[1244433] = {
["req"] = 110,
},
[7934] = {
["req"] = 80,
},
},
},
["trainerReqsByName"] = {
["poisons|Instant Poison II"] = {
["rlv"] = 28,
["req"] = 120,
},
["alchemy|Swim Speed Potion"] = {
["req"] = 100,
},
["alchemy|Magenta Dye"] = {
["req"] = 120,
},
["firstaid|Simple Poultice"] = {
["req"] = 90,
},
["alchemy|Elixir of Defense"] = {
["req"] = 195,
},
["firstaid|Lesser Healing Potion"] = {
["req"] = 55,
},
["alchemy|Lesser Troll's Blood Elixir"] = {
["req"] = 125,
},
["alchemy|Oil of Immolation"] = {
["req"] = 205,
},
["poisons|Wound Poison"] = {
["rlv"] = 32,
["req"] = 140,
},
["poisons|Wound Poison III"] = {
["rlv"] = 48,
["req"] = 220,
},
["poisons|Instant Poison III"] = {
["rlv"] = 36,
["req"] = 160,
},
["firstaid|Silk Bandage"] = {
["req"] = 150,
},
["firstaid|Minor Healing Potion"] = {
["req"] = 1,
},
["poisons|Deadly Poison III"] = {
["rlv"] = 46,
["req"] = 210,
},
["firstaid|Anti-Venom"] = {
["req"] = 80,
},
["alchemy|Fire Oil"] = {
["req"] = 130,
},
["poisons|Wound Poison II"] = {
["rlv"] = 40,
["req"] = 180,
},
["poisons|Deadly Poison"] = {
["rlv"] = 30,
["req"] = 130,
},
["alchemy|Expert Alchemist"] = {
["rlv"] = 20,
["req"] = 125,
},
["poisons|Mind-numbing Poison III"] = {
["rlv"] = 52,
["req"] = 240,
},
["poisons|Deadly Poison IV"] = {
["rlv"] = 54,
["req"] = 250,
},
["poisons|Instant Poison VI"] = {
["rlv"] = 60,
["req"] = 280,
},
["alchemy|Viridian Dye"] = {
["req"] = 215,
},
["poisons|Deadly Poison II"] = {
["rlv"] = 38,
["req"] = 170,
},
["alchemy|Lesser Invisibility Potion"] = {
["req"] = 165,
},
["alchemy|Elixir of Agility"] = {
["req"] = 185,
},
["alchemy|Draught of Greater Water Breathing"] = {
["req"] = 215,
},
["alchemy|Mana Potion"] = {
["req"] = 160,
},
["poisons|Instant Poison IV"] = {
["rlv"] = 44,
["req"] = 200,
},
["poisons|Mind-numbing Poison"] = {
["rlv"] = 24,
["req"] = 100,
},
["alchemy|Elixir of Wisdom"] = {
["req"] = 90,
},
["alchemy|Elixir of Fire Power"] = {
["req"] = 140,
},
["alchemy|Elixir of Lesser Fortitude"] = {
["req"] = 175,
},
["alchemy|Catseye Draught"] = {
["req"] = 200,
},
["poisons|Blind"] = {
["rlv"] = 34,
["req"] = 1,
},
["poisons|Mind-numbing Poison II"] = {
["rlv"] = 38,
["req"] = 170,
},
["poisons|Instant Poison V"] = {
["rlv"] = 52,
["req"] = 240,
},
["poisons|Blinding Powder"] = {
["rlv"] = 34,
["req"] = 150,
},
["alchemy|Elixir of Lesser Defense"] = {
["req"] = 130,
},
["poisons|Crippling Poison II"] = {
["rlv"] = 50,
["req"] = 230,
},
["alchemy|Lesser Mana Potion"] = {
["req"] = 120,
},
["poisons|Wound Poison IV"] = {
["rlv"] = 56,
["req"] = 260,
},
["poisons|Crippling Poison"] = {
["rlv"] = 20,
["req"] = 1,
},
["firstaid|Healing Potion"] = {
["req"] = 110,
},
["alchemy|Greater Mana Potion"] = {
["req"] = 205,
},
},
}

local PROF_DEFAULTS = {
	selectedProf = "alchemy",
	activeTab = "path",
	knownRecipesOnly = false,
	shoppingGroupMode = "consolidated",
	charLevelMode = "auto",
	overtimeMode = "auto",
	goalMode = "smart",
	recipeFilter = "trainer_vendor",
	sellDays = 3,
	applyAHCut = true,
	smartFilterColdItems = true,
	includeVendorSell = true,
	useOwned = true,
	subCraftMode = "smart",
	minimap = { hide = true, minimapPos = 242 },
	window = {},
	profTargets = {},
	profTargetsByChar = {},
	lockedRoutesByChar = {},
	knownSpells = {},
	trainerCosts = {},
	trainerReqs = {},
	trainerReqsByName = {},
	liveThresholds = {},
}

local function deepMergeMissing(dst, src)
	if type(dst) ~= "table" or type(src) ~= "table" then return end
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			deepMergeMissing(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function MP.GetDB()
	local mmdb = (type(_G.MerchantMasterDB) == "table") and _G.MerchantMasterDB or nil
	local ext = (type(_G.MerchantProfessorDB) == "table") and _G.MerchantProfessorDB or nil
	if mmdb and type(mmdb.professor) == "table" and mmdb.professor._defaultsApplied
		and (not ext or ext == mmdb.professor or mmdb.professor._migratedLegacyProfDB)
		and (not STATIC_TRAINER_SEED or mmdb.professor._migratedStandaloneSeed) then
		return mmdb.professor
	elseif not mmdb and ext and ext._defaultsApplied
		and (not STATIC_TRAINER_SEED or ext._migratedStandaloneSeed) then
		return ext
	end
	local db
	if mmdb then
		if type(mmdb.professor) ~= "table" then
			mmdb.professor = {}
		end
		db = mmdb.professor
		if ext and ext ~= db and not db._migratedLegacyProfDB then
			deepMergeMissing(db, ext)
			db._migratedLegacyProfDB = true
		end
	else
		if not ext then
			ext = {}
			_G.MerchantProfessorDB = ext
		end
		db = ext
	end
	if STATIC_TRAINER_SEED and not db._migratedStandaloneSeed then
		db.trainerCosts = db.trainerCosts or {}
		deepMergeMissing(db.trainerCosts, STATIC_TRAINER_SEED.trainerCosts)
		db.trainerReqs = db.trainerReqs or {}
		deepMergeMissing(db.trainerReqs, STATIC_TRAINER_SEED.trainerReqs)
		db.trainerReqsByName = db.trainerReqsByName or {}
		deepMergeMissing(db.trainerReqsByName, STATIC_TRAINER_SEED.trainerReqsByName)
		db._migratedStandaloneSeed = true
	end
	deepMergeMissing(db, PROF_DEFAULTS)
	if db.subCraftMode == "cheapest" then db.subCraftMode = "smart" end
	if db.activeTab == "overtime" then db.activeTab = "path" end
	if db.shoppingGroupMode ~= "consolidated" and db.shoppingGroupMode ~= "by_level" then
		db.shoppingGroupMode = "consolidated"
	end
	db._defaultsApplied = true
	return db
end
ns.GetProfessorDB = MP.GetDB


---------------------------------------------------------------------------------------------------
-- MerchantProfessor — Optimizer Engine, Legacy Trait Detector & Self-Feeding Shopping List Builder
-- Extends MerchantMaster's live AH / Local Snapshot / Vendor / Favor pricing across all 10 craftable skills.
---------------------------------------------------------------------------------------------------

local math_min, math_max, math_floor, math_ceil = math.min, math.max, math.floor, math.ceil
local liveThresholdsRev = 0
local ITEM_ID_BY_NAME = {}
for id, info in pairs(MP.ITEM_INFO or {}) do
	if info and info.name and info.name ~= "" and not ITEM_ID_BY_NAME[info.name] then
		ITEM_ID_BY_NAME[info.name] = id
	end
end

-- Build fast output-item -> recipes index per profession for same-profession sub-crafting
MP.RECIPES_BY_OUTPUT = {}
MP.PROF_BY_SPELL = {}
MP.RECIPE_BY_SPELL = {}
for pk, list in pairs(MP.RECIPES or {}) do
	local byOut = {}
	for _, r in ipairs(list) do
		if r.s then
			MP.PROF_BY_SPELL[r.s] = pk
			MP.RECIPE_BY_SPELL[r.s] = r
		end
		if (r.i or 0) > 0 and not r.ench then
			byOut[r.i] = byOut[r.i] or {}
			byOut[r.i][#byOut[r.i] + 1] = r
		end
	end
	MP.RECIPES_BY_OUTPUT[pk] = byOut
end

function MP.GetLiveThresholdsRev()
	return liveThresholdsRev
end

local function isItemBoP(itemID)
	if not itemID or itemID <= 0 then return false end
	if ns.ITEM_BOP and ns.ITEM_BOP[itemID] then return true end
	local info = MP.ITEM_INFO and MP.ITEM_INFO[itemID]
	return (info and info.bop == true) or false
end

local function resolveMns()
	local MM = _G.MerchantMasterAPI
	return (MM and MM.ns) or ns
end

local function resolveOwnedID(name)
	if type(name) ~= "string" or name == "" then return nil end
	local mns = resolveMns()
	if mns and mns.ITEM_IDS_BY_NAME and mns.ITEM_IDS_BY_NAME[name] then
		return mns.ITEM_IDS_BY_NAME[name]
	end
	return ITEM_ID_BY_NAME[name]
end

local function getOwnedQtyByID(itemID, ctx)
	if not ctx or not ctx.useOwned or not itemID or itemID <= 0 then return 0 end
	ctx.ownedQtyCache = ctx.ownedQtyCache or {}
	local cached = ctx.ownedQtyCache[itemID]
	if cached ~= nil then return cached end
	local q = 0
	if ctx.ownedByID then
		q = tonumber(ctx.ownedByID[itemID]) or 0
	end
	if q == 0 and ctx.ownedCounts and not ctx._ownedIDsExclusive then
		local nm = MP.ItemName(itemID)
		if nm and ctx.ownedCounts[nm] then
			q = math_max(q, tonumber(ctx.ownedCounts[nm]) or 0)
		end
	end
	if q < 0 then q = 0 end
	ctx.ownedQtyCache[itemID] = q
	return q
end

local SPECS_BY_PROF = {}
for specID, sInfo in pairs(MP.PROF_SPECS or {}) do
	SPECS_BY_PROF[sInfo.prof] = SPECS_BY_PROF[sInfo.prof] or {}
	SPECS_BY_PROF[sInfo.prof][#SPECS_BY_PROF[sInfo.prof] + 1] = specID
end

local FALLBACK_MM_API = { ns = ns }
function MP.GetMM()
	if _G.MerchantMasterAPI then return _G.MerchantMasterAPI end
	FALLBACK_MM_API.ns = ns
	FALLBACK_MM_API.Theme = ns.Theme
	return FALLBACK_MM_API
end

function MP.InitPricingBridge()
	local mns = resolveMns()
	if not mns then return false end

	mns.ALL_CATALOG_IDS = mns.ALL_CATALOG_IDS or {}
	mns.VENDOR_REAGENTS = mns.VENDOR_REAGENTS or {}
	mns.ITEM_NAMES = mns.ITEM_NAMES or {}
	mns.ITEM_NAMES_BY_ID = mns.ITEM_NAMES_BY_ID or {}
	mns.ITEM_IDS_BY_NAME = mns.ITEM_IDS_BY_NAME or {}

	for id, info in pairs(MP.ITEM_INFO or {}) do
		mns.ALL_CATALOG_IDS[id] = true
		if info.name and info.name ~= "" then
			if not mns.ITEM_NAMES[id] then mns.ITEM_NAMES[id] = info.name end
			if not mns.ITEM_NAMES_BY_ID[id] then mns.ITEM_NAMES_BY_ID[id] = info.name end
			if not mns.ITEM_IDS_BY_NAME[info.name] then mns.ITEM_IDS_BY_NAME[info.name] = id end
		end
	end
	return true
end

function MP.ItemName(itemID)
	if not itemID or itemID <= 0 then return "" end
	local mns = resolveMns()
	if mns and mns.ItemName then
		local nm = mns.ItemName(itemID)
		if nm and not nm:find("^Item #") then return nm end
	end
	local info = MP.ITEM_INFO and MP.ITEM_INFO[itemID]
	if info and info.name and info.name ~= "" then return info.name end
	if GetItemInfo then
		local nm = GetItemInfo(itemID)
		if nm then return nm end
	end
	return "Item #" .. tostring(itemID)
end

function MP.GetVendorSell(itemID)
	if not itemID or itemID <= 0 then return 0 end
	local mns = resolveMns()
	if mns and mns.GetVendorSellPrice then
		local liveSell = mns.GetVendorSellPrice(itemID)
		if type(liveSell) == "number" and liveSell >= 0 then
			return liveSell
		end
	end
	local sellPrice
	if C_Item and C_Item.GetItemInfo then
		sellPrice = select(11, C_Item.GetItemInfo(itemID))
	elseif GetItemInfo then
		sellPrice = select(11, GetItemInfo(itemID))
	end
	if type(sellPrice) == "number" and sellPrice >= 0 then
		return math_floor(sellPrice + 0.5)
	end
	local info = MP.ITEM_INFO and MP.ITEM_INFO[itemID]
	if info and type(info.sell) == "number" and info.sell >= 0 then
		return info.sell
	end
	return 0
end

---------------------------------------------------------------------------------------------------
-- WoW: Forever Legacy Trait Detection (Tree 1187 / System 45: Professions)

local function readTraitNodeRank(configID, nodeID, maxRanks)
	if not (C_Traits and C_Traits.GetNodeInfo and configID and nodeID) then return nil end
	local ok, info = pcall(C_Traits.GetNodeInfo, configID, nodeID)
	if not ok or type(info) ~= "table" then return nil end
	local r = tonumber(info.activeRank) or tonumber(info.ranksPurchased) or tonumber(info.currentRank) or 0
	if r < 0 then r = 0 elseif maxRanks and r > maxRanks then r = maxRanks end
	return r
end

function MP.DetectLegacyPerks()
	local traits = MP.LEGACY_TRAITS
	local res = {
		detected = false,
		overtime = 0,
		bartering = 0,
		masterChef = 0,
		perfBonus = 0,
	}
	local configID
	if C_Traits then
		if C_Traits.GetConfigIDByTreeID then
			local ok, cid = pcall(C_Traits.GetConfigIDByTreeID, traits.treeID)
			if ok and cid and cid > 0 then configID = cid end
		end
		if not configID and C_Traits.GetConfigIDBySystemID then
			local ok, cid = pcall(C_Traits.GetConfigIDBySystemID, traits.systemID)
			if ok and cid and cid > 0 then configID = cid end
		end
	end
	if configID then
		local ot = readTraitNodeRank(configID, traits.overtime.nodeID, traits.overtime.maxRanks)
		if ot ~= nil then
			res.detected = true
			res.overtime = ot
			res.bartering = readTraitNodeRank(configID, traits.bartering.nodeID, traits.bartering.maxRanks) or 0
			res.masterChef = readTraitNodeRank(configID, traits.masterChef.nodeID, traits.masterChef.maxRanks) or 0
			res.perfBonus = readTraitNodeRank(configID, traits.perfBonus.nodeID, traits.perfBonus.maxRanks) or 0
			return res
		end
	end
	-- Fallback if C_Traits config isn't loaded yet
	local checkSpell = IsPlayerSpell or IsSpellKnown
	if checkSpell then
		local ok, known = pcall(checkSpell, traits.overtime.spellID)
		if ok and known then
			res.detected = true
			res.overtime = 1
		end
	end
	return res
end

function MP.GetEffectiveLegacy(db)
	db = db or MP.GetDB() or {}
	local live = MP.DetectLegacyPerks()
	local otMode = db.overtimeMode
	local ot = live.overtime
	local isManual = false
	if type(otMode) == "number" and otMode >= 0 and otMode <= 5 then
		ot = math_floor(otMode)
		isManual = true
	end
	local bart = (type(db.barteringOverride) == "number") and db.barteringOverride or live.bartering
	local chef = (type(db.masterChefOverride) == "number") and db.masterChefOverride or live.masterChef
	local perf = (type(db.perfBonusOverride) == "number") and db.perfBonusOverride or live.perfBonus
	return {
		detected = live.detected,
		liveOvertime = live.overtime,
		overtime = ot,
		overtimeBonus = ot * 0.04,
		isManualOvertime = isManual,
		bartering = bart,
		vendorMult = 1 - 0.05 * bart,
		masterChef = chef,
		cookingYieldMult = 1 + 0.10 * chef,
		perfBonus = perf,
		favorYieldMult = 1 + 0.05 * perf,
	}
end

---------------------------------------------------------------------------------------------------
-- Live Player Profession Skill, Character Level & Trainer Ground-Truth Requirements

local NAME_TO_PROF_KEY = {}
for k, info in pairs(MP.PROFESSIONS) do
	NAME_TO_PROF_KEY[info.name:lower()] = k
end
MP.NAME_TO_PROF_KEY = NAME_TO_PROF_KEY

function MP.GetCharKey()
	local name = (ns.GetPlayerFullName and ns.GetPlayerFullName()) or (UnitName and UnitName("player")) or "Player"
	local realm = GetRealmName and GetRealmName() or "Forever"
	return name .. "-" .. realm
end

function MP.GetLivePlayerLevel()
	local lv = UnitLevel and UnitLevel("player")
	lv = tonumber(lv)
	if not lv or lv < 1 then return 60 end
	return math_max(1, math_min(60, math_floor(lv)))
end

function MP.GetEffectiveCharLevel(db, opts)
	opts = opts or {}
	if tonumber(opts.charLevel) then
		return math_max(1, math_min(60, math_floor(tonumber(opts.charLevel)))), false
	end
	if opts.ignoreCharLevel == true or opts.useFullRange == true then
		return 60, false
	end
	db = db or MP.GetDB() or {}
	local mode = db.charLevelMode
	if type(mode) == "number" and mode >= 1 and mode <= 60 then
		return math_floor(mode), false
	end
	return MP.GetLivePlayerLevel(), true
end

function MP.GetMaxSkillForCharLevel(profKey, charLevel, liveMaxRank)
	local pInfo = MP.PROFESSIONS[profKey]
	if not pInfo then return 300, nil end
	charLevel = tonumber(charLevel) or 60
	liveMaxRank = tonumber(liveMaxRank) or 0

	if pInfo.levelScale and pInfo.levelScale > 0 then
		local minLv = pInfo.minLv or 20
		if charLevel < minLv and liveMaxRank <= 0 then
			return 0, { cap = minLv * pInfo.levelScale, rlv = minLv, name = pInfo.name }
		end
		local cap = math_max(liveMaxRank, math_min(300, charLevel * pInfo.levelScale))
		local nextInfo = nil
		if cap < 300 then
			local nextLv = math_max(minLv, math_floor(cap / pInfo.levelScale) + 1)
			nextInfo = {
				cap = math_min(300, nextLv * pInfo.levelScale),
				rlv = nextLv,
				name = pInfo.name .. " Cap " .. tostring(math_min(300, nextLv * pInfo.levelScale)),
			}
		end
		return cap, nextInfo
	end

	local maxCap = liveMaxRank
	local nextRank = nil
	for _, rk in ipairs(pInfo.ranks or {}) do
		local reqLv = rk.rlv or 1
		if charLevel >= reqLv then
			if rk.cap > maxCap then maxCap = rk.cap end
		elseif not nextRank and rk.cap > maxCap then
			nextRank = { cap = rk.cap, rlv = reqLv, name = rk.name }
		end
	end
	return maxCap, nextRank
end

function MP.GetEffectiveRecipeReqs(rec, db, profKey)
	if not rec then return 1, 1 end
	db = db or MP.GetDB()
	local pk = profKey or rec.prof
	local effReq = rec.req or 1
	local effRlv = rec.rlv or 1

	-- MerchantProfessor live trainer scanner (highest authority: exact server values)
	if type(db) == "table" then
		local tSpell = db.trainerReqs and pk and db.trainerReqs[pk] and db.trainerReqs[pk][rec.s]
		local tName = (not tSpell) and db.trainerReqsByName and pk and rec.n and db.trainerReqsByName[pk .. "|" .. rec.n] or nil
		local tr = tSpell or tName
		if type(tr) == "table" then
			if tonumber(tr.req) and tonumber(tr.req) > 0 then
				effReq = math_floor(tonumber(tr.req))
			end
			if tonumber(tr.rlv) and tonumber(tr.rlv) > 0 then
				effRlv = math_max(effRlv, math_floor(tonumber(tr.rlv)))
			end
		end
	end

	return effReq, effRlv
end

function MP.ScanPlayerProfessions()
	local out = {}
	local mns = resolveMns()
	if mns and (mns.GetLivePlayerProfessions or mns.GetPlayerProfessions) then
		local mmProfs = (mns.GetLivePlayerProfessions or mns.GetPlayerProfessions)() or {}
		for k, rank in pairs(mmProfs) do
			if MP.PROFESSIONS[k] and type(rank) == "number" and rank > 0 then
				out[k] = { rank = rank, maxRank = math_min(300, math_max(75, math_ceil(rank / 75) * 75)), learned = true }
			end
		end
	end

	-- Classic / Forever SkillLines API gives exact rank AND maxRank (75 / 150 / 225 / 300)
	if GetNumSkillLines and GetSkillLineInfo then
		local ok, num = pcall(GetNumSkillLines)
		if ok and type(num) == "number" then
			for idx = 1, num do
				local sName, isHeader, _, sRank, _, sMod, sMaxRank = GetSkillLineInfo(idx)
				if not isHeader and type(sName) == "string" then
					local pk = NAME_TO_PROF_KEY[sName:lower()]
					if pk and type(sRank) == "number" and sRank > 0 then
						out[pk] = {
							rank = sRank,
							mod = tonumber(sMod) or 0,
							maxRank = tonumber(sMaxRank) or 75,
							learned = true,
						}
					end
				end
			end
		end
	end

	-- Rogue Poisons fallback check
	if not out.poisons and UnitClass then
		local _, classToken = UnitClass("player")
		if classToken == "ROGUE" then
			local check = IsPlayerSpell or IsSpellKnown
			if check and check(2842) then
				local pl = MP.GetLivePlayerLevel()
				out.poisons = { rank = math_min(300, math_max(100, pl * 5)), maxRank = math_min(300, pl * 5), learned = true }
			end
		end
	end

	return out
end

function MP.IsRecipeKnownByPlayer(rec, ignoreCharLearned)
	if not rec then return false end
	if rec.src == "start" or rec.src == "gather" then return true end
	if ignoreCharLearned then return false end
	local recProf = rec.prof or (rec.s and MP.PROF_BY_SPELL and MP.PROF_BY_SPELL[rec.s]) or nil
	local mns = resolveMns()
	if mns and mns.IsRecipeKnown and rec.s then
		local ok, k = pcall(mns.IsRecipeKnown, { spellID = rec.s, name = rec.n, prof = recProf, skill = rec.req }, { currentCharOnly = true })
		if ok then return k == true end
	end
	local db = MP.GetDB()
	local ck = MP.GetCharKey()
	if db and db.knownSpells and db.knownSpells[ck] and db.knownSpells[ck][rec.s] then
		return true
	end
	local check = IsSpellKnown or IsPlayerSpell
	if check and rec.s and rec.s < 9000000 then
		local ok, k = pcall(check, rec.s)
		if ok and k then return true end
	end
	return false
end

local function getPlayerActiveSpec(profKey, ignoreCharLearned)
	if ignoreCharLearned then return nil end
	local specs = SPECS_BY_PROF[profKey]
	if not specs then return nil end
	local check = IsPlayerSpell or IsSpellKnown
	if not check then return nil end
	for _, spID in ipairs(specs) do
		local ok, k = pcall(check, spID)
		if ok and k then return spID end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Skill-Up Chance & Expected Crafts Math (Working Overtime: multiplicative +4% per rank on Yellow & Green)

function MP.GetEffectiveThresholds(rec, db)
	if not rec then return 1, 1, 1, 1, 1 end
	local effReq, effRlv = MP.GetEffectiveRecipeReqs(rec, db ~= false and db or nil, rec.prof)
	local y = math_max(effReq, tonumber(rec.y) or effReq)
	local g = math_max(y, tonumber(rec.g) or y)
	local gr = math_max(g, tonumber(rec.gr) or g)
	local ltDb = (db ~= false) and (db or MP.GetDB()) or nil
	local lt = (type(ltDb) == "table" and type(ltDb.liveThresholds) == "table" and rec.s) and ltDb.liveThresholds[rec.s] or nil
	if type(lt) == "table" then
		if tonumber(lt.gr) and tonumber(lt.gr) > 0 then
			gr = math_floor(tonumber(lt.gr))
		else
			if tonumber(lt.maxGr) then gr = math_min(gr, math_floor(tonumber(lt.maxGr))) end
			if tonumber(lt.minGr) then gr = math_max(gr, math_floor(tonumber(lt.minGr))) end
		end
		if tonumber(lt.maxG) then g = math_min(g, math_floor(tonumber(lt.maxG))) end
		if tonumber(lt.minG) then g = math_max(g, math_floor(tonumber(lt.minG))) end
		if tonumber(lt.maxY) then y = math_min(y, math_floor(tonumber(lt.maxY))) end
		if tonumber(lt.minY) then y = math_max(y, math_floor(tonumber(lt.minY))) end
		gr = math_max(effReq, gr)
		y = math_max(effReq, math_min(y, gr))
		g = math_max(y, math_min(g, gr))
	end
	return effReq, y, g, gr, effRlv
end

function MP.RecordLiveRecipeColor(spellID, skillRank, difficulty, exactGrey, db)
	local sid = tonumber(spellID)
	local rk = tonumber(skillRank)
	if not sid or sid <= 0 or not rk or rk < 1 or rk > 350 or type(difficulty) ~= "string" then
		return false
	end
	local d = difficulty:lower()
	local norm
	if d == "optimal" or d == "orange" then
		norm = "optimal"
	elseif d == "medium" or d == "yellow" then
		norm = "medium"
	elseif d == "easy" or d == "green" then
		norm = "easy"
	elseif d == "trivial" or d == "grey" or d == "gray" then
		norm = "trivial"
	else
		return false
	end
	db = db or MP.GetDB()
	if type(db) ~= "table" then return false end
	db.liveThresholds = db.liveThresholds or {}
	local s = math_floor(rk)
	local cur = db.liveThresholds[sid]
	local changed = false
	if type(cur) ~= "table" then
		cur = {}
		db.liveThresholds[sid] = cur
		changed = true
	end
	local prevY, prevMaxY = cur.minY, cur.maxY
	local prevG, prevMaxG = cur.minG, cur.maxG
	local prevGr, prevMaxGr, prevExactGr = cur.minGr, cur.maxGr, cur.gr

	if norm == "optimal" then
		if not cur.minY or s + 1 > cur.minY then cur.minY = s + 1 end
		if cur.maxY and cur.maxY < cur.minY then cur.maxY = nil end
		if cur.maxG and cur.maxG < cur.minY then cur.maxG = nil end
		if cur.maxGr and cur.maxGr < cur.minY then cur.maxGr = nil end
		if cur.gr and s >= cur.gr then cur.gr = nil end
	elseif norm == "medium" then
		if not cur.maxY or s < cur.maxY then cur.maxY = s end
		if cur.minY and cur.minY > cur.maxY then cur.minY = nil end
		if not cur.minG or s + 1 > cur.minG then cur.minG = s + 1 end
		if cur.maxG and cur.maxG < cur.minG then cur.maxG = nil end
		if cur.maxGr and cur.maxGr < cur.minG then cur.maxGr = nil end
		if cur.gr and s >= cur.gr then cur.gr = nil end
	elseif norm == "easy" then
		if not cur.maxY or s < cur.maxY then cur.maxY = s end
		if cur.minY and cur.minY > cur.maxY then cur.minY = nil end
		if not cur.maxG or s < cur.maxG then cur.maxG = s end
		if cur.minG and cur.minG > cur.maxG then cur.minG = nil end
		if not cur.minGr or s + 1 > cur.minGr then cur.minGr = s + 1 end
		if cur.maxGr and cur.maxGr < cur.minGr then cur.maxGr = nil end
		if cur.gr and s >= cur.gr then cur.gr = nil end
	elseif norm == "trivial" then
		if not cur.maxGr or s < cur.maxGr then cur.maxGr = s end
		if cur.minGr and cur.minGr > cur.maxGr then cur.minGr = nil end
		if cur.minG and cur.minG > cur.maxGr then cur.minG = nil end
		if cur.minY and cur.minY > cur.maxGr then cur.minY = nil end
		if cur.gr and s < cur.gr then cur.gr = nil end
	end

	local eg = tonumber(exactGrey)
	if eg and eg > 0 then
		cur.gr = math_floor(eg)
	end

	if cur.minY ~= prevY or cur.maxY ~= prevMaxY
		or cur.minG ~= prevG or cur.maxG ~= prevMaxG
		or cur.minGr ~= prevGr or cur.maxGr ~= prevMaxGr
		or cur.gr ~= prevExactGr then
		changed = true
	end
	if changed then
		cur.at = s
		cur.diff = norm
		liveThresholdsRev = liveThresholdsRev + 1
		if MP.InvalidateSolveCache then MP.InvalidateSolveCache() end
	end
	return changed
end

function MP.GetSkillColor(rec, skill, effReqOverride, db)
	if not rec then return "gray" end
	local effReq, y, g, gr = MP.GetEffectiveThresholds(rec, db)
	local req = effReqOverride or effReq
	if skill < req then return "locked" end
	if skill >= gr or gr <= y then return "gray" end
	if skill < y then return "orange" end
	if skill < g then return "yellow" end
	return "green"
end

function MP.GetSkillUpChance(rec, skill, overtimeRank, effReqOverride, db)
	if not rec then return 0 end
	local effReq, y, _, gr = MP.GetEffectiveThresholds(rec, db)
	local req = effReqOverride or effReq
	if skill < req or skill >= gr or gr <= y then
		return 0
	end
	if skill < y then
		return 1.0
	end
	local base = (gr - skill) / (gr - y)
	local mult = 1.0 + (tonumber(overtimeRank) or 0) * 0.04
	return math_min(1.0, math_max(0, base * mult))
end

---------------------------------------------------------------------------------------------------
-- Recipe Economics: Reagent Cost, Same-Prof Sub-Crafting, One-Time Unlock & Market Hotness Resale

local function getBestFavorUnitPrice(mns, perfYieldMult)
	if not (mns and mns.EvaluateCrates) then return 0 end
	local rows = mns.EvaluateCrates({ mode = "cheapest" })
	local best
	for _, r in ipairs(rows or {}) do
		if r.pricePerToken and r.pricePerToken > 0 and (not best or r.pricePerToken < best) then
			best = r.pricePerToken
		end
	end
	return best and math_max(1, math_floor(best / (perfYieldMult or 1) + 0.5)) or 0
end

local function getPlayerFactionCode()
	if UnitFactionGroup then
		local f = UnitFactionGroup("player")
		if f == "Alliance" then return "A" elseif f == "Horde" then return "H" end
	end
	local mns = resolveMns()
	if mns and mns.DetectActiveEconomy then
		local econ = mns.DetectActiveEconomy()
		if type(econ) == "string" then
			if econ:find("Alliance") then return "A" elseif econ:find("Horde") then return "H" end
		end
	end
	return "AH"
end

MP.GetBestFavorUnitPrice = getBestFavorUnitPrice
MP.GetPlayerFactionCode = getPlayerFactionCode

local function formatSourceCoin(mns, copper)
	local n = math_floor((tonumber(copper) or 0) + 0.5)
	if n <= 0 then return nil end
	if mns and mns.FormatMoneyCompact then
		return mns.FormatMoneyCompact(n)
	end
	local g = math_floor(n / 10000)
	local s = math_floor((n % 10000) / 100)
	local c = n % 100
	if g > 0 and s > 0 then return string.format("%dg %ds", g, s) end
	if g > 0 then return string.format("%dg", g) end
	if s > 0 and c > 0 then return string.format("%ds %dc", s, c) end
	if s > 0 then return string.format("%ds", s) end
	return string.format("%dc", c)
end

local ALLOWED_BY_FILTER = {
	known_only     = { start = true, gather = true },
	trainer_only   = { start = true, trainer = true, gather = true },
	trainer_vendor = { start = true, trainer = true, vendor = true, gather = true },
	with_ah        = { start = true, trainer = true, vendor = true, ah = true, gather = true },
	all            = { start = true, trainer = true, vendor = true, ah = true, camp = true, quest = true, gather = true },
}

-- Evaluates same-profession intermediate sub-recipes (e.g. Blackmouth Oil -> Draught of Water Breathing,
-- Bolts of Cloth -> Tailoring gear, Smelt Tin/Copper -> Smelt Bronze, Blasting Powder -> Bombs)
local function findBestSameProfSubEv(rgID, maxSkillAtStep, ctx, visited)
	if ctx.subCraftMode == "buy_only" or ctx.subCraftMode == "buy" then return nil end
	if ctx.subCraftOverrides and ctx.subCraftOverrides[rgID] == "buy" then return nil end
	local byOut = MP.RECIPES_BY_OUTPUT[ctx.profKey]
	local list = byOut and byOut[rgID]
	if not list or #list == 0 then return nil end

	visited = visited or {}
	if visited[rgID] then return nil end
	local nextVisited = {}
	for k, v in pairs(visited) do nextVisited[k] = v end
	nextVisited[rgID] = true

	local bestEv, bestUnit = nil, nil
	for _, subRec in ipairs(list) do
		if (subRec.cd or 0) < 60 and not subRec.ench and (subRec.c or 1) > 0 then
			local subReq = MP.GetEffectiveRecipeReqs(subRec, ctx.db, ctx.profKey)
			if subReq <= maxSkillAtStep then
				ctx.subEvCache = ctx.subEvCache or {}
				local cacheKey = tostring(subRec.s) .. "@" .. tostring(maxSkillAtStep)
				local subEv = ctx.subEvCache[cacheKey]
				if subEv == nil then
					subEv = MP.EvaluateRecipeForSolver(subRec, ctx, nextVisited) or false
					ctx.subEvCache[cacheKey] = subEv
				end
				if subEv then
					local unit = math_max(1, math_floor((subEv.grossPerCraft / (subRec.c or 1)) + 0.5))
					if not bestUnit or unit < bestUnit then
						bestEv = subEv
						bestUnit = unit
					end
				end
			end
		end
	end
	return bestEv, bestUnit
end

local CLASS_LOCKED_SPELLS = {
	[9513] = "ROGUE", -- Thistle Tea (Rogue quest: Klaven's Tower / Mission: Possible)
}

function MP.EvaluateRecipeForSolver(rec, ctx, visited)
	local mns = ctx.mns
	local legacy = ctx.legacy
	if (rec.cd or 0) >= 60 and not ctx.allowCooldowns and not ctx.includeLockedForBrowse then
		return nil
	end
	local effReq, effY, effG, effGr, effRlv = MP.GetEffectiveThresholds(rec, ctx.db)
	local known = MP.IsRecipeKnownByPlayer(rec, ctx.ignoreLearnedSpells)
	local charLevel = ctx.charLevel or 60

	-- Class-restricted quest recipes (e.g. Rogue-only Thistle Tea)
	local reqClass = rec.s and CLASS_LOCKED_SPELLS[rec.s] or nil
	if reqClass and not known and not ctx.includeLockedForBrowse and UnitClass then
		local _, classToken = UnitClass("player")
		if classToken and classToken ~= reqClass then
			return nil
		end
	end

	-- Check recipe source filter (already-known recipes are always allowed)
	if not known and not ctx.allowedSources[rec.src] then
		return nil
	end

	-- Character level gate to learn the recipe
	local lockedByCharLevel = nil
	if not known and effRlv > charLevel then
		if ctx.includeLockedForBrowse then
			lockedByCharLevel = effRlv
		else
			return nil
		end
	end

	-- Specialization gate (Gnomish/Goblin Engineering Lv 30, Armorsmith/Weaponsmith & LW Specs Lv 40)
	local lockedBySpec = nil
	if not known and (rec.spec or 0) > 0 then
		local activeSpec = ctx.activeSpec
		if activeSpec and activeSpec ~= rec.spec then
			if ctx.includeLockedForBrowse then
				lockedBySpec = rec.spec
			else
				return nil
			end
		elseif not activeSpec and not ctx.allowedSources.quest then
			if ctx.includeLockedForBrowse then
				lockedBySpec = rec.spec
			else
				return nil
			end
		end
	end

	-- Faction check for faction-exclusive vendor/quest/camping recipes
	local scrollViaAH = false
	if not known and rec.fac and rec.fac ~= "AH" and ctx.playerFaction ~= "AH" and rec.fac ~= ctx.playerFaction then
		if rec.src == "vendor" then
			local riInfo = rec.ri and MP.ITEM_INFO[rec.ri]
			if riInfo and not riInfo.bop and ctx.allowedSources.ah and mns then
				local ahP = mns.GetItemMarketPrice(rec.ri)
				if ahP and ahP > 0 then
					scrollViaAH = true
				elseif ctx.includeLockedForBrowse then
					scrollViaAH = true
				else
					return nil
				end
			elseif not ctx.includeLockedForBrowse then
				return nil
			end
		elseif not ctx.includeLockedForBrowse then
			return nil
		end
	end

	-- Reputation check for Camp recipes unless 'all' allows future unlocks
	local repLocked = (not known and rec.src == "camp" and (rec.rep or 0) > 0 and (ctx.standingID or 4) < rec.rep) and true or false
	if repLocked and ctx.onlyUnlockedCamp then
		return nil
	end

	-- Permanent recipe source display (including NPC vendor g/s/c or Merchant's Favor token cost)
	-- plus one-time unlock cost when unlearned.
	local sourceDisplay = "Trainer"
	local vendorCopperCost, vendorCostText, favorTokens = nil, nil, nil
	local ahScrollPrice = nil
	if rec.src == "start" then
		sourceDisplay = "Starter"
	elseif rec.src == "gather" then
		sourceDisplay = "World Veins"
	elseif rec.src == "trainer" then
		sourceDisplay = "Trainer"
	elseif rec.src == "vendor" then
		if scrollViaAH then
			ahScrollPrice = mns and rec.ri and mns.GetItemMarketPrice(rec.ri) or 0
			local ahTxt = formatSourceCoin(mns, ahScrollPrice)
			sourceDisplay = ahTxt and ("AH Scroll (" .. ahTxt .. ")") or "AH Scroll"
		else
			local vCost
			if mns and mns.GetRecipeVendorBuyPrice then
				vCost = mns.GetRecipeVendorBuyPrice(rec.ri, rec.rbuy, legacy.bartering)
			end
			if not vCost then
				vCost = math_floor((rec.rbuy or 0) * legacy.vendorMult + 0.5)
			end
			vendorCopperCost = (vCost > 0) and vCost or nil
			vendorCostText = vendorCopperCost and formatSourceCoin(mns, vendorCopperCost) or nil
			sourceDisplay = vendorCostText and ("Vendor (" .. vendorCostText .. ")") or "Vendor Scroll"
		end
	elseif rec.src == "ah" then
		ahScrollPrice = mns and rec.ri and mns.GetItemMarketPrice(rec.ri) or nil
		sourceDisplay = "AH Scroll"
	elseif rec.src == "camp" then
		favorTokens = (rec.favorCost and rec.favorCost > 0 and rec.favorCost) or (rec.fav and rec.fav > 0 and rec.fav) or 30
		vendorCostText = string.format("%d Favor", favorTokens)
		sourceDisplay = string.format("Vendor (%d Favor)", favorTokens)
	elseif rec.src == "quest" then
		sourceDisplay = "Quest"
	else
		sourceDisplay = rec.src or "Drop"
	end

	local baseUnlockCost = 0
	local favorUnlockCopper = 0
	local unlockLabel = "Known"
	if not known then
		if rec.src == "start" or rec.src == "gather" then
			baseUnlockCost = 0
			unlockLabel = sourceDisplay
		elseif rec.src == "trainer" then
			local cachedTC = ctx.trainerCosts and (ctx.trainerCosts[rec.s] or ctx.trainerCosts[rec.n])
			baseUnlockCost = tonumber(cachedTC) or tonumber(rec.tc) or 0
			unlockLabel = "Trainer"
		elseif rec.src == "vendor" then
			if scrollViaAH then
				baseUnlockCost = ahScrollPrice or 0
				unlockLabel = "AH Scroll"
			else
				baseUnlockCost = vendorCopperCost or 0
				unlockLabel = sourceDisplay
			end
		elseif rec.src == "ah" then
			if not ahScrollPrice or ahScrollPrice <= 0 then
				if not ctx.includeLockedForBrowse then return nil end
				baseUnlockCost = 0
			else
				baseUnlockCost = ahScrollPrice
			end
			unlockLabel = "AH Scroll"
		elseif rec.src == "camp" then
			baseUnlockCost = 0
			favorUnlockCopper = (favorTokens and favorTokens > 0 and (ctx.favorUnitPrice or 0) > 0)
				and math_floor(favorTokens * ctx.favorUnitPrice + 0.5) or 0
			unlockLabel = sourceDisplay
		elseif rec.src == "quest" then
			baseUnlockCost = 0
			unlockLabel = "Quest"
		else
			if not ctx.includeLockedForBrowse then return nil end
			unlockLabel = sourceDisplay
		end
	end

	-- Reagent unit cost per craft (with same-profession & cross-profession smart sub-crafting)
	local grossPerCraft = 0
	local reagentDetails = {}
	local maxParentSkill = effReq
	if rec.src ~= "gather" then
		for _, rg in ipairs(rec.r or {}) do
			local rgID, rgQty = rg[1], rg[2]
			local unitCost, srcTag, isSubCraft = nil, nil, false
			local ahUnit, ahSrc = nil, nil
			local optEntry = nil
			local sameProfSubEv = nil
			local ownedOnlyReag = false

			local vBase, vFromPricing = nil, false
			local isKnownVendorReag = mns and mns.VENDOR_REAGENTS and mns.VENDOR_REAGENTS[rgID] ~= nil
			if mns and mns.GetVendorBuyPrice then
				local candBuy, candLive = mns.GetVendorBuyPrice(rgID, isKnownVendorReag and mns.VENDOR_REAGENTS[rgID] or nil, false, legacy.bartering)
				if candBuy and (isKnownVendorReag or candLive) then
					vBase, vFromPricing = candBuy, true
				end
			elseif isKnownVendorReag then
				vBase = mns.VENDOR_REAGENTS[rgID]
			end
			if vBase then
				unitCost = vFromPricing and vBase or math_max(1, math_floor(vBase * legacy.vendorMult + 0.5))
				ahUnit = unitCost
				srcTag = "Vendor"
			elseif mns then
				ctx.itemOptionCache = ctx.itemOptionCache or {}
				optEntry = ctx.itemOptionCache[rgID]
				if not optEntry then
					local ahU, ahS = mns.GetReagentUnitCost(rgID)
					if not ahU and mns.GetFallbackMarketPrice then
						local fbU, fbS = mns.GetFallbackMarketPrice(rgID)
						if fbU and fbU > 0 then
							ahU = fbU
							ahS = fbS and (fbS .. " (No AH)") or "Fallback"
						end
					end
					local cOpt
					if ctx.subCraftMode ~= "buy_only" and ctx.subCraftMode ~= "buy" and mns.GetItemCraftOption then
						local effSubMode = (ctx.subCraftMode == "all_sub") and "all_sub" or "smart"
						cOpt = mns.GetItemCraftOption(rgID, {
							parentProf = ctx.profKey,
							subCraftMode = effSubMode,
							subCraftOverrides = ctx.subCraftOverrides,
						})
					end
					optEntry = { ahUnit = ahU, ahSrc = ahS, craftOpt = cOpt }
					ctx.itemOptionCache[rgID] = optEntry
				end
				ahUnit, ahSrc = optEntry.ahUnit, optEntry.ahSrc

				-- 1. Same-profession intermediate sub-craft (e.g. Blackmouth Oil -> Draught of Water Breathing,
				--    Bolts of Cloth -> Tailoring, Smelt Tin/Copper -> Smelt Bronze, Parts -> Engineering)
				local spEv, spUnit = findBestSameProfSubEv(rgID, maxParentSkill, ctx, visited)
				local forceSub = (ctx.subCraftMode == "all_sub") or (ctx.subCraftOverrides and ctx.subCraftOverrides[rgID] == "craft")
				if spEv and spUnit then
					if forceSub or not ahUnit or spUnit < ahUnit then
						unitCost = spUnit
						srcTag = "Sub-Craft"
						isSubCraft = true
						sameProfSubEv = spEv
					end
				end

				-- 2. Cross-profession sub-craft (e.g. Blacksmithing using character's learned Mining to smelt bars)
				local craftOpt = optEntry.craftOpt
				local craftCD = tonumber(craftOpt and craftOpt.recipe and craftOpt.recipe.cd) or 0
				if not unitCost and craftOpt and craftOpt.unitCraftCost and craftCD < 60 then
					local canCrossSub = (craftOpt.playerCanCraft and not ctx.ignoreLearnedSpells) or forceSub
					if canCrossSub and (forceSub or not ahUnit or craftOpt.unitCraftCost < ahUnit) then
						unitCost = craftOpt.unitCraftCost
						srcTag = "Sub-Craft"
						isSubCraft = true
					end
				end

				-- 3. Buy directly from AH (or Fallback Market Price)
				if not unitCost and ahUnit then
					unitCost = ahUnit
					srcTag = ahSrc or "AH"
				end

				-- 4. Owned-only fallback when item is absent on AH with no fallback market price
				if not unitCost and ctx.useOwned and getOwnedQtyByID(rgID, ctx) >= rgQty then
					unitCost = MP.GetVendorSell(rgID)
					srcTag = "Owned"
					ownedOnlyReag = true
				end
			end

			if not unitCost then
				return nil -- Missing market price for required non-vendor reagent
			end
			grossPerCraft = grossPerCraft + unitCost * rgQty
			reagentDetails[#reagentDetails + 1] = {
				itemID = rgID,
				qtyPerCraft = rgQty,
				unitCost = unitCost,
				ahUnitCost = ahUnit,
				source = srcTag,
				isVendor = (vBase ~= nil),
				isSubCraft = isSubCraft,
				ownedOnly = ownedOnlyReag,
				sameProfSubEv = sameProfSubEv,
				craftOpt = (isSubCraft and not sameProfSubEv and optEntry) and optEntry.craftOpt or nil,
			}
		end
	end

	-- Output resale profile with MerchantMaster Market Hotness (Sales/Day vs AH Listed Stock)
	-- & Expected Expired-Post Deposit Risk (WoW refunds deposit when sold; failed posts lose 15% vendor deposit)
	local outID = rec.i or 0
	local vendorUnit = (not rec.ench and outID > 0) and MP.GetVendorSell(outID) or 0
	local outBoP = (rec.bop == true) or (outID > 0 and isItemBoP(outID))
	local canAH = (not rec.ench) and (not outBoP) and (outID > 0)
		and (not mns or not mns.IsItemSellable or mns.IsItemSellable(outID))
	local deNetUnit = 0
	if ctx.useDisenchantRecovery and (not rec.ench) and outID > 0
		and (not outBoP or ctx.playerKnowsEnchanting)
		and mns and mns.GetItemDEValue then
		local deNet = mns.GetItemDEValue(outID, nil, ctx.applyAHCut)
		if type(deNet) == "number" and deNet > 0 then
			deNetUnit = deNet
		end
	end

	local ahGrossUnit, ahPriceSource = nil, nil
	local rawAHUnit, rawAHSource = nil, nil
	local spotAHGrossUnit = nil
	local conservativeCapped, conservativeAnchorSrc = false, nil
	local lastKnownAHUnit, lastKnownAHSource = nil, nil
	local rawDailySold, realmDailySold, listed, saleRate, saleAvg = nil, nil, nil, nil, nil
	local isUnlisted, isCustomPrice = false, false
	if canAH and mns then
		rawAHUnit, rawAHSource = mns.GetItemMarketPrice(outID)
		spotAHGrossUnit = rawAHUnit
		if mns.GetRealmAdjustedDailySold then
			realmDailySold, rawDailySold = mns.GetRealmAdjustedDailySold(outID)
		elseif mns.GetDailySold then
			rawDailySold = mns.GetDailySold(outID)
			realmDailySold = rawDailySold
		end
		if mns.GetNumListed then listed = mns.GetNumListed(outID) end

		if mns.GetLastKnownAHPrice then
			lastKnownAHUnit, lastKnownAHSource = mns.GetLastKnownAHPrice(outID)
		end
		if not lastKnownAHUnit and rawAHUnit and rawAHUnit > 0 then
			lastKnownAHUnit, lastKnownAHSource = rawAHUnit, rawAHSource or "Live AH"
		end

		isUnlisted = (listed == 0) or (rawAHUnit == nil)
		local customPrice = (_G.MerchantMasterDB and _G.MerchantMasterDB.outlierPrices and tonumber(_G.MerchantMasterDB.outlierPrices[outID])) or nil
		if isUnlisted then
			if customPrice and customPrice > 0 then
				ahGrossUnit, ahPriceSource = math_floor(customPrice + 0.5), "Custom Price"
				isCustomPrice = true
			else
				ahGrossUnit, ahPriceSource = nil, nil
			end
		else
			if ctx.goalMode == "smart" and rawAHUnit and rawAHUnit > 0 and mns.GetConservativeSaleUnitPrice then
				local consUnit, wasCapped, ancSrc = mns.GetConservativeSaleUnitPrice(outID, rawAHUnit)
				ahGrossUnit = consUnit or rawAHUnit
				conservativeCapped = wasCapped and true or false
				conservativeAnchorSrc = ancSrc
				ahPriceSource = conservativeCapped and ((rawAHSource or "AH") .. " (Anchored)") or rawAHSource
			elseif ctx.goalMode == "ah_max" and rawAHUnit and rawAHUnit > 0 and mns.GetRealisticSaleUnitPrice then
				local realUnit, wasTrollCapped = mns.GetRealisticSaleUnitPrice(outID, rawAHUnit)
				ahGrossUnit = realUnit or rawAHUnit
				conservativeCapped = wasTrollCapped and true or false
				conservativeAnchorSrc = wasTrollCapped and ((mns.HasSnapshots and mns.HasSnapshots()) and "Snapshot Market Ceiling" or "AH Market Ceiling") or nil
				ahPriceSource = wasTrollCapped and ((rawAHSource or "AH") .. " (Capped)") or rawAHSource
			else
				ahGrossUnit, ahPriceSource = rawAHUnit, rawAHSource
			end
		end
	elseif canAH then
		isUnlisted = true
	end

	local dailySold = realmDailySold or 0
	local demand = (mns and mns.EvaluateMarketDemand)
		and mns.EvaluateMarketDemand(listed, realmDailySold, canAH)
		or {
			sellable = canAH,
			tierKey = canAH and (isUnlisted and "monopoly" or "unknown") or "bop",
			isHot = false,
			isMonopoly = isUnlisted,
			isUnlisted = isUnlisted,
			isListed = not isUnlisted,
			heatBadge = canAH and (isUnlisted and "|cffffffffUNLISTED|r" or "|cff777777—|r") or "|cff777777BoP|r",
			heatShort = canAH and (isUnlisted and "|cffffffffUNLISTED|r" or "|cff777777—|r") or "|cff777777BoP|r",
			stateLabel = canAH and (isUnlisted and "UNLISTED (0 on AH)" or "Unknown Demand") or "Not Tradeable",
			demandScore = canAH and -1 or -100,
		}

	local sellDays = ctx.sellDays or 3
	local hotnessMult = 0
	local defaultSaleRate = 0.10
	if canAH and ahGrossUnit then
		if isCustomPrice then
			hotnessMult = 1.0
			defaultSaleRate = 0.85
			if dailySold < 1 then dailySold = 3 end
		elseif listed ~= nil and realmDailySold ~= nil then
			local tk = demand.tierKey
			local ratio = demand.salesRatio or 0
			if tk == "monopoly" or tk == "high_turn" then
				hotnessMult = 1.0
				defaultSaleRate = 0.88
			elseif tk == "favorable" then
				hotnessMult = math_min(1.0, math_max(0.35, (dailySold * sellDays) / math_max(1, listed)))
				defaultSaleRate = (ratio >= 0.35) and 0.68 or 0.48
			elseif tk == "steady" then
				hotnessMult = math_min(0.60, math_max(0.15, (dailySold * sellDays) / math_max(1, listed)))
				defaultSaleRate = 0.28
			elseif ctx.smartFilterColdItems == false and dailySold >= 0.15 then
				hotnessMult = math_min(0.35, math_max(0.10, (dailySold * sellDays) / math_max(1, listed)))
				defaultSaleRate = 0.15
			else
				hotnessMult = 0
				defaultSaleRate = 0.10
			end
		elseif realmDailySold ~= nil then
			if dailySold >= 10 then
				hotnessMult = 1.0
				defaultSaleRate = 0.78
			elseif dailySold >= 1.5 then
				hotnessMult = 0.85
				defaultSaleRate = 0.52
			elseif dailySold >= 0.20 then
				hotnessMult = 0.60
				defaultSaleRate = 0.32
			elseif ctx.smartFilterColdItems == false and dailySold >= 0.15 then
				hotnessMult = 0.25
				defaultSaleRate = 0.15
			else
				hotnessMult = 0
				defaultSaleRate = 0.10
			end
		else
			if listed == nil or listed <= 80 then
				hotnessMult = 1.0
				defaultSaleRate = 0.55
				dailySold = 5
			else
				hotnessMult = 0.35
				defaultSaleRate = 0.30
				dailySold = 2
			end
		end
	end

	local effSaleRate = defaultSaleRate
	if saleRate and saleRate > 0 then
		if demand.isHot and saleRate > defaultSaleRate then
			effSaleRate = math_min(0.98, saleRate)
		else
			effSaleRate = math_max(0.08, math_min(0.95, (saleRate + defaultSaleRate) * 0.5))
		end
	end

	local unitDeposit12h = (mns and mns.GetAHUnitDeposit and outID > 0)
		and mns.GetAHUnitDeposit(outID, 1, rec.c or 1)
		or math_max(5, math_floor(vendorUnit * 0.15 + 0.5))
	local ahCutUnit = (ahGrossUnit and ctx.applyAHCut) and math_floor(ahGrossUnit * 0.05 + 0.5) or 0
	local afterCutUnit = ahGrossUnit and math_max(0, ahGrossUnit - ahCutUnit) or 0
	local expectedRelists = (ahGrossUnit and not isCustomPrice and ctx.applyAHCut and hotnessMult > 0)
		and math_min(4.0, math_max(0, (1.0 - effSaleRate) / math_max(0.15, effSaleRate)))
		or 0
	local relistLossUnit = (ahGrossUnit and not isCustomPrice and ctx.applyAHCut and hotnessMult > 0)
		and math_floor(expectedRelists * unitDeposit12h + 0.5)
		or 0
	local ahNetUnit = ahGrossUnit and math_max(0, afterCutUnit - relistLossUnit) or 0
	local hotnessCap = 0
	if hotnessMult > 0 and dailySold >= 0.15 then
		local horizonDem = dailySold * sellDays
		if isCustomPrice or realmDailySold == nil then
			hotnessCap = math_max(1, math_floor(horizonDem * hotnessMult + 0.5))
		else
			local compShare = (listed and listed > 0) and (horizonDem / (horizonDem + 0.5 * listed)) or 1.0
			hotnessCap = math_max(1, math_floor(horizonDem * compShare + 0.5))
		end
	end

	local yieldPerCraft = (rec.c or 1) * ((ctx.profKey == "cooking" and rec.src ~= "gather") and legacy.cookingYieldMult or 1.0)

	return {
		rec = rec,
		effReq = effReq,
		effY = effY,
		effG = effG,
		effGr = effGr,
		effRlv = effRlv,
		lockedByCharLevel = lockedByCharLevel,
		lockedBySpec = lockedBySpec,
		repLocked = repLocked,
		known = known,
		baseUnlockCost = baseUnlockCost,
		favorUnlockCopper = favorUnlockCopper,
		baseUnlockFavor = (not known and rec.src == "camp") and favorTokens or 0,
		unlockLabel = unlockLabel,
		sourceDisplay = sourceDisplay,
		scrollViaAH = scrollViaAH,
		vendorCopperCost = vendorCopperCost,
		vendorCostText = vendorCostText,
		favorTokens = favorTokens,
		repStanding = (rec.src == "camp" and (rec.rep or 0) > 0) and rec.rep or nil,
		vendorName = (rec.vn and rec.vn ~= "") and rec.vn or nil,
		grossPerCraft = grossPerCraft,
		reagentDetails = reagentDetails,
		vendorUnit = vendorUnit,
		deNetUnit = deNetUnit,
		unitDeposit12h = unitDeposit12h,
		relistDeposit = unitDeposit12h,
		expectedRelists = expectedRelists,
		relistLossUnit = relistLossUnit,
		canAH = canAH,
		isUnlisted = isUnlisted,
		isCustomPrice = isCustomPrice,
		lastKnownAHUnit = lastKnownAHUnit,
		lastKnownAHSource = lastKnownAHSource,
		spotAHGrossUnit = spotAHGrossUnit,
		conservativeCapped = conservativeCapped,
		conservativeAnchorSrc = conservativeAnchorSrc,
		ahGrossUnit = ahGrossUnit,
		ahPriceSource = ahPriceSource,
		ahCutUnit = ahCutUnit,
		afterCutUnit = afterCutUnit,
		ahNetUnit = ahNetUnit,
		dailySold = (realmDailySold ~= nil) and realmDailySold or nil,
		regionDailySold = (rawDailySold ~= nil) and rawDailySold or nil,
		listed = listed,
		saleRate = saleRate,
		effSaleRate = effSaleRate,
		demand = demand,
		hotnessMult = hotnessMult,
		hotnessCap = hotnessCap,
		yieldPerCraft = yieldPerCraft,
	}
end

local function computeOutputsResale(ev, unitsMade, ctx, alreadySoldAH)
	if unitsMade <= 0 or ev.rec.ench or (ev.rec.i or 0) <= 0 then
		return 0, 0, 0, "None"
	end
	local vUnit = ctx.includeVendorSell and ev.vendorUnit or 0
	local deUnit = (ctx.useDisenchantRecovery and ev.deNetUnit and ev.deNetUnit > 0) and ev.deNetUnit or 0
	local floorUnit = vUnit
	local floorIsDE = false
	if deUnit > floorUnit then
		floorUnit = deUnit
		floorIsDE = true
	end
	local floorLabel = floorIsDE and "DE (est.)" or "Vendor"
	local goal = ctx.goalMode or "smart"

	if goal == "cheapest" or not ev.canAH then
		return unitsMade * floorUnit, 0, unitsMade, (floorUnit > 0 and floorLabel or "Keep/Use")
	end

	-- Unlisted outputs fall back to non-AH floor (Vendor or DE)
	if (ev.isUnlisted and not ev.isCustomPrice) or not ev.ahGrossUnit then
		if floorUnit > 0 then
			return unitsMade * floorUnit, 0, unitsMade, floorIsDE and "DE (est.)" or "Vendor (Unlisted)"
		end
		return 0, 0, 0, "Unlisted"
	end

	if goal == "ah_max" then
		local maxUnit = math_max(floorUnit, ev.afterCutUnit or ev.ahNetUnit or 0)
		if maxUnit <= floorUnit and floorUnit > 0 then
			return unitsMade * floorUnit, 0, unitsMade, floorLabel
		end
		return unitsMade * maxUnit, unitsMade, 0, "AH"
	end

	if (ev.hotnessCap or 0) <= 0 then
		local isCold = ev.demand and ev.demand.tierKey == "cold" and (ev.listed or 0) > 0
		local tag
		if floorIsDE then
			tag = "DE (est.)"
		else
			tag = isCold
				and (floorUnit > 0 and "Vendor (Cold AH)" or "Cold AH")
				or (floorUnit > 0 and "Vendor (Low Vol)" or "Low Vol")
		end
		return unitsMade * floorUnit, 0, unitsMade, tag
	end

	if ev.ahNetUnit <= floorUnit then
		local tag
		if floorIsDE then
			tag = "DE (est.)"
		else
			tag = (floorUnit > 0 and (ev.afterCutUnit or 0) > floorUnit) and "Vendor (Deposit Risk)" or (floorUnit > 0 and "Vendor" or "Keep/Use")
		end
		return unitsMade * floorUnit, 0, unitsMade, tag
	end

	local remCap = math_max(0, ev.hotnessCap - (alreadySoldAH or 0))
	local ahSold = math_min(unitsMade, remCap)
	local floorSold = unitsMade - ahSold
	local total = ahSold * ev.ahNetUnit + floorSold * floorUnit
	local tag
	if ahSold == 0 then
		tag = floorIsDE and "DE (est.)" or ((floorUnit > 0) and "Vendor (Cap Hit)" or "Cap Hit")
	elseif floorSold > 0 then
		tag = string.format(floorIsDE and "AH %d + DE %d" or "AH %d + Vend %d", ahSold, floorSold)
	else
		tag = "AH"
	end
	return total, ahSold, floorSold, tag
end
MP.ComputeOutputsResale = computeOutputsResale

---------------------------------------------------------------------------------------------------
-- Exact Segment Dynamic Programming Leveling Path Optimizer

local function buildSolverContext(profKey, opts)
	opts = opts or {}
	local db = MP.GetDB()
	local mns = resolveMns()
	local legacy = opts.legacyOverride or MP.GetEffectiveLegacy(db)
	if opts.overtimeRank ~= nil then
		local r = math_max(0, math_min(5, math_floor(tonumber(opts.overtimeRank) or 0)))
		legacy = {
			detected = legacy.detected,
			liveOvertime = legacy.liveOvertime,
			overtime = r,
			overtimeBonus = r * 0.04,
			isManualOvertime = true,
			bartering = legacy.bartering,
			vendorMult = legacy.vendorMult,
			masterChef = legacy.masterChef,
			cookingYieldMult = legacy.cookingYieldMult,
			perfBonus = legacy.perfBonus,
			favorYieldMult = legacy.favorYieldMult,
		}
	end

	local mmdb = (type(_G.MerchantMasterDB) == "table") and _G.MerchantMasterDB or nil
	local recipeFilter = opts.recipeFilter or db.recipeFilter or "trainer_vendor"
	local sharedKnownOnly = (mmdb and mmdb.knownRecipesOnly ~= nil) and (mmdb.knownRecipesOnly == true) or (db.knownRecipesOnly == true)
	local knownOnly = (opts.knownRecipesOnly == true)
		or (opts.knownRecipesOnly == nil and opts.recipeFilter == nil and sharedKnownOnly)
	if knownOnly then
		recipeFilter = "known_only"
	end
	local allowed = ALLOWED_BY_FILTER[recipeFilter] or ALLOWED_BY_FILTER.trainer_vendor
	local repState = mns and mns.GetMerchantReputation and mns.GetMerchantReputation() or nil

	local applyAHCut = (mmdb and mmdb.applyAHCut ~= nil) and (mmdb.applyAHCut ~= false) or (db.applyAHCut ~= false)
	if opts.applyAHCut ~= nil then applyAHCut = (opts.applyAHCut == true) end
	local smartFilterColdItems = (mmdb and mmdb.smartFilterColdItems ~= nil) and (mmdb.smartFilterColdItems ~= false) or (db.smartFilterColdItems ~= false)
	if opts.smartFilterColdItems ~= nil then smartFilterColdItems = (opts.smartFilterColdItems == true) end
	local includeVendorSell = (db.includeVendorSell ~= false)
	if opts.includeVendorSell ~= nil then includeVendorSell = (opts.includeVendorSell == true) end
	local useOwned = (db.useOwned ~= false)
	if opts.useOwned ~= nil then useOwned = (opts.useOwned == true) end

	local ignoreLearnedSpells = (opts.useFullRange == true) or (opts.ignoreLearnedSpells == true)
	local charLevel, isAutoCharLv = MP.GetEffectiveCharLevel(db, opts)
	local rawSubMode = opts.subCraftMode or (mmdb and mmdb.subCraftMode) or db.subCraftMode or "smart"
	if rawSubMode == "cheapest" then rawSubMode = "smart" end
	local sharedSubOverrides = opts.subCraftOverrides or (mmdb and mmdb.subCraftOverrides) or db.subCraftOverrides
	local explicitByID = type(opts.ownedCountsByID) == "table"
	local explicitByName = type(opts.ownedCounts) == "table"
	local ownedByID = nil
	if explicitByID then
		ownedByID = opts.ownedCountsByID
	elseif explicitByName then
		ownedByID = {}
		for k, v in pairs(opts.ownedCounts) do
			local q = tonumber(v) or 0
			if q > 0 then
				if type(k) == "number" then
					ownedByID[k] = (ownedByID[k] or 0) + q
				else
					local id = resolveOwnedID(k)
					if id and id > 0 then
						ownedByID[id] = (ownedByID[id] or 0) + q
					end
				end
			end
		end
	elseif MM and MM.GetOwnedCountsByID then
		ownedByID = MM.GetOwnedCountsByID()
	end

	return {
		db = db,
		profKey = profKey,
		profInfo = MP.PROFESSIONS[profKey],
		mns = mns,
		legacy = legacy,
		charLevel = charLevel,
		isAutoCharLv = isAutoCharLv,
		activeSpec = getPlayerActiveSpec(profKey, ignoreLearnedSpells),
		recipeFilter = recipeFilter,
		allowedSources = allowed,
		goalMode = opts.goalMode or db.goalMode or "smart",
		sellDays = tonumber(opts.sellDays or db.sellDays) or 3,
		applyAHCut = applyAHCut,
		smartFilterColdItems = smartFilterColdItems,
		includeVendorSell = includeVendorSell,
		useDisenchantRecovery = (opts.useDisenchantRecovery ~= nil) and (opts.useDisenchantRecovery == true) or (db.useDisenchantRecovery == true),
		playerKnowsEnchanting = (opts.playerKnowsEnchanting ~= nil) and (opts.playerKnowsEnchanting == true) or ((opts.liveProfs or MP.ScanPlayerProfessions() or {}).enchanting ~= nil),
		useOwned = useOwned,
		ownedCounts = opts.ownedCounts or (MM and MM.GetOwnedCounts and MM.GetOwnedCounts()) or {},
		ownedByID = ownedByID,
		_ownedIDsExclusive = explicitByID,
		_allowOwnedExtra = (not explicitByID and not explicitByName),
		ownedOppCache = {},
		ownedQtyCache = {},
		subCraftMode = rawSubMode,
		subCraftOverrides = sharedSubOverrides or {},
		trainerCosts = db.trainerCosts or {},
		playerFaction = getPlayerFactionCode(),
		favorUnitPrice = getBestFavorUnitPrice(mns, legacy.favorYieldMult),
		standingID = repState and repState.standingID or 4,
		onlyUnlockedCamp = (opts.onlyUnlockedCamp == true),
		allowCooldowns = (opts.allowCooldowns == true),
		ignoreLearnedSpells = ignoreLearnedSpells,
		includeLockedForBrowse = (opts.includeLockedForBrowse == true),
		itemOptionCache = {},
		subEvCache = {},
	}
end

local function hasUnlockedInChain(prevNode, checkSpellID, checkRodCat)
	local cur = prevNode
	while cur do
		if checkSpellID and cur.unlockedSpells and cur.unlockedSpells[checkSpellID] then
			return true
		end
		if checkRodCat and cur.rodCat == checkRodCat then
			return true
		end
		cur = cur.prev
	end
	return false
end

local function collectSubUnlockCosts(ev, prevNode, unlockedSpells, seen)
	local extra = 0
	seen = seen or {}
	for _, rg in ipairs(ev.reagentDetails or {}) do
		local subEv = rg.sameProfSubEv
		if subEv and subEv.rec and not seen[subEv.rec.s] then
			seen[subEv.rec.s] = true
			if not subEv.known and not hasUnlockedInChain(prevNode, subEv.rec.s, nil) then
				extra = extra + (subEv.baseUnlockCost or 0)
				unlockedSpells = unlockedSpells or {}
				unlockedSpells[subEv.rec.s] = true
			end
			local childExtra
			childExtra, unlockedSpells = collectSubUnlockCosts(subEv, prevNode, unlockedSpells, seen)
			extra = extra + childExtra
		end
	end
	return extra, unlockedSpells
end

local function collectUnlearnedSubNodes(subEv, outList, seen)
	if not subEv or not subEv.rec then return outList end
	local subSpell = subEv.rec.s
	if seen[subSpell] then return outList end
	seen[subSpell] = true
	if not subEv.known then
		outList = outList or {}
		outList[#outList + 1] = { spell = subSpell, cost = subEv.baseUnlockCost or 0 }
	end
	local rgList = subEv.reagentDetails
	if rgList then
		for i = 1, #rgList do
			local cSub = rgList[i].sameProfSubEv
			if cSub and cSub.rec and not seen[cSub.rec.s] then
				outList = collectUnlearnedSubNodes(cSub, outList, seen)
			end
		end
	end
	return outList
end

local function buildResaleFast(ev, ctx)
	if ev.rec.ench or (ev.rec.i or 0) <= 0 then
		return 0, 0, false, 0, 0, 0
	end
	local vUnit = ctx.includeVendorSell and ev.vendorUnit or 0
	local deUnit = (ctx.useDisenchantRecovery and ev.deNetUnit and ev.deNetUnit > 0) and ev.deNetUnit or 0
	local floorUnit = math_max(vUnit, deUnit)
	local goal = ctx.goalMode or "smart"
	if goal == "cheapest" or not ev.canAH then
		return 1, floorUnit, false, 0, 0, 0
	end
	if (ev.isUnlisted and not ev.isCustomPrice) or not ev.ahGrossUnit then
		if floorUnit > 0 then
			return 1, floorUnit, false, 0, 0, 0
		end
		return 0, 0, false, 0, 0, 0
	end
	if goal == "ah_max" then
		local maxUnit = math_max(floorUnit, ev.afterCutUnit or ev.ahNetUnit or 0)
		if maxUnit <= floorUnit and floorUnit > 0 then
			return 1, floorUnit, false, 0, 0, 0
		end
		return 1, maxUnit, true, 0, 0, 0
	end
	if (ev.hotnessCap or 0) <= 0 or ev.ahNetUnit <= floorUnit then
		return 1, floorUnit, false, 0, 0, 0
	end
	return 2, 0, false, ev.hotnessCap, ev.ahNetUnit, floorUnit
end

local GREEN_RISK = 1.25

local function getOwnedOpportunityCost(itemID, buyUnit, isVendor, ctx)
	buyUnit = tonumber(buyUnit) or 0
	if buyUnit <= 0 then return 0, 0 end
	local cache = ctx.ownedOppCache
	local base = cache and cache[itemID] or nil
	if not base then
		local vSell = MP.GetVendorSell(itemID) or 0
		local bop = isItemBoP(itemID)
		local ahNet = 0
		local isVendReag = (isVendor == true) or (ctx.mns and ctx.mns.VENDOR_REAGENTS and ctx.mns.VENDOR_REAGENTS[itemID] ~= nil)
		if not bop and not isVendReag and ctx.mns and ctx.mns.GetItemMarketPrice then
			local canAH = (not ctx.mns.IsItemSellable) or ctx.mns.IsItemSellable(itemID)
			if canAH then
				local mkt = ctx.mns.GetItemMarketPrice(itemID)
				if mkt and mkt > 0 then
					if ctx.goalMode == "smart" and ctx.mns.GetConservativeSaleUnitPrice then
						mkt = ctx.mns.GetConservativeSaleUnitPrice(itemID, mkt) or mkt
					elseif ctx.goalMode == "ah_max" and ctx.mns.GetRealisticSaleUnitPrice then
						mkt = ctx.mns.GetRealisticSaleUnitPrice(itemID, mkt) or mkt
					end
					local cut = ctx.applyAHCut and math_floor(mkt * 0.05 + 0.5) or 0
					ahNet = math_max(0, mkt - cut)
				end
			end
		end
		base = { vSell = vSell, ahNet = ahNet, bop = bop }
		if cache then cache[itemID] = base end
	end
	local oppCost = base.bop and base.vSell or math_min(buyUnit, math_max(base.vSell, base.ahNet))
	local savePerUnit = math_max(0, buyUnit - oppCost)
	return oppCost, savePerUnit
end

local function scoreSegmentSlow(goalMode, netCraftGold, crafts, deltaSkill, greenExtraCrafts, extraSubClicks, grossPerCraft)
	local extraCost = extraSubClicks * 15
	local nonSkill = crafts - deltaSkill
	if nonSkill < 0 then nonSkill = 0 end
	local gExtra = (greenExtraCrafts and greenExtraCrafts > 0) and greenExtraCrafts or 0
	local perCraftNet = netCraftGold / crafts
	if perCraftNet > 0 then
		local failUnit = (perCraftNet > 20) and perCraftNet or 20
		local failPen = gExtra * failUnit
		return netCraftGold + failPen + extraCost, failPen
	end
	-- Break-even or profitable craft: credit real skill-up profit uniformly across all modes (including guaranteed
	-- NPC vendor profit in cheapest mode), while applying a 20% gross-outlay anti-spam floor (min 20c) to failed
	-- and green-risk crafts so DP never pushes deep-green crafts on profitable items for 1 skill point.
	local skillPart = deltaSkill * perCraftNet
	local failFloor = math_floor((grossPerCraft or 0) * 0.20 + 0.5)
	if failFloor < 20 then failFloor = 20 end
	local failPen = (nonSkill + gExtra) * failFloor
	return skillPart + failPen + extraCost, failPen
end

local function getBracketBounds(skill, targetSkill, profKey)
	if profKey == "poisons" then
		return 0, targetSkill
	end
	local lo, hi
	if skill < 75 then
		lo, hi = 0, 75
	elseif skill < 150 then
		lo, hi = 75, 150
	elseif skill < 225 then
		lo, hi = 150, 225
	else
		lo, hi = 225, targetSkill
	end
	if hi > targetSkill then hi = targetSkill end
	return lo, hi
end

local function buildCoupledPairUnlocks(subEv, subRec, ev, rec, unlockedSet, evalBySpell)
	local pairUnlock, pairFavorUnlock = 0, 0
	local pairUnlocked, subOnlyUnlocked
	if not subEv.known and not unlockedSet[subRec.s] then
		pairUnlock = pairUnlock + subEv.baseUnlockCost
		pairFavorUnlock = pairFavorUnlock + (subEv.favorUnlockCopper or 0)
		pairUnlocked = { [subRec.s] = true }
		subOnlyUnlocked = { [subRec.s] = true }
	end
	if not ev.known and not unlockedSet[rec.s] and not (pairUnlocked and pairUnlocked[rec.s]) then
		pairUnlock = pairUnlock + ev.baseUnlockCost
		pairFavorUnlock = pairFavorUnlock + (ev.favorUnlockCopper or 0)
		pairUnlocked = pairUnlocked or {}
		pairUnlocked[rec.s] = true
	end
	if (rec.pre or 0) > 0 then
		local preID = rec.pre
		while preID and preID > 0 do
			local preEv = evalBySpell[preID]
			if not preEv then break end
			if not preEv.known and not unlockedSet[preID] and not (pairUnlocked and pairUnlocked[preID]) then
				pairUnlock = pairUnlock + preEv.baseUnlockCost
				pairFavorUnlock = pairFavorUnlock + (preEv.favorUnlockCopper or 0)
				pairUnlocked = pairUnlocked or {}
				pairUnlocked[preID] = true
			end
			preID = preEv.rec.pre
		end
	end
	return pairUnlock, pairFavorUnlock, pairUnlocked, subOnlyUnlocked
end

local function runCoupledTransitionsAt(s1, baseCost, prevNode, curBracketHi, state, chain, cBucket)
	local ctx = state.ctx
	local goalMode = state.goalMode
	local evalBySpell = state.evalBySpell
	local rodEvalByCat = state.rodEvalByCat
	local ownedRods = state.ownedRods
	local prefUncovered = state.prefUncovered
	local dp = state.dp
	local nodeAt = state.nodeAt
	local oscAvail = state.oscAvail
	local oscUnlock = state.oscUnlock
	local oscHasSpells = state.oscHasSpells

	local priorSpec = chain.priorSpec
	local usedSpells = chain.usedSpells
	local unlockedSet = chain.unlockedSet
	local unlockedRods = chain.unlockedRods
	local priorAHSoldMap = chain.priorAHSoldMap
	local ownedUsedInChain = chain.ownedUsedInChain
	local surplusMap = chain.surplusMap

	for ci = 1, #cBucket do
		local ce = cBucket[ci]
		local pr, rg, subPr = ce.pr, ce.rg, ce.subPr
		local ev, subEv = pr.ev, subPr.ev
		local rec, subRec = ev.rec, subEv.rec
		if not (prefUncovered and (ev.isFallbackBridge or subEv.isFallbackBridge))
			and not usedSpells[rec.s] and not usedSpells[subRec.s] then
			local subSpecOK = ((subRec.spec or 0) == 0) or (not priorSpec) or (priorSpec == subRec.spec)
			local comboSpec = ((subRec.spec or 0) > 0 and subRec.spec) or priorSpec
			local mainSpecOK = ((rec.spec or 0) == 0) or (not comboSpec) or (comboSpec == rec.spec)
			if subSpecOK and mainSpecOK then
				local minMid = (s1 + 1 > pr.aStart) and (s1 + 1) or pr.aStart
				local maxMid = math_min(subPr.aEnd, pr.aEnd - 1, curBracketHi - 1)
				local mainMaxS2 = math_min(pr.aEnd, curBracketHi)
				if minMid <= maxMid and minMid < mainMaxS2 then
					local pairUnlock, pairFavorUnlock, pairUnlocked, subOnlyUnlocked =
						buildCoupledPairUnlocks(subEv, subRec, ev, rec, unlockedSet, evalBySpell)
					local rodCat = rec.rod or 0
					local rodCost = 0
					if rodCat > 0 and not ownedRods[rodCat] and not unlockedRods[rodCat] then
						local rEv = rodEvalByCat[rodCat]
						if rEv then
							rodCost = rEv.grossPerCraft + (rEv.known and 0 or rEv.baseUnlockCost)
						end
					end

					local otherReuse = nil
					if surplusMap then
						local rgList = ev.reagentDetails
						for rgi = 1, #rgList do
							local rg2 = rgList[rgi]
							if rg2.itemID ~= rg.itemID then
								local sEntry2 = surplusMap[rg2.itemID]
								local sNode2 = sEntry2 and sEntry2.node
								local av2 = sEntry2 and sEntry2.avail or 0
								if sNode2 and av2 > 0 then
									local fg2 = sNode2.surplusResaleUnit or 0
									if (rg2.unitCost or 0) >= fg2 then
										otherReuse = otherReuse or {}
										otherReuse[#otherReuse + 1] = {
											itemID = rg2.itemID,
											qtyPerCraft = rg2.qtyPerCraft,
											avail = av2,
											savePerUnit = (rg2.unitCost or 0) - fg2,
										}
									end
								end
							end
						end
					end

					local otherSubReags = ce.otherSubReags
					local nOtherSub = otherSubReags and #otherSubReags or 0
					local fastOtherQty, fastOtherHasSpells, useFastOther = 0, false, false
					if nOtherSub > 0 then
						useFastOther = true
						for osIdx = 1, nOtherSub do
							local osr = otherSubReags[osIdx]
							local sEntry2 = surplusMap and surplusMap[osr.itemID]
							local sNode2 = sEntry2 and sEntry2.node
							local av = (sEntry2 and sEntry2.avail > 0 and osr.unitCost >= (sNode2.surplusResaleUnit or 0)) and sEntry2.avail or 0
							oscAvail[osIdx] = av
							local uCost, anyU = 0, false
							if osr.unlearnedList then
								for ui = 1, #osr.unlearnedList do
									local u = osr.unlearnedList[ui]
									if not unlockedSet[u.spell] and not (pairUnlocked and pairUnlocked[u.spell]) then
										uCost = uCost + u.cost
										anyU = true
									end
								end
							end
							oscUnlock[osIdx] = uCost
							oscHasSpells[osIdx] = anyU
							if av > 0 or uCost > 0 or osr.subYield > 1 or pr.ownedReags ~= nil then
								useFastOther = false
							else
								fastOtherQty = fastOtherQty + osr.qtyPerCraft
								if anyU then fastOtherHasSpells = true end
							end
						end
					end

					local priorSubAH = (subRec.i and subRec.i > 0) and (priorAHSoldMap[subRec.i] or 0) or 0
					local priorMainAH = (rec.i and rec.i > 0) and (priorAHSoldMap[rec.i] or 0) or 0
					local subYield = math_max(1, subRec.c or 1)
					local finalSpec = ((rec.spec or 0) > 0 and rec.spec) or comboSpec
					local subRemCapBase = (subPr.rKind == 2) and math_max(0, subPr.rCap - priorSubAH) or 0
					local mainRemCapBase = (pr.rKind == 2) and math_max(0, pr.rCap - priorMainAH) or 0
					local rgUnitCost = rg.unitCost
					local basePlusPair = baseCost + pairUnlock + pairFavorUnlock + rodCost
					local subOwnedList = subPr.ownedReags
					local nSubOwned = subOwnedList and #subOwnedList or 0
					local mainOwnedList = pr.ownedReags
					local nMainOwned = mainOwnedList and #mainOwnedList or 0
					local srCanReuseAll1 = (subPr.rKind == 0) or (subPr.rKind == 1 and (subPr.rAllAH and (subPr.rUnit <= rgUnitCost) or (not subPr.rAllAH and (subPr.rUnit <= rgUnitCost or goalMode == "cheapest"))))
					local subCanReuseVend2 = (subPr.rVendUnit <= rgUnitCost)
					local subCanReuseAH2 = (subPr.rAHUnit <= rgUnitCost)
					local subAlreadyUnlocked = (subEv.known or unlockedSet[subRec.s]) and true or false
					local canEverReuseSub = (subPr.rKind ~= 2) and srCanReuseAll1 or (subPr.rKind == 2 and (subCanReuseVend2 or subCanReuseAH2))

					if canEverReuseSub or not subAlreadyUnlocked then
						local subY, subG = subEv.effY or subRec.y or 0, subEv.effG or subRec.g or 0
						local mainY, mainG = ev.effY or rec.y or 0, ev.effG or rec.g or 0
						local denseMid = (maxMid - minMid) <= 10
						for sMid = minMid, maxMid do
							if denseMid or sMid == minMid or sMid == maxMid or (sMid % 5 == 0)
								or sMid == subY or sMid == subG or sMid == mainY or sMid == mainG then
								local subExact = subPr.pref[sMid] - subPr.pref[s1]
								local subGreenExtra = math_max(0, (subPr.prefWeighted[sMid] - subPr.prefWeighted[s1]) - subExact)
								local subDelta = sMid - s1
								local subCeil = math_ceil(subExact - 1e-9)
								local subCrafts = (subCeil > subDelta) and subCeil or subDelta

								local subOwnedPossible = true
								local subOwnedCredit = 0
								local subUsedByID = nil
								if nSubOwned > 0 then
									for soi = 1, nSubOwned do
										local sor = subOwnedList[soi]
										local av = sor.totalOwned - (ownedUsedInChain and ownedUsedInChain[sor.itemID] or 0)
										if av < 0 then av = 0 end
										local need = subCrafts * sor.qtyPerCraft
										if sor.ownedOnly and av < need then
											subOwnedPossible = false
											break
										end
										if av > 0 and not sor.isSameProfSub then
											local uo = (av < need) and av or need
											if uo > 0 then
												subOwnedCredit = subOwnedCredit + uo * sor.savePerUnit
												subUsedByID = subUsedByID or {}
												subUsedByID[sor.itemID] = uo
											end
										end
									end
								end

								if not subOwnedPossible then
									break
								end

								local subUnitsMade = math_floor(subCrafts * subEv.yieldPerCraft + 1e-9)
								local subGrossTot = subCrafts * subEv.grossPerCraft
								local maxReusable = 0
								if subPr.rKind ~= 2 then
									if srCanReuseAll1 then maxReusable = subUnitsMade end
								else
									local subAHCap = (subUnitsMade < subRemCapBase) and subUnitsMade or subRemCapBase
									if subCanReuseVend2 then maxReusable = maxReusable + (subUnitsMade - subAHCap) end
									if subCanReuseAH2 then maxReusable = maxReusable + subAHCap end
								end

								if maxReusable > 0 or not subAlreadyUnlocked then
									local fullSubLeftResale, fullSubLeftAH = 0, 0
									if maxReusable == 0 and subUnitsMade > 0 then
										if subPr.rKind == 1 then
											fullSubLeftResale = subUnitsMade * subPr.rUnit
											if subPr.rAllAH then fullSubLeftAH = subUnitsMade end
										elseif subPr.rKind == 2 then
											fullSubLeftAH = (subUnitsMade < subRemCapBase) and subUnitsMade or subRemCapBase
											fullSubLeftResale = fullSubLeftAH * subPr.rAHUnit + (subUnitsMade - fullSubLeftAH) * subPr.rVendUnit
										end
									end

									for s2 = sMid + 1, mainMaxS2 do
										local mainExact = pr.pref[s2] - pr.pref[sMid]
										local mainGreenExtra = math_max(0, (pr.prefWeighted[s2] - pr.prefWeighted[sMid]) - mainExact)
										local mainDelta = s2 - sMid
										local mainCeil = math_ceil(mainExact - 1e-9)
										local mainCrafts = (mainCeil > mainDelta) and mainCeil or mainDelta
										local mainUnitsMade = math_floor(mainCrafts * ev.yieldPerCraft + 1e-9)

										local otherCredit = 0
										local otherSurplusUsedByID = nil
										if otherReuse then
											for oIdx = 1, #otherReuse do
												local orp = otherReuse[oIdx]
												local needO = mainCrafts * orp.qtyPerCraft
												local usedO = (orp.avail < needO) and orp.avail or needO
												if usedO > 0 then
													otherCredit = otherCredit + usedO * orp.savePerUnit
													if nMainOwned > 0 then
														otherSurplusUsedByID = otherSurplusUsedByID or {}
														otherSurplusUsedByID[orp.itemID] = usedO
													end
												end
											end
										end

										local subNeeded = mainCrafts * rg.qtyPerCraft
										local usedFromSub = (maxReusable < subNeeded) and maxReusable or subNeeded
										local leftoverSub = subUnitsMade - usedFromSub
										local remSubAfterStep = subNeeded - usedFromSub
										local mainOwnedCredit = 0
										local mainOwnedPossible = true
										local mainOtherSubAvail = nil
										local usedOwnCoupledMain = 0
										if nMainOwned > 0 then
											for moi = 1, nMainOwned do
												local mor = mainOwnedList[moi]
												local av = mor.totalOwned - (ownedUsedInChain and ownedUsedInChain[mor.itemID] or 0) - (subUsedByID and subUsedByID[mor.itemID] or 0)
												if av < 0 then av = 0 end
												if mor.itemID == rg.itemID then
													if mor.ownedOnly and av < remSubAfterStep then
														mainOwnedPossible = false
														break
													end
													if av > 0 and remSubAfterStep > 0 then
														local uo = (av < remSubAfterStep) and av or remSubAfterStep
														mainOwnedCredit = mainOwnedCredit + uo * mor.savePerUnit
														usedOwnCoupledMain = uo
													end
												else
													local surU = (otherSurplusUsedByID and otherSurplusUsedByID[mor.itemID]) or 0
													local mNeed = math_max(0, mainCrafts * mor.qtyPerCraft - surU)
													if mor.ownedOnly and av < mNeed then
														mainOwnedPossible = false
														break
													end
													if av > 0 and mNeed > 0 then
														if mor.isSameProfSub then
															mainOtherSubAvail = mainOtherSubAvail or {}
															mainOtherSubAvail[mor.itemID] = av
														else
															local uo = (av < mNeed) and av or mNeed
															mainOwnedCredit = mainOwnedCredit + uo * mor.savePerUnit
														end
													end
												end
											end
										end
										if not mainOwnedPossible then
											break
										end

										local remSub = remSubAfterStep - usedOwnCoupledMain
										local prepSubBatches = (remSub > 0) and ((subYield == 1) and remSub or math_ceil(remSub / subYield)) or 0
										local mainSubExtraGold = 0
										if remSub > 0 and subYield > 1 then
											local craftRem = prepSubBatches * subEv.grossPerCraft
											local buyRem = ce.rgAHBuyUnit and (remSub * ce.rgAHBuyUnit) or nil
											if buyRem and buyRem <= craftRem then
												mainSubExtraGold = buyRem - (remSub * rgUnitCost)
												prepSubBatches = 0
											else
												mainSubExtraGold = craftRem - (remSub * rgUnitCost)
											end
										end

										local subLeftResale, subLeftAH = 0, 0
										if usedFromSub == 0 then
											subLeftResale = fullSubLeftResale
											subLeftAH = fullSubLeftAH
										elseif leftoverSub > 0 then
											if subPr.rKind == 1 then
												subLeftResale = leftoverSub * subPr.rUnit
												if subPr.rAllAH then subLeftAH = leftoverSub end
											elseif subPr.rKind == 2 then
												subLeftAH = (leftoverSub < subRemCapBase) and leftoverSub or subRemCapBase
												subLeftResale = subLeftAH * subPr.rAHUnit + (leftoverSub - subLeftAH) * subPr.rVendUnit
											end
										end

										local mainResale, mainAHSold = 0, 0
										if mainUnitsMade > 0 then
											if pr.rKind == 1 then
												mainResale = mainUnitsMade * pr.rUnit
												if pr.rAllAH then mainAHSold = mainUnitsMade end
											elseif pr.rKind == 2 then
												local remM = (subRec.i == rec.i) and math_max(0, mainRemCapBase - subLeftAH) or mainRemCapBase
												mainAHSold = (mainUnitsMade < remM) and mainUnitsMade or remM
												mainResale = mainAHSold * pr.rAHUnit + (mainUnitsMade - mainAHSold) * pr.rVendUnit
											end
										end

										local otherExtraClicks, otherSubExtraCost, otherSubUnlockExtra, anyOtherSubUsed = 0, 0, 0, false
										if useFastOther then
											otherExtraClicks = mainCrafts * fastOtherQty
											anyOtherSubUsed = fastOtherHasSpells
										elseif nOtherSub > 0 then
											for osIdx = 1, nOtherSub do
												local osr = otherSubReags[osIdx]
												local remAfterO = math_max(0, mainCrafts * osr.qtyPerCraft - oscAvail[osIdx])
												local oOwn = mainOtherSubAvail and mainOtherSubAvail[osr.itemID] or 0
												local usedOOwn = (oOwn < remAfterO) and oOwn or remAfterO
												if usedOOwn > 0 then
													local _, oSave = getOwnedOpportunityCost(osr.itemID, osr.unitCost or 0, false, ctx)
													mainOwnedCredit = mainOwnedCredit + usedOOwn * oSave
												end
												local rOther = remAfterO - usedOOwn
												if rOther > 0 then
													local oUnl = oscUnlock[osIdx]
													local oYield = osr.subYield
													if oUnl == 0 and oYield == 1 then
														otherExtraClicks = otherExtraClicks + rOther
														if oscHasSpells[osIdx] then anyOtherSubUsed = true end
													else
														local oBatches = (oYield == 1) and rOther or math_ceil(rOther / oYield)
														local oCraftCost = oBatches * osr.subGrossPerCraft + oUnl
														local oBuyCost = osr.ahBuyUnit and (rOther * osr.ahBuyUnit) or nil
														if oBuyCost and oBuyCost <= oCraftCost then
															otherSubExtraCost = otherSubExtraCost + (oBuyCost - rOther * osr.unitCost)
														else
															otherSubExtraCost = otherSubExtraCost + (oBatches * osr.subGrossPerCraft - rOther * osr.unitCost)
															otherSubUnlockExtra = otherSubUnlockExtra + oUnl
															otherExtraClicks = otherExtraClicks + oBatches
															if oscHasSpells[osIdx] then anyOtherSubUsed = true end
														end
													end
												end
											end
										end

										local pairNetCraftGold = subGrossTot + (mainCrafts * ev.grossPerCraft) + mainSubExtraGold + otherSubExtraCost - (usedFromSub * rgUnitCost) - otherCredit - subOwnedCredit - mainOwnedCredit - subLeftResale - mainResale
										local pairGreenExtra = subGreenExtra + mainGreenExtra
										local extraClicks = prepSubBatches + otherExtraClicks
										local segScore, failPen
										if pairGreenExtra == 0 and pairNetCraftGold > 0 then
											segScore = pairNetCraftGold + (extraClicks * 15)
											failPen = 0
										else
											local pairGrossOutlay = subGrossTot + (mainCrafts * ev.grossPerCraft) + mainSubExtraGold + otherSubExtraCost - (usedFromSub * rgUnitCost)
											segScore, failPen = scoreSegmentSlow(goalMode, pairNetCraftGold, subCrafts + mainCrafts, s2 - s1, pairGreenExtra, extraClicks, pairGrossOutlay / math_max(1, subCrafts + mainCrafts))
										end
										local candTotal = basePlusPair + otherSubUnlockExtra + segScore

										if candTotal < dp[s2] then
											local finalPairUnlocked = pairUnlocked
											if anyOtherSubUsed then
												finalPairUnlocked = {}
												if pairUnlocked then
													for k, v in pairs(pairUnlocked) do finalPairUnlocked[k] = v end
												end
												for osIdx = 1, nOtherSub do
													if oscHasSpells[osIdx] then
														local osr = otherSubReags[osIdx]
														local oOwn = mainOtherSubAvail and mainOtherSubAvail[osr.itemID] or 0
														local rOther = mainCrafts * osr.qtyPerCraft - oscAvail[osIdx] - oOwn
														if rOther > 0 then
															local oUnl = oscUnlock[osIdx]
															local oBatches = (osr.subYield == 1) and rOther or math_ceil(rOther / osr.subYield)
															local oCraftCost = oBatches * osr.subGrossPerCraft + oUnl
															local oBuyCost = osr.ahBuyUnit and (rOther * osr.ahBuyUnit) or nil
															if not (oBuyCost and oBuyCost <= oCraftCost) then
																for ui = 1, #osr.unlearnedList do
																	finalPairUnlocked[osr.unlearnedList[ui].spell] = true
																end
															end
														end
													end
												end
											end
											local mainConsumed = nil
											if otherReuse then
												for oIdx = 1, #otherReuse do
													local orp = otherReuse[oIdx]
													local u = (orp.avail < (mainCrafts * orp.qtyPerCraft)) and orp.avail or (mainCrafts * orp.qtyPerCraft)
													if u > 0 then
														mainConsumed = mainConsumed or {}
														mainConsumed[orp.itemID] = u
													end
												end
											end
											if not useFastOther and nOtherSub > 0 then
												for osIdx = 1, nOtherSub do
													local av = oscAvail[osIdx]
													if av > 0 then
														local osr = otherSubReags[osIdx]
														local u = (av < (mainCrafts * osr.qtyPerCraft)) and av or (mainCrafts * osr.qtyPerCraft)
														if u > 0 then
															mainConsumed = mainConsumed or {}
															if not mainConsumed[osr.itemID] or u > mainConsumed[osr.itemID] then
																mainConsumed[osr.itemID] = u
															end
														end
													end
												end
											end
											local mainOwnedUsed = nil
											if nMainOwned > 0 then
												for moi = 1, nMainOwned do
													local mor = mainOwnedList[moi]
													if mor.itemID == rg.itemID then
														if usedOwnCoupledMain > 0 then
															mainOwnedUsed = mainOwnedUsed or {}
															mainOwnedUsed[mor.itemID] = usedOwnCoupledMain
														end
													else
														local av = mor.totalOwned - (ownedUsedInChain and ownedUsedInChain[mor.itemID] or 0) - (subUsedByID and subUsedByID[mor.itemID] or 0)
														if av > 0 then
															local surU = (mainConsumed and mainConsumed[mor.itemID]) or 0
															local remNeed = math_max(0, mainCrafts * mor.qtyPerCraft - surU)
															local uo = (av < remNeed) and av or remNeed
															if uo > 0 then
																mainOwnedUsed = mainOwnedUsed or {}
																mainOwnedUsed[mor.itemID] = uo
															end
														end
													end
												end
											end
											dp[s2] = candTotal
											local subNode = {
												s1 = s1,
												s2 = sMid,
												ev = subEv,
												spec = comboSpec,
												exactCrafts = subExact,
												crafts = subCrafts,
												unlockCost = 0,
												unlockedSpells = subOnlyUnlocked,
												outItemID = subRec.i,
												ahSold = subLeftAH,
												surplusID = (leftoverSub > 0 and not subRec.ench and (subRec.i or 0) > 0) and subRec.i or nil,
												surplusUnits = leftoverSub,
												surplusResaleUnit = (leftoverSub > 0) and (subLeftResale / leftoverSub) or 0,
												effortPerUnit = 0,
												ownedUsedByID = subUsedByID,
												prev = prevNode,
											}
											nodeAt[s2] = {
												s1 = sMid,
												s2 = s2,
												ev = ev,
												spec = finalSpec,
												exactCrafts = mainExact,
												crafts = mainCrafts,
												unlockCost = pairUnlock + otherSubUnlockExtra,
												rodCat = (rodCost > 0) and rodCat or nil,
												rodCost = rodCost,
												unlockedSpells = finalPairUnlocked,
												outItemID = rec.i,
												ahSold = mainAHSold,
												surplusID = (not rec.ench and (rec.i or 0) > 0) and rec.i or nil,
												surplusUnits = mainUnitsMade,
												surplusResaleUnit = (mainUnitsMade > 0) and (mainResale / mainUnitsMade) or 0,
												effortPerUnit = (mainUnitsMade > 0 and failPen > 0) and (failPen / mainUnitsMade) or 0,
												consumedSurplus = mainConsumed,
												ownedUsedByID = mainOwnedUsed,
												prev = subNode,
											}
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

local function solveDPWithCandidates(candidates, evalBySpell, rodEvalByCat, startSkill, targetSkill, ctx, allowPartial, prefUncovered)
	local otRank = tonumber(ctx.legacy.overtime) or 0
	local otMult = 1.0 + otRank * 0.04
	local goalMode = ctx.goalMode or "smart"

	-- Precompute prefix expected-craft & green-risk arrays + fast resale/owned params per candidate recipe
	local prepped = {}
	local preppedBySpell = {}
	local activeAt = {}
	for _, ev in ipairs(candidates) do
		local rec = ev.rec
		local reqRank = ev.effReq or rec.req or 1
		local effY = ev.effY or rec.y or reqRank
		local effGr = ev.effGr or rec.gr or 0
		local aStart = math_max(startSkill, reqRank)
		local aEnd = math_min(targetSkill, effGr)
		if aStart < aEnd then
			local pref = { [aStart] = 0 }
			local prefWeighted = { [aStart] = 0 }
			local valid = true
			for s = aStart, aEnd - 1 do
				local p
				if s < reqRank or s >= effGr or effGr <= effY then
					p = 0
				elseif s < effY then
					p = 1.0
				else
					p = math_min(1.0, math_max(0, ((effGr - s) / (effGr - effY)) * otMult))
				end
				if p <= 0 then
					valid = false
					break
				end
				local stepCrafts = 1.0 / p
				pref[s + 1] = pref[s] + stepCrafts
				if p < 0.5 then
					prefWeighted[s + 1] = prefWeighted[s] + 1.0 + ((stepCrafts - 1.0) * GREEN_RISK)
				else
					prefWeighted[s + 1] = prefWeighted[s] + stepCrafts
				end
			end
			if valid then
				local rKind, rUnit, rAllAH, rCap, rAHUnit, rVendUnit = buildResaleFast(ev, ctx)
				local subReags = nil
				local ownedReags = nil
				local hasOwnedOnlyReag = false
				local allSubForced = (ctx.subCraftMode == "all_sub")
				local subOverrides = ctx.subCraftOverrides
				for _, rg in ipairs(ev.reagentDetails or {}) do
					local subEv = rg.sameProfSubEv
					if subEv then
						local isForced = allSubForced or (subOverrides and subOverrides[rg.itemID] == "craft")
						local ahBuyUnit = (not isForced and rg.ahUnitCost and rg.ahUnitCost > 0) and rg.ahUnitCost or nil
						local unlearnedList = collectUnlearnedSubNodes(subEv, nil, {})
						subReags = subReags or {}
						subReags[#subReags + 1] = {
							itemID = rg.itemID,
							qtyPerCraft = rg.qtyPerCraft,
							subYield = math_max(1, subEv.rec.c or 1),
							subGrossPerCraft = subEv.grossPerCraft or 0,
							unitCost = rg.unitCost or 0,
							ahBuyUnit = ahBuyUnit,
							unlearnedList = unlearnedList,
						}
					end
					if ctx.useOwned then
						local ownQ = getOwnedQtyByID(rg.itemID, ctx)
						if ownQ > 0 or rg.ownedOnly then
							local _, savePerUnit = getOwnedOpportunityCost(rg.itemID, rg.unitCost or 0, rg.isVendor, ctx)
							if savePerUnit > 0 or rg.ownedOnly or (subEv ~= nil) then
								ownedReags = ownedReags or {}
								ownedReags[#ownedReags + 1] = {
									itemID = rg.itemID,
									qtyPerCraft = rg.qtyPerCraft,
									totalOwned = ownQ,
									savePerUnit = savePerUnit,
									ownedOnly = (rg.ownedOnly == true),
									isSameProfSub = (subEv ~= nil),
								}
								if rg.ownedOnly then hasOwnedOnlyReag = true end
							end
						end
					elseif rg.ownedOnly then
						ownedReags = ownedReags or {}
						ownedReags[#ownedReags + 1] = {
							itemID = rg.itemID,
							qtyPerCraft = rg.qtyPerCraft,
							totalOwned = 0,
							savePerUnit = 0,
							ownedOnly = true,
							isSameProfSub = (subEv ~= nil),
						}
						hasOwnedOnlyReag = true
					end
				end
				local pObj = {
					ev = ev,
					aStart = aStart,
					aEnd = aEnd,
					pref = pref,
					prefWeighted = prefWeighted,
					rKind = rKind,
					rUnit = rUnit,
					rAllAH = rAllAH,
					rCap = rCap,
					rAHUnit = rAHUnit,
					rVendUnit = rVendUnit,
					hasSameProfSub = (subReags ~= nil),
					subReags = subReags,
					ownedReags = ownedReags,
					hasOwnedOnlyReag = hasOwnedOnlyReag,
				}
				prepped[#prepped + 1] = pObj
				preppedBySpell[rec.s] = pObj
				for s = aStart, aEnd - 1 do
					local bucket = activeAt[s]
					if not bucket then bucket = {}; activeAt[s] = bucket end
					bucket[#bucket + 1] = pObj
				end
			end
		end
	end

	-- Pre-index coupled (subPr -> pr) macro-transitions by s1
	local coupledAt = {}
	local allSubForcedGlobal = (ctx.subCraftMode == "all_sub")
	local subOverridesGlobal = ctx.subCraftOverrides
	for i = 1, #prepped do
		local pr = prepped[i]
		if pr.hasSameProfSub then
			local ev = pr.ev
			local rec = ev.rec
			for _, rg in ipairs(ev.reagentDetails) do
				local subEv = rg.sameProfSubEv
				local subRec = subEv and subEv.rec
				local subPr = subRec and preppedBySpell[subRec.s]
				if subPr and subRec.s ~= rec.s then
					local s1Lo = subPr.aStart
					local s1Hi = math_min(subPr.aEnd - 1, pr.aEnd - 2)
					if s1Lo <= s1Hi then
						local otherSubReags = nil
						if pr.subReags and #pr.subReags > 1 then
							for sri = 1, #pr.subReags do
								local sr = pr.subReags[sri]
								if sr.itemID ~= rg.itemID then
									otherSubReags = otherSubReags or {}
									otherSubReags[#otherSubReags + 1] = sr
								end
							end
						end
						local rgForced = allSubForcedGlobal or (subOverridesGlobal and subOverridesGlobal[rg.itemID] == "craft")
						local rgAHBuyUnit = (not rgForced and rg.ahUnitCost and rg.ahUnitCost > 0) and rg.ahUnitCost or nil
						local entry = {
							pr = pr,
							rg = rg,
							subPr = subPr,
							otherSubReags = otherSubReags,
							rgAHBuyUnit = rgAHBuyUnit,
						}
						for s = s1Lo, s1Hi do
							local minMid = (s + 1 > pr.aStart) and (s + 1) or pr.aStart
							local maxMid = (subPr.aEnd < pr.aEnd - 1) and subPr.aEnd or (pr.aEnd - 1)
							if minMid <= maxMid then
								local cb = coupledAt[s]
								if not cb then cb = {}; coupledAt[s] = cb end
								cb[#cb + 1] = entry
							end
						end
					end
				end
			end
		end
	end

	-- Check owned Enchanting rods (by itemID or localized name fallback)
	local ownedRods = {}
	if ctx.profKey == "enchanting" then
		for cat, rInfo in pairs(MP.ENCHANTING_RODS) do
			local hasByID = (ctx.ownedByID and (ctx.ownedByID[rInfo.itemID] or 0) > 0)
				or (ctx._allowOwnedExtra and getOwnedQtyByID(rInfo.itemID, ctx) > 0)
			local nm = (not hasByID and not ctx._ownedIDsExclusive) and MP.ItemName(rInfo.itemID) or nil
			local hasByName = nm and ((ctx.ownedCounts[nm] or 0) > 0) or false
			if hasByID or hasByName or (startSkill > (rInfo.req + 35) and cat < 377) then
				ownedRods[cat] = true
			end
		end
	end

	local INF = 1e18
	local dp = {}
	local nodeAt = {}
	for s = startSkill, targetSkill do
		dp[s] = INF
	end
	dp[startSkill] = 0
	nodeAt[startSkill] = nil

	-- Reusable zero-allocation scratch arrays for sub-craft unlock/avail tracking
	local scAvail = {}
	local scUnlock = {}
	local scHasSpells = {}
	local oscAvail = {}
	local oscUnlock = {}
	local oscHasSpells = {}
	local profKey = ctx.profKey
	local dpState = {
		ctx = ctx,
		goalMode = goalMode,
		evalBySpell = evalBySpell,
		rodEvalByCat = rodEvalByCat,
		ownedRods = ownedRods,
		prefUncovered = prefUncovered,
		dp = dp,
		nodeAt = nodeAt,
		oscAvail = oscAvail,
		oscUnlock = oscUnlock,
		oscHasSpells = oscHasSpells,
	}
	local chainScratch = {}

	for s1 = startSkill, targetSkill - 1 do
		local baseCost = dp[s1]
		if baseCost < INF then
			local prevNode = nodeAt[s1]
			local curBracketLo, curBracketHi = getBracketBounds(s1, targetSkill, profKey)

			-- Single O(depth) walk of prevNode per s1 (tracks per-bracket usedSpells, unconsumed surplus, and owned usage)
			local priorSpec = ctx.activeSpec
			local usedSpells = {}
			local unlockedSet = {}
			local unlockedRods = {}
			local priorAHSoldMap = {}
			local ownedUsedInChain = nil
			local consumedSurplusByID = nil
			local surplusMap = nil
			local cur = prevNode
			local hop = 0
			while cur do
				if not priorSpec and cur.spec and cur.spec > 0 then priorSpec = cur.spec end
				local cev = cur.ev
				if cev and cev.rec and (cur.s2 or 0) > curBracketLo then
					usedSpells[cev.rec.s] = true
				end
				if cur.unlockedSpells then
					for us in pairs(cur.unlockedSpells) do unlockedSet[us] = true end
				end
				if cur.rodCat then unlockedRods[cur.rodCat] = true end
				local oid = cur.outItemID
				if oid and oid > 0 and (cur.ahSold or 0) > 0 then
					priorAHSoldMap[oid] = (priorAHSoldMap[oid] or 0) + cur.ahSold
				end
				if cur.ownedUsedByID then
					ownedUsedInChain = ownedUsedInChain or {}
					for okID, oq in pairs(cur.ownedUsedByID) do
						ownedUsedInChain[okID] = (ownedUsedInChain[okID] or 0) + oq
					end
				end
				if cur.consumedSurplus then
					consumedSurplusByID = consumedSurplusByID or {}
					for csID, csQty in pairs(cur.consumedSurplus) do
						consumedSurplusByID[csID] = (consumedSurplusByID[csID] or 0) + csQty
					end
				end
				if hop < 3 then
					local sid = cur.surplusID
					if sid and (cur.surplusUnits or 0) > 0 then
						local priorUsed = consumedSurplusByID and consumedSurplusByID[sid] or 0
						local rem = cur.surplusUnits - priorUsed
						if consumedSurplusByID and priorUsed > 0 then
							local attr = (cur.surplusUnits < priorUsed) and cur.surplusUnits or priorUsed
							consumedSurplusByID[sid] = priorUsed - attr
						end
						if rem > 0 then
							if not surplusMap then surplusMap = {} end
							if not surplusMap[sid] then
								surplusMap[sid] = { node = cur, avail = rem }
							end
						end
					end
				end
				cur = cur.prev
				hop = hop + 1
			end

			local bucket = activeAt[s1]
			if bucket then
				local baseUncov = prefUncovered and prefUncovered[s1] or 0
				for i = 1, #bucket do
					local pr = bucket[i]
					local ev = pr.ev
					local rec = ev.rec
					local isBridge = (prefUncovered ~= nil and ev.isFallbackBridge == true)
					local bridgeOK = (not isBridge) or (prefUncovered[pr.aEnd] > baseUncov)
					local specOK = ((rec.spec or 0) == 0) or (not priorSpec) or (priorSpec == rec.spec)
					if bridgeOK and specOK and not usedSpells[rec.s] then
						local unlockCost = 0
						local favorUnlockCost = 0
						local unlockedSpells
						if not ev.known and not unlockedSet[rec.s] then
							unlockCost = unlockCost + ev.baseUnlockCost
							favorUnlockCost = favorUnlockCost + (ev.favorUnlockCopper or 0)
							unlockedSpells = { [rec.s] = true }
						end

						if (rec.pre or 0) > 0 then
							local preID = rec.pre
							while preID and preID > 0 do
								local preEv = evalBySpell[preID]
								if not preEv then break end
								if not preEv.known and not unlockedSet[preID] then
									unlockCost = unlockCost + preEv.baseUnlockCost
									favorUnlockCost = favorUnlockCost + (preEv.favorUnlockCopper or 0)
									unlockedSpells = unlockedSpells or {}
									unlockedSpells[preID] = true
								end
								preID = preEv.rec.pre
							end
						end

						local rodCat = rec.rod or 0
						local rodCost = 0
						if rodCat > 0 and not ownedRods[rodCat] and not unlockedRods[rodCat] then
							local rEv = rodEvalByCat[rodCat]
							if rEv then
								rodCost = rEv.grossPerCraft + (rEv.known and 0 or rEv.baseUnlockCost)
							end
						end

						local pref = pr.pref
						local prefW = pr.prefWeighted
						local basePref = pref[s1]
						local basePrefW = prefW[s1]
						local maxS2 = math_min(pr.aEnd, curBracketHi)
						local gPerCraft = ev.grossPerCraft
						local yPerCraft = ev.yieldPerCraft
						local rKind, rUnit, rAllAH, rCap, rAHUnit, rVendUnit = pr.rKind, pr.rUnit, pr.rAllAH, pr.rCap, pr.rAHUnit, pr.rVendUnit

						-- Check preceding step surplus reuse & precomputed same-profession sub-crafts
						local reusePool = nil
						if surplusMap then
							local rgList = ev.reagentDetails
							for rgi = 1, #rgList do
								local rg = rgList[rgi]
								local sEntry = surplusMap[rg.itemID]
								local sNode = sEntry and sEntry.node
								local avail = sEntry and sEntry.avail or 0
								if sNode and avail > 0 then
									local forgoneUnit = sNode.surplusResaleUnit or 0
									if (rg.unitCost or 0) >= forgoneUnit then
										reusePool = reusePool or {}
										reusePool[#reusePool + 1] = {
											itemID = rg.itemID,
											qtyPerCraft = rg.qtyPerCraft,
											avail = avail,
											savePerUnit = (rg.unitCost or 0) - forgoneUnit,
											effortRefundUnit = rg.sameProfSubEv and (sNode.effortPerUnit or 0) or 0,
										}
									end
								end
							end
						end

						local subReags = pr.subReags
						local nSubReags = subReags and #subReags or 0
						local fastSimpleSubQty = 0
						local fastSimpleHasSpells = false
						local useFastSub = false
						if nSubReags > 0 then
							useFastSub = true
							for scIdx = 1, nSubReags do
								local sr = subReags[scIdx]
								local sEntry = surplusMap and surplusMap[sr.itemID]
								local sNode = sEntry and sEntry.node
								local av = (sEntry and sEntry.avail > 0 and sr.unitCost >= (sNode.surplusResaleUnit or 0)) and sEntry.avail or 0
								scAvail[scIdx] = av
								local uList = sr.unlearnedList
								local uCost = 0
								local anyU = false
								if uList then
									for ui = 1, #uList do
										local u = uList[ui]
										if not unlockedSet[u.spell] and not (unlockedSpells and unlockedSpells[u.spell]) then
											uCost = uCost + u.cost
											anyU = true
										end
									end
								end
								scUnlock[scIdx] = uCost
								scHasSpells[scIdx] = anyU
								if av > 0 or uCost > 0 or sr.subYield > 1 or pr.ownedReags ~= nil then
									useFastSub = false
								else
									fastSimpleSubQty = fastSimpleSubQty + sr.qtyPerCraft
									if anyU then fastSimpleHasSpells = true end
								end
							end
						end

						local ownedList = pr.ownedReags
						local nOwned = ownedList and #ownedList or 0
						local priorAHSold = (rec.i and rec.i > 0) and (priorAHSoldMap[rec.i] or 0) or 0
						local remCapBase = (rKind == 2) and (rCap - priorAHSold) or 0
						if remCapBase < 0 then remCapBase = 0 end
						local basePlusUnlock = baseCost + unlockCost + favorUnlockCost + rodCost

						for s2 = s1 + 1, maxS2 do
							if (not isBridge) or (prefUncovered[s2] > baseUncov) then
								local exactCrafts = pref[s2] - basePref
								local greenExtraCrafts = math_max(0, (prefW[s2] - basePrefW) - exactCrafts)
								local deltaSkill = s2 - s1
								local cCeil = math_ceil(exactCrafts - 1e-9)
								local crafts = (cCeil > deltaSkill) and cCeil or deltaSkill

								local reuseCredit = 0
								local effortRefund = 0
								local reuseUsedByID = nil
								if reusePool then
									for rIdx = 1, #reusePool do
										local rp = reusePool[rIdx]
										local need = crafts * rp.qtyPerCraft
										local used = (rp.avail < need) and rp.avail or need
										if used > 0 then
											reuseCredit = reuseCredit + used * rp.savePerUnit
											effortRefund = effortRefund + used * rp.effortRefundUnit
											if nOwned > 0 then
												reuseUsedByID = reuseUsedByID or {}
												reuseUsedByID[rp.itemID] = used
											end
										end
									end
								end

								local ownedPossible = true
								local ownedCredit = 0
								local ownedSubAvailByID = nil
								if nOwned > 0 then
									for oi = 1, nOwned do
										local orItem = ownedList[oi]
										local availOwn = orItem.totalOwned - (ownedUsedInChain and ownedUsedInChain[orItem.itemID] or 0)
										if availOwn < 0 then availOwn = 0 end
										local surUsed = (reuseUsedByID and reuseUsedByID[orItem.itemID]) or 0
										local remNeedOwn = math_max(0, crafts * orItem.qtyPerCraft - surUsed)
										if orItem.ownedOnly and availOwn < remNeedOwn then
											ownedPossible = false
											break
										end
										if availOwn > 0 and remNeedOwn > 0 then
											if orItem.isSameProfSub then
												ownedSubAvailByID = ownedSubAvailByID or {}
												ownedSubAvailByID[orItem.itemID] = availOwn
											else
												local uo = (availOwn < remNeedOwn) and availOwn or remNeedOwn
												ownedCredit = ownedCredit + uo * orItem.savePerUnit
											end
										end
									end
								end

								if not ownedPossible then
									break
								end

								local unitsMade = math_floor(crafts * yPerCraft + 1e-9)
								local resale, ahSold = 0, 0
								if unitsMade > 0 then
									if rKind == 1 then
										resale = unitsMade * rUnit
										if rAllAH then ahSold = unitsMade end
									elseif rKind == 2 then
										ahSold = (unitsMade < remCapBase) and unitsMade or remCapBase
										resale = ahSold * rAHUnit + (unitsMade - ahSold) * rVendUnit
									end
								end

								local extraSubClicks = 0
								local subExtraCost = 0
								local subUnlockExtra = 0
								local anySubUsed = false
								if useFastSub then
									extraSubClicks = crafts * fastSimpleSubQty
									anySubUsed = fastSimpleHasSpells
								elseif nSubReags > 0 then
									for scIdx = 1, nSubReags do
										local sr = subReags[scIdx]
										local remAfterSurplus = crafts * sr.qtyPerCraft - scAvail[scIdx]
										if remAfterSurplus < 0 then remAfterSurplus = 0 end
										local ownSub = ownedSubAvailByID and ownedSubAvailByID[sr.itemID] or 0
										local usedOwnSub = (ownSub < remAfterSurplus) and ownSub or remAfterSurplus
										if usedOwnSub > 0 then
											local _, subSave = getOwnedOpportunityCost(sr.itemID, sr.unitCost or 0, false, ctx)
											ownedCredit = ownedCredit + usedOwnSub * subSave
										end
										local remSub = remAfterSurplus - usedOwnSub
										if remSub > 0 then
											local sUnl = scUnlock[scIdx]
											local sYield = sr.subYield
											if sUnl == 0 and sYield == 1 then
												extraSubClicks = extraSubClicks + remSub
												if scHasSpells[scIdx] then anySubUsed = true end
											else
												local batches = (sYield == 1) and remSub or math_ceil(remSub / sYield)
												local craftCost = batches * sr.subGrossPerCraft + sUnl
												local ahBuy = sr.ahBuyUnit
												local buyCost = ahBuy and (remSub * ahBuy) or nil
												if buyCost and buyCost <= craftCost then
													subExtraCost = subExtraCost + (buyCost - remSub * sr.unitCost)
												else
													subExtraCost = subExtraCost + (batches * sr.subGrossPerCraft - remSub * sr.unitCost)
													subUnlockExtra = subUnlockExtra + sUnl
													extraSubClicks = extraSubClicks + batches
													if scHasSpells[scIdx] then anySubUsed = true end
												end
											end
										end
									end
								end

								local netCraftGold = (crafts * gPerCraft) + subExtraCost - reuseCredit - ownedCredit - resale
								local segScore, failPen
								if greenExtraCrafts == 0 and netCraftGold > 0 then
									segScore = netCraftGold + (extraSubClicks * 15)
									failPen = 0
								else
									segScore, failPen = scoreSegmentSlow(goalMode, netCraftGold, crafts, deltaSkill, greenExtraCrafts, extraSubClicks, gPerCraft)
								end
								local candTotal = basePlusUnlock + subUnlockExtra + segScore - effortRefund

								if candTotal < dp[s2] then
									local segUnlocked = unlockedSpells
									if anySubUsed then
										segUnlocked = {}
										if unlockedSpells then
											for k, v in pairs(unlockedSpells) do segUnlocked[k] = v end
										end
										for scIdx = 1, nSubReags do
											if scHasSpells[scIdx] then
												local sr = subReags[scIdx]
												local ownSub = ownedSubAvailByID and ownedSubAvailByID[sr.itemID] or 0
												local remSub = crafts * sr.qtyPerCraft - scAvail[scIdx] - ownSub
												if remSub > 0 then
													local sUnl = scUnlock[scIdx]
													local sYield = sr.subYield
													local batches = (sYield == 1) and remSub or math_ceil(remSub / sYield)
													local craftCost = batches * sr.subGrossPerCraft + sUnl
													local ahBuy = sr.ahBuyUnit
													local buyCost = ahBuy and (remSub * ahBuy) or nil
													if not (buyCost and buyCost <= craftCost) then
														local uList = sr.unlearnedList
														for ui = 1, #uList do
															segUnlocked[uList[ui].spell] = true
														end
													end
												end
											end
										end
									end
									local segConsumed = nil
									if reusePool then
										for rIdx = 1, #reusePool do
											local rp = reusePool[rIdx]
											local need = crafts * rp.qtyPerCraft
											local used = (rp.avail < need) and rp.avail or need
											if used > 0 then
												segConsumed = segConsumed or {}
												segConsumed[rp.itemID] = used
											end
										end
									end
									if not useFastSub and nSubReags > 0 then
										for scIdx = 1, nSubReags do
											local av = scAvail[scIdx]
											if av > 0 then
												local sr = subReags[scIdx]
												local need = crafts * sr.qtyPerCraft
												local used = (av < need) and av or need
												if used > 0 then
													segConsumed = segConsumed or {}
													if not segConsumed[sr.itemID] or used > segConsumed[sr.itemID] then
														segConsumed[sr.itemID] = used
													end
												end
											end
										end
									end
									local segOwnedUsed = nil
									if nOwned > 0 then
										for oi = 1, nOwned do
											local orItem = ownedList[oi]
											local availOwn = orItem.totalOwned - (ownedUsedInChain and ownedUsedInChain[orItem.itemID] or 0)
											if availOwn > 0 then
												local need = crafts * orItem.qtyPerCraft
												local surUsed = (segConsumed and segConsumed[orItem.itemID]) or 0
												local remNeed = math_max(0, need - surUsed)
												local uo = (availOwn < remNeed) and availOwn or remNeed
												if uo > 0 then
													segOwnedUsed = segOwnedUsed or {}
													segOwnedUsed[orItem.itemID] = uo
												end
											end
										end
									end
									dp[s2] = candTotal
									nodeAt[s2] = {
										s1 = s1,
										s2 = s2,
										ev = ev,
										spec = ((rec.spec or 0) > 0) and rec.spec or priorSpec,
										exactCrafts = exactCrafts,
										crafts = crafts,
										unlockCost = unlockCost + subUnlockExtra,
										rodCat = (rodCost > 0) and rodCat or nil,
										rodCost = rodCost,
										unlockedSpells = segUnlocked,
										outItemID = rec.i,
										ahSold = ahSold,
										surplusID = (not rec.ench and (rec.i or 0) > 0) and rec.i or nil,
										surplusUnits = unitsMade,
										surplusResaleUnit = (unitsMade > 0) and (resale / unitsMade) or 0,
										effortPerUnit = (unitsMade > 0 and failPen > 0) and (failPen / unitsMade) or 0,
										consumedSurplus = segConsumed,
										ownedUsedByID = segOwnedUsed,
										prev = prevNode,
									}
								end
							end
						end
					end
				end
			end

			-- Coupled 2-Step Same-Profession Sub-Craft Macro-Transition: (subEv: s1 -> sMid) + (ev: sMid -> s2)
			local cBucket = coupledAt[s1]
			if cBucket then
				chainScratch.priorSpec = priorSpec
				chainScratch.usedSpells = usedSpells
				chainScratch.unlockedSet = unlockedSet
				chainScratch.unlockedRods = unlockedRods
				chainScratch.priorAHSoldMap = priorAHSoldMap
				chainScratch.ownedUsedInChain = ownedUsedInChain
				chainScratch.surplusMap = surplusMap
				runCoupledTransitionsAt(s1, baseCost, prevNode, curBracketHi, dpState, chainScratch, cBucket)
			end
		end
	end

	local endSkill = targetSkill
	if dp[targetSkill] >= INF then
		if not allowPartial then
			return nil, nil
		end
		endSkill = nil
		for s = targetSkill - 1, startSkill + 1, -1 do
			if dp[s] < INF then
				endSkill = s
				break
			end
		end
		if not endSkill then
			return nil, nil
		end
	end

	local segments = {}
	local cur = nodeAt[endSkill]
	while cur do
		segments[#segments + 1] = cur
		cur = cur.prev
	end
	for i = 1, math_floor(#segments / 2) do
		local j = #segments - i + 1
		segments[i], segments[j] = segments[j], segments[i]
	end
	return segments, (endSkill ~= targetSkill) and endSkill or nil
end

local function analyzeSkillCoverage(candidates, startSkill, targetSkill)
	local covered = {}
	for i = 1, #candidates do
		local ev = candidates[i]
		local rec = ev.rec
		local aStart = math_max(startSkill, ev.effReq or rec.req or 1)
		local aEnd = math_min(targetSkill, rec.gr or 0)
		for s = aStart, aEnd - 1 do
			covered[s] = true
		end
	end
	local prefUncovered = { [startSkill] = 0 }
	local minUncov, maxUncov = nil, nil
	for s = startSkill, targetSkill - 1 do
		if not covered[s] then
			if not minUncov then minUncov = s end
			maxUncov = s
			prefUncovered[s + 1] = prefUncovered[s] + 1
		else
			prefUncovered[s + 1] = prefUncovered[s]
		end
	end
	return (minUncov == nil), prefUncovered, minUncov, maxUncov
end

local function hasFullSkillCoverage(candidates, startSkill, targetSkill)
	local isFull = analyzeSkillCoverage(candidates, startSkill, targetSkill)
	return isFull
end

local solvePathCache = {}
function MP.InvalidateSolveCache()
	solvePathCache = {}
end

local function solveProfessionPathImpl(profKey, opts)
	opts = opts or {}
	local profInfo = MP.PROFESSIONS[profKey]
	if not profInfo then return nil end

	local liveProfs = opts.liveProfs or MP.ScanPlayerProfessions()
	local charProf = liveProfs[profKey]
	local startSkill = tonumber(opts.startSkill) or (charProf and charProf.rank) or profInfo.defaultStart or 1
	local requestedTarget = tonumber(opts.targetSkill) or 300
	startSkill = math_max(1, math_min(300, math_floor(startSkill)))
	requestedTarget = math_max(1, math_min(300, math_floor(requestedTarget)))
	local targetSkill = requestedTarget

	local ctx = buildSolverContext(profKey, opts)
	local knownMaxRank = (not opts.useFullRange and charProf and charProf.learned and charProf.maxRank) or 0
	local maxSkillForLv, nextRankForLv = MP.GetMaxSkillForCharLevel(profKey, ctx.charLevel, knownMaxRank)
	local levelCapInfo = nil

	if maxSkillForLv <= 0 then
		return {
			profKey = profKey,
			profInfo = profInfo,
			startSkill = startSkill,
			targetSkill = requestedTarget,
			requestedTarget = requestedTarget,
			charLevel = ctx.charLevel,
			isAutoCharLv = ctx.isAutoCharLv,
			levelLocked = true,
			levelCapInfo = {
				charLevel = ctx.charLevel,
				requestedTarget = requestedTarget,
				cappedTarget = 0,
				nextCap = nextRankForLv and nextRankForLv.cap or 75,
				nextReqLv = nextRankForLv and nextRankForLv.rlv or (profInfo.minLv or 5),
				nextRankName = nextRankForLv and nextRankForLv.name or "Apprentice",
			},
			legacy = ctx.legacy,
			steps = {},
			shoppingList = {},
			shoppingListByLevel = {},
			totalCrafts = 0,
			totalGrossMats = 0,
			totalTrainUnlocks = 0,
			totalFavorTokens = 0,
			totalResale = 0,
			netCost = 0,
		}
	end

	if targetSkill > maxSkillForLv then
		levelCapInfo = {
			charLevel = ctx.charLevel,
			requestedTarget = requestedTarget,
			cappedTarget = maxSkillForLv,
			nextCap = nextRankForLv and nextRankForLv.cap or 300,
			nextReqLv = nextRankForLv and nextRankForLv.rlv or 60,
			nextRankName = nextRankForLv and nextRankForLv.name or "Next Rank",
		}
		targetSkill = maxSkillForLv
	end

	if startSkill >= targetSkill then
		return {
			profKey = profKey,
			profInfo = profInfo,
			startSkill = startSkill,
			targetSkill = targetSkill,
			requestedTarget = requestedTarget,
			charLevel = ctx.charLevel,
			isAutoCharLv = ctx.isAutoCharLv,
			alreadyMet = true,
			alreadyAtLevelCap = (levelCapInfo ~= nil),
			levelCapInfo = levelCapInfo,
			legacy = ctx.legacy,
			steps = {},
			shoppingList = {},
			shoppingListByLevel = {},
			totalCrafts = 0,
			totalGrossMats = 0,
			totalTrainUnlocks = 0,
			totalFavorTokens = 0,
			totalResale = 0,
			netCost = 0,
		}
	end

	local rawRecipes = MP.RECIPES[profKey] or {}
	local candidates = {}
	local evalBySpell = {}
	local rodEvalByCat = {}

	for _, rec in ipairs(rawRecipes) do
		local ev = MP.EvaluateRecipeForSolver(rec, ctx)
		if ev then
			candidates[#candidates + 1] = ev
			evalBySpell[rec.s] = ev
		end
	end
	if profKey == "enchanting" then
		for cat, rInfo in pairs(MP.ENCHANTING_RODS) do
			local rRec = MP.RECIPES_BY_SPELL[rInfo.spellID]
			if rRec then
				rodEvalByCat[cat] = evalBySpell[rInfo.spellID] or MP.EvaluateRecipeForSolver(rRec, {
					db = ctx.db, profKey = profKey, mns = ctx.mns, legacy = ctx.legacy,
					charLevel = 60, allowedSources = ALLOWED_BY_FILTER.all,
					goalMode = ctx.goalMode, sellDays = ctx.sellDays,
					applyAHCut = ctx.applyAHCut, includeVendorSell = ctx.includeVendorSell,
					subCraftMode = ctx.subCraftMode, subCraftOverrides = ctx.subCraftOverrides,
					trainerCosts = ctx.trainerCosts, playerFaction = ctx.playerFaction,
					favorUnitPrice = ctx.favorUnitPrice, standingID = 8,
				})
			end
		end
	end

	local segments, partialCap = nil, nil
	local usedFallbackFilter = false
	local fallbackRange = nil
	local knownCapSkill = nil
	local primaryFull, primaryPrefUncov, minUncov, maxUncov = analyzeSkillCoverage(candidates, startSkill, targetSkill)

	if ctx.recipeFilter == "known_only" then
		segments, partialCap = solveDPWithCandidates(candidates, evalBySpell, rodEvalByCat, startSkill, targetSkill, ctx, true)
		if segments and partialCap then
			targetSkill = partialCap
			knownCapSkill = partialCap
		end
	elseif primaryFull then
		segments = solveDPWithCandidates(candidates, evalBySpell, rodEvalByCat, startSkill, targetSkill, ctx, false)
	end

	if not segments and ctx.recipeFilter ~= "all" then
		local origAllowed = ctx.allowedSources
		local primaryCandidates = candidates
		local primaryBySpell = evalBySpell
		local fbOrder = { "trainer_vendor", "with_ah", "all" }
		for _, fbKey in ipairs(fbOrder) do
			if fbKey ~= ctx.recipeFilter then
				ctx.allowedSources = ALLOWED_BY_FILTER[fbKey]
				ctx.subEvCache = {}
				local mergedCands = {}
				local mergedBySpell = {}
				for i = 1, #primaryCandidates do
					local pev = primaryCandidates[i]
					mergedCands[i] = pev
					mergedBySpell[pev.rec.s] = pev
				end
				for _, rec in ipairs(rawRecipes) do
					if not primaryBySpell[rec.s] then
						local ev = MP.EvaluateRecipeForSolver(rec, ctx)
						if ev then
							ev.isFallbackBridge = true
							mergedCands[#mergedCands + 1] = ev
							mergedBySpell[rec.s] = ev
						end
					end
				end
				if hasFullSkillCoverage(mergedCands, startSkill, targetSkill) then
					-- Prefer scoped bridging on transitions covering uncovered skills so unrelated levels respect the chosen filter
					if not primaryFull and minUncov ~= nil then
						segments = solveDPWithCandidates(mergedCands, mergedBySpell, rodEvalByCat, startSkill, targetSkill, ctx, false, primaryPrefUncov)
						if segments then
							usedFallbackFilter = fbKey
							fallbackRange = { from = minUncov, to = maxUncov + 1, filterKey = fbKey }
							candidates = mergedCands
							evalBySpell = mergedBySpell
							break
						end
					end
					-- Unscoped fallback if spec-locked or cost-blocked path prevented reaching the gap
					for i = 1, #mergedCands do mergedCands[i].isFallbackBridge = nil end
					segments = solveDPWithCandidates(mergedCands, mergedBySpell, rodEvalByCat, startSkill, targetSkill, ctx, false)
					if segments then
						usedFallbackFilter = fbKey
						candidates = mergedCands
						evalBySpell = mergedBySpell
						break
					end
				end
			end
		end
		ctx.allowedSources = origAllowed
	end

	if not segments then
		return {
			profKey = profKey,
			profInfo = profInfo,
			startSkill = startSkill,
			targetSkill = targetSkill,
			requestedTarget = requestedTarget,
			charLevel = ctx.charLevel,
			isAutoCharLv = ctx.isAutoCharLv,
			levelCapInfo = levelCapInfo,
			unreachable = true,
			legacy = ctx.legacy,
			steps = {},
			shoppingList = {},
			shoppingListByLevel = {},
			totalCrafts = 0,
			totalGrossMats = 0,
			totalTrainUnlocks = 0,
			totalFavorTokens = 0,
			totalResale = 0,
			netCost = 0,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- Trainer locations for rank milestones (Apprentice 75, Journeyman 150, Expert 225, Artisan 300)
	local CAP_TRAINERS = {
		A = { short = "Capital Cities", detail = "Capital City Trainers (Stormwind / Ironforge / Darnassus)" },
		H = { short = "Capital Cities", detail = "Capital City Trainers (Orgrimmar / Undercity / Thunder Bluff)" },
	}
	local MINING_TRAINERS = {
		A = { short = "Capital Cities", detail = "Any Capital Mining Trainer (Ironforge / Stormwind)" },
		H = { short = "Capital Cities", detail = "Any Capital Mining Trainer (Orgrimmar / Undercity / Thunder Bluff)" },
	}
	MP.RANK_TRAINERS = MP.RANK_TRAINERS or {
		alchemy = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Ainethil, Darnassus (54.9, 24.0)", detail = "Ainethil - Darnassus, Craftsmen's Terrace (54.9, 24.0)" },
				H = { short = "Doctor Herbert Halsey, Undercity (47.8, 73.3)", detail = "Doctor Herbert Halsey - Undercity, Apothecarium (47.8, 73.3)" },
			},
			[300] = {
				A = { short = "Kylanna Windwhisper, Feralas (32.6, 43.8)", detail = "Kylanna Windwhisper - Feralas, Feathermoon Stronghold (32.6, 43.8)" },
				H = { short = "Rogvar, Swamp of Sorrows (48.5, 55.9)", detail = "Rogvar - Swamp of Sorrows, Stonard (48.5, 55.9)" },
			},
		},
		blacksmithing = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Bengus Deepforge, Ironforge (52.5, 41.5)", detail = "Bengus Deepforge - Ironforge, The Great Forge (52.5, 41.5)" },
				H = { short = "Saru Steelfury, Orgrimmar (82.3, 23.0)", detail = "Saru Steelfury - Orgrimmar, Valley of Honor (82.3, 23.0)" },
			},
			[300] = {
				AH = { short = "Brikk Keencraft, Booty Bay (29.0, 75.6)", detail = "Brikk Keencraft - Stranglethorn Vale, Booty Bay (29.0, 75.6)" },
			},
		},
		enchanting = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Kitta Firewind, Elwynn Forest (64.9, 70.7)", detail = "Kitta Firewind - Elwynn Forest, Tower of Azora (64.9, 70.7)" },
				H = { short = "Hgarth, Stonetalon Mtns (49.2, 57.2)", detail = "Hgarth - Stonetalon Mountains, Sun Rock Retreat (49.2, 57.2)" },
			},
			[300] = {
				AH = { short = "Annora, Uldaman (Badlands)", detail = "Annora - Uldaman (inside dungeon, Badlands)" },
			},
		},
		engineering = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Springspindle Fizzlegear, Ironforge (68.5, 43.5)", detail = "Springspindle Fizzlegear - Ironforge, Tinker Town (68.5, 43.5)" },
				H = { short = "Roxxik, Orgrimmar (76.2, 25.2)", detail = "Roxxik - Orgrimmar, Valley of Honor (76.2, 25.2)" },
			},
			[300] = {
				AH = { short = "Buzzek Bracketswing, Gadgetzan (52.3, 27.7)", detail = "Buzzek Bracketswing - Tanaris, Gadgetzan (52.3, 27.7)" },
			},
		},
		leatherworking = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Telonis, Darnassus (64.4, 21.5)", detail = "Telonis - Darnassus, Craftsmen's Terrace (64.4, 21.5)" },
				H = { short = "Una, Thunder Bluff (41.5, 42.6)", detail = "Una - Thunder Bluff, Middle Rise (41.5, 42.6)" },
			},
			[300] = {
				A = { short = "Drakk Stonehand, The Hinterlands (13.4, 43.5)", detail = "Drakk Stonehand - The Hinterlands, Aerie Peak (13.4, 43.5)" },
				H = { short = "Hahrana Ironhide, Feralas (74.4, 43.1)", detail = "Hahrana Ironhide - Feralas, Camp Mojache (74.4, 43.1)" },
			},
		},
		tailoring = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Georgio Bolero, Stormwind (53.1, 81.3)", detail = "Georgio Bolero - Stormwind City, Mage Quarter (53.1, 81.3)" },
				H = { short = "Josef Gregorian, Undercity (70.8, 30.7)", detail = "Josef Gregorian - Undercity, Magic Quarter (70.8, 30.7)" },
			},
			[300] = {
				A = { short = "Timothy Worthington, Theramore (66.2, 51.8)", detail = "Timothy Worthington - Dustwallow Marsh, Theramore Isle (66.2, 51.8)" },
				H = { short = "Daryl Stack, Tarren Mill (63.7, 20.8)", detail = "Daryl Stack - Hillsbrad Foothills, Tarren Mill (63.7, 20.8)" },
			},
		},
		mining = {
			[75]  = MINING_TRAINERS,
			[150] = MINING_TRAINERS,
			[225] = MINING_TRAINERS,
			[300] = MINING_TRAINERS,
		},
		cooking = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Shandrina, Ashenvale (49.5, 67.1)", detail = "Shandrina - Ashenvale, Silverwind Refuge (49.5, 67.1) [Book]" },
				H = { short = "Wulan, Desolace (26.2, 69.7)", detail = "Wulan - Desolace, Shadowprey Village (26.2, 69.7) [Book]" },
			},
			[300] = {
				AH = { short = "Dirge Quikcleave, Gadgetzan (52.6, 28.1)", detail = "Dirge Quikcleave - Tanaris, Gadgetzan (52.6, 28.1) [Quest: Clamlette Surprise]" },
			},
		},
		firstaid = {
			[75]  = CAP_TRAINERS,
			[150] = CAP_TRAINERS,
			[225] = {
				A = { short = "Deneb Walker, Arathi Highlands (27.0, 58.8)", detail = "Deneb Walker - Arathi Highlands, Stromgarde Keep (27.0, 58.8) [Book]" },
				H = { short = "Balai Lok'Wein, Dustwallow Marsh (36.5, 30.4)", detail = "Balai Lok'Wein - Dustwallow Marsh, Brackenwall Village (36.5, 30.4) [Book]" },
			},
			[300] = {
				A = { short = "Dr. Gustaf VanHowzen, Theramore (67.8, 49.0)", detail = "Doctor Gustaf VanHowzen - Dustwallow Marsh, Theramore Isle (67.8, 49.0) [Quest: Triage]" },
				H = { short = "Dr. Gregory Victor, Hammerfall (73.4, 36.9)", detail = "Doctor Gregory Victor - Arathi Highlands, Hammerfall (73.4, 36.9) [Quest: Triage]" },
			},
		},
	}

	function MP.GetRankTrainerInfo(pKey, rankCap, playerFaction)
		local pTbl = MP.RANK_TRAINERS and MP.RANK_TRAINERS[pKey]
		local entry = pTbl and pTbl[rankCap]
		if not entry then return nil end
		local facCode = (playerFaction == "Alliance" or playerFaction == "A") and "A"
			or ((playerFaction == "Horde" or playerFaction == "H") and "H") or nil
		if entry.AH then
			return {
				short = entry.AH.short,
				detail = entry.AH.detail,
				faction = "AH",
				all = entry,
			}
		end
		local chosen = (facCode and entry[facCode]) or nil
		if chosen then
			local otherCode = (facCode == "A") and "H" or "A"
			return {
				short = chosen.short,
				detail = chosen.detail,
				faction = facCode,
				otherDetail = entry[otherCode] and entry[otherCode].detail or nil,
				otherFaction = otherCode,
				all = entry,
			}
		end
		local aShort = entry.A and ("[A] " .. entry.A.short) or nil
		local hShort = entry.H and ("[H] " .. entry.H.short) or nil
		local aDet = entry.A and ("[A] " .. entry.A.detail) or nil
		local hDet = entry.H and ("[H] " .. entry.H.detail) or nil
		return {
			short = (aShort and hShort) and (aShort .. " / " .. hShort) or (aShort or hShort or ""),
			detail = (aDet and hDet) and (aDet .. " / " .. hDet) or (aDet or hDet or ""),
			faction = "BOTH",
			all = entry,
		}
	end

	-- Build Chronological Steps (Rank Milestones + Rods + Same-Prof Sub-Crafts + Self-Feeding Pool)

	local pendingRanks = {}
	for _, rk in ipairs(profInfo.ranks or {}) do
		if targetSkill > (rk.cap - 75) and knownMaxRank < rk.cap then
			if not (rk.cap == 75 and startSkill > 1) then
				pendingRanks[#pendingRanks + 1] = {
					cap = rk.cap,
					triggerAt = math_max(startSkill, rk.maxNeed),
					trainAt = rk.trainAt,
					rlv = rk.rlv or 1,
					name = rk.name,
					cost = rk.cost or 0,
					bookID = rk.bookID,
					inserted = false,
				}
			end
		end
	end

	local steps = {}
	local stepIndex = 0
	local craftedPool = {}       -- [itemID] = { { avail = N, step = stepTable }, ... }
	local ahSoldSoFar = {}       -- [itemID] = cumulative AH units sold across steps
	local unlockedInSteps = {}   -- [spellID] = true once unlockCost is charged on a step
	local scrollNeedList = {}
	local rodRecipesInserted = {}
	local ownedIntermSavings = 0
	local ownedPoolByID = {}
	local ownedPoolByName = {}
	local ownedPoolResolvedID = {}
	if ctx.useOwned then
		if ctx.ownedByID then
			for k, v in pairs(ctx.ownedByID) do
				local id = tonumber(k)
				local q = tonumber(v) or 0
				if id and id > 0 and q > 0 then
					ownedPoolByID[id] = q
				end
			end
		end
		if not ctx._ownedIDsExclusive then
			for k, v in pairs(ctx.ownedCounts or {}) do
				local q = tonumber(v) or 0
				if q > 0 then
					if type(k) == "number" then
						if not ownedPoolByID[k] then ownedPoolByID[k] = q end
					else
						ownedPoolByName[k] = q
					end
				end
			end
		end
	end

	local function getPoolOwned(itemID, itemName)
		if not ctx.useOwned or not itemID or itemID <= 0 then return 0 end
		if not ownedPoolResolvedID[itemID] then
			ownedPoolResolvedID[itemID] = true
			local base = getOwnedQtyByID(itemID, ctx)
			if base == 0 and not ctx._ownedIDsExclusive then
				local nm = itemName or MP.ItemName(itemID)
				if nm and ownedPoolByName[nm] then
					base = ownedPoolByName[nm]
					ownedPoolByName[nm] = nil
				end
			end
			ownedPoolByID[itemID] = base
		end
		return ownedPoolByID[itemID] or 0
	end

	local function consumePoolOwned(itemID, itemName, qty)
		if qty <= 0 or not itemID or itemID <= 0 then return end
		local cur = getPoolOwned(itemID, itemName)
		ownedPoolByID[itemID] = math_max(0, cur - qty)
	end

	local function pushMilestoneStep(atSkill, title, subSource, unlockCopper, extraItemID, reqLv, rankMeta)
		stepIndex = stepIndex + 1
		steps[stepIndex] = {
			stepNum = stepIndex,
			isMilestone = true,
			s1 = atSkill,
			s2 = atSkill,
			reqLv = reqLv or 1,
			rankCap = rankMeta and rankMeta.cap or nil,
			trainAt = rankMeta and rankMeta.trainAt or nil,
			trainerInfo = rankMeta and rankMeta.trainerInfo or nil,
			trainerLocation = rankMeta and rankMeta.trainerInfo and rankMeta.trainerInfo.detail or nil,
			skillRange = tostring(atSkill),
			sortSkill = atSkill - 0.1,
			name = title,
			itemID = extraItemID or 0,
			sourceLabel = subSource,
			crafts = 0,
			chanceRange = (reqLv and reqLv > 1) and ("Lv " .. tostring(reqLv)) or "—",
			unlockCost = unlockCopper,
			grossMats = 0,
			resale = 0,
			ahResaleTotal = nil,
			vendorResaleTotal = nil,
			sellChannel = "-",
			dailySold = nil,
			netCost = unlockCopper,
		}
		if extraItemID and extraItemID > 0 and unlockCopper > 0 then
			local sc = {
				itemID = extraItemID,
				qty = 1,
				unitCost = unlockCopper,
				source = subSource or "Vendor Book",
				isVendor = true,
				usedIn = title,
			}
			steps[stepIndex].scrollNeed = sc
			scrollNeedList[#scrollNeedList + 1] = sc
		end
	end

	-- Split any segment that crosses a hard Rank Cap (75 / 150 / 225) at rk.triggerAt
	local workSegments = {}
	for _, seg in ipairs(segments) do
		local curS1 = seg.s1
		local remRod = seg.rodCat
		local rec = seg.ev.rec
		local effReq = seg.ev.effReq

		for _, rk in ipairs(pendingRanks) do
			if rk.triggerAt > curS1 and rk.triggerAt < seg.s2 then
				local sumInv = 0
				for s = curS1, rk.triggerAt - 1 do
					local p = MP.GetSkillUpChance(rec, s, ctx.legacy.overtime, effReq)
					sumInv = sumInv + ((p > 0) and (1.0 / p) or 1.0)
				end
				local c1 = math_max(rk.triggerAt - curS1, math_ceil(sumInv - 1e-9))
				workSegments[#workSegments + 1] = {
					s1 = curS1,
					s2 = rk.triggerAt,
					ev = seg.ev,
					crafts = c1,
					exactCrafts = sumInv,
					rodCat = remRod,
				}
				curS1 = rk.triggerAt
				remRod = nil
			end
		end

		local remInv = 0
		for s = curS1, seg.s2 - 1 do
			local p = MP.GetSkillUpChance(rec, s, ctx.legacy.overtime, effReq)
			remInv = remInv + ((p > 0) and (1.0 / p) or 1.0)
		end
		local cRem = (curS1 == seg.s1) and seg.crafts or math_max(seg.s2 - curS1, math_ceil(remInv - 1e-9))
		workSegments[#workSegments + 1] = {
			s1 = curS1,
			s2 = seg.s2,
			ev = seg.ev,
			crafts = cRem,
			exactCrafts = remInv,
			rodCat = remRod,
		}
	end

	-- Consumes available units of `itemID` from `craftedPool`, updating upstream step resale & reuse notes
	local function takeFromCraftedPool(itemID, neededQty, unitSavedVal, targetPrepStep, rgIsSubCraft, consumerName, consumerStepNumGuess, consumerToken, outReuseLinks)
		local taken = 0
		local poolList = craftedPool[itemID]
		if not (poolList and #poolList > 0 and neededQty > 0) then return 0 end
		for _, pEntry in ipairs(poolList) do
			if taken >= neededQty then break end
			if pEntry.avail > 0 then
				local prevStep = pEntry.step
				local maxTake = 0
				if targetPrepStep ~= nil then
					if prevStep == targetPrepStep then
						maxTake = pEntry.avail
					end
				elseif prevStep.isSubCraftStep then
					maxTake = pEntry.avail
				else
					-- Skill-up step: compute exact marginal resale per unit so we NEVER steal profitable AH-sold outputs
					local availAH = math_min(pEntry.avail, prevStep.ahSold or 0)
					local availNonAH = math_max(0, pEntry.avail - availAH)
					local vendUnit = (ctx.includeVendorSell and prevStep.ev and prevStep.ev.vendorUnit) or 0
					if (prevStep.vendorSold or 0) == 0 then vendUnit = 0 end
					local ahUnit = (ctx.goalMode == "ah_max")
						and math_max(vendUnit, (prevStep.ev and (prevStep.ev.afterCutUnit or prevStep.ev.ahNetUnit)) or 0)
						or ((prevStep.ev and prevStep.ev.ahNetUnit) or 0)
					if availNonAH > 0 and (unitSavedVal >= vendUnit or ((prevStep.ahSold or 0) == 0 and rgIsSubCraft)) then
						maxTake = maxTake + availNonAH
					end
					if availAH > 0 and unitSavedVal >= ahUnit then
						maxTake = maxTake + availAH
					end
				end

				if maxTake > 0 then
					local take = math_min(maxTake, neededQty - taken)
					pEntry.avail = pEntry.avail - take
					taken = taken + take

					prevStep.unitsKeptForLater = (prevStep.unitsKeptForLater or 0) + take
					prevStep.keptValueSaved = (prevStep.keptValueSaved or 0) + (take * unitSavedVal)
					prevStep.keptForSteps = prevStep.keptForSteps or {}
					local matchedKs = nil
					for _, ks in ipairs(prevStep.keptForSteps) do
						local match = (consumerToken and ks._token == consumerToken)
							or (not consumerToken and not ks._token and ks.name == consumerName)
						if match then
							ks.qty = ks.qty + take
							ks.savedCopper = ks.savedCopper + (take * unitSavedVal)
							matchedKs = ks
							break
						end
					end
					if not matchedKs then
						matchedKs = {
							_token = consumerToken,
							stepNum = consumerStepNumGuess,
							name = consumerName,
							qty = take,
							savedCopper = take * unitSavedVal,
						}
						prevStep.keptForSteps[#prevStep.keptForSteps + 1] = matchedKs
					end
					if outReuseLinks and not matchedKs._linked then
						matchedKs._linked = true
						outReuseLinks[#outReuseLinks + 1] = matchedKs
					end

					local sellableLeft = math_max(0, prevStep.unitsMade - prevStep.unitsKeptForLater)
					local prevID = prevStep.itemID or 0
					local oldAH = prevStep.ahSold or 0
					local priorBeforePrev = math_max(0, (ahSoldSoFar[prevID] or 0) - oldAH)
					local newResale, newAHSold, newVendSold, newResaleTag = computeOutputsResale(prevStep.ev, sellableLeft, ctx, priorBeforePrev)
					if prevID > 0 then
						ahSoldSoFar[prevID] = priorBeforePrev + newAHSold
					end
					prevStep.resale = newResale
					prevStep.ahSold = newAHSold
					prevStep.vendorSold = newVendSold
					if prevStep.unitsKeptForLater > 0 and sellableLeft == 0 then
						prevStep.resaleTag = string.format("Reused (%s)", consumerName)
					elseif prevStep.unitsKeptForLater > 0 then
						prevStep.resaleTag = string.format("%s (%dx) + %dx Reused", newResaleTag, sellableLeft, prevStep.unitsKeptForLater)
					else
						prevStep.resaleTag = newResaleTag
					end
					prevStep.netCost = prevStep.unlockCost + prevStep.grossMats - prevStep.resale
				end
			end
		end
		return taken
	end

	-- Pure side-effect-free upper-bound cost estimate for a same-profession sub-craft batch
	-- (including unlearned unlock fees & nested sub-craft buy-vs-craft decisions up to depth 3)
	local function estimateSubCraftTotalCost(subEv, batches, curDepth, willPayUnlock)
		local total = (willPayUnlock and not subEv.known and not unlockedInSteps[subEv.rec.s]) and (subEv.baseUnlockCost or 0) or 0
		for _, srg in ipairs(subEv.reagentDetails or {}) do
			local need = srg.qtyPerCraft * batches
			if srg.sameProfSubEv and (curDepth + 1) <= 3 then
				local cSub = srg.sameProfSubEv
				local cYield = math_max(1, cSub.rec.c or 1)
				local cBatches = math_ceil(need / cYield)
				local cForce = (ctx.subCraftMode == "all_sub") or (ctx.subCraftOverrides and ctx.subCraftOverrides[srg.itemID] == "craft")
				local cCraft = estimateSubCraftTotalCost(cSub, cBatches, curDepth + 1, true)
				local cBuy = (srg.ahUnitCost and srg.ahUnitCost > 0) and (need * srg.ahUnitCost) or nil
				if not cForce and cBuy and cCraft >= cBuy then
					total = total + cBuy
				else
					total = total + cCraft
				end
			elseif srg.sameProfSubEv and srg.ahUnitCost and srg.ahUnitCost > 0 then
				total = total + need * srg.ahUnitCost
			else
				total = total + need * (srg.unitCost or 0)
			end
		end
		return total
	end

	-- Recursively crafts any missing same-profession sub-craft reagents BEFORE the consumer step,
	-- merging into the immediately preceding step when it is the same recipe or adding a Sub-Craft prep step!
	local function ensureRecipeReagentsAndCost(ev, craftsCount, atSkill, consumerName, depth)
		depth = (depth or 0) + 1
		local stepGross = 0
		local consumedFromSteps = {}
		local consumedFromOwnedInterm = {}
		local boughtDirectOnAH = {}
		local consumerToken = {}
		local reuseLinks = {}

		for _, rg in ipairs(ev.reagentDetails or {}) do
			local totalNeed = rg.qtyPerCraft * craftsCount
			local unitSavedVal = rg.unitCost or 0
			local fromPool = takeFromCraftedPool(rg.itemID, totalNeed, unitSavedVal, nil, rg.isSubCraft and true or false, consumerName, stepIndex + 1, consumerToken, reuseLinks)

			local remNeed = totalNeed - fromPool
			local fromOwnedInterm = 0
			if remNeed > 0 and rg.sameProfSubEv and depth <= 3 and ctx.useOwned then
				local availOwn = getPoolOwned(rg.itemID)
				if availOwn > 0 then
					fromOwnedInterm = math_min(remNeed, availOwn)
					consumePoolOwned(rg.itemID, nil, fromOwnedInterm)
					remNeed = remNeed - fromOwnedInterm
					ownedIntermSavings = ownedIntermSavings + (fromOwnedInterm * rg.unitCost)
					consumedFromOwnedInterm[rg.itemID] = fromOwnedInterm
				end
			end

			if remNeed > 0 and rg.sameProfSubEv and (rg.sameProfSubEv.effReq or 1) <= (atSkill or 300) and depth <= 3 then
				local subEv = rg.sameProfSubEv
				local subRec = subEv.rec
				local subYield = math_max(1, subRec.c or 1)
				local subBatches = math_ceil(remNeed / subYield)
				local subUnits = math_floor(subBatches * subEv.yieldPerCraft + 1e-9)

				local forceSub = (ctx.subCraftMode == "all_sub") or (ctx.subCraftOverrides and ctx.subCraftOverrides[rg.itemID] == "craft")
				local prevStep = steps[stepIndex]
				local canMergeIntoPrev = prevStep and not prevStep.isMilestone and not prevStep.isRod and prevStep.spellID == subRec.s
				if canMergeIntoPrev and not prevStep.isSubCraftStep and (prevStep.ahSold or 0) > 0 then
					local prevAHU = (ctx.goalMode == "ah_max")
						and ((prevStep.ev and (prevStep.ev.afterCutUnit or prevStep.ev.ahNetUnit)) or 0)
						or ((prevStep.ev and prevStep.ev.ahNetUnit) or 0)
					if prevAHU > (rg.unitCost or 0) then
						canMergeIntoPrev = false
					end
				end

				-- Buy-vs-Craft Total-Batch Guard BEFORE mutating steps/pools via recursion!
				local estSubTotal = estimateSubCraftTotalCost(subEv, subBatches, depth, not canMergeIntoPrev)
				local directBuyCost = (rg.ahUnitCost and rg.ahUnitCost > 0) and (remNeed * rg.ahUnitCost) or nil
				local skipSubCraft = (not forceSub) and (directBuyCost ~= nil) and (estSubTotal >= directBuyCost)

				if not skipSubCraft then
					-- First recursively ensure any sub-reagents needed by `subEv`
					local subGross, subConsumedSteps, subConsumedOwned, subBoughtDirect, subReuseLinks = ensureRecipeReagentsAndCost(subEv, subBatches, atSkill, subRec.n, depth)

					if canMergeIntoPrev and steps[stepIndex] == prevStep then
						for _, ks in ipairs(subReuseLinks or {}) do
							ks.destStep = prevStep
						end
						-- Merge extra prep crafts directly into the immediately preceding step of the same recipe!
						prevStep.skillCrafts = prevStep.skillCrafts or prevStep.crafts
						prevStep.prepCrafts = (prevStep.prepCrafts or 0) + subBatches
						prevStep.crafts = prevStep.crafts + subBatches
						prevStep.unitsMade = (prevStep.unitsMade or 0) + subUnits
						prevStep.grossMats = (prevStep.grossMats or 0) + subGross
						prevStep.consumedFromSteps = prevStep.consumedFromSteps or {}
						for k, v in pairs(subConsumedSteps) do
							prevStep.consumedFromSteps[k] = (prevStep.consumedFromSteps[k] or 0) + v
						end
						prevStep.consumedFromOwnedInterm = prevStep.consumedFromOwnedInterm or {}
						for k, v in pairs(subConsumedOwned) do
							prevStep.consumedFromOwnedInterm[k] = (prevStep.consumedFromOwnedInterm[k] or 0) + v
						end
						if subBoughtDirect then
							prevStep.boughtDirectOnAH = prevStep.boughtDirectOnAH or {}
							for k, v in pairs(subBoughtDirect) do
								if v then prevStep.boughtDirectOnAH[k] = true end
							end
						end
						-- Add newly made subUnits to prevStep's craftedPool entry, then consume `remNeed`
						local poolList = craftedPool[subRec.i]
						local prevEntry = poolList and poolList[#poolList]
						if prevEntry and prevEntry.step == prevStep then
							prevEntry.avail = prevEntry.avail + subUnits
						else
							craftedPool[subRec.i] = craftedPool[subRec.i] or {}
							craftedPool[subRec.i][#craftedPool[subRec.i] + 1] = { avail = subUnits, step = prevStep }
						end
						local extraTaken = takeFromCraftedPool(rg.itemID, remNeed, unitSavedVal, prevStep, true, consumerName, stepIndex + 1, consumerToken, reuseLinks)
						fromPool = fromPool + extraTaken
						remNeed = remNeed - extraTaken
					else
						-- Emit an explicit Sub-Craft Prep step right before the consumer step
						local subUnlock, subFavor = 0, 0
						local subScrollNeed = nil
						if not subEv.known and not unlockedInSteps[subRec.s] then
							subUnlock = subEv.baseUnlockCost or 0
							subFavor = subEv.baseUnlockFavor or 0
							unlockedInSteps[subRec.s] = true
							if (subUnlock > 0 or subFavor > 0) and subRec.ri and subRec.ri > 0 and (subRec.src == "vendor" or subRec.src == "ah" or subRec.src == "camp") then
								subScrollNeed = {
									itemID = subRec.ri,
									qty = 1,
									unitCost = subUnlock,
									source = subEv.unlockLabel,
									isVendor = (subRec.src == "camp") or (subRec.src == "vendor" and not subEv.scrollViaAH),
									favorTokens = subEv.favorTokens,
									usedIn = subRec.n,
								}
								scrollNeedList[#scrollNeedList + 1] = subScrollNeed
							end
						end

						local subOutID = subRec.i or 0
						local priorSubAH = (subOutID > 0) and (ahSoldSoFar[subOutID] or 0) or 0
						local subResale, subAHSold, subVendSold, subResTag = computeOutputsResale(subEv, subUnits, ctx, priorSubAH)
						if subOutID > 0 and subAHSold > 0 then
							ahSoldSoFar[subOutID] = priorSubAH + subAHSold
						end

						stepIndex = stepIndex + 1
						local subStepObj = {
							stepNum = stepIndex,
							scrollNeed = subScrollNeed,
							isMilestone = false,
							isSubCraftStep = true,
							spellID = subRec.s,
							itemID = subOutID,
							s1 = atSkill,
							s2 = atSkill,
							skillRange = tostring(atSkill),
							sortSkill = atSkill - 0.02,
							name = "Sub-Craft: " .. subRec.n,
							rawRecipeName = subRec.n,
							sourceLabel = (subUnlock > 0 or subFavor > 0) and subEv.unlockLabel or "Sub-Craft",
							srcType = subRec.src,
							crafts = subBatches,
							skillCrafts = 0,
							prepCrafts = subBatches,
							exactCrafts = subBatches,
							unitsMade = subUnits,
							unitsKeptForLater = 0,
							keptValueSaved = 0,
							chanceStart = 0,
							chanceEnd = 0,
							chanceRange = "Prep",
							unlockCost = subUnlock,
							unlockFavor = subFavor,
							grossMats = subGross,
							resale = subResale,
							standaloneResale = subResale,
							standaloneTag = subResTag,
							standaloneNetCost = subUnlock + subGross - subResale,
							ahSold = subAHSold,
							vendorSold = subVendSold,
							resaleTag = subResTag,
							dailySold = subEv.canAH and subEv.dailySold or nil,
							listed = subEv.canAH and subEv.listed or nil,
							demand = subEv.demand,
							demandScore = subEv.demand and subEv.demand.demandScore or nil,
							heatBadge = subEv.demand and subEv.demand.heatBadge or nil,
							netCost = subUnlock + subGross - subResale,
							ev = subEv,
							rec = subRec,
							reagentDetails = subEv.reagentDetails,
							consumedFromSteps = subConsumedSteps,
							consumedFromOwnedInterm = subConsumedOwned,
							boughtDirectOnAH = subBoughtDirect,
						}
						steps[stepIndex] = subStepObj
						for _, ks in ipairs(subReuseLinks or {}) do
							ks.destStep = subStepObj
						end
						craftedPool[subOutID] = craftedPool[subOutID] or {}
						craftedPool[subOutID][#craftedPool[subOutID] + 1] = { avail = subUnits, step = subStepObj }

						local extraTaken = takeFromCraftedPool(rg.itemID, remNeed, unitSavedVal, subStepObj, true, consumerName, stepIndex + 1, consumerToken, reuseLinks)
						fromPool = fromPool + extraTaken
						remNeed = remNeed - extraTaken
					end
				end
			end

			if remNeed > 0 then
				local effUnitCost = rg.unitCost or 0
				if rg.sameProfSubEv and rg.ahUnitCost and rg.ahUnitCost > 0 then
					effUnitCost = rg.ahUnitCost
					boughtDirectOnAH[rg.itemID] = true
				end
				stepGross = stepGross + remNeed * effUnitCost
			end
			if fromPool > 0 then
				consumedFromSteps[rg.itemID] = fromPool
			end
		end

		return stepGross, consumedFromSteps, consumedFromOwnedInterm, boughtDirectOnAH, reuseLinks
	end

	for _, seg in ipairs(workSegments) do
		local ev = seg.ev
		local rec = ev.rec

		-- Insert any Rank Training milestone needed at this exact skill cap boundary (1 / 75 / 150 / 225)
		for _, rk in ipairs(pendingRanks) do
			if not rk.inserted and seg.s2 > rk.triggerAt and seg.s1 >= rk.triggerAt then
				local bookCost = rk.cost
				if rk.bookID then
					bookCost = math_floor(bookCost * ctx.legacy.vendorMult + 0.5)
				end
				local extraNotes = {}
				if rk.trainAt and rk.trainAt < rk.triggerAt then
					extraNotes[#extraNotes + 1] = "skill " .. tostring(rk.trainAt)
				end
				if (rk.rlv or 1) > 1 then
					extraNotes[#extraNotes + 1] = "Lv " .. tostring(rk.rlv)
				end
				local noteStr = (#extraNotes > 0) and (" (" .. table.concat(extraNotes, ", ") .. ")") or ""
				local rankSubSrc = rk.bookID and ("Vendor (" .. (formatSourceCoin(ctx.mns, bookCost) or "Book") .. ")") or "Trainer Rank"
				local tInfo = MP.GetRankTrainerInfo and MP.GetRankTrainerInfo(profKey, rk.cap, ctx.playerFaction) or nil
				local locSuffix = (tInfo and tInfo.short and tInfo.short ~= "") and (" - " .. tInfo.short) or ""
				pushMilestoneStep(rk.triggerAt, "Train " .. rk.name .. " — Cap " .. rk.cap .. noteStr .. locSuffix, rankSubSrc, bookCost, rk.bookID, rk.rlv, {
					cap = rk.cap,
					trainAt = rk.trainAt,
					trainerInfo = tInfo,
				})
				rk.inserted = true
			end
		end

		-- Insert Enchanting Runed Rod milestone if triggered on this segment
		if seg.rodCat and not rodRecipesInserted[seg.rodCat] then
			rodRecipesInserted[seg.rodCat] = true
			local rodMeta = MP.ENCHANTING_RODS[seg.rodCat]
			local rEv = rodEvalByCat[seg.rodCat]
			if rodMeta and rEv then
				local rUnlock = (rEv.known or unlockedInSteps[rEv.rec.s]) and 0 or rEv.baseUnlockCost
				unlockedInSteps[rEv.rec.s] = true
				local rodGross, rodConsumedSteps, rodConsumedOwned, rodBoughtDirect, rodReuseLinks = ensureRecipeReagentsAndCost(rEv, 1, seg.s1, rodMeta.name, 1)
				stepIndex = stepIndex + 1
				local rodStepObj = {
					stepNum = stepIndex,
					isRod = true,
					spellID = rodMeta.spellID,
					itemID = rodMeta.itemID,
					s1 = seg.s1,
					s2 = seg.s1,
					skillRange = tostring(seg.s1),
					sortSkill = seg.s1 - 0.05,
					name = "Craft Tool: " .. rodMeta.name,
					rawRecipeName = rodMeta.name,
					sourceLabel = rEv.unlockLabel,
					crafts = 1,
					chanceRange = "Tool",
					unlockCost = rUnlock,
		grossMats = rodGross,
					resale = 0,
					ahResaleTotal = nil,
					vendorResaleTotal = nil,
					sellChannel = "-",
					dailySold = nil,
					netCost = rUnlock + rodGross,
					reagentDetails = rEv.reagentDetails,
					consumedFromSteps = rodConsumedSteps,
					consumedFromOwnedInterm = rodConsumedOwned,
					boughtDirectOnAH = rodBoughtDirect,
					ev = rEv,
					rec = rEv.rec,
				}
				steps[stepIndex] = rodStepObj
				for _, ks in ipairs(rodReuseLinks or {}) do
					ks.destStep = rodStepObj
				end
				if rUnlock > 0 and rEv.rec.ri and rEv.rec.ri > 0 then
					local sc = {
						itemID = rEv.rec.ri,
						qty = 1,
						unitCost = rUnlock,
						source = rEv.unlockLabel,
						isVendor = (rEv.rec.src == "vendor"),
						usedIn = rodMeta.name,
					}
					steps[stepIndex].scrollNeed = sc
					scrollNeedList[#scrollNeedList + 1] = sc
				end
			end
		end

		-- Compute unlock cost once per unique recipe + prerequisite chain
		local segUnlockCost, segUnlockFavor = 0, 0
		local segScrollNeed = nil
		if not ev.known and not unlockedInSteps[rec.s] then
			segUnlockCost = segUnlockCost + (ev.baseUnlockCost or 0)
			segUnlockFavor = segUnlockFavor + (ev.baseUnlockFavor or 0)
			unlockedInSteps[rec.s] = true
			if ((ev.baseUnlockCost or 0) > 0 or (ev.baseUnlockFavor or 0) > 0) and rec.ri and rec.ri > 0 and (rec.src == "vendor" or rec.src == "ah" or rec.src == "camp") then
				segScrollNeed = {
					itemID = rec.ri,
					qty = 1,
					unitCost = ev.baseUnlockCost,
					source = ev.unlockLabel,
					isVendor = (rec.src == "camp") or (rec.src == "vendor" and not ev.scrollViaAH),
					favorTokens = ev.favorTokens,
					usedIn = rec.n,
				}
				scrollNeedList[#scrollNeedList + 1] = segScrollNeed
			end
		end
		if (rec.pre or 0) > 0 then
			local preID = rec.pre
			while preID and preID > 0 do
				local preEv = evalBySpell[preID]
				if not preEv then break end
				if not preEv.known and not unlockedInSteps[preID] then
					segUnlockCost = segUnlockCost + (preEv.baseUnlockCost or 0)
					segUnlockFavor = segUnlockFavor + (preEv.baseUnlockFavor or 0)
					unlockedInSteps[preID] = true
				end
				preID = preEv.rec.pre
			end
		end

		-- Compute start/end skill-up chances for display
		local pStart = MP.GetSkillUpChance(rec, seg.s1, ctx.legacy.overtime, ev.effReq)
		local pEnd = MP.GetSkillUpChance(rec, seg.s2 - 1, ctx.legacy.overtime, ev.effReq)
		local chanceStr
		if math.abs(pStart - pEnd) < 0.005 then
			chanceStr = string.format("%d%%", math_floor(pStart * 100 + 0.5))
		else
			chanceStr = string.format("%d%%->%d%%", math_floor(pStart * 100 + 0.5), math_floor(pEnd * 100 + 0.5))
		end

		-- Ensure same-profession sub-crafts & consume self-crafted intermediates FIRST
		local stepGross, consumedFromSteps, consumedFromOwnedInterm, boughtDirectOnAH, stepReuseLinks = ensureRecipeReagentsAndCost(ev, seg.crafts, seg.s1, rec.n, 1)

		local unitsMade = (seg.unitsOverride ~= nil) and seg.unitsOverride or math_floor(seg.crafts * ev.yieldPerCraft + 1e-9)
		local outID = rec.i or 0
		local priorAH = (outID > 0) and (ahSoldSoFar[outID] or 0) or 0
		local resale, ahSold, vendSold, resaleTag = computeOutputsResale(ev, unitsMade, ctx, priorAH)
		if outID > 0 and ahSold > 0 then
			ahSoldSoFar[outID] = priorAH + ahSold
		end

		stepIndex = stepIndex + 1
		local hasTradeOutput = (not rec.ench) and ((rec.i or 0) > 0)
		local stepObj = {
			stepNum = stepIndex,
			scrollNeed = segScrollNeed,
			isMilestone = false,
			spellID = rec.s,
			itemID = rec.i or 0,
			s1 = seg.s1,
			s2 = seg.s2,
			reqSkill = ev.effReq,
			reqLv = ev.effRlv,
			skillRange = string.format("%d -> %d", seg.s1, seg.s2),
			sortSkill = seg.s1,
			name = rec.n,
			rawRecipeName = rec.n,
			sourceLabel = ev.unlockLabel,
			srcType = rec.src,
			crafts = seg.crafts,
			skillCrafts = seg.crafts,
			prepCrafts = 0,
			exactCrafts = seg.exactCrafts,
			unitsMade = unitsMade,
			unitsKeptForLater = 0,
			keptValueSaved = 0,
			chanceStart = pStart,
			chanceEnd = pEnd,
			chanceRange = chanceStr,
			unlockCost = segUnlockCost,
			unlockFavor = segUnlockFavor,
			grossMats = stepGross,
			resale = resale,
			standaloneResale = resale,
			standaloneTag = resaleTag,
			standaloneNetCost = segUnlockCost + stepGross - resale,
			ahSold = ahSold,
			vendorSold = vendSold,
			resaleTag = resaleTag,
			dailySold = ev.canAH and ev.dailySold or nil,
			listed = ev.canAH and ev.listed or nil,
			demand = hasTradeOutput and ev.demand or nil,
			demandScore = (hasTradeOutput and ev.demand) and ev.demand.demandScore or nil,
			heatBadge = (hasTradeOutput and ev.demand) and ev.demand.heatBadge or nil,
			netCost = segUnlockCost + stepGross - resale,
			ev = ev,
			rec = rec,
			reagentDetails = ev.reagentDetails,
			consumedFromSteps = consumedFromSteps,
			consumedFromOwnedInterm = consumedFromOwnedInterm,
			boughtDirectOnAH = boughtDirectOnAH,
		}
		steps[stepIndex] = stepObj
		for _, ks in ipairs(stepReuseLinks or {}) do
			ks.destStep = stepObj
		end

		if (rec.i or 0) > 0 and unitsMade > 0 and not rec.ench then
			craftedPool[rec.i] = craftedPool[rec.i] or {}
			craftedPool[rec.i][#craftedPool[rec.i] + 1] = {
				avail = unitsMade,
				step = stepObj,
			}
		end
	end

	-- Pass 1: Re-sync chronological stepNum + compute raw full-recipe economics after all reuse/prep steps settle
	for idx, st in ipairs(steps) do
		st.stepNum = idx
		if not st.isMilestone and not st.isRod and not st.isSubCraftStep and (st.prepCrafts or 0) > 0 then
			st.chanceRange = st.chanceRange .. string.format(" (+%dp)", st.prepCrafts)
		end
		st.rolledInCost = 0
		st.rolledOutCost = 0
		st.rolledInSteps = nil
		st.isPureInvestment = false
		st.allocatedNetCost = st.netCost or 0
		if not st.isMilestone then
			local reusedInputMats = 0
			local reusedAHValue = 0
			if st.consumedFromSteps and st.reagentDetails then
				for _, rg in ipairs(st.reagentDetails) do
					local fromSelf = st.consumedFromSteps[rg.itemID] or 0
					if fromSelf > 0 then
						local uCost = rg.unitCost or 0
						reusedInputMats = reusedInputMats + (fromSelf * uCost)
						reusedAHValue = reusedAHValue + (fromSelf * math_max(uCost, rg.ahUnitCost or 0))
					end
				end
			end
			st.reusedInputMats = reusedInputMats
			st.reusedAHValue = reusedAHValue
			st.fullRecipeMats = (st.grossMats or 0) + reusedInputMats
			st.fullRecipeNet = (st.unlockCost or 0) + st.fullRecipeMats - (st.resale or 0)
		end
	end

	-- Pass 2: Chronological investment / cost-rollup accounting (upstream pre-crafts roll into their downstream consumer steps)
	for _, st in ipairs(steps) do
		local validTargets = nil
		local totalDestQty = 0
		if st.keptForSteps then
			for _, ks in ipairs(st.keptForSteps) do
				local dest = ks.destStep
				if dest and dest.stepNum then
					ks.stepNum = dest.stepNum
					if not st.isMilestone and (st.unitsKeptForLater or 0) > 0 and (st.unitsMade or 0) > 0
						and dest.stepNum > st.stepNum and (ks.qty or 0) > 0 then
						validTargets = validTargets or {}
						validTargets[#validTargets + 1] = ks
						totalDestQty = totalDestQty + ks.qty
					end
				end
				ks._token = nil
				ks._linked = nil
			end
		end

		if validTargets and totalDestQty > 0 then
			local isPureInv = ((st.unitsKeptForLater >= st.unitsMade) or (st.isSubCraftStep == true)) and ((st.resale or 0) == 0)
			local baseCostPool = (st.grossMats or 0) + (st.rolledInCost or 0)
			local totalTransfer
			if isPureInv then
				totalTransfer = (st.unlockCost or 0) + baseCostPool
			else
				totalTransfer = math_floor((baseCostPool * math_min(1, st.unitsKeptForLater / st.unitsMade)) + 0.5)
			end
			local remaining = totalTransfer
			local nTargets = #validTargets
			for tIdx, ks in ipairs(validTargets) do
				local share
				if tIdx == nTargets then
					share = remaining
				else
					share = math_floor((totalTransfer * (ks.qty / totalDestQty)) + 0.5)
					remaining = remaining - share
				end
				ks.rolledCost = share
				local dest = ks.destStep
				dest.rolledInCost = (dest.rolledInCost or 0) + share
				dest.rolledInSteps = dest.rolledInSteps or {}
				dest.rolledInSteps[#dest.rolledInSteps + 1] = {
					stepNum = st.stepNum,
					name = st.rawRecipeName or st.name,
					qty = ks.qty,
					cost = share,
				}
			end
			st.rolledOutCost = totalTransfer
			st.isPureInvestment = isPureInv
		end

		if st.keptForSteps then
			for _, ks in ipairs(st.keptForSteps) do
				ks.destStep = nil
			end
		end

		st.allocatedNetCost = (st.unlockCost or 0) + (st.grossMats or 0) + (st.rolledInCost or 0) - (st.rolledOutCost or 0) - (st.resale or 0)
		if st.isMilestone or st.isRod then
			st.ahResaleTotal = nil
			st.vendorResaleTotal = nil
			st.sellChannel = "-"
		else
			local sev = st.ev
			local um = st.unitsMade or 0
			local hasAH = sev and sev.canAH and sev.ahGrossUnit and (not sev.isUnlisted or sev.isCustomPrice) and um > 0
			local ahU = hasAH and ((ctx.goalMode == "ah_max") and (sev.afterCutUnit or sev.ahNetUnit or 0) or (sev.ahNetUnit or 0)) or nil
			st.ahResaleTotal = (ahU ~= nil) and (um * ahU) or nil
			local vU = (sev and not sev.rec.ench and (sev.rec.i or 0) > 0) and (sev.vendorUnit or 0) or 0
			st.vendorResaleTotal = (vU > 0 and um > 0) and (um * vU) or nil
			local ahS = st.ahSold or 0
			local vendS = st.vendorSold or 0
			local kept = st.unitsKeptForLater or 0
			local usedDE = type(st.resaleTag) == "string" and st.resaleTag:find("DE", 1, true) ~= nil
			if ahS > 0 and vendS > 0 then
				st.sellChannel = usedDE and "AH+DE" or "AH+V"
			elseif ahS > 0 then
				st.sellChannel = "AH"
			elseif vendS > 0 then
				st.sellChannel = usedDE and "DE" or "V"
			elseif kept > 0 and st.keptForSteps and st.keptForSteps[1] and st.keptForSteps[1].stepNum then
				st.sellChannel = "-> #" .. tostring(st.keptForSteps[1].stepNum)
			elseif kept > 0 then
				st.sellChannel = "Kept"
			else
				st.sellChannel = "-"
			end
		end
	end

	-----------------------------------------------------------------------------------------------
	-- Build Stock-Aware Shopping Lists: Consolidated (Standard) + By Level (Per Skill Range)

	local function formatMergedSkillRanges(intervals)
		if not intervals or #intervals == 0 then return "—", "—" end
		local merged = {}
		for _, iv in ipairs(intervals) do
			local a = iv.s1 or 1
			local b = iv.s2 or a
			local last = merged[#merged]
			if last and a <= last.s2 then
				if b > last.s2 then last.s2 = b end
			else
				merged[#merged + 1] = { s1 = a, s2 = b }
			end
		end
		local detailParts = {}
		for _, m in ipairs(merged) do
			detailParts[#detailParts + 1] = (m.s1 == m.s2) and tostring(m.s1) or string.format("%d -> %d", m.s1, m.s2)
		end
		local detailStr = table.concat(detailParts, ", ")
		if #merged == 1 then
			return detailParts[1], detailStr
		elseif #merged == 2 then
			local c1 = (merged[1].s1 == merged[1].s2) and tostring(merged[1].s1) or string.format("%d-%d", merged[1].s1, merged[1].s2)
			local c2 = (merged[2].s1 == merged[2].s2) and tostring(merged[2].s1) or string.format("%d-%d", merged[2].s1, merged[2].s2)
			local compact = c1 .. ", " .. c2
			if #compact <= 13 then
				return compact, detailStr
			end
		end
		return string.format("%d -> %d (%d)", merged[1].s1, merged[#merged].s2, #merged), detailStr
	end

	local reagentAgg = {}
	local reagentOrder = {}
	local stepNeeds = {}

	for _, st in ipairs(steps) do
		local stS1 = st.s1 or 1
		local stS2 = st.s2 or stS1
		local stRange = (stS1 == stS2) and tostring(stS1) or string.format("%d -> %d", stS1, stS2)
		local perStepByItem = {}
		local perStepOrder = {}

		local function addStepShopNeed(itemID, qty, unitCost, source, isVendor, usedInName, selfCraftedQty, favorTokens, isScroll)
			if qty <= 0 and (selfCraftedQty or 0) <= 0 then return end
			if favorTokens and favorTokens > 0 then unitCost = 0 end
			local entry = reagentAgg[itemID]
			if not entry then
				entry = {
					itemID = itemID,
					name = MP.ItemName(itemID),
					rawNeed = 0,
					selfCrafted = 0,
					ownedUsed = 0,
					buyQty = 0,
					unitCost = unitCost or 0,
					source = source or "AH",
					isVendor = isVendor and true or false,
					favorTokens = favorTokens,
					firstSkill = stS1,
					firstStepNum = st.stepNum or 1,
					intervals = {},
					usedMap = {},
					usedList = {},
				}
				reagentAgg[itemID] = entry
				reagentOrder[#reagentOrder + 1] = entry
			end
			entry.rawNeed = entry.rawNeed + qty
			entry.selfCrafted = entry.selfCrafted + (selfCraftedQty or 0)
			if stS1 < entry.firstSkill then
				entry.firstSkill = stS1
			end
			local lastIv = entry.intervals[#entry.intervals]
			if not lastIv or lastIv.stepNum ~= st.stepNum then
				entry.intervals[#entry.intervals + 1] = { s1 = stS1, s2 = stS2, stepNum = st.stepNum }
			end
			if usedInName and not entry.usedMap[usedInName] then
				entry.usedMap[usedInName] = true
				entry.usedList[#entry.usedList + 1] = usedInName
			end

			local sn = perStepByItem[itemID]
			if not sn then
				sn = {
					stepNum = st.stepNum or 1,
					s1 = stS1,
					s2 = stS2,
					skillRange = stRange,
					isScroll = isScroll and true or false,
					itemID = itemID,
					name = entry.name,
					rawNeed = 0,
					selfCrafted = 0,
					unitCost = unitCost or 0,
					source = source or "AH",
					isVendor = isVendor and true or false,
					favorTokens = favorTokens,
					usedMap = {},
					usedList = {},
				}
				perStepByItem[itemID] = sn
				perStepOrder[#perStepOrder + 1] = sn
			end
			sn.rawNeed = sn.rawNeed + qty
			sn.selfCrafted = sn.selfCrafted + (selfCraftedQty or 0)
			if usedInName and not sn.usedMap[usedInName] then
				sn.usedMap[usedInName] = true
				sn.usedList[#sn.usedList + 1] = usedInName
			end
		end

		if st.scrollNeed then
			local sc = st.scrollNeed
			addStepShopNeed(sc.itemID, sc.qty, sc.unitCost, sc.source, sc.isVendor, sc.usedIn, 0, sc.favorTokens, true)
		end

		if st.reagentDetails and st.crafts and st.crafts > 0 then
			local dispName = st.rawRecipeName or st.name
			for _, rg in ipairs(st.reagentDetails) do
				local totalNeed = rg.qtyPerCraft * st.crafts
				local fromSelf = (st.consumedFromSteps and st.consumedFromSteps[rg.itemID]) or 0
				local fromOwnInt = (st.consumedFromOwnedInterm and st.consumedFromOwnedInterm[rg.itemID]) or 0
				local extNeed = math_max(0, totalNeed - fromSelf - fromOwnInt)

				if rg.sameProfSubEv then
					if extNeed > 0 then
						addStepShopNeed(rg.itemID, extNeed, rg.ahUnitCost or rg.unitCost, "AH", rg.isVendor, dispName, fromSelf + fromOwnInt, nil, false)
					end
				elseif extNeed > 0 and rg.isSubCraft and rg.craftOpt and rg.craftOpt.breakdown and ctx.mns and ctx.mns.CollectLeafReagents then
					local subMade = rg.craftOpt.numMade or 1
					local subBatches = math_ceil(extNeed / subMade)
					local leafMap = ctx.mns.CollectLeafReagents(rg.craftOpt.breakdown, subBatches, {})
					for leafID, leafQty in pairs(leafMap) do
						local vBase, vFromPricing = nil, false
						local isKnownVendorLeaf = ctx.mns.VENDOR_REAGENTS and ctx.mns.VENDOR_REAGENTS[leafID] ~= nil
						if ctx.mns.GetVendorBuyPrice then
							local candBuy, candLive = ctx.mns.GetVendorBuyPrice(leafID, isKnownVendorLeaf and ctx.mns.VENDOR_REAGENTS[leafID] or nil, false, ctx.legacy.bartering)
							if candBuy and (isKnownVendorLeaf or candLive) then
								vBase, vFromPricing = candBuy, true
							end
						elseif isKnownVendorLeaf then
							vBase = ctx.mns.VENDOR_REAGENTS[leafID]
						end
						local lUnit, lSrc
						if vBase then
							lUnit = vFromPricing and vBase or math_max(1, math_floor(vBase * ctx.legacy.vendorMult + 0.5))
							lSrc = "Vendor"
						else
							lUnit, lSrc = ctx.mns.GetReagentUnitCost(leafID)
						end
						addStepShopNeed(leafID, leafQty, lUnit or 0, lSrc or "AH", vBase ~= nil, dispName .. " (via " .. MP.ItemName(rg.itemID) .. ")", 0, nil, false)
					end
				elseif extNeed > 0 or fromSelf > 0 then
					if extNeed > 0 then
						addStepShopNeed(rg.itemID, extNeed, rg.unitCost, rg.source, rg.isVendor, dispName, fromSelf, nil, false)
					end
				end
			end
		end

		for _, sn in ipairs(perStepOrder) do
			stepNeeds[#stepNeeds + 1] = sn
		end
	end

	local shoppingList = {}
	local shoppingListByLevel = {}
	local leafOwnedSavings = 0
	local mns = ctx.mns

	-- Deduct owned inventory chronologically across steps so By Level and Consolidated sums match 100%
	for idx, sn in ipairs(stepNeeds) do
		local ownedAvail = ctx.useOwned and getPoolOwned(sn.itemID, sn.name) or 0
		local ownedUsed = math_min(sn.rawNeed, ownedAvail)
		if ctx.useOwned and ownedUsed > 0 then
			consumePoolOwned(sn.itemID, sn.name, ownedUsed)
		end
		local buyQty = math_max(0, sn.rawNeed - ownedUsed)
		leafOwnedSavings = leafOwnedSavings + (ownedUsed * sn.unitCost)

		local agg = reagentAgg[sn.itemID]
		if agg then
			agg.ownedUsed = agg.ownedUsed + ownedUsed
			agg.buyQty = agg.buyQty + buyQty
		end

		local listed = (not sn.isVendor and mns and mns.GetNumListed) and mns.GetNumListed(sn.itemID) or nil
		local dailySold = (not sn.isVendor and mns and mns.GetDailySold) and mns.GetDailySold(sn.itemID) or nil
		local lineCost = (sn.favorTokens and sn.favorTokens > 0) and 0 or (buyQty * sn.unitCost)
		local lowStock = (not sn.isVendor and buyQty > 0 and listed ~= nil and buyQty > listed) or false

		shoppingListByLevel[#shoppingListByLevel + 1] = {
			itemID = sn.itemID,
			name = sn.name,
			stepNum = sn.stepNum,
			s1 = sn.s1,
			s2 = sn.s2,
			skillRange = sn.skillRange,
			skillRangesDetail = sn.skillRange,
			sortSkill = sn.s1 * 1000 + sn.stepNum + (sn.isScroll and 0 or 0.5) + idx * 0.0001,
			source = sn.source,
			isVendor = sn.isVendor,
			favorTokens = sn.favorTokens,
			favorCost = sn.favorTokens,
			lineFavor = (sn.favorTokens or 0) * buyQty,
			usedIn = table.concat(sn.usedList, ", "),
			totalNeed = sn.rawNeed + sn.selfCrafted,
			ownedOrSelf = ownedUsed + sn.selfCrafted,
			ownedUsed = ownedUsed,
			selfCrafted = sn.selfCrafted,
			buyQty = buyQty,
			listed = listed,
			lowStock = lowStock,
			dailySold = dailySold,
			unitPrice = sn.unitCost,
			lineCost = lineCost,
		}
	end

	for _, e in ipairs(reagentOrder) do
		local listed = (not e.isVendor and mns and mns.GetNumListed) and mns.GetNumListed(e.itemID) or nil
		local dailySold = (not e.isVendor and mns and mns.GetDailySold) and mns.GetDailySold(e.itemID) or nil
		local lineCost = (e.favorTokens and e.favorTokens > 0) and 0 or (e.buyQty * e.unitCost)
		local lowStock = (not e.isVendor and e.buyQty > 0 and listed ~= nil and e.buyQty > listed) or false
		local rangeShort, rangeDetail = formatMergedSkillRanges(e.intervals)

		shoppingList[#shoppingList + 1] = {
			itemID = e.itemID,
			name = e.name,
			s1 = e.firstSkill,
			skillRange = rangeShort,
			skillRangesDetail = rangeDetail,
			sortSkill = e.firstSkill * 1000 + (e.firstStepNum or 1),
			source = e.source,
			isVendor = e.isVendor,
			favorTokens = e.favorTokens,
			favorCost = e.favorTokens,
			lineFavor = (e.favorTokens or 0) * e.buyQty,
			usedIn = table.concat(e.usedList, ", "),
			totalNeed = e.rawNeed + e.selfCrafted,
			ownedOrSelf = e.ownedUsed + e.selfCrafted,
			ownedUsed = e.ownedUsed,
			selfCrafted = e.selfCrafted,
			buyQty = e.buyQty,
			listed = listed,
			lowStock = lowStock,
			dailySold = dailySold,
			unitPrice = e.unitCost,
			lineCost = lineCost,
		}
	end

	table.sort(shoppingList, function(a, b)
		if (a.buyQty > 0) ~= (b.buyQty > 0) then return a.buyQty > 0 end
		if a.isVendor ~= b.isVendor then return not a.isVendor end
		if a.lineCost ~= b.lineCost then return a.lineCost > b.lineCost end
		return a.name < b.name
	end)

	-- Final Totals (strictly preserving netCost == totalTrainUnlocks + totalGrossMats - totalResale)
	local totalCrafts, stepGrossSum, totalTrainUnlocks, totalResale = 0, 0, 0, 0
	local totalFavorTokens = 0
	for _, row in ipairs(shoppingList) do totalFavorTokens = totalFavorTokens + (row.lineFavor or 0) end
	for _, st in ipairs(steps) do
		totalCrafts = totalCrafts + (st.crafts or 0)
		local listedFavor = st.scrollNeed and (st.scrollNeed.favorTokens or 0) * (st.scrollNeed.qty or 1) or 0
		totalFavorTokens = totalFavorTokens + math_max(0, (st.unlockFavor or 0) - listedFavor)
		stepGrossSum = stepGrossSum + (st.grossMats or 0)
		totalTrainUnlocks = totalTrainUnlocks + (st.unlockCost or 0)
		totalResale = totalResale + (st.resale or 0)
	end
	local rawGrossMats = stepGrossSum + ownedIntermSavings
	local totalOwnedSavings = leafOwnedSavings + ownedIntermSavings
	local effectiveGrossMats = math_max(0, stepGrossSum - leafOwnedSavings)
	local netCost = totalTrainUnlocks + effectiveGrossMats - totalResale

	return {
		profKey = profKey,
		profInfo = profInfo,
		startSkill = startSkill,
		targetSkill = targetSkill,
		requestedTarget = requestedTarget,
		charLevel = ctx.charLevel,
		isAutoCharLv = ctx.isAutoCharLv,
		levelCapInfo = levelCapInfo,
		legacy = ctx.legacy,
		goalMode = ctx.goalMode,
		recipeFilter = ctx.recipeFilter,
		knownCapSkill = knownCapSkill,
		usedFallbackFilter = usedFallbackFilter,
		fallbackRange = fallbackRange,
		steps = steps,
		shoppingList = shoppingList,
		shoppingListByLevel = shoppingListByLevel,
		totalCrafts = totalCrafts,
		rawGrossMats = rawGrossMats,
		ownedSavings = totalOwnedSavings,
		totalGrossMats = effectiveGrossMats,
		totalTrainUnlocks = totalTrainUnlocks,
		totalFavorTokens = totalFavorTokens,
		totalSpend = totalTrainUnlocks + effectiveGrossMats,
		totalResale = totalResale,
	netCost = netCost, -- negative means NET PROFIT!
	}
end

local vendorStopsIndexCache = nil
local vendorStopsPinsRef = nil
local function getVendorStopsIndex()
	if vendorStopsIndexCache and vendorStopsPinsRef == ns.NPC_PINS then return vendorStopsIndexCache end
	local recipeByItemID = {}
	for _, r in ipairs(ns.RECIPES or {}) do
		local rid = tonumber(r.recipeItemID)
		if rid and rid > 0 and not recipeByItemID[rid] then
			recipeByItemID[rid] = r
		end
	end
	local pinsByKey = {}
	for npcID, npc in pairs(ns.NPC_PINS or {}) do
		for _, key in ipairs(npc.recipeKeys or {}) do
			pinsByKey[key] = pinsByKey[key] or {}
			pinsByKey[key][#pinsByKey[key] + 1] = { npcID = npcID, npc = npc }
		end
	end
	vendorStopsPinsRef = ns.NPC_PINS
	vendorStopsIndexCache = { recipeByItemID = recipeByItemID, pinsByKey = pinsByKey }
	return vendorStopsIndexCache
end

local function factionAllowed(fac, playerFac)
	if not fac or fac == "" or fac == "AH" or not playerFac or playerFac == "" or playerFac == "AH" then
		return true
	end
	return fac == playerFac
end

-- Greedy set-cover over shoppingList vendor items / Favor recipes using ns.NPC_PINS
function MP.BuildVendorStops(shoppingList, playerFaction)
	local pFac = playerFaction or getPlayerFactionCode()
	if pFac == "Alliance" then pFac = "A" elseif pFac == "Horde" then pFac = "H" end
	local idx = getVendorStopsIndex()
	local needRows = {}
	for _, row in ipairs(shoppingList or {}) do
		local qty = tonumber(row.buyQty) or 0
		local isVend = (row.isVendor == true) or ((tonumber(row.favorCost) or tonumber(row.favorTokens) or 0) > 0)
		if qty > 0 and isVend then
			needRows[#needRows + 1] = row
		end
	end
	if #needRows == 0 then
		return { stops = {}, stopCount = 0, vendorItemCount = 0 }
	end

	local stopMeta = {}
	local itemCandidates = {}
	for i, row in ipairs(needRows) do
		local cands = {}
		local r = row.itemID and idx.recipeByItemID[row.itemID] or nil
		if r then
			local rKey = (r.spellID and r.outputItemID) and ("s:" .. tostring(r.spellID) .. ":i:" .. tostring(r.outputItemID)) or nil
			local pinList = rKey and idx.pinsByKey[rKey] or nil
			if pinList then
				for _, p in ipairs(pinList) do
					local npc = p.npc
					local recFac = npc.recipeFactions and npc.recipeFactions[rKey] or "AH"
					if factionAllowed(npc.faction, pFac) and factionAllowed(recFac, pFac) then
						local skey = "npc:" .. tostring(p.npcID)
						if not stopMeta[skey] then
							local sp = npc.spawns and npc.spawns[1] or nil
							local zone
							if sp and sp.uiMapID then
								local mInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(sp.uiMapID) or nil
								zone = (mInfo and mInfo.name) or ("Map " .. tostring(sp.uiMapID))
							end
							stopMeta[skey] = {
								key = skey,
								npcID = p.npcID,
								name = npc.name or ("Vendor #" .. tostring(p.npcID)),
								kind = npc.kind or "vendor",
								faction = npc.faction or "AH",
								zone = zone,
								uiMapID = sp and sp.uiMapID or nil,
								x = sp and sp.x or nil,
								y = sp and sp.y or nil,
								coords = (sp and sp.x and sp.y) and string.format("%.1f, %.1f", sp.x * 100, sp.y * 100) or nil,
							}
						end
						cands[#cands + 1] = skey
					end
				end
			end
			if #cands == 0 then
				local vName
				if pFac == "A" then vName = r.vendorA elseif pFac == "H" then vName = r.vendorH end
				vName = vName or r.vendorAll or r.vendorA or r.vendorH
				if r.source == "camp" then
					vName = vName or "Merchant's Favor Quartermaster"
				else
					vName = vName or "Recipe Vendor"
				end
				local skey = "named:" .. vName
				if not stopMeta[skey] then
					stopMeta[skey] = {
						key = skey,
						name = vName,
						kind = (r.source == "camp") and "camp" or "vendor",
						faction = pFac,
					}
				end
				cands[#cands + 1] = skey
			end
		else
			local hasFavor = ((tonumber(row.favorCost) or tonumber(row.favorTokens) or 0) > 0)
			local skey = hasFavor and "gen:favor" or "gen:supplies"
			if not stopMeta[skey] then
				stopMeta[skey] = {
					key = skey,
					name = hasFavor and "Merchant's Favor Camp" or "Trade / Profession Supplies Vendor",
					kind = hasFavor and "camp" or "vendor",
					faction = "AH",
				}
			end
			cands[#cands + 1] = skey
		end
		itemCandidates[i] = cands
	end

	local uncovered = {}
	for i = 1, #needRows do uncovered[i] = true end
	local remCount = #needRows
	local stops = {}
	while remCount > 0 do
		local counts = {}
		local bestKey, bestCnt = nil, -1
		for i = 1, #needRows do
			if uncovered[i] then
				for _, skey in ipairs(itemCandidates[i]) do
					counts[skey] = (counts[skey] or 0) + 1
					local c = counts[skey]
					if c > bestCnt or (c == bestCnt and bestKey and stopMeta[skey].name < stopMeta[bestKey].name) then
						bestKey = skey
						bestCnt = c
					end
				end
			end
		end
		if not bestKey then break end
		local meta = stopMeta[bestKey]
		local stop = {
			key = meta.key,
			npcID = meta.npcID,
			name = meta.name,
			kind = meta.kind,
			faction = meta.faction,
			zone = meta.zone,
			uiMapID = meta.uiMapID,
			x = meta.x,
			y = meta.y,
			coords = meta.coords,
			items = {},
			totalCost = 0,
			totalFavor = 0,
		}
		for i = 1, #needRows do
			if uncovered[i] then
				local covered = false
				for _, skey in ipairs(itemCandidates[i]) do
					if skey == bestKey then covered = true; break end
				end
				if covered then
					uncovered[i] = false
					remCount = remCount - 1
					local row = needRows[i]
					stop.items[#stop.items + 1] = {
						itemID = row.itemID,
						name = row.name,
						qty = row.buyQty,
						cost = row.lineCost or 0,
						favor = row.lineFavor or 0,
					}
					stop.totalCost = stop.totalCost + (row.lineCost or 0)
					stop.totalFavor = stop.totalFavor + (row.lineFavor or 0)
				end
			end
		end
		stops[#stops + 1] = stop
	end
	return { stops = stops, stopCount = #stops, vendorItemCount = #needRows }
end

function MP.ComputeGoldRunway(stepsOrPlan, copperMoney)
	local stepList = (type(stepsOrPlan) == "table" and type(stepsOrPlan.steps) == "table") and stepsOrPlan.steps or stepsOrPlan
	local startCopper = math_max(0, math_floor((tonumber(copperMoney) or (GetMoney and GetMoney()) or 0) + 0.5))
	local bal = startCopper
	local minBal = startCopper
	local coveredSteps = 0
	local shortfallStepNum = nil
	local shortfallStep = nil
	local stillFunded = true
	local nSteps = (type(stepList) == "table") and #stepList or 0
	for i = 1, nSteps do
		local st = stepList[i]
		local spend = (st.unlockCost or 0) + (st.grossMats or 0)
		bal = bal - spend
		if bal < minBal then
			minBal = bal
		end
		if stillFunded then
			if bal < 0 then
				stillFunded = false
				shortfallStepNum = st.stepNum or i
				shortfallStep = st
			else
				coveredSteps = coveredSteps + 1
			end
		end
		bal = bal + (st.resale or 0)
	end
	local shortfallCopper = (minBal < 0) and (-minBal) or 0
	return {
		startCopper = startCopper,
		minBalance = minBal,
		endBalance = bal,
		shortfallCopper = shortfallCopper,
		isFunded = (shortfallCopper == 0),
		shortfallStepNum = shortfallStepNum,
		shortfallStep = shortfallStep,
		coveredSteps = coveredSteps,
		totalSteps = nSteps,
	}
end

local function serializeOverrides(tbl)
	if type(tbl) ~= "table" then return "" end
	local keys = {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	if #keys == 0 then return "" end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for i = 1, #keys do
		local k = keys[i]
		parts[i] = tostring(k) .. "=" .. tostring(tbl[k])
	end
	return table.concat(parts, ",")
end

function MP.SolveProfessionPath(profKey, opts)
	opts = opts or {}
	local profInfo = MP.PROFESSIONS[profKey]
	if not profInfo then return nil end

	local mns = ns
	local canCache = (not opts.forceRecompute)
		and opts.ownedCounts == nil and opts.ownedCountsByID == nil
		and opts.subCraftOverrides == nil
		and opts.overtimeRank == nil and opts.legacyOverride == nil
		and opts.overtimeOverride == nil and opts.goalMode == nil
		and opts.recipeFilter == nil and opts.charLevel == nil
		and opts.useFullRange == nil and opts.activeSpec == nil
		and opts.sellDays == nil and opts.subCraftMode == nil
		and opts.knownRecipesOnly == nil and opts.applyAHCut == nil
		and opts.includeVendorSell == nil and opts.useOwned == nil
		and opts.useDisenchantRecovery == nil and opts.playerKnowsEnchanting == nil
		and opts.ignoreLearnedSpells == nil and opts.ignoreCharLevel == nil
		and opts.onlyUnlockedCamp == nil and opts.allowCooldowns == nil
		and opts.includeLockedForBrowse == nil
	local cacheKey
	if canCache then
		local db = MP.GetDB()
		local mmdb = _G.MerchantMasterDB
		local liveProfs = opts.liveProfs or MP.ScanPlayerProfessions()
		local cp = liveProfs and liveProfs[profKey]
		local sSkill = tonumber(opts.startSkill) or (cp and cp.rank) or profInfo.defaultStart or 1
		local tSkill = tonumber(opts.targetSkill) or 300
		local pVer = (mns.GetEffectivePriceVersion and mns.GetEffectivePriceVersion()) or mns.priceCacheEpoch or 0
		local appRef = mns.app
		local solveRev = appRef and appRef.profSolveRev or 0
		local ownRev = (db.useOwned ~= false) and (appRef and appRef.ownershipRev or 0) or 0
		local effCharLv = MP.GetEffectiveCharLevel(db, opts)
		local effLegacy = MP.GetEffectiveLegacy(db)
		local sharedSubOv = (mmdb and mmdb.subCraftOverrides) or db.subCraftOverrides
		local repState = mns.GetMerchantReputation and mns.GetMerchantReputation() or nil
		cacheKey = table.concat({
			tostring(profKey), tostring(sSkill), tostring(tSkill),
			tostring(cp and cp.rank or 0), tostring(cp and cp.maxRank or 0),
			tostring(db.charLevelMode or ""), tostring(effCharLv),
			tostring(db.overtimeMode or ""),
			tostring(effLegacy.overtime), tostring(effLegacy.bartering),
			tostring(effLegacy.masterChef), tostring(effLegacy.perfBonus),
			tostring(db.goalMode or ""), tostring(db.recipeFilter or ""),
			tostring(db.sellDays or 3), tostring(db.includeVendorSell ~= false),
			tostring(db.useDisenchantRecovery == true),
			tostring(liveProfs and liveProfs.enchanting ~= nil),
			tostring(db.useOwned ~= false),
			tostring(db.subCraftMode or ""), tostring(db.activeSpec or ""),
			tostring(getPlayerActiveSpec(profKey, false) or ""),
			tostring(getPlayerFactionCode()),
			tostring(repState and repState.standingID or 4),
			serializeOverrides(sharedSubOv),
			tostring(mmdb and mmdb.knownRecipesOnly == true),
			tostring(mmdb and mmdb.applyAHCut ~= false),
			tostring((mmdb and mmdb.smartFilterColdItems ~= nil) and (mmdb.smartFilterColdItems ~= false) or (db.smartFilterColdItems ~= false)),
			tostring(mmdb and mmdb.economy or "auto"),
			tostring(mmdb and mmdb.priceSource or "auto"),
			tostring(mmdb and mmdb.subCraftMode or ""),
			tostring(pVer), tostring(solveRev), tostring(ownRev),
			tostring(liveThresholdsRev),
		}, "|")
		local hit = solvePathCache[profKey]
		if hit and hit.key == cacheKey then
			return hit.res
		end
	end

	local openedEval = false
	if mns.BeginEval and not mns._evalCache then
		local bank = mns.app and mns.app.getUIPriceBank and mns.app.getUIPriceBank() or nil
		mns.BeginEval(bank)
		openedEval = true
	end
	local ok, res = pcall(solveProfessionPathImpl, profKey, opts)
	if openedEval then
		if ok then
			if mns.EndEval then mns.EndEval() end
		else
			if mns.ResetEval then mns.ResetEval() end
		end
	end
	if not ok then error(res, 2) end
	if canCache and cacheKey and res then
		solvePathCache[profKey] = { key = cacheKey, res = res }
	end
	return res
end

---------------------------------------------------------------------------------------------------
-- Working Overtime Lab: 0/5 (+0%) vs Active vs 5/5 (+20%) Across All 10 Craftable Professions

local function computeLevelingSpend(res)
	if not res then return 0 end
	local spend = 0
	for _, st in ipairs(res.steps or {}) do
		if st.isMilestone then
			spend = spend + (st.unlockCost or 0)
		elseif not st.isPureInvestment then
			local alloc = (st.allocatedNetCost ~= nil) and st.allocatedNetCost or (st.netCost or 0)
			if alloc > 0 then
				spend = spend + alloc
			end
		end
	end
	return spend
end

function MP.CompareOvertimeForProfession(profKey, opts)
	opts = opts or {}
	local mns = ns
	local openedEval = false
	if mns and mns.BeginEval and not mns._evalCache then
		local bank = mns.app and mns.app.getUIPriceBank and mns.app.getUIPriceBank() or nil
		mns.BeginEval(bank)
		openedEval = true
	end
	local ok, cmp = pcall(function()
		local baseOpts0 = {}
		local baseOpts5 = {}
		for k, v in pairs(opts) do baseOpts0[k] = v; baseOpts5[k] = v end
		baseOpts0.overtimeRank = 0
		baseOpts5.overtimeRank = 5

		local r0 = MP.SolveProfessionPath(profKey, baseOpts0)
		local r5 = MP.SolveProfessionPath(profKey, baseOpts5)
		if not r0 or not r5 or r0.unreachable or r5.unreachable or r0.levelLocked or r5.levelLocked then
			return { profKey = profKey, r0 = r0, r5 = r5 }
		end

		local spells5 = {}
		for _, st in ipairs(r5.steps) do
			if st.spellID then spells5[st.spellID] = true end
		end
		local skippedList = {}
		local skippedSeen = {}
		for _, st in ipairs(r0.steps) do
			if st.spellID and not spells5[st.spellID] and not skippedSeen[st.spellID] then
				skippedSeen[st.spellID] = true
				skippedList[#skippedList + 1] = st.rawRecipeName or st.name
			end
		end

		local lvl0 = computeLevelingSpend(r0)
		local lvl5 = computeLevelingSpend(r5)
		return {
			profKey = profKey,
			profName = MP.PROFESSIONS[profKey].name,
			category = MP.PROFESSIONS[profKey].cat,
			startSkill = r0.startSkill,
			targetSkill = r0.targetSkill,
			crafts0 = r0.totalCrafts,
			crafts5 = r5.totalCrafts,
			craftsSaved = r0.totalCrafts - r5.totalCrafts,
			unlocks0 = r0.totalTrainUnlocks,
			unlocks5 = r5.totalTrainUnlocks,
			unlocksSaved = r0.totalTrainUnlocks - r5.totalTrainUnlocks,
			net0 = r0.netCost,
			net5 = r5.netCost,
			goldSaved = r0.netCost - r5.netCost,
			levelingCost0 = lvl0,
			levelingCost5 = lvl5,
			levelingSaved = lvl0 - lvl5,
			skippedSummary = (#skippedList > 0) and ("Skips: " .. table.concat(skippedList, ", ")) or "Fewer yellow/green crafts",
			r0 = r0,
			r5 = r5,
		}
	end)
	if openedEval then
		if ok then
			if mns.EndEval then mns.EndEval() end
		else
			if mns.ResetEval then mns.ResetEval() end
		end
	end
	if not ok then error(cmp, 2) end
	return cmp
end

function MP.BuildAllProfessionsOvertimeMatrix(opts)
	opts = opts or {}
	local mns = ns
	local openedEval = false
	if mns and mns.BeginEval and not mns._evalCache then
		local bank = mns.app and mns.app.getUIPriceBank and mns.app.getUIPriceBank() or nil
		mns.BeginEval(bank)
		openedEval = true
	end
	local ok, rows = pcall(function()
		local liveProfs = MP.ScanPlayerProfessions()
		local out = {}
		for _, pk in ipairs(MP.PROF_ORDER) do
			local pInfo = MP.PROFESSIONS[pk]
			local pOpts = {}
			for k, v in pairs(opts) do pOpts[k] = v end
			pOpts.liveProfs = liveProfs
			if opts.useFullRange then
				pOpts.startSkill = pInfo.defaultStart or 1
				pOpts.targetSkill = 300
				pOpts.ignoreCharLevel = true
			else
				pOpts.startSkill = (liveProfs[pk] and liveProfs[pk].rank) or pInfo.defaultStart or 1
				pOpts.targetSkill = 300
				if pOpts.startSkill >= 300 then
					pOpts.startSkill = pInfo.defaultStart or 1
				end
			end
			local cmp = MP.CompareOvertimeForProfession(pk, pOpts)
			cmp.isLearned = (liveProfs[pk] and liveProfs[pk].learned) or false
			cmp.liveRank = liveProfs[pk] and liveProfs[pk].rank or 0
			out[#out + 1] = cmp
		end
		return out
	end)
	if openedEval then
		if ok then
			if mns.EndEval then mns.EndEval() end
		else
			if mns.ResetEval then mns.ResetEval() end
		end
	end
	if not ok then error(rows, 2) end
	return rows
end
end)() end
