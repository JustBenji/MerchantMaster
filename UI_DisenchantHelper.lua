-- MerchantMaster: Standalone Bag Disenchant Helper Window
-- Lets the player pick disenchantable bag items, toggle Arcane Salvager (+20%),
-- and continuously click one SecureActionButtonTemplate DISENCHANT button.

local ADDON, ns = ...

local DisenchantHelper = {}
ns.DisenchantHelper = DisenchantHelper

local DISENCHANT_SPELL_ID = 13262
local ENCHANTING_SKILL_LINE = 333
local ENCHANTING_SPELL_ID = 7411
local PROF_BTN_SIZE = 30
local CRAFT_BTN_SIZE = 28
local CRAFT_FRAME_NAMES = { "CraftFrame", "TradeSkillFrame", "ProfessionsFrame" }
local WATCHED_ADDONS = {
	Blizzard_ProfessionsBook = true,
	Blizzard_CraftUI = true,
	Blizzard_TradeSkillUI = true,
	Blizzard_Professions = true,
	MerchantMaster = true,
}
local COMBAT_DEFER_MSG = "MerchantMaster: Cannot open Disenchant Helper for the first time during combat - it will open when combat ends."
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
	pendingOpenAfterCombat = false,
	pendingButtonsRefresh = false,
	profBookBtn = nil,
	profBookBtns = {},
	craftWinBtns = {},
	activeCraftWinBtn = nil,
	eventFrame = nil,
}
local hookedGlobals = {}
local hookedFrames = {}
local registeredEventRegistry = {}
local EVENT_REGISTRY_OWNER = {}
local PANEL_BUTTON_KEYS = {
	"SpellButton1",
	"SpellButton2",
	"SpellButtonTop",
	"SpellButtonBottom",
	"button1",
	"button2",
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

local function hasSecret(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if _G.issecrettable and type(v) == "table" and _G.issecrettable(v) then return true end
		if _G.issecretvalue and _G.issecretvalue(v) then return true end
	end
	return false
end

local function getBagNumSlots(bag)
	if _G.C_Container and _G.C_Container.GetContainerNumSlots then
		local n = _G.C_Container.GetContainerNumSlots(bag)
		if hasSecret(n) then return 0 end
		return tonumber(n) or 0
	elseif _G.GetContainerNumSlots then
		local n = _G.GetContainerNumSlots(bag)
		if hasSecret(n) then return 0 end
		return tonumber(n) or 0
	end
	return 0
end

local function getBagSlotInfo(bag, slot)
	if _G.C_Container and _G.C_Container.GetContainerItemInfo then
		local info = _G.C_Container.GetContainerItemInfo(bag, slot)
		if hasSecret(info) or type(info) ~= "table" then return nil end
		if hasSecret(info.itemID, info.hyperlink, info.iconFileID, info.stackCount, info.isBound) then return nil end
		if info.itemID then
			local link = info.hyperlink
			if not link and _G.C_Container.GetContainerItemLink then
				link = _G.C_Container.GetContainerItemLink(bag, slot)
				if hasSecret(link) then link = nil end
			end
			return tonumber(info.itemID), link, info.iconFileID, tonumber(info.stackCount) or 1, info.isBound == true
		end
		return nil
	elseif _G.GetContainerItemInfo then
		local icon, count, _, quality, _, _, link = _G.GetContainerItemInfo(bag, slot)
		if hasSecret(icon, count, quality, link) then return nil end
		if type(link) == "string" then
			local id = tonumber(link:match("item:(%d+)"))
			return id, link, icon, tonumber(count) or 1, false, quality
		end
	end
	return nil
end

local function isInCombat()
	if not _G.InCombatLockdown then return false end
	local v = _G.InCombatLockdown()
	if hasSecret(v) then return true end
	return v and true or false
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
	state.lastPriceRev = (ns.GetPriceDataRevision and ns.GetPriceDataRevision()) or ns.priceCacheEpoch or 0
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
	if not hasSecret(name) and type(name) == "string" and name ~= "" then
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

local function isFrameVisible(fr)
	if not fr then return false end
	if type(fr.IsVisible) == "function" then
		local vis = fr:IsVisible()
		if not hasSecret(vis) then
			return vis and true or false
		end
	end
	if type(fr.IsShown) == "function" then
		local sh = fr:IsShown()
		if not hasSecret(sh) then
			return sh and true or false
		end
	end
	return false
end

local function getDefaultAnchorFrame()
	for _, fr in ipairs({ _G.ProfessionsFrame, _G.CraftFrame, _G.TradeSkillFrame, _G.SpellBookFrame }) do
		if isFrameVisible(fr) then
			return fr
		end
	end
	return nil
end

local function syncDockModeButton(f)
	if not (f and f.dockModeBtn) then return end
	local btn = f.dockModeBtn
	local mode = (ns.Window and ns.Window.GetMode) and ns.Window.GetMode("disenchant_helper", "snap") or "snap"
	local lbl = (mode == "lock" and "Lock") or (mode == "free" and "Free") or "Snap"
	if btn.SetText then
		btn:SetText(lbl)
	elseif btn.fs and btn.fs.SetText then
		btn.fs:SetText(lbl)
	end
	if btn.SetVariant then
		btn:SetVariant(mode == "lock" and "primary" or "secondary")
	end
	if btn.SetActive then
		btn:SetActive(mode == "lock")
	end
end

local function applyWindowPosition(f)
	if not f or isInCombat() then return end
	local mode = (ns.Window and ns.Window.GetMode) and ns.Window.GetMode("disenchant_helper", "snap") or "snap"
	if mode == "free" and ns.Window and ns.Window.HasSavedPosition and ns.Window.HasSavedPosition("disenchant_helper") then
		ns.Window.RestorePosition(f, "disenchant_helper")
	elseif ns.Window and ns.Window.PlaceBeside then
		ns.Window.PlaceBeside(f, getDefaultAnchorFrame(), "CENTER", 0, 0, 12)
	end
	syncDockModeButton(f)
end

local function ensureBuilt()
	if state.frame then return state.frame end
	if isInCombat() then return nil end
	local T = ns.Theme
	if not (T and T.CreateFloatingWindow) then return nil end

	local f = T.CreateFloatingWindow("MerchantMasterDisenchantHelper", "Disenchant Helper", 496, 584, {
		warcraftChrome = true,
		compactChrome = true,
		customTitleUpper = true,
		centerY = 0,
		positionKey = "disenchant_helper",
		combatSafeDrag = true,
		canDrag = function()
			return (not ns.Window or not ns.Window.GetMode)
				or ns.Window.GetMode("disenchant_helper", "snap") ~= "lock"
		end,
		onDragStart = function(win)
			if ns.Window and ns.Window.GetMode and ns.Window.GetMode("disenchant_helper", "snap") == "snap" then
				ns.Window.SetMode("disenchant_helper", "free")
				syncDockModeButton(win)
			end
		end,
	})
	state.frame = f
	if f.header and f.closeBtn then
		local dockBtn = T.CreatePlateButton(f.header, "Snap", 48, 22, { variant = "secondary", pill = true, fontSize = 10 })
		dockBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -6, 0)
		dockBtn:SetScript("OnClick", function()
			if not (ns.Window and ns.Window.CycleMode) then return end
			local nextMode = ns.Window.CycleMode("disenchant_helper", "snap")
			if nextMode == "free" then
				if ns.Window.DetachToUIParent then ns.Window.DetachToUIParent(f) end
				if ns.Window.SavePosition then ns.Window.SavePosition(f, "disenchant_helper") end
				syncDockModeButton(f)
			else
				applyWindowPosition(f)
			end
		end)
		if dockBtn.HookScript and _G.GameTooltip then
			dockBtn:HookScript("OnEnter", function(self)
				local mode = (ns.Window and ns.Window.GetMode) and ns.Window.GetMode("disenchant_helper", "snap") or "snap"
				_G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
				_G.GameTooltip:AddLine("Window Dock: " .. ((mode == "lock" and "Lock") or (mode == "free" and "Free") or "Snap"), 1, 0.85, 0.25)
				if mode == "snap" then
					_G.GameTooltip:AddLine("Snap: Attached to the profession window. Drag to switch to Free, or click to Lock.", 0.9, 0.92, 0.96, true)
				elseif mode == "lock" then
					_G.GameTooltip:AddLine("Lock: Locked beside the profession window so they stay together. Click to switch to Free.", 0.9, 0.92, 0.96, true)
				else
					_G.GameTooltip:AddLine("Free: Saved free position. Click to snap back beside the profession window.", 0.9, 0.92, 0.96, true)
				end
				_G.GameTooltip:Show()
			end)
			dockBtn:HookScript("OnLeave", function()
				if _G.GameTooltip_Hide then _G.GameTooltip_Hide() elseif _G.GameTooltip then _G.GameTooltip:Hide() end
			end)
		end
		f.dockModeBtn = dockBtn
		f._mmTitleRightAnchor = dockBtn
		if f.titleFs then
			f.titleFs:SetPoint("RIGHT", dockBtn, "LEFT", -8, 0)
		end
		syncDockModeButton(f)
	end
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
			if not hasSecret(arg1) and arg1 == "ActionButtonUseKeyDown" then
				syncButtonClickEdge(f.deBtn)
			end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if state.pendingButtonsRefresh and not isInCombat() then
				state.pendingButtonsRefresh = false
				DisenchantHelper.RefreshProfessionButtons()
			end
		end
		if not f:IsShown() then return end
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if not hasSecret(arg1, spellID) and arg1 == "player" and spellID == DISENCHANT_SPELL_ID then
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
	syncDockModeButton(f)
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
	local inCombat = isInCombat()
	local canClick = (cur ~= nil) and (not inCombat)
	if not inCombat then
		if f.deBtn.SetEnabled then f.deBtn:SetEnabled(canClick) end
	end
	if canClick then
		f.deBtn.label:SetText(string.format("DISENCHANT (%d left)", selCount))
		f.deBtn.label:SetTextColor(1, 1, 1, 1)
		local surf = f.deBtn.surface
		if surf and surf.SetFill then
			surf:SetFill(0.44, 0.22, 0.74, 1.0)
			if surf.SetStroke then surf:SetStroke(0.82, 0.62, 1.0, 0.92) end
		end
	else
		f.deBtn.label:SetText(inCombat and "IN COMBAT" or "DISENCHANT")
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

local function deferFirstOpenInCombat()
	if not state.frame and isInCombat() then
		state.pendingOpenAfterCombat = true
		if _G.print then
			_G.print(COMBAT_DEFER_MSG)
		end
		return true
	end
	return false
end

function DisenchantHelper.ApplyPosition()
	if state.frame then
		applyWindowPosition(state.frame)
	end
end

function DisenchantHelper.Invalidate()
	state.lastPriceRev = nil
	if ns.ClearDECache then ns.ClearDECache() end
	if state.frame and state.frame:IsShown() then
		DisenchantHelper.ScanBags()
	end
end

function DisenchantHelper.Show()
	if deferFirstOpenInCombat() then return false end
	local f = ensureBuilt()
	if not f then return false end
	state.pendingOpenAfterCombat = false
	applyWindowPosition(f)
	f:Show()
	DisenchantHelper.ScanBags()
	return true
end

function DisenchantHelper.Hide()
	state.pendingOpenAfterCombat = false
	if state.frame then state.frame:Hide() end
end

function DisenchantHelper.Toggle()
	if deferFirstOpenInCombat() then return false end
	local f = ensureBuilt()
	if not f then return false end
	if f:IsShown() then
		f:Hide()
		return false
	end
	return DisenchantHelper.Show()
end

---------------------------------------------------------------------------------------------------
-- Launcher Buttons in Blizzard Professions Spellbook & Enchanting Craft Windows
---------------------------------------------------------------------------------------------------
local function isProfBookVisible(profFrame)
	if not isFrameVisible(profFrame) then return false end
	if profFrame == _G.SpellBookProfessionFrame and _G.SpellBookFrame then
		if not isFrameVisible(_G.SpellBookFrame) then return false end
	end
	if _G.ProfessionsFrame and profFrame == _G.ProfessionsFrame.BookPage then
		if not isFrameVisible(_G.ProfessionsFrame) then return false end
	end
	return true
end

local function getEnchantingSpellName()
	local name = (_G.C_Spell and _G.C_Spell.GetSpellName and _G.C_Spell.GetSpellName(ENCHANTING_SPELL_ID))
		or (_G.GetSpellInfo and _G.GetSpellInfo(ENCHANTING_SPELL_ID))
	if not hasSecret(name) and type(name) == "string" and name ~= "" then
		return name
	end
	return "Enchanting"
end

local function isEnchantingName(name)
	if hasSecret(name) or type(name) ~= "string" or name == "" then return false end
	local low = name:lower()
	if low == "enchanting" then return true end
	local locName = getEnchantingSpellName()
	if type(locName) == "string" and locName ~= "" and low == locName:lower() then
		return true
	end
	return false
end

local function paintLauncherButton(btn)
	if not btn then return end
	local T = ns.Theme
	local p = pal()
	local isLight = (p.mode == "light")
	local hovered = (btn._hovered == true)
	local customSkin = (T and T.IsCustomSkin and T.IsCustomSkin()) and true or false
	local deTex = (customSkin and T and T.GetSkinAsset and T.GetSkin)
		and T.GetSkinAsset(T.GetSkin(), "de_btn") or nil

	if customSkin and deTex and btn.skinArt then
		if btn.surface and btn.surface.SetShown then
			btn.surface:SetShown(false)
		elseif btn.surface and btn.surface.UpdateTheme then
			btn.surface:UpdateTheme({ 0, 0, 0, 0 }, false)
		end
		if btn.iconTex then btn.iconTex:Hide() end
		btn.skinArt:SetTexture(deTex)
		local boost = hovered and 1.0 or 0.95
		btn.skinArt:SetVertexColor(boost, boost, boost, 1)
		btn.skinArt:Show()
		if btn.skinHover then
			btn.skinHover:SetTexture(deTex)
			btn.skinHover:Show()
		end
	else
		if btn.skinArt then btn.skinArt:Hide() end
		if btn.skinHover then btn.skinHover:Hide() end
		if btn.surface and btn.surface.SetShown then btn.surface:SetShown(true) end
		local dCol = isLight and { 0.34, 0.20, 0.64, 1.0 } or { 0.36, 0.22, 0.66, 1.0 }
		if hovered then
			dCol = {
				math.min(1, dCol[1] + (isLight and 0.08 or 0.12)),
				math.min(1, dCol[2] + (isLight and 0.08 or 0.10)),
				math.min(1, dCol[3] + 0.08),
				1.0,
			}
		end
		btn._fillColor = dCol
		if btn.surface and btn.surface.UpdateTheme then
			btn.surface:UpdateTheme(dCol, false)
		end
		if btn.iconTex then
			btn.iconTex:Show()
			if btn.iconTex.SetVertexColor then
				btn.iconTex:SetVertexColor(1, 1, 1, 1)
			end
		end
	end
end

local function createLauncherButton(parent, size)
	local T = ns.Theme
	local sz = tonumber(size) or 28
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(sz, sz)
	btn:SetText("")
	if btn.EnableMouse then btn:EnableMouse(true) end
	if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp") end

	if T and T.NineApple then
		btn.surface = T.NineApple(btn, "pill", { 0.36, 0.22, 0.66, 1.0 }, false, {
			cornerSize = math.floor(sz / 2),
		})
	end
	if T and T.AppleIcon then
		btn.iconTex = T.AppleIcon(btn, "star", math.max(12, math.floor(sz * 0.56)), { 1, 1, 1, 1 })
		btn.iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
	end
	btn.skinArt = btn:CreateTexture(nil, "ARTWORK", nil, 1)
	btn.skinArt:SetAllPoints(btn)
	btn.skinArt:Hide()
	btn.skinHover = btn:CreateTexture(nil, "HIGHLIGHT")
	btn.skinHover:SetAllPoints(btn)
	if btn.skinHover.SetBlendMode then btn.skinHover:SetBlendMode("ADD") end
	btn.skinHover:SetVertexColor(1, 0.96, 0.85, 0.20)
	btn.skinHover:Hide()

	btn:SetScript("OnClick", function()
		DisenchantHelper.Toggle()
	end)
	btn:SetScript("OnEnter", function(self)
		self._hovered = true
		paintLauncherButton(self)
		if _G.GameTooltip then
			_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			_G.GameTooltip:AddLine("Disenchant Helper", 1, 1, 1)
			_G.GameTooltip:AddLine("Scan bag gear and queue greens/blues for continuous 1-click Disenchanting.", 0.85, 0.85, 0.88, true)
			_G.GameTooltip:AddLine("Click to open or close Disenchant Helper.", 0.78, 0.62, 1)
			_G.GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function(self)
		self._hovered = false
		paintLauncherButton(self)
		if _G.GameTooltip_Hide then
			_G.GameTooltip_Hide()
		elseif _G.GameTooltip and _G.GameTooltip.Hide then
			_G.GameTooltip:Hide()
		end
	end)

	paintLauncherButton(btn)
	if T and T.RegisterWidget then
		T.RegisterWidget(btn, function()
			paintLauncherButton(btn)
		end)
	end
	btn:Hide()
	return btn
end

local function safeFrameLevel(fr)
	if not fr or type(fr.GetFrameLevel) ~= "function" then return 0 end
	local lvl = fr:GetFrameLevel()
	if hasSecret(lvl) or type(lvl) ~= "number" then return 0 end
	return lvl
end

local function getButtonLabelText(btn)
	if not btn then return nil end
	local labelFs = btn.spellString
		or btn.SpellName
		or (type(btn.GetName) == "function" and btn:GetName() and _G[btn:GetName() .. "SpellName"])
	if labelFs and type(labelFs.GetText) == "function" then
		local ok, txt = pcall(labelFs.GetText, labelFs)
		if ok and not hasSecret(txt) and type(txt) == "string" and txt ~= "" then
			return txt
		end
	end
	return nil
end

local function isDisenchantSpellButton(btn, spellOffset, numAbilities, slotHint)
	if not btn then return false end
	local deName = getDisenchantSpellName()
	local deLow = deName:lower()

	if btn.spellID ~= nil and not hasSecret(btn.spellID) then
		if btn.spellID == DISENCHANT_SPELL_ID then return true end
	end
	if type(btn.GetSpellID) == "function" then
		local okId, sid = pcall(btn.GetSpellID, btn)
		if okId and not hasSecret(sid) and sid == DISENCHANT_SPELL_ID then
			return true
		end
	end

	local slot = nil
	if type(btn.slotID) == "number" and not hasSecret(btn.slotID) and btn.slotID > 0 then
		slot = btn.slotID
	elseif type(btn.spellIndex) == "number" and not hasSecret(btn.spellIndex) and btn.spellIndex > 0 then
		slot = btn.spellIndex
	elseif type(btn.GetID) == "function" then
		local rawID = btn:GetID()
		if not hasSecret(rawID) and type(rawID) == "number" and rawID > 0 then
			local off = (type(btn.spellOffset) == "number" and not hasSecret(btn.spellOffset) and btn.spellOffset)
				or (type(spellOffset) == "number" and spellOffset) or 0
			if off > 0 and rawID <= math.max(2, tonumber(numAbilities) or 2) then
				slot = off + rawID
			else
				slot = rawID
			end
		end
	end
	if not slot and type(spellOffset) == "number" and type(slotHint) == "number" then
		if (tonumber(numAbilities) or 0) >= slotHint then
			slot = spellOffset + slotHint
		end
	end

	if slot and _G.C_SpellBook and type(_G.C_SpellBook.GetSpellBookItemInfo) == "function" then
		local bank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player) or 0
		local ok, info = pcall(_G.C_SpellBook.GetSpellBookItemInfo, slot, bank)
		if ok and type(info) == "table" and not hasSecret(info) then
			if (not hasSecret(info.spellID) and info.spellID == DISENCHANT_SPELL_ID)
				or (not hasSecret(info.actionID) and info.actionID == DISENCHANT_SPELL_ID) then
				return true
			end
			if not hasSecret(info.name) and type(info.name) == "string" and info.name ~= "" then
				local sl = info.name:lower()
				if sl == "disenchant" or sl == deLow then return true end
			end
		end
	end

	if slot and type(_G.GetSpellBookItemInfo) == "function" then
		local bookTypes = { _G.BOOKTYPE_PROFESSION or "professions", _G.BOOKTYPE_SPELL or "spell" }
		for _, bt in ipairs(bookTypes) do
			local ok, skillType, spellID = pcall(_G.GetSpellBookItemInfo, slot, bt)
			if ok and not hasSecret(skillType, spellID) and spellID == DISENCHANT_SPELL_ID then
				return true
			end
			if type(_G.GetSpellBookItemName) == "function" then
				local nok, sname = pcall(_G.GetSpellBookItemName, slot, bt)
				if nok and not hasSecret(sname) and type(sname) == "string" and sname ~= "" then
					local sl = sname:lower()
					if sl == "disenchant" or sl == deLow then return true end
				end
			end
		end
	end

	local txt = getButtonLabelText(btn)
	if txt then
		local tl = txt:lower()
		if tl == "disenchant" or tl == deLow then return true end
	end

	return false
end

local function resolvePrimaryPanel(profBookFrame, content, panelName)
	return (content and content[panelName]) or profBookFrame[panelName] or _G[panelName]
end

local function findDisenchantButtonInPanel(profPanel, panelName, spellOffset, numAbilities)
	if not (profPanel and isFrameVisible(profPanel)) then return nil end
	local rawCandidates = {
		{ btn = profPanel.SpellButton1, hint = 1 },
		{ btn = profPanel.SpellButton2, hint = 2 },
		{ btn = profPanel.SpellButtonTop, hint = 1 },
		{ btn = profPanel.SpellButtonBottom, hint = 2 },
		{ btn = profPanel.button1, hint = 1 },
		{ btn = profPanel.button2, hint = 2 },
		{ btn = _G[panelName .. "SpellButton1"], hint = 1 },
		{ btn = _G[panelName .. "SpellButton2"], hint = 2 },
		{ btn = _G[panelName .. "SpellButtonTop"], hint = 1 },
		{ btn = _G[panelName .. "SpellButtonBottom"], hint = 2 },
	}
	local seen = {}
	for _, entry in ipairs(rawCandidates) do
		local b = entry.btn
		if b and not seen[b] then
			seen[b] = true
			if isFrameVisible(b) and isDisenchantSpellButton(b, spellOffset, numAbilities, entry.hint) then
				return b
			end
		end
	end
	return nil
end

local function isPanelEnchanting(profPanel, panelName)
	if not profPanel then return false end
	local nameFs = profPanel.professionName
		or profPanel.ProfessionName
		or (panelName and _G[panelName .. "ProfessionName"])
	if nameFs and type(nameFs.GetText) == "function" then
		local ok, txt = pcall(nameFs.GetText, nameFs)
		if ok and isEnchantingName(txt) then
			return true
		end
	end
	for _, key in ipairs(PANEL_BUTTON_KEYS) do
		local b = profPanel[key]
		if b and isFrameVisible(b) then
			if b.spellID ~= nil and not hasSecret(b.spellID) and b.spellID == ENCHANTING_SPELL_ID then
				return true
			end
			if isEnchantingName(getButtonLabelText(b)) then
				return true
			end
		end
	end
	return false
end

local function findEnchantingDisenchantButton(profBookFrame)
	if not isProfBookVisible(profBookFrame) then return nil, nil end
	local content = profBookFrame.ProfessionsContentFrame or profBookFrame
	if content ~= profBookFrame and not isFrameVisible(content) then
		return nil, nil
	end

	local profApiResolved = false
	local knowsEnchanting = false
	if type(_G.GetProfessions) == "function" and type(_G.GetProfessionInfo) == "function" then
		local okP, p1, p2 = pcall(_G.GetProfessions)
		if okP and not hasSecret(p1, p2) then
			local primaryIndices = { p1, p2 }
			for slotIdx = 1, 2 do
				local profIdx = primaryIndices[slotIdx]
				if type(profIdx) == "number" and profIdx > 0 then
					local okI, name, _, _, _, numAbilities, spellOffset, skillLine = pcall(_G.GetProfessionInfo, profIdx)
					if okI and not hasSecret(name, numAbilities, spellOffset, skillLine) then
						profApiResolved = true
						if skillLine == ENCHANTING_SKILL_LINE or isEnchantingName(name) then
							knowsEnchanting = true
							local panelName = "PrimaryProfession" .. slotIdx
							local profPanel = resolvePrimaryPanel(profBookFrame, content, panelName)
							local found = findDisenchantButtonInPanel(profPanel, panelName, spellOffset, numAbilities)
							if found then
								return found, profPanel
							end
						end
					end
				end
			end
		end
	end

	if profApiResolved and not knowsEnchanting then
		return nil, nil
	end

	for slotIdx = 1, 2 do
		local panelName = "PrimaryProfession" .. slotIdx
		local profPanel = resolvePrimaryPanel(profBookFrame, content, panelName)
		if profPanel and isFrameVisible(profPanel) then
			local found = findDisenchantButtonInPanel(profPanel, panelName, nil, nil)
			if found and (knowsEnchanting or isPanelEnchanting(profPanel, panelName) or isDisenchantSpellButton(found, nil, nil, nil)) then
				return found, profPanel
			end
		end
	end

	return nil, nil
end

local function getFrameBoundsX(fr)
	if not fr then return nil, nil end
	local l = type(fr.GetLeft) == "function" and fr:GetLeft() or nil
	local r = type(fr.GetRight) == "function" and fr:GetRight() or nil
	local w = type(fr.GetWidth) == "function" and fr:GetWidth() or nil
	if hasSecret(l, r, w) then return nil, nil end
	if type(l) == "number" then
		if type(r) ~= "number" then
			r = l + ((type(w) == "number" and w > 0) and w or 0)
		end
		return l, r
	end
	return nil, nil
end

local function anchorProfBookButton(btn, profBookFrame, profPanel, spellBtn)
	local gap = 8
	local edgePad = 8
	local labelFs = spellBtn.spellString
		or spellBtn.SpellName
		or (type(spellBtn.GetName) == "function" and spellBtn:GetName() and _G[spellBtn:GetName() .. "SpellName"])

	local btnL, btnR = getFrameBoundsX(spellBtn)
	local contL, contR = getFrameBoundsX(profBookFrame)
	local panelL, panelR = getFrameBoundsX(profPanel)
	if not contL then contL, contR = panelL, panelR end
	if contL and panelL then contL = math.max(contL, panelL) end
	if contR and panelR then contR = math.min(contR, panelR) end

	local labelL, labelR = nil, nil
	if labelFs and isFrameVisible(labelFs) then
		labelL, labelR = getFrameBoundsX(labelFs)
		local strW = (type(labelFs.GetStringWidth) == "function" and labelFs:GetStringWidth()) or 0
		if hasSecret(strW) or type(strW) ~= "number" then strW = 0 end
		if labelL then
			labelR = math.max(labelR or labelL, labelL + strW)
		end
	end

	btn:ClearAllPoints()
	if btnL and btnR and contL and contR and contR > contL then
		local contentRight = (labelR and labelR > btnR) and labelR or btnR
		if contentRight + gap + PROF_BTN_SIZE <= contR - edgePad then
			local offX = math.ceil(contentRight - btnR) + gap
			btn:SetPoint("LEFT", spellBtn, "RIGHT", offX, 0)
		elseif (btnL - gap - PROF_BTN_SIZE >= contL + edgePad) and (not labelL or labelL >= btnL) then
			btn:SetPoint("RIGHT", spellBtn, "LEFT", -gap, 0)
		else
			btn:SetPoint("TOP", spellBtn, "BOTTOM", 0, -6)
		end
	else
		local labelW = 0
		if labelFs and isFrameVisible(labelFs) then
			local lw = (type(labelFs.GetWidth) == "function" and labelFs:GetWidth()) or 0
			local sw = (type(labelFs.GetStringWidth) == "function" and labelFs:GetStringWidth()) or 0
			if not hasSecret(lw, sw) then
				labelW = math.max(tonumber(lw) or 0, tonumber(sw) or 0)
			end
		end
		if labelW > 0 then
			btn:SetPoint("LEFT", spellBtn, "RIGHT", math.min(120, math.ceil(labelW) + 12), 0)
		else
			btn:SetPoint("LEFT", spellBtn, "RIGHT", gap, 0)
		end
	end

	if btn.SetFrameStrata then
		local strata = (profBookFrame and profBookFrame.GetFrameStrata and profBookFrame:GetFrameStrata())
			or (profPanel and profPanel.GetFrameStrata and profPanel:GetFrameStrata())
			or "MEDIUM"
		if hasSecret(strata) or type(strata) ~= "string" or strata == "" then
			strata = "MEDIUM"
		end
		btn:SetFrameStrata(strata)
	end
	if btn.SetFrameLevel then
		local targetLevel = math.max(
			safeFrameLevel(spellBtn),
			safeFrameLevel(profPanel),
			safeFrameLevel(profBookFrame)
		) + 5
		btn:SetFrameLevel(targetLevel)
	end
end

local function isCraftWindowEnchanting(frameName)
	if frameName == "CraftFrame" then
		if type(_G.GetCraftDisplaySkillLine) == "function" then
			local ok, name = pcall(_G.GetCraftDisplaySkillLine)
			if ok and not hasSecret(name) then
				if isEnchantingName(name) then return true end
				if type(name) == "string" and name ~= "" then return false end
			end
		end
	elseif frameName == "TradeSkillFrame" then
		if type(_G.GetTradeSkillLine) == "function" then
			local ok, name = pcall(_G.GetTradeSkillLine)
			if ok and not hasSecret(name) then
				if isEnchantingName(name) then return true end
				if type(name) == "string" and name ~= "" then return false end
			end
		end
	end

	if _G.C_TradeSkillUI and type(_G.C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
		local ok, info = pcall(_G.C_TradeSkillUI.GetBaseProfessionInfo)
		if ok and type(info) == "table" and not hasSecret(info) then
			if not hasSecret(info.professionID) and info.professionID == ENCHANTING_SKILL_LINE then
				return true
			end
			if isEnchantingName(info.professionName) then
				return true
			end
			if (info.professionID ~= nil and not hasSecret(info.professionID))
				or (not hasSecret(info.professionName) and type(info.professionName) == "string" and info.professionName ~= "") then
				return false
			end
		end
	end

	if frameName == "ProfessionsFrame" then
		if type(_G.GetTradeSkillLine) == "function" then
			local ok, name = pcall(_G.GetTradeSkillLine)
			if ok and isEnchantingName(name) then return true end
		end
		if type(_G.GetCraftDisplaySkillLine) == "function" then
			local ok, name = pcall(_G.GetCraftDisplaySkillLine)
			if ok and isEnchantingName(name) then return true end
		end
	end

	return false
end

local function hideAllProfBookButtons()
	for _, b in pairs(state.profBookBtns) do
		if b and b.Hide then b:Hide() end
	end
	if state.profBookBtn and state.profBookBtn.Hide then
		state.profBookBtn:Hide()
	end
end

local function refreshProfBookButton()
	local activeBook = nil
	local spellBtn = nil
	local profPanel = nil
	local bookCandidates = {}
	if _G.ProfessionsFrame and _G.ProfessionsFrame.BookPage then
		bookCandidates[#bookCandidates + 1] = _G.ProfessionsFrame.BookPage
	end
	if _G.SpellBookProfessionFrame then
		bookCandidates[#bookCandidates + 1] = _G.SpellBookProfessionFrame
	end
	if _G.ProfessionsBookFrame then
		bookCandidates[#bookCandidates + 1] = _G.ProfessionsBookFrame
	end

	for _, fr in ipairs(bookCandidates) do
		if isProfBookVisible(fr) then
			local foundBtn, foundPanel = findEnchantingDisenchantButton(fr)
			if foundBtn then
				activeBook = fr
				spellBtn = foundBtn
				profPanel = foundPanel
				break
			end
		end
	end

	if not (activeBook and spellBtn) then
		hideAllProfBookButtons()
		return false
	end

	local targetParent = profPanel or activeBook
	for owner, b in pairs(state.profBookBtns) do
		if owner ~= targetParent and b and b.Hide then
			b:Hide()
		end
	end

	local btn = state.profBookBtns[targetParent]
	if not btn or (btn.GetParent and btn:GetParent() ~= targetParent) then
		if btn and btn.Hide then btn:Hide() end
		btn = createLauncherButton(targetParent, PROF_BTN_SIZE)
		state.profBookBtns[targetParent] = btn
	end
	state.profBookBtn = btn
	anchorProfBookButton(btn, activeBook, profPanel, spellBtn)
	paintLauncherButton(btn)
	btn:Show()
	return true
end

local function refreshCraftWindowButtons()
	local shownBtn = nil
	for _, frameName in ipairs(CRAFT_FRAME_NAMES) do
		local frame = _G[frameName]
		local btn = state.craftWinBtns[frameName]
		local bookPageShown = (frameName == "ProfessionsFrame" and frame and frame.BookPage and isFrameVisible(frame.BookPage)) and true or false
		if frame and isFrameVisible(frame) and not bookPageShown and isCraftWindowEnchanting(frameName) then
			if not btn or (btn.GetParent and btn:GetParent() ~= frame) then
				if btn and btn.Hide then btn:Hide() end
				btn = createLauncherButton(frame, CRAFT_BTN_SIZE)
				state.craftWinBtns[frameName] = btn
			end
			local anchor = frame.MaximizeMinimize or frame.CloseButton or _G[frameName .. "CloseButton"]
			btn:ClearAllPoints()
			if anchor then
				btn:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
			else
				btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -4)
			end
			if btn.SetFrameStrata and frame.GetFrameStrata then
				local strata = frame:GetFrameStrata()
				if not hasSecret(strata) and type(strata) == "string" and strata ~= "" then
					btn:SetFrameStrata(strata)
				end
			end
			if btn.SetFrameLevel then
				local baseLvl = safeFrameLevel(frame)
				if anchor then
					baseLvl = math.max(baseLvl, safeFrameLevel(anchor))
				end
				btn:SetFrameLevel(baseLvl + 5)
			end
			paintLauncherButton(btn)
			btn:Show()
			shownBtn = btn
		else
			if btn and btn.Hide then
				btn:Hide()
			end
		end
	end
	if shownBtn then
		state.activeCraftWinBtn = shownBtn
	elseif state.activeCraftWinBtn and state.activeCraftWinBtn.Hide then
		state.activeCraftWinBtn:Hide()
	end
	return shownBtn ~= nil
end

local function hookGlobalOnce(fnName, callback)
	local cur = _G[fnName]
	if type(cur) ~= "function" then return end
	if hookedGlobals[fnName] == cur then return end
	if type(_G.hooksecurefunc) == "function" then
		_G.hooksecurefunc(fnName, callback)
		hookedGlobals[fnName] = _G[fnName]
	end
end

local function hookFrameOnce(frame, onShowFn, onHideFn)
	if not frame or hookedFrames[frame] or type(frame.HookScript) ~= "function" then return end
	hookedFrames[frame] = true
	if onShowFn then frame:HookScript("OnShow", onShowFn) end
	if onHideFn then frame:HookScript("OnHide", onHideFn) end
end

local function hookBookPageOnce(bookPage, onShowFn, onHideFn)
	if not bookPage then return end
	hookFrameOnce(bookPage, onShowFn, onHideFn)
end

local function hookEventRegistryOnce(eventName, callback)
	local reg = _G.EventRegistry
	if type(reg) ~= "table" or type(reg.RegisterCallback) ~= "function" then return end
	if registeredEventRegistry[reg] and registeredEventRegistry[reg][eventName] then return end
	local ok = pcall(reg.RegisterCallback, reg, eventName, callback, EVENT_REGISTRY_OWNER)
	if ok then
		registeredEventRegistry[reg] = registeredEventRegistry[reg] or {}
		registeredEventRegistry[reg][eventName] = true
	end
end

local function onBlizzProfessionUpdate()
	DisenchantHelper.RefreshProfessionButtons()
end

local function installBlizzardHooks()
	hookGlobalOnce("ProfessionsBookFrame_Update", onBlizzProfessionUpdate)
	hookGlobalOnce("SpellBook_UpdateProfessions", onBlizzProfessionUpdate)
	hookGlobalOnce("SpellBookFrame_Update", onBlizzProfessionUpdate)
	hookGlobalOnce("CraftFrame_Update", onBlizzProfessionUpdate)
	hookGlobalOnce("TradeSkillFrame_Update", onBlizzProfessionUpdate)

	hookEventRegistryOnce("ProfessionsBookFrame.Show", onBlizzProfessionUpdate)
	hookEventRegistryOnce("ProfessionsBookFrame.Hide", onBlizzProfessionUpdate)

	hookFrameOnce(_G.SpellBookProfessionFrame, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	hookFrameOnce(_G.ProfessionsBookFrame, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	hookFrameOnce(_G.SpellBookFrame, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	hookFrameOnce(_G.CraftFrame, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	hookFrameOnce(_G.TradeSkillFrame, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	hookFrameOnce(_G.ProfessionsFrame, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	if _G.ProfessionsFrame then
		hookBookPageOnce(_G.ProfessionsFrame.BookPage, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
		hookFrameOnce(_G.ProfessionsFrame.CraftingPage, onBlizzProfessionUpdate, onBlizzProfessionUpdate)
	end
end

function DisenchantHelper.RefreshProfessionButtons()
	installBlizzardHooks()
	if isInCombat() then
		state.pendingButtonsRefresh = true
		return false
	end
	state.pendingButtonsRefresh = false
	local profShown = refreshProfBookButton()
	local craftShown = refreshCraftWindowButtons()
	if state.frame and state.frame:IsShown() then
		local mode = (ns.Window and ns.Window.GetMode) and ns.Window.GetMode("disenchant_helper", "snap") or "snap"
		if mode ~= "free" and not (ns.Window and ns.Window.IsDragging and ns.Window.IsDragging(state.frame)) then
			applyWindowPosition(state.frame)
		else
			syncDockModeButton(state.frame)
		end
	end
	return profShown or craftShown
end

local function handleIntegrationEvent(_, event, arg1)
	if event == "ADDON_LOADED" then
		if (not hasSecret(arg1) and WATCHED_ADDONS[arg1])
			or (_G.ProfessionsFrame and not hookedFrames[_G.ProfessionsFrame])
			or (_G.ProfessionsFrame and _G.ProfessionsFrame.BookPage and not hookedFrames[_G.ProfessionsFrame.BookPage])
			or (_G.ProfessionsBookFrame and not hookedFrames[_G.ProfessionsBookFrame]) then
			DisenchantHelper.RefreshProfessionButtons()
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if state.pendingOpenAfterCombat and not isInCombat() then
			state.pendingOpenAfterCombat = false
			DisenchantHelper.Show()
		elseif state.frame and state.frame:IsShown() and not isInCombat() then
			state.castingNotice = nil
			syncButtonClickEdge(state.frame.deBtn)
			DisenchantHelper.ScanBags()
		end
		if state.pendingButtonsRefresh and not isInCombat() then
			state.pendingButtonsRefresh = false
			DisenchantHelper.RefreshProfessionButtons()
		end
		return
	end
	DisenchantHelper.RefreshProfessionButtons()
end

do
	local ev = CreateFrame("Frame")
	for _, evName in ipairs({
		"PLAYER_LOGIN",
		"PLAYER_ENTERING_WORLD",
		"ADDON_LOADED",
		"SPELLS_CHANGED",
		"SKILL_LINES_CHANGED",
		"LEARNED_SPELL_IN_TAB",
		"PLAYER_REGEN_ENABLED",
		"CRAFT_SHOW",
		"CRAFT_UPDATE",
		"CRAFT_CLOSE",
		"TRADE_SKILL_SHOW",
		"TRADE_SKILL_UPDATE",
		"TRADE_SKILL_CLOSE",
		"TRADE_SKILL_DATA_SOURCE_CHANGED",
	}) do
		pcall(ev.RegisterEvent, ev, evName)
	end
	ev:SetScript("OnEvent", handleIntegrationEvent)
	state.eventFrame = ev
end

function DisenchantHelper.GetActiveTarget()
	local cur = state.activeIndex and state.items[state.activeIndex] or nil
	if not cur then return nil end
	return cur.bag, cur.slot, cur.itemID, cur.link, state.arcaneSalvager == true
end

function DisenchantHelper.GetState()
	local selCount, totalCopper, unpricedCount = countSelected()
	local active = state.activeIndex and state.items[state.activeIndex] or nil
	local profBookBtn = state.profBookBtn
	local craftWinBtn = state.activeCraftWinBtn
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
		profBookBtn = profBookBtn,
		craftWinBtn = craftWinBtn,
		profBookShown = (profBookBtn ~= nil and profBookBtn:IsShown()) and true or false,
		craftWinShown = (craftWinBtn ~= nil and craftWinBtn:IsShown()) and true or false,
		pendingOpenAfterCombat = state.pendingOpenAfterCombat == true,
		pendingButtonsRefresh = state.pendingButtonsRefresh == true,
		eventFrame = state.eventFrame,
	}
end
