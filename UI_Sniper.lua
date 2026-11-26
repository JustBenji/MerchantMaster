-- MerchantMaster UI_Sniper.lua
-- Dedicated Sniper UI providing Gap Sniper (sniper_gap) and Vendor Sniper (sniper_vendor).
-- Follows Apple HIG / Liquid Glass + Warcraft Skins via UI_Theme.lua, lazy construction on
-- first Show(), zero idle OnUpdate scripts, fixed reusable virtual row pooling, and strictly
-- synchronous OnClick purchase actions for WoW Forever compliance.

local ADDON, ns = ...

-- Idempotent reload guard (test_wp2.lua): never recreate or double-register on reload.
if ns.UISniper and ns.sniperProvider then
	if _G.MerchantMasterAPI and _G.MerchantMasterAPI.RegisterSniper then
		_G.MerchantMasterAPI.RegisterSniper(ns.sniperProvider)
	end
	return
end

local UI = {}
ns.UISniper = UI

local unpack = unpack or table.unpack
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format, tostring, tonumber, type, pairs, ipairs = string.format, tostring, tonumber, type, pairs, ipairs

---------------------------------------------------------------------------------------------------
-- Constants & Defaults
---------------------------------------------------------------------------------------------------

local ROW_POOL_SIZE = 18
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 24
local LADDER_ROW_COUNT = 6
local LADDER_PANEL_HEIGHT = 160
local LADDER_ROW_HEIGHT = 17
local SCROLLBAR_WIDTH = 12
local SECTION_GAP = 8

local DEFAULT_CONFIG = {
	gapScope = "all",
	minGapPct = 15,
	minRoiPct = 15,
	minProfitCopper = 10000, -- 1g
	maxSpendCopper = 5000000, -- 500g
	maxBuyShareDailyPct = 50,
	minDailySales = 1,
	minQty = 2,
	fastSellersFirst = true,
	vendorMinProfitCopper = 1000, -- 10s
	vendorIncludeCommodities = true,
	vendorAutoFromBrowse = true,
}

local GAP_SCOPE_LABELS = {
	all = "All AH Items",
	commodities = "Commodities",
	items = "Equipment",
}

local function normalizeGapScope(scope)
	if scope == "commodities" or scope == "items" or scope == "all" then
		return scope
	end
	return "all"
end

local function nextGapScope(scope)
	local cur = normalizeGapScope(scope)
	if cur == "all" then return "commodities" end
	if cur == "commodities" then return "items" end
	return "all"
end

local FALLBACK_QUALITY_HEX = {
	[0] = "9d9d9d",
	[1] = "ffffff",
	[2] = "1eff00",
	[3] = "0070dd",
	[4] = "a335ee",
	[5] = "ff8000",
}

local FALLBACK_PALETTES = {
	dark = {
		mode = "dark",
		winBg = { 0.110, 0.110, 0.118, 0.99 },
		cardBg = { 0.173, 0.173, 0.180, 1.00 },
		cardAltBg = { 0.204, 0.204, 0.220, 1.00 },
		cardHover = { 0.224, 0.224, 0.239, 1.00 },
		inputBg = { 1.000, 1.000, 1.000, 0.075 },
		border = { 1.000, 1.000, 1.000, 0.12 },
		borderStrong = { 1.000, 1.000, 1.000, 0.22 },
		separator = { 0.329, 0.329, 0.345, 0.60 },
		text = { 1.000, 1.000, 1.000, 1.00 },
		textSecondary = { 0.922, 0.922, 0.961, 0.62 },
		textMuted = { 0.682, 0.682, 0.698, 1.00 },
		accentBlue = { 0.000, 0.569, 1.000, 1.00 },
		textBlue = { 0.361, 0.722, 1.000, 1.00 },
		accentGreen = { 0.188, 0.820, 0.345, 1.00 },
		accentOrange = { 1.000, 0.573, 0.188, 1.00 },
		accentRed = { 1.000, 0.380, 0.396, 1.00 },
		accentPurple = { 0.918, 0.553, 1.000, 1.00 },
		frameBorder = { 0.750, 0.560, 0.180, 1.00 },
		hexText = "ffffff",
		hexSecondary = "ebebf5",
		hexMuted = "98989d",
		hexPositive = "30d158",
		hexGreen = "30d158",
		hexBlue = "5ac8fa",
		hexOrange = "ff9230",
		hexRed = "ff4245",
		hexPurple = "bf5af2",
		hexGold = "ffd60a",
		hexSilver = "c7c7cc",
		hexCopper = "e08a5e",
	},
	light = {
		mode = "light",
		winBg = { 0.949, 0.949, 0.969, 0.99 },
		cardBg = { 1.000, 1.000, 1.000, 1.00 },
		cardAltBg = { 0.949, 0.949, 0.969, 1.00 },
		cardHover = { 0.898, 0.898, 0.918, 1.00 },
		inputBg = { 0.000, 0.000, 0.000, 0.06 },
		border = { 0.000, 0.000, 0.000, 0.08 },
		borderStrong = { 0.000, 0.000, 0.000, 0.14 },
		separator = { 0.235, 0.235, 0.263, 0.29 },
		text = { 0.000, 0.000, 0.000, 1.00 },
		textSecondary = { 0.235, 0.235, 0.263, 0.76 },
		textMuted = { 0.369, 0.384, 0.416, 1.00 },
		accentBlue = { 0.000, 0.533, 1.000, 1.00 },
		textBlue = { 0.000, 0.384, 0.800, 1.00 },
		accentGreen = { 0.000, 0.478, 0.169, 1.00 },
		accentOrange = { 0.702, 0.290, 0.000, 1.00 },
		accentRed = { 0.722, 0.078, 0.102, 1.00 },
		accentPurple = { 0.620, 0.125, 0.706, 1.00 },
		frameBorder = { 0.600, 0.440, 0.160, 1.00 },
		hexText = "000000",
		hexSecondary = "3c3c43",
		hexMuted = "5e626a",
		hexPositive = "007a2b",
		hexGreen = "007a2b",
		hexBlue = "0062cc",
		hexOrange = "b34a00",
		hexRed = "b8141a",
		hexPurple = "9e20b4",
		hexGold = "a87600",
		hexSilver = "63666e",
		hexCopper = "9c5630",
	},
}

---------------------------------------------------------------------------------------------------
-- Secret-Value & Defensive Helpers
---------------------------------------------------------------------------------------------------

local function readable(v)
	if type(_G.issecretvalue) == "function" then
		local ok, isSec = pcall(_G.issecretvalue, v)
		if not ok or isSec then return false end
	end
	if type(v) == "table" and type(_G.issecrettable) == "function" then
		local ok, isSec = pcall(_G.issecrettable, v)
		if not ok or isSec then return false end
	end
	return true
end

local function shown(frame)
	if (type(frame) ~= "table" and type(frame) ~= "userdata") or type(frame.IsShown) ~= "function" then
		return false
	end
	local ok, val = pcall(frame.IsShown, frame)
	return ok and readable(val) and val == true
end

local function safeNum(v, fallback)
	if not readable(v) then return fallback end
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

local function safeStr(v, fallback)
	if not readable(v) then return fallback or "" end
	if type(v) == "string" then return v end
	return fallback or ""
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function shiftDown()
	if type(_G.IsShiftKeyDown) ~= "function" then return false end
	local ok, val = pcall(_G.IsShiftKeyDown)
	return ok and readable(val) and val == true
end

local function isAtAH()
	return shown(_G.AuctionHouseFrame)
end

local function getSE()
	local se = ns.SniperEngine
	if type(se) == "table" then return se end
	return nil
end

local function getTheme()
	local t = ns.Theme
	if type(t) == "table" then return t end
	return nil
end

local function getPal()
	local T = getTheme()
	local mode = (T and T.GetMode and T.GetMode()) or "dark"
	if mode ~= "light" then mode = "dark" end
	local pal = (T and T.GetActivePalette and T.GetActivePalette())
		or (T and T.PALETTES and T.PALETTES[mode])
		or FALLBACK_PALETTES[mode]
	return pal, mode
end

local function isCustomSkin()
	local T = getTheme()
	return T and type(T.IsCustomSkin) == "function" and T.IsCustomSkin() == true
end

local function getTableStyle()
	if not isCustomSkin() then return "standard" end
	local T = getTheme()
	return (T and T.GetTableStyle and T.GetTableStyle()) or "t5_ruled"
end

local function hasSnapshotMode()
	if type(ns.HasSnapshots) == "function" and ns.HasSnapshots() then
		return true
	end
	if type(ns.HasSnapshotExtension) == "function" and ns.HasSnapshotExtension() then
		return true
	end
	if ns.app and ns.app.snapshotExtension ~= nil then
		return true
	end
	return false
end

local function applyFont(fs, size, weight, flags)
	if type(fs) ~= "table" then return end
	local T = getTheme()
	if T and type(T.ApplyFont) == "function" then
		T.ApplyFont(fs, size or 12, weight or "regular", flags or "")
	elseif type(fs.SetFont) == "function" then
		local fonts = T and T.FONTS
		local fallback = (fonts and fonts.fallback) or _G.STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
		local path = (weight == "semibold" or weight == "bold")
			and ((fonts and fonts.semibold) or fallback)
			or ((fonts and fonts.regular) or fallback)
		local ok = fs:SetFont(path, size or 12, flags or "")
		if ok == false then
			fs:SetFont(fallback, size or 12, flags or "")
		end
	end
	if type(fs.SetShadowOffset) == "function" then fs:SetShadowOffset(0, 0) end
	if type(fs.SetShadowColor) == "function" then fs:SetShadowColor(0, 0, 0, 0) end
end

local function setFsColor(fs, col, alphaOverride)
	if not fs or type(fs.SetTextColor) ~= "function" or type(col) ~= "table" then return end
	fs:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, alphaOverride or col[4] or 1)
end

local function formatMoney(copper, signed)
	local val = safeNum(copper)
	if val == nil then return "--" end
	local T = getTheme()
	if T and type(T.FormatMoneyText) == "function" then
		local ok, txt = pcall(T.FormatMoneyText, val, signed)
		if ok and readable(txt) and type(txt) == "string" and txt ~= "" then
			return txt
		end
	end
	if type(ns.FormatMoneyCompact) == "function" then
		local ok, txt = pcall(ns.FormatMoneyCompact, val, signed)
		if ok and readable(txt) and type(txt) == "string" and txt ~= "" then
			return txt
		end
	end
	local neg = val < 0
	local a = floor(abs(val) + 0.5)
	local g = floor(a / 10000)
	local s = floor((a % 10000) / 100)
	local c = a % 100
	local prefix = neg and "-" or (signed and a > 0 and "+" or "")
	if g > 0 then
		if s > 0 then return format("%s%dg %02ds", prefix, g, s) end
		return format("%s%dg", prefix, g)
	elseif s > 0 then
		if c > 0 then return format("%s%ds %02dc", prefix, s, c) end
		return format("%s%ds", prefix, s)
	end
	return format("%s%dc", prefix, c)
end

local function formatPercent(pct)
	local n = safeNum(pct)
	if n == nil then return "--" end
	if abs(n) >= 100 then
		return format("%.0f%%", n)
	end
	return format("%.1f%%", n)
end

local function formatInt(n)
	local v = floor(safeNum(n, 0) + 0.5)
	local neg = v < 0
	local s = tostring(abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return neg and ("-" .. out) or out
end

local function formatHours(hours)
	local h = safeNum(hours)
	if h == nil or h <= 0 then return "--" end
	if h < 1 then
		return format("%dm", max(1, floor(h * 60 + 0.5)))
	elseif h < 48 then
		return format("%.1fh", h)
	end
	return format("%.1fd", h / 24)
end

local function formatSilverGoldInput(copper)
	local c = max(0, floor(safeNum(copper, 0) + 0.5))
	if c == 0 then return "0s" end
	if c >= 10000 and (c % 10000) == 0 then
		return format("%dg", floor(c / 10000))
	elseif c >= 10000 and (c % 100) == 0 then
		local g = floor(c / 10000)
		local s = floor((c % 10000) / 100)
		return format("%dg %ds", g, s)
	elseif (c % 100) == 0 then
		return format("%ds", floor(c / 100))
	end
	return format("%.1fs", c / 100)
end

local function parseSilverGoldInput(raw)
	local txt = safeStr(raw, ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if txt == "" then return 0 end
	local g = safeNum(txt:match("(%d+%.?%d*)%s*g"))
	local s = safeNum(txt:match("(%d+%.?%d*)%s*s"))
	local c = safeNum(txt:match("(%d+%.?%d*)%s*c"))
	if g or s or c then
		return max(0, floor((g or 0) * 10000 + (s or 0) * 100 + (c or 0) + 0.5))
	end
	local bare = safeNum(txt)
	if bare then
		-- Bare number in Vendor Min Profit defaults to silver (s).
		return max(0, floor(bare * 100 + 0.5))
	end
	return nil
end

local function resolveItemInfo(itemID, itemLink)
	local id = safeNum(itemID, 0)
	local name, link, quality, icon
	local query = (type(itemLink) == "string" and itemLink ~= "") and itemLink or (id > 0 and id or nil)
	if query then
		if _G.C_Item and type(_G.C_Item.GetItemInfo) == "function" then
			local ok, rName, rLink, rQual, _, _, _, _, _, _, rIcon = pcall(_G.C_Item.GetItemInfo, query)
			if ok then
				if readable(rName) and type(rName) == "string" then name = rName end
				if readable(rLink) and type(rLink) == "string" then link = rLink end
				if readable(rQual) and type(rQual) == "number" then quality = rQual end
				if readable(rIcon) and rIcon ~= nil then icon = rIcon end
			end
		elseif type(_G.GetItemInfo) == "function" then
			local ok, rName, rLink, rQual, _, _, _, _, _, _, rIcon = pcall(_G.GetItemInfo, query)
			if ok then
				if readable(rName) and type(rName) == "string" then name = rName end
				if readable(rLink) and type(rLink) == "string" then link = rLink end
				if readable(rQual) and type(rQual) == "number" then quality = rQual end
				if readable(rIcon) and rIcon ~= nil then icon = rIcon end
			end
		end
		if not icon and id > 0 and _G.C_Item and type(_G.C_Item.GetItemIconByID) == "function" then
			local ok, rIcon = pcall(_G.C_Item.GetItemIconByID, id)
			if ok and readable(rIcon) and rIcon ~= nil then icon = rIcon end
		end
	end
	return name, link, quality, icon
end

local function getDealItemVisual(deal)
	if type(deal) ~= "table" then return "Unknown Item", nil, 1, nil end
	local id = safeNum(deal.itemID, 0)
	local name = safeStr(deal.itemName or deal.name, "")
	local link = safeStr(deal.itemLink, "")
	local quality = safeNum(deal.quality)
	local icon = readable(deal.icon) and deal.icon or nil
	if name == "" or not icon or quality == nil then
		local rName, rLink, rQual, rIcon = resolveItemInfo(id, link ~= "" and link or nil)
		if name == "" and rName then name = rName end
		if link == "" and rLink then link = rLink end
		if quality == nil and rQual then quality = rQual end
		if not icon and rIcon then icon = rIcon end
	end
	if name == "" then
		name = id > 0 and ("Item #" .. tostring(id)) or "Unknown Item"
	end
	return name, (link ~= "" and link or nil), quality or 1, icon
end

local function qualityColorForDeal(quality, pal)
	local q = safeNum(quality, 1)
	if q == 1 then
		return pal.text
	end
	local iqc = _G.ITEM_QUALITY_COLORS
	if type(iqc) == "table" and type(iqc[q]) == "table" then
		local c = iqc[q]
		if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
			-- In light mode darken bright uncommon green/white slightly for readability.
			if pal.mode == "light" and q == 2 then
				return pal.accentGreen
			end
			return { c.r, c.g, c.b, 1 }
		end
	end
	if q == 2 then return pal.accentGreen end
	if q == 3 then return pal.textBlue or pal.accentBlue end
	if q == 4 then return pal.accentPurple end
	if q == 5 then return pal.accentOrange end
	if q == 0 then return pal.textMuted end
	return pal.text
end

local function normalizeSubTab(subTab)
	if subTab == "sniper_vendor" or subTab == "vendor" then
		return "sniper_vendor"
	end
	return "sniper_gap"
end

---------------------------------------------------------------------------------------------------
-- Persisted Config (MerchantMasterDB.sniper)
---------------------------------------------------------------------------------------------------

local fallbackConfig = {}

local function getMergedDefaults()
	local out = {}
	for k, v in pairs(DEFAULT_CONFIG) do out[k] = v end
	local SE = getSE()
	if SE and type(SE.GetDefaults) == "function" then
		local ok, engDef = pcall(SE.GetDefaults)
		if ok and type(engDef) == "table" then
			for k, v in pairs(engDef) do
				out[k] = v
			end
		end
	end
	return out
end

local function getConfig()
	local SE = getSE()
	if SE and type(SE.GetSettings) == "function" then
		local ok, cfg = pcall(SE.GetSettings)
		if ok and type(cfg) == "table" then
			local defs = getMergedDefaults()
			for k, v in pairs(defs) do
				if cfg[k] == nil then cfg[k] = v end
			end
			return cfg
		end
	elseif SE and type(SE.GetConfig) == "function" then
		local ok, cfg = pcall(SE.GetConfig)
		if ok and type(cfg) == "table" then
			local defs = getMergedDefaults()
			for k, v in pairs(defs) do
				if cfg[k] == nil then cfg[k] = v end
			end
			return cfg
		end
	end
	local db = _G.MerchantMasterDB
	local cfg
	if type(db) == "table" then
		if type(db.sniper) ~= "table" then db.sniper = {} end
		cfg = db.sniper
	else
		cfg = fallbackConfig
	end
	local defs = getMergedDefaults()
	for k, v in pairs(defs) do
		if cfg[k] == nil then cfg[k] = v end
	end
	return cfg
end

local function updateConfig(key, value)
	local cfg = getConfig()
	cfg[key] = value
	local SE = getSE()
	if SE and type(SE.SetOption) == "function" then
		pcall(SE.SetOption, key, value)
	elseif SE and type(SE.SetConfig) == "function" then
		pcall(SE.SetConfig, key, value)
	elseif SE and type(SE.UpdateConfig) == "function" then
		pcall(SE.UpdateConfig, cfg)
	end
end

---------------------------------------------------------------------------------------------------
-- Engine Deal Field Extractors (defensive aliases for seamless Wave B integration)
---------------------------------------------------------------------------------------------------

local function getDealKey(deal)
	if type(deal) ~= "table" then return "" end
	if deal.idKey ~= nil then return tostring(deal.idKey) end
	if deal.dealKey ~= nil then return tostring(deal.dealKey) end
	if deal.key ~= nil then return tostring(deal.key) end
	if deal.auctionID ~= nil then return tostring(deal.itemID or 0) .. ":" .. tostring(deal.auctionID) end
	return tostring(deal.itemID or 0) .. ":" .. tostring(deal.source or "")
end

local function getGapBuyQty(d) return safeNum(d.buyQty or d.qty or d.quantity, 0) end
local function getRemainingItemListings(d)
	if type(d) ~= "table" or d.kind ~= "item" then return 0 end
	if type(d.buyQueue) == "table" then
		return #d.buyQueue
	end
	local rem = safeNum(d.remainingListings)
	if rem ~= nil then return max(0, floor(rem)) end
	local lc = safeNum(d.listingCount)
	if lc ~= nil then return max(0, floor(lc)) end
	local tl = safeNum(d.totalListings)
	if tl ~= nil then return max(0, floor(tl)) end
	return 1
end
local function getGapListingCount(d)
	if type(d) ~= "table" then return 0 end
	local tl = safeNum(d.totalListings)
	if tl and tl > 0 then return floor(tl) end
	local bought = safeNum(d.boughtListings, 0)
	if bought > 0 then
		return floor(bought) + getRemainingItemListings(d)
	end
	local lc = safeNum(d.listingCount)
	if lc and lc > 0 then return floor(lc) end
	if type(d.buyQueue) == "table" and #d.buyQueue > 0 then
		return #d.buyQueue
	end
	local rem = safeNum(d.remainingListings)
	if rem and rem > 0 then return floor(rem) end
	return 0
end
local function formatGapQty(d)
	local qty = getGapBuyQty(d)
	if type(d) == "table" and d.kind == "item" then
		local totalLots = getGapListingCount(d)
		local rem = getRemainingItemListings(d)
		local bought = safeNum(d.boughtListings, 0)
		if bought > 0 and totalLots > 1 then
			return format("%sx (%d/%d lots)", formatInt(qty), rem, totalLots)
		end
		local lots = (type(d.buyQueue) == "table" and #d.buyQueue > 0) and #d.buyQueue or totalLots
		if lots > 1 then
			return format("%sx (%d lots)", formatInt(qty), lots)
		elseif lots == 1 then
			return format("%sx (1 lot)", formatInt(qty))
		end
		return format("%sx", formatInt(qty))
	end
	return formatInt(qty)
end
local function getGapAvgBuy(d) return safeNum(d.avgBuyPrice or d.avgBuy or d.avgUnitPrice, 0) end
local function getGapNextTier(d) return safeNum(d.nextTierPrice or d.nextTier or d.wallPrice, 0) end
local function getGapRelistPrice(d) return safeNum(d.relistPrice or d.resalePrice, max(0, getGapNextTier(d) - 1)) end
local function getGapPct(d) return safeNum(d.gapPct, 0) end
local function getGapRoiPct(d) return safeNum(d.roiPct, 0) end
local function getGapNetProfit(d) return safeNum(d.netProfit or d.profit, 0) end
local function getGapDailySold(d) return safeNum(d.dailySold or d.salesPerDay or d.effectiveDailySold, 0) end
local function getGapEstHours(d)
	local h = safeNum(d.estHoursToSell)
	if h and h > 0 then return h end
	local ds = getGapDailySold(d)
	local qty = getGapBuyQty(d)
	if ds > 0 and qty > 0 then
		return (qty / ds) * 24
	end
	return nil
end

local function getVendorAhPrice(d) return safeNum(d.ahPrice or d.minPrice or d.buyoutAmount or d.unitPrice, 0) end
local function getVendorSell(d) return safeNum(d.vendorSell or d.vendorPrice, 0) end
local function getVendorProfitUnit(d)
	local p = safeNum(d.profitPerUnit or d.unitProfit)
	if p ~= nil then return p end
	return getVendorSell(d) - getVendorAhPrice(d)
end
local function getVendorQty(d) return max(1, floor(safeNum(d.totalQuantity or d.qty or d.quantity, 1))) end
local function getVendorTotalProfit(d)
	local tp = safeNum(d.totalProfit)
	if tp ~= nil then return tp end
	return max(0, getVendorProfitUnit(d)) * getVendorQty(d)
end

local function getActivePurchaseState()
	local SE = getSE()
	if SE and type(SE.GetPurchaseState) == "function" then
		local ok, ps = pcall(SE.GetPurchaseState)
		if ok and type(ps) == "table" then return ps end
	end
	return nil
end

local function resolveDealStep(deal, ps)
	if type(deal) ~= "table" then return "ready" end
	local step = safeStr(deal.purchaseState or deal.actionState or deal.state or deal.status, "")
	if ps and (ps.active or ps.step or ps.state) then
		local psKey = (ps.idKey or ps.dealKey) and tostring(ps.idKey or ps.dealKey) or nil
		local dKey = getDealKey(deal)
		local matches = (ps.deal and ps.deal == deal)
			or (psKey and psKey == dKey)
			or (not psKey and ps.itemID and deal.itemID and ps.itemID == deal.itemID and (not ps.auctionID or ps.auctionID == deal.auctionID))
		if matches then
			local pStep = safeStr(ps.step or ps.state, "")
			if pStep ~= "" then step = pStep end
		end
	end
	step = step:lower()
	if step == "" or step == "new" or step == "idle" then return "ready" end
	return step
end

local BLOCKED_REASON_LABELS = {
	ah_closed = { "Open AH", "Open the Auction House before buying or checking." },
	cart_buyer_busy = { "Cart Buyer Busy", "Finish or pause Cart Buyer before starting a sniper action." },
	insufficient_gold = { "Not Enough Gold", "Not enough gold for this purchase." },
	throttled = { "AH Busy", "Auction House busy. Click again in a moment." },
	purchase_in_flight = { "Purchase Active", "Another sniper purchase is already in flight." },
	needs_live_scan = { "Check at AH", "Snapshot equipment deal requires live Check at the Auction House." },
	expired = { "Check Expired", "Live verification expired. Click Check again." },
	unprofitable = { "Price Changed", "Listing is no longer profitable at current price." },
	empty_shortlist = { "No Matches", "No items matched your current shortlist filters." },
	insufficient_live_history = {
		"Need AH History",
		"Scan the AH at least 3 times (across 15+ minutes) to build local baseline prices for Gap Sniper.",
	},
	api_unavailable = { "AH Unavailable", "Auction House API is currently unavailable." },
}

local function describeBlockedReason(errCode, engineMsg)
	local code = safeStr(errCode, ""):lower()
	local entry = BLOCKED_REASON_LABELS[code]
	local eng = safeStr(engineMsg, "")
	if entry then
		return entry[1], (eng ~= "" and eng or entry[2])
	end
	if eng ~= "" then
		local short = (#eng > 22) and (eng:sub(1, 19) .. "...") or eng
		return short, eng
	end
	if code ~= "" then
		return code, "Action blocked: " .. code
	end
	return "Action Blocked", "Action could not be completed."
end

local function gapActionPresentation(deal, ps)
	local step = resolveDealStep(deal, ps)
	if step == "checking" or step == "verifying" then
		return "Checking...", "secondary", false, "checking"
	elseif step == "unavailable" or step == "gone" then
		return "Gone", "ghost", false, "unavailable"
	elseif step == "quoting" or step == "requesting_quote" then
		return "Quoting...", "secondary", false, step
	elseif step == "awaiting_confirm" or step == "confirm" then
		return "Confirm", "primary", true, step
	elseif step == "confirming" or step == "buying" or step == "purchasing" then
		return "Buying...", "secondary", false, step
	elseif step == "bought" or step == "purchased" or step == "done" then
		return "Bought", "ghost", false, step
	end

	if type(deal) == "table" and deal.kind == "item" then
		if deal.needsLiveScan == true or type(deal.buyQueue) ~= "table" then
			return "Check", "secondary", true, "needs_live_scan"
		end
		local rem = getRemainingItemListings(deal)
		if rem <= 0 then
			return "Bought", "ghost", false, "bought"
		end
		local label = (rem > 1) and format("Buy (%d)", rem) or "Buy"
		if step == "failed" or step == "cancelled" or step == "canceled" or step == "expired" then
			return label, "secondary", true, step
		end
		return label, "primary", true, "ready"
	end

	if step == "failed" or step == "cancelled" or step == "canceled" or step == "expired" then
		return "Buy", "secondary", true, step
	end
	return "Buy", "primary", true, "ready"
end

local function vendorActionPresentation(deal, ps)
	local step = resolveDealStep(deal, ps)
	local isComm = (deal and (deal.isCommodity == true or deal.kind == "commodity"))
	if step == "checking" or step == "verifying" then
		return "Checking...", "secondary", false, "Checking"
	elseif step == "quoting" or step == "requesting_quote" then
		return "Quoting...", "secondary", false, "Quoting"
	elseif step == "awaiting_confirm" or step == "confirm" then
		return "Confirm", "primary", true, "Confirm"
	elseif step == "ready_to_buy" or step == "verified" then
		return "Buy", "primary", true, "Verified"
	elseif step == "buying" or step == "confirming" or step == "purchasing" then
		return "Buying...", "secondary", false, "Buying"
	elseif step == "bought" or step == "purchased" or step == "done" then
		return "Bought", "ghost", false, "Bought"
	elseif step == "gone" or step == "unavailable" then
		return "Gone", "ghost", false, "Gone"
	elseif step == "price_up" or step == "overpriced" or step == "not_profitable" then
		return "Price Up", "ghost", false, "Price Up"
	elseif step == "unverified" then
		return "Check", "secondary", true, "New"
	elseif step == "failed" or step == "cancelled" or step == "canceled" then
		return isComm and "Buy" or "Check", "secondary", true, "Retry"
	end
	if isComm then
		return "Buy", "primary", true, "Ready"
	end
	return "Check", "secondary", true, "New"
end

---------------------------------------------------------------------------------------------------
-- Internal State
---------------------------------------------------------------------------------------------------

local state = {
	parent = nil,
	root = nil,
	built = false,
	themeHooked = false,
	listenerHooked = false,
	activeSubTab = "sniper_gap",
	dirty = true,
	refreshTimerPending = false,
	pendingRefreshReason = nil,

	gapView = nil,
	vendorView = nil,

	gapSort = { col = "netProfit", asc = false },
	vendorSort = { col = "profitPerUnit", asc = false },
	gapRows = {},
	vendorRows = {},

	selectedGapKey = nil,
	selectedGapDeal = nil,
	ladderExpanded = false,

	statusOverride = nil,
	statusMessage = nil,
	statusVariant = nil,
	vendorStatusMsg = nil,

	styledCards = {},
	themedText = {},
	themedSeparators = {},
	tables = {},
}

---------------------------------------------------------------------------------------------------
-- Surface & Skin Helpers (Apple HIG + Warcraft Skins)
---------------------------------------------------------------------------------------------------

local function createSurfaceCard(parent, kind, fillKey)
	local f = CreateFrame("Frame", nil, parent)
	local T = getTheme()
	local card
	if T and type(T.NineApple) == "function" then
		card = T.NineApple(f, kind or "glass_r10", fillKey or "cardBg", false, { noSpecular = true })
	end
	local bgFallback = not card and f:CreateTexture(nil, "BACKGROUND") or nil
	if bgFallback then bgFallback:SetAllPoints(f) end

	local skinEdges = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		local t = f:CreateTexture(nil, "BORDER", nil, 2)
		if side == "top" then
			t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
			t:SetHeight(1)
		elseif side == "bottom" then
			t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
			t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
			t:SetHeight(1)
		elseif side == "left" then
			t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
			t:SetWidth(1)
		else
			t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
			t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
			t:SetWidth(1)
		end
		t:Hide()
		skinEdges[side] = t
	end

	local entry = {
		frame = f,
		card = card,
		bgFallback = bgFallback,
		fillKey = fillKey or "cardBg",
		skinEdges = skinEdges,
	}
	state.styledCards[#state.styledCards + 1] = entry
	f._mmSniperCard = entry
	return f, entry
end

local function paintSurfaceCard(entry, pal)
	if not entry then return end
	if entry.card and entry.card.UpdateTheme then
		entry.card:UpdateTheme()
	elseif entry.bgFallback then
		local col = pal[entry.fillKey] or pal.cardBg
		entry.bgFallback:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
	end
	local custom = isCustomSkin()
	local fb = pal.frameBorder or pal.borderStrong or { 0.75, 0.56, 0.18, 0.85 }
	for _, tex in pairs(entry.skinEdges) do
		if custom then
			tex:SetColorTexture(fb[1], fb[2], fb[3], 0.72)
			tex:Show()
		else
			tex:Hide()
		end
	end
end

local function registerThemedFs(fs, colorKey)
	state.themedText[#state.themedText + 1] = { fs = fs, key = colorKey or "text" }
	return fs
end

local function createSeparator(parent)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetHeight(1)
	state.themedSeparators[#state.themedSeparators + 1] = tex
	return tex
end

local function createButton(parent, label, w, h, opts)
	local T = getTheme()
	if T and type(T.CreatePlateButton) == "function" then
		return T.CreatePlateButton(parent, label, w, h, opts)
	end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 96, h or 24)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)
	bg:SetColorTexture(0.24, 0.24, 0.28, 1)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetText(label or "")
	if b.SetFontString then b:SetFontString(fs) end
	b.fs = fs
	function b:SetVariant() end
	function b:SetActive() end
	return b
end

local function createBadgePill(parent, text, variant, opts)
	local T = getTheme()
	if T and type(T.CreateBadgePill) == "function" then
		return T.CreateBadgePill(parent, text, variant, opts)
	end
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(84, (opts and opts.height) or 20)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(0.25, 0.25, 0.30, 0.85)
	local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lbl:SetPoint("CENTER", 0, 0)
	lbl:SetText(text or "")
	local pill = { frame = f, label = lbl, variant = variant or "neutral" }
	function pill:SetVariant(v, t)
		if v then self.variant = v end
		if t ~= nil then
			lbl:SetText(tostring(t))
			f:SetWidth(max(44, #tostring(t) * 6 + 16))
		end
	end
	return pill
end

local function createProgressBar(parent, h, opts)
	local T = getTheme()
	if T and type(T.CreateProgressBar) == "function" then
		return T.CreateProgressBar(parent, h or 6, opts)
	end
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(h or 6)
	local track = f:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(f)
	track:SetColorTexture(1, 1, 1, 0.14)
	local fill = f:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	fill:SetWidth(1)
	fill:SetColorTexture(0.0, 0.569, 1.0, 0.9)
	local bar = { frame = f, _frac = 0 }
	function bar:SetValue(frac, col)
		self._frac = clamp(safeNum(frac, 0), 0, 1)
		local w = max(1, (f.GetWidth and f:GetWidth()) or 160)
		fill:SetWidth(max(1, floor(w * self._frac + 0.5)))
		if self._frac <= 0 then fill:Hide() else fill:Show() end
		if type(col) == "table" then
			fill:SetColorTexture(col[1], col[2], col[3], col[4] or 0.9)
		end
	end
	function bar:SetColor(col)
		if type(col) == "table" then
			fill:SetColorTexture(col[1], col[2], col[3], col[4] or 0.9)
		end
	end
	return bar
end

local function createNumericField(parent, labelText, boxW, tooltipText, onCommit)
	local wrap = CreateFrame("Frame", nil, parent)
	wrap:SetHeight(22)

	local lbl = wrap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lbl:SetPoint("LEFT", wrap, "LEFT", 0, 0)
	lbl:SetJustifyH("LEFT")
	if lbl.SetWordWrap then lbl:SetWordWrap(false) end
	applyFont(lbl, 11, "regular")
	lbl:SetText(labelText)
	registerThemedFs(lbl, "textSecondary")

	local box = CreateFrame("EditBox", nil, wrap)
	box:SetSize(boxW or 48, 20)
	box:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
	if box.SetAutoFocus then box:SetAutoFocus(false) end
	if box.SetMaxLetters then box:SetMaxLetters(14) end
	if box.SetJustifyH then box:SetJustifyH("RIGHT") end

	local T = getTheme()
	if T and type(T.StyleEditBox) == "function" then
		T.StyleEditBox(box, { pill = false, border = true, fontSize = 11, leftInset = 6, rightInset = 6 })
	else
		applyFont(box, 11, "regular")
		local bg = box:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(box)
		bg:SetColorTexture(1, 1, 1, 0.08)
	end

	local function commit()
		if type(onCommit) == "function" then
			onCommit(box:GetText(), box)
		end
	end
	box:SetScript("OnEnterPressed", function(self)
		commit()
		if self.ClearFocus then self:ClearFocus() end
	end)
	box:SetScript("OnEscapePressed", function(self)
		if self.ClearFocus then self:ClearFocus() end
		if UI.IsShown() then UI.Refresh("escape_filter") end
	end)
	box:SetScript("OnEditFocusLost", function()
		commit()
	end)

	if tooltipText and tooltipText ~= "" then
		local function showTip(owner)
			if not _G.GameTooltip then return end
			_G.GameTooltip:SetOwner(owner, "ANCHOR_TOP")
			_G.GameTooltip:ClearLines()
			_G.GameTooltip:AddLine(labelText, 1, 1, 1)
			_G.GameTooltip:AddLine(tooltipText, 0.85, 0.85, 0.90, true)
			_G.GameTooltip:Show()
		end
		local function hideTip()
			if _G.GameTooltip then _G.GameTooltip:Hide() end
		end
		box:HookScript("OnEnter", showTip)
		box:HookScript("OnLeave", hideTip)
	end

	local lblW = max(36, ceil((lbl.GetStringWidth and lbl:GetStringWidth()) or (#labelText * 6)))
	wrap:SetWidth(lblW + 6 + (boxW or 48) + 4)

	return { wrap = wrap, label = lbl, box = box }
end

local function createToggleField(parent, labelText, tooltipText, onToggle)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(34, 18)
	local lbl = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lbl:SetText(labelText)
	cb.label = lbl
	local T = getTheme()
	if T and type(T.SkinCheckButton) == "function" then
		T.SkinCheckButton(cb)
	else
		applyFont(lbl, 11, "regular")
		lbl:ClearAllPoints()
		lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
	end
	applyFont(lbl, 11, "regular")

	cb:SetScript("OnClick", function(self)
		local on = self.GetChecked and self:GetChecked() and true or false
		if type(onToggle) == "function" then
			onToggle(on)
		end
	end)
	if tooltipText and tooltipText ~= "" then
		cb:HookScript("OnEnter", function(self)
			if not _G.GameTooltip then return end
			_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
			_G.GameTooltip:ClearLines()
			_G.GameTooltip:AddLine(labelText, 1, 1, 1)
			_G.GameTooltip:AddLine(tooltipText, 0.85, 0.85, 0.90, true)
			_G.GameTooltip:Show()
		end)
		cb:HookScript("OnLeave", function()
			if _G.GameTooltip then _G.GameTooltip:Hide() end
		end)
	end
	return cb
end

---------------------------------------------------------------------------------------------------
-- Fixed Reusable Virtual Pooled Table
---------------------------------------------------------------------------------------------------

local function createPooledTable(parent, columns, opts)
	opts = opts or {}
	local container, cardEntry = createSurfaceCard(parent, "glass_r10", "cardBg")

	-- Header bar
	local header = CreateFrame("Frame", nil, container)
	header:SetHeight(HEADER_HEIGHT)
	header:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", container, "TOPRIGHT", -1, -1)

	local headerBg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
	headerBg:SetAllPoints(header)
	headerBg:Hide()

	local headerSep = createSeparator(header)
	headerSep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 6, 0)
	headerSep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -6, 0)

	-- Body clip area
	local body = CreateFrame("Frame", nil, container)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -3)
	body:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(SCROLLBAR_WIDTH + 8), 4)
	if body.SetClipsChildren then body:SetClipsChildren(true) end
	if body.EnableMouseWheel then body:EnableMouseWheel(true) end

	-- Slim scrollbar
	local scrollBar = CreateFrame("Slider", nil, container)
	scrollBar:SetWidth(SCROLLBAR_WIDTH)
	scrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -3, -(HEADER_HEIGHT + 4))
	scrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -3, 4)
	if scrollBar.SetOrientation then scrollBar:SetOrientation("VERTICAL") end
	if scrollBar.SetMinMaxValues then scrollBar:SetMinMaxValues(0, 0) end
	if scrollBar.SetValueStep then scrollBar:SetValueStep(1) end
	if scrollBar.SetObeyStepOnDrag then scrollBar:SetObeyStepOnDrag(true) end
	if scrollBar.SetValue then scrollBar:SetValue(0) end
	local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(4, 32)
	thumb:SetColorTexture(1, 1, 1, 0.28)
	if scrollBar.SetThumbTexture then scrollBar:SetThumbTexture(thumb) end
	local T = getTheme()
	if T and type(T.SlimScrollBar) == "function" then
		T.SlimScrollBar(scrollBar)
	end

	-- Empty state text
	local emptyFs = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	emptyFs:SetPoint("CENTER", body, "CENTER", 0, 4)
	emptyFs:SetWidth(420)
	emptyFs:SetJustifyH("CENTER")
	if emptyFs.SetWordWrap then emptyFs:SetWordWrap(true) end
	applyFont(emptyFs, 12, "regular")
	registerThemedFs(emptyFs, "textMuted")
	emptyFs:Hide()

	local tbl = {
		container = container,
		cardEntry = cardEntry,
		header = header,
		headerBg = headerBg,
		headerSep = headerSep,
		body = body,
		scrollBar = scrollBar,
		emptyFs = emptyFs,
		columns = columns,
		headers = {},
		rows = {},
		data = {},
		scrollOffset = 0,
		visibleCount = ROW_POOL_SIZE,
		colX = {},
		colW = {},
		opts = opts,
		_settingSlider = false,
	}

	-- Create column header buttons
	for idx, col in ipairs(columns) do
		local hb = CreateFrame("Button", nil, header)
		hb:SetHeight(HEADER_HEIGHT)
		local fs = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("LEFT", hb, "LEFT", 4, 0)
		fs:SetPoint("RIGHT", hb, "RIGHT", -4, 0)
		fs:SetJustifyH(col.align or "LEFT")
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		if fs.SetMaxLines then fs:SetMaxLines(1) end
		applyFont(fs, 11, "semibold")
		fs:SetText(col.label)
		hb.fs = fs
		hb.col = col

		local hl = hb:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(hb)
		hl:SetColorTexture(1, 1, 1, 0.05)

		if col.sortable ~= false then
			hb:SetScript("OnClick", function()
				if type(opts.onHeaderClick) == "function" then
					opts.onHeaderClick(col.key)
				end
			end)
		end
		if col.hint then
			hb:SetScript("OnEnter", function(self)
				if not _G.GameTooltip then return end
				_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
				_G.GameTooltip:ClearLines()
				_G.GameTooltip:AddLine(col.label, 1, 1, 1)
				_G.GameTooltip:AddLine(col.hint, 0.85, 0.85, 0.90, true)
				_G.GameTooltip:Show()
			end)
			hb:SetScript("OnLeave", function()
				if _G.GameTooltip then _G.GameTooltip:Hide() end
			end)
		end
		tbl.headers[idx] = hb
	end

	-- Create fixed pool of ROW_POOL_SIZE reusable row frames
	for i = 1, ROW_POOL_SIZE do
		local row = CreateFrame("Button", nil, body)
		row:SetHeight(ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row._poolIndex = i

		local bg = row:CreateTexture(nil, "BACKGROUND", nil, 0)
		bg:SetAllPoints(row)
		row.bg = bg

		local selBar = row:CreateTexture(nil, "ARTWORK", nil, 1)
		selBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
		selBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
		selBar:SetWidth(3)
		selBar:Hide()
		row.selBar = selBar

		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(row)
		hl:SetColorTexture(1, 1, 1, 0.06)
		row.hl = hl

		local rule = row:CreateTexture(nil, "BORDER", nil, 0)
		rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
		rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
		rule:SetHeight(1)
		row.rule = rule

		row.cells = {}
		for idx, col in ipairs(columns) do
			if col.kind == "item" then
				local cell = CreateFrame("Frame", nil, row)
				cell:SetHeight(ROW_HEIGHT)
				local ic = cell:CreateTexture(nil, "ARTWORK")
				ic:SetSize(18, 18)
				ic:SetPoint("LEFT", cell, "LEFT", 4, 0)
				if ic.SetTexCoord then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
				local fs = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				fs:SetPoint("LEFT", ic, "RIGHT", 6, 0)
				fs:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
				fs:SetJustifyH("LEFT")
				if fs.SetWordWrap then fs:SetWordWrap(false) end
				if fs.SetMaxLines then fs:SetMaxLines(1) end
				applyFont(fs, 11, "regular")
				cell.icon = ic
				cell.fs = fs
				row.cells[idx] = cell
			elseif col.kind == "action" then
				local cell = CreateFrame("Frame", nil, row)
				cell:SetHeight(ROW_HEIGHT)
				local btn = createButton(cell, "Buy", max(64, (col.width or 84) - 8), ROW_HEIGHT - 6, {
					variant = "primary",
					fontSize = 11,
					weight = "semibold",
				})
				btn:SetPoint("CENTER", cell, "CENTER", 0, 0)
				btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				-- Strictly synchronous OnClick handler for WoW Forever protected AH calls.
				btn:SetScript("OnClick", function(self, mouseButton)
					local deal = row._deal
					if deal and type(opts.onActionClick) == "function" then
						opts.onActionClick(deal, mouseButton, row, self)
					end
				end)
				btn:HookScript("OnEnter", function(self)
					if row._deal and type(opts.onActionTooltip) == "function" then
						opts.onActionTooltip(self, row._deal)
					end
				end)
				btn:HookScript("OnLeave", function()
					if _G.GameTooltip then _G.GameTooltip:Hide() end
				end)
				cell.btn = btn
				row.cells[idx] = cell
			else
				local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				fs:SetJustifyH(col.align or "LEFT")
				if fs.SetWordWrap then fs:SetWordWrap(false) end
				if fs.SetMaxLines then fs:SetMaxLines(1) end
				applyFont(fs, 11, col.bold and "semibold" or "regular")
				row.cells[idx] = fs
			end
		end

		row:SetScript("OnClick", function(self, mouseButton)
			local deal = self._deal
			if not deal then return end
			if shiftDown() then
				local _, link = getDealItemVisual(deal)
				if link then
					if type(_G.ChatEdit_InsertLink) == "function" then
						pcall(_G.ChatEdit_InsertLink, link)
						return
					end
				end
			end
			if type(opts.onRowClick) == "function" then
				opts.onRowClick(deal, mouseButton, self)
			end
		end)
		row:SetScript("OnEnter", function(self)
			if self._deal and type(opts.onRowTooltip) == "function" then
				opts.onRowTooltip(self, self._deal)
			end
		end)
		row:SetScript("OnLeave", function()
			if _G.GameTooltip then _G.GameTooltip:Hide() end
		end)

		row:Hide()
		tbl.rows[i] = row
	end

	function tbl:Layout()
		local bodyW = (body.GetWidth and body:GetWidth()) or 0
		if bodyW < 200 then
			local cw = (container.GetWidth and container:GetWidth()) or 0
			bodyW = max(560, cw - SCROLLBAR_WIDTH - 14)
		end
		local bodyH = (body.GetHeight and body:GetHeight()) or 0
		if bodyH < ROW_HEIGHT then
			bodyH = ROW_POOL_SIZE * ROW_HEIGHT
		end
		local vis = clamp(floor(bodyH / ROW_HEIGHT), 1, ROW_POOL_SIZE)
		self.visibleCount = vis

		local fixedTotal = 0
		local flexIdx = 1
		for idx, col in ipairs(self.columns) do
			if col.flex then
				flexIdx = idx
			else
				fixedTotal = fixedTotal + (col.width or 76)
			end
		end
		local flexW = max(140, bodyW - fixedTotal)

		local x = 0
		for idx, col in ipairs(self.columns) do
			local w = col.flex and flexW or (col.width or 76)
			self.colX[idx] = x
			self.colW[idx] = w
			local hb = self.headers[idx]
			hb:ClearAllPoints()
			hb:SetPoint("TOPLEFT", header, "TOPLEFT", x + 4, 0)
			hb:SetWidth(w)
			x = x + w
		end

		for i = 1, ROW_POOL_SIZE do
			local row = self.rows[i]
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
			row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -((i - 1) * ROW_HEIGHT))
			for idx, col in ipairs(self.columns) do
				local cell = row.cells[idx]
				local cx = self.colX[idx]
				local cw = self.colW[idx]
				if col.kind == "item" or col.kind == "action" then
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", row, "TOPLEFT", cx, 0)
					cell:SetWidth(cw)
					if col.kind == "action" and cell.btn then
						cell.btn:SetWidth(max(62, cw - 8))
					end
				else
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", row, "LEFT", cx + 4, 0)
					cell:SetWidth(max(12, cw - 8))
				end
			end
		end

		self:UpdateScrollBounds()
	end

	function tbl:UpdateScrollBounds()
		local total = #self.data
		local maxOffset = max(0, total - self.visibleCount)
		self.scrollOffset = clamp(self.scrollOffset, 0, maxOffset)
		self._settingSlider = true
		if scrollBar.SetMinMaxValues then
			scrollBar:SetMinMaxValues(0, maxOffset)
		end
		if scrollBar.SetValue then
			scrollBar:SetValue(self.scrollOffset)
		end
		self._settingSlider = false
		if maxOffset > 0 then
			scrollBar:Show()
		else
			scrollBar:Hide()
		end
	end

	function tbl:ResetScroll()
		self.scrollOffset = 0
		self:UpdateScrollBounds()
	end

	function tbl:PaintHeaders(sortState)
		local pal = getPal()
		for idx, hb in ipairs(self.headers) do
			local col = hb.col
			local text = col.label
			if sortState and sortState.col == col.key then
				text = text .. (sortState.asc and " ^" or " v")
				setFsColor(hb.fs, pal.text)
			else
				setFsColor(hb.fs, pal.textSecondary)
			end
			hb.fs:SetText(text)
		end
	end

	function tbl:PaintChrome()
		local pal = getPal()
		paintSurfaceCard(self.cardEntry, pal)
		local style = getTableStyle()
		local custom = isCustomSkin() and (style == "t5_ruled" or style == "t5_well" or style == "t3_strips")
		local T2 = getTheme()
		if custom and T2 and T2.GetSkinAsset and T2.GetSkin then
			local assetName = (style == "t3_strips") and "panel_hdr" or "header_bg"
			headerBg:SetTexture(T2.GetSkinAsset(T2.GetSkin(), assetName))
			headerBg:SetVertexColor(1, 1, 1, 0.94)
			headerBg:Show()
		else
			headerBg:Hide()
		end
		for i = 1, ROW_POOL_SIZE do
			local row = self.rows[i]
			if row.hl and row.hl.SetColorTexture then
				if pal.mode == "light" then
					row.hl:SetColorTexture(0, 0, 0, 0.04)
				else
					row.hl:SetColorTexture(1, 1, 1, 0.055)
				end
			end
			if row.rule and row.rule.SetColorTexture then
				local sep = pal.separator
				row.rule:SetColorTexture(sep[1], sep[2], sep[3], (sep[4] or 0.4) * 0.45)
			end
			if row.selBar and row.selBar.SetColorTexture then
				local ac = pal.accentBlue
				row.selBar:SetColorTexture(ac[1], ac[2], ac[3], 1)
			end
		end
	end

	function tbl:Render(rowsData, sortState, emptyMsg)
		self.data = rowsData or {}
		self:PaintHeaders(sortState)
		self:UpdateScrollBounds()

		local pal = getPal()
		local total = #self.data
		if total == 0 then
			for i = 1, ROW_POOL_SIZE do
				self.rows[i]._deal = nil
				self.rows[i]:Hide()
			end
			emptyFs:SetText(emptyMsg or "No deals found.")
			emptyFs:Show()
			return
		end
		emptyFs:Hide()

		local startIdx = self.scrollOffset
		for i = 1, ROW_POOL_SIZE do
			local row = self.rows[i]
			local dataIdx = startIdx + i
			local deal = (i <= self.visibleCount) and self.data[dataIdx] or nil
			if deal then
				row._deal = deal
				row._dataIndex = dataIdx
				local isSelected = type(opts.isSelected) == "function" and opts.isSelected(deal) or false
				if isSelected then
					local ac = pal.accentBlue
					row.bg:SetColorTexture(ac[1], ac[2], ac[3], pal.mode == "light" and 0.12 or 0.16)
					row.selBar:Show()
				elseif (dataIdx % 2) == 0 then
					if pal.mode == "light" then
						row.bg:SetColorTexture(0, 0, 0, 0.025)
					else
						row.bg:SetColorTexture(1, 1, 1, 0.025)
					end
					row.selBar:Hide()
				else
					row.bg:SetColorTexture(0, 0, 0, 0)
					row.selBar:Hide()
				end
				if type(opts.bindRow) == "function" then
					opts.bindRow(row, deal, pal)
				end
				row:Show()
			else
				row._deal = nil
				row:Hide()
			end
		end
	end

	-- Scroll events (ZERO OnUpdate!)
	scrollBar:SetScript("OnValueChanged", function(_, value)
		if tbl._settingSlider then return end
		local nextOff = floor(safeNum(value, 0) + 0.5)
		if nextOff ~= tbl.scrollOffset then
			tbl.scrollOffset = nextOff
			if type(opts.onScroll) == "function" then opts.onScroll() end
		end
	end)
	body:SetScript("OnMouseWheel", function(_, delta)
		local total = #tbl.data
		local maxOffset = max(0, total - tbl.visibleCount)
		if maxOffset <= 0 then return end
		local step = (delta > 0) and -3 or 3
		local nextOff = clamp(tbl.scrollOffset + step, 0, maxOffset)
		if nextOff ~= tbl.scrollOffset then
			tbl.scrollOffset = nextOff
			if type(opts.onScroll) == "function" then opts.onScroll() end
		end
	end)
	if container.HookScript then
		container:HookScript("OnSizeChanged", function()
			if state.built and UI.IsShown() then
				tbl:Layout()
				if type(opts.onScroll) == "function" then opts.onScroll() end
			end
		end)
	end

	state.tables[#state.tables + 1] = tbl
	return tbl
end

---------------------------------------------------------------------------------------------------
-- Sorting & Filtering
---------------------------------------------------------------------------------------------------

local function sortDeals(list, sortState, getValFn)
	if #list <= 1 then return list end
	local col = sortState.col
	local asc = sortState.asc
	table.sort(list, function(a, b)
		local va = getValFn(a, col)
		local vb = getValFn(b, col)
		if va == vb then
			local na = getDealItemVisual(a)
			local nb = getDealItemVisual(b)
			if na ~= nb then return na < nb end
			return getDealKey(a) < getDealKey(b)
		end
		if va == nil then return false end
		if vb == nil then return true end
		if type(va) == "string" or type(vb) == "string" then
			va, vb = tostring(va):lower(), tostring(vb):lower()
		end
		if asc then return va < vb else return va > vb end
	end)
	return list
end

local function gapSortValue(deal, col)
	if col == "name" then
		local n = getDealItemVisual(deal)
		return n
	elseif col == "buyQty" then return getGapBuyQty(deal)
	elseif col == "avgBuyPrice" then return getGapAvgBuy(deal)
	elseif col == "nextTierPrice" then return getGapNextTier(deal)
	elseif col == "gapPct" then return getGapPct(deal)
	elseif col == "netProfit" then return getGapNetProfit(deal)
	elseif col == "estHoursToSell" then return getGapEstHours(deal)
	elseif col == "actionState" then return resolveDealStep(deal, getActivePurchaseState())
	end
	return getGapNetProfit(deal)
end

local function vendorSortValue(deal, col)
	if col == "name" then
		local n = getDealItemVisual(deal)
		return n
	elseif col == "ahPrice" then return getVendorAhPrice(deal)
	elseif col == "vendorSell" then return getVendorSell(deal)
	elseif col == "profitPerUnit" then return getVendorProfitUnit(deal)
	elseif col == "source" then return safeStr(deal.source, "Snapshot")
	elseif col == "status" then
		local _, _, _, statusLbl = vendorActionPresentation(deal, getActivePurchaseState())
		return statusLbl
	elseif col == "actionState" then
		local lbl = vendorActionPresentation(deal, getActivePurchaseState())
		return lbl
	end
	return getVendorProfitUnit(deal)
end

local function collectGapDeals()
	local SE = getSE()
	local raw = {}
	if SE and type(SE.GetGapDeals) == "function" then
		local ok, res = pcall(SE.GetGapDeals)
		if ok and type(res) == "table" then raw = res end
	end
	local cfg = getConfig()
	local scope = normalizeGapScope(cfg.gapScope)
	local minGap = safeNum(cfg.minGapPct, 0)
	local minRoi = safeNum(cfg.minRoiPct, 0)
	local minProfit = safeNum(cfg.minProfitCopper, 0)
	local maxSpend = safeNum(cfg.maxSpendCopper, 0)
	local maxShare = safeNum(cfg.maxBuyShareDailyPct, 0)
	local minQty = safeNum(cfg.minQty, 0)
	local minSales = safeNum(cfg.minDailySales, 0)

	local ps = getActivePurchaseState()
	local out = {}
	for _, d in ipairs(raw) do
		if type(d) == "table" then
			local isItem = (d.kind == "item")
			local pass = true
			if scope == "commodities" and isItem then pass = false end
			if scope == "items" and not isItem then pass = false end

			local boughtListings = safeNum(d.boughtListings, 0)
			local step = resolveDealStep(d, ps)
			local preserveInProgress = (boughtListings > 0) or (step ~= "ready")

			if pass and not preserveInProgress then
				local qty = getGapBuyQty(d)
				local totalCost = safeNum(d.totalCost, qty * getGapAvgBuy(d))
				local netProfit = getGapNetProfit(d)
				local gapPct = getGapPct(d)
				local roiPct = getGapRoiPct(d)
				local dailySold = getGapDailySold(d)
				if not isItem and minQty > 0 and qty > 0 and qty < minQty then pass = false end
				if minGap > 0 and gapPct < minGap then pass = false end
				if minRoi > 0 and roiPct > 0 and roiPct < minRoi then pass = false end
				if minProfit > 0 and netProfit < minProfit then pass = false end
				if maxSpend > 0 and totalCost > maxSpend then pass = false end
				if minSales > 0 and dailySold > 0 and dailySold < minSales then pass = false end
				if maxShare > 0 and dailySold > 0 then
					local shareCap = isItem
						and max(1, floor(dailySold * (maxShare / 100) + 0.5))
						or floor(dailySold * (maxShare / 100))
					if qty > shareCap then pass = false end
				end
			end
			if pass then
				out[#out + 1] = d
			end
		end
	end
	return sortDeals(out, state.gapSort, gapSortValue)
end

local function collectVendorDeals()
	local SE = getSE()
	local raw = {}
	if SE and type(SE.GetVendorDeals) == "function" then
		local ok, res = pcall(SE.GetVendorDeals)
		if ok and type(res) == "table" then raw = res end
	end
	local cfg = getConfig()
	local minProfit = safeNum(cfg.vendorMinProfitCopper, 0)
	local includeComm = cfg.vendorIncludeCommodities ~= false

	local out = {}
	for _, d in ipairs(raw) do
		if type(d) == "table" then
			local pUnit = getVendorProfitUnit(d)
			local pass = (pUnit >= minProfit)
			if not includeComm and (d.isCommodity == true or d.kind == "commodity") then
				pass = false
			end
			if pass then
				out[#out + 1] = d
			end
		end
	end
	return sortDeals(out, state.vendorSort, vendorSortValue)
end

---------------------------------------------------------------------------------------------------
-- Expandable Bottom Price Ladder Panel (Gap Sniper)
---------------------------------------------------------------------------------------------------

local function buildLadderPanel(parent, onClose)
	local frame, cardEntry = createSurfaceCard(parent, "glass_r10", "cardAltBg")
	frame:SetHeight(LADDER_PANEL_HEIGHT)
	frame:Hide()

	-- Top header line
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
	if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

	local titleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleFs:SetPoint("LEFT", icon, "RIGHT", 7, 0)
	titleFs:SetJustifyH("LEFT")
	if titleFs.SetWordWrap then titleFs:SetWordWrap(false) end
	applyFont(titleFs, 12, "semibold")
	registerThemedFs(titleFs, "text")

	local closeBtn = createButton(frame, "", 20, 20, {
		icon = "close",
		iconSize = 10,
		variant = "ghost",
		pill = true,
	})
	closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -7)
	closeBtn:SetScript("OnClick", function()
		if type(onClose) == "function" then onClose() end
	end)

	local subtitleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	subtitleFs:SetPoint("LEFT", titleFs, "RIGHT", 8, 0)
	subtitleFs:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
	subtitleFs:SetJustifyH("LEFT")
	if subtitleFs.SetWordWrap then subtitleFs:SetWordWrap(false) end
	if subtitleFs.SetMaxLines then subtitleFs:SetMaxLines(1) end
	applyFont(subtitleFs, 11, "regular")
	registerThemedFs(subtitleFs, "textSecondary")

	-- Economics breakdown line
	local econFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	econFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -29)
	econFs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -29)
	econFs:SetJustifyH("LEFT")
	if econFs.SetWordWrap then econFs:SetWordWrap(false) end
	if econFs.SetMaxLines then econFs:SetMaxLines(1) end
	applyFont(econFs, 11, "regular")
	registerThemedFs(econFs, "textSecondary")

	local sep = createSeparator(frame)
	sep:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -45)
	sep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -45)

	-- Fixed reusable ladder tier rows (zero dynamic creation!)
	local tierRows = {}
	for i = 1, LADDER_ROW_COUNT do
		local r = CreateFrame("Frame", nil, frame)
		r:SetHeight(LADDER_ROW_HEIGHT)
		r:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -(49 + (i - 1) * (LADDER_ROW_HEIGHT + 1)))
		r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -(49 + (i - 1) * (LADDER_ROW_HEIGHT + 1)))

		local rowBg = r:CreateTexture(nil, "BACKGROUND", nil, 0)
		rowBg:SetAllPoints(r)
		r.bg = rowBg

		local barTrack = r:CreateTexture(nil, "BACKGROUND", nil, 1)
		barTrack:SetPoint("LEFT", r, "LEFT", 280, 0)
		barTrack:SetPoint("RIGHT", r, "RIGHT", -96, 0)
		barTrack:SetHeight(6)
		r.barTrack = barTrack

		local barFill = r:CreateTexture(nil, "ARTWORK", nil, 1)
		barFill:SetPoint("LEFT", barTrack, "LEFT", 0, 0)
		barFill:SetHeight(6)
		barFill:SetWidth(4)
		r.barFill = barFill

		local tagFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tagFs:SetPoint("LEFT", r, "LEFT", 4, 0)
		tagFs:SetWidth(48)
		tagFs:SetJustifyH("LEFT")
		applyFont(tagFs, 10, "semibold")
		r.tagFs = tagFs

		local priceFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		priceFs:SetPoint("LEFT", tagFs, "RIGHT", 4, 0)
		priceFs:SetWidth(94)
		priceFs:SetJustifyH("RIGHT")
		applyFont(priceFs, 11, "regular")
		r.priceFs = priceFs

		local qtyFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		qtyFs:SetPoint("LEFT", priceFs, "RIGHT", 10, 0)
		qtyFs:SetWidth(112)
		qtyFs:SetJustifyH("LEFT")
		applyFont(qtyFs, 11, "regular")
		r.qtyFs = qtyFs

		local noteFs = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		noteFs:SetPoint("RIGHT", r, "RIGHT", -4, 0)
		noteFs:SetWidth(88)
		noteFs:SetJustifyH("RIGHT")
		applyFont(noteFs, 10, "regular")
		r.noteFs = noteFs

		r:Hide()
		tierRows[i] = r
	end

	local ladder = {
		frame = frame,
		cardEntry = cardEntry,
		icon = icon,
		titleFs = titleFs,
		subtitleFs = subtitleFs,
		econFs = econFs,
		tierRows = tierRows,
	}

	function ladder:Render(deal)
		if type(deal) ~= "table" then
			frame:Hide()
			return
		end
		local pal = getPal()
		local T = getTheme()
		local name, _, quality, ic = getDealItemVisual(deal)
		icon:SetTexture(ic or (T and T.ASSETS and T.ASSETS.icon_coins) or "Interface\\Icons\\INV_Misc_QuestionMark")
		titleFs:SetText(name)
		setFsColor(titleFs, qualityColorForDeal(quality, pal))

		local buyQty = getGapBuyQty(deal)
		local avgBuy = getGapAvgBuy(deal)
		local totalCost = safeNum(deal.totalCost, buyQty * avgBuy)
		local nextTier = getGapNextTier(deal)
		local relist = getGapRelistPrice(deal)
		local ahCut = safeNum(deal.ahCut, 0)
		local SE = getSE()
		local cutRate = safeNum(deal.ahCutRate) or (SE and SE.GetDynamicAuctionCut and SE.GetDynamicAuctionCut()) or 0.05
		local deposit = safeNum(deal.deposit, 0)
		local depHours = safeNum(deal.depositHours, 8)
		local netProfit = getGapNetProfit(deal)
		local roiPct = getGapRoiPct(deal)
		local estHrs = getGapEstHours(deal)
		local dailySold = getGapDailySold(deal)

		local isItemDeal = (deal.kind == "item")
		if isItemDeal then
			local totalLots = max(1, getGapListingCount(deal))
			local rem = getRemainingItemListings(deal)
			local bought = safeNum(deal.boughtListings, 0)
			local lotText
			if deal.needsLiveScan == true or type(deal.buyQueue) ~= "table" then
				lotText = format("%d %s, needs Check", totalLots, totalLots == 1 and "lot" or "lots")
			elseif bought > 0 or rem ~= totalLots then
				lotText = format("%d/%d lots left", rem, totalLots)
			else
				lotText = format("%d %s", totalLots, totalLots == 1 and "lot" or "lots")
			end
			subtitleFs:SetText(format("Price Ladder · Equipment (%sx, %s @ avg %s -> Total %s)", formatInt(buyQty), lotText, formatMoney(avgBuy), formatMoney(totalCost)))
		else
			subtitleFs:SetText(format("Price Ladder · Commodity (Buy %s @ avg %s -> Total %s)", formatInt(buyQty), formatMoney(avgBuy), formatMoney(totalCost)))
		end

		local capNote = ""
		if nextTier > 0 and relist > 0 and relist < (nextTier - 1) then
			capNote = " [Ref Cap]"
		end
		econFs:SetText(format(
			"Relist: %s%s  |  AH Cut (%d%%): -%s  |  Deposit Risk (%dh): %s  |  Net: %s (%s ROI)  |  Est. Sell: %s (%.1f/d)",
			formatMoney(relist),
			capNote,
			floor(cutRate * 100 + 0.5),
			formatMoney(ahCut),
			depHours,
			formatMoney(deposit),
			formatMoney(netProfit, true),
			formatPercent(roiPct),
			formatHours(estHrs),
			dailySold
		))

		-- Build tier display list (from deal.ladder or synthesized fallback from avgBuy/nextTier)
		local tiers = type(deal.ladder) == "table" and deal.ladder or nil
		if not tiers or #tiers == 0 then
			tiers = {
				{ unitPrice = avgBuy, quantity = buyQty, cumulativeQty = buyQty, isBuy = true },
				{ unitPrice = nextTier, quantity = safeNum(deal.nextTierQty, 1), isWall = true },
			}
		end

		local maxQty = 1
		local count = min(#tiers, LADDER_ROW_COUNT)
		for i = 1, count do
			local q = safeNum(tiers[i].quantity or tiers[i].qty, 0)
			if q > maxQty then maxQty = q end
		end

		local trackW = max(60, ((frame.GetWidth and frame:GetWidth()) or 680) - 396)
		local cum = 0
		for i = 1, LADDER_ROW_COUNT do
			local r = tierRows[i]
			local td = tiers[i]
			if td then
				local unitP = safeNum(td.unitPrice or td.price, 0)
				local tQty = safeNum(td.quantity or td.qty, 0)
				local tLots = safeNum(td.listingCount or td.listings or td.lots)
				local buyPart = safeNum(td.buyQty)
				cum = safeNum(td.cumulativeQty or td.cumQty) or (cum + tQty)
				local isWall = (td.isWall == true) or (td.wall == true) or (td.role == "wall")
				local isBuy = (not isWall) and ((td.isBuy == true) or (td.buy == true) or (td.role == "buy") or (buyPart and buyPart > 0))

				if isBuy then
					local gc = pal.accentGreen
					r.bg:SetColorTexture(gc[1], gc[2], gc[3], pal.mode == "light" and 0.10 or 0.12)
					r.tagFs:SetText("[BUY]")
					setFsColor(r.tagFs, pal.accentGreen)
					r.barFill:SetColorTexture(gc[1], gc[2], gc[3], 0.85)
					r.noteFs:SetText(buyPart and buyPart < tQty and format("Take %d/%d", buyPart, tQty) or (isItemDeal and "Buy Lot" or "Sweep"))
					setFsColor(r.noteFs, pal.accentGreen)
				elseif isWall then
					local oc = pal.accentOrange
					r.bg:SetColorTexture(oc[1], oc[2], oc[3], pal.mode == "light" and 0.12 or 0.14)
					r.tagFs:SetText("[WALL]")
					setFsColor(r.tagFs, pal.accentOrange)
					r.barFill:SetColorTexture(oc[1], oc[2], oc[3], 0.85)
					r.noteFs:SetText("Cliff Wall")
					setFsColor(r.noteFs, pal.accentOrange)
				else
					r.bg:SetColorTexture(0, 0, 0, 0)
					r.tagFs:SetText("TIER")
					setFsColor(r.tagFs, pal.textMuted)
					local bc = pal.textMuted
					r.barFill:SetColorTexture(bc[1], bc[2], bc[3], 0.45)
					r.noteFs:SetText("")
				end

				r.priceFs:SetText(formatMoney(unitP))
				setFsColor(r.priceFs, pal.text)
				if isItemDeal and tLots and tLots > 0 then
					local lotN = floor(tLots)
					r.qtyFs:SetText(format("x%s · %d %s", formatInt(tQty), lotN, lotN == 1 and "lot" or "lots"))
				else
					r.qtyFs:SetText(format("x%s  (cum %s)", formatInt(tQty), formatInt(cum)))
				end
				setFsColor(r.qtyFs, pal.textSecondary)

				local mt = pal.mode == "light" and { 0, 0, 0, 0.08 } or { 1, 1, 1, 0.10 }
				r.barTrack:SetColorTexture(mt[1], mt[2], mt[3], mt[4])
				local frac = clamp(tQty / maxQty, 0.06, 1)
				r.barFill:SetWidth(max(4, floor(trackW * frac + 0.5)))

				r:Show()
			else
				r:Hide()
			end
		end

		frame:Show()
	end

	return ladder
end

---------------------------------------------------------------------------------------------------
-- Sub-View 1: Gap Sniper (sniper_gap)
---------------------------------------------------------------------------------------------------

local GAP_COLUMNS = {
	{ key = "name",           label = "Item",       flex = true,  align = "LEFT",   kind = "item",   hint = "Item name. Click row to expand Price Ladder. Shift-click to link in chat." },
	{ key = "buyQty",         label = "Buy Qty",    width = 84,   align = "RIGHT",  hint = "Total units (and lots for equipment) to buy across underpriced tiers." },
	{ key = "avgBuyPrice",    label = "Avg Buy",    width = 86,   align = "RIGHT",  hint = "Weighted average purchase price per unit." },
	{ key = "nextTierPrice",  label = "Next Tier",  width = 86,   align = "RIGHT",  hint = "Resale cliff wall unit price above the bought tiers." },
	{ key = "gapPct",         label = "Gap %",      width = 58,   align = "RIGHT",  hint = "Percentage gap between average buy price and relist price." },
	{ key = "netProfit",      label = "Net Profit", width = 94,   align = "RIGHT",  bold = true, hint = "Estimated net profit after dynamic AH cut (5% or 15%); Forever deposit is refunded on sale." },
	{ key = "estHoursToSell", label = "Est. Sell",  width = 64,   align = "RIGHT",  hint = "Estimated hours to sell buyQty based on multi-source daily sales velocity." },
	{ key = "actionState",    label = "Action",     width = 88,   align = "CENTER", kind = "action", sortable = false, hint = "Left-click: Buy -> Confirm (commodities) or Buy (N) PlaceBid (equipment). Right-click: Cancel." },
}

local function buildGapView(parent)
	local view = CreateFrame("Frame", nil, parent)
	view:SetAllPoints(parent)

	-- 1. Top Action & Status Card
	local topCard = createSurfaceCard(view, "glass_r10", "cardBg")
	topCard:SetHeight(58)
	topCard:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	topCard:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)

	local scanBtn = createButton(topCard, "Start Gap Scan", 132, 26, {
		variant = "primary",
		icon = "bolt",
		iconSize = 13,
		fontSize = 12,
		weight = "semibold",
	})
	scanBtn:SetPoint("LEFT", topCard, "LEFT", 12, 0)

	local snapBtn = createButton(topCard, "Scan Snapshot", 118, 26, {
		variant = "secondary",
		icon = "refresh",
		iconSize = 12,
		fontSize = 11,
	})
	snapBtn:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)

	local statusPill = createBadgePill(topCard, "Ready", "neutral", { height = 20, fontSize = 11 })
	statusPill.frame:SetPoint("TOPRIGHT", topCard, "TOPRIGHT", -12, -9)

	local progressFs = topCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	progressFs:SetPoint("TOPLEFT", snapBtn, "TOPRIGHT", 14, 7)
	progressFs:SetPoint("RIGHT", statusPill.frame, "LEFT", -10, 0)
	progressFs:SetJustifyH("LEFT")
	if progressFs.SetWordWrap then progressFs:SetWordWrap(false) end
	if progressFs.SetMaxLines then progressFs:SetMaxLines(1) end
	applyFont(progressFs, 11, "regular")
	registerThemedFs(progressFs, "textSecondary")
	progressFs:SetText("Scanned 0 / 0 | Deals: 0 | AH Cut: 5%")

	local function syncGapSnapshotLayout()
		local showSnap = hasSnapshotMode()
		if showSnap then
			snapBtn:Show()
			if progressFs.ClearAllPoints then progressFs:ClearAllPoints() end
			progressFs:SetPoint("TOPLEFT", snapBtn, "TOPRIGHT", 14, 7)
			progressFs:SetPoint("RIGHT", statusPill.frame, "LEFT", -10, 0)
		else
			snapBtn:Hide()
			if progressFs.ClearAllPoints then progressFs:ClearAllPoints() end
			progressFs:SetPoint("TOPLEFT", scanBtn, "TOPRIGHT", 14, 7)
			progressFs:SetPoint("RIGHT", statusPill.frame, "LEFT", -10, 0)
		end
	end
	syncGapSnapshotLayout()

	local progressBar = createProgressBar(topCard, 6, { value = 0 })
	progressBar.frame:SetPoint("TOPLEFT", progressFs, "BOTTOMLEFT", 0, -7)
	progressBar.frame:SetPoint("RIGHT", topCard, "RIGHT", -12, 0)

	-- 2. Filter Strip Card (2 clean rows, persisted in MerchantMasterDB.sniper)
	local filterCard = createSurfaceCard(view, "glass_r10", "cardBg")
	filterCard:SetHeight(60)
	filterCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -SECTION_GAP)
	filterCard:SetPoint("TOPRIGHT", topCard, "BOTTOMRIGHT", 0, -SECTION_GAP)

	local filters = {}
	local gapTable

	local function refreshAfterFilter()
		if gapTable then gapTable:ResetScroll() end
		if UI.IsShown() then UI.Refresh("filter_changed") end
	end

	-- Row 1: Economics + Scope Toggle Pill
	filters.minGapPct = createNumericField(filterCard, "Min Gap %", 44, "Minimum percentage price gap between avg buy and relist price.", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = clamp(v, 0, 500)
			updateConfig("minGapPct", v)
			refreshAfterFilter()
		else
			box:SetText(tostring(getConfig().minGapPct))
		end
	end)
	filters.minGapPct.wrap:SetPoint("TOPLEFT", filterCard, "TOPLEFT", 12, -7)

	filters.minRoiPct = createNumericField(filterCard, "Min ROI %", 44, "Minimum net return on investment after dynamic AH cut (deposit refunded on sale).", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = clamp(v, 0, 1000)
			updateConfig("minRoiPct", v)
			refreshAfterFilter()
		else
			box:SetText(tostring(getConfig().minRoiPct))
		end
	end)
	filters.minRoiPct.wrap:SetPoint("LEFT", filters.minGapPct.wrap, "RIGHT", 10, 0)

	filters.minProfitGold = createNumericField(filterCard, "Min Profit (g)", 50, "Minimum net profit in gold (e.g. 10 = 10g).", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = clamp(v, 0, 999999)
			updateConfig("minProfitCopper", floor(v * 10000 + 0.5))
			refreshAfterFilter()
		else
			box:SetText(tostring(floor((getConfig().minProfitCopper or 0) / 10000 + 0.5)))
		end
	end)
	filters.minProfitGold.wrap:SetPoint("LEFT", filters.minRoiPct.wrap, "RIGHT", 10, 0)

	filters.maxSpendGold = createNumericField(filterCard, "Max Spend (g)", 54, "Maximum total gold to invest in a single gap flip.", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = clamp(v, 1, 9999999)
			updateConfig("maxSpendCopper", floor(v * 10000 + 0.5))
			refreshAfterFilter()
		else
			box:SetText(tostring(floor((getConfig().maxSpendCopper or 0) / 10000 + 0.5)))
		end
	end)
	filters.maxSpendGold.wrap:SetPoint("LEFT", filters.minProfitGold.wrap, "RIGHT", 10, 0)

	local scopeBtn = createButton(filterCard, GAP_SCOPE_LABELS.all, 108, 22, {
		variant = "primary",
		pill = true,
		fontSize = 11,
		weight = "semibold",
	})
	scopeBtn:SetPoint("TOPRIGHT", filterCard, "TOPRIGHT", -12, -6)
	scopeBtn:SetScript("OnClick", function()
		local cur = normalizeGapScope(getConfig().gapScope)
		local nxt = nextGapScope(cur)
		updateConfig("gapScope", nxt)
		refreshAfterFilter()
	end)
	scopeBtn:HookScript("OnEnter", function(self)
		if not _G.GameTooltip then return end
		local cur = normalizeGapScope(getConfig().gapScope)
		_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
		_G.GameTooltip:ClearLines()
		_G.GameTooltip:AddLine("Scan & Filter Scope: " .. (GAP_SCOPE_LABELS[cur] or "All AH Items"), 1, 1, 1)
		_G.GameTooltip:AddLine("Click to cycle: All AH Items -> Commodities -> Equipment.", 0.85, 0.85, 0.90, true)
		_G.GameTooltip:AddLine(
			hasSnapshotMode()
				and "Applies to 2-Stage Gap Scan, Snapshot preview, and visible deals."
				or "Applies to 2-Stage Gap Scan and visible deals.",
			0.65, 0.65, 0.72, true
		)
		_G.GameTooltip:Show()
	end)
	scopeBtn:HookScript("OnLeave", function()
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)

	local scopeLbl = filterCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	scopeLbl:SetPoint("RIGHT", scopeBtn, "LEFT", -6, 0)
	scopeLbl:SetJustifyH("RIGHT")
	if scopeLbl.SetWordWrap then scopeLbl:SetWordWrap(false) end
	applyFont(scopeLbl, 11, "regular")
	scopeLbl:SetText("Scope")
	registerThemedFs(scopeLbl, "textSecondary")
	filters.scopeBtn = scopeBtn
	filters.scopeLabel = scopeLbl

	-- Row 2: Liquidity & Anti-Bait
	filters.maxBuyShareDailyPct = createNumericField(filterCard, "Max % Daily Sales", 42, "Liquidity cap: never buy more than this % of estimated daily sales.", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = clamp(v, 1, 500)
			updateConfig("maxBuyShareDailyPct", v)
			refreshAfterFilter()
		else
			box:SetText(tostring(getConfig().maxBuyShareDailyPct))
		end
	end)
	filters.maxBuyShareDailyPct.wrap:SetPoint("TOPLEFT", filterCard, "TOPLEFT", 12, -33)

	filters.minDailySales = createNumericField(filterCard, "Min Sales/Day", 42, "Minimum estimated daily sales velocity to consider an item.", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = clamp(v, 0, 100000)
			updateConfig("minDailySales", v)
			refreshAfterFilter()
		else
			box:SetText(tostring(getConfig().minDailySales))
		end
	end)
	filters.minDailySales.wrap:SetPoint("LEFT", filters.maxBuyShareDailyPct.wrap, "RIGHT", 14, 0)

	filters.minQty = createNumericField(filterCard, "Min Qty", 38, "Anti-bait guard for commodities: minimum units below the wall to ignore 1-unit bait traps (equipment allows 1).", function(txt, box)
		local v = safeNum(txt)
		if v then
			v = max(1, floor(v))
			updateConfig("minQty", v)
			refreshAfterFilter()
		else
			box:SetText(tostring(getConfig().minQty))
		end
	end)
	filters.minQty.wrap:SetPoint("LEFT", filters.minDailySales.wrap, "RIGHT", 14, 0)

	filters.fastSellersFirst = createToggleField(filterCard, "Fast Sellers First", "Prioritize highest daily-velocity items first during scans.", function(on)
		updateConfig("fastSellersFirst", on)
		refreshAfterFilter()
	end)
	filters.fastSellersFirst:SetPoint("LEFT", filters.minQty.wrap, "RIGHT", 18, 0)

	-- 3. Expandable Bottom Price Ladder Panel
	local ladder

	local function anchorGapTable()
		gapTable.container:ClearAllPoints()
		gapTable.container:SetPoint("TOPLEFT", filterCard, "BOTTOMLEFT", 0, -SECTION_GAP)
		gapTable.container:SetPoint("TOPRIGHT", filterCard, "BOTTOMRIGHT", 0, -SECTION_GAP)
		if state.ladderExpanded and state.selectedGapDeal then
			gapTable.container:SetPoint("BOTTOMLEFT", ladder.frame, "TOPLEFT", 0, SECTION_GAP)
			gapTable.container:SetPoint("BOTTOMRIGHT", ladder.frame, "TOPRIGHT", 0, SECTION_GAP)
		else
			gapTable.container:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
			gapTable.container:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
		end
	end

	ladder = buildLadderPanel(view, function()
		state.ladderExpanded = false
		state.selectedGapKey = nil
		state.selectedGapDeal = nil
		ladder.frame:Hide()
		anchorGapTable()
		gapTable:Layout()
		UI.Refresh("close_ladder")
	end)
	ladder.frame:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
	ladder.frame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)

	-- 4. Sortable Deals Table
	gapTable = createPooledTable(view, GAP_COLUMNS, {
		onHeaderClick = function(colKey)
			if state.gapSort.col == colKey then
				state.gapSort.asc = not state.gapSort.asc
			else
				state.gapSort.col = colKey
				state.gapSort.asc = (colKey == "name" or colKey == "estHoursToSell")
			end
			if gapTable then gapTable:ResetScroll() end
			UI.Refresh("gap_sort")
		end,
		isSelected = function(deal)
			return state.ladderExpanded and state.selectedGapKey ~= nil and getDealKey(deal) == state.selectedGapKey
		end,
		onRowClick = function(deal)
			local key = getDealKey(deal)
			if state.ladderExpanded and state.selectedGapKey == key then
				state.ladderExpanded = false
				state.selectedGapKey = nil
				state.selectedGapDeal = nil
				ladder.frame:Hide()
			else
				state.ladderExpanded = true
				state.selectedGapKey = key
				state.selectedGapDeal = deal
				ladder:Render(deal)
			end
			anchorGapTable()
			gapTable:Layout()
			UI.Refresh("select_gap_row")
		end,
		-- Strictly synchronous OnClick invocation for protected AH calls!
		onActionClick = function(deal, mouseButton)
			local SE = getSE()
			if not SE then
				state.statusOverride = "Engine Missing"
				state.statusMessage = "SniperEngine not loaded."
				state.statusVariant = "warning"
				UI.Refresh("no_engine")
				return
			end
			if mouseButton == "RightButton" then
				if type(SE.CancelActivePurchase) == "function" then
					SE.CancelActivePurchase("Cancelled by user.")
				elseif type(SE.CancelPurchase) == "function" then
					SE.CancelPurchase(deal)
				elseif type(SE.HandleRowAction) == "function" then
					SE.HandleRowAction(deal, "cancel")
				end
			else
				if type(SE.HandleRowAction) == "function" then
					local okAct, errCode = SE.HandleRowAction(deal)
					if okAct == false then
						local engMsg = (type(SE.scan) == "table" and safeStr(SE.scan.statusText, "")) or ""
						local shortMsg, fullMsg = describeBlockedReason(errCode, engMsg)
						state.statusOverride = shortMsg
						state.statusMessage = fullMsg
						state.statusVariant = "warning"
					else
						state.statusOverride = nil
						state.statusMessage = nil
					end
				end
			end
			UI.Refresh("gap_action")
		end,
		onActionTooltip = function(owner, deal)
			if not _G.GameTooltip then return end
			local ps = getActivePurchaseState()
			local lbl, _, _, step = gapActionPresentation(deal, ps)
			_G.GameTooltip:SetOwner(owner, "ANCHOR_TOP")
			_G.GameTooltip:ClearLines()
			_G.GameTooltip:AddLine("Gap Action: " .. lbl, 1, 1, 1)
			if deal.kind == "item" then
				local rem = getRemainingItemListings(deal)
				if step == "checking" then
					_G.GameTooltip:AddLine("Checking live Auction House listings for exact buyout and auctionID...", 0.85, 0.85, 0.90, true)
				elseif step == "unavailable" then
					_G.GameTooltip:AddLine("No qualifying listings remain on the Auction House.", 1.0, 0.45, 0.45, true)
				elseif step == "needs_live_scan" or deal.needsLiveScan == true or type(deal.buyQueue) ~= "table" then
					_G.GameTooltip:AddLine("Snapshot preview: Left-click to Check live Auction House listings before buying.", 0.85, 0.85, 0.90, true)
				elseif step == "buying" or step == "confirming" or step == "purchasing" then
					_G.GameTooltip:AddLine("Submitting PlaceBid buyout on Auction House...", 0.85, 0.85, 0.90, true)
				elseif step == "bought" or rem <= 0 then
					_G.GameTooltip:AddLine("All cheap listings up to target wall purchased.", 0.30, 0.85, 0.45, true)
				elseif rem > 1 then
					_G.GameTooltip:AddLine(format("Left-click: Buy next cheap listing via PlaceBid (%d listings remaining until target wall).", rem), 0.30, 0.85, 0.45, true)
					_G.GameTooltip:AddLine("Right-click: Cancel in-flight purchase.", 1.0, 0.58, 0.25, true)
				else
					_G.GameTooltip:AddLine("Left-click: Buy cheap listing via PlaceBid on Auction House.", 0.30, 0.85, 0.45, true)
				end
			elseif step == "awaiting_confirm" or step == "confirm" then
				_G.GameTooltip:AddLine("Left-click: Confirm commodity purchase on AH.", 0.30, 0.85, 0.45, true)
				_G.GameTooltip:AddLine("Right-click: Cancel active quote.", 1.0, 0.58, 0.25, true)
			elseif step == "quoting" then
				_G.GameTooltip:AddLine("Waiting for COMMODITY_PRICE_UPDATED quote...", 0.85, 0.85, 0.90, true)
				_G.GameTooltip:AddLine("Right-click: Cancel quote.", 1.0, 0.58, 0.25, true)
			else
				_G.GameTooltip:AddLine("Left-click: Request live AH commodity quote (2-step safe buy).", 0.85, 0.85, 0.90, true)
			end
			_G.GameTooltip:Show()
		end,
		onRowTooltip = function(owner, deal)
			if not _G.GameTooltip then return end
			_G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			_G.GameTooltip:ClearLines()
			local id = safeNum(deal.itemID, 0)
			local name, link = getDealItemVisual(deal)
			if link and _G.GameTooltip.SetHyperlink then
				pcall(_G.GameTooltip.SetHyperlink, _G.GameTooltip, link)
			elseif id > 0 and _G.GameTooltip.SetItemByID then
				pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, id)
			else
				_G.GameTooltip:AddLine(name, 1, 1, 1)
			end
			_G.GameTooltip:AddLine(" ")
			if deal.kind == "item" then
				local rem = getRemainingItemListings(deal)
				local totalLots = max(1, getGapListingCount(deal))
				if deal.needsLiveScan == true or type(deal.buyQueue) ~= "table" then
					_G.GameTooltip:AddDoubleLine("Type:", format("Equipment (%d %s, needs Check)", totalLots, totalLots == 1 and "lot" or "lots"), 0.78, 0.78, 0.82, 0.95, 0.75, 0.35)
				else
					_G.GameTooltip:AddDoubleLine("Type:", format("Equipment (%d/%d lots left)", rem, totalLots), 0.78, 0.78, 0.82, 0.95, 0.75, 0.35)
				end
			else
				_G.GameTooltip:AddDoubleLine("Type:", "Commodity", 0.78, 0.78, 0.82, 0.6, 0.82, 1)
			end
			_G.GameTooltip:AddDoubleLine("Buy Qty / Total Cost:", format("%s  (%s)", formatGapQty(deal), formatMoney(safeNum(deal.totalCost, getGapBuyQty(deal) * getGapAvgBuy(deal)))), 0.78, 0.78, 0.82, 1, 1, 1)
			_G.GameTooltip:AddDoubleLine("Relist / Next Wall:", format("%s / %s", formatMoney(getGapRelistPrice(deal)), formatMoney(getGapNextTier(deal))), 0.78, 0.78, 0.82, 1, 0.82, 0.2)
			_G.GameTooltip:AddDoubleLine("Net Profit / ROI:", format("%s (%s)", formatMoney(getGapNetProfit(deal), true), formatPercent(getGapRoiPct(deal))), 0.78, 0.78, 0.82, 0.2, 0.85, 0.4)
			_G.GameTooltip:AddDoubleLine("Est. Sell / Daily:", format("%s (%.1f/d)", formatHours(getGapEstHours(deal)), getGapDailySold(deal)), 0.78, 0.78, 0.82, 0.6, 0.82, 1)
			_G.GameTooltip:AddLine("Click row to toggle Price Ladder.", 0.65, 0.65, 0.70)
			_G.GameTooltip:Show()
		end,
		bindRow = function(row, deal, pal)
			local T = getTheme()
			local name, _, quality, ic = getDealItemVisual(deal)
			local itemCell = row.cells[1]
			itemCell.icon:SetTexture(ic or (T and T.ASSETS and T.ASSETS.icon_coins) or "Interface\\Icons\\INV_Misc_QuestionMark")
			itemCell.fs:SetText(name)
			setFsColor(itemCell.fs, qualityColorForDeal(quality, pal))

			row.cells[2]:SetText(formatGapQty(deal))
			setFsColor(row.cells[2], deal.kind == "item" and pal.textSecondary or pal.text)

			row.cells[3]:SetText(formatMoney(getGapAvgBuy(deal)))
			setFsColor(row.cells[3], pal.text)

			row.cells[4]:SetText(formatMoney(getGapNextTier(deal)))
			setFsColor(row.cells[4], pal.textSecondary)

			local gapPct = getGapPct(deal)
			row.cells[5]:SetText(formatPercent(gapPct))
			setFsColor(row.cells[5], gapPct >= 30 and pal.accentGreen or (pal.textBlue or pal.accentBlue))

			local net = getGapNetProfit(deal)
			row.cells[6]:SetText(formatMoney(net, true))
			setFsColor(row.cells[6], net >= 0 and pal.accentGreen or pal.accentRed)

			local hrs = getGapEstHours(deal)
			row.cells[7]:SetText(formatHours(hrs))
			if hrs and hrs <= 12 then
				setFsColor(row.cells[7], pal.accentGreen)
			elseif hrs and hrs <= 36 then
				setFsColor(row.cells[7], pal.text)
			else
				setFsColor(row.cells[7], pal.textSecondary)
			end

			local ps = getActivePurchaseState()
			local btnLabel, variant, enabled = gapActionPresentation(deal, ps)
			local btn = row.cells[8].btn
			btn:SetText(btnLabel)
			if btn.SetVariant then btn:SetVariant(variant) end
			if btn.SetEnabled then btn:SetEnabled(enabled) end
		end,
		onScroll = function()
			if state.gapView then
				state.gapView.repaintRows()
			end
		end,
	})
	anchorGapTable()

	local function buildScanOpts()
		local cfg = getConfig()
		local out = {}
		for k, v in pairs(cfg) do out[k] = v end
		local scope = normalizeGapScope(cfg.gapScope)
		out.gapScope = scope
		out.scope = scope
		return out
	end

	-- Top bar button handlers
	scanBtn:SetScript("OnClick", function()
		local SE = getSE()
		if not SE then
			state.statusOverride = "Engine unavailable"
			state.statusVariant = "warning"
			UI.Refresh("no_engine")
			return
		end
		local sc = (SE.GetScanProgress and SE.GetScanProgress())
			or (SE.GetScanState and SE.GetScanState())
			or (SE.GetState and SE.GetState())
			or {}
		local rawScan = (type(SE.scan) == "table") and SE.scan or nil
		local active = (sc.active == true) or (sc.scanning == true) or (rawScan and rawScan.active == true)
		if active then
			if type(SE.StopGapScan) == "function" then
				SE.StopGapScan()
			elseif type(SE.StopScan) == "function" then
				SE.StopScan()
			end
		else
			state.statusOverride = nil
			state.statusMessage = nil
			state.lastEmptyReason = nil
			local opts = buildScanOpts()
			local okStart, errCode
			if type(SE.StartGapScan) == "function" then
				okStart, errCode = SE.StartGapScan(opts)
			elseif type(SE.StartScan) == "function" then
				okStart, errCode = SE.StartScan(opts)
			end
			if okStart == false then
				if safeStr(errCode, ""):lower() == "insufficient_live_history" then
					state.lastEmptyReason = "insufficient_live_history"
				end
				local engMsg = (type(SE.scan) == "table" and safeStr(SE.scan.statusText, "")) or ""
				local shortMsg, fullMsg = describeBlockedReason(errCode, engMsg)
				state.statusOverride = shortMsg
				state.statusMessage = fullMsg
				state.statusVariant = "warning"
			end
		end
		UI.Refresh("gap_scan_toggle")
	end)
	scanBtn:HookScript("OnEnter", function(self)
		if not _G.GameTooltip then return end
		local cur = normalizeGapScope(getConfig().gapScope)
		_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
		_G.GameTooltip:ClearLines()
		_G.GameTooltip:AddLine("2-Stage Gap Scan (" .. (GAP_SCOPE_LABELS[cur] or "All AH Items") .. ")", 1, 1, 1)
		_G.GameTooltip:AddLine("Stage 1/2: Sweeps all AH lowest prices.", 0.85, 0.85, 0.90, true)
		_G.GameTooltip:AddLine("Stage 2/2: Drills only underpriced hits in selected scope.", 0.85, 0.85, 0.90, true)
		_G.GameTooltip:Show()
	end)
	scanBtn:HookScript("OnLeave", function()
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)

	snapBtn:SetScript("OnClick", function()
		local SE = getSE()
		if not SE then
			state.statusOverride = "Engine unavailable"
			state.statusVariant = "warning"
			UI.Refresh("no_engine")
			return
		end
		state.statusOverride = nil
		state.statusMessage = nil
		local opts = buildScanOpts()
		if type(SE.ScanSnapshotForGapDeals) == "function" then
			SE.ScanSnapshotForGapDeals(nil, opts)
		elseif type(SE.ScanGapSnapshot) == "function" then
			SE.ScanGapSnapshot(nil, opts)
		end
		UI.Refresh("gap_snapshot_scan")
	end)
	snapBtn:HookScript("OnEnter", function(self)
		if not _G.GameTooltip then return end
		local cur = normalizeGapScope(getConfig().gapScope)
		_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
		_G.GameTooltip:ClearLines()
		_G.GameTooltip:AddLine("Scan Snapshot (" .. (GAP_SCOPE_LABELS[cur] or "All AH Items") .. ")", 1, 1, 1)
		_G.GameTooltip:AddLine("Instant offline/online gap preview from the 15-min snapshot for the selected scope.", 0.85, 0.85, 0.90, true)
		_G.GameTooltip:Show()
	end)
	snapBtn:HookScript("OnLeave", function()
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)

	local function syncFilterInputs()
		local cfg = getConfig()
		local function setUnfocused(box, text)
			if not box or (box.HasFocus and box:HasFocus()) then return end
			box:SetText(text)
		end
		setUnfocused(filters.minGapPct.box, tostring(safeNum(cfg.minGapPct, DEFAULT_CONFIG.minGapPct)))
		setUnfocused(filters.minRoiPct.box, tostring(safeNum(cfg.minRoiPct, DEFAULT_CONFIG.minRoiPct)))
		setUnfocused(filters.minProfitGold.box, tostring(floor(safeNum(cfg.minProfitCopper, DEFAULT_CONFIG.minProfitCopper) / 10000 + 0.5)))
		setUnfocused(filters.maxSpendGold.box, tostring(floor(safeNum(cfg.maxSpendCopper, DEFAULT_CONFIG.maxSpendCopper) / 10000 + 0.5)))
		setUnfocused(filters.maxBuyShareDailyPct.box, tostring(safeNum(cfg.maxBuyShareDailyPct, DEFAULT_CONFIG.maxBuyShareDailyPct)))
		setUnfocused(filters.minDailySales.box, tostring(safeNum(cfg.minDailySales, DEFAULT_CONFIG.minDailySales)))
		setUnfocused(filters.minQty.box, tostring(safeNum(cfg.minQty, DEFAULT_CONFIG.minQty)))
		if filters.fastSellersFirst.SetChecked then
			filters.fastSellersFirst:SetChecked(cfg.fastSellersFirst ~= false)
		end
		if filters.scopeBtn then
			local scope = normalizeGapScope(cfg.gapScope)
			filters.scopeBtn:SetText(GAP_SCOPE_LABELS[scope] or GAP_SCOPE_LABELS.all)
			if filters.scopeBtn.SetVariant then
				filters.scopeBtn:SetVariant(scope == "all" and "primary" or "secondary")
			end
		end
	end

	local function repaintRows()
		local scope = normalizeGapScope(getConfig().gapScope)
		local scopeLabel = GAP_SCOPE_LABELS[scope] or GAP_SCOPE_LABELS.all
		local SE = getSE()
		local emptyReason = state.lastEmptyReason
			or (SE and type(SE.scan) == "table" and safeStr(SE.scan.lastEmptyReason, ""))
			or ""
		local emptyMsg
		if emptyReason == "insufficient_live_history" then
			emptyMsg = "Scan the AH at least 3 times (across 15+ minutes) to build local baseline prices for Gap Sniper."
		elseif hasSnapshotMode() then
			emptyMsg = format("No gap deals for %s. Click [Scan Snapshot] for an instant preview or [Start Gap Scan] at the Auction House.", scopeLabel)
		else
			emptyMsg = format("No gap deals for %s. Click [Start Gap Scan] at the Auction House.", scopeLabel)
		end
		gapTable:Render(state.gapRows, state.gapSort, emptyMsg)
	end

	local function refreshGapView()
		syncGapSnapshotLayout()
		syncFilterInputs()
		state.gapRows = collectGapDeals()

		-- Keep selected ladder deal synced with latest deal object
		if state.ladderExpanded and state.selectedGapKey then
			local found
			for _, d in ipairs(state.gapRows) do
				if getDealKey(d) == state.selectedGapKey then
					found = d
					break
				end
			end
			if found then
				state.selectedGapDeal = found
				ladder:Render(found)
			else
				state.ladderExpanded = false
				state.selectedGapKey = nil
				state.selectedGapDeal = nil
				ladder.frame:Hide()
			end
			anchorGapTable()
		end

		local SE = getSE()
		local sc = (SE and ((SE.GetScanProgress and SE.GetScanProgress())
			or (SE.GetScanState and SE.GetScanState())
			or (SE.GetState and SE.GetState()))) or {}
		local rawScan = (SE and type(SE.scan) == "table") and SE.scan or nil
		local scanning = (sc.active == true) or (sc.scanning == true) or (rawScan and rawScan.active == true)
		local phase = safeStr(sc.phase or (rawScan and rawScan.phase), ""):lower()
		if phase == "" and scanning then
			if sc.awaitingBrowse == true or (rawScan and rawScan.awaitingBrowse == true) then
				phase = "browse"
			else
				phase = "drill"
			end
		end
		local scanned = safeNum(sc.scanned, rawScan and safeNum(rawScan.scanned, 0) or 0)
		local total = safeNum(sc.total, rawScan and safeNum(rawScan.total, 0) or 0)
		local dealsN = #state.gapRows
		local cutRate = (SE and SE.GetDynamicAuctionCut and safeNum(SE.GetDynamicAuctionCut())) or safeNum(sc.ahCutRate or sc.ahCut, 0.05)
		local isNeutral = (SE and SE.IsNeutralAH and SE.IsNeutralAH() == true) or (sc.isNeutral == true) or (cutRate >= 0.14)

		-- Primary scan button toggle
		if scanning then
			scanBtn:SetText("Stop")
			if scanBtn.SetVariant then scanBtn:SetVariant("danger") end
		else
			scanBtn:SetText("Start Gap Scan")
			if scanBtn.SetVariant then scanBtn:SetVariant("primary") end
		end

		-- Progress bar & 2-stage telemetry text
		local cutPct = floor(cutRate * 100 + 0.5)
		local cutSuffix = isNeutral and format("%d%% Neutral", cutPct) or format("%d%%", cutPct)
		local pal = getPal()
		local frac = 0
		local barColor = pal.accentBlue

		if scanning and phase == "browse" then
			local ms = (ns.MarketScan and type(ns.MarketScan.GetState) == "function") and ns.MarketScan.GetState() or nil
			local browseSeen = safeNum(sc.browseSeen or sc.seen or (rawScan and (rawScan.browseSeen or rawScan.seen)) or (ms and ms.active and ms.seen), 0)
			local browseTotal = safeNum(sc.browseTotal or (rawScan and rawScan.browseTotal) or (ms and ms.active and ms.total), 0)
			local browsePage = safeNum(sc.browsePage or (rawScan and rawScan.browsePage) or (ms and ms.active and ms.page), 0)
			if browseTotal > 0 and browseSeen > 0 then
				progressFs:SetText(format("Stage 1/2: Sweeping all AH lowest prices... (%s / %s seen)", formatInt(browseSeen), formatInt(browseTotal)))
				frac = clamp(browseSeen / browseTotal, 0.08, 0.98)
			elseif browseSeen > 0 then
				progressFs:SetText(format("Stage 1/2: Sweeping all AH lowest prices... (%s seen)", formatInt(browseSeen)))
				frac = 0.22 + ((browsePage % 6) * 0.11)
			elseif browsePage > 0 then
				progressFs:SetText(format("Stage 1/2: Sweeping all AH lowest prices... (page %d)", floor(browsePage)))
				frac = 0.22 + ((browsePage % 6) * 0.11)
			else
				progressFs:SetText("Stage 1/2: Sweeping all AH lowest prices...")
				frac = 0.25
			end
			barColor = pal.accentBlue
		elseif scanning and phase == "drill" then
			progressFs:SetText(format("Stage 2/2: Drilling %d / %d hits | Deals: %d | AH Cut: %s", scanned, total, dealsN, cutSuffix))
			frac = (total > 0) and clamp(scanned / total, 0.04, 1) or (dealsN > 0 and 1 or 0.04)
			barColor = pal.accentBlue
		else
			if state.statusMessage and state.statusMessage ~= "" then
				progressFs:SetText(format("%s | Deals: %d | AH Cut: %s", state.statusMessage, dealsN, cutSuffix))
			else
				progressFs:SetText(format("Scanned %d / %d | Deals: %d | AH Cut: %s", scanned, total, dealsN, cutSuffix))
			end
			frac = (total > 0) and clamp(scanned / total, 0, 1) or (dealsN > 0 and 1 or 0)
			barColor = (dealsN > 0) and pal.accentGreen or pal.accentBlue
		end
		progressBar:SetValue(frac, barColor)

		-- Status pill
		local ps = getActivePurchaseState()
		local psStep = ps and safeStr(ps.step or ps.state, ""):lower() or ""
		local pillText, pillVar = "Ready", "neutral"
		if psStep == "awaiting_confirm" or psStep == "confirm" then
			pillText, pillVar = "Confirm Buy", "positive"
		elseif psStep == "quoting" or psStep == "requesting_quote" then
			pillText, pillVar = "Quoting...", "info"
		elseif psStep == "buying" or psStep == "confirming" or psStep == "purchasing" then
			pillText, pillVar = "Buying...", "info"
		elseif state.statusOverride then
			pillText = state.statusOverride
			pillVar = state.statusVariant or "warning"
		elseif scanning and phase == "browse" then
			pillText, pillVar = "Stage 1/2", "info"
		elseif scanning and phase == "drill" then
			pillText, pillVar = "Stage 2/2", "info"
		elseif scanning then
			pillText, pillVar = "Scanning", "info"
		elseif isNeutral then
			pillText, pillVar = "Neutral 15%", "warning"
		elseif hasSnapshotMode() and safeStr(sc.source, ""):lower() == "snapshot" then
			pillText, pillVar = "Snapshot", "purple"
		elseif dealsN > 0 then
			pillText, pillVar = format("%d Deals", dealsN), "positive"
		elseif not isAtAH() then
			if hasSnapshotMode() then
				pillText, pillVar = "Offline Preview", "neutral"
			else
				pillText, pillVar = "Open AH", "neutral"
			end
		end
		statusPill:SetVariant(pillVar, pillText)

		gapTable:Layout()
		repaintRows()
	end

	return {
		frame = view,
		topCard = topCard,
		filterCard = filterCard,
		table = gapTable,
		ladder = ladder,
		scanBtn = scanBtn,
		snapBtn = snapBtn,
		statusPill = statusPill,
		progressBar = progressBar,
		filters = filters,
		refresh = refreshGapView,
		repaintRows = repaintRows,
		anchorGapTable = anchorGapTable,
	}
end

---------------------------------------------------------------------------------------------------
-- Sub-View 2: Vendor Sniper (sniper_vendor)
---------------------------------------------------------------------------------------------------

local VENDOR_COLUMNS = {
	{ key = "name",          label = "Item",          flex = true, align = "LEFT",   kind = "item",   hint = "Item listed below NPC vendor sell price. Shift-click to link in chat." },
	{ key = "ahPrice",       label = "AH Price",      width = 88,  align = "RIGHT",  hint = "Cheapest Auction House buyout price per unit." },
	{ key = "vendorSell",    label = "Vendor Sell",   width = 88,  align = "RIGHT",  hint = "NPC vendor sell value per unit (verified by itemLink on Check)." },
	{ key = "profitPerUnit", label = "Profit / Unit", width = 94,  align = "RIGHT",  bold = true, hint = "Guaranteed risk-free profit per unit (Vendor Sell - AH Price)." },
	{ key = "source",        label = "Source",        width = 74,  align = "CENTER", hint = "Where the deal was detected on the Auction House." },
	{ key = "status",        label = "Status",        width = 82,  align = "CENTER", hint = "Live verification and purchase state." },
	{ key = "actionState",   label = "Action",        width = 88,  align = "CENTER", kind = "action", sortable = false, hint = "Left-click: Check -> Buy (items) or Buy -> Confirm (commodities). Right-click: Cancel." },
}

local function buildVendorView(parent)
	local view = CreateFrame("Frame", nil, parent)
	view:SetAllPoints(parent)

	-- 1. Top Action & KPI Card
	local topCard = createSurfaceCard(view, "glass_r10", "cardBg")
	topCard:SetHeight(52)
	topCard:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
	topCard:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)

	local snapBtn = createButton(topCard, "Scan Snapshot", 124, 26, {
		variant = "primary",
		icon = "search",
		iconSize = 12,
		fontSize = 11,
		weight = "semibold",
	})
	snapBtn:SetPoint("LEFT", topCard, "LEFT", 12, 0)

	local browseBtn = createButton(topCard, "Full AH Browse", 126, 26, {
		variant = "secondary",
		icon = "refresh",
		iconSize = 12,
		fontSize = 11,
	})
	browseBtn:SetPoint("LEFT", snapBtn, "RIGHT", 8, 0)

	local clearBtn = createButton(topCard, "Clear", 68, 26, {
		variant = "secondary",
		icon = "close",
		iconSize = 10,
		fontSize = 11,
	})
	clearBtn:SetPoint("LEFT", browseBtn, "RIGHT", 8, 0)

	local function syncVendorSnapshotLayout()
		local showSnap = hasSnapshotMode()
		if showSnap then
			snapBtn:Show()
			if snapBtn.SetVariant then snapBtn:SetVariant("primary") end
			if browseBtn.ClearAllPoints then browseBtn:ClearAllPoints() end
			browseBtn:SetPoint("LEFT", snapBtn, "RIGHT", 8, 0)
			if browseBtn.SetVariant then browseBtn:SetVariant("secondary") end
		else
			snapBtn:Hide()
			if browseBtn.ClearAllPoints then browseBtn:ClearAllPoints() end
			browseBtn:SetPoint("LEFT", topCard, "LEFT", 12, 0)
			if browseBtn.SetVariant then browseBtn:SetVariant("primary") end
		end
	end
	syncVendorSnapshotLayout()

	local kpiPill = createBadgePill(topCard, "Guaranteed: 0c", "positive", { height = 22, fontSize = 11, weight = "semibold" })
	kpiPill.frame:SetPoint("RIGHT", topCard, "RIGHT", -12, 0)

	local statusFs = topCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statusFs:SetPoint("LEFT", clearBtn, "RIGHT", 12, 0)
	statusFs:SetPoint("RIGHT", kpiPill.frame, "LEFT", -10, 0)
	statusFs:SetJustifyH("LEFT")
	if statusFs.SetWordWrap then statusFs:SetWordWrap(false) end
	if statusFs.SetMaxLines then statusFs:SetMaxLines(1) end
	applyFont(statusFs, 11, "regular")
	registerThemedFs(statusFs, "textSecondary")
	statusFs:SetText("")

	-- 2. Filter Strip Card (1 clean row, persisted in MerchantMasterDB.sniper)
	local filterCard = createSurfaceCard(view, "glass_r10", "cardBg")
	filterCard:SetHeight(38)
	filterCard:SetPoint("TOPLEFT", topCard, "BOTTOMLEFT", 0, -SECTION_GAP)
	filterCard:SetPoint("TOPRIGHT", topCard, "BOTTOMRIGHT", 0, -SECTION_GAP)

	local filters = {}
	local vendorTable
	local function refreshAfterFilter()
		if vendorTable then vendorTable:ResetScroll() end
		if UI.IsShown() then UI.Refresh("vendor_filter_changed") end
	end

	filters.minProfit = createNumericField(filterCard, "Min Profit (s/g)", 66, "Minimum vendor profit per unit. Examples: 50s, 2g, 1g 50s, or bare silver (50).", function(txt, box)
		local parsed = parseSilverGoldInput(txt)
		if parsed ~= nil then
			updateConfig("vendorMinProfitCopper", parsed)
			box:SetText(formatSilverGoldInput(parsed))
			refreshAfterFilter()
		else
			box:SetText(formatSilverGoldInput(getConfig().vendorMinProfitCopper))
		end
	end)
	filters.minProfit.wrap:SetPoint("LEFT", filterCard, "LEFT", 12, 0)

	filters.includeCommodities = createToggleField(filterCard, "Include Commodities", "Include stackable commodity items listed below vendor sell price.", function(on)
		updateConfig("vendorIncludeCommodities", on)
		refreshAfterFilter()
	end)
	filters.includeCommodities:SetPoint("LEFT", filters.minProfit.wrap, "RIGHT", 18, 0)

	filters.autoBrowse = createToggleField(filterCard, "Auto-populate from Browse", "Automatically capture vendor snipes during every MarketScan AH browse.", function(on)
		updateConfig("vendorAutoFromBrowse", on)
		refreshAfterFilter()
	end)
	filters.autoBrowse:SetPoint("LEFT", filters.includeCommodities.label, "RIGHT", 22, 0)

	-- 3. Sortable Deals Table
	vendorTable = createPooledTable(view, VENDOR_COLUMNS, {
		onHeaderClick = function(colKey)
			if state.vendorSort.col == colKey then
				state.vendorSort.asc = not state.vendorSort.asc
			else
				state.vendorSort.col = colKey
				state.vendorSort.asc = (colKey == "name" or colKey == "ahPrice" or colKey == "source")
			end
			if vendorTable then vendorTable:ResetScroll() end
			UI.Refresh("vendor_sort")
		end,
		-- Strictly synchronous OnClick invocation for protected AH calls!
		onActionClick = function(deal, mouseButton)
			local SE = getSE()
			if not SE then
				state.vendorStatusMsg = "SniperEngine not loaded"
				UI.Refresh("no_engine")
				return
			end
			if mouseButton == "RightButton" then
				if type(SE.CancelActivePurchase) == "function" then
					SE.CancelActivePurchase("Cancelled by user.")
				elseif type(SE.CancelPurchase) == "function" then
					SE.CancelPurchase(deal)
				elseif type(SE.HandleVendorAction) == "function" then
					SE.HandleVendorAction(deal, "cancel")
				end
			else
				if type(SE.HandleVendorAction) == "function" then
					local okAct, errCode = SE.HandleVendorAction(deal)
					if okAct == false then
						local engMsg = (type(SE.scan) == "table" and safeStr(SE.scan.statusText, "")) or ""
						local _, fullMsg = describeBlockedReason(errCode, engMsg)
						state.vendorStatusMsg = fullMsg
					else
						state.vendorStatusMsg = nil
					end
				end
			end
			UI.Refresh("vendor_action")
		end,
		onActionTooltip = function(owner, deal)
			if not _G.GameTooltip then return end
			local ps = getActivePurchaseState()
			local lbl, _, _, statusLbl = vendorActionPresentation(deal, ps)
			_G.GameTooltip:SetOwner(owner, "ANCHOR_TOP")
			_G.GameTooltip:ClearLines()
			_G.GameTooltip:AddLine("Vendor Action: " .. lbl, 1, 1, 1)
			if deal.isCommodity then
				_G.GameTooltip:AddLine("Commodity: Buy -> Confirm (2-click Forever safe purchase).", 0.85, 0.85, 0.90, true)
			elseif statusLbl == "Verified" then
				_G.GameTooltip:AddLine("Verified live auctionID + itemLink vendor value. Click Buy to PlaceBid.", 0.30, 0.85, 0.45, true)
			else
				_G.GameTooltip:AddLine("Click Check to verify live buyout and exact itemLink vendor sell value before buying.", 0.85, 0.85, 0.90, true)
			end
			_G.GameTooltip:AddLine("Right-click: Cancel pending check or quote.", 0.70, 0.70, 0.76, true)
			_G.GameTooltip:Show()
		end,
		onRowTooltip = function(owner, deal)
			if not _G.GameTooltip then return end
			_G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
			_G.GameTooltip:ClearLines()
			local id = safeNum(deal.itemID, 0)
			local name, link = getDealItemVisual(deal)
			if link and _G.GameTooltip.SetHyperlink then
				pcall(_G.GameTooltip.SetHyperlink, _G.GameTooltip, link)
			elseif id > 0 and _G.GameTooltip.SetItemByID then
				pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, id)
			else
				_G.GameTooltip:AddLine(name, 1, 1, 1)
			end
			_G.GameTooltip:AddLine(" ")
			_G.GameTooltip:AddDoubleLine("AH Buyout:", formatMoney(getVendorAhPrice(deal)), 0.78, 0.78, 0.82, 1, 1, 1)
			_G.GameTooltip:AddDoubleLine("Vendor Sell:", formatMoney(getVendorSell(deal)), 0.78, 0.78, 0.82, 1, 0.82, 0.2)
			_G.GameTooltip:AddDoubleLine("Guaranteed Profit / Unit:", formatMoney(getVendorProfitUnit(deal), true), 0.78, 0.78, 0.82, 0.2, 0.85, 0.4)
			local qty = getVendorQty(deal)
			if qty > 1 then
				_G.GameTooltip:AddDoubleLine("Listed Qty / Total:", format("x%d  (%s)", qty, formatMoney(getVendorTotalProfit(deal), true)), 0.78, 0.78, 0.82, 0.2, 0.85, 0.4)
			end
			_G.GameTooltip:AddDoubleLine("Source:", safeStr(deal.source, "Snapshot"), 0.78, 0.78, 0.82, 0.6, 0.82, 1)
			_G.GameTooltip:Show()
		end,
		bindRow = function(row, deal, pal)
			local T = getTheme()
			local name, _, quality, ic = getDealItemVisual(deal)
			local itemCell = row.cells[1]
			itemCell.icon:SetTexture(ic or (T and T.ASSETS and T.ASSETS.icon_coins) or "Interface\\Icons\\INV_Misc_QuestionMark")
			itemCell.fs:SetText(name)
			setFsColor(itemCell.fs, qualityColorForDeal(quality, pal))

			row.cells[2]:SetText(formatMoney(getVendorAhPrice(deal)))
			setFsColor(row.cells[2], pal.text)

			row.cells[3]:SetText(formatMoney(getVendorSell(deal)))
			setFsColor(row.cells[3], pal.textSecondary)

			local pUnit = getVendorProfitUnit(deal)
			row.cells[4]:SetText(formatMoney(pUnit, true))
			setFsColor(row.cells[4], pUnit > 0 and pal.accentGreen or pal.accentRed)

			local src = safeStr(deal.source, "Snapshot")
			row.cells[5]:SetText(src)
			setFsColor(row.cells[5], src:lower() == "browse" and (pal.textBlue or pal.accentBlue) or pal.accentPurple)

			local ps = getActivePurchaseState()
			local btnLabel, variant, enabled, statusLbl = vendorActionPresentation(deal, ps)
			row.cells[6]:SetText(statusLbl)
			if statusLbl == "Verified" or statusLbl == "Confirm" or statusLbl == "Bought" then
				setFsColor(row.cells[6], pal.accentGreen)
			elseif statusLbl == "Checking" or statusLbl == "Quoting" or statusLbl == "Buying" then
				setFsColor(row.cells[6], pal.textBlue or pal.accentBlue)
			elseif statusLbl == "Gone" or statusLbl == "Price Up" then
				setFsColor(row.cells[6], pal.accentRed)
			else
				setFsColor(row.cells[6], pal.textSecondary)
			end

			local btn = row.cells[7].btn
			btn:SetText(btnLabel)
			if btn.SetVariant then btn:SetVariant(variant) end
			if btn.SetEnabled then btn:SetEnabled(enabled) end
		end,
		onScroll = function()
			if state.vendorView then
				state.vendorView.repaintRows()
			end
		end,
	})
	vendorTable.container:SetPoint("TOPLEFT", filterCard, "BOTTOMLEFT", 0, -SECTION_GAP)
	vendorTable.container:SetPoint("TOPRIGHT", filterCard, "BOTTOMRIGHT", 0, -SECTION_GAP)
	vendorTable.container:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
	vendorTable.container:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)

	-- Top bar button handlers
	snapBtn:SetScript("OnClick", function()
		local SE = getSE()
		if not SE then
			state.vendorStatusMsg = "SniperEngine not loaded"
			UI.Refresh("no_engine")
			return
		end
		state.vendorStatusMsg = nil
		if type(SE.ScanSnapshotForVendorDeals) == "function" then
			local cfg = getConfig()
			SE.ScanSnapshotForVendorDeals(nil, {
				vendorMinProfitCopper = cfg.vendorMinProfitCopper,
				minProfitCopper = cfg.vendorMinProfitCopper,
				vendorIncludeCommodities = cfg.vendorIncludeCommodities,
				includeCommodities = cfg.vendorIncludeCommodities,
			})
		end
		UI.Refresh("vendor_snapshot_scan")
	end)

	browseBtn:SetScript("OnClick", function()
		if not isAtAH() then
			state.vendorStatusMsg = "Open Auction House to run Full AH Browse."
			UI.Refresh("vendor_need_ah")
			return
		end
		state.vendorStatusMsg = "Scanning AH Browse..."
		local SE = getSE()
		if SE and type(SE.StartVendorBrowseScan) == "function" then
			SE.StartVendorBrowseScan(getConfig())
		elseif ns.MarketScan and type(ns.MarketScan.EnsureBrowseRunning) == "function" then
			ns.MarketScan.EnsureBrowseRunning()
		else
			local ms = ns.MarketScan and ns.MarketScan.GetState and ns.MarketScan.GetState()
			if not (ms and ms.active) then
				if ns.app and type(ns.app.refreshAllMarketValues) == "function" then
					ns.app.refreshAllMarketValues()
				elseif _G.MerchantMasterAPI and type(_G.MerchantMasterAPI.RefreshMarket) == "function" then
					_G.MerchantMasterAPI.RefreshMarket()
				end
			end
		end
		UI.Refresh("vendor_browse_scan")
	end)

	clearBtn:SetScript("OnClick", function()
		state.vendorStatusMsg = nil
		local SE = getSE()
		if SE and type(SE.ClearVendorDeals) == "function" then
			SE.ClearVendorDeals()
		end
		state.vendorRows = {}
		if vendorTable then vendorTable:ResetScroll() end
		UI.Refresh("vendor_clear")
	end)

	local function syncFilterInputs()
		local cfg = getConfig()
		if filters.minProfit.box and (not filters.minProfit.box.HasFocus or not filters.minProfit.box:HasFocus()) then
			filters.minProfit.box:SetText(formatSilverGoldInput(cfg.vendorMinProfitCopper))
		end
		if filters.includeCommodities.SetChecked then
			filters.includeCommodities:SetChecked(cfg.vendorIncludeCommodities ~= false)
		end
		if filters.autoBrowse.SetChecked then
			filters.autoBrowse:SetChecked(cfg.vendorAutoFromBrowse ~= false)
		end
	end

	local function repaintRows()
		local emptyMsg = hasSnapshotMode()
			and "No vendor snipes found yet. Click [Scan Snapshot] for an instant scan or [Full AH Browse] at the Auction House."
			or "No vendor snipes found yet. Click [Full AH Browse] at the Auction House."
		local SE = getSE()
		if #state.vendorRows == 0 and SE and type(SE.GetVendorDeals) == "function" then
			local ok, raw = pcall(SE.GetVendorDeals)
			if ok and type(raw) == "table" and #raw > 0 then
				emptyMsg = format("%d vendor snipe(s) hidden by current filters (Min Profit / Include Commodities).", #raw)
			end
		end
		vendorTable:Render(state.vendorRows, state.vendorSort, emptyMsg)
	end

	local function refreshVendorView()
		syncVendorSnapshotLayout()
		syncFilterInputs()
		state.vendorRows = collectVendorDeals()

		local totalGuaranteed = 0
		local activeCount = 0
		local ps = getActivePurchaseState()
		for _, d in ipairs(state.vendorRows) do
			local step = resolveDealStep(d, ps)
			if step ~= "bought" and step ~= "gone" and step ~= "price_up" then
				totalGuaranteed = totalGuaranteed + max(0, getVendorTotalProfit(d))
				activeCount = activeCount + 1
			end
		end

		local kpiText = activeCount > 0
			and format("Guaranteed: %s (%d)", formatMoney(totalGuaranteed), activeCount)
			or "Guaranteed: 0c"
		kpiPill:SetVariant(totalGuaranteed > 0 and "positive" or "neutral", kpiText)

		local ms = ns.MarketScan and ns.MarketScan.GetState and ns.MarketScan.GetState()
		if ms and ms.active then
			statusFs:SetText(format("Browse scanning page %d...", safeNum(ms.page, 1)))
		elseif state.vendorStatusMsg then
			statusFs:SetText(state.vendorStatusMsg)
		elseif not isAtAH() then
			if hasSnapshotMode() then
				statusFs:SetText("Snapshot preview mode (open AH to check and buy)")
			else
				statusFs:SetText("Open the Auction House to run Full AH Browse")
			end
		else
			statusFs:SetText("")
		end

		vendorTable:Layout()
		repaintRows()
	end

	return {
		frame = view,
		topCard = topCard,
		filterCard = filterCard,
		table = vendorTable,
		snapBtn = snapBtn,
		browseBtn = browseBtn,
		clearBtn = clearBtn,
		kpiPill = kpiPill,
		filters = filters,
		refresh = refreshVendorView,
		repaintRows = repaintRows,
	}
end

---------------------------------------------------------------------------------------------------
-- Engine Listener & Lazy Construction
---------------------------------------------------------------------------------------------------

local function isWarningStatusText(msg)
	local low = safeStr(msg, ""):lower()
	if low == "" or low == "idle" then return false end
	return low:find("open the auction house", 1, true) ~= nil
		or low:find("cart buyer", 1, true) ~= nil
		or low:find("not enough gold", 1, true) ~= nil
		or low:find("busy", 1, true) ~= nil
		or low:find("timed out", 1, true) ~= nil
		or low:find("failed", 1, true) ~= nil
		or low:find("cancelled", 1, true) ~= nil
		or low:find("canceled", 1, true) ~= nil
		or low:find("expired", 1, true) ~= nil
		or low:find("interrupted", 1, true) ~= nil
		or low:find("unavailable", 1, true) ~= nil
		or low:find("no longer profitable", 1, true) ~= nil
		or low:find("no listing", 1, true) ~= nil
		or low:find("moved above", 1, true) ~= nil
end

local COALESCED_ENGINE_EVENTS = {
	status = true,
	scan_progress = true,
	browse_progress = true,
	vendor_deals = true,
	gap_deals = true,
}

local function scheduleCoalescedRefresh(reason)
	state.dirty = true
	state.pendingRefreshReason = reason
	if state.refreshTimerPending then return end
	if _G.C_Timer and type(_G.C_Timer.After) == "function" then
		state.refreshTimerPending = true
		_G.C_Timer.After(0.1, function()
			state.refreshTimerPending = false
			local pendingReason = state.pendingRefreshReason or "coalesced"
			state.pendingRefreshReason = nil
			if state.dirty and UI.IsShown() then
				UI.Refresh(pendingReason)
			end
		end)
	else
		UI.Refresh(reason)
	end
end

local function onEngineEvent(eventType, payload)
	if eventType == "scan_started" or eventType == "scan_progress" or eventType == "scan_phase"
		or eventType == "scan_complete" or eventType == "scan_stopped"
		or eventType == "browse_progress" or eventType == "browse_complete"
		or eventType == "purchase_started" or eventType == "purchase_quoted" or eventType == "purchase_quote"
		or eventType == "purchase_succeeded" or eventType == "purchase_done" then
		local stopMsg = (eventType == "scan_stopped" and type(payload) == "table") and safeStr(payload.statusText, "") or ""
		local stopReason = (eventType == "scan_stopped" and type(payload) == "table") and safeStr(payload.reason, ""):lower() or ""
		if stopReason == "insufficient_live_history" then
			state.lastEmptyReason = "insufficient_live_history"
			local shortMsg, fullMsg = describeBlockedReason("insufficient_live_history", stopMsg)
			state.statusOverride = shortMsg
			state.statusMessage = fullMsg
			state.statusVariant = "warning"
		elseif stopMsg ~= "" and isWarningStatusText(stopMsg) then
			state.lastEmptyReason = nil
			local shortMsg, fullMsg = describeBlockedReason(nil, stopMsg)
			state.statusOverride = shortMsg
			state.statusMessage = fullMsg
			state.statusVariant = "warning"
		else
			state.statusOverride = nil
			if eventType == "scan_started" or eventType == "scan_progress" or eventType == "scan_phase"
				or eventType == "browse_progress" or eventType == "purchase_succeeded" or eventType == "purchase_done" then
				state.statusMessage = nil
				state.lastEmptyReason = nil
			elseif eventType == "scan_stopped" and stopReason == "" then
				state.lastEmptyReason = nil
			end
		end
	elseif type(payload) == "string" then
		local msg = safeStr(payload, "")
		if msg ~= "" and msg:lower() ~= "idle" then
			if eventType == "vendor_status" or state.activeSubTab == "sniper_vendor" then
				state.vendorStatusMsg = msg
			end
			if eventType == "status" or eventType == "error" then
				local SE = getSE()
				local scanning = SE and type(SE.scan) == "table" and SE.scan.active == true
				if isWarningStatusText(msg) then
					local shortMsg, fullMsg = describeBlockedReason(nil, msg)
					state.statusOverride = shortMsg
					state.statusMessage = fullMsg
					state.statusVariant = (eventType == "error") and "danger" or "warning"
				elseif not scanning then
					state.statusMessage = msg
				end
			end
		end
	elseif type(payload) == "table" then
		local msg = safeStr(payload.error or payload.message or payload.reason or payload.statusText, "")
		if msg ~= "" then
			if eventType == "vendor_status" or payload.scope == "vendor" then
				state.vendorStatusMsg = msg
			elseif payload.error or eventType == "error" or eventType == "purchase_cancelled" or eventType == "purchase_failed" then
				local shortMsg, fullMsg = describeBlockedReason(payload.code, msg)
				state.statusOverride = shortMsg
				state.statusMessage = fullMsg
				state.statusVariant = (payload.error or eventType == "purchase_failed") and "danger" or (payload.variant or "warning")
			end
		end
	end
	if not UI.IsShown() then
		state.dirty = true
		return
	end
	local reason = eventType or "engine_event"
	if COALESCED_ENGINE_EVENTS[eventType] then
		scheduleCoalescedRefresh(reason)
		return
	end
	UI.Refresh(reason)
end

local function attachEngineListener()
	if state.listenerHooked then return end
	local SE = getSE()
	if SE and type(SE.SetListener) == "function" then
		local ok = pcall(SE.SetListener, onEngineEvent)
		if ok then state.listenerHooked = true end
	end
end

local function hookThemeEvents()
	if state.themeHooked then return end
	local T = getTheme()
	if not T then return end
	state.themeHooked = true
	local function onThemeChange()
		if state.built then
			UI.ApplyTheme()
		end
	end
	if type(T.OnModeChanged) == "function" then T.OnModeChanged(onThemeChange) end
	if type(T.OnSkinChanged) == "function" then T.OnSkinChanged(onThemeChange) end
	if type(T.OnTableStyleChanged) == "function" then T.OnTableStyleChanged(onThemeChange) end
end

local function ensureBuilt()
	if state.built then return true end
	if not state.root then return false end
	state.built = true

	state.gapView = buildGapView(state.root)
	state.vendorView = buildVendorView(state.root)
	state.gapView.frame:Hide()
	state.vendorView.frame:Hide()

	hookThemeEvents()
	attachEngineListener()
	UI.ApplyTheme()
	return true
end

---------------------------------------------------------------------------------------------------
-- Provider Public Lifecycle API
---------------------------------------------------------------------------------------------------

function UI.Mount(parent)
	if not parent then return false end
	if state.root then
		if state.parent ~= parent then
			state.parent = parent
			if state.root.SetParent then state.root:SetParent(parent) end
			state.root:ClearAllPoints()
			state.root:SetAllPoints(parent)
		end
		return state.root
	end
	state.parent = parent
	-- Lightweight hidden root only: ZERO row frames created until first Show()!
	local root = CreateFrame("Frame", nil, parent)
	root:SetAllPoints(parent)
	root:Hide()
	state.root = root
	return root
end

function UI.Show(subTab)
	if not state.root then return false end
	if subTab ~= nil then
		state.activeSubTab = normalizeSubTab(subTab)
	end
	ensureBuilt()
	attachEngineListener()

	state.root:Show()
	if state.activeSubTab == "sniper_vendor" then
		state.gapView.frame:Hide()
		state.vendorView.frame:Show()
	else
		state.vendorView.frame:Hide()
		state.gapView.frame:Show()
	end
	state.dirty = false
	UI.Refresh("show")
	return true
end

function UI.Hide()
	if state.root then
		state.root:Hide()
	end
	if state.gapView and state.gapView.frame then state.gapView.frame:Hide() end
	if state.vendorView and state.vendorView.frame then state.vendorView.frame:Hide() end
end

function UI.IsShown()
	return state.root ~= nil and shown(state.root)
end

function UI.GetActiveSubTab()
	return state.activeSubTab
end

function UI.Layout()
	if not state.built or not UI.IsShown() then return end
	if state.activeSubTab == "sniper_vendor" and state.vendorView then
		state.vendorView.table:Layout()
		state.vendorView.repaintRows()
	elseif state.gapView then
		state.gapView.anchorGapTable()
		state.gapView.table:Layout()
		state.gapView.repaintRows()
	end
end

function UI.ApplyTheme()
	if not state.built then return end
	local pal = getPal()
	for _, entry in ipairs(state.styledCards) do
		paintSurfaceCard(entry, pal)
	end
	for _, item in ipairs(state.themedText) do
		local col = pal[item.key] or pal.text
		setFsColor(item.fs, col)
	end
	local sep = pal.separator
	for _, tex in ipairs(state.themedSeparators) do
		if tex and tex.SetColorTexture then
			tex:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.5)
		end
	end
	for _, tbl in ipairs(state.tables) do
		tbl:PaintChrome()
	end
	if UI.IsShown() then
		UI.Refresh("theme")
	end
end

function UI.Refresh(reason)
	if not state.built or not UI.IsShown() then
		state.dirty = true
		return
	end
	attachEngineListener()
	state.dirty = false
	state.pendingRefreshReason = nil
	if state.activeSubTab == "sniper_vendor" then
		if state.vendorView then state.vendorView.refresh(reason) end
	else
		if state.gapView then state.gapView.refresh(reason) end
	end
end

function UI.Invalidate(reason)
	state.dirty = true
	if UI.IsShown() then
		UI.Refresh(reason or "invalidate")
	end
end

---------------------------------------------------------------------------------------------------
-- Provider Registration (Idempotent)
---------------------------------------------------------------------------------------------------

local provider = {
	Mount = UI.Mount,
	Show = UI.Show,
	Hide = UI.Hide,
	Refresh = UI.Refresh,
	ApplyTheme = UI.ApplyTheme,
	Invalidate = UI.Invalidate,
	IsShown = UI.IsShown,
	Layout = UI.Layout,
	GetActiveSubTab = UI.GetActiveSubTab,
}

ns.sniperProvider = provider

if _G.MerchantMasterAPI and type(_G.MerchantMasterAPI.RegisterSniper) == "function" then
	_G.MerchantMasterAPI.RegisterSniper(provider)
end
