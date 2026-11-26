-- Standalone Independence Gate Suite (Pure Lua 5.1, zero host_fixture dependency)
-- Verifies MerchantMaster runs strictly standalone with enableLegacyPriceAddons == false
-- and makes ZERO reads/calls on any third-party addon global across load, login, 3s timer,
-- pricing, ownership, accounting, profession scanning, and Crate/Writ Shift-Click routing.

local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
local addonDir = testsDir .. "../"
local COUNTS = dofile(testsDir .. "catalog_counts.lua")

local assertions = 0
local function check(cond, msg)
	assertions = assertions + 1
	if not cond then
		error("STANDALONE GATE FAIL [" .. assertions .. "]: " .. tostring(msg), 2)
	end
end

---------------------------------------------------------------------------------------------------
-- 1. Verify MerchantMaster.toc has COUNTS.tocFiles Lua entries and ZERO third-party OptionalDeps
---------------------------------------------------------------------------------------------------
do
	local fh = assert(io.open(addonDir .. "MerchantMaster.toc", "rb"))
	local raw = fh:read("*a")
	fh:close()
	local luaCount = 0
	for line in raw:gmatch("[^\r\n]+") do
		check(not line:match("^##%s*OptionalDeps:"), "MerchantMaster.toc must not declare OptionalDeps: " .. line)
		local clean = line:match("^%s*([^#%s].-)%s*$")
		if clean and clean:match("%.lua$") then
			luaCount = luaCount + 1
		end
	end
	check(luaCount == COUNTS.tocFiles,
		"MerchantMaster.toc must list " .. COUNTS.tocFiles .. " Lua files, got " .. luaCount)
	check(not raw:find("TradeSkillMaster", 1, true), "MerchantMaster.toc must not reference TradeSkillMaster")
	check(not raw:find("Auctionator", 1, true), "MerchantMaster.toc must not reference Auctionator")
	check(not raw:find("Auc-Advanced", 1, true), "MerchantMaster.toc must not reference Auc-Advanced")
end

---------------------------------------------------------------------------------------------------
-- 2. Strict Third-Party Global Spy Proxies (installed BEFORE addon load, ADDON_LOADED, PLAYER_LOGIN)
---------------------------------------------------------------------------------------------------
local thirdPartyHits = {}
local function makeSpyGlobal(name)
	return setmetatable({}, {
		__index = function(_, k)
			thirdPartyHits[#thirdPartyHits + 1] = name .. ".__index[" .. tostring(k) .. "]"
			return nil
		end,
		__newindex = function(_, k, v)
			thirdPartyHits[#thirdPartyHits + 1] = name .. ".__newindex[" .. tostring(k) .. "=" .. tostring(v) .. "]"
		end,
		__call = function()
			thirdPartyHits[#thirdPartyHits + 1] = name .. ".__call()"
			return nil
		end,
	})
end

_G.TSM_API = makeSpyGlobal("TSM_API")
_G.TradeSkillMasterDB = makeSpyGlobal("TradeSkillMasterDB")
_G.Auctionator = makeSpyGlobal("Auctionator")
_G.AucAdvanced = makeSpyGlobal("AucAdvanced")
_G.Syndicator = makeSpyGlobal("Syndicator")
_G.OneForAllDB = makeSpyGlobal("OneForAllDB")
_G.OneForAllCharDB = makeSpyGlobal("OneForAllCharDB")

local function assertZeroThirdParty(stage)
	if #thirdPartyHits > 0 then
		error(string.format("STANDALONE GATE FAIL [%s]: %d third-party global access(es): %s",
			stage, #thirdPartyHits, table.concat(thirdPartyHits, ", ")), 2)
	end
	check(#thirdPartyHits == 0, "Zero third-party global accesses at " .. stage)
end

---------------------------------------------------------------------------------------------------
-- 3. Minimal Standalone WoW 16001 Client Mock (NO enableLegacyPriceAddons override)
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
_G.issecretvalue = function() return false end

local mockTime = 1794360000
local mockClock = 1000.0
_G.time = function() return mockTime end
_G.GetTime = function() return mockClock end
_G.date = os.date
_G.GetLocale = function() return "enUS" end
_G.SecondsToTime = function(s) return tostring(s) .. "s" end
local shiftDown = false
_G.IsShiftKeyDown = function() return shiftDown end
_G.PlaySound = function() end
_G.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2 }
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.ChatEdit_InsertLink = function() return false end
_G.HandleModifiedItemClick = function() return false end
_G.GetMoney = function() return 500000 end
_G.IsUsingLegacyAuctionClient = function() return false end

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

local function makeWidget(frameType, name, parent)
	local w = {
		_type = frameType or "Frame",
		_name = name,
		_parent = parent,
		_shown = true,
		_scripts = {},
		_events = {},
		_regions = {},
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
	function w:GetRegions() return unpack(self._regions or {}) end
	function w:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
	function w:Hide() self._shown = false; if self._scripts.OnHide then self._scripts.OnHide(self) end end
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
		for i, pt in ipairs(self._points) do
			if pt[1] == entry[1] then self._points[i] = entry; return end
		end
		self._points[#self._points + 1] = entry
	end
	function w:SetAllPoints(rel)
		self._points = { { "TOPLEFT", rel or self._parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or self._parent, "BOTTOMRIGHT", 0, 0 } }
	end
	function w:ClearAllPoints() self._points = {} end
	function w:GetNumPoints() return #(self._points or {}) end
	function w:GetPoint(i)
		local p = (self._points or {})[i or 1]
		if not p then return end
		return p[1], p[2] or self._parent, p[3] or p[1], p[4] or 0, p[5] or 0
	end
	function w:SetMovable(...) end
	function w:SetClampedToScreen(...) end
	function w:EnableMouse(...) end
	function w:EnableKeyboard(...) end
	function w:SetPropagateKeyboardInput(...) end
	function w:IsMouseOver() return false end
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
		self._scripts[ev] = function(...) if old then old(...) end; fn(...) end
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
	function w:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a or 1 } end
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
	function w:SetTexture(tex, wh, wv) self._texture, self._wrapH, self._wrapV = tex, wh, wv end
	function w:GetTexture() return self._texture end
	function w:SetColorTexture(r, g, b, a) self._colorTexture = { r, g, b, a } end
	function w:SetTexCoord(...) end
	function w:SetAtlas(...) end
	function w:SetBlendMode(...) end
	function w:SetHorizTile(...) end
	function w:SetVertTile(...) end
	function w:SetVertexColor(r, g, b, a) self._vertexColor = { r, g, b, a } end
	function w:GetVertexColor() return 1, 1, 1, 1 end
	function w:SetRotation(r) self._rotation = r end
	function w:SetDesaturated(...) end
	function w:SetDrawLayer(l, s) self._layer, self._subLevel = l, s end
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
		return {
			CreateAnimation = function()
				return { SetOrder = function() end, SetDuration = function() end, SetFromAlpha = function() end, SetToAlpha = function() end, SetStartDelay = function() end }
			end,
			SetToFinalAlpha = function() end,
			Play = function() end,
			Stop = function() end,
		}
	end
	function w:Click(btn) if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end end
	function w:CreateTexture(n, layer, _, sub)
		local t = makeWidget("Texture", n, self)
		t._layer, t._subLevel = layer, sub
		self._regions[#self._regions + 1] = t
		return t
	end
	function w:CreateLine(n, layer)
		local l = self:CreateTexture(n, layer)
		function l:SetThickness() end
		function l:SetStartPoint() end
		function l:SetEndPoint() end
		return l
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
		function w:NumLines() return #(self._lines or {}) end
	end
	return w
end

local createdFrames = {}
_G.UIParent = makeWidget("Frame", "UIParent", nil)
function _G.UIParent:GetWidth() return 1920 end
function _G.UIParent:GetHeight() return 1080 end
_G.Minimap = makeWidget("Frame", "Minimap", _G.UIParent)
function _G.Minimap:GetWidth() return 140 end
function _G.Minimap:GetHeight() return 140 end
_G.GameTooltip = makeWidget("GameTooltip", "GameTooltip", _G.UIParent)
_G.GameTooltip_Hide = function() _G.GameTooltip:Hide() end
_G.GetCursorPosition = function() return 1100, 350 end

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
				for i = 1, math.min(#items, 10) do
					local rw = makeWidget("Button", nil, self)
					self._view._initFn(rw, items[i])
					self._frames[#self._frames + 1] = rw
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
	function v:SetElementInitializer(_, fn) self._initFn = fn end
	function v:SetPadding(...) end
	return v
end
_G.ScrollUtil = { InitScrollBoxListWithScrollBar = function(sb, bar, view) sb._view = view; sb._bar = bar end }
_G.CreateDataProvider = function(list)
	local items = list or {}
	return { GetCollection = function() return items end, Enumerate = function() return ipairs(items) end }
end

local scheduledTimers = {}
_G.C_Timer = {
	After = function(delay, fn)
		if type(fn) ~= "function" then return end
		scheduledTimers[#scheduledTimers + 1] = { at = mockClock + (tonumber(delay) or 0), fn = fn }
	end,
	NewTimer = function(delay, fn)
		local cancelled = false
		if type(fn) == "function" then
			scheduledTimers[#scheduledTimers + 1] = {
				at = mockClock + (tonumber(delay) or 0),
				fn = function() if not cancelled then fn() end end,
			}
		end
		return { Cancel = function() cancelled = true end }
	end,
}
local function runTimers(advanceSec)
	mockClock = mockClock + (advanceSec or 0)
	mockTime = mockTime + (advanceSec or 0)
	local guard = 0
	while guard < 500 do
		local idx
		for i, t in ipairs(scheduledTimers) do
			if t.at <= mockClock then idx = i; break end
		end
		if not idx then break end
		local t = table.remove(scheduledTimers, idx)
		guard = guard + 1
		t.fn()
	end
end

_G.Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		return { _frame = frame, _name = name, GetID = function() return 99 end }
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}

_G.Enum = {
	GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 },
	AuctionHouseSortOrder = { Price = 0, Buyout = 1, Bid = 2 },
	ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
}
_G.C_GameRules = { IsGameRuleActive = function() return false end }
_G.UnitFactionGroup = function() return "Horde" end
_G.GetRealmName = function() return "Forever" end
_G.UnitName = function() return "StandaloneHero" end
_G.GetCVar = function(k) if k == "Portal" then return "EU" end return "" end
_G.GetProfessions = function() return 1, 2, nil, nil, nil, nil end
_G.GetProfessionInfo = function(idx)
	if idx == 1 then return "Alchemy", 136240, 200, 300, 0, 0, 171 end
	if idx == 2 then return "Herbalism", 136065, 225, 300, 0, 0, 182 end
end
_G.GetNumSkillLines = function() return 2 end
_G.GetSkillLineInfo = function(i)
	if i == 1 then return "Alchemy", false, false, 200, 0, 0, 300 end
	if i == 2 then return "Herbalism", false, false, 225, 0, 0, 300 end
end
_G.C_Reputation = {
	GetFactionDataByID = function(fid)
		if fid == 2587 then
			return { factionID = fid, name = "Durotar Supply and Logistics", reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4500 }
		end
	end,
}
_G.C_CurrencyInfo = {
	GetCurrencyInfo = function(cid) if cid == 3402 then return { quantity = 50, iconFileID = 237281 } end end,
}
_G.C_Item = {
	GetItemInfo = function() return nil end,
	GetItemIconByID = function() return 134400 end,
	RequestLoadItemDataByID = function() end,
	DoesItemExist = function() return true end,
}
_G.ItemLocation = {
	CreateFromBagAndSlot = function(b, s) return { bagID = b, slotIndex = s } end,
}
_G.NUM_BAG_SLOTS = 4
_G.C_Container = {
	GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end,
	GetContainerNumFreeSlots = function(b) return b == 0 and 12 or 0, 0 end,
	GetContainerItemInfo = function(b, s)
		if b == 0 and s == 1 then
			return { itemID = 2447, stackCount = 20, iconFileID = 134187, hyperlink = "|cffffffff|Hitem:2447::::::::20:::::|h[Peacebloom]|h|r" }
		end
	end,
}
_G.C_TooltipInfo = { GetBagItem = function() return nil end }
_G.C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy", skillLevel = 200, maxSkillLevel = 300 } end,
	GetAllRecipeIDs = function() return {} end,
	GetRecipeInfo = function() return nil end,
}
_G.AuctionHouseFrame = makeWidget("Frame", "AuctionHouseFrame", _G.UIParent)
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
	GetBrowseResults = function() return {} end,
	HasFullBrowseResults = function() return true end,
	MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0 } end,
	GetItemKeyInfo = function(k) return { itemName = "Item", isCommodity = true } end,
	HasSearchResults = function() return false end,
	IsSellItemValid = function() return true end,
	GetItemCommodityStatus = function() return _G.Enum.ItemCommodityStatus.Commodity end,
	GetAvailablePostCount = function() return 20 end,
	CalculateItemDeposit = function() return 100 end,
	CalculateCommodityDeposit = function() return 100 end,
	PostItem = function() return false end,
	PostCommodity = function() return false end,
	QueryOwnedAuctions = function() end,
	GetNumOwnedAuctions = function() return 0 end,
	GetOwnedAuctionInfo = function() return nil end,
	CancelAuction = function() end,
	CanCancelAuction = function() return true end,
	GetCancelCost = function() return 0 end,
}
_G.MailFrame = makeWidget("Frame", "MailFrame", _G.UIParent)
_G.MailFrame:Hide()
_G.TakeInboxItem = function() end
_G.TakeInboxMoney = function() end
_G.AutoLootMailItem = function() end
_G.CheckInbox = function() end
_G.GetInboxNumItems = function() return 0, 0 end
_G.GetInboxHeaderInfo = function() return nil end
_G.GetInboxInvoiceInfo = function() return nil end
_G.BuyTrainerService = function() end
_G.GetTrainerServiceInfo = function() return nil end
_G.GetTrainerServiceCost = function() return 0 end
_G.DepositGuildBankMoney = function() end
_G.WithdrawGuildBankMoney = function() end
_G.GetGuildInfo = function() return "StandaloneGuild" end

local appHelperRawCalls = 0
_G.TSM_APPHELPER_LOAD_DATA = function() appHelperRawCalls = appHelperRawCalls + 1 end

---------------------------------------------------------------------------------------------------
-- 4. Load Addon Directly via fixture_toc.lua + Verify Pre-ADDON_LOADED Buffer & Discard
---------------------------------------------------------------------------------------------------
local ns = {}
local fixture = dofile(testsDir .. "fixture_toc.lua")
local analytics = fixture.Load(addonDir, "MerchantMaster", ns, check)
check(analytics ~= nil and analytics == _G.MerchantMasterAnalytics, "Analytics namespace loaded")
assertZeroThirdParty("after_file_load")

-- Verify TSM_APPHELPER_LOAD_DATA is NOT hooked by MerchantMaster (pure standalone)
_G.TSM_APPHELPER_LOAD_DATA("AUCTIONDB_MARKET_DATA", "Normal-Horde",
	[[return {downloadTime=1794359000,fields={"itemString","minBuyout","marketValue","numAuctions"},data={{"i:2447",50,60,12}}}]])
check(appHelperRawCalls == 1, "Pre-ADDON_LOADED TSM_APPHELPER_LOAD_DATA is untouched by MerchantMaster")
check(ns.pendingTSMAppData == nil, "ns.pendingTSMAppData removed in pure standalone mode")
check(ns.UseLegacyPriceAddons == nil, "ns.UseLegacyPriceAddons removed in pure standalone mode")
check(ns.QueryTSM == nil and ns.QueryAuctionator == nil and ns.QueryAuctioneer == nil,
	"Legacy third-party price query helpers removed")
check(ns.GetAuctionatorMarketStats == nil, "Legacy GetAuctionatorMarketStats removed")

local function fireAllEventFrames(event, ...)
	for _, f in ipairs(createdFrames) do
		if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then
			f._scripts.OnEvent(f, event, ...)
		end
	end
end

-- Seed legacy SavedVariables values BEFORE ADDON_LOADED to verify automatic migration!
_G.MerchantMasterDB = { priceSource = "tsm_min", economy = "tsm_alt" }
fireAllEventFrames("ADDON_LOADED", "MerchantMaster")
check(_G.MerchantMasterDB ~= nil and _G.MerchantMasterDB.priceSource == "auto",
	"ADDON_LOADED normalizes legacy priceSource='tsm_min' -> 'auto'")
check(_G.MerchantMasterDB.economy == "auto",
	"ADDON_LOADED normalizes legacy economy='tsm_alt' -> 'auto'")
check(ns.NormalizePriceSourceKey("auctionator") == "auto" and ns.NormalizePriceSourceKey("auctioneer") == "auto"
	and ns.NormalizePriceSourceKey("tsm_market") == "auto",
	"NormalizePriceSourceKey migrates all legacy third-party priceSource keys to 'auto'")
check(ns.NormalizeEconomyKey("region") == "auto" and ns.NormalizeEconomyKey("tsm_alt") == "auto",
	"NormalizeEconomyKey migrates legacy 'region'/'tsm_alt' economy keys to 'auto'")
check(ns.tsmRawAppHelper == nil and ns.tsmParsedEconomies == nil and ns.tsmAppDataEpoch == nil,
	"All TSM AppHelper ingestion tables removed")
assertZeroThirdParty("after_ADDON_LOADED")

-- Fire PLAYER_LOGIN + advance 5 seconds so any login timers execute cleanly without third-party reads
fireAllEventFrames("PLAYER_LOGIN")
runTimers(5)
assertZeroThirdParty("after_PLAYER_LOGIN_and_5s_timer")

---------------------------------------------------------------------------------------------------
-- 5. Pricing, Ownership, Analytics, Professor_Engine, Built-in AH Buyer & Shift-Click Gates
---------------------------------------------------------------------------------------------------
local app = ns.app
local Store = analytics.Store
local AUI = analytics.UI

-- Built-in AH Buyer is the sole native path (legacy toggle functions & UI controls removed)
check(app.isBuiltInAHBuyerEnabled == nil and app.setBuiltInAHBuyer == nil,
	"Legacy AH Buyer toggle helpers removed")
check(app.multiSearchAuctionator == nil and app.sendShoppingRowsToAuctionator == nil,
	"Legacy Auctionator export helpers removed")
check(app.ui.optLegacyPriceCheck == nil and app.ui.optBuiltInBuyerCheck == nil,
	"Legacy Options checkboxes removed")
assertZeroThirdParty("after_standalone_api_checks")

-- Pricing queries (with zero TSM_API reads)
local p1 = ns.GetItemMarketPrice(2447)
local p2 = ns.GetReagentUnitCost(2447)
local p3 = ns.GetFallbackMarketPrice(2447)
local ds = ns.GetDailySold(2447)
local nl = ns.GetNumListed(2447)
local _ = p1, p2, p3, ds, nl
ns.BuildRecipeRows({ profFilter = "alchemy" })
ns.BuildCrateRows({ crateMode = "cheapest" })
ns.BuildWritRows({ profFilter = "all" })
assertZeroThirdParty("after_pricing_and_builders")

-- Ownership lookups (with zero TSM_API / Syndicator reads)
check(type(app.getItemOwnershipBreakdown) == "function", "app.getItemOwnershipBreakdown exists")
local bd = app.getItemOwnershipBreakdown(2447, "Peacebloom")
check(type(bd) == "table", "getItemOwnershipBreakdown works without Syndicator/TSM")
check(_G.MerchantMasterAPI.GetSyndicatorExtraByID == nil, "Legacy GetSyndicatorExtraByID removed from API")
assertZeroThirdParty("after_ownership")

-- Analytics Store & UI gates (TSM importer/reconciler removed; passive row.tsm compatibility tested in store/ui suites)
check(Store.SeedTSM == nil and Store.ReconcileTSMSales == nil,
	"Legacy Store.SeedTSM and Store.ReconcileTSMSales removed")
local charKey = app.charKey or "Normal-Horde-Forever-StandaloneHero"
local knownId = Store.ResolveItemIDByName(charKey, "Peacebloom")
check(knownId == 2447, "Store.ResolveItemIDByName resolves native catalog itemID (got " .. tostring(knownId) .. ")")
local missingId = Store.ResolveItemIDByName(charKey, "NonExistentStandaloneItemXYZ")
check(missingId == 0 or missingId == nil, "Store.ResolveItemIDByName returns 0/nil without reading TradeSkillMasterDB (got " .. tostring(missingId) .. ")")
check(AUI and AUI.seedTsmBtn == nil, "Analytics UI.seedTsmBtn removed in pure standalone mode")
assertZeroThirdParty("after_analytics_gates")

-- Professor_Engine (with zero Syndicator / OneForAllDB / OneForAllCharDB reads)
if ns.MP then
	if ns.MP.ScanPlayerProfessions then ns.MP.ScanPlayerProfessions() end
	local sampleProfRec = ns.MP.RECIPES and ns.MP.RECIPES.alchemy and ns.MP.RECIPES.alchemy[1]
	if sampleProfRec and ns.MP.GetEffectiveRecipeReqs then
		ns.MP.GetEffectiveRecipeReqs("alchemy", sampleProfRec)
	end
	if ns.MP.BuildPath then
		ns.MP.BuildPath("alchemy", 1, 75, {})
	end
end
assertZeroThirdParty("after_professor_engine")

-- Crate & Writ Shift-Click routing -> routes to Built-in OrderFlow / CartBuyer without touching _G.Auctionator
do
	local openCalls, orderFlowCalls = {}, {}
	local origOpenCart = app.openCartBuyer
	local origEnterFlow = app.enterOrderFlowMode
	app.openCartBuyer = function(rows, title)
		openCalls[#openCalls + 1] = { rows = rows, title = title }
		return true
	end
	app.enterOrderFlowMode = function(stage)
		orderFlowCalls[#orderFlowCalls + 1] = stage
		return true
	end
	local sent = app.sendShoppingRowsToBuyer({ { itemID = 765, name = "Silverleaf", qty = 20, count = 20, source = "AH", ahUnitPrice = 15 } }, "Standalone Cart")
	check(sent == true and (#orderFlowCalls == 1 or #openCalls == 1),
		"sendShoppingRowsToBuyer routes directly to built-in OrderFlow/CartBuyer")

	app.multiSearchBuyer({ { searchString = "Silverleaf", quantity = 20, itemID = 765 } }, "Standalone Multi")
	check(#openCalls >= 1, "multiSearchBuyer delegates to built-in CartBuyer natively")

	-- Exercise real Shift-Click on rendered Waylaid Crate and Craftsman's Writ rows
	app.panel:Show()
	shiftDown = true
	app.setTab("crates")
	app.refresh()
	local crateClicked = false
	if app.ui and app.ui.cratesTable and app.ui.cratesTable.scrollBox then
		for _, rw in ipairs(app.ui.cratesTable.scrollBox._frames or {}) do
			if rw.data and rw._scripts and rw._scripts.OnClick then
				local before = #orderFlowCalls + #openCalls
				rw:Click("LeftButton")
				if (#orderFlowCalls + #openCalls) > before then crateClicked = true; break end
			end
		end
	end
	check(crateClicked, "Waylaid Crate Shift-Click routes to Built-in OrderFlow/CartBuyer without Auctionator")

	app.setTab("writs")
	app.refresh()
	local writClicked = false
	if app.ui and app.ui.writsTable and app.ui.writsTable.scrollBox then
		for _, rw in ipairs(app.ui.writsTable.scrollBox._frames or {}) do
			if rw.data and rw._scripts and rw._scripts.OnClick then
				local before = #orderFlowCalls + #openCalls
				rw:Click("LeftButton")
				if (#orderFlowCalls + #openCalls) > before then writClicked = true; break end
			end
		end
	end
	check(writClicked, "Craftsman's Writ Shift-Click routes to Built-in OrderFlow/CartBuyer without Auctionator")
	shiftDown = false
	app.openCartBuyer = origOpenCart
	app.enterOrderFlowMode = origEnterFlow
end
assertZeroThirdParty("after_crate_and_writ_shift_click")

---------------------------------------------------------------------------------------------------
-- 6. Unlisted Blizzard Snapshot Handling (qty == 0 -> minBuyout returns nil, falls back to MV/hist)
---------------------------------------------------------------------------------------------------
do
	check(type(_G.MERCHANTMASTER_LOAD_SNAPSHOTS) == "function", "_G.MERCHANTMASTER_LOAD_SNAPSHOTS is registered")
	local b32 = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
	local function enc32(num)
		num = math.floor(tonumber(num) or 0)
		if num <= 0 then return "0" end
		local d = {}
		while num > 0 do
			local rem = num % 32
			d[#d + 1] = b32:sub(rem + 1, rem + 1)
			num = math.floor(num / 32)
		end
		local out = {}
		for i = #d, 1, -1 do out[#out + 1] = d[i] end
		return table.concat(out)
	end

	local econ = ns.CurrentEconomyInfo().effectiveKey
	local unlistedID = 13468      -- Black Lotus (unlisted, has marketValue + historical)
	local unlistedHistID = 13465  -- Mountain Silversage (unlisted, marketValue=0, historical=42000)
	local listedID = 13463        -- Dreamfoil (listed, qty=35)
	local snapTs = mockTime - 600
	-- Feed unlisted items with qty=0 (even if a stale minBuyout field were non-zero, qty==0 must suppress minBuyout!)
	local lineUnlisted = string.format("%d:%s,%s,%s,%s,%s,%s",
		unlistedID, enc32(1234), enc32(50000), enc32(42000), enc32(0), enc32(snapTs), enc32(48000))
	local lineUnlistedHist = string.format("%d:%s,%s,%s,%s,%s,%s",
		unlistedHistID, enc32(999), enc32(0), enc32(42000), enc32(0), enc32(snapTs), enc32(0))
	local lineListed = string.format("%d:%s,%s,%s,%s,%s,%s",
		listedID, enc32(14000), enc32(15000), enc32(14500), enc32(35), enc32(snapTs), enc32(14800))

	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("META", econ,
		string.format([[return {v=1,updatedAt=%d,source="blizzard",windowDays=30,itemCount=3,heatmapCount=0}]], snapTs))
	_G.MERCHANTMASTER_LOAD_SNAPSHOTS("LATEST", econ, lineUnlisted .. ";" .. lineUnlistedHist .. ";" .. lineListed)
	if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end

	local minUnlisted, recUnlisted = ns.QueryLocalSnapshot(unlistedID, econ, "minBuyout")
	check(minUnlisted == nil, "Unlisted (qty==0) QueryLocalSnapshot('minBuyout') must return nil, got " .. tostring(minUnlisted))
	check(recUnlisted ~= nil and recUnlisted.qty == 0 and recUnlisted.minBuyout == nil,
		"Unlisted snapshot record keeps qty==0 and minBuyout==nil")
	check(recUnlisted.marketValue == 50000 and recUnlisted.historical == 42000,
		"Unlisted snapshot record preserves marketValue=50000 and historical=42000")

	local priceMV = ns.QueryLocalSnapshot(unlistedID, econ)
	check(priceMV == 50000, "Unlisted (qty==0) QueryLocalSnapshot falls back to marketValue=50000, got " .. tostring(priceMV))

	local minHistOnly = ns.QueryLocalSnapshot(unlistedHistID, econ, "minBuyout")
	local priceHistOnly = ns.QueryLocalSnapshot(unlistedHistID, econ)
	check(minHistOnly == nil and priceHistOnly == 42000,
		"Unlisted (qty==0, marketValue=0) falls back to historical=42000, got " .. tostring(priceHistOnly))

	if ns.Pricing and ns.Pricing.GetItemSnapshotLatest then
		local pMin = ns.Pricing.GetItemSnapshotLatest(unlistedID, econ, "minBuyout")
		local pRec, pVal = ns.Pricing.GetItemSnapshotLatest(unlistedID, econ)
		check(pMin == nil, "Pricing.GetItemSnapshotLatest('minBuyout') returns nil for unlisted qty==0")
		check(pRec ~= nil and pVal == 50000 and pRec.historical == 42000,
			"Pricing.GetItemSnapshotLatest returns fallback marketValue & historical for unlisted qty==0")
	end

	-- General GetItemMarketPrice fallback on unlisted item uses marketValue/historical (not 0 or stale minBuyout)
	local fallbackPrice = ns.GetItemMarketPrice(unlistedID)
	check(fallbackPrice == 50000 or fallbackPrice == 48000 or fallbackPrice == 42000,
		"GetItemMarketPrice on unlisted (qty==0) item falls back to marketValue/recent/historical, got " .. tostring(fallbackPrice))

	-- Listed item (qty > 0) still returns live minBuyout
	local minListed = ns.QueryLocalSnapshot(listedID, econ, "minBuyout")
	check(minListed == 14000, "Listed (qty>0) snapshot still returns minBuyout=14000, got " .. tostring(minListed))
end

---------------------------------------------------------------------------------------------------
-- 7. All Items Overview, Filtering, Item Quick Look & Craft Update (Zero Third-Party Access)
---------------------------------------------------------------------------------------------------
do
	local app = ns.app
	app.panel:Show()
	app.setTab("all_items")
	app.refresh()
	runTimers(1)
	check(app.ui and app.ui.allItemsView and app.ui.allItemsView:IsShown(),
		"All Items view renders in strict standalone mode")

	local rows = ns.AllItems and ns.AllItems.GetRows and ns.AllItems.GetRows() or {}
	local ssRow
	for _, r in ipairs(rows) do
		if r.itemID == 7912 then ssRow = r; break end
	end
	check(ssRow ~= nil and ssRow.name == "Solid Stone" and ssRow.prof == "mining",
		"All Items includes Solid Stone (7912) under Mining in standalone mode")

	local view = app.ui.allItemsView
	for _, pillKey in ipairs({ "mining", "herbalism", "skinning", "all" }) do
		check(view.profBtns and view.profBtns[pillKey] ~= nil, "Standalone All Items pill exists: " .. pillKey)
		view.profBtns[pillKey]:Click("LeftButton")
	end
	view.resetButton:Click("LeftButton")
	runTimers(1)

	app.openQuickLook("item", ssRow, { toggle = false })
	local hud = app.superListProvider and app.superListProvider.GetQuickLookFrame and app.superListProvider.GetQuickLookFrame()
	check(hud ~= nil and hud:IsShown() and hud.kind == "item",
		"Item Quick Look opens for Solid Stone in standalone mode")
	if app.superListProvider and app.superListProvider.CloseQuickLook then
		app.superListProvider.CloseQuickLook()
	end

	app.invalidateRecipeStats("ownership", { ids = { [7912] = true }, names = { ["Solid Stone"] = true } })
	runTimers(1)
	app.refresh()
end
assertZeroThirdParty("after_all_items")
assertZeroThirdParty("final_complete")

print(string.format("STANDALONE_GATES: PASS (%d assertions, 0 third-party accesses)", assertions))
