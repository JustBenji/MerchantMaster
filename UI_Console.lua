-- MerchantMaster UI_Console.lua
-- Unified Console & Admin Monitor page:
--   1. Overview            (RAM, SavedVariables, Live AH scans, Health, optional Snapshot cards)
--   2. Database            (WoW SavedVariables schema inspector + optional SQLite companion tables)
--   3. Perf & Debug        (Zero-overhead opt-in runtime profiler & privacy-safe Debug Bundle)
--   4. Setup               (Optional snapshot companion setup commands; hidden when absent)
--   5. Settings            (Synced /mm options, Leveling guide, tooltip settings)
--   6. Addon UI            (Theme/skin, table style & price format switcher with live preview)
--   7. Data & Maintenance  (Two-click cache/ledger cleanup with hover tooltips, CSV export, slash help)
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
	console_setup = true,
	console_settings = true,
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
	setupView = nil,
	settingsView = nil,
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
	setupOpts = {
		region = "eu",
		presetKey = "Normal-Horde",
		customHouse = "2:114=Normal-Horde",
		intervalMin = 15,
		retentionDays = 30,
		maxExportMB = 8,
		dbPath = "",
		outDir = "",
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

	settingsControls = {},
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
			sLines[#sLines + 1] = format("Windows Runner Task: %s (enabled=%s, every %dm, retain %dd)",
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
			sLines[#sLines + 1] = colorHex("hexMuted", "SYSTEM telemetry unavailable from snapshot companion. Open Setup tab or run export.", pal)
		end
		ov.snapDetailFs:SetText(table.concat(sLines, "\n"))
	end

	return ov
end

---------------------------------------------------------------------------------------------------
-- Sub-View 2: Database & Storage Inspector (console_database)
---------------------------------------------------------------------------------------------------

local DB_VISIBLE_ROWS = 18

local function buildDatabaseView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local dv = {
		frame = frame,
		rows = {},
	}

	local summaryCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	summaryCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	summaryCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	summaryCard:SetHeight(56)
	dv.summaryCard = summaryCard

	local sumTitle = makeFs(summaryCard, 12, "semibold", "text")
	sumTitle:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 14, -8)
	sumTitle:SetText("Storage Architecture (WoW SavedVariables)")
	dv.sumTitle = sumTitle

	local sumBody = makeFs(summaryCard, 11, "regular", "textSecondary")
	sumBody:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 14, -27)
	sumBody:SetPoint("TOPRIGHT", summaryCard, "TOPRIGHT", -14, -27)
	if sumBody.SetWordWrap then sumBody:SetWordWrap(true) end
	dv.sumBody = sumBody

	local leftCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	leftCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -64)
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
	local T = getTheme()
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
		leftCard:SetWidth(max(360, floor((w - 10) * 0.48)))
	end

	function dv.refresh()
		local CE = getCE()
		if not CE then return end
		local showSnap = hasSnapshotExt()
		local storage = CE.CollectStorageSnapshot()
		local sys = showSnap and storage.sysMeta or nil

		if showSnap then
			dv.sumTitle:SetText("Storage Architecture (SQLite Companion + WoW SavedVariables)")
			dv.listHdr:SetText("Tables (SQLite + SavedVariables) -- Click to inspect")
			if sys then
				dv.sumBody:SetText(format(
					"SQLite: DB %s | WAL %s | SHM %s | Pages %s (%d free) | Journal %s | Export %s / %s  --  SavedVariables Total: %s",
					CE.FormatBytes(sys.dbBytes or 0), CE.FormatBytes(sys.walBytes or 0),
					CE.FormatBytes(sys.shmBytes or 0), CE.FormatInt(sys.pageCount or 0),
					sys.freelist or 0, tostring(sys.journalMode or "wal"),
					CE.FormatBytes(sys.exportBytes or 0), CE.FormatBytes(sys.exportCapBytes or 0),
					CE.FormatBytes(storage.totalSavedBytes or 0)))
			else
				dv.sumBody:SetText(format(
					"SavedVariables Est: %s  |  SQLite companion telemetry pending.",
					CE.FormatBytes(storage.totalSavedBytes or 0)))
			end
		else
			dv.sumTitle:SetText("Storage Architecture (WoW SavedVariables)")
			dv.listHdr:SetText("SavedVariables Tables -- Click to inspect")
			dv.sumBody:SetText(format(
				"SavedVariables Est: %s across %d tracked tables (MerchantMasterDB + MerchantMasterLedgerDB).",
				CE.FormatBytes(storage.totalSavedBytes or 0),
				#(storage.savedTables or {})))
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
-- Sub-View 4: Setup & Companion Config (console_setup)
---------------------------------------------------------------------------------------------------

local function buildSetupView(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local su = {
		frame = frame,
	}

	local statusCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	statusCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	statusCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	statusCard:SetHeight(74)

	local stTitle = makeFs(statusCard, 13, "semibold", "text")
	stTitle:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 14, -10)
	stTitle:SetText("Blizzard API & Scheduled Runner Status")

	local stBody = makeFs(statusCard, 11, "regular", "textSecondary")
	stBody:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 14, -30)
	stBody:SetPoint("TOPRIGHT", statusCard, "TOPRIGHT", -14, -30)
	if stBody.SetWordWrap then stBody:SetWordWrap(true) end
	su.stBody = stBody

	-- Config Builder Card
	local cfgCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	cfgCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -82)
	cfgCard:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -82)
	cfgCard:SetHeight(148)

	local cfgTitle = makeFs(cfgCard, 13, "semibold", "text")
	cfgTitle:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 14, -10)
	cfgTitle:SetText("Companion Config Builder (Generates PowerShell Commands Below)")

	local regionBtn = createButton(cfgCard, "Region: EU", 110, 24, { dropdown = true, fontSize = 11 })
	regionBtn:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 14, -38)
	su.regionBtn = regionBtn

	local presetBtn = createButton(cfgCard, "Server: Normal-Horde (2:114)", 230, 24, { dropdown = true, fontSize = 11 })
	presetBtn:SetPoint("LEFT", regionBtn, "RIGHT", 8, 0)
	su.presetBtn = presetBtn

	local intervalBtn = createButton(cfgCard, "Every: 15 min", 120, 24, { dropdown = true, fontSize = 11 })
	intervalBtn:SetPoint("LEFT", presetBtn, "RIGHT", 8, 0)
	su.intervalBtn = intervalBtn

	local retainBtn = createButton(cfgCard, "Retain: 30d", 115, 24, { dropdown = true, fontSize = 11 })
	retainBtn:SetPoint("LEFT", intervalBtn, "RIGHT", 8, 0)
	su.retainBtn = retainBtn

	local capBtn = createButton(cfgCard, "Cap: 8 MB", 105, 24, { dropdown = true, fontSize = 11 })
	capBtn:SetPoint("LEFT", retainBtn, "RIGHT", 8, 0)
	su.capBtn = capBtn

	local resetCfgBtn = createButton(cfgCard, "Reset Defaults", 110, 24, { variant = "ghost", fontSize = 11 })
	resetCfgBtn:SetPoint("LEFT", capBtn, "RIGHT", 8, 0)

	local customLbl = makeFs(cfgCard, 11, "regular", "textSecondary")
	customLbl:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 14, -76)
	customLbl:SetText("Custom House (ruleset:house=Econ):")

	local customBox = createSingleLineBox(cfgCard, 195, 22, function(self)
		state.setupOpts.customHouse = (self.GetText and self:GetText()) or ""
		state.setupOpts.presetKey = "custom"
		su.updateCommands()
	end)
	customBox:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 14, -96)
	customBox:SetText(state.setupOpts.customHouse)
	su.customBox = customBox

	local dbLbl = makeFs(cfgCard, 11, "regular", "textSecondary")
	dbLbl:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 224, -76)
	dbLbl:SetText("SQLite DB Path (blank = default):")

	local dbBox = createSingleLineBox(cfgCard, 270, 22, function(self)
		state.setupOpts.dbPath = (self.GetText and self:GetText()) or ""
		su.updateCommands()
	end)
	dbBox:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 224, -96)
	su.dbBox = dbBox

	local outLbl = makeFs(cfgCard, 11, "regular", "textSecondary")
	outLbl:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 508, -76)
	outLbl:SetText("Export Out Dir (blank = AddOns\\MerchantMaster_Snapshots):")

	local outBox = createSingleLineBox(cfgCard, 300, 22, function(self)
		state.setupOpts.outDir = (self.GetText and self:GetText()) or ""
		su.updateCommands()
	end)
	outBox:SetPoint("TOPLEFT", cfgCard, "TOPLEFT", 508, -96)
	su.outBox = outBox

	-- Bottom Command Boxes Card
	local cmdCard = createSurfaceCard(frame, "glass_r12", "cardBg")
	cmdCard:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -238)
	cmdCard:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

	local c1Lbl = makeFs(cmdCard, 11, "semibold", "text")
	c1Lbl:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 14, -10)
	c1Lbl:SetText("1. Launch Visual Setup GUI (Windows Desktop Form for API Key, Server & Task):")

	local guiBox = createSingleLineBox(cmdCard, 720, 24)
	guiBox:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 14, -28)
	guiBox:SetPoint("TOPRIGHT", cmdCard, "TOPRIGHT", -104, -28)
	su.guiBox = guiBox

	local guiSelBtn = createButton(cmdCard, "Select", 78, 24, { variant = "secondary", fontSize = 11 })
	guiSelBtn:SetPoint("TOPRIGHT", cmdCard, "TOPRIGHT", -14, -28)
	guiSelBtn:SetScript("OnClick", function() selectAllInBox(guiBox) end)

	local c2Lbl = makeFs(cmdCard, 11, "semibold", "text")
	c2Lbl:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 14, -60)
	c2Lbl:SetText("2. Apply Settings, Server & Windows Task in PowerShell:")

	local cfgBox = createSingleLineBox(cmdCard, 720, 24)
	cfgBox:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 14, -78)
	cfgBox:SetPoint("TOPRIGHT", cmdCard, "TOPRIGHT", -104, -78)
	su.cfgBox = cfgBox

	local cfgSelBtn = createButton(cmdCard, "Select", 78, 24, { variant = "secondary", fontSize = 11 })
	cfgSelBtn:SetPoint("TOPRIGHT", cmdCard, "TOPRIGHT", -14, -78)
	cfgSelBtn:SetScript("OnClick", function() selectAllInBox(cfgBox) end)

	local c3Lbl = makeFs(cmdCard, 11, "semibold", "text")
	c3Lbl:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 14, -110)
	c3Lbl:SetText("3. Set Blizzard API Key in Windows User Env (Never saved in addon files) & Discover:")

	local keyCard, keyBox = createMultiLineArea(cmdCard)
	keyCard:SetPoint("TOPLEFT", cmdCard, "TOPLEFT", 14, -130)
	keyCard:SetPoint("BOTTOMRIGHT", cmdCard, "BOTTOMRIGHT", -104, 12)
	su.keyBox = keyBox

	local keySelBtn = createButton(cmdCard, "Select", 78, 24, { variant = "primary", pill = true, fontSize = 11 })
	keySelBtn:SetPoint("TOPRIGHT", cmdCard, "TOPRIGHT", -14, -130)
	keySelBtn:SetScript("OnClick", function() selectAllInBox(keyBox) end)

	local REGION_OPTS = {
		{ key = "eu", label = "EU (Europe)" },
		{ key = "us", label = "US (Americas)" },
		{ key = "kr", label = "KR (Korea)" },
		{ key = "tw", label = "TW (Taiwan)" },
	}
	local INTERVAL_OPTS = {
		{ key = 5, label = "Every 5 min" },
		{ key = 10, label = "Every 10 min" },
		{ key = 15, label = "Every 15 min" },
		{ key = 30, label = "Every 30 min" },
		{ key = 60, label = "Every 60 min" },
	}
	local RETAIN_OPTS = {
		{ key = 7, label = "Retain 7 days" },
		{ key = 14, label = "Retain 14 days" },
		{ key = 30, label = "Retain 30 days" },
		{ key = 60, label = "Retain 60 days" },
		{ key = 90, label = "Retain 90 days" },
	}
	local CAP_OPTS = {
		{ key = 4, label = "4 MB Cap" },
		{ key = 8, label = "8 MB Cap" },
		{ key = 12, label = "12 MB Cap" },
		{ key = 16, label = "16 MB Cap" },
	}

	function su.updateCommands()
		local CE = getCE()
		if not CE then return end
		local presets = (type(CE.GetServerPresets) == "function" and CE.GetServerPresets()) or {}
		local presetLabel = state.setupOpts.presetKey or "Normal-Horde"
		for _, p in ipairs(presets) do
			if p.key == state.setupOpts.presetKey then
				presetLabel = p.label
				break
			end
		end
		setButtonLabel(regionBtn, "Region: " .. tostring(state.setupOpts.region or "eu"):upper())
		setButtonLabel(presetBtn, "Server: " .. presetLabel)
		setButtonLabel(intervalBtn, format("Every: %d min", tonumber(state.setupOpts.intervalMin) or 15))
		setButtonLabel(retainBtn, format("Retain: %dd", tonumber(state.setupOpts.retentionDays) or 30))
		setButtonLabel(capBtn, format("Cap: %d MB", tonumber(state.setupOpts.maxExportMB) or 8))

		local cmds = CE.BuildSetupCommands(state.setupOpts)
		if type(cmds) == "table" then
			if guiBox.SetText then guiBox:SetText(cmds.guiCmd or "") end
			if cfgBox.SetText then cfgBox:SetText(cmds.configureCmd or "") end
			if keyBox.SetText then keyBox:SetText(cmds.apiKeyCmd or "") end
		else
			if guiBox.SetText then guiBox:SetText("") end
			if cfgBox.SetText then cfgBox:SetText("") end
			if keyBox.SetText then keyBox:SetText("") end
		end
	end

	regionBtn:SetScript("OnClick", function(self)
		local T = getTheme()
		if T and T.OpenDropDown then
			T.OpenDropDown(self, REGION_OPTS, state.setupOpts.region, function(k)
				state.setupOpts.region = k
				su.updateCommands()
			end, 160)
		end
	end)
	presetBtn:SetScript("OnClick", function(self)
		local T = getTheme()
		local CE = getCE()
		if T and T.OpenDropDown and CE then
			local presets = (type(CE.GetServerPresets) == "function" and CE.GetServerPresets()) or {}
			T.OpenDropDown(self, presets, state.setupOpts.presetKey, function(k)
				state.setupOpts.presetKey = k
				su.updateCommands()
			end, 240)
		end
	end)
	intervalBtn:SetScript("OnClick", function(self)
		local T = getTheme()
		if T and T.OpenDropDown then
			T.OpenDropDown(self, INTERVAL_OPTS, state.setupOpts.intervalMin, function(k)
				state.setupOpts.intervalMin = k
				su.updateCommands()
			end, 160)
		end
	end)
	retainBtn:SetScript("OnClick", function(self)
		local T = getTheme()
		if T and T.OpenDropDown then
			T.OpenDropDown(self, RETAIN_OPTS, state.setupOpts.retentionDays, function(k)
				state.setupOpts.retentionDays = k
				su.updateCommands()
			end, 160)
		end
	end)
	capBtn:SetScript("OnClick", function(self)
		local T = getTheme()
		if T and T.OpenDropDown then
			T.OpenDropDown(self, CAP_OPTS, state.setupOpts.maxExportMB, function(k)
				state.setupOpts.maxExportMB = k
				su.updateCommands()
			end, 140)
		end
	end)
	resetCfgBtn:SetScript("OnClick", function()
		state.setupOpts.region = "eu"
		state.setupOpts.presetKey = "Normal-Horde"
		state.setupOpts.customHouse = "2:114=Normal-Horde"
		state.setupOpts.intervalMin = 15
		state.setupOpts.retentionDays = 30
		state.setupOpts.maxExportMB = 8
		state.setupOpts.dbPath = ""
		state.setupOpts.outDir = ""
		if customBox.SetText then customBox:SetText(state.setupOpts.customHouse) end
		if dbBox.SetText then dbBox:SetText("") end
		if outBox.SetText then outBox:SetText("") end
		su.updateCommands()
	end)

	function su.retheme()
		local CE = getCE()
		if not CE then return end
		local pal = getPal()
		local sys = su._lastSys
		if sys then
			su.stBody:SetText(format(
				"Task: %s (enabled=%s)  |  Region: %s  |  Creds: %s  |  Every %dm  |  Retain %dd  |  Houses: %s  |  Last Sync: %s",
				tostring(sys.taskStatus or "?"), tostring(sys.taskEnabled),
				tostring(sys.region or "?"),
				sys.credsSet and colorHex("hexGreen", "SET", pal) or colorHex("hexWarning", "MISSING", pal),
				sys.intervalMin or 15, sys.retentionDays or 30,
				tostring(sys.houseMap or ""),
				CE.FormatTimestamp(sys.exportedAt)))
		else
			su.stBody:SetText("Runner SYSTEM status unavailable from snapshot companion. Configure below and paste command #2 or #3 in PowerShell.")
		end
	end

	function su.refresh()
		local CE = getCE()
		if not CE then return end
		su._lastSys = ns.Pricing and type(ns.Pricing.GetSnapshotSystemMeta) == "function"
			and ns.Pricing.GetSnapshotSystemMeta() or nil
		su.retheme()
		su.updateCommands()
	end

	return su
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
-- Sub-View 6: Addon UI & Live Theme Preview (console_ui)
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
			{ key = "standard",  label = "Modern Glass",           swatch = { 0.36, 0.72, 1.0 } },
			{ key = "human",     label = "Human (Stormwind)",      swatch = { 0.48, 0.69, 0.96 } },
			{ key = "night_elf", label = "Night Elf (Kaldorei)",   swatch = { 0.40, 0.91, 0.98 } },
			{ key = "orc",       label = "Orc (Orgrimmar)",        swatch = { 0.87, 0.65, 0.29 } },
			{ key = "undead",    label = "Undead (Forsaken)",      swatch = { 0.38, 0.81, 0.78 } },
			{ key = "goblin",    label = "Goblin (Trade Baron)",   swatch = { 0.18, 0.95, 0.56 } },
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
		local curSkin = (T and T.GetSkin and T.GetSkin()) or "standard"
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
		local curSkin = (T and T.GetSkin and T.GetSkin()) or "standard"
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

local function syncSubTabVisibility()
	local bar = state.subTabBar
	if not bar or not bar.buttons or not bar._defs then return end
	local showSetup = hasSnapshotExt()
	local x = 4
	for _, d in ipairs(bar._defs) do
		local b = bar.buttons[d.key]
		if b then
			local visible = (d.key ~= "console_setup") or showSetup
			if visible then
				b:ClearAllPoints()
				b:SetPoint("LEFT", bar, "LEFT", x, 0)
				b:Show()
				x = x + (d.width or 86) + 4
			else
				b:Hide()
			end
		end
	end
	bar.rightStart = x + 6
end

local function buildSubTabBar(root)
	local defs = {
		{ key = "console_overview", label = "Overview", width = 86, hint = "Addon RAM, SavedVariables, Live AH scans & health" },
		{ key = "console_database", label = "Database", width = 86, hint = "WoW SavedVariables schema inspector" },
		{ key = "console_perf", label = "Perf & Debug", width = 104, hint = "Opt-in runtime profiler & support debug bundle" },
		{ key = "console_setup", label = "Setup", width = 72, hint = "Snapshot companion setup & runner config" },
		{ key = "console_settings", label = "Settings", width = 82, hint = "Market, inventory scope, Leveling filter & item tooltips" },
		{ key = "console_ui", label = "Addon UI", width = 86, hint = "Window skins, dark/light mode, table styles & price formats with live preview" },
		{ key = "console_data", label = "Data & Maintenance", width = 148, hint = "Cache clears, Ledger pruning, CSV export & slash commands" },
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
	syncSubTabVisibility()
end

local function ensureBuilt()
	if state.built or not state.root then return end
	state.built = true
	buildSubTabBar(state.root)
	state.overviewView = buildOverviewView(state.root)
	state.databaseView = buildDatabaseView(state.root)
	state.perfView = buildPerfView(state.root)
	state.setupView = buildSetupView(state.root)
	state.settingsView = buildSettingsView(state.root)
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
		console_setup = state.setupView,
		console_settings = state.settingsView,
		console_ui = state.uiView,
		console_data = state.dataView,
	}
end

function UI.Show(subTab)
	if not state.root then return false end
	ensureBuilt()
	syncSubTabVisibility()
	local wasShown = UI.IsShown()
	local prevTab = state.activeSubTab
	local target = SUB_TABS[subTab] and subTab or "console_overview"
	if target == "console_setup" and not hasSnapshotExt() then
		target = "console_overview"
	end
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
		elseif state.activeSubTab == "console_setup" and state.setupView and type(state.setupView.retheme) == "function" then
			state.setupView.retheme()
		elseif state.activeSubTab == "console_database" and state.databaseView and type(state.databaseView.renderRows) == "function" then
			state.databaseView.renderRows()
		elseif state.activeSubTab == "console_ui" and state.uiView and type(state.uiView.sync) == "function" then
			state.uiView.sync()
		end
	end
end

function UI.SyncSettings()
	if not state.built then return end
	if state.settingsView and type(state.settingsView.sync) == "function" then
		state.settingsView.sync()
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
	syncSubTabVisibility()
	if state.activeSubTab == "console_setup" and not hasSnapshotExt() then
		state.dirty = true
		if UI.IsShown() then
			UI.Show("console_overview")
		else
			state.activeSubTab = "console_overview"
		end
	elseif UI.IsShown() then
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
	syncSubTabVisibility()
	if state.activeSubTab == "console_setup" and not hasSnapshotExt() then
		state.activeSubTab = "console_overview"
		if state.subTabBar and state.subTabBar.SetActiveKey then
			state.subTabBar:SetActiveKey("console_overview")
		end
		for k, v in pairs(viewMap()) do
			if v and v.frame then
				if k == "console_overview" then v.frame:Show() else v.frame:Hide() end
			end
		end
		UI.Layout()
	end
	if reason == "app_refresh" then
		if state.activeSubTab == "console_settings"
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
