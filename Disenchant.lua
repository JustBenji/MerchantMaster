-- MerchantMaster: Disenchanting Rules, Probabilities, Blacklist, Metadata Fallback & Live Learner
-- Ported 1-for-1 from TradeSkillMaster LibTSMData (DATA.Forever + NonDisenchantable.All)
-- with:
--   * Classic/Wowhead weapon Astral Essence bracket fix (ilvl 21-25 -> 10998, 26-30 -> 11082)
--   * Symmetric low-ilvl rare weapon bracket (ilvl 5-15 -> Strange Dust / Lesser Magic Essence)
--   * WoW: Forever DB2 ITEM_FLAG_NO_DISENCHANT (0x8000) crafted wands & non-DE catalog additions
--   * Classic/Forever eligibility parity (Held-in-Off-Hand eligible; Cosmetic armor, Fishing Poles, Thrown, Trinkets, Shirts, Tabards excluded; no ilvl skill gate in Forever)
--   * Static craftable metadata fallback (ns.DE_ITEM_META -> MerchantMasterDB.deItemMetaCache)
--   * Live Disenchant Learner with Arcane Salvager normalization & Bayesian shrinkage (w = casts / (casts + 10) once casts >= 3)

local _, ns = ...

do
	local function readable(v)
		return not (issecretvalue and issecretvalue(v))
			and not (type(v) == "table" and issecrettable and issecrettable(v))
	end

	local function isFiniteNumber(v)
		return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
	end

	local QUALITY_HEX = {
		[1] = "|cffffffff",
		[2] = "|cff1eff00",
		[3] = "|cff0070dd",
		[4] = "|cffa335ee",
	}

	local QUALITY_NAMES = {
		[2] = "Uncommon",
		[3] = "Rare",
		[4] = "Epic",
	}

	-- Arcane Salvager (WoW: Forever item 279985, Boosted Disenchanting camp utility): +20% expected extra loot
	ns.DE_ARCANE_SALVAGER_ITEM_ID = 279985
	ns.DE_ARCANE_SALVAGER_BONUS = 0.20

	function ns.IsArcaneSalvagerActive(explicitOverride)
		if explicitOverride ~= nil then
			return explicitOverride == true
		end
		local itemSpellName, itemSpellID
		local getItemSpell = (_G.C_Item and _G.C_Item.GetItemSpell) or _G.GetItemSpell
		if type(getItemSpell) == "function" and ns.DE_ARCANE_SALVAGER_ITEM_ID then
			local okS, sName, sID = pcall(getItemSpell, ns.DE_ARCANE_SALVAGER_ITEM_ID)
			if okS and readable(sName) and type(sName) == "string" and sName ~= "" then
				itemSpellName = sName:lower()
			end
			if okS and readable(sID) and type(sID) == "number" and sID > 0 then
				itemSpellID = sID
			end
		end
		local function matchesAS(name, spellID)
			if itemSpellID and readable(spellID) and spellID == itemSpellID then
				return true
			end
			if readable(name) and type(name) == "string" and name ~= "" then
				local lo = name:lower()
				if lo:find("arcane salvager", 1, true)
					or lo:find("boosted disenchanting", 1, true)
					or (itemSpellName and lo == itemSpellName) then
					return true
				end
			end
			return false
		end
		local cua = _G.C_UnitAuras
		if type(cua) == "table" then
			if type(cua.GetAuraDataBySpellName) == "function" then
				for _, qName in ipairs({ "Arcane Salvager", "Boosted Disenchanting" }) do
					local okA, data = pcall(cua.GetAuraDataBySpellName, "player", qName, "HELPFUL")
					if okA and type(data) == "table" and readable(data) then
						return true
					end
				end
			end
			if type(cua.GetBuffDataByIndex) == "function" then
				for i = 1, 40 do
					local okA, data = pcall(cua.GetBuffDataByIndex, "player", i)
					if not okA or type(data) ~= "table" or not readable(data) then break end
					if matchesAS(data.name, data.spellId or data.spellID) then
						return true
					end
				end
			elseif type(cua.GetAuraDataByIndex) == "function" then
				for i = 1, 40 do
					local okA, data = pcall(cua.GetAuraDataByIndex, "player", i, "HELPFUL")
					if not okA or type(data) ~= "table" or not readable(data) then break end
					if matchesAS(data.name, data.spellId or data.spellID) then
						return true
					end
				end
			end
		end
		local unitBuff = _G.UnitBuff
		if type(unitBuff) == "function" then
			for i = 1, 40 do
				local okA, name, _, _, _, _, _, _, _, _, spellID = pcall(unitBuff, "player", i)
				if not okA or not readable(name) or name == nil then break end
				if matchesAS(name, spellID) then
					return true
				end
			end
		elseif type(_G.UnitAura) == "function" then
			for i = 1, 40 do
				local okA, name, _, _, _, _, _, _, _, _, spellID = pcall(_G.UnitAura, "player", i, "HELPFUL")
				if not okA or not readable(name) or name == nil then break end
				if matchesAS(name, spellID) then
					return true
				end
			end
		end
		local db = _G.MerchantMasterDB
		if type(db) == "table" and (db.disenchantHelperAS == true or db.disenchantCrafterArcaneSalvager == true) then
			return true
		end
		return false
	end

	-- Bayesian shrinkage parameters for Live Disenchant Learner
	ns.DE_LEARN_MIN_CASTS = 3
	ns.DE_LEARN_PRIOR_WEIGHT = 10

	-- Static metadata for all 24 Vanilla / Forever enchanting materials
	ns.DE_MAT_INFO = {
		-- Dusts (Common)
		[10940] = { name = "Strange Dust", quality = 1, kind = "Dust" },
		[11083] = { name = "Soul Dust", quality = 1, kind = "Dust" },
		[11137] = { name = "Vision Dust", quality = 1, kind = "Dust" },
		[11176] = { name = "Dream Dust", quality = 1, kind = "Dust" },
		[16204] = { name = "Illusion Dust", quality = 1, kind = "Dust" },
		-- Essences (Uncommon)
		[10938] = { name = "Lesser Magic Essence", quality = 2, kind = "Essence" },
		[10939] = { name = "Greater Magic Essence", quality = 2, kind = "Essence" },
		[10998] = { name = "Lesser Astral Essence", quality = 2, kind = "Essence" },
		[11082] = { name = "Greater Astral Essence", quality = 2, kind = "Essence" },
		[11134] = { name = "Lesser Mystic Essence", quality = 2, kind = "Essence" },
		[11135] = { name = "Greater Mystic Essence", quality = 2, kind = "Essence" },
		[11174] = { name = "Lesser Nether Essence", quality = 2, kind = "Essence" },
		[11175] = { name = "Greater Nether Essence", quality = 2, kind = "Essence" },
		[16202] = { name = "Lesser Eternal Essence", quality = 2, kind = "Essence" },
		[16203] = { name = "Greater Eternal Essence", quality = 2, kind = "Essence" },
		-- Shards (Rare)
		[10978] = { name = "Small Glimmering Shard", quality = 3, kind = "Shard" },
		[11084] = { name = "Large Glimmering Shard", quality = 3, kind = "Shard" },
		[11138] = { name = "Small Glowing Shard", quality = 3, kind = "Shard" },
		[11139] = { name = "Large Glowing Shard", quality = 3, kind = "Shard" },
		[11177] = { name = "Small Radiant Shard", quality = 3, kind = "Shard" },
		[11178] = { name = "Large Radiant Shard", quality = 3, kind = "Shard" },
		[14343] = { name = "Small Brilliant Shard", quality = 3, kind = "Shard" },
		[14344] = { name = "Large Brilliant Shard", quality = 3, kind = "Shard" },
		-- Crystals (Epic)
		[20725] = { name = "Nexus Crystal", quality = 4, kind = "Crystal" },
	}

	-- Complete NonDisenchantable blacklist from TSM LibTSMData/Item/NonDisenchantable.lua (196 IDs)
	-- plus WoW: Forever DB2 ItemSparse ITEM_FLAG_NO_DISENCHANT (0x8000) crafted wands & catalog items.
	ns.DE_NON_DISENCHANTABLE = {
		[38] = true, [45] = true, [49] = true, [53] = true, [127] = true, [148] = true, [154] = true,
		[2105] = true, [2575] = true, [2576] = true, [2577] = true, [2579] = true, [2587] = true,
		[3426] = true, [3427] = true, [3428] = true,
		[4330] = true, [4332] = true, [4333] = true, [4334] = true, [4335] = true, [4336] = true, [4344] = true,
		[5107] = true, [6096] = true, [6097] = true, [6117] = true, [6120] = true, [6125] = true, [6134] = true,
		[6136] = true, [6384] = true, [6385] = true, [6795] = true, [6796] = true, [6833] = true,
		[10034] = true, [10052] = true, [10054] = true, [10055] = true, [10056] = true,
		[11287] = true, [11288] = true, [11289] = true, [11290] = true,
		[13347] = true, [16059] = true, [16060] = true, [17723] = true, [18231] = true,
		[20033] = true, [20034] = true, -- Zandalar Robes (DB2 NO_DISENCHANT)
		[20406] = true, [20407] = true, [20408] = true, [20897] = true, [20901] = true, [21766] = true,
		[22749] = true, [22750] = true, -- Sentinel's Pants (DB2 NO_DISENCHANT)
		[23345] = true, [23473] = true, [23476] = true, [24143] = true, [31279] = true,
		[41248] = true, [41249] = true, [41250] = true, [41251] = true, [41252] = true, [41253] = true, [41254] = true, [41255] = true,
		[42360] = true, [42361] = true, [42363] = true, [42365] = true, [42368] = true, [42369] = true, [42370] = true,
		[42371] = true, [42372] = true, [42373] = true, [42374] = true, [42375] = true, [42376] = true, [42377] = true, [42378] = true,
		[44693] = true, [44694] = true,
		[45664] = true, [45666] = true, [45667] = true, [45668] = true, [45669] = true, [45670] = true, [45671] = true, [45672] = true, [45673] = true, [45674] = true,
		[48663] = true, [49567] = true, [52252] = true, [52485] = true, [52486] = true, [52487] = true, [52488] = true, [52548] = true,
		[53852] = true, [60223] = true, [68611] = true, [75274] = true, [84661] = true, [89586] = true,
		[97826] = true, [97827] = true, [97828] = true, [97829] = true, [97830] = true, [97831] = true, [97832] = true,
		[109262] = true, [122604] = true, [127842] = true, [128023] = true, [128024] = true,
		[141408] = true, [151607] = true, [151771] = true, [151772] = true, [152632] = true, [152633] = true, [152635] = true, [152637] = true,
		[167081] = true, [167082] = true,
		[167177] = true, [167178] = true, [167179] = true, [167180] = true, [167181] = true, [167182] = true, [167183] = true, [167184] = true,
		[167185] = true, [167186] = true, [167187] = true, [167188] = true, [167189] = true, [167190] = true, [167191] = true, [167192] = true,
		[167193] = true, [167194] = true, [167195] = true, [167196] = true, [167197] = true,
		[186056] = true, [186058] = true, [186163] = true,
		-- WoW: Forever crafted Enchanting wands (DB2 ItemSparse Flags_0 & 0x8000 = ITEM_FLAG_NO_DISENCHANT)
		[217287] = true, -- Greater Mystic Wand (Forever ID)
		[231955] = true, [231956] = true, [231957] = true, [231958] = true, [231959] = true, [231960] = true, [231961] = true, [231962] = true,
		[231963] = true, [231964] = true, [231965] = true, [231966] = true, [231967] = true, [231968] = true, [231969] = true, [231970] = true,
		[234830] = true, [234831] = true, [234832] = true, [234833] = true, [234834] = true, [234835] = true, [234836] = true, [234837] = true,
		[234881] = true, [234882] = true, [234883] = true, [234884] = true, [234885] = true, [234886] = true, [234887] = true, [234888] = true,
		[234924] = true, [234925] = true, [234926] = true, [234927] = true, [234928] = true, [234929] = true, [234930] = true, [234931] = true,
		[247789] = true, -- Novice's Practice Wand
		[249144] = true, -- Twisted Nether Wand
		[249232] = true, -- Lesser Eternal Wand
		[249234] = true, -- Dreambough Wand
		[249237] = true, -- Greater Eternal Wand
		[249385] = true, -- Brilliant Wand
	}

	-- Excluded equipLocs: non-equippable, cosmetic shirts/tabards, trinkets, containers/ammo, thrown.
	-- Eligible slots include armor pieces, cloaks, shields, rings, necks, relics, weapons, wands (except blacklisted crafted wands), and Held-in-Off-Hand (INVTYPE_HOLDABLE).
	local DE_EXCLUDED_EQUIPLOCS = {
		[""] = true,
		INVTYPE_BODY = true,
		INVTYPE_TABARD = true,
		INVTYPE_TRINKET = true,
		INVTYPE_BAG = true,
		INVTYPE_AMMO = true,
		INVTYPE_QUIVER = true,
		INVTYPE_THROWN = true,
	}

	-- Target-indexed TSM DATA.Forever disenchant table (classID 2 = Weapon, 4 = Armor).
	-- WoW: Forever has no Enchanting skill level gate on disenchanting (requiredSkill = 1 across all brackets).
	-- Fixes applied over raw TSM DATA.Forever:
	--   1. ilvl 21-25 weapons -> Lesser Astral Essence (10998) and 26-30 -> Greater Astral Essence (11082).
	--   2. Symmetric low-ilvl rare weapon bracket (ilvl 5-15 -> 10940 20% 2-3, 10938 80% 2-3).
	local ARMOR = 4
	local WEAPON = 2
	ns.DE_DATA = {
		-- Dust
		[10940] = { -- Strange Dust
			minLevel = 1, maxLevel = 20,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 5,  maxItemLevel = 15, matRate = 0.800, minAmount = 1, maxAmount = 2, amountOfMats = 1.200 },
				{ class = ARMOR,  quality = 2, minItemLevel = 16, maxItemLevel = 20, matRate = 0.750, minAmount = 2, maxAmount = 3, amountOfMats = 1.850 },
				{ class = ARMOR,  quality = 2, minItemLevel = 21, maxItemLevel = 25, matRate = 0.750, minAmount = 4, maxAmount = 6, amountOfMats = 3.750 },
				{ class = ARMOR,  quality = 3, minItemLevel = 5,  maxItemLevel = 15, matRate = 0.800, minAmount = 2, maxAmount = 3, amountOfMats = 2.000 },
				{ class = ARMOR,  quality = 3, minItemLevel = 16, maxItemLevel = 19, matRate = 0.750, minAmount = 3, maxAmount = 4, amountOfMats = 2.625 },
				{ class = WEAPON, quality = 2, minItemLevel = 5,  maxItemLevel = 15, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 16, maxItemLevel = 20, matRate = 0.200, minAmount = 2, maxAmount = 3, amountOfMats = 0.500 },
				{ class = WEAPON, quality = 2, minItemLevel = 21, maxItemLevel = 25, matRate = 0.150, minAmount = 4, maxAmount = 6, amountOfMats = 0.750 },
				{ class = WEAPON, quality = 3, minItemLevel = 5,  maxItemLevel = 15, matRate = 0.200, minAmount = 2, maxAmount = 3, amountOfMats = 0.500 },
				{ class = WEAPON, quality = 3, minItemLevel = 16, maxItemLevel = 19, matRate = 0.200, minAmount = 3, maxAmount = 4, amountOfMats = 0.700 },
			},
		},
		[11083] = { -- Soul Dust
			minLevel = 21, maxLevel = 30,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 26, maxItemLevel = 30, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
				{ class = ARMOR,  quality = 2, minItemLevel = 31, maxItemLevel = 35, matRate = 0.750, minAmount = 2, maxAmount = 5, amountOfMats = 2.550 },
				{ class = WEAPON, quality = 2, minItemLevel = 26, maxItemLevel = 30, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 31, maxItemLevel = 35, matRate = 0.200, minAmount = 2, maxAmount = 5, amountOfMats = 0.700 },
			},
		},
		[11137] = { -- Vision Dust
			minLevel = 31, maxLevel = 40,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 36, maxItemLevel = 40, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
				{ class = ARMOR,  quality = 2, minItemLevel = 41, maxItemLevel = 45, matRate = 0.750, minAmount = 2, maxAmount = 5, amountOfMats = 2.550 },
				{ class = WEAPON, quality = 2, minItemLevel = 36, maxItemLevel = 40, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 41, maxItemLevel = 45, matRate = 0.200, minAmount = 2, maxAmount = 5, amountOfMats = 0.700 },
			},
		},
		[11176] = { -- Dream Dust
			minLevel = 41, maxLevel = 50,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 46, maxItemLevel = 50, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
				{ class = ARMOR,  quality = 2, minItemLevel = 51, maxItemLevel = 55, matRate = 0.750, minAmount = 2, maxAmount = 5, amountOfMats = 2.550 },
				{ class = WEAPON, quality = 2, minItemLevel = 46, maxItemLevel = 50, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 51, maxItemLevel = 55, matRate = 0.200, minAmount = 2, maxAmount = 5, amountOfMats = 0.700 },
			},
		},
		[16204] = { -- Illusion Dust
			minLevel = 51, maxLevel = 60,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 56, maxItemLevel = 60, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
				{ class = ARMOR,  quality = 2, minItemLevel = 61, maxItemLevel = 99, matRate = 0.750, minAmount = 2, maxAmount = 5, amountOfMats = 2.550 },
				{ class = WEAPON, quality = 2, minItemLevel = 56, maxItemLevel = 60, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 61, maxItemLevel = 99, matRate = 0.200, minAmount = 2, maxAmount = 5, amountOfMats = 0.700 },
			},
		},

		-- Essences
		[10938] = { -- Lesser Magic Essence
			minLevel = 1, maxLevel = 10,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 5, maxItemLevel = 15, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = ARMOR,  quality = 3, minItemLevel = 5, maxItemLevel = 15, matRate = 0.200, minAmount = 2, maxAmount = 3, amountOfMats = 0.500 },
				{ class = WEAPON, quality = 2, minItemLevel = 5, maxItemLevel = 15, matRate = 0.800, minAmount = 1, maxAmount = 2, amountOfMats = 1.200 },
				{ class = WEAPON, quality = 3, minItemLevel = 5, maxItemLevel = 15, matRate = 0.800, minAmount = 2, maxAmount = 3, amountOfMats = 2.000 },
			},
		},
		[10939] = { -- Greater Magic Essence
			minLevel = 11, maxLevel = 15,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 16, maxItemLevel = 20, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = ARMOR,  quality = 3, minItemLevel = 16, maxItemLevel = 19, matRate = 0.200, minAmount = 2, maxAmount = 3, amountOfMats = 0.500 },
				{ class = WEAPON, quality = 2, minItemLevel = 16, maxItemLevel = 20, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
				{ class = WEAPON, quality = 3, minItemLevel = 16, maxItemLevel = 19, matRate = 0.750, minAmount = 2, maxAmount = 3, amountOfMats = 1.875 },
			},
		},
		[10998] = { -- Lesser Astral Essence
			minLevel = 16, maxLevel = 20,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 21, maxItemLevel = 25, matRate = 0.150, minAmount = 1, maxAmount = 2, amountOfMats = 0.220 },
				{ class = WEAPON, quality = 2, minItemLevel = 21, maxItemLevel = 25, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[11082] = { -- Greater Astral Essence
			minLevel = 21, maxLevel = 25,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 26, maxItemLevel = 30, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 26, maxItemLevel = 30, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[11134] = { -- Lesser Mystic Essence
			minLevel = 26, maxLevel = 30,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 31, maxItemLevel = 35, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 31, maxItemLevel = 35, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[11135] = { -- Greater Mystic Essence
			minLevel = 31, maxLevel = 35,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 36, maxItemLevel = 40, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 36, maxItemLevel = 40, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[11174] = { -- Lesser Nether Essence
			minLevel = 36, maxLevel = 40,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 41, maxItemLevel = 45, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 41, maxItemLevel = 45, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[11175] = { -- Greater Nether Essence
			minLevel = 41, maxLevel = 45,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 46, maxItemLevel = 50, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 46, maxItemLevel = 50, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[16202] = { -- Lesser Eternal Essence
			minLevel = 46, maxLevel = 50,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 51, maxItemLevel = 55, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = WEAPON, quality = 2, minItemLevel = 51, maxItemLevel = 55, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
			},
		},
		[16203] = { -- Greater Eternal Essence
			minLevel = 51, maxLevel = 60,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 56, maxItemLevel = 60, matRate = 0.200, minAmount = 1, maxAmount = 2, amountOfMats = 0.300 },
				{ class = ARMOR,  quality = 2, minItemLevel = 61, maxItemLevel = 99, matRate = 0.200, minAmount = 2, maxAmount = 3, amountOfMats = 0.500 },
				{ class = WEAPON, quality = 2, minItemLevel = 56, maxItemLevel = 60, matRate = 0.750, minAmount = 1, maxAmount = 2, amountOfMats = 1.100 },
				{ class = WEAPON, quality = 2, minItemLevel = 61, maxItemLevel = 99, matRate = 0.750, minAmount = 2, maxAmount = 3, amountOfMats = 1.850 },
			},
		},

		-- Shards
		[10978] = { -- Small Glimmering Shard
			minLevel = 1, maxLevel = 20,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 16, maxItemLevel = 20, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 2, minItemLevel = 21, maxItemLevel = 25, matRate = 0.100, minAmount = 1, maxAmount = 1, amountOfMats = 0.100 },
				{ class = ARMOR,  quality = 3, minItemLevel = 16, maxItemLevel = 19, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 20, maxItemLevel = 25, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 16, maxItemLevel = 20, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 2, minItemLevel = 21, maxItemLevel = 25, matRate = 0.100, minAmount = 1, maxAmount = 1, amountOfMats = 0.100 },
				{ class = WEAPON, quality = 3, minItemLevel = 16, maxItemLevel = 19, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 20, maxItemLevel = 25, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
			},
		},
		[11084] = { -- Large Glimmering Shard
			minLevel = 21, maxLevel = 25,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 26, maxItemLevel = 30, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 26, maxItemLevel = 30, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 26, maxItemLevel = 30, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 26, maxItemLevel = 30, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
			},
		},
		[11138] = { -- Small Glowing Shard
			minLevel = 26, maxLevel = 30,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 31, maxItemLevel = 35, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 31, maxItemLevel = 35, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 31, maxItemLevel = 35, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 31, maxItemLevel = 35, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
			},
		},
		[11139] = { -- Large Glowing Shard
			minLevel = 31, maxLevel = 35,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 36, maxItemLevel = 40, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 36, maxItemLevel = 40, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 36, maxItemLevel = 40, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 36, maxItemLevel = 40, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
			},
		},
		[11177] = { -- Small Radiant Shard
			minLevel = 36, maxLevel = 40,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 41, maxItemLevel = 45, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 41, maxItemLevel = 45, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = ARMOR,  quality = 4, minItemLevel = 40, maxItemLevel = 45, matRate = 1.000, minAmount = 2, maxAmount = 4, amountOfMats = 3.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 41, maxItemLevel = 45, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 41, maxItemLevel = 45, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 4, minItemLevel = 40, maxItemLevel = 45, matRate = 1.000, minAmount = 2, maxAmount = 4, amountOfMats = 3.000 },
			},
		},
		[11178] = { -- Large Radiant Shard
			minLevel = 41, maxLevel = 45,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 46, maxItemLevel = 50, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 46, maxItemLevel = 50, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = ARMOR,  quality = 4, minItemLevel = 46, maxItemLevel = 50, matRate = 1.000, minAmount = 2, maxAmount = 4, amountOfMats = 3.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 46, maxItemLevel = 50, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 46, maxItemLevel = 50, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 4, minItemLevel = 46, maxItemLevel = 50, matRate = 1.000, minAmount = 2, maxAmount = 4, amountOfMats = 3.000 },
			},
		},
		[14343] = { -- Small Brilliant Shard
			minLevel = 46, maxLevel = 50,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 51, maxItemLevel = 55, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 51, maxItemLevel = 55, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = ARMOR,  quality = 4, minItemLevel = 51, maxItemLevel = 55, matRate = 1.000, minAmount = 2, maxAmount = 4, amountOfMats = 3.000 },
				{ class = WEAPON, quality = 2, minItemLevel = 51, maxItemLevel = 55, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 51, maxItemLevel = 55, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 4, minItemLevel = 51, maxItemLevel = 55, matRate = 1.000, minAmount = 2, maxAmount = 4, amountOfMats = 3.000 },
			},
		},
		[14344] = { -- Large Brilliant Shard
			minLevel = 51, maxLevel = 60,
			sourceInfo = {
				{ class = ARMOR,  quality = 2, minItemLevel = 56, maxItemLevel = 60, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 2, minItemLevel = 61, maxItemLevel = 99, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = ARMOR,  quality = 3, minItemLevel = 56, maxItemLevel = 60, matRate = 0.995, minAmount = 1, maxAmount = 1, amountOfMats = 0.995 },
				{ class = ARMOR,  quality = 3, minItemLevel = 61, maxItemLevel = 99, matRate = 0.990, minAmount = 1, maxAmount = 1, amountOfMats = 0.990 },
				{ class = WEAPON, quality = 2, minItemLevel = 56, maxItemLevel = 60, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 2, minItemLevel = 61, maxItemLevel = 99, matRate = 0.050, minAmount = 1, maxAmount = 1, amountOfMats = 0.050 },
				{ class = WEAPON, quality = 3, minItemLevel = 56, maxItemLevel = 60, matRate = 0.995, minAmount = 1, maxAmount = 1, amountOfMats = 0.995 },
				{ class = WEAPON, quality = 3, minItemLevel = 61, maxItemLevel = 99, matRate = 0.990, minAmount = 1, maxAmount = 1, amountOfMats = 0.990 },
			},
		},

		-- Crystals
		[20725] = { -- Nexus Crystal
			minLevel = 51, maxLevel = 60,
			sourceInfo = {
				{ class = ARMOR,  quality = 3, minItemLevel = 56, maxItemLevel = 60, matRate = 0.005, minAmount = 1, maxAmount = 1, amountOfMats = 0.005 },
				{ class = ARMOR,  quality = 3, minItemLevel = 61, maxItemLevel = 99, matRate = 0.010, minAmount = 1, maxAmount = 1, amountOfMats = 0.010 },
				{ class = ARMOR,  quality = 4, minItemLevel = 56, maxItemLevel = 60, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = ARMOR,  quality = 4, minItemLevel = 61, maxItemLevel = 99, matRate = 1.000, minAmount = 1, maxAmount = 2, amountOfMats = 1.666 },
				{ class = WEAPON, quality = 3, minItemLevel = 56, maxItemLevel = 60, matRate = 0.005, minAmount = 1, maxAmount = 1, amountOfMats = 0.005 },
				{ class = WEAPON, quality = 3, minItemLevel = 61, maxItemLevel = 99, matRate = 0.010, minAmount = 1, maxAmount = 1, amountOfMats = 0.010 },
				{ class = WEAPON, quality = 4, minItemLevel = 56, maxItemLevel = 60, matRate = 1.000, minAmount = 1, maxAmount = 1, amountOfMats = 1.000 },
				{ class = WEAPON, quality = 4, minItemLevel = 61, maxItemLevel = 99, matRate = 1.000, minAmount = 1, maxAmount = 2, amountOfMats = 1.666 },
			},
		},
	}

	-- Deterministic iteration order across all target mats (matches DE_MAT_INFO)
	local DE_MAT_ORDER = {
		10940, 11083, 11137, 11176, 16204,
		10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,
		10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344,
		20725,
	}

	local deBreakdownMemo = {}
	local deProfileMemo = {}
	local deObsVersion = 0

	function ns.ClearDECache()
		deBreakdownMemo = {}
		deProfileMemo = {}
	end

	function ns.GetDEObservationVersion()
		return deObsVersion
	end

	function ns.IsDisenchantMaterial(itemID)
		local id = tonumber(itemID)
		return (id ~= nil and ns.DE_MAT_INFO[id] ~= nil) and true or false
	end

	-- -------------------------------------------------------------------------
	-- Persistent Metadata Cache & Live DE Observations Store
	-- -------------------------------------------------------------------------

	local function cacheItemMetaInDB(itemID, quality, ilvl, classID, subclassID, equipLoc)
		local db = _G.MerchantMasterDB
		if type(db) ~= "table" then return end
		if type(itemID) ~= "number" or itemID <= 0 then return end
		if not isFiniteNumber(quality) or not isFiniteNumber(classID) then return end
		local mc = db.deItemMetaCache
		if type(mc) ~= "table" then
			mc = {}
			db.deItemMetaCache = mc
		end
		mc[itemID] = {
			q = math.floor(quality),
			ilvl = isFiniteNumber(ilvl) and math.max(0, math.floor(ilvl)) or 0,
			c = math.floor(classID),
			sc = isFiniteNumber(subclassID) and math.floor(subclassID) or 0,
			eq = (readable(equipLoc) and type(equipLoc) == "string") and equipLoc or "",
		}
	end

	local function lookupFallbackMeta(itemID)
		local staticMeta = ns.DE_ITEM_META and ns.DE_ITEM_META[itemID]
		if type(staticMeta) == "table" and isFiniteNumber(staticMeta.q) and isFiniteNumber(staticMeta.c) then
			return staticMeta, "static"
		end
		local db = _G.MerchantMasterDB
		local mc = (type(db) == "table") and db.deItemMetaCache or nil
		local cachedMeta = (type(mc) == "table") and mc[itemID] or nil
		if type(cachedMeta) == "table" and isFiniteNumber(cachedMeta.q) and isFiniteNumber(cachedMeta.c) then
			return cachedMeta, "cache"
		end
		return nil, nil
	end

	local function sanitizeObsEntry(entry)
		if type(entry) ~= "table" then return nil end
		local casts = isFiniteNumber(entry.casts) and math.floor(entry.casts) or 0
		if casts <= 0 then return nil end
		local asCasts = isFiniteNumber(entry.asCasts) and math.floor(entry.asCasts) or 0
		if asCasts < 0 then asCasts = 0 end
		if asCasts > casts then asCasts = casts end
		local rawMats = type(entry.mats) == "table" and entry.mats or nil
		if not rawMats then return nil end

		local asMult = 1 + (ns.DE_ARCANE_SALVAGER_BONUS or 0.20)
		local effDenom = (casts - asCasts) + (asCasts * asMult)
		if effDenom <= 0 then effDenom = casts end

		local cleanMats = {}
		local hasAny = false
		for k, m in pairs(rawMats) do
			local matID = tonumber(k)
			if matID and isFiniteNumber(matID) and matID > 0 and matID == math.floor(matID) and type(m) == "table" then
				local drops = isFiniteNumber(m.drops) and math.floor(m.drops) or 0
				local totalQty = isFiniteNumber(m.totalQty) and m.totalQty or 0
				if drops > 0 and totalQty > 0 then
					if drops > casts then drops = casts end
					local minQty = isFiniteNumber(m.minQty) and m.minQty or 1
					local maxQty = isFiniteNumber(m.maxQty) and m.maxQty or minQty
					if minQty < 0 then minQty = 0 end
					if maxQty < minQty then maxQty = minQty end
					local baseMinQty = isFiniteNumber(m.baseMinQty) and m.baseMinQty or nil
					local baseMaxQty = isFiniteNumber(m.baseMaxQty) and m.baseMaxQty or nil
					if baseMinQty == nil then
						baseMinQty = (asCasts == casts) and (minQty / asMult) or minQty
					end
					if baseMaxQty == nil then
						baseMaxQty = (asCasts == casts) and (maxQty / asMult) or maxQty
					end
					if baseMinQty < 0 then baseMinQty = 0 end
					if baseMaxQty < baseMinQty then baseMaxQty = baseMinQty end
					local baseQty = isFiniteNumber(m.baseQty) and m.baseQty or nil
					if baseQty ~= nil and baseQty < 0 then baseQty = nil end
					-- Unbiased baseline expected quantity per cast:
					--   * Preferred: baseQty / casts (where each AS cast contributed qty / (1 + AS_BONUS) to baseQty)
					--   * Legacy fallback (entries lacking baseQty): totalQty / ((casts - asCasts) + asCasts * (1 + AS_BONUS))
					local avgQty = (baseQty ~= nil) and (baseQty / casts) or (totalQty / effDenom)
					local dropRate = drops / casts
					if dropRate > 1 then dropRate = 1 end
					cleanMats[matID] = {
						drops = drops,
						totalQty = totalQty,
						baseQty = baseQty or (avgQty * casts),
						minQty = minQty,
						maxQty = maxQty,
						baseMinQty = baseMinQty,
						baseMaxQty = baseMaxQty,
						avgQty = avgQty,
						dropRate = dropRate,
					}
					hasAny = true
				end
			end
		end
		if not hasAny then return nil end
		return {
			casts = casts,
			asCasts = asCasts,
			mats = cleanMats,
			lastSource = (entry.lastSource == "helper") and "helper" or "manual",
			lastAt = isFiniteNumber(entry.lastAt) and entry.lastAt or 0,
		}
	end

	local function ensureObsStore()
		local db = _G.MerchantMasterDB
		if type(db) ~= "table" then return nil end
		local obs = db.deObservations
		if type(obs) ~= "table" then
			obs = { version = 1, byBucket = {}, byItem = {} }
			db.deObservations = obs
		end
		if type(obs.byBucket) ~= "table" then obs.byBucket = {} end
		if type(obs.byItem) ~= "table" then obs.byItem = {} end
		if not isFiniteNumber(obs.version) then obs.version = 1 end
		return obs
	end

	local function getOrInitRawObsEntry(container, key)
		local e = container[key]
		if type(e) ~= "table" then
			e = { casts = 0, asCasts = 0, mats = {} }
			container[key] = e
			return e
		end
		local casts = isFiniteNumber(e.casts) and math.floor(e.casts) or 0
		if casts < 0 then casts = 0 end
		local asCasts = isFiniteNumber(e.asCasts) and math.floor(e.asCasts) or 0
		if asCasts < 0 then asCasts = 0 end
		if asCasts > casts then asCasts = casts end
		e.casts = casts
		e.asCasts = asCasts
		if type(e.mats) ~= "table" then e.mats = {} end
		return e
	end

	local function applyCastToEntry(entry, castQty, isAS, sourceTag, nowTs)
		local asMult = 1 + (ns.DE_ARCANE_SALVAGER_BONUS or 0.20)
		-- Backfill baseQty & baseMinQty/baseMaxQty on legacy pre-existing mat records before adding this cast
		if entry.casts > 0 then
			local oldEff = (entry.casts - entry.asCasts) + (entry.asCasts * asMult)
			if oldEff <= 0 then oldEff = entry.casts end
			for matID, m in pairs(entry.mats) do
				if type(m) == "table" then
					if not isFiniteNumber(m.baseQty) and isFiniteNumber(m.totalQty) then
						m.baseQty = (m.totalQty / oldEff) * entry.casts
					end
					if not isFiniteNumber(m.baseMinQty) and isFiniteNumber(m.minQty) then
						m.baseMinQty = (entry.asCasts == entry.casts) and (m.minQty / asMult) or m.minQty
					end
					if not isFiniteNumber(m.baseMaxQty) and isFiniteNumber(m.maxQty) then
						m.baseMaxQty = (entry.asCasts == entry.casts) and (m.maxQty / asMult) or m.maxQty
					end
				end
			end
		end

		entry.casts = entry.casts + 1
		if isAS then
			entry.asCasts = entry.asCasts + 1
		end
		entry.lastSource = sourceTag
		entry.lastAt = nowTs

		for matID, qty in pairs(castQty) do
			local normQty = isAS and (qty / asMult) or qty
			local m = entry.mats[matID]
			if type(m) ~= "table" then
				m = { drops = 0, totalQty = 0, baseQty = 0, minQty = qty, maxQty = qty, baseMinQty = normQty, baseMaxQty = normQty }
				entry.mats[matID] = m
			end
			local prevDrops = isFiniteNumber(m.drops) and math.floor(m.drops) or 0
			local prevTotal = isFiniteNumber(m.totalQty) and m.totalQty or 0
			local prevBase = isFiniteNumber(m.baseQty) and m.baseQty or prevTotal
			local prevMin = isFiniteNumber(m.minQty) and m.minQty or qty
			local prevMax = isFiniteNumber(m.maxQty) and m.maxQty or qty
			local prevBaseMin = isFiniteNumber(m.baseMinQty) and m.baseMinQty or normQty
			local prevBaseMax = isFiniteNumber(m.baseMaxQty) and m.baseMaxQty or normQty

			m.drops = prevDrops + 1
			m.totalQty = prevTotal + qty
			m.baseQty = prevBase + normQty
			m.minQty = (qty < prevMin) and qty or prevMin
			m.maxQty = (qty > prevMax) and qty or prevMax
			m.baseMinQty = (normQty < prevBaseMin) and normQty or prevBaseMin
			m.baseMaxQty = (normQty > prevBaseMax) and normQty or prevBaseMax
		end
	end

	function ns.GetDEMaterialMeta(matID)
		local info = ns.DE_MAT_INFO[matID]
		local liveName
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		if getInfo then
			local nm = getInfo(matID)
			if readable(nm) and type(nm) == "string" and nm ~= "" then
				liveName = nm
			end
		end
		local fallbackName = (ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[matID]) or (info and info.name) or ("Item #" .. tostring(matID))
		local name = liveName or fallbackName
		local quality = (info and info.quality) or 1
		local colorHex = QUALITY_HEX[quality] or QUALITY_HEX[1]
		return name, quality, colorHex, (info and info.kind) or "Material"
	end

	function ns.FormatDEChancePct(matRate)
		local pct = (tonumber(matRate) or 0) * 100
		if math.abs(pct - math.floor(pct + 0.5)) < 1e-4 then
			return tostring(math.floor(pct + 0.5))
		end
		return (string.format("%.2f", pct):gsub("0+$", ""):gsub("%.$", ""))
	end

	function ns.FormatDEAmount(amountOfMats)
		local v = tonumber(amountOfMats) or 0
		if math.abs(v - math.floor(v + 0.5)) < 1e-4 then
			return tostring(math.floor(v + 0.5))
		end
		return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
	end

	function ns.IsItemDisenchantable(itemID, itemLink)
		if not itemID or type(itemID) ~= "number" or itemID <= 0 then
			return false, "invalid", nil
		end
		if ns.DE_NON_DISENCHANTABLE[itemID] then
			return false, "blacklisted", nil
		end

		local name, quality, ilvl, equipLoc, classID, subclassID
		local metaSource = nil

		-- 1. Try live WoW client GetItemInfo on bare itemID first so base cache never stores scaled link ilvl
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		if getInfo then
			local lName, _, lQuality, lIlvl, _, _, _, _, lEquipLoc, _, _, lClassID, lSubclassID = getInfo(itemID)
			local fromBareID = (readable(lName) and lName and readable(lClassID) and lClassID and readable(lQuality) and lQuality) and true or false
			if not fromBareID and itemLink then
				lName, _, lQuality, lIlvl, _, _, _, _, lEquipLoc, _, _, lClassID, lSubclassID = getInfo(itemLink)
			end
			if readable(lName) and lName and readable(lClassID) and lClassID and readable(lQuality) and lQuality then
				name = lName
				quality = lQuality
				ilvl = readable(lIlvl) and lIlvl or 0
				equipLoc = (readable(lEquipLoc) and type(lEquipLoc) == "string") and lEquipLoc or ""
				classID = lClassID
				subclassID = (readable(lSubclassID) and type(lSubclassID) == "number") and lSubclassID or 0
				metaSource = "live"
				-- Only persist unscaled bare-itemID metadata into deItemMetaCache
				if fromBareID then
					cacheItemMetaInDB(itemID, quality, ilvl, classID, subclassID, equipLoc)
				end
			end
		end

		-- 2. Fallback to static ns.DE_ITEM_META then persistent MerchantMasterDB.deItemMetaCache
		if not metaSource then
			local fb, fbSrc = lookupFallbackMeta(itemID)
			if fb then
				quality = fb.q
				ilvl = tonumber(fb.ilvl) or 0
				classID = fb.c
				subclassID = tonumber(fb.sc) or 0
				equipLoc = type(fb.eq) == "string" and fb.eq or ""
				name = (ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[itemID])
					or (ns.ITEMS and ns.ITEMS[itemID] and ns.ITEMS[itemID].name)
					or ("Item #" .. tostring(itemID))
				metaSource = fbSrc
			else
				if ns.RequestItemDataLoad then ns.RequestItemDataLoad(itemID) end
				return nil, "uncached", nil
			end
		end

		if (classID ~= ARMOR and classID ~= WEAPON) or quality < 2 or quality > 4 then
			return false, "ineligible", nil
		end
		-- Exclude Fishing Poles (weapon subclass 20), Thrown weapons (weapon subclass 16), and Cosmetic armor (armor subclass 5)
		if classID == WEAPON and (subclassID == 20 or subclassID == 16) then
			return false, "ineligible", nil
		end
		if classID == ARMOR and subclassID == 5 then
			return false, "ineligible", nil
		end
		if not readable(equipLoc) or not equipLoc or DE_EXCLUDED_EQUIPLOCS[equipLoc] then
			return false, "ineligible", nil
		end

		-- Preserve itemLink detailed item level override regardless of live vs static/cache metadata source
		if itemLink then
			local getDetailed = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
			if getDetailed then
				local ok, detailed = pcall(getDetailed, itemLink)
				if ok and readable(detailed) and type(detailed) == "number" and detailed > 0 then
					ilvl = detailed
				end
			end
		end
		if not readable(ilvl) or type(ilvl) ~= "number" or ilvl <= 0 then
			return false, "ineligible", nil
		end

		return true, nil, {
			itemID = itemID,
			name = name,
			quality = quality,
			qualityName = QUALITY_NAMES[quality] or "Unknown",
			ilvl = ilvl,
			classID = classID,
			className = (classID == WEAPON) and "Weapon" or "Armor",
			subclassID = subclassID,
			equipLoc = equipLoc,
			metaSource = metaSource,
		}
	end

	-- Records one observed Disenchant cast into MerchantMasterDB.deObservations (both byItem and byBucket).
	-- lootedMats accepts either:
	--   * array of { itemID = matID, qty = count }
	--   * map of [matID] = count
	-- opts = { itemLink = string, arcaneSalvager = boolean, source = "manual" | "helper" }
	-- Arcane Salvager normalization:
	--   Each AS cast stores raw loot in totalQty/minQty/maxQty while contributing qty / (1 + DE_ARCANE_SALVAGER_BONUS)
	--   to baseQty, so AS (+20%) observations combine cleanly with non-AS casts without inflating the non-AS baseline.
	function ns.RecordDEObservation(sourceItemID, lootedMats, opts)
		opts = type(opts) == "table" and opts or {}
		local itemLink = type(opts.itemLink) == "string" and opts.itemLink or nil
		local srcID = tonumber(sourceItemID)
		if (not srcID or srcID <= 0) and itemLink then
			srcID = tonumber(itemLink:match("item:(%d+)"))
		end
		if not srcID or not isFiniteNumber(srcID) or srcID <= 0 or srcID ~= math.floor(srcID) then
			return false, "invalid"
		end
		if type(lootedMats) ~= "table" then
			return false, "empty_loot"
		end

		-- Aggregate looted stacks per matID for this single DE cast
		local castQty = {}
		local matCount = 0
		if #lootedMats > 0 then
			for _, row in ipairs(lootedMats) do
				if type(row) == "table" then
					local mid = tonumber(row.itemID or row.id)
					local qty = tonumber(row.qty or row.count)
					if mid and isFiniteNumber(mid) and mid > 0 and mid == math.floor(mid)
						and qty and isFiniteNumber(qty) and qty > 0 then
						if not castQty[mid] then matCount = matCount + 1 end
						castQty[mid] = (castQty[mid] or 0) + qty
					end
				end
			end
		end
		if matCount == 0 then
			for k, v in pairs(lootedMats) do
				local mid = tonumber(k)
				local qty = tonumber(v)
				if mid and isFiniteNumber(mid) and mid > 0 and mid == math.floor(mid)
					and qty and isFiniteNumber(qty) and qty > 0 then
					if not castQty[mid] then matCount = matCount + 1 end
					castQty[mid] = (castQty[mid] or 0) + qty
				end
			end
		end
		if matCount == 0 then
			return false, "empty_loot"
		end

		local ok, err, meta = ns.IsItemDisenchantable(srcID, itemLink)
		if ok == false then
			return false, err or "ineligible"
		end

		local store = ensureObsStore()
		if not store then
			return false, "no_db"
		end

		local bucketKey = nil
		if meta and meta.classID and meta.quality and meta.ilvl then
			bucketKey = tostring(meta.classID) .. ":" .. tostring(meta.quality) .. ":" .. tostring(meta.ilvl)
		end

		local isAS = (opts.arcaneSalvager == true)
		local sourceTag = (opts.source == "helper") and "helper" or "manual"
		local nowTs = (type(_G.time) == "function") and _G.time() or 0

		local itemEntry = getOrInitRawObsEntry(store.byItem, srcID)
		applyCastToEntry(itemEntry, castQty, isAS, sourceTag, nowTs)

		if bucketKey then
			local bucketEntry = getOrInitRawObsEntry(store.byBucket, bucketKey)
			applyCastToEntry(bucketEntry, castQty, isAS, sourceTag, nowTs)
		end

		deObsVersion = deObsVersion + 1
		ns.ClearDECache()
		return true, bucketKey
	end

	-- Returns sanitized observation stats for an item (preferring its c:q:ilvl bucket unless byItem has more/newer casts), or nil.
	function ns.GetDEObservationStats(itemID, itemLink)
		if not itemID or type(itemID) ~= "number" or itemID <= 0 then
			return nil
		end
		local db = _G.MerchantMasterDB
		local obs = (type(db) == "table") and db.deObservations or nil
		if type(obs) ~= "table" then
			return nil
		end

		local bucketKey = nil
		local ok, _, meta = ns.IsItemDisenchantable(itemID, itemLink)
		if ok and meta and meta.classID and meta.quality and meta.ilvl then
			bucketKey = tostring(meta.classID) .. ":" .. tostring(meta.quality) .. ":" .. tostring(meta.ilvl)
		end

		local itemStats = (type(obs.byItem) == "table") and sanitizeObsEntry(obs.byItem[itemID]) or nil
		local bucketStats = (bucketKey and type(obs.byBucket) == "table") and sanitizeObsEntry(obs.byBucket[bucketKey]) or nil

		local primary = bucketStats
		if not primary then
			primary = itemStats
		elseif itemStats then
			if itemStats.casts > primary.casts
				or (itemStats.casts == primary.casts and (itemStats.lastAt or 0) > (primary.lastAt or 0)) then
				primary = itemStats
			end
		end
		if not primary then
			return nil
		end
		return {
			casts = primary.casts,
			asCasts = primary.asCasts,
			itemCasts = itemStats and itemStats.casts or 0,
			bucketKey = bucketKey,
			mats = primary.mats,
			lastSource = primary.lastSource,
			lastAt = primary.lastAt,
		}
	end

	-- Returns outcomes (array of rows), errOrNil, metaInfo
	-- Each row supports both positional [1]=matID,[2]=matRate,[3]=minAmount,[4]=maxAmount,[5]=amountOfMats
	-- and named keys (matID, matRate, minAmount, maxAmount, amountOfMats, chance, minQty, maxQty).
	function ns.GetItemDEProfile(itemID, itemLink)
		local ok, err, meta = ns.IsItemDisenchantable(itemID, itemLink)
		if ok == nil then
			return nil, err or "uncached", nil
		end
		if not ok or not meta then
			return nil, err or "ineligible", nil
		end
		local profKey = tostring(meta.classID) .. ":" .. tostring(meta.quality) .. ":" .. tostring(meta.ilvl)
		local cached = deProfileMemo[profKey]
		if cached then
			if cached.err then return nil, cached.err, meta end
			return cached.rows, nil, meta
		end

		local out = {}
		for _, matID in ipairs(DE_MAT_ORDER) do
			local target = ns.DE_DATA[matID]
			if target and target.sourceInfo then
				for _, info in ipairs(target.sourceInfo) do
					if info.class == meta.classID
						and info.quality == meta.quality
						and meta.ilvl >= info.minItemLevel
						and meta.ilvl <= info.maxItemLevel then
						out[#out + 1] = {
							matID, info.matRate, info.minAmount, info.maxAmount, info.amountOfMats,
							matID = matID,
							chance = info.matRate,
							matRate = info.matRate,
							minQty = info.minAmount,
							maxQty = info.maxAmount,
							minAmount = info.minAmount,
							maxAmount = info.maxAmount,
							amountOfMats = info.amountOfMats,
							requiredSkill = 1,
						}
						break
					end
				end
			end
		end

		if #out == 0 then
			deProfileMemo[profKey] = { err = "out_of_band" }
			return nil, "out_of_band", meta
		end

		table.sort(out, function(a, b)
			if a.matRate ~= b.matRate then return a.matRate > b.matRate end
			return a.matID < b.matID
		end)

		deProfileMemo[profKey] = { rows = out }
		return out, nil, meta
	end

	-- Computes full DE breakdown priced via MerchantMaster tracked prices,
	-- with Bayesian shrinkage blending from live observed DE casts once casts >= 3.
	-- Returns breakdownTable (or nil), errOrNil.
	function ns.GetItemDEBreakdown(itemID, itemLink, applyAHCut)
		if not itemID or type(itemID) ~= "number" or itemID <= 0 then
			return nil, "invalid"
		end
		local applyCut = (applyAHCut ~= false)
		local cutFlag = applyCut and "1" or "0"
		local cacheKey = tostring(itemLink or itemID) .. ":" .. cutFlag
		local hit = deBreakdownMemo[cacheKey]
		if hit then
			if hit.err then return nil, hit.err end
			return hit.bd, nil
		end

		local mats, err, meta = ns.GetItemDEProfile(itemID, itemLink)
		if err == "uncached" then
			return nil, "uncached"
		end
		if not mats then
			deBreakdownMemo[cacheKey] = { err = err or "ineligible" }
			return nil, err or "ineligible"
		end

		local obs = ns.GetDEObservationStats(itemID, itemLink)
		local learnedCasts = (obs and obs.casts) or 0
		local minCasts = ns.DE_LEARN_MIN_CASTS or 3
		local priorW = ns.DE_LEARN_PRIOR_WEIGHT or 10
		local learnedBlended = (learnedCasts >= minCasts)
		local shrinkW = learnedBlended and (learnedCasts / (learnedCasts + priorW)) or 0

		-- Build combined outcome rows (baseline rows + any novel observed mats when blended)
		local evalRows = {}
		local seenMat = {}
		for _, row in ipairs(mats) do
			local matID = row.matID
			seenMat[matID] = true
			local baseAmt = row.amountOfMats
			local baseRate = row.matRate
			local effAmt = baseAmt
			local effRate = baseRate
			local obsAmt = nil
			local obsRate = nil
			if learnedBlended then
				local om = obs and obs.mats and obs.mats[matID]
				obsAmt = om and om.avgQty or 0
				obsRate = om and om.dropRate or 0
				effAmt = (1 - shrinkW) * baseAmt + shrinkW * obsAmt
				effRate = (1 - shrinkW) * baseRate + shrinkW * obsRate
			end
			evalRows[#evalRows + 1] = {
				matID = matID,
				matRate = effRate,
				minAmount = row.minAmount,
				maxAmount = row.maxAmount,
				amountOfMats = effAmt,
				baselineAmountOfMats = baseAmt,
				baselineMatRate = baseRate,
				observedAmountOfMats = obsAmt,
				observedMatRate = obsRate,
			}
		end

		if learnedBlended and obs and obs.mats then
			local extraIDs = {}
			for matID in pairs(obs.mats) do
				if not seenMat[matID] then
					extraIDs[#extraIDs + 1] = matID
				end
			end
			table.sort(extraIDs)
			for _, matID in ipairs(extraIDs) do
				local om = obs.mats[matID]
				evalRows[#evalRows + 1] = {
					matID = matID,
					matRate = shrinkW * (om.dropRate or 0),
					minAmount = om.baseMinQty or om.minQty or 1,
					maxAmount = om.baseMaxQty or om.maxQty or 1,
					amountOfMats = shrinkW * (om.avgQty or 0),
					baselineAmountOfMats = 0,
					baselineMatRate = 0,
					observedAmountOfMats = om.avgQty or 0,
					observedMatRate = om.dropRate or 0,
				}
			end
			table.sort(evalRows, function(a, b)
				if a.matRate ~= b.matRate then return a.matRate > b.matRate end
				return a.matID < b.matID
			end)
		end

		local gross = 0
		local baselineGross = 0
		local minRollGross = nil
		local maxRollGross = nil
		local pricedCount = 0
		local missingPriceCount = 0
		local pricedOutcomes = {}
		local asMult = 1 + (ns.DE_ARCANE_SALVAGER_BONUS or 0.20)

		for _, row in ipairs(evalRows) do
			local matID = row.matID
			local price, srcLabel
			if ns.GetItemMarketPrice then
				price, srcLabel = ns.GetItemMarketPrice(matID)
			end
			if (not price or price <= 0) and ns.GetFallbackMarketPrice then
				price, srcLabel = ns.GetFallbackMarketPrice(matID)
			end
			local hasPrice = (type(price) == "number" and price > 0)
			local matName, matQuality, matColor, matKind = ns.GetDEMaterialMeta(matID)
			local evGross, evNet, evNetRounded, minVal, maxVal
			if hasPrice then
				pricedCount = pricedCount + 1
				evGross = row.amountOfMats * price
				evNet = applyCut and (evGross * 0.95) or evGross
				evNetRounded = math.floor(evNet + 0.5)
				minVal = row.minAmount * price
				maxVal = row.maxAmount * price
				gross = gross + evGross
				baselineGross = baselineGross + (row.baselineAmountOfMats * price)
				if minRollGross == nil or minVal < minRollGross then minRollGross = minVal end
				if maxRollGross == nil or maxVal > maxRollGross then maxRollGross = maxVal end
			else
				missingPriceCount = missingPriceCount + 1
				price = nil
				srcLabel = "Unpriced"
			end

			pricedOutcomes[#pricedOutcomes + 1] = {
				matID = matID,
				name = matName,
				quality = matQuality,
				colorHex = matColor,
				kind = matKind,
				matRate = row.matRate,
				minAmount = row.minAmount,
				maxAmount = row.maxAmount,
				amountOfMats = row.amountOfMats,
				baselineAmountOfMats = row.baselineAmountOfMats,
				baselineMatRate = row.baselineMatRate,
				observedAmountOfMats = row.observedAmountOfMats,
				observedMatRate = row.observedMatRate,
				unitPrice = price,
				priceSource = srcLabel or "Market",
				evGross = evGross,
				evNet = evNet,
				evNetRounded = evNetRounded,
				minRollGross = minVal,
				maxRollGross = maxVal,
				sharePct = 0,
			}
		end

		local grossCopper, netCopper, asGrossCopper, asNetCopper
		local baselineGrossCopper, baselineNetCopper
		local minGrossCopper, maxGrossCopper, minNetCopper, maxNetCopper
		if pricedCount > 0 then
			grossCopper = math.floor(gross + 0.5)
			netCopper = applyCut and math.floor(grossCopper * 0.95 + 0.5) or grossCopper
			baselineGrossCopper = learnedBlended and math.floor(baselineGross + 0.5) or grossCopper
			baselineNetCopper = learnedBlended
				and (applyCut and math.floor(baselineGrossCopper * 0.95 + 0.5) or baselineGrossCopper)
				or netCopper
			asGrossCopper = math.floor(grossCopper * asMult + 0.5)
			asNetCopper = math.floor(netCopper * asMult + 0.5)
			minGrossCopper = math.floor((minRollGross or 0) + 0.5)
			maxGrossCopper = math.floor((maxRollGross or 0) + 0.5)
			minNetCopper = applyCut and math.floor(minGrossCopper * 0.95 + 0.5) or minGrossCopper
			maxNetCopper = applyCut and math.floor(maxGrossCopper * 0.95 + 0.5) or maxGrossCopper
			for _, o in ipairs(pricedOutcomes) do
				if o.evGross then
					o.sharePct = (gross > 0) and ((o.evGross / gross) * 100) or 0
				end
			end
		end

		local primary = pricedOutcomes[1]
		local primarySummary = primary
			and (ns.FormatDEChancePct(primary.matRate) .. "% " .. primary.name)
			or ""

		local bd = {
			itemID = itemID,
			quality = meta and meta.quality or nil,
			qualityName = meta and meta.qualityName or nil,
			ilvl = meta and meta.ilvl or nil,
			classID = meta and meta.classID or nil,
			className = meta and meta.className or nil,
			applyAHCut = applyCut,
			grossCopper = grossCopper,
			netCopper = netCopper,
			baselineGrossCopper = baselineGrossCopper,
			baselineNetCopper = baselineNetCopper,
			asGrossCopper = asGrossCopper,
			asNetCopper = asNetCopper,
			minGrossCopper = minGrossCopper,
			maxGrossCopper = maxGrossCopper,
			minNetCopper = minNetCopper,
			maxNetCopper = maxNetCopper,
			pricedCount = pricedCount,
			missingPriceCount = missingPriceCount,
			learnedCasts = learnedCasts,
			learnedBlended = learnedBlended,
			learnedWeight = shrinkW,
			primarySummary = primarySummary,
			outcomes = pricedOutcomes,
		}
		deBreakdownMemo[cacheKey] = { bd = bd }
		return bd, nil
	end

	-- Backward-compatible scalar EV helper: returns netCopper (or nil), grossCopper (or nil), errOrNil.
	function ns.GetItemDEValue(itemID, itemLink, applyAHCut)
		local bd, err = ns.GetItemDEBreakdown(itemID, itemLink, applyAHCut)
		if not bd then
			return nil, nil, err
		end
		if bd.netCopper == nil then
			return nil, nil, "missing_price"
		end
		return bd.netCopper, bd.grossCopper, nil
	end
end
