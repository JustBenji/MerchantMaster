-- MerchantMaster: Unified Local Snapshot & Live AH Pricing,
-- Crafting & Gathering Profitability, Unlock Logic & Reputation Progression Engine

local ADDON, ns = ...
local function readable(v)
	return not (issecretvalue and issecretvalue(v))
		and not (type(v) == "table" and issecrettable and issecrettable(v))
end
local function demandNumber(v)
	if readable(v) and type(v) == "number" and v == v and v >= 0 and v < math.huge then return v end
end

-- WoW Forever (16001) Regional Unique Names helper: returns (fullName, firstName).
-- Captures UnitName("player")'s 2nd surname return value when RegionalUniqueNamesEnabled() is active.
function ns.GetPlayerFullName()
	local first, second
	if _G.UnitName then
		first, second = _G.UnitName("player")
	end
	if not readable(first) or type(first) ~= "string" or first == "" then
		first = "Player"
	end
	local player = first
	local firstName = first
	if _G.RegionalUniqueNamesEnabled and _G.RegionalUniqueNamesEnabled()
		and readable(second) and type(second) == "string" and second ~= "" then
		local sep = (_G.Constants and _G.Constants.CharacterNameSeparatorConsts
			and _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
		player = first .. sep .. second
	end
	local splitFirst = player:match("^([^%s]+)%s+")
	if type(splitFirst) == "string" and splitFirst ~= "" then
		firstName = splitFirst
	end
	return player, firstName
end

-- Accounting prices are copper; SaleRate is 0..100 and NumExpires is a count.
-- Resolve the merged module at call time because Pricing loads before Analytics.
ns.Pricing = ns.Pricing or {}
function ns.Pricing.GetAccountingPrice(sourceKey, itemID, filters)
	if (_G.issecretvalue and (_G.issecretvalue(sourceKey) or _G.issecretvalue(itemID))) then return nil end
	if type(sourceKey) ~= "string" or (type(itemID) ~= "number" and type(itemID) ~= "string") then return nil end
	local analytics = ns.Analytics
	if not analytics then return nil end
	local model = analytics.Model
	if model and type(model.GetPriceSource) == "function" then return model.GetPriceSource(sourceKey, itemID, filters) end
end
do
	for _, key in ipairs({ "AvgBuy", "SmartAvgBuy", "CurBasis", "AvgSell", "MinBuy", "MaxBuy", "MinSell", "MaxSell", "SaleRate", "NumExpires" }) do
		local source = key
		ns.Pricing[source] = function(itemID, filters) return ns.Pricing.GetAccountingPrice(source, itemID, filters) end
	end
end

local RECENT_LIVE_AH_SECONDS = 1800 -- 30 minutes: labels recent Live AH scans as "Live AH" vs older "Saved AH Scan"
local SNAPSHOT_FRESH_SECONDS = 5400 -- 90 minutes: local snapshot freshness threshold
local QUESTION_ICON = 134400
local CRATE_ICON = 236994

local COIN_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:1:0|t"
local COIN_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:11:11:1:0|t"
local COIN_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:11:11:1:0|t"

ns.COIN_GOLD = COIN_GOLD
ns.COIN_SILVER = COIN_SILVER
ns.COIN_COPPER = COIN_COPPER
ns.QUESTION_ICON = QUESTION_ICON
ns.CRATE_ICON = CRATE_ICON
ns.ADDON_ICON = "Interface\\AddOns\\MerchantMaster\\Textures\\MerchantMasterLogo"
ns.ADDON_ICON_SMALL = "Interface\\AddOns\\MerchantMaster\\Textures\\MerchantMasterLogo64"

ns.PRICE_SOURCES = {
	{ key = "auto",        label = "Auto (Best)",    short = "Auto" },
	{ key = "snapshot",    label = "Local Snapshot", short = "Snapshot" },
	{ key = "live_ah",     label = "Live AH",        short = "Saved AH" },
}

local LEGACY_PRICE_SOURCES = {
	tsm_min = true,
	tsm_market = true,
	auctionator = true,
	auctioneer = true,
}

function ns.GetDB()
	return _G.MerchantMasterDB
end

function ns.NormalizePriceSourceKey(key)
	if key == "live" then return "live_ah" end
	if type(key) ~= "string" or LEGACY_PRICE_SOURCES[key] then
		return "auto"
	end
	for _, s in ipairs(ns.PRICE_SOURCES) do
		if s.key == key then return key end
	end
	return "auto"
end

function ns.GetEffectivePriceSource()
	local db = ns.GetDB()
	local raw = (db and db.priceSource) or "auto"
	local key = ns.NormalizePriceSourceKey(raw)
	if db and LEGACY_PRICE_SOURCES[raw] then
		db.priceSource = key
	end
	if key == "snapshot" and not (ns.HasSnapshots and ns.HasSnapshots()) then
		return "auto"
	end
	return key
end
ns.Pricing.GetEffectivePriceSource = ns.GetEffectivePriceSource

function ns.GetAvailablePriceSources()
	local includeSnap = (ns.HasSnapshots and ns.HasSnapshots())
		or (ns.HasSnapshotExtension and ns.HasSnapshotExtension())
		or (ns.app and ns.app.snapshotExtension ~= nil)
	if includeSnap then
		return ns.PRICE_SOURCES
	end
	local out = {}
	for _, s in ipairs(ns.PRICE_SOURCES) do
		if s.key ~= "snapshot" then
			out[#out + 1] = s
		end
	end
	return out
end

function ns.CurrentSourceInfo()
	local key = ns.GetEffectivePriceSource()
	for i, s in ipairs(ns.PRICE_SOURCES) do
		if s.key == key then return s, i end
	end
	return ns.PRICE_SOURCES[1], 1
end

local requestedItemIDs = {}
ns.pendingItemLoads = {}
ns.priceCacheEpoch = 1
ns._evalCache = nil
local evalDepth = 0
local crateTooltipMemo = {}
local tooltipCraftMemo = {}
local cachedBarteringRank = nil

ns.CRATE_BY_ID = ns.CRATE_BY_ID or {}
if ns.CRATES then
	for _, crate in ipairs(ns.CRATES) do
		if crate and crate.itemID then
			ns.CRATE_BY_ID[crate.itemID] = crate
		end
	end
end

ns.SEALED_CRATE_BY_ID = ns.SEALED_CRATE_BY_ID or {}
if ns.DEFAULT_REWARDS then
	for tier, byQuality in pairs(ns.DEFAULT_REWARDS) do
		if type(byQuality) == "table" then
			for quality, rw in pairs(byQuality) do
				if type(rw) == "table" and rw.sealedID then
					ns.SEALED_CRATE_BY_ID[rw.sealedID] = {
						itemID = rw.sealedID,
						sealed = true,
						tier = tier,
						quality = quality,
						tokens = rw.tokens,
						copper = rw.copper,
						questID = rw.questID,
						unconfirmed = rw.unconfirmed,
					}
				end
			end
		end
	end
end

function ns.InvalidateCrateTooltipCache()
	crateTooltipMemo = {}
end

function ns.InvalidateTooltipEconCache()
	if ns.ClearDECache then ns.ClearDECache() end
	tooltipCraftMemo = {}
end

function ns.InvalidateVendorDiscountCache()
	cachedBarteringRank = nil
end

function ns.InvalidatePriceCache()
	ns.priceCacheEpoch = (ns.priceCacheEpoch or 1) + 1
	ns._evalCache = nil
	ns.InvalidateCrateTooltipCache()
	ns.InvalidateTooltipEconCache()
	if ns.MP and ns.MP.InvalidateSolveCache then ns.MP.InvalidateSolveCache() end
end

-- Surgical invalidation when sub-craft routing or live recipe reagents change:
-- preserves raw AH/Snapshot/vendor price caches while clearing derived craft-route memos.
function ns.InvalidateCraftDecisionCache(bank)
	if type(bank) == "table" then
		bank.craftOpt = {}
		bank.smartCraft = {}
	end
	if ns._evalCache then
		ns._evalCache.craftOpt = (type(bank) == "table" and bank.craftOpt) or {}
		ns._evalCache.smartCraft = (type(bank) == "table" and bank.smartCraft) or {}
	end
	ns.InvalidateCrateTooltipCache()
	tooltipCraftMemo = {}
	if ns.MP and ns.MP.InvalidateSolveCache then ns.MP.InvalidateSolveCache() end
end

-- Surgical per-item price invalidation: clears ONLY affected item slots in active eval/UI price
-- caches plus derived craft-route/tooltip/solve memos WITHOUT bumping ns.priceCacheEpoch.
function ns.InvalidateItemPrices(itemIDs)
	local ids = {}
	if type(itemIDs) == "number" then
		if itemIDs > 0 then ids[itemIDs] = true end
	elseif type(itemIDs) == "table" then
		for k, v in pairs(itemIDs) do
			if type(v) == "number" and v > 0 then
				ids[v] = true
			elseif type(k) == "number" and k > 0 and v then
				ids[k] = true
			end
		end
	end
	if not next(ids) then return false end
	local ec = ns._evalCache
	local uiBank = ns.app and ns.app.uiPriceBank
	for id in pairs(ids) do
		if ec then
			ns.InvalidateEvalItem(ec, id)
		end
		if uiBank and uiBank ~= ec then
			ns.InvalidateEvalItem(uiBank, id)
		elseif not ec then
			ns.InvalidateEvalItem(nil, id)
		end
	end
	if ec then ec.candidates = {} end
	if uiBank and uiBank ~= ec then uiBank.candidates = {} end
	if uiBank and ec and ec.mktPrice ~= uiBank.mktPrice then
		uiBank.craftOpt = {}
		uiBank.smartCraft = {}
		ns.InvalidateCraftDecisionCache()
	else
		ns.InvalidateCraftDecisionCache(uiBank)
	end
	ns.InvalidateCrateTooltipCache()
	ns.InvalidateTooltipEconCache()
	if ns.MP and ns.MP.InvalidateSolveCache then ns.MP.InvalidateSolveCache() end
	return true
end

function ns.GetEffectivePriceVersion()
	return ns.priceCacheEpoch
end

local evalOptStack = {}

function ns.PushEvalOpts(opts)
	if type(opts) == "table" and (opts.craftableAllChars ~= nil or opts.knownRecipesOnly ~= nil or opts.unlockFilter ~= nil) then
		evalOptStack[#evalOptStack + 1] = opts
		return #evalOptStack
	end
	return nil
end

function ns.PopEvalOpts(token)
	if token then
		for i = #evalOptStack, token, -1 do
			evalOptStack[i] = nil
		end
	end
end

function ns.IsAllCharsCraftableActive(opts)
	if type(opts) == "table" and opts.currentCharOnly == true then return false end
	if type(opts) == "table" and opts.craftableAllChars ~= nil then
		return opts.craftableAllChars == true
	end
	local top = evalOptStack[#evalOptStack]
	if top and top.craftableAllChars ~= nil then
		return top.craftableAllChars == true
	end
	local db = ns.GetDB()
	if not db or db.craftableAllChars ~= true then return false end
	-- Falls back to Craftable Now DB state unless opts sets craftableAllChars or currentCharOnly.
	local knownOnly = (type(opts) == "table" and (opts.knownRecipesOnly == true or opts.unlockFilter == "known"))
		or (top and (top.knownRecipesOnly == true or top.unlockFilter == "known"))
		or (db.knownRecipesOnly == true) or (db.unlockFilter == "known")
	return knownOnly == true
end

function ns.BeginEval(bank)
	evalDepth = evalDepth + 1
	if evalDepth == 1 or not ns._evalCache or ns._evalCache.epoch ~= ns.priceCacheEpoch then
		if bank then
			if not bank.conservativeAnchor then bank.conservativeAnchor = {} end
			if not bank.realmDailySold then bank.realmDailySold = {} end
			if not bank.maxStack then bank.maxStack = {} end
		end
		ns._evalCache = {
			epoch = ns.priceCacheEpoch,
			mktPrice = (bank and bank.mktPrice) or {},
			reagentCost = (bank and bank.reagentCost) or {},
			numListed = (bank and bank.numListed) or {},
			dailySold = (bank and bank.dailySold) or {},
			vendorSell = (bank and bank.vendorSell) or {},
			lastKnownAH = (bank and bank.lastKnownAH) or {},
			conservativeAnchor = (bank and bank.conservativeAnchor) or {},
			realmDailySold = (bank and bank.realmDailySold) or {},
			maxStack = (bank and bank.maxStack) or {},
			craftOpt = (bank and bank.craftOpt) or {},
			smartCraft = (bank and bank.smartCraft) or {},
			candidates = (bank and bank.candidates) or {},
			itemNames = (bank and bank.itemNames) or {},
			itemIcons = (bank and bank.itemIcons) or {},
			activeEcon = nil,
			econInfo = nil,
			sellable = {},
			liveProfMap = nil,
			profMapByMode = {},
			repState = nil,
			knownRecByMode = { self = {}, all = {} },
			knownInfoByMode = { self = {}, all = {} },
			knownSpell = {},
			writCdByMode = { self = {}, all = {} },
			econChars = {},
		}
	end
	return ns._evalCache
end

function ns.EndEval()
	if evalDepth > 0 then
		evalDepth = evalDepth - 1
	end
	if evalDepth <= 0 then
		evalDepth = 0
		ns._evalCache = nil
		evalOptStack = {}
	end
end

function ns.ResetEval()
	evalDepth = 0
	ns._evalCache = nil
	evalOptStack = {}
end

function ns.RequestItemDataLoad(itemID)
	if not itemID or itemID <= 0 then return false end
	if not requestedItemIDs[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
		requestedItemIDs[itemID] = true
		ns.pendingItemLoads[itemID] = true
		pcall(C_Item.RequestLoadItemDataByID, itemID)
		return true
	end
	return false
end

function ns.ItemName(itemID, fallback)
	if not readable(fallback) then fallback = nil end
	if not readable(itemID) or type(itemID) ~= "number" or itemID <= 0 then
		return fallback or "Unknown"
	end
	local ec = ns._evalCache
	if ec and ec.itemNames[itemID] then
		return ec.itemNames[itemID]
	end
	local name
	if C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(itemID)
	elseif GetItemInfo then
		name = GetItemInfo(itemID)
	end
	if readable(name) and type(name) == "string" and name ~= "" then
		ns.ITEM_NAMES_BY_ID[itemID] = name
		ns.ITEM_IDS_BY_NAME[name] = itemID
		ns.pendingItemLoads[itemID] = nil
		if ec then ec.itemNames[itemID] = name end
		return name
	end
	local known = fallback or ns.ITEM_NAMES_BY_ID[itemID]
	if known and known ~= "" then
		if ec and (fallback == nil or known == ns.ITEM_NAMES_BY_ID[itemID]) then ec.itemNames[itemID] = known end
		return known
	end
	ns.RequestItemDataLoad(itemID)
	return "Item #" .. tostring(itemID)
end

function ns.GetRecipeDisplayName(recipe)
	if not readable(recipe) or type(recipe) ~= "table" then return "Unknown" end
	local rname = readable(recipe.name) and recipe.name or nil
	if type(rname) ~= "string" then rname = readable(recipe.n) and recipe.n or nil end
	if type(rname) == "string" and rname:find("^Transmute:") then return rname end
	return ns.ItemName(recipe.outputItemID, rname)
end

function ns.ItemIcon(itemID, defaultIcon)
	if itemID and itemID > 0 then
		local ec = ns._evalCache
		if ec and ec.itemIcons[itemID] then
			return ec.itemIcons[itemID]
		end
		if C_Item and C_Item.GetItemIconByID then
			local icon = C_Item.GetItemIconByID(itemID)
			if icon then
				if ec then ec.itemIcons[itemID] = icon end
				return icon
			end
		end
		if GetItemIcon then
			local icon = GetItemIcon(itemID)
			if icon then
				if ec then ec.itemIcons[itemID] = icon end
				return icon
			end
		end
	end
	return defaultIcon or QUESTION_ICON
end

function ns.FormatMoneyCompact(copper, colorizeSign)
	-- Themed golden g / silver s / copper c suffixes whenever the theme is loaded;
	-- the Blizzard coin-texture path below only serves bare (theme-less) hosts.
	local theme = ns.Theme
	if theme and theme.FormatMoneyParts then
		if copper == nil then
			return "|cff" .. ((theme.PALETTE and theme.PALETTE.hexMuted) or "777777") .. "—|r"
		end
		if theme.FormatMoneyText then -- FormatMoneyParts(...).text without the per-call table
			return theme.FormatMoneyText(copper, colorizeSign and true or "cost", false)
		end
		return theme.FormatMoneyParts(copper, colorizeSign and true or "cost", false).text
	end
	if copper == nil then
		return "|cff777777—|r"
	end
	local sign = copper < 0 and "-" or ""
	local val = math.floor(math.abs(copper) + 0.5)
	local gold = math.floor(val / 10000)
	local silver = math.floor((val % 10000) / 100)
	local cop = val % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = string.format("%d%s", gold, COIN_GOLD)
		if silver > 0 or cop > 0 then
			parts[#parts + 1] = string.format("%02d%s", silver, COIN_SILVER)
		end
		if cop > 0 then
			parts[#parts + 1] = string.format("%02d%s", cop, COIN_COPPER)
		end
	elseif silver > 0 then
		parts[#parts + 1] = string.format("%d%s", silver, COIN_SILVER)
		if cop > 0 then
			parts[#parts + 1] = string.format("%02d%s", cop, COIN_COPPER)
		end
	else
		parts[#parts + 1] = string.format("%d%s", cop, COIN_COPPER)
	end
	local text = sign .. table.concat(parts, " ")
	if colorizeSign then
		if copper > 0 then
			return "|cff33ff33+" .. text .. "|r"
		elseif copper < 0 then
			return "|cffff5555" .. text .. "|r"
		end
	elseif copper < 0 then
		return "|cff33ff33" .. text .. "|r"
	end
	return text
end

---------------------------------------------------------------------------------------------------
-- Base32 Compact Integer Decoder (used by MerchantMaster_Snapshots companion addon)

local function decodeBase32(val)
	if not val or val == "" then return 0 end
	if #val > 6 then
		local lower = tonumber(string.sub(val, -6), 32)
		local upper = tonumber(string.sub(val, 1, -7), 32)
		if lower and upper then
			return lower + upper * 1073741824 -- 2^30
		end
	end
	return tonumber(val, 32) or 0
end

---------------------------------------------------------------------------------------------------
-- Local Snapshot & 7x24 Heatmap Data Ingestion (MerchantMaster_Snapshots companion addon)

ns.snapshotRaw = ns.snapshotRaw or {}
ns.snapshotParsed = ns.snapshotParsed or {}
ns.snapshotHeatmapCache = ns.snapshotHeatmapCache or {}
ns.snapshotSystem = ns.snapshotSystem or nil

local SNAPSHOT_META_ENV_MT = {
	__newindex = function()
		error("snapshot meta sandbox is read-only", 2)
	end,
}

local function evalSnapshotLuaTable(rawData)
	if not readable(rawData) or type(rawData) ~= "string" or rawData == "" then
		return nil
	end
	if string.byte(rawData, 1) == 27 then
		return nil
	end
	local env = setmetatable({}, SNAPSHOT_META_ENV_MT)
	local fn
	if loadstring and setfenv then
		fn = loadstring(rawData)
		if type(fn) ~= "function" then return nil end
		setfenv(fn, env)
	elseif load then
		fn = load(rawData, "snapshot_meta", "t", env)
		if type(fn) ~= "function" then return nil end
	else
		return nil
	end
	local ok, tbl = pcall(fn)
	if not ok or type(tbl) ~= "table" then return nil end
	return tbl
end

local function parseSnapshotMeta(rawData)
	local tbl = evalSnapshotLuaTable(rawData)
	if not tbl then return nil end
	return {
		v = tonumber(tbl.v) or 1,
		updatedAt = tonumber(tbl.updatedAt) or 0,
		source = type(tbl.source) == "string" and tbl.source or "",
		windowDays = tonumber(tbl.windowDays) or 30,
		itemCount = tonumber(tbl.itemCount) or 0,
		heatmapCount = tonumber(tbl.heatmapCount) or 0,
		depthCount = tonumber(tbl.depthCount) or 0,
		velocityCount = tonumber(tbl.velocityCount) or 0,
		velocityObsHours = tonumber(tbl.velocityObsHours) or 0,
	}
end

local function parseSnapshotSystem(rawData)
	local tbl = evalSnapshotLuaTable(rawData)
	if not tbl then return nil end
	local tables = {}
	if type(tbl.tables) == "table" then
		for _, entry in ipairs(tbl.tables) do
			if type(entry) == "table" and type(entry.n) == "string" then
				tables[#tables + 1] = {
					n = entry.n,
					r = tonumber(entry.r) or 0,
					c = tonumber(entry.c) or 0,
					f = type(entry.f) == "string" and entry.f or "",
				}
			end
		end
	end
	return {
		v = tonumber(tbl.v) or 1,
		apiVersion = tbl.apiVersion ~= nil and tonumber(tbl.apiVersion) or nil,
		exportedAt = tonumber(tbl.exportedAt) or 0,
		exportBytes = tonumber(tbl.exportBytes) or 0,
		exportCapBytes = tonumber(tbl.exportCapBytes) or 0,
		truncated = tbl.truncated == true,
		retentionDays = tonumber(tbl.retentionDays) or 30,
		dbPath = type(tbl.dbPath) == "string" and tbl.dbPath or "",
		outDir = type(tbl.outDir) == "string" and tbl.outDir or "",
		dbBytes = tonumber(tbl.dbBytes) or 0,
		walBytes = tonumber(tbl.walBytes) or 0,
		shmBytes = tonumber(tbl.shmBytes) or 0,
		pageSize = tonumber(tbl.pageSize) or 0,
		pageCount = tonumber(tbl.pageCount) or 0,
		freelist = tonumber(tbl.freelist) or 0,
		journalMode = type(tbl.journalMode) == "string" and tbl.journalMode or "",
		localDataDirBytes = tonumber(tbl.localDataDirBytes) or 0,
		logBytes = tonumber(tbl.logBytes) or 0,
		logPolls = tonumber(tbl.logPolls) or 0,
		log304 = tonumber(tbl.log304) or 0,
		logExports = tonumber(tbl.logExports) or 0,
		logErrors = tonumber(tbl.logErrors) or 0,
		taskInstalled = tbl.taskInstalled == true,
		taskEnabled = tbl.taskEnabled == true,
		taskStatus = type(tbl.taskStatus) == "string" and tbl.taskStatus or "",
		taskRepeat = type(tbl.taskRepeat) == "string" and tbl.taskRepeat or "",
		taskNextRun = type(tbl.taskNextRun) == "string" and tbl.taskNextRun or "",
		region = type(tbl.region) == "string" and tbl.region or "",
		credsSet = tbl.credsSet == true,
		houseMap = type(tbl.houseMap) == "string" and tbl.houseMap or "",
		sourceMode = type(tbl.sourceMode) == "string" and tbl.sourceMode or "",
		intervalMin = tonumber(tbl.intervalMin) or 15,
		totalRuns = tonumber(tbl.totalRuns) or 0,
		blizzRuns = tonumber(tbl.blizzRuns) or 0,
		errRuns = tonumber(tbl.errRuns) or 0,
		lastError = type(tbl.lastError) == "string" and tbl.lastError or "",
		lastErrorAt = tonumber(tbl.lastErrorAt) or 0,
		tables = tables,
	}
end

local function resolveSnapshotEconomyKey(econOverride)
	if econOverride ~= nil and type(econOverride) == "string" and econOverride ~= "" and readable(econOverride) then
		return econOverride
	end
	local ec = ns._evalCache
	local db = ns.GetDB and ns.GetDB()
	local rawSelKey = (db and db.economy) or "auto"
	if rawSelKey == "tsm_alt" or rawSelKey == "region" then
		rawSelKey = "auto"
	end
	if ec and ec.econInfo and ec.econInfo._rawSelKey == rawSelKey then
		local ek = ec.econInfo.effectiveKey
		if type(ek) == "string" and ek ~= "" then return ek end
		return nil
	end
	if rawSelKey == "auto" and ns.DetectActiveEconomy then
		local activeEcon = ns.DetectActiveEconomy()
		if type(activeEcon) == "string" and activeEcon ~= "" then return activeEcon end
	end
	local econ = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo()
	if econ and type(econ.effectiveKey) == "string" and econ.effectiveKey ~= "" then
		return econ.effectiveKey
	end
	return nil
end

local snapshotsProbeAttempted = false
local snapshotApiMismatchWarned = false

local function getExpectedSnapshotApiVersion()
	local api = _G.MerchantMasterAPI
	if readable(api) and type(api) == "table" then
		local v = tonumber(api.API_VERSION)
		if v and v > 0 then return v end
	end
	return 1
end

local function recordSnapshotApiMismatch(actualVer, expectedVer, contextTag)
	local msg = string.format(
		"Snapshot data schema mismatch (%s): got apiVersion=%s, expected %d.",
		tostring(contextTag or "ingest"), tostring(actualVer), expectedVer
	)
	ns.snapshotApiMismatch = {
		expected = expectedVer,
		actual = actualVer,
		tag = contextTag,
		message = msg,
		at = (type(time) == "function" and time()) or 0,
	}
	if snapshotApiMismatchWarned then return end
	snapshotApiMismatchWarned = true
	if ns.ConsoleEngine and type(ns.ConsoleEngine.RecordWarning) == "function" then
		pcall(ns.ConsoleEngine.RecordWarning, "snapshot_api_version", msg)
	elseif _G.MerchantMasterLedgerDB and type(_G.MerchantMasterLedgerDB.probe) == "table"
		and type(_G.MerchantMasterLedgerDB.probe.log) == "table" then
		local log = _G.MerchantMasterLedgerDB.probe.log
		log[#log + 1] = {
			at = (type(time) == "function" and time()) or 0,
			tag = "SnapshotAPI",
			msg = msg,
		}
		while #log > 200 do table.remove(log, 1) end
	end
end

function ns.EnsureSnapshotsLoaded(force)
	if next(ns.snapshotRaw) ~= nil then return true end
	if not force and snapshotsProbeAttempted then return false end
	snapshotsProbeAttempted = true
	local loader = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
	if type(loader) == "function" then
		pcall(loader, "MerchantMaster_Snapshots")
	end
	return next(ns.snapshotRaw) ~= nil
end

function ns.ResetSnapshotsLoadAttempt()
	snapshotsProbeAttempted = false
end

local function bucketHasSnapshotItems(raw)
	if not readable(raw) or type(raw) ~= "table" then return false end
	if type(raw.latestChunks) == "table" and #raw.latestChunks > 0 then return true end
	if type(raw.heat24Chunks) == "table" and #raw.heat24Chunks > 0 then return true end
	if type(raw.heat7x24Chunks) == "table" and #raw.heat7x24Chunks > 0 then return true end
	if type(raw.depthChunks) == "table" and #raw.depthChunks > 0 then return true end
	if type(raw.velocityChunks) == "table" and #raw.velocityChunks > 0 then return true end
	local meta = raw.meta
	if readable(meta) and type(meta) == "table" then
		if (tonumber(meta.itemCount) or 0) > 0
			or (tonumber(meta.heatmapCount) or 0) > 0
			or (tonumber(meta.depthCount) or 0) > 0
			or (tonumber(meta.velocityCount) or 0) > 0 then
			return true
		end
	end
	return false
end

local function parsedHasSnapshotItems(parsed)
	if not readable(parsed) or type(parsed) ~= "table" then return false end
	if type(parsed.items) == "table" and next(parsed.items) ~= nil then return true end
	local meta = parsed.meta
	if readable(meta) and type(meta) == "table" then
		if (tonumber(meta.itemCount) or 0) > 0
			or (tonumber(meta.heatmapCount) or 0) > 0
			or (tonumber(meta.depthCount) or 0) > 0
			or (tonumber(meta.velocityCount) or 0) > 0 then
			return true
		end
	end
	return false
end

local function isSnapshotsAddonLoaded()
	if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
		local ok, loadedOrLoading, loaded = pcall(_G.C_AddOns.IsAddOnLoaded, "MerchantMaster_Snapshots")
		if ok and ((readable(loadedOrLoading) and loadedOrLoading == true) or (readable(loaded) and loaded == true)) then
			return true
		end
	elseif type(_G.IsAddOnLoaded) == "function" then
		local ok, loadedOrLoading, loaded = pcall(_G.IsAddOnLoaded, "MerchantMaster_Snapshots")
		if ok and ((readable(loadedOrLoading) and loadedOrLoading == true) or (readable(loaded) and loaded == true)) then
			return true
		end
	end
	return false
end

local function findSnapshotRaw(econKey)
	if type(econKey) ~= "string" or econKey == "" then return nil, nil end
	if next(ns.snapshotRaw) == nil then
		ns.EnsureSnapshotsLoaded()
	end
	local raw = ns.snapshotRaw[econKey]
	if raw then return raw, econKey end
	local lower = econKey:lower()
	for k, v in pairs(ns.snapshotRaw) do
		if type(k) == "string" and k:lower() == lower then
			return v, k
		end
	end
	return nil, nil
end

function ns.HasSnapshots(econOverride)
	if next(ns.snapshotRaw) == nil then
		ns.EnsureSnapshotsLoaded()
	end
	if type(econOverride) == "string" and econOverride ~= "" and readable(econOverride) then
		local raw = findSnapshotRaw(econOverride)
		if bucketHasSnapshotItems(raw) then return true end
		local parsed = ns.snapshotParsed and ns.snapshotParsed[econOverride]
		if parsedHasSnapshotItems(parsed) then return true end
		return false
	end
	if type(ns.snapshotRaw) == "table" then
		for _, raw in pairs(ns.snapshotRaw) do
			if bucketHasSnapshotItems(raw) then return true end
		end
	end
	if type(ns.snapshotParsed) == "table" then
		for _, parsed in pairs(ns.snapshotParsed) do
			if parsedHasSnapshotItems(parsed) then return true end
		end
	end
	if readable(ns.SnapshotMeta) and type(ns.SnapshotMeta) == "table" then
		if (tonumber(ns.SnapshotMeta.itemCount) or 0) > 0
			or (tonumber(ns.SnapshotMeta.heatmapCount) or 0) > 0 then
			return true
		end
		for _, meta in pairs(ns.SnapshotMeta) do
			if readable(meta) and type(meta) == "table"
				and ((tonumber(meta.itemCount) or 0) > 0 or (tonumber(meta.heatmapCount) or 0) > 0) then
				return true
			end
		end
	end
	if readable(ns.SnapshotData) and type(ns.SnapshotData) == "table" and next(ns.SnapshotData) ~= nil then
		return true
	end
	return false
end
ns.Pricing.HasSnapshots = ns.HasSnapshots

function ns.Pricing.GetSnapshotStatus(econOverride)
	if ns.HasSnapshots(econOverride) then
		return "active"
	end
	if (ns.HasSnapshotExtension and ns.HasSnapshotExtension())
		or (ns.app and ns.app.snapshotExtension ~= nil)
		or isSnapshotsAddonLoaded()
		or ns.snapshotSystem ~= nil
		or (type(ns.snapshotRaw) == "table" and next(ns.snapshotRaw) ~= nil) then
		return "installed_empty"
	end
	return "absent"
end

local lastSnapshotIngestEpoch = nil

function ns.IngestSnapshotData(tag, econKey, rawData, apiVersion)
	if not readable(tag) or not readable(econKey) or not readable(rawData) then return end
	if type(apiVersion) ~= "nil" then
		local expectedVer = getExpectedSnapshotApiVersion()
		local parsedVer = readable(apiVersion) and tonumber(apiVersion) or nil
		if not parsedVer or parsedVer ~= expectedVer then
			recordSnapshotApiMismatch(readable(apiVersion) and apiVersion or "secret", expectedVer, tag)
			return false
		end
	end
	if type(tag) ~= "string" or type(econKey) ~= "string" or econKey == "" or type(rawData) ~= "string" then
		return
	end
	if tag == "SYSTEM" then
		local sys = parseSnapshotSystem(rawData)
		if sys then
			if type(sys.apiVersion) ~= "nil" then
				local expectedVer = getExpectedSnapshotApiVersion()
				if sys.apiVersion ~= expectedVer then
					recordSnapshotApiMismatch(sys.apiVersion, expectedVer, "SYSTEM")
					return false
				end
			end
			ns.snapshotSystem = sys
		end
		return
	end
	if tag ~= "META" and tag ~= "LATEST" and tag ~= "HEAT24" and tag ~= "HEAT7X24"
		and tag ~= "DEPTH" and tag ~= "VELOCITY" then
		return
	end

	local bucket = ns.snapshotRaw[econKey]
	local hadBucketCache = bucket ~= nil and (
		bucket.heat24Index ~= nil
		or bucket.heat24Decoded ~= nil
		or bucket.heat24OverlayCache ~= nil
		or bucket.heat7x24Index ~= nil
		or bucket.depthIndex ~= nil
		or bucket.depthDecoded ~= nil
		or bucket.velocityParsed ~= nil
	)
	if tag == "META" then
		local meta = parseSnapshotMeta(rawData)
		if not meta then return end
		if not bucket or bucket.meta ~= nil then
			bucket = {
				meta = meta,
				latestChunks = {},
				heat24Chunks = {},
				heat24Index = nil,
				heat24Decoded = nil,
				heat24OverlayCache = nil,
				heat7x24Chunks = {},
				heat7x24Index = nil,
				depthChunks = {},
				depthIndex = nil,
				depthDecoded = nil,
				velocityChunks = {},
				velocityParsed = nil,
			}
			ns.snapshotRaw[econKey] = bucket
		else
			bucket.meta = meta
			bucket.heat24Decoded = nil
			bucket.heat24OverlayCache = nil
			bucket.velocityParsed = nil
		end
	else
		if not bucket then
			bucket = {
				meta = nil,
				latestChunks = {},
				heat24Chunks = {},
				heat24Index = nil,
				heat24Decoded = nil,
				heat24OverlayCache = nil,
				heat7x24Chunks = {},
				heat7x24Index = nil,
				depthChunks = {},
				depthIndex = nil,
				depthDecoded = nil,
				velocityChunks = {},
				velocityParsed = nil,
			}
			ns.snapshotRaw[econKey] = bucket
		end
		if tag == "LATEST" then
			bucket.latestChunks[#bucket.latestChunks + 1] = rawData
		elseif tag == "HEAT24" then
			bucket.heat24Chunks[#bucket.heat24Chunks + 1] = rawData
			bucket.heat24Index = nil
			bucket.heat24Decoded = nil
			bucket.heat24OverlayCache = nil
		elseif tag == "HEAT7X24" then
			bucket.heat7x24Chunks[#bucket.heat7x24Chunks + 1] = rawData
			bucket.heat7x24Index = nil
		elseif tag == "DEPTH" then
			bucket.depthChunks = bucket.depthChunks or {}
			bucket.depthChunks[#bucket.depthChunks + 1] = rawData
			bucket.depthIndex = nil
			bucket.depthDecoded = nil
		elseif tag == "VELOCITY" then
			bucket.velocityChunks = bucket.velocityChunks or {}
			bucket.velocityChunks[#bucket.velocityChunks + 1] = rawData
			bucket.velocityParsed = nil
		end
	end

	local hadParsed = ns.snapshotParsed[econKey] ~= nil
	local hadHeatmap = ns.snapshotHeatmapCache[econKey] ~= nil
	if tag == "META" or tag == "LATEST" then
		ns.snapshotParsed[econKey] = nil
	end
	if tag == "META" or tag == "HEAT7X24" then
		ns.snapshotHeatmapCache[econKey] = nil
	end
	if (tag == "META" or hadParsed or hadHeatmap or hadBucketCache or ns._evalCache ~= nil or lastSnapshotIngestEpoch ~= ns.priceCacheEpoch)
		and ns.InvalidatePriceCache then
		ns.InvalidatePriceCache()
		lastSnapshotIngestEpoch = ns.priceCacheEpoch
	end
end

_G.MERCHANTMASTER_LOAD_SNAPSHOTS = ns.IngestSnapshotData
ns.Pricing.IngestSnapshotData = ns.IngestSnapshotData

local function parseSnapshotLatestChunk(chunk, items, metaUpdatedAt, metaSource)
	if type(chunk) ~= "string" or chunk == "" then return end
	for entry in string.gmatch(chunk, "([^;\r\n]+)") do
		local idStr, rest = string.match(entry, "^%s*(%d+):(.*)$")
		local id = idStr and tonumber(idStr)
		if id and id > 0 and rest then
			local f1, f2, f3, f4, f5, f6 = string.match(rest, "^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,%s]*)")
			if f1 ~= nil then
				local minB = decodeBase32(f1)
				local mkt = decodeBase32(f2)
				local hist = decodeBase32(f3)
				local qty = decodeBase32(f4)
				local numA = decodeBase32(f5)
				local tsDelta = decodeBase32(f6)
				items[id] = {
					minBuyout = (minB > 0 and qty > 0) and minB or nil,
					marketValue = mkt > 0 and mkt or nil,
					historical = hist > 0 and hist or nil,
					qty = qty,
					numAuctions = numA,
					updatedAt = metaUpdatedAt - tsDelta,
					source = metaSource,
				}
			end
		end
	end
end

local function ensureHeat24Index(raw)
	if raw.heat24Index then return raw.heat24Index end
	local idx = {}
	local chunks = raw.heat24Chunks
	if chunks then
		for i = 1, #chunks do
			local chunk = chunks[i]
			if type(chunk) == "string" and chunk ~= "" then
				for entry in string.gmatch(chunk, "([^;\r\n]+)") do
					local idStr, rest = string.match(entry, "^%s*(%d+):(.*)$")
					local id = idStr and tonumber(idStr)
					if id and id > 0 and rest and rest ~= "" then
						idx[id] = rest
					end
				end
			end
		end
	end
	raw.heat24Index = idx
	return idx
end

local function parseHeat24Entry(rest, metaUpdatedAt, metaSource)
	local pipePos = string.find(rest, "|", 1, true)
	local headStr = pipePos and string.sub(rest, 1, pipePos - 1) or rest
	local hoursStr = pipePos and string.sub(rest, pipePos + 1) or ""
	local medS, avgS, avgQtyS, cvS, sampS, bbSlotS, bbPS, bsSlotS, bsPS =
		string.match(headStr, "^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,%s]*)")
	if medS == nil then return nil end
	local bbSlot = tonumber(bbSlotS)
	local bestBuy = nil
	if bbSlot and bbSlot >= 0 and bbSlot <= 167 then
		bestBuy = {
			dow = math.floor(bbSlot / 24) + 1,
			hour = bbSlot % 24,
			price = decodeBase32(bbPS),
		}
	end
	local bsSlot = tonumber(bsSlotS)
	local bestSell = nil
	if bsSlot and bsSlot >= 0 and bsSlot <= 167 then
		bestSell = {
			dow = math.floor(bsSlot / 24) + 1,
			hour = bsSlot % 24,
			price = decodeBase32(bsPS),
		}
	end
	local hourly = {}
	if hoursStr ~= "" then
		local idx = 0
		local pos = 1
		local len = #hoursStr
		while idx <= 23 do
			local comma = string.find(hoursStr, ",", pos, true)
			local tok
			if comma then
				tok = string.sub(hoursStr, pos, comma - 1)
				pos = comma + 1
			else
				tok = string.sub(hoursStr, pos, len)
			end
			if tok ~= "" then
				local v = decodeBase32(tok)
				if v > 0 then
					hourly[idx] = v
				end
			end
			if not comma then break end
			idx = idx + 1
		end
	end
	return {
		hourly = hourly,
		medianPrice = decodeBase32(medS),
		avgPrice = decodeBase32(avgS),
		avgQty = decodeBase32(avgQtyS),
		cvPct = decodeBase32(cvS),
		totalSamples = decodeBase32(sampS),
		bestBuy = bestBuy,
		bestSell = bestSell,
		updatedAt = metaUpdatedAt,
		source = metaSource,
	}
end

local function getDecodedHeat24(raw, id)
	if not raw or not raw.heat24Chunks or #raw.heat24Chunks == 0 then return nil end
	local decoded = raw.heat24Decoded
	if not decoded then
		decoded = {}
		raw.heat24Decoded = decoded
	end
	local base = decoded[id]
	if base ~= nil then
		return base ~= false and base or nil
	end
	local idx = ensureHeat24Index(raw)
	local rest = idx[id]
	if not rest or rest == "" then
		decoded[id] = false
		return nil
	end
	local meta = raw.meta
	local metaUpdatedAt = (meta and meta.updatedAt) or 0
	local metaSource = (meta and meta.source ~= "" and meta.source) or "snapshot"
	base = parseHeat24Entry(rest, metaUpdatedAt, metaSource)
	decoded[id] = base or false
	return base
end

local function getParsedSnapshotLatest(econKey)
	local raw, resolvedKey = findSnapshotRaw(econKey)
	if not raw then return nil, nil end
	local cached = ns.snapshotParsed[resolvedKey]
	if cached then return cached, resolvedKey end

	local meta = raw.meta
	local metaUpdatedAt = (meta and meta.updatedAt) or 0
	local metaSource = (meta and meta.source ~= "" and meta.source) or "snapshot"

	local items = {}
	local chunks = raw.latestChunks
	if chunks then
		for i = 1, #chunks do
			parseSnapshotLatestChunk(chunks[i], items, metaUpdatedAt, metaSource)
		end
	end

	local parsed = {
		meta = meta,
		items = items,
	}
	ns.snapshotParsed[resolvedKey] = parsed
	return parsed, resolvedKey
end

function ns.QueryLocalSnapshot(itemID, econOverride, field)
	if not readable(itemID) then return nil, nil end
	local id = tonumber(itemID)
	if not id or id <= 0 then return nil, nil end
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return nil, nil end
	local parsed = getParsedSnapshotLatest(econKey)
	local rec = parsed and parsed.items and parsed.items[id]
	if not rec then return nil, nil end
	local isListed = (rec.qty == nil or rec.qty > 0)
	local liveMin = (isListed and rec.minBuyout and rec.minBuyout > 0) and rec.minBuyout or nil
	if field == "minBuyout" then
		return liveMin, rec
	end
	local price = liveMin
		or ((rec.marketValue and rec.marketValue > 0) and rec.marketValue
		or ((rec.historical and rec.historical > 0) and rec.historical or nil))
	return price, rec
end

function ns.Pricing.GetItemSnapshotLatest(itemID, econOverride, field)
	local val, rec = ns.QueryLocalSnapshot(itemID, econOverride, field)
	if field == "minBuyout" then
		return val, rec
	end
	return rec, val
end

local RULESET_META = {
	normal = { label = "Normal", rank = 1 },
	pvp = { label = "PvP", rank = 2 },
	rp = { label = "RP", rank = 3 },
	roleplay = { label = "RP", rank = 3 },
	rppvp = { label = "RPPvP", rank = 4 },
	["rp-pvp"] = { label = "RPPvP", rank = 4 },
	["roleplay pvp"] = { label = "RPPvP", rank = 4 },
	hardcore = { label = "Hardcore", rank = 5 },
	hc = { label = "Hardcore", rank = 5 },
}

local FACTION_META = {
	horde = { label = "Horde", rank = 1 },
	alliance = { label = "Alliance", rank = 2 },
	blackwater = { label = "Blackwater", rank = 3 },
}

local function parseEconomyHouseInfo(econKey)
	local rsPart, facPart = string.match(tostring(econKey or ""), "^(.-)%-([^%-]+)$")
	if not rsPart then
		return tostring(econKey or ""), "Other", 99, 9
	end
	local rsInfo = RULESET_META[rsPart:lower()]
	local facInfo = FACTION_META[facPart:lower()]
	return (rsInfo and rsInfo.label) or rsPart,
		(facInfo and facInfo.label) or facPart,
		(rsInfo and rsInfo.rank) or 99,
		(facInfo and facInfo.rank) or 9
end

function ns.Pricing.GetAllAuctionHousesForItem(itemID, homeEconOverride)
	if not readable(itemID) then return nil end
	local id = tonumber(itemID)
	if not id or id <= 0 then return nil end
	ns.EnsureSnapshotsLoaded()

	local homeEcon = resolveSnapshotEconomyKey(homeEconOverride)
	local homeLower = homeEcon and homeEcon:lower() or nil
	local rows = {}
	local homeMin = nil

	for ek, raw in pairs(ns.snapshotRaw) do
		if type(ek) == "string" and ek ~= "" and type(raw) == "table"
			and ((raw.latestChunks and #raw.latestChunks > 0) or raw.meta ~= nil) then
			local liveMin, rec = ns.QueryLocalSnapshot(id, ek, "minBuyout")
			local qty = (rec and tonumber(rec.qty)) or 0
			local isListed = (qty > 0 and liveMin ~= nil and liveMin > 0)
			local minB = isListed and liveMin or nil
			local mktV = (isListed and rec and rec.marketValue and rec.marketValue > 0) and rec.marketValue or nil
			local numA = (isListed and rec and tonumber(rec.numAuctions)) or 0
			local updatedAt = (rec and rec.updatedAt) or (raw.meta and raw.meta.updatedAt) or nil
			local rsLabel, facLabel, rsRank, facRank = parseEconomyHouseInfo(ek)
			local isHome = (homeLower ~= nil and ek:lower() == homeLower)
			if isHome and minB then
				homeMin = minB
			end
			rows[#rows + 1] = {
				economy = ek,
				ruleset = rsLabel,
				faction = facLabel,
				rulesetRank = rsRank,
				factionRank = facRank,
				isHome = isHome,
				listed = isListed,
				minBuyout = minB,
				marketValue = mktV,
				qty = isListed and qty or 0,
				numAuctions = numA,
				updatedAt = updatedAt,
				diffPct = nil,
			}
		end
	end

	table.sort(rows, function(a, b)
		if a.rulesetRank ~= b.rulesetRank then return a.rulesetRank < b.rulesetRank end
		if a.factionRank ~= b.factionRank then return a.factionRank < b.factionRank end
		return a.economy < b.economy
	end)

	local listedHouses, totalQty = 0, 0
	local lowest, highest = nil, nil
	for i = 1, #rows do
		local row = rows[i]
		if row.listed and row.minBuyout and row.minBuyout > 0 then
			listedHouses = listedHouses + 1
			totalQty = totalQty + row.qty
			if homeMin and homeMin > 0 then
				row.diffPct = ((row.minBuyout - homeMin) / homeMin) * 100
			end
			if not lowest or row.minBuyout < lowest.minBuyout then
				lowest = row
			end
			if not highest or row.minBuyout > highest.minBuyout then
				highest = row
			end
		end
	end

	return {
		homeEcon = homeEcon,
		homeMin = homeMin,
		totalHouses = #rows,
		listedHouses = listedHouses,
		totalQty = totalQty,
		lowest = lowest,
		highest = highest,
		rows = rows,
	}
end

ns.GetAllAuctionHousesForItem = ns.Pricing.GetAllAuctionHousesForItem

local function getSnapshotMetaRaw(econOverride)
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return nil end
	local raw = findSnapshotRaw(econKey)
	return raw and raw.meta or nil
end

function ns.Pricing.GetSnapshotSystemMeta()
	if ns.snapshotSystem == nil then
		ns.EnsureSnapshotsLoaded()
	end
	return ns.snapshotSystem
end

function ns.Pricing.GetSnapshotMeta(econOverride)
	local m = getSnapshotMetaRaw(econOverride)
	if not m then return nil end
	return {
		updatedAt = m.updatedAt,
		source = m.source,
		windowDays = m.windowDays,
		itemCount = m.itemCount,
		heatmapCount = m.heatmapCount,
		depthCount = m.depthCount or 0,
		velocityCount = m.velocityCount or 0,
		velocityObsHours = m.velocityObsHours or 0,
	}
end

function ns.Pricing.IsSnapshotFresh(econOverride, maxAgeSec)
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return false, nil, nil end
	local meta = getSnapshotMetaRaw(econKey)
	if not meta or type(meta.updatedAt) ~= "number" or meta.updatedAt <= 0 then
		return false, nil, meta
	end
	local now = (type(time) == "function" and time()) or 0
	if now <= 0 then
		return false, nil, meta
	end
	local ageSec = math.max(0, now - meta.updatedAt)
	local limit = (type(maxAgeSec) == "number" and maxAgeSec > 0) and maxAgeSec or SNAPSHOT_FRESH_SECONDS
	return ageSec <= limit, ageSec, meta
end

local function ensureDepthIndex(raw)
	if raw.depthIndex then return raw.depthIndex end
	local idx = {}
	local chunks = raw.depthChunks
	if chunks then
		for i = 1, #chunks do
			local chunk = chunks[i]
			if type(chunk) == "string" and chunk ~= "" then
				for entry in string.gmatch(chunk, "([^;\r\n]+)") do
					local idStr, payload = string.match(entry, "^%s*(%d+):(.*)$")
					local id = idStr and tonumber(idStr)
					if id and id > 0 and payload and payload ~= "" then
						idx[id] = payload
					end
				end
			end
		end
	end
	raw.depthIndex = idx
	return idx
end

function ns.Pricing.GetItemSnapshotDepth(itemID, econOverride)
	if not readable(itemID) then return nil end
	local id = tonumber(itemID)
	if not id or id <= 0 then return nil end
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return nil end
	local raw = findSnapshotRaw(econKey)
	if not raw or not raw.depthChunks or #raw.depthChunks == 0 then return nil end

	local decoded = raw.depthDecoded
	if not decoded then
		decoded = {}
		raw.depthDecoded = decoded
	end
	local tiers = decoded[id]
	if tiers == nil then
		local idx = ensureDepthIndex(raw)
		local payload = idx[id]
		if not payload or payload == "" then
			decoded[id] = false
			return nil
		end
		local parsedTiers = {}
		local needsSort = false
		local prevPrice = 0
		for seg in string.gmatch(payload, "([^|]+)") do
			local pS, qS = string.match(seg, "^%s*([^,]+),([^,%s]+)")
			if pS and qS then
				local p = decodeBase32(pS)
				local q = decodeBase32(qS)
				if p > 0 and q > 0 then
					if p < prevPrice then needsSort = true end
					prevPrice = p
					parsedTiers[#parsedTiers + 1] = { price = p, qty = q }
				end
			end
		end
		if #parsedTiers == 0 then
			decoded[id] = false
			return nil
		end
		if needsSort then
			table.sort(parsedTiers, function(a, b) return a.price < b.price end)
		end
		decoded[id] = parsedTiers
		tiers = parsedTiers
	end
	if tiers == false then return nil end
	local out = {}
	for i = 1, #tiers do
		out[i] = { price = tiers[i].price, qty = tiers[i].qty }
	end
	return out
end

local function ensureVelocityParsed(raw)
	if raw.velocityParsed then return raw.velocityParsed end
	local parsed = {}
	local chunks = raw.velocityChunks
	local meta = raw.meta
	local metaUpdatedAt = (meta and meta.updatedAt) or 0
	local metaSource = (meta and meta.source ~= "" and meta.source) or "snapshot"
	if chunks then
		for i = 1, #chunks do
			local chunk = chunks[i]
			if type(chunk) == "string" and chunk ~= "" then
				for entry in string.gmatch(chunk, "([^;\r\n]+)") do
					local idStr, rest = string.match(entry, "^%s*(%d+):(.*)$")
					local id = idStr and tonumber(idStr)
					if id and id > 0 and rest then
						local f1, f2, f3, f4 = string.match(rest, "^([^,]*),([^,]*),([^,]*),([^,%s]*)")
						if f1 ~= nil then
							local estX1000 = decodeBase32(f1)
							local obsHours = decodeBase32(f2)
							local conf = decodeBase32(f3)
							local raw7d = decodeBase32(f4)
							parsed[id] = {
								estDailySold = estX1000 / 1000,
								obsHours = obsHours,
								confidence = conf,
								raw7d = raw7d,
								updatedAt = metaUpdatedAt,
								source = metaSource,
							}
						end
					end
				end
			end
		end
	end
	raw.velocityParsed = parsed
	return parsed
end

local function getItemSnapshotVelocityRaw(itemID, econOverride)
	if not readable(itemID) then return nil end
	local id = tonumber(itemID)
	if not id or id <= 0 then return nil end
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return nil end
	local raw = findSnapshotRaw(econKey)
	if not raw or not raw.velocityChunks or #raw.velocityChunks == 0 then return nil end
	local parsed = ensureVelocityParsed(raw)
	return parsed[id]
end

function ns.Pricing.GetItemSnapshotVelocity(itemID, econOverride)
	local rec = getItemSnapshotVelocityRaw(itemID, econOverride)
	if not rec then return nil end
	return {
		estDailySold = rec.estDailySold,
		obsHours = rec.obsHours,
		confidence = rec.confidence,
		raw7d = rec.raw7d,
		updatedAt = rec.updatedAt,
		source = rec.source,
	}
end

local function localDowHour(ts)
	local fn = date or (os and os.date)
	if type(fn) == "function" then
		local ok, t = pcall(fn, "*t", ts)
		if ok and type(t) == "table" and type(t.wday) == "number" and type(t.hour) == "number" then
			-- Lua wday: Sun=1, Mon=2..Sat=7 -> ISO Mon=1..Sun=7
			return ((t.wday + 5) % 7) + 1, t.hour
		end
	end
	local day = math.floor(ts / 86400)
	return ((day + 3) % 7) + 1, math.floor((ts % 86400) / 3600)
end

local function collectLiveScanOverlay(itemID, econKey, minTs)
	local db = ns.GetDB and ns.GetDB()
	if not readable(db) or type(db) ~= "table" then return nil, 0, 0 end
	local bySlot, byHour, seenTs = nil, nil, nil
	local maxTs, count = 0, 0
	local function addSample(ts, price, qty)
		ts = demandNumber(ts)
		price = demandNumber(price)
		if not ts or ts <= minTs or not price or price <= 0 then return end
		if seenTs and seenTs[ts] then return end
		if not seenTs then seenTs = {} end
		seenTs[ts] = true
		qty = demandNumber(qty) or 0
		local dow, hour = localDowHour(ts)
		local slot = (dow - 1) * 24 + hour
		if not bySlot then
			bySlot = {}
			byHour = {}
		end
		local s = bySlot[slot]
		if not s then
			bySlot[slot] = { dow = dow, hour = hour, sumP = price, sumQ = qty, minP = price, n = 1 }
		else
			s.sumP = s.sumP + price
			s.sumQ = s.sumQ + qty
			if price < s.minP then s.minP = price end
			s.n = s.n + 1
		end
		local h = byHour[hour]
		if not h then
			byHour[hour] = { sumP = price, n = 1, latestAt = ts, latestDow = dow }
		else
			h.sumP = h.sumP + price
			h.n = h.n + 1
			if ts >= h.latestAt then h.latestAt = ts; h.latestDow = dow end
		end
		if ts > maxTs then maxTs = ts end
		count = count + 1
	end

	local snapsRoot = readable(db.ahSnapshots) and type(db.ahSnapshots) == "table" and db.ahSnapshots
	local econSnaps = snapsRoot and readable(snapsRoot[econKey]) and type(snapsRoot[econKey]) == "table" and snapsRoot[econKey]
	local snapRaw = econSnaps and econSnaps[itemID]
	local snapArr = (ns.MarketScan and ns.MarketScan.ReadSnapshots and ns.MarketScan.ReadSnapshots(snapRaw))
		or (readable(snapRaw) and type(snapRaw) == "table" and snapRaw or nil)
	if snapArr then
		for i = 1, #snapArr - 2, 3 do
			addSample(snapArr[i], snapArr[i + 1], snapArr[i + 2])
		end
	end

	local pricesRoot = readable(db.ahPrices) and type(db.ahPrices) == "table" and db.ahPrices
	local econPrices = pricesRoot and readable(pricesRoot[econKey]) and type(pricesRoot[econKey]) == "table" and pricesRoot[econKey]
	local priceRec = econPrices and readable(econPrices[itemID]) and type(econPrices[itemID]) == "table" and econPrices[itemID]
	if priceRec and readable(priceRec.absent) and not priceRec.absent then
		addSample(priceRec.at, priceRec.price, priceRec.qty)
	end

	if not bySlot then return nil, 0, 0 end
	return { bySlot = bySlot, byHour = byHour }, maxTs, count
end

function ns.Pricing.GetItemHeatStrip24h(itemID, econOverride)
	local id
	if type(itemID) == "number" then
		if not readable(itemID) or itemID <= 0 then return nil end
		id = itemID
	else
		if not readable(itemID) then return nil end
		id = tonumber(itemID)
		if not id or id <= 0 then return nil end
	end
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return nil end
	local raw, resolvedKey = findSnapshotRaw(econKey)
	if not raw then return nil end
	local base = getDecodedHeat24(raw, id)
	if not base then return nil end

	local db = ns.GetDB and ns.GetDB()
	if type(db) ~= "table" or not readable(db) then
		return base
	end
	local liveEcon = resolvedKey or econKey
	local snapsRoot = db.ahSnapshots
	local econSnaps = (type(snapsRoot) == "table" and readable(snapsRoot)) and snapsRoot[liveEcon] or nil
	local snapRaw = (type(econSnaps) == "table" and readable(econSnaps)) and econSnaps[id] or nil
	local packedSnap = (type(snapRaw) == "string" and readable(snapRaw) and snapRaw:sub(1, 3) == "v1:") and snapRaw or nil

	local baseUpdatedAt = base.updatedAt or 0
	local pricesRoot = db.ahPrices
	local econPrices = (type(pricesRoot) == "table" and readable(pricesRoot)) and pricesRoot[liveEcon] or nil
	local priceRec = (type(econPrices) == "table" and readable(econPrices)) and econPrices[id] or nil
	local priceRecAt, priceRecVal = nil, nil
	if type(priceRec) == "table" and readable(priceRec) and readable(priceRec.absent) and not priceRec.absent then
		local at = priceRec.at
		if type(at) == "number" and at > baseUpdatedAt and readable(at) and at == at and at < math.huge then
			local pv = demandNumber(priceRec.price)
			if pv and pv > 0 then
				priceRecAt = at
				priceRecVal = pv
			end
		end
	end

	local oCache = raw.heat24OverlayCache
	local cached = oCache and oCache[id]
	if packedSnap and cached
		and cached.baseUpdatedAt == baseUpdatedAt
		and cached.snapRaw == packedSnap
		and cached.priceRecAt == priceRecAt
		and cached.priceRecVal == priceRecVal then
		return cached.result
	end

	local snapArr = nil
	if packedSnap then
		snapArr = ns.MarketScan and ns.MarketScan.ReadSnapshots and ns.MarketScan.ReadSnapshots(packedSnap) or nil
	elseif type(snapRaw) == "table" and readable(snapRaw) then
		snapArr = snapRaw
	end
	local snapLen = snapArr and #snapArr or 0

	if snapLen < 3 and not priceRecAt then
		return base
	end

	local firstSnapTs, lastSnapTs, lastSnapVal = nil, nil, nil
	if snapLen >= 3 then
		local lastIdx = math.floor((snapLen - 3) / 3) * 3 + 1
		firstSnapTs = demandNumber(snapArr[1])
		lastSnapTs = demandNumber(snapArr[lastIdx])
		lastSnapVal = demandNumber(snapArr[lastIdx + 1])
	end

	if not packedSnap and cached
		and cached.baseUpdatedAt == baseUpdatedAt
		and cached.snapRaw == nil
		and cached.snapArr == snapArr
		and cached.snapLen == snapLen
		and cached.firstSnapTs == firstSnapTs
		and cached.lastSnapTs == lastSnapTs
		and cached.lastSnapVal == lastSnapVal
		and cached.priceRecAt == priceRecAt
		and cached.priceRecVal == priceRecVal then
		return cached.result
	end

	local overlay, maxTs, liveCount = collectLiveScanOverlay(id, liveEcon, baseUpdatedAt)
	local result
	if not overlay then
		result = base
	else
		local hourlyCopy = {}
		if type(base.hourly) == "table" then
			for h = 0, 23 do
				if base.hourly[h] ~= nil then
					hourlyCopy[h] = base.hourly[h]
				end
			end
		end
		local bestBuy = base.bestBuy and { dow = base.bestBuy.dow, hour = base.bestBuy.hour, price = base.bestBuy.price } or nil
		local bestSell = base.bestSell and { dow = base.bestSell.dow, hour = base.bestSell.hour, price = base.bestSell.price } or nil
		for hr, rec in pairs(overlay.byHour) do
			local liveP = math.floor((rec.sumP / rec.n) + 0.5)
			hourlyCopy[hr] = liveP
			if bestBuy and liveP < bestBuy.price then
				bestBuy = { dow = rec.latestDow, hour = hr, price = liveP }
			end
			if bestSell and liveP > bestSell.price then
				bestSell = { dow = rec.latestDow, hour = hr, price = liveP }
			end
		end
		local vals = {}
		local sumP = 0
		for h = 0, 23 do
			local v = hourlyCopy[h]
			if type(v) == "number" and v > 0 then
				vals[#vals + 1] = v
				sumP = sumP + v
			end
		end
		local avgP = (#vals > 0) and math.floor((sumP / #vals) + 0.5) or base.avgPrice
		local medP = base.medianPrice
		if #vals > 0 then
			table.sort(vals)
			if #vals % 2 == 1 then
				medP = vals[(#vals + 1) / 2]
			else
				local mid = #vals / 2
				medP = math.floor((vals[mid] + vals[mid + 1]) / 2 + 0.5)
			end
		end
		result = {
			hourly = hourlyCopy,
			medianPrice = medP,
			avgPrice = avgP,
			avgQty = base.avgQty,
			cvPct = base.cvPct,
			totalSamples = (base.totalSamples or 0) + liveCount,
			bestBuy = bestBuy,
			bestSell = bestSell,
			updatedAt = math.max(baseUpdatedAt, maxTs),
			source = base.source,
			hasLiveOverlay = true,
			liveUpdatedAt = maxTs,
		}
	end

	if not oCache then
		oCache = {}
		raw.heat24OverlayCache = oCache
	end
	oCache[id] = {
		baseUpdatedAt = baseUpdatedAt,
		snapRaw = packedSnap,
		snapArr = snapArr,
		snapLen = snapLen,
		firstSnapTs = firstSnapTs,
		lastSnapTs = lastSnapTs,
		lastSnapVal = lastSnapVal,
		priceRecAt = priceRecAt,
		priceRecVal = priceRecVal,
		result = result,
	}
	return result
end

local function round1Decimal(x)
	if type(x) ~= "number" or x ~= x then return 0 end
	local r
	if x >= 0 then
		r = math.floor(x * 10 + 0.5) / 10
	else
		r = math.ceil(x * 10 - 0.5) / 10
	end
	if r == 0 then return 0 end
	return r
end

local function ensureHeat7x24Index(raw)
	if raw.heat7x24Index then return raw.heat7x24Index end
	local idx = {}
	local chunks = raw.heat7x24Chunks
	if chunks then
		for i = 1, #chunks do
			local chunk = chunks[i]
			if type(chunk) == "string" and chunk ~= "" then
				for entry in string.gmatch(chunk, "([^;\r\n]+)") do
					local idStr, payload = string.match(entry, "^%s*(%d+):(.*)$")
					local id = idStr and tonumber(idStr)
					if id and id > 0 and payload and payload ~= "" then
						idx[id] = payload
					end
				end
			end
		end
	end
	raw.heat7x24Index = idx
	return idx
end

local function finalizeHeatmapGrid(cells, meta, id, resolvedKey, liveUpdatedAt)
	local dailyAcc = {}
	local hourlyAcc = {}
	local allPrices = {}
	local totalW = 0
	local totalSamples = 0
	local sumPriceW = 0
	local sumQtyW = 0
	local overallMin = nil
	local overallMax = nil
	local populatedCount = 0

	for dow = 1, 7 do
		local row = cells[dow]
		for hour = 0, 23 do
			local cell = row[hour]
			if cell and cell.avgPrice and cell.avgPrice > 0 then
				local avgP = cell.avgPrice
				local minP = (cell.minPrice and cell.minPrice > 0) and cell.minPrice or avgP
				local avgQ = cell.avgQty or 0
				local samples = cell.samples or 0
				local w = (samples > 0) and samples or 1

				populatedCount = populatedCount + 1
				allPrices[populatedCount] = avgP
				totalW = totalW + w
				totalSamples = totalSamples + samples
				sumPriceW = sumPriceW + avgP * w
				sumQtyW = sumQtyW + avgQ * w
				if not overallMin or minP < overallMin then overallMin = minP end
				if not overallMax or avgP > overallMax then overallMax = avgP end

				local da = dailyAcc[dow]
				if not da then
					dailyAcc[dow] = { sumP = avgP * w, sumQ = avgQ * w, w = w, minP = minP, samples = samples }
				else
					da.sumP = da.sumP + avgP * w
					da.sumQ = da.sumQ + avgQ * w
					da.w = da.w + w
					if minP < da.minP then da.minP = minP end
					da.samples = da.samples + samples
				end

				local ha = hourlyAcc[hour]
				if not ha then
					hourlyAcc[hour] = { sumP = avgP * w, sumQ = avgQ * w, w = w, minP = minP, samples = samples }
				else
					ha.sumP = ha.sumP + avgP * w
					ha.sumQ = ha.sumQ + avgQ * w
					ha.w = ha.w + w
					if minP < ha.minP then ha.minP = minP end
					ha.samples = ha.samples + samples
				end
			end
		end
	end

	if populatedCount == 0 then return nil end

	local overallAvg = math.floor((sumPriceW / totalW) + 0.5)
	local overallQty = math.floor((sumQtyW / totalW) + 0.5)

	table.sort(allPrices)
	local medianPrice
	if populatedCount % 2 == 1 then
		medianPrice = allPrices[(populatedCount + 1) / 2]
	else
		local mid = populatedCount / 2
		medianPrice = math.floor((allPrices[mid] + allPrices[mid + 1]) / 2 + 0.5)
	end

	local cvPct = 0
	if populatedCount > 1 and overallAvg > 0 then
		local sumSq = 0
		for i = 1, populatedCount do
			local d = allPrices[i] - overallAvg
			sumSq = sumSq + d * d
		end
		local stdDev = math.sqrt(sumSq / populatedCount)
		cvPct = math.floor((stdDev / overallAvg) * 100 + 0.5)
	end

	local bestBuy = nil
	local bestSell = nil
	for dow = 1, 7 do
		local row = cells[dow]
		for hour = 0, 23 do
			local cell = row[hour]
			if cell then
				cell.pctVsAvg = (overallAvg > 0) and round1Decimal(((cell.avgPrice - overallAvg) / overallAvg) * 100) or 0
				if not bestBuy
					or cell.avgPrice < bestBuy.avgPrice
					or (cell.avgPrice == bestBuy.avgPrice and cell.minPrice < bestBuy.minPrice) then
					bestBuy = {
						dow = dow,
						hour = hour,
						avgPrice = cell.avgPrice,
						minPrice = cell.minPrice,
						pctVsAvg = cell.pctVsAvg,
					}
				end
				if not bestSell
					or cell.avgPrice > bestSell.avgPrice
					or (cell.avgPrice == bestSell.avgPrice and cell.minPrice > bestSell.minPrice) then
					bestSell = {
						dow = dow,
						hour = hour,
						avgPrice = cell.avgPrice,
						minPrice = cell.minPrice,
						pctVsAvg = cell.pctVsAvg,
					}
				end
			end
		end
	end

	local daily = {}
	for dow = 1, 7 do
		local da = dailyAcc[dow]
		if da then
			daily[dow] = {
				avgPrice = math.floor((da.sumP / da.w) + 0.5),
				minPrice = da.minP,
				avgQty = math.floor((da.sumQ / da.w) + 0.5),
				samples = da.samples,
			}
		end
	end

	local hourly = {}
	for hour = 0, 23 do
		local ha = hourlyAcc[hour]
		if ha then
			hourly[hour] = {
				avgPrice = math.floor((ha.sumP / ha.w) + 0.5),
				minPrice = ha.minP,
				avgQty = math.floor((ha.sumQ / ha.w) + 0.5),
				samples = ha.samples,
			}
		end
	end

	local baseUpdatedAt = (meta and meta.updatedAt) or 0
	local res = {
		itemID = id,
		economy = resolvedKey,
		updatedAt = (liveUpdatedAt and liveUpdatedAt > baseUpdatedAt) and liveUpdatedAt or baseUpdatedAt,
		source = (meta and meta.source ~= "" and meta.source) or "snapshot",
		windowDays = (meta and meta.windowDays) or 30,
		cells = cells,
		daily = daily,
		hourly = hourly,
		overall = {
			avgPrice = overallAvg,
			medianPrice = medianPrice,
			minPrice = overallMin,
			maxPrice = overallMax,
			avgQty = overallQty,
			totalSamples = totalSamples,
			cvPct = cvPct,
		},
		bestBuy = bestBuy,
		bestSell = bestSell,
	}
	if liveUpdatedAt and liveUpdatedAt > 0 then
		res.hasLiveOverlay = true
		res.liveUpdatedAt = liveUpdatedAt
	end
	return res
end

function ns.Pricing.GetItemHeatmap(itemID, econOverride)
	if not readable(itemID) then return nil end
	local id = tonumber(itemID)
	if not id or id <= 0 then return nil end
	local econKey = resolveSnapshotEconomyKey(econOverride)
	if not econKey then return nil end
	local raw, resolvedKey = findSnapshotRaw(econKey)
	if not raw then return nil end

	local econCache = ns.snapshotHeatmapCache[resolvedKey]
	local base = nil
	if econCache then
		local hit = econCache[id]
		if hit ~= nil then
			base = hit ~= false and hit or nil
			if not base then return nil end
		end
	else
		econCache = {}
		ns.snapshotHeatmapCache[resolvedKey] = econCache
	end

	if not base then
		local idx = ensureHeat7x24Index(raw)
		local payload = idx[id]
		if not payload or payload == "" then
			econCache[id] = false
			return nil
		end

		local cells = { {}, {}, {}, {}, {}, {}, {} }
		for seg in string.gmatch(payload, "([^|]+)") do
			local slotStr, avgS, minS, qtyS, nS = string.match(seg, "^%s*(%d+)=([^,]*),([^,]*),([^,]*),([^,%s]*)")
			local slot = slotStr and tonumber(slotStr)
			if slot and slot >= 0 and slot <= 167 then
				local avgP = decodeBase32(avgS)
				if avgP > 0 then
					local minP = (minS ~= "" and decodeBase32(minS)) or avgP
					if minP <= 0 then minP = avgP end
					local avgQ = decodeBase32(qtyS)
					local samples = decodeBase32(nS)
					local dow = math.floor(slot / 24) + 1
					local hour = slot % 24
					cells[dow][hour] = {
						avgPrice = avgP,
						minPrice = minP,
						avgQty = avgQ,
						samples = samples,
						pctVsAvg = 0,
					}
				end
			end
		end

		base = finalizeHeatmapGrid(cells, raw.meta, id, resolvedKey, nil)
		if not base then
			econCache[id] = false
			return nil
		end
		econCache[id] = base
	end

	local overlay, maxTs = collectLiveScanOverlay(id, resolvedKey, base.updatedAt or 0)
	if not overlay then
		return base
	end

	-- Non-destructive shallow copy of cells (copying every cell so pctVsAvg recalc never mutates cached base)
	local cellsCopy = { {}, {}, {}, {}, {}, {}, {} }
	for dow = 1, 7 do
		local srcRow = base.cells[dow]
		local dstRow = cellsCopy[dow]
		for hour = 0, 23 do
			local c = srcRow[hour]
			if c then
				dstRow[hour] = {
					avgPrice = c.avgPrice,
					minPrice = c.minPrice,
					avgQty = c.avgQty,
					samples = c.samples,
					pctVsAvg = c.pctVsAvg,
				}
			end
		end
	end

	for _, obs in pairs(overlay.bySlot) do
		local dstRow = cellsCopy[obs.dow]
		local cur = dstRow[obs.hour]
		if cur then
			local oldW = (cur.samples and cur.samples > 0) and cur.samples or 1
			local newW = oldW + obs.n
			cur.avgPrice = math.floor((cur.avgPrice * oldW + obs.sumP) / newW + 0.5)
			cur.minPrice = math.min(cur.minPrice or cur.avgPrice, obs.minP)
			cur.avgQty = math.floor(((cur.avgQty or 0) * oldW + obs.sumQ) / newW + 0.5)
			cur.samples = (cur.samples or 0) + obs.n
			cur.liveOverlay = true
		else
			dstRow[obs.hour] = {
				avgPrice = math.floor((obs.sumP / obs.n) + 0.5),
				minPrice = obs.minP,
				avgQty = math.floor((obs.sumQ / obs.n) + 0.5),
				samples = obs.n,
				pctVsAvg = 0,
				liveOverlay = true,
			}
		end
	end

	return finalizeHeatmapGrid(cellsCopy, raw.meta, id, resolvedKey, maxTs)
end

local cachedDetectEcon = nil
local cachedDetectFnRefs = nil

function ns.InvalidateEconomyDetectCache()
	cachedDetectEcon = nil
	cachedDetectFnRefs = nil
end

function ns.DetectActiveEconomy()
	local ec = ns._evalCache
	if ec and ec.activeEcon then
		local ae = ec.activeEcon
		return ae[1], ae[2], ae[3], ae[4]
	end
	local ruleFn = C_GameRules and C_GameRules.IsGameRuleActive or nil
	if cachedDetectEcon and cachedDetectFnRefs
		and cachedDetectFnRefs[1] == UnitFactionGroup
		and cachedDetectFnRefs[2] == ruleFn
		and cachedDetectFnRefs[3] == GetRealmName
		and cachedDetectFnRefs[4] == GetCVar then
		if ec then ec.activeEcon = cachedDetectEcon end
		return cachedDetectEcon[1], cachedDetectEcon[2], cachedDetectEcon[3], cachedDetectEcon[4]
	end
	local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Horde"
	if faction ~= "Alliance" and faction ~= "Horde" then faction = "Horde" end
	local ruleset = nil
	local isHC = false
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule then
		local okHC, hc = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.HardcoreRuleset)
		local okRP, rp = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.RPRuleset)
		local okPvP, pvp = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.PvPRuleset)
		if okHC and hc then
			ruleset = "Hardcore"
			isHC = true
		elseif (okRP and rp) and (okPvP and pvp) then
			ruleset = "Roleplay PvP"
		elseif okRP and rp then
			ruleset = "Roleplay"
		elseif okPvP and pvp then
			ruleset = "PvP"
		else
			ruleset = "Normal"
		end
	end
	local econKey
	if ruleset then
		econKey = ruleset .. "-" .. faction
	else
		local realm = (GetRealmName and GetRealmName()) or "Normal"
		if realm:find("%-Horde$") or realm:find("%-Alliance$") then
			econKey = realm
		else
			econKey = realm .. "-" .. faction
		end
	end
	local portal = (GetCVar and GetCVar("Portal")) or ""
	if portal == "" and GetCurrentRegionName then
		local okR, regName = pcall(GetCurrentRegionName)
		if okR and type(regName) == "string" and regName ~= "" then portal = regName end
	end
	if portal == "" then portal = "EU" end
	if portal == "public-test" then portal = "PTR" end
	portal = portal:upper()
	local regionKey = isHC and ("Forever-HC-" .. portal) or ("Forever-" .. portal)
	local res = { econKey, regionKey, isHC, portal }
	if ec then
		ec.activeEcon = res
	end
	cachedDetectEcon = res
	cachedDetectFnRefs = { UnitFactionGroup, ruleFn, GetRealmName, GetCVar }
	return econKey, regionKey, isHC, portal
end

function ns.NormalizeEconomyKey(key)
	if type(key) ~= "string" or key == "" or key == "tsm_alt" or key == "region" then
		return "auto"
	end
	if ns.ECONOMY_BY_KEY and ns.ECONOMY_BY_KEY[key] then
		return key
	end
	return "auto"
end

function ns.CurrentEconomyInfo()
	local ec = ns._evalCache
	local db = ns.GetDB()
	local dbRawKey = db and db.economy
	local rawSelKey = ns.NormalizeEconomyKey(dbRawKey or "auto")
	if db and (dbRawKey == "tsm_alt" or dbRawKey == "region") then
		db.economy = "auto"
	end
	if ec and ec.econInfo and ec.econInfo._rawSelKey == rawSelKey then
		return ec.econInfo
	end
	local selKey = rawSelKey
	local activeEcon, activeRegion, activeHC, portal = ns.DetectActiveEconomy()
	local found, idx = ns.ECONOMIES[1], 1
	for i, e in ipairs(ns.ECONOMIES) do
		if e.key == selKey then
			found, idx = e, i
			break
		end
	end
	selKey = found.key

	local info
	if selKey == "auto" then
		info = {
			_rawSelKey = rawSelKey,
			selectedKey = "auto",
			effectiveKey = activeEcon,
			regionKey = activeRegion,
			isHC = activeHC,
			isActive = true,
			isRegionOnly = false,
			label = activeEcon,
			buttonLabel = "Auto (" .. activeEcon .. ")",
			index = idx,
		}
	else
		local isHC = found.hc and true or false
		local regKey = isHC and ("Forever-HC-" .. portal) or ("Forever-" .. portal)
		info = {
			_rawSelKey = rawSelKey,
			selectedKey = selKey,
			effectiveKey = selKey,
			regionKey = regKey,
			isHC = isHC,
			isActive = (selKey:lower() == activeEcon:lower()),
			isRegionOnly = false,
			label = found.label,
			buttonLabel = found.label,
			index = idx,
		}
	end
	if ec then
		ec.econInfo = info
	end
	return info
end

function ns.QueryLiveAH(itemID, econOverride)
	local db = ns.GetDB()
	local ahTable = nil
	if econOverride and db and db.ahPrices and db.ahPrices[econOverride] then
		ahTable = db.ahPrices[econOverride]
	elseif not econOverride then
		local econ = ns.CurrentEconomyInfo()
		if db and db.ahPrices and db.ahPrices[econ.effectiveKey] then
			ahTable = db.ahPrices[econ.effectiveKey]
		elseif econ.isActive then
			ahTable = ns.ahPrices
		end
	end
	local rec = ahTable and ahTable[itemID]
	if not rec then return nil, nil end
	if rec.absent then return nil, rec end
	if type(rec.price) == "number" and rec.price > 0 then
		return rec.price, rec
	end
	return nil, rec
end

local function extractTimestamps(liveRec, snapRec)
	local liveAt = (liveRec and type(liveRec.at) == "number" and liveRec.at > 0) and liveRec.at or 0
	local liveIsRecent = (liveAt > 0 and (time() - liveAt) <= RECENT_LIVE_AH_SECONDS)
	local snapAt = (snapRec and type(snapRec.updatedAt) == "number" and snapRec.updatedAt > 0) and snapRec.updatedAt or 0
	return liveAt, liveIsRecent, snapAt
end

local function resolveMarketFallbackChain(itemID, econ, liveVal, liveRec, snapVal, snapRec)
	local econKey = econ and econ.effectiveKey
	if snapVal == nil and snapRec == nil and econKey then
		snapVal, snapRec = ns.QueryLocalSnapshot(itemID, econKey)
	end
	local liveAt, liveIsRecent, snapAt = extractTimestamps(liveRec, snapRec)
	if snapVal and (not liveVal or snapAt > liveAt) then
		return snapVal, "Snapshot", snapRec and snapRec.qty
	end
	if liveVal then
		return liveVal, (liveIsRecent and "Live AH" or "Saved AH Scan"), liveRec and liveRec.qty
	end
	return nil, nil, nil
end

-- Returns unitPrice (copper or nil), sourceLabel, stockCount (or nil)
local function computeItemMarketPrice(itemID)
	local mode = ns.GetEffectivePriceSource()
	local econ = ns.CurrentEconomyInfo()

	-- 1. Cross-economy mode (e.g. viewing Normal-Alliance or PvP-Horde while logged onto Normal-Horde)
	if not econ.isActive then
		local liveVal, liveRec = ns.QueryLiveAH(itemID, econ.effectiveKey)
		if mode == "live_ah" then
			return liveVal, liveVal and ("Live AH (" .. econ.label .. ")") or (liveRec and liveRec.absent and "Not listed (Live AH)" or nil), liveRec and liveRec.qty
		elseif mode == "snapshot" then
			local sv, srec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
			return sv, sv and ("Snapshot (" .. econ.label .. ")") or nil, srec and srec.qty
		end
		local snapVal, snapRec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
		local liveAt, liveIsRecent, snapAt = extractTimestamps(liveRec, snapRec)
		local snapLabel = "Snapshot (" .. econ.label .. ")"
		local liveLabel = "Live AH (" .. econ.label .. ")"
		local savedLabel = "Saved AH (" .. econ.label .. ")"
		if liveIsRecent and liveRec and liveRec.absent then
			if snapVal and snapAt > liveAt then
				return snapVal, snapLabel, snapRec and snapRec.qty
			end
			return nil, "Not listed (" .. econ.label .. ")", 0
		end
		if snapVal and (not liveVal or snapAt > liveAt) then
			return snapVal, snapLabel, snapRec and snapRec.qty
		end
		if liveVal then
			return liveVal, (liveIsRecent and liveLabel or savedLabel), liveRec and liveRec.qty
		end
		return nil, nil, nil
	end

	-- 2. Active character economy
	if mode == "snapshot" then
		local sv, srec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
		return sv, sv and "Snapshot" or nil, srec and srec.qty
	elseif mode == "live_ah" then
		local v, rec = ns.QueryLiveAH(itemID, econ.effectiveKey)
		return v, v and "Live AH" or (rec and rec.absent and "Not listed (Live AH)" or nil), rec and rec.qty
	end

	-- Auto (Best): Most recent wins between Manual Live AH and Blizzard Local Snapshot
	local liveVal, liveRec = ns.QueryLiveAH(itemID, econ.effectiveKey)
	local snapVal, snapRec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
	local liveAt, liveIsRecent, snapAt = extractTimestamps(liveRec, snapRec)
	if liveIsRecent and liveRec and liveRec.absent then
		if snapVal and snapAt > liveAt then
			return snapVal, "Snapshot", snapRec and snapRec.qty
		end
		return nil, "Not listed (Live AH)", 0
	end
	return resolveMarketFallbackChain(itemID, econ, liveVal, liveRec, snapVal, snapRec)
end

function ns.GetItemMarketPrice(itemID)
	if not itemID or itemID <= 0 then return nil, nil, nil end
	local ec = ns._evalCache
	if ec then
		local hit = ec.mktPrice[itemID]
		if hit then
			return hit[1] ~= false and hit[1] or nil,
				hit[2] ~= false and hit[2] or nil,
				hit[3] ~= false and hit[3] or nil
		end
	end
	local p, src, stk = computeItemMarketPrice(itemID)
	if ec then
		ec.mktPrice[itemID] = { p ~= nil and p or false, src ~= nil and src or false, stk ~= nil and stk or false }
	end
	return p, src, stk
end

-- Fallback price lookup skipping fresh Live AH 'absent' short-circuit (for leveling solver stability)
function ns.GetFallbackMarketPrice(itemID)
	if not itemID or itemID <= 0 then return nil, nil end
	local econ = ns.CurrentEconomyInfo()
	if not econ.isActive then
		local liveVal, liveRec = ns.QueryLiveAH(itemID, econ.effectiveKey)
		local snapVal, snapRec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
		local liveAt, liveIsRecent, snapAt = extractTimestamps(liveRec, snapRec)
		local snapLabel = "Snapshot (" .. econ.label .. ")"
		local liveLabel = "Live AH (" .. econ.label .. ")"
		local savedLabel = "Saved AH (" .. econ.label .. ")"
		if snapVal and (not liveVal or snapAt > liveAt) then
			return snapVal, snapLabel
		end
		if liveVal then
			return liveVal, (liveIsRecent and liveLabel or savedLabel)
		end
		if liveRec and type(liveRec.lastPrice) == "number" and liveRec.lastPrice > 0 then
			return math.floor(liveRec.lastPrice + 0.5), "Last Seen AH"
		end
		return nil, nil
	end
	local liveVal, liveRec = ns.QueryLiveAH(itemID, econ.effectiveKey)
	local snapVal, snapRec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
	local p, src = resolveMarketFallbackChain(itemID, econ, liveVal, liveRec, snapVal, snapRec)
	if p then return p, src end
	if liveRec and type(liveRec.lastPrice) == "number" and liveRec.lastPrice > 0 then
		return math.floor(liveRec.lastPrice + 0.5), "Last Seen AH"
	end
	return nil, nil
end

local function computeLastKnownAHPrice(itemID)
	local db = ns.GetDB()
	local econ = ns.CurrentEconomyInfo()

	local liveVal, liveLbl, liveAt = nil, nil, 0
	if db and db.ahPrices and econ and econ.effectiveKey then
		local pool = db.ahPrices[econ.effectiveKey]
		local rec = type(pool) == "table" and pool[itemID] or db.ahPrices[itemID]
		if type(rec) == "table" then
			liveAt = (type(rec.at) == "number" and rec.at > 0) and rec.at or 0
			if type(rec.price) == "number" and rec.price > 0 then
				liveVal = math.floor(rec.price + 0.5)
				liveLbl = "Live AH Scan"
			elseif type(rec.lastPrice) == "number" and rec.lastPrice > 0 then
				liveVal = math.floor(rec.lastPrice + 0.5)
				liveLbl = "Last Seen AH"
			end
		end
	end

	local snapVal, snapLbl, snapAt = nil, nil, 0
	if econ and econ.effectiveKey then
		local sv, srec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
		if not sv and srec and srec.historical and srec.historical > 0 then
			sv = srec.historical
		end
		if sv and sv > 0 then
			snapVal = math.floor(sv + 0.5)
			snapLbl = econ.isActive and "Snapshot" or ("Snapshot (" .. econ.label .. ")")
			snapAt = (srec and type(srec.updatedAt) == "number" and srec.updatedAt > 0) and srec.updatedAt or 0
		end
	end

	if liveVal and snapVal then
		if snapAt > liveAt then
			return snapVal, snapLbl
		end
		return liveVal, liveLbl
	elseif liveVal then
		return liveVal, liveLbl
	elseif snapVal then
		return snapVal, snapLbl
	end
	return nil, nil
end

function ns.GetLastKnownAHPrice(itemID)
	if not itemID or itemID <= 0 then return nil, nil end
	local ec = ns._evalCache
	if ec and ec.lastKnownAH then
		local hit = ec.lastKnownAH[itemID]
		if hit then
			return hit[1] ~= false and hit[1] or nil, hit[2] ~= false and hit[2] or nil
		end
	end
	local p, src = computeLastKnownAHPrice(itemID)
	if ec and ec.lastKnownAH then
		ec.lastKnownAH[itemID] = { p ~= nil and p or false, src ~= nil and src or false }
	end
	return p, src
end

function ns.ResolveOutputSaleValuation(itemID, listed, sellable, craftCost, applyAHCut, outlierPrices)
	if not sellable or not itemID or itemID <= 0 then
		return {
			isUnlisted = false,
			unitAH = nil,
			ahValue = nil,
			ahSource = nil,
			profit = nil,
			marginPct = nil,
			lastKnownPrice = nil,
			lastKnownSource = nil,
			vendorSell = 0,
			isCustomPrice = false,
			usedVendorFloor = false,
		}
	end
	local lastKnownPrice, lastKnownSource = ns.GetLastKnownAHPrice(itemID)
	local vendorSell = ns.GetVendorSellPrice(itemID) or 0
	local rawAH, rawSrc = ns.GetItemMarketPrice(itemID)
	local isUnlisted = (listed == 0) or (rawAH == nil and listed == nil)
	local db = ns.GetDB()
	local ovMap = outlierPrices or (db and db.outlierPrices) or nil
	local customPrice = ovMap and tonumber(ovMap[itemID]) or nil
	if customPrice and customPrice <= 0 then customPrice = nil end

	local unitAH, ahValue, ahSource = nil, nil, nil
	local profit, marginPct = nil, nil
	local isCustomPrice, usedVendorFloor = false, false

	if isUnlisted then
		if customPrice then
			unitAH = customPrice
			ahValue = customPrice
			ahSource = "Custom Price"
			isCustomPrice = true
			if craftCost ~= nil then
				local netSale = applyAHCut and math.floor(customPrice * 0.95 + 0.5) or customPrice
				profit = netSale - craftCost
				if craftCost > 0 then marginPct = (profit / craftCost) * 100 end
			end
		end
	elseif rawAH and rawAH > 0 then
		unitAH = rawAH
		local netSale = applyAHCut and math.floor(rawAH * 0.95 + 0.5) or rawAH
		if vendorSell > 0 and netSale < vendorSell then
			ahValue = vendorSell
			ahSource = "Vendor"
			usedVendorFloor = true
			if craftCost ~= nil then
				profit = vendorSell - craftCost
				if craftCost > 0 then marginPct = (profit / craftCost) * 100 end
			end
		else
			ahValue = rawAH
			ahSource = rawSrc
			if craftCost ~= nil then
				profit = netSale - craftCost
				if craftCost > 0 then marginPct = (profit / craftCost) * 100 end
			end
		end
	end

	return {
		isUnlisted = isUnlisted,
		unitAH = unitAH,
		ahValue = ahValue,
		ahSource = ahSource,
		profit = profit,
		marginPct = marginPct,
		lastKnownPrice = lastKnownPrice,
		lastKnownSource = lastKnownSource,
		vendorSell = vendorSell,
		isCustomPrice = isCustomPrice,
		usedVendorFloor = usedVendorFloor,
	}
end

local function currentVendorCharKey()
	if ns.app and type(ns.app.charKey) == "string" and ns.app.charKey ~= "" then
		return ns.app.charKey
	end
	if ns.activeCharKey and type(ns.activeCharKey) == "string" and ns.activeCharKey ~= "" then
		return ns.activeCharKey
	end
	local rawFirst = UnitName and UnitName("player")
	if readable(rawFirst) and type(rawFirst) == "string" and rawFirst ~= "" then
		local name = (ns.GetPlayerFullName and ns.GetPlayerFullName()) or rawFirst
		local realm = GetRealmName and GetRealmName()
		return name .. "-" .. ((readable(realm) and type(realm) == "string" and realm ~= "") and realm or "Forever")
	end
	return nil
end

local BARTERING_TREE_ID = 1187
local BARTERING_SPELL_ID = 1225459

-- Single-owner reader for WoW: Forever Legacy Profession trait Bartering (spell 1225459, 0..2 ranks).
function ns.GetBarteringRank()
	if cachedBarteringRank ~= nil then
		return cachedBarteringRank
	end
	local rank = 0
	if C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo then
		local okCfg, configID = pcall(C_Traits.GetConfigIDByTreeID, BARTERING_TREE_ID)
		if okCfg and readable(configID) and type(configID) == "number" and configID > 0 then
			local okNodes, nodes = pcall(C_Traits.GetTreeNodes, BARTERING_TREE_ID)
			if okNodes and readable(nodes) and type(nodes) == "table" then
				local found = false
				for _, nodeID in ipairs(nodes) do
					local okN, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
					if okN and readable(node) and type(node) == "table" and type(node.entryIDs) == "table" then
						for _, entryID in ipairs(node.entryIDs) do
							local okE, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
							local defID = okE and readable(entry) and type(entry) == "table" and entry.definitionID
							if defID and C_Traits.GetDefinitionInfo then
								local okD, def = pcall(C_Traits.GetDefinitionInfo, defID)
								local sid = okD and readable(def) and type(def) == "table" and (def.spellID or def.overriddenSpellID)
								if sid == BARTERING_SPELL_ID then
									local r = tonumber(node.activeRank) or tonumber(node.ranksPurchased) or tonumber(node.currentRank) or 0
									rank = math.max(0, math.min(2, math.floor(r)))
									found = true
									break
								end
							end
						end
					end
					if found then break end
				end
				if found then
					cachedBarteringRank = rank
					return rank
				end
			end
		end
	end
	return rank
end

local function readSavedVendorBuyEntry(entry, allowLimited, isKnownVendorReagent, expectedBartering, expectedRepDisc)
	if type(entry) == "number" then
		if entry > 0 and (expectedBartering == nil or expectedBartering == 0)
			and (expectedRepDisc == nil or expectedRepDisc == false) then
			return math.floor(entry + 0.5)
		end
		return nil
	end
	if type(entry) == "table" and type(entry.price) == "number" and entry.price > 0 then
		if entry.limited and not allowLimited and not isKnownVendorReagent then
			return nil
		end
		if expectedBartering ~= nil then
			local entryBarter = (type(entry.bartering) == "number") and entry.bartering or 0
			if entryBarter ~= expectedBartering then
				return nil
			end
		end
		if expectedRepDisc ~= nil then
			if (entry.repDisc == true) ~= expectedRepDisc then
				return nil
			end
		end
		return math.floor(entry.price + 0.5)
	end
	return nil
end

local function readGlobalVendorBuyEntry(entry, allowLimited, isKnownVendorReagent, combinedMult, effBarter, expectedRepDisc)
	if type(entry) == "table" then
		if entry.limited and not allowLimited and not isKnownVendorReagent then
			return nil
		end
		if type(entry.basePrice) == "number" and entry.basePrice > 0 then
			return math.max(1, math.floor(entry.basePrice * combinedMult + 0.5))
		end
		if type(entry.price) == "number" and entry.price > 0 and effBarter == 0 and expectedRepDisc ~= true then
			return math.floor(entry.price + 0.5)
		end
		return nil
	end
	if type(entry) == "number" and entry > 0 and effBarter == 0 and expectedRepDisc ~= true then
		return math.floor(entry + 0.5)
	end
	return nil
end

-- Captures live WoW: Forever NPC merchant buy prices whenever a vendor window opens/updates.
-- Skips currency/extended-cost items (e.g. Merchant's Favor tokens) and tags limited-stock items
-- so rare limited-stock goods never spoof infinite reagent supply.
function ns.CaptureMerchantVendorPrices()
	if not GetMerchantNumItems then return 0 end
	local count = GetMerchantNumItems()
	if not readable(count) or type(count) ~= "number" or count <= 0 then return 0 end
	local db = ns.GetDB and ns.GetDB()
	if not db then return 0 end
	local charKey = currentVendorCharKey()
	db.liveVendorBuy = db.liveVendorBuy or {}
	db.liveVendorBuyGlobal = db.liveVendorBuyGlobal or {}
	local charMap = charKey and (db.liveVendorBuy[charKey] or {}) or nil
	if charKey then db.liveVendorBuy[charKey] = charMap end

	local barteringRank = ns.GetBarteringRank()
	local npcReaction = UnitReaction and UnitReaction("npc", "player")
	local repDisc = (readable(npcReaction) and type(npcReaction) == "number" and npcReaction >= 6) and true or false
	local combinedMult = (1 - 0.05 * barteringRank) * (repDisc and 0.90 or 1.0)

	local merchantAPI = _G.C_MerchantFrame
	local infoFn = merchantAPI and (merchantAPI.GetItemInfo or merchantAPI.GetMerchantItemInfo)
	local captured, changed = 0, false

	for slot = 1, count do
		local info = infoFn and infoFn(slot)
		local price, stack, numAvail, extended, itemID
		if readable(info) and type(info) == "table" then
			price = info.price or info.buyPrice
			stack = info.stackCount or info.quantity or info.stackSize
			numAvail = info.numAvailable
			extended = info.hasExtendedCost
			itemID = info.itemID
		end
		if _G.GetMerchantItemInfo and (price == nil or stack == nil or numAvail == nil or extended == nil) then
			local _, _, p, s, na, _, _, e = _G.GetMerchantItemInfo(slot)
			if price == nil then price = p end
			if stack == nil then stack = s end
			if numAvail == nil then numAvail = na end
			if extended == nil then extended = e end
		end
		if not (readable(itemID) and type(itemID) == "number" and itemID > 0) then
			local link = _G.GetMerchantItemLink and _G.GetMerchantItemLink(slot)
			if readable(link) and type(link) == "string" then
				itemID = tonumber(link:match("item:(%d+)"))
			end
		end
		if readable(itemID) and readable(price) and readable(stack) and readable(numAvail) and readable(extended)
			and type(itemID) == "number" and itemID > 0
			and not extended
			and type(price) == "number" and price > 0 then
			local st = (type(stack) == "number" and stack > 0) and stack or 1
			local unitCopper = math.max(1, math.floor((price / st) + 0.5))
			local limited = (type(numAvail) == "number" and numAvail >= 0) or false
			local prevChar = charMap and charMap[itemID]
			if charMap then
				if type(prevChar) ~= "table" or prevChar.price ~= unitCopper
					or (prevChar.limited == true) ~= limited
					or prevChar.bartering ~= barteringRank
					or (prevChar.repDisc == true) ~= repDisc then
					charMap[itemID] = { price = unitCopper, limited = limited, bartering = barteringRank, repDisc = repDisc }
					changed = true
				end
			end
			if not limited then
				local basePrice = (combinedMult > 0) and math.max(1, math.floor((unitCopper / combinedMult) + 0.5)) or unitCopper
				local prevGlob = db.liveVendorBuyGlobal[itemID]
				if type(prevGlob) ~= "table" or prevGlob.basePrice ~= basePrice or prevGlob.limited == true then
					db.liveVendorBuyGlobal[itemID] = { basePrice = basePrice, limited = false }
					changed = true
				end
			end
			captured = captured + 1
		end
	end

	if changed and ns.InvalidatePriceCache then
		ns.InvalidatePriceCache()
	end
	return captured
end

-- Returns unitCopper (or nil), isLiveObserved (boolean: true when already observed on live WoW: Forever vendor).
-- Optional barteringRankOverride: number (0..2) for simulation, false for undiscounted base, nil for live rank.
-- Optional honoredDiscountOverride: boolean (true=Honored 10% rep discount, false=none), nil for existing behavior.
function ns.GetVendorBuyPrice(itemID, staticCopper, allowLimited, barteringRankOverride, honoredDiscountOverride)
	local effBarter
	if barteringRankOverride == false then
		effBarter = 0
	elseif type(barteringRankOverride) == "number" then
		effBarter = math.max(0, math.min(2, math.floor(barteringRankOverride)))
	else
		effBarter = ns.GetBarteringRank()
	end
	local barterMult = 1 - 0.05 * effBarter
	local expectedRepDisc = nil
	local repMult = 1.0
	if honoredDiscountOverride ~= nil then
		expectedRepDisc = (honoredDiscountOverride == true)
		repMult = expectedRepDisc and 0.90 or 1.0
	end
	local combinedMult = barterMult * repMult

	if not itemID or itemID <= 0 then
		if type(staticCopper) == "number" and staticCopper > 0 then
			return math.max(1, math.floor(staticCopper * combinedMult + 0.5)), false
		end
		return nil, false
	end
	local isKnownVendorReagent = (ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[itemID] ~= nil) or false
	local db = ns.GetDB and ns.GetDB()
	if db then
		local charKey = currentVendorCharKey()
		local charEntry = charKey and db.liveVendorBuy and db.liveVendorBuy[charKey] and db.liveVendorBuy[charKey][itemID]
		local charPrice = readSavedVendorBuyEntry(charEntry, allowLimited == true, isKnownVendorReagent, effBarter, expectedRepDisc)
		if charPrice then
			return charPrice, true
		end
		local globEntry = db.liveVendorBuyGlobal and db.liveVendorBuyGlobal[itemID]
		local globPrice = readGlobalVendorBuyEntry(globEntry, allowLimited == true, isKnownVendorReagent, combinedMult, effBarter, expectedRepDisc)
		if globPrice then
			return globPrice, true
		end
	end
	local fallback = staticCopper
	if fallback == nil and ns.VENDOR_REAGENTS then
		fallback = ns.VENDOR_REAGENTS[itemID]
	end
	if type(fallback) == "number" and fallback > 0 then
		return math.max(1, math.floor(fallback * combinedMult + 0.5)), false
	end
	return nil, false
end

---------------------------------------------------------------------------------------------------
-- Tooltip Craft Cost (Disenchant rules & EV live in Disenchant.lua)

-- Tooltip helper delegating to Calculators.lua (ns.GetItemCraftOption) with persistent epoch-cleared memo.
function ns.GetTooltipCraftCost(itemID)
	if not itemID or itemID <= 0 then return nil end
	local hit = tooltipCraftMemo[itemID]
	if hit ~= nil then
		return hit ~= false and hit or nil
	end
	if not (ns.RECIPES_BY_OUTPUT and ns.RECIPES_BY_OUTPUT[itemID] and ns.GetItemCraftOption) then
		tooltipCraftMemo[itemID] = false
		return nil
	end
	local opt = ns.GetItemCraftOption(itemID, 0)
	local unit = (opt and type(opt.unitCost) == "number" and opt.unitCost > 0) and math.floor(opt.unitCost + 0.5) or nil
	tooltipCraftMemo[itemID] = unit or false
	return unit
end

-- Returns unitCost (copper or nil), sourceLabel, isVendor (bool)
function ns.GetReagentUnitCost(itemID)
	if not itemID or itemID <= 0 then return nil, nil, false end
	local ec = ns._evalCache
	if ec then
		local hit = ec.reagentCost[itemID]
		if hit then
			return hit[1] ~= false and hit[1] or nil,
				hit[2] ~= false and hit[2] or nil,
				hit[3]
		end
	end
	local vendorPrice = ns.GetVendorBuyPrice(itemID, ns.VENDOR_REAGENTS and ns.VENDOR_REAGENTS[itemID], false)
	local ahPrice, ahSource = ns.GetItemMarketPrice(itemID)
	local uCost, uSrc, isVend
	if vendorPrice and ahPrice then
		if vendorPrice <= ahPrice then
			uCost, uSrc, isVend = vendorPrice, "Vendor", true
		else
			uCost, uSrc, isVend = ahPrice, ahSource, false
		end
	elseif vendorPrice then
		uCost, uSrc, isVend = vendorPrice, "Vendor", true
	else
		uCost, uSrc, isVend = ahPrice, ahSource, false
	end
	if ec then
		ec.reagentCost[itemID] = { uCost ~= nil and uCost or false, uSrc ~= nil and uSrc or false, isVend }
	end
	return uCost, uSrc, isVend
end

local function extractSnapListed(snapRec)
	if not snapRec or (snapRec.qty == nil and snapRec.numAuctions == nil) then return nil end
	if snapRec.qty and snapRec.qty > 0 then
		return snapRec.qty
	elseif snapRec.numAuctions and snapRec.numAuctions > 0 then
		return snapRec.numAuctions
	elseif snapRec.qty ~= nil then
		return snapRec.qty
	end
	return nil
end

-- Number of listings / units on the Auction House (most recent wins between Live AH and Local Snapshot)
local function computeNumListed(itemID)
	local econ = ns.CurrentEconomyInfo()
	local _, liveRec = ns.QueryLiveAH(itemID, econ.effectiveKey)
	local _, snapRec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
	local snapNum = extractSnapListed(snapRec)
	local liveAt, liveIsRecent, snapAt = extractTimestamps(liveRec, snapRec)
	local liveQty = (liveRec and not liveRec.absent and liveRec.qty ~= nil) and liveRec.qty or nil

	if liveIsRecent and liveRec and liveRec.absent then
		if snapNum ~= nil and snapAt > liveAt then
			return snapNum
		end
		return 0
	end

	if snapNum ~= nil and (liveQty == nil or snapAt > liveAt) then
		return snapNum
	end
	if liveQty ~= nil then
		return liveQty
	end
	if liveRec and liveRec.absent then
		return 0
	end
	return nil
end

function ns.GetNumListed(itemID)
	if not itemID or itemID <= 0 then return nil end
	local ec = ns._evalCache
	if ec then
		local hit = ec.numListed[itemID]
		if hit ~= nil then
			return hit ~= false and hit or nil
		end
	end
	local val = computeNumListed(itemID)
	if ec then
		ec.numListed[itemID] = (val ~= nil) and val or false
	end
	return val
end

-- Daily sales rate from Blizzard Local Snapshot hourly velocity (obsHours >= 3),
-- falling back cleanly to Live AH MarketScan.GetLocalVelocity (>= 2 scan pairs, >= 15m span).
local function computeDailySold(itemID, economy)
	local econ = economy or ns.CurrentEconomyInfo()
	local econKey = type(econ) == "table" and econ.effectiveKey or (type(econ) == "string" and econ or nil)
	if not econKey or econKey == "" then return nil end
	local snapVel = getItemSnapshotVelocityRaw(itemID, econKey)
	local snapEst = nil
	if snapVel and type(snapVel.obsHours) == "number" and snapVel.obsHours >= 3 then
		snapEst = demandNumber(snapVel.estDailySold)
		if snapEst and snapEst > 0 then
			return snapEst
		end
	end
	local ms = ns.MarketScan
	if ms and type(ms.GetLocalVelocity) == "function" then
		local ok, vel = pcall(ms.GetLocalVelocity, itemID, econKey)
		if ok and readable(vel) and type(vel) == "table" then
			local pairsCount = tonumber(vel.scanPairs) or 0
			local localEst = demandNumber(vel.clearsPerDay)
			if pairsCount >= 2 and localEst ~= nil then
				if localEst > 0 or snapEst == nil then
					return localEst
				end
			end
		end
	end
	return snapEst
end

function ns.GetDailySold(itemID)
	if not itemID or itemID <= 0 then return nil end
	local ec = ns._evalCache
	if ec then
		local hit = ec.dailySold[itemID]
		if hit ~= nil then
			return hit ~= false and hit or nil
		end
	end
	local val = computeDailySold(itemID)
	if ec then
		ec.dailySold[itemID] = (val ~= nil) and val or false
	end
	return val
end

-- Single-realm daily sales rate from Blizzard Local Snapshot hourly velocity (share = 1.0)
function ns.GetRealmAdjustedDailySold(itemID)
	if not itemID or itemID <= 0 then return nil, nil, 1.0 end
	local ec = ns._evalCache
	if ec and ec.realmDailySold then
		local hit = ec.realmDailySold[itemID]
		if hit then
			return hit[1] ~= false and hit[1] or nil,
				hit[2] ~= false and hit[2] or nil,
				hit[3]
		end
	end
	local est = ns.GetDailySold(itemID)
	if ec and ec.realmDailySold then
		ec.realmDailySold[itemID] = { est ~= nil and est or false, est ~= nil and est or false, 1.0 }
	end
	return est, est, 1.0
end

local function computeConservativeAnchor(itemID)
	local econ = ns.CurrentEconomyInfo()
	if not econ or not econ.effectiveKey then return nil, nil end
	local _, snapRec = ns.QueryLocalSnapshot(itemID, econ.effectiveKey)
	if snapRec then
		if type(snapRec.marketValue) == "number" and snapRec.marketValue > 0 then
			return math.floor(snapRec.marketValue + 0.5), "Snapshot Market"
		elseif type(snapRec.historical) == "number" and snapRec.historical > 0 then
			return math.floor(snapRec.historical + 0.5), "Snapshot Historical"
		end
	end
	return nil, nil
end

-- Caps spot AH buyout spikes against Local Snapshot market / historical value
function ns.GetConservativeSaleUnitPrice(itemID, rawAHUnit)
	if not itemID or itemID <= 0 or type(rawAHUnit) ~= "number" or rawAHUnit <= 0 then
		return rawAHUnit, false, nil
	end
	local spot = math.floor(rawAHUnit + 0.5)
	local ec = ns._evalCache
	local cap, capSrc = nil, nil
	local hit = ec and ec.conservativeAnchor and ec.conservativeAnchor[itemID]
	if hit then
		cap = hit[1] ~= false and hit[1] or nil
		capSrc = hit[2] ~= false and hit[2] or nil
	else
		cap, capSrc = computeConservativeAnchor(itemID)
		if ec and ec.conservativeAnchor then
			ec.conservativeAnchor[itemID] = { cap ~= nil and cap or false, capSrc ~= nil and capSrc or false }
		end
	end
	if cap and cap > 0 and cap < spot then
		return cap, true, capSrc
	end
	return spot, false, nil
end

local multiDemandCache = {epoch=-1, byEcon={}}

local itemEvalFields = {"mktPrice", "reagentCost", "lastKnownAH", "vendorSell",
	"numListed", "dailySold", "itemNames", "itemIcons",
	"conservativeAnchor", "realmDailySold", "maxStack"}

function ns.InvalidateEvalItem(bank, itemID)
	if bank then
		for _, field in ipairs(itemEvalFields) do
			local cache = bank[field]
			if cache then cache[itemID] = nil end
		end
	end
	for _, items in pairs(multiDemandCache.byEcon) do items[itemID] = nil end
end

function ns.InvalidateEvalCrafts(bank)
	-- These caches use composite or reagent-table keys, and can include nested crafts.
	if bank then bank.craftOpt, bank.smartCraft, bank.candidates = {}, {}, {} end
end
local function localScanStamp(itemID, econKey)
	local db = MerchantMasterDB
	local history = db and db.ahHistory and db.ahHistory[econKey]
	local lots = db and db.ahLotPrev and db.ahLotPrev[econKey]
	local ringRaw = history and history[itemID]
	local ring = (ns.MarketScan and ns.MarketScan.ReadHistory and ns.MarketScan.ReadHistory(ringRaw))
		or (type(ringRaw) == "table" and ringRaw or nil)
	local last = ring and ring[#ring]
	local lot = lots and lots[itemID]
	local hasLocal = (ring and #ring > 0) or (lot and type(lot.t) == "number") or false
	return last and last.t or 0, last and last.p, last and last.q,
		lot and lot.t or 0, lot and lot.p, lot and lot.q, ring, hasLocal
end

local function localScanExpiry(ring, now)
	if not ring then return nil end
	local expiry
	for _, sample in ipairs(ring) do
		local stamp = sample and sample.t
		if type(stamp) == "number" and stamp <= now and stamp >= now - 72*3600 then
			local boundary = stamp + 72*3600 + 1
			if not expiry or boundary < expiry then expiry = boundary end
		end
	end
	return expiry
end

local personal7dCache = { model = nil, version = nil, storeDB = nil, modelGen = nil, day = nil, econ = nil, byID = nil }

local function getAnalyticsLedgerStamp()
	local day = (type(time) == "function" and math.floor(time() / 86400)) or 0
	local analytics = ns.Analytics
	if not readable(analytics) or type(analytics) ~= "table" then return nil, nil, nil, nil, day end
	local model = analytics.Model
	if not readable(model) or type(model) ~= "table" then return nil, nil, nil, nil, day end
	local store = analytics.Store
	if readable(store) and type(store) == "table" and store.readOnly == true then
		return nil, nil, nil, nil, day
	end
	local ver, storeDB = 0, nil
	if readable(store) and type(store) == "table" then
		if store.ahSalesVersion ~= nil and (store._trackedAccountingVersion == nil or store.accountingVersion == store._trackedAccountingVersion) then
			ver = store.ahSalesVersion
		else
			ver = store.accountingVersion or store.version or 0
		end
		storeDB = readable(store.db) and store.db or nil
	end
	local modelGen = readable(model.generation) and model.generation or 0
	return model, ver, storeDB, modelGen, day
end

local function queryPersonalDailySold(itemID, econKey, model, ver, storeDB, modelGen, day)
	if not model then return 0, nil end
	-- O(1) cached 7d AH table when full Analytics.Model (with GetItemStats + Compute) is loaded.
	if type(model.GetItemStats) == "function" and type(model.Compute) == "function" then
		if personal7dCache.model ~= model or personal7dCache.version ~= ver
			or personal7dCache.storeDB ~= storeDB or personal7dCache.modelGen ~= modelGen
			or personal7dCache.day ~= day or personal7dCache.econ ~= econKey then
			local ok, res = pcall(model.Compute, "items", {
				char = "all", econ = econKey, period = "7d", source = "AH", knownCostOnly = false,
			})
			local byID = {}
			if ok and readable(res) and type(res) == "table" then
				if type(res.byItemID) == "table" then
					byID = res.byItemID
				elseif type(res.rows) == "table" then
					for _, r in ipairs(res.rows) do
						if readable(r) and type(r) == "table" then
							local rid = demandNumber(r.itemID)
							if rid then byID[rid] = r end
						end
					end
				end
			end
			personal7dCache = {
				model = model, version = ver, storeDB = storeDB, modelGen = modelGen,
				day = day, econ = econKey, byID = byID,
			}
		end
		local rec = personal7dCache.byID and personal7dCache.byID[itemID]
		if readable(rec) and type(rec) == "table" then
			local ahSold = demandNumber(rec.ahSold) or demandNumber(rec.sold)
			if ahSold and ahSold > 0 then
				return ahSold / 7, ver
			end
			local vel = demandNumber(rec.ahVelocity) or demandNumber(rec.velocity)
			if vel and vel > 0 then
				return vel, ver
			end
		end
		return 0, ver
	end
	-- Direct GetItemDetail fallback when only GetItemDetail is exposed/mocked.
	if type(model.GetItemDetail) == "function" then
		local ok, det = pcall(model.GetItemDetail, itemID, {
			char = "all", econ = econKey, period = "7d", source = "AH",
		})
		if ok and readable(det) and type(det) == "table" then
			local d7 = readable(det.windows) and type(det.windows) == "table" and det.windows.d7
			local ahSold = demandNumber(det.ahSold)
				or (readable(d7) and type(d7) == "table" and (demandNumber(d7.ahSold) or demandNumber(d7.sold)))
			if ahSold and ahSold > 0 then
				return ahSold / 7, ver
			end
		end
	end
	return 0, ver
end

function ns.GetMultiSourceDemand(itemID, econKey)
	if not demandNumber(itemID) or itemID <= 0 or not readable(econKey) then return nil end
	local economy
	if econKey == nil then economy = ns.CurrentEconomyInfo(); econKey = economy.effectiveKey end
	if type(econKey) ~= "string" then return nil end
	local epoch = ns.priceCacheEpoch
	if multiDemandCache.epoch ~= epoch then
		multiDemandCache = {epoch=epoch, byEcon={}}
	end
	local scanAt, scanPrice, scanQty, lotAt, lotPrice, lotQty, ring, hasLocal = localScanStamp(itemID, econKey)
	local analyticsModel, ledgerVer, ledgerDB, modelGen, ledgerDay = getAnalyticsLedgerStamp()
	local byItem = multiDemandCache.byEcon[econKey]
	local cached = byItem and byItem[itemID]
	local now = (ring and #ring > 0 or lotAt > 0) and time and time() or nil
	if cached and cached.scanAt == scanAt and cached.scanPrice == scanPrice and cached.scanQty == scanQty
		and cached.lotAt == lotAt and cached.lotPrice == lotPrice and cached.lotQty == lotQty
		and cached.analyticsModel == analyticsModel and cached.ledgerVer == ledgerVer
		and cached.ledgerDB == ledgerDB and cached.modelGen == modelGen and cached.ledgerDay == ledgerDay
		and (not cached.scanExpiry or (now and now < cached.scanExpiry)) then
		return cached.result ~= false and cached.result or nil
	end
	local velocity = hasLocal and ns.MarketScan and ns.MarketScan.GetLocalVelocity
		and ns.MarketScan.GetLocalVelocity(itemID, econKey) or nil

	local rawSnapVel = getItemSnapshotVelocityRaw(itemID, econKey)
	local snapMeta = getSnapshotMetaRaw(econKey)
	local velocityObsHours = (snapMeta and demandNumber(snapMeta.velocityObsHours)) or 0
	local _, snapRec = ns.QueryLocalSnapshot(itemID, econKey)
	local snapQty = snapRec and demandNumber(snapRec.qty) or nil
	local snapVel, snapDaily = nil, nil
	if rawSnapVel and type(rawSnapVel.obsHours) == "number" and rawSnapVel.obsHours >= 3 then
		snapDaily = demandNumber(rawSnapVel.estDailySold)
		if snapDaily ~= nil then
			snapVel = rawSnapVel
		end
	end
	local snapObsHours = snapVel and snapVel.obsHours or 0
	local snapConfidence = snapVel and snapVel.confidence or 0
	local localDaily = velocity and demandNumber(velocity.clearsPerDay) or nil
	local localConf = velocity and velocity.confidence or "None"
	local personalDaily = queryPersonalDailySold(itemID, econKey, analyticsModel, ledgerVer, ledgerDB, modelGen, ledgerDay)
	local observedZero = (rawSnapVel == nil and velocityObsHours >= 12 and snapQty ~= nil and snapQty > 0)

	-- Unified single-realm demand estimate:
	-- 1. Realm observations (Blizzard hourly velocity weighted by confidence + local AH clears).
	local marketEst, marketSrc = nil, nil
	if snapDaily ~= nil and localDaily ~= nil then
		local wSnap = (snapConfidence >= 3 and 0.85) or (snapConfidence == 2 and 0.65) or 0.45
		local wLocal = (localConf == "High" and 0.70) or 0.35
		marketEst = (snapDaily * wSnap + localDaily * wLocal) / (wSnap + wLocal)
		marketSrc = (wSnap >= wLocal) and "Blizz" or "Local"
	elseif snapDaily ~= nil then
		marketEst = snapDaily
		marketSrc = "Blizz"
	elseif localDaily ~= nil then
		marketEst = localDaily
		marketSrc = "Local"
	elseif observedZero then
		snapDaily = 0
		snapObsHours = velocityObsHours
		marketEst = 0
		marketSrc = "Blizz"
	end

	-- 2. ALWAYS floor at confirmed personal 7d AH sales/day!
	local effectiveDailySold, demandSource
	if personalDaily > 0 then
		effectiveDailySold = math.max(marketEst or 0, personalDaily)
		if marketSrc == "Blizz" and ((snapDaily or 0) > 0 or (marketEst or 0) > 0) then
			demandSource = "Blizz+You"
		elseif marketSrc == "Local" and (localDaily or 0) > 0 then
			demandSource = "Local+You"
		else
			demandSource = "Personal"
		end
	else
		effectiveDailySold = marketEst
		if effectiveDailySold ~= nil and effectiveDailySold > 0 then
			demandSource = marketSrc
		elseif snapVel or (observedZero and marketSrc == "Blizz") then
			demandSource = "Blizz"
		end
	end

	local confidence
	if personalDaily > 0
		or (snapVel and snapConfidence >= 3 and snapObsHours >= 24)
		or localConf == "High" then
		confidence = "High"
	elseif (snapVel and snapObsHours >= 12)
		or (observedZero and marketSrc == "Blizz" and velocityObsHours >= 48)
		or localConf == "Med" then
		confidence = "Med"
	elseif snapVel ~= nil or (observedZero and marketSrc == "Blizz") or localConf == "Low" then
		confidence = "Low"
	else
		confidence = "None"
	end

	local result = {
		dailySold = effectiveDailySold,
		effectiveDailySold = effectiveDailySold,
		localClearsPerDay = localDaily,
		localScanPairs = velocity and velocity.scanPairs or 0,
		localConfidence = localConf,
		personalDailySold = personalDaily,
		snapVel = snapVel,
		snapDailySold = snapDaily,
		snapObsHours = snapObsHours,
		velocityObsHours = velocityObsHours,
		snapConfidence = snapConfidence,
		snapRaw7d = snapVel and snapVel.raw7d or 0,
		snapSource = snapVel and "Blizz" or nil,
		demandSource = demandSource,
		confidence = confidence,
	}
	local demand = effectiveDailySold or 0
	local supply = snapQty
	local score = math.min(60, math.log(1 + demand) * 20)
	if supply and supply > 0 then score = score + math.min(15, demand / supply * 15) end
	result.liquidityScore = math.max(0, math.min(100, score))

	if not byItem then byItem = {}; multiDemandCache.byEcon[econKey] = byItem end
	byItem[itemID] = {
		result = result,
		scanAt = scanAt, scanPrice = scanPrice, scanQty = scanQty,
		lotAt = lotAt, lotPrice = lotPrice, lotQty = lotQty,
		analyticsModel = analyticsModel, ledgerVer = ledgerVer,
		ledgerDB = ledgerDB, modelGen = modelGen, ledgerDay = ledgerDay,
		scanExpiry = localScanExpiry(ring, now or (time and time() or 0)),
	}
	return result
end

---------------------------------------------------------------------------------------------------
-- Dynamic BoP / Sellable Detection & Live Client Recipe Reagent Learner

-- Returns isSellable (boolean), bindReason (string)
function ns.IsItemSellable(outputItemID, staticSellable, isEnchant)
	if isEnchant or not outputItemID or outputItemID <= 0 then
		return false, "Direct Enchant (Cannot list directly on AH)"
	end
	local ec = ns._evalCache
	local sKey
	if ec then
		sKey = outputItemID * 4 + (staticSellable == false and 1 or (staticSellable == true and 2 or 0))
		local hit = ec.sellable[sKey]
		if hit then
			return hit[1], hit[2]
		end
	end
	local bindType
	if C_Item and C_Item.GetItemInfo then
		bindType = select(14, C_Item.GetItemInfo(outputItemID))
	elseif GetItemInfo then
		bindType = select(14, GetItemInfo(outputItemID))
	end
	local sellable, reason
	if type(bindType) == "number" then
		-- 0 = None, 1 = Bind on Pickup (Soulbound), 2 = Bind on Equip, 3 = Bind on Use, 4 = Quest
		if bindType == 1 or bindType == 4 then
			sellable, reason = false, "Bind on Pickup (Soulbound)"
		else
			sellable, reason = true, bindType == 2 and "Bind on Equip (Sellable on AH)" or "Tradeable Item (Sellable on AH)"
		end
	else
		if staticSellable == nil then
			ns.RequestItemDataLoad(outputItemID)
		end
		if ns.ITEM_BOP and ns.ITEM_BOP[outputItemID] then
			sellable, reason = false, "Bind on Pickup (Soulbound)"
		elseif staticSellable == false then
			sellable, reason = false, "Bind on Pickup (Soulbound)"
		else
			sellable, reason = true, "Sellable on AH"
		end
	end
	if ec and sKey then
		ec.sellable[sKey] = { sellable, reason }
	end
	return sellable, reason
end

local function sameReagentList(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
	local mapA = {}
	for i = 1, #a do
		local pair = a[i]
		if type(pair) ~= "table" then return false end
		local id, qty = tonumber(pair[1]), tonumber(pair[2])
		if not id or not qty then return false end
		mapA[id] = (mapA[id] or 0) + qty
	end
	local mapB = {}
	for i = 1, #b do
		local pair = b[i]
		if type(pair) ~= "table" then return false end
		local id, qty = tonumber(pair[1]), tonumber(pair[2])
		if not id or not qty then return false end
		mapB[id] = (mapB[id] or 0) + qty
	end
	for id, qty in pairs(mapA) do
		if mapB[id] ~= qty then return false end
	end
	for id, qty in pairs(mapB) do
		if mapA[id] ~= qty then return false end
	end
	return true
end

local function ensureRecipesBySpellIndex()
	if not ns._recipesBySpell then
		local idx = {}
		for _, rec in ipairs(ns.RECIPES or {}) do
			if rec.spellID and rec.spellID > 0 then
				idx[rec.spellID] = rec
			end
		end
		ns._recipesBySpell = idx
	end
	return ns._recipesBySpell
end

-- Applies live server reagents captured from an open profession window when they differ from catalog data.
function ns.SyncLiveRecipeReagents(spellID, liveReagents, bank)
	spellID = tonumber(spellID)
	if not spellID or spellID <= 0 or type(liveReagents) ~= "table" or #liveReagents == 0 then
		return false
	end
	local clean = {}
	for i = 1, #liveReagents do
		local pair = liveReagents[i]
		local id = type(pair) == "table" and tonumber(pair[1]) or nil
		local qty = type(pair) == "table" and tonumber(pair[2]) or nil
		if not id or id <= 0 or not qty or qty <= 0 then
			return false
		end
		clean[i] = { id, qty }
	end
	local bySpell = ensureRecipesBySpellIndex()
	local rec = bySpell[spellID]
	local mpRec = ns.MP and ns.MP.RECIPES_BY_SPELL and ns.MP.RECIPES_BY_SPELL[spellID]
	if not rec and not mpRec then return false end
	local changed = false
	if rec and not sameReagentList(rec.reagents, clean) then
		rec.reagents = clean
		rec._reagentsChecked = true
		changed = true
	end
	if mpRec and not sameReagentList(mpRec.r, clean) then
		local mpCopy = {}
		for i = 1, #clean do mpCopy[i] = { clean[i][1], clean[i][2] } end
		mpRec.r = mpCopy
		changed = true
	end
	if changed then
		for i = 1, #clean do
			ns.ALL_CATALOG_IDS[clean[i][1]] = true
		end
		local db = ns.GetDB()
		if db then
			db.liveRecipeReagents = db.liveRecipeReagents or {}
			db.liveRecipeReagents[spellID] = clean
		end
		if ns.InvalidateCraftDecisionCache then
			ns.InvalidateCraftDecisionCache(bank)
		end
	end
	return changed
end

function ns.RecordRecipeYieldRange(spellID, minMade, maxMade)
	spellID = tonumber(spellID)
	local lo = tonumber(minMade)
	local hi = tonumber(maxMade or minMade)
	if not spellID or spellID <= 0 or not lo or lo <= 0 then return false end
	if not hi or hi <= 0 then hi = lo end
	lo = math.floor(lo + 0.5)
	hi = math.floor(hi + 0.5)
	if lo > hi then lo, hi = hi, lo end
	spellID = math.floor(spellID + 0.5)
	local bySpell = ensureRecipesBySpellIndex()
	local rec = bySpell[spellID]
	local updated = false
	if rec then
		if rec.minMade ~= lo or rec.maxMade ~= hi then
			rec.minMade, rec.maxMade = lo, hi
			updated = true
		end
	end
	local db = ns.GetDB()
	local baseNum = (rec and tonumber(rec.numMade)) or 1
	if type(db) == "table" and (lo ~= hi or lo ~= baseNum) then
		db.learnedRecipeYields = db.learnedRecipeYields or {}
		local prev = db.learnedRecipeYields[spellID]
		if type(prev) ~= "table" or prev.min ~= lo or prev.max ~= hi then
			db.learnedRecipeYields[spellID] = { min = lo, max = hi }
			updated = true
		end
	end
	return updated
end

function ns.ResolveRecipeYieldRange(recipe)
	if type(recipe) ~= "table" then return 1, 1 end
	local lo = tonumber(recipe.minMade)
	local hi = tonumber(recipe.maxMade)
	local spellID = tonumber(recipe.spellID)
	if (not lo or not hi) and spellID and spellID > 0 then
		local db = ns.GetDB()
		local saved = db and db.learnedRecipeYields and db.learnedRecipeYields[spellID]
		if type(saved) == "table" and tonumber(saved.min) and tonumber(saved.min) > 0 then
			lo = math.floor(tonumber(saved.min) + 0.5)
			hi = math.floor(tonumber(saved.max or saved.min) + 0.5)
			if lo > hi then lo, hi = hi, lo end
			recipe.minMade, recipe.maxMade = lo, hi
		end
	end
	if (not lo or not hi) and not recipe._yieldChecked and spellID and spellID > 0 and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
		recipe._yieldChecked = true
		local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
		if ok and type(schematic) == "table" then
			local qMin = tonumber(schematic.quantityMin)
			local qMax = tonumber(schematic.quantityMax or qMin)
			if qMin and qMin > 0 then
				lo = math.floor(qMin + 0.5)
				hi = math.max(lo, math.floor((qMax or lo) + 0.5))
				recipe.minMade, recipe.maxMade = lo, hi
				ns.RecordRecipeYieldRange(spellID, lo, hi)
			end
		end
	end
	local base = (tonumber(recipe.numMade) and tonumber(recipe.numMade) > 0) and math.floor(tonumber(recipe.numMade) + 0.5) or 1
	lo = (lo and lo > 0) and lo or base
	hi = (hi and hi >= lo) and hi or lo
	return lo, hi
end

-- Resolves recipe reagents, learning dynamically from WoW's client schematic or tooltip if uncached
function ns.ResolveRecipeReagents(recipe)
	local db = ns.GetDB()
	local liveOverride = db and db.liveRecipeReagents and recipe.spellID and db.liveRecipeReagents[recipe.spellID]
	if type(liveOverride) == "table" and #liveOverride > 0 then
		if not sameReagentList(recipe.reagents, liveOverride) then
			recipe.reagents = liveOverride
			recipe._reagentsChecked = true
			for i = 1, #liveOverride do
				if liveOverride[i] and liveOverride[i][1] then
					ns.ALL_CATALOG_IDS[liveOverride[i][1]] = true
				end
			end
		end
		return recipe.reagents
	end
	if recipe.reagents and #recipe.reagents > 0 then
		return recipe.reagents
	end
	if recipe._reagentsChecked then
		return recipe.reagents or {}
	end
	local cacheKey = recipe.recipeItemID or recipe.spellID
	if db and db.learnedSchematics and cacheKey and db.learnedSchematics[cacheKey] then
		local cached = db.learnedSchematics[cacheKey]
		if #cached > 0 then
			recipe.reagents = cached
			recipe._reagentsChecked = true
			return cached
		end
	end

	-- 1. Try C_Item.GetItemSpell + C_TradeSkillUI.GetRecipeSchematic
	local spellID = recipe.spellID
	if (not spellID or spellID <= 0) and recipe.recipeItemID and C_Item and C_Item.GetItemSpell then
		local ok, first, second = pcall(C_Item.GetItemSpell, recipe.recipeItemID)
		if ok then
			spellID = type(first) == "table" and first.spellID or second
			if type(spellID) == "number" and spellID > 0 then
				recipe.spellID = spellID
			end
		end
	end
	if spellID and spellID > 0 and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
		local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
		if ok and type(schematic) == "table" and type(schematic.reagentSlotSchematics) == "table" then
			local learned = {}
			for _, slot in ipairs(schematic.reagentSlotSchematics) do
				local rg = slot.reagents and slot.reagents[1]
				if rg and rg.itemID and slot.quantityRequired and slot.quantityRequired > 0 then
					learned[#learned + 1] = { rg.itemID, slot.quantityRequired }
					ns.ALL_CATALOG_IDS[rg.itemID] = true
				end
			end
			if #learned > 0 then
				recipe.reagents = learned
				recipe._reagentsChecked = true
				if schematic.quantityMin and schematic.quantityMin > 0 then
					recipe.numMade = schematic.quantityMin
					local qMax = math.max(schematic.quantityMin, tonumber(schematic.quantityMax) or schematic.quantityMin)
					recipe.minMade = schematic.quantityMin
					recipe.maxMade = qMax
					ns.RecordRecipeYieldRange(spellID, schematic.quantityMin, qMax)
				end
				if db and cacheKey then
					db.learnedSchematics = db.learnedSchematics or {}
					db.learnedSchematics[cacheKey] = learned
				end
				return learned
			end
		end
	end

	-- 2. Try C_TooltipInfo.GetItemByID on the recipe item ("Requires Reagent (2), Reagent")
	if recipe.recipeItemID and C_TooltipInfo and C_TooltipInfo.GetItemByID then
		local ok, data = pcall(C_TooltipInfo.GetItemByID, recipe.recipeItemID)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			local reqPrefix = SPELL_REAGENTS or "Requires "
			reqPrefix = reqPrefix:gsub("|n", ""):gsub("^%s+", "")
			for _, line in ipairs(data.lines) do
				local txt = line and line.leftText
				if type(txt) == "string" then
					local clean = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\194\160", " ")
					local body = clean:match("^Requires%s+(.+)$") or clean:match("^Reagents:%s*(.+)$")
					if body and not body:find("^Level ") and not body:find("%(%d+%)$") then
						local learned = {}
						for part in body:gmatch("([^,]+)") do
							part = part:match("^%s*(.-)%s*$")
							local rname, rqty = part:match("^(.-)%s*%((%d+)%)$")
							if not rname then rname, rqty = part, "1" end
							local rid = ns.ITEM_IDS_BY_NAME[rname]
							if not rid and C_Item and C_Item.GetItemInfoInstant then
								rid = C_Item.GetItemInfoInstant(rname)
							end
							if rid and rid > 0 then
								learned[#learned + 1] = { rid, tonumber(rqty) or 1 }
								ns.ALL_CATALOG_IDS[rid] = true
							end
						end
						if #learned > 0 then
							recipe.reagents = learned
							recipe._reagentsChecked = true
							if db and cacheKey then
								db.learnedSchematics = db.learnedSchematics or {}
								db.learnedSchematics[cacheKey] = learned
							end
							return learned
						end
					end
				end
			end
		end
	end

	recipe._reagentsChecked = true
	return recipe.reagents or {}
end

-- Computes total per-unit crafting cost for a recipe or writ
function ns.ComputeCraftCost(reagents, numMade, fallbackOutputID)
	numMade = (type(numMade) == "number" and numMade > 0) and numMade or 1
	if reagents and #reagents > 0 then
		local sum = 0
		local breakdown = {}
		local complete = true
		for _, pair in ipairs(reagents) do
			local rid, rqty = pair[1], pair[2]
			local unitCost, src, isVendor = ns.GetReagentUnitCost(rid)
			local lineCost = unitCost and (unitCost * rqty) or nil
			if lineCost then
				sum = sum + lineCost
			else
				complete = false
			end
			breakdown[#breakdown + 1] = {
				itemID = rid,
				name = ns.ItemName(rid),
				qty = rqty,
				unitCost = unitCost,
				lineCost = lineCost,
				source = src,
				isVendor = isVendor,
			}
		end
		if complete then
			return math.floor((sum / numMade) + 0.5), breakdown, "Reagents"
		end
		return nil, breakdown, nil
	end
	return nil, {}, nil
end

---------------------------------------------------------------------------------------------------
-- Player Profession, Skill Rank, Known Spell & Merchant Reputation Detection

local spellProfSkillCache = nil
local function getSpellProfSkillMap()
	if spellProfSkillCache then return spellProfSkillCache end
	local map = {}
	for _, list in ipairs({ ns.RECIPES or {}, ns.WRITS or {} }) do
		for _, entry in ipairs(list) do
			local sid = tonumber(entry.spellID)
			local pk = entry.prof
			if sid and sid > 0 and pk then
				local sk = tonumber(entry.skill) or 1
				local cur = map[sid]
				if not cur then
					map[sid] = { prof = pk, skill = sk }
				elseif sk > cur.skill then
					cur.skill = sk
				end
			end
		end
	end
	spellProfSkillCache = map
	return map
end

local function scanLivePlayerProfessionsUncached()
	local map = {} -- map[profKey] = currentSkillRank

	local function record(profKey, rank)
		if not profKey then return end
		rank = tonumber(rank) or 1
		if not map[profKey] or rank > map[profKey] then
			map[profKey] = rank
		end
	end

	-- 1. Retail / Forever 16001 GetProfessions()
	if GetProfessions and GetProfessionInfo then
		local ok, p1, p2, arch, fish, cook, fa = pcall(GetProfessions)
		if ok then
			for _, idx in pairs({ p1, p2, arch, fish, cook, fa }) do
				if idx then
					local iok, name, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, idx)
					if iok then
						if type(name) == "table" then
							skillLine = name.skillLine or name.professionID
							rank = name.skillLevel or name.rank
							name = name.name
						end
						local pkey = skillLine and ns.PROF_BY_SKILLLINE[skillLine]
						if not pkey and type(name) == "string" then
							local low = name:lower()
							for _, p in ipairs(ns.PROFESSIONS) do
								if p.full and p.full:lower() == low then pkey = p.key; break end
							end
						end
						record(pkey, rank)
					end
				end
			end
		end
	end

	-- 2. Classic GetNumSkillLines / GetSkillLineInfo
	if GetNumSkillLines and GetSkillLineInfo then
		local ok, num = pcall(GetNumSkillLines)
		if ok and type(num) == "number" then
			for i = 1, num do
				local iok, sName, isHeader, _, sRank = pcall(GetSkillLineInfo, i)
				if iok and not isHeader and type(sName) == "string" then
					local low = sName:lower()
					for _, p in ipairs(ns.PROFESSIONS) do
						if p.full and p.full:lower() == low then
							record(p.key, sRank)
							break
						end
					end
				end
			end
		end
	end

	-- 3. Fallback spellbook check on Apprentice spells if skill table hasn't populated yet
	for _, p in ipairs(ns.PROFESSIONS) do
		if p.spell and not map[p.key] then
			if (IsPlayerSpell and IsPlayerSpell(p.spell)) or (IsSpellKnown and IsSpellKnown(p.spell)) then
				record(p.key, 1)
			end
		end
	end

	return map
end

local baseGetPlayerProfessions

function ns.GetLivePlayerProfessions()
	if ns.GetPlayerProfessions ~= baseGetPlayerProfessions then
		return ns.GetPlayerProfessions()
	end
	local ec = ns._evalCache
	if ec and ec.liveProfMap then
		return ec.liveProfMap
	end
	local map = scanLivePlayerProfessionsUncached()
	if ec then
		ec.liveProfMap = map
	end
	return map
end

function ns.GetCharProfessions(ch)
	if type(ch) ~= "table" then return {} end
	local out = {}
	if ch == ns.activeChar then
		for pk, rank in pairs(ns.GetLivePlayerProfessions() or {}) do
			if type(rank) == "number" then out[pk] = rank end
		end
	end
	if type(ch.profs) == "table" then
		for pk, rank in pairs(ch.profs) do
			if type(rank) == "number" and rank > (out[pk] or 0) then
				out[pk] = rank
			end
		end
	end
	if type(ch.scannedProfs) == "table" then
		for pk, flag in pairs(ch.scannedProfs) do
			if flag == true and ns.PROF_BY_KEY[pk] and not out[pk] then
				out[pk] = 1
			end
		end
	end
	local spellMap = getSpellProfSkillMap()
	local function inferFromSpells(spellTable)
		if type(spellTable) ~= "table" then return end
		for spID, flag in pairs(spellTable) do
			if flag == true then
				local info = spellMap[tonumber(spID)]
				if info and info.prof and ns.PROF_BY_KEY[info.prof] then
					local cur = out[info.prof] or 0
					local inferred = info.skill or 1
					if inferred > cur then out[info.prof] = math.max(1, inferred) end
				end
			end
		end
	end
	inferFromSpells(ch.knownSpells)
	local mpDB = ns.GetProfessorDB and ns.GetProfessorDB() or _G.MerchantProfessorDB
	local mpKey = (type(ch.name) == "string" and ch.name ~= "" and type(ch.realm) == "string" and ch.realm ~= "")
		and (ch.name .. "-" .. ch.realm) or nil
	if mpDB and type(mpDB.knownSpells) == "table" and mpKey and mpDB.knownSpells[mpKey] then
		inferFromSpells(mpDB.knownSpells[mpKey])
	end
	return out
end

function ns.GetEconomyCharacters(econKey)
	local targetEcon = econKey or (ns.CurrentEconomyInfo and ns.CurrentEconomyInfo().effectiveKey)
		or (ns.activeChar and ns.activeChar.economy)
	local cacheKey = targetEcon or "_default"
	local ec = ns._evalCache
	if ec and ec.econChars and ec.econChars[cacheKey] then
		return ec.econChars[cacheKey]
	end
	local list, seen = {}, {}
	local activeCh = ns.activeChar
	if type(activeCh) == "table" and (not targetEcon or not activeCh.economy or activeCh.economy == targetEcon) then
		list[#list + 1] = activeCh
		seen[activeCh] = true
	end
	local db = ns.GetDB()
	local chars = db and db.chars
	if type(chars) == "table" then
		local keys = {}
		for k, c in pairs(chars) do
			if type(c) == "table" and not seen[c] then
				keys[#keys + 1] = tostring(k)
			end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local c = chars[k]
			if type(c) == "table" and not seen[c] then
				local match = false
				if type(c.economy) == "string" and c.economy ~= "" then
					match = (not targetEcon) or (c.economy == targetEcon)
				elseif type(activeCh) == "table" and c.realm ~= nil and c.realm == activeCh.realm
					and c.faction ~= nil and c.faction == activeCh.faction then
					match = (not targetEcon) or (targetEcon:sub(-(#c.faction + 1)) == ("-" .. c.faction))
				end
				if match then
					seen[c] = true
					list[#list + 1] = c
				end
			end
		end
	end
	if ec and ec.econChars then
		ec.econChars[cacheKey] = list
	end
	return list
end

baseGetPlayerProfessions = function(opts)
	local allChars = ns.IsAllCharsCraftableActive(opts)
	local slot = allChars and "all" or "self"
	local ec = ns._evalCache
	if ec and ec.profMapByMode and ec.profMapByMode[slot] then
		return ec.profMapByMode[slot]
	end
	local map = {}
	for pk, rank in pairs(ns.GetLivePlayerProfessions() or {}) do
		if type(rank) == "number" then map[pk] = rank end
	end
	if allChars then
		for _, ch in ipairs(ns.GetEconomyCharacters()) do
			if ch ~= ns.activeChar then
				for pk, rank in pairs(ns.GetCharProfessions(ch)) do
					if type(rank) == "number" and rank > (map[pk] or 0) then
						map[pk] = rank
					end
				end
			end
		end
	end
	if ec and ec.profMapByMode then
		ec.profMapByMode[slot] = map
	end
	return map
end

ns.GetPlayerProfessions = baseGetPlayerProfessions

local function readableTradeVal(v)
	return not ((_G.issecretvalue and _G.issecretvalue(v)) or (type(v) == "table" and _G.issecrettable and _G.issecrettable(v)))
end

local function safeCallBool(fn)
	if type(fn) ~= "function" then return false end
	local ok, val = pcall(fn)
	if not ok or not readableTradeVal(val) then return false end
	return val == true or val == 1
end

function ns.IsForeignTradeSkill()
	local T = _G.C_TradeSkillUI
	if T then
		if safeCallBool(T.IsTradeSkillLinked)
			or safeCallBool(T.IsTradeSkillGuild)
			or safeCallBool(T.IsTradeSkillGuildMember)
			or safeCallBool(T.IsNPCCrafting) then
			return true
		end
	end
	if safeCallBool(_G.IsTradeSkillLinked) or safeCallBool(_G.IsTradeSkillGuild) then
		return true
	end
	return false
end

local function resolveOpenTradeSkillProf(pinfo)
	if not readableTradeVal(pinfo) or type(pinfo) ~= "table" then return nil, nil end
	local pkey = readableTradeVal(pinfo.professionID) and pinfo.professionID and ns.PROF_BY_SKILLLINE[pinfo.professionID] or nil
	if not pkey and readableTradeVal(pinfo.professionName) and type(pinfo.professionName) == "string" then
		local low = pinfo.professionName:lower()
		for _, p in ipairs(ns.PROFESSIONS) do
			if p.full and p.full:lower() == low then pkey = p.key; break end
		end
	end
	local winRank = (readableTradeVal(pinfo.skillLevel) and type(pinfo.skillLevel) == "number" and pinfo.skillLevel > 0) and pinfo.skillLevel or nil
	return pkey, winRank
end

local function getOpenOwnTradeSkillState(pm)
	local ec = ns._evalCache
	if ec and ec.openTS ~= nil then
		return ec.openTS
	end
	local state = false
	local T = _G.C_TradeSkillUI
	if T and T.GetRecipeInfo and not ns.IsForeignTradeSkill()
		and (not T.IsTradeSkillReady or safeCallBool(T.IsTradeSkillReady)) then
		local openProf, winRank = nil, nil
		if T.GetBaseProfessionInfo then
			local pok, pinfo = pcall(T.GetBaseProfessionInfo)
			if pok then openProf, winRank = resolveOpenTradeSkillProf(pinfo) end
		end
		local hasAnyProf = pm and next(pm) ~= nil
		local ownRank = openProf and pm and pm[openProf] or nil
		local foreignRank = hasAnyProf and openProf and (not ownRank or (winRank and winRank > ownRank + 15))
		if not foreignRank then
			local idSet = nil
			if openProf and T.GetAllRecipeIDs then
				local iok, ids = pcall(T.GetAllRecipeIDs)
				if iok and readableTradeVal(ids) and type(ids) == "table" and #ids > 0 then
					idSet = {}
					for _, id in ipairs(ids) do
						if readableTradeVal(id) and type(id) == "number" then
							idSet[id] = true
						end
					end
				end
			end
			state = { prof = openProf, ids = idSet }
		end
	end
	if ec then
		ec.openTS = state
	end
	return state
end

local function canUseLegacyGlobalKnownSpells(db, ch, hasAnyProf)
	return db ~= nil and type(db.knownSpells) == "table" and next(db.knownSpells) ~= nil and ch ~= nil and hasAnyProf == true
end

local function charOwnsToolItem(toolID, ch, isActive)
	if not toolID or toolID <= 0 then return false end
	local tName = ns.ItemName and ns.ItemName(toolID) or nil
	if type(ch) == "table" and type(tName) == "string" and tName ~= "" then
		for _, k in ipairs({ "bags", "boundBags", "bank", "mail", "bought" }) do
			local tbl = ch[k]
			if type(tbl) == "table" and (tonumber(tbl[tName]) or 0) > 0 then
				return true
			end
		end
	end
	if isActive then
		local fn = (_G.C_Item and type(_G.C_Item.GetItemCount) == "function" and _G.C_Item.GetItemCount)
			or (type(_G.GetItemCount) == "function" and _G.GetItemCount)
			or nil
		if fn then
			local ok, cnt = pcall(fn, toolID, true)
			if ok and readableTradeVal(cnt) and (tonumber(cnt) or 0) > 0 then
				return true
			end
		end
	end
	return false
end

local function checkRecipeKnownOnChar(recipe, ch, pm, isActive)
	if not recipe then return false end
	if recipe.anyChar then return true end
	local hasAnyProf = pm and next(pm) ~= nil
	if hasAnyProf and recipe.prof and ns.PROF_BY_KEY[recipe.prof] and not pm[recipe.prof] then
		return false
	end
	local toolID = readableTradeVal(recipe.toolItemID) and tonumber(recipe.toolItemID) or nil
	if toolID and toolID > 0 then
		if recipe.prof and ns.PROF_BY_KEY[recipe.prof] then
			local skill = pm and tonumber(pm[recipe.prof]) or nil
			if not skill or skill < (tonumber(recipe.skill) or 1) then
				return false
			end
		end
		local spellID = recipe.spellID
		if ch and type(ch.knownSpells) == "table" and spellID and ch.knownSpells[spellID] then
			return true
		end
		return charOwnsToolItem(toolID, ch, isActive)
	end
	if recipe.acqType == "start" and recipe.prof and pm and pm[recipe.prof] then
		return true
	end
	local spellID = recipe.spellID
	local ec = ns._evalCache
	local mpDB = ns.GetProfessorDB and ns.GetProfessorDB() or _G.MerchantProfessorDB
	if isActive then
		if spellID and spellID > 0 then
			if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
			if IsSpellKnown and IsSpellKnown(spellID) then return true end
			local openTS = getOpenOwnTradeSkillState(pm)
			if openTS and (not openTS.prof or recipe.prof == openTS.prof) then
				local live
				if ec and ec.knownSpell[spellID] ~= nil then
					local cached = ec.knownSpell[spellID]
					if cached ~= "nil" then live = cached end
				else
					local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spellID)
					if ok and readableTradeVal(info) and type(info) == "table" and readableTradeVal(info.learned) and info.learned ~= nil then
						live = (info.learned == true)
						if ec then ec.knownSpell[spellID] = live end
					elseif ec then
						ec.knownSpell[spellID] = "nil"
					end
				end
				if live == true then
					return true
				elseif live == false and openTS.prof and recipe.prof == openTS.prof and openTS.ids and openTS.ids[spellID] then
					return false
				end
			end
			if mpDB and mpDB.knownSpells and ns.MP and ns.MP.GetCharKey then
				local ck = ns.MP.GetCharKey()
				if ck and mpDB.knownSpells[ck] and mpDB.knownSpells[ck][spellID] then
					return true
				end
			end
		end
	else
		if not ch then return false end
		if mpDB and type(mpDB.knownSpells) == "table" and spellID and spellID > 0 then
			local mpKey = (type(ch.name) == "string" and ch.name ~= "" and type(ch.realm) == "string" and ch.realm ~= "")
				and (ch.name .. "-" .. ch.realm) or nil
			if mpKey and mpDB.knownSpells[mpKey] and mpDB.knownSpells[mpKey][spellID] then
				return true
			end
		end
	end
	if ch and (ch.knownSpells or ch.knownOutputs or ch.knownNames) then
		if spellID and spellID > 0 and ch.knownSpells and ch.knownSpells[spellID] then
			return true
		end
		local hasSpellMap = ch.knownSpells and next(ch.knownSpells) ~= nil
		if not spellID or spellID <= 0 or not hasSpellMap then
			local outID = recipe.outputItemID or recipe.requiredItemID
			if outID and outID > 0 and ch.knownOutputs and ch.knownOutputs[outID] then
				return true
			end
			local nm = (recipe.requiredItemName or recipe.name or ""):lower()
			if nm ~= "" and ch.knownNames and ch.knownNames[nm] then
				return true
			end
		end
		if (ch.scannedProfs and next(ch.scannedProfs) ~= nil) or hasSpellMap or not isActive then
			return false
		end
	end
	if isActive then
		local db = ns.GetDB()
		if canUseLegacyGlobalKnownSpells(db, ch, hasAnyProf) and spellID and db.knownSpells[spellID] then
			if hasAnyProf and recipe.prof and pm[recipe.prof] and recipe.skill and recipe.skill > (pm[recipe.prof] + 15) then
				return false
			end
			local fac = (ch and ch.faction) or (UnitFactionGroup and UnitFactionGroup("player")) or nil
			local facCode = (fac == "Alliance" or fac == "A") and "A" or ((fac == "Horde" or fac == "H") and "H" or nil)
			if recipe.fac and recipe.fac ~= "AH" and facCode and recipe.fac ~= facCode then
				return false
			end
			return true
		end
	end
	return false
end

local function formatAltKnownTag(knownInfo)
	if type(knownInfo) ~= "table" or knownInfo.knownOnActive or #(knownInfo.altNames or {}) == 0 then
		return nil
	end
	local alts = knownInfo.altNames
	if #alts > 1 then
		return alts[1] .. " +" .. tostring(#alts - 1)
	end
	return alts[1]
end

function ns.GetRecipeKnownInfo(recipe, opts)
	if not recipe then return { known = false, knownOnActive = false, altNames = {} } end
	local allChars = ns.IsAllCharsCraftableActive(opts)
	local slot = allChars and "all" or "self"
	local ec = ns._evalCache
	local cacheBucket = ec and ec.knownInfoByMode and ec.knownInfoByMode[slot]
	if cacheBucket and cacheBucket[recipe] then
		return cacheBucket[recipe]
	end
	local activeKnown = checkRecipeKnownOnChar(recipe, ns.activeChar, ns.GetLivePlayerProfessions(), true)
	local altNames = {}
	if allChars then
		local seen = {}
		local activeCh = ns.activeChar
		for _, ch in ipairs(ns.GetEconomyCharacters()) do
			if ch ~= activeCh and checkRecipeKnownOnChar(recipe, ch, ns.GetCharProfessions(ch), false) then
				local label = (type(ch.name) == "string" and ch.name ~= "") and ch.name or "Alt"
				if not seen[label] then
					seen[label] = true
					altNames[#altNames + 1] = label
				end
			end
		end
	end
	local info = {
		known = activeKnown or (#altNames > 0),
		knownOnActive = activeKnown,
		altNames = altNames,
	}
	if cacheBucket then cacheBucket[recipe] = info end
	if ec and ec.knownRecByMode and ec.knownRecByMode[slot] then
		ec.knownRecByMode[slot][recipe] = info.known
	end
	return info
end

function ns.IsRecipeKnown(recipe, opts)
	if not recipe then return false end
	local allChars = ns.IsAllCharsCraftableActive(opts)
	local slot = allChars and "all" or "self"
	local ec = ns._evalCache
	local hit = ec and ec.knownRecByMode and ec.knownRecByMode[slot] and ec.knownRecByMode[slot][recipe]
	if hit ~= nil then
		return hit
	end
	return ns.GetRecipeKnownInfo(recipe, opts).known
end

local COOLDOWN_WINDOW_MAP = {
	[82800]  = { 86400,  "24h" },
	[169200] = { 172800, "48h" },
	[255600] = { 259200, "72h" },
	[259200] = { 259200, "72h" },
	[342000] = { 345600, "4d"  },
}

local SHARED_TRANSMUTE_LIST = {
	17187,   -- Transmute: Arcanite (48h)
	1317279, -- Transmute: Legionite (48h)
	17559,   -- Transmute: Air to Fire (24h)
	17560,   -- Transmute: Fire to Earth (24h)
	17561,   -- Transmute: Earth to Water (24h)
	17562,   -- Transmute: Water to Air (24h)
	17563,   -- Transmute: Undeath to Water (24h)
	17564,   -- Transmute: Water to Undeath (24h)
	17565,   -- Transmute: Life to Earth (24h)
	17566,   -- Transmute: Earth to Life (24h)
}
local INDEPENDENT_TRANSMUTE_SPELLS = { [11479] = true, [11480] = true, [25146] = true }
local SHARED_TRANSMUTE_SPELLS = {}
for _, sid in ipairs(SHARED_TRANSMUTE_LIST) do
	SHARED_TRANSMUTE_SPELLS[sid] = true
end

function ns.GetRecipeBaseCooldown(recipe)
	if type(recipe) ~= "table" then return nil end
	local raw = recipe.cd or recipe.cooldown
	local cd = readableTradeVal(raw) and tonumber(raw) or nil
	local sid = readableTradeVal(recipe.spellID) and recipe.spellID or (readableTradeVal(recipe.s) and recipe.s or nil)
	if (not cd or cd < 60) and ns.MP and ns.MP.RECIPES_BY_SPELL and sid then
		local mpRec = ns.MP.RECIPES_BY_SPELL[sid]
		local mpRaw = mpRec and mpRec.cd
		if readableTradeVal(mpRaw) then
			cd = tonumber(mpRaw)
		end
	end
	if cd and cd >= 60 then return cd end
	return nil
end

function ns.NormalizeCooldownWindow(baseSec)
	baseSec = tonumber(baseSec) or 0
	local hit = COOLDOWN_WINDOW_MAP[baseSec]
	if hit then return hit[1], hit[2] end
	if baseSec >= 3600 then
		return baseSec, string.format("%dh", math.floor(baseSec / 3600 + 0.5))
	end
	return baseSec, string.format("%dm", math.max(1, math.floor(baseSec / 60 + 0.5)))
end

function ns.FormatCooldownRemaining(remSec)
	local s = math.max(0, math.floor((tonumber(remSec) or 0) + 0.5))
	if s >= 3600 then
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		if m > 0 then
			return string.format("%dh %dm", h, m)
		end
		return string.format("%dh", h)
	elseif s >= 60 then
		return string.format("%dm", math.floor(s / 60))
	end
	return string.format("%ds", s)
end

function ns.GetRecipeCooldownGroup(recipe)
	if type(recipe) ~= "table" then return nil, nil end
	local rawID = readableTradeVal(recipe.spellID) and recipe.spellID or (readableTradeVal(recipe.s) and recipe.s or nil)
	local spellID = rawID and tonumber(rawID) or nil
	if spellID and INDEPENDENT_TRANSMUTE_SPELLS[spellID] then return nil, nil end
	if spellID and SHARED_TRANSMUTE_SPELLS[spellID] then
		return "alchemy_transmute", "Shared Transmute CD"
	end
	local rname = recipe.name or recipe.n
	if recipe.prof == "alchemy" and type(rname) == "string" and rname:find("^Transmute:")
		and (ns.GetRecipeBaseCooldown(recipe) or 0) >= 82800 then
		return "alchemy_transmute", "Shared Transmute CD"
	end
	return nil, nil
end

local function ensureActiveCharCooldowns()
	local ch = ns.activeChar
	if type(ch) == "table" then
		if type(ch.cooldowns) ~= "table" then ch.cooldowns = {} end
		if type(ch.cooldownGroups) ~= "table" then ch.cooldownGroups = {} end
		return ch.cooldowns, ch.cooldownGroups
	end
	return nil, nil
end

local function rebuildSharedTransmuteCooldownGroup(ch, nowEpoch)
	if type(ch) ~= "table" then return nil end
	if type(ch.cooldowns) ~= "table" then ch.cooldowns = {} end
	if type(ch.cooldownGroups) ~= "table" then ch.cooldownGroups = {} end
	local cds, groups = ch.cooldowns, ch.cooldownGroups
	local now = readableTradeVal(nowEpoch) and tonumber(nowEpoch) or (time and time()) or 0
	local latest
	for _, spellID in ipairs(SHARED_TRANSMUTE_LIST) do
		local raw = cds and cds[spellID]
		local exp = readableTradeVal(raw) and tonumber(raw) or nil
		if exp and exp > now and (not latest or exp > latest) then latest = exp end
	end
	if groups then groups.alchemy_transmute = latest end
	return latest
end

ns.RebuildSharedTransmuteCooldownGroup = rebuildSharedTransmuteCooldownGroup

local function computeLiveStartDurationRem(startTime, duration)
	if not readableTradeVal(startTime) or not readableTradeVal(duration) then return nil, false end
	startTime = tonumber(startTime)
	duration = tonumber(duration)
	if not startTime or not duration then return nil, false end
	if duration == 0 then
		return 0, true
	end
	if duration <= 1.5 or startTime <= 0 then
		return nil, false
	end
	local gt = GetTime and GetTime() or nil
	if not readableTradeVal(gt) or type(gt) ~= "number" then return nil, false end
	local elapsed = gt - startTime
	if elapsed < 0 then
		if startTime > 4000000 and gt < 500000 then
			elapsed = (4294967.296 - startTime) + gt
		else
			elapsed = 0
		end
	end
	local rem = math.max(0, math.min(duration + 60, duration - elapsed))
	return rem, true
end

local function probeLiveSpellCooldown(spellID)
	local sawZero = false
	if _G.C_TradeSkillUI and type(_G.C_TradeSkillUI.GetRecipeCooldown) == "function" then
		local ok, rem = pcall(_G.C_TradeSkillUI.GetRecipeCooldown, spellID)
		if ok and readableTradeVal(rem) and type(rem) == "number" then
			if rem > 1.5 then return rem, true end
			if rem == 0 then sawZero = true end
		end
	end
	if _G.C_Spell and type(_G.C_Spell.GetSpellCooldown) == "function" then
		local ok, info = pcall(_G.C_Spell.GetSpellCooldown, spellID)
		if ok and readableTradeVal(info) and type(info) == "table" then
			local rem, valid = computeLiveStartDurationRem(info.startTime, info.duration)
			if valid then
				if rem > 1.5 then return rem, true end
				sawZero = true
			end
		end
	end
	if type(_G.GetSpellCooldown) == "function" then
		local ok, startTime, duration = pcall(_G.GetSpellCooldown, spellID)
		if ok then
			local rem, valid = computeLiveStartDurationRem(startTime, duration)
			if valid then
				if rem > 1.5 then return rem, true end
				sawZero = true
			end
		end
	end
	if sawZero then return 0, true end
	return nil, false
end

local function probeLiveItemCooldown(itemID)
	local fn = (_G.C_Container and type(_G.C_Container.GetItemCooldown) == "function" and _G.C_Container.GetItemCooldown)
		or (type(_G.GetItemCooldown) == "function" and _G.GetItemCooldown)
		or nil
	if not fn then return nil end
	local ok, startTime, duration = pcall(fn, itemID)
	if not ok or not readableTradeVal(duration) then return nil end
	local dur = tonumber(duration)
	if not dur or dur <= 1.5 then return nil end
	local rem, valid = computeLiveStartDurationRem(startTime, dur)
	if valid and rem and rem > 1.5 then
		return rem
	end
	return nil
end

local function isSiblingTransmuteKnown(sibID)
	local ch = ns.activeChar
	if ch and type(ch.knownSpells) == "table" and ch.knownSpells[sibID] then
		return true
	end
	local rec = ns.MP and ns.MP.RECIPES_BY_SPELL and ns.MP.RECIPES_BY_SPELL[sibID]
	if rec and ns.IsRecipeKnown and ns.IsRecipeKnown(rec, { currentCharOnly = true }) then
		return true
	end
	local db = ns.GetDB and ns.GetDB()
	local livePm = ns.GetLivePlayerProfessions and ns.GetLivePlayerProfessions() or nil
	if canUseLegacyGlobalKnownSpells(db, ch, livePm ~= nil and livePm.alchemy ~= nil) and db.knownSpells[sibID] then
		return true
	end
	return false
end

local function getSavedCharRecipeCooldownRem(ch, spellID, grp, now)
	if type(ch) ~= "table" then return 0 end
	local cds = type(ch.cooldowns) == "table" and ch.cooldowns or nil
	local sharedExp
	if grp == "alchemy_transmute" then sharedExp = rebuildSharedTransmuteCooldownGroup(ch, now) end
	local exp = cds and readableTradeVal(cds[spellID]) and tonumber(cds[spellID]) or nil
	if exp then
		if exp > now then
			return exp - now
		else
			cds[spellID] = nil
		end
	end
	if grp then
		local cdGroups = type(ch.cooldownGroups) == "table" and ch.cooldownGroups or nil
		local gExp
		if grp == "alchemy_transmute" then
			gExp = sharedExp
		elseif cdGroups and readableTradeVal(cdGroups[grp]) then
			gExp = tonumber(cdGroups[grp])
		end
		if gExp then
			if gExp > now then
				return gExp - now
			elseif cdGroups then
				cdGroups[grp] = nil
			end
		end
	end
	return 0
end

local function computeActiveCharCooldownRemaining(recipe, nowEpoch)
	local rawID = recipe and (readableTradeVal(recipe.spellID) and recipe.spellID or (readableTradeVal(recipe.s) and recipe.s)) or nil
	local spellID = rawID and tonumber(rawID) or nil
	if not spellID or spellID <= 0 then return 0, "none" end
	local now = readableTradeVal(nowEpoch) and tonumber(nowEpoch) or (time and time()) or 0
	local isKnown = ns.IsRecipeKnown and ns.IsRecipeKnown(recipe, { currentCharOnly = true }) or false
	local grp = ns.GetRecipeCooldownGroup(recipe)

	local liveRem, liveValid = probeLiveSpellCooldown(spellID)
	if liveValid and liveRem > 1.5 then
		local cds, cdGroups = ensureActiveCharCooldowns()
		local exp = now + math.ceil(liveRem)
		if cds then cds[spellID] = exp end
		if grp == "alchemy_transmute" then
			rebuildSharedTransmuteCooldownGroup(ns.activeChar, now)
		elseif grp and cdGroups then
			cdGroups[grp] = math.max(tonumber(cdGroups[grp]) or 0, exp)
		end
		return liveRem, "live"
	end

	-- Tool-activated cooldowns (e.g. Salt Shaker 15846 -> Refined Deeprock Salt 19566).
	local toolID = readableTradeVal(recipe.toolItemID) and tonumber(recipe.toolItemID) or nil
	if toolID and toolID > 0 then
		local itemRem = probeLiveItemCooldown(toolID)
		if itemRem and itemRem > 1.5 then
			local cds = ensureActiveCharCooldowns()
			if cds then cds[spellID] = now + math.ceil(itemRem) end
			return itemRem, "live"
		end
	end

	-- Shared Alchemy Transmute fallback: probe learned sibling transmutes before concluding ready/expired.
	local siblingConfirmedReady = false
	if grp == "alchemy_transmute" then
		for _, sibID in ipairs(SHARED_TRANSMUTE_LIST) do
			if sibID ~= spellID and isSiblingTransmuteKnown(sibID) then
				local sibRem, sibValid = probeLiveSpellCooldown(sibID)
				if sibValid then
					if sibRem > 1.5 then
						local cds = ensureActiveCharCooldowns()
						local exp = now + math.ceil(sibRem)
						if cds then cds[sibID] = exp end
						rebuildSharedTransmuteCooldownGroup(ns.activeChar, now)
						return sibRem, "shared_live"
					elseif sibRem == 0 then
						siblingConfirmedReady = true
					end
				end
			end
		end
	end

	local directConfirmedReady = (liveValid and liveRem == 0 and isKnown) or false
	if directConfirmedReady or siblingConfirmedReady then
		local cds, cdGroups = ensureActiveCharCooldowns()
		if directConfirmedReady and cds then cds[spellID] = nil end
		if grp then
			if cdGroups then cdGroups[grp] = nil end
			if grp == "alchemy_transmute" and cds then
				for _, sibID in ipairs(SHARED_TRANSMUTE_LIST) do
					cds[sibID] = nil
				end
				rebuildSharedTransmuteCooldownGroup(ns.activeChar, now)
			end
		end
		return 0, directConfirmedReady and "live" or "shared_live"
	end

	local rem = getSavedCharRecipeCooldownRem(ns.activeChar, spellID, grp, now)
	if rem > 0 then
		local ch = ns.activeChar
		local cds = ch and type(ch.cooldowns) == "table" and ch.cooldowns or nil
		local directExp = cds and readableTradeVal(cds[spellID]) and tonumber(cds[spellID]) or nil
		if directExp and directExp > now then
			return rem, "saved"
		end
		return rem, "shared_saved"
	end

	return 0, isKnown and "ready" or "unknown"
end

function ns.GetPlayerRecipeCooldownRemaining(recipe, nowEpoch)
	if not ns.IsAllCharsCraftableActive() then
		return computeActiveCharCooldownRemaining(recipe, nowEpoch)
	end
	local rawID = recipe and (readableTradeVal(recipe.spellID) and recipe.spellID or (readableTradeVal(recipe.s) and recipe.s)) or nil
	local spellID = rawID and tonumber(rawID) or nil
	if not spellID or spellID <= 0 then return 0, "none" end
	local info = ns.GetRecipeKnownInfo(recipe)
	if not info or not info.known then
		return computeActiveCharCooldownRemaining(recipe, nowEpoch)
	end
	local now = readableTradeVal(nowEpoch) and tonumber(nowEpoch) or (time and time()) or 0
	local grp = ns.GetRecipeCooldownGroup(recipe)
	local minRem, minSrc
	if info.knownOnActive then
		local activeRem, activeSrc = computeActiveCharCooldownRemaining(recipe, nowEpoch)
		if activeRem <= 0 then return 0, activeSrc end
		minRem, minSrc = activeRem, activeSrc
	end
	local activeCh = ns.activeChar
	for _, ch in ipairs(ns.GetEconomyCharacters()) do
		if ch ~= activeCh and checkRecipeKnownOnChar(recipe, ch, ns.GetCharProfessions(ch), false) then
			local rem = getSavedCharRecipeCooldownRem(ch, spellID, grp, now)
			if rem <= 0 then
				return 0, "alt_ready"
			elseif not minRem or rem < minRem then
				minRem, minSrc = rem, "saved"
			end
		end
	end
	return minRem or 0, minSrc or "ready"
end

function ns.GetRecipeCooldownInfo(recipe, nowEpoch)
	local baseCD = ns.GetRecipeBaseCooldown(recipe)
	if not baseCD then return nil end
	local nominalSec, winLbl = ns.NormalizeCooldownWindow(baseCD)
	local grp, grpLabel = ns.GetRecipeCooldownGroup(recipe)
	local isKnown = ns.IsRecipeKnown and ns.IsRecipeKnown(recipe) or false
	local rem = ns.GetPlayerRecipeCooldownRemaining(recipe, nowEpoch)
	local onCD = (rem and rem > 0) and true or false
	local available, availableLabel
	if onCD then
		available = false
		availableLabel = "No"
	elseif isKnown then
		available = true
		availableLabel = "Yes"
	else
		available = nil
		availableLabel = nil
	end
	local rname = recipe.name or recipe.n
	return {
		hasCooldown = true,
		isTransmute = (type(rname) == "string" and rname:find("^Transmute:") ~= nil) or false,
		sharedGroup = grp,
		sharedLabel = grpLabel,
		isShared = (grp ~= nil),
		baseSeconds = baseCD,
		nominalSeconds = nominalSec,
		windowLabel = winLbl,
		rateLabel = "1 / " .. winLbl,
		maxPerDay = 86400 / nominalSec,
		maxBatch = 1,
		known = isKnown,
		onCooldown = onCD,
		available = available,
		availableLabel = availableLabel,
		remainingSeconds = rem,
		remainingLabel = onCD and ns.FormatCooldownRemaining(rem) or nil,
	}
end

---------------------------------------------------------------------------------------------------
-- Craft Ability + How-to-Get Engine, Market Demand / Heat Engine & Best-in-Class Evaluator (v2.3.0)

ns.RECIPE_SOURCE_OPTIONS = {
	{ key = "all",        label = "All Sources",                 short = "All" },
	{ key = "merchant",   label = "Merchant Recipes (Favor)",    short = "Merchant" },
	{ key = "vendor",     label = "Vendor Recipes (NPC)",        short = "Vendor" },
	{ key = "trainer",    label = "Trainer Recipes",             short = "Trainer" },
	{ key = "ah",         label = "AH / World Drop Recipes",     short = "AH Drops" },
	{ key = "quest_drop", label = "Quest & BoP Drop Recipes",    short = "Quest/BoP" },
	{ key = "gather",     label = "Gathering Nodes",             short = "Gathering" },
}

local NON_ALL_RECIPE_SOURCE_KEYS = { "merchant", "vendor", "trainer", "ah", "quest_drop", "gather" }

function ns.GetRecipeSourceBucket(recipe)
	if not recipe then return "trainer" end
	local acq = recipe.acqType
	if recipe.source == "gather" or acq == "gather" then
		return "gather"
	elseif recipe.source == "camp" or acq == "camp" then
		return "merchant"
	elseif acq == "vendor" or acq == "vendor_ah" then
		return "vendor"
	elseif acq == "ah" then
		return "ah"
	elseif acq == "quest" or acq == "drop_bop" then
		return "quest_drop"
	end
	return "trainer"
end

function ns.HasActiveRecipeSourceFilter(selectedMap)
	if type(selectedMap) ~= "table" or selectedMap.all == true then
		return false
	end
	local count = 0
	for _, k in ipairs(NON_ALL_RECIPE_SOURCE_KEYS) do
		if selectedMap[k] == true then
			count = count + 1
		end
	end
	return count > 0 and count < #NON_ALL_RECIPE_SOURCE_KEYS
end

function ns.MatchesRecipeSourceFilter(recipe, selectedMap, legacyMerchantOnly, legacySourceFilter)
	if ns.HasActiveRecipeSourceFilter(selectedMap) then
		return selectedMap[ns.GetRecipeSourceBucket(recipe)] == true
	end
	if legacyMerchantOnly == true or legacySourceFilter == "camp" then
		return ns.GetRecipeSourceBucket(recipe) == "merchant"
	elseif legacySourceFilter == "gather" then
		return ns.GetRecipeSourceBucket(recipe) == "gather"
	elseif legacySourceFilter == "classic" then
		local b = ns.GetRecipeSourceBucket(recipe)
		return b ~= "merchant" and b ~= "gather"
	end
	return true
end

function ns.FormatRecipeSourcesLabel(selectedMap)
	if not ns.HasActiveRecipeSourceFilter(selectedMap) then
		return "Sources: All"
	end
	local shorts = {}
	for _, opt in ipairs(ns.RECIPE_SOURCE_OPTIONS) do
		if opt.key ~= "all" and selectedMap[opt.key] == true then
			shorts[#shorts + 1] = opt.short
		end
	end
	if #shorts == 0 then
		return "Sources: All"
	elseif #shorts == 1 then
		return "Sources: " .. shorts[1]
	elseif #shorts == 2 then
		return "Src: " .. shorts[1] .. " + " .. shorts[2]
	end
	return string.format("Sources: %d Selected", #shorts)
end

ns.CRAFTABLE_FILTERS = {
	{ key = "all",     label = "Craft: All" },
	{ key = "known",   label = "Craft: Known Recipes" },
	{ key = "yes",     label = "Craft: Able Now" },
	{ key = "no",      label = "Craft: Need Recipe/Skill" },
	{ key = "trainer", label = "Get: From Trainer" },
	{ key = "vendor",  label = "Get: Recipe Vendor" },
	{ key = "ah",      label = "Get: Auction House" },
}

ns.DEMAND_FILTERS = {
	{ key = "all",       label = "Demand: All" },
	{ key = "monopoly",  label = "Demand: Monopoly" },
	{ key = "high_turn", label = "Demand: High Turn (>=1x)" },
	{ key = "hot",       label = "Demand: Hot/Fav (>=0.15x)" },
	{ key = "unlisted",  label = "Demand: Unlisted (0)" },
	{ key = "listed",    label = "Demand: Listed (Yes)" },
	{ key = "cold",      label = "Demand: Cold (<0.05x)" },
}

function ns.GetRecipeVendorBuyPrice(recipeItemID, staticCopper, barteringRankOverride)
	if ns.GetVendorBuyPrice then
		return ns.GetVendorBuyPrice(recipeItemID, staticCopper, true, barteringRankOverride)
	end
	if type(staticCopper) == "number" and staticCopper > 0 then
		return math.floor(staticCopper + 0.5), false
	end
	return nil, false
end

function ns.GetRecipeWowheadURL(obj)
	if not obj or obj.acqType == "gather" or obj.source == "gather" then
		return nil, nil, nil
	end
	local recipeItemID = tonumber(obj.recipeItemID)
	if recipeItemID and recipeItemID > 0 then
		local rLabel = (obj.recipeName and obj.recipeName ~= "") and obj.recipeName or obj.name or obj.requiredItemName or ("Item #" .. tostring(recipeItemID))
		return "https://www.wowhead.com/forever/item=" .. tostring(recipeItemID), rLabel, "item"
	end
	local spellID = tonumber(obj.spellID)
	if spellID and spellID > 0 then
		local sLabel = (obj.recipeName and obj.recipeName ~= "") and obj.recipeName or obj.name or obj.requiredItemName or ("Spell #" .. tostring(spellID))
		return "https://www.wowhead.com/forever/spell=" .. tostring(spellID), sLabel, "spell"
	end
	local fallbackID = tonumber(obj.outputItemID) or tonumber(obj.requiredItemID) or tonumber(obj.itemID)
	if fallbackID and fallbackID > 0 then
		local fLabel = obj.name or obj.requiredItemName or ("Item #" .. tostring(fallbackID))
		return "https://www.wowhead.com/forever/item=" .. tostring(fallbackID), fLabel, "item"
	end
	return nil, nil, nil
end

function ns.EvaluateCraftAbility(obj, profMap, repState)
	if not obj then
		return {
			ableToCraft = false,
			sortScore = 0,
			acqType = "trainer",
			howCategory = "trainer",
			howShort = "Trainer",
			howDetail = "Profession Trainer",
			cellText = "|cff777777—|r",
		}
	end
	local profKey = obj.prof or "alchemy"
	local reqSkill = tonumber(obj.skill) or 1
	local _, reqRep, meetsRep, repFactionName = ns.GetRecipeStanding(obj, repState)
	local repFactionID = (reqRep > 0 and ((readable(obj.repFactionID) and tonumber(obj.repFactionID)) or (readable(obj.repFacID) and tonumber(obj.repFacID)))) or nil
	local favorCost = tonumber(obj.favorCost) or 0
	local pObj = ns.PROF_BY_KEY[profKey]
	local profFull = pObj and pObj.full or profKey
	local profAbbr = pObj and pObj.label or profKey

	local playerSkill = profMap and profMap[profKey]
	local hasProf = (playerSkill ~= nil)
	local anyProfLearned = profMap and (next(profMap) ~= nil) or false
	local meetsSkill = hasProf and (playerSkill >= reqSkill) or false
	local knownInfo = ns.GetRecipeKnownInfo and ns.GetRecipeKnownInfo(obj) or nil
	local known = knownInfo and knownInfo.known or ns.IsRecipeKnown(obj)
	local altTag = formatAltKnownTag(knownInfo)

	local acqType = obj.acqType or (obj.source == "camp" and "camp" or (obj.source == "gather" and "gather" or "trainer"))
	local playerFaction = (repState and repState.playerFaction) or (UnitFactionGroup and UnitFactionGroup("player")) or "Horde"
	local myVendor = (playerFaction == "Alliance") and obj.vendorA or obj.vendorH
	local oppVendor = (playerFaction == "Alliance") and obj.vendorH or obj.vendorA
	local recipeItemID = (obj.recipeItemID and obj.recipeItemID > 0) and obj.recipeItemID or nil

	local howShort, howCategory, howDetail
	local vendorCopperCost, vendorFavorCost, vendorCostText
	if acqType == "gather" then
		howShort = "Gather"
		howCategory = "gather"
		howDetail = string.format("Gathered via %s (%d)", profFull, reqSkill)
	elseif acqType == "camp" then
		local repName = (reqRep > 0 and ns.STANDING_NAMES[reqRep]) or "Neutral"
		vendorFavorCost = (favorCost and favorCost > 0) and favorCost or nil
		vendorCostText = vendorFavorCost and (tostring(vendorFavorCost) .. " Favor") or nil
		howShort = vendorCostText and ("Vendor (" .. vendorCostText .. ")") or "Camp Vendor"
		howCategory = "vendor"
		howDetail = vendorFavorCost
			and string.format("Merchant Camp Vendor (%s · %d Favor Tokens)", repName, vendorFavorCost)
			or string.format("Merchant Camp Vendor (%s)", repName)
	elseif acqType == "vendor" or acqType == "vendor_ah" then
		if not (myVendor and myVendor ~= "") and (oppVendor and oppVendor ~= "") and acqType == "vendor_ah" then
			howShort = "Auction House"
			howCategory = "ah"
			howDetail = "Buy on Auction House (Opposite-faction vendor: " .. (obj.vendorAll or oppVendor) .. ")"
		else
			vendorCopperCost = ns.GetRecipeVendorBuyPrice(recipeItemID, obj.recipeVendorPrice)
			vendorCostText = vendorCopperCost and ns.FormatMoneyCompact(vendorCopperCost) or nil
			howCategory = "vendor"
			if acqType == "vendor_ah" then
				howShort = vendorCostText and ("Vendor " .. vendorCostText .. " / AH") or "Vendor / AH"
			else
				howShort = vendorCostText and ("Vendor (" .. vendorCostText .. ")") or "Recipe Vendor"
			end
			local vName = (myVendor and myVendor ~= "" and myVendor)
				or (obj.vendorAll and obj.vendorAll ~= "" and obj.vendorAll)
				or oppVendor
			local costPart = vendorCostText and (" — Cost: " .. vendorCostText) or ""
			local repPart = (reqRep > 0) and (" · Requires " .. (repFactionName and (repFactionName .. " ") or "") .. (ns.STANDING_NAMES[reqRep] or "")) or ""
			if vName and vName ~= "" then
				howDetail = "Recipe Vendor: " .. vName .. costPart .. repPart .. ((acqType == "vendor_ah") and " (also sold on AH)" or "")
			else
				howDetail = "NPC Recipe Vendor" .. costPart .. repPart .. ((acqType == "vendor_ah") and " or Auction House" or "")
			end
		end
	elseif acqType == "ah" then
		howShort = "Auction House"
		howCategory = "ah"
		local rName = obj.recipeName
		howDetail = (rName and rName ~= "" and rName ~= obj.name and rName ~= obj.requiredItemName)
			and ("Buy on Auction House: " .. rName)
			or "Buy Recipe on Auction House (World Drop)"
	elseif acqType == "quest" then
		howShort = "Quest"
		howCategory = "quest"
		local qNote = (myVendor and myVendor ~= "" and myVendor) or obj.vendorAll
		howDetail = (qNote and qNote ~= "") and qNote
			or ((obj.recipeName and obj.recipeName ~= "") and ("Quest Reward: " .. obj.recipeName) or "Quest / Special NPC")
		if reqRep > 0 then
			howDetail = howDetail .. " · Requires " .. (repFactionName and (repFactionName .. " ") or "") .. (ns.STANDING_NAMES[reqRep] or "")
		end
	elseif acqType == "drop_bop" then
		howShort = "Drop (BoP)"
		howCategory = "quest"
		howDetail = (obj.recipeName and obj.recipeName ~= "" and obj.recipeName ~= obj.name)
			and ("World / Dungeon BoP Drop: " .. obj.recipeName)
			or "World / Dungeon Drop (Bind on Pickup)"
		if reqRep > 0 then
			howDetail = howDetail .. " · Requires " .. (repFactionName and (repFactionName .. " ") or "") .. (ns.STANDING_NAMES[reqRep] or "")
		end
	elseif acqType == "start" then
		howShort = "Starter"
		howCategory = "trainer"
		howDetail = obj.anyChar and "Right-click item in bags to combine"
			or string.format("Starter %s Skill (Learned at Skill 1)", profFull)
	else
		howShort = "Trainer"
		howCategory = "trainer"
		howDetail = string.format("%s Trainer (Requires Skill %d)", profFull, reqSkill)
	end

	local recipeAHPrice, recipeAHSource, recipeAHStock = nil, nil, nil
	if recipeItemID and acqType ~= "camp" then
		recipeAHPrice, recipeAHSource = ns.GetItemMarketPrice(recipeItemID)
		recipeAHStock = ns.GetNumListed(recipeItemID)
	end

	local ableToCraft = false
	local cellText, reasonText, sortScore
	if acqType == "gather" then
		if hasProf and meetsSkill then
			ableToCraft = true
			sortScore = 100
			cellText = "|cff33ff33Yes (Gather)|r"
			reasonText = string.format("Able to gather now (%s %d/%d).", profFull, playerSkill or reqSkill, reqSkill)
		else
			ableToCraft = false
			sortScore = hasProf and 50 or 10
			cellText = string.format("|cffaaaaaaNo · %s %d|r", profAbbr, reqSkill)
			reasonText = hasProf
				and string.format("Need %s skill %d (currently %d).", profFull, reqSkill, playerSkill or 0)
				or string.format("Requires %s (%d).", profFull, reqSkill)
		end
	elseif known then
		ableToCraft = true
		sortScore = 100
		if altTag then
			cellText = "|cff33ff33Yes (" .. altTag .. ")|r"
			reasonText = "Able to Craft on alt: " .. table.concat(knownInfo.altNames, ", ") .. "."
		else
			cellText = "|cff33ff33Yes|r"
			reasonText = "Able to Craft — recipe learned on this character."
		end
	elseif hasProf and meetsSkill and meetsRep then
		ableToCraft = false
		if howCategory == "trainer" then
			sortScore = 85
			cellText = "|cffffd244No · Trainer|r"
			reasonText = string.format("Skill %d met — learn from %s Trainer (or open profession window once to sync).", reqSkill, profFull)
		elseif howCategory == "vendor" then
			sortScore = 75
			cellText = (acqType == "camp")
				and ("|cff44ddaaNo · " .. howShort .. "|r")
				or ("|cff66ccffNo · " .. howShort .. "|r")
			reasonText = "Skill met — buy recipe from " .. howDetail
		elseif howCategory == "ah" then
			sortScore = 65
			cellText = "|cffff9944No · Buy AH|r"
			reasonText = "Skill met — " .. howDetail
		else
			sortScore = 60
			cellText = "|cffcc88ffNo · Quest|r"
			reasonText = "Skill met — obtain via " .. howDetail
		end
	elseif hasProf and not meetsSkill then
		ableToCraft = false
		sortScore = 40
		local repName = ns.STANDING_NAMES[reqRep] or ("Rep " .. tostring(reqRep))
		if howCategory == "vendor" then
			if vendorCostText then
				cellText = not meetsRep and string.format("|cffff7744No · Vendor %s · %s (%d)|r", vendorCostText, repName, reqSkill)
					or string.format("|cffff7744No · Vendor %s (%d)|r", vendorCostText, reqSkill)
			else
				cellText = not meetsRep and string.format("|cffff7744No · Vendor · %s (%d)|r", repName, reqSkill)
					or string.format("|cffff7744No · Vendor (%d)|r", reqSkill)
			end
		else
			local tag = (howCategory == "trainer") and "Trainer" or ((howCategory == "ah") and "AH" or "Quest")
			cellText = not meetsRep and string.format("|cffff7744No · %s · %s (%d)|r", tag, repName, reqSkill)
				or string.format("|cffff7744No · %s (%d)|r", tag, reqSkill)
		end
		reasonText = string.format("Need %s %d (you have %d) · Get from: %s", profFull, reqSkill, playerSkill or 0, howDetail)
	elseif hasProf and not meetsRep then
		ableToCraft = false
		sortScore = 35
		local repName = ns.STANDING_NAMES[reqRep] or ("Rep " .. tostring(reqRep))
		local reqLabel = (repFactionName and (repFactionName .. " ") or "") .. repName
		if vendorCostText then
			cellText = string.format("|cffff6666No · %s (%s)|r", repName, vendorCostText)
		else
			cellText = "|cffff6666No · " .. repName .. "|r"
		end
		reasonText = string.format("Need %s reputation · Get from: %s", reqLabel, howDetail)
	elseif anyProfLearned and not hasProf then
		ableToCraft = false
		sortScore = 15
		local repSuffix = not meetsRep and (" · " .. (ns.STANDING_NAMES[reqRep] or ("Rep " .. tostring(reqRep)))) or ""
		if howCategory == "vendor" then
			cellText = "|cff999999No · " .. howShort .. repSuffix .. "|r"
		else
			local tag = (howCategory == "trainer") and "Trainer" or ((howCategory == "ah") and "Auction House" or "Quest")
			cellText = string.format("|cff999999No · %s%s|r", tag, repSuffix)
		end
		reasonText = string.format("Character does not have %s (%d) · Recipe source: %s", profFull, reqSkill, howDetail)
	else
		-- No professions detected on character yet: still display exact recipe source & vendor cost cleanly
		ableToCraft = false
		sortScore = 25
		local srcCol = (howCategory == "trainer" and "|cffffd244")
			or (acqType == "camp" and "|cff44ddaa")
			or (howCategory == "vendor" and "|cff66ccff")
			or (howCategory == "ah" and "|cffff9944")
			or "|cffcc88ff"
		local repSuffix = not meetsRep and (" · " .. (ns.STANDING_NAMES[reqRep] or ("Rep " .. tostring(reqRep)))) or ""
		cellText = srcCol .. "No · " .. howShort .. repSuffix .. "|r"
		reasonText = string.format("Requires %s (%d) · Get from: %s", profFull, reqSkill, howDetail)
	end

	local wowheadURL, wowheadLabel, wowheadKind = ns.GetRecipeWowheadURL(obj)

	return {
		ableToCraft = ableToCraft,
		known = known,
		knownOnActive = knownInfo and knownInfo.knownOnActive or false,
		knownAltNames = knownInfo and knownInfo.altNames or nil,
		hasProf = hasProf,
		meetsSkill = meetsSkill,
		meetsRep = meetsRep,
		reqRep = reqRep,
		repFactionID = repFactionID,
		repFactionName = repFactionName,
		playerSkill = playerSkill,
		reqSkill = reqSkill,
		profKey = profKey,
		profFull = profFull,
		acqType = acqType,
		howCategory = howCategory,
		howShort = howShort,
		howDetail = howDetail,
		vendorCopperCost = vendorCopperCost,
		vendorFavorCost = vendorFavorCost,
		vendorCostText = vendorCostText,
		recipeItemID = recipeItemID,
		spellID = tonumber(obj.spellID),
		recipeName = obj.recipeName,
		recipeAHPrice = recipeAHPrice,
		recipeAHSource = recipeAHSource,
		recipeAHStock = recipeAHStock,
		wowheadURL = wowheadURL,
		wowheadLabel = wowheadLabel,
		wowheadKind = wowheadKind,
		cellText = cellText,
		reasonText = reasonText,
		sortScore = sortScore,
	}
end

function ns.MatchesCraftableFilter(craftAbility, filterKey)
	filterKey = filterKey or "all"
	if filterKey == "all" then return true end
	if not craftAbility then return false end
	if filterKey == "known" then
		return craftAbility.known == true or (craftAbility.acqType == "gather" and craftAbility.ableToCraft == true)
	elseif filterKey == "yes" then
		return craftAbility.ableToCraft == true
	elseif filterKey == "no" then
		return craftAbility.ableToCraft ~= true
	elseif filterKey == "trainer" then
		return craftAbility.howCategory == "trainer"
	elseif filterKey == "vendor" then
		return craftAbility.howCategory == "vendor"
	elseif filterKey == "ah" then
		return craftAbility.howCategory == "ah" or craftAbility.acqType == "vendor_ah"
	end
	return true
end

-- Evaluates Market Demand, Sales Ratio (Sales/Day / Listed), Listed Yes/No, Monopoly & Hot/Cold status
function ns.EvaluateMarketDemand(listed, dailySold, sellable)
	if sellable == false then
		return {
			sellable = false,
			isListed = false,
			isUnlisted = false,
			listedYesNo = "|cff777777BoP|r",
			listedSort = -1,
			salesRatio = nil,
			daysOfSupply = nil,
			tierKey = "bop",
			isHot = false,
			isMonopoly = false,
			heatBadge = "|cff777777Soulbound|r",
			heatShort = "|cff777777BoP|r",
			ratioText = "|cff777777—|r",
			stateLabel = "|cff777777Bind on Pickup / Not Tradeable|r",
			demandScore = -100,
		}
	end

	local hasSales = (type(dailySold) == "number" and dailySold > 0)
	local hasListed = (type(listed) == "number")
	local isListed = hasListed and (listed > 0) or nil
	local listedYesNo, listedSort
	if hasListed then
		listedSort = listed
		if listed == 0 then
			listedYesNo = hasSales and "|cffffffffUNLISTED (0) *|r" or "|cffffffffUNLISTED (0)|r"
		elseif listed == 1 and hasSales and dailySold >= 0.25 then
			listedYesNo = "|cffffb833Yes (1) *|r"
		else
			listedYesNo = "|cff66ee66Yes (" .. tostring(listed) .. ")|r"
		end
	else
		listedSort = nil
		listedYesNo = "|cff777777—|r"
	end

	-- 1. Empty-Market Monopoly (0 listed on AH while buyers purchase daily!)
	if hasListed and listed == 0 and hasSales then
		return {
			sellable = true,
			isListed = false,
			isUnlisted = true,
			listedYesNo = listedYesNo,
			listedSort = 0,
			salesRatio = 999,
			daysOfSupply = 0,
			tierKey = "monopoly",
			isHot = true,
			isMonopoly = true,
			heatBadge = "|cffffffffUNLISTED *|r",
			heatShort = "|cffffffffUNLISTED|r",
			ratioText = "|cffffffffUNLISTED (0)|r",
			stateLabel = "|cffffffffUNLISTED — Empty AH (Set Market Price!)|r",
			demandScore = 10000 + dailySold,
		}
	end

	-- 2. Sole-Seller Monopoly (only 1 unit listed on AH with active daily sales!)
	if hasListed and listed == 1 and hasSales and dailySold >= 0.25 then
		local ratio = dailySold / 1
		return {
			sellable = true,
			isListed = true,
			listedYesNo = listedYesNo,
			listedSort = 1,
			salesRatio = ratio,
			daysOfSupply = 1 / dailySold,
			tierKey = "monopoly",
			isHot = true,
			isMonopoly = true,
			heatBadge = "|cffffb833* Monopoly (1)|r",
			heatShort = "|cffffb833* Sole (1)|r",
			ratioText = string.format("|cffffb833%.2fx|r", ratio),
			stateLabel = string.format("|cffffb833Monopoly — Only 1 Listed (%.2fx/day)|r", ratio),
			demandScore = 9000 + ratio,
		}
	end

	-- 3. Both Listed (>0) and DailySold (>=0) known -> exact Sales Ratio (dailySold / listed)
	if hasListed and listed > 0 and type(dailySold) == "number" then
		local ratio = dailySold / listed
		local days = (dailySold > 0) and (listed / dailySold) or 9999
		local fmtR = ratio >= 10 and string.format("%.1fx", ratio) or string.format("%.2fx", ratio)
		if ratio >= 1.0 then
			return {
				sellable = true,
				isListed = true,
				listedYesNo = listedYesNo,
				listedSort = listed,
				salesRatio = ratio,
				daysOfSupply = days,
				tierKey = "high_turn",
				isHot = true,
				isMonopoly = false,
				heatBadge = "|cffff5533Hot " .. fmtR .. "|r",
				heatShort = "|cffff5533Hot (High Turn)|r",
				ratioText = "|cffff6644" .. fmtR .. "|r",
				stateLabel = string.format("|cffff6644Hot — High Turnaround (%.1fd supply)|r", days),
				demandScore = 5000 + ratio,
			}
		elseif ratio >= 0.35 then
			return {
				sellable = true,
				isListed = true,
				listedYesNo = listedYesNo,
				listedSort = listed,
				salesRatio = ratio,
				daysOfSupply = days,
				tierKey = "favorable",
				isHot = true,
				isMonopoly = false,
				heatBadge = "|cffff9933Hot " .. fmtR .. "|r",
				heatShort = "|cffff9933Hot|r",
				ratioText = "|cffffaa44" .. fmtR .. "|r",
				stateLabel = string.format("|cffffaa44Hot Demand (%.1fd supply)|r", days),
				demandScore = 3000 + ratio * 100,
			}
		elseif ratio >= 0.15 then
			-- Includes 200 sales/day / 1,000 listed = 0.20x Favorable Ratio!
			return {
				sellable = true,
				isListed = true,
				listedYesNo = listedYesNo,
				listedSort = listed,
				salesRatio = ratio,
				daysOfSupply = days,
				tierKey = "favorable",
				isHot = true,
				isMonopoly = false,
				heatBadge = "|cff44ee66Fav " .. fmtR .. "|r",
				heatShort = "|cff44ee66Favorable|r",
				ratioText = "|cff66ee66" .. fmtR .. "|r",
				stateLabel = string.format("|cff44ee66Favorable Ratio (%.1fd supply)|r", days),
				demandScore = 2000 + ratio * 100,
			}
		elseif ratio >= 0.05 then
			return {
				sellable = true,
				isListed = true,
				listedYesNo = listedYesNo,
				listedSort = listed,
				salesRatio = ratio,
				daysOfSupply = days,
				tierKey = "steady",
				isHot = false,
				isMonopoly = false,
				heatBadge = "|cffeecc55Steady " .. fmtR .. "|r",
				heatShort = "|cffeecc55Steady|r",
				ratioText = "|cffeecc55" .. fmtR .. "|r",
				stateLabel = string.format("|cffeecc55Steady Turnover (%.0fd supply)|r", days),
				demandScore = 500 + ratio * 100,
			}
		else
			return {
				sellable = true,
				isListed = true,
				listedYesNo = listedYesNo,
				listedSort = listed,
				salesRatio = ratio,
				daysOfSupply = days,
				tierKey = "cold",
				isHot = false,
				isMonopoly = false,
				heatBadge = "|cff66aaffCold " .. fmtR .. "|r",
				heatShort = "|cff66aaffCold|r",
				ratioText = "|cff66aaff" .. fmtR .. "|r",
				stateLabel = dailySold > 0
					and string.format("|cff66aaffCold — Oversupplied (%.0fd supply)|r", math.min(999, days))
					or "|cff66aaffCold — Low Demand|r",
				demandScore = ratio * 100,
			}
		end
	end

	-- 4. Unlisted (0 listed) with 0 / unknown regional sales
	if hasListed and listed == 0 then
		return {
			sellable = true,
			isListed = false,
			isUnlisted = true,
			listedYesNo = listedYesNo,
			listedSort = 0,
			salesRatio = nil,
			daysOfSupply = 0,
			tierKey = "unlisted",
			isHot = false,
			isMonopoly = false,
			heatBadge = "|cffffffffUNLISTED|r",
			heatShort = "|cffffffffUNLISTED|r",
			ratioText = "|cffffffffUNLISTED (0)|r",
			stateLabel = "|cffffffffUNLISTED — No AH Listings (Set Market Price)|r",
			demandScore = 1500,
		}
	end

	-- 5. Only Snapshot dailySold known (server listings N/A)
	if hasSales then
		local hotReg = dailySold >= 15
		return {
			sellable = true,
			isListed = nil,
			listedYesNo = listedYesNo,
			listedSort = nil,
			salesRatio = nil,
			daysOfSupply = nil,
			tierKey = hotReg and "favorable" or (dailySold >= 2 and "steady" or "cold"),
			isHot = hotReg,
			isMonopoly = false,
			heatBadge = hotReg and "|cff44ee66Active|r" or (dailySold >= 2 and "|cffeecc55Steady|r" or "|cff66aaffCold|r"),
			heatShort = hotReg and "|cff44ee66Active|r" or (dailySold >= 2 and "|cffeecc55Steady|r" or "|cff66aaffCold|r"),
			ratioText = "|cff777777—|r",
			stateLabel = string.format("|cffbbbbbbSnapshot %.1f sold/day (scan AH for server stock)|r", dailySold),
			demandScore = dailySold,
		}
	end

	return {
		sellable = true,
		isListed = isListed,
		listedYesNo = listedYesNo,
		listedSort = listedSort,
		salesRatio = nil,
		daysOfSupply = nil,
		tierKey = "unknown",
		isHot = false,
		isMonopoly = false,
		heatBadge = "|cff777777—|r",
		heatShort = "|cff777777—|r",
		ratioText = "|cff777777—|r",
		stateLabel = "|cff777777No market data — click Refresh AH|r",
		demandScore = -1,
	}
end

function ns.MatchesDemandFilter(demand, filterKey)
	filterKey = filterKey or "all"
	if filterKey == "all" then return true end
	if not demand or demand.sellable == false then return false end
	if filterKey == "monopoly" then
		return demand.tierKey == "monopoly"
	elseif filterKey == "high_turn" then
		return demand.tierKey == "monopoly" or demand.tierKey == "high_turn"
	elseif filterKey == "hot" then
		return demand.isHot == true
	elseif filterKey == "unlisted" then
		return demand.isListed == false
	elseif filterKey == "listed" then
		return demand.isListed == true
	elseif filterKey == "cold" then
		return demand.tierKey == "cold"
	end
	return true
end

function ns.EvaluateBestInClass(recipe)
	if not recipe or not recipe.bisClass then
		return {
			hasEval = false,
			isBiS = false,
			cellText = "|cff555555—|r",
			sortScore = 0,
		}
	end
	local isBiS = (recipe.isBiS == true)
	local rank = tonumber(recipe.bisRank) or (isBiS and 1 or 2)
	local total = tonumber(recipe.bisTotal) or 1
	return {
		hasEval = true,
		isBiS = isBiS,
		classLabel = recipe.bisClass,
		valText = recipe.bisVal,
		rank = rank,
		total = total,
		bestName = recipe.bisBestName,
		bestVal = recipe.bisBestVal,
		effectText = recipe.effectText,
		cellText = isBiS and "|cffffd200Best|r" or string.format("|cff999999#%d/%d|r", rank, total),
		sortScore = isBiS and (10000 + total * 10 + (recipe.skill or 0) * 0.01) or (1000 - rank * 10 + (recipe.skill or 0) * 0.01),
	}
end

function ns.GetFavorBalance()
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, ns.FAVOR_CURRENCY_ID)
		if ok and type(info) == "table" and type(info.quantity) == "number" then
			return info.quantity, info.iconFileID
		end
	end
	if GetCurrencyInfo then
		local ok, _, amount, icon = pcall(GetCurrencyInfo, ns.FAVOR_CURRENCY_ID)
		if ok and type(amount) == "number" then
			return amount, icon
		end
	end
	return nil, nil
end

local CATALOG_REP_FACTIONS = {
	{ id = 59, name = "Thorium Brotherhood" },
	{ id = 270, name = "Zandalar Tribe" },
	{ id = 529, name = "Argent Dawn" },
	{ id = 576, name = "Timbermaw Hold" },
	{ id = 609, name = "Cenarion Circle" },
	{ id = 2740, name = "Kirin Tor" },
	{ id = 2758, name = "Nightclaw Druids" },
	{ id = 2787, name = "Earthen Ring" },
}

local function scanLiveFactionMap()
	local byID, byName = {}, {}
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		local okN, numF = pcall(C_Reputation.GetNumFactions)
		if okN and readable(numF) and type(numF) == "number" then
			for i = 1, numF do
				local okD, data = pcall(C_Reputation.GetFactionDataByIndex, i)
				if okD and readable(data) and type(data) == "table" and readable(data.reaction) then
					local s = tonumber(data.reaction)
					if s then
						if readable(data.factionID) and tonumber(data.factionID) then
							byID[tonumber(data.factionID)] = s
						end
						if readable(data.name) and type(data.name) == "string" and data.name ~= "" then
							byName[data.name:lower()] = s
						end
					end
				end
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		local okN, numF = pcall(GetNumFactions)
		if okN and readable(numF) and type(numF) == "number" then
			for i = 1, numF do
				local okI, fname, _, sid, _, _, _, _, _, _, _, _, _, _, fid = pcall(GetFactionInfo, i)
				if okI and readable(sid) then
					local s = tonumber(sid)
					if s then
						if readable(fid) and tonumber(fid) then
							byID[tonumber(fid)] = s
						end
						if readable(fname) and type(fname) == "string" and fname ~= "" then
							byName[fname:lower()] = s
						end
					end
				end
			end
		end
	end
	return byID, byName
end

local function lookupLiveFactionStanding(fid, fname, liveByID, liveByName)
	local s
	if fid and C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, data = pcall(C_Reputation.GetFactionDataByID, fid)
		if ok and readable(data) and type(data) == "table" and readable(data.reaction) then
			s = tonumber(data.reaction)
		end
	end
	if not s and fid and GetFactionInfoByID then
		local ok, _, _, sid = pcall(GetFactionInfoByID, fid)
		if ok and readable(sid) then
			s = tonumber(sid)
		end
	end
	if not s and fid and liveByID then s = liveByID[fid] end
	if not s and fname then
		local low = fname:lower()
		if liveByName and liveByName[low] then
			s = liveByName[low]
		elseif not liveByID and not liveByName then
			local byID, byName = scanLiveFactionMap()
			s = (fid and byID[fid]) or byName[low]
		end
	end
	if not s then
		s = (fid == 576 or (fname and fname:lower() == "timbermaw hold")) and 2 or 4
	end
	return s
end

function ns.GetRecipeStanding(obj, repState)
	local reqRep = (type(obj) == "table" and readable(obj.rep) and tonumber(obj.rep)) or 0
	if reqRep <= 0 then
		return nil, 0, true, nil
	end
	local isCamp = (obj.source == "camp" or obj.acqType == "camp")
	local fid = (not isCamp and readable(obj.repFactionID) and tonumber(obj.repFactionID))
		or (not isCamp and readable(obj.repFacID) and tonumber(obj.repFacID))
		or nil
	local fname = (not isCamp and readable(obj.repFaction) and type(obj.repFaction) == "string" and obj.repFaction ~= "" and obj.repFaction)
		or (not isCamp and readable(obj.repFac) and type(obj.repFac) == "string" and obj.repFac ~= "" and obj.repFac)
		or nil
	if isCamp or (not fid and not fname) then
		local s = (type(repState) == "table" and readable(repState.standing) and tonumber(repState.standing)) or 4
		local campName = (type(repState) == "table" and readable(repState.factionName) and type(repState.factionName) == "string" and repState.factionName ~= "" and repState.factionName)
			or "Merchant's Camp"
		return s, reqRep, (s >= reqRep), campName
	end

	local facs = type(repState) == "table" and readable(repState.factions) and type(repState.factions) == "table" and repState.factions or nil
	local s = facs and ((fid and readable(facs[fid]) and tonumber(facs[fid])) or (fname and readable(facs[fname]) and tonumber(facs[fname]))) or nil
	if not s then
		local ec = ns._evalCache
		local ck = fid or fname
		if ec and ck then
			ec.factionStandings = ec.factionStandings or {}
			s = ec.factionStandings[ck]
		end
		if not s then
			s = lookupLiveFactionStanding(fid, fname)
			if ec and ck then ec.factionStandings[ck] = s end
		end
	end
	return s, reqRep, (s >= reqRep), fname
end

function ns.BuildRecipeRepFields(recipe, repState, unlock)
	local rawRep = (readable(recipe) and type(recipe) == "table" and readable(recipe.rep) and tonumber(recipe.rep)) or 0
	if rawRep > 0 then
		local _, effReqRep, meetsRep, repFactionName = ns.GetRecipeStanding(recipe, repState)
		local reqRep = effReqRep or rawRep
		local repLabel = (ns.STANDING_NAMES and ns.STANDING_NAMES[reqRep]) or ("Rep " .. tostring(reqRep))
		local isCamp = (recipe.source == "camp" or recipe.acqType == "camp")
		repFactionName = isCamp and "Merchant" or repFactionName
		local repMet = meetsRep == true
		if unlock and unlock.meetsRep ~= nil then repMet = unlock.meetsRep == true end
		return reqRep, reqRep, repLabel, repFactionName, repMet
	end
	return 0, nil, nil, nil, true
end

-- Returns { factionID, factionName, playerFaction, standing, barMin, barMax, barValue, totalFromNeutral, factions, factionsDigest }
function ns.GetMerchantReputation()
	local ec = ns._evalCache
	if ec and ec.repState then
		return ec.repState
	end
	local playerFaction = UnitFactionGroup and UnitFactionGroup("player") or "Horde"
	local factionID = (playerFaction == "Alliance") and ns.FACTION_ALLIANCE or ns.FACTION_HORDE
	local defaultName = (playerFaction == "Alliance") and "Azeroth Commerce Authority" or "Durotar Supply and Logistics"
	local name, standing, bmin, bmax, bval

	if C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
		if ok and readable(data) and type(data) == "table" and readable(data.reaction) and data.reaction then
			name = readable(data.name) and data.name or nil
			standing = data.reaction
			bmin = readable(data.currentReactionThreshold) and data.currentReactionThreshold or nil
			bmax = readable(data.nextReactionThreshold) and data.nextReactionThreshold or nil
			bval = readable(data.currentStanding) and data.currentStanding or nil
		end
	end
	if not standing and GetFactionInfoByID then
		local ok, fname, _, sid, low, high, val = pcall(GetFactionInfoByID, factionID)
		if ok and readable(sid) and sid then
			name = readable(fname) and fname or nil
			standing = sid
			bmin = readable(low) and low or nil
			bmax = readable(high) and high or nil
			bval = readable(val) and val or nil
		end
	end

	standing = tonumber(standing) or 4
	bmin = tonumber(bmin) or 0
	bmax = tonumber(bmax) or 3000
	bval = tonumber(bval) or 0

	local tierOffsets = { [4] = 0, [5] = 3000, [6] = 9000, [7] = 21000, [8] = 42000 }
	local totalFromNeutral
	if standing > 4 and bmin == 0 and tierOffsets[standing] then
		totalFromNeutral = tierOffsets[standing] + math.max(0, bval)
	else
		totalFromNeutral = math.max(0, bval)
	end

	local liveByID, liveByName = scanLiveFactionMap()
	local factions, digestParts = {}, {}
	for _, entry in ipairs(CATALOG_REP_FACTIONS) do
		local s = lookupLiveFactionStanding(entry.id, entry.name, liveByID, liveByName)
		factions[entry.id] = s
		factions[entry.name] = s
		digestParts[#digestParts + 1] = tostring(entry.id) .. ":" .. tostring(s)
		if ec then
			ec.factionStandings = ec.factionStandings or {}
			ec.factionStandings[entry.id] = s
		end
	end

	local repRes = {
		factionID = factionID,
		factionName = (name and name ~= "") and name or defaultName,
		playerFaction = playerFaction,
		standing = standing,
		standingName = ns.STANDING_NAMES[standing] or "Neutral",
		barMin = bmin,
		barMax = bmax,
		barValue = bval,
		inTierCurrent = math.max(0, bval - bmin),
		inTierMax = math.max(1, bmax - bmin),
		totalFromNeutral = totalFromNeutral,
		factions = factions,
		factionsDigest = table.concat(digestParts, "|"),
	}
	if ec then
		ec.repState = repRes
	end
	return repRes
end

function ns.IsOtherExceptionRecipe(recipe)
	if not readable(recipe) or type(recipe) ~= "table" then return false end
	if recipe.prof == "others" or recipe.anyChar == true then return true end
	local toolID = readableTradeVal(recipe.toolItemID) and tonumber(recipe.toolItemID) or nil
	return toolID ~= nil and toolID > 0
end

function ns.EvaluateUnlock(profKey, reqSkill, reqRep, favorCost, recipe, profMap, repState)
	reqSkill = tonumber(reqSkill) or 1
	reqRep = tonumber(reqRep) or (recipe and readable(recipe.rep) and tonumber(recipe.rep)) or 0
	favorCost = tonumber(favorCost) or 0
	local isAnyChar = recipe and recipe.anyChar == true
	local playerSkill = profMap and profMap[profKey]
	local hasProf = isAnyChar or (playerSkill ~= nil)
	local anyProfLearned = profMap and next(profMap) ~= nil or false
	local meetsSkill = isAnyChar or (hasProf and (playerSkill >= reqSkill)) or false
	local meetsRep = true
	local repFactionName = nil
	if reqRep > 0 then
		local standingObj = recipe
		if not standingObj or ((tonumber(standingObj.rep) or 0) <= 0) then
			standingObj = {
				rep = reqRep,
				source = recipe and recipe.source,
				acqType = recipe and recipe.acqType,
				repFactionID = recipe and recipe.repFactionID,
				repFaction = recipe and recipe.repFaction,
			}
		end
		local _
		_, reqRep, meetsRep, repFactionName = ns.GetRecipeStanding(standingObj, repState)
	end
	local knownInfo = (recipe and recipe.source ~= "gather" and ns.GetRecipeKnownInfo)
		and ns.GetRecipeKnownInfo(recipe) or nil
	local known = (recipe and recipe.source == "gather" and hasProf and meetsSkill)
		or (knownInfo and knownInfo.known)
		or (recipe and ns.IsRecipeKnown(recipe))
		or false
	local altTag = formatAltKnownTag(knownInfo)
	local unlockedNow = known or ((not anyProfLearned or meetsSkill) and meetsRep)
	local bracket, minCharLevel = ns.SkillRankBracket(reqSkill)

	local parts = { tostring(reqSkill) }
	if reqRep and reqRep > 0 then
		parts[#parts + 1] = ns.STANDING_NAMES[reqRep] or ("Rep " .. reqRep)
	end
	if favorCost > 0 then
		parts[#parts + 1] = tostring(favorCost) .. "F"
	elseif recipe and recipe.source == "gather" then
		parts[#parts + 1] = "Gather"
	elseif recipe and recipe.acqType == "ah" then
		parts[#parts + 1] = "AH"
	elseif recipe and (recipe.acqType == "vendor" or recipe.acqType == "vendor_ah") then
		parts[#parts + 1] = "Vendor"
	elseif recipe and recipe.acqType == "quest" then
		parts[#parts + 1] = "Quest"
	elseif recipe and recipe.acqType == "drop_bop" then
		parts[#parts + 1] = "Drop"
	elseif recipe and recipe.acqType == "start" then
		parts[#parts + 1] = "Starter"
	elseif recipe and (recipe.acqType == "trainer" or recipe.source == "trainer") then
		parts[#parts + 1] = "Trainer"
	end
	local label = table.concat(parts, " · ")

	local color
	if known then
		color = "|cff33ff33"
		label = label .. (altTag and (" (" .. altTag .. ")") or " (Known)")
	elseif hasProf and meetsSkill and meetsRep then
		color = "|cff66ee66"
	elseif not meetsRep then
		color = "|cffff6666"
	elseif hasProf and not meetsSkill then
		color = "|cffffaa44"
	else
		color = "|cffcccccc"
	end

	return {
		known = known,
		knownOnActive = knownInfo and knownInfo.knownOnActive or false,
		knownAltNames = knownInfo and knownInfo.altNames or nil,
		hasProf = hasProf,
		anyProfLearned = anyProfLearned,
		playerSkill = playerSkill,
		meetsSkill = meetsSkill,
		meetsRep = meetsRep,
		repFactionName = repFactionName,
		unlockedNow = unlockedNow,
		bracket = bracket,
		minCharLevel = minCharLevel,
		label = label,
		coloredLabel = color .. label .. "|r",
		sortScore = reqSkill + (reqRep * 1000),
		isSmeltedBar = (profKey == "mining" and recipe ~= nil and recipe.source ~= "gather"),
		isOtherException = ns.IsOtherExceptionRecipe(recipe),
	}
end

function ns.MatchesGlobalFilters(profKey, unlockInfo, profFilter, unlockFilter)
	profFilter = profFilter or "all"
	unlockFilter = unlockFilter or "all"

	if profFilter == "mine_profs" then
		if unlockInfo.anyProfLearned and not unlockInfo.hasProf then
			return false
		end
	elseif profFilter == "others" then
		if profKey ~= "others" and not (unlockInfo and unlockInfo.isOtherException) then
			return false
		end
	elseif profFilter ~= "all" then
		-- Allow Blacksmithing filter to also match smelted bar bundles tagged under Mining
		if profKey ~= profFilter and not (profFilter == "blacksmithing" and unlockInfo and unlockInfo.isSmeltedBar) then
			return false
		end
	end

	if unlockFilter == "applies" or unlockFilter == "mine_profs" then
		if unlockInfo.anyProfLearned and not unlockInfo.hasProf then
			return false
		end
	elseif unlockFilter == "unlocked" then
		if not unlockInfo.unlockedNow then
			return false
		end
	elseif unlockFilter == "known" then
		if not unlockInfo.known then
			return false
		end
	elseif unlockFilter == "locked" then
		if unlockInfo.known or (unlockInfo.hasProf and unlockInfo.meetsSkill and unlockInfo.meetsRep) then
			return false
		end
	end

	return true
end

---------------------------------------------------------------------------------------------------
-- Generic Multi-Column Sorter (nil values always sorted last regardless of direction)

function ns.SortRows(rows, sortCol, sortAsc, tieCol, stringCols)
	local isString = stringCols and stringCols[sortCol] or false
	table.sort(rows, function(a, b)
		local va, vb = a[sortCol], b[sortCol]
		if va == nil and vb ~= nil then return false end
		if va ~= nil and vb == nil then return true end
		if va ~= nil and vb ~= nil then
			if isString then
				local sa, sb = tostring(va):lower(), tostring(vb):lower()
				if sa ~= sb then
					if sortAsc then return sa < sb else return sa > sb end
				end
			else
				if va ~= vb then
					if sortAsc then return va < vb else return va > vb end
				end
			end
		end
		if tieCol and a[tieCol] ~= b[tieCol] then
			if a[tieCol] == nil then return false end
			if b[tieCol] == nil then return true end
			return a[tieCol] < b[tieCol]
		end
		local na, nb = tostring(a.name or a.crateName or a.writName or ""), tostring(b.name or b.crateName or b.writName or "")
		if na ~= nb then return na < nb end
		return tostring(a.reagentName or a.idx or "") < tostring(b.reagentName or b.idx or "")
	end)
end

---------------------------------------------------------------------------------------------------
-- 1. Waylaid Crates Row Builder (Merchant's Favor Optimizer)

function ns.GetCrateReward(crate)
	local db = ns.GetDB()
	local custom = db and db.rewards and db.rewards[crate.tier] and db.rewards[crate.tier][crate.quality]
	local def = ns.DEFAULT_REWARDS[crate.tier] and ns.DEFAULT_REWARDS[crate.tier][crate.quality]
	local tokens = (custom and custom.tokens) or (def and def.tokens) or 0
	local copper = (custom and custom.copper ~= nil) and custom.copper or (def and def.copper or 0)
	return tokens, copper, def and def.unconfirmed and not (custom and custom.tokens)
end

function ns.BuildCrateRows(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts(opts)
	local yieldBudget = type(opts.yieldBudget) == "function" and opts.yieldBudget or nil
	local minimalBest = opts.minimalBest == true
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local bestOnly = opts.bestOnly and true or false
	local crateMode = opts.crateMode or "cheapest" -- "cheapest" | "craft" | "buy"
	local subCraftMode = opts.subCraftMode or "smart"
	local subCraftOverrides = opts.subCraftOverrides
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.unlockFilter or "all"
	local counts = opts.ownedCounts or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()

	if minimalBest then
		local firstIdx = opts.startIndex or 1
		local lastIdx = math.min(opts.endIndex or #ns.CRATES, #ns.CRATES)
		local bestToken = opts.bestPricePerToken
		local craftOptions = {profMap=profMap, subCraftMode=subCraftMode, subCraftOverrides=subCraftOverrides}
		opts.outNextIndex, opts.outDone = nil, nil
		for crateIdx = firstIdx, lastIdx do
			local crate = ns.CRATES[crateIdx]
			local cratePrice = ns.GetItemMarketPrice(crate.itemID)
			local tokens, rewardCopper = ns.GetCrateReward(crate)
			if tokens and tokens > 0 and cratePrice ~= nil then
				for _, bundle in ipairs(crate.bundles) do
					craftOptions.parentProf = bundle.prof
					local craftOpt = ns.GetItemCraftOption and ns.GetItemCraftOption(bundle.itemID, craftOptions) or nil
					if crateMode ~= "craft" or craftOpt ~= nil then
						local unlock = ns.EvaluateUnlock(bundle.prof, bundle.skill, 0, 0, craftOpt and craftOpt.recipe or nil, profMap, repState)
						if ns.MatchesGlobalFilters(bundle.prof, unlock, profFilter, unlockFilter) then
							local buyEach = ns.GetItemMarketPrice(bundle.itemID)
							local buyTotal = buyEach and (buyEach * bundle.qty) or nil
							local craftEach = craftOpt and craftOpt.unitCraftCost or nil
							local craftTotal = craftEach and (craftEach * bundle.qty) or nil
							local reagentTotal
							if crateMode == "buy" then
								reagentTotal = buyTotal
							elseif crateMode == "craft" then
								reagentTotal = craftTotal
							else
								local ov = subCraftOverrides and subCraftOverrides[bundle.itemID]
								if ov == "craft" and craftTotal then
									reagentTotal = craftTotal
								elseif ov == "buy" and buyTotal then
									reagentTotal = buyTotal
								elseif craftTotal and buyTotal then
									reagentTotal = math.min(craftTotal, buyTotal)
								else
									reagentTotal = craftTotal or buyTotal
								end
							end
							if reagentTotal ~= nil then
								local totalPrice = cratePrice + reagentTotal - (rewardCopper or 0)
								local pricePerToken = totalPrice / tokens
								if bestToken == nil or pricePerToken < bestToken then bestToken = pricePerToken end
							end
						end
					end
				end
			end
			if yieldBudget and yieldBudget() then
				lastIdx = crateIdx
				break
			end
		end
		if lastIdx < #ns.CRATES then opts.outNextIndex = lastIdx + 1 else opts.outDone = true end
		ns.PopEvalOpts(evalTok)
		ns.EndEval()
		local best = bestToken and {pricePerToken=bestToken} or nil
		if opts.outNextIndex then return nil, best end
		return {}, best
	end

	local allRows = {}
	local pricedCount, totalCombos = 0, 0
	local bestOverallRow = nil
	local craftOptions = {profMap=profMap, subCraftMode=subCraftMode, subCraftOverrides=subCraftOverrides}

	for _, crate in ipairs(ns.CRATES) do
		local crateDisplay = ns.ItemName(crate.itemID, crate.name)
		local crateShort = crateDisplay:gsub("^Waylaid Crate:%s*", "")
		local cratePrice, crateSource, crateStock = ns.GetItemMarketPrice(crate.itemID)
		local tokens, rewardCopper, unconfirmed = ns.GetCrateReward(crate)
		local bestForThisCrate = nil

		for _, bundle in ipairs(crate.bundles) do
			craftOptions.parentProf = bundle.prof
			local craftOpt = ns.GetItemCraftOption and ns.GetItemCraftOption(bundle.itemID, craftOptions) or nil
			local hasCraft = (craftOpt ~= nil)

			if crateMode ~= "craft" or hasCraft then
				local fakeRec = hasCraft and craftOpt.recipe or nil
				local unlock = ns.EvaluateUnlock(bundle.prof, bundle.skill, 0, 0, fakeRec, profMap, repState)
				if ns.MatchesGlobalFilters(bundle.prof, unlock, profFilter, unlockFilter) then
					totalCombos = totalCombos + 1
					local qty = bundle.qty

					local buyEach, buySource, reagentStock = ns.GetItemMarketPrice(bundle.itemID)
					local buyTotal = buyEach and (buyEach * qty) or nil

					local craftEach = craftOpt and craftOpt.unitCraftCost or nil
					local craftTotal = craftEach and (craftEach * qty) or nil
					local craftSource = craftOpt and ("Craft (" .. craftOpt.profLabel .. ")") or nil

					local reagentEach, reagentTotal, reagentSource, chosenMode
					if crateMode == "buy" then
						reagentEach, reagentTotal, reagentSource = buyEach, buyTotal, buySource
						chosenMode = buyTotal and "Buy" or "—"
					elseif crateMode == "craft" then
						reagentEach, reagentTotal, reagentSource = craftEach, craftTotal, craftSource
						chosenMode = craftTotal and "Craft" or "—"
					else
						local ov = subCraftOverrides and subCraftOverrides[bundle.itemID]
						if ov == "craft" and craftTotal then
							reagentEach, reagentTotal, reagentSource, chosenMode = craftEach, craftTotal, craftSource, "Craft"
						elseif ov == "buy" and buyTotal then
							reagentEach, reagentTotal, reagentSource, chosenMode = buyEach, buyTotal, buySource, "Buy"
						elseif craftTotal and buyTotal then
							if craftTotal <= buyTotal then
								reagentEach, reagentTotal, reagentSource, chosenMode = craftEach, craftTotal, craftSource, "Craft"
							else
								reagentEach, reagentTotal, reagentSource, chosenMode = buyEach, buyTotal, buySource, "Buy"
							end
						elseif craftTotal then
							reagentEach, reagentTotal, reagentSource, chosenMode = craftEach, craftTotal, craftSource, "Craft"
						elseif buyTotal then
							reagentEach, reagentTotal, reagentSource, chosenMode = buyEach, buyTotal, buySource, "Buy"
						else
							reagentEach, reagentTotal, reagentSource, chosenMode = nil, nil, nil, "—"
						end
					end

					local grossTotal = (cratePrice and reagentTotal) and (cratePrice + reagentTotal) or nil
					local totalPrice = grossTotal and (grossTotal - rewardCopper) or nil
					local pricePerToken = (totalPrice and tokens and tokens > 0) and (totalPrice / tokens) or nil

					if pricePerToken ~= nil then
						pricedCount = pricedCount + 1
					end
			local replacesBest = not bestForThisCrate
				or (pricePerToken ~= nil and (bestForThisCrate.pricePerToken == nil or pricePerToken < bestForThisCrate.pricePerToken))
				or (bestForThisCrate.pricePerToken == nil and reagentTotal ~= nil
					and (bestForThisCrate.reagentTotal == nil or reagentTotal < bestForThisCrate.reagentTotal))

			if not bestOnly or replacesBest then
					local reagentDisplay = ns.ItemName(bundle.itemID, bundle.name)
					local profObj = ns.PROF_BY_KEY[bundle.prof]
					local crateDailySold = ns.GetDailySold(crate.itemID)
					local reagentDailySold = ns.GetDailySold(bundle.itemID)
					local row = {
						crate = crate,
						crateID = crate.itemID,
						crateFullName = crateDisplay,
						crateName = crateShort,
						crateQuality = crate.quality,
						crateIcon = ns.ItemIcon(crate.itemID, CRATE_ICON),
						cratePrice = cratePrice,
						crateSource = crateSource,
						crateStock = crateStock,
						crateDailySold = crateDailySold,
						reagentID = bundle.itemID,
						reagentEnglishName = bundle.name,
						reagentName = reagentDisplay,
						reagentIcon = ns.ItemIcon(bundle.itemID, QUESTION_ICON),
						reagentEach = reagentEach,
						reagentSource = reagentSource,
						reagentStock = reagentStock,
						reagentDailySold = reagentDailySold,
						dailySold = (reagentDailySold ~= nil) and reagentDailySold or crateDailySold,
						reagentQty = qty,
						reagentOwned = counts[reagentDisplay] or counts[bundle.name] or 0,
						reagentTotal = reagentTotal,
						buyEach = buyEach,
						buyTotal = buyTotal,
						buySource = buySource,
						craftEach = craftEach,
						craftTotal = craftTotal,
						craftOpt = craftOpt,
						hasCraft = hasCraft,
						mode = chosenMode,
						prof = bundle.prof,
						profLabel = profObj and profObj.label or "",
						skill = bundle.skill,
						unlock = unlock,
						tokens = tokens,
						reward = rewardCopper,
						grossTotal = grossTotal,
						totalPrice = totalPrice,
						pricePerToken = pricePerToken,
						unconfirmed = unconfirmed,
					}

					if row.pricePerToken ~= nil and (not bestOverallRow or row.pricePerToken < bestOverallRow.pricePerToken) then
						bestOverallRow = row
					end

					if not bestForThisCrate or (row.pricePerToken ~= nil and (bestForThisCrate.pricePerToken == nil or row.pricePerToken < bestForThisCrate.pricePerToken)) then
						bestForThisCrate = row
					elseif bestForThisCrate.pricePerToken == nil and row.reagentTotal ~= nil and (bestForThisCrate.reagentTotal == nil or row.reagentTotal < bestForThisCrate.reagentTotal) then
						bestForThisCrate = row
					end

					if not bestOnly then
						allRows[#allRows + 1] = row
					end
			end
				end
			end
			if opts.yieldBudget and not opts._isFallback and coroutine.running()
				and opts.yieldBudget() then
				ns.PopEvalOpts(evalTok)
				ns.EndEval()
				coroutine.yield()
				ns.BeginEval()
				evalTok = ns.PushEvalOpts(opts)
			end
		end

		if bestOnly and bestForThisCrate then
			allRows[#allRows + 1] = bestForThisCrate
		end
	end

	-- If a non-crate profession filter (e.g. Alchemy, Cooking, First Aid, Enchanting) hid all 96 crate rows,
	-- automatically fall back to showing all crates so Favor buyers never face a blank table.
	if totalCombos == 0 and (profFilter ~= "all" or unlockFilter ~= "all") and not opts._isFallback then
		local fbOpts = {}
		for k, v in pairs(opts) do fbOpts[k] = v end
		fbOpts.profFilter = "all"
		fbOpts.unlockFilter = "all"
		fbOpts._isFallback = true
		local fbRows, fbBest, fbPriced, fbTotal = ns.BuildCrateRows(fbOpts)
		ns.PopEvalOpts(evalTok)
		ns.EndEval()
		return fbRows, fbBest, fbPriced, fbTotal, profFilter
	end

	local filtered = {}
	for _, row in ipairs(allRows) do
		if needle == ""
			or row.crateFullName:lower():find(needle, 1, true)
			or row.crateName:lower():find(needle, 1, true)
			or row.reagentName:lower():find(needle, 1, true)
			or row.crate.tier:lower():find(needle, 1, true)
			or row.prof:lower():find(needle, 1, true) then
			filtered[#filtered + 1] = row
		end
	end

	ns.PopEvalOpts(evalTok)
	ns.EndEval()
	return filtered, bestOverallRow, pricedCount, totalCombos, nil
end

---------------------------------------------------------------------------------------------------
-- 2. Craftsman's Writs Row Builder (Merchant Reputation Optimizer: Craft vs Buy + Tiered Writ Coin Pouch + Area)

function ns.GetWritPouchInfo(writ)
	if type(writ) == "table" then
		local byRep = ns.WRIT_POUCH_BY_REP and writ.rep and ns.WRIT_POUCH_BY_REP[tonumber(writ.rep)]
		if byRep then
			return tonumber(writ.pouchCopper) or tonumber(byRep.avgMoneyCopper) or 7480,
				writ.pouchItemID or byRep.id,
				writ.tier or byRep.tier
		end
		if tonumber(writ.pouchCopper) then
			return tonumber(writ.pouchCopper), writ.pouchItemID, writ.tier
		end
		local r = tonumber(writ.rep) or 0
		if r > 0 and r <= 75 then
			return 3536, 284584, "Journeyman"
		elseif r > 75 and r <= 125 then
			return 7480, 284585, "Expert"
		elseif r > 125 then
			return 7480, 284586, "Artisan"
		end
	end
	local def = (ns.WRIT_POUCH_INFO and tonumber(ns.WRIT_POUCH_INFO.defaultCopper))
		or tonumber(ns.DEFAULT_WRIT_POUCH_COPPER)
		or 7480
	return def, 284585, "Expert"
end

function ns.GetWritPouchRefund(writ, opts)
	if opts and opts.includeWritPouch == false then
		return 0
	end
	if (not opts or opts.includeWritPouch == nil) and MerchantMasterDB and MerchantMasterDB.includeWritPouch == false then
		return 0
	end
	local custom = (opts and tonumber(opts.writPouchCopper))
		or (MerchantMasterDB and tonumber(MerchantMasterDB.customWritPouchCopper))
	if custom and custom >= 0 then
		return math.floor(custom + 0.5)
	end
	local copper = ns.GetWritPouchInfo(writ)
	return math.floor((copper or 7480) + 0.5)
end

function ns.GetWritZoneInfo(writ)
	if type(writ) ~= "table" or not readable(writ) then return "Unmapped", "unmapped", nil, nil, nil end
	local z = type(writ.zone) == "string" and readable(writ.zone) and writ.zone:match("^%s*(.-)%s*$")
	if z == "" or z == "Unknown" or z == "Unmapped" then z = nil end
	local npc, x, y = writ.npc, writ.x, writ.y
	if z and npc and x and y then return z, "static", npc, x, y end

	local db, id = _G.MerchantMasterDB, writ.itemID
	local zones = type(db) == "table" and readable(db) and db.learnedWritZones
	id = readable(id) and id or nil
	local learned = id and type(zones) == "table" and readable(zones) and zones[id]
	if type(learned) == "table" and readable(learned) and readable(learned.source)
		and learned.source ~= "quest_accept" and learned.source ~= "bettermaps"
		and type(learned.zone) == "string" and readable(learned.zone) then
		local lz = learned.zone:match("^%s*(.-)%s*$")
		if lz ~= "" and lz ~= "Unknown" and lz ~= "Unmapped" then
			local lnpc = readable(learned.npc) and learned.npc or nil
			local lx = readable(learned.x) and learned.x or nil
			local ly = readable(learned.y) and learned.y or nil
			if not z then return lz, "learned", lnpc or npc, lx or x, ly or y end
			if lz == z then npc, x, y = npc or lnpc, x or lx, y or ly end
		end
	end
	if z then return z, "static", npc, x, y end
	local hint = id and ns.WRIT_ZONE_HINTS and ns.WRIT_ZONE_HINTS[id]
	if type(hint) == "string" then
		local hz = hint:match("^%s*(.-)%s*$")
		if hz ~= "" then
			return hz, "hint", writ.npc, writ.x, writ.y
		end
	end
	return "Unmapped", "unmapped", nil, nil, nil
end

function ns.GetWritZoneLabel(writ)
	local z, src = ns.GetWritZoneInfo(writ)
	if src == "hint" or src == "unmapped" then return "Unmapped" end
	return z
end

function ns.GetWritZones()
	local counts = {}
	local reps = {}
	local order = {}
	local unmappedCount, unmappedRep = 0, 0
	local mappedCount = 0

	for _, writ in ipairs(ns.WRITS or {}) do
		local z = ns.GetWritZoneLabel(writ)
		local r = tonumber(writ.rep) or 0
		if z == "Unmapped" then
			unmappedCount = unmappedCount + 1
			unmappedRep = unmappedRep + r
		else
			mappedCount = mappedCount + 1
			if not counts[z] then
				counts[z] = 0
				reps[z] = 0
				order[#order + 1] = z
			end
			counts[z] = counts[z] + 1
			reps[z] = reps[z] + r
		end
	end

	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)

	local list = {
		{ key = "all", label = "Area: All Zones" },
		{ key = "mapped", label = string.format("Area: Known Areas (%d)", mappedCount), count = mappedCount },
	}
	for _, z in ipairs(order) do
		list[#list + 1] = {
			key = z,
			label = string.format("%s (%d · +%d Rep)", z, counts[z], reps[z]),
			count = counts[z],
			totalRep = reps[z],
		}
	end
	if unmappedCount > 0 then
		list[#list + 1] = {
			key = "unmapped",
			label = string.format("Unmapped (%d · +%d Rep)", unmappedCount, unmappedRep),
			count = unmappedCount,
			totalRep = unmappedRep,
		}
	end
	return list
end

function ns.MatchesWritZoneFilter(writ, zoneFilter)
	zoneFilter = zoneFilter or "all"
	if zoneFilter == "" or zoneFilter == "all" then
		return true
	end
	local z = ns.GetWritZoneLabel(writ)
	if zoneFilter == "mapped" then
		return z ~= "Unmapped"
	elseif zoneFilter == "unmapped" then
		return z == "Unmapped"
	end
	if z == zoneFilter then
		return true
	end
	return z:lower():find( tostring(zoneFilter):lower(), 1, true ) ~= nil
end

function ns.GetDailyQuestResetSeconds(nowEpoch)
	local liveReset = _G.C_DateAndTime
	if readable(liveReset) and type(liveReset) == "table" and type(liveReset.GetSecondsUntilDailyReset) == "function" then
		local ok, value = pcall(liveReset.GetSecondsUntilDailyReset)
		if ok and readable(value) and type(value) == "number" and value > 0 and value <= 172800 then return value, true end
	end
	if type(_G.GetQuestResetTime) == "function" then
		local ok, value = pcall(_G.GetQuestResetTime)
		if ok and readable(value) and type(value) == "number" and value > 0 and value <= 172800 then return value, true end
	end
	local now = tonumber(nowEpoch) or (time and time()) or 0
	local rem = 86400 - (now % 86400)
	return math.max(60, math.min(86400, rem)), false
end

function ns.FormatWritCooldownShort(sec)
	sec = tonumber(sec) or 0
	if sec >= 3600 then return string.format("%dh", math.max(1, math.floor(sec / 3600 + 0.5))) end
	return string.format("%dm", math.min(59, math.max(1, math.ceil(sec / 60))))
end

function ns.RecordWritTurnInCooldown(questID, nowEpoch)
	if not readable(questID) then return false end
	local qid = tonumber(questID)
	if not qid or qid <= 0 then return false end
	local char = ns.activeChar or (ns.app and ns.app.char)
	if not readable(char) or type(char) ~= "table" then return false end
	char.writCooldowns = readable(char.writCooldowns) and type(char.writCooldowns) == "table"
		and not (_G.issecrettable and _G.issecrettable(char.writCooldowns)) and char.writCooldowns or {}
	local now = tonumber(nowEpoch) or (time and time()) or 0
	local rem = ns.GetDailyQuestResetSeconds(now)
	char.writCooldowns[qid] = now + rem
	return true
end

function ns.GetWritCooldownInfo(writ, opts)
	opts = opts or {}
	local qid
	if type(writ) == "table" and readable(writ) then
		if readable(writ.questID) then qid = tonumber(writ.questID) end
	elseif readable(writ) then
		qid = tonumber(writ)
	end
	local allChars = (opts.char == nil) and ns.IsAllCharsCraftableActive(opts) or false
	local ec = ns._evalCache
	local cdBucket = ec and ec.writCdByMode and (allChars and ec.writCdByMode.all or ec.writCdByMode.self)
	if qid and cdBucket and opts.now == nil and opts.char == nil and cdBucket[qid] then
		return cdBucket[qid]
	end
	if not qid or qid <= 0 then
		return { hasCooldown = false, available = false, onCooldown = false, remainingSeconds = 0, shortText = "-", sortValue = 999999 }
	end
	if allChars and type(writ) == "table" then
		local activeCh = ns.activeChar or (ns.app and ns.app.char)
		local knowingChars = {}
		for _, ch in ipairs(ns.GetEconomyCharacters()) do
			local isAct = (ch == activeCh)
			local pm = isAct and ns.GetLivePlayerProfessions() or ns.GetCharProfessions(ch)
			if checkRecipeKnownOnChar(writ, ch, pm, isAct) then
				knowingChars[#knowingChars + 1] = ch
			end
		end
		if #knowingChars > 0 then
			local bestCD
			for _, ch in ipairs(knowingChars) do
				local cInfo = ns.GetWritCooldownInfo(writ, { char = ch, now = opts.now, currentCharOnly = true })
				if cInfo and not cInfo.onCooldown then
					bestCD = cInfo
					break
				end
				if cInfo and (not bestCD or (cInfo.remainingSeconds or 0) < (bestCD.remainingSeconds or 0)) then
					bestCD = cInfo
				end
			end
			if bestCD then
				if cdBucket and opts.now == nil then cdBucket[qid] = bestCD end
				return bestCD
			end
		end
	end
	local now = (readable(opts.now) and tonumber(opts.now)) or (time and time()) or 0
	local defaultChar = ns.activeChar or (ns.app and ns.app.char)
	local char = (readable(opts.char) and opts.char) or defaultChar
	local savedMap = readable(char) and type(char) == "table" and readable(char.writCooldowns)
		and type(char.writCooldowns) == "table" and not (_G.issecrettable and _G.issecrettable(char.writCooldowns))
		and char.writCooldowns or nil
	local savedExp = savedMap and readable(savedMap[qid]) and tonumber(savedMap[qid]) or nil
	if savedExp and savedExp <= now then savedMap[qid] = nil; savedExp = nil end
	local questLog = _G.C_QuestLog
	local liveFn
	if readable(questLog) and type(questLog) == "table" and type(questLog.IsQuestFlaggedCompleted) == "function" then
		liveFn = questLog.IsQuestFlaggedCompleted
	elseif type(_G.IsQuestFlaggedCompleted) == "function" then
		liveFn = _G.IsQuestFlaggedCompleted
	end
	local liveCompleted
	if liveFn and char == defaultChar then
		local ok, value = pcall(liveFn, qid)
		if ok and readable(value) and type(value) == "boolean" then liveCompleted = value end
	end
	local resetSec, hasLiveReset = ns.GetDailyQuestResetSeconds(now)
	local completed, remSec = false, nil
	if liveCompleted == true then
		completed = true
		remSec = (hasLiveReset and resetSec) or (savedExp and savedExp > now and (savedExp - now)) or resetSec
		if savedMap then savedMap[qid] = now + remSec end
	elseif liveCompleted == false then
		if hasLiveReset then
			if savedMap then savedMap[qid] = nil end
		elseif savedExp and savedExp > now then
			completed, remSec = true, savedExp - now
		end
	elseif savedExp and savedExp > now then
		completed, remSec = true, savedExp - now
	end
	local result
	if completed then
		result = { hasCooldown = true, isDaily = true, nominalSeconds = 86400, available = false, onCooldown = true, remainingSeconds = remSec, resetAt = now + remSec, shortText = ns.FormatWritCooldownShort(remSec), sortValue = remSec }
	else
		result = { hasCooldown = true, isDaily = true, nominalSeconds = 86400, available = true, onCooldown = false, remainingSeconds = 0, resetAt = nil, shortText = "R", sortValue = 0 }
	end
	if qid and cdBucket and opts.now == nil and opts.char == nil then
		cdBucket[qid] = result
	end
	return result
end

local function buildWritRowsImpl(opts)
	opts = opts or {}
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local writMode = opts.writMode or "cheapest" -- "cheapest" | "craft" | "buy"
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.unlockFilter or "all"
	local zoneFilter = opts.zoneFilter or (MerchantMasterDB and MerchantMasterDB.writZoneFilter) or "all"
	local writTurnInQueue = opts.writTurnInQueue or (MerchantMasterDB and MerchantMasterDB.writTurnInQueue) or nil
	local counts = opts.ownedCounts or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()

	local rows = {}
	local pricedCount, totalWrits, nearZeroCount = 0, 0, 0
	local bestWritRow = nil

	for _, writ in ipairs(ns.WRITS) do
		local unlock = ns.EvaluateUnlock(writ.prof, writ.skill, 0, 0, writ, profMap, repState)
		if ns.MatchesGlobalFilters(writ.prof, unlock, profFilter, unlockFilter)
			and ns.MatchesWritZoneFilter(writ, zoneFilter) then
			totalWrits = totalWrits + 1
			local writFull = ns.ItemName(writ.itemID, writ.name)
			local writShort = writFull:gsub("^Craftsman's Writ:%s*", "")
			local reqName = ns.ItemName(writ.requiredItemID, writ.requiredItemName)

			local writPrice, writSource = ns.GetItemMarketPrice(writ.itemID)
			local buyUnit, buySource = ns.GetItemMarketPrice(writ.requiredItemID)
			local buyCost = buyUnit and (buyUnit * writ.qty) or nil

			local unitCraft, breakdown, craftSrc
			if ns.ComputeSmartCraftCost then
				unitCraft, breakdown, craftSrc = ns.ComputeSmartCraftCost(writ.reagents, writ.numMade, writ.requiredItemID, {
					parentProf = writ.prof,
					profMap = profMap,
					subCraftMode = opts.subCraftMode or "smart",
					subCraftOverrides = opts.subCraftOverrides,
				})
			else
				unitCraft, breakdown, craftSrc = ns.ComputeCraftCost(writ.reagents, writ.numMade, writ.requiredItemID)
			end
			local numMade = math.max(1, writ.numMade or 1)
			local batches = math.ceil((writ.qty or 1) / numMade)
			local craftCost = unitCraft and (unitCraft * numMade * batches) or nil

			local chosenCost, chosenMode
			local override = opts.subCraftOverrides and opts.subCraftOverrides[writ.requiredItemID]
			if writMode == "buy" then
				chosenCost, chosenMode = buyCost, buyCost and "Buy" or "—"
			elseif writMode == "craft" then
				chosenCost, chosenMode = craftCost, craftCost and "Craft" or "—"
			elseif override == "craft" and craftCost ~= nil then
				chosenCost, chosenMode = craftCost, "Craft"
			elseif override == "buy" and buyCost ~= nil then
				chosenCost, chosenMode = buyCost, "Buy"
			else
				if craftCost and buyCost then
					if craftCost <= buyCost then
						chosenCost, chosenMode = craftCost, "Craft"
					else
						chosenCost, chosenMode = buyCost, "Buy"
					end
				elseif craftCost then
					chosenCost, chosenMode = craftCost, "Craft"
				elseif buyCost then
					chosenCost, chosenMode = buyCost, "Buy"
				else
					chosenCost, chosenMode = nil, "—"
				end
			end

			local grossTotal = (writPrice and chosenCost) and (writPrice + chosenCost) or nil
			local _, pouchItemID, pouchTier = ns.GetWritPouchInfo(writ)
			local pouchRefund = ns.GetWritPouchRefund(writ, opts)
			local totalPrice = grossTotal and (grossTotal - pouchRefund) or nil
			local pricePerRep = (totalPrice ~= nil and writ.rep > 0) and (totalPrice / writ.rep) or nil
			local grossPricePerRep = (grossTotal and writ.rep > 0) and (grossTotal / writ.rep) or nil
			local isNearZero = (totalPrice ~= nil and totalPrice <= 500)
			if pricePerRep ~= nil then
				pricedCount = pricedCount + 1
			end

			local infoZone, zoneSrc, infoNpc, infoX, infoY = ns.GetWritZoneInfo(writ)
			local zoneLabel = ns.GetWritZoneLabel(writ)
			local npcName = (infoNpc and infoNpc ~= "") and infoNpc or nil
			local coordText = (infoX and infoY and ((tonumber(infoX) or 0) > 0 or (tonumber(infoY) or 0) > 0))
				and string.format("%.1f, %.1f", tonumber(infoX) or 0, tonumber(infoY) or 0) or nil
			local shortInfoZone = (infoZone or "Unmapped"):gsub("^Stormwind City$", "Stormwind"):gsub("^Hillsbrad Foothills$", "Hillsbrad")
			local areaDisplay
			if zoneSrc == "hint" then
				areaDisplay = "|cff888888" .. shortInfoZone .. " (likely)|r"
			elseif zoneSrc == "learned" then
				areaDisplay = "|cff66ee88" .. shortInfoZone .. "|r"
			elseif zoneLabel == "Unmapped" then
				areaDisplay = "|cff777777Unmapped|r"
			else
				areaDisplay = "|cff88ddff" .. shortInfoZone .. "|r"
			end

			local profObj = ns.PROF_BY_KEY[writ.prof]
			local profLabel = (profObj and profObj.label or writ.prof) .. " " .. tostring(writ.skill)
			local writDailySold = ns.GetDailySold(writ.itemID)
			local reqDailySold = ns.GetDailySold(writ.requiredItemID)
			local reqListed = ns.GetNumListed(writ.requiredItemID)
			local craftAbility = ns.EvaluateCraftAbility(writ, profMap, repState)
			local demand = ns.EvaluateMarketDemand(reqListed, reqDailySold, true)
			local queuedCount = (writTurnInQueue and tonumber(writTurnInQueue[writ.itemID])) or 0

			local cdInfo = ns.GetWritCooldownInfo(writ, opts)
			local row = {
				writ = writ,
				questID = writ.questID,
				cdInfo = cdInfo,
				onCooldown = cdInfo.onCooldown,
				cdAvailable = cdInfo.available,
				cdRemaining = cdInfo.remainingSeconds,
				cdText = cdInfo.shortText,
				cdSort = cdInfo.sortValue,
				writID = writ.itemID,
				writFullName = writFull,
				writName = writShort,
				writIcon = ns.ItemIcon(writ.itemID, 134939),
				writPrice = writPrice,
				writSource = writSource,
				writDailySold = writDailySold,
				reqItemID = writ.requiredItemID,
				reqItemName = reqName,
				reqItemIcon = ns.ItemIcon(writ.requiredItemID, QUESTION_ICON),
				reqQty = writ.qty,
				reqOwned = counts[reqName] or counts[writ.requiredItemName] or 0,
				reqDailySold = reqDailySold,
				reqListed = reqListed,
				dailySold = (reqDailySold ~= nil) and reqDailySold or writDailySold,
				prof = writ.prof,
				skill = writ.skill,
				profSkillLabel = profLabel,
				profSkillSort = (profObj and profObj.label or writ.prof) .. string.format("%03d", writ.skill),
				unlock = unlock,
				craftAbility = craftAbility,
				demand = demand,
				rep = writ.rep,
				zone = zoneLabel,
				zoneSource = zoneSrc,
				zoneHint = (zoneSrc == "hint") and infoZone or nil,
				npc = npcName,
				coordText = coordText,
				areaDisplay = areaDisplay,
				buyUnit = buyUnit,
				buyCost = buyCost,
				buySource = buySource,
				craftCost = craftCost,
				craftBreakdown = breakdown,
				craftSource = craftSrc,
				mode = chosenMode,
				grossTotal = grossTotal,
				pouchRefund = pouchRefund,
				pouchTier = pouchTier,
				pouchItemID = pouchItemID,
				totalPrice = totalPrice,
				pricePerRep = pricePerRep,
				grossPricePerRep = grossPricePerRep,
				nearZero = isNearZero,
				queuedCount = queuedCount,
			}

			if row.pricePerRep ~= nil and (not bestWritRow or row.pricePerRep < bestWritRow.pricePerRep) then
				bestWritRow = row
			end

			if needle == ""
				or row.writFullName:lower():find(needle, 1, true)
				or row.writName:lower():find(needle, 1, true)
				or row.reqItemName:lower():find(needle, 1, true)
				or row.prof:lower():find(needle, 1, true)
				or row.zone:lower():find(needle, 1, true)
				or (npcName and npcName:lower():find(needle, 1, true)) then
				if isNearZero then
					nearZeroCount = nearZeroCount + 1
				end
				rows[#rows + 1] = row
			end
		end
	end

	rows.nearZeroCount = nearZeroCount
	return rows, bestWritRow, pricedCount, totalWrits, nearZeroCount
end

function ns.BuildWritRows(opts)
	ns.BeginEval()
	local evalTok = ns.PushEvalOpts(opts)
	local ok, r1, r2, r3, r4, r5 = pcall(buildWritRowsImpl, opts)
	ns.PopEvalOpts(evalTok)
	ns.EndEval()
	if not ok then error(r1, 0) end
	return r1, r2, r3, r4, r5
end

---------------------------------------------------------------------------------------------------
-- 3. All Recipes & Gathering Profitability Explorer Row Builder

-- The third argument reuses the legacy builder's already evaluated filter inputs.
local function buildRecipeRowImpl(recipe, opts, evaluated)
	opts = opts or {}
	evaluated = evaluated or {}
	local profMap = evaluated.profMap or opts.profMap or ns.GetPlayerProfessions()
	local repState = evaluated.repState or opts.repState or ns.GetMerchantReputation()
	local counts = opts.ownedCounts or {}
	local applyAHCut = opts.applyAHCut ~= false
	local unlock = evaluated.unlock or ns.EvaluateUnlock(recipe.prof, recipe.skill, recipe.rep, recipe.favorCost, recipe, profMap, repState)
	local sellable, bindReason = evaluated.sellable, evaluated.bindReason
	if sellable == nil then sellable, bindReason = ns.IsItemSellable(recipe.outputItemID, recipe.sellable, recipe.isEnchant) end
	local bisInfo = evaluated.bisInfo or ns.EvaluateBestInClass(recipe)
	local craftAbility = evaluated.craftAbility or ns.EvaluateCraftAbility(recipe, profMap, repState)
	local listed, dailySold = evaluated.listed, evaluated.dailySold
	if not evaluated.demand and sellable and recipe.outputItemID then
		listed = ns.GetNumListed(recipe.outputItemID)
		dailySold = ns.GetDailySold(recipe.outputItemID)
		if issecretvalue and issecretvalue(listed) then listed = nil end
		if issecretvalue and issecretvalue(dailySold) then dailySold = nil end
	end
	local demand = evaluated.demand or ns.EvaluateMarketDemand(listed, dailySold, sellable)
	local displayName = evaluated.displayName or ns.GetRecipeDisplayName(recipe)
	local reagents = ns.ResolveRecipeReagents(recipe)
	local numMade = (recipe.numMade and recipe.numMade > 0) and recipe.numMade or 1
	local craftCost, breakdown, craftSrc
	if ns.ComputeSmartCraftCost then
		craftCost, breakdown, craftSrc = ns.ComputeSmartCraftCost(reagents, numMade, recipe.outputItemID, {
			parentProf = recipe.prof,
			profMap = profMap,
			subCraftMode = opts.subCraftMode or "smart",
			subCraftOverrides = opts.subCraftOverrides,
		})
	else
		craftCost, breakdown, craftSrc = ns.ComputeCraftCost(reagents, numMade, recipe.outputItemID)
	end

	local val = ns.ResolveOutputSaleValuation(
		recipe.outputItemID,
		listed,
		sellable,
		craftCost,
		applyAHCut,
		opts.outlierPrices
	)
	local unitAH, ahSource = val.unitAH, val.ahSource
	local ahValue, profit, marginPct = val.ahValue, val.profit, val.marginPct
	local profObj = ns.PROF_BY_KEY[recipe.prof]
	local iconID = recipe.outputItemID or recipe.recipeItemID
	local row = {
		idx = recipe.idx,
		recipe = recipe,
		isGather = false,
		itemID = recipe.outputItemID,
		recipeItemID = recipe.recipeItemID,
		name = displayName,
		icon = ns.ItemIcon(iconID, 134939),
		prof = recipe.prof,
		profLabel = profObj and profObj.label or recipe.prof,
		skill = recipe.skill,
		rep = recipe.rep,
		favorCost = recipe.favorCost,
		source = recipe.source,
		numMade = numMade,
		unlock = unlock,
		unlockSort = unlock.sortScore,
		craftAbility = craftAbility,
		canCraftSort = craftAbility.sortScore,
		bisInfo = bisInfo,
		bisSort = bisInfo.sortScore,
		demand = demand,
		demandSort = demand.demandScore,
		listedSort = demand.listedSort,
		sellable = sellable,
		sellableSort = sellable and 1 or 0,
		bindReason = bindReason,
		craftCost = craftCost,
		craftBreakdown = breakdown,
		craftSource = craftSrc,
		unitAH = unitAH,
		ahValue = ahValue,
		ahSource = ahSource,
		isUnlisted = val.isUnlisted,
		isCustomPrice = val.isCustomPrice,
		usedVendorFloor = val.usedVendorFloor,
		lastKnownPrice = val.lastKnownPrice,
		lastKnownSource = val.lastKnownSource,
		vendorSell = val.vendorSell,
		profit = profit,
		marginPct = marginPct,
		listed = listed,
		dailySold = dailySold,
		ownedCount = (recipe.outputItemID and counts[ns.ItemName(recipe.outputItemID)]) or counts[displayName] or 0,
	}
	return row
end

function ns.BuildRecipeRow(recipe, opts, evaluated)
	opts = opts or {}
	ns.BeginEval(opts.priceBank)
	local evalTok = ns.PushEvalOpts(opts)
	local ok, row = pcall(buildRecipeRowImpl, recipe, opts, evaluated)
	ns.PopEvalOpts(evalTok)
	ns.EndEval()
	if not ok then error(row, 0) end
	return row
end

function ns.BuildRecipeRows(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts(opts)
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.knownRecipesOnly and "known" or (opts.unlockFilter or "all")
	local sellableFilter = opts.sellableFilter or "all" -- "all" | "yes" | "no"
	local sourceFilter = opts.merchantVendorOnly and "camp" or (opts.sourceFilter or "all") -- "all" | "camp" | "classic" | "gather"
	local recipeSources = opts.recipeSources
	local hasMultiSources = ns.HasActiveRecipeSourceFilter(recipeSources)
	local demandFilter = opts.demandFilter or "all"
	local craftableFilter = opts.craftableFilter or "all"
	local bisOnly = opts.bisOnly and true or false
	local applyAHCut = (opts.applyAHCut ~= false)
	local counts = opts.ownedCounts or {}
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local repState = opts.repState or ns.GetMerchantReputation()

	local rows = {}
	local profitableCount, totalMatched = 0, 0
	local bestProfitRow = nil
	local summary = {
		canCraftCount = 0,
		monopolyCount = 0,
		hotCount = 0,
		unlistedCount = 0,
		bisCount = 0,
	}

	-- A. Crafting recipes across all professions (Merchant, Vendor, Trainer, AH, Quest/BoP)
	local onlyGatherMulti = hasMultiSources
		and recipeSources.gather == true
		and not recipeSources.merchant
		and not recipeSources.vendor
		and not recipeSources.trainer
		and not recipeSources.ah
		and not recipeSources.quest_drop
	if sourceFilter ~= "gather" and not onlyGatherMulti then
		for _, recipe in ipairs(ns.RECIPES) do
			local srcPass = ns.MatchesRecipeSourceFilter(recipe, recipeSources, opts.merchantVendorOnly, sourceFilter)
			if srcPass then
				local unlock = ns.EvaluateUnlock(recipe.prof, recipe.skill, recipe.rep, recipe.favorCost, recipe, profMap, repState)
				if ns.MatchesGlobalFilters(recipe.prof, unlock, profFilter, unlockFilter) then
					local sellable, bindReason = ns.IsItemSellable(recipe.outputItemID, recipe.sellable, recipe.isEnchant)
					local sellPass = (sellableFilter == "all")
						or (sellableFilter == "yes" and sellable)
						or (sellableFilter == "no" and not sellable)
					if sellPass then
						local bisInfo = ns.EvaluateBestInClass(recipe)
						if not bisOnly or bisInfo.isBiS then
							local craftAbility = ns.EvaluateCraftAbility(recipe, profMap, repState)
							if ns.MatchesCraftableFilter(craftAbility, craftableFilter) then
								local listed, dailySold = nil, nil
								if sellable and recipe.outputItemID then
									listed = ns.GetNumListed(recipe.outputItemID)
									dailySold = ns.GetDailySold(recipe.outputItemID)
								end
								local demand = ns.EvaluateMarketDemand(listed, dailySold, sellable)
								if ns.MatchesDemandFilter(demand, demandFilter) then
									local displayName = recipe.outputItemID and ns.ItemName(recipe.outputItemID, recipe.name) or recipe.name
									if needle == ""
										or displayName:lower():find(needle, 1, true)
										or (recipe.recipeName and recipe.recipeName:lower():find(needle, 1, true))
										or recipe.prof:lower():find(needle, 1, true)
										or (bisInfo.classLabel and bisInfo.classLabel:lower():find(needle, 1, true))
										or (recipe.effectText and recipe.effectText:lower():find(needle, 1, true))
										or (craftAbility.howShort and craftAbility.howShort:lower():find(needle, 1, true))
										or (craftAbility.howDetail and craftAbility.howDetail:lower():find(needle, 1, true)) then
										totalMatched = totalMatched + 1
										local row = ns.BuildRecipeRow(recipe, opts, {
										    profMap=profMap, repState=repState, unlock=unlock, sellable=sellable, bindReason=bindReason,
										    bisInfo=bisInfo, craftAbility=craftAbility, demand=demand, listed=listed, dailySold=dailySold, displayName=displayName,
										})
										if row.profit and row.profit > 0 then profitableCount = profitableCount + 1 end
										if craftAbility.ableToCraft then summary.canCraftCount = summary.canCraftCount + 1 end
										if demand.isMonopoly then summary.monopolyCount = summary.monopolyCount + 1 end
										if demand.isHot then summary.hotCount = summary.hotCount + 1 end
										if (demand.isListed == false or row.isUnlisted) and sellable then summary.unlistedCount = summary.unlistedCount + 1 end
										if bisInfo.isBiS then summary.bisCount = summary.bisCount + 1 end
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
			end
		end
	end

	-- B. Gathering nodes (shown when Herbalism/Mining/Skinning selected, or Gather selected in multi-select / sourceFilter)
	local profObjSel = ns.PROF_BY_KEY[profFilter]
	local includeGather
	if hasMultiSources then
		includeGather = (recipeSources.gather == true)
	else
		includeGather = (sourceFilter == "gather")
			or (sourceFilter == "all" and profObjSel and profObjSel.kind == "gather")
	end
	if includeGather and sellableFilter ~= "no" and not bisOnly then
		for idx, g in ipairs(ns.GATHER_ITEMS) do
			local fakeRec = { prof = g.prof, skill = g.skill, source = "gather", acqType = "gather" }
			local unlock = ns.EvaluateUnlock(g.prof, g.skill, 0, 0, fakeRec, profMap, repState)
			if ns.MatchesGlobalFilters(g.prof, unlock, profFilter, unlockFilter) then
				local craftAbility = ns.EvaluateCraftAbility(fakeRec, profMap, repState)
				if ns.MatchesCraftableFilter(craftAbility, craftableFilter) then
					local listed = ns.GetNumListed(g.itemID)
					local dailySold = ns.GetDailySold(g.itemID)
					local demand = ns.EvaluateMarketDemand(listed, dailySold, true)
					if ns.MatchesDemandFilter(demand, demandFilter) then
						local displayName = ns.ItemName(g.itemID, g.name)
						if needle == ""
							or displayName:lower():find(needle, 1, true)
							or g.prof:lower():find(needle, 1, true)
							or (g.note and g.note:lower():find(needle, 1, true)) then
							totalMatched = totalMatched + 1
							local val = ns.ResolveOutputSaleValuation(
								g.itemID,
								listed,
								true,
								0,
								applyAHCut,
								opts.outlierPrices
							)
							local netProfit = val.profit
							if netProfit and netProfit > 0 then
								profitableCount = profitableCount + 1
							end
							if craftAbility.ableToCraft then summary.canCraftCount = summary.canCraftCount + 1 end
							if demand.isMonopoly then summary.monopolyCount = summary.monopolyCount + 1 end
							if demand.isHot then summary.hotCount = summary.hotCount + 1 end
							if demand.isListed == false or val.isUnlisted then summary.unlistedCount = summary.unlistedCount + 1 end
							local bisInfo = ns.EvaluateBestInClass(nil)
							local pObj = ns.PROF_BY_KEY[g.prof]
							local row = {
								idx = 100000 + idx,
								gather = g,
								isGather = true,
								itemID = g.itemID,
								name = displayName,
								icon = ns.ItemIcon(g.itemID, QUESTION_ICON),
								prof = g.prof,
								profLabel = pObj and pObj.label or g.prof,
								skill = g.skill,
								rep = 0,
								favorCost = 0,
								source = "gather",
								numMade = 1,
								unlock = unlock,
								unlockSort = unlock.sortScore,
								craftAbility = craftAbility,
								canCraftSort = craftAbility.sortScore,
								bisInfo = bisInfo,
								bisSort = bisInfo.sortScore,
								demand = demand,
								demandSort = demand.demandScore,
								listedSort = demand.listedSort,
								sellable = true,
								sellableSort = 1,
								bindReason = "Tradeable Gathered Material (Sellable on AH)",
								craftCost = 0,
								craftBreakdown = {},
								unitAH = val.unitAH,
								ahValue = val.ahValue,
								ahSource = val.ahSource,
								isUnlisted = val.isUnlisted,
								isCustomPrice = val.isCustomPrice,
								usedVendorFloor = val.usedVendorFloor,
								lastKnownPrice = val.lastKnownPrice,
								lastKnownSource = val.lastKnownSource,
								vendorSell = val.vendorSell,
								profit = netProfit,
								marginPct = nil,
								listed = listed,
								dailySold = dailySold,
								ownedCount = counts[displayName] or 0,
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

	ns.PopEvalOpts(evalTok)
	ns.EndEval()
	return rows, bestProfitRow, profitableCount, totalMatched, summary
end

---------------------------------------------------------------------------------------------------
-- 4. Reputation Progression Cost Calculator & Rank Unlocks Explorer

function ns.GetRacialRepMultiplier(humanDiplomacy)
	local forgedMeta = ns.FORGED_RECEIPT
	local multipliers = forgedMeta and forgedMeta.racialMultipliers
	if humanDiplomacy == true then
		return (multipliers and tonumber(multipliers.Human)) or 1.1
	end
	if humanDiplomacy == nil and type(_G.UnitRace) == "function" then
		local ok, _, raceFile = pcall(_G.UnitRace, "player")
		if ok and readable(raceFile) then
			local mult = multipliers and tonumber(multipliers[raceFile])
			if mult then return mult end
			if raceFile == "Human" then return 1.1 end
		end
	end
	return 1.0
end

function ns.EvalEfficiency(netCost, rep)
	if type(netCost) ~= "number" or type(rep) ~= "number" or rep <= 0 then return nil end

	local cpr = netCost / rep
	local tier, label, hex
	if netCost <= 0 then
		tier, label, hex = "free", "Profit / Free", "30d158"
	elseif cpr <= 50 then
		tier, label, hex = "great", "Great", "30d158"
	elseif cpr <= 150 then
		tier, label, hex = "good", "Good", "66ee66"
	elseif cpr <= 400 then
		tier, label, hex = "fair", "Fair", "ffd60a"
	else
		tier, label, hex = "costly", "Costly", "ff9230"
	end
	return {
		costPerRep = cpr,
		repPerGold = (netCost > 0) and (rep * 10000 / netCost) or nil,
		isProfit = netCost < 0,
		isFree = netCost <= 0,
		tier = tier,
		label = label,
		coloredLabel = "|cff" .. hex .. label .. "|r",
	}
end

local function getForgedFavorCrate(opts)
	local crateRows, bestCrate = ns.BuildCrateRows({
		subCraftMode = opts.subCraftMode,
		subCraftOverrides = opts.subCraftOverrides,
		crateMode = opts.crateMode or "cheapest",
		profFilter = opts.profFilter or "all",
		unlockFilter = opts.unlockFilter or "all",
		ownedCounts = opts.ownedCounts,
		profMap = opts.profMap,
		repState = opts.repState,
		bestOnly = false,
	})

	local key = opts.favorCrateKey ~= nil and tostring(opts.favorCrateKey) or nil
	local crateID = tonumber(opts.favorCrateID)
	local fc = bestCrate
	if key or crateID then
		local matched
		for _, cr in ipairs(crateRows) do
			if (key and (key == tostring(cr.crateID) .. ":" .. tostring(cr.reagentID)
					or key == tostring(cr.crateID) or key == cr.crateName or key == cr.crateFullName))
				or (crateID and tonumber(cr.crateID) == crateID) then
				if not matched or (cr.pricePerToken ~= nil
					and (matched.pricePerToken == nil or cr.pricePerToken < matched.pricePerToken)) then
					matched = cr
				end
			end
		end
		fc = matched or bestCrate
	end
	if not fc or not fc.tokens or fc.tokens <= 0 then return nil end

	local reward = fc.reward or 0
	local costPerFavor = fc.pricePerToken or (fc.totalPrice and fc.totalPrice / fc.tokens)
	local grossCostPerFavor = fc.grossTotal and fc.grossTotal / fc.tokens
	local cashbackPerFavor = reward / fc.tokens
	return {
		crateID = fc.crateID,
		itemID = fc.crateID,
		key = tostring(fc.crateID) .. ":" .. tostring(fc.reagentID),
		name = fc.crateName,
		crateName = fc.crateName,
		crateFullName = fc.crateFullName,
		tier = fc.crate and fc.crate.tier,
		quality = fc.crateQuality,
		icon = fc.crateIcon,
		tokens = fc.tokens,
		cratePrice = fc.cratePrice,
		emptyPriceSource = fc.crateSource,
		reagentTotal = fc.reagentTotal,
		grossTotal = fc.grossTotal,
		reward = reward,
		totalPrice = fc.totalPrice,
		costPerFavor = costPerFavor,
		pricePerToken = costPerFavor,
		favorGrossCostPerFavor = grossCostPerFavor,
		favorCashbackPerFavor = cashbackPerFavor,
		mode = fc.mode,
		prof = fc.prof,
		profLabel = fc.profLabel,
		reagentID = fc.reagentID,
		reagentName = fc.reagentName,
		reagentQty = fc.reagentQty,
		reagentEach = fc.reagentEach,
		reagentSource = fc.reagentSource,
		craftOpt = fc.craftOpt,
		breakdown = fc.craftOpt and fc.craftOpt.breakdown or nil,
		matDetails = {{
			itemID = fc.reagentID,
			name = fc.reagentName,
			qty = fc.reagentQty,
			unitPrice = fc.reagentEach,
			totalPrice = fc.reagentTotal,
			source = fc.reagentSource,
			mode = fc.mode,
			prof = fc.prof,
			craftOpt = fc.craftOpt,
		}},
	}
end

local function forgedCostLess(a, b, field)
	local aCost, bCost = a[field], b[field]
	if aCost == bCost then return a.crateID < b.crateID end
	return aCost ~= nil and (bCost == nil or aCost < bCost)
end

local function buildForgedDeliveryRowsImpl(opts)
	opts = opts or {}
	local forgedMode = opts.forgedMode == "banked" and "banked" or "self_funded"
	local isBanked = forgedMode == "banked"
	local forgedTurnInQueue = opts.forgedTurnInQueue

	local forgedMeta = ns.FORGED_RECEIPT or {}
	local favorRequired = tonumber(forgedMeta.favorCost) or 15
	local baseRep = tonumber(forgedMeta.baseRep) or 50
	local forgedRefund = tonumber(forgedMeta.refundCopper) or 100
	local repMult = ns.GetRacialRepMultiplier(opts.humanDiplomacy)
	local effectiveRep = math.floor(baseRep * repMult + 0.5)
	local questID = tonumber(forgedMeta.questID) or 93862
	local receiptItemID = tonumber(forgedMeta.receiptItemID) or 262902
	local containerItemID = tonumber(forgedMeta.containerItemID) or 262917

	local bestFavorCrate = getForgedFavorCrate(opts)
	local favorCostPerFavor = bestFavorCrate and bestFavorCrate.costPerFavor
	local favorGrossCostPerFavor = bestFavorCrate and bestFavorCrate.favorGrossCostPerFavor
	local favorCashbackPerFavor = bestFavorCrate and bestFavorCrate.favorCashbackPerFavor
	local sfFavorCost = favorCostPerFavor and favorRequired * favorCostPerFavor
	local favorCost = isBanked and 0 or sfFavorCost
	local favorGrossCost = isBanked and 0 or (favorGrossCostPerFavor and favorRequired * favorGrossCostPerFavor)
	local favorCashback = isBanked and 0 or (favorCashbackPerFavor and favorRequired * favorCashbackPerFavor)
	local totalRefund = isBanked and forgedRefund or (forgedRefund + (favorCashback or 0))
	local queuedByID = {}
	if type(forgedTurnInQueue) == "table" then
		for k, v in pairs(forgedTurnInQueue) do
			if type(v) == "table" then
				local id = tonumber(v.crateID or k)
				local qty = tonumber(v.count or v.qty) or 0
				if id and qty > 0 then queuedByID[id] = (queuedByID[id] or 0) + qty end
			else
				local id = tonumber(k)
				local qty = tonumber(v) or 0
				if id and qty > 0 then queuedByID[id] = (queuedByID[id] or 0) + qty end
			end
		end
	end

	local allRows = {}
	for _, crate in ipairs(ns.CRATES) do
		local crateID = crate.itemID
		local crateDisplay = ns.ItemName(crateID, crate.name)
		local crateShort = crateDisplay:gsub("^Waylaid Crate:%s*", "")
		local emptyPrice, emptyPriceSource, emptyStock = ns.GetItemMarketPrice(crateID)
		local numListed = ns.GetNumListed(crateID)
		local liveEmptySource = type(emptyPriceSource) == "string" and emptyPriceSource:find("Live AH", 1, true) ~= nil
		local emptyAhQty = numListed or emptyStock
		if emptyStock ~= nil and (liveEmptySource
			or (type(emptyPriceSource) == "string" and emptyPriceSource:find("Saved AH", 1, true))) then
			emptyAhQty = emptyStock
		end

		local forgedCrateNet = emptyPrice and (emptyPrice - forgedRefund)
		local selfFundedNetCost = (forgedCrateNet ~= nil and sfFavorCost ~= nil) and (forgedCrateNet + sfFavorCost) or nil
		local netCost = isBanked and forgedCrateNet or selfFundedNetCost
		local selfFundedCostPerRep = (selfFundedNetCost ~= nil and effectiveRep > 0) and (selfFundedNetCost / effectiveRep) or nil
		local bankedCostPerRep = (forgedCrateNet ~= nil and effectiveRep > 0) and (forgedCrateNet / effectiveRep) or nil
		local costPerRep = isBanked and bankedCostPerRep or selfFundedCostPerRep

		allRows[#allRows + 1] = {
			forged = true,
			rowKey = "forged:" .. tostring(crateID),
			itemID = crateID,
			crateID = crateID,
			name = crateDisplay,
			shortName = crateShort,
			crateName = crateShort,
			crateFullName = crateDisplay,
			icon = ns.ItemIcon(crateID, CRATE_ICON),
			tier = crate.tier,
			quality = crate.quality,
			emptyPrice = emptyPrice,
			emptyAhQty = emptyAhQty,
			emptyPriceSource = emptyPriceSource,
			isLiveEmpty = emptyPrice ~= nil and liveEmptySource,
			favorRequired = favorRequired,
			bestFavorCrate = bestFavorCrate,
			favorCrateName = bestFavorCrate and bestFavorCrate.name or nil,
			favorCostPerFavor = favorCostPerFavor,
			favorCost = favorCost,
			favorGrossCost = favorGrossCost,
			favorCashback = favorCashback,
			forgedRefund = forgedRefund,
			totalRefund = totalRefund,
			forgedCrateNet = forgedCrateNet,
			netCost = netCost,
			selfFundedNetCost = selfFundedNetCost,
			bankedNetCost = forgedCrateNet,
			baseRep = baseRep,
			repMult = repMult,
			rep = effectiveRep,
			costPerRep = costPerRep,
			selfFundedCostPerRep = selfFundedCostPerRep,
			bankedCostPerRep = bankedCostPerRep,
			forgedMode = forgedMode,
			available = netCost ~= nil,
			source = isBanked and "Banked Favor" or "Self-Funded",
			canBuy = emptyPrice ~= nil,
			efficiency = ns.EvalEfficiency(netCost, effectiveRep),
			ahListed = emptyAhQty,
			dailySold = ns.GetDailySold(crateID),
			questID = questID,
			receiptItemID = receiptItemID,
			containerItemID = containerItemID,
			queuedCount = queuedByID[crateID] or 0,
		}
	end

	local rows = {}
	local bestSelfFunded, bestBanked
	local selfFundedAvailableCount, bankedAvailableCount = 0, 0
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local tierFilter = opts.tierFilter or "all"
	local qualityFilter = opts.qualityFilter or "all"
	local quality = tonumber(qualityFilter)
	for _, row in ipairs(allRows) do
		if row.selfFundedCostPerRep ~= nil
			and (not bestSelfFunded or forgedCostLess(row, bestSelfFunded, "selfFundedCostPerRep")) then
			bestSelfFunded = row
		end
		if row.bankedCostPerRep ~= nil and (not bestBanked or forgedCostLess(row, bestBanked, "bankedCostPerRep")) then
			bestBanked = row
		end

		if (tierFilter == "all" or row.tier == tierFilter)
			and (qualityFilter == "all" or row.quality == quality)
			and (not opts.availableOnly or row.available)
			and (needle == "" or row.crateFullName:lower():find(needle, 1, true)
				or row.crateName:lower():find(needle, 1, true)
				or (row.tier and row.tier:lower():find(needle, 1, true))) then
			rows[#rows + 1] = row
			if row.selfFundedNetCost ~= nil then selfFundedAvailableCount = selfFundedAvailableCount + 1 end
			if row.bankedNetCost ~= nil then bankedAvailableCount = bankedAvailableCount + 1 end
		end
	end
	table.sort(rows, function(a, b)
		if a.available ~= b.available then return a.available end
		return forgedCostLess(a, b, "costPerRep")
	end)

	return {
		rows = rows,
		bestSelfFunded = bestSelfFunded,
		bestBanked = bestBanked,
		bestFavorCrate = bestFavorCrate,
		repMult = repMult,
		baseRep = baseRep,
		effectiveRep = effectiveRep,
		forgedMode = forgedMode,
		favorRequired = favorRequired,
		forgedRefund = forgedRefund,
		favorCost = favorCost,
		favorGrossCost = favorGrossCost,
		favorCashback = favorCashback,
		favorCostPerFavor = favorCostPerFavor,
		meta = {
			totalCrates = #rows,
			allCrates = #allRows,
			availableCount = isBanked and bankedAvailableCount or selfFundedAvailableCount,
			selfFundedAvailableCount = selfFundedAvailableCount,
			bankedAvailableCount = bankedAvailableCount,
		},
	}
end

function ns.BuildForgedDeliveryRows(opts)
	local priceSource = opts and opts.priceSource
	local db = priceSource ~= nil and ns.GetDB() or nil
	local previousSource = db and db.priceSource
	local sourceChanged = db and priceSource ~= previousSource
	local parentDepth, parentCache = evalDepth, ns._evalCache
	local evalTok = nil

	local ok, result = pcall(function()
		local priceBank = opts and opts.priceBank
		if sourceChanged then
			db.priceSource = priceSource
			ns._evalCache = nil
			if priceBank and parentCache then
				-- A supplied bank can share tables with the parent evaluation.
				local isolatedBank = {}
				for field, value in pairs(priceBank) do
					if value ~= parentCache[field] then isolatedBank[field] = value end
				end
				priceBank = isolatedBank
			end
		end
		ns.BeginEval(priceBank)
		evalTok = ns.PushEvalOpts(opts)
		return buildForgedDeliveryRowsImpl(opts)
	end)

	ns.PopEvalOpts(evalTok)
	-- BuildCrateRows can fail before closing its own evaluation.
	while evalDepth > parentDepth do ns.EndEval() end
	if sourceChanged then
		db.priceSource = previousSource
		ns._evalCache = parentCache
	end
	if not ok then error(result, 0) end
	return result
end

function ns.BuildReputationOverview(opts)
	ns.BeginEval()
	opts = opts or {}
	local evalTok = ns.PushEvalOpts(opts)
	local repState = opts.repState or ns.GetMerchantReputation()
	local profMap = opts.profMap or ns.GetPlayerProfessions()
	local profFilter = opts.profFilter or "all"
	local unlockFilter = opts.unlockFilter or "all"
	local rankFilter = opts.rankFilter or 0 -- 0=All, 4=Neutral, 5=Friendly, 6=Honored, 7=Revered, 8=Exalted
	local needle = (opts.search or ""):lower():match("^%s*(.-)%s*$")
	local simStartRep = opts.simStartRep -- nil = live standing, or integer total rep from Neutral 0
	local includeShippingLabel = opts.includeShippingLabel and true or false

	local currentTotalRep = (simStartRep ~= nil) and simStartRep or repState.totalFromNeutral
	local shippingBonus = includeShippingLabel and 2000 or 0

	-- Best writ (for rep cost, including tiered Coin Pouch refund & optional zone filter) and best crate (for Favor token gold cost)
	local _, bestWrit, _, _, nearZeroWrits = ns.BuildWritRows({
		writMode = "cheapest",
		includeWritPouch = opts.includeWritPouch,
		writPouchCopper = opts.writPouchCopper,
		zoneFilter = opts.zoneFilter,
		profMap = profMap,
		repState = repState,
	})
	if not bestWrit and opts.zoneFilter and opts.zoneFilter ~= "all" then
		_, bestWrit = ns.BuildWritRows({
			writMode = "cheapest",
			includeWritPouch = opts.includeWritPouch,
			writPouchCopper = opts.writPouchCopper,
			zoneFilter = "all",
			profMap = profMap,
			repState = repState,
		})
	end
	local _, bestCrate = ns.BuildCrateRows({ bestOnly = true })

	local bestPricePerRep = bestWrit and bestWrit.pricePerRep or nil
	local bestGrossPricePerRep = bestWrit and bestWrit.grossPricePerRep or bestPricePerRep
	local bestWritRep = bestWrit and bestWrit.rep or 125
	local bestWritPouch = bestWrit and bestWrit.pouchRefund or ns.GetWritPouchRefund({ rep = bestWritRep }, opts)
	local bestPricePerFavor = bestCrate and bestCrate.pricePerToken or nil

	-- Count camp recipes per standing rank
	local recipeCountsByRank = { [4] = #(ns.CAMP_RECIPES_BY_REP[0] or {}), [5] = #(ns.CAMP_RECIPES_BY_REP[5] or {}), [6] = #(ns.CAMP_RECIPES_BY_REP[6] or {}), [7] = 0, [8] = 0 }

	local tierSummaries = {
		[4] = string.format("%d Base Camp Recipes (30–45F) + +2,000 Rep Shipping Label", recipeCountsByRank[4]),
		[5] = string.format("%d Mid-Tier Camp Recipes (60–120F, Reagent Bags, Greater Elixirs)", recipeCountsByRank[5]),
		[6] = string.format("%d High-Tier Camp Recipes (90–360F) + Advertising Signpost Toy (1,200F)", recipeCountsByRank[6]),
		[7] = "Packmule Treat Companion Pet (1,500 Favor)",
		[8] = "Reins of the Pack Kodo Epic Mount (6,000F) + Faction Tabard (200F)",
	}

	local milestones = {}
	for _, tier in ipairs(ns.REP_TIERS) do
		local rawNeeded = math.max(0, tier.totalRep - currentTotalRep)
		local netRepNeeded = math.max(0, rawNeeded - (rawNeeded > 0 and shippingBonus or 0))
		local writsBest = (netRepNeeded > 0) and math.ceil(netRepNeeded / bestWritRep) or 0
		local writs75 = (netRepNeeded > 0) and math.ceil(netRepNeeded / 75) or 0
		local writs125 = (netRepNeeded > 0) and math.ceil(netRepNeeded / 125) or 0
		local writs200 = (netRepNeeded > 0) and math.ceil(netRepNeeded / 200) or 0
		local estGoldCost, estGrossCost, estPouchRefund = nil, nil, 0
		if netRepNeeded == 0 then
			estGoldCost, estGrossCost, estPouchRefund = 0, 0, 0
		elseif bestPricePerRep ~= nil then
			estGoldCost = math.floor(netRepNeeded * bestPricePerRep + 0.5)
			estGrossCost = bestGrossPricePerRep and math.floor(netRepNeeded * bestGrossPricePerRep + 0.5) or estGoldCost
			estPouchRefund = writsBest * (bestWritPouch or 0)
		end
		milestones[#milestones + 1] = {
			standing = tier.standing,
			rankName = tier.name,
			totalRep = tier.totalRep,
			reached = currentTotalRep >= tier.totalRep,
			rawRepNeeded = rawNeeded,
			repNeeded = netRepNeeded,
			writsBest = writsBest,
			writs75 = writs75,
			writs125 = writs125,
			writs200 = writs200,
			estGoldCost = estGoldCost,
			estGrossCost = estGrossCost,
			estPouchRefund = estPouchRefund,
			unlockSummary = tierSummaries[tier.standing] or "",
		}
	end

	-- Build filterable Unlocks list (Special Cosmetics/Mounts + all 311 Merchant Camp Recipes)
	local unlocks = {}
	if profFilter == "all" then
		for _, sp in ipairs(ns.SPECIAL_REP_UNLOCKS) do
			if (not sp.faction or sp.faction == repState.playerFaction)
				and (rankFilter == 0 or sp.rep == rankFilter) then
				local unlockedNow = repState.standing >= sp.rep
				local ufPass = (unlockFilter == "all" or unlockFilter == "applies")
					or (unlockFilter == "unlocked" and unlockedNow)
					or (unlockFilter == "locked" and not unlockedNow)
				if ufPass then
					local disp = ns.ItemName(sp.itemID, sp.name)
					if needle == "" or disp:lower():find(needle, 1, true) or sp.category:lower():find(needle, 1, true) or sp.note:lower():find(needle, 1, true) then
						local favorGold = (sp.favorCost > 0 and bestPricePerFavor) and math.floor(sp.favorCost * bestPricePerFavor + 0.5) or (sp.favorCost == 0 and 0 or nil)
						unlocks[#unlocks + 1] = {
							isSpecial = true,
							itemID = sp.itemID,
							name = disp,
							icon = ns.ItemIcon(sp.itemID, CRATE_ICON),
							category = sp.category,
							prof = "all",
							rep = sp.rep,
							repName = ns.STANDING_NAMES[sp.rep] or "Neutral",
							repSort = sp.rep * 1000,
							skill = nil,
							sellable = false,
							sellableSort = 0,
							favorCost = sp.favorCost,
							favorGoldCost = favorGold,
							craftProfit = nil,
							dailySold = nil,
							note = sp.note,
							unlockedNow = unlockedNow,
							statusText = unlockedNow and "|cff33ff33Unlocked|r" or ("|cffff6666Need " .. (ns.STANDING_NAMES[sp.rep] or "") .. "|r"),
							statusSort = unlockedNow and 1 or 2,
						}
					end
				end
			end
		end
	end

	for _, recipe in ipairs(ns.RECIPES) do
		if recipe.source == "camp" then
			local effRep = (recipe.rep == 0) and 4 or recipe.rep
			if rankFilter == 0 or effRep == rankFilter then
				local unlock = ns.EvaluateUnlock(recipe.prof, recipe.skill, recipe.rep, recipe.favorCost, recipe, profMap, repState)
				if ns.MatchesGlobalFilters(recipe.prof, unlock, profFilter, unlockFilter) then
					local disp = recipe.outputItemID and ns.ItemName(recipe.outputItemID, recipe.name) or recipe.name
					if needle == "" or disp:lower():find(needle, 1, true) or recipe.recipeName:lower():find(needle, 1, true) or recipe.prof:lower():find(needle, 1, true) then
						local sellable = ns.IsItemSellable(recipe.outputItemID, recipe.sellable, recipe.isEnchant)
						local favorGold = (recipe.favorCost > 0 and bestPricePerFavor) and math.floor(recipe.favorCost * bestPricePerFavor + 0.5) or nil
						local craftProfit = nil
						local dailySold = nil
						if sellable and recipe.outputItemID then
							local reagents = ns.ResolveRecipeReagents(recipe)
							local cCost = ns.ComputeCraftCost(reagents, recipe.numMade or 1, recipe.outputItemID)
							local uAH = ns.GetItemMarketPrice(recipe.outputItemID)
							if cCost and uAH then
								craftProfit = math.floor(uAH * 0.95 + 0.5) - cCost
							end
							dailySold = ns.GetDailySold(recipe.outputItemID)
						elseif recipe.outputItemID then
							dailySold = ns.GetDailySold(recipe.outputItemID)
						end
						local pObj = ns.PROF_BY_KEY[recipe.prof]
						local statusText, statusSort
						if unlock.known then
							statusText, statusSort = "|cff33ff33Learned|r", 0
						elseif unlock.meetsRep and (not unlock.anyProfLearned or unlock.meetsSkill) then
							statusText, statusSort = "|cff66ee66Available Now|r", 1
						elseif not unlock.meetsRep then
							statusText, statusSort = "|cffff6666Need " .. (ns.STANDING_NAMES[effRep] or "") .. "|r", 3
						else
							statusText, statusSort = "|cffffaa44Need Skill " .. tostring(recipe.skill) .. "|r", 2
						end
						unlocks[#unlocks + 1] = {
							isSpecial = false,
							recipe = recipe,
							bisInfo = ns.EvaluateBestInClass(recipe),
							craftAbility = ns.EvaluateCraftAbility(recipe, profMap, repState),
							itemID = recipe.outputItemID or recipe.recipeItemID,
							recipeItemID = recipe.recipeItemID,
							name = disp,
							icon = ns.ItemIcon(recipe.outputItemID or recipe.recipeItemID, 134939),
							category = pObj and pObj.full or recipe.prof,
							prof = recipe.prof,
							rep = effRep,
							repName = ns.STANDING_NAMES[effRep] or "Neutral",
							repSort = effRep * 1000 + recipe.skill,
							skill = recipe.skill,
							sellable = sellable,
							sellableSort = sellable and 1 or 0,
							favorCost = recipe.favorCost,
							favorGoldCost = favorGold,
							craftProfit = craftProfit,
							dailySold = dailySold,
							unlock = unlock,
							unlockedNow = unlock.unlockedNow,
							statusText = statusText,
							statusSort = statusSort,
						}
					end
				end
			end
		end
	end

	local repOut = {
		repState = repState,
		favorBalance = ns.GetFavorBalance(),
		currentTotalRep = currentTotalRep,
		includeShippingLabel = includeShippingLabel,
		includeWritPouch = (bestWritPouch and bestWritPouch > 0) or false,
		writPouchCopper = bestWritPouch or 0,
		nearZeroWrits = nearZeroWrits or 0,
		bestWrit = bestWrit,
		bestCrate = bestCrate,
		milestones = milestones,
		unlocks = unlocks,
	}
	local ok, forgedRes = pcall(ns.BuildForgedDeliveryRows, {
		forgedMode = opts.forgedMode,
		humanDiplomacy = opts.humanDiplomacy,
		favorCrateKey = opts.favorCrateKey,
		favorCrateID = opts.favorCrateID,
		priceSource = opts.priceSource,
		subCraftMode = opts.subCraftMode,
		subCraftOverrides = opts.subCraftOverrides,
		crateMode = opts.crateMode,
		profFilter = "all",
		unlockFilter = "all",
		profMap = profMap,
		repState = repState,
	})
	ns.PopEvalOpts(evalTok)
	ns.EndEval()
	if not ok then error(forgedRes, 0) end
	repOut.forgedSummary = {
		bestSelfFundedRow = forgedRes.bestSelfFunded,
		bestBankedRow = forgedRes.bestBanked,
		bestSelfFunded = forgedRes.bestSelfFunded,
		bestBanked = forgedRes.bestBanked,
		bestFavorCrate = forgedRes.bestFavorCrate,
		repMult = forgedRes.repMult,
		baseRep = forgedRes.baseRep,
		effectiveRep = forgedRes.effectiveRep,
		favorRequired = forgedRes.favorRequired,
		forgedRefund = forgedRes.forgedRefund,
		forgedMode = forgedRes.forgedMode,
		favorCost = forgedRes.favorCost,
		favorGrossCost = forgedRes.favorGrossCost,
		favorCashback = forgedRes.favorCashback,
		favorCostPerFavor = forgedRes.favorCostPerFavor,
		availableCount = forgedRes.meta and forgedRes.meta.availableCount or 0,
		totalCrates = forgedRes.meta and forgedRes.meta.totalCrates or 0,
		rows = forgedRes.rows,
	}
	return repOut
end

---------------------------------------------------------------------------------------------------
-- 5. Waylaid Crate Hover Tooltip Data Builder (O(1) Memoized)

local function serializeOverridesSig(overrides)
	if type(overrides) ~= "table" then return "" end
	local keys = {}
	for k in pairs(overrides) do
		keys[#keys + 1] = k
	end
	if #keys == 0 then return "" end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for i = 1, #keys do
		local k = keys[i]
		parts[i] = tostring(k) .. "=" .. tostring(overrides[k])
	end
	return table.concat(parts, ",")
end

local function buildDynamicBundlesSig(bundles)
	local parts = {}
	for i, b in ipairs(bundles) do
		local qty = tonumber(b.qty or b.count) or 1
		parts[i] = tostring(b.itemID or "") .. ":" .. tostring(b.name or "") .. "x" .. tostring(qty)
	end
	return table.concat(parts, ";")
end

local function sortCrateTooltipBundles(a, b)
	local aPriced = a.bundleTotal ~= nil
	local bPriced = b.bundleTotal ~= nil
	if aPriced ~= bPriced then
		return aPriced
	end
	if aPriced then
		local am = a.missingCost
		local bm = b.missingCost
		if am ~= nil and bm ~= nil and am ~= bm then
			return am < bm
		end
		if a.bundleTotal ~= b.bundleTotal then
			return a.bundleTotal < b.bundleTotal
		end
		return (a.name or "") < (b.name or "")
	end
	local aRatio = (a.qty and a.qty > 0) and (a.missing / a.qty) or 1
	local bRatio = (b.qty and b.qty > 0) and (b.missing / b.qty) or 1
	if aRatio ~= bRatio then
		return aRatio < bRatio
	end
	return (a.name or "") < (b.name or "")
end

function ns.BuildCrateTooltipData(target, opts)
	local crate, sealed, dynamic
	if type(target) == "number" then
		crate = ns.CRATE_BY_ID[target]
		if not crate then
			sealed = ns.SEALED_CRATE_BY_ID[target]
		end
		if not crate and not sealed then
			return nil
		end
	elseif type(target) == "table" then
		if target.sealed and target.itemID and ns.SEALED_CRATE_BY_ID[target.itemID] then
			sealed = ns.SEALED_CRATE_BY_ID[target.itemID]
		elseif target.sealed and target.tier then
			sealed = target
		elseif target.itemID and ns.CRATE_BY_ID[target.itemID]
			and (target == ns.CRATE_BY_ID[target.itemID] or type(target.bundles) ~= "table") then
			crate = ns.CRATE_BY_ID[target.itemID]
		elseif type(target.bundles) == "table" and #target.bundles > 0 then
			dynamic = target
		elseif target.itemID and ns.SEALED_CRATE_BY_ID[target.itemID] then
			sealed = ns.SEALED_CRATE_BY_ID[target.itemID]
		else
			return nil
		end
	else
		return nil
	end

	opts = opts or {}
	local db = ns.GetDB()
	local crateMode = opts.crateMode or "cheapest"
	local subCraftMode = opts.subCraftMode or "smart"
	local subCraftOverrides = opts.subCraftOverrides
	local forgedMode = (opts.forgedMode == "banked") and "banked" or "self_funded"
	local humanDiplomacy = opts.humanDiplomacy
	local priceVersion = (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion()) or ns.priceCacheEpoch or 1
	local priceSource = (ns.GetEffectivePriceSource and ns.GetEffectivePriceSource()) or (db and db.priceSource) or "auto"
	local rawEconOpt = opts.economy
	local econInfo = ns.CurrentEconomyInfo()
	local economyKey = (rawEconOpt and rawEconOpt ~= "auto" and tostring(rawEconOpt))
		or (econInfo and (econInfo.effectiveKey or econInfo.selectedKey))
		or "auto"

	local targetKey
	local dynamicSig = ""
	if crate then
		targetKey = "c:" .. tostring(crate.itemID)
	elseif sealed then
		targetKey = "s:" .. tostring(sealed.itemID)
	else
		targetKey = "d:" .. tostring(dynamic.itemID or dynamic.name or "dynamic")
		dynamicSig = buildDynamicBundlesSig(dynamic.bundles)
	end

	local ownershipSig
	if opts.ownershipRev ~= nil then
		ownershipSig = tostring(opts.ownershipRev)
	elseif not sealed and type(opts.ownedCounts) == "table" and next(opts.ownedCounts) ~= nil then
		local srcBundles = (crate and crate.bundles) or (dynamic and dynamic.bundles)
		local ownParts = {}
		for i, b in ipairs(srcBundles) do
			local bID = b.itemID or (b.name and ns.ITEM_IDS_BY_NAME and ns.ITEM_IDS_BY_NAME[b.name])
			local dispName = bID and ns.ItemName(bID, b.name) or b.name
			local cnt = (dispName and opts.ownedCounts[dispName]) or (b.name and opts.ownedCounts[b.name]) or 0
			ownParts[i] = tostring(cnt)
		end
		ownershipSig = table.concat(ownParts, ",")
	else
		ownershipSig = "0"
	end

	local sigRest = table.concat({
		dynamicSig,
		tostring(priceVersion),
		tostring(priceSource),
		ownershipSig,
		tostring(crateMode),
		tostring(subCraftMode),
		serializeOverridesSig(subCraftOverrides),
		tostring(forgedMode),
		tostring(humanDiplomacy),
		tostring(economyKey),
		tostring(opts.favorCrateKey or ""),
		tostring(opts.favorCrateID or ""),
		tostring(opts.craftableAllChars or ""),
		tostring(opts.knownRecipesOnly or ""),
	}, "\031")

	local cached = crateTooltipMemo[targetKey]
	if cached and cached.sig == sigRest then
		return cached.result
	end

	local prevEcon = db and db.economy
	local econChanged = rawEconOpt ~= nil and db ~= nil and rawEconOpt ~= prevEcon
		and ns.ECONOMY_BY_KEY ~= nil and ns.ECONOMY_BY_KEY[rawEconOpt] ~= nil
	local parentDepth, parentCache = evalDepth, ns._evalCache
	local evalTok = nil

	local ok, result = pcall(function()
		if econChanged then
			db.economy = rawEconOpt
			ns._evalCache = nil
		end
		ns.BeginEval()

		local profMap = opts.profMap or ns.GetPlayerProfessions()
		local repState = opts.repState or ns.GetMerchantReputation()
		local evalOpts = {
			crateMode = crateMode,
			subCraftMode = subCraftMode,
			subCraftOverrides = subCraftOverrides,
			ownedCounts = opts.ownedCounts,
			profMap = profMap,
			repState = repState,
			forgedMode = forgedMode,
			humanDiplomacy = humanDiplomacy,
			favorCrateKey = opts.favorCrateKey,
			favorCrateID = opts.favorCrateID,
			craftableAllChars = opts.craftableAllChars,
			knownRecipesOnly = opts.knownRecipesOnly,
			unlockFilter = opts.unlockFilter or "all",
			profFilter = opts.profFilter or "all",
			currentCharOnly = opts.currentCharOnly,
		}
		evalTok = ns.PushEvalOpts(evalOpts)

		local activeEcon = ns.CurrentEconomyInfo()
		local economyLabel = activeEcon and (activeEcon.label or activeEcon.effectiveKey) or ""

		local crateID, name, shortName, tier, quality
		if crate then
			crateID = crate.itemID
			name = ns.ItemName(crateID, crate.name)
			shortName = name:gsub("^Waylaid Crate:%s*", "")
			tier = crate.tier
			quality = crate.quality
		elseif sealed then
			crateID = sealed.itemID
			name = ns.ItemName(crateID, (type(target) == "table" and target.name) or "Sealed Waylaid Crate")
			shortName = name:gsub("^Sealed Waylaid Crate:%s*", "")
			tier = sealed.tier
			quality = sealed.quality
		else
			crateID = dynamic.itemID
			name = (crateID and ns.ItemName(crateID, dynamic.name)) or dynamic.name or "Waylaid Crate"
			shortName = name:gsub("^Waylaid Crate:%s*", "")
			tier = dynamic.tier or name:match("Apprentice") or name:match("Journeyman")
				or name:match("Expert") or name:match("Artisan")
			quality = dynamic.quality
		end

		local bundles = {}
		if not sealed then
			local srcBundles = (crate and crate.bundles) or (dynamic and dynamic.bundles) or {}
			local counts = opts.ownedCounts or {}
			local craftOptions = {
				profMap = profMap,
				subCraftMode = subCraftMode,
				subCraftOverrides = subCraftOverrides,
				craftableAllChars = opts.craftableAllChars,
				knownRecipesOnly = opts.knownRecipesOnly,
				unlockFilter = opts.unlockFilter,
				currentCharOnly = opts.currentCharOnly,
			}

			for _, b in ipairs(srcBundles) do
				local qty = tonumber(b.qty or b.count) or 1
				local bItemID = b.itemID or (b.name and ns.ITEM_IDS_BY_NAME and ns.ITEM_IDS_BY_NAME[b.name]) or nil
				local displayName = bItemID and ns.ItemName(bItemID, b.name) or (b.name or "Unknown")

				local buyEach, buySource
				if bItemID and bItemID > 0 then
					buyEach, buySource = ns.GetItemMarketPrice(bItemID)
				end
				local buyTotal = buyEach and (buyEach * qty) or nil

				craftOptions.parentProf = b.prof
				local craftOpt = (bItemID and ns.GetItemCraftOption) and ns.GetItemCraftOption(bItemID, craftOptions) or nil
				local craftEach = craftOpt and craftOpt.unitCraftCost or nil
				local craftTotal = craftEach and (craftEach * qty) or nil
				local craftSource = craftOpt and ("Craft (" .. craftOpt.profLabel .. ")") or nil

				local unitCost, bundleTotal, mode, source
				if crateMode == "buy" then
					unitCost, bundleTotal, source = buyEach, buyTotal, buySource
					mode = buyTotal and "Buy" or "—"
				elseif crateMode == "craft" then
					unitCost, bundleTotal, source = craftEach, craftTotal, craftSource
					mode = craftTotal and "Craft" or "—"
				else
					local ov = bItemID and subCraftOverrides and subCraftOverrides[bItemID] or nil
					if ov == "craft" and craftTotal then
						unitCost, bundleTotal, source, mode = craftEach, craftTotal, craftSource, "Craft"
					elseif ov == "buy" and buyTotal then
						unitCost, bundleTotal, source, mode = buyEach, buyTotal, buySource, "Buy"
					elseif craftTotal and buyTotal then
						if craftTotal <= buyTotal then
							unitCost, bundleTotal, source, mode = craftEach, craftTotal, craftSource, "Craft"
						else
							unitCost, bundleTotal, source, mode = buyEach, buyTotal, buySource, "Buy"
						end
					elseif craftTotal then
						unitCost, bundleTotal, source, mode = craftEach, craftTotal, craftSource, "Craft"
					elseif buyTotal then
						unitCost, bundleTotal, source, mode = buyEach, buyTotal, buySource, "Buy"
					else
						unitCost, bundleTotal, source, mode = nil, nil, nil, "—"
					end
				end

				local owned = counts[displayName] or (b.name and counts[b.name]) or 0
				local missing = math.max(0, qty - owned)
				local missingCost = unitCost and (unitCost * missing) or nil

				bundles[#bundles + 1] = {
					itemID = bItemID,
					name = displayName,
					englishName = b.name,
					qty = qty,
					prof = b.prof,
					skill = b.skill,
					buyEach = buyEach,
					buyTotal = buyTotal,
					buySource = buySource,
					craftEach = craftEach,
					craftTotal = craftTotal,
					craftOpt = craftOpt,
					unitCost = unitCost,
					bundleTotal = bundleTotal,
					mode = mode,
					source = source,
					owned = owned,
					missing = missing,
					missingCost = missingCost,
					isBest = false,
				}
			end

			table.sort(bundles, sortCrateTooltipBundles)
			if bundles[1] then
				bundles[1].isBest = (bundles[1].bundleTotal ~= nil) or false
			end
		end

		local tokens, rewardCopper, unconfirmed
		if crate then
			tokens, rewardCopper, unconfirmed = ns.GetCrateReward(crate)
		elseif sealed then
			tokens, rewardCopper, unconfirmed = ns.GetCrateReward({ tier = sealed.tier, quality = sealed.quality })
			if (not tokens or tokens == 0) and sealed.tokens then
				tokens = sealed.tokens
			end
			if (rewardCopper == nil or rewardCopper == 0) and sealed.copper ~= nil then
				rewardCopper = sealed.copper
			end
			if unconfirmed == nil then
				unconfirmed = sealed.unconfirmed
			end
		elseif tier and quality then
			tokens, rewardCopper, unconfirmed = ns.GetCrateReward({ tier = tier, quality = quality })
		else
			tokens = dynamic.tokens or 0
			rewardCopper = dynamic.copper or 0
			unconfirmed = dynamic.unconfirmed
		end

		local emptyPrice, emptySource
		if crateID and not sealed then
			emptyPrice, emptySource = ns.GetItemMarketPrice(crateID)
		end

		local bestBundle = bundles[1]
		local fillCost = (sealed and 0) or (bestBundle and bestBundle.bundleTotal or nil)
		local missingFillCost = (sealed and 0) or (bestBundle and bestBundle.missingCost or nil)
		local grossFilledCost = (emptyPrice ~= nil and fillCost ~= nil) and (emptyPrice + fillCost) or nil
		local netFilledCost = (grossFilledCost ~= nil) and (grossFilledCost - (rewardCopper or 0)) or nil
		local fillOnlyNetCost = (fillCost ~= nil) and (fillCost - (rewardCopper or 0)) or nil
		local pricePerToken = (netFilledCost ~= nil and tokens and tokens > 0) and (netFilledCost / tokens) or nil

		local receipt = ns.FORGED_RECEIPT or {}
		local favorRequired = tonumber(receipt.favorCost) or 15
		local forgedRefund = tonumber(receipt.refundCopper) or 100
		local baseRep = tonumber(receipt.baseRep) or 50
		local repMult = ns.GetRacialRepMultiplier(humanDiplomacy)
		local forgedRep = math.floor(baseRep * repMult + 0.5)
		local isHuman = repMult > 1.0
		local receiptsFromFavor = (tokens and tokens > 0) and (tokens / favorRequired) or 0
		local equivRepFromFavor = (tokens and tokens > 0) and (tokens * forgedRep / favorRequired) or 0

		local bestFavorCrate = (not sealed) and getForgedFavorCrate(evalOpts) or nil
		local favorCostPerFavor = bestFavorCrate and bestFavorCrate.costPerFavor or nil
		local feederName = bestFavorCrate and bestFavorCrate.crateName or nil
		local sfFavorCost = favorCostPerFavor and (favorRequired * favorCostPerFavor) or nil

		local bankedNetCost = (emptyPrice ~= nil) and (emptyPrice - forgedRefund) or nil
		local bankedCostPerRep = (bankedNetCost ~= nil and forgedRep > 0) and (bankedNetCost / forgedRep) or nil
		local selfFundedNetCost = (bankedNetCost ~= nil and sfFavorCost ~= nil) and (bankedNetCost + sfFavorCost) or nil
		local selfFundedCostPerRep = (selfFundedNetCost ~= nil and forgedRep > 0)
			and (selfFundedNetCost / forgedRep) or nil
		local activeNetTurnIn = (forgedMode == "banked") and bankedNetCost or selfFundedNetCost
		local activeCostPerRep = (forgedMode == "banked") and bankedCostPerRep or selfFundedCostPerRep

		local bankedNetCostExCrate = -forgedRefund
		local bankedCostPerRepExCrate = (forgedRep > 0) and (bankedNetCostExCrate / forgedRep) or nil
		local selfFundedNetCostExCrate = (sfFavorCost ~= nil) and (sfFavorCost - forgedRefund) or nil
		local selfFundedCostPerRepExCrate = (selfFundedNetCostExCrate ~= nil and forgedRep > 0)
			and (selfFundedNetCostExCrate / forgedRep) or nil
		local activeNetTurnInExCrate = (forgedMode == "banked") and bankedNetCostExCrate or selfFundedNetCostExCrate
		local activeCostPerRepExCrate = (forgedMode == "banked") and bankedCostPerRepExCrate or selfFundedCostPerRepExCrate

		return {
			kind = sealed and "sealed" or (crate and "crate" or "dynamic"),
			crateID = crateID,
			name = name,
			shortName = shortName,
			tier = tier,
			quality = quality,
			economyLabel = economyLabel,
			tokens = tokens,
			rewardCopper = rewardCopper,
			unconfirmed = unconfirmed,
			emptyPrice = emptyPrice,
			emptySource = emptySource,
			bundles = bundles,
			bestBundle = bestBundle,
			fillCost = fillCost,
			missingFillCost = missingFillCost,
			grossFilledCost = grossFilledCost,
			netFilledCost = netFilledCost,
			fillOnlyNetCost = fillOnlyNetCost,
			pricePerToken = pricePerToken,
			favorRequired = favorRequired,
			forgedRefund = forgedRefund,
			baseRep = baseRep,
			repMult = repMult,
			isHuman = isHuman,
			forgedRep = forgedRep,
			receiptsFromFavor = receiptsFromFavor,
			equivRepFromFavor = equivRepFromFavor,
			forgedMode = forgedMode,
			feederName = feederName,
			favorCostPerFavor = favorCostPerFavor,
			sfFavorCost = sfFavorCost,
			selfFundedNetCost = selfFundedNetCost,
			selfFundedCostPerRep = selfFundedCostPerRep,
			bankedNetCost = bankedNetCost,
			bankedCostPerRep = bankedCostPerRep,
			activeNetTurnIn = activeNetTurnIn,
			activeCostPerRep = activeCostPerRep,
			selfFundedNetCostExCrate = selfFundedNetCostExCrate,
			selfFundedCostPerRepExCrate = selfFundedCostPerRepExCrate,
			bankedNetCostExCrate = bankedNetCostExCrate,
			bankedCostPerRepExCrate = bankedCostPerRepExCrate,
			activeNetTurnInExCrate = activeNetTurnInExCrate,
			activeCostPerRepExCrate = activeCostPerRepExCrate,
		}
	end)

	ns.PopEvalOpts(evalTok)
	while evalDepth > parentDepth do
		ns.EndEval()
	end
	if econChanged then
		db.economy = prevEcon
		ns._evalCache = parentCache
	end
	if not ok then
		error(result, 0)
	end

	crateTooltipMemo[targetKey] = {
		sig = sigRest,
		result = result,
	}
	return result
end
