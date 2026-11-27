-- MerchantMaster UI_Console.lua
-- Unified Console & Admin Monitor page:
--   1. Overview            (RAM, SavedVariables, Live AH scans, Health, optional Snapshot cards)
--   2. Database            (WoW SavedVariables schema inspector + optional SQLite companion tables)
--   3. Perf & Debug        (Zero-overhead opt-in runtime profiler & privacy-safe Debug Bundle)
--   4. Snapshot Sync       (GitHub Auto-Sync & 3-way Price Refresh Mode)
--   5. Settings            (Synced /mm options, Leveling guide, tooltip settings)
--   6. Mail                (Saved mail recipients, mailbox quick-pick buttons & safety net)
--   7. Tooltip Setup       (Item tooltip sections, price format, modifier & live example preview)
--   8. Addon UI            (Theme/skin, table style & price format switcher with live preview)
--   9. Data & Maintenance  (Two-click cache/ledger cleanup with hover tooltips, CSV export, slash help)
-- Pure ASCII only (BAD_GLYPHS=0).

local ADDON, ns = ...
ns = ns or {}

if ns.UIConsole then
	return
end

local UI = {}
ns.UIConsole = UI

local floor, max, min = math.floor, math.max, math.min
local format, tostring, tonumber, type, pairs, ipairs = string.format, tostring, tonumber, type, pairs, ipairs

local SUB_TABS = {
	console_overview = true,
	console_database = true,
	console_perf = true,
	console_setup2 = true,
	console_settings = true,
	console_mail = true,
	console_tooltips = true,
	console_ui = true,
	console_data = true,
}

local FALLBACK_PALETTES = {
	dark = {
		mode = "dark",
		winBg = { 0.110, 0.110, 0.118, 0.99 },
		sidebarBg = { 0.125, 0.133, 0.160, 0.97 },
		toolbarBg = { 0.149, 0.149, 0.165, 0.95 },
		cardBg = { 0.173, 0.173, 0.180, 1.0 },
		cardAltBg = { 0.204, 0.204, 0.220, 1.0 },
		cardHover = { 0.224, 0.224, 0.239, 1.0 },
		navActiveBg = { 1.0, 1.0, 1.0, 0.13 },
		border = { 1.0, 1.0, 1.0, 0.12 },
		text = { 1, 1, 1, 1 },
		textSecondary = { 0.922, 0.922, 0.961, 0.62 },
		textMuted = { 0.682, 0.682, 0.698, 1.0 },
		textOnAccent = { 0, 0, 0, 1 },
		accentBlue = { 0, 0.569, 1.0, 1.0 },
		textBlue = { 0.361, 0.722, 1.0, 1.0 },
		accentGreen = { 0.188, 0.820, 0.345, 1.0 },
		accentOrange = { 1.0, 0.573, 0.188, 1.0 },
		accentRed = { 1.0, 0.380, 0.396, 1.0 },
		separator = { 0.329, 0.329, 0.345, 0.6 },
		hexText = "ffffff",
		hexSecondary = "ebebf5",
		hexMuted = "98989d",
		hexGreen = "30d158",
		hexBlue = "5ac8fa",
		hexWarning = "ff9230",
		hexDanger = "ff4245",
		hexGold = "ffd60a",
		hexSilver = "c7c7cc",
		hexCopper = "e08a5e",
	},
	light = {
		mode = "light",
		winBg = { 0.949, 0.949, 0.969, 0.99 },
		sidebarBg = { 0.935, 0.938, 0.956, 0.97 },
		toolbarBg = { 0.949, 0.949, 0.969, 0.96 },
		cardBg = { 1, 1, 1, 1 },
		cardAltBg = { 0.949, 0.949, 0.969, 1 },
		cardHover = { 0.898, 0.898, 0.918, 1 },
		navActiveBg = { 0, 0, 0, 0.10 },
		border = { 0, 0, 0, 0.10 },
		text = { 0, 0, 0, 1 },
		textSecondary = { 0.235, 0.235, 0.263, 0.76 },
		textMuted = { 0.369, 0.384, 0.416, 1.0 },
		textOnAccent = { 0, 0, 0, 1 },
		accentBlue = { 0, 0.533, 1.0, 1.0 },
		textBlue = { 0, 0.384, 0.8, 1 },
		accentGreen = { 0, 0.478, 0.169, 1 },
		accentOrange = { 0.702, 0.290, 0, 1 },
		accentRed = { 0.722, 0.078, 0.102, 1 },
		separator = { 0.235, 0.235, 0.263, 0.29 },
		hexText = "000000",
		hexSecondary = "3c3c43",
		hexMuted = "5e626a",
		hexGreen = "007a2b",
		hexBlue = "0062cc",
		hexWarning = "9e4b00",
		hexDanger = "b8141a",
		hexGold = "8a5a00",
		hexSilver = "5a606d",
		hexCopper = "9c4616",
	},
}

local state = {
	parent = nil,
	root = nil,
	built = false,
	themeHooked = false,
	activeSubTab = "console_overview",
	dirty = true,

	subTabBar = nil,
	perfPill = nil,
	refreshBtn = nil,

	overviewView = nil,
	databaseView = nil,
	perfView = nil,
	settingsView = nil,
	mailView = nil,
	tooltipsView = nil,
	uiView = nil,
	dataView = nil,

	styledCards = {},
	themedText = {},
	themedSeparators = {},

	dbScrollOffset = 0,
	dbSelectedId = nil,
	dbItems = {},

	bundleOpts = {
		includeSettings = true,
		includeDatabase = true,
		includePerf = true,
		includeLogs = true,
		redactNames = true,
	},
	uiPreview = {
		skin = nil,
		mode = nil,
		tableStyle = nil,
		priceMode = nil,
	},
	pruneDays = 30,
	armedAction = nil,
	actionStatus = "Ready.",
	actionStatusVariant = "muted",
	exportCsvText = "",

	tooltipSampleKey = "green_lens",

	settingsControls = {},
	mailControls = {},
	tooltipControls = {},
	uiControls = {},
}

---------------------------------------------------------------------------------------------------
-- Defensive & Theme Helpers
---------------------------------------------------------------------------------------------------

local function getCE()
	return type(ns.ConsoleEngine) == "table" and ns.ConsoleEngine or nil
end

local function hasSnapshotExt()
	local CE = getCE()
	if CE and type(CE.HasSnapshotExtension) == "function" and CE.HasSnapshotExtension() then
		return true
	end
	return (ns.app and ns.app.snapshotExtension ~= nil) and true or false
end

local function hasSnapshotsAny()
	if hasSnapshotExt() then return true end
	if type(ns.HasSnapshots) == "function" and ns.HasSnapshots() then
		return true
	end
	return false
end

local function hasMapPinsExt()
	local CE = getCE()
	if CE and type(CE.HasMapPinsExtension) == "function" and CE.HasMapPinsExtension() then
		return true
	end
	return (ns.app and ns.app.mapPinsProvider ~= nil) and true or false
end

local function getTheme()
	return type(ns.Theme) == "table" and ns.Theme or nil
end

local function getPal()
	local T = getTheme()
	local mode = (T and type(T.GetMode) == "function" and T.GetMode()) or "dark"
	if mode ~= "light" then mode = "dark" end
	local pal = (T and type(T.GetActivePalette) == "function" and T.GetActivePalette())
		or (T and T.PALETTES and T.PALETTES[mode])
		or FALLBACK_PALETTES[mode]
	return pal, mode
end

local function palHex(key, pal)
	local p = pal or getPal()
	if type(p) == "table" then
		local v = p[key]
		if type(v) == "string" and #v == 6 then return v end
		if type(p.hexText) == "string" and #p.hexText == 6 then return p.hexText end
	end
	return "ffffff"
end

local function colorHex(hexKey, text, pal)
	return "|cff" .. palHex(hexKey, pal) .. tostring(text or "") .. "|r"
end

local function setFsColor(fs, col)
	if not fs or type(col) ~= "table" then return end
	if type(fs.SetTextColor) == "function" then
		fs:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
	end
end

local function applyFont(fs, size, weight)
	if not fs then return end
	local T = getTheme()
	if T and type(T.ApplyFont) == "function" then
		T.ApplyFont(fs, size or 12, weight or "regular", "")
	elseif type(fs.SetFont) == "function" then
		fs:SetFont("Fonts\\ARIALN.TTF", size or 12, "")
	end
	if type(fs.SetShadowOffset) == "function" then fs:SetShadowOffset(0, 0) end
	if type(fs.SetShadowColor) == "function" then fs:SetShadowColor(0, 0, 0, 0) end
end

local function createSurfaceCard(parent, kind, fillKey)
	local f = CreateFrame("Frame", nil, parent)
	local T = getTheme()
	local card
	if T and type(T.NineApple) == "function" then
		card = T.NineApple(f, kind or "glass_r12", fillKey or "cardBg", false, { noSpecular = true })
	end
	local bgFallback = not card and f:CreateTexture(nil, "BACKGROUND") or nil
	if bgFallback then bgFallback:SetAllPoints(f) end
	local entry = {
		frame = f,
		card = card,
		bgFallback = bgFallback,
		fillKey = fillKey or "cardBg",
	}
	state.styledCards[#state.styledCards + 1] = entry
	return f, entry
end

local function paintSurfaceCard(entry, pal)
	if not entry then return end
	if entry.card and type(entry.card.UpdateTheme) == "function" then
		entry.card:UpdateTheme()
	elseif entry.bgFallback and entry.bgFallback.SetColorTexture then
		local col = pal[entry.fillKey] or pal.cardBg
		entry.bgFallback:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
	end
end

local function registerThemedFs(fs, colorKey)
	state.themedText[#state.themedText + 1] = { fs = fs, key = colorKey or "text" }
	setFsColor(fs, getPal()[colorKey or "text"] or getPal().text)
	return fs
end

local function createSeparator(parent)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetHeight(1)
	local sep = getPal().separator or { 0.4, 0.4, 0.4, 0.4 }
	if tex.SetColorTexture then
		tex:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4)
	end
	state.themedSeparators[#state.themedSeparators + 1] = tex
	return tex
end

local function makeFs(parent, size, weight, colorKey, justifyH)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	applyFont(fs, size or 11, weight or "regular")
	if fs.SetJustifyH then fs:SetJustifyH(justifyH or "LEFT") end
	registerThemedFs(fs, colorKey or "text")
	return fs
end

local function createButton(parent, label, w, h, opts)
	local T = getTheme()
	if T and type(T.CreatePlateButton) == "function" then
		return T.CreatePlateButton(parent, label, w, h, opts)
	end
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 100, h or 24)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetText(label or "")
	b.fs = fs
	function b:SetVariant() end
	function b:SetActive() end
	return b
end

local function setButtonLabel(btn, text)
	if not btn then return end
	if btn.fs and type(btn.fs.SetText) == "function" then
		btn.fs:SetText(text or "")
	elseif type(btn.SetText) == "function" then
		btn:SetText(text or "")
	end
end

local function createCheck(parent, label, size, onClick)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(20, 20)
	local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
	lbl:SetText(label or "")
	lbl:SetJustifyH("LEFT")
	if lbl.SetWordWrap then lbl:SetWordWrap(false) end
	applyFont(lbl, size or 11, "regular")
	registerThemedFs(lbl, "text")
	cb.label = lbl
	local T = getTheme()
	if T and type(T.SkinCheckButton) == "function" then
		T.SkinCheckButton(cb)
	end
	if onClick then
		cb:SetScript("OnClick", function(self)
			local checked = self.GetChecked and (self:GetChecked() == true) or false
			onClick(self, checked)
		end)
	end
	return cb
end

local function createSingleLineBox(parent, w, h, onChanged)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(w or 180, h or 22)
	if box.SetAutoFocus then box:SetAutoFocus(false) end
	local T = getTheme()
	if T and type(T.StyleEditBox) == "function" then
		T.StyleEditBox(box, { pill = false, border = true, fontSize = 11, leftInset = 6, rightInset = 6 })
	else
		applyFont(box, 11, "regular")
		registerThemedFs(box, "text")
	end
	if box.SetScript then
		box:SetScript("OnEscapePressed", function(self)
			if self.ClearFocus then self:ClearFocus() end
		end)
		box:SetScript("OnEnterPressed", function(self)
			if self.ClearFocus then self:ClearFocus() end
			if onChanged then onChanged(self) end
		end)
		box:SetScript("OnTextChanged", function(self, isUser)
			if isUser and onChanged then onChanged(self) end
		end)
	end
	return box
end

local function createMultiLineArea(parent)
	local card = createSurfaceCard(parent, "glass_r8", "cardAltBg")
	local scroll = CreateFrame("ScrollFrame", nil, card)
	scroll:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 6)

	local boxParent = (scroll.SetScrollChild ~= nil) and scroll or card
	local box = CreateFrame("EditBox", nil, boxParent)
	if box.SetMultiLine then box:SetMultiLine(true) end
	if box.SetAutoFocus then box:SetAutoFocus(false) end
	if box.SetJustifyH then box:SetJustifyH("LEFT") end
	applyFont(box, 11, "regular")
	registerThemedFs(box, "text")

	if scroll.SetScrollChild then
		box:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
		box:SetWidth(420)
		box:SetHeight(600)
		scroll:SetScrollChild(box)
		scroll:SetScript("OnSizeChanged", function(self, w)
			if w and w > 40 and box.SetWidth then
				box:SetWidth(floor(w - 6))
			end
		end)
		scroll:SetScript("OnMouseDown", function()
			if box.SetFocus then box:SetFocus() end
		end)
	else
		box:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
		box:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 6)
	end

	local sb = CreateFrame("Slider", nil, card)
	sb:SetWidth(6)
	sb:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -6)
	sb:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4, 6)
	if sb.SetOrientation then sb:SetOrientation("VERTICAL") end
	if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 0) end
	if sb.SetValueStep then sb:SetValueStep(18) end
	if sb.SetValue then sb:SetValue(0) end
	local thumb = sb:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(4, 28)
	thumb:SetColorTexture(1, 1, 1, 0.30)
	if sb.SetThumbTexture then sb:SetThumbTexture(thumb) end
	local T = getTheme()
	if T and type(T.SlimScrollBar) == "function" then
		T.SlimScrollBar(sb)
	end
	if sb.SetScript and scroll.SetVerticalScroll then
		sb:SetScript("OnValueChanged", function(_, val)
			if scroll.SetVerticalScroll then scroll:SetVerticalScroll(val or 0) end
		end)
	end
	if card.EnableMouseWheel then card:EnableMouseWheel(true) end
	card:SetScript("OnMouseWheel", function(_, delta)
		if scroll.GetVerticalScrollRange and scroll.SetVerticalScroll and scroll.GetVerticalScroll then
			local rng = scroll:GetVerticalScrollRange() or 0
			local cur = scroll:GetVerticalScroll() or 0
			local nextV = max(0, min(rng, cur - delta * 36))
			scroll:SetVerticalScroll(nextV)
			if sb.SetMinMaxValues then sb:SetMinMaxValues(0, rng) end
			if sb.SetValue then sb:SetValue(nextV) end
		end
	end)

	box:SetScript("OnEscapePressed", function(self)
		if self.ClearFocus then self:ClearFocus() end
	end)
	box:SetScript("OnTextChanged", function(self)
		local txt = (self.GetText and self:GetText()) or ""
		local lineCount = 1
		for _ in txt:gmatch("\n") do lineCount = lineCount + 1 end
		local needH = max(180, lineCount * 14 + 24)
		if self.SetHeight then self:SetHeight(needH) end
		if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
		if scroll.GetVerticalScrollRange and sb.SetMinMaxValues then
			local rng = scroll:GetVerticalScrollRange() or 0
			sb:SetMinMaxValues(0, rng)
		end
	end)

	return card, box, scroll, sb
end

local function selectAllInBox(box)
	if not box then return end
	if box.SetFocus then box:SetFocus() end
	if box.HighlightText then box:HighlightText() end
end

local function setStatusMsg(msg, variant)
	state.actionStatus = tostring(msg or "")
	state.actionStatusVariant = variant or "muted"
	local fs = state.dataView and state.dataView.actionStatusFs
	if fs then
		local pal = getPal()
		local hk = (state.actionStatusVariant == "danger") and "hexDanger"
			or ((state.actionStatusVariant == "warning") and "hexWarning"
			or ((state.actionStatusVariant == "green") and "hexGreen"
			or ((state.actionStatusVariant == "blue") and "hexBlue" or "hexSecondary")))
		fs:SetText(colorHex(hk, state.actionStatus, pal))
	end
end

local function attachTooltip(widget, title, lines, anchor)
	if not widget or type(widget.SetScript) ~= "function" then return end
	local onEnter = function(self)
		local gt = _G.GameTooltip
		if not gt then return end
		local tTitle = type(title) == "function" and title() or title
		local tLines = type(lines) == "function" and lines() or lines
		gt:SetOwner(self, anchor or "ANCHOR_RIGHT")
		gt:AddLine(tTitle or "", 1, 0.82, 0)
		for _, ln in ipairs(tLines or {}) do
			if type(ln) == "table" then
				gt:AddLine(ln[1] or "", ln[2] or 0.9, ln[3] or 0.9, ln[4] or 0.92, true)
			else
				gt:AddLine(tostring(ln or ""), 0.9, 0.92, 0.96, true)
			end
		end
		gt:Show()
	end
	local onLeave = function()
		if _G.GameTooltip_Hide then
			_G.GameTooltip_Hide()
		elseif _G.GameTooltip and _G.GameTooltip.Hide then
			_G.GameTooltip:Hide()
		end
	end
	if widget.HookScript then
		widget:HookScript("OnEnter", onEnter)
		widget:HookScript("OnLeave", onLeave)
	else
		widget:SetScript("OnEnter", onEnter)
		widget:SetScript("OnLeave", onLeave)
	end
end

---------------------------------------------------------------------------------------------------
-- Sub-View 1: Overview (console_overview)
---------------------------------------------------------------------------------------------------

local function buildOverviewView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local ov = {
		frame = frame,
		kpis = {},
		svRows = {},
	}

	local kpiBar = CreateFrame("Frame", nil, frame)
	kpiBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	kpiBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	kpiBar:SetHeight(104)
	ov.kpiBar = kpiBar

	local T = getTheme()
	local kpiSpecs = {
		{
			title = "Addon Memory (RAM)",
			icon = "bars",
			tipTitle = "Addon Memory (RAM)",
			tipLines = function()
				if hasSnapshotExt() then
					return {
						"Live Lua memory currently held in WoW RAM across MerchantMaster and loaded companions.",
						"Click Refresh to sample updated memory usage.",
					}
				end
				return {
					"Live Lua memory currently held in WoW RAM by MerchantMaster.",
					"Click Refresh to sample updated memory usage.",
				}
			end,
		},
		{
			title = "Snapshot Storage (Disk)",
			icon = "doc",
			tipTitle = "Snapshot Storage (Disk) vs Export Cap",
			tipLines = function()
				return {
					"Top number: total storage used on disk by the local snapshot SQLite database, WAL/SHM journal, and sync log.",
					"Bottom Lua Export: size of the companion snapshot export loaded into WoW RAM vs its safety cap.",
				}
			end,
		},
		{
			title = "Live AH Scans",
			icon = "refresh",
			tipTitle = function()
				return hasSnapshotExt() and "AH Refreshes (Blizzard API / Manual)" or "In-Game Live AH Scans"
			end,
			tipLines = function()
				if hasSnapshotExt() then
					return {
						"API Runs: background polls by the snapshot companion (304 = Blizzard AH unchanged since last poll).",
						"Manual: full, partial, single-item, and deep-lot AH scans run in-game on this account.",
					}
				end
				return {
					"Tracks full, partial, single-item, and deep-lot Auction House scans run in-game on this account.",
					"Run two full AH scans spaced 15+ minutes apart to build local velocity estimates.",
				}
			end,
		},
		{
			title = "Health & Profiler",
			icon = "shield",
			tipTitle = "Addon Health & Runtime Profiler",
			tipLines = function()
				if hasSnapshotExt() then
					return {
						"Shows combined Snapshot Runner + Analytics Ledger errors and whether the opt-in runtime profiler is enabled.",
						"Console stays static during crafts and bag changes -- click Refresh to sample live numbers.",
					}
				end
				return {
					"Shows Analytics Ledger capture errors and whether the opt-in runtime profiler is enabled.",
					"Console stays static during crafts and bag changes -- click Refresh to sample live numbers.",
				}
			end,
		},
	}
	for i, spec in ipairs(kpiSpecs) do
		local c
		if T and type(T.CreateKpiCard) == "function" then
			c = T.CreateKpiCard(kpiBar, {
				height = 104,
				icon = spec.icon,
				uppercase = false,
				title = spec.title,
				value = "--",
				sub = "--",
			})
			c.frame:SetParent(kpiBar)
			if c.valueFs then applyFont(c.valueFs, 20, "semibold") end
			if c.subFs then applyFont(c.subFs, 11, "regular") end
		else
			local f = createSurfaceCard(kpiBar, "glass_r16", "cardBg")
			f:SetHeight(104)
			c = { frame = f }
			function c:SetData() end
		end
		if c.frame then
			if c.frame.EnableMouse then c.frame:EnableMouse(true) end
			attachTooltip(c.frame, spec.tipTitle, spec.tipLines, "ANCHOR_BOTTOM")
		end
		ov.kpis[i] = c
	end

	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -114)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(500)
	ov.leftCard = leftCard

	local leftTitle = makeFs(leftCard, 13, "semibold", "text")
	leftTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -12)
	leftTitle:SetText("SavedVariables & Static Catalog")

	local leftTotalFs = makeFs(leftCard, 11, "semibold", "textBlue", "RIGHT")
	leftTotalFs:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -13)
	leftTotalFs:SetText("--")
	ov.leftTotalFs = leftTotalFs

	local leftSep = createSeparator(leftCard)
	leftSep:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -34)
	leftSep:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -12, -34)

	for i = 1, 14 do
		local r = CreateFrame("Frame", nil, leftCard)
		r:SetHeight(19)
		r:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -(40 + (i - 1) * 19))
		r:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -(40 + (i - 1) * 19))
		local nameFs = makeFs(r, 11, "regular", "text")
		nameFs:SetPoint("LEFT", r, "LEFT", 0, 0)
		nameFs:SetPoint("RIGHT", r, "RIGHT", -150, 0)
		if nameFs.SetWordWrap then nameFs:SetWordWrap(false) end
		local countFs = makeFs(r, 11, "regular", "textSecondary", "RIGHT")
		countFs:SetPoint("RIGHT", r, "RIGHT", -76, 0)
		countFs:SetWidth(70)
		local sizeFs = makeFs(r, 11, "semibold", "text", "RIGHT")
		sizeFs:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		sizeFs:SetWidth(70)
		ov.svRows[i] = { frame = r, nameFs = nameFs, countFs = countFs, sizeFs = sizeFs }
	end

	local catSep = createSeparator(leftCard)
	catSep:SetPoint("TOPLEFT", leftCard, "BOTTOMLEFT", 12, 58)
	catSep:SetPoint("TOPRIGHT", leftCard, "BOTTOMRIGHT", -12, 58)

	local catHdr = makeFs(leftCard, 11, "semibold", "textSecondary")
	catHdr:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 14, 38)
	catHdr:SetText("Static Addon Catalog")

	local catBody = makeFs(leftCard, 11, "regular", "text")
	catBody:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 14, 14)
	catBody:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -14, 14)
	if catBody.SetWordWrap then catBody:SetWordWrap(true) end
	ov.catBody = catBody

	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	ov.rightCard = rightCard

	local rightTitle = makeFs(rightCard, 13, "semibold", "text")
	rightTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -12)
	rightTitle:SetText("In-Game Live AH Scans & Economy State")
	ov.rightTitle = rightTitle

	local rightSep = createSeparator(rightCard)
	rightSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -34)
	rightSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -34)

	local snapDetailFs = makeFs(rightCard, 11, "regular", "text")
	snapDetailFs:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -44)
	snapDetailFs:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -44)
	snapDetailFs:SetHeight(185)
	if snapDetailFs.SetJustifyV then snapDetailFs:SetJustifyV("TOP") end
	if snapDetailFs.SetWordWrap then snapDetailFs:SetWordWrap(true) end
	ov.snapDetailFs = snapDetailFs

	local midSep = createSeparator(rightCard)
	midSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -236)
	midSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -236)
	ov.midSep = midSep

	local manTitle = makeFs(rightCard, 13, "semibold", "text")
	manTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -246)
	manTitle:SetText("In-Game Manual Scans & Economy State")
	ov.manTitle = manTitle

	local manDetailFs = makeFs(rightCard, 11, "regular", "text")
	manDetailFs:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -270)
	manDetailFs:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)
	if manDetailFs.SetJustifyV then manDetailFs:SetJustifyV("TOP") end
	if manDetailFs.SetWordWrap then manDetailFs:SetWordWrap(true) end
	ov.manDetailFs = manDetailFs

	function ov.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		local gap = 10
		local showSnap = hasSnapshotExt()
		local visibleKpis = {}
		for i, c in ipairs(ov.kpis) do
			if c and c.frame then
				if i == 2 and not showSnap then
					c.frame:Hide()
				else
					c.frame:Show()
					visibleKpis[#visibleKpis + 1] = c
				end
			end
		end
		local count = max(1, #visibleKpis)
		local kw = max(140, floor((w - gap * (count - 1)) / count))
		for idx, c in ipairs(visibleKpis) do
			c.frame:ClearAllPoints()
			c.frame:SetPoint("TOPLEFT", kpiBar, "TOPLEFT", (idx - 1) * (kw + gap), 0)
			c.frame:SetWidth(kw)
		end
		leftCard:SetWidth(max(340, floor((w - gap) * 0.50)))

		ov.manDetailFs:ClearAllPoints()
		if showSnap then
			ov.rightTitle:SetText("Snapshot Sync & Manual AH Refreshes")
			ov.snapDetailFs:Show()
			ov.midSep:Show()
			ov.manTitle:Show()
			ov.manDetailFs:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -270)
			ov.manDetailFs:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)
		else
			ov.rightTitle:SetText("In-Game Live AH Scans & Economy State")
			ov.snapDetailFs:Hide()
			ov.midSep:Hide()
			ov.manTitle:Hide()
			ov.manDetailFs:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -44)
			ov.manDetailFs:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)
		end
	end

	function ov.refresh()
		local CE = getCE()
		if not CE then return end
		local showSnap = hasSnapshotExt()
		local showMapPins = hasMapPinsExt()
		local storage = CE.CollectStorageSnapshot()
		local ref = CE.GetRefreshSummary()
		local perf = CE.GetPerfSnapshot()
		local sys = showSnap and storage.sysMeta or nil

		ov.layout()

		-- KPI 1: RAM
		local ramParts = { "Core " .. CE.FormatBytes((storage.ram.merchantMasterKB or 0) * 1024) }
		if showSnap or (storage.ram.snapshotsKB or 0) > 0 then
			ramParts[#ramParts + 1] = "Snap " .. CE.FormatBytes((storage.ram.snapshotsKB or 0) * 1024)
		end
		if showMapPins or (storage.ram.mapPinsKB or 0) > 0 then
			ramParts[#ramParts + 1] = "Pins " .. CE.FormatBytes((storage.ram.mapPinsKB or 0) * 1024)
		end
		ov.kpis[1]:SetData({
			title = "Addon Memory (RAM)",
			value = format("%.1f MB", (storage.ram.totalKB or 0) / 1024),
			sub = table.concat(ramParts, " | "),
		})

		-- KPI 2: Disk & Snapshots (only visible when snapshot companion registered)
		if showSnap then
			if sys then
				local sqliteFiles = (sys.dbBytes or 0) + (sys.walBytes or 0) + (sys.shmBytes or 0)
				local diskTotal = max(sqliteFiles, sys.localDataDirBytes or 0)
				ov.kpis[2]:SetData({
					title = "Snapshot Storage (Disk)",
					value = CE.FormatBytes(diskTotal),
					sub = format("Lua Export: %s / %s%s",
						CE.FormatBytes(sys.exportBytes or 0),
						CE.FormatBytes(sys.exportCapBytes or 0),
						sys.truncated and " (TRUNC)" or ""),
				})
			else
				ov.kpis[2]:SetData({
					title = "Snapshot Storage (Disk)",
					value = CE.FormatBytes(storage.totalSavedBytes or 0),
					sub = "SYSTEM export pending (run Setup/Export)",
				})
			end
		end

		-- KPI 3: AH Refreshes
		local totalManual = (ref.manualFullScans or 0) + (ref.manualPartialScans or 0)
			+ (ref.manualSingleRefreshes or 0) + (ref.manualDeepLotScans or 0)
		if showSnap then
			local apiRuns = sys and (sys.totalRuns or 0) or 0
			local api304 = sys and (sys.log304 or 0) or 0
			ov.kpis[3]:SetData({
				title = "AH Refreshes (API / Manual)",
				value = format("%s / %s", CE.FormatInt(apiRuns), CE.FormatInt(totalManual)),
				sub = format("API 304: %d | Full: %d | Single: %d | Deep: %d",
					api304, ref.manualFullScans or 0, ref.manualSingleRefreshes or 0, ref.manualDeepLotScans or 0),
			})
		else
			ov.kpis[3]:SetData({
				title = "Live AH Scans",
				value = CE.FormatInt(totalManual),
				sub = format("Full: %d | Partial: %d | Single: %d | Deep: %d",
					ref.manualFullScans or 0, ref.manualPartialScans or 0,
					ref.manualSingleRefreshes or 0, ref.manualDeepLotScans or 0),
			})
		end

		-- KPI 4: Health & Profiler
		local errTotal = (showSnap and sys) and ((sys.errRuns or 0) + (sys.logErrors or 0)) or 0
		local ldb = type(_G.MerchantMasterLedgerDB) == "table" and _G.MerchantMasterLedgerDB or nil
		local statsErr = ldb and type(ldb.stats) == "table" and type(ldb.stats.errors) == "table" and ldb.stats.errors or nil
		local txErr = 0
		if statsErr then
			for _, v in pairs(statsErr) do txErr = txErr + (tonumber(v) or 0) end
		end
		local totalErr = errTotal + txErr
		ov.kpis[4]:SetData({
			title = "Health & Profiler",
			value = totalErr == 0 and "Healthy" or format("%d Errs", totalErr),
			tag = perf.enabled and "Prof ON" or "Prof OFF",
			tagVariant = perf.enabled and "orange" or "neutral",
			sub = format("Runtime: %s | LedgerErr: %d",
				perf.enabled and "ON" or "OFF",
				txErr),
		})

		-- SavedVariables breakdown rows
		ov.leftTotalFs:SetText("Est Total: " .. CE.FormatBytes(storage.totalSavedBytes or 0))
		for i = 1, #ov.svRows do
			local row = ov.svRows[i]
			local item = storage.savedTables[i]
			if item then
				row.frame:Show()
				row.nameFs:SetText(format("%s (%s)", item.label, item.store .. "." .. item.key))
				row.countFs:SetText(CE.FormatInt(item.rows or 0) .. " rows")
				row.sizeFs:SetText(CE.FormatBytes(item.estBytes or 0))
			else
				row.frame:Hide()
			end
		end

		local sc = storage.staticCatalog
		if showMapPins and sc.npcPins ~= nil then
			ov.catBody:SetText(format(
				"Items: %s  |  Recipes: %s  |  Writs: %s  |  Crates: %s  |  NPC Pins: %s",
				CE.FormatInt(sc.items), CE.FormatInt(sc.recipes), CE.FormatInt(sc.writs),
				CE.FormatInt(sc.crates), CE.FormatInt(sc.npcPins)))
		else
			ov.catBody:SetText(format(
				"Items: %s  |  Recipes: %s  |  Writs: %s  |  Crates: %s",
				CE.FormatInt(sc.items), CE.FormatInt(sc.recipes), CE.FormatInt(sc.writs),
				CE.FormatInt(sc.crates)))
		end

		ov._lastRef = ref
		ov._lastSys = sys
		ov.retheme()

		-- Manual AH scan summary
		local mLines = {}
		if not showSnap then
			local srcLabel = (ns.CurrentSourceInfo and ns.CurrentSourceInfo().label) or "Live AH"
			mLines[#mLines + 1] = format("Active Economy: %s   |   Price Source: %s",
				tostring(ref.activeEcon or "Normal-Horde"), tostring(srcLabel))
			mLines[#mLines + 1] = ""
		end
		mLines[#mLines + 1] = format("Full AH Scans: %d   |   Partial / Cancelled Scans: %d",
			ref.manualFullScans or 0, ref.manualPartialScans or 0)
		mLines[#mLines + 1] = format("Single-Item Refreshes: %d   |   Deep Order-Book Lot Scans: %d",
			ref.manualSingleRefreshes or 0, ref.manualDeepLotScans or 0)
		mLines[#mLines + 1] = format("Last Full AH Scan: %s (%s) -- %s items in %.1fs",
			CE.FormatTimestamp(ref.lastFullScanAt), CE.FormatAge(ref.lastFullScanAt),
			CE.FormatInt(ref.lastFullScanItems or 0), ref.lastFullScanSec or 0)
		mLines[#mLines + 1] = format("Last Partial Scan: %s   |   Last Single Refresh: %s",
			CE.FormatAge(ref.lastPartialAt), CE.FormatAge(ref.lastSingleAt))
		mLines[#mLines + 1] = format("Last Deep Lot Scan: %s   |   SavedVariables Root Total: %s",
			CE.FormatAge(ref.lastDeepLotAt), CE.FormatBytes(storage.totalSavedBytes or 0))
		ov.manDetailFs:SetText(table.concat(mLines, "\n"))
	end

	function ov.retheme()
		local CE = getCE()
		local ref = ov._lastRef
		local sys = ov._lastSys
		if not (CE and ref) then return end
		if not hasSnapshotExt() then
			ov.snapDetailFs:SetText("")
			return
		end
		local pal = getPal()
		local sLines = {}
		local sm = ref.snapMeta
		if sm then
			sLines[#sLines + 1] = format("Active Economy: %s  |  Source: %s",
				colorHex("hexBlue", ref.activeEcon, pal), tostring(sm.source or "?"))
			sLines[#sLines + 1] = format("Snapshot Updated: %s (%s)",
				CE.FormatTimestamp(sm.updatedAt), CE.FormatAge(sm.updatedAt))
			sLines[#sLines + 1] = format("Catalog Coverage: %s items | %s heatmaps | %s depth | %s velocity (%dh)",
				CE.FormatInt(sm.itemCount or 0), CE.FormatInt(sm.heatmapCount or 0),
				CE.FormatInt(sm.depthCount or 0), CE.FormatInt(sm.velocityCount or 0),
				tonumber(sm.velocityObsHours) or 0)
		else
			sLines[#sLines + 1] = "Active Economy: " .. colorHex("hexWarning", ref.activeEcon .. " (No snapshot loaded)", pal)
		end
		sLines[#sLines + 1] = ""
		if sys then
			sLines[#sLines + 1] = format("Background Runner Task: %s (enabled=%s, every %dm, retain %dd)",
				tostring(sys.taskStatus), tostring(sys.taskEnabled), sys.intervalMin or 15, sys.retentionDays or 30)
			sLines[#sLines + 1] = format("Region: %s  |  API Credentials: %s  |  Houses: %s",
				tostring(sys.region),
				sys.credsSet and colorHex("hexGreen", "SET", pal) or colorHex("hexWarning", "MISSING", pal),
				tostring(sys.houseMap or ""))
			sLines[#sLines + 1] = format("SQLite Sync Runs: %d total (%d Blizz, %d Errors)",
				sys.totalRuns or 0, sys.blizzRuns or 0, sys.errRuns or 0)
			sLines[#sLines + 1] = format("Sync Log: %s (%d polls, %d 304 No-Change, %d exports, %d log errors)",
				CE.FormatBytes(sys.logBytes or 0), sys.logPolls or 0, sys.log304 or 0,
				sys.logExports or 0, sys.logErrors or 0)
			if sys.lastError and sys.lastError ~= "" then
				sLines[#sLines + 1] = colorHex("hexDanger", "Last Runner Error: " .. sys.lastError, pal)
			end
		else
			sLines[#sLines + 1] = colorHex("hexMuted", "SYSTEM telemetry unavailable from snapshot companion. Open Snapshot Settings tab or run export.", pal)
		end
		ov.snapDetailFs:SetText(table.concat(sLines, "\n"))
	end

	return ov
end

---------------------------------------------------------------------------------------------------
-- Sub-View 2: Database & Storage Inspector (console_database)
---------------------------------------------------------------------------------------------------

local DB_VISIBLE_ROWS = 15

local function buildDatabaseView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local dv = {
		frame = frame,
		rows = {},
	}

	local T = getTheme()

	-- Dedicated Snapshot Storage Card (Left, 50% width)
	local snapStorageCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	snapStorageCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	snapStorageCard:SetHeight(118)
	snapStorageCard:SetWidth(460)
	dv.snapStorageCard = snapStorageCard

	local snapTitle = makeFs(snapStorageCard, 12, "semibold", "text")
	snapTitle:SetPoint("TOPLEFT", snapStorageCard, "TOPLEFT", 14, -10)
	snapTitle:SetText("AH Snapshot Storage (On Disk)")
	dv.snapTitle = snapTitle

	if T and type(T.CreateBadgePill) == "function" then
		local pill = T.CreateBadgePill(snapStorageCard, "Not Installed", "neutral", { height = 20, fontSize = 10 })
		pill.frame:SetPoint("TOPRIGHT", snapStorageCard, "TOPRIGHT", -12, -8)
		dv.snapBadge = pill
	end

	local snapHeadline = makeFs(snapStorageCard, 13, "semibold", "textBlue")
	snapHeadline:SetPoint("TOPLEFT", snapStorageCard, "TOPLEFT", 14, -30)
	snapHeadline:SetPoint("TOPRIGHT", snapStorageCard, "TOPRIGHT", -14, -30)
	if snapHeadline.SetWordWrap then snapHeadline:SetWordWrap(false) end
	snapHeadline:SetText("External Disk DB: Not Installed (0 B)")
	dv.snapHeadline = snapHeadline

	local snapBody = makeFs(snapStorageCard, 11, "regular", "textSecondary")
	snapBody:SetPoint("TOPLEFT", snapStorageCard, "TOPLEFT", 14, -50)
	snapBody:SetPoint("BOTTOMRIGHT", snapStorageCard, "BOTTOMRIGHT", -14, 10)
	if snapBody.SetJustifyV then snapBody:SetJustifyV("TOP") end
	if snapBody.SetWordWrap then snapBody:SetWordWrap(true) end
	dv.snapBody = snapBody

	-- WoW SavedVariables & Combined Storage Card (Right, 50% width)
	local svStorageCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	svStorageCard:SetPoint("TOPLEFT", snapStorageCard, "TOPRIGHT", 10, 0)
	svStorageCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	svStorageCard:SetHeight(118)
	dv.svStorageCard = svStorageCard
	dv.summaryCard = svStorageCard

	local sumTitle = makeFs(svStorageCard, 12, "semibold", "text")
	sumTitle:SetPoint("TOPLEFT", svStorageCard, "TOPLEFT", 14, -10)
	sumTitle:SetText("WoW SavedVariables & Combined Storage")
	dv.sumTitle = sumTitle

	local svHeadline = makeFs(svStorageCard, 13, "semibold", "text")
	svHeadline:SetPoint("TOPLEFT", svStorageCard, "TOPLEFT", 14, -30)
	svHeadline:SetPoint("TOPRIGHT", svStorageCard, "TOPRIGHT", -14, -30)
	if svHeadline.SetWordWrap then svHeadline:SetWordWrap(false) end
	svHeadline:SetText("WoW SavedVariables Est: 0 B")
	dv.svHeadline = svHeadline

	local sumBody = makeFs(svStorageCard, 11, "regular", "textSecondary")
	sumBody:SetPoint("TOPLEFT", svStorageCard, "TOPLEFT", 14, -50)
	sumBody:SetPoint("BOTTOMRIGHT", svStorageCard, "BOTTOMRIGHT", -14, 10)
	if sumBody.SetJustifyV then sumBody:SetJustifyV("TOP") end
	if sumBody.SetWordWrap then sumBody:SetWordWrap(true) end
	dv.sumBody = sumBody

	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -126)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(460)
	dv.leftCard = leftCard

	local listHdr = makeFs(leftCard, 12, "semibold", "text")
	listHdr:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -10)
	listHdr:SetText("SavedVariables Tables -- Click to inspect")
	dv.listHdr = listHdr

	local pageInfoFs = makeFs(leftCard, 11, "regular", "textSecondary", "RIGHT")
	pageInfoFs:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -10)
	dv.pageInfoFs = pageInfoFs

	local lSep = createSeparator(leftCard)
	lSep:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 10, -30)
	lSep:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -10, -30)

	local sb = CreateFrame("Slider", nil, leftCard)
	sb:SetWidth(6)
	sb:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -4, -36)
	sb:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -4, 34)
	if sb.SetOrientation then sb:SetOrientation("VERTICAL") end
	if sb.SetMinMaxValues then sb:SetMinMaxValues(0, 0) end
	if sb.SetValueStep then sb:SetValueStep(1) end
	if sb.SetValue then sb:SetValue(0) end
	local thumb = sb:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(4, 32)
	thumb:SetColorTexture(1, 1, 1, 0.30)
	if sb.SetThumbTexture then sb:SetThumbTexture(thumb) end
	if T and type(T.SlimScrollBar) == "function" then T.SlimScrollBar(sb) end
	dv.scrollBar = sb

	for i = 1, DB_VISIBLE_ROWS do
		local r = CreateFrame("Button", nil, leftCard)
		r:SetHeight(22)
		r:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 10, -(36 + (i - 1) * 22))
		r:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -(36 + (i - 1) * 22))
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(r)
		bg:SetColorTexture(0, 0, 0, 0)
		r.bg = bg

		local srcFs = makeFs(r, 10, "semibold", "textBlue")
		srcFs:SetPoint("LEFT", r, "LEFT", 6, 0)
		srcFs:SetWidth(94)
		if srcFs.SetWordWrap then srcFs:SetWordWrap(false) end

		local nameFs = makeFs(r, 11, "regular", "text")
		nameFs:SetPoint("LEFT", srcFs, "RIGHT", 6, 0)
		nameFs:SetPoint("RIGHT", r, "RIGHT", -125, 0)
		if nameFs.SetWordWrap then nameFs:SetWordWrap(false) end

		local metaFs = makeFs(r, 11, "regular", "textSecondary", "RIGHT")
		metaFs:SetPoint("RIGHT", r, "RIGHT", -6, 0)
		metaFs:SetWidth(116)

		r.srcFs, r.nameFs, r.metaFs = srcFs, nameFs, metaFs
		r:SetScript("OnClick", function(self)
			if self._entry then
				state.dbSelectedId = self._entry.id
				dv.renderRows()
				dv.renderDetail()
			end
		end)
		dv.rows[i] = r
	end

	if leftCard.EnableMouseWheel then leftCard:EnableMouseWheel(true) end
	leftCard:SetScript("OnMouseWheel", function(_, delta)
		local maxOff = max(0, #state.dbItems - DB_VISIBLE_ROWS)
		state.dbScrollOffset = max(0, min(maxOff, state.dbScrollOffset - (delta > 0 and 2 or -2)))
		if sb.SetValue then sb:SetValue(state.dbScrollOffset) end
		dv.renderRows()
	end)
	if sb.SetScript then
		sb:SetScript("OnValueChanged", function(_, val)
			state.dbScrollOffset = floor((val or 0) + 0.5)
			dv.renderRows()
		end)
	end

	local prevBtn = createButton(leftCard, "Prev", 74, 22, { variant = "secondary", fontSize = 11 })
	prevBtn:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 12, 8)
	prevBtn:SetScript("OnClick", function()
		state.dbScrollOffset = max(0, state.dbScrollOffset - 6)
		if sb.SetValue then sb:SetValue(state.dbScrollOffset) end
		dv.renderRows()
	end)

	local nextBtn = createButton(leftCard, "Next", 74, 22, { variant = "secondary", fontSize = 11 })
	nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
	nextBtn:SetScript("OnClick", function()
		local maxOff = max(0, #state.dbItems - DB_VISIBLE_ROWS)
		state.dbScrollOffset = min(maxOff, state.dbScrollOffset + 6)
		if sb.SetValue then sb:SetValue(state.dbScrollOffset) end
		dv.renderRows()
	end)

	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	dv.rightCard = rightCard

	local detTitle = makeFs(rightCard, 13, "semibold", "text")
	detTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -12)
	detTitle:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -12)
	detTitle:SetText("Field & Schema Inspector")
	dv.detTitle = detTitle

	local detSep = createSeparator(rightCard)
	detSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -34)
	detSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -34)

	local detMeta = makeFs(rightCard, 11, "regular", "textSecondary")
	detMeta:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -44)
	detMeta:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -44)
	detMeta:SetHeight(56)
	if detMeta.SetJustifyV then detMeta:SetJustifyV("TOP") end
	if detMeta.SetWordWrap then detMeta:SetWordWrap(true) end
	dv.detMeta = detMeta

	local fieldBoxCard = createSurfaceCard(rightCard, "glass_r8", "cardAltBg")
	fieldBoxCard:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -106)
	fieldBoxCard:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)

	local fieldHdr = makeFs(fieldBoxCard, 11, "semibold", "textBlue")
	fieldHdr:SetPoint("TOPLEFT", fieldBoxCard, "TOPLEFT", 12, -10)
	fieldHdr:SetText("Columns / Fields")

	local fieldBody = makeFs(fieldBoxCard, 11, "regular", "text")
	fieldBody:SetPoint("TOPLEFT", fieldBoxCard, "TOPLEFT", 12, -30)
	fieldBody:SetPoint("BOTTOMRIGHT", fieldBoxCard, "BOTTOMRIGHT", -12, 12)
	if fieldBody.SetJustifyV then fieldBody:SetJustifyV("TOP") end
	if fieldBody.SetWordWrap then fieldBody:SetWordWrap(true) end
	dv.fieldBody = fieldBody

	function dv.renderRows()
		local CE = getCE()
		local pal = getPal()
		local items = state.dbItems or {}
		local maxOff = max(0, #items - DB_VISIBLE_ROWS)
		if state.dbScrollOffset > maxOff then state.dbScrollOffset = maxOff end
		if sb.SetMinMaxValues then sb:SetMinMaxValues(0, maxOff) end
		dv.pageInfoFs:SetText(format("%d tables (%d-%d)", #items, #items > 0 and (state.dbScrollOffset + 1) or 0,
			min(#items, state.dbScrollOffset + DB_VISIBLE_ROWS)))
		for i = 1, DB_VISIBLE_ROWS do
			local r = dv.rows[i]
			local entry = items[state.dbScrollOffset + i]
			r._entry = entry
			if entry then
				r:Show()
				local sel = (state.dbSelectedId == entry.id)
				if sel then
					r.bg:SetColorTexture(pal.cardHover[1], pal.cardHover[2], pal.cardHover[3], pal.cardHover[4] or 0.9)
				elseif (i % 2) == 0 then
					r.bg:SetColorTexture(pal.cardAltBg[1], pal.cardAltBg[2], pal.cardAltBg[3], 0.45)
				else
					r.bg:SetColorTexture(0, 0, 0, 0)
				end
				r.srcFs:SetText(entry.kindTag or "")
				r.nameFs:SetText(entry.displayName or entry.key or "")
				r.metaFs:SetText(entry.statText or "")
			else
				r:Hide()
			end
		end
	end

	function dv.renderDetail()
		local sel
		for _, entry in ipairs(state.dbItems or {}) do
			if entry.id == state.dbSelectedId then
				sel = entry
				break
			end
		end
		if not sel then sel = state.dbItems[1] end
		if not sel then
			dv.detTitle:SetText("Field & Schema Inspector")
			dv.detMeta:SetText("No tables available.")
			dv.fieldBody:SetText("")
			return
		end
		state.dbSelectedId = sel.id
		dv.detTitle:SetText(format("%s (%s.%s)", sel.displayName or sel.key, sel.store, sel.key))
		dv.detMeta:SetText(format("Store: %s  |  Key: %s\nRows / Entries: %s  |  Detail: %s",
			tostring(sel.store), tostring(sel.key),
			getCE() and getCE().FormatInt(sel.rows or 0) or tostring(sel.rows or 0),
			tostring(sel.detailStat or "--")))
		dv.fieldBody:SetText(tostring(sel.fields or "(no field schema recorded)"))
	end

	function dv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		snapStorageCard:SetWidth(max(320, floor((w - 10) / 2)))
		leftCard:SetWidth(max(360, floor((w - 10) * 0.48)))
	end

	function dv.refresh()
		local CE = getCE()
		if not CE then return end
		local showSnap = hasSnapshotExt()
		local storage = CE.CollectStorageSnapshot()
		local ds = storage.diskSummary or {}
		local sys = showSnap and storage.sysMeta or nil
		local ref = type(CE.GetRefreshSummary) == "function" and CE.GetRefreshSummary() or {}
		local addonState = ds.addonState or (type(CE.GetAddonState) == "function" and CE.GetAddonState("MerchantMaster_Snapshots") or "absent")
		local localSnapRows = 0
		for _, sv in ipairs(storage.savedTables or {}) do
			if sv.id == "MerchantMasterDB.ahSnapshots" then
				localSnapRows = tonumber(sv.rows) or 0
				break
			end
		end

		if showSnap then
			dv.listHdr:SetText("Tables (SQLite + SavedVariables) -- Click to inspect")
			if dv.snapBadge and dv.snapBadge.SetVariant then
				dv.snapBadge:SetVariant("green", "Active")
			end
			if sys then
				dv.snapHeadline:SetText(format(
					"Total on Disk: %s  |  %s Snapshots",
					CE.FormatBytes(ds.snapshotDiskTotalBytes or 0),
					CE.FormatInt(ds.snapshotRuns or 0)))
				dv.snapBody:SetText(format(
					"SQLite DB: %s  |  WAL: %s  |  SHM: %s  |  Sync Log: %s  |  Data Folder: %s\nAddOn Export: %s / %s%s  |  %s price rows  |  %dd window  |  %d err\nDB Path: %s",
					CE.FormatBytes(ds.dbBytes or 0),
					CE.FormatBytes(ds.walBytes or 0),
					CE.FormatBytes(ds.shmBytes or 0),
					CE.FormatBytes(ds.logBytes or 0),
					CE.FormatBytes(ds.dataDirBytes or 0),
					CE.FormatBytes(ds.exportBytes or 0),
					CE.FormatBytes(ds.exportCapBytes or 0),
					ds.truncated and " (TRUNC)" or "",
					CE.FormatInt(ds.snapshotRows or 0),
					ds.retentionDays or 30,
					ds.errRuns or 0,
					(ds.dbPath and ds.dbPath ~= "") and ds.dbPath or "(default data folder)"))
				dv.svHeadline:SetText("Combined Total (Disk + WoW): " .. CE.FormatBytes(ds.combinedTotalBytes or 0))
				dv.sumBody:SetText(format(
					"SavedVariables Est: %s across %d tables (MerchantMasterDB + MerchantMasterLedgerDB)\nSQLite Tables: %d  |  Pages: %s (%d free)  |  Journal: %s\nIn-Game Live AH Scans: %d full, %d partial  |  Last Sync: %s",
					CE.FormatBytes(storage.totalSavedBytes or 0),
					#(storage.savedTables or {}),
					#(storage.sqliteTables or {}),
					CE.FormatInt(sys.pageCount or 0),
					sys.freelist or 0,
					tostring(sys.journalMode or "wal"),
					ref.manualFullScans or 0,
					ref.manualPartialScans or 0,
					CE.FormatTimestamp(ds.exportedAt or sys.exportedAt)))
			else
				dv.snapHeadline:SetText("Snapshot Helper Active  |  Disk Telemetry Pending")
				dv.snapBody:SetText("MerchantMaster_Snapshots is loaded, waiting for SYSTEM metrics from SnapshotData.lua.\nRun Sync Now in your Snapshot Maker tool and type /reload to view SQLite file sizes & snapshot counts.")
				dv.svHeadline:SetText("WoW SavedVariables Est: " .. CE.FormatBytes(storage.totalSavedBytes or 0))
				dv.sumBody:SetText(format(
					"SavedVariables Est: %s across %d tracked tables (MerchantMasterDB + MerchantMasterLedgerDB)\nIn-Game Live AH Scans: %d full, %d partial  |  Local AH Snapshots: %s items",
					CE.FormatBytes(storage.totalSavedBytes or 0),
					#(storage.savedTables or {}),
					ref.manualFullScans or 0,
					ref.manualPartialScans or 0,
					CE.FormatInt(localSnapRows)))
			end
		elseif addonState == "disabled" then
			dv.listHdr:SetText("SavedVariables Tables -- Click to inspect")
			if dv.snapBadge and dv.snapBadge.SetVariant then
				dv.snapBadge:SetVariant("orange", "Disabled")
			end
			dv.snapHeadline:SetText("Data Pack Unchecked in Esc -> AddOns")
			dv.snapBody:SetText("The background Python sync already wrote snapshot data to disk, but WoW has MerchantMaster_Snapshots unchecked.\nOpen Esc -> AddOns, check MerchantMaster Snapshots, and click Reload UI to see your full disk size & snapshot count.")
			dv.svHeadline:SetText("WoW SavedVariables Est: " .. CE.FormatBytes(storage.totalSavedBytes or 0))
			dv.sumBody:SetText(format(
				"SavedVariables Est: %s across %d tracked tables (MerchantMasterDB + MerchantMasterLedgerDB).\nIn-Game Live AH Scans: %d full, %d partial  |  Local AH Snapshots: %s items\nExternal SQLite Disk DB: hidden while MerchantMaster_Snapshots is disabled.",
				CE.FormatBytes(storage.totalSavedBytes or 0),
				#(storage.savedTables or {}),
				ref.manualFullScans or 0,
				ref.manualPartialScans or 0,
				CE.FormatInt(localSnapRows)))
		else
			dv.listHdr:SetText("SavedVariables Tables -- Click to inspect")
			if dv.snapBadge and dv.snapBadge.SetVariant then
				dv.snapBadge:SetVariant("neutral", "Not Installed")
			end
			dv.snapHeadline:SetText("External Disk DB: Not Installed (0 B)")
			dv.snapBody:SetText("MerchantMaster is running standalone from live in-game AH scans.\nOpen the Snapshot Settings tab to set up the optional background Python sync (30-day disk DB; split Windows Task Scheduler & Linux systemd setup).")
			dv.svHeadline:SetText("WoW SavedVariables Est: " .. CE.FormatBytes(storage.totalSavedBytes or 0))
			dv.sumBody:SetText(format(
				"SavedVariables Est: %s across %d tracked tables (MerchantMasterDB + MerchantMasterLedgerDB).\nIn-Game Live AH Scans: %d full, %d partial  |  Local AH Snapshots: %s items\nExternal SQLite Disk DB: 0 B (not loaded).",
				CE.FormatBytes(storage.totalSavedBytes or 0),
				#(storage.savedTables or {}),
				ref.manualFullScans or 0,
				ref.manualPartialScans or 0,
				CE.FormatInt(localSnapRows)))
		end

		local items = {}
		if showSnap then
			for _, st in ipairs(storage.sqliteTables or {}) do
				items[#items + 1] = {
					id = st.id,
					kindTag = "SQLite",
					store = st.store,
					key = st.key,
					displayName = st.label,
					rows = st.rows,
					statText = format("%s r | %d c", CE.FormatInt(st.rows or 0), st.cols or 0),
					detailStat = format("%d columns", st.cols or 0),
					fields = st.fields,
				}
			end
		end
		for _, sv in ipairs(storage.savedTables or {}) do
			items[#items + 1] = {
				id = sv.id,
				kindTag = sv.store == "MerchantMasterLedgerDB" and "Ledger"
					or (sv.key == "professor" and "Professor" or "SavedVars"),
				store = sv.store,
				key = sv.key,
				displayName = sv.label,
				rows = sv.rows,
				statText = format("%s r | %s", CE.FormatInt(sv.rows or 0), CE.FormatBytes(sv.estBytes or 0)),
				detailStat = "Est. " .. CE.FormatBytes(sv.estBytes or 0),
				fields = sv.fields,
			}
		end
		state.dbItems = items
		if not state.dbSelectedId and items[1] then
			state.dbSelectedId = items[1].id
		end
		dv.renderRows()
		dv.renderDetail()
	end

	return dv
end

---------------------------------------------------------------------------------------------------
-- Sub-View 3: Performance Profiler & Support Debugger (console_perf)
---------------------------------------------------------------------------------------------------

local function buildPerfView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local pv = {
		frame = frame,
	}

	local ctrlCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	ctrlCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	ctrlCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	ctrlCard:SetHeight(114)
	pv.ctrlCard = ctrlCard

	local ctrlTitle = makeFs(ctrlCard, 13, "semibold", "text")
	ctrlTitle:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 14, -10)
	ctrlTitle:SetText("Performance & Diagnostics Controls")

	local noteFs = makeFs(ctrlCard, 11, "regular", "textSecondary")
	noteFs:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 14, -30)
	noteFs:SetPoint("TOPRIGHT", ctrlCard, "TOPRIGHT", -14, -30)
	noteFs:SetText("Zero-overhead default: when diagnostics are OFF, zero timing or probe hooks run anywhere in MerchantMaster.")
	pv.noteFs = noteFs

	local rtCheck = createCheck(ctrlCard, "Runtime & Transaction Profiler (Default OFF)", 11, function(_, on)
		local CE = getCE()
		if CE then CE.SetPerfEnabled(on) end
		UI.Refresh("toggle_perf")
	end)
	rtCheck:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 14, -54)
	pv.rtCheck = rtCheck

	local resetPerfBtn = createButton(ctrlCard, "Reset Timings", 110, 22, { variant = "secondary", fontSize = 11 })
	resetPerfBtn:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 355, -53)
	resetPerfBtn:SetScript("OnClick", function()
		local CE = getCE()
		if CE then CE.ResetPerfMetrics() end
		UI.Refresh("reset_perf")
	end)

	local probeCheck = createCheck(ctrlCard, "Ledger Capture Probe (Debug Log)", 11, function(_, on)
		if type(_G.MerchantMasterLedgerDB) == "table" then
			_G.MerchantMasterLedgerDB.probe = type(_G.MerchantMasterLedgerDB.probe) == "table" and _G.MerchantMasterLedgerDB.probe or {}
			_G.MerchantMasterLedgerDB.probe.enabled = (on == true)
		end
		UI.Refresh("toggle_probe")
	end)
	probeCheck:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 495, -54)
	pv.probeCheck = probeCheck

	local clearProbeBtn = createButton(ctrlCard, "Clear Log", 96, 22, { variant = "secondary", fontSize = 11 })
	clearProbeBtn:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 755, -53)
	clearProbeBtn:SetScript("OnClick", function()
		local CE = getCE()
		if CE then CE.RunAction("clear_probe_log") end
		UI.Refresh("clear_probe")
	end)

	local reloadHintFs = makeFs(ctrlCard, 11, "regular", "textBlue")
	reloadHintFs:SetPoint("TOPLEFT", ctrlCard, "TOPLEFT", 14, -86)
	reloadHintFs:SetPoint("TOPRIGHT", ctrlCard, "TOPRIGHT", -14, -86)
	reloadHintFs:SetText("Tip: Enable Runtime Profiler or Ledger Probe only while testing, then turn OFF when finished.")
	pv.reloadHintFs = reloadHintFs

	-- Left lower card: Runtime & UI Timings
	local metricsCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	metricsCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -122)
	metricsCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	metricsCard:SetWidth(440)
	pv.metricsCard = metricsCard

	local mTitle = makeFs(metricsCard, 13, "semibold", "text")
	mTitle:SetPoint("TOPLEFT", metricsCard, "TOPLEFT", 14, -12)
	mTitle:SetText("Transaction & UI Timings")

	local mSep = createSeparator(metricsCard)
	mSep:SetPoint("TOPLEFT", metricsCard, "TOPLEFT", 12, -34)
	mSep:SetPoint("TOPRIGHT", metricsCard, "TOPRIGHT", -12, -34)

	local timingBody = makeFs(metricsCard, 11, "regular", "text")
	timingBody:SetPoint("TOPLEFT", metricsCard, "TOPLEFT", 14, -42)
	timingBody:SetPoint("BOTTOMRIGHT", metricsCard, "BOTTOMRIGHT", -14, 12)
	if timingBody.SetJustifyV then timingBody:SetJustifyV("TOP") end
	if timingBody.SetWordWrap then timingBody:SetWordWrap(true) end
	pv.timingBody = timingBody

	-- Right lower card: Debugger Copy-Paste Bundle
	local debugCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	debugCard:SetPoint("TOPLEFT", metricsCard, "TOPRIGHT", 10, 0)
	debugCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	pv.debugCard = debugCard

	local dTitle = makeFs(debugCard, 13, "semibold", "text")
	dTitle:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 14, -12)
	dTitle:SetText("Debugger Copy-Paste Support Bundle")

	local dBytesFs = makeFs(debugCard, 11, "regular", "textSecondary", "RIGHT")
	dBytesFs:SetPoint("TOPRIGHT", debugCard, "TOPRIGHT", -14, -13)
	dBytesFs:SetText("0 B")
	pv.dBytesFs = dBytesFs

	local chkSet = createCheck(debugCard, "Settings", 11, function(_, on)
		state.bundleOpts.includeSettings = on
	end)
	chkSet:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 14, -38)
	local chkDB = createCheck(debugCard, "Database", 11, function(_, on)
		state.bundleOpts.includeDatabase = on
	end)
	chkDB:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 112, -38)
	local chkPerf = createCheck(debugCard, "Perf", 11, function(_, on)
		state.bundleOpts.includePerf = on
	end)
	chkPerf:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 214, -38)
	local chkLogs = createCheck(debugCard, "Errors/Probe", 11, function(_, on)
		state.bundleOpts.includeLogs = on
	end)
	chkLogs:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 286, -38)
	local chkRedact = createCheck(debugCard, "Redact Names", 11, function(_, on)
		state.bundleOpts.redactNames = on
	end)
	chkRedact:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 412, -38)
	pv.chkSet, pv.chkDB, pv.chkPerf, pv.chkLogs, pv.chkRedact = chkSet, chkDB, chkPerf, chkLogs, chkRedact

	local genBtn = createButton(debugCard, "Generate Debug Bundle", 165, 24, { variant = "primary", pill = true, fontSize = 11 })
	genBtn:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 14, -66)
	genBtn:SetScript("OnClick", function()
		pv.regenerateBundle()
		selectAllInBox(pv.bundleBox)
	end)

	local selAllBtn = createButton(debugCard, "Select All (Ctrl+C)", 135, 24, { variant = "secondary", fontSize = 11 })
	selAllBtn:SetPoint("LEFT", genBtn, "RIGHT", 8, 0)
	selAllBtn:SetScript("OnClick", function()
		selectAllInBox(pv.bundleBox)
	end)

	local boxCard, bundleBox = createMultiLineArea(debugCard)
	boxCard:SetPoint("TOPLEFT", debugCard, "TOPLEFT", 14, -98)
	boxCard:SetPoint("BOTTOMRIGHT", debugCard, "BOTTOMRIGHT", -14, 12)
	pv.bundleBox = bundleBox

	function pv.regenerateBundle()
		local CE = getCE()
		if not CE then return end
		local text = CE.BuildDebugBundle(state.bundleOpts)
		if pv.bundleBox and pv.bundleBox.SetText then
			pv.bundleBox:SetText(text)
		end
		pv.dBytesFs:SetText(CE.FormatBytes(#text))
	end

	function pv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		metricsCard:SetWidth(max(340, floor((w - 10) * 0.44)))
	end

	function pv.refresh()
		local CE = getCE()
		if not CE then return end
		local perf = CE.GetPerfSnapshot()
		local ldb = type(_G.MerchantMasterLedgerDB) == "table" and _G.MerchantMasterLedgerDB or nil
		local probeOn = (ldb and type(ldb.probe) == "table" and ldb.probe.enabled == true) and true or false

		if pv.rtCheck.SetChecked then pv.rtCheck:SetChecked(perf.enabled == true) end
		if pv.probeCheck.SetChecked then pv.probeCheck:SetChecked(probeOn) end

		if pv.chkSet.SetChecked then pv.chkSet:SetChecked(state.bundleOpts.includeSettings) end
		if pv.chkDB.SetChecked then pv.chkDB:SetChecked(state.bundleOpts.includeDatabase) end
		if pv.chkPerf.SetChecked then pv.chkPerf:SetChecked(state.bundleOpts.includePerf) end
		if pv.chkLogs.SetChecked then pv.chkLogs:SetChecked(state.bundleOpts.includeLogs) end
		if pv.chkRedact.SetChecked then pv.chkRedact:SetChecked(state.bundleOpts.redactNames) end

		local tLines = {}
		tLines[#tLines + 1] = format("Runtime Profiler: %s  |  Recorded Tx: %d (avg %.3f ms, max %.3f ms)",
			perf.enabled and "ON" or "OFF", perf.txTotal or 0, perf.txAvgMs or 0, perf.txMaxMs or 0)
		if #perf.txByKind > 0 then
			for i = 1, min(8, #perf.txByKind) do
				local k = perf.txByKind[i]
				tLines[#tLines + 1] = format("  TX %-12s n=%d  avg=%.3fms  max=%.3fms", k.kind, k.count, k.avgMs, k.maxMs)
			end
		else
			tLines[#tLines + 1] = "  No transaction timings recorded yet."
		end
		if #perf.uiByTab > 0 then
			tLines[#tLines + 1] = ""
			tLines[#tLines + 1] = "Recent UI Refreshes:"
			for i = 1, min(8, #perf.uiByTab) do
				local u = perf.uiByTab[i]
				tLines[#tLines + 1] = format("  UI %-16s n=%d  avg=%.2fms  last=%.2fms", u.tab, u.count, u.avgMs, u.lastMs)
			end
		end
		if #perf.bootPhases > 0 then
			tLines[#tLines + 1] = ""
			tLines[#tLines + 1] = "Boot Phases:"
			for i = 1, min(6, #perf.bootPhases) do
				local bp = perf.bootPhases[i]
				tLines[#tLines + 1] = format("  %-18s %.2fms", tostring(bp.phase or "?"), bp.ms or 0)
			end
		end
		pv.timingBody:SetText(table.concat(tLines, "\n"))

		if pv.bundleBox and ((pv.bundleBox.GetText and pv.bundleBox:GetText()) or "") == "" then
			pv.regenerateBundle()
		end
	end

	return pv
end

---------------------------------------------------------------------------------------------------
-- Sub-View 4: Snapshot Sync - GitHub Auto-Sync (Zero API Key) (console_setup2)
---------------------------------------------------------------------------------------------------

local function buildSetupV2View(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local v2 = {
		frame = frame,
	}

	local function addCardAccent(card, r, g, b, a)
		if not (card and card.CreateTexture) then return nil end
		local bar = card:CreateTexture(nil, "ARTWORK", nil, 2)
		bar:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -1)
		bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -1)
		bar:SetHeight(2)
		bar:SetColorTexture(r, g, b, a or 0.90)
		return bar
	end

	-- Top Status & Feed Summary Card
	local statusCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	statusCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	statusCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	statusCard:SetHeight(72)
	addCardAccent(statusCard, 0.24, 0.84, 0.48, 0.90)
	v2.statusCard = statusCard

	local stTitle = makeFs(statusCard, 13, "semibold", "text")
	stTitle:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 14, -8)
	stTitle:SetPoint("TOPRIGHT", statusCard, "TOPRIGHT", -14, -8)
	stTitle:SetText("Snapshot Sync (GitHub Auto-Sync - Zero API Key)")
	v2.stTitle = stTitle

	local stBody = makeFs(statusCard, 11, "regular", "textSecondary")
	stBody:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 14, -26)
	stBody:SetPoint("TOPRIGHT", statusCard, "TOPRIGHT", -14, -26)
	stBody:SetHeight(22)
	if stBody.SetJustifyV then stBody:SetJustifyV("TOP") end
	if stBody.SetWordWrap then stBody:SetWordWrap(true) end
	v2.stBody = stBody

	local stFeed = makeFs(statusCard, 11, "regular", "textBlue")
	stFeed:SetPoint("BOTTOMLEFT", statusCard, "BOTTOMLEFT", 14, 6)
	stFeed:SetPoint("BOTTOMRIGHT", statusCard, "BOTTOMRIGHT", -14, 6)
	if stFeed.SetWordWrap then stFeed:SetWordWrap(true) end
	stFeed:SetText("Public Feed: JustBenji/MerchantMaster-SnapshotData (tag: snapshots-live)  |  SHA256 verified before import")
	v2.stFeed = stFeed

	-- 3-Way Price Refresh Mode Card (Local Snapshot & TSM Light never mix)
	local tsmCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	tsmCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -80)
	tsmCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -80)
	tsmCard:SetHeight(72)
	addCardAccent(tsmCard, 0.24, 0.72, 0.98, 0.90)
	v2.tsmCard = tsmCard

	local modeLbl = makeFs(tsmCard, 12, "semibold", "text")
	modeLbl:SetPoint("TOPLEFT", tsmCard, "TOPLEFT", 14, -10)
	modeLbl:SetText("Price Refresh Mode:")
	v2.modeLbl = modeLbl

	v2.modeBtns = {}
	do
		local modeDefs = {
			{
				key = "local",
				label = "Local Snapshot",
				width = 118,
				tipTitle = "Local Snapshot Mode",
				tipLines = {
					"Uses MerchantMaster_Snapshots for 15m background AH updates, 7x24 heatmaps, and 6-tier buyout depth.",
					"Local Snapshot and TSM Light never mix (TSM stays completely off).",
				},
			},
			{
				key = "tsm",
				label = "TSM Light",
				width = 96,
				tipTitle = "TSM Light Mode (Hourly Prices)",
				tipLines = {
					"Uses TradeSkillMaster addon + TSM Desktop App for hourly prices inside MerchantMaster tables with zero local storage.",
					"Local Snapshot and TSM Light never mix (Local Snapshot, 7x24 heatmaps, and buyout depth are paused).",
				},
			},
			{
				key = "none",
				label = "None (Manual AH)",
				width = 132,
				tipTitle = "Manual AH Only Mode",
				tipLines = {
					"Manual in-game Auction House scans only.",
					"Both Local Snapshot background data and TSM Light are paused (they never mix).",
				},
			},
		}
		local prevBtn = nil
		for _, def in ipairs(modeDefs) do
			local btn = createButton(tsmCard, def.label, def.width, 24, {
				variant = "secondary",
				pill = true,
				fontSize = 11,
			})
			if not prevBtn then
				btn:SetPoint("TOPLEFT", tsmCard, "TOPLEFT", 146, -7)
			else
				btn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
			end
			local modeKey = def.key
			btn:SetScript("OnClick", function()
				if type(ns.SetBackgroundPriceMode) == "function" then
					ns.SetBackgroundPriceMode(modeKey)
				else
					if type(_G.MerchantMasterDB) ~= "table" then _G.MerchantMasterDB = {} end
					_G.MerchantMasterDB.backgroundPriceMode = modeKey
					_G.MerchantMasterDB.useTSMPrices = (modeKey == "tsm")
					if type(ns.InvalidatePriceCache) == "function" then
						ns.InvalidatePriceCache()
					end
				end
				local app = ns.app
				if app and app.ui and app.ui.optSourceBtn and type(ns.CurrentSourceInfo) == "function" then
					app.ui.optSourceBtn:SetText("Price Source: " .. ns.CurrentSourceInfo().label)
				end
				v2.retheme()
				UI.SyncSettings()
				if app and type(app.refresh) == "function" then
					app.refresh()
				end
			end)
			attachTooltip(btn, def.tipTitle, def.tipLines)
			v2.modeBtns[modeKey] = btn
			prevBtn = btn
		end
	end
	v2.enableBtn = v2.modeBtns["local"]
	v2.disableBtn = v2.modeBtns["none"]

	local tsmStatusFs = makeFs(tsmCard, 11, "semibold", "textMuted", "RIGHT")
	tsmStatusFs:SetPoint("TOPRIGHT", tsmCard, "TOPRIGHT", -14, -10)
	tsmStatusFs:SetWidth(220)
	tsmStatusFs:SetText("Manual AH Only (Local OFF)")
	v2.tsmStatusFs = tsmStatusFs

	local tsmSubFs = makeFs(tsmCard, 10, "regular", "textSecondary")
	tsmSubFs:SetPoint("TOPLEFT", tsmCard, "TOPLEFT", 14, -36)
	tsmSubFs:SetPoint("BOTTOMRIGHT", tsmCard, "BOTTOMRIGHT", -14, 6)
	if tsmSubFs.SetJustifyV then tsmSubFs:SetJustifyV("TOP") end
	if tsmSubFs.SetWordWrap then tsmSubFs:SetWordWrap(true) end
	tsmSubFs:SetText("Manual in-game Auction House scans only. Both Local Snapshot background data and TSM Light are paused (Local Snapshot and TSM Light never mix).")
	v2.tsmSubFs = tsmSubFs

	local function makeCopyRowV2(card, yOff, labelText, btnVariant)
		local isPrimary = (btnVariant == "primary")
		local lbl = makeFs(card, 11, "semibold", isPrimary and "textGold" or "textMuted")
		lbl:SetPoint("TOPLEFT", card, "TOPLEFT", 14, yOff)
		lbl:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, yOff)
		lbl:SetText(labelText)

		local btnW = isPrimary and 88 or 74
		local boxRight = isPrimary and -112 or -98
		local box = createSingleLineBox(card, 320, 24)
		box:SetPoint("TOPLEFT", card, "TOPLEFT", 14, yOff - 16)
		box:SetPoint("TOPRIGHT", card, "TOPRIGHT", boxRight, yOff - 16)

		local selBtn = createButton(card, isPrimary and "Copy / Select" or "Select", btnW, 24, {
			variant = btnVariant or "secondary",
			pill = isPrimary,
			fontSize = isPrimary and 10 or 11,
		})
		selBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, yOff - 16)
		selBtn:SetScript("OnClick", function()
			selectAllInBox(box)
			if v2.stFeed then
				v2.stFeed:SetText(colorHex("hexBlue", "Command highlighted - press Ctrl+C, then paste once into PowerShell / Terminal.", getPal()))
			end
		end)
		return box, selBtn, lbl
	end

	-- Left Column: Windows Automatic GitHub Sync
	local winCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	winCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -160)
	winCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	winCard:SetWidth(460)
	addCardAccent(winCard, 0.30, 0.66, 0.96, 0.85)
	v2.winCard = winCard

	local winTitle = makeFs(winCard, 13, "semibold", "text")
	winTitle:SetPoint("TOPLEFT", winCard, "TOPLEFT", 14, -8)
	winTitle:SetText("Windows Automatic GitHub Sync (PowerShell)")

	local winSub = makeFs(winCard, 10, "regular", "textSecondary")
	winSub:SetPoint("TOPLEFT", winCard, "TOPLEFT", 14, -24)
	winSub:SetPoint("TOPRIGHT", winCard, "TOPRIGHT", -14, -24)
	winSub:SetText("Requires Python 3.11+ (python.org or winget install Python.Python.3.12) - Zero API Key")

	local wSep = createSeparator(winCard)
	wSep:SetPoint("TOPLEFT", winCard, "TOPLEFT", 12, -40)
	wSep:SetPoint("TOPRIGHT", winCard, "TOPRIGHT", -12, -40)

	v2.winInstallBox, v2.winSelectBtn = makeCopyRowV2(winCard, -48, "1. Recommended - 1-Line Auto-Setup:", "primary")
	v2.winAltBox, v2.winAltSelectBtn = makeCopyRowV2(winCard, -94, "2. Fallback (if 'py' is not recognized):", "secondary")
	v2.winCheckBox, v2.winCheckBtn = makeCopyRowV2(winCard, -140, "3. Preview Missing Data (--check-only):", "secondary")
	v2.winRebuildBox, v2.winRebuildBtn = makeCopyRowV2(winCard, -186, "4. Rebuild Snapshot DB (--force):", "secondary")
	v2.winUninstallBox, v2.winUninstallBtn = makeCopyRowV2(winCard, -232, "5. Turn Off Background Sync (uninstall-task):", "secondary")

	local winNote = makeFs(winCard, 10, "regular", "textSecondary")
	winNote:SetPoint("TOPLEFT", winCard, "TOPLEFT", 14, -278)
	winNote:SetPoint("BOTTOMRIGHT", winCard, "BOTTOMRIGHT", -14, 8)
	if winNote.SetJustifyV then winNote:SetJustifyV("TOP") end
	if winNote.SetWordWrap then winNote:SetWordWrap(true) end
	winNote:SetText("Installs hidden Task Scheduler catch-up (zero UAC prompt, 100-350 KB/hr deltas). Rebuild re-syncs local cache; Uninstall removes scheduled sync cleanly.")
	v2.winNote = winNote

	-- Right Column: Linux / Steam Deck & macOS Automatic GitHub Sync
	local unixCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	unixCard:SetPoint("TOPLEFT", winCard, "TOPRIGHT", 10, 0)
	unixCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -160)
	unixCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	addCardAccent(unixCard, 0.30, 0.66, 0.96, 0.85)
	v2.unixCard = unixCard

	local unixTitle = makeFs(unixCard, 13, "semibold", "text")
	unixTitle:SetPoint("TOPLEFT", unixCard, "TOPLEFT", 14, -8)
	unixTitle:SetText("Linux / Steam Deck & macOS Auto-Sync (Terminal)")

	local unixSub = makeFs(unixCard, 10, "regular", "textSecondary")
	unixSub:SetPoint("TOPLEFT", unixCard, "TOPLEFT", 14, -24)
	unixSub:SetPoint("TOPRIGHT", unixCard, "TOPRIGHT", -14, -24)
	unixSub:SetText("Auto-detects Wine, Lutris, Steam Deck, Bottles & macOS - Zero API Key")

	local uSep = createSeparator(unixCard)
	uSep:SetPoint("TOPLEFT", unixCard, "TOPLEFT", 12, -40)
	uSep:SetPoint("TOPRIGHT", unixCard, "TOPRIGHT", -12, -40)

	v2.linuxInstallBox, v2.linuxSelectBtn = makeCopyRowV2(unixCard, -48, "1. Recommended (Linux / Steam Deck 1-Line Auto-Setup):", "primary")
	v2.macInstallBox, v2.macSelectBtn = makeCopyRowV2(unixCard, -94, "2. macOS 1-Line Auto-Setup:", "secondary")
	v2.linuxCheckBox, v2.linuxCheckBtn = makeCopyRowV2(unixCard, -140, "3. Preview Missing Data (--check-only):", "secondary")
	v2.linuxRebuildBox, v2.linuxRebuildBtn = makeCopyRowV2(unixCard, -186, "4. Rebuild Snapshot DB (--force):", "secondary")
	v2.linuxUninstallBox, v2.linuxUninstallBtn = makeCopyRowV2(unixCard, -232, "5. Turn Off Background Sync (uninstall-task):", "secondary")

	local unixNote = makeFs(unixCard, 10, "regular", "textSecondary")
	unixNote:SetPoint("TOPLEFT", unixCard, "TOPLEFT", 14, -278)
	unixNote:SetPoint("BOTTOMRIGHT", unixCard, "BOTTOMRIGHT", -14, 8)
	if unixNote.SetJustifyV then unixNote:SetJustifyV("TOP") end
	if unixNote.SetWordWrap then unixNote:SetWordWrap(true) end
	unixNote:SetText("Uses isolated ~/.local/bin/mm-snapshots with systemd timer / launchd agent & SHA256 check. Feed: github.com/JustBenji/MerchantMaster-SnapshotData")
	v2.unixNote = unixNote

	function v2.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		local halfW = max(320, floor((w - 10) / 2))
		winCard:SetWidth(halfW)
	end

	function v2.updateTsmStatus(pal)
		pal = pal or getPal()
		local mode = (type(ns.GetBackgroundPriceMode) == "function" and ns.GetBackgroundPriceMode()) or "none"
		if type(v2.modeBtns) == "table" then
			for k, btn in pairs(v2.modeBtns) do
				if btn and type(btn.SetActive) == "function" then
					btn:SetActive(k == mode)
				end
			end
		end
		if mode == "local" then
			local hasLocal = hasSnapshotExt() or (type(ns.HasRawSnapshots) == "function" and ns.HasRawSnapshots() == true)
			if v2.tsmStatusFs then
				if hasLocal then
					v2.tsmStatusFs:SetText(colorHex("hexGreen", "Local Snapshot Active", pal))
				else
					v2.tsmStatusFs:SetText(colorHex("hexWarning", "Local Snapshot (Not Installed)", pal))
				end
			end
			if v2.tsmSubFs then
				v2.tsmSubFs:SetText("Uses MerchantMaster_Snapshots for 15m background AH updates, 7x24 heatmaps, and 6-tier buyout depth. Local Snapshot and TSM Light never mix (TSM stays completely off).")
			end
		elseif mode == "tsm" then
			local avail = false
			if type(ns.IsTSMAvailable) == "function" then
				avail = ns.IsTSMAvailable() == true
			else
				local api = rawget(_G, "TSM_API")
				avail = type(api) == "table" and type(api.GetCustomPriceValue) == "function"
			end
			if v2.tsmStatusFs then
				if avail then
					v2.tsmStatusFs:SetText(colorHex("hexGreen", "TSM Light Active (Local OFF)", pal))
				else
					v2.tsmStatusFs:SetText(colorHex("hexWarning", "Waiting for TradeSkillMaster", pal))
				end
			end
			if v2.tsmSubFs then
				v2.tsmSubFs:SetText("Uses TradeSkillMaster addon + TSM Desktop App for hourly prices inside MerchantMaster tables with zero local storage. Local Snapshot and TSM Light never mix (Local Snapshot, 7x24 heatmaps, and buyout depth are paused).")
			end
		else
			if v2.tsmStatusFs then
				v2.tsmStatusFs:SetText(colorHex("hexMuted", "Manual AH Only (Local OFF)", pal))
			end
			if v2.tsmSubFs then
				v2.tsmSubFs:SetText("Manual in-game Auction House scans only. Both Local Snapshot background data and TSM Light are paused (Local Snapshot and TSM Light never mix).")
			end
		end
	end

	function v2.retheme()
		local CE = getCE()
		if not CE then return end
		local pal = getPal()
		v2.updateTsmStatus(pal)
		local installed = hasSnapshotExt()
		local addonState = type(CE.GetAddonState) == "function" and CE.GetAddonState("MerchantMaster_Snapshots") or (installed and "loaded" or "absent")
		local bgMode = (type(ns.GetBackgroundPriceMode) == "function" and ns.GetBackgroundPriceMode()) or "none"
		local suppressed = type(ns.IsLocalSnapshotSuppressed) == "function" and ns.IsLocalSnapshotSuppressed()

		if not installed then
			if addonState == "disabled" then
				v2.stTitle:SetText("Snapshot Sync (GitHub Auto-Sync - Enable Pack in WoW)")
				v2.stBody:SetText("SnapshotData.lua is on disk, but MerchantMaster_Snapshots is unchecked in Esc -> AddOns. Check it and click Reload UI.")
			else
				v2.stTitle:SetText("Snapshot Sync (GitHub Auto-Sync - Zero API Key)")
				v2.stBody:SetText("Copy 1 command below -> auto-installs Python sync, detects WoW Forever, pulls GitHub deltas & exports SnapshotData.lua -> /reload in WoW.")
			end
		elseif suppressed and bgMode == "tsm" then
			v2.stTitle:SetText("Snapshot Sync (GitHub Auto-Sync - Paused by TSM Light)")
			v2.stBody:SetText("Snapshot pack is ready on disk. Click Local Snapshot above to switch back from TSM Light.")
		elseif suppressed and bgMode == "none" then
			v2.stTitle:SetText("Snapshot Sync (GitHub Auto-Sync - OFF / Manual AH)")
			v2.stBody:SetText("Snapshot pack is ready on disk, currently paused. Click Local Snapshot above to resume or run Rebuild (--force) below.")
		else
			v2.stTitle:SetText("Snapshot Sync (GitHub Auto-Sync - Active)")
			local sys = v2._lastSys
			if sys then
				local diskTotal = max(((tonumber(sys.dbBytes) or 0) + (tonumber(sys.walBytes) or 0) + (tonumber(sys.shmBytes) or 0) + (tonumber(sys.logBytes) or 0)), tonumber(sys.localDataDirBytes) or 0) + (tonumber(sys.exportBytes) or 0)
				v2.stBody:SetText(format("GitHub Auto-Sync Active | Disk: %s | Snapshots: %s | Every %dm | Last Sync: %s",
					CE.FormatBytes(diskTotal), CE.FormatInt(sys.totalRuns or 0), sys.intervalMin or 15, CE.FormatTimestamp(sys.exportedAt)))
			else
				v2.stBody:SetText("GitHub Auto-Sync Ready | Local Snapshot mode active. Run 1 command below on a fresh PC to auto-install and sync.")
			end
		end

		v2.stFeed:SetText("Public Feed: JustBenji/MerchantMaster-SnapshotData (tag: snapshots-live)  |  Mode: " .. (bgMode == "local" and colorHex("hexGreen", "Local Snapshot Active", pal) or colorHex("hexWarning", bgMode == "none" and "OFF (Manual AH)" or "Paused (TSM Light)", pal)))
	end

	function v2.refresh()
		local CE = getCE()
		if not CE then return end
		local installed = hasSnapshotExt()
		v2._lastSys = installed and ns.Pricing and type(ns.Pricing.GetSnapshotSystemMeta) == "function"
			and ns.Pricing.GetSnapshotSystemMeta() or nil

		local cmds = CE.INSTALL_COMMANDS_V2 or {}
		if v2.winInstallBox and v2.winInstallBox.SetText then v2.winInstallBox:SetText(cmds.windows or "") end
		if v2.winAltBox and v2.winAltBox.SetText then v2.winAltBox:SetText(cmds.windowsAlt or "") end
		if v2.winCheckBox and v2.winCheckBox.SetText then v2.winCheckBox:SetText(cmds.windowsCheck or "") end
		if v2.winRebuildBox and v2.winRebuildBox.SetText then v2.winRebuildBox:SetText(cmds.windowsRebuild or "") end
		if v2.winUninstallBox and v2.winUninstallBox.SetText then v2.winUninstallBox:SetText(cmds.windowsUninstall or "") end
		if v2.linuxInstallBox and v2.linuxInstallBox.SetText then v2.linuxInstallBox:SetText(cmds.linux or "") end
		if v2.macInstallBox and v2.macInstallBox.SetText then v2.macInstallBox:SetText(cmds.macos or "") end
		if v2.linuxCheckBox and v2.linuxCheckBox.SetText then v2.linuxCheckBox:SetText(cmds.linuxCheck or "") end
		if v2.linuxRebuildBox and v2.linuxRebuildBox.SetText then v2.linuxRebuildBox:SetText(cmds.linuxRebuild or "") end
		if v2.linuxUninstallBox and v2.linuxUninstallBox.SetText then v2.linuxUninstallBox:SetText(cmds.linuxUninstall or "") end

		v2.retheme()
	end

	return v2
end

---------------------------------------------------------------------------------------------------
-- Sub-View 5: Settings (console_settings)
---------------------------------------------------------------------------------------------------

local function buildSettingsView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local sv = {
		frame = frame,
		checks = {},
	}

	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(500)
	sv.leftCard = leftCard

	local leftTitle = makeFs(leftCard, 13, "semibold", "text")
	leftTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -12)
	leftTitle:SetText("General, Market & Pricing Settings")

	local econBtn = createButton(leftCard, "Economy: --", 220, 24, { dropdown = true, fontSize = 11 })
	econBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -40)
	econBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	econBtn:SetScript("OnClick", function(self, mouseBtn)
		if ns.app and type(ns.app.cycleEconomy) == "function" then
			ns.app.cycleEconomy(mouseBtn, self)
		end
		UI.SyncSettings()
	end)
	attachTooltip(econBtn, "Active Economy", {
		"Switches between Auto-detected realm/faction and any specific Classic Forever economy (Normal, PvP, RP, Hardcore x Horde/Alliance).",
		"Right-click to reset back to Auto.",
	})

	local sourceBtn = createButton(leftCard, "Price Source: --", 220, 24, { dropdown = true, fontSize = 11 })
	sourceBtn:SetPoint("LEFT", econBtn, "RIGHT", 8, 0)
	sourceBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	sourceBtn:SetScript("OnClick", function(self, mouseBtn)
		if not _G.MerchantMasterDB then return end
		local app = ns.app
		local function applySrc(pickedKey)
			_G.MerchantMasterDB.priceSource = pickedKey
			if ns.InvalidatePriceCache then ns.InvalidatePriceCache() end
			if app and app.ui and app.ui.optSourceBtn and ns.CurrentSourceInfo then
				app.ui.optSourceBtn:SetText("Price Source: " .. ns.CurrentSourceInfo().label)
			end
			if app and app.refresh then app.refresh() end
			UI.SyncSettings()
		end
		if mouseBtn == "RightButton" then
			applySrc("auto")
		else
			local avail = (ns.GetAvailablePriceSources and ns.GetAvailablePriceSources()) or ns.PRICE_SOURCES or {}
			local curKey = (ns.GetEffectivePriceSource and ns.GetEffectivePriceSource()) or _G.MerchantMasterDB.priceSource or "auto"
			local T = getTheme()
			if T and T.OpenDropDown then
				T.OpenDropDown(self, avail, curKey, applySrc, 210)
			end
		end
	end)
	attachTooltip(sourceBtn, "Primary Price Source", function()
		if hasSnapshotsAny() then
			return {
				"Controls whether MerchantMaster prefers Local Snapshot, Live AH Scans, or newest-timestamp Auto selection.",
				"Right-click to reset to Auto.",
			}
		end
		return {
			"Controls which Live AH price source MerchantMaster uses for crafting and resale calculations.",
			"Right-click to reset to Auto.",
		}
	end)

	local lSep = createSeparator(leftCard)
	lSep:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -74)
	lSep:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -12, -74)

	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	sv.rightCard = rightCard

	local rightTitle = makeFs(rightCard, 13, "semibold", "text")
	rightTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -12)
	rightTitle:SetText("Inventory Scope & Hover Tooltips")

	local rSep = createSeparator(rightCard)
	rSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -38)
	rSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -38)

	local function addCheck(hostCard, yOff, label, tipTitle, tipLines, getFn, setFn)
		local cb = createCheck(hostCard, label, 11, function(_, on)
			if not _G.MerchantMasterDB then _G.MerchantMasterDB = {} end
			setFn(on)
			UI.SyncSettings()
		end)
		cb:SetPoint("TOPLEFT", hostCard, "TOPLEFT", 14, yOff)
		cb._get = getFn
		if tipTitle then
			attachTooltip(cb, tipTitle, tipLines)
		end
		sv.checks[#sv.checks + 1] = cb
		return cb
	end

	-- Left card: General, Market & Pricing checkboxes
	local minimapCheck = addCheck(leftCard, -88, "Show the minimap button",
		"Minimap Button", {
			"Shows or hides the MerchantMaster minimap icon (/mm minimap).",
		},
		function() return not (_G.MerchantMasterDB and _G.MerchantMasterDB.minimap and _G.MerchantMasterDB.minimap.hide) end,
		function(on)
			_G.MerchantMasterDB.minimap = _G.MerchantMasterDB.minimap or {}
			_G.MerchantMasterDB.minimap.hide = not on
			local LDBI = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
			if LDBI then
				if on then LDBI:Show(ADDON) else LDBI:Hide(ADDON) end
			end
		end)

	addCheck(leftCard, -120, "Don't open automatically with the Auction House",
		"AH Auto-Open Guard", {
			"When checked, opening the Auction House will NOT automatically pop open MerchantMaster's main window.",
		},
		function() return _G.MerchantMasterDB and _G.MerchantMasterDB.hideWithAH == true end,
		function(on)
			_G.MerchantMasterDB.hideWithAH = on
			if ns.app and ns.app.ui and ns.app.ui.hideWithAH then ns.app.ui.hideWithAH:SetChecked(on) end
		end)

	addCheck(leftCard, -152, "Deduct 5% Auction House cut from Crafting Profit",
		"5% AH Cut Deduction", {
			"Subtracts the standard 5% faction Auction House consignment fee from calculated crafting and resale profits.",
		},
		function() return not _G.MerchantMasterDB or _G.MerchantMasterDB.applyAHCut ~= false end,
		function(on)
			_G.MerchantMasterDB.applyAHCut = on
			if ns.app and ns.app.refresh then ns.app.refresh() end
		end)

	local coldFilterCheck = addCheck(leftCard, -184, "Leveling guide: Smart filter not to use cold items (< 0.05x Hotness)",
		"Leveling guide: Smart filter not to use cold items", {
			"When checked, Professor Leveling Smart mode blocks Cold (< 0.05x Hotness) crafts from AH resale valuation and falls back to Vendor/DE.",
			"Uncheck to permit a small demand-capped AH resale allowance on Cold leveling crafts.",
		},
		function() return not _G.MerchantMasterDB or _G.MerchantMasterDB.smartFilterColdItems ~= false end,
		function(on)
			_G.MerchantMasterDB.smartFilterColdItems = on
			if ns.MP and ns.MP.InvalidateSolveCache then ns.MP.InvalidateSolveCache() end
			if ns.app and ns.app.refresh then ns.app.refresh() end
		end)

	local mailShortcutBtn = createButton(leftCard, "Mail Recipients & Safety ->", 210, 24, { variant = "secondary", fontSize = 11 })
	mailShortcutBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -224)
	mailShortcutBtn:SetScript("OnClick", function()
		if ns.app and type(ns.app.setTab) == "function" then
			ns.app.setTab("console_mail")
		else
			UI.Show("console_mail")
		end
	end)
	attachTooltip(mailShortcutBtn, "Mail Recipients & Safety", {
		"Configure per-economy Bank, Investment Storage, Auction, Main Crafter, and Profession mail recipients.",
		"Customize mailbox quick-pick buttons and the unsaved-recipient confirmation popup.",
	})

	local tooltipShortcutBtn = createButton(leftCard, "Tooltip Setup ->", 156, 24, { variant = "secondary", fontSize = 11 })
	tooltipShortcutBtn:SetPoint("LEFT", mailShortcutBtn, "RIGHT", 8, 0)
	tooltipShortcutBtn:SetScript("OnClick", function()
		if ns.app and type(ns.app.setTab) == "function" then
			ns.app.setTab("console_tooltips")
		else
			UI.Show("console_tooltips")
		end
	end)
	attachTooltip(tooltipShortcutBtn, "Tooltip Setup", {
		"Customize item tooltip sections, price format, modifier key, and preview live examples.",
	})

	local leftNote = makeFs(leftCard, 11, "regular", "textSecondary")
	leftNote:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 14, 14)
	leftNote:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -14, 14)
	if leftNote.SetWordWrap then leftNote:SetWordWrap(true) end
	leftNote:SetText("All settings sync with Interface -> AddOns -> MerchantMaster. See 'Addon UI' for themes and table styles, and 'Data & Maintenance' for cleanup actions.")

	-- Right card: Inventory, Character & Item Tooltip checkboxes
	addCheck(rightCard, -50, "Include items in mail",
		"Inventory: Include Mail", {
			"Counts materials sitting in your cached mailbox when computing craftable items and Shopping List gaps.",
		},
		function() return _G.MerchantMasterDB and _G.MerchantMasterDB.includeMail == true end,
		function(on)
			_G.MerchantMasterDB.includeMail = on
			if ns.app and ns.app.mapPinsProvider and type(ns.app.mapPinsProvider.OnEvent) == "function" then
				ns.app.mapPinsProvider.OnEvent("HOST_CONTEXT_CHANGED")
			end
			if ns.app then
				if ns.app.invalidateRecipeStats then ns.app.invalidateRecipeStats("ownership") end
				if ns.app.ui and ns.app.ui.includeMail then ns.app.ui.includeMail:SetChecked(on) end
				if ns.app.refresh then ns.app.refresh() end
			end
		end)

	addCheck(rightCard, -82, "Include items in bank",
		"Inventory: Include Bank", {
			"Counts items stored in your personal bank when calculating owned materials.",
		},
		function() return _G.MerchantMasterDB and _G.MerchantMasterDB.includeBank == true end,
		function(on)
			_G.MerchantMasterDB.includeBank = on
			if ns.app and ns.app.mapPinsProvider and type(ns.app.mapPinsProvider.OnEvent) == "function" then
				ns.app.mapPinsProvider.OnEvent("HOST_CONTEXT_CHANGED")
			end
			if ns.app then
				if ns.app.invalidateRecipeStats then ns.app.invalidateRecipeStats("ownership") end
				if ns.app.ui and ns.app.ui.includeBank then ns.app.ui.includeBank:SetChecked(on) end
				if ns.app.refresh then ns.app.refresh() end
			end
		end)

	addCheck(rightCard, -114, "Include items on alts",
		"Inventory: Include Alts", {
			"Counts materials across your other characters in the same economy when planning purchases.",
		},
		function() return _G.MerchantMasterDB and _G.MerchantMasterDB.includeAlts == true end,
		function(on)
			_G.MerchantMasterDB.includeAlts = on
			if ns.app and ns.app.mapPinsProvider and type(ns.app.mapPinsProvider.OnEvent) == "function" then
				ns.app.mapPinsProvider.OnEvent("HOST_CONTEXT_CHANGED")
			end
			if ns.app then
				if ns.app.invalidateRecipeStats then ns.app.invalidateRecipeStats("ownership") end
				if ns.app.ui and ns.app.ui.includeAlts then ns.app.ui.includeAlts:SetChecked(on) end
				if ns.app.refresh then ns.app.refresh() end
			end
		end)

	addCheck(rightCard, -146, "Craftable Now: include recipes learned on all characters",
		"All-Character Craft Scope", {
			"When filtering to Known Recipes ('Craftable Now'), shows recipes learned on any alt in your active economy and labels which alt crafts them.",
		},
		function() return _G.MerchantMasterDB and _G.MerchantMasterDB.craftableAllChars == true end,
		function(on)
			if ns.app and ns.app.setCraftableAllChars then ns.app.setCraftableAllChars(on) end
		end)

	addCheck(rightCard, -184, "Show Waylaid Crate cost & reputation tooltip on hover",
		"Waylaid Crate Tooltips", {
			"Adds cheapest fill options, Shopping List cost, and reputation/favor reward details when hovering Waylaid Crates.",
		},
		function() return ns.IsCrateTooltipEnabled and ns.IsCrateTooltipEnabled() == true end,
		function(on)
			if ns.app and ns.app.setCrateTooltips then ns.app.setCrateTooltips(on) end
		end)

	addCheck(rightCard, -216, "Show Craft Cost in item tooltips",
		"Tooltip: Craft Cost", {
			"Shows reagent craft cost for known/catalog items right inside WoW item hover tooltips.",
		},
		function() return ns.IsTooltipCraftCostEnabled and ns.IsTooltipCraftCostEnabled() == true end,
		function(on)
			if ns.app and ns.app.setTooltipCraftCost then ns.app.setTooltipCraftCost(on) end
		end)

	addCheck(rightCard, -248, "Show Disenchant Value in item tooltips",
		"Tooltip: Disenchant Value", {
			"Shows expected Disenchant value for BoE/BoP gear inside WoW item hover tooltips.",
		},
		function() return ns.IsTooltipDEValueEnabled and ns.IsTooltipDEValueEnabled() == true end,
		function(on)
			if ns.app and ns.app.setTooltipDEValue then ns.app.setTooltipDEValue(on) end
		end)

	state.settingsControls = {
		econBtn = econBtn,
		sourceBtn = sourceBtn,
		minimapCheck = minimapCheck,
		coldFilterCheck = coldFilterCheck,
		mailShortcutBtn = mailShortcutBtn,
		tooltipShortcutBtn = tooltipShortcutBtn,
		checks = sv.checks,
	}

	function sv.sync()
		local econLabel = (ns.CurrentEconomyInfo and ns.CurrentEconomyInfo().buttonLabel) or "Normal-Horde"
		local srcLabel = (ns.CurrentSourceInfo and ns.CurrentSourceInfo().label) or "Auto"
		setButtonLabel(econBtn, "Economy: " .. econLabel)
		setButtonLabel(sourceBtn, "Price Source: " .. srcLabel)
		for _, cb in ipairs(sv.checks) do
			if cb.SetChecked and cb._get then
				cb:SetChecked(cb._get() == true)
			end
		end
	end

	function sv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		leftCard:SetWidth(max(420, floor((w - 10) * 0.50)))
	end

	function sv.refresh()
		sv.sync()
	end

	return sv
end

---------------------------------------------------------------------------------------------------
-- Sub-View 6: Mail Recipients & Send Safety Net (console_mail)
---------------------------------------------------------------------------------------------------

local function buildMailView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local mv = {
		frame = frame,
		inputs = {},
		pickBtns = {},
		coreRows = {},
		profCells = {},
		previewChips = {},
		syncing = false,
	}

	local function getMH()
		return type(ns.MailHelper) == "table" and ns.MailHelper or nil
	end

	local function getActiveEconLabel()
		if type(ns.CurrentEconomyInfo) == "function" then
			local info = ns.CurrentEconomyInfo()
			if type(info) == "table" and type(info.key) == "string" and info.key ~= "" then
				return info.key
			end
		end
		if type(ns.DetectActiveEconomy) == "function" then
			local e = ns.DetectActiveEconomy()
			if type(e) == "string" and e ~= "" then return e end
		end
		return "Normal-Horde"
	end

	local function getSelfCharName()
		if type(ns.GetPlayerFullName) == "function" then
			local ok, full = pcall(ns.GetPlayerFullName)
			if ok and type(full) == "string" and full ~= "" then return full end
		end
		if type(_G.UnitName) == "function" then
			local n = _G.UnitName("player")
			if type(n) == "string" and n ~= "" then return n end
		end
		if ns.app and type(ns.app.char) == "table" and type(ns.app.char.name) == "string" then
			return ns.app.char.name
		end
		return ""
	end

	local function syncClearBtn(box)
		if box and box._mmClearBtn then
			local txt = (box.GetText and box:GetText()) or ""
			box._mmClearBtn:SetShown(txt ~= "")
		end
	end

	local function createPresetEditBox(hostParent, roleKey, defaultW)
		local box = CreateFrame("EditBox", nil, hostParent)
		box:SetSize(defaultW or 172, 22)
		if box.SetAutoFocus then box:SetAutoFocus(false) end
		local T = getTheme()
		if T and type(T.StyleEditBox) == "function" then
			T.StyleEditBox(box, { pill = false, border = true, fontSize = 11, leftInset = 6, withClear = true })
		else
			applyFont(box, 11, "regular")
			registerThemedFs(box, "text")
		end
		local function commitBox(self)
			if mv.syncing then return end
			local txt = (self.GetText and self:GetText()) or ""
			syncClearBtn(self)
			local MH = getMH()
			if MH and type(MH.SetPresetCharacter) == "function" then
				MH.SetPresetCharacter(roleKey, txt)
			end
			mv.renderPreview()
		end
		if box.SetScript then
			box:SetScript("OnEscapePressed", function(self)
				if self.ClearFocus then self:ClearFocus() end
			end)
			box:SetScript("OnEnterPressed", function(self)
				if self.ClearFocus then self:ClearFocus() end
				commitBox(self)
			end)
			box:SetScript("OnEditFocusLost", function(self)
				commitBox(self)
			end)
			box:SetScript("OnTextChanged", function(self, isUser)
				syncClearBtn(self)
				if isUser and not mv.syncing then
					commitBox(self)
				end
			end)
		end
		if box._mmClearBtn and type(box._mmClearBtn.HookScript) == "function" then
			box._mmClearBtn:HookScript("OnClick", function()
				syncClearBtn(box)
				local MH = getMH()
				if MH and type(MH.SetPresetCharacter) == "function" then
					MH.SetPresetCharacter(roleKey, "")
				end
				mv.renderPreview()
			end)
		end
		return box
	end

	local function openKnownCharPicker(ownerBtn, roleKey, box)
		local T = getTheme()
		local MH = getMH()
		local selfName = getSelfCharName()
		local normSelf = (MH and MH.NormalizeCharacterName) and MH.NormalizeCharacterName(selfName) or selfName
		local opts = {}
		local seenKeys = {}
		if normSelf and normSelf ~= "" then
			local sk = string.lower(normSelf)
			seenKeys[sk] = true
			opts[#opts + 1] = { key = normSelf, label = "Use This Character (" .. normSelf .. ")" }
		end
		local known = (MH and type(MH.GetKnownEconomyCharacters) == "function") and MH.GetKnownEconomyCharacters() or {}
		for _, ch in ipairs(known) do
			if ch and type(ch.name) == "string" and ch.name ~= "" then
				local ck = string.lower(ch.name)
				if not seenKeys[ck] then
					seenKeys[ck] = true
					opts[#opts + 1] = { key = ch.name, label = ch.name }
				end
			end
		end
		opts[#opts + 1] = { key = "__CLEAR__", label = "(Clear)" }

		local function onPick(val)
			local chosen = (val == "__CLEAR__") and "" or tostring(val or "")
			mv.syncing = true
			if box and box.SetText then box:SetText(chosen) end
			mv.syncing = false
			syncClearBtn(box)
			if MH and type(MH.SetPresetCharacter) == "function" then
				MH.SetPresetCharacter(roleKey, chosen)
			end
			mv.renderPreview()
		end

		if T and type(T.OpenDropDown) == "function" then
			local curVal = (box and box.GetText and box:GetText()) or ""
			T.OpenDropDown(ownerBtn, opts, curVal, onPick, 210)
		elseif normSelf and normSelf ~= "" then
			onPick(normSelf)
		end
	end

	-- Left Card (60%): Preset Mail Characters
	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(580)
	mv.leftCard = leftCard

	local titleFs = makeFs(leftCard, 13, "semibold", "text")
	titleFs:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -12)
	titleFs:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -12)
	titleFs:SetText("Preset Mail Characters (" .. getActiveEconLabel() .. ")")
	mv.titleFs = titleFs

	local subFs = makeFs(leftCard, 11, "regular", "textSecondary")
	subFs:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -30)
	subFs:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -30)
	subFs:SetText("Saved per economy. Supports WoW Forever first + last names (e.g. 'First Last').")
	mv.subFs = subFs

	local coreSpecs = {
		{ key = "bank",              label = "Bank Character",     icon = 133784 },
		{ key = "investmentStorage", label = "Investment Storage", icon = 133786 },
		{ key = "auction",           label = "Auction Character",  icon = 133785 },
		{ key = "mainCrafter",       label = "Main Crafter",       icon = 136241 },
	}
	for i, spec in ipairs(coreSpecs) do
		local yOff = -(50 + (i - 1) * 27)
		local row = CreateFrame("Frame", nil, leftCard)
		row:SetHeight(24)
		row:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, yOff)
		row:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, yOff)

		local ico = row:CreateTexture(nil, "ARTWORK")
		ico:SetSize(16, 16)
		ico:SetPoint("LEFT", row, "LEFT", 0, 0)
		ico:SetTexture(spec.icon)
		ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local lbl = makeFs(row, 11, "semibold", "text")
		lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
		lbl:SetWidth(122)
		lbl:SetText(spec.label)

		local box = createPresetEditBox(row, spec.key, 240)
		box:SetPoint("LEFT", lbl, "RIGHT", 6, 0)

		local pickBtn = createButton(row, "Pick", 64, 22, { dropdown = true, fontSize = 11 })
		pickBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		pickBtn:SetScript("OnClick", function(self)
			openKnownCharPicker(self, spec.key, box)
		end)
		attachTooltip(pickBtn, "Pick Character", {
			"Choose 'Use This Character' or any known character in your active economy.",
		})

		mv.inputs[spec.key] = box
		mv.pickBtns[spec.key] = pickBtn
		mv.coreRows[i] = { frame = row, box = box, pickBtn = pickBtn, key = spec.key }
	end

	local profSep = createSeparator(leftCard)
	profSep:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -162)
	profSep:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -12, -162)

	local profTitle = makeFs(leftCard, 12, "semibold", "text")
	profTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -170)
	profTitle:SetText("Profession Characters")

	local profSpecs = {
		{ key = "alchemy",        label = "Alchemy",        icon = 136240 },
		{ key = "blacksmithing",  label = "Blacksmithing",  icon = 136241 },
		{ key = "enchanting",     label = "Enchanting",     icon = 136244 },
		{ key = "engineering",    label = "Engineering",    icon = 136243 },
		{ key = "leatherworking", label = "Leatherworking", icon = 136247 },
		{ key = "tailoring",      label = "Tailoring",      icon = 136249 },
		{ key = "cooking",        label = "Cooking",        icon = 133971 },
		{ key = "firstaid",       label = "First Aid",      icon = 135966 },
	}
	for i, spec in ipairs(profSpecs) do
		local col = (i - 1) % 2
		local rowIdx = floor((i - 1) / 2)
		local cell = CreateFrame("Frame", nil, leftCard)
		cell:SetHeight(44)
		cell:SetWidth(250)

		local ico = cell:CreateTexture(nil, "ARTWORK")
		ico:SetSize(14, 14)
		ico:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -1)
		ico:SetTexture(spec.icon)
		ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local lbl = makeFs(cell, 11, "semibold", "textSecondary")
		lbl:SetPoint("LEFT", ico, "RIGHT", 5, 0)
		lbl:SetText(spec.label)

		local box = createPresetEditBox(cell, spec.key, 172)
		box:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -18)

		local pickBtn = createButton(cell, "Pick", 62, 22, { dropdown = true, fontSize = 10 })
		pickBtn:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, -18)
		pickBtn:SetScript("OnClick", function(self)
			openKnownCharPicker(self, spec.key, box)
		end)
		attachTooltip(pickBtn, "Pick " .. spec.label .. " Alt", {
			"Choose 'Use This Character' or any known character in your active economy.",
		})

		mv.inputs[spec.key] = box
		mv.pickBtns[spec.key] = pickBtn
		mv.profCells[i] = { frame = cell, col = col, row = rowIdx, box = box, pickBtn = pickBtn, key = spec.key }
	end

	local leftNote = makeFs(leftCard, 11, "regular", "textSecondary")
	leftNote:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 14, 12)
	leftNote:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -14, 12)
	if leftNote.SetWordWrap then leftNote:SetWordWrap(true) end
	leftNote:SetText("Assigning the same character to multiple roles automatically combines them into one mailbox button.")

	-- Right Card (40%): Mailbox Quick-Pick Options, Safety Net & Live Preview Strip
	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	mv.rightCard = rightCard

	local dispTitle = makeFs(rightCard, 13, "semibold", "text")
	dispTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -12)
	dispTitle:SetText("Mailbox Quick-Pick Buttons")

	local function makeDispCheck(yOff, label, optKey, tipTitle, tipLines)
		local cb = createCheck(rightCard, label, 11, function(_, on)
			local MH = getMH()
			if MH and type(MH.SetDisplayOption) == "function" then
				MH.SetDisplayOption(optKey, on)
			end
			mv.renderPreview()
		end)
		cb:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, yOff)
		if cb.label then
			cb.label:SetPoint("RIGHT", rightCard, "RIGHT", -14, 0)
			if cb.label.SetWordWrap then cb.label:SetWordWrap(true) end
		end
		if tipTitle then
			attachTooltip(cb, tipTitle, tipLines)
		end
		return cb
	end

	mv.showIconCheck = makeDispCheck(-38, "Show role icon", "showIcon", "Show Role Icon", {
		"Displays the primary role icon (Bank, Auction, Main Crafter, or Profession) on each mailbox button.",
	})
	mv.showNameCheck = makeDispCheck(-66, "Show character name", "showName", "Show Character Name", {
		"Displays the recipient's character name on each mailbox button.",
	})
	mv.showRoleCheck = makeDispCheck(-94, "Show role label", "showRole", "Show Role Label", {
		"Displays the saved role label (e.g. 'Bank / Auction') on each mailbox button.",
	})

	local dispHint = makeFs(rightCard, 10, "regular", "textSecondary")
	dispHint:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -120)
	dispHint:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -120)
	dispHint:SetText("If all 3 are unchecked, buttons display 2-letter initials.")

	local rSep1 = createSeparator(rightCard)
	rSep1:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -140)
	rSep1:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -140)

	local safetyTitle = makeFs(rightCard, 13, "semibold", "text")
	safetyTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -150)
	safetyTitle:SetText("Send Mail Safety Net")

	mv.warnUnsavedCheck = makeDispCheck(-176, "Confirm before mailing items to a character not saved here", "warnUnsaved",
		"Unsaved Recipient Confirmation", {
			"Shows a confirmation popup before sending mail with attached items to any character not listed on the left.",
			"Gold-only or text-only mail always sends without a popup.",
		})

	local safetyCaption = makeFs(rightCard, 11, "regular", "textSecondary")
	safetyCaption:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 40, -210)
	safetyCaption:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -210)
	if safetyCaption.SetWordWrap then safetyCaption:SetWordWrap(true) end
	safetyCaption:SetText("Gold-only or text-only mail sends without a popup.")
	mv.safetyCaption = safetyCaption

	local rSep2 = createSeparator(rightCard)
	rSep2:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -238)
	rSep2:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -238)

	local prevTitle = makeFs(rightCard, 12, "semibold", "text")
	prevTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -248)
	prevTitle:SetText("Live Mailbox Preview")

	local previewModeFs = makeFs(rightCard, 10, "regular", "textBlue", "RIGHT")
	previewModeFs:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -249)
	previewModeFs:SetText("Sample preview")
	mv.previewModeFs = previewModeFs

	local previewCard = createSurfaceCard(rightCard, "glass_r8", "cardAltBg")
	previewCard:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -270)
	previewCard:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)
	mv.previewCard = previewCard

	local prevStatusFs = makeFs(previewCard, 10, "semibold", "textSecondary")
	prevStatusFs:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 10, -8)
	prevStatusFs:SetPoint("TOPRIGHT", previewCard, "TOPRIGHT", -10, -8)
	mv.prevStatusFs = prevStatusFs

	for i = 1, 5 do
		local chip = CreateFrame("Frame", nil, previewCard)
		chip:SetHeight(32)
		chip:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 10, -(28 + (i - 1) * 35))
		chip:SetPoint("TOPRIGHT", previewCard, "TOPRIGHT", -10, -(28 + (i - 1) * 35))
		local cbg = chip:CreateTexture(nil, "BACKGROUND")
		if cbg.SetAllPoints then cbg:SetAllPoints(chip) else cbg:SetPoint("TOPLEFT", chip, "TOPLEFT", 0, 0) end
		chip.bg = cbg

		local ico = chip:CreateTexture(nil, "ARTWORK")
		ico:SetSize(16, 16)
		ico:SetPoint("LEFT", chip, "LEFT", 7, 0)
		ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		chip.iconTex = ico

		local nameFs = makeFs(chip, 11, "semibold", "text")
		if nameFs.SetWordWrap then nameFs:SetWordWrap(false) end
		chip.nameFs = nameFs

		local roleFs = makeFs(chip, 10, "regular", "textSecondary")
		if roleFs.SetWordWrap then roleFs:SetWordWrap(false) end
		chip.roleFs = roleFs

		local initFs = makeFs(chip, 11, "semibold", "text", "CENTER")
		initFs:SetPoint("CENTER", chip, "CENTER", 0, 0)
		initFs:Hide()
		chip.initFs = initFs

		chip:Hide()
		mv.previewChips[i] = chip
	end

	local SAMPLE_PREVIEW = {
		{ name = "Goldbank",    roleLabel = "Bank / Auction", icon = 133784, initials = "GB", isSelf = false },
		{ name = "Elara Vance", roleLabel = "Alchemy",        icon = 136240, initials = "EV", isSelf = false },
	}

	function mv.renderPreview()
		local MH = getMH()
		local pal = getPal()
		local disp = (MH and type(MH.GetDisplayOptions) == "function" and MH.GetDisplayOptions())
			or { showIcon = true, showName = true, showRole = true, warnUnsaved = true }
		local liveEntries = (MH and type(MH.BuildPresetRecipientEntries) == "function" and MH.BuildPresetRecipientEntries()) or {}
		local isSample = (#liveEntries == 0)
		local list = isSample and SAMPLE_PREVIEW or liveEntries

		if mv.previewModeFs then
			mv.previewModeFs:SetText(isSample and "Sample preview (0 saved)" or format("%d saved preset(s)", #liveEntries))
		end
		if mv.prevStatusFs then
			if disp.warnUnsaved then
				mv.prevStatusFs:SetText("Safety Net: " .. colorHex("hexGreen", "ON", pal) .. "  |  Unsaved items prompt before send")
			else
				mv.prevStatusFs:SetText("Safety Net: " .. colorHex("hexWarning", "OFF", pal) .. "  |  No popup on unsaved recipients")
			end
		end

		local showIcon = disp.showIcon == true
		local showName = disp.showName == true
		local showRole = disp.showRole == true
		local initialsOnly = (not showIcon) and (not showName) and (not showRole)

		for i = 1, #mv.previewChips do
			local chip = mv.previewChips[i]
			local entry = list[i]
			if entry then
				chip:Show()
				if chip.bg and chip.bg.SetColorTexture then
					local bgCol = pal.cardBg or { 0.17, 0.17, 0.18, 1 }
					chip.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], 0.92)
				end
				if initialsOnly then
					chip.iconTex:Hide()
					chip.nameFs:Hide()
					chip.roleFs:Hide()
					chip.initFs:Show()
					chip.initFs:SetText(entry.initials or "??")
				else
					chip.initFs:Hide()
					local leftX = 8
					if showIcon then
						chip.iconTex:Show()
						chip.iconTex:SetTexture(entry.icon)
						leftX = 28
					else
						chip.iconTex:Hide()
					end
					if showName then
						chip.nameFs:Show()
						chip.nameFs:ClearAllPoints()
						if showRole then
							chip.nameFs:SetPoint("TOPLEFT", chip, "TOPLEFT", leftX, -4)
							chip.nameFs:SetPoint("TOPRIGHT", chip, "TOPRIGHT", -8, -4)
						else
							chip.nameFs:SetPoint("LEFT", chip, "LEFT", leftX, 0)
							chip.nameFs:SetPoint("RIGHT", chip, "RIGHT", -8, 0)
						end
						chip.nameFs:SetText(entry.isSelf and (entry.name .. " (You)") or entry.name)
					else
						chip.nameFs:Hide()
					end
					if showRole then
						chip.roleFs:Show()
						chip.roleFs:ClearAllPoints()
						if showName then
							chip.roleFs:SetPoint("BOTTOMLEFT", chip, "BOTTOMLEFT", leftX, 4)
							chip.roleFs:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -8, 4)
						else
							chip.roleFs:SetPoint("LEFT", chip, "LEFT", leftX, 0)
							chip.roleFs:SetPoint("RIGHT", chip, "RIGHT", -8, 0)
						end
						chip.roleFs:SetText(entry.roleLabel or "")
					else
						chip.roleFs:Hide()
					end
				end
			else
				chip:Hide()
			end
		end
	end

	function mv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		local leftW = max(460, floor((w - 10) * 0.60))
		leftCard:SetWidth(leftW)

		local innerW = max(430, leftW - 28)
		local coreBoxW = max(148, innerW - 146 - 92)
		for _, r in ipairs(mv.coreRows) do
			if r.box and r.box.SetWidth then
				r.box:SetWidth(coreBoxW)
			end
		end

		local colGap = 14
		local cellW = max(210, floor((innerW - colGap) / 2))
		local profBoxW = max(126, cellW - 90)
		for _, c in ipairs(mv.profCells) do
			c.frame:ClearAllPoints()
			c.frame:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14 + c.col * (cellW + colGap), -(190 + c.row * 46))
			c.frame:SetWidth(cellW)
			if c.box and c.box.SetWidth then
				c.box:SetWidth(profBoxW)
			end
		end
	end

	function mv.sync()
		local MH = getMH()
		mv.titleFs:SetText("Preset Mail Characters (" .. getActiveEconLabel() .. ")")
		local econ = (MH and type(MH.GetActiveEconPresets) == "function" and MH.GetActiveEconPresets()) or {}
		local disp = (MH and type(MH.GetDisplayOptions) == "function" and MH.GetDisplayOptions())
			or { showIcon = true, showName = true, showRole = true, warnUnsaved = true }

		mv.syncing = true
		for _, k in ipairs({ "bank", "investmentStorage", "auction", "mainCrafter" }) do
			local box = mv.inputs[k]
			if box and box.SetText then
				box:SetText(type(econ[k]) == "string" and econ[k] or "")
				syncClearBtn(box)
			end
		end
		local profs = type(econ.professions) == "table" and econ.professions or {}
		for _, pk in ipairs({ "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "cooking", "firstaid" }) do
			local box = mv.inputs[pk]
			if box and box.SetText then
				box:SetText(type(profs[pk]) == "string" and profs[pk] or "")
				syncClearBtn(box)
			end
		end
		mv.syncing = false

		if mv.showIconCheck and mv.showIconCheck.SetChecked then mv.showIconCheck:SetChecked(disp.showIcon == true) end
		if mv.showNameCheck and mv.showNameCheck.SetChecked then mv.showNameCheck:SetChecked(disp.showName == true) end
		if mv.showRoleCheck and mv.showRoleCheck.SetChecked then mv.showRoleCheck:SetChecked(disp.showRole == true) end
		if mv.warnUnsavedCheck and mv.warnUnsavedCheck.SetChecked then mv.warnUnsavedCheck:SetChecked(disp.warnUnsaved == true) end

		mv.renderPreview()
	end

	function mv.retheme()
		mv.renderPreview()
	end

	function mv.refresh()
		mv.sync()
	end

	state.mailControls = mv
	return mv
end

---------------------------------------------------------------------------------------------------
-- Sub-View 7: Tooltip Setup & Live Example Preview (console_tooltips)
---------------------------------------------------------------------------------------------------

local TOOLTIP_FALLBACK_DEFAULTS = {
	ttEnabled = true,
	ttPriceFormat = "colored",
	ttModifier = "none",
	ttMarketEnabled = true,
	ttMinBuyout = true,
	ttMarketValue = true,
	ttListedCount = true,
	ttVendorSell = false,
	tooltipCraftCost = false,
	ttCraftProfit = true,
	tooltipDEValue = true,
	ttDEArcaneSalvager = true,
	tooltipDEBreakdown = true,
	crateTooltips = true,
	anTooltips = true,
	ttAccSell = true,
	ttAccBasis = true,
	ttAccProfit = true,
	ttAccLastSold = true,
	ttAccSaleRate = true,
	ttAccSlowing = true,
	ttHideEmpty = true,
	anTooltipInventory = true,
	ttInvByChar = true,
	ttInvHideZero = true,
	ttInvCompact = true,
}

local TOOLTIP_SECTIONS = {
	{
		title = "Market & Pricing",
		items = {
			{ key = "ttMarketEnabled", label = "Show Market & Pricing section", tip = "Master switch for live AH and market price lines in item hover tooltips." },
			{ key = "ttMinBuyout",     label = "Min Buyout (AH lowest)", indent = true, parentKey = "ttMarketEnabled", tip = "Shows the lowest current Auction House buyout price." },
			{ key = "ttMarketValue",   label = "Market Value (14d / Region)", indent = true, parentKey = "ttMarketEnabled", tip = "Shows historical or snapshot Market Value alongside Min Buyout." },
			{ key = "ttListedCount",   label = "Listed count & scan age", indent = true, parentKey = "ttMarketEnabled", tip = "Shows active AH listing count and how recently prices were scanned." },
			{ key = "ttVendorSell",    label = "Vendor Sell price", indent = true, parentKey = "ttMarketEnabled", tip = "Shows MerchantMaster vendor sell reference line inside the Market section." },
		},
	},
	{
		title = "Crafting & Disenchant",
		items = {
			{ key = "tooltipCraftCost",   label = "Craft Cost (cheapest reagents)", tip = "Shows reagent crafting cost for known and catalog recipes on hover." },
			{ key = "ttCraftProfit",      label = "Craft Profit & margin", indent = true, parentKey = "tooltipCraftCost", tip = "Shows expected net profit after AH fee when Craft Cost is enabled." },
			{ key = "tooltipDEValue",     label = "Disenchant Value", tip = "Shows expected disenchant value for eligible gear inside tooltips." },
			{ key = "ttDEArcaneSalvager", label = "Arcane Salvager (+20% bonus)", indent = true, parentKey = "tooltipDEValue", tip = "Shows boosted disenchant value with the +20% Arcane Salvager perk." },
			{ key = "tooltipDEBreakdown", label = "DE material breakdown", indent = true, parentKey = "tooltipDEValue", tip = "Lists individual dust, essence, and shard drop odds under Disenchant Value." },
			{ key = "crateTooltips",      label = "Waylaid Crate fill cost & rep", tip = "Shows cheapest crate fill, Shopping List cost, and reputation/favor details." },
		},
	},
	{
		title = "Accounting",
		items = {
			{ key = "anTooltips",    label = "Show Accounting section", tip = "Master switch for personal sales, cost basis, and profit history in tooltips." },
			{ key = "ttAccSell",     label = "Avg Sell & Min / Max Sell", indent = true, parentKey = "anTooltips", tip = "Shows your average, minimum, and maximum historical sale prices." },
			{ key = "ttAccBasis",    label = "Avg Buy & Current Basis", indent = true, parentKey = "anTooltips", tip = "Shows your average buy cost and remaining FIFO inventory cost basis." },
			{ key = "ttAccProfit",   label = "Avg Profit", indent = true, parentKey = "anTooltips", tip = "Shows your realized average profit per unit sold." },
			{ key = "ttAccLastSold", label = "Last Sold price", indent = true, parentKey = "anTooltips", tip = "Shows the unit price of your most recent recorded sale." },
			{ key = "ttAccSaleRate", label = "Sale Rate & Expires", indent = true, parentKey = "anTooltips", tip = "Shows historical sell-through percentage and expired auctions count." },
			{ key = "ttAccSlowing",  label = "Slowing / Over-listed alert", indent = true, parentKey = "anTooltips", tip = "Highlights items with repeated expires that need a price review." },
			{ key = "ttHideEmpty",   label = "Hide section when item has no history", indent = true, parentKey = "anTooltips", tip = "Suppresses the Accounting header when an item has zero recorded trades." },
		},
	},
	{
		title = "Inventory",
		items = {
			{ key = "anTooltipInventory", label = "Show Inventory section", tip = "Master switch for cross-character bag, bank, mail, and AH counts." },
			{ key = "ttInvByChar",        label = "Per-character breakdown", indent = true, parentKey = "anTooltipInventory", tip = "Lists each character's owned quantities above the Total Inventory line." },
			{ key = "ttInvHideZero",      label = "Hide zero-count alts", indent = true, parentKey = "anTooltipInventory", tip = "Omits characters that currently hold 0 of the hovered item." },
			{ key = "ttInvCompact",       label = "Compact inventory line format", indent = true, parentKey = "anTooltipInventory", tip = "Uses compact counts like '42 (12 bags, 20 bank, 0 mail, 10 AH)' instead of verbose labels." },
		},
	},
}

local function buildFallbackTooltipPreview(sampleKey, getPref)
	local on = getPref("ttEnabled") ~= false
	local dim = { 0.42, 0.45, 0.50 }
	local gold = { 1.00, 0.82, 0.00 }
	local slate = { 0.62, 0.66, 0.72 }
	local white = { 0.90, 0.92, 0.95 }
	local green = { 0.28, 0.88, 0.45 }
	local function mkRow(left, right, enabled, isHeader, rL, gL, bL, rR, gR, bR)
		local active = on and (enabled ~= false)
		if not active then
			return { left = left, right = right, rL = dim[1], gL = dim[2], bL = dim[3], rR = dim[1], gR = dim[2], bR = dim[3], enabled = false, isHeader = isHeader == true }
		end
		return {
			left = left,
			right = right,
			rL = rL or (isHeader and gold[1] or white[1]),
			gL = gL or (isHeader and gold[2] or white[2]),
			bL = bL or (isHeader and gold[3] or white[3]),
			rR = rR or (isHeader and slate[1] or white[1]),
			gR = gR or (isHeader and slate[2] or white[2]),
			bR = bR or (isHeader and slate[3] or white[3]),
			enabled = true,
			isHeader = isHeader == true,
		}
	end
	local name = "Green Lens"
	local qRGB = { 0.00, 0.44, 0.87 }
	local sub = "Item Level 48  |  Binds when equipped"
	local sell = "Sell Price: 1g 12s 40c"
	if sampleKey == "silk_cloth" then
		name = "Silk Cloth"
		qRGB = { 1.00, 1.00, 1.00 }
		sub = "Trade Goods  |  Stack: 20"
		sell = "Sell Price: 1s 50c"
	elseif sampleKey == "waylaid_crate" then
		name = "Waylaid Supplies: Bronze Bars"
		qRGB = { 0.12, 1.00, 0.00 }
		sub = "Unique  |  Requires Level 15"
		sell = ""
	end
	local mOn = getPref("ttMarketEnabled") ~= false
	local cOn = getPref("tooltipCraftCost") == true
	local deOn = getPref("tooltipDEValue") ~= false
	local aOn = getPref("anTooltips") ~= false
	local iOn = getPref("anTooltipInventory") ~= false
	return {
		header = { name = name, qualityRGB = qRGB, subtitle = sub, sellPrice = sell },
		rows = {
			mkRow("MerchantMaster Market", "(Live AH)", mOn, true),
			mkRow("  Min Buyout", "18g 45s", mOn and getPref("ttMinBuyout") ~= false, false),
			mkRow("  Market Value", "21g 20s", mOn and getPref("ttMarketValue") ~= false, false),
			mkRow("  Listed", "7 (4m ago)", mOn and getPref("ttListedCount") ~= false, false),
			mkRow("MerchantMaster Craft & DE", "", cOn or deOn, true),
			mkRow("  Craft Cost", "11g 30s", cOn, false),
			mkRow("  Craft Profit", "+6g 22s (+55%)", cOn and getPref("ttCraftProfit") ~= false, false, white[1], white[2], white[3], green[1], green[2], green[3]),
			mkRow("  Disenchant Value", "4g 85s", deOn, false),
			mkRow("MerchantMaster Accounting", "(per 1)", aOn, true),
			mkRow("  Avg Sell", "19g 90s", aOn and getPref("ttAccSell") ~= false, false),
			mkRow("  Avg Profit", "+7g 60s", aOn and getPref("ttAccProfit") ~= false, false, white[1], white[2], white[3], green[1], green[2], green[3]),
			mkRow("MerchantMaster Inventory", "4 total", iOn, true),
			mkRow("  Total Inventory", "4", iOn, false),
		},
	}
end

local function buildTooltipsView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local tv = {
		frame = frame,
		checks = {},
		checkMeta = {},
		sampleBtns = {},
		presetBtns = {},
		formatBtns = {},
		modBtns = {},
		previewRows = {},
		sectionHeaders = {},
	}

	local function getTP()
		return type(ns.TooltipPrefs) == "table" and ns.TooltipPrefs or nil
	end

	local function getPref(key)
		local TP = getTP()
		if TP and type(TP.Get) == "function" then
			return TP.Get(key)
		end
		if _G.MerchantMasterDB and _G.MerchantMasterDB[key] ~= nil then
			return _G.MerchantMasterDB[key]
		end
		return TOOLTIP_FALLBACK_DEFAULTS[key]
	end

	local function syncExternalControls()
		if ns.app and ns.app.ui then
			local crateOn = getPref("crateTooltips") == true
			if ns.app.ui.optCrateTooltipCheck and ns.app.ui.optCrateTooltipCheck.SetChecked then
				ns.app.ui.optCrateTooltipCheck:SetChecked(crateOn)
			end
			if ns.app.ui.crateTooltipCheck and ns.app.ui.crateTooltipCheck.SetChecked then
				ns.app.ui.crateTooltipCheck:SetChecked(crateOn)
			end
		end
	end

	local function setPref(key, val)
		local TP = getTP()
		if TP and type(TP.Set) == "function" then
			TP.Set(key, val)
		else
			if not _G.MerchantMasterDB then _G.MerchantMasterDB = {} end
			_G.MerchantMasterDB[key] = val
			if ns.InvalidateMarketTooltipCache then ns.InvalidateMarketTooltipCache() end
			if ns.InvalidateEconTooltipCache then ns.InvalidateEconTooltipCache() end
			if ns.InvalidateCrateTooltipCache then ns.InvalidateCrateTooltipCache() end
		end
		syncExternalControls()
		UI.SyncSettings()
		if not state.built then
			tv.sync()
		end
	end

	local function applyPreset(name)
		local TP = getTP()
		if TP and type(TP.ApplyPreset) == "function" then
			TP.ApplyPreset(name)
		else
			if not _G.MerchantMasterDB then _G.MerchantMasterDB = {} end
			if name == "all" then
				for k, v in pairs(TOOLTIP_FALLBACK_DEFAULTS) do
					if type(v) == "boolean" then
						_G.MerchantMasterDB[k] = true
					end
				end
			elseif name == "compact" then
				for k, v in pairs(TOOLTIP_FALLBACK_DEFAULTS) do
					_G.MerchantMasterDB[k] = v
				end
				_G.MerchantMasterDB.ttListedCount = false
				_G.MerchantMasterDB.ttVendorSell = false
				_G.MerchantMasterDB.tooltipDEBreakdown = false
				_G.MerchantMasterDB.ttAccLastSold = false
				_G.MerchantMasterDB.ttAccSaleRate = false
				_G.MerchantMasterDB.ttInvByChar = false
				_G.MerchantMasterDB.ttInvCompact = true
			else
				for k, v in pairs(TOOLTIP_FALLBACK_DEFAULTS) do
					_G.MerchantMasterDB[k] = v
				end
			end
			if ns.InvalidateMarketTooltipCache then ns.InvalidateMarketTooltipCache() end
			if ns.InvalidateEconTooltipCache then ns.InvalidateEconTooltipCache() end
			if ns.InvalidateCrateTooltipCache then ns.InvalidateCrateTooltipCache() end
		end
		syncExternalControls()
		UI.SyncSettings()
		if not state.built then
			tv.sync()
		end
	end

	-- -----------------------------------------------------------------------------------------------
	-- Top Global Options Bar (height 48px)
	-- -----------------------------------------------------------------------------------------------
	local topBar = createSurfaceCard(frame, "glass_r12", "cardBg")
	topBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	topBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	topBar:SetHeight(48)
	tv.topBar = topBar

	local masterCheck = createCheck(topBar, "Enable MM Tooltips", 11, function(_, on)
		setPref("ttEnabled", on)
	end)
	masterCheck:SetPoint("LEFT", topBar, "LEFT", 12, 0)
	attachTooltip(masterCheck, "Enable MerchantMaster Tooltips", {
		"Master switch for all MerchantMaster item tooltip additions.",
		"Turn off to hide Market, Crafting, Disenchant, Accounting, Inventory, and Crate tooltip lines.",
	})
	tv.checks.ttEnabled = masterCheck
	tv.checkMeta.ttEnabled = { key = "ttEnabled", isMaster = true }

	local vDiv1 = topBar:CreateTexture(nil, "ARTWORK")
	vDiv1:SetSize(1, 24)
	vDiv1:SetPoint("LEFT", topBar, "LEFT", 174, 0)
	state.themedSeparators[#state.themedSeparators + 1] = vDiv1

	local fmtLbl = makeFs(topBar, 10, "semibold", "textSecondary")
	fmtLbl:SetPoint("LEFT", vDiv1, "RIGHT", 6, 0)
	fmtLbl:SetText("Price:")

	do
		local fmtSpecs = {
			{ key = "colored", label = "Colored Text", w = 82 },
			{ key = "icons",   label = "Coin Icons",   w = 72 },
		}
		local prev = fmtLbl
		for idx, sp in ipairs(fmtSpecs) do
			local b = createButton(topBar, sp.label, sp.w, 22, { variant = "secondary", pill = true, fontSize = 10 })
			b:SetPoint("LEFT", prev, "RIGHT", idx == 1 and 6 or 4, 0)
			local fk = sp.key
			b:SetScript("OnClick", function()
				setPref("ttPriceFormat", fk)
			end)
			attachTooltip(b, "Tooltip Price Format: " .. sp.label, {
				fk == "icons"
					and "Renders WoW gold, silver, and copper coin textures inside tooltips."
					or "Renders compact colored g / s / c letters inside tooltips.",
			})
			tv.formatBtns[fk] = b
			prev = b
		end
	end

	local vDiv2 = topBar:CreateTexture(nil, "ARTWORK")
	vDiv2:SetSize(1, 24)
	vDiv2:SetPoint("LEFT", tv.formatBtns.icons, "RIGHT", 6, 0)
	state.themedSeparators[#state.themedSeparators + 1] = vDiv2

	local modLbl = makeFs(topBar, 10, "semibold", "textSecondary")
	modLbl:SetPoint("LEFT", vDiv2, "RIGHT", 6, 0)
	modLbl:SetText("Modifier:")

	do
		local modSpecs = {
			{ key = "none",  label = "Always", w = 50 },
			{ key = "shift", label = "Shift",  w = 42 },
			{ key = "alt",   label = "Alt",    w = 36 },
			{ key = "ctrl",  label = "Ctrl",   w = 40 },
		}
		local prev = modLbl
		for idx, sp in ipairs(modSpecs) do
			local b = createButton(topBar, sp.label, sp.w, 22, { variant = "secondary", pill = true, fontSize = 10 })
			b:SetPoint("LEFT", prev, "RIGHT", idx == 1 and 6 or 4, 0)
			local mk = sp.key
			b:SetScript("OnClick", function()
				setPref("ttModifier", mk)
			end)
			attachTooltip(b, "Tooltip Modifier: " .. sp.label, {
				mk == "none"
					and "Always shows MerchantMaster tooltip lines on hover (hold Shift to multiply by stack size)."
					or ("Only displays MerchantMaster tooltip lines while holding " .. sp.label .. "."),
			})
			tv.modBtns[mk] = b
			prev = b
		end
	end

	-- Right-aligned Preset buttons: All On, Compact, Reset
	do
		local resetBtn = createButton(topBar, "Reset", 54, 22, { variant = "secondary", fontSize = 10 })
		resetBtn:SetPoint("RIGHT", topBar, "RIGHT", -12, 0)
		resetBtn:SetScript("OnClick", function() applyPreset("reset") end)
		attachTooltip(resetBtn, "Reset Tooltip Defaults", { "Restores all tooltip options to MerchantMaster's recommended defaults." })
		tv.presetBtns.reset = resetBtn

		local compactBtn = createButton(topBar, "Compact", 64, 22, { variant = "secondary", fontSize = 10 })
		compactBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
		compactBtn:SetScript("OnClick", function() applyPreset("compact") end)
		attachTooltip(compactBtn, "Compact Preset", { "Keeps key buyout, DE, profit, and total inventory lines while hiding detailed breakdowns." })
		tv.presetBtns.compact = compactBtn

		local allBtn = createButton(topBar, "All On", 54, 22, { variant = "secondary", fontSize = 10 })
		allBtn:SetPoint("RIGHT", compactBtn, "LEFT", -4, 0)
		allBtn:SetScript("OnClick", function() applyPreset("all") end)
		attachTooltip(allBtn, "All On Preset", { "Enables every tooltip section and detail line." })
		tv.presetBtns.all = allBtn

		local preLbl = makeFs(topBar, 10, "semibold", "textSecondary")
		preLbl:SetPoint("RIGHT", allBtn, "LEFT", -6, 0)
		preLbl:SetText("Presets:")
		tv.presetLbl = preLbl
	end

	-- -----------------------------------------------------------------------------------------------
	-- Left Pane (~46%): Scrollable 4-Section Toggle List
	-- -----------------------------------------------------------------------------------------------
	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -8)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(450)
	tv.leftCard = leftCard

	local leftTitle = makeFs(leftCard, 13, "semibold", "text")
	leftTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -10)
	leftTitle:SetText("Tooltip Sections & Lines")

	local leftSub = makeFs(leftCard, 10, "regular", "textSecondary", "RIGHT")
	leftSub:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -12)
	leftSub:SetText("Changes apply immediately")

	local leftSep = createSeparator(leftCard)
	leftSep:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -32)
	leftSep:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -12, -32)

	local optScroll = CreateFrame("ScrollFrame", nil, leftCard)
	optScroll:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 6, -36)
	optScroll:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -16, 8)
	tv.optScroll = optScroll

	local optChildParent = (optScroll.SetScrollChild ~= nil) and optScroll or leftCard
	local optChild = CreateFrame("Frame", nil, optChildParent)
	optChild:SetPoint("TOPLEFT", optChildParent, "TOPLEFT", 0, 0)
	optChild:SetWidth(410)
	if optScroll.SetScrollChild then
		optScroll:SetScrollChild(optChild)
	end
	tv.optChild = optChild

	local optSb = CreateFrame("Slider", nil, leftCard)
	optSb:SetWidth(6)
	optSb:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -4, -38)
	optSb:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -4, 8)
	if optSb.SetOrientation then optSb:SetOrientation("VERTICAL") end
	if optSb.SetMinMaxValues then optSb:SetMinMaxValues(0, 0) end
	if optSb.SetValueStep then optSb:SetValueStep(20) end
	if optSb.SetValue then optSb:SetValue(0) end
	local optThumb = optSb:CreateTexture(nil, "ARTWORK")
	optThumb:SetSize(4, 32)
	optThumb:SetColorTexture(1, 1, 1, 0.30)
	if optSb.SetThumbTexture then optSb:SetThumbTexture(optThumb) end
	local T = getTheme()
	if T and type(T.SlimScrollBar) == "function" then
		T.SlimScrollBar(optSb)
	end
	if optSb.SetScript and optScroll.SetVerticalScroll then
		optSb:SetScript("OnValueChanged", function(_, val)
			if optScroll.SetVerticalScroll then optScroll:SetVerticalScroll(val or 0) end
		end)
	end
	tv.optSb = optSb

	local function syncOptScrollRange()
		if optScroll.UpdateScrollChildRect then optScroll:UpdateScrollChildRect() end
		if optScroll.GetVerticalScrollRange and optSb.SetMinMaxValues then
			local rng = max(0, optScroll:GetVerticalScrollRange() or 0)
			optSb:SetMinMaxValues(0, rng)
			if optSb.SetShown then optSb:SetShown(rng > 0) end
		end
	end

	local function onOptWheel(_, delta)
		if optScroll.GetVerticalScrollRange and optScroll.SetVerticalScroll and optScroll.GetVerticalScroll then
			local rng = max(0, optScroll:GetVerticalScrollRange() or 0)
			local cur = optScroll:GetVerticalScroll() or 0
			local nxt = max(0, min(rng, cur - delta * 32))
			optScroll:SetVerticalScroll(nxt)
			if optSb.SetMinMaxValues then optSb:SetMinMaxValues(0, rng) end
			if optSb.SetValue then optSb:SetValue(nxt) end
		end
	end
	if leftCard.EnableMouseWheel then leftCard:EnableMouseWheel(true) end
	leftCard:SetScript("OnMouseWheel", onOptWheel)
	if optScroll.EnableMouseWheel then optScroll:EnableMouseWheel(true) end
	optScroll:SetScript("OnMouseWheel", onOptWheel)

	-- Populate 4 grouped sections inside optChild
	do
		local y = 6
		for sIdx, sec in ipairs(TOOLTIP_SECTIONS) do
			if sIdx > 1 then
				local sDiv = createSeparator(optChild)
				sDiv:SetPoint("TOPLEFT", optChild, "TOPLEFT", 8, -y)
				sDiv:SetPoint("TOPRIGHT", optChild, "TOPRIGHT", -8, -y)
				y = y + 9
			end
			local hdrFs = makeFs(optChild, 11, "semibold", "textBlue")
			hdrFs:SetPoint("TOPLEFT", optChild, "TOPLEFT", 8, -y)
			hdrFs:SetText(sec.title)
			tv.sectionHeaders[sIdx] = hdrFs
			y = y + 20

			for _, item in ipairs(sec.items) do
				local key = item.key
				local cb = createCheck(optChild, item.label, 11, function(_, on)
					setPref(key, on)
				end)
				local xOff = item.indent and 22 or 8
				cb:SetPoint("TOPLEFT", optChild, "TOPLEFT", xOff, -y)
				if item.tip then
					attachTooltip(cb, item.label, { item.tip })
				end
				tv.checks[key] = cb
				tv.checkMeta[key] = item
				y = y + 24
			end
			y = y + 4
		end
		optChild:SetHeight(max(200, y + 10))
	end

	-- -----------------------------------------------------------------------------------------------
	-- Right Pane (~54%): TSM-Inspired "Example Tooltip" Live Preview Panel
	-- -----------------------------------------------------------------------------------------------
	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	tv.rightCard = rightCard

	local rightTitle = makeFs(rightCard, 13, "semibold", "text")
	rightTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -10)
	rightTitle:SetText("Example Tooltip")

	local dimHintFs = makeFs(rightCard, 10, "regular", "textSecondary", "RIGHT")
	dimHintFs:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -12)
	dimHintFs:SetWidth(130)
	if dimHintFs.SetWordWrap then dimHintFs:SetWordWrap(false) end
	dimHintFs:SetText("Dimmed = hidden")
	tv.dimHintFs = dimHintFs

	-- Sample item switcher pills
	do
		local sampleSpecs = {
			{ key = "green_lens",    label = "Green Lens",    w = 84 },
			{ key = "silk_cloth",    label = "Silk Cloth",    w = 74 },
			{ key = "waylaid_crate", label = "Waylaid Crate", w = 96 },
		}
		local prev
		for idx, sp in ipairs(sampleSpecs) do
			local b = createButton(rightCard, sp.label, sp.w, 22, { variant = "secondary", pill = true, fontSize = 10 })
			if idx == 1 then
				b:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -34)
			else
				b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
			end
			local sk = sp.key
			b:SetScript("OnClick", function()
				state.tooltipSampleKey = sk
				tv.sync()
			end)
			attachTooltip(b, "Preview Sample: " .. sp.label, {
				"Switches the Example Tooltip below to inspect how " .. sp.label .. " renders with your current toggles.",
			})
			tv.sampleBtns[sk] = b
			prev = b
		end
	end

	local previewStatusFs = makeFs(rightCard, 10, "semibold", "textSecondary", "RIGHT")
	previewStatusFs:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -40)
	previewStatusFs:SetWidth(130)
	if previewStatusFs.SetWordWrap then previewStatusFs:SetWordWrap(false) end
	previewStatusFs:SetText("Active on hover")
	tv.previewStatusFs = previewStatusFs

	local rightSep = createSeparator(rightCard)
	rightSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -62)
	rightSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -62)

	-- Dark WoW Tooltip Preview Box (#0B0E14 fill, 1px crisp gold/slate border, rounded corners)
	local tipBox = CreateFrame("Frame", nil, rightCard)
	tipBox:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -72)
	tipBox:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)
	tv.tipBox = tipBox

	if T and type(T.NineApple) == "function" then
		tv.tipSurface = T.NineApple(tipBox, "glass_r8", { 0.043, 0.055, 0.078, 0.98 }, { 0.68, 0.58, 0.34, 0.85 }, { noSpecular = true })
	else
		local bg = tipBox:CreateTexture(nil, "BACKGROUND", nil, 0)
		bg:SetAllPoints(tipBox)
		bg:SetColorTexture(0.043, 0.055, 0.078, 0.98)
		local bTop = tipBox:CreateTexture(nil, "BORDER")
		bTop:SetHeight(1)
		bTop:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 0, 0)
		bTop:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", 0, 0)
		bTop:SetColorTexture(0.68, 0.58, 0.34, 0.85)
		local bBot = tipBox:CreateTexture(nil, "BORDER")
		bBot:SetHeight(1)
		bBot:SetPoint("BOTTOMLEFT", tipBox, "BOTTOMLEFT", 0, 0)
		bBot:SetPoint("BOTTOMRIGHT", tipBox, "BOTTOMRIGHT", 0, 0)
		bBot:SetColorTexture(0.68, 0.58, 0.34, 0.85)
		local bLeft = tipBox:CreateTexture(nil, "BORDER")
		bLeft:SetWidth(1)
		bLeft:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 0, 0)
		bLeft:SetPoint("BOTTOMLEFT", tipBox, "BOTTOMLEFT", 0, 0)
		bLeft:SetColorTexture(0.68, 0.58, 0.34, 0.85)
		local bRight = tipBox:CreateTexture(nil, "BORDER")
		bRight:SetWidth(1)
		bRight:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", 0, 0)
		bRight:SetPoint("BOTTOMRIGHT", tipBox, "BOTTOMRIGHT", 0, 0)
		bRight:SetColorTexture(0.68, 0.58, 0.34, 0.85)
	end

	-- WoW item header (quality-colored title, subtitle, vendor sell line)
	local headerNameFs = tipBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	headerNameFs:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 12, -10)
	headerNameFs:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -12, -10)
	headerNameFs:SetJustifyH("LEFT")
	if headerNameFs.SetWordWrap then headerNameFs:SetWordWrap(false) end
	applyFont(headerNameFs, 13, "semibold")
	tv.headerNameFs = headerNameFs

	local headerSubFs = tipBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerSubFs:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 12, -28)
	headerSubFs:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -12, -28)
	headerSubFs:SetJustifyH("LEFT")
	if headerSubFs.SetWordWrap then headerSubFs:SetWordWrap(false) end
	applyFont(headerSubFs, 10, "regular")
	tv.headerSubFs = headerSubFs

	local headerSellFs = tipBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerSellFs:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 12, -42)
	headerSellFs:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -12, -42)
	headerSellFs:SetJustifyH("LEFT")
	if headerSellFs.SetWordWrap then headerSellFs:SetWordWrap(false) end
	applyFont(headerSellFs, 10, "regular")
	tv.headerSellFs = headerSellFs

	local headerSep = tipBox:CreateTexture(nil, "ARTWORK")
	headerSep:SetHeight(1)
	headerSep:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 10, -58)
	headerSep:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -10, -58)
	headerSep:SetColorTexture(0.38, 0.42, 0.50, 0.45)
	tv.headerSep = headerSep

	-- Scrollable container inside tipBox for the 36 pooled double-column preview rows
	local tipScroll = CreateFrame("ScrollFrame", nil, tipBox)
	tipScroll:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 10, -64)
	tipScroll:SetPoint("BOTTOMRIGHT", tipBox, "BOTTOMRIGHT", -16, 8)
	tv.tipScroll = tipScroll

	local tipChildParent = (tipScroll.SetScrollChild ~= nil) and tipScroll or tipBox
	local tipChild = CreateFrame("Frame", nil, tipChildParent)
	tipChild:SetPoint("TOPLEFT", tipChildParent, "TOPLEFT", 0, 0)
	tipChild:SetWidth(420)
	tipChild:SetHeight(320)
	if tipScroll.SetScrollChild then
		tipScroll:SetScrollChild(tipChild)
	end
	tv.tipChild = tipChild

	local tipSb = CreateFrame("Slider", nil, tipBox)
	tipSb:SetWidth(5)
	tipSb:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -4, -64)
	tipSb:SetPoint("BOTTOMRIGHT", tipBox, "BOTTOMRIGHT", -4, 8)
	if tipSb.SetOrientation then tipSb:SetOrientation("VERTICAL") end
	if tipSb.SetMinMaxValues then tipSb:SetMinMaxValues(0, 0) end
	if tipSb.SetValueStep then tipSb:SetValueStep(16) end
	if tipSb.SetValue then tipSb:SetValue(0) end
	local tipThumb = tipSb:CreateTexture(nil, "ARTWORK")
	tipThumb:SetSize(4, 28)
	tipThumb:SetColorTexture(0.75, 0.78, 0.85, 0.30)
	if tipSb.SetThumbTexture then tipSb:SetThumbTexture(tipThumb) end
	if T and type(T.SlimScrollBar) == "function" then
		T.SlimScrollBar(tipSb)
	end
	if tipSb.SetScript and tipScroll.SetVerticalScroll then
		tipSb:SetScript("OnValueChanged", function(_, val)
			if tipScroll.SetVerticalScroll then tipScroll:SetVerticalScroll(val or 0) end
		end)
	end
	tv.tipSb = tipSb

	local function onTipWheel(_, delta)
		if tipScroll.GetVerticalScrollRange and tipScroll.SetVerticalScroll and tipScroll.GetVerticalScroll then
			local rng = max(0, tipScroll:GetVerticalScrollRange() or 0)
			local cur = tipScroll:GetVerticalScroll() or 0
			local nxt = max(0, min(rng, cur - delta * 28))
			tipScroll:SetVerticalScroll(nxt)
			if tipSb.SetMinMaxValues then tipSb:SetMinMaxValues(0, rng) end
			if tipSb.SetValue then tipSb:SetValue(nxt) end
		end
	end
	if tipBox.EnableMouseWheel then tipBox:EnableMouseWheel(true) end
	tipBox:SetScript("OnMouseWheel", onTipWheel)
	if tipScroll.EnableMouseWheel then tipScroll:EnableMouseWheel(true) end
	tipScroll:SetScript("OnMouseWheel", onTipWheel)

	-- 36 pooled double-column FontString rows
	for i = 1, 36 do
		local rf = CreateFrame("Frame", nil, tipChild)
		rf:SetHeight(15)
		rf:Hide()

		local rFs = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		rFs:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
		rFs:SetJustifyH("RIGHT")
		if rFs.SetWordWrap then rFs:SetWordWrap(false) end
		applyFont(rFs, 11, "regular")

		local lFs = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		lFs:SetPoint("LEFT", rf, "LEFT", 2, 0)
		lFs:SetPoint("RIGHT", rFs, "LEFT", -8, 0)
		lFs:SetJustifyH("LEFT")
		if lFs.SetWordWrap then lFs:SetWordWrap(false) end
		applyFont(lFs, 11, "regular")

		tv.previewRows[i] = {
			frame = rf,
			leftFs = lFs,
			rightFs = rFs,
			enabled = false,
			isHeader = false,
		}
	end

	function tv.syncPreview()
		local sampleKey = state.tooltipSampleKey or "green_lens"
		local TP = getTP()
		local data
		if TP and type(TP.BuildPreviewLines) == "function" then
			local ok, res = pcall(TP.BuildPreviewLines, sampleKey)
			if ok and type(res) == "table" then
				data = res
			end
		end
		if type(data) ~= "table" then
			data = buildFallbackTooltipPreview(sampleKey, getPref)
		end

		local hdr = type(data.header) == "table" and data.header or {}
		local qRGB = type(hdr.qualityRGB) == "table" and hdr.qualityRGB or { 1, 1, 1 }
		headerNameFs:SetText(tostring(hdr.name or "Item Preview"))
		headerNameFs:SetTextColor(qRGB[1] or 1, qRGB[2] or 1, qRGB[3] or 1, 1)

		local subTxt = tostring(hdr.subtitle or "")
		local sellTxt = tostring(hdr.sellPrice or "")
		local hdrY = 28
		if subTxt ~= "" then
			headerSubFs:SetText(subTxt)
			headerSubFs:SetTextColor(0.72, 0.76, 0.82, 1)
			headerSubFs:ClearAllPoints()
			headerSubFs:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 12, -hdrY)
			headerSubFs:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -12, -hdrY)
			headerSubFs:Show()
			hdrY = hdrY + 14
		else
			headerSubFs:SetText("")
			headerSubFs:Hide()
		end
		if sellTxt ~= "" then
			headerSellFs:SetText(sellTxt)
			headerSellFs:SetTextColor(0.90, 0.92, 0.95, 1)
			headerSellFs:ClearAllPoints()
			headerSellFs:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 12, -hdrY)
			headerSellFs:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -12, -hdrY)
			headerSellFs:Show()
			hdrY = hdrY + 15
		else
			headerSellFs:SetText("")
			headerSellFs:Hide()
		end

		headerSep:ClearAllPoints()
		headerSep:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 10, -(hdrY + 2))
		headerSep:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -10, -(hdrY + 2))
		tipScroll:ClearAllPoints()
		tipScroll:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 10, -(hdrY + 8))
		tipScroll:SetPoint("BOTTOMRIGHT", tipBox, "BOTTOMRIGHT", -16, 8)
		tipSb:ClearAllPoints()
		tipSb:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", -4, -(hdrY + 8))
		tipSb:SetPoint("BOTTOMRIGHT", tipBox, "BOTTOMRIGHT", -4, 8)

		local rows = type(data.rows) == "table" and data.rows or {}
		local y = 0
		local shownCount = 0
		for i = 1, 36 do
			local slot = tv.previewRows[i]
			local r = rows[i]
			if r then
				shownCount = shownCount + 1
				local isHdr = (r.isHeader == true)
				local isEn = (r.enabled ~= false)
				if shownCount > 1 and isHdr then
					y = y + 6
				end
				local rowH = isHdr and 17 or 15
				slot.frame:ClearAllPoints()
				slot.frame:SetPoint("TOPLEFT", tipChild, "TOPLEFT", 0, -y)
				slot.frame:SetPoint("TOPRIGHT", tipChild, "TOPRIGHT", 0, -y)
				slot.frame:SetHeight(rowH)
				applyFont(slot.leftFs, 11, isHdr and "semibold" or "regular")
				applyFont(slot.rightFs, 11, "regular")

				local rL = tonumber(r.rL) or (isEn and (isHdr and 1.00 or 0.90) or 0.42)
				local gL = tonumber(r.gL) or (isEn and (isHdr and 0.82 or 0.92) or 0.45)
				local bL = tonumber(r.bL) or (isEn and (isHdr and 0.00 or 0.95) or 0.50)
				local rR = tonumber(r.rR) or (isEn and (isHdr and 0.62 or 0.90) or 0.42)
				local gR = tonumber(r.gR) or (isEn and (isHdr and 0.66 or 0.92) or 0.45)
				local bR = tonumber(r.bR) or (isEn and (isHdr and 0.72 or 0.95) or 0.50)

				local rightTxt = tostring(r.right or "")
				slot.leftFs:ClearAllPoints()
				slot.leftFs:SetPoint("LEFT", slot.frame, "LEFT", 2, 0)
				if rightTxt ~= "" then
					slot.leftFs:SetPoint("RIGHT", slot.rightFs, "LEFT", -8, 0)
				else
					slot.leftFs:SetPoint("RIGHT", slot.frame, "RIGHT", -2, 0)
				end
				slot.leftFs:SetText(tostring(r.left or ""))
				slot.leftFs:SetTextColor(rL, gL, bL, 1)
				slot.rightFs:SetText(rightTxt)
				slot.rightFs:SetTextColor(rR, gR, bR, 1)
				slot.enabled = isEn
				slot.isHeader = isHdr
				slot.frame:Show()
				y = y + rowH
			else
				slot.leftFs:SetText("")
				slot.rightFs:SetText("")
				slot.enabled = false
				slot.isHeader = false
				slot.frame:Hide()
			end
		end

		tipChild:SetHeight(max(120, y + 10))
		if tipScroll.UpdateScrollChildRect then tipScroll:UpdateScrollChildRect() end
		if tipScroll.GetVerticalScrollRange and tipSb.SetMinMaxValues then
			local rng = max(0, tipScroll:GetVerticalScrollRange() or 0)
			tipSb:SetMinMaxValues(0, rng)
			if tipSb.SetShown then tipSb:SetShown(rng > 0) end
		end
	end

	function tv.sync()
		local pal = getPal()
		local masterOn = getPref("ttEnabled") ~= false
		local curFmt = tostring(getPref("ttPriceFormat") or "colored")
		local curMod = tostring(getPref("ttModifier") or "none")
		local curSample = tostring(state.tooltipSampleKey or "green_lens")

		for key, cb in pairs(tv.checks) do
			local on = getPref(key) == true
			if cb.SetChecked then cb:SetChecked(on) end
			if cb.label then
				local meta = tv.checkMeta[key]
				local dimmed = false
				if key ~= "ttEnabled" then
					if not masterOn then
						dimmed = true
					elseif meta and meta.parentKey and getPref(meta.parentKey) == false then
						dimmed = true
					end
				end
				setFsColor(cb.label, dimmed and (pal.textMuted or pal.textSecondary) or pal.text)
			end
		end

		for k, b in pairs(tv.formatBtns) do
			if b.SetActive then b:SetActive(k == curFmt) end
		end
		for k, b in pairs(tv.modBtns) do
			if b.SetActive then b:SetActive(k == curMod) end
		end
		for k, b in pairs(tv.sampleBtns) do
			if b.SetActive then b:SetActive(k == curSample) end
		end

		if not masterOn then
			previewStatusFs:SetText("All Tooltips OFF")
			setFsColor(previewStatusFs, pal.accentRed or pal.textSecondary)
		elseif curMod ~= "none" then
			local ml = (curMod == "shift" and "Shift") or (curMod == "alt" and "Alt") or (curMod == "ctrl" and "Ctrl") or curMod
			previewStatusFs:SetText("Hold " .. ml .. " to show")
			setFsColor(previewStatusFs, pal.accentOrange or pal.textSecondary)
		else
			previewStatusFs:SetText("Active on hover")
			setFsColor(previewStatusFs, pal.accentGreen or pal.textSecondary)
		end

		tv.syncPreview()
	end

	function tv.retheme()
		tv.sync()
	end

	function tv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		local leftW = max(380, floor((w - 10) * 0.46))
		leftCard:SetWidth(leftW)
		if optChild.SetWidth then
			optChild:SetWidth(max(320, leftW - 26))
		end
		syncOptScrollRange()

		local rightW = max(360, w - leftW - 10)
		if tipChild.SetWidth then
			tipChild:SetWidth(max(300, rightW - 58))
		end
		if tipScroll.UpdateScrollChildRect then tipScroll:UpdateScrollChildRect() end
		if tipScroll.GetVerticalScrollRange and tipSb.SetMinMaxValues then
			local rng = max(0, tipScroll:GetVerticalScrollRange() or 0)
			tipSb:SetMinMaxValues(0, rng)
			if tipSb.SetShown then tipSb:SetShown(rng > 0) end
		end
	end

	function tv.refresh()
		tv.sync()
		tv.layout()
	end

	state.tooltipControls = {
		checks = tv.checks,
		sampleBtns = tv.sampleBtns,
		presetBtns = tv.presetBtns,
		formatBtns = tv.formatBtns,
		modBtns = tv.modBtns,
		previewRows = tv.previewRows,
		leftCard = tv.leftCard,
		rightCard = tv.rightCard,
		topBar = tv.topBar,
		tipBox = tv.tipBox,
		headerNameFs = tv.headerNameFs,
		headerSubFs = tv.headerSubFs,
		headerSellFs = tv.headerSellFs,
	}

	return tv
end

---------------------------------------------------------------------------------------------------
-- Sub-View 8: Addon UI & Live Theme Preview (console_ui)
---------------------------------------------------------------------------------------------------

local function formatPreviewMoney(copper, signed, priceMode, pPal)
	local a = floor(math.abs(tonumber(copper) or 0) + 0.5)
	local neg = (tonumber(copper) or 0) < 0
	local g = floor(a / 10000)
	local s = floor((a % 10000) / 100)
	local c = a % 100
	local prefix = neg and "-" or (signed and a > 0 and "+" or "")
	local hg = pPal.hexGold or "ffd60a"
	local hs = pPal.hexSilver or "c7c7cc"
	local hc = pPal.hexCopper or "e08a5e"
	local gTag = "|cff" .. hg .. "g|r"
	local sTag = "|cff" .. hs .. "s|r"
	local cTag = "|cff" .. hc .. "c|r"
	if priceMode == "no_copper" then
		local roundS = c >= 50 and (s + 1) or s
		local adjG = g + floor(roundS / 100)
		local adjS = roundS % 100
		if adjG > 0 then
			return format("%s%d%s %02d%s", prefix, adjG, gTag, adjS, sTag)
		elseif adjS > 0 then
			return format("%s%d%s", prefix, adjS, sTag)
		end
		return format("%s%d%s", prefix, c, cTag)
	elseif priceMode == "full_fixed" then
		return format("%s%02d%s %02d%s %02d%s", prefix, g, gTag, s, sTag, c, cTag)
	end
	if g > 0 then
		if s > 0 then return format("%s%d%s %02d%s", prefix, g, gTag, s, sTag) end
		return format("%s%d%s", prefix, g, gTag)
	elseif s > 0 then
		return format("%s%d%s %02d%s", prefix, s, sTag, c, cTag)
	end
	return format("%s%d%s", prefix, c, cTag)
end

local function resolvePreviewPalette(skinKey, modeKey)
	local T = getTheme()
	if skinKey and skinKey ~= "standard" and T and T.SKIN_PALETTES and T.SKIN_PALETTES[skinKey] then
		return T.SKIN_PALETTES[skinKey]
	end
	local mk = (modeKey == "light") and "light" or "dark"
	return (T and T.PALETTES and T.PALETTES[mk]) or FALLBACK_PALETTES[mk]
end

local function solidColor(col, fallback)
	local c = col or fallback or { 0.15, 0.15, 0.17, 1 }
	return c[1] or 0.15, c[2] or 0.15, c[3] or 0.17, 1
end

local function buildAddonUIView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local uv = {
		frame = frame,
		skinBtns = {},
		modeBtns = {},
		tableBtns = {},
		priceBtns = {},
		sampleRows = {},
		kpis = {},
		navItems = {},
	}

	-- Left Card: Controls
	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(475)
	uv.leftCard = leftCard

	local lTitle = makeFs(leftCard, 13, "semibold", "text")
	lTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -12)
	lTitle:SetText("Addon Appearance & Formatting (Hover to Preview)")

	local skinHdr = makeFs(leftCard, 11, "semibold", "textSecondary")
	skinHdr:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -38)
	skinHdr:SetText("Window Skin / Theme")

	do
		local skins = {
			{ key = "goblin",    label = "Goblin (Trade Baron)",   swatch = { 0.18, 0.95, 0.56 } },
			{ key = "human",     label = "Human (Stormwind)",      swatch = { 0.48, 0.69, 0.96 } },
			{ key = "night_elf", label = "Night Elf (Kaldorei)",   swatch = { 0.40, 0.91, 0.98 } },
			{ key = "orc",       label = "Orc (Orgrimmar)",        swatch = { 0.87, 0.65, 0.29 } },
			{ key = "undead",    label = "Undead (Forsaken)",      swatch = { 0.38, 0.81, 0.78 } },
			{ key = "standard",  label = "Modern Glass",           swatch = { 0.36, 0.72, 1.0 } },
		}
		for i, info in ipairs(skins) do
			local col = (i - 1) % 2
			local row = floor((i - 1) / 2)
			local btn = createButton(leftCard, info.label, 212, 24, { variant = "secondary", fontSize = 11 })
			btn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14 + col * 220, -(56 + row * 28))
			local dot = btn:CreateTexture(nil, "ARTWORK", nil, 1)
			dot:SetSize(8, 8)
			dot:SetPoint("LEFT", btn, "LEFT", 8, 0)
			dot:SetColorTexture(info.swatch[1], info.swatch[2], info.swatch[3], 1)
			if btn.HookScript then
				btn:HookScript("OnEnter", function()
					state.uiPreview.skin = info.key
					if info.key == "standard" then
						state.uiPreview.mode = nil
					end
					uv.renderPreview()
				end)
				btn:HookScript("OnLeave", function()
					state.uiPreview.skin = nil
					uv.renderPreview()
				end)
			end
			btn:SetScript("OnClick", function()
				state.uiPreview.skin = nil
				if ns.app and ns.app.applyUiSkin then
					ns.app.applyUiSkin(info.key)
				elseif getTheme() and getTheme().SetSkin then
					getTheme().SetSkin(info.key)
				end
				uv.sync()
			end)
			attachTooltip(btn, info.label, {
				"Hover to preview this window skin on the right.",
				"Click to apply immediately.",
			})
			uv.skinBtns[info.key] = btn
		end
	end

	local modeHdr = makeFs(leftCard, 11, "semibold", "textSecondary")
	modeHdr:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -148)
	modeHdr:SetText("Modern Glass Appearance")

	do
		local modes = {
			{ key = "dark",  label = "Dark Mode" },
			{ key = "light", label = "Light Mode" },
		}
		for i, m in ipairs(modes) do
			local btn = createButton(leftCard, m.label, 140, 24, { variant = "secondary", fontSize = 11 })
			btn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14 + (i - 1) * 148, -166)
			if btn.HookScript then
				btn:HookScript("OnEnter", function()
					state.uiPreview.skin = "standard"
					state.uiPreview.mode = m.key
					uv.renderPreview()
				end)
				btn:HookScript("OnLeave", function()
					state.uiPreview.skin = nil
					state.uiPreview.mode = nil
					uv.renderPreview()
				end)
			end
			btn:SetScript("OnClick", function()
				state.uiPreview.skin = nil
				state.uiPreview.mode = nil
				local T = getTheme()
				if T and T.GetSkin and T.GetSkin() ~= "standard" and ns.app and ns.app.applyUiSkin then
					ns.app.applyUiSkin("standard")
				end
				if _G.MerchantMasterDB then _G.MerchantMasterDB.uiThemeMode = m.key end
				if T and T.SetMode then T.SetMode(m.key) end
				uv.sync()
			end)
			attachTooltip(btn, m.label, {
				"Switches Modern Glass between Dark and Light mode.",
			})
			uv.modeBtns[m.key] = btn
		end
	end

	local tblHdr = makeFs(leftCard, 11, "semibold", "textSecondary")
	tblHdr:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -202)
	tblHdr:SetText("Table Style")

	do
		local styles = {
			{ key = "t5_ruled",  label = "Ruled Lines" },
			{ key = "t5_well",   label = "Deep Well" },
			{ key = "t3_strips", label = "Card Strips" },
			{ key = "classic",   label = "Classic" },
		}
		for i, stInfo in ipairs(styles) do
			local col = (i - 1) % 2
			local row = floor((i - 1) / 2)
			local btn = createButton(leftCard, stInfo.label, 212, 24, { variant = "secondary", fontSize = 11 })
			btn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14 + col * 220, -(220 + row * 28))
			if btn.HookScript then
				btn:HookScript("OnEnter", function()
					state.uiPreview.tableStyle = stInfo.key
					uv.renderPreview()
				end)
				btn:HookScript("OnLeave", function()
					state.uiPreview.tableStyle = nil
					uv.renderPreview()
				end)
			end
			btn:SetScript("OnClick", function()
				state.uiPreview.tableStyle = nil
				if ns.app and ns.app.applyTableStyle then
					ns.app.applyTableStyle(stInfo.key)
				elseif getTheme() and getTheme().SetTableStyle then
					getTheme().SetTableStyle(stInfo.key)
				end
				uv.sync()
			end)
			uv.tableBtns[stInfo.key] = btn
		end
	end

	local pFmtHdr = makeFs(leftCard, 11, "semibold", "textSecondary")
	pFmtHdr:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -288)
	pFmtHdr:SetText("Price Display Format")

	do
		local pModes = {
			{ key = "compact",    label = "Standard" },
			{ key = "no_copper",  label = "Gold & Silver" },
			{ key = "full_fixed", label = "00g 00s 00c" },
		}
		for i, pm in ipairs(pModes) do
			local btn = createButton(leftCard, pm.label, 140, 24, { variant = "secondary", fontSize = 11 })
			btn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14 + (i - 1) * 146, -306)
			if btn.HookScript then
				btn:HookScript("OnEnter", function()
					state.uiPreview.priceMode = pm.key
					uv.renderPreview()
				end)
				btn:HookScript("OnLeave", function()
					state.uiPreview.priceMode = nil
					uv.renderPreview()
				end)
			end
			btn:SetScript("OnClick", function()
				state.uiPreview.priceMode = nil
				if ns.app and ns.app.applyPriceDisplayMode then
					ns.app.applyPriceDisplayMode(pm.key)
				end
				uv.sync()
			end)
			uv.priceBtns[pm.key] = btn
		end
	end

	local posHdr = makeFs(leftCard, 11, "semibold", "textSecondary")
	posHdr:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -344)
	posHdr:SetText("Window Positions")

	local resetPosBtn = createButton(leftCard, "Reset Window Positions", 188, 24, { variant = "secondary", fontSize = 11 })
	resetPosBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -362)
	resetPosBtn:SetScript("OnClick", function()
		if ns.app and ns.app.resetWindowPositions then
			ns.app.resetWindowPositions()
		elseif ns.Window and ns.Window.ClearSavedPosition then
			ns.Window.ClearSavedPosition(nil)
		end
	end)
	attachTooltip(resetPosBtn, "Reset Window Positions", {
		"Clears saved positions for MerchantMaster, Disenchant Helper, Crafter/Trade Strip, and Shopping List so they return to smart default spawning.",
	})
	uv.resetPosBtn = resetPosBtn

	local uiNote = makeFs(leftCard, 11, "regular", "textSecondary")
	uiNote:SetPoint("BOTTOMLEFT", leftCard, "BOTTOMLEFT", 14, 14)
	uiNote:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -14, 14)
	if uiNote.SetWordWrap then uiNote:SetWordWrap(true) end
	uiNote:SetText("Hover any option above to preview changes on the right without applying them. Click any button to save immediately.")

	-- Right Card: Live UI Preview Canvas
	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	uv.rightCard = rightCard

	local pHeaderFs = makeFs(rightCard, 13, "semibold", "text")
	pHeaderFs:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -12)
	pHeaderFs:SetText("Live Preview")
	uv.pHeaderFs = pHeaderFs

	local pMetaFs = makeFs(rightCard, 11, "regular", "textSecondary", "RIGHT")
	pMetaFs:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -13)
	pMetaFs:SetText("--")
	uv.pMetaFs = pMetaFs

	local pSep = createSeparator(rightCard)
	pSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -34)
	pSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -34)

	-- Miniature MerchantMaster frame
	local miniWin = CreateFrame("Frame", nil, rightCard)
	miniWin:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 16, -46)
	miniWin:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -16, 44)
	uv.miniWin = miniWin
	local miniWinBg = miniWin:CreateTexture(nil, "BACKGROUND", nil, 0)
	miniWinBg:SetAllPoints(miniWin)
	uv.miniWinBg = miniWinBg

	local miniSide = CreateFrame("Frame", nil, miniWin)
	miniSide:SetPoint("TOPLEFT", miniWin, "TOPLEFT", 0, 0)
	miniSide:SetPoint("BOTTOMLEFT", miniWin, "BOTTOMLEFT", 0, 0)
	miniSide:SetWidth(120)
	uv.miniSide = miniSide
	local miniSideBg = miniSide:CreateTexture(nil, "BACKGROUND", nil, 1)
	miniSideBg:SetAllPoints(miniSide)
	uv.miniSideBg = miniSideBg

	local miniBrand = miniSide:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	miniBrand:SetPoint("TOPLEFT", miniSide, "TOPLEFT", 10, -10)
	applyFont(miniBrand, 11, "semibold")
	miniBrand:SetText("MerchantMaster")
	uv.miniBrand = miniBrand

	local navLabels = { "Today's Overview", "All Recipes", "Waylaid Crates", "Gap Sniper" }
	for i, lbl in ipairs(navLabels) do
		local nf = CreateFrame("Frame", nil, miniSide)
		nf:SetHeight(20)
		nf:SetPoint("TOPLEFT", miniSide, "TOPLEFT", 8, -(36 + (i - 1) * 24))
		nf:SetPoint("TOPRIGHT", miniSide, "TOPRIGHT", -8, -(36 + (i - 1) * 24))
		local nbg = nf:CreateTexture(nil, "BACKGROUND", nil, 2)
		nbg:SetAllPoints(nf)
		local nfs = nf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		nfs:SetPoint("LEFT", nf, "LEFT", 8, 0)
		nfs:SetJustifyH("LEFT")
		applyFont(nfs, 10, i == 1 and "semibold" or "regular")
		nfs:SetText(lbl)
		uv.navItems[i] = { frame = nf, bg = nbg, fs = nfs, active = (i == 1) }
	end

	local miniWallet = CreateFrame("Frame", nil, miniSide)
	miniWallet:SetHeight(48)
	miniWallet:SetPoint("BOTTOMLEFT", miniSide, "BOTTOMLEFT", 8, 8)
	miniWallet:SetPoint("BOTTOMRIGHT", miniSide, "BOTTOMRIGHT", -8, 8)
	local mwBg = miniWallet:CreateTexture(nil, "BACKGROUND", nil, 2)
	mwBg:SetAllPoints(miniWallet)
	local mwLbl = miniWallet:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mwLbl:SetPoint("TOPLEFT", miniWallet, "TOPLEFT", 8, -7)
	applyFont(mwLbl, 9, "regular")
	mwLbl:SetText("Character Gold")
	local mwVal = miniWallet:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mwVal:SetPoint("BOTTOMLEFT", miniWallet, "BOTTOMLEFT", 8, 7)
	applyFont(mwVal, 11, "semibold")
	uv.miniWallet = { bg = mwBg, lbl = mwLbl, val = mwVal }

	local miniToolbar = CreateFrame("Frame", nil, miniWin)
	miniToolbar:SetHeight(32)
	miniToolbar:SetPoint("TOPLEFT", miniSide, "TOPRIGHT", 8, -8)
	miniToolbar:SetPoint("TOPRIGHT", miniWin, "TOPRIGHT", -8, -8)
	local mtBg = miniToolbar:CreateTexture(nil, "BACKGROUND", nil, 1)
	mtBg:SetAllPoints(miniToolbar)
	local mtPill = CreateFrame("Frame", nil, miniToolbar)
	mtPill:SetSize(88, 20)
	mtPill:SetPoint("LEFT", miniToolbar, "LEFT", 8, 0)
	local mtPillBg = mtPill:CreateTexture(nil, "BACKGROUND", nil, 2)
	mtPillBg:SetAllPoints(mtPill)
	local mtPillFs = mtPill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mtPillFs:SetPoint("CENTER", 0, 0)
	applyFont(mtPillFs, 10, "semibold")
	mtPillFs:SetText("Craftable Now")
	local mtStat = miniToolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	mtStat:SetPoint("RIGHT", miniToolbar, "RIGHT", -8, 0)
	applyFont(mtStat, 10, "regular")
	mtStat:SetText("Normal-Horde | Live AH")
	uv.miniToolbar = { bg = mtBg, pillBg = mtPillBg, pillFs = mtPillFs, statFs = mtStat }

	for i = 1, 2 do
		local kc = CreateFrame("Frame", nil, miniWin)
		kc:SetHeight(56)
		local kbg = kc:CreateTexture(nil, "BACKGROUND", nil, 1)
		kbg:SetAllPoints(kc)
		local kt = kc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		kt:SetPoint("TOPLEFT", kc, "TOPLEFT", 10, -8)
		applyFont(kt, 10, "semibold")
		kt:SetText(i == 1 and "BEST CRAFT PROFIT" or "DAILY SPREAD")
		local kv = kc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		kv:SetPoint("BOTTOMLEFT", kc, "BOTTOMLEFT", 10, 10)
		applyFont(kv, 13, "semibold")
		uv.kpis[i] = { frame = kc, bg = kbg, titleFs = kt, valFs = kv }
	end

	local miniTable = CreateFrame("Frame", nil, miniWin)
	miniTable:SetPoint("TOPLEFT", miniToolbar, "BOTTOMLEFT", 0, -68)
	miniTable:SetPoint("BOTTOMRIGHT", miniWin, "BOTTOMRIGHT", -8, 8)
	local tblBg = miniTable:CreateTexture(nil, "BACKGROUND", nil, 1)
	tblBg:SetAllPoints(miniTable)
	uv.miniTable = miniTable
	uv.miniTableBg = tblBg

	local thName = miniTable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	thName:SetPoint("TOPLEFT", miniTable, "TOPLEFT", 10, -6)
	applyFont(thName, 10, "semibold")
	thName:SetText("Recipe / Item")
	local thBuy = miniTable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	thBuy:SetPoint("TOPRIGHT", miniTable, "TOPRIGHT", -96, -6)
	thBuy:SetWidth(84)
	thBuy:SetJustifyH("RIGHT")
	applyFont(thBuy, 10, "semibold")
	thBuy:SetText("Cost")
	local thProfit = miniTable:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	thProfit:SetPoint("TOPRIGHT", miniTable, "TOPRIGHT", -10, -6)
	thProfit:SetWidth(84)
	thProfit:SetJustifyH("RIGHT")
	applyFont(thProfit, 10, "semibold")
	thProfit:SetText("Net Profit")
	local thDiv = miniTable:CreateTexture(nil, "ARTWORK")
	thDiv:SetHeight(1)
	thDiv:SetPoint("TOPLEFT", miniTable, "TOPLEFT", 6, -22)
	thDiv:SetPoint("TOPRIGHT", miniTable, "TOPRIGHT", -6, -22)
	uv.tblHeaders = { thName, thBuy, thProfit, div = thDiv }

	local sampleItems = {
		{ name = "Flask of Supreme Power", cost = 214550, profit = 68500 },
		{ name = "Elixir of Mongoose",     cost = 52400,  profit = 18250 },
		{ name = "Major Mana Potion",      cost = 31800,  profit = 9400 },
		{ name = "Solid Dynamite",         cost = 1850,   profit = -340 },
	}
	for i, si in ipairs(sampleItems) do
		local rf = CreateFrame("Frame", nil, miniTable)
		rf:SetHeight(24)
		rf:SetPoint("TOPLEFT", miniTable, "TOPLEFT", 6, -(26 + (i - 1) * 28))
		rf:SetPoint("TOPRIGHT", miniTable, "TOPRIGHT", -6, -(26 + (i - 1) * 28))
		local rbg = rf:CreateTexture(nil, "BACKGROUND", nil, 2)
		rbg:SetAllPoints(rf)
		local rline = rf:CreateTexture(nil, "ARTWORK")
		rline:SetHeight(1)
		rline:SetPoint("BOTTOMLEFT", rf, "BOTTOMLEFT", 0, 0)
		rline:SetPoint("BOTTOMRIGHT", rf, "BOTTOMRIGHT", 0, 0)
		local nFs = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		nFs:SetPoint("LEFT", rf, "LEFT", 6, 0)
		nFs:SetPoint("RIGHT", rf, "RIGHT", -182, 0)
		nFs:SetJustifyH("LEFT")
		if nFs.SetWordWrap then nFs:SetWordWrap(false) end
		applyFont(nFs, 11, "regular")
		nFs:SetText(si.name)
		local bFs = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		bFs:SetPoint("RIGHT", rf, "RIGHT", -90, 0)
		bFs:SetWidth(84)
		bFs:SetJustifyH("RIGHT")
		applyFont(bFs, 11, "regular")
		local pFs = rf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		pFs:SetPoint("RIGHT", rf, "RIGHT", -6, 0)
		pFs:SetWidth(84)
		pFs:SetJustifyH("RIGHT")
		applyFont(pFs, 11, "semibold")
		uv.sampleRows[i] = { frame = rf, bg = rbg, line = rline, nameFs = nFs, buyFs = bFs, profitFs = pFs, sample = si }
	end

	local pFooterFs = makeFs(rightCard, 11, "regular", "textSecondary")
	pFooterFs:SetPoint("BOTTOMLEFT", rightCard, "BOTTOMLEFT", 16, 14)
	pFooterFs:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -16, 14)
	pFooterFs:SetText("Hover any Skin, Mode, Table Style, or Price Format button on the left to preview before applying.")

	function uv.renderPreview()
		local T = getTheme()
		local curSkin = (T and T.GetSkin and T.GetSkin()) or "goblin"
		local curMode = (T and T.GetMode and T.GetMode()) or "dark"
		local curTbl = (T and T.GetTableStyle and T.GetTableStyle()) or "t5_ruled"
		local curPrice = (T and T.GetPriceDisplayMode and T.GetPriceDisplayMode()) or "compact"

		local isHovering = (state.uiPreview.skin ~= nil) or (state.uiPreview.mode ~= nil)
			or (state.uiPreview.tableStyle ~= nil) or (state.uiPreview.priceMode ~= nil)
		local pSkin = state.uiPreview.skin or curSkin
		local pMode = state.uiPreview.mode or curMode
		local pTbl = state.uiPreview.tableStyle or curTbl
		local pPrice = state.uiPreview.priceMode or curPrice

		local pPal = resolvePreviewPalette(pSkin, pMode)
		pHeaderFs:SetText(isHovering and "Live Preview (Hovering)" or "Live Preview (Active)")
		pMetaFs:SetText(format("Skin: %s  |  Table: %s  |  Price: %s",
			pSkin == "standard" and ("standard-" .. pMode) or pSkin, pTbl, pPrice))

		miniWinBg:SetColorTexture(solidColor(pPal.winBg))
		miniSideBg:SetColorTexture(solidColor(pPal.sidebarBg))
		setFsColor(miniBrand, pPal.titleCream or pPal.text)

		for _, ni in ipairs(uv.navItems) do
			if ni.active then
				local nac = pPal.navActiveBg or pPal.accentBlue
				ni.bg:SetColorTexture(nac[1] or 0.3, nac[2] or 0.5, nac[3] or 0.8, 0.30)
				setFsColor(ni.fs, pPal.text)
			else
				ni.bg:SetColorTexture(0, 0, 0, 0)
				setFsColor(ni.fs, pPal.textSecondary)
			end
		end
		uv.miniWallet.bg:SetColorTexture(solidColor(pPal.cardBg))
		setFsColor(uv.miniWallet.lbl, pPal.textSecondary)
		setFsColor(uv.miniWallet.val, pPal.text)
		uv.miniWallet.val:SetText(formatPreviewMoney(12485670, false, pPrice, pPal))

		uv.miniToolbar.bg:SetColorTexture(solidColor(pPal.toolbarBg or pPal.cardBg))
		uv.miniToolbar.pillBg:SetColorTexture(solidColor(pPal.accentBlue))
		setFsColor(uv.miniToolbar.pillFs, pPal.textOnAccent or pPal.text)
		setFsColor(uv.miniToolbar.statFs, pPal.textSecondary)
		uv.miniToolbar.statFs:SetText(hasSnapshotsAny() and "Normal-Horde | Snap 4m" or "Normal-Horde | Live AH")

		uv.kpis[1].bg:SetColorTexture(solidColor(pPal.cardBg))
		setFsColor(uv.kpis[1].titleFs, pPal.textSecondary)
		setFsColor(uv.kpis[1].valFs, pPal.accentGreen or pPal.text)
		uv.kpis[1].valFs:SetText(formatPreviewMoney(124580, true, pPrice, pPal))

		uv.kpis[2].bg:SetColorTexture(solidColor(pPal.cardBg))
		setFsColor(uv.kpis[2].titleFs, pPal.textSecondary)
		setFsColor(uv.kpis[2].valFs, pPal.text)
		uv.kpis[2].valFs:SetText(formatPreviewMoney(214850, false, pPrice, pPal))

		-- Table container & style preview
		if pTbl == "t5_well" then
			uv.miniTableBg:SetColorTexture(solidColor(pPal.cardAltBg))
		else
			uv.miniTableBg:SetColorTexture(solidColor(pPal.cardBg))
		end
		for idx = 1, 3 do
			setFsColor(uv.tblHeaders[idx], pPal.textSecondary)
		end
		local sep = pPal.separator or { 0.4, 0.4, 0.4, 0.5 }
		uv.tblHeaders.div:SetColorTexture(sep[1] or 0.4, sep[2] or 0.4, sep[3] or 0.4, sep[4] or 0.5)

		for idx, row in ipairs(uv.sampleRows) do
			if pTbl == "t3_strips" then
				row.bg:SetColorTexture(solidColor(pPal.cardAltBg))
				row.line:Hide()
			elseif pTbl == "t5_well" then
				if (idx % 2) == 0 then
					local cb = pPal.cardBg
					row.bg:SetColorTexture(cb[1] or 0.2, cb[2] or 0.2, cb[3] or 0.2, 0.55)
				else
					row.bg:SetColorTexture(0, 0, 0, 0)
				end
				row.line:Hide()
			elseif pTbl == "classic" then
				if (idx % 2) == 0 then
					row.bg:SetColorTexture(solidColor(pPal.cardAltBg))
				else
					row.bg:SetColorTexture(solidColor(pPal.cardBg))
				end
				row.line:Show()
				row.line:SetColorTexture(sep[1] or 0.4, sep[2] or 0.4, sep[3] or 0.4, 0.35)
			else -- t5_ruled
				row.bg:SetColorTexture(0, 0, 0, 0)
				row.line:Show()
				row.line:SetColorTexture(sep[1] or 0.4, sep[2] or 0.4, sep[3] or 0.4, 0.55)
			end
			setFsColor(row.nameFs, pPal.text)
			setFsColor(row.buyFs, pPal.textSecondary)
			row.buyFs:SetText(formatPreviewMoney(row.sample.cost, false, pPrice, pPal))
			local isPos = row.sample.profit >= 0
			setFsColor(row.profitFs, isPos and (pPal.accentGreen or pPal.text) or (pPal.accentRed or pPal.text))
			row.profitFs:SetText(formatPreviewMoney(row.sample.profit, true, pPrice, pPal))
		end
	end

	function uv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		leftCard:SetWidth(max(450, floor((w - 10) * 0.47)))
		local mw = (miniWin.GetWidth and miniWin:GetWidth()) or 480
		if mw <= 0 then mw = 480 end
		local kw = max(120, floor((mw - 120 - 24) / 2))
		uv.kpis[1].frame:ClearAllPoints()
		uv.kpis[1].frame:SetPoint("TOPLEFT", miniToolbar, "BOTTOMLEFT", 0, -6)
		uv.kpis[1].frame:SetWidth(kw)
		uv.kpis[2].frame:ClearAllPoints()
		uv.kpis[2].frame:SetPoint("TOPLEFT", uv.kpis[1].frame, "TOPRIGHT", 8, 0)
		uv.kpis[2].frame:SetPoint("TOPRIGHT", miniToolbar, "BOTTOMRIGHT", 0, -6)
	end

	function uv.sync()
		local T = getTheme()
		local curSkin = (T and T.GetSkin and T.GetSkin()) or "goblin"
		local curMode = (T and T.GetMode and T.GetMode()) or "dark"
		local curTbl = (T and T.GetTableStyle and T.GetTableStyle()) or "t5_ruled"
		local curPrice = (T and T.GetPriceDisplayMode and T.GetPriceDisplayMode()) or "compact"
		for k, b in pairs(uv.skinBtns) do
			if b.SetActive then b:SetActive(k == curSkin) end
		end
		for k, b in pairs(uv.modeBtns) do
			if b.SetActive then b:SetActive(curSkin == "standard" and k == curMode) end
		end
		for k, b in pairs(uv.tableBtns) do
			if b.SetActive then b:SetActive(k == curTbl) end
		end
		for k, b in pairs(uv.priceBtns) do
			if b.SetActive then b:SetActive(k == curPrice) end
		end
		uv.renderPreview()
	end

	function uv.refresh()
		uv.sync()
	end

	state.uiControls = uv
	return uv
end

---------------------------------------------------------------------------------------------------
-- Sub-View 7: Data & Maintenance (console_data)
---------------------------------------------------------------------------------------------------

local function buildDataView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local dv = {
		frame = frame,
		armedBtns = {},
		actionBtns = {},
	}

	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	leftCard:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	leftCard:SetWidth(520)
	dv.leftCard = leftCard

	local dTitle = makeFs(leftCard, 13, "semibold", "text")
	dTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -12)
	dTitle:SetText("Data & Maintenance Actions (Hover Buttons for Details)")

	local actionStatusFs = makeFs(leftCard, 11, "semibold", "textSecondary")
	actionStatusFs:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -32)
	actionStatusFs:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -32)
	actionStatusFs:SetHeight(24)
	actionStatusFs:SetText(state.actionStatus)
	dv.actionStatusFs = actionStatusFs

	local function resetArmedLabels()
		state.armedAction = nil
		for _, info in ipairs(dv.armedBtns) do
			setButtonLabel(info.btn, info.idleLabel)
			if info.btn.SetVariant then info.btn:SetVariant("secondary") end
		end
	end

	local function makeActionBtn(label, x, y, w, actionKey, argFn, destructive, tipTitle, tipLines)
		local btn = createButton(leftCard, label, w or 224, 24, {
			variant = "secondary",
			fontSize = 11,
		})
		btn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", x, y)
		if destructive then
			dv.armedBtns[#dv.armedBtns + 1] = { btn = btn, idleLabel = label, actionKey = actionKey }
		end
		btn:SetScript("OnClick", function(self)
			if destructive and state.armedAction ~= actionKey then
				resetArmedLabels()
				state.armedAction = actionKey
				setButtonLabel(self, "Confirm: " .. label .. "?")
				if self.SetVariant then self:SetVariant("danger") end
				setStatusMsg("Click again to confirm '" .. label .. "'.", "warning")
				return
			end
			resetArmedLabels()
			local CE = getCE()
			if not CE then return end
			local arg = argFn and argFn() or nil
			local res = CE.RunAction(actionKey, arg)
			if res and res.ok then
				setStatusMsg(res.message, "green")
				if actionKey == "export_ledger_csv" and res.data then
					state.exportCsvText = res.data
					if dv.csvBox and dv.csvBox.SetText then
						dv.csvBox:SetText(res.data)
					end
				end
			else
				setStatusMsg((res and res.message) or "Action failed.", "danger")
			end
			UI.Refresh("data_action")
		end)
		attachTooltip(btn, tipTitle or label, tipLines)
		dv.actionBtns[actionKey] = btn
		return btn
	end

	makeActionBtn("Pack AH History", 14, -64, 232, "pack_ah_history", nil, false,
		"Pack AH History", {
			"What it does: Compresses timestamped AH price rings in MerchantMasterDB.ahHistory, ahDaily, and ahSnapshots.",
			"When to use: To reduce SavedVariables memory/size after heavy scanning.",
			"What it resets: Nothing -- keeps all price history intact in tighter delta format.",
		})

	dv.forgetAhBtn = makeActionBtn("Forget Live AH Prices", 258, -64, 232, "forget_live_ah", nil, true,
		"Forget Live AH Prices (2-Click Confirm)", {
			"What it does: Wipes saved live AH prices (ahPrices, costs, ahLots) for your active economy only.",
			"When to use: If a broken or incomplete AH scan left bad prices and you want a clean slate before re-scanning.",
			"What it resets: Current manual scan buyouts & lot depth (keeps recipes, settings, and Ledger history).",
		})

	makeActionBtn("Queue Wealth Snapshot", 14, -96, 232, "queue_wealth_snapshot", nil, false,
		"Queue Wealth Snapshot", {
			"What it does: Immediately records current character gold, bags/bank/mail value, and open auctions to MerchantMasterLedgerDB.wealth.",
			"When to use: Right after a big payout or buyout when you want Analytics -> Portfolio updated now.",
			"What it resets: Nothing -- appends one new wealth timestamp.",
		})

	dv.clearSellerBtn = makeActionBtn("Clear Seller Cache", 258, -96, 232, "clear_seller_stats", nil, true,
		"Clear Seller Cache (2-Click Confirm)", {
			"What it does: Clears MerchantMasterDB.sellerStats (monopoly/competitor seller concentration cache).",
			"When to use: If seller names or competitor counts look stale and you want them rebuilt on the next AH scan.",
			"What it resets: SellerStats concentration cache only (keeps all item prices and Ledger history).",
		})

	makeActionBtn("Reset Analytics Errors", 14, -128, 232, "reset_ledger_errors", nil, false,
		"Reset Analytics Errors", {
			"What it does: Zeroes MerchantMasterLedgerDB.stats.errors and re-enables Ledger capture hooks if tripped by the circuit breaker.",
			"When to use: After resolving an issue shown in Perf & Debug when Analytics Ledger tracking was paused.",
			"What it resets: Error counters and paused hook flags only (keeps all transactions).",
		})

	dv.clearSniperBtn = makeActionBtn("Clear Sniper Cache", 258, -128, 232, "clear_sniper_cache", nil, true,
		"Clear Sniper Cache (2-Click Confirm)", {
			"What it does: Clears active Gap Sniper & Vendor Sniper results, Sniper session profit counters, drill-down cache, and history.",
			"When to use: Starting a fresh AH session so old or already-bought snipes are cleared.",
			"What it resets: Sniper deals list & session counters only (keeps SavedVariables prices and Ledger).",
		})

	local pSep = createSeparator(leftCard)
	pSep:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 12, -166)
	pSep:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -12, -166)

	local pTitle = makeFs(leftCard, 12, "semibold", "text")
	pTitle:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -176)
	pTitle:SetText("Ledger Prune & CSV Export")

	local pruneDaysBtn = createButton(leftCard, "Cutoff: 30d", 112, 24, { dropdown = true, fontSize = 11 })
	pruneDaysBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -200)
	pruneDaysBtn:SetScript("OnClick", function(self)
		local T = getTheme()
		if T and T.OpenDropDown then
			T.OpenDropDown(self, {
				{ key = 30, label = "Older than 30 days" },
				{ key = 60, label = "Older than 60 days" },
				{ key = 90, label = "Older than 90 days" },
			}, state.pruneDays, function(k)
				state.pruneDays = k
				setButtonLabel(pruneDaysBtn, format("Cutoff: %dd", k))
			end, 160)
		end
	end)
	attachTooltip(pruneDaysBtn, "Ledger Retention Cutoff", {
		"Select how many recent days of individual transaction rows to keep in full detail before pruning folds older days.",
	})
	dv.pruneDaysBtn = pruneDaysBtn

	local previewBtn = createButton(leftCard, "Preview Prune", 122, 24, { variant = "secondary", fontSize = 11 })
	previewBtn:SetPoint("LEFT", pruneDaysBtn, "RIGHT", 6, 0)
	previewBtn:SetScript("OnClick", function()
		resetArmedLabels()
		local CE = getCE()
		if not CE then return end
		local p = CE.PreviewPruneLedger(state.pruneDays)
		if type(p) == "table" and p.ok ~= false then
			dv.pruneInfoFs:SetText(format("Preview (< %s): %d days, %d rows | %s -> %s",
				tostring(p.cutoffDay or "?"), p.daysToPrune or 0, p.rowsToPrune or 0,
				CE.FormatBytes(p.estBytesBefore or 0), CE.FormatBytes(p.estBytesAfter or 0)))
		else
			dv.pruneInfoFs:SetText("Preview error: " .. tostring(p and p.err or "unavailable"))
		end
	end)
	attachTooltip(previewBtn, "Preview Ledger Prune", {
		"What it does: Safely dry-runs retention folding without changing data, reporting how many days, rows, and bytes will be reclaimed.",
		"When to use: Click before Prune Ledger.",
	})
	dv.previewBtn = previewBtn

	dv.pruneBtn = makeActionBtn("Prune Ledger", 258, -200, 114, "prune_ledger", function() return state.pruneDays end, true,
		"Prune Ledger (2-Click Confirm)", {
			"What it does: Folds Ledger transaction rows older than the selected cutoff (30d/60d/90d) into compact archived checkpoints.",
			"When to use: Every few weeks if MerchantMasterLedgerDB becomes huge on reload.",
			"What it resets: Removes individual old daily rows before cutoff (all-time profit, cost basis, and wealth totals stay intact).",
		})

	local exportCsvBtn = createButton(leftCard, "Export CSV", 112, 24, { variant = "secondary", fontSize = 11 })
	exportCsvBtn:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 378, -200)
	exportCsvBtn:SetScript("OnClick", function()
		resetArmedLabels()
		local CE = getCE()
		if not CE then return end
		local res = CE.RunAction("export_ledger_csv")
		if res and res.ok then
			state.exportCsvText = res.data or ""
			if dv.csvBox and dv.csvBox.SetText then dv.csvBox:SetText(state.exportCsvText) end
			setStatusMsg(res.message, "green")
			selectAllInBox(dv.csvBox)
		else
			setStatusMsg((res and res.message) or "Export failed.", "danger")
		end
	end)
	attachTooltip(exportCsvBtn, "Export Ledger CSV", {
		"What it does: Generates full CSV accounting output of MerchantMasterLedgerDB below and selects it for Ctrl+C.",
		"When to use: For Excel / Google Sheets analysis or offline backup.",
		"What it resets: Nothing -- read-only export.",
	})
	dv.exportCsvBtn = exportCsvBtn

	local pruneInfoFs = makeFs(leftCard, 11, "regular", "textSecondary")
	pruneInfoFs:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -230)
	pruneInfoFs:SetPoint("TOPRIGHT", leftCard, "TOPRIGHT", -14, -230)
	pruneInfoFs:SetText("Click 'Preview Prune' before pruning old ledger rows.")
	dv.pruneInfoFs = pruneInfoFs

	local csvCard, csvBox = createMultiLineArea(leftCard)
	csvCard:SetPoint("TOPLEFT", leftCard, "TOPLEFT", 14, -252)
	csvCard:SetPoint("BOTTOMRIGHT", leftCard, "BOTTOMRIGHT", -14, 14)
	dv.csvBox = csvBox

	-- Right Card: Quick Use-Case Guide + Slash Reference
	local rightCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	rightCard:SetPoint("TOPLEFT", leftCard, "TOPRIGHT", 10, 0)
	rightCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	dv.rightCard = rightCard

	local guideTitle = makeFs(rightCard, 13, "semibold", "text")
	guideTitle:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -12)
	guideTitle:SetText("When to Use Maintenance Actions")

	local guideBody = makeFs(rightCard, 11, "regular", "textSecondary")
	guideBody:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -36)
	guideBody:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -14, -36)
	guideBody:SetHeight(184)
	if guideBody.SetJustifyV then guideBody:SetJustifyV("TOP") end
	if guideBody.SetWordWrap then guideBody:SetWordWrap(true) end
	guideBody:SetText(table.concat({
		"- Pack AH History: Shrinks SavedVariables size without losing prices.",
		"- Forget Live AH Prices: Clears bad or stale AH scan prices before running a fresh scan.",
		"- Queue Wealth Snapshot: Forces an immediate Portfolio gold/stock checkpoint.",
		"- Clear Seller Cache: Rebuilds competitor concentration on your next scan.",
		"- Reset Analytics Errors: Clears tripped capture-hook breaker flags.",
		"- Clear Sniper Cache: Clears active Gap/Vendor Sniper deals and session stats.",
		"- Prune Ledger: Folds old daily tx rows while keeping lifetime profit totals.",
		"All destructive buttons require two clicks to confirm.",
	}, "\n"))

	local slSep = createSeparator(rightCard)
	slSep:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 12, -228)
	slSep:SetPoint("TOPRIGHT", rightCard, "TOPRIGHT", -12, -228)

	local slHdr = makeFs(rightCard, 12, "semibold", "text")
	slHdr:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -238)
	slHdr:SetText("Slash Commands Reference")

	local slashHelpFs = makeFs(rightCard, 10, "regular", "textSecondary")
	slashHelpFs:SetPoint("TOPLEFT", rightCard, "TOPLEFT", 14, -260)
	slashHelpFs:SetPoint("BOTTOMRIGHT", rightCard, "BOTTOMRIGHT", -14, 14)
	if slashHelpFs.SetJustifyV then slashHelpFs:SetJustifyV("TOP") end
	if slashHelpFs.SetWordWrap then slashHelpFs:SetWordWrap(true) end
	dv.slashHelpFs = slashHelpFs

	function dv.sync()
		if ns.app and type(ns.app.buildSlashHelp) == "function" then
			dv.slashHelpFs:SetText(ns.app.buildSlashHelp())
		end
	end

	function dv.layout()
		local w = (frame.GetWidth and frame:GetWidth()) or 1000
		if w <= 0 then w = 1000 end
		leftCard:SetWidth(max(506, floor((w - 10) * 0.54)))
	end

	function dv.refresh()
		dv.sync()
	end

	return dv
end

---------------------------------------------------------------------------------------------------
-- Top Bar, Theme Integration & Lazy Build
---------------------------------------------------------------------------------------------------

local function buildSubTabBar(root)
	local defs = {
		{ key = "console_overview", label = "Overview", width = 60, hint = "Addon RAM, SavedVariables, Live AH scans & health" },
		{ key = "console_database", label = "Database", width = 62, hint = "WoW SavedVariables schema inspector" },
		{ key = "console_perf", label = "Perf & Debug", width = 80, hint = "Opt-in runtime profiler & support debug bundle" },
		{ key = "console_setup2", label = "Snapshot Sync", width = 96, hint = "GitHub Auto-Sync & 3-way Price Refresh Mode - zero API key" },
		{ key = "console_settings", label = "Settings", width = 56, hint = "Market, inventory scope, Leveling filter & item tooltips" },
		{ key = "console_mail", label = "Mail", width = 38, hint = "Saved mail recipients, mailbox quick-pick buttons & send safety net" },
		{ key = "console_tooltips", label = "Tooltip Setup", width = 80, hint = "Customize item tooltip sections, price format & live example preview" },
		{ key = "console_ui", label = "Addon UI", width = 58, hint = "Window skins, dark/light mode, table styles & price formats with live preview" },
		{ key = "console_data", label = "Data & Maintenance", width = 110, hint = "Cache clears, Ledger pruning, CSV export & slash commands" },
	}
	local function onSelect(key)
		if ns.app and type(ns.app.setTab) == "function" then
			ns.app.setTab(key)
		else
			UI.Show(key)
		end
	end

	local T = getTheme()
	local bar
	if T and type(T.CreateSubTabBar) == "function" then
		bar = T.CreateSubTabBar(root, defs, onSelect)
	else
		bar = CreateFrame("Frame", nil, root)
		bar:SetHeight(26)
		bar.buttons = {}
		local x = 4
		for _, d in ipairs(defs) do
			local b = createButton(bar, d.label, d.width, 20, { variant = "ghost", pill = true })
			b:SetPoint("LEFT", bar, "LEFT", x, 0)
			local k = d.key
			b:SetScript("OnClick", function() onSelect(k) end)
			bar.buttons[k] = b
			x = x + d.width + 4
		end
		function bar:SetActiveKey(activeKey)
			for k, btn in pairs(self.buttons) do
				if btn.SetActive then btn:SetActive(k == activeKey) end
			end
		end
	end
	bar._defs = defs
	bar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)

	local refreshBtn = createButton(bar, "Refresh", 76, 20, { variant = "secondary", fontSize = 11 })
	refreshBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	refreshBtn:SetScript("OnClick", function()
		UI.Refresh("manual_btn")
	end)
	state.refreshBtn = refreshBtn

	if T and type(T.CreateBadgePill) == "function" then
		local pill = T.CreateBadgePill(bar, "Profiler OFF", "neutral", { height = 20, fontSize = 10 })
		pill.frame:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
		state.perfPill = pill
	end

	state.subTabBar = bar
end

local function ensureBuilt()
	if state.built or not state.root then return end
	state.built = true
	buildSubTabBar(state.root)
	state.overviewView = buildOverviewView(state.root)
	state.databaseView = buildDatabaseView(state.root)
	state.perfView = buildPerfView(state.root)
	state.setupV2View = buildSetupV2View(state.root)
	state.settingsView = buildSettingsView(state.root)
	state.mailView = buildMailView(state.root)
	state.tooltipsView = buildTooltipsView(state.root)
	state.uiView = buildAddonUIView(state.root)
	state.dataView = buildDataView(state.root)
	UI.ApplyTheme()
end

---------------------------------------------------------------------------------------------------
-- Provider Public API
---------------------------------------------------------------------------------------------------

function UI.Mount(parent)
	if state.root then
		if parent and state.root:GetParent() ~= parent then
			state.root:SetParent(parent)
			state.root:ClearAllPoints()
			state.root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
			state.root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
		end
		return state.root
	end
	state.parent = parent
	local root = CreateFrame("Frame", nil, parent)
	root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	root:Hide()
	state.root = root

	local T = getTheme()
	if not state.themeHooked and T then
		state.themeHooked = true
		if type(T.RegisterWidget) == "function" then
			T.RegisterWidget(root, UI.ApplyTheme)
		end
		if type(T.OnModeChanged) == "function" then
			T.OnModeChanged(function() UI.ApplyTheme() end)
		end
		if type(T.OnSkinChanged) == "function" then
			T.OnSkinChanged(function() UI.ApplyTheme() end)
		end
	end
	return root
end

local function viewMap()
	return {
		console_overview = state.overviewView,
		console_database = state.databaseView,
		console_perf = state.perfView,
		console_setup2 = state.setupV2View,
		console_settings = state.settingsView,
		console_mail = state.mailView,
		console_tooltips = state.tooltipsView,
		console_ui = state.uiView,
		console_data = state.dataView,
	}
end

function UI.Show(subTab)
	if not state.root then return false end
	if not (ns.app and ns.app.snapshotExtension) and type(ns.EnsureSnapshotsLoaded) == "function" then
		ns.EnsureSnapshotsLoaded()
	end
	ensureBuilt()
	if subTab == "console_setup" then
		subTab = "console_setup2"
	end
	local wasShown = UI.IsShown()
	local prevTab = state.activeSubTab
	local target = SUB_TABS[subTab] and subTab or "console_overview"
	if wasShown and prevTab == target and not state.dirty then
		return true
	end
	state.activeSubTab = target
	state.root:Show()
	if state.subTabBar and state.subTabBar.SetActiveKey then
		state.subTabBar:SetActiveKey(target)
	end
	for k, v in pairs(viewMap()) do
		if v and v.frame then
			if k == target then v.frame:Show() else v.frame:Hide() end
		end
	end
	UI.Layout()
	UI.Refresh("show")
	return true
end

function UI.Hide()
	state.dirty = true
	if state.root then state.root:Hide() end
	return true
end

function UI.IsShown()
	return state.root ~= nil and state.root:IsShown() == true
end

function UI.GetActiveSubTab()
	return state.activeSubTab
end

function UI.Layout()
	if not state.built or not UI.IsShown() then return end
	local active = viewMap()[state.activeSubTab]
	if active and type(active.layout) == "function" then
		active.layout()
	end
end

function UI.ApplyTheme()
	if not state.built then return end
	local pal = getPal()
	for _, entry in ipairs(state.styledCards) do
		paintSurfaceCard(entry, pal)
	end
	for _, item in ipairs(state.themedText) do
		setFsColor(item.fs, pal[item.key] or pal.text)
	end
	local sep = pal.separator or { 0.4, 0.4, 0.4, 0.4 }
	for _, tex in ipairs(state.themedSeparators) do
		if tex and tex.SetColorTexture then
			tex:SetColorTexture(sep[1], sep[2], sep[3], sep[4] or 0.4)
		end
	end
	if state.dataView and state.dataView.actionStatusFs then
		setStatusMsg(state.actionStatus, state.actionStatusVariant)
	end
	if UI.IsShown() then
		if state.activeSubTab == "console_overview" and state.overviewView and type(state.overviewView.retheme) == "function" then
			state.overviewView.retheme()
		elseif state.activeSubTab == "console_setup2" and state.setupV2View and type(state.setupV2View.retheme) == "function" then
			state.setupV2View.retheme()
		elseif state.activeSubTab == "console_database" and state.databaseView and type(state.databaseView.renderRows) == "function" then
			state.databaseView.renderRows()
		elseif state.activeSubTab == "console_mail" and state.mailView and type(state.mailView.retheme) == "function" then
			state.mailView.retheme()
		elseif state.activeSubTab == "console_tooltips" and state.tooltipsView and type(state.tooltipsView.retheme) == "function" then
			state.tooltipsView.retheme()
		elseif state.activeSubTab == "console_ui" and state.uiView and type(state.uiView.sync) == "function" then
			state.uiView.sync()
		end
	end
end

function UI.SyncSettings()
	if not state.built then return end
	if state.setupV2View and type(state.setupV2View.retheme) == "function" then
		state.setupV2View.retheme()
	end
	if state.settingsView and type(state.settingsView.sync) == "function" then
		state.settingsView.sync()
	end
	if state.mailView and type(state.mailView.sync) == "function" then
		state.mailView.sync()
	end
	if state.tooltipsView and type(state.tooltipsView.sync) == "function" then
		state.tooltipsView.sync()
	end
	if state.uiView and type(state.uiView.sync) == "function" then
		state.uiView.sync()
	end
	if state.dataView and type(state.dataView.sync) == "function" then
		state.dataView.sync()
	end
end

function UI.SyncExtensions()
	if not state.built then return end
	if UI.IsShown() then
		UI.Layout()
		UI.Refresh("extension_changed")
	else
		state.dirty = true
	end
end

function UI.Refresh(reason)
	if not state.built or not UI.IsShown() then
		state.dirty = true
		return
	end
	if reason == "manual_btn" and not hasSnapshotExt() and type(ns.EnsureSnapshotsLoaded) == "function" then
		ns.EnsureSnapshotsLoaded(true)
	end
	if reason == "app_refresh" then
		if state.activeSubTab == "console_settings"
			or state.activeSubTab == "console_mail"
			or state.activeSubTab == "console_tooltips"
			or state.activeSubTab == "console_ui"
			or state.activeSubTab == "console_data" then
			UI.SyncSettings()
		end
		return
	end
	state.dirty = false
	local CE = getCE()
	if state.perfPill and CE then
		local on = CE.IsPerfEnabled()
		state.perfPill:SetVariant(on and "orange" or "neutral", on and "Profiler ON" or "Profiler OFF")
	end
	local active = viewMap()[state.activeSubTab]
	if active and type(active.refresh) == "function" then
		active.refresh(reason)
	end
end

UI._state = state

---------------------------------------------------------------------------------------------------
-- Provider Registration (Idempotent)
---------------------------------------------------------------------------------------------------

local provider = {
	Mount = UI.Mount,
	Show = UI.Show,
	Hide = UI.Hide,
	Refresh = UI.Refresh,
	Layout = UI.Layout,
	ApplyTheme = UI.ApplyTheme,
	SyncSettings = UI.SyncSettings,
	SyncExtensions = UI.SyncExtensions,
	IsShown = UI.IsShown,
	GetActiveSubTab = UI.GetActiveSubTab,
}

ns.consoleProvider = provider

if _G.MerchantMasterAPI and type(_G.MerchantMasterAPI.RegisterConsole) == "function" then
	_G.MerchantMasterAPI.RegisterConsole(provider)
elseif ns.app and type(ns.app.registerConsole) == "function" then
	ns.app.registerConsole(provider)
end
