-- Realistic WoW 16001 Performance & Event-Storm Benchmark for MerchantMaster
local addonDir = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local snapshotsDir = addonDir .. "../MerchantMaster_Snapshots/"

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

local simNow = 1000.0
local wallEpoch = 1794360000
_G.time = function() return wallEpoch + math.floor(simNow - 1000.0) end
_G.GetTime = function() return simNow end
_G.GetLocale = function() return "enUS" end
_G.SecondsToTime = function(s) return tostring(s) .. "s" end
_G.IsShiftKeyDown = function() return false end
_G.PlaySound = function() end
_G.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2 }
_G.UISpecialFrames = {}
_G.SlashCmdList = {}

local counters = {
	tsmCustomPrice = 0,
	tsmToItemString = 0,
	detectGameRule = 0,
	setBagItem = 0,
	getBagSlot = 0,
	requestLoadItem = 0,
	getRecipeInfo = 0,
	tooltipGetItemByID = 0,
	appRefresh = 0,
	uiRefresh = 0,
}

local function resetCounters()
	for k in pairs(counters) do counters[k] = 0 end
end

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

local timers = {}
_G.C_Timer = {
	After = function(delay, fn)
		timers[#timers + 1] = { due = simNow + (tonumber(delay) or 0), fn = fn, cancelled = false }
	end,
	NewTimer = function(delay, fn)
		local t = { due = simNow + (tonumber(delay) or 0), fn = fn, cancelled = false }
		function t:Cancel() self.cancelled = true end
		timers[#timers + 1] = t
		return t
	end,
}

local function stepTimersTo(targetTime)
	while true do
		local nextIdx, bestDue = nil, nil
		for i, t in ipairs(timers) do
			if not t.cancelled and t.due <= targetTime then
				if not bestDue or t.due < bestDue then
					bestDue, nextIdx = t.due, i
				end
			end
		end
		if not nextIdx then break end
		local job = table.remove(timers, nextIdx)
		simNow = job.due
		if not job.cancelled then job.fn() end
	end
	simNow = targetTime
end

local createdFrames = {}
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
		_regions = {},
	}
	function w:GetName() return self._name end
	function w:GetObjectType() return self._type end
	function w:GetParent() return self._parent end
	function w:SetParent(p) self._parent = p end
	function w:GetRegions() return unpack(self._regions or {}) end
	function w:Show()
		local wasShown = self._shown
		self._shown = true
		if not wasShown and self._scripts.OnShow then self._scripts.OnShow(self) end
	end
	function w:Hide()
		local wasShown = self._shown
		self._shown = false
		if wasShown and self._scripts.OnHide then self._scripts.OnHide(self) end
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
	function w:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
	function w:SetFont(...) end
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
	function w:SetColorTexture(...) end
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
		local ag = { Play = function() end, Stop = function() end, SetToFinalAlpha = function() end }
		function ag:CreateAnimation()
			return { SetOrder = function() end, SetDuration = function() end, SetFromAlpha = function() end, SetToAlpha = function() end, SetStartDelay = function() end }
		end
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
			counters.setBagItem = counters.setBagItem + 1
			local data = _G.C_TooltipInfo.GetBagItem(bag, slot)
			self._lines = {}
			if data and data.lines then
				for i, ln in ipairs(data.lines) do
					self._lines[i] = ln.leftText or ""
					if self._name then
						local fs = _G[self._name .. "TextLeft" .. i] or makeWidget("FontString", self._name .. "TextLeft" .. i, self)
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
			if self._view and self._view._initFn then
				local items = dp:GetCollection()
				local limit = math.min(#items, 20)
				for i = 1, limit do
					local rowWidget = self._frames[i] or makeWidget("Button", nil, self)
					self._view._initFn(rowWidget, items[i])
					self._frames[i] = rowWidget
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
_G.GameTooltip = makeWidget("GameTooltip", "GameTooltip", UIParent)
_G.GameTooltip_Hide = function() GameTooltip:Hide() end
_G.Settings = {
	RegisterCanvasLayoutCategory = function(f, n) return { _frame = f, _name = n, GetID = function() return 99 end } end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}

_G.Enum = {
	GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 },
	AuctionHouseSortOrder = { Price = 0 },
}
_G.C_GameRules = {
	IsGameRuleActive = function()
		counters.detectGameRule = counters.detectGameRule + 1
		return false
	end,
}
_G.UnitFactionGroup = function() return "Horde" end
_G.GetRealmName = function() return "Normal" end
_G.UnitName = function() return "StandalonePlayer" end
_G.GetCVar = function(k) if k == "Portal" then return "EU" end return "" end

_G.GetProfessions = function() return 1, 2, nil, nil, 3, nil end
_G.GetProfessionInfo = function(idx)
	if idx == 1 then return "Alchemy", 136240, 225, 300, 0, 0, 171 end
	if idx == 2 then return "Leatherworking", 133611, 250, 300, 0, 0, 165 end
	if idx == 3 then return "Cooking", 133971, 210, 300, 0, 0, 185 end
end
_G.C_Reputation = {
	GetFactionDataByID = function(fid)
		return {
			factionID = fid,
			name = "Durotar Supply and Logistics",
			reaction = 5,
			currentReactionThreshold = 3000,
			nextReactionThreshold = 9000,
			currentStanding = 4500,
		}
	end,
}
_G.C_CurrencyInfo = {
	GetCurrencyInfo = function(cid)
		if cid == 3402 then
			counters.uiRefresh = (counters.uiRefresh or 0) + 1
			return { quantity = 85, iconFileID = 237281 }
		end
	end,
}
_G.C_TradeSkillUI = {
	GetRecipeInfo = function()
		counters.getRecipeInfo = counters.getRecipeInfo + 1
		return nil
	end,
}

-- Simulate realistic WoW item cache: 15% cached initially, 85% require async server load!
local clientItemCache = {}
local pendingServerItemQueue = {}
_G.C_Item = {
	GetItemInfo = function(id)
		local c = clientItemCache[id]
		if c then
			return c.name, nil, 2, 20, 15, "Trade Goods", "Herb", 20, "", 134400, 250, 7, 0, 0
		end
		return nil
	end,
	GetItemIconByID = function() return 134400 end,
	RequestLoadItemDataByID = function(id)
		counters.requestLoadItem = counters.requestLoadItem + 1
		if not clientItemCache[id] then
			pendingServerItemQueue[#pendingServerItemQueue + 1] = id
		end
	end,
}

-- Realistic 5x20 = 100 bag slots with 75 distinct items (1 Waylaid Crate + 74 regular items)
_G.NUM_BAG_SLOTS = 4
local bagData = {}
for b = 0, 4 do
	bagData[b] = {}
	for s = 1, 20 do
		local idx = b * 20 + s
		if idx == 1 then
			bagData[b][s] = { itemID = 248682, stackCount = 1, iconFileID = 236994, hyperlink = "|cff1eff00|Hitem:248682::::::::20:::::|h[Waylaid Crate: Apprentice Herbs]|h|r" }
		elseif idx <= 75 then
			local fakeID = 50000 + idx
			bagData[b][s] = { itemID = fakeID, stackCount = 5, iconFileID = 134400, hyperlink = string.format("|cffffffff|Hitem:%d::::::::20:::::|h[Adventurer Bag Item %d]|h|r", fakeID, idx) }
		end
	end
end

_G.C_Container = {
	GetContainerNumSlots = function(b) return (b >= 0 and b <= 4) and 20 or 0 end,
	GetContainerItemInfo = function(b, s)
		counters.getBagSlot = counters.getBagSlot + 1
		return bagData[b] and bagData[b][s] or nil
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
		return {
			lines = {
				{ leftText = "Adventurer Bag Item" },
				{ leftText = "Binds when equipped" },
				{ leftText = "+12 Stamina" },
				{ leftText = "Requires Level 45" },
				{ leftText = "Sell Price: 45s 20c" },
			},
		}
	end,
	GetItemByID = function()
		counters.tooltipGetItemByID = counters.tooltipGetItemByID + 1
		return { lines = { { leftText = "Recipe" }, { leftText = "Requires Skill 150" } } }
	end,
}

_G.TSM_APPHELPER_LOAD_DATA = function() end
_G.TradeSkillMasterDB = { ["g@ @coreOptions"] = { auctionDBAltRealm = "PvP-Alliance" } }

-- Parse .toc & load MerchantMaster
local tocFh = assert(io.open(addonDir .. "MerchantMaster.toc", "r"))
local tocFiles = {}
for line in tocFh:lines() do
	local clean = line:gsub("\r", ""):match("^%s*([^#%s].-)%s*$")
	if clean and clean ~= "" then tocFiles[#tocFiles + 1] = clean end
end
tocFh:close()

local ns = {}
local mailboxTakeItem,mailboxTakeMoney,mailboxAutoLoot
_G.TakeInboxItem=function(...) if mailboxTakeItem then return mailboxTakeItem(...) end end
_G.TakeInboxMoney=function(...) if mailboxTakeMoney then return mailboxTakeMoney(...) end end
_G.AutoLootMailItem=function(...) if mailboxAutoLoot then return mailboxAutoLoot(...) end end
local fixture = dofile(((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "fixture_toc.lua")
local analytics = fixture.Load(addonDir, "MerchantMaster", ns)
assert(analytics == _G.MerchantMasterAnalytics, "unified Analytics namespace")

-- Optional Blizzard Snapshot companion payload; fall back to synthetic Live AH prices standalone
local snapNS = {}
local snapLoader = loadfile(snapshotsDir .. "MerchantMaster_Snapshots.lua")
local snapData = loadfile(snapshotsDir .. "SnapshotData.lua")
if snapLoader and snapData then
	snapLoader("MerchantMaster_Snapshots", snapNS)
	snapData("MerchantMaster_Snapshots", snapNS)
end
_G.MerchantMasterDB = _G.MerchantMasterDB or {}
local snapMeta = ns.Pricing and ns.Pricing.GetSnapshotMeta and ns.Pricing.GetSnapshotMeta("Normal-Horde")
if snapMeta and snapMeta.updatedAt and snapMeta.updatedAt + 3600 > wallEpoch then
	wallEpoch = snapMeta.updatedAt + 3600
elseif not (ns.HasSnapshots and ns.HasSnapshots()) then
	_G.MerchantMasterDB.ahPrices = _G.MerchantMasterDB.ahPrices or {}
	local nh = { _scannedAt = wallEpoch - 120 }
	for id in pairs(ns.ALL_CATALOG_IDS or {}) do
		nh[id] = { price = math.max(50, ((ns.VENDOR_SELL and ns.VENDOR_SELL[id]) or 100) * 3), qty = 25, at = wallEpoch - 120 }
	end
	_G.MerchantMasterDB.ahPrices["Normal-Horde"] = nh
end

-- Locate MerchantMaster eventFrame and wrap app.refresh to count calls
local eventFrame
for _, f in ipairs(createdFrames) do
	if f._events and f._events.ADDON_LOADED and f._scripts.OnEvent then
		eventFrame = f
		break
	end
end

_G.MerchantMasterAPI.RegisterRefreshListener(function()
	counters.appRefresh = counters.appRefresh + 1
end)

-- Boot addon & step past login timers (0 -> 6s with panel closed)
eventFrame._scripts.OnEvent(eventFrame, "ADDON_LOADED", "MerchantMaster")
eventFrame._scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
stepTimersTo(1006.0)
pendingServerItemQueue = {}

---------------------------------------------------------------------------------------------------
-- BENCHMARK 1: Open /mm (Dashboard) + stand idle for 5.0 seconds while server streams item info
--              + random nearby player/tooltip GET_ITEM_INFO_RECEIVED events fire!
---------------------------------------------------------------------------------------------------
resetCounters()
local t0 = os.clock()
_G.MerchantMasterAPI.TogglePanel() -- user types /mm
local tOpen = os.clock() - t0
local openRefreshes = counters.uiRefresh
local openTSM = counters.tsmCustomPrice
local openSetBag = counters.setBagItem
local openReqLoad = counters.requestLoadItem
local openGameRule = counters.detectGameRule

-- Simulate 5.0 seconds (100 ticks of 50ms = 20 FPS/server ticks):
-- Server streams back up to 2 queued items per 50ms (40 items/sec) + 1 unrelated world item per 100ms
local tIdle0 = os.clock()
for step = 1, 100 do
	local nextTime = 1006.0 + step * 0.05
	for _ = 1, 2 do
		local loadedID = table.remove(pendingServerItemQueue, 1)
		if loadedID then
			clientItemCache[loadedID] = { name = ns.ITEM_NAMES_BY_ID[loadedID] or ("Item " .. loadedID) }
			if eventFrame._events.GET_ITEM_INFO_RECEIVED then
				eventFrame._scripts.OnEvent(eventFrame, "GET_ITEM_INFO_RECEIVED", loadedID, true)
			end
		end
	end
	if step % 2 == 0 and eventFrame._events.GET_ITEM_INFO_RECEIVED then
		-- Unrelated world item loaded by another player's gear / nameplate / tooltip
		eventFrame._scripts.OnEvent(eventFrame, "GET_ITEM_INFO_RECEIVED", 990000 + step, true)
	end
	stepTimersTo(nextTime)
end
local tIdle5s = os.clock() - tIdle0
local total5s = os.clock() - t0

local idleRefreshes = counters.uiRefresh - openRefreshes
local totalRefreshes5s = counters.uiRefresh
local totalTSM5s = counters.tsmCustomPrice
local totalSetBag5s = counters.setBagItem
local totalGameRule5s = counters.detectGameRule
local totalRecipeInfo5s = counters.getRecipeInfo
local totalTooltipItem5s = counters.tooltipGetItemByID

---------------------------------------------------------------------------------------------------
-- BENCHMARK 2: Tab-Switch Tour Across All Major Views
---------------------------------------------------------------------------------------------------
resetCounters()
local tabs = { "profit_spread", "outliers", "recipes", "crates", "writs", "rep", "calc_favor", "calc_rep", "prof_path", "prof_shop", "prof_browse", "an_overview", "bags", "dashboard" }
local tTabs0 = os.clock()
for _, tb in ipairs(tabs) do
	_G.MerchantMasterAPI.SetTab(tb)
end
local tTabs = os.clock() - tTabs0

print(string.format("OPEN_MS=%.2f | OPEN_REFRESHES=%d | OPEN_TSM=%d | OPEN_SETBAG=%d | OPEN_REQLOAD=%d | OPEN_GAMERULE=%d",
	tOpen * 1000, openRefreshes, openTSM, openSetBag, openReqLoad, openGameRule))
print(string.format("IDLE_5S_MS=%.2f | IDLE_REFRESHES=%d | TOTAL_5S_MS=%.2f | TOTAL_5S_REFRESHES=%d | TOTAL_5S_TSM=%d | TOTAL_5S_SETBAG=%d | TOTAL_5S_GAMERULE=%d | TOTAL_5S_RECINFO=%d | TOTAL_5S_TTITEM=%d",
	tIdle5s * 1000, idleRefreshes, total5s * 1000, totalRefreshes5s, totalTSM5s, totalSetBag5s, totalGameRule5s, totalRecipeInfo5s, totalTooltipItem5s))
print(string.format("TAB_TOUR_14_MS=%.2f | TAB_TOUR_REFRESHES=%d | TAB_TOUR_TSM=%d | TAB_TOUR_SETBAG=%d",
	tTabs * 1000, counters.uiRefresh, counters.tsmCustomPrice, counters.setBagItem))


-- Slice A: exercise the real host and Accounting dispatch together.
local app=ns.app
local function fireAll(event,...)
    for _,frame in ipairs(createdFrames) do
        if frame._events and frame._events[event] and frame._scripts.OnEvent then frame._scripts.OnEvent(frame,event,...) end
    end
end
analytics.Capture.OnEvent(nil,"ADDON_LOADED","MerchantMaster")
analytics.Capture.OnEvent(nil,"PLAYER_LOGIN")
stepTimersTo(simNow+10)
local fullScans,commits,ownershipChanges,valuations=0,0,0,0
local originalScan=analytics.Capture.ScanMailboxSnapshot
analytics.Capture.ScanMailboxSnapshot=function(...) fullScans=fullScans+1; return originalScan(...) end
local originalCommit=app.CommitMailboxSnapshot
app.CommitMailboxSnapshot=function(...) commits=commits+1; return originalCommit(...) end
local originalInvalidate=app.invalidateRecipeStats
app.invalidateRecipeStats=function(reason,...) if reason=="ownership" then ownershipChanges=ownershipChanges+1 end; return originalInvalidate(reason,...) end
local originalValue=analytics.Capture.ValueWealthItem
analytics.Capture.ValueWealthItem=function(...) valuations=valuations+1; return originalValue(...) end
local quantity,mailReady=3,true
local attachments=0
_G.GetInboxNumItems=function() return 1,1 end
_G.GetInboxHeaderInfo=function() if mailReady then return 1,1,"Synthetic","Synthetic parcel",0,0,30,quantity>0 and 1 or 0,false,false end end
_G.GetInboxInvoiceInfo=function() end
_G.ATTACHMENTS_MAX_RECEIVE=12
_G.GetInboxItem=function(_,slot) attachments=attachments+1; if slot==1 and quantity>0 then return "Perf Parcel",900001,nil,quantity end end
_G.GetInboxItemLink=function(_,slot) if slot==1 and quantity>0 then return "item:900001" end end
mailboxTakeItem=function() quantity=math.max(0,quantity-1) end
mailboxTakeMoney=function() end
mailboxAutoLoot=function() quantity=0 end
analytics.Capture.InstallHooks()
local mailboxStart=os.clock()
fireAll("MAIL_SHOW")
for i=1,100 do fireAll("MAIL_INBOX_UPDATE") end
stepTimersTo(simNow+0.99)
assert(fullScans==0,"open scan must coalesce for a full second")
stepTimersTo(simNow+0.02)
assert(fullScans==1 and commits==1,"one shared open snapshot")
assert(app.char.mail["Perf Parcel"]==3,"host consumes shared named totals")
assert(analytics.Inventory.GetItemBreakdown(900001).mail==3,"inventory consumes shared ID totals")
local ownershipAfterOpen=ownershipChanges
stepTimersTo(simNow+5)
local beforeIdleAttachments,beforeIdleValues=attachments,valuations
for i=1,1200 do fireAll("MAIL_INBOX_UPDATE"); stepTimersTo(simNow+0.05) end
assert(fullScans==1 and attachments==beforeIdleAttachments,"idle inbox storm never scans attachments")
assert(ownershipChanges==ownershipAfterOpen and valuations==beforeIdleValues,"idle inbox storms never invalidate ownership or value wealth")
local idleAttachmentReads,idleValuations=attachments-beforeIdleAttachments,valuations-beforeIdleValues
_G.TakeInboxItem(1,1); _G.TakeInboxItem(1,1); _G.TakeInboxMoney(1)
fireAll("MAIL_INBOX_UPDATE")
fireAll("CLOSE_INBOX_ITEM",1,1)
stepTimersTo(simNow+1.1)
assert(fullScans==2 and commits==2 and app.char.mail["Perf Parcel"]==1,"take actions share one reconciliation")
local ownershipAfterTake=ownershipChanges
_G.TakeInboxMoney(1); fireAll("MAIL_INBOX_UPDATE"); fireAll("CLOSE_INBOX_ITEM",1)
stepTimersTo(simNow+1.1)
assert(fullScans==3 and ownershipChanges==ownershipAfterTake,"failed/no-op retrieval preserves ownership version")
_G.AutoLootMailItem(1); fireAll("MAIL_CLOSED")
stepTimersTo(simNow+2)
assert(fullScans==3 and app.char.mail["Perf Parcel"]==1,"close cancels pending action and retains accepted snapshot")
mailReady=false; fireAll("MAIL_SHOW"); stepTimersTo(simNow+1.1)
assert(fullScans==4 and commits==3 and app.char.mail["Perf Parcel"]==1,"unreadable open preserves valid quantities")
mailReady=true; stepTimersTo(simNow+1.1)
assert(fullScans==5 and commits==4 and not app.char.mail["Perf Parcel"],"bounded readiness retry accepts settled inbox")
fireAll("MAIL_CLOSED")
stepTimersTo(simNow+5)
print(string.format("MEASURE MAILBOX_STORM_MS=%.3f SCANS=%d COMMITS=%d IDLE_ATTACHMENT_READS=%d IDLE_VALUATIONS=%d",(os.clock()-mailboxStart)*1000,fullScans,commits,idleAttachmentReads,idleValuations))

-- Frame registration order cannot introduce an independent Accounting open scan.
local scansBeforeReverse=fullScans
analytics.Capture.OnEvent(nil,"MAIL_SHOW")
eventFrame._scripts.OnEvent(eventFrame,"MAIL_SHOW")
assert(fullScans==scansBeforeReverse,"Accounting-first MAIL_SHOW still defers to the shared coordinator")
stepTimersTo(simNow+1.1)
assert(fullScans==scansBeforeReverse+1,"reversed event order produces exactly one open scan")
fireAll("MAIL_CLOSED")

-- Time alone must preserve the UI bank; freshness and explicit dependencies still expire it.
local bank=app.getUIPriceBank()
stepTimersTo(simNow+65)
assert(app.getUIPriceBank()==bank,"elapsed idle time does not discard the UI price bank")
ns.InvalidatePriceCache(); assert(app.getUIPriceBank()~=bank,"accepted price epoch expires bank")
local econ=ns.CurrentEconomyInfo().effectiveKey
MerchantMasterDB.ahPrices=MerchantMasterDB.ahPrices or {}; MerchantMasterDB.ahPrices[econ]=MerchantMasterDB.ahPrices[econ] or {}
MerchantMasterDB.ahPrices[econ][900002]={price=100,qty=1,at=time()-1800,absent=false}
ns.InvalidatePriceCache(); bank=app.getUIPriceBank()
stepTimersTo(simNow+2)
assert(app.getUIPriceBank()==bank,"Standalone mode does not spuriously expire UI price bank on legacy 30m boundary")

-- Warm the real accounting model with synthetic history, then use the host's item hook.
local char=app.charKey
for i=1,600 do analytics.Store.Append({char=char,type="AH_SELL",itemID=900000+i%8,qty=1,total=95,unit=100,time=time(),extra={gross=100,fee=5}}) end
stepTimersTo(simNow+2)
local traversals,inventoryReads=0,0
local iter=analytics.Store.IterDays
analytics.Store.IterDays=function(...) traversals=traversals+1; return iter(...) end
local breakdown=analytics.Inventory.GetItemBreakdown
analytics.Inventory.GetItemBreakdown=function(...) inventoryReads=inventoryReads+1; return breakdown(...) end
local merchantReads=0
_G.GetMerchantNumItems=function() merchantReads=merchantReads+1; return 8 end
_G.GetMerchantItemLink=function(slot) merchantReads=merchantReads+1; return "item:"..(900000+slot-1) end
analytics.Tooltips.Invalidate()
local preloadStart=os.clock()
local preloadMaxCallback=0
local oldAfter=C_Timer.After
C_Timer.After=function(delay,fn)
    oldAfter(delay,function() local started=os.clock(); fn(); preloadMaxCallback=math.max(preloadMaxCallback,(os.clock()-started)*1000) end)
end
fireAll("MERCHANT_SHOW"); stepTimersTo(simNow+3)
local preloadMS=(os.clock()-preloadStart)*1000
C_Timer.After=oldAfter
assert(traversals==2,"merchant preload builds all-time/recent indexes once each")
local builds,reads,merchantBefore=traversals,inventoryReads,merchantReads
local hoverID=900001
GameTooltip.GetItem=function() return "Perf Item","item:"..hoverID end
GameTooltip.GetTooltipData=function() return {itemID=hoverID,stackCount=1} end
local tooltipOwner={}
GameTooltip.GetOwner=function() return tooltipOwner end
local hook=assert(GameTooltip._scripts.OnTooltipSetItem,"host tooltip hook")
local function clearTooltip()
    GameTooltip:ClearLines()
    if GameTooltip._scripts.OnTooltipCleared then GameTooltip._scripts.OnTooltipCleared(GameTooltip) end
end
local hoverStart=os.clock()
for i=1,1000 do
    hoverID=900000+i%8; clearTooltip(); hook(GameTooltip)
    assert(table.concat(GameTooltip._lines," "):find("MerchantMaster Accounting",1,true),"primed host hover renders Accounting")
end
local hoverMS=(os.clock()-hoverStart)*1000
assert(traversals==builds and inventoryReads==reads and merchantReads==merchantBefore,"warm host/vendor/spread tooltip performs no history, inventory, or shop enumeration")
local hotTraversals,hotInventoryReads,hotMerchantReads=traversals-builds,inventoryReads-reads,merchantReads-merchantBefore
-- A cleared or repurposed tooltip must not receive an old deferred result.
analytics.Tooltips.Invalidate(); hoverID=910001; clearTooltip(); hook(GameTooltip)
assert(#GameTooltip._lines==0,"cold host hover queues work")
hoverID=910002; tooltipOwner={}; clearTooltip(); stepTimersTo(simNow+3)
assert(#GameTooltip._lines==0,"delayed tooltip cannot append to a different item/owner")
print(string.format("MEASURE PRELOAD_MS=%.3f PRELOAD_MAX_CALLBACK_MS=%.3f HOVER_1000_MS=%.3f HOT_LEDGER_TRAVERSALS=%d HOT_INVENTORY_READS=%d HOT_MERCHANT_READS=%d",preloadMS,preloadMaxCallback,hoverMS,hotTraversals,hotInventoryReads,hotMerchantReads))
print("PASS: Slice A real host mailbox, preload, hover and price-cache performance contracts")
