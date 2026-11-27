-- Unified Watchlist (Favorites) store, evaluator, and UI table provider for MerchantMaster.
local ADDON, ns = ...
if type(ns) ~= "table" then
	ADDON = ADDON or "MerchantMaster"
	ns = (type(_G.MerchantMasterNS) == "table" and _G.MerchantMasterNS) or {}
end
if ns.Watchlist then return end

local W = {}
ns.Watchlist = W

local C, H, S = {}, {}, {}

local HEAT_POPOVER_W = 368
local HEAT_POPOVER_H = 214
local APPLE_ROOT = "Interface\\AddOns\\" .. tostring(ADDON or "MerchantMaster") .. "\\Assets\\apple\\"

C.PRICE_DROP_THRESHOLD = -10.0

C.PROF_SHORT = {
	alchemy = "Alch",
	blacksmithing = "BS",
	enchanting = "Ench",
	engineering = "Eng",
	leatherworking = "LW",
	tailoring = "Tailor",
	cooking = "Cook",
	firstaid = "FA",
	poisons = "Pois",
	mining = "Mine",
	herbalism = "Herb",
	skinning = "Skin",
}

C.FILTER_PILLS = {
	{ key = "all",        label = "All",        tip = "Show all favorited recipes and standalone items." },
	{ key = "recipes",    label = "Recipes",    tip = "Show only favorited crafting recipes." },
	{ key = "items",      label = "Items",      tip = "Show only favorited standalone items and materials." },
	{ key = "profitable", label = "Profitable", tip = "Show only favorited recipes with positive net crafting profit." },
	{ key = "price_drop", label = "Price Drop", tip = "Show favorites whose current AH price is at least 10% below their 24-hour or 7-day baseline." },
}

C.KNOWN_FILTERS = {
	{ key = "all",     label = "Known: All" },
	{ key = "known",   label = "Known: Learned" },
	{ key = "unknown", label = "Known: Unlearned" },
}

C.DEMAND_FILTERS_FALLBACK = {
	{ key = "all",       label = "Demand: All" },
	{ key = "monopoly",  label = "Demand: Monopoly" },
	{ key = "high_turn", label = "Demand: High Turn (>=1x)" },
	{ key = "hot",       label = "Demand: Hot/Fav (>=0.15x)" },
	{ key = "unlisted",  label = "Demand: Unlisted (0)" },
	{ key = "listed",    label = "Demand: Listed (Yes)" },
	{ key = "cold",      label = "Demand: Cold (<0.05x)" },
}

C.COLUMNS = {
	-- 15 default visible columns (minWidth sum = 824px + 70px gaps = 894px, fits inside 1020px viewport)
	{ key = "fav",           label = "",             width = 26,  minWidth = 24,  grow = 0,    align = "CENTER", defaultAsc = true,  locked = true, noSort = true, isStar = true,
	  hint = "Favorite star: click to remove this recipe or item from your Watchlist." },
	{ key = "name",          label = "Item / Recipe", width = 186, minWidth = 124, grow = 1.70, align = "LEFT",   defaultAsc = true,  locked = true, icon = true,
	  hint = "Item or recipe name. Left-click for Quick Look, Right-click for Deep Analysis, Shift-click to add to Shopping List." },
	{ key = "kindLabel",     label = "Type",         width = 58,  minWidth = 42,  grow = 0.25, align = "LEFT",   defaultAsc = true,
	  hint = "Profession abbreviation for recipes (e.g. LW, Alch) or Item for standalone items." },
	{ key = "knownSort",     label = "Known",        width = 48,  minWidth = 38,  grow = 0.15, align = "CENTER", defaultAsc = false,
	  hint = "Whether you (or an alt in All Chars mode) know the recipe. Standalone items show -." },
	{ key = "ownedQty",      label = "Owned",        width = 48,  minWidth = 36,  grow = 0.20, align = "RIGHT",  defaultAsc = false,
	  hint = "Quantity owned across bags, bank, and tracked alts." },
	{ key = "listed",        label = "Listed",       width = 48,  minWidth = 36,  grow = 0.20, align = "RIGHT",  defaultAsc = false,
	  hint = "Active Auction House listing quantity." },
	{ key = "unitAH",        label = "AH Price",     width = 76,  minWidth = 62,  grow = 0.45, align = "RIGHT",  defaultAsc = false,
	  hint = "Current Auction House unit buyout price." },
	{ key = "craftCost",     label = "Craft Cost",   width = 76,  minWidth = 62,  grow = 0.45, align = "RIGHT",  defaultAsc = true,
	  hint = "Total reagent craft cost per output unit. Standalone items show -." },
	{ key = "profit",        label = "Profit",       width = 80,  minWidth = 64,  grow = 0.50, align = "RIGHT",  defaultAsc = false,
	  hint = "Net crafting profit per output unit after AH cut. Standalone items show -." },
	{ key = "marginPct",     label = "Margin",       width = 56,  minWidth = 46,  grow = 0.25, align = "RIGHT",  defaultAsc = false,
	  hint = "Return on craft cost (Profit / Craft Cost). Standalone items show -." },
	{ key = "salesPerDay",   label = "Sales/d",      width = 66,  minWidth = 54,  grow = 0.35, align = "RIGHT",  defaultAsc = false,
	  hint = "Estimated daily AH sales velocity." },
	{ key = "demandSort",    label = "Demand",       width = 96,  minWidth = 74,  grow = 0.60, align = "LEFT",   defaultAsc = false, heatStrip = true,
	  hint = "Market demand rating and 24-hour heat strip. Click when snapshot data exists for hourly timing." },
	{ key = "trend24hDelta", label = "24h Chg",      width = 72,  minWidth = 56,  grow = 0.40, align = "RIGHT",  defaultAsc = true,
	  hint = "Price change in gold/silver over the last 24 hours (Current AH vs 24h ago). Green = cheaper now; red = higher." },
	{ key = "trend24hPct",   label = "24h Trend",    width = 62,  minWidth = 48,  grow = 0.25, align = "RIGHT",  defaultAsc = true,
	  hint = "Current AH unit price vs 24 hours ago percentage change. Green = dropped (buy deal); red = rose." },
	{ key = "trendPct",      label = "7d Trend",     width = 60,  minWidth = 48,  grow = 0.25, align = "RIGHT",  defaultAsc = true,
	  hint = "Current AH unit price vs 7-day baseline percentage change." },
	-- 8 default hidden optional columns (toggleable in Cols popover)
	{ key = "trend7dDelta",  label = "7d Chg",       width = 72,  minWidth = 56,  grow = 0.40, align = "RIGHT",  defaultAsc = true,  defaultHidden = true,
	  hint = "Price change in gold/silver vs 7-day baseline." },
	{ key = "subCraftLabel", label = "Sub-Craft",    width = 72,  minWidth = 56,  grow = 0.30, align = "LEFT",   defaultAsc = true,  defaultHidden = true,
	  hint = "Sub-craft reagent sourcing mode for recipes (Sub-Craft or Buy). Standalone items show -." },
	{ key = "vendorSell",    label = "Vendor Sell",  width = 74,  minWidth = 58,  grow = 0.40, align = "RIGHT",  defaultAsc = false, defaultHidden = true,
	  hint = "NPC vendor sell price." },
	{ key = "turnoverPerDay", label = "Gold/d",      width = 76,  minWidth = 58,  grow = 0.45, align = "RIGHT",  defaultAsc = false, defaultHidden = true,
	  hint = "Estimated daily AH gold turnover (AH Price x Sales/d)." },
	{ key = "categoryLabel", label = "Category",     width = 88,  minWidth = 66,  grow = 0.50, align = "LEFT",   defaultAsc = true,  defaultHidden = true,
	  hint = "Profession or item category label." },
	{ key = "sourceLabel",   label = "Source",       width = 82,  minWidth = 62,  grow = 0.45, align = "LEFT",   defaultAsc = true,  defaultHidden = true,
	  hint = "Recipe or item acquisition source." },
	{ key = "requiredSkill", label = "Skill",        width = 48,  minWidth = 38,  grow = 0.20, align = "RIGHT",  defaultAsc = true,  defaultHidden = true,
	  hint = "Required profession skill level." },
	{ key = "wowheadURL",    label = "Wowhead",      width = 62,  minWidth = 48,  grow = 0.30, align = "CENTER", defaultAsc = true,  defaultHidden = true,
	  hint = "Click to copy the Wowhead link." },
}

C.NUMERIC_KEYS = {
	knownSort = true,
	ownedQty = true,
	listed = true,
	unitAH = true,
	craftCost = true,
	profit = true,
	marginPct = true,
	salesPerDay = true,
	demandSort = true,
	trend24hDelta = true,
	trend24hPct = true,
	trendPct = true,
	trend7dDelta = true,
	vendorSell = true,
	turnoverPerDay = true,
	requiredSkill = true,
}

C.FALLBACK = {
	text = { 1, 1, 1 },
	muted = { 0.60, 0.60, 0.64 },
	secondary = { 0.82, 0.82, 0.85 },
	gold = { 1.00, 0.82, 0.18, 1.00 },
	green = { 0.20, 0.78, 0.35 },
	blue = { 0.36, 0.72, 1.00 },
	red = { 1.00, 0.26, 0.27 },
	lightGreen = { 0.08, 0.56, 0.22 },
	lightRed = { 0.722, 0.078, 0.102 },
}

-- Internal state
S.version = 0
S.listeners = {}
S.fallbackStore = { version = 1, items = {} }
S.fallbackColConfig = { order = {}, hidden = {} }
for i, col in ipairs(C.COLUMNS) do
	S.fallbackColConfig.order[i] = col.key
	if col.defaultHidden then S.fallbackColConfig.hidden[col.key] = true end
end
S.localSort = { col = "profit", asc = false }
S.host = nil
S.latest = nil
S.view = nil
S.tbl = nil
S.rows = nil
S.filteredRows = nil
S.selectedKey = nil
S.shiftActive = false
S.lastShiftDown = false
S.prepared = {}
S.colEpoch = 0
S.cellCacheEpoch = 0
S.appliedColSig = nil
S.boundWidth = nil
S.evalSig = nil
S.cellValueCache = setmetatable({}, { __mode = "k" })
S.recipeIndex = nil
S.recipeIndexCount = -1
S.catalogByID = nil
S.catalogRef = nil

---------------------------------------------------------------------------------------------------
-- Core Utility Helpers
---------------------------------------------------------------------------------------------------

local function readable(v)
	return not (issecretvalue and issecretvalue(v))
		and not (type(v) == "table" and issecrettable and issecrettable(v))
end

local function number(v)
	if not readable(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

local function nonnegative(v)
	local n = number(v)
	if n and n >= 0 then return n end
	return nil
end

local function posInt(v)
	local n = tonumber(v)
	if not n or n ~= n or n <= 0 or n == math.huge then return nil end
	local f = math.floor(n)
	if f ~= n then return nil end
	return f
end

local function text(v)
	if readable(v) and type(v) == "string" then return v end
	return ""
end

local function shown(frame)
	if (type(frame) ~= "table" and type(frame) ~= "userdata") or type(frame.IsShown) ~= "function" then
		return false
	end
	local ok, val = pcall(frame.IsShown, frame)
	return ok and readable(val) and val == true
end

local function isMouseOverFrame(frame)
	if (type(frame) ~= "table" and type(frame) ~= "userdata") or type(frame.IsMouseOver) ~= "function" then
		return false
	end
	local ok, val = pcall(frame.IsMouseOver, frame)
	return ok and readable(val) and val == true
end

local function shiftKeyDown()
	if type(IsShiftKeyDown) ~= "function" then return false end
	local ok, val = pcall(IsShiftKeyDown)
	return ok and readable(val) and val == true
end

local function currentLocalHour()
	local fn = date or (os and os.date)
	if type(fn) == "function" then
		local ok, t = pcall(fn, "*t")
		if ok and type(t) == "table" and type(t.hour) == "number" then
			return t.hour
		end
	end
	local now = (time and time()) or 0
	return math.floor((now % 86400) / 3600)
end

local function snapshotsAvailable()
	if type(ns.HasSnapshots) == "function" then
		return ns.HasSnapshots() == true
	end
	return (ns.app and ns.app.snapshotExtension ~= nil) and true or false
end

local function colorHex(col, fallback)
	if type(col) ~= "table" then return fallback or "ffffff" end
	local r = math.max(0, math.min(255, math.floor((col[1] or 1) * 255 + 0.5)))
	local g = math.max(0, math.min(255, math.floor((col[2] or 1) * 255 + 0.5)))
	local b = math.max(0, math.min(255, math.floor((col[3] or 1) * 255 + 0.5)))
	return string.format("%02x%02x%02x", r, g, b)
end

local function getThemePalette()
	local T = ns.Theme
	if type(T) == "table" then
		if type(T.GetActivePalette) == "function" then
			local p = T.GetActivePalette()
			if type(p) == "table" then return p end
		end
		if type(T.PALETTES) == "table" and type(T.GetMode) == "function" then
			local p = T.PALETTES[T.GetMode()] or T.PALETTES.dark
			if type(p) == "table" then return p end
		end
		if type(T.PALETTE) == "table" then return T.PALETTE end
	end
	return nil
end

local function themeText(str)
	if type(str) ~= "string" then return str end
	local T = ns.Theme
	if type(T) == "table" and type(T.TransformText) == "function" then
		return T.TransformText(str)
	end
	return str
end

local function applyFont(fs, size, weight, flags)
	if type(fs) ~= "table" and type(fs) ~= "userdata" then return end
	local T = ns.Theme
	if type(T) == "table" and type(T.ApplyFont) == "function" then
		T.ApplyFont(fs, size, weight, flags)
		return
	end
	if type(fs.SetFont) == "function" then
		local target
		if type(T) == "table" then
			if type(T.ResolveFontPath) == "function" then
				target = T.ResolveFontPath(weight)
			elseif type(T.FONTS) == "table" then
				local wantBold = (weight == "semibold" or weight == "bold" or weight == "heavy")
				target = (wantBold and T.FONTS.semibold) or T.FONTS.regular or T.FONTS.fallback
			end
		end
		target = target or STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
		local sz = tonumber(size) or 12
		local fl = flags or ""
		local ok = fs:SetFont(target, sz, fl)
		local loaded = type(fs.GetFont) == "function" and select(1, fs:GetFont())
		if ok == false or (ok == nil and loaded ~= target) then
			fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF", sz, fl)
		end
	end
	if type(fs.SetShadowOffset) == "function" then fs:SetShadowOffset(0, 0) end
	if type(fs.SetShadowColor) == "function" then fs:SetShadowColor(0, 0, 0, 0) end
end

local function money(v, signed)
	if not number(v) then return "-" end
	local T = ns.Theme
	if T and type(T.FormatMoneyText) == "function" then
		return T.FormatMoneyText(v, signed)
	elseif T and type(T.FormatMoneyParts) == "function" then
		local parts = T.FormatMoneyParts(v, signed)
		if parts and parts.text then return parts.text end
	end
	if ns.FormatMoneyCompact then
		return ns.FormatMoneyCompact(v, signed)
	end
	return tostring(math.floor(v + 0.5)) .. "c"
end

local function moneyCompact(v, signed)
	if not number(v) then return "-" end
	if ns.FormatMoneyCompact then return ns.FormatMoneyCompact(v, signed) end
	return money(v, signed)
end

local function formatSalesCell(val, pal)
	if not number(val) then return "-" end
	local T = ns.Theme
	local raw = (type(T) == "table" and type(T.FormatSalesPerDay) == "function")
		and T.FormatSalesPerDay(val) or string.format("%.1f/d", val)
	pal = pal or getThemePalette()
	if pal and pal.mode == "light" and type(raw) == "string" then
		raw = raw:gsub("|cff7fd4ff", "|cff0066cc"):gsub("|cff6e6b64", "|cff6e6e73"):gsub("|cff7a766e", "|cff6e6e73")
	end
	return themeText(raw) or raw
end

local function fingerprint(tbl)
	if type(tbl) ~= "table" then return tostring(tbl) end
	local keys = {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for i = 1, #keys do
		local k = keys[i]
		local v = tbl[k]
		parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and ("{" .. fingerprint(v) .. "}") or tostring(v))
	end
	return table.concat(parts, ";")
end

function H.getDB(ctx)
	local c = ctx or S.latest
	return (type(c) == "table" and type(c.db) == "table" and c.db)
		or (type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB)
		or nil
end

function H.ensureStore(db)
	db = db or H.getDB()
	local store
	if type(db) == "table" then
		if type(db.watchlist) ~= "table" then
			db.watchlist = { version = 1, items = {} }
		end
		store = db.watchlist
	else
		store = S.fallbackStore
	end
	if type(store.version) ~= "number" then store.version = 1 end
	if type(store.items) ~= "table" then store.items = {} end
	return store
end

function H.now()
	if type(time) == "function" then
		local ok, t = pcall(time)
		if ok and number(t) then return t end
	end
	return 0
end

function H.active()
	if S.host and type(S.host.isActive) == "function" then
		return S.host.isActive() == true
	end
	return S.view ~= nil and shown(S.view)
end

function H.copyColumn(col)
	local copy = {}
	for k, v in pairs(col) do copy[k] = v end
	return copy
end

function H.setBtnText(btn, txt)
	if not btn then return end
	if btn.SetText then btn:SetText(txt) end
	if btn.fs and btn.fs.SetText then btn.fs:SetText(txt) end
end

function H.liftAndShowTooltip()
	if not GameTooltip then return end
	local T = ns.Theme
	if T and T.LiftTooltip then T.LiftTooltip(GameTooltip) end
	GameTooltip:Show()
end

function H.frameBounds(frame, scale)
	if not frame or type(frame.GetLeft) ~= "function" or type(frame.GetTop) ~= "function" then return end
	local factor = ((frame.GetEffectiveScale and frame:GetEffectiveScale()) or scale or 1) / (scale or 1)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return end
	return left * factor, top * factor, (left + (frame:GetWidth() or 0)) * factor, (top - (frame:GetHeight() or 0)) * factor
end

---------------------------------------------------------------------------------------------------
-- 1. Watchlist Public Data API & 3-Way Listener Sync
---------------------------------------------------------------------------------------------------

local function parseKeyString(str)
	if type(str) ~= "string" then return nil, nil end
	local s = str:match("^%s*(.-)%s*$")
	if s == "" then return nil, nil end
	local prefix, idStr = s:match("^(%a+):(%d+)$")
	if prefix and idStr then
		local id = posInt(idStr)
		if id then
			if prefix == "recipe" then
				local k = "recipe:" .. tostring(id)
				return k, { key = k, kind = "recipe", spellID = id, itemID = nil }
			elseif prefix == "item" then
				local k = "item:" .. tostring(id)
				return k, { key = k, kind = "item", itemID = id, spellID = nil }
			else
				return s, { key = s, kind = prefix, itemID = id, spellID = nil }
			end
		end
	end
	local bare = posInt(s)
	if bare then
		local k = "item:" .. tostring(bare)
		return k, { key = k, kind = "item", itemID = bare, spellID = nil }
	end
	return nil, nil
end

function W.NormalizeKey(target)
	if target == nil then return nil, nil end
	local ttype = type(target)
	if ttype == "number" then
		local id = posInt(target)
		if not id then return nil, nil end
		local k = "item:" .. tostring(id)
		return k, { key = k, kind = "item", itemID = id, spellID = nil }
	elseif ttype == "string" then
		return parseKeyString(target)
	elseif ttype ~= "table" then
		return nil, nil
	end

	local rec = type(target.recipe) == "table" and target.recipe or nil
	local row = type(target.row) == "table" and target.row or nil
	local rowRec = row and type(row.recipe) == "table" and row.recipe or nil

	local spellID = posInt(target.spellID)
		or posInt(rec and (rec.spellID or rec.recipeID))
		or posInt(row and row.spellID)
		or posInt(rowRec and (rowRec.spellID or rowRec.recipeID))

	local itemID = posInt(target.outputItemID)
		or posInt(target.itemID)
		or posInt(rec and rec.outputItemID)
		or posInt(row and (row.outputItemID or row.itemID))
		or posInt(rowRec and rowRec.outputItemID)

	local explicitKind = target.kind or (row and row.kind)

	if explicitKind == "recipe" or spellID then
		if spellID then
			local k = "recipe:" .. tostring(spellID)
			return k, { key = k, kind = "recipe", spellID = spellID, itemID = itemID }
		elseif itemID then
			local k = "item:" .. tostring(itemID)
			return k, { key = k, kind = "item", itemID = itemID, spellID = nil }
		end
	elseif itemID then
		local k = "item:" .. tostring(itemID)
		return k, { key = k, kind = "item", itemID = itemID, spellID = nil }
	end

	if type(target.key) == "string" then
		return parseKeyString(target.key)
	end
	return nil, nil
end

function H.ensureRecipeIndex()
	local list = type(ns.RECIPES) == "table" and ns.RECIPES or nil
	local count = list and #list or 0
	if S.recipeIndex and S.recipeIndexCount == count then
		return S.recipeIndex
	end
	local bySpell, byOutput = {}, {}
	for i = 1, count do
		local rec = list[i]
		if type(rec) == "table" then
			local sp = posInt(rec.spellID)
			if sp and not bySpell[sp] then
				bySpell[sp] = rec
			end
			local oid = posInt(rec.outputItemID)
			if oid and not rec.isEnchant then
				local prev = byOutput[oid]
				if not prev then
					byOutput[oid] = rec
				else
					local prevCD = (tonumber(prev.cd) or 0) > 0
					local curCD = (tonumber(rec.cd) or 0) > 0
					if prevCD and not curCD then
						byOutput[oid] = rec
					elseif prevCD == curCD and (tonumber(rec.skill) or 9999) < (tonumber(prev.skill) or 9999) then
						byOutput[oid] = rec
					end
				end
			end
		end
	end
	S.recipeIndex = { bySpell = bySpell, byOutput = byOutput }
	S.recipeIndexCount = count
	return S.recipeIndex
end

function H.ensureCatalogByID()
	if not (ns.AllItemsModel and type(ns.AllItemsModel.GetCatalog) == "function") then
		return nil
	end
	local cat = ns.AllItemsModel.GetCatalog()
	if cat == S.catalogRef and S.catalogByID then
		return S.catalogByID
	end
	local map = {}
	for i = 1, #(cat or {}) do
		local e = cat[i]
		if type(e) == "table" and e.itemID then
			map[e.itemID] = e
		end
	end
	S.catalogRef = cat
	S.catalogByID = map
	return map
end

function H.notifyListeners(event, key, entry)
	S.evalSig = nil
	S.cellCacheEpoch = S.cellCacheEpoch + 1
	local snapshot = {}
	for i = 1, #S.listeners do snapshot[i] = S.listeners[i] end
	for i = 1, #snapshot do
		local fn = snapshot[i]
		if type(fn) == "function" then
			pcall(fn, event, key, entry)
		end
	end
	if S.view and S.tbl then
		W.Refresh(S.latest)
	end
end

function W.Add(target)
	local key, meta = W.NormalizeKey(target)
	if not key or not meta then return nil, nil end
	local store = H.ensureStore()
	local existing = store.items[key]
	if type(existing) == "table" then
		-- Backfill itemID if previously missing
		if not existing.itemID and meta.itemID then existing.itemID = meta.itemID end
		if not existing.spellID and meta.spellID then existing.spellID = meta.spellID end
		return existing, key
	end
	local itemID = meta.itemID
	if not itemID and meta.spellID then
		local rIdx = H.ensureRecipeIndex()
		local rec = rIdx.bySpell[meta.spellID]
		if rec and posInt(rec.outputItemID) then
			itemID = posInt(rec.outputItemID)
		end
	end
	local entry = {
		key = key,
		kind = meta.kind,
		itemID = itemID,
		spellID = meta.spellID,
		addedAt = H.now(),
	}
	store.items[key] = entry
	S.version = S.version + 1
	H.notifyListeners("add", key, entry)
	return entry, key
end

function W.Remove(keyOrTarget)
	local key = W.NormalizeKey(keyOrTarget)
	if not key then return false, nil end
	local store = H.ensureStore()
	local existing = store.items[key]
	if existing == nil then return false, key end
	store.items[key] = nil
	S.version = S.version + 1
	H.notifyListeners("remove", key, existing)
	return true, key
end

function W.Toggle(target)
	local key = W.NormalizeKey(target)
	if not key then return false, nil, nil end
	local store = H.ensureStore()
	if store.items[key] ~= nil then
		local removed = W.Remove(key)
		return false, key, removed and nil or store.items[key]
	end
	local entry = W.Add(target)
	return entry ~= nil, key, entry
end

function W.IsFavorite(target)
	local key = W.NormalizeKey(target)
	if not key then return false end
	local store = H.ensureStore()
	return store.items[key] ~= nil
end

W.IsWatched = W.IsFavorite
W.Has = W.IsFavorite
W.Contains = W.IsFavorite

function W.FindFavoriteForItem(itemID)
	local id = posInt(itemID)
	if not id then return nil, nil end
	local store = H.ensureStore()
	local directKey = "item:" .. tostring(id)
	if type(store.items[directKey]) == "table" then
		return store.items[directKey], directKey
	end
	local rIdx = H.ensureRecipeIndex()
	local bestEntry, bestKey
	for k, entry in pairs(store.items) do
		if type(entry) == "table" then
			local matched = (posInt(entry.itemID) == id)
			if not matched and entry.spellID then
				local rec = rIdx.bySpell[posInt(entry.spellID)]
				if rec and posInt(rec.outputItemID) == id then
					matched = true
				end
			end
			if matched then
				if not bestEntry or (tonumber(entry.addedAt) or 0) < (tonumber(bestEntry.addedAt) or 0)
					or ((tonumber(entry.addedAt) or 0) == (tonumber(bestEntry.addedAt) or 0) and tostring(k) < tostring(bestKey)) then
					bestEntry = entry
					bestKey = k
				end
			end
		end
	end
	return bestEntry, bestKey
end

function W.GetEntries()
	local store = H.ensureStore()
	local out = {}
	for k, entry in pairs(store.items) do
		if type(entry) == "table" then
			if not entry.key then entry.key = k end
			out[#out + 1] = entry
		end
	end
	table.sort(out, function(a, b)
		local ta = tonumber(a.addedAt) or 0
		local tb = tonumber(b.addedAt) or 0
		if ta ~= tb then return ta < tb end
		return tostring(a.key or "") < tostring(b.key or "")
	end)
	return out
end

function W.GetCount()
	local store = H.ensureStore()
	local n = 0
	for _, entry in pairs(store.items) do
		if type(entry) == "table" then n = n + 1 end
	end
	return n
end

function W.GetVersion()
	return S.version
end

function W.Clear()
	local store = H.ensureStore()
	local hadAny = next(store.items) ~= nil
	for k in pairs(store.items) do store.items[k] = nil end
	if hadAny then
		S.version = S.version + 1
		H.notifyListeners("clear", nil, nil)
	end
	return hadAny
end

function W.RegisterListener(fn)
	if type(fn) ~= "function" then return function() end end
	for i = 1, #S.listeners do
		if S.listeners[i] == fn then
			return function()
				for j = #S.listeners, 1, -1 do
					if S.listeners[j] == fn then table.remove(S.listeners, j) end
				end
			end
		end
	end
	S.listeners[#S.listeners + 1] = fn
	return function()
		for j = #S.listeners, 1, -1 do
			if S.listeners[j] == fn then table.remove(S.listeners, j) end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 2. Unified Watchlist Row Evaluator & 7-Day Trend Computation
---------------------------------------------------------------------------------------------------

function H.resolveEconKey(context)
	local econ = text(context and context.economy)
	if econ ~= "" then return econ end
	if type(context) == "table" and type(context.econInfo) == "table" and text(context.econInfo.effectiveKey) ~= "" then
		return context.econInfo.effectiveKey
	end
	if ns.CurrentEconomyInfo then
		local info = ns.CurrentEconomyInfo()
		if type(info) == "table" and text(info.effectiveKey) ~= "" then
			return info.effectiveKey
		end
	end
	if ns.DetectActiveEconomy then
		local e = ns.DetectActiveEconomy()
		if type(e) == "string" and e ~= "" then return e end
	end
	return nil
end

function H.ownedQty(context, id, name)
	local sc = type(context) == "table" and type(context.statsContext) == "table" and context.statsContext or nil
	local ids = (sc and type(sc.ownedCountsByID) == "table" and sc.ownedCountsByID)
		or (type(context) == "table" and type(context.ownedCountsByID) == "table" and context.ownedCountsByID)
		or (MerchantMasterAPI and type(MerchantMasterAPI.GetOwnedCountsByID) == "function" and MerchantMasterAPI.GetOwnedCountsByID())
		or nil
	local counts = (type(context) == "table" and type(context.counts) == "table" and context.counts)
		or (type(context) == "table" and type(context.ownedCounts) == "table" and context.ownedCounts)
		or (sc and type(sc.ownedCounts) == "table" and sc.ownedCounts)
		or (S.host and type(S.host.getOwnedCounts) == "function" and S.host.getOwnedCounts())
		or (MerchantMasterAPI and type(MerchantMasterAPI.GetOwnedCounts) == "function" and MerchantMasterAPI.GetOwnedCounts())
		or nil
	local qty = (ids and id and nonnegative(ids[id])) or (counts and id and nonnegative(counts[id]))
	if not qty and name and counts then qty = nonnegative(counts[name]) end
	if not qty and id and ns.ItemName and counts then
		local liveNm = ns.ItemName(id)
		if liveNm then qty = nonnegative(counts[liveNm]) end
	end
	return qty or 0
end

function H.profShort(profKey)
	if type(profKey) ~= "string" or profKey == "" then return "Recipe" end
	if C.PROF_SHORT[profKey] then return C.PROF_SHORT[profKey] end
	local info = ns.PROF_BY_KEY and ns.PROF_BY_KEY[profKey]
	if type(info) == "table" then
		if type(info.short) == "string" and info.short ~= "" then return info.short end
		if type(info.label) == "string" and info.label ~= "" then return info.label end
	end
	return profKey:sub(1, 1):upper() .. profKey:sub(2, 4)
end

function H.computeTrend7d(itemID, unitAH, econKey, now)
	local id = posInt(itemID)
	if not id then return nil, nil, nil end
	local curDay = math.floor((number(now) or H.now()) / 86400)
	local baseline, source, directPct

	-- 1. MarketScan.GetItemTrend7d: prefer prior-day mean baseline when unitAH is known, else t7.trendPct
	if ns.MarketScan and type(ns.MarketScan.GetItemTrend7d) == "function" then
		local ok, t7 = pcall(ns.MarketScan.GetItemTrend7d, id, econKey, now)
		if ok and type(t7) == "table" then
			local pts = type(t7.points) == "table" and t7.points or nil
			if pts and #pts > 0 and number(unitAH) and unitAH > 0 then
				local sum, cnt = 0, 0
				for i = 1, #pts do
					local pt = pts[i]
					local d = type(pt) == "table" and number(pt.d)
					local p = type(pt) == "table" and nonnegative(pt.price)
					if d and p and p > 0 and d < curDay then
						sum = sum + p
						cnt = cnt + 1
					end
				end
				if cnt > 0 then
					baseline = sum / cnt
					source = t7.source or "trend7d"
				end
			end
			if not baseline and number(t7.trendPct) then
				directPct = t7.trendPct
				baseline = nonnegative(t7.startPrice7d)
				source = t7.source or "trend7d"
			elseif not baseline and number(unitAH) and unitAH > 0 and nonnegative(t7.startPrice7d) and t7.startPrice7d > 0 then
				baseline = t7.startPrice7d
				source = t7.source or "trend7d"
			end
		end
	end

	-- 2. Pricing.GetItemHeatStrip24h average price baseline
	if not baseline and not directPct and number(unitAH) and unitAH > 0
		and ns.Pricing and type(ns.Pricing.GetItemHeatStrip24h) == "function" then
		local ok, strip = pcall(ns.Pricing.GetItemHeatStrip24h, id, econKey)
		if ok and type(strip) == "table" then
			local avgP = nonnegative(strip.avgPrice)
			if avgP and avgP > 0 then
				baseline = avgP
				source = "heat24"
			end
		end
	end

	-- 3. Pricing.GetItemHeatmap overall average price baseline
	if not baseline and not directPct and number(unitAH) and unitAH > 0
		and ns.Pricing and type(ns.Pricing.GetItemHeatmap) == "function" then
		local ok, hm = pcall(ns.Pricing.GetItemHeatmap, id, econKey)
		if ok and type(hm) == "table" and type(hm.overall) == "table" then
			local avgP = nonnegative(hm.overall.avgPrice)
			if avgP and avgP > 0 then
				baseline = avgP
				source = "heatmap"
			end
		end
	end

	-- 4. Local snapshot historical / marketValue baseline
	if not baseline and not directPct and number(unitAH) and unitAH > 0
		and type(ns.QueryLocalSnapshot) == "function" then
		local ok, _, snapRec = pcall(ns.QueryLocalSnapshot, id, econKey)
		if ok and type(snapRec) == "table" then
			local hist = nonnegative(snapRec.historical) or nonnegative(snapRec.marketValue)
			if hist and hist > 0 then
				baseline = hist
				source = "snapshot"
			end
		end
	end

	if directPct ~= nil then
		return directPct, baseline, source
	end
	if baseline and baseline > 0 and number(unitAH) and unitAH > 0 then
		local pct = (unitAH - baseline) / baseline * 100
		if number(pct) then
			return pct, baseline, source
		end
	end
	return nil, nil, nil
end

function H.computeTrend24h(itemID, unitAH, econKey, now)
	local id = posInt(itemID)
	if not id then return nil, nil, nil, nil end
	local tNow = number(now) or H.now()

	-- 1. Primary 24h trend engine (identical source to Quick Look & Bloomberg)
	if ns.MarketScan and type(ns.MarketScan.GetItemTrend24h) == "function" then
		local ok, t24 = pcall(ns.MarketScan.GetItemTrend24h, id, econKey, tNow)
		if ok and type(t24) == "table" then
			local startP = nonnegative(t24.startPrice24h)
			local curP = (number(unitAH) and unitAH > 0) and unitAH or nonnegative(t24.currentPrice)
			if startP and startP > 0 and curP and curP > 0 then
				if number(t24.trendPct) ~= nil or (tonumber(t24.hoursCollected) or 0) >= 2 or curP ~= startP then
					local delta = curP - startP
					local pct = (delta / startP) * 100
					if number(pct) then
						return pct, delta, startP, t24.source or "trend24h"
					end
				end
			end
		end
	end

	-- 2. Fallback: Pricing.GetItemHeatStrip24h hourly curve when live 24h scans absent
	if number(unitAH) and unitAH > 0 and ns.Pricing and type(ns.Pricing.GetItemHeatStrip24h) == "function" then
		local ok, strip = pcall(ns.Pricing.GetItemHeatStrip24h, id, econKey)
		if ok and type(strip) == "table" and type(strip.hourly) == "table" then
			local curH = currentLocalHour()
			local earliestP, posCount = nil, 0
			for offset = 1, 24 do
				local h = (curH + offset) % 24
				local p = nonnegative(strip.hourly[h])
				if p and p > 0 then
					posCount = posCount + 1
					if not earliestP then earliestP = p end
				end
			end
			if earliestP and earliestP > 0 and (posCount >= 2 or earliestP ~= unitAH) then
				local delta = unitAH - earliestP
				local pct = (delta / earliestP) * 100
				if number(pct) then
					return pct, delta, earliestP, "heat24"
				end
			end
		end
	end

	return nil, nil, nil, nil
end

function H.buildStatsContext(context, econKey, db, now)
	if type(context) == "table" and type(context.statsContext) == "table" then
		return context.statsContext
	end
	if ns.app and type(ns.app.getRecipeStatsContext) == "function" then
		local ok, sc = pcall(ns.app.getRecipeStatsContext)
		if ok and type(sc) == "table" then
			if econKey and not sc.economy then sc.economy = econKey end
			if number(now) then sc.now = now end
			return sc
		end
	end
	db = db or H.getDB(context) or {}
	return {
		db = db,
		economy = econKey,
		now = now,
		applyAHCut = (type(context) == "table" and context.applyAHCut ~= nil)
			and (context.applyAHCut == true) or (db.applyAHCut ~= false),
		ownedCounts = (type(context) == "table" and (context.counts or context.ownedCounts))
			or (S.host and S.host.getOwnedCounts and S.host.getOwnedCounts()) or nil,
		ownedCountsByID = (type(context) == "table" and context.ownedCountsByID) or nil,
		profMap = (type(context) == "table" and context.profMap) or (ns.GetPlayerProfessions and ns.GetPlayerProfessions()) or nil,
		repState = type(context) == "table" and context.repState or nil,
		subCraftMode = (type(context) == "table" and context.subCraftMode) or db.subCraftMode or "smart",
		subCraftOverrides = (type(context) == "table" and context.subCraftOverrides) or db.subCraftOverrides,
	}
end

function H.deriveSubCraftLabel(rRow)
	local bd = type(rRow) == "table" and type(rRow.craftBreakdown) == "table" and rRow.craftBreakdown or nil
	if not bd or #bd == 0 then return "-" end
	local subCount = 0
	for i = 1, #bd do
		local b = bd[i]
		if type(b) == "table" and (b.useCraft == true or b.mode == "craft" or b.subCraft == true or b.isSubCraft == true) then
			subCount = subCount + 1
		end
	end
	if subCount > 0 then
		return subCount == 1 and "1 Sub" or (tostring(subCount) .. " Sub")
	end
	return "Buy"
end

function H.evaluateRecipeEntry(entry, recipe, context, statsCtx, econKey, now)
	local rRow
	if ns.RecipeStats and type(ns.RecipeStats.Get) == "function" then
		local ok, res = pcall(ns.RecipeStats.Get, recipe, statsCtx)
		if ok and type(res) == "table" then rRow = res end
	end
	if not rRow and type(ns.BuildRecipeRow) == "function" then
		local ok, res = pcall(ns.BuildRecipeRow, recipe, statsCtx)
		if ok and type(res) == "table" then rRow = res end
	end
	rRow = rRow or {}

	local outID = posInt(recipe.outputItemID) or posInt(rRow.outputItemID) or posInt(entry.itemID)
	local name = text(rRow.name)
	if name == "" then
		name = (ns.GetRecipeDisplayName and ns.GetRecipeDisplayName(recipe))
			or (outID and ns.ItemName and ns.ItemName(outID, recipe.name))
			or text(recipe.name)
			or ("Recipe #" .. tostring(recipe.spellID or 0))
	end
	local icon = rRow.icon or (outID and ns.ItemIcon and ns.ItemIcon(outID, ns.QUESTION_ICON)) or ns.QUESTION_ICON
	local sellable = (rRow.sellable ~= nil) and (rRow.sellable == true)
		or (outID and ns.IsItemSellable and ns.IsItemSellable(outID, recipe.sellable, recipe.isEnchant))
		or true
	local unitAH = nonnegative(rRow.unitAH)
	if unitAH == nil and sellable and outID and ns.GetItemMarketPrice then
		unitAH = nonnegative(ns.GetItemMarketPrice(outID))
	end
	local craftCost = nonnegative(rRow.craftCost)
	local profit = number(rRow.profit)
	if profit == nil and craftCost ~= nil and unitAH ~= nil and sellable then
		local applyCut = (statsCtx and statsCtx.applyAHCut ~= false)
		local netSale = applyCut and math.floor(unitAH * 0.95 + 0.5) or unitAH
		profit = netSale - craftCost
	end
	local marginPct = number(rRow.marginPct)
	if marginPct == nil and craftCost and craftCost > 0 and profit ~= nil then
		marginPct = (profit / craftCost) * 100
	end
	local listed = nonnegative(rRow.listed)
	if listed == nil and sellable and outID and ns.GetNumListed then
		listed = nonnegative(ns.GetNumListed(outID))
	end
	local ownedQty = nonnegative(rRow.ownedOutputQty)
	if ownedQty == nil then
		ownedQty = H.ownedQty(context, outID, name)
	end
	local salesPerDay = nonnegative(rRow.salesPerDay) or nonnegative(rRow.dailySold)
	local turnoverPerDay = nonnegative(rRow.turnoverPerDay)
		or ((salesPerDay and unitAH) and (salesPerDay * unitAH) or nil)
	local demand = type(rRow.demand) == "table" and rRow.demand
		or (ns.EvaluateMarketDemand and ns.EvaluateMarketDemand(listed, salesPerDay, sellable))
		or nil
	local demandSort = (demand and number(demand.demandScore)) or number(rRow.demandSort)
	local vendorSell = nonnegative(rRow.vendorSell)
		or (outID and ns.GetVendorSellPrice and nonnegative(ns.GetVendorSellPrice(outID)))
		or nil
	local known = (rRow.known == true) or (type(rRow.craftAbility) == "table" and rRow.craftAbility.known == true)
	local knownSort = known and 1 or 0
	local trendPct, trendBaseline, trendSource = H.computeTrend7d(outID, unitAH, econKey, now)
	local trend7dDelta = (number(unitAH) and number(trendBaseline)) and (unitAH - trendBaseline) or nil
	local trend24hPct, trend24hDelta, trend24hStart, trend24hSource = H.computeTrend24h(outID, unitAH, econKey, now)
	local kindLabel = H.profShort(recipe.prof)
	local profInfo = ns.PROF_BY_KEY and recipe.prof and ns.PROF_BY_KEY[recipe.prof]
	local categoryLabel = (type(profInfo) == "table" and text(profInfo.label) ~= "" and profInfo.label) or kindLabel
	local wowheadURL = text(rRow.wowheadURL) ~= "" and rRow.wowheadURL
		or (ns.GetRecipeWowheadURL and ns.GetRecipeWowheadURL(recipe))
		or (outID and ("https://www.wowhead.com/classic/item=" .. tostring(outID)) or nil)

	return {
		key = entry.key,
		kind = "recipe",
		watchEntry = entry,
		recipe = recipe,
		recipeRow = rRow,
		spellID = posInt(recipe.spellID),
		itemID = outID,
		outputItemID = outID,
		name = name,
		icon = icon,
		prof = recipe.prof,
		kindLabel = kindLabel,
		known = known,
		knownSort = knownSort,
		ownedQty = ownedQty,
		ownedOutputQty = ownedQty,
		listed = listed,
		unitAH = unitAH,
		ahSource = rRow.ahSource,
		craftCost = craftCost,
		profit = profit,
		marginPct = marginPct,
		salesPerDay = salesPerDay,
		salesScope = rRow.salesScope,
		salesWindowDays = rRow.salesWindowDays,
		turnoverPerDay = turnoverPerDay,
		demand = demand,
		demandSort = demandSort,
		trendPct = trendPct,
		trendBaseline = trendBaseline,
		trendSource = trendSource,
		trend7dDelta = trend7dDelta,
		trend24hPct = trend24hPct,
		trend24hDelta = trend24hDelta,
		trend24hStart = trend24hStart,
		trend24hSource = trend24hSource,
		subCraftLabel = H.deriveSubCraftLabel(rRow),
		vendorSell = vendorSell,
		categoryLabel = categoryLabel,
		sourceLabel = text(rRow.sourceLabel) ~= "" and rRow.sourceLabel or "-",
		requiredSkill = number(rRow.requiredSkill) or number(recipe.skill),
		wowheadURL = wowheadURL,
		sellable = sellable == true,
		numMade = rRow.numMade or recipe.numMade or 1,
		craftAbility = rRow.craftAbility,
		unlock = rRow.unlock,
		cdInfo = rRow.cdInfo,
		buyCostCopper = rRow.buyCostCopper,
		sourceCost = rRow.sourceCost,
		marketDemand = rRow.marketDemand,
		goodScore = rRow.goodScore,
		goodShort = rRow.goodShort,
		goodFull = rRow.goodFull,
		addedAt = entry.addedAt,
	}
end

function H.evaluateItemEntry(entry, context, econKey, now, catByID)
	local id = posInt(entry.itemID)
	if not id then return nil end
	local catEntry = catByID and catByID[id] or nil
	local name = (ns.ItemName and ns.ItemName(id, catEntry and catEntry.name))
		or (catEntry and catEntry.name)
		or ("Item #" .. tostring(id))
	local icon = (ns.ItemIcon and ns.ItemIcon(id, ns.QUESTION_ICON)) or ns.QUESTION_ICON
	local bop = catEntry and catEntry.bop == true or false
	local sellable = (ns.IsItemSellable and ns.IsItemSellable(id, not bop, false)) or (not bop)
	local vendorSell = (ns.GetVendorSellPrice and nonnegative(ns.GetVendorSellPrice(id)))
		or (catEntry and nonnegative(catEntry.sell))
		or nil
	local ownedQty = H.ownedQty(context, id, name)

	local unitAH, ahSource, listed, marketValue, marketDemand
	local salesPerDay, salesScope, salesWindowDays

	if sellable then
		local rawAH, rawSrc
		if ns.GetItemMarketPrice then
			rawAH, rawSrc = ns.GetItemMarketPrice(id)
			unitAH = nonnegative(rawAH)
			if unitAH then ahSource = rawSrc end
		end
		if ns.GetNumListed then
			listed = nonnegative(ns.GetNumListed(id))
		end
		if type(ns.GetItemMarketValue7d) == "function" then
			marketValue = nonnegative(ns.GetItemMarketValue7d(id))
		end
		if type(ns.QueryLocalSnapshot) == "function" then
			local _, snapRec = ns.QueryLocalSnapshot(id, econKey)
			if type(snapRec) == "table" then
				if marketValue == nil then
					marketValue = nonnegative(snapRec.marketValue) or nonnegative(snapRec.historical)
				end
				if not ns.GetNumListed and listed == nil and nonnegative(snapRec.qty) then
					listed = nonnegative(snapRec.qty)
				end
				if not ns.GetItemMarketPrice and unitAH == nil then
					unitAH = nonnegative(snapRec.minBuyout) or marketValue
				end
			end
		end
		if marketValue == nil then marketValue = unitAH end

		if ns.GetMultiSourceDemand then
			marketDemand = ns.GetMultiSourceDemand(id, econKey)
		end
		local md = type(marketDemand) == "table" and marketDemand or nil
		local snapDaily = md and nonnegative(md.snapDailySold) or nil
		local fallbackDaily = (ns.GetDailySold and nonnegative(ns.GetDailySold(id))) or nil
		if snapDaily and snapDaily > 0 then
			salesPerDay = snapDaily
			salesScope = "Blizzard"
			salesWindowDays = 7
		elseif md and nonnegative(md.localClearsPerDay) then
			salesPerDay = nonnegative(md.localClearsPerDay)
			salesScope = "Local Scan"
			salesWindowDays = 3
		elseif md and nonnegative(md.effectiveDailySold) then
			salesPerDay = nonnegative(md.effectiveDailySold)
			salesScope = text(md.demandSource) ~= "" and md.demandSource or "Market"
			salesWindowDays = 7
		elseif fallbackDaily ~= nil then
			salesPerDay = fallbackDaily
			salesScope = "Blizzard"
			salesWindowDays = 7
		end
	end

	local turnoverPerDay = (salesPerDay and unitAH) and (salesPerDay * unitAH) or nil
	local demand = ns.EvaluateMarketDemand and ns.EvaluateMarketDemand(listed, salesPerDay, sellable) or nil
	local demandSort = demand and number(demand.demandScore) or nil
	local trendPct, trendBaseline, trendSource = H.computeTrend7d(id, unitAH, econKey, now)
	local trend7dDelta = (number(unitAH) and number(trendBaseline)) and (unitAH - trendBaseline) or nil
	local trend24hPct, trend24hDelta, trend24hStart, trend24hSource = H.computeTrend24h(id, unitAH, econKey, now)

	-- Standalone items MUST keep craftCost, profit, marginPct, knownSort as nil (rendered as muted "-")
	return {
		key = entry.key,
		kind = "item",
		watchEntry = entry,
		recipe = nil,
		recipeRow = nil,
		spellID = nil,
		itemID = id,
		outputItemID = id,
		name = name,
		icon = icon,
		prof = (catEntry and catEntry.prof) or "others",
		kindLabel = "Item",
		known = nil,
		knownSort = nil,
		ownedQty = ownedQty,
		ownedOutputQty = ownedQty,
		listed = listed,
		unitAH = unitAH,
		ahSource = ahSource,
		marketValue = marketValue,
		craftCost = nil,
		profit = nil,
		marginPct = nil,
		salesPerDay = salesPerDay,
		salesScope = salesScope,
		salesWindowDays = salesWindowDays,
		turnoverPerDay = turnoverPerDay,
		demand = demand,
		demandSort = demandSort,
		marketDemand = marketDemand,
		trendPct = trendPct,
		trendBaseline = trendBaseline,
		trendSource = trendSource,
		trend7dDelta = trend7dDelta,
		trend24hPct = trend24hPct,
		trend24hDelta = trend24hDelta,
		trend24hStart = trend24hStart,
		trend24hSource = trend24hSource,
		subCraftLabel = nil,
		vendorSell = vendorSell,
		categoryLabel = (catEntry and catEntry.categoryLabel) or "Item",
		sourceLabel = (catEntry and catEntry.sourceLabel) or "Item",
		gatherNote = catEntry and catEntry.gatherNote or nil,
		requiredSkill = catEntry and number(catEntry.requiredSkill) or nil,
		usedInCount = (catEntry and catEntry.usedInCount) or 0,
		usedInRecipes = (catEntry and catEntry.usedInRecipes) or {},
		wowheadURL = (catEntry and catEntry.wowheadURL) or ("https://www.wowhead.com/classic/item=" .. tostring(id)),
		sellable = sellable == true,
		bop = bop,
		numMade = 1,
		addedAt = entry.addedAt,
	}
end

function W.EvaluateRows(context)
	context = type(context) == "table" and context or S.latest or {}
	local db = H.getDB(context) or {}
	local econKey = H.resolveEconKey(context)
	local now = number(context.now) or H.now()
	local entries = W.GetEntries()
	if #entries == 0 then
		S.rows = {}
		return S.rows
	end
	local rIdx = H.ensureRecipeIndex()
	local catByID = H.ensureCatalogByID()
	local statsCtx = H.buildStatsContext(context, econKey, db, now)
	local rows = {}
	local batchStarted = false
	if ns.RecipeStats and type(ns.RecipeStats.BeginBatch) == "function" then
		pcall(ns.RecipeStats.BeginBatch, statsCtx)
		batchStarted = true
	end
	local ok, err = pcall(function()
		for i = 1, #entries do
			local entry = entries[i]
			local recipe
			if entry.kind == "recipe" then
				if entry.spellID then
					recipe = rIdx.bySpell[posInt(entry.spellID)]
				end
				if not recipe and entry.itemID then
					recipe = rIdx.byOutput[posInt(entry.itemID)]
				end
			end
			local row
			if recipe then
				row = H.evaluateRecipeEntry(entry, recipe, context, statsCtx, econKey, now)
			else
				row = H.evaluateItemEntry(entry, context, econKey, now, catByID)
			end
			if row then
				rows[#rows + 1] = row
			end
		end
	end)
	if batchStarted and ns.RecipeStats and type(ns.RecipeStats.EndBatch) == "function" then
		pcall(ns.RecipeStats.EndBatch)
	end
	if not ok then
		if ns.ResetEval then pcall(ns.ResetEval) end
		error(err, 0)
	end
	S.rows = rows
	return rows
end

function W.FilterSort(rows, filters, sort)
	filters = type(filters) == "table" and filters or {}
	sort = type(sort) == "table" and sort or {}
	local pill = filters.filter or filters.pill or "all"
	local knownFilter = filters.knownFilter or "all"
	local demandFilter = filters.demandFilter or "all"
	local needle = text(filters.search):lower():match("^%s*(.-)%s*$")

	local result = {}
	for i = 1, #(rows or {}) do
		local r = rows[i]
		local keep = true
		if pill == "recipes" then
			keep = (r.kind == "recipe")
		elseif pill == "items" then
			keep = (r.kind == "item")
		elseif pill == "profitable" then
			keep = (number(r.profit) ~= nil and r.profit > 0)
		elseif pill == "price_drop" then
			keep = (number(r.trend24hPct) ~= nil and r.trend24hPct <= C.PRICE_DROP_THRESHOLD)
				or (number(r.trendPct) ~= nil and r.trendPct <= C.PRICE_DROP_THRESHOLD)
		end
		if keep and knownFilter ~= "all" then
			if knownFilter == "known" then
				keep = (r.known == true)
			elseif knownFilter == "unknown" then
				keep = (r.kind == "recipe" and r.known ~= true)
			end
		end
		if keep and demandFilter ~= "all" and ns.MatchesDemandFilter then
			keep = ns.MatchesDemandFilter(r.demand, demandFilter) == true
		end
		if keep and needle ~= "" then
			local hay = table.concat({
				text(r.name),
				tostring(r.itemID or ""),
				tostring(r.spellID or ""),
				text(r.kindLabel),
				text(r.categoryLabel),
				text(r.sourceLabel),
				text(r.prof),
			}, "\n"):lower()
			keep = (hay:find(needle, 1, true) ~= nil)
		end
		if keep then
			result[#result + 1] = r
		end
	end

	local key = sort.key or sort.col or "profit"
	if key == "fav" then key = "name" end
	local isNumeric = C.NUMERIC_KEYS[key] == true
	local ascending = (sort.ascending == true) or (sort.asc == true) or (sort.direction == "asc")

	local values, names, keys = {}, {}, {}
	for i = 1, #result do
		local r = result[i]
		local val = r[key]
		if isNumeric then
			local nv = number(val)
			values[r] = (nv ~= nil) and nv or false
		else
			local sv = text(val)
			values[r] = (sv ~= "" and sv ~= "-") and sv:lower() or false
		end
		names[r] = text(r.name):lower()
		keys[r] = text(r.key)
	end

	table.sort(result, function(a, b)
		local av, bv = values[a], values[b]
		if av == false and bv ~= false then return false end
		if av ~= false and bv == false then return true end
		if av ~= false and av ~= bv then
			if ascending then return av < bv else return av > bv end
		end
		local an, bn = names[a], names[b]
		if an ~= bn then return an < bn end
		return keys[a] < keys[b]
	end)

	return result
end

function W.GetRows()
	if not S.rows then
		return W.EvaluateRows(S.latest)
	end
	return S.rows
end

function W.GetFilteredRows()
	return S.filteredRows or {}
end

---------------------------------------------------------------------------------------------------
-- 3. Column Config, Formatting, Heat Popover & UI Helpers
---------------------------------------------------------------------------------------------------

function H.demandFilters()
	return (type(ns.DEMAND_FILTERS) == "table" and #ns.DEMAND_FILTERS > 0) and ns.DEMAND_FILTERS or C.DEMAND_FILTERS_FALLBACK
end

function H.findLabel(list, key, fallback)
	for _, it in ipairs(list or {}) do
		if it.key == key then return it.label end
	end
	return fallback or tostring(key or "All")
end

function H.normalizeColumnConfig(db)
	local cfg
	if type(db) == "table" then
		if type(db.watchlistColumns) ~= "table" then db.watchlistColumns = {} end
		cfg = db.watchlistColumns
	else
		cfg = S.fallbackColConfig
	end
	if type(cfg.order) ~= "table" then cfg.order = {} end
	if type(cfg.hidden) ~= "table" then cfg.hidden = {} end
	local byKey = {}
	for _, col in ipairs(C.COLUMNS) do byKey[col.key] = col end

	local hadOrder = #cfg.order > 0
	local seen, cleanOrder = {}, {}
	for _, key in ipairs(cfg.order) do
		if byKey[key] and not seen[key] then
			seen[key] = true
			cleanOrder[#cleanOrder + 1] = key
		end
	end
	if not hadOrder then
		for _, col in ipairs(C.COLUMNS) do
			if col.defaultHidden and cfg.hidden[col.key] == nil then
				cfg.hidden[col.key] = true
			end
		end
	end
	for _, col in ipairs(C.COLUMNS) do
		if not seen[col.key] then
			seen[col.key] = true
			if hadOrder and (col.key == "trend24hDelta" or col.key == "trend24hPct") then
				local inserted = false
				for i, existingKey in ipairs(cleanOrder) do
					if existingKey == "trendPct" then
						table.insert(cleanOrder, i, col.key)
						inserted = true
						break
					end
				end
				if not inserted then
					cleanOrder[#cleanOrder + 1] = col.key
				end
			else
				cleanOrder[#cleanOrder + 1] = col.key
			end
			if col.defaultHidden and cfg.hidden[col.key] == nil then
				cfg.hidden[col.key] = true
			end
		end
	end
	-- Keep fav pinned at #1 and name pinned at #2
	local pinned = { "fav", "name" }
	local finalOrder = { "fav", "name" }
	local pinnedSet = { fav = true, name = true }
	for _, k in ipairs(cleanOrder) do
		if not pinnedSet[k] then finalOrder[#finalOrder + 1] = k end
	end
	cfg.order = finalOrder
	for _, pk in ipairs(pinned) do cfg.hidden[pk] = nil end
	for k in pairs(cfg.hidden) do
		if not byKey[k] or byKey[k].locked or cfg.hidden[k] ~= true then
			cfg.hidden[k] = nil
		end
	end
	return cfg, byKey
end

function H.getActiveColumnDefs(db)
	local cfg, byKey = H.normalizeColumnConfig(db)
	local out = {}
	for _, key in ipairs(cfg.order) do
		local col = byKey[key]
		if col and (col.locked or cfg.hidden[key] ~= true) then
			out[#out + 1] = H.copyColumn(col)
		end
	end
	return out, cfg
end

function H.resolveSort()
	if S.host and type(S.host.getSort) == "function" then
		local s = S.host.getSort()
		if type(s) == "table" then
			return s.col or "profit", s.asc == true
		end
	end
	return S.localSort.col or "profit", S.localSort.asc == true
end

function H.filtersFromDB(ctx)
	local c = ctx or S.latest or {}
	local db = H.getDB(c) or {}
	local search = c.search
	if search == nil then search = db.watchlistSearch or "" end
	return {
		filter = db.watchlistFilter or "all",
		knownFilter = db.watchlistKnownFilter or "all",
		demandFilter = db.watchlistDemandFilter or "all",
		search = search,
	}
end

function H.updateFilterControls(db)
	db = db or H.getDB()
	local v = S.view
	if not v then return end
	local activeFilter = (type(db) == "table" and db.watchlistFilter) or "all"
	for key, btn in pairs(v.filterBtns or {}) do
		local active = (key == activeFilter)
		btn.active = active
		if btn.SetActive then btn:SetActive(active) end
	end
	if v.modeButton then
		H.setBtnText(v.modeButton, "View: " .. H.findLabel(C.FILTER_PILLS, activeFilter, "All"))
	end
	if v.knownButton then
		H.setBtnText(v.knownButton, H.findLabel(C.KNOWN_FILTERS, (type(db) == "table" and db.watchlistKnownFilter) or "all", "Known: All"))
	end
	if v.demandButton then
		H.setBtnText(v.demandButton, H.findLabel(H.demandFilters(), (type(db) == "table" and db.watchlistDemandFilter) or "all", "Demand: All"))
	end
end

function H.clearInsetChrome()
	local t = S.tbl
	if not t or type(t.inset) ~= "table" then return end
	if type(t.inset._mmCard) == "table" then
		for _, k in ipairs({ "fill", "border", "stroke" }) do
			local obj = t.inset._mmCard[k]
			if type(obj) == "table" then
				if type(obj.SetColor) == "function" then obj:SetColor(0, 0, 0, 0) end
				if type(obj.SetAlpha) == "function" then obj:SetAlpha(0) end
				if type(obj.SetShown) == "function" then obj:SetShown(false) end
			end
		end
	end
	if type(t.inset.GetRegions) == "function" then
		for _, r in ipairs({ t.inset:GetRegions() }) do
			if type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture" and type(r.SetAlpha) == "function" then
				r:SetAlpha(0)
			end
		end
	end
	for _, k in ipairs({ "NineSlice", "Bg", "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder" }) do
		local reg = t.inset[k]
		if type(reg) == "table" and type(reg.Hide) == "function" then reg:Hide() end
	end
end

function H.getHeatStripForRow(data)
	if not snapshotsAvailable() then return nil end
	local id = type(data) == "table" and (data.outputItemID or data.itemID) or nil
	if not id or id <= 0 then return nil end
	local P = ns.Pricing
	if not (P and type(P.GetItemHeatStrip24h) == "function") then return nil end
	local econ = H.resolveEconKey(S.latest)
	return P.GetItemHeatStrip24h(id, econ)
end

function H.closeHeatPopover(onlyForRow)
	local pop = type(S.view) == "table" and rawget(S.view, "heatPopover") or nil
	if not (type(pop) == "table" or type(pop) == "userdata") then return end
	if onlyForRow and pop.ownerCell and pop.ownerCell._ownerRow ~= onlyForRow then return end
	if shown(pop) then pop:Hide() end
	pop.ownerCell = nil
	pop.itemID = nil
end

function H.repositionHeatPopover(pop, ownerCell)
	if not pop or not ownerCell then return end
	local parent = pop:GetParent() or S.view
	local scale = parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
	local pL, pT, pR, pB = H.frameBounds(parent, scale)
	local cL, cT, cR = H.frameBounds(ownerCell, scale)
	if not (pL and cL) then return end
	local x = cR - pL + 8
	if x + HEAT_POPOVER_W > (pR - pL - 6) then
		x = cL - pL - HEAT_POPOVER_W - 8
	end
	x = math.max(6, math.min(x, (pR - pL) - HEAT_POPOVER_W - 6))
	local yTop = pT - cT - 4
	local maxTop = (pT - pB) - HEAT_POPOVER_H - 6
	yTop = math.max(6, math.min(yTop, maxTop))
	pop:ClearAllPoints()
	pop:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -yTop)
end

function H.ensureHeatPopover()
	local existing = type(S.view) == "table" and rawget(S.view, "heatPopover") or nil
	if existing then return existing end
	local Chart = ns.Analytics and ns.Analytics.Chart
	if not (Chart and type(Chart.CreateHeatmapTimingDrawer) == "function") then return nil end
	local T = ns.Theme
	local parent = S.view
	local pop = CreateFrame("Frame", nil, parent)
	pop:SetSize(HEAT_POPOVER_W, HEAT_POPOVER_H)
	if pop.SetFrameStrata then pop:SetFrameStrata("DIALOG") end
	if parent and parent.GetFrameLevel and pop.SetFrameLevel then
		pop:SetFrameLevel((parent:GetFrameLevel() or 2) + 80)
	end
	pop:EnableMouse(true)
	pop:Hide()
	pop.drawer = Chart.CreateHeatmapTimingDrawer(pop, HEAT_POPOVER_W, HEAT_POPOVER_H, {
		compact = true,
		showCurve = true,
		onClose = function() H.closeHeatPopover() end,
	})
	if pop.drawer then
		pop.drawer:ClearAllPoints()
		pop.drawer:SetPoint("TOPLEFT", pop, "TOPLEFT", 0, 0)
		pop.drawer:Show()
	end
	pop:SetScript("OnHide", function(self)
		self.ownerCell = nil
		self.itemID = nil
		if self.drawer and self.drawer.SimulateHover then self.drawer:SimulateHover(nil, nil) end
	end)
	if T and T.RegisterWidget then
		T.RegisterWidget(pop, function()
			if pop.drawer and pop.drawer.UpdateTheme then pop.drawer:UpdateTheme() end
		end)
	end
	if type(S.view) == "table" then S.view.heatPopover = pop end
	return pop
end

function H.toggleHeatPopover(ownerCell, row)
	if not snapshotsAvailable() then H.closeHeatPopover(); return end
	local itemID = type(row) == "table" and (row.outputItemID or row.itemID) or nil
	if not ownerCell or not itemID then return end
	local pop = type(S.view) == "table" and rawget(S.view, "heatPopover") or nil
	if pop and shown(pop) and pop.ownerCell == ownerCell and pop.itemID == itemID then
		H.closeHeatPopover()
		return
	end
	H.closeHeatPopover()
	pop = H.ensureHeatPopover()
	if not pop or not pop.drawer then return end
	local econ = H.resolveEconKey(S.latest)
	local heatmap = ns.Pricing and ns.Pricing.GetItemHeatmap and ns.Pricing.GetItemHeatmap(itemID, econ) or nil
	local fallbackQL = nil
	if not heatmap and ns.RecipeStats and ns.RecipeStats.BuildQuickLook then
		local ctx = {
			kind = row.kind == "recipe" and "recipe" or "item",
			econInfo = S.latest and S.latest.econInfo,
			applyAHCut = not MerchantMasterDB or MerchantMasterDB.applyAHCut ~= false,
			window = (MerchantMasterDB and MerchantMasterDB.quickLookWindow) or "7d",
		}
		fallbackQL = ns.RecipeStats.BuildQuickLook(row.recipeRow or row, ctx)
	end
	pop.ownerCell = ownerCell
	pop.itemID = itemID
	pop.drawer:Layout(HEAT_POPOVER_W, HEAT_POPOVER_H, true)
	pop.drawer:SetItem(itemID, heatmap, fallbackQL, econ)
	H.repositionHeatPopover(pop, ownerCell)
	pop:Show()
end

function H.styleHeaders()
	local t = S.tbl
	if not t then return end
	local T = ns.Theme
	local pal = getThemePalette()
	local sortCol, sortAsc = H.resolveSort()
	local tStyle = (T and T.IsCustomSkin and T.IsCustomSkin() and T.GetTableStyle and T.GetTableStyle()) or "standard"
	local styled = (tStyle == "t5_ruled" or tStyle == "t5_well" or tStyle == "t3_strips")
	local chevPath = (T and T.ASSETS and T.ASSETS.icon_chevron_down) or (APPLE_ROOT .. "icon_chevron_down")
	local activeHex = colorHex(pal and (pal.textBlue or pal.accentBlue), "0091ff")
	local mutedCol = styled and (pal and (pal.gold or pal.text)) or (pal and pal.textMuted) or C.FALLBACK.muted
	local activeCol = (pal and (pal.textBlue or pal.accentBlue)) or C.FALLBACK.blue
	if type(t.headerBar) == "table" and type(t.headerBar.GetRegions) == "function" then
		for _, reg in ipairs({ t.headerBar:GetRegions() }) do
			if type(reg) == "table" and reg.GetObjectType and reg:GetObjectType() == "Texture" and reg.SetColorTexture then
				if styled then
					reg:SetColorTexture(0, 0, 0, 0)
				elseif pal and pal.separator then
					reg:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
				end
			end
		end
	end
	for i, col in ipairs(t.columns or {}) do
		local btn = t.headerBtns and t.headerBtns[i]
		if type(btn) == "table" then
			if btn.SetHeight then btn:SetHeight(26) end
			if type(btn.sep) == "table" and type(btn.sep.Hide) == "function" then
				btn.sep:Hide()
			end
			if type(btn.bg) == "table" and btn.bg.SetColorTexture then
				btn.bg:SetColorTexture(0, 0, 0, 0)
			end
			if col.key == "fav" then
				if btn.fs then btn.fs:SetText("") end
				if not btn._starIcon and type(btn.CreateTexture) == "function" then
					local star = btn:CreateTexture(nil, "ARTWORK")
					star:SetSize(12, 12)
					star:SetPoint("CENTER", btn, "CENTER", 0, 0)
					star:SetTexture((T and T.ASSETS and T.ASSETS.icon_star) or (APPLE_ROOT .. "icon_star"))
					btn._starIcon = star
				end
				if btn._starIcon and btn._starIcon.SetVertexColor then
					btn._starIcon:SetVertexColor(1.0, 0.82, 0.18, 0.9)
				end
			elseif btn.fs then
				applyFont(btn.fs, styled and 10 or 11, styled and "semibold" or "regular")
				if btn.fs.SetJustifyH then btn.fs:SetJustifyH(col.align or "LEFT") end
				if btn.fs.SetJustifyV then btn.fs:SetJustifyV("MIDDLE") end
				local lbl = col.label or ""
				local dispLbl = styled and string.upper(lbl) or lbl
				if sortCol == col.key then
					local arrow = sortAsc
						and (" |T" .. chevPath .. ":9:9:0:0:16:16:0:16:16:0|t")
						or (" |T" .. chevPath .. ":9:9:0:0:16:16:0:16:0:16|t")
					btn.fs:SetText("|cff" .. activeHex .. dispLbl .. "|r" .. arrow)
					if btn.fs.SetTextColor then btn.fs:SetTextColor(activeCol[1], activeCol[2], activeCol[3], 1) end
				else
					btn.fs:SetText(dispLbl)
					if btn.fs.SetTextColor then btn.fs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1) end
				end
			end
		end
	end
	if t.paintTableChrome then t.paintTableChrome() end
end

function H.formatCellValues(data, pal)
	local cached = S.cellValueCache[data]
	local priceVer = (ns.GetPriceDataRevision and ns.GetPriceDataRevision())
		or (ns.GetEffectivePriceVersion and ns.GetEffectivePriceVersion())
		or ns.priceCacheEpoch
	if cached and cached.epoch == S.cellCacheEpoch and cached.pal == pal and cached.priceVer == priceVer then
		return cached.values
	end
	local isLight = pal and pal.mode == "light"
	local mutedHex = (pal and pal.hexMuted) or (isLight and "6e6e73" or "8e8e93")
	local okHex = (pal and (pal.hexSuccess or pal.hexPositive)) or (isLight and "007a2b" or "34c759")
	local badHex = (pal and (pal.hexDanger or pal.hexNegative)) or (isLight and "b8141a" or "ff453a")
	local mutedDash = "|cff" .. mutedHex .. "-|r"

	local values = {}
	values.fav = ""
	values.name = data.name or ""
	values.kindLabel = text(data.kindLabel) ~= "" and data.kindLabel or (data.kind == "recipe" and "Recipe" or "Item")
	if data.kind == "recipe" and data.knownSort ~= nil then
		if data.known == true then
			values.knownSort = "|cff" .. okHex .. "Yes|r"
		else
			values.knownSort = "|cff" .. mutedHex .. "No|r"
		end
	else
		values.knownSort = mutedDash
	end
	values.ownedQty = (number(data.ownedQty) and data.ownedQty > 0) and tostring(math.floor(data.ownedQty + 0.5)) or mutedDash
	values.listed = (number(data.listed) and data.listed > 0) and tostring(math.floor(data.listed + 0.5)) or "0"
	values.unitAH = number(data.unitAH) and money(data.unitAH) or ("|cff" .. mutedHex .. "n/a|r")

	if number(data.craftCost) then
		values.craftCost = money(data.craftCost)
	else
		values.craftCost = mutedDash
	end

	if number(data.profit) then
		local p = data.profit
		local col = (p > 0 and okHex) or (p < 0 and badHex) or mutedHex
		values.profit = "|cff" .. col .. money(p, true) .. "|r"
	else
		values.profit = mutedDash
	end

	if number(data.marginPct) then
		local m = data.marginPct
		local col = (m > 0 and okHex) or (m < 0 and badHex) or mutedHex
		values.marginPct = "|cff" .. col .. string.format("%+.0f%%", m) .. "|r"
	else
		values.marginPct = mutedDash
	end

	values.salesPerDay = number(data.salesPerDay) and formatSalesCell(data.salesPerDay, pal) or mutedDash

	local dm = type(data.demand) == "table" and data.demand or nil
	local dmBadge = dm and (dm.shortBadge or dm.badge or dm.label) or ""
	values.demandSort = dmBadge ~= "" and (themeText(dmBadge) or dmBadge) or mutedDash

	local function formatSignedPct(val)
		if not number(val) then return mutedDash end
		local col
		if val <= C.PRICE_DROP_THRESHOLD then
			col = okHex
		elseif val < -0.5 then
			col = okHex
		elseif val > 0.5 then
			col = badHex
		else
			col = mutedHex
		end
		return "|cff" .. col .. string.format("%+.0f%%", val) .. "|r"
	end

	local function formatSignedMoneyDelta(val)
		if not number(val) then return mutedDash end
		local col = (val < 0 and okHex) or (val > 0 and badHex) or mutedHex
		local plain = money(val, "neutral"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		return "|cff" .. col .. plain .. "|r"
	end

	values.trend24hDelta = formatSignedMoneyDelta(data.trend24hDelta)
	values.trend24hPct = formatSignedPct(data.trend24hPct)
	values.trendPct = formatSignedPct(data.trendPct)
	values.trend7dDelta = formatSignedMoneyDelta(data.trend7dDelta)

	values.subCraftLabel = text(data.subCraftLabel) ~= "" and data.subCraftLabel or mutedDash
	values.vendorSell = number(data.vendorSell) and money(data.vendorSell) or ("|cff" .. mutedHex .. "n/a|r")
	values.turnoverPerDay = number(data.turnoverPerDay) and moneyCompact(data.turnoverPerDay) or mutedDash
	values.categoryLabel = text(data.categoryLabel) ~= "" and data.categoryLabel or mutedDash
	values.sourceLabel = text(data.sourceLabel) ~= "" and data.sourceLabel or mutedDash
	values.requiredSkill = number(data.requiredSkill) and tostring(data.requiredSkill) or mutedDash
	values.wowheadURL = text(data.wowheadURL) ~= "" and "Link" or mutedDash

	S.cellValueCache[data] = {
		epoch = S.cellCacheEpoch,
		pal = pal,
		priceVer = priceVer,
		values = values,
	}
	return values
end

---------------------------------------------------------------------------------------------------
-- Shopping Qty Helpers (Recipes & Standalone Items)
---------------------------------------------------------------------------------------------------

function H.getShoppingQty(data)
	if not (data and S.host) then return 0 end
	if data.kind == "recipe" and data.recipe and type(S.host.getRecipeShoppingQty) == "function" then
		return S.host.getRecipeShoppingQty(data.recipeRow or data) or 0
	end
	if type(S.host.getItemShoppingQty) == "function" then
		return S.host.getItemShoppingQty(data) or 0
	end
	return 0
end

function H.adjustShoppingQty(data, delta)
	if not (data and S.host) then return 0 end
	local after = 0
	if data.kind == "recipe" and data.recipe and type(S.host.adjustRecipeShoppingQty) == "function" then
		after = S.host.adjustRecipeShoppingQty(data.recipeRow or data, delta) or 0
	elseif type(S.host.adjustItemShoppingQty) == "function" then
		after = S.host.adjustItemShoppingQty(data, delta) or 0
	end
	W.RepaintShoppingQty()
	return after
end

function H.styleRowStepper(stepper, qty, pal)
	if not stepper then return end
	local T = ns.Theme
	local dark = not (T and T.GetMode and T.GetMode() == "light")
	local bgCol = dark and { 0.16, 0.17, 0.19 } or { 0.92, 0.93, 0.95 }
	local stCol = dark and { 1, 1, 1, 0.22 } or { 0, 0, 0, 0.18 }
	local textCol = (pal and pal.text) or C.FALLBACK.text
	local activeCol = (pal and pal.accentGreen) or C.FALLBACK.green
	local qc = (qty and qty > 0) and activeCol or ((pal and pal.textSecondary) or C.FALLBACK.secondary)
	if stepper.bg then
		if stepper.bg.SetColor then stepper.bg:SetColor(bgCol[1], bgCol[2], bgCol[3], 1)
		elseif stepper.bg.SetColorTexture then stepper.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], 1) end
	end
	if stepper.stroke and stepper.stroke.SetColor then
		stepper.stroke:SetColor(stCol[1], stCol[2], stCol[3], stCol[4] or 0.22)
	end
	if stepper.minusBtn and stepper.minusBtn.fs then
		stepper.minusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
	end
	if stepper.plusBtn and stepper.plusBtn.fs then
		stepper.plusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
	end
	if stepper.qtyFs then
		stepper.qtyFs:SetText(tostring(qty or 0))
		stepper.qtyFs:SetTextColor(qc[1], qc[2], qc[3], qc[4] or 1)
	end
end

function H.ensureRowStepper(r)
	if r.shiftStepper then return r.shiftStepper end
	local T = ns.Theme
	local stepper = CreateFrame("Frame", nil, r)
	stepper:SetSize(74, 20)
	stepper:SetPoint("RIGHT", r, "RIGHT", -2, 0)
	if r.GetFrameLevel and stepper.SetFrameLevel then
		stepper:SetFrameLevel((r:GetFrameLevel() or 1) + 4)
	end
	if stepper.EnableMouse then stepper:EnableMouse(true) end
	if T and T.RoundRect and T.ASSETS and T.ASSETS.pill_fill then
		stepper.bg = T.RoundRect(stepper, stepper, "BACKGROUND", 0, 10, 0, 0.204, 0.204, 0.220, 1, T.ASSETS.pill_fill)
		stepper.stroke = T.RoundRect(stepper, stepper, "BORDER", 1, 10, 0, 1, 1, 1, 0.22, T.ASSETS.pill_stroke)
	else
		stepper.bg = stepper:CreateTexture(nil, "BACKGROUND")
		stepper.bg:SetAllPoints()
		stepper.bg:SetColorTexture(0.204, 0.204, 0.220, 1)
	end
	local minusBtn = CreateFrame("Button", nil, stepper)
	minusBtn:SetSize(22, 20)
	minusBtn:SetPoint("LEFT", stepper, "LEFT", 0, 0)
	minusBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minusBtn.fs = minusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	minusBtn.fs:SetAllPoints()
	minusBtn.fs:SetJustifyH("CENTER")
	minusBtn.fs:SetText("-")
	applyFont(minusBtn.fs, 12, "semibold")
	minusBtn:SetScript("OnClick", function(_, button)
		if r.data then
			local cur = H.getShoppingQty(r.data)
			local delta = (button == "RightButton") and -math.max(1, cur) or -1
			H.adjustShoppingQty(r.data, delta)
		end
	end)
	local plusBtn = CreateFrame("Button", nil, stepper)
	plusBtn:SetSize(22, 20)
	plusBtn:SetPoint("RIGHT", stepper, "RIGHT", 0, 0)
	plusBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	plusBtn.fs = plusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	plusBtn.fs:SetAllPoints()
	plusBtn.fs:SetJustifyH("CENTER")
	plusBtn.fs:SetText("+")
	applyFont(plusBtn.fs, 12, "semibold")
	plusBtn:SetScript("OnClick", function(_, button)
		if r.data then
			local delta = (button == "RightButton") and 5 or 1
			H.adjustShoppingQty(r.data, delta)
		end
	end)
	local qtyFs = stepper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	qtyFs:SetPoint("LEFT", minusBtn, "RIGHT", 0, 0)
	qtyFs:SetPoint("RIGHT", plusBtn, "LEFT", 0, 0)
	qtyFs:SetJustifyH("CENTER")
	applyFont(qtyFs, 11, "semibold")
	stepper.minusBtn, stepper.plusBtn, stepper.qtyFs = minusBtn, plusBtn, qtyFs
	stepper:Hide()
	r.shiftStepper = stepper
	return stepper
end

function H.paintRowShiftUI(r, pal)
	if not (r and r.data) then return end
	local hovered = isMouseOverFrame(r) or (r.shiftStepper and isMouseOverFrame(r.shiftStepper))
	local qty = H.getShoppingQty(r.data)
	local showStep = (S.shiftActive == true) or (qty > 0 and hovered)
	local activeCols = S.tbl and S.tbl.columns
	local colX = S.tbl and S.tbl.colX
	local cellsByKey = r.cellGroup and r.cellGroup.cellsByKey
	if showStep then
		local stepper = H.ensureRowStepper(r)
		H.styleRowStepper(stepper, qty, pal)
		stepper:Show()
		local n = activeCols and #activeCols or 0
		if n > 0 and cellsByKey and colX then
			r._shiftHidden = true
			local lastCol = activeCols[n]
			local lastX = colX[n]
			local tblRight = (lastCol and lastX) and (lastX + (lastCol.width or 0)) or 0
			local rawRowW = (r.GetWidth and r:GetWidth()) or 0
			local rowW = (rawRowW >= math.max(200, tblRight * 0.5)) and rawRowW or tblRight
			if rowW > 80 then
				local cutoff = rowW - 80
				for i = 1, n do
					local col = activeCols[i]
					local c = col and cellsByKey[col.key]
					local cx = colX[i] or 0
					local cw = (col and col.width) or 0
					local overlap = (cx + cw > cutoff)
					if c and c.SetShown then c:SetShown(not overlap) end
				end
			end
		end
	else
		if r.shiftStepper then r.shiftStepper:Hide() end
		if r._shiftHidden then
			r._shiftHidden = false
			if activeCols and cellsByKey then
				for i = 1, #activeCols do
					local c = cellsByKey[activeCols[i].key]
					if c and c.Show then c:Show() end
				end
			end
		end
	end
end

function H.paintRowSep(r)
	if not r then return end
	local pal = getThemePalette()
	if r.sep then
		if not r._sepAnchored and type(r.sep.ClearAllPoints) == "function" and type(r.sep.SetPoint) == "function" then
			r._sepAnchored = true
			r.sep:ClearAllPoints()
			r.sep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 16, 0)
			r.sep:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -16, 0)
			if r.sep.SetHeight then r.sep:SetHeight(1) end
		end
		if type(r.sep.SetColorTexture) == "function" then
			local sep = pal and pal.separator
			if sep then
				r.sep:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.45) * 0.45)
			else
				r.sep:SetColorTexture(0.5, 0.5, 0.54, 0.18)
			end
		end
	end
	if r.hl and type(r.hl.SetColorTexture) == "function" and pal and pal.glassHover then
		local hc = pal.glassHover
		r.hl:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.06)
	end
end

function H.paintRowSelection(r)
	if not r then return end
	local sel = r.data and S.selectedKey ~= nil and r.data.key == S.selectedKey
	if r.selectTex then
		if sel then
			local pal = getThemePalette()
			local c = (pal and pal.rowSelect) or { 0.25, 0.55, 1, 0.18 }
			r.selectTex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.18)
			r.selectTex:Show()
		else
			r.selectTex:Hide()
		end
	end
	H.paintRowSep(r)
end

function H.showRowTooltip(owner, data)
	if not (GameTooltip and data) then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local title = data.name or ("Item #" .. tostring(data.itemID or 0))
	GameTooltip:SetText(title, 1, 0.85, 0.25)
	GameTooltip:AddDoubleLine("Type", text(data.kindLabel) ~= "" and data.kindLabel or "Item", 0.72, 0.72, 0.76, 1, 1, 1)
	if data.kind == "recipe" then
		GameTooltip:AddDoubleLine("Known", data.known and "Yes" or "No", 0.72, 0.72, 0.76, data.known and 0.25 or 0.75, data.known and 0.9 or 0.75, data.known and 0.35 or 0.78)
	end
	GameTooltip:AddDoubleLine("AH Price", number(data.unitAH) and money(data.unitAH) or "n/a", 0.72, 0.72, 0.76, 1, 1, 1)
	if number(data.craftCost) then
		GameTooltip:AddDoubleLine("Craft Cost", money(data.craftCost), 0.72, 0.72, 0.76, 1, 1, 1)
	end
	if number(data.profit) then
		GameTooltip:AddDoubleLine("Craft Profit", money(data.profit, true), 0.72, 0.72, 0.76, data.profit >= 0 and 0.25 or 1, data.profit >= 0 and 0.9 or 0.35, 0.35)
	end
	if number(data.marginPct) then
		GameTooltip:AddDoubleLine("Margin", string.format("%+.1f%%", data.marginPct), 0.72, 0.72, 0.76, data.marginPct >= 0 and 0.25 or 1, data.marginPct >= 0 and 0.9 or 0.35, 0.35)
	end
	if number(data.trend24hPct) then
		local t24 = data.trend24hPct
		local d24 = number(data.trend24hDelta)
		local s24 = number(data.trend24hStart)
		local curP = number(data.unitAH)
		local detail = ""
		local function plainMoney(v, sgn)
			return (money(v, sgn):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		end
		if d24 ~= nil and s24 and curP then
			detail = string.format(" (%s: %s -> %s)", plainMoney(d24, "neutral"), plainMoney(s24), plainMoney(curP))
		elseif d24 ~= nil then
			detail = string.format(" (%s)", plainMoney(d24, "neutral"))
		end
		GameTooltip:AddDoubleLine("24h Trend", string.format("%+.1f%%%s", t24, detail), 0.72, 0.72, 0.76, t24 <= 0 and 0.25 or 1, t24 <= 0 and 0.9 or 0.35, 0.35)
	end
	if number(data.trendPct) then
		local tp = data.trendPct
		local d7 = number(data.trend7dDelta)
		local base = number(data.trendBaseline)
		local function plainMoney(v, sgn)
			return (money(v, sgn):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		end
		local extra = ""
		if d7 ~= nil and base then
			extra = string.format(" (%s, 7d avg %s)", plainMoney(d7, "neutral"), plainMoney(base))
		elseif d7 ~= nil then
			extra = string.format(" (%s)", plainMoney(d7, "neutral"))
		elseif base then
			extra = string.format(" (7d avg %s)", plainMoney(base))
		end
		GameTooltip:AddDoubleLine("7d Trend", string.format("%+.1f%%%s", tp, extra), 0.72, 0.72, 0.76, tp <= 0 and 0.25 or 1, tp <= 0 and 0.9 or 0.35, 0.35)
	end
	GameTooltip:AddDoubleLine("Listed / Owned", string.format("%d / %d", math.floor(tonumber(data.listed) or 0), math.floor(tonumber(data.ownedQty) or 0)), 0.72, 0.72, 0.76, 1, 1, 1)
	GameTooltip:AddLine(" ", 1, 1, 1)
	GameTooltip:AddLine("Left-Click: Quick Look | Right-Click: Deep Analysis", 0.60, 0.86, 1.00, true)
	GameTooltip:AddLine("Shift-Click: Add/Remove Shopping List | Star: Remove from Watchlist", 0.40, 1.00, 0.60, true)
	H.liftAndShowTooltip()
end

function H.handleRowClick(row, button, colKey, ownerCell)
	if not (row and row.data) then return end
	local data = row.data
	if colKey == "fav" and button == "LeftButton" then
		W.Toggle(data)
		return
	end
	if shiftKeyDown() and button == "LeftButton" then
		H.adjustShoppingQty(data, 1)
		return
	end
	if shiftKeyDown() and button == "RightButton" then
		local cur = H.getShoppingQty(data)
		if cur > 0 then H.adjustShoppingQty(data, -1) end
		return
	end
	if colKey == "demandSort" and button == "LeftButton" and snapshotsAvailable() and H.getHeatStripForRow(data) then
		H.toggleHeatPopover(ownerCell, data)
		return
	end
	if colKey == "wowheadURL" and button == "LeftButton" then
		if S.host and S.host.openWowheadPopup and text(data.wowheadURL) ~= "" then
			S.host.openWowheadPopup({
				wowheadURL = data.wowheadURL,
				wowheadLabel = data.name,
				wowheadKind = data.kind == "recipe" and "recipe" or "item",
				recipeName = data.name,
			}, data.name, data.icon)
		end
		return
	end
	if button == "RightButton" then
		local openDA = (S.host and S.host.openDeepAnalysis) or (ns.app and ns.app.openDeepAnalysis)
		if type(openDA) == "function" then
			local targetKind = data.kind == "recipe" and "recipe" or "item"
			openDA({
				kind = targetKind,
				row = targetKind == "recipe" and (data.recipeRow or data) or data,
				recipe = data.recipe,
				itemID = data.itemID,
				name = data.name,
				icon = data.icon,
			}, { tab = "watchlist" })
		end
		return
	end
	if button == "LeftButton" then
		S.selectedKey = data.key
		if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
			S.tbl.scrollBox:ForEachFrame(H.paintRowSelection)
		end
		local openQL = (S.host and S.host.openQuickLook) or (ns.app and ns.app.openQuickLook)
		if type(openQL) == "function" then
			local targetKind = data.kind == "recipe" and "recipe" or "item"
			openQL(targetKind, targetKind == "recipe" and (data.recipeRow or data) or data, { owner = row, toggle = true })
		end
	end
end

function H.prepareCells()
	local t = S.tbl
	local parent = (t and t.scrollBox) or S.view
	local T = ns.Theme
	local Chart = ns.Analytics and ns.Analytics.Chart
	local rowH = (t and t.rowHeight) or (S.host and S.host.rowHeight) or 22
	local cells, byKey = {}, {}
	for i, col in ipairs(C.COLUMNS) do
		local cell = CreateFrame("Button", nil, parent)
		cell:SetHeight(rowH)
		cell:EnableMouse(true)
		cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		if col.isStar then
			local star = cell:CreateTexture(nil, "ARTWORK")
			star:SetSize(13, 13)
			star:SetPoint("CENTER", cell, "CENTER", 0, 0)
			star:SetTexture((T and T.ASSETS and T.ASSETS.icon_star) or (APPLE_ROOT .. "icon_star"))
			cell.starIcon = star
		else
			if col.icon then
				local icon = cell:CreateTexture(nil, "ARTWORK")
				icon:SetSize(16, 16)
				icon:SetPoint("LEFT", 2, 0)
				cell.icon = icon
			end
			local fs = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", col.icon and 22 or 0, 0)
			fs:SetPoint("RIGHT", 0, 0)
			fs:SetJustifyH(col.align or "LEFT")
			if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
			fs:SetWordWrap(false)
			applyFont(fs, 11, col.key == "name" and "semibold" or "regular")
			cell.fs = fs
		end
		if col.heatStrip and Chart and type(Chart.CreateHeatStrip24h) == "function" then
			local hs = Chart.CreateHeatStrip24h(cell, { height = 4, showNowTick = true })
			if hs then
				local frameObj = hs.frame or hs
				if frameObj and frameObj.SetPoint then
					frameObj:ClearAllPoints()
					frameObj:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 2, 2)
					frameObj:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
				end
				cell.heatStrip = hs
				cell._heatStripBound = false
			end
		end
		cell._colKey = col.key
		cell:SetScript("OnClick", function(self, button)
			H.handleRowClick(self._ownerRow, button, self._colKey, self)
		end)
		cell:SetScript("OnEnter", function(self)
			local row = self._ownerRow
			if not (row and row.data) then return end
			if self._colKey == "fav" then
				if GameTooltip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					local isFav = W.IsFavorite(row.data)
					GameTooltip:SetText(isFav and "Remove from Watchlist" or "Add to Watchlist", 1, 0.85, 0.25)
					H.liftAndShowTooltip()
				end
			else
				H.showRowTooltip(row, row.data)
			end
			H.paintRowShiftUI(row, getThemePalette())
		end)
		cell:SetScript("OnLeave", function(self)
			if GameTooltip then GameTooltip:Hide() end
			local row = self._ownerRow
			if row and row.data then H.paintRowShiftUI(row, getThemePalette()) end
		end)
		cells[i] = cell
		byKey[col.key] = cell
	end
	return { cells = cells, cellsByKey = byKey }
end

function H.bindRow(r, data)
	if not r then return end
	if not r.cellGroup then
		if S.host and S.host.applyRowHighlight then S.host.applyRowHighlight(r) end
		if r.sep and type(r.sep.ClearAllPoints) == "function" and type(r.sep.SetPoint) == "function" then
			r._sepAnchored = true
			r.sep:ClearAllPoints()
			r.sep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 16, 0)
			r.sep:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -16, 0)
			if r.sep.SetHeight then r.sep:SetHeight(1) end
		end
		if ns.Theme and ns.Theme.RegisterWidget then
			ns.Theme.RegisterWidget(r, function() H.paintRowSep(r) end)
		end
		H.paintRowSep(r)
		if #S.prepared == 0 then
			S.prepared[#S.prepared + 1] = H.prepareCells()
		end
		r.cellGroup = table.remove(S.prepared)
		r.cells = r.cellGroup.cells
	end
	if r.stripe and r.stripe.SetColorTexture then
		r.stripe:SetColorTexture(0, 0, 0, 0)
	end
	if not r.selectTex then
		r.selectTex = r:CreateTexture(nil, "BACKGROUND", nil, 2)
		r.selectTex:SetAllPoints()
		r.selectTex:Hide()
	end
	if r.data ~= data then
		H.closeHeatPopover(r)
	end
	r.data = data
	local t = S.tbl
	local pal = getThemePalette()
	local rowH = (t and t.rowHeight) or (S.host and S.host.rowHeight) or 22
	local active = {}
	local activeCells = r._activeCells
	if not activeCells then activeCells = {}; r._activeCells = activeCells end
	for k in pairs(activeCells) do activeCells[k] = nil end
	local vals = data and H.formatCellValues(data, pal) or nil
	if t then
		for i, col in ipairs(t.columns or {}) do
			local cell = r.cellGroup.cellsByKey[col.key]
			if cell then
				active[cell] = true
				activeCells[i] = cell
				cell:SetParent(r)
				cell._ownerRow = r
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", r, "LEFT", t.colX[i] or 4, 0)
				cell:SetSize(col.width, rowH)
				cell:Show()
				if data and vals then
					if cell.starIcon and cell.starIcon.SetVertexColor then
						local fav = W.IsFavorite(data)
						if fav then
							cell.starIcon:SetVertexColor(1.0, 0.82, 0.18, 1.0)
						else
							local mc = (pal and pal.textMuted) or C.FALLBACK.muted
							cell.starIcon:SetVertexColor(mc[1], mc[2], mc[3], mc[4] or 1.0)
						end
					end
					if cell.fs then
						if cell.fs.SetJustifyV then cell.fs:SetJustifyV("MIDDLE") end
						if col.key == "kindLabel" or col.key == "categoryLabel" or col.key == "sourceLabel" or col.key == "subCraftLabel" then
							local c = (pal and pal.textSecondary) or C.FALLBACK.secondary
							cell.fs:SetTextColor(c[1], c[2], c[3], 1)
						else
							local c = (pal and pal.text) or C.FALLBACK.text
							cell.fs:SetTextColor(c[1], c[2], c[3], 1)
						end
						cell.fs:SetText(vals[col.key] or "-")
					end
					if cell.icon then
						cell.icon:SetTexture(data.icon or ns.QUESTION_ICON)
						cell.icon:Show()
					end
					if cell.heatStrip then
						local strip = H.getHeatStripForRow(data)
						if strip then
							cell.heatStrip:Bind(strip, pal, currentLocalHour())
							cell.heatStrip:Layout(math.max(24, (col.width or 80) - 4))
							cell._heatStripBound = true
						elseif cell._heatStripBound then
							cell.heatStrip:Clear()
							cell._heatStripBound = false
						end
					end
				end
			end
		end
	end
	r.cells = activeCells
	for _, cell in ipairs(r.cellGroup.cells) do
		if not active[cell] then
			cell._ownerRow = nil
			cell:Hide()
			if cell.icon then cell.icon:Hide() end
			if cell._heatStripBound and cell.heatStrip then
				cell.heatStrip:Clear()
				cell._heatStripBound = false
			end
		end
	end
	H.paintRowSelection(r)
	H.paintRowShiftUI(r, pal)
	if not r._wlHooked then
		r._wlHooked = true
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r:SetScript("OnClick", function(self, button)
			H.handleRowClick(self, button, nil, nil)
		end)
		r:SetScript("OnEnter", function(self)
			if self.data then
				H.showRowTooltip(self, self.data)
				H.paintRowShiftUI(self, getThemePalette())
			end
		end)
		r:SetScript("OnLeave", function(self)
			if GameTooltip then GameTooltip:Hide() end
			H.paintRowShiftUI(self, getThemePalette())
		end)
	end
end

function H.applyColumnConfig(db)
	local activeCols, cfg = H.getActiveColumnDefs(db or H.getDB())
	S.appliedColSig = fingerprint(cfg)
	local t = S.tbl
	if not t then return end
	t.columns = t.columns or {}
	for k in pairs(t.columns) do t.columns[k] = nil end
	t.baseWidths = t.baseWidths or {}
	for k in pairs(t.baseWidths) do t.baseWidths[k] = nil end
	t.growWeights = t.growWeights or {}
	for k in pairs(t.growWeights) do t.growWeights[k] = nil end
	t.colX = t.colX or {}
	for k in pairs(t.colX) do t.colX[k] = nil end
	t.headerBtns = t.headerBtns or {}
	for k in pairs(t.headerBtns) do t.headerBtns[k] = nil end
	local activeBtns = {}
	local x = 4
	for i, col in ipairs(activeCols) do
		t.columns[i] = col
		t.baseWidths[i] = col.width
		t.growWeights[i] = col.grow
		t.colX[i] = x
		x = x + col.width + 5
		local btn = t.headerBtnsByKey and t.headerBtnsByKey[col.key]
		t.headerBtns[i] = btn
		if btn then
			activeBtns[btn] = true
			if btn.Show then btn:Show() end
		end
	end
	for _, btn in pairs(t.headerBtnsByKey or {}) do
		if not activeBtns[btn] and btn.Hide then btn:Hide() end
	end
	S.colEpoch = S.colEpoch + 1
	S.cellCacheEpoch = S.cellCacheEpoch + 1
	local w = S.view and S.view.GetWidth and S.view:GetWidth() or 0
	if w > 0 then
		W.Layout(w, S.view:GetHeight(), true)
	else
		for i, col in ipairs(t.columns) do
			local btn = t.headerBtns[i]
			if btn and t.headerBar then
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", t.headerBar, "LEFT", t.colX[i], 1)
				btn:SetWidth(col.width)
			end
		end
		H.styleHeaders()
	end
	if t.scrollBox and t.scrollBox.ForEachFrame then
		t.scrollBox:ForEachFrame(function(r)
			if r.data then H.bindRow(r, r.data) end
		end)
	end
end

function H.buildColumnPopover(v, T)
	local pop = CreateFrame("Frame", nil, v)
	local rowCount = #C.COLUMNS
	pop:SetSize(288, math.max(300, 48 + rowCount * 20))
	pop:SetPoint("TOPRIGHT", v.colSettingsBtn, "BOTTOMRIGHT", 0, -6)
	if pop.SetFrameStrata then pop:SetFrameStrata("DIALOG") end
	if v.GetFrameLevel and pop.SetFrameLevel then pop:SetFrameLevel((v:GetFrameLevel() or 2) + 80) end
	pop:EnableMouse(true)
	pop:Hide()
	if T and T.NineApple then
		pop.surface = T.NineApple(pop, "glass_r16", T.COLORS and T.COLORS.toolbarBg, T.COLORS and T.COLORS.borderStrong, { noSpecular = true })
	else
		pop.bg = pop:CreateTexture(nil, "BACKGROUND")
		pop.bg:SetAllPoints()
		pop.bg:SetColorTexture(0.11, 0.12, 0.14, 0.97)
	end
	pop.titleFs = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pop.titleFs:SetPoint("TOPLEFT", 12, -12)
	pop.titleFs:SetText("Watchlist Columns")
	applyFont(pop.titleFs, 12, "semibold")
	pop.closeBtn = T and T.CreatePlateButton and T.CreatePlateButton(pop, "", 22, 22, { variant = "ghost", pill = true, icon = T.ASSETS and T.ASSETS.icon_close, iconSize = 11 })
		or CreateFrame("Button", nil, pop)
	pop.closeBtn:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -10, -8)
	pop.closeBtn:SetScript("OnClick", function() W.ToggleColumnSettings(false) end)
	pop.resetBtn = T and T.CreatePlateButton and T.CreatePlateButton(pop, "Reset", 50, 22, { variant = "secondary", pill = true, fontSize = 11 })
		or CreateFrame("Button", nil, pop)
	pop.resetBtn:SetPoint("RIGHT", pop.closeBtn, "LEFT", -6, 0)
	pop.resetBtn:SetScript("OnClick", function() W.ResetColumns() end)

	pop.rows = {}
	for idx = 1, rowCount do
		local r = CreateFrame("Frame", nil, pop)
		r:SetSize(264, 19)
		r:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -38 - (idx - 1) * 20)
		local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
		cb:SetSize(18, 18)
		cb:SetPoint("LEFT", r, "LEFT", 0, 0)
		cb:SetScript("OnClick", function(self)
			if r.colKey then
				W.SetColumnVisible(r.colKey, self:GetChecked() == true)
			end
		end)
		local lbl = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
		lbl:SetPoint("RIGHT", r, "RIGHT", -48, 0)
		lbl:SetJustifyH("LEFT")
		lbl:SetWordWrap(false)
		applyFont(lbl, 11, "regular")
		local up = CreateFrame("Button", nil, r)
		up:SetSize(18, 18)
		up:SetPoint("RIGHT", r, "RIGHT", -22, 0)
		up.fs = up:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		up.fs:SetAllPoints()
		up.fs:SetJustifyH("CENTER")
		up.fs:SetText("^")
		applyFont(up.fs, 11, "semibold")
		up:SetScript("OnClick", function()
			if r.colKey then W.MoveColumn(r.colKey, -1) end
		end)
		local dn = CreateFrame("Button", nil, r)
		dn:SetSize(18, 18)
		dn:SetPoint("RIGHT", r, "RIGHT", -2, 0)
		dn.fs = dn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		dn.fs:SetAllPoints()
		dn.fs:SetJustifyH("CENTER")
		dn.fs:SetText("v")
		applyFont(dn.fs, 11, "semibold")
		dn:SetScript("OnClick", function()
			if r.colKey then W.MoveColumn(r.colKey, 1) end
		end)
		r.cb, r.lbl, r.up, r.dn = cb, lbl, up, dn
		pop.rows[idx] = r
	end
	v.colSettingsPopover = pop
end

function H.refreshColumnPopover()
	local pop = S.view and S.view.colSettingsPopover
	if not pop then return end
	local cfg, byKey = H.normalizeColumnConfig(H.getDB())
	local pal = getThemePalette()
	local tc = (pal and pal.text) or C.FALLBACK.text
	local mc = (pal and pal.textMuted) or C.FALLBACK.muted
	for idx, r in ipairs(pop.rows or {}) do
		local key = cfg.order[idx]
		local col = key and byKey[key]
		if col then
			r.colKey = key
			r:Show()
			r.lbl:SetText(col.key == "fav" and "Favorite Star" or col.label)
			local vis = col.locked or cfg.hidden[key] ~= true
			r.cb:SetChecked(vis)
			if r.cb.Enable and r.cb.Disable then
				if col.locked then r.cb:Disable() else r.cb:Enable() end
			end
			r.lbl:SetTextColor(vis and tc[1] or mc[1], vis and tc[2] or mc[2], vis and tc[3] or mc[3], 1)
			if r.up.SetEnabled then r.up:SetEnabled(not col.locked and idx > 3) end
			if r.dn.SetEnabled then r.dn:SetEnabled(not col.locked and idx < #cfg.order) end
		else
			r.colKey = nil
			r:Hide()
		end
	end
end

function H.themeColumnSettingsPopover()
	local pop = S.view and S.view.colSettingsPopover
	if not pop then return end
	local pal = getThemePalette()
	if pop.surface and pop.surface.UpdateTheme and pal then
		pop.surface:UpdateTheme(pal.toolbarBg, pal.borderStrong)
	end
	if pop.titleFs and pal and pal.text then
		pop.titleFs:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
	end
	H.refreshColumnPopover()
end

function H.resetFilters()
	if S.host and type(S.host.resetWatchlistFilters) == "function" then
		S.host.resetWatchlistFilters()
		return
	end
	local db = H.getDB()
	if type(db) == "table" then
		db.watchlistFilter = "all"
		db.watchlistKnownFilter = "all"
		db.watchlistDemandFilter = "all"
		db.watchlistSearch = ""
	end
	if S.latest then S.latest.search = "" end
	if ns.app and ns.app.resetSearchBox and ns.app.ui and ns.app.ui.searchBox then
		ns.app.resetSearchBox(ns.app.ui.searchBox)
	end
	H.updateFilterControls(db)
	W.Refresh(S.latest)
end

function H.updateShiftHeader()
	local v = S.view
	if not v then return end
	if v.shiftBadge and v.shiftBadge.SetShown then
		v.shiftBadge:SetShown(S.shiftActive == true)
	end
	if v.summary and v.summary.ClearAllPoints and v.summary.SetPoint then
		v.summary:ClearAllPoints()
		if v.summaryLeftAnchor then
			v.summary:SetPoint("LEFT", v.summaryLeftAnchor, "RIGHT", 8, 0)
		end
		if S.shiftActive and v.shiftBadge then
			v.summary:SetPoint("RIGHT", v.shiftBadge, "LEFT", -8, 0)
		elseif v.filtersButton then
			v.summary:SetPoint("RIGHT", v.filtersButton, "LEFT", -8, 0)
		elseif v.resetButton then
			v.summary:SetPoint("RIGHT", v.resetButton, "LEFT", -8, 0)
		end
	end
end

function H.applyTheme()
	local pal = getThemePalette()
	local v = S.view
	if not v then return end
	if v._mmCard and v._mmCard.UpdateTheme then v._mmCard:UpdateTheme() end
	if v.barSep and v.barSep.SetColorTexture then
		if pal and pal.separator then
			v.barSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.45) * 0.65)
		else
			v.barSep:SetColorTexture(0.5, 0.5, 0.54, 0.25)
		end
	end
	if v.summary and pal and pal.textSecondary then
		v.summary:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
	end
	if v.emptyText and pal and pal.textMuted then
		v.emptyText:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
	end
	H.clearInsetChrome()
	H.styleHeaders()
	H.themeColumnSettingsPopover()
	W.RepaintVisible()
	if S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame then
		S.tbl.scrollBox:ForEachFrame(H.paintRowSep)
	end
end

function H.buildHeader(v, T)
	local bar = CreateFrame("Frame", nil, v)
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetHeight(40)
	v.headerBar = bar

	local barSep = bar:CreateTexture(nil, "BORDER")
	barSep:SetPoint("BOTTOMLEFT", 0, 0)
	barSep:SetPoint("BOTTOMRIGHT", 0, 0)
	barSep:SetHeight(1)
	v.barSep = barSep

	local function attachHeaderTooltip(btn, title, body, anchor)
		btn:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, anchor or "ANCHOR_BOTTOMLEFT")
			GameTooltip:AddLine(title, 1, 0.85, 0.25)
			GameTooltip:AddLine(body, 1, 1, 1, true)
			H.liftAndShowTooltip()
		end)
		btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end

	v.filterBtns = {}
	v.filterOrder = {}
	local prevPill
	for idx, spec in ipairs(C.FILTER_PILLS) do
		local pw = math.max(36, #spec.label * 6 + 16)
		local btn = T and T.CreatePlateButton and T.CreatePlateButton(bar, spec.label, pw, 22, { variant = "secondary", pill = true, fontSize = 10, weight = "semibold" })
			or CreateFrame("Button", nil, bar)
		btn:SetSize(pw, 22)
		local pfs = (btn.GetFontString and btn:GetFontString()) or btn.fs
		if pfs and pfs.SetJustifyV then pfs:SetJustifyV("MIDDLE") end
		if idx == 1 then
			btn:SetPoint("LEFT", bar, "LEFT", 8, 0)
		else
			btn:SetPoint("LEFT", prevPill, "RIGHT", 4, 0)
		end
		btn.filterKey = spec.key
		btn:SetScript("OnClick", function()
			local db = H.getDB()
			if type(db) == "table" then db.watchlistFilter = spec.key end
			H.updateFilterControls(db)
			W.Refresh(S.latest)
		end)
		attachHeaderTooltip(btn, spec.label, spec.tip, "ANCHOR_BOTTOM")
		v.filterBtns[spec.key] = btn
		v.filterOrder[idx] = btn
		prevPill = btn
	end

	v.colSettingsBtn = T and T.CreatePlateButton and T.CreatePlateButton(bar, "Cols", 54, 26, { variant = "secondary", pill = true, fontSize = 11 })
		or CreateFrame("Button", nil, bar)
	v.colSettingsBtn:SetSize(54, 26)
	v.colSettingsBtn:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	if v.colSettingsBtn.fs and v.colSettingsBtn.fs.SetJustifyV then v.colSettingsBtn.fs:SetJustifyV("MIDDLE") end
	v.colSettingsBtn:SetScript("OnClick", function() W.ToggleColumnSettings() end)
	attachHeaderTooltip(v.colSettingsBtn, "Customize Columns", "Show, hide, and reorder Watchlist table columns.", "ANCHOR_BOTTOMLEFT")

	v.shopButton = T and T.CreatePlateButton and T.CreatePlateButton(bar, "Shop", 62, 26, { variant = "secondary", pill = true, fontSize = 11 })
		or CreateFrame("Button", nil, bar)
	v.shopButton:SetSize(62, 26)
	v.shopButton:SetPoint("RIGHT", v.colSettingsBtn, "LEFT", -6, 0)
	if v.shopButton.fs and v.shopButton.fs.SetJustifyV then v.shopButton.fs:SetJustifyV("MIDDLE") end
	v.shopButton:SetScript("OnClick", function()
		if S.host and S.host.toggleShoppingWindow then
			S.host.toggleShoppingWindow(true)
		elseif S.host and S.host.openShoppingWindow then
			S.host.openShoppingWindow(true)
		elseif ns.app and ns.app.toggleShoppingWindow then
			ns.app.toggleShoppingWindow(true)
		end
	end)
	attachHeaderTooltip(v.shopButton, "Shopping List", "Open or close the Shopping List window.", "ANCHOR_BOTTOMLEFT")

	v.resetButton = T and T.CreatePlateButton and T.CreatePlateButton(bar, "Reset", 58, 26, { variant = "secondary", pill = true, fontSize = 11 })
		or CreateFrame("Button", nil, bar)
	v.resetButton:SetSize(58, 26)
	v.resetButton:SetPoint("RIGHT", v.shopButton, "LEFT", -6, 0)
	if v.resetButton.fs and v.resetButton.fs.SetJustifyV then v.resetButton.fs:SetJustifyV("MIDDLE") end
	v.resetButton:SetScript("OnClick", H.resetFilters)
	attachHeaderTooltip(v.resetButton, "Reset Filters", "Clear active Watchlist filter pills, dropdowns, and search text.", "ANCHOR_BOTTOMLEFT")

	v.filtersButton = T and T.CreatePlateButton and T.CreatePlateButton(bar, "Filters", 66, 26, { variant = "secondary", pill = true, fontSize = 11, icon = T and T.ASSETS and T.ASSETS.icon_bars, iconSize = 11 })
		or CreateFrame("Button", nil, bar)
	v.filtersButton:SetSize(66, 26)
	v.filtersButton:SetPoint("RIGHT", v.resetButton, "LEFT", -6, 0)
	if v.filtersButton.fs and v.filtersButton.fs.SetJustifyV then v.filtersButton.fs:SetJustifyV("MIDDLE") end
	v.filtersButton:SetScript("OnClick", function(self)
		if S.host and S.host.toggleScreenFilters then
			S.host.toggleScreenFilters(self)
		elseif S.host and S.host.toggleFiltersPopover then
			S.host.toggleFiltersPopover(self)
		elseif ns.app and ns.app.toggleScreenFilters then
			ns.app.toggleScreenFilters(self)
		end
	end)
	attachHeaderTooltip(v.filtersButton, "Watchlist Filters", "Filter watched entries by type, learned status, and market demand.", "ANCHOR_BOTTOMLEFT")

	local badgePill = (type(T) == "table" and type(T.CreateBadgePill) == "function")
		and T.CreateBadgePill(bar, "Quick-Add Mode", "blue", { height = 22, fontSize = 11, padX = 12 })
		or nil
	local shiftBadge = badgePill and badgePill.frame or CreateFrame("Frame", nil, bar)
	shiftBadge._pill = badgePill
	if not badgePill then
		shiftBadge:SetSize(102, 22)
		shiftBadge.label = shiftBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		shiftBadge.label:SetAllPoints()
		shiftBadge.label:SetJustifyH("CENTER")
		if shiftBadge.label.SetJustifyV then shiftBadge.label:SetJustifyV("MIDDLE") end
		shiftBadge.label:SetText("Quick-Add Mode")
		applyFont(shiftBadge.label, 11, "semibold")
	elseif badgePill.label and badgePill.label.SetJustifyV then
		badgePill.label:SetJustifyV("MIDDLE")
	end
	shiftBadge:SetPoint("RIGHT", v.filtersButton, "LEFT", -8, 0)
	shiftBadge:EnableMouse(true)
	attachHeaderTooltip(shiftBadge, "Quick-Add Mode", "Hold Shift and left-click a row to add +1 to Shopping List, or right-click to remove -1.", "ANCHOR_BOTTOM")
	shiftBadge:Hide()
	v.shiftBadge = shiftBadge

	v.summaryLeftAnchor = prevPill
	v.summary = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	v.summary:SetJustifyH("RIGHT")
	if v.summary.SetJustifyV then v.summary:SetJustifyV("MIDDLE") end
	v.summary:SetWordWrap(false)
	applyFont(v.summary, 11, "regular")
	v.summary:SetText("0 / 0 watched")
	H.updateShiftHeader()
end

function H.buildSidebarControls(v, context, T)
	local sbParent = (context and context.sidebarParent) or v
	local function makeSidebarBtn(txt, onClick, isDrop)
		local btn = CreateFrame("Button", nil, sbParent, "UIPanelButtonTemplate")
		btn:SetSize(194, 21)
		btn:SetText(txt)
		if T and T.SkinButton then T.SkinButton(btn, isDrop and { dropdown = true } or { primary = false }) end
		btn._isCheck = false
		btn:Hide()
		btn:SetScript("OnClick", onClick)
		return btn
	end

	v.modeButton = makeSidebarBtn("View: All", function(self)
		local db = H.getDB()
		local cur = (type(db) == "table" and db.watchlistFilter) or "all"
		if T and T.OpenDropDown then
			T.OpenDropDown(self, C.FILTER_PILLS, cur, function(key)
				if type(db) == "table" then db.watchlistFilter = key end
				H.updateFilterControls(db)
				W.Refresh(S.latest)
			end)
		end
	end, true)

	v.knownButton = makeSidebarBtn("Known: All", function(self)
		local db = H.getDB()
		local cur = (type(db) == "table" and db.watchlistKnownFilter) or "all"
		if T and T.OpenDropDown then
			T.OpenDropDown(self, C.KNOWN_FILTERS, cur, function(key)
				if type(db) == "table" then db.watchlistKnownFilter = key end
				H.updateFilterControls(db)
				W.Refresh(S.latest)
			end)
		end
	end, true)

	v.demandButton = makeSidebarBtn("Demand: All", function(self)
		local db = H.getDB()
		local cur = (type(db) == "table" and db.watchlistDemandFilter) or "all"
		if T and T.OpenDropDown then
			T.OpenDropDown(self, H.demandFilters(), cur, function(key)
				if type(db) == "table" then db.watchlistDemandFilter = key end
				H.updateFilterControls(db)
				W.Refresh(S.latest)
			end)
		end
	end, true)

	v.resetFiltersButton = makeSidebarBtn("Reset Filters", H.resetFilters, false)
end

---------------------------------------------------------------------------------------------------
-- 4. Public UI Provider Interface (matches AllItems provider contract)
---------------------------------------------------------------------------------------------------

function W.GetView()
	return S.view
end

function W.GetSidebarControls()
	local v = S.view
	if not v then return {} end
	return { v.modeButton, v.knownButton, v.demandButton, v.resetFiltersButton }
end

function W.GetColumnConfig()
	return H.normalizeColumnConfig(H.getDB())
end

function W.SetColumnVisible(key, visible)
	local db = H.getDB()
	local cfg, byKey = H.normalizeColumnConfig(db)
	if not byKey[key] or byKey[key].locked then return end
	cfg.hidden[key] = (not visible) and true or nil
	H.applyColumnConfig(db)
	H.refreshColumnPopover()
end

function W.MoveColumn(key, delta)
	local db = H.getDB()
	local cfg, byKey = H.normalizeColumnConfig(db)
	if not byKey[key] or byKey[key].locked then return end
	local idx
	for i, k in ipairs(cfg.order) do
		if k == key then idx = i; break end
	end
	if not idx then return end
	local dst = idx + (delta or 0)
	if dst < 3 or dst > #cfg.order then return end
	cfg.order[idx], cfg.order[dst] = cfg.order[dst], cfg.order[idx]
	H.applyColumnConfig(db)
	H.refreshColumnPopover()
end

function W.ResetColumns()
	local db = H.getDB()
	if type(db) == "table" then
		db.watchlistColumns = nil
	else
		S.fallbackColConfig = { order = {}, hidden = {} }
		for i, col in ipairs(C.COLUMNS) do
			S.fallbackColConfig.order[i] = col.key
			if col.defaultHidden then S.fallbackColConfig.hidden[col.key] = true end
		end
	end
	H.applyColumnConfig(db)
	H.refreshColumnPopover()
end

function W.ToggleColumnSettings(force)
	local pop = S.view and S.view.colSettingsPopover
	if not pop then return false end
	local want = force
	if want == nil then want = not shown(pop) end
	if want then
		H.refreshColumnPopover()
		H.themeColumnSettingsPopover()
		pop:Show()
	else
		pop:Hide()
	end
	return shown(pop)
end

function W.CloseHeatPopover()
	H.closeHeatPopover()
end

function W.GetHeatPopover()
	local pop = type(S.view) == "table" and rawget(S.view, "heatPopover") or nil
	return (type(pop) == "table" or type(pop) == "userdata") and pop or nil
end

function W.SetShiftMode(on)
	local want = on == true
	if S.shiftActive == want then return end
	S.shiftActive = want
	H.updateShiftHeader()
	W.RepaintShoppingQty()
end

function W.RepaintShoppingQty()
	if not (S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame) then return end
	local pal = getThemePalette()
	S.tbl.scrollBox:ForEachFrame(function(r)
		if r.data then H.paintRowShiftUI(r, pal) end
	end)
end

function W.RepaintVisible()
	if not (S.tbl and S.tbl.scrollBox and S.tbl.scrollBox.ForEachFrame) then return end
	local db = H.getDB()
	local _, cfg = H.getActiveColumnDefs(db)
	if S.appliedColSig ~= fingerprint(cfg) then
		H.applyColumnConfig(db)
		return
	end
	S.tbl.scrollBox:ForEachFrame(function(r)
		if r.data then H.bindRow(r, r.data) end
	end)
end

function W.CancelPresentation()
	-- Synchronous evaluation for Watchlist; keep method for AllItems parity.
end

function W.Cancel()
	S.evalSig = nil
end

function W.Invalidate()
	S.evalSig = nil
	S.rows = nil
	S.filteredRows = nil
	S.cellCacheEpoch = S.cellCacheEpoch + 1
end

function W.Layout(width, _, deferScrollRefresh)
	local t = S.tbl
	local v = S.view
	if not (t and v) then return end
	local w = tonumber(width) or (v.GetWidth and v:GetWidth()) or 0
	if w <= 0 then return end
	if ns.Window and ns.Window.LayoutTable then
		local hdrW = (t.headerBar and t.headerBar.GetWidth and t.headerBar:GetWidth()) or 0
		ns.Window.LayoutTable(t, math.max(hdrW, w - 24), 1, deferScrollRefresh)
	end
	if t.scrollBox and t.scrollBox.ForEachFrame then
		local demandW
		for _, col in ipairs(t.columns or {}) do
			if col.key == "demandSort" then demandW = col.width; break end
		end
		if demandW then
			local stripW = math.max(24, demandW - 4)
			t.scrollBox:ForEachFrame(function(r)
				local cell = r.cellGroup and r.cellGroup.cellsByKey and r.cellGroup.cellsByKey.demandSort
				if cell and cell._heatStripBound and cell.heatStrip then
					cell.heatStrip:Layout(stripW)
				end
			end)
		end
	end
	local pop = W.GetHeatPopover()
	if pop and shown(pop) and pop.ownerCell then
		H.repositionHeatPopover(pop, pop.ownerCell)
	end
	H.styleHeaders()
end

function W.Refresh(context)
	if not (S.view and S.tbl) then return end
	if context then S.latest = context end
	local curPriceRev = (ns.GetPriceDataRevision and ns.GetPriceDataRevision()) or ns.priceCacheEpoch or 0
	if S.lastPriceRev ~= curPriceRev then
		S.evalSig = nil
		S.rows = nil
		S.filteredRows = nil
		S.cellCacheEpoch = (S.cellCacheEpoch or 0) + 1
		S.lastPriceRev = curPriceRev
	end
	local ctx = S.latest or {}
	local db = H.getDB(ctx) or {}
	H.updateFilterControls(db)

	if S.appliedColSig ~= fingerprint(H.normalizeColumnConfig(db)) then
		H.applyColumnConfig(db)
	end

	local rows = W.EvaluateRows(ctx)
	local col, asc = H.resolveSort()
	local filters = H.filtersFromDB(ctx)
	local filtered = W.FilterSort(rows, filters, { key = col, ascending = asc })
	S.filteredRows = filtered

	local v = S.view
	local t = S.tbl
	local currentWidth = (S.host and S.host.parent and S.host.parent.GetWidth and S.host.parent:GetWidth())
		or (v.GetWidth and v:GetWidth()) or 0
	if currentWidth > 0 and S.boundWidth ~= currentWidth then
		S.boundWidth = currentWidth
		W.Layout(currentWidth)
	end

	if type(t.setRows) == "function" then
		t.setRows(filtered)
	elseif t.scrollBox and t.scrollBox.SetDataProvider and CreateDataProvider then
		t.scrollBox:SetDataProvider(CreateDataProvider(filtered))
	end

	if v.summary then
		v.summary:SetText(string.format("%d / %d watched", #filtered, #rows))
	end
	if v.emptyText then
		if #rows == 0 then
			v.emptyText:SetText("Your Watchlist is empty. Click the star on any recipe or item in Quick Look or Deep Analysis to track it here.")
			v.emptyText:Show()
		elseif #filtered == 0 then
			v.emptyText:SetText("No watched recipes or items match the active filter or search.")
			v.emptyText:Show()
		else
			v.emptyText:Hide()
		end
	end
	H.styleHeaders()
end

function W.Create(parent, context)
	if S.view then
		if type(context) == "table" then
			S.host = context
			S.latest = context
		end
		return S.view
	end
	S.host = context or {}
	S.latest = context or {}
	local T = (context and context.theme) or ns.Theme
	local v = CreateFrame("Frame", nil, parent)
	v:SetAllPoints()
	v:Hide()
	S.view = v

	v:SetScript("OnUpdate", function()
		if not H.active() then return end
		local down = shiftKeyDown()
		if down ~= S.lastShiftDown then
			S.lastShiftDown = down
			W.SetShiftMode(down)
		end
	end)
	v:SetScript("OnHide", function(self)
		S.lastShiftDown = false
		if S.shiftActive then W.SetShiftMode(false) end
		if self.colSettingsPopover and self.colSettingsPopover.Hide then self.colSettingsPopover:Hide() end
		H.closeHeatPopover()
		W.CancelPresentation()
	end)
	v.CloseHeatPopover = W.CloseHeatPopover
	if type(T) == "table" and type(T.NineApple) == "function" then
		v._mmCard = T.NineApple(v, "glass_r10", "cardBg", false, { noSpecular = true })
	end

	H.buildHeader(v, T)

	local columns = {}
	for i, col in ipairs(C.COLUMNS) do columns[i] = H.copyColumn(col) end
	if type(S.host.createSortableTable) == "function" then
		S.tbl = S.host.createSortableTable(v, -41, "watchlist", columns, H.bindRow, nil, {
			preserveCellColors = true,
			preparedCells = true,
		})
	else
		-- Minimal standalone fallback table if mounted without host.createSortableTable
		local headerBar = CreateFrame("Frame", nil, v)
		headerBar:SetPoint("TOPLEFT", 6, -41)
		headerBar:SetPoint("TOPRIGHT", -18, -41)
		headerBar:SetHeight(28)
		local inset = CreateFrame("Frame", nil, v)
		inset:SetPoint("TOPLEFT", 0, -68)
		inset:SetPoint("BOTTOMRIGHT", 0, 0)
		local scrollBox = CreateFrame("Frame", nil, inset)
		scrollBox:SetAllPoints()
		scrollBox._frames = {}
		function scrollBox:ForEachFrame(fn)
			for _, fr in ipairs(self._frames) do
				if fr:IsShown() then fn(fr) end
			end
		end
		local tbl = {
			columns = columns,
			colX = {},
			headerBtns = {},
			headerBar = headerBar,
			inset = inset,
			scrollBox = scrollBox,
			rowHeight = 22,
			proportional = true,
		}
		local x = 4
		for i, col in ipairs(columns) do
			tbl.colX[i] = x
			x = x + col.width + 5
			local btn = CreateFrame("Button", nil, headerBar)
			btn:SetSize(col.width, 26)
			btn:SetPoint("LEFT", headerBar, "LEFT", tbl.colX[i], 0)
			btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			btn.fs:SetAllPoints()
			btn.fs:SetText(col.label)
			if not col.noSort then
				btn:SetScript("OnClick", function()
					local curCol, curAsc = H.resolveSort()
					if curCol == col.key then
						S.localSort.asc = not curAsc
					else
						S.localSort.col = col.key
						S.localSort.asc = (col.defaultAsc == true)
					end
					W.Refresh(S.latest)
				end)
			end
			tbl.headerBtns[i] = btn
		end
		function tbl.setRows(list)
			for idx = 1, math.max(#scrollBox._frames, #(list or {})) do
				local rowData = list and list[idx]
				local fr = scrollBox._frames[idx]
				if rowData then
					if not fr then
						fr = CreateFrame("Button", nil, scrollBox)
						fr:SetSize(960, tbl.rowHeight)
						fr:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 0, -(idx - 1) * tbl.rowHeight)
						scrollBox._frames[idx] = fr
					end
					fr:Show()
					H.bindRow(fr, rowData)
				elseif fr then
					fr.data = nil
					fr:Hide()
				end
			end
		end
		S.tbl = tbl
	end

	v.table = S.tbl
	S.tbl.headerBtnsByKey = {}
	for i, col in ipairs(S.tbl.columns) do
		local hbtn = S.tbl.headerBtns[i]
		S.tbl.headerBtnsByKey[col.key] = hbtn
		if col.noSort and hbtn and hbtn.SetScript then
			hbtn:SetScript("OnClick", nil)
		end
	end
	S.tbl.growWeights = {}
	for i, col in ipairs(S.tbl.columns) do
		S.tbl.growWeights[i] = col.grow
	end
	if S.tbl.headerBar and S.tbl.headerBar.SetHeight then S.tbl.headerBar:SetHeight(28) end
	H.clearInsetChrome()
	if type(S.tbl.inset) == "table" then
		S.tbl.inset:ClearAllPoints()
		S.tbl.inset:SetPoint("TOPLEFT", 0, -68)
		S.tbl.inset:SetPoint("BOTTOMRIGHT", 0, 0)
	end
	S.tbl.updateHeaders = H.styleHeaders
	S.tbl.proportional = true

	local emptyParent = S.tbl.inset or v
	local emptyText = emptyParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	emptyText:SetPoint("CENTER", emptyParent, "CENTER", 0, 0)
	emptyText:SetWidth(520)
	emptyText:SetJustifyH("CENTER")
	emptyText:SetWordWrap(true)
	applyFont(emptyText, 12, "regular")
	emptyText:SetText("Your Watchlist is empty. Click the star on any recipe or item in Quick Look or Deep Analysis to track it here.")
	emptyText:Hide()
	v.emptyText = emptyText

	H.buildColumnPopover(v, T)
	H.buildSidebarControls(v, context, T)

	v._applyColumnConfig = H.applyColumnConfig
	v._refreshColumnPopover = H.refreshColumnPopover
	v._themeColumnSettingsPopover = H.themeColumnSettingsPopover
	v._applyTheme = H.applyTheme
	v._applyColumnConfig(H.getDB())

	if T and T.RegisterWidget then
		T.RegisterWidget(v, H.applyTheme)
	elseif T and T.OnModeChanged then
		T.OnModeChanged(H.applyTheme)
	end
	if v.HookScript then
		v:HookScript("OnShow", function()
			local curRev = (ns.GetPriceDataRevision and ns.GetPriceDataRevision()) or ns.priceCacheEpoch or 0
			if S.lastPriceRev ~= curRev then
				W.Invalidate()
				W.Refresh(S.latest)
			end
		end)
	end
	H.applyTheme()
	return v
end

if MerchantMasterAPI and type(MerchantMasterAPI.RegisterWatchlist) == "function" then
	MerchantMasterAPI.RegisterWatchlist(W)
end
