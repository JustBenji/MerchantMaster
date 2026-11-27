-- Headless WoW 3.3.5 / Classic Frame-Graph Dumper for MerchantMaster
-- Runs in Lua 5.1, loads MerchantMaster.toc in exact client order, seeds realistic
-- Horde/Normal market + profession + turn-in + ledger data, drives tab/theme transitions,
-- solves WoW anchor constraints at 1920x960, and exports JSON scene trees.

local unpack = unpack or table.unpack

local scriptDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local addonDir = scriptDir .. "../"
-- CLI: `lua_frame_dump.lua [outDir] [--audit] [--skins] [--cart-ah-only] [--only=a,b]` (flags and outDir in any order).
-- --skins additionally dumps the Warcraft-skin scenes (Standard dark/light + 5 skins + options/market/recipes + cart/ah-buyer).
local audit, skinsMode, cartAhOnly, onlyScenes, outDirArg = false, false, false, nil, nil
for _, a in ipairs(arg or {}) do
	if a == "--audit" then audit = true
	elseif a == "--skins" then skinsMode = true
	elseif a == "--cart-ah-only" then cartAhOnly = true; skinsMode = true
	elseif a:sub(1, 7) == "--only=" then
		onlyScenes = onlyScenes or {}
		skinsMode = true
		for name in a:sub(8):gmatch("[^,]+") do
			onlyScenes[name] = true
		end
	elseif not outDirArg then outDirArg = a end
end
local outDir = outDirArg or (scriptDir .. "scene_dumps")
outDir = outDir:gsub("[/\\]+$", "")

local VIEWPORT_W = 1920
local VIEWPORT_H = 960

---------------------------------------------------------------------------------------------------
-- Minimal JSON Encoder (pure Lua 5.1)
---------------------------------------------------------------------------------------------------
local function jsonEscape(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\")
	s = s:gsub('"', '\\"')
	s = s:gsub("\b", "\\b")
	s = s:gsub("\f", "\\f")
	s = s:gsub("\n", "\\n")
	s = s:gsub("\r", "\\r")
	s = s:gsub("\t", "\\t")
	s = s:gsub("[%z\1-\31]", function(c)
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. s .. '"'
end

local function isArray(t)
	local count = 0
	for k, _ in pairs(t) do
		if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
			return false
		end
		count = count + 1
	end
	for i = 1, count do
		if t[i] == nil then return false end
	end
	return count > 0
end

local function encodeJson(v)
	local tp = type(v)
	if tp == "nil" then
		return "null"
	elseif tp == "boolean" then
		return v and "true" or "false"
	elseif tp == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "0"
		end
		if math.floor(v) == v and math.abs(v) < 1e14 then
			return string.format("%d", v)
		end
		return string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
	elseif tp == "string" then
		return jsonEscape(v)
	elseif tp == "table" then
		if v.__json_array or isArray(v) then
			local parts = {}
			for i = 1, #v do
				parts[#parts + 1] = encodeJson(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local keys = {}
			for k, val in pairs(v) do
				if type(k) == "string" and k:sub(1, 2) ~= "__" and val ~= nil then
					keys[#keys + 1] = k
				end
			end
			table.sort(keys)
			local parts = {}
			for _, k in ipairs(keys) do
				parts[#parts + 1] = jsonEscape(k) .. ":" .. encodeJson(v[k])
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

---------------------------------------------------------------------------------------------------
-- WoW Globals, Utility Functions & Event/Timer Queues
---------------------------------------------------------------------------------------------------
_G.WOW_PROJECT_ID = 100
_G.WOW_PROJECT_CAMELOT = 100
_G.WOW_PROJECT_CLASSIC = 2
_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
_G.WOW_PROJECT_WRATH_CLASSIC = 11

_G.strmatch = string.match
_G.strfind = string.find
_G.strsub = string.sub
_G.strlower = string.lower
_G.strupper = string.upper
_G.strlen = string.len
_G.strsplit = function(sep, str, pieces)
	local out = {}
	local pattern = "([^" .. sep:gsub("([^%w])", "%%%1") .. "]*)" .. sep .. "?"
	local idx = 1
	local s = tostring(str or "")
	while idx <= #s + 1 do
		local a, b = s:find(sep, idx, true)
		if not a then
			out[#out + 1] = s:sub(idx)
			break
		end
		out[#out + 1] = s:sub(idx, a - 1)
		idx = b + 1
		if pieces and #out >= pieces - 1 then
			out[#out + 1] = s:sub(idx)
			break
		end
	end
	return unpack(out)
end
_G.strtrim = function(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
_G.format = string.format
_G.tinsert = table.insert
_G.tremove = table.remove
_G.sort = table.sort
_G.tContains = function(tbl, item)
	for _, v in pairs(tbl or {}) do
		if v == item then return true end
	end
	return false
end
_G.wipe = function(t)
	if type(t) == "table" then
		for k in pairs(t) do t[k] = nil end
	end
	return t
end
_G.CopyTable = function(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = _G.CopyTable(v) end
	return c
end
_G.Mixin = function(t, ...)
	for i = 1, select("#", ...) do
		local src = select(i, ...)
		if type(src) == "table" then
			for k, v in pairs(src) do t[k] = v end
		end
	end
	return t
end
_G.CreateFromMixins = function(...)
	return _G.Mixin({}, ...)
end
_G.CreateVector2D = function(x, y)
	return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end
_G.issecretvalue = function() return false end

local simTime = 1794360000
local simClock = 1000.0
_G.time = function() return simTime end
_G.GetTime = function() return simClock end
_G.date = os.date
_G.GetLocale = function() return "enUS" end
_G.SecondsToTime = function(s)
	s = math.floor(tonumber(s) or 0)
	if s >= 3600 then return math.floor(s / 3600) .. "h" end
	if s >= 60 then return math.floor(s / 60) .. "m" end
	return s .. "s"
end
_G.IsShiftKeyDown = function() return false end
_G.IsControlKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.PlaySound = function() end
_G.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2, IG_MAINMENU_OPTION_CHECKBOX_ON = 3 }
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.ChatEdit_InsertLink = function() return false end
_G.HandleModifiedItemClick = function() return false end
_G.GetBuildInfo = function() return "1.15.7", "60000", "Nov 16 2026", 11507 end
_G.debugprofilestop = function() return os.clock() * 1000 end
_G.GetMoney = function() return 18426500 end
_G.GetMoneyString = function(copper, separateThousands)
	copper = math.floor(tonumber(copper) or 0)
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 or g > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end
_G.GetCoinTextureString = _G.GetMoneyString
_G.GetNumAddOns = function() return 1 end
_G.GetAddOnInfo = function() return "MerchantMaster", "MerchantMaster", "", true, "INSECURE", false end
_G.IsAddOnLoaded = function(name)
	return name == "MerchantMaster"
end
local function readTocVersion()
	local f = io.open("MerchantMaster.toc", "r")
	if not f then return "dev" end
	for line in f:lines() do
		local ver = line:match("^##%s*Version:%s*(.-)%s*$")
		if ver and ver ~= "" then
			f:close()
			if ver == "@project-version@" then return "dev" end
			return ver
		end
	end
	f:close()
	return "dev"
end
local TOC_VERSION = readTocVersion()

_G.C_AddOns = {
	IsAddOnLoaded = _G.IsAddOnLoaded,
	GetAddOnMetadata = function(_, k)
		if k == "Version" then return TOC_VERSION end
		return nil
	end,
}

_G.hooksecurefunc = function(tblOrName, nameOrFn, maybeFn)
	if type(tblOrName) == "string" then
		local orig = _G[tblOrName]
		local hook = nameOrFn
		_G[tblOrName] = function(...)
			local r1, r2, r3, r4
			if orig then r1, r2, r3, r4 = orig(...) end
			hook(...)
			return r1, r2, r3, r4
		end
	elseif type(tblOrName) == "table" and type(nameOrFn) == "string" and type(maybeFn) == "function" then
		local orig = tblOrName[nameOrFn]
		tblOrName[nameOrFn] = function(...)
			local r1, r2, r3, r4
			if orig then r1, r2, r3, r4 = orig(...) end
			maybeFn(...)
			return r1, r2, r3, r4
		end
	end
end

local timerQueue = {}
_G.C_Timer = {
	After = function(delay, fn)
		if type(fn) ~= "function" then return end
		if (tonumber(delay) or 0) <= 2.0 then
			timerQueue[#timerQueue + 1] = fn
		end
	end,
	NewTimer = function(delay, fn)
		local cancelled = false
		if type(fn) == "function" and (tonumber(delay) or 0) <= 2.0 then
			timerQueue[#timerQueue + 1] = function()
				if not cancelled then fn() end
			end
		end
		return { Cancel = function() cancelled = true end }
	end,
	NewTicker = function()
		return { Cancel = function() end }
	end,
}

local function drainTimers(maxSteps)
	local steps = 0
	while #timerQueue > 0 and steps < (maxSteps or 5000) do
		local fn = table.remove(timerQueue, 1)
		steps = steps + 1
		local ok, err = pcall(fn)
		if not ok then
			io.stderr:write("[timer warn] " .. tostring(err) .. "\n")
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Standard WoW FontObjects & Strata Order
---------------------------------------------------------------------------------------------------
local FONT_TEMPLATES = {
	GameFontNormal          = { size = 12, flags = "", color = { 1, 0.82, 0, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontNormalSmall     = { size = 10, flags = "", color = { 1, 0.82, 0, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontNormalMed3      = { size = 14, flags = "", color = { 1, 0.82, 0, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontNormalLarge     = { size = 16, flags = "", color = { 1, 0.82, 0, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontNormalHuge      = { size = 20, flags = "", color = { 1, 0.82, 0, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontHighlight       = { size = 12, flags = "", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontHighlightSmall  = { size = 10, flags = "", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontHighlightMedium = { size = 14, flags = "", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontHighlightLarge  = { size = 16, flags = "", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontDisable         = { size = 12, flags = "", color = { 0.5, 0.5, 0.5, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	GameFontDisableSmall    = { size = 10, flags = "", color = { 0.5, 0.5, 0.5, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	NumberFontNormal        = { size = 12, flags = "OUTLINE", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	NumberFontNormalSmall   = { size = 10, flags = "OUTLINE", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
	ChatFontNormal          = { size = 12, flags = "", color = { 1, 1, 1, 1 }, shadowOffset = { 1, -1 }, shadowColor = { 0, 0, 0, 0.85 } },
}
for fname, fdef in pairs(FONT_TEMPLATES) do
	_G[fname] = {
		GetFont = function() return "Fonts\\FRIZQT__.TTF", fdef.size, fdef.flags end,
		GetTextColor = function() return unpack(fdef.color) end,
		GetShadowOffset = function() return unpack(fdef.shadowOffset) end,
		GetShadowColor = function() return unpack(fdef.shadowColor) end,
	}
end

local fontFileCache = {}
local BUILTIN_WOW_FONTS = {
	["fonts\\frizqt__.ttf"] = true,
	["fonts\\arialn.ttf"] = true,
	["fonts\\morpheus.ttf"] = true,
	["fonts\\skurri.ttf"] = true,
}
local function isValidWowFont(fp)
	if type(fp) ~= "string" or fp == "" then return false end
	local low = fp:lower():gsub("/", "\\")
	if fontFileCache[low] ~= nil then return fontFileCache[low] end
	if BUILTIN_WOW_FONTS[low] then
		fontFileCache[low] = true
		return true
	end
	local rel = fp:gsub("\\", "/"):gsub("^Interface/AddOns/MerchantMaster/", ""):gsub("^interface/addons/merchantmaster/", "")
	local f = io.open(addonDir .. rel, "rb")
	if f then
		f:close()
		fontFileCache[low] = true
		return true
	end
	fontFileCache[low] = false
	return false
end

local STRATA_ORDER = {
	WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3,
	HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
local LAYER_ORDER = {
	BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4,
}

---------------------------------------------------------------------------------------------------
-- Faithful WoW Widget Model & Anchor Constraint Solver
---------------------------------------------------------------------------------------------------
local allWidgets = {}
local nextWidgetId = 0

local function stripWowMarkup(text)
	local s = tostring(text or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local imgPx = 0
	s = s:gsub("|T([^|]+)|t", function(inner)
		local _, w = inner:match(":(%d+):(%d+)")
		imgPx = imgPx + (tonumber(w) or 12)
		return ""
	end)
	return s, imgPx
end

local function makeWidget(frameType, name, parent, template)
	nextWidgetId = nextWidgetId + 1
	local w = {
		_id = nextWidgetId,
		_type = frameType or "Frame",
		_name = name,
		_parent = parent,
		_template = template,
		_shown = true,
		_alpha = 1.0,
		_scale = 1.0,
		_strata = nil,
		_frameLevel = nil,
		_drawLayer = "ARTWORK",
		_subLevel = 0,
		_clipsChildren = false,
		_ignoreParentAlpha = false,
		_ignoreParentScale = false,
		_points = {},
		_regions = {},
		_children = {},
		_scripts = {},
		_events = {},
		_explicitW = nil,
		_explicitH = nil,
		_rect = { left = 0, bottom = 0, right = 0, top = 0 },
		_lastFiredW = nil,
		_lastFiredH = nil,
		_text = "",
		_fontPath = "Fonts\\FRIZQT__.TTF",
		_fontSize = 12,
		_fontFlags = "",
		_textColor = { 1, 1, 1, 1 },
		_shadowOffset = { 0, 0 },
		_shadowColor = { 0, 0, 0, 0 },
		_justifyH = "CENTER",
		_justifyV = "MIDDLE",
		_wordWrap = true,
		_enabled = true,
		_checked = false,
		_vertexColor = { 1, 1, 1, 1 },
		_texCoord = { 0, 1, 0, 1 },
		_blendMode = "BLEND",
	}

	local isRegion = frameType == "Texture" or frameType == "FontString" or frameType == "Line" or frameType == "MaskTexture"
	local ownerList = parent and (isRegion and parent._regions or parent._children)
	if ownerList then
		ownerList[#ownerList + 1] = w
	end
	allWidgets[#allWidgets + 1] = w

	function w:GetName() return self._name end
	function w:GetObjectType() return self._type end
	function w:IsObjectType(t) return self._type == t end
	function w:GetParent() return self._parent end
	function w:SetParent(p)
		if type(p) == "string" then p = _G[p] end
		if self._parent == p then return end
		local oldList = self._parent and (isRegion and self._parent._regions or self._parent._children)
		if oldList then
			for i = #oldList, 1, -1 do
				if oldList[i] == self then table.remove(oldList, i) end
			end
		end
		self._parent = p
		local newList = p and (isRegion and p._regions or p._children)
		if newList then
			newList[#newList + 1] = self
		end
	end
	function w:GetChildren() return unpack(self._children or {}) end
	function w:GetNumChildren() return #(self._children or {}) end
	function w:GetRegions() return unpack(self._regions or {}) end
	function w:GetNumRegions() return #(self._regions or {}) end

	function w:Show()
		local wasShown = self._shown
		self._shown = true
		if not wasShown and self._scripts.OnShow then
			self._scripts.OnShow(self)
		end
	end
	function w:Hide()
		local wasShown = self._shown
		self._shown = false
		if wasShown and self._scripts.OnHide then
			self._scripts.OnHide(self)
		end
	end
	function w:SetShown(b)
		if b then self:Show() else self:Hide() end
	end
	function w:IsShown() return self._shown and true or false end
	function w:IsVisible()
		local cur = self
		while cur do
			if not cur._shown then return false end
			cur = cur._parent
		end
		return true
	end

	function w:SetSize(x, y)
		self._explicitW = tonumber(x)
		self._explicitH = tonumber(y)
	end
	function w:SetWidth(x) self._explicitW = tonumber(x) end
	function w:SetHeight(y) self._explicitH = tonumber(y) end

	function w:GetWidth()
		if self._rect and (self._rect.right - self._rect.left) > 0 then
			return self._rect.right - self._rect.left
		end
		return self._explicitW or 0
	end
	function w:GetHeight()
		if self._rect and (self._rect.top - self._rect.bottom) > 0 then
			return self._rect.top - self._rect.bottom
		end
		return self._explicitH or 0
	end
	function w:GetSize() return self:GetWidth(), self:GetHeight() end
	function w:GetLeft() return self._rect.left end
	function w:GetRight() return self._rect.right end
	function w:GetTop() return self._rect.top end
	function w:GetBottom() return self._rect.bottom end
	function w:GetCenter()
		return (self._rect.left + self._rect.right) * 0.5, (self._rect.bottom + self._rect.top) * 0.5
	end

	function w:ClearAllPoints() self._points = {} end
	function w:SetPoint(point, a2, a3, a4, a5)
		local relTo, relPoint, xOfs, yOfs
		if a2 == nil and a3 == nil and a4 == nil and a5 == nil then
			relTo, relPoint, xOfs, yOfs = self._parent or _G.UIParent, point, 0, 0
		elseif type(a2) == "number" then
			relTo, relPoint, xOfs, yOfs = self._parent or _G.UIParent, point, a2, tonumber(a3) or 0
		else
			relTo = a2 or self._parent or _G.UIParent
			if type(relTo) == "string" then relTo = _G[relTo] or self._parent or _G.UIParent end
			if type(a3) == "number" then
				relPoint, xOfs, yOfs = point, a3, tonumber(a4) or 0
			else
				relPoint = a3 or point
				xOfs = tonumber(a4) or 0
				yOfs = tonumber(a5) or 0
			end
		end
		local entry = { point = point, relTo = relTo, relPoint = relPoint, x = xOfs, y = yOfs }
		for i, p in ipairs(self._points) do
			if p.point == point then
				self._points[i] = entry
				return
			end
		end
		self._points[#self._points + 1] = entry
	end
	function w:SetAllPoints(rel)
		if type(rel) == "string" then rel = _G[rel] end
		local target = rel or self._parent or _G.UIParent
		self._points = {
			{ point = "TOPLEFT", relTo = target, relPoint = "TOPLEFT", x = 0, y = 0 },
			{ point = "BOTTOMRIGHT", relTo = target, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
		}
	end
	function w:GetNumPoints() return #(self._points or {}) end
	function w:GetPoint(i)
		local p = self._points and self._points[i or 1]
		if not p then return nil end
		return p.point, p.relTo, p.relPoint, p.x, p.y
	end

	function w:SetMovable(...) end
	function w:SetResizable(...) end
	function w:SetMinResize(...) end
	function w:SetMaxResize(...) end
	function w:SetResizeBounds(...) end
	function w:SetClampedToScreen(...) end
	function w:SetClampRectInsets(...) end
	function w:EnableMouse(...) end
	function w:EnableMouseWheel(...) end
	function w:RegisterForDrag(...) end
	function w:RegisterForClicks(...) end
	function w:SetAttribute(k, v)
		self._attrs = self._attrs or {}
		self._attrs[k] = v
	end
	function w:GetAttribute(k)
		return self._attrs and self._attrs[k] or nil
	end
	function w:StartMoving() end
	function w:StopMovingOrSizing() end
	function w:SetToplevel(...) end
	function w:Raise() end
	function w:Lower() end
	function w:SetClipsChildren(b) self._clipsChildren = b and true or false end
	function w:DoesClipChildren() return self._clipsChildren end

	function w:SetFrameStrata(s) self._strata = s end
	function w:GetFrameStrata()
		if self._strata then return self._strata end
		if self._parent and self._parent.GetFrameStrata then return self._parent:GetFrameStrata() end
		return "MEDIUM"
	end
	function w:SetFixedFrameStrata(...) end
	function w:SetFrameLevel(lvl) self._frameLevel = tonumber(lvl) or 1 end
	function w:GetFrameLevel()
		if self._frameLevel ~= nil then return self._frameLevel end
		if self._parent and self._parent.GetFrameLevel then return (self._parent:GetFrameLevel() or 0) + 1 end
		return 1
	end
	function w:SetFixedFrameLevel(...) end

	function w:SetAlpha(a) self._alpha = tonumber(a) or 1.0 end
	function w:GetAlpha() return self._alpha end
	function w:SetIgnoreParentAlpha(b) self._ignoreParentAlpha = b and true or false end
	function w:SetIgnoreParentScale(b) self._ignoreParentScale = b and true or false end
	function w:SetScale(s) self._scale = tonumber(s) or 1.0 end
	function w:GetScale() return self._scale end
	function w:GetEffectiveScale()
		if self._ignoreParentScale or not self._parent then return self._scale end
		return self._scale * (self._parent:GetEffectiveScale() or 1.0)
	end

	function w:SetTitle(t) self._title = t end
	function w:SetPortraitToAsset(i) self._portrait = i end
	function w:SetScript(ev, fn) self._scripts[ev] = fn end
	function w:GetScript(ev) return self._scripts[ev] end
	function w:HasScript(ev) return self._scripts[ev] ~= nil end
	function w:HookScript(ev, fn)
		local old = self._scripts[ev]
		self._scripts[ev] = function(...)
			if old then old(...) end
			fn(...)
		end
	end
	function w:RegisterEvent(ev) self._events[ev] = true end
	function w:UnregisterEvent(ev) self._events[ev] = nil end
	function w:UnregisterAllEvents() self._events = {} end
	function w:IsEventRegistered(ev) return self._events[ev] == true end

	-- Backdrop support
	function w:SetBackdrop(bd) self._backdrop = bd end
	function w:GetBackdrop() return self._backdrop end
	function w:SetBackdropColor(r, g, b, a) self._backdropColor = { r or 0, g or 0, b or 0, a or 1 } end
	function w:GetBackdropColor()
		if self._backdropColor then return unpack(self._backdropColor) end
		return 0, 0, 0, 0
	end
	function w:SetBackdropBorderColor(r, g, b, a) self._backdropBorderColor = { r or 1, g or 1, b or 1, a or 1 } end
	function w:GetBackdropBorderColor()
		if self._backdropBorderColor then return unpack(self._backdropBorderColor) end
		return 1, 1, 1, 1
	end

	-- Text & FontString support
	function w:SetText(t)
		self._text = tostring(t or "")
		if self._fs and self._fs ~= self then
			self._fs:SetText(self._text)
		end
		if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
	end
	function w:SetFormattedText(fmt, ...)
		local ok, res = pcall(string.format, tostring(fmt or ""), ...)
		self:SetText(ok and res or tostring(fmt or ""))
	end
	function w:GetText() return self._text end
	function w:GetStringWidth()
		local clean, imgPx = stripWowMarkup(self._text)
		local sz = self._fontSize or 12
		local fp = tostring(self._fontPath or ""):lower()
		local weightScale = (fp:find("semibold", 1, true) or fp:find("bold", 1, true)) and 1.04 or 1.0
		local px = 0
		local i = 1
		local n = #clean
		while i <= n do
			local b = clean:byte(i)
			if b >= 0x80 and b <= 0xBF then
				-- UTF-8 continuation byte: skip so multi-byte middot/dash isn't double-counted
			elseif b >= 0xC0 then
				-- Multi-byte glyph (middot, em-dash, ellipsis, etc.)
				px = px + sz * 0.45
			else
				local ch = clean:sub(i, i)
				if ch:match("[A-ZMW@]") then
					px = px + sz * 0.70 * weightScale
				elseif ch:match("[0-9+]") then
					px = px + sz * 0.62 * weightScale
				elseif ch:match("[iltfjI%.,:;!|%- ]") then
					px = px + sz * 0.33
				else
					px = px + sz * 0.56 * weightScale
				end
			end
			i = i + 1
		end
		return math.ceil(px + imgPx + 3)
	end
	function w:GetStringHeight()
		local sz = self._fontSize or 12
		local _, nl = (self._text or ""):gsub("\n", "\n")
		return math.ceil((nl + 1) * sz * 1.28)
	end
	function w:GetWrappedWidth() return self:GetStringWidth() end
	function w:GetFont() return self._fontPath, self._fontSize, self._fontFlags end
	function w:SetFont(fp, fs, ff)
		if fp ~= nil and not isValidWowFont(fp) then
			return false
		end
		if fp then self._fontPath = fp end
		if fs then self._fontSize = tonumber(fs) or self._fontSize end
		self._fontFlags = ff or ""
		return true
	end
	function w:SetFontObject(fo)
		if type(fo) == "string" then fo = _G[fo] end
		if fo and fo.GetFont then
			local fp, fs, ff = fo:GetFont()
			self:SetFont(fp, fs, ff)
		end
		if fo and fo.GetTextColor then
			local r, g, b, a = fo:GetTextColor()
			self:SetTextColor(r, g, b, a)
		end
		if fo and fo.GetShadowOffset then
			local sx, sy = fo:GetShadowOffset()
			self:SetShadowOffset(sx, sy)
		end
		if fo and fo.GetShadowColor then
			local sr, sg, sb, sa = fo:GetShadowColor()
			self:SetShadowColor(sr, sg, sb, sa)
		end
	end
	function w:SetNormalFontObject(fo) self._normalFontObj = fo end
	function w:SetHighlightFontObject(...) end
	function w:SetDisabledFontObject(...) end
	function w:SetTextColor(r, g, b, a)
		self._textColor = { tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, (a ~= nil) and tonumber(a) or 1 }
	end
	function w:GetTextColor() return unpack(self._textColor) end
	function w:SetShadowColor(r, g, b, a)
		self._shadowColor = { tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0, (a ~= nil) and tonumber(a) or 1 }
	end
	function w:GetShadowColor() return unpack(self._shadowColor or { 0, 0, 0, 0 }) end
	function w:SetShadowOffset(x, y)
		self._shadowOffset = { tonumber(x) or 0, tonumber(y) or 0 }
	end
	function w:GetShadowOffset() return unpack(self._shadowOffset or { 0, 0 }) end
	function w:SetTextInsets(l, r, t, b) self._textInsets = { l or 0, r or 0, t or 0, b or 0 } end
	function w:SetPushedTextOffset(...) end
	function w:SetFontString(fs) self._fs = fs end
	function w:GetFontString()
		if not self._fs and (self._type == "Button" or self._type == "CheckButton") then
			local fs = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			fs:SetPoint("CENTER", self, "CENTER", 0, 0)
			self._fs = fs
		end
		return self._fs
	end
	function w:SetJustifyH(j) self._justifyH = j or "CENTER" end
	function w:GetJustifyH() return self._justifyH end
	function w:SetJustifyV(j) self._justifyV = j or "MIDDLE" end
	function w:GetJustifyV() return self._justifyV end
	function w:SetWordWrap(b) self._wordWrap = b and true or false end
	function w:SetNonSpaceWrap(...) end
	function w:SetMaxLines(n) self._maxLines = n end
	function w:SetIndentedWordWrap(...) end

	-- Button / EditBox / CheckButton state
	function w:SetChecked(b) self._checked = b and true or false end
	function w:GetChecked() return self._checked end
	function w:SetEnabled(b) self._enabled = b and true or false end
	function w:IsEnabled() return self._enabled and true or false end
	function w:Enable() self._enabled = true end
	function w:Disable() self._enabled = false end
	function w:SetButtonState(...) end
	function w:SetAutoFocus(...) end
	function w:SetNumeric(...) end
	function w:SetMaxLetters(...) end
	function w:HasFocus() return false end
	function w:SetFocus() end
	function w:ClearFocus() end
	function w:SetCursorPosition(...) end
	function w:HighlightText(...) end
	function w:SetMultiLine(...) end
	function w:Click(btn)
		if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end
	end

	-- Texture & Line methods
	function w:SetTexture(tex, wrapH, wrapV)
		if type(tex) == "number" then
			self._texturePath = "__fileid:" .. tostring(tex)
		else
			self._texturePath = tex
		end
		self._wrapH = wrapH
		self._wrapV = wrapV
		self._colorTexture = nil
		self._gradient = nil
	end
	function w:GetTexture() return self._texturePath end
	function w:SetColorTexture(r, g, b, a)
		self._colorTexture = { tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1 }
		self._texturePath = nil
		self._gradient = nil
	end
	function w:SetGradient(dir, minC, maxC)
		local r1, g1, b1, a1 = 1, 1, 1, 1
		local r2, g2, b2, a2 = 1, 1, 1, 1
		if type(minC) == "table" then
			if minC.GetRGBA then r1, g1, b1, a1 = minC:GetRGBA() else r1, g1, b1, a1 = minC.r or minC[1] or 1, minC.g or minC[2] or 1, minC.b or minC[3] or 1, (minC.a ~= nil and minC.a) or minC[4] or 1 end
		end
		if type(maxC) == "table" then
			if maxC.GetRGBA then r2, g2, b2, a2 = maxC:GetRGBA() else r2, g2, b2, a2 = maxC.r or maxC[1] or 1, maxC.g or maxC[2] or 1, maxC.b or maxC[3] or 1, (maxC.a ~= nil and maxC.a) or maxC[4] or 1 end
		end
		self._gradient = {
			dir = (dir == "VERTICAL") and "VERTICAL" or "HORIZONTAL",
			min = { tonumber(r1) or 0, tonumber(g1) or 0, tonumber(b1) or 0, (a1 ~= nil) and tonumber(a1) or 1 },
			max = { tonumber(r2) or 0, tonumber(g2) or 0, tonumber(b2) or 0, (a2 ~= nil) and tonumber(a2) or 1 },
		}
		if not self._colorTexture then
			self._colorTexture = { 1, 1, 1, 1 }
		end
	end
	function w:SetGradientAlpha(dir, r1, g1, b1, a1, r2, g2, b2, a2)
		self._gradient = {
			dir = (dir == "VERTICAL") and "VERTICAL" or "HORIZONTAL",
			min = { tonumber(r1) or 0, tonumber(g1) or 0, tonumber(b1) or 0, (a1 ~= nil) and tonumber(a1) or 1 },
			max = { tonumber(r2) or 0, tonumber(g2) or 0, tonumber(b2) or 0, (a2 ~= nil) and tonumber(a2) or 1 },
		}
		if not self._colorTexture then
			self._colorTexture = { 1, 1, 1, 1 }
		end
	end
	function w:SetTexCoord(a, b, c, d, e, f, g, h)
		self._texQuad = nil
		if e ~= nil then
			-- 8-arg form: ulx, uly, blx, bly, urx, ury, brx, bry
			if skinsMode and a == c and e == g and b == f and d == h then
				-- Axis-aligned quad: keep the corner order so mirrored corners (l > r / t > b) survive.
				self._texCoord = { a, e, b, d }
			else
				local l = math.min(a, c, e, g)
				local r = math.max(a, c, e, g)
				local t = math.min(b, d, f, h)
				local bot = math.max(b, d, f, h)
				self._texCoord = { l, r, t, bot }
				-- Rotated / transposed quads keep the raw corners so the previewer can rebuild the transform.
				if skinsMode then self._texQuad = { a, b, c, d, e, f, g, h } end
			end
		else
			self._texCoord = { tonumber(a) or 0, tonumber(b) or 1, tonumber(c) or 0, tonumber(d) or 1 }
		end
	end
	function w:GetTexCoord() return unpack(self._texCoord) end
	function w:SetAtlas(atlas) self._atlas = atlas end
	function w:SetBlendMode(m) self._blendMode = m or "BLEND" end
	function w:SetHorizTile(b) self._horizTile = b and true or false end
	function w:SetVertTile(b) self._vertTile = b and true or false end
	function w:SetVertexColor(r, g, b, a)
		self._vertexColor = { tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1 }
	end
	function w:GetVertexColor() return unpack(self._vertexColor) end
	function w:SetDesaturated(b) self._desaturated = b and true or false end
	function w:SetRotation(rad) self._rotation = tonumber(rad) or 0 end
	function w:SetDrawLayer(layer, sub)
		self._drawLayer = layer or "ARTWORK"
		self._subLevel = tonumber(sub) or 0
	end
	function w:GetDrawLayer() return self._drawLayer, self._subLevel end

	-- Line-specific methods
	function w:SetThickness(t) self._thickness = tonumber(t) or 1 end
	function w:SetStartPoint(pt, relOrX, xOrY, y)
		if type(relOrX) == "number" then
			self._lineStart = { point = pt, relTo = self._parent, x = relOrX, y = tonumber(xOrY) or 0 }
		else
			self._lineStart = { point = pt, relTo = relOrX or self._parent, x = tonumber(xOrY) or 0, y = tonumber(y) or 0 }
		end
	end
	function w:SetEndPoint(pt, relOrX, xOrY, y)
		if type(relOrX) == "number" then
			self._lineEnd = { point = pt, relTo = self._parent, x = relOrX, y = tonumber(xOrY) or 0 }
		else
			self._lineEnd = { point = pt, relTo = relOrX or self._parent, x = tonumber(xOrY) or 0, y = tonumber(y) or 0 }
		end
	end

	-- Texture accessors for Buttons / CheckButtons / Sliders
	function w:SetNormalTexture(t)
		if type(t) == "string" or type(t) == "number" then
			self:GetNormalTexture():SetTexture(t)
		else
			self._normalTex = t
		end
	end
	function w:SetPushedTexture(t)
		if type(t) == "string" or type(t) == "number" then
			self:GetPushedTexture():SetTexture(t)
		else
			self._pushedTex = t
		end
	end
	function w:SetDisabledTexture(t)
		if type(t) == "string" or type(t) == "number" then
			self:GetDisabledTexture():SetTexture(t)
		else
			self._disabledTex = t
		end
	end
	function w:SetHighlightTexture(t)
		if type(t) == "string" or type(t) == "number" then
			self:GetHighlightTexture():SetTexture(t)
		else
			self._highlightTex = t
		end
	end
	function w:GetNormalTexture()
		if not self._normalTex then
			self._normalTex = self:CreateTexture(nil, "BACKGROUND")
			self._normalTex:SetAllPoints(self)
		end
		return self._normalTex
	end
	function w:GetPushedTexture()
		if not self._pushedTex then
			self._pushedTex = self:CreateTexture(nil, "BACKGROUND")
			self._pushedTex:Hide()
		end
		return self._pushedTex
	end
	function w:GetDisabledTexture()
		if not self._disabledTex then
			self._disabledTex = self:CreateTexture(nil, "BACKGROUND")
			self._disabledTex:Hide()
		end
		return self._disabledTex
	end
	function w:GetCheckedTexture()
		if not self._checkedTex then
			self._checkedTex = self:CreateTexture(nil, "ARTWORK")
			self._checkedTex:SetAllPoints(self)
		end
		return self._checkedTex
	end
	function w:GetDisabledCheckedTexture() return self:GetCheckedTexture() end
	function w:GetHighlightTexture()
		if not self._highlightTex then
			self._highlightTex = self:CreateTexture(nil, "HIGHLIGHT")
			self._highlightTex:SetAllPoints(self)
		end
		return self._highlightTex
	end
	function w:GetThumbTexture()
		if not self._thumbTex then
			self._thumbTex = self:CreateTexture(nil, "ARTWORK")
		end
		return self._thumbTex
	end
	function w:SetThumbTexture(t)
		if type(t) == "string" or type(t) == "number" then
			self:GetThumbTexture():SetTexture(t)
		else
			self._thumbTex = t
		end
	end

	-- ScrollFrame / Slider / StatusBar
	function w:SetScrollChild(child)
		self._scrollChild = child
		if child then
			child:SetParent(self)
			child:ClearAllPoints()
			child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		end
	end
	function w:GetScrollChild() return self._scrollChild end
	function w:SetVerticalScroll(v) self._vScroll = tonumber(v) or 0 end
	function w:GetVerticalScroll() return self._vScroll or 0 end
	function w:GetVerticalScrollRange() return 0 end
	function w:UpdateScrollChildRect() end
	function w:SetMinMaxValues(lo, hi) self._minVal, self._maxVal = lo or 0, hi or 100 end
	function w:GetMinMaxValues() return self._minVal or 0, self._maxVal or 100 end
	function w:SetValue(v) self._val = tonumber(v) or 0 end
	function w:GetValue() return self._val or 0 end
	function w:SetValueStep(...) end
	function w:SetObeyStepOnDrag(...) end
	function w:SetOrientation(o) self._orientation = o end
	function w:SetStatusBarTexture(t) self._statusTex = t end
	function w:SetStatusBarColor(...) end

	-- Child region creators
	function w:CreateTexture(n, layer, inherits, sub)
		local t = makeWidget("Texture", n, self, inherits)
		t._drawLayer = layer or "ARTWORK"
		t._subLevel = tonumber(sub) or 0
		return t
	end
	function w:CreateFontString(n, layer, inherits, sub)
		local fs = makeWidget("FontString", n, self, inherits)
		fs._drawLayer = layer or "OVERLAY"
		fs._subLevel = tonumber(sub) or 0
		if inherits then fs:SetFontObject(inherits) end
		return fs
	end
	function w:CreateLine(n, layer, inherits, sub)
		local ln = makeWidget("Line", n, self, inherits)
		ln._drawLayer = layer or "ARTWORK"
		ln._subLevel = tonumber(sub) or 0
		ln._thickness = 1
		return ln
	end
	function w:CreateMaskTexture(n)
		local m = makeWidget("MaskTexture", n, self)
		m._shown = false
		return m
	end
	function w:AddMaskTexture(...) end

	function w:CreateAnimationGroup()
		local ag = {}
		function ag:CreateAnimation()
			local an = {}
			function an:SetOrder(...) end
			function an:SetDuration(...) end
			function an:SetFromAlpha(...) end
			function an:SetToAlpha(...) end
			function an:SetStartDelay(...) end
			function an:SetDegrees(...) end
			function an:SetSmoothing(...) end
			return an
		end
		function ag:SetToFinalAlpha(...) end
		function ag:SetLooping(...) end
		function ag:Play() end
		function ag:Stop() end
		return ag
	end

	-- Template initialization
	if template == "UICheckButtonTemplate" then
		w.Text = w:CreateFontString(name and (name .. "Text") or nil, "OVERLAY", "GameFontNormal")
		w.Text:SetPoint("LEFT", w, "RIGHT", 4, 0)
	elseif template == "UIPanelButtonTemplate" then
		w.Text = w:CreateFontString(name and (name .. "Text") or nil, "OVERLAY", "GameFontNormal")
		w.Text:SetPoint("CENTER", w, "CENTER", 0, 0)
		w._fs = w.Text
	elseif template == "InputBoxTemplate" then
		w.Left = w:CreateTexture(nil, "BACKGROUND")
		w.Middle = w:CreateTexture(nil, "BACKGROUND")
		w.Right = w:CreateTexture(nil, "BACKGROUND")
	elseif template == "PortraitFrameTemplate" then
		w.Bg = w:CreateTexture(nil, "BACKGROUND")
		w.TitleContainer = makeWidget("Frame", nil, w)
		w.TitleContainer.TitleText = w.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	elseif template == "MinimalScrollBar" then
		w.Track = makeWidget("Frame", nil, w)
		w.Track.Thumb = makeWidget("Button", nil, w.Track)
		function w:SetScrollPercentage(...) end
		function w:GetScrollPercentage() return 0 end
		function w:SetVisibleExtentPercentage(...) end
		function w:SetPanExtentPercentage(...) end
		function w:HasScrollableExtent() return false end
		function w:Update(...) end
	end

	if frameType == "GameTooltip" then
		w._lines = {}
		function w:SetOwner(...)
			self._lines = {}
			if select(2, ...) == "ANCHOR_NONE" then
				self._shown = false
			end
		end
		function w:ClearLines() self._lines = {} end
		function w:AddLine(t) self._lines[#self._lines + 1] = tostring(t or "") end
		function w:AddDoubleLine(l, r) self._lines[#self._lines + 1] = tostring(l or "") .. " | " .. tostring(r or "") end
		function w:SetItemByID(id) self._lines[#self._lines + 1] = "Item:" .. tostring(id) end
		function w:SetHyperlink(h) self._lines[#self._lines + 1] = tostring(h) end
		function w:SetBagItem(bag, slot)
			local data = _G.C_TooltipInfo and _G.C_TooltipInfo.GetBagItem and _G.C_TooltipInfo.GetBagItem(bag, slot)
			self._lines = {}
			if data and data.lines then
				for i, ln in ipairs(data.lines) do
					self._lines[i] = ln.leftText or ""
					if self._name then
						local fs = makeWidget("FontString", self._name .. "TextLeft" .. i, self)
						fs._text = self._lines[i]
						_G[self._name .. "TextLeft" .. i] = fs
					end
				end
			end
		end
		function w:NumLines() return #(self._lines or {}) end
	end

	return w
end

_G.UIParent = makeWidget("Frame", "UIParent", nil)
_G.UIParent._explicitW = VIEWPORT_W
_G.UIParent._explicitH = VIEWPORT_H
_G.UIParent._rect = { left = 0, bottom = 0, right = VIEWPORT_W, top = VIEWPORT_H }

_G.Minimap = makeWidget("Frame", "Minimap", _G.UIParent)
_G.Minimap:SetSize(140, 140)
_G.Minimap:SetPoint("TOPRIGHT", _G.UIParent, "TOPRIGHT", -20, -20)
_G.Minimap.GetZoom = function() return 1 end
_G.Minimap.SetZoom = function() end
_G.Minimap:Hide()

_G.GetCursorPosition = function() return 720, 450 end

local scrollBoxes = {}

_G.CreateFrame = function(frameType, name, parent, template)
	if type(parent) == "string" then parent = _G[parent] end
	local f = makeWidget(frameType, name, parent, template)
	if name then _G[name] = f end
	if template == "WowScrollBoxList" then
		f._frames = {}
		f._clipsChildren = true
		scrollBoxes[#scrollBoxes + 1] = f
		local function rebuildScrollRows(self)
			if not self._view or not self._view._initFn or not self._dp then return end
			local items = self._dp:GetCollection()
			local rowH = self._view._h or 22
			local padT = self._view._padT or 0
			local padL = self._view._padL or 0
			local padR = self._view._padR or 0
			local boxH = self:GetHeight()
			if boxH <= 0 then boxH = 520 end
			local calc = self._view._calc
			local yCur = padT
			local rendered = 0
			for i = 1, #items do
				if i > 40 or (rendered > 0 and yCur > boxH + 48) then break end
				local eh = (calc and calc(i, items[i])) or rowH
				if not eh or eh <= 0 then eh = rowH end
				local rowWidget = self._frames[i]
				if not rowWidget then
					rowWidget = makeWidget("Button", nil, self)
					self._frames[i] = rowWidget
				end
				rowWidget:Show()
				rowWidget:ClearAllPoints()
				local yTop = -yCur
				rowWidget:SetPoint("TOPLEFT", self, "TOPLEFT", padL, yTop)
				rowWidget:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padR, yTop)
				rowWidget:SetHeight(eh)
				self._view._initFn(rowWidget, items[i])
				yCur = yCur + eh
				rendered = i
			end
			for i = rendered + 1, #self._frames do
				self._frames[i]:Hide()
			end
		end
		function f:SetDataProvider(dp)
			self._dp = dp
			rebuildScrollRows(self)
		end
		function f:GetDataProvider() return self._dp end
		function f:GetView() return self._view end
		function f:FullUpdate() rebuildScrollRows(self) end
		function f:ScrollToElementDataIndex() end
		function f:GetDerivedScrollOffset() return 0 end
		function f:ForEachFrame(fn)
			for _, fr in ipairs(self._frames or {}) do
				if fr:IsShown() then fn(fr) end
			end
		end
	end
	return f
end

_G.CreateColor = function(r, g, b, a)
	local obj = { r = tonumber(r) or 0, g = tonumber(g) or 0, b = tonumber(b) or 0, a = (a ~= nil) and tonumber(a) or 1 }
	function obj:GetRGBA() return self.r, self.g, self.b, self.a end
	function obj:GetRGB() return self.r, self.g, self.b end
	return obj
end

_G.CreateScrollBoxListLinearView = function()
	local v = { _h = 22, _padT = 0, _padB = 0, _padL = 0, _padR = 0 }
	function v:SetElementExtent(h) self._h = tonumber(h) or 22 end
	function v:SetElementExtentCalculator(fn) self._calc = fn end
	function v:SetElementInitializer(frameType, fn) self._initFn = fn end
	function v:SetPadding(t, b, l, r)
		self._padT, self._padB, self._padL, self._padR = t or 0, b or 0, l or 0, r or 0
	end
	return v
end
_G.ScrollBoxConstants = { RetainScrollPosition = true }
_G.ScrollUtil = {
	InitScrollBoxListWithScrollBar = function(scrollBox, scrollBar, view)
		scrollBox._view = view
		scrollBox._bar = scrollBar
	end,
}
_G.CreateDataProvider = function(list)
	local items = list or {}
	return {
		GetCollection = function() return items end,
		GetSize = function() return #items end,
		Enumerate = function() return ipairs(items) end,
	}
end

_G.GameTooltip = makeWidget("GameTooltip", "GameTooltip", _G.UIParent)
_G.GameTooltip:Hide()
_G.GameTooltip_Hide = function() _G.GameTooltip:Hide() end

---------------------------------------------------------------------------------------------------
-- Anchor Constraint Solver
---------------------------------------------------------------------------------------------------
local function getAnchorXY(rect, pt)
	local l, b, r, t = rect.left, rect.bottom, rect.right, rect.top
	local cx, cy = (l + r) * 0.5, (b + t) * 0.5
	if pt == "TOPLEFT" then return l, t
	elseif pt == "TOP" then return cx, t
	elseif pt == "TOPRIGHT" then return r, t
	elseif pt == "LEFT" then return l, cy
	elseif pt == "CENTER" then return cx, cy
	elseif pt == "RIGHT" then return r, cy
	elseif pt == "BOTTOMLEFT" then return l, b
	elseif pt == "BOTTOM" then return cx, b
	elseif pt == "BOTTOMRIGHT" then return r, b
	end
	return cx, cy
end

local function solveWidgetRect(w)
	if w == _G.UIParent then
		w._rect.left = 0
		w._rect.bottom = 0
		w._rect.right = VIEWPORT_W
		w._rect.top = VIEWPORT_H
		return
	end

	local pts = w._points
	local parent = w._parent or _G.UIParent
	local prect = parent._rect

	local cL, cR, cCX
	local cT, cB, cCY

	if pts and #pts > 0 then
		for _, p in ipairs(pts) do
			local rel = p.relTo or parent
			local rrect = (rel and rel._rect) or prect
			local rx, ry = getAnchorXY(rrect, p.relPoint or p.point)
			local tx = rx + (p.x or 0)
			local ty = ry + (p.y or 0)
			local pt = p.point
			if pt == "TOPLEFT" or pt == "LEFT" or pt == "BOTTOMLEFT" then cL = tx
			elseif pt == "TOP" or pt == "CENTER" or pt == "BOTTOM" then if not cCX then cCX = tx end
			elseif pt == "TOPRIGHT" or pt == "RIGHT" or pt == "BOTTOMRIGHT" then cR = tx
			end
			if pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT" then cT = ty
			elseif pt == "LEFT" or pt == "CENTER" or pt == "RIGHT" then if not cCY then cCY = ty end
			elseif pt == "BOTTOMLEFT" or pt == "BOTTOM" or pt == "BOTTOMRIGHT" then cB = ty
			end
		end
	end

	local ew = w._explicitW
	local eh = w._explicitH
	if w._type == "FontString" then
		-- In WoW, SetWidth(0) / SetHeight(0) clears an explicit constraint so the FontString auto-sizes to its text.
		if ew ~= nil and ew <= 0 then ew = nil end
		if eh ~= nil and eh <= 0 then eh = nil end
		w._constrainedW = (ew ~= nil) or (cL ~= nil and cR ~= nil)
		if not ew and not (cL and cR) then
			ew = math.max(1, w:GetStringWidth())
		end
		if not eh and not (cT and cB) then
			eh = math.max(12, w:GetStringHeight())
		end
	end

	local left, right
	if cL and cR then
		left, right = cL, cR
	elseif cL then
		left = cL
		right = cL + (ew or 0)
	elseif cR then
		right = cR
		left = cR - (ew or 0)
	elseif cCX then
		local hw = (ew or 0) * 0.5
		left, right = cCX - hw, cCX + hw
	else
		left = prect.left
		right = left + (ew or 0)
	end

	local bottom, top
	if cT and cB then
		bottom, top = cB, cT
	elseif cT then
		top = cT
		bottom = cT - (eh or 0)
	elseif cB then
		bottom = cB
		top = cB + (eh or 0)
	elseif cCY then
		local hh = (eh or 0) * 0.5
		bottom, top = cCY - hh, cCY + hh
	else
		top = prect.top
		bottom = top - (eh or 0)
	end

	if right < left then right = left end
	if top < bottom then top = bottom end

	w._rect.left = left
	w._rect.right = right
	w._rect.bottom = bottom
	w._rect.top = top
end

local function solveLayout(fireSizeChanged)
	for pass = 1, 20 do
		for i = 1, #allWidgets do
			solveWidgetRect(allWidgets[i])
		end
	end
	if fireSizeChanged then
		for i = 1, #allWidgets do
			local w = allWidgets[i]
			if w._scripts and w._scripts.OnSizeChanged then
				local nw = w:GetWidth()
				local nh = w:GetHeight()
				if w._lastFiredW ~= nw or w._lastFiredH ~= nh then
					w._lastFiredW, w._lastFiredH = nw, nh
					pcall(w._scripts.OnSizeChanged, w, nw, nh)
				end
			end
		end
		for pass = 1, 12 do
			for i = 1, #allWidgets do
				solveWidgetRect(allWidgets[i])
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Seed Game Environment (Horde / Normal, Alchemy 300 / Herbalism 300, Honored, Snapshots, Ledger)
---------------------------------------------------------------------------------------------------
_G.Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		return { _frame = frame, _name = name, GetID = function() return 99 end }
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}

_G.Enum = {
	GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 },
	AuctionHouseSortOrder = { Price = 0, Buyout = 1, Bid = 2, Quantity = 3, Name = 4, Level = 5, TimeRemaining = 6 },
	ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
	UIMapType = { World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 },
}
_G.C_GameRules = { IsGameRuleActive = function() return false end }
_G.UnitFactionGroup = function() return "Horde" end
_G.GetRealmName = function() return "Forever" end
_G.UnitName = function() return "Grommash" end
_G.GetCVar = function(k)
	if k == "Portal" then return "EU" end
	if k == "rotateMinimap" then return "0" end
	return "1"
end
_G.IsLoggedIn = function() return true end
_G.UnitPosition = function() return 0, 0, 0, 0 end

_G.MapCanvasDataProviderMixin = { GetMap = function(self) return self.map end }
_G.MapCanvasPinMixin = {}
_G.CreateFramePool = function() return {} end
_G.C_Map = {
	GetMapInfo = function() return nil end,
	GetMapChildrenInfo = function() return {} end,
	GetWorldPosFromMapPos = function() return nil, nil end,
	GetBestMapForUnit = function() return 1411 end,
}
_G.WorldMapFrame = makeWidget("Frame", "WorldMapFrame", _G.UIParent)
_G.WorldMapFrame:Hide()
_G.WorldMapFrame.pinPools = {}
_G.WorldMapFrame.GetCanvas = function(self) return self end
_G.WorldMapFrame.GetMapID = function() return 1411 end
_G.WorldMapFrame.AddDataProvider = function(self, p) p.map = self end

-- Alchemy 300/300 & Herbalism 300/300
_G.GetProfessions = function() return 1, 2, nil, nil, nil, nil end
_G.GetProfessionInfo = function(idx)
	if idx == 1 then return "Alchemy", 136240, 300, 300, 0, 0, 171 end
	if idx == 2 then return "Herbalism", 136065, 300, 300, 0, 0, 182 end
end
_G.GetNumSkillLines = function() return 2 end
_G.GetSkillLineInfo = function(i)
	if i == 1 then return "Alchemy", false, false, 300, 0, 0, 300 end
	if i == 2 then return "Herbalism", false, false, 300, 0, 0, 300 end
end
_G.IsPlayerSpell = function(spellID)
	if spellID == 2259 or spellID == 2366 then return true end
	return (_G.MerchantMasterDB and _G.MerchantMasterDB.learnedSpells and _G.MerchantMasterDB.learnedSpells[spellID] == true) or false
end
_G.IsSpellKnown = _G.IsPlayerSpell

-- Durotar Supply: Honored 4,850 / 12,000; Favor = 142
_G.C_Reputation = {
	GetFactionDataByID = function(fid)
		if fid ~= 2586 and fid ~= 2587 then return nil end
		return {
			factionID = fid,
			name = fid == 2586 and "Azeroth Commerce Authority" or "Durotar Supply and Logistics",
			reaction = 6,
			currentReactionThreshold = 9000,
			nextReactionThreshold = 21000,
			currentStanding = 13850,
		}
	end,
}
_G.GetFactionInfoByID = function(fid)
	if fid ~= 2586 and fid ~= 2587 then return nil end
	local name = (fid == 2586) and "Azeroth Commerce Authority" or "Durotar Supply and Logistics"
	return name, "", 6, 9000, 21000, 13850
end
_G.C_CurrencyInfo = {
	GetCurrencyInfo = function(cid)
		if cid == 3402 then return { quantity = 142, iconFileID = 237281 } end
	end,
}
local nsRef = nil
-- --skins scenes only: GetItemIcon returns real WoW icon texture paths (Interface\Icons\*) so the previewer
-- can paint the matching icon PNG. Default dumps keep the numeric fileIDs (byte-identical Standard output).
local skinIcons = false
local SKIN_ICON_BY_ID = {
	[248682] = "INV_Crate_03",                   -- Waylaid Crate
	[13463] = "INV_Misc_Herb_Dreamfoil",         -- Dreamfoil
	[13465] = "INV_Misc_Herb_MountainSilversage", -- Mountain Silversage
	[8838] = "INV_Misc_Herb_18",                 -- Sungrass
	[13468] = "INV_Misc_Herb_BlackLotus",        -- Black Lotus
	[3371] = "INV_Drink_05",                     -- Empty Vial
	[3372] = "INV_Drink_05",                     -- Leaded Vial
	[8925] = "INV_Drink_05",                     -- Crystal Vial
	[13454] = "INV_Potion_25",                   -- Greater Arcane Elixir
	[13452] = "INV_Potion_32",                   -- Elixir of the Mongoose
	[13453] = "INV_Potion_40",                   -- Elixir of Brute Force
	[13442] = "INV_Potion_83",                   -- Mighty Rage Potion
	[13457] = "INV_Potion_24",                   -- Greater Fire Protection Potion
	[274275] = "INV_Potion_100",                 -- Flask of Natural Precision (synthetic preview icon)
	[13446] = "INV_Potion_54",                   -- Major Healing Potion
	[13444] = "INV_Potion_76",                   -- Major Mana Potion
	[13512] = "INV_Potion_41",                   -- Flask of Supreme Power
	[13521] = "INV_Scroll_03",                   -- Recipe: Flask of Supreme Power
	[6050] = "INV_Potion_32",                    -- Frost Oil
	[6049] = "INV_Potion_32",
	[10504] = "INV_Misc_Lens_01",                -- Green Lens
	[11176] = "INV_Enchant_DustDream",           -- Dream Dust
	[11178] = "INV_Enchant_ShardRadiantLarge",   -- Large Radiant Shard
	[4304] = "INV_Misc_LeatherScrap_02",         -- Thick Leather
}
local SKIN_POTION_ICONS = { "INV_Potion_32", "INV_Potion_25", "INV_Potion_76", "INV_Potion_54", "INV_Potion_41", "INV_Potion_80" }
local function guessSkinIconPath(numId, low)
	local base = SKIN_ICON_BY_ID[numId]
	if not base then
		if low:find("crate", 1, true) then base = "INV_Crate_03"
		elseif low:find("vial", 1, true) then base = "INV_Drink_05"
		elseif low:find("writ", 1, true) then base = "INV_Scroll_05"
		elseif low:find("lens", 1, true) or low:find("goggle", 1, true) then base = "INV_Misc_Lens_01"
		elseif low:find("recipe", 1, true) or low:find("pattern", 1, true) or low:find("plans", 1, true)
			or low:find("formula", 1, true) or low:find("schematic", 1, true) or low:find("manual", 1, true)
			or low:find("scroll", 1, true) then base = "INV_Scroll_03"
		elseif low:find("lotus", 1, true) then base = "INV_Misc_Herb_BlackLotus"
		elseif low:find("foil", 1, true) then base = "INV_Misc_Herb_Dreamfoil"
		elseif low:find("sage", 1, true) then base = "INV_Misc_Herb_MountainSilversage"
		elseif low:find("sungrass", 1, true) or low:find("bloom", 1, true) or low:find("grass", 1, true)
			or low:find("root", 1, true) or low:find("moss", 1, true) or low:find("weed", 1, true)
			or low:find("leaf", 1, true) or low:find("thorn", 1, true) or low:find("kelp", 1, true)
			or low:find("tear", 1, true) or low:find("mushroom", 1, true) or low:find("gromsblood", 1, true)
			or low:find("sansam", 1, true) or low:find("herb", 1, true) then base = "INV_Misc_Herb_07"
		elseif low:find("cloth", 1, true) or low:find("bolt", 1, true) or low:find("linen", 1, true)
			or low:find("silk", 1, true) or low:find("wool", 1, true) or low:find("mageweave", 1, true)
			or low:find("runecloth", 1, true) or low:find("hood", 1, true) or low:find("robe", 1, true)
			or low:find("cuff", 1, true) or low:find("sandal", 1, true) then base = "INV_Fabric_Linen_01"
		elseif low:find("hide", 1, true) or low:find("leather", 1, true) or low:find("glove", 1, true)
			or low:find("bracer", 1, true) or low:find("belt", 1, true) or low:find("boot", 1, true)
			or low:find("cloak", 1, true) or low:find("pants", 1, true) or low:find("legging", 1, true)
			or low:find("gauntlet", 1, true) or low:find("helm", 1, true) or low:find("plate", 1, true)
			or low:find("shoulder", 1, true) then base = "INV_Misc_LeatherScrap_02"
		elseif low:find("hammer", 1, true) or low:find("blade", 1, true) or low:find("sword", 1, true)
			or low:find("axe", 1, true) or low:find("mace", 1, true) or low:find("staff", 1, true) then base = "INV_Weapon_Blade_01"
		elseif low:find("flame", 1, true) or low:find("fire", 1, true) or low:find("sac", 1, true) then base = "INV_Potion_24"
		elseif low:find("oil", 1, true) or low:find("frost", 1, true) then base = "INV_Potion_83"
		elseif low:find("water", 1, true) or low:find("snapper", 1, true) or low:find("fish", 1, true) then base = "INV_Potion_100"
		elseif low:find("essence", 1, true) or low:find("dust", 1, true) or low:find("shard", 1, true) then base = "INV_Potion_25"
		else base = SKIN_POTION_ICONS[(numId % #SKIN_POTION_ICONS) + 1] end
	end
	return "Interface\\Icons\\" .. base
end
local function guessItemIconByID(id)
	local numId = tonumber(id)
	if not numId then return skinIcons and "Interface\\Icons\\INV_Misc_QuestionMark" or 134400 end
	local nm = (nsRef and nsRef.ITEM_NAMES_BY_ID and nsRef.ITEM_NAMES_BY_ID[numId]) or ""
	local low = tostring(nm):lower()
	if skinIcons then return guessSkinIconPath(numId, low) end
	if low:find("crate", 1, true) then return 236994 end
	if low:find("vial", 1, true) then return 134715 end
	if low:find("writ", 1, true) or low:find("recipe", 1, true) or low:find("pattern", 1, true)
		or low:find("plans", 1, true) or low:find("formula", 1, true) or low:find("schematic", 1, true)
		or low:find("manual", 1, true) or low:find("scroll", 1, true) then
		return 134939
	end
	if low:find("foil", 1, true) or low:find("sage", 1, true) or low:find("lotus", 1, true)
		or low:find("bloom", 1, true) or low:find("grass", 1, true) or low:find("root", 1, true)
		or low:find("moss", 1, true) or low:find("weed", 1, true) or low:find("leaf", 1, true)
		or low:find("thorn", 1, true) or low:find("kelp", 1, true) or low:find("tear", 1, true)
		or low:find("mushroom", 1, true) or low:find("gromsblood", 1, true) or low:find("sansam", 1, true)
		or low:find("herb", 1, true) then
		return 134187
	end
	return 134830
end
_G.C_Item = {
	GetItemInfo = function(idOrLink)
		local id = tonumber(idOrLink) or tonumber(tostring(idOrLink or ""):match("item:(%d+)"))
		if id == 13463 then return "Dreamfoil", nil, 1, 55, 0, "Trade Goods", "Herb", 20, "", 134187, 250, 7, 9, 0 end
		if id == 13465 then return "Mountain Silversage", nil, 1, 55, 0, "Trade Goods", "Herb", 20, "", 134187, 300, 7, 9, 0 end
		if id == 8838 then return "Sungrass", nil, 1, 45, 0, "Trade Goods", "Herb", 20, "", 134187, 150, 7, 9, 0 end
		if id == 13452 then return "Elixir of the Mongoose", nil, 1, 55, 46, "Consumable", "Elixir", 20, "", 134812, 500, 0, 2, 0 end
		if id == 248682 then return "Waylaid Crate: Apprentice Herbs", nil, 2, 20, 0, "Consumable", "Other", 1, "", 236994, 50, 0, 8, 0 end
		return nil
	end,
	GetItemIconByID = guessItemIconByID,
	RequestLoadItemDataByID = function() end,
	DoesItemExist = function(loc)
		if type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil then
			return _G.C_Container and _G.C_Container.GetContainerItemInfo(loc.bagID, loc.slotIndex) ~= nil
		end
		return false
	end,
}
_G.GetItemInfo = _G.C_Item.GetItemInfo
_G.GetItemIcon = guessItemIconByID

_G.ItemLocation = {
	CreateFromBagAndSlot = function(a, b, c)
		local bag, slot
		if type(a) == "table" then bag, slot = b, c else bag, slot = a, b end
		return {
			bagID = bag,
			slotIndex = slot,
			IsBagAndSlot = function() return true end,
			GetBagAndSlot = function(self) return self.bagID, self.slotIndex end,
		}
	end,
}

_G.NUM_BAG_SLOTS = 4
local BAG_ITEMS = {
	[1] = { itemID = 248682, stackCount = 1, iconFileID = 236994, name = "Waylaid Crate: Apprentice Herbs" },
	[2] = { itemID = 13463,  stackCount = 40, iconFileID = 134187, name = "Dreamfoil" },
	[3] = { itemID = 13465,  stackCount = 24, iconFileID = 134187, name = "Mountain Silversage" },
	[4] = { itemID = 8838,   stackCount = 30, iconFileID = 134187, name = "Sungrass" },
	[5] = { itemID = 3371,   stackCount = 20, iconFileID = 134715, name = "Empty Vial" },
	[6] = { itemID = 8925,   stackCount = 20, iconFileID = 134715, name = "Crystal Vial" },
	[7] = { itemID = 3372,   stackCount = 12, iconFileID = 134715, name = "Leaded Vial" },
}
_G.C_Container = {
	GetContainerNumSlots = function(b) return b == 0 and #BAG_ITEMS or 0 end,
	GetContainerNumFreeSlots = function(b) return b == 0 and 12 or 0, 0 end,
	GetContainerItemInfo = function(b, s)
		if b == 0 and BAG_ITEMS[s] then
			local it = BAG_ITEMS[s]
			return {
				itemID = it.itemID,
				stackCount = it.stackCount,
				iconFileID = it.iconFileID,
				hyperlink = "|cffffffff|Hitem:" .. it.itemID .. "::::::::60:::::|h[" .. it.name .. "]|h|r",
			}
		end
	end,
}
_G.C_TooltipInfo = {
	GetBagItem = function(b, s)
		if b == 0 and s == 1 then
			return {
				lines = {
					{ leftText = "Waylaid Crate: Apprentice Herbs" },
					{ leftText = "Use: Fill the crate with any bundle from the following list:\n- 20 Peacebloom\n- 20 Silverleaf\n- 10 Earthroot" },
				},
			}
		end
	end,
}
_G.C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy", skillLevel = 300, maxSkillLevel = 300 } end,
	GetAllRecipeIDs = function() return {} end,
	GetRecipeInfo = function() return nil end,
}

local DUMP_OWNED_AUCTIONS = {
	{
		auctionID = 9001,
		itemKey = { itemID = 13463, itemLevel = 0, itemSuffix = 0 },
		itemLink = "|cffffffff|Hitem:13463::::::::60:::::|h[Dreamfoil]|h|r",
		quantity = 20,
		buyoutAmount = 14800,
		bidAmount = 0,
		timeLeftSeconds = 42000,
		status = 0,
	},
	{
		auctionID = 9002,
		itemKey = { itemID = 13465, itemLevel = 0, itemSuffix = 0 },
		itemLink = "|cffffffff|Hitem:13465::::::::60:::::|h[Mountain Silversage]|h|r",
		quantity = 10,
		buyoutAmount = 19500,
		bidAmount = 0,
		timeLeftSeconds = 39600,
		status = 0,
	},
	{
		auctionID = 9003,
		itemKey = { itemID = 248682, itemLevel = 20, itemSuffix = 0 },
		itemLink = "|cff1eff00|Hitem:248682::::::::60:::::|h[Waylaid Crate: Apprentice Herbs]|h|r",
		quantity = 1,
		buyoutAmount = 42000,
		bidAmount = 35000,
		bidder = "OtherBuyer",
		timeLeftSeconds = 21600,
		status = 0,
	},
	{
		auctionID = 9004,
		itemKey = { itemID = 8838, itemLevel = 0, itemSuffix = 0 },
		itemLink = "|cffffffff|Hitem:8838::::::::60:::::|h[Sungrass]|h|r",
		quantity = 15,
		buyoutAmount = 9200,
		bidAmount = 0,
		timeLeftSeconds = 36000,
		status = 0,
	},
}

_G.IsUsingLegacyAuctionClient = function() return false end
_G.C_AuctionHouse = {
	IsThrottledMessageSystemReady = function() return true end,
	IsUsingLegacyAuctionClient = function() return false end,
	SendBrowseQuery = function() end,
	SendSearchQuery = function() end,
	SendSellSearchQuery = function() end,
	GetBrowseResults = function() return {} end,
	HasFullBrowseResults = function() return true end,
	MakeItemKey = function(id, itemLevel, itemSuffix)
		return { itemID = id, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0 }
	end,
	GetItemKeyFromItem = function(loc)
		if type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil then
			local info = _G.C_Container.GetContainerItemInfo(loc.bagID, loc.slotIndex)
			if info and info.itemID then return { itemID = info.itemID, itemLevel = 0, itemSuffix = 0 } end
		end
		return nil
	end,
	HasSearchResults = function() return true end,
	GetItemKeyInfo = function(k)
		local id = type(k) == "table" and k.itemID or nil
		local isComm = id ~= 248682
		local nm = (nsRef and nsRef.ITEM_NAMES_BY_ID and id and nsRef.ITEM_NAMES_BY_ID[id]) or "Item"
		return { itemName = nm, isCommodity = isComm, quality = isComm and 1 or 2, iconFileID = guessItemIconByID(id) }
	end,
	IsSellItemValid = function(loc) return _G.C_Item.DoesItemExist(loc) end,
	GetItemCommodityStatus = function(loc)
		if type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil then
			local info = _G.C_Container.GetContainerItemInfo(loc.bagID, loc.slotIndex)
			if info and info.itemID == 248682 then return _G.Enum.ItemCommodityStatus.Item end
		end
		return _G.Enum.ItemCommodityStatus.Commodity
	end,
	GetAvailablePostCount = function(loc)
		if type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil and _G.C_Container then
			local info = _G.C_Container.GetContainerItemInfo(loc.bagID, loc.slotIndex)
			if not info or not info.itemID then return 0 end
			local total = 0
			for b = 0, (_G.NUM_BAG_SLOTS or 4) do
				local n = _G.C_Container.GetContainerNumSlots(b) or 0
				for s = 1, n do
					local ci = _G.C_Container.GetContainerItemInfo(b, s)
					if ci and ci.itemID == info.itemID then
						total = total + (tonumber(ci.stackCount) or 1)
					end
				end
			end
			return total
		end
		return 0
	end,
	CalculateItemDeposit = function() return 150 end,
	CalculateCommodityDeposit = function(_, _, qty) return 100 * math.max(1, tonumber(qty) or 1) end,
	PostItem = function() return false end,
	PostCommodity = function() return false end,
	ConfirmPostItem = function() end,
	ConfirmPostCommodity = function() end,
	QueryOwnedAuctions = function() end,
	GetNumOwnedAuctions = function() return #DUMP_OWNED_AUCTIONS end,
	GetOwnedAuctionInfo = function(idx) return DUMP_OWNED_AUCTIONS[idx] end,
	CancelAuction = function() end,
	CanCancelAuction = function() return true end,
	GetCancelCost = function(auctionID) return auctionID == 9003 and 1750 or 0 end,
	GetNumCommoditySearchResults = function() return 3 end,
	GetCommoditySearchResultInfo = function(_, idx)
		if idx == 1 then return { quantity = 40, unitPrice = 14500, numOwnerItems = 0 }
		elseif idx == 2 then return { quantity = 60, unitPrice = 14800, numOwnerItems = 20 }
		elseif idx == 3 then return { quantity = 100, unitPrice = 15200, numOwnerItems = 0 } end
		return nil
	end,
	HasFullCommoditySearchResults = function() return true end,
	GetNumItemSearchResults = function() return 1 end,
	GetItemSearchResultInfo = function(_, idx)
		if idx == 1 then return { auctionID = 9003, buyoutAmount = 42000, quantity = 1, containsOwnerItem = true } end
		return nil
	end,
	HasFullItemSearchResults = function() return true end,
}

_G.MailFrame = makeWidget("Frame", "MailFrame", _G.UIParent)
_G.MailFrame:SetSize(338, 424)
_G.MailFrame:Hide()
_G.CheckInbox = function() end
_G.GetInboxNumItems = function() return 0, 0 end
_G.GetInboxHeaderInfo = function() return nil end
_G.GetInboxInvoiceInfo = function() return nil end
_G.TakeInboxMoney = function() end
_G.AutoLootMailItem = function() end
_G.BuyTrainerService = function() end
_G.GetTrainerServiceInfo = function() return nil end
_G.GetTrainerServiceCost = function() return 0 end
_G.DepositGuildBankMoney = function() end
_G.WithdrawGuildBankMoney = function() end
_G.GetGuildInfo = function() return "Horde Guild" end

_G.AuctionHouseFrame = makeWidget("Frame", "AuctionHouseFrame", _G.UIParent)
_G.AuctionHouseFrame:Hide()
_G.AuctionHouseFrame.SearchBar = makeWidget("Frame", nil, _G.AuctionHouseFrame)
_G.AuctionHouseFrame.SearchBar.FilterButton = makeWidget("Button", nil, _G.AuctionHouseFrame.SearchBar)
_G.AuctionHouseFrame.SearchBar.SearchBox = makeWidget("EditBox", nil, _G.AuctionHouseFrame.SearchBar)

_G.WaylaidCratesDB = { minimap = { minimapPos = 215 }, chars = {} }

---------------------------------------------------------------------------------------------------
-- Load MerchantMaster Addon in Exact TOC Order
---------------------------------------------------------------------------------------------------
local ns = {}
nsRef = ns
local tocFh = assert(io.open(addonDir .. "MerchantMaster.toc", "r"))
local tocFiles = {}
for line in tocFh:lines() do
	local rel = line:gsub("\r", ""):match("^%s*([^#%s].-)%s*$")
	if rel and rel:match("%.lua$") then
		tocFiles[#tocFiles + 1] = rel
	end
end
tocFh:close()

for _, rel in ipairs(tocFiles) do
	local chunk, err = loadfile(addonDir .. rel)
	assert(chunk, "Compile failed for " .. rel .. ": " .. tostring(err))
	chunk("MerchantMaster", ns)
end

-- Seed rich realistic standalone prices across Alchemy, Reagents, Crates, and Writs
local seedPrices = {
	-- Alchemy outputs (high demand + monopolies)
	[13454] = { min = 79500, mkt = 82000, num = 6,  spd = 18.4 }, -- Greater Arcane Elixir
	[13444] = { min = 41500, mkt = 43000, num = 14, spd = 42.0 }, -- Major Mana Potion
	[13452] = { min = 68400, mkt = 71000, num = 8,  spd = 31.2 }, -- Elixir of Mongoose
	[5634]  = { min = 24200, mkt = 26000, num = 5,  spd = 26.5 }, -- Free Action Potion
	[13453] = { min = 112000, mkt = 118000, num = 0, spd = 4.2 }, -- Elixir of Brute Force (monopoly)
	[13512] = { min = 265000, mkt = 278000, num = 1, spd = 2.8 }, -- Flask of Supreme Power
	[13442] = { min = 68500, mkt = 71500, num = 2,  spd = 8.4 },  -- Mighty Rage Potion
	[13446] = { min = 18500, mkt = 19200, num = 22, spd = 54.0 }, -- Major Healing Potion
	[13457] = { min = 44500, mkt = 46800, num = 9,  spd = 14.5 }, -- Greater Fire Protection Potion
	[13456] = { min = 36500, mkt = 38000, num = 7,  spd = 11.2 }, -- Greater Frost Protection Potion
	-- Reagents
	[13463] = { min = 4200,  mkt = 4400,  num = 48, spd = 190 },  -- Dreamfoil
	[13465] = { min = 6800,  mkt = 7100,  num = 34, spd = 160 },  -- Mountain Silversage
	[13464] = { min = 3100,  mkt = 3300,  num = 40, spd = 140 },  -- Golden Sansam
	[13466] = { min = 2800,  mkt = 3000,  num = 28, spd = 110 },  -- Plaguebloom
	[13467] = { min = 2900,  mkt = 3100,  num = 30, spd = 120 },  -- Icecap
	[13468] = { min = 68000, mkt = 72000, num = 4,  spd = 12 },   -- Black Lotus
	[8838]  = { min = 1800,  mkt = 1950,  num = 50, spd = 160 },  -- Sungrass
	[8839]  = { min = 2100,  mkt = 2250,  num = 36, spd = 95 },   -- Blindweed
	[8845]  = { min = 1600,  mkt = 1750,  num = 22, spd = 70 },   -- Ghost Mushroom
	[8846]  = { min = 2400,  mkt = 2600,  num = 18, spd = 65 },   -- Gromsblood
	[3821]  = { min = 370,   mkt = 410,   num = 569, spd = 80 },  -- Goldthorn
	[3819]  = { min = 1000,  mkt = 1100,  num = 182, spd = 64 },  -- Wintersbite
	[6050]  = { min = 2623,  mkt = 2800,  num = 229, spd = 9.21 }, -- Frost Protection Potion
	[6049]  = { min = 3850,  mkt = 4100,  num = 41, spd = 6.4 },  -- Fire Protection Potion
	[6371]  = { min = 2400,  mkt = 2550,  num = 17, spd = 11.5 }, -- Fire Oil (cheaper to craft)
	[6359]  = { min = 180,   mkt = 195,   num = 240, spd = 130 }, -- Firefin Snapper
	[4402]  = { min = 1450,  mkt = 1500,  num = 9,  spd = 21 },   -- Small Flame Sac (stock short)
	[3358]  = { min = 1400,  mkt = 1550,  num = 30, spd = 90 },   -- Khadgar's Whisker
	[2447]  = { min = 45,    mkt = 52,    num = 80, spd = 300 },  -- Peacebloom
	[765]   = { min = 42,    mkt = 48,    num = 75, spd = 280 },  -- Silverleaf
	[2449]  = { min = 68,    mkt = 75,    num = 45, spd = 150 },  -- Earthroot
	[3371]  = { min = 5,     mkt = 5,     num = 99, spd = 999 },  -- Empty Vial
	[3372]  = { min = 36,    mkt = 36,    num = 99, spd = 999 },  -- Leaded Vial
	[8925]  = { min = 50,    mkt = 50,    num = 99, spd = 999 },  -- Crystal Vial
	-- Waylaid Crates & Bundle items
	[248682] = { min = 900,  mkt = 950,   num = 14, spd = 15 },
	[248702] = { min = 380,  mkt = 420,   num = 18, spd = 22 },
	[2589]   = { min = 12,   mkt = 14,    num = 120, spd = 600 }, -- Linen Cloth
	[2996]   = { min = 45,   mkt = 50,    num = 60, spd = 180 },  -- Bolt of Linen Cloth
	[4234]   = { min = 640,  mkt = 680,   num = 45, spd = 140 },  -- Heavy Leather
	[4235]   = { min = 1280, mkt = 1350,  num = 20, spd = 45 },   -- Heavy Hide
}

local seededAhPrices = { _scannedAt = simTime - 480 }
local seededVelocity = {}
for id, p in pairs(seedPrices) do
	seededAhPrices[id] = { price = p.min, qty = p.num, absent = (p.num == 0), at = simTime - 480 }
	seededVelocity[id] = p.spd
end
if ns.ITEM_NAMES_BY_ID then
	for id, _ in pairs(ns.ITEM_NAMES_BY_ID) do
		if not seededAhPrices[id] then
			local base = 250 + (id % 47) * 185
			seededAhPrices[id] = { price = base, qty = 2 + (id % 15), at = simTime - 480 }
			seededVelocity[id] = 1.5 + (id % 18) * 0.8
		end
	end
end
do
	local origGetDailySold = ns.GetDailySold
	ns.GetDailySold = function(id)
		if seededVelocity[id] ~= nil then return seededVelocity[id] end
		return origGetDailySold and origGetDailySold(id) or nil
	end
end

---------------------------------------------------------------------------------------------------
-- Seed SavedVariables (MerchantMasterDB, MerchantMasterLedgerDB)
---------------------------------------------------------------------------------------------------
_G.MerchantMasterDB = {
	window = { width = 1840, height = 730, scale = 1.0, widthVersion = 2 },
	themeMode = "dark",
	uiThemeMode = "dark",
	economy = "Normal-Horde",
	crateMode = "cheapest",
	applyAHCut = true,
	knownRecipesOnly = false,
	unlockFilter = "mine_profs",
	profFilter = "all",
	merchantVendorOnly = false,
	calcRespectStock = true,
	superListSources = {},
	ahPrices = {
		["Normal-Horde"] = seededAhPrices,
	},
	liveVendorBuyGlobal = {
		[3371] = { basePrice = 5, limited = false },
		[3372] = { basePrice = 36, limited = false },
		[8925] = { basePrice = 50, limited = false },
	},
	shoppingList = {
		{ key = "seed:13463", itemID = 13463, name = "Dreamfoil", qty = 60, sourceLabel = "Alchemy" },
		{ key = "seed:13465", itemID = 13465, name = "Mountain Silversage", qty = 35, sourceLabel = "Alchemy" },
		{ key = "seed:13468", itemID = 13468, name = "Black Lotus", qty = 2, sourceLabel = "Alchemy" },
		{ key = "seed:8925",  itemID = 8925,  name = "Crystal Vial", qty = 40, sourceLabel = "NPC Vendor", isVendor = true, source = "vendor" },
	},
	learnedSpells = {
		[17573] = true, -- Greater Arcane Elixir
		[17580] = true, -- Major Mana Potion
		[17571] = true, -- Elixir of the Mongoose
		[6624]  = true, -- Free Action Potion
		[17556] = true, -- Major Healing Potion
		[17574] = true, -- Greater Fire Protection Potion
		[17575] = true, -- Greater Frost Protection Potion
	},
	lastRefreshAt = simTime - 480,
	professor = {
		selectedProf = "alchemy",
		fromSkill = 1,
		toSkill = 300,
		respectBags = true,
		preferCheap = true,
	},
}

-- Seed 14 days of Analytics Ledger transactions & wealth snapshots
local ledgerEvents = {}
local ledgerSnapshots = {}
local charKey = "Grommash - Forever"
local runningGold = 14800000
for dayIdx = 13, 0, -1 do
	local ts = simTime - dayIdx * 86400
	local dayProfit = 380000 + ((dayIdx * 73) % 29) * 18000
	runningGold = runningGold + dayProfit
	ledgerSnapshots[#ledgerSnapshots + 1] = {
		ts = ts,
		day = os.date("%Y-%m-%d", ts),
		char = charKey,
		gold = runningGold,
		inventory = 4200000 + dayIdx * 85000,
		auctions = 1950000,
	}
	ledgerEvents[#ledgerEvents + 1] = {
		id = #ledgerEvents + 1,
		ts = ts + 3600,
		kind = "SALE",
		category = "CRAFT_SALE",
		char = charKey,
		itemID = 13454,
		itemName = "Greater Arcane Elixir",
		qty = 6,
		amount = 477000,
		cost = 248000,
		source = "AH",
	}
	ledgerEvents[#ledgerEvents + 1] = {
		id = #ledgerEvents + 1,
		ts = ts + 7200,
		kind = "PURCHASE",
		category = "MAT_BUY",
		char = charKey,
		itemID = 13463,
		itemName = "Dreamfoil",
		qty = 40,
		amount = -168000,
		source = "AH",
	}
end

_G.MerchantMasterLedgerDB = {
	version = 1,
	events = ledgerEvents,
	snapshots = ledgerSnapshots,
	investments = {
		{ id = 1, name = "Black Lotus Stockpile", itemID = 13468, qty = 8, cost = 512000, ts = simTime - 86400 * 5 },
		{ id = 2, name = "Dreamfoil Reserve", itemID = 13463, qty = 200, cost = 760000, ts = simTime - 86400 * 3 },
	},
	writs = {
		{ ts = simTime - 86400, itemID = 13446, name = "Artisan Writ: Major Healing Potion", cost = 7480, reward = 7900, rep = 200 },
	},
}

---------------------------------------------------------------------------------------------------
-- Fire ADDON_LOADED & PLAYER_LOGIN
---------------------------------------------------------------------------------------------------
for _, w in ipairs(allWidgets) do
	if w._events and w._events.ADDON_LOADED and w._scripts and w._scripts.OnEvent then
		w._scripts.OnEvent(w, "ADDON_LOADED", "MerchantMaster")
	end
end
drainTimers(500)

for _, w in ipairs(allWidgets) do
	if w._events and w._events.PLAYER_LOGIN and w._scripts and w._scripts.OnEvent then
		w._scripts.OnEvent(w, "PLAYER_LOGIN")
	end
end
drainTimers(500)

-- Populate real Analytics Store ledger events and wealth snapshots
if ns.Analytics and ns.Analytics.Store then
	local Store = ns.Analytics.Store
	if Store.Init then Store.Init() end
	local char, econ = Store.CurrentCharAndEcon()
	local runningGold = 14800000
	for dayIdx = 13, 0, -1 do
		local ts = simTime - dayIdx * 86400
		local dayKey = Store.DayKey(ts)
		local profit = 420000 + ((dayIdx * 37) % 19) * 24000
		runningGold = runningGold + profit
		Store.Append({
			time = ts + 1800,
			type = "AH_BUY",
			char = char,
			econ = econ,
			itemID = 13463,
			qty = 40,
			unit = 4200,
			total = -168000,
			where = "Orgrimmar",
			skipRecon = true,
			extra = { name = "Dreamfoil" },
		})
		Store.Append({
			time = ts + 2400,
			type = "CRAFT",
			char = char,
			econ = econ,
			itemID = 13454,
			qty = 10,
			unit = 41500,
			total = 0,
			cogs = 415000,
			where = "Orgrimmar",
			skipRecon = true,
			extra = { name = "Greater Arcane Elixir", reagentCost = 415000 },
		})
		local saleQty1 = 4 + ((dayIdx * 5 + 3) % 11)
		local saleQty2 = 6 + ((dayIdx * 3 + 1) % 13)
		Store.Append({
			time = ts + 5400,
			type = "AH_SELL",
			char = char,
			econ = econ,
			itemID = 13454,
			qty = saleQty1,
			unit = 79500,
			total = saleQty1 * 75525,
			cogs = saleQty1 * 41500,
			where = "Orgrimmar",
			skipRecon = true,
			extra = { name = "Greater Arcane Elixir", gross = saleQty1 * 79500, fee = saleQty1 * 3975 },
		})
		Store.Append({
			time = ts + 7200,
			type = "AH_SELL",
			char = char,
			econ = econ,
			itemID = 13444,
			qty = saleQty2,
			unit = 41500,
			total = saleQty2 * 39425,
			cogs = saleQty2 * 24200,
			where = "Orgrimmar",
			skipRecon = true,
			extra = { name = "Major Mana Potion", gross = saleQty2 * 41500, fee = saleQty2 * 2075 },
		})
		if dayIdx % 3 == 0 then
			Store.Append({
				time = ts + 9000,
				type = "CRATE_TURNIN",
				char = char,
				econ = econ,
				itemID = 248682,
				qty = 1,
				unit = 1280,
				total = 5000,
				where = "Durotar",
				skipRecon = true,
				extra = { name = "Crate: Apprentice Herbs", favor = 10, rep = 200 },
			})
		end
		Store.SaveSnapshot(char, dayKey, {
			gold = runningGold,
			items = 3400000 + (14 - dayIdx) * 90000,
			listed = 1950000,
			bags = 1200000,
			bank = 2200000 + (14 - dayIdx) * 90000,
			mail = 0,
			econ = econ,
		})
	end
end

-- Ensure app panel is shown and centered inside 1920x960
local app = ns.app
assert(app and app.panel and app.setTab, "MerchantMaster ns.app must initialize cleanly")

local function flushPendingLayout()
	solveLayout(false)
	if app.ui and app.ui.winChrome and app.ui.winChrome.window then
		local win = app.ui.winChrome.window
		if win.pulse and win.pulse._scripts and win.pulse._scripts.OnUpdate then
			pcall(win.pulse._scripts.OnUpdate, win.pulse, 0.1)
		end
	end
	if app.layoutWindow then pcall(app.layoutWindow) end
	solveLayout(true)
end

app.panel:ClearAllPoints()
app.panel:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
app.panel:Show()
flushPendingLayout()
drainTimers(500)

---------------------------------------------------------------------------------------------------
-- Scene Dumper
---------------------------------------------------------------------------------------------------
local function isEffectivelyVisible(w)
	local cur = w
	while cur do
		if not cur._shown then return false end
		cur = cur._parent
	end
	return true
end

local function effectiveAlpha(w)
	local a = w._alpha or 1.0
	local cur = w
	while cur and cur._parent and not cur._ignoreParentAlpha do
		cur = cur._parent
		a = a * (cur._alpha or 1.0)
	end
	return a
end

local function emitClipBox(w)
	local cur = w._parent
	local cL, cB, cR, cT
	while cur do
		if cur._clipsChildren and cur._rect then
			local r = cur._rect
			cL = cL and math.max(cL, r.left) or r.left
			cB = cB and math.max(cB, r.bottom) or r.bottom
			cR = cR and math.min(cR, r.right) or r.right
			cT = cT and math.min(cT, r.top) or r.top
		end
		cur = cur._parent
	end
	if not cL then return nil end
	if cR < cL then cR = cL end
	if cT < cB then cT = cB end
	return {
		x = cL,
		y = VIEWPORT_H - cT,
		w = math.max(0, cR - cL),
		h = math.max(0, cT - cB),
	}
end

local function dumpScene(sceneName, winFrameOverride, extraMeta)
	if onlyScenes and not onlyScenes[sceneName] then
		return
	end
	if cartAhOnly and not (sceneName:sub(1, 10) == "live-cart-" or sceneName:sub(1, 13) == "live-ahbuyer-" or sceneName:sub(1, 5) == "flow-") then
		return
	end
	solveLayout(true)
	-- Re-sync scrollboxes to solved dimensions
	for _, sb in ipairs(scrollBoxes) do
		if isEffectivelyVisible(sb) and sb._dp then
			sb:FullUpdate()
		end
	end
	solveLayout(true)

	-- Collect visible frames & regions in WoW draw order
	local orderIndex = {}
	for idx, w in ipairs(allWidgets) do
		orderIndex[w] = idx
	end

	local function getStrataRank(w)
		return STRATA_ORDER[w:GetFrameStrata()] or 3
	end

	-- Gather all visible draw primitives with sort keys:
	-- (strataRank, frameLevel, ownerOrder, drawLayerRank, subLevel, isTextOrBackdrop, regionOrder)
	local items = {}

	-- No CSS backdrop-filter tagging: WoW cannot blur behind a frame, so previews composite only
	-- what the client really draws (the baked Liquid Glass .tga substrate + lensing layers).

	for idx, w in ipairs(allWidgets) do
		local isRegion = (w._type == "Texture" or w._type == "FontString" or w._type == "Line" or w._type == "MaskTexture")
		if not isRegion and isEffectivelyVisible(w) then
			local alpha = effectiveAlpha(w)
			local r = w._rect
			local x = r.left
			local y = VIEWPORT_H - r.top
			local ww = math.max(0, r.right - r.left)
			local hh = math.max(0, r.top - r.bottom)
			local strata = getStrataRank(w)
			local lvl = w:GetFrameLevel() or 1


			if alpha > 0.001 and ww > 0 and hh > 0 and w._backdrop then
				local bgc = w._backdropColor or { 0, 0, 0, 0 }
				local bdc = w._backdropBorderColor or { 1, 1, 1, 0 }
				if (bgc[4] or 0) > 0.001 or (bdc[4] or 0) > 0.001 then
					items[#items + 1] = {
						kind = "backdrop",
						id = w._id,
						name = w._name,
						x = x, y = y, w = ww, h = hh,
						alpha = alpha,
						bgColor = bgc,
						borderColor = bdc,
						edgeSize = w._backdrop.edgeSize or 1,
						clip = emitClipBox(w),
						__s1 = strata, __s2 = lvl, __s3 = idx, __s4 = -1, __s5 = -1, __s6 = 0, __s7 = 0,
					}
				end
			end

			if alpha > 0.001 and w._type == "EditBox" and w._text and w._text ~= "" and ww > 0 and hh > 0 then
				local ins = w._textInsets or { 0, 0, 0, 0 }
				local padL = tonumber(ins[1]) or 6
				local padR = tonumber(ins[2]) or 6
				local padT = tonumber(ins[3]) or 0
				local padB = tonumber(ins[4]) or 0
				local ew = math.max(1, ww - padL - padR)
				local eh = math.max(1, hh - padT - padB)
				items[#items + 1] = {
					kind = "text",
					id = w._id * 100000 + 1,
					x = x + padL, y = y + padT, w = ew, h = eh,
					alpha = alpha,
					text = w._text,
					fontSize = w._fontSize or 11,
					fontPath = w._fontPath,
					fontFlags = w._fontFlags,
					color = w._textColor or { 0.96, 0.96, 0.98, 1 },
					shadowOffset = w._shadowOffset or { 0, 0 },
					shadowColor = w._shadowColor or { 0, 0, 0, 0 },
					constrainedW = true,
					justifyH = (w._justifyH and w._justifyH ~= "CENTER") and w._justifyH or "LEFT",
					justifyV = "MIDDLE",
					wordWrap = false,
					clip = emitClipBox(w),
					__s1 = strata, __s2 = lvl, __s3 = idx, __s4 = 1, __s5 = 3, __s6 = 1, __s7 = 9999,
				}
			end

			if alpha > 0.001 and w._regions then
				for rIdx, reg in ipairs(w._regions) do
					if reg._shown and reg._drawLayer ~= "HIGHLIGHT" then
						local rAlpha = alpha * (reg._alpha or 1.0)
						if rAlpha > 0.001 then
							local rr = reg._rect
							local rx = rr.left
							local ry = VIEWPORT_H - rr.top
							local rw = math.max(0, rr.right - rr.left)
							local rh = math.max(0, rr.top - rr.bottom)
							local layerRank = LAYER_ORDER[reg._drawLayer or "ARTWORK"] or 2
							local subLvl = reg._subLevel or 0

							if reg._type == "Texture" and rw > 0 and rh > 0 then
								if reg._colorTexture then
									local emitColor = reg._colorTexture
									local emitGrad = nil
									if reg._gradient and reg._gradient.min and reg._gradient.max then
										local gMin, gMax = reg._gradient.min, reg._gradient.max
										emitGrad = { dir = reg._gradient.dir, min = gMin, max = gMax }
										emitColor = {
											(gMin[1] + gMax[1]) * 0.5,
											(gMin[2] + gMax[2]) * 0.5,
											(gMin[3] + gMax[3]) * 0.5,
											(gMin[4] + gMax[4]) * 0.5,
										}
									end
									items[#items + 1] = {
										kind = "color",
										id = reg._id,
										x = rx, y = ry, w = rw, h = rh,
										alpha = rAlpha,
										color = emitColor,
										gradient = emitGrad,
										blend = reg._blendMode,
										clip = emitClipBox(reg),
										__s1 = strata, __s2 = lvl, __s3 = idx, __s4 = 0, __s5 = layerRank, __s6 = subLvl, __s7 = rIdx,
									}
								elseif reg._texturePath then
									items[#items + 1] = {
										kind = "texture",
										id = reg._id,
										x = rx, y = ry, w = rw, h = rh,
										alpha = rAlpha,
										texture = reg._texturePath,
										texCoord = reg._texCoord,
										vertexColor = reg._vertexColor,
										blend = reg._blendMode,
										desaturated = reg._desaturated or false,
										rotation = reg._rotation or 0,
										horizTile = (skinsMode and reg._horizTile) or nil,
										vertTile = (skinsMode and reg._vertTile) or nil,
										wrapH = (skinsMode and reg._wrapH) or nil,
										wrapV = (skinsMode and reg._wrapV) or nil,
										texQuad = (skinsMode and reg._texQuad) or nil,
										clip = emitClipBox(reg),
										__s1 = strata, __s2 = lvl, __s3 = idx, __s4 = 0, __s5 = layerRank, __s6 = subLvl, __s7 = rIdx,
									}
								end
							elseif reg._type == "FontString" and reg._text and reg._text ~= "" then
								items[#items + 1] = {
									kind = "text",
									id = reg._id,
									x = rx, y = ry, w = math.max(1, rw), h = math.max(1, rh),
									alpha = rAlpha,
									text = reg._text,
									fontSize = reg._fontSize or 12,
									fontPath = reg._fontPath,
									fontFlags = reg._fontFlags,
									color = reg._textColor,
									shadowOffset = reg._shadowOffset or { 0, 0 },
									shadowColor = reg._shadowColor or { 0, 0, 0, 0 },
									constrainedW = reg._constrainedW and true or false,
									justifyH = reg._justifyH or "CENTER",
									justifyV = reg._justifyV or "MIDDLE",
									wordWrap = reg._wordWrap and true or false,
									clip = emitClipBox(reg),
									__s1 = strata, __s2 = lvl, __s3 = idx, __s4 = 1, __s5 = layerRank, __s6 = subLvl, __s7 = rIdx,
								}
							elseif reg._type == "Line" and reg._lineStart and reg._lineEnd then
								local sRel = (reg._lineStart.relTo and reg._lineStart.relTo._rect) or r
								local eRel = (reg._lineEnd.relTo and reg._lineEnd.relTo._rect) or r
								local sx, sy = getAnchorXY(sRel, reg._lineStart.point or "BOTTOMLEFT")
								local ex, ey = getAnchorXY(eRel, reg._lineEnd.point or "BOTTOMLEFT")
								sx = sx + (reg._lineStart.x or 0)
								sy = sy + (reg._lineStart.y or 0)
								ex = ex + (reg._lineEnd.x or 0)
								ey = ey + (reg._lineEnd.y or 0)
								items[#items + 1] = {
									kind = "line",
									id = reg._id,
									x1 = sx, y1 = VIEWPORT_H - sy,
									x2 = ex, y2 = VIEWPORT_H - ey,
									thickness = reg._thickness or 1.5,
									alpha = rAlpha,
									color = reg._colorTexture or reg._vertexColor or { 1, 1, 1, 1 },
									clip = emitClipBox(reg),
									__s1 = strata, __s2 = lvl, __s3 = idx, __s4 = 0, __s5 = layerRank, __s6 = subLvl, __s7 = rIdx,
								}
							end
						end
					end
				end
			end
		end
	end

	table.sort(items, function(a, b)
		if a.__s1 ~= b.__s1 then return a.__s1 < b.__s1 end
		if a.__s2 ~= b.__s2 then return a.__s2 < b.__s2 end
		if a.__s3 ~= b.__s3 then return a.__s3 < b.__s3 end
		if a.__s5 ~= b.__s5 then return a.__s5 < b.__s5 end
		if a.__s6 ~= b.__s6 then return a.__s6 < b.__s6 end
		if a.__s4 ~= b.__s4 then return a.__s4 < b.__s4 end
		return a.__s7 < b.__s7
	end)
	if sceneName == "audit-writs-dark" or sceneName == "audit-writs-light" or sceneName == "writs-cd-dark" then
		local found = { ready = false, fourteenHours = false, fiveHours = false, thirtyFiveMinutes = false }
		for _, item in ipairs(items) do
			if item.kind == "text" then
				local text = tostring(item.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
				found.ready = found.ready or text == "R"
				found.fourteenHours = found.fourteenHours or text == "14h"
				found.fiveHours = found.fiveHours or text == "5h"
				found.thirtyFiveMinutes = found.thirtyFiveMinutes or text == "35m"
			end
		end
		assert(found.ready and found.fiveHours and found.thirtyFiveMinutes
			and (sceneName ~= "writs-cd-dark" or found.fourteenHours),
			"Writ scene must export ready, 5h, 35m, and its requested cooldown sample: " .. sceneName)
	end

	local mode = (ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode()) or "dark"
	local winFrame = winFrameOverride or app.panel
	local pRect = winFrame._rect
	local rawW = pRect.right - pRect.left
	local rawH = pRect.top - pRect.bottom
	local pScale = (winFrame.GetScale and winFrame:GetScale()) or 1.0
	if math.abs(pScale - 1.0) > 1e-4 then
		-- Center scaled panel cleanly inside viewport
		local rawCx = (pRect.left + pRect.right) * 0.5
		local rawCy = VIEWPORT_H - (pRect.bottom + pRect.top) * 0.5
		local dstCx = VIEWPORT_W * 0.5
		local dstCy = VIEWPORT_H * 0.5
		local function tx(x) return dstCx + (x - rawCx) * pScale end
		local function ty(y) return dstCy + (y - rawCy) * pScale end
		for _, it in ipairs(items) do
			if it.kind == "line" then
				it.x1 = tx(it.x1); it.y1 = ty(it.y1)
				it.x2 = tx(it.x2); it.y2 = ty(it.y2)
				it.thickness = (it.thickness or 1.5) * pScale
			else
				it.x = tx(it.x); it.y = ty(it.y)
				it.w = it.w * pScale; it.h = it.h * pScale
				if it.fontSize then it.fontSize = it.fontSize * pScale end
			end
			if it.clip then
				it.clip.x = tx(it.clip.x); it.clip.y = ty(it.clip.y)
				it.clip.w = it.clip.w * pScale; it.clip.h = it.clip.h * pScale
			end
		end
	end
	local winW = rawW * pScale
	local winH = rawH * pScale
	local payload = {
		scene = sceneName,
		mode = mode,
		-- Only skinned dumps carry a skin key; Standard scenes stay byte-identical (renderer defaults to "standard").
		skin = (function()
			local sk = ns.Theme and ns.Theme.GetSkin and ns.Theme.GetSkin() or nil
			if sk and (skinsMode or sk ~= "standard") then return sk end
			return nil
		end)(),
		viewport = { w = VIEWPORT_W, h = VIEWPORT_H },
		window = {
			x = (VIEWPORT_W - winW) * 0.5,
			y = (VIEWPORT_H - winH) * 0.5,
			w = winW,
			h = winH,
		},
		items = items,
	}
	payload.items.__json_array = true
	if type(extraMeta) == "table" then
		for mk, mv in pairs(extraMeta) do payload[mk] = mv end
	end

	local outPath = outDir .. "/" .. sceneName .. ".json"
	local fh = assert(io.open(outPath, "w"))
	fh:write(encodeJson(payload))
	fh:close()
	print(string.format("[lua_frame_dump] %s -> %s (%d draw items, win=%.0fx%.0f scale=%.3f)",
		sceneName, outPath, #items, rawW, rawH, pScale))
end

---------------------------------------------------------------------------------------------------
-- Capture All 6 Required Views
---------------------------------------------------------------------------------------------------
local function setThemeMode(mode)
	if ns.Theme and ns.Theme.SetSkin and ns.Theme.GetSkin and ns.Theme.GetSkin() ~= "standard" then
		ns.Theme.SetSkin("standard")
	end
	if _G.MerchantMasterDB then _G.MerchantMasterDB.uiThemeMode = mode end
	if ns.Theme and ns.Theme.SetMode then
		ns.Theme.SetMode(mode)
	end
	if app.ui and app.ui.appearanceSwitch and app.ui.appearanceSwitch.UpdateTheme then
		app.ui.appearanceSwitch.UpdateTheme()
	end
	if app.refresh then app.refresh() end
	drainTimers(500)
	flushPendingLayout()
end

local dumpWindowWidth, dumpWindowHeight = 1840, 730
local function switchTab(tabKey)
	if tabKey ~= "recipes" and _G.MerchantMasterDB and _G.MerchantMasterDB.window then
		_G.MerchantMasterDB.window.width = dumpWindowWidth
		_G.MerchantMasterDB.window.height = dumpWindowHeight
		if app.ui and app.ui.winChrome and app.ui.winChrome.window then
			app.ui.winChrome.window:SetMinimumWidth(1320)
			app.ui.winChrome.window:ApplyFull()
		end
	end
	app.setTab(tabKey)
	drainTimers(3000)
	flushPendingLayout()
	if app.refresh then app.refresh() end
	drainTimers(3000)
	app.panel:ClearAllPoints()
	app.panel:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
	flushPendingLayout()
end

local withVendorCrafterSeed

if not cartAhOnly and not onlyScenes then
-- 1. overview-dark
setThemeMode("dark")
switchTab("dashboard")
dumpScene("overview-dark")

-- 2. overview-light
setThemeMode("light")
switchTab("dashboard")
dumpScene("overview-light")

-- 3. market-dark (Daily Crafts / profit_spread)
setThemeMode("dark")
switchTab("profit_spread")
dumpScene("market-dark")

-- 4. market-light
setThemeMode("light")
switchTab("profit_spread")
dumpScene("market-light")

-- 5. market-allrecipes-dark (All Recipes)
setThemeMode("dark")
switchTab("recipes")
dumpScene("market-allrecipes-dark")

-- 6. market-allrecipes-light (All Recipes Light)
setThemeMode("light")
switchTab("recipes")
dumpScene("market-allrecipes-light")

-- 6v. vendor-crafter-dark / vendor-crafter-light (Vendor Crafter with seeded profitable recipes, shared reagents, vendor loop & Row 3 Profit Maximizer)
withVendorCrafterSeed = function(fn)
	local db = _G.MerchantMasterDB
	local econ = ns.CurrentEconomyInfo().effectiveKey
	local priorMC = db.vendorCrafterMasterChef
	local priorBarter = db.vendorCrafterBartering
	local priorHonored = db.vendorCrafterHonored
	local priorMoat = db.vendorCrafterMoatFilter
	local priorTopN = db.vendorCrafterTopN
	local priorMaxCrafts = db.vendorCrafterMaxCrafts
	local priorBudget = db.vendorCrafterBudget
	local priorTopOnly = db.vendorCrafterTopOnly
	local priorProf = db.profFilter
	local priorUnlock = db.unlockFilter
	local priorKnown = db.knownRecipesOnly
	local priorSearch = app.ui and app.ui.searchBox and app.ui.searchBox:GetText() or ""
	local priorAhLots = db.ahLots
	local priorLiveEcon = db.ahPrices and db.ahPrices[econ]
	local priorPoisonSell = ns.ITEM_VENDOR_SELL and ns.ITEM_VENDOR_SELL[5237]
	local savedMin, savedMkt, savedNum = {}, {}, {}

	local vcSeed = {
		-- Heavy Kodo Stew (12215, Cooking, numMade=2, sell=300 -> avgVendor=900 at MC 5/5): Deep moat
		[12204] = { min = 180, mkt = 190, num = 240, lots = { { price = 180, qty = 120 }, { price = 240, qty = 80 }, { price = 500, qty = 40 } } },
		-- Tender Wolf Steak (18045, Cooking, numMade=1, sell=300 -> avgVendor=450 at MC 5/5): Steady moat
		[12208] = { min = 160, mkt = 175, num = 57, lots = { { price = 160, qty = 22 }, { price = 260, qty = 15 }, { price = 420, qty = 20 } } },
		-- Monster Omelet (12218, Cooking, numMade=1, sell=300 -> avgVendor=450 at MC 5/5): Thin moat
		[12207] = { min = 90, mkt = 105, num = 18, lots = { { price = 90, qty = 8 }, { price = 260, qty = 10 } } },
		-- Undermine Clam Chowder (16766, Cooking, numMade=2, sell=100 -> avgVendor=300 at MC 5/5): Moment (flash dip)
		[7974]  = { min = 60, mkt = 200, num = 36, lots = { { price = 60, qty = 6 }, { price = 220, qty = 30 } } },
		-- Patterned Bronze Bracers (2868) & Big Bronze Knife (3848) sharing Bronze Bar (2841) multi-tier AH lots!
		[2841]  = { min = 45, mkt = 48, num = 450, lots = { { price = 45, qty = 350 }, { price = 90, qty = 100 }, { price = 140, qty = 80 } } },
		[3478]  = { min = 25, mkt = 28, num = 250, lots = { { price = 25, qty = 200 }, { price = 60, qty = 50 } } },
		[3470]  = { min = 15, mkt = 18, num = 200, lots = { { price = 15, qty = 150 }, { price = 40, qty = 50 } } },
		[818]   = { min = 100, mkt = 110, num = 60, lots = { { price = 100, qty = 40 }, { price = 220, qty = 20 } } },
		[2319]  = { min = 50, mkt = 55, num = 80, lots = { { price = 50, qty = 60 }, { price = 120, qty = 20 } } },
		-- Major Healing Potion (13446, Alchemy, sell=1000): Steady moat
		[13464] = { min = 220, mkt = 235, num = 140, lots = { { price = 220, qty = 80 }, { price = 380, qty = 60 } } },
		[13465] = { min = 280, mkt = 295, num = 70, lots = { { price = 280, qty = 40 }, { price = 520, qty = 30 } } },
	}

	local liveCopy = {}
	for k, v in pairs(priorLiveEcon or {}) do liveCopy[k] = v end
	local lotsEcon = {}
	for itemID, spec in pairs(vcSeed) do
		liveCopy[itemID] = { price = spec.min, qty = spec.num, at = simTime - 60 }
		lotsEcon[itemID] = { at = simTime - 60, lots = spec.lots }
	end
	liveCopy._scannedAt = simTime - 60

	-- Temporarily elevate Mind-numbing Poison (5237, pure vendor reagents) sell value so a live Vendor Loop (Inf) showcases in dumps
	if ns.ITEM_VENDOR_SELL then ns.ITEM_VENDOR_SELL[5237] = 140 end

	db.ahPrices = db.ahPrices or {}
	db.ahPrices[econ] = liveCopy
	db.ahLots = { [econ] = lotsEcon }
	db.vendorCrafterMasterChef = 5
	db.vendorCrafterBartering = 2
	db.vendorCrafterHonored = false
	db.vendorCrafterMoatFilter = "all"
	db.vendorCrafterTopN = 10
	db.vendorCrafterMaxCrafts = 0
	db.vendorCrafterBudget = 0
	db.vendorCrafterTopOnly = false
	db.profFilter = "all"
	db.unlockFilter = "all"
	db.knownRecipesOnly = false
	if app.ui and app.ui.searchBox then app.ui.searchBox:SetText("") end
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	if ns.VendorCrafterModel and ns.VendorCrafterModel.ClearCache then ns.VendorCrafterModel.ClearCache() end
	if app.vendorCrafterProvider and app.vendorCrafterProvider.Invalidate then app.vendorCrafterProvider.Invalidate("all") end

	local ok, err = pcall(fn)

	if ns.ITEM_VENDOR_SELL then ns.ITEM_VENDOR_SELL[5237] = priorPoisonSell end
	db.ahPrices[econ] = priorLiveEcon
	db.ahLots = priorAhLots
	db.vendorCrafterMasterChef = priorMC
	db.vendorCrafterBartering = priorBarter
	db.vendorCrafterHonored = priorHonored
	db.vendorCrafterMoatFilter = priorMoat
	db.vendorCrafterTopN = priorTopN
	db.vendorCrafterMaxCrafts = priorMaxCrafts
	db.vendorCrafterBudget = priorBudget
	db.vendorCrafterTopOnly = priorTopOnly
	db.profFilter = priorProf
	db.unlockFilter = priorUnlock
	db.knownRecipesOnly = priorKnown
	if app.ui and app.ui.searchBox then app.ui.searchBox:SetText(priorSearch) end
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	if ns.VendorCrafterModel and ns.VendorCrafterModel.ClearCache then ns.VendorCrafterModel.ClearCache() end
	if app.vendorCrafterProvider and app.vendorCrafterProvider.Invalidate then app.vendorCrafterProvider.Invalidate("all") end
	if not ok then error(err, 0) end
end

withVendorCrafterSeed(function()
	setThemeMode("dark")
	switchTab("vendor_crafter")
	local view = app.ui and app.ui.vendorCrafterView
	local tbl = app.ui and app.ui.vendorCrafterTable
	local col = tbl and tbl.scrollBox and tbl.scrollBox._dp and tbl.scrollBox._dp:GetCollection() or {}
	assert(#col >= 4, "vendor-crafter-dark must render seeded profitable rows, got " .. tostring(#col))
	assert(view and view.activePlan and (view.activePlan.recipeCount or 0) >= 4 and (view.activePlan.vendorLoopCount or 0) >= 1,
		"vendor-crafter-dark must populate Row 3 Profit Maximizer plan with >=4 recipes and >=1 vendor loop")
	assert(view.planSummaryFs and (view.planSummaryFs:GetText() or "") ~= "" and view.planSummaryFs:GetText() ~= "No active plan",
		"vendor-crafter-dark must display populated Row 3 planSummaryFs")
	dumpScene("vendor-crafter-dark")

	setThemeMode("light")
	switchTab("vendor_crafter")
	dumpScene("vendor-crafter-light")
end)

-- 6a. market-allrecipes-columns-dark (All Recipes Dark with Column Customizer popover + hovered traffic lights)
do
	setThemeMode("dark")
	switchTab("recipes")
	if ns.SuperList and ns.SuperList.ToggleColumnSettings then
		ns.SuperList.ToggleColumnSettings(true)
	end
	if app.ui and app.ui.trafficLights and app.ui.trafficLights.SetHovered then
		app.ui.trafficLights.SetHovered(true)
	end
	flushPendingLayout()
	dumpScene("market-allrecipes-columns-dark")
	if ns.SuperList and ns.SuperList.ToggleColumnSettings then
		ns.SuperList.ToggleColumnSettings(false)
	end
	if app.ui and app.ui.trafficLights and app.ui.trafficLights.SetHovered then
		app.ui.trafficLights.SetHovered(false)
	end
end

-- 6b/6c. market-allrecipes-shift-dark / light (Shift-hold quick-add mode with 2 queued recipes)
do
	local tbl = app.ui and app.ui.recipesTable
	local col = tbl and tbl.scrollBox and tbl.scrollBox._dp and tbl.scrollBox._dp:GetCollection() or {}
	local q1, q2 = col[1], col[3] or col[2]
	local oldShift = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	if q1 and app.adjustRecipeShoppingQty then app.adjustRecipeShoppingQty(q1, 2) end
	if q2 and app.adjustRecipeShoppingQty then app.adjustRecipeShoppingQty(q2, 1) end

	setThemeMode("dark")
	switchTab("recipes")
	if ns.SuperList and ns.SuperList.SetShiftMode then ns.SuperList.SetShiftMode(true) end
	flushPendingLayout()
	dumpScene("market-allrecipes-shift-dark")

	setThemeMode("light")
	switchTab("recipes")
	if ns.SuperList and ns.SuperList.SetShiftMode then ns.SuperList.SetShiftMode(true) end
	flushPendingLayout()
	dumpScene("market-allrecipes-shift-light")

	if ns.SuperList and ns.SuperList.SetShiftMode then ns.SuperList.SetShiftMode(false) end
	_G.IsShiftKeyDown = oldShift
	if _G.MerchantMasterDB and type(_G.MerchantMasterDB.craftOrderQueue) == "table" then
		wipe(_G.MerchantMasterDB.craftOrderQueue)
	end
	if app.syncUnifiedShoppingList then app.syncUnifiedShoppingList() end
	if ns.SuperList and ns.SuperList.RepaintVisible then ns.SuperList.RepaintVisible() end
end

-- 6d. minimized-dark (Collapsed 72px top-bar mode via orange traffic light, with seeded cart pill)
do
	setThemeMode("dark")
	switchTab("dashboard")
	if _G.MerchantMasterDB then
		_G.MerchantMasterDB.craftOrderQueue = {
			{ spellID = 7258, outputItemID = 6050, prof = "alchemy", qty = 4 },
		}
	end
	if app.syncUnifiedShoppingList then app.syncUnifiedShoppingList() end
	local minBtn = app.ui and app.ui.trafficLights and app.ui.trafficLights.minBtn
	if minBtn and minBtn.Click then
		minBtn:Click("LeftButton")
	elseif app.setMinimized then
		app.setMinimized(true)
	end
	if app.ui and app.ui.trafficLights and app.ui.trafficLights.SetHovered then
		app.ui.trafficLights.SetHovered(true)
	end
	drainTimers(500)
	flushPendingLayout()
	dumpScene("minimized-dark")
	if app.ui and app.ui.trafficLights and app.ui.trafficLights.SetHovered then
		app.ui.trafficLights.SetHovered(false)
	end

	if minBtn and minBtn.Click then
		minBtn:Click("LeftButton")
	elseif app.setMinimized then
		app.setMinimized(false)
	end
	if _G.MerchantMasterDB and type(_G.MerchantMasterDB.craftOrderQueue) == "table" then
		wipe(_G.MerchantMasterDB.craftOrderQueue)
	end
	if app.syncUnifiedShoppingList then app.syncUnifiedShoppingList() end
	drainTimers(500)
	flushPendingLayout()
end

-- 7. turnins-dark (Waylaid Crates + Reputation check)
setThemeMode("dark")
switchTab("crates")
dumpScene("turnins-dark")

-- 8. turnins-light
setThemeMode("light")
switchTab("crates")
dumpScene("turnins-light")

-- 9. leveling-dark (1-300 Leveling)
setThemeMode("dark")
switchTab("prof_path")
dumpScene("leveling-dark")

-- 10. leveling-light
setThemeMode("light")
switchTab("prof_path")
dumpScene("leveling-light")

-- 11. ledger-dark (Profit & Wealth)
setThemeMode("dark")
switchTab("an_overview")
dumpScene("ledger-dark")

-- 12. ledger-light
setThemeMode("light")
switchTab("an_overview")
dumpScene("ledger-light")
end

---------------------------------------------------------------------------------------------------
-- 13-14. Shopping List modal over the main window (Dark + Light)
---------------------------------------------------------------------------------------------------
local function seedShoppingScene()
	local db = _G.MerchantMasterDB
	db.shoppingList = {}
	db.writCraftQueue, db.spreadQueue, db.writTurnInQueue = {}, {}, {}
	db.subCraftOverrides = {}
	db.subCraftMode = "smart"
	db.craftOrderDeductOwned = true
	db.shoppingSortScope = "main"
	db.craftOrderQueue = {
		-- Wintersbite + Goldthorn (Buy AH) + Leaded Vial (NPC Vendor, 12 owned)
		{ spellID = 7258, outputItemID = 6050, prof = "alchemy", qty = 20 },
		-- Small Flame Sac (stock short) + Fire Oil ([Craft -> Buy] sub-craft: Firefin Snapper + owned Empty Vial)
		{ spellID = 7257, outputItemID = 6049, prof = "alchemy", qty = 5 },
	}
	app.sortState.shopping_list = { col = "default", asc = true }
end

local function dumpShoppingScene(mode, sceneName)
	setThemeMode(mode)
	switchTab("dashboard")
	seedShoppingScene()
	app.toggleShoppingWindow(true)
	if app.refreshUnifiedShoppingDisplay then app.refreshUnifiedShoppingDisplay() end
	local modal = app.ui.shopModal
	modal:ClearAllPoints()
	modal:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
	drainTimers(500)
	flushPendingLayout()
	dumpScene(sceneName)
end

if not cartAhOnly and not onlyScenes then
dumpShoppingScene("dark", "shopping-dark")
dumpShoppingScene("light", "shopping-light")
app.toggleShoppingWindow(false)

---------------------------------------------------------------------------------------------------
-- 15. overview-scanning-dark: a live AH browse scan mid-flight (page 14, 312 matched, 1850 seen)
---------------------------------------------------------------------------------------------------
do
	setThemeMode("dark")
	_G.MerchantMasterDB.economy = "auto"
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	switchTab("dashboard")

	local catalogIDs = {}
	for id in pairs(ns.ALL_CATALOG_IDS) do catalogIDs[#catalogIDs + 1] = id end
	table.sort(catalogIDs)

	_G.AuctionHouseFrame:Show()
	_G.C_AuctionHouse.HasFullBrowseResults = function() return false end
	_G.C_AuctionHouse.RequestMoreBrowseResults = function() end
	app.refreshAllMarketValues() -- real scan start: toast + status capsule flip to "Scanning AH…"

	local PAGES, MATCHED, SEEN = 14, 312, 1850
	local nextCatalog, sent = 1, 0
	for page = 1, PAGES do
		local batch = {}
		local wantCatalog = math.floor(MATCHED * page / PAGES) - (nextCatalog - 1)
		for _ = 1, wantCatalog do
			local id = catalogIDs[nextCatalog]
			nextCatalog = nextCatalog + 1
			batch[#batch + 1] = { itemKey = { itemID = id }, totalQuantity = 3 + (id % 40), minPrice = 400 + (id % 97) * 55 }
		end
		local wantTotal = math.floor(SEEN * page / PAGES) - sent
		while #batch < wantTotal do
			batch[#batch + 1] = { itemKey = { itemID = 900000 + sent + #batch }, totalQuantity = 1, minPrice = 100 }
		end
		sent = sent + #batch
		ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", batch) -- fires app.onScanProgress per page
	end

	local scanState = ns.MarketScan.GetState()
	assert(scanState.active and scanState.page == PAGES and scanState.matchedCount == MATCHED and scanState.seen == SEEN,
		string.format("scan simulation drifted: page=%s matched=%s seen=%s", tostring(scanState.page), tostring(scanState.matchedCount), tostring(scanState.seen)))
	app.onScanProgress()
	local refreshBtn = app.ui.winChrome.ahRefresh.button
	local spin = refreshBtn:GetScript("OnUpdate")
	if spin then spin(refreshBtn, 0.25) end
	flushPendingLayout()
	dumpScene("overview-scanning-dark")

	app.cancelMarketScan(false)
	_G.AuctionHouseFrame:Hide()
	_G.C_AuctionHouse.HasFullBrowseResults = function() return true end
	if app.ui.toast and app.ui.toast.frame then app.ui.toast.frame:Hide() end
	_G.MerchantMasterDB.economy = "Normal-Horde"
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end

---------------------------------------------------------------------------------------------------
-- Optional contrast-audit sweep: `lua_frame_dump.lua <outDir> --audit` also dumps every other
-- route in both appearances (audit-<tab>-<mode>.json) for tools/audit_theme_contrast.py.
---------------------------------------------------------------------------------------------------
local function seedVisibleWritCooldowns(durations)
	local activeChar = assert(ns.activeChar, "active character must exist for Writ cooldown preview")
	local frames = app.ui and app.ui.writsTable and app.ui.writsTable.scrollBox and app.ui.writsTable.scrollBox._frames or {}
	activeChar.writCooldowns = {}
	local seeded = 0
	for _, frame in ipairs(frames) do
		local questID = frame.data and tonumber(frame.data.questID)
		if questID and durations[seeded + 1] then
			seeded = seeded + 1
			activeChar.writCooldowns[questID] = simTime + durations[seeded]
		end
	end
	assert(seeded == #durations, "visible Writ rows must cover all requested cooldown samples")
	if app.sortState then app.sortState.writs = { col = "cdSort", asc = false } end
	if ns._evalCache then ns._evalCache.writCooldowns = nil end
	app.refresh()
	drainTimers(1000)
	flushPendingLayout()
end

if audit then
	if ns.IngestSnapshotData then
		ns.IngestSnapshotData("SYSTEM", "_global", [[return {
			v = 1, exportedAt = 1794360000, region = "eu", credsSet = true,
			intervalMin = 15, retentionDays = 30, exportCapBytes = 8388608, exportBytes = 1048576,
			truncated = false, taskStatus = "Ready", taskEnabled = true, houseMap = "2:114=Normal-Horde",
			dbBytes = 4194304, walBytes = 32768, shmBytes = 32768, localDataDirBytes = 65536,
			pageCount = 1024, pageSize = 4096, freelist = 0, journalMode = "wal",
			logBytes = 8192, logPolls = 48, log304 = 40, logExports = 8, logErrors = 0,
			totalRuns = 12, blizzRuns = 12, errRuns = 0, lastError = "",
			tables = {
				{ n = "houses", r = 1, c = 6, f = "house_id, region, realm_slug, faction, economy_key, updated_at" },
				{ n = "snapshots", r = 48, c = 6, f = "snapshot_id, house_id, source, fetched_at, item_count, lot_count" },
				{ n = "item_prices", r = 6400, c = 8, f = "snapshot_id, item_id, min_buyout, market_value, num_auctions" },
			},
		}]])
	end
	local auditTabs = {
		"vendor_crafter", "writs", "outliers", "crates", "forged", "rep", "calc_favor", "calc_rep",
		"prof_shop", "prof_browse", "an_ledger", "an_items", "an_portfolio", "an_invest", "an_writs",
		"console_overview", "console_database", "console_perf", "console_setup", "console_settings", "console_ui", "console_data", "bags",
	}
	local activeChar = ns.activeChar
	local priorWritCooldowns = activeChar and activeChar.writCooldowns
	local priorWritSort = app.sortState and app.sortState.writs
	seedShoppingScene()
	for _, tab in ipairs(auditTabs) do
		local function dumpTabModes()
			for _, mode in ipairs({ "dark", "light" }) do
				setThemeMode(mode)
				switchTab(tab)
				if tab == "writs" then seedVisibleWritCooldowns({ 5 * 3600, 35 * 60, 5 * 3600 }) end
				dumpScene("audit-" .. tab .. "-" .. mode)
			end
		end
		if tab == "vendor_crafter" then
			withVendorCrafterSeed(dumpTabModes)
		else
			dumpTabModes()
		end
	end
	if activeChar then activeChar.writCooldowns = priorWritCooldowns end
	if app.sortState then app.sortState.writs = priorWritSort end

	-- Deep Analysis contrast audit scenes (dark + light) with seeded 7x24 snapshot heatmap.
	if app.openDeepAnalysis and _G.MERCHANTMASTER_LOAD_SNAPSHOTS then
		local priorSnapRaw = ns.snapshotRaw
		local priorSnapParsed = ns.snapshotParsed
		local priorSnapHeat = ns.snapshotHeatmapCache
		local priorTab = app.activeTab
		local priorMode = ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode() or "dark"
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local b32 = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
		local function enc32(num)
			num = math.floor(tonumber(num) or 0)
			if num <= 0 then return "0" end
			local d = {}
			while num > 0 do
				local rem = num % 32
				d[#d + 1] = string.sub(b32, rem + 1, rem + 1)
				num = math.floor(num / 32)
			end
			local o = {}
			for i = #d, 1, -1 do o[#o + 1] = d[i] end
			return table.concat(o)
		end
		local function buildHeatPayloads(itemID, basePrice)
			local h24 = {}
			local cells = {}
			for dow = 1, 7 do
				for hr = 0, 23 do
					local mult = (hr <= 5 and 0.80) or (hr <= 11 and 0.93) or (hr <= 16 and 1.00) or (hr <= 20 and 1.16) or 1.32
					if dow >= 6 then mult = mult * 1.04 end
					local avgP = math.floor(basePrice * mult + 0.5)
					local minP = math.floor(avgP * 0.92 + 0.5)
					local qty = (hr <= 5) and 38 or ((hr >= 18) and 9 or 20)
					local slot = (dow - 1) * 24 + hr
					cells[#cells + 1] = tostring(slot) .. "=" .. enc32(avgP) .. "," .. enc32(minP) .. "," .. enc32(qty) .. ",4"
					if dow == 1 then h24[hr + 1] = enc32(avgP) end
				end
			end
			local bbSlot = 3 -- Mon 03:00
			local bsSlot = 6 * 24 + 21 -- Sun 21:00
			local bbP = math.floor(basePrice * 0.80 + 0.5)
			local bsP = math.floor(basePrice * 1.32 * 1.04 + 0.5)
			local heat24Line = string.format("%d:%s,%s,%s,%s,%s,%d,%s,%d,%s|%s",
				itemID, enc32(basePrice), enc32(basePrice), enc32(22), enc32(14), enc32(672),
				bbSlot, enc32(bbP), bsSlot, enc32(bsP), table.concat(h24, ","))
			local heat7x24Line = tostring(itemID) .. ":" .. table.concat(cells, "|")
			local latestLine = string.format("%d:%s,%s,%s,%s,%s,%s",
				itemID, enc32(math.floor(basePrice * 0.94 + 0.5)), enc32(basePrice), enc32(basePrice), enc32(18), enc32(simTime - 1800), enc32(basePrice))
			return latestLine, heat24Line, heat7x24Line
		end
		ns.snapshotRaw = {}
		ns.snapshotParsed = {}
		ns.snapshotHeatmapCache = {}
		local l1, h1, m1 = buildHeatPayloads(13512, 685000)
		local l2, h2, m2 = buildHeatPayloads(13468, 382000)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
			string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=2,heatmapCount=2}]], simTime - 1800))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, l1 .. ";" .. l2)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", econ, h1 .. ";" .. h2)
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", econ, m1 .. ";" .. m2)
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

		setThemeMode("dark")
		switchTab("recipes")
		assert(app.openDeepAnalysis({ kind = "recipe", itemID = 13512 }, { tab = "recipes", wasQuickLookOpen = false }),
			"deep-analysis audit scene must open Flask of Supreme Power")
		drainTimers(500)
		flushPendingLayout()
		dumpScene("deep-analysis-dark")

		setThemeMode("light")
		if ns.DeepAnalysis and ns.DeepAnalysis.Refresh then ns.DeepAnalysis.Refresh() end
		drainTimers(500)
		flushPendingLayout()
		dumpScene("deep-analysis-light")

		if app.returnFromDeepAnalysis then app.returnFromDeepAnalysis() end
		ns.snapshotRaw = priorSnapRaw
		ns.snapshotParsed = priorSnapParsed
		ns.snapshotHeatmapCache = priorSnapHeat
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		setThemeMode(priorMode)
		switchTab(priorTab or "dashboard")
	end

	print(string.format("[lua_frame_dump] %d audit scenes exported.", #auditTabs * 2 + 2))
end

-- Weekly Silversage gaps leave gaps in total cost. Hourly scans use sparse shared slots.
do
	local db = MerchantMasterDB
	local economy = ns.CurrentEconomyInfo().effectiveKey
	local day = math.floor(simTime / 86400)
	local scanAt = simTime - 240
	local daily, live, snapshots = {}, {}, {}
	local priorDailyByEconomy, priorHistoryByEconomy, priorSnapshots, priorWindow = db.ahDaily, db.ahHistory, db.ahSnapshots, db.quickLookWindow
	local priorSnapRaw, priorSnapParsed, priorSnapHeat = ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache
	ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = { _isolated = {} }, {}, {}
	db.ahHistory = {}
	local priorSearch, priorMode, priorTab = app.ui.searchBox:GetText(), ns.Theme.GetMode(), app.activeTab
	db.ahDaily = db.ahDaily or {}
	local priorDaily, priorLive = db.ahDaily[economy], db.ahPrices[economy]
	for id, quote in pairs(priorLive or {}) do live[id] = quote end
	db.ahDaily[economy], db.ahPrices[economy] = daily, live
	db.ahSnapshots = { [economy] = snapshots }
	db.quickLookWindow = "7d"
	local velocity = {
		[13512] = {18.5, 19.2, 18.8, 21.4, 21.1, 23.6, 24.2},
		[13468] = {4.2, 8.1, 6.5, 12.2, 8.4, 13.0, 9.2},
	}
	local listings = {
		[13512] = {26, 24, 23, 20, 18, 17, 14},
		[13468] = {15, 14, 12, 15, 11, 10, 8},
		[13521] = {8, 7, 6, 5, 4, 3, 2},
	}
	local series = {
		[13512] = {600000, 610000, 606000, 636000, 644000, 670000, 685000}, -- Flask of Supreme Power
		[13468] = {320000, 323500, 321800, 346000, 356000, 372000, 382000}, -- Black Lotus
		[13463] = {4800, 4590, 4690, 4500, 4470, 4320, 4200}, -- Dreamfoil
		[13465] = {7300, nil, 7480, nil, nil, 7610, 7800}, -- Mountain Silversage
		[13521] = {1480000, 1450000, 1410000, 1415000, 1340000, 1290000, 1220000}, -- Recipe scroll
	}
	local hourOffsets = {-23, -19, -14, -8, -3, 0}
	local scrollHourlyListings = {6, 5, 4, 3, nil, 2}
	local hourlyPrices = {
		[13512] = {650000, 663000, 659000, 674000, 670500},
		[13468] = {370000, 371800, 367800, 374500, 379000},
		[13463] = {4320, 4250, 4280, 4160, 4240},
		[13465] = {7610, 7635, 7450, 7700, 7680},
		[13521] = {1290000, 1270000, 1235000, 1250000},
	}
	local priorVelocity = {}
	for itemID, prices in pairs(series) do
		local buckets, history = {}, {}
		local itemVelocity, itemListings = velocity[itemID], listings[itemID]
		for i = 1, 7 do
			if prices[i] then
				local point = { d = day - 7 + i, lastP = prices[i], lastQ = itemListings and itemListings[i] or 20,
					at = scanAt - (7 - i) * 86400 }
				if itemVelocity then
					point.scanPairs, point.scanSeconds, point.scanUnits = 2, 7200, itemVelocity[i] / 4
				end
				buckets[#buckets + 1] = point
			end
		end
		if itemVelocity then
			priorVelocity[itemID] = seededVelocity[itemID]
			seededVelocity[itemID] = itemVelocity[7]
		end
		for i, offset in ipairs(hourOffsets) do
			local qty = itemListings and itemListings[i + 1] or 20
			if itemID == 13521 then qty = scrollHourlyListings[i] end
			if qty then
				local at = scanAt + offset * 3600
				local price = hourlyPrices[itemID][i] or prices[7]
				local n = #history
				if itemVelocity then
					-- Two earlier scans in this hour give the velocity model two observed intervals.
					local sold = math.floor(itemVelocity[i + 1] / 4 + 0.5)
					history[n + 1], history[n + 2], history[n + 3] = at - 900, price - 100, qty + sold
					history[n + 4], history[n + 5], history[n + 6] = at - 450, price - 50, qty + math.floor(sold / 2)
					n = n + 6
				end
				history[n + 1], history[n + 2], history[n + 3] = at, price, qty
			end
		end
		daily[itemID] = buckets
		snapshots[itemID] = history
		live[itemID] = { price = prices[7], qty = buckets[#buckets].lastQ, at = scanAt }
	end
	local priorVialPrice = db.liveVendorBuyGlobal and db.liveVendorBuyGlobal[8925]
	db.liveVendorBuyGlobal = db.liveVendorBuyGlobal or {}
	db.liveVendorBuyGlobal[8925] = { price = 500, basePrice = 500, at = simTime, limited = false } -- Crystal Vial
	live[8925] = nil
	ns.InvalidatePriceCache()
	ns.SuperList.Invalidate("all")
	setThemeMode("dark")
	switchTab("recipes")
	app.ui.searchBox:SetText("Flask")
	app.refresh()
	drainTimers(3000)
	flushPendingLayout()
	local tableWidget = assert(app.ui and app.ui.recipesTable, "All Recipes table must exist")
	local clicked = false
	for _, rowFrame in ipairs(tableWidget.scrollBox._frames or {}) do
		if rowFrame.data and rowFrame.data.outputItemID == 13512 then
			local nameCell = rowFrame.cellGroup and rowFrame.cellGroup.cellsByKey and rowFrame.cellGroup.cellsByKey.name
			assert(nameCell, "visible Flask row must have a name cell")
			nameCell:Click("LeftButton")
			clicked = true
			break
		end
	end
	assert(clicked, "visible Flask recipe row must be available for a left click")
	local hud = assert(ns.SuperList.GetQuickLookFrame(), "left-click must create Quick Look")
	assert(hud:IsShown() and hud.pinned == true, "left-click must show and pin Quick Look")
	assert(hud.data.bottleneck.series.days == 4 and hud.data.breakEvenCrafts == 19, "showcase progression must match its fixture")
	assert(hud.movers[1].name and hud.movers[1].qty and hud.movers[1].price and not hud.craftButton,
		"Quick Look must have separate reagent, quantity and price fields")
	local scrollListed = assert(hud.scrollListedRow, "recipe Quick Look must have a scroll listing row")
	local function checkScrollListings(delta, pct, coverage, lastSlot)
		assert(scrollListed:IsShown() and scrollListed.name:GetText() == "Scroll AH listed"
			and scrollListed.price:GetText() == "2" and scrollListed.impact:GetText() == delta
			and scrollListed.pct:GetText() == pct and scrollListed.coverage:GetText() == coverage
			and scrollListed.spark:IsShown() and scrollListed.trace.lines[lastSlot]:IsShown(),
			"scroll listings must paint the live count, change, coverage and sparkline for " .. hud.window)
	end
	checkScrollListings("-6", "-75.0%", "7/7d", 7)
	dumpScene("quicklook-dark")
	setThemeMode("light")
	dumpScene("quicklook-light")
	setThemeMode("dark")
	hud.win24Btn:Click("LeftButton")
	hud.overviewRows[1]:Click("LeftButton")
	assert(hud.window == "24h" and hud.expandChart:IsShown() and hud.data.net.count == #hourOffsets,
		"Quick Look must expand Profit with the sparse hourly samples")
	checkScrollListings("-4", "-66.7%", "5/24h", 24)
	-- Resolve the chart's new height before Quick Look clamps the HUD to the window.
	solveLayout(false)
	hud.Reposition()
	dumpScene("quicklook-24h-expanded-dark")
	setThemeMode("light")
	dumpScene("quicklook-24h-expanded-light")
	ns.SuperList.CloseQuickLook()
	assert(not hud:IsShown(), "Quick Look must close before the next preview scene")
	db.ahDaily[economy], db.ahPrices[economy] = priorDaily, priorLive
	db.ahDaily, db.ahHistory, db.ahSnapshots, db.quickLookWindow = priorDailyByEconomy, priorHistoryByEconomy, priorSnapshots, priorWindow
	ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = priorSnapRaw, priorSnapParsed, priorSnapHeat
	for id in pairs(velocity) do seededVelocity[id] = priorVelocity[id] end
	if db.liveVendorBuyGlobal then db.liveVendorBuyGlobal[8925] = priorVialPrice end
	ns.InvalidatePriceCache()
	ns.SuperList.Invalidate("all")
	app.ui.searchBox:SetText(priorSearch)
	app.setTab(priorTab)
	setThemeMode(priorMode)
end

---------------------------------------------------------------------------------------------------
-- Daily Writ cooldown contrast sample, plus the closed-AH refresh state.
---------------------------------------------------------------------------------------------------
do
	local activeChar = assert(ns.activeChar, "active character must exist for Writ cooldown preview")
	local priorWritCooldowns = activeChar.writCooldowns
	local priorWritSort = app.sortState and app.sortState.writs
	if app.ui and app.ui.searchBox then app.ui.searchBox:SetText("") end
	if ns._evalCache then ns._evalCache.writCooldowns = nil end
	setThemeMode("dark")
	switchTab("writs")
	seedVisibleWritCooldowns({ 14 * 3600, 5 * 3600, 35 * 60 })
	dumpScene("writs-cd-dark")
	activeChar.writCooldowns = priorWritCooldowns
	if app.sortState then app.sortState.writs = priorWritSort end
end

-- Turn-in HUDs use real visible rows and dated sample observations for each item.
do
	local econ = ns.CurrentEconomyInfo().effectiveKey
	local day = math.floor(simTime / 86400)
	MerchantMasterDB.ahDaily = MerchantMasterDB.ahDaily or {}
	local daily = MerchantMasterDB.ahDaily[econ] or {}
	MerchantMasterDB.ahDaily[econ] = daily
	for id, base in pairs({ [264066] = 13200, [8949] = 6800, [3820] = 1200, [3821] = 1900,
		[248704] = 7200, [4359] = 455, [2840] = 290, [4361] = 925, [4363] = 1410, [2880] = 85 }) do
		local points = {}
		for i = 1, 7 do
			points[i] = { d = day - 7 + i, lastP = math.floor(base * (1 + i * 0.04)), lastQ = 45 - 2 * i,
				at = simTime - 240 - (7 - i) * 86400 }
		end
		daily[id] = points
	end
	local function dumpTurnIn(tab, kind, search, tableWidget, match)
		setThemeMode("dark")
		switchTab(tab)
		app.ui.searchBox:SetText(search)
		app.refresh()
		flushPendingLayout()
		local owner
		for _, frame in ipairs(tableWidget.scrollBox._frames or {}) do
			if frame.data and match(frame.data) then owner = frame; break end
		end
		assert(owner, "Visible " .. kind .. " preview row missing")
		owner:Click("LeftButton")
		local hud = assert(ns.SuperList.GetQuickLookFrame(), "Row click must open Quick Look")
		assert(hud:IsShown() and hud.data.kind == kind and #hud.data.movers >= 4,
			"Turn-in HUD must render its acquisition and reagent rows")
		assert(hud.movers[1].price:GetJustifyH() == "RIGHT"
			and hud.overviewRows[1].price:GetJustifyH() == "RIGHT" and hud.overviewRows[2].price:GetJustifyH() == "RIGHT",
			"Turn-in HUD monetary values must be right aligned")
		for _, mode in ipairs({ "dark", "light" }) do
			setThemeMode(mode)
			dumpScene(kind .. "-quicklook-" .. mode)
		end
		ns.SuperList.CloseQuickLook()
		app.ui.searchBox:SetText("")
	end
	local char = assert(ns.activeChar)
	local priorCooldowns = char.writCooldowns
	local priorUnlock, priorProf = MerchantMasterDB.unlockFilter, MerchantMasterDB.profFilter
	MerchantMasterDB.unlockFilter, MerchantMasterDB.profFilter = "all", "all"
	char.writCooldowns = { [94266] = simTime + 35 * 60 }
	dumpTurnIn("writs", "writ", "Elixir of Agility", app.ui.writsTable, function(row) return row.writID == 264066 end)
	char.writCooldowns = priorCooldowns
	dumpTurnIn("crates", "crate", "Apprentice Parts", app.ui.cratesTable, function(row) return row.reagentID == 4359 end)
	MerchantMasterDB.unlockFilter, MerchantMasterDB.profFilter = priorUnlock, priorProf
end

-- Forged Delivery previews use the seeded market and a week of sample observations.
do
	local db, ui = MerchantMasterDB, app.ui
	local economy, day = ns.CurrentEconomyInfo().effectiveKey, math.floor(simTime / 86400)
	local priorDaily, priorWindow, priorForgedMode = db.ahDaily, db.quickLookWindow, db.forgedMode
	local priorCrateMode = db.crateMode
	local priorTab, priorTheme, priorSearch = app.activeTab, ns.Theme.GetMode(), ui.searchBox:GetText()
	local daily = {}
	local function seedHistory(id)
		if daily[id] then return end
		local price = ns.GetItemMarketPrice(id)
		if not price then return end
		local qty = ns.GetNumListed(id) or 8
		local points = {}
		for i = 1, 7 do
			points[i] = { d = day - 7 + i, lastP = math.max(1, math.floor(price * (0.82 + (i - 1) * 0.03) + 0.5)),
				lastQ = qty + 7 - i, at = simTime - (7 - i) * 86400 }
		end
		daily[id] = points
	end
	for _, crate in ipairs(ns.CRATES) do
		seedHistory(crate.itemID)
		for _, bundle in ipairs(crate.bundles) do seedHistory(bundle.itemID) end
	end
	db.ahDaily, db.quickLookWindow, db.forgedMode = { [economy] = daily }, "7d", "self_funded"
	db.crateMode = "buy"
	ui.searchBox:SetText("")
	for _, mode in ipairs({ "dark", "light" }) do
		setThemeMode(mode)
		switchTab("forged")
		dumpScene("forged-" .. mode)
	end

	setThemeMode("dark")
	switchTab("forged")
	local owner
	for _, frame in ipairs(ui.forgedTable.scrollBox._frames) do
		if frame.data then owner = frame; break end
	end
	assert(owner, "Visible Forged Delivery preview row missing")
	owner:Click("LeftButton")
	local hud = ns.SuperList.GetQuickLookFrame()
	assert(hud and hud:IsShown() and hud.data and hud.data.kind == "forged", "Forged row click opens its Quick Look")
	assert(hud.data.chartSeries.emptyCrate.days == 7 and hud.data.chartSeries.favorCost.days == 7,
		"Forged Quick Look preview has seven observations for the empty crate and Favor costs")
	flushPendingLayout()
	dumpScene("forged-quicklook-dark")
	ns.SuperList.CloseQuickLook()
	db.ahDaily, db.quickLookWindow, db.forgedMode = priorDaily, priorWindow, priorForgedMode
	db.crateMode = priorCrateMode
	ui.searchBox:SetText(priorSearch)
	app.setTab(priorTab)
	setThemeMode(priorTheme)
end

do
	local db, char = MerchantMasterDB, assert(ns.activeChar)
	local previousCooldowns, previousGroups = char.cooldowns, char.cooldownGroups
	char.cooldowns = { [11479] = simTime + 3600, [17187] = simTime + 8 * 3600 }
	char.cooldownGroups = {}
	local oldFactionData = C_Reputation.GetFactionDataByID
	C_Reputation.GetFactionDataByID = function(id)
		if id == 270 then return { factionID = id, name = "Zandalar Tribe", reaction = 6 } end
		return oldFactionData(id)
	end
	local prices = db.ahPrices[ns.CurrentEconomyInfo().effectiveKey]
	local prior = {}
	for id, price in pairs({ [20004] = 59321, [3577] = 13125, [12360] = 183475, [3575] = 412, [2776] = 6789 }) do
		prior[id] = prices[id]
		prices[id] = { price = price, qty = id == 3575 and 30 or 1, at = simTime }
	end
	ns.InvalidatePriceCache()
	setThemeMode("dark")
	switchTab("outliers")
	local rows = ns.BuildOutlierRows({ profFilter = "alchemy", outlierQuality = "all" })
	local picked = {}
	for _, row in ipairs(rows) do picked[row.itemID] = row end
	local potion, iron, shared = picked[20004], picked[3577], picked[12360]
	assert(potion and potion.repLabel == "Honored" and potion.repFactionName == "Zandalar Tribe",
		"Monopolies preview requires Zandalar Tribe Honored recipe evidence")
	assert(iron and iron.recipe.spellID == 11479 and iron.cdInfo.remainingLabel == "1h" and not iron.cdInfo.sharedGroup,
		"Monopolies preview requires the independent 1h Iron to Gold cooldown")
	assert(shared and shared.cdInfo.sharedGroup == "alchemy_transmute" and shared.cdInfo.remainingLabel == "8h",
		"Monopolies preview requires a separate shared Alchemy transmute cooldown")
	app.ui.outliersTable.setRows({ potion, iron, shared })
	dumpScene("monopolies-rep-transmute-dark")
	for id in pairs({ [20004] = true, [3577] = true, [12360] = true, [3575] = true, [2776] = true }) do prices[id] = prior[id] end
	C_Reputation.GetFactionDataByID = oldFactionData
	char.cooldowns, char.cooldownGroups = previousCooldowns, previousGroups
	ns.InvalidatePriceCache()
end

do
	local prior = MerchantMasterDB.priceDisplayMode
	setThemeMode("dark")
	switchTab("writs")
	for _, sample in ipairs({ { "compact", "prices-standard-dark" }, { "no_copper", "prices-no-copper-dark" },
		{ "full_fixed", "prices-3modes-rightalign-dark" } }) do
		MerchantMasterDB.priceDisplayMode = sample[1]
		app.refresh()
		flushPendingLayout()
		local first = app.ui.writsTable.scrollBox._frames[1]
		assert(first and first.cells[7]:GetJustifyH() == "RIGHT" and app.ui.writsResetBtn:IsShown(),
			"Price format comparison requires right-aligned prices and the Reset Filters pill")
		dumpScene(sample[2])
	end
	MerchantMasterDB.priceDisplayMode = prior
end

do
	setThemeMode("dark")
	switchTab("recipes")
	_G.AuctionHouseFrame:Hide()
	local refresh = app.ui and app.ui.winChrome and app.ui.winChrome.ahRefresh
	local button = refresh and refresh.button
	assert(button and button.GetScript, "AH refresh button must exist")
	local onEnter = button:GetScript("OnEnter")
	if onEnter then onEnter(button) end
	button:Click("LeftButton")
	assert(button.ahNotOpen == true, "closed AH click must expose the not-open state")
	local tooltipFound = false
	for _, line in ipairs(_G.GameTooltip._lines or {}) do
		if line == "AH not open" then tooltipFound = true end
	end
	assert(tooltipFound, "closed AH click must show the AH not open tooltip")
	local tooltipFrame = _G.GameTooltip
	tooltipFrame:SetFrameStrata("TOOLTIP")
	tooltipFrame:SetSize(124, 28)
	tooltipFrame:ClearAllPoints()
	tooltipFrame:SetPoint("BOTTOM", button, "TOP", 0, 6)
	tooltipFrame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
	tooltipFrame:SetBackdropColor(0.055, 0.065, 0.09, 0.98)
	tooltipFrame:SetBackdropBorderColor(0.35, 0.38, 0.46, 0.95)
	local tooltipText = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tooltipText:SetPoint("CENTER", tooltipFrame, "CENTER", 0, 0)
	tooltipText:SetText("AH not open")
	tooltipText:SetTextColor(1, 0.26, 0.28, 1)
	tooltipText:Show()
	flushPendingLayout()
	dumpScene("ah-not-open-dark")
	_G.AuctionHouseFrame:Show()
	if refresh and refresh.Update then refresh:Update() end
	local onLeave = button:GetScript("OnLeave")
	if onLeave then onLeave(button) end
	tooltipText:Hide()
	tooltipFrame:SetBackdrop(nil)
	_G.GameTooltip:Hide()
	_G.AuctionHouseFrame:Hide()
end

-- Craftable Now -> All Chars toolbar & SuperList preview.
do
	local db, ui = MerchantMasterDB, app.ui
	local savedChars, savedActive = db.chars, ns.activeChar
	local savedKnown, savedUnlock, savedAll = db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars
	local savedTab, savedTheme, savedSearch = app.activeTab, ns.Theme.GetMode(), ui.searchBox:GetText()
	local savedGetProfessions, savedGetProfessionInfo = _G.GetProfessions, _G.GetProfessionInfo
	local savedGetNumSkillLines, savedGetSkillLineInfo = _G.GetNumSkillLines, _G.GetSkillLineInfo
	local savedIsPlayerSpell, savedIsSpellKnown, savedTradeSkill = _G.IsPlayerSpell, _G.IsSpellKnown, _G.C_TradeSkillUI
	_G.GetProfessions = function() return nil, nil, nil, nil, 1, nil end
	_G.GetProfessionInfo = function(idx)
		if idx == 1 then return "Cooking", 133971, 300, 300, 0, 0, 185 end
	end
	_G.GetNumSkillLines = function() return 1 end
	_G.GetSkillLineInfo = function(i)
		if i == 1 then return "Cooking", false, false, 300, 0, 0, 300 end
	end
	_G.IsPlayerSpell = function() return false end
	_G.IsSpellKnown = _G.IsPlayerSpell
	_G.C_TradeSkillUI = nil
	local econ = ns.CurrentEconomyInfo().effectiveKey
	local bankChar = {
		name = "Banker", realm = "Forever", faction = "Horde", economy = econ,
		profs = { cooking = 300 }, knownSpells = {}, knownOutputs = {}, knownNames = {},
		scannedProfs = { cooking = true }, cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
	}
	local alchSpells = { [17634] = true, [11449] = true }
	for sid, v in pairs(db.learnedSpells or {}) do
		if v then alchSpells[sid] = true end
	end
	local alchAlt = {
		name = "AlchAlt", realm = "Forever", faction = "Horde", economy = econ,
		profs = { alchemy = 300 }, knownSpells = alchSpells,
		knownOutputs = {}, knownNames = {}, scannedProfs = { alchemy = true },
		cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
	}
	local tailorAlt = {
		name = "TailorAlt", realm = "Forever", faction = "Horde", economy = econ,
		profs = { tailoring = 300 }, knownSpells = {},
		knownOutputs = {}, knownNames = {}, scannedProfs = { tailoring = true },
		cooldowns = {}, cooldownGroups = {}, writCooldowns = {},
	}
	db.chars = {
		["Normal-Horde-Forever-Banker"] = bankChar,
		["Normal-Horde-Forever-AlchAlt"] = alchAlt,
		["Normal-Horde-Forever-TailorAlt"] = tailorAlt,
	}
	ns.activeChar = bankChar
	db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = true, "known", true
	ui.searchBox:SetText("")
	app.invalidateCraftableScope()
	for _, mode in ipairs({ "dark", "light" }) do
		setThemeMode(mode)
		switchTab("recipes")
		drainTimers(3000)
		flushPendingLayout()
		assert(ui.charScopeSeg and ui.charScopeSeg.frame:IsShown(), "charScopeSeg must show in Craftable Now at 1840px")
		dumpScene("craftable-allchars-" .. mode)
	end
	_G.GetProfessions, _G.GetProfessionInfo = savedGetProfessions, savedGetProfessionInfo
	_G.GetNumSkillLines, _G.GetSkillLineInfo = savedGetNumSkillLines, savedGetSkillLineInfo
	_G.IsPlayerSpell, _G.IsSpellKnown, _G.C_TradeSkillUI = savedIsPlayerSpell, savedIsSpellKnown, savedTradeSkill
	db.chars, ns.activeChar = savedChars, savedActive
	db.knownRecipesOnly, db.unlockFilter, db.craftableAllChars = savedKnown, savedUnlock, savedAll
	app.invalidateCraftableScope()
	ui.searchBox:SetText(savedSearch)
	app.setTab(savedTab)
	setThemeMode(savedTheme)
end
end

---------------------------------------------------------------------------------------------------
-- Warcraft skin sweep: `lua_frame_dump.lua <outDir> --skins`
-- overview-standard-dark/light, overview-<skin> x5, options-goblin (UI Theme dropdown open),
-- market-goblin, allrecipes-night_elf. Always ends back on Standard dark / Overview.
---------------------------------------------------------------------------------------------------
if skinsMode then
	skinIcons = true
	-- The pre-sweep UI bank contains numeric placeholder icons. Re-evaluate against the custom icon stub.
	app.uiPriceBank = nil
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	local Theme = assert(ns.Theme, "ns.Theme missing")
	assert(Theme.SetSkin and Theme.GetSkin, "Theme.SetSkin/GetSkin missing: UI_Theme.lua skin API has not landed")

	local function applySkin(key)
		local api = _G.MerchantMasterAPI
		if api and api.SetSkin then
			api.SetSkin(key)
		else
			if _G.MerchantMasterDB then _G.MerchantMasterDB.uiSkin = key end
			Theme.SetSkin(key)
		end
		assert(Theme.GetSkin() == key, "skin did not switch to " .. key .. ", got " .. tostring(Theme.GetSkin()))
		if app.refresh then app.refresh() end
		drainTimers(500)
		flushPendingLayout()
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(500)
		flushPendingLayout()
	end

	local function sizeSkinViewport(key, customW, customH, customVpW, customVpH)
		local custom = key ~= "standard"
		VIEWPORT_W = custom and (customVpW or 1440) or 1920
		VIEWPORT_H = custom and (customVpH or 900) or 960
		dumpWindowWidth = custom and (customW or 1320) or 1840
		dumpWindowHeight = custom and (customH or 730) or 730
		_G.UIParent:SetSize(VIEWPORT_W, VIEWPORT_H)
		local saved = _G.MerchantMasterDB.window
		saved.width, saved.height = dumpWindowWidth, dumpWindowHeight
		app.ui.winChrome.window:SetMinimumWidth(1320)
		app.ui.winChrome.window:ApplyFull()
	end

	local function skinScene(sceneName, key, mode, tab, extraMeta, customW, customH, customVpW, customVpH)
		if onlyScenes and not onlyScenes[sceneName] then return end
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		sizeSkinViewport(key, customW, customH, customVpW, customVpH)
		applySkin(key)
		if key == "standard" then setThemeMode(mode or "dark") end
		switchTab(tab or "dashboard")
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene(sceneName, nil, extraMeta)
	end

	local priorSkin = Theme.GetSkin()
	local priorMode = Theme.GetUserMode and Theme.GetUserMode() or Theme.GetMode()
	local priorTab = app.activeTab

	-- Shared synthetic snapshot & morning brief seeders for Goblin Baron v3.3.2 previews
	local BARON_B32 = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
	local function baronEnc32(num)
		num = math.floor(tonumber(num) or 0)
		if num <= 0 then return "0" end
		local d = {}
		while num > 0 do
			local rem = num % 32
			d[#d + 1] = string.sub(BARON_B32, rem + 1, rem + 1)
			num = math.floor(num / 32)
		end
		local out = {}
		for i = #d, 1, -1 do out[#out + 1] = d[i] end
		return table.concat(out)
	end

	local function buildBaronSnapPayloads(itemID, basePrice, qtyBase, nowTs)
		local h24 = {}
		local cells = {}
		for dow = 1, 7 do
			for hr = 0, 23 do
				local mult = (hr <= 5 and 0.80) or (hr <= 11 and 0.93) or (hr <= 16 and 1.00) or (hr <= 20 and 1.18) or 1.33
				if dow >= 6 then mult = mult * 1.04 end
				local avgP = math.floor(basePrice * mult + 0.5)
				local minP = math.floor(avgP * 0.92 + 0.5)
				local qty = (hr <= 5) and math.floor(qtyBase * 1.6) or ((hr >= 18) and math.max(3, math.floor(qtyBase * 0.5)) or qtyBase)
				local slot = (dow - 1) * 24 + hr
				cells[#cells + 1] = tostring(slot) .. "=" .. baronEnc32(avgP) .. "," .. baronEnc32(minP) .. "," .. baronEnc32(qty) .. ",4"
				if dow == 1 then h24[hr + 1] = baronEnc32(avgP) end
			end
		end
		local bbSlot = 3
		local bsSlot = 6 * 24 + 21
		local bbP = math.floor(basePrice * 0.80 + 0.5)
		local bsP = math.floor(basePrice * 1.33 * 1.04 + 0.5)
		local latest = string.format("%d:%s,%s,%s,%s,%s,%s",
			itemID, baronEnc32(math.floor(basePrice * 0.93 + 0.5)), baronEnc32(basePrice), baronEnc32(basePrice),
			baronEnc32(qtyBase), baronEnc32((nowTs or simTime) - 600), baronEnc32(basePrice))
		local heat24 = string.format("%d:%s,%s,%s,%s,%s,%d,%s,%d,%s|%s",
			itemID, baronEnc32(basePrice), baronEnc32(basePrice), baronEnc32(qtyBase), baronEnc32(15), baronEnc32(672),
			bbSlot, baronEnc32(bbP), bsSlot, baronEnc32(bsP), table.concat(h24, ","))
		local heat7x24 = tostring(itemID) .. ":" .. table.concat(cells, "|")
		return latest, heat24, heat7x24
	end

	local function withMorningBriefSeed(fn)
		local Store = ns.Analytics and ns.Analytics.Store
		local db = _G.MerchantMasterDB
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local priorSimTime = simTime
		local priorLedgerDB = _G.MerchantMasterLedgerDB
		local priorStoreDB = Store and Store.db
		local priorDashMode = db.dashboardMode
		local priorDashRange = db.dashboardBriefRange
		local priorAhDaily = db.ahDaily
		local priorLivePrices = db.ahPrices and db.ahPrices[econ]
		local priorScannedAt = priorLivePrices and priorLivePrices._scannedAt
		local savedPrices = {}

		-- Set deterministic morning time (09:20 local) so greeting is "Good morning, Grommash"
		local morningTs = priorSimTime + 7 * 3600
		simTime = morningTs
		local curDay = math.floor(morningTs / 86400)

		-- Seed synthetic reagent drops: Thick Leather (4304) 8s -> 6s (-25% -> Green Lens),
		-- Dreamfoil (13463) 52s -> 42s (-19% -> Greater Arcane Elixir / Mongoose),
		-- Mountain Silversage (13465) 82s -> 68s (-17% -> Elixir of the Mongoose),
		-- Golden Sansam (13464) 38s -> 31s (-18% -> Major Healing Potion)
		local dropPrices = {
			[4304]  = { cur = 600,  base = 800,  qty = 46 },  -- Thick Leather
			[10504] = { cur = 165000, base = 158000, qty = 4 }, -- Green Lens
			[13463] = { cur = 4200, base = 5200, qty = 54 },  -- Dreamfoil
			[13465] = { cur = 6800, base = 8200, qty = 36 },  -- Mountain Silversage
			[13464] = { cur = 3100, base = 3800, qty = 48 },  -- Golden Sansam
			[13466] = { cur = 2800, base = 3400, qty = 30 },  -- Plaguebloom
		}
		db.ahPrices = db.ahPrices or {}
		db.ahPrices[econ] = db.ahPrices[econ] or {}
		db.ahPrices[econ]._scannedAt = morningTs - 240
		db.ahDaily = db.ahDaily or {}
		local dailyCopy = {}
		for k, v in pairs((priorAhDaily and priorAhDaily[econ]) or {}) do dailyCopy[k] = v end
		for id, spec in pairs(dropPrices) do
			savedPrices[id] = db.ahPrices[econ][id]
			db.ahPrices[econ][id] = { price = spec.cur, qty = spec.qty, at = morningTs - 240 }
			dailyCopy[id] = {
				{ d = curDay - 4, lastP = math.floor(spec.base * 1.03), lastQ = spec.qty + 8, at = morningTs - 4 * 86400 },
				{ d = curDay - 3, lastP = spec.base, lastQ = spec.qty + 5, at = morningTs - 3 * 86400 },
				{ d = curDay - 2, lastP = math.floor(spec.base * 0.99), lastQ = spec.qty + 3, at = morningTs - 2 * 86400 },
				{ d = curDay - 1, lastP = spec.base, lastQ = spec.qty + 1, at = morningTs - 86400 },
				{ d = curDay,     lastP = spec.cur, lastQ = spec.qty, at = morningTs - 240 },
			}
		end
		db.ahDaily[econ] = dailyCopy
		db.dashboardMode = "brief"
		db.dashboardBriefRange = "7d"

		-- Fresh synthetic ledger with strict AH_SELL profit history, CRAFT records & hourly wealth snapshots
		_G.MerchantMasterLedgerDB = {}
		if Store and Store.Init then Store.Init() end
		local charKey = Store and select(1, Store.CurrentCharAndEcon()) or "Normal-Horde-Forever-Grommash"
		local dailyItems = {
			{ id = 13512, name = "Flask of Supreme Power",         gross = 274000, fee = 13700, cogs = 178000, qty = 2 },
			{ id = 10504, name = "Green Lens",                     gross = 168000, fee = 8400,  cogs = 72000,  qty = 2 },
			{ id = 13454, name = "Greater Arcane Elixir",          gross = 79500,  fee = 3975,  cogs = 41500,  qty = 6 },
			{ id = 13452, name = "Elixir of the Mongoose",         gross = 68400,  fee = 3420,  cogs = 36800,  qty = 8 },
			{ id = 13444, name = "Major Mana Potion",              gross = 41500,  fee = 2075,  cogs = 22400,  qty = 10 },
			{ id = 5634,  name = "Free Action Potion",             gross = 24200,  fee = 1210,  cogs = 12800,  qty = 8 },
			{ id = 13457, name = "Greater Fire Protection Potion", gross = 44500,  fee = 2225,  cogs = 24900,  qty = 5 },
			{ id = 4304,  name = "Thick Leather",                  gross = 18000,  fee = 900,   cogs = 11500,  qty = 20 },
		}
		local runGold = 14800000
		local dayMultipliers = { 0.88, 1.12, 0.76, 1.24, 1.05, 0.94, 1.18, 1.32 }
		local ydayHoursAgo = { 22, 19, 16, 13, 10 }
		for dOff = 7, 1, -1 do
			local baseTs = morningTs - dOff * 86400 - 7200
			local mult = dayMultipliers[8 - dOff] or 1.0
			local dayProfit = 0
			for idx = 1, 5 do
				local it = dailyItems[((dOff + idx - 1) % #dailyItems) + 1]
				local q = math.max(1, math.floor(it.qty * mult + 0.5))
				local g = it.gross * q
				local f = it.fee * q
				local c = it.cogs * q
				dayProfit = dayProfit + (g - f - c)
				local saleTs = (dOff == 1) and (morningTs - ydayHoursAgo[idx] * 3600 + 900) or (baseTs - (idx * 1800))
				Store.Append({
					time = saleTs,
					type = "AH_SELL",
					char = charKey,
					econ = econ,
					itemID = it.id,
					qty = q,
					unit = it.gross,
					total = g - f,
					cogs = c,
					where = "Orgrimmar",
					skipRecon = true,
					extra = { name = it.name, gross = g, fee = f },
				})
			end
			runGold = runGold + dayProfit
			Store.SaveSnapshot(charKey, Store.DayKey(baseTs), {
				gold = runGold,
				items = 3650000 + (8 - dOff) * 95000,
				listed = 2100000,
				bags = 1250000,
				bank = 2400000 + (8 - dOff) * 95000,
				mail = 0,
				econ = econ,
				time = baseTs,
			})
		end
		-- Today's CRAFT records so Green Lens, Greater Arcane Elixir, Mongoose, Major Healing rank at top of Reagent Price-Drop Alerts
		local todayCrafts = {
			{ spellID = 12622, itemID = 10504, name = "Green Lens",            qty = 6 },
			{ spellID = 17573, itemID = 13454, name = "Greater Arcane Elixir", qty = 14 },
			{ spellID = 17571, itemID = 13452, name = "Elixir of the Mongoose", qty = 12 },
			{ spellID = 17556, itemID = 13446, name = "Major Healing Potion",  qty = 18 },
		}
		for i, cr in ipairs(todayCrafts) do
			Store.Append({
				time = morningTs - 5 * 3600 + i * 300,
				type = "CRAFT",
				char = charKey,
				econ = econ,
				itemID = cr.itemID,
				qty = cr.qty,
				unit = 0,
				total = 0,
				cogs = 0,
				where = "Orgrimmar",
				skipRecon = true,
				extra = { spellID = cr.spellID, name = cr.name },
			})
		end
		-- Today's crisp AH_SELL log (10 varied sales including DE-origin tag for scrollable Recent AH Sales + Best Items)
		local todaySales = {
			{ minsAgo = 14,  id = 13512, name = "Flask of Supreme Power",         qty = 2,  gross = 548000, fee = 27400, cogs = 356000 },
			{ minsAgo = 26,  id = 11176, name = "Dream Dust",                     qty = 1,  gross = 18500,  fee = 925,   cogs = 8400,
				deOrigin = { srcItemID = 10504, srcName = "Green Lens", srcCost = 8400 } },
			{ minsAgo = 55,  id = 13454, name = "Greater Arcane Elixir",          qty = 8,  gross = 636000, fee = 31800, cogs = 332000 },
			{ minsAgo = 82,  id = 13452, name = "Elixir of the Mongoose",         qty = 10, gross = 684000, fee = 34200, cogs = 368000 },
			{ minsAgo = 145, id = 13444, name = "Major Mana Potion",              qty = 15, gross = 622500, fee = 31125, cogs = 336000 },
			{ minsAgo = 210, id = 13457, name = "Greater Fire Protection Potion", qty = 6,  gross = 267000, fee = 13350, cogs = 149400 },
			{ minsAgo = 275, id = 5634,  name = "Free Action Potion",             qty = 10, gross = 242000, fee = 12100, cogs = 128000 },
			{ minsAgo = 340, id = 4304,  name = "Thick Leather",                  qty = 40, gross = 36000,  fee = 1800,  cogs = 24000 },
			{ minsAgo = 415, id = 13446, name = "Major Healing Potion",           qty = 20, gross = 370000, fee = 18500, cogs = 212000 },
			{ minsAgo = 490, id = 13456, name = "Greater Frost Protection Potion", qty = 5, gross = 182500, fee = 9125,  cogs = 105000 },
		}
		for idx, s in ipairs(todaySales) do
			Store.Append({
				time = morningTs - s.minsAgo * 60,
				type = "AH_SELL",
				char = charKey,
				econ = econ,
				itemID = s.id,
				qty = s.qty,
				unit = math.floor(s.gross / s.qty),
				total = s.gross - s.fee,
				cogs = s.cogs,
				where = "Orgrimmar",
				skipRecon = true,
				extra = { name = s.name, gross = s.gross, fee = s.fee, replayOrder = 100 - idx, deOrigin = s.deOrigin },
			})
		end
		-- Seed 10 hourly intraday wealth snapshots up to morningTs (Total Wealth Hourly Line Chart)
		local hourlyWealthSteps = { 0, 140000, 220000, 390000, 510000, 680000, 920000, 1180000, 1460000, 1890000 }
		for hIdx = 1, #hourlyWealthSteps do
			local hTs = morningTs - (#hourlyWealthSteps - hIdx) * 3600
			simTime = hTs
			Store.SaveSnapshot(charKey, Store.DayKey(hTs), {
				gold = runGold + hourlyWealthSteps[hIdx],
				items = 4380000 + hIdx * 24000,
				listed = 2240000 - hIdx * 12000,
				bags = 1420000,
				bank = 2960000 + hIdx * 24000,
				mail = 0,
				econ = econ,
				time = hTs,
			})
		end
		simTime = morningTs

		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if ns.DashboardBrief and ns.DashboardBrief.InvalidateCache then ns.DashboardBrief.InvalidateCache() end
		if ns.Analytics and ns.Analytics.Model and ns.Analytics.Model.Invalidate then ns.Analytics.Model.Invalidate() end

		local ok, err = pcall(fn)

		simTime = priorSimTime
		_G.MerchantMasterLedgerDB = priorLedgerDB
		if Store then Store.db = priorStoreDB end
		db.dashboardMode = priorDashMode
		db.dashboardBriefRange = priorDashRange
		db.ahDaily = priorAhDaily
		if priorLivePrices then
			for id in pairs(dropPrices) do db.ahPrices[econ][id] = savedPrices[id] end
			db.ahPrices[econ]._scannedAt = priorScannedAt
		end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if ns.DashboardBrief and ns.DashboardBrief.InvalidateCache then ns.DashboardBrief.InvalidateCache() end
		if ns.Analytics and ns.Analytics.Model and ns.Analytics.Model.Invalidate then ns.Analytics.Model.Invalidate() end
		if not ok then error(err, 0) end
	end

if not cartAhOnly then
	skinScene("overview-standard-dark", "standard", "dark")
	skinScene("overview-standard-light", "standard", "light")
	for _, key in ipairs({ "human", "night_elf", "orc", "undead" }) do
		skinScene("overview-" .. key, key)
	end
	if not onlyScenes or onlyScenes["overview-goblin"] then
		withMorningBriefSeed(function()
			sizeSkinViewport("goblin")
			applySkin("goblin")
			switchTab("dashboard")
			if app.ui and app.ui.dashBriefView then
				local bv = app.ui.dashBriefView
				if bv.wealthToggle and bv.wealthToggle.SetActive then
					bv.wealthToggle:SetActive("hourly", false)
				end
				if bv.Refresh then bv:Refresh(true) end
			end
			if app.refreshSkinLayout then app.refreshSkinLayout() end
			drainTimers(500)
			flushPendingLayout()
			if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
			dumpScene("overview-goblin")
		end)
	end
	skinScene("overview-goblin-bright", "goblin", nil, "dashboard", { brightBackdrop = true })

	-- options-goblin: the Interface > AddOns options page shown on its own with the UI Theme dropdown open.
	if not onlyScenes or onlyScenes["options-goblin"] then
	do
		applySkin("goblin")
		switchTab("dashboard")
		local of = assert(app.ui.optionsFrame, "app.ui.optionsFrame missing")
		local panelWasShown = app.panel:IsShown()
		app.panel:Hide()
		of:SetParent(_G.UIParent)
		of:ClearAllPoints()
		of:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
		of:SetSize(820, 640)
		of:SetFrameStrata("DIALOG")
		if not of._skinDumpBacking then
			-- The real page sits on Blizzard's dark Settings canvas; give the dump an equivalent backing.
			of._skinDumpBacking = of:CreateTexture(nil, "BACKGROUND")
			of._skinDumpBacking:SetAllPoints(of)
			of._skinDumpBacking:SetColorTexture(0.07, 0.07, 0.08, 1)
		end
		of:Show()
		drainTimers(500)
		flushPendingLayout()
		local skinBtn = app.ui.optUiSkinBtn
		if skinBtn then
			skinBtn:Click("LeftButton")
			drainTimers(500)
			flushPendingLayout()
		else
			print("[lua_frame_dump] NOTE: app.ui.optUiSkinBtn not present yet (skin-opts); options-goblin dumped without the dropdown")
		end
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("options-goblin", of)
		if Theme.CloseDropDown then Theme.CloseDropDown() end
		of:Hide()
		if panelWasShown then
			app.panel:Show()
			app.panel:ClearAllPoints()
			app.panel:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
		end
	end
	end

	skinScene("market-goblin", "goblin", nil, "profit_spread")
	skinScene("leveling-goblin", "goblin", nil, "prof_path")
	skinScene("allrecipes-goblin", "goblin", nil, "recipes")
	skinScene("turnins-goblin", "goblin", nil, "crates", nil, 1600, 880, 1728, 1080)
	skinScene("writs-goblin", "goblin", nil, "writs", nil, 1600, 880, 1728, 1080)
	skinScene("ledger-goblin", "goblin", nil, "an_overview")
	skinScene("allrecipes-night_elf", "night_elf", nil, "recipes")

	-- deep-analysis-goblin (08-baron-deep-analysis.png): visual-first Deep Analysis for Flask of Supreme Power
	if not onlyScenes or onlyScenes["deep-analysis-goblin"] then
	do
		local db = _G.MerchantMasterDB
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local priorSnapRaw, priorSnapParsed, priorSnapHeat = ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache
		local priorDaily, priorSnaps = db.ahDaily, db.ahSnapshots
		local priorLive = db.ahPrices and db.ahPrices[econ]
		local priorDaScannedAt = priorLive and priorLive._scannedAt
		local savedLive = {}
		local Store = ns.Analytics and ns.Analytics.Store
		local priorLedgerDB = _G.MerchantMasterLedgerDB
		local priorStoreDB = Store and Store.db

		local day = math.floor(simTime / 86400)
		local scanAt = simTime - 240
		if db.ahPrices and db.ahPrices[econ] then
			db.ahPrices[econ]._scannedAt = scanAt
		end
		local daDaily, daSnaps = {}, {}
		local daSeries = {
			[13512] = { 610000, 622000, 618000, 642000, 655000, 672000, 685000 }, -- Flask of Supreme Power
			[13468] = { 320000, 326000, 330000, 344000, 355000, 370000, 382000 }, -- Black Lotus
			[13463] = { 4750, 4620, 4560, 4440, 4390, 4290, 4200 },               -- Dreamfoil
			[13465] = { 7300, 7420, 7480, 7560, 7610, 7720, 7800 },               -- Mountain Silversage
			[13521] = { 1450000, 1410000, 1380000, 1340000, 1300000, 1260000, 1220000 },
		}
		local hourOffsets = { -23, -19, -15, -11, -7, -3, 0 }
		for id, pts in pairs(daSeries) do
			savedLive[id] = db.ahPrices[econ][id]
			db.ahPrices[econ][id] = { price = pts[7], qty = 16, at = scanAt }
			local b = {}
			for i = 1, 7 do
				b[i] = { d = day - 7 + i, lastP = pts[i], lastQ = 22 - i, at = scanAt - (7 - i) * 86400 }
			end
			daDaily[id] = b
			local h = {}
			for i, off in ipairs(hourOffsets) do
				local mult = 0.94 + i * 0.011
				h[#h + 1] = scanAt + off * 3600
				h[#h + 1] = math.floor(pts[7] * mult + 0.5)
				h[#h + 1] = 20 - i
			end
			daSnaps[id] = h
		end
		db.ahDaily = { [econ] = daDaily }
		db.ahSnapshots = { [econ] = daSnaps }

		-- Standalone Live AH mode (no 7x24 timing drawer) so side-by-side 24h & 7d charts,
		-- Profit Waterfall, Reagent Cost Share bars, Demand Heat meter, and Ledger profit bars
		-- all render cleanly in one crisp 1320x730 view at 1.000 scale!
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = {}, {}, {}

		-- Seed personal ledger sales for Flask of Supreme Power so Ledger profit bars populate
		_G.MerchantMasterLedgerDB = {}
		if Store and Store.Init then Store.Init() end
		local charKey = Store and select(1, Store.CurrentCharAndEcon()) or "Normal-Horde-Forever-Grommash"
		local flaskSales = {
			{ dOff = 6, qty = 2, gross = 1280000, cogs = 960000 },
			{ dOff = 5, qty = 3, gross = 1965000, cogs = 1440000 },
			{ dOff = 4, qty = 1, gross = 655000,  cogs = 485000 },
			{ dOff = 3, qty = 4, gross = 2680000, cogs = 1940000 },
			{ dOff = 2, qty = 2, gross = 1350000, cogs = 980000 },
			{ dOff = 1, qty = 3, gross = 2055000, cogs = 1465000 },
			{ dOff = 0, qty = 2, gross = 1370000, cogs = 985000 },
		}
		for _, fs in ipairs(flaskSales) do
			local fee = math.floor(fs.gross * 0.05)
			Store.Append({
				time = simTime - fs.dOff * 86400 - 1200,
				type = "AH_SELL",
				char = charKey,
				econ = econ,
				itemID = 13512,
				qty = fs.qty,
				unit = math.floor(fs.gross / fs.qty),
				total = fs.gross - fee,
				cogs = fs.cogs,
				where = "Orgrimmar",
				skipRecon = true,
				extra = { name = "Flask of Supreme Power", gross = fs.gross, fee = fee },
			})
		end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if ns.Analytics and ns.Analytics.Model and ns.Analytics.Model.Invalidate then ns.Analytics.Model.Invalidate() end

		sizeSkinViewport("goblin")
		applySkin("goblin")
		switchTab("dashboard")
		assert(app.openDeepAnalysis({ kind = "recipe", itemID = 13512 }, { tab = "recipes", wasQuickLookOpen = false }),
			"deep-analysis-goblin must open Flask of Supreme Power")
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(500)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("deep-analysis-goblin")

		if app.returnFromDeepAnalysis then app.returnFromDeepAnalysis() end
		_G.MerchantMasterLedgerDB = priorLedgerDB
		if Store then Store.db = priorStoreDB end
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = priorSnapRaw, priorSnapParsed, priorSnapHeat
		db.ahDaily, db.ahSnapshots = priorDaily, priorSnaps
		if priorLive then
			for id in pairs(daSeries) do db.ahPrices[econ][id] = savedLive[id] end
			db.ahPrices[econ]._scannedAt = priorDaScannedAt
		end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if ns.Analytics and ns.Analytics.Model and ns.Analytics.Model.Invalidate then ns.Analytics.Model.Invalidate() end
	end
	end

	-- all-items-goblin (09-baron-all-items.png): polished All Items with soft separators, light top card & Quick Look stars
	if not onlyScenes or onlyScenes["all-items-goblin"] then
	do
		local db = _G.MerchantMasterDB
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local priorSnapRaw, priorSnapParsed, priorSnapHeat = ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache
		local priorWL = db.watchlist and _G.CopyTable(db.watchlist) or nil
		local priorSearch = app.ui and app.ui.searchBox and app.ui.searchBox:GetText() or ""

		-- Seed 24h heat strips on top items so Demand strips look rich in All Items
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = {}, {}, {}
		local heatIDs = {
			{ 13512, 265000, 14 }, { 13454, 79500, 18 }, { 13452, 68400, 22 },
			{ 13444, 41500, 32 },  { 13468, 68000, 8 },  { 13463, 4200, 58 },
			{ 13465, 6800, 42 },   { 13446, 18500, 46 }, { 5634, 24200, 19 },
			{ 13457, 44500, 15 },  { 13456, 36500, 12 }, { 4304, 600, 64 },
		}
		local lParts, hParts, mParts = {}, {}, {}
		for _, spec in ipairs(heatIDs) do
			local l, h, m = buildBaronSnapPayloads(spec[1], spec[2], spec[3], simTime)
			lParts[#lParts + 1] = l
			hParts[#hParts + 1] = h
			mParts[#mParts + 1] = m
		end
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
			string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=%d,heatmapCount=%d}]], simTime - 600, #heatIDs, #heatIDs))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, table.concat(lParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", econ, table.concat(hParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", econ, table.concat(mParts, ";"))

		-- Star a few flagship items so filled gold Watchlist stars display alongside outline stars
		if ns.Watchlist and ns.Watchlist.Clear then
			ns.Watchlist.Clear()
			ns.Watchlist.Add({ kind = "item", itemID = 13452 })
			ns.Watchlist.Add({ kind = "item", itemID = 13454 })
			ns.Watchlist.Add({ kind = "item", itemID = 4304 })
		end
		if app.ui and app.ui.searchBox then app.ui.searchBox:SetText("") end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

		sizeSkinViewport("goblin")
		applySkin("goblin")
		switchTab("all_items")
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(2000)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("all-items-goblin")

		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = priorSnapRaw, priorSnapParsed, priorSnapHeat
		db.watchlist = priorWL
		if app.ui and app.ui.searchBox then app.ui.searchBox:SetText(priorSearch) end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	end
	end

	-- watchlist-goblin (10-baron-watchlist.png): favorites mixing recipes + standalone items (e.g. Thick Leather with muted '-')
	if not onlyScenes or onlyScenes["watchlist-goblin"] then
	do
		local db = _G.MerchantMasterDB
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local priorSnapRaw, priorSnapParsed, priorSnapHeat = ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache
		local priorWL = db.watchlist and _G.CopyTable(db.watchlist) or nil
		local priorDaily = db.ahDaily
		local priorLive = db.ahPrices and db.ahPrices[econ]
		local savedLive = {}
		local priorSearch = app.ui and app.ui.searchBox and app.ui.searchBox:GetText() or ""

		local wlItems = {
			[13512] = { cur = 278000, base = 252000, qty = 6,  vel = 4.6 },  -- Flask of Supreme Power (+10.3%)
			[10504] = { cur = 168000, base = 152000, qty = 4,  vel = 5.2 },  -- Green Lens (+10.5%)
			[13454] = { cur = 79500,  base = 73500,  qty = 11, vel = 18.4 }, -- Greater Arcane Elixir (+8.2%)
			[13452] = { cur = 68400,  base = 64000,  qty = 9,  vel = 31.2 }, -- Elixir of the Mongoose (+6.9%)
			[13444] = { cur = 41500,  base = 39800,  qty = 18, vel = 42.0 }, -- Major Mana Potion (+4.3%)
			[5634]  = { cur = 24200,  base = 22800,  qty = 14, vel = 26.5 }, -- Free Action Potion (+6.1%)
			[4304]  = { cur = 600,    base = 780,    qty = 52, vel = 68.0 }, -- Thick Leather (-23.1% drop)
			[13468] = { cur = 68000,  base = 76500,  qty = 5,  vel = 12.0 }, -- Black Lotus (-11.1% drop)
			[13463] = { cur = 4200,   base = 5200,   qty = 58, vel = 190.0 }, -- Dreamfoil (-19.2% drop)
			[13465] = { cur = 6800,   base = 8100,   qty = 34, vel = 160.0 }, -- Mountain Silversage (-16.0% drop)
		}
		local day = math.floor(simTime / 86400)
		local wlDaily = {}
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = {}, {}, {}
		local lParts, hParts, mParts = {}, {}, {}
		for id, spec in pairs(wlItems) do
			savedLive[id] = db.ahPrices[econ][id]
			db.ahPrices[econ][id] = { price = spec.cur, qty = spec.qty, at = simTime - 300 }
			seededVelocity[id] = spec.vel
			wlDaily[id] = {
				{ d = day - 3, lastP = spec.base, lastQ = spec.qty + 4, at = simTime - 3 * 86400 },
				{ d = day - 2, lastP = spec.base, lastQ = spec.qty + 2, at = simTime - 2 * 86400 },
				{ d = day - 1, lastP = spec.base, lastQ = spec.qty + 1, at = simTime - 86400 },
				{ d = day,     lastP = spec.cur,  lastQ = spec.qty,     at = simTime - 300 },
			}
			local l, h, m = buildBaronSnapPayloads(id, spec.base, spec.qty, simTime)
			-- Overwrite LATEST minBuyout to cur so 7d trend reflects exact drop/rise
			lParts[#lParts + 1] = string.format("%d:%s,%s,%s,%s,%s,%s",
				id, baronEnc32(spec.cur), baronEnc32(spec.base), baronEnc32(spec.base),
				baronEnc32(spec.qty), baronEnc32(simTime - 300), baronEnc32(spec.base))
			hParts[#hParts + 1] = h
			mParts[#mParts + 1] = m
		end
		db.ahDaily = { [econ] = wlDaily }
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
			string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=%d,heatmapCount=%d}]], simTime - 300, #lParts, #hParts))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, table.concat(lParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT24", econ, table.concat(hParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("HEAT7X24", econ, table.concat(mParts, ";"))

		-- Populate Watchlist with 6 recipes + 4 standalone items
		local WL = assert(ns.Watchlist, "ns.Watchlist missing")
		WL.Clear()
		local wantedRecipes = { [17637] = true, [12622] = true, [17573] = true, [17571] = true, [17580] = true, [6624] = true }
		for _, r in ipairs(ns.RECIPES or {}) do
			if r and r.spellID and wantedRecipes[r.spellID] then
				WL.Add({ kind = "recipe", recipe = r })
			end
		end
		WL.Add({ kind = "item", itemID = 4304 })  -- Thick Leather
		WL.Add({ kind = "item", itemID = 13468 }) -- Black Lotus
		WL.Add({ kind = "item", itemID = 13463 }) -- Dreamfoil
		WL.Add({ kind = "item", itemID = 13465 }) -- Mountain Silversage

		if app.ui and app.ui.searchBox then app.ui.searchBox:SetText("") end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

		sizeSkinViewport("goblin")
		applySkin("goblin")
		switchTab("watchlist")
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(2000)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("watchlist-goblin")

		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = priorSnapRaw, priorSnapParsed, priorSnapHeat
		db.watchlist = priorWL
		db.ahDaily = priorDaily
		if priorLive then
			for id in pairs(wlItems) do db.ahPrices[econ][id] = savedLive[id] end
		end
		if app.ui and app.ui.searchBox then app.ui.searchBox:SetText(priorSearch) end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	end
	end

	-- disenchant-helper-goblin (11-baron-disenchant-helper.png): Disenchant Helper window + Professions Disenchant launcher icon
	if not onlyScenes or onlyScenes["disenchant-helper-goblin"] then
	do
		local DH = assert(ns.DisenchantHelper, "ns.DisenchantHelper missing")
		local db = _G.MerchantMasterDB
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local priorContainer = _G.C_Container
		local priorNumBags = _G.NUM_BAG_SLOTS
		local priorGetProfs, priorGetProfInfo = _G.GetProfessions, _G.GetProfessionInfo
		local priorGetSpellBook = _G.GetSpellBookItemInfo
		local priorProfFrame = _G.ProfessionsFrame
		local priorSpellBookProf = _G.SpellBookProfessionFrame
		local priorProf1 = _G.PrimaryProfession1
		local priorAS = db.disenchantHelperAS
		local priorPanelShown = app.panel:IsShown()

		-- Seed Enchanting dust/essence/shard AH prices for rich EV numbers
		local deMatPrices = {
			[11176] = 1250,  -- Dream Dust
			[16204] = 1950,  -- Illusion Dust
			[11175] = 18500, -- Greater Nether Essence
			[16203] = 44500, -- Greater Eternal Essence
			[11178] = 32000, -- Large Radiant Shard
			[14344] = 49500, -- Large Brilliant Shard
			[14343] = 18000, -- Small Brilliant Shard
			[11177] = 11500, -- Small Radiant Shard
			[10940] = 650,   -- Strange Dust
			[11083] = 950,   -- Soul Dust
			[11137] = 1450,  -- Vision Dust
		}
		local savedMatPrices = {}
		for id, pr in pairs(deMatPrices) do
			savedMatPrices[id] = db.ahPrices[econ][id]
			db.ahPrices[econ][id] = { price = pr, qty = 40, at = simTime - 180 }
		end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

		local deBagItems = {
			[1] = { itemID = 8191,   stackCount = 1, iconFileID = 134256, hyperlink = "|cff1eff00|Hitem:8191:0:0:0:0:0:42:0|h[Turtle Scale Helm of the Owl]|h|r" },
			[2] = { itemID = 8206,   stackCount = 1, iconFileID = 134256, hyperlink = "|cff1eff00|Hitem:8206:0:0:0:0:0:19:0|h[Tough Scorpid Leggings of the Tiger]|h|r" },
			[3] = { itemID = 12428,  stackCount = 1, iconFileID = 136241, hyperlink = "|cff1eff00|Hitem:12428:0:0:0:0:0:11:0|h[Imperial Plate Shoulders]|h|r" },
			[4] = { itemID = 15083,  stackCount = 1, iconFileID = 134256, hyperlink = "|cff1eff00|Hitem:15083:0:0:0:0:0:27:0|h[Wicked Leather Gauntlets of the Bear]|h|r" },
			[5] = { itemID = 254123, stackCount = 1, iconFileID = 132641, hyperlink = "|cff1eff00|Hitem:254123:0:0:0:0:0:14:0|h[Runecloth Cuffs of Intellect]|h|r" },
			[6] = { itemID = 250540, stackCount = 1, iconFileID = 136241, hyperlink = "|cff1eff00|Hitem:250540|h[Shining Mithril Breastplate]|h|r" },
			[7] = { itemID = 254117, stackCount = 1, iconFileID = 132641, hyperlink = "|cff0070dd|Hitem:254117|h[Radiant Sandals]|h|r" },
			[8] = { itemID = 285281, stackCount = 1, iconFileID = 135274, hyperlink = "|cff0070dd|Hitem:285281|h[Arcanite Blacksmith Hammer]|h|r" },
			[9] = { itemID = 250541, stackCount = 1, iconFileID = 136241, hyperlink = "|cff1eff00|Hitem:250541|h[Shining Mithril Pauldrons]|h|r" },
		}
		_G.NUM_BAG_SLOTS = 0
		_G.C_Container = {
			GetContainerNumSlots = function(b) return b == 0 and #deBagItems or 0 end,
			GetContainerNumFreeSlots = function() return 10, 0 end,
			GetContainerItemInfo = function(b, s) return (b == 0) and deBagItems[s] or nil end,
			GetContainerItemLink = function(b, s) return (b == 0 and deBagItems[s]) and deBagItems[s].hyperlink or nil end,
		}

		VIEWPORT_W, VIEWPORT_H = 1440, 900
		_G.UIParent:SetSize(VIEWPORT_W, VIEWPORT_H)
		applySkin("goblin")
		app.panel:Hide()

		-- Left side: WoW Forever ProfessionsFrame.BookPage showing Enchanting -> Disenchant + real MerchantMaster launcher icon
		local profFrame = makeWidget("Frame", "ProfessionsFrame", _G.UIParent)
		profFrame:SetSize(480, 420)
		profFrame:ClearAllPoints()
		profFrame:SetPoint("LEFT", _G.UIParent, "LEFT", 118, 0)
		profFrame:SetFrameStrata("MEDIUM")
		profFrame:SetFrameLevel(1)

		local bookPage = makeWidget("Frame", nil, profFrame)
		bookPage:SetAllPoints(profFrame)
		bookPage:SetFrameStrata("MEDIUM")
		bookPage:SetFrameLevel(100)
		bookPage:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
		bookPage:SetBackdropColor(0.08, 0.07, 0.06, 0.96)
		bookPage:SetBackdropBorderColor(0.62, 0.48, 0.22, 0.94)
		profFrame.BookPage = bookPage

		local sbTitle = bookPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		sbTitle:SetPoint("TOPLEFT", bookPage, "TOPLEFT", 20, -18)
		sbTitle:SetJustifyH("LEFT")
		sbTitle:SetText("Professions")
		sbTitle:SetTextColor(0.97, 0.84, 0.49, 1)

		local sbSub = bookPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sbSub:SetPoint("TOPLEFT", bookPage, "TOPLEFT", 20, -42)
		sbSub:SetJustifyH("LEFT")
		sbSub:SetText("ProfessionsFrame.BookPage  -  Enchanting Disenchant Launcher")
		sbSub:SetTextColor(0.68, 0.66, 0.60, 1)

		local contentFrame = makeWidget("Frame", nil, bookPage)
		contentFrame:SetPoint("TOPLEFT", bookPage, "TOPLEFT", 20, -76)
		contentFrame:SetSize(440, 260)
		contentFrame:SetFrameLevel(101)
		bookPage.ProfessionsContentFrame = contentFrame

		local p1 = makeWidget("Frame", nil, contentFrame)
		p1:SetSize(440, 150)
		p1:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
		p1:SetFrameLevel(102)
		p1:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8 })
		p1:SetBackdropColor(0.11, 0.10, 0.09, 0.95)
		p1:SetBackdropBorderColor(0.46, 0.36, 0.20, 0.80)
		contentFrame.PrimaryProfession1 = p1

		local p1Ico = p1:CreateTexture(nil, "ARTWORK")
		p1Ico:SetSize(38, 38)
		p1Ico:SetPoint("TOPLEFT", p1, "TOPLEFT", 14, -14)
		p1Ico:SetTexture(136244)

		local p1Title = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
		p1Title:SetPoint("TOPLEFT", p1Ico, "TOPRIGHT", 10, -2)
		p1Title:SetJustifyH("LEFT")
		p1Title:SetText("Enchanting")
		p1Title:SetTextColor(0.98, 0.88, 0.56, 1)
		p1.professionName = p1Title

		local p1Rank = p1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		p1Rank:SetPoint("TOPLEFT", p1Title, "BOTTOMLEFT", 0, -4)
		p1Rank:SetJustifyH("LEFT")
		p1Rank:SetText("Artisan  300 / 300")
		p1Rank:SetTextColor(0.50, 0.88, 0.56, 1)

		local sb1 = makeWidget("Button", nil, p1)
		sb1:SetSize(34, 34)
		sb1:SetPoint("TOPLEFT", p1, "TOPLEFT", 18, -82)
		sb1:SetFrameLevel(103)
		sb1.spellID = 7411
		local topTex = sb1:CreateTexture(nil, "ARTWORK")
		topTex:SetAllPoints(sb1)
		topTex:SetTexture(136244)
		sb1.spellString = sb1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		sb1.spellString:SetPoint("LEFT", sb1, "RIGHT", 8, 0)
		sb1.spellString:SetJustifyH("LEFT")
		sb1.spellString:SetText("Enchanting")
		sb1.spellString:SetTextColor(0.95, 0.94, 0.90, 1)
		p1.SpellButton1 = sb1

		local sb2 = makeWidget("Button", nil, p1)
		sb2:SetSize(34, 34)
		sb2:SetPoint("LEFT", sb1, "RIGHT", 140, 0)
		sb2:SetFrameLevel(103)
		sb2.spellID = 13262
		local botTex = sb2:CreateTexture(nil, "ARTWORK")
		botTex:SetAllPoints(sb2)
		botTex:SetTexture(132853)
		sb2.spellString = sb2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		sb2.spellString:SetPoint("LEFT", sb2, "RIGHT", 8, 0)
		sb2.spellString:SetJustifyH("LEFT")
		sb2.spellString:SetText("Disenchant")
		sb2.spellString:SetTextColor(0.95, 0.94, 0.90, 1)
		p1.SpellButton2 = sb2

		_G.ProfessionsFrame = profFrame
		_G.SpellBookProfessionFrame = nil
		_G.PrimaryProfession1 = nil

		local sbNote = bookPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sbNote:SetPoint("TOPLEFT", p1, "BOTTOMLEFT", 4, -18)
		sbNote:SetPoint("TOPRIGHT", p1, "BOTTOMRIGHT", -4, -18)
		sbNote:SetJustifyH("LEFT")
		sbNote:SetWordWrap(true)
		sbNote:SetText("MerchantMaster mounts a 1-click Disenchant Helper launcher directly onto WoW Forever's ProfessionsFrame.BookPage right beside Disenchant.")
		sbNote:SetTextColor(0.76, 0.78, 0.80, 1)

		_G.GetProfessions = function() return 1, nil, nil, nil, nil, nil end
		_G.GetProfessionInfo = function(idx)
			if idx == 1 then return "Enchanting", 136244, 300, 300, 2, 10, 333 end
		end
		_G.GetSpellBookItemInfo = function(slot)
			if slot == 11 then return "SPELL", 7411 end
			if slot == 12 then return "SPELL", 13262 end
		end

		profFrame:Show()
		bookPage:Show()
		contentFrame:Show()
		p1:Show()
		solveLayout(false)
		DH.RefreshProfessionButtons()
		local dhSt = DH.GetState()
		assert(dhSt.profBookShown == true and dhSt.profBookBtn and dhSt.profBookBtn:GetFrameLevel() >= 108,
			"disenchant-helper-goblin must mount BookPage launcher beside Disenchant at level >= 108")

		-- Right side: Standalone Goblin Baron Disenchant Helper window
		DH.Show()
		DH.ScanBags()
		DH.SelectAll()
		DH.SetArcaneSalvager(true)
		local dhFrame = DH.GetState().frame
		assert(dhFrame and dhFrame:IsShown(), "disenchant-helper-goblin must open DisenchantHelper frame")
		dhFrame:ClearAllPoints()
		dhFrame:SetPoint("LEFT", profFrame, "RIGHT", 64, 0)
		drainTimers(500)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("disenchant-helper-goblin", dhFrame)

		-- Clean up
		DH.Hide()
		bookPage:Hide()
		profFrame:Hide()
		_G.ProfessionsFrame = priorProfFrame
		_G.SpellBookProfessionFrame = priorSpellBookProf
		_G.PrimaryProfession1 = priorProf1
		_G.GetProfessions, _G.GetProfessionInfo = priorGetProfs, priorGetProfInfo
		_G.GetSpellBookItemInfo = priorGetSpellBook
		DH.RefreshProfessionButtons()
		_G.C_Container = priorContainer
		_G.NUM_BAG_SLOTS = priorNumBags
		db.disenchantHelperAS = priorAS
		for id in pairs(deMatPrices) do db.ahPrices[econ][id] = savedMatPrices[id] end
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
		if priorPanelShown then app.panel:Show() end
	end
	end

	-- mail-helper-goblin (13-baron-mail-helper.png): Console -> Mail presets (Bank, AH, Main Crafter, Professions + Live Mailbox Preview)
	if not onlyScenes or onlyScenes["mail-helper-goblin"] then
	do
		local MH = assert(ns.MailHelper, "ns.MailHelper missing")
		local db = _G.MerchantMasterDB
		local priorMailPresets = db.mailPresets and _G.CopyTable(db.mailPresets) or nil
		local priorChars = db.chars and _G.CopyTable(db.chars) or nil
		local econ = ns.CurrentEconomyInfo().effectiveKey

		db.chars = db.chars or {}
		db.chars[econ .. "-Forever-Goldbank"] = { name = "Goldbank", realm = "Forever", economy = econ }
		db.chars[econ .. "-Forever-Elara Vance"] = { name = "Elara Vance", realm = "Forever", economy = econ }
		db.chars[econ .. "-Forever-Kazzak"] = { name = "Kazzak", realm = "Forever", economy = econ }
		db.chars[econ .. "-Forever-Zuljin"] = { name = "Zuljin", realm = "Forever", economy = econ }
		db.chars[econ .. "-Forever-Tinker"] = { name = "Tinker", realm = "Forever", economy = econ }

		db.mailPresets = nil
		MH.SetPresetCharacter("bank", "Goldbank")
		MH.SetPresetCharacter("auction", "Elara Vance")
		MH.SetPresetCharacter("mainCrafter", "Kazzak")
		MH.SetPresetCharacter("alchemy", "Grommash")
		MH.SetPresetCharacter("enchanting", "Zuljin")
		MH.SetPresetCharacter("engineering", "Tinker")
		MH.SetPresetCharacter("leatherworking", "Kazzak")
		MH.SetPresetCharacter("tailoring", "Elara Vance")
		MH.SetDisplayOption("showIcon", true)
		MH.SetDisplayOption("showName", true)
		MH.SetDisplayOption("showRole", true)
		MH.SetDisplayOption("warnUnsaved", true)

		sizeSkinViewport("goblin")
		applySkin("goblin")
		switchTab("console_mail")
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(500)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("mail-helper-goblin")

		db.mailPresets = priorMailPresets
		db.chars = priorChars
	end
	end

	-- sell-helper-goblin (14-baron-sell-helper.png): Standalone Auction House "MM Sell" Tab
	if not onlyScenes or onlyScenes["sell-helper-goblin"] then
	do
		local AHSell = assert(ns.AHSellTab, "ns.AHSellTab missing")
		local OF = assert(app.orderFlow, "app.orderFlow missing")
		local priorPanelShown = app.panel:IsShown()
		local priorContainer = _G.C_Container
		local priorNumBags = _G.NUM_BAG_SLOTS
		local priorGetItemInfo = _G.C_Item.GetItemInfo
		local priorAhf = _G.AuctionHouseFrame

		VIEWPORT_W, VIEWPORT_H = 1440, 900
		_G.UIParent:SetSize(VIEWPORT_W, VIEWPORT_H)
		applySkin("goblin")
		app.panel:Hide()

		-- Seed sellable bag inventory across Consumable, Trade Goods, Armor
		local sellBagItems = {
			[1]  = { itemID = 13452, stackCount = 12, quality = 1, classID = 0, maxStack = 20, name = "Elixir of the Mongoose",          iconFileID = "Interface\\Icons\\INV_Potion_32" },
			[2]  = { itemID = 13454, stackCount = 10, quality = 1, classID = 0, maxStack = 20, name = "Greater Arcane Elixir",           iconFileID = "Interface\\Icons\\INV_Potion_25" },
			[3]  = { itemID = 13444, stackCount = 20, quality = 1, classID = 0, maxStack = 20, name = "Major Mana Potion",               iconFileID = "Interface\\Icons\\INV_Potion_76" },
			[4]  = { itemID = 13446, stackCount = 15, quality = 1, classID = 0, maxStack = 20, name = "Major Healing Potion",            iconFileID = "Interface\\Icons\\INV_Potion_54" },
			[5]  = { itemID = 13512, stackCount = 3,  quality = 1, classID = 0, maxStack = 20, name = "Flask of Supreme Power",          iconFileID = "Interface\\Icons\\INV_Potion_41" },
			[6]  = { itemID = 5634,  stackCount = 10, quality = 1, classID = 0, maxStack = 20, name = "Free Action Potion",              iconFileID = "Interface\\Icons\\INV_Potion_80" },
			[7]  = { itemID = 13457, stackCount = 8,  quality = 1, classID = 0, maxStack = 20, name = "Greater Fire Protection Potion",  iconFileID = "Interface\\Icons\\INV_Potion_24" },
			[8]  = { itemID = 13463, stackCount = 40, quality = 1, classID = 7, maxStack = 20, name = "Dreamfoil",                       iconFileID = "Interface\\Icons\\INV_Misc_Herb_Dreamfoil" },
			[9]  = { itemID = 13465, stackCount = 24, quality = 1, classID = 7, maxStack = 20, name = "Mountain Silversage",             iconFileID = "Interface\\Icons\\INV_Misc_Herb_MountainSilversage" },
			[10] = { itemID = 13468, stackCount = 2,  quality = 2, classID = 7, maxStack = 20, name = "Black Lotus",                     iconFileID = "Interface\\Icons\\INV_Misc_Herb_BlackLotus" },
			[11] = { itemID = 4304,  stackCount = 30, quality = 1, classID = 7, maxStack = 20, name = "Thick Leather",                   iconFileID = "Interface\\Icons\\INV_Misc_LeatherScrap_02" },
			[12] = { itemID = 10504, stackCount = 1,  quality = 3, classID = 4, maxStack = 1,  name = "Green Lens",                      iconFileID = "Interface\\Icons\\INV_Misc_Lens_01" },
			[13] = { itemID = 8191,  stackCount = 1,  quality = 2, classID = 4, maxStack = 1,  name = "Turtle Scale Helm",               iconFileID = "Interface\\Icons\\INV_Misc_LeatherScrap_02" },
		}
		local sellInfoByID = {}
		for _, bi in ipairs(sellBagItems) do sellInfoByID[bi.itemID] = bi end
		_G.NUM_BAG_SLOTS = 0
		_G.C_Container = {
			GetContainerNumSlots = function(b) return b == 0 and #sellBagItems or 0 end,
			GetContainerNumFreeSlots = function() return 8, 0 end,
			GetContainerItemInfo = function(b, s)
				local bi = (b == 0) and sellBagItems[s]
				if not bi then return nil end
				return {
					itemID = bi.itemID,
					stackCount = bi.stackCount,
					quality = bi.quality,
					iconFileID = bi.iconFileID,
					isBound = false,
					isLocked = false,
					hyperlink = "|cffffffff|Hitem:" .. bi.itemID .. "::::::::60:::::|h[" .. bi.name .. "]|h|r",
				}
			end,
		}
		_G.C_Item.GetItemInfo = function(q)
			local id = tonumber(q) or tonumber(tostring(q or ""):match("item:(%d+)"))
			local bi = id and sellInfoByID[id]
			if bi then
				local cls = (bi.classID == 0 and "Consumable") or (bi.classID == 4 and "Armor") or "Trade Goods"
				return bi.name, "|cffffffff|Hitem:" .. bi.itemID .. "|h[" .. bi.name .. "]|h|r", bi.quality, 55, 45, cls, cls, bi.maxStack, "", bi.iconFileID, 500, bi.classID, 0, 0
			end
			return priorGetItemInfo(q)
		end
		_G.GetItemInfo = _G.C_Item.GetItemInfo

		-- Build realistic full AuctionHouseFrame host with native tabs + MM Sell selected
		local hostAH = makeWidget("Frame", "AuctionHouseFramePreviewSell", _G.UIParent)
		hostAH:SetSize(1080, 660)
		hostAH:ClearAllPoints()
		hostAH:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 12)
		hostAH:SetFrameStrata("MEDIUM")
		hostAH:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
		hostAH:SetBackdropColor(0.05, 0.06, 0.05, 0.96)
		hostAH:SetBackdropBorderColor(0.68, 0.52, 0.20, 0.95)
		function hostAH:SetDisplayMode() end
		local ahHdr = hostAH:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		ahHdr:SetPoint("TOP", hostAH, "TOP", 0, -6)
		ahHdr:SetText("MerchantMaster - Sell")
		ahHdr:SetTextColor(0.97, 0.84, 0.49, 1)
		hostAH.Tabs = {}
		local tabNames = { "Buy", "Sell", "Auctions" }
		for i, lbl in ipairs(tabNames) do
			local tb = makeWidget("Button", "PreviewAHTab" .. i, hostAH)
			tb:SetSize(84, 26)
			if i == 1 then
				tb:SetPoint("TOPLEFT", hostAH, "BOTTOMLEFT", 14, 0)
			else
				tb:SetPoint("TOPLEFT", hostAH.Tabs[i - 1], "TOPRIGHT", 4, 0)
			end
			tb:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 6 })
			tb:SetBackdropColor(0.08, 0.09, 0.08, 0.92)
			tb:SetBackdropBorderColor(0.45, 0.36, 0.18, 0.85)
			local tfs = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			tfs:SetAllPoints(tb)
			tfs:SetText(lbl)
			tfs:SetTextColor(0.75, 0.72, 0.65, 1)
			hostAH.Tabs[i] = tb
		end
		hostAH:Show()
		_G.AuctionHouseFrame = hostAH

		-- Seed OrderFlow Sell stage queue + live competitor listings on active item
		local st = OF.GetState()
		st.env.atAH = true
		st.notice = nil
		local sl = st.stages.sell
		sl.duration = 3
		sl.undercutMode = "1c"
		sl.activeIndex = 1
		sl.items = {
			{
				key = "sell:13452", itemID = 13452, name = "Elixir of the Mongoose", quality = 1,
				channel = "ah", status = "ready", isCommodity = true, bag = 0, slot = 1,
				totalQty = 12, soldQty = 0, remaining = 12, inBags = 12, postQty = 12,
				liveUnit = 68400, marketRef = 68400, customPrice = nil, listingsScanned = true,
				currentListings = {
					{ price = 68399, quantity = 6,  containsOwnerItem = true },
					{ price = 68400, quantity = 14, containsOwnerItem = false },
					{ price = 68950, quantity = 10, containsOwnerItem = false },
					{ price = 69500, quantity = 20, containsOwnerItem = false },
					{ price = 71000, quantity = 15, containsOwnerItem = false },
					{ price = 72400, quantity = 8,  containsOwnerItem = false },
					{ price = 74000, quantity = 25, containsOwnerItem = false },
				},
			},
			{
				key = "sell:13454", itemID = 13454, name = "Greater Arcane Elixir", quality = 1,
				channel = "ah", status = "ready", isCommodity = true, bag = 0, slot = 2,
				totalQty = 10, soldQty = 0, remaining = 10, inBags = 10, postQty = 10,
				liveUnit = 79500, marketRef = 79500, listingsScanned = true,
			},
			{
				key = "sell:13444", itemID = 13444, name = "Major Mana Potion", quality = 1,
				channel = "ah", status = "ready", isCommodity = true, bag = 0, slot = 3,
				totalQty = 20, soldQty = 0, remaining = 20, inBags = 20, postQty = 20,
				liveUnit = 41500, marketRef = 41500, listingsScanned = true,
			},
			{
				key = "sell:13512", itemID = 13512, name = "Flask of Supreme Power", quality = 1,
				channel = "ah", status = "ready", isCommodity = true, bag = 0, slot = 5,
				totalQty = 3, soldQty = 0, remaining = 3, inBags = 3, postQty = 3,
				liveUnit = 265000, marketRef = 265000, listingsScanned = true,
			},
			{
				key = "sell:10504", itemID = 10504, name = "Green Lens", quality = 3,
				channel = "ah", status = "ready", isCommodity = false, bag = 0, slot = 12,
				totalQty = 1, soldQty = 0, remaining = 1, inBags = 1, postQty = 1,
				liveUnit = 165000, marketRef = 165000, listingsScanned = true,
			},
		}

		AHSell.SetSubTab("prices")
		AHSell.SelectTab()
		if AHSell.tabButton then
			AHSell.tabButton:SetSize(84, 26)
			AHSell.tabButton:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 6 })
			AHSell.tabButton:SetBackdropColor(0.08, 0.28, 0.16, 0.98)
			AHSell.tabButton:SetBackdropBorderColor(0.95, 0.78, 0.32, 0.98)
			local tfs = AHSell.tabButton:GetFontString()
			if tfs then
				tfs:SetText("MM Sell")
				tfs:SetTextColor(1.0, 0.94, 0.72, 1)
			end
		end
		AHSell.Render()
		drainTimers(500)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("sell-helper-goblin", hostAH)

		-- Clean up
		AHSell.HideTab()
		hostAH:Hide()
		_G.AuctionHouseFrame = priorAhf
		_G.C_Container = priorContainer
		_G.NUM_BAG_SLOTS = priorNumBags
		_G.C_Item.GetItemInfo = priorGetItemInfo
		_G.GetItemInfo = priorGetItemInfo
		sl.items = {}
		if priorPanelShown then app.panel:Show() end
	end
	end

	-- sniper-goblin (16-baron-sniper.png): Gap Sniper with multi-tier snapshot order-book depth deals & price ladder
	if not onlyScenes or onlyScenes["sniper-goblin"] then
	do
		local SE = assert(ns.SniperEngine, "ns.SniperEngine missing")
		local db = _G.MerchantMasterDB
		local econ = ns.CurrentEconomyInfo().effectiveKey
		local priorSnapRaw, priorSnapParsed, priorSnapHeat = ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache
		local priorGapDeals = SE.gapDeals
		local priorSniperCfg = db.sniper and _G.CopyTable(db.sniper) or nil
		local priorGetItemInfo = _G.C_Item.GetItemInfo
		local priorAhPrices = db.ahPrices and db.ahPrices[econ]
		local savedAhPrices = {}

		-- Seed rich multi-tier DEPTH + LATEST + VELOCITY (milli-units/day) + REGSALE snapshot with clear >35% gap cliffs
		local gapSeeds = {
			-- { itemID, name, refPrice, vel1000, tiers = { {price, qty}, ... } }
			{ 13468, "Black Lotus",                    78000,  18000,  { { 44000, 3 },  { 76500, 12 }, { 79500, 16 }, { 84000, 20 } } },
			{ 13452, "Elixir of the Mongoose",         72000,  31200,  { { 43500, 6 },  { 70500, 18 }, { 73500, 24 }, { 78000, 30 } } },
			{ 13454, "Greater Arcane Elixir",          82000,  22000,  { { 50000, 5 },  { 80500, 14 }, { 84500, 20 }, { 89000, 25 } } },
			{ 13465, "Mountain Silversage",            8400,   160000, { { 4900, 22 },  { 8200, 65 },  { 8700, 80 },  { 9400, 95 } } },
			{ 13463, "Dreamfoil",                      5400,   190000, { { 3100, 30 },  { 5250, 75 },  { 5700, 90 },  { 6200, 110 } } },
			{ 13444, "Major Mana Potion",              44000,  42000,  { { 27500, 8 },  { 43000, 28 }, { 45500, 40 }, { 49000, 50 } } },
			{ 13457, "Greater Fire Protection Potion", 48000,  14500,  { { 29500, 5 },  { 47000, 16 }, { 50000, 22 }, { 54000, 28 } } },
			{ 4304,  "Thick Leather",                  1100,   68000,  { { 620, 30 },   { 1080, 120 }, { 1200, 150 }, { 1350, 180 } } },
		}
		local gapInfoByID = {}
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = {}, {}, {}
		local lParts, dParts, vParts, rParts = {}, {}, {}, {}
		for _, gs in ipairs(gapSeeds) do
			local id, nm, refP, vel100, tiers = gs[1], gs[2], gs[3], gs[4], gs[5]
			gapInfoByID[id] = { name = nm, icon = guessSkinIconPath(id, nm:lower()) }
			if priorAhPrices then
				savedAhPrices[id] = priorAhPrices[id]
				priorAhPrices[id] = { price = refP, qty = 20, at = simTime - 300 }
			end
			local minP = tiers[1][1]
			local totQ = 0
			local tSegs = {}
			for _, t in ipairs(tiers) do
				totQ = totQ + t[2]
				tSegs[#tSegs + 1] = baronEnc32(t[1]) .. "," .. baronEnc32(t[2])
			end
			lParts[#lParts + 1] = string.format("%d:%s,%s,%s,%s,%s,%s",
				id, baronEnc32(minP), baronEnc32(refP), baronEnc32(refP),
				baronEnc32(totQ), baronEnc32(simTime - 300), baronEnc32(refP))
			dParts[#dParts + 1] = tostring(id) .. ":" .. table.concat(tSegs, "|")
			vParts[#vParts + 1] = tostring(id) .. ":" .. baronEnc32(vel100) .. "," .. baronEnc32(24) .. "," .. baronEnc32(4) .. "," .. baronEnc32(30)
			rParts[#rParts + 1] = tostring(id) .. ":" .. baronEnc32(refP) .. "," .. baronEnc32(vel100) .. "," .. baronEnc32(450)
		end
		_G.C_Item.GetItemInfo = function(q)
			local id = tonumber(q) or tonumber(tostring(q or ""):match("item:(%d+)"))
			local gi = id and gapInfoByID[id]
			if gi then
				return gi.name, "|cffffffff|Hitem:" .. id .. "|h[" .. gi.name .. "]|h|r", 1, 55, 45, "Trade Goods", "Herb", 20, "", gi.icon, 250, 7, 0, 0
			end
			return priorGetItemInfo(q)
		end
		_G.GetItemInfo = _G.C_Item.GetItemInfo

		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
			string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=%d,depthCount=%d,velocityCount=%d,regSaleCount=%d,velocityObsHours=24}]],
				simTime - 300, #gapSeeds, #gapSeeds, #gapSeeds, #gapSeeds))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, table.concat(lParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("DEPTH", econ, table.concat(dParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("VELOCITY", econ, table.concat(vParts, ";"))
		_G.MERCHANTMASTER_LOAD_SNAPSHOTS("REGSALE", econ, table.concat(rParts, ";"))
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

		sizeSkinViewport("goblin")
		applySkin("goblin")
		switchTab("sniper_gap")
		SE.ScanSnapshotForGapDeals(econ, { minGapPct = 15, minRoiPct = 15, minProfitCopper = 10000, minDailySales = 1, minQty = 2 })
		if ns.UISniper and ns.UISniper.Refresh then ns.UISniper.Refresh() end
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(500)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("sniper-goblin")

		SE.ClearGapDeals()
		SE.gapDeals = priorGapDeals or {}
		_G.C_Item.GetItemInfo = priorGetItemInfo
		_G.GetItemInfo = priorGetItemInfo
		if priorAhPrices then
			for id in pairs(gapInfoByID) do priorAhPrices[id] = savedAhPrices[id] end
		end
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = priorSnapRaw, priorSnapParsed, priorSnapHeat
		db.sniper = priorSniperCfg
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	end
	end

	-- console-snapshots-goblin (17-baron-console-snapshots.png): Console -> Snapshot Settings split Windows PowerShell + Linux/Steam Deck view
	if not onlyScenes or onlyScenes["console-snapshots-goblin"] then
	do
		local priorSnapRaw, priorSnapParsed, priorSnapHeat = ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache
		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = {}, {}, {}
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

		sizeSkinViewport("goblin")
		applySkin("goblin")
		switchTab("console_setup")
		if app.refreshSkinLayout then app.refreshSkinLayout() end
		drainTimers(500)
		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("console-snapshots-goblin")

		ns.snapshotRaw, ns.snapshotParsed, ns.snapshotHeatmapCache = priorSnapRaw, priorSnapParsed, priorSnapHeat
		if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
	end
	end

	-- ah-minimap-brand: live Auction House SearchBar (28x28 Logo A open button) + live Minimap button (30x30, ring-free).
	if not onlyScenes or onlyScenes["ah-minimap-brand"] then
	do
		sizeSkinViewport("goblin")
		applySkin("goblin")
		local panelWasShown = app.panel:IsShown()
		app.panel:Hide()

		local function fire(ev, ...)
			for _, w in ipairs(allWidgets) do
				if w._events and w._events[ev] and w._scripts and w._scripts.OnEvent then
					w._scripts.OnEvent(w, ev, ...)
				end
			end
		end

		-- Fire AUCTION_HOUSE_SHOW so MerchantMaster creates the real app.ui.ahBtn via addAHSearchBarButton().
		local ahf = _G.AuctionHouseFrame
		local sb = ahf.SearchBar
		ahf:ClearAllPoints()
		ahf:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
		ahf:SetSize(960, 420)
		ahf:SetFrameStrata("DIALOG")
		ahf:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12 })
		ahf:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
		ahf:SetBackdropBorderColor(0.58, 0.44, 0.18, 0.95)
		ahf:Show()
		fire("AUCTION_HOUSE_SHOW")
		drainTimers(200)
		app.panel:Hide()

		-- Layout realistic AH SearchBar chrome around the real app.ui.ahBtn.
		local titleFs = ahf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		titleFs:SetPoint("TOPLEFT", ahf, "TOPLEFT", 28, -24)
		titleFs:SetJustifyH("LEFT")
		titleFs:SetText("MerchantMaster Logo A  ·  Auction House & Minimap Chrome")
		titleFs:SetTextColor(0.97, 0.84, 0.49, 1)

		local ahLbl = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ahLbl:SetPoint("TOPLEFT", ahf, "TOPLEFT", 28, -72)
		ahLbl:SetJustifyH("LEFT")
		ahLbl:SetText("AUCTION HOUSE SEARCH BAR  (28x28 Logo A coin button between SearchBox and Filters)")
		ahLbl:SetTextColor(0.74, 0.78, 0.84, 1)

		sb:ClearAllPoints()
		sb:SetPoint("TOPLEFT", ahf, "TOPLEFT", 28, -96)
		sb:SetSize(640, 44)
		sb:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8 })
		sb:SetBackdropColor(0.11, 0.12, 0.15, 1)
		sb:SetBackdropBorderColor(0.36, 0.34, 0.28, 1)
		sb:Show()

		sb.FilterButton:ClearAllPoints()
		sb.FilterButton:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
		sb.FilterButton:SetSize(84, 24)
		sb.FilterButton:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 6 })
		sb.FilterButton:SetBackdropColor(0.24, 0.14, 0.12, 1)
		sb.FilterButton:SetBackdropBorderColor(0.68, 0.54, 0.26, 1)
		local filterTxt = sb.FilterButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		filterTxt:SetAllPoints(sb.FilterButton)
		filterTxt:SetText("Filters")
		filterTxt:SetTextColor(0.98, 0.86, 0.45, 1)
		sb.FilterButton:Show()

		sb.SearchBox:ClearAllPoints()
		sb.SearchBox:SetPoint("LEFT", sb, "LEFT", 12, 0)
		if app.ui.ahBtn then
			sb.SearchBox:SetPoint("RIGHT", app.ui.ahBtn, "LEFT", -8, 0)
		end
		sb.SearchBox:SetHeight(24)
		sb.SearchBox:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 6 })
		sb.SearchBox:SetBackdropColor(0.05, 0.06, 0.08, 1)
		sb.SearchBox:SetBackdropBorderColor(0.28, 0.30, 0.36, 1)
		local searchHint = sb.SearchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		searchHint:SetPoint("LEFT", sb.SearchBox, "LEFT", 8, 0)
		searchHint:SetJustifyH("LEFT")
		searchHint:SetText("Search Auction House...")
		searchHint:SetTextColor(0.55, 0.58, 0.64, 1)
		sb.SearchBox:Show()

		assert(app.ui.ahBtn and app.ui.ahBtn:IsShown(), "app.ui.ahBtn must be created and shown on AUCTION_HOUSE_SHOW")

		-- Show live Minimap + live LibDBIcon10_MerchantMaster button (30x30 Logo A, border & background removed).
		local mmLbl = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		mmLbl:SetPoint("TOPLEFT", ahf, "TOPLEFT", 28, -172)
		mmLbl:SetJustifyH("LEFT")
		mmLbl:SetText("MINIMAP BUTTON  (30x30 ring-free Logo A)")
		mmLbl:SetTextColor(0.74, 0.78, 0.84, 1)

		local mm = _G.Minimap
		local savedMmParent = mm:GetParent()
		local savedMmPoints = mm._points
		mm:SetParent(ahf)
		mm:ClearAllPoints()
		mm:SetPoint("TOPLEFT", ahf, "TOPLEFT", 64, -206)
		mm:SetSize(160, 160)
		mm:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
		mm:SetBackdropColor(0.09, 0.14, 0.12, 1)
		mm:SetBackdropBorderColor(0.62, 0.48, 0.22, 1)
		mm:Show()

		local mmZone = mm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		mmZone:SetPoint("CENTER", mm, "CENTER", 0, 0)
		mmZone:SetText("Orgrimmar")
		mmZone:SetTextColor(0.86, 0.82, 0.68, 0.85)

		local DBIcon = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
		local mmBtn = DBIcon and DBIcon.GetMinimapButton and DBIcon:GetMinimapButton("MerchantMaster")
		assert(mmBtn, "LibDBIcon10_MerchantMaster minimap button must exist")
		mmBtn:SetFrameStrata("DIALOG")
		mmBtn:SetFrameLevel(ahf:GetFrameLevel() + 10)
		if DBIcon.Refresh then DBIcon:Refresh("MerchantMaster") end
		mmBtn:Show()

		-- Also show 64px & 256px coin swatches on the right for crispness inspection.
		local swLbl = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		swLbl:SetPoint("TOPLEFT", ahf, "TOPLEFT", 380, -172)
		swLbl:SetJustifyH("LEFT")
		swLbl:SetText("LOGO A TEXTURE SWATCHES  (64px & 256px)")
		swLbl:SetTextColor(0.74, 0.78, 0.84, 1)

		local sw64 = ahf:CreateTexture(nil, "ARTWORK")
		sw64:SetSize(64, 64)
		sw64:SetPoint("TOPLEFT", ahf, "TOPLEFT", 388, -220)
		sw64:SetTexture(ns.ADDON_ICON_SMALL)
		local sw64Lbl = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sw64Lbl:SetPoint("TOP", sw64, "BOTTOM", 0, -8)
		sw64Lbl:SetText("64x64")
		sw64Lbl:SetTextColor(0.82, 0.84, 0.88, 1)

		local sw30 = ahf:CreateTexture(nil, "ARTWORK")
		sw30:SetSize(30, 30)
		sw30:SetPoint("TOPLEFT", ahf, "TOPLEFT", 484, -237)
		sw30:SetTexture(ns.ADDON_ICON_SMALL)
		local sw30Lbl = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sw30Lbl:SetPoint("TOP", sw30, "BOTTOM", 0, -25)
		sw30Lbl:SetText("30x30")
		sw30Lbl:SetTextColor(0.82, 0.84, 0.88, 1)

		local sw256 = ahf:CreateTexture(nil, "ARTWORK")
		sw256:SetSize(128, 128)
		sw256:SetPoint("TOPLEFT", ahf, "TOPLEFT", 552, -200)
		sw256:SetTexture(ns.ADDON_ICON)
		local sw256Lbl = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sw256Lbl:SetPoint("TOP", sw256, "BOTTOM", 0, -8)
		sw256Lbl:SetText("256x256 (at 128px)")
		sw256Lbl:SetTextColor(0.82, 0.84, 0.88, 1)

		flushPendingLayout()
		if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		dumpScene("ah-minimap-brand", ahf)

		-- Clean up preview chrome and restore hidden state.
		mm:Hide()
		mm:SetParent(savedMmParent)
		mm._points = savedMmPoints
		ahf:Hide()
		fire("AUCTION_HOUSE_CLOSED")
		if panelWasShown then
			app.panel:Show()
			app.panel:ClearAllPoints()
			app.panel:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
		end
	end
	end
	end

	-- Live Option A Sales Cart & Option B Minimized AH Buying Mode scenes (Goblin Baron + Dark + Light).
	local runCartBlock = not onlyScenes
	if onlyScenes then
		for k in pairs(onlyScenes) do
			if k:sub(1, 10) == "live-cart-" or k:sub(1, 13) == "live-ahbuyer-" or k:sub(1, 5) == "flow-" then
				runCartBlock = true
				break
			end
		end
	end
	if runCartBlock then
	do
		local function fireEv(ev, ...)
			for _, w in ipairs(allWidgets) do
				if w._events and w._events[ev] and w._scripts and w._scripts.OnEvent then
					w._scripts.OnEvent(w, ev, ...)
				end
			end
		end

		local function seedEightMainOrders()
			seedShoppingScene()
			local db = _G.MerchantMasterDB
			-- Rich V6 showcase order list:
			-- 1. Fire Protection Potion -> active SUB-CRAFT (Fire Oil: CRAFT · ALCH white+cyan+swap + nested mats) + direct AH + Vendor
			-- 2. Free Action Potion -> purple CRAFTABLE (Blackmouth Oil 6370 overridden to "buy": toggleable BUY AH + swap icon!) + AH + Vendor
			-- 3. Greater Frost Protection Potion -> long 31-char Main Order title verifying zero premature truncation
			-- 4-5. Frost Protection Potion + Elixir of the Mongoose
			db.subCraftOverrides = { [6370] = "buy" }
			db.craftOrderQueue = {
				{ spellID = 7257,  outputItemID = 6049,  prof = "alchemy", qty = 5 },
				{ spellID = 6624,  outputItemID = 5634,  prof = "alchemy", qty = 8 },
				{ spellID = 17575, outputItemID = 13456, prof = "alchemy", qty = 4 },
				{ spellID = 7258,  outputItemID = 6050,  prof = "alchemy", qty = 20 },
				{ spellID = 17571, outputItemID = 13452, prof = "alchemy", qty = 5 },
			}
		end

		local function dumpCartLiveScene(sceneName, skinKey, mode, makeEmpty, opts)
			if onlyScenes and not onlyScenes[sceneName] then return end
			opts = opts or {}
			VIEWPORT_W, VIEWPORT_H = 1440, 900
			_G.UIParent:SetSize(VIEWPORT_W, VIEWPORT_H)
			applySkin(skinKey)
			if skinKey == "standard" then setThemeMode(mode or "dark") end
			switchTab("dashboard")
			if makeEmpty then
				if app.clearUnifiedShoppingList then app.clearUnifiedShoppingList() end
			elseif opts.eightOrders then
				seedEightMainOrders()
			else
				seedShoppingScene()
			end
			app.panel:Hide()
			local modal = assert(app.ui.shopModal, "app.ui.shopModal missing")
			local targetW = opts.w or 1160
			local targetH = opts.h or 720
			if _G.MerchantMasterDB then
				_G.MerchantMasterDB.shoppingWindowSize = { w = targetW, h = targetH }
			end
			modal:SetSize(targetW, targetH)
			modal:ClearAllPoints()
			modal:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
			if opts.initialOpenOnly then
				-- Reproduce live WoW sequence: sync first while hidden, then Show() triggering OnShow -> layoutColumns().
				if app.syncUnifiedShoppingList then app.syncUnifiedShoppingList() end
				modal:Show()
			else
				app.toggleShoppingWindow(true)
				if app.refreshUnifiedShoppingDisplay then app.refreshUnifiedShoppingDisplay() end
			end
			drainTimers(500)
			flushPendingLayout()
			if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
			dumpScene(sceneName, modal)
			app.toggleShoppingWindow(false)
			if _G.MerchantMasterDB then _G.MerchantMasterDB.shoppingWindowSize = { w = 1160, h = 720 } end
			modal:SetSize(1160, 720)
		end

		dumpCartLiveScene("live-cart-goblin", "goblin", nil, false, { eightOrders = true, initialOpenOnly = true, w = 1160, h = 720 })
		dumpCartLiveScene("live-cart-compact-goblin", "goblin", nil, false, { eightOrders = true, initialOpenOnly = true, w = 1160, h = 660 })
		dumpCartLiveScene("live-cart-empty-goblin", "goblin", nil, true, { w = 1160, h = 720 })
		dumpCartLiveScene("live-cart-dark", "standard", "dark", false, { w = 1160, h = 720 })
		dumpCartLiveScene("live-cart-light", "standard", "light", false, { w = 1160, h = 720 })

		local ahf = _G.AuctionHouseFrame
		local savedExtended = _G.MerchantMasterDB and _G.MerchantMasterDB.ahBuyerExtended

		local function prepCleanAHFrame(showAH)
			if not ahf then return end
			if ahf.SearchBar and not ahf.SearchBar.StartSearch then
				ahf.SearchBar.StartSearch = function() end
			end
			for _, ch in ipairs(ahf._children or {}) do
				if ch.Hide then ch:Hide() end
			end
			for _, reg in ipairs(ahf._regions or {}) do
				if reg.Hide then reg:Hide() end
			end
			if showAH then
				ahf:ClearAllPoints()
				ahf:SetPoint("LEFT", _G.UIParent, "LEFT", 52, 0)
				ahf:SetSize(610, 560)
				ahf:SetFrameStrata("MEDIUM")
				ahf:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
				ahf:SetBackdropColor(0.08, 0.07, 0.06, 0.94)
				ahf:SetBackdropBorderColor(0.46, 0.36, 0.20, 0.92)
				if not ahf._mmLivePreviewHdr then
					local hdr = ahf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
					hdr:SetPoint("TOPLEFT", ahf, "TOPLEFT", 22, -20)
					hdr:SetJustifyH("LEFT")
					hdr:SetText("Auction House")
					hdr:SetTextColor(0.95, 0.84, 0.56, 1)
					ahf._mmLivePreviewHdr = hdr
					local sub = ahf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					sub:SetPoint("TOPLEFT", ahf, "TOPLEFT", 22, -46)
					sub:SetJustifyH("LEFT")
					sub:SetText("Blizzard Native Buy Screen  -  Docked beside MerchantMaster AH Buyer")
					sub:SetTextColor(0.68, 0.64, 0.56, 1)
					ahf._mmLivePreviewSub = sub
				end
				ahf._mmLivePreviewHdr:Show()
				ahf._mmLivePreviewSub:Show()
				ahf:Show()
				fireEv("AUCTION_HOUSE_SHOW")
			else
				ahf:Hide()
				fireEv("AUCTION_HOUSE_CLOSED")
			end
		end

		local function buildRichAHBuyerTerms()
			return {
				{
					searchString = "Firefin Snapper", isExact = true, quantity = 12, itemID = 6359, unitPrice = 180,
					maxBuyUnit = 210, breakEvenUnit = 245,
					provenance = {
						{ qty = 12, subCraftName = "Fire Oil", subCraftItemID = 6371, subCraftProf = "Alchemy", targetName = "Fire Protection Potion", targetItemID = 6049, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Small Flame Sac", isExact = true, quantity = 10, itemID = 4402, unitPrice = 1450,
					provenance = {
						{ qty = 10, targetName = "Fire Protection Potion", targetItemID = 6049, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Wintersbite", isExact = true, quantity = 20, itemID = 3819, unitPrice = 1000,
					provenance = {
						{ qty = 20, targetName = "Frost Protection Potion", targetItemID = 6050, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Goldthorn", isExact = true, quantity = 20, itemID = 3821, unitPrice = 370,
					maxBuyUnit = 420, breakEvenUnit = 450,
					provenance = {
						{ qty = 20, targetName = "Frost Protection Potion", targetItemID = 6050, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Dreamfoil", isExact = true, quantity = 14, itemID = 13463, unitPrice = 8200,
					provenance = {
						{ qty = 10, targetName = "Elixir of the Mongoose", targetItemID = 13452, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
						{ qty = 4, targetName = "Greater Fire Protection Potion", targetItemID = 13457, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Mountain Silversage", isExact = true, quantity = 10, itemID = 13465, unitPrice = 9600,
					provenance = {
						{ qty = 10, targetName = "Elixir of the Mongoose", targetItemID = 13452, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Black Lotus", isExact = true, quantity = 1, itemID = 13468, unitPrice = 215000,
					maxBuyUnit = 240000, breakEvenUnit = 260000,
					provenance = {
						{ qty = 1, targetName = "Flask of Supreme Power", targetItemID = 13512, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Plaguebloom", isExact = true, quantity = 12, itemID = 13466, unitPrice = 6400,
					provenance = {
						{ qty = 12, targetName = "Major Mana Potion", targetItemID = 13444, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
				{
					searchString = "Rugged Leather", isExact = true, quantity = 12, itemID = 8170, unitPrice = 2400,
					provenance = {
						{ qty = 12, targetName = "Waylaid Crate: Heavy Armor", targetItemID = 8170, sourceKind = "crate_turnin", sourceLabel = "Waylaid Crate" },
					},
				},
				{
					searchString = "Runecloth", isExact = true, quantity = 20, itemID = 14047, unitPrice = 900,
					provenance = {
						{ qty = 20, targetName = "Craftsman's Writ: Runecloth", targetItemID = 14047, sourceKind = "writ_turnin", sourceLabel = "Writ Turn-In" },
					},
				},
				{
					searchString = "Sungrass", isExact = true, quantity = 8, itemID = 8838, unitPrice = 3100,
					provenance = {
						{ qty = 8, targetName = "Greater Arcane Elixir", targetItemID = 13454, sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					},
				},
			}
		end

		local function applyLiveQuotesAndBought(ahOpen)
			local st = app.cartBuyer and app.cartBuyer.GetState and app.cartBuyer.GetState()
			if not (st and st.items) then return end
			-- Mark last 2 items as already bought so Bought vs To Buy overview shows realistic progress & gold spent.
			if #st.items >= 10 and app.cartBuyer.MarkBought then
				app.cartBuyer.MarkBought(10)
				app.cartBuyer.MarkBought(9)
			end
			if ahOpen then
				local liveByIdx = {
					[1] = 150,    -- cheaper (-30c / -17%)
					[2] = 1450,   -- exact match (0c / 0%)
					[3] = 1000,   -- exact match
					[4] = 400,    -- +8%
					[5] = 8850,   -- +8%
					[7] = 266600, -- +24%
				}
				for idx, liveUnit in pairs(liveByIdx) do
					local it = st.items[idx]
					if it and it.targetUnit and it.targetUnit > 0 then
						local diff = liveUnit - it.targetUnit
						local pct = math.floor((diff / it.targetUnit) * 100 + 0.5)
						it.liveUnit = liveUnit
						it.liveTotal = liveUnit * (it.remaining or it.needed or 1)
						it.priceDeltaPct = pct
						it.priceDiffCopper = diff
						it.priceDiffPct = pct
						it.priceDiffTotalCopper = diff * (it.remaining or it.needed or 1)
						it.priceAlert = pct >= 20 and "high" or (pct > 0 and "up" or "ok")
						if it.maxBuyUnit and it.maxBuyUnit > 0 then
							it.buyCapMarginCopper = it.maxBuyUnit - liveUnit
							it.overBuyCap = (liveUnit > it.maxBuyUnit)
						else
							it.buyCapMarginCopper = nil
							it.overBuyCap = nil
						end
					end
				end
			end
		end

		local function dumpAHBuyerLiveScene(sceneName, skinKey, mode, ahOpen, extended, filterDestName, selectIdx)
			if onlyScenes and not onlyScenes[sceneName] then return end
			VIEWPORT_W, VIEWPORT_H = 1440, 900
			_G.UIParent:SetSize(VIEWPORT_W, VIEWPORT_H)
			applySkin(skinKey)
			if skinKey == "standard" then setThemeMode(mode or "dark") end
			switchTab("dashboard")
			_G.MerchantMasterDB.ahBuyerExtended = extended and true or false
			prepCleanAHFrame(ahOpen)
			app.openCartBuyer(buildRichAHBuyerTerms(), "Shopping List")
			applyLiveQuotesAndBought(ahOpen)
			local modal = assert(app.ui.cartBuyerModal, "app.ui.cartBuyerModal missing")
			if app.cartBuyer and app.cartBuyer.SelectItem then
				app.cartBuyer.SelectItem(selectIdx or 1)
			end
			if filterDestName and app.cartBuyer and app.cartBuyer.GetAllDestinations and app.cartBuyer.SetDestinationFilter then
				for _, d in ipairs(app.cartBuyer.GetAllDestinations()) do
					if (d.targetName or d.name or d.key) == filterDestName then
						app.cartBuyer.SetDestinationFilter(d.key)
						break
					end
				end
			elseif app.cartBuyer and app.cartBuyer.SetDestinationFilter then
				app.cartBuyer.SetDestinationFilter(nil)
			end
			if not ahOpen then
				modal:ClearAllPoints()
				modal:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
			else
				modal:ClearAllPoints()
				modal:SetPoint("LEFT", ahf, "RIGHT", 14, 0)
			end
			if modal.Render then modal.Render() end
			drainTimers(500)
			flushPendingLayout()
			if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
			dumpScene(sceneName, modal)
			if app.cartBuyer and app.cartBuyer.SetDestinationFilter then app.cartBuyer.SetDestinationFilter(nil) end
			if app.exitAHBuyingMode then app.exitAHBuyingMode(false) end
		end

		dumpAHBuyerLiveScene("live-ahbuyer-compact-goblin", "goblin", nil, true, false)
		dumpAHBuyerLiveScene("live-ahbuyer-extended-goblin", "goblin", nil, true, true)
		dumpAHBuyerLiveScene("live-ahbuyer-overcap-goblin", "goblin", nil, true, true, nil, 7)
		dumpAHBuyerLiveScene("live-ahbuyer-filtered-goblin", "goblin", nil, true, true, "Fire Protection Potion")
		dumpAHBuyerLiveScene("live-ahbuyer-waiting-goblin", "goblin", nil, false, false)
		dumpAHBuyerLiveScene("live-ahbuyer-extended-dark", "standard", "dark", true, true)
		dumpAHBuyerLiveScene("live-ahbuyer-extended-light", "standard", "light", true, true)

		-- 4-Stage Order & Crafting Task Flow Live Preview Scenes (Stage 2 Vendor, Stage 3 Collect, Stage 4 Craft Compact & Extended)
		do
			prepCleanAHFrame(false)
			local function makeDockHostFrame(name, titleStr, subStr, w, h)
				local f = makeWidget("Frame", name, _G.UIParent)
				f:ClearAllPoints()
				f:SetPoint("LEFT", _G.UIParent, "LEFT", 52, 0)
				f:SetSize(w or 540, h or 520)
				f:SetFrameStrata("MEDIUM")
				f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
				f:SetBackdropColor(0.08, 0.07, 0.06, 0.94)
				f:SetBackdropBorderColor(0.46, 0.36, 0.20, 0.92)
				local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
				hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -20)
				hdr:SetJustifyH("LEFT")
				hdr:SetText(titleStr)
				hdr:SetTextColor(0.95, 0.84, 0.56, 1)
				local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				sub:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -46)
				sub:SetJustifyH("LEFT")
				sub:SetText(subStr)
				sub:SetTextColor(0.68, 0.64, 0.56, 1)
				f:Hide()
				return f
			end

			local origMF, origBF, origMLF, origTSF = _G.MerchantFrame, _G.BankFrame, _G.MailFrame, _G.TradeSkillFrame
			local origGetMNum, origGetMID, origGetMInfo, origGetMMax = _G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack
			local origGetTSLine, origGetNumTS, origGetTSInfo, origGetTSLink = _G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillRecipeLink
			local origUnitName = _G.UnitName
			local origGetBagByID = app.getBagCountByID

			local mockMerchant = makeDockHostFrame("MerchantFrame", "Vendor: Maria Lumere", "Blizzard Merchant Window - Docked beside MerchantMaster Vendor Strip", 540, 520)
			local mockBank = makeDockHostFrame("BankFrame", "Bank Vault", "Blizzard Bank Window - Docked beside MerchantMaster Collect Strip", 540, 520)
			local mockTS = makeDockHostFrame("TradeSkillFrame", "Alchemy", "Blizzard Profession Window - Docked beside MerchantMaster Crafting Strip", 540, 520)

			_G.MerchantFrame = mockMerchant
			_G.BankFrame = mockBank
			_G.TradeSkillFrame = mockTS

			local flowMockBags = {
				[6359] = 12, -- Firefin Snapper (for 6x Fire Oil)
				[3371] = 10, -- Empty Vial (for 6x Fire Oil)
				[6371] = 6,  -- Fire Oil
				[4402] = 6,  -- Small Flame Sac
				[3372] = 6,  -- Leaded Vial
				[13463] = 10, -- Dreamfoil
				[13465] = 8,  -- Mountain Silversage
				[8925] = 10,  -- Crystal Vial
			}
			app.getBagCountByID = function(id) return flowMockBags[id] or 0 end

			local function buildRich4StageRows()
				return {
					{ isMainRow = true, mainGroupKey = "m1", name = "Fire Protection Potion", itemID = 6049, spellID = 7257, prof = "alchemy", qty = 6, sourceKind = "craft_order", sourceLabel = "Crafting Order",
						reagents = { { itemID = 4402, name = "Small Flame Sac", qty = 1 }, { itemID = 6371, name = "Fire Oil", qty = 1 }, { itemID = 3372, name = "Leaded Vial", qty = 1 } } },
					{ indent = 1, mainGroupKey = "m1", isSubBranchRoot = true, subGroupKey = "s1", name = "Fire Oil", itemID = 6371, spellID = 7837, prof = "alchemy", craftProf = "alchemy", qty = 6, makeMyself = true, categoryName = "Fire Protection Potion", sourceKind = "craft_order", sourceLabel = "Crafting Order",
						reagents = { { itemID = 6359, name = "Firefin Snapper", qty = 2 }, { itemID = 3371, name = "Empty Vial", qty = 1 } } },
					{ indent = 2, isSubRow = true, mainGroupKey = "m1", subGroupKey = "s1", parentSubName = "Fire Oil", name = "Firefin Snapper", itemID = 6359, qty = 12, ahUnitPrice = 180, categoryName = "Fire Protection Potion", sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					{ indent = 2, isSubRow = true, mainGroupKey = "m1", subGroupKey = "s1", parentSubName = "Fire Oil", name = "Empty Vial", itemID = 3371, qty = 6, isVendor = true, vendorUnitPrice = 20, categoryName = "Fire Protection Potion", sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					{ indent = 1, mainGroupKey = "m1", name = "Small Flame Sac", itemID = 4402, qty = 0, ownedUsed = 6, categoryName = "Fire Protection Potion", sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					{ indent = 1, mainGroupKey = "m1", name = "Leaded Vial", itemID = 3372, qty = 6, isVendor = true, vendorUnitPrice = 40, categoryName = "Fire Protection Potion", sourceKind = "craft_order", sourceLabel = "Crafting Order" },

					{ isMainRow = true, mainGroupKey = "m2", name = "Elixir of the Mongoose", itemID = 13452, spellID = 17571, prof = "alchemy", qty = 5, sourceKind = "craft_order", sourceLabel = "Crafting Order",
						reagents = { { itemID = 13465, name = "Mountain Silversage", qty = 2 }, { itemID = 13463, name = "Dreamfoil", qty = 2 }, { itemID = 8925, name = "Crystal Vial", qty = 1 } } },
					{ indent = 1, mainGroupKey = "m2", name = "Mountain Silversage", itemID = 13465, qty = 4, ownedUsed = 6, ahUnitPrice = 9600, categoryName = "Elixir of the Mongoose", sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					{ indent = 1, mainGroupKey = "m2", name = "Dreamfoil", itemID = 13463, qty = 0, ownedUsed = 10, categoryName = "Elixir of the Mongoose", sourceKind = "craft_order", sourceLabel = "Crafting Order" },
					{ indent = 1, mainGroupKey = "m2", name = "Crystal Vial", itemID = 8925, qty = 5, isVendor = true, vendorUnitPrice = 500, categoryName = "Elixir of the Mongoose", sourceKind = "craft_order", sourceLabel = "Crafting Order" },

					{ isMainRow = true, mainGroupKey = "m3", name = "Flask of Supreme Power", itemID = 13512, spellID = 17637, prof = "alchemy", qty = 1, sourceKind = "craft_order", sourceLabel = "Crafting Order",
						reagents = { { itemID = 13463, name = "Dreamfoil", qty = 30 }, { itemID = 13465, name = "Mountain Silversage", qty = 10 }, { itemID = 13468, name = "Black Lotus", qty = 1 }, { itemID = 8925, name = "Crystal Vial", qty = 1 } } },
					{ indent = 1, mainGroupKey = "m3", name = "Black Lotus", itemID = 13468, qty = 0, ownedUsed = 1, categoryName = "Flask of Supreme Power", sourceKind = "craft_order", sourceLabel = "Crafting Order" },
				}
			end

			local function flowOwnership(id)
				if id == 4402 then return { bags = 0, bank = 14, mail = 0, alts = {} } end
				if id == 13465 then return { bags = 0, bank = 0, mail = 6, alts = {} } end
				if id == 13463 then return { bags = 10, bank = 0, mail = 0, alts = {} } end
				if id == 13468 then return { bags = 0, bank = 0, mail = 0, alts = { { name = "Bankalt", location = "Bank", qty = 2 } } } end
				return { bags = 0, bank = 0, mail = 0, alts = {} }
			end

			local function dumpFlowScene(sceneName, stageKey, extended, opts)
				if onlyScenes and not onlyScenes[sceneName] then return end
				VIEWPORT_W, VIEWPORT_H = 1440, 900
				_G.UIParent:SetSize(VIEWPORT_W, VIEWPORT_H)
				applySkin("goblin")
				switchTab("dashboard")
				_G.MerchantMasterDB.ahBuyerExtended = extended and true or false
				mockMerchant:Hide(); mockBank:Hide(); mockTS:Hide()

				app.orderFlow.LoadFromShoppingRows(buildRich4StageRows(), {
					title = "Shopping List",
					ownershipProvider = flowOwnership,
				})
				-- Mark Stage 1 AH done so top pipeline bar shows realistic progress (1. AH [OK])
				local ofSt = app.orderFlow.GetState()
				for i = 1, #(ofSt.stages.ah.items or {}) do
					app.cartBuyer.MarkBought(i)
				end

				local hostFrame = nil
				local origUnitCastingInfo = _G.UnitCastingInfo
				if stageKey == "vendor" then
					mockMerchant:Show()
					hostFrame = mockMerchant
					_G.UnitName = function(u) if u == "npc" then return "Maria Lumere" end return origUnitName and origUnitName(u) or "Player" end
					_G.GetMerchantNumItems = function() return 2 end
					_G.GetMerchantItemID = function(s) return (s == 1 and 8925) or (s == 2 and 3372) or nil end
					_G.GetMerchantItemInfo = function(s)
						if s == 1 then return "Crystal Vial", nil, 2500, 5, -1, true, false, false end
						if s == 2 then return "Leaded Vial", nil, 200, 5, -1, true, false, false end
					end
					_G.GetMerchantItemMaxStack = function() return 20 end
					app.orderFlow.SetActiveStage("vendor")
					app.enterOrderFlowMode("vendor")
					app.orderFlow.OnMerchantShow()
					app.orderFlow.SelectVendorItem(1)
				elseif stageKey == "collect" then
					mockBank:Show()
					hostFrame = mockBank
					app.orderFlow.SetActiveStage("collect")
					app.enterOrderFlowMode("collect")
					ofSt.env.atBank = true
					for _, it in ipairs(ofSt.stages.collect.items or {}) do
						if it.source == "bank" then it.availableHere = 14; it.status = "ready" end
					end
					app.orderFlow.SelectCollectItem(1)
				elseif stageKey == "craft" then
					mockTS:Show()
					hostFrame = mockTS
					_G.GetTradeSkillLine = function() return "Alchemy", 300, 300 end
					_G.GetNumTradeSkills = function() return 4 end
					_G.GetTradeSkillInfo = function(i)
						local list = { "Fire Oil", "Fire Protection Potion", "Elixir of the Mongoose", "Flask of Supreme Power" }
						return list[i], "optimal"
					end
					_G.GetTradeSkillRecipeLink = function(i)
						local ids = { 7837, 7257, 17571, 17637 }
						return ids[i] and ("|cffffd000|Henchant:" .. ids[i] .. "|h[R]|h|r") or nil
					end
					app.orderFlow.SetActiveStage("craft")
					app.enterOrderFlowMode("craft")
					app.orderFlow.OnTradeSkillShow()
					app.orderFlow.SelectCraftTask(1)
					if opts and opts.midCast then
						local nowMs = ((_G.GetTime and _G.GetTime()) or simTime or 1000) * 1000
						_G.UnitCastingInfo = function(u)
							if u == "player" then
								return "Fire Oil", "Fire Oil", nil, nowMs - 1400, nowMs + 1600, true, "cast-preview-1", false, 7837
							end
						end
						if app.orderFlow.OnSpellcastStart then
							app.orderFlow.OnSpellcastStart("player", 7837, "cast-preview-1")
						end
					end
				end

				local modal = assert(app.ui.cartBuyerModal, "app.ui.cartBuyerModal missing")
				if hostFrame then
					modal:ClearAllPoints()
					modal:SetPoint("LEFT", hostFrame, "RIGHT", 14, 0)
				end
				if modal.Render then modal.Render() end
				if opts and opts.showAutoCraftConfirm and modal.autoCraftConfirmModal and modal.autoCraftConfirmModal.OpenConfirm then
					modal.autoCraftConfirmModal.OpenConfirm()
				end
				drainTimers(500)
				flushPendingLayout()
				if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
				dumpScene(sceneName, modal)
				if modal.autoCraftConfirmModal and modal.autoCraftConfirmModal.Hide then
					modal.autoCraftConfirmModal:Hide()
				end
				if opts and opts.midCast and app.orderFlow.OnSpellcastStop then
					app.orderFlow.OnSpellcastStop("player", 7837, false)
				end
				_G.UnitCastingInfo = origUnitCastingInfo
				if app.exitAHBuyingMode then app.exitAHBuyingMode(false) end
				mockMerchant:Hide(); mockBank:Hide(); mockTS:Hide()
			end

			dumpFlowScene("flow-collect-goblin", "collect", false)
			dumpFlowScene("flow-vendor-goblin", "vendor", false)
			dumpFlowScene("flow-craft-goblin", "craft", false, { midCast = true })
			dumpFlowScene("flow-craft-extended-goblin", "craft", true)

			_G.MerchantFrame, _G.BankFrame, _G.MailFrame, _G.TradeSkillFrame = origMF, origBF, origMLF, origTSF
			_G.GetMerchantNumItems, _G.GetMerchantItemID, _G.GetMerchantItemInfo, _G.GetMerchantItemMaxStack = origGetMNum, origGetMID, origGetMInfo, origGetMMax
			_G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo, _G.GetTradeSkillRecipeLink = origGetTSLine, origGetNumTS, origGetTSInfo, origGetTSLink
			_G.UnitName = origUnitName
			app.getBagCountByID = origGetBagByID
		end

		prepCleanAHFrame(false)
		_G.MerchantMasterDB.ahBuyerExtended = savedExtended
		app.panel:Show()
	end
	end

	-- Restore the pre-sweep state.
	sizeSkinViewport(priorSkin or "standard")
	applySkin(priorSkin or "standard")
	setThemeMode(priorMode or "dark")
	switchTab(priorTab or "dashboard")
	skinIcons = false
	print("[lua_frame_dump] 22 skin & cart/ah-buyer scenes exported.")
end

print("[lua_frame_dump] All requested scenes exported cleanly.")
