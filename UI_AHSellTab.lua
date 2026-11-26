local ADDON, ns = ...
local app = ns.app or {}
ns.app = app

-- Standalone Auction House "MM Sell" Tab (LibAHTab-1-0 + Spacious Auctionator-Parity Layout)
local AHSellTab = {}
ns.AHSellTab = AHSellTab

local SELL_TAB_ID = "MerchantMaster_Sell"
local SELL_TAB_LABEL = "MM Sell"
local SELL_TAB_HEADER = "MerchantMaster - Sell"

local SELL_UNDERCUT_LABELS = { match = "Match", ["1c"] = "-1c", ["1s"] = "-1s", pct = "-1%" }
local SELL_DUR_LABELS = { [1] = "2h", [2] = "8h", [3] = "24h" }
local SELL_PRICES_VISIBLE_ROWS = 9
local SELL_PRICES_ROW_H = 22
local SELL_QUEUE_VISIBLE_ROWS = 8
local SELL_QUEUE_ROW_H = 26
local SELL_HISTORY_VISIBLE_ROWS = 8
local SELL_HISTORY_ROW_H = 24
local BAG_GRID_COLS = 5
local BAG_TILE_SZ = 38
local BAG_TILE_GAP = 4
local BAG_CAT_HDR_H = 18
local BAG_TILE_ROW_H = BAG_TILE_SZ + BAG_TILE_GAP
local BAG_VIEW_H = 260

local function getPal()
	local active = ns.Theme and ns.Theme.GetActivePalette and ns.Theme.GetActivePalette()
	if active then return active end
	if ns.Theme and ns.Theme.PALETTES and ns.Theme.GetMode then
		local p = ns.Theme.PALETTES[ns.Theme.GetMode()]
		if p then return p end
	end
	return (ns.Theme and (ns.Theme.PALETTE or ns.Theme.COLORS)) or {}
end

local function isLightTheme()
	return ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode() == "light"
end

local function palHex(key, fb)
	local p = getPal()
	return "|cff" .. tostring((p and p[key]) or fb or "ffffff")
end

local function applySafeFont(fs, size, weight)
	if not fs then return end
	if ns.Theme and ns.Theme.ApplyFont then
		ns.Theme.ApplyFont(fs, size, weight)
	elseif ns.Theme and ns.Theme.SetFont then
		ns.Theme.SetFont(fs, size, "")
	end
end

local function resolveIconTex(itemID, spellID)
	if itemID and itemID > 0 then
		local tex = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
			or (GetItemIcon and GetItemIcon(itemID))
		if tex then return tex end
	end
	if spellID and spellID > 0 then
		local stex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
			or (GetSpellTexture and GetSpellTexture(spellID))
		if stex then return stex end
	end
	return ns.QUESTION_ICON or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function getQualityRGB(q)
	if ns.GetItemQualityColor then
		local r, g, b = ns.GetItemQualityColor(q or 1)
		if r and g and b then return r, g, b end
	end
	if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q or 1] then
		local c = _G.ITEM_QUALITY_COLORS[q or 1]
		return c.r or 1, c.g or 1, c.b or 1
	end
	local fb = {
		[0] = { 0.62, 0.62, 0.62 },
		[1] = { 0.96, 0.96, 0.96 },
		[2] = { 0.12, 1.00, 0.00 },
		[3] = { 0.00, 0.44, 0.87 },
		[4] = { 0.64, 0.21, 0.93 },
		[5] = { 1.00, 0.50, 0.00 },
	}
	local c = fb[q or 1] or fb[1]
	return c[1], c[2], c[3]
end

local function formatSellTitle(of, item)
	if not item then return "No Item Selected", "Drag an item here or click one from Bags below." end
	local name = (of and of.FormatSellItemTitle and of.FormatSellItemTitle(item)) or tostring(item.name or "Item")
	local q = item.quality or 1
	local r, g, b = getQualityRGB(q)
	local hex = string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	local inBags = tonumber(item.inBags) or 0
	local rem = tonumber(item.remaining) or 0
	local sub = string.format("In Bags: %d  |  Queue: %d left", inBags, rem)
	if item.channel == "vendor" then
		sub = string.format("In Bags: %d  |  Vendor: %d left", inBags, rem)
	end
	return hex .. name .. "|r", sub
end

local function makeFramedBtn(parent, w, h, label, fontSize, opts)
	opts = opts or {}
	local b = CreateFrame("Button", opts.name, parent)
	b:SetSize(w, h)
	b._enabled = true
	b._label = tostring(label or "")
	b.plate = ns.Theme.NineApple(b, "glass_r8",
		{ 0.06, 0.18, 0.12, 0.92 },
		{ 0.83, 0.64, 0.24, 0.78 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = math.min(8, math.floor(h * 0.4)), noSpecular = true })
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", b, "LEFT", 4, 0)
	fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
	fs:SetWordWrap(false)
	applySafeFont(fs, fontSize or 10, "semibold")
	fs:SetText(b._label)
	b.fs = fs

	local origEnable, origDisable = b.Enable, b.Disable
	local function applyStyle(self)
		local en = (self._enabled ~= false)
		local f = self._fill or { 0.06, 0.18, 0.12, 0.92 }
		local s = self._stroke or { 0.83, 0.64, 0.24, 0.78 }
		local t = self._textCol or { 0.98, 0.96, 0.90, 1.0 }
		if en then
			self.plate:SetFill(f[1], f[2], f[3], f[4] or 0.92)
			self.plate:SetStroke(s[1], s[2], s[3], s[4] or 0.78)
			fs:SetTextColor(t[1], t[2], t[3], t[4] or 1.0)
		else
			self.plate:SetFill(f[1] * 0.65, f[2] * 0.65, f[3] * 0.65, 0.60)
			self.plate:SetStroke(s[1], s[2], s[3], 0.30)
			fs:SetTextColor(t[1] * 0.65, t[2] * 0.65, t[3] * 0.65, 0.45)
		end
	end
	function b:PaintStyle(fill, stroke, textCol)
		self._fill = fill
		self._stroke = stroke
		self._textCol = textCol
		applyStyle(self)
	end
	function b:SetEnabled(en)
		self._enabled = (en == true)
		if en then
			if origEnable then pcall(origEnable, self) end
		else
			if origDisable then pcall(origDisable, self) end
		end
		applyStyle(self)
	end
	function b:IsEnabled() return self._enabled ~= false end
	function b:SetText(txt)
		self._label = tostring(txt or "")
		fs:SetText(self._label)
	end
	function b:GetText() return self._label end
	b:SetScript("OnEnter", function(self)
		if self._enabled == false then return end
		local s = self._stroke or { 0.83, 0.64, 0.24, 0.78 }
		self.plate:SetStroke(math.min(1, s[1] + 0.12), math.min(1, s[2] + 0.12), math.min(1, s[3] + 0.12), 1.0)
	end)
	b:SetScript("OnLeave", function(self)
		applyStyle(self)
	end)
	return b
end

local function makeBaronScrollbar(parent, onStep)
	local track = CreateFrame("Frame", nil, parent)
	track:SetWidth(8)
	track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -2)
	track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 2)
	track.plate = ns.Theme.NineApple(track, "pill",
		{ 0.03, 0.08, 0.05, 0.85 },
		{ 0.83, 0.64, 0.24, 0.35 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 4, noSpecular = true })
	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(6)
	thumb:SetPoint("TOP", track, "TOP", 0, -1)
	thumb:SetHeight(32)
	thumb.plate = ns.Theme.NineApple(thumb, "pill",
		{ 0.18, 0.72, 0.44, 0.92 },
		{ 0.97, 0.84, 0.49, 0.88 },
		{ layer = "ARTWORK", sub = 1, cornerSize = 3, noSpecular = true })
	if track.EnableMouseWheel then track:EnableMouseWheel(true) end
	track:SetScript("OnMouseWheel", function(_, delta)
		if onStep then onStep(delta) end
	end)
	thumb:SetScript("OnClick", function()
		if onStep then onStep(-1) end
	end)
	function track:Update(offset, visibleCount, totalCount, isLight, strokeCol, fillCol)
		if not totalCount or totalCount <= visibleCount then
			self:Hide()
			return false
		end
		self:Show()
		local h = self:GetHeight()
		if not h or h < 20 then h = 160 end
		local ratio = visibleCount / totalCount
		local th = math.max(18, math.floor((h - 4) * ratio))
		local maxOff = math.max(1, totalCount - visibleCount)
		local travel = math.max(0, (h - 4) - th)
		local topOff = math.floor(travel * (math.min(maxOff, math.max(0, offset)) / maxOff) + 0.5)
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", self, "TOP", 0, -(2 + topOff))
		self.plate:SetFill(isLight and 0.88 or 0.03, isLight and 0.90 or 0.08, isLight and 0.92 or 0.05, 0.85)
		self.plate:SetStroke(strokeCol[1], strokeCol[2], strokeCol[3], 0.35)
		thumb.plate:SetFill(fillCol[1], fillCol[2], fillCol[3], 0.92)
		thumb.plate:SetStroke(strokeCol[1], strokeCol[2], strokeCol[3], 0.85)
		return true
	end
	track:Hide()
	return track
end

local function addTip(widget, title, bodyFnOrText)
	if not (widget and widget.SetScript) then return end
	if widget.SetMotionScriptsWhileDisabled then
		pcall(widget.SetMotionScriptsWhileDisabled, widget, true)
	end
	local fn = function(self)
		if not GameTooltip then return end
		local body = (type(bodyFnOrText) == "function") and bodyFnOrText(self) or bodyFnOrText
		if type(bodyFnOrText) == "function" and (type(body) ~= "string" or body == "") then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(title, 1.0, 0.85, 0.35)
		if type(body) == "string" and body ~= "" then
			GameTooltip:AddLine(body, 0.90, 0.92, 0.94, true)
		end
		if ns.Theme and ns.Theme.LiftTooltip then ns.Theme.LiftTooltip(GameTooltip) end
		GameTooltip:Show()
	end
	local leaveFn = function()
		if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
	end
	if widget.HookScript then
		widget:HookScript("OnEnter", fn)
		widget:HookScript("OnLeave", leaveFn)
	else
		widget:SetScript("OnEnter", fn)
		widget:SetScript("OnLeave", leaveFn)
	end
end

-- Bootstrap compatible LibAHTab-1-0 if Auctionator (or another provider) is not loaded
local function ensureLibAHTab()
	local ls = _G.LibStub
	if ls then
		local existing = ls("LibAHTab-1-0", true)
		if existing and existing.CreateTab then
			return existing
		end
	end

	local lib = ls and ls:NewLibrary("LibAHTab-1-0", 5) or AHSellTab._fallbackLib
	if not lib then
		lib = {}
		AHSellTab._fallbackLib = lib
	end
	if lib.internalState and lib.CreateTab then
		return lib
	end

	local MIN_TAB_WIDTH = 70
	local TAB_PADDING = 20
	local OFFSET_X = 3
	if _G.WOW_PROJECT_ID and _G.WOW_PROJECT_MAINLINE and _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_MAINLINE
		and (_G.WOW_PROJECT_CAMELOT == nil or _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_CAMELOT) then
		OFFSET_X = -14
	end

	function lib:DoesIDExist(tabID)
		return lib.internalState ~= nil and lib.internalState.usedIDs[tabID] ~= nil
	end

	function lib:CreateTab(tabID, attachedFrame, displayText, tabHeader)
		local ahf = _G.AuctionHouseFrame
		if not ahf then return nil end
		if not lib.internalState then
			lib.internalState = {
				Tabs = {},
				usedIDs = {},
				selectedTab = nil,
			}
			local root = CreateFrame("Frame", nil, ahf)
			root:SetSize(10, 10)
			if ahf.Tabs and #ahf.Tabs > 0 then
				root:SetPoint("TOPLEFT", ahf.Tabs[#ahf.Tabs], "TOPRIGHT")
			else
				root:SetPoint("BOTTOMLEFT", ahf, "BOTTOMLEFT", 12, -28)
			end
			lib.internalState.rootFrame = root
			if _G.hooksecurefunc and ahf.SetDisplayMode then
				_G.hooksecurefunc(ahf, "SetDisplayMode", function(_, mode)
					if mode ~= nil and #mode > 0 and lib.internalState then
						for _, tab in ipairs(lib.internalState.Tabs) do
							if tab.frameRef and tab.frameRef.Hide then tab.frameRef:Hide() end
							if _G.PanelTemplates_DeselectTab then pcall(_G.PanelTemplates_DeselectTab, tab) end
						end
					end
				end)
			end
		end
		if lib:DoesIDExist(tabID) then
			return lib.internalState.usedIDs[tabID]
		end
		local newTab = CreateFrame("Button", "LibAHFrame-1.0-" .. tabID, lib.internalState.rootFrame, "AuctionHouseFrameDisplayModeTabTemplate")
		table.insert(lib.internalState.Tabs, newTab)
		newTab:SetText(displayText)
		lib.internalState.usedIDs[tabID] = newTab
		if _G.PanelTemplates_TabResize then
			pcall(_G.PanelTemplates_TabResize, newTab, TAB_PADDING, nil, MIN_TAB_WIDTH)
		end
		if #lib.internalState.Tabs > 1 then
			newTab:SetPoint("TOPLEFT", lib.internalState.Tabs[#lib.internalState.Tabs - 1], "TOPRIGHT", OFFSET_X, 0)
		else
			newTab:SetPoint("TOPLEFT", lib.internalState.rootFrame, "TOPLEFT", OFFSET_X, 0)
		end
		if newTab.SetHitRectInsets then
			newTab:SetHitRectInsets((math.abs(OFFSET_X) - 3) / 2, (math.abs(OFFSET_X) - 3) / 2, 0, 0)
		end
		if _G.PanelTemplates_DeselectTab then
			pcall(_G.PanelTemplates_DeselectTab, newTab)
		end
		newTab.frameRef = attachedFrame
		newTab.tabHeader = tabHeader or displayText
		attachedFrame:Hide()
		newTab:SetScript("OnClick", function()
			lib:SetSelected(tabID)
		end)
		return newTab
	end

	function lib:GetButton(tabID)
		return lib.internalState and lib.internalState.usedIDs[tabID] or nil
	end

	function lib:SetSelected(tabID)
		local ahf = _G.AuctionHouseFrame
		if not (lib.internalState and lib:DoesIDExist(tabID)) then return end
		if ahf and ahf.SetDisplayMode then
			ahf:SetDisplayMode({})
			ahf.displayMode = nil
		end
		for _, tab in ipairs(lib.internalState.Tabs) do
			if tab.frameRef and tab.frameRef.Hide then tab.frameRef:Hide() end
			if _G.PanelTemplates_DeselectTab then pcall(_G.PanelTemplates_DeselectTab, tab) end
		end
		if ahf and ahf.Tabs then
			for _, tab in ipairs(ahf.Tabs) do
				if _G.PanelTemplates_DeselectTab then pcall(_G.PanelTemplates_DeselectTab, tab) end
			end
		end
		local selectedTab = lib:GetButton(tabID)
		if selectedTab then
			if _G.PanelTemplates_SelectTab then pcall(_G.PanelTemplates_SelectTab, selectedTab) end
			if ahf and ahf.SetTitle then pcall(ahf.SetTitle, ahf, selectedTab.tabHeader) end
			if selectedTab.frameRef and selectedTab.frameRef.Show then selectedTab.frameRef:Show() end
		end
	end

	return lib
end

-- Build UI cleanly and lazily on first attachment / inspection
local initialized = false
local attachedHost = nil
local attachedLib = nil
local pickupHooked = false
local lastPickedBag, lastPickedSlot = nil, nil

local spaceBindOwner = CreateFrame("Frame", nil, UIParent)
local spaceBound = false
local spacePendingSync = false

local tabFrame = nil
local tabBtn = nil

local pricesScrollOffset = 0
local queueScrollOffset = 0
local historyScrollOffset = 0
local bagScrollOffset = 0
local bagLayoutCache = {}
local bagScanCache = {}
local activeSubTab = "prices"

local function installBagPickupHook()
	if pickupHooked then return end
	if _G.C_Container and type(_G.C_Container.PickupContainerItem) == "function" then
		pickupHooked = true
		if _G.hooksecurefunc then
			_G.hooksecurefunc(_G.C_Container, "PickupContainerItem", function(bag, slot)
				lastPickedBag = bag
				lastPickedSlot = slot
			end)
		else
			local origPickup = _G.C_Container.PickupContainerItem
			_G.C_Container.PickupContainerItem = function(bag, slot, ...)
				lastPickedBag = bag
				lastPickedSlot = slot
				return origPickup(bag, slot, ...)
			end
		end
	end
end

local function isHostAHFull()
	local ahf = _G.AuctionHouseFrame
	return ahf ~= nil and type(ahf) == "table" and ahf.Tabs ~= nil and #ahf.Tabs > 0 and ahf.SetDisplayMode ~= nil
end

local function isAHOpensafe()
	local ahf = _G.AuctionHouseFrame
	if ahf and ahf.IsShown and ahf:IsShown() then return true end
	return false
end

function AHSellTab.IsShown()
	return tabFrame ~= nil and tabFrame:IsShown() and true or false
end

function AHSellTab.IsSpacePendingSync()
	return spacePendingSync
end

function AHSellTab.SyncSpaceBinding(forceClear)
	local of = ns.MarketScan and ns.MarketScan.OrderFlow or app.orderFlow
	local sl = of and of.GetState and of.GetState().stages.sell
	local cur = sl and sl.items and sl.items[sl.activeIndex]
	local isLegacy = (_G.IsUsingLegacyAuctionClient and _G.IsUsingLegacyAuctionClient() == true)
	local hasAHContext = (cur ~= nil and cur.channel ~= "vendor")
		or (sl ~= nil and (sl.pendingPost ~= nil or sl.warningConfirm ~= nil))
	local shouldBind = (not forceClear)
		and (not isLegacy)
		and isAHOpensafe()
		and AHSellTab.IsShown()
		and hasAHContext
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		spacePendingSync = true
		return false
	end
	spacePendingSync = false
	if shouldBind then
		if not spaceBound and type(_G.SetOverrideBindingClick) == "function" then
			pcall(_G.SetOverrideBindingClick, spaceBindOwner, false, "SPACE", "MerchantMasterSellPostBtn", "LeftButton")
			spaceBound = true
		end
	elseif spaceBound then
		if type(_G.ClearOverrideBindings) == "function" then
			pcall(_G.ClearOverrideBindings, spaceBindOwner)
		end
		spaceBound = false
	end
	return spaceBound
end
AHSellTab.spaceBindOwner = spaceBindOwner

local function getOrderFlow()
	return (ns.MarketScan and ns.MarketScan.OrderFlow) or app.orderFlow
end

local function buildBagCategoryLayout(items)
	local out = {}
	local lastCat = nil
	local row = nil
	for _, rec in ipairs(items or {}) do
		local cat = rec.className or "Miscellaneous"
		if cat ~= lastCat then
			lastCat = cat
			out[#out + 1] = { kind = "header", label = cat, h = BAG_CAT_HDR_H }
			row = nil
		end
		if (not row) or (#row.items >= BAG_GRID_COLS) then
			row = { kind = "row", items = {}, h = BAG_TILE_ROW_H }
			out[#out + 1] = row
		end
		row.items[#row.items + 1] = rec
	end
	return out
end

local function isWidgetFrame(f)
	if f == nil then return false end
	return ((f.IsObjectType and f:IsObjectType("Frame")) or (f.GetObjectType and f:GetObjectType() == "Frame")) and true or false
end

local function getBagVisibleLayoutCount()
	local gridH = (AHSellTab.sellBagGrid and AHSellTab.sellBagGrid.GetHeight and AHSellTab.sellBagGrid:GetHeight()) or 0
	if gridH < 120 then gridH = BAG_VIEW_H end
	return math.max(4, math.floor(gridH / BAG_TILE_ROW_H)), gridH
end

local function getVisibleRowCount(area, rowH, maxRows, minRows)
	local h = (area and area.GetHeight and area:GetHeight()) or 0
	local floorMin = minRows or 3
	if h >= (rowH * floorMin) then
		return math.max(floorMin, math.min(maxRows, math.floor(h / rowH)))
	end
	return maxRows
end

local function getCurrentSellListings()
	local of = getOrderFlow()
	local sl = of and of.GetState and of.GetState().stages.sell
	local cur = sl and sl.items and sl.items[sl.activeIndex]
	if cur and type(cur.currentListings) == "table" then
		return cur.currentListings, cur.listingsScanned == true
	end
	if (not cur) and sl and type(sl.lastItemListings) == "table" then
		return sl.lastItemListings, true
	end
	return {}, false
end

local function getHistoryRowsData(target)
	local itemID = target and tonumber(target.itemID) or 0
	if itemID <= 0 or not (ns.MarketScan and ns.MarketScan.GetItemTrend7d) then
		return {}, nil, nil
	end
	local t7 = ns.MarketScan.GetItemTrend7d(itemID)
	local t24 = ns.MarketScan.GetItemTrend24h and ns.MarketScan.GetItemTrend24h(itemID) or nil
	local rows = {}
	local nowSec = (time and time()) or 0
	local curDay = math.floor(nowSec / 86400)
	local pts7 = t7 and t7.points or {}
	for idx = #pts7, 1, -1 do
		local pt = pts7[idx]
		if pt and pt.price and pt.price > 0 then
			local diff = curDay - (pt.d or curDay)
			local lbl = (diff == 0) and "Today" or (diff > 0 and string.format("-%dd", diff) or string.format("Day %d", pt.d or 0))
			rows[#rows + 1] = {
				when = lbl,
				price = pt.price,
				qty = pt.qty or 0,
				vel = pt.salesPerDay,
				source = t7.source or "7d",
			}
		end
	end
	if #rows == 0 and t24 and t24.points then
		local pts24 = t24.points
		local curHour = t24.curHour or math.floor(nowSec / 3600)
		for idx = #pts24, 1, -1 do
			local pt = pts24[idx]
			if pt and pt.price and pt.price > 0 then
				local dh = math.max(0, curHour - (pt.h or curHour))
				rows[#rows + 1] = {
					when = (dh == 0) and "This hr" or string.format("-%dh", dh),
					price = pt.price,
					qty = pt.qty or 0,
					vel = pt.salesPerDay,
					source = t24.source or "24h",
				}
			end
		end
	end
	return rows, t7, t24
end

local function buildUI()
	if initialized then return end
	initialized = true
	installBagPickupHook()

	local ahf = _G.AuctionHouseFrame
	local parentFrame = isWidgetFrame(ahf) and ahf or UIParent
	tabFrame = CreateFrame("Frame", "MerchantMasterAHSellTabFrame", parentFrame)
	tabFrame:SetSize(784, 486)
	tabFrame:Hide()
	tabFrame.bgPlate = ns.Theme.NineApple(tabFrame, "glass_r12",
		{ 0.03, 0.08, 0.05, 0.94 },
		{ 0.83, 0.64, 0.24, 0.72 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 10, noSpecular = true })

	AHSellTab.frame = tabFrame
	app.ui = app.ui or {}
	app.ui.ahSellTab = AHSellTab

	-- Top Sale Bar (Spacious Auctionator-style item preview, Qty, Price, Bid, Duration, Rule, Deposit, Post)
	local topBar = CreateFrame("Frame", nil, tabFrame)
	topBar:SetHeight(144)
	topBar:SetPoint("TOPLEFT", tabFrame, "TOPLEFT", 8, -8)
	topBar:SetPoint("TOPRIGHT", tabFrame, "TOPRIGHT", -8, -8)
	topBar.plate = ns.Theme.NineApple(topBar, "glass_r10",
		{ 0.04, 0.12, 0.08, 0.96 },
		{ 0.83, 0.64, 0.24, 0.60 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	AHSellTab.topBar = topBar

	-- Left preview + drag-and-drop socket (indented top header clears WoW AH circular portrait)
	local activeFs = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	activeFs:SetPoint("TOPLEFT", topBar, "TOPLEFT", 52, -8)
	activeFs:SetWidth(142)
	activeFs:SetHeight(18)
	activeFs:SetJustifyH("LEFT")
	activeFs:SetJustifyV("MIDDLE")
	activeFs:SetWordWrap(false)
	applySafeFont(activeFs, 13, "semibold")
	AHSellTab.activeFs = activeFs

	local spotSubFs = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spotSubFs:SetPoint("TOPLEFT", activeFs, "BOTTOMLEFT", 0, -2)
	spotSubFs:SetWidth(142)
	spotSubFs:SetHeight(14)
	spotSubFs:SetJustifyH("LEFT")
	spotSubFs:SetJustifyV("MIDDLE")
	spotSubFs:SetWordWrap(false)
	applySafeFont(spotSubFs, 9.5, "regular")
	AHSellTab.spotSubFs = spotSubFs

	local iconDropBtn = CreateFrame("Button", nil, topBar)
	iconDropBtn:SetSize(56, 56)
	iconDropBtn:SetPoint("TOPLEFT", topBar, "TOPLEFT", 14, -50)
	iconDropBtn.plate = ns.Theme.NineApple(iconDropBtn, "glass_r8",
		{ 0.02, 0.07, 0.05, 0.98 },
		{ 0.83, 0.64, 0.24, 0.90 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	local dropTex = iconDropBtn:CreateTexture(nil, "ARTWORK")
	dropTex:SetPoint("TOPLEFT", iconDropBtn, "TOPLEFT", 5, -5)
	dropTex:SetPoint("BOTTOMRIGHT", iconDropBtn, "BOTTOMRIGHT", -5, 5)
	dropTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	dropTex:SetTexture(ns.QUESTION_ICON or "Interface\\Icons\\INV_Misc_QuestionMark")
	iconDropBtn.tex = dropTex
	local dropCountFs = iconDropBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dropCountFs:SetPoint("BOTTOMRIGHT", iconDropBtn, "BOTTOMRIGHT", -5, 4)
	applySafeFont(dropCountFs, 10, "bold")
	iconDropBtn.countFs = dropCountFs
	AHSellTab.iconDropBtn = iconDropBtn

	local dropHintFs = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dropHintFs:SetPoint("TOPLEFT", iconDropBtn, "TOPRIGHT", 8, -4)
	dropHintFs:SetWidth(116)
	dropHintFs:SetHeight(48)
	dropHintFs:SetJustifyH("LEFT")
	dropHintFs:SetJustifyV("TOP")
	dropHintFs:SetWordWrap(true)
	applySafeFont(dropHintFs, 9, "regular")
	dropHintFs:SetText(palHex("hexMuted", "98989d") .. "Drop bag item here or click from Bags below.|r")
	AHSellTab.dropHintFs = dropHintFs

	if iconDropBtn.SetScript then
		iconDropBtn:SetScript("OnReceiveDrag", function()
			AHSellTab.HandleBagDrop()
		end)
		iconDropBtn:SetScript("OnClick", function()
			local hasCur = (_G.GetCursorInfo and _G.GetCursorInfo() ~= nil)
				or (_G.C_Cursor and _G.C_Cursor.GetCursorItem and _G.C_Cursor.GetCursorItem() ~= nil)
			if hasCur or lastPickedBag ~= nil then
				AHSellTab.HandleBagDrop()
			end
		end)
		iconDropBtn:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			local of = getOrderFlow()
			local sl = of and of.GetState and of.GetState().stages.sell
			local cur = sl and sl.items and sl.items[sl.activeIndex]
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if cur and cur.itemLink and GameTooltip.SetHyperlink then
				pcall(GameTooltip.SetHyperlink, GameTooltip, cur.itemLink)
			elseif cur and cur.itemID and cur.itemID > 0 and GameTooltip.SetItemByID then
				pcall(GameTooltip.SetItemByID, GameTooltip, cur.itemID)
			else
				GameTooltip:AddLine("MM Sell Item Slot", 1.0, 0.85, 0.35)
				GameTooltip:AddLine("Drag a bag item here to stage it for sale.", 0.90, 0.92, 0.94, true)
			end
			if ns.Theme and ns.Theme.LiftTooltip then ns.Theme.LiftTooltip(GameTooltip) end
			GameTooltip:Show()
		end)
		iconDropBtn:SetScript("OnLeave", function()
			if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
		end)
	end
	if topBar.SetScript then
		topBar:SetScript("OnReceiveDrag", function()
			AHSellTab.HandleBagDrop()
		end)
	end

	-- EditBox helpers & state guards
	local suppressSellEditCommit = false
	local qtyBox, priceGBox, priceSBox, priceCBox, bidGBox, bidSBox, bidCBox, bidRow, vQtyBox

	local function parseEditCopper(gBox, sBox, cBox)
		local g = math.max(0, math.floor(tonumber(gBox and gBox:GetText() or "0") or 0))
		local s = math.max(0, math.min(99, math.floor(tonumber(sBox and sBox:GetText() or "0") or 0)))
		local c = math.max(0, math.min(99, math.floor(tonumber(cBox and cBox:GetText() or "0") or 0)))
		return g * 10000 + s * 100 + c
	end

	local function updateSellLiveReadouts()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if not (cur and cur.channel ~= "vendor") then return end
		local isComm = of.IsSellItemCommodity and of.IsSellItemCommodity(cur) or false
		local limit = of.GetSellPostLimit and of.GetSellPostLimit(cur) or 0
		local rawQ = math.max(0, math.floor(tonumber(qtyBox and qtyBox:GetText() or "0") or 0))
		local qty = (limit > 0) and math.min(rawQ, limit) or 0
		local buyout = parseEditCopper(priceGBox, priceSBox, priceCBox)
		local bid = isComm and 0 or parseEditCopper(bidGBox, bidSBox, bidCBox)
		local effUnit = (buyout > 0) and buyout or bid
		local dep = (qty > 0 and of.ComputeSellDeposit) and of.ComputeSellDeposit(cur, sl.duration or 2, qty) or 0
		local tot = qty * effUnit
		local playerMoney = (type(_G.GetMoney) == "function") and tonumber(_G.GetMoney()) or nil
		local lowMoney = (playerMoney ~= nil and dep > playerMoney)
		if AHSellTab.sellDepFs then
			local depCol = lowMoney and palHex("hexDanger", "ff453a") or palHex("hexText", "ffffff")
			local depVal = (dep > 0) and ns.FormatMoneyCompact(dep) or "0c"
			AHSellTab.sellDepFs:SetText(palHex("hexMuted", "98989d") .. "Deposit: |r" .. depCol .. depVal .. "|r")
		end
		if AHSellTab.sellTotalFs then
			local totVal = (tot > 0) and ns.FormatMoneyCompact(tot) or "0c"
			AHSellTab.sellTotalFs:SetText(palHex("hexMuted", "98989d") .. "Total Price: |r" .. palHex("hexGold", "f7d57c") .. totVal .. "|r")
		end
		if AHSellTab.sellMaxBtn then
			AHSellTab.sellMaxBtn:SetEnabled(limit > 0 and rawQ ~= limit)
		end
		if AHSellTab.sellBidHintFs and not isComm then
			if buyout > 0 and bid >= buyout then
				AHSellTab.sellBidHintFs:SetText(palHex("hexDanger", "ff453a") .. "Bid >= BO!|r")
			else
				AHSellTab.sellBidHintFs:SetText(palHex("hexMuted", "98989d") .. "Optional|r")
			end
		end
		if AHSellTab.postBtn and sl.pendingPost == nil then
			local okState = of.GetSellPostButtonState and of.GetSellPostButtonState(sl.activeIndex, {
				qty = qty,
				unitPrice = buyout,
				bidPrice = bid,
			})
			AHSellTab.postBtn:SetEnabled(okState == true)
		end
	end

	local function commitQty()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if not (cur and of.SetSellItemQty) then return end
		local raw = qtyBox and qtyBox:GetText() or ""
		local parsed = tonumber(raw)
		if parsed == nil then return end
		local q = math.max(0, math.floor(parsed + 0.5))
		local curQ = of.GetSellPostQty and of.GetSellPostQty(cur) or (cur.postQty or 0)
		if q == curQ then return end
		of.SetSellItemQty(sl.activeIndex, q)
	end

	local function commitPrimaryPrice()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if not (cur and of.SetSellItemPrice) then return end
		local copper = parseEditCopper(priceGBox, priceSBox, priceCBox)
		local curBuyout = of.ComputeSellUnitPrice and of.ComputeSellUnitPrice(cur) or 0
		if cur.customPrice == nil and copper == curBuyout then return end
		if cur.customPrice ~= nil and copper == cur.customPrice then return end
		of.SetSellItemPrice(sl.activeIndex, copper, nil)
	end

	local function commitBidPrice()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if not (cur and of.SetSellItemBidPrice) then return end
		if of.IsSellItemCommodity and of.IsSellItemCommodity(cur) then return end
		local copper = parseEditCopper(bidGBox, bidSBox, bidCBox)
		local curBid = math.max(0, math.floor(tonumber(cur.bidPrice) or 0))
		if copper == curBid then return end
		of.SetSellItemBidPrice(sl.activeIndex, copper)
	end

	local function commitVendorQty()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if not (cur and of.SetSellItemQty) then return end
		local parsed = tonumber(vQtyBox and vQtyBox:GetText() or "")
		if not parsed or parsed < 1 then return end
		local q = math.floor(parsed + 0.5)
		if q == math.max(0, math.floor(tonumber(cur.remaining) or 0)) then return end
		of.SetSellItemQty(sl.activeIndex, q)
	end

	local function clearSellInputFocus()
		suppressSellEditCommit = true
		for _, bx in ipairs({ qtyBox, priceGBox, priceSBox, priceCBox, bidGBox, bidSBox, bidCBox, vQtyBox }) do
			if bx and bx.ClearFocus then
				bx:ClearFocus()
			end
		end
		suppressSellEditCommit = false
	end

	local function commitSellInputsAndClearFocus()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if cur then
			if cur.channel == "vendor" then
				if vQtyBox and vQtyBox:IsShown() then commitVendorQty() end
			else
				if qtyBox and qtyBox:IsShown() then commitQty() end
				if priceGBox and priceGBox:IsShown() then commitPrimaryPrice() end
				if bidRow and bidRow:IsShown() and bidGBox then commitBidPrice() end
			end
		end
		clearSellInputFocus()
	end
	AHSellTab.clearSellInputFocus = clearSellInputFocus
	AHSellTab.commitSellInputsAndClearFocus = commitSellInputsAndClearFocus

	local function triggerSellPostFromEnter()
		local of = getOrderFlow()
		if not of then return end
		local pa = of.GetSellPrimaryAction and of.GetSellPrimaryAction() or nil
		if not (pa and pa.enabled) then return end
		if pa.action == "confirm" then
			of.ConfirmPendingSellPost()
		elseif pa.action == "confirm_warning" then
			of.ConfirmLowPriceSellPost()
		elseif pa.action == "post_ah" then
			of.PostSellItem()
		end
	end

	local function makeSellEditBox(parentFrame, w, maxChars, onCommit, onEnterPost, onTabNext, onTabPrev)
		local box = CreateFrame("EditBox", nil, parentFrame)
		box:SetSize(w, 24)
		if box.SetAutoFocus then box:SetAutoFocus(false) end
		if box.SetNumeric then box:SetNumeric(true) end
		if box.SetMaxLetters then box:SetMaxLetters(maxChars) end
		if box.SetJustifyH then box:SetJustifyH("RIGHT") end
		if box.SetTextInsets then box:SetTextInsets(5, 5, 0, 0) end
		applySafeFont(box, 11, "semibold")
		box.plate = ns.Theme.NineApple(box, "glass_r8",
			{ 0.02, 0.07, 0.05, 0.96 },
			{ 0.83, 0.64, 0.24, 0.80 },
			{ layer = "BACKGROUND", sub = 0, cornerSize = 5, noSpecular = true })
		if box.SetTextColor then box:SetTextColor(1, 1, 1, 1) end
		if box.SetScript then
			box:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
			box:SetScript("OnEnterPressed", function(self)
				if onCommit then onCommit() end
				suppressSellEditCommit = true
				if self.ClearFocus then self:ClearFocus() end
				suppressSellEditCommit = false
				if onEnterPost then onEnterPost() end
			end)
			box:SetScript("OnEditFocusLost", function()
				if (not suppressSellEditCommit) and onCommit then onCommit() end
			end)
			box:SetScript("OnTextChanged", function(_, isUser)
				if isUser then updateSellLiveReadouts() end
			end)
			box:SetScript("OnTabPressed", function(self)
				if onCommit then onCommit() end
				local shift = (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) == true
				local target = shift and (onTabPrev and onTabPrev()) or (onTabNext and onTabNext())
				suppressSellEditCommit = true
				if target and target.SetFocus and target:IsShown() then
					target:SetFocus()
					if target.HighlightText then target:HighlightText() end
				elseif self.ClearFocus then
					self:ClearFocus()
				end
				suppressSellEditCommit = false
			end)
		end
		return box
	end

	-- Center Sell Form (spacious Qty, Buyout, Bid, and action row)
	local form = CreateFrame("Frame", nil, topBar)
	form:SetPoint("TOPLEFT", topBar, "TOPLEFT", 198, -8)
	form:SetSize(336, 126)
	AHSellTab.sellForm = form

	local qtyRow = CreateFrame("Frame", nil, form)
	qtyRow:SetHeight(24)
	qtyRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, 0)
	qtyRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, 0)

	local qtyLbl = qtyRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	qtyLbl:SetPoint("LEFT", qtyRow, "LEFT", 0, 0)
	qtyLbl:SetWidth(82)
	qtyLbl:SetJustifyH("LEFT")
	applySafeFont(qtyLbl, 10.5, "semibold")
	AHSellTab.sellQtyLbl = qtyLbl

	local qtyMinus = makeFramedBtn(qtyRow, 24, 24, "-", 12)
	qtyMinus:SetPoint("LEFT", qtyLbl, "RIGHT", 4, 0)
	qtyMinus:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if cur and of.SetSellItemQty then
			local q = of.GetSellPostQty(cur)
			of.SetSellItemQty(sl.activeIndex, math.max(1, q - 1))
		end
	end)
	AHSellTab.sellQtyMinus = qtyMinus

	qtyBox = makeSellEditBox(qtyRow, 56, 5, commitQty, triggerSellPostFromEnter,
		function() return priceGBox end, function() return bidCBox end)
	qtyBox:SetPoint("LEFT", qtyMinus, "RIGHT", 4, 0)
	AHSellTab.sellQtyBox = qtyBox

	local qtyPlus = makeFramedBtn(qtyRow, 24, 24, "+", 12)
	qtyPlus:SetPoint("LEFT", qtyBox, "RIGHT", 4, 0)
	qtyPlus:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if cur and of.SetSellItemQty then
			local q, lim = of.GetSellPostQty(cur)
			of.SetSellItemQty(sl.activeIndex, math.min(math.max(1, lim), q + 1))
		end
	end)
	AHSellTab.sellQtyPlus = qtyPlus

	local maxBtn = makeFramedBtn(qtyRow, 52, 24, "Max", 10)
	maxBtn:SetPoint("LEFT", qtyPlus, "RIGHT", 6, 0)
	maxBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.SetSellItemMaxQty then of.SetSellItemMaxQty() end
	end)
	addTip(maxBtn, "Max Stack Count", "Set Quantity to maximum available post count for the selected item.")
	AHSellTab.sellMaxBtn = maxBtn

	local maxInfoFs = qtyRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	maxInfoFs:SetPoint("LEFT", maxBtn, "RIGHT", 8, 0)
	maxInfoFs:SetJustifyH("LEFT")
	applySafeFont(maxInfoFs, 10, "regular")
	AHSellTab.sellMaxInfoFs = maxInfoFs

	-- Buyout / Unit Price row
	local priceRow = CreateFrame("Frame", nil, form)
	priceRow:SetHeight(24)
	priceRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -30)
	priceRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -30)

	local priceLbl = priceRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	priceLbl:SetPoint("LEFT", priceRow, "LEFT", 0, 0)
	priceLbl:SetWidth(82)
	priceLbl:SetJustifyH("LEFT")
	applySafeFont(priceLbl, 10.5, "semibold")
	AHSellTab.sellPriceLbl = priceLbl

	priceGBox = makeSellEditBox(priceRow, 64, 6, commitPrimaryPrice, triggerSellPostFromEnter,
		function() return priceSBox end, function() return qtyBox end)
	priceGBox:SetPoint("LEFT", priceLbl, "RIGHT", 4, 0)
	local pGTag = priceRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pGTag:SetPoint("LEFT", priceGBox, "RIGHT", 3, 0)
	applySafeFont(pGTag, 10, "bold")
	AHSellTab.sellPriceGBox = priceGBox
	AHSellTab.sellPriceGTag = pGTag

	priceSBox = makeSellEditBox(priceRow, 36, 2, commitPrimaryPrice, triggerSellPostFromEnter,
		function() return priceCBox end, function() return priceGBox end)
	priceSBox:SetPoint("LEFT", pGTag, "RIGHT", 6, 0)
	local pSTag = priceRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pSTag:SetPoint("LEFT", priceSBox, "RIGHT", 3, 0)
	applySafeFont(pSTag, 10, "bold")
	AHSellTab.sellPriceSBox = priceSBox
	AHSellTab.sellPriceSTag = pSTag

	priceCBox = makeSellEditBox(priceRow, 36, 2, commitPrimaryPrice, triggerSellPostFromEnter,
		function() return (bidRow and bidRow:IsShown()) and bidGBox or qtyBox end,
		function() return priceSBox end)
	priceCBox:SetPoint("LEFT", pSTag, "RIGHT", 6, 0)
	local pCTag = priceRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pCTag:SetPoint("LEFT", priceCBox, "RIGHT", 3, 0)
	applySafeFont(pCTag, 10, "bold")
	AHSellTab.sellPriceCBox = priceCBox
	AHSellTab.sellPriceCTag = pCTag

	local priceSrcFs = priceRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	priceSrcFs:SetPoint("LEFT", pCTag, "RIGHT", 8, 0)
	priceSrcFs:SetJustifyH("LEFT")
	applySafeFont(priceSrcFs, 9.5, "semibold")
	AHSellTab.sellPriceSrcFs = priceSrcFs

	-- Optional Bid Price row (non-commodities only)
	bidRow = CreateFrame("Frame", nil, form)
	bidRow:SetHeight(24)
	bidRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -60)
	bidRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -60)
	AHSellTab.sellBidRow = bidRow

	local bidLbl = bidRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bidLbl:SetPoint("LEFT", bidRow, "LEFT", 0, 0)
	bidLbl:SetWidth(82)
	bidLbl:SetJustifyH("LEFT")
	applySafeFont(bidLbl, 10.5, "semibold")
	AHSellTab.sellBidLbl = bidLbl

	bidGBox = makeSellEditBox(bidRow, 64, 6, commitBidPrice, triggerSellPostFromEnter,
		function() return bidSBox end, function() return priceCBox end)
	bidGBox:SetPoint("LEFT", bidLbl, "RIGHT", 4, 0)
	local bGTag = bidRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bGTag:SetPoint("LEFT", bidGBox, "RIGHT", 3, 0)
	applySafeFont(bGTag, 10, "bold")
	AHSellTab.sellBidGBox = bidGBox
	AHSellTab.sellBidGTag = bGTag

	bidSBox = makeSellEditBox(bidRow, 36, 2, commitBidPrice, triggerSellPostFromEnter,
		function() return bidCBox end, function() return bidGBox end)
	bidSBox:SetPoint("LEFT", bGTag, "RIGHT", 6, 0)
	local bSTag = bidRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bSTag:SetPoint("LEFT", bidSBox, "RIGHT", 3, 0)
	applySafeFont(bSTag, 10, "bold")
	AHSellTab.sellBidSBox = bidSBox
	AHSellTab.sellBidSTag = bSTag

	bidCBox = makeSellEditBox(bidRow, 36, 2, commitBidPrice, triggerSellPostFromEnter,
		function() return qtyBox end, function() return bidSBox end)
	bidCBox:SetPoint("LEFT", bSTag, "RIGHT", 6, 0)
	local bCTag = bidRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bCTag:SetPoint("LEFT", bidCBox, "RIGHT", 3, 0)
	applySafeFont(bCTag, 10, "bold")
	AHSellTab.sellBidCBox = bidCBox
	AHSellTab.sellBidCTag = bCTag

	local bidHintFs = bidRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bidHintFs:SetPoint("LEFT", bCTag, "RIGHT", 8, 0)
	bidHintFs:SetJustifyH("LEFT")
	applySafeFont(bidHintFs, 9.5, "regular")
	AHSellTab.sellBidHintFs = bidHintFs

	-- Vendor Bar (shown ONLY when active item is routed to Vendor)
	local vendBar = CreateFrame("Frame", nil, topBar)
	vendBar:SetPoint("TOPLEFT", topBar, "TOPLEFT", 198, -12)
	vendBar:SetSize(336, 122)
	vendBar:Hide()
	AHSellTab.sellVendorBar = vendBar

	local vQtyLbl = vendBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vQtyLbl:SetPoint("TOPLEFT", vendBar, "TOPLEFT", 0, -6)
	vQtyLbl:SetWidth(82)
	vQtyLbl:SetJustifyH("LEFT")
	applySafeFont(vQtyLbl, 10.5, "semibold")
	vQtyLbl:SetText("Vendor Qty")

	vQtyBox = makeSellEditBox(vendBar, 56, 5, commitVendorQty, nil, nil, nil)
	vQtyBox:SetPoint("LEFT", vQtyLbl, "RIGHT", 4, 0)
	AHSellTab.vendQtyBox = vQtyBox

	local vMaxBtn = makeFramedBtn(vendBar, 52, 24, "Max", 10)
	vMaxBtn:SetPoint("LEFT", vQtyBox, "RIGHT", 8, 0)
	vMaxBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if cur and of.GetSellPostLimit then
			local lim = of.GetSellPostLimit(cur)
			if lim > 0 then of.SetSellItemQty(sl.activeIndex, lim) end
		end
	end)
	AHSellTab.vendMaxBtn = vMaxBtn

	local vendInfoFs = vendBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vendInfoFs:SetPoint("TOPLEFT", vendBar, "TOPLEFT", 0, -40)
	vendInfoFs:SetPoint("TOPRIGHT", vendBar, "TOPRIGHT", 0, -40)
	vendInfoFs:SetJustifyH("LEFT")
	applySafeFont(vendInfoFs, 10, "regular")
	AHSellTab.vendInfoFs = vendInfoFs

	local vendSellBtn = makeFramedBtn(vendBar, 120, 28, "Sell to Vendor", 10.5)
	vendSellBtn:SetPoint("TOPLEFT", vendBar, "TOPLEFT", 0, -78)
	vendSellBtn:SetScript("OnClick", function()
		commitSellInputsAndClearFocus()
		local of = getOrderFlow()
		if of and of.SellToVendor then of.SellToVendor() end
	end)
	AHSellTab.vendSellBtn = vendSellBtn

	local vendSellAllBtn = makeFramedBtn(vendBar, 120, 28, "Sell All Vendor", 10.5)
	vendSellAllBtn:SetPoint("LEFT", vendSellBtn, "RIGHT", 8, 0)
	vendSellAllBtn:SetScript("OnClick", function()
		commitSellInputsAndClearFocus()
		local of = getOrderFlow()
		if of and of.SellAllToVendor then of.SellAllToVendor() end
	end)
	AHSellTab.vendSellAllBtn = vendSellAllBtn

	-- Action buttons row (Post / Post All / Done / Skip) directly inside Center area
	local postBtn = makeFramedBtn(topBar, 122, 28, "Post", 11, { name = "MerchantMasterSellPostBtn" })
	postBtn:SetPoint("TOPLEFT", topBar, "TOPLEFT", 198, -102)
	postBtn:SetScript("OnClick", function()
		commitSellInputsAndClearFocus()
		local of = getOrderFlow()
		if not of then return end
		local sl = of.GetState and of.GetState().stages.sell
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if cur and cur.channel == "vendor" then
			if of.SellToVendor then of.SellToVendor() end
			return
		end
		local pa = of.GetSellPrimaryAction and of.GetSellPrimaryAction() or nil
		if pa and pa.action == "confirm" then
			of.ConfirmPendingSellPost()
		elseif pa and pa.action == "confirm_warning" then
			of.ConfirmLowPriceSellPost()
		elseif of.PostSellItem then
			of.PostSellItem()
		end
	end)
	addTip(postBtn, "Post Auction (Space)", "Post the selected Quantity at the displayed price. Pressing Spacebar while this tab is open also posts.")
	AHSellTab.postBtn = postBtn

	local postAllBtn = makeFramedBtn(topBar, 82, 28, "Post All", 10.5)
	postAllBtn:SetPoint("LEFT", postBtn, "RIGHT", 6, 0)
	postAllBtn:SetScript("OnClick", function()
		commitSellInputsAndClearFocus()
		local of = getOrderFlow()
		if not of then return end
		local sl = of.GetState and of.GetState().stages.sell
		if sl and sl.warningConfirm and of.CancelPendingSellPost then
			of.CancelPendingSellPost("clear")
			return
		end
		if sl and (sl.pendingPost ~= nil or sl.postAllActive) and of.CancelPendingSellPost then
			of.CancelPendingSellPost("user_cancel")
			return
		end
		local cur = sl and sl.items and sl.items[sl.activeIndex]
		if cur and cur.channel == "vendor" then
			if of.SellAllToVendor then of.SellAllToVendor() end
		elseif of.PostAllNext then
			of.PostAllNext()
		end
	end)
	addTip(postAllBtn, "Post All / Cancel", "Post remaining pending AH items in the Sell Queue one after another, or cancel an active post.")
	AHSellTab.postAllBtn = postAllBtn

	local doneBtn = makeFramedBtn(topBar, 58, 28, "Done", 10)
	doneBtn:SetPoint("LEFT", postAllBtn, "RIGHT", 6, 0)
	doneBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.MarkSellDone then of.MarkSellDone() end
	end)
	AHSellTab.doneBtn = doneBtn

	local skipBtn = makeFramedBtn(topBar, 56, 28, "Skip", 10)
	skipBtn:SetPoint("LEFT", doneBtn, "RIGHT", 6, 0)
	skipBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.SkipSellItem then of.SkipSellItem() end
	end)
	AHSellTab.skipBtn = skipBtn

	-- Right column of Top Sale Bar: Refresh, Duration (2h/8h/24h), Rule, Channel, Deposit, Total Price
	local refreshBtn = makeFramedBtn(topBar, 64, 20, "Refresh", 9.5)
	refreshBtn:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -10, -8)
	refreshBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.RefreshSellSearch then of.RefreshSellSearch() end
	end)
	addTip(refreshBtn, "Refresh Live Prices", "Re-scan live Auction House prices for the selected or last posted item.")
	AHSellTab.sellRefreshBtn = refreshBtn

	local durLbl = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	durLbl:SetPoint("TOPLEFT", topBar, "TOPRIGHT", -222, -10)
	durLbl:SetJustifyH("LEFT")
	applySafeFont(durLbl, 10, "semibold")
	AHSellTab.sellDurLbl = durLbl

	local durBtns = {}
	for dIdx = 1, 3 do
		local db = makeFramedBtn(topBar, 38, 22, SELL_DUR_LABELS[dIdx], 9.5)
		if dIdx == 1 then
			db:SetPoint("TOPLEFT", topBar, "TOPRIGHT", -222, -34)
		else
			db:SetPoint("LEFT", durBtns[dIdx - 1], "RIGHT", 4, 0)
		end
		db:SetScript("OnClick", function()
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.SetSellDuration then of.SetSellDuration(dIdx) end
		end)
		durBtns[dIdx] = db
	end
	AHSellTab.sellDurBtns = durBtns

	local chBtn = makeFramedBtn(topBar, 82, 22, "Sell: AH", 9.5)
	chBtn:SetPoint("LEFT", durBtns[3], "RIGHT", 8, 0)
	chBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.ToggleSellItemChannel then of.ToggleSellItemChannel() end
	end)
	addTip(chBtn, "Switch Channel", "Toggle the selected item between posting on the Auction House and selling to a Vendor.")
	AHSellTab.sellChBtn = chBtn

	local ucBtn = makeFramedBtn(topBar, 104, 22, "Rule: Match", 9.5)
	ucBtn:SetPoint("TOPLEFT", durBtns[1], "BOTTOMLEFT", 0, -6)
	ucBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.CycleSellUndercutMode then of.CycleSellUndercutMode() end
	end)
	addTip(ucBtn, "Undercut Rule", "Cycle pricing rule: Match (0% LIFO), -1c, -1s, or -1%.")
	AHSellTab.sellUcBtn = ucBtn

	local depFs = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	depFs:SetPoint("TOPLEFT", ucBtn, "BOTTOMLEFT", 0, -8)
	depFs:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -10, -92)
	depFs:SetJustifyH("LEFT")
	applySafeFont(depFs, 10, "semibold")
	AHSellTab.sellDepFs = depFs

	local totalFs = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	totalFs:SetPoint("TOPLEFT", depFs, "BOTTOMLEFT", 0, -4)
	totalFs:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -10, -112)
	totalFs:SetJustifyH("LEFT")
	applySafeFont(totalFs, 10.5, "semibold")
	AHSellTab.sellTotalFs = totalFs

	-- Notice Banner directly under Top Sale Bar
	local noticeBar = CreateFrame("Frame", nil, tabFrame)
	noticeBar:SetHeight(20)
	noticeBar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
	noticeBar:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -4)
	noticeBar.plate = ns.Theme.NineApple(noticeBar, "glass_r8",
		{ 0.08, 0.16, 0.22, 0.92 },
		{ 0.34, 0.83, 0.91, 0.75 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
	local noticeFs = noticeBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	noticeFs:SetPoint("LEFT", noticeBar, "LEFT", 8, 0)
	noticeFs:SetPoint("RIGHT", noticeBar, "RIGHT", -8, 0)
	noticeFs:SetJustifyH("LEFT")
	noticeFs:SetWordWrap(false)
	applySafeFont(noticeFs, 9.5, "semibold")
	noticeBar:Hide()
	AHSellTab.noticeBar = noticeBar
	AHSellTab.noticeFs = noticeFs

	-- Bottom-Left Categorized Bag Pane (Auctionator-style grouped icons)
	local bagPane = CreateFrame("Frame", nil, tabFrame)
	bagPane:SetWidth(234)
	bagPane:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -8)
	bagPane:SetPoint("BOTTOMLEFT", tabFrame, "BOTTOMLEFT", 10, 10)
	bagPane.plate = ns.Theme.NineApple(bagPane, "glass_r10",
		{ 0.03, 0.09, 0.06, 0.95 },
		{ 0.83, 0.64, 0.24, 0.50 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	AHSellTab.sellBagPane = bagPane

	local bagHdrFs = bagPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bagHdrFs:SetPoint("TOPLEFT", bagPane, "TOPLEFT", 10, -8)
	applySafeFont(bagHdrFs, 10.5, "semibold")
	bagHdrFs:SetText("BAGS")
	AHSellTab.sellBagHdrFs = bagHdrFs

	local bagCountFs = bagPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bagCountFs:SetPoint("TOPRIGHT", bagPane, "TOPRIGHT", -10, -8)
	applySafeFont(bagCountFs, 9.5, "semibold")
	AHSellTab.sellBagCountFs = bagCountFs

	local bagHintFs = bagPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bagHintFs:SetPoint("TOPLEFT", bagPane, "TOPLEFT", 10, -23)
	bagHintFs:SetPoint("TOPRIGHT", bagPane, "TOPRIGHT", -10, -23)
	bagHintFs:SetJustifyH("LEFT")
	bagHintFs:SetWordWrap(false)
	applySafeFont(bagHintFs, 9, "regular")
	bagHintFs:SetText("Left: AH  |  Right: Vendor  |  Drag to top")

	local bagGrid = CreateFrame("Frame", nil, bagPane)
	bagGrid:SetPoint("TOPLEFT", bagPane, "TOPLEFT", 8, -38)
	bagGrid:SetPoint("BOTTOMRIGHT", bagPane, "BOTTOMRIGHT", -6, 8)
	AHSellTab.sellBagGrid = bagGrid

	local function stepBagScroll(delta)
		local visLayCount = getBagVisibleLayoutCount()
		local maxOff = math.max(0, #bagLayoutCache - visLayCount)
		bagScrollOffset = math.max(0, math.min(maxOff, bagScrollOffset - (delta > 0 and 1 or -1)))
		AHSellTab.Render()
	end
	if bagGrid.EnableMouseWheel then bagGrid:EnableMouseWheel(true) end
	bagGrid:SetScript("OnMouseWheel", function(_, delta) stepBagScroll(delta) end)
	local bagScroll = makeBaronScrollbar(bagGrid, stepBagScroll)
	AHSellTab.sellBagScroll = bagScroll

	local bagCatHdrs = {}
	for i = 1, 10 do
		local h = bagGrid:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		h:SetJustifyH("LEFT")
		h:SetWordWrap(false)
		applySafeFont(h, 9.5, "semibold")
		h:Hide()
		bagCatHdrs[i] = h
	end
	AHSellTab.sellBagCatHdrs = bagCatHdrs

	local bagTiles = {}
	for i = 1, 45 do
		local tile = CreateFrame("Button", nil, bagGrid)
		tile:SetSize(BAG_TILE_SZ, BAG_TILE_SZ)
		tile.plate = ns.Theme.NineApple(tile, "glass_r8",
			{ 0.04, 0.11, 0.08, 0.92 },
			{ 0.83, 0.64, 0.24, 0.45 },
			{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
		local tex = tile:CreateTexture(nil, "ARTWORK")
		tex:SetPoint("TOPLEFT", tile, "TOPLEFT", 3, -3)
		tex:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -3, 3)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		tile.tex = tex
		local cntFs = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cntFs:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -3, 2)
		applySafeFont(cntFs, 9, "bold")
		tile.cntFs = cntFs
		if tile.RegisterForClicks then tile:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
		tile:SetScript("OnClick", function(self, mouseBtn)
			local rec = self._bagRec
			if not rec then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if not (of and of.AddBagItemToSell) then return end
			if mouseBtn == "RightButton" then
				of.AddBagItemToSell(rec.itemID, rec.totalCount, {
					channel = "vendor",
					itemLink = rec.itemLink,
					name = rec.name,
					classID = rec.classID,
					itemLevel = rec.itemLevel,
					quality = rec.quality,
				})
			else
				of.AddBagItemToSell(rec.itemID, nil, {
					channel = rec.ahValid and "ah" or "vendor",
					itemLink = rec.itemLink,
					name = rec.name,
					classID = rec.classID,
					itemLevel = rec.itemLevel,
					quality = rec.quality,
					useDefaultQty = true,
				})
			end
		end)
		tile:SetScript("OnEnter", function(self)
			local rec = self._bagRec
			if not (rec and GameTooltip) then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if rec.itemLink and GameTooltip.SetHyperlink then
				pcall(GameTooltip.SetHyperlink, GameTooltip, rec.itemLink)
			else
				GameTooltip:AddLine(tostring(rec.name or "Item"), getQualityRGB(rec.quality))
			end
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine(string.format("In Bags: %dx (%s)", rec.totalCount or 1, rec.className or "Misc"), 0.85, 0.88, 0.92)
			if rec.ahValid then
				GameTooltip:AddLine("Left-Click: Select / Stage for AH", 0.30, 0.92, 0.56)
			end
			if (rec.vendorSell or 0) > 0 then
				GameTooltip:AddLine("Right-Click: Stage for Vendor (" .. ns.FormatMoneyCompact(rec.vendorSell) .. " ea)", 0.98, 0.82, 0.38)
			end
			if ns.Theme and ns.Theme.LiftTooltip then ns.Theme.LiftTooltip(GameTooltip) end
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", function()
			if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
		end)
		tile:Hide()
		bagTiles[i] = tile
	end
	AHSellTab.sellBagTiles = bagTiles

	-- Bottom-Right Spacious Tabbed Panel (Current Prices / Sell Queue / Price History)
	local pricesBox = CreateFrame("Frame", nil, tabFrame)
	pricesBox:SetPoint("TOPLEFT", bagPane, "TOPRIGHT", 10, 0)
	pricesBox:SetPoint("BOTTOMRIGHT", tabFrame, "BOTTOMRIGHT", -10, 38)
	local pricesPlate = ns.Theme.NineApple(pricesBox, "glass_r10",
		{ 0.03, 0.09, 0.06, 0.95 },
		{ 0.83, 0.64, 0.24, 0.54 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	AHSellTab.sellPricesBox = pricesBox
	AHSellTab.sellPricesPlate = pricesPlate

	-- Sub-Tab 1: Current Prices
	local pricesView = CreateFrame("Frame", nil, pricesBox)
	pricesView:SetAllPoints(pricesBox)
	AHSellTab.sellPricesView = pricesView

	local pHdr = CreateFrame("Frame", nil, pricesView)
	pHdr:SetPoint("TOPLEFT", pricesView, "TOPLEFT", 10, -6)
	pHdr:SetPoint("TOPRIGHT", pricesView, "TOPRIGHT", -10, -6)
	pHdr:SetHeight(20)
	local pHdrSep = pricesView:CreateTexture(nil, "ARTWORK")
	pHdrSep:SetPoint("TOPLEFT", pHdr, "BOTTOMLEFT", 0, 0)
	pHdrSep:SetPoint("TOPRIGHT", pHdr, "BOTTOMRIGHT", 0, 0)
	pHdrSep:SetHeight(1)
	AHSellTab.sellPricesHdrSep = pHdrSep

	local function makeColHdr(txt, align)
		local fs = pHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH(align or "LEFT")
		fs:SetJustifyV("MIDDLE")
		fs:SetWordWrap(false)
		applySafeFont(fs, 9.5, "semibold")
		fs:SetText(txt)
		return fs
	end
	local pCol1 = makeColHdr("Unit Price", "LEFT")
	local pCol2 = makeColHdr("Bid", "LEFT")
	local pCol3 = makeColHdr("Avail", "RIGHT")
	local pCol4 = makeColHdr("You?", "RIGHT")
	pCol4:SetPoint("RIGHT", pHdr, "RIGHT", -6, 0)
	pCol4:SetWidth(54)
	AHSellTab.sellPricesCol1 = pCol1
	AHSellTab.sellPricesCol2 = pCol2
	AHSellTab.sellPricesCol3 = pCol3
	AHSellTab.sellPricesCol4 = pCol4

	local pListArea = CreateFrame("Frame", nil, pricesView)
	pListArea:SetPoint("TOPLEFT", pHdr, "BOTTOMLEFT", 0, -2)
	pListArea:SetPoint("BOTTOMRIGHT", pricesView, "BOTTOMRIGHT", -10, 6)
	AHSellTab.sellPricesListArea = pListArea

	local pEmptyFs = pListArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pEmptyFs:SetPoint("CENTER", pListArea, "CENTER", 0, 0)
	pEmptyFs:SetJustifyH("CENTER")
	applySafeFont(pEmptyFs, 10.5, "semibold")
	pEmptyFs:Hide()
	AHSellTab.sellPricesEmptyFs = pEmptyFs

	local function stepPricesScroll(delta)
		local list = getCurrentSellListings()
		local visRows = getVisibleRowCount(pListArea, SELL_PRICES_ROW_H, SELL_PRICES_VISIBLE_ROWS, 3)
		local maxOff = math.max(0, #list - visRows)
		pricesScrollOffset = math.max(0, math.min(maxOff, pricesScrollOffset - (delta > 0 and 1 or -1)))
		AHSellTab.Render()
	end
	if pListArea.EnableMouseWheel then pListArea:EnableMouseWheel(true) end
	pListArea:SetScript("OnMouseWheel", function(_, delta) stepPricesScroll(delta) end)
	local pScroll = makeBaronScrollbar(pListArea, stepPricesScroll)
	AHSellTab.sellPricesScroll = pScroll

	local pRows = {}
	for i = 1, SELL_PRICES_VISIBLE_ROWS do
		local pr = CreateFrame("Button", nil, pListArea)
		pr:SetHeight(SELL_PRICES_ROW_H)
		pr.bg = pr:CreateTexture(nil, "BACKGROUND")
		pr.bg:SetAllPoints()
		local function makeCell(align)
			local fs = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetJustifyH(align or "LEFT")
			fs:SetJustifyV("MIDDLE")
			fs:SetWordWrap(false)
			applySafeFont(fs, 10, "regular")
			return fs
		end
		pr.c1 = makeCell("LEFT")
		pr.c2 = makeCell("LEFT")
		pr.c3 = makeCell("RIGHT")
		pr.c4 = makeCell("RIGHT")
		pr.c4:SetPoint("RIGHT", pr, "RIGHT", -6, 0)
		pr.c4:SetWidth(54)
		pr:SetScript("OnClick", function(self)
			if not self._listing then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.SelectSellListingPrice then
				local exact = (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) == true
				of.SelectSellListingPrice(self._listing, exact)
			end
		end)
		pr:SetScript("OnEnter", function(self)
			if not (self._listing and GameTooltip) then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			if self._listing.containsOwnerItem then
				GameTooltip:AddLine("Your Auction Listing", 0.30, 0.92, 0.56)
				GameTooltip:AddLine("Click: Match your price", 0.90, 0.92, 0.94)
			else
				GameTooltip:AddLine("Click: Undercut using Rule", 1.0, 0.85, 0.35)
				GameTooltip:AddLine("Shift-Click: Match exact price", 0.72, 0.86, 1.0)
			end
			if ns.Theme and ns.Theme.LiftTooltip then ns.Theme.LiftTooltip(GameTooltip) end
			GameTooltip:Show()
		end)
		pr:SetScript("OnLeave", function()
			if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
		end)
		pr:Hide()
		pRows[i] = pr
	end
	AHSellTab.sellPricesRows = pRows

	-- Sub-Tab 2: Sell Queue
	local queueView = CreateFrame("Frame", nil, pricesBox)
	queueView:SetAllPoints(pricesBox)
	queueView:Hide()
	AHSellTab.sellQueueView = queueView

	local qHdr = CreateFrame("Frame", nil, queueView)
	qHdr:SetPoint("TOPLEFT", queueView, "TOPLEFT", 10, -6)
	qHdr:SetPoint("TOPRIGHT", queueView, "TOPRIGHT", -10, -6)
	qHdr:SetHeight(24)

	local qHdrFs = qHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	qHdrFs:SetPoint("LEFT", qHdr, "LEFT", 2, 0)
	qHdrFs:SetJustifyH("LEFT")
	applySafeFont(qHdrFs, 10, "semibold")
	AHSellTab.sellQueueHdrFs = qHdrFs

	local qClearBtn = makeFramedBtn(qHdr, 56, 20, "Clear", 9.5)
	qClearBtn:SetPoint("RIGHT", qHdr, "RIGHT", 0, 0)
	qClearBtn:SetScript("OnClick", function()
		clearSellInputFocus()
		local of = getOrderFlow()
		if of and of.ClearSellQueue then of.ClearSellQueue() end
	end)
	AHSellTab.sellQueueClearBtn = qClearBtn

	local qListArea = CreateFrame("Frame", nil, queueView)
	qListArea:SetPoint("TOPLEFT", qHdr, "BOTTOMLEFT", 0, -4)
	qListArea:SetPoint("BOTTOMRIGHT", queueView, "BOTTOMRIGHT", -10, 6)
	AHSellTab.sellQueueListArea = qListArea

	local qEmptyFs = qListArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	qEmptyFs:SetPoint("CENTER", qListArea, "CENTER", 0, 0)
	qEmptyFs:SetJustifyH("CENTER")
	applySafeFont(qEmptyFs, 10.5, "regular")
	qEmptyFs:SetText(palHex("hexMuted", "98989d") .. "Sell Queue is empty. Click items on the left or drag to top.|r")
	qEmptyFs:Hide()
	AHSellTab.sellQueueEmptyFs = qEmptyFs

	local function stepQueueScroll(delta)
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local total = sl and #(sl.items or {}) or 0
		local visRows = getVisibleRowCount(qListArea, SELL_QUEUE_ROW_H, SELL_QUEUE_VISIBLE_ROWS, 3)
		local maxOff = math.max(0, total - visRows)
		queueScrollOffset = math.max(0, math.min(maxOff, queueScrollOffset - (delta > 0 and 1 or -1)))
		AHSellTab.Render()
	end
	if qListArea.EnableMouseWheel then qListArea:EnableMouseWheel(true) end
	qListArea:SetScript("OnMouseWheel", function(_, delta) stepQueueScroll(delta) end)
	local qScroll = makeBaronScrollbar(qListArea, stepQueueScroll)
	AHSellTab.sellQueueScroll = qScroll

	local qRows = {}
	for i = 1, SELL_QUEUE_VISIBLE_ROWS do
		local qr = CreateFrame("Button", nil, qListArea)
		qr:SetHeight(SELL_QUEUE_ROW_H)
		qr.bg = qr:CreateTexture(nil, "BACKGROUND")
		qr.bg:SetAllPoints()

		qr.icon = qr:CreateTexture(nil, "ARTWORK")
		qr.icon:SetSize(20, 20)
		qr.icon:SetPoint("LEFT", qr, "LEFT", 4, 0)
		qr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		qr.nameFs = qr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qr.nameFs:SetPoint("LEFT", qr.icon, "RIGHT", 6, 0)
		qr.nameFs:SetWidth(206)
		qr.nameFs:SetJustifyH("LEFT")
		qr.nameFs:SetWordWrap(false)
		applySafeFont(qr.nameFs, 10, "semibold")

		qr.qtyFs = qr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qr.qtyFs:SetPoint("LEFT", qr.nameFs, "RIGHT", 6, 0)
		qr.qtyFs:SetWidth(58)
		qr.qtyFs:SetJustifyH("RIGHT")
		applySafeFont(qr.qtyFs, 9.5, "regular")

		qr.priceFs = qr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qr.priceFs:SetPoint("LEFT", qr.qtyFs, "RIGHT", 8, 0)
		qr.priceFs:SetWidth(86)
		qr.priceFs:SetJustifyH("RIGHT")
		applySafeFont(qr.priceFs, 9.5, "semibold")

		qr.removeBtn = makeFramedBtn(qr, 20, 20, "X", 9)
		qr.removeBtn:SetPoint("RIGHT", qr, "RIGHT", -2, 0)
		qr.removeBtn:SetScript("OnClick", function()
			if not qr._itemIndex then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.RemoveSellItem then of.RemoveSellItem(qr._itemIndex) end
		end)

		qr.chBtn = makeFramedBtn(qr, 46, 20, "AH", 8.5)
		qr.chBtn:SetPoint("RIGHT", qr.removeBtn, "LEFT", -6, 0)
		qr.chBtn:SetScript("OnClick", function()
			if not qr._itemIndex then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.ToggleSellItemChannel then of.ToggleSellItemChannel(qr._itemIndex) end
		end)

		qr:SetScript("OnClick", function(self)
			if not self._itemIndex then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.SelectSellItem then of.SelectSellItem(self._itemIndex) end
		end)
		qr:Hide()
		qRows[i] = qr
	end
	AHSellTab.sellQueueRows = qRows

	-- Sub-Tab 3: Price History
	local histView = CreateFrame("Frame", nil, pricesBox)
	histView:SetAllPoints(pricesBox)
	histView:Hide()
	AHSellTab.sellHistoryView = histView

	local hSummaryFs = histView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hSummaryFs:SetPoint("TOPLEFT", histView, "TOPLEFT", 12, -8)
	hSummaryFs:SetPoint("TOPRIGHT", histView, "TOPRIGHT", -12, -8)
	hSummaryFs:SetJustifyH("LEFT")
	hSummaryFs:SetWordWrap(false)
	applySafeFont(hSummaryFs, 10, "semibold")
	AHSellTab.sellHistorySummaryFs = hSummaryFs

	local hListArea = CreateFrame("Frame", nil, histView)
	hListArea:SetPoint("TOPLEFT", histView, "TOPLEFT", 10, -28)
	hListArea:SetPoint("BOTTOMRIGHT", histView, "BOTTOMRIGHT", -10, 6)
	AHSellTab.sellHistoryListArea = hListArea

	local hEmptyFs = hListArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hEmptyFs:SetPoint("CENTER", hListArea, "CENTER", 0, 0)
	hEmptyFs:SetJustifyH("CENTER")
	applySafeFont(hEmptyFs, 10.5, "regular")
	hEmptyFs:Hide()
	AHSellTab.sellHistoryEmptyFs = hEmptyFs

	local function stepHistoryScroll(delta)
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell
		local target = (sl and sl.items and sl.items[sl.activeIndex]) or (sl and sl.lastItemInfo)
		local rows = getHistoryRowsData(target)
		local visRows = getVisibleRowCount(hListArea, SELL_HISTORY_ROW_H, SELL_HISTORY_VISIBLE_ROWS, 3)
		local maxOff = math.max(0, #rows - visRows)
		historyScrollOffset = math.max(0, math.min(maxOff, historyScrollOffset - (delta > 0 and 1 or -1)))
		AHSellTab.Render()
	end
	if hListArea.EnableMouseWheel then hListArea:EnableMouseWheel(true) end
	hListArea:SetScript("OnMouseWheel", function(_, delta) stepHistoryScroll(delta) end)
	local hScroll = makeBaronScrollbar(hListArea, stepHistoryScroll)
	AHSellTab.sellHistoryScroll = hScroll

	local hRows = {}
	for i = 1, SELL_HISTORY_VISIBLE_ROWS do
		local hr = CreateFrame("Frame", nil, hListArea)
		hr:SetHeight(SELL_HISTORY_ROW_H)
		hr.bg = hr:CreateTexture(nil, "BACKGROUND")
		hr.bg:SetAllPoints()
		local function mk(x, w, align)
			local fs = hr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", hr, "LEFT", x, 0)
			fs:SetWidth(w)
			fs:SetJustifyH(align or "LEFT")
			fs:SetWordWrap(false)
			applySafeFont(fs, 10, "regular")
			return fs
		end
		hr.c1 = mk(4, 72, "LEFT")
		hr.c2 = mk(82, 134, "RIGHT")
		hr.c3 = mk(226, 76, "RIGHT")
		hr.c4 = mk(312, 96, "RIGHT")
		hr.c5 = mk(414, 72, "RIGHT")
		hr:Hide()
		hRows[i] = hr
	end
	AHSellTab.sellHistoryRows = hRows

	-- Bottom Mini-Tabs beneath Right Panel (Current Prices / Sell Queue / Price History)
	local subTabBtns = {}
	local subSpecs = {
		{ key = "prices", label = "Current Prices", w = 116 },
		{ key = "queue", label = "Sell Queue", w = 110 },
		{ key = "history", label = "Price History", w = 112 },
	}
	for idx, spec in ipairs(subSpecs) do
		local b = makeFramedBtn(tabFrame, spec.w, 24, spec.label, 10)
		if idx == 1 then
			b:SetPoint("TOPLEFT", pricesBox, "BOTTOMLEFT", 6, -4)
		else
			b:SetPoint("LEFT", subTabBtns[subSpecs[idx - 1].key], "RIGHT", 6, 0)
		end
		b:SetScript("OnClick", function()
			clearSellInputFocus()
			AHSellTab.SetSubTab(spec.key)
		end)
		subTabBtns[spec.key] = b
	end
	AHSellTab.subTabBtns = subTabBtns
	if ns.Theme and ns.Theme.RegisterWidget then
		ns.Theme.RegisterWidget(tabFrame, function()
			if AHSellTab.IsShown() then AHSellTab.Render() end
		end)
	end
end

function AHSellTab.SetSubTab(key)
	if key ~= "prices" and key ~= "queue" and key ~= "history" then return false end
	activeSubTab = key
	AHSellTab.activeSubTab = key
	AHSellTab.Render()
	return true
end

function AHSellTab.HandleBagDrop(bag, slot)
	if not initialized then buildUI() end
	local of = getOrderFlow()
	if not (of and of.AddCursorItemToSell) then return false, "no_api" end
	local b, s = bag, slot
	local hasCursor = (_G.GetCursorInfo and _G.GetCursorInfo() ~= nil)
		or (_G.C_Cursor and _G.C_Cursor.GetCursorItem and _G.C_Cursor.GetCursorItem() ~= nil)
	if b == nil or s == nil then
		if (_G.C_Cursor and _G.C_Cursor.GetCursorItem) then
			local loc = _G.C_Cursor.GetCursorItem()
			if type(loc) == "table" and loc.GetBagAndSlot then
				local okBS, lb, ls = pcall(loc.GetBagAndSlot, loc)
				if okBS and lb ~= nil and ls ~= nil then
					b, s = lb, ls
				end
			elseif type(loc) == "table" and loc.bagID ~= nil and loc.slotIndex ~= nil then
				b, s = loc.bagID, loc.slotIndex
			end
		end
		if (b == nil or s == nil) and hasCursor and lastPickedBag ~= nil and lastPickedSlot ~= nil then
			b, s = lastPickedBag, lastPickedSlot
		end
	end
	lastPickedBag, lastPickedSlot = nil, nil
	local ok, res = of.AddCursorItemToSell(b, s)
	AHSellTab.Render()
	AHSellTab.SyncSpaceBinding()
	return ok, res
end

function AHSellTab.EnsureAttached()
	if not initialized then buildUI() end
	local ahf = _G.AuctionHouseFrame
	if not ahf then return false end
	local ahIsFrame = isWidgetFrame(ahf)
	if isHostAHFull() then
		if attachedHost ~= nil and attachedHost ~= ahf and AHSellTab._fallbackLib then
			AHSellTab._fallbackLib.internalState = nil
		end
		local lib = ensureLibAHTab()
		if lib then
			if (attachedHost ~= ahf or attachedLib ~= lib or not lib:DoesIDExist(SELL_TAB_ID)) then
				attachedHost = ahf
				attachedLib = lib
				if ahIsFrame then
					if tabFrame.SetParent then tabFrame:SetParent(ahf) end
					if tabFrame.SetFrameLevel and ahf.GetFrameLevel then
						tabFrame:SetFrameLevel((ahf:GetFrameLevel() or 1) + 5)
					end
				end
				tabFrame:ClearAllPoints()
				tabFrame:SetPoint("TOPLEFT", ahf, "TOPLEFT", 6, -24)
				tabFrame:SetPoint("BOTTOMRIGHT", ahf, "BOTTOMRIGHT", -6, 28)
				if not lib:DoesIDExist(SELL_TAB_ID) then
					lib:CreateTab(SELL_TAB_ID, tabFrame, SELL_TAB_LABEL, SELL_TAB_HEADER)
				end
				tabBtn = (lib.GetButton and lib:GetButton(SELL_TAB_ID)) or _G["LibAHFrame-1.0-" .. SELL_TAB_ID]
				AHSellTab.tabButton = tabBtn
				if tabFrame.HookScript and not tabFrame._mmHooksInstalled then
					tabFrame._mmHooksInstalled = true
					tabFrame:HookScript("OnShow", function()
						local of = getOrderFlow()
						if of then
							local sl = of.GetState and of.GetState().stages.sell
							local cur = sl and sl.items and sl.items[sl.activeIndex]
							if cur and cur.channel == "ah" and (cur.remaining or 0) > 0
								and cur.status ~= "done" and cur.status ~= "skipped"
								and not cur.listingsScanned and of.ScanSellItemMarket then
								of.ScanSellItemMarket(sl.activeIndex, "select")
							end
						end
						AHSellTab.Render()
						AHSellTab.SyncSpaceBinding()
					end)
					tabFrame:HookScript("OnHide", function()
						AHSellTab.SyncSpaceBinding(true)
					end)
				end
			end
			return true
		end
	end
	-- Lightweight mock / non-Tabs AuctionHouseFrame fallback
	if ahIsFrame then
		if tabFrame.SetParent then tabFrame:SetParent(ahf) end
		if tabFrame.SetFrameLevel and ahf.GetFrameLevel then
			tabFrame:SetFrameLevel((ahf:GetFrameLevel() or 1) + 5)
		end
	end
	if not tabBtn then
		local parentForBtn = ahIsFrame and ahf or UIParent
		tabBtn = CreateFrame("Button", "LibAHFrame-1.0-" .. SELL_TAB_ID, parentForBtn)
		tabBtn:SetSize(84, 28)
		tabBtn:SetText(SELL_TAB_LABEL)
		tabBtn:SetScript("OnClick", function()
			AHSellTab.SelectTab()
		end)
		AHSellTab.tabButton = tabBtn
	end
	return true
end

function AHSellTab.SelectTab()
	AHSellTab.EnsureAttached()
	local ahf = _G.AuctionHouseFrame
	if isHostAHFull() and attachedLib and attachedLib.SetSelected and attachedLib:DoesIDExist(SELL_TAB_ID) then
		attachedLib:SetSelected(SELL_TAB_ID)
	else
		if ahf and ahf.SetDisplayMode then
			ahf:SetDisplayMode({})
			ahf.displayMode = nil
		end
		if tabFrame then tabFrame:Show() end
	end
	local of = getOrderFlow()
	if of then
		local sl = of.GetState and of.GetState().stages.sell
		if sl and sl.items then
			local cur = sl.items[sl.activeIndex]
			if cur and cur.channel == "ah" and (cur.remaining or 0) > 0
				and cur.status ~= "done" and cur.status ~= "skipped"
				and not cur.listingsScanned and of.ScanSellItemMarket then
				of.ScanSellItemMarket(sl.activeIndex, "select")
			end
		end
	end
	AHSellTab.Render()
	AHSellTab.SyncSpaceBinding()
	return true
end

function AHSellTab.HideTab()
	if tabFrame and tabFrame:IsShown() then
		tabFrame:Hide()
	end
	AHSellTab.SyncSpaceBinding(true)
end

function AHSellTab.OnAuctionHouseClosed()
	AHSellTab.HideTab()
end

function AHSellTab.OnStateUpdated()
	if not initialized then return end
	if AHSellTab.IsShown() then
		AHSellTab.Render()
		AHSellTab.SyncSpaceBinding()
	end
end

function AHSellTab.Render()
	if not initialized then buildUI() end
	if not tabFrame then return end

	local of = getOrderFlow()
	local st = of and of.GetState and of.GetState() or {}
	local sl = st.stages and st.stages.sell or { items = {}, activeIndex = 1, duration = 2, undercutMode = "match" }
	local items = sl.items or {}
	local cur = items[sl.activeIndex]
	local inAH = isAHOpensafe()
	local isLight = isLightTheme()
	local pal = getPal()

	local goldBorder = { 0.83, 0.64, 0.24 }
	local subtleBorder = isLight and { 0.00, 0.00, 0.00, 0.14 } or { 0.83, 0.64, 0.24, 0.35 }
	local accentGreen = isLight and { 0.00, 0.48, 0.22 } or { 0.18, 0.72, 0.44 }
	local sepCol = isLight and { 0.00, 0.00, 0.00 } or goldBorder
	local btnInactFill = isLight and { 0.90, 0.92, 0.96, 1.0 } or { 0.05, 0.13, 0.09, 0.92 }
	local btnInactText = isLight and { 0.12, 0.15, 0.19, 1.0 } or { 0.94, 0.92, 0.88, 1.0 }
	local btnActFill = isLight and { 0.00, 0.48, 0.22, 1.0 } or { 0.10, 0.40, 0.24, 0.98 }
	local btnActStroke = isLight and { 0.00, 0.36, 0.16, 1.0 } or { 0.24, 0.95, 0.56, 0.95 }
	local btnActText = { 1.0, 1.0, 1.0, 1.0 }
	local boxFill = isLight and { 0.98, 0.99, 1.00, 1.0 } or { 0.02, 0.07, 0.05, 0.96 }
	local boxStroke = isLight and { 0.60, 0.65, 0.74, 0.90 } or { 0.83, 0.64, 0.24, 0.80 }
	local boxInk = isLight and { 0.07, 0.09, 0.13, 1.0 } or { 1.0, 1.0, 1.0, 1.0 }
	local topFill = isLight and { 0.95, 0.96, 0.98, 1.0 } or { 0.04, 0.12, 0.08, 0.96 }
	local paneFill = isLight and { 0.96, 0.97, 0.99, 1.0 } or { 0.03, 0.09, 0.06, 0.95 }

	tabFrame.bgPlate:SetFill(isLight and 0.91 or 0.02, isLight and 0.93 or 0.06, isLight and 0.96 or 0.04, 0.96)
	AHSellTab.topBar.plate:SetFill(topFill[1], topFill[2], topFill[3], topFill[4])
	AHSellTab.sellBagPane.plate:SetFill(paneFill[1], paneFill[2], paneFill[3], paneFill[4])
	AHSellTab.sellPricesPlate:SetFill(paneFill[1], paneFill[2], paneFill[3], paneFill[4])

	-- Notice Banner & dynamic top anchor for bottom panes
	local hasNotice = (type(st.notice) == "string" and st.notice ~= "")
	if hasNotice then
		local nk = st.noticeKind or "info"
		local nFill = isLight
			and (nk == "danger" and { 0.98, 0.90, 0.90, 1.0 } or (nk == "positive" and { 0.88, 0.96, 0.90, 1.0 } or { 0.90, 0.94, 0.98, 1.0 }))
			or (nk == "danger" and { 0.24, 0.06, 0.07, 0.96 } or (nk == "positive" and { 0.05, 0.20, 0.12, 0.96 } or { 0.08, 0.16, 0.22, 0.95 }))
		local nStroke = (nk == "danger" and { 0.96, 0.35, 0.35, 0.88 }) or (nk == "positive" and { 0.24, 0.95, 0.56, 0.85 }) or { 0.34, 0.83, 0.91, 0.80 }
		local nHex = (nk == "danger" and palHex("hexDanger", "ff453a")) or (nk == "positive" and palHex("hexPositive", "30d158")) or palHex("hexInfo", "56d4e8")
		AHSellTab.noticeBar.plate:SetFill(nFill[1], nFill[2], nFill[3], nFill[4])
		AHSellTab.noticeBar.plate:SetStroke(nStroke[1], nStroke[2], nStroke[3], nStroke[4])
		AHSellTab.noticeFs:SetText(nHex .. st.notice .. "|r")
		AHSellTab.noticeBar:Show()
		AHSellTab.sellBagPane:ClearAllPoints()
		AHSellTab.sellBagPane:SetPoint("TOPLEFT", AHSellTab.noticeBar, "BOTTOMLEFT", 0, -6)
		AHSellTab.sellBagPane:SetPoint("BOTTOMLEFT", tabFrame, "BOTTOMLEFT", 10, 10)
	else
		AHSellTab.noticeBar:Hide()
		AHSellTab.sellBagPane:ClearAllPoints()
		AHSellTab.sellBagPane:SetPoint("TOPLEFT", AHSellTab.topBar, "BOTTOMLEFT", 0, -8)
		AHSellTab.sellBagPane:SetPoint("BOTTOMLEFT", tabFrame, "BOTTOMLEFT", 10, 10)
	end

	-- Active Item preview + Drop Slot
	local titleStr, subStr = formatSellTitle(of, cur)
	AHSellTab.activeFs:SetText(titleStr)
	AHSellTab.spotSubFs:SetText(palHex("hexMuted", "98989d") .. subStr .. "|r")
	if cur and cur.itemID then
		AHSellTab.iconDropBtn.tex:SetTexture(resolveIconTex(cur.itemID, cur.spellID))
		local r, g, b = getQualityRGB(cur.quality)
		AHSellTab.iconDropBtn.plate:SetStroke(r, g, b, 0.95)
		local qDisp = (cur.channel == "vendor") and (cur.remaining or 0) or (of and of.GetSellPostQty and of.GetSellPostQty(cur) or cur.remaining or 0)
		AHSellTab.iconDropBtn.countFs:SetText((qDisp and qDisp > 1) and tostring(qDisp) or "")
	else
		AHSellTab.iconDropBtn.tex:SetTexture(ns.QUESTION_ICON or "Interface\\Icons\\INV_Misc_QuestionMark")
		AHSellTab.iconDropBtn.plate:SetStroke(goldBorder[1], goldBorder[2], goldBorder[3], 0.65)
		AHSellTab.iconDropBtn.countFs:SetText("")
	end

	-- Channel & Refresh header controls
	AHSellTab.sellRefreshBtn:SetEnabled(inAH and (cur ~= nil or sl.lastItemInfo ~= nil) and sl.pendingPost == nil)
	AHSellTab.sellRefreshBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

	local isVend = (cur ~= nil and cur.channel == "vendor")
	AHSellTab.sellChBtn:SetEnabled(cur ~= nil)
	AHSellTab.sellChBtn:SetText(isVend and "Sell: Vendor" or "Sell: AH")
	AHSellTab.sellChBtn:PaintStyle(isVend and { 0.36, 0.24, 0.06, 0.92 } or btnActFill, goldBorder, btnInactText)

	AHSellTab.sellDurLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Duration|r")
	local curDur = sl.duration or 2
	for dIdx = 1, 3 do
		local db = AHSellTab.sellDurBtns[dIdx]
		local activeD = (dIdx == curDur)
		db:SetEnabled(cur ~= nil and not isVend)
		db:PaintStyle(activeD and btnActFill or btnInactFill,
			activeD and btnActStroke or subtleBorder,
			activeD and btnActText or btnInactText)
	end
	AHSellTab.sellUcBtn:SetEnabled(cur ~= nil and not isVend)
	AHSellTab.sellUcBtn:SetText("Rule: " .. (SELL_UNDERCUT_LABELS[sl.undercutMode or "match"] or "Match"))
	AHSellTab.sellUcBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

	if isVend then
		AHSellTab.sellForm:Hide()
		AHSellTab.sellVendorBar:Show()
		AHSellTab.postBtn:Hide()
		AHSellTab.postAllBtn:Hide()
		AHSellTab.doneBtn:Hide()
		AHSellTab.skipBtn:Hide()
		if AHSellTab.vendQtyBox then
			local focused = AHSellTab.vendQtyBox.HasFocus and AHSellTab.vendQtyBox:HasFocus()
			if not focused then AHSellTab.vendQtyBox:SetText(tostring(cur.remaining or 1)) end
		end
		local vUnit = (of and of.IsSellItemVendorable) and select(2, of.IsSellItemVendorable(cur)) or (cur.vendorSell or 0)
		local vLim = (of and of.GetSellPostLimit and of.GetSellPostLimit(cur)) or (cur.inBags or 0)
		AHSellTab.vendInfoFs:SetText(string.format("In Bags: %d  |  Unit Value: %s  |  Total: %s",
			vLim, ns.FormatMoneyCompact(vUnit), ns.FormatMoneyCompact(vUnit * (cur.remaining or 0))))
		AHSellTab.sellDepFs:SetText(palHex("hexMuted", "98989d") .. "Deposit: |r0c")
		AHSellTab.sellTotalFs:SetText(palHex("hexMuted", "98989d") .. "Vendor Value: |r" .. palHex("hexGold", "f7d57c") .. ns.FormatMoneyCompact(vUnit * (cur.remaining or 0)) .. "|r")
		AHSellTab.vendSellBtn:SetEnabled(vLim > 0)
		AHSellTab.vendSellAllBtn:SetEnabled(true)
	else
		AHSellTab.sellVendorBar:Hide()
		AHSellTab.sellForm:Show()
		AHSellTab.postBtn:Show()
		AHSellTab.postAllBtn:Show()
		AHSellTab.doneBtn:Show()
		AHSellTab.skipBtn:Show()

		local isCommItem = (cur ~= nil and of and of.IsSellItemCommodity and of.IsSellItemCommodity(cur)) and true or false
		local postQty = cur and of.GetSellPostQty(cur) or 0
		local postLimit = cur and select(1, of.GetSellPostLimit(cur)) or 0
		local buyoutP, priceSrc, bidP = 0, "none", 0
		if cur and of and of.ComputeSellUnitPrice then
			buyoutP, priceSrc, bidP = of.ComputeSellUnitPrice(cur)
		end
		local effUnit = (buyoutP > 0) and buyoutP or bidP
		local dep = (cur and postQty > 0 and of and of.ComputeSellDeposit) and of.ComputeSellDeposit(cur, curDur, postQty) or 0
		local totP = postQty * effUnit
		local playerMoney = (type(_G.GetMoney) == "function") and tonumber(_G.GetMoney()) or nil
		local lowMoney = (playerMoney ~= nil and dep > playerMoney)

		AHSellTab.sellQtyLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Quantity|r")
		AHSellTab.sellPriceLbl:SetText(palHex("hexSecondary", "ebebf5") .. (isCommItem and "Unit Price|r" or "Buyout Price|r"))
		AHSellTab.sellBidLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Bid Price|r")
		AHSellTab.sellPriceGTag:SetText(palHex("hexGold", "ffd60a") .. "g|r")
		AHSellTab.sellPriceSTag:SetText(palHex("hexSilver", "c7c7cc") .. "s|r")
		AHSellTab.sellPriceCTag:SetText(palHex("hexCopper", "e08a5e") .. "c|r")
		AHSellTab.sellBidGTag:SetText(palHex("hexGold", "ffd60a") .. "g|r")
		AHSellTab.sellBidSTag:SetText(palHex("hexSilver", "c7c7cc") .. "s|r")
		AHSellTab.sellBidCTag:SetText(palHex("hexCopper", "e08a5e") .. "c|r")

		AHSellTab.sellQtyMinus:SetEnabled(cur ~= nil and postLimit > 0 and postQty > 1)
		AHSellTab.sellQtyMinus:PaintStyle(btnInactFill, goldBorder, btnInactText)
		AHSellTab.sellQtyPlus:SetEnabled(cur ~= nil and postLimit > 0 and postQty < postLimit)
		AHSellTab.sellQtyPlus:PaintStyle(btnInactFill, goldBorder, btnInactText)
		AHSellTab.sellMaxBtn:SetEnabled(cur ~= nil and postLimit > 0 and postQty ~= postLimit)
		AHSellTab.sellMaxBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)
		AHSellTab.sellMaxInfoFs:SetText(palHex("hexMuted", "98989d") .. string.format("Max: %d|r", postLimit))

		local srcTagMap = {
			custom = palHex("hexGold", "f7d57c") .. "Custom|r",
			live_own = palHex("hexPositive", "30d158") .. "Own Top|r",
			live_ah = palHex("hexInfo", "56d4e8") .. "Live AH|r",
			market_db = palHex("hexMuted", "98989d") .. "DB Price|r",
			vendor_fallback = palHex("hexMuted", "98989d") .. "Est|r",
			none = "",
		}
		AHSellTab.sellPriceSrcFs:SetText(srcTagMap[priceSrc or "none"] or "")

		if isCommItem or cur == nil then
			AHSellTab.sellBidRow:Hide()
		else
			AHSellTab.sellBidRow:Show()
			if buyoutP > 0 and bidP >= buyoutP then
				AHSellTab.sellBidHintFs:SetText(palHex("hexDanger", "ff453a") .. "Bid >= BO!|r")
			else
				AHSellTab.sellBidHintFs:SetText(palHex("hexMuted", "98989d") .. "Optional|r")
			end
		end

		local depCol = lowMoney and palHex("hexDanger", "ff453a") or palHex("hexText", "ffffff")
		AHSellTab.sellDepFs:SetText(palHex("hexMuted", "98989d") .. "Deposit: |r" .. depCol .. ((dep > 0) and ns.FormatMoneyCompact(dep) or "0c") .. "|r")
		AHSellTab.sellTotalFs:SetText(palHex("hexMuted", "98989d") .. "Total Price: |r" .. palHex("hexGold", "f7d57c") .. ((totP > 0) and ns.FormatMoneyCompact(totP) or "0c") .. "|r")

		for _, bx in ipairs({ AHSellTab.sellQtyBox, AHSellTab.sellPriceGBox, AHSellTab.sellPriceSBox, AHSellTab.sellPriceCBox, AHSellTab.sellBidGBox, AHSellTab.sellBidSBox, AHSellTab.sellBidCBox }) do
			if bx then
				if bx.plate then
					bx.plate:SetFill(boxFill[1], boxFill[2], boxFill[3], boxFill[4])
					bx.plate:SetStroke(boxStroke[1], boxStroke[2], boxStroke[3], boxStroke[4])
				end
				if bx.SetTextColor then bx:SetTextColor(boxInk[1], boxInk[2], boxInk[3], boxInk[4]) end
			end
		end
		if not (AHSellTab.sellQtyBox.HasFocus and AHSellTab.sellQtyBox:HasFocus()) then
			AHSellTab.sellQtyBox:SetText(tostring(postQty))
		end
		local pg, ps, pc = math.floor(buyoutP / 10000), math.floor((buyoutP % 10000) / 100), math.floor(buyoutP % 100)
		if not (AHSellTab.sellPriceGBox.HasFocus and AHSellTab.sellPriceGBox:HasFocus()) then AHSellTab.sellPriceGBox:SetText(tostring(pg)) end
		if not (AHSellTab.sellPriceSBox.HasFocus and AHSellTab.sellPriceSBox:HasFocus()) then AHSellTab.sellPriceSBox:SetText(tostring(ps)) end
		if not (AHSellTab.sellPriceCBox.HasFocus and AHSellTab.sellPriceCBox:HasFocus()) then AHSellTab.sellPriceCBox:SetText(tostring(pc)) end
		if not isCommItem and cur ~= nil then
			local bg, bs, bc = math.floor(bidP / 10000), math.floor((bidP % 10000) / 100), math.floor(bidP % 100)
			if not (AHSellTab.sellBidGBox.HasFocus and AHSellTab.sellBidGBox:HasFocus()) then AHSellTab.sellBidGBox:SetText(tostring(bg)) end
			if not (AHSellTab.sellBidSBox.HasFocus and AHSellTab.sellBidSBox:HasFocus()) then AHSellTab.sellBidSBox:SetText(tostring(bs)) end
			if not (AHSellTab.sellBidCBox.HasFocus and AHSellTab.sellBidCBox:HasFocus()) then AHSellTab.sellBidCBox:SetText(tostring(bc)) end
		end

		local pa = (of and of.GetSellPrimaryAction) and of.GetSellPrimaryAction() or { label = "Post", enabled = false }
		local postCol = (pa.action == "confirm" or pa.action == "confirm_warning")
			and { 0.42, 0.28, 0.06, 0.96 }
			or { 0.48, 0.09, 0.12, 0.96 }
		AHSellTab.postBtn:SetText(pa.label or "Post")
		AHSellTab.postBtn:SetEnabled(pa.enabled == true)
		AHSellTab.postBtn:PaintStyle(postCol, goldBorder, { 1.0, 0.96, 0.88, 1.0 })

		local pendingCancel = (sl.warningConfirm ~= nil or sl.pendingPost ~= nil or sl.postAllActive == true)
		if pendingCancel then
			AHSellTab.postAllBtn:SetText("Cancel")
			AHSellTab.postAllBtn:SetEnabled(true)
		else
			local hasPendingAH = false
			local isLegacy = (_G.IsUsingLegacyAuctionClient and _G.IsUsingLegacyAuctionClient() == true)
			if inAH and (not isLegacy) and _G.C_AuctionHouse ~= nil then
				for _, it in ipairs(items) do
					if it.channel == "ah" and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
						hasPendingAH = true
						break
					end
				end
			end
			AHSellTab.postAllBtn:SetText("Post All")
			AHSellTab.postAllBtn:SetEnabled(hasPendingAH)
		end
		AHSellTab.postAllBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

		local canDone = (cur ~= nil and (cur.remaining or 0) > 0 and cur.status ~= "done")
		AHSellTab.doneBtn:SetEnabled(canDone)
		AHSellTab.doneBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

		local hasOtherPending = false
		for idx, it in ipairs(items) do
			if idx ~= (sl.activeIndex or 1) and (it.remaining or 0) > 0 and it.status ~= "done" and it.status ~= "skipped" then
				hasOtherPending = true
				break
			end
		end
		AHSellTab.skipBtn:SetEnabled(cur ~= nil and hasOtherPending)
		AHSellTab.skipBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)
	end

	-- Categorized Bag Grid Render (bottom-left)
	bagScanCache = (of and of.ScanSellableBags and of.ScanSellableBags()) or {}
	bagLayoutCache = buildBagCategoryLayout(bagScanCache)
	AHSellTab.sellBagCountFs:SetText(palHex("hexGold", "f7d57c") .. string.format("%d Items|r", #bagScanCache))

	local totalLay = #bagLayoutCache
	local visLayCount, gridH = getBagVisibleLayoutCount()
	local maxBagOff = math.max(0, totalLay - visLayCount)
	if bagScrollOffset > maxBagOff then bagScrollOffset = maxBagOff end
	if bagScrollOffset < 0 then bagScrollOffset = 0 end
	AHSellTab.sellBagScroll:Update(bagScrollOffset, visLayCount, totalLay, isLight, goldBorder, accentGreen)

	for _, h in ipairs(AHSellTab.sellBagCatHdrs) do h:Hide() end
	for _, t in ipairs(AHSellTab.sellBagTiles) do t._bagRec = nil; t:Hide() end

	local curY = 0
	local hdrIdx = 0
	local tileIdx = 0
	for lIdx = bagScrollOffset + 1, totalLay do
		local entry = bagLayoutCache[lIdx]
		if not entry or (curY + entry.h) > gridH then break end
		if entry.kind == "header" then
			hdrIdx = hdrIdx + 1
			local hf = AHSellTab.sellBagCatHdrs[hdrIdx]
			if hf then
				hf:ClearAllPoints()
				hf:SetPoint("TOPLEFT", AHSellTab.sellBagGrid, "TOPLEFT", 2, -curY)
				hf:SetText(palHex("hexGold", "f7d57c") .. tostring(entry.label) .. "|r")
				hf:Show()
			end
		elseif entry.kind == "row" then
			for colIdx, rec in ipairs(entry.items) do
				tileIdx = tileIdx + 1
				local tile = AHSellTab.sellBagTiles[tileIdx]
				if tile then
					tile._bagRec = rec
					tile:ClearAllPoints()
					tile:SetPoint("TOPLEFT", AHSellTab.sellBagGrid, "TOPLEFT", (colIdx - 1) * (BAG_TILE_SZ + BAG_TILE_GAP), -curY)
					tile.tex:SetTexture(rec.icon or resolveIconTex(rec.itemID))
					local r, g, b = getQualityRGB(rec.quality)
					if rec.inQueue then
						tile.plate:SetFill(0.06, 0.28, 0.16, 0.96)
						tile.plate:SetStroke(0.24, 0.95, 0.56, 0.95)
					else
						tile.plate:SetFill(isLight and 0.92 or 0.04, isLight and 0.94 or 0.11, isLight and 0.97 or 0.08, 0.94)
						tile.plate:SetStroke(r, g, b, 0.72)
					end
					tile.cntFs:SetText((rec.totalCount and rec.totalCount > 1) and tostring(rec.totalCount) or "")
					tile:Show()
				end
			end
		end
		curY = curY + entry.h
	end

	-- Bottom-Right Tabbed View (Prices / Sell Queue / Price History)
	for _, sKey in ipairs({ "prices", "queue", "history" }) do
		local sb = AHSellTab.subTabBtns[sKey]
		local isAct = (activeSubTab == sKey)
		if sKey == "queue" then
			sb:SetText(#items > 0 and string.format("Sell Queue (%d)", #items) or "Sell Queue")
		end
		sb:PaintStyle(isAct and btnActFill or btnInactFill,
			isAct and btnActStroke or goldBorder,
			isAct and btnActText or btnInactText)
	end

	AHSellTab.sellPricesView:Hide()
	AHSellTab.sellQueueView:Hide()
	AHSellTab.sellHistoryView:Hide()

	if activeSubTab == "prices" then
		AHSellTab.sellPricesView:Show()
		AHSellTab.sellPricesHdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], 0.45)

		local listTarget = cur or sl.lastItemInfo
		local listIsComm = (cur ~= nil and of and of.IsSellItemCommodity) and of.IsSellItemCommodity(cur) or false
		if (not cur) and listTarget then
			listIsComm = (listTarget.isCommodity == true)
		end
		local listIsEquip = (not listIsComm) and listTarget and (listTarget.classID == 2 or listTarget.classID == 4 or listTarget.classID == 19)
		local hdrCol = pal.textMuted or { 0.65, 0.72, 0.68, 1 }
		for _, cHdr in ipairs({ AHSellTab.sellPricesCol1, AHSellTab.sellPricesCol2, AHSellTab.sellPricesCol3, AHSellTab.sellPricesCol4 }) do
			cHdr:SetTextColor(hdrCol[1], hdrCol[2], hdrCol[3], 1)
		end
		AHSellTab.sellPricesCol4:SetText("You?")

		if listIsComm then
			AHSellTab.sellPricesCol1:ClearAllPoints(); AHSellTab.sellPricesCol1:SetPoint("LEFT", AHSellTab.sellPricesCol1:GetParent(), "LEFT", 4, 0); AHSellTab.sellPricesCol1:SetWidth(170)
			AHSellTab.sellPricesCol1:SetText("Unit Price")
			AHSellTab.sellPricesCol2:Hide()
			AHSellTab.sellPricesCol3:ClearAllPoints(); AHSellTab.sellPricesCol3:SetPoint("RIGHT", AHSellTab.sellPricesCol4, "LEFT", -12, 0); AHSellTab.sellPricesCol3:SetWidth(120)
			AHSellTab.sellPricesCol3:SetText("Avail")
		else
			AHSellTab.sellPricesCol1:ClearAllPoints(); AHSellTab.sellPricesCol1:SetPoint("LEFT", AHSellTab.sellPricesCol1:GetParent(), "LEFT", 4, 0); AHSellTab.sellPricesCol1:SetWidth(134)
			AHSellTab.sellPricesCol1:SetText("Buyout")
			AHSellTab.sellPricesCol2:ClearAllPoints(); AHSellTab.sellPricesCol2:SetPoint("LEFT", AHSellTab.sellPricesCol1, "RIGHT", 8, 0); AHSellTab.sellPricesCol2:SetWidth(120)
			AHSellTab.sellPricesCol2:SetText("Bid"); AHSellTab.sellPricesCol2:Show()
			AHSellTab.sellPricesCol3:ClearAllPoints(); AHSellTab.sellPricesCol3:SetPoint("LEFT", AHSellTab.sellPricesCol2, "RIGHT", 8, 0); AHSellTab.sellPricesCol3:SetWidth(84)
			AHSellTab.sellPricesCol3:SetText(listIsEquip and "iLvl" or "Qty")
		end

		local listings, scanned = getCurrentSellListings()
		local isScanning = (sl.pendingSearch ~= nil) and true or false
		local visPRows = getVisibleRowCount(AHSellTab.sellPricesListArea, SELL_PRICES_ROW_H, SELL_PRICES_VISIBLE_ROWS, 3)
		local maxPOff = math.max(0, #listings - visPRows)
		if pricesScrollOffset > maxPOff then pricesScrollOffset = maxPOff end
		if pricesScrollOffset < 0 then pricesScrollOffset = 0 end
		local hasPScroll = AHSellTab.sellPricesScroll:Update(pricesScrollOffset, visPRows, #listings, isLight, goldBorder, accentGreen)
		local pRightPad = hasPScroll and -11 or 0

		if isScanning and #listings == 0 then
			AHSellTab.sellPricesEmptyFs:SetText(palHex("hexInfo", "56d4e8") .. "Scanning live AH...|r")
			AHSellTab.sellPricesEmptyFs:Show()
		elseif #listings == 0 then
			local emptyMsg = scanned and "No active AH listings" or (listTarget and "No active AH listings" or "Select an item to view Current Prices")
			AHSellTab.sellPricesEmptyFs:SetText(palHex("hexMuted", "98989d") .. emptyMsg .. "|r")
			AHSellTab.sellPricesEmptyFs:Show()
		else
			AHSellTab.sellPricesEmptyFs:Hide()
		end

		for i = 1, SELL_PRICES_VISIBLE_ROWS do
			local pr = AHSellTab.sellPricesRows[i]
			local rec = (i <= visPRows) and listings[pricesScrollOffset + i] or nil
			if rec then
				pr._listing = rec
				pr:ClearAllPoints()
				pr:SetPoint("TOPLEFT", pr:GetParent(), "TOPLEFT", 0, -((i - 1) * SELL_PRICES_ROW_H))
				pr:SetPoint("TOPRIGHT", pr:GetParent(), "TOPRIGHT", pRightPad, -((i - 1) * SELL_PRICES_ROW_H))
				if rec.containsOwnerItem then
					pr.bg:SetColorTexture(isLight and 0.00 or 0.06, isLight and 0.48 or 0.24, isLight and 0.18 or 0.14, isLight and 0.12 or 0.55)
				elseif (i % 2) == 0 then
					pr.bg:SetColorTexture(isLight and 0.00 or 1.00, isLight and 0.00 or 1.00, isLight and 0.00 or 1.00, isLight and 0.03 or 0.04)
				else
					pr.bg:SetColorTexture(0, 0, 0, 0)
				end
				pr.c4:SetText(rec.containsOwnerItem and (palHex("hexPositive", "30d158") .. "Yes|r") or (palHex("hexMuted", "98989d") .. "-|r"))
				if listIsComm then
					pr.c1:ClearAllPoints(); pr.c1:SetPoint("LEFT", pr, "LEFT", 4, 0); pr.c1:SetWidth(170)
					pr.c1:SetText((rec.price and rec.price > 0) and ns.FormatMoneyCompact(rec.price) or (palHex("hexMuted", "98989d") .. "-|r"))
					pr.c2:Hide()
					pr.c3:ClearAllPoints(); pr.c3:SetPoint("RIGHT", pr.c4, "LEFT", -12, 0); pr.c3:SetWidth(120)
					local qTxt = (_G.FormatLargeNumber and _G.FormatLargeNumber(rec.quantity or 1)) or tostring(rec.quantity or 1)
					pr.c3:SetText(palHex("hexText", "ffffff") .. qTxt .. "|r")
				else
					pr.c1:ClearAllPoints(); pr.c1:SetPoint("LEFT", pr, "LEFT", 4, 0); pr.c1:SetWidth(134)
					pr.c1:SetText((rec.price and rec.price > 0) and ns.FormatMoneyCompact(rec.price) or (palHex("hexMuted", "98989d") .. "-|r"))
					pr.c2:ClearAllPoints(); pr.c2:SetPoint("LEFT", pr.c1, "RIGHT", 8, 0); pr.c2:SetWidth(120)
					pr.c2:SetText((rec.bidPrice and rec.bidPrice > 0) and ns.FormatMoneyCompact(rec.bidPrice) or (palHex("hexMuted", "98989d") .. "-|r"))
					pr.c2:Show()
					pr.c3:ClearAllPoints(); pr.c3:SetPoint("LEFT", pr.c2, "RIGHT", 8, 0); pr.c3:SetWidth(84)
					local col3Val = listIsEquip
						and ((rec.itemLevel and rec.itemLevel > 0) and tostring(rec.itemLevel) or "-")
						or tostring(rec.quantity or 1)
					pr.c3:SetText(palHex("hexText", "ffffff") .. col3Val .. "|r")
				end
				pr:Show()
			else
				pr._listing = nil
				pr:Hide()
			end
		end
	elseif activeSubTab == "queue" then
		AHSellTab.sellQueueView:Show()
		local remTot = 0
		for _, it in ipairs(items) do remTot = remTot + (tonumber(it.remaining) or 0) end
		AHSellTab.sellQueueHdrFs:SetText(string.format("Sell Queue: %d items (%d remaining)", #items, remTot))
		AHSellTab.sellQueueClearBtn:SetEnabled(#items > 0)
		AHSellTab.sellQueueClearBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

		local visQRows = getVisibleRowCount(AHSellTab.sellQueueListArea, SELL_QUEUE_ROW_H, SELL_QUEUE_VISIBLE_ROWS, 3)
		local maxQOff = math.max(0, #items - visQRows)
		if queueScrollOffset > maxQOff then queueScrollOffset = maxQOff end
		if queueScrollOffset < 0 then queueScrollOffset = 0 end
		local hasQScroll = AHSellTab.sellQueueScroll:Update(queueScrollOffset, visQRows, #items, isLight, goldBorder, accentGreen)
		local qRightPad = hasQScroll and -11 or 0
		if #items == 0 then
			AHSellTab.sellQueueEmptyFs:Show()
		else
			AHSellTab.sellQueueEmptyFs:Hide()
		end
		for i = 1, SELL_QUEUE_VISIBLE_ROWS do
			local qr = AHSellTab.sellQueueRows[i]
			local realIdx = queueScrollOffset + i
			local it = (i <= visQRows) and items[realIdx] or nil
			if it then
				qr._itemIndex = realIdx
				qr:ClearAllPoints()
				qr:SetPoint("TOPLEFT", qr:GetParent(), "TOPLEFT", 0, -((i - 1) * SELL_QUEUE_ROW_H))
				qr:SetPoint("TOPRIGHT", qr:GetParent(), "TOPRIGHT", qRightPad, -((i - 1) * SELL_QUEUE_ROW_H))
				local isSel = (realIdx == (sl.activeIndex or 1))
				if isSel then
					qr.bg:SetColorTexture(isLight and 0.00 or 0.08, isLight and 0.45 or 0.28, isLight and 0.22 or 0.18, isLight and 0.14 or 0.65)
				elseif (i % 2) == 0 then
					qr.bg:SetColorTexture(1, 1, 1, 0.03)
				else
					qr.bg:SetColorTexture(0, 0, 0, 0)
				end
				qr.icon:SetTexture(resolveIconTex(it.itemID, it.spellID))
				local r, g, b = getQualityRGB(it.quality)
				local hex = string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
				qr.nameFs:SetText(hex .. tostring(it.name or "Item") .. "|r")
				qr.qtyFs:SetText(string.format("%d/%d", tonumber(it.soldQty) or 0, tonumber(it.totalQty) or 0))
				local up = (of and of.ComputeSellUnitPrice) and of.ComputeSellUnitPrice(it) or 0
				qr.priceFs:SetText(up > 0 and ns.FormatMoneyCompact(up) or "-")
				qr.chBtn:SetText(it.channel == "vendor" and "VEND" or "AH")
				qr.chBtn:PaintStyle(it.channel == "vendor" and { 0.36, 0.24, 0.06, 0.92 } or btnActFill, goldBorder, btnInactText)
				qr.removeBtn:PaintStyle({ 0.38, 0.08, 0.10, 0.92 }, goldBorder, { 1, 0.92, 0.92, 1 })
				qr:Show()
			else
				qr._itemIndex = nil
				qr:Hide()
			end
		end
	elseif activeSubTab == "history" then
		AHSellTab.sellHistoryView:Show()
		local target = cur or sl.lastItemInfo
		local rows, t7, t24 = getHistoryRowsData(target)
		local nameTxt = target and tostring(target.name or "Selected Item") or "Selected Item"
		local curTxt = (t7 and t7.currentPrice and t7.currentPrice > 0) and ns.FormatMoneyCompact(t7.currentPrice)
			or ((t24 and t24.currentPrice and t24.currentPrice > 0) and ns.FormatMoneyCompact(t24.currentPrice) or "N/A")
		local trendStr = "Trend: insufficient"
		if t7 and t7.trendPct ~= nil then
			local arrow = (t7.trendPct > 0 and "+") or ""
			trendStr = string.format("7d Trend: %s%.1f%% (%s)", arrow, t7.trendPct, tostring(t7.direction or ""))
		elseif t24 and t24.trendPct ~= nil then
			local arrow = (t24.trendPct > 0 and "+") or ""
			trendStr = string.format("24h Trend: %s%.1f%%", arrow, t24.trendPct)
		end
		AHSellTab.sellHistorySummaryFs:SetText(string.format("%s  |  Current: %s  |  %s", nameTxt, curTxt, trendStr))

		local visHRows = getVisibleRowCount(AHSellTab.sellHistoryListArea, SELL_HISTORY_ROW_H, SELL_HISTORY_VISIBLE_ROWS, 3)
		local maxHOff = math.max(0, #rows - visHRows)
		if historyScrollOffset > maxHOff then historyScrollOffset = maxHOff end
		if historyScrollOffset < 0 then historyScrollOffset = 0 end
		local hasHScroll = AHSellTab.sellHistoryScroll:Update(historyScrollOffset, visHRows, #rows, isLight, goldBorder, accentGreen)
		local hRightPad = hasHScroll and -11 or 0

		if #rows == 0 then
			AHSellTab.sellHistoryEmptyFs:SetText(palHex("hexMuted", "98989d") .. "No price history recorded for this item yet.|r")
			AHSellTab.sellHistoryEmptyFs:Show()
		else
			AHSellTab.sellHistoryEmptyFs:Hide()
		end
		for i = 1, SELL_HISTORY_VISIBLE_ROWS do
			local hr = AHSellTab.sellHistoryRows[i]
			local rec = (i <= visHRows) and rows[historyScrollOffset + i] or nil
			if rec then
				hr:ClearAllPoints()
				hr:SetPoint("TOPLEFT", hr:GetParent(), "TOPLEFT", 0, -((i - 1) * SELL_HISTORY_ROW_H))
				hr:SetPoint("TOPRIGHT", hr:GetParent(), "TOPRIGHT", hRightPad, -((i - 1) * SELL_HISTORY_ROW_H))
				hr.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.0)
				hr.c1:SetText(tostring(rec.when or ""))
				hr.c2:SetText(rec.price > 0 and ns.FormatMoneyCompact(rec.price) or "-")
				hr.c3:SetText(string.format("Qty: %d", tonumber(rec.qty) or 0))
				hr.c4:SetText(rec.vel and string.format("%.1f / day", rec.vel) or "-")
				hr.c5:SetText(palHex("hexMuted", "98989d") .. tostring(rec.source or "") .. "|r")
				hr:Show()
			else
				hr:Hide()
			end
		end
	end
end
