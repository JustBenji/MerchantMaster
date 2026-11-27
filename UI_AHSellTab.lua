local ADDON, ns = ...
local app = ns.app or {}
ns.app = app

-- Standalone Auction House "MM Sell" Tab (LibAHTab-1-0 + Spacious Auctionator-Parity Layout)
local AHSellTab = {}
ns.AHSellTab = AHSellTab

local SELL_TAB_ID = "MerchantMaster_Sell"
local SELL_TAB_LABEL = "MM Sell"
local SELL_TAB_HEADER = "MerchantMaster - Sell"
local BELOW_VENDOR_POPUP = "MERCHANTMASTER_CONFIRM_BELOW_VENDOR"
local BELOW_VENDOR_POPUP_TEXT = "Are you sure you want to sell %s on the Auction House?\n\nAfter the 5%% AH cut you receive %s"

local SELL_UNDERCUT_LABELS = { match = "Match", ["1c"] = "-1c", ["1s"] = "-1s", pct = "-1%" }
local SELL_UNDERCUT_SPECS = {
	{ key = "match", label = "Match" },
	{ key = "1c",    label = "-1c" },
	{ key = "1s",    label = "-1s" },
	{ key = "pct",   label = "-1%" },
}
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

local function formatSellCoinMoney(copper, overrideHex)
	if copper == nil then return palHex("hexMuted", "98989d") .. "-|r" end
	local num = tonumber(copper) or 0
	local sign = num < 0 and "-" or ""
	local v = math.floor(math.abs(num) + 0.5)
	local g = math.floor(v / 10000)
	local s = math.floor((v % 10000) / 100)
	local c = v % 100
	local cGold = ns.COIN_GOLD or "|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:1:0|t"
	local cSilver = ns.COIN_SILVER or "|TInterface\\MoneyFrame\\UI-SilverIcon:11:11:1:0|t"
	local cCopper = ns.COIN_COPPER or "|TInterface\\MoneyFrame\\UI-CopperIcon:11:11:1:0|t"
	local ov = nil
	if type(overrideHex) == "string" and overrideHex ~= "" then
		ov = (overrideHex:sub(1, 2) == "|c") and overrideHex or ("|cff" .. overrideHex)
	end
	local gHex = ov or palHex("hexGold", "ffd60a")
	local sHex = ov or palHex("hexSilver", "c7c7cc")
	local cHex = ov or palHex("hexCopper", "e08a5e")
	if g > 0 then
		local out = sign .. gHex .. tostring(g) .. "|r" .. cGold
		if s > 0 or c > 0 then
			out = out .. " " .. sHex .. string.format("%02d", s) .. "|r" .. cSilver
		end
		if c > 0 then
			out = out .. " " .. cHex .. string.format("%02d", c) .. "|r" .. cCopper
		end
		return out
	elseif s > 0 then
		local out = sign .. sHex .. tostring(s) .. "|r" .. cSilver
		if c > 0 then
			out = out .. " " .. cHex .. string.format("%02d", c) .. "|r" .. cCopper
		end
		return out
	else
		return sign .. cHex .. tostring(c) .. "|r" .. cCopper
	end
end
AHSellTab.FormatCoinMoney = formatSellCoinMoney

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
	return hex .. name .. "|r", sub
end

local function formatUnitSummaryText(effUnit)
	if not effUnit or effUnit <= 0 then
		return palHex("hexMuted", "98989d") .. "-|r"
	end
	local netUnit = math.floor(effUnit * 0.95)
	return formatSellCoinMoney(effUnit)
		.. palHex("hexMuted", "98989d") .. " (Net |r"
		.. formatSellCoinMoney(netUnit)
		.. palHex("hexMuted", "98989d") .. ")|r"
end

local function setBtnLabelPressed(btn, down)
	if btn._labelDown == down then return end
	btn._labelDown = down
	local lfs = btn.fs
	if not lfs then return end
	lfs:ClearAllPoints()
	if down then
		lfs:SetPoint("LEFT", btn, "LEFT", 5, -1)
		lfs:SetPoint("RIGHT", btn, "RIGHT", -3, -1)
	else
		lfs:SetPoint("LEFT", btn, "LEFT", 4, 0)
		lfs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
	end
end

local function setTileIconInset(tile, px)
	if tile._texInset == px then return end
	tile._texInset = px
	local tex = tile.tex
	if not tex then return end
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", tile, "TOPLEFT", px, -px)
	tex:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -px, px)
end

local function bagTilePlayPressPulse(self)
	self._pressGen = (self._pressGen or 0) + 1
	self._pressPending = (self._pressPending or 0) + 1
	setTileIconInset(self, 5)
	if self.pressTex then self.pressTex:Show() end
	if _G.C_Timer and type(_G.C_Timer.After) == "function" then
		_G.C_Timer.After(0.09, self._pressRestore)
	else
		self._pressRestore()
	end
end

local function makeFramedBtn(parent, w, h, label, fontSize, opts)
	opts = opts or {}
	local b = CreateFrame("Button", opts.name, parent)
	b:SetSize(w, h)
	b._enabled = true
	b._hovered = false
	b._pressed = false
	b._pulsing = false
	b._pulseGen = 0
	b._pulsePending = 0
	b._labelDown = false
	b._label = tostring(label or "")
	b.plate = ns.Theme.NineApple(b, "glass_r8",
		{ 0.06, 0.18, 0.12, 0.92 },
		{ 0.83, 0.64, 0.24, 0.78 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = math.min(8, math.floor(h * 0.4)), noSpecular = true })

	local hoverTex = b:CreateTexture(nil, "OVERLAY", nil, 1)
	hoverTex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	hoverTex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	hoverTex:SetColorTexture(1.0, 0.98, 0.92, 0.12)
	hoverTex:Hide()
	b.hoverTex = hoverTex

	local pressTex = b:CreateTexture(nil, "OVERLAY", nil, 2)
	pressTex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	pressTex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	pressTex:SetColorTexture(0.0, 0.0, 0.0, 0.16)
	pressTex:Hide()
	b.pressTex = pressTex

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
			if self._hovered then
				self.plate:SetStroke(math.min(1, s[1] + 0.14), math.min(1, s[2] + 0.14), math.min(1, s[3] + 0.14), 1.0)
			else
				self.plate:SetStroke(s[1], s[2], s[3], s[4] or 0.78)
			end
			fs:SetTextColor(t[1], t[2], t[3], t[4] or 1.0)
		else
			self._hovered = false
			self._pressed = false
			hoverTex:Hide()
			if not self._pulsing then
				pressTex:Hide()
				setBtnLabelPressed(self, false)
			end
			self.plate:SetFill(f[1] * 0.65, f[2] * 0.65, f[3] * 0.65, 0.60)
			self.plate:SetStroke(s[1], s[2], s[3], 0.34)
			fs:SetTextColor(t[1] * 0.72, t[2] * 0.72, t[3] * 0.72, 0.58)
		end
	end
	b._pulseRestore = function()
		b._pulsePending = math.max(0, (b._pulsePending or 1) - 1)
		if b._pulsePending > 0 then return end
		b._pulsing = false
		if b._pressed and b._enabled ~= false then
			pressTex:SetColorTexture(0.0, 0.0, 0.0, 0.16)
			pressTex:Show()
			setBtnLabelPressed(b, true)
		else
			pressTex:Hide()
			setBtnLabelPressed(b, false)
		end
		applyStyle(b)
	end
	function b:PlayPressPulse()
		self._pulseGen = (self._pulseGen or 0) + 1
		self._pulsePending = (self._pulsePending or 0) + 1
		self._pulsing = true
		setBtnLabelPressed(self, true)
		pressTex:SetColorTexture(1.0, 0.96, 0.82, 0.18)
		pressTex:Show()
		if _G.C_Timer and type(_G.C_Timer.After) == "function" then
			_G.C_Timer.After(0.09, self._pulseRestore)
		else
			self._pulseRestore()
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
		self._hovered = true
		hoverTex:Show()
		local s = self._stroke or { 0.83, 0.64, 0.24, 0.78 }
		self.plate:SetStroke(math.min(1, s[1] + 0.14), math.min(1, s[2] + 0.14), math.min(1, s[3] + 0.14), 1.0)
	end)
	b:SetScript("OnLeave", function(self)
		self._hovered = false
		self._pressed = false
		hoverTex:Hide()
		if not self._pulsing then
			pressTex:Hide()
			setBtnLabelPressed(self, false)
		end
		applyStyle(self)
	end)
	b:SetScript("OnMouseDown", function(self)
		if self._enabled == false then return end
		self._pressed = true
		setBtnLabelPressed(self, true)
		pressTex:SetColorTexture(0.0, 0.0, 0.0, 0.16)
		pressTex:Show()
	end)
	b:SetScript("OnMouseUp", function(self)
		self._pressed = false
		if not self._pulsing then
			pressTex:Hide()
			setBtnLabelPressed(self, false)
		end
		applyStyle(self)
	end)
	b:SetScript("PostClick", function(self)
		self:PlayPressPulse()
	end)
	return b
end

-- Ultra-light 2-texture scrollbar (track + thumb), wheel + drag + track click, memoized geometry
local function makeLightScrollbar(parent, onStep, onSetOffset)
	local track = CreateFrame("Frame", nil, parent)
	track:SetWidth(6)
	track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -2)
	track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 2)
	local trackTex = track:CreateTexture(nil, "BACKGROUND")
	trackTex:SetAllPoints(track)
	track.trackTex = trackTex

	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(4)
	thumb:SetPoint("TOP", track, "TOP", 0, -1)
	thumb:SetHeight(24)
	local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetAllPoints(thumb)
	thumb.thumbTex = thumbTex
	track.thumb = thumb

	local hovered = false
	local dragging = false
	local curLight = false
	local curMaxOff = 0
	local curThumbH = 24
	local curTrackH = 160
	local lastH = -1
	local lastTop = -1
	local lastVisible = false
	local lastLight = nil
	local lastActive = nil

	local function paintThumb(force)
		local active = hovered or dragging
		if (not force) and lastLight == curLight and lastActive == active then return end
		lastLight = curLight
		lastActive = active
		if curLight then
			trackTex:SetColorTexture(0.0, 0.0, 0.0, 0.08)
			thumbTex:SetColorTexture(0.18, 0.22, 0.28, active and 0.65 or 0.36)
		else
			trackTex:SetColorTexture(1.0, 1.0, 1.0, 0.12)
			thumbTex:SetColorTexture(0.84, 0.86, 0.88, active and 0.65 or 0.36)
		end
	end

	local function cursorToOffset()
		if not (onSetOffset and curMaxOff > 0) then return end
		local getCur = _G.GetCursorPosition
		if type(getCur) ~= "function" then return end
		local _, cy = getCur()
		local scale = (track.GetEffectiveScale and track:GetEffectiveScale()) or 1
		if scale <= 0 then scale = 1 end
		cy = (cy or 0) / scale
		local top = (track.GetTop and track:GetTop()) or 0
		local h = curTrackH
		local travel = math.max(1, (h - 2) - curThumbH)
		local relY = (top - 1) - cy - (curThumbH * 0.5)
		local frac = math.max(0, math.min(1, relY / travel))
		local newOff = math.floor(frac * curMaxOff + 0.5)
		onSetOffset(newOff)
	end

	if track.EnableMouseWheel then track:EnableMouseWheel(true) end
	if track.EnableMouse then track:EnableMouse(true) end
	track:SetScript("OnMouseWheel", function(_, delta)
		if onStep then onStep(delta) end
	end)
	track:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
		if onSetOffset and type(_G.GetCursorPosition) == "function" and track.GetTop then
			cursorToOffset()
		elseif onStep then
			onStep(-1)
		end
	end)

	thumb:SetScript("OnEnter", function()
		hovered = true
		paintThumb(false)
	end)
	thumb:SetScript("OnLeave", function()
		hovered = false
		paintThumb(false)
	end)
	thumb:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
		dragging = true
		paintThumb(false)
		if track.SetScript then
			track:SetScript("OnUpdate", function()
				if dragging then cursorToOffset() end
			end)
		end
	end)
	thumb:SetScript("OnMouseUp", function()
		dragging = false
		if track.SetScript then track:SetScript("OnUpdate", nil) end
		paintThumb(false)
	end)
	thumb:SetScript("OnClick", function()
		if not dragging and onStep then onStep(-1) end
	end)

	function track:Update(offset, visibleCount, totalCount, isLight)
		curLight = (isLight == true)
		if not totalCount or totalCount <= visibleCount then
			curMaxOff = 0
			if lastVisible then
				lastVisible = false
				self:Hide()
			end
			return false
		end
		if not lastVisible then
			lastVisible = true
			self:Show()
		end
		local h = (self.GetHeight and self:GetHeight()) or 0
		if h < 20 then h = 160 end
		curTrackH = h
		local ratio = visibleCount / totalCount
		local th = math.max(18, math.floor((h - 2) * ratio))
		local maxOff = math.max(1, totalCount - visibleCount)
		curMaxOff = maxOff
		curThumbH = th
		local travel = math.max(0, (h - 2) - th)
		local topOff = math.floor(travel * (math.min(maxOff, math.max(0, offset)) / maxOff) + 0.5)
		if th ~= lastH then
			lastH = th
			thumb:SetHeight(th)
		end
		if topOff ~= lastTop then
			lastTop = topOff
			thumb:ClearAllPoints()
			thumb:SetPoint("TOP", self, "TOP", 0, -(1 + topOff))
		end
		paintThumb(false)
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
local bagCacheDirty = true
local lastBagQueueSig = nil
local lastUsedBagHdrs = 0
local lastUsedBagTiles = 0
local lastChromeKey = nil
local lastPricesLayoutKey = nil
local lastQueueLayoutKey = nil
local lastHistoryLayoutKey = nil
local historyCacheKey = nil
local historyCacheRows = {}
local historyCacheT7 = nil
local historyCacheT24 = nil
local activeSubTab = "prices"
local lastAutoScanItemKey = nil
local lastAutoScanAt = 0
local lastTopBarLayoutW = -1
local popupShownKey = nil

local layoutTopBar
local renderBagGrid
local renderPricesList
local renderQueueList
local renderHistoryList

local function getOrderFlow()
	return (ns.MarketScan and ns.MarketScan.OrderFlow) or app.orderFlow
end

local function ensureBelowVendorPopup()
	if type(_G.StaticPopupDialogs) ~= "table" then
		_G.StaticPopupDialogs = {}
	end
	if not _G.StaticPopupDialogs[BELOW_VENDOR_POPUP] then
		_G.StaticPopupDialogs[BELOW_VENDOR_POPUP] = {
			text = BELOW_VENDOR_POPUP_TEXT,
			button1 = "Post on AH",
			button2 = "Cancel",
			OnAccept = function()
				popupShownKey = nil
				local of = getOrderFlow()
				if of and of.ConfirmLowPriceSellPost then
					of.ConfirmLowPriceSellPost()
				end
			end,
			OnCancel = function()
				popupShownKey = nil
				local of = getOrderFlow()
				if of and of.CancelPendingSellPost then
					of.CancelPendingSellPost("clear")
				end
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
	end
end
ensureBelowVendorPopup()

local function hideBelowVendorPopup()
	if popupShownKey ~= nil then
		popupShownKey = nil
		if type(_G.StaticPopup_Hide) == "function" then
			pcall(_G.StaticPopup_Hide, BELOW_VENDOR_POPUP)
		end
	end
end

local function showBelowVendorPopup(of)
	ensureBelowVendorPopup()
	local sl = of and of.GetState and of.GetState().stages.sell
	local wc = sl and sl.warningConfirm
	if not (wc and wc.reason == "below_vendor") then return false end
	local cur = sl.items and sl.items[wc.itemIndex or sl.activeIndex]
	if not cur then return false end
	local itemName = tostring(cur.name or "this item")
	local effUnit = (wc.unitPrice and wc.unitPrice > 0) and wc.unitPrice or (wc.bidPrice or 0)
	local netUnit = math.floor(effUnit * 0.95)
	local vUnit = tonumber(cur.vendorSell) or 0
	if of and of.IsSellItemVendorable then
		local _, vs = of.IsSellItemVendorable(cur)
		if tonumber(vs) and tonumber(vs) > 0 then vUnit = tonumber(vs) end
	end
	local diff = math.max(0, vUnit - netUnit)
	local netStr = formatSellCoinMoney(netUnit)
	local vendStr = formatSellCoinMoney(vUnit)
	local diffStr = formatSellCoinMoney(diff)
	local key = tostring(wc.itemIndex or 0) .. ":" .. tostring(effUnit) .. ":" .. tostring(vUnit)
	popupShownKey = key
	if type(_G.StaticPopup_Show) ~= "function" then return false end
	local detailStr = string.format("%s per item, while a vendor pays %s per item (%s more at vendor).", netStr, vendStr, diffStr)
	pcall(_G.StaticPopup_Show, BELOW_VENDOR_POPUP, itemName, detailStr)
	return true
end

function AHSellTab.MarkBagsDirty()
	bagCacheDirty = true
end

local function nowAutoScanMono()
	if type(_G.GetTime) == "function" then
		local ok, t = pcall(_G.GetTime)
		if ok and type(t) == "number" then return t end
	end
	if type(_G.time) == "function" then
		local ok, t = pcall(_G.time)
		if ok and type(t) == "number" then return t end
	end
	return 0
end

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
	local of = getOrderFlow()
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

local function computeBagQueueSig(items)
	local parts = {}
	for i, it in ipairs(items or {}) do
		if it and it.status ~= "done" and it.status ~= "skipped" then
			parts[#parts + 1] = tostring(it.itemID or 0) .. ":" .. tostring(it.itemLink or "")
		end
	end
	return table.concat(parts, ";")
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

local function updateVendorValueReadout(of, cur, effUnit, isLight)
	local row = AHSellTab.sellVendorRow
	local lbl = AHSellTab.sellVendorLbl
	local valFs = AHSellTab.sellVendorValFs
	if not (row and lbl and valFs) then return end
	if not cur then
		row._isBelowVendor = false
		if row.plate then
			row.plate:SetFill(isLight and 0.91 or 0.012, isLight and 0.93 or 0.016, isLight and 0.96 or 0.025, isLight and 0.95 or 0.94)
			row.plate:SetStroke(isLight and 0.00 or 0.83, isLight and 0.00 or 0.64, isLight and 0.00 or 0.24, isLight and 0.18 or 0.42)
		end
		lbl:SetText(palHex("hexMuted", "98989d") .. "Vendor Value|r")
		valFs:SetText(palHex("hexMuted", "98989d") .. "-|r")
		return
	end
	local vUnit = tonumber(cur.vendorSell) or 0
	if of and of.IsSellItemVendorable then
		local _, vs = of.IsSellItemVendorable(cur)
		if tonumber(vs) and tonumber(vs) > 0 then vUnit = tonumber(vs) end
	end
	if vUnit <= 0 then
		row._isBelowVendor = false
		if row.plate then
			row.plate:SetFill(isLight and 0.91 or 0.012, isLight and 0.93 or 0.016, isLight and 0.96 or 0.025, isLight and 0.95 or 0.94)
			row.plate:SetStroke(isLight and 0.00 or 0.83, isLight and 0.00 or 0.64, isLight and 0.00 or 0.24, isLight and 0.18 or 0.42)
		end
		lbl:SetText(palHex("hexMuted", "98989d") .. "Vendor Value|r")
		valFs:SetText(palHex("hexMuted", "98989d") .. "No vendor|r")
		return
	end
	local eff = tonumber(effUnit) or 0
	local netUnit = (eff > 0) and math.floor(eff * 0.95) or 0
	local isBelowVendor = (eff > 0 and netUnit < vUnit)
	row._isBelowVendor = isBelowVendor
	if isBelowVendor then
		if row.plate then
			if isLight then
				row.plate:SetFill(0.98, 0.90, 0.86, 1.0)
				row.plate:SetStroke(0.86, 0.26, 0.18, 0.88)
			else
				row.plate:SetFill(0.30, 0.09, 0.06, 0.94)
				row.plate:SetStroke(0.96, 0.42, 0.24, 0.92)
			end
		end
		lbl:SetText(palHex("hexDanger", "ff453a") .. "Vendor Value|r")
		valFs:SetText(formatSellCoinMoney(vUnit) .. " " .. palHex("hexDanger", "ff453a") .. "(> AH Net!)|r")
	else
		if row.plate then
			row.plate:SetFill(isLight and 0.91 or 0.012, isLight and 0.93 or 0.016, isLight and 0.96 or 0.025, isLight and 0.95 or 0.94)
			row.plate:SetStroke(isLight and 0.00 or 0.83, isLight and 0.00 or 0.64, isLight and 0.00 or 0.24, isLight and 0.18 or 0.42)
		end
		lbl:SetText(palHex("hexMuted", "98989d") .. "Vendor Value|r")
		valFs:SetText(formatSellCoinMoney(vUnit))
	end
end

local function updateSellSummaryReadouts(of, cur, qty, effUnit, curDur, isLight)
	local q = math.max(0, tonumber(qty) or 0)
	local unit = math.max(0, tonumber(effUnit) or 0)
	local gross = q * unit
	local netTotal = math.floor(gross * 0.95)
	local cut = gross - netTotal
	local dur = curDur or 2
	local dep = (cur and q > 0 and of and of.ComputeSellDeposit) and of.ComputeSellDeposit(cur, dur, q) or 0
	local playerMoney = (type(_G.GetMoney) == "function") and tonumber(_G.GetMoney()) or nil
	local lowMoney = (playerMoney ~= nil and dep > playerMoney)

	if AHSellTab.sellDepRow and AHSellTab.sellDepRow.plate then
		if lowMoney then
			AHSellTab.sellDepRow.plate:SetFill(isLight and 0.98 or 0.30, isLight and 0.90 or 0.09, isLight and 0.86 or 0.06, isLight and 1.0 or 0.94)
			AHSellTab.sellDepRow.plate:SetStroke(0.96, 0.36, 0.24, 0.90)
		else
			AHSellTab.sellDepRow.plate:SetFill(isLight and 0.91 or 0.012, isLight and 0.93 or 0.016, isLight and 0.96 or 0.025, isLight and 0.95 or 0.94)
			AHSellTab.sellDepRow.plate:SetStroke(isLight and 0.00 or 0.94, isLight and 0.00 or 0.60, isLight and 0.00 or 0.16, isLight and 0.18 or 0.48)
		end
	end

	if AHSellTab.sellUnitSummaryFs then
		AHSellTab.sellUnitSummaryFs:SetText(cur and formatUnitSummaryText(unit) or (palHex("hexMuted", "98989d") .. "-|r"))
	end
	if AHSellTab.sellTotalValFs then
		AHSellTab.sellTotalValFs:SetText(formatSellCoinMoney(gross > 0 and gross or 0))
	end
	if AHSellTab.sellCutValFs then
		if cut > 0 then
			local cutHex = isLight and "b84234" or "e87c6c"
			AHSellTab.sellCutValFs:SetText("|cff" .. cutHex .. "-|r" .. formatSellCoinMoney(cut, cutHex))
		else
			AHSellTab.sellCutValFs:SetText(palHex("hexMuted", "98989d") .. "-|r")
		end
	end
	if AHSellTab.sellDepLbl then
		local durTag = SELL_DUR_LABELS[dur] or "8h"
		local lblHex = lowMoney and palHex("hexDanger", "ff453a") or palHex("hexMuted", "98989d")
		AHSellTab.sellDepLbl:SetText(lblHex .. "Deposit (" .. durTag .. ")|r")
	end
	if AHSellTab.sellDepValFs then
		AHSellTab.sellDepValFs:SetText(formatSellCoinMoney(dep > 0 and dep or 0, lowMoney and palHex("hexDanger", "ff453a") or nil))
	end
	if AHSellTab.sellNetValFs then
		AHSellTab.sellNetValFs:SetText(formatSellCoinMoney(netTotal > 0 and netTotal or 0))
	end
end

local function buildUI()
	if initialized then return end
	initialized = true
	ensureBelowVendorPopup()
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

	if tabFrame.RegisterEvent and tabFrame.SetScript then
		pcall(tabFrame.RegisterEvent, tabFrame, "BAG_UPDATE_DELAYED")
		tabFrame:SetScript("OnEvent", function(_, ev)
			if ev == "BAG_UPDATE_DELAYED" then
				bagCacheDirty = true
				if AHSellTab.IsShown() and renderBagGrid then
					renderBagGrid(true, isLightTheme())
				end
			end
		end)
	end

	AHSellTab.frame = tabFrame
	app.ui = app.ui or {}
	app.ui.ahSellTab = AHSellTab

	-- Top Sale Bar (3-Zone Aligned Workstation: Selected Item | Pricing & Rules & Actions | Vendor, Duration & Cost Summary)
	local topBar = CreateFrame("Frame", nil, tabFrame)
	topBar:SetHeight(176)
	topBar:SetPoint("TOPLEFT", tabFrame, "TOPLEFT", 10, -10)
	topBar:SetPoint("TOPRIGHT", tabFrame, "TOPRIGHT", -10, -10)
	topBar.plate = ns.Theme.NineApple(topBar, "glass_r10",
		{ 0.022, 0.028, 0.040, 0.94 },
		{ 0.83, 0.64, 0.24, 0.60 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	local topAccent = topBar:CreateTexture(nil, "ARTWORK", nil, 2)
	topAccent:SetPoint("TOPLEFT", topBar, "TOPLEFT", 2, -1)
	topAccent:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -2, -1)
	topAccent:SetHeight(2)
	AHSellTab.topBarTopAccent = topAccent
	AHSellTab.topBar = topBar
	if topBar.HookScript then
		topBar:HookScript("OnSizeChanged", function()
			lastTopBarLayoutW = -1
			layoutTopBar()
		end)
	elseif topBar.SetScript then
		topBar:SetScript("OnSizeChanged", function()
			lastTopBarLayoutW = -1
			layoutTopBar()
		end)
	end

	-- Subtle vertical zone dividers
	local topDiv1 = topBar:CreateTexture(nil, "ARTWORK")
	topDiv1:SetWidth(1)
	topDiv1:SetPoint("TOP", topBar, "TOPLEFT", 306, -12)
	topDiv1:SetPoint("BOTTOM", topBar, "BOTTOMLEFT", 306, 12)
	AHSellTab.topDiv1 = topDiv1

	local topDiv2 = topBar:CreateTexture(nil, "ARTWORK")
	topDiv2:SetWidth(1)
	topDiv2:SetPoint("TOP", topBar, "TOPLEFT", 705, -12)
	topDiv2:SetPoint("BOTTOM", topBar, "BOTTOMLEFT", 705, 12)
	AHSellTab.topDiv2 = topDiv2

	-- Zone 1 (Left): Selected Item header, drag-and-drop icon socket, widened labels
	do
		local zone1 = CreateFrame("Frame", nil, topBar)
		zone1:SetPoint("TOPLEFT", topBar, "TOPLEFT", 12, -10)
		zone1:SetPoint("BOTTOMLEFT", topBar, "BOTTOMLEFT", 12, 10)
		zone1:SetWidth(282)
		zone1.plate = ns.Theme.NineApple(zone1, "glass_r8",
			{ 0.012, 0.016, 0.025, 0.88 },
			{ 0.83, 0.64, 0.24, 0.34 },
			{ layer = "BACKGROUND", sub = 1, cornerSize = 8, noSpecular = true })
		AHSellTab.sellZone1 = zone1

		local zone1EyebrowFs = zone1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		zone1EyebrowFs:SetPoint("TOPLEFT", zone1, "TOPLEFT", 2, -2)
		zone1EyebrowFs:SetWidth(278)
		zone1EyebrowFs:SetHeight(14)
		zone1EyebrowFs:SetJustifyH("LEFT")
		zone1EyebrowFs:SetJustifyV("MIDDLE")
		zone1EyebrowFs:SetWordWrap(false)
		applySafeFont(zone1EyebrowFs, 9, "semibold")
		zone1EyebrowFs:SetText("SELECTED ITEM")
		AHSellTab.zone1EyebrowFs = zone1EyebrowFs

		local iconDropBtn = CreateFrame("Button", nil, zone1)
		iconDropBtn:SetSize(56, 56)
		iconDropBtn:SetPoint("TOPLEFT", zone1, "TOPLEFT", 2, -22)
		iconDropBtn._hovered = false
		iconDropBtn._pressed = false
		iconDropBtn._pressGen = 0
		iconDropBtn._pressPending = 0
		iconDropBtn._texInset = 5
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
		local dropHoverTex = iconDropBtn:CreateTexture(nil, "OVERLAY", nil, 1)
		dropHoverTex:SetPoint("TOPLEFT", iconDropBtn, "TOPLEFT", 2, -2)
		dropHoverTex:SetPoint("BOTTOMRIGHT", iconDropBtn, "BOTTOMRIGHT", -2, 2)
		dropHoverTex:SetColorTexture(1.0, 0.96, 0.84, 0.16)
		dropHoverTex:Hide()
		iconDropBtn.hoverTex = dropHoverTex
		local dropPressTex = iconDropBtn:CreateTexture(nil, "OVERLAY", nil, 2)
		dropPressTex:SetPoint("TOPLEFT", iconDropBtn, "TOPLEFT", 2, -2)
		dropPressTex:SetPoint("BOTTOMRIGHT", iconDropBtn, "BOTTOMRIGHT", -2, 2)
		dropPressTex:SetColorTexture(1.0, 1.0, 1.0, 0.24)
		dropPressTex:Hide()
		iconDropBtn.pressTex = dropPressTex
		iconDropBtn._pressRestore = function()
			iconDropBtn._pressPending = math.max(0, (iconDropBtn._pressPending or 1) - 1)
			if iconDropBtn._pressPending > 0 then return end
			if not iconDropBtn._pressed then
				setTileIconInset(iconDropBtn, 5)
			end
			dropPressTex:Hide()
		end
		function iconDropBtn:PlayPressPulse()
			self._pressGen = (self._pressGen or 0) + 1
			self._pressPending = (self._pressPending or 0) + 1
			setTileIconInset(self, 7)
			dropPressTex:Show()
			if _G.C_Timer and type(_G.C_Timer.After) == "function" then
				_G.C_Timer.After(0.09, self._pressRestore)
			else
				self._pressRestore()
			end
		end
		local dropCountFs = iconDropBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		dropCountFs:SetPoint("BOTTOMRIGHT", iconDropBtn, "BOTTOMRIGHT", -5, 4)
		applySafeFont(dropCountFs, 10.5, "bold")
		if dropCountFs.SetShadowOffset then dropCountFs:SetShadowOffset(1, -1) end
		if dropCountFs.SetShadowColor then dropCountFs:SetShadowColor(0, 0, 0, 0.95) end
		iconDropBtn.countFs = dropCountFs
		AHSellTab.iconDropBtn = iconDropBtn

		local activeFs = zone1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		activeFs:SetPoint("TOPLEFT", zone1, "TOPLEFT", 68, -22)
		activeFs:SetWidth(212)
		activeFs:SetHeight(40)
		activeFs:SetJustifyH("LEFT")
		activeFs:SetJustifyV("TOP")
		activeFs:SetWordWrap(true)
		applySafeFont(activeFs, 13, "semibold")
		AHSellTab.activeFs = activeFs

		local spotSubFs = zone1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		spotSubFs:SetPoint("TOPLEFT", zone1, "TOPLEFT", 2, -88)
		spotSubFs:SetWidth(278)
		spotSubFs:SetHeight(16)
		spotSubFs:SetJustifyH("LEFT")
		spotSubFs:SetJustifyV("MIDDLE")
		spotSubFs:SetWordWrap(false)
		applySafeFont(spotSubFs, 10, "regular")
		AHSellTab.spotSubFs = spotSubFs

		local spotMetaFs = zone1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		spotMetaFs:SetPoint("TOPLEFT", spotSubFs, "BOTTOMLEFT", 0, -4)
		spotMetaFs:SetWidth(278)
		spotMetaFs:SetHeight(16)
		spotMetaFs:SetJustifyH("LEFT")
		spotMetaFs:SetJustifyV("MIDDLE")
		spotMetaFs:SetWordWrap(false)
		applySafeFont(spotMetaFs, 9.5, "semibold")
		AHSellTab.spotMetaFs = spotMetaFs

		AHSellTab.dropHintBox = nil
		AHSellTab.dropHintFs = nil

		if iconDropBtn.SetScript then
			iconDropBtn:SetScript("OnReceiveDrag", function(self)
				self:PlayPressPulse()
				AHSellTab.HandleBagDrop()
			end)
			iconDropBtn:SetScript("OnClick", function(self)
				self:PlayPressPulse()
				local hasCur = (_G.GetCursorInfo and _G.GetCursorInfo() ~= nil)
					or (_G.C_Cursor and _G.C_Cursor.GetCursorItem and _G.C_Cursor.GetCursorItem() ~= nil)
				if hasCur or lastPickedBag ~= nil then
					AHSellTab.HandleBagDrop()
				end
			end)
			iconDropBtn:SetScript("OnMouseDown", function(self)
				self._pressed = true
				setTileIconInset(self, 7)
			end)
			iconDropBtn:SetScript("OnMouseUp", function(self)
				self._pressed = false
				setTileIconInset(self, 5)
			end)
			iconDropBtn:SetScript("OnEnter", function(self)
				self._hovered = true
				dropHoverTex:Show()
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
			iconDropBtn:SetScript("OnLeave", function(self)
				self._hovered = false
				self._pressed = false
				dropHoverTex:Hide()
				setTileIconInset(self, 5)
				if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
			end)
		end
	end
	if topBar.SetScript then
		topBar:SetScript("OnReceiveDrag", function()
			AHSellTab.HandleBagDrop()
		end)
	end

	-- EditBox helpers & state guards
	local suppressSellEditCommit = false
	local qtyBox, priceGBox, priceSBox, priceCBox, bidGBox, bidSBox, bidCBox, bidRow

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
		if not cur then return end
		local isComm = (cur.isCommodity ~= nil) and (cur.isCommodity == true)
			or (of.IsSellItemCommodity and of.IsSellItemCommodity(cur) or false)
		local limit = of.GetSellPostLimit and of.GetSellPostLimit(cur) or 0
		local rawQ = math.max(0, math.floor(tonumber(qtyBox and qtyBox:GetText() or "0") or 0))
		local qty = (limit > 0) and math.min(rawQ, limit) or 0
		local buyout = parseEditCopper(priceGBox, priceSBox, priceCBox)
		local bid = isComm and 0 or parseEditCopper(bidGBox, bidSBox, bidCBox)
		local effUnit = (buyout > 0) and buyout or bid
		local lightMode = isLightTheme()
		updateSellSummaryReadouts(of, cur, qty, effUnit, sl.duration or 2, lightMode)
		updateVendorValueReadout(of, cur, effUnit, lightMode)
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

	local function clearSellInputFocus()
		suppressSellEditCommit = true
		for _, bx in ipairs({ qtyBox, priceGBox, priceSBox, priceCBox, bidGBox, bidSBox, bidCBox }) do
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
			if qtyBox and qtyBox:IsShown() then commitQty() end
			if priceGBox and priceGBox:IsShown() then commitPrimaryPrice() end
			if bidRow and bidRow:IsShown() and bidGBox then commitBidPrice() end
		end
		clearSellInputFocus()
	end
	AHSellTab.clearSellInputFocus = clearSellInputFocus
	AHSellTab.commitSellInputsAndClearFocus = commitSellInputsAndClearFocus

	local function executePrimaryPostAction()
		local of = getOrderFlow()
		if not of then return end
		local pa = of.GetSellPrimaryAction and of.GetSellPrimaryAction() or nil
		if pa and pa.action == "confirm" then
			of.ConfirmPendingSellPost()
		elseif pa and pa.action == "confirm_warning" then
			hideBelowVendorPopup()
			of.ConfirmLowPriceSellPost()
		elseif pa and pa.action == "sell_vendor" then
			if of.SellToVendor then of.SellToVendor() end
		elseif of.PostSellItem then
			local ok, err, why = of.PostSellItem()
			if ok == false and err == "confirm_low_price" and why == "below_vendor" then
				showBelowVendorPopup(of)
			end
		end
	end

	local function triggerSellPostFromEnter()
		local of = getOrderFlow()
		if not of then return end
		local pa = of.GetSellPrimaryAction and of.GetSellPrimaryAction() or nil
		if not (pa and pa.enabled) then return end
		executePrimaryPostAction()
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

	-- Zone 2 (Center): Aligned Vertical Stack (Qty, Unit Price, Rule, Starting Bid, Action Row)
	local form = CreateFrame("Frame", nil, topBar)
	form:SetPoint("TOPLEFT", topBar, "TOPLEFT", 318, -10)
	form:SetSize(375, 156)
	AHSellTab.sellForm = form

	do
		local qtyRow = CreateFrame("Frame", nil, form)
		qtyRow:SetHeight(24)
		qtyRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -2)
		qtyRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -2)
		AHSellTab.sellQtyRow = qtyRow

		local qtyLbl = qtyRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qtyLbl:SetPoint("LEFT", qtyRow, "LEFT", 0, 0)
		qtyLbl:SetWidth(82)
		qtyLbl:SetJustifyH("LEFT")
		qtyLbl:SetWordWrap(false)
		applySafeFont(qtyLbl, 10.5, "semibold")
		AHSellTab.sellQtyLbl = qtyLbl

		local qtyMinus = makeFramedBtn(qtyRow, 24, 24, "-", 12)
		qtyMinus:SetPoint("LEFT", qtyLbl, "RIGHT", 8, 0)
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

		local maxBtn = makeFramedBtn(qtyRow, 50, 24, "Max", 10)
		maxBtn:SetPoint("LEFT", qtyPlus, "RIGHT", 8, 0)
		maxBtn:SetScript("OnClick", function()
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.SetSellItemMaxQty then of.SetSellItemMaxQty() end
		end)
		addTip(maxBtn, "Max Stack Count", "Set Quantity to maximum available post count for the selected item.")
		AHSellTab.sellMaxBtn = maxBtn

		local maxInfoFs = qtyRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		maxInfoFs:SetPoint("LEFT", maxBtn, "RIGHT", 10, 0)
		maxInfoFs:SetJustifyH("LEFT")
		maxInfoFs:SetWordWrap(false)
		applySafeFont(maxInfoFs, 10, "regular")
		AHSellTab.sellMaxInfoFs = maxInfoFs

		-- Row 2: Buyout / Unit Price row on identical rail
		local priceRow = CreateFrame("Frame", nil, form)
		priceRow:SetHeight(24)
		priceRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -32)
		priceRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -32)
		AHSellTab.sellPriceRow = priceRow

		local priceLbl = priceRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		priceLbl:SetPoint("LEFT", priceRow, "LEFT", 0, 0)
		priceLbl:SetWidth(82)
		priceLbl:SetJustifyH("LEFT")
		priceLbl:SetWordWrap(false)
		applySafeFont(priceLbl, 10.5, "semibold")
		AHSellTab.sellPriceLbl = priceLbl

		priceGBox = makeSellEditBox(priceRow, 66, 6, commitPrimaryPrice, triggerSellPostFromEnter,
			function() return priceSBox end, function() return qtyBox end)
		priceGBox:SetPoint("LEFT", priceLbl, "RIGHT", 8, 0)
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

		local priceSrcPill = CreateFrame("Frame", nil, priceRow)
		priceSrcPill:SetSize(64, 20)
		priceSrcPill:SetPoint("LEFT", pCTag, "RIGHT", 10, 0)
		priceSrcPill.plate = ns.Theme.NineApple(priceSrcPill, "pill",
			{ 0.06, 0.17, 0.22, 0.90 },
			{ 0.34, 0.83, 0.91, 0.65 },
			{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
		AHSellTab.sellPriceSrcPill = priceSrcPill

		local priceSrcFs = priceSrcPill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		priceSrcFs:SetPoint("LEFT", priceSrcPill, "LEFT", 4, 0)
		priceSrcFs:SetPoint("RIGHT", priceSrcPill, "RIGHT", -4, 0)
		priceSrcFs:SetJustifyH("CENTER")
		priceSrcFs:SetJustifyV("MIDDLE")
		priceSrcFs:SetWordWrap(false)
		applySafeFont(priceSrcFs, 9, "semibold")
		AHSellTab.sellPriceSrcFs = priceSrcFs

		-- Row 3: Undercut Rule row aligned on identical Zone 2 rail directly under Unit Price
		local ruleRow = CreateFrame("Frame", nil, form)
		ruleRow:SetHeight(24)
		ruleRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -62)
		ruleRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -62)
		AHSellTab.sellRuleRow = ruleRow

		local ruleLbl = ruleRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ruleLbl:SetPoint("LEFT", ruleRow, "LEFT", 0, 0)
		ruleLbl:SetWidth(82)
		ruleLbl:SetHeight(22)
		ruleLbl:SetJustifyH("LEFT")
		ruleLbl:SetJustifyV("MIDDLE")
		ruleLbl:SetWordWrap(false)
		applySafeFont(ruleLbl, 10.5, "semibold")
		AHSellTab.sellRuleLbl = ruleLbl

		local ucBtns = {}
		for uIdx, spec in ipairs(SELL_UNDERCUT_SPECS) do
			local bw = (uIdx == 1) and 68 or 58
			local ub = makeFramedBtn(ruleRow, bw, 22, spec.label, 9.5)
			ub._ucKey = spec.key
			if uIdx == 1 then
				ub:SetPoint("LEFT", ruleLbl, "RIGHT", 8, 0)
			else
				ub:SetPoint("LEFT", ucBtns[uIdx - 1], "RIGHT", 5, 0)
			end
			ub:SetScript("OnClick", function()
				clearSellInputFocus()
				local of = getOrderFlow()
				if of and of.SetSellUndercutMode then of.SetSellUndercutMode(spec.key) end
			end)
			addTip(ub, "Undercut Rule: " .. spec.label, "Set pricing rule to " .. spec.label .. " against lowest competitor listing.")
			ucBtns[uIdx] = ub
		end
		AHSellTab.sellUcBtns = ucBtns

		-- Backward-compatible cycle proxy for existing tests referencing AHSellTab.sellUcBtn
		AHSellTab.sellUcBtn = {
			Click = function()
				clearSellInputFocus()
				local of = getOrderFlow()
				if of and of.CycleSellUndercutMode then of.CycleSellUndercutMode() end
			end,
			GetText = function()
				local of = getOrderFlow()
				local sl = of and of.GetState and of.GetState().stages.sell
				local mode = (sl and sl.undercutMode) or "match"
				return "Rule: " .. (SELL_UNDERCUT_LABELS[mode] or "Match")
			end,
			IsEnabled = function()
				return ucBtns[1] and ucBtns[1]:IsEnabled() or false
			end,
			SetEnabled = function(_, en)
				for _, ub in ipairs(ucBtns) do ub:SetEnabled(en) end
			end,
			IsShown = function()
				return ucBtns[1] and ucBtns[1]:IsShown() or false
			end,
		}

		-- Row 4: Optional Starting Bid row (non-commodities only) on identical rail
		bidRow = CreateFrame("Frame", nil, form)
		bidRow:SetHeight(24)
		bidRow:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -92)
		bidRow:SetPoint("TOPRIGHT", form, "TOPRIGHT", 0, -92)
		AHSellTab.sellBidRow = bidRow

		local bidLbl = bidRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bidLbl:SetPoint("LEFT", bidRow, "LEFT", 0, 0)
		bidLbl:SetWidth(82)
		bidLbl:SetJustifyH("LEFT")
		bidLbl:SetWordWrap(false)
		applySafeFont(bidLbl, 10.5, "semibold")
		AHSellTab.sellBidLbl = bidLbl

		bidGBox = makeSellEditBox(bidRow, 66, 6, commitBidPrice, triggerSellPostFromEnter,
			function() return bidSBox end, function() return priceCBox end)
		bidGBox:SetPoint("LEFT", bidLbl, "RIGHT", 8, 0)
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
		bidHintFs:SetPoint("LEFT", bCTag, "RIGHT", 10, 0)
		bidHintFs:SetJustifyH("LEFT")
		bidHintFs:SetWordWrap(false)
		applySafeFont(bidHintFs, 9.5, "regular")
		AHSellTab.sellBidHintFs = bidHintFs

		-- Row 5: Clean action bar (Post | Refresh | context-only Cancel) flush with Zone 2 left rail
		local postBtn = makeFramedBtn(topBar, 148, 30, "Post", 11.5, { name = "MerchantMasterSellPostBtn" })
		postBtn:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 0, 2)
		postBtn:SetScript("OnClick", function()
			commitSellInputsAndClearFocus()
			executePrimaryPostAction()
		end)
		addTip(postBtn, "Post Auction (Space)", "Post the selected Quantity at the displayed price. Pressing Spacebar while this tab is open also posts.")
		AHSellTab.postBtn = postBtn

		local refreshBtn = makeFramedBtn(topBar, 110, 30, "Refresh", 10.5)
		refreshBtn:SetPoint("LEFT", postBtn, "RIGHT", 8, 0)
		refreshBtn:SetScript("OnClick", function()
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.RefreshSellSearch then of.RefreshSellSearch() end
		end)
		addTip(refreshBtn, "Refresh Live Prices", "Re-scan live Auction House prices for the selected or last posted item.")
		AHSellTab.sellRefreshBtn = refreshBtn

		local cancelBtn = makeFramedBtn(topBar, 92, 30, "Cancel", 10.5)
		cancelBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
		cancelBtn:SetScript("OnClick", function()
			clearSellInputFocus()
			hideBelowVendorPopup()
			local of = getOrderFlow()
			if not of then return end
			local sl = of.GetState and of.GetState().stages.sell
			if sl and sl.warningConfirm and of.CancelPendingSellPost then
				of.CancelPendingSellPost("clear")
			elseif sl and sl.pendingPost ~= nil and of.CancelPendingSellPost then
				of.CancelPendingSellPost("user_cancel")
			end
		end)
		addTip(cancelBtn, "Cancel Pending Post", "Cancel the active post confirmation or low-price warning.")
		cancelBtn:Hide()
		AHSellTab.cancelBtn = cancelBtn
	end

	-- Zone 3 (Right): Vendor Value Bar -> Duration Row -> Standalone Deposit Bar -> 4-Row Cost & Payout Summary Card
	do
		local zone3 = CreateFrame("Frame", nil, topBar)
		zone3:SetPoint("TOPRIGHT", topBar, "TOPRIGHT", -12, -10)
		zone3:SetPoint("BOTTOMRIGHT", topBar, "BOTTOMRIGHT", -12, 10)
		zone3:SetWidth(319)
		AHSellTab.sellZone3 = zone3

		local vendorRow = CreateFrame("Frame", nil, zone3)
		vendorRow:SetPoint("TOPLEFT", zone3, "TOPLEFT", 0, 0)
		vendorRow:SetPoint("TOPRIGHT", zone3, "TOPRIGHT", 0, 0)
		vendorRow:SetHeight(22)
		if vendorRow.EnableMouse then vendorRow:EnableMouse(true) end
		vendorRow.plate = ns.Theme.NineApple(vendorRow, "glass_r8",
			{ 0.012, 0.016, 0.025, 0.94 },
			{ 0.83, 0.64, 0.24, 0.42 },
			{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
		addTip(vendorRow, "Vendor Sell Value", "Per-item NPC vendor price. Highlights red/amber whenever selling to a vendor beats your 95% AH net after the 5% AH cut.")
		AHSellTab.sellVendorRow = vendorRow

		local vendorLbl = vendorRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		vendorLbl:SetPoint("LEFT", vendorRow, "LEFT", 8, 0)
		vendorLbl:SetHeight(16)
		vendorLbl:SetJustifyH("LEFT")
		vendorLbl:SetJustifyV("MIDDLE")
		vendorLbl:SetWordWrap(false)
		applySafeFont(vendorLbl, 10, "semibold")
		vendorLbl:SetText("Vendor Value")
		AHSellTab.sellVendorLbl = vendorLbl

		local vendorValFs = vendorRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		vendorValFs:SetPoint("RIGHT", vendorRow, "RIGHT", -8, 0)
		vendorValFs:SetPoint("LEFT", vendorLbl, "RIGHT", 6, 0)
		vendorValFs:SetHeight(16)
		vendorValFs:SetJustifyH("RIGHT")
		vendorValFs:SetJustifyV("MIDDLE")
		vendorValFs:SetWordWrap(false)
		applySafeFont(vendorValFs, 10, "semibold")
		AHSellTab.sellVendorValFs = vendorValFs

		-- Duration row (2h / 8h / 24h) between Vendor Value and Deposit
		local durRow = CreateFrame("Frame", nil, zone3)
		durRow:SetPoint("TOPLEFT", zone3, "TOPLEFT", 0, -26)
		durRow:SetPoint("TOPRIGHT", zone3, "TOPRIGHT", 0, -26)
		durRow:SetHeight(22)
		AHSellTab.sellDurRow = durRow

		local durLbl = durRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		durLbl:SetPoint("LEFT", durRow, "LEFT", 0, 0)
		durLbl:SetWidth(56)
		durLbl:SetHeight(22)
		durLbl:SetJustifyH("LEFT")
		durLbl:SetJustifyV("MIDDLE")
		durLbl:SetWordWrap(false)
		applySafeFont(durLbl, 10, "semibold")
		AHSellTab.sellDurLbl = durLbl

		local durBtns = {}
		for dIdx = 1, 3 do
			local db = makeFramedBtn(durRow, 82, 22, SELL_DUR_LABELS[dIdx], 9.5)
			if dIdx == 1 then
				db:SetPoint("LEFT", durLbl, "RIGHT", 4, 0)
			else
				db:SetPoint("LEFT", durBtns[dIdx - 1], "RIGHT", 5, 0)
			end
			db:SetScript("OnClick", function()
				clearSellInputFocus()
				local of = getOrderFlow()
				if of and of.SetSellDuration then of.SetSellDuration(dIdx) end
			end)
			durBtns[dIdx] = db
		end
		AHSellTab.sellDurBtns = durBtns

		-- Standalone Deposit Box directly underneath Duration (twin of Vendor Value)
		local depRow = CreateFrame("Frame", nil, zone3)
		depRow:SetPoint("TOPLEFT", zone3, "TOPLEFT", 0, -52)
		depRow:SetPoint("TOPRIGHT", zone3, "TOPRIGHT", 0, -52)
		depRow:SetHeight(22)
		if depRow.EnableMouse then depRow:EnableMouse(true) end
		depRow.plate = ns.Theme.NineApple(depRow, "glass_r8",
			{ 0.012, 0.016, 0.025, 0.94 },
			{ 0.94, 0.60, 0.16, 0.48 },
			{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
		addTip(depRow, "Auction Deposit", "Upfront deposit held while your auction is active. Refunded when sold; forfeited if canceled or expired.")
		AHSellTab.sellDepRow = depRow

		local depLbl = depRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		depLbl:SetPoint("LEFT", depRow, "LEFT", 8, 0)
		depLbl:SetHeight(16)
		depLbl:SetJustifyH("LEFT")
		depLbl:SetJustifyV("MIDDLE")
		depLbl:SetWordWrap(false)
		applySafeFont(depLbl, 10, "semibold")
		depLbl:SetText("Deposit")
		AHSellTab.sellDepLbl = depLbl

		local depValFs = depRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		depValFs:SetPoint("RIGHT", depRow, "RIGHT", -8, 0)
		depValFs:SetPoint("LEFT", depLbl, "RIGHT", 6, 0)
		depValFs:SetHeight(16)
		depValFs:SetJustifyH("RIGHT")
		depValFs:SetJustifyV("MIDDLE")
		depValFs:SetWordWrap(false)
		applySafeFont(depValFs, 10, "semibold")
		AHSellTab.sellDepValFs = depValFs

		-- Complete Cost & Payout Summary Card (4 crisp uniform-font rows + 1px hairline before Net Payout)
		local summaryCard = CreateFrame("Frame", nil, zone3)
		summaryCard:SetPoint("TOPLEFT", zone3, "TOPLEFT", 0, -78)
		summaryCard:SetPoint("BOTTOMRIGHT", zone3, "BOTTOMRIGHT", 0, 0)
		summaryCard:SetHeight(78)
		if summaryCard.EnableMouse then summaryCard:EnableMouse(true) end
		summaryCard.plate = ns.Theme.NineApple(summaryCard, "glass_r8",
			{ 0.012, 0.016, 0.025, 0.94 },
			{ 0.24, 0.68, 0.96, 0.46 },
			{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
		local summaryTopAccent = summaryCard:CreateTexture(nil, "ARTWORK", nil, 2)
		summaryTopAccent:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 2, -1)
		summaryTopAccent:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -2, -1)
		summaryTopAccent:SetHeight(2)
		AHSellTab.sellSummaryTopAccent = summaryTopAccent
		addTip(summaryCard, "Cost & Payout Summary",
			"Price / Item: Unit buyout and per-item net after the 5% AH fee.\n"
			.. "Total Price: Gross buyout (Quantity x Price).\n"
			.. "AH Cut (5%): Auction House fee deducted when your auction sells.\n"
			.. "Net Payout (95%): Gold mailed to you after the 5% AH cut.")
		AHSellTab.sellSummaryCard = summaryCard

		-- Row 1: Price / Item (uniform 10pt font across all summary rows)
		local unitRow = CreateFrame("Frame", nil, summaryCard)
		unitRow:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 8, -5)
		unitRow:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -8, -5)
		unitRow:SetHeight(16)
		AHSellTab.sellUnitRow = unitRow

		local unitLbl = unitRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		unitLbl:SetPoint("LEFT", unitRow, "LEFT", 0, 0)
		unitLbl:SetHeight(16)
		unitLbl:SetJustifyH("LEFT")
		unitLbl:SetJustifyV("MIDDLE")
		unitLbl:SetWordWrap(false)
		applySafeFont(unitLbl, 10, "semibold")
		AHSellTab.sellUnitLbl = unitLbl

		local unitSummaryFs = unitRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		unitSummaryFs:SetPoint("RIGHT", unitRow, "RIGHT", 0, 0)
		unitSummaryFs:SetPoint("LEFT", unitLbl, "RIGHT", 4, 0)
		unitSummaryFs:SetHeight(16)
		unitSummaryFs:SetJustifyH("RIGHT")
		unitSummaryFs:SetJustifyV("MIDDLE")
		unitSummaryFs:SetWordWrap(false)
		applySafeFont(unitSummaryFs, 10, "semibold")
		AHSellTab.sellUnitSummaryFs = unitSummaryFs

		-- Row 2: Total Price (Gross)
		local totalLbl = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		totalLbl:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 8, -22)
		totalLbl:SetHeight(16)
		totalLbl:SetJustifyH("LEFT")
		totalLbl:SetJustifyV("MIDDLE")
		totalLbl:SetWordWrap(false)
		applySafeFont(totalLbl, 10, "semibold")
		AHSellTab.sellTotalLbl = totalLbl

		local totalValFs = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		totalValFs:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -8, -22)
		totalValFs:SetPoint("LEFT", totalLbl, "RIGHT", 4, 0)
		totalValFs:SetHeight(16)
		totalValFs:SetJustifyH("RIGHT")
		totalValFs:SetJustifyV("MIDDLE")
		totalValFs:SetWordWrap(false)
		applySafeFont(totalValFs, 10, "semibold")
		AHSellTab.sellTotalValFs = totalValFs

		-- Row 3: AH Cut (5%)
		local cutLbl = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cutLbl:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 8, -39)
		cutLbl:SetHeight(16)
		cutLbl:SetJustifyH("LEFT")
		cutLbl:SetJustifyV("MIDDLE")
		cutLbl:SetWordWrap(false)
		applySafeFont(cutLbl, 10, "semibold")
		AHSellTab.sellCutLbl = cutLbl

		local cutValFs = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cutValFs:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -8, -39)
		cutValFs:SetPoint("LEFT", cutLbl, "RIGHT", 4, 0)
		cutValFs:SetHeight(16)
		cutValFs:SetJustifyH("RIGHT")
		cutValFs:SetJustifyV("MIDDLE")
		cutValFs:SetWordWrap(false)
		applySafeFont(cutValFs, 10, "semibold")
		AHSellTab.sellCutValFs = cutValFs

		-- 1px hairline divider before Net Payout
		local summarySep = summaryCard:CreateTexture(nil, "ARTWORK")
		summarySep:SetHeight(1)
		summarySep:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 8, -56)
		summarySep:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -8, -56)
		AHSellTab.sellSummarySep = summarySep

		-- Row 4 (bottom): Net Payout (95%)
		local netLbl = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		netLbl:SetPoint("BOTTOMLEFT", summaryCard, "BOTTOMLEFT", 8, 3)
		netLbl:SetHeight(18)
		netLbl:SetJustifyH("LEFT")
		netLbl:SetJustifyV("MIDDLE")
		netLbl:SetWordWrap(false)
		applySafeFont(netLbl, 10.5, "bold")
		AHSellTab.sellNetLbl = netLbl

		local netValFs = summaryCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		netValFs:SetPoint("BOTTOMRIGHT", summaryCard, "BOTTOMRIGHT", -8, 3)
		netValFs:SetPoint("LEFT", netLbl, "RIGHT", 4, 0)
		netValFs:SetHeight(18)
		netValFs:SetJustifyH("RIGHT")
		netValFs:SetJustifyV("MIDDLE")
		netValFs:SetWordWrap(false)
		applySafeFont(netValFs, 10.5, "bold")
		AHSellTab.sellNetValFs = netValFs

		-- Compatibility proxies for tests reading sellDepFs / sellTotalFs text directly
		AHSellTab.sellDepFs = {
			GetText = function()
				return "Deposit: " .. tostring(depValFs:GetText() or "")
			end,
			IsShown = function() return depValFs:IsShown() end,
		}
		AHSellTab.sellTotalFs = {
			GetText = function()
				local lbl = tostring(totalLbl:GetText() or "Total Price")
				return lbl .. ": " .. tostring(totalValFs:GetText() or "")
			end,
			IsShown = function() return totalValFs:IsShown() end,
		}
	end

	-- Always-Shown Zero-Shift Notice Banner directly under Top Sale Bar
	local noticeBar = CreateFrame("Frame", nil, tabFrame)
	noticeBar:SetHeight(20)
	noticeBar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
	noticeBar:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", 0, -4)
	noticeBar.plate = ns.Theme.NineApple(noticeBar, "glass_r8",
		{ 0.03, 0.08, 0.05, 0.72 },
		{ 0.83, 0.64, 0.24, 0.20 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 6, noSpecular = true })
	local noticeFs = noticeBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	noticeFs:SetPoint("LEFT", noticeBar, "LEFT", 8, 0)
	noticeFs:SetPoint("RIGHT", noticeBar, "RIGHT", -8, 0)
	noticeFs:SetJustifyH("LEFT")
	noticeFs:SetWordWrap(false)
	applySafeFont(noticeFs, 9.5, "semibold")
	noticeFs:SetText(palHex("hexMuted", "98989d") .. "Waiting for first action...|r")
	noticeBar:Show()
	AHSellTab.noticeBar = noticeBar
	AHSellTab.noticeFs = noticeFs

	-- Bottom-Left Categorized Bag Pane (permanently anchored below noticeBar for zero layout shift)
	local bagPane = CreateFrame("Frame", nil, tabFrame)
	bagPane:SetWidth(234)
	bagPane:SetPoint("TOPLEFT", noticeBar, "BOTTOMLEFT", 0, -6)
	bagPane:SetPoint("BOTTOMLEFT", tabFrame, "BOTTOMLEFT", 10, 10)
	bagPane.plate = ns.Theme.NineApple(bagPane, "glass_r10",
		{ 0.020, 0.026, 0.038, 0.94 },
		{ 0.83, 0.64, 0.24, 0.50 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	local bagTopAccent = bagPane:CreateTexture(nil, "ARTWORK", nil, 2)
	bagTopAccent:SetPoint("TOPLEFT", bagPane, "TOPLEFT", 2, -1)
	bagTopAccent:SetPoint("TOPRIGHT", bagPane, "TOPRIGHT", -2, -1)
	bagTopAccent:SetHeight(2)
	AHSellTab.sellBagTopAccent = bagTopAccent
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
	AHSellTab.sellBagHintFs = nil

	local bagGrid = CreateFrame("Frame", nil, bagPane)
	bagGrid:SetPoint("TOPLEFT", bagPane, "TOPLEFT", 8, -26)
	bagGrid:SetPoint("BOTTOMRIGHT", bagPane, "BOTTOMRIGHT", -6, 8)
	AHSellTab.sellBagGrid = bagGrid

	local function setBagScroll(newOff)
		local visLayCount = getBagVisibleLayoutCount()
		local maxOff = math.max(0, #bagLayoutCache - visLayCount)
		local clamped = math.max(0, math.min(maxOff, math.floor(newOff or 0)))
		if clamped == bagScrollOffset then return end
		bagScrollOffset = clamped
		renderBagGrid(false, isLightTheme())
	end
	local function stepBagScroll(delta)
		setBagScroll(bagScrollOffset - (delta > 0 and 1 or -1))
	end
	if bagGrid.EnableMouseWheel then bagGrid:EnableMouseWheel(true) end
	bagGrid:SetScript("OnMouseWheel", function(_, delta) stepBagScroll(delta) end)
	local bagScroll = makeLightScrollbar(bagGrid, stepBagScroll, setBagScroll)
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

	-- Lightweight bag tiles with pre-allocated hover sheen & tactile click micro-animation
	local bagTiles = {}
	for i = 1, 45 do
		local tile = CreateFrame("Button", nil, bagGrid)
		tile:SetSize(BAG_TILE_SZ, BAG_TILE_SZ)
		tile._hovered = false
		tile._pressed = false
		tile._pressGen = 0
		tile._pressPending = 0
		tile._texInset = 3
		tile._br, tile._bg, tile._bb, tile._ba = 0.83, 0.64, 0.24, 0.45

		local borderTex = tile:CreateTexture(nil, "BACKGROUND", nil, 0)
		borderTex:SetAllPoints(tile)
		borderTex:SetColorTexture(0.83, 0.64, 0.24, 0.45)
		tile.borderTex = borderTex

		local fillTex = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
		fillTex:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
		fillTex:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
		fillTex:SetColorTexture(0.04, 0.11, 0.08, 0.94)
		tile.fillTex = fillTex

		local tex = tile:CreateTexture(nil, "ARTWORK")
		tex:SetPoint("TOPLEFT", tile, "TOPLEFT", 3, -3)
		tex:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -3, 3)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		tile.tex = tex

		local hoverTex = tile:CreateTexture(nil, "OVERLAY", nil, 1)
		hoverTex:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
		hoverTex:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
		hoverTex:SetColorTexture(1.0, 0.94, 0.72, 0.18)
		hoverTex:Hide()
		tile.hoverTex = hoverTex

		local pressTex = tile:CreateTexture(nil, "OVERLAY", nil, 2)
		pressTex:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
		pressTex:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -1, 1)
		pressTex:SetColorTexture(1.0, 1.0, 1.0, 0.28)
		pressTex:Hide()
		tile.pressTex = pressTex

		tile._pressRestore = function()
			tile._pressPending = math.max(0, (tile._pressPending or 1) - 1)
			if tile._pressPending > 0 then return end
			if not tile._pressed then
				setTileIconInset(tile, 3)
			end
			pressTex:Hide()
		end
		tile.PlayPressPulse = bagTilePlayPressPulse

		local cntFs = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cntFs:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -3, 2)
		applySafeFont(cntFs, 9, "bold")
		tile.cntFs = cntFs

		if tile.RegisterForClicks then tile:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
		tile:SetScript("OnMouseDown", function(self)
			if not self._bagRec then return end
			self._pressed = true
			setTileIconInset(self, 5)
		end)
		tile:SetScript("OnMouseUp", function(self)
			self._pressed = false
			if (self._pressPending or 0) <= 0 then
				setTileIconInset(self, 3)
			end
		end)
		tile:SetScript("OnClick", function(self)
			local rec = self._bagRec
			if not rec then return end
			self:PlayPressPulse()
			clearSellInputFocus()
			local of = getOrderFlow()
			if not (of and of.AddBagItemToSell) then return end
			of.AddBagItemToSell(rec.itemID, nil, {
				channel = "ah",
				itemLink = rec.itemLink,
				name = rec.name,
				classID = rec.classID,
				itemLevel = rec.itemLevel,
				quality = rec.quality,
				useDefaultQty = true,
			})
		end)
		tile:SetScript("OnEnter", function(self)
			self._hovered = true
			hoverTex:Show()
			borderTex:SetColorTexture(self._br or 0.83, self._bg or 0.64, self._bb or 0.24, 1.0)
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
			GameTooltip:AddLine("Click: Select / Stage for AH", 0.30, 0.92, 0.56)
			if (rec.vendorSell or 0) > 0 then
				GameTooltip:AddLine("Vendor Value: " .. formatSellCoinMoney(rec.vendorSell) .. " ea", 0.98, 0.82, 0.38)
			end
			if ns.Theme and ns.Theme.LiftTooltip then ns.Theme.LiftTooltip(GameTooltip) end
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", function(self)
			self._hovered = false
			self._pressed = false
			hoverTex:Hide()
			borderTex:SetColorTexture(self._br or 0.83, self._bg or 0.64, self._bb or 0.24, self._ba or 0.72)
			if (self._pressPending or 0) <= 0 then
				setTileIconInset(self, 3)
			end
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
		{ 0.014, 0.020, 0.032, 0.95 },
		{ 0.22, 0.66, 0.94, 0.48 },
		{ layer = "BACKGROUND", sub = 0, cornerSize = 8, noSpecular = true })
	local pricesTopAccent = pricesBox:CreateTexture(nil, "ARTWORK", nil, 2)
	pricesTopAccent:SetPoint("TOPLEFT", pricesBox, "TOPLEFT", 2, -1)
	pricesTopAccent:SetPoint("TOPRIGHT", pricesBox, "TOPRIGHT", -2, -1)
	pricesTopAccent:SetHeight(2)
	AHSellTab.sellPricesTopAccent = pricesTopAccent
	AHSellTab.sellPricesBox = pricesBox
	AHSellTab.sellPricesPlate = pricesPlate

	-- Sub-Tab 1: Current Prices (Auctionator-Parity 3-col Commodity / 5-col Equipment + vertical column guide lines)
	local pricesView = CreateFrame("Frame", nil, pricesBox)
	pricesView:SetAllPoints(pricesBox)
	AHSellTab.sellPricesView = pricesView

	local pHdr = CreateFrame("Frame", nil, pricesView)
	pHdr:SetPoint("TOPLEFT", pricesView, "TOPLEFT", 10, -6)
	pHdr:SetPoint("TOPRIGHT", pricesView, "TOPRIGHT", -10, -6)
	pHdr:SetHeight(20)
	AHSellTab.sellPricesHdr = pHdr

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
	local pCol2 = makeColHdr("Bid Price", "LEFT")
	local pCol3 = makeColHdr("Avail", "RIGHT")
	local pCol4 = makeColHdr("iLvl", "RIGHT")
	local pCol5 = makeColHdr("Owned?", "RIGHT")
	AHSellTab.sellPricesCol1 = pCol1
	AHSellTab.sellPricesCol2 = pCol2
	AHSellTab.sellPricesCol3 = pCol3
	AHSellTab.sellPricesCol4 = pCol4
	AHSellTab.sellPricesCol5 = pCol5

	local pListArea = CreateFrame("Frame", nil, pricesView)
	pListArea:SetPoint("TOPLEFT", pHdr, "BOTTOMLEFT", 0, -2)
	pListArea:SetPoint("BOTTOMRIGHT", pricesView, "BOTTOMRIGHT", -10, 6)
	AHSellTab.sellPricesListArea = pListArea
	if pListArea.HookScript then
		pListArea:HookScript("OnSizeChanged", function()
			lastPricesLayoutKey = nil
		end)
	end

	-- 4 vertical column guide lines spanning from pHdr top down to pListArea bottom
	local vDivs = {}
	for i = 1, 4 do
		local d = pricesView:CreateTexture(nil, "ARTWORK")
		d:SetWidth(1)
		d:Hide()
		vDivs[i] = d
	end
	AHSellTab.sellPricesVDivs = vDivs

	local pEmptyFs = pListArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pEmptyFs:SetPoint("CENTER", pListArea, "CENTER", 0, 0)
	pEmptyFs:SetJustifyH("CENTER")
	applySafeFont(pEmptyFs, 10.5, "semibold")
	pEmptyFs:Hide()
	AHSellTab.sellPricesEmptyFs = pEmptyFs

	local function setPricesScroll(newOff)
		local list = getCurrentSellListings()
		local visRows = getVisibleRowCount(pListArea, SELL_PRICES_ROW_H, SELL_PRICES_VISIBLE_ROWS, 3)
		local maxOff = math.max(0, #list - visRows)
		local clamped = math.max(0, math.min(maxOff, math.floor(newOff or 0)))
		if clamped == pricesScrollOffset then return end
		pricesScrollOffset = clamped
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell or { items = {}, activeIndex = 1 }
		local cur = sl.items and sl.items[sl.activeIndex]
		renderPricesList(of, sl, cur, isLightTheme())
	end
	local function stepPricesScroll(delta)
		setPricesScroll(pricesScrollOffset - (delta > 0 and 1 or -1))
	end
	if pListArea.EnableMouseWheel then pListArea:EnableMouseWheel(true) end
	pListArea:SetScript("OnMouseWheel", function(_, delta) stepPricesScroll(delta) end)
	local pScroll = makeLightScrollbar(pListArea, stepPricesScroll, setPricesScroll)
	AHSellTab.sellPricesScroll = pScroll

	local pRows = {}
	for i = 1, SELL_PRICES_VISIBLE_ROWS do
		local pr = CreateFrame("Button", nil, pListArea)
		pr:SetHeight(SELL_PRICES_ROW_H)
		pr.bg = pr:CreateTexture(nil, "BACKGROUND")
		pr.bg:SetAllPoints()
		pr.hoverTex = pr:CreateTexture(nil, "ARTWORK", nil, 1)
		pr.hoverTex:SetAllPoints()
		pr.hoverTex:SetColorTexture(1.0, 0.95, 0.80, 0.10)
		pr.hoverTex:Hide()
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
		pr.c5 = makeCell("RIGHT")
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
			if not self._listing then return end
			if self.hoverTex then self.hoverTex:Show() end
			if not GameTooltip then return end
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
		pr:SetScript("OnLeave", function(self)
			if self.hoverTex then self.hoverTex:Hide() end
			if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
		end)
		pr:Hide()
		pRows[i] = pr
	end
	AHSellTab.sellPricesRows = pRows

	-- Sub-Tab 2: Sell Queue (no per-row channel toggle button)
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

	local function setQueueScroll(newOff)
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell or { items = {}, activeIndex = 1 }
		local items = sl.items or {}
		local visRows = getVisibleRowCount(qListArea, SELL_QUEUE_ROW_H, SELL_QUEUE_VISIBLE_ROWS, 3)
		local maxOff = math.max(0, #items - visRows)
		local clamped = math.max(0, math.min(maxOff, math.floor(newOff or 0)))
		if clamped == queueScrollOffset then return end
		queueScrollOffset = clamped
		renderQueueList(of, sl, items, isLightTheme())
	end
	local function stepQueueScroll(delta)
		setQueueScroll(queueScrollOffset - (delta > 0 and 1 or -1))
	end
	if qListArea.EnableMouseWheel then qListArea:EnableMouseWheel(true) end
	qListArea:SetScript("OnMouseWheel", function(_, delta) stepQueueScroll(delta) end)
	local qScroll = makeLightScrollbar(qListArea, stepQueueScroll, setQueueScroll)
	AHSellTab.sellQueueScroll = qScroll

	local qRows = {}
	for i = 1, SELL_QUEUE_VISIBLE_ROWS do
		local qr = CreateFrame("Button", nil, qListArea)
		qr:SetHeight(SELL_QUEUE_ROW_H)
		qr.bg = qr:CreateTexture(nil, "BACKGROUND")
		qr.bg:SetAllPoints()
		qr.hoverTex = qr:CreateTexture(nil, "ARTWORK", nil, 1)
		qr.hoverTex:SetAllPoints()
		qr.hoverTex:SetColorTexture(1.0, 0.95, 0.80, 0.10)
		qr.hoverTex:Hide()

		qr.icon = qr:CreateTexture(nil, "ARTWORK")
		qr.icon:SetSize(20, 20)
		qr.icon:SetPoint("LEFT", qr, "LEFT", 4, 0)
		qr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		qr.removeBtn = makeFramedBtn(qr, 20, 20, "X", 9)
		qr.removeBtn:SetPoint("RIGHT", qr, "RIGHT", -2, 0)
		qr.removeBtn:SetScript("OnClick", function()
			if not qr._itemIndex then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.RemoveSellItem then of.RemoveSellItem(qr._itemIndex) end
		end)

		qr.priceFs = qr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qr.priceFs:SetPoint("RIGHT", qr.removeBtn, "LEFT", -10, 0)
		qr.priceFs:SetWidth(116)
		qr.priceFs:SetJustifyH("RIGHT")
		qr.priceFs:SetWordWrap(false)
		applySafeFont(qr.priceFs, 9.5, "semibold")

		qr.qtyFs = qr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qr.qtyFs:SetPoint("RIGHT", qr.priceFs, "LEFT", -10, 0)
		qr.qtyFs:SetWidth(58)
		qr.qtyFs:SetJustifyH("RIGHT")
		qr.qtyFs:SetWordWrap(false)
		applySafeFont(qr.qtyFs, 9.5, "regular")

		qr.nameFs = qr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qr.nameFs:SetPoint("LEFT", qr.icon, "RIGHT", 6, 0)
		qr.nameFs:SetPoint("RIGHT", qr.qtyFs, "LEFT", -8, 0)
		qr.nameFs:SetJustifyH("LEFT")
		qr.nameFs:SetWordWrap(false)
		applySafeFont(qr.nameFs, 10, "semibold")

		qr:SetScript("OnClick", function(self)
			if not self._itemIndex then return end
			clearSellInputFocus()
			local of = getOrderFlow()
			if of and of.SelectSellItem then of.SelectSellItem(self._itemIndex) end
		end)
		qr:SetScript("OnEnter", function(self)
			if self._itemIndex and self.hoverTex then self.hoverTex:Show() end
		end)
		qr:SetScript("OnLeave", function(self)
			if self.hoverTex then self.hoverTex:Hide() end
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

	local function setHistoryScroll(newOff)
		local visRows = getVisibleRowCount(hListArea, SELL_HISTORY_ROW_H, SELL_HISTORY_VISIBLE_ROWS, 3)
		local maxOff = math.max(0, #historyCacheRows - visRows)
		local clamped = math.max(0, math.min(maxOff, math.floor(newOff or 0)))
		if clamped == historyScrollOffset then return end
		historyScrollOffset = clamped
		local of = getOrderFlow()
		local sl = of and of.GetState and of.GetState().stages.sell or { items = {}, activeIndex = 1 }
		local cur = sl.items and sl.items[sl.activeIndex]
		renderHistoryList(true, of, sl, cur, isLightTheme())
	end
	local function stepHistoryScroll(delta)
		setHistoryScroll(historyScrollOffset - (delta > 0 and 1 or -1))
	end
	if hListArea.EnableMouseWheel then hListArea:EnableMouseWheel(true) end
	hListArea:SetScript("OnMouseWheel", function(_, delta) stepHistoryScroll(delta) end)
	local hScroll = makeLightScrollbar(hListArea, stepHistoryScroll, setHistoryScroll)
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
			lastChromeKey = nil
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
	bagCacheDirty = true
	local ok, res = of.AddCursorItemToSell(b, s)
	AHSellTab.Render()
	AHSellTab.SyncSpaceBinding()
	return ok, res
end

local function triggerOpenSellAutoScan(of)
	if not (of and of.ScanSellItemMarket and isAHOpensafe()) then return false end
	local sl = of.GetState and of.GetState().stages.sell
	if not (sl and sl.items) then return false end
	local cur = sl.items[sl.activeIndex]
	if not (cur and cur.channel == "ah" and (cur.remaining or 0) > 0
		and cur.status ~= "done" and cur.status ~= "skipped") then
		return false
	end
	if sl.pendingSearch and sl.pendingSearch.itemID == cur.itemID then
		return false
	end
	local itemKey = tostring(cur.itemID or 0) .. ":" .. tostring(cur.itemLink or "") .. ":" .. tostring(sl.activeIndex or 1)
	local now = nowAutoScanMono()
	if lastAutoScanItemKey == itemKey and now > 0 and lastAutoScanAt > 0 and (now - lastAutoScanAt) < 2.0 then
		return false
	end
	local ok, err = of.ScanSellItemMarket(sl.activeIndex, "select")
	if ok or err == "throttled" or err == "channel_busy" then
		lastAutoScanItemKey = itemKey
		lastAutoScanAt = now
	end
	return ok, err
end

layoutTopBar = function()
	if not (AHSellTab.topBar and AHSellTab.sellZone1 and AHSellTab.sellForm and AHSellTab.sellZone3) then return end
	local w = (AHSellTab.topBar.GetWidth and AHSellTab.topBar:GetWidth()) or 0
	if w < 600 then
		local ahf = _G.AuctionHouseFrame
		local ahfW = (ahf and ahf.GetWidth and ahf:GetWidth()) or 0
		if ahfW >= 640 then
			w = ahfW - 32
		else
			local tw = (tabFrame and tabFrame.GetWidth and tabFrame:GetWidth()) or 784
			w = math.max(764, tw - 20)
		end
	end
	w = math.floor(w + 0.5)
	if w == lastTopBarLayoutW then return end
	lastTopBarLayoutW = w

	local wide = (w >= 960)
	local pad = wide and 12 or 8
	local gap = wide and 12 or 6
	local z1W = wide and math.min(286, math.floor(w * 0.27)) or math.min(176, math.floor(w * 0.228))
	local z3W = wide and math.min(324, math.floor(w * 0.305)) or math.min(244, math.floor(w * 0.318))
	local div1X = pad + z1W + gap
	local z2X = div1X + gap
	local div2X = w - pad - z3W - gap
	local z2W = math.max(200, div2X - z2X - gap)

	AHSellTab.sellZone1:ClearAllPoints()
	AHSellTab.sellZone1:SetPoint("TOPLEFT", AHSellTab.topBar, "TOPLEFT", pad, -10)
	AHSellTab.sellZone1:SetPoint("BOTTOMLEFT", AHSellTab.topBar, "BOTTOMLEFT", pad, 10)
	AHSellTab.sellZone1:SetWidth(z1W)

	local iconSz = wide and 56 or 44
	local txtX = iconSz + 10
	local txtW = math.max(104, z1W - txtX - 2)
	local fullZ1W = math.max(150, z1W - 4)
	AHSellTab.iconDropBtn:SetSize(iconSz, iconSz)
	AHSellTab.zone1EyebrowFs:ClearAllPoints()
	AHSellTab.zone1EyebrowFs:SetPoint("TOPLEFT", AHSellTab.sellZone1, "TOPLEFT", 2, -2)
	AHSellTab.zone1EyebrowFs:SetWidth(fullZ1W)
	AHSellTab.activeFs:ClearAllPoints()
	AHSellTab.activeFs:SetPoint("TOPLEFT", AHSellTab.sellZone1, "TOPLEFT", txtX, -22)
	AHSellTab.activeFs:SetWidth(txtW)
	AHSellTab.spotSubFs:ClearAllPoints()
	AHSellTab.spotSubFs:SetPoint("TOPLEFT", AHSellTab.sellZone1, "TOPLEFT", 2, wide and -88 or -76)
	AHSellTab.spotSubFs:SetWidth(fullZ1W)
	AHSellTab.spotMetaFs:SetWidth(fullZ1W)

	AHSellTab.topDiv1:ClearAllPoints()
	AHSellTab.topDiv1:SetPoint("TOP", AHSellTab.topBar, "TOPLEFT", div1X, -12)
	AHSellTab.topDiv1:SetPoint("BOTTOM", AHSellTab.topBar, "BOTTOMLEFT", div1X, 12)

	AHSellTab.topDiv2:ClearAllPoints()
	AHSellTab.topDiv2:SetPoint("TOP", AHSellTab.topBar, "TOPLEFT", div2X, -12)
	AHSellTab.topDiv2:SetPoint("BOTTOM", AHSellTab.topBar, "BOTTOMLEFT", div2X, 12)

	AHSellTab.sellForm:ClearAllPoints()
	AHSellTab.sellForm:SetPoint("TOPLEFT", AHSellTab.topBar, "TOPLEFT", z2X, -10)
	AHSellTab.sellForm:SetSize(z2W, 156)

	local lblW = wide and 82 or 68
	local railGap = wide and 8 or 4
	local qtyBtnW = wide and 24 or 22
	local qtyGap = wide and 4 or 3
	local qtyBoxW = wide and 56 or 48
	local maxBtnW = wide and 50 or 42
	local maxGap = wide and 8 or 5
	local maxInfoGap = wide and 10 or 6

	AHSellTab.sellQtyLbl:SetWidth(lblW)
	AHSellTab.sellPriceLbl:SetWidth(lblW)
	AHSellTab.sellRuleLbl:SetWidth(lblW)
	AHSellTab.sellBidLbl:SetWidth(lblW)

	AHSellTab.sellQtyMinus:SetSize(qtyBtnW, 24)
	AHSellTab.sellQtyMinus:ClearAllPoints()
	AHSellTab.sellQtyMinus:SetPoint("LEFT", AHSellTab.sellQtyLbl, "RIGHT", railGap, 0)
	AHSellTab.sellQtyBox:SetWidth(qtyBoxW)
	AHSellTab.sellQtyBox:ClearAllPoints()
	AHSellTab.sellQtyBox:SetPoint("LEFT", AHSellTab.sellQtyMinus, "RIGHT", qtyGap, 0)
	AHSellTab.sellQtyPlus:SetSize(qtyBtnW, 24)
	AHSellTab.sellQtyPlus:ClearAllPoints()
	AHSellTab.sellQtyPlus:SetPoint("LEFT", AHSellTab.sellQtyBox, "RIGHT", qtyGap, 0)
	AHSellTab.sellMaxBtn:SetSize(maxBtnW, 24)
	AHSellTab.sellMaxBtn:ClearAllPoints()
	AHSellTab.sellMaxBtn:SetPoint("LEFT", AHSellTab.sellQtyPlus, "RIGHT", maxGap, 0)
	AHSellTab.sellMaxInfoFs:ClearAllPoints()
	AHSellTab.sellMaxInfoFs:SetPoint("LEFT", AHSellTab.sellMaxBtn, "RIGHT", maxInfoGap, 0)

	local gW = wide and 66 or 50
	local scW = wide and 36 or 30
	local tagGap = wide and 3 or 2
	local segGap = wide and 6 or 4
	local pillGap = wide and 10 or 6

	AHSellTab.sellPriceGBox:SetWidth(gW)
	AHSellTab.sellPriceGBox:ClearAllPoints()
	AHSellTab.sellPriceGBox:SetPoint("LEFT", AHSellTab.sellPriceLbl, "RIGHT", railGap, 0)
	AHSellTab.sellPriceGTag:ClearAllPoints()
	AHSellTab.sellPriceGTag:SetPoint("LEFT", AHSellTab.sellPriceGBox, "RIGHT", tagGap, 0)
	AHSellTab.sellPriceSBox:SetWidth(scW)
	AHSellTab.sellPriceSBox:ClearAllPoints()
	AHSellTab.sellPriceSBox:SetPoint("LEFT", AHSellTab.sellPriceGTag, "RIGHT", segGap, 0)
	AHSellTab.sellPriceSTag:ClearAllPoints()
	AHSellTab.sellPriceSTag:SetPoint("LEFT", AHSellTab.sellPriceSBox, "RIGHT", tagGap, 0)
	AHSellTab.sellPriceCBox:SetWidth(scW)
	AHSellTab.sellPriceCBox:ClearAllPoints()
	AHSellTab.sellPriceCBox:SetPoint("LEFT", AHSellTab.sellPriceSTag, "RIGHT", segGap, 0)
	AHSellTab.sellPriceCTag:ClearAllPoints()
	AHSellTab.sellPriceCTag:SetPoint("LEFT", AHSellTab.sellPriceCBox, "RIGHT", tagGap, 0)
	AHSellTab.sellPriceSrcPill:SetWidth(wide and 64 or 50)
	AHSellTab.sellPriceSrcPill:ClearAllPoints()
	AHSellTab.sellPriceSrcPill:SetPoint("LEFT", AHSellTab.sellPriceCTag, "RIGHT", pillGap, 0)

	-- Zone 2 Row 3: Undercut Rule buttons aligned on identical Zone 2 rail directly under Unit Price
	local ucGap = wide and 5 or 3
	local ruleRailW = math.max(180, math.min(wide and 272 or 234, z2W - lblW - railGap))
	local matchW = wide and 68 or 56
	local otherW = math.floor((ruleRailW - matchW - ucGap * 3) / 3)
	local lastW = ruleRailW - matchW - otherW * 2 - ucGap * 3
	for uIdx = 1, #AHSellTab.sellUcBtns do
		local ub = AHSellTab.sellUcBtns[uIdx]
		local uw = (uIdx == 1) and matchW or ((uIdx == #AHSellTab.sellUcBtns) and lastW or otherW)
		ub:SetWidth(uw)
		ub:ClearAllPoints()
		if uIdx == 1 then
			ub:SetPoint("LEFT", AHSellTab.sellRuleLbl, "RIGHT", railGap, 0)
		else
			ub:SetPoint("LEFT", AHSellTab.sellUcBtns[uIdx - 1], "RIGHT", ucGap, 0)
		end
	end

	-- Zone 2 Row 4: Starting Bid (equipment only)
	AHSellTab.sellBidGBox:SetWidth(gW)
	AHSellTab.sellBidGBox:ClearAllPoints()
	AHSellTab.sellBidGBox:SetPoint("LEFT", AHSellTab.sellBidLbl, "RIGHT", railGap, 0)
	AHSellTab.sellBidGTag:ClearAllPoints()
	AHSellTab.sellBidGTag:SetPoint("LEFT", AHSellTab.sellBidGBox, "RIGHT", tagGap, 0)
	AHSellTab.sellBidSBox:SetWidth(scW)
	AHSellTab.sellBidSBox:ClearAllPoints()
	AHSellTab.sellBidSBox:SetPoint("LEFT", AHSellTab.sellBidGTag, "RIGHT", segGap, 0)
	AHSellTab.sellBidSTag:ClearAllPoints()
	AHSellTab.sellBidSTag:SetPoint("LEFT", AHSellTab.sellBidSBox, "RIGHT", tagGap, 0)
	AHSellTab.sellBidCBox:SetWidth(scW)
	AHSellTab.sellBidCBox:ClearAllPoints()
	AHSellTab.sellBidCBox:SetPoint("LEFT", AHSellTab.sellBidSTag, "RIGHT", segGap, 0)
	AHSellTab.sellBidCTag:ClearAllPoints()
	AHSellTab.sellBidCTag:SetPoint("LEFT", AHSellTab.sellBidCBox, "RIGHT", tagGap, 0)
	AHSellTab.sellBidHintFs:ClearAllPoints()
	AHSellTab.sellBidHintFs:SetPoint("LEFT", AHSellTab.sellBidCTag, "RIGHT", pillGap, 0)

	-- Zone 2 Row 5: Post | Refresh | context-only Cancel (both wide and compact)
	local actGap = wide and 8 or 6
	local actSpan = math.min(z2W, wide and 366 or 306)
	local pW = wide and 148 or math.floor(actSpan * 0.42)
	local refW = wide and 110 or math.floor(actSpan * 0.30)
	local canW = math.max(66, actSpan - pW - refW - actGap * 2)
	AHSellTab.postBtn:SetSize(pW, 30)
	AHSellTab.postBtn:ClearAllPoints()
	AHSellTab.postBtn:SetPoint("BOTTOMLEFT", AHSellTab.sellForm, "BOTTOMLEFT", 0, 2)
	AHSellTab.sellRefreshBtn:SetSize(refW, 30)
	AHSellTab.sellRefreshBtn:ClearAllPoints()
	AHSellTab.sellRefreshBtn:SetPoint("LEFT", AHSellTab.postBtn, "RIGHT", actGap, 0)
	AHSellTab.cancelBtn:SetSize(canW, 30)
	AHSellTab.cancelBtn:ClearAllPoints()
	AHSellTab.cancelBtn:SetPoint("LEFT", AHSellTab.sellRefreshBtn, "RIGHT", actGap, 0)

	-- Zone 3: Vendor Value -> Duration -> Complete Cost & Payout Summary Card
	AHSellTab.sellZone3:ClearAllPoints()
	AHSellTab.sellZone3:SetPoint("TOPRIGHT", AHSellTab.topBar, "TOPRIGHT", -pad, -10)
	AHSellTab.sellZone3:SetPoint("BOTTOMRIGHT", AHSellTab.topBar, "BOTTOMRIGHT", -pad, 10)
	AHSellTab.sellZone3:SetWidth(z3W)

	local z3LblW = wide and 56 or 48
	local z3Gap = 4
	local z3RailW = z3W - z3LblW - z3Gap
	AHSellTab.sellDurLbl:SetWidth(z3LblW)

	local durGap = wide and 5 or 3
	local durW = math.floor((z3RailW - durGap * 2) / 3)
	local durLastW = z3RailW - durW * 2 - durGap * 2
	for dIdx = 1, 3 do
		local db = AHSellTab.sellDurBtns[dIdx]
		db:SetWidth(dIdx == 3 and durLastW or durW)
		db:ClearAllPoints()
		if dIdx == 1 then
			db:SetPoint("LEFT", AHSellTab.sellDurLbl, "RIGHT", z3Gap, 0)
		else
			db:SetPoint("LEFT", AHSellTab.sellDurBtns[dIdx - 1], "RIGHT", durGap, 0)
		end
	end
end

local function paintStaticChrome(isLight)
	local skinKey = (ns.Theme and ns.Theme.GetSkin and ns.Theme.GetSkin()) or "default"
	local chromeKey = (isLight and "L:" or "D:") .. tostring(skinKey)
	if chromeKey == lastChromeKey then return end
	lastChromeKey = chromeKey

	local pal = getPal()
	local goldBorder = { 0.83, 0.64, 0.24 }
	local sepCol = isLight and { 0.00, 0.00, 0.00 } or goldBorder
	local boxFill = isLight and { 0.98, 0.99, 1.00, 1.0 } or { 0.012, 0.016, 0.025, 0.96 }
	local boxStroke = isLight and { 0.60, 0.65, 0.74, 0.90 } or { 0.83, 0.64, 0.24, 0.72 }
	local boxInk = isLight and { 0.07, 0.09, 0.13, 1.0 } or { 1.0, 1.0, 1.0, 1.0 }
	local topFill = isLight and { 0.95, 0.96, 0.98, 1.0 } or { 0.022, 0.028, 0.040, 0.94 }
	local bagFill = isLight and { 0.96, 0.97, 0.99, 1.0 } or { 0.020, 0.026, 0.038, 0.94 }
	local pricesFill = isLight and { 0.96, 0.97, 0.99, 1.0 } or { 0.014, 0.020, 0.032, 0.95 }
	local pricesStroke = isLight and { 0.00, 0.00, 0.00, 0.16 } or { 0.22, 0.66, 0.94, 0.48 }

	tabFrame.bgPlate:SetFill(isLight and 0.91 or 0.018, isLight and 0.93 or 0.036, isLight and 0.96 or 0.032, 0.96)
	AHSellTab.topBar.plate:SetFill(topFill[1], topFill[2], topFill[3], topFill[4])
	AHSellTab.sellBagPane.plate:SetFill(bagFill[1], bagFill[2], bagFill[3], bagFill[4])
	AHSellTab.sellPricesPlate:SetFill(pricesFill[1], pricesFill[2], pricesFill[3], pricesFill[4])
	AHSellTab.sellPricesPlate:SetStroke(pricesStroke[1], pricesStroke[2], pricesStroke[3], pricesStroke[4])
	if AHSellTab.topBarTopAccent then
		AHSellTab.topBarTopAccent:SetColorTexture(isLight and 0.14 or 0.94, isLight and 0.42 or 0.72, isLight and 0.78 or 0.22, isLight and 0.45 or 0.85)
	end
	if AHSellTab.sellBagTopAccent then
		AHSellTab.sellBagTopAccent:SetColorTexture(isLight and 0.14 or 0.94, isLight and 0.42 or 0.72, isLight and 0.78 or 0.22, isLight and 0.40 or 0.80)
	end
	if AHSellTab.sellPricesTopAccent then
		AHSellTab.sellPricesTopAccent:SetColorTexture(isLight and 0.06 or 0.24, isLight and 0.48 or 0.72, isLight and 0.88 or 0.98, isLight and 0.60 or 0.88)
	end

	local divAlpha = isLight and 0.18 or 0.46
	if AHSellTab.topDiv1 then AHSellTab.topDiv1:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], divAlpha) end
	if AHSellTab.topDiv2 then AHSellTab.topDiv2:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], divAlpha) end
	if AHSellTab.sellZone1 and AHSellTab.sellZone1.plate then
		AHSellTab.sellZone1.plate:SetFill(isLight and 0.92 or 0.012, isLight and 0.94 or 0.016, isLight and 0.97 or 0.025, isLight and 0.86 or 0.90)
		AHSellTab.sellZone1.plate:SetStroke(isLight and 0.00 or 0.83, isLight and 0.00 or 0.64, isLight and 0.00 or 0.24, isLight and 0.14 or 0.38)
	end
	if AHSellTab.sellSummarySep then AHSellTab.sellSummarySep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.14 or 0.24) end
	if AHSellTab.sellSummaryTopAccent then
		AHSellTab.sellSummaryTopAccent:SetColorTexture(isLight and 0.06 or 0.24, isLight and 0.48 or 0.72, isLight and 0.88 or 0.98, isLight and 0.55 or 0.85)
	end
	if AHSellTab.sellSummaryCard and AHSellTab.sellSummaryCard.plate then
		AHSellTab.sellSummaryCard.plate:SetFill(isLight and 0.91 or 0.012, isLight and 0.93 or 0.016, isLight and 0.96 or 0.025, isLight and 0.95 or 0.94)
		AHSellTab.sellSummaryCard.plate:SetStroke(isLight and 0.00 or 0.24, isLight and 0.00 or 0.68, isLight and 0.00 or 0.96, isLight and 0.18 or 0.46)
	end
	if AHSellTab.sellDepRow and AHSellTab.sellDepRow.plate then
		AHSellTab.sellDepRow.plate:SetFill(isLight and 0.91 or 0.012, isLight and 0.93 or 0.016, isLight and 0.96 or 0.025, isLight and 0.95 or 0.94)
		AHSellTab.sellDepRow.plate:SetStroke(isLight and 0.00 or 0.94, isLight and 0.00 or 0.60, isLight and 0.00 or 0.16, isLight and 0.18 or 0.48)
	end
	if AHSellTab.zone1EyebrowFs then
		AHSellTab.zone1EyebrowFs:SetText(palHex("hexGold", "d4b26a") .. "SELECTED ITEM|r")
	end

	AHSellTab.sellQtyLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Quantity|r")
	AHSellTab.sellBidLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Starting Bid|r")
	AHSellTab.sellRuleLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Rule|r")
	AHSellTab.sellPriceGTag:SetText(palHex("hexGold", "ffd60a") .. "g|r")
	AHSellTab.sellPriceSTag:SetText(palHex("hexSilver", "c7c7cc") .. "s|r")
	AHSellTab.sellPriceCTag:SetText(palHex("hexCopper", "e08a5e") .. "c|r")
	AHSellTab.sellBidGTag:SetText(palHex("hexGold", "ffd60a") .. "g|r")
	AHSellTab.sellBidSTag:SetText(palHex("hexSilver", "c7c7cc") .. "s|r")
	AHSellTab.sellBidCTag:SetText(palHex("hexCopper", "e08a5e") .. "c|r")
	AHSellTab.sellDurLbl:SetText(palHex("hexSecondary", "ebebf5") .. "Duration|r")
	AHSellTab.sellUnitLbl:SetText(palHex("hexMuted", "98989d") .. "Price / Item|r")
	AHSellTab.sellTotalLbl:SetText(palHex("hexMuted", "98989d") .. "Total Price|r")
	if AHSellTab.sellCutLbl then
		AHSellTab.sellCutLbl:SetText(palHex("hexMuted", "98989d") .. "AH Cut (5%)|r")
	end
	AHSellTab.sellDepLbl:SetText(palHex("hexMuted", "98989d") .. "Deposit|r")
	if AHSellTab.sellNetLbl then
		AHSellTab.sellNetLbl:SetText(palHex("hexPositive", "30d158") .. "Net Payout (95%)|r")
	end

	for _, bx in ipairs({ AHSellTab.sellQtyBox, AHSellTab.sellPriceGBox, AHSellTab.sellPriceSBox, AHSellTab.sellPriceCBox, AHSellTab.sellBidGBox, AHSellTab.sellBidSBox, AHSellTab.sellBidCBox }) do
		if bx then
			if bx.plate then
				bx.plate:SetFill(boxFill[1], boxFill[2], boxFill[3], boxFill[4])
				bx.plate:SetStroke(boxStroke[1], boxStroke[2], boxStroke[3], boxStroke[4])
			end
			if bx.SetTextColor then bx:SetTextColor(boxInk[1], boxInk[2], boxInk[3], boxInk[4]) end
		end
	end

	if AHSellTab.sellPricesHdrSep then
		AHSellTab.sellPricesHdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], 0.45)
	end
	local hdrCol = pal.textMuted or { 0.65, 0.72, 0.68, 1 }
	for _, cHdr in ipairs({ AHSellTab.sellPricesCol1, AHSellTab.sellPricesCol2, AHSellTab.sellPricesCol3, AHSellTab.sellPricesCol4, AHSellTab.sellPricesCol5 }) do
		if cHdr then cHdr:SetTextColor(hdrCol[1], hdrCol[2], hdrCol[3], 1) end
	end
	local vDivAlpha = isLight and 0.12 or 0.22
	for _, vd in ipairs(AHSellTab.sellPricesVDivs or {}) do
		vd:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], vDivAlpha)
	end
	lastPricesLayoutKey = nil
end

renderBagGrid = function(forceRescan, isLight)
	if not (AHSellTab.sellBagGrid and AHSellTab.sellBagTiles) then return end
	if forceRescan then
		local of = getOrderFlow()
		bagScanCache = (of and of.ScanSellableBags and of.ScanSellableBags()) or {}
		bagLayoutCache = buildBagCategoryLayout(bagScanCache)
		bagCacheDirty = false
		AHSellTab.sellBagCountFs:SetText(palHex("hexGold", "f7d57c") .. string.format("%d Items|r", #bagScanCache))
	end

	local totalLay = #bagLayoutCache
	local visLayCount, gridH = getBagVisibleLayoutCount()
	local maxBagOff = math.max(0, totalLay - visLayCount)
	if bagScrollOffset > maxBagOff then bagScrollOffset = maxBagOff end
	if bagScrollOffset < 0 then bagScrollOffset = 0 end
	AHSellTab.sellBagScroll:Update(bagScrollOffset, visLayCount, totalLay, isLight)

	local curY = 0
	local hdrIdx = 0
	local tileIdx = 0
	local catHdrs = AHSellTab.sellBagCatHdrs
	local tiles = AHSellTab.sellBagTiles
	local grid = AHSellTab.sellBagGrid

	for lIdx = bagScrollOffset + 1, totalLay do
		local entry = bagLayoutCache[lIdx]
		if not entry or (curY + entry.h) > gridH then break end
		if entry.kind == "header" then
			hdrIdx = hdrIdx + 1
			local hf = catHdrs[hdrIdx]
			if hf then
				if hf._posY ~= curY then
					hf._posY = curY
					hf:ClearAllPoints()
					hf:SetPoint("TOPLEFT", grid, "TOPLEFT", 2, -curY)
				end
				local txt = palHex("hexGold", "f7d57c") .. tostring(entry.label) .. "|r"
				if hf._txt ~= txt then
					hf._txt = txt
					hf:SetText(txt)
				end
				if not hf._shown then
					hf._shown = true
					hf:Show()
				end
			end
		elseif entry.kind == "row" then
			for colIdx, rec in ipairs(entry.items) do
				tileIdx = tileIdx + 1
				local tile = tiles[tileIdx]
				if tile then
					tile._bagRec = rec
					local px = (colIdx - 1) * (BAG_TILE_SZ + BAG_TILE_GAP)
					if tile._posX ~= px or tile._posY ~= curY then
						tile._posX = px
						tile._posY = curY
						tile:ClearAllPoints()
						tile:SetPoint("TOPLEFT", grid, "TOPLEFT", px, -curY)
					end
					local icon = rec.icon or resolveIconTex(rec.itemID)
					if tile._tex ~= icon then
						tile._tex = icon
						tile.tex:SetTexture(icon)
					end
					local inQ = (rec.inQueue == true)
					local q = rec.quality or 1
					if tile._inQ ~= inQ or tile._q ~= q or tile._isLight ~= isLight then
						tile._inQ = inQ
						tile._q = q
						tile._isLight = isLight
						if inQ then
							tile.fillTex:SetColorTexture(0.06, 0.28, 0.16, 0.96)
							tile._br, tile._bg, tile._bb, tile._ba = 0.24, 0.95, 0.56, 0.95
							tile.borderTex:SetColorTexture(0.24, 0.95, 0.56, tile._hovered and 1.0 or 0.95)
						else
							local r, g, b = getQualityRGB(q)
							tile.fillTex:SetColorTexture(isLight and 0.92 or 0.014, isLight and 0.94 or 0.018, isLight and 0.97 or 0.028, 0.95)
							tile._br, tile._bg, tile._bb, tile._ba = r, g, b, 0.72
							tile.borderTex:SetColorTexture(r, g, b, tile._hovered and 1.0 or 0.72)
						end
					end
					local cntTxt = (rec.totalCount and rec.totalCount > 1) and tostring(rec.totalCount) or ""
					if tile._cntTxt ~= cntTxt then
						tile._cntTxt = cntTxt
						tile.cntFs:SetText(cntTxt)
					end
					if not tile._shown then
						tile._shown = true
						tile:Show()
					end
				end
			end
		end
		curY = curY + entry.h
	end

	-- Delta-hide only previously visible unused headers and tiles
	for i = hdrIdx + 1, lastUsedBagHdrs do
		local hf = catHdrs[i]
		if hf then
			hf._shown = false
			hf:Hide()
		end
	end
	lastUsedBagHdrs = hdrIdx

	for i = tileIdx + 1, lastUsedBagTiles do
		local tile = tiles[i]
		if tile then
			tile._bagRec = nil
			tile._hovered = false
			tile._pressed = false
			tile._pressGen = (tile._pressGen or 0) + 1
			if tile.hoverTex then tile.hoverTex:Hide() end
			if tile.pressTex then tile.pressTex:Hide() end
			setTileIconInset(tile, 3)
			tile._shown = false
			tile:Hide()
		end
	end
	lastUsedBagTiles = tileIdx
end

renderPricesList = function(of, sl, cur, isLight)
	local pListArea = AHSellTab.sellPricesListArea
	if not pListArea then return end

	local listTarget = cur or sl.lastItemInfo
	local listIsComm = false
	if cur ~= nil then
		if cur.isCommodity ~= nil then
			listIsComm = (cur.isCommodity == true)
		elseif of and of.IsSellItemCommodity then
			listIsComm = (of.IsSellItemCommodity(cur) == true)
		end
	elseif listTarget then
		listIsComm = (listTarget.isCommodity == true)
	end

	local listings, scanned = getCurrentSellListings()
	local isScanning = (sl.pendingSearch ~= nil) and true or false
	local visPRows = getVisibleRowCount(pListArea, SELL_PRICES_ROW_H, SELL_PRICES_VISIBLE_ROWS, 3)
	local maxPOff = math.max(0, #listings - visPRows)
	if pricesScrollOffset > maxPOff then pricesScrollOffset = maxPOff end
	if pricesScrollOffset < 0 then pricesScrollOffset = 0 end
	local hasPScroll = AHSellTab.sellPricesScroll:Update(pricesScrollOffset, visPRows, #listings, isLight)
	local pRightPad = hasPScroll and -9 or 0

	local rawW = (pListArea.GetWidth and pListArea:GetWidth()) or 0
	if rawW < 240 then rawW = 520 end
	local areaW = math.floor(rawW + 0.5)
	local availW = math.max(320, areaW - (hasPScroll and 9 or 0))
	local layoutKey = (listIsComm and "C:" or "I:") .. tostring(areaW) .. ":" .. (hasPScroll and "1:" or "0:") .. tostring(visPRows)

	if layoutKey ~= lastPricesLayoutKey then
		lastPricesLayoutKey = layoutKey
		local pHdr = AHSellTab.sellPricesHdr
		local c1 = AHSellTab.sellPricesCol1
		local c2 = AHSellTab.sellPricesCol2
		local c3 = AHSellTab.sellPricesCol3
		local c4 = AHSellTab.sellPricesCol4
		local c5 = AHSellTab.sellPricesCol5
		local vDivs = AHSellTab.sellPricesVDivs or {}

		c5:SetText("Owned?")
		if listIsComm then
			local w5 = 64
			local x5 = availW - w5 - 4
			local w3 = 96
			local x3 = x5 - w3 - 10
			local w1 = math.max(120, x3 - 14)

			c1:ClearAllPoints(); c1:SetPoint("LEFT", pHdr, "LEFT", 6, 0); c1:SetWidth(w1); c1:SetText("Unit Price"); c1:Show()
			c2:Hide()
			c3:ClearAllPoints(); c3:SetPoint("LEFT", pHdr, "LEFT", x3, 0); c3:SetWidth(w3); c3:SetText("Avail"); c3:Show()
			c4:Hide()
			c5:ClearAllPoints(); c5:SetPoint("LEFT", pHdr, "LEFT", x5, 0); c5:SetWidth(w5); c5:Show()

			if vDivs[1] then
				vDivs[1]:ClearAllPoints()
				vDivs[1]:SetPoint("TOP", pHdr, "TOPLEFT", x3 - 5, 0)
				vDivs[1]:SetPoint("BOTTOM", pListArea, "BOTTOMLEFT", x3 - 5, 0)
				vDivs[1]:Show()
			end
			if vDivs[2] then
				vDivs[2]:ClearAllPoints()
				vDivs[2]:SetPoint("TOP", pHdr, "TOPLEFT", x5 - 5, 0)
				vDivs[2]:SetPoint("BOTTOM", pListArea, "BOTTOMLEFT", x5 - 5, 0)
				vDivs[2]:Show()
			end
			if vDivs[3] then vDivs[3]:Hide() end
			if vDivs[4] then vDivs[4]:Hide() end

			for i = 1, SELL_PRICES_VISIBLE_ROWS do
				local pr = AHSellTab.sellPricesRows[i]
				pr:ClearAllPoints()
				pr:SetPoint("TOPLEFT", pListArea, "TOPLEFT", 0, -((i - 1) * SELL_PRICES_ROW_H))
				pr:SetPoint("TOPRIGHT", pListArea, "TOPRIGHT", pRightPad, -((i - 1) * SELL_PRICES_ROW_H))
				pr.c1:ClearAllPoints(); pr.c1:SetPoint("LEFT", pr, "LEFT", 6, 0); pr.c1:SetWidth(w1)
				pr.c2:Hide()
				pr.c3:ClearAllPoints(); pr.c3:SetPoint("LEFT", pr, "LEFT", x3, 0); pr.c3:SetWidth(w3)
				pr.c4:Hide()
				pr.c5:ClearAllPoints(); pr.c5:SetPoint("LEFT", pr, "LEFT", x5, 0); pr.c5:SetWidth(w5)
			end
		else
			local w5 = 62
			local x5 = availW - w5 - 4
			local w4 = 44
			local x4 = x5 - w4 - 10
			local w3 = 48
			local x3 = x4 - w3 - 10
			local rem = math.max(150, x3 - 16)
			local w1 = math.floor(rem * 0.52)
			local x2 = 6 + w1 + 10
			local w2 = math.max(60, x3 - x2 - 10)

			c1:ClearAllPoints(); c1:SetPoint("LEFT", pHdr, "LEFT", 6, 0); c1:SetWidth(w1); c1:SetText("Buyout Price"); c1:Show()
			c2:ClearAllPoints(); c2:SetPoint("LEFT", pHdr, "LEFT", x2, 0); c2:SetWidth(w2); c2:SetText("Bid Price"); c2:Show()
			c3:ClearAllPoints(); c3:SetPoint("LEFT", pHdr, "LEFT", x3, 0); c3:SetWidth(w3); c3:SetText("Avail"); c3:Show()
			c4:ClearAllPoints(); c4:SetPoint("LEFT", pHdr, "LEFT", x4, 0); c4:SetWidth(w4); c4:SetText("iLvl"); c4:Show()
			c5:ClearAllPoints(); c5:SetPoint("LEFT", pHdr, "LEFT", x5, 0); c5:SetWidth(w5); c5:Show()

			local divXs = { x2 - 5, x3 - 5, x4 - 5, x5 - 5 }
			for dIdx = 1, 4 do
				local vd = vDivs[dIdx]
				if vd then
					vd:ClearAllPoints()
					vd:SetPoint("TOP", pHdr, "TOPLEFT", divXs[dIdx], 0)
					vd:SetPoint("BOTTOM", pListArea, "BOTTOMLEFT", divXs[dIdx], 0)
					vd:Show()
				end
			end

			for i = 1, SELL_PRICES_VISIBLE_ROWS do
				local pr = AHSellTab.sellPricesRows[i]
				pr:ClearAllPoints()
				pr:SetPoint("TOPLEFT", pListArea, "TOPLEFT", 0, -((i - 1) * SELL_PRICES_ROW_H))
				pr:SetPoint("TOPRIGHT", pListArea, "TOPRIGHT", pRightPad, -((i - 1) * SELL_PRICES_ROW_H))
				pr.c1:ClearAllPoints(); pr.c1:SetPoint("LEFT", pr, "LEFT", 6, 0); pr.c1:SetWidth(w1)
				pr.c2:ClearAllPoints(); pr.c2:SetPoint("LEFT", pr, "LEFT", x2, 0); pr.c2:SetWidth(w2); pr.c2:Show()
				pr.c3:ClearAllPoints(); pr.c3:SetPoint("LEFT", pr, "LEFT", x3, 0); pr.c3:SetWidth(w3)
				pr.c4:ClearAllPoints(); pr.c4:SetPoint("LEFT", pr, "LEFT", x4, 0); pr.c4:SetWidth(w4); pr.c4:Show()
				pr.c5:ClearAllPoints(); pr.c5:SetPoint("LEFT", pr, "LEFT", x5, 0); pr.c5:SetWidth(w5)
			end
		end
	end

	if isScanning and #listings == 0 then
		AHSellTab.sellPricesEmptyFs:SetText(palHex("hexInfo", "56d4e8") .. "Scanning live AH...|r")
		AHSellTab.sellPricesEmptyFs:Show()
	elseif #listings == 0 then
		local emptyMsg = (scanned or listTarget) and "No active AH listings" or "Select an item to view Current Prices"
		AHSellTab.sellPricesEmptyFs:SetText(palHex("hexMuted", "98989d") .. emptyMsg .. "|r")
		AHSellTab.sellPricesEmptyFs:Show()
	else
		AHSellTab.sellPricesEmptyFs:Hide()
	end

	local mutedDash = palHex("hexMuted", "98989d") .. "-|r"
	local posHex = palHex("hexPositive", "30d158")
	local txtHex = palHex("hexText", "ffffff")
	local fmtLarge = _G.FormatLargeNumber

	for i = 1, SELL_PRICES_VISIBLE_ROWS do
		local pr = AHSellTab.sellPricesRows[i]
		local rec = (i <= visPRows) and listings[pricesScrollOffset + i] or nil
		if rec then
			pr._listing = rec
			if rec.containsOwnerItem then
				pr.bg:SetColorTexture(isLight and 0.00 or 0.06, isLight and 0.48 or 0.24, isLight and 0.18 or 0.14, isLight and 0.12 or 0.55)
			elseif (i % 2) == 0 then
				pr.bg:SetColorTexture(isLight and 0.00 or 1.00, isLight and 0.00 or 1.00, isLight and 0.00 or 1.00, isLight and 0.03 or 0.04)
			else
				pr.bg:SetColorTexture(0, 0, 0, 0)
			end

			pr.c1:SetText((rec.price and rec.price > 0) and formatSellCoinMoney(rec.price) or mutedDash)
			local qtyNum = tonumber(rec.quantity) or 1
			local qTxt = fmtLarge and fmtLarge(qtyNum) or tostring(qtyNum)
			pr.c3:SetText(txtHex .. qTxt .. "|r")

			if not listIsComm then
				pr.c2:SetText((rec.bidPrice and rec.bidPrice > 0) and formatSellCoinMoney(rec.bidPrice) or mutedDash)
				local ilvlTxt = (rec.itemLevel and rec.itemLevel > 0) and tostring(rec.itemLevel) or "-"
				pr.c4:SetText(txtHex .. ilvlTxt .. "|r")
			end

			if rec.containsOwnerItem then
				local ownCnt = tonumber(rec.numOwnerItems) or 0
				if ownCnt > 1 and ownCnt < qtyNum then
					pr.c5:SetText(posHex .. string.format("Yes (%d)|r", ownCnt))
				else
					pr.c5:SetText(posHex .. "Yes|r")
				end
			else
				pr.c5:SetText(mutedDash)
			end
			pr:Show()
		else
			pr._listing = nil
			if pr.hoverTex then pr.hoverTex:Hide() end
			pr:Hide()
		end
	end
end

renderQueueList = function(of, sl, items, isLight)
	local qListArea = AHSellTab.sellQueueListArea
	if not qListArea then return end

	local goldBorder = { 0.83, 0.64, 0.24 }
	local btnInactFill = isLight and { 0.90, 0.92, 0.96, 1.0 } or { 0.05, 0.13, 0.09, 0.92 }
	local btnInactText = isLight and { 0.12, 0.15, 0.19, 1.0 } or { 0.94, 0.92, 0.88, 1.0 }

	local remTot = 0
	for _, it in ipairs(items) do remTot = remTot + (tonumber(it.remaining) or 0) end
	AHSellTab.sellQueueHdrFs:SetText(string.format("Sell Queue: %d items (%d remaining)", #items, remTot))
	AHSellTab.sellQueueClearBtn:SetEnabled(#items > 0)
	AHSellTab.sellQueueClearBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

	local visQRows = getVisibleRowCount(qListArea, SELL_QUEUE_ROW_H, SELL_QUEUE_VISIBLE_ROWS, 3)
	local maxQOff = math.max(0, #items - visQRows)
	if queueScrollOffset > maxQOff then queueScrollOffset = maxQOff end
	if queueScrollOffset < 0 then queueScrollOffset = 0 end
	local hasQScroll = AHSellTab.sellQueueScroll:Update(queueScrollOffset, visQRows, #items, isLight)
	local qRightPad = hasQScroll and -9 or 0

	local qLayoutKey = (hasQScroll and "1:" or "0:") .. tostring(visQRows)
	if qLayoutKey ~= lastQueueLayoutKey then
		lastQueueLayoutKey = qLayoutKey
		for i = 1, SELL_QUEUE_VISIBLE_ROWS do
			local qr = AHSellTab.sellQueueRows[i]
			qr:ClearAllPoints()
			qr:SetPoint("TOPLEFT", qListArea, "TOPLEFT", 0, -((i - 1) * SELL_QUEUE_ROW_H))
			qr:SetPoint("TOPRIGHT", qListArea, "TOPRIGHT", qRightPad, -((i - 1) * SELL_QUEUE_ROW_H))
		end
	end

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
			qr.priceFs:SetText(up > 0 and formatSellCoinMoney(up) or (palHex("hexMuted", "98989d") .. "-|r"))
			qr.removeBtn:PaintStyle({ 0.38, 0.08, 0.10, 0.92 }, goldBorder, { 1, 0.92, 0.92, 1 })
			qr:Show()
		else
			qr._itemIndex = nil
			if qr.hoverTex then qr.hoverTex:Hide() end
			qr:Hide()
		end
	end
end

renderHistoryList = function(reuseCache, of, sl, cur, isLight)
	local hListArea = AHSellTab.sellHistoryListArea
	if not hListArea then return end

	local target = cur or sl.lastItemInfo
	local targetID = target and tonumber(target.itemID) or 0
	local epoch = (ns.GetPriceDataRevision and tonumber(ns.GetPriceDataRevision())) or tonumber(ns.priceCacheEpoch) or 0
	local hKey = tostring(targetID) .. ":" .. tostring(epoch)

	local rows, t7, t24
	if reuseCache and historyCacheKey == hKey then
		rows, t7, t24 = historyCacheRows, historyCacheT7, historyCacheT24
	else
		rows, t7, t24 = getHistoryRowsData(target)
		historyCacheKey = hKey
		historyCacheRows = rows
		historyCacheT7 = t7
		historyCacheT24 = t24
	end

	local nameTxt = target and tostring(target.name or "Selected Item") or "Selected Item"
	local curTxt = (t7 and t7.currentPrice and t7.currentPrice > 0) and formatSellCoinMoney(t7.currentPrice)
		or ((t24 and t24.currentPrice and t24.currentPrice > 0) and formatSellCoinMoney(t24.currentPrice) or "N/A")
	local trendStr = "Trend: insufficient"
	if t7 and t7.trendPct ~= nil then
		local arrow = (t7.trendPct > 0 and "+") or ""
		trendStr = string.format("7d Trend: %s%.1f%% (%s)", arrow, t7.trendPct, tostring(t7.direction or ""))
	elseif t24 and t24.trendPct ~= nil then
		local arrow = (t24.trendPct > 0 and "+") or ""
		trendStr = string.format("24h Trend: %s%.1f%%", arrow, t24.trendPct)
	end
	AHSellTab.sellHistorySummaryFs:SetText(string.format("%s  |  Current: %s  |  %s", nameTxt, curTxt, trendStr))

	local visHRows = getVisibleRowCount(hListArea, SELL_HISTORY_ROW_H, SELL_HISTORY_VISIBLE_ROWS, 3)
	local maxHOff = math.max(0, #rows - visHRows)
	if historyScrollOffset > maxHOff then historyScrollOffset = maxHOff end
	if historyScrollOffset < 0 then historyScrollOffset = 0 end
	local hasHScroll = AHSellTab.sellHistoryScroll:Update(historyScrollOffset, visHRows, #rows, isLight)
	local hRightPad = hasHScroll and -9 or 0

	local hLayoutKey = (hasHScroll and "1:" or "0:") .. tostring(visHRows)
	if hLayoutKey ~= lastHistoryLayoutKey then
		lastHistoryLayoutKey = hLayoutKey
		for i = 1, SELL_HISTORY_VISIBLE_ROWS do
			local hr = AHSellTab.sellHistoryRows[i]
			hr:ClearAllPoints()
			hr:SetPoint("TOPLEFT", hListArea, "TOPLEFT", 0, -((i - 1) * SELL_HISTORY_ROW_H))
			hr:SetPoint("TOPRIGHT", hListArea, "TOPRIGHT", hRightPad, -((i - 1) * SELL_HISTORY_ROW_H))
		end
	end

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
			hr.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.0)
			hr.c1:SetText(tostring(rec.when or ""))
			hr.c2:SetText(rec.price > 0 and formatSellCoinMoney(rec.price) or "-")
			hr.c3:SetText(string.format("Qty: %d", tonumber(rec.qty) or 0))
			hr.c4:SetText(rec.vel and string.format("%.1f / day", rec.vel) or "-")
			hr.c5:SetText(palHex("hexMuted", "98989d") .. tostring(rec.source or "") .. "|r")
			hr:Show()
		else
			hr:Hide()
		end
	end
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
						bagCacheDirty = true
						local of = getOrderFlow()
						if of then
							triggerOpenSellAutoScan(of)
						end
						AHSellTab.Render()
						AHSellTab.SyncSpaceBinding()
					end)
					tabFrame:HookScript("OnHide", function()
						lastAutoScanItemKey = nil
						lastAutoScanAt = 0
						hideBelowVendorPopup()
						AHSellTab.SyncSpaceBinding(true)
					end)
				end
			end
			if ns.app and ns.app.ensureAuctionHouseMMTab then ns.app.ensureAuctionHouseMMTab() end
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
	if ns.app and ns.app.ensureAuctionHouseMMTab then ns.app.ensureAuctionHouseMMTab() end
	return true
end

function AHSellTab.SelectTab()
	AHSellTab.EnsureAttached()
	bagCacheDirty = true
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
		triggerOpenSellAutoScan(of)
	end
	AHSellTab.Render()
	AHSellTab.SyncSpaceBinding()
	return true
end

function AHSellTab.HideTab()
	lastAutoScanItemKey = nil
	lastAutoScanAt = 0
	hideBelowVendorPopup()
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

	local goldBorder = { 0.83, 0.64, 0.24 }
	local subtleBorder = isLight and { 0.00, 0.00, 0.00, 0.14 } or { 0.83, 0.64, 0.24, 0.35 }
	local btnInactFill = isLight and { 0.90, 0.92, 0.96, 1.0 } or { 0.05, 0.13, 0.09, 0.92 }
	local btnInactText = isLight and { 0.12, 0.15, 0.19, 1.0 } or { 0.94, 0.92, 0.88, 1.0 }
	local btnActFill = isLight and { 0.00, 0.48, 0.22, 1.0 } or { 0.10, 0.40, 0.24, 0.98 }
	local btnActStroke = isLight and { 0.00, 0.36, 0.16, 1.0 } or { 0.24, 0.95, 0.56, 0.95 }
	local btnActText = { 1.0, 1.0, 1.0, 1.0 }

	paintStaticChrome(isLight)
	layoutTopBar()

	-- Auto-hide below-vendor popup if warning cleared or active item changed
	if popupShownKey ~= nil then
		local wc = sl.warningConfirm
		local stillValid = (wc ~= nil and wc.reason == "below_vendor" and wc.itemIndex == sl.activeIndex and inAH)
		if not stillValid then
			hideBelowVendorPopup()
		end
	end

	-- Always-Shown Zero-Shift Notice Banner (never hides or re-anchors bottom panes)
	local hasNotice = (type(st.notice) == "string" and st.notice ~= "")
	if hasNotice then
		local nk = st.noticeKind or "info"
		local nFill = isLight
			and (nk == "danger" and { 0.98, 0.90, 0.90, 1.0 } or (nk == "positive" and { 0.88, 0.96, 0.90, 1.0 } or { 0.90, 0.94, 0.98, 1.0 }))
			or (nk == "danger" and { 0.14, 0.03, 0.04, 0.95 } or (nk == "positive" and { 0.016, 0.028, 0.024, 0.94 } or { 0.016, 0.024, 0.036, 0.94 }))
		local nStroke = isLight
			and ((nk == "danger" and { 0.85, 0.24, 0.24, 0.85 }) or (nk == "positive" and { 0.12, 0.56, 0.28, 0.75 }) or { 0.10, 0.46, 0.82, 0.75 })
			or ((nk == "danger" and { 0.94, 0.34, 0.34, 0.62 }) or (nk == "positive" and { 0.22, 0.80, 0.46, 0.48 }) or { 0.28, 0.74, 0.96, 0.52 })
		local nHex = (nk == "danger" and palHex("hexDanger", "ff453a")) or (nk == "positive" and palHex("hexPositive", "30d158")) or palHex("hexInfo", "56d4e8")
		AHSellTab.noticeBar.plate:SetFill(nFill[1], nFill[2], nFill[3], nFill[4])
		AHSellTab.noticeBar.plate:SetStroke(nStroke[1], nStroke[2], nStroke[3], nStroke[4])
		AHSellTab.noticeFs:SetText(nHex .. st.notice .. "|r")
	else
		local idleFill = isLight and { 0.93, 0.94, 0.96, 0.85 } or { 0.016, 0.022, 0.032, 0.90 }
		local idleStroke = isLight and { 0.00, 0.00, 0.00, 0.12 } or { 0.83, 0.64, 0.24, 0.26 }
		AHSellTab.noticeBar.plate:SetFill(idleFill[1], idleFill[2], idleFill[3], idleFill[4])
		AHSellTab.noticeBar.plate:SetStroke(idleStroke[1], idleStroke[2], idleStroke[3], idleStroke[4])
		AHSellTab.noticeFs:SetText(palHex("hexMuted", "98989d") .. "Waiting for first action...|r")
	end
	AHSellTab.noticeBar:Show()

	-- Compute active item commodity flag & post qty/limit ONCE per Render
	local isCommItem = false
	local postQty, postLimit = 0, 0
	if cur and of then
		if cur.isCommodity ~= nil then
			isCommItem = (cur.isCommodity == true)
		elseif of.IsSellItemCommodity then
			isCommItem = (of.IsSellItemCommodity(cur) == true)
		end
		if of.GetSellPostQty then
			postQty, postLimit = of.GetSellPostQty(cur)
			postQty = tonumber(postQty) or 0
			postLimit = tonumber(postLimit) or 0
		end
	end

	-- Active Item preview + Drop Slot
	local titleStr, subStr = formatSellTitle(of, cur)
	AHSellTab.activeFs:SetText(titleStr)
	AHSellTab.spotSubFs:SetText(palHex("hexMuted", "98989d") .. subStr .. "|r")
	if cur and cur.itemID then
		AHSellTab.iconDropBtn.tex:SetTexture(resolveIconTex(cur.itemID, cur.spellID))
		local r, g, b = getQualityRGB(cur.quality)
		AHSellTab.iconDropBtn.plate:SetStroke(r, g, b, 0.95)
		local qDisp = (postQty > 0) and postQty or (cur.remaining or 0)
		AHSellTab.iconDropBtn.countFs:SetText((qDisp and qDisp > 1) and tostring(qDisp) or "")
		if AHSellTab.spotMetaFs then
			local kindTag = isCommItem and "Commodity" or "Equipment"
			local scanTag = (sl.pendingSearch and sl.pendingSearch.itemID == cur.itemID)
				and (palHex("hexInfo", "56d4e8") .. "Scanning AH...|r")
				or (palHex("hexPositive", "30d158") .. "AH Ready|r")
			AHSellTab.spotMetaFs:SetText(palHex("hexSecondary", "c8d0ca") .. kindTag .. "  |  |r" .. scanTag)
		end
	else
		AHSellTab.iconDropBtn.tex:SetTexture(ns.QUESTION_ICON or "Interface\\Icons\\INV_Misc_QuestionMark")
		AHSellTab.iconDropBtn.plate:SetStroke(goldBorder[1], goldBorder[2], goldBorder[3], 0.65)
		AHSellTab.iconDropBtn.countFs:SetText("")
		if AHSellTab.spotMetaFs then
			AHSellTab.spotMetaFs:SetText(palHex("hexMuted", "98989d") .. "Waiting for item|r")
		end
	end

	-- Keep AH pricing form & Zone 3 controls always shown cleanly
	AHSellTab.sellForm:Show()
	AHSellTab.postBtn:Show()
	AHSellTab.sellRefreshBtn:Show()
	AHSellTab.sellDurLbl:Show()
	AHSellTab.sellRuleLbl:Show()

	local curDur = sl.duration or 2
	for dIdx = 1, 3 do
		local db = AHSellTab.sellDurBtns[dIdx]
		local activeD = (dIdx == curDur)
		db:Show()
		db:SetEnabled(cur ~= nil)
		db:PaintStyle(activeD and btnActFill or btnInactFill,
			activeD and btnActStroke or subtleBorder,
			activeD and btnActText or btnInactText)
	end

	local curRule = sl.undercutMode or "match"
	for _, ub in ipairs(AHSellTab.sellUcBtns or {}) do
		local activeR = (ub._ucKey == curRule)
		ub:Show()
		ub:SetEnabled(cur ~= nil)
		ub:PaintStyle(activeR and btnActFill or btnInactFill,
			activeR and btnActStroke or subtleBorder,
			activeR and btnActText or btnInactText)
	end

	local buyoutP, priceSrc, bidP = 0, "none", 0
	if cur and of and of.ComputeSellUnitPrice then
		buyoutP, priceSrc, bidP = of.ComputeSellUnitPrice(cur)
	end
	local effUnit = (buyoutP > 0) and buyoutP or bidP

	AHSellTab.sellPriceLbl:SetText(palHex("hexSecondary", "ebebf5") .. (isCommItem and "Unit Price|r" or "Buyout Price|r"))

	AHSellTab.sellQtyMinus:SetEnabled(cur ~= nil and postLimit > 0 and postQty > 1)
	AHSellTab.sellQtyMinus:PaintStyle(btnInactFill, goldBorder, btnInactText)
	AHSellTab.sellQtyPlus:SetEnabled(cur ~= nil and postLimit > 0 and postQty < postLimit)
	AHSellTab.sellQtyPlus:PaintStyle(btnInactFill, goldBorder, btnInactText)
	AHSellTab.sellMaxBtn:SetEnabled(cur ~= nil and postLimit > 0 and postQty ~= postLimit)
	AHSellTab.sellMaxBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)
	AHSellTab.sellMaxInfoFs:SetText(palHex("hexMuted", "98989d") .. string.format("(max %d)|r", postLimit))

	local refKind = cur and cur.marketRefSource or nil
	if not refKind and cur and cur.itemID and ns.GetCanonicalItemPrice then
		local can = ns.GetCanonicalItemPrice(cur.itemID)
		refKind = can and can.kind or nil
	end
	local mktDbTag
	if refKind == "live" then
		mktDbTag = { txt = palHex("hexInfo", "56d4e8") .. "Live AH|r", fill = { 0.06, 0.18, 0.24, 0.90 }, stroke = { 0.34, 0.83, 0.91, 0.72 } }
	elseif refKind == "tsm" then
		mktDbTag = { txt = palHex("hexGold", "f7d57c") .. "TSM|r", fill = { 0.22, 0.17, 0.06, 0.88 }, stroke = { 0.83, 0.64, 0.24, 0.68 } }
	else
		mktDbTag = { txt = palHex("hexMuted", "b8c0c8") .. "Snap|r", fill = { 0.10, 0.14, 0.16, 0.85 }, stroke = { 0.55, 0.62, 0.68, 0.55 } }
	end
	local srcTagMap = {
		custom = { txt = palHex("hexGold", "f7d57c") .. "Custom|r", fill = { 0.24, 0.18, 0.05, 0.90 }, stroke = { 0.88, 0.70, 0.26, 0.75 } },
		live_own = { txt = palHex("hexPositive", "30d158") .. "Own Top|r", fill = { 0.05, 0.22, 0.12, 0.90 }, stroke = { 0.24, 0.90, 0.50, 0.72 } },
		live_ah = { txt = palHex("hexInfo", "56d4e8") .. "Live AH|r", fill = { 0.06, 0.18, 0.24, 0.90 }, stroke = { 0.34, 0.83, 0.91, 0.72 } },
		market_db = mktDbTag,
		vendor_fallback = { txt = palHex("hexMuted", "b8c0c8") .. "Est|r", fill = { 0.10, 0.14, 0.16, 0.85 }, stroke = { 0.55, 0.62, 0.68, 0.55 } },
	}
	local srcInfo = srcTagMap[priceSrc or "none"]
	if srcInfo then
		AHSellTab.sellPriceSrcFs:SetText(srcInfo.txt)
		if AHSellTab.sellPriceSrcPill then
			AHSellTab.sellPriceSrcPill.plate:SetFill(srcInfo.fill[1], srcInfo.fill[2], srcInfo.fill[3], srcInfo.fill[4])
			AHSellTab.sellPriceSrcPill.plate:SetStroke(srcInfo.stroke[1], srcInfo.stroke[2], srcInfo.stroke[3], srcInfo.stroke[4])
			AHSellTab.sellPriceSrcPill:Show()
		end
	else
		AHSellTab.sellPriceSrcFs:SetText("")
		if AHSellTab.sellPriceSrcPill then AHSellTab.sellPriceSrcPill:Hide() end
	end

	if AHSellTab.sellUnitRow then
		AHSellTab.sellUnitRow:Show()
	end
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

	-- Per-item Vendor Value alert bar & Complete 5-Row Cost/Payout Summary Card (Zone 3)
	updateVendorValueReadout(of, cur, effUnit, isLight)
	updateSellSummaryReadouts(of, cur, postQty, effUnit, curDur, isLight)

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

	-- Action row: Post | Refresh | context-only Cancel
	local pa = (of and of.GetSellPrimaryAction) and of.GetSellPrimaryAction() or { label = "Post", enabled = false }
	local postCol = (pa.action == "confirm" or pa.action == "confirm_warning")
		and { 0.42, 0.28, 0.06, 0.96 }
		or { 0.48, 0.09, 0.12, 0.96 }
	AHSellTab.postBtn:SetText(pa.label or "Post")
	AHSellTab.postBtn:SetEnabled(pa.enabled == true)
	AHSellTab.postBtn:PaintStyle(postCol, goldBorder, { 1.0, 0.96, 0.88, 1.0 })

	AHSellTab.sellRefreshBtn:SetEnabled(inAH and (cur ~= nil or sl.lastItemInfo ~= nil) and sl.pendingPost == nil)
	AHSellTab.sellRefreshBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)

	local showCancel = (sl.warningConfirm ~= nil or sl.pendingPost ~= nil)
	if showCancel then
		AHSellTab.cancelBtn:SetEnabled(true)
		AHSellTab.cancelBtn:PaintStyle(btnInactFill, goldBorder, btnInactText)
		AHSellTab.cancelBtn:Show()
	else
		AHSellTab.cancelBtn:Hide()
	end

	-- Categorized Bag Grid (only rescans bags when dirty or queue signature changed)
	local queueSig = computeBagQueueSig(items)
	local needBagRescan = bagCacheDirty or (app.bagsDirty == true) or (queueSig ~= lastBagQueueSig)
	if needBagRescan then
		lastBagQueueSig = queueSig
	end
	renderBagGrid(needBagRescan, isLight)

	-- Bottom-Right Tabbed View (Current Prices / Sell Queue / Price History)
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
		renderPricesList(of, sl, cur, isLight)
	elseif activeSubTab == "queue" then
		AHSellTab.sellQueueView:Show()
		renderQueueList(of, sl, items, isLight)
	elseif activeSubTab == "history" then
		AHSellTab.sellHistoryView:Show()
		renderHistoryList(false, of, sl, cur, isLight)
	end
end
