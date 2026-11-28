-- MerchantMaster: Professor Leveling Path, Shopping & Recipe Browser UI
local ADDON, ns = ...
local app = ns.app
local matchProfKeyByName = ns.matchProfKeyByName
local sameProfKeys, sameCounts = app.sameProfKeys, app.sameCounts

---------------------------------------------------------------------------------------------------
-- Embedded Professor Module (Unified 1-300 Leveling Path, Working Overtime Solver, Shopping & Browse)
do local _ = (function()
	local MP = ns.MP
	if not MP then return end
	local mmApp = app
	local Theme = ns.Theme

	local papp = {
		activeTab = "path",
		ui = {},
		sortState = {
			path   = { col = "sortSkill", asc = true },
			shop   = { col = "lineCost",  asc = false },
			browse = { col = "req",       asc = true },
		},
	}
	MP.app = papp

	local CHAR_LEVEL_OPTIONS = {
		{ key = "auto", label = "Lv: Auto" },
		{ key = 60,     label = "Lv: 60 (Plan All)" },
		{ key = 10,     label = "Lv: 10 (Journeyman)" },
		{ key = 20,     label = "Lv: 20 (Expert)" },
		{ key = 30,     label = "Lv: 30" },
		{ key = 35,     label = "Lv: 35 (Artisan)" },
		{ key = 40,     label = "Lv: 40 (Specs)" },
		{ key = 50,     label = "Lv: 50" },
	}

	local OVERTIME_OPTIONS = {
		{ key = "auto", label = "Overtime: Auto" },
		{ key = 0,      label = "Overtime: 0/5 (+0%)" },
		{ key = 1,      label = "Overtime: 1/5 (+4%)" },
		{ key = 2,      label = "Overtime: 2/5 (+8%)" },
		{ key = 3,      label = "Overtime: 3/5 (+12%)" },
		{ key = 4,      label = "Overtime: 4/5 (+16%)" },
		{ key = 5,      label = "Overtime: 5/5 (+20%)" },
	}

	local GOAL_OPTIONS = {
		{ key = "smart",    label = "Goal: Smart Net/Profit" },
		{ key = "cheapest", label = "Goal: Cheapest (Vendor Net)" },
		{ key = "ah_max",   label = "Goal: Max AH (Uncapped / High Risk)" },
	}

	local RECIPE_FILTER_OPTIONS = {
		{ key = "known_only",     label = "Src: Known Recipes Only" },
		{ key = "trainer_vendor", label = "Src: Trainer + Vendor" },
		{ key = "trainer_only",   label = "Src: Trainer Only" },
		{ key = "with_ah",        label = "Src: + AH Scrolls" },
		{ key = "all",            label = "Src: All (+ Favor Camp)" },
	}

	local SELL_DAYS_OPTIONS = {
		{ key = 1, label = "AH Horizon: 1 Day" },
		{ key = 3, label = "AH Horizon: 3 Days" },
		{ key = 7, label = "AH Horizon: 7 Days" },
	}

	local function getProfDB()
		return MP.GetDB()
	end

	local function profSay(msg)
		print("|cffffd200MerchantMaster (Professor)|r: " .. tostring(msg))
	end

	local function applyFont(fs, size, weight, flags)
		if not fs or not fs.SetFont then return end
		if Theme and Theme.ApplyFont then
			Theme.ApplyFont(fs, size, weight, flags)
			if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
			if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
			return
		end
		local wantBold = (weight == "semibold" or weight == "bold" or weight == "heavy")
		local primaryPath = (Theme and Theme.ResolveFontPath and Theme.ResolveFontPath(weight))
			or (Theme and Theme.FONTS and (wantBold and Theme.FONTS.semibold or Theme.FONTS.regular))
			or STANDARD_TEXT_FONT
			or "Fonts\\ARIALN.TTF"
		local sz = size or 12
		local fl = flags or ""
		local ok = fs:SetFont(primaryPath, sz, fl)
		if ok == false or (ok == nil and fs.GetFont and select(1, fs:GetFont()) ~= primaryPath) then
			ok = fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF", sz, fl)
			if ok == false then
				ok = fs:SetFont("Fonts\\ARIALN.TTF", sz, fl)
				if ok == false then
					fs:SetFont("Fonts\\FRIZQT__.TTF", sz, fl)
				end
			end
		end
		if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
		if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
	end

	local function setCellBold(fs, isBold)
		if not fs or not fs.GetFont or not fs.SetFont then return end
		if not fs._mpBaseSize then
			local _, fSize = fs:GetFont()
			fs._mpBaseSize = fSize or 12
		end
		applyFont(fs, fs._mpBaseSize, isBold and "semibold" or "regular", "")
	end

	local function getProfPalette()
		local active = Theme and Theme.GetActivePalette and Theme.GetActivePalette()
		if active then return active end
		if Theme and Theme.PALETTES and Theme.GetMode then
			return Theme.PALETTES[Theme.GetMode()] or Theme.PALETTES.dark
		end
		return nil
	end

	local function colorHex(col, fallback)
		if type(col) ~= "table" then return fallback or "ffffff" end
		local r = math.max(0, math.min(255, math.floor((col[1] or 1) * 255 + 0.5)))
		local g = math.max(0, math.min(255, math.floor((col[2] or 1) * 255 + 0.5)))
		local b = math.max(0, math.min(255, math.floor((col[3] or 1) * 255 + 0.5)))
		return string.format("%02x%02x%02x", r, g, b)
	end

	-- Zero amount with the themed copper "c" unit (ink defaults to muted)
	local function readable(value)
		if type(_G.issecretvalue) == "function" then
			local ok, secret = pcall(_G.issecretvalue, value)
			if not ok or secret then return false end
		end
		if type(value) == "table" and type(_G.issecrettable) == "function" then
			local ok, secret = pcall(_G.issecrettable, value)
			if not ok or secret then return false end
		end
		return true
	end

	local function zeroCopper(inkHex)
		local pal = getProfPalette()
		local ink = inkHex or colorHex(pal and pal.textMuted, "8e8e93")
		local text = Theme and Theme.FormatMoneyText and Theme.FormatMoneyText(0, false, false)
		if text then
			local textHex = colorHex(pal and pal.hexText, "ffffff")
			return (text:gsub("|cff" .. textHex, "|cff" .. ink, 1))
		end
		return "|cff" .. ink .. "0|r|cff" .. ((pal and pal.hexCopper) or "e08a5e") .. "c|r"
	end

	local function formatMoney(copper, showZero)
		local pal = getProfPalette()
		local mutedHex = colorHex(pal and pal.textMuted, "8e8e93")
		if not readable(copper) then return "|cff" .. mutedHex .. "—|r" end
		if copper == nil then return "|cff" .. mutedHex .. "—|r" end
		local n = math.floor(tonumber(copper) or 0)
		if n == 0 then
			return showZero and zeroCopper() or ("|cff" .. mutedHex .. "—|r")
		end
		if Theme and Theme.FormatMoneyFable then
			return Theme.FormatMoneyFable(math.abs(n), false)
		elseif Theme and Theme.FormatMoneyParts then
			local parts = Theme.FormatMoneyParts(math.abs(n), nil, true)
			if parts and parts.text then
				return parts.text
			end
		end
		return ns.FormatMoneyCompact(math.abs(n))
	end

	local function formatSalesPerDay(val)
		local pal = getProfPalette()
		local mutedHex = colorHex(pal and pal.textMuted, "8e8e93")
		if not val then return "|cff" .. mutedHex .. "—|r" end
		local raw = (Theme and Theme.FormatSalesPerDay) and Theme.FormatSalesPerDay(val) or tostring(val)
		if pal and pal.mode == "light" and type(raw) == "string" then
			raw = raw:gsub("|cff7fd4ff", "|cff0066cc"):gsub("|cff6e6b64", "|cff" .. mutedHex):gsub("|cff7a766e", "|cff" .. mutedHex)
		end
		return raw
	end

	local function formatNetCostOrProfit(netCopper)
		local pal = getProfPalette()
		local mutedHex = colorHex(pal and pal.textMuted, "8e8e93")
		if netCopper == nil then return "|cff" .. mutedHex .. "—|r" end
		local greenHex = colorHex(pal and pal.accentGreen, "30d158")
		local orangeHex = colorHex(pal and pal.accentOrange, "ff9230")
		local n = math.floor(tonumber(netCopper) or 0)
		if n < 0 then
			return "|cff" .. greenHex .. "+|r" .. formatMoney(-n, true) .. "  |cff" .. greenHex .. "Profit|r"
		elseif n == 0 then
			return zeroCopper(greenHex) .. "|cff" .. greenHex .. " (Break-Even)|r"
		else
			return "|cff" .. orangeHex .. "-|r" .. formatMoney(n, true)
		end
	end

	local function findOptLabel(list, key)
		for _, it in ipairs(list) do
			if it.key == key then return it.label end
		end
		return list[1] and list[1].label or ""
	end

	local function getItemIcon(itemID, fallbackIcon)
		if itemID and itemID > 0 then
			return ns.ItemIcon(itemID, fallbackIcon or "Interface\\Icons\\INV_Scroll_03")
		end
		return fallbackIcon or "Interface\\Icons\\INV_Scroll_03"
	end

	local function defaultProfBounds(profKey)
		local pInfo = MP.PROFESSIONS[profKey] or MP.PROFESSIONS.alchemy
		local live = MP.ScanPlayerProfessions()[profKey]
		local startVal = (live and live.rank and live.rank < 300 and live.rank) or pInfo.defaultStart or 1
		return startVal, 300
	end

	local function ensureCharTargets(db)
		local ck = MP.GetCharKey()
		db.profTargetsByChar = db.profTargetsByChar or {}
		if type(db.profTargetsByChar[ck]) ~= "table" then
			db.profTargetsByChar[ck] = {}
			if type(db.profTargets) == "table" and not db._targetsCharKey then
				for k, v in pairs(db.profTargets) do
					if type(v) == "table" then
						db.profTargetsByChar[ck][k] = { from = v.from, to = v.to }
					end
				end
			end
		end
		if db._targetsCharKey ~= ck then
			db._targetsCharKey = ck
			db.profTargets = db.profTargetsByChar[ck]
		elseif db.profTargets ~= db.profTargetsByChar[ck] and type(db.profTargets) == "table" then
			db.profTargetsByChar[ck] = db.profTargets
		end
		return db.profTargetsByChar[ck]
	end

	local function getProfBounds(profKey)
		local db = getProfDB()
		local targets = ensureCharTargets(db)
		local saved = targets[profKey]
		if not saved then
			local from, to = defaultProfBounds(profKey)
			saved = { from = from, to = to }
			targets[profKey] = saved
		end
		saved.from = math.max(1, math.min(299, math.floor(tonumber(saved.from) or 1)))
		saved.to = math.max(saved.from + 1, math.min(300, math.floor(tonumber(saved.to) or 300)))
		return saved.from, saved.to
	end

	local function setProfBounds(profKey, fromVal, toVal)
		local db = getProfDB()
		local targets = ensureCharTargets(db)
		fromVal = math.max(1, math.min(299, math.floor(tonumber(fromVal) or 1)))
		toVal = math.max(fromVal + 1, math.min(300, math.floor(tonumber(toVal) or 300)))
		targets[profKey] = { from = fromVal, to = toVal }
		return fromVal, toVal
	end

	local function applyRowHighlight(r)
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.sep = r:CreateTexture(nil, "BORDER")
		r.sep:SetPoint("BOTTOMLEFT", 16, 0)
		r.sep:SetPoint("BOTTOMRIGHT", -16, 0)
		r.sep:SetHeight(1)
		local pal = getProfPalette()
		if pal and pal.separator then
			r.sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.25) * 0.45)
		else
			r.sep:SetColorTexture(1, 1, 1, 0.07)
		end
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		if pal and pal.cardHover then
			hl:SetColorTexture(pal.cardHover[1], pal.cardHover[2], pal.cardHover[3], pal.cardHover[4] or 0.06)
		else
			hl:SetColorTexture(1, 1, 1, 0.05)
		end
		r.hl = hl
	end

	local function sortProfRows(rows, col, asc, fallbackCol, stringCols)
		stringCols = stringCols or {}
		table.sort(rows, function(a, b)
			local va, vb = a[col], b[col]
			if va == vb and fallbackCol then
				va, vb = a[fallbackCol], b[fallbackCol]
			end
			if va == nil and vb == nil then return false end
			if va == nil then return false end
			if vb == nil then return true end
			if stringCols[col] or (type(va) == "string" and type(vb) == "string") then
				local sa, sb = tostring(va):lower(), tostring(vb):lower()
				if sa == sb then return (a.stepNum or a.itemID or 0) < (b.stepNum or b.itemID or 0) end
				if asc then return sa < sb else return sa > sb end
			end
			local na, nb = tonumber(va) or 0, tonumber(vb) or 0
			if na == nb then return (a.stepNum or a.itemID or 0) < (b.stepNum or b.itemID or 0) end
			if asc then return na < nb else return na > nb end
		end)
	end

	local PROF_ROW_H = 34
	local PROF_COL_GAP = 5

	local function createProfTable(parent, topOffset, bottomOffset, columns, fillRow, sortKey)
		-- Data-model cell strings (demand badges, source labels) carry raw colour codes:
		-- translate them to the active palette once the row's cells exist.
		local function initAndFillRow(rowFrame, data, tbl)
			local firstInit = (rowFrame.cells == nil)
			fillRow(rowFrame, data, tbl)
			if firstInit and Theme and Theme.AutoThemeCells then Theme.AutoThemeCells(rowFrame) end
			-- Uncoloured cell text ("Starter", "Trainer") follows the appearance instead of staying white
			local tc = (getProfPalette() or {}).text
			if tc and rowFrame.cells then
				for _, cell in ipairs(rowFrame.cells) do
					local fs = (type(cell) == "table" and cell.fs) or cell
					if fs and fs.SetTextColor then fs:SetTextColor(tc[1], tc[2], tc[3], 1) end
				end
			end
		end
		columns = ns.Window.CopyColumns(columns)
		local moneyColumns = { unlockCost = true, grossMats = true, resale = true, netCost = true,
			ahResaleTotal = true, vendorResaleTotal = true, ahUnit = true, vendorUnit = true,
			unitPrice = true, lineCost = true, craftCost = true, resaleUnit = true, profitCraft = true, salesValue = true }
		for _, col in ipairs(columns) do
			col.minWidth = col.minWidth or math.floor(col.width * 0.70)
			if moneyColumns[col.key] then col.minWidth = math.max(col.minWidth, col.compactMoney and 54 or 90) end
			if moneyColumns[col.key] then col.align = "RIGHT" end
		end
		local tbl = { columns = columns, colX = {}, resizeParent = parent, professor = true, proportional = true }
		mmApp.ui.resizeTables = mmApp.ui.resizeTables or {}
		mmApp.ui.resizeTables[#mmApp.ui.resizeTables + 1] = tbl
		local headerBar = CreateFrame("Frame", nil, parent)
		headerBar:SetPoint("TOPLEFT", 0, topOffset)
		headerBar:SetPoint("TOPRIGHT", 0, topOffset)
		headerBar:SetHeight(28)
		local hUnderline = headerBar:CreateTexture(nil, "BORDER")
		hUnderline:SetPoint("BOTTOMLEFT", 0, 0)
		hUnderline:SetPoint("BOTTOMRIGHT", 0, 0)
		hUnderline:SetHeight(1)
		local pal0 = getProfPalette()
		if pal0 and pal0.separator then
			hUnderline:SetColorTexture(pal0.separator[1], pal0.separator[2], pal0.separator[3], pal0.separator[4] or 0.45)
		else
			hUnderline:SetColorTexture(0.35, 0.35, 0.38, 0.45)
		end
		tbl.headerBar = headerBar
		tbl.hUnderline = hUnderline

		local curX = 4
		tbl.hdrBtns = {}
		for i, col in ipairs(columns) do
			tbl.colX[i] = curX
			local hb = CreateFrame("Button", nil, headerBar)
			hb:SetSize(col.width, 26)
			hb:SetPoint("LEFT", headerBar, "LEFT", curX, 0)
			hb.fs = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			hb.fs:SetAllPoints()
			hb.fs:SetJustifyH(col.align or "LEFT")
			hb.fs:SetWordWrap(false)
			applyFont(hb.fs, 11, "regular")
			hb:SetScript("OnClick", function()
				if not sortKey or not col.sortCol then return end
				local st = papp.sortState[sortKey]
				if st.col == col.sortCol then
					st.asc = not st.asc
				else
					st.col = col.sortCol
					st.asc = (col.defaultAsc ~= false)
				end
				mmApp.refresh()
			end)
			if col.hint then
				hb:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:AddLine(col.label, 1, 0.82, 0)
					GameTooltip:AddLine(col.hint, 1, 1, 1, true)
					GameTooltip:Show()
				end)
				hb:SetScript("OnLeave", GameTooltip_Hide)
			end
			tbl.hdrBtns[i] = hb
			curX = curX + col.width + PROF_COL_GAP
		end

		local inset = CreateFrame("Frame", nil, parent)
		inset:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -1)
		inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottomOffset or 0)
		tbl.inset = inset

		function tbl.updateHeaders()
			local st = sortKey and papp.sortState[sortKey]
			local pal = getProfPalette()
			local mutedCol = (pal and pal.textMuted) or { 0.60, 0.60, 0.65 }
			local activeCol = (pal and (pal.textBlue or pal.accentBlue)) or { 0.04, 0.52, 1.0 }
			local activeHex = colorHex(activeCol, "0a84ff")
			if hUnderline and pal and pal.separator then
				hUnderline:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], pal.separator[4] or 0.08)
			end
			local appleRoot = (Theme and Theme.APPLE_ASSET_ROOT) or ("Interface\\AddOns\\" .. tostring(ADDON or "MerchantMaster") .. "\\Assets\\apple\\")
		local chevTex = (Theme and Theme.ASSETS and Theme.ASSETS.icon_chevron_down) or (appleRoot .. "icon_chevron_down")
			for i, col in ipairs(columns) do
				local lbl = col.label or ""
				local btn = tbl.hdrBtns[i]
				local isActive = st and col.sortCol and st.col == col.sortCol
				applyFont(btn.fs, 11, isActive and "semibold" or "regular")
				if isActive then
					local arrow = st.asc
						and (" |T" .. chevTex .. ":9:9:1:0:16:16:0:16:16:0|t")
						or (" |T" .. chevTex .. ":9:9:1:0:16:16:0:16:0:16|t")
					btn.fs:SetText("|cff" .. activeHex .. lbl .. "|r" .. arrow)
					if btn.fs.SetTextColor then btn.fs:SetTextColor(activeCol[1], activeCol[2], activeCol[3], 1) end
				else
					btn.fs:SetText(lbl)
					if btn.fs.SetTextColor then btn.fs:SetTextColor(mutedCol[1], mutedCol[2], mutedCol[3], 1) end
				end
			end
		end

		if CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar then
			local scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
			scrollBox:SetPoint("TOPLEFT", 4, -4)
			scrollBox:SetPoint("BOTTOMRIGHT", -18, 4)
			local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
			scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 3, -2)
			scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 3, 2)
			if Theme.SlimScrollBar then Theme.SlimScrollBar(scrollBar) end

			local view = CreateScrollBoxListLinearView()
			view:SetElementExtent(PROF_ROW_H)
			view:SetElementInitializer("Button", function(rowFrame, elementData)
				if rowFrame.RegisterForClicks then rowFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
				initAndFillRow(rowFrame, elementData, tbl)
				if tbl.layoutRow then tbl.layoutRow(rowFrame) end
			end)
			ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
			tbl.scrollBox = scrollBox

			function tbl.setRows(dataList)
				local rows = dataList or {}
				for idx, d in ipairs(rows) do
					d._rowIndex = idx
				end
				scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or true)
			end
		else
			tbl.pool = {}
			tbl.data = {}
			function tbl.setRows(dataList)
				tbl.data = dataList or {}
				for idx, d in ipairs(tbl.data) do
					d._rowIndex = idx
					local rf = tbl.pool[idx]
					if not rf then
						rf = CreateFrame("Button", nil, inset)
						if rf.RegisterForClicks then rf:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
						rf:SetHeight(PROF_ROW_H)
						rf:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4 - (idx - 1) * PROF_ROW_H)
						rf:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -14, -4 - (idx - 1) * PROF_ROW_H)
						tbl.pool[idx] = rf
					end
					rf:Show()
					initAndFillRow(rf, d, tbl)
				end
				for idx = #tbl.data + 1, #tbl.pool do
					tbl.pool[idx]:Hide()
				end
			end
		end

		function tbl.forEachRow(fn)
			if tbl.scrollBox and tbl.scrollBox.ForEachFrame then
				tbl.scrollBox:ForEachFrame(fn)
			elseif tbl.pool then
				for _, rf in ipairs(tbl.pool) do
					if rf:IsShown() then fn(rf) end
				end
			end
		end

		tbl.updateHeaders()
		return tbl
	end

	local function shiftKeyDown()
		if type(_G.IsShiftKeyDown) ~= "function" then return false end
		local ok, down = pcall(_G.IsShiftKeyDown)
		if not ok or not readable(down) then return nil end
		return down == true
	end

	local function tryCraftOrSearchStep(step)
		if not step then return end
		if step.spellID and C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()
			and C_TradeSkillUI.OpenRecipe and (not InCombatLockdown or not InCombatLockdown())
			and ((ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())) then
			local ok = pcall(C_TradeSkillUI.OpenRecipe, step.spellID)
			if ok then return end
		end
		local targetName = step.rawRecipeName or step.name
		if GetNumTradeSkills and GetTradeSkillInfo and DoTradeSkill and TradeSkillFrame and TradeSkillFrame:IsShown() then
			local num = GetNumTradeSkills() or 0
			for i = 1, num do
				local sName, sType = GetTradeSkillInfo(i)
				if sType ~= "header" and sName == targetName then
					DoTradeSkill(i, math.max(1, step.crafts or 1))
					return
				end
			end
		end
		if GetNumCrafts and GetCraftInfo and DoCraft and CraftFrame and CraftFrame:IsShown() then
			local num = GetNumCrafts() or 0
			for i = 1, num do
				local cName = GetCraftInfo(i)
				if cName == targetName then
					DoCraft(i)
					return
				end
			end
		end
		if step.rec and step.rec.ri and step.rec.ri > 0 and step.unlockCost and step.unlockCost > 0 and step.rec.src == "ah" then
			mmApp.searchAH(MP.ItemName(step.rec.ri), 1, step.rec.ri)
			return
		end
		if step.reagentDetails and #step.reagentDetails > 0 then
			for _, rg in ipairs(step.reagentDetails) do
				if not rg.isVendor then
					mmApp.searchAH(MP.ItemName(rg.itemID), rg.qtyPerCraft * math.max(1, step.crafts or 1), rg.itemID)
					return
				end
			end
		end
		if step.itemID and step.itemID > 0 then
			mmApp.searchAH(MP.ItemName(step.itemID), 1, step.itemID)
		end
	end

	local function isBookMilestone(row)
		local d = row and (row._orig or row)
		return d ~= nil and d.isMilestone == true and (tonumber(d.itemID) or 0) > 0
	end

	local function resolveProfQueueRecipe(row, profKeyOverride)
		local d = row and (row._orig or row)
		if not d or d.isMilestone or d.srcType == "gather" then return nil end
		if not ns.ResolveCraftingOrderRecipe then return nil end
		local outID = tonumber(d.outputItemID or d.itemID)
		local profKey = profKeyOverride or d.prof or (d.rec and d.rec.prof) or (getProfDB().selectedProf or "alchemy")
		return ns.ResolveCraftingOrderRecipe({
			spellID = d.spellID,
			outputItemID = (outID and outID > 0) and outID or nil,
			prof = profKey,
		}, ns.GetPlayerProfessions and ns.GetPlayerProfessions() or nil, false)
	end

	local function getScrollCartEntry(itemID)
		local id = tonumber(itemID) or 0
		if id <= 0 or not (MerchantMasterDB and type(MerchantMasterDB.shoppingList) == "table") then return nil end
		local key = "prof_scroll:" .. tostring(id)
		for _, cur in ipairs(MerchantMasterDB.shoppingList) do
			if cur and cur.key == key then return cur end
		end
		return nil
	end

	local function ensureScrollInCart(sc, suppressRefresh)
		local id = sc and tonumber(sc.itemID) or 0
		if id <= 0 or (tonumber(sc.favorTokens) or 0) > 0 or not mmApp.addUnifiedShoppingItem then return false end
		if getScrollCartEntry(id) then return false end
		mmApp._profPreviewCleared = nil
		return mmApp.addUnifiedShoppingItem({
			key = "prof_scroll:" .. tostring(id),
			name = MP.ItemName(id),
			itemID = id,
			qty = math.max(1, math.floor((tonumber(sc.qty) or 1) + 0.5)),
			sourceLabel = "Recipe Scroll",
		}, suppressRefresh)
	end

	local function removeScrollFromCart(itemID)
		local id = tonumber(itemID) or 0
		if id <= 0 or not getScrollCartEntry(id) or not mmApp.removeShoppingMainItem then return false end
		return mmApp.removeShoppingMainItem({ sourceKind = "shopping", key = "prof_scroll:" .. tostring(id) })
	end

	local function getProfRowQueuedQty(row)
		local d = row and (row._orig or row)
		if not d then return 0 end
		if isBookMilestone(d) then
			local entry = getScrollCartEntry(d.itemID)
			return entry and math.max(0, math.floor((tonumber(entry.qty) or 0) + 0.5)) or 0
		end
		local rec = resolveProfQueueRecipe(d)
		if not rec or not mmApp.getRecipeShoppingQty then return 0 end
		return tonumber(mmApp.getRecipeShoppingQty(rec)) or 0
	end

	local function canQueueProfRow(row)
		return isBookMilestone(row) or resolveProfQueueRecipe(row) ~= nil
	end

	local function extractProfStepReagents(step)
		local r = step and step.rec and step.rec.r
		if type(r) == "table" and #r > 0 then
			return r
		end
		return nil
	end

	local function adjustProfRowShiftQty(row, delta)
		local d = row and (row._orig or row)
		if not d then return 0 end
		local step = tonumber(delta) or 0
		if step == 0 then return getProfRowQueuedQty(d) end
		if isBookMilestone(d) then
			local cur = getProfRowQueuedQty(d)
			local nextQty = math.max(0, cur + step)
			if nextQty <= 0 then
				removeScrollFromCart(d.itemID)
			elseif cur == 0 then
				ensureScrollInCart({ itemID = d.itemID, qty = nextQty }, false)
			else
				local entry = getScrollCartEntry(d.itemID)
				if entry then
					entry.qty = nextQty
					if mmApp.syncUnifiedShoppingList then mmApp.syncUnifiedShoppingList() end
				end
			end
			if papp.RepaintShoppingQty then papp.RepaintShoppingQty() end
			return nextQty
		end
		local rec = resolveProfQueueRecipe(d)
		if not rec or not mmApp.adjustRecipeShoppingQty then return 0 end
		local stepMeta = nil
		if step > 0 then
			local stepReagents = extractProfStepReagents(d)
			local kept = math.max(0, math.floor((tonumber(d.unitsKeptForLater) or 0) + 0.5))
			if stepReagents or kept > 0 then
				stepMeta = { reagents = stepReagents, reusedQty = kept > 0 and kept or nil }
			end
		end
		return mmApp.adjustRecipeShoppingQty(rec, step, stepMeta)
	end

	local function clickProfStepCartButton(row, mouseBtn)
		local d = row and (row._orig or row)
		if not d then return end
		if mouseBtn ~= nil and (not readable(mouseBtn) or type(mouseBtn) ~= "string") then return end
		if (d.isMilestone and not isBookMilestone(d)) or d.srcType == "gather" then
			tryCraftOrSearchStep(d)
			return
		end
		if isBookMilestone(d) then
			if mouseBtn == "RightButton" then
				adjustProfRowShiftQty(d, -math.max(1, getProfRowQueuedQty(d)))
			elseif getProfRowQueuedQty(d) == 0 then
				adjustProfRowShiftQty(d, 1)
			else
				adjustProfRowShiftQty(d, 1)
			end
			return
		end
		local rec = resolveProfQueueRecipe(d)
		if not rec or not mmApp.adjustRecipeShoppingQty then return end
		local curQty = tonumber(mmApp.getRecipeShoppingQty(rec)) or 0
		if mouseBtn == "RightButton" then
			if curQty > 0 then mmApp.adjustRecipeShoppingQty(rec, -curQty) end
			if d.scrollNeed and d.scrollNeed.itemID then removeScrollFromCart(d.scrollNeed.itemID) end
			return
		end
		local qMade = math.max(1, tonumber(rec.numMade) or 1)
		local targetUnits = math.max(1, tonumber(d.crafts) or 1) * qMade
		local delta = (curQty < targetUnits) and (targetUnits - curQty) or qMade
		local kept = math.min(targetUnits, math.max(0, math.floor((tonumber(d.unitsKeptForLater) or 0) + 0.5)))
		mmApp.adjustRecipeShoppingQty(rec, delta, {
			reagents = extractProfStepReagents(d),
			reusedQty = kept > 0 and kept or nil,
		})
		if d.scrollNeed and not (d.rec and MP.IsRecipeKnownByPlayer(d.rec)) then
			ensureScrollInCart(d.scrollNeed, false)
		end
	end

	function papp.addOverviewToCart()
		local steps = papp.lastVisiblePathSteps or (papp.lastPathResult and papp.lastPathResult.steps) or {}
		if #steps == 0 then return 0 end
		local ordered = {}
		for i, st in ipairs(steps) do ordered[i] = st end
		table.sort(ordered, function(a, b) return (a.stepNum or 0) < (b.stepNum or 0) end)

		local profKey = getProfDB().selectedProf or "alchemy"
		local targetBySpell = {}
		local recipeOrder = {}
		local scrolls = {}
		for _, st in ipairs(ordered) do
			if isBookMilestone(st) then
				scrolls[#scrolls + 1] = { itemID = st.itemID, qty = 1 }
			else
				local rec = resolveProfQueueRecipe(st, profKey)
				if rec then
					local key = tostring(rec.spellID or rec.idx or rec.outputItemID or st.name)
					local qMade = math.max(1, tonumber(rec.numMade) or 1)
					local addUnits = math.max(1, tonumber(st.crafts) or 1) * qMade
					local addReused = math.min(addUnits, math.max(0, math.floor((tonumber(st.unitsKeptForLater) or 0) + 0.5)))
					local bucket = targetBySpell[key]
					if not bucket then
						bucket = { rec = rec, units = 0, reusedUnits = 0, reagents = extractProfStepReagents(st) }
						targetBySpell[key] = bucket
						recipeOrder[#recipeOrder + 1] = bucket
					elseif not bucket.reagents then
						bucket.reagents = extractProfStepReagents(st)
					end
					bucket.units = bucket.units + addUnits
					bucket.reusedUnits = bucket.reusedUnits + addReused
				end
				if st.scrollNeed and not (st.rec and MP.IsRecipeKnownByPlayer(st.rec)) then
					scrolls[#scrolls + 1] = st.scrollNeed
				end
			end
		end

		local changed = 0
		for _, bucket in ipairs(recipeOrder) do
			local cur = (mmApp.getRecipeShoppingQty and tonumber(mmApp.getRecipeShoppingQty(bucket.rec))) or 0
			if mmApp.adjustRecipeShoppingQty then
				local meta = {
					reagents = bucket.reagents,
					reusedQty = bucket.reusedUnits,
					setReusedQty = true,
				}
				if cur < bucket.units then
					local after = mmApp.adjustRecipeShoppingQty(bucket.rec, bucket.units - cur, meta)
					if (tonumber(after) or 0) > cur then changed = changed + 1 end
				else
					mmApp.adjustRecipeShoppingQty(bucket.rec, 0, meta)
				end
			end
		end
		for _, sc in ipairs(scrolls) do
			if ensureScrollInCart(sc, true) then changed = changed + 1 end
		end
		if mmApp.hasUnifiedShoppingItems and mmApp.hasUnifiedShoppingItems() and mmApp.syncUnifiedShoppingList then
			mmApp.syncUnifiedShoppingList()
		end
		if papp.RepaintShoppingQty then papp.RepaintShoppingQty() end
		if changed > 0 then
			if mmApp.ui and mmApp.ui.toast and mmApp.ui.toast.ShowToast then
				mmApp.ui.toast:ShowToast(string.format("Added %d leveling item%s to Shopping Cart", changed, changed == 1 and "" or "s"), "success")
			end
		elseif mmApp.toggleShoppingWindow then
			mmApp.toggleShoppingWindow(true)
		end
		return changed
	end

	papp.lockedRoutes = papp.lockedRoutes or {}

	local function shallowCopyTbl(src)
		if type(src) ~= "table" then return nil end
		local out = {}
		for k, v in pairs(src) do
			if type(v) ~= "table" and type(v) ~= "function" then
				out[k] = v
			end
		end
		return out
	end

	local function serializeLockedSnapshot(res)
		if type(res) ~= "table" then return nil end
		local out = {
			profKey = res.profKey,
			startSkill = res.startSkill,
			targetSkill = res.targetSkill,
			requestedTarget = res.requestedTarget,
			charLevel = res.charLevel,
			isAutoCharLv = res.isAutoCharLv,
			goalMode = res.goalMode,
			recipeFilter = res.recipeFilter,
			knownCapSkill = res.knownCapSkill,
			usedFallbackFilter = res.usedFallbackFilter,
			totalCrafts = res.totalCrafts,
			rawGrossMats = res.rawGrossMats,
			ownedSavings = res.ownedSavings,
			totalGrossMats = res.totalGrossMats,
			totalTrainUnlocks = res.totalTrainUnlocks,
			totalFavorTokens = res.totalFavorTokens,
			totalSpend = res.totalSpend,
			totalResale = res.totalResale,
			netCost = res.netCost,
			levelLocked = res.levelLocked,
			alreadyAtLevelCap = res.alreadyAtLevelCap,
			unreachable = res.unreachable,
			levelCapInfo = shallowCopyTbl(res.levelCapInfo),
			legacy = shallowCopyTbl(res.legacy),
			fallbackRange = shallowCopyTbl(res.fallbackRange),
			steps = {},
			shoppingList = {},
			shoppingListByLevel = {},
		}
		for i, st in ipairs(res.steps or {}) do
			local c = shallowCopyTbl(st) or {}
			if type(st.scrollNeed) == "table" then c.scrollNeed = shallowCopyTbl(st.scrollNeed) end
			if type(st.trainerInfo) == "table" then c.trainerInfo = shallowCopyTbl(st.trainerInfo) end
			if type(st.keptForSteps) == "table" then
				c.keptForSteps = {}
				for ki, ks in ipairs(st.keptForSteps) do
					c.keptForSteps[ki] = shallowCopyTbl(ks)
				end
			end
			if type(st.rolledInSteps) == "table" then
				c.rolledInSteps = {}
				for ri, rs in ipairs(st.rolledInSteps) do
					c.rolledInSteps[ri] = shallowCopyTbl(rs)
				end
			end
			if type(st.reagentDetails) == "table" then
				c.reagentDetails = {}
				for rgi, rg in ipairs(st.reagentDetails) do
					c.reagentDetails[rgi] = {
						itemID = rg.itemID,
						qtyPerCraft = rg.qtyPerCraft,
						unitCost = rg.unitCost,
						ahUnitCost = rg.ahUnitCost,
						source = rg.source,
						isVendor = rg.isVendor,
						isSubCraft = rg.isSubCraft,
					}
				end
			end
			if type(st.ev) == "table" then
				c.ev = {
					effReq = st.ev.effReq,
					effRlv = st.ev.effRlv,
					isUnlisted = st.ev.isUnlisted,
					isCustomPrice = st.ev.isCustomPrice,
					favorTokens = st.ev.favorTokens,
					vendorCopperCost = st.ev.vendorCopperCost,
					vendorName = st.ev.vendorName,
					vendorUnit = st.ev.vendorUnit,
					ahGrossUnit = st.ev.ahGrossUnit,
					ahCutUnit = st.ev.ahCutUnit,
					relistLossUnit = st.ev.relistLossUnit,
					ahNetUnit = st.ev.ahNetUnit,
					ahPriceSource = st.ev.ahPriceSource,
					lastKnownAHUnit = st.ev.lastKnownAHUnit,
					lastKnownAHSource = st.ev.lastKnownAHSource,
					canAH = st.ev.canAH,
					repStanding = st.ev.repStanding,
					scrollViaAH = st.ev.scrollViaAH,
				}
				if type(st.ev.demand) == "table" then
					c.ev.demand = shallowCopyTbl(st.ev.demand)
				end
				c.demand = c.ev.demand
			end
			out.steps[i] = c
		end
		for i, row in ipairs(res.shoppingList or {}) do
			out.shoppingList[i] = shallowCopyTbl(row)
		end
		for i, row in ipairs(res.shoppingListByLevel or {}) do
			out.shoppingListByLevel[i] = shallowCopyTbl(row)
		end
		return out
	end

	local function rehydrateLockedSnapshot(saved)
		if type(saved) ~= "table" or type(saved.pathRes) ~= "table" then return nil end
		local res = saved.pathRes
		local pk = saved.profKey or res.profKey
		res.profKey = pk
		res.profInfo = pk and MP.PROFESSIONS[pk] or nil
		for _, st in ipairs(res.steps or {}) do
			if st.spellID and MP.RECIPE_BY_SPELL and MP.RECIPE_BY_SPELL[st.spellID] then
				st.rec = MP.RECIPE_BY_SPELL[st.spellID]
			end
			if type(st.ev) == "table" and type(st.ev.demand) == "table" then
				st.demand = st.ev.demand
			end
		end
		return saved
	end

	function papp.getLockedSnapshot(profKey)
		local pk = profKey or (getProfDB().selectedProf or "alchemy")
		local mem = papp.lockedRoutes and papp.lockedRoutes[pk] or nil
		if mem and mem.pathRes then return mem end
		local db = getProfDB()
		local ck = MP.GetCharKey()
		local byChar = db.lockedRoutesByChar and db.lockedRoutesByChar[ck]
		local saved = byChar and byChar[pk] or nil
		if saved and saved.pathRes then
			local hydrated = rehydrateLockedSnapshot(saved)
			if hydrated then
				papp.lockedRoutes[pk] = hydrated
				return hydrated
			end
		end
		return nil
	end

	function papp.isViewLocked(profKey)
		local snap = papp.getLockedSnapshot(profKey)
		return snap ~= nil and snap.pathRes ~= nil
	end

	function papp.syncLockUI(profKey)
		local pk = profKey or (getProfDB().selectedProf or "alchemy")
		local locked = papp.isViewLocked(pk)
		local label = locked and "Locked" or "Lock View"
		if papp.ui.pathLockBtn then
			papp.ui.pathLockBtn:SetText(label)
			if papp.ui.pathLockBtn.SetActive then papp.ui.pathLockBtn:SetActive(locked) end
		end
		if papp.ui.shopLockBtn then
			papp.ui.shopLockBtn:SetText(label)
			if papp.ui.shopLockBtn.SetActive then papp.ui.shopLockBtn:SetActive(locked) end
		end
		if papp.ui.pathLockBadge then
			papp.ui.pathLockBadge:SetShown(locked)
		end
		if papp.ui.pathShiftBadge then
			papp.ui.pathShiftBadge:ClearAllPoints()
			local anchor = (locked and papp.ui.pathLockBadge) or (papp.ui.pathBadge and papp.ui.pathBadge.frame)
			if anchor then
				papp.ui.pathShiftBadge:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
			end
		end
		return locked
	end

	function papp.setViewLocked(profKey, locked, silent)
		local pk = profKey or (getProfDB().selectedProf or "alchemy")
		local pName = (MP.PROFESSIONS[pk] and MP.PROFESSIONS[pk].name) or pk
		local db = getProfDB()
		local ck = MP.GetCharKey()
		db.lockedRoutesByChar = db.lockedRoutesByChar or {}
		db.lockedRoutesByChar[ck] = db.lockedRoutesByChar[ck] or {}
		if locked then
			local snapRes = papp.lastPathResult
			if not snapRes or (snapRes.profKey and snapRes.profKey ~= pk) then
				local fromS, toS = getProfBounds(pk)
				snapRes = MP.SolveProfessionPath(pk, {
					startSkill = fromS,
					targetSkill = toS,
					liveProfs = MP.ScanPlayerProfessions(),
				})
			end
			local ts = time and time() or 0
			papp.lockedRoutes[pk] = {
				profKey = pk,
				pathRes = snapRes,
				lockedAt = ts,
			}
			db.lockedRoutesByChar[ck][pk] = {
				profKey = pk,
				pathRes = serializeLockedSnapshot(snapRes),
				lockedAt = ts,
			}
			papp.syncLockUI(pk)
			if not silent and mmApp.ui and mmApp.ui.toast and mmApp.ui.toast.ShowToast then
				mmApp.ui.toast:ShowToast(string.format("Guide locked (%s) - crafts will not change on refresh", pName), "info")
			end
		else
			papp.lockedRoutes[pk] = nil
			db.lockedRoutesByChar[ck][pk] = nil
			papp.syncLockUI(pk)
			if not silent then
				if mmApp.ui and mmApp.ui.toast and mmApp.ui.toast.ShowToast then
					mmApp.ui.toast:ShowToast(string.format("Guide unlocked (%s) - live AH updates resumed", pName), "info")
				end
				if mmApp.refresh then mmApp.refresh() end
			end
		end
		return papp.isViewLocked(pk)
	end

	function papp.toggleViewLock(profKey)
		local pk = profKey or (getProfDB().selectedProf or "alchemy")
		return papp.setViewLocked(pk, not papp.isViewLocked(pk))
	end

	local function ensureLockPromptModal()
		if papp.ui.lockPromptModal then return papp.ui.lockPromptModal end
		local modal = Theme.CreateFloatingWindow("MerchantMasterProfLockModal", "Lock Leveling Guide?", 440, 148, {
			positionKey = "prof_lock",
		})
		modal:SetFrameStrata("FULLSCREEN_DIALOG")
		local body = modal.body

		local msgFs = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		msgFs:SetPoint("TOPLEFT", 6, -6)
		msgFs:SetPoint("RIGHT", -6, 0)
		msgFs:SetJustifyH("LEFT")
		msgFs:SetWordWrap(true)
		applyFont(msgFs, 13, "semibold")
		msgFs:SetText("Do you want to lock the guide so crafts don't change on refresh?")
		modal.msgFs = msgFs

		local subFs = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		subFs:SetPoint("TOPLEFT", msgFs, "BOTTOMLEFT", 0, -6)
		subFs:SetPoint("RIGHT", -6, 0)
		subFs:SetJustifyH("LEFT")
		subFs:SetWordWrap(true)
		applyFont(subFs, 11, "regular")
		subFs:SetText("You can unlock it anytime using the Lock View button.")
		modal.subFs = subFs

		local lockBtn = Theme.CreatePlateButton(body, "Lock Guide", 122, 28, { primary = true })
		lockBtn:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -4, 4)
		applyFont(lockBtn.fs or (lockBtn.GetFontString and lockBtn:GetFontString()), 12, "semibold")
		lockBtn:SetScript("OnClick", function()
			local pk = modal._profKey or (getProfDB().selectedProf or "alchemy")
			modal:Hide()
			papp.setViewLocked(pk, true)
		end)
		modal.lockBtn = lockBtn

		local keepBtn = Theme.CreatePlateButton(body, "Keep Unlocked", 126, 28, { variant = "secondary" })
		keepBtn:SetPoint("RIGHT", lockBtn, "LEFT", -8, 0)
		applyFont(keepBtn.fs or (keepBtn.GetFontString and keepBtn:GetFontString()), 12, "regular")
		keepBtn:SetScript("OnClick", function()
			modal:Hide()
		end)
		modal.keepBtn = keepBtn

		papp.ui.lockPromptModal = modal
		return modal
	end

	function papp.promptLockGuide(profKey)
		local pk = profKey or (getProfDB().selectedProf or "alchemy")
		if papp.isViewLocked(pk) then return nil end
		local modal = ensureLockPromptModal()
		modal._profKey = pk
		local pal = getProfPalette()
		if modal.msgFs and modal.msgFs.SetTextColor and pal and pal.text then
			modal.msgFs:SetTextColor(pal.text[1], pal.text[2], pal.text[3], pal.text[4] or 1)
		end
		if modal.subFs and modal.subFs.SetTextColor and pal and pal.textSecondary then
			modal.subFs:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], pal.textSecondary[4] or 0.78)
		end
		if modal.ApplySavedOrDefaultPosition then modal:ApplySavedOrDefaultPosition() end
		modal:Show()
		if modal.Raise then modal:Raise() end
		return modal
	end

	function papp.optimizeForMe(profKey)
		local db = getProfDB()
		local pk = profKey or db.selectedProf or "alchemy"
		if cacheOpenTrainerCosts then cacheOpenTrainerCosts(false) end
		if cacheOpenTradeSkills then cacheOpenTradeSkills() end
		local live = MP.ScanPlayerProfessions()
		local lp = live and live[pk]
		local curFrom, curTo = getProfBounds(pk)
		local targetTo = math.max(2, math.min(300, tonumber(curTo) or 300))
		local nextFrom = curFrom
		local detectedRank = nil
		if lp and lp.learned and (tonumber(lp.rank) or 0) > 0 then
			detectedRank = math.floor(tonumber(lp.rank) + 0.5)
			nextFrom = math.min(299, math.max(1, detectedRank))
			if targetTo <= nextFrom then targetTo = 300 end
			local f, t = setProfBounds(pk, nextFrom, targetTo)
			nextFrom, targetTo = f, t
			if papp.ui.fromBox then papp.ui.fromBox:SetText(tostring(f)) end
			if papp.ui.toBox then papp.ui.toBox:SetText(tostring(t)) end
		end

		db.useOwned = true
		if papp.ui.ownedChk and papp.ui.ownedChk.SetChecked then
			papp.ui.ownedChk:SetChecked(true)
		end

		-- If the active bracket is already completed at the player's live skill, switch to All so steps are visible
		if papp.activeBracket and papp.activeBracket ~= "all" then
			for _, bp in ipairs(papp.ui.bracketPills or {}) do
				local bd = bp and bp.bracket
				if bd and bd.key == papp.activeBracket and nextFrom >= bd.hi then
					papp.activeBracket = "all"
					break
				end
			end
		end

		-- Unlock this profession if locked so live skill & owned mats actually recompute
		if papp.isViewLocked(pk) then
			papp.setViewLocked(pk, false, true)
		end

		if mmApp.refresh then mmApp.refresh() end

		local pName = (MP.PROFESSIONS[pk] and MP.PROFESSIONS[pk].name) or pk
		if mmApp.ui and mmApp.ui.toast and mmApp.ui.toast.ShowToast then
			if detectedRank then
				mmApp.ui.toast:ShowToast(string.format("Optimized %s (%d -> %d) using your owned mats", pName, nextFrom, targetTo), "success")
			else
				mmApp.ui.toast:ShowToast(string.format("Optimized %s (%d -> %d) using your owned mats (skill not learned yet)", pName, nextFrom, targetTo), "info")
			end
		end
		return nextFrom, targetTo, detectedRank
	end

	local function handleProfRowClick(rowFrame, d, mouseBtn)
		if not d then return end
		if mouseBtn ~= nil and (not readable(mouseBtn) or type(mouseBtn) ~= "string") then return end
		local raw = d._orig or d
		local shiftState = shiftKeyDown()
		if shiftState == nil then return end
		if (shiftState or papp.shiftActive) and canQueueProfRow(raw) then
			local outID = tonumber(raw.outputItemID or raw.itemID)
			if (mouseBtn == nil or mouseBtn == "LeftButton") and outID and outID > 0
				and mmApp.tryQuickLookChatLink and mmApp.tryQuickLookChatLink(outID) == true then
				return
			end
			local delta = (mouseBtn == "RightButton") and -1 or 1
			adjustProfRowShiftQty(raw, delta)
			return
		end
		if mouseBtn == "RightButton" then
			if d._mode == "browse" or (not raw.s1 and raw.req) then
				if raw.itemID and raw.itemID > 0 and mmApp.searchAH then
					mmApp.searchAH(MP.ItemName(raw.itemID), 1, raw.itemID)
				end
			else
				tryCraftOrSearchStep(raw)
			end
			return
		end
		raw.prof = raw.prof or (getProfDB().selectedProf or "alchemy")
		if d._mode ~= "browse" and raw.stepNum and papp.selectStep then
			papp.selectStep(raw)
		end
		local qlRow = mmApp.buildRecipeQuickLookRow and mmApp.buildRecipeQuickLookRow(raw)
		if qlRow and mmApp.openQuickLook then
			mmApp.openQuickLook("recipe", qlRow, { owner = rowFrame })
			if qlRow.outputItemID and qlRow.outputItemID > 0 and _G.AuctionHouseFrame and _G.AuctionHouseFrame.IsShown and _G.AuctionHouseFrame:IsShown() and mmApp.searchAH then
				mmApp.searchAH(qlRow.name, 1, qlRow.outputItemID, { silentNoAH = true, coalesce = true })
			end
			return
		end
		tryCraftOrSearchStep(raw)
	end

	local function styleProfStepper(stepper, qty, pal)
		if not stepper then return end
		local isLight = (pal and pal.mode == "light")
		local bgCol = (pal and pal.cardAltBg) or (isLight and { 0.949, 0.949, 0.969, 1 } or { 0.204, 0.204, 0.220, 1 })
		local stCol = (pal and pal.borderStrong) or (isLight and { 0, 0, 0, 0.14 } or { 1, 1, 1, 0.22 })
		local textCol = (pal and pal.text) or (isLight and { 0, 0, 0, 1 } or { 1, 1, 1, 1 })
		local mutedCol = (pal and pal.textMuted) or (isLight and { 0.369, 0.384, 0.416, 1 } or { 0.596, 0.596, 0.616, 0.88 })
		local greenCol = (pal and pal.accentGreen) or (isLight and { 0, 0.478, 0.169, 1 } or { 0.188, 0.820, 0.345, 1 })
		if stepper.bg then
			if stepper.bg.SetColor then stepper.bg:SetColor(bgCol[1], bgCol[2], bgCol[3], 1)
			elseif stepper.bg.SetColorTexture then stepper.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], 1) end
		end
		if stepper.stroke and stepper.stroke.SetColor then
			stepper.stroke:SetColor(stCol[1], stCol[2], stCol[3], stCol[4] or 0.22)
		end
		if stepper.minusBtn and stepper.minusBtn.fs and stepper.minusBtn.fs.SetTextColor then
			stepper.minusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
		end
		if stepper.plusBtn and stepper.plusBtn.fs and stepper.plusBtn.fs.SetTextColor then
			stepper.plusBtn.fs:SetTextColor(textCol[1], textCol[2], textCol[3], 1)
		end
		if stepper.qtyFs then
			stepper.qtyFs:SetText(tostring(qty))
			if stepper.qtyFs.SetTextColor then
				local qc = (qty > 0) and greenCol or mutedCol
				stepper.qtyFs:SetTextColor(qc[1], qc[2], qc[3], qc[4] or 1)
			end
		end
	end

	local function ensureProfRowStepper(r)
		if r.shiftStepper then return r.shiftStepper end
		local stepper = CreateFrame("Frame", nil, r)
		stepper:SetSize(76, 20)
		stepper:SetPoint("RIGHT", r, "RIGHT", -2, 0)
		if r.GetFrameLevel and stepper.SetFrameLevel then
			stepper:SetFrameLevel((r:GetFrameLevel() or 1) + 4)
		end
		if stepper.EnableMouse then stepper:EnableMouse(true) end
		if Theme and Theme.RoundRect and Theme.ASSETS and Theme.ASSETS.pill_fill then
			stepper.bg = Theme.RoundRect(stepper, stepper, "BACKGROUND", 0, 10, 0, 0.204, 0.204, 0.220, 1, Theme.ASSETS.pill_fill)
			if Theme.ASSETS.pill_stroke then
				stepper.stroke = Theme.RoundRect(stepper, stepper, "BORDER", 1, 10, 0, 1, 1, 1, 0.22, Theme.ASSETS.pill_stroke)
			end
		else
			stepper.bg = stepper:CreateTexture(nil, "BACKGROUND")
			stepper.bg:SetAllPoints()
			stepper.bg:SetColorTexture(0.204, 0.204, 0.220, 1)
		end
		local minusBtn = CreateFrame("Button", nil, stepper)
		minusBtn:SetSize(22, 18)
		minusBtn:SetPoint("LEFT", stepper, "LEFT", 1, 0)
		minusBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		minusBtn.hl = minusBtn:CreateTexture(nil, "HIGHLIGHT")
		minusBtn.hl:SetAllPoints()
		minusBtn.hl:SetColorTexture(1, 1, 1, 0.08)
		minusBtn.fs = minusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		minusBtn.fs:SetAllPoints()
		minusBtn.fs:SetJustifyH("CENTER")
		applyFont(minusBtn.fs, 12, "semibold")
		minusBtn.fs:SetText("-")
		minusBtn:SetScript("OnClick", function(_, button)
			local row = r.data
			if not row then return end
			local cur = getProfRowQueuedQty(row)
			local delta = (button == "RightButton") and -math.max(1, cur) or -1
			adjustProfRowShiftQty(row, delta)
		end)

		local plusBtn = CreateFrame("Button", nil, stepper)
		plusBtn:SetSize(22, 18)
		plusBtn:SetPoint("RIGHT", stepper, "RIGHT", -1, 0)
		plusBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		plusBtn.hl = plusBtn:CreateTexture(nil, "HIGHLIGHT")
		plusBtn.hl:SetAllPoints()
		plusBtn.hl:SetColorTexture(1, 1, 1, 0.08)
		plusBtn.fs = plusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		plusBtn.fs:SetAllPoints()
		plusBtn.fs:SetJustifyH("CENTER")
		applyFont(plusBtn.fs, 12, "semibold")
		plusBtn.fs:SetText("+")
		plusBtn:SetScript("OnClick", function(_, button)
			local row = r.data
			if not row then return end
			local delta = (button == "RightButton") and 5 or 1
			adjustProfRowShiftQty(row, delta)
		end)

		local qtyFs = stepper:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		qtyFs:SetPoint("LEFT", minusBtn, "RIGHT", 0, 0)
		qtyFs:SetPoint("RIGHT", plusBtn, "LEFT", 0, 0)
		qtyFs:SetJustifyH("CENTER")
		qtyFs:SetWordWrap(false)
		applyFont(qtyFs, 11, "semibold")
		qtyFs:SetText("0")

		stepper.minusBtn = minusBtn
		stepper.plusBtn = plusBtn
		stepper.qtyFs = qtyFs
		stepper:Hide()
		r.shiftStepper = stepper
		return stepper
	end

	local function paintPathCartCell(r, pal)
		local d = r and r.data
		local n = r and r.cells and #r.cells or 0
		local act = (n > 0) and r.cells[n] or nil
		if not (d and act and act.fs) then return end
		local greenHex = colorHex(pal and pal.accentGreen, "30d158")
		local blueHex = colorHex(pal and (pal.textBlue or pal.accentBlue), "0a84ff")
		local secHex = colorHex(pal and pal.textSecondary, "aeaeb2")
		local actBg, actTxt
		if (d.isMilestone and not isBookMilestone(d)) or d.srcType == "gather" then
			actBg = (pal and pal.pillTrack) or { 0.47, 0.47, 0.50, 0.16 }
			actTxt = "|cff" .. secHex .. (d.srcType == "gather" and "Mine" or "Train") .. "|r"
		else
			local qty = getProfRowQueuedQty(d)
			if qty > 0 then
				local gc = (pal and pal.accentGreen) or { 0.19, 0.82, 0.35 }
				actBg = { gc[1], gc[2], gc[3], 0.20 }
				actTxt = "|cff" .. greenHex .. "Cart: " .. tostring(qty) .. "|r"
			else
				local bc = (pal and pal.accentBlue) or { 0.04, 0.52, 1.0 }
				actBg = { bc[1], bc[2], bc[3], 0.18 }
				actTxt = "|cff" .. blueHex .. "+ Cart|r"
			end
		end
		if act.pillBg and act.pillBg.SetColor then
			act.pillBg:SetColor(actBg[1], actBg[2], actBg[3], actBg[4] or 0.18)
		elseif act.bg then
			act.bg:SetColorTexture(actBg[1], actBg[2], actBg[3], actBg[4] or 0.18)
		end
		act.fs:SetText(actTxt)
	end

	local function paintProfRowShiftState(r, tbl, isPathTable)
		if not r or not r.data then
			if r and r.shiftStepper then r.shiftStepper:Hide() end
			return
		end
		local pal = getProfPalette()
		local isLight = (pal and pal.mode == "light")
		if isPathTable then
			paintPathCartCell(r, pal)
		end
		if papp.shiftActive and canQueueProfRow(r.data) then
			local qty = getProfRowQueuedQty(r.data)
			local stepper = ensureProfRowStepper(r)
			styleProfStepper(stepper, qty, pal)
			stepper:Show()
			local n = r.cells and #r.cells or 0
			if n > 0 then
				r._shiftHidden = true
				local activeCols = tbl and tbl.columns
				local colX = tbl and tbl.colX
				local lastCol = activeCols and activeCols[n]
				local lastX = colX and colX[n]
				local tblRight = (lastCol and lastX) and (lastX + (lastCol.width or 0)) or 0
				local rawRowW = (r.GetWidth and r:GetWidth()) or 0
				local rowW = (rawRowW >= math.max(200, tblRight * 0.5)) and rawRowW or tblRight
				local hidAny = false
				if rowW > 80 and activeCols and colX then
					local cutoff = rowW - 80
					for i = 1, n do
						local c = r.cells[i]
						local cx = colX[i] or 0
						local cw = (activeCols[i] and activeCols[i].width) or 0
						local overlap = (cx + cw > cutoff)
						if c and c.SetShown then c:SetShown(not overlap) end
						if overlap then hidAny = true end
					end
				end
				if not hidAny and r.cells[n] and r.cells[n].SetShown then
					r.cells[n]:SetShown(false)
				end
			end
			if r.bg then
				if qty > 0 then
					local gc = (pal and pal.accentGreen) or { 0.19, 0.82, 0.35 }
					r.bg:SetColorTexture(gc[1], gc[2], gc[3], isLight and 0.10 or 0.14)
				else
					local bc = (pal and pal.accentBlue) or { 0.04, 0.52, 1.0 }
					r.bg:SetColorTexture(bc[1], bc[2], bc[3], isLight and 0.05 or 0.07)
				end
			end
		else
			if r.shiftStepper then r.shiftStepper:Hide() end
			if r._shiftHidden and r.cells then
				r._shiftHidden = false
				for _, c in ipairs(r.cells) do
					if c and c.SetShown then c:SetShown(true) end
				end
			end
			if r.bg then
				local raw = r.data and (r.data._orig or r.data)
				if isPathTable and raw and raw.stepNum and papp.selectedStepNum == raw.stepNum then
					local bc = (pal and pal.accentBlue) or { 0.04, 0.52, 1.0 }
					r.bg:SetColorTexture(bc[1], bc[2], bc[3], isLight and 0.11 or 0.14)
				elseif raw and raw.isMilestone then
					local bc = (pal and pal.accentBlue) or { 0.04, 0.52, 1.0 }
					r.bg:SetColorTexture(bc[1], bc[2], bc[3], 0.06)
				else
					r.bg:SetColorTexture(0, 0, 0, 0)
				end
			end
		end
	end

	function papp.RepaintShoppingQty()
		if papp.ui.pathTable and papp.ui.pathTable.forEachRow then
			papp.ui.pathTable.forEachRow(function(rf) paintProfRowShiftState(rf, papp.ui.pathTable, true) end)
		end
		if papp.ui.browseTable and papp.ui.browseTable.forEachRow then
			papp.ui.browseTable.forEachRow(function(rf) paintProfRowShiftState(rf, papp.ui.browseTable, false) end)
		end
	end

	function papp.SetShiftMode(on)
		papp.shiftActive = (on == true)
		if papp.ui.pathShiftBadge then papp.ui.pathShiftBadge:SetShown(papp.shiftActive) end
		if papp.ui.browseShiftBadge then papp.ui.browseShiftBadge:SetShown(papp.shiftActive) end
		papp.RepaintShoppingQty()
		return papp.shiftActive
	end

	local function parseProfessorProvenance(usedIn, fallbackName)
		local txt = (type(usedIn) == "string") and usedIn:match("^%s*(.-)%s*$") or ""
		if txt == "" then
			return nil, fallbackName
		end
		local sepStart, sepEnd = txt:find("->", 1, true)
		if sepStart then
			local left = txt:sub(1, sepStart - 1):match("^%s*(.-)%s*$")
			local right = txt:sub(sepEnd + 1):match("^%s*(.-)%s*$")
			if left ~= "" and right ~= "" then
				return left, right
			end
		end
		return nil, txt
	end

	local function addProfessorProv(list, qty, subCraftName, targetName, sourceLabel)
		local q = math.max(1, math.floor((tonumber(qty) or 1) + 0.5))
		for _, p in ipairs(list) do
			if p.targetName == targetName and p.subCraftName == subCraftName and p.sourceLabel == sourceLabel then
				p.qty = (tonumber(p.qty) or 0) + q
				return
			end
		end
		list[#list + 1] = {
			qty = q,
			subCraftName = subCraftName,
			targetName = targetName,
			sourceKind = "leveling",
			sourceLabel = sourceLabel,
		}
	end

	function papp.sendShoppingToBuyer()
		local res = papp.lastPathResult
		if not res then return false end
		local profTitle = (res.profInfo and res.profInfo.name) and (res.profInfo.name .. " Leveling") or "Leveling"
		local activeBrk = nil
		if papp.activeBracket and papp.activeBracket ~= "all" and type(res.shoppingListByLevel) == "table" then
			for _, bp in ipairs(papp.ui.bracketPills or {}) do
				if bp.bracket and bp.bracket.key == papp.activeBracket then
					activeBrk = bp.bracket
					break
				end
			end
		end

		local provByKey = {}
		local filteredOrder = nil
		if type(res.shoppingListByLevel) == "table" then
			local byID = {}
			if activeBrk then filteredOrder = {} end
			for _, it in ipairs(res.shoppingListByLevel) do
				local s1 = it.s1 or 1
				local s2 = it.s2 or s1
				local inBrk = (not activeBrk)
					or ((s2 > s1) and (s2 > activeBrk.lo and s1 < activeBrk.hi))
					or (s1 >= activeBrk.lo and (s1 < activeBrk.hi or (activeBrk.hi == 300 and s1 == 300)))
				if inBrk and not it.isVendor and (it.buyQty or 0) > 0 then
					local k = it.itemID or it.name
					local provList = provByKey[k]
					if not provList then
						provList = {}
						provByKey[k] = provList
					end
					local subCraft, targetName = parseProfessorProvenance(it.usedIn, profTitle)
					local stepLbl = (tonumber(it.stepNum) and tonumber(it.stepNum) > 0)
						and ("Leveling #" .. tostring(it.stepNum))
						or "Leveling"
					addProfessorProv(provList, it.buyQty, subCraft, targetName, stepLbl)
					if activeBrk then
						local agg = byID[k]
						if not agg then
							agg = { name = it.name, qty = 0, itemID = it.itemID, unitPrice = it.unitPrice or it.ahUnitPrice, usedIn = it.usedIn }
							byID[k] = agg
							filteredOrder[#filteredOrder + 1] = agg
						end
						agg.qty = agg.qty + it.buyQty
					end
				end
			end
		end

		local sourceList = filteredOrder or res.shoppingList
		if not sourceList then return false end
		local rows = {}
		for _, it in ipairs(sourceList) do
			local q = it.buyQty or it.qty
			if not it.isVendor and q and q > 0 then
				local k = it.itemID or it.name
				local prov = provByKey[k]
				if not prov or #prov == 0 then
					local subCraft, targetName = parseProfessorProvenance(it.usedIn, profTitle)
					prov = {
						{
							qty = q,
							subCraftName = subCraft,
							targetName = targetName,
							sourceKind = "leveling",
							sourceLabel = "Leveling",
						},
					}
				end
				rows[#rows + 1] = {
					name = it.name,
					qty = q,
					itemID = it.itemID,
					unitPrice = it.unitPrice or it.ahUnitPrice,
					sourceKind = "leveling",
					sourceLabel = "Leveling",
					provenance = prov,
				}
			end
		end
		if #rows == 0 then
			profSay("All needed items are NPC Vendor items or already owned!")
			return false
		end
		if mmApp.openCartBuyer then
			return mmApp.openCartBuyer(rows, "MP " .. (res.profInfo and res.profInfo.name or "Leveling"))
		end
		if mmApp.multiSearchBuyer and mmApp.multiSearchBuyer("MP " .. (res.profInfo and res.profInfo.name or "Leveling"), rows) then
			return true
		end
		if rows[1] then
			return mmApp.searchAH(rows[1].name, rows[1].qty, rows[1].itemID)
		end
		return false
	end

	local cacheOpenTradeSkills, cacheOpenTrainerCosts

	-- Build Sidebar Contextual Controls for Professor inside MerchantMaster's Sidebar
	local sidebar = mmApp.ui.sidebar
	local SB_W = 194

	local scanRow = CreateFrame("Frame", nil, sidebar)
	scanRow:SetSize(SB_W, 21)
	scanRow._isCheck = false
	scanRow:Hide()

	local scanBtn = Theme.CreatePlateButton(scanRow, "Scan Trainer", 118, 20)
	scanBtn:SetPoint("LEFT", 0, 0)
	scanBtn:SetScript("OnClick", function()
		if cacheOpenTrainerCosts then cacheOpenTrainerCosts(true) end
		if cacheOpenTradeSkills then cacheOpenTradeSkills() end
		local curProf = getProfDB().selectedProf
		local live = MP.ScanPlayerProfessions()
		local lp = live[curProf]
		if lp and lp.learned then
			local startVal = math.min(299, math.max(1, lp.rank))
			local f, t = setProfBounds(curProf, startVal, 300)
			if papp.ui.fromBox then papp.ui.fromBox:SetText(tostring(f)) end
			if papp.ui.toBox then papp.ui.toBox:SetText(tostring(t)) end
			profSay(string.format("Scanned live %s skill: %d / %d.", MP.PROFESSIONS[curProf].name, lp.rank, lp.maxRank))
		else
			for _, pk in ipairs(MP.PROF_ORDER) do
				if live[pk] and live[pk].learned then
					getProfDB().selectedProf = pk
					if MerchantMasterDB then MerchantMasterDB.profFilter = pk end
					local startVal = math.min(299, math.max(1, live[pk].rank))
					local f, t = setProfBounds(pk, startVal, 300)
					if papp.ui.fromBox then papp.ui.fromBox:SetText(tostring(f)) end
					if papp.ui.toBox then papp.ui.toBox:SetText(tostring(t)) end
					profSay(string.format("Detected learned profession %s: %d / %d.", MP.PROFESSIONS[pk].name, live[pk].rank, live[pk].maxRank))
					mmApp.refresh()
					return
				end
			end
			profSay("No learned crafting skill detected on character yet; simulating from default start.")
		end
		mmApp.refresh()
	end)
	scanBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Scan Trainer, Character Skill & Legacy Perks", 1, 0.82, 0)
		GameTooltip:AddLine("Reads open Trainer fees/requirements, your current profession skill rank, character level, known recipes, and Working Overtime Legacy rank.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	scanBtn:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.scanBtn = scanBtn

	local fullBtn = Theme.CreatePlateButton(scanRow, "1-300", 72, 20)
	fullBtn:SetPoint("LEFT", scanBtn, "RIGHT", 4, 0)
	fullBtn:SetScript("OnClick", function()
		local pk = getProfDB().selectedProf
		local defStart = (MP.PROFESSIONS[pk] and MP.PROFESSIONS[pk].defaultStart) or 1
		local f, t = setProfBounds(pk, defStart, 300)
		if papp.ui.fromBox then papp.ui.fromBox:SetText(tostring(f)) end
		if papp.ui.toBox then papp.ui.toBox:SetText(tostring(t)) end
		mmApp.refresh()
	end)
	papp.ui.fullBtn = fullBtn
	papp.ui.scanRow = scanRow

	local boundsRow = CreateFrame("Frame", nil, sidebar)
	boundsRow:SetSize(SB_W, 21)
	boundsRow._isCheck = false
	boundsRow:Hide()

	local fromLbl = boundsRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fromLbl:SetPoint("LEFT", 2, 0)
	fromLbl:SetText("Skill:")
	applyFont(fromLbl, 11, "regular")

	local fromBox = CreateFrame("EditBox", nil, boundsRow, "InputBoxTemplate")
	fromBox:SetSize(56, 20)
	fromBox:SetPoint("LEFT", fromLbl, "RIGHT", 6, 0)
	fromBox:SetAutoFocus(false)
	fromBox:SetNumeric(true)
	fromBox:SetMaxLetters(3)
	Theme.StyleEditBox(fromBox)
	papp.ui.fromBox = fromBox

	local arrowLbl = boundsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrowLbl:SetPoint("LEFT", fromBox, "RIGHT", 6, 0)
	arrowLbl:SetText("->")
	applyFont(arrowLbl, 11, "regular")

	local toBox = CreateFrame("EditBox", nil, boundsRow, "InputBoxTemplate")
	toBox:SetSize(56, 20)
	toBox:SetPoint("LEFT", arrowLbl, "RIGHT", 6, 0)
	toBox:SetAutoFocus(false)
	toBox:SetNumeric(true)
	toBox:SetMaxLetters(3)
	Theme.StyleEditBox(toBox)
	papp.ui.toBox = toBox

	local function commitBounds()
		local pk = getProfDB().selectedProf
		local f, t = setProfBounds(pk, tonumber(fromBox:GetText()) or 1, tonumber(toBox:GetText()) or 300)
		fromBox:SetText(tostring(f))
		toBox:SetText(tostring(t))
		fromBox:ClearFocus()
		toBox:ClearFocus()
		mmApp.refresh()
	end
	fromBox:SetScript("OnEnterPressed", commitBounds)
	toBox:SetScript("OnEnterPressed", commitBounds)
	fromBox:SetScript("OnEditFocusLost", commitBounds)
	toBox:SetScript("OnEditFocusLost", commitBounds)
	papp.ui.boundsRow = boundsRow

	local charLvBtn = mmApp.ui.makeSidebarDrop(CHAR_LEVEL_OPTIONS,
		function() return getProfDB().charLevelMode or "auto" end,
		function(k) getProfDB().charLevelMode = k end,
		function()
			local d = getProfDB()
			d.charLevelMode = (d.charLevelMode == "auto") and 60 or "auto"
		end,
		"Character Level Progression Gate",
		"Enforces character level gates on Rank Training, recipe scrolls, quests, and specializations.\nLeft-Click: choose level  ·  Right-Click: toggle Auto <-> Lv 60 (Plan All)")
	papp.ui.charLvBtn = charLvBtn

	local overtimeBtn = mmApp.ui.makeSidebarDrop(OVERTIME_OPTIONS,
		function() return getProfDB().overtimeMode or "auto" end,
		function(k) getProfDB().overtimeMode = k end,
		function() getProfDB().overtimeMode = "auto" end,
		"Legacy Perk: Working Overtime (Tree 1187)",
		"Boosts Yellow & Green skill-up probability by +4% per rank (up to +20% at 5/5).\nLeft-Click: simulate 0/5 .. 5/5  ·  Right-Click: Auto")
	papp.ui.overtimeBtn = overtimeBtn

	local goalBtn = mmApp.ui.makeSidebarDrop(GOAL_OPTIONS,
		function() return getProfDB().goalMode or "smart" end,
		function(k) getProfDB().goalMode = k end,
		function() getProfDB().goalMode = "smart" end,
		"Optimization Goal & Output Resale Mode",
		"· Smart Net/Profit: Sells liquid outputs on AH (conservative price, single-realm cap) and excess to Vendor\n· Cheapest (Vendor Net): Minimizes net leveling spend using NPC Vendor floor only\n· Max AH (Uncapped / High Risk): Values 100% of tradeable outputs at spot net AH price")
	papp.ui.goalBtn = goalBtn

	local recFilterBtn = mmApp.ui.makeSidebarDrop(RECIPE_FILTER_OPTIONS,
		function()
			local d = getProfDB()
			return (MerchantMasterDB and MerchantMasterDB.knownRecipesOnly) and "known_only" or (d.recipeFilter or "trainer_vendor")
		end,
		function(k)
			local d = getProfDB()
			d.recipeFilter = k
			if MerchantMasterDB then
				MerchantMasterDB.knownRecipesOnly = (k == "known_only")
				MerchantMasterDB.unlockFilter = (k == "known_only") and "known" or (MerchantMasterDB.unlockFilter == "known" and "all" or MerchantMasterDB.unlockFilter)
			end
		end,
		function()
			getProfDB().recipeFilter = "trainer_vendor"
			if MerchantMasterDB then
				MerchantMasterDB.knownRecipesOnly = false
				if MerchantMasterDB.unlockFilter == "known" then MerchantMasterDB.unlockFilter = "all" end
			end
		end,
		"Allowed Recipe Unlock Sources",
		"Choose Known Recipes Only, Trainer + Vendor, Trainer Only, + AH Scrolls, or All (+ Favor Camp).")
	papp.ui.recFilterBtn = recFilterBtn

	local horizonBtn = mmApp.ui.makeSidebarDrop(SELL_DAYS_OPTIONS,
		function() return getProfDB().sellDays or 3 end,
		function(k) getProfDB().sellDays = k end,
		function() getProfDB().sellDays = 3 end,
		"Auction House Resale Horizon",
		"Caps expected AH resale volume at estimated Daily Sold x Horizon Days before routing excess outputs to NPC Vendor floor.")
	papp.ui.horizonBtn = horizonBtn

	local useOwnedChk = mmApp.ui.makeSidebarCheck("Use Owned Stock", function(self)
		getProfDB().useOwned = self:GetChecked() and true or false
		mmApp.refresh()
	end, "Deduct Owned Inventory", "Deducts reagents, crafted intermediates, and scrolls already in your Bags, Bank, Mail, and Alts from Leveling Shopping List quantities.")
	papp.ui.ownedChk = useOwnedChk

	local useDEChk = mmApp.ui.makeSidebarCheck("Include DE Recovery (est.)", function(self)
		getProfDB().useDisenchantRecovery = self:GetChecked() and true or false
		if MP.InvalidateSolveCache then MP.InvalidateSolveCache() end
		mmApp.refresh()
	end, "Disenchant Recovery (est.)", "Includes estimated Vanilla 1-60 disenchanting material value (after AH cut) as a third recovery route alongside Vendor and AH when leveling.")
	papp.ui.deRecoveryChk = useDEChk

	-- Build Professor Views inside MerchantMaster's professorView (1,074px center workspace)
	local profBody = mmApp.ui.professorView
	papp.ui.body = profBody

	local lastProfShiftDown = false
	local function syncProfShiftFromModifier()
		local state = shiftKeyDown()
		if state == nil then return end
		local down = state and true or false
		if down ~= lastProfShiftDown then
			lastProfShiftDown = down
			papp.SetShiftMode(down)
		end
	end
	pcall(profBody.RegisterEvent, profBody, "MODIFIER_STATE_CHANGED")
	profBody:SetScript("OnEvent", function(self, event)
		if event == "MODIFIER_STATE_CHANGED" and self:IsShown() then
			syncProfShiftFromModifier()
		end
	end)
	local function onProfShiftUpdate(self)
		if not self:IsShown() then return end
		syncProfShiftFromModifier()
	end
	profBody:HookScript("OnShow", function(self)
		self:SetScript("OnUpdate", onProfShiftUpdate)
		local state = shiftKeyDown()
		if state == nil then return end
		local down = state and true or false
		lastProfShiftDown = down
		if down ~= (papp.shiftActive == true) then papp.SetShiftMode(down) end
	end)
	profBody:HookScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
		lastProfShiftDown = false
		if papp.shiftActive then papp.SetShiftMode(false) end
		if papp.ui.kpiStrip then papp.ui.kpiStrip:Hide() end
		if mmApp.superListProvider and mmApp.superListProvider.GetQuickLookFrame and mmApp.superListProvider.CloseQuickLook then
			local hud = mmApp.superListProvider.GetQuickLookFrame()
			if hud and hud:IsShown() and type(hud.openedTab) == "string" and hud.openedTab:sub(1, 5) == "prof_" then
				mmApp.superListProvider.CloseQuickLook()
			end
		end
	end)

	local pathView = CreateFrame("Frame", nil, profBody)
	pathView:SetAllPoints()
	papp.ui.pathView = pathView

	-- 1. Profession Pill Selector Strip
	local profPillBar = CreateFrame("Frame", nil, pathView)
	profPillBar:SetPoint("TOPLEFT", pathView, "TOPLEFT", 0, 0)
	profPillBar:SetPoint("TOPRIGHT", pathView, "TOPRIGHT", 0, 0)
	profPillBar:SetHeight(28)
	papp.ui.profPillBar = profPillBar
	papp.ui.profPills = {}

	local function makePillButton(parent, label, width)
		return Theme.CreatePlateButton(parent, label, width, 24, { pill = true, fontSize = 11 })
	end

	local prevProfPill = nil
	for _, pk in ipairs(MP.PROF_ORDER or {}) do
		local pInfo = MP.PROFESSIONS[pk]
		if pInfo then
			local lbl = pInfo.name or pk
			local pw = math.max(58, #lbl * 6 + 20)
			local pb = makePillButton(profPillBar, lbl, pw)
			if not prevProfPill then
				pb:SetPoint("LEFT", profPillBar, "LEFT", 0, 0)
			else
				pb:SetPoint("LEFT", prevProfPill, "RIGHT", 5, 0)
			end
			pb.profKey = pk
			pb:SetScript("OnClick", function()
				getProfDB().selectedProf = pk
				if MerchantMasterDB then MerchantMasterDB.profFilter = pk end
				local f, t = getProfBounds(pk)
				if papp.ui.fromBox then papp.ui.fromBox:SetText(tostring(f)) end
				if papp.ui.toBox then papp.ui.toBox:SetText(tostring(t)) end
				mmApp.refresh()
			end)
			papp.ui.profPills[#papp.ui.profPills + 1] = pb
			prevProfPill = pb
		end
	end

	-- 2. Three Compact Inline KPI Pills in the Top Sub-Strip (next to Leveling Path / List / Browse Recipes)
	local kpiParent = (mmApp.ui and mmApp.ui.subStrip) or pathView
	local kpiStrip = CreateFrame("Frame", nil, kpiParent)
	if mmApp.ui and mmApp.ui.subStrip and mmApp.ui.profSubBar then
		kpiStrip:SetPoint("LEFT", mmApp.ui.profSubBar, "RIGHT", 12, 0)
		kpiStrip:SetPoint("RIGHT", mmApp.ui.subStrip, "RIGHT", -2, 0)
		kpiStrip:SetHeight(24)
	else
		kpiStrip:SetPoint("TOPLEFT", pathView, "TOPLEFT", 0, -34)
		kpiStrip:SetPoint("TOPRIGHT", pathView, "TOPRIGHT", 0, -34)
		kpiStrip:SetHeight(24)
	end
	kpiStrip:Hide()
	papp.ui.kpiStrip = kpiStrip
	papp.ui.kpiCards = {}
	local KPI_DEFS = {
		{ title = "Skill Filter",       icon = "bars",        meter = true,  minW = 186, maxW = 216, weight = 0.28 },
		{ title = "Est. Leveling Cost", icon = "coins",       meter = false, minW = 266, maxW = 340, weight = 0.43 },
		{ title = "Steps Remaining",    icon = "checkcircle", meter = false, minW = 198, maxW = 240, weight = 0.29 },
	}
	local kpiGap = 8
	for i, kd in ipairs(KPI_DEFS) do
		local c = CreateFrame("Frame", nil, kpiStrip)
		c:SetSize(kd.maxW, 24)
		c:SetPoint("LEFT", kpiStrip, "LEFT", 0, 0)
		c._kpiDef = kd
		if c.EnableMouse then c:EnableMouse(true) end
		if Theme and Theme.NineApple then
			c._mmGlass = Theme.NineApple(c, "glass_r10", "cardBg", false, { noSpecular = true })
		else
			Theme.Card(c, c, 8, false, { 0.17, 0.17, 0.18, 1 })
		end
		if Theme and Theme.AppleIcon then
			c.icon = Theme.AppleIcon(c, kd.icon, 11)
			c.icon:SetPoint("LEFT", c, "LEFT", 9, 0)
		end
		c.lbl = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		if c.icon then
			c.lbl:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
		else
			c.lbl:SetPoint("LEFT", c, "LEFT", 9, 0)
		end
		c.lbl:SetJustifyH("LEFT")
		c.lbl:SetWordWrap(false)
		applyFont(c.lbl, 10, "regular")
		c.lbl:SetText(kd.title)

		c.val = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		c.val:SetPoint("LEFT", c.lbl, "RIGHT", 6, 0)
		c.val:SetJustifyH("LEFT")
		c.val:SetWordWrap(false)
		applyFont(c.val, 12, "semibold")

		c.unit = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		c.unit:SetPoint("LEFT", c.val, "RIGHT", 4, 0)
		c.unit:SetPoint("RIGHT", c, "RIGHT", -9, 0)
		c.unit:SetJustifyH("LEFT")
		c.unit:SetWordWrap(false)
		applyFont(c.unit, 10, "regular")
		c.unit:SetText("")

		if kd.meter then
			if Theme and Theme.CreateProgressBar then
				local pb = Theme.CreateProgressBar(c, 2)
				pb.frame:SetPoint("BOTTOMLEFT", 9, 1)
				pb.frame:SetPoint("BOTTOMRIGHT", -9, 1)
				c.progressBar = pb
				c.meterTrack = pb.frame
			else
				local track = CreateFrame("Frame", nil, c)
				track:SetPoint("BOTTOMLEFT", 9, 1)
				track:SetPoint("BOTTOMRIGHT", -9, 1)
				track:SetHeight(2)
				local trTex = track:CreateTexture(nil, "BACKGROUND")
				trTex:SetAllPoints()
				trTex:SetColorTexture(1, 1, 1, 0.10)
				local fillTex = track:CreateTexture(nil, "ARTWORK")
				fillTex:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
				fillTex:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
				fillTex:SetWidth(4)
				fillTex:SetColorTexture(1, 1, 1, 0.86)
				c.meterTrackTex = trTex
				c.meterFillTex = fillTex
				c.meterTrack = track
			end
		end

		c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		c.sub:Hide()

		c:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			local title = (self.lbl and self.lbl.GetText and self.lbl:GetText()) or kd.title
			local vTxt = (self.val and self.val.GetText and self.val:GetText()) or ""
			local uTxt = (self.unit and self.unit.GetText and self.unit:GetText()) or ""
			local sTxt = (self.sub and self.sub.GetText and self.sub:GetText()) or ""
			GameTooltip:AddLine(title, 1, 0.82, 0)
			if vTxt ~= "" then
				GameTooltip:AddLine(uTxt ~= "" and (vTxt .. " " .. uTxt) or vTxt, 1, 1, 1)
			end
			if sTxt ~= "" then
				GameTooltip:AddLine(sTxt, 0.82, 0.82, 0.86, true)
			end
			local rw = self._runway
			if rw and (rw.totalSteps or 0) > 0 then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Gold Runway", 1, 0.82, 0)
				GameTooltip:AddDoubleLine("Wallet Gold:", formatMoney(rw.startCopper, true), 0.82, 0.82, 0.86, 1, 1, 1)
				if rw.isFunded then
					GameTooltip:AddDoubleLine("Status:", string.format("Covered all %d steps (min bal %s)", rw.totalSteps, formatMoney(rw.minBalance, true)), 0.82, 0.82, 0.86, 0.25, 0.88, 0.42)
				else
					local stName = rw.shortfallStep and (rw.shortfallStep.rawRecipeName or rw.shortfallStep.name) or "Next Step"
					GameTooltip:AddDoubleLine("Funded Through:", string.format("%d / %d steps (short %s at #%d %s)", rw.coveredSteps or 0, rw.totalSteps, formatMoney(rw.shortfallCopper, true), rw.shortfallStepNum or 1, stName), 0.82, 0.82, 0.86, 1, 0.55, 0.25)
				end
			end
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", GameTooltip_Hide)

		papp.ui.kpiCards[i] = c
	end

	function papp.layoutKpis()
		local cards = papp.ui.kpiCards or {}
		if #cards == 0 then return end
		local subW = (mmApp.ui and mmApp.ui.subStrip and mmApp.ui.subStrip.GetWidth and mmApp.ui.subStrip:GetWidth()) or 0
		if subW <= 0 then
			subW = (profBody.GetWidth and profBody:GetWidth()) or 1080
		end
		local subBarW = (mmApp.ui and mmApp.ui.profSubBar and mmApp.ui.profSubBar.GetWidth and mmApp.ui.profSubBar:GetWidth()) or 374
		local availW = math.max(540, subW - subBarW - 14)
		local reserveStatus = (availW >= 1000) and 230 or 0
		local budget = math.max(540, availW - reserveStatus - (#cards - 1) * kpiGap)
		local x = 0
		local fromSkill = getProfBounds(getProfDB().selectedProf or "alchemy")
		local pal = getProfPalette()
		for _, card in ipairs(cards) do
			local def = card._kpiDef or {}
			local w = math.floor(budget * (def.weight or (1 / #cards)))
			if reserveStatus > 0 and def.maxW then
				w = math.min(def.maxW, math.max(def.minW or 160, w))
			else
				w = math.max(150, w)
			end
			card:SetWidth(w)
			card:ClearAllPoints()
			card:SetPoint("LEFT", kpiStrip, "LEFT", x, 0)
			x = x + w + kpiGap
			if papp._updateSkillMeter and def.meter then
				papp._updateSkillMeter(card, fromSkill, pal)
			end
		end
		papp._kpiHasRoomForStatus = (reserveStatus > 0)
	end

	-- 3. Four Clean Bracket Pills (1-75 Apprentice, 75-150 Journeyman, 150-225 Expert, 225-300 Artisan)
	local BRACKET_DEFS = {
		{ key = "all",        label = "All (1-300)",       lo = 1,   hi = 300 },
		{ key = "apprentice", label = "1-75 Apprentice",   lo = 1,   hi = 75  },
		{ key = "journeyman", label = "75-150 Journeyman", lo = 75,  hi = 150 },
		{ key = "expert",     label = "150-225 Expert",    lo = 150, hi = 225 },
		{ key = "artisan",    label = "225-300 Artisan",   lo = 225, hi = 300 },
	}
	local bracketBar = CreateFrame("Frame", nil, pathView)
	bracketBar:SetPoint("TOPLEFT", pathView, "TOPLEFT", 0, -34)
	bracketBar:SetPoint("TOPRIGHT", pathView, "TOPRIGHT", 0, -34)
	bracketBar:SetHeight(28)
	papp.ui.bracketBar = bracketBar
	papp.ui.bracketPills = {}
	papp.activeBracket = "all"

	local prevBrk = nil
	for _, bd in ipairs(BRACKET_DEFS) do
		local bw = math.max(72, #bd.label * 6 + 24)
		local bb = makePillButton(bracketBar, bd.label, bw)
		if not prevBrk then
			bb:SetPoint("LEFT", bracketBar, "LEFT", 0, 0)
		else
			bb:SetPoint("LEFT", prevBrk, "RIGHT", 8, 0)
		end
		bb.bracket = bd
		bb:SetScript("OnClick", function()
			if papp.activeBracket == bd.key and bd.key ~= "all" then
				papp.activeBracket = "all"
			else
				papp.activeBracket = bd.key
			end
			mmApp.refresh()
		end)
		papp.ui.bracketPills[#papp.ui.bracketPills + 1] = bb
		prevBrk = bb
	end

	local pathResetBtn = Theme.CreatePlateButton(bracketBar, "Reset Filters", 106, 24, { variant = "secondary", pill = true, fontSize = 11 })
	pathResetBtn:SetPoint("RIGHT", bracketBar, "RIGHT", 0, 0)
	pathResetBtn:SetScript("OnClick", function() papp.resetFilters() end)
	papp.ui.pathResetBtn = pathResetBtn
	local pathFiltersBtn = mmApp.createFiltersButton(bracketBar, "pathFiltersBtn", pathResetBtn)
	papp.ui.pathFiltersBtn = pathFiltersBtn

	local GOAL_SEG_ITEMS = {
		{ key = "cheapest", label = "Cheapest",   width = 76, hint = "Cheapest (Vendor Net): minimizes net leveling spend (outputs valued at NPC vendor floor)." },
		{ key = "smart",    label = "Smart",      width = 64, hint = "Smart Net/Profit: conservative AH price and competition-adjusted single-realm demand cap; excess to Vendor." },
		{ key = "ah_max",   label = "Max Profit", width = 84, hint = "Max AH (Uncapped / High Risk): values 100% of tradeable outputs at spot net Auction House price." },
	}
	local function setProfGoalMode(key)
		local db = getProfDB()
		db.goalMode = key
		if papp.ui.goalBtn then papp.ui.goalBtn:SetText(findOptLabel(GOAL_OPTIONS, key)) end
		if papp.ui.goalSeg then papp.ui.goalSeg:SetActive(key, true) end
		if papp.ui.browseGoalSeg then papp.ui.browseGoalSeg:SetActive(key, true) end
		mmApp.refresh()
	end
	papp.setGoalMode = setProfGoalMode

	local function createProfGoalSegment(parent, rightAnchor)
		if not (Theme and Theme.CreateSegmentedControl) then return nil end
		local seg = Theme.CreateSegmentedControl(parent, GOAL_SEG_ITEMS, {
			height = 26,
			fontSize = 11,
			border = true,
			activeKey = getProfDB().goalMode or "smart",
			onChange = setProfGoalMode,
		})
		seg.frame:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)
		for _, item in ipairs(GOAL_SEG_ITEMS) do
			local btn = seg.buttons and seg.buttons[item.key]
			if btn and item.hint then
				btn:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:AddLine("Optimization Mode — " .. item.label, 1, 0.82, 0)
					GameTooltip:AddLine(item.hint, 1, 1, 1, true)
					GameTooltip:Show()
				end)
				btn:SetScript("OnLeave", GameTooltip_Hide)
			end
		end
		return seg
	end
	papp.ui.goalSeg = createProfGoalSegment(bracketBar, pathFiltersBtn)

	-- 4. Step List Bento Card (Full-Width Path Table)
	local pathCard = CreateFrame("Frame", nil, pathView)
	pathCard:SetPoint("TOPLEFT", pathView, "TOPLEFT", 0, -68)
	pathCard:SetPoint("BOTTOMRIGHT", pathView, "BOTTOMRIGHT", 0, 0)
	if pathCard.SetClipsChildren then pathCard:SetClipsChildren(true) end
	if Theme and Theme.NineApple then
		pathCard._mmGlass = Theme.NineApple(pathCard, "glass_r10", "cardBg", false, { noSpecular = true })
	else
		Theme.Card(pathCard, pathCard, 8, false, { 0.17, 0.17, 0.18, 1 })
	end
	papp.ui.pathCard = pathCard
	papp.selectedStepNum = nil
	papp.selectedStepData = nil

	function papp.layoutDetailPane()
		if not (pathView and pathCard) then return end
		local pw = (pathView.GetWidth and pathView:GetWidth()) or (profBody.GetWidth and profBody:GetWidth()) or 0
		if pw <= 0 then pw = 1400 end
		pathCard:ClearAllPoints()
		pathCard:SetPoint("TOPLEFT", pathView, "TOPLEFT", 0, -68)
		pathCard:SetPoint("BOTTOMRIGHT", pathView, "BOTTOMRIGHT", 0, 0)
		if papp.ui.pathBadge and papp.ui.pathBadge.frame then
			papp.ui.pathBadge.frame:SetShown(true)
		end
		if papp.ui.pathTable and papp.ui.pathTable.columns then
			local pt = papp.ui.pathTable
			if pt.baseWidths then
				for i, col in ipairs(pt.columns) do
					if pt.baseWidths[i] then col.width = pt.baseWidths[i] end
					if pt.hdrBtns and pt.hdrBtns[i] then pt.hdrBtns[i]:Show() end
				end
			end
			pt._layoutDirty = true
			if ns.Window and ns.Window.LayoutTable then
				ns.Window.LayoutTable(pt, pw, 0)
			end
		end
	end

	function papp.selectStep(st)
		if not st then return end
		papp.selectedStepNum = st.stepNum
		papp.selectedStepData = st
		if papp.ui.pathTable and papp.ui.pathTable.forEachRow then
			papp.ui.pathTable.forEachRow(function(rf)
				paintProfRowShiftState(rf, papp.ui.pathTable, true)
			end)
		end
	end

	local pathHead = CreateFrame("Frame", nil, pathCard)
	pathHead:SetPoint("TOPLEFT", pathCard, "TOPLEFT", 0, 0)
	pathHead:SetPoint("TOPRIGHT", pathCard, "TOPRIGHT", 0, 0)
	pathHead:SetHeight(48)
	local pathHeadSep = pathHead:CreateTexture(nil, "BORDER")
	pathHeadSep:SetPoint("BOTTOMLEFT", 0, 0)
	pathHeadSep:SetPoint("BOTTOMRIGHT", 0, 0)
	pathHeadSep:SetHeight(1)
	papp.ui.pathHeadSep = pathHeadSep

	local pathHeadTitle = pathHead:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pathHeadTitle:SetPoint("LEFT", 16, 0)
	applyFont(pathHeadTitle, 15, "semibold")
	pathHeadTitle:SetText("Leveling Route")
	papp.ui.pathHeadTitle = pathHeadTitle

	if Theme and Theme.CreateBadgePill then
		papp.ui.pathBadge = Theme.CreateBadgePill(pathHead, "0 steps", "neutral")
		papp.ui.pathBadge.frame:SetPoint("LEFT", pathHeadTitle, "RIGHT", 10, 0)
		local lockPill = Theme.CreateBadgePill(pathHead, "Locked", "warning", { height = 22, fontSize = 11, padX = 12 })
		if lockPill and lockPill.frame then
			lockPill.frame:SetPoint("LEFT", papp.ui.pathBadge.frame, "RIGHT", 8, 0)
			lockPill.frame:Hide()
			papp.ui.pathLockBadge = lockPill.frame
		end
		local shiftPill = Theme.CreateBadgePill(pathHead, "Quick-Add Mode", "blue", { height = 22, fontSize = 11, padX = 14 })
		if shiftPill and shiftPill.frame then
			shiftPill.frame:SetPoint("LEFT", papp.ui.pathBadge.frame, "RIGHT", 8, 0)
			shiftPill.frame:Hide()
			papp.ui.pathShiftBadge = shiftPill.frame
		end
	end

	local addAllCartBtn = Theme.CreatePlateButton(pathHead, "+ Add All to Cart", 148, 30, { primary = true })
	addAllCartBtn:SetPoint("RIGHT", pathHead, "RIGHT", -12, 0)
	applyFont(addAllCartBtn.fs or (addAllCartBtn.GetFontString and addAllCartBtn:GetFontString()), 12, "semibold")
	addAllCartBtn:SetScript("OnClick", function()
		local changed = papp.addOverviewToCart()
		local pk = getProfDB().selectedProf or "alchemy"
		if (changed or 0) > 0 and not papp.isViewLocked(pk) then
			papp.promptLockGuide(pk)
		end
	end)
	addAllCartBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Add Leveling Overview to Shopping Cart", 1, 0.82, 0)
		GameTooltip:AddLine("Adds every craftable step and required recipe scroll/book from the currently filtered overview into your Unified Shopping Cart.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	addAllCartBtn:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.pathAddCartBtn = addAllCartBtn

	local queueBtn = Theme.CreatePlateButton(pathHead, "Buy on AH", 134, 30, { variant = "secondary" })
	queueBtn:SetPoint("RIGHT", addAllCartBtn, "LEFT", -6, 0)
	applyFont(queueBtn.fs or (queueBtn.GetFontString and queueBtn:GetFontString()), 12, "semibold")
	queueBtn:SetScript("OnClick", function()
		papp.sendShoppingToBuyer()
	end)
	papp.ui.pathQueueBtn = queueBtn

	local lockViewBtn = Theme.CreatePlateButton(pathHead, "Lock View", 84, 30, { variant = "secondary" })
	lockViewBtn:SetPoint("RIGHT", queueBtn, "LEFT", -6, 0)
	applyFont(lockViewBtn.fs or (lockViewBtn.GetFontString and lockViewBtn:GetFontString()), 12, "semibold")
	lockViewBtn:SetScript("OnClick", function()
		papp.toggleViewLock(getProfDB().selectedProf or "alchemy")
	end)
	lockViewBtn:SetScript("OnEnter", function(self)
		local pk = getProfDB().selectedProf or "alchemy"
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if papp.isViewLocked(pk) then
			GameTooltip:AddLine("Guide Locked", 1, 0.82, 0)
			GameTooltip:AddLine("Crafts and steps are frozen so AH refreshes will not shift your leveling plan. Click to unlock and resume live updates.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Lock Leveling View", 1, 0.82, 0)
			GameTooltip:AddLine("Freezes the current leveling guide for this profession so AH scans and refreshes do not change your planned crafts.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	lockViewBtn:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.pathLockBtn = lockViewBtn

	local optimizeMeBtn = Theme.CreatePlateButton(pathHead, "Optimize for Me", 114, 30, { variant = "secondary" })
	optimizeMeBtn:SetPoint("RIGHT", lockViewBtn, "LEFT", -6, 0)
	applyFont(optimizeMeBtn.fs or (optimizeMeBtn.GetFontString and optimizeMeBtn:GetFontString()), 12, "semibold")
	optimizeMeBtn:SetScript("OnClick", function()
		papp.optimizeForMe(getProfDB().selectedProf or "alchemy")
	end)
	optimizeMeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Optimize for Me", 1, 0.82, 0)
		GameTooltip:AddLine("Sets the Skill Filter start to your character's live profession skill, enables Use Owned Stock, and recalculates the cheapest route using items you already own.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	optimizeMeBtn:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.pathOptimizeBtn = optimizeMeBtn

	local function formatKeptDestTag(st, compact)
		local list = st and st.keptForSteps
		if not list or #list == 0 then return nil end
		local nums, seen = {}, {}
		for _, ks in ipairs(list) do
			local sn = tonumber(ks.stepNum)
			if sn and sn > 0 and not seen[sn] then
				seen[sn] = true
				nums[#nums + 1] = sn
			end
		end
		if #nums == 0 then return nil end
		table.sort(nums)
		if #nums == 1 then
			return (compact and "->" or "-> ") .. "#" .. tostring(nums[1])
		elseif #nums == 2 then
			return (compact and "->" or "-> ") .. "#" .. tostring(nums[1]) .. ",#" .. tostring(nums[2])
		else
			return (compact and "->" or "-> ") .. "#" .. tostring(nums[1]) .. "+"
		end
	end

	local MM = _G.MerchantMasterAPI
	local ROW_H = PROF_ROW_H
	local PATH_COLS = {
		{ key = "stepNum",           sortCol = "stepNum",           label = "#",                 width = 24,  minWidth = 22,  align = "CENTER", hint = "Chronological step number" },
		{ key = "skillRange",        sortCol = "sortSkill",         label = "Skill",             width = 64,  minWidth = 52,  align = "CENTER", hint = "Skill bracket covered by this recipe or training milestone" },
		{ key = "name",              sortCol = "name",              label = "Recipe / Milestone",width = 166, minWidth = 118, align = "LEFT",   hint = "Left-Click: Quick View · Shift-Click: +1/-1 to Shopping Cart · Right-Click: Craft or Search AH" },
		{ key = "sourceLabel",       sortCol = "sourceLabel",       label = "Unlock Via",        width = 62,  minWidth = 50,  align = "CENTER", hint = "How you learn this recipe (Starter, Trainer, Vendor, Favor Camp, AH Scroll)" },
		{ key = "crafts",            sortCol = "crafts",            label = "Crafts",            width = 36,  minWidth = 30,  align = "RIGHT",  hint = "Expected crafts needed across this skill bracket (boosted by Working Overtime)", defaultAsc = false },
		{ key = "chanceRange",       sortCol = "crafts",            label = "Skill %",           width = 56,  minWidth = 46,  align = "CENTER", hint = "Skill-up probability from start -> end of this bracket" },
		{ key = "unlockCost",        sortCol = "unlockCost",        label = "Unlock",            width = 54,  minWidth = 54,  align = "RIGHT",  compactMoney = true, hint = "One-time trainer fee, recipe scroll cost, or Rank training fee", defaultAsc = false },
		{ key = "grossMats",         sortCol = "grossMats",         label = "Mats Spend",        width = 64,  minWidth = 56,  align = "RIGHT",  compactMoney = true, hint = "Direct reagent cash spent on this step (pre-crafted investments roll into their final product's Net Cost / Profit).", defaultAsc = false },
		{ key = "ahResaleTotal",     sortCol = "ahResaleTotal",     label = "AH",                width = 64,  minWidth = 56,  align = "RIGHT",  compactMoney = true, hint = "Expected AH net resale for this step's outputs ('-' when unlisted / soulbound)", defaultAsc = false },
		{ key = "vendorResaleTotal", sortCol = "vendorResaleTotal", label = "Vendor",            width = 60,  minWidth = 54,  align = "RIGHT",  compactMoney = true, hint = "NPC vendor sell value for this step's outputs", defaultAsc = false },
		{ key = "sellChannel",       sortCol = "sellChannel",       label = "Sell",              width = 44,  minWidth = 38,  align = "CENTER", hint = "Recommended output channel: AH, V (Vendor), AH+V, -> #N (keep for later step), or '-'" },
		{ key = "heatBadge",         sortCol = "demandScore",       label = "Hotness",           width = 58,  minWidth = 48,  align = "CENTER", hint = "MerchantMaster Market Hotness: Sales/Day divided by current AH Listed Stock", defaultAsc = false },
		{ key = "dailySold",         sortCol = "dailySold",         label = "Sales/d",           width = 42,  minWidth = 36,  align = "RIGHT",  hint = "Estimated daily AH units sold for the crafted output", defaultAsc = false },
		{ key = "netCost",           sortCol = "allocatedNetCost",  label = "Net Cost / Profit", width = 92,  minWidth = 86,  align = "RIGHT",  compactMoney = true, hint = "True net cost or green +Profit after rolling in pre-crafted inputs from earlier steps." },
		{ key = "action",            sortCol = nil,                 label = "+ Cart",            width = 68,  minWidth = 62,  align = "CENTER", hint = "Left-Click: add step crafts to Shopping Cart · Right-Click: remove · Hold Shift for manual +/- stepper" },
	}
	MP.PATH_COLS = PATH_COLS

	local function showStepTooltip(owner, st)
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		if st.itemID and st.itemID > 0 and GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(st.itemID)
		else
			GameTooltip:AddLine(st.name, 1, 0.82, 0)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Skill Bracket:", st.skillRange .. "  (" .. (st.chanceRange or "—") .. ")", 0.85, 0.85, 0.85, 1, 0.82, 0)
		if not st.isMilestone and st.rec then
			local reqSkill = st.reqSkill or (st.ev and st.ev.effReq) or st.rec.req or 1
			local reqLv = st.reqLv or (st.ev and st.ev.effRlv) or st.rec.rlv or 1
			local reqStr = "Skill " .. tostring(reqSkill) .. ((reqLv > 1) and ("  ·  Char Lv " .. tostring(reqLv)) or "")
			GameTooltip:AddDoubleLine("Requires To Learn:", reqStr, 0.85, 0.85, 0.85, 0.75, 0.92, 1)
		elseif st.isMilestone then
			if (st.reqLv or 1) > 1 then
				GameTooltip:AddDoubleLine("Requires Character Level:", "Lv " .. tostring(st.reqLv), 0.85, 0.85, 0.85, 0.75, 0.92, 1)
			end
			if st.trainAt and st.trainAt > 1 and st.trainAt < (st.s1 or 1) then
				GameTooltip:AddDoubleLine("Can Train Starting At:", "Skill " .. tostring(st.trainAt), 0.85, 0.85, 0.85, 0.75, 0.92, 1)
			end
			if st.trainerInfo and st.trainerInfo.detail and st.trainerInfo.detail ~= "" then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Where to Train:", 1, 0.82, 0)
				GameTooltip:AddLine("  " .. st.trainerInfo.detail, 0.45, 0.95, 0.55, true)
				if st.trainerInfo.otherDetail and st.trainerInfo.otherDetail ~= "" then
					local otherTag = (st.trainerInfo.otherFaction == "A") and "[Alliance] " or "[Horde] "
					GameTooltip:AddLine("  " .. otherTag .. st.trainerInfo.otherDetail, 0.65, 0.65, 0.70, true)
				end
			end
		end
		if not st.isMilestone and not st.isSubCraftStep and (st.prepCrafts or 0) > 0 and (st.skillCrafts or 0) > 0 then
			GameTooltip:AddDoubleLine(
				"Craft Breakdown:",
				string.format("%dx for Skill %s + %dx sub-craft prep = %dx total", st.skillCrafts, st.skillRange, st.prepCrafts, st.crafts or 0),
				0.85, 0.85, 0.85, 0.45, 0.95, 1
			)
		end
		if st.ev and st.ev.favorTokens then
			GameTooltip:AddDoubleLine(
				"Unlock Source:",
				string.format("%s  (%d Merchant's Favor Tokens)", (st.sourceLabel or "—"), st.unlockFavor or st.ev.favorTokens),
				0.85, 0.85, 0.85, 0.35, 0.92, 0.72
			)
		else
			GameTooltip:AddDoubleLine("Unlock Source:", ((st.sourceLabel or "—")) .. "  (" .. formatMoney(st.unlockCost, true) .. ")", 0.85, 0.85, 0.85, 1, 1, 1)
		end
		if st.ev and st.ev.vendorName and st.ev.vendorName ~= "" then
			GameTooltip:AddDoubleLine("Vendor NPC:", st.ev.vendorName, 0.80, 0.80, 0.80, 0.55, 0.88, 1)
		end
		if not st.isMilestone and st.reagentDetails and #st.reagentDetails > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format("Reagents (%dx Crafts -> %dx Output):", st.crafts or 0, st.unitsMade or 0), 1, 0.82, 0)
			for _, rg in ipairs(st.reagentDetails) do
				local totNeed = rg.qtyPerCraft * (st.crafts or 1)
				local selfUsed = (st.consumedFromSteps and st.consumedFromSteps[rg.itemID]) or 0
				local ownInt = (st.consumedFromOwnedInterm and st.consumedFromOwnedInterm[rg.itemID]) or 0
				local remBuy = math.max(0, totNeed - selfUsed - ownInt)
				local boughtAH = st.boughtDirectOnAH and st.boughtDirectOnAH[rg.itemID]
				local effUnit = (boughtAH and rg.ahUnitCost and rg.ahUnitCost > 0) and rg.ahUnitCost or rg.unitCost
				local tag
				if selfUsed > 0 and ownInt > 0 then
					tag = string.format(" (%dx self-crafted + %dx owned)", selfUsed, ownInt)
				elseif selfUsed > 0 and remBuy > 0 and boughtAH then
					tag = string.format(" (%dx self-crafted, %dx [AH])", selfUsed, remBuy)
				elseif selfUsed > 0 then
					tag = string.format(" (%dx self-crafted in route!)", selfUsed)
				elseif ownInt > 0 and remBuy > 0 and boughtAH then
					tag = string.format(" (%dx owned, %dx [AH])", ownInt, remBuy)
				elseif ownInt > 0 then
					tag = string.format(" (%dx owned in bags)", ownInt)
				elseif boughtAH then
					tag = " [AH]"
				else
					tag = " [" .. (rg.source or "AH") .. "]"
				end
				GameTooltip:AddDoubleLine(
					string.format("  %dx %s%s", totNeed, MP.ItemName(rg.itemID), tag),
					formatMoney(remBuy * effUnit, true),
					0.9, 0.9, 0.9, 1, 1, 1
				)
			end
		end
		local ev = st.ev
		if not st.isMilestone and ev and (st.unitsMade or 0) > 0 and not (st.rec and st.rec.ench) and (st.itemID or 0) > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Output Resale & Market Hotness:", 1, 0.82, 0)
			if st.demand then
				local stockPart = (st.listed ~= nil) and (tostring(st.listed) .. " on AH") or "AH stock N/A"
				local salesPart
				if st.dailySold ~= nil then
					if ev.regionDailySold and ev.regionDailySold > st.dailySold * 1.05 then
						salesPart = string.format("%.1f/d realm (%.1f/d reg)", st.dailySold, ev.regionDailySold)
					else
						salesPart = string.format("%.1f/day", st.dailySold)
					end
				else
					salesPart = "0/day"
				end
				GameTooltip:AddDoubleLine("  Hotness (" .. salesPart .. " vs " .. stockPart .. "):", st.demand.stateLabel or st.demand.heatBadge or "—", 0.85, 0.85, 0.85, 1, 1, 1)
			end
			if ev.isUnlisted and not ev.isCustomPrice then
				GameTooltip:AddDoubleLine("  AH Status:", "UNLISTED (No active AH price — set custom market price in Outliers)", 0.85, 0.85, 0.85, 1, 1, 1)
			elseif ev.ahGrossUnit and ev.ahGrossUnit > 0 then
				local depStr = (ev.relistLossUnit and ev.relistLossUnit > 0)
					and (" - " .. formatMoney(ev.relistLossUnit, true) .. " relist")
					or " (0c relist risk)"
				GameTooltip:AddDoubleLine(
					"  AH Unit (" .. (ev.ahPriceSource or "AH") .. "):",
					string.format("%s - %s cut%s = %s", formatMoney(ev.ahGrossUnit, true), formatMoney(ev.ahCutUnit or 0, true), depStr, formatMoney(ev.ahNetUnit, true)),
					0.85, 0.85, 0.85, 0.55, 1, 0.70
				)
				if ev.conservativeCapped and ev.spotAHGrossUnit and ev.spotAHGrossUnit > ev.ahGrossUnit then
					GameTooltip:AddDoubleLine(
						"  Spot AH (Capped by " .. (ev.conservativeAnchorSrc or "Anchor") .. "):",
						formatMoney(ev.spotAHGrossUnit, true),
						0.75, 0.75, 0.75, 0.95, 0.75, 0.35
					)
				end
			end
			if ev.lastKnownAHUnit and ev.lastKnownAHUnit > 0 then
				GameTooltip:AddDoubleLine(
					"  Last Known AH Price (" .. (ev.lastKnownAHSource or "History") .. "):",
					formatMoney(ev.lastKnownAHUnit, true),
					0.85, 0.85, 0.85, 0.65, 0.90, 1
				)
			end
			if (ev.vendorUnit or 0) > 0 then
				GameTooltip:AddDoubleLine("  NPC Vendor Floor:", formatMoney(ev.vendorUnit, true) .. " / unit", 0.75, 0.75, 0.75, 0.85, 0.85, 0.85)
			end
			if (st.unitsKeptForLater or 0) > 0 then
				local destParts = {}
				for _, ks in ipairs(st.keptForSteps or {}) do
					local costPart = (ks.rolledCost and ks.rolledCost > 0) and (" (" .. formatMoney(ks.rolledCost, true) .. ")") or ""
					destParts[#destParts + 1] = string.format("%dx -> #%s %s%s", ks.qty, tostring(ks.stepNum or "?"), ks.name, costPart)
				end
				local destStr = (#destParts > 0) and table.concat(destParts, ", ") or (tostring(st.unitsKeptForLater) .. "x downstream")
				if (st.rolledOutCost or 0) > 0 then
					GameTooltip:AddDoubleLine("  Invested Into:", destStr, 0.85, 0.85, 0.85, 0.4, 0.95, 1)
				else
					GameTooltip:AddDoubleLine("  Reused in Later Step:", destStr .. " (value credited there)", 0.85, 0.85, 0.85, 0.4, 0.95, 1)
				end
			end
			if (st.ahSold or 0) > 0 then
				GameTooltip:AddDoubleLine(string.format("  Leftover Sold on AH (%dx):", st.ahSold), "+" .. formatMoney(st.ahSold * (ev.ahNetUnit or 0), true), 0.85, 0.85, 0.85, 0.3, 1, 0.5)
			end
			if (st.vendorSold or 0) > 0 and (ev.vendorUnit or 0) > 0 then
				GameTooltip:AddDoubleLine(string.format("  Leftover Sold to Vendor (%dx):", st.vendorSold), "+" .. formatMoney(st.vendorSold * ev.vendorUnit, true), 0.85, 0.85, 0.85, 0.85, 0.85, 0.85)
			end
			if (st.unitsKeptForLater or 0) > 0 and (st.standaloneResale or 0) > (st.resale or 0) then
				GameTooltip:AddDoubleLine(
					string.format("  If Sold Standalone (all %dx):", st.unitsMade),
					"+" .. formatMoney(st.standaloneResale, true) .. "  (" .. formatNetCostOrProfit(st.standaloneNetCost) .. ")",
					0.75, 0.82, 0.95, 1, 1, 1
				)
			end
		end
		GameTooltip:AddLine(" ")
		if (st.rolledInCost or 0) > 0 and st.rolledInSteps and #st.rolledInSteps > 0 then
			GameTooltip:AddLine("Rolled-In Pre-Crafts:", 1, 0.82, 0)
			for _, ri in ipairs(st.rolledInSteps) do
				GameTooltip:AddDoubleLine(
					string.format("  #%d %s (%dx)", ri.stepNum or 0, tostring(ri.name or ""), ri.qty or 0),
					formatMoney(ri.cost or 0, true),
					0.85, 0.85, 0.85, 0.4, 0.95, 1
				)
			end
			GameTooltip:AddDoubleLine(
				"Total Recipe Cost (Direct + Pre-Crafts):",
				formatMoney((st.unlockCost or 0) + (st.grossMats or 0) + (st.rolledInCost or 0), true),
				0.9, 0.9, 0.9, 1, 1, 1
			)
			if (st.reusedAHValue or 0) > (st.reusedInputMats or 0) * 1.15 then
				GameTooltip:AddDoubleLine(
					"Note: Reused parts AH value:",
					formatMoney(st.reusedAHValue, true),
					0.95, 0.78, 0.35, 0.95, 0.78, 0.35
				)
			end
		elseif (st.reusedInputMats or 0) > 0 then
			local fullNet = st.fullRecipeNet or 0
			local fullNetStr
			if fullNet > 0 then
				fullNetStr = "|cffff5533-" .. formatMoney(fullNet, true) .. " Loss|r"
			else
				fullNetStr = formatNetCostOrProfit(fullNet)
			end
			GameTooltip:AddDoubleLine(
				"Full Recipe Check (incl. sub-crafts):",
				string.format("Mats %s vs Resale %s -> %s", formatMoney(st.fullRecipeMats or 0, true), formatMoney(st.resale or 0, true), fullNetStr),
				1, 0.82, 0, 1, 1, 1
			)
			if (st.reusedAHValue or 0) > (st.reusedInputMats or 0) * 1.15 then
				GameTooltip:AddDoubleLine(
					"Note: Reused parts AH value:",
					formatMoney(st.reusedAHValue, true),
					0.95, 0.78, 0.35, 0.95, 0.78, 0.35
				)
			end
		end
		if st.isPureInvestment then
			local ttPal = getProfPalette()
			local ttMuted = colorHex(ttPal and ttPal.textMuted, "8e8e93")
			local destTag = formatKeptDestTag(st, false) or "later step"
			GameTooltip:AddDoubleLine("Step Net Result:", "|cff" .. ttMuted .. "— (Invested " .. destTag .. ")|r", 1, 0.82, 0, 1, 1, 1)
		elseif (st.rolledOutCost or 0) > 0 then
			GameTooltip:AddDoubleLine("Step Net (Leftover Sold):", formatNetCostOrProfit(st.allocatedNetCost), 1, 0.82, 0, 1, 1, 1)
		elseif (st.rolledInCost or 0) > 0 then
			GameTooltip:AddDoubleLine("Step Net (incl. Pre-Crafts):", formatNetCostOrProfit(st.allocatedNetCost), 1, 0.82, 0, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine("Step Net Result:", formatNetCostOrProfit(st.netCost), 1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip:AddLine("Left-Click: Quick View  ·  [+ Cart]: Add Step  ·  Hold Shift: Manual +/-  ·  Right-Click: Craft / AH", 0.65, 0.85, 1)
		GameTooltip:Show()
	end

	local function difficultyDotColor(d, pal)
		local colName = "gray"
		if d.isMilestone then
			return (pal and pal.accentBlue) or { 0.04, 0.52, 1.0 }
		elseif d.rec and MP.GetSkillColor then
			local sAt = d.s1 or 1
			colName = MP.GetSkillColor(d.rec, sAt, d.reqSkill)
		elseif type(d.chanceRange) == "string" then
			local pct = tonumber(d.chanceRange:match("(%d+)%%"))
			if pct then
				if pct >= 99 then colName = "orange"
				elseif pct >= 50 then colName = "yellow"
				elseif pct > 0 then colName = "green" end
			end
		end
		if colName == "orange" then
			return (pal and pal.accentOrange) or { 1.0, 0.57, 0.19 }
		elseif colName == "yellow" then
			return { 1.0, 0.84, 0.0 }
		elseif colName == "green" then
			return (pal and pal.accentGreen) or { 0.19, 0.82, 0.35 }
		else
			return (pal and pal.textMuted) or { 0.56, 0.56, 0.58 }
		end
	end

	papp.ui.pathTable = createProfTable(pathCard, -49, 0, PATH_COLS, function(r, d, tbl)
		local pal = getProfPalette()
		local isLight = Theme and Theme.GetMode and Theme.GetMode() == "light"
		if not r.cells then
			applyRowHighlight(r)
			if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
			r.cells = {}
			for i, col in ipairs(tbl.columns) do
				if col.key == "name" then
					local b = CreateFrame("Button", nil, r)
					b:SetSize(col.width, ROW_H)
					b:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
					local circlePath = (Theme and Theme.ASSETS and Theme.ASSETS.circle_fill)
					b.glyphBg = b:CreateTexture(nil, "ARTWORK")
					b.glyphBg:SetSize(28, 28)
					b.glyphBg:SetPoint("LEFT", 0, 0)
					if circlePath and b.glyphBg.SetTexture then
						b.glyphBg:SetTexture(circlePath)
					else
						b.glyphBg:SetColorTexture(1, 1, 1, 0.08)
					end
					b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
					b.icon:SetSize(16, 16)
					b.icon:SetPoint("CENTER", b.glyphBg, "CENTER", 0, 0)
					if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
					b.dot = b:CreateTexture(nil, "ARTWORK")
					b.dot:SetSize(6, 6)
					b.dot:SetPoint("LEFT", b.glyphBg, "RIGHT", 6, 0)
					if circlePath and b.dot.SetTexture then
						b.dot:SetTexture(circlePath)
					else
						b.dot:SetColorTexture(1, 0.57, 0.19, 1)
					end
					b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					b.fs:SetPoint("LEFT", b.dot, "RIGHT", 5, 0)
					b.fs:SetPoint("RIGHT", 0, 0)
					b.fs:SetJustifyH("LEFT")
					b.fs:SetWordWrap(false)
					applyFont(b.fs, 12, "semibold")
					b:SetScript("OnEnter", function(self) if self:GetParent().data then showStepTooltip(self, self:GetParent().data) end end)
					b:SetScript("OnLeave", GameTooltip_Hide)
					b:SetScript("OnClick", function(self, mouseBtn)
						local rf = self:GetParent()
						if rf and rf.data then handleProfRowClick(rf, rf.data, mouseBtn) end
					end)
					r.cells[i] = b
				elseif col.key == "action" then
					local ab = CreateFrame("Button", nil, r)
					ab:SetSize(col.width, math.min(24, ROW_H - 6))
					ab:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					if ab.RegisterForClicks then ab:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
					if Theme and Theme.RoundRect and Theme.ASSETS and Theme.ASSETS.pill_fill then
						ab.pillBg = Theme.RoundRect(ab, ab, "BACKGROUND", 0, 12, 0, 0.47, 0.47, 0.50, 0.14, Theme.ASSETS.pill_fill)
					else
						ab.bg = ab:CreateTexture(nil, "BACKGROUND")
						ab.bg:SetAllPoints()
					end
					ab.fs = ab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					ab.fs:SetAllPoints()
					ab.fs:SetJustifyH("CENTER")
					applyFont(ab.fs, 11, "semibold")
					ab:SetScript("OnEnter", function(self)
						local st = self:GetParent().data
						if not st then return end
						GameTooltip:SetOwner(self, "ANCHOR_TOP")
						if (st.isMilestone and not isBookMilestone(st)) or st.srcType == "gather" then
							GameTooltip:AddLine(st.name or "Milestone", 1, 0.82, 0)
							GameTooltip:AddLine("Trainer rank milestone or gathering step.", 0.85, 0.85, 0.88, true)
						else
							local cur = getProfRowQueuedQty(st)
							GameTooltip:AddLine(cur > 0 and ("In Shopping Cart (" .. tostring(cur) .. ")") or "Add Step to Shopping Cart", 1, 0.82, 0)
							GameTooltip:AddLine("Left-Click: add step crafts to Shopping Cart\nRight-Click: remove from Shopping Cart\nHold Shift: manual +/- stepper", 1, 1, 1, true)
						end
						GameTooltip:Show()
					end)
					ab:SetScript("OnLeave", GameTooltip_Hide)
					ab:SetScript("OnClick", function(self, mouseBtn)
						clickProfStepCartButton(self:GetParent().data, mouseBtn)
					end)
					r.cells[i] = ab
				else
					local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					fs:SetSize(col.width, ROW_H)
					fs:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					fs:SetJustifyH(col.align or "LEFT")
					fs:SetWordWrap(false)
					applyFont(fs, 12, "regular")
					r.cells[i] = fs
				end
			end
			r:SetScript("OnClick", function(self, mouseBtn)
				if self.data then handleProfRowClick(self, self.data, mouseBtn) end
			end)
		end

		r.data = d
		if r.sep and r.sep.SetColorTexture and pal and pal.separator then
			r.sep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], pal.separator[4] or 0.08)
		end

		if r.cells[3].glyphBg then
			local gc = isLight and 0 or 1
			local ga = isLight and 0.06 or 0.08
			if r.cells[3].glyphBg.SetVertexColor then
				r.cells[3].glyphBg:SetVertexColor(gc, gc, gc, ga)
			elseif r.cells[3].glyphBg.SetColorTexture then
				r.cells[3].glyphBg:SetColorTexture(gc, gc, gc, ga)
			end
		end

		local textHex = colorHex(pal and pal.text, "ffffff")
		local mutedHex = colorHex(pal and pal.textMuted, "8e8e93")
		local blueHex = colorHex(pal and (pal.textBlue or pal.accentBlue), "0a84ff")
		local greenHex = colorHex(pal and pal.accentGreen, "30d158")

		r.cells[1]:SetText("|cff" .. mutedHex .. tostring(d.stepNum or "") .. "|r")
		r.cells[2]:SetText(d.isMilestone and ("|cff" .. blueHex .. d.skillRange .. "|r") or ("|cff" .. textHex .. d.skillRange .. "|r"))

		local dc = difficultyDotColor(d, pal)
		if r.cells[3].dot and r.cells[3].dot.SetVertexColor then
			r.cells[3].dot:SetVertexColor(dc[1], dc[2], dc[3], 1)
		end
		r.cells[3].icon:SetTexture(getItemIcon(d.itemID, d.isMilestone and "Interface\\Icons\\INV_Misc_Book_11" or MP.PROFESSIONS[getProfDB().selectedProf].icon))
		r.cells[3].fs:SetText(
			d.isMilestone and ("|cff" .. blueHex .. d.name .. "|r")
			or ((d.isRod or d.isSubCraftStep) and ("|cff" .. blueHex .. d.name .. "|r")
			or ("|cff" .. textHex .. (d.name or "") .. "|r"))
		)
		local pathSrcCell = (d.sourceLabel or "—")
		if pathSrcCell ~= "Known" and pathSrcCell ~= "Sub-Craft" then
			if d.srcType == "camp" then
				pathSrcCell = "|cff" .. greenHex .. pathSrcCell .. "|r"
			elseif (d.srcType == "vendor" and not (d.ev and d.ev.scrollViaAH)) or (d.isMilestone and (d.itemID or 0) > 0) then
				pathSrcCell = "|cff" .. blueHex .. pathSrcCell .. "|r"
			else
				pathSrcCell = "|cff" .. colorHex(pal and pal.textSecondary, "aeaeb2") .. pathSrcCell .. "|r"
			end
		else
			pathSrcCell = "|cff" .. mutedHex .. pathSrcCell .. "|r"
		end
		r.cells[4]:SetText(pathSrcCell)
		r.cells[5]:SetText((d.crafts and d.crafts > 0) and ("|cff" .. textHex .. tostring(d.crafts) .. "|r") or ("|cff" .. mutedHex .. "—|r"))
		r.cells[6]:SetText("|cff" .. colorHex(pal and pal.textSecondary, "aeaeb2") .. (d.chanceRange or "—") .. "|r")
		r.cells[7]:SetText(((d.unlockFavor or 0) > 0)
			and string.format("|cff%s%d Favor|r", greenHex, d.unlockFavor)
			or formatMoney(d.unlockCost, false))
		r.cells[8]:SetText(formatMoney(d.grossMats, false))
		local stepUnlisted = (not d.isMilestone) and d.ev and d.ev.isUnlisted and true or false
		local stepCustom = (not d.isMilestone) and d.ev and d.ev.isCustomPrice and true or false
		local ahTot = d.ahResaleTotal
		if ahTot == nil and not d.isMilestone and (d.ahSold or 0) > 0 and (d.resale or 0) > 0 then
			ahTot = d.resale
		end
		if ahTot ~= nil then
			local ownSuffix = stepCustom and (" |cff" .. blueHex .. "[Own]|r") or ""
			r.cells[9]:SetText(formatMoney(ahTot, true) .. ownSuffix)
		else
			r.cells[9]:SetText("|cff" .. mutedHex .. "-|r")
		end

		local vendTot = d.vendorResaleTotal
		if vendTot == nil and not d.isMilestone and (d.ahSold or 0) == 0 and (d.resale or 0) > 0 then
			vendTot = d.resale
		end
		if vendTot and vendTot > 0 then
			r.cells[10]:SetText(formatMoney(vendTot, true))
		else
			r.cells[10]:SetText("|cff" .. mutedHex .. "-|r")
		end

		local sellChan = d.sellChannel
		if sellChan == nil then
			if d.isMilestone or d.isRod then
				sellChan = "-"
			elseif (d.ahSold or 0) > 0 and (d.vendorSold or 0) > 0 then
				sellChan = "AH+V"
			elseif (d.ahSold or 0) > 0 then
				sellChan = "AH"
			elseif (d.vendorSold or 0) > 0 then
				sellChan = "V"
			elseif (d.unitsKeptForLater or 0) > 0 then
				local destTag = formatKeptDestTag(d, false)
				if (d.resale or 0) > 0 and destTag then
					sellChan = "V " .. destTag
				elseif destTag then
					sellChan = destTag
				else
					sellChan = "Kept"
				end
			elseif (d.resale or 0) > 0 then
				sellChan = "V"
			else
				sellChan = "-"
			end
		end
		local orangeHex = colorHex(pal and pal.accentOrange, "ff9230")
		local secHex = colorHex(pal and pal.textSecondary, "aeaeb2")
		local chanHex
		if sellChan == "AH" then
			chanHex = greenHex
		elseif sellChan == "AH+V" then
			chanHex = orangeHex
		elseif sellChan:sub(1, 1) == "V" then
			chanHex = secHex
		elseif sellChan:find("->", 1, true) or sellChan == "Kept" then
			chanHex = blueHex
		else
			chanHex = mutedHex
		end
		r.cells[11]:SetText("|cff" .. chanHex .. sellChan .. "|r")

		r.cells[12]:SetText(d.heatBadge or ("|cff" .. mutedHex .. "—|r"))
		setCellBold(r.cells[12], stepUnlisted)
		r.cells[13]:SetText(formatSalesPerDay(d.dailySold))
		if d.isPureInvestment then
			r.cells[14]:SetText("|cff" .. mutedHex .. "—|r")
		elseif d.allocatedNetCost ~= nil then
			r.cells[14]:SetText(formatNetCostOrProfit(d.allocatedNetCost))
		elseif (d.reusedInputMats or 0) > 0 and (d.netCost or 0) < 0 and (d.fullRecipeNet or 0) > 0 then
			local n = math.floor(tonumber(d.netCost) or 0)
			r.cells[14]:SetText("|cff" .. orangeHex .. "+|r" .. formatMoney(-n, true) .. "|cff" .. orangeHex .. "*|r")
		else
			r.cells[14]:SetText(formatNetCostOrProfit(d.netCost))
		end
		paintProfRowShiftState(r, tbl, true)
	end, "path")

	-----------------------------------------------------------------------------------------------
	-- Shared Shopping Row Renderer + Floating Shopping List Window (1060 x 460) + Tab 2 Full Shopping List
	-- 4 + 950 + 10*5 = 1004 <= 1048px
	local SHOP_COLS = {
		{ key = "skillRange",  sortCol = "sortSkill",   label = "Level",                        width = 68,  align = "CENTER", defaultAsc = true, hint = "Skill level bracket where this item is needed (Consolidated merged range or per-bracket By Level)" },
		{ key = "name",        sortCol = "name",        label = "Shopping Item / Recipe Scroll", width = 198, align = "LEFT",   hint = "Click any non-vendor row to search & buy the exact quantity on the Auction House" },
		{ key = "source",      sortCol = "source",      label = "Acquire Via",                   width = 100, align = "CENTER", hint = "Cheapest source (Vendor (<g/s/c>), Vendor (<N> Favor), Vendor, AH, AH Scroll)" },
		{ key = "usedIn",      sortCol = "usedIn",      label = "Used In Step(s)",               width = 152, align = "LEFT",   hint = "Which leveling recipes consume this item" },
		{ key = "totalNeed",   sortCol = "totalNeed",   label = "Total Need",                    width = 58,  align = "RIGHT",  hint = "Gross quantity required", defaultAsc = false },
		{ key = "ownedOrSelf", sortCol = "ownedOrSelf", label = "Owned / Self",                  width = 68,  align = "RIGHT",  hint = "Units covered by Bags/Bank/Mail/Alts + self-crafted intermediates from earlier steps", defaultAsc = false },
		{ key = "buyQty",      sortCol = "buyQty",      label = "Buy Qty",                       width = 52,  align = "RIGHT",  hint = "Net quantity you still need to buy", defaultAsc = false },
		{ key = "listed",      sortCol = "listed",      label = "AH Stock",                      width = 56,  align = "RIGHT",  hint = "Quantity currently listed on the Auction House", defaultAsc = false },
		{ key = "dailySold",   sortCol = "dailySold",   label = "Sales/Day",                     width = 56,  align = "RIGHT",  hint = "Estimated daily AH sales", defaultAsc = false },
		{ key = "unitPrice",   sortCol = "unitPrice",   label = "Unit Price",                    width = 68, minWidth = 92,  align = "RIGHT",  hint = "Unit acquisition price (or Favor tokens)", defaultAsc = false },
		{ key = "lineCost",    sortCol = "lineCost",    label = "Line Total",                    width = 74, minWidth = 92,  align = "RIGHT",  hint = "Buy Qty x Unit Price", defaultAsc = false },
	}
	MP.SHOP_COLS = SHOP_COLS

	local function setShoppingGroupMode(mode)
		local d = getProfDB()
		if mode ~= "by_level" then mode = "consolidated" end
		d.shoppingGroupMode = mode
		if mode == "by_level" then
			papp.sortState.shop = { col = "sortSkill", asc = true }
		else
			papp.sortState.shop = { col = "lineCost", asc = false }
		end
		mmApp.refresh()
	end
	papp.setShoppingGroupMode = setShoppingGroupMode

	local function fillShoppingRow(r, d, tbl)
		if not r.cells then
			applyRowHighlight(r)
			r.cells = {}
			for i, col in ipairs(tbl.columns) do
				if col.key == "name" then
					local b = CreateFrame("Button", nil, r)
					b:SetSize(col.width, ROW_H)
					b:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					local circlePath = (Theme and Theme.ASSETS and Theme.ASSETS.circle_fill)
					b.glyphBg = b:CreateTexture(nil, "ARTWORK")
					b.glyphBg:SetSize(28, 28)
					b.glyphBg:SetPoint("LEFT", 0, 0)
					if circlePath and b.glyphBg.SetTexture then
						b.glyphBg:SetTexture(circlePath)
					else
						b.glyphBg:SetColorTexture(1, 1, 1, 0.08)
					end
					b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
					b.icon:SetSize(16, 16)
					b.icon:SetPoint("CENTER", b.glyphBg, "CENTER", 0, 0)
					if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
					b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					b.fs:SetPoint("LEFT", b.glyphBg, "RIGHT", 8, 0)
					b.fs:SetPoint("RIGHT", 0, 0)
					b.fs:SetJustifyH("LEFT")
					b.fs:SetWordWrap(false)
					applyFont(b.fs, 12, "semibold")
					b:SetScript("OnEnter", function(self)
						local row = self:GetParent().data
						if not row then return end
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						if row.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(row.itemID) else GameTooltip:AddLine(row.name, 1, 1, 1) end
						GameTooltip:AddLine(" ")
						if row.skillRangesDetail or row.skillRange then
							GameTooltip:AddDoubleLine("Skill Level Range:", tostring(row.skillRangesDetail or row.skillRange), 0.85, 0.85, 0.85, 1, 0.82, 0)
						end
						GameTooltip:AddDoubleLine("Acquire Via:", tostring(row.source or "AH"), 0.85, 0.85, 0.85, 0.65, 0.90, 1)
						if row.favorTokens then
							GameTooltip:AddDoubleLine("Vendor Recipe Cost:", string.format("%d Merchant's Favor Tokens", row.lineFavor or row.favorTokens), 0.85, 0.85, 0.85, 0.35, 0.92, 0.72)
						end
						GameTooltip:AddDoubleLine("Total Needed:", tostring(row.totalNeed), 0.85, 0.85, 0.85, 1, 1, 1)
						if (row.selfCrafted or 0) > 0 then
							GameTooltip:AddDoubleLine("Self-Crafted in Earlier Step:", tostring(row.selfCrafted) .. " (0c extra)", 0.85, 0.85, 0.85, 0.4, 0.95, 1)
						end
						if (row.ownedUsed or 0) > 0 then
							GameTooltip:AddDoubleLine("Deducted from Owned Stock:", tostring(row.ownedUsed), 0.85, 0.85, 0.85, 0.3, 1, 0.5)
						end
						GameTooltip:AddDoubleLine("Net Buy Qty:", tostring(row.buyQty) .. "  (" .. ((row.lineFavor and row.lineFavor > 0) and (tostring(row.lineFavor) .. " Favor") or formatMoney(row.lineCost, true)) .. ")", 1, 0.82, 0, 1, 1, 1)
						if row.lowStock and row.listed ~= nil then
							GameTooltip:AddLine(string.format("Low AH Stock: only %d listed right now (need %d)", row.listed, row.buyQty), 1, 0.45, 0.25, true)
						end
						if not row.isVendor then
							GameTooltip:AddLine("Click to search " .. tostring(math.max(1, row.buyQty)) .. "x on Auction House", 0.65, 0.85, 1)
						end
						GameTooltip:Show()
					end)
					b:SetScript("OnLeave", GameTooltip_Hide)
					b:SetScript("OnClick", function(self)
						local row = self:GetParent().data
						if row and not row.isVendor and MM.SearchAH then MM.SearchAH(row.name, math.max(1, row.buyQty), row.itemID) end
					end)
					r.cells[i] = b
				else
					local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					fs:SetSize(col.width, ROW_H)
					fs:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					fs:SetJustifyH(col.align or "LEFT")
					fs:SetWordWrap(false)
					applyFont(fs, 12, "regular")
					r.cells[i] = fs
				end
			end
			r:SetScript("OnClick", function(self)
				local row = self.data
				if row and not row.isVendor and MM.SearchAH then MM.SearchAH(row.name, math.max(1, row.buyQty), row.itemID) end
			end)
		end
		if d.favorCost and d.favorCost > 0 then
			d.lineCost = 0
			d.lineFavor = d.favorCost * (d.buyQty or d.qty or 1)
		end
		r.data = d
		r.bg:SetColorTexture(0, 0, 0, 0)
		local isLight = Theme and Theme.GetMode and Theme.GetMode() == "light"
		if r.cells[2].glyphBg then
			local gc = isLight and 0 or 1
			local ga = isLight and 0.06 or 0.08
			if r.cells[2].glyphBg.SetVertexColor then
				r.cells[2].glyphBg:SetVertexColor(gc, gc, gc, ga)
			elseif r.cells[2].glyphBg.SetColorTexture then
				r.cells[2].glyphBg:SetColorTexture(gc, gc, gc, ga)
			end
		end
		local sPal = getProfPalette()
		local sTextHex = colorHex(sPal and sPal.text, "ffffff")
		local sSecHex = colorHex(sPal and sPal.textSecondary, "aeaeb2")
		local sMutedHex = colorHex(sPal and sPal.textMuted, "8e8e93")
		local sGreenHex = colorHex(sPal and sPal.accentGreen, "30d158")
		local sBlueHex = colorHex(sPal and (sPal.textBlue or sPal.accentBlue), "0a84ff")
		local sOrangeHex = colorHex(sPal and sPal.accentOrange, "ff9230")
		if r.sep and r.sep.SetColorTexture and sPal and sPal.separator then
			r.sep:SetColorTexture(sPal.separator[1], sPal.separator[2], sPal.separator[3], (sPal.separator[4] or 0.25) * 0.45)
		end
		r.cells[1]:SetText("|cff" .. sTextHex .. tostring(d.skillRange or "—") .. "|r")
		r.cells[2].icon:SetTexture(getItemIcon(d.itemID))
		r.cells[2].fs:SetText("|cff" .. sTextHex .. tostring(d.name or "") .. "|r")
		r.cells[3]:SetText(d.favorTokens and ("|cff" .. sGreenHex .. (d.source or "Camp") .. "|r") or (d.isVendor and "|cff" .. sBlueHex .. (d.source or "Vendor") .. "|r" or ("|cff" .. sOrangeHex .. (d.source or "AH") .. "|r")))
		r.cells[4]:SetText("|cff" .. sSecHex .. (d.usedIn or "") .. "|r")
		r.cells[5]:SetText("|cff" .. sTextHex .. tostring(d.totalNeed or 0) .. "|r")
		r.cells[6]:SetText((d.ownedOrSelf and d.ownedOrSelf > 0) and ("|cff" .. sGreenHex .. tostring(d.ownedOrSelf) .. "|r") or ("|cff" .. sMutedHex .. "0|r"))
		r.cells[7]:SetText(d.buyQty > 0 and ("|cff" .. sTextHex .. tostring(d.buyQty) .. "|r") or ("|cff" .. sGreenHex .. "0|r"))
		local shopUnlisted = (not d.isVendor) and (d.listed == 0)
		if d.isVendor then
			r.cells[8]:SetText("|cff" .. sBlueHex .. "Inf|r")
		elseif shopUnlisted then
			r.cells[8]:SetText("|cff" .. sTextHex .. "UNLISTED|r")
		elseif d.listed ~= nil then
			r.cells[8]:SetText(d.lowStock and ("|cff" .. sOrangeHex .. tostring(d.listed) .. "!|r") or ("|cff" .. sTextHex .. tostring(d.listed) .. "|r"))
		else
			r.cells[8]:SetText("|cff" .. sMutedHex .. "—|r")
		end
		setCellBold(r.cells[8], shopUnlisted)
		r.cells[9]:SetText(formatSalesPerDay(d.dailySold))
		r.cells[10]:SetText(d.favorTokens and string.format("|cff%s%d Favor|r", sGreenHex, d.favorTokens) or formatMoney(d.unitPrice, true))
		r.cells[11]:SetText((d.favorCost and d.favorCost > 0) and ("|cff" .. sGreenHex .. tostring(d.lineFavor or 0) .. " Favor|r") or formatMoney(d.lineCost, true))
	end

	-----------------------------------------------------------------------------------------------
	-- TAB 2: Full Shopping List
	local shopView = CreateFrame("Frame", nil, profBody)
	shopView:SetAllPoints()
	shopView:Hide()
	papp.ui.shopView = shopView

	local shopCard = CreateFrame("Frame", nil, shopView)
	shopCard:SetAllPoints()
	if Theme and Theme.NineApple then
		shopCard._mmGlass = Theme.NineApple(shopCard, "glass_r10", "cardBg", false, { noSpecular = true })
	end
	papp.ui.shopCard = shopCard

	local shopHead = CreateFrame("Frame", nil, shopCard)
	shopHead:SetPoint("TOPLEFT", shopCard, "TOPLEFT", 0, 0)
	shopHead:SetPoint("TOPRIGHT", shopCard, "TOPRIGHT", 0, 0)
	shopHead:SetHeight(48)
	local shopHeadSep = shopHead:CreateTexture(nil, "BORDER")
	shopHeadSep:SetPoint("BOTTOMLEFT", 0, 0)
	shopHeadSep:SetPoint("BOTTOMRIGHT", 0, 0)
	shopHeadSep:SetHeight(1)
	papp.ui.shopHeadSep = shopHeadSep

	local shopHdrFs = shopHead:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	shopHdrFs:SetPoint("LEFT", 16, 0)
	shopHdrFs:SetPoint("RIGHT", -440, 0)
	shopHdrFs:SetJustifyH("LEFT")
	shopHdrFs:SetWordWrap(false)
	applyFont(shopHdrFs, 14, "semibold")
	papp.ui.shopHdrFs = shopHdrFs

	local shopAddCartBtn = Theme.CreatePlateButton(shopHead, "+ Add All to Cart", 142, 28, { primary = true })
	shopAddCartBtn:SetPoint("RIGHT", shopHead, "RIGHT", -12, 0)
	shopAddCartBtn:SetScript("OnClick", function()
		local changed = papp.addOverviewToCart()
		local pk = getProfDB().selectedProf or "alchemy"
		if (changed or 0) > 0 and not papp.isViewLocked(pk) then
			papp.promptLockGuide(pk)
		end
	end)
	papp.ui.shopAddCartBtn = shopAddCartBtn

	local shopAllAucBtn = Theme.CreatePlateButton(shopHead, "Buy All AH Items", 214, 28, { variant = "secondary" })
	shopAllAucBtn:SetPoint("RIGHT", shopAddCartBtn, "LEFT", -8, 0)
	shopAllAucBtn:SetScript("OnClick", function()
		papp.sendShoppingToBuyer()
	end)
	papp.ui.shopAllAucBtn = shopAllAucBtn

	local shopByLevelBtn = Theme.CreatePlateButton(shopHead, "By Level", 92, 26)
	shopByLevelBtn:SetPoint("RIGHT", shopAllAucBtn, "LEFT", -8, 0)
	shopByLevelBtn:SetScript("OnClick", function()
		setShoppingGroupMode("by_level")
	end)
	shopByLevelBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("By Level Shopping Breakdown", 1, 0.82, 0)
		GameTooltip:AddLine("Splits shopping quantities per chronological skill bracket (e.g. 1 -> 55, 55 -> 90, 150 -> 210) so you can see exactly what is needed at each leveling stage.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	shopByLevelBtn:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.shopByLevelBtn = shopByLevelBtn

	local shopConsolidatedBtn = Theme.CreatePlateButton(shopHead, "Consolidated", 108, 26)
	shopConsolidatedBtn:SetPoint("RIGHT", shopByLevelBtn, "LEFT", -4, 0)
	shopConsolidatedBtn:SetScript("OnClick", function()
		setShoppingGroupMode("consolidated")
	end)
	shopConsolidatedBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Consolidated Shopping List (Standard)", 1, 0.82, 0)
		GameTooltip:AddLine("Merges identical materials across all steps into a single shopping total while showing the combined Level range.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	shopConsolidatedBtn:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.shopConsolidatedBtn = shopConsolidatedBtn
	local shopResetBtn = Theme.CreatePlateButton(shopHead, "Reset Filters", 106, 24, { variant = "secondary", pill = true, fontSize = 11 })
	shopResetBtn:SetPoint("RIGHT", shopConsolidatedBtn, "LEFT", -8, 0)
	shopResetBtn:SetScript("OnClick", function() papp.resetFilters() end)
	papp.ui.shopResetBtn = shopResetBtn
	local shopFiltersBtn = mmApp.createFiltersButton(shopHead, "shopFiltersBtn", shopResetBtn)
	papp.ui.shopFiltersBtn = shopFiltersBtn
	shopHdrFs:ClearAllPoints()
	shopHdrFs:SetPoint("LEFT", 16, 0)
	shopHdrFs:SetPoint("RIGHT", shopFiltersBtn, "LEFT", -10, 0)

	local shopHdrHover = CreateFrame("Frame", nil, shopHead)
	shopHdrHover:SetPoint("TOPLEFT", shopHead, "TOPLEFT", 12, 0)
	shopHdrHover:SetPoint("BOTTOMRIGHT", shopFiltersBtn, "BOTTOMLEFT", -8, 0)
	if shopHdrHover.EnableMouse then shopHdrHover:EnableMouse(true) end
	shopHdrHover:SetScript("OnEnter", function(self)
		local vs = papp.lastVendorStops
		if not (GameTooltip and vs and (vs.stopCount or 0) > 0) then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(string.format("Vendor Stops (%d %s)", vs.stopCount, vs.stopCount == 1 and "stop" or "stops"), 1, 0.82, 0)
		for idx, st in ipairs(vs.stops or {}) do
			local loc = st.zone and (st.coords and (st.zone .. " (" .. st.coords .. ")") or st.zone) or ""
			local head = string.format("%d. %s%s", idx, st.name or "Vendor", (loc ~= "") and (" — " .. loc) or "")
			local costStr = (st.totalCost or 0) > 0 and formatMoney(st.totalCost, true) or ""
			if (st.totalFavor or 0) > 0 then
				costStr = (costStr ~= "" and (costStr .. " + ") or "") .. tostring(st.totalFavor) .. " Favor"
			end
			GameTooltip:AddDoubleLine(head, costStr ~= "" and costStr or "—", 0.55, 0.88, 1, 1, 1, 1)
			for _, it in ipairs(st.items or {}) do
				GameTooltip:AddLine(string.format("   %dx %s", it.qty or 1, it.name or ""), 0.85, 0.85, 0.88)
			end
		end
		GameTooltip:Show()
	end)
	shopHdrHover:SetScript("OnLeave", GameTooltip_Hide)
	papp.ui.shopHdrHover = shopHdrHover

	papp.ui.shopTable = createProfTable(shopCard, -49, 0, SHOP_COLS, fillShoppingRow, "shop")

	-----------------------------------------------------------------------------------------------
	-- TAB 3: Browse All Recipes (Explore & Profit-Check Every Recipe in Profession)
	local browseView = CreateFrame("Frame", nil, profBody)
	browseView:SetAllPoints()
	browseView:Hide()
	papp.ui.browseView = browseView
	if Theme and Theme.NineApple then
		browseView._mmGlass = Theme.NineApple(browseView, "glass_r10", "cardBg", false, { noSpecular = true })
	end

	-- 4 + 988 + 11*5 = 1047 <= 1048px
	local BROWSE_COLS = {
		{ key = "req",          sortCol = "req",          label = "Req",            width = 44,  minWidth = 38,  align = "RIGHT",  hint = "Skill rank and character level required to learn" },
		{ key = "thresholds",   sortCol = "gr",           label = "Yel / Grn / Gry",width = 82,  minWidth = 72,  align = "CENTER", hint = "Skill thresholds where recipe turns Yellow, Green, and Gray" },
		{ key = "name",         sortCol = "name",         label = "Recipe",         width = 152, minWidth = 112, align = "LEFT",   hint = "Click to search output or reagents on Auction House" },
		{ key = "sourceLabel",  sortCol = "sourceLabel",  label = "Source",         width = 102, minWidth = 78,  align = "CENTER", hint = "How the recipe is acquired, including NPC vendor coin cost or Merchant's Favor token cost" },
		{ key = "chanceAtFrom", sortCol = "chanceAtFrom", label = "Skill %",        width = 50,  minWidth = 42,  align = "CENTER", hint = "Skill-up probability at your current 'From' skill (including Working Overtime)", defaultAsc = false },
		{ key = "unlockCost",   sortCol = "unlockCost",   label = "Unlock",         width = 58,  minWidth = 54,  align = "RIGHT",  compactMoney = true, hint = "One-time unlock price when unlearned (or Favor tokens for Camp recipes)", defaultAsc = true },
		{ key = "craftCost",    sortCol = "craftCost",    label = "Craft Cost",     width = 66,  minWidth = 58,  align = "RIGHT",  compactMoney = true, hint = "Reagent cost for 1 craft", defaultAsc = true },
		{ key = "ahUnit",       sortCol = "ahUnit",       label = "AH",             width = 64,  minWidth = 56,  align = "RIGHT",  compactMoney = true, hint = "Expected AH net resale for 1 craft's output ('-' when unlisted / soulbound)", defaultAsc = false },
		{ key = "vendorUnit",   sortCol = "vendorUnit",   label = "Vendor",         width = 60,  minWidth = 54,  align = "RIGHT",  compactMoney = true, hint = "NPC vendor sell value for 1 craft's output", defaultAsc = false },
		{ key = "sellChannel",  sortCol = "sellChannel",  label = "Sell",           width = 40,  minWidth = 36,  align = "CENTER", hint = "Best output channel for 1 craft: AH, V (Vendor), or '-'" },
		{ key = "heatBadge",    sortCol = "demandScore",  label = "Hotness",        width = 72,  minWidth = 60,  align = "CENTER", hint = "MerchantMaster Market Hotness: Sales/Day divided by current AH Listed Stock", defaultAsc = false },
		{ key = "dailySold",    sortCol = "dailySold",    label = "Sales/d",        width = 48,  minWidth = 40,  align = "RIGHT",  hint = "Estimated daily AH sales", defaultAsc = false },
		{ key = "profitCraft",  sortCol = "profitCraft",  label = "Profit / Craft", width = 78,  minWidth = 72,  align = "RIGHT",  compactMoney = true, hint = "Best output resale (AH net or Vendor floor) minus Craft Cost per single craft", defaultAsc = false },
		{ key = "status",       sortCol = "statusSort",   label = "Status",         width = 52,  minWidth = 46,  align = "CENTER", hint = "Known, Available at From skill & level, or Locked by Skill / Char Lv / Spec" },
	}
	MP.BROWSE_COLS = BROWSE_COLS

	local function showBrowseTooltip(owner, row)
		if not row then return end
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		if row.itemID and row.itemID > 0 and GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(row.itemID)
		else
			GameTooltip:AddLine(row.name, 1, 0.82, 0)
		end
		local ev = row.ev
		GameTooltip:AddLine(" ")
		local rSkill = row.req or 1
		local rLv = row.rlv or 1
		GameTooltip:AddDoubleLine("Requires To Learn:", "Skill " .. tostring(rSkill) .. ((rLv > 1) and ("  ·  Char Lv " .. tostring(rLv)) or ""), 0.85, 0.85, 0.85, 0.75, 0.92, 1)
		GameTooltip:AddDoubleLine("Recipe Source:", tostring(row.sourceLabel or "—"), 0.85, 0.85, 0.85, 1, 1, 1)
		if ev then
			if ev.favorTokens and ev.favorTokens > 0 then
				local crateGold = ev.favorTokens * (row.favorUnitPrice or 0)
				local standNames = { [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }
				local repNote = (ev.repStanding and standNames[ev.repStanding]) and ("  ·  " .. standNames[ev.repStanding]) or ""
				GameTooltip:AddDoubleLine(
					"Vendor Recipe Cost:",
					string.format("%d Merchant's Favor Tokens (~ %s)%s", ev.favorTokens, formatMoney(crateGold, true), repNote),
					0.85, 0.85, 0.85, 0.35, 0.92, 0.72
				)
			elseif ev.vendorCopperCost and ev.vendorCopperCost > 0 then
				GameTooltip:AddDoubleLine("Vendor Recipe Cost:", formatMoney(ev.vendorCopperCost, true), 0.85, 0.85, 0.85, 0.55, 0.88, 1)
			end
			if ev.vendorName and ev.vendorName ~= "" then
				GameTooltip:AddDoubleLine("Vendor NPC:", ev.vendorName, 0.80, 0.80, 0.80, 0.55, 0.88, 1)
			end
			if ev.demand and (row.itemID or 0) > 0 then
				local stockPart = (ev.listed ~= nil) and (tostring(ev.listed) .. " on AH") or "AH stock N/A"
				local salesPart = (ev.dailySold ~= nil) and string.format("%.1f/day", ev.dailySold) or "0/day"
				GameTooltip:AddDoubleLine("Market Hotness (" .. salesPart .. " vs " .. stockPart .. "):", ev.demand.stateLabel or "—", 0.85, 0.85, 0.85, 1, 1, 1)
			end
			if ev.isUnlisted and not ev.isCustomPrice then
				GameTooltip:AddDoubleLine("AH Status:", "UNLISTED (No active AH price — set custom market price in Outliers)", 0.85, 0.85, 0.85, 1, 1, 1)
			elseif ev.ahGrossUnit and ev.ahGrossUnit > 0 then
				GameTooltip:AddDoubleLine(
					"AH Unit (" .. (ev.ahPriceSource or "AH") .. "):",
					string.format("%s - %s cut - %s relist = %s", formatMoney(ev.ahGrossUnit, true), formatMoney(ev.ahCutUnit or 0, true), formatMoney(ev.relistLossUnit or 0, true), formatMoney(ev.ahNetUnit, true)),
					0.85, 0.85, 0.85, 0.55, 1, 0.70
				)
			end
			if ev.lastKnownAHUnit and ev.lastKnownAHUnit > 0 then
				GameTooltip:AddDoubleLine(
					"Last Known AH Price (" .. (ev.lastKnownAHSource or "History") .. "):",
					formatMoney(ev.lastKnownAHUnit, true),
					0.85, 0.85, 0.85, 0.65, 0.90, 1
				)
			end
			if (ev.vendorUnit or 0) > 0 then
				GameTooltip:AddDoubleLine("NPC Vendor Floor:", formatMoney(ev.vendorUnit, true), 0.75, 0.75, 0.75, 0.85, 0.85, 0.85)
			end
		end
		GameTooltip:Show()
	end

	local browseBar = CreateFrame("Frame", nil, browseView)
	browseBar:SetPoint("TOPLEFT", 0, 0)
	browseBar:SetPoint("TOPRIGHT", 0, 0)
	browseBar:SetHeight(34)
	local browseResetBtn = Theme.CreatePlateButton(browseBar, "Reset Filters", 106, 24, { variant = "secondary", pill = true, fontSize = 11 })
	browseResetBtn:SetPoint("RIGHT", -12, 0)
	browseResetBtn:SetScript("OnClick", function() papp.resetFilters() end)
	papp.ui.browseResetBtn = browseResetBtn
	local browseFiltersBtn = mmApp.createFiltersButton(browseBar, "browseFiltersBtn", browseResetBtn)
	papp.ui.browseFiltersBtn = browseFiltersBtn
	papp.ui.browseGoalSeg = createProfGoalSegment(browseBar, browseFiltersBtn)
	if Theme and Theme.CreateBadgePill then
		local brShiftPill = Theme.CreateBadgePill(browseBar, "Quick-Add Mode", "blue", { height = 22, fontSize = 11, padX = 14 })
		if brShiftPill and brShiftPill.frame then
			brShiftPill.frame:SetPoint("LEFT", browseBar, "LEFT", 16, 0)
			brShiftPill.frame:Hide()
			papp.ui.browseShiftBadge = brShiftPill.frame
		end
	end
	papp.ui.browseTable = createProfTable(browseView, -34, 0, BROWSE_COLS, function(r, d, tbl)
		if not r.cells then
			applyRowHighlight(r)
			if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
			r.cells = {}
			for i, col in ipairs(tbl.columns) do
				if col.key == "name" then
					local b = CreateFrame("Button", nil, r)
					b:SetSize(col.width, ROW_H)
					b:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
					local circlePath = (Theme and Theme.ASSETS and Theme.ASSETS.circle_fill)
					b.glyphBg = b:CreateTexture(nil, "ARTWORK")
					b.glyphBg:SetSize(28, 28)
					b.glyphBg:SetPoint("LEFT", 0, 0)
					if circlePath and b.glyphBg.SetTexture then
						b.glyphBg:SetTexture(circlePath)
					else
						b.glyphBg:SetColorTexture(1, 1, 1, 0.08)
					end
					b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
					b.icon:SetSize(16, 16)
					b.icon:SetPoint("CENTER", b.glyphBg, "CENTER", 0, 0)
					if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
					b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					b.fs:SetPoint("LEFT", b.glyphBg, "RIGHT", 8, 0)
					b.fs:SetPoint("RIGHT", 0, 0)
					b.fs:SetJustifyH("LEFT")
					b.fs:SetWordWrap(false)
					applyFont(b.fs, 12, "semibold")
					b:SetScript("OnEnter", function(self) showBrowseTooltip(self, self:GetParent().data) end)
					b:SetScript("OnLeave", GameTooltip_Hide)
					b:SetScript("OnClick", function(self, mouseBtn)
						local rf = self:GetParent()
						if rf and rf.data then handleProfRowClick(rf, rf.data, mouseBtn) end
					end)
					r.cells[i] = b
				else
					local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
					fs:SetSize(col.width, ROW_H)
					fs:SetPoint("LEFT", r, "LEFT", tbl.colX[i], 0)
					fs:SetJustifyH(col.align or "LEFT")
					fs:SetWordWrap(false)
					applyFont(fs, 12, "regular")
					r.cells[i] = fs
				end
			end
			r:SetScript("OnClick", function(self, mouseBtn)
				if self.data then handleProfRowClick(self, self.data, mouseBtn) end
			end)
		end
		r.data = d
		local isLight = Theme and Theme.GetMode and Theme.GetMode() == "light"
		if r.cells[3].glyphBg then
			local gc = isLight and 0 or 1
			local ga = isLight and 0.06 or 0.08
			if r.cells[3].glyphBg.SetVertexColor then
				r.cells[3].glyphBg:SetVertexColor(gc, gc, gc, ga)
			elseif r.cells[3].glyphBg.SetColorTexture then
				r.cells[3].glyphBg:SetColorTexture(gc, gc, gc, ga)
			end
		end
		local bPal = getProfPalette()
		if r.sep and r.sep.SetColorTexture and bPal and bPal.separator then
			r.sep:SetColorTexture(bPal.separator[1], bPal.separator[2], bPal.separator[3], (bPal.separator[4] or 0.25) * 0.45)
		end
		local bTextHex = colorHex(bPal and bPal.text, "ffffff")
		local bMutedHex = colorHex(bPal and bPal.textMuted, "8e8e93")
		local bSecHex = colorHex(bPal and bPal.textSecondary, "aeaeb2")
		local bGreenHex = colorHex(bPal and bPal.accentGreen, "30d158")
		local bBlueHex = colorHex(bPal and (bPal.textBlue or bPal.accentBlue), "0a84ff")
		local bOrangeHex = colorHex(bPal and bPal.accentOrange, "ff9230")
		local bRedHex = colorHex(bPal and bPal.accentRed, "ff453a")
		local bPurpleHex = colorHex(bPal and bPal.accentPurple, "bf5af2")
		r.cells[1]:SetText("|cff" .. bTextHex .. tostring(d.reqStr or d.req or 1) .. "|r")
		r.cells[2]:SetText(d.thresholds or ("|cff" .. bMutedHex .. "—|r"))
		r.cells[3].icon:SetTexture(getItemIcon(d.itemID, MP.PROFESSIONS[getProfDB().selectedProf].icon))
		r.cells[3].fs:SetText("|cff" .. bTextHex .. tostring(d.name or "") .. "|r")
		local srcOut = d.sourceLabel or "—"
		if d.srcType == "camp" then
			srcOut = "|cff" .. bGreenHex .. srcOut .. "|r"
		elseif d.srcType == "vendor" and not (d.ev and d.ev.scrollViaAH) then
			srcOut = "|cff" .. bBlueHex .. srcOut .. "|r"
		elseif d.srcType == "ah" or (d.ev and d.ev.scrollViaAH) then
			srcOut = "|cff" .. bOrangeHex .. srcOut .. "|r"
		elseif d.srcType == "trainer" then
			srcOut = "|cff" .. bSecHex .. srcOut .. "|r"
		elseif d.srcType == "quest" then
			srcOut = "|cff" .. bPurpleHex .. srcOut .. "|r"
		end
		r.cells[4]:SetText(srcOut)
		r.cells[5]:SetText(d.chanceStr or ("|cff" .. bMutedHex .. "—|r"))
		if not d.known and d.favorTokens and d.favorTokens > 0 then
			r.cells[6]:SetText(string.format("|cff%s%d Favor|r", bGreenHex, d.favorTokens))
		else
			r.cells[6]:SetText(formatMoney(d.unlockCost, false))
		end
		r.cells[7]:SetText(d.craftCost and formatMoney(d.craftCost, true) or ("|cff" .. bRedHex .. "Unpriced|r"))
		if d.ahUnit ~= nil then
			local ownTag = d.resaleIsCustom and (" |cff" .. bBlueHex .. "[Own]|r") or ""
			r.cells[8]:SetText(formatMoney(d.ahUnit, true) .. ownTag)
		else
			r.cells[8]:SetText("|cff" .. bMutedHex .. "-|r")
		end
		if d.vendorUnit and d.vendorUnit > 0 then
			r.cells[9]:SetText(formatMoney(d.vendorUnit, true))
		else
			r.cells[9]:SetText("|cff" .. bMutedHex .. "-|r")
		end
		local bChan = d.sellChannel or "-"
		local bChanHex = (bChan == "AH" and bGreenHex) or (bChan == "V" and bSecHex) or bMutedHex
		r.cells[10]:SetText("|cff" .. bChanHex .. bChan .. "|r")
		r.cells[11]:SetText(d.heatBadge or ("|cff" .. bMutedHex .. "—|r"))
		setCellBold(r.cells[11], d.isUnlisted == true)
		r.cells[12]:SetText(formatSalesPerDay(d.dailySold))
		if d.profitCraft ~= nil then
			r.cells[13]:SetText(d.profitCraft >= 0 and ("|cff" .. bGreenHex .. "+" .. formatMoney(d.profitCraft, true) .. "|r") or ("|cff" .. bRedHex .. "-" .. formatMoney(-d.profitCraft, true) .. "|r"))
		else
			r.cells[13]:SetText("|cff" .. bMutedHex .. "—|r")
		end
		r.cells[14]:SetText(d.status or "")
		paintProfRowShiftState(r, tbl, false)
	end, "browse")

	local function syncProfessorActiveShoppingList(pathRes, profKey, fromSkill, effTarget, isByLevel)
		local consolidatedShop = (pathRes and pathRes.shoppingList) or {}
		local mmRows = {}
		local needBuyCount, totalBuyCopper, totalFavor = 0, 0, 0
		for _, it in ipairs(consolidatedShop) do
			if (it.buyQty or 0) > 0 then
				needBuyCount = needBuyCount + 1
				local favorCost = it.favorCost or it.favorTokens or 0
				local lineFavor = favorCost > 0 and favorCost * it.buyQty or 0
				local lineCost = favorCost > 0 and 0 or (it.lineCost or 0)
				totalBuyCopper = totalBuyCopper + lineCost
				totalFavor = totalFavor + lineFavor
				mmRows[#mmRows + 1] = {
					itemID = it.itemID,
					name = it.name,
					icon = getItemIcon(it.itemID),
					role = (it.source and it.source:find("Scroll")) and "Scroll" or "Reagent",
					qty = it.buyQty,
					owned = it.ownedOrSelf or 0,
					isVendor = it.isVendor == true,
					listed = it.listed,
					dailySold = it.dailySold,
					ahUnitPrice = (not it.isVendor and not it.favorTokens) and it.unitPrice or nil,
					ahTotalPrice = (not it.isVendor and not it.favorTokens) and it.lineCost or nil,
					lineCost = lineCost,
					favorCost = favorCost,
					lineFavor = lineFavor,
					action = it.isVendor and "NPC Vendor" or "Buy AH",
				}
			end
		end
		local modeTag = isByLevel and "By Level" or "Consolidated"
		local pName = (MP.PROFESSIONS[profKey] and MP.PROFESSIONS[profKey].name) or profKey
		local sPal = getProfPalette()
		local sTextHex = colorHex(sPal and sPal.text, "ffffff")
		local sMutedHex = colorHex(sPal and sPal.textMuted, "8e8e93")
		local sGreenHex = colorHex(sPal and sPal.accentGreen, "30d158")
		local summaryStr = string.format(
			"|cff%s%s Leveling (%d -> %d · %s):|r  %d items to buy  ·  Total Spend: %s  ·  Est. Resale: |cff%s+%s|r",
			sTextHex, pName, fromSkill, effTarget, modeTag, needBuyCount,
			formatMoney(totalBuyCopper, true) .. (totalFavor > 0 and (" + " .. tostring(totalFavor) .. " Favor") or ""), sGreenHex, formatMoney(pathRes and pathRes.totalResale or 0, true))
		if mmApp.hasUnifiedShoppingItems and mmApp.hasUnifiedShoppingItems() then
			if mmApp.syncUnifiedShoppingList then
				mmApp.syncUnifiedShoppingList()
			end
		elseif mmApp._profPreviewCleared then
			mmApp.setActiveShoppingList({}, "|cff" .. sMutedHex .. "Shopping List is empty. Click [+ Add to List] or [+ Queue] on any screen.|r", "Shopping List", mmApp.activeTab)
		else
			mmApp.setActiveShoppingList(mmRows, summaryStr, "Shopping List")
		end
		return needBuyCount, totalBuyCopper, totalFavor
	end

	local function refreshProfessor(activeLeafTab, _, statusFs, scanBanner, rawSearch)
		local db = getProfDB()
		-- Auto-sync profession selection if user picked a crafting profession in MerchantMaster sidebar earlier
		local mmProf = MerchantMasterDB and MerchantMasterDB.profFilter
		if mmProf and MP.PROFESSIONS[mmProf] and db.selectedProf ~= mmProf then
			db.selectedProf = mmProf
		end
		local profKey = db.selectedProf or "alchemy"
		if not MP.PROFESSIONS[profKey] then
			profKey = "alchemy"
			db.selectedProf = profKey
		end

		local subKey = "path"
		if activeLeafTab == "prof_shop" then subKey = "shop"
		elseif activeLeafTab == "prof_browse" then subKey = "browse" end
		papp.activeTab = subKey
		db.activeTab = subKey

		papp.ui.pathView:SetShown(subKey == "path")
		papp.ui.shopView:SetShown(subKey == "shop")
		papp.ui.browseView:SetShown(subKey == "browse")
		if papp.ui.kpiStrip then
			papp.ui.kpiStrip:SetShown(subKey == "path")
		end
		if subKey == "path" and papp.layoutKpis then
			papp.layoutKpis()
		end

		local liveProfs = MP.ScanPlayerProfessions()
		local legacy = MP.GetEffectiveLegacy(db)
		local effCharLv, isAutoCharLv = MP.GetEffectiveCharLevel(db)

		local lvLabel = isAutoCharLv
			and string.format("Lv: Auto (%d)", effCharLv)
			or string.format("Lv: %d", effCharLv)
		papp.ui.charLvBtn:SetText(lvLabel)

		local otLabel = (db.overtimeMode == "auto")
			and string.format("Overtime: Auto (%d/5)", legacy.overtime)
			or findOptLabel(OVERTIME_OPTIONS, db.overtimeMode)
		papp.ui.overtimeBtn:SetText(otLabel)
		local activeGoal = db.goalMode or "smart"
		papp.ui.goalBtn:SetText(findOptLabel(GOAL_OPTIONS, activeGoal))
		if papp.ui.goalSeg then papp.ui.goalSeg:SetActive(activeGoal, true) end
		if papp.ui.browseGoalSeg then papp.ui.browseGoalSeg:SetActive(activeGoal, true) end
		local knownOnly = (MerchantMasterDB and MerchantMasterDB.knownRecipesOnly == true) or (db.recipeFilter == "known_only")
		local effectiveFilter = knownOnly and "known_only" or (db.recipeFilter or "trainer_vendor")
		papp.ui.recFilterBtn:SetText(findOptLabel(RECIPE_FILTER_OPTIONS, effectiveFilter))
		papp.ui.horizonBtn:SetText(findOptLabel(SELL_DAYS_OPTIONS, db.sellDays or 3))
		papp.ui.ownedChk:SetChecked(db.useOwned ~= false)

		local fromSkill, targetSkill = getProfBounds(profKey)
		if not (papp.ui.fromBox.HasFocus and papp.ui.fromBox:HasFocus()) then
			papp.ui.fromBox:SetText(tostring(fromSkill))
		end
		if not (papp.ui.toBox.HasFocus and papp.ui.toBox:HasFocus()) then
			papp.ui.toBox:SetText(tostring(targetSkill))
		end

		local search = (rawSearch or ""):lower():match("^%s*(.-)%s*$")

		papp._warmedVendorProfs = papp._warmedVendorProfs or {}
		if ns.WarmLiveVendorPrices and MP.RECIPES and MP.RECIPES[profKey] and not papp._warmedVendorProfs[profKey] then
			papp._warmedVendorProfs[profKey] = true
			local warmIDs, warmSeen = {}, {}
			for _, rec in ipairs(MP.RECIPES[profKey]) do
				local oid = rec.i
				if oid and oid > 0 and not warmSeen[oid] then
					warmSeen[oid] = true
					warmIDs[#warmIDs + 1] = oid
				end
			end
			ns.WarmLiveVendorPrices(warmIDs)
		end

		local lockedSnap = papp.getLockedSnapshot(profKey)
		local pathRes
		if lockedSnap and lockedSnap.pathRes then
			pathRes = lockedSnap.pathRes
		else
			pathRes = MP.SolveProfessionPath(profKey, {
				startSkill = fromSkill,
				targetSkill = targetSkill,
				liveProfs = liveProfs,
			})
		end
		papp.lastPathResult = pathRes
		papp.syncLockUI(profKey)

		local effTarget = pathRes.targetSkill or targetSkill
		local econInfo = ns.CurrentEconomyInfo()
		local palStatus = getProfPalette()
		local capNote = ""
		if pathRes.levelLocked and pathRes.levelCapInfo then
			capNote = string.format("  ·  |cff%sRequires Char Lv %d (%s)|r", colorHex(palStatus and palStatus.accentOrange, "ff9230"), pathRes.levelCapInfo.nextReqLv or 5, pathRes.levelCapInfo.nextRankName or "Rank")
		elseif pathRes.knownCapSkill then
			capNote = string.format("  ·  |cff%sKnown Cap %d|r", colorHex(palStatus and palStatus.accentGreen, "30d158"), pathRes.knownCapSkill)
		elseif pathRes.levelCapInfo then
			capNote = string.format("  ·  |cff%sLv %d Cap %d (%s at Lv %d)|r", colorHex(palStatus and palStatus.textSecondary, "aeaeb2"), effCharLv, pathRes.levelCapInfo.cappedTarget, pathRes.levelCapInfo.nextRankName or "Next Rank", pathRes.levelCapInfo.nextReqLv or 60)
		end
		if statusFs then
			applyFont(statusFs, 11, "regular")
			if statusFs.SetTextColor and palStatus and palStatus.textSecondary then
				statusFs:SetTextColor(palStatus.textSecondary[1], palStatus.textSecondary[2], palStatus.textSecondary[3], palStatus.textSecondary[4] or 0.72)
			end
			-- "Normal-Horde" -> "Normal · Horde" (same middle-dot economy label as the main status capsule)
			local econLabel = tostring(econInfo.label or ""):gsub("%-(Horde)$", " · %1"):gsub("%-(Alliance)$", " · %1")
			if subKey == "path" then
				if scanBanner then
					statusFs:SetText(scanBanner)
				elseif papp._kpiHasRoomForStatus then
					statusFs:SetText(string.format("OT %d/5 (+%d%%)  ·  %s%s", legacy.overtime, legacy.overtime * 4, econLabel, capNote))
				else
					statusFs:SetText("")
				end
			else
				statusFs:SetText(scanBanner or string.format("%s %d -> %d  ·  OT %d/5 (+%d%%)  ·  %s%s",
					MP.PROFESSIONS[profKey].name, fromSkill, effTarget, legacy.overtime, legacy.overtime * 4, econLabel, capNote))
			end
		end

		local consolidatedShop = pathRes.shoppingList or {}
		local isByLevel = (db.shoppingGroupMode == "by_level")
		local activeShopList = isByLevel and (pathRes.shoppingListByLevel or consolidatedShop) or consolidatedShop
		local modeTag = isByLevel and "By Level" or "Consolidated"

		if papp.ui.shopConsolidatedBtn then papp.ui.shopConsolidatedBtn:SetActive(not isByLevel) end
		if papp.ui.shopByLevelBtn then papp.ui.shopByLevelBtn:SetActive(isByLevel) end

		local _, totalBuyCopper, totalFavor = syncProfessorActiveShoppingList(pathRes, profKey, fromSkill, effTarget, isByLevel)

		if papp.ui.pathTable then
			papp.ui.pathTable.headerBar:SetShown(true)
			papp.ui.pathTable.inset:SetShown(true)
		end
		if papp.ui.browseTable then
			papp.ui.browseTable.headerBar:SetShown(true)
			papp.ui.browseTable.inset:SetShown(true)
		end

		local function paintPillState(pill, active)
			pill:SetActive(active)
			applyFont(pill.fs, 11, active and "semibold" or "regular")
		end

		local function updateSkillMeter(card, skillVal, pal)
			if not card then return end
			local pct = math.max(0.02, math.min(1.0, (skillVal or 1) / 300))
			local isLight = Theme and Theme.GetMode and Theme.GetMode() == "light"
			local fc = (pal and pal.meterFill) or (isLight and { 0, 0, 0, 0.78 } or { 1, 1, 1, 0.86 })
			local tc = (pal and pal.meterTrack) or (isLight and { 0, 0, 0, 0.08 } or { 1, 1, 1, 0.10 })
			if card.progressBar and card.progressBar.SetValue then
				card.progressBar:SetValue(pct)
				return
			end
			local trackW = (card.meterTrack and card.meterTrack.GetWidth and card.meterTrack:GetWidth()) or 280
			if trackW < 20 then trackW = 280 end
			local fillW = math.max(6, math.floor(trackW * pct + 0.5))
			if card.meterFillFrame and card.meterFillPill then
				card.meterFillFrame:SetWidth(fillW)
				card.meterFillPill:SetColor(fc[1], fc[2], fc[3], fc[4] or 0.86)
				if card.meterTrackPill then
					card.meterTrackPill:SetColor(tc[1], tc[2], tc[3], tc[4] or 0.10)
				end
			elseif card.meterFillTex then
				card.meterFillTex:SetWidth(fillW)
				if card.meterFillTex.SetColorTexture then card.meterFillTex:SetColorTexture(fc[1], fc[2], fc[3], fc[4] or 0.86) end
				if card.meterTrackTex and card.meterTrackTex.SetColorTexture then
					card.meterTrackTex:SetColorTexture(tc[1], tc[2], tc[3], tc[4] or 0.10)
				end
			end
		end
		papp._updateSkillMeter = updateSkillMeter
		papp._paintPillState = paintPillState

		for _, pp in ipairs(papp.ui.profPills or {}) do
			paintPillState(pp, pp.profKey == profKey, false)
		end
		for _, bp in ipairs(papp.ui.bracketPills or {}) do
			local bd = bp.bracket
			local isAct = (papp.activeBracket == bd.key)
			local isDone = (bd.key ~= "all") and (fromSkill >= bd.hi)
			paintPillState(bp, isAct, isDone)
		end

		if subKey == "path" then
			local pal = getProfPalette()
			local textHex = colorHex(pal and pal.text, "ffffff")
			local mutedHex = colorHex(pal and pal.textMuted, "8e8e93")
			local greenHex = colorHex(pal and pal.accentGreen, "30d158")
			local orangeHex = colorHex(pal and pal.accentOrange, "ff9230")
			local redHex = colorHex(pal and pal.accentRed, "ff453a")

			local cards = papp.ui.kpiCards
			local craftSteps = 0
			for _, st in ipairs(pathRes.steps or {}) do
				st.prof = profKey
				if not st.isMilestone then craftSteps = craftSteps + 1 end
			end

			local activeBrk = nil
			for _, bp in ipairs(papp.ui.bracketPills or {}) do
				if bp.bracket.key == papp.activeBracket and bp.bracket.key ~= "all" then
					activeBrk = bp.bracket
					break
				end
			end

			local stepRows = {}
			local stepNumSet = {}
			for _, st in ipairs(pathRes.steps or {}) do
				local matchSearch = (search == "" or (st.name and st.name:lower():find(search, 1, true)) or (st.sourceLabel and st.sourceLabel:lower():find(search, 1, true)))
				local matchBrk = true
				if activeBrk then
					local s1 = st.s1 or st.sortSkill or 1
					local s2 = st.s2 or s1
					if s2 > s1 then
						matchBrk = (s2 > activeBrk.lo and s1 < activeBrk.hi)
					else
						matchBrk = (s1 >= activeBrk.lo and (s1 < activeBrk.hi or (activeBrk.hi == 300 and s1 == 300)))
					end
				end
				if matchSearch and matchBrk then
					stepRows[#stepRows + 1] = st
					if st.stepNum then stepNumSet[st.stepNum] = true end
				end
			end
			papp.lastVisiblePathSteps = stepRows

			local isFiltered = (activeBrk ~= nil) or (search ~= "")
			local dispNetCost, dispGrossMats, dispTrainUnlocks, dispResale, dispFavorTokens, dispStepCount, dispCrafts, dispCraftSteps
			if not isFiltered then
				dispNetCost = pathRes.netCost
				dispGrossMats = pathRes.totalGrossMats or 0
				dispTrainUnlocks = pathRes.totalTrainUnlocks or 0
				dispResale = pathRes.totalResale or 0
				dispFavorTokens = pathRes.totalFavorTokens or 0
				dispStepCount = #(pathRes.steps or {})
				dispCrafts = pathRes.totalCrafts or 0
				dispCraftSteps = craftSteps
			else
				local stepGrossSum, extraFavor = 0, 0
				dispTrainUnlocks, dispResale, dispCrafts, dispCraftSteps = 0, 0, 0, 0
				for _, st in ipairs(stepRows) do
					stepGrossSum = stepGrossSum + (st.grossMats or 0)
					dispTrainUnlocks = dispTrainUnlocks + (st.unlockCost or 0)
					dispResale = dispResale + (st.resale or 0)
					dispCrafts = dispCrafts + (st.crafts or 0)
					if not st.isMilestone then dispCraftSteps = dispCraftSteps + 1 end
					local listedFavor = st.scrollNeed and (st.scrollNeed.favorTokens or 0) * (st.scrollNeed.qty or 1) or 0
					extraFavor = extraFavor + math.max(0, (st.unlockFavor or 0) - listedFavor)
				end
				local leafOwnedSaved, favorFromShop = 0, 0
				for _, sn in ipairs(pathRes.shoppingListByLevel or {}) do
					if sn.stepNum and stepNumSet[sn.stepNum] then
						if not (sn.favorTokens and sn.favorTokens > 0) then
							leafOwnedSaved = leafOwnedSaved + ((sn.ownedUsed or 0) * (sn.unitPrice or 0))
						end
						favorFromShop = favorFromShop + (sn.lineFavor or 0)
					end
				end
				dispGrossMats = math.max(0, stepGrossSum - leafOwnedSaved)
				dispFavorTokens = favorFromShop + extraFavor
				dispStepCount = #stepRows
				dispNetCost = (dispStepCount > 0 or not pathRes.unreachable) and (dispTrainUnlocks + dispGrossMats - dispResale) or nil
			end
			papp.lastFilteredStats = {
				bracket = activeBrk and activeBrk.key or "all",
				stepCount = dispStepCount,
				craftSteps = dispCraftSteps,
				totalCrafts = dispCrafts,
				totalGrossMats = dispGrossMats,
				totalTrainUnlocks = dispTrainUnlocks,
				totalResale = dispResale,
				totalFavorTokens = dispFavorTokens,
				netCost = dispNetCost,
			}

			-- Card 1: Current Skill + Meter Progress Bar
			if pathRes.levelLocked and pathRes.levelCapInfo then
				cards[1].val:SetText(string.format("|cff%sRequires Lv %d|r", redHex, pathRes.levelCapInfo.nextReqLv or 5))
				if cards[1].unit then cards[1].unit:SetText("") end
				cards[1].sub:SetText(string.format("Lv %d too low for %s", effCharLv, pathRes.levelCapInfo.nextRankName or MP.PROFESSIONS[profKey].name))
			elseif pathRes.alreadyAtLevelCap and pathRes.levelCapInfo then
				cards[1].val:SetText(string.format("|cff%s%d / %d|r", orangeHex, fromSkill, pathRes.levelCapInfo.cappedTarget))
				if cards[1].unit then cards[1].unit:SetText("|cff" .. mutedHex .. "Cap|r") end
				cards[1].sub:SetText(string.format("%s unlocks at Lv %d", pathRes.levelCapInfo.nextRankName or "Next Rank", pathRes.levelCapInfo.nextReqLv or 60))
			else
				cards[1].val:SetText(string.format("|cff%s%d -> %d|r", textHex, fromSkill, effTarget))
				if cards[1].unit then cards[1].unit:SetText("|cff" .. mutedHex .. "/ 300|r") end
				if pathRes.levelCapInfo then
					cards[1].sub:SetText(string.format("Lv %d cap %d · %s at Lv %d", effCharLv, pathRes.levelCapInfo.cappedTarget, pathRes.levelCapInfo.nextRankName or "Next", pathRes.levelCapInfo.nextReqLv or 60))
				elseif pathRes.knownCapSkill then
					cards[1].sub:SetText(string.format("Known Recipes cap %d · %d recipes", pathRes.knownCapSkill, craftSteps))
				else
					local subText
					if pathRes.fallbackRange then
						local fr = pathRes.fallbackRange
						local fbLbl = (fr.filterKey == "trainer_vendor") and "Vendor" or ((fr.filterKey == "with_ah") and "AH Scroll" or "All")
						subText = string.format("%s · %s bridge %d-%d", MP.PROFESSIONS[profKey].name, fbLbl, fr.from or 1, fr.to or 300)
					elseif pathRes.usedFallbackFilter then
						subText = "Auto-expanded: " .. pathRes.usedFallbackFilter
					else
						subText = MP.PROFESSIONS[profKey].name .. " · " .. craftSteps .. " recipes"
					end
					cards[1].sub:SetText(subText)
				end
			end
			updateSkillMeter(cards[1], fromSkill, pal)

			-- Card 2: Est. Leveling Cost (updates dynamically with active bracket filter)
			cards[2].lbl:SetText(activeBrk and string.format("Est. Leveling Cost (%d-%d)", activeBrk.lo, activeBrk.hi) or "Est. Leveling Cost")
			local favorSuffix = dispFavorTokens > 0 and (" + " .. tostring(dispFavorTokens) .. " Favor") or ""
			if dispNetCost == nil then
				cards[2].val:SetText("|cff" .. mutedHex .. "—|r")
				if cards[2].unit then cards[2].unit:SetText("") end
			else
				local nCost = math.floor(tonumber(dispNetCost) or 0)
				if nCost < 0 then
					cards[2].val:SetText("|cff" .. textHex .. "+|r" .. formatMoney(-nCost, true))
					if cards[2].unit then cards[2].unit:SetText("|cff" .. mutedHex .. "net profit" .. favorSuffix .. "|r") end
				elseif nCost == 0 then
					cards[2].val:SetText(zeroCopper(textHex))
					if cards[2].unit then cards[2].unit:SetText("|cff" .. mutedHex .. "Break-Even" .. favorSuffix .. "|r") end
				else
					cards[2].val:SetText("|cff" .. textHex .. "-|r" .. formatMoney(nCost, true))
					if cards[2].unit then cards[2].unit:SetText("|cff" .. mutedHex .. "net cost" .. favorSuffix .. "|r") end
				end
			end
			local copperMoney = (GetMoney and GetMoney()) or 0
			local runway = MP.ComputeGoldRunway and MP.ComputeGoldRunway(stepRows, copperMoney) or nil
			papp.lastGoldRunway = runway
			cards[2]._runway = runway
			local runwaySuffix = ""
			if runway and copperMoney > 0 and #stepRows > 0 then
				runwaySuffix = runway.isFunded
					and " · Funded"
					or string.format(" · Short %s (#%d)", formatMoney(runway.shortfallCopper, true), runway.shortfallStepNum or 1)
			end
			cards[2].sub:SetText(string.format("Mats %s · Train %s · Resale +%s%s",
				formatMoney(dispGrossMats, true),
				formatMoney(dispTrainUnlocks, true),
				formatMoney(dispResale, true),
				runwaySuffix))

			-- Card 3: Steps Remaining (updates dynamically with active bracket filter)
			cards[3].lbl:SetText(activeBrk and string.format("Steps (%d-%d)", activeBrk.lo, activeBrk.hi) or "Steps Remaining")
			cards[3].val:SetText(string.format("|cff%s%d Steps|r", textHex, dispStepCount))
			if cards[3].unit then
				cards[3].unit:SetText(string.format("|cff%s(%d Crafts)|r", mutedHex, dispCrafts))
			end
			cards[3].sub:SetText(string.format("%d recipes · Overtime %d/5 (+%d%% skill-up)", dispCraftSteps, legacy.overtime, legacy.overtime * 4))

			if papp.ui.pathHeadTitle then
				papp.ui.pathHeadTitle:SetText(activeBrk and ("Leveling Route · " .. activeBrk.label) or "Leveling Route")
			end
			if papp.ui.pathAddCartBtn then
				papp.ui.pathAddCartBtn:SetText(activeBrk and string.format("+ Add %d-%d to Cart", activeBrk.lo, activeBrk.hi) or "+ Add All to Cart")
			end
			if papp.ui.pathBadge and papp.ui.pathBadge.SetVariant then
				papp.ui.pathBadge.SetVariant("neutral", string.format("%d steps · %d crafts", dispStepCount, dispCrafts))
			end
			local srt = papp.sortState.path
			sortProfRows(stepRows, srt.col, srt.asc, "stepNum", { name = true, sourceLabel = true, sellChannel = true })
			if papp.layoutDetailPane then papp.layoutDetailPane() end
			local foundSel = nil
			if papp.selectedStepNum then
				for _, st in ipairs(stepRows) do
					if st.stepNum == papp.selectedStepNum then foundSel = st break end
				end
			end
			if not foundSel and #stepRows > 0 then
				for _, st in ipairs(stepRows) do
					if not st.isMilestone and st.rolledInSteps and #st.rolledInSteps > 0 then foundSel = st break end
				end
				if not foundSel then
					for _, st in ipairs(stepRows) do
						if not st.isMilestone and st.reagentDetails and #st.reagentDetails > 0 and (st.ahResaleTotal or 0) > 0 then foundSel = st break end
					end
				end
				foundSel = foundSel or stepRows[1]
			end
			papp.selectedStepData = foundSel
			papp.selectedStepNum = foundSel and foundSel.stepNum or nil
			papp.ui.pathTable.updateHeaders()
			papp.ui.pathTable.setRows(stepRows)

		elseif subKey == "shop" then
			local shopRows = {}
			local ahLines, vendorLines = 0, 0
			for _, it in ipairs(consolidatedShop) do
				if (it.buyQty or 0) > 0 then
					if it.isVendor then vendorLines = vendorLines + 1 else ahLines = ahLines + 1 end
				end
			end
			for _, it in ipairs(activeShopList) do
				if search == "" or (it.name and it.name:lower():find(search, 1, true)) or (it.usedIn and it.usedIn:lower():find(search, 1, true)) or (it.skillRange and it.skillRange:lower():find(search, 1, true)) then
					shopRows[#shopRows + 1] = it
				end
			end
			local srt = papp.sortState.shop
			sortProfRows(shopRows, srt.col, srt.asc, isByLevel and "sortSkill" or "lineCost", { name = true, source = true, usedIn = true })
			papp.ui.shopTable.updateHeaders()
			papp.ui.shopTable.setRows(shopRows)
			local vendorStops = MP.BuildVendorStops and MP.BuildVendorStops(activeShopList, MP.GetPlayerFactionCode()) or nil
			papp.lastVendorStops = vendorStops
			local stopSuffix = (vendorStops and (vendorStops.stopCount or 0) > 0)
				and string.format(" (%d %s)", vendorStops.stopCount, vendorStops.stopCount == 1 and "stop" or "stops")
				or ""
			local sPal = getProfPalette()
			local sTextHex = colorHex(sPal and sPal.text, "ffffff")
			local sGreenHex = colorHex(sPal and sPal.accentGreen, "30d158")
			papp.ui.shopHdrFs:SetText(string.format(
				"|cff%s%s (%d -> %d) %s:|r  %d AH + %d Vendor%s  ·  Total Spend: %s  ·  Est. Resale: |cff%s+%s|r",
				sTextHex, MP.PROFESSIONS[profKey].name, fromSkill, effTarget, modeTag, ahLines, vendorLines, stopSuffix,
				formatMoney(totalBuyCopper, true) .. (totalFavor > 0 and (" + " .. tostring(totalFavor) .. " Favor") or ""), sGreenHex, formatMoney(pathRes.totalResale or 0, true)
			))

		elseif subKey == "browse" then
			local raw = MP.RECIPES[profKey] or {}
			local filterKnownOnly = knownOnly
			local liveFavorUnit = (MP.GetBestFavorUnitPrice and MP.GetBestFavorUnitPrice(ns, legacy.favorYieldMult)) or 0
			local applyAHCut = (MerchantMasterDB == nil) or (MerchantMasterDB.applyAHCut ~= false)
			local smartFilterColdItems = (MerchantMasterDB and MerchantMasterDB.smartFilterColdItems ~= nil) and (MerchantMasterDB.smartFilterColdItems ~= false) or (db.smartFilterColdItems ~= false)
			local subCraftMode = (MerchantMasterDB and MerchantMasterDB.subCraftMode) or db.subCraftMode or "smart"
			local subCraftOverrides = (MerchantMasterDB and MerchantMasterDB.subCraftOverrides) or db.subCraftOverrides or {}
			local bPal = getProfPalette()
			local brTextHex = colorHex(bPal and bPal.text, "ffffff")
			local brSecHex = colorHex(bPal and bPal.textSecondary, "aeaeb2")
			local brMutedHex = colorHex(bPal and bPal.textMuted, "8e8e93")
			local brGreenHex = colorHex(bPal and bPal.accentGreen, "30d158")
			local brBlueHex = colorHex(bPal and (bPal.textBlue or bPal.accentBlue), "0a84ff")
			local brOrangeHex = colorHex(bPal and bPal.accentOrange, "ff9230")
			local brRedHex = colorHex(bPal and bPal.accentRed, "ff453a")
			local priceRev = (type(ns.GetPriceDataRevision) == "function" and ns.GetPriceDataRevision()) or ns.priceCacheEpoch or 0
			local playerFaction = (MP.GetPlayerFactionCode and MP.GetPlayerFactionCode()) or "AH"
			local playerKnowsEnchanting = (MP.ScanPlayerProfessions and (MP.ScanPlayerProfessions().enchanting ~= nil)) or false
			local function smallMapSig(tbl)
				if type(tbl) ~= "table" then return "" end
				local parts = {}
				for k, v in pairs(tbl) do
					if type(v) == "table" then
						parts[#parts + 1] = tostring(k) .. ":" .. smallMapSig(v)
					elseif v ~= nil and v ~= false then
						parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
					end
				end
				table.sort(parts)
				return table.concat(parts, ",")
			end
			local trainerReqSig = table.concat({
				smallMapSig(db.trainerCosts),
				smallMapSig(db.trainerReqs and db.trainerReqs[profKey]),
				smallMapSig(db.trainerReqsByName),
				smallMapSig(db.liveThresholds),
				smallMapSig(subCraftOverrides),
			}, ";")
			local knownSigAcc, knownSigCnt = 0, 0
			for idx, rec in ipairs(raw) do
				if MP.IsRecipeKnownByPlayer(rec) then
					knownSigCnt = knownSigCnt + 1
					knownSigAcc = knownSigAcc + (tonumber(rec.s) or idx) * (knownSigCnt % 17 + 1)
				end
			end
			local browseCacheKey = table.concat({
				tostring(profKey),
				tostring(fromSkill),
				tostring(effCharLv),
				tostring(filterKnownOnly),
				tostring(priceRev),
				tostring(ns.GetItemMarketPrice),
				tostring(ns.GetNumListed),
				tostring(liveFavorUnit),
				tostring(db.goalMode or "smart"),
				tostring(db.sellDays or 3),
				tostring(db.includeVendorSell ~= false),
				tostring(db.useDisenchantRecovery == true),
				tostring(applyAHCut),
				tostring(smartFilterColdItems),
				tostring(subCraftMode),
				tostring(playerFaction),
				tostring(playerKnowsEnchanting),
				tostring(legacy.overtime),
				tostring(legacy.bartering),
				tostring(legacy.vendorMult),
				tostring(legacy.favorYieldMult),
				tostring(knownSigCnt) .. ":" .. tostring(knownSigAcc),
				trainerReqSig,
				brTextHex, brSecHex, brMutedHex, brGreenHex, brBlueHex, brOrangeHex, brRedHex,
			}, "|")

			local allRows
			if papp._browseCache and papp._browseCache.key == browseCacheKey then
				allRows = papp._browseCache.rows
			else
				local dummyCtx = {
					db = db,
					profKey = profKey,
					mns = ns,
					legacy = legacy,
					charLevel = effCharLv,
					includeLockedForBrowse = true,
					allowCooldowns = true,
					allowedSources = { start = true, trainer = true, vendor = true, ah = true, camp = true, quest = true, gather = true },
					goalMode = db.goalMode or "smart",
					sellDays = db.sellDays or 3,
					applyAHCut = applyAHCut,
					smartFilterColdItems = smartFilterColdItems,
					includeVendorSell = (db.includeVendorSell ~= false),
					useDisenchantRecovery = (db.useDisenchantRecovery == true),
					playerKnowsEnchanting = playerKnowsEnchanting,
					subCraftMode = subCraftMode,
					subCraftOverrides = subCraftOverrides,
					trainerCosts = db.trainerCosts or {},
					playerFaction = playerFaction,
					favorUnitPrice = liveFavorUnit,
					standingID = 8,
					itemOptionCache = {},
					subEvCache = {},
				}
				allRows = {}
				for _, rec in ipairs(raw) do
					local known = MP.IsRecipeKnownByPlayer(rec)
					local isIntrinsicKnown = known or (rec.src == "start") or (rec.src == "gather")
					if (not filterKnownOnly) or isIntrinsicKnown then
						local effReq, effRlv = MP.GetEffectiveRecipeReqs(rec, db, profKey)
						local ev = MP.EvaluateRecipeForSolver(rec, dummyCtx)
						local fallbackFav = (rec.src == "camp") and ((rec.fav and rec.fav > 0) and rec.fav or 30) or nil
						local srcDisplay = (ev and ev.sourceDisplay) or (ev and ev.unlockLabel)
						if not srcDisplay then
							if rec.src == "camp" then
								srcDisplay = string.format("Vendor (%d Favor)", fallbackFav)
							elseif rec.src == "vendor" then
								local vEff
								if ns.GetRecipeVendorBuyPrice then
									vEff = ns.GetRecipeVendorBuyPrice(rec.ri, rec.rbuy, legacy.bartering)
								end
								if not vEff and rec.rbuy and rec.rbuy > 0 then
									vEff = math.floor(rec.rbuy * (legacy.vendorMult or 1) + 0.5)
								end
								local vCoin = (vEff and vEff > 0) and formatMoney(vEff, true) or nil
								srcDisplay = vCoin and ("Vendor (" .. vCoin .. ")") or "Vendor Scroll"
							elseif rec.src == "trainer" then srcDisplay = "Trainer"
							elseif rec.src == "ah" then srcDisplay = "AH Scroll"
							elseif rec.src == "quest" then srcDisplay = "Quest"
							elseif rec.src == "start" then srcDisplay = "Starter"
							elseif rec.src == "gather" then srcDisplay = "World Veins"
							else srcDisplay = rec.src or "Drop" end
						end
						local effReqT, effYT, effGT, effGrT = MP.GetEffectiveThresholds(rec, db)
						effReq = effReqT
						local p = MP.GetSkillUpChance(rec, fromSkill, legacy.overtime, effReq, db)
						local col = MP.GetSkillColor(rec, fromSkill, effReq, db)
						local colHex = (col == "orange" and ("|cff" .. brOrangeHex)) or (col == "yellow" and ("|cff" .. brSecHex)) or (col == "green" and ("|cff" .. brGreenHex)) or ("|cff" .. brMutedHex)
						local statusStr, statusSort
						if isIntrinsicKnown then statusStr, statusSort = "|cff" .. brGreenHex .. "Known|r", 1
						elseif effRlv > effCharLv then statusStr, statusSort = "|cff" .. brOrangeHex .. "Char Lv " .. tostring(effRlv) .. "|r", 4
						elseif fromSkill < effReq then statusStr, statusSort = "|cff" .. brRedHex .. "Skill " .. tostring(effReq) .. "|r", 3
						elseif (rec.spec or 0) > 0 then statusStr, statusSort = "|cff" .. brBlueHex .. "Spec|r", 2
						else statusStr, statusSort = "|cff" .. brSecHex .. "Available|r", 2 end
						local reqStr = (effRlv > 1) and string.format("%d |cff%sL%d|r", effReq, brMutedHex, effRlv) or tostring(effReq)
						local craftCost = ev and ev.grossPerCraft or nil
						local resale1, resaleIsAH, resaleIsCustom = nil, false, false
						local ahVal1, vendVal1, sellChan = nil, nil, "-"
						local hasOut = (not rec.ench) and ((rec.i or 0) > 0)
						local rowUnlisted = (ev and hasOut and ev.isUnlisted) and true or false
						if ev and hasOut then
							local units1 = math.max(1, math.floor(ev.yieldPerCraft + 0.5))
							local rawVend = (ev.vendorUnit and ev.vendorUnit > 0) and (units1 * ev.vendorUnit) or nil
							vendVal1 = rawVend
							local vFloor = (db.includeVendorSell ~= false) and (rawVend or 0) or 0
							local deVal1 = (db.useDisenchantRecovery == true and ev.deNetUnit and ev.deNetUnit > 0) and (units1 * ev.deNetUnit) or 0
							local floorVal = vFloor
							local floorChan = "V"
							if deVal1 > floorVal then
								floorVal = deVal1
								floorChan = "DE"
							end
							local hasAHPrice = ev.canAH and ev.ahGrossUnit and (not ev.isUnlisted or ev.isCustomPrice)
							if hasAHPrice then
								local ahPer = (db.goalMode == "ah_max") and (ev.afterCutUnit or ev.ahNetUnit or 0) or (ev.ahNetUnit or 0)
								ahVal1 = units1 * ahPer
								resaleIsCustom = (ev.isCustomPrice == true)
							end
							if db.goalMode == "cheapest" or not ev.canAH then
								if floorVal > 0 then
									resale1, resaleIsAH, sellChan = floorVal, false, floorChan
								end
							elseif not hasAHPrice then
								if floorVal > 0 then
									resale1, resaleIsAH, sellChan = floorVal, false, floorChan
								end
							elseif db.goalMode == "ah_max" then
								if floorVal > 0 and ahVal1 <= floorVal then
									resale1, resaleIsAH, sellChan = floorVal, false, floorChan
								else
									resale1, resaleIsAH, sellChan = ahVal1, true, "AH"
								end
							else
								if (ev.hotnessCap or 0) > 0 and ahVal1 > floorVal then
									resale1, resaleIsAH, sellChan = ahVal1, true, "AH"
								elseif floorVal > 0 then
									resale1, resaleIsAH, sellChan = floorVal, false, floorChan
								end
							end
						end
						allRows[#allRows + 1] = {
							prof = profKey,
							spellID = rec.s,
							itemID = rec.i or 0,
							req = effReq,
							rlv = effRlv,
							reqStr = reqStr,
							gr = effGrT or rec.gr or 0,
							thresholds = string.format("|cff%s%d|r / |cff%s%d|r / |cff%s%d|r", brOrangeHex, effYT or rec.y or 0, brGreenHex, effGT or rec.g or 0, brMutedHex, effGrT or rec.gr or 0),
							name = rec.n,
							srcType = rec.src,
							known = isIntrinsicKnown,
							favorTokens = (ev and ev.favorTokens) or fallbackFav,
							favorUnitPrice = liveFavorUnit,
							sourceLabel = srcDisplay,
							chanceAtFrom = p,
							chanceStr = p > 0 and string.format("%s%d%%|r", colHex, math.floor(p * 100 + 0.5)) or ("|cff" .. brMutedHex .. "0%|r"),
							unlockCost = (ev and ev.baseUnlockCost) or 0,
							craftCost = craftCost,
							ahUnit = ahVal1,
							vendorUnit = vendVal1,
							sellChannel = sellChan,
							resaleUnit = resale1,
							resaleIsAH = resaleIsAH,
							resaleIsCustom = resaleIsCustom,
							isUnlisted = rowUnlisted,
							heatBadge = (ev and hasOut and ev.demand) and ev.demand.heatBadge or nil,
							demandScore = (ev and hasOut and ev.demand) and ev.demand.demandScore or nil,
							dailySold = ev and ev.dailySold or nil,
							profitCraft = (craftCost and resale1 ~= nil) and (resale1 - craftCost) or nil,
							status = statusStr,
							statusSort = statusSort,
							ev = ev,
							_searchText = (tostring(rec.n or "") .. "\0" .. tostring(rec.src or "") .. "\0" .. tostring(srcDisplay or "")):lower(),
						}
					end
				end
				papp._browseCache = { key = browseCacheKey, rows = allRows }
			end

			local bRows = {}
			if search == "" then
				for i = 1, #allRows do
					bRows[i] = allRows[i]
				end
			else
				for i = 1, #allRows do
					local row = allRows[i]
					if row._searchText:find(search, 1, true) then
						bRows[#bRows + 1] = row
					end
				end
			end
			local srt = papp.sortState.browse
			sortProfRows(bRows, srt.col, srt.asc, "req", { name = true, sourceLabel = true, sellChannel = true })
			papp.lastBrowseRows = bRows
			papp.ui.browseTable.updateHeaders()
			papp.ui.browseTable.setRows(bRows)
		end
	end

	function papp.resetFilters()
		papp._browseCache = nil
		local db = getProfDB()
		local tab = mmApp.activeTab
		if mmApp.resetSubCraftMode then mmApp.resetSubCraftMode() end
		if tab == "prof_browse" then
			db.browseTier, db.browseProf, db.browseOwnedOnly, db.browseSearch = "all", "all", false, ""
			papp.browseTier, papp.browseProf, papp.browseOwnedOnly, papp.browseSearch = "all", "all", false, ""
			mmApp.resetSearchBox(mmApp.ui.searchBox)
			return mmApp.refresh()
		end
		if tab == "prof_shop" then
			db.shopSearch = ""
			papp.shopSearch = ""
			mmApp.resetSearchBox(mmApp.ui.searchBox)
			setShoppingGroupMode("consolidated")
			return
		end

		local profKey = db.selectedProf or "alchemy"
		if papp.isViewLocked(profKey) then
			papp.setViewLocked(profKey, false, true)
		end
		local from, to = setProfBounds(profKey, defaultProfBounds(profKey))
		db.goalMode, db.recipeFilter, db.sellDays = "smart", "trainer_vendor", 3
		db.charLevelMode, db.overtimeMode, db.useOwned = "auto", "auto", false
		db.useDisenchantRecovery = false
		db.knownRecipesOnly, db.subCraftMode = false, "smart"
		if MerchantMasterDB then
			MerchantMasterDB.knownRecipesOnly = false
			MerchantMasterDB.unlockFilter = "all"
		end
		mmApp.resetSearchBox(mmApp.ui.searchBox)
		fromBox:SetText(tostring(from))
		toBox:SetText(tostring(to))
		fromBox:ClearFocus()
		toBox:ClearFocus()
		goalBtn:SetText(findOptLabel(GOAL_OPTIONS, "smart"))
		if papp.ui.goalSeg then papp.ui.goalSeg:SetActive("smart", true) end
		if papp.ui.browseGoalSeg then papp.ui.browseGoalSeg:SetActive("smart", true) end
		recFilterBtn:SetText(findOptLabel(RECIPE_FILTER_OPTIONS, "trainer_vendor"))
		horizonBtn:SetText(findOptLabel(SELL_DAYS_OPTIONS, 3))
		charLvBtn:SetText(findOptLabel(CHAR_LEVEL_OPTIONS, "auto"))
		overtimeBtn:SetText(findOptLabel(OVERTIME_OPTIONS, "auto"))
		useOwnedChk:SetChecked(false)
		useDEChk:SetChecked(false)
		if mmApp.ui.knownRecipesCheck then mmApp.ui.knownRecipesCheck:SetChecked(false) end
		if mmApp.ui.scopeSeg then mmApp.ui.scopeSeg:SetActive("all", true) end
		papp.activeBracket = "all"
		if papp._paintPillState then
			for _, button in ipairs(papp.ui.bracketPills) do
				papp._paintPillState(button, button.bracket.key == "all", false)
			end
		end
		mmApp.refresh()
	end
	local profResetFiltersBtn = mmApp.ui.makeSidebarBtn("Reset Filters", false, papp.resetFilters)
	papp.ui.profResetFiltersBtn = profResetFiltersBtn
	local profControls = {
		profResetFiltersBtn,
		scanRow,
		boundsRow,
		charLvBtn,
		overtimeBtn,
		goalBtn,
		recFilterBtn,
		horizonBtn,
		useOwnedChk,
		useDEChk,
		mmApp.ui.subCraftBtn,
	}

	function papp.GetSidebarControls() return profControls end

	local function applyProfTheme()
		local pal = getProfPalette()
		local bg = (pal and pal.cardBg) or { 0.17, 0.17, 0.18, 1 }
		local function updateGlass(f)
			if not f or not f._mmGlass then return end
			if f._mmGlass.UpdateTheme then
				f._mmGlass:UpdateTheme()
			elseif f._mmGlass.SetFill then
				f._mmGlass:SetFill(bg)
			else
				if f._mmGlass.fill and f._mmGlass.fill.SetColor then f._mmGlass.fill:SetColor(bg[1], bg[2], bg[3], bg[4] or 1) end
			end
		end
		for _, card in ipairs(papp.ui.kpiCards or {}) do
			updateGlass(card)
			if card.lbl and card.lbl.SetTextColor and pal and pal.textMuted then
				card.lbl:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
			end
			if card.val and card.val.SetTextColor and pal and pal.text then
				card.val:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
			end
			if card.unit and card.unit.SetTextColor and pal and pal.textMuted then
				card.unit:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
			end
			if card.sub and card.sub.SetTextColor and pal and pal.textSecondary then
				card.sub:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
			end
			if card.icon and card.icon.SetVertexColor and pal and pal.textMuted then
				card.icon:SetVertexColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
			end
		end
		updateGlass(papp.ui.pathCard)
		updateGlass(papp.ui.shopCard)
		updateGlass(papp.ui.browseView)
		if papp.ui.pathHeadSep and pal and pal.separator then
			papp.ui.pathHeadSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], pal.separator[4] or 0.45)
		end
		if papp.ui.shopHeadSep and pal and pal.separator then
			papp.ui.shopHeadSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], pal.separator[4] or 0.45)
		end
		if papp.ui.pathHeadTitle and papp.ui.pathHeadTitle.SetTextColor and pal and pal.text then
			papp.ui.pathHeadTitle:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
		end
		if papp.ui.shopHdrFs and papp.ui.shopHdrFs.SetTextColor and pal and pal.text then
			papp.ui.shopHdrFs:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
		end
		if fromLbl and fromLbl.SetTextColor and pal and pal.textSecondary then
			fromLbl:SetTextColor(pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1)
		end
		if arrowLbl and arrowLbl.SetTextColor and pal and pal.textMuted then
			arrowLbl:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1)
		end
		for _, eb in ipairs({ fromBox, toBox }) do
			if eb and eb.SetTextColor and pal and pal.text then
				eb:SetTextColor(pal.text[1], pal.text[2], pal.text[3], 1)
			end
		end
		local curProf = getProfDB().selectedProf or "alchemy"
		local curFrom = getProfBounds(curProf)
		if papp._paintPillState then
			for _, pp in ipairs(papp.ui.profPills or {}) do
				papp._paintPillState(pp, pp.profKey == curProf, false)
			end
			for _, bp in ipairs(papp.ui.bracketPills or {}) do
				local bd = bp.bracket
				papp._paintPillState(bp, papp.activeBracket == bd.key, (bd.key ~= "all") and (curFrom >= bd.hi))
			end
		end
		if papp._updateSkillMeter and papp.ui.kpiCards and papp.ui.kpiCards[1] then
			papp._updateSkillMeter(papp.ui.kpiCards[1], curFrom, pal)
		end
		for _, t in ipairs({ papp.ui.pathTable, papp.ui.shopTable, papp.ui.browseTable }) do
			if t and t.updateHeaders then t.updateHeaders() end
		end
		if mmApp.panel and mmApp.panel:IsShown() and type(mmApp.activeTab) == "string" and mmApp.activeTab:sub(1, 5) == "prof_" then
			mmApp.refresh()
		end
	end
	if Theme and Theme.OnModeChanged then
		Theme.OnModeChanged(applyProfTheme)
	end
	applyProfTheme()

	_G.MerchantMasterAPI.RegisterProfessor({
		layout = function()
			if papp.layoutKpis then papp.layoutKpis() end
			if papp.layoutDetailPane then papp.layoutDetailPane() end
		end,
		controls = profControls,
		sidebarControls = papp.GetSidebarControls,
		resetFilters = papp.resetFilters,
		onProfSelected = function(pk)
			local f, t = getProfBounds(pk)
			if papp.ui.fromBox then papp.ui.fromBox:SetText(tostring(f)) end
			if papp.ui.toBox then papp.ui.toBox:SetText(tostring(t)) end
		end,
		refresh = refreshProfessor,
		repaintShoppingQty = papp.RepaintShoppingQty,
		setShiftMode = papp.SetShiftMode,
	})

	-- Live WoW Event Scanner (Professions, Known Recipes & Trainer Spell Fees/SkillReqs)
	cacheOpenTradeSkills = function()
		if ns.IsForeignTradeSkill and ns.IsForeignTradeSkill() then return false end
		local function readable(v)
			return not ((_G.issecretvalue and _G.issecretvalue(v)) or (type(v) == "table" and _G.issecrettable and _G.issecrettable(v)))
		end
		local profMap = ns.GetPlayerProfessions and ns.GetPlayerProfessions() or {}
		local hasAnyProf = next(profMap) ~= nil
		local db, ck = getProfDB(), MP.GetCharKey()
		db.knownSpells[ck] = db.knownSpells[ck] or {}
		local changed = false
		local usedModernAPI = false
		if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo then
			local openPkey, winRank = nil, nil
			if C_TradeSkillUI.GetBaseProfessionInfo then
				local pok, pinfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
				if pok and readable(pinfo) and type(pinfo) == "table" then
					openPkey = (readable(pinfo.professionID) and pinfo.professionID and ns.PROF_BY_SKILLLINE[pinfo.professionID])
						or (readable(pinfo.professionName) and matchProfKeyByName(pinfo.professionName))
					winRank = (readable(pinfo.skillLevel) and type(pinfo.skillLevel) == "number" and pinfo.skillLevel > 0) and pinfo.skillLevel or nil
				end
			end
			if openPkey and hasAnyProf and (not profMap[openPkey] or (winRank and winRank > profMap[openPkey] + 15)) then
				return false
			end
			local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
			if ok and readable(ids) and type(ids) == "table" and #ids > 0 then
				local infos, anyLearnedFlag = {}, false
				for _, id in ipairs(ids) do
					if readable(id) then
						local iok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
						if iok and readable(info) and type(info) == "table" then
							infos[id] = info
							if readable(info.learned) and info.learned ~= nil then
								anyLearnedFlag = true
							end
						end
					end
				end
				if anyLearnedFlag then
					usedModernAPI = true
					for _, id in ipairs(ids) do
						local info = infos[id]
						if info and readable(info.learned) then
							if info.learned == true then
								if not db.knownSpells[ck][id] then
									db.knownSpells[ck][id] = true
									changed = true
								end
							elseif info.learned == false then
								if db.knownSpells[ck][id] ~= nil then
									db.knownSpells[ck][id] = nil
									changed = true
								end
							end
						end
						if info and winRank and winRank > 0 and readable(info.difficulty) and type(info.difficulty) == "string" then
							if MP.RecordLiveRecipeColor and MP.RecordLiveRecipeColor(id, winRank, info.difficulty, nil, db) then
								changed = true
							end
						end
					end
				end
			end
		end
		if not usedModernAPI and GetNumTradeSkills and GetTradeSkillInfo then
			if not ns._recipeByProfAndName then
				local lookup = { all = {} }
				for _, pk in ipairs(MP.PROF_ORDER) do
					lookup[pk] = {}
					for _, rec in ipairs(MP.RECIPES[pk] or {}) do
						local name = rec.n:lower()
						lookup[pk][name] = lookup[pk][name] or {}
						lookup.all[name] = lookup.all[name] or {}
						table.insert(lookup[pk][name], rec)
						table.insert(lookup.all[name], rec)
					end
				end
				ns._recipeByProfAndName = lookup
			end
			local num = GetNumTradeSkills()
			if not readable(num) or type(num) ~= "number" or num <= 0 then return changed end
			local line, winRank
			if GetTradeSkillLine then line, winRank = GetTradeSkillLine() end
			local pk = readable(line) and matchProfKeyByName(line) or nil
			if hasAnyProf and (not pk or not profMap[pk] or (readable(winRank) and type(winRank) == "number" and winRank > 0 and winRank > profMap[pk] + 15)) then
				return changed
			end
			local names = ns._recipeByProfAndName[pk or "all"] or ns._recipeByProfAndName.all
			local validRank = readable(winRank) and type(winRank) == "number" and winRank > 0
			for i = 1, num do
				local sName, sType = GetTradeSkillInfo(i)
				if readable(sName) and readable(sType) and sType ~= "header" and type(sName) == "string" then
					for _, rec in ipairs(names[sName:lower()] or {}) do
						if not db.knownSpells[ck][rec.s] then db.knownSpells[ck][rec.s] = true; changed = true end
						if validRank and MP.RecordLiveRecipeColor and MP.RecordLiveRecipeColor(rec.s, winRank, sType, nil, db) then
							changed = true
						end
					end
				end
			end
		end
		return changed
	end
	papp.cacheOpenTradeSkills = cacheOpenTradeSkills

	ns.TrainerServices.Initialize(getProfDB)
	cacheOpenTrainerCosts = ns.TrainerServices.Scan

	local profEvents = CreateFrame("Frame")
	for _, ev in ipairs({
		"PLAYER_LOGIN",
		"PLAYER_LEVEL_UP",
		"SKILL_LINES_CHANGED",
		"TRADE_SKILL_SHOW",
		"TRADE_SKILL_UPDATE",
		"TRADE_SKILL_CLOSE",
		"CRAFT_SHOW",
		"CRAFT_CLOSE",
		"TRAINER_SHOW",
		"TRAINER_UPDATE",
		"TRAIT_CONFIG_UPDATED",
		"NEW_RECIPE_LEARNED",
	}) do
		pcall(profEvents.RegisterEvent, profEvents, ev)
	end

	local function isPlayerCastingCraft()
		if UnitCastingInfo and UnitCastingInfo("player") then return true end
		if UnitChannelInfo and UnitChannelInfo("player") then return true end
		return false
	end

	local function hasOpenProfRecipes()
		if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
			local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
			if ok and type(ids) == "table" and #ids > 0 then return true end
		end
		if GetNumTradeSkills then
			local ok, n = pcall(GetNumTradeSkills)
			if ok and type(n) == "number" and n > 0 then return true end
		end
		return false
	end

	local function scheduleProfRefresh(reason)
		if not (mmApp.panel and mmApp.panel:IsShown() and type(mmApp.activeTab) == "string" and mmApp.activeTab:sub(1, 5) == "prof_") then
			return
		end
		if mmApp.scheduleRecipeRefresh then
			mmApp.scheduleRecipeRefresh(reason or "professor")
		elseif mmApp.refresh then
			mmApp.refresh()
		end
	end

	profEvents:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			getProfDB()
			MP.InitPricingBridge()
			app._lastSkillEventProfs = ns.GetPlayerProfessions and ns.GetPlayerProfessions() or {}
		elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
			papp._tsSessionScanned = false
		elseif event == "TRADE_SKILL_UPDATE" then
			if isPlayerCastingCraft() then return end
			if papp._tsSessionScanned == true then return end
			local now = GetTime and GetTime() or 0
			if mmApp and mmApp._lastCraftEventTime and now > 0 and (now - mmApp._lastCraftEventTime) < 2.5 then return end
			if now > 0 and (now - (papp._lastTradeSkillCacheTime or 0)) < 3.0 then return end
			papp._lastTradeSkillCacheTime = now
			local changed = cacheOpenTradeSkills()
			if hasOpenProfRecipes() then papp._tsSessionScanned = true end
			if changed then
				app.invalidateRecipeStats("known")
				scheduleProfRefresh("professor")
			end
		elseif event == "TRADE_SKILL_SHOW" or event == "NEW_RECIPE_LEARNED" then
			local changed = cacheOpenTradeSkills()
			if hasOpenProfRecipes() then papp._tsSessionScanned = true end
			if changed or event == "NEW_RECIPE_LEARNED" then
				app.invalidateRecipeStats("known")
				scheduleProfRefresh("professor")
			end
		elseif event == "TRAINER_SHOW" then
			cacheOpenTrainerCosts(true)
			app.invalidateRecipeStats("trainer")
			scheduleProfRefresh("professor")
		elseif event == "TRAINER_UPDATE" then
			cacheOpenTrainerCosts(false)
			app.invalidateRecipeStats("trainer")
			scheduleProfRefresh("professor")
		elseif event == "SKILL_LINES_CHANGED" then
			local profMap = ns.GetPlayerProfessions and ns.GetPlayerProfessions() or {}
			local prev = app._lastSkillEventProfs or app._lastPlayerProfMap
			local keysChanged = (prev == nil and next(profMap) ~= nil)
				or (prev ~= nil and not sameProfKeys(prev, profMap))
			local ranksChanged = keysChanged or (prev ~= nil and not sameCounts(prev, profMap))
			app._lastSkillEventProfs = profMap
			app._lastPlayerProfMap = profMap
			if ranksChanged then
				local invReason = keysChanged and "professions" or "skills"
				app.invalidateRecipeStats(invReason)
				if not app.recipeInvalidationBound then
					if app.superListProvider and app.superListProvider.Invalidate then
						app.superListProvider.Invalidate(invReason)
					end
					if app.vendorCrafterProvider and app.vendorCrafterProvider.Invalidate then
						app.vendorCrafterProvider.Invalidate(invReason)
					end
				end
				if keysChanged and app.warmSuperListCache
					and not (mmApp.panel and mmApp.panel:IsShown() and mmApp.activeTab == "recipes") then
					app.warmSuperListCache(0.05)
				end
				scheduleProfRefresh("skills")
			end
		else
			app.invalidateRecipeStats("skills")
			scheduleProfRefresh("professor")
		end
	end)

	local function openProfessorTab(subTab)
		local target = "prof_path"
		if subTab == "shop" or subTab == "prof_shop" then target = "prof_shop"
		elseif subTab == "browse" or subTab == "prof_browse" then target = "prof_browse"
		elseif subTab == "path" or subTab == "prof_path" then target = "prof_path" end
		mmApp.togglePanel(target)
	end

	SLASH_MERCHANTPROFESSOR1 = "/mp"
	SLASH_MERCHANTPROFESSOR2 = "/prof"
	SLASH_MERCHANTPROFESSOR3 = "/professor"
	SLASH_MERCHANTPROFESSOR4 = "/merchantprofessor"
	SlashCmdList.MERCHANTPROFESSOR = function(msg)
		msg = (msg or ""):lower():match("^%s*(.-)%s*$")
		if msg == "shop" or msg == "shopping" or msg == "list" then
			openProfessorTab("prof_shop")
		elseif msg == "bylevel" or msg == "by_level" then
			if papp.setShoppingGroupMode then papp.setShoppingGroupMode("by_level") end
			openProfessorTab("prof_shop")
		elseif msg == "consolidated" then
			if papp.setShoppingGroupMode then papp.setShoppingGroupMode("consolidated") end
			openProfessorTab("prof_shop")
		elseif msg == "browse" or msg == "recipes" then
			openProfessorTab("prof_browse")
		elseif msg == "known" or msg == "knownrecipes" then
			if MerchantMasterDB then
				local on = not MerchantMasterDB.knownRecipesOnly
				MerchantMasterDB.knownRecipesOnly = on
				MerchantMasterDB.unlockFilter = on and "known" or "all"
				local d = getProfDB()
				d.recipeFilter = on and "known_only" or "trainer_vendor"
				profSay("Known Recipes Only: " .. (on and "ON (showing what you can do right now)" or "OFF (showing full potential)"))
			end
			openProfessorTab("prof_path")
		elseif msg == "overtime" or msg == "ot" or msg == "legacy" then
			local leg = MP.GetEffectiveLegacy(getProfDB())
			profSay(string.format("Working Overtime active in solver: %d/5 (+%d%% skill-up chance).", leg.overtime, leg.overtime * 4))
			openProfessorTab("prof_path")
		elseif msg == "options" or msg == "config" or msg == "settings" then
			if _G.MerchantMasterAPI and _G.MerchantMasterAPI.OpenOptions then _G.MerchantMasterAPI.OpenOptions() end
		elseif msg == "scan" then
			local live = MP.ScanPlayerProfessions()
			local pk = getProfDB().selectedProf
			if live[pk] and live[pk].learned then
				setProfBounds(pk, math.min(299, live[pk].rank), 300)
			end
			openProfessorTab("prof_path")
		else
			for _, pk in ipairs(MP.PROF_ORDER) do
				if msg == pk or MP.PROFESSIONS[pk].name:lower() == msg then
					getProfDB().selectedProf = pk
					if MerchantMasterDB then MerchantMasterDB.profFilter = pk end
					openProfessorTab("prof_path")
					return
				end
			end
			if mmApp.panel and mmApp.panel:IsShown() and type(mmApp.activeTab) == "string" and mmApp.activeTab:sub(1, 5) == "prof_" then
				mmApp.panel:Hide()
			else
				openProfessorTab(getProfDB().activeTab or "prof_path")
			end
		end
	end

	_G.MerchantProfessorAPI = {
		MP = MP,
		TogglePanel = function(tab)
			if tab then
				openProfessorTab(tab)
			elseif mmApp.panel and mmApp.panel:IsShown() and type(mmApp.activeTab) == "string" and mmApp.activeTab:sub(1, 5) == "prof_" then
				mmApp.panel:Hide()
			else
				openProfessorTab(getProfDB().activeTab or "prof_path")
			end
		end,
		SelectProfession = function(pk)
			if MP.PROFESSIONS[pk] then
				getProfDB().selectedProf = pk
				if MerchantMasterDB then MerchantMasterDB.profFilter = pk end
				openProfessorTab("prof_path")
			end
		end,
		SolveProfessionPath = MP.SolveProfessionPath,
		CompareOvertimeForProfession = MP.CompareOvertimeForProfession,
		BuildAllProfessionsOvertimeMatrix = MP.BuildAllProfessionsOvertimeMatrix,
	}
end)() end
