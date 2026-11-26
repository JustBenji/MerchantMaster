local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
_G.MerchantMasterAnalytics = ns
local unpack = unpack or table.unpack
local function H()
    return host
end

local Chart = {}
ns.Chart = Chart

local APPLE_ASSET = "Interface\\AddOns\\" .. tostring(addonName or "MerchantMaster") .. "\\Assets\\apple\\"
local LINE_SOFT_TEX = APPLE_ASSET .. "line_soft.tga"

local function applySmoothLine(line, thickness, r, g, b, a)
    line:SetThickness(thickness)
    if line.SetTexture and line.SetVertexColor then
        line:SetTexture(LINE_SOFT_TEX)
        line:SetVertexColor(r, g, b, a or 1)
    else
        line:SetColorTexture(r, g, b, a or 1)
    end
end

local FALLBACK_PALETTES = {
    dark = {
        mode = "dark",
        cardBg = { 0.173, 0.173, 0.180, 1.0 },
        cardAltBg = { 0.110, 0.110, 0.118, 1.0 },
        pillTrack = { 1.0, 1.0, 1.0, 0.08 },
        border = { 1.0, 1.0, 1.0, 0.14 },
        specular = { 1.0, 1.0, 1.0, 0.24 },
        separator = { 0.329, 0.329, 0.345, 0.48 },
        text = { 1.0, 1.0, 1.0, 1.0 },
        textSecondary = { 0.922, 0.922, 0.961, 0.62 },
        textMuted = { 0.596, 0.596, 0.616, 1.0 },
        accentBlue = { 0.000, 0.569, 1.000, 1.0 },
        accentGreen = { 0.188, 0.820, 0.345, 1.0 },
        accentOrange = { 1.000, 0.573, 0.188, 1.0 },
        accentRed = { 1.000, 0.271, 0.227, 1.0 },
        accentPurple = { 0.749, 0.353, 0.949, 1.0 },
    },
    light = {
        mode = "light",
        cardBg = { 1.0, 1.0, 1.0, 1.0 },
        cardAltBg = { 0.949, 0.949, 0.969, 1.0 },
        pillTrack = { 0.0, 0.0, 0.0, 0.06 },
        border = { 0.0, 0.0, 0.0, 0.12 },
        specular = { 1.0, 1.0, 1.0, 0.75 },
        separator = { 0.235, 0.235, 0.263, 0.24 },
        text = { 0.0, 0.0, 0.0, 1.0 },
        textSecondary = { 0.235, 0.235, 0.263, 0.76 },
        textMuted = { 0.431, 0.431, 0.451, 1.0 },
        accentBlue = { 0.000, 0.533, 1.000, 1.0 },
        accentGreen = { 0.000, 0.478, 0.169, 1.0 },
        accentOrange = { 0.702, 0.290, 0.000, 1.0 },
        accentRed = { 0.839, 0.141, 0.161, 1.0 },
        accentPurple = { 0.686, 0.322, 0.871, 1.0 },
    },
}

local function getPalette()
    local h = H()
    local theme = h and h.Theme
    local mode = (theme and theme.GetMode and theme.GetMode()) or "dark"
    if mode ~= "light" then mode = "dark" end
    local pal = (theme and theme.GetActivePalette and theme.GetActivePalette()) or (theme and theme.PALETTES and theme.PALETTES[mode])
    local fb = FALLBACK_PALETTES[mode]
    if not pal then return fb, mode end
    return {
        mode = mode,
        cardBg = pal.cardBg or fb.cardBg,
        cardAltBg = pal.cardAltBg or fb.cardAltBg,
        pillTrack = pal.pillTrack or fb.pillTrack,
        border = pal.border or fb.border,
        specular = pal.specular or fb.specular,
        separator = pal.separator or fb.separator,
        text = pal.text or fb.text,
        textSecondary = pal.textSecondary or fb.textSecondary,
        textMuted = pal.textMuted or fb.textMuted,
        accentBlue = pal.accentBlue or fb.accentBlue,
        accentGreen = pal.accentGreen or fb.accentGreen,
        accentOrange = pal.accentOrange or fb.accentOrange,
        accentRed = pal.accentRed or fb.accentRed,
        accentPurple = pal.accentPurple or fb.accentPurple,
    }, mode
end

function Chart.SeriesColors()
    local pal = getPalette()
    return {
        blue = pal.accentBlue,
        green = pal.accentGreen,
        orange = pal.accentOrange,
        purple = pal.accentPurple,
        red = pal.accentRed,
    }
end

local function assetPath(name)
    local h = H()
    local assets = h and h.Theme and h.Theme.ASSETS
    if assets and assets[name] then return assets[name] end
    return APPLE_ASSET .. name
end

local function applyFont(fs, size, weight, flags)
    if type(fs) ~= "table" then return end
    local h = H()
    local theme = h and h.Theme
    if theme and theme.ApplyFont then
        theme.ApplyFont(fs, size, weight, flags)
        return
    end
    if fs.SetFont then
        local fonts = theme and theme.FONTS
        local isSemi = (weight == "semibold" or weight == "bold" or weight == "heavy")
        local fallbackFont = (fonts and fonts.fallback) or _G.STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"
        local target = (fonts and (isSemi and fonts.semibold or fonts.regular)) or fallbackFont
        local sz = tonumber(size) or 11
        local fl = flags or ""
        local ok = fs:SetFont(target, sz, fl)
        local loaded = fs.GetFont and select(1, fs:GetFont())
        if ok == false or (ok == nil and loaded ~= target) then
            fs:SetFont(fallbackFont, sz, fl)
        end
    end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
end

local function setFontSize(fs, size, weight)
    applyFont(fs, size, weight or "regular")
end

local function setColor(fs, col, fallbackA)
    if fs and fs.SetTextColor and col then
        fs:SetTextColor(col[1], col[2], col[3], col[4] or fallbackA or 1)
    end
end

local function money(value, signed)
    local h = H()
    if h and h.Theme and h.Theme.FormatMoneyFable then
        return h.Theme.FormatMoneyFable(tonumber(value) or 0, signed == true)
    elseif h and h.Theme and h.Theme.FormatMoneyParts then
        local parts = h.Theme.FormatMoneyParts(tonumber(value) or 0, signed == true, true)
        if type(parts) == "table" and parts.text then return parts.text end
    end
    return h and h.FormatMoneyCompact and h.FormatMoneyCompact(value, signed == true) or tostring(value)
end

local MONTH_NAMES = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function formatAxisMoney(copper, step, pal)
    copper = tonumber(copper) or 0
    local neg = copper < 0
    local absV = math.abs(copper)
    local isLight = pal and pal.mode == "light"
    local gHex = isLight and "9a6700" or "ffd100"
    local sHex = isLight and "5e626a" or "c7c7cc"
    local cHex = isLight and "9c5221" or "e08a5e"
    local sign = neg and "-" or ""
    local g = absV / 10000
    if absV == 0 then
        if (step or 10000) >= 10000 then
            return "0|cff" .. gHex .. "g|r"
        elseif (step or 100) >= 100 then
            return "0|cff" .. sHex .. "s|r"
        end
        return "0|cff" .. cHex .. "c|r"
    end
    if g >= 1000000 then
        if g < 10000000 then
            return sign .. string.format("%.2fM", g / 1000000) .. "|cff" .. gHex .. "g|r"
        end
        return sign .. tostring(math.floor(g / 1000000 + 0.5)) .. "M|cff" .. gHex .. "g|r"
    elseif g >= 1000 then
        if g < 10000 then
            return sign .. string.format("%.2fk", g / 1000) .. "|cff" .. gHex .. "g|r"
        end
        return sign .. tostring(math.floor(g / 1000 + 0.5)) .. "k|cff" .. gHex .. "g|r"
    elseif absV >= 10000 or (step and step >= 10000) then
        return sign .. tostring(math.floor(g + 0.5)) .. "|cff" .. gHex .. "g|r"
    elseif absV >= 100 or (step and step >= 100) then
        return sign .. tostring(math.floor(absV / 100 + 0.5)) .. "|cff" .. sHex .. "s|r"
    end
    return sign .. tostring(math.floor(absV + 0.5)) .. "|cff" .. cHex .. "c|r"
end

local function formatAxisX(raw, longSpan)
    local s = tostring(raw or "")
    local a, b = s:match("^(%d%d%d%d%-%d%d%-%d%d)%s*%-%s*(%d%d%d%d%-%d%d%-%d%d)$")
    if a and b then
        if a == b then return formatAxisX(a, longSpan) end
        return formatAxisX(a, longSpan) .. " - " .. formatAxisX(b, longSpan)
    end
    local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y and m and d then
        local mn = MONTH_NAMES[tonumber(m)] or m
        if longSpan then
            return mn .. " '" .. y:sub(3, 4)
        end
        return mn .. " " .. d
    end
    return s
end

-- TSM-inspired nice-step Y-axis calculation: chooses clean round tick intervals
-- (1, 2, 2.5, 5, 7, 10 * 10^k) so gridlines land on readable numbers like 0g, 7g, 14g, 21g, 28g, 35g.
local function computeNiceYAxis(lo, hi, plotHeight, isMoney)
    if lo == nil or hi == nil then return 0, 1, { 0, 1 }, 1 end
    local maxAbs = math.max(math.abs(lo), math.abs(hi))
    if lo == hi then
        local pad = isMoney and math.max(10000, maxAbs * 0.1) or math.max(1, maxAbs * 0.1)
        lo = lo >= 0 and math.max(0, lo - pad) or (lo - pad)
        hi = hi + pad
        maxAbs = math.max(math.abs(lo), math.abs(hi))
    end
    local maxTicks = math.max(3, math.min(6, math.floor((plotHeight or 140) / 26) + 1))
    local targetIntervals = math.max(2, maxTicks - 1)
    local rawRange = math.max(1e-6, hi - lo)
    local rawStep = rawRange / targetIntervals
    local minUnit = isMoney and (maxAbs >= 10000 and 10000 or (maxAbs >= 100 and 100 or 1)) or 1
    if rawStep < minUnit then rawStep = minUnit end
    local mag = 10 ^ math.floor(math.log10(rawStep))
    local norm = rawStep / mag
    local mult
    if norm <= 1.0 then mult = 1
    elseif norm <= 2.0 then mult = 2
    elseif norm <= 5.0 then mult = 5
    elseif norm <= 7.0 then mult = 7
    else mult = 10 end
    local step = math.max(minUnit, mult * mag)
    local niceLo
    if lo < 0 then
        niceLo = math.floor((lo - step * 0.08) / step) * step
    else
        niceLo = math.floor(lo / step) * step
        if lo < step * 1.5 then niceLo = 0 end
    end
    local niceHi
    if hi <= 0 and lo < 0 then
        niceHi = 0
    else
        niceHi = math.ceil((hi + step * 0.08) / step) * step
    end
    if niceHi <= niceLo then niceHi = niceLo + step end
    local ticks = {}
    local v = niceLo
    local guard = 0
    while v <= niceHi + step * 0.001 and guard < 12 do
        ticks[#ticks + 1] = math.abs(v) < step * 1e-6 and 0 or v
        v = v + step
        guard = guard + 1
    end
    if #ticks < 2 then ticks = { niceLo, niceHi } end
    return niceLo, niceHi, ticks, step
end

local function label(parent, point, x, y, align, size, weight)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint(point, x, y)
    fs:SetJustifyH(align or "LEFT")
    fs:SetWordWrap(false)
    applyFont(fs, size or 11, weight or "regular")
    setColor(fs, getPalette().textSecondary)
    return fs
end

local function hide(pool)
    for _, widget in pairs(pool) do widget:Hide() end
end

local function texture(parent, pool, i)
    if not pool[i] then pool[i] = parent:CreateTexture(nil, "ARTWORK") end
    pool[i]:ClearAllPoints()
    pool[i]:Show()
    return pool[i]
end

local function value(point)
    local v = tonumber(point and point.value)
    if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
    return v
end

local function key(point, i)
    return point.day or point.label or i
end

-- Two extrema per bucket plus endpoints keep spikes without growing frame pools.
local function sample(points)
    if #points <= 60 then return points end
    local out = { points[1] }
    for bucket = 1, 29 do
        local first = 2 + math.floor((bucket - 1) * (#points - 2) / 29)
        local last = 1 + math.floor(bucket * (#points - 2) / 29)
        local lo, hi = first, first
        for i = first + 1, last do
            if value(points[i]) < value(points[lo]) then lo = i end
            if value(points[i]) > value(points[hi]) then hi = i end
        end
        if lo > hi then lo, hi = hi, lo end
        out[#out + 1] = points[lo]
        if hi ~= lo then out[#out + 1] = points[hi] end
    end
    out[#out + 1] = points[#points]
    return out
end

local function applySurface(chart, pal)
    local h = H()
    local theme = h and h.Theme
    if not chart._surfaceInit then
        chart._surfaceInit = true
        if theme and theme.NineApple then
            chart.card = theme.NineApple(chart, "glass_r10", pal.cardBg, false, { noSpecular = true })
        elseif theme and theme.Card then
            chart.card = theme.Card(chart, chart, 10, false, pal.cardBg)
        end
    end
    if chart.card then
        if chart.card.SetFill then chart.card:SetFill(pal.cardBg[1], pal.cardBg[2], pal.cardBg[3], pal.cardBg[4] or 1) end
        if chart.card.SetColors then chart.card:SetColors(pal.cardBg, false) end
        if chart.card.border and chart.card.border.SetShown then chart.card.border:SetShown(false) end
    end
end

local function stylePillButton(btn, pal)
    if not btn._pillInit then
        btn._pillInit = true
        local host = H()
        local theme = host and host.Theme
        if theme and theme.NineApple then
            btn._pillSurface = theme.NineApple(btn, "pill", pal.pillTrack, false, { noSpecular = true })
        else
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(assetPath("pill_fill"))
            btn._pillBg = bg
        end
    end
    local r, g, b, a = unpack(pal.pillTrack)
    if btn._pillSurface then
        btn._pillSurface:SetFill(r, g, b, a)
    elseif btn._pillBg and btn._pillBg.SetVertexColor then
        btn._pillBg:SetVertexColor(r, g, b, a or 0.10)
    end
    setColor(btn.text, pal.text)
end

local function moneyAxisWidth()
    local host = H()
    local theme = host and host.Theme
    return theme and theme.GetPriceDisplayMode and theme.GetPriceDisplayMode() == "full_fixed" and 90 or 64
end

local function base(parent, width, height, opts)
    opts = opts or {}
    local pal = getPalette()
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(width, height)
    applySurface(chart, pal)

    chart.title = label(chart, "TOPLEFT", 16, -15, "LEFT", 15, "semibold")
    setColor(chart.title, pal.text)

    chart.summary = label(chart, "TOPRIGHT", -16, -16, "RIGHT", 12, "regular")
    setColor(chart.summary, pal.textSecondary)
    chart.summary:SetWidth(math.max(1, width * 0.34))
    chart.title:SetPoint("TOPRIGHT", chart.summary, "TOPLEFT", -12, 1)

    local headerSep = chart:CreateTexture(nil, "BORDER")
    headerSep:SetPoint("TOPLEFT", 0, -48)
    headerSep:SetPoint("TOPRIGHT", 0, -48)
    headerSep:SetHeight(1)
    headerSep:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.4) * 0.50)
    chart.headerSep = headerSep

    chart.empty = label(chart, "CENTER", 0, -14, "CENTER", 12, "regular")
    setColor(chart.empty, pal.textMuted)
    chart.empty:SetText("No data for selected period")

    chart.plot = CreateFrame("Frame", nil, chart)
    chart.plot:SetPoint("TOPLEFT", 76, -50)
    chart.plot:SetSize(math.max(1, width - 94), math.max(1, height - 66))
    chart.plotWidth, chart.plotHeight = math.max(1, width - 94), math.max(1, height - 66)

    -- TSM-style deep recessed plot canvas so anti-aliased curves & gridlines pop cleanly
    chart._plotBg = chart.plot:CreateTexture(nil, "BACKGROUND", nil, -2)
    chart._plotBg:SetAllPoints(chart.plot)
    if pal.mode == "light" then
        chart._plotBg:SetColorTexture(0.955, 0.955, 0.968, 0.85)
    else
        chart._plotBg:SetColorTexture(0.055, 0.059, 0.067, 0.78)
    end

    chart.yLabels, chart.xLabels, chart._grids = {}, {}, {}
    for i = 1, 3 do
        local fraction = (i - 1) / 2
        chart.yLabels[i] = label(chart.plot, "BOTTOMLEFT", -8, chart.plotHeight * fraction, "RIGHT", 11, "regular")
        chart.yLabels[i]:ClearAllPoints()
        chart.yLabels[i]:SetPoint("RIGHT", chart.plot, "BOTTOMLEFT", -8, chart.plotHeight * fraction)
        chart.yLabels[i]:SetWidth(64)
        setColor(chart.yLabels[i], pal.textSecondary)
        chart.xLabels[i] = label(chart.plot, "BOTTOMLEFT", chart.plotWidth * fraction, -14,
            i == 1 and "LEFT" or (i == 3 and "RIGHT" or "CENTER"), 11, "regular")
        chart.xLabels[i]:ClearAllPoints()
        chart.xLabels[i]:SetPoint(i == 1 and "LEFT" or (i == 3 and "RIGHT" or "CENTER"),
            chart.plot, "BOTTOMLEFT", chart.plotWidth * fraction, -12)
        chart.xLabels[i]:SetWidth(84)
        setColor(chart.xLabels[i], pal.textSecondary)
        for dash = 0, 15 do
            local grid = chart.plot:CreateTexture(nil, "BACKGROUND")
            grid.dash, grid.fraction = dash, fraction
            grid:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.4) * 0.35)
            chart._grids[#chart._grids + 1] = grid
        end
    end

    chart._lines, chart._glowLines, chart._dots, chart._bars, chart._hits = {}, {}, {}, {}, {}
    chart._yAxisLines, chart._yAxisLabels, chart._xAxisLabels = {}, {}, {}

    -- TSM-style hover crosshair, snapped highlight dot, floating value readout & drag-zoom selection box
    chart._hoverLine = chart.plot:CreateTexture(nil, "OVERLAY")
    chart._hoverLine:SetWidth(1)
    chart._hoverLine:SetColorTexture(pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], 0.85)
    chart._hoverLine:Hide()

    chart._hoverDot = chart.plot:CreateTexture(nil, "OVERLAY")
    chart._hoverDot:SetSize(8, 8)
    chart._hoverDot:SetTexture(assetPath("circle_fill"))
    chart._hoverDot:SetVertexColor(pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], 1)
    chart._hoverDot:Hide()

    chart._hoverText = chart.plot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    applyFont(chart._hoverText, 11, "semibold")
    setColor(chart._hoverText, pal.accentOrange)
    chart._hoverText:SetWordWrap(false)
    chart._hoverText:Hide()

    chart._hoverBar = chart.plot:CreateTexture(nil, "BACKGROUND", nil, -1)
    chart._hoverBar:Hide()

    chart._selectionBox = chart.plot:CreateTexture(nil, "ARTWORK")
    chart._selectionBox:SetColorTexture(pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], 0.18)
    chart._selectionBox:Hide()

    chart.resetZoom = CreateFrame("Button", nil, chart)
    chart.resetZoom:SetSize(78, 22)
    chart.resetZoom:SetPoint("TOPRIGHT", chart, "TOPRIGHT", -14, -54)
    if chart.plot.GetFrameLevel and chart.resetZoom.SetFrameLevel then
        chart.resetZoom:SetFrameLevel(chart.plot:GetFrameLevel() + 5)
    end
    chart.resetZoom.text = chart.resetZoom:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart.resetZoom.text:SetPoint("CENTER", chart.resetZoom, "CENTER", 0, 0)
    setFontSize(chart.resetZoom.text, 11, "regular")
    chart.resetZoom.text:SetText("Reset Zoom")
    stylePillButton(chart.resetZoom, pal)
    chart.resetZoom:SetScript("OnClick", function()
        chart._zoomRange = nil
        if chart._redraw then chart._redraw() end
    end)
    chart.resetZoom:Hide()

    function chart:_hideHover()
        if self._hoverLine then self._hoverLine:Hide() end
        if self._hoverDot then self._hoverDot:Hide() end
        if self._hoverBar then self._hoverBar:Hide() end
        if self._hoverText then self._hoverText:Hide() end
        if self._onHover then self._onHover(nil) end
    end

    function chart:_showHover(x, y, hoverLabel, dotColor, barLeft, barSlotW)
        local p = getPalette()
        local accent = dotColor or p.accentOrange
        if barLeft ~= nil and barSlotW ~= nil and self._hoverBar then
            if self._hoverLine then self._hoverLine:Hide() end
            if self._hoverDot then self._hoverDot:Hide() end
            self._hoverBar:ClearAllPoints()
            self._hoverBar:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", barLeft, 0)
            self._hoverBar:SetSize(math.max(2, barSlotW), math.max(1, self.plotHeight))
            if p.mode == "light" then
                self._hoverBar:SetColorTexture(0, 0, 0, 0.06)
            else
                self._hoverBar:SetColorTexture(1, 1, 1, 0.07)
            end
            self._hoverBar:Show()
        else
            if self._hoverBar then self._hoverBar:Hide() end
            if self._hoverLine then
                self._hoverLine:ClearAllPoints()
                self._hoverLine:SetColorTexture(accent[1], accent[2], accent[3], 0.72)
                self._hoverLine:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x, 0)
                self._hoverLine:SetSize(1, math.max(1, self.plotHeight))
                self._hoverLine:Show()
            end
            if self._hoverDot and y ~= nil then
                self._hoverDot:ClearAllPoints()
                self._hoverDot:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", x - 4, y - 4)
                self._hoverDot:SetVertexColor(accent[1], accent[2], accent[3], 1)
                self._hoverDot:Show()
            elseif self._hoverDot then
                self._hoverDot:Hide()
            end
        end
        if self._hoverText and hoverLabel and hoverLabel ~= "" then
            self._hoverText:SetText(hoverLabel)
            setColor(self._hoverText, p.text)
            local tw = (self._hoverText.GetStringWidth and self._hoverText:GetStringWidth()) or (#hoverLabel * 6)
            self._hoverText:ClearAllPoints()
            if x - tw / 2 < 0 then
                self._hoverText:SetPoint("BOTTOMLEFT", self.plot, "TOPLEFT", 0, 2)
            elseif x + tw / 2 > self.plotWidth then
                self._hoverText:SetPoint("BOTTOMRIGHT", self.plot, "TOPRIGHT", 0, 2)
            else
                self._hoverText:SetPoint("BOTTOM", self.plot, "TOPLEFT", x, 2)
            end
            self._hoverText:Show()
        end
    end

    function chart:ApplyTheme()
        local p = getPalette()
        applySurface(self, p)
        setColor(self.title, p.text)
        if self._summaryPositive == true then
            setColor(self.summary, p.accentGreen)
        elseif self._summaryPositive == false then
            setColor(self.summary, p.accentRed)
        else
            setColor(self.summary, p.textSecondary)
        end
        setColor(self.empty, p.textMuted)
        if self.headerSep then
            self.headerSep:SetColorTexture(p.separator[1], p.separator[2], p.separator[3], (p.separator[4] or 0.4) * 0.50)
        end
        for i = 1, 3 do
            setColor(self.yLabels[i], p.textSecondary)
            setColor(self.xLabels[i], p.textSecondary)
        end
        for _, lbl in ipairs(self._yAxisLabels) do setColor(lbl, p.textSecondary) end
        for _, lbl in ipairs(self._xAxisLabels) do setColor(lbl, p.textSecondary) end
        for _, gl in ipairs(self._yAxisLines) do
            gl:SetColorTexture(p.separator[1], p.separator[2], p.separator[3], (p.separator[4] or 0.4) * 0.42)
        end
        for _, grid in ipairs(self._grids) do
            grid:SetColorTexture(p.separator[1], p.separator[2], p.separator[3], (p.separator[4] or 0.4) * 0.35)
        end
        if self.baseline then
            self.baseline:SetColorTexture(p.separator[1], p.separator[2], p.separator[3], math.min(0.65, (p.separator[4] or 0.4) * 0.90))
        end
        if self._plotBg then
            if p.mode == "light" then
                self._plotBg:SetColorTexture(0.955, 0.955, 0.968, 0.85)
            else
                self._plotBg:SetColorTexture(0.055, 0.059, 0.067, 0.78)
            end
        end
        if self._selectionBox then
            self._selectionBox:SetColorTexture(p.accentBlue[1], p.accentBlue[2], p.accentBlue[3], 0.18)
        end
        stylePillButton(self.resetZoom, p)
        if self._redraw then self._redraw() end
    end

    function chart:Layout(chartWidth, chartHeight, skipRedraw)
        chartWidth = math.max(1, chartWidth or (self.GetWidth and self:GetWidth()) or width)
        chartHeight = math.max(1, chartHeight or (self.GetHeight and self:GetHeight()) or height)
        if self.SetSize then self:SetSize(chartWidth, chartHeight) end
        self.axisWidth = moneyAxisWidth()
        local plotLeft = self.axisWidth + 12
        self.plotWidth, self.plotHeight = math.max(1, chartWidth - plotLeft - 18), math.max(1, chartHeight - 66)
        self.summary:SetWidth(math.max(1, chartWidth * 0.34))
        self.plot:ClearAllPoints()
        self.plot:SetPoint("TOPLEFT", plotLeft, -50)
        self.plot:SetSize(self.plotWidth, self.plotHeight)
        for i = 1, 3 do
            local fraction = (i - 1) / 2
            self.yLabels[i]:ClearAllPoints()
            self.yLabels[i]:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -8, self.plotHeight * fraction)
            self.yLabels[i]:SetWidth(self.axisWidth)
            self.xLabels[i]:ClearAllPoints()
            self.xLabels[i]:SetPoint(i == 1 and "LEFT" or (i == 3 and "RIGHT" or "CENTER"),
                self.plot, "BOTTOMLEFT", self.plotWidth * fraction, -12)
        end
        local segW = math.max(1, self.plotWidth / 16)
        for _, grid in ipairs(self._grids) do
            grid:ClearAllPoints()
            grid:SetSize(segW, 1)
            grid:SetPoint("BOTTOMLEFT", self.plotWidth * grid.dash / 16, self.plotHeight * grid.fraction)
        end
        if self._redraw and not skipRedraw then self._redraw() end
    end

    local function cursorFraction(self)
        if not GetCursorPosition or not self.plot.GetLeft then return nil end
        local x = GetCursorPosition()
        if type(x) ~= "number" then return nil end
        local scale = self.plot.GetEffectiveScale and self.plot:GetEffectiveScale() or 1
        if not scale or scale == 0 then scale = 1 end
        local left = self.plot:GetLeft()
        if type(left) ~= "number" then return nil end
        return math.max(0, math.min(1, (x / scale - left) / math.max(1, self.plotWidth)))
    end

    function chart:_beginRange()
        self._dragStart = cursorFraction(self)
    end

    function chart:_updateSelection(x)
        if not self._dragStart or not self._selectionBox then return end
        local startX = self._dragStart * self.plotWidth
        local minX = math.min(startX, x)
        local maxX = math.max(startX, x)
        if maxX - minX >= 2 then
            self._selectionBox:ClearAllPoints()
            self._selectionBox:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", minX, 0)
            self._selectionBox:SetSize(maxX - minX, math.max(1, self.plotHeight))
            self._selectionBox:Show()
        else
            self._selectionBox:Hide()
        end
    end

    function chart:_endRange()
        local start, finish = self._dragStart, cursorFraction(self)
        self._dragStart = nil
        if self._selectionBox then self._selectionBox:Hide() end
        if start == nil or finish == nil or not self._rawPointCount or self._rawPointCount < 2 then return end
        local current = self._zoomRange or { 1, self._rawPointCount }
        local span = current[2] - current[1]
        local a = current[1] + math.floor(math.min(start, finish) * span)
        local b = current[1] + math.floor(math.max(start, finish) * span)
        if b - a < 1 then return end
        self._zoomRange = { math.max(1, a), math.min(self._rawPointCount, b) }
        if self._redraw then self._redraw() end
    end

    chart.plot:EnableMouse(true)
    chart.plot:SetScript("OnMouseDown", function(_, button) if not button or button == "LeftButton" then chart:_beginRange() end end)
    chart.plot:SetScript("OnMouseUp", function(_, button) if not button or button == "LeftButton" then chart:_endRange() end end)

    function chart:SetTitle(txt) self.title:SetText(txt or "") end

    function chart:_clearRender()
        hide(self._lines); hide(self._glowLines); hide(self._dots); hide(self._bars); hide(self._hits)
        hide(self._yAxisLines); hide(self._yAxisLabels); hide(self._xAxisLabels)
        self._dragStart = nil
        self:_hideHover()
        if self._selectionBox then self._selectionBox:Hide() end
        for _, hit in pairs(self._hits) do hit.tooltip = nil; hit.hoverMeta = nil end
        if self.baseline then self.baseline:Hide() end
        self._lastSeries, self._lastBars, self._pointCount, self._barCount = {}, {}, 0, 0
        self._summaryPositive = nil
        self.resetZoom:Hide()
        self.summary:SetText("")
        for i = 1, 3 do
            self.xLabels[i]:SetText(""); self.xLabels[i]:Hide()
            self.yLabels[i]:SetText(""); self.yLabels[i]:Hide()
        end
        for _, grid in ipairs(self._grids) do grid:Hide() end
        self.empty:Show()
        if GameTooltip and self._tooltipOwner then GameTooltip:Hide(); self._tooltipOwner = nil end
    end

    function chart:Clear()
        self._inputSeries, self._inputBars = nil, nil
        self._zoomRange, self._rawCategories, self._rawPointCount = nil, nil, 0
        self:_clearRender()
    end

    function chart:_axes(lo, hi, points, formatY, ticks, step, isMoney, isBar)
        self.empty:Hide()
        local pal = getPalette()
        local h = H()
        local isFullFixed = h and h.Theme and h.Theme.GetPriceDisplayMode and h.Theme.GetPriceDisplayMode() == "full_fixed"
        local useCompactAxis = isMoney and not isFullFixed
        local yTicks = ticks or { lo, lo + (hi - lo) * 0.5, hi }
        local range = math.max(1e-6, hi - lo)
        for i = 1, 3 do
            self.yLabels[i]:Hide()
            self.xLabels[i]:Hide()
        end
        for _, grid in ipairs(self._grids) do grid:Hide() end
        -- Draw dynamic crisp Y-axis horizontal gridlines and nicely rounded labels (TSM style)
        for i, tv in ipairs(yTicks) do
            local frac = math.max(0, math.min(1, (tv - lo) / range))
            local yPos = frac * self.plotHeight
            local gl = self._yAxisLines[i]
            if not gl then
                gl = self.plot:CreateTexture(nil, "BACKGROUND")
                self._yAxisLines[i] = gl
            end
            gl:ClearAllPoints()
            gl:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, yPos)
            gl:SetSize(self.plotWidth, 1)
            gl:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], (pal.separator[4] or 0.4) * (i == 1 and 0.65 or 0.36))
            gl:Show()

            local yl = self._yAxisLabels[i]
            if not yl then
                yl = label(self.plot, "RIGHT", -8, yPos, "RIGHT", 11, "regular")
                self._yAxisLabels[i] = yl
            end
            yl:ClearAllPoints()
            local clampedY = math.max(5, math.min(self.plotHeight - 5, yPos))
            yl:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -8, clampedY)
            yl:SetWidth(self.axisWidth or 64)
            setColor(yl, pal.textSecondary)
            local txt = useCompactAxis and formatAxisMoney(tv, step, pal) or formatY(tv)
            yl:SetText(txt)
            yl:Show()
            if i == 1 then self.yLabels[1]:SetText(txt)
            elseif i == #yTicks then self.yLabels[3]:SetText(txt) end
        end
        if #yTicks >= 2 then
            local midVal = yTicks[math.ceil(#yTicks / 2)]
            self.yLabels[2]:SetText(useCompactAxis and formatAxisMoney(midVal, step, pal) or formatY(midVal))
        end

        -- Draw dynamic evenly-spaced X-axis date labels (TSM style, edge-clamped)
        local n = #(points or {})
        if n == 0 then return end
        local longSpan = n > 180
        local maxLabels = math.max(2, math.min(7, math.floor(self.plotWidth / 76) + 1))
        local count = math.min(n, maxLabels)
        local indices = {}
        if count == 1 then
            indices[1] = 1
        else
            for k = 1, count do
                local idx = math.floor(1 + (k - 1) * (n - 1) / (count - 1) + 0.5)
                if #indices == 0 or indices[#indices] ~= idx then
                    indices[#indices + 1] = idx
                end
            end
        end
        local halfLabelW = 34
        for i, idx in ipairs(indices) do
            local p = points[idx]
            local frac = isBar and ((idx - 0.5) / n) or (n > 1 and ((idx - 1) / (n - 1)) or 0.5)
            local xPos = frac * self.plotWidth
            local xl = self._xAxisLabels[i]
            if not xl then
                xl = label(self.plot, "TOP", xPos, -6, "CENTER", 11, "regular")
                self._xAxisLabels[i] = xl
            end
            xl:ClearAllPoints()
            xl:SetWidth(76)
            if xPos < halfLabelW then
                xl:SetJustifyH("LEFT")
                xl:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", 0, -6)
            elseif xPos + halfLabelW > self.plotWidth then
                xl:SetJustifyH("RIGHT")
                xl:SetPoint("TOPRIGHT", self.plot, "BOTTOMRIGHT", 0, -6)
            else
                xl:SetJustifyH("CENTER")
                xl:SetPoint("TOP", self.plot, "BOTTOMLEFT", xPos, -6)
            end
            setColor(xl, pal.textSecondary)
            local lblText = formatAxisX(p and (p.label or p.day) or "", longSpan)
            xl:SetText(lblText)
            xl:Show()
            if i == 1 then self.xLabels[1]:SetText(lblText) end
            if i == #indices then self.xLabels[3]:SetText(lblText) end
        end
        local midP = points[math.ceil(n / 2)]
        self.xLabels[2]:SetText(formatAxisX(midP and (midP.label or midP.day) or "", longSpan))
    end

    function chart:_hit(i, x, hitWidth, tooltip, hoverMeta)
        local hit = self._hits[i]
        if not hit then
            hit = CreateFrame("Button", nil, self.plot)
            hit:SetScript("OnEnter", function(button)
                if button.hoverMeta then
                    local hm = button.hoverMeta
                    self:_showHover(hm.x, hm.y, hm.label, hm.color, hm.barLeft, hm.barSlotW)
                    if self._dragStart then self:_updateSelection(hm.x) end
                    if self._onHover then self._onHover(hm.rawDate) end
                end
                if not GameTooltip then return end
                self._tooltipOwner = button
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                button.tooltip(GameTooltip)
                GameTooltip:Show()
            end)
            hit:SetScript("OnLeave", function()
                self._tooltipOwner = nil
                self:_hideHover()
                if GameTooltip then GameTooltip:Hide() end
            end)
            hit:SetScript("OnMouseDown", function(_, button) if not button or button == "LeftButton" then self:_beginRange() end end)
            hit:SetScript("OnMouseUp", function(_, button) if not button or button == "LeftButton" then self:_endRange() end end)
            self._hits[i] = hit
        end
        hit:ClearAllPoints()
        hit:SetPoint("BOTTOMLEFT", x, 0)
        hit:SetSize(math.max(1, hitWidth), self.plotHeight)
        hit.tooltip = tooltip
        hit.hoverMeta = hoverMeta
        hit:Show()
    end

    local h = H()
    if h and h.Theme and h.Theme.OnModeChanged then
        h.Theme.OnModeChanged(function() chart:ApplyTheme() end)
    end

    chart:SetTitle(opts.title)
    chart:Clear()
    chart:Layout(width, height)
    return chart
end

function Chart.CreateLineChart(parent, width, height, opts)
    opts = opts or {}
    local chart = base(parent, width, height, opts)
    chart._redraw = function()
        if chart._inputSeries then chart._redrawing = true; chart:SetData(chart._inputSeries, chart._inputOpts); chart._redrawing = nil end
    end

    local function resolveSeriesColor(series, sIdx, pal)
        if series.colorKey then
            local keyMap = {
                blue = pal.accentBlue,
                green = pal.accentGreen,
                orange = pal.accentOrange,
                purple = pal.accentPurple,
                red = pal.accentRed,
            }
            if keyMap[series.colorKey] then return keyMap[series.colorKey] end
        end
        if series.color then return series.color end
        local cycle = { pal.accentBlue, pal.accentGreen, pal.accentOrange, pal.accentPurple }
        return cycle[((sIdx - 1) % #cycle) + 1]
    end

    function chart:SetData(seriesList, callOpts)
        if self.axisWidth ~= moneyAxisWidth() then self:Layout(nil, nil, true) end
        if not self._redrawing then self._zoomRange = nil end
        self._inputSeries, self._inputOpts = seriesList or {}, callOpts
        self:_clearRender()
        local pal = getPalette()
        local settings = callOpts or opts
        local formatY = settings.formatY or opts.formatY or money
        local isMoney = (settings.formatY == nil and opts.formatY == nil)
        if settings.title then self:SetTitle(settings.title) end
        local lo, hi, reference, longest = nil, nil, nil, 0
        local maps, categories, seen, pointKeys = {}, {}, {}, {}
        for _, series in ipairs(seriesList or {}) do
            for i, point in ipairs(series.points or series.data or {}) do
                local pointKey = key(point, i)
                pointKeys[point] = pointKey
                if not seen[pointKey] then seen[pointKey] = true; categories[#categories + 1] = pointKey end
            end
        end
        table.sort(categories, function(a, b)
            if type(a) == type(b) then return a < b end
            return tostring(a) < tostring(b)
        end)
        local categoryIndex = {}
        for i, category in ipairs(categories) do categoryIndex[category] = i end
        self._rawCategories, self._rawPointCount = categories, #categories
        local selectedFirst = self._zoomRange and self._zoomRange[1] or 1
        local selectedLast = self._zoomRange and self._zoomRange[2] or #categories
        local activeSeriesCount = 0
        for _, series in ipairs(seriesList or {}) do
            if #(series.points or series.data or {}) > 0 then activeSeriesCount = activeSeriesCount + 1 end
        end
        for s, series in ipairs(seriesList or {}) do
            local sourcePoints = series.points or series.data or {}
            local points = {}
            for i, source in ipairs(sourcePoints) do
                local index = categoryIndex[key(source, i)]
                if index and index >= selectedFirst and index <= selectedLast then points[#points + 1] = source end
            end
            local sampled = sample(points)
            local resolvedColor = resolveSeriesColor(series, s, pal)
            if (activeSeriesCount == 1 or settings.trendColor) and #sampled >= 2 then
                local firstV, lastV = value(sampled[1]), value(sampled[#sampled])
                if pal.mode == "light" then
                    resolvedColor = (lastV >= firstV) and pal.accentGreen or pal.accentRed
                else
                    resolvedColor = (lastV >= firstV) and { 0.110, 0.855, 0.463, 1.0 } or { 0.961, 0.298, 0.278, 1.0 }
                end
            end
            self._lastSeries[s] = {
                name = series.name,
                color = resolvedColor,
                colorKey = series.colorKey,
                points = sampled,
                data = sampled,
            }
            self._pointCount = math.max(self._pointCount, #sampled)
            maps[s] = {}
            for i, p in ipairs(points) do
                local v = value(p)
                lo, hi = math.min(lo or v, v), math.max(hi or v, v)
                local pointKey = pointKeys[p] or key(p, i)
                maps[s][pointKey] = p
                if not seen[pointKey] then seen[pointKey] = true; categories[#categories + 1] = pointKey end
            end
            if #points > longest then reference, longest = sampled, #points end
        end
        self.resetZoom:SetShown(self._zoomRange ~= nil)
        if not reference or #reference == 0 then return end
        local positions, visibleCategories = {}, {}
        for i = selectedFirst, selectedLast do
            if categories[i] ~= nil then visibleCategories[#visibleCategories + 1] = categories[i] end
        end
        for i, category in ipairs(visibleCategories) do
            positions[category] = #visibleCategories > 1 and (i - 1) / (#visibleCategories - 1) * self.plotWidth or self.plotWidth / 2
        end
        local yLo, yHi, yTicks, yStep = computeNiceYAxis(lo, hi, self.plotHeight, isMoney)
        lo, hi = yLo, yHi
        self:_axes(lo, hi, reference, formatY, yTicks, yStep, isMoney)
        local lineIndex, dotIndex = 0, 0
        local glowAlpha = (pal.mode == "light") and 0.10 or 0.16
        for _, series in ipairs(self._lastSeries) do
            local points, color = series.points, series.color or pal.accentBlue
            local r, g, b, a = color[1], color[2], color[3], color[4] or 1
            local previousX, previousY
            for i, p in ipairs(points) do
                local x = positions[pointKeys[p] or key(p, i)] or 0
                local y = (value(p) - lo) / (hi - lo) * self.plotHeight
                if previousX and self.plot.CreateLine then
                    lineIndex = lineIndex + 1
                    local glow = self._glowLines[lineIndex]
                    if not glow then glow = self.plot:CreateLine(nil, "ARTWORK", nil, 0); self._glowLines[lineIndex] = glow end
                    applySmoothLine(glow, 8.0, r, g, b, glowAlpha)
                    glow:SetStartPoint("BOTTOMLEFT", previousX, previousY)
                    glow:SetEndPoint("BOTTOMLEFT", x, y)
                    glow:Show()

                    local line = self._lines[lineIndex]
                    if not line then line = self.plot:CreateLine(nil, "ARTWORK", nil, 1); self._lines[lineIndex] = line end
                    applySmoothLine(line, 3.5, r, g, b, a)
                    line:SetStartPoint("BOTTOMLEFT", previousX, previousY)
                    line:SetEndPoint("BOTTOMLEFT", x, y)
                    line:Show()
                end
                if not self.plot.CreateLine or #points == 1 then
                    dotIndex = dotIndex + 1
                    local dot = texture(self.plot, self._dots, dotIndex)
                    dot:SetSize(6, 6); dot:SetPoint("BOTTOMLEFT", x - 3, y - 3)
                    dot:SetTexture(assetPath("circle_fill"))
                    dot:SetVertexColor(r, g, b, a)
                end
                previousX, previousY = x, y
            end
        end
        local primarySeries = self._lastSeries[1]
        for i, p in ipairs(reference) do
            local point, pointKey = p, pointKeys[p] or key(p, i)
            local x = positions[pointKey] or 0
            local left = i == 1 and 0 or ((positions[pointKeys[reference[i - 1]]] or 0) + x) / 2
            local right = i == #reference and self.plotWidth or ((positions[pointKeys[reference[i + 1]]] or 0) + x) / 2
            local primaryPt = maps[1] and maps[1][pointKey] or point
            local py = primaryPt and ((value(primaryPt) - lo) / (hi - lo) * self.plotHeight) or nil
            local dateLbl = formatAxisX(point.day or point.label or "", false)
            local hoverLbl = (dateLbl ~= "" and (dateLbl .. "  ") or "") .. formatY(value(primaryPt))
            self:_hit(i, left, right - left, function(tip)
                tip:AddLine(tostring(point.day or point.label or ""), pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3])
                for s, series in ipairs(self._lastSeries) do
                    local found = maps[s][pointKey]
                    if found then tip:AddDoubleLine(series.name or "Value", formatY(value(found))) end
                end
            end, {
                x = x,
                y = py,
                label = hoverLbl,
                rawDate = tostring(point.day or point.label or ""),
                color = (primarySeries and primarySeries.color) or pal.accentOrange,
            })
        end
        local legend = {}
        for _, series in ipairs(self._lastSeries) do legend[#legend + 1] = series.name or "Value" end
        self.summary:SetText(settings.summary or table.concat(legend, " / "))
        setColor(self.summary, pal.textSecondary)
    end
    return chart
end

function Chart.CreateBarChart(parent, width, height, opts)
    opts = opts or {}
    local chart = base(parent, width, height, opts)
    chart._redraw = function()
        if chart._inputBars then chart._redrawing = true; chart:SetData(chart._inputBars, chart._inputOpts); chart._redrawing = nil end
    end
    chart.baseline = chart.plot:CreateTexture(nil, "BORDER")
    chart.baseline:Hide()

    function chart:SetData(bars, callOpts)
        if self.axisWidth ~= moneyAxisWidth() then self:Layout(nil, nil, true) end
        if not self._redrawing then self._zoomRange = nil end
        self._inputBars, self._inputOpts = bars or {}, callOpts
        self:_clearRender()
        local pal = getPalette()
        local settings = callOpts or opts
        local formatY = settings.formatY or opts.formatY or money
        local isMoney = (settings.formatY == nil and opts.formatY == nil)
        if settings.title then self:SetTitle(settings.title) end
        bars = bars or {}
        self._rawPointCount = #bars
        if #bars == 0 then return end
        self.resetZoom:SetShown(self._zoomRange ~= nil)
        if self._zoomRange then
            local sliced = {}
            for i = math.max(1, self._zoomRange[1]), math.min(#bars, self._zoomRange[2]) do sliced[#sliced + 1] = bars[i] end
            bars = sliced
        end
        local rendered = bars
        if #bars > 45 then
            rendered = {}
            for bucket = 1, 45 do
                local first = 1 + math.floor((bucket - 1) * #bars / 45)
                local last = math.floor(bucket * #bars / 45)
                local total = 0
                for i = first, last do total = total + value(bars[i]) end
                rendered[bucket] = { day = tostring(bars[first].day or bars[first].label or "") .. " - " ..
                    tostring(bars[last].day or bars[last].label or ""), label = bars[first].label or bars[first].day,
                    value = total, first = bars[first], last = bars[last] }
            end
        end
        self._lastBars, self._barCount = rendered, #rendered
        local lo, hi, total = 0, 0, 0
        for _, p in ipairs(rendered) do lo = math.min(lo, value(p)); hi = math.max(hi, value(p)); total = total + value(p) end
        if lo == hi then hi = lo + (isMoney and 10000 or 1) end
        local yLo, yHi, yTicks, yStep = computeNiceYAxis(lo, hi, self.plotHeight, isMoney)
        lo, hi = math.min(0, yLo), math.max(0, yHi)
        self:_axes(lo, hi, rendered, formatY, yTicks, yStep, isMoney, true)
        local zero = -lo / (hi - lo) * self.plotHeight
        local hasNeg = lo < 0
        self.baseline:ClearAllPoints(); self.baseline:SetPoint("BOTTOMLEFT", 0, zero)
        self.baseline:SetSize(self.plotWidth, 1)
        self.baseline:SetColorTexture(pal.separator[1], pal.separator[2], pal.separator[3], hasNeg and 0.80 or math.min(0.65, (pal.separator[4] or 0.4) * 0.90))
        self.baseline:Show()
        local step = self.plotWidth / #rendered
        local barW = math.min(36, math.max(2, step * 0.68))
        local isLight = (pal.mode == "light")
        local posTip = isLight and pal.accentGreen or { 0.110, 0.855, 0.463, 0.96 }
        local posBase = isLight and { pal.accentGreen[1], pal.accentGreen[2], pal.accentGreen[3], 0.55 } or { 0.063, 0.520, 0.285, 0.78 }
        local negTip = isLight and pal.accentRed or { 0.961, 0.298, 0.278, 0.96 }
        local negBase = isLight and { pal.accentRed[1], pal.accentRed[2], pal.accentRed[3], 0.55 } or { 0.620, 0.165, 0.155, 0.78 }
        local function formatSignedVal(v)
            return isMoney and money(v, true) or formatY(v)
        end
        for i, p in ipairs(rendered) do
            local v, point = value(p), p
            local y = (v - lo) / (hi - lo) * self.plotHeight
            local totalBarH = v == 0 and 1 or math.max(2, math.abs(y - zero))
            local slotLeft = (i - 1) * step
            local barX = slotLeft + (step - barW) * 0.5
            local barY = math.min(zero, y)
            local posCol = isLight and { pal.accentGreen[1], pal.accentGreen[2], pal.accentGreen[3], 0.92 } or { pal.accentGreen[1], 0.80, pal.accentGreen[3], 0.92 }
            local negCol = isLight and { pal.accentRed[1], pal.accentRed[2], pal.accentRed[3], 0.92 } or { 0.88, pal.accentRed[2], pal.accentRed[3], 0.92 }
            local compatColor = v > 0 and posCol
                or (v < 0 and negCol
                or { pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.55 })
            local visualColor = v > 0 and posTip or (v < 0 and negTip or pal.textMuted)
            local bar = texture(self.plot, self._bars, i)
            bar:SetColorTexture(unpack(compatColor))
            if bar.SetVertexColor then bar:SetVertexColor(1, 1, 1, 1) end
            if v ~= 0 and bar.SetGradient and _G.CreateColor then
                if v > 0 then
                    pcall(bar.SetGradient, bar, "VERTICAL",
                        _G.CreateColor(posBase[1], posBase[2], posBase[3], posBase[4]),
                        _G.CreateColor(posTip[1], posTip[2], posTip[3], posTip[4]))
                else
                    pcall(bar.SetGradient, bar, "VERTICAL",
                        _G.CreateColor(negTip[1], negTip[2], negTip[3], negTip[4]),
                        _G.CreateColor(negBase[1], negBase[2], negBase[3], negBase[4]))
                end
            end
            bar:SetSize(barW, totalBarH)
            bar:SetPoint("BOTTOMLEFT", barX, barY)
            local barCenterX = slotLeft + step * 0.5
            local dateLbl = formatAxisX(point.day or point.label or "", false)
            self:_hit(i, slotLeft, step, function(tip)
                tip:AddLine(dateLbl ~= "" and dateLbl or tostring(point.day or point.label or ""), pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3])
                tip:AddDoubleLine("Realized Profit", formatSignedVal(value(point)))
            end, {
                x = barCenterX,
                y = y,
                label = (dateLbl ~= "" and (dateLbl .. "  ") or "") .. formatSignedVal(v),
                rawDate = tostring(point.day or point.label or ""),
                color = visualColor,
                barLeft = slotLeft,
                barSlotW = step,
            })
        end
        self._summaryPositive = total > 0 and true or (total < 0 and false or nil)
        self.summary:SetText(settings.summary or formatSignedVal(total))
        if self._summaryPositive == true then
            setColor(self.summary, pal.accentGreen)
        elseif self._summaryPositive == false then
            setColor(self.summary, pal.accentRed)
        else
            setColor(self.summary, pal.textSecondary)
        end
    end
    return chart
end

---------------------------------------------------------------------------------------------------
-- Concept B & Concept C Time-of-Day Heatmap Widgets
-- Pure SetColorTexture pooled quads (zero per-cell CreateFrame, zero new .tga/.blp assets).
---------------------------------------------------------------------------------------------------

local DOW_LABELS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local HOUR_TICKS = { 0, 3, 6, 9, 12, 15, 18, 21 }

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function lerpRGBA(c1, c2, t)
    if t ~= t or t < 0 then t = 0 elseif t > 1 then t = 1 end
    local a1 = c1[4] or 1
    local a2 = c2[4] or 1
    return c1[1] + (c2[1] - c1[1]) * t,
        c1[2] + (c2[2] - c1[2]) * t,
        c1[3] + (c2[3] - c1[3]) * t,
        a1 + (a2 - a1) * t
end

function Chart.IsoDowFromWday(wday)
    local w = tonumber(wday) or 2
    return ((w + 5) % 7) + 1 -- ISO 1=Mon..5=Fri, 6=Sat, 7=Sun
end

local function nowIsoDowAndHour(nowOverride)
    local fn = _G.date or (os and os.date)
    local t
    if fn then
        if nowOverride ~= nil then
            t = fn("*t", nowOverride)
        else
            t = fn("*t")
        end
    end
    local wday = (type(t) == "table" and tonumber(t.wday)) or 2
    local dow = Chart.IsoDowFromWday(wday)
    local hour = (type(t) == "table" and tonumber(t.hour)) or 12
    if hour < 0 then hour = 0 elseif hour > 23 then hour = 23 end
    return dow, hour
end

local lastFullSrc, lastFullMode, lastFullPal
local function fullPalette(palOverride)
    if type(palOverride) == "table" and palOverride._isFull then
        return palOverride
    end
    local h = H()
    local theme = h and h.Theme
    local activePal = theme and theme.GetActivePalette and theme.GetActivePalette()
    local basePal = palOverride
    if type(basePal) ~= "table" then
        basePal = activePal
            or (theme and theme.PALETTES and theme.PALETTES[(theme.GetMode and theme.GetMode()) or "dark"])
    end
    local mode = (basePal and basePal.mode == "light") and "light" or "dark"
    if not palOverride and theme and theme.GetMode and theme.GetMode() == "light" then
        mode = "light"
    end
    if basePal ~= nil and basePal == activePal and basePal == lastFullSrc and mode == lastFullMode and lastFullPal then
        return lastFullPal
    end
    local fb = FALLBACK_PALETTES[mode]
    local isLight = (mode == "light")
    local p = basePal or fb
    local out = {
        _isFull = true,
        mode = mode,
        skin = p.skin,
        cardBg = p.cardBg or fb.cardBg,
        cardAltBg = p.cardAltBg or fb.cardAltBg,
        pillTrack = p.pillTrack or fb.pillTrack,
        pillThumb = p.pillThumb or (isLight and { 1.0, 1.0, 1.0, 1.0 } or { 1.0, 1.0, 1.0, 0.17 }),
        border = p.border or fb.border,
        separator = p.separator or fb.separator,
        text = p.text or fb.text,
        textSecondary = p.textSecondary or fb.textSecondary,
        textMuted = p.textMuted or fb.textMuted,
        textBlue = p.textBlue or (isLight and { 0.0, 0.384, 0.800, 1.0 } or { 0.361, 0.722, 1.0, 1.0 }),
        accentBlue = p.accentBlue or fb.accentBlue,
        accentGreen = p.accentGreen or fb.accentGreen,
        accentOrange = p.accentOrange or fb.accentOrange,
        accentRed = p.accentRed or fb.accentRed,
        accentPurple = p.accentPurple or fb.accentPurple,
        hexText = p.hexText or (isLight and "000000" or "ffffff"),
        hexSecondary = p.hexSecondary or (isLight and "3c3c43" or "ebebf5"),
        hexMuted = p.hexMuted or (isLight and "5e626a" or "98989d"),
        hexPositive = p.hexPositive or (isLight and "007a2b" or "30d158"),
        hexBlue = p.hexBlue or (isLight and "0062cc" or "5ac8fa"),
        hexWarning = p.hexWarning or (isLight and "9e4b00" or "ff9230"),
        hexDanger = p.hexDanger or (isLight and "b8141a" or "ff4245"),
    }
    if basePal ~= nil and basePal == activePal then
        lastFullSrc, lastFullMode, lastFullPal = basePal, mode, out
    end
    return out
end

local function palHex(key, pal, fbHex)
    local hex = (pal and pal[key]) or fbHex or "ffffff"
    return "|cff" .. tostring(hex)
end

local function formatMoneyPartsText(copper, signed, pal)
    local p = pal or fullPalette()
    if type(copper) ~= "number" or copper ~= copper or copper == math.huge or copper == -math.huge then
        return palHex("hexMuted", p, "98989d") .. "—|r"
    end
    local h = H()
    local theme = h and h.Theme
    if theme and theme.FormatMoneyParts then
        local parts = theme.FormatMoneyParts(copper, signed == true, true)
        if type(parts) == "table" and parts.text then
            return parts.text
        elseif type(parts) == "string" then
            return parts
        end
    end
    return money(copper, signed == true)
end

local function formatCompactQty(qty)
    if type(qty) ~= "number" or qty ~= qty then return "—" end
    if qty >= 10000 then
        return string.format("%.0fk", qty / 1000)
    elseif qty >= 1000 then
        return string.format("%.1fk", qty / 1000)
    end
    return tostring(math.floor(qty + 0.5))
end

local function formatSignedPct(pct)
    if type(pct) ~= "number" or pct ~= pct then return "—" end
    if math.abs(pct) < 0.05 then return "0.0%" end
    return string.format("%+.1f%%", pct)
end

local function heatmapBadgeStyle(variant, pal)
    local isLight = (pal.mode == "light")
    if isLight and variant == "positive" then
        return { 0.000, 0.478, 0.169, 0.12 }, { 0.000, 0.478, 0.169, 1.0 }
    elseif isLight and (variant == "hot" or variant == "warning") then
        return { 0.878, 0.420, 0.000, 0.12 }, { 0.620, 0.294, 0.000, 1.0 }
    elseif isLight and variant == "danger" then
        return { 0.839, 0.141, 0.161, 0.12 }, { 0.722, 0.078, 0.102, 1.0 }
    elseif isLight and variant == "blue" then
        return { 0.000, 0.451, 0.902, 0.12 }, { 0.000, 0.384, 0.800, 1.0 }
    elseif variant == "positive" then
        return { pal.accentGreen[1], pal.accentGreen[2], pal.accentGreen[3], 0.18 }, pal.accentGreen
    elseif variant == "hot" or variant == "warning" then
        return { pal.accentOrange[1], pal.accentOrange[2], pal.accentOrange[3], 0.18 }, pal.accentOrange
    elseif variant == "danger" then
        return { pal.accentRed[1], pal.accentRed[2], pal.accentRed[3], 0.18 }, pal.accentRed
    elseif variant == "blue" then
        return { pal.accentBlue[1], pal.accentBlue[2], pal.accentBlue[3], 0.18 }, pal.textBlue
    end
    if isLight then
        return { 0.463, 0.463, 0.502, 0.13 }, pal.textSecondary
    end
    return { 0.463, 0.463, 0.502, 0.26 }, pal.text
end

local function createBadge(parent, height, fontSize)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(height or 20)
    local h = H()
    local theme = h and h.Theme
    local surface, bgTex
    if theme and theme.NineApple then
        surface = theme.NineApple(frame, "pill", { 1, 1, 1, 0.14 }, false, { noSpecular = true })
    else
        bgTex = frame:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(frame)
        bgTex:SetColorTexture(0.3, 0.3, 0.34, 0.4)
    end
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetWordWrap(false)
    applyFont(text, fontSize or 10, "semibold")

    local b = { frame = frame, surface = surface, bgTex = bgTex, text = text, variant = "neutral" }
    function b:Set(variant, txt, pal, padX, minW)
        self.variant = variant or "neutral"
        if txt ~= nil then self.text:SetText(tostring(txt)) end
        local p = fullPalette(pal)
        local fill, ink = heatmapBadgeStyle(self.variant, p)
        if self.surface and self.surface.SetFill then
            self.surface:SetFill(fill[1], fill[2], fill[3], fill[4] or 0.16)
        elseif self.bgTex then
            self.bgTex:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 0.16)
        end
        setColor(self.text, ink)
        local sw = (self.text.GetStringWidth and self.text:GetStringWidth()) or (#(self.text:GetText() or "") * 6)
        self.frame:SetWidth(math.max(minW or 26, math.ceil(sw) + (padX or 14)))
    end
    return b
end

local DARK_HEAT_STOPS = {
    deepBlue    = { 0.080, 0.360, 0.780, 0.94 }, -- <= -15%
    deepBlueExt = { 0.080 * 0.82, 0.360 * 0.85, 0.780 + 0.08, 0.98 },
    cyanTeal    = { 0.100, 0.560, 0.680, 0.90 }, -- -15 .. -5%
    slate       = { 0.260, 0.280, 0.330, 0.86 }, -- -5 .. +5%
    amber       = { 0.780, 0.560, 0.140, 0.90 }, -- +5 .. +15%
    orange      = { 0.920, 0.440, 0.120, 0.94 }, -- +15 .. +30%
    coralRed    = { 0.940, 0.260, 0.240, 0.96 }, -- > +30%
    coralRedExt = { 0.940 + 0.04, 0.260 * 0.82, 0.240 * 0.82, 0.98 },
}

local LIGHT_HEAT_STOPS = {
    deepBlue    = { 0.120, 0.440, 0.880, 0.90 }, -- <= -15%
    deepBlueExt = { 0.120 * 0.82, 0.440 * 0.85, 0.880 + 0.08, 0.98 },
    cyanTeal    = { 0.140, 0.620, 0.720, 0.84 }, -- -15 .. -5%
    slate       = { 0.810, 0.830, 0.870, 0.90 }, -- -5 .. +5%
    amber       = { 0.900, 0.660, 0.180, 0.88 }, -- +5 .. +15%
    orange      = { 0.920, 0.480, 0.140, 0.92 }, -- +15 .. +30%
    coralRed    = { 0.880, 0.220, 0.220, 0.94 }, -- > +30%
    coralRedExt = { 0.880 + 0.04, 0.220 * 0.82, 0.220 * 0.82, 0.98 },
}

local FALLBACK_HEAT_ALT_BG = { 0.12, 0.12, 0.14, 1.0 }
local skinNeutralCache = setmetatable({}, { __mode = "k" })

function Chart.HeatmapCellColor(pctVsAvg, metricMode, pal, isWeekend, supplyRatio)
    local p = (type(pal) == "table" and pal._isFull) and pal or fullPalette(pal)
    local isLight = (p.mode == "light")
    local mode = (metricMode == "avg" or metricMode == "supply") and metricMode
        or ((type(metricMode) == "string") and metricMode:lower() or "avg")

    local effectivePct
    if mode == "supply" then
        if type(supplyRatio) == "number" and supplyRatio == supplyRatio then
            -- Low supply = warm sell opportunity (+%), high supply = cool abundant (-%)
            effectivePct = (1.0 - supplyRatio) * 35.0
        elseif type(pctVsAvg) == "number" and pctVsAvg == pctVsAvg then
            effectivePct = -pctVsAvg
        else
            effectivePct = nil
        end
    else
        if type(pctVsAvg) == "number" and pctVsAvg == pctVsAvg then
            effectivePct = pctVsAvg
        else
            effectivePct = nil
        end
    end

    if effectivePct == nil then
        if isLight then
            if isWeekend then
                return 0.885, 0.892, 0.922, 0.90
            end
            return 0.915, 0.918, 0.935, 0.85
        end
        local alt = p.cardAltBg or FALLBACK_HEAT_ALT_BG
        local a1, a2, a3 = alt[1] or 0.12, alt[2] or 0.12, alt[3] or 0.14
        local r = a1 + (0.10 - a1) * 0.55
        local g = a2 + (0.11 - a2) * 0.55
        local b = a3 + (0.14 - a3) * 0.55
        if isWeekend then
            r, g, b = r + 0.02, g + 0.02, b + 0.05
            if r < 0 then r = 0 elseif r > 1 then r = 1 end
            if g < 0 then g = 0 elseif g > 1 then g = 1 end
            if b < 0 then b = 0 elseif b > 1 then b = 1 end
        end
        return r, g, b, 0.62
    end

    local stops = isLight and LIGHT_HEAT_STOPS or DARK_HEAT_STOPS
    local neutral = stops.slate
    if not isLight and p.skin and p.skin ~= "standard" and p.cardAltBg then
        local alt = p.cardAltBg
        local cached = skinNeutralCache[alt]
        local a1, a2, a3 = alt[1] or 0.2, alt[2] or 0.2, alt[3] or 0.25
        if not cached or cached._a1 ~= a1 or cached._a2 ~= a2 or cached._a3 ~= a3 then
            local sl = stops.slate
            cached = {
                sl[1] + (a1 - sl[1]) * 0.35,
                sl[2] + (a2 - sl[2]) * 0.35,
                sl[3] + (a3 - sl[3]) * 0.35,
                sl[4],
                _a1 = a1, _a2 = a2, _a3 = a3,
            }
            skinNeutralCache[alt] = cached
        end
        neutral = cached
    end

    local r, g, b, a
    if effectivePct <= -15 then
        r, g, b, a = lerpRGBA(stops.deepBlue, stops.deepBlueExt, (-15 - effectivePct) / 15)
    elseif effectivePct <= -5 then
        r, g, b, a = lerpRGBA(stops.deepBlue, stops.cyanTeal, (effectivePct + 15) / 10)
    elseif effectivePct < 5 then
        if effectivePct < 0 then
            r, g, b, a = lerpRGBA(stops.cyanTeal, neutral, (effectivePct + 5) / 5)
        else
            r, g, b, a = lerpRGBA(neutral, stops.amber, (effectivePct / 5) * 0.35)
        end
    elseif effectivePct <= 15 then
        r, g, b, a = lerpRGBA(stops.amber, stops.orange, ((effectivePct - 5) / 10) * 0.35)
    elseif effectivePct <= 30 then
        r, g, b, a = lerpRGBA(stops.orange, stops.coralRed, ((effectivePct - 15) / 15) * 0.55)
    else
        r, g, b, a = lerpRGBA(stops.coralRed, stops.coralRedExt, (effectivePct - 30) / 20)
    end

    if isWeekend then
        if isLight then
            r, g, b, a = r * 0.96, g * 0.97, b + 0.03, a + 0.03
        else
            r, g, b, a = r + 0.02, g + 0.02, b + 0.04, a + 0.02
        end
    end
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    if g < 0 then g = 0 elseif g > 1 then g = 1 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return r, g, b, a
end

local function buildFallbackSeries(fallbackQuickLook)
    if type(fallbackQuickLook) ~= "table" then return nil end
    local function extractSeries(entry, seriesName, colorKey)
        if type(entry) ~= "table" then return nil end
        local pts = {}
        if type(entry.points) == "table" and #entry.points > 0 then
            for i, p in ipairs(entry.points) do
                if type(p) == "table" and tonumber(p.value) ~= nil then
                    pts[#pts + 1] = { day = p.day or p.label or ("T" .. i), label = p.label or p.day, value = tonumber(p.value) }
                end
            end
        elseif type(entry.values) == "table" then
            local maxIdx = #entry.values
            for k in pairs(entry.values) do
                if type(k) == "number" and k > maxIdx then maxIdx = k end
            end
            local is24h = (fallbackQuickLook.window == "24h")
            local nowTs = tonumber(fallbackQuickLook.now) or (time and time()) or 0
            local startDay = tonumber(fallbackQuickLook.startDay)
            local startSlot = tonumber(fallbackQuickLook.startSlot)
            for i = 1, maxIdx do
                local v = tonumber(entry.values[i])
                if v ~= nil and v == v then
                    local lbl
                    if is24h and startSlot then
                        local ts = (startSlot + i - 1) * 3600
                        local fn = _G.date or (os and os.date)
                        lbl = fn and fn("!%H:00", ts) or string.format("%02d:00", (i - 1) % 24)
                    elseif startDay then
                        local ts = (startDay + i - 1) * 86400
                        local fn = _G.date or (os and os.date)
                        lbl = fn and fn("!%Y-%m-%d", ts) or ("D" .. i)
                    elseif nowTs > 0 and maxIdx <= 7 then
                        local ts = nowTs - (maxIdx - i) * 86400
                        local fn = _G.date or (os and os.date)
                        lbl = fn and fn("!%Y-%m-%d", ts) or ("D" .. i)
                    else
                        lbl = is24h and string.format("%02d:00", (i - 1) % 24) or ("D" .. i)
                    end
                    pts[#pts + 1] = { day = lbl, label = lbl, value = v }
                end
            end
        end
        if #pts == 0 then return nil end
        return { name = seriesName, colorKey = colorKey, points = pts }
    end
    local out = {}
    local sOut = extractSeries(fallbackQuickLook.output, "Sell Price", "blue")
    local sCost = extractSeries(fallbackQuickLook.cost, "Craft Cost", "orange")
    local sNet = extractSeries(fallbackQuickLook.net, "Net Profit", "green")
    if sOut then out[#out + 1] = sOut end
    if sCost then out[#out + 1] = sCost end
    if sNet then out[#out + 1] = sNet end
    if #out == 0 then return nil end
    return out
end

local function mergeTwoHourCell(c0, c1, overallAvg)
    if not c0 and not c1 then return nil end
    if c0 and not c1 then return c0 end
    if c1 and not c0 then return c1 end
    local w0 = (c0.samples and c0.samples > 0) and c0.samples or 1
    local w1 = (c1.samples and c1.samples > 0) and c1.samples or 1
    local w = w0 + w1
    local avgP = math.floor(((c0.avgPrice or 0) * w0 + (c1.avgPrice or 0) * w1) / w + 0.5)
    local minP = math.min(c0.minPrice or c0.avgPrice or 0, c1.minPrice or c1.avgPrice or 0)
    local avgQ = math.floor(((c0.avgQty or 0) * w0 + (c1.avgQty or 0) * w1) / w + 0.5)
    local samples = (c0.samples or 0) + (c1.samples or 0)
    local pct = (overallAvg and overallAvg > 0) and (math.floor((((avgP - overallAvg) / overallAvg) * 100) * 10 + 0.5) / 10) or 0
    return { avgPrice = avgP, minPrice = minP, avgQty = avgQ, samples = samples, pctVsAvg = pct }
end

local function makeBorderRing(parent, layer, sub)
    return {
        top = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2),
        bottom = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2),
        left = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2),
        right = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2),
    }
end

local function setRingRect(ring, anchor, x, yFromTop, w, h, thick, r, g, b, a)
    thick = thick or 2
    ring.top:ClearAllPoints()
    ring.top:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -yFromTop)
    ring.top:SetSize(math.max(1, w), thick)
    ring.top:SetColorTexture(r, g, b, a)
    ring.top:Show()

    ring.bottom:ClearAllPoints()
    ring.bottom:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -(yFromTop + h - thick))
    ring.bottom:SetSize(math.max(1, w), thick)
    ring.bottom:SetColorTexture(r, g, b, a)
    ring.bottom:Show()

    ring.left:ClearAllPoints()
    ring.left:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -yFromTop)
    ring.left:SetSize(thick, math.max(1, h))
    ring.left:SetColorTexture(r, g, b, a)
    ring.left:Show()

    ring.right:ClearAllPoints()
    ring.right:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + w - thick, -yFromTop)
    ring.right:SetSize(thick, math.max(1, h))
    ring.right:SetColorTexture(r, g, b, a)
    ring.right:Show()
end

local function hideRing(ring)
    if not ring then return end
    ring.top:Hide()
    ring.bottom:Hide()
    ring.left:Hide()
    ring.right:Hide()
end

function Chart.CreateHeatmapTimingDrawer(parent, width, height, opts)
    opts = opts or {}
    local compact = (opts.compact == true)
    local showCurve = (opts.showCurve ~= false)
    local initW = math.max(280, tonumber(width) or (compact and 480 or 860))
    local initH = math.max(180, tonumber(height) or (compact and 240 or 415))

    local pal = fullPalette()
    local drawer = CreateFrame("Frame", nil, parent)
    drawer:SetSize(initW, initH)
    applySurface(drawer, pal)

    drawer._compact = compact
    drawer._showCurve = showCurve
    drawer._metric = "avg"
    drawer._resolution = "24h"
    drawer._onDeepAnalysis = opts.onDeepAnalysis
    drawer._onClose = opts.onClose
    drawer._nowOverride = opts.nowOverride
    drawer._itemID = nil
    drawer._heatmap = nil
    drawer._fallbackQuickLook = nil
    drawer._econOverride = nil
    drawer._hoverDow = nil
    drawer._hoverHour = nil
    drawer._curveHoverHour = nil

    -- 1. Action Verdict Banner (38px)
    drawer.banner = CreateFrame("Frame", nil, drawer)
    drawer.banner:SetHeight(38)
    drawer.bannerBg = drawer.banner:CreateTexture(nil, "BACKGROUND")
    drawer.bannerBg:SetAllPoints(drawer.banner)

    drawer.verdictPill = createBadge(drawer.banner, 22, 10)
    drawer.verdictPill.frame:SetPoint("LEFT", drawer.banner, "LEFT", 8, 0)

    drawer.stabilityPill = createBadge(drawer.banner, 20, 10)
    drawer.stabilityPill.frame:SetPoint("RIGHT", drawer.banner, "RIGHT", -8, 0)

    drawer.freshnessText = drawer.banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.freshnessText:SetJustifyH("RIGHT")
    drawer.freshnessText:SetWordWrap(false)
    applyFont(drawer.freshnessText, 10, "regular")
    drawer.freshnessText:SetPoint("RIGHT", drawer.stabilityPill.frame, "LEFT", -8, 0)

    drawer.verdictHeadline = drawer.banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.verdictHeadline:SetJustifyH("LEFT")
    drawer.verdictHeadline:SetWordWrap(false)
    applyFont(drawer.verdictHeadline, compact and 10 or 11, "semibold")
    drawer.verdictHeadline:SetPoint("LEFT", drawer.verdictPill.frame, "RIGHT", 8, 0)
    drawer.verdictHeadline:SetPoint("RIGHT", drawer.freshnessText, "LEFT", -8, 0)

    -- 2. Controls Row (28px)
    drawer.controls = CreateFrame("Frame", nil, drawer)
    drawer.controls:SetHeight(28)

    local function makeSegmentedGroup(ctrlParent, defs, onPick)
        local track = CreateFrame("Frame", nil, ctrlParent)
        track:SetHeight(24)
        local trackBg = track:CreateTexture(nil, "BACKGROUND")
        trackBg:SetAllPoints(track)
        local btns = {}
        local ordered = {}
        local xOff = 2
        for _, def in ipairs(defs) do
            local btn = CreateFrame("Button", nil, track)
            local bw = def.width or 48
            btn:SetSize(bw, 20)
            btn:SetPoint("LEFT", track, "LEFT", xOff, 0)
            btn:EnableMouse(true)
            btn:RegisterForClicks("LeftButtonUp")
            btn._key = def.key
            btn._activeBg = btn:CreateTexture(nil, "BACKGROUND")
            btn._activeBg:SetAllPoints(btn)
            btn._activeBg:Hide()
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.text:SetWordWrap(false)
            applyFont(btn.text, 10, "semibold")
            btn.text:SetText(def.label)
            btn:SetScript("OnClick", function() onPick(def.key) end)
            btns[def.key] = btn
            ordered[#ordered + 1] = btn
            xOff = xOff + bw + 2
        end
        track:SetWidth(xOff)
        return track, trackBg, btns, ordered
    end

    drawer.metricTrack, drawer.metricTrackBg, drawer.metricBtns, drawer._metricOrdered = makeSegmentedGroup(
        drawer.controls,
        {
            { key = "avg", label = "Avg", width = 40 },
            { key = "min", label = "Min", width = 40 },
            { key = "supply", label = "Supply", width = 52 },
        },
        function(mode) drawer:SetMetric(mode) end
    )
    drawer.metricTrack:SetPoint("LEFT", drawer.controls, "LEFT", 0, 0)

    drawer.resTrack, drawer.resTrackBg, drawer.resBtns, drawer._resOrdered = makeSegmentedGroup(
        drawer.controls,
        {
            { key = "24h", label = "24h", width = 38 },
            { key = "12x2h", label = "12x2h", width = 48 },
        },
        function(res) drawer:SetResolution(res) end
    )
    drawer.resTrack:SetPoint("LEFT", drawer.metricTrack, "RIGHT", 8, 0)

    -- Optional compact Close + Deep Analysis > buttons on the right
    if opts.onClose then
        local closeBtn = CreateFrame("Button", nil, drawer.controls)
        closeBtn:SetSize(22, 22)
        closeBtn:SetPoint("RIGHT", drawer.controls, "RIGHT", 0, 0)
        closeBtn:EnableMouse(true)
        closeBtn:RegisterForClicks("LeftButtonUp")
        closeBtn._bg = closeBtn:CreateTexture(nil, "BACKGROUND")
        closeBtn._bg:SetAllPoints(closeBtn)
        closeBtn._icon = closeBtn:CreateTexture(nil, "ARTWORK")
        closeBtn._icon:SetSize(10, 10)
        closeBtn._icon:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
        closeBtn._icon:SetTexture(assetPath("icon_close"))
        closeBtn:SetScript("OnClick", function()
            if drawer._onClose then drawer._onClose() end
        end)
        drawer.closeBtn = closeBtn
    end

    if opts.onDeepAnalysis then
        local daBtn = CreateFrame("Button", nil, drawer.controls)
        daBtn:SetSize(112, 22)
        if drawer.closeBtn then
            daBtn:SetPoint("RIGHT", drawer.closeBtn, "LEFT", -6, 0)
        else
            daBtn:SetPoint("RIGHT", drawer.controls, "RIGHT", 0, 0)
        end
        daBtn:EnableMouse(true)
        daBtn:RegisterForClicks("LeftButtonUp")
        daBtn._bg = daBtn:CreateTexture(nil, "BACKGROUND")
        daBtn._bg:SetAllPoints(daBtn)
        daBtn.text = daBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        daBtn.text:SetPoint("CENTER", daBtn, "CENTER", 0, 0)
        daBtn.text:SetWordWrap(false)
        applyFont(daBtn.text, 10, "semibold")
        daBtn.text:SetText("Deep Analysis >")
        daBtn:SetScript("OnClick", function()
            if drawer._onDeepAnalysis then drawer._onDeepAnalysis(drawer._itemID) end
        end)
        drawer.deepAnalysisBtn = daBtn
    end

    -- Compact thermal legend
    drawer.legend = CreateFrame("Frame", nil, drawer.controls)
    drawer.legend:SetHeight(20)
    drawer.legend:SetWidth(134)
    if drawer.deepAnalysisBtn then
        drawer.legend:SetPoint("RIGHT", drawer.deepAnalysisBtn, "LEFT", -10, 0)
    elseif drawer.closeBtn then
        drawer.legend:SetPoint("RIGHT", drawer.closeBtn, "LEFT", -10, 0)
    else
        drawer.legend:SetPoint("RIGHT", drawer.controls, "RIGHT", 0, 0)
    end
    drawer.legendLow = drawer.legend:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.legendLow:SetPoint("LEFT", drawer.legend, "LEFT", 0, 0)
    drawer.legendLow:SetWordWrap(false)
    applyFont(drawer.legendLow, 10, "regular")
    drawer.legendLow:SetText("Low")

    drawer.legendSwatches = {}
    for i = 1, 6 do
        local sw = drawer.legend:CreateTexture(nil, "ARTWORK")
        sw:SetSize(11, 8)
        sw:SetPoint("LEFT", drawer.legend, "LEFT", 32 + (i - 1) * 12, 0)
        drawer.legendSwatches[i] = sw
    end

    drawer.legendHigh = drawer.legend:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.legendHigh:SetPoint("LEFT", drawer.legend, "LEFT", 106, 0)
    drawer.legendHigh:SetWordWrap(false)
    applyFont(drawer.legendHigh, 10, "regular")
    drawer.legendHigh:SetText("High")

    -- 3. 7x24 Day x Hour Matrix
    drawer.matrixFrame = CreateFrame("Frame", nil, drawer)
    drawer.weekendBgs = {}
    for dow = 6, 7 do
        local wbg = drawer.matrixFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        drawer.weekendBgs[dow] = wbg
    end

    drawer.dayLabels = {}
    drawer.dayAvgLabels = {}
    for dow = 1, 7 do
        local dl = drawer.matrixFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dl:SetJustifyH("RIGHT")
        dl:SetWordWrap(false)
        applyFont(dl, compact and 10 or 11, (dow >= 6) and "semibold" or "regular")
        dl:SetText(DOW_LABELS[dow])
        drawer.dayLabels[dow] = dl

        local avgLbl = drawer.matrixFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        avgLbl:SetJustifyH("RIGHT")
        avgLbl:SetWordWrap(false)
        applyFont(avgLbl, compact and 10 or 11, "regular")
        drawer.dayAvgLabels[dow] = avgLbl
    end

    drawer.dayAvgHeader = drawer.matrixFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.dayAvgHeader:SetJustifyH("RIGHT")
    drawer.dayAvgHeader:SetWordWrap(false)
    applyFont(drawer.dayAvgHeader, 10, "semibold")
    drawer.dayAvgHeader:SetText("Day Avg")

    drawer.gridArea = CreateFrame("Frame", nil, drawer.matrixFrame)
    drawer.hourHeaders = {}
    for _, hTick in ipairs(HOUR_TICKS) do
        local hl = drawer.matrixFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hl:SetJustifyH("CENTER")
        hl:SetWordWrap(false)
        applyFont(hl, 10, "regular")
        hl:SetText(string.format("%02d", hTick))
        drawer.hourHeaders[hTick] = hl
    end

    drawer.nowHourPill = createBadge(drawer.matrixFrame, 16, 9)

    -- 168 pooled Texture quads (ZERO per-cell CreateFrame)
    drawer.cells = {}
    for dow = 1, 7 do
        drawer.cells[dow] = {}
        for hour = 0, 23 do
            local quad = drawer.gridArea:CreateTexture(nil, "ARTWORK", nil, 0)
            drawer.cells[dow][hour] = quad
        end
    end

    -- Hover column highlight + hover cell ring + 4-edge Now ring
    drawer.colHighlight = drawer.gridArea:CreateTexture(nil, "ARTWORK", nil, 2)
    drawer.colHighlight:Hide()
    drawer.hoverRing = makeBorderRing(drawer.gridArea, "OVERLAY", 1)
    hideRing(drawer.hoverRing)
    drawer.nowRing = makeBorderRing(drawer.gridArea, "OVERLAY", 3)
    hideRing(drawer.nowRing)

    -- Single mouse hit overlay covering the entire 7x24 grid
    drawer.hitOverlay = CreateFrame("Frame", nil, drawer.gridArea)
    drawer.hitOverlay:SetAllPoints(drawer.gridArea)
    drawer.hitOverlay:EnableMouse(true)

    local function cellFromCursor()
        if not _G.GetCursorPosition or not drawer.gridArea.GetLeft or not drawer.gridArea.GetTop then
            return nil, nil
        end
        local cx, cy = _G.GetCursorPosition()
        if type(cx) ~= "number" or type(cy) ~= "number" then return nil, nil end
        local scale = (drawer.gridArea.GetEffectiveScale and drawer.gridArea:GetEffectiveScale()) or 1
        if not scale or scale == 0 then scale = 1 end
        local left = drawer.gridArea:GetLeft()
        local top = drawer.gridArea:GetTop()
        local gw = drawer._gridW or (drawer.gridArea.GetWidth and drawer.gridArea:GetWidth()) or 0
        local gh = drawer._gridH or (drawer.gridArea.GetHeight and drawer.gridArea:GetHeight()) or 0
        if type(left) ~= "number" or type(top) ~= "number" or gw <= 0 or gh <= 0 then return nil, nil end
        local rx = (cx / scale) - left
        local ry = top - (cy / scale)
        if rx < 0 or rx > gw or ry < 0 or ry > gh then return nil, nil end
        local hour = math.max(0, math.min(23, math.floor((rx / gw) * 24)))
        local dow = math.max(1, math.min(7, math.floor((ry / gh) * 7) + 1))
        return dow, hour
    end

    local hoverPollGen = 0
    local function startHoverPoll()
        hoverPollGen = hoverPollGen + 1
        local gen = hoverPollGen
        local function pollMatrixCursor()
            if gen ~= hoverPollGen or not drawer.hitOverlay._hovering or not drawer:IsShown() then return end
            local dow, hour = cellFromCursor()
            if dow and hour ~= nil then
                if dow ~= drawer._hoverDow or hour ~= drawer._hoverHour then
                    drawer:SimulateHover(dow, hour)
                end
            end
            if gen == hoverPollGen and drawer.hitOverlay._hovering and drawer:IsShown()
                and _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.05, pollMatrixCursor)
            end
        end
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.05, pollMatrixCursor)
        end
    end

    drawer.hitOverlay:SetScript("OnEnter", function(self)
        self._hovering = true
        local dow, hour = cellFromCursor()
        if dow and hour ~= nil then
            drawer:SimulateHover(dow, hour)
        end
        startHoverPoll()
    end)
    drawer.hitOverlay:SetScript("OnLeave", function(self)
        self._hovering = false
        hoverPollGen = hoverPollGen + 1
        drawer:SimulateHover(nil, nil)
    end)
    drawer.hitOverlay:SetScript("OnHide", function(self)
        self._hovering = false
        hoverPollGen = hoverPollGen + 1
        if drawer._hoverDow ~= nil or drawer._hoverHour ~= nil then
            drawer:SimulateHover(nil, nil)
        end
    end)

    -- 4. Column-Aligned 24-Hour Average Curve (124px, when showCurve ~= false)
    drawer.curveFrame = CreateFrame("Frame", nil, drawer)
    drawer.curveTitle = drawer.curveFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.curveTitle:SetJustifyH("LEFT")
    drawer.curveTitle:SetWordWrap(false)
    applyFont(drawer.curveTitle, 10, "semibold")
    drawer.curveTitle:SetText("24h Average Curve")

    drawer.curveHoverReadout = drawer.curveFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.curveHoverReadout:SetJustifyH("RIGHT")
    drawer.curveHoverReadout:SetWordWrap(false)
    applyFont(drawer.curveHoverReadout, 10, "semibold")
    drawer.curveHoverReadout:Hide()

    drawer.curvePlot = CreateFrame("Frame", nil, drawer.curveFrame)
    drawer.curvePlotBg = drawer.curvePlot:CreateTexture(nil, "BACKGROUND", nil, -2)
    drawer.curvePlotBg:SetAllPoints(drawer.curvePlot)

    drawer.curveYGrids = {}
    drawer.curveYLabels = {}
    drawer.curveGlowLines = {}
    drawer.curveLines = {}
    drawer.curveDots = {}
    drawer.curveHits = {}

    for i = 1, 23 do
        if drawer.curvePlot.CreateLine then
            local glow = drawer.curvePlot:CreateLine(nil, "ARTWORK", nil, 0)
            glow:Hide()
            drawer.curveGlowLines[i] = glow
            local line = drawer.curvePlot:CreateLine(nil, "ARTWORK", nil, 1)
            line:Hide()
            drawer.curveLines[i] = line
        end
    end

    for hIdx = 0, 23 do
        local dot = drawer.curvePlot:CreateTexture(nil, "ARTWORK", nil, 2)
        dot:SetSize(5, 5)
        dot:SetTexture(assetPath("circle_fill"))
        dot:Hide()
        drawer.curveDots[hIdx] = dot

        local hit = CreateFrame("Button", nil, drawer.curvePlot)
        hit:EnableMouse(true)
        hit._hour = hIdx
        hit:SetScript("OnEnter", function(btn)
            drawer:SimulateCurveHover(btn._hour)
        end)
        hit:SetScript("OnLeave", function()
            drawer:SimulateCurveHover(nil)
        end)
        drawer.curveHits[hIdx] = hit
    end

    drawer.curveAvgLine = drawer.curvePlot:CreateTexture(nil, "BORDER")
    drawer.curveAvgLine:Hide()

    drawer.curveAvgLabel = drawer.curveFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.curveAvgLabel:SetJustifyH("LEFT")
    drawer.curveAvgLabel:SetWordWrap(false)
    applyFont(drawer.curveAvgLabel, 10, "regular")
    drawer.curveAvgLabel:Hide()

    drawer.curveHoverLine = drawer.curvePlot:CreateTexture(nil, "OVERLAY", nil, 1)
    drawer.curveHoverLine:SetWidth(1)
    drawer.curveHoverLine:Hide()

    drawer.curveHoverDot = drawer.curvePlot:CreateTexture(nil, "OVERLAY", nil, 2)
    drawer.curveHoverDot:SetSize(8, 8)
    drawer.curveHoverDot:SetTexture(assetPath("circle_fill"))
    drawer.curveHoverDot:Hide()

    if not showCurve then
        drawer.curveFrame:Hide()
    end

    -- 5. Graceful Empty State + Fallback Chart Container
    drawer.emptyFrame = CreateFrame("Frame", nil, drawer)
    drawer.emptyText = drawer.emptyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    drawer.emptyText:SetJustifyH("CENTER")
    drawer.emptyText:SetWordWrap(true)
    applyFont(drawer.emptyText, compact and 11 or 12, "regular")
    drawer.emptyFrame:Hide()

    -- Internal helpers
    function drawer:_getCellForMetric(dow, hour)
        local hm = self._heatmap
        if not hm or not hm.cells or not hm.cells[dow] then return nil end
        local overallAvg = hm.overall and hm.overall.avgPrice or 0
        if self._resolution == "12x2h" then
            local bStart = math.floor(hour / 2) * 2
            return mergeTwoHourCell(hm.cells[dow][bStart], hm.cells[dow][bStart + 1], overallAvg)
        end
        return hm.cells[dow][hour]
    end

    function drawer:_cellColorArgs(cell)
        if not cell then return nil, nil end
        local hm = self._heatmap
        local overall = hm and hm.overall or {}
        if self._metric == "min" then
            local ref = (overall.avgPrice and overall.avgPrice > 0) and overall.avgPrice or overall.minPrice
            local pct = (ref and ref > 0 and cell.minPrice) and (((cell.minPrice - ref) / ref) * 100) or cell.pctVsAvg
            return pct, nil
        elseif self._metric == "supply" then
            local overallQty = math.max(1, tonumber(overall.avgQty) or 1)
            local ratio = (tonumber(cell.avgQty) or 0) / overallQty
            return cell.pctVsAvg, ratio
        end
        return cell.pctVsAvg, nil
    end

    function drawer:_getCurvePointValue(hour)
        local hm = self._heatmap
        if not hm or not hm.hourly then return nil, nil end
        local overall = hm.overall or {}
        local slot
        if self._resolution == "12x2h" then
            local bStart = math.floor(hour / 2) * 2
            slot = mergeTwoHourCell(hm.hourly[bStart], hm.hourly[bStart + 1], overall.avgPrice)
        else
            slot = hm.hourly[hour]
        end
        if not slot then return nil, nil end
        if self._metric == "min" then
            return slot.minPrice or slot.avgPrice, slot
        elseif self._metric == "supply" then
            return slot.avgQty, slot
        end
        return slot.avgPrice, slot
    end

    function drawer:_paintMatrixColumnHighlight(hour)
        if hour == nil or not self._gridW or not self._gridH then
            self.colHighlight:Hide()
            return
        end
        local p = fullPalette()
        local x, w
        if self._resolution == "12x2h" then
            local bucket = math.floor(hour / 2)
            local bw = self._gridW / 12
            x = bucket * bw
            w = math.max(2, bw - 1)
        else
            local cw = self._gridW / 24
            x = hour * cw
            w = math.max(2, cw - 1)
        end
        self.colHighlight:ClearAllPoints()
        self.colHighlight:SetPoint("TOPLEFT", self.gridArea, "TOPLEFT", x, 0)
        self.colHighlight:SetSize(w, math.max(1, self._gridH))
        if p.mode == "light" then
            self.colHighlight:SetColorTexture(0, 0, 0, 0.08)
        else
            self.colHighlight:SetColorTexture(1, 1, 1, 0.14)
        end
        self.colHighlight:Show()
    end

    function drawer:_highlightCurveHour(hour)
        if not self._showCurve or not self._heatmap or hour == nil then
            self.curveHoverLine:Hide()
            self.curveHoverDot:Hide()
            self.curveHoverReadout:Hide()
            return
        end
        local p = fullPalette()
        local plotW = self._gridW or 1
        local plotH = self._curvePlotH or 1
        local displayHour = (self._resolution == "12x2h") and (math.floor(hour / 2) * 2) or hour
        local x
        if self._resolution == "12x2h" then
            x = (math.floor(hour / 2) + 0.5) * (plotW / 12)
        else
            x = (hour + 0.5) * (plotW / 24)
        end
        local accent = p.accentOrange
        self.curveHoverLine:ClearAllPoints()
        self.curveHoverLine:SetPoint("BOTTOMLEFT", self.curvePlot, "BOTTOMLEFT", x, 0)
        self.curveHoverLine:SetSize(1, math.max(1, plotH))
        self.curveHoverLine:SetColorTexture(accent[1], accent[2], accent[3], 0.85)
        self.curveHoverLine:Show()

        local val = self:_getCurvePointValue(displayHour)
        local lo = self._curveLo or 0
        local hi = self._curveHi or 1
        local overall = self._heatmap.overall or {}
        if val ~= nil and hi > lo then
            local y = clamp01((val - lo) / (hi - lo)) * plotH
            self.curveHoverDot:ClearAllPoints()
            self.curveHoverDot:SetPoint("BOTTOMLEFT", self.curvePlot, "BOTTOMLEFT", x - 4, y - 4)
            self.curveHoverDot:SetVertexColor(accent[1], accent[2], accent[3], 1)
            self.curveHoverDot:Show()

            local hourSpan = (self._resolution == "12x2h")
                and string.format("%02d:00-%02d:00", displayHour, displayHour + 2)
                or string.format("%02d:00", displayHour)
            local valTxt, pctTxt
            if self._metric == "supply" then
                valTxt = formatCompactQty(val) .. " qty"
                local refQ = math.max(1, tonumber(overall.avgQty) or 1)
                pctTxt = formatSignedPct(((val - refQ) / refQ) * 100)
            else
                valTxt = formatMoneyPartsText(val, false, p)
                local refP = tonumber(overall.avgPrice) or 0
                pctTxt = (refP > 0) and formatSignedPct(((val - refP) / refP) * 100) or "—"
            end
            self.curveHoverReadout:SetText(string.format("%s · %s (%s vs avg)", hourSpan, valTxt, pctTxt))
            setColor(self.curveHoverReadout, p.text)
            self.curveHoverReadout:Show()
        else
            self.curveHoverDot:Hide()
            self.curveHoverReadout:SetText(string.format("%02d:00 · No data", displayHour))
            setColor(self.curveHoverReadout, p.textMuted)
            self.curveHoverReadout:Show()
        end
    end

    function drawer:SimulateCurveHover(hour)
        if hour == nil or not self._heatmap then
            self._curveHoverHour = nil
            self:_highlightCurveHour(nil)
            if self._hoverDow == nil then
                self:_paintMatrixColumnHighlight(nil)
            end
            if GameTooltip and self._tooltipOwner == self.curvePlot then
                GameTooltip:Hide()
                self._tooltipOwner = nil
            end
            return false
        end
        hour = math.max(0, math.min(23, math.floor(tonumber(hour) or 0)))
        self._curveHoverHour = hour
        self._hoverDow = nil
        self._hoverHour = nil
        hideRing(self.hoverRing)
        self:_paintMatrixColumnHighlight(hour)
        self:_highlightCurveHour(hour)
        if GameTooltip then
            local p = fullPalette()
            local displayHour = (self._resolution == "12x2h") and (math.floor(hour / 2) * 2) or hour
            local endHour = (self._resolution == "12x2h") and (displayHour + 2) or (displayHour + 1)
            local _, slot = self:_getCurvePointValue(displayHour)
            local overall = self._heatmap.overall or {}
            self._tooltipOwner = self.curvePlot
            GameTooltip:SetOwner(self.curveHits[hour] or self.curvePlot, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(string.format("All Days %02d:00 - %02d:00", displayHour, endHour), 0.36, 0.72, 1.0)
            if slot then
                GameTooltip:AddDoubleLine("Avg Price", formatMoneyPartsText(slot.avgPrice, false, p), 0.82, 0.82, 0.86, 1, 1, 1)
                GameTooltip:AddDoubleLine("Min Price", formatMoneyPartsText(slot.minPrice, false, p), 0.82, 0.82, 0.86, 1, 1, 1)
                local refP = tonumber(overall.avgPrice) or 0
                local pct = (refP > 0 and slot.avgPrice) and (((slot.avgPrice - refP) / refP) * 100) or 0
                GameTooltip:AddDoubleLine("vs Weekly Avg", formatSignedPct(pct), 0.82, 0.82, 0.86, 1, 1, 1)
                GameTooltip:AddDoubleLine("Avg Supply", formatCompactQty(slot.avgQty), 0.82, 0.82, 0.86, 1, 1, 1)
                GameTooltip:AddDoubleLine("Samples", tostring(slot.samples or 0), 0.82, 0.82, 0.86, 1, 1, 1)
            else
                GameTooltip:AddLine("No data recorded for this hour", 0.65, 0.65, 0.70)
            end
            local h = H()
            if h and h.Theme and h.Theme.LiftTooltip then h.Theme.LiftTooltip(GameTooltip) end
            GameTooltip:Show()
        end
        return true
    end

    function drawer:SimulateHover(dow, hour)
        if dow == nil or hour == nil or not self._heatmap then
            self._hoverDow = nil
            self._hoverHour = nil
            hideRing(self.hoverRing)
            self:_paintMatrixColumnHighlight(nil)
            self:_highlightCurveHour(nil)
            if GameTooltip and self._tooltipOwner == self.hitOverlay then
                GameTooltip:Hide()
                self._tooltipOwner = nil
            end
            return false
        end
        dow = math.max(1, math.min(7, math.floor(tonumber(dow) or 1)))
        hour = math.max(0, math.min(23, math.floor(tonumber(hour) or 0)))
        self._hoverDow = dow
        self._hoverHour = hour
        self._curveHoverHour = nil

        self:_paintMatrixColumnHighlight(hour)
        if self._gridW and self._gridH then
            local p = fullPalette()
            local rowH = self._gridH / 7
            local yTop = (dow - 1) * rowH
            local x, w
            if self._resolution == "12x2h" then
                local bucket = math.floor(hour / 2)
                local bw = self._gridW / 12
                x = bucket * bw
                w = math.max(2, bw - 1)
            else
                local cw = self._gridW / 24
                x = hour * cw
                w = math.max(2, cw - 1)
            end
            local ink = p.text
            setRingRect(self.hoverRing, self.gridArea, x, yTop, w, math.max(2, rowH - 1), 1, ink[1], ink[2], ink[3], 0.90)
        end

        self:_highlightCurveHour(hour)

        if GameTooltip then
            local p = fullPalette()
            local displayHour = (self._resolution == "12x2h") and (math.floor(hour / 2) * 2) or hour
            local endHour = (self._resolution == "12x2h") and (displayHour + 2) or (displayHour + 1)
            local cell = self:_getCellForMetric(dow, hour)
            self._tooltipOwner = self.hitOverlay
            GameTooltip:SetOwner(self.hitOverlay, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(string.format("%s %02d:00 - %02d:00", DOW_LABELS[dow] or "?", displayHour, endHour), 0.36, 0.72, 1.0)
            if cell then
                GameTooltip:AddDoubleLine("Avg Price", formatMoneyPartsText(cell.avgPrice, false, p), 0.82, 0.82, 0.86, 1, 1, 1)
                GameTooltip:AddDoubleLine("Min Price", formatMoneyPartsText(cell.minPrice, false, p), 0.82, 0.82, 0.86, 1, 1, 1)
                local pct = cell.pctVsAvg or 0
                local pr, pg, pb = 0.88, 0.88, 0.92
                if pct <= -5 then pr, pg, pb = 0.19, 0.82, 0.35
                elseif pct >= 5 then pr, pg, pb = 1.00, 0.57, 0.19 end
                GameTooltip:AddDoubleLine("vs Weekly Avg", formatSignedPct(pct), 0.82, 0.82, 0.86, pr, pg, pb)
                GameTooltip:AddDoubleLine("Avg Supply", formatCompactQty(cell.avgQty), 0.82, 0.82, 0.86, 1, 1, 1)
                GameTooltip:AddDoubleLine("Samples", tostring(cell.samples or 0), 0.82, 0.82, 0.86, 1, 1, 1)
            else
                GameTooltip:AddLine("No data recorded for this hour", 0.65, 0.65, 0.70)
            end
            local h = H()
            if h and h.Theme and h.Theme.LiftTooltip then h.Theme.LiftTooltip(GameTooltip) end
            GameTooltip:Show()
        end
        return true
    end

    function drawer:_renderBanner(p)
        local hm = self._heatmap
        if p.mode == "light" then
            self.bannerBg:SetColorTexture(0.949, 0.949, 0.969, 0.92)
        else
            local alt = p.cardAltBg or { 0.12, 0.12, 0.14, 1.0 }
            self.bannerBg:SetColorTexture(alt[1], alt[2], alt[3], 0.75)
        end

        if not hm then
            self.verdictPill:Set("neutral", "LIMITED DATA", p, 14, 84)
            self.stabilityPill.frame:Hide()
            self.freshnessText:SetText("")
            self.verdictHeadline:SetText("No hourly auction timing data loaded")
            setColor(self.verdictHeadline, p.textSecondary)
            return
        end

        local nowDow, nowHour = nowIsoDowAndHour(self._nowOverride)
        local overall = hm.overall or {}
        local overallAvg = tonumber(overall.avgPrice) or 0
        local curCell = hm.cells and hm.cells[nowDow] and hm.cells[nowDow][nowHour]
        local curPct
        if curCell and curCell.pctVsAvg ~= nil then
            curPct = curCell.pctVsAvg
        elseif hm.hourly and hm.hourly[nowHour] and hm.hourly[nowHour].avgPrice and overallAvg > 0 then
            curPct = ((hm.hourly[nowHour].avgPrice - overallAvg) / overallAvg) * 100
        end

        local totalSamples = tonumber(overall.totalSamples) or 0
        local verdictText, verdictVar
        if totalSamples < 4 or curPct == nil then
            verdictText, verdictVar = "LIMITED DATA", "neutral"
        elseif curPct <= -5 then
            verdictText, verdictVar = "BUY WINDOW", "positive"
        elseif curPct >= 5 then
            verdictText, verdictVar = "SELL WINDOW", "hot"
        else
            verdictText, verdictVar = "FAIR PRICE", "blue"
        end
        self.verdictPill:Set(verdictVar, verdictText, p, 14, 84)

        local cvPct = tonumber(overall.cvPct) or 0
        local stabText, stabVar
        if totalSamples < 12 then
            stabText, stabVar = "Recent", "neutral"
        elseif cvPct <= 12 then
            stabText, stabVar = "Steady", "positive"
        else
            stabText, stabVar = "Volatile", "warning"
        end
        self.stabilityPill.frame:Show()
        self.stabilityPill:Set(stabVar, stabText, p, 12, 52)

        local src = tostring(hm.source or "snapshot")
        local winDays = tonumber(hm.windowDays) or 30
        self.freshnessText:SetText(string.format("%s · %dd", src, winDays))
        setColor(self.freshnessText, p.textMuted)

        local headlineParts = {}
        if curPct ~= nil then
            local pctHex = (curPct <= -5) and palHex("hexPositive", p, "30d158")
                or ((curPct >= 5) and palHex("hexWarning", p, "ff9230") or palHex("hexText", p, "ffffff"))
            headlineParts[#headlineParts + 1] = string.format("Now %s %02d:00 · %s%s|r vs avg",
                DOW_LABELS[nowDow], nowHour, pctHex, formatSignedPct(curPct))
        else
            headlineParts[#headlineParts + 1] = string.format("Now %s %02d:00 · No sample", DOW_LABELS[nowDow], nowHour)
        end
        if hm.bestBuy and hm.bestBuy.dow and hm.bestBuy.hour ~= nil then
            local bb = hm.bestBuy
            local bbPct = (bb.pctVsAvg ~= nil) and string.format(" (%s)", formatSignedPct(bb.pctVsAvg)) or ""
            headlineParts[#headlineParts + 1] = string.format("Best Buy %s %02d:00%s", DOW_LABELS[bb.dow] or "?", bb.hour, bbPct)
        end
        if hm.bestSell and hm.bestSell.dow and hm.bestSell.hour ~= nil then
            local bs = hm.bestSell
            local bsPct = (bs.pctVsAvg ~= nil) and string.format(" (%s)", formatSignedPct(bs.pctVsAvg)) or ""
            headlineParts[#headlineParts + 1] = string.format("Best Sell %s %02d:00%s", DOW_LABELS[bs.dow] or "?", bs.hour, bsPct)
        end
        self.verdictHeadline:SetText(table.concat(headlineParts, " · "))
        setColor(self.verdictHeadline, p.text)
    end

    function drawer:_renderControls(p)
        local track = p.pillTrack
        local thumb = p.pillThumb
        self.metricTrackBg:SetColorTexture(track[1], track[2], track[3], track[4] or 0.08)
        self.resTrackBg:SetColorTexture(track[1], track[2], track[3], track[4] or 0.08)

        for _, btn in ipairs(self._metricOrdered) do
            local on = (btn._key == self._metric)
            btn._activeBg:SetShown(on)
            if on then
                btn._activeBg:SetColorTexture(thumb[1], thumb[2], thumb[3], thumb[4] or 0.2)
            end
            setColor(btn.text, on and p.text or p.textSecondary)
        end
        for _, btn in ipairs(self._resOrdered) do
            local on = (btn._key == self._resolution)
            btn._activeBg:SetShown(on)
            if on then
                btn._activeBg:SetColorTexture(thumb[1], thumb[2], thumb[3], thumb[4] or 0.2)
            end
            setColor(btn.text, on and p.text or p.textSecondary)
        end

        if self._metric == "supply" then
            self.legendLow:SetText("High")
            self.legendHigh:SetText("Low")
        else
            self.legendLow:SetText("Low")
            self.legendHigh:SetText("High")
        end
        setColor(self.legendLow, p.textMuted)
        setColor(self.legendHigh, p.textMuted)
        local samplePcts = { -20, -10, 0, 10, 22, 36 }
        local sampleRatios = { 1.6, 1.3, 1.0, 0.7, 0.4, 0.1 }
        for i = 1, 6 do
            local r, g, b, a = Chart.HeatmapCellColor(samplePcts[i], self._metric, p, false, sampleRatios[i])
            self.legendSwatches[i]:SetColorTexture(r, g, b, a)
        end

        if self.deepAnalysisBtn then
            local fill, ink = heatmapBadgeStyle("blue", p)
            self.deepAnalysisBtn._bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 0.16)
            setColor(self.deepAnalysisBtn.text, ink)
        end
        if self.closeBtn then
            self.closeBtn._bg:SetColorTexture(track[1], track[2], track[3], track[4] or 0.08)
            self.closeBtn._icon:SetVertexColor(p.textSecondary[1], p.textSecondary[2], p.textSecondary[3], p.textSecondary[4] or 0.85)
        end
    end

    function drawer:_renderMatrix(p)
        local hm = self._heatmap
        if not hm then return end
        local nowDow, nowHour = nowIsoDowAndHour(self._nowOverride)
        local is12 = (self._resolution == "12x2h")
        local gridW = self._gridW or 240
        local gridH = self._gridH or 120
        local rowH = gridH / 7
        local gap = self._compact and 1 or 2

        -- Weekend row tints (Sat = 6, Sun = 7)
        for dow = 6, 7 do
            local wbg = self.weekendBgs[dow]
            if p.mode == "light" then
                wbg:SetColorTexture(0.000, 0.384, 0.800, 0.055)
            else
                wbg:SetColorTexture(p.accentBlue[1], p.accentBlue[2], p.accentBlue[3], 0.075)
            end
            wbg:Show()
        end

        -- Day labels & right-hand Day Avg / Min / Avg Qty column
        self.dayAvgHeader:SetText(self._metric == "supply" and "Avg Qty" or (self._metric == "min" and "Day Min" or "Day Avg"))
        setColor(self.dayAvgHeader, p.textMuted)

        for dow = 1, 7 do
            setColor(self.dayLabels[dow], (dow >= 6) and p.text or p.textSecondary)
            local d = hm.daily and hm.daily[dow]
            local avgLbl = self.dayAvgLabels[dow]
            if d then
                if self._metric == "supply" then
                    avgLbl:SetText(formatCompactQty(d.avgQty))
                    setColor(avgLbl, p.text)
                elseif self._metric == "min" then
                    avgLbl:SetText(formatMoneyPartsText(d.minPrice, false, p))
                    setColor(avgLbl, p.text)
                else
                    avgLbl:SetText(formatMoneyPartsText(d.avgPrice, false, p))
                    setColor(avgLbl, p.text)
                end
            else
                avgLbl:SetText("—")
                setColor(avgLbl, p.textMuted)
            end
        end

        -- Hour header ticks + green Now pill
        local colW24 = gridW / 24
        local nowCenterX = (is12 and (math.floor(nowHour / 2) + 0.5) * (gridW / 12) or (nowHour + 0.5) * colW24)
        self.nowHourPill:Set("positive", string.format("%02d", nowHour), p, 8, 22)
        self.nowHourPill.frame:ClearAllPoints()
        self.nowHourPill.frame:SetPoint("BOTTOM", self.gridArea, "TOPLEFT", nowCenterX, 2)
        self.nowHourPill.frame:Show()

        for _, hTick in ipairs(HOUR_TICKS) do
            local hl = self.hourHeaders[hTick]
            local hx = (hTick + 0.5) * colW24
            hl:ClearAllPoints()
            hl:SetPoint("BOTTOM", self.gridArea, "TOPLEFT", hx, 3)
            setColor(hl, p.textMuted)
            hl:SetShown(math.abs(hx - nowCenterX) >= 22)
        end

        -- Paint 168 pooled quads (hiding odd columns in 12x2h mode while widening even columns)
        local overallAvg = hm.overall and hm.overall.avgPrice or 0
        for dow = 1, 7 do
            local isWeekend = (dow == 6 or dow == 7)
            local yTop = (dow - 1) * rowH
            local cellH = math.max(2, rowH - gap)
            for hour = 0, 23 do
                local quad = self.cells[dow][hour]
                if is12 and (hour % 2 == 1) then
                    quad:Hide()
                else
                    local x, cellW, cell
                    if is12 then
                        local bucket = math.floor(hour / 2)
                        local bw = gridW / 12
                        x = bucket * bw
                        cellW = math.max(2, bw - gap)
                        cell = mergeTwoHourCell(hm.cells and hm.cells[dow] and hm.cells[dow][hour],
                            hm.cells and hm.cells[dow] and hm.cells[dow][hour + 1], overallAvg)
                    else
                        x = hour * colW24
                        cellW = math.max(2, colW24 - gap)
                        cell = hm.cells and hm.cells[dow] and hm.cells[dow][hour]
                    end
                    local pct, ratio = self:_cellColorArgs(cell)
                    local r, g, b, a = Chart.HeatmapCellColor(pct, self._metric, p, isWeekend, ratio)
                    quad:ClearAllPoints()
                    quad:SetPoint("TOPLEFT", self.gridArea, "TOPLEFT", x, -yTop)
                    quad:SetSize(cellW, cellH)
                    quad:SetColorTexture(r, g, b, a)
                    quad:Show()
                end
            end
        end

        -- 4-edge Now ring around (nowDow, nowHour)
        local nowY = (nowDow - 1) * rowH
        local nowX, nowW
        if is12 then
            local bucket = math.floor(nowHour / 2)
            local bw = gridW / 12
            nowX = bucket * bw
            nowW = math.max(2, bw - gap)
        else
            nowX = nowHour * colW24
            nowW = math.max(2, colW24 - gap)
        end
        local gc = p.accentGreen
        setRingRect(self.nowRing, self.gridArea, nowX, nowY, nowW, math.max(2, rowH - gap), 2, gc[1], gc[2], gc[3], 1.0)
    end

    function drawer:_renderCurve(p)
        if not self._showCurve or not self._heatmap then return end
        local hm = self._heatmap
        local overall = hm.overall or {}
        local is12 = (self._resolution == "12x2h")
        local plotW = self._gridW or 240
        local plotH = self._curvePlotH or 84
        local isMoney = (self._metric ~= "supply")

        self.curveTitle:SetText(self._metric == "supply" and "24h Average Supply Curve"
            or (self._metric == "min" and "24h Min Price Curve" or "24h Average Price Curve"))
        setColor(self.curveTitle, p.textSecondary)

        if p.mode == "light" then
            self.curvePlotBg:SetColorTexture(0.955, 0.955, 0.968, 0.85)
        else
            self.curvePlotBg:SetColorTexture(0.055, 0.059, 0.067, 0.78)
        end

        local vals = {}
        local lo, hi = nil, nil
        local stepHours = is12 and 2 or 1
        local count = 0
        for hIdx = 0, 23, stepHours do
            local v = self:_getCurvePointValue(hIdx)
            if v ~= nil then
                vals[hIdx] = v
                lo = math.min(lo or v, v)
                hi = math.max(hi or v, v)
                count = count + 1
            end
        end

        local refAvg = (self._metric == "supply") and tonumber(overall.avgQty) or tonumber(overall.avgPrice)
        if refAvg and refAvg > 0 then
            lo = math.min(lo or refAvg, refAvg)
            hi = math.max(hi or refAvg, refAvg)
        end

        for i = 1, #self.curveGlowLines do self.curveGlowLines[i]:Hide() end
        for i = 1, #self.curveLines do self.curveLines[i]:Hide() end
        for hIdx = 0, 23 do self.curveDots[hIdx]:Hide() end
        for _, g in ipairs(self.curveYGrids) do g:Hide() end
        for _, l in ipairs(self.curveYLabels) do l:Hide() end
        self.curveAvgLine:Hide()
        self.curveAvgLabel:Hide()

        if count == 0 then
            self._curveLo, self._curveHi = 0, 1
            return
        end

        local yLo, yHi, yTicks, yStep = computeNiceYAxis(lo, hi, plotH, isMoney)
        self._curveLo, self._curveHi = yLo, yHi
        local range = math.max(1e-6, yHi - yLo)

        for i, tv in ipairs(yTicks) do
            local frac = clamp01((tv - yLo) / range)
            local yPos = frac * plotH
            local gl = self.curveYGrids[i]
            if not gl then
                gl = self.curvePlot:CreateTexture(nil, "BACKGROUND")
                self.curveYGrids[i] = gl
            end
            gl:ClearAllPoints()
            gl:SetPoint("BOTTOMLEFT", self.curvePlot, "BOTTOMLEFT", 0, yPos)
            gl:SetSize(plotW, 1)
            gl:SetColorTexture(p.separator[1], p.separator[2], p.separator[3], (p.separator[4] or 0.4) * 0.36)
            gl:Show()

            local yl = self.curveYLabels[i]
            if not yl then
                yl = self.curveFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                yl:SetJustifyH("RIGHT")
                yl:SetWordWrap(false)
                applyFont(yl, 10, "regular")
                self.curveYLabels[i] = yl
            end
            yl:ClearAllPoints()
            local clampedY = math.max(5, math.min(plotH - 5, yPos))
            yl:SetPoint("RIGHT", self.curvePlot, "BOTTOMLEFT", -6, clampedY)
            yl:SetWidth(math.max(30, (self._dayColW or 48)))
            setColor(yl, p.textSecondary)
            yl:SetText(isMoney and formatAxisMoney(tv, yStep, p) or formatCompactQty(tv))
            yl:Show()
        end

        -- Weekly average horizontal reference line
        if refAvg and refAvg >= yLo and refAvg <= yHi then
            local avgY = clamp01((refAvg - yLo) / range) * plotH
            self.curveAvgLine:ClearAllPoints()
            self.curveAvgLine:SetPoint("BOTTOMLEFT", self.curvePlot, "BOTTOMLEFT", 0, avgY)
            self.curveAvgLine:SetSize(plotW, 1)
            local ac = p.accentGreen
            self.curveAvgLine:SetColorTexture(ac[1], ac[2], ac[3], 0.72)
            self.curveAvgLine:Show()

            self.curveAvgLabel:ClearAllPoints()
            self.curveAvgLabel:SetPoint("LEFT", self.curvePlot, "BOTTOMRIGHT", 6, math.max(5, math.min(plotH - 5, avgY)))
            self.curveAvgLabel:SetWidth(math.max(40, self._avgColW or 80))
            self.curveAvgLabel:SetText("Avg " .. (isMoney and formatAxisMoney(refAvg, yStep, p) or formatCompactQty(refAvg)))
            setColor(self.curveAvgLabel, p.textSecondary)
            self.curveAvgLabel:Show()
        end

        -- Draw pooled lines aligned 1:1 with matrix columns
        local lineCol = (self._metric == "supply") and p.accentPurple or p.accentBlue
        local r, g, b, a = lineCol[1], lineCol[2], lineCol[3], lineCol[4] or 1
        local glowAlpha = (p.mode == "light") and 0.10 or 0.18
        local prevX, prevY = nil, nil
        local segIdx = 0
        for hIdx = 0, 23, stepHours do
            local v = vals[hIdx]
            if v ~= nil then
                local x = is12 and ((math.floor(hIdx / 2) + 0.5) * (plotW / 12)) or ((hIdx + 0.5) * (plotW / 24))
                local y = clamp01((v - yLo) / range) * plotH
                if prevX ~= nil and self.curveLines[segIdx + 1] then
                    segIdx = segIdx + 1
                    local glow = self.curveGlowLines[segIdx]
                    applySmoothLine(glow, 7.0, r, g, b, glowAlpha)
                    glow:SetStartPoint("BOTTOMLEFT", prevX, prevY)
                    glow:SetEndPoint("BOTTOMLEFT", x, y)
                    glow:Show()

                    local line = self.curveLines[segIdx]
                    applySmoothLine(line, 2.8, r, g, b, a)
                    line:SetStartPoint("BOTTOMLEFT", prevX, prevY)
                    line:SetEndPoint("BOTTOMLEFT", x, y)
                    line:Show()
                end
                if not self.curvePlot.CreateLine or count == 1 then
                    local dot = self.curveDots[hIdx]
                    dot:ClearAllPoints()
                    dot:SetPoint("BOTTOMLEFT", self.curvePlot, "BOTTOMLEFT", x - 2.5, y - 2.5)
                    dot:SetVertexColor(r, g, b, a)
                    dot:Show()
                end
                prevX, prevY = x, y
            else
                prevX, prevY = nil, nil
            end
        end

        -- Position 24 hit strips aligned to matrix columns
        local colW24 = plotW / 24
        for hIdx = 0, 23 do
            local hit = self.curveHits[hIdx]
            hit:ClearAllPoints()
            hit:SetPoint("BOTTOMLEFT", self.curvePlot, "BOTTOMLEFT", hIdx * colW24, 0)
            hit:SetSize(math.max(1, colW24), math.max(1, plotH))
            hit:Show()
        end
    end

    function drawer:_renderEmpty(p)
        local h = H()
        local hasSnaps = (h and h.HasSnapshots and h.HasSnapshots()) or (h and h.app and h.app.snapshotExtension ~= nil)
        local meta = h and h.Pricing and h.Pricing.GetSnapshotMeta and h.Pricing.GetSnapshotMeta(self._econOverride)
        if meta ~= nil then
            self.emptyText:SetText("No hourly history recorded for this item yet")
        elseif not hasSnaps then
            self.emptyText:SetText("Live AH mode: scan the Auction House to build local price history.")
        else
            self.emptyText:SetText("No hourly snapshot data loaded for this economy yet.")
        end
        setColor(self.emptyText, p.textSecondary)

        local fbSeries = buildFallbackSeries(self._fallbackQuickLook)
        local emptyW = math.max(160, (self._innerW or 400))
        local emptyH = math.max(80, (self._emptyH or 180))
        if fbSeries and emptyH >= 130 then
            self.emptyText:ClearAllPoints()
            self.emptyText:SetPoint("TOPLEFT", self.emptyFrame, "TOPLEFT", 4, -4)
            self.emptyText:SetPoint("TOPRIGHT", self.emptyFrame, "TOPRIGHT", -4, -4)
            local fbH = math.max(100, emptyH - 28)
            if not self.fallbackChart then
                self.fallbackChart = Chart.CreateLineChart(self.emptyFrame, emptyW, fbH, {
                    title = "Recent Price History (Fallback)",
                })
            end
            self.fallbackChart:ClearAllPoints()
            self.fallbackChart:SetPoint("TOPLEFT", self.emptyFrame, "TOPLEFT", 0, -24)
            self.fallbackChart:Layout(emptyW, fbH, true)
            self.fallbackChart:SetData(fbSeries, { title = "Recent Price History (Fallback)" })
            self.fallbackChart:Show()
        else
            if self.fallbackChart then self.fallbackChart:Hide() end
            self.emptyText:ClearAllPoints()
            self.emptyText:SetPoint("CENTER", self.emptyFrame, "CENTER", 0, 0)
            self.emptyText:SetWidth(math.max(120, emptyW - 24))
        end
    end

    function drawer:_redraw()
        self._dirty = false
        local p = fullPalette()
        self:_renderBanner(p)
        self:_renderControls(p)
        local hasData = (self._heatmap ~= nil)
        self.controls:SetShown(hasData or (self.deepAnalysisBtn ~= nil) or (self.closeBtn ~= nil))
        self.metricTrack:SetShown(hasData)
        self.resTrack:SetShown(hasData)
        self.legend:SetShown(hasData and not self._hideLegendNarrow)
        self.matrixFrame:SetShown(hasData)
        self.curveFrame:SetShown(hasData and self._showCurve)
        self.emptyFrame:SetShown(not hasData)

        if hasData then
            self:_renderMatrix(p)
            if self._showCurve then
                self:_renderCurve(p)
            end
            if self._hoverDow and self._hoverHour ~= nil then
                self:SimulateHover(self._hoverDow, self._hoverHour)
            elseif self._curveHoverHour ~= nil then
                self:SimulateCurveHover(self._curveHoverHour)
            end
        else
            hideRing(self.nowRing)
            hideRing(self.hoverRing)
            self.colHighlight:Hide()
            self:_renderEmpty(p)
        end
    end

    function drawer:Layout(w, h, skipRedraw)
        w = math.max(260, tonumber(w) or (self.GetWidth and self:GetWidth()) or initW)
        h = math.max(160, tonumber(h) or (self.GetHeight and self:GetHeight()) or initH)
        local sameSize = (self._lastW == w and self._lastH == h)
        if not sameSize then
            self._lastW = w
            self._lastH = h
            self:SetSize(w, h)

            local padX = self._compact and 10 or 14
            local padTop = self._compact and 8 or 10
            local innerW = math.max(200, w - padX * 2)
            self._innerW = innerW

            -- Banner (38px)
            self.banner:ClearAllPoints()
            self.banner:SetPoint("TOPLEFT", self, "TOPLEFT", padX, -padTop)
            self.banner:SetSize(innerW, 38)

            -- Controls (28px)
            local ctrlY = padTop + 38 + 6
            self.controls:ClearAllPoints()
            self.controls:SetPoint("TOPLEFT", self, "TOPLEFT", padX, -ctrlY)
            self.controls:SetSize(innerW, 28)
            local rightBtnsW = (self.closeBtn and 22 or 0)
                + (self.deepAnalysisBtn and (112 + (self.closeBtn and 6 or 0)) or 0)
            self._hideLegendNarrow = (innerW - 240 - rightBtnsW) < 146

            -- Matrix & Curve vertical budget
            local bodyTop = ctrlY + 28 + 6
            local bodyH = math.max(100, h - bodyTop - padTop)
            local curveH = self._showCurve and math.min(124, math.max(88, math.floor(bodyH * 0.38))) or 0
            local gapMC = self._showCurve and 8 or 0
            local matrixH = math.max(84, bodyH - curveH - gapMC)
            if not self._showCurve then
                matrixH = math.min(bodyH, self._compact and 148 or 196)
            end

            local dayColW = self._compact and 34 or 52
            local avgColW = self._compact and 72 or 90
            local gridLeft = dayColW + 6
            local gridW = math.max(96, innerW - gridLeft - avgColW - 8)
            local headerH = 18
            local gridH = math.max(56, matrixH - headerH - 2)
            self._dayColW = dayColW
            self._avgColW = avgColW
            self._gridW = gridW
            self._gridH = gridH

            self.matrixFrame:ClearAllPoints()
            self.matrixFrame:SetPoint("TOPLEFT", self, "TOPLEFT", padX, -bodyTop)
            self.matrixFrame:SetSize(innerW, matrixH)

            self.gridArea:ClearAllPoints()
            self.gridArea:SetPoint("TOPLEFT", self.matrixFrame, "TOPLEFT", gridLeft, -headerH)
            self.gridArea:SetSize(gridW, gridH)

            self.dayAvgHeader:ClearAllPoints()
            self.dayAvgHeader:SetPoint("TOPRIGHT", self.matrixFrame, "TOPRIGHT", 0, -2)
            self.dayAvgHeader:SetWidth(avgColW)

            local rowH = gridH / 7
            for dow = 1, 7 do
                local yTop = headerH + (dow - 1) * rowH
                local dl = self.dayLabels[dow]
                dl:ClearAllPoints()
                dl:SetPoint("RIGHT", self.matrixFrame, "TOPLEFT", dayColW, -(yTop + rowH * 0.5))
                dl:SetWidth(dayColW)

                local al = self.dayAvgLabels[dow]
                al:ClearAllPoints()
                al:SetPoint("RIGHT", self.matrixFrame, "TOPRIGHT", 0, -(yTop + rowH * 0.5))
                al:SetWidth(avgColW)

                if dow >= 6 and self.weekendBgs[dow] then
                    local wbg = self.weekendBgs[dow]
                    wbg:ClearAllPoints()
                    wbg:SetPoint("TOPLEFT", self.matrixFrame, "TOPLEFT", 0, -yTop)
                    wbg:SetSize(innerW, math.max(2, rowH - 1))
                end
            end

            -- Curve aligned 1:1 with matrix columns (same gridLeft & gridW)
            if self._showCurve then
                local curveTop = bodyTop + matrixH + gapMC
                local curveTitleH = 18
                local curvePlotH = math.max(56, curveH - curveTitleH - 6)
                self._curvePlotH = curvePlotH
                self.curveFrame:ClearAllPoints()
                self.curveFrame:SetPoint("TOPLEFT", self, "TOPLEFT", padX, -curveTop)
                self.curveFrame:SetSize(innerW, curveH)

                self.curveTitle:ClearAllPoints()
                self.curveTitle:SetPoint("TOPLEFT", self.curveFrame, "TOPLEFT", gridLeft, -1)

                self.curveHoverReadout:ClearAllPoints()
                self.curveHoverReadout:SetPoint("TOPRIGHT", self.curveFrame, "TOPLEFT", gridLeft + gridW, -1)

                self.curvePlot:ClearAllPoints()
                self.curvePlot:SetPoint("TOPLEFT", self.curveFrame, "TOPLEFT", gridLeft, -curveTitleH)
                self.curvePlot:SetSize(gridW, curvePlotH)
            end

            -- Empty frame occupies body space
            self._emptyH = bodyH
            self.emptyFrame:ClearAllPoints()
            self.emptyFrame:SetPoint("TOPLEFT", self, "TOPLEFT", padX, -bodyTop)
            self.emptyFrame:SetSize(innerW, bodyH)
            self._dirty = true
        end

        if not skipRedraw and (not sameSize or self._dirty) then
            self:_redraw()
        end
    end

    function drawer:SetItem(itemID, heatmap, fallbackQuickLook, econOverride)
        self._itemID = itemID
        self._heatmap = (type(heatmap) == "table" and type(heatmap.cells) == "table") and heatmap or nil
        self._fallbackQuickLook = fallbackQuickLook
        self._econOverride = econOverride
        self._hoverDow = nil
        self._hoverHour = nil
        self._curveHoverHour = nil
        hideRing(self.hoverRing)
        self.colHighlight:Hide()
        self:_highlightCurveHour(nil)
        self:_redraw()
    end

    function drawer:SetMetric(mode)
        local m = (type(mode) == "string") and mode:lower() or "avg"
        if m ~= "avg" and m ~= "min" and m ~= "supply" then m = "avg" end
        self._metric = m
        self:_redraw()
    end

    function drawer:SetResolution(res)
        local r = (res == "12x2h") and "12x2h" or "24h"
        self._resolution = r
        self:_redraw()
    end

    function drawer:ApplyTheme()
        local p = fullPalette()
        applySurface(self, p)
        if self.fallbackChart and self.fallbackChart.ApplyTheme then
            self.fallbackChart:ApplyTheme()
        end
        self:_redraw()
    end

    function drawer:Clear()
        self._itemID = nil
        self._heatmap = nil
        self._fallbackQuickLook = nil
        self._econOverride = nil
        self:SimulateHover(nil, nil)
        self:SimulateCurveHover(nil)
        if self.fallbackChart then
            self.fallbackChart:Clear()
            self.fallbackChart:Hide()
        end
        self:_redraw()
    end

    local h = H()
    if h and h.Theme then
        if h.Theme.OnModeChanged then
            h.Theme.OnModeChanged(function() drawer:ApplyTheme() end)
        end
        if h.Theme.OnSkinChanged then
            h.Theme.OnSkinChanged(function() drawer:ApplyTheme() end)
        end
    end

    drawer:Layout(initW, initH, opts.skipInitialRedraw == true)
    return drawer
end

-- Weak-keyed 24-bar RGBA cache keyed by strip24h (never mutates caller/Pricing tables).
local heatStripBarCache = setmetatable({}, { __mode = "k" })

function Chart.CreateHeatStrip24h(parent, opts)
    opts = opts or {}
    local height = math.max(2, tonumber(opts.height) or 4)
    local showNowTick = (opts.showNowTick ~= false)

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(height)
    frame:Hide()

    local segments = {}
    for h = 0, 23 do
        local seg = frame:CreateTexture(nil, "ARTWORK", nil, 0)
        seg:Hide()
        segments[h] = seg
    end

    local nowTick = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    nowTick:Hide()

    local strip = {
        frame = frame,
        segments = segments,
        nowTick = nowTick,
        _height = height,
        _showNowTick = showNowTick,
        _width = nil,
        _laidOutWidth = nil,
        _laidOutNowHour = nil,
        _data = nil,
        _nowHour = nil,
        _pal = nil,
        _updatedAt = nil,
        _hasLiveOverlay = nil,
        _segsShown = false,
    }

    function strip:Bind(strip24h, pal, nowHour)
        if type(strip24h) ~= "table" or type(strip24h.hourly) ~= "table" then
            self:Clear()
            return
        end
        local palKey = pal
        if palKey == nil then
            local h = H()
            local theme = h and h.Theme
            palKey = (theme and theme.GetActivePalette and theme.GetActivePalette())
                or (theme and theme.GetMode and theme.GetMode())
                or "dark"
        end
        local updatedAt = strip24h.updatedAt
        local hasLive = strip24h.hasLiveOverlay
        if self._data == strip24h and self._pal == palKey and self._nowHour == nowHour
            and self._updatedAt == updatedAt and self._hasLiveOverlay == hasLive then
            return
        end
        local hourChanged = (self._nowHour ~= nowHour)
        self._data = strip24h
        self._pal = palKey
        self._nowHour = nowHour
        self._updatedAt = updatedAt
        self._hasLiveOverlay = hasLive

        local p = (type(pal) == "table" and pal._isFull) and pal or fullPalette(pal)
        local barKey = (p.mode or "dark") .. "|" .. tostring(p.skin or "standard")
        local avgP = strip24h.avgPrice
        local medP = strip24h.medianPrice
        local hourly = strip24h.hourly
        local altBg = p.cardAltBg
        local byStrip = heatStripBarCache[strip24h]
        local cached = byStrip and byStrip[barKey]
        local rgba
        if cached
            and cached.updatedAt == updatedAt
            and cached.hasLive == hasLive
            and cached.avgPrice == avgP
            and cached.medianPrice == medP
            and cached.hourly == hourly
            and cached.altBg == altBg then
            rgba = cached.rgba
        else
            local refPrice = tonumber(avgP)
            if not refPrice or refPrice <= 0 then
                refPrice = tonumber(medP)
            end
            if not refPrice or refPrice <= 0 then
                local sum, n = 0, 0
                for h = 0, 23 do
                    local raw = hourly[h]
                    local v = (type(raw) == "table") and tonumber(raw.avgPrice) or tonumber(raw)
                    if v and v > 0 then sum, n = sum + v, n + 1 end
                end
                if n > 0 then refPrice = sum / n end
            end
            rgba = (cached and cached.rgba) or {}
            for h = 0, 23 do
                local raw = hourly[h]
                local v = (type(raw) == "table") and tonumber(raw.avgPrice) or tonumber(raw)
                local pct
                if v and v > 0 and refPrice and refPrice > 0 then
                    pct = ((v - refPrice) / refPrice) * 100
                else
                    pct = nil
                end
                local r, g, b, a = Chart.HeatmapCellColor(pct, "avg", p, false, nil)
                local idx = h * 4
                rgba[idx + 1] = r
                rgba[idx + 2] = g
                rgba[idx + 3] = b
                rgba[idx + 4] = a
            end
            if not byStrip then
                byStrip = {}
                heatStripBarCache[strip24h] = byStrip
            end
            if not cached then
                cached = {}
                byStrip[barKey] = cached
            end
            cached.rgba = rgba
            cached.updatedAt = updatedAt
            cached.hasLive = hasLive
            cached.avgPrice = avgP
            cached.medianPrice = medP
            cached.hourly = hourly
            cached.altBg = altBg
        end

        local segs = self.segments
        local showSegs = not self._segsShown
        for h = 0, 23 do
            local idx = h * 4
            local seg = segs[h]
            seg:SetColorTexture(rgba[idx + 1], rgba[idx + 2], rgba[idx + 3], rgba[idx + 4])
            if showSegs then seg:Show() end
        end
        self._segsShown = true

        if self._showNowTick and type(nowHour) == "number" and nowHour >= 0 and nowHour <= 23 then
            if p.mode == "light" then
                self.nowTick:SetColorTexture(0.000, 0.478, 0.169, 1.0)
            else
                self.nowTick:SetColorTexture(1.000, 1.000, 1.000, 0.95)
            end
            self.nowTick:Show()
        else
            self.nowTick:Hide()
        end

        self.frame:Show()
        if self._width then
            local effHour = (self._showNowTick and type(nowHour) == "number" and nowHour >= 0 and nowHour <= 23)
                and math.floor(nowHour) or nil
            if self._laidOutWidth ~= self._width or (hourChanged and self._laidOutNowHour ~= effHour) then
                self:Layout(self._width)
            end
        end
    end

    function strip:Layout(width)
        width = math.max(24, tonumber(width) or self._width or 48)
        local nowHour = (self._showNowTick and type(self._nowHour) == "number" and self._nowHour >= 0 and self._nowHour <= 23 and self._data)
            and math.floor(self._nowHour) or nil
        if self._laidOutWidth == width and self._laidOutNowHour == nowHour then
            self._width = width
            return
        end
        self._width = width
        if self._laidOutWidth ~= width then
            self.frame:SetSize(width, self._height)
            for h = 0, 23 do
                local x0 = math.floor(h * width / 24)
                local x1 = math.floor((h + 1) * width / 24)
                local segW = math.max(1, x1 - x0)
                local seg = self.segments[h]
                seg:ClearAllPoints()
                seg:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x0, 0)
                seg:SetSize(segW, self._height)
            end
            self._laidOutWidth = width
        end
        if nowHour ~= nil then
            local x0 = math.floor(nowHour * width / 24)
            local x1 = math.floor((nowHour + 1) * width / 24)
            local tickW = math.max(1, math.min(2, x1 - x0))
            local cx = x0 + math.floor(math.max(0, (x1 - x0 - tickW)) / 2)
            self.nowTick:ClearAllPoints()
            self.nowTick:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", cx, -1)
            self.nowTick:SetSize(tickW, self._height + 2)
            self.nowTick:Show()
        else
            self.nowTick:Hide()
        end
        self._laidOutNowHour = nowHour
    end

    function strip:Clear()
        self._data = nil
        self._pal = nil
        self._nowHour = nil
        self._updatedAt = nil
        self._hasLiveOverlay = nil
        self._segsShown = false
        self._laidOutWidth = nil
        self._laidOutNowHour = nil
        for h = 0, 23 do
            self.segments[h]:Hide()
        end
        self.nowTick:Hide()
        self.frame:Hide()
    end

    return strip
end
