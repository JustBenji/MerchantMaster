-- Offline Lua 5.1 End-to-End Verification Suite for MerchantMaster
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local COUNTS = dofile(testsDir .. "catalog_counts.lua")
local addonDir = testsDir .. "../"

local assertions = 0
local function check(cond, msg)
	assertions = assertions + 1
	if not cond then
		error("ASSERTION FAILED [" .. assertions .. "]: " .. tostring(msg), 2)
	end
end

local function approxEq(a, b, eps, msg)
	eps = eps or 0.01
	check(type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps,
		string.format("%s (got %s, expected %s)", msg or "approxEq", tostring(a), tostring(b)))
end

---------------------------------------------------------------------------------------------------
-- Minimal WoW 16001 Client API Mock
---------------------------------------------------------------------------------------------------
_G.strmatch = string.match
_G.strfind = string.find
_G.strsub = string.sub
_G.strlower = string.lower
_G.strupper = string.upper
_G.format = string.format
_G.tinsert = table.insert
_G.tremove = table.remove
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
local fixtureNow = 1794360000
_G.time = function() return fixtureNow end
_G.GetTime = function() return 1000.0 end
_G.GetLocale = function() return "enUS" end
_G.SecondsToTime = function(s) return tostring(s) .. "s" end
_G.IsShiftKeyDown = function() return false end
_G.PlaySound = function() end
_G.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2 }
_G.UISpecialFrames = {}
_G.SlashCmdList = {}

local secureHookCalls={}
_G.ChatEdit_InsertLink=function() return 'chat-result' end
_G.HandleModifiedItemClick=function() return 'click-result' end
_G.hooksecurefunc = function(tblOrName, nameOrFn, maybeFn)
    if type(tblOrName)=='string' then secureHookCalls[tblOrName]=(secureHookCalls[tblOrName] or 0)+1 end
	if type(tblOrName) == "string" then
		local orig = _G[tblOrName]
		local hook = nameOrFn
		_G[tblOrName] = function(...)
			local r1, r2, r3, r4 = nil, nil, nil, nil
			if orig then r1, r2, r3, r4 = orig(...) end
			hook(...)
			return r1, r2, r3, r4
		end
	elseif type(tblOrName) == "table" and type(nameOrFn) == "string" and type(maybeFn) == "function" then
		local orig = tblOrName[nameOrFn]
		tblOrName[nameOrFn] = function(...)
			local r1, r2, r3, r4 = nil, nil, nil, nil
			if orig then r1, r2, r3, r4 = orig(...) end
			maybeFn(...)
			return r1, r2, r3, r4
		end
	end
end

local function makeWidget(frameType, name, parent)
	local w = {
		_type = frameType or "Frame",
		_name = name,
		_parent = parent,
		_shown = true,
		_scripts = {},
		_events = {},
		_text = "",
		_checked = false,
		_enabled = true,
		_scale = 1.0,
		_width = 100,
		_height = 20,
	}
	function w:GetName() return self._name end
	function w:GetObjectType() return self._type end
	function w:GetParent() return self._parent end
	function w:SetParent(p) self._parent = p end
	w._regions = {}
	function w:GetRegions() return unpack(self._regions or {}) end
	function w:Show()
		self._shown = true
		if self._scripts.OnShow then self._scripts.OnShow(self) end
	end
	function w:Hide()
		self._shown = false
		if self._scripts.OnHide then self._scripts.OnHide(self) end
	end
	function w:SetShown(b) if b then self:Show() else self:Hide() end end
	function w:IsShown() return self._shown and true or false end
	function w:IsVisible() return self._shown and true or false end
	function w:SetSize(x, y) self._width, self._height = x, y end
	function w:SetWidth(x) self._width = x end
	function w:SetHeight(y) self._height = y end
	function w:GetWidth() return self._width end
	function w:GetHeight() return self._height end
	function w:GetLeft() return 200 end
	function w:GetTop() return 900 end
	function w:SetPoint(...)
		self._points = self._points or {}
		local entry = { ... }
		for i, point in ipairs(self._points) do
			if point[1] == entry[1] then self._points[i] = entry; return end
		end
		self._points[#self._points + 1] = entry
	end
	function w:SetAllPoints(rel)
		self._points = { { "TOPLEFT", rel or self._parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or self._parent, "BOTTOMRIGHT", 0, 0 } }
	end
	function w:ClearAllPoints() self._points = {} end
	function w:GetNumPoints() return #(self._points or {}) end
	function w:GetPoint(index)
		local p = (self._points or {})[index or 1]
		if not p then return end
		local anchor, relative, relativeAnchor, x, y = p[1], p[2], p[3], p[4], p[5]
		if type(relative) == "number" then
			x, y, relative, relativeAnchor = relative, relativeAnchor, self._parent, anchor
		else
			relative = relative or self._parent
			if type(relative) == "string" then relative = _G[relative] or relative end
			if type(relativeAnchor) == "number" then
				x, y, relativeAnchor = relativeAnchor, x, anchor
			end
		end
		return anchor, relative, relativeAnchor or anchor, x or 0, y or 0
	end
	function w:SetMovable(...) end
	function w:SetClampedToScreen(...) end
	function w:EnableMouse(...) end
	function w:EnableKeyboard(value) self.keyboard = value and true or false end
	function w:SetPropagateKeyboardInput(value) self.propagate = value and true or false end
	function w:IsMouseOver() return self.mouseOver and true or false end
	function w:RegisterForDrag(...) end
	function w:RegisterForClicks(...) end
	function w:StartMoving() end
	function w:StopMovingOrSizing() end
	function w:SetToplevel(...) end
	function w:Raise() end
	function w:SetFrameStrata(...) end
	function w:SetFixedFrameStrata(...) end
	function w:SetFrameLevel(lvl) self._frameLevel = tonumber(lvl) or 1 end
	function w:SetFixedFrameLevel(...) end
	function w:GetFrameLevel() return self._frameLevel or 1 end
	function w:SetAlpha(...) end
	function w:SetScale(s) self._scale = tonumber(s) or 1.0 end
	function w:GetScale() return self._scale end
	function w:GetEffectiveScale() return self._scale end
	function w:SetTitle(t) self._title = t end
	function w:SetPortraitToAsset(i) self._portrait = i end
	function w:SetScript(ev, fn) self._scripts[ev] = fn end
	function w:GetScript(ev) return self._scripts[ev] end
	function w:SetAttribute(k, v)
		self._attrs = self._attrs or {}
		self._attrs[k] = v
	end
	function w:GetAttribute(k)
		return self._attrs and self._attrs[k] or nil
	end
	function w:HookScript(ev, fn)
		local old = self._scripts[ev]
		self._scripts[ev] = function(...)
			if old then old(...) end
			fn(...)
		end
	end
	function w:RegisterEvent(ev) self._events[ev] = true end
	function w:UnregisterEvent(ev) self._events[ev] = nil end
	function w:SetText(t)
		self._text = tostring(t or "")
		if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, false) end
	end
	function w:GetText() return self._text end
	function w:GetStringWidth()
		local pixels=0
		local clean=(self._text or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
		clean=clean:gsub('|T(.-)|t',function(texture)
			local height,width=texture:match(':(%d+):(%d+)')
			pixels=pixels+(tonumber(width) or tonumber(height) or 12)
			return ''
		end)
		return #clean*6+pixels
	end
	local VALID_FONT_FLAGS = {
		[""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
		["OUTLINE, MONOCHROME"] = true, ["OUTLINE,MONOCHROME"] = true,
		["THICKOUTLINE, MONOCHROME"] = true, ["THICKOUTLINE,MONOCHROME"] = true,
	}
	local VALID_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
	function w:GetFont() return self._fontPath or "Fonts\\FRIZQT__.TTF", self._fontSize or 12, self._fontFlags or "" end
	function w:SetFont(fp, fs, ff)
		if ff ~= nil and type(ff) == "string" and not VALID_FONT_FLAGS[ff] then
			error("WoW C++ SetFont invalid flag: " .. tostring(ff), 2)
		end
		self._fontPath, self._fontSize, self._fontFlags = fp, fs, ff or ""
	end
	function w:SetTextColor(r, g, b, a)
		if r ~= nil and type(r) ~= "number" then
			error("WoW C++ SetTextColor expects numeric r, got " .. type(r), 2)
		end
		self._textColor = { r, g, b, a or 1 }
	end
	function w:GetTextColor() return unpack(self._textColor or { 1, 1, 1, 1 }) end
	function w:SetTextInsets(...) end
	function w:SetFontString(fs) self._fs = fs end
	function w:GetFontString() return self._fs end
	function w:SetChecked(b) self._checked = b and true or false end
	function w:GetChecked() return self._checked end
	function w:SetEnabled(b) self._enabled = b and true or false end
	function w:IsEnabled() return self._enabled and true or false end
	function w:Enable() self._enabled = true end
	function w:Disable() self._enabled = false end
	function w:SetAutoFocus(...) end
	function w:SetNumeric(...) end
	function w:SetMaxLetters(...) end
	function w:HasFocus() return false end
	function w:ClearFocus() end
	function w:SetJustifyH(j) self._justifyH = j end
	function w:GetJustifyH() return self._justifyH or "CENTER" end
	function w:SetJustifyV(...) end
	function w:SetWordWrap(...) end
	function w:SetNonSpaceWrap(...) end
	function w:SetTexture(texture, wrapH, wrapV)
		self._texture = texture
		self._wrapH = wrapH
		self._wrapV = wrapV
	end
	function w:GetTexture() return self._texture end
	function w:SetColorTexture(r, g, b, a)
		if r ~= nil and type(r) ~= "number" then
			error("WoW C++ SetColorTexture expects numeric r, got " .. type(r), 2)
		end
		self._colorTexture = { r, g, b, a }
	end
	function w:SetTexCoord(...) end
	function w:SetAtlas(...) end
	function w:SetBlendMode(...) end
	function w:SetHorizTile(...) end
	function w:SetVertTile(...) end
	function w:SetVertexColor(r, g, b, a)
		if r ~= nil and type(r) ~= "number" then
			error("WoW C++ SetVertexColor expects numeric r, got " .. type(r), 2)
		end
		self._vertexColor = { r, g, b, a }
	end
	function w:GetVertexColor() return 1, 1, 1, 1 end
	function w:SetRotation(rad) self._rotation = rad end
	function w:SetDesaturated(...) end
	function w:SetDrawLayer(layer, sub) self._layer = layer; self._subLevel = sub end
	function w:GetDrawLayer() return self._layer or "ARTWORK", self._subLevel or 0 end
	function w:SetNormalTexture(...) end
	function w:SetPushedTexture(...) end
	function w:SetDisabledTexture(...) end
	function w:SetHighlightTexture(...) end
	function w:GetNormalTexture() return makeWidget("Texture", nil, self) end
	function w:GetPushedTexture() return makeWidget("Texture", nil, self) end
	function w:GetDisabledTexture() return makeWidget("Texture", nil, self) end
	function w:GetCheckedTexture() return makeWidget("Texture", nil, self) end
	function w:GetDisabledCheckedTexture() return makeWidget("Texture", nil, self) end
	function w:GetHighlightTexture() return makeWidget("Texture", nil, self) end
	function w:GetThumbTexture() return makeWidget("Texture", nil, self) end
	function w:CreateAnimationGroup()
		local ag = {}
		function ag:CreateAnimation()
			local an = {}
			function an:SetOrder(...) end
			function an:SetDuration(...) end
			function an:SetFromAlpha(...) end
			function an:SetToAlpha(...) end
			function an:SetStartDelay(...) end
			return an
		end
		function ag:SetToFinalAlpha(...) end
		function ag:Play() end
		function ag:Stop() end
		return ag
	end
	function w:Click(btn)
		if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end
	end
	function w:CreateTexture(n, layer, inherits, subLevel)
		if layer ~= nil and not VALID_LAYERS[layer] then
			error("WoW C++ CreateTexture invalid layer: " .. tostring(layer), 2)
		end
		if subLevel ~= nil and (type(subLevel) ~= "number" or subLevel < -8 or subLevel > 7) then
			error("WoW C++ CreateTexture subLevel out of [-8,7]: " .. tostring(subLevel), 2)
		end
		local t = makeWidget("Texture", n, self)
		t._layer = layer
		t._subLevel = subLevel
		self._regions[#self._regions + 1] = t
		return t
	end
	function w:CreateLine(n, layer)
		local line = self:CreateTexture(n, layer)
		function line:SetThickness(value) self._thickness = value end
		function line:SetStartPoint(...) self._startPoint = { ... } end
		function line:SetEndPoint(...) self._endPoint = { ... } end
		return line
	end
	function w:CreateFontString(n, layer)
		local fs = makeWidget("FontString", n, self)
		fs._layer = layer or "OVERLAY"
		self._regions[#self._regions + 1] = fs
		return fs
	end
	function w:CreateMaskTexture(n) return makeWidget("MaskTexture", n, self) end
	function w:AddMaskTexture(...) end
	if frameType == "GameTooltip" then
		w._lines = {}
		function w:SetOwner(...) self._lines = {} end
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

local createdFrames = {}
_G.UIParent = makeWidget("Frame", "UIParent", nil)
function _G.UIParent:GetWidth() return 1920 end
function _G.UIParent:GetHeight() return 1080 end
_G.GetCursorPosition = function() return 1100, 350 end
_G.Minimap = makeWidget("Frame", "Minimap", UIParent)
function _G.Minimap:GetWidth() return 140 end
function _G.Minimap:GetHeight() return 140 end

_G.CreateFrame = function(frameType, name, parent, template)
	local f = makeWidget(frameType, name, parent)
	if name then _G[name] = f end
	if template == "UICheckButtonTemplate" then
		f.Text = f:CreateFontString(name and (name .. "Text") or nil)
		f.Text:SetText("CheckButton")
	end
	if template == "WowScrollBoxList" then
		f._frames = {}
		function f:SetDataProvider(dp)
			self._dp = dp
			self._frames = {}
			if self._view and self._view._initFn then
				local items = dp:GetCollection()
				local limit = math.min(#items, 15)
				for i = 1, limit do
					local rowWidget = makeWidget("Button", nil, self)
					self._view._initFn(rowWidget, items[i])
					self._frames[#self._frames + 1] = rowWidget
				end
				if #items > limit then
					local lastWidget = makeWidget("Button", nil, self)
					self._view._initFn(lastWidget, items[#items])
					self._frames[#self._frames + 1] = lastWidget
				end
			end
		end
		function f:ForEachFrame(fn)
			for _, fr in ipairs(self._frames or {}) do fn(fr) end
		end
	end
	createdFrames[#createdFrames + 1] = f
	return f
end

_G.CreateScrollBoxListLinearView = function()
	local v = {}
	function v:SetElementExtent(h) self._h = h end
	function v:SetElementExtentCalculator(fn) self._calc = fn end
	function v:SetElementInitializer(frameType, fn) self._initFn = fn end
	function v:SetPadding(...) end
	return v
end

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
		Enumerate = function() return ipairs(items) end,
	}
end

_G.GameTooltip = makeWidget("GameTooltip", "GameTooltip", UIParent)
_G.GameTooltip_Hide = function() GameTooltip:Hide() end

local timerQueue, timerHead, timerTail, drainingTimers = {}, 1, 0, false
_G.C_Timer = {
	After = function(_, fn)
		if type(fn) ~= "function" then return end
		timerTail = timerTail + 1
		timerQueue[timerTail] = fn
		if drainingTimers then return end
		drainingTimers = true
		while timerHead <= timerTail do
			local cb = timerQueue[timerHead]
			timerQueue[timerHead] = nil
			timerHead = timerHead + 1
			local ok, err = pcall(cb)
			if not ok then
				timerQueue, timerHead, timerTail, drainingTimers = {}, 1, 0, false
				error(err, 0)
			end
		end
		timerQueue, timerHead, timerTail, drainingTimers = {}, 1, 0, false
	end,
	NewTimer = function(_, _) return { Cancel = function() end } end,
}

_G.Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		return { _frame = frame, _name = name, GetID = function() return 99 end }
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}

local activeGameRules = { hc = false, rp = false, pvp = false }
local activeFaction = "Horde"
_G.Enum = {
	GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 },
	AuctionHouseSortOrder = { Price = 0, Buyout = 1, Bid = 2, Quantity = 3, Name = 4, Level = 5, TimeRemaining = 6 },
	ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
}
_G.C_GameRules = {
	IsGameRuleActive = function(rule)
		if rule == 1 then return activeGameRules.hc end
		if rule == 2 then return activeGameRules.rp end
		if rule == 3 then return activeGameRules.pvp end
		return false
	end,
}
_G.UnitFactionGroup = function() return activeFaction end
_G.GetRealmName = function() return "Forever" end
_G.UnitName = function() return "StandalonePlayer" end
local mockCVars = { Portal = "EU", scriptProfile = "0" }
_G.GetCVar = function(k) return mockCVars[k] or "" end
_G.SetCVar = _G.SetCVar or function(k, v) mockCVars[tostring(k)] = tostring(v) end
_G.GetBuildInfo = _G.GetBuildInfo or function() return "1.16.0", "60000", "Nov 2026", 16001 end

local tocVersion = nil
local mockAddons = {
	{ name = "MerchantMaster", enabled = true, loaded = true, memKB = 2450.5, version = "@project-version@" },
}
local function findMockAddon(nameOrIdx)
	if type(nameOrIdx) == "number" then return mockAddons[nameOrIdx] end
	for _, a in ipairs(mockAddons) do
		if a.name == nameOrIdx then return a end
	end
end
local function setMockAddon(name, info)
	local existing = findMockAddon(name)
	if info == nil then
		for i, a in ipairs(mockAddons) do
			if a.name == name then
				table.remove(mockAddons, i)
				return
			end
		end
		return
	end
	if existing then
		for k, v in pairs(info) do existing[k] = v end
		existing.name = name
	else
		local entry = { name = name, enabled = true, loaded = false, memKB = 0 }
		for k, v in pairs(info) do entry[k] = v end
		mockAddons[#mockAddons + 1] = entry
	end
end
_G.UpdateAddOnMemoryUsage = _G.UpdateAddOnMemoryUsage or function() end
_G.GetAddOnMemoryUsage = _G.GetAddOnMemoryUsage or function(nameOrIdx)
	local a = findMockAddon(nameOrIdx)
	return (a and a.loaded) and a.memKB or 0
end
_G.GetNumAddOns = _G.GetNumAddOns or function() return #mockAddons end
_G.GetAddOnInfo = _G.GetAddOnInfo or function(nameOrIdx)
	local a = findMockAddon(nameOrIdx)
	if a then return a.name, a.name, nil, a.enabled end
end
_G.GetAddOnMetadata = _G.GetAddOnMetadata or function(nameOrIdx, field)
	local a = findMockAddon(nameOrIdx)
	if not a then return nil end
	if field == "Version" then
		if a.name == "MerchantMaster" and tocVersion then return tocVersion end
		return a.version
	end
	return a[field]
end
_G.IsAddOnLoaded = _G.IsAddOnLoaded or function(name)
	local a = findMockAddon(name)
	return a ~= nil and a.loaded == true
end
_G.GetAddOnEnableState = _G.GetAddOnEnableState or function(playerOrAddon, maybeAddon)
	local target = findMockAddon(maybeAddon) or findMockAddon(playerOrAddon)
	return (target and target.enabled) and 2 or 0
end
_G.EnableAddOn = _G.EnableAddOn or function(name)
	local a = findMockAddon(name)
	if a then a.enabled = true end
end
_G.DisableAddOn = _G.DisableAddOn or function(name)
	local a = findMockAddon(name)
	if a then a.enabled = false end
end
_G.C_AddOns = _G.C_AddOns or {
	GetNumAddOns = _G.GetNumAddOns,
	GetAddOnInfo = _G.GetAddOnInfo,
	GetAddOnMetadata = _G.GetAddOnMetadata,
	IsAddOnLoaded = _G.IsAddOnLoaded,
	GetAddOnEnableState = _G.GetAddOnEnableState,
	EnableAddOn = _G.EnableAddOn,
	DisableAddOn = _G.DisableAddOn,
	UpdateAddOnMemoryUsage = _G.UpdateAddOnMemoryUsage,
	GetAddOnMemoryUsage = _G.GetAddOnMemoryUsage,
}

-- Mock professions: Leatherworking 250, Tailoring 225, Herbalism 250
_G.GetProfessions = function() return 1, 2, nil, nil, 3, nil end
_G.GetProfessionInfo = function(idx)
	if idx == 1 then return "Leatherworking", 133611, 250, 300, 0, 0, 165 end
	if idx == 2 then return "Tailoring", 136249, 225, 300, 0, 0, 197 end
	if idx == 3 then return "Herbalism", 136065, 250, 300, 0, 0, 182 end
end

-- Mock Merchant Reputation: Friendly 1,500 / 6,000 -> totalFromNeutral = 4,500
local mockRep = { reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4500 }
_G.C_Reputation = {
	GetFactionDataByID = function(fid)
		if fid ~= 2586 and fid ~= 2587 then return nil end
		return {
			factionID = fid,
			name = fid == 2586 and "Azeroth Commerce Authority" or "Durotar Supply and Logistics",
			reaction = mockRep.reaction,
			currentReactionThreshold = mockRep.currentReactionThreshold,
			nextReactionThreshold = mockRep.nextReactionThreshold,
			currentStanding = mockRep.currentStanding,
		}
	end,
}
_G.C_CurrencyInfo = {
	GetCurrencyInfo = function(cid)
		if cid == 3402 then return { quantity = 85, iconFileID = 237281 } end
	end,
}

local mockItemBindTypes = {}
local mockVendorSell = {}
_G.C_Item = {
	GetItemInfo = function(id)
		local bt = mockItemBindTypes[id]
		local vs = mockVendorSell[id]
		if bt ~= nil or vs ~= nil then
			return nil, nil, 2, 20, 15, "Armor", "Leather", 1, "", 134400, vs or 1200, 4, 2, bt or 2
		end
		return nil
	end,
	GetItemIconByID = function() return 134400 end,
	RequestLoadItemDataByID = function() end,
	DoesItemExist = function(loc)
		if type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil then
			return _G.C_Container and _G.C_Container.GetContainerItemInfo(loc.bagID, loc.slotIndex) ~= nil
		end
		return false
	end,
}

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
_G.C_Container = {
	GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
	GetContainerNumFreeSlots = function(b) return b == 0 and 10 or 0, 0 end,
	GetContainerItemInfo = function(b, s)
		if b == 0 and s == 1 then
			return { itemID = 248682, stackCount = 1, iconFileID = 236994, hyperlink = "|cff1eff00|Hitem:248682::::::::20:::::|h[Waylaid Crate: Apprentice Herbs]|h|r" }
		elseif b == 0 and s == 2 then
			return { itemID = 2447, stackCount = 8, iconFileID = 134187, hyperlink = "|cffffffff|Hitem:2447::::::::20:::::|h[Peacebloom]|h|r" }
		end
	end,
}

_G.BuyTrainerService = function() end
_G.GetTrainerServiceInfo = function() return nil end
_G.GetTrainerServiceCost = function() return 0 end
_G.DepositGuildBankMoney = function() end
_G.WithdrawGuildBankMoney = function() end
_G.GetGuildInfo = function() return "TestGuild" end
_G.CheckInbox = function() end
_G.GetInboxNumItems = function() return 0, 0 end
_G.GetInboxHeaderInfo = function() return nil end
_G.GetInboxInvoiceInfo = function() return nil end
_G.TakeInboxMoney = function() end
_G.AutoLootMailItem = function() end
_G.IsUsingLegacyAuctionClient = function() return false end
_G.MailFrame = makeWidget("Frame", "MailFrame", UIParent)
_G.MailFrame:SetSize(338, 424)
_G.MailFrame:Hide()
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

_G.WaylaidCratesDB = {
	minimap = { minimapPos = 215 },
	chars = { ["OldChar"] = { bags = { ["Peacebloom"] = 5 } } },
}

---------------------------------------------------------------------------------------------------
-- 1. Parse MerchantMaster.toc & Load All Files in Exact WoW Order
---------------------------------------------------------------------------------------------------
local tocFh = assert(io.open(addonDir .. "MerchantMaster.toc", "r"))
local tocFiles = {}
for line in tocFh:lines() do
	local ver = line:match("^##%s*Version:%s*(%S+)")
	if ver then tocVersion = ver end
	local clean = line:gsub("\r", ""):match("^%s*([^#%s].-)%s*$")
	if clean and clean ~= "" then
		tocFiles[#tocFiles + 1] = clean
	end
end
tocFh:close()
local validTocVersion = tocVersion == "@project-version@" or (type(tocVersion) == "string" and tocVersion:match("^v?%d+%.%d+%.%d+") ~= nil)
check(validTocVersion, "Expected .toc Version @project-version@ or semver, got " .. tostring(tocVersion))
check(#tocFiles == COUNTS.tocFiles, "Expected " .. COUNTS.tocFiles .. " Lua files in .toc, got " .. #tocFiles)

local ns = {}
_G.TakeInboxItem=function() end
local fixture = dofile(testsDir .. "fixture_toc.lua")
local analytics = fixture.Load(addonDir, "MerchantMaster", ns, check)
assert(analytics == _G.MerchantMasterAnalytics, "unified Analytics namespace")

-- Standalone default: zero loaded snapshots. Suites needing snapshot payloads opt in via hostEnv.loadSyntheticSnapshots().
local preSnapDB = _G.MerchantMasterDB
local B32_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
local function encodeBase32(n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return "0" end
	local out = {}
	while n > 0 do
		local rem = n % 32
		out[#out + 1] = B32_DIGITS:sub(rem + 1, rem + 1)
		n = math.floor(n / 32)
	end
	for i = 1, math.floor(#out / 2) do
		out[i], out[#out - i + 1] = out[#out - i + 1], out[i]
	end
	return table.concat(out)
end
local function loadSyntheticSnapshots(opts)
	opts = opts or {}
	local econ = opts.econ or "Normal-Horde"
	local updatedAt = opts.updatedAt or (fixtureNow - 300)
	local source = opts.source or "blizzard"
	local latest = opts.latest
	local velocity = opts.velocity
	local itemCount = opts.itemCount
	local velocityCount = opts.velocityCount or 0
	if type(opts.items) == "table" then
		local lParts, vParts = {}, {}
		local nItems, nVel = 0, 0
		for id, spec in pairs(opts.items) do
			nItems = nItems + 1
			lParts[#lParts + 1] = string.format("%d:%s,%s,%s,%s,%s,%s",
				id,
				encodeBase32(spec.minBuyout or spec.marketValue or 0),
				encodeBase32(spec.marketValue or spec.minBuyout or 0),
				encodeBase32(spec.historical or spec.marketValue or spec.minBuyout or 0),
				encodeBase32(spec.qty or 20),
				encodeBase32(spec.numAuctions or 4),
				encodeBase32(spec.tsDelta or 0))
			if spec.dailySold and spec.dailySold > 0 then
				nVel = nVel + 1
				vParts[#vParts + 1] = string.format("%d:%s,%s,%s,%s",
					id,
					encodeBase32(math.floor(spec.dailySold * 1000 + 0.5)),
					encodeBase32(spec.obsHours or 24),
					encodeBase32(spec.confidence or 2),
					encodeBase32(spec.raw7d or math.floor(spec.dailySold * 7 + 0.5)))
			end
		end
		latest = latest or table.concat(lParts, ";")
		if velocity == nil and #vParts > 0 then velocity = table.concat(vParts, ";") end
		itemCount = itemCount or nItems
		if nVel > 0 then velocityCount = nVel end
	end
	if latest == nil then
		latest = "2447:F,I,H,3O,4,0"
		itemCount = itemCount or 1
	end
	local meta = opts.meta or string.format(
		"return {v=1,updatedAt=%d,source=%q,windowDays=%d,itemCount=%d,heatmapCount=%d,depthCount=%d,velocityCount=%d,velocityObsHours=%d}",
		updatedAt, source, opts.windowDays or 30, itemCount or 1, opts.heatmapCount or 0,
		opts.depthCount or 0, velocityCount, opts.velocityObsHours or (velocity and 24 or 0)
	)
	if opts.registerAddon ~= false then
		setMockAddon("MerchantMaster_Snapshots", { enabled = true, loaded = true, memKB = 640.0, version = opts.version or "1.0.0" })
	end
	if opts.system then
		ns.IngestSnapshotData("SYSTEM", "_global", opts.system)
	end
	ns.IngestSnapshotData("META", econ, meta)
	if latest ~= "" then
		ns.IngestSnapshotData("LATEST", econ, latest)
	end
	if velocity and velocity ~= "" then
		ns.IngestSnapshotData("VELOCITY", econ, velocity)
	end
	if opts.heat24 and opts.heat24 ~= "" then
		ns.IngestSnapshotData("HEAT24", econ, opts.heat24)
	end
	if opts.heat7x24 and opts.heat7x24 ~= "" then
		ns.IngestSnapshotData("HEAT7X24", econ, opts.heat7x24)
	end
	if opts.depth and opts.depth ~= "" then
		ns.IngestSnapshotData("DEPTH", econ, opts.depth)
	end
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end
local function clearSyntheticSnapshots()
	if ns.snapshotRaw then wipe(ns.snapshotRaw) end
	if ns.snapshotParsed then wipe(ns.snapshotParsed) end
	if ns.snapshotHeatmapCache then wipe(ns.snapshotHeatmapCache) end
	ns.snapshotSystem = nil
	setMockAddon("MerchantMaster_Snapshots", nil)
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
end

-- Fire ADDON_LOADED + PLAYER_LOGIN
local eventFrame
for _, f in ipairs(createdFrames) do
	if f._events and f._events.ADDON_LOADED and f._scripts.OnEvent then
		eventFrame = f
		break
	end
end
check(eventFrame ~= nil, "MerchantMaster event frame must exist")
MerchantMasterDB = preSnapDB or {}
MerchantMasterDB.merchantVendorOnly=true; MerchantMasterDB.superListSources=nil
eventFrame._scripts.OnEvent(eventFrame, "ADDON_LOADED", "MerchantMaster")
check(MerchantMasterDB.superListSources and MerchantMasterDB.superListSources.merchant==true and MerchantMasterDB.merchantVendorOnly==false,'login migrates legacy merchant source')
MerchantMasterDB.superListSources={}
eventFrame._scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
check(_G.MerchantMasterDB.crateMode == "cheapest", "Default crateMode initialized")
check(_G.MerchantMasterDB.merchantVendorOnly == false, "Default merchantVendorOnly initialized")
check(_G.MerchantMasterDB.calcRespectStock == true, "Default calcRespectStock initialized")
if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
check(secureHookCalls.ChatEdit_InsertLink==1 and secureHookCalls.HandleModifiedItemClick==1,'item-link integrations use secure post-hooks')
check(ChatEdit_InsertLink('plain')=='chat-result' and HandleModifiedItemClick('plain')=='click-result','secure link integrations preserve API return values')

---------------------------------------------------------------------------------------------------

-- Default hidden AuctionHouseFrame, C_AuctionHouse and C_TradeSkillUI for suites using shared fixture directly
_G.AuctionHouseFrame = makeWidget("Frame", "AuctionHouseFrame", UIParent)
_G.AuctionHouseFrame.SearchBar = makeWidget("Frame", nil, _G.AuctionHouseFrame)
_G.AuctionHouseFrame.SearchBar.FilterButton = makeWidget("Button", nil, _G.AuctionHouseFrame.SearchBar)
_G.AuctionHouseFrame.SearchBar.SearchBox = makeWidget("EditBox", nil, _G.AuctionHouseFrame.SearchBar)
_G.AuctionHouseFrame:Hide()

_G.C_AuctionHouse = {
	IsThrottledMessageSystemReady = function() return true end,
	IsUsingLegacyAuctionClient = function() return false end,
	SendBrowseQuery = function() end,
	SendSearchQuery = function() end,
	SendSellSearchQuery = function() end,
	GetBrowseResults = function()
		return {
			{ itemKey = { itemID = 248682, itemLevel = 1, itemSuffix = 0 }, totalQuantity = 12, minPrice = 280 },
			{ itemKey = { itemID = 2447, itemLevel = 1, itemSuffix = 0 }, totalQuantity = 340, minPrice = 15 },
		}
	end,
	HasFullBrowseResults = function() return true end,
	MakeItemKey = function(id, itemLevel, itemSuffix)
		return { itemID = id, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0 }
	end,
	GetItemKeyFromItem = function(loc)
		if type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil then
			local info = _G.C_Container and _G.C_Container.GetContainerItemInfo(loc.bagID, loc.slotIndex)
			if info and info.itemID then return { itemID = info.itemID, itemLevel = 0, itemSuffix = 0 } end
		end
		return nil
	end,
	HasSearchResults = function() return false end,
	GetItemKeyInfo = function(k)
		local id = type(k) == "table" and k.itemID or nil
		return { itemName = (id and ns.ITEM_NAMES_BY_ID and ns.ITEM_NAMES_BY_ID[id]) or "Item", isCommodity = true }
	end,
	IsSellItemValid = function(loc) return _G.C_Item.DoesItemExist(loc) end,
	GetItemCommodityStatus = function() return _G.Enum.ItemCommodityStatus.Commodity end,
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
	CalculateCommodityDeposit = function() return 100 end,
	PostItem = function() return false end,
	PostCommodity = function() return false end,
	ConfirmPostItem = function() end,
	ConfirmPostCommodity = function() end,
	QueryOwnedAuctions = function() end,
	GetNumOwnedAuctions = function() return 0 end,
	GetOwnedAuctionInfo = function() return nil end,
	CancelAuction = function() end,
	CanCancelAuction = function() return true end,
	GetCancelCost = function() return 0 end,
	GetNumCommoditySearchResults = function() return 2 end,
	GetCommoditySearchResultInfo = function(_, idx)
		if idx == 1 then return { quantity = 20, unitPrice = 14 }
		else return { quantity = 80, unitPrice = 45 } end
	end,
	HasFullCommoditySearchResults = function() return true end,
}

_G.C_TradeSkillUI = _G.C_TradeSkillUI or {
	GetBaseProfessionInfo = function() return nil end,
	GetAllRecipeIDs = function() return {} end,
	GetRecipeInfo = function() return nil end,
}

local hostEnv = {
	ns = ns,
	testsDir = testsDir,
	addonDir = addonDir,
	COUNTS = COUNTS,
	check = check,
	approxEq = approxEq,
	assertions = function() return assertions end,
	makeWidget = makeWidget,
	createdFrames = createdFrames,
	eventFrame = eventFrame,
	fixture = fixture,
	analytics = analytics,
	mockVendorSell = mockVendorSell,
	mockItemBindTypes = mockItemBindTypes,
	mockRep = mockRep,
	mockAddons = mockAddons,
	setMockAddon = setMockAddon,
	loadSyntheticSnapshots = loadSyntheticSnapshots,
	clearSyntheticSnapshots = clearSyntheticSnapshots,
	getFixtureNow = function() return fixtureNow end,
	setFixtureNow = function(t) fixtureNow = t end,
	secureHookCalls = secureHookCalls,
	tocFiles = tocFiles,
	tocVersion = tocVersion,
}
return ns, createdFrames, hostEnv
