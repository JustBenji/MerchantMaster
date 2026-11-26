-- MerchantMaster: Standalone Bag Disenchant Helper Window
-- Lets the player pick disenchantable bag items, toggle Arcane Salvager (+20%),
-- and continuously click one SecureActionButtonTemplate DISENCHANT button.

local ADDON, ns = ...

local DisenchantHelper = {}
ns.DisenchantHelper = DisenchantHelper

local DISENCHANT_SPELL_ID = 13262
local AS_MULT = 1 + (ns.DE_ARCANE_SALVAGER_BONUS or 0.20)
local QUALITY_RGB = {
	[2] = { 0.12, 1.00, 0.00 },
	[3] = { 0.00, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 },
}

local state = {
	frame = nil,
	items = {},
	selected = {},
	skipped = {},
	activeIndex = nil,
	scrollOffset = 0,
	rows = {},
	outcomeLines = {},
	arcaneSalvager = false,
	applyAHCut = true,
	castingNotice = nil,
}

local function pal()
	local T = ns.Theme
	if T and T.GetActivePalette then
		local p = T.GetActivePalette()
		if type(p) == "table" then return p end
	end
	return (T and T.PALETTE) or {}
end

local function moneyTxt(copper)
	if type(copper) ~= "number" or copper ~= copper then return "-" end
	local rounded = math.floor(copper + 0.5)
	local T = ns.Theme
	if T and T.FormatMoneyText then
		return T.FormatMoneyText(rounded, "cost")
	end
	if ns.FormatMoneyCompact then
		return ns.FormatMoneyCompact(rounded)
	end
	return tostring(rounded) .. "c"
end

local function extractFullItemName(link, fallbackName, itemID)
	if type(link) == "string" then
		local bracketName = link:match("%[(.-)%]")
		if type(bracketName) == "string" and bracketName ~= "" then
			return bracketName
		end
	end
	if type(fallbackName) == "string" and fallbackName ~= "" then
		return fallbackName
	end
	return "Item #" .. tostring(itemID or 0)
end

local function makeSlotKey(bag, slot, itemID)
	return tostring(bag) .. ":" .. tostring(slot) .. ":" .. tostring(itemID)
end

local function getBagNumSlots(bag)
	if _G.C_Container and _G.C_Container.GetContainerNumSlots then
		return tonumber(_G.C_Container.GetContainerNumSlots(bag)) or 0
	elseif _G.GetContainerNumSlots then
		return tonumber(_G.GetContainerNumSlots(bag)) or 0
	end
	return 0
end

local function getBagSlotInfo(bag, slot)
	if _G.C_Container and _G.C_Container.GetContainerItemInfo then
		local info = _G.C_Container.GetContainerItemInfo(bag, slot)
		if type(info) == "table" and info.itemID then
			local link = info.hyperlink
			if not link and _G.C_Container.GetContainerItemLink then
				link = _G.C_Container.GetContainerItemLink(bag, slot)
			end
			return tonumber(info.itemID), link, info.iconFileID, tonumber(info.stackCount) or 1, info.isBound == true
		end
		return nil
	elseif _G.GetContainerItemInfo then
		local icon, count, _, quality, _, _, link = _G.GetContainerItemInfo(bag, slot)
		if link then
			local id = tonumber(link:match("item:(%d+)"))
			return id, link, icon, tonumber(count) or 1, false, quality
		end
	end
	return nil
end

local function isInCombat()
	return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end

local function syncSettingsFromDB()
	local db = _G.MerchantMasterDB
	if type(db) == "table" then
		state.arcaneSalvager = (db.disenchantHelperAS == true)
		state.applyAHCut = (db.applyAHCut ~= false)
	else
		state.arcaneSalvager = false
		state.applyAHCut = true
	end
end

local function effectiveEV(item)
	if not item then return nil end
	if state.arcaneSalvager then
		return item.asNetCopper or (item.netCopper and math.floor(item.netCopper * AS_MULT + 0.5)) or nil
	end
	return item.netCopper
end

local function countSelected()
	local cnt, totalCopper, unpriced = 0, 0, 0
	local firstIdx = nil
	for i, it in ipairs(state.items) do
		if state.selected[it.key] then
			cnt = cnt + 1
			if not firstIdx then firstIdx = i end
			local ev = effectiveEV(it)
			if ev and ev > 0 then
				totalCopper = totalCopper + ev
			else
				unpriced = unpriced + 1
			end
		end
	end
	return cnt, totalCopper, unpriced, firstIdx
end

local updateUI

local function scrollListBy(delta)
	local d = tonumber(delta) or 0
	if d == 0 then return false end
	local maxOff = math.max(0, #state.items - 7)
	local step = (d > 0) and -1 or 1
	local nextOff = math.max(0, math.min(maxOff, (state.scrollOffset or 0) + step))
	if nextOff ~= state.scrollOffset then
		state.scrollOffset = nextOff
		if updateUI then updateUI() end
		return true
	end
	return false
end

local function scrollListToRatio(ratio)
	local maxOff = math.max(0, #state.items - 7)
	local r = math.max(0, math.min(1, tonumber(ratio) or 0))
	local nextOff = math.floor(r * maxOff + 0.5)
	if nextOff ~= state.scrollOffset then
		state.scrollOffset = nextOff
		if updateUI then updateUI() end
		return true
	end
	return false
end

function DisenchantHelper.ScanBags()
	syncSettingsFromDB()
	local items = {}
	local validKeys = {}
	local maxBags = (_G.NUM_BAG_SLOTS ~= nil) and tonumber(_G.NUM_BAG_SLOTS) or 4
	local getInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo

	for bag = 0, maxBags do
		local slots = getBagNumSlots(bag)
		for slot = 1, slots do
			local itemID, link, slotIcon, stackCount, isBound = getBagSlotInfo(bag, slot)
			if itemID and itemID > 0 and ns.IsItemDisenchantable then
				local ok, err, meta = ns.IsItemDisenchantable(itemID, link)
				if ok and meta then
					local bd = ns.GetItemDEBreakdown and ns.GetItemDEBreakdown(itemID, link, state.applyAHCut) or nil
					if bd and bd.outcomes and #bd.outcomes > 0 then
						local icon = slotIcon
						if not icon and getInfo then
							icon = select(10, getInfo(link or itemID))
						end
						local key = makeSlotKey(bag, slot, itemID)
						validKeys[key] = true
						items[#items + 1] = {
							key = key,
							bag = bag,
							slot = slot,
							itemID = itemID,
							link = link or ("item:" .. tostring(itemID)),
							name = extractFullItemName(link, meta.name, itemID),
							quality = meta.quality or 2,
							qualityName = meta.qualityName or "Uncommon",
							ilvl = meta.ilvl or 0,
							className = meta.className or "Armor",
							icon = icon or 134400,
							stackCount = stackCount or 1,
							isBound = isBound == true,
							netCopper = bd.netCopper,
							asNetCopper = bd.asNetCopper,
							primarySummary = bd.primarySummary or "",
							outcomes = bd.outcomes,
							missingPriceCount = bd.missingPriceCount or 0,
						}
					end
				end
			end
		end
	end

	-- Prune selections and skipped markers for items no longer in that slot
	for k in pairs(state.selected) do
		if not validKeys[k] then state.selected[k] = nil end
	end
	for k in pairs(state.skipped) do
		if not validKeys[k] then state.skipped[k] = nil end
	end

	table.sort(items, function(a, b)
		if (a.quality or 0) ~= (b.quality or 0) then
			return (a.quality or 0) < (b.quality or 0)
		end
		if (a.ilvl or 0) ~= (b.ilvl or 0) then
			return (a.ilvl or 0) < (b.ilvl or 0)
		end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)

	state.items = items
	local _, _, _, firstIdx = countSelected()
	state.activeIndex = firstIdx

	local maxOff = math.max(0, #items - 7)
	if state.scrollOffset > maxOff then state.scrollOffset = maxOff end
	if state.frame and updateUI then
		updateUI()
	end
	return #items
end

function DisenchantHelper.SelectAll()
	for _, it in ipairs(state.items) do
		state.selected[it.key] = true
		state.skipped[it.key] = nil
	end
	local _, _, _, firstIdx = countSelected()
	state.activeIndex = firstIdx
	if updateUI then updateUI() end
end

function DisenchantHelper.SelectNone()
	for k in pairs(state.selected) do state.selected[k] = nil end
	state.activeIndex = nil
	if updateUI then updateUI() end
end

function DisenchantHelper.SelectByQuality(quality)
	for _, it in ipairs(state.items) do
		if it.quality == quality then
			state.selected[it.key] = true
			state.skipped[it.key] = nil
		else
			state.selected[it.key] = nil
		end
	end
	local _, _, _, firstIdx = countSelected()
	state.activeIndex = firstIdx
	if updateUI then updateUI() end
end

function DisenchantHelper.ToggleKey(key)
	if not key then return false end
	if state.selected[key] then
		state.selected[key] = nil
	else
		state.selected[key] = true
		state.skipped[key] = nil
	end
	local _, _, _, firstIdx = countSelected()
	state.activeIndex = firstIdx
	if updateUI then updateUI() end
	return state.selected[key] == true
end

function DisenchantHelper.SkipCurrent()
	local cur = state.activeIndex and state.items[state.activeIndex] or nil
	if not cur then return false end
	state.selected[cur.key] = nil
	state.skipped[cur.key] = true
	local _, _, _, firstIdx = countSelected()
	state.activeIndex = firstIdx
	if updateUI then updateUI() end
	return true
end

function DisenchantHelper.SetArcaneSalvager(on)
	local val = (on == true)
	state.arcaneSalvager = val
	if _G.MerchantMasterDB then
		_G.MerchantMasterDB.disenchantHelperAS = val
	end
	if updateUI then updateUI() end
end

local function getDisenchantSpellName()
	local name = (_G.C_Spell and _G.C_Spell.GetSpellName and _G.C_Spell.GetSpellName(DISENCHANT_SPELL_ID))
		or (_G.GetSpellInfo and _G.GetSpellInfo(DISENCHANT_SPELL_ID))
	if type(name) == "string" and name ~= "" then
		return name
	end
	return "Disenchant"
end

local function buildMacroForItem(it)
	if not it or it.bag == nil or it.slot == nil then return "" end
	return string.format("/cast %s;\n/use %d %d", getDisenchantSpellName(), it.bag, it.slot)
end

local function syncButtonClickEdge(btn)
	if not btn or not btn.RegisterForClicks or isInCombat() then return end
	local useKeyDown = (_G.GetCVarBool and _G.GetCVarBool("ActionButtonUseKeyDown")) and true or false
	btn:RegisterForClicks(useKeyDown and "LeftButtonDown" or "LeftButtonUp")
end

local function applyButtonMacro(btn, macro)
	if not btn or not btn.SetAttribute or isInCombat() then return end
	local text = (type(macro) == "string") and macro or ""
	btn:SetAttribute("type", "macro")
	btn:SetAttribute("*type1", "macro")
	btn:SetAttribute("macrotext", text)
	btn:SetAttribute("*macrotext1", text)
end

local function ensureBuilt()
	if state.frame then return state.frame end
	local T = ns.Theme
	if not (T and T.CreateFloatingWindow) then return nil end

	local f = T.CreateFloatingWindow("MerchantMasterDisenchantHelper", "Disenchant Helper", 496, 584, {
		warcraftChrome = true,
		compactChrome = true,
		customTitleUpper = true,
		centerY = 0,
	})
	state.frame = f
	local body = f.body or f

	-- Filter / Selection Bar
	local bar = CreateFrame("Frame", nil, body)
	bar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
	bar:SetHeight(32)
	f.filterBar = bar

	local btnAll = T.CreatePlateButton(bar, "All", 46, 24, { variant = "secondary", pill = true, fontSize = 11 })
	btnAll:SetPoint("LEFT", bar, "LEFT", 0, 0)
	btnAll:SetScript("OnClick", function() DisenchantHelper.SelectAll() end)

	local btnGreen = T.CreatePlateButton(bar, "Green", 58, 24, { variant = "secondary", pill = true, fontSize = 11 })
	btnGreen:SetPoint("LEFT", btnAll, "RIGHT", 6, 0)
	btnGreen:SetScript("OnClick", function() DisenchantHelper.SelectByQuality(2) end)

	local btnBlue = T.CreatePlateButton(bar, "Blue", 50, 24, { variant = "secondary", pill = true, fontSize = 11 })
	btnBlue:SetPoint("LEFT", btnGreen, "RIGHT", 6, 0)
	btnBlue:SetScript("OnClick", function() DisenchantHelper.SelectByQuality(3) end)

	local btnNone = T.CreatePlateButton(bar, "None", 52, 24, { variant = "secondary", pill = true, fontSize = 11 })
	btnNone:SetPoint("LEFT", btnBlue, "RIGHT", 6, 0)
	btnNone:SetScript("OnClick", function() DisenchantHelper.SelectNone() end)

	local btnAS = T.CreatePlateButton(bar, "AS +20%", 76, 24, { variant = "secondary", pill = true, fontSize = 11 })
	btnAS:SetPoint("LEFT", btnNone, "RIGHT", 6, 0)
	btnAS:SetScript("OnClick", function()
		DisenchantHelper.SetArcaneSalvager(not state.arcaneSalvager)
	end)
	f.asBtn = btnAS

	local btnRefresh = T.CreatePlateButton(bar, "Scan", 54, 24, { variant = "secondary", pill = true, fontSize = 11 })
	btnRefresh:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	btnRefresh:SetScript("OnClick", function()
		DisenchantHelper.ScanBags()
	end)

	-- Summary strip
	local summaryFs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summaryFs:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -4)
	summaryFs:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -2, -4)
	summaryFs:SetHeight(16)
	summaryFs:SetJustifyH("LEFT")
	summaryFs:SetWordWrap(false)
	T.ApplyFont(summaryFs, 11, "regular")
	f.summaryFs = summaryFs

	-- Scrollable Bag Checklist Card (7 visible rows x 30px = 210px + 12px padding)
	local listCard = CreateFrame("Frame", nil, body)
	listCard:SetPoint("TOPLEFT", summaryFs, "BOTTOMLEFT", -2, -6)
	listCard:SetPoint("TOPRIGHT", summaryFs, "BOTTOMRIGHT", 2, -6)
	listCard:SetHeight(222)
	listCard.plate = T.NineApple(listCard, "glass_r10", "cardBg", "border")
	if listCard.EnableMouseWheel then listCard:EnableMouseWheel(true) end
	listCard:SetScript("OnMouseWheel", function(_, delta)
		scrollListBy(delta)
	end)
	f.listCard = listCard

	local scrollTrack = CreateFrame("Frame", nil, listCard)
	scrollTrack:SetWidth(8)
	scrollTrack:SetPoint("TOPRIGHT", listCard, "TOPRIGHT", -6, -8)
	scrollTrack:SetPoint("BOTTOMRIGHT", listCard, "BOTTOMRIGHT", -6, 8)
	scrollTrack.bg = scrollTrack:CreateTexture(nil, "BACKGROUND")
	scrollTrack.bg:SetAllPoints(scrollTrack)
	scrollTrack.bg:SetColorTexture(1, 1, 1, 0.08)
	if scrollTrack.EnableMouse then scrollTrack:EnableMouse(true) end
	scrollTrack:SetScript("OnMouseDown", function(self)
		if #state.items <= 7 then return end
		local top = self.GetTop and self:GetTop()
		local h = self.GetHeight and self:GetHeight()
		local _, cy = _G.GetCursorPosition and _G.GetCursorPosition()
		local sc = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
		if type(top) == "number" and type(h) == "number" and h > 0 and type(cy) == "number" then
			local ratio = (top - (cy / sc)) / h
			scrollListToRatio(ratio)
		end
	end)
	scrollTrack:Hide()
	f.scrollTrack = scrollTrack

	local scrollThumb = CreateFrame("Button", nil, scrollTrack)
	scrollThumb:SetWidth(8)
	scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
	scrollThumb:SetHeight(40)
	scrollThumb.tex = scrollThumb:CreateTexture(nil, "ARTWORK")
	scrollThumb.tex:SetAllPoints(scrollThumb)
	scrollThumb.tex:SetColorTexture(0.75, 0.65, 0.95, 0.55)
	if scrollThumb.EnableMouse then scrollThumb:EnableMouse(true) end
	scrollThumb:SetScript("OnMouseDown", function(self)
		if #state.items <= 7 then return end
		self._dragging = true
		self:SetScript("OnUpdate", function(s)
			if not s._dragging then
				s:SetScript("OnUpdate", nil)
				return
			end
			local top = scrollTrack.GetTop and scrollTrack:GetTop()
			local h = scrollTrack.GetHeight and scrollTrack:GetHeight()
			local _, cy = _G.GetCursorPosition and _G.GetCursorPosition()
			local sc = (scrollTrack.GetEffectiveScale and scrollTrack:GetEffectiveScale()) or 1
			if type(top) == "number" and type(h) == "number" and h > 0 and type(cy) == "number" then
				scrollListToRatio((top - (cy / sc)) / h)
			end
		end)
	end)
	scrollThumb:SetScript("OnMouseUp", function(self)
		self._dragging = false
		self:SetScript("OnUpdate", nil)
	end)
	f.scrollThumb = scrollThumb

	local emptyFs = listCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	emptyFs:SetPoint("CENTER", listCard, "CENTER", 0, 0)
	emptyFs:SetWidth(360)
	emptyFs:SetJustifyH("CENTER")
	emptyFs:SetWordWrap(true)
	T.ApplyFont(emptyFs, 12, "regular")
	emptyFs:SetText("No disenchantable gear found in your bags.")
	emptyFs:Hide()
	f.emptyFs = emptyFs

	for i = 1, 7 do
		local row = CreateFrame("Button", nil, listCard)
		row:SetHeight(30)
		row:SetPoint("TOPLEFT", listCard, "TOPLEFT", 6, -6 - (i - 1) * 30)
		row:SetPoint("TOPRIGHT", listCard, "TOPRIGHT", -6, -6 - (i - 1) * 30)
		row:RegisterForClicks("LeftButtonUp")
		if row.EnableMouseWheel then row:EnableMouseWheel(true) end
		row:SetScript("OnMouseWheel", function(_, delta)
			scrollListBy(delta)
		end)

		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints(row)
		row.bg:Hide()

		row.checkBox = row:CreateTexture(nil, "ARTWORK")
		row.checkBox:SetSize(14, 14)
		row.checkBox:SetPoint("LEFT", row, "LEFT", 6, 0)

		row.checkMark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.checkMark:SetPoint("CENTER", row.checkBox, "CENTER", 0, 0)
		row.checkMark:SetJustifyH("CENTER")
		T.ApplyFont(row.checkMark, 10, "bold")
		row.checkMark:SetText("X")

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", row.checkBox, "RIGHT", 8, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		row.evFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.evFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		row.evFs:SetWidth(92)
		row.evFs:SetJustifyH("RIGHT")
		row.evFs:SetWordWrap(false)
		T.ApplyFont(row.evFs, 11, "semibold")

		row.metaFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.metaFs:SetPoint("RIGHT", row.evFs, "LEFT", -8, 0)
		row.metaFs:SetWidth(64)
		row.metaFs:SetJustifyH("RIGHT")
		row.metaFs:SetWordWrap(false)
		T.ApplyFont(row.metaFs, 10, "regular")

		row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.nameFs:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.nameFs:SetPoint("RIGHT", row.metaFs, "LEFT", -6, 0)
		row.nameFs:SetJustifyH("LEFT")
		row.nameFs:SetWordWrap(false)
		T.ApplyFont(row.nameFs, 11.5, "semibold")

		row:SetScript("OnClick", function(self)
			if self.itemKey then
				DisenchantHelper.ToggleKey(self.itemKey)
			end
		end)
		row:SetScript("OnEnter", function(self)
			local p = pal()
			if p and p.cardHover then
				self.bg:SetColorTexture(p.cardHover[1], p.cardHover[2], p.cardHover[3], p.cardHover[4] or 0.12)
				self.bg:Show()
			end
			if _G.GameTooltip and self.itemBag ~= nil and self.itemSlot ~= nil then
				_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if _G.GameTooltip.SetBagItem then
					_G.GameTooltip:SetBagItem(self.itemBag, self.itemSlot)
				elseif self.itemLink and _G.GameTooltip.SetHyperlink then
					_G.GameTooltip:SetHyperlink(self.itemLink)
				end
				_G.GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function(self)
			if self._selectedBg then
				local p = pal()
				local ac = (p and p.accentBlue) or { 0.0, 0.56, 1.0, 0.16 }
				self.bg:SetColorTexture(ac[1], ac[2], ac[3], 0.12)
			else
				self.bg:Hide()
			end
			if _G.GameTooltip_Hide then _G.GameTooltip_Hide()
			elseif _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
		end)
		row:Hide()
		state.rows[i] = row
	end
	f.rows = state.rows

	-- Footer with Skip + SecureActionButtonTemplate DISENCHANT (built first so spotCard anchors above it)
	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	footer:SetHeight(38)
	f.footer = footer

	local skipBtn = T.CreatePlateButton(footer, "Skip", 84, 34, { variant = "secondary", pill = true, fontSize = 12 })
	skipBtn:SetPoint("LEFT", footer, "LEFT", 0, 0)
	skipBtn:SetScript("OnClick", function()
		DisenchantHelper.SkipCurrent()
	end)
	f.skipBtn = skipBtn

	local deBtn = CreateFrame("Button", "MerchantMasterDEActionBtn", footer, "SecureActionButtonTemplate")
	deBtn:SetPoint("LEFT", skipBtn, "RIGHT", 10, 0)
	deBtn:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
	deBtn:SetHeight(34)
	deBtn:EnableMouse(true)
	syncButtonClickEdge(deBtn)
	deBtn.surface = T.NineApple(deBtn, "pill", { 0.42, 0.22, 0.72, 1.0 }, { 0.78, 0.56, 0.98, 0.90 }, { cornerSize = 18 })
	deBtn.label = deBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	deBtn.label:SetAllPoints(deBtn)
	deBtn.label:SetJustifyH("CENTER")
	deBtn.label:SetJustifyV("MIDDLE")
	T.ApplyFont(deBtn.label, 13, "bold")
	deBtn.label:SetText("DISENCHANT")
	applyButtonMacro(deBtn, "")
	deBtn:HookScript("PreClick", function()
		if isInCombat() then return end
		local cur = state.activeIndex and state.items[state.activeIndex] or nil
		if cur then
			local liveID = getBagSlotInfo(cur.bag, cur.slot)
			if liveID ~= cur.itemID then
				DisenchantHelper.ScanBags()
				cur = state.activeIndex and state.items[state.activeIndex] or nil
			end
		end
		applyButtonMacro(deBtn, buildMacroForItem(cur))
		if cur and ns.NotifyDisenchantTarget then
			ns.NotifyDisenchantTarget(cur.bag, cur.slot, cur.itemID, cur.link, "helper", state.arcaneSalvager == true)
		end
	end)
	f.deBtn = deBtn

	-- Active Target Spotlight Card (anchored strictly above footer so DISENCHANT button is never overlapped)
	local spotCard = CreateFrame("Frame", nil, body)
	spotCard:SetPoint("TOPLEFT", listCard, "BOTTOMLEFT", 0, -8)
	spotCard:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 8)
	spotCard.plate = T.NineApple(spotCard, "glass_r10", "cardAltBg", "border")
	f.spotCard = spotCard

	local spotHdr = spotCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spotHdr:SetPoint("TOPLEFT", spotCard, "TOPLEFT", 12, -10)
	spotHdr:SetText("NEXT DISENCHANT TARGET")
	T.ApplyFont(spotHdr, 10, "semibold")
	f.spotHdr = spotHdr

	local spotIcon = spotCard:CreateTexture(nil, "ARTWORK")
	spotIcon:SetSize(28, 28)
	spotIcon:SetPoint("TOPLEFT", spotCard, "TOPLEFT", 12, -28)
	spotIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.spotIcon = spotIcon

	local spotName = spotCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	spotName:SetPoint("TOPLEFT", spotIcon, "TOPRIGHT", 10, 0)
	spotName:SetPoint("TOPRIGHT", spotCard, "TOPRIGHT", -12, -28)
	spotName:SetJustifyH("LEFT")
	spotName:SetWordWrap(false)
	T.ApplyFont(spotName, 13, "semibold")
	f.spotName = spotName

	local spotSub = spotCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	spotSub:SetPoint("TOPLEFT", spotName, "BOTTOMLEFT", 0, -2)
	spotSub:SetPoint("TOPRIGHT", spotCard, "TOPRIGHT", -12, -46)
	spotSub:SetJustifyH("LEFT")
	spotSub:SetWordWrap(false)
	T.ApplyFont(spotSub, 10.5, "regular")
	f.spotSub = spotSub

	for i = 1, 3 do
		local ol = spotCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ol:SetPoint("TOPLEFT", spotCard, "TOPLEFT", 14, -62 - (i - 1) * 16)
		ol:SetPoint("TOPRIGHT", spotCard, "TOPRIGHT", -12, -62 - (i - 1) * 16)
		ol:SetHeight(15)
		ol:SetJustifyH("LEFT")
		ol:SetWordWrap(false)
		T.ApplyFont(ol, 10.5, "regular")
		ol:Hide()
		state.outcomeLines[i] = ol
	end

	local statusFs = spotCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusFs:SetPoint("BOTTOMLEFT", spotCard, "BOTTOMLEFT", 12, 8)
	statusFs:SetPoint("BOTTOMRIGHT", spotCard, "BOTTOMRIGHT", -12, 8)
	statusFs:SetJustifyH("LEFT")
	statusFs:SetWordWrap(false)
	T.ApplyFont(statusFs, 10, "regular")
	f.statusFs = statusFs

	-- Event frame for bag & spellcast auto-advance while open
	local ev = CreateFrame("Frame", nil, f)
	ev:RegisterEvent("BAG_UPDATE_DELAYED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	ev:RegisterEvent("CVAR_UPDATE")
	ev:SetScript("OnEvent", function(_, event, arg1, _, spellID)
		if event == "CVAR_UPDATE" then
			if arg1 == "ActionButtonUseKeyDown" then
				syncButtonClickEdge(f.deBtn)
			end
			return
		end
		if not f:IsShown() then return end
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if arg1 == "player" and spellID == DISENCHANT_SPELL_ID then
				state.castingNotice = "Disenchanted - waiting for bag update..."
				DisenchantHelper.ScanBags()
			end
			return
		end
		if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED" then
			state.castingNotice = nil
			syncButtonClickEdge(f.deBtn)
			DisenchantHelper.ScanBags()
		end
	end)

	f:SetScript("OnShow", function()
		syncButtonClickEdge(f.deBtn)
		DisenchantHelper.ScanBags()
	end)

	T.RegisterWidget(f, function()
		if updateUI then updateUI() end
	end)

	return f
end

updateUI = function()
	local f = state.frame
	if not f then return end
	local p = pal()
	local textCol = p.text or { 1, 1, 1, 1 }
	local secCol = p.textSecondary or { 0.78, 0.78, 0.82, 1 }
	local mutedCol = p.textMuted or { 0.58, 0.58, 0.62, 1 }
	local greenCol = p.accentGreen or { 0.18, 0.84, 0.45, 1 }

	if f.asBtn then
		if f.asBtn.SetVariant then f.asBtn:SetVariant(state.arcaneSalvager and "primary" or "secondary") end
		if f.asBtn.SetActive then f.asBtn:SetActive(state.arcaneSalvager) end
		local fs = f.asBtn.GetFontString and f.asBtn:GetFontString()
		if fs and fs.SetText then
			fs:SetText(state.arcaneSalvager and "AS +20%: ON" or "AS +20%")
		end
	end

	local selCount, totalCopper, unpricedCount, firstIdx = countSelected()
	state.activeIndex = firstIdx

	local totalItems = #state.items
	local maxOff = math.max(0, totalItems - 7)
	if (state.scrollOffset or 0) > maxOff then state.scrollOffset = maxOff end
	local hasScroll = totalItems > 7

	local asNote = state.arcaneSalvager and " (AS +20%)" or ""
	local rangeNote = hasScroll and string.format("  ·  Showing %d-%d", (state.scrollOffset or 0) + 1, math.min(totalItems, (state.scrollOffset or 0) + 7)) or ""
	f.summaryFs:SetTextColor(secCol[1], secCol[2], secCol[3], 1)
	f.summaryFs:SetText(string.format("%d found  ·  %d selected  ·  Est. %s%s%s",
		totalItems, selCount, moneyTxt(totalCopper), asNote, rangeNote))

	f.emptyFs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
	f.emptyFs:SetShown(totalItems == 0)

	if f.scrollTrack and f.scrollThumb then
		if hasScroll then
			f.scrollTrack:Show()
			local trackH = (f.scrollTrack.GetHeight and f.scrollTrack:GetHeight()) or 0
			if trackH <= 0 then trackH = 206 end
			local thumbH = math.max(24, math.floor(trackH * (7 / totalItems) + 0.5))
			local travel = math.max(0, trackH - thumbH)
			local topOffset = (maxOff > 0) and math.floor(travel * ((state.scrollOffset or 0) / maxOff) + 0.5) or 0
			f.scrollThumb:SetHeight(thumbH)
			f.scrollThumb:ClearAllPoints()
			f.scrollThumb:SetPoint("TOP", f.scrollTrack, "TOP", 0, -topOffset)
			f.scrollThumb:Show()
		else
			f.scrollTrack:Hide()
			f.scrollThumb:Hide()
		end
	end

	local acCol = p.accentBlue or { 0.2, 0.55, 1.0, 1 }
	for i = 1, 7 do
		local row = state.rows[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f.listCard, "TOPLEFT", 6, -6 - (i - 1) * 30)
		row:SetPoint("TOPRIGHT", f.listCard, "TOPRIGHT", hasScroll and -18 or -6, -6 - (i - 1) * 30)
		local it = state.items[state.scrollOffset + i]
		if it then
			local isSel = (state.selected[it.key] == true)
			row.itemKey = it.key
			row.itemBag = it.bag
			row.itemSlot = it.slot
			row.itemLink = it.link
			row._selectedBg = isSel
			if isSel then
				row.bg:SetColorTexture(acCol[1], acCol[2], acCol[3], 0.14)
				row.bg:Show()
				row.checkBox:SetColorTexture(greenCol[1], greenCol[2], greenCol[3], 0.92)
				row.checkMark:SetText("X")
				row.checkMark:SetTextColor(0.05, 0.08, 0.05, 1)
			else
				row.bg:Hide()
				row.checkBox:SetColorTexture(mutedCol[1], mutedCol[2], mutedCol[3], 0.28)
				row.checkMark:SetText("")
			end
			row.icon:SetTexture(it.icon)
			local qCol = (p.mode ~= "light" and QUALITY_RGB[it.quality]) or textCol
			row.nameFs:SetTextColor(qCol[1], qCol[2], qCol[3], 1)
			row.nameFs:SetText(it.name)
			row.metaFs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
			row.metaFs:SetText("iLvl " .. tostring(it.ilvl or 0))
			local ev = effectiveEV(it)
			row.evFs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
			row.evFs:SetText(ev and moneyTxt(ev) or "Unpriced")
			row:Show()
		else
			row.itemKey = nil
			row:Hide()
		end
	end

	local cur = state.activeIndex and state.items[state.activeIndex] or nil
	f.spotHdr:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
	if cur then
		f.spotIcon:SetTexture(cur.icon)
		f.spotIcon:Show()
		f.spotName:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
		f.spotName:SetText(cur.name)
		f.spotSub:SetTextColor(secCol[1], secCol[2], secCol[3], 1)
		f.spotSub:SetText(string.format("Bag %d Slot %d  ·  %s iLvl %d %s%s",
			cur.bag, cur.slot, cur.qualityName, cur.ilvl or 0, cur.className,
			cur.isBound and "  ·  Soulbound" or ""))
		for idx = 1, 3 do
			local ol = state.outcomeLines[idx]
			local o = cur.outcomes and cur.outcomes[idx]
			if o then
				local pctStr = ns.FormatDEChancePct and ns.FormatDEChancePct(o.matRate) or tostring(math.floor((o.matRate or 0) * 100 + 0.5))
				local amtStr = (o.minAmount == o.maxAmount) and (tostring(o.minAmount) .. "x") or (tostring(o.minAmount) .. "-" .. tostring(o.maxAmount) .. "x")
				local evVal = o.evNetRounded
				if evVal and state.arcaneSalvager then
					evVal = math.floor(evVal * AS_MULT + 0.5)
				end
				ol:SetTextColor(secCol[1], secCol[2], secCol[3], 1)
				ol:SetText(string.format("%s%%  %s  (%s)  ->  %s", pctStr, o.name or "Material", amtStr, evVal and moneyTxt(evVal) or "Unpriced"))
				ol:Show()
			else
				ol:Hide()
			end
		end
		if f.statusFs then
			f.statusFs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
			f.statusFs:SetText(state.castingNotice or string.format("%d item%s queued for continuous Disenchant clicks", selCount, selCount == 1 and "" or "s"))
		end
	else
		f.spotIcon:Hide()
		f.spotName:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
		f.spotName:SetText("Select items above to disenchant")
		f.spotSub:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
		f.spotSub:SetText("Click rows individually or use All / Green / Blue pills.")
		for idx = 1, 3 do state.outcomeLines[idx]:Hide() end
		if f.statusFs then
			f.statusFs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
			f.statusFs:SetText("Tip: Enable AS +20% when near your Arcane Salvager.")
		end
	end

	if f.skipBtn and f.skipBtn.SetEnabled then
		f.skipBtn:SetEnabled(cur ~= nil)
	end
	local macro = buildMacroForItem(cur)
	applyButtonMacro(f.deBtn, macro)
	syncButtonClickEdge(f.deBtn)
	local canClick = (cur ~= nil) and (not isInCombat())
	if f.deBtn.SetEnabled then f.deBtn:SetEnabled(canClick) end
	if canClick then
		f.deBtn.label:SetText(string.format("DISENCHANT (%d left)", selCount))
		f.deBtn.label:SetTextColor(1, 1, 1, 1)
		local surf = f.deBtn.surface
		if surf and surf.SetFill then
			surf:SetFill(0.44, 0.22, 0.74, 1.0)
			if surf.SetStroke then surf:SetStroke(0.82, 0.62, 1.0, 0.92) end
		end
	else
		f.deBtn.label:SetText(isInCombat() and "IN COMBAT" or "DISENCHANT")
		f.deBtn.label:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1)
		local surf = f.deBtn.surface
		if surf and surf.SetFill then
			local cbg = p.cardAltBg or { 0.14, 0.14, 0.16, 0.85 }
			local brd = p.border or { 0.3, 0.3, 0.35, 0.5 }
			surf:SetFill(cbg[1], cbg[2], cbg[3], cbg[4] or 0.85)
			if surf.SetStroke then surf:SetStroke(brd[1], brd[2], brd[3], brd[4] or 0.5) end
		end
	end
end

function DisenchantHelper.ScrollBy(delta)
	return scrollListBy(delta)
end

function DisenchantHelper.Show()
	local f = ensureBuilt()
	if not f then return false end
	f:Show()
	DisenchantHelper.ScanBags()
	return true
end

function DisenchantHelper.Hide()
	if state.frame then state.frame:Hide() end
end

function DisenchantHelper.Toggle()
	local f = ensureBuilt()
	if not f then return false end
	if f:IsShown() then
		f:Hide()
		return false
	end
	return DisenchantHelper.Show()
end

function DisenchantHelper.GetActiveTarget()
	local cur = state.activeIndex and state.items[state.activeIndex] or nil
	if not cur then return nil end
	return cur.bag, cur.slot, cur.itemID, cur.link, state.arcaneSalvager == true
end

function DisenchantHelper.GetState()
	local selCount, totalCopper, unpricedCount = countSelected()
	local active = state.activeIndex and state.items[state.activeIndex] or nil
	return {
		shown = (state.frame and state.frame:IsShown()) and true or false,
		frame = state.frame,
		itemCount = #state.items,
		items = state.items,
		selectedCount = selCount,
		totalEstCopper = totalCopper,
		unpricedCount = unpricedCount,
		arcaneSalvager = state.arcaneSalvager,
		scrollOffset = state.scrollOffset or 0,
		maxScrollOffset = math.max(0, #state.items - 7),
		activeItem = active,
		macrotext = state.frame and state.frame.deBtn and state.frame.deBtn:GetAttribute("macrotext") or "",
	}
end
