-- Analytics integration tests; widget mocks follow test_merchantmaster.lua.
-- Offline Lua 5.1 End-to-End Verification Suite for MerchantMaster v2.2.0
local _srcInfo = debug and debug.getinfo(1, "S").source or ""
local testsDir = (_srcInfo:sub(1, 1) == "@" and _srcInfo:sub(2):match("^(.*[/\\])")) or "./"
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
_G.time = function() return 1794360000 end
_G.GetTime = function() return 1000.0 end
_G.GetLocale = function() return "enUS" end
_G.SecondsToTime = function(s) return tostring(s) .. "s" end
_G.IsShiftKeyDown = function() return false end
_G.PlaySound = function() end
_G.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2 }
_G.UISpecialFrames = {}
_G.SlashCmdList = {}

_G.hooksecurefunc = function(tblOrName, nameOrFn, maybeFn)
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
	function w:SetAllPoints(relative)
		self._points = { { "TOPLEFT", relative or self._parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", relative or self._parent, "BOTTOMRIGHT", 0, 0 } }
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
			if type(relativeAnchor) == "number" then x, y, relativeAnchor = relativeAnchor, x, anchor end
		end
		return anchor, relative, relativeAnchor or anchor, x or 0, y or 0
	end
	function w:SetMovable(...) end
	function w:SetClampedToScreen(...) end
	function w:EnableMouse(...) end
	function w:RegisterForDrag(...) end
	function w:RegisterForClicks(...) end
	function w:StartMoving() end
	function w:StopMovingOrSizing() end
	function w:SetToplevel(...) end
	function w:Raise() end
	function w:SetFrameStrata(...) end
	function w:SetFixedFrameStrata(...) end
	function w:SetFrameLevel(...) end
	function w:SetFixedFrameLevel(...) end
	function w:GetFrameLevel() return 1 end
	function w:SetAlpha(...) end
	function w:SetScale(s) self._scale = tonumber(s) or 1.0 end
	function w:GetScale() return self._scale end
	function w:GetEffectiveScale() return self._scale end
	function w:SetTitle(t) self._title = t end
	function w:SetPortraitToAsset(i) self._portrait = i end
	function w:SetScript(ev, fn) self._scripts[ev] = fn end
	function w:GetScript(ev) return self._scripts[ev] end
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
	function w:GetStringWidth() return #(self._text or "") * 6 end
	function w:GetFont() return self._fontPath or "Fonts\\FRIZQT__.TTF", self._fontSize or 12, self._fontFlags or "" end
	function w:SetFont(fp, fs, ff) self._fontPath, self._fontSize, self._fontFlags = fp, fs, ff or "" end
	function w:SetTextColor(...) end
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
	function w:SetJustifyH(...) end
	function w:SetJustifyV(...) end
	function w:SetWordWrap(...) end
	function w:SetNonSpaceWrap(...) end
	function w:SetTexture(...) end
	function w:SetColorTexture(...) self._color = {...} end
	function w:SetTexCoord(...) end
	function w:SetAtlas(...) end
	function w:SetBlendMode(...) end
	function w:SetHorizTile(...) end
	function w:SetVertTile(...) end
	function w:SetVertexColor(...) end
	function w:GetVertexColor() return 1, 1, 1, 1 end
	function w:SetDesaturated(...) end
	function w:SetDrawLayer(...) end
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
	function w:CreateTexture(n)
		local t = makeWidget("Texture", n, self)
		self._regions[#self._regions + 1] = t
		return t
	end
	function w:CreateFontString(n)
		local fs = makeWidget("FontString", n, self)
		self._regions[#self._regions + 1] = fs
		return fs
	end
	function w:CreateLine(n) return makeWidget("Line", n, self) end
	function w:SetThickness(n) self._thickness = n end
	function w:SetStartPoint(...) self._start = {...} end
	function w:SetEndPoint(...) self._end = {...} end
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

_G.C_Timer = {
	After = function(_, fn) fn() end,
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
	AuctionHouseSortOrder = { Price = 0 },
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
_G.GetCVar = function(k) if k == "Portal" then return "EU" end return "" end

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
}

_G.NUM_BAG_SLOTS = 4
_G.C_Container = {
	GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
	GetContainerItemInfo = function(b, s)
		if b == 0 and s == 1 then
			return { itemID = 248682, stackCount = 1, iconFileID = 236994, hyperlink = "|cff1eff00|Hitem:248682::::::::20:::::|h[Waylaid Crate: Apprentice Herbs]|h|r" }
		elseif b == 0 and s == 2 then
			return { itemID = 2447, stackCount = 8, iconFileID = 134187, hyperlink = "|cffffffff|Hitem:2447::::::::20:::::|h[Peacebloom]|h|r" }
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

local mockTSMPrices = {
	dbminbuyout = {},
	dbmarket = {},
	dbnumauctions = {},
	dbregionsoldperday = {},
	dbregionmarketavg = {},
	dbaltminbuyout = {},
	dbaltmarket = {},
	dbaltnumauctions = {},
	vendorbuy = {},
	vendorsell = {},
}

_G.TSM_API = {
	GetCustomPriceValue = function(key, itemStr)
		local id = tonumber(tostring(itemStr):match("i:(%d+)"))
		if not id then return nil end
		if key == "dbregionsoldperday * 1000" then
			local v = mockTSMPrices.dbregionsoldperday[id]
			return v and (v * 1000) or nil
		end
		local tbl = mockTSMPrices[key]
		return tbl and tbl[id] or nil
	end,
}

local tsmAppHelperCalls = 0
_G.TSM_APPHELPER_LOAD_DATA = function() tsmAppHelperCalls = tsmAppHelperCalls + 1 end

_G.WaylaidCratesDB = {
	minimap = { minimapPos = 215 },
	chars = { ["OldChar"] = { bags = { ["Peacebloom"] = 5 } } },
}
_G.TradeSkillMasterDB = {
	["g@ @coreOptions"] = { auctionDBAltRealm = "PvP-Alliance" },
}

-- All capture-facing APIs exist before either TOC is loaded.
local realOS = os
local ciScale = (realOS and realOS.getenv and (realOS.getenv("CI") == "true" or realOS.getenv("GITHUB_ACTIONS") == "true")) and 2.5 or 1.0
local mockNow, mockGetTime = 1794484800, 1000
local timers, timerID = {}, 0
_G.time = function(t) return t and realOS.time(t) or mockNow end
_G.date = realOS.date
_G.GetTime = function() return mockGetTime end
_G.debugprofilestop = function() return realOS.clock() * 1000 end
_G.C_Timer = {
    After = function(sec, fn)
        timerID = timerID + 1
        timers[#timers + 1] = { at = mockGetTime + sec, fn = fn, id = timerID }
    end,
    NewTimer = function(sec, fn)
        local cancelled = false
        C_Timer.After(sec, function() if not cancelled then fn() end end)
        return { Cancel = function() cancelled = true end }
    end,
}
local function advanceTime(seconds)
    local target, steps = mockGetTime + seconds, 0
    while true do
        local nextIndex
        for i, timer in ipairs(timers) do
            if timer.at <= target and (not nextIndex or timer.at < timers[nextIndex].at or
                (timer.at == timers[nextIndex].at and timer.id < timers[nextIndex].id)) then nextIndex = i end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        mockNow = mockNow + timer.at - mockGetTime; mockGetTime = timer.at
        timer.fn(); steps = steps + 1
        check(steps < 10000, "timer queue must terminate")
    end
    mockNow = mockNow + target - mockGetTime; mockGetTime = target
end
local function fire(event, ...)
    local frames = {}; for i, f in ipairs(createdFrames) do frames[i] = f end
    for _, f in ipairs(frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end
local function link(id) return "|cffffffff|Hitem:" .. id .. ":::::::::|h[Item " .. id .. "]|h|r" end
local mockChar, mockMoney, mockFavor = "AnalyticsA", 10000000, 100
local bag, mail, lootSlots, merchant = {}, {}, {}, {}
local mockFishing, mockQuest, mockZone = false, 0, "Test Marsh"
local mockAuctionItem, mockDeposit, mockPrice = 2447, 60, 50
_G.UnitName = function() return mockChar end
_G.UnitGUID = function() return "Player-TEST-0001" end
_G.GetMoney = function() return mockMoney end
_G.GetRealZoneText = function() return mockZone end
_G.GetSubZoneText = function() return "Test Camp" end
_G.C_Map = { GetBestMapForUnit = function() return 1413 end,
    GetMapInfo = function() return { name = mockZone, mapID = 1413 } end,
    GetPlayerMapPosition = function() return { x = 0.5, y = 0.5, GetXY = function() return 0.5, 0.5 end } end }
_G.C_CurrencyInfo.GetCurrencyInfo = function() return { quantity = mockFavor, name = "Merchant Favor", iconFileID = 237281 } end
_G.C_Item.GetItemCount = function(id) return bag[id] or 0 end
_G.GetItemCount = _G.C_Item.GetItemCount
_G.GetItemInfoInstant = function(id)
    id = tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))
    return id, "Trade Goods", "Other", "", 134400, 7, 0
end
_G.C_Item.GetItemInfoInstant = _G.GetItemInfoInstant
local originalItemInfo = C_Item.GetItemInfo
_G.C_Item.GetItemInfo = function(id)
    local known = originalItemInfo(id)
    if known then return originalItemInfo(id) end
    local n = tonumber(id) or tonumber(tostring(id):match("item:(%d+)")) or 0
    return "Item " .. n, link(n), 1, 1, 1, "Trade Goods", "Other", 200, "", 134400, 1, 7, 0, 0
end
_G.GetItemInfo = _G.C_Item.GetItemInfo
_G.C_Container.GetContainerNumSlots = function(b) return b == 0 and 100 or 0 end
local function bagID(slot)
    local ids = {}; for id, qty in pairs(bag) do if qty > 0 then ids[#ids + 1] = id end end; table.sort(ids)
    return ids[slot]
end
_G.C_Container.GetContainerItemInfo = function(b, s)
    local id = b == 0 and bagID(s)
    if id then return { itemID = id, stackCount = bag[id], iconFileID = 134400, hyperlink = link(id), isLocked = false } end
end
_G.C_Container.GetContainerItemID = function(b, s) local info = C_Container.GetContainerItemInfo(b, s); return info and info.itemID end
_G.C_Container.GetContainerItemLink = function(b, s) local id = C_Container.GetContainerItemID(b, s); return id and link(id) end
_G.C_Container.UseContainerItem = function() end
_G.C_Container.PickupContainerItem = function() end
_G.ItemLocation = { CreateFromBagAndSlot = function(_, b, s)
    return { bagID = b, slotIndex = s, GetBagAndSlot = function() return b, s end,
        IsBagAndSlot = function() return true end, IsValid = function() return true end }
end }
_G.C_AuctionHouse = {
    StartCommoditiesPurchase = function() end, ConfirmCommoditiesPurchase = function() end,
    CancelCommoditiesPurchase = function() end, PostCommodity = function() end, ConfirmPostCommodity = function() end,
    PostItem = function() end, PlaceBid = function() end, CancelAuction = function() end,
    CalculateCommodityDeposit = function() return mockDeposit end, CalculateItemDeposit = function() return mockDeposit end,
    GetCommoditySearchResultInfo = function() return { unitPrice = mockPrice, quantity = 1000 } end,
    GetOwnedAuctionInfo = function() return { auctionID = 1, itemKey = { itemID = mockAuctionItem },
        itemID = mockAuctionItem, quantity = 20, buyoutAmount = 2000, unitPrice = 100 } end,
    GetNumOwnedAuctions = function() return 1 end, GetAuctionItemSubClasses = function() return {} end,
    GetAuctionItemInfoByKey = function(key) return { itemID = key.itemID } end,
    IsThrottledMessageSystemReady = function() return true end, RequestOwnedAuctions = function() end,
    GetItemKeyFromItem = function() return { itemID = mockAuctionItem } end,
    GetReplicateItemInfo = function() end, GetNumReplicateItems = function() return 0 end,
}
_G.C_Item.GetItemID = function(location) return location and C_Container.GetContainerItemID(location.bagID, location.slotIndex) or mockAuctionItem end
_G.C_MerchantFrame = { GetBuybackItemInfo = function() end, GetMerchantItemInfo = function(i) return merchant[i] end }
_G.GetMerchantNumItems = function() return #merchant end
_G.GetMerchantItemInfo = function(i)
    local m = merchant[i]; if not m then return end
    return m.name or ("Item " .. m.id), 134400, m.price or 0, m.stack or 1, -1, true, true, m.favor ~= nil
end
_G.GetMerchantItemLink = function(i) return merchant[i] and link(merchant[i].id) end
_G.GetMerchantItemID = function(i) return merchant[i] and merchant[i].id end
_G.GetMerchantItemCostInfo = function(i) return merchant[i] and merchant[i].favor and 1 or 0 end
_G.GetMerchantItemCostItem = function(i)
    return 237281, merchant[i] and merchant[i].favor or 0, "|Hcurrency:3402|h[Merchant Favor]|h|r", "Merchant Favor"
end
_G.BuyMerchantItem = function() end
_G.SellCursorItem = function() end
_G.BuybackItem = function() end
_G.GetInboxNumItems = function() return #mail, #mail end
_G.GetInboxHeaderInfo = function(i)
    local m = mail[i]; if not m then return end
    return 134400, 0, m.sender or "Auction House", m.subject or "Auction successful", m.money or 0,
        0, m.days or 29, m.returned and 1 or 0, false, false, false, true, false
end
_G.GetInboxInvoiceInfo = function(i)
    local m = mail[i]; if not m then return end
    return m.invoice or "seller", m.name or ("Item " .. m.id), "SyntheticBuyer", m.gross or 1000,
        m.gross or 1000, m.deposit or 0, m.fee or 0, 0, 0, 0, m.qty or 20, true
end
_G.GetInboxItem = function(i)
    local m = mail[i]; if m and m.returned then return m.name or ("Item " .. m.id), m.id, 134400, m.qty or 20, 1, false end
end
_G.GetInboxItemLink = function(i) return mail[i] and mail[i].returned and link(mail[i].id) end
local collectedMail=setmetatable({},{__mode="k"})
local function collectMailMoney(i)
    local m=mail[i]
    if m and not collectedMail[m] then mockMoney=mockMoney+(m.money or 0); collectedMail[m]=true end
end
_G.TakeInboxMoney = collectMailMoney
_G.AutoLootMailItem = collectMailMoney
_G.TakeInboxItem = function() end
_G.DeleteInboxItem = function() end
_G.GetNumLootItems = function() return #lootSlots end
_G.IsFishingLoot = function() return mockFishing end
_G.LOOT_SLOT_ITEM, _G.LOOT_SLOT_MONEY, _G.LOOT_SLOT_CURRENCY = 1, 2, 3
_G.GetLootSlotType = function(i) return lootSlots[i].coin and 2 or 1 end
_G.GetLootSlotInfo = function(i)
    local l = lootSlots[i]; return 134400, l.coin and "12 Copper" or ("Item " .. l.id), l.qty or 1, nil, 1, false, false, nil, false
end
_G.GetLootSlotLink = function(i) return lootSlots[i].id and link(lootSlots[i].id) end
_G.GetLootSourceInfo = function() return 1, "Creature-0-0-0-0-12345-00001", 1 end
_G.LootSlot = function() end
_G.GetQuestID = function() return mockQuest end
_G.GetQuestReward = function() end
_G.GetQuestLogRewardMoney = function() return 0 end
_G.GetQuestMoneyToGet = function() return 0 end
_G.C_QuestLog = { GetQuestInfo = function() return "Synthetic Quest" end, IsQuestFlaggedCompleted = function() return false end }
_G.issecretvalue = function() return false end

local analyticsDir = addonDir .. "Analytics/"
local fixture = dofile(testsDir .. "fixture_toc.lua")
local host, analytics = {}, nil
-- Remember original hook targets so a simulated reload can retire old hooks.
local hookTargets, captureFrames = {}, {}
local secureHook = _G.hooksecurefunc
_G.hooksecurefunc = function(target, key, callback)
    local owner, field = type(target) == "string" and _G or target, type(target) == "string" and target or key
    hookTargets[owner] = hookTargets[owner] or {}
    if not hookTargets[owner][field] then hookTargets[owner][field] = owner[field] end
    return secureHook(target, key, callback)
end
-- Unified modules must operate with WoW's os-free sandbox.
_G.os = nil
analytics = fixture.Load(addonDir, "MerchantMaster", host, check)
fire("ADDON_LOADED", "MerchantMaster")
check(host.UseLegacyPriceAddons == nil, "UseLegacyPriceAddons removed in pure standalone mode")
if host.InvalidatePriceCache then host.InvalidatePriceCache() end
check(host.app.charKey == nil, "host character is unavailable before login")
C_AuctionHouse.StartCommoditiesPurchase(2447, 20)
fire("COMMODITY_PRICE_UPDATED", 50, 1000); fire("COMMODITY_PURCHASE_SUCCEEDED", 2447, 20)
check(next(MerchantMasterLedgerDB.days) == nil, "capture before host login is ignored")
fire("PLAYER_LOGIN")
advanceTime(31)
local Store, Model, Capture, UI, Chart = analytics.Store, analytics.Model, analytics.Capture, analytics.UI, analytics.Chart
captureFrames[Capture.frame] = true
check(Store and Model and Capture and UI and Chart, "one TOC booted all modules")
check(UI.Register() or UI.registered, "analytics provider registered")
local function compute(view, opts)
    local f = { char = "all", period = "all", type = "all", zone = "all", knownCostOnly = false }
    for k, v in pairs(opts or {}) do f[k] = v end
    Model.Invalidate(); return Model.Compute(view, f)
end
local function rawRows(kind)
    local result = {}
    Store.IterDays("0000-00-00", "9999-99-99", function(_, rows)
        for _, row in ipairs(rows) do if not kind or row.type == kind then result[#result + 1] = row end end
    end)
    return result
end
local function exactly(kind, expected)
    local rows = rawRows(kind); check(#rows == expected, kind .. " count: got " .. #rows .. ", expected " .. expected); return rows[1]
end
local function itemRow(id, opts)
    for _, r in ipairs(compute("items", opts).rows or {}) do if r.itemID == id then return r end end
    error("missing item performance row " .. tostring(id), 2)
end
local function current() return Store.CurrentCharAndEcon() end
local function append(kind, id, qty, total, extra, at)
    return Store.Append({ type = kind, itemID = id, qty = qty, total = total, unit = qty > 0 and math.abs(total) / qty or 0,
        time = at or mockNow, where = mockZone, extra = extra or {} })
end
local function reloadCapture(login)
    for frame in pairs(captureFrames) do frame._events = {} end
    for owner, fields in pairs(hookTargets) do for field, original in pairs(fields) do owner[field] = original end end
    assert(loadfile(analyticsDir .. "Capture.lua"))("MerchantMaster", host)
    Capture = analytics.Capture; captureFrames[Capture.frame] = true
    Capture.frame._scripts.OnEvent(Capture.frame, "ADDON_LOADED", "MerchantMaster")
    -- These reloads occur inside an already logged-in host; restore its hooks.
    if host.app.charKey then Capture.InstallHooks() end
    if login then Capture.frame._scripts.OnEvent(Capture.frame, "PLAYER_LOGIN") end
end
local function reset()
    timers = {}; bag, mail, lootSlots, merchant = {}, {}, {}, {}
    mockFishing, mockQuest, mockMoney, mockFavor = false, 0, 10000000, 100
    mockChar = "AnalyticsA"; mockAuctionItem, mockDeposit, mockPrice = 2447, 60, 50
    host.app.charKey = "Normal-Horde-Forever-AnalyticsA"
    host.app.panel:Hide()
    host.app.char.bags, host.app.char.bank, host.app.char.mail = {}, {}, {}
    host.app.char.boundBags, host.app.char.boundBank, host.app.char.bought, host.app.char.gear = {}, {}, {}, {}
    _G.MerchantMasterLedgerDB = {}; Store.Init(); Model.Invalidate()
    Store.onChange = function() Model.Invalidate(); UI.ScheduleRefresh() end
    MerchantMasterDB.anChar, MerchantMasterDB.anPeriod, MerchantMasterDB.anType, MerchantMasterDB.anZone = "all", "30d", "all", "all"
    MerchantMasterDB.anKnownCostOnly, MerchantMasterDB.anItemMode = false, "profit"
    issecretvalue = function() return false end
    reloadCapture(false)
    Store.InitRecon(Store.CurrentCharAndEcon(), mockMoney)
end
local function buy(id, qty, unit, outcome)
    mockPrice = unit
    C_AuctionHouse.StartCommoditiesPurchase(id, qty)
    fire("COMMODITY_PRICE_UPDATED", unit, qty * unit)
    C_AuctionHouse.ConfirmCommoditiesPurchase(id, qty)
    fire(outcome or "COMMODITY_PURCHASE_SUCCEEDED", id, qty)
end
local function post(id, qty, unit)
    mockAuctionItem = id; bag[id] = math.max(bag[id] or 0, qty)
    local location = ItemLocation:CreateFromBagAndSlot(0, 1)
    C_AuctionHouse.PostCommodity(location, 1, qty, unit)
    C_AuctionHouse.ConfirmPostCommodity(location, 1, qty, unit)
    fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
end
local function sale(id, qty, gross, deposit, fee)
    mail = { { id = id, qty = qty, gross = gross, deposit = deposit, fee = fee,
        money = gross - fee + deposit, name = "Item " .. id } }
    fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE"); TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    advanceTime(0.6)
end
local failures, cases = {}, 0
local function test(name, fn)
    cases = cases + 1
    local ok, err = xpcall(function() reset(); fn() end, debug.traceback)
    if ok then print("PASS " .. name) else failures[#failures + 1] = name .. ": " .. tostring(err); print("FAIL " .. name .. ": " .. tostring(err)) end
end

test("T1 confirmed commodity purchase and basis", function()
    buy(2447, 20, 50)
    local r = exactly("AH_BUY", 1); check(r.total == -1000 and r.qty == 20, "confirmed purchase cash and quantity")
    local _, econ = current(); local qty, avg = Store.Basis(econ, 2447)
    check(qty == 20 and avg == 50, "20 units at 50c basis")
end)
test("T2 failed and abandoned commodity purchase", function()
    buy(2447, 20, 50, "COMMODITY_PURCHASE_FAILED"); advanceTime(31); exactly("AH_BUY", 0)
    C_AuctionHouse.StartCommoditiesPurchase(2447, 20); fire("COMMODITY_PRICE_UPDATED", 50, 1000)
    C_AuctionHouse.ConfirmCommoditiesPurchase(2447, 20); fire("AUCTION_HOUSE_CLOSED"); advanceTime(31)
    exactly("AH_BUY", 0)
end)
test("T3 posting confirmation is deduplicated", function()
    post(2447, 20, 100); advanceTime(1)
    local r = exactly("AH_POST", 1); check(r.total == -60, "posting books one deposit")
    local char = current(); local lots = Store.Lots(char, 2447)
    check(#lots == 1 and lots[1].qty == 20, "one open lot")
end)
test("T4 sale invoice dedupe survives relog", function()
    buy(2447, 20, 20); post(2447, 20, 50); sale(2447, 20, 1000, 60, 50)
    local r = exactly("AH_SELL", 1); check(r.total == 1010 and r.cogs == 400, "mail cash includes returned deposit, COGS uses basis")
    check(itemRow(2447).profit == 550, "realized profit excludes returned deposit")
    -- Recreate the capture module and its hooks while retaining only persisted DB.
    fire("MAIL_CLOSED")
    local saved = MerchantMasterLedgerDB
    reloadCapture(true)
    check(MerchantMasterLedgerDB == saved, "relog retains ledger DB")
    fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE"); TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1); advanceTime(1)
    exactly("AH_SELL", 1)
end)
test("T5 expire mail closes lot and loses deposit", function()
    post(2447, 20, 50)
    mail = { { id = 2447, qty = 20, returned = true, invoice = "", subject = "Auction expired: Item 2447", deposit = 60, money = 0 } }
    fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE"); TakeInboxItem(1, 1); fire("CLOSE_INBOX_ITEM", 1); advanceTime(1)
    local r = exactly("AH_EXPIRE", 1)
    check(r.total == 0 and r.extra.depLost == 60, "expiry loses deposit with zero cash flow")
    local char = current(); check(#Store.Lots(char, 2447) == 0, "expired lot closed")
end)
test("T6 one-hour reprices, two-hour relists and sale duration", function()
    append("AH_BUY", 2447, 60, -600)
    append("AH_POST", 2447, 20, -60); append("AH_CANCEL", 2447, 20, 0)
    advanceTime(1800); append("AH_POST", 2447, 20, -60)
    local r = itemRow(2447); check(r.relists == 0 and r.reprices == 20, "within one hour is repricing")
    append("AH_CANCEL", 2447, 20, 0); advanceTime(7200)
    local postedAt = mockNow; append("AH_POST", 2447, 20, -60)
    r = itemRow(2447); check(r.relists == 20 and r.reprices == 20, "after two hours is relisting")
    advanceTime(86400); append("AH_SELL", 2447, 20, 1900, { gross = 2000, fee = 100, saleAt = mockNow })
    approxEq(itemRow(2447).daysToSell, (mockNow - postedAt) / 86400, 0.000001, "sale duration uses latest lot")
end)
test("T7 vendor buy confirmed by money delta", function()
    merchant = { { id = 2447, price = 100, stack = 1 } }; fire("MERCHANT_SHOW")
    BuyMerchantItem(1, 5); mockMoney = mockMoney - 500; fire("PLAYER_MONEY"); advanceTime(1)
    local r = exactly("VENDOR_BUY", 1); check(r.total == -500 and r.unit == 100 and r.qty == 5, "vendor stack accounting")
end)
test("T8 unconfirmed vendor timeout uses controllable clock", function()
    merchant = { { id = 2447, price = 100, stack = 1 } }; fire("MERCHANT_SHOW")
    BuyMerchantItem(1, 5); advanceTime(9); exactly("VENDOR_BUY", 0)
    advanceTime(2); local r = exactly("VENDOR_BUY", 1)
    check(r.unconfirmed or r.extra.unconfirmed, "10-second timeout marks unconfirmed")
end)
test("T9 loot item and copper are daily aggregates", function()
    lootSlots = { { id = 2447, qty = 3 }, { coin = true, qty = 12 } }
    fire("LOOT_READY"); fire("LOOT_OPENED"); bag[2447] = 3
    mockMoney = mockMoney + 12; fire("BAG_UPDATE_DELAYED"); fire("PLAYER_MONEY"); fire("LOOT_SLOT_CLEARED", 1); fire("LOOT_SLOT_CLEARED", 2)
    fire("LOOT_CLOSED"); advanceTime(2)
    local char, econ = current(); local counters = MerchantMasterLedgerDB.loot[Store.DayKey()][char]
    check(counters["2447|Mob|" .. mockZone] == 3, "mob loot quantity aggregated")
    check(counters["0|Money|" .. mockZone] == 12, "loot money aggregated")
    check(#rawRows("LOOT") == 0, "loot does not spam raw rows")
    local qty, avg = Store.Basis(econ, 2447); check(qty == 3 and avg == 0, "loot adds zero-cost basis")
    for _, kind in ipairs({ "all", "loot" }) do
        local found = false; for _, r in ipairs(compute("ledger", { type = kind }).rows) do if r.itemID == 2447 then found = true end end
        check(found, "aggregate appears in " .. kind .. " ledger")
    end
end)
test("T10 fishing source survives loot aggregation", function()
    mockFishing = true; lootSlots = { { id = 6291, qty = 2 } }
    fire("LOOT_READY"); fire("LOOT_OPENED"); bag[6291] = 2; fire("BAG_UPDATE_DELAYED"); fire("LOOT_CLOSED"); advanceTime(2)
    local char = current(); local counters = MerchantMasterLedgerDB.loot[Store.DayKey()][char]
    check(counters["6291|Fishing|" .. mockZone] == 2, "fishing tagged correctly")
end)
test("T11 craft consumes reagent basis and prices output", function()
    local rec = host.RECIPES[1]
    check(rec and rec.spellID and rec.reagents and #rec.reagents > 0, "real recipe fixture exists")
    local output = rec.outputItemID or rec.itemID; local made, totalCost = rec.numMade or 1, 0
    local _, econ = current()
    for _, reagent in ipairs(rec.reagents) do
        local id, qty = reagent.itemID or reagent[1], reagent.qty or reagent[2]
        bag[id] = qty; Store.AddBasis(econ, id, qty, qty * 25); totalCost = totalCost + qty * 25
    end
    fire("BAG_UPDATE_DELAYED"); advanceTime(1)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Test", rec.spellID)
    bag[output] = made
    for _, reagent in ipairs(rec.reagents) do bag[reagent.itemID or reagent[1]] = 0 end
    fire("BAG_UPDATE_DELAYED"); advanceTime(2)
    exactly("CRAFT", 1)
    local qty, avg = Store.Basis(econ, output); check(qty == made, "crafted output basis quantity")
    approxEq(avg, totalCost / made, 0.001, "output uses consumed reagent cost")
    for _, reagent in ipairs(rec.reagents) do check(Store.Basis(econ, reagent.itemID or reagent[1]) == 0, "reagent consumed") end
end)
test("T12 writ cost, learned zone, FIFO pouches and Waylaid favor", function()
    local w
    for _, candidate in ipairs(host.WRITS) do if candidate.pouchItemID == 284584 or candidate.pouchItemID == 284585 then w = candidate; break end end
    check(w ~= nil, "real Journeyman or Expert writ exists")
    local _, econ = current()
    Store.AddBasis(econ, w.itemID, 1, 100); Store.AddBasis(econ, w.requiredItemID, w.qty, w.qty * 30)
    bag[w.itemID], bag[w.requiredItemID] = 1, w.qty
    mockQuest = w.questID; fire("QUEST_COMPLETE"); GetQuestReward(1)
    fire("QUEST_TURNED_IN", w.questID, 0, 0); advanceTime(1)
    local r = exactly("WRIT_TURNIN", 1); check(r.cogs == 100 + w.qty * 30, "writ freezes consumed cost")
    local learned = MerchantMasterDB.learnedWritZones and MerchantMasterDB.learnedWritZones[w.itemID]
    check(learned ~= nil, "writ zone learned")
    local learnedQuery = { itemID = w.itemID }
    local zone, source = host.GetWritZoneInfo(learnedQuery); check(zone == mockZone and source == "learned", "learned zone returned when no static zone overrides it")
    check(host.GetWritZoneLabel(learnedQuery):find(mockZone, 1, true) ~= nil, "learned zone label")
    -- Different writ IDs in the same pouch tier make FIFO attribution observable.
    local w2
    for _, candidate in ipairs(host.WRITS) do if candidate.itemID ~= w.itemID and candidate.pouchItemID == w.pouchItemID then w2 = candidate; break end end
    check(w2 ~= nil, "second writ in same pouch tier exists")
    Store.AddBasis(econ, w2.itemID, 1, 100); Store.AddBasis(econ, w2.requiredItemID, w2.qty, w2.qty * 30)
    advanceTime(31); mockQuest = w2.questID; GetQuestReward(1); fire("QUEST_TURNED_IN", w2.questID, 0, 0); advanceTime(1)
    local pouch = w.pouchItemID or 284584; check(pouch == 284584 or pouch == 284585, "supported coin pouch fixture")
    bag = { [pouch] = 2 }; fire("BAG_UPDATE_DELAYED"); advanceTime(1)
    C_Container.UseContainerItem(0, 1); mockMoney = mockMoney + 75; fire("PLAYER_MONEY"); advanceTime(1)
    local p = exactly("POUCH_MONEY", 1); check(p.total == 75 and p.extra.writItemID == w.itemID, "pouch FIFO attribution")
    C_Container.UseContainerItem(0, 1); mockMoney = mockMoney + 125; fire("PLAYER_MONEY"); advanceTime(1)
    local pouches = rawRows("POUCH_MONEY"); check(#pouches == 2 and pouches[2].extra.writItemID == w2.itemID, "second pouch goes to second writ in FIFO")
    local before = compute("writs"); approxEq(before.perRep, (200 + (w.qty + w2.qty) * 30 - 200) / (w.rep + w2.rep), 0.001, "writ actual running average")
    local tier, reward
    for t, rewards in pairs(host.DEFAULT_REWARDS) do if rewards[1] and rewards[1].sealedID then tier, reward = t, rewards[1]; break end end
    check(reward and tier, "real Waylaid reward exists")
    Store.AddBasis(econ, reward.sealedID, 1, 1000); bag[reward.sealedID] = 1
    mockQuest = reward.questID; GetQuestReward(1); fire("QUEST_TURNED_IN", mockQuest, 0, reward.copper or 0); advanceTime(1)
    exactly("CRATE_TURNIN", 1)
    approxEq(compute("writs").favorPrice, math.max(0, 1000 - (reward.copper or 0)) / reward.tokens, 0.001, "favor running average")
end)
test("T13 favor recipe purchase and payback avoid double booking", function()
    local rec
    for _, candidate in ipairs(host.RECIPES) do if candidate.recipeItemID and (candidate.favorCost or 0) > 0 then rec = candidate; break end end
    check(rec ~= nil, "real favor recipe exists")
    append("CRATE_TURNIN", 248765, 1, 0, { favor = 10, reagentCost = 1000, bundleCost = 1000 })
    local price = Store.GetRunningFavorPrice(); check(price > 0, "favor has nonzero frozen price")
    merchant = { { id = rec.recipeItemID, price = 0, stack = 1, favor = rec.favorCost } }
    fire("MERCHANT_SHOW"); BuyMerchantItem(1, 1); mockFavor = mockFavor - rec.favorCost; fire("CURRENCY_DISPLAY_UPDATE", 3402, mockFavor)
    advanceTime(11)
    local r = exactly("FAVOR_SPEND", 1); exactly("VENDOR_BUY", 0)
    check(r.itemID == rec.recipeItemID, "recipe scroll identity recorded")
    approxEq(r.extra.favorCopperValue, math.floor(rec.favorCost * price + 0.5), 0.001, "favor cost frozen in whole copper at purchase")
    local output = rec.outputItemID or rec.itemID
    append("AH_BUY", output, 10, -100)
    append("AH_SELL", output, 10, r.extra.favorCopperValue + 5000, { gross = r.extra.favorCopperValue + 5000, fee = 0 })
    local found
    for _, investment in ipairs(compute("invest").recipes) do if investment.itemID == rec.recipeItemID then found = investment end end
    check(found and found.unitsSold == 10 and found.isPaidBack, "crafted output sales pay back recipe investment")
    approxEq(found.investCost, r.extra.favorCopperValue, 0.001, "investment cost booked once")
end)
test("T14 missing basis estimated and same-economy alt basis retained", function()
    local _, econ = current(); Store.AddBasis(econ, 2447, 2, 100)
    host.app.charKey = "Normal-Horde-Forever-AnalyticsB"; mockChar = "AnalyticsB"
    check(Store.Basis(econ, 2447) == 2, "switching alt preserves economy basis")
    local oldCost, oldRecipes = host.ComputeCraftCost, host.RECIPES_BY_OUTPUT[2447]
    host.RECIPES_BY_OUTPUT[2447] = { reagents = {}, numMade = 1 }
    host.ComputeCraftCost = function() return 80 end
    local ok, err = pcall(function()
        local r = append("AH_SELL", 2447, 5, 1000, { gross = 1000, fee = 0 })
        check(r.cogs == 340 and r.extra.est, "known plus estimated missing basis cost")
        check(itemRow(2447).est == true, "performance marks estimate")
        check(#compute("items", { knownCostOnly = true }).rows == 0, "known-cost filter excludes estimate")
    end)
    host.ComputeCraftCost, host.RECIPES_BY_OUTPUT[2447] = oldCost, oldRecipes
    check(ok, tostring(err))
end)
test("T15 slowing boundary, minimum evidence and 7/14-day windows", function()
    for _, fixture in ipairs({ { 2447, 5, 3, false }, { 2448, 2, 1, false }, { 2449, 5, 2, true } }) do
        local id, previous, recent = fixture[1], fixture[2], fixture[3]
        append("AH_BUY", id, 100, -100, {}, mockNow - 13 * 86400)
        append("AH_SELL", id, previous, 500, { gross = 500, fee = 0 }, mockNow - 8 * 86400)
        append("AH_SELL", id, recent, 300, { gross = 300, fee = 0 }, mockNow - 86400)
        local r = itemRow(id)
        approxEq(r.slowRatio, recent / previous, 0.000001, "exact slowing ratio")
        check(r.isSlowing == fixture[4], "strict below 0.6 with at least 3 earlier sales")
        approxEq(r.velocity, recent / 7, 0.000001, "recent seven-day velocity")
        approxEq(r.prevVelocity, previous / 7, 0.000001, "previous seven-day velocity")
    end
    advanceTime(7 * 86400)
    check(itemRow(2449).velocity == 0, "time advancement rolls seven-day window")
    check(#compute("ledger", { period = "7d" }).rows == 0, "old sales leave current seven-day ledger")
end)
test("T16 500-row lossless packed day within 5ms", function()
    local day = Store.DayKey(); local tricky = "comma, semi; equal= pipe| percent% newline\nreturn\r%2C%25"
    for i = 1, 500 do
        Store.Append({ time = mockNow + i / 10000, char = "Synthetic-Char", econ = "Normal-Horde", type = "ADJUST",
            where = tricky .. i, itemID = 0, qty = i, unit = 0.125, total = -i, cogs = i / 4, ref = tricky,
            extra = { [tricky] = tricky, n = i / 8, yes = true, no = false, empty = "" } })
    end
    local before = rawRows(); check(#before == 500, "fixture has exactly 500 raw rows")
    collectgarbage("collect") -- Exclude fixture allocation debt, as in the overview benchmark.
    local elapsed, after = math.huge, nil
    for _ = 1, 5 do
        local copy = {}; for idx, rw in ipairs(before) do copy[idx] = rw end
        MerchantMasterLedgerDB.days[day] = { r = copy }
        collectgarbage("stop")
        local t0 = realOS.clock() * 1000
        local packed = Store.PackDay(day); after = Store.UnpackDayString(packed)
        local dt = realOS.clock() * 1000 - t0
        collectgarbage("restart")
        if dt < elapsed then elapsed = dt end
    end
    check(#after == #before, "pack row count")
    local function equal(a, b, path)
        check(type(a) == type(b), path .. " type")
        if type(a) == "table" then
            for k, v in pairs(a) do equal(v, b[k], path .. "." .. tostring(k)) end
            for k in pairs(b) do check(a[k] ~= nil, path .. " unexpected field " .. tostring(k)) end
        else check(a == b, path .. " value") end
    end
    for i = 1, #before do equal(before[i], after[i], "packed row " .. i) end
    print(string.format("MEASURE T16 pack+decode %.3f ms", elapsed)); check(elapsed <= 5 * ciScale, "500-row pack/decode exceeds 5ms: " .. elapsed)
end)
test("R3 packed day compatibility and mixed scalar columns", function()
    local legacy = "123,Char,Normal-Horde,ADJUST,Some%2Cwhere,0,1,0.125,-5,2.5,ref%25,x=n:1.25;no=b:false;yes=b:true;empty=s:;escaped=s:%252C%0A%7C"
    local old = Store.UnpackDayString(legacy)[1]
    check(old.time == 123 and old.where == "Some,where" and old.ref == "ref%", "legacy row fields decode")
    check(old.extra.x == 1.25 and old.extra.no == false and old.extra.yes == true, "legacy numeric and boolean metadata")
    check(old.extra.empty == "" and old.extra.escaped == "%2C\n|", "legacy escapes decode once")
    local day = Store.DayKey()
    check(#Store.UnpackDayString(Store.PackDay(day)) == 0, "missing day decodes empty")
    local a = Store.Append({ type = "ADJUST", ref = "", extra = { mixed = false, sparse = "a:\n,b", [7] = true, time = 1 } })
    local b = Store.Append({ type = "ADJUST", extra = { mixed = 0, [7] = false, time = "two" } })
    local c = Store.Append({ type = "ADJUST", cogs = 0, extra = { mixed = "", sparse = true } })
    local packed = Store.PackDay(day); local rows = Store.UnpackDayString(packed)
    check(Store.PackDay(day) == packed and #rows == 3, "packing is idempotent")
    check(rows[1].ref == "" and rows[2].ref == nil, "empty and absent references stay distinct")
    check(rows[1].extra.mixed == false and rows[2].extra.mixed == 0 and rows[3].extra.mixed == "", "mixed scalar types survive")
    check(rows[1].extra.sparse == "a:\n,b" and rows[2].extra.sparse == nil and rows[3].extra.sparse == true, "sparse metadata survives")
    check(rows[1].extra[7] == true and rows[2].extra[7] == false and rows[3].extra[7] == nil, "numeric metadata keys survive")
    check(rows[1].extra.time == 1 and rows[2].extra.time == "two", "metadata keys may also name row fields")
    check(rows[1].cogs == nil and rows[3].cogs == 0, "absent and zero cost stay distinct")
    Store.Append({ type = "ADJUST", total = 9 })
    check(#rawRows() == 4 and rawRows()[1].ref == "", "append reopens packed day losslessly")
    MerchantMasterLedgerDB.days[day] = { r = {} }
    check(#Store.UnpackDayString(Store.PackDay(day)) == 0, "empty stored day round trips")
end)
test("T17 legacy TSM importer removed while passive historical tsm rows load and display", function()
    check(Store.SeedTSM == nil and Store.ReconcileTSMSales == nil, "SeedTSM and ReconcileTSMSales removed")
    local char = current(); local old = math.floor(mockNow - 86400)
    Store.Append({ char = char, econ = "Normal-Horde", type = "AH_BUY", itemID = 2447, qty = 5, unit = 20, total = -100, time = old, where = "Auction House", extra = { tsm = 1, seller = "OldSeller" } })
    Store.Append({ char = char, econ = "Normal-Horde", type = "AH_SELL", itemID = 2447, qty = 2, unit = 100, total = 190, time = old + 60, where = "Auction House", extra = { tsm = 1, gross = 200, fee = 10, buyer = "OldBuyer" } })
    Store.Rebuild()
    local list = rawRows()
    check(#list == 2 and list[1].extra.tsm == 1 and list[2].extra.tsm == 1, "passive historical extra.tsm rows load cleanly")
    check(list[2].cogs == 40, "passive historical tsm sale computes FIFO COGS cleanly")
    local res = Model.Compute("ledger", { char = "all", type = "all", zone = "all", period = "all" })
    check(res and #(res.rows or {}) == 2, "Model computes ledger with passive extra.tsm rows")
end)
test("T18 five hook failures trip breaker and reset re-enables", function()
    local original = Store.Append
    Store.Append = function() error("synthetic capture error") end
    local ok, err = pcall(function()
        for _ = 1, 6 do buy(2447, 20, 50); advanceTime(0.1) end
    end)
    Store.Append = original
    check(ok, "capture errors do not escape host: " .. tostring(err))
    local disabled
    for kind, value in pairs(MerchantMasterLedgerDB.stats.disabled) do if value then disabled = kind end end
    check(disabled ~= nil and Store.IsDisabled(disabled), "five capture errors disable kind")
    check(MerchantMasterLedgerDB.stats.errors[disabled] == 5, "disabled hook stops recording errors")
    Store.ResetErrors(); check(not Store.IsDisabled(disabled), "reset re-enables capture")
    buy(2447, 20, 50); exactly("AH_BUY", 1)
end)
test("T19 secret event payload ignored without errors", function()
    local secret = setmetatable({}, { __tostring = function() error("secret string coercion") end })
    issecretvalue = function(v) return v == secret end
    local before = #rawRows()
    local ok = pcall(function() fire("COMMODITY_PRICE_UPDATED", secret, secret); fire("COMMODITY_PURCHASE_SUCCEEDED", secret, secret) end)
    check(ok and #rawRows() == before, "secret payload ignored safely")
    check(next(MerchantMasterLedgerDB.stats.errors) == nil, "secret payload does not trip breaker")
end)

test("T20a 365 days x 300 items overview within 30ms", function()
    local char, econ = current()
    for dayIndex = 0, 364 do
        local day, items = Store.DayKey(mockNow - dayIndex * 86400), {}
        for i = 1, 300 do
            local r = {}; for _, field in ipairs(Store.ROLL_FIELDS) do r[field] = 0 end
            r.sold, r.gross, r.fee, r.cogs, r.posted = 1, 100, 5, 40, 2
            items[10000 + i] = r
        end
        MerchantMasterLedgerDB.roll[day] = { [econ] = items }
        MerchantMasterLedgerDB.dayStats[day] = { [char] = { profitDelta = 16500, salesGross = 30000, adjustTotal = 0 } }
    end
    local elapsed, result = math.huge, nil
    for _ = 1, 5 do
        Model.Invalidate(); collectgarbage("collect"); collectgarbage("stop")
        local t0 = realOS.clock() * 1000
        result = Model.Compute("overview", { char = "all", type = "all", zone = "all", period = "all", knownCostOnly = false })
        local dt = realOS.clock() * 1000 - t0
        collectgarbage("restart")
        if dt < elapsed then elapsed = dt end
    end
    check(result.kpis.profit == 365 * 300 * 55, "entire rollup contributes to profit")
    check(#result.profitByDay == 365, "all days charted")
    print(string.format("MEASURE T20 overview %.3f ms", elapsed)); check(elapsed <= 30 * ciScale, "overview exceeds 30ms: " .. elapsed)
end)
test("T20b all views, width budgets, sub-tabs and actual averages", function()
    append("AH_BUY", 2447, 20, -1000); append("AH_POST", 2447, 20, -60)
    append("AH_SELL", 2447, 4, 400, { gross = 420, fee = 20 })
    local char, econ = current()
    MerchantMasterLedgerDB.dayStats[Store.DayKey()] = { [char] = {
        writCost = 1000, writQuestCash = 100, pouchCash = 100, writRep = 100, writsDone = 1,
        crateCost = 2000, crateCash = 1000, favorGained = 10, cratesDone = 1,
        tiers = { Journeyman = { cost = 1000, cash = 100, refund = 100, rep = 100, writs = 1 } },
    } }
    Store.SaveSnapshot(char, Store.DayKey(), { gold = mockMoney, items = 1234, listed = 5678, econ = econ })
    Model.Invalidate()
    local tabs = { "an_overview", "an_ledger", "an_items", "an_portfolio", "an_invest", "an_writs" }
    host.app.panel:Show()
    for _, tab in ipairs(tabs) do
        MerchantMasterAPI.SetTab(tab); host.app.refresh()
        check(host.app.analyticsProvider ~= nil, tab .. " refresh did not break provider")
        check(UI.views[tab] and UI.views[tab]:IsShown(), tab .. " visible")
        check(#UI.GetSidebarControls(tab) <= 6, tab .. " sidebar fits")
        for key, view in pairs(UI.views) do if key ~= tab then check(not view:IsShown(), "inactive view hidden") end end
    end
    local count = 0
    for key, tbl in pairs(UI.tables) do
        local width = 4 + (#tbl.columns - 1) * 5
        for _, col in ipairs(tbl.columns) do width = width + col.width end
        check(width <= 1048, key .. " header width " .. width); count = count + 1
    end
    check(count == 8, "all eight analytics tables built (including expandable an_wealth)")
    local total = 0
    for _, button in pairs(host.app.ui.analyticsSubBar.buttons) do total = total + button:GetWidth() end
    check(total <= 528 and host.app.ui.analyticsSubBar:GetWidth() <= 528, "Analytics sub-tab layout fits 528px")
    local econ = host.CurrentEconomyInfo and host.CurrentEconomyInfo().effectiveKey or "Normal-Horde"
    MerchantMasterDB.ahPrices = MerchantMasterDB.ahPrices or {}
    MerchantMasterDB.ahPrices[econ] = MerchantMasterDB.ahPrices[econ] or { _scannedAt = time() }
    for id in pairs(host.ALL_CATALOG_IDS) do
        MerchantMasterDB.ahPrices[econ][id] = { price = 1000, qty = 100000, at = time() }
    end
    MerchantMasterDB.calcDeductFavor, MerchantMasterDB.calcUseOwned, MerchantMasterDB.calcRespectStock = false, false, false
    MerchantMasterDB.calcFavorTarget, MerchantMasterDB.calcRepTarget = 25, 6
    host.app.uiPriceBank = nil
    if host.InvalidatePriceCache then host.InvalidatePriceCache() end
    MerchantMasterAPI.SetTab("calc_favor"); host.app.refresh()
    check(host.app.ui.favorSummaryFs:GetText():find("My Avg:", 1, true) ~= nil, "Favor calculator displays read-only actual average")
    MerchantMasterAPI.SetTab("calc_rep"); host.app.refresh()
    check(host.app.ui.repSummaryFs:GetText():find("My Avg:", 1, true) ~= nil, "Rep calculator displays read-only actual average")
end)
test("T20c strict font allowlist and no repeating render work", function()
    local allowedUTF8 = { [string.char(194, 183)] = true, [string.char(226, 128, 148)] = true,
        [string.char(226, 128, 147)] = true, [string.char(226, 128, 166)] = true, [string.char(195, 151)] = true }
    local BAD_GLYPHS = 0
    for _, name in ipairs({ "Store.lua", "Model.lua", "Capture.lua", "Chart.lua", "UI.lua" }) do
        local file = assert(io.open(analyticsDir .. name, "rb")); local source = file:read("*a"); file:close()
        local i = 1
        while i <= #source do
            local b = source:byte(i)
            if b < 128 then i = i + 1
            else
                local len = b >= 240 and 4 or (b >= 224 and 3 or 2)
                if not allowedUTF8[source:sub(i, i + len - 1)] then BAD_GLYPHS = BAD_GLYPHS + 1 end
                i = i + len
            end
        end
        check(not source:match('SetScript%s*%(%s*["\']On' .. 'Update["\']'), name .. " uses no render-loop refresh")
        check(not source:find("C_Timer." .. "NewTicker", 1, true), name .. " uses no repeating ticker")
    end
    print("BAD_GLYPHS=" .. BAD_GLYPHS); check(BAD_GLYPHS == 0, "all companion files use only supported font glyphs")
end)

test("R2 charts handle empty, singleton, spikes, signs, pooling and fallback", function()
    local chart = Chart.CreateLineChart(UIParent, 528, 195, { title = "Test line", formatY = tostring })
    chart:SetData({}); check(chart._pointCount == 0 and chart.empty:IsShown(), "empty line state")
    chart:SetData({ { name = "One", points = { { day = "2026-01-01", value = 0 } } } })
    check(chart._pointCount == 1 and not chart.empty:IsShown(), "singleton line state")
    local points = {}
    for i = 1, 365 do points[i] = { day = string.format("D%03d", i), label = tostring(i), value = i % 9 - 4 } end
    points[123].value, points[124].value = 100000, -100000
    local input = { { name = "Total", points = points }, { name = "Gold", points = points, color = { 0, 1, 0, 1 } } }
    chart:SetData(input)
    check(chart._pointCount <= 60, "line rendering capped at 60 points per series")
    local sampled = chart._lastSeries[1].points
    check(sampled[1] == points[1] and sampled[#sampled] == points[#points], "sample retains endpoints")
    local high, low = false, false
    for _, p in ipairs(sampled) do high = high or p.value == 100000; low = low or p.value == -100000 end
    check(high and low, "sample retains bucket extrema")
    local lineCount, hitCount = #chart._lines, #chart._hits
    for _ = 1, 4 do chart:SetData(input) end
    check(#chart._lines == lineCount and #chart._hits == hitCount, "line and hover objects reused")
    local hit = chart._hits[1]; hit:GetScript("OnEnter")(hit)
    check(GameTooltip:NumLines() == 3, "tooltip has date and both exact series values")
    hit:GetScript("OnLeave")(hit); check(not GameTooltip:IsShown(), "hover leave hides tooltip")
    chart:Clear(); check(chart._pointCount == 0 and chart.empty:IsShown(), "line clear resets state")
    for _, line in ipairs(chart._lines) do check(not line:IsShown(), "unused line hidden") end
    chart.plot.CreateLine = nil
    chart:SetData({ { name = "Fallback", points = points } })
    check(#chart._dots > 0 and #chart._dots <= 60, "minimal mock falls back to pooled dots")
    chart:SetTitle("Renamed"); check(chart.title:GetText() == "Renamed", "line title updates")
    local bars = Chart.CreateBarChart(UIParent, 528, 195, { title = "Test bars", formatY = tostring })
    bars:SetData({ { day = "A", value = -10 }, { day = "B", value = 0 }, { day = "C", value = 10 } })
    check(bars._barCount == 3 and bars._bars[2]:GetHeight() == 1, "zero bar is one-pixel tick")
    check(bars._bars[1]:GetHeight() > 0 and bars._bars[3]:GetHeight() > 0, "both bar signs render")
    check(bars._bars[1]._color[1] == 0.88 and bars._bars[3]._color[2] == 0.80, "negative coral and positive emerald colors")
    bars:SetData(points); check(bars._barCount <= 45, "bars capped at 45 buckets")
    local total, expected = 0, 0
    for _, b in ipairs(bars._lastBars) do total = total + b.value end
    for _, p in ipairs(points) do expected = expected + p.value end
    check(total == expected, "bar buckets preserve total profit")
    local pool = #bars._bars; bars:SetData(points); check(#bars._bars == pool, "bar textures pooled")
    bars:Clear(); check(bars._barCount == 0 and bars.empty:IsShown(), "bar clear resets state")
    for _, bar in ipairs(bars._bars) do check(not bar:IsShown(), "cleared bar hidden") end
end)
test("R2 sidebar modes, resets, conditional import and table sorting", function()
    append("AH_BUY", 2447, 10, -100); append("AH_SELL", 2447, 2, 100, { gross = 100, fee = 0 })
    append("AH_BUY", 2448, 10, -100); append("AH_SELL", 2448, 3, 500, { gross = 500, fee = 0 })
    local savedDropdown, options, pick = host.Theme.OpenDropDown
    host.Theme.OpenDropDown = function(_, list, _, callback) options, pick = list, callback end
    local ok, err = pcall(function()
        UI.itemModeBtn:Click()
        for _, option in ipairs(options) do
            pick(option.key)
            check(MerchantMasterDB.anItemMode == option.key, "item mode persists")
            check(host.app.sortState.an_items.col == option.col and host.app.sortState.an_items.asc == (option.asc == true), "item mode updates sort state")
        end
        UI.charBtn:Click("RightButton"); UI.periodBtn:Click("RightButton"); UI.typeBtn:Click("RightButton"); UI.zoneBtn:Click("RightButton")
        check(MerchantMasterDB.anChar == "all" and MerchantMasterDB.anPeriod == "30d" and MerchantMasterDB.anType == "all" and MerchantMasterDB.anZone == "all", "right-click defaults")
        UI.knownCostCheck:SetChecked(true); UI.knownCostCheck:Click()
        check(MerchantMasterDB.anKnownCostOnly == true, "known-cost switch persists checked state")
        UI.knownCostCheck:SetChecked(false); UI.knownCostCheck:Click()
        check(MerchantMasterDB.anKnownCostOnly == false, "known-cost switch persists unchecked state")
        MerchantMasterDB.anItemMode = "profit"
        host.app.sortState.an_items = { col = "profit", asc = false }
        host.app.panel:Show(); MerchantMasterAPI.SetTab("an_items"); host.app.refresh()
        local tbl = UI.tables.an_items
        tbl.headerBtns[2]:Click(); local first = tbl.scrollBox._dp:GetCollection()[1]
        check(first and first.itemID == 2447, "clickable profit header sorts ascending")
        tbl.headerBtns[2]:Click(); first = tbl.scrollBox._dp:GetCollection()[1]
        check(first.itemID == 2448, "clickable profit header sorts descending")
        check(UI.seedTsmBtn == nil, "Legacy TSM import button removed from Analytics UI")
        _G.TradeSkillMasterDB = {}; MerchantMasterLedgerDB.seed.tsm = nil
        check(#UI.GetSidebarControls("an_ledger") == 5, "Standalone an_ledger sidebar always has 5 controls")
        _G.TradeSkillMasterDB = nil
    end)
    host.Theme.OpenDropDown = savedDropdown
    check(ok, tostring(err))
end)
test("R2 trailing debounce refreshes only visible analytics", function()
    local original, calls = host.app.refresh, 0
    host.app.refresh = function() calls = calls + 1 end
    local ok, err = pcall(function()
        timers = {}; host.app.panel:Show(); host.app.activeTab = "an_ledger"; calls = 0
        Store.onChange(); advanceTime(0.3); Store.onChange(); advanceTime(0.3)
        check(calls == 0, "new change postpones trailing refresh")
        advanceTime(0.2); check(calls == 1, "one trailing refresh at 0.5 seconds after last change")
        Store.onChange(); host.app.activeTab = "calc_rep"; advanceTime(1)
        check(calls == 1, "non-analytics tabs do not refresh")
        host.app.activeTab = "an_items"; Store.onChange(); host.app.panel:Hide(); advanceTime(1)
        check(calls == 1, "hidden panel does not refresh")
        host.app.panel:Show(); check(calls == 2, "host refreshes once when panel opens")
        advanceTime(1); check(calls == 2, "show alone does not repeat old timer")
    end)
    host.app.refresh = original; check(ok, tostring(err))
end)
test("R2 paused capture banner, reset click and ledger size warning", function()
    host.app.panel:Show(); MerchantMasterAPI.SetTab("an_ledger")
    for _ = 1, 5 do Store.RecordError("AH_BUY", "synthetic breaker") end
    host.app.refresh()
    check(UI.banner:IsShown() and UI.banner.label:GetText():find("Capture paused:", 1, true), "breaker warning shown")
    check(UI.banner:GetHeight() == 22, "warning height is 22 pixels")
    UI.banner:Click(); check(not Store.IsDisabled("AH_BUY"), "banner resets disabled capture")
    local original = Store.EstimateBytes; Store.EstimateBytes = function() return 3 * 1024 * 1024 end
    local ok, err = pcall(function()
        host.app.refresh(); check(UI.banner:IsShown() and UI.banner.label:GetText() == "Ledger size > 3 MB", "size threshold notice")
    end)
    Store.EstimateBytes = original; check(ok, tostring(err))
end)
test("R2 slash commands route and expose probe status safely", function()
    local api = MerchantMasterAPI
    local toggle, snapshot, resetFn, printer = api.TogglePanel, Capture.QueueWealthSnapshot, Store.ResetErrors, print
    local tab, snapshots, resets, messages = nil, 0, 0, {}
    api.TogglePanel = function(value) tab = value end
    Capture.QueueWealthSnapshot = function() snapshots = snapshots + 1 end
    Store.ResetErrors = function() resets = resets + 1 end
    _G.print = function(value) messages[#messages + 1] = tostring(value) end
    local ok, err = pcall(function()
        SlashCmdList.MERCHANTMASTERANALYTICS(""); check(tab == "analytics", "mma opens analytics")
        SlashCmdList.MERCHANTMASTERANALYTICS("ledger"); check(tab == "an_ledger", "mma ledger opens ledger")
        SlashCmdList.MERCHANTMASTERANALYTICS("probe"); check(MerchantMasterLedgerDB.probe.enabled == true, "probe enabled")
        SlashCmdList.MERCHANTMASTERANALYTICS("probe"); check(MerchantMasterLedgerDB.probe.enabled == false, "probe disabled")
        SlashCmdList.MERCHANTMASTERANALYTICS("snapshot"); check(snapshots == 1, "manual wealth snapshot")
        SlashCmdList.MERCHANTMASTERANALYTICS("reseterrors"); check(resets == 1, "manual breaker reset")
        SlashCmdList.MERCHANTMASTERANALYTICS("status"); check(#messages >= 3 and messages[#messages]:find("writ / rep", 1, true), "status includes actual averages")
    end)
    api.TogglePanel, Capture.QueueWealthSnapshot, Store.ResetErrors, _G.print = toggle, snapshot, resetFn, printer
    check(ok, tostring(err))
end)

test("R2 30-second post timeout and 5-second craft expiry", function()
    bag[2447] = 20
    local loc = ItemLocation:CreateFromBagAndSlot(0, 1)
    C_AuctionHouse.PostCommodity(loc, 1, 20, 50)
    advanceTime(29); exactly("AH_POST", 0)
    -- Anti-phantom-lot contract: unconfirmed PostCommodity without ConfirmPostCommodity/AUCTION_HOUSE_AUCTION_CREATED discards on 30s timeout
    advanceTime(2); exactly("AH_POST", 0)
    -- Confirmed post (ConfirmPostCommodity + AUCTION_HOUSE_AUCTION_CREATED) logs exactly 1 AH_POST
    C_AuctionHouse.PostCommodity(loc, 1, 20, 50)
    C_AuctionHouse.ConfirmPostCommodity(loc, 1, 20, 50)
    fire("AUCTION_HOUSE_AUCTION_CREATED", 1); exactly("AH_POST", 1)
    local rec = host.RECIPES[1]; local id = rec.outputItemID or rec.itemID
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Expired", rec.spellID)
    advanceTime(6); bag[id] = rec.numMade or 1; fire("BAG_UPDATE_DELAYED")
    exactly("CRAFT", 0)
end)
test("R2 no loot or craft without a bag rise and retrieving mail ignored", function()
    lootSlots = { { id = 2447, qty = 2 } }; fire("LOOT_OPENED"); fire("BAG_UPDATE_DELAYED"); fire("LOOT_CLOSED"); advanceTime(2)
    local char, econ = current()
    check(not (MerchantMasterLedgerDB.loot[Store.DayKey()] or {})[char], "no bag rise produces no loot")
    check(Store.Basis(econ, 2447) == 0, "no phantom loot basis")
    local rec = host.RECIPES[1]
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-No-Output", rec.spellID); fire("BAG_UPDATE_DELAYED"); advanceTime(6)
    exactly("CRAFT", 0)
    _G.RETRIEVING_DATA = "Retrieving data"
    mail = { { id = 2447, qty = 1, subject = RETRIEVING_DATA, money = 100 } }
    fire("MAIL_SHOW"); TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1); exactly("AH_SELL", 0)
end)
test("R2 ADJUST reconciles unexplained money once", function()
    local char = current()
    append("AH_BUY", 2447, 5, -500)
    local row = Store.ReconcileGold(char, mockMoney - 525, "Test Reconciliation")
    check(row and row.type == "ADJUST" and row.total == -25, "reconciliation subtracts explained cash")
    Store.ReconcileGold(char, mockMoney - 525, "Test Reconciliation"); exactly("ADJUST", 1)
    check(compute("overview").kpis.unexplained == -25, "overview exposes unexplained money")
end)
test("R2 reputation push closes on standing boundary", function()
    local w = host.WRITS[1]
    local first = mockNow - 100
    Store.Append({ type = "WRIT_TURNIN", itemID = w.itemID, qty = 1, total = 100, cogs = 1000,
        time = first, extra = { rep = w.rep } })
    append("STANDING", 0, 0, 0, { from = 5, to = 6, name = "Honored" }, first + 10)
    Store.Append({ type = "WRIT_TURNIN", itemID = w.itemID, qty = 1, total = 50, cogs = 500,
        time = first + 20, extra = { rep = w.rep } })
    local pushes = compute("invest").pushes
    check(#pushes == 2, "completed and active reputation pushes separated")
    local closed, active
    for _, p in ipairs(pushes) do
        if p.active == false or p.endedAt or p.endTime then closed = p else active = p end
    end
    check(closed and active and closed.writsDone == 1 and active.writsDone == 1, "writs assigned to correct push")
    check(closed.netCost == 900 and active.netCost == 450, "push net costs frozen independently")
end)
test("R2 snapshot maps inventory names, listed lots and carries alts forward", function()
    local char, econ = current()
    host.app.char.bags, host.app.char.bank, host.app.char.mail = { ["Synthetic Herb"] = 2 }, { ["Synthetic Herb"] = 3 }, { ["Unknown inventory"] = 9 }
    MerchantMasterDB.itemIDs["Synthetic Herb"] = 2447
    Store.Append({ type = "AH_POST", itemID = 2447, qty = 2, unit = 200, total = -60 })
    local oldMarket, oldVendor = host.GetItemMarketPrice, host.GetVendorSellPrice
    host.GetItemMarketPrice, host.GetVendorSellPrice = function() return 100 end, function() return 1 end
    local ok, err = pcall(function()
        Capture.QueueWealthSnapshot(); advanceTime(2)
        local snap = MerchantMasterLedgerDB.snaps[char][Store.DayKey()]
        check(snap.gold == mockMoney and snap.items == 500 and snap.listed == 400, "snapshot maps known names and skips unknown inventory")
        check(snap.econ == econ, "snapshot retains valuation economy")
        local yesterday = Store.DayKey(mockNow - 86400)
        Store.SaveSnapshot("Normal-Horde-Forever-AnalyticsB", yesterday, { gold = 1000, items = 100, listed = 0, econ = econ })
        local portfolio = compute("portfolio")
        check(portfolio.latestTotal == mockMoney + 500 + 400 + 1100, "unchanged alt wealth carried forward")
        check(#portfolio.byChar == 2, "wealth breakdown includes both characters")
    end)
    host.GetItemMarketPrice, host.GetVendorSellPrice = oldMarket, oldVendor
    check(ok, tostring(err))
end)
test("R2 zero-sale ratios and 500-row ledger window", function()
    append("AH_POST", 2447, 5, -60)
    local r = itemRow(2447)
    check(r.daysToSell == nil and r.sellThrough == nil and r.slowRatio == nil, "undefined ratios stay nil without sales")
    check(r.velocity == 0 and not r.isSlowing, "zero sales are not slowing evidence")
    for i = 1, 510 do append("ADJUST", 0, 0, i, {}, mockNow - i) end
    local rows = compute("ledger").rows
    check(#rows == 500, "ledger returns at most 500 newest rows")
    check(rows[1].time >= rows[#rows].time, "ledger window is newest first")
    local filtered = compute("ledger", { type = "buys" }).rows; check(#filtered == 0, "type filtering does not leak unrelated rows")
end)
test("R2 host placeholder survives provider absence", function()
    local provider = host.app.analyticsProvider; host.app.analyticsProvider = nil
    local ok, err = pcall(function()
        host.app.panel:Show(); MerchantMasterAPI.SetTab("an_overview"); host.app.refresh()
        local empty = host.app.ui.analyticsView.emptyFs
        check(empty:IsShown() and empty:GetText():find("Analytics is unavailable", 1, true), "host shows integrated Analytics load-error prompt")
    end)
    host.app.analyticsProvider = provider; check(ok, tostring(err))
end)
test("R2 future schema is read-only and unsupported auction API is safe", function()
    local saved = MerchantMasterLedgerDB
    _G.MerchantMasterLedgerDB = { schema = 99, marker = "preserve" }; Store.Init()
    local result = Store.Append({ type = "AH_BUY", itemID = 2447, qty = 1, total = -50 })
    check(result == nil and MerchantMasterLedgerDB.marker == "preserve" and MerchantMasterLedgerDB.days == nil, "future schema is not rewritten")
    _G.MerchantMasterLedgerDB = saved; Store.Init()
    local auction = C_AuctionHouse; _G.C_AuctionHouse = nil
    local ok, err = pcall(Capture.InstallHooks); _G.C_AuctionHouse = auction
    check(ok, "legacy client without auction API: " .. tostring(err))
end)

test("R4 two identical sale invoices in inbox both record while same-slot hooks dedupe", function()
    buy(2447, 40, 20); post(2447, 20, 50); post(2447, 20, 50)
    mail = {
        { id = 2447, qty = 20, gross = 1000, deposit = 60, fee = 50, money = 1010, name = "Item 2447" },
        { id = 2447, qty = 20, gross = 1000, deposit = 60, fee = 50, money = 1010, name = "Item 2447" },
    }
    fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
    -- Loot first mail: repeated hooks on slot 1 (even across MAIL_INBOX_UPDATE and >10s delay before inbox shrinks) must only record once
    TakeInboxMoney(1); AutoLootMailItem(1); fire("CLOSE_INBOX_ITEM", 1)
    fire("MAIL_INBOX_UPDATE"); advanceTime(15); DeleteInboxItem(1); fire("CLOSE_INBOX_ITEM", 1)
    exactly("AH_SELL", 1)
    -- Empty shell case: money becomes 0 on slot 1 while second mail still has money=1010, then relog!
    mail[1].money = 0
    fire("MAIL_CLOSED"); reloadCapture(true); fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
    DeleteInboxItem(1); fire("CLOSE_INBOX_ITEM", 1)
    exactly("AH_SELL", 1)
    -- Now remove empty shell 1; slot 1 becomes the second uncollected identical mail (money=1010) -> must record #2!
    table.remove(mail, 1); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1); advanceTime(1)
    local sales = rawRows("AH_SELL")
    check(#sales == 2, "both identical sale mails recorded without shell double-count: got " .. #sales)
    -- Also test rapid looting of slots 1 and 2 BEFORE MAIL_INBOX_UPDATE fires (first remove the looted mail #2)!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2447, qty = 20, gross = 1000, deposit = 60, fee = 50, money = 1010, name = "Item 2447" },
        { id = 2447, qty = 20, gross = 1000, deposit = 60, fee = 50, money = 1010, name = "Item 2447" },
    }
    fire("MAIL_INBOX_UPDATE")
    AutoLootMailItem(1); AutoLootMailItem(2)
    sales = rawRows("AH_SELL")
    check(#sales == 4, "rapid batch AutoLootMailItem(1) + AutoLootMailItem(2) before MAIL_INBOX_UPDATE records both: got " .. #sales)
    -- Also test removing first identical mail while an unrelated new mail arrives (keeping total inbox count == 2)!
    mail = {
        { id = 2447, qty = 20, gross = 1000, deposit = 60, fee = 50, money = 1010, name = "Item 2447" },
        { id = 2448, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2448" },
    }
    -- Wait: simulate fresh pair first:
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2449, qty = 10, gross = 800, deposit = 30, fee = 40, money = 790, name = "Item 2449" },
        { id = 2449, qty = 10, gross = 800, deposit = 30, fee = 40, money = 790, name = "Item 2449" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 5, "first 2449 sale recorded")
    -- Remove first 2449 AND add unrelated 2448 at end so inbox count stays 2!
    table.remove(mail, 1)
    mail[#mail + 1] = { id = 2448, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2448" }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 6, "second 2449 sale recorded even when unrelated arrival kept inbox count == 2")
    -- Also test partial settlement: collect BOTH identical mails (1 and 2), settle ONLY mail 1, then repeat hook on remaining slot 1 -> NO duplicate!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2450, qty = 5, gross = 600, deposit = 20, fee = 30, money = 590, name = "Item 2450" },
        { id = 2450, qty = 5, gross = 600, deposit = 20, fee = 30, money = 590, name = "Item 2450" },
    }
    fire("MAIL_INBOX_UPDATE")
    AutoLootMailItem(1); AutoLootMailItem(2)
    check(#rawRows("AH_SELL") == 8, "both 2450 mails recorded on rapid batch loot")
    table.remove(mail, 1); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 8, "partial settlement of first 2450 mail preserves second mail consumed identity without duplicating")
    -- Also test reverse order: collect slot 2 FIRST, refresh unchanged inbox before money disappears -> slot 2 stays consumed (no dup) AND slot 1 still records!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2451, qty = 5, gross = 700, deposit = 20, fee = 35, money = 685, name = "Item 2451" },
        { id = 2451, qty = 5, gross = 700, deposit = 20, fee = 35, money = 685, name = "Item 2451" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(2); fire("CLOSE_INBOX_ITEM", 2)
    check(#rawRows("AH_SELL") == 9, "collecting slot 2 first records one 2451 sale")
    fire("MAIL_INBOX_UPDATE") -- unchanged refresh before slot 2 money disappears!
    TakeInboxMoney(2); fire("CLOSE_INBOX_ITEM", 2)
    check(#rawRows("AH_SELL") == 9, "repeating slot 2 after unchanged refresh does NOT duplicate")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 10, "collecting slot 1 after slot 2 + unchanged refresh records the remaining 2451 sale")
    -- Also test 3 identical mails: collect slots 1 and 3, then settle slot 3 ONLY -> repeating slot 1 does NOT duplicate AND slot 2 still records!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2452, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, days = 29.9, name = "Item 2452" },
        { id = 2452, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, days = 29.8, name = "Item 2452" },
        { id = 2452, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, days = 29.7, name = "Item 2452" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); TakeInboxMoney(3)
    check(#rawRows("AH_SELL") == 12, "collecting slots 1 and 3 of 2452 records 2 sales")
    table.remove(mail, 3); fire("MAIL_INBOX_UPDATE") -- settle slot 3 ONLY!
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 12, "repeating slot 1 after slot 3 settled does NOT duplicate")
    TakeInboxMoney(2); fire("CLOSE_INBOX_ITEM", 2)
    check(#rawRows("AH_SELL") == 13, "collecting slot 2 after slot 3 settled records the 3rd 2452 sale")
    -- Also test 3 identical mails: collect slots 1 and 3, then remove slot 1 -> untouched slot 2 shifts to slot 1 and MUST record, while old slot 3 (now slot 2) stays consumed!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2453, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2453" },
        { id = 2453, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2453" },
        { id = 2453, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2453" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); TakeInboxMoney(3)
    check(#rawRows("AH_SELL") == 15, "collecting slots 1 and 3 of 2453 records 2 sales")
    table.remove(mail, 1); fire("MAIL_INBOX_UPDATE") -- remove slot 1 (FIFO settlement)!
    TakeInboxMoney(2); fire("CLOSE_INBOX_ITEM", 2) -- old slot 3 is now slot 2 -> must NOT duplicate!
    check(#rawRows("AH_SELL") == 15, "repeating shifted slot 2 (was slot 3) does NOT duplicate")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1) -- old untouched slot 2 is now slot 1 -> MUST record!
    check(#rawRows("AH_SELL") == 16, "collecting shifted untouched slot 1 (was slot 2) records the 3rd 2453 sale")
    -- Also test repeated MAIL_INBOX_UPDATE + MAIL_CLOSED + MAIL_SHOW after partial removal does NOT retire remaining pending entry!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2454, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2454" },
        { id = 2454, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2454" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); TakeInboxMoney(2)
    check(#rawRows("AH_SELL") == 18, "collecting both 2454 mails records 2 sales")
    table.remove(mail, 1)
    fire("MAIL_INBOX_UPDATE"); fire("MAIL_INBOX_UPDATE"); fire("MAIL_INBOX_UPDATE")
    fire("MAIL_CLOSED"); fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 18, "reopening mailbox after repeated inbox updates does NOT re-record unremoved 2nd mail")
    -- Also test: loot an invoice leaving its empty shell (money=0) while a brand-new identical invoice arrives (money=555) -> new invoice MUST record (both live and after relog)!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2455, qty = 5, gross = 600, deposit = 10, fee = 30, money = 580, name = "Item 2455" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1)
    check(#rawRows("AH_SELL") == 19, "first 2455 sale recorded")
    -- Slot 1 turns into empty shell (money=0) AND a new identical 2455 arrives at slot 2!
    mail[1].money = 0
    mail[2] = { id = 2455, qty = 5, gross = 600, deposit = 10, fee = 30, money = 580, name = "Item 2455" }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(2)
    check(#rawRows("AH_SELL") == 20, "new identical 2455 invoice arriving alongside empty shell records properly")
    -- Also test: two identical invoices present, collect slot 1, then MAIL_CLOSED + MAIL_SHOW BEFORE slot 1 money disappears -> repeating slot 1 does NOT duplicate!
    mail = {}
    fire("MAIL_INBOX_UPDATE")
    mail = {
        { id = 2456, qty = 5, gross = 600, deposit = 10, fee = 30, money = 580, name = "Item 2456" },
        { id = 2456, qty = 5, gross = 600, deposit = 10, fee = 30, money = 580, name = "Item 2456" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1)
    check(#rawRows("AH_SELL") == 21, "first 2456 sale recorded")
    fire("MAIL_CLOSED"); fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 21, "closing/reopening mailbox before money disappears preserves slot 1 consumed identity")
    TakeInboxMoney(2)
    check(#rawRows("AH_SELL") == 22, "slot 2 of 2456 still records after close/reopen")
    -- Also test temporarily unreadable mail (`RETRIEVING_DATA`): preserves consumed state and does NOT retire seenMail!
    _G.RETRIEVING_DATA = "Retrieving data"
    mail = { { id = 2457, qty = 5, gross = 600, deposit = 10, fee = 30, money = 580, name = "Item 2457" } }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1)
    check(#rawRows("AH_SELL") == 23, "2457 sale recorded once")
    mail[1].subject = RETRIEVING_DATA
    fire("MAIL_INBOX_UPDATE")
    mail[1].subject = "Auction successful"
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 23, "temporarily unreadable mail does NOT duplicate on restore")
    -- Also test > 50 identical invoices (55 identical sales + relog): NO 50-occurrence cap!
    mail = {}; fire("MAIL_INBOX_UPDATE")
    for k = 1, 55 do
        mail = { { id = 2458, qty = 1, gross = 200, deposit = 10, fee = 10, money = 200, name = "Item 2458" } }
        fire("MAIL_INBOX_UPDATE")
        TakeInboxMoney(1)
        if k < 55 then mail = {}; fire("MAIL_INBOX_UPDATE") end
    end
    check(#rawRows("AH_SELL") == 23 + 55, "all 55 identical sales recorded: got " .. (#rawRows("AH_SELL") - 23))
    reloadCapture(true); fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == 23 + 55, "55th identical sale stays deduplicated after relog without 50-cap")
    -- Astra probe 1: fully loot/remove identical pair, then repeat with a second identical pair where one settles first -> remaining mail MUST record!
    local baseCount = #rawRows("AH_SELL")
    mail = {
        { id = 2459, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2459" },
        { id = 2459, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2459" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); TakeInboxMoney(2)
    mail = {}; fire("MAIL_INBOX_UPDATE") -- both fully removed (`gone = true` x 2)
    check(#rawRows("AH_SELL") == baseCount + 2, "first pair of 2459 recorded 2 sales")
    mail = {
        { id = 2459, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2459" },
        { id = 2459, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2459" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1)
    check(#rawRows("AH_SELL") == baseCount + 3, "first mail of second 2459 pair recorded")
    table.remove(mail, 1); fire("MAIL_INBOX_UPDATE") -- slot 1 settles, untouched slot 2 shifts to slot 1!
    TakeInboxMoney(1)
    check(#rawRows("AH_SELL") == baseCount + 4, "second mail of second 2459 pair recorded despite historical gone entries")
    -- Astra probe 2: with two identical invoices + unrelated slot 3, loot slot 1, make slot 3 unreadable (`RETRIEVING_DATA`), refresh, repeat hook on slot 1 -> NO duplicate, and slot 2 still records!
    mail = {
        { id = 2460, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2460" },
        { id = 2460, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2460" },
        { id = 2461, qty = 1, gross = 100, deposit = 5, fee = 5, money = 100, name = "Item 2461" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1)
    check(#rawRows("AH_SELL") == baseCount + 5, "first 2460 recorded")
    mail[3].subject = RETRIEVING_DATA
    fire("MAIL_INBOX_UPDATE") -- unrelated slot 3 temporarily unreadable!
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == baseCount + 5, "repeating slot 1 while unrelated slot 3 is unreadable does NOT duplicate")
    mail[3].subject = "Auction successful"
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == baseCount + 5, "repeating slot 1 after slot 3 restores still does NOT duplicate")
    TakeInboxMoney(2)
    check(#rawRows("AH_SELL") == baseCount + 6, "slot 2 of 2460 records cleanly")
    -- Also test rapid batch looting of second pair (TakeInboxMoney(1) + TakeInboxMoney(2) before update) followed by partial settlement (`raw = 2 -> 1`)!
    mail = {
        { id = 2459, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2459" },
        { id = 2459, qty = 5, gross = 500, deposit = 20, fee = 25, money = 495, name = "Item 2459" },
    }
    fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); TakeInboxMoney(2)
    check(#rawRows("AH_SELL") == baseCount + 8, "third pair of 2459 rapid batch looted")
    table.remove(mail, 1); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == baseCount + 8, "remaining unremoved slot of third pair stays deduplicated")
    reloadCapture(true); fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
    TakeInboxMoney(1); fire("CLOSE_INBOX_ITEM", 1)
    check(#rawRows("AH_SELL") == baseCount + 8, "remaining unremoved slot of third pair stays deduplicated across relog")
end)

test("R4 historical tsm-flagged rows do not close live open lots or pollute return pool", function()
    local char, econ = current()
    post(2447, 20, 100); advanceTime(1)
    check(#Store.Lots(char, 2447) == 1 and Store.Lots(char, 2447)[1].qty == 20, "live open lot present before historical replay")
    local cutoff = MerchantMasterLedgerDB.stats.firstLive[char]
    Store.Append({ char = char, econ = econ, type = "AH_BUY", itemID = 2447, qty = 20, unit = 15, total = -300, time = cutoff - 86400, where = "Auction House", extra = { tsm = 1 } })
    Store.Append({ char = char, econ = econ, type = "AH_SELL", itemID = 2447, qty = 10, unit = 80, total = 760, time = cutoff - 43200, where = "Auction House", extra = { tsm = 1, gross = 800, fee = 40 } })
    Store.Rebuild()
    local lots = Store.Lots(char, 2447)
    check(#lots == 1 and lots[1].qty == 20 and lots[1].deposit == 60, "live open lot untouched by historical tsm-flagged rows")
    local retPool = MerchantMasterLedgerDB.ret[char] and MerchantMasterLedgerDB.ret[char][2447] or {}
    check(#retPool == 0, "historical rows did not enter live relist pool")
    local sellRows = rawRows("AH_SELL")
    check(#sellRows == 1 and sellRows[1].cogs == 150, "historical sale used chronological buy basis (10 * 15c = 150c)")
end)

test("R4 cancelling specific auctionID closes matching lot deposit instead of oldest FIFO", function()
    local char = current()
    -- Lot 1: auctionID 101, deposit 20c, unit 50c; Lot 2: auctionID 202, deposit 90c, unit 120c
    Store.Append({ type = "AH_POST", itemID = 2447, qty = 10, unit = 50, total = -20, extra = { auctionID = 101, name = "Item 2447" } })
    Store.Append({ type = "AH_POST", itemID = 2447, qty = 10, unit = 120, total = -90, extra = { auctionID = 202, name = "Item 2447" } })
    local oldOwned = C_AuctionHouse.GetOwnedAuctionInfo
    C_AuctionHouse.GetOwnedAuctionInfo = function(idx)
        if idx == 1 then return { auctionID = 202, itemID = 2447, quantity = 10, unitPrice = 120, buyoutAmount = 1200 } end
    end
    C_AuctionHouse.CancelAuction(202)
    fire("AUCTION_CANCELED", 202)
    C_AuctionHouse.GetOwnedAuctionInfo = oldOwned
    local c = exactly("AH_CANCEL", 1)
    check(c.extra.depLost == 90, "cancelling auction 202 loses 90c deposit, not 20c oldest lot (got " .. tostring(c.extra.depLost) .. ")")
    local lots = Store.Lots(char, 2447)
    check(#lots == 1 and lots[1].auctionID == 101 and lots[1].deposit == 20, "lot 101 remains open intact")
    -- Cancelling an untracked pre-install auction (auctionID 999, unitPrice 300) must NOT close lot 101!
    C_AuctionHouse.GetOwnedAuctionInfo = function(idx)
        if idx == 1 then return { auctionID = 999, itemID = 2447, quantity = 10, unitPrice = 300, buyoutAmount = 3000 } end
    end
    C_AuctionHouse.CancelAuction(999)
    fire("AUCTION_CANCELED", 999)
    C_AuctionHouse.GetOwnedAuctionInfo = oldOwned
    lots = Store.Lots(char, 2447)
    check(#lots == 1 and lots[1].auctionID == 101 and lots[1].deposit == 20, "untracked cancel leaves tracked lot 101 intact")
    -- Also when both a priced unassigned lot (unit=50) and a zero-price unassigned lot (unit=0) exist, unmatched cancel at unit=300 closes ONLY the zero-price lot!
    Store.Append({ type = "AH_POST", itemID = 2448, qty = 5, unit = 50, total = -40, extra = { name = "Item 2448" } })
    Store.Append({ type = "AH_POST", itemID = 2448, qty = 5, unit = 0, total = -10, extra = { name = "Item 2448" } })
    Store.Append({ type = "AH_CANCEL", itemID = 2448, qty = 5, unit = 300, total = 0, extra = { auctionID = 888, unitPrice = 300 } })
    local lots48 = Store.Lots(char, 2448)
    check(#lots48 == 1 and lots48[1].unit == 50 and lots48[1].deposit == 40, "unmatched cancel closes only zero-unit fallback lot, preserving priced lot")
    -- Also test live post confirmed by PLAYER_MONEY BEFORE AUCTION_HOUSE_AUCTION_CREATED(id): auctionID still attaches so cancelling older same-price auction closes older deposit!
    mockAuctionItem = 2449; bag[2449] = 40
    local loc = ItemLocation:CreateFromBagAndSlot(0, 1)
    mockDeposit = 25; C_AuctionHouse.PostCommodity(loc, 1, 10, 80); mockMoney = mockMoney - 25; fire("PLAYER_MONEY"); fire("AUCTION_HOUSE_AUCTION_CREATED", 501)
    mockDeposit = 95; C_AuctionHouse.PostCommodity(loc, 1, 10, 80); mockMoney = mockMoney - 95; fire("PLAYER_MONEY"); fire("AUCTION_HOUSE_AUCTION_CREATED", 502)
    C_AuctionHouse.GetOwnedAuctionInfo = function(idx)
        if idx == 1 then return { auctionID = 501, itemID = 2449, quantity = 10, unitPrice = 80, buyoutAmount = 800 } end
    end
    C_AuctionHouse.CancelAuction(501); fire("AUCTION_CANCELED", 501)
    C_AuctionHouse.GetOwnedAuctionInfo = oldOwned
    local lots49 = Store.Lots(char, 2449)
    check(#lots49 == 1 and lots49[1].auctionID == 502 and lots49[1].deposit == 95, "PLAYER_MONEY confirmation still bound auctionID 501/502 so cancelling 501 left 502 intact")
end)

test("R4 character filter isolates Char A vs Char B in same economy on Items and Overview", function()
    local charA = "Normal-Horde-Forever-AnalyticsA"
    local charB = "Normal-Horde-Forever-AnalyticsB"
    Store.Append({ char = charA, econ = "Normal-Horde", type = "AH_BUY", itemID = 2447, qty = 10, total = -100 })
    Store.Append({ char = charA, econ = "Normal-Horde", type = "AH_SELL", itemID = 2447, qty = 10, total = 500, extra = { gross = 500, fee = 0 } })
    Store.Append({ char = charB, econ = "Normal-Horde", type = "AH_BUY", itemID = 2448, qty = 10, total = -200 })
    Store.Append({ char = charB, econ = "Normal-Horde", type = "AH_SELL", itemID = 2448, qty = 10, total = 900, extra = { gross = 900, fee = 0 } })
    local itemsA = compute("items", { char = charA }).rows
    local itemsB = compute("items", { char = charB }).rows
    check(#itemsA == 1 and itemsA[1].itemID == 2447 and itemsA[1].profit == 400, "Items filtered to Char A excludes Char B")
    check(#itemsB == 1 and itemsB[1].itemID == 2448 and itemsB[1].profit == 700, "Items filtered to Char B excludes Char A")
    local ovA = compute("overview", { char = charA })
    local ovB = compute("overview", { char = charB })
    check(ovA.kpis.profit == 400 and #ovA.top == 1 and ovA.top[1].itemID == 2447, "Overview filtered to Char A")
    check(ovB.kpis.profit == 700 and #ovB.top == 1 and ovB.top[1].itemID == 2448, "Overview filtered to Char B")
end)

test("R4 recipe array craft-cost fallback, paidBackPct percentage, totalMatched and EstimateBytes perf", function()
    -- 1. RECIPES_BY_OUTPUT array shape ({ rec1 })
    local oldCost, oldRecipes = host.ComputeCraftCost, host.RECIPES_BY_OUTPUT[2447]
    host.RECIPES_BY_OUTPUT[2447] = { { reagents = { { 1, 1 } }, numMade = 1 } }
    host.ComputeCraftCost = function(reagents) return reagents and 75 or nil end
    local cost = Store.EstimateCraftOrMarketCost(2447)
    host.ComputeCraftCost, host.RECIPES_BY_OUTPUT[2447] = oldCost, oldRecipes
    check(cost == 75, "RECIPES_BY_OUTPUT array shape unwraps first recipe")
    -- 2. Recipe paidBackPct renders 50.0% not 0.5%
    local rec = host.RECIPES[1]
    if rec and rec.recipeItemID then
        local out = rec.outputItemID or rec.itemID
        Store.Append({ type = "VENDOR_BUY", itemID = rec.recipeItemID, qty = 1, total = -1000 })
        Store.Append({ type = "AH_BUY", itemID = out, qty = 5, total = -100 })
        Store.Append({ type = "AH_SELL", itemID = out, qty = 5, total = 600, extra = { gross = 600, fee = 0 } })
        local inv = compute("invest").recipes[1]
        check(inv and math.abs(inv.paidBackPct - 0.5) < 0.001, "paidBackPct model ratio is 0.5")
        local rendered = UI.Columns.an_recipes[8].render(inv)
        check(rendered == "50.0%", "paidBackPct renders 50.0%, got " .. tostring(rendered))
    end
    -- 3. Ledger totalMatched > 500 while rows capped at 500
    for i = 1, 520 do append("ADJUST", 0, 0, 1, {}, mockNow - i) end
    local led = compute("ledger")
    check(#led.rows == 500 and led.totalMatched >= 520, "ledger exposes full totalMatched count")
    -- 4. EstimateBytes speed on 365d x 300 items (< 5ms uncached, 0ms cached)
    local char = current()
    for d = 0, 364 do
        local day, items = Store.DayKey(mockNow - d * 86400), {}
        for i = 1, 300 do items[10000 + i] = { sold = 1 } end
        MerchantMasterLedgerDB.roll[day] = { [char] = items }
    end
    Store.version = Store.version + 1
    local t0 = realOS.clock() * 1000
    local bytes1 = Store.EstimateBytes()
    local dt1 = realOS.clock() * 1000 - t0
    local t1 = realOS.clock() * 1000
    local bytes2 = Store.EstimateBytes()
    local dt2 = realOS.clock() * 1000 - t1
    print(string.format("MEASURE EstimateBytes uncached=%.3f ms cached=%.3f ms bytes=%d", dt1, dt2, bytes1))
    check(bytes1 == bytes2 and bytes1 > 100000 and dt1 <= 15 * ciScale and dt2 <= 1 * ciScale, "EstimateBytes fast & cached")
end)

test("R5 expandable wealth breakdown categories, bound/gear valuation, offline alt fallback and UI expand/collapse", function()
    local charA = current()
    local charB = "Normal-Horde-Forever-AltThe"
    -- Set up market prices + vendor prices + bound/gear/mail/bank items on active char + offline alt
    mockTSMPrices.dbminbuyout[2447], mockTSMPrices.dbmarket[2447], mockTSMPrices.dbnumauctions[2447] = 500, 500, 12 -- Peacebloom: 5s AH
    mockTSMPrices.dbminbuyout[9991], mockTSMPrices.dbmarket[9991], mockTSMPrices.dbnumauctions[9991] = 25000, 25000, 0 -- Unlisted w/ region avg
    local oldGetVendor, oldMarket, oldListed, oldSellable = host.GetVendorSellPrice, host.GetItemMarketPrice, host.GetNumListed, host.IsItemSellable
    host.GetVendorSellPrice = function(id)
        if id == 2447 then return 25 end
        if id == 7001 then return 420 end -- Equipped Leather Vest (vendor 4s 20c)
        if id == 7002 then return 180 end -- Bound Bag Item (vendor 1s 80c)
        if id == 9991 then return 60 end -- Unlisted item (vendor 60c)
        return 0
    end
    host.GetItemMarketPrice = function(id)
        if id == 2447 then return 500, "Live AH" end
        if id == 7001 then return 80000, "Live AH" end -- even if AH has price, gear must be vendor!
        if id == 7002 then return 50000, "Live AH" end -- bound bag item must be vendor!
        if id == 9991 then return nil, nil end -- unlisted item falls back to vendor!
        if id == 8001 then return 3700, "Saved AH" end -- Shadow Protection Writ
        return nil, nil
    end
    host.GetNumListed = function(id)
        if id == 9991 then return 0 end
        return 5
    end
    host.IsItemSellable = function(id) return id ~= 6948 end -- Hearthstone unsellable
    MerchantMasterDB.itemIDs = MerchantMasterDB.itemIDs or {}
    MerchantMasterDB.itemIDs["Peacebloom"] = 2447
    MerchantMasterDB.itemIDs["Explorer Tunic"] = 7001
    MerchantMasterDB.itemIDs["Soulbound Trophy"] = 7002
    MerchantMasterDB.itemIDs["Unlisted Relic"] = 9991
    MerchantMasterDB.itemIDs["Journeyman Pouch"] = 284584
    MerchantMasterDB.itemIDs["Hearthstone"] = 6948
    MerchantMasterDB.itemIDs["Writ: Shadow Prot"] = 8001
    host.app.char.bags = { ["Peacebloom"] = 10, ["Soulbound Trophy"] = 2, ["Unlisted Relic"] = 1, ["Hearthstone"] = 1 }
    host.app.char.boundBags = { ["Soulbound Trophy"] = 2 }
    host.app.char.bank = { ["Journeyman Pouch"] = 2 }
    host.app.char.boundBank = {}
    host.app.char.mail = { ["Peacebloom"] = 4 }
    host.app.char.bought = {}
    host.app.char.gear = { ["Explorer Tunic"] = 1 }
    local oldScanGear = host.app.scanGear
    host.app.scanGear = nil -- preserve mock gear table above
    Store.Append({ char = charA, econ = "Normal-Horde", type = "AH_POST", itemID = 2447, qty = 5, unit = 600, total = -20 })
    mockMoney = 27076
    Capture.QueueWealthSnapshot({ sync = true })

    -- Offline alt in MerchantMasterDB.chars with legacy snapshot (no DB.wealth[charB] yet!)
    MerchantMasterDB.chars = MerchantMasterDB.chars or {}
    MerchantMasterDB.chars[charB] = {
        name = "The",
        economy = "Normal-Horde",
        bags = { ["Writ: Shadow Prot"] = 7, ["Hearthstone"] = 1 },
        mail = { ["Peacebloom"] = 3 },
    }
    Store.SaveSnapshot(charB, Store.DayKey(), { gold = 0, items = 7 * 3700 + 3 * 500, listed = 0, econ = "Normal-Horde" })
    Model.Invalidate()

    local ok, err = pcall(function()
        local p = compute("portfolio")
        check(p.categories and #p.categories == 6, "portfolio returns 6 wealth categories")
        local byKey = {}
        for _, cat in ipairs(p.categories) do byKey[cat.catKey] = cat end
        -- Verify charA item valuations:
        -- Bags on charA: 10*500 (5000) + 2*180 bound (360) + 1*60 unlisted (60) + 0 hearthstone = 5420
        -- Bags on charB (offline fallback): 7*3700 (25900) + 0 = 25900 -> total bags = 31320
        check(byKey.gold.total == 27076, "Liquid Gold category matches 27076c, got " .. tostring(byKey.gold.total))
        check(byKey.bags.total == 31320, "Bags category values tradeable at market, bound at vendor, unlisted TSM avg at vendor, plus offline alt, got " .. tostring(byKey.bags.total))
        check(byKey.bank.total == 2 * 3536, "Bank category values 2x Journeyman Coin Pouch at Pouch Avg (7072c), got " .. tostring(byKey.bank.total))
        check(byKey.mail.total == (4 + 3) * 500, "Mail category combines charA (4) + offline alt charB (3) mail items (3500c), got " .. tostring(byKey.mail.total))
        check(byKey.gear.total == 420, "Equipped Gear strictly valued at vendor sell price (420c, never 80000c AH), got " .. tostring(byKey.gear.total))
        check(byKey.listed.total == 5 * 600, "Listed on AH category values open lot at 3000c, got " .. tostring(byKey.listed.total))

        -- Verify CharShort reads MerchantMasterDB.chars[charB].name
        check(Model.CharShort(charB) == "The (Normal/Horde)", "CharShort formats offline alt cleanly")

        -- Verify UI rendering, [+] / [-] expand/collapse, and View switcher
        MerchantMasterDB.anPortfolioView = "breakdown"
        UI.expandedWealth = { bags = true, gear = false }
        host.app.panel:Show(); MerchantMasterAPI.SetTab("an_portfolio"); host.app.refresh()
        local view = UI.views.an_portfolio
        check(view.breakdownPane:IsShown() and not view.charsPane:IsShown(), "Wealth Breakdown pane visible by default")
        local rows = view.breakdownTable.scrollBox._dp:GetCollection()
        -- 6 categories + bags children (Peacebloom charA, Writ charB, Soulbound Trophy charA, Unlisted Relic charA, Hearthstone x2)
        check(#rows > 6, "Expanded Bags category renders child item rows below Bags header")
        local gearCatIdx
        for idx, r in ipairs(rows) do
            if r.isCategory and r.catKey == "gear" then gearCatIdx = idx end
        end
        check(gearCatIdx ~= nil and rows[gearCatIdx].expanded == false, "Equipped Gear starts collapsed")
        local renderedCollapsed = UI.Columns.an_wealth[1].render(rows[gearCatIdx])
        check(renderedCollapsed:find("[+]", 1, true) ~= nil and renderedCollapsed:find("Equipped Gear", 1, true) ~= nil, "Collapsed category renders [+] Equipped Gear")

        -- Simulate clicking the Equipped Gear row to expand it
        UI.expandedWealth.gear = true; host.app.refresh()
        local rows2 = view.breakdownTable.scrollBox._dp:GetCollection()
        check(#rows2 == #rows + 1, "Expanding Equipped Gear adds Explorer Tunic child row")
        local gearAfter
        for idx, r in ipairs(rows2) do
            if r.isCategory and r.catKey == "gear" then gearAfter = idx end
        end
        check(rows2[gearAfter].expanded == true and rows2[gearAfter + 1].name == "Explorer Tunic" and rows2[gearAfter + 1].basis == "Vendor (Gear)",
            "Child item appears directly under [-] Equipped Gear with Vendor (Gear) basis")

        -- Switch to By Character view
        MerchantMasterDB.anPortfolioView = "chars"; host.app.refresh()
        check(not view.breakdownPane:IsShown() and view.charsPane:IsShown(), "Switching anPortfolioView to chars shows character table")
        MerchantMasterDB.anPortfolioView = "breakdown"

        -- Verify cross-economy UI selection isolation + synthetic alt reconciliation + cold-cache item load resnapshot
        host.GetItemMarketPrice = function(id)
            local econ = MerchantMasterDB.economy or "Normal-Horde"
            if id == 2447 then return (econ == "PvP-Alliance") and 99999 or 500, "Saved AH" end
            if id == 8001 then return 3700, "Saved AH" end
            return nil, nil
        end
        MerchantMasterDB.economy = "PvP-Alliance"
        Capture.QueueWealthSnapshot({ sync = true })
        check(MerchantMasterDB.economy == "PvP-Alliance", "QueueWealthSnapshot restores selected UI economy")
        check(MerchantMasterLedgerDB.wealth[charA].cats.bags[1].unit == 500, "CharA bag item valued at Normal-Horde 500c despite UI viewing PvP-Alliance")
        MerchantMasterDB.economy = "Normal-Horde"

        -- Synthetic offline alt with stale s.items reconciles latestTotal and byChar
        Store.SaveSnapshot(charB, Store.DayKey(), { gold = 0, items = 999999, listed = 0, econ = "Normal-Horde" })
        Model.Invalidate()
        local pSync = compute("portfolio")
        local sumChars = 0
        for _, bc in ipairs(pSync.byChar) do sumChars = sumChars + bc.total end
        check(pSync.latestTotal == sumChars and pSync.latestTotal < 200000, "Synthetic offline alt reconciles stale legacy snapshot total with itemized total")

        -- Cold-cache nil vendor price queues GET_ITEM_INFO_RECEIVED resnapshot
        local coldLoaded = false
        host.GetVendorSellPrice = function(id)
            if id == 7001 then return coldLoaded and 420 or nil end
            if id == 7002 then return 180 end
            if id == 9991 then return 60 end
            return 0
        end
        Capture.QueueWealthSnapshot({ sync = true })
        check(Capture._pendingItemIDs and Capture._pendingItemIDs[7001] == true, "Cold-cache gear item registered in _pendingItemIDs")
        coldLoaded = true
        Capture.frame:GetScript("OnEvent")(Capture.frame, "GET_ITEM_INFO_RECEIVED", 7001, true)
        advanceTime(3.0)
        check(MerchantMasterLedgerDB.wealth[charA].cats.gear[1].total == 420, "GET_ITEM_INFO_RECEIVED resnapshots cold-cache gear at 420c vendor value")
    end)

    host.GetVendorSellPrice, host.GetItemMarketPrice, host.GetNumListed, host.IsItemSellable = oldGetVendor, oldMarket, oldListed, oldSellable
    host.app.scanGear = oldScanGear
    check(ok, tostring(err))
end)

test("R6 mailbox pre-hook, shifted slot rapid loot, live listed sync, AH owned sync, TSM catch-up and confirmed Writ turn-ins", function()
    local char, econ = current()
    local oldGetInvoice = _G.GetInboxInvoiceInfo
    local oldTakeMoney = _G.TakeInboxMoney
    local oldGetMapInfo = _G.C_Map.GetMapInfo
    local oldGetNextWp = _G.C_QuestLog.GetNextWaypoint
    local oldGetQuestsOnMap = _G.C_QuestLog.GetQuestsOnMap
    local oldNumOwned = _G.C_AuctionHouse.GetNumOwnedAuctions
    local oldOwnedInfo = _G.C_AuctionHouse.GetOwnedAuctionInfo

    local ok, err = pcall(function()
        -- 1. Post 2x Dusky Leather Armor (7374) and 1x Fire Oil (6371), verify live Listed on AH = 3 items
        Store.AddBasis(econ, 7374, 2, 6544)
        Store.AddBasis(econ, 6371, 1, 200)
        Store.Append({ type = "AH_POST", char = char, econ = econ, itemID = 7374, qty = 1, unit = 8990, total = -140, where = "Auction House", extra = { deposit = 140, unitPrice = 8990, auctionID = 63662330 } })
        Store.Append({ type = "AH_POST", char = char, econ = econ, itemID = 7374, qty = 1, unit = 8990, total = -140, where = "Auction House", extra = { deposit = 140, unitPrice = 8990, auctionID = 63663546 } })
        Store.Append({ type = "AH_POST", char = char, econ = econ, itemID = 6371, qty = 1, unit = 500, total = -20, where = "Auction House", extra = { deposit = 20, unitPrice = 500, auctionID = 63669999 } })
        Model.Invalidate()
        local pBefore = compute("portfolio")
        check(pBefore.latestListed == (8990 + 8990 + 500), "Portfolio Listed on AH immediately reflects 3 live open lots")

        -- 2. Simulate Blizzard C TakeInboxMoney clearing money=0 inside C AND rapid Open-All shifting Slot 2 -> Slot 1 without MAIL_INBOX_UPDATE
        -- Also simulate empty player="" at MAIL_SHOW streaming to "BuyerOne" / "BuyerTwo" at TakeInboxMoney!
        mail = {
            { id = 6371, name = "Fire Oil", qty = 1, gross = 500, deposit = 20, fee = 25, money = 495, invoice = "seller", buyer = "", subject = "Auction successful: Fire Oil" },
            { id = 7374, name = "Dusky Leather Armor", qty = 1, gross = 8990, deposit = 140, fee = 449, money = 8681, invoice = "seller", buyer = "", subject = "Auction successful: Dusky Leather Armor" },
            { id = 0, name = "", qty = 0, money = 0, invoice = "", sender = "Guildie", subject = "" }, -- empty subject player mail must NOT poison cacheMail!
        }
        _G.GetInboxInvoiceInfo = function(i)
            local m = mail[i]; if not m or m.invoice == "" then return end
            return m.invoice or "seller", m.name, m.buyer or "", m.gross, m.gross, m.deposit or 0, m.fee or 0, 0, 0, 0, m.qty or 1, true
        end
        -- Reinstall pre-hook around simulated C TakeInboxMoney that strips money immediately
        _G.__MMAnalyticsMailPreHooked = nil
        _G.TakeInboxMoney = function(i)
            if mail[i] then mockMoney=mockMoney+(mail[i].money or 0); mail[i].money = 0 end
        end
        Capture.InstallHooks()

        fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
        -- Async buyer name arrives before click
        mail[1].buyer = "BuyerOne"
        mail[2].buyer = "BuyerTwo"
        -- Loot Slot 1 (Fire Oil); C strips money=0; mail shifts Slot 2 -> Slot 1 immediately (Open All Mail behavior)
        _G.TakeInboxMoney(1)
        table.remove(mail, 1)
        -- Loot shifted Slot 1 (Dusky Leather Armor) BEFORE any MAIL_INBOX_UPDATE!
        _G.TakeInboxMoney(1)
        fire("CLOSE_INBOX_ITEM", 1)
        advanceTime(0.5)

        local sellRows = rawRows("AH_SELL")
        check(#sellRows == 2, "Both shifted rapid-looted mailbox sales recorded via pre-hook despite C clearing money")
        check(sellRows[1].itemID == 6371 and sellRows[2].itemID == 7374, "Fire Oil and Dusky Leather Armor both captured with exact itemIDs")
        check(sellRows[2].extra.buyer == "BuyerTwo", "Async streamed buyer name preserved without breaking dedupe fingerprint")
        check(#Store.Lots(char, 7374) == 1, "Dusky Leather Armor open lots dropped from 2 to 1 immediately")
        Model.Invalidate()
        local pAfter = compute("portfolio")
        check(pAfter.latestListed == 8990, "Portfolio Listed on AH immediately updates from 2x to 1x Dusky Leather Armor (8990c)")

        -- 3. Verify Store.ReconcileTSMSales is removed in standalone mode
        check(Store.ReconcileTSMSales == nil, "Legacy Store.ReconcileTSMSales removed in pure standalone mode")

        -- 4. Verify Capture.SyncOwnedAuctions prunes phantom open lots when AH is open and mailbox has no pending AH mail
        Store.Append({ type = "AH_POST", char = char, econ = econ, itemID = 2447, qty = 5, unit = 100, total = -15, where = "Auction House", time = mockNow - 120, extra = { deposit = 15, unitPrice = 100, auctionID = 888001 } })
        check(#Store.Lots(char, 2447) == 1, "Phantom lot staged before AH sync")
        mail = {}
        _G.AuctionHouseFrame = { IsShown = function() return true end }
        _G.HasNewMail = function() return false end
        _G.C_AuctionHouse.GetNumOwnedAuctions = function() return 0 end
        _G.C_AuctionHouse.GetOwnedAuctionInfo = function() return nil end
        Capture.visitedMailboxThisSession = true
        local pruned = Capture.SyncOwnedAuctions()
        check(pruned == 5 and #Store.Lots(char, 2447) == 0, "SyncOwnedAuctions prunes missing lot when AH owned list is empty and mailbox is clear")
        _G.AuctionHouseFrame = nil

        -- 5. Only a completed turn-in may persist a learned destination.
        MerchantMasterDB.learnedWritZones = {}
        local mapCalls = 0
        _G.C_QuestLog.GetNextWaypoint = function() mapCalls = mapCalls + 1; return 1428, 0.652, 0.241 end
        _G.C_QuestLog.GetQuestsOnMap = function() mapCalls = mapCalls + 1; return { { questID = 94325, x = 0.409, y = 0.28 } } end
        check(not Capture.frame._events.QUEST_ACCEPTED, "Capture does not register QUEST_ACCEPTED")
        check(Capture.LearnWritZoneFromQuest == nil, "Quest-accept location learner is removed")
        fire("QUEST_ACCEPTED", 1, 94325)
        advanceTime(1)
        check(MerchantMasterDB.learnedWritZones[264125] == nil and mapCalls == 0,
            "Accepting Radiant Circlet does not persist or query waypoint locations")

        mockZone = "Burning Steppes"
        _G.UnitName = function(u) return u == "npc" and "Tinkee Steamboil" or playerShort end
        mockQuest = 94325
        GetQuestReward(1)
        fire("QUEST_TURNED_IN", 94325, 0, 0)
        _G.UnitName = oldUnitName
        local lwTurnin = MerchantMasterDB.learnedWritZones[264125]
        check(lwTurnin and lwTurnin.zone == "Burning Steppes" and lwTurnin.subzone == "Test Camp"
            and lwTurnin.npc == "Tinkee Steamboil" and lwTurnin.x == 50 and lwTurnin.y == 50
            and lwTurnin.source == "turnin" and lwTurnin.at == mockNow,
            "Completed turn-in persists exact zone, subzone, NPC, coordinates and timestamp")
        local writ
        for _, entry in ipairs(host.WRITS) do if entry.itemID == 264125 then writ = entry; break end end
        local learnedZone, learnedSource = host.GetWritZoneInfo(writ)
        check(learnedZone == "Burning Steppes" and learnedSource == "learned", "Confirmed turn-in resolves as learned")

        local synthetic = { zone = "Synthetic Vale", npc = "Fixture", source = "synthetic" }
        local zones = { [264125] = lwTurnin, [900001] = { zone = "Badlands", source = "quest_accept" },
            [900002] = { zone = "Dustwallow Marsh", source = "bettermaps" },
            [900003] = { zone = "Mulgore", source = "quest_accept" },
            [900004] = synthetic, [900005] = { source = "bettermaps" } }
        MerchantMasterDB.learnedWritZones = zones
        check(host.SanitizeLearnedWritZones == Capture.SanitizeLearnedWritZones, "Sanitizer is exported on the host namespace")
        check(Capture.SanitizeLearnedWritZones(zones), "Sanitizer removes unconfirmed sources in every zone and unknown IDs")
        check(zones[900001] == nil and zones[900002] == nil and zones[900003] == nil and zones[900005] == nil,
            "Both stale source types are removed even without a zone")
        check(zones[264125] == lwTurnin and zones[900004] == synthetic, "Sanitizer preserves completed turn-ins and synthetic entries")
        check(not Capture.SanitizeLearnedWritZones(zones), "Sanitizer is idempotent")
        zones[900006] = { source = "quest_accept", zone = "Feralas" }
        check(Capture.SyncActiveWritQuests() == 0 and zones[900006] == nil and mapCalls == 0,
            "Compatibility sync only sanitizes and never queries quests")
        zones[264125] = { zone = "Dustwallow Marsh", source = "bettermaps" }
        local staleZone, staleSource = host.GetWritZoneInfo(writ)
        check(staleZone == "Azshara" and staleSource == "hint", "Zone lookup ignores stale sources before login sanitization")
        zones[900007] = { zone = "Badlands", source = "quest_accept" }
        reloadCapture(true)
        check(zones[264125] == nil and zones[900007] == nil and zones[900004] == synthetic,
            "PLAYER_LOGIN immediately sanitizes stale sources and preserves synthetic data")

    end)

    _G.GetInboxInvoiceInfo = oldGetInvoice
    _G.__MMAnalyticsMailPreHooked = nil
    _G.TakeInboxMoney = oldTakeMoney
    Capture.InstallHooks()
    _G.C_Map.GetMapInfo = oldGetMapInfo
    _G.C_QuestLog.GetNextWaypoint = oldGetNextWp
    _G.C_QuestLog.GetQuestsOnMap = oldGetQuestsOnMap
    _G.C_AuctionHouse.GetNumOwnedAuctions = oldNumOwned
    _G.C_AuctionHouse.GetOwnedAuctionInfo = oldOwnedInfo
    check(ok, tostring(err))
end)

test("R7 analytics resets only the active route and restores wealth series", function()
	local app = host.app
	local oldTab = app.activeTab
	MerchantMasterDB.anProf, MerchantMasterDB.anGroup, MerchantMasterDB.anMinRarity = "items-prof", "items-prof", 3
	MerchantMasterDB.anLedgerGroup, MerchantMasterDB.anLedgerMinRarity = "alchemy", 4
	app.activeTab = "an_ledger"
	local ledgerFilters = UI.Filters()
	check(ledgerFilters.group == "alchemy" and ledgerFilters.minRarity == 4 and ledgerFilters.prof == nil,
		"Ledger reads its own category and rarity filters")
	UI.ResetFilters()
	ledgerFilters = UI.Filters()
	check(ledgerFilters.group == nil and ledgerFilters.minRarity == nil and MerchantMasterDB.anLedgerGroup == nil
		and MerchantMasterDB.anLedgerMinRarity == nil, "Ledger reset clears stored and effective category and rarity filters")
	check(UI.views.an_ledger.prof:GetText() == "Prof" and UI.views.an_ledger.rarity:GetText() == "Rarity",
		"Ledger reset restores the category and rarity controls")
	check(MerchantMasterDB.anProf == "items-prof" and MerchantMasterDB.anGroup == "items-prof"
		and MerchantMasterDB.anMinRarity == 3, "Ledger reset preserves Items category and rarity selections")
	app.activeTab = "an_items"
	local itemFilters = UI.Filters()
	check(itemFilters.group == "items-prof" and itemFilters.minRarity == 3 and itemFilters.prof == "items-prof",
		"Items continues to use its independent category and rarity filters")
	MerchantMasterDB.anLedgerPreset = "other"
	MerchantMasterDB.anLedgerOffset = 125
	MerchantMasterDB.anPortfolioView = "characters"
	MerchantMasterDB.anInvPriceSource = "basis"
	MerchantMasterDB.anChar, MerchantMasterDB.anPeriod, MerchantMasterDB.anProf = "Mage-Realm", "7d", "alchemy"
	app.activeTab = "an_writs"
	UI.ResetFilters()
	check(MerchantMasterDB.anChar == "all" and MerchantMasterDB.anPeriod == "30d" and MerchantMasterDB.anProf == nil,
		"writ reset clears shared analytics bar filters")
	check(MerchantMasterDB.anLedgerPreset == "other" and MerchantMasterDB.anLedgerOffset == 125,
		"writ reset preserves ledger preferences")
	check(MerchantMasterDB.anPortfolioView == "characters" and MerchantMasterDB.anInvPriceSource == "basis",
		"writ reset preserves portfolio preferences")
	MerchantMasterDB.anWealthSeries = { total = false, gold = false, items = false, listed = false }
	app.activeTab = "an_overview"
	UI.ShowWealthSeriesMenu()
	UI.ResetFilters()
	check(UI.seriesMenu and not UI.seriesMenu:IsShown(), "overview reset closes the open wealth-series picker")
	local series = MerchantMasterDB.anWealthSeries
	check(series.total and series.gold and series.items and series.listed, "overview reset enables every wealth series")
	app.activeTab = oldTab
end)

test("R8 Items source and faction selections do not filter other analytics routes", function()
	local oldTab, oldSource, oldFaction = host.app.activeTab, MerchantMasterDB.anSource, MerchantMasterDB.anFaction
	local oldQuery, queriedFilters = Model.QueryLedger
	host.app.activeTab = "an_items"
	MerchantMasterDB.anSource, MerchantMasterDB.anFaction = "Craft", "Horde"
	local itemFilters = UI.Filters()
	check(itemFilters.source == "Craft" and itemFilters.faction == "Horde", "Items applies its selected source and faction")
	Model.QueryLedger = function(filters, ...)
		queriedFilters = filters
		return oldQuery(filters, ...)
	end
	host.app.activeTab = "an_ledger"
	local ok, err = pcall(UI.Refresh, "an_ledger", host.app.ui.analyticsView)
	Model.QueryLedger = oldQuery
	local ledgerUnfiltered = queriedFilters and queriedFilters.source == nil and queriedFilters.faction == "all"
	local storedSelections = MerchantMasterDB.anSource == "Craft" and MerchantMasterDB.anFaction == "Horde"
	local otherRoutesUnfiltered = true
	for _, tab in ipairs({ "an_overview", "an_portfolio", "an_wealth", "an_invest", "an_recipes", "an_writs", "an_pushes" }) do
		host.app.activeTab = tab
		local filters = UI.Filters()
		otherRoutesUnfiltered = otherRoutesUnfiltered and filters.source == nil and filters.faction == "all"
	end
	host.app.activeTab = "an_items"
	itemFilters = UI.Filters()
	host.app.activeTab, MerchantMasterDB.anSource, MerchantMasterDB.anFaction = oldTab, oldSource, oldFaction
	check(ok, "Ledger refresh completes: " .. tostring(err))
	check(ledgerUnfiltered, "Ledger query ignores hidden Items source and faction selections")
	check(otherRoutesUnfiltered, "Routes without source and faction controls query all sources and factions")
	check(storedSelections and itemFilters.source == "Craft" and itemFilters.faction == "Horde",
		"Returning to Items restores the stored Craft and Horde selections")
end)

test("R7 Overview passes exact copper amounts to the money formatter", function()
	local oldTab, oldCompute = host.app.activeTab, Model.Compute
	local oldPriceDisplayMode = MerchantMasterDB.priceDisplayMode
	local oldMoneyFormatter = host.Theme.FormatMoneyFable
	local captured, fractionalPassedThrough = {}, false
	MerchantMasterDB.priceDisplayMode = "full_fixed"
	local metrics = { profit = -10000, avgDailyProfit = 12345 }
	Model.Compute = function()
		return { kpis = metrics, top = {}, profitByDay = {}, wealth = {},
			topSingleSale = {}, topSingleBuy = {} }
	end
	host.Theme.FormatMoneyFable = function(value, signed)
		captured[#captured + 1] = value
		if value == 49.6 then fractionalPassedThrough = true end
		return oldMoneyFormatter(value, signed)
	end
	host.app.activeTab = "an_overview"
	local ok, err = pcall(UI.Refresh, "an_overview", host.app.ui.analyticsView)
	local rendered = UI.views.an_overview.kpis[1].value:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	MerchantMasterDB.priceDisplayMode = "no_copper"
	metrics.profit, metrics.avgDailyProfit = 0, 49.6
	local fractionalOk, fractionalErr = pcall(UI.Refresh, "an_overview", host.app.ui.analyticsView)
	local fractionalText = UI.views.an_overview.kpis[1].value:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	Model.Compute = oldCompute
	host.Theme.FormatMoneyFable = oldMoneyFormatter
	MerchantMasterDB.priceDisplayMode = oldPriceDisplayMode
	host.app.activeTab = oldTab
	check(ok, "Overview refresh completes with full-fixed money formatting: " .. tostring(err))
	check(captured[1] == -10000 and captured[2] == 12345,
		"Overview formatter receives -10000c and 12345c without pre-rounding")
	check(rendered:find("-01g 00s 00c", 1, true) ~= nil and rendered:find("01g 23s 45c", 1, true) ~= nil,
		"Overview displays -10000c and 12345c with exact full-fixed silver and copper buckets")
	check(fractionalOk, "Overview refresh completes with fractional no-copper average: " .. tostring(fractionalErr))
	check(fractionalPassedThrough and fractionalText:find("Avg/Day 0s", 1, true) ~= nil,
		"49.6c reaches the shared formatter and rounds to 0s in no-copper mode")
end)

test("VC-T1 Ledger craft yield telemetry captures variable rolls without double reagent consumption", function()
	local rec
	for _, r in ipairs(host.RECIPES or {}) do
		if r.spellID == 3946 then rec = r; break end
	end
	check(rec and rec.outputItemID == 4378, "Heavy Dynamite (3946 -> 4378) recipe fixture exists")
	local _, econ = current()
	bag[4377] = 10; bag[2592] = 5
	Store.AddBasis(econ, 4377, 10, 100)
	Store.AddBasis(econ, 2592, 5, 50)
	fire("BAG_UPDATE_DELAYED"); advanceTime(1)

	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-HD-1", 3946)
	fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:4378:0:0:0:0:0:0:0|h[Heavy Dynamite]|h|r x5.")
	bag[4378] = 5; bag[4377] = 8; bag[2592] = 4
	fire("BAG_UPDATE_DELAYED"); advanceTime(2)

	local craftRow = exactly("CRAFT", 1)
	check(craftRow.qty == 5, "High-roll Heavy Dynamite records qty == 5")
	check(craftRow.extra and craftRow.extra.casts == 1 and craftRow.extra.spellID == 3946,
		"CRAFT extra preserves casts == 1 and spellID == 3946")
	check(Store.Basis(econ, 4377) == 8 and Store.Basis(econ, 2592) == 4,
		"Single cast with roll=5 consumes 1x reagents (2x Powder, 1x Cloth), not 2x")

	local ys = Store.GetCraftYieldStats(3946)
	check(ys and ys.casts == 1 and ys.totalOutput == 5 and ys.minSeen == 5 and ys.maxSeen == 5
		and ys.hist and ys.hist[5] == 1, "CraftYieldStats tracks casts, totalOutput, minSeen, maxSeen, and hist")
	approxEq(ys.avg, 5.0, 0.001, "Single 5x roll gives measured avg 5.0")
end)

test("VC-T2 Ledger craft yield histogram survives Rebuild and ignores zero-bag-rise loot chat", function()
	local _, econ = current()
	local rolls = { 1, 2, 2, 3, 3, 3, 4, 4, 5, 2 }
	local powderQty, clothQty, dynamiteQty = 20, 10, 0
	bag[4377] = powderQty; bag[2592] = clothQty; bag[4378] = 0
	Store.AddBasis(econ, 4377, powderQty, powderQty * 10)
	Store.AddBasis(econ, 2592, clothQty, clothQty * 5)
	fire("BAG_UPDATE_DELAYED"); advanceTime(1)

	for idx, roll in ipairs(rolls) do
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-HD-V-" .. idx, 3946)
		local suffix = (roll > 1) and (" x" .. roll .. ".") or "."
		fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:4378:0:0:0:0:0:0:0|h[Heavy Dynamite]|h|r" .. suffix)
		powderQty = powderQty - 2
		clothQty = clothQty - 1
		dynamiteQty = dynamiteQty + roll
		bag[4377] = powderQty; bag[2592] = clothQty; bag[4378] = dynamiteQty
		fire("BAG_UPDATE_DELAYED"); advanceTime(2)
	end

	-- CHAT_MSG_LOOT + spellcast WITHOUT bag rise must NOT log craft yield or craft row
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-HD-Ghost", 3946)
	fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:4378:0:0:0:0:0:0:0|h[Heavy Dynamite]|h|r x4.")
	fire("BAG_UPDATE_DELAYED"); advanceTime(6)

	local rawCrafts = rawRows("CRAFT")
	check(#rawCrafts == 10, "10 real crafts logged and zero-bag-rise loot ignored (got " .. #rawCrafts .. ")")

	local ys = Store.GetCraftYieldStats(3946)
	check(ys and ys.casts == 10 and ys.totalOutput == 29 and ys.minSeen == 1 and ys.maxSeen == 5,
		"10 casts aggregate to totalOutput=29, minSeen=1, maxSeen=5")
	approxEq(ys.avg, 2.9, 0.001, "10 casts yield measured avg 2.9")
	check(ys.hist[1] == 1 and ys.hist[2] == 3 and ys.hist[3] == 3 and ys.hist[4] == 2 and ys.hist[5] == 1,
		"Histogram matches exact roll counts [1]=1,[2]=3,[3]=3,[4]=2,[5]=1")

	Store.Rebuild()
	local ysAfter = Store.GetCraftYieldStats(3946)
	check(ysAfter and ysAfter.casts == 10 and ysAfter.totalOutput == 29 and ysAfter.minSeen == 1
		and ysAfter.maxSeen == 5 and ysAfter.hist[2] == 3 and ysAfter.hist[5] == 1,
		"CraftYieldStats persists intact across Store.Rebuild()")
	approxEq(ysAfter.avg, 2.9, 0.001, "Measured avg persists across Store.Rebuild()")
end)

test("Portfolio CollectCharEntries merges duplicate keys and labels mixed bound/unbound splits clearly", function()
	MerchantMasterDB.itemIDs = MerchantMasterDB.itemIDs or {}
	MerchantMasterDB.itemIDs["Peacebloom"] = 2447
	MerchantMasterDB.itemIDs["Soulbound Trophy"] = 7002
	local charTbl = {
		bags = { ["Peacebloom"] = 6, [2447] = 4, ["Soulbound Trophy"] = 2 },
		boundBags = { ["Peacebloom"] = 2, ["Soulbound Trophy"] = 2 },
		bank = {}, boundBank = {}, mail = {}, bought = {}, gear = {},
	}
	local entries = Capture.CollectCharEntries(host, MerchantMasterDB, charTbl)
	local pbTrade, pbBound, trophy = nil, nil, nil
	local pbCount = 0
	for _, e in ipairs(entries) do
		if e.id == 2447 then
			pbCount = pbCount + 1
			if e.bound then pbBound = e else pbTrade = e end
		elseif e.id == 7002 then
			trophy = e
		end
	end
	check(pbCount == 2 and pbTrade and pbTrade.qty == 8 and pbTrade.name == "Peacebloom",
		"Duplicate name+numeric keys for Peacebloom merge into one tradeable entry (qty=8)")
	check(pbBound and pbBound.qty == 2 and pbBound.name == "Peacebloom (Bound)",
		"Mixed tradeable+bound item labels bound split as 'Peacebloom (Bound)'")
	check(trophy and trophy.qty == 2 and trophy.bound and trophy.name == "Soulbound Trophy",
		"Pure-bound item keeps its clean name without redundant suffix")
end)

test("Portfolio Item Inventory collapses alias charKeys and QueueWealthSnapshot avoids ghost placeholder", function()
	local oldCharKey = host.app.charKey
	local oldChar = host.app.char
	local canonKey = "Normal-Horde-ExampleRealm PvE-AliasAlt"
	local aliasKey = "Normal-Horde-Forever-AliasAlt"
	local ghostKey = "Normal-Horde-Forever-Player"
	MerchantMasterDB.chars = MerchantMasterDB.chars or {}
	MerchantMasterDB.itemIDs = MerchantMasterDB.itemIDs or {}
	MerchantMasterDB.itemIDs["Explorer Tunic"] = 7001
	MerchantMasterDB.chars[canonKey] = { name = "AliasAlt", economy = "Normal-Horde", bags = {}, bank = {}, mail = {}, gear = { ["Explorer Tunic"] = 1 } }
	MerchantMasterDB.chars[aliasKey] = { name = "AliasAlt", economy = "Normal-Horde", bags = {}, bank = {}, mail = {}, gear = { ["Explorer Tunic"] = 1 } }
	MerchantMasterLedgerDB.inventory = MerchantMasterLedgerDB.inventory or {}
	MerchantMasterLedgerDB.inventory[canonKey] = { updatedAt = mockNow, econ = "Normal-Horde", bags = {}, bank = {}, mail = {}, gear = { [7001] = 1 } }
	MerchantMasterLedgerDB.inventory[aliasKey] = { updatedAt = mockNow - 60, econ = "Normal-Horde", bags = {}, bank = {}, mail = {}, gear = { [7001] = 1 } }
	MerchantMasterLedgerDB.inventory[ghostKey] = { updatedAt = mockNow - 60, econ = "Normal-Horde", bags = {}, bank = {}, mail = {}, gear = { [7001] = 1 } }

	host.app.charKey = canonKey
	local bd = analytics.Inventory.GetItemBreakdown(7001, "Normal-Horde")
	local altGearCount = 0
	for _, entry in ipairs(bd.byChar or {}) do
		if entry.shortName == "AliasAlt" then altGearCount = altGearCount + (entry.gear or 0) end
		check(entry.char ~= aliasKey and entry.char ~= ghostKey, "GetItemBreakdown excludes alias and placeholder keys")
	end
	check(altGearCount == 1, "GetItemBreakdown counts AliasAlt equipped gear once (not 2x), got " .. tostring(altGearCount))

	local matrix = Model.GetInventoryMatrix({ econ = "Normal-Horde" })
	local tunicRow
	for _, r in ipairs(matrix.rows or {}) do if r.itemID == 7001 then tunicRow = r; break end end
	check(tunicRow and tunicRow.gear == 1, "Model.GetInventoryMatrix aggregates equipped gear without alias duplication")

	-- Pre-login / missing charKey alongside existing real chars must not create ghost Normal-Horde-Forever-Player snapshot
	host.app.charKey = nil
	host.app.char = { bags = { ["Peacebloom"] = 5 }, bank = {}, mail = {}, bought = {}, gear = { ["Explorer Tunic"] = 1 } }
	Capture._snapshotSignature = nil
	Capture.QueueWealthSnapshot({ sync = true, force = true })
	check(MerchantMasterLedgerDB.wealth[ghostKey] == nil and (not MerchantMasterLedgerDB.snaps[ghostKey]),
		"QueueWealthSnapshot skips creating ghost Normal-Horde-Forever-Player alongside real characters")

	-- Cleanup
	MerchantMasterDB.chars[canonKey] = nil
	MerchantMasterDB.chars[aliasKey] = nil
	MerchantMasterLedgerDB.inventory[canonKey] = nil
	MerchantMasterLedgerDB.inventory[aliasKey] = nil
	MerchantMasterLedgerDB.inventory[ghostKey] = nil
	host.app.charKey = oldCharKey
	host.app.char = oldChar
end)

test("Forever Surname Migration consolidates Aldric -> Aldric Stone & The -> The Endboss without doubling wealth", function()
	local oldCharKey = host.app.charKey
	local oldAnChar = MerchantMasterDB.anChar
	local pfx = "Normal-Horde-Forever"
	local oldAldric = pfx .. "-Aldric"
	local newAldric = pfx .. "-Aldric Stone"
	local oldThe = pfx .. "-The"
	local newThe = pfx .. "-The Endboss"
	local day1, day2 = "2026-11-18", "2026-11-19"

	-- Seed live/current-state tables with BOTH old & new keys (old has stale data, new has authoritative live data)
	MerchantMasterLedgerDB.wealth[oldAldric] = { econ = "Normal-Horde", at = mockNow - 500, cats = { bags = { { id = 2447, name = "Peacebloom", qty = 99, unit = 100, total = 9900 } } } }
	MerchantMasterLedgerDB.wealth[newAldric] = { econ = "Normal-Horde", at = mockNow, cats = { bags = { { id = 2447, name = "Peacebloom", qty = 5, unit = 100, total = 500 } } } }
	MerchantMasterLedgerDB.wealth[oldThe] = { econ = "Normal-Horde", at = mockNow - 400, cats = { bags = { { id = 765, name = "Silverleaf", qty = 40, unit = 200, total = 8000 } } } }
	MerchantMasterLedgerDB.wealth[newThe] = { econ = "Normal-Horde", at = mockNow - 10, cats = { bags = { { id = 765, name = "Silverleaf", qty = 10, unit = 200, total = 2000 } } } }

	MerchantMasterLedgerDB.inventory = MerchantMasterLedgerDB.inventory or {}
	MerchantMasterLedgerDB.inventory[oldAldric] = { updatedAt = mockNow - 500, econ = "Normal-Horde", bags = { [2447] = 99 }, bank = {}, mail = {}, gear = {} }
	MerchantMasterLedgerDB.inventory[newAldric] = { updatedAt = mockNow, econ = "Normal-Horde", bags = { [2447] = 5 }, bank = {}, mail = {}, gear = {} }
	MerchantMasterLedgerDB.inventory[oldThe] = { updatedAt = mockNow - 400, econ = "Normal-Horde", bags = { [765] = 40 }, bank = { [765] = 2 }, mail = {}, gear = {} }
	MerchantMasterLedgerDB.inventory[newThe] = { updatedAt = mockNow - 10, econ = "Normal-Horde", bags = { [765] = 10 }, bank = {}, mail = {}, gear = {} }

	MerchantMasterLedgerDB.snaps[oldAldric] = { [day1] = { gold = 1000, items = 9900, listed = 0, econ = "Normal-Horde" }, [day2] = { gold = 2000, items = 9900, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[newAldric] = { [day2] = { gold = 3500, items = 500, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[oldThe] = { [day1] = { gold = 500, items = 8000, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[newThe] = { [day2] = { gold = 700, items = 2000, listed = 0, econ = "Normal-Horde" } }

	-- Historical days (day1 packed string, day2 unpacked rows)
	MerchantMasterLedgerDB.days[day1] = {
		s = Store.PackRows({
			{ time = mockNow - 86400, char = oldAldric, econ = "Normal-Horde", type = "AH_SELL", where = "Auction House", itemID = 2447, qty = 10, unit = 100, total = 950, cogs = 400, extra = { gross = 1000, fee = 50 } },
			{ time = mockNow - 86300, char = oldThe, econ = "Normal-Horde", type = "AH_BUY", where = "Auction House", itemID = 765, qty = 5, unit = 200, total = -1000, extra = {} },
		}),
	}
	MerchantMasterLedgerDB.days[day2] = {
		r = {
			{ time = mockNow - 100, char = oldAldric, econ = "Normal-Horde", type = "VENDOR_SELL", where = "Orgrimmar", itemID = 2447, qty = 2, unit = 50, total = 100, extra = {} },
			{ time = mockNow - 50, char = newAldric, econ = "Normal-Horde", type = "AH_SELL", where = "Auction House", itemID = 2447, qty = 3, unit = 100, total = 285, extra = { gross = 300, fee = 15 } },
		},
	}

	-- Roll, archivedRoll, loot, archivedLoot, dayStats, basis, basisEvents, stats
	MerchantMasterLedgerDB.roll[day1] = {
		[oldAldric] = { [2447] = { sold = 10, gross = 1000, fee = 50, ahSold = 10 } },
		[newAldric] = { [2447] = { sold = 2, gross = 200, fee = 10, ahSold = 2 } },
	}
	MerchantMasterLedgerDB.archivedRoll[oldThe] = { [765] = { bought = 5, spent = 1000 } }
	MerchantMasterLedgerDB.loot[day1] = {
		[oldAldric] = { ["2447|Mob|Durotar"] = 7 },
		[newAldric] = { ["2447|Mob|Durotar"] = 3 },
	}
	MerchantMasterLedgerDB.archivedLoot[oldThe] = { ["765|Gather|Barrens"] = 12 }
	MerchantMasterLedgerDB.dayStats[day1] = {
		[oldAldric] = { salesGross = 1000, profitDelta = 550, tiers = { T1 = { writs = 1, cost = 100 } } },
		[newAldric] = { salesGross = 200, profitDelta = 100, tiers = { T1 = { writs = 2, cost = 200 } } },
	}
	MerchantMasterLedgerDB.basis[oldAldric] = { [2447] = { qty = 10, avg = 50 } }
	MerchantMasterLedgerDB.basis[newAldric] = { [2447] = { qty = 10, avg = 150 } }
	MerchantMasterLedgerDB.basisEvents[#MerchantMasterLedgerDB.basisEvents + 1] = { time = mockNow - 500, char = oldThe, cash = 250, order = 99999 }
	MerchantMasterLedgerDB.stats.chars[oldAldric] = true
	MerchantMasterLedgerDB.stats.chars[newAldric] = true
	MerchantMasterLedgerDB.stats.chars[oldThe] = true
	MerchantMasterLedgerDB.stats.chars[newThe] = true
	MerchantMasterLedgerDB.stats.firstLive[oldAldric] = mockNow - 90000
	MerchantMasterLedgerDB.stats.firstLive[newAldric] = mockNow - 1000
	MerchantMasterLedgerDB.stats.firstLive[oldThe] = mockNow - 80000
	MerchantMasterLedgerDB.stats.lastStanding[oldThe] = 5

	-- Host MerchantMasterDB.chars + anChar filter
	MerchantMasterDB.chars = MerchantMasterDB.chars or {}
	MerchantMasterDB.chars[oldAldric] = { name = "Aldric", economy = "Normal-Horde", bags = { ["Peacebloom"] = 99 }, bank = { ["Silverleaf"] = 4 }, mail = {}, knownSpells = { [2329] = true } }
	MerchantMasterDB.chars[newAldric] = { name = "Aldric Stone", firstName = "Aldric", economy = "Normal-Horde", bags = { ["Peacebloom"] = 5 }, bank = {}, mail = {}, knownSpells = {} }
	MerchantMasterDB.chars[oldThe] = { name = "The", economy = "Normal-Horde", bags = { ["Silverleaf"] = 40 }, bank = { ["Peacebloom"] = 6 }, mail = {} }
	MerchantMasterDB.chars[newThe] = { name = "The Endboss", firstName = "The", economy = "Normal-Horde", bags = { ["Silverleaf"] = 10 }, bank = {}, mail = {} }
	MerchantMasterDB.anChar = oldAldric

	local count, map = Store.MigrateForeverSurnames(MerchantMasterDB.chars, newAldric)
	check(count == 2 and map[oldAldric] == newAldric and map[oldThe] == newThe,
		"MigrateForeverSurnames migrates both Aldric -> Aldric Stone and The -> The Endboss, got count=" .. tostring(count))

	-- Live tables keep newKey authoritative data and remove oldKey
	check(MerchantMasterLedgerDB.wealth[oldAldric] == nil and MerchantMasterLedgerDB.wealth[oldThe] == nil,
		"Old single-word wealth keys removed")
	check(MerchantMasterLedgerDB.wealth[newAldric].cats.bags[1].qty == 5
		and MerchantMasterLedgerDB.wealth[newThe].cats.bags[1].qty == 10,
		"Live wealth data on full-name keys NOT overwritten by stale old data")
	check(MerchantMasterLedgerDB.inventory[oldAldric] == nil and MerchantMasterLedgerDB.inventory[oldThe] == nil
		and MerchantMasterLedgerDB.inventory[newAldric].bags[2447] == 5
		and MerchantMasterLedgerDB.inventory[newThe].bags[765] == 10,
		"Live inventory removes old keys and preserves authoritative full-name bags")

	-- Historical snaps preserve missing days without overwriting existing days
	check(MerchantMasterLedgerDB.snaps[oldAldric] == nil and MerchantMasterLedgerDB.snaps[oldThe] == nil,
		"Old single-word snaps removed")
	check(MerchantMasterLedgerDB.snaps[newAldric][day1] and MerchantMasterLedgerDB.snaps[newAldric][day1].gold == 1000
		and MerchantMasterLedgerDB.snaps[newAldric][day2].gold == 3500
		and MerchantMasterLedgerDB.snaps[newThe][day1] and MerchantMasterLedgerDB.snaps[newThe][day1].gold == 500,
		"Snaps backfill missing historical days without overwriting newer full-name day snaps")

	-- Packed day1 & unpacked day2 rows rewritten to full names
	local rowsDay1 = Store.UnpackDayString(MerchantMasterLedgerDB.days[day1].s)
	check(#rowsDay1 == 2 and rowsDay1[1].char == newAldric and rowsDay1[2].char == newThe,
		"Packed day1 rows rewritten to full Forever names")
	check(MerchantMasterLedgerDB.days[day2].r[1].char == newAldric and MerchantMasterLedgerDB.days[day2].r[2].char == newAldric,
		"Unpacked day2 rows rewritten to full Forever names")

	-- Roll, archivedRoll, loot, archivedLoot, dayStats, basis, basisEvents, stats merged cleanly
	check(MerchantMasterLedgerDB.roll[day1][oldAldric] == nil
		and MerchantMasterLedgerDB.roll[day1][newAldric][2447].sold == 12
		and MerchantMasterLedgerDB.roll[day1][newAldric][2447].gross == 1200,
		"Daily roll sums numeric fields into full-name key")
	check(MerchantMasterLedgerDB.archivedRoll[oldThe] == nil
		and MerchantMasterLedgerDB.archivedRoll[newThe][765].bought == 5,
		"archivedRoll migrated to full-name key")
	check(MerchantMasterLedgerDB.loot[day1][oldAldric] == nil
		and MerchantMasterLedgerDB.loot[day1][newAldric]["2447|Mob|Durotar"] == 10,
		"Daily loot counters summed into full-name key")
	check(MerchantMasterLedgerDB.archivedLoot[oldThe] == nil
		and MerchantMasterLedgerDB.archivedLoot[newThe]["765|Gather|Barrens"] == 12,
		"archivedLoot migrated to full-name key")
	check(MerchantMasterLedgerDB.dayStats[day1][oldAldric] == nil
		and MerchantMasterLedgerDB.dayStats[day1][newAldric].salesGross == 1200
		and MerchantMasterLedgerDB.dayStats[day1][newAldric].tiers.T1.writs == 3,
		"dayStats & nested tier stats summed into full-name key")
	check(MerchantMasterLedgerDB.basis[oldAldric] == nil
		and MerchantMasterLedgerDB.basis[newAldric][2447].qty == 20
		and MerchantMasterLedgerDB.basis[newAldric][2447].avg == 100,
		"Char-keyed basis merged with weighted average")
	check(MerchantMasterLedgerDB.basisEvents[#MerchantMasterLedgerDB.basisEvents].char == newThe,
		"basisEvents char rewritten to full-name key")
	check(MerchantMasterLedgerDB.stats.chars[oldAldric] == nil and MerchantMasterLedgerDB.stats.chars[oldThe] == nil
		and MerchantMasterLedgerDB.stats.firstLive[newAldric] == mockNow - 90000
		and MerchantMasterLedgerDB.stats.firstLive[oldAldric] == nil
		and MerchantMasterLedgerDB.stats.lastStanding[newThe] == 5
		and MerchantMasterLedgerDB.stats.lastStanding[oldThe] == nil,
		"stats.chars, firstLive (min timestamp), and lastStanding migrated cleanly")

	-- Host MerchantMasterDB.chars cleaned without copying stale bags; anChar rewritten
	check(MerchantMasterDB.chars[oldAldric] == nil and MerchantMasterDB.chars[oldThe] == nil,
		"Host MerchantMasterDB.chars stale single-word entries removed")
	check(MerchantMasterDB.chars[newAldric].bags["Peacebloom"] == 5
		and MerchantMasterDB.chars[newAldric].bank["Silverleaf"] == 4
		and MerchantMasterDB.chars[newAldric].knownSpells[2329] == true
		and MerchantMasterDB.chars[newThe].bags["Silverleaf"] == 10
		and MerchantMasterDB.chars[newThe].bank["Peacebloom"] == 6,
		"Host chars preserve live bags and merge non-bag fields (bank, knownSpells)")
	check(MerchantMasterDB.anChar == newAldric, "MerchantMasterDB.anChar rewritten to full-name key")

	-- Idempotent second run is a zero-op
	local count2 = Store.MigrateForeverSurnames(MerchantMasterDB.chars, newAldric)
	check(count2 == 0, "Second MigrateForeverSurnames run is an idempotent no-op")

	-- Cleanup
	for _, k in ipairs({ oldAldric, newAldric, oldThe, newThe }) do
		MerchantMasterLedgerDB.wealth[k] = nil
		MerchantMasterLedgerDB.inventory[k] = nil
		MerchantMasterLedgerDB.snaps[k] = nil
		MerchantMasterLedgerDB.archivedRoll[k] = nil
		MerchantMasterLedgerDB.archivedLoot[k] = nil
		MerchantMasterLedgerDB.basis[k] = nil
		MerchantMasterLedgerDB.stats.chars[k] = nil
		MerchantMasterLedgerDB.stats.firstLive[k] = nil
		MerchantMasterLedgerDB.stats.lastStanding[k] = nil
		MerchantMasterDB.chars[k] = nil
	end
	MerchantMasterLedgerDB.days[day1] = nil
	MerchantMasterLedgerDB.days[day2] = nil
	MerchantMasterLedgerDB.roll[day1] = nil
	MerchantMasterLedgerDB.loot[day1] = nil
	MerchantMasterLedgerDB.dayStats[day1] = nil
	table.remove(MerchantMasterLedgerDB.basisEvents)
	MerchantMasterDB.anChar = oldAnChar
	host.app.charKey = oldCharKey
end)

test("Ambiguity guard prevents merging 'The' when both 'The Endboss' and 'The Banker' exist + Model/Audit alias guard", function()
	local pfx = "Normal-Horde-Forever"
	local kOld = pfx .. "-The"
	local kAlt1 = pfx .. "-The Endboss"
	local kAlt2 = pfx .. "-The Banker"
	local kSoloOld = pfx .. "-Solo"
	local kSoloNew = pfx .. "-Solo Trader"
	local day = Store.DayKey()

	-- Ambiguous case: TWO two-word alts share first word "The" and old key has no GUID
	MerchantMasterLedgerDB.wealth[kOld] = { econ = "Normal-Horde", at = mockNow - 200, cats = { bags = {} } }
	MerchantMasterLedgerDB.wealth[kAlt1] = { econ = "Normal-Horde", at = mockNow, cats = { bags = {} } }
	MerchantMasterLedgerDB.wealth[kAlt2] = { econ = "Normal-Horde", at = mockNow, cats = { bags = {} } }
	MerchantMasterLedgerDB.snaps[kOld] = { [day] = { gold = 100, items = 0, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[kAlt1] = { [day] = { gold = 200, items = 0, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[kAlt2] = { [day] = { gold = 300, items = 0, listed = 0, econ = "Normal-Horde" } }

	local countAmb, mapAmb = Store.MigrateForeverSurnames(MerchantMasterDB.chars, kAlt1)
	check(countAmb == 0 and mapAmb[kOld] == nil and MerchantMasterLedgerDB.wealth[kOld] ~= nil,
		"Ambiguity guard refuses to merge 'The' when both 'The Endboss' and 'The Banker' exist without matching GUID")

	-- Canonical alias guard in Model.GetPortfolio & Inventory.Audit when unmigrated unambiguous pair exists
	MerchantMasterLedgerDB.wealth[kSoloOld] = { econ = "Normal-Horde", at = mockNow - 100, cats = { bags = { { id = 2447, name = "Peacebloom", qty = 10, unit = 100, total = 1000 } } } }
	MerchantMasterLedgerDB.wealth[kSoloNew] = { econ = "Normal-Horde", at = mockNow, cats = { bags = { { id = 2447, name = "Peacebloom", qty = 10, unit = 100, total = 1000 } } } }
	MerchantMasterLedgerDB.snaps[kSoloOld] = { [day] = { gold = 500, items = 1000, listed = 0, bags = 1000, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[kSoloNew] = { [day] = { gold = 500, items = 1000, listed = 0, bags = 1000, econ = "Normal-Horde" } }
	Model.Invalidate()
	local port = Model.Compute("portfolio", { econ = "Normal-Horde", period = "30d" })
	local soloCount = 0
	for _, cRow in ipairs(port.byChar or {}) do
		if cRow.char == kSoloOld or cRow.char == kSoloNew then
			soloCount = soloCount + 1
			check(cRow.char == kSoloNew, "Portfolio prefers two-word Forever key 'Solo Trader' over 'Solo'")
		end
	end
	check(soloCount == 1, "Portfolio collapses unambiguous single-word/two-word pair into 1 row, got " .. tostring(soloCount))

	local audit = analytics.Inventory.AnalyzePortfolio({ char = kSoloNew, econ = "Normal-Horde" })
	local sawAlias = false
	for _, fnd in ipairs(audit.issues or audit.findings or {}) do
		if fnd.code == "ALIAS" and tostring(fnd.reason):find("Solo", 1, true) then sawAlias = true; break end
	end
	check(sawAlias, "Inventory.AnalyzePortfolio flags [ALIAS] for unambiguous single-word 'Solo' vs 'Solo Trader'")

	-- Cleanup
	for _, k in ipairs({ kOld, kAlt1, kAlt2, kSoloOld, kSoloNew }) do
		MerchantMasterLedgerDB.wealth[k] = nil
		MerchantMasterLedgerDB.snaps[k] = nil
	end
	Model.Invalidate()
end)

test("Pushback #89 Regressions: DB.lots ghost-auction guard, GUID-matched PLAYER_LOGIN order, anChars/inTransitMail, and ALIAS GUID conflict", function()
	local pfx = "Normal-Horde-Forever"
	local oldAldric = pfx .. "-Aldric"
	local newAldric = pfx .. "-Aldric Stone"
	local oldSolo = pfx .. "-Ghost"
	local newSolo = pfx .. "-Ghost Rider"

	-- Fix #1: Existing DB.lots[newAldric] must NEVER be polluted by stale DB.lots[oldAldric] ghost auctions
	MerchantMasterLedgerDB.lots[oldAldric] = { [9999] = { { qty = 50, unit = 1000, postedAt = mockNow - 9000 } } }
	MerchantMasterLedgerDB.lots[newAldric] = { [2447] = { { qty = 3, unit = 500, postedAt = mockNow } } }
	-- Also test empty {} existing lots on newSolo (all auctions sold/expired -> must NOT resurrect oldSolo ghost lots!)
	MerchantMasterLedgerDB.lots[oldSolo] = { [8888] = { { qty = 20, unit = 500, postedAt = mockNow - 5000 } } }
	MerchantMasterLedgerDB.lots[newSolo] = {}

	-- Fix #3: MerchantMasterDB.anChars multi-select & DB.inTransitMail toChar/fromChar
	local origAnChars = MerchantMasterDB.anChars
	MerchantMasterDB.anChars = { [oldAldric] = true, [newAldric] = nil }
	MerchantMasterLedgerDB.inTransitMail = MerchantMasterLedgerDB.inTransitMail or {}
	local transitIdx = #MerchantMasterLedgerDB.inTransitMail + 1
	MerchantMasterLedgerDB.inTransitMail[transitIdx] = {
		toChar = oldAldric, fromChar = oldSolo, econ = "Normal-Horde",
		items = { [2447] = 4 }, money = 0, expiresAt = mockNow + 3600,
	}

	local c1 = Store.MigrateForeverSurnames(MerchantMasterDB.chars, newAldric)
	check(c1 == 2, "Fix #1/#3: migrated Aldric and Ghost cleanly, got " .. tostring(c1))
	check(MerchantMasterLedgerDB.lots[oldAldric] == nil
		and MerchantMasterLedgerDB.lots[newAldric][9999] == nil
		and MerchantMasterLedgerDB.lots[newAldric][2447] ~= nil
		and MerchantMasterLedgerDB.lots[newAldric][2447][1].qty == 3,
		"Fix #1: Existing DB.lots[newAldric] keeps live lot 2447 and does NOT resurrect stale ghost lot 9999")
	check(MerchantMasterLedgerDB.lots[oldSolo] == nil
		and MerchantMasterLedgerDB.lots[newSolo] ~= nil
		and MerchantMasterLedgerDB.lots[newSolo][8888] == nil,
		"Fix #1: Existing empty DB.lots[newSolo] does NOT resurrect stale ghost lot 8888")
	check(MerchantMasterDB.anChars[oldAldric] == nil and MerchantMasterDB.anChars[newAldric] == true,
		"Fix #3: MerchantMasterDB.anChars multi-select filter rewritten to full-name key")
	check(MerchantMasterLedgerDB.inTransitMail[transitIdx].toChar == newAldric
		and MerchantMasterLedgerDB.inTransitMail[transitIdx].fromChar == newSolo,
		"Fix #3: DB.inTransitMail toChar and fromChar rewritten to full-name keys")

	-- Fix #2: GUID-disambiguated migration on real app.resyncBags when TWO same-first-word alts exist!
	local oldThe = pfx .. "-The"
	local endboss = pfx .. "-The Endboss"
	local banker = pfx .. "-The Banker"
	local origCharKey, origChar = host.app.charKey, host.app.char
	local origUnitName, origReg, origConsts, origUnitGUID, origRealm = _G.UnitName, _G.RegionalUniqueNamesEnabled, _G.Constants, _G.UnitGUID, _G.GetRealmName
	MerchantMasterDB.chars = MerchantMasterDB.chars or {}
	MerchantMasterDB.chars[oldThe] = { name = "The", realm = "Forever", faction = "Horde", economy = "Normal-Horde", guid = "Player-16001-AAA", bags = { ["Peacebloom"] = 88 } }
	MerchantMasterDB.chars[endboss] = { name = "The Endboss", firstName = "The", realm = "Forever", faction = "Horde", economy = "Normal-Horde", guid = "Player-16001-AAA", bags = {} }
	MerchantMasterDB.chars[banker] = { name = "The Banker", firstName = "The", realm = "Forever", faction = "Horde", economy = "Normal-Horde", guid = "Player-16001-BBB", bags = {} }
	MerchantMasterLedgerDB.wealth[oldThe] = { econ = "Normal-Horde", at = mockNow - 300, cats = { bags = {} } }
	MerchantMasterLedgerDB.snaps[oldThe] = { ["2026-11-15"] = { gold = 777, items = 0, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[endboss] = { ["2026-11-19"] = { gold = 999, items = 0, listed = 0, econ = "Normal-Horde" } }
	MerchantMasterLedgerDB.snaps[banker] = { ["2026-11-19"] = { gold = 111, items = 0, listed = 0, econ = "Normal-Horde" } }
	host.app.charKey = endboss
	host.app.char = MerchantMasterDB.chars[endboss]
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
	_G.UnitName = function(u) if u == "player" then return "The", "Endboss" end end
	_G.UnitGUID = function(u) if u == "player" then return "Player-16001-AAA" end end
	_G.GetRealmName = function() return "Forever" end
	if host.app.resyncBags then
		host.app.resyncBags(false)
	else
		Store.MigrateForeverSurnames(MerchantMasterDB.chars, endboss)
	end
	check(MerchantMasterLedgerDB.wealth[oldThe] == nil and MerchantMasterLedgerDB.snaps[oldThe] == nil
		and MerchantMasterLedgerDB.snaps[endboss]["2026-11-15"]
		and MerchantMasterLedgerDB.snaps[endboss]["2026-11-15"].gold == 777
		and MerchantMasterLedgerDB.snaps[banker]["2026-11-15"] == nil,
		"Fix #2: GUID-matched activeKey migrates 'The' -> 'The Endboss' BEFORE host purge even when 'The Banker' exists")

	-- Fix #4: Inventory.AnalyzePortfolio [ALIAS] does NOT flag distinct GUIDs as a false positive
	local kDistOld = pfx .. "-Unique"
	local kDistNew = pfx .. "-Unique Smith"
	MerchantMasterDB.chars[kDistOld] = { name = "Unique", economy = "Normal-Horde", guid = "Player-16001-OLD" }
	MerchantMasterDB.chars[kDistNew] = { name = "Unique Smith", economy = "Normal-Horde", guid = "Player-16001-NEW" }
	MerchantMasterLedgerDB.wealth[kDistOld] = { econ = "Normal-Horde", at = mockNow, cats = { bags = {} } }
	MerchantMasterLedgerDB.wealth[kDistNew] = { econ = "Normal-Horde", at = mockNow, cats = { bags = {} } }
	local auditDist = analytics.Inventory.AnalyzePortfolio({ char = kDistNew, econ = "Normal-Horde" })
	local falseAlias = false
	for _, fnd in ipairs(auditDist.issues or {}) do
		if fnd.code == "ALIAS" and tostring(fnd.reason):find("Unique", 1, true) then falseAlias = true; break end
	end
	check(not falseAlias, "Fix #4: AnalyzePortfolio [ALIAS] does NOT emit false positive when GUIDs explicitly differ")

	-- Cleanup
	_G.UnitName, _G.RegionalUniqueNamesEnabled, _G.Constants, _G.UnitGUID, _G.GetRealmName = origUnitName, origReg, origConsts, origUnitGUID, origRealm
	host.app.charKey, host.app.char = origCharKey, origChar
	MerchantMasterDB.anChars = origAnChars
	table.remove(MerchantMasterLedgerDB.inTransitMail, transitIdx)
	for _, k in ipairs({ oldAldric, newAldric, oldSolo, newSolo, oldThe, endboss, banker, kDistOld, kDistNew }) do
		MerchantMasterLedgerDB.lots[k] = nil
		MerchantMasterLedgerDB.wealth[k] = nil
		MerchantMasterLedgerDB.snaps[k] = nil
		MerchantMasterLedgerDB.stats.chars[k] = nil
		if MerchantMasterDB.chars then MerchantMasterDB.chars[k] = nil end
	end
	Model.Invalidate()
end)

test("ns.GetPlayerFullName resolves WoW Forever surnames cleanly across modules", function()
	check(type(host.GetPlayerFullName) == "function", "ns.GetPlayerFullName is exposed early on addon namespace")
	local origUnitName = _G.UnitName
	local origReg = _G.RegionalUniqueNamesEnabled
	local origConsts = _G.Constants

	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
	_G.UnitName = function(u) if u == "player" then return "Aldric", "Stone" end end
	local full, first = host.GetPlayerFullName()
	check(full == "Aldric Stone" and first == "Aldric",
		"GetPlayerFullName joins Forever 2nd return surname: got " .. tostring(full) .. " / " .. tostring(first))

	-- Embedded space in 1st return without RegionalUniqueNamesEnabled
	_G.RegionalUniqueNamesEnabled = function() return false end
	_G.UnitName = function(u) if u == "player" then return "The Endboss", nil end end
	local full2, first2 = host.GetPlayerFullName()
	check(full2 == "The Endboss" and first2 == "The",
		"GetPlayerFullName splits embedded space cleanly: got " .. tostring(full2) .. " / " .. tostring(first2))

	-- Classic single-word name
	_G.UnitName = function(u) if u == "player" then return "Thrall", "Forever" end end
	local full3, first3 = host.GetPlayerFullName()
	check(full3 == "Thrall" and first3 == "Thrall",
		"GetPlayerFullName ignores realm-style 2nd return when RegionalUniqueNamesEnabled is false")

	-- Verify Professor_Engine.GetCharKey uses full Forever surname
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.UnitName = function(u) if u == "player" then return "Aldric", "Stone" end end
	if host.MP and host.MP.GetCharKey then
		local pk = host.MP.GetCharKey()
		check(pk:find("^Aldric Stone%-") ~= nil, "Professor_Engine MP.GetCharKey uses full Forever name, got " .. tostring(pk))
	end

	_G.UnitName = origUnitName
	_G.RegionalUniqueNamesEnabled = origReg
	_G.Constants = origConsts
end)

_G._MM_TEST_HOST = host
print(string.format("Analytics suite: %d cases, %d assertions, %d failures", cases, assertions, #failures))
if #failures > 0 then error(table.concat(failures, "\n\n"), 0) end

---------------------------------------------------------------------------------------------------
