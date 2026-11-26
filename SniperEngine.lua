-- SniperEngine.lua
-- All-Items 2-Stage Gap Sniper & Vendor Sniper engine for MerchantMaster (WoW Forever).
-- Supports commodities, equipment, recipes, and all Auction House items.
-- Self-contained math, snapshot/live valuation, browse ingestion, and WoW Forever
-- protected two-click commodity / sequential PlaceBid purchase state machine.
--
-- IMPORTANT:
-- * NEVER calls Analytics.Store.Append (Analytics/Capture.lua already hooks
--   StartCommoditiesPurchase, ConfirmCommoditiesPurchase, and PlaceBid).
-- * Protected purchase APIs (StartCommoditiesPurchase, ConfirmCommoditiesPurchase,
--   PlaceBid) are invoked strictly synchronously from user button OnClick handlers.
-- * Pure ASCII only (passes tools/check_glyphs.py with 0 violations).

local ADDON, ns = ...
ns = ns or {}

local SE = {}
ns.SniperEngine = SE

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

SE.FOREVER_MIN_DEPOSIT = 100          -- 1s floor (100c) on WoW Forever
SE.FOREVER_FACTION_DEPOSIT_RATE = 5   -- 5% per 2h (5% / 20% / 60% for 2h / 8h / 24h)
SE.FOREVER_NEUTRAL_DEPOSIT_RATE = 25  -- 25% per 2h (25% / 100% / 300% for 2h / 8h / 24h)
SE.FACTION_AH_CUT = 0.05
SE.NEUTRAL_AH_CUT = 0.15
SE.QUOTE_TIMEOUT = 30                 -- WoW Forever slow-house commodity quote timeout (s)
SE.BUY_WATCHDOG_TIMEOUT = 15          -- Watchdog timeout for PlaceBid buyouts (s)
SE.LIVE_CHECK_TTL = 15                -- Verified live vendor check lifetime (s)
SE.SEARCH_TIMEOUT = 10                -- Live item/commodity search timeout (s)
SE.WEDGE_VALVE_SECONDS = 10           -- Release IsThrottledMessageSystemReady wedge after 10s
SE.MAX_COMMODITY_PAGES = 1            -- Page 1 already holds cheapest 50-100 tiers/listings
SE.BROWSE_FRESH_TTL = 60              -- Skip Stage 1 browse sweep if swept < 60s ago
SE.DRILL_CACHE_TTL = 120              -- Skip re-drilling unchanged (minPrice, totalQty) within 120s
SE.MAX_VENDOR_LOAD_PRICE = 500000     -- 50g ceiling above any Classic vendor sell price (skip load flood)

local VALID_GAP_SCOPES = {
	all = true,
	commodities = true,
	items = true,
}

-- Neutral (Blackwater / Goblin) Auction House uiMapIDs (Classic + Modern IDs).
local NEUTRAL_AH_MAP_IDS = {
	[1413] = true, -- The Barrens (Ratchet) Classic
	[1434] = true, -- Stranglethorn Vale (Booty Bay) Classic
	[1446] = true, -- Tanaris (Gadgetzan) Classic
	[1452] = true, -- Winterspring (Everlook) Classic
	[10]   = true, -- Northern Barrens (Ratchet) Modern
	[50]   = true, -- Cape of Stranglethorn (Booty Bay) Modern
	[210]  = true, -- Cape of Stranglethorn (Booty Bay alt)
	[71]   = true, -- Tanaris (Gadgetzan) Modern
	[83]   = true, -- Winterspring (Everlook) Modern
}

local DEFAULTS = {
	-- Gap Sniper (WoW Forever tuned)
	gapScope = "all",                 -- "all" | "commodities" | "items"
	minGapPct = 15,
	minRoiPct = 15,
	minProfitCopper = 10000,          -- 1g
	maxSpendCopper = 5000000,         -- 500g (0 = character available gold)
	maxBuyShareDailyPct = 50,         -- Flipping Pal liquidity cap (% of dailySold)
	minDailySales = 1,                -- Minimum units sold/day
	minQty = 2,                       -- Anti-bait unit floor (commodities only; items default to 1)
	maxQty = 200,                     -- Per-snipe unit cap (0 = unlimited)
	buyCeilingPct = 95,               -- Max buy % of conservative reference price
	minQuality = 1,                   -- 1 = Common+ (skip grey Poor vendor trash)
	fastSellersFirst = true,          -- Sort shortlist descending by discount % x velocity
	maxShortlistItems = 120,          -- Max items queued for live gap scan
	tolerancePct = 5,                 -- Quote slippage tolerance %
	relistDurationHours = 8,          -- Default Forever listing duration (2 / 8 / 24)
	-- Vendor Sniper
	vendorMinProfitCopper = 1000,     -- 10s default min profit per unit
	vendorIncludeCommodities = true,
	vendorAutoFromBrowse = true,
	vendorMaxSpendCopper = 0,         -- 0 = character available gold
	vendorMaxQty = 0,                 -- 0 = all profitable units
}

-------------------------------------------------------------------------------
-- Runtime State
-------------------------------------------------------------------------------

SE.atAH = false
SE.browseCache = {}       -- [keySig] = { sig, itemID, itemKey, minPrice, totalQuantity, itemLink, quality, isCommodity, economy, updatedAt }
SE.drillCache = {}        -- [keySig] = { minPrice, totalQuantity, drilledAt }
SE.gapDeals = {}          -- array of evaluated gap deal tables
SE.gapDealsByKey = {}     -- [idKey] = deal
SE.vendorDeals = {}       -- array of vendor deal tables
SE.vendorDealsByKey = {}  -- [idKey] = deal
SE.unresolvedVendor = {}  -- [cacheKey] = pending row awaiting GET_ITEM_INFO_RECEIVED
SE.purchase = nil         -- active protected purchase state machine
SE.pendingCheck = nil     -- active live Check search (vendor or snapshot gap item)
SE.scan = {
	active = false,
	phase = "idle",         -- "idle" | "browse" | "drill"
	awaitingBrowse = false,
	startedBrowse = false,
	browseSeen = 0,
	browseStartMono = nil,
	lastBrowseAt = nil,
	lastBrowseEcon = nil,
	lastCompleteBrowseStart = nil,
	shortlist = {},
	shortlistByID = {},
	shortlistByKey = {},
	index = 0,
	total = 0,
	scanned = 0,
	dealsFound = 0,
	awaitingItemID = nil,
	awaitingKeySig = nil,
	awaitingItemKey = nil,
	awaitingPages = 0,
	lastEmptyReason = nil,
	statusText = "Idle",
}
SE.session = {
	buys = 0,
	spent = 0,
	estProfit = 0,
	gapDealsFound = 0,
	vendorDealsFound = 0,
}

local neutralCache = nil
local notReadySince = nil
local fallbackSettings = nil
local uiListener = nil
local eventFrame = nil
local checkSeq = 0
local scanSeq = 0
local unresolvedVendorByID = {}
local vendorDealsDirty = false

-------------------------------------------------------------------------------
-- Secret-Value Safety & Utility Helpers
-------------------------------------------------------------------------------

local function isReadable(v)
	if _G.issecretvalue and _G.issecretvalue(v) then
		return false
	end
	if type(v) == "table" and _G.issecrettable and _G.issecrettable(v) then
		return false
	end
	return true
end

local function safeNumber(v)
	if not isReadable(v) then return nil end
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return nil end
		return v
	end
	if t == "string" then
		local n = tonumber(v)
		if n and n == n and n ~= math.huge and n ~= -math.huge then
			return n
		end
	end
	return nil
end

local function safeString(v)
	if not isReadable(v) then return nil end
	if type(v) == "string" then return v end
	return nil
end

local function safeBool(v)
	if not isReadable(v) then return nil end
	if type(v) == "boolean" then return v end
	return nil
end

local function safeTable(v)
	if not isReadable(v) then return nil end
	if type(v) == "table" then return v end
	return nil
end

local function nowMono()
	if type(_G.GetTime) == "function" then
		local ok, t = pcall(_G.GetTime)
		local n = ok and safeNumber(t) or nil
		if n then return n end
	end
	if type(_G.time) == "function" then
		local ok, t = pcall(_G.time)
		local n = ok and safeNumber(t) or nil
		if n then return n end
	end
	return 0
end

local function nowEpoch()
	if type(_G.time) == "function" then
		local ok, t = pcall(_G.time)
		local n = ok and safeNumber(t) or nil
		if n then return n end
	end
	return 0
end

local function afterDelay(seconds, fn)
	if _G.C_Timer and type(_G.C_Timer.After) == "function" then
		pcall(_G.C_Timer.After, seconds, fn)
		return true
	end
	return false
end

local function notify(eventName, payload)
	if type(uiListener) == "function" then
		pcall(uiListener, eventName, payload)
	end
end

local function setStatusText(text)
	SE.scan.statusText = text or ""
	notify("status", SE.scan.statusText)
end

local function getPlayerMoney()
	if type(_G.GetMoney) ~= "function" then return nil end
	local ok, m = pcall(_G.GetMoney)
	if not ok then return nil end
	return safeNumber(m)
end

local function activeEconomy(econOverride)
	local s = safeString(econOverride)
	if s and s ~= "" then return s end
	if type(ns.DetectActiveEconomy) == "function" then
		local ok, econ = pcall(ns.DetectActiveEconomy)
		local es = ok and safeString(econ) or nil
		if es and es ~= "" then return es end
	end
	return "Forever-EU"
end

local function isAHOpen()
	if SE.atAH then return true end
	local f = _G.AuctionHouseFrame or _G.AuctionFrame
	if safeTable(f) and type(f.IsShown) == "function" then
		local ok, shown = pcall(f.IsShown, f)
		if ok and safeBool(shown) == true then
			SE.atAH = true
			return true
		end
	end
	return false
end

local function isAHBusyForSniper(allowMarketScan)
	local ch = safeTable(ns.AHChannel)
	if ch and type(ch.IsBusy) == "function" then
		local ok, busy = pcall(ch.IsBusy, "sniper")
		if ok and safeBool(busy) == true then
			if allowMarketScan and type(ch.GetOwner) == "function" then
				local okO, own = pcall(ch.GetOwner)
				if okO and safeString(own) == "market_scan" then
					return false
				end
			end
			return true
		end
	end
	return false
end

local function isCartBuyerConfirming()
	local ch = safeTable(ns.AHChannel)
	if ch and type(ch.GetOwner) == "function" then
		local okO, owner = pcall(ch.GetOwner)
		if okO and safeString(owner) == "cart_buyer" then
			return true
		end
	end
	local app = safeTable(ns.app)
	local cb = app and safeTable(app.cartBuyer)
	if cb and type(cb.IsPurchaseInFlight) == "function" then
		local okF, inFlight = pcall(cb.IsPurchaseInFlight)
		if okF and safeBool(inFlight) == true then
			return true
		end
	end
	if cb and type(cb.GetState) == "function" then
		local ok, st = pcall(cb.GetState)
		if ok then
			local stTbl = safeTable(st)
			if stTbl and (stTbl.pendingExternal ~= nil
				or stTbl.directBuy ~= nil
				or safeString(stTbl.step) == "awaiting_confirm") then
				return true
			end
		end
	end
	return false
end

local function isCartBuyerActive(allowMarketScan)
	if isAHBusyForSniper(allowMarketScan) then
		return true
	end
	if isCartBuyerConfirming() then
		return true
	end
	local app = safeTable(ns.app)
	local cb = app and safeTable(app.cartBuyer)
	if cb and type(cb.GetState) == "function" then
		local ok, st = pcall(cb.GetState)
		if ok then
			local stTbl = safeTable(st)
			if stTbl and (safeBool(stTbl.active) == true
				or stTbl.pendingExternal ~= nil
				or stTbl.directBuy ~= nil
				or safeString(stTbl.step) == "awaiting_confirm") then
				return true
			end
		end
	end
	return false
end

local function acquireSniperChannel(kind)
	local ch = safeTable(ns.AHChannel)
	if ch and type(ch.TryAcquire) == "function" then
		local ok, acquired, err = pcall(ch.TryAcquire, "sniper", { kind = kind, preemptScan = true })
		if not ok then
			return false, "channel_error"
		end
		if acquired ~= true then
			if type(ch.GetOwner) == "function" then
				local okO, own = pcall(ch.GetOwner)
				if okO and safeString(own) == "cart_buyer" then
					return false, "cart_buyer_busy"
				end
			end
			return false, safeString(err) or "ah_busy"
		end
	end
	return true, nil
end

local function releaseSniperChannel()
	local ch = safeTable(ns.AHChannel)
	if ch and type(ch.Release) == "function" then
		pcall(ch.Release, "sniper")
	end
end

local function isThrottledReady()
	local ah = _G.C_AuctionHouse
	if not (safeTable(ah) and type(ah.IsThrottledMessageSystemReady) == "function") then
		notReadySince = nil
		return true
	end
	local ok, ready = pcall(ah.IsThrottledMessageSystemReady)
	local b = ok and safeBool(ready)
	if b ~= false then
		notReadySince = nil
		return true
	end
	local now = nowMono()
	if not notReadySince then
		notReadySince = now
		return false
	end
	if (now - notReadySince) >= SE.WEDGE_VALVE_SECONDS then
		return true
	end
	return false
end

local function priceSortSpec()
	local enum = _G.Enum
	if safeTable(enum) and safeTable(enum.AuctionHouseSortOrder)
		and enum.AuctionHouseSortOrder.Price ~= nil then
		return { { sortOrder = enum.AuctionHouseSortOrder.Price, reverseSort = false } }
	end
	return {}
end

local function readItemInfoSafe(query)
	if query == nil then return nil end
	local fn = (safeTable(_G.C_Item) and _G.C_Item.GetItemInfo) or _G.GetItemInfo
	if type(fn) ~= "function" then return nil end
	local ok, name, link, quality, _, _, _, _, maxStack, _, icon, sellPrice = pcall(fn, query)
	if not ok then return nil end
	local sName = safeString(name)
	if not sName then return nil end
	local sSell = safeNumber(sellPrice)
	local sStack = safeNumber(maxStack)
	return {
		name = sName,
		link = safeString(link),
		quality = safeNumber(quality),
		maxStack = sStack and math.max(1, math.floor(sStack)) or nil,
		icon = isReadable(icon) and icon or nil,
		sellPrice = sSell and math.max(0, math.floor(sSell)) or nil,
	}
end

local function isKnownNonCommodity(itemID, itemKey, cachedIsComm)
	if cachedIsComm == false then return true end
	if cachedIsComm == true then return false end
	-- Fast zero-miss local lookup via C_Item.GetItemInfoInstant before AH/GetItemInfo calls
	local cItem = safeTable(_G.C_Item)
	local instantFn = (cItem and cItem.GetItemInfoInstant) or _G.GetItemInfoInstant
	if type(instantFn) == "function" then
		local okInst, _, _, _, equipLoc, _, classID = pcall(instantFn, itemID)
		if okInst then
			local cid = safeNumber(classID)
			local eloc = safeString(equipLoc)
			if (eloc and eloc ~= "" and eloc ~= "INVTYPE_NON_EQUIP" and eloc ~= "INVTYPE_NON_EQUIP_IGNORE")
				or cid == 1 or cid == 2 or cid == 4 or cid == 11 or cid == 17 then
				return true
			end
		end
	end
	local ah = safeTable(_G.C_AuctionHouse)
	if ah and type(ah.GetItemKeyInfo) == "function" then
		local key = safeTable(itemKey)
		if not key then
			if type(ah.MakeItemKey) == "function" then
				local okK, k = pcall(ah.MakeItemKey, itemID, 0, 0, 0)
				if okK then key = safeTable(k) end
			end
			if not key then
				key = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
			end
		end
		local okI, info = pcall(ah.GetItemKeyInfo, key, true)
		local it = okI and safeTable(info) or nil
		if it then
			local ic = safeBool(it.isCommodity)
			if ic == false then return true end
			if ic == true then return false end
		end
	end
	local info = readItemInfoSafe(itemID)
	if info and info.maxStack ~= nil and info.maxStack == 1 then
		return true
	end
	return false
end

local function requestItemLoad(itemID)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return end
	if safeTable(_G.C_Item) and type(_G.C_Item.RequestLoadItemDataByID) == "function" then
		pcall(_G.C_Item.RequestLoadItemDataByID, id)
	elseif type(ns.RequestItemDataLoad) == "function" then
		pcall(ns.RequestItemDataLoad, id)
	end
end

local function getItemDisplayMeta(itemID, itemLink)
	local info = (itemLink and readItemInfoSafe(itemLink)) or readItemInfoSafe(itemID)
	if info then
		return info.name, info.icon, info.quality, info.link, info.sellPrice
	end
	local fallbackName = nil
	if type(ns.ItemName) == "function" then
		local ok, n = pcall(ns.ItemName, itemID)
		fallbackName = ok and safeString(n) or nil
	end
	return fallbackName or ("Item " .. tostring(itemID)), nil, nil, itemLink, nil
end

local function getBaseVendorSell(itemID)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return nil end
	if type(ns.GetVendorSellPrice) == "function" then
		local ok, v = pcall(ns.GetVendorSellPrice, id)
		local n = ok and safeNumber(v) or nil
		if n and n >= 0 then return math.floor(n) end
	end
	local info = readItemInfoSafe(id)
	if info and info.sellPrice ~= nil then
		return info.sellPrice
	end
	return nil
end

-- Verifies live vendor sell price for an itemLink first so scaled / random-suffix
-- BoEs are never mispriced by their base itemID. Falls back to base itemID only
-- when no itemLink is provided.
local function getLinkVerifiedVendorSell(itemID, itemLink, allowRequestLoad)
	local link = safeString(itemLink)
	if link and link ~= "" then
		local info = readItemInfoSafe(link)
		if info and info.sellPrice ~= nil then
			return info.sellPrice, true, false
		end
		-- Link exists but is not cached yet -> request load only when allowed; do NOT trust base ID.
		if allowRequestLoad ~= false then
			requestItemLoad(itemID)
			return nil, false, true
		end
		return nil, false, false
	end
	local base = getBaseVendorSell(itemID)
	if base ~= nil then
		return base, false, false
	end
	if allowRequestLoad ~= false then
		requestItemLoad(itemID)
		return nil, false, true
	end
	return nil, false, false
end

-------------------------------------------------------------------------------
-- Settings / Defaults (MerchantMasterDB.sniper)
-------------------------------------------------------------------------------

local function normalizeGapScope(value)
	local s = safeString(value)
	if s and VALID_GAP_SCOPES[s] then
		return s
	end
	return "all"
end

function SE.GetDefaults()
	local copy = {}
	for k, v in pairs(DEFAULTS) do
		copy[k] = v
	end
	return copy
end

function SE.GetSettings()
	local db = nil
	if type(ns.GetDB) == "function" then
		local ok, d = pcall(ns.GetDB)
		if ok then db = safeTable(d) end
	end
	if not db then
		db = safeTable(_G.MerchantMasterDB)
	end
	local tbl
	if db then
		if type(db.sniper) ~= "table" then
			db.sniper = {}
		end
		tbl = db.sniper
	else
		if not fallbackSettings then
			fallbackSettings = {}
		end
		tbl = fallbackSettings
	end
	if not tbl._foreverDefaultsV2 then
		if tbl.minGapPct == 20 then tbl.minGapPct = 15 end
		if tbl.minRoiPct == 25 then tbl.minRoiPct = 15 end
		if tbl.minProfitCopper == 100000 then tbl.minProfitCopper = 10000 end
		if tbl.maxShortlistItems == 250 then tbl.maxShortlistItems = 120 end
		tbl._foreverDefaultsV2 = true
	end
	for k, v in pairs(DEFAULTS) do
		if tbl[k] == nil then
			tbl[k] = v
		end
	end
	if not VALID_GAP_SCOPES[safeString(tbl.gapScope) or ""] then
		tbl.gapScope = "all"
	end
	return tbl
end

function SE.SetOption(key, value)
	if DEFAULTS[key] == nil then return false end
	local settings = SE.GetSettings()
	if type(DEFAULTS[key]) == "boolean" then
		settings[key] = (value == true)
	elseif type(DEFAULTS[key]) == "string" then
		local s = safeString(value)
		if not s then return false end
		if key == "gapScope" and not VALID_GAP_SCOPES[s] then
			return false
		end
		settings[key] = s
	else
		local n = safeNumber(value)
		if not n or n < 0 then return false end
		settings[key] = n
	end
	notify("settings", { key = key, value = settings[key] })
	return true
end

function SE.SetListener(fn)
	uiListener = (type(fn) == "function") and fn or nil
end

-------------------------------------------------------------------------------
-- WoW Forever Exact Deposit & Dynamic Neutral AH Detection
-------------------------------------------------------------------------------

function SE.ResetNeutralCache()
	neutralCache = nil
end

local function detectNeutralAHRaw()
	-- 1. Live NPC auctioneer faction check while interacting at the AH
	if type(_G.UnitExists) == "function" and type(_G.UnitFactionGroup) == "function" then
		local okEx, exists = pcall(_G.UnitExists, "npc")
		if okEx and safeBool(exists) == true then
			local okNpc, npcFaction = pcall(_G.UnitFactionGroup, "npc")
			local okPlr, playerFaction = pcall(_G.UnitFactionGroup, "player")
			local nf = okNpc and safeString(npcFaction) or nil
			local pf = okPlr and safeString(playerFaction) or nil
			if nf == "Neutral" then
				return true
			elseif nf and pf and nf ~= "" and pf ~= "" then
				return nf ~= pf
			end
		end
	end
	-- 2. Fallback uiMapID check for Blackwater / Goblin hubs
	if safeTable(_G.C_Map) and type(_G.C_Map.GetBestMapForUnit) == "function" then
		local okMap, mapID = pcall(_G.C_Map.GetBestMapForUnit, "player")
		local mid = okMap and safeNumber(mapID) or nil
		if mid and NEUTRAL_AH_MAP_IDS[mid] then
			return true
		end
	end
	return false
end

function SE.IsNeutralAH(forceRefresh)
	if not forceRefresh and neutralCache ~= nil then
		return neutralCache
	end
	local detected = detectNeutralAHRaw()
	if isAHOpen() then
		neutralCache = detected
	end
	return detected
end

function SE.GetDynamicAuctionCut(forceRefresh)
	return SE.IsNeutralAH(forceRefresh) and SE.NEUTRAL_AH_CUT or SE.FACTION_AH_CUT
end

-- Exact WoW Forever deposit formula:
--   deposit = max(100, floor(vendorSell * qty * rate * hours / 200))
--   rate = 25 (Blackwater neutral: 25%/100%/300%) or 5 (faction: 5%/20%/60%)
--   hours = 2, 8, or 24 (defaults to 8)
function SE.GetForeverAuctionDeposit(vendorSellCopper, qty, durationHours, isNeutral)
	local sell = math.max(0, math.floor(safeNumber(vendorSellCopper) or 0))
	local count = math.max(1, math.floor(safeNumber(qty) or 1))
	local hours = safeNumber(durationHours)
	if not hours or hours <= 0 then hours = 8 end
	local neutral
	if isNeutral ~= nil then
		neutral = (isNeutral == true)
	else
		neutral = SE.IsNeutralAH()
	end
	local rate = neutral and SE.FOREVER_NEUTRAL_DEPOSIT_RATE or SE.FOREVER_FACTION_DEPOSIT_RATE
	local raw = math.floor(sell * count * rate * hours / 200)
	return math.max(SE.FOREVER_MIN_DEPOSIT, raw)
end

ns.GetForeverAuctionDeposit = SE.GetForeverAuctionDeposit
ns.GetDynamicAuctionCut = SE.GetDynamicAuctionCut

-------------------------------------------------------------------------------
-- Snapshot Hydration & Multi-Source Valuation Helpers
-------------------------------------------------------------------------------

local function hydrateSnapshotItems(econOverride)
	local econ = activeEconomy(econOverride)
	if type(ns.QueryLocalSnapshot) == "function" then
		-- Trigger Pricing.lua lazy chunk parse into ns.snapshotParsed[resolvedKey]
		pcall(ns.QueryLocalSnapshot, 2447, econ)
	end
	local parsedMap = safeTable(ns.snapshotParsed)
	if not parsedMap then return nil, econ, nil end

	local bucket = safeTable(parsedMap[econ])
	local resolvedKey = econ
	if not bucket then
		local lowerEcon = econ:lower()
		for k, v in pairs(parsedMap) do
			if type(k) == "string" and k:lower() == lowerEcon and safeTable(v) then
				bucket = v
				resolvedKey = k
				break
			end
		end
	end
	if not bucket then
		-- Fallback: if Pricing normalized econ to a single hydrated bucket, pick the first with items
		for k, v in pairs(parsedMap) do
			local vt = safeTable(v)
			if vt and safeTable(vt.items) then
				bucket = vt
				resolvedKey = k
				break
			end
		end
	end
	if not bucket or not safeTable(bucket.items) then
		return nil, resolvedKey, nil
	end
	return bucket.items, resolvedKey, safeTable(bucket.meta)
end

function SE.GetSnapshotFreshness(econOverride, maxAgeSec)
	local pricing = safeTable(ns.Pricing)
	if pricing and type(pricing.IsSnapshotFresh) == "function" then
		local ok, fresh, ageSec, meta = pcall(pricing.IsSnapshotFresh, econOverride, maxAgeSec)
		if ok then
			return safeBool(fresh) == true, safeNumber(ageSec), safeTable(meta)
		end
	end
	return false, nil, nil
end

function SE.GetItemDemand(itemID, econOverride)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return 0, nil, nil, 0 end
	local econ = activeEconomy(econOverride)

	-- 1. Unified multi-source demand (on ns)
	if type(ns.GetMultiSourceDemand) == "function" then
		local ok, d = pcall(ns.GetMultiSourceDemand, id, econ)
		local dt = ok and safeTable(d) or nil
		if dt then
			local daily = safeNumber(dt.effectiveDailySold) or safeNumber(dt.dailySold)
			if daily and daily >= 0 then
				return daily, safeNumber(dt.saleRate), safeString(dt.demandSource), safeNumber(dt.confidence) or 0
			end
		end
	end

	-- 2. Snapshot hourly velocity (on ns.Pricing, obsHours >= 3 gate)
	local pricing = safeTable(ns.Pricing)
	if pricing and type(pricing.GetItemSnapshotVelocity) == "function" then
		local ok, vel = pcall(pricing.GetItemSnapshotVelocity, id, econ)
		local vt = ok and safeTable(vel) or nil
		if vt then
			local obs = safeNumber(vt.obsHours) or 0
			local est = safeNumber(vt.estDailySold)
			if obs >= 3 and est and est >= 0 then
				return est, nil, safeString(vt.source) or "snapshot_vel", safeNumber(vt.confidence) or 0
			end
		end
	end

	-- 3. Live AH local scan velocity fallback (requires >= 2 scan pairs, >= 15m span)
	local ms = safeTable(ns.MarketScan)
	if ms and type(ms.GetLocalVelocity) == "function" then
		local ok, vel = pcall(ms.GetLocalVelocity, id, econ)
		local vt = ok and safeTable(vel) or nil
		if vt then
			local pairsCount = safeNumber(vt.scanPairs) or 0
			local est = safeNumber(vt.clearsPerDay)
			if pairsCount >= 2 and est and est >= 0 then
				local confStr = safeString(vt.confidence)
				local confNum = (confStr == "High" and 3) or (confStr == "Med" and 2) or 1
				return est, nil, "Local", confNum
			end
		end
	end

	return 0, nil, nil, 0
end

local function resolveCurrentScanExcludeTs(itemID, econ, opts)
	local ot = safeTable(opts)
	if ot then
		local explicit = safeNumber(ot.currentScanAt) or safeNumber(ot.excludeTimestamp)
		if explicit and explicit > 0 then
			return explicit
		end
	end
	local db = safeTable(_G.MerchantMasterDB)
	local ahRoot = db and safeTable(db.ahPrices)
	local ahEcon = ahRoot and safeTable(ahRoot[econ])
	if not ahEcon then return nil end
	local scannedAt = safeNumber(ahEcon._scannedAt)
	local itemRec = safeTable(ahEcon[itemID])
	local itemAt = itemRec and safeNumber(itemRec.at) or nil
	if scannedAt and scannedAt > 0 and itemAt and itemAt > 0 then
		return math.max(scannedAt, itemAt)
	end
	if itemAt and itemAt > 0 then return itemAt end
	if scannedAt and scannedAt > 0 then return scannedAt end
	return nil
end

local function collectPriorLiveHistoryPrices(itemID, econ, excludeTs)
	local db = safeTable(_G.MerchantMasterDB)
	if not db then return nil end
	local ms = safeTable(ns.MarketScan)
	local prices = {}
	local seenTs = {}
	local seenDays = {}

	local histRoot = safeTable(db.ahHistory)
	local histEcon = histRoot and safeTable(histRoot[econ])
	local rawHist = histEcon and histEcon[itemID]
	local ring = nil
	if rawHist ~= nil then
		if ms and type(ms.ReadHistory) == "function" then
			local ok, decoded = pcall(ms.ReadHistory, rawHist)
			if ok then ring = safeTable(decoded) end
		else
			ring = safeTable(rawHist)
		end
	end
	if ring then
		for i = 1, #ring do
			local e = safeTable(ring[i])
			if e then
				local t = safeNumber(e.t)
				local p = safeNumber(e.p)
				if t and t > 0 and p and p > 0 then
					if (not excludeTs or t < excludeTs) and not seenTs[t] then
						seenTs[t] = true
						seenDays[math.floor(t / 86400)] = true
						prices[#prices + 1] = p
					end
				end
			end
		end
	end

	local dailyRoot = safeTable(db.ahDaily)
	local dailyEcon = dailyRoot and safeTable(dailyRoot[econ])
	local rawDaily = dailyEcon and dailyEcon[itemID]
	local buckets = nil
	if rawDaily ~= nil then
		if ms and type(ms.ReadDaily) == "function" then
			local ok, decoded = pcall(ms.ReadDaily, rawDaily)
			if ok then buckets = safeTable(decoded) end
		else
			buckets = safeTable(rawDaily)
		end
	end
	if buckets then
		for i = 1, #buckets do
			local b = safeTable(buckets[i])
			if b then
				local bDay = safeNumber(b.d)
				local bt = safeNumber(b.at) or (bDay and bDay * 86400 or nil)
				local bp = safeNumber(b.lastP) or safeNumber(b.minP) or safeNumber(b.obsP)
				local dayKey = bDay or (bt and math.floor(bt / 86400) or nil)
				if bp and bp > 0 then
					local excluded = (excludeTs ~= nil and bt ~= nil and bt >= excludeTs)
					local dupTs = (bt ~= nil and seenTs[bt] == true)
					local dupDay = (dayKey ~= nil and seenDays[dayKey] == true)
					if not excluded and not dupTs and not dupDay then
						if bt then seenTs[bt] = true end
						if dayKey then seenDays[dayKey] = true end
						prices[#prices + 1] = bp
					end
				end
			end
		end
	end

	return prices
end

local function computeLiveHistoryReference(itemID, econ, opts)
	local excludeTs = resolveCurrentScanExcludeTs(itemID, econ, opts)
	local prices = collectPriorLiveHistoryPrices(itemID, econ, excludeTs)
	if not prices or #prices < 2 then
		return nil, nil
	end
	table.sort(prices)
	local n = #prices
	local medianUnit
	if (n % 2) == 1 then
		medianUnit = prices[(n + 1) / 2]
	else
		medianUnit = (prices[n / 2] + prices[(n / 2) + 1]) / 2
	end
	if not medianUnit or medianUnit <= 0 then
		return nil, nil
	end
	return math.floor(medianUnit + 0.5), "live_history"
end

local function hasSufficientLocalHistory(econ)
	local db = safeTable(_G.MerchantMasterDB)
	if not db or type(econ) ~= "string" or econ == "" then return false end
	local histRoot = safeTable(db.ahHistory)
	local histEcon = histRoot and safeTable(histRoot[econ])
	if histEcon then
		for idKey in pairs(histEcon) do
			local id = safeNumber(idKey)
			if id and id > 0 then
				local excludeTs = resolveCurrentScanExcludeTs(id, econ, nil)
				local prices = collectPriorLiveHistoryPrices(id, econ, excludeTs)
				if prices and #prices >= 2 then
					return true
				end
			end
		end
	end
	local dailyRoot = safeTable(db.ahDaily)
	local dailyEcon = dailyRoot and safeTable(dailyRoot[econ])
	if dailyEcon then
		for idKey in pairs(dailyEcon) do
			local id = safeNumber(idKey)
			if id and id > 0 then
				local excludeTs = resolveCurrentScanExcludeTs(id, econ, nil)
				local prices = collectPriorLiveHistoryPrices(id, econ, excludeTs)
				if prices and #prices >= 2 then
					return true
				end
			end
		end
	end
	return false
end

function SE.GetReferencePrice(itemID, econOverride, opts)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return nil, nil end
	if safeTable(opts) then
		local ov = safeNumber(opts.refPrice)
		if ov and ov > 0 then
			return math.floor(ov), "override"
		end
	end

	local econ = activeEconomy(econOverride)

	local snapMV, snapHist, snapMin = nil, nil, nil
	if type(ns.QueryLocalSnapshot) == "function" then
		local ok, price, rec = pcall(ns.QueryLocalSnapshot, id, econ)
		if ok then
			local rt = safeTable(rec)
			if rt then
				snapMV = safeNumber(rt.marketValue)
				snapHist = safeNumber(rt.historical)
				snapMin = safeNumber(rt.minBuyout)
			end
			if not snapMin then
				snapMin = safeNumber(price)
			end
		end
	end

	local rawAnchor = nil
	local rawSource = nil
	if snapMV and snapMV > 0 then
		if snapHist and snapHist > 0 then
			local histCap = math.floor(snapHist * 1.25 + 0.5)
			if snapMV <= histCap then
				rawAnchor = math.floor(snapMV)
				rawSource = "snapshot_mv"
			else
				rawAnchor = histCap
				rawSource = "snapshot_hist_cap"
			end
		else
			rawAnchor = math.floor(snapMV)
			rawSource = "snapshot_mv"
		end
	elseif snapHist and snapHist > 0 then
		rawAnchor = math.floor(snapHist)
		rawSource = "snapshot_hist"
	elseif snapMin and snapMin > 0 then
		rawAnchor = math.floor(snapMin)
		rawSource = "snapshot_min"
	end

	if not rawAnchor or rawAnchor <= 0 then
		rawAnchor, rawSource = computeLiveHistoryReference(id, econ, opts)
	end

	if not rawAnchor or rawAnchor <= 0 then
		return nil, nil
	end

	if type(ns.GetConservativeSaleUnitPrice) == "function" then
		local ok, capped, wasCapped, capSrc = pcall(ns.GetConservativeSaleUnitPrice, id, rawAnchor)
		local cn = ok and safeNumber(capped) or nil
		if cn and cn > 0 then
			if safeBool(wasCapped) == true then
				return math.floor(cn), safeString(capSrc) or "conservative_cap"
			end
			return math.floor(cn), rawSource
		end
	end

	return rawAnchor, rawSource
end

-------------------------------------------------------------------------------
-- Gap Sniper Shortlist Builder (Fast Sellers First)
-------------------------------------------------------------------------------

-- Returns canonical signature for an itemKey:
--   "id:ilvl:suf:pet" when any variant field is non-zero (supports negative Classic suffixes),
--   or integer itemID for base 0:0:0 keys (preserves SE.browseCache[itemID] compatibility).
local function makeItemKeySignature(itemID, itemKey)
	local kt = safeTable(itemKey)
	local id = safeNumber(itemID) or (kt and safeNumber(kt.itemID))
	if not id or id <= 0 then return nil end
	id = math.floor(id)
	if kt then
		local ilvl = math.floor(safeNumber(kt.itemLevel) or 0)
		local suf = math.floor(safeNumber(kt.itemSuffix) or 0)
		local pet = math.floor(safeNumber(kt.battlePetSpeciesID) or 0)
		if ilvl ~= 0 or suf ~= 0 or pet ~= 0 then
			return string.format("%d:%d:%d:%d", id, ilvl, suf, pet)
		end
	end
	return id
end

function SE.BuildGapShortlist(opts)
	opts = safeTable(opts) or {}
	local settings = SE.GetSettings()
	local econ = activeEconomy(opts.econ)
	local now = nowMono()

	local minDailySales = safeNumber(opts.minDailySales)
	if minDailySales == nil then minDailySales = settings.minDailySales end
	local buyCeilingPct = safeNumber(opts.buyCeilingPct)
	if buyCeilingPct == nil then buyCeilingPct = settings.buyCeilingPct end
	local minGapPct = safeNumber(opts.minGapPct)
	if minGapPct == nil then minGapPct = settings.minGapPct end
	local minRoiPct = safeNumber(opts.minRoiPct)
	if minRoiPct == nil then minRoiPct = settings.minRoiPct end
	local minProfitCopper = safeNumber(opts.minProfitCopper)
	if minProfitCopper == nil then minProfitCopper = safeNumber(opts.minProfit) end
	if minProfitCopper == nil then minProfitCopper = settings.minProfitCopper end
	minProfitCopper = math.max(0, math.floor(minProfitCopper or 0))
	local minQty = safeNumber(opts.minQty)
	if minQty == nil then minQty = settings.minQty end
	minQty = math.max(1, math.floor(minQty or 2))
	local itemMinQty = safeNumber(opts.itemMinQty)
	itemMinQty = math.max(1, math.floor(itemMinQty or 1))
	local maxQty = safeNumber(opts.maxQty)
	if maxQty == nil then maxQty = settings.maxQty end
	maxQty = math.max(0, math.floor(maxQty or 0))
	local maxBuyShareDailyPct = safeNumber(opts.maxBuyShareDailyPct)
	if maxBuyShareDailyPct == nil then maxBuyShareDailyPct = settings.maxBuyShareDailyPct end
	local minQuality = safeNumber(opts.minQuality)
	if minQuality == nil then minQuality = settings.minQuality end
	local maxItems = safeNumber(opts.maxItems)
	if maxItems == nil then maxItems = settings.maxShortlistItems or 120 end
	local scope = normalizeGapScope(opts.gapScope or opts.scope or settings.gapScope)
	local browseOnly = (opts.browseOnly == true)
	local forceRedrill = (opts.forceRedrill == true)
	local minUpdatedAt = safeNumber(opts.minUpdatedAt)

	local isNeutral
	if opts.isNeutral ~= nil then
		isNeutral = (opts.isNeutral == true)
	else
		isNeutral = SE.IsNeutralAH()
	end
	local ahCutRate = safeNumber(opts.ahCut)
	if ahCutRate == nil then
		ahCutRate = isNeutral and SE.NEUTRAL_AH_CUT or SE.FACTION_AH_CUT
	end

	-- Spend budget (matching EvaluateCommodityGap / EvaluateItemGap)
	local maxSpend = safeNumber(opts.maxSpend)
	if maxSpend == nil then maxSpend = safeNumber(opts.maxSpendCopper) end
	if maxSpend == nil then maxSpend = settings.maxSpendCopper end
	local effMaxSpend = (maxSpend and maxSpend > 0) and math.floor(maxSpend) or math.huge
	if opts.ignorePlayerGold ~= true then
		local playerMoney = getPlayerMoney()
		if playerMoney ~= nil then
			effMaxSpend = math.min(effMaxSpend, math.max(0, math.floor(playerMoney)))
		end
	end
	if effMaxSpend <= 0 then
		return {}
	end

	-- Exact mathematical Stage 1 ceiling: cannot satisfy minGapPct or minRoiPct above this % of refPrice
	local gapCeilPct = math.floor(100 / (1 + math.max(0, minGapPct or 0) / 100))
	local roiCeilPct = math.floor(100 * (1 - ahCutRate) / (1 + math.max(0, minRoiPct or 0) / 100))
	local effCeilingPct = math.max(1, math.min(buyCeilingPct, gapCeilPct, roiCeilPct))

	local fastFirst
	if opts.fastSellersFirst ~= nil then
		fastFirst = (opts.fastSellersFirst == true)
	else
		fastFirst = (settings.fastSellersFirst ~= false)
	end

	local merged = {}

	-- 1. Seed from hydrated snapshot items (skipped when browseOnly=true after a full live sweep)
	if not browseOnly then
		local snapItems = hydrateSnapshotItems(econ)
		if snapItems then
			for idKey, rec in pairs(snapItems) do
				local id = safeNumber(idKey)
				local rt = safeTable(rec)
				if id and id > 0 and rt then
					local minP = safeNumber(rt.minBuyout)
					local snapQty = safeNumber(rt.qty) or 0
					if minP and minP > 0 and snapQty > 0 then
						local sig = math.floor(id)
						merged[sig] = {
							sig = sig,
							itemID = sig,
							minPrice = math.floor(minP),
							totalQuantity = snapQty,
							source = "Snapshot",
						}
					end
				end
			end
		end
	end

	-- 2. Overlay live Browse rows for the active economy (keyed by full itemKey signature)
	for _, brow in pairs(SE.browseCache) do
		local bt = safeTable(brow)
		if bt then
			local bEcon = safeString(bt.economy)
			local econMatch = (bEcon == nil) or (bEcon == econ)
			local updatedAt = safeNumber(bt.updatedAt)
			local freshMatch = (minUpdatedAt == nil) or (updatedAt ~= nil and updatedAt >= minUpdatedAt)
			local id = safeNumber(bt.itemID)
			local minP = safeNumber(bt.minPrice)
			if econMatch and freshMatch and id and id > 0 and minP and minP > 0 then
				local sig = makeItemKeySignature(id, bt.itemKey)
				if sig ~= nil then
					merged[sig] = {
						sig = sig,
						itemID = math.floor(id),
						minPrice = math.floor(minP),
						totalQuantity = safeNumber(bt.totalQuantity) or 0,
						quality = safeNumber(bt.quality),
						isCommodity = safeBool(bt.isCommodity),
						itemKey = bt.itemKey,
						itemLink = bt.itemLink,
						source = "Browse",
					}
				end
			end
		end
	end

	-- Memoize demand & reference price by itemID within this pass (M3)
	local demandCache = {}
	local refCache = {}
	local shortlist = {}
	local reusedDeals = {}
	local totalCandidates = 0
	local passedPreGates = 0
	local demandChecked = 0
	local demandDataCount = 0
	local refChecked = 0
	local refFound = 0
	local hasSnapshots = (type(ns.HasSnapshots) == "function" and ns.HasSnapshots(econ) == true)
		or (hydrateSnapshotItems(econ) ~= nil)
	local refOpts = (opts.currentScanAt or opts.excludeTimestamp)
		and { currentScanAt = opts.currentScanAt, excludeTimestamp = opts.excludeTimestamp }
		or nil

	for sig, cand in pairs(merged) do
		totalCandidates = totalCandidates + 1
		local id = cand.itemID
		local totalQty = cand.totalQuantity or 0
		local keep = true

		-- Pure-Lua O(1) gates BEFORE any WoW C-API calls (B2, M2, M3):
		-- 1) Unaffordable single unit
		if effMaxSpend < math.huge and cand.minPrice > effMaxSpend then
			keep = false
		end

		-- 2) Universal impossible-cliff gate (a 2-tier cliff requires at least 2 total units)
		if keep and totalQty > 0 and totalQty < 2 then
			keep = false
		end

		-- 3) Known quality below minQuality
		if keep and cand.quality ~= nil and minQuality > 0 and cand.quality < minQuality then
			keep = false
		end

		-- 4) M2 Differential Browse delta-memoization (skip unchanged order book drilled < 120s ago)
		if keep and not forceRedrill then
			local dc = SE.drillCache[sig]
			if dc and dc.minPrice == cand.minPrice and dc.totalQuantity == totalQty
				and (now - dc.drilledAt) < SE.DRILL_CACHE_TTL then
				if dc.deal then
					reusedDeals[#reusedDeals + 1] = dc.deal
				end
				keep = false
			end
		end

		if keep then
			passedPreGates = passedPreGates + 1
		end

		-- 5) Memoized demand gate (pure Lua)
		local dailySold, saleRate, demandSrc
		if keep then
			demandChecked = demandChecked + 1
			local dRec = demandCache[id]
			if dRec == nil then
				local ds, sr, dsrc = SE.GetItemDemand(id, econ)
				dRec = { ds, sr, dsrc }
				demandCache[id] = dRec
			end
			dailySold, saleRate, demandSrc = dRec[1], dRec[2], dRec[3]
			if demandSrc ~= nil or (dailySold and dailySold > 0) then
				demandDataCount = demandDataCount + 1
			end
			if dailySold < minDailySales then
				keep = false
			end
		end

		-- 6) Memoized reference price & exact tightened ceiling gate (pure Lua)
		local refPrice, refSrc, maxNetUnit
		if keep then
			refChecked = refChecked + 1
			local rRec = refCache[id]
			if rRec == nil then
				local rp, rsrc = SE.GetReferencePrice(id, econ, refOpts)
				if rp and rp > 0 then
					rRec = { rp, rsrc }
				else
					rRec = false
				end
				refCache[id] = rRec
			end
			if not rRec then
				keep = false
			else
				refFound = refFound + 1
				refPrice, refSrc = rRec[1], rRec[2]
				local ceiling = math.floor(refPrice * (effCeilingPct / 100))
				maxNetUnit = math.floor(refPrice * (1 - ahCutRate))
				if cand.minPrice > ceiling or maxNetUnit <= cand.minPrice then
					keep = false
				end
			end
		end

		-- 7) Classification, scope, quality, liquidity & exact upper-bound total profit (B2, M3)
		if keep then
			local nonComm = isKnownNonCommodity(id, cand.itemKey, cand.isCommodity)
			local isComm = not nonComm
			local scopeOk
			if scope == "commodities" then
				scopeOk = isComm
			elseif scope == "items" then
				scopeOk = nonComm
			else
				scopeOk = true
			end

			local quality = cand.quality
			if scopeOk and quality == nil and minQuality > 0 then
				local info = readItemInfoSafe(cand.itemLink or id)
				if info then quality = info.quality end
			end
			local qualityOk = scopeOk and ((minQuality <= 0) or (quality == nil) or (quality >= minQuality))

			if qualityOk then
				local reqMinQty = isComm and minQty or itemMinQty
				local cliffOk = (totalQty <= 0) or (totalQty >= (isComm and (minQty + 1) or math.max(2, itemMinQty + 1)))

				local effMaxQty = (maxQty > 0) and maxQty or math.huge
				local liqOk = true
				if cliffOk and maxBuyShareDailyPct and maxBuyShareDailyPct > 0 and dailySold and dailySold > 0 then
					if isComm then
						local liqCap = math.floor(dailySold * (maxBuyShareDailyPct / 100))
						if liqCap < minQty then
							liqOk = false
						else
							effMaxQty = math.min(effMaxQty, liqCap)
						end
					else
						local liqCap = math.max(1, math.floor(dailySold * (maxBuyShareDailyPct / 100) + 0.5))
						effMaxQty = math.min(effMaxQty, liqCap)
					end
				end

				if cliffOk and liqOk then
					local maxAvail = (totalQty > 0) and (totalQty - 1) or effMaxQty
					local maxAfford = (effMaxSpend < math.huge) and math.floor(effMaxSpend / cand.minPrice) or maxAvail
					local maxBuyable = math.min(maxAvail, effMaxQty, maxAfford)
					local profitOk = (maxBuyable > 0) and (maxBuyable >= reqMinQty)
					if profitOk and maxBuyable < math.huge then
						if (maxBuyable * (maxNetUnit - cand.minPrice)) < minProfitCopper then
							profitOk = false
						end
					end

					if profitOk then
						local ratioPct = (cand.minPrice / refPrice) * 100
						local discountPct = math.max(0, 100 - ratioPct)
						local priorityScore = discountPct * math.max(0.1, dailySold)
						shortlist[#shortlist + 1] = {
							sig = sig,
							itemID = id,
							minPrice = cand.minPrice,
							refPrice = refPrice,
							refSource = refSrc,
							ratioPct = ratioPct,
							discountPct = discountPct,
							priorityScore = priorityScore,
							dailySold = dailySold,
							saleRate = saleRate,
							demandSource = demandSrc,
							totalQuantity = totalQty,
							quality = quality,
							isCommodity = isComm,
							itemKey = cand.itemKey,
							itemLink = cand.itemLink,
							source = cand.source,
						}
					end
				end
			end
		end
	end

	table.sort(shortlist, function(a, b)
		if fastFirst then
			if a.priorityScore ~= b.priorityScore then return a.priorityScore > b.priorityScore end
			if a.discountPct ~= b.discountPct then return a.discountPct > b.discountPct end
			if a.dailySold ~= b.dailySold then return a.dailySold > b.dailySold end
		else
			if a.discountPct ~= b.discountPct then return a.discountPct > b.discountPct end
			if a.dailySold ~= b.dailySold then return a.dailySold > b.dailySold end
		end
		if a.itemID ~= b.itemID then return a.itemID < b.itemID end
		return tostring(a.sig) < tostring(b.sig)
	end)

	if maxItems and maxItems > 0 and #shortlist > maxItems then
		for i = #shortlist, maxItems + 1, -1 do
			shortlist[i] = nil
		end
	end

	if #shortlist == 0 and #reusedDeals == 0 and not hasSnapshots then
		local coldDemand = (minDailySales > 0 and demandChecked > 0 and demandDataCount == 0)
		local coldRefs = (refChecked > 0 and refFound == 0)
		local coldStart = coldDemand or coldRefs or ((passedPreGates == 0) and not hasSufficientLocalHistory(econ))
		if coldStart then
			shortlist.rows = {}
			shortlist.reason = "insufficient_live_history"
			shortlist.scannedCandidates = totalCandidates
			shortlist.refFound = refFound
			shortlist.demandDataCount = demandDataCount
			return shortlist, reusedDeals, {
				rows = shortlist.rows,
				reason = "insufficient_live_history",
				scannedCandidates = totalCandidates,
				refFound = refFound,
				demandDataCount = demandDataCount,
			}
		end
	end

	return shortlist, reusedDeals
end

-------------------------------------------------------------------------------
-- Gap Sniper Evaluator (Multi-Tier Cliff, Resale Cap, Liquidity Cap & Ladder)
-------------------------------------------------------------------------------

local function normalizeTiers(tiers)
	local tTbl = safeTable(tiers)
	if not tTbl then return {} end
	local out = {}
	local needsSort = false
	local prevPrice = 0
	for i = 1, #tTbl do
		local row = safeTable(tTbl[i])
		if row then
			local up = safeNumber(row.unitPrice) or safeNumber(row.price)
			local qty = safeNumber(row.quantity) or safeNumber(row.qty)
			local ownerQty = safeNumber(row.numOwnerItems) or 0
			if up and up > 0 and qty and qty > 0 then
				local avail = math.floor(qty) - math.max(0, math.floor(ownerQty))
				if avail > 0 then
					local p = math.floor(up)
					if p < prevPrice then needsSort = true end
					prevPrice = p
					out[#out + 1] = {
						unitPrice = p,
						quantity = avail,
					}
				end
			end
		end
	end
	if needsSort then
		table.sort(out, function(a, b) return a.unitPrice < b.unitPrice end)
	end
	-- Coalesce adjacent identical prices so cliff detection never treats same-price splits as a gap
	local merged = {}
	for i = 1, #out do
		local cur = out[i]
		local last = merged[#merged]
		if last and last.unitPrice == cur.unitPrice then
			last.quantity = last.quantity + cur.quantity
		else
			merged[#merged + 1] = { unitPrice = cur.unitPrice, quantity = cur.quantity }
		end
	end
	return merged
end

function SE.EvaluateCommodityGap(itemID, tiers, opts)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return nil end

	local norm = normalizeTiers(tiers)
	if #norm < 2 then
		-- Need at least 2 distinct price tiers to prove an observable price cliff
		return nil
	end

	opts = safeTable(opts) or {}
	local settings = SE.GetSettings()
	local econ = activeEconomy(opts.econ)

	local minQty = safeNumber(opts.minQty)
	if minQty == nil then minQty = settings.minQty end
	minQty = math.max(1, math.floor(minQty or 2))

	local maxQty = safeNumber(opts.maxQty)
	if maxQty == nil then maxQty = settings.maxQty end
	maxQty = math.max(0, math.floor(maxQty or 0))

	local minGapPct = safeNumber(opts.minGapPct)
	if minGapPct == nil then minGapPct = settings.minGapPct end

	local minRoiPct = safeNumber(opts.minRoiPct)
	if minRoiPct == nil then minRoiPct = settings.minRoiPct end

	local minProfitCopper = safeNumber(opts.minProfitCopper)
	if minProfitCopper == nil then minProfitCopper = safeNumber(opts.minProfit) end
	if minProfitCopper == nil then minProfitCopper = settings.minProfitCopper end

	local maxBuyShareDailyPct = safeNumber(opts.maxBuyShareDailyPct)
	if maxBuyShareDailyPct == nil then maxBuyShareDailyPct = settings.maxBuyShareDailyPct end

	local buyCeilingPct = safeNumber(opts.buyCeilingPct)
	if buyCeilingPct == nil then buyCeilingPct = settings.buyCeilingPct end

	local durationHours = safeNumber(opts.relistDurationHours) or safeNumber(opts.durationHours) or settings.relistDurationHours or 8

	local isNeutral
	if opts.isNeutral ~= nil then
		isNeutral = (opts.isNeutral == true)
	else
		isNeutral = SE.IsNeutralAH()
	end
	local ahCutRate = safeNumber(opts.ahCut)
	if ahCutRate == nil then
		ahCutRate = isNeutral and SE.NEUTRAL_AH_CUT or SE.FACTION_AH_CUT
	end

	-- Spend budget
	local maxSpend = safeNumber(opts.maxSpend)
	if maxSpend == nil then maxSpend = safeNumber(opts.maxSpendCopper) end
	if maxSpend == nil then maxSpend = settings.maxSpendCopper end
	local effMaxSpend = (maxSpend and maxSpend > 0) and math.floor(maxSpend) or math.huge
	if opts.ignorePlayerGold ~= true then
		local playerMoney = getPlayerMoney()
		if playerMoney ~= nil then
			effMaxSpend = math.min(effMaxSpend, math.max(0, math.floor(playerMoney)))
		end
	end
	if effMaxSpend <= 0 then return nil end

	-- Reference valuation & demand
	local refPrice, refSource = SE.GetReferencePrice(id, econ, opts)
	local dailySold = safeNumber(opts.dailySold)
	if dailySold == nil then
		dailySold = SE.GetItemDemand(id, econ)
	end

	-- Flipping Pal liquidity cap: buyQty <= dailySold * (maxBuyShareDailyPct / 100) when dailySold > 0
	-- When evaluating snapshot equipment (opts.isEquipment == true), match EvaluateItemGap's >= 1 floor.
	local effMaxQty = (maxQty > 0) and maxQty or math.huge
	if maxBuyShareDailyPct and maxBuyShareDailyPct > 0 and dailySold and dailySold > 0 then
		local liqCap
		if opts.isEquipment == true then
			liqCap = math.max(1, math.floor(dailySold * (maxBuyShareDailyPct / 100) + 0.5))
		else
			liqCap = math.floor(dailySold * (maxBuyShareDailyPct / 100))
			if liqCap <= 0 then return nil end
		end
		effMaxQty = math.min(effMaxQty, liqCap)
	end

	-- Per-unit buy ceiling relative to reference price
	local maxUnitPrice = math.huge
	if refPrice and refPrice > 0 and buyCeilingPct and buyCeilingPct > 0 then
		maxUnitPrice = math.floor(refPrice * (buyCeilingPct / 100))
		if maxUnitPrice <= 0 then return nil end
	end

	local vendorSell = safeNumber(opts.vendorSell)
	if vendorSell == nil then
		vendorSell = getBaseVendorSell(id) or 0
	end

	local runningQty = 0
	local runningSpend = 0
	local best = nil

	for i = 1, #norm - 1 do
		local tier = norm[i]
		if tier.unitPrice > maxUnitPrice then
			break
		end

		local avail = tier.quantity
		local take = avail
		if runningQty + take > effMaxQty then
			take = effMaxQty - runningQty
		end
		if take <= 0 then
			break
		end
		local maxAfford = math.floor((effMaxSpend - runningSpend) / tier.unitPrice)
		if take > maxAfford then
			take = maxAfford
		end
		if take <= 0 then
			break
		end

		runningQty = runningQty + take
		runningSpend = runningSpend + (take * tier.unitPrice)

		local clearedTier = (take == avail)
		if clearedTier then
			local nextTier = norm[i + 1]
			local nextTierPrice = nextTier.unitPrice
			local nextTierQty = nextTier.quantity
			if nextTierPrice > tier.unitPrice and runningQty >= minQty then
				local avgBuyPrice = runningSpend / runningQty
				local rawRelist = nextTierPrice - 1
				local relistPrice
				if refPrice and refPrice > 0 then
					relistPrice = math.min(rawRelist, math.floor(refPrice))
				else
					relistPrice = rawRelist
				end
				-- Effective wall capped at refPrice so fake cliffs never inflate gapPct
				local effectiveWall = (refPrice and refPrice > 0) and math.min(nextTierPrice, refPrice) or nextTierPrice
				local gapPct = avgBuyPrice > 0 and (((effectiveWall - avgBuyPrice) / avgBuyPrice) * 100) or 0

				if relistPrice > avgBuyPrice then
					local grossRevenue = relistPrice * runningQty
					local ahCut = math.floor(grossRevenue * ahCutRate + 0.5)
					local netRevenue = grossRevenue - ahCut
					local netProfit = netRevenue - runningSpend
					local roiPct = runningSpend > 0 and ((netProfit / runningSpend) * 100) or 0
					local deposit = SE.GetForeverAuctionDeposit(vendorSell, runningQty, durationHours, isNeutral)

					if gapPct >= minGapPct and roiPct >= minRoiPct and netProfit >= minProfitCopper then
						local better = false
						if not best then
							better = true
						elseif netProfit > best.netProfit then
							better = true
						elseif netProfit == best.netProfit and roiPct > best.roiPct then
							better = true
						end
						if better then
							best = {
								endTier = i,
								wallTier = i + 1,
								buyQty = runningQty,
								totalCost = runningSpend,
								avgBuyPrice = avgBuyPrice,
								nextTierPrice = nextTierPrice,
								nextTierQty = nextTierQty,
								relistPrice = relistPrice,
								grossRevenue = grossRevenue,
								ahCut = ahCut,
								deposit = deposit,
								netProfit = netProfit,
								roiPct = roiPct,
								gapPct = gapPct,
							}
						end
					end
				end
			end
		else
			-- Partial tier leaves competitor stock at tier.unitPrice -> no cliff past here
			break
		end

		if runningQty >= effMaxQty or runningSpend >= effMaxSpend then
			break
		end
	end

	if not best then
		return nil
	end

	-- Build clean Price Ladder breakdown for UI preview (bought tiers + wall + up to 2 context tiers)
	local ladder = {}
	local ladderLimit = math.min(#norm, best.wallTier + 2)
	for i = 1, ladderLimit do
		local t = norm[i]
		local role
		local bQty = 0
		if i <= best.endTier then
			role = "buy"
			bQty = t.quantity
		elseif i == best.wallTier then
			role = "wall"
		else
			role = "above"
		end
		ladder[#ladder + 1] = {
			tierIndex = i,
			unitPrice = t.unitPrice,
			quantity = t.quantity,
			buyQty = bQty,
			role = role,
			subtotal = bQty * t.unitPrice,
		}
	end

	local itemName, itemIcon, itemQuality, itemLink = getItemDisplayMeta(id, opts.itemLink)
	local estHoursToSell = (dailySold and dailySold > 0) and ((best.buyQty / dailySold) * 24) or nil

	return {
		idKey = "gap:" .. tostring(id),
		kind = "commodity",
		isCommodity = true,
		mode = "gap",
		itemID = id,
		itemName = itemName,
		icon = itemIcon,
		quality = itemQuality,
		itemLink = itemLink,
		buyQty = best.buyQty,
		quantity = best.buyQty,
		avgBuyPrice = best.avgBuyPrice,
		totalCost = best.totalCost,
		nextTierPrice = best.nextTierPrice,
		nextTierQty = best.nextTierQty,
		relistPrice = best.relistPrice,
		refPrice = refPrice,
		refSource = refSource,
		grossRevenue = best.grossRevenue,
		ahCutRate = ahCutRate,
		ahCut = best.ahCut,
		isNeutral = isNeutral,
		deposit = best.deposit,
		depositHours = durationHours,
		netProfit = best.netProfit,
		netProfitAfterDeposit = best.netProfit - best.deposit,
		roiPct = best.roiPct,
		gapPct = best.gapPct,
		dailySold = dailySold,
		estHoursToSell = estHoursToSell,
		ladder = ladder,
		tiersBought = best.endTier,
		source = safeString(opts.source) or "Live",
		foundAt = nowMono(),
		status = "ready",
	}
end

local function makeGapDealKey(itemID, itemKey)
	local sig = makeItemKeySignature(itemID, itemKey)
	return "gap:" .. tostring(sig or itemID)
end

-- Equipment / Non-Commodity Gap Sniper Evaluator:
-- Takes raw item search rows { { auctionID, buyoutAmount, quantity, itemLink }, ... },
-- groups them into price tiers, finds the best cliff cutoff up to nextTierPrice - 1
-- (capped at refPrice), and returns a deal with a sequential buyQueue + identical
-- Price Ladder shape to EvaluateCommodityGap.
function SE.EvaluateItemGap(itemID, rawRows, opts)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return nil end

	local rowsTbl = safeTable(rawRows)
	if not rowsTbl or #rowsTbl < 2 then return nil end

	local listings = {}
	for i = 1, #rowsTbl do
		local row = safeTable(rowsTbl[i])
		if row then
			local ownerReadable = isReadable(row.containsOwnerItem) and isReadable(row.containsAccountItem)
			local owned = (not ownerReadable)
				or (safeBool(row.containsOwnerItem) == true)
				or (safeBool(row.containsAccountItem) == true)
				or ((safeNumber(row.numOwnerItems) or 0) > 0)
			if not owned then
				local aid = safeNumber(row.auctionID)
				local buyout = safeNumber(row.buyoutAmount)
				local qty = safeNumber(row.quantity)
				if qty == nil then qty = 1 end
				if aid and aid > 0 and buyout and buyout > 0 and qty and qty > 0 then
					buyout = math.floor(buyout)
					qty = math.max(1, math.floor(qty))
					local exactUnit = buyout / qty
					local unitPrice = math.floor(exactUnit)
					if unitPrice > 0 then
						listings[#listings + 1] = {
							auctionID = math.floor(aid),
							buyoutAmount = buyout,
							quantity = qty,
							unitPrice = unitPrice,
							exactUnitPrice = exactUnit,
							itemLink = safeString(row.itemLink),
						}
					end
				end
			end
		end
	end

	if #listings < 2 then return nil end

	table.sort(listings, function(a, b)
		if a.exactUnitPrice ~= b.exactUnitPrice then return a.exactUnitPrice < b.exactUnitPrice end
		if a.buyoutAmount ~= b.buyoutAmount then return a.buyoutAmount < b.buyoutAmount end
		return a.auctionID < b.auctionID
	end)

	-- Group sorted listings into distinct price tiers
	local tiers = {}
	for i = 1, #listings do
		local l = listings[i]
		local last = tiers[#tiers]
		if last and last.unitPrice == l.unitPrice then
			last.quantity = last.quantity + l.quantity
			last.totalCost = last.totalCost + l.buyoutAmount
			last.listingCount = last.listingCount + 1
			last.listings[#last.listings + 1] = l
		else
			tiers[#tiers + 1] = {
				unitPrice = l.unitPrice,
				quantity = l.quantity,
				totalCost = l.buyoutAmount,
				listingCount = 1,
				listings = { l },
			}
		end
	end

	if #tiers < 2 then
		-- Need at least 2 distinct price tiers to prove an observable price cliff
		return nil
	end

	opts = safeTable(opts) or {}
	local settings = SE.GetSettings()
	local econ = activeEconomy(opts.econ)

	-- Equipment/non-commodity anti-bait floor reads ONLY opts.itemMinQty (default 1);
	-- never fall back to commodity opts.minQty or settings.minQty.
	local minQty = safeNumber(opts.itemMinQty)
	minQty = math.max(1, math.floor(minQty or 1))

	local maxQty = safeNumber(opts.maxQty)
	if maxQty == nil then maxQty = settings.maxQty end
	maxQty = math.max(0, math.floor(maxQty or 0))

	local minGapPct = safeNumber(opts.minGapPct)
	if minGapPct == nil then minGapPct = settings.minGapPct end

	local minRoiPct = safeNumber(opts.minRoiPct)
	if minRoiPct == nil then minRoiPct = settings.minRoiPct end

	local minProfitCopper = safeNumber(opts.minProfitCopper)
	if minProfitCopper == nil then minProfitCopper = safeNumber(opts.minProfit) end
	if minProfitCopper == nil then minProfitCopper = settings.minProfitCopper end

	local maxBuyShareDailyPct = safeNumber(opts.maxBuyShareDailyPct)
	if maxBuyShareDailyPct == nil then maxBuyShareDailyPct = settings.maxBuyShareDailyPct end

	local buyCeilingPct = safeNumber(opts.buyCeilingPct)
	if buyCeilingPct == nil then buyCeilingPct = settings.buyCeilingPct end

	local durationHours = safeNumber(opts.relistDurationHours) or safeNumber(opts.durationHours) or settings.relistDurationHours or 8

	local isNeutral
	if opts.isNeutral ~= nil then
		isNeutral = (opts.isNeutral == true)
	else
		isNeutral = SE.IsNeutralAH()
	end
	local ahCutRate = safeNumber(opts.ahCut)
	if ahCutRate == nil then
		ahCutRate = isNeutral and SE.NEUTRAL_AH_CUT or SE.FACTION_AH_CUT
	end

	-- Spend budget
	local maxSpend = safeNumber(opts.maxSpend)
	if maxSpend == nil then maxSpend = safeNumber(opts.maxSpendCopper) end
	if maxSpend == nil then maxSpend = settings.maxSpendCopper end
	local effMaxSpend = (maxSpend and maxSpend > 0) and math.floor(maxSpend) or math.huge
	if opts.ignorePlayerGold ~= true then
		local playerMoney = getPlayerMoney()
		if playerMoney ~= nil then
			effMaxSpend = math.min(effMaxSpend, math.max(0, math.floor(playerMoney)))
		end
	end
	if effMaxSpend <= 0 then return nil end

	-- Reference valuation & demand
	local refPrice, refSource = SE.GetReferencePrice(id, econ, opts)
	local dailySold = safeNumber(opts.dailySold)
	if dailySold == nil then
		dailySold = SE.GetItemDemand(id, econ)
	end

	-- Liquidity cap when dailySold > 0 (min 1 unit so <1/day rare BoEs stay buyable;
	-- matches UI_Sniper.collectGapDeals exactly).
	local effMaxQty = (maxQty > 0) and maxQty or math.huge
	if maxBuyShareDailyPct and maxBuyShareDailyPct > 0 and dailySold and dailySold > 0 then
		local liqCap = math.max(1, math.floor(dailySold * (maxBuyShareDailyPct / 100) + 0.5))
		effMaxQty = math.min(effMaxQty, liqCap)
	end

	-- Per-unit buy ceiling relative to reference price
	local maxUnitPrice = math.huge
	if refPrice and refPrice > 0 and buyCeilingPct and buyCeilingPct > 0 then
		maxUnitPrice = math.floor(refPrice * (buyCeilingPct / 100))
		if maxUnitPrice <= 0 then return nil end
	end

	local firstLink = listings[1].itemLink or safeString(opts.itemLink)
	local vendorSell = safeNumber(opts.vendorSell)
	if vendorSell == nil then
		local lv = getLinkVerifiedVendorSell(id, firstLink)
		vendorSell = lv or getBaseVendorSell(id) or 0
	end

	local runningQty = 0
	local runningSpend = 0
	local best = nil

	for i = 1, #tiers - 1 do
		local tier = tiers[i]
		if tier.unitPrice > maxUnitPrice then
			break
		end
		-- Must clear the entire price tier to establish the cliff up to tiers[i + 1]
		if runningQty + tier.quantity > effMaxQty then
			break
		end
		if runningSpend + tier.totalCost > effMaxSpend then
			break
		end

		runningQty = runningQty + tier.quantity
		runningSpend = runningSpend + tier.totalCost

		local nextTier = tiers[i + 1]
		local nextTierPrice = nextTier.unitPrice
		local nextTierQty = nextTier.quantity
		if nextTierPrice > tier.unitPrice and runningQty >= minQty then
			local avgBuyPrice = runningSpend / runningQty
			local rawRelist = nextTierPrice - 1
			local relistPrice
			if refPrice and refPrice > 0 then
				relistPrice = math.min(rawRelist, math.floor(refPrice))
			else
				relistPrice = rawRelist
			end
			local effectiveWall = (refPrice and refPrice > 0) and math.min(nextTierPrice, refPrice) or nextTierPrice
			local gapPct = avgBuyPrice > 0 and (((effectiveWall - avgBuyPrice) / avgBuyPrice) * 100) or 0

			if relistPrice > avgBuyPrice then
				local grossRevenue = relistPrice * runningQty
				local ahCut = math.floor(grossRevenue * ahCutRate + 0.5)
				local netRevenue = grossRevenue - ahCut
				local netProfit = netRevenue - runningSpend
				local roiPct = runningSpend > 0 and ((netProfit / runningSpend) * 100) or 0
				local deposit = SE.GetForeverAuctionDeposit(vendorSell, runningQty, durationHours, isNeutral)

				if gapPct >= minGapPct and roiPct >= minRoiPct and netProfit >= minProfitCopper then
					local better = false
					if not best then
						better = true
					elseif netProfit > best.netProfit then
						better = true
					elseif netProfit == best.netProfit and roiPct > best.roiPct then
						better = true
					end
					if better then
						best = {
							endTier = i,
							wallTier = i + 1,
							buyQty = runningQty,
							totalCost = runningSpend,
							avgBuyPrice = avgBuyPrice,
							nextTierPrice = nextTierPrice,
							nextTierQty = nextTierQty,
							relistPrice = relistPrice,
							grossRevenue = grossRevenue,
							ahCut = ahCut,
							deposit = deposit,
							netProfit = netProfit,
							roiPct = roiPct,
							gapPct = gapPct,
						}
					end
				end
			end
		end

		if runningQty >= effMaxQty or runningSpend >= effMaxSpend then
			break
		end
	end

	if not best then
		return nil
	end

	-- Sequential buyQueue across all cheap listings in tiers 1..best.endTier
	local buyQueue = {}
	for i = 1, best.endTier do
		local t = tiers[i]
		for j = 1, #t.listings do
			local l = t.listings[j]
			buyQueue[#buyQueue + 1] = {
				auctionID = l.auctionID,
				buyoutAmount = l.buyoutAmount,
				quantity = l.quantity,
				unitPrice = l.unitPrice,
				itemLink = l.itemLink,
			}
		end
	end

	-- Price Ladder with identical shape to EvaluateCommodityGap
	local ladder = {}
	local ladderLimit = math.min(#tiers, best.wallTier + 2)
	for i = 1, ladderLimit do
		local t = tiers[i]
		local role
		local bQty = 0
		local subtotal = 0
		if i <= best.endTier then
			role = "buy"
			bQty = t.quantity
			subtotal = t.totalCost
		elseif i == best.wallTier then
			role = "wall"
		else
			role = "above"
		end
		ladder[#ladder + 1] = {
			tierIndex = i,
			unitPrice = t.unitPrice,
			quantity = t.quantity,
			listingCount = t.listingCount,
			buyQty = bQty,
			role = role,
			subtotal = subtotal,
		}
	end

	local itemName, itemIcon, itemQuality, resolvedLink = getItemDisplayMeta(id, firstLink)
	local estHoursToSell = (dailySold and dailySold > 0) and ((best.buyQty / dailySold) * 24) or nil

	return {
		idKey = makeGapDealKey(id, opts.itemKey),
		kind = "item",
		isCommodity = false,
		mode = "gap",
		itemID = id,
		itemKey = safeTable(opts.itemKey),
		itemName = itemName,
		icon = itemIcon,
		quality = itemQuality,
		itemLink = firstLink or resolvedLink,
		buyQty = best.buyQty,
		quantity = best.buyQty,
		listingCount = #buyQueue,
		remainingListings = #buyQueue,
		totalListings = #buyQueue,
		boughtListings = 0,
		buyQueue = buyQueue,
		vendorSell = vendorSell,
		avgBuyPrice = best.avgBuyPrice,
		totalCost = best.totalCost,
		nextTierPrice = best.nextTierPrice,
		nextTierQty = best.nextTierQty,
		relistPrice = best.relistPrice,
		refPrice = refPrice,
		refSource = refSource,
		grossRevenue = best.grossRevenue,
		ahCutRate = ahCutRate,
		ahCut = best.ahCut,
		isNeutral = isNeutral,
		deposit = best.deposit,
		depositHours = durationHours,
		netProfit = best.netProfit,
		netProfitAfterDeposit = best.netProfit - best.deposit,
		roiPct = best.roiPct,
		gapPct = best.gapPct,
		dailySold = dailySold,
		estHoursToSell = estHoursToSell,
		ladder = ladder,
		tiersBought = best.endTier,
		source = safeString(opts.source) or "Live",
		foundAt = nowMono(),
		status = "ready",
	}
end

-------------------------------------------------------------------------------
-- Gap Deals List Management & Instant Snapshot Gap Preview
-------------------------------------------------------------------------------

local function sortGapDeals()
	table.sort(SE.gapDeals, function(a, b)
		if a.netProfit ~= b.netProfit then return a.netProfit > b.netProfit end
		if a.roiPct ~= b.roiPct then return a.roiPct > b.roiPct end
		return a.itemID < b.itemID
	end)
end

local function removeGapDealByKey(idKey)
	local old = idKey and SE.gapDealsByKey[idKey] or nil
	if not old then return end
	if SE.purchase and SE.purchase.deal == old then return end
	SE.gapDealsByKey[idKey] = nil
	for i = #SE.gapDeals, 1, -1 do
		if SE.gapDeals[i] == old then
			table.remove(SE.gapDeals, i)
			break
		end
	end
end

local function clearStaleGapDeals()
	local kept = {}
	local keptByKey = {}
	local activeDeal = (SE.purchase and SE.purchase.mode == "gap") and SE.purchase.deal or nil
	if activeDeal and activeDeal.idKey then
		kept[1] = activeDeal
		keptByKey[activeDeal.idKey] = activeDeal
	end
	SE.gapDeals = kept
	SE.gapDealsByKey = keptByKey
	notify("gap_deals", SE.gapDeals)
end

local function upsertGapDeal(deal)
	if not deal or not deal.idKey then return end
	-- When inserting a live variant key (e.g. gap:55001:45:-12:0), remove any stale
	-- base Snapshot placeholder (gap:55001) so Snapshot + Live never duplicate.
	if deal.itemID then
		local baseKey = "gap:" .. tostring(deal.itemID)
		if deal.idKey ~= baseKey then
			local baseOld = SE.gapDealsByKey[baseKey]
			if baseOld and baseOld.source == "Snapshot" then
				removeGapDealByKey(baseKey)
			end
		end
	end
	local existing = SE.gapDealsByKey[deal.idKey]
	if existing then
		-- Do not clobber a deal currently mid-purchase
		if SE.purchase and SE.purchase.deal == existing then
			return
		end
		for i = 1, #SE.gapDeals do
			if SE.gapDeals[i] == existing then
				SE.gapDeals[i] = deal
				break
			end
		end
	else
		SE.gapDeals[#SE.gapDeals + 1] = deal
		SE.session.gapDealsFound = SE.session.gapDealsFound + 1
	end
	SE.gapDealsByKey[deal.idKey] = deal
	sortGapDeals()
end

function SE.GetGapDeals()
	return SE.gapDeals
end

function SE.ClearDrillCache()
	SE.drillCache = {}
end

function SE.ClearGapDeals()
	if SE.purchase and SE.purchase.mode == "gap" then
		SE.CancelActivePurchase("Cleared deals")
	end
	SE.gapDeals = {}
	SE.gapDealsByKey = {}
	SE.drillCache = {}
	notify("gap_deals", SE.gapDeals)
end

local startGapDrillStage

function SE.ScanSnapshotForGapDeals(econOverride, opts)
	opts = safeTable(opts) or {}
	local econ = activeEconomy(econOverride or opts.econ)
	local pricing = safeTable(ns.Pricing)
	if not (pricing and type(pricing.GetItemSnapshotDepth) == "function") then
		setStatusText("Snapshot depth data unavailable.")
		return SE.gapDeals
	end

	if opts.append ~= true then
		clearStaleGapDeals()
	end

	local shortlist = SE.BuildGapShortlist({
		econ = econ,
		gapScope = opts.gapScope or opts.scope,
		minDailySales = opts.minDailySales,
		buyCeilingPct = opts.buyCeilingPct,
		minGapPct = opts.minGapPct,
		minRoiPct = opts.minRoiPct,
		minProfitCopper = opts.minProfitCopper or opts.minProfit,
		maxSpend = opts.maxSpend or opts.maxSpendCopper,
		minQty = opts.minQty,
		itemMinQty = opts.itemMinQty,
		maxQty = opts.maxQty,
		maxBuyShareDailyPct = opts.maxBuyShareDailyPct,
		isNeutral = opts.isNeutral,
		ahCut = opts.ahCut,
		minQuality = opts.minQuality,
		maxItems = opts.maxItems,
		fastSellersFirst = opts.fastSellersFirst,
		forceRedrill = true,
	})

	local found = 0
	for i = 1, #shortlist do
		local entry = shortlist[i]
		local ok, depth = pcall(pricing.GetItemSnapshotDepth, entry.itemID, econ)
		local dt = ok and safeTable(depth) or nil
		if dt and #dt >= 2 then
			local evalOpts = {}
			for k, v in pairs(opts) do evalOpts[k] = v end
			evalOpts.econ = econ
			evalOpts.refPrice = entry.refPrice
			evalOpts.dailySold = entry.dailySold
			evalOpts.source = "Snapshot"
			local isItem = (entry.isCommodity == false)
			if isItem then
				evalOpts.minQty = safeNumber(opts.itemMinQty) or 1
				evalOpts.isEquipment = true
			end
			local deal = SE.EvaluateCommodityGap(entry.itemID, dt, evalOpts)
			if deal then
				if isItem then
					deal.idKey = makeGapDealKey(entry.itemID, entry.itemKey)
					deal.itemKey = safeTable(entry.itemKey)
					deal.kind = "item"
					deal.isCommodity = false
					deal.buyQueue = nil
					deal.listingCount = deal.buyQty
					deal.remainingListings = deal.buyQty
					deal.totalListings = deal.buyQty
					deal.boughtListings = 0
					deal.needsLiveScan = true
					deal._checkOpts = {
						econ = econ,
						minGapPct = opts.minGapPct,
						minRoiPct = opts.minRoiPct,
						minProfitCopper = opts.minProfitCopper or opts.minProfit,
						maxSpend = opts.maxSpend or opts.maxSpendCopper,
						maxQty = opts.maxQty,
						maxBuyShareDailyPct = opts.maxBuyShareDailyPct,
						buyCeilingPct = opts.buyCeilingPct,
						itemMinQty = opts.itemMinQty,
						isNeutral = opts.isNeutral,
						ahCut = opts.ahCut,
					}
				end
				upsertGapDeal(deal)
				found = found + 1
			end
		end
	end

	setStatusText(string.format("Snapshot gap scan: %d deals from %d candidates.", found, #shortlist))
	notify("gap_deals", SE.gapDeals)
	return SE.gapDeals
end

-------------------------------------------------------------------------------
-- Vendor Sniper Evaluator (Browse Batch Ingestion & Full Snapshot Scan)
-------------------------------------------------------------------------------

local function sortVendorDeals()
	table.sort(SE.vendorDeals, function(a, b)
		if a.profitPerUnit ~= b.profitPerUnit then return a.profitPerUnit > b.profitPerUnit end
		if a.totalProfit ~= b.totalProfit then return a.totalProfit > b.totalProfit end
		return a.itemID < b.itemID
	end)
end

local function makeVendorDealKey(itemID, itemKey)
	local kt = safeTable(itemKey)
	if kt then
		local ilvl = math.floor(safeNumber(kt.itemLevel) or 0)
		local suf = math.floor(safeNumber(kt.itemSuffix) or 0)
		local pet = math.floor(safeNumber(kt.battlePetSpeciesID) or 0)
		if ilvl ~= 0 or suf ~= 0 or pet ~= 0 then
			return string.format("vendor:%d:%d:%d:%d", itemID, ilvl, suf, pet)
		end
	end
	return "vendor:" .. tostring(itemID)
end

local function queueUnresolvedVendor(cacheKey, itemID, entry)
	local id = math.floor(itemID)
	SE.unresolvedVendor[cacheKey] = entry
	local bucket = unresolvedVendorByID[id]
	if not bucket then
		bucket = {}
		unresolvedVendorByID[id] = bucket
	end
	bucket[cacheKey] = true
end

function SE.PruneBrowseCache(econOverride, olderThanMono)
	local econ = activeEconomy(econOverride)
	for k, v in pairs(SE.browseCache) do
		local bt = safeTable(v)
		if not bt then
			SE.browseCache[k] = nil
		else
			local bEcon = safeString(bt.economy)
			if bEcon == nil or bEcon == econ then
				if olderThanMono == nil or (safeNumber(bt.updatedAt) or 0) < olderThanMono then
					SE.browseCache[k] = nil
				end
			end
		end
	end
end

local function flushDeferredVendorDeals()
	if vendorDealsDirty then
		vendorDealsDirty = false
		sortVendorDeals()
		notify("vendor_deals", SE.vendorDeals)
	end
end

local function removeVendorDealByKey(idKey)
	local old = idKey and SE.vendorDealsByKey[idKey] or nil
	if not old then return end
	if (SE.purchase and SE.purchase.deal == old)
		or (SE.pendingCheck and SE.pendingCheck.deal == old) then
		return
	end
	SE.vendorDealsByKey[idKey] = nil
	for i = #SE.vendorDeals, 1, -1 do
		if SE.vendorDeals[i] == old then
			table.remove(SE.vendorDeals, i)
			break
		end
	end
end

local function clearStaleVendorDeals()
	local kept = {}
	local keptByKey = {}
	local activePurchase = (SE.purchase and SE.purchase.mode == "vendor") and SE.purchase.deal or nil
	local activeCheck = (SE.pendingCheck and SE.pendingCheck.mode == "vendor") and SE.pendingCheck.deal or nil
	if activePurchase and activePurchase.idKey then
		kept[#kept + 1] = activePurchase
		keptByKey[activePurchase.idKey] = activePurchase
	end
	if activeCheck and activeCheck.idKey and not keptByKey[activeCheck.idKey] then
		kept[#kept + 1] = activeCheck
		keptByKey[activeCheck.idKey] = activeCheck
	end
	SE.vendorDeals = kept
	SE.vendorDealsByKey = keptByKey
	SE.unresolvedVendor = {}
	unresolvedVendorByID = {}
	vendorDealsDirty = false
	notify("vendor_deals", SE.vendorDeals)
end

local function upsertVendorDeal(deal)
	if deal and deal.itemID and deal.idKey then
		local baseKey = "vendor:" .. tostring(deal.itemID)
		if deal.idKey ~= baseKey then
			local baseOld = SE.vendorDealsByKey[baseKey]
			if baseOld and baseOld.source == "Snapshot" then
				removeVendorDealByKey(baseKey)
			end
		end
	end
	local existing = SE.vendorDealsByKey[deal.idKey]
	if existing then
		-- Keep active purchase or active live check intact
		if (SE.purchase and SE.purchase.deal == existing)
			or (SE.pendingCheck and SE.pendingCheck.deal == existing) then
			return false
		end
		for i = 1, #SE.vendorDeals do
			if SE.vendorDeals[i] == existing then
				SE.vendorDeals[i] = deal
				break
			end
		end
	else
		SE.vendorDeals[#SE.vendorDeals + 1] = deal
		SE.session.vendorDealsFound = SE.session.vendorDealsFound + 1
	end
	SE.vendorDealsByKey[deal.idKey] = deal
	return true
end

local function evaluateVendorCandidate(itemID, minPrice, qty, source, extra)
	if minPrice <= 0 then return nil, false end
	local settings = (extra and extra.settings) or SE.GetSettings()
	local minProfit = (extra and safeNumber(extra.minProfitCopper)) or settings.vendorMinProfitCopper or 0

	local includeComm
	if extra and extra.includeCommodities ~= nil then
		includeComm = (extra.includeCommodities == true)
	else
		includeComm = settings.vendorIncludeCommodities ~= false
	end
	local itemLink = extra and safeString(extra.itemLink) or nil
	local isComm = extra and safeBool(extra.isCommodity)
	if isComm == nil then
		local info = (itemLink and readItemInfoSafe(itemLink)) or readItemInfoSafe(itemID)
		if info and info.maxStack ~= nil then
			isComm = (info.maxStack > 1)
		end
	end
	if isComm == true and not includeComm then
		return nil, false
	end

	-- Skip RequestLoadItemDataByID flood for items above any Classic vendor sell price (> 50g)
	local allowLoad = (minPrice <= SE.MAX_VENDOR_LOAD_PRICE)
	local vendorSell, linkVerified, uncached = getLinkVerifiedVendorSell(itemID, itemLink, allowLoad)
	if uncached then
		return nil, true
	end
	if not vendorSell or vendorSell <= minPrice then
		return nil, false
	end
	local profitPerUnit = vendorSell - minPrice
	if profitPerUnit < minProfit then
		return nil, false
	end

	local count = math.max(1, math.floor(safeNumber(qty) or 1))
	local totalCost = minPrice * count
	local totalProfit = profitPerUnit * count
	local roiPct = (profitPerUnit / minPrice) * 100
	local itemName, itemIcon, itemQuality, resolvedLink = getItemDisplayMeta(itemID, itemLink)
	local itemKey = extra and safeTable(extra.itemKey) or nil
	local idKey = makeVendorDealKey(itemID, itemKey)
	local isCommBool = (isComm == true)

	return {
		idKey = idKey,
		kind = isCommBool and "commodity" or "item",
		mode = "vendor",
		itemID = itemID,
		itemKey = itemKey,
		itemName = itemName,
		icon = itemIcon,
		quality = itemQuality,
		itemLink = itemLink or resolvedLink,
		isCommodity = isCommBool,
		ahPrice = minPrice,
		buyUnit = minPrice,
		vendorSell = vendorSell,
		linkVerified = linkVerified,
		profitPerUnit = profitPerUnit,
		quantity = count,
		buyQty = count,
		totalCost = totalCost,
		totalProfit = totalProfit,
		roiPct = roiPct,
		source = source or "Snapshot",
		status = "unverified",
		foundAt = nowMono(),
	}, false
end

function SE.IngestBrowseBatch(rows, econOverride, opts)
	local list = safeTable(rows)
	if not list then return 0 end

	-- Hoist settings, thresholds, economy, and scratch table outside the per-row loop (B5)
	local optsTbl = safeTable(opts)
	local settings = SE.GetSettings()
	local econ = activeEconomy(econOverride)
	local now = nowMono()
	local autoVendor = settings.vendorAutoFromBrowse ~= false
	if optsTbl and optsTbl.autoVendor ~= nil then
		autoVendor = (optsTbl.autoVendor == true)
	end
	local minProfit = (optsTbl and safeNumber(optsTbl.minProfitCopper)) or settings.vendorMinProfitCopper or 0
	local includeComm = settings.vendorIncludeCommodities ~= false
	if optsTbl and optsTbl.includeCommodities ~= nil then
		includeComm = (optsTbl.includeCommodities == true)
	end
	local vendorExtra = {
		settings = settings,
		minProfitCopper = minProfit,
		includeCommodities = includeComm,
		itemKey = nil,
		itemLink = nil,
		isCommodity = nil,
	}

	local flagged = 0
	local validSeen = 0
	for i = 1, #list do
		local row = safeTable(list[i])
		if row then
			local itemKey = safeTable(row.itemKey)
			local itemID = safeNumber(row.itemID) or (itemKey and safeNumber(itemKey.itemID))
			local minPrice = safeNumber(row.minPrice)
			local totalQty = math.max(1, math.floor(safeNumber(row.totalQuantity) or 1))
			local itemLink = safeString(row.itemLink)
			local quality = safeNumber(row.quality)
			local isComm = safeBool(row.isCommodity)

			if itemID and itemID > 0 and minPrice and minPrice > 0 then
				validSeen = validSeen + 1
				local id = math.floor(itemID)
				local p = math.floor(minPrice)
				local cacheKey = makeItemKeySignature(id, itemKey) or id
				SE.browseCache[cacheKey] = {
					sig = cacheKey,
					itemID = id,
					itemKey = itemKey,
					minPrice = p,
					totalQuantity = totalQty,
					itemLink = itemLink,
					quality = quality,
					isCommodity = isComm,
					economy = econ,
					updatedAt = now,
				}
				if autoVendor then
					vendorExtra.itemKey = itemKey
					vendorExtra.itemLink = itemLink
					vendorExtra.isCommodity = isComm
					local deal, uncached = evaluateVendorCandidate(id, p, totalQty, "Browse", vendorExtra)
					if deal then
						upsertVendorDeal(deal)
						flagged = flagged + 1
					elseif uncached then
						queueUnresolvedVendor(cacheKey, id, {
							itemID = id,
							itemKey = itemKey,
							minPrice = p,
							totalQuantity = totalQty,
							itemLink = itemLink,
							isCommodity = isComm,
							source = "Browse",
						})
					end
				end
			end
		end
	end

	if SE.scan.active and SE.scan.awaitingBrowse and validSeen > 0 then
		SE.scan.browseSeen = (SE.scan.browseSeen or 0) + validSeen
		setStatusText(string.format("Stage 1/2: Sweeping all AH lowest prices (%d seen)...", SE.scan.browseSeen))
		notify("scan_progress", SE.GetScanProgress())
	end

	if flagged > 0 then
		-- Defer sortVendorDeals() + notify("vendor_deals") until OnBrowseScanComplete (B5)
		vendorDealsDirty = true
	end
	return flagged
end

-- Alias matching MarketScan Wave B hook signature
SE.OnBrowseBatch = SE.IngestBrowseBatch

function SE.OnBrowseScanComplete(econOverride, partial)
	local econ = activeEconomy(econOverride)
	local isPartial = (partial == true)
	local completeAt = nowMono()
	if not isPartial then
		SE.scan.lastBrowseAt = completeAt
		SE.scan.lastBrowseEcon = econ
		SE.scan.lastCompleteBrowseStart = SE.scan.browseStartMono or (completeAt - SE.BROWSE_FRESH_TTL)
	end
	SE.scan.browseStartMono = nil
	flushDeferredVendorDeals()
	notify("browse_complete", {
		economy = econ,
		partial = isPartial,
		vendorCount = #SE.vendorDeals,
	})
	-- Stage 1 -> Stage 2 automatic transition: drill ONLY live browse hits from this sweep
	if SE.scan.active and SE.scan.awaitingBrowse then
		SE.scan.awaitingBrowse = false
		SE.scan.startedBrowse = false
		if not isAHOpen() then
			SE.StopGapScan("Auction House closed.")
			return
		end
		if type(startGapDrillStage) == "function" then
			local drillOpts = {}
			for k, v in pairs(SE.scan.opts or {}) do drillOpts[k] = v end
			if not isPartial then
				drillOpts.browseOnly = true
				drillOpts.minUpdatedAt = SE.scan.lastCompleteBrowseStart
			else
				drillOpts.browseOnly = false
				drillOpts.minUpdatedAt = nil
			end
			startGapDrillStage(drillOpts, econ, true)
		end
	end
end

function SE.OnBrowseScanCancelled(econOverride, partial)
	SE.scan.browseStartMono = nil
	flushDeferredVendorDeals()
	if SE.scan.active and SE.scan.awaitingBrowse then
		SE.scan.awaitingBrowse = false
		SE.scan.startedBrowse = false
		SE.StopGapScan("Browse scan cancelled.")
	end
end

function SE.ScanSnapshotForVendorDeals(econOverride, opts)
	opts = safeTable(opts) or {}
	local econ = activeEconomy(econOverride or opts.econ)
	local snapItems = hydrateSnapshotItems(econ)
	if not snapItems then
		setStatusText("No snapshot data available for vendor scan.")
		return SE.vendorDeals
	end

	if opts.append ~= true then
		clearStaleVendorDeals()
	end

	local settings = SE.GetSettings()
	local minProfit = safeNumber(opts.vendorMinProfitCopper)
	if minProfit == nil then minProfit = safeNumber(opts.minProfitCopper) end
	if minProfit == nil then minProfit = safeNumber(opts.minProfit) end
	if minProfit == nil then minProfit = settings.vendorMinProfitCopper or 0 end
	local includeComm = settings.vendorIncludeCommodities ~= false
	if opts.vendorIncludeCommodities ~= nil then
		includeComm = (opts.vendorIncludeCommodities == true)
	elseif opts.includeCommodities ~= nil then
		includeComm = (opts.includeCommodities == true)
	end
	local vendorExtra = {
		settings = settings,
		minProfitCopper = minProfit,
		includeCommodities = includeComm,
	}

	local found = 0
	for idKey, rec in pairs(snapItems) do
		local id = safeNumber(idKey)
		local rt = safeTable(rec)
		if id and id > 0 and rt then
			local minP = safeNumber(rt.minBuyout)
			local snapQty = safeNumber(rt.qty) or 0
			if minP and minP > 0 and snapQty > 0 then
				local intId = math.floor(id)
				local p = math.floor(minP)
				local qty = math.max(1, math.floor(snapQty))
				local deal, uncached = evaluateVendorCandidate(intId, p, qty, "Snapshot", vendorExtra)
				if deal then
					upsertVendorDeal(deal)
					found = found + 1
				elseif uncached then
					queueUnresolvedVendor(intId, intId, {
						itemID = intId,
						minPrice = p,
						totalQuantity = qty,
						source = "Snapshot",
					})
				end
			end
		end
	end

	vendorDealsDirty = false
	sortVendorDeals()
	setStatusText(string.format("Vendor snapshot scan: %d profitable items found.", found))
	notify("vendor_deals", SE.vendorDeals)
	return SE.vendorDeals
end

function SE.GetVendorDeals()
	return SE.vendorDeals
end

function SE.ClearVendorDeals()
	if SE.purchase and SE.purchase.mode == "vendor" then
		SE.CancelActivePurchase("Cleared vendor deals")
	end
	SE.pendingCheck = nil
	SE.vendorDeals = {}
	SE.vendorDealsByKey = {}
	SE.unresolvedVendor = {}
	unresolvedVendorByID = {}
	vendorDealsDirty = false
	notify("vendor_deals", SE.vendorDeals)
end

function SE.DismissDeal(deal)
	if not safeTable(deal) or not deal.idKey then return false end
	if SE.purchase and SE.purchase.deal == deal then return false end
	if SE.pendingCheck and SE.pendingCheck.deal == deal then return false end
	if deal.mode == "vendor" then
		SE.vendorDealsByKey[deal.idKey] = nil
		for i = #SE.vendorDeals, 1, -1 do
			if SE.vendorDeals[i] == deal or SE.vendorDeals[i].idKey == deal.idKey then
				table.remove(SE.vendorDeals, i)
				break
			end
		end
		notify("vendor_deals", SE.vendorDeals)
		return true
	else
		SE.gapDealsByKey[deal.idKey] = nil
		for i = #SE.gapDeals, 1, -1 do
			if SE.gapDeals[i] == deal or SE.gapDeals[i].idKey == deal.idKey then
				table.remove(SE.gapDeals, i)
				break
			end
		end
		notify("gap_deals", SE.gapDeals)
		return true
	end
end

-------------------------------------------------------------------------------
-- Protected Purchase State Machine (WoW Forever 2-Click Commodity & Item)
-------------------------------------------------------------------------------

local function abortPurchase(reason, cancelServer)
	local p = SE.purchase
	if not p then return end
	if cancelServer and p.kind == "commodity"
		and (p.state == "quoting" or p.state == "awaiting_confirm" or p.state == "confirming") then
		if safeTable(_G.C_AuctionHouse) and type(_G.C_AuctionHouse.CancelCommoditiesPurchase) == "function" then
			pcall(_G.C_AuctionHouse.CancelCommoditiesPurchase)
		end
	end
	SE.purchase = nil
	releaseSniperChannel()
	if p.deal then
		if p.deal.mode == "vendor" and p.deal.status ~= "bought" then
			p.deal.status = (p.deal.verifiedAt and "ready_to_buy") or "unverified"
		elseif p.deal.status ~= "bought" then
			p.deal.status = "ready"
		end
		p.deal.lastError = reason
	end
	setStatusText(reason or "Purchase cancelled.")
	notify("purchase_cancelled", { purchase = p, reason = reason })
end

function SE.CancelActivePurchase(reason)
	if not SE.purchase then return false end
	abortPurchase(reason or "Purchase cancelled by user.", true)
	return true
end

function SE.GetPurchaseState()
	return SE.purchase
end

-- Click 1 for Commodity Buy (strictly synchronous inside button OnClick):
-- Calls C_AuctionHouse.StartCommoditiesPurchase(itemID, qty) with EXACTLY 2 args.
function SE.StartCommodityBuy(deal)
	if not safeTable(deal) then return false, "no_deal" end
	if not isAHOpen() then
		setStatusText("Open the Auction House before buying.")
		return false, "ah_closed"
	end
	if isCartBuyerConfirming() then
		setStatusText("Finish Cart Buyer confirmation before starting a sniper purchase.")
		return false, "cart_buyer_busy"
	end
	if SE.purchase then
		return false, "purchase_in_flight"
	end
	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.StartCommoditiesPurchase) == "function") then
		return false, "api_unavailable"
	end
	if not isThrottledReady() then
		setStatusText("Auction House busy. Click Buy again in a moment.")
		return false, "throttled"
	end

	local itemID = safeNumber(deal.itemID)
	local qty = math.floor(safeNumber(deal.buyQty) or safeNumber(deal.quantity) or 0)
	local expectedTotal = math.floor(safeNumber(deal.totalCost) or safeNumber(deal.totalPrice) or 0)
	if not itemID or itemID <= 0 or qty <= 0 or expectedTotal <= 0 then
		return false, "invalid_deal"
	end

	local playerMoney = getPlayerMoney()
	if playerMoney ~= nil and expectedTotal > playerMoney then
		setStatusText("Not enough gold for this purchase.")
		return false, "insufficient_gold"
	end

	local settings = SE.GetSettings()
	local tolPct = math.max(0, safeNumber(settings.tolerancePct) or 5)
	local maxTotalWithTol = math.floor(expectedTotal * (1 + tolPct / 100))

	-- Vendor commodity buys must never exceed guaranteed vendor proceeds
	if deal.mode == "vendor" then
		local vSell = safeNumber(deal.vendorSell) or 0
		local vMinP = settings.vendorMinProfitCopper or 0
		local vendorCeiling = (vSell * qty) - math.max(1, vMinP)
		if vendorCeiling <= 0 then
			return false, "unprofitable"
		end
		maxTotalWithTol = math.min(maxTotalWithTol, vendorCeiling)
	end

	local okCh, errCh = acquireSniperChannel("commodity")
	if not okCh then
		setStatusText("Auction House channel busy (" .. tostring(errCh or "busy") .. ").")
		return false, errCh or "ah_busy"
	end

	local p = {
		idKey = deal.idKey,
		kind = "commodity",
		mode = deal.mode or "gap",
		deal = deal,
		itemID = itemID,
		qty = qty,
		expectedTotal = expectedTotal,
		maxTotalWithTolerance = maxTotalWithTol,
		vendorSell = safeNumber(deal.vendorSell),
		estProfit = safeNumber(deal.netProfit) or safeNumber(deal.totalProfit) or 0,
		state = "quoting",
		quoteSerial = 0,
		startedAt = nowMono(),
	}
	SE.purchase = p
	deal.status = "quoting"
	deal.lastError = nil
	setStatusText(string.format("Quoting %dx %s...", qty, deal.itemName or ("Item " .. tostring(itemID))))
	notify("purchase_started", p)

	-- EXACTLY 2 arguments (WoW Forever blocks a 3rd unitPrice argument!)
	local ok, accepted = pcall(ah.StartCommoditiesPurchase, itemID, qty)
	if SE.purchase ~= p then
		return false, "aborted_during_call"
	end
	if not ok or accepted == false then
		abortPurchase("Could not start commodity purchase.", false)
		return false, "start_failed"
	end

	afterDelay(SE.QUOTE_TIMEOUT, function()
		if SE.purchase == p and p.state == "quoting" then
			abortPurchase("Commodity price quote timed out (30s).", true)
		end
	end)
	return true
end

-- Click 2 for Commodity Buy (strictly synchronous inside button OnClick):
-- Calls C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, qty) after quote passed.
function SE.ConfirmCommodityBuy(deal)
	local p = SE.purchase
	if not p or p.kind ~= "commodity" or p.state ~= "awaiting_confirm" then
		return false, "not_awaiting_confirm"
	end
	if deal and p.deal ~= deal and deal.idKey ~= p.idKey then
		return false, "deal_mismatch"
	end
	if not isAHOpen() then
		abortPurchase("Auction House closed before confirm.", false)
		return false, "ah_closed"
	end
	if isCartBuyerConfirming() then
		return false, "cart_buyer_busy"
	end
	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.ConfirmCommoditiesPurchase) == "function") then
		abortPurchase("ConfirmCommoditiesPurchase unavailable.", true)
		return false, "api_unavailable"
	end

	local playerMoney = getPlayerMoney()
	if playerMoney ~= nil and p.verifiedTotalPrice and p.verifiedTotalPrice > playerMoney then
		abortPurchase("Not enough gold for Blizzard's quote.", true)
		return false, "insufficient_gold"
	end

	p.state = "confirming"
	if p.deal then p.deal.status = "confirming" end
	setStatusText("Confirming commodity purchase...")
	notify("purchase_confirming", p)

	-- Blizzard / WoW Forever ConfirmCommoditiesPurchase takes (itemID, quantity)
	local ok, accepted = pcall(ah.ConfirmCommoditiesPurchase, p.itemID, p.qty)
	if SE.purchase ~= p then
		return false, "aborted_during_call"
	end
	if not ok or accepted == false then
		abortPurchase("Commodity purchase confirmation failed.", true)
		return false, "confirm_failed"
	end

	-- Watchdog: never leave SE.purchase permanently wedged if Blizzard drops completion
	afterDelay(SE.QUOTE_TIMEOUT, function()
		if SE.purchase == p and p.state == "confirming" then
			abortPurchase("Commodity purchase confirmation timed out (30s).", false)
		end
	end)
	return true
end

local function extractTiersFromMarketScanResult(res)
	local tiers = {}
	local raw = safeTable(res.rawRows)
	if raw and #raw > 0 then
		for i = 1, #raw do
			local r = safeTable(raw[i])
			if r then
				local up = safeNumber(r.unitPrice)
				local q = safeNumber(r.competitorQty)
				if q == nil then q = safeNumber(r.quantity) end
				if up and up > 0 and q and q > 0 then
					tiers[#tiers + 1] = { unitPrice = math.floor(up), quantity = math.floor(q) }
				end
			end
		end
		return tiers
	end
	local lots = safeTable(res.lots)
	if lots then
		for i = 1, #lots do
			local l = safeTable(lots[i])
			if l then
				local up = safeNumber(l.price)
				local q = safeNumber(l.n)
				if up and up > 0 and q and q > 0 then
					tiers[#tiers + 1] = { unitPrice = math.floor(up), quantity = math.floor(q) }
				end
			end
		end
	end
	return tiers
end

local function applyVendorItemRows(deal, rows)
	local settings = SE.GetSettings()
	local minProfit = settings.vendorMinProfitCopper or 0
	local best = nil
	local list = safeTable(rows) or {}

	for i = 1, #list do
		local info = safeTable(list[i])
		if info then
			local owned = (safeBool(info.containsOwnerItem) == true)
				or (safeBool(info.containsAccountItem) == true)
				or ((safeNumber(info.numOwnerItems) or 0) > 0)
			local buyout = safeNumber(info.buyoutAmount)
			local auctionID = safeNumber(info.auctionID)
			if not owned and buyout and buyout > 0 and auctionID then
				buyout = math.floor(buyout)
				local qty = math.max(1, math.floor(safeNumber(info.quantity) or 1))
				local liveLink = safeString(info.itemLink)
				local liveVendor = getLinkVerifiedVendorSell(deal.itemID, liveLink)
				if liveVendor and (liveVendor * qty) > buyout then
					local totalProfit = (liveVendor * qty) - buyout
					local unitBuyout = math.floor(buyout / qty)
					local profitPerUnit = liveVendor - unitBuyout
					if totalProfit >= minProfit and (not best or totalProfit > best.totalProfit) then
						best = {
							auctionID = auctionID,
							buyoutAmount = buyout,
							quantity = qty,
							unitBuyout = unitBuyout,
							itemLink = liveLink,
							vendorSell = liveVendor,
							profitPerUnit = profitPerUnit,
							totalProfit = totalProfit,
						}
					end
				end
			end
		end
	end

	SE.pendingCheck = nil
	if best then
		deal.kind = "item"
		deal.isCommodity = false
		deal.auctionID = best.auctionID
		deal.buyoutAmount = best.buyoutAmount
		deal.ahPrice = best.unitBuyout
		deal.buyUnit = best.unitBuyout
		deal.itemLink = best.itemLink or deal.itemLink
		deal.vendorSell = best.vendorSell
		deal.linkVerified = (best.itemLink ~= nil)
		deal.profitPerUnit = best.profitPerUnit
		deal.quantity = best.quantity
		deal.buyQty = best.quantity
		deal.totalCost = best.buyoutAmount
		deal.totalProfit = best.totalProfit
		deal.roiPct = (best.totalProfit / best.buyoutAmount) * 100
		deal.verifiedAt = nowMono()
		deal.status = "ready_to_buy"
		setStatusText("Live item verified below vendor value. Click Buy to purchase.")
		notify("vendor_checked", deal)
	else
		deal.status = "unavailable"
		deal.verifiedAt = nil
		setStatusText("Live check: no listing currently profitable below vendor value.")
		notify("vendor_unavailable", deal)
	end
end

local function applyVendorCommodityTiers(deal, tiers)
	local settings = SE.GetSettings()
	local vendorSell = getBaseVendorSell(deal.itemID) or deal.vendorSell or 0
	local minProfit = settings.vendorMinProfitCopper or 0
	local maxQty = math.floor(settings.vendorMaxQty or 0)
	local maxSpend = math.floor(settings.vendorMaxSpendCopper or 0)
	local spendCap = (maxSpend > 0) and maxSpend or math.huge
	local playerMoney = getPlayerMoney()
	if playerMoney ~= nil then
		spendCap = math.min(spendCap, math.max(0, math.floor(playerMoney)))
	end

	local totalQty, totalCost = 0, 0
	local list = safeTable(tiers) or {}
	for i = 1, #list do
		local t = list[i]
		if t.unitPrice >= vendorSell then break end
		local take = t.quantity
		if maxQty > 0 then take = math.min(take, maxQty - totalQty) end
		if spendCap < math.huge then
			take = math.min(take, math.floor((spendCap - totalCost) / t.unitPrice))
		end
		if take <= 0 then break end
		totalQty = totalQty + take
		totalCost = totalCost + (take * t.unitPrice)
	end

	SE.pendingCheck = nil
	local proceeds = vendorSell * totalQty
	local profit = proceeds - totalCost
	if totalQty > 0 and profit >= minProfit then
		deal.kind = "commodity"
		deal.isCommodity = true
		deal.vendorSell = vendorSell
		deal.buyQty = totalQty
		deal.quantity = totalQty
		deal.totalCost = totalCost
		deal.ahPrice = math.floor(totalCost / totalQty)
		deal.buyUnit = deal.ahPrice
		deal.profitPerUnit = vendorSell - deal.ahPrice
		deal.totalProfit = profit
		deal.roiPct = totalCost > 0 and ((profit / totalCost) * 100) or 0
		deal.verifiedAt = nowMono()
		deal.status = "ready_to_buy"
		setStatusText("Live commodity verified below vendor value. Click Buy to quote.")
		notify("vendor_checked", deal)
	else
		deal.status = "unavailable"
		deal.verifiedAt = nil
		setStatusText("Live check: no commodity units currently profitable below vendor value.")
		notify("vendor_unavailable", deal)
	end
end

-- Click 1 for Vendor Sniper: live exact search to fetch fresh auctionID + itemLink + buyout
function SE.StartVendorCheck(deal)
	if not safeTable(deal) then return false, "no_deal" end
	if not isAHOpen() then
		setStatusText("Open the Auction House before checking live auctions.")
		return false, "ah_closed"
	end
	if isCartBuyerActive() then
		setStatusText("Finish or pause Cart Buyer before checking live auctions.")
		return false, "cart_buyer_busy"
	end
	if SE.purchase then
		return false, "purchase_in_flight"
	end

	local ah = safeTable(_G.C_AuctionHouse)
	local itemKey = safeTable(deal.itemKey)
	if not itemKey and ah and type(ah.MakeItemKey) == "function" then
		local okKey, k = pcall(ah.MakeItemKey, deal.itemID, 0, 0, 0)
		if okKey then itemKey = safeTable(k) end
	end
	if not itemKey then
		itemKey = { itemID = deal.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
	end

	local isCommodity = deal.isCommodity
	if isCommodity == nil and ah and type(ah.GetItemKeyInfo) == "function" then
		local okInfo, info = pcall(ah.GetItemKeyInfo, itemKey, true)
		local it = okInfo and safeTable(info) or nil
		if it then
			isCommodity = safeBool(it.isCommodity)
		end
	end

	local ms = safeTable(ns.MarketScan)
	local useMarketScan = ms and type(ms.CheckItemLive) == "function"

	if not useMarketScan then
		if not (ah and type(ah.SendSearchQuery) == "function") then
			return false, "api_unavailable"
		end
		if not isThrottledReady() then
			setStatusText("Auction House busy. Click Check again in a moment.")
			return false, "throttled"
		end
	end

	checkSeq = checkSeq + 1
	local seq = checkSeq
	SE.pendingCheck = {
		seq = seq,
		mode = "vendor",
		deal = deal,
		itemID = deal.itemID,
		itemKey = itemKey,
		keySig = makeItemKeySignature(deal.itemID, itemKey),
		kind = (isCommodity == true) and "commodity" or "item",
		usingMarketScan = useMarketScan == true,
		startedAt = nowMono(),
	}
	deal.status = "checking"
	deal.lastError = nil
	setStatusText("Checking live Auction House listing...")
	notify("vendor_checking", deal)

	if useMarketScan then
		local okCall, started, err = pcall(ms.CheckItemLive, itemKey, function(res)
			if not SE.pendingCheck or SE.pendingCheck.seq ~= seq then return end
			local rt = safeTable(res)
			if not rt or rt.failed then
				SE.pendingCheck = nil
				deal.status = "unavailable"
				deal.verifiedAt = nil
				setStatusText("Live check failed or timed out. Click Check again.")
				notify("vendor_unavailable", deal)
				return
			end
			if rt.isCommodity == true or rt.whole == false then
				applyVendorCommodityTiers(deal, extractTiersFromMarketScanResult(rt))
			else
				applyVendorItemRows(deal, rt.rawRows)
			end
		end)
		if not okCall or started == false then
			SE.pendingCheck = nil
			deal.status = "unverified"
			setStatusText("Live check could not start. Try again.")
			notify("vendor_check_failed", deal)
			return false, err or "search_failed"
		end
	else
		local ok, accepted = pcall(ah.SendSearchQuery, itemKey, priceSortSpec(), true)
		if not ok or accepted == false then
			SE.pendingCheck = nil
			deal.status = "unverified"
			setStatusText("Live search rejected. Try again.")
			notify("vendor_check_failed", deal)
			return false, "search_failed"
		end
	end

	afterDelay(SE.SEARCH_TIMEOUT, function()
		if SE.pendingCheck and SE.pendingCheck.seq == seq then
			SE.pendingCheck = nil
			deal.status = "unverified"
			setStatusText("Live check timed out. Click Check again.")
			notify("vendor_check_failed", deal)
		end
	end)
	return true
end

-- Click 2 for Vendor Item Buy (strictly synchronous inside button OnClick):
-- Calls C_AuctionHouse.PlaceBid(auctionID, buyoutAmount).
function SE.ExecuteVendorBuy(deal)
	if not safeTable(deal) then return false, "no_deal" end
	if deal.status ~= "ready_to_buy" then
		return false, "not_verified"
	end
	if not isAHOpen() then
		setStatusText("Open the Auction House before buying.")
		return false, "ah_closed"
	end
	if isCartBuyerConfirming() then
		setStatusText("Finish Cart Buyer confirmation before buying.")
		return false, "cart_buyer_busy"
	end
	if SE.purchase then
		return false, "purchase_in_flight"
	end
	if deal.verifiedAt and (nowMono() - deal.verifiedAt) > SE.LIVE_CHECK_TTL then
		deal.status = "unverified"
		deal.verifiedAt = nil
		setStatusText("Live check expired. Click Check again.")
		notify("vendor_deals", SE.vendorDeals)
		return false, "expired"
	end

	if deal.kind == "commodity" then
		return SE.StartCommodityBuy(deal)
	end

	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.PlaceBid) == "function") then
		return false, "api_unavailable"
	end
	if not isThrottledReady() then
		setStatusText("Auction House busy. Click Buy again in a moment.")
		return false, "throttled"
	end

	local auctionID = safeNumber(deal.auctionID)
	local buyout = math.floor(safeNumber(deal.buyoutAmount) or 0)
	local qty = math.max(1, math.floor(safeNumber(deal.buyQty) or safeNumber(deal.quantity) or 1))
	local vendorSell = safeNumber(deal.vendorSell) or 0
	local totalVendorProceeds = vendorSell * qty
	if not auctionID or buyout <= 0 or buyout >= totalVendorProceeds then
		deal.status = "unverified"
		setStatusText("Listing no longer profitable below vendor value.")
		return false, "unprofitable"
	end

	local playerMoney = getPlayerMoney()
	if playerMoney ~= nil and buyout > playerMoney then
		setStatusText("Not enough gold for this auction.")
		return false, "insufficient_gold"
	end

	local okCh, errCh = acquireSniperChannel("item")
	if not okCh then
		setStatusText("Auction House channel busy (" .. tostring(errCh or "busy") .. ").")
		return false, errCh or "ah_busy"
	end

	local p = {
		idKey = deal.idKey,
		kind = "item",
		mode = "vendor",
		deal = deal,
		itemID = deal.itemID,
		auctionID = auctionID,
		buyoutAmount = buyout,
		qty = qty,
		vendorSell = vendorSell,
		estProfit = totalVendorProceeds - buyout,
		state = "buying",
		startedAt = nowMono(),
	}
	SE.purchase = p
	deal.status = "buying"
	setStatusText("Submitting buyout...")
	notify("purchase_started", p)

	local ok, accepted = pcall(ah.PlaceBid, auctionID, buyout)
	if SE.purchase ~= p then
		return false, "aborted_during_call"
	end
	if not ok or accepted == false then
		abortPurchase("PlaceBid failed.", false)
		return false, "bid_failed"
	end

	-- Watchdog: on Forever, sniped auctions fire UI_ERROR_MESSAGE and never
	-- AUCTION_HOUSE_PURCHASE_COMPLETED. Release SE.purchase after 15s.
	afterDelay(SE.BUY_WATCHDOG_TIMEOUT, function()
		if SE.purchase == p and p.state == "buying" then
			if p.deal then p.deal.verifiedAt = nil end
			abortPurchase("Auction buyout timed out (15s) - listing may have been sniped.", false)
		end
	end)
	return true
end

local function recalcItemGapDealRemaining(deal)
	local queue = safeTable(deal.buyQueue)
	local left = queue and #queue or 0
	deal.listingCount = left
	deal.remainingListings = left
	if left <= 0 then
		return 0
	end
	local remQty, remCost = 0, 0
	for i = 1, left do
		local e = safeTable(queue[i])
		if e then
			remQty = remQty + math.max(1, math.floor(safeNumber(e.quantity) or 1))
			remCost = remCost + math.max(0, math.floor(safeNumber(e.buyoutAmount) or 0))
		end
	end
	local avgBuy = remQty > 0 and (remCost / remQty) or 0
	local relist = safeNumber(deal.relistPrice) or 0
	local nextTier = safeNumber(deal.nextTierPrice) or relist
	local refPrice = safeNumber(deal.refPrice)
	local cutRate = safeNumber(deal.ahCutRate) or SE.GetDynamicAuctionCut()
	local isNeutral = (deal.isNeutral == true)
	local depHours = safeNumber(deal.depositHours) or SE.GetSettings().relistDurationHours or 8
	local vendorSell = safeNumber(deal.vendorSell)
	if vendorSell == nil then
		local firstLink = safeTable(queue[1]) and safeString(queue[1].itemLink) or deal.itemLink
		vendorSell = getLinkVerifiedVendorSell(deal.itemID, firstLink) or getBaseVendorSell(deal.itemID) or 0
	end
	local gross = relist * remQty
	local ahCut = math.floor(gross * cutRate + 0.5)
	local netProfit = (gross - ahCut) - remCost
	local deposit = SE.GetForeverAuctionDeposit(vendorSell, remQty, depHours, isNeutral)
	local roiPct = remCost > 0 and ((netProfit / remCost) * 100) or 0
	local effWall = (refPrice and refPrice > 0) and math.min(nextTier, refPrice) or nextTier
	local gapPct = avgBuy > 0 and (((effWall - avgBuy) / avgBuy) * 100) or 0
	local dailySold = safeNumber(deal.dailySold)
	local estHours = (dailySold and dailySold > 0) and ((remQty / dailySold) * 24) or nil

	deal.buyQty = remQty
	deal.quantity = remQty
	deal.totalCost = remCost
	deal.avgBuyPrice = avgBuy
	deal.grossRevenue = gross
	deal.ahCut = ahCut
	deal.netProfit = netProfit
	deal.deposit = deposit
	deal.netProfitAfterDeposit = netProfit - deposit
	deal.roiPct = roiPct
	deal.gapPct = gapPct
	deal.estHoursToSell = estHours
	return left
end

-- Click for Equipment / Non-Commodity Gap Sniper Buy (strictly synchronous inside OnClick):
-- Calls C_AuctionHouse.PlaceBid(entry.auctionID, entry.buyoutAmount) for deal.buyQueue[1].
function SE.StartItemGapBuy(deal)
	if not safeTable(deal) then return false, "no_deal" end
	if not isAHOpen() then
		setStatusText("Open the Auction House before buying.")
		return false, "ah_closed"
	end
	if isCartBuyerActive() then
		setStatusText("Finish or pause Cart Buyer before starting a sniper purchase.")
		return false, "cart_buyer_busy"
	end
	if SE.purchase then
		return false, "purchase_in_flight"
	end
	local queue = safeTable(deal.buyQueue)
	if not queue or #queue == 0 then
		if deal.needsLiveScan then
			setStatusText("Run a live Gap Scan to fetch live auction IDs before buying this item.")
			return false, "needs_live_scan"
		end
		setStatusText("No live listings remaining in buy queue.")
		return false, "empty_queue"
	end
	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.PlaceBid) == "function") then
		return false, "api_unavailable"
	end
	if not isThrottledReady() then
		setStatusText("Auction House busy. Click Buy again in a moment.")
		return false, "throttled"
	end

	local entry = safeTable(queue[1])
	local auctionID = entry and safeNumber(entry.auctionID)
	local buyout = entry and math.floor(safeNumber(entry.buyoutAmount) or 0)
	local qty = entry and math.max(1, math.floor(safeNumber(entry.quantity) or 1)) or 1
	if not auctionID or auctionID <= 0 or not buyout or buyout <= 0 then
		return false, "invalid_listing"
	end

	local playerMoney = getPlayerMoney()
	if playerMoney ~= nil and buyout > playerMoney then
		setStatusText("Not enough gold for this auction.")
		return false, "insufficient_gold"
	end

	local relist = safeNumber(deal.relistPrice) or 0
	local cut = safeNumber(deal.ahCutRate) or SE.GetDynamicAuctionCut()
	local gross = relist * qty
	local estProfit = (relist > 0) and (gross - math.floor(gross * cut + 0.5) - buyout) or 0

	local okCh, errCh = acquireSniperChannel("item")
	if not okCh then
		setStatusText("Auction House channel busy (" .. tostring(errCh or "busy") .. ").")
		return false, errCh or "ah_busy"
	end

	local p = {
		idKey = deal.idKey,
		kind = "item",
		mode = deal.mode or "gap",
		deal = deal,
		itemID = deal.itemID,
		auctionID = math.floor(auctionID),
		buyoutAmount = buyout,
		qty = qty,
		estProfit = estProfit,
		state = "buying",
		startedAt = nowMono(),
	}
	SE.purchase = p
	deal.status = "buying"
	deal.lastError = nil
	setStatusText(string.format("Buying %s (%d listings left)...",
		deal.itemName or ("Item " .. tostring(deal.itemID)), #queue))
	notify("purchase_started", p)

	local ok, accepted = pcall(ah.PlaceBid, p.auctionID, buyout)
	if SE.purchase ~= p then
		return false, "aborted_during_call"
	end
	if not ok or accepted == false then
		abortPurchase("PlaceBid failed.", false)
		return false, "bid_failed"
	end

	-- Watchdog: release SE.purchase after 15s if listing was sniped and no completion fires.
	-- Pop the dead sniped auctionID from buyQueue so the next click tries lot #2 (or re-checks live).
	afterDelay(SE.BUY_WATCHDOG_TIMEOUT, function()
		if SE.purchase == p and p.state == "buying" then
			local d = p.deal
			if d and safeTable(d.buyQueue) then
				local removeIdx = 1
				for i = 1, #d.buyQueue do
					local e = safeTable(d.buyQueue[i])
					if e and safeNumber(e.auctionID) == p.auctionID then
						removeIdx = i
						break
					end
				end
				if #d.buyQueue >= removeIdx then
					table.remove(d.buyQueue, removeIdx)
				end
				local left = recalcItemGapDealRemaining(d)
				if left == 0 then
					d.buyQueue = nil
					d.needsLiveScan = true
				end
			end
			abortPurchase("Auction buyout timed out (15s) - listing may have been sniped.", false)
			notify("gap_deals", SE.gapDeals)
		end
	end)
	return true
end

local function applyGapItemCheckRows(deal, rows, itemKey)
	SE.pendingCheck = nil
	if not safeTable(deal) then return end

	local evalOpts = {}
	if safeTable(deal._checkOpts) then
		for k, v in pairs(deal._checkOpts) do
			evalOpts[k] = v
		end
	end
	if evalOpts.refPrice == nil and deal.refPrice then evalOpts.refPrice = deal.refPrice end
	if evalOpts.dailySold == nil and deal.dailySold then evalOpts.dailySold = deal.dailySold end
	evalOpts.itemKey = safeTable(itemKey) or safeTable(deal.itemKey)
	evalOpts.itemLink = deal.itemLink
	evalOpts.source = "Live"

	local fresh = SE.EvaluateItemGap(deal.itemID, rows, evalOpts)
	if fresh then
		deal.kind = "item"
		deal.isCommodity = false
		deal.itemKey = fresh.itemKey or deal.itemKey
		deal.itemName = fresh.itemName or deal.itemName
		deal.icon = fresh.icon or deal.icon
		deal.quality = fresh.quality or deal.quality
		deal.itemLink = fresh.itemLink or deal.itemLink
		deal.buyQty = fresh.buyQty
		deal.quantity = fresh.quantity
		deal.listingCount = fresh.listingCount
		deal.remainingListings = fresh.remainingListings
		deal.totalListings = fresh.totalListings
		deal.boughtListings = 0
		deal.buyQueue = fresh.buyQueue
		deal.vendorSell = fresh.vendorSell
		deal.avgBuyPrice = fresh.avgBuyPrice
		deal.totalCost = fresh.totalCost
		deal.nextTierPrice = fresh.nextTierPrice
		deal.nextTierQty = fresh.nextTierQty
		deal.relistPrice = fresh.relistPrice
		deal.refPrice = fresh.refPrice
		deal.refSource = fresh.refSource
		deal.grossRevenue = fresh.grossRevenue
		deal.ahCutRate = fresh.ahCutRate
		deal.ahCut = fresh.ahCut
		deal.isNeutral = fresh.isNeutral
		deal.deposit = fresh.deposit
		deal.depositHours = fresh.depositHours
		deal.netProfit = fresh.netProfit
		deal.netProfitAfterDeposit = fresh.netProfitAfterDeposit
		deal.roiPct = fresh.roiPct
		deal.gapPct = fresh.gapPct
		deal.dailySold = fresh.dailySold
		deal.estHoursToSell = fresh.estHoursToSell
		deal.ladder = fresh.ladder
		deal.tiersBought = fresh.tiersBought
		deal.source = "Live"
		deal.foundAt = nowMono()
		deal.needsLiveScan = false
		deal.status = "ready"
		deal.lastError = nil
		sortGapDeals()
		setStatusText(string.format("Live listings verified (%d lots). Click Buy to purchase.", #fresh.buyQueue))
		notify("gap_checked", deal)
		notify("gap_deals", SE.gapDeals)
	else
		deal.status = "unavailable"
		deal.needsLiveScan = false
		deal.buyQueue = nil
		deal.listingCount = 0
		deal.remainingListings = 0
		setStatusText("Live check: no qualifying equipment gap listings currently on AH.")
		notify("gap_unavailable", deal)
		notify("gap_deals", SE.gapDeals)
	end
end

-- Click 1 for Snapshot Equipment Gap Deal: fetch live auctionIDs & build buyQueue
-- so Click 2 can execute PlaceBid synchronously inside OnClick.
function SE.CheckItemGapLive(deal)
	if not safeTable(deal) then return false, "no_deal" end
	if not isAHOpen() then
		setStatusText("Open the Auction House before checking live auctions.")
		return false, "ah_closed"
	end
	if isCartBuyerActive() then
		setStatusText("Finish or pause Cart Buyer before checking live auctions.")
		return false, "cart_buyer_busy"
	end
	if SE.purchase then
		return false, "purchase_in_flight"
	end

	local ah = safeTable(_G.C_AuctionHouse)
	local itemKey = safeTable(deal.itemKey)
	if not itemKey and ah and type(ah.MakeItemKey) == "function" then
		local okKey, k = pcall(ah.MakeItemKey, deal.itemID, 0, 0, 0)
		if okKey then itemKey = safeTable(k) end
	end
	if not itemKey then
		itemKey = { itemID = deal.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
	end

	local ms = safeTable(ns.MarketScan)
	local useMarketScan = ms and type(ms.CheckItemLive) == "function"
	if not useMarketScan then
		if not (ah and type(ah.SendSearchQuery) == "function") then
			return false, "api_unavailable"
		end
		if not isThrottledReady() then
			setStatusText("Auction House busy. Click Check again in a moment.")
			return false, "throttled"
		end
	end

	checkSeq = checkSeq + 1
	local seq = checkSeq
	SE.pendingCheck = {
		seq = seq,
		mode = "gap",
		deal = deal,
		itemID = deal.itemID,
		itemKey = itemKey,
		keySig = makeItemKeySignature(deal.itemID, itemKey),
		kind = "item",
		usingMarketScan = useMarketScan == true,
		startedAt = nowMono(),
	}
	deal.status = "checking"
	deal.lastError = nil
	setStatusText("Checking live Auction House listings...")
	notify("gap_checking", deal)
	notify("gap_deals", SE.gapDeals)

	if useMarketScan then
		local okCall, started, err = pcall(ms.CheckItemLive, itemKey, function(res)
			if not SE.pendingCheck or SE.pendingCheck.seq ~= seq then return end
			local rt = safeTable(res)
			if not rt or rt.failed then
				SE.pendingCheck = nil
				deal.status = "unavailable"
				deal.needsLiveScan = false
				deal.buyQueue = nil
				deal.listingCount = 0
				deal.remainingListings = 0
				setStatusText("Live check failed or timed out. Click Check again.")
				notify("gap_unavailable", deal)
				notify("gap_deals", SE.gapDeals)
				return
			end
			applyGapItemCheckRows(deal, rt.rawRows, rt.itemKey or itemKey)
		end)
		if not okCall or started == false then
			SE.pendingCheck = nil
			deal.status = "ready"
			setStatusText("Live check could not start. Try again.")
			notify("gap_check_failed", deal)
			notify("gap_deals", SE.gapDeals)
			return false, err or "search_failed"
		end
	else
		local ok, accepted = pcall(ah.SendSearchQuery, itemKey, priceSortSpec(), true)
		if not ok or accepted == false then
			SE.pendingCheck = nil
			deal.status = "ready"
			setStatusText("Live search rejected. Try again.")
			notify("gap_check_failed", deal)
			notify("gap_deals", SE.gapDeals)
			return false, "search_failed"
		end
	end

	afterDelay(SE.SEARCH_TIMEOUT, function()
		if SE.pendingCheck and SE.pendingCheck.seq == seq then
			SE.pendingCheck = nil
			deal.status = "ready"
			setStatusText("Live check timed out. Click Check again.")
			notify("gap_check_failed", deal)
			notify("gap_deals", SE.gapDeals)
		end
	end)
	return true
end

-- Unified synchronous OnClick handlers for UI_Sniper.lua
function SE.HandleRowAction(deal, action)
	if action == "cancel" then
		if SE.purchase and (not deal or SE.purchase.deal == deal) then
			return SE.CancelActivePurchase("Purchase cancelled by user.")
		end
		return false, "no_purchase"
	end
	if not safeTable(deal) then return false, "no_deal" end
	if deal.kind == "item" then
		if deal.needsLiveScan or not safeTable(deal.buyQueue) then
			return SE.CheckItemGapLive(deal)
		end
		return SE.StartItemGapBuy(deal)
	end
	if SE.purchase and SE.purchase.deal == deal
		and SE.purchase.kind == "commodity" and SE.purchase.state == "awaiting_confirm" then
		return SE.ConfirmCommodityBuy(deal)
	end
	return SE.StartCommodityBuy(deal)
end

function SE.HandleVendorAction(deal)
	if not safeTable(deal) then return false, "no_deal" end
	if SE.purchase and SE.purchase.deal == deal
		and SE.purchase.kind == "commodity" and SE.purchase.state == "awaiting_confirm" then
		return SE.ConfirmCommodityBuy(deal)
	end
	if deal.status == "ready_to_buy" then
		return SE.ExecuteVendorBuy(deal)
	end
	return SE.StartVendorCheck(deal)
end

-------------------------------------------------------------------------------
-- Live Gap Sniper 2-Stage Sweep & Rotation (Event-Driven, Zero OnUpdate)
-------------------------------------------------------------------------------

local function evaluateLiveGapResult(itemID, isItem, rawRows, tiers, itemKey)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return nil end

	local evalOpts = {}
	for k, v in pairs(SE.scan.opts or {}) do
		evalOpts[k] = v
	end
	local keySig = makeItemKeySignature(id, itemKey)
	local meta = (keySig and SE.scan.shortlistByKey and SE.scan.shortlistByKey[keySig])
		or (SE.scan.shortlistByID and SE.scan.shortlistByID[id])
		or nil
	if meta then
		if evalOpts.refPrice == nil and meta.refPrice then evalOpts.refPrice = meta.refPrice end
		if evalOpts.dailySold == nil and meta.dailySold then evalOpts.dailySold = meta.dailySold end
		if evalOpts.itemKey == nil and meta.itemKey then evalOpts.itemKey = meta.itemKey end
		if evalOpts.itemLink == nil and meta.itemLink then evalOpts.itemLink = meta.itemLink end
	end
	if safeTable(itemKey) then
		evalOpts.itemKey = itemKey
	end
	evalOpts.source = "Live"

	local deal
	if isItem then
		deal = SE.EvaluateItemGap(id, rawRows, evalOpts)
	else
		if safeTable(tiers) and #tiers >= 2 then
			deal = SE.EvaluateCommodityGap(id, tiers, evalOpts)
		end
	end

	if deal then
		upsertGapDeal(deal)
		SE.scan.dealsFound = SE.scan.dealsFound + 1
		notify("gap_deals", SE.gapDeals)
	end
	return deal
end

local function stepGapScan()
	if not SE.scan.active or SE.scan.phase ~= "drill" then return end
	if not isAHOpen() then
		SE.StopGapScan("Auction House closed.")
		return
	end
	if SE.purchase then
		-- Pause stepping while a purchase is in flight; resumes after completion/abort
		return
	end
	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.SendSearchQuery) == "function") then
		SE.StopGapScan("Auction House search API unavailable.")
		return
	end

	local nextIdx = SE.scan.index + 1
	if nextIdx > SE.scan.total then
		SE.StopGapScan(string.format("Gap scan complete: %d deals from %d hits.",
			SE.scan.dealsFound, SE.scan.scanned))
		return
	end

	if not isThrottledReady() then
		local seq = scanSeq
		afterDelay(0.25, function()
			if SE.scan.active and SE.scan.phase == "drill" and scanSeq == seq then
				stepGapScan()
			end
		end)
		return
	end

	local cand = SE.scan.shortlist[nextIdx]
	local itemKey = cand.itemKey
	if not itemKey and type(ah.MakeItemKey) == "function" then
		local okK, k = pcall(ah.MakeItemKey, cand.itemID, 0, 0, 0)
		if okK then itemKey = safeTable(k) end
	end
	if not itemKey then
		itemKey = { itemID = cand.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
	end
	local watchSig = cand.sig or makeItemKeySignature(cand.itemID, itemKey)

	SE.scan.index = nextIdx
	SE.scan.awaitingItemID = cand.itemID
	SE.scan.awaitingKeySig = watchSig
	SE.scan.awaitingItemKey = itemKey
	SE.scan.awaitingPages = 0

	notify("scan_progress", SE.GetScanProgress())
	local ok, accepted = pcall(ah.SendSearchQuery, itemKey, priceSortSpec(), true)
	if not ok or accepted == false then
		SE.scan.awaitingItemID = nil
		SE.scan.awaitingKeySig = nil
		SE.scan.awaitingItemKey = nil
		local seq = scanSeq
		afterDelay(0.5, function()
			if SE.scan.active and SE.scan.phase == "drill" and scanSeq == seq then
				stepGapScan()
			end
		end)
		return
	end

	local seq = scanSeq
	afterDelay(SE.SEARCH_TIMEOUT, function()
		if SE.scan.active and SE.scan.phase == "drill" and scanSeq == seq and SE.scan.awaitingKeySig == watchSig then
			SE.scan.awaitingItemID = nil
			SE.scan.awaitingKeySig = nil
			SE.scan.awaitingItemKey = nil
			SE.scan.scanned = SE.scan.scanned + 1
			stepGapScan()
		end
	end)
end

local function recordDrillCompletion(itemID, itemKey, deal)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return end
	local rSig = makeItemKeySignature(id, itemKey)
	local meta = (rSig and SE.scan.shortlistByKey and SE.scan.shortlistByKey[rSig])
		or (SE.scan.shortlistByID and SE.scan.shortlistByID[id])
		or nil
	local cacheSig = (meta and meta.sig) or rSig
	if meta and cacheSig ~= nil then
		SE.drillCache[cacheSig] = {
			minPrice = meta.minPrice,
			totalQuantity = meta.totalQuantity or 0,
			drilledAt = nowMono(),
			deal = deal,
		}
	end
end

local function findBrowseStarter()
	local ms = safeTable(ns.MarketScan)
	if ms and type(ms.EnsureBrowseRunning) == "function" then
		return ms.EnsureBrowseRunning, false, true
	end
	local app = safeTable(ns.app)
	-- Fallback if EnsureBrowseRunning is absent: attach if already active rather than toggling off
	if ms and type(ms.GetState) == "function" then
		local okS, st = pcall(ms.GetState)
		local stTbl = okS and safeTable(st) or nil
		if stTbl and safeBool(stTbl.active) == true then
			return nil, true, false
		end
	end
	if ms and type(ms.StartMarketScan) == "function" then
		return ms.StartMarketScan, false, false
	end
	if app and type(app.startMarketScan) == "function" then
		return app.startMarketScan, false, false
	end
	if app and type(app.refreshAllMarketValues) == "function" then
		return app.refreshAllMarketValues, false, false
	end
	return nil, false, false
end

startGapDrillStage = function(scanOpts, econ, fromBrowse)
	local opts = safeTable(scanOpts) or {}
	local buildOpts = {}
	for k, v in pairs(opts) do buildOpts[k] = v end
	buildOpts.econ = activeEconomy(econ or opts.econ)

	local shortlist, reusedDeals = SE.BuildGapShortlist(buildOpts)
	local emptyReason = (safeTable(shortlist) and safeString(shortlist.reason)) or nil
	local reusedCount = 0
	if safeTable(reusedDeals) and #reusedDeals > 0 then
		for i = 1, #reusedDeals do
			if reusedDeals[i] then
				upsertGapDeal(reusedDeals[i])
				reusedCount = reusedCount + 1
			end
		end
		notify("gap_deals", SE.gapDeals)
	end
	if #shortlist == 0 then
		SE.scan.active = false
		SE.scan.phase = "idle"
		SE.scan.awaitingBrowse = false
		SE.scan.startedBrowse = false
		SE.scan.browseStartMono = nil
		SE.scan.usingMarketScan = false
		SE.scan.shortlist = {}
		SE.scan.shortlistByID = {}
		SE.scan.shortlistByKey = {}
		SE.scan.total = 0
		SE.scan.scanned = 0
		SE.scan.dealsFound = reusedCount
		SE.scan.lastEmptyReason = (reusedCount == 0) and emptyReason or nil
		if reusedCount > 0 then
			setStatusText(string.format("Gap scan complete: %d cached deals (market unchanged).", reusedCount))
		elseif emptyReason == "insufficient_live_history" then
			setStatusText("Scan the AH at least twice (15+ minutes apart) to build local baseline prices for Gap Sniper.")
		else
			setStatusText("No items matched your shortlist filters.")
		end
		notify("scan_stopped", SE.GetScanProgress())
		return reusedCount > 0, reusedCount > 0 and "cached" or (emptyReason or "empty_shortlist")
	end
	SE.scan.lastEmptyReason = nil

	scanSeq = scanSeq + 1
	local seq = scanSeq
	local byID = {}
	local byKey = {}
	for i = 1, #shortlist do
		local entry = shortlist[i]
		local sig = entry.sig or makeItemKeySignature(entry.itemID, entry.itemKey)
		if sig ~= nil then
			byKey[sig] = entry
		end
		if byID[entry.itemID] == nil then
			byID[entry.itemID] = entry
		end
	end

	SE.scan.active = true
	SE.scan.phase = "drill"
	SE.scan.awaitingBrowse = false
	SE.scan.startedBrowse = false
	SE.scan.shortlist = shortlist
	SE.scan.shortlistByID = byID
	SE.scan.shortlistByKey = byKey
	SE.scan.index = 0
	SE.scan.total = #shortlist
	SE.scan.scanned = 0
	SE.scan.dealsFound = 0
	SE.scan.awaitingItemID = nil
	SE.scan.awaitingKeySig = nil
	SE.scan.awaitingItemKey = nil
	SE.scan.awaitingPages = 0
	SE.scan.opts = opts
	SE.scan.usingMarketScan = false

	local ms = safeTable(ns.MarketScan)
	if ms and type(ms.StartSniperQueue) == "function" then
		local queueItems = {}
		for i = 1, #shortlist do
			queueItems[i] = shortlist[i].itemKey or shortlist[i].itemID
		end
		SE.scan.usingMarketScan = true
		setStatusText(string.format("Stage 2/2: Drilling 0 / %d hits | Deals: 0", #shortlist))
		notify(fromBrowse and "scan_progress" or "scan_started", SE.GetScanProgress())

		local okCall, started, addedOrErr = pcall(ms.StartSniperQueue, queueItems, function(res)
			if not SE.scan.active or scanSeq ~= seq then return end
			local rt = safeTable(res)
			if rt and rt.cancelled == true then
				SE.scan.active = false
				SE.scan.phase = "idle"
				SE.scan.usingMarketScan = false
				setStatusText("Gap scan cancelled.")
				notify("scan_stopped", SE.GetScanProgress())
				return
			end
			SE.scan.scanned = SE.scan.scanned + 1
			if rt and not rt.failed then
				local isItem = (rt.whole == true) or (rt.isCommodity == false)
				local deal
				if isItem then
					deal = evaluateLiveGapResult(rt.itemID, true, rt.rawRows, nil, rt.itemKey)
				else
					local tiers = extractTiersFromMarketScanResult(rt)
					deal = evaluateLiveGapResult(rt.itemID, false, nil, tiers, rt.itemKey)
				end
				recordDrillCompletion(rt.itemID, rt.itemKey, deal)
			end
			setStatusText(string.format("Stage 2/2: Drilling %d / %d hits | Deals: %d",
				SE.scan.scanned, SE.scan.total, SE.scan.dealsFound))
			notify("scan_progress", SE.GetScanProgress())
			if SE.scan.scanned >= SE.scan.total then
				SE.scan.active = false
				SE.scan.phase = "idle"
				SE.scan.usingMarketScan = false
				setStatusText(string.format("Gap scan complete: %d deals from %d hits.",
					SE.scan.dealsFound, SE.scan.scanned))
				notify("scan_stopped", SE.GetScanProgress())
			end
		end, { maxPages = SE.MAX_COMMODITY_PAGES })

		if not okCall or started == false then
			SE.scan.active = false
			SE.scan.phase = "idle"
			SE.scan.usingMarketScan = false
			setStatusText("Could not start live Gap Scan.")
			notify("scan_stopped", SE.GetScanProgress())
			return false, addedOrErr or "queue_failed"
		end

		local added = safeNumber(addedOrErr)
		if added and added >= 0 then
			SE.scan.total = math.floor(added)
			if SE.scan.active and scanSeq == seq then
				if SE.scan.total == 0 or SE.scan.scanned >= SE.scan.total then
					SE.scan.active = false
					SE.scan.phase = "idle"
					SE.scan.usingMarketScan = false
					setStatusText(string.format("Gap scan complete: %d deals from %d hits.",
						SE.scan.dealsFound, SE.scan.scanned))
					notify("scan_stopped", SE.GetScanProgress())
				else
					setStatusText(string.format("Stage 2/2: Drilling %d / %d hits | Deals: %d",
						SE.scan.scanned, SE.scan.total, SE.scan.dealsFound))
					notify("scan_progress", SE.GetScanProgress())
				end
			end
		end
		return true
	end

	setStatusText(string.format("Stage 2/2: Drilling 0 / %d hits | Deals: 0", #shortlist))
	notify(fromBrowse and "scan_progress" or "scan_started", SE.GetScanProgress())
	stepGapScan()
	return true
end

function SE.StartGapScan(opts)
	if not isAHOpen() then
		setStatusText("Open the Auction House to run a live Gap Scan.")
		return false, "ah_closed"
	end
	if isCartBuyerActive(true) then
		setStatusText("Finish or pause Cart Buyer before starting a live Gap Scan.")
		return false, "cart_buyer_busy"
	end

	local scanOpts = {}
	if safeTable(opts) then
		for k, v in pairs(opts) do scanOpts[k] = v end
	end
	local econ = activeEconomy(scanOpts.econ)
	scanOpts.econ = econ

	if scanOpts.append ~= true and scanOpts.keepExisting ~= true then
		clearStaleGapDeals()
	end

	local browseFresh = false
	if SE.scan.lastBrowseAt and SE.scan.lastBrowseEcon == econ then
		local age = nowMono() - SE.scan.lastBrowseAt
		if age >= 0 and age < SE.BROWSE_FRESH_TTL then
			browseFresh = true
		end
	end

	local browseStarter, browseAlreadyActive, isEnsure = findBrowseStarter()
	local canBrowse = (browseStarter ~= nil) or browseAlreadyActive
	local wantBrowse = (scanOpts.fullHouseSweep ~= false)
		and (scanOpts.skipBrowse ~= true)
		and canBrowse
		and ((scanOpts.forceBrowse == true) or (not browseFresh))

	if wantBrowse then
		local ms = safeTable(ns.MarketScan)
		if SE.scan.usingMarketScan then
			if ms and type(ms.CancelSniperQueue) == "function" then
				pcall(ms.CancelSniperQueue)
			end
		end
		local alreadyActive = browseAlreadyActive
		if not alreadyActive and isEnsure and ms and type(ms.GetState) == "function" then
			local okS, st = pcall(ms.GetState)
			local stTbl = okS and safeTable(st) or nil
			if stTbl and safeBool(stTbl.active) == true then
				alreadyActive = true
			end
		end

		scanSeq = scanSeq + 1
		local seq = scanSeq
		SE.scan.active = true
		SE.scan.phase = "browse"
		SE.scan.awaitingBrowse = true
		SE.scan.startedBrowse = false
		SE.scan.browseSeen = 0
		SE.scan.browseStartMono = alreadyActive and (nowMono() - SE.BROWSE_FRESH_TTL) or nowMono()
		SE.scan.shortlist = {}
		SE.scan.shortlistByID = {}
		SE.scan.shortlistByKey = {}
		SE.scan.index = 0
		SE.scan.total = 0
		SE.scan.scanned = 0
		SE.scan.dealsFound = 0
		SE.scan.awaitingItemID = nil
		SE.scan.awaitingKeySig = nil
		SE.scan.awaitingItemKey = nil
		SE.scan.awaitingPages = 0
		SE.scan.lastEmptyReason = nil
		SE.scan.opts = scanOpts
		SE.scan.usingMarketScan = false
		setStatusText("Stage 1/2: Sweeping all AH lowest prices...")
		notify("scan_started", SE.GetScanProgress())

		if not browseAlreadyActive then
			-- Prune stale browseCache entries and stale vendor deals when starting a fresh browse
			if not alreadyActive then
				SE.PruneBrowseCache(econ)
				clearStaleVendorDeals()
			end
			local okCall, started, ensureStatus = pcall(browseStarter)
			-- Handle synchronous OnBrowseScanComplete / OnBrowseScanCancelled inside starter gracefully
			if scanSeq ~= seq or not SE.scan.awaitingBrowse then
				return true
			end
			if not okCall or started == false then
				SE.scan.active = false
				SE.scan.phase = "idle"
				SE.scan.awaitingBrowse = false
				SE.scan.startedBrowse = false
				SE.scan.browseStartMono = nil
				setStatusText("Could not start full AH Browse sweep.")
				notify("scan_stopped", SE.GetScanProgress())
				return false, "browse_failed"
			end
			if isEnsure and ensureStatus == "already_active" then
				SE.scan.startedBrowse = false
				SE.scan.browseStartMono = nowMono() - SE.BROWSE_FRESH_TTL
			else
				SE.scan.startedBrowse = true
			end
		end
		return true
	end

	-- When jumping directly to Stage 2 from a <60s complete browse (not skipBrowse),
	-- drill ONLY live browse hits from that sweep for the active economy.
	if browseFresh and canBrowse and scanOpts.skipBrowse ~= true and scanOpts.fullHouseSweep ~= false
		and scanOpts.browseOnly == nil and SE.scan.lastCompleteBrowseStart ~= nil then
		scanOpts.browseOnly = true
		scanOpts.minUpdatedAt = SE.scan.lastCompleteBrowseStart
	end

	return startGapDrillStage(scanOpts, econ, false)
end

function SE.StopGapScan(reason)
	scanSeq = scanSeq + 1
	local ms = safeTable(ns.MarketScan)
	local wasUsingMS = SE.scan.usingMarketScan
	local wasAwaitingBrowse = SE.scan.awaitingBrowse
	local wasStartedBrowse = SE.scan.startedBrowse

	-- Clear scan state BEFORE calling MarketScan cancel hooks to prevent re-entrancy
	SE.scan.active = false
	SE.scan.phase = "idle"
	SE.scan.awaitingBrowse = false
	SE.scan.startedBrowse = false
	SE.scan.browseStartMono = nil
	SE.scan.usingMarketScan = false
	SE.scan.awaitingItemID = nil
	SE.scan.awaitingKeySig = nil
	SE.scan.awaitingItemKey = nil
	SE.scan.awaitingPages = 0

	if wasUsingMS then
		if ms and type(ms.CancelSniperQueue) == "function" then
			pcall(ms.CancelSniperQueue)
		end
	end
	if wasAwaitingBrowse and wasStartedBrowse then
		if ms and type(ms.CancelBrowseScan) == "function" then
			pcall(ms.CancelBrowseScan)
		elseif ms and type(ms.CancelMarketScan) == "function" then
			pcall(ms.CancelMarketScan, false)
		elseif safeTable(ns.app) and type(ns.app.cancelMarketScan) == "function" then
			pcall(ns.app.cancelMarketScan, false)
		end
	end
	setStatusText(reason or "Gap scan stopped.")
	notify("scan_stopped", SE.GetScanProgress())
end

function SE.GetScanProgress()
	local neutral = SE.IsNeutralAH()
	return {
		active = SE.scan.active,
		phase = SE.scan.phase or "idle",
		awaitingBrowse = SE.scan.awaitingBrowse == true,
		browseSeen = SE.scan.browseSeen or 0,
		scanned = SE.scan.scanned,
		total = SE.scan.total,
		dealsFound = SE.scan.dealsFound,
		isNeutral = neutral,
		ahCutRate = neutral and SE.NEUTRAL_AH_CUT or SE.FACTION_AH_CUT,
		reason = SE.scan.lastEmptyReason,
		statusText = SE.scan.statusText,
	}
end

function SE.GetSessionStats()
	return SE.session
end

function SE.ResetSessionStats()
	SE.session.buys = 0
	SE.session.spent = 0
	SE.session.estProfit = 0
	SE.session.gapDealsFound = 0
	SE.session.vendorDealsFound = 0
	notify("session", SE.session)
end

-------------------------------------------------------------------------------
-- Event Handlers (Dedicated Event Frame - Never Swallowed by MarketScan)
-------------------------------------------------------------------------------

local function handleCommodityPriceUpdated(newUnitPrice, newTotalPrice)
	local p = SE.purchase
	if not p or p.kind ~= "commodity"
		or (p.state ~= "quoting" and p.state ~= "awaiting_confirm") then
		return
	end

	local unit = safeNumber(newUnitPrice)
	local total = safeNumber(newTotalPrice)
	if not unit or unit <= 0 or not total or total <= 0 then
		abortPurchase("Invalid or secret commodity quote received.", true)
		return
	end

	unit = math.floor(unit)
	total = math.floor(total)

	local playerMoney = getPlayerMoney()
	if playerMoney ~= nil and total > playerMoney then
		abortPurchase("Quote exceeds available gold.", true)
		return
	end

	if total > p.maxTotalWithTolerance then
		abortPurchase("Price moved above tolerance ceiling. Cancelled.", true)
		return
	end

	if p.mode == "vendor" and p.vendorSell then
		local proceeds = p.vendorSell * p.qty
		if total >= proceeds then
			abortPurchase("Commodity quote no longer below vendor sell value.", true)
			return
		end
	end

	p.verifiedUnitPrice = unit
	p.verifiedTotalPrice = total
	p.state = "awaiting_confirm"
	p.quoteSerial = (p.quoteSerial or 0) + 1
	if p.deal then
		p.deal.status = "awaiting_confirm"
		p.deal.quotedUnit = unit
		p.deal.quotedTotal = total
	end

	setStatusText(string.format("Quote locked: %dx at %dc total. Click Confirm to buy.", p.qty, total))
	notify("purchase_quoted", p)

	local window = SE.QUOTE_TIMEOUT
	local ah = safeTable(_G.C_AuctionHouse)
	if ah and type(ah.GetQuoteDurationRemaining) == "function" then
		local okQ, left = pcall(ah.GetQuoteDurationRemaining)
		local ln = okQ and safeNumber(left) or nil
		if ln and ln > 0 then
			window = math.max(5, math.min(120, ln))
		end
	end

	local serial = p.quoteSerial
	afterDelay(window, function()
		if SE.purchase == p and p.state == "awaiting_confirm" and p.quoteSerial == serial then
			abortPurchase("Commodity price quote expired before Confirm.", true)
		end
	end)
end

local function handleCommodityPurchaseSucceeded()
	local p = SE.purchase
	if not p or p.kind ~= "commodity" or p.state ~= "confirming" then
		return
	end
	if isCartBuyerConfirming() then
		return
	end
	SE.purchase = nil
	releaseSniperChannel()
	local spent = p.verifiedTotalPrice or p.expectedTotal or 0
	SE.session.buys = SE.session.buys + 1
	SE.session.spent = SE.session.spent + spent
	SE.session.estProfit = SE.session.estProfit + (p.estProfit or 0)
	if p.deal then
		p.deal.status = "bought"
	end
	setStatusText(string.format("Bought %dx %s.", p.qty, (p.deal and p.deal.itemName) or ("Item " .. tostring(p.itemID))))
	notify("purchase_succeeded", p)
	if SE.scan.active and not SE.scan.usingMarketScan then
		stepGapScan()
	end
end

local function handleItemPurchaseCompleted(auctionID)
	local p = SE.purchase
	if not p or p.kind ~= "item" or p.state ~= "buying" then
		return
	end
	local aid = safeNumber(auctionID)
	if auctionID ~= nil and (not aid or aid ~= p.auctionID) then
		return
	end
	SE.purchase = nil
	releaseSniperChannel()
	local spent = p.buyoutAmount or 0
	SE.session.buys = SE.session.buys + 1
	SE.session.spent = SE.session.spent + spent
	SE.session.estProfit = SE.session.estProfit + (p.estProfit or 0)

	local deal = p.deal
	if deal then
		if deal.mode == "gap" and safeTable(deal.buyQueue) then
			local removeIdx = 1
			for i = 1, #deal.buyQueue do
				local entry = safeTable(deal.buyQueue[i])
				if entry and safeNumber(entry.auctionID) == p.auctionID then
					removeIdx = i
					break
				end
			end
			if #deal.buyQueue >= removeIdx then
				table.remove(deal.buyQueue, removeIdx)
			end
			local left = recalcItemGapDealRemaining(deal)
			deal.boughtListings = (safeNumber(deal.boughtListings) or 0) + 1
			deal.totalListings = safeNumber(deal.totalListings) or (left + deal.boughtListings)
			if left > 0 then
				deal.status = "ready"
				setStatusText(string.format("Bought %s (%d cheap listings left - click Buy).",
					deal.itemName or ("Item " .. tostring(p.itemID)), left))
			else
				deal.status = "bought"
				setStatusText(string.format("Bought all cheap listings for %s.",
					deal.itemName or ("Item " .. tostring(p.itemID))))
			end
			notify("gap_deals", SE.gapDeals)
		else
			deal.status = "bought"
			setStatusText(string.format("Bought %s for %dc.",
				deal.itemName or ("Item " .. tostring(p.itemID)), spent))
		end
	else
		setStatusText(string.format("Bought Item %s for %dc.", tostring(p.itemID), spent))
	end
	notify("purchase_succeeded", p)
	if SE.scan.active and not SE.scan.usingMarketScan and SE.scan.phase == "drill" then
		stepGapScan()
	end
end

local function readLiveItemRows(searchKey)
	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.GetNumItemSearchResults) == "function"
		and type(ah.GetItemSearchResultInfo) == "function") then
		return {}
	end
	local okN, rawN = pcall(ah.GetNumItemSearchResults, searchKey)
	local count = okN and math.floor(safeNumber(rawN) or 0) or 0
	local rows = {}
	for i = 1, count do
		local okR, rawInfo = pcall(ah.GetItemSearchResultInfo, searchKey, i)
		local info = okR and safeTable(rawInfo) or nil
		if info then
			rows[#rows + 1] = info
		end
	end
	return rows
end

local function readLiveCommodityTiers(itemID)
	local ah = safeTable(_G.C_AuctionHouse)
	if not (ah and type(ah.GetNumCommoditySearchResults) == "function"
		and type(ah.GetCommoditySearchResultInfo) == "function") then
		return {}
	end
	local okN, rawN = pcall(ah.GetNumCommoditySearchResults, itemID)
	local n = okN and safeNumber(rawN) or 0
	local tiers = {}
	for i = 1, math.floor(n) do
		local okR, info = pcall(ah.GetCommoditySearchResultInfo, itemID, i)
		local rt = okR and safeTable(info) or nil
		if rt then
			local up = safeNumber(rt.unitPrice)
			local qty = safeNumber(rt.quantity)
			local own = safeNumber(rt.numOwnerItems) or 0
			if up and up > 0 and qty and qty > 0 then
				local avail = math.floor(qty) - math.max(0, math.floor(own))
				if avail > 0 then
					tiers[#tiers + 1] = { unitPrice = math.floor(up), quantity = avail }
				end
			end
		end
	end
	return tiers
end

local function handleVendorItemResults(itemKey)
	local pc = SE.pendingCheck
	if not pc or pc.usingMarketScan or pc.kind ~= "item" then return end
	local kt = safeTable(itemKey)
	local keyID = kt and safeNumber(kt.itemID)
	if keyID and keyID ~= pc.itemID then return end
	if kt and pc.keySig ~= nil then
		local gotSig = makeItemKeySignature(keyID or pc.itemID, kt)
		if gotSig ~= nil and gotSig ~= pc.keySig then return end
	end

	local searchKey = kt or pc.itemKey
	local rows = readLiveItemRows(searchKey)
	if pc.mode == "gap" then
		applyGapItemCheckRows(pc.deal, rows, searchKey)
	else
		applyVendorItemRows(pc.deal, rows)
	end
end

local function handleVendorCommodityResults(itemID)
	local pc = SE.pendingCheck
	if not pc or pc.usingMarketScan or pc.kind ~= "commodity" or pc.itemID ~= itemID then return end
	applyVendorCommodityTiers(pc.deal, readLiveCommodityTiers(itemID))
end

local function handleGapScanCommodityResults(itemID)
	if not SE.scan.active or SE.scan.phase ~= "drill" or SE.scan.awaitingItemID ~= itemID then return end
	local ah = safeTable(_G.C_AuctionHouse)
	if ah and type(ah.HasFullCommoditySearchResults) == "function"
		and type(ah.RequestMoreCommoditySearchResults) == "function"
		and SE.scan.awaitingPages < SE.MAX_COMMODITY_PAGES then
		local okF, full = pcall(ah.HasFullCommoditySearchResults, itemID)
		if okF and safeBool(full) == false then
			SE.scan.awaitingPages = SE.scan.awaitingPages + 1
			pcall(ah.RequestMoreCommoditySearchResults, itemID)
			return
		end
	end

	local tiers = readLiveCommodityTiers(itemID)
	SE.scan.awaitingItemID = nil
	SE.scan.awaitingKeySig = nil
	SE.scan.awaitingItemKey = nil
	SE.scan.scanned = SE.scan.scanned + 1
	recordDrillCompletion(itemID, nil)
	evaluateLiveGapResult(itemID, false, nil, tiers, nil)
	setStatusText(string.format("Stage 2/2: Drilling %d / %d hits | Deals: %d",
		SE.scan.scanned, SE.scan.total, SE.scan.dealsFound))
	notify("scan_progress", SE.GetScanProgress())
	stepGapScan()
end

local function handleGapScanItemResults(itemKey)
	if not SE.scan.active or SE.scan.usingMarketScan or SE.scan.phase ~= "drill" or not SE.scan.awaitingItemID then
		return
	end
	local kt = safeTable(itemKey)
	local keyID = kt and safeNumber(kt.itemID)
	if not keyID or keyID ~= SE.scan.awaitingItemID then
		return
	end
	local gotSig = makeItemKeySignature(keyID, kt)
	if SE.scan.awaitingKeySig ~= nil and gotSig ~= SE.scan.awaitingKeySig then
		return
	end
	local rows = readLiveItemRows(kt)
	SE.scan.awaitingItemID = nil
	SE.scan.awaitingKeySig = nil
	SE.scan.awaitingItemKey = nil
	SE.scan.scanned = SE.scan.scanned + 1
	recordDrillCompletion(keyID, kt)
	evaluateLiveGapResult(keyID, true, rows, nil, kt)
	setStatusText(string.format("Stage 2/2: Drilling %d / %d hits | Deals: %d",
		SE.scan.scanned, SE.scan.total, SE.scan.dealsFound))
	notify("scan_progress", SE.GetScanProgress())
	stepGapScan()
end

local function handleItemInfoReceived(itemID, success)
	local id = safeNumber(itemID)
	if not id or id <= 0 then return end
	id = math.floor(id)
	if safeBool(success) == false then return end

	local keysToCheck = nil
	local bucket = unresolvedVendorByID[id]
	if bucket then
		keysToCheck = {}
		for ck in pairs(bucket) do
			keysToCheck[#keysToCheck + 1] = ck
		end
	elseif SE.unresolvedVendor[id] then
		keysToCheck = { id }
	end
	if not keysToCheck or #keysToCheck == 0 then return end

	local anyAdded = false
	for i = 1, #keysToCheck do
		local ck = keysToCheck[i]
		local pending = SE.unresolvedVendor[ck]
		if pending then
			local deal, stillUncached = evaluateVendorCandidate(id, pending.minPrice, pending.totalQuantity, pending.source, {
				itemKey = pending.itemKey,
				itemLink = pending.itemLink,
				isCommodity = pending.isCommodity,
			})
			if not stillUncached then
				SE.unresolvedVendor[ck] = nil
				if bucket then bucket[ck] = nil end
			end
			if deal then
				upsertVendorDeal(deal)
				anyAdded = true
			end
		elseif bucket then
			bucket[ck] = nil
		end
	end
	if bucket and next(bucket) == nil then
		unresolvedVendorByID[id] = nil
	end
	if anyAdded then
		sortVendorDeals()
		notify("vendor_deals", SE.vendorDeals)
	end
end

function SE.OnEvent(event, arg1, arg2)
	if event == "AUCTION_HOUSE_SHOW" then
		SE.atAH = true
		neutralCache = nil
		SE.IsNeutralAH(true)
		notify("ah_show", { isNeutral = SE.IsNeutralAH(), ahCutRate = SE.GetDynamicAuctionCut() })
	elseif event == "AUCTION_HOUSE_CLOSED" then
		SE.atAH = false
		neutralCache = nil
		notReadySince = nil
		SE.drillCache = {}
		if SE.scan.active then
			SE.StopGapScan("Auction House closed.")
		end
		if SE.pendingCheck then
			if SE.pendingCheck.deal then
				SE.pendingCheck.deal.status = (SE.pendingCheck.mode == "gap") and "ready" or "unverified"
			end
			SE.pendingCheck = nil
		end
		if SE.purchase then
			abortPurchase("Auction House closed.", false)
		end
		releaseSniperChannel()
		notify("ah_closed")
	elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" or event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
		if SE.scan.active and SE.scan.awaitingBrowse then
			SE.StopGapScan("Browse scan interrupted.")
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		handleCommodityPriceUpdated(arg1, arg2)
	elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
		if SE.purchase and SE.purchase.kind == "commodity" then
			abortPurchase("Commodity price unavailable.", true)
		end
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		handleCommodityPurchaseSucceeded()
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		if SE.purchase and SE.purchase.kind == "commodity" then
			abortPurchase("Commodity purchase failed.", true)
		end
	elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
		handleItemPurchaseCompleted(arg1)
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		handleVendorItemResults(arg1)
		handleGapScanItemResults(arg1)
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		local id = safeNumber(arg1)
		if id and id > 0 then
			if SE.pendingCheck and not SE.pendingCheck.usingMarketScan
				and SE.pendingCheck.kind == "commodity" and SE.pendingCheck.itemID == id then
				handleVendorCommodityResults(id)
			elseif SE.scan.active and not SE.scan.usingMarketScan and SE.scan.awaitingItemID == id then
				handleGapScanCommodityResults(id)
			end
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		handleItemInfoReceived(arg1, arg2)
	end
end

local REGISTERED_EVENTS = {
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
	"AUCTION_HOUSE_PURCHASE_COMPLETED",
	"AUCTION_HOUSE_BROWSE_FAILURE",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"GET_ITEM_INFO_RECEIVED",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"ITEM_SEARCH_RESULTS_UPDATED",
}

-- Dedicated frame so MarketScan.HandleEvent can never swallow Sniper events.
-- Zero OnUpdate scripts attached!
function SE.InitEventFrame()
	if eventFrame then return eventFrame end
	if type(_G.CreateFrame) ~= "function" then return nil end
	local ok, f = pcall(_G.CreateFrame, "Frame")
	if not ok or not f then return nil end
	for i = 1, #REGISTERED_EVENTS do
		if type(f.RegisterEvent) == "function" then
			pcall(f.RegisterEvent, f, REGISTERED_EVENTS[i])
		end
	end
	if type(f.SetScript) == "function" then
		f:SetScript("OnEvent", function(_, event, arg1, arg2)
			SE.OnEvent(event, arg1, arg2)
		end)
	end
	eventFrame = f
	SE.eventFrame = f
	return f
end

SE.InitEventFrame()

return SE
