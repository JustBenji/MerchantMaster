-- MerchantMaster: Professions, Waylaid Crates, Craftsman's Writs, Gathering Nodes & Reputation Unlocks
local _, ns = ...

ns.FAVOR_CURRENCY_ID = 3402
ns.FACTION_ALLIANCE = 2586 -- Azeroth Commerce Authority
ns.FACTION_HORDE = 2587    -- Durotar Supply and Logistics

ns.ITEM_IDS_BY_NAME = {}
ns.ITEM_NAMES_BY_ID = {}
ns.ALL_CATALOG_IDS = {}

function ns.RegisterItem(id, name)
	if not id or id <= 0 then return end
	ns.ALL_CATALOG_IDS[id] = true
	if name and name ~= "" then
		if not ns.ITEM_NAMES_BY_ID[id] then ns.ITEM_NAMES_BY_ID[id] = name end
		if not ns.ITEM_IDS_BY_NAME[name] then ns.ITEM_IDS_BY_NAME[name] = id end
	end
end

-- Profession definitions (supports both Classic skillLine IDs and WoW Forever 16001 release skillLine IDs)
ns.PROFESSIONS = {
	{ key = "all",            label = "All",     full = "All Professions" },
	{ key = "mine_profs",     label = "My Profs",full = "My Learned Professions" },
	{ key = "alchemy",        label = "Alch",    full = "Alchemy",        skillLine = 171, releaseLine = 2937, spell = 2259, kind = "craft" },
	{ key = "blacksmithing",  label = "BS",      full = "Blacksmithing",  skillLine = 164, releaseLine = 2938, spell = 2018, kind = "craft" },
	{ key = "cooking",        label = "Cook",    full = "Cooking",        skillLine = 185, releaseLine = 2939, spell = 2550, kind = "secondary" },
	{ key = "enchanting",     label = "Ench",    full = "Enchanting",     skillLine = 333, releaseLine = 2940, spell = 7411, kind = "craft" },
	{ key = "engineering",    label = "Eng",     full = "Engineering",    skillLine = 202, releaseLine = 2941, spell = 4036, kind = "craft" },
	{ key = "firstaid",       label = "FA",      full = "First Aid",      skillLine = 129, releaseLine = 2942, spell = 3273, kind = "secondary" },
	{ key = "leatherworking", label = "LW",      full = "Leatherworking", skillLine = 165, releaseLine = 2945, spell = 2108, kind = "craft" },
	{ key = "tailoring",      label = "Tailor",  full = "Tailoring",      skillLine = 197, releaseLine = 2948, spell = 3908, kind = "craft" },
	{ key = "herbalism",      label = "Herb",    full = "Herbalism",      skillLine = 182, releaseLine = 2944, spell = 2366, kind = "gather" },
	{ key = "mining",         label = "Mine",    full = "Mining",         skillLine = 186, releaseLine = 2946, spell = 2575, kind = "gather" },
	{ key = "skinning",       label = "Skin",    full = "Skinning",       skillLine = 393, releaseLine = 2947, spell = 8613, kind = "gather" },
	{ key = "poisons",        label = "Pois",    full = "Poisons",        skillLine = 40,  spell = 2842, kind = "secondary" },
}

ns.PROF_BY_KEY = {}
ns.PROF_BY_SKILLLINE = {}
for _, p in ipairs(ns.PROFESSIONS) do
	ns.PROF_BY_KEY[p.key] = p
	if p.skillLine then ns.PROF_BY_SKILLLINE[p.skillLine] = p.key end
	if p.releaseLine then ns.PROF_BY_SKILLLINE[p.releaseLine] = p.key end
end
ns.PROF_BY_KEY.others = { key = "others", label = "Others", short = "Others", full = "Others", kind = "other" }

-- WoW: Forever Economy Splits (5 Rulesets x 2 Factions)
ns.ECONOMIES = {
	{ key = "auto",                  label = "Auto",             full = "Auto (Current Character Economy)" },
	{ key = "Normal-Horde",          label = "Normal-Horde",     full = "Normal - Horde",          ruleset = "Normal",       faction = "Horde",    hc = false },
	{ key = "Normal-Alliance",       label = "Normal-Alliance",  full = "Normal - Alliance",       ruleset = "Normal",       faction = "Alliance", hc = false },
	{ key = "PvP-Horde",             label = "PvP-Horde",        full = "PvP - Horde",             ruleset = "PvP",          faction = "Horde",    hc = false },
	{ key = "PvP-Alliance",          label = "PvP-Alliance",     full = "PvP - Alliance",          ruleset = "PvP",          faction = "Alliance", hc = false },
	{ key = "Roleplay-Horde",        label = "RP-Horde",         full = "Roleplay - Horde",        ruleset = "Roleplay",     faction = "Horde",    hc = false },
	{ key = "Roleplay-Alliance",     label = "RP-Alliance",      full = "Roleplay - Alliance",     ruleset = "Roleplay",     faction = "Alliance", hc = false },
	{ key = "Roleplay PvP-Horde",    label = "RP-PvP-Horde",     full = "Roleplay PvP - Horde",    ruleset = "Roleplay PvP", faction = "Horde",    hc = false },
	{ key = "Roleplay PvP-Alliance", label = "RP-PvP-Alliance",  full = "Roleplay PvP - Alliance", ruleset = "Roleplay PvP", faction = "Alliance", hc = false },
	{ key = "Hardcore-Horde",        label = "HC-Horde",         full = "Hardcore - Horde",        ruleset = "Hardcore",     faction = "Horde",    hc = true  },
	{ key = "Hardcore-Alliance",     label = "HC-Alliance",      full = "Hardcore - Alliance",     ruleset = "Hardcore",     faction = "Alliance", hc = true  },
}

ns.ECONOMY_BY_KEY = {}
for _, e in ipairs(ns.ECONOMIES) do
	ns.ECONOMY_BY_KEY[e.key] = e
end

-- Skill rank unlock brackets in Classic / Forever
function ns.SkillRankBracket(skill)
	skill = tonumber(skill) or 1
	if skill <= 75 then
		return "Apprentice", 1
	elseif skill <= 150 then
		return "Journeyman", 10
	elseif skill <= 225 then
		return "Expert", 20
	else
		return "Artisan", 35
	end
end

-- Reputation standings & cumulative reputation required from Neutral 0
ns.REP_TIERS = {
	{ standing = 4, name = "Neutral",  totalRep = 0,     span = 3000  },
	{ standing = 5, name = "Friendly", totalRep = 3000,  span = 6000  },
	{ standing = 6, name = "Honored",  totalRep = 9000,  span = 12000 },
	{ standing = 7, name = "Revered",  totalRep = 21000, span = 21000 },
	{ standing = 8, name = "Exalted",  totalRep = 42000, span = 1000  },
}

ns.STANDING_NAMES = {
	[0] = "Neutral",
	[1] = "Hated",
	[2] = "Hostile",
	[3] = "Unfriendly",
	[4] = "Neutral",
	[5] = "Friendly",
	[6] = "Honored",
	[7] = "Revered",
	[8] = "Exalted",
}

-- Special non-recipe Merchant's Favor (currency 3402) items sold at Three Corners (Alliance) / Crossroads (Horde)
ns.SPECIAL_REP_UNLOCKS = {
	{ itemID = 280179, name = "Shipping Label (First Filled Crate Quest)", rep = 4, favorCost = 0,    category = "Quest Bonus",   note = "One-time +2,000 Reputation boost on first Waylaid Crate" },
	{ itemID = 262902, name = "Forged Delivery Receipt",                   rep = 5, favorCost = 15,   category = "Consumable",    questID = 93862, containerItemID = 262917, forgedRefundCopper = 100, forgedBaseRep = 50, note = "Turns an empty Waylaid Crate into +50 Reputation (+1s 00c, Friendly)" },
	{ itemID = 262896, name = "Forger's Quill",                            rep = 6, favorCost = 15,   category = "Consumable",    note = "Rerolls a Craftsman's Writ to another writ of the same tier (Honored)" },
	{ itemID = 270887, name = "Advertising License Application",           rep = 6, favorCost = 1200, category = "Toy",           faction = "Horde",    note = "Profession Signpost Toy (Honored)" },
	{ itemID = 270888, name = "Advertising License Application",           rep = 6, favorCost = 1200, category = "Toy",           faction = "Alliance", note = "Profession Signpost Toy (Honored)" },
	{ itemID = 271621, name = "Alchemy Certification",                     rep = 4, favorCost = 1000, category = "Certification", note = "Requires Skill 300; unlocks Profession Title" },
	{ itemID = 271622, name = "Blacksmithing Certification",               rep = 4, favorCost = 1000, category = "Certification", note = "Requires Skill 300; unlocks Profession Title" },
	{ itemID = 271624, name = "Enchanting Certification",                  rep = 4, favorCost = 1000, category = "Certification", note = "Requires Skill 300; unlocks Profession Title" },
	{ itemID = 271625, name = "Engineering Certification",                 rep = 4, favorCost = 1000, category = "Certification", note = "Requires Skill 300; unlocks Profession Title" },
	{ itemID = 271626, name = "Leatherworking Certification",              rep = 4, favorCost = 1000, category = "Certification", note = "Requires Skill 300; unlocks Profession Title" },
	{ itemID = 271627, name = "Tailoring Certification",                   rep = 4, favorCost = 1000, category = "Certification", note = "Requires Skill 300; unlocks Profession Title" },
	{ itemID = 284664, name = "Packmule Treat",                            rep = 7, favorCost = 1500, category = "Pet",           note = "Minimule Companion Pet (Revered)" },
	{ itemID = 262764, name = "Durotar Supply and Logistics Tabard",       rep = 8, favorCost = 200,  category = "Tabard",        faction = "Horde",    note = "Horde Faction Tabard (Exalted)" },
	{ itemID = 262765, name = "Azeroth Commerce Authority Tabard",         rep = 8, favorCost = 200,  category = "Tabard",        faction = "Alliance", note = "Alliance Faction Tabard (Exalted)" },
	{ itemID = 262766, name = "Reins of the Pack Kodo",                    rep = 8, favorCost = 6000, category = "Mount",         note = "Account-wide Epic Pack Kodo Mount (Exalted, Level 60)" },
}
for _, u in ipairs(ns.SPECIAL_REP_UNLOCKS) do
	ns.RegisterItem(u.itemID, u.name)
end

-- Verified Beta P2 Waylaid Crate turn-in rewards (Merchant's Favor + copper cashback)
ns.DEFAULT_REWARDS = {
	Apprentice = {
		[1] = { tokens = 5,  copper = 250,  questID = 91899, sealedID = 248765 },
		[2] = { tokens = 10, copper = 500,  questID = 91904, sealedID = 248770 },
	},
	Journeyman = {
		[1] = { tokens = 10, copper = 500,  questID = 91900, sealedID = 248766 },
		[2] = { tokens = 20, copper = 1000, questID = 91905, sealedID = 248771 },
	},
	Expert = {
		[1] = { tokens = 15, copper = 750,  questID = 91901, sealedID = 248767 },
		[2] = { tokens = 30, copper = 1500, questID = 91906, sealedID = 248772 },
	},
	Artisan = {
		[1] = { tokens = 20, copper = 1000, questID = 91902, unconfirmed = true },
		[2] = { tokens = 40, copper = 2000, questID = 91907, unconfirmed = true },
	},
}

ns.FORGED_RECEIPT = {
	receiptItemID = 262902,
	receiptName = "Forged Delivery Receipt",
	containerItemID = 262917,
	containerName = "Notarized Shipping Container",
	questID = 93862,
	questName = "Crate Return",
	favorCost = 15,
	requiredStanding = 5,
	baseRep = 50,
	refundCopper = 100,
	dailyCap = 0,
	racialMultipliers = { Human = 1.1 },
	allianceVendor = { name = "Dianne Softstep", mapX = 9.1, mapY = 76.5 },
	hordeVendor = { name = "Kurvelk Shadowhoof", mapX = 49.8, mapY = 30.0 },
	turnInAlliance = { name = "Marcy Baker", mapX = 9.5, mapY = 71.1 },
	turnInHorde = { name = "Dokimi", mapX = 50.0, mapY = 29.2 },
}

-- Gathering items & skill thresholds (Herbalism, Mining, Skinning)
ns.GATHER_BY_ITEM = {}
ns.GATHER_ITEMS = {
	-- Herbalism (28 herbs)
	{ itemID = 2447,  name = "Peacebloom",          prof = "herbalism", skill = 1,   yellow = 25,  gray = 100, note = "Starter zones" },
	{ itemID = 765,   name = "Silverleaf",          prof = "herbalism", skill = 1,   yellow = 25,  gray = 100, note = "Starter zones (trees)" },
	{ itemID = 2449,  name = "Earthroot",           prof = "herbalism", skill = 15,  yellow = 40,  gray = 115, note = "Hills & cliffs" },
	{ itemID = 785,   name = "Mageroyal",           prof = "herbalism", skill = 50,  yellow = 75,  gray = 150, note = "Barrens, Westfall, Darkshore" },
	{ itemID = 2450,  name = "Briarthorn",          prof = "herbalism", skill = 70,  yellow = 95,  gray = 170, note = "Barrens, Redridge, Darkshore" },
	{ itemID = 3820,  name = "Stranglekelp",        prof = "herbalism", skill = 85,  yellow = 110, gray = 185, note = "Coasts & underwater" },
	{ itemID = 2453,  name = "Bruiseweed",          prof = "herbalism", skill = 100, yellow = 125, gray = 200, note = "Hillsbrad, Stonetalon, Wetlands" },
	{ itemID = 3355,  name = "Wild Steelbloom",     prof = "herbalism", skill = 115, yellow = 140, gray = 215, note = "Stonetalon, Arathi, Stranglethorn" },
	{ itemID = 3369,  name = "Grave Moss",          prof = "herbalism", skill = 120, yellow = 145, gray = 220, note = "Duskwood, Desolace, Wetlands" },
	{ itemID = 3356,  name = "Kingsblood",          prof = "herbalism", skill = 125, yellow = 150, gray = 225, note = "Hillsbrad, Stranglethorn, Wetlands" },
	{ itemID = 3357,  name = "Liferoot",            prof = "herbalism", skill = 150, yellow = 175, gray = 250, note = "River & lake banks" },
	{ itemID = 3818,  name = "Fadeleaf",            prof = "herbalism", skill = 160, yellow = 185, gray = 260, note = "Swamp of Sorrows, Arathi" },
	{ itemID = 3821,  name = "Goldthorn",           prof = "herbalism", skill = 170, yellow = 195, gray = 270, note = "Arathi, Ferelas, Hinterlands" },
	{ itemID = 3358,  name = "Khadgar's Whisker",   prof = "herbalism", skill = 185, yellow = 210, gray = 285, note = "Stranglethorn, Hinterlands" },
	{ itemID = 3819,  name = "Wintersbite",         prof = "herbalism", skill = 195, yellow = 220, gray = 295, note = "Alterac Mountains" },
	{ itemID = 4625,  name = "Firebloom",           prof = "herbalism", skill = 205, yellow = 230, gray = 305, note = "Tanaris, Searing Gorge, Badlands" },
	{ itemID = 8831,  name = "Purple Lotus",        prof = "herbalism", skill = 210, yellow = 235, gray = 310, note = "Ashenvale, Azshara, Tanaris ruins" },
	{ itemID = 8836,  name = "Arthas' Tears",       prof = "herbalism", skill = 220, yellow = 245, gray = 320, note = "Felwood, Plaguelands" },
	{ itemID = 8838,  name = "Sungrass",            prof = "herbalism", skill = 230, yellow = 255, gray = 330, note = "Feralas, Hinterlands, Un'Goro" },
	{ itemID = 8839,  name = "Blindweed",           prof = "herbalism", skill = 235, yellow = 260, gray = 335, note = "Swamp of Sorrows, Un'Goro" },
	{ itemID = 8845,  name = "Ghost Mushroom",      prof = "herbalism", skill = 245, yellow = 270, gray = 345, note = "Hinterlands & Maraudon caves" },
	{ itemID = 8846,  name = "Gromsblood",          prof = "herbalism", skill = 250, yellow = 275, gray = 350, note = "Felwood, Blasted Lands, Desolace" },
	{ itemID = 13464, name = "Golden Sansam",       prof = "herbalism", skill = 260, yellow = 285, gray = 360, note = "Feralas, Un'Goro, Azshara" },
	{ itemID = 13463, name = "Dreamfoil",           prof = "herbalism", skill = 270, yellow = 290, gray = 370, note = "Un'Goro, Azshara, Plaguelands" },
	{ itemID = 13465, name = "Mountain Silversage", prof = "herbalism", skill = 280, yellow = 305, gray = 380, note = "Winterspring, Un'Goro, Azshara" },
	{ itemID = 13466, name = "Plaguebloom",         prof = "herbalism", skill = 285, yellow = 310, gray = 385, note = "Western & Eastern Plaguelands" },
	{ itemID = 13467, name = "Icecap",              prof = "herbalism", skill = 290, yellow = 315, gray = 390, note = "Winterspring" },
	{ itemID = 13468, name = "Black Lotus",         prof = "herbalism", skill = 300, yellow = 325, gray = 400, note = "High-level zones (rare spawn)" },
	-- Mining (9 ores)
	{ itemID = 2770,  name = "Copper Ore",          prof = "mining",    skill = 1,   yellow = 25,  gray = 100, note = "Copper Vein" },
	{ itemID = 2771,  name = "Tin Ore",             prof = "mining",    skill = 65,  yellow = 90,  gray = 165, note = "Tin Vein" },
	{ itemID = 2775,  name = "Silver Ore",          prof = "mining",    skill = 75,  yellow = 100, gray = 175, note = "Silver Vein" },
	{ itemID = 2772,  name = "Iron Ore",            prof = "mining",    skill = 125, yellow = 150, gray = 225, note = "Iron Deposit" },
	{ itemID = 2776,  name = "Gold Ore",            prof = "mining",    skill = 155, yellow = 180, gray = 255, note = "Gold Vein" },
	{ itemID = 3858,  name = "Mithril Ore",         prof = "mining",    skill = 175, yellow = 200, gray = 275, note = "Mithril Deposit" },
	{ itemID = 7911,  name = "Truesilver Ore",      prof = "mining",    skill = 230, yellow = 255, gray = 330, note = "Truesilver Deposit" },
	{ itemID = 11370, name = "Dark Iron Ore",       prof = "mining",    skill = 230, yellow = 255, gray = 330, note = "Dark Iron Deposit" },
	{ itemID = 10620, name = "Thorium Ore",         prof = "mining",    skill = 245, yellow = 270, gray = 375, note = "Small / Rich Thorium Vein" },
	-- Skinning (9 leathers/hides)
	{ itemID = 2934,  name = "Ruined Leather Scraps", prof = "skinning", skill = 1,   yellow = 15,  gray = 50,  note = "Level 1-10 beasts" },
	{ itemID = 2318,  name = "Light Leather",       prof = "skinning",  skill = 1,   yellow = 45,  gray = 100, note = "Level 1-20 beasts" },
	{ itemID = 783,   name = "Light Hide",          prof = "skinning",  skill = 1,   yellow = 45,  gray = 100, note = "Level 10-20 beasts" },
	{ itemID = 2319,  name = "Medium Leather",      prof = "skinning",  skill = 75,  yellow = 115, gray = 165, note = "Level 20-30 beasts" },
	{ itemID = 4232,  name = "Medium Hide",         prof = "skinning",  skill = 75,  yellow = 115, gray = 165, note = "Level 20-30 beasts" },
	{ itemID = 4234,  name = "Heavy Leather",       prof = "skinning",  skill = 150, yellow = 185, gray = 235, note = "Level 30-40 beasts" },
	{ itemID = 4235,  name = "Heavy Hide",          prof = "skinning",  skill = 150, yellow = 185, gray = 235, note = "Level 30-40 beasts" },
	{ itemID = 4304,  name = "Thick Leather",       prof = "skinning",  skill = 205, yellow = 240, gray = 285, note = "Level 40-50 beasts" },
	{ itemID = 8169,  name = "Thick Hide",          prof = "skinning",  skill = 205, yellow = 240, gray = 285, note = "Level 40-50 beasts" },
	{ itemID = 8170,  name = "Rugged Leather",      prof = "skinning",  skill = 255, yellow = 285, gray = 330, note = "Level 51-60 beasts" },
}
for _, g in ipairs(ns.GATHER_ITEMS) do
	ns.GATHER_BY_ITEM[g.itemID] = g
	ns.RegisterItem(g.itemID, g.name)
end


-- Waylaid Crates (30 crates, 96 reagent bundles) with profession & skill unlock mapping
ns.CRATES = {}

local CRATE_MAT_PROF = {
	-- Textiles (Cloth -> Tailoring, Leather -> Skinning)
	[2589] = { prof = "tailoring", skill = 1 },   [2592] = { prof = "tailoring", skill = 75 },
	[4306] = { prof = "tailoring", skill = 125 }, [4338] = { prof = "tailoring", skill = 175 },
	[14047] = { prof = "tailoring", skill = 250 },
	-- Curiosities (Enchanting disenchant materials)
	[10940] = { prof = "enchanting", skill = 1 },   [10939] = { prof = "enchanting", skill = 1 },
	[10978] = { prof = "enchanting", skill = 25 },  [11084] = { prof = "enchanting", skill = 50 },
	[11083] = { prof = "enchanting", skill = 75 },  [11082] = { prof = "enchanting", skill = 75 },
	[11138] = { prof = "enchanting", skill = 100 }, [11139] = { prof = "enchanting", skill = 125 },
	[11137] = { prof = "enchanting", skill = 150 }, [11135] = { prof = "enchanting", skill = 150 },
	[11177] = { prof = "enchanting", skill = 175 }, [11178] = { prof = "enchanting", skill = 200 },
	[11176] = { prof = "enchanting", skill = 225 }, [11175] = { prof = "enchanting", skill = 225 },
	[14343] = { prof = "enchanting", skill = 250 }, [14344] = { prof = "enchanting", skill = 275 },
	-- Fabrics (Bolts -> Tailoring, Cured Hides -> Leatherworking)
	[2996] = { prof = "tailoring", skill = 1 },     [2997] = { prof = "tailoring", skill = 75 },
	[4305] = { prof = "tailoring", skill = 125 },   [4339] = { prof = "tailoring", skill = 175 },
	[14048] = { prof = "tailoring", skill = 250 },
	[4231] = { prof = "leatherworking", skill = 35 },  [4233] = { prof = "leatherworking", skill = 100 },
	[4236] = { prof = "leatherworking", skill = 150 }, [8172] = { prof = "leatherworking", skill = 200 },
	-- Ingots (Smelting -> Mining / Blacksmithing)
	[2840] = { prof = "mining", skill = 1 },   [3576] = { prof = "mining", skill = 65 },
	[2841] = { prof = "mining", skill = 65 },  [2842] = { prof = "mining", skill = 75 },
	[3575] = { prof = "mining", skill = 125 }, [3577] = { prof = "mining", skill = 155 },
	[3859] = { prof = "mining", skill = 165 }, [3860] = { prof = "mining", skill = 175 },
	[6037] = { prof = "mining", skill = 230 }, [11371] = { prof = "mining", skill = 230 },
	[12359] = { prof = "mining", skill = 250 },
	-- Parts (Engineering)
	[4359] = { prof = "engineering", skill = 1 },   [4361] = { prof = "engineering", skill = 50 },
	[4363] = { prof = "engineering", skill = 65 },  [4371] = { prof = "engineering", skill = 105 },
	[4375] = { prof = "engineering", skill = 120 }, [4382] = { prof = "engineering", skill = 145 },
	[10558] = { prof = "engineering", skill = 150 },[4387] = { prof = "engineering", skill = 160 },
	[10559] = { prof = "engineering", skill = 195 },[10560] = { prof = "engineering", skill = 200 },
	[10561] = { prof = "engineering", skill = 215 },[15994] = { prof = "engineering", skill = 260 },
	[18631] = { prof = "engineering", skill = 260 },[16000] = { prof = "engineering", skill = 275 },
}

local function cb(qty, id, name)
	ns.RegisterItem(id, name)
	local g = ns.GATHER_BY_ITEM[id]
	local m = CRATE_MAT_PROF[id]
	return {
		qty = qty,
		itemID = id,
		name = name,
		prof = (g and g.prof) or (m and m.prof) or "other",
		skill = (g and g.skill) or (m and m.skill) or 1,
	}
end

local function addCrate(itemID, quality, level, shortName, ...)
	local tier = shortName:match("Apprentice")
		or shortName:match("Journeyman")
		or shortName:match("Expert")
		or shortName:match("Artisan")
	local fullName = "Waylaid Crate: " .. shortName
	ns.RegisterItem(itemID, fullName)
	ns.CRATES[#ns.CRATES + 1] = {
		itemID = itemID,
		quality = quality,
		level = level,
		tier = tier,
		shortName = shortName,
		name = fullName,
		bundles = { ... },
	}
end

addCrate(248682, 1, 10, "Apprentice Herbs", cb(20, 2447, "Peacebloom"), cb(20, 765, "Silverleaf"), cb(10, 2449, "Earthroot"), cb(10, 785, "Mageroyal"), cb(10, 2450, "Briarthorn"))
addCrate(248683, 1, 10, "Apprentice Ore", cb(20, 2770, "Copper Ore"), cb(20, 2771, "Tin Ore"))
addCrate(248684, 1, 10, "Apprentice Textiles", cb(40, 2589, "Linen Cloth"), cb(20, 2318, "Light Leather"))
addCrate(248685, 1, 10, "Apprentice Curiosities", cb(20, 10940, "Strange Dust"), cb(4, 10939, "Greater Magic Essence"), cb(6, 10978, "Small Glimmering Shard"), cb(2, 11084, "Large Glimmering Shard"))
addCrate(248702, 2, 10, "Apprentice Fabrics", cb(2, 4231, "Cured Light Hide"), cb(20, 2996, "Bolt of Linen Cloth"))
addCrate(248703, 2, 10, "Apprentice Ingots", cb(20, 2840, "Copper Bar"), cb(20, 3576, "Tin Bar"), cb(10, 2841, "Bronze Bar"))
addCrate(248704, 2, 10, "Apprentice Parts", cb(16, 4359, "Handful of Copper Bolts"), cb(16, 4361, "Copper Tube"), cb(4, 4363, "Copper Modulator"))
addCrate(248686, 1, 10, "Journeyman Herbs", cb(10, 3820, "Stranglekelp"), cb(10, 2453, "Bruiseweed"), cb(10, 3355, "Wild Steelbloom"), cb(10, 3369, "Grave Moss"), cb(10, 3356, "Kingsblood"))
addCrate(248687, 1, 10, "Journeyman Ore", cb(10, 2775, "Silver Ore"), cb(20, 2772, "Iron Ore"))
addCrate(248688, 1, 10, "Journeyman Textiles", cb(20, 2592, "Wool Cloth"), cb(40, 4306, "Silk Cloth"), cb(20, 2319, "Medium Leather"))
addCrate(248689, 1, 10, "Journeyman Curiosities", cb(20, 11083, "Soul Dust"), cb(4, 11082, "Greater Astral Essence"), cb(6, 11138, "Small Glowing Shard"), cb(2, 11139, "Large Glowing Shard"))
addCrate(248705, 2, 10, "Journeyman Fabrics", cb(6, 2997, "Bolt of Woolen Cloth"), cb(10, 4305, "Bolt of Silk Cloth"), cb(2, 4233, "Cured Medium Hide"))
addCrate(248706, 2, 10, "Journeyman Ingots", cb(10, 2842, "Silver Bar"), cb(20, 3575, "Iron Bar"))
addCrate(248707, 2, 10, "Journeyman Parts", cb(8, 4371, "Bronze Tube"), cb(7, 4375, "Whirring Bronze Gizmo"), cb(4, 4382, "Bronze Framework"), cb(45, 10558, "Gold Power Core"))
addCrate(248690, 1, 20, "Earthly Expert Herbs", cb(20, 3357, "Liferoot"), cb(10, 3818, "Fadeleaf"), cb(10, 3821, "Goldthorn"), cb(10, 3358, "Khadgar's Whisker"))
addCrate(248691, 1, 20, "Flowering Expert Herbs", cb(10, 3819, "Wintersbite"), cb(10, 4625, "Firebloom"), cb(20, 8831, "Purple Lotus"), cb(10, 8836, "Arthas' Tears"))
addCrate(248692, 1, 20, "Expert Ore", cb(10, 2776, "Gold Ore"), cb(20, 3858, "Mithril Ore"))
addCrate(248693, 1, 20, "Expert Textiles", cb(40, 4338, "Mageweave Cloth"), cb(20, 4234, "Heavy Leather"))
addCrate(248694, 1, 20, "Expert Curiosities", cb(20, 11137, "Vision Dust"), cb(4, 11135, "Greater Mystic Essence"), cb(6, 11177, "Small Radiant Shard"), cb(2, 11178, "Large Radiant Shard"))
addCrate(248708, 2, 20, "Expert Fabrics", cb(8, 4339, "Bolt of Mageweave"), cb(2, 4236, "Cured Heavy Hide"))
addCrate(248709, 2, 20, "Expert Ingots", cb(20, 3860, "Mithril Bar"), cb(15, 3859, "Steel Bar"), cb(10, 3577, "Gold Bar"))
addCrate(248710, 2, 20, "Expert Parts", cb(8, 4387, "Iron Strut"), cb(5, 10559, "Mithril Tube"), cb(12, 10560, "Unstable Trigger"), cb(5, 10561, "Mithril Casing"))
addCrate(248695, 1, 35, "Earthly Artisan Herbs", cb(10, 13464, "Golden Sansam"), cb(20, 8838, "Sungrass"), cb(10, 8839, "Blindweed"), cb(10, 8845, "Ghost Mushroom"), cb(10, 8846, "Gromsblood"))
addCrate(248696, 1, 35, "Flowering Artisan Herbs", cb(20, 13463, "Dreamfoil"), cb(20, 13465, "Mountain Silversage"), cb(20, 13466, "Plaguebloom"), cb(20, 13467, "Icecap"))
addCrate(248697, 1, 35, "Artisan Ore", cb(10, 7911, "Truesilver Ore"), cb(20, 10620, "Thorium Ore"), cb(20, 11370, "Dark Iron Ore"))
addCrate(248698, 1, 35, "Artisan Textiles", cb(40, 14047, "Runecloth"), cb(20, 4304, "Thick Leather"), cb(20, 8170, "Rugged Leather"))
addCrate(248699, 1, 35, "Artisan Curiosities", cb(20, 11176, "Dream Dust"), cb(4, 11175, "Greater Nether Essence"), cb(6, 14343, "Small Brilliant Shard"), cb(2, 14344, "Large Brilliant Shard"))
addCrate(248711, 2, 35, "Artisan Fabrics", cb(8, 14048, "Bolt of Runecloth"), cb(2, 8172, "Cured Thick Hide"))
addCrate(248712, 2, 35, "Artisan Ingots", cb(2, 11371, "Dark Iron Bar"), cb(10, 6037, "Truesilver Bar"), cb(20, 12359, "Thorium Bar"))
addCrate(248713, 2, 35, "Artisan Parts", cb(5, 15994, "Thorium Widget"), cb(5, 18631, "Truesilver Transformer"), cb(2, 16000, "Thorium Tube"))

-- Craftsman's Writs (150 WoW Forever Merchant Reputation Orders for factions 2586 / 2587)
-- Turn-in quests reward a tiered Coin Pouch containing silver based on Writ reputation tier.
ns.DEFAULT_WRIT_POUCH_COPPER = 7480
ns.WRIT_POUCH_BY_REP = {
	[25]  = { id = 284583, name = "Coin Pouch", tier = "Apprentice", rep = 25,  avgMoneyCopper = 3536 },
	[75]  = { id = 284584, name = "Coin Pouch", tier = "Journeyman", rep = 75,  avgMoneyCopper = 3536 },
	[125] = { id = 284585, name = "Coin Pouch", tier = "Expert",     rep = 125, avgMoneyCopper = 7480 },
	[200] = { id = 284586, name = "Coin Pouch", tier = "Artisan",    rep = 200, avgMoneyCopper = 7480 },
}
ns.WRIT_POUCH_INFO = {
	defaultCopper = 7480,
	pouches = {
		ns.WRIT_POUCH_BY_REP[25],
		ns.WRIT_POUCH_BY_REP[75],
		ns.WRIT_POUCH_BY_REP[125],
		ns.WRIT_POUCH_BY_REP[200],
	},
}
ns.RegisterItem(284583, "Coin Pouch")
ns.RegisterItem(284584, "Coin Pouch")
ns.RegisterItem(284585, "Coin Pouch")
ns.RegisterItem(284586, "Coin Pouch")

ns.WRITS = {}
ns.WRIT_ACQ_BY_WRIT_ID = {}
local function addWrit(itemID, questID, shortName, reqID, reqName, qty, rep, prof, skill, spellID, numMade, reagents, npc, zone, x, y, acqType, recID, recName, vA, vH, vAll, recVendorPrice)
	local fullName = "Craftsman's Writ: " .. shortName
	local pouchMeta = ns.WRIT_POUCH_BY_REP[rep]
	ns.RegisterItem(itemID, fullName)
	ns.RegisterItem(reqID, reqName)
	if reagents then
		for _, r in ipairs(reagents) do
			ns.ALL_CATALOG_IDS[r[1]] = true
		end
	end
	local entry = {
		itemID = itemID,
		questID = questID,
		name = fullName,
		shortName = shortName,
		requiredItemID = reqID,
		requiredItemName = reqName,
		qty = qty,
		rep = rep,
		tier = pouchMeta and pouchMeta.tier or nil,
		pouchItemID = pouchMeta and pouchMeta.id or nil,
		pouchCopper = pouchMeta and pouchMeta.avgMoneyCopper or nil,
		prof = prof,
		skill = skill,
		spellID = spellID,
		numMade = numMade,
		reagents = reagents,
		npc = npc ~= "" and npc or nil,
		zone = zone ~= "" and zone or nil,
		x = x > 0 and x or nil,
		y = y > 0 and y or nil,
	}
	if acqType ~= nil then
		entry.acqType = acqType
		if recID and recID > 0 then entry.recipeItemID = recID end
		if recName and recName ~= "" then entry.recipeName = recName end
		entry.vendorA = vA or ""
		entry.vendorH = vH or ""
		entry.vendorAll = vAll or ""
		if recVendorPrice and recVendorPrice > 0 then entry.recipeVendorPrice = recVendorPrice end
		ns.WRIT_ACQ_BY_WRIT_ID[itemID] = { acqType, recID or 0, recName or "", vA or "", vH or "", vAll or "", recVendorPrice or 0 }
	end
	ns.WRITS[#ns.WRITS + 1] = entry
end

addWrit(264049, 94249, "Azure Silk Hood", 7048, "Azure Silk Hood", 1, 75, "tailoring", 145, 8760, nil, nil, "Cowardly Peon", "Ashenvale", 78.4, 68.8, "trainer", 0, "", "", "", "", 0)
addWrit(264045, 94245, "Barbaric Gloves", 4254, "Barbaric Gloves", 1, 75, "leatherworking", 150, 3771, nil, nil, "Goblin Pit Boss", "Thousand Needles", 79.9, 76.7, "ah", 4297, "Pattern: Barbaric Gloves", "", "", "", 0)
addWrit(264036, 94236, "Big Bronze Bomb", 4380, "Big Bronze Bomb", 1, 75, "engineering", 140, 3950, nil, nil, "Razzeric", "Thousand Needles", 80.3, 76.1, "trainer", 0, "", "", "", "", 0)
addWrit(264027, 94227, "Big Bronze Knife", 3848, "Big Bronze Knife", 1, 75, "blacksmithing", 100, 3491, nil, nil, "\"Plucky\" Johnson", "Thousand Needles", 79.6, 75.6, "trainer", 0, "", "", "", "", 0)
addWrit(264048, 94248, "Blue Overalls", 6263, "Blue Overalls", 1, 75, "tailoring", 100, 7639, nil, nil, "Alyce", "Arathi Highlands", 34, 23.2, "vendor_ah", 6274, "Pattern: Blue Overalls", "Gina MacGregor, Alexandra Bolero", "Mallen Swain, Borya", "Gina MacGregor [A], Alexandra Bolero [A]", 400)
addWrit(264053, 94253, "Colorful Kilt", 10048, "Colorful Kilt", 1, 75, "tailoring", 120, 12047, nil, nil, "Hekshi", "Stranglethorn Vale", 50.4, 19.2, "ah", 10316, "Pattern: Colorful Kilt", "", "", "", 0)
addWrit(264037, 94237, "Crafted Solid Shot", 8069, "Crafted Solid Shot", 200, 75, "engineering", 125, 3947, nil, nil, "Kixxle", "Wetlands", 50.3, 37.8, "trainer", 0, "", "", "", "", 0)
addWrit(264044, 94244, "Dark Leather Shoulders", 4252, "Dark Leather Shoulders", 1, 75, "leatherworking", 140, 3769, nil, nil, "Narkk", "Stranglethorn Vale", 28.1, 74.4, "ah", 4296, "Pattern: Dark Leather Shoulders", "", "", "", 0)
addWrit(264041, 94241, "Dark Leather Tunic", 2317, "Dark Leather Tunic", 1, 75, "leatherworking", 100, 2169, nil, nil, "Kzixx", "Duskwood", 81.8, 19.8, "ah", 2409, "Pattern: Dark Leather Tunic", "", "", "", 0)
addWrit(264019, 94219, "Draught of Water Breathing", 5996, "Elixir of Water Breathing", 1, 75, "alchemy", 90, 7179, nil, nil, "Kixxle", "Wetlands", 50.3, 37.8, "trainer", 0, "", "", "", "", 0)
addWrit(264018, 94218, "Elixir of Defense", 8951, "Elixir of Greater Defense", 1, 75, "alchemy", 195, 11450, nil, nil, "Rizzle Brassbolts", "Thousand Needles", 77.2, 77.4, "trainer", 0, "", "", "", "", 0)
addWrit(264016, 94216, "Elixir of Lesser Agility", 3390, "Elixir of Lesser Agility", 1, 75, "alchemy", 140, 2333, nil, nil, "Ziz Fizziks", "Stonetalon Mountains", 59, 62.4, "ah", 3396, "Recipe: Elixir of Lesser Agility", "", "", "", 0)
addWrit(264011, 94004, "Elixir of Ogre's Strength", 3391, "Elixir of Ogre's Strength", 1, 75, "alchemy", 150, 3188, nil, nil, "Sos'mol", "Alterac Mountains", 38.4, 61.2, "ah", 6211, "Recipe: Elixir of Ogre's Strength", "", "", "", 0)
addWrit(264012, 94212, "Elixir of Wisdom", 3383, "Elixir of Wisdom", 1, 75, "alchemy", 90, 3171, nil, nil, "Muggol Breezebeard", "Arathi Highlands", 48.8, 55.8, "trainer", 0, "", "", "", "", 0)
addWrit(264030, 94230, "Explosive Sheep", 4384, "Explosive Sheep", 1, 75, "engineering", 150, 3955, nil, nil, "Alyce", "Arathi Highlands", 34, 23.2, "trainer", 0, "", "", "", "", 0)
addWrit(264039, 94239, "Fine Leather Pants", 5958, "Fine Leather Pants", 1, 75, "leatherworking", 105, 7133, nil, nil, "Alyce", "Arathi Highlands", 34, 23.2, "ah", 5972, "Pattern: Fine Leather Pants", "", "", "", 0)
addWrit(264015, 94215, "Free Action Potion", 5634, "Free Action Potion", 1, 75, "alchemy", 150, 6624, nil, nil, "Webbed Mudsnout Gnoll", "Hillsbrad Foothills", 63.4, 70.8, "vendor_ah", 5642, "Recipe: Free Action Potion", "Ulthir, Soolie Berryfizz", "Kor'geld", "Kor'geld [H], Ulthir [A]", 1800)
addWrit(264035, 94235, "Gnomish Universal Remote", 7506, "Gnomish Universal Remote", 1, 75, "engineering", 125, 9269, nil, nil, "Scooty", "Stranglethorn Vale", 27.6, 77.4, "vendor", 7560, "Schematic: Gnomish Universal Remote", "Gearcutter Cogspinner, Jinky Twizzlefixxit", "Jinky Twizzlefixxit", "Gearcutter Cogspinner [A], Jinky Twizzlefixxit", 1200)
addWrit(264021, 94221, "Golden Rod", 11128, "Golden Rod", 1, 75, "blacksmithing", 150, 14379, nil, nil, "Muggol Breezebeard", "Arathi Highlands", 48.8, 55.8, "trainer", 0, "", "", "", "", 0)
addWrit(264054, 94254, "Greater Adept's Robe", 6264, "Greater Adept's Robe", 1, 75, "tailoring", 115, 7643, nil, nil, "Magus Tirth", "Thousand Needles", 78.3, 75.7, "vendor_ah", 6275, "Pattern: Greater Adept's Robe", "Jennabink Powerseam, Rann Flamespinner", "Millie Gregorian", "Jennabink Powerseam [A], Rann Flamespinner [A]", 800)
addWrit(264028, 94228, "Green Iron Boots", 3484, "Green Iron Boots", 1, 75, "blacksmithing", 145, 3334, nil, nil, "Kixxle", "Wetlands", 50.3, 37.8, "ah", 3611, "Plans: Green Iron Boots", "", "", "", 0)
addWrit(264026, 94226, "Green Iron Gauntlets", 3485, "Green Iron Gauntlets", 1, 75, "blacksmithing", 150, 3336, nil, nil, "\"Sea Wolf\" MacKinley", "Stranglethorn Vale", 27.8, 77.1, "ah", 3612, "Plans: Green Iron Gauntlets", "", "", "", 0)
addWrit(264024, 94224, "Heavy Bronze Mace", 3491, "Heavy Bronze Mace", 1, 75, "blacksmithing", 130, 3296, nil, nil, "Gorgrash", "Hillsbrad Foothills", 80, 48.4, "trainer", 0, "", "", "", "", 0)
addWrit(264038, 94238, "Heavy Leather Ball", 18662, "Heavy Leather Ball", 1, 75, "leatherworking", 150, 23190, nil, nil, "Sos'mol", "Alterac Mountains", 38.3, 61.2, "vendor_ah", 18731, "Pattern: Heavy Leather Ball", "Bombus Finespindle", "Tamar", "Tamar [H], Bombus Finespindle [A]", 2000)
addWrit(264043, 94243, "Heavy Quiver", 7371, "Heavy Quiver", 1, 75, "leatherworking", 150, 9193, nil, nil, "Ziz Fizziks", "Stonetalon Mountains", 59, 62.4, "trainer", 0, "", "", "", "", 0)
addWrit(264040, 94240, "Herbalist's Gloves", 7349, "Herbalist's Gloves", 1, 75, "leatherworking", 135, 9146, nil, nil, "Murache", "Ashenvale", 64.5, 79.2, "vendor_ah", 7361, "Pattern: Herbalist's Gloves", "Harlown Darkweave", "", "Harlown Darkweave [A]", 1800)
addWrit(264022, 94222, "Iridescent Hammer", 5541, "Iridescent Hammer", 1, 75, "blacksmithing", 140, 6518, nil, nil, "Cowardly Peon", "Ashenvale", 78.4, 68.8, "ah", 5543, "Plans: Iridescent Hammer", "", "", "", 0)
addWrit(264013, 94213, "Lesser Mana Potion", 3385, "Lesser Mana Potion", 1, 75, "alchemy", 120, 3173, nil, nil, "Ash'alari", "Ashenvale", 60.2, 72.4, "trainer", 0, "", "", "", "", 0)
addWrit(264017, 94217, "Lesser Troll's Blood Elixir", 3388, "Strong Troll's Blood Potion", 1, 75, "alchemy", 125, 3176, nil, nil, "Short John Mithril", "Stranglethorn Vale", 29.6, 47.4, "trainer", 0, "", "", "", "", 0)
-- Alan Sneeks (257282) QDB spawn has corrupt Y=21424.0; verified Forever Hillsbrad/Alterac pin 30.4, 61.2.
addWrit(264047, 94247, "Lesser Wizard's Robe", 5766, "Lesser Wizard's Robe", 1, 75, "tailoring", 135, 6690, nil, nil, "Alan Sneeks", "Alterac Mountains", 30.4, 61.2, "trainer", 0, "", "", "", "", 0)
addWrit(264032, 94232, "Minor Recombobulator", 4381, "Minor Recombobulator", 1, 75, "engineering", 140, 3952, nil, nil, "Kzixx", "Duskwood", 81.8, 19.8, "vendor_ah", 14639, "Schematic: Minor Recombobulator", "Fradd Swiftgear, Namdo Bizzfizzle", "Gagsprocket", "Fradd Swiftgear [A], Namdo Bizzfizzle [A]", 1500)
addWrit(264031, 94231, "Moonsight Rifle", 4383, "Moonsight Rifle", 1, 75, "engineering", 145, 3954, nil, nil, "Grembly", "Ashenvale", 82.4, 50.4, "ah", 4412, "Schematic: Moonsight Rifle", "", "", "", 0)
addWrit(264029, 94229, "Ornate Spyglass", 5507, "Ornate Spyglass", 1, 75, "engineering", 135, 6458, nil, nil, "Alan Sneeks", "Alterac Mountains", 30.4, 61.2, "trainer", 0, "", "", "", "", 0)
addWrit(264020, 94220, "Pearl-Handled Dagger", 5540, "Pearl-handled Dagger", 1, 75, "blacksmithing", 110, 6517, nil, nil, "Alan Sneeks", "Alterac Mountains", 30.4, 61.2, "trainer", 0, "", "", "", "", 0)
addWrit(264051, 94251, "Phoenix Pants", 4317, "Phoenix Pants", 1, 75, "tailoring", 125, 3851, nil, nil, "Bath'rah the Windwatcher", "Alterac Mountains", 80.5, 66.9, "ah", 4349, "Pattern: Phoenix Pants", "", "", "", 0)
addWrit(264042, 94242, "Pilferer's Gloves", 7358, "Pilferer's Gloves", 1, 75, "leatherworking", 140, 9148, nil, nil, "Kris Legace", "Hillsbrad Foothills", 80.1, 38.9, "ah", 7363, "Pattern: Pilferer's Gloves", "", "", "", 0)
addWrit(264033, 94233, "Practice Lock", 6712, "Practice Lock", 1, 75, "engineering", 100, 8334, nil, nil, "Gorgrash", "Hillsbrad Foothills", 80, 48.4, "trainer", 0, "", "", "", "", 0)
addWrit(264046, 94246, "Red Whelp Gloves", 7284, "Red Whelp Gloves", 1, 75, "leatherworking", 120, 9072, nil, nil, "Kixxle", "Wetlands", 50.3, 37.8, "vendor_ah", 7290, "Pattern: Red Whelp Gloves", "Wenna Silkbeard", "", "Wenna Silkbeard [A]", 1600)
addWrit(264052, 94252, "Red Woolen Boots", 4313, "Red Woolen Boots", 1, 75, "tailoring", 95, 3847, nil, nil, "Ziz Fizziks", "Stonetalon Mountains", 59, 62.4, "ah", 4345, "Pattern: Red Woolen Boots", "", "", "", 0)
addWrit(264025, 94225, "Rough Bronze Leggings", 2865, "Rough Bronze Leggings", 1, 75, "blacksmithing", 105, 2668, nil, nil, "Ziz Fizziks", "Stonetalon Mountains", 59, 62.4, "trainer", 0, "", "", "", "", 0)
addWrit(264034, 94234, "Shadow Goggles", 4373, "Shadow Goggles", 1, 75, "engineering", 120, 3940, nil, nil, "Ziz Fizziks", "Stonetalon Mountains", 59, 62.4, "ah", 4410, "Schematic: Shadow Goggles", "", "", "", 0)
addWrit(264014, 94214, "Shadow Protection Potion", 6048, "Shadow Protection Potion", 1, 75, "alchemy", 135, 7256, nil, nil, "Kzixx", "Duskwood", 81.8, 19.8, "vendor", 6054, "Recipe: Shadow Protection Potion", "Harklan Moongrove", "Christoph Jeffcoat", "Christoph Jeffcoat [H], Harklan Moongrove [A]", 900)
addWrit(264023, 94223, "Silver Skeleton Key", 15869, "Silver Skeleton Key", 1, 75, "blacksmithing", 100, 19666, nil, nil, "Battered Trunk", "Duskwood", 26.2, 36.3, "trainer", 0, "", "", "", "", 0)
addWrit(264050, 94250, "Small Silk Pack", 4245, "Small Silk Pack", 1, 75, "tailoring", 150, 3813, nil, nil, "Kzixx", "Duskwood", 81.8, 19.8, "trainer", 0, "", "", "", "", 0)
addWrit(264055, 94255, "Spider Silk Slippers", 4321, "Spider Silk Slippers", 1, 75, "tailoring", 140, 3856, nil, nil, "Kixxle", "Wetlands", 50.3, 37.8, "ah", 4350, "Pattern: Spider Silk Slippers", "", "", "", 0)
addWrit(264081, 94281, "Advanced Target Dummy", 4392, "Advanced Target Dummy", 1, 125, "engineering", 185, 3965, nil, nil, "Bibbly F'utzbuckle", "Desolace", 62.33, 38.99, "trainer", 0, "", "", "", "", 0)
addWrit(264100, 94300, "Big Voodoo Mask", 8201, "Big Voodoo Mask", 1, 125, "leatherworking", 220, 10531, nil, nil, "Mukomonji", "Swamp of Sorrows", 60.5, 52.1, "ah", 8387, "Pattern: Big Voodoo Mask", "", "", "", 0)
addWrit(264101, 94301, "Big Voodoo Robe", 8200, "Big Voodoo Robe", 1, 125, "leatherworking", 215, 10520, nil, nil, "Yeh'kinya", "Tanaris", 66.99, 22.36, "ah", 8386, "Pattern: Big Voodoo Robe", "", "", "", 0)
addWrit(264110, 94310, "Black Mageweave Vest", 9998, "Black Mageweave Vest", 1, 125, "tailoring", 205, 12048, nil, nil, "Spek", "Riverglades", 76.89, 54.15, "trainer", 0, "", "", "", "", 0)
addWrit(264072, 94272, "Blue Glittering Axe", 7942, "Blue Glittering Axe", 1, 125, "blacksmithing", 220, 9995, nil, nil, "Scout Raroul", "Feralas", 72.4, 52.2, "ah", 7992, "Plans: Blue Glittering Axe", "", "", "", 0)
addWrit(264060, 94260, "Catseye Draught", 10592, "Catseye Elixir", 1, 125, "alchemy", 200, 12609, nil, nil, "Scout Raroul", "Feralas", 72.4, 52.2, "trainer", 0, "", "", "", "", 0)
addWrit(264084, 94284, "Catseye Ultra Goggles", 10501, "Catseye Ultra Goggles", 1, 125, "engineering", 220, 12607, nil, nil, "Scout Raroul", "Feralas", 72.4, 52.2, "ah", 10603, "Schematic: Catseye Ultra Goggles", "", "", "", 0)
addWrit(264114, 94314, "Cindercloth Robe", 10042, "Cindercloth Robe", 1, 125, "tailoring", 225, 12069, nil, nil, "Atal'ai Exile", "The Hinterlands", 33.75, 75.21, "trainer", 0, "", "", "", "", 0)
addWrit(264092, 94292, "Comfortable Leather Hat", 8174, "Comfortable Leather Hat", 1, 125, "leatherworking", 200, 10490, nil, nil, "Garek", "Badlands", 61.8, 54.2, "ah", 8384, "Pattern: Comfortable Leather Hat", "", "", "", 0)
addWrit(264082, 94282, "Craftsman's Monocle", 4393, "Craftsman's Monocle", 1, 125, "engineering", 185, 3966, nil, nil, "The Ravenous", "Dustwallow Marsh", 54.0, 56.48, "ah", 4415, "Schematic: Craftsman's Monocle", "", "", "", 0)
addWrit(264106, 94306, "Crimson Silk Robe", 7063, "Crimson Silk Robe", 1, 125, "tailoring", 205, 8802, nil, nil, "Tabetha", "Dustwallow Marsh", 46.06, 57.09, "vendor", 7088, "Pattern: Crimson Silk Robe", "Vizzklick, Stitch Pinwizzle", "Vizzklick, Stitch Pinwizzle", "Vizzklick, Stitch Pinwizzle", 5000)
addWrit(264091, 94291, "Dark Iron Bomb", 16005, "Dark Iron Bomb", 1, 125, "engineering", 285, 19799, nil, nil, "Gibbert", "Un'Goro Crater", 44.1, 7.19, "ah", 16049, "Schematic: Dark Iron Bomb", "", "", "", 0)
addWrit(264094, 94294, "Dusky Bracers", 7378, "Dusky Bracers", 1, 125, "leatherworking", 185, 9201, nil, nil, "The Ravenous", "Dustwallow Marsh", 54.0, 56.48, "trainer", 0, "", "", "", "", 0)
addWrit(264115, 94315, "Earthen Silk Belt", 7061, "Earthen Silk Belt", 1, 125, "tailoring", 195, 8797, nil, nil, "Petra Grossen", "Un'Goro Crater", 43.7, 7.24, "ah", 7086, "Pattern: Earthen Silk Belt", "", "", "", 0)
addWrit(264066, 94266, "Elixir of Agility", 8949, "Elixir of Agility", 1, 125, "alchemy", 185, 11449, nil, nil, "Juo", "The Hinterlands", 80.1, 55.4, "trainer", 0, "", "", "", "", 0)
addWrit(264108, 94308, "Enchanted Mageweave Pouch", 22246, "Enchanted Mageweave Pouch", 1, 125, "tailoring", 225, 27658, nil, nil, "Impsy", "Felwood", 41.36, 45.02, "vendor_ah", 22307, "Pattern: Enchanted Mageweave Pouch", "Jessara Cordell, Vaean", "Nata Dawnstrider, Kithas", "Jessara Cordell [A], Nata Dawnstrider [H]", 6000)
addWrit(264087, 94287, "Fire Goggles", 10500, "Fire Goggles", 1, 125, "engineering", 205, 12594, nil, nil, "Durganon", "Searing Gorge", 41.1, 58.3, "trainer", 0, "", "", "", "", 0)
addWrit(264063, 94263, "Fire Protection Potion", 6049, "Fire Protection Potion", 1, 125, "alchemy", 165, 7257, nil, nil, "Durganon", "Searing Gorge", 41.1, 58.3, "vendor", 6055, "Recipe: Fire Protection Potion", "Nandar Branson", "Jeeda", "Nandar Branson [A], Jeeda [H]", 1500)
addWrit(264086, 94286, "Flash Bomb", 4852, "Flash Bomb", 1, 125, "engineering", 185, 8243, nil, nil, "Spek", "Riverglades", 76.89, 54.15, "ah", 6672, "Schematic: Flash Bomb", "", "", "", 0)
addWrit(264056, 94256, "Frost Protection Potion", 6050, "Frost Protection Potion", 1, 125, "alchemy", 190, 7258, nil, nil, "Lotwil Veriatus", "Badlands", 25.9, 44.9, "vendor", 6056, "Recipe: Frost Protection Potion", "Drovnar Strongbrew, Glyx Brewright", "Glyx Brewright", "Drovnar Strongbrew [A], Glyx Brewright", 2000)
addWrit(264083, 94283, "Goblin Land Mine", 4395, "Goblin Land Mine", 1, 125, "engineering", 195, 3968, nil, nil, "Jessir Moonbow", "Felwood", 51.35, 82.01, "ah", 4416, "Schematic: Goblin Land Mine", "", "", "", 0)
addWrit(264065, 94265, "Goblin Rocket Fuel", 9061, "Goblin Rocket Fuel", 1, 125, "alchemy", 210, 11456, 1, {{9260,1},{4625,1},{3372,1}}, "Alchemist Pestlezugg", "Tanaris", 50.9, 27, "ah", 10644, "Recipe: Goblin Rocket Fuel", "", "", "", 0)
addWrit(264074, 94274, "Golden Scale Coif", 3837, "Golden Scale Coif", 1, 125, "blacksmithing", 190, 3503, nil, nil, "Spek", "Riverglades", 76.89, 54.15, "vendor", 6047, "Plans: Golden Scale Coif", "Krinkle Goodsteel", "Krinkle Goodsteel", "Krinkle Goodsteel", 4400)
addWrit(264078, 94278, "Golden Scale Gauntlets", 9366, "Golden Scale Gauntlets", 1, 125, "blacksmithing", 205, 11643, nil, nil, "Gilveradin Sunchaser", "The Hinterlands", 26.71, 48.59, "ah", 9367, "Plans: Golden Scale Gauntlets", "", "", "", 0)
addWrit(264061, 94261, "Great Rage Potion", 5633, "Great Rage Potion", 1, 125, "alchemy", 175, 6618, nil, nil, "Dendrite Starblaze", "Moonglade", 56.21, 30.64, "vendor_ah", 5643, "Recipe: Great Rage Potion", "Ulthir", "Hagrus", "Hagrus [H], Ulthir [A]", 2000)
addWrit(264093, 94293, "Guardian Cloak", 5965, "Guardian Cloak", 1, 125, "leatherworking", 185, 7153, nil, nil, "Azore Aldamort", "Desolace", 38.88, 27.16, "ah", 5974, "Pattern: Guardian Cloak", "", "", "", 0)
addWrit(264089, 94289, "Gyromatic Micro-Adjuster", 10498, "Gyromatic Micro-Adjustor", 1, 125, "engineering", 175, 12590, nil, nil, "Jhordy Lapforge", "Tanaris", 52.3, 26.89, "trainer", 0, "", "", "", "", 0)
addWrit(264079, 94279, "Heavy Mithril Axe", 7941, "Heavy Mithril Axe", 1, 125, "blacksmithing", 210, 9993, nil, nil, "Torwa Pathfinder", "Un'Goro Crater", 71.64, 75.96, "trainer", 0, "", "", "", "", 0)
addWrit(264069, 94269, "Inlaid Mithril Cylinder", 9060, "Inlaid Mithril Cylinder", 1, 125, "blacksmithing", 200, 11454, nil, nil, "Bibbly F'utzbuckle", "Desolace", 62.33, 38.99, "ah", 10713, "Plans: Inlaid Mithril Cylinder", "", "", "", 0)
addWrit(264057, 94257, "Lesser Invisibility Potion", 3823, "Lesser Invisibility Potion", 1, 125, "alchemy", 165, 3448, nil, nil, "Centaur Pariah", "Desolace", 50.42, 86.65, "trainer", 0, "", "", "", "", 0)
addWrit(264058, 94258, "Lesser Stoneshield Potion", 4623, "Lesser Stoneshield Potion", 1, 125, "alchemy", 215, 4942, nil, nil, "Mudcrush Durtfeet", "Dustwallow Marsh", 35.15, 38.26, "ah", 4624, "Recipe: Lesser Stoneshield Potion", "", "", "", 0)
addWrit(264104, 94304, "Mageweave Bag", 10050, "Mageweave Bag", 1, 125, "tailoring", 225, 12065, nil, nil, "Rigglefuzz", "Badlands", 42.39, 52.93, "trainer", 0, "", "", "", "", 0)
addWrit(264062, 94262, "Mana Potion", 3827, "Mana Potion", 1, 125, "alchemy", 160, 3452, nil, nil, "Spek", "Riverglades", 76.89, 54.15, "trainer", 0, "", "", "", "", 0)
addWrit(264080, 94280, "Mechanical Dragonling", 4396, "Mechanical Dragonling", 1, 125, "engineering", 200, 3969, nil, nil, "Garyanne Fleezlebop", "Badlands", 67.69, 51.7, "vendor_ah", 13311, "Schematic: Mechanical Dragonling", "Gnaz Blunderflame", "Gnaz Blunderflame", "Gnaz Blunderflame", 10000)
addWrit(264090, 94290, "Mechanical Repair Kit", 11590, "Mechanical Repair Kit", 1, 125, "engineering", 200, 15255, nil, nil, "Rhapsody Shindigger", "The Hinterlands", 26.9, 48.6, "trainer", 0, "", "", "", "", 0)
addWrit(264088, 94288, "Mithril Frag Bomb", 10514, "Mithril Frag Bomb", 1, 125, "engineering", 215, 12603, nil, nil, "Bullets Bigblast", "Swamp of Sorrows", 69.9, 41.7, "trainer", 0, "", "", "", "", 0)
addWrit(264073, 94273, "Moonsteel Broadsword", 3853, "Moonsteel Broadsword", 1, 125, "blacksmithing", 180, 3496, nil, nil, "Meliri", "Moonglade", 51.18, 42.31, "vendor", 12163, "Plans: Moonsteel Broadsword", "Zarena Cromwind", "Zarena Cromwind", "Zarena Cromwind", 4400)
addWrit(264059, 94259, "Nature Protection Potion", 6052, "Nature Protection Potion", 1, 125, "alchemy", 190, 7259, nil, nil, "Greta Mosshoof", "Felwood", 51.1, 82.2, "vendor", 6057, "Recipe: Nature Protection Potion", "Logannas, Glyx Brewright", "Bronk, Glyx Brewright", "Glyx Brewright, Alchemist Pestlezugg", 2000)
addWrit(264099, 94299, "Nightscape Shoulders", 8192, "Nightscape Shoulders", 1, 125, "leatherworking", 210, 10516, nil, nil, "Evonice Sootsmoker", "Searing Gorge", 38.35, 27.74, "vendor", 8409, "Pattern: Nightscape Shoulders", "Nioma", "Jangdor Swiftstrider", "Jangdor Swiftstrider [H], Nioma [A]", 4000)
addWrit(264112, 94312, "Orange Martial Shirt", 10052, "Orange Martial Shirt", 1, 125, "tailoring", 220, 12064, nil, nil, "Bullets Bigblast", "Swamp of Sorrows", 69.9, 41.7, "vendor_ah", 10311, "Pattern: Orange Martial Shirt", "Elynna", "Mahu", "Mahu [H], Elynna [A]", 3000)
addWrit(264071, 94271, "Ornate Mithril Shoulders", 7928, "Ornate Mithril Shoulders", 1, 125, "blacksmithing", 225, 9952, nil, nil, "Taronn Redfeather", "Felwood", 50.89, 81.62, "trainer", 0, "", "", "", "", 0)
addWrit(264097, 94297, "Quickdraw Quiver", 8217, "Quickdraw Quiver", 1, 125, "leatherworking", 225, 14930, nil, nil, "Narianna", "Moonglade", 53.34, 42.7, "trainer", 0, "", "", "", "", 0)
addWrit(264111, 94311, "Red Mageweave Pants", 10009, "Red Mageweave Pants", 1, 125, "tailoring", 215, 12060, nil, nil, "Lookout Captain Lolo Longstriker", "Searing Gorge", 37.74, 26.56, "ah", 10302, "Pattern: Red Mageweave Pants", "", "", "", 0)
addWrit(264064, 94264, "Shadow Oil", 3824, "Shadow Oil", 1, 125, "alchemy", 165, 3449, 1, {{3818,4},{3369,4},{3372,1}}, "Mukomonji", "Swamp of Sorrows", 60.5, 52.1, "vendor", 6068, "Recipe: Shadow Oil", "Bliztik", "Montarr, Bliztik", "Bliztik, Montarr [H]", 1500)
addWrit(264105, 94305, "Shadoweave Gloves", 10023, "Shadoweave Gloves", 1, 125, "tailoring", 225, 12071, nil, nil, "Willow", "Desolace", 62.2, 39.63, "trainer", 0, "", "", "", "", 0)
addWrit(264107, 94307, "Shadoweave Robe", 10004, "Shadoweave Robe", 1, 125, "tailoring", 215, 12055, nil, nil, "Eridan Bluewind", "Felwood", 51.35, 81.51, "trainer", 0, "", "", "", "", 0)
addWrit(264075, 94275, "Solid Sharpening Stone", 7964, "Solid Sharpening Stone", 1, 125, "blacksmithing", 200, 9918, nil, nil, "Master Smith Burninate", "Searing Gorge", 38.8, 28.51, "trainer", 0, "", "", "", "", 0)
addWrit(264109, 94309, "Star Belt", 4329, "Star Belt", 1, 125, "tailoring", 200, 3864, nil, nil, "Mylentha Riverbend", "Moonglade", 51.77, 32.58, "ah", 4356, "Pattern: Star Belt", "", "", "", 0)
addWrit(264068, 94268, "Steel Plate Helm", 7922, "Steel Plate Helm", 1, 125, "blacksmithing", 215, 9935, nil, nil, "Furious Shadowforge Digger", "Badlands", 44.29, 11.42, "trainer", 0, "", "", "", "", 0)
addWrit(264070, 94270, "Steel Weapon Chain", 6041, "Steel Weapon Chain", 1, 125, "blacksmithing", 190, 7224, nil, nil, "Ugbert", "Dustwallow Marsh", 40.9, 28, "ah", 6046, "Plans: Steel Weapon Chain", "", "", "", 0)
addWrit(264098, 94298, "Swift Boots", 7391, "Swift Boots", 1, 125, "leatherworking", 200, 9208, nil, nil, "Spek", "Riverglades", 76.89, 54.15, "ah", 7453, "Pattern: Swift Boots", "", "", "", 0)
addWrit(264103, 94303, "Thick Leather Ammo Pouch", 8218, "Thick Leather Ammo Pouch", 1, 125, "leatherworking", 225, 14932, nil, nil, "Nergal", "Un'Goro Crater", 43.27, 7.73, "trainer", 0, "", "", "", "", 0)
addWrit(264077, 94277, "Truesilver Rod", 11144, "Truesilver Rod", 1, 125, "blacksmithing", 200, 14380, nil, nil, "Spigot Operator Luglunket", "Tanaris", 52.49, 28.45, "trainer", 0, "", "", "", "", 0)
addWrit(264102, 94302, "Turtle Scale Breastplate", 8189, "Turtle Scale Breastplate", 1, 125, "leatherworking", 210, 10511, nil, nil, "Juo", "The Hinterlands", 80.1, 55.4, "trainer", 0, "", "", "", "", 0)
addWrit(264085, 94285, "Unstable Trigger", 10560, "Unstable Trigger", 1, 125, "engineering", 200, 12591, nil, nil, "Narianna", "Moonglade", 53.34, 42.7, "trainer", 0, "", "", "", "", 0)
addWrit(264113, 94313, "White Bandit Mask", 10008, "White Bandit Mask", 1, 125, "tailoring", 215, 12059, nil, nil, "Vizzklick", "Tanaris", 51.01, 27.36, "ah", 10301, "Pattern: White Bandit Mask", "", "", "", 0)
addWrit(264076, 94276, "Wicked Mithril Blade", 7943, "Wicked Mithril Blade", 1, 125, "blacksmithing", 225, 9997, nil, nil, "Mukomonji", "Swamp of Sorrows", 62.39, 52.85, "ah", 8029, "Plans: Wicked Mithril Blade", "", "", "", 0)
addWrit(264095, 94295, "Wild Leather Helmet", 8214, "Wild Leather Helmet", 1, 125, "leatherworking", 225, 10546, nil, nil, "Ivy Leafrunner", "Felwood", 50.96, 81.58, "quest", 8405, "Pattern: Wild Leather Helmet", "", "", "", 0)
addWrit(264096, 94296, "Wild Leather Shoulders", 8210, "Wild Leather Shoulders", 1, 125, "leatherworking", 220, 10529, nil, nil, "Scout Raroul", "Feralas", 72.4, 52.2, "quest", 8403, "Pattern: Wild Leather Shoulders", "", "", "", 0)
addWrit(264067, 94267, "Wildvine Potion", 9144, "Wildvine Potion", 1, 125, "alchemy", 225, 11458, nil, nil, "Spark Nilminer", "Un'Goro Crater", 43.5, 7.42, "ah", 9294, "Recipe: Wildvine Potion", "", "", "", 0)
addWrit(264132, 94332, "Arcanite Skeleton Key", 15872, "Arcanite Skeleton Key", 1, 200, "blacksmithing", 275, 19669, nil, nil, "", "", 0, 0, "ah", 0, "", "", "", "", 0)
addWrit(264157, 94357, "Cenarion Herb Bag", 22251, "Cenarion Herb Bag", 1, 200, "tailoring", 275, 27724, nil, nil, "", "", 0, 0, "vendor", 22310, "Pattern: Cenarion Herb Bag", "Mishta", "Mishta", "Mishta", 20000)
addWrit(264148, 94348, "Chimeric Vest", 15075, "Chimeric Vest", 1, 200, "leatherworking", 290, 19081, nil, nil, "Earthcaller Franzahl", "Winterspring", 53.98, 90.39, "ah", 15755, "Pattern: Chimeric Vest", "", "", "", 0)
addWrit(264130, 94330, "Darkrune Gauntlets", 20549, "Darkrune Gauntlets", 1, 200, "blacksmithing", 300, 24912, nil, nil, "", "", 0, 0, "ah", 20553, "Plans: Darkrune Gauntlets", "", "", "", 0)
addWrit(264124, 94324, "Distilled Firewater", 246948, "Distilled Firewater", 1, 200, "alchemy", 250, 236754, nil, nil, "Bor'dorc", "Winterspring", 64.84, 33.22, "ah", 236754, "Recipe: Distilled Firewater", "", "", "", 0)
addWrit(264119, 94319, "Draught of Detect Demon", 9233, "Elixir of Detect Demon", 1, 200, "alchemy", 250, 11478, nil, nil, "Hastings", "Deadwind Pass", 46.99, 75.32, "trainer", 0, "", "", "", "", 0)
addWrit(264117, 94317, "Dreamless Sleep Potion", 12190, "Dreamless Sleep Potion", 1, 200, "alchemy", 230, 15833, nil, nil, "Kum'isha the Collector", "Blasted Lands", 51.98, 35.65, "trainer", 0, "", "", "", "", 0)
addWrit(264133, 94333, "Ebon Shiv", 7947, "Ebon Shiv", 1, 200, "blacksmithing", 255, 10013, nil, nil, "Xizzer Fizzbolt", "Winterspring", 60.8, 38.6, "vendor", 8030, "Plans: Ebon Shiv", "Magnus Frostwake", "Magnus Frostwake", "Magnus Frostwake", 10000)
addWrit(264156, 94356, "Felcloth Boots", 14108, "Felcloth Boots", 1, 200, "tailoring", 285, 18437, nil, nil, "Egan", "Eastern Plaguelands", 11.36, 26.6, "ah", 14492, "Pattern: Felcloth Boots", "", "", "", 0)
addWrit(264139, 94339, "Field Repair Bot 74A", 18232, "Field Repair Bot 74A", 1, 200, "engineering", 300, 22704, nil, nil, "", "", 0, 0, "quest", 0, "", "Scroll on floor near Golem Lord Argelmach (BRD)", "Scroll on floor near Golem Lord Argelmach (BRD)", "Scroll on floor near Golem Lord Argelmach (BRD)", 0)
addWrit(264121, 94321, "Flask of Chromatic Resistance", 13513, "Flask of Chromatic Resistance", 1, 200, "alchemy", 300, 17638, nil, nil, "", "", 0, 0, "ah", 13522, "Recipe: Flask of Chromatic Resistance", "", "", "", 0)
addWrit(264151, 94351, "Frostsaber Boots", 15071, "Frostsaber Boots", 1, 200, "leatherworking", 275, 19066, nil, nil, "", "", 0, 0, "vendor", 15740, "Pattern: Frostsaber Boots", "Qia", "Qia", "Qia", 16000)
addWrit(264159, 94359, "Ghostweave Vest", 14141, "Ghostweave Vest", 1, 200, "tailoring", 275, 18416, nil, nil, "", "", 0, 0, "ah", 14480, "Pattern: Ghostweave Vest", "", "", "", 0)
addWrit(264120, 94320, "Gift of Arthas", 9088, "Gift of Arthas", 1, 200, "alchemy", 240, 11466, nil, nil, "Adon", "Eastern Plaguelands", 50.92, 11.48, "ah", 9296, "Recipe: Gift of Arthas", "", "", "", 0)
addWrit(264137, 94337, "Gnomish Alarm-O-Bot", 18645, "Gnomish Alarm-O-Bot", 1, 200, "engineering", 265, 23096, nil, nil, "", "", 0, 0, "ah", 18654, "Schematic: Gnomish Alarm-O-Bot", "", "", "", 0)
addWrit(264138, 94338, "Goblin Jumper Cables XL", 18587, "Goblin Jumper Cables XL", 1, 200, "engineering", 265, 23078, nil, nil, "", "", 0, 0, "ah", 18653, "Schematic: Goblin Jumper Cables XL", "", "", "", 0)
addWrit(264144, 94344, "Gordok Ogre Suit", 18258, "Gordok Ogre Suit", 1, 200, "tailoring", 285, 22813, nil, nil, "", "", 0, 0, "quest", 0, "", "Quest: The Gordok Ogre Suit (Dire Maul North)", "Quest: The Gordok Ogre Suit (Dire Maul North)", "Quest: The Gordok Ogre Suit (Dire Maul North)", 0)
addWrit(264118, 94318, "Greater Fire Protection Potion", 13457, "Greater Fire Protection Potion", 1, 200, "alchemy", 290, 17574, nil, nil, "Gorzeeki Wildeyes", "Burning Steppes", 12.44, 31.63, "ah", 13494, "Recipe: Greater Fire Protection Potion", "", "", "", 0)
addWrit(264135, 94335, "Green Lens", 10504, "Green Lens", 1, 200, "engineering", 245, 12622, nil, nil, "Kum'isha the Collector", "Blasted Lands", 51.98, 35.65, "trainer", 0, "", "", "", "", 0)
addWrit(264149, 94349, "Heavy Scorpid Helm", 15080, "Heavy Scorpid Helm", 1, 200, "leatherworking", 295, 19088, nil, nil, "", "", 0, 0, "vendor", 15762, "Pattern: Heavy Scorpid Helm", "Zannok Hidepiercer", "Zannok Hidepiercer", "Zannok Hidepiercer", 25000)
addWrit(264131, 94331, "Huge Thorium Battleaxe", 12775, "Huge Thorium Battleaxe", 1, 200, "blacksmithing", 280, 16971, nil, nil, "", "", 0, 0, "vendor", 12823, "Plans: Huge Thorium Battleaxe", "Magnus Frostwake", "Magnus Frostwake", "Magnus Frostwake", 20000)
addWrit(264129, 94329, "Imperial Plate Chest", 12422, "Imperial Plate Chest", 1, 200, "blacksmithing", 300, 16663, nil, nil, "", "", 0, 0, "quest", 12705, "Plans: Imperial Plate Chest", "", "", "", 0)
addWrit(264136, 94336, "Lifelike Mechanical Toad", 15996, "Lifelike Mechanical Toad", 1, 200, "engineering", 265, 19793, nil, nil, "Ugkragg", "Burning Steppes", 38.33, 35.47, "ah", 16044, "Schematic: Lifelike Mechanical Toad", "", "", "", 0)
addWrit(264122, 94322, "Limited Invulnerability Potion", 3387, "Limited Invulnerability Potion", 1, 200, "alchemy", 250, 3175, nil, nil, "Jarund Stoutstrider", "Silithus", 82.05, 18.08, "ah", 3395, "Recipe: Limited Invulnerability Potion", "", "", "", 0)
addWrit(264123, 94323, "Major Rejuvenation Potion", 18253, "Major Rejuvenation Potion", 1, 200, "alchemy", 300, 22732, nil, nil, "Kirala Fairgrass", "Western Plaguelands", 59.57, 53.15, "ah", 18257, "Recipe: Major Rejuvenation Potion", "", "", "", 0)
addWrit(264134, 94334, "Masterwork Target Dummy", 16023, "Masterwork Target Dummy", 1, 200, "engineering", 275, 19814, nil, nil, "Rayan Dawnrisen", "Azshara", 30.01, 40.18, "vendor", 16046, "Schematic: Masterwork Target Dummy", "Xizzer Fizzbolt, Kor'gar", "Xizzer Fizzbolt, Kor'gar", "Xizzer Fizzbolt, Kor'gar", 16000)
addWrit(264128, 94328, "Mithril Spurs", 7969, "Mithril Spurs", 1, 200, "blacksmithing", 235, 9964, nil, nil, "Calliard", "Deadwind Pass", 48.35, 68.72, "ah", 7989, "Plans: Mithril Spurs", "", "", "", 0)
addWrit(264127, 94327, "Orcish War Leggings", 7929, "Orcish War Leggings", 1, 200, "blacksmithing", 230, 9957, nil, nil, "Ugkragg", "Burning Steppes", 38.33, 35.47, "trainer", 0, "", "", "", "", 0)
addWrit(264116, 94316, "Potion of Demonslaying", 9224, "Elixir of Demonslaying", 1, 200, "alchemy", 250, 11477, nil, nil, "Archmage Xylem", "Azshara", 29.25, 40.21, "vendor", 9300, "Recipe: Elixir of Demonslaying", "Nina Lightbrew", "Rartar", "Rartar [H], Nina Lightbrew [A]", 10000)
addWrit(264126, 94326, "Radiant Belt", 12416, "Radiant Belt", 1, 200, "blacksmithing", 260, 16645, nil, nil, "Kum'isha the Collector", "Blasted Lands", 51.98, 35.65, "ah", 12685, "Plans: Radiant Belt", "", "", "", 0)
addWrit(264125, 94325, "Radiant Circlet", 12417, "Radiant Circlet", 1, 200, "blacksmithing", 295, 16659, nil, nil, "", "", 0, 0, "ah", 12702, "Plans: Radiant Circlet", "", "", "", 0)
addWrit(264153, 94353, "Runecloth Bag", 14046, "Runecloth Bag", 1, 200, "tailoring", 260, 18405, nil, nil, "Kum'isha the Collector", "Blasted Lands", 51.98, 35.65, "vendor_ah", 14468, "Pattern: Runecloth Bag", "Qia", "Qia", "Qia", 12000)
addWrit(264154, 94354, "Runecloth Boots", 13864, "Runecloth Boots", 1, 200, "tailoring", 280, 18423, nil, nil, "Gorzeeki Wildeyes", "Burning Steppes", 12.44, 31.63, "vendor", 14488, "Pattern: Runecloth Boots", "Darnall", "Darnall", "Darnall", 20000)
addWrit(264150, 94350, "Runic Leather Bracers", 15092, "Runic Leather Bracers", 1, 200, "leatherworking", 275, 19065, nil, nil, "Fallen Adventurer", "Western Plaguelands", 38.2, 72.41, "ah", 15739, "Pattern: Runic Leather Bracers", "", "", "", 0)
addWrit(264146, 94346, "Runic Leather Headband", 15094, "Runic Leather Headband", 1, 200, "leatherworking", 290, 19082, nil, nil, "Hastings", "Deadwind Pass", 46.99, 75.32, "vendor", 15756, "Pattern: Runic Leather Headband", "Jase Farlane", "Jase Farlane", "Jase Farlane", 22000)
addWrit(264158, 94358, "Shadoweave Mask", 10025, "Shadoweave Mask", 1, 200, "tailoring", 245, 12086, nil, nil, "Hermit Ortell", "Silithus", 67.19, 69.76, "quest", 10463, "Pattern: Shadoweave Mask", "", "", "", 0)
addWrit(264141, 94341, "Sniper Scope", 10548, "Sniper Scope", 1, 200, "engineering", 240, 12620, nil, nil, "Suspicious Adventurer", "Western Plaguelands", 65.74, 76.1, "ah", 10608, "Schematic: Sniper Scope", "", "", "", 0)
addWrit(264160, 94360, "Soul Pouch", 21340, "Soul Pouch", 1, 200, "tailoring", 260, 26085, nil, nil, "Zelizax", "Winterspring", 57.62, 88.08, "vendor_ah", 21358, "Pattern: Soul Pouch", "Vizzklick, Stitch Pinwizzle", "Vizzklick, Stitch Pinwizzle", "Vizzklick, Stitch Pinwizzle", 12000)
addWrit(264142, 94342, "Tranquil Mechanical Yeti", 21277, "Tranquil Mechanical Yeti", 1, 200, "engineering", 250, 26011, nil, nil, "", "", 0, 0, "trainer", 0, "", "", "", "", 0)
addWrit(264140, 94340, "Truesilver Transformer", 18631, "Truesilver Transformer", 1, 200, "engineering", 260, 23071, nil, nil, "Khur Hornstriker", "Silithus", 48.67, 37.0, "vendor", 18651, "Schematic: Truesilver Transformer", "Mazk Snipeshot", "Mazk Snipeshot", "Mazk Snipeshot", 12000)
addWrit(264155, 94355, "Tuxedo Jacket", 10036, "Tuxedo Jacket", 1, 200, "tailoring", 250, 12093, nil, nil, "Hastings", "Deadwind Pass", 46.99, 75.32, "vendor_ah", 10326, "Pattern: Tuxedo Jacket", "Outfitter Eric", "Millie Gregorian", "Millie Gregorian [H], Outfitter Eric [A]", 5000)
addWrit(264145, 94345, "Volcanic Breastplate", 15053, "Volcanic Breastplate", 1, 200, "leatherworking", 285, 19076, nil, nil, "", "", 0, 0, "ah", 15749, "Pattern: Volcanic Breastplate", "", "", "", 0)
addWrit(264147, 94347, "Wicked Leather Bracers", 15084, "Wicked Leather Bracers", 1, 200, "leatherworking", 265, 19052, nil, nil, "Quartermaster Miranda Breechlock", "Eastern Plaguelands", 71.79, 50.25, "ah", 15728, "Pattern: Wicked Leather Bracers", "", "", "", 0)
addWrit(264143, 94343, "Wicked Leather Pants", 15087, "Wicked Leather Pants", 1, 200, "leatherworking", 290, 19083, nil, nil, "", "", 0, 0, "ah", 15757, "Pattern: Wicked Leather Pants", "", "", "", 0)
addWrit(264152, 94352, "Wizardweave Turban", 14130, "Wizardweave Turban", 1, 200, "tailoring", 300, 18450, nil, nil, "Joy Ar'nareth", "Azshara", 30.02, 40.14, "ah", 14505, "Pattern: Wizardweave Turban", "", "", "", 0)


-- All 45 Journeyman and 60 Expert writs have confirmed turn-in NPCs above.
-- Artisan writs use 9 zone slots across each profession block:
-- Azshara, Blasted Lands, Burning Steppes, Deadwind Pass, Eastern Plaguelands,
-- [Slot 5 unhinted: Hyjal-border/unconfirmed], Silithus, Western Plaguelands, Winterspring.
-- These 13 zone-only hints stay unconfirmed until a completed turn-in is observed in play.
ns.WRIT_ZONE_HINTS = {
	[264125] = "Azshara",             -- Radiant Circlet
	[264129] = "Eastern Plaguelands", -- Imperial Plate Chest
	[264131] = "Silithus",            -- Huge Thorium Battleaxe
	[264132] = "Western Plaguelands", -- Arcanite Skeleton Key
	[264137] = "Deadwind Pass",       -- Gnomish Alarm-O-Bot
	[264138] = "Eastern Plaguelands", -- Goblin Jumper Cables XL
	[264142] = "Winterspring",        -- Tranquil Mechanical Yeti
	[264143] = "Azshara",             -- Wicked Leather Pants
	[264144] = "Blasted Lands",       -- Gordok Ogre Suit
	[264145] = "Burning Steppes",     -- Volcanic Breastplate
	[264149] = "Silithus",            -- Heavy Scorpid Helm
	[264151] = "Winterspring",        -- Frostsaber Boots
	[264159] = "Western Plaguelands", -- Ghostweave Vest
}
