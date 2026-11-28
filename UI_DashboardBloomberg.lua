-- Bloomberg TV Multi-Pane Workstation Dashboard (Pure ASCII Lua 5.1)
-- 3-column broadcast desk: Stage Canvas + Headlines | Spotlight + Most Active + Timing | Stocks Ticker Rail.
-- Zero OnUpdate scripts, zero runtime frame allocations on redraw, pure ASCII, skin & dark/light aware.
local addonName, ns = ...

local UI = {}
ns.DashboardBloomberg = UI

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format, tostring, tonumber, type = string.format, tostring, tonumber, type
local unpack = unpack or table.unpack

local C = {
    AUTO_ROTATE_SEC = 12,
    MAX_STAGE_PTS = 40,
    MAX_REF_DOTS = 24,
    MAX_X_LABELS = 7,
    MAX_NEWS_ROWS = 10,
    MAX_SPOT_SEGS = 24,
    MAX_SPOT_BASE = 16,
    MAX_ACT_ROWS = 5,
    MAX_RAIL_TILES = 8,
    MAX_RAIL_SEGS = 16,
    MAX_RAIL_BASE = 12,
    RANGE_DAYS = { ["24h"] = 1, ["7d"] = 7, ["14d"] = 14, ["30d"] = 30 },
    SLIDE_BADGES = {
        vol_price    = "PRICE & VOL",
        wealth       = "NET WORTH",
        profit       = "AH PROFIT",
        craft_spread = "CRAFT SPREAD",
    },
    NEWS_BADGES = {
        costs  = "COSTS",
        deals  = "BUY ZONE",
        sales  = "SALES",
        movers = "WATCH",
    },
    APPLE_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MerchantMaster") .. "\\Assets\\apple\\",
}

local H = {}
local Builders = {}
local Render = {}

---------------------------------------------------------------------------------------------------
-- Core Safe Utilities
---------------------------------------------------------------------------------------------------
function H.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function H.isSecret(v)
    return (_G.issecretvalue and _G.issecretvalue(v))
        or (type(v) == "table" and _G.issecrettable and _G.issecrettable(v))
end

function H.safeNum(v, fallback)
    if H.isSecret(v) then return fallback end
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

function H.getPalette()
    local T = ns.Theme
    if T and T.GetActivePalette then
        local pal = T.GetActivePalette()
        if type(pal) == "table" then return pal end
    end
    return {
        mode = "dark",
        cardBg = { 0.14, 0.15, 0.17, 0.96 },
        cardAltBg = { 0.09, 0.10, 0.12, 0.96 },
        border = { 1, 1, 1, 0.14 },
        separator = { 1, 1, 1, 0.14 },
        glassSep = { 1, 1, 1, 0.14 },
        text = { 0.96, 0.96, 0.98, 1 },
        textSecondary = { 0.72, 0.74, 0.78, 1 },
        textMuted = { 0.56, 0.58, 0.63, 1 },
        accentBlue = { 0.20, 0.60, 1.00, 1 },
        accentGreen = { 0.19, 0.82, 0.35, 1 },
        accentOrange = { 1.00, 0.60, 0.18, 1 },
        accentRed = { 1.00, 0.32, 0.30, 1 },
        accentPurple = { 0.78, 0.42, 0.96, 1 },
        gold = { 1.00, 0.82, 0.20, 1 },
        rowHover = { 1, 1, 1, 0.07 },
        pillTrack = { 1, 1, 1, 0.09 },
        pillThumb = { 1, 1, 1, 0.18 },
    }
end

function H.setTextColor(fs, col, aOverride)
    if not (fs and fs.SetTextColor and type(col) == "table") then return end
    fs:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, aOverride or col[4] or 1)
end

function H.applyFont(fs, size, weight)
    if not fs then return end
    local T = ns.Theme
    if T and T.ApplyFont then
        T.ApplyFont(fs, size or 12, weight or "regular")
    elseif fs.SetFont then
        fs:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "")
    end
end

function H.makeFS(parent, size, weight, justifyH)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH(justifyH or "LEFT")
    fs:SetWordWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    H.applyFont(fs, size or 12, weight or "regular")
    fs._mmSize = size or 12
    fs._mmWeight = weight or "regular"
    return fs
end

function H.asset(key, fallbackFile)
    local T = ns.Theme
    if T and T.ASSETS and T.ASSETS[key] then return T.ASSETS[key] end
    return C.APPLE_ROOT .. (fallbackFile or key)
end

function H.formatCopper(copper, signed)
    local Brief = ns.DashboardBrief
    if Brief and type(Brief.FormatCopper) == "function" then
        return Brief.FormatCopper(copper, signed)
    end
    local v = H.safeNum(copper, 0) or 0
    local neg = v < 0
    local av = floor(abs(v) + 0.5)
    local g = floor(av / 10000)
    local s = floor((av % 10000) / 100)
    local c = av % 100
    local pfx = neg and "-" or ((signed and av > 0) and "+" or "")
    if g >= 1000 then return format("%s%dg", pfx, g) end
    if g > 0 then
        return (s > 0) and format("%s%dg %ds", pfx, g, s) or format("%s%dg", pfx, g)
    end
    if s > 0 then
        return (c > 0 and s < 10) and format("%s%ds %dc", pfx, s, c) or format("%s%ds", pfx, s)
    end
    return format("%s%dc", pfx, c)
end

function H.formatPct(pct)
    local n = H.safeNum(pct, nil)
    if n == nil then return "0.0%" end
    if n > 0 then return format("+%.1f%%", n) end
    return format("%.1f%%", n)
end

function H.deltaColor(val, pal, neutralKey)
    local n = H.safeNum(val, 0) or 0
    if n > 0.0001 then return pal.accentGreen or { 0.19, 0.82, 0.35, 1 } end
    if n < -0.0001 then return pal.accentRed or { 1.00, 0.32, 0.30, 1 } end
    return pal[neutralKey or "textSecondary"] or pal.textSecondary or pal.text
end

function H.resolveEconKey(override)
    if type(override) == "string" and override ~= "" then return override end
    if ns.DetectActiveEconomy then
        local ok, ek = pcall(ns.DetectActiveEconomy)
        if ok and type(ek) == "string" and ek ~= "" and not H.isSecret(ek) then return ek end
    end
    local Store = ns.Analytics and ns.Analytics.Store
    if Store and Store.CurrentCharAndEcon then
        local _, ek = Store.CurrentCharAndEcon()
        if type(ek) == "string" and ek ~= "" then return ek end
    end
    return "Normal-Horde"
end

function H.getGreeting(playerOverride)
    local Brief = ns.DashboardBrief
    if Brief and type(Brief.GetGreeting) == "function" then
        return Brief.GetGreeting(nil, playerOverride)
    end
    local nm = (type(playerOverride) == "string" and playerOverride ~= "" and playerOverride) or "Merchant"
    return "Market Desk, " .. nm
end

function H.resolveIcon(stock)
    if stock and stock.icon and not H.isSecret(stock.icon) then return stock.icon end
    local id = stock and H.safeNum(stock.itemID, 0) or 0
    if id > 0 then
        local Model = ns.Analytics and ns.Analytics.Model
        if Model and Model.ItemIcon then
            local ic = Model.ItemIcon(id)
            if ic and not H.isSecret(ic) then return ic end
        end
        if _G.C_Item and _G.C_Item.GetItemIconByID then
            local ok, ic = pcall(_G.C_Item.GetItemIconByID, id)
            if ok and ic and not H.isSecret(ic) then return ic end
        end
        if _G.GetItemIcon then
            local ok, ic = pcall(_G.GetItemIcon, id)
            if ok and ic and not H.isSecret(ic) then return ic end
        end
    end
    return H.asset("icon_coins", "icon_coins")
end

function H.setSegmentLine(seg, parent, x1, y1, x2, y2, thickness, col, alpha)
    if not seg then return end
    local r = (col and col[1]) or 1
    local g = (col and col[2]) or 1
    local b = (col and col[3]) or 1
    local a = alpha or (col and col[4]) or 1
    if seg._isLine and seg.SetStartPoint and seg.SetEndPoint then
        seg:SetThickness(thickness or 2)
        if seg.SetTexture and seg.SetVertexColor then
            seg:SetTexture(H.asset("line_soft", "line_soft"))
            seg:SetVertexColor(r, g, b, a)
        elseif seg.SetColorTexture then
            seg:SetColorTexture(r, g, b, a)
        end
        seg:SetStartPoint("BOTTOMLEFT", parent, x1, y1)
        seg:SetEndPoint("BOTTOMLEFT", parent, x2, y2)
        seg:Show()
    else
        -- Texture fallback when CreateLine is unavailable (e.g. minimal perf harness)
        local cx = floor((x1 + x2) * 0.5 + 0.5)
        local cy = floor((y1 + y2) * 0.5 + 0.5)
        local w = max(2, floor(abs(x2 - x1) + 0.5))
        local h = max(2, floor(thickness or 2))
        seg:ClearAllPoints()
        seg:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", cx - floor(w * 0.5), cy - floor(h * 0.5))
        seg:SetSize(w, h)
        seg:SetColorTexture(r, g, b, a)
        seg:Show()
    end
end

function H.createLinePool(parent, count, layer, sublevel)
    local pool = {}
    local canLine = (type(parent.CreateLine) == "function")
    for i = 1, count do
        local seg
        if canLine then
            seg = parent:CreateLine(nil, layer or "ARTWORK", nil, sublevel or 2)
            seg._isLine = true
        else
            seg = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 2)
            seg._isLine = false
        end
        seg:Hide()
        pool[i] = seg
    end
    return pool
end

function H.createPlotWell(canvas)
    local bg = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:Hide()
    local edges = {}
    for idx = 1, 4 do
        local e = canvas:CreateTexture(nil, "BORDER", nil, 1)
        e:Hide()
        edges[idx] = e
    end
    local well = { bg = bg, edges = edges }
    function well:Hide()
        self.bg:Hide()
        for _, e in ipairs(self.edges) do e:Hide() end
    end
    function well:ShowBox(left, bottom, w, h, pal)
        local isLight = pal and (pal.mode == "light")
        local bw = max(1, floor(w + 0.5))
        local bh = max(1, floor(h + 0.5))
        self.bg:ClearAllPoints()
        self.bg:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", left, bottom)
        self.bg:SetSize(bw, bh)
        if isLight then
            self.bg:SetColorTexture(0.02, 0.04, 0.08, 0.045)
        else
            self.bg:SetColorTexture(0.01, 0.015, 0.025, 0.64)
        end
        self.bg:Show()
        local bc = isLight and { 0.08, 0.12, 0.20, 0.14 } or { 0.30, 0.62, 0.88, 0.22 }
        local eTop, eBot, eL, eR = self.edges[1], self.edges[2], self.edges[3], self.edges[4]
        eTop:ClearAllPoints(); eTop:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", left, bottom + bh - 1); eTop:SetSize(bw, 1)
        eBot:ClearAllPoints(); eBot:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", left, bottom); eBot:SetSize(bw, 1)
        eL:ClearAllPoints();   eL:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", left, bottom); eL:SetSize(1, bh)
        eR:ClearAllPoints();   eR:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", left + bw - 1, bottom); eR:SetSize(1, bh)
        for _, e in ipairs(self.edges) do
            e:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
            e:Show()
        end
    end
    return well
end

function H.createCard(parent, fillKey, borderKey, accentKey)
    local T = ns.Theme
    local fk = fillKey or "cardBg"
    local bk = (borderKey == nil) and "border" or borderKey
    local frame = CreateFrame("Frame", nil, parent)
    frame._fillKey = fk
    frame._borderKey = bk
    frame._accentKey = accentKey
    if T and T.NineApple then
        frame._surface = T.NineApple(frame, "glass_r10", fk, bk, { noSpecular = true })
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        frame._fallbackBg = bg
    end

    local skinTile = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    skinTile:SetAllPoints()
    skinTile:Hide()
    frame._skinTile = skinTile

    -- Translucent dark studio plate so chart panels & visual cards pop cleanly against patterned skins
    local darkBackdrop = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    darkBackdrop:SetPoint("TOPLEFT", 1, -1)
    darkBackdrop:SetPoint("BOTTOMRIGHT", -1, 1)
    darkBackdrop:Hide()
    frame._darkBackdrop = darkBackdrop

    local studioEdges = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local edge = frame:CreateTexture(nil, "BORDER", nil, 2)
        if side == "top" then
            edge:SetPoint("TOPLEFT", 0, 0); edge:SetPoint("TOPRIGHT", 0, 0); edge:SetHeight(1)
        elseif side == "bottom" then
            edge:SetPoint("BOTTOMLEFT", 0, 0); edge:SetPoint("BOTTOMRIGHT", 0, 0); edge:SetHeight(1)
        elseif side == "left" then
            edge:SetPoint("TOPLEFT", 0, 0); edge:SetPoint("BOTTOMLEFT", 0, 0); edge:SetWidth(1)
        else
            edge:SetPoint("TOPRIGHT", 0, 0); edge:SetPoint("BOTTOMRIGHT", 0, 0); edge:SetWidth(1)
        end
        edge:Hide()
        studioEdges[#studioEdges + 1] = edge
    end
    frame._skinEdges = studioEdges

    local topAccent = frame:CreateTexture(nil, "BORDER", nil, 3)
    topAccent:SetPoint("TOPLEFT", 1, -1)
    topAccent:SetPoint("TOPRIGHT", -1, -1)
    topAccent:SetHeight(2)
    topAccent:Hide()
    frame._topAccent = topAccent

    local hdrTint = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
    hdrTint:SetPoint("TOPLEFT", 2, -2)
    hdrTint:SetPoint("TOPRIGHT", -2, -2)
    hdrTint:SetHeight(28)
    hdrTint:Hide()
    frame._hdrTint = hdrTint

    function frame:PaintCard(pal)
        pal = pal or H.getPalette()
        local isLight = (pal.mode == "light")
        local fillCol = pal[self._fillKey] or pal.cardBg
        if self._surface and self._surface.UpdateTheme then
            self._surface:UpdateTheme(self._fillKey, self._borderKey)
        elseif self._fallbackBg and fillCol then
            self._fallbackBg:SetColorTexture(fillCol[1], fillCol[2], fillCol[3], fillCol[4] or 0.96)
        end

        local custom = T and T.IsCustomSkin and T.IsCustomSkin()
        if custom and pal.frameBorder and T.GetSkinAsset and T.GetSkin then
            local tex = T.GetSkinAsset(T.GetSkin(), "surface")
            if tex then
                self._skinTile:SetTexture(tex, "CLAMP", "CLAMP")
                self._skinTile:SetAlpha(isLight and (self._fillKey == "cardAltBg" and 0.65 or 0.90)
                    or (self._fillKey == "cardAltBg" and 0.12 or 0.16))
                self._skinTile:Show()
            else
                self._skinTile:Hide()
            end
        else
            self._skinTile:Hide()
        end

        local ak = self._accentKey
        if not isLight then
            local plateAlpha = custom
                and (self._fillKey == "cardAltBg" and 0.84 or 0.80)
                or  (self._fillKey == "cardAltBg" and 0.66 or 0.62)
            self._darkBackdrop:SetColorTexture(0.010, 0.015, 0.024, plateAlpha)
            self._darkBackdrop:Show()
        else
            self._darkBackdrop:Hide()
        end

        local edgeCol, topCol, edgeThick
        if ak == "cyan" then
            edgeCol = isLight and { 0.08, 0.48, 0.88, 0.35 } or { 0.20, 0.74, 0.98, custom and 0.86 or 0.68 }
            topCol  = isLight and { 0.06, 0.48, 0.88, 0.80 } or { 0.30, 0.80, 1.00, 0.96 }
            edgeThick = 2
        elseif ak == "amber" then
            edgeCol = isLight and { 0.80, 0.40, 0.04, 0.24 } or { 0.88, 0.60, 0.18, custom and 0.56 or 0.38 }
            topCol  = isLight and { 0.82, 0.42, 0.04, 0.78 } or { 0.98, 0.64, 0.16, 0.94 }
            edgeThick = 1
        else
            edgeCol = isLight and { 0, 0, 0, 0.12 } or { 0.46, 0.56, 0.68, custom and 0.46 or 0.24 }
            topCol  = isLight and { 0.12, 0.14, 0.18, 0.14 } or { 0.70, 0.78, 0.90, 0.38 }
            edgeThick = 1
        end

        if edgeCol and (not isLight or ak == "cyan") then
            for idx, e in ipairs(self._skinEdges) do
                if idx <= 2 then
                    e:SetHeight(edgeThick)
                else
                    e:SetWidth(edgeThick)
                end
                e:SetColorTexture(edgeCol[1], edgeCol[2], edgeCol[3], edgeCol[4])
                e:Show()
            end
        else
            for _, e in ipairs(self._skinEdges) do e:Hide() end
        end
        if topCol then
            self._topAccent:SetColorTexture(topCol[1], topCol[2], topCol[3], topCol[4])
            self._topAccent:Show()
            if self._hdrTint then
                if not isLight then
                    local tintA = (ak == "cyan" or ak == "amber") and 0.065 or 0.040
                    self._hdrTint:SetColorTexture(topCol[1], topCol[2], topCol[3], tintA)
                    self._hdrTint:Show()
                else
                    self._hdrTint:Hide()
                end
            end
        else
            self._topAccent:Hide()
            if self._hdrTint then self._hdrTint:Hide() end
        end
    end

    return frame
end

function H.createMiniButton(parent, text, w, h, fontSize, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w or 44, h or 20)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn.bg = bg

    local bTop = btn:CreateTexture(nil, "BORDER")
    bTop:SetPoint("TOPLEFT", 0, 0); bTop:SetPoint("TOPRIGHT", 0, 0); bTop:SetHeight(1)
    local bBot = btn:CreateTexture(nil, "BORDER")
    bBot:SetPoint("BOTTOMLEFT", 0, 0); bBot:SetPoint("BOTTOMRIGHT", 0, 0); bBot:SetHeight(1)
    btn._borders = { bTop, bBot }

    local lbl = H.makeFS(btn, fontSize or 10, "semibold", "CENTER")
    lbl:SetPoint("LEFT", btn, "LEFT", 2, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    lbl:SetText(text or "")
    btn.label = lbl
    btn._active = false
    btn._hovered = false
    btn._accent = false

    function btn:Paint(pal)
        pal = pal or H.getPalette()
        local isLight = (pal.mode == "light")
        local bgCol, txtCol, brdCol
        if self._active then
            if self._accent then
                bgCol = isLight and { 0.80, 0.36, 0.02, 0.92 } or { 0.95, 0.56, 0.10, 0.92 }
                txtCol = isLight and { 1, 1, 1, 1 } or { 0.05, 0.05, 0.07, 1 }
                brdCol = bgCol
            else
                bgCol = pal.pillThumb or (isLight and { 0.14, 0.15, 0.18, 0.14 } or { 1, 1, 1, 0.18 })
                txtCol = pal.text
                brdCol = pal.accentOrange or pal.border
            end
        elseif self._hovered then
            bgCol = pal.rowHover or (isLight and { 0, 0, 0, 0.08 } or { 1, 1, 1, 0.10 })
            txtCol = pal.text
            brdCol = pal.border
        else
            bgCol = pal.pillTrack or (isLight and { 0, 0, 0, 0.05 } or { 1, 1, 1, 0.06 })
            txtCol = pal.textSecondary
            brdCol = pal.border or { 1, 1, 1, 0.10 }
        end
        self.bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.12)
        for _, b in ipairs(self._borders) do
            b:SetColorTexture(brdCol[1], brdCol[2], brdCol[3], (brdCol[4] or 0.2) * (self._active and 0.9 or 0.45))
        end
        H.applyFont(self.label, fontSize or 10, "semibold")
        H.setTextColor(self.label, txtCol)
    end

    btn:SetScript("OnEnter", function(self)
        self._hovered = true
        self:Paint(H.getPalette())
    end)
    btn:SetScript("OnLeave", function(self)
        self._hovered = false
        self:Paint(H.getPalette())
    end)
    if type(onClick) == "function" then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

function H.createSegmented(parent, items, opts)
    local T = ns.Theme
    if T and type(T.CreateSegmentedControl) == "function" then
        return T.CreateSegmentedControl(parent, items, opts)
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight((opts and opts.height) or 26)
    local activeKey = (opts and opts.activeKey) or (items[1] and items[1].key)
    local buttons = {}
    local x = 2
    local ctrl = { frame = f, buttons = buttons }
    function ctrl:SetActive(k, silent)
        activeKey = k
        for bk, b in pairs(buttons) do
            b._active = (bk == activeKey)
            b:Paint(H.getPalette())
        end
        if not silent and opts and opts.onChange then opts.onChange(k) end
    end
    function ctrl:GetActive() return activeKey end
    function ctrl:UpdateTheme()
        local pal = H.getPalette()
        for _, b in pairs(buttons) do b:Paint(pal) end
    end
    for _, def in ipairs(items or {}) do
        local bw = def.width or max(36, #(def.label or "") * 7 + 14)
        local b = H.createMiniButton(f, def.label or def.key, bw, ((opts and opts.height) or 26) - 4,
            (opts and opts.fontSize) or 11, function() ctrl:SetActive(def.key, false) end)
        b:SetPoint("LEFT", f, "LEFT", x, 0)
        b._active = (def.key == activeKey)
        buttons[def.key] = b
        x = x + bw + 2
    end
    f:SetWidth(x + 2)
    return ctrl
end

function H.createBadge(parent, text, variant, opts)
    local T = ns.Theme
    if T and type(T.CreateBadgePill) == "function" then
        return T.CreateBadgePill(parent, text, variant, opts)
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(80, (opts and opts.height) or 20)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local lbl = H.makeFS(f, (opts and opts.fontSize) or 10, "semibold", "CENTER")
    lbl:SetPoint("LEFT", f, "LEFT", 4, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    lbl:SetText(text or "")
    local pill = { frame = f, label = lbl, bg = bg, variant = variant or "neutral" }
    function pill:SetVariant(newVar, newText)
        if newVar then self.variant = newVar end
        if newText ~= nil then lbl:SetText(tostring(newText)) end
        local pal = H.getPalette()
        local tr = pal.pillTrack or { 1, 1, 1, 0.10 }
        bg:SetColorTexture(tr[1], tr[2], tr[3], tr[4] or 0.12)
        H.setTextColor(lbl, pal.textSecondary)
        f:SetWidth(max(36, #(lbl:GetText() or "") * 6 + ((opts and opts.padX) or 12)))
    end
    pill:SetVariant(variant or "neutral", text or "")
    return pill
end

function H.createScrollbar(body)
    local track = body:CreateTexture(nil, "BORDER")
    track:SetPoint("TOPRIGHT", body, "TOPRIGHT", -1, -2)
    track:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -1, 2)
    track:SetWidth(3)
    track:Hide()

    local thumb = body:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(3)
    thumb:Hide()

    local sb = { track = track, thumb = thumb, body = body }
    function sb:Update(total, visible, offset)
        local maxOff = max(0, (total or 0) - (visible or 1))
        if maxOff <= 0 then
            self.track:Hide()
            self.thumb:Hide()
            return
        end
        local bh = max(24, (H.safeNum(self.body:GetHeight(), 160) or 160) - 4)
        local th = max(18, floor(bh * (visible / total) + 0.5))
        local travel = max(0, bh - th)
        local ratio = H.clamp((offset or 0) / maxOff, 0, 1)
        self.track:Show()
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", -1, -2 - floor(travel * ratio + 0.5))
        self.thumb:SetSize(3, th)
        self.thumb:Show()
    end
    function sb:Paint(pal)
        pal = pal or H.getPalette()
        local sep = pal.separator or { 1, 1, 1, 0.14 }
        local tm = pal.textMuted or { 0.6, 0.6, 0.65, 0.7 }
        self.track:SetColorTexture(sep[1], sep[2], sep[3], 0.18)
        self.thumb:SetColorTexture(tm[1], tm[2], tm[3], 0.58)
    end
    return sb
end

function H.samplePoints(points, maxPts)
    local n = type(points) == "table" and #points or 0
    if n <= maxPts then return points or {} end
    local out = {}
    local step = (n - 1) / (maxPts - 1)
    for i = 1, maxPts do
        local idx = H.clamp(floor((i - 1) * step + 1.5), 1, n)
        out[i] = points[idx]
    end
    return out
end

function H.findStock(snap, key)
    if type(snap) ~= "table" then return nil end
    if key then
        for _, s in ipairs(snap.allStocks or {}) do
            if s.key == key then return s end
        end
        for _, s in ipairs(snap.stocks or {}) do
            if s.key == key then return s end
        end
    end
    if type(snap.selectedStock) == "table" then return snap.selectedStock end
    if snap.stocks and snap.stocks[1] then return snap.stocks[1] end
    if snap.allStocks and snap.allStocks[1] then return snap.allStocks[1] end
    return nil
end

function H.emptySnapshot(econKey, rangeKey, filterKey, freshness)
    return {
        econKey = econKey or "Normal-Horde",
        rangeKey = rangeKey or "7d",
        filterKey = filterKey or "all",
        allStocks = {},
        stocks = {},
        mostActive = {},
        slides = {
            { id = "vol_price", kind = "vol_price", title = "Market Supply vs Min Price", points = {} },
            { id = "wealth", kind = "wealth", title = "Net Worth Trajectory", points = {} },
            { id = "profit", kind = "profit", title = "Realized AH Profit", points = {} },
            { id = "craft_spread", kind = "craft_spread", title = "Craft Cost vs Sale Spread", points = {} },
        },
        headlines = {
            {
                id = "empty_1",
                category = "sales",
                severity = "info",
                title = "Star items in Watchlist or run an AH scan to populate live GoblinTV feeds",
                detail = "Your top crafted recipes, heavily bought reagents, and Watchlist favorites appear automatically.",
            },
        },
        kpis = {
            todayProfit = 0,
            todaySalesCount = 0,
            yesterdayProfit = 0,
            netWorth = 0,
            netWorthDeltaCopper = 0,
            netWorthDeltaPct = 0,
            topMover = nil,
        },
        timing = {
            econKey = econKey or "Normal-Horde",
            freshnessText = freshness or "Live",
            bestSellText = "Open AH to scan",
            bestBuyText = "Open AH to scan",
            watchlistCount = 0,
            trackedCraftsCount = 0,
        },
    }
end

---------------------------------------------------------------------------------------------------
-- Panel Builders (Zero Allocations After Create)
---------------------------------------------------------------------------------------------------
function Builders.buildBanner(ctx)
    local banner = CreateFrame("Frame", nil, ctx.view)
    banner:SetHeight(32)

    local bloomBadge = CreateFrame("Frame", nil, banner)
    bloomBadge:SetSize(76, 20)
    bloomBadge:SetPoint("LEFT", banner, "LEFT", 2, 0)
    bloomBadge.bg = bloomBadge:CreateTexture(nil, "BACKGROUND")
    bloomBadge.bg:SetAllPoints()
    bloomBadge.label = H.makeFS(bloomBadge, 10, "semibold", "CENTER")
    bloomBadge.label:SetPoint("CENTER", bloomBadge, "CENTER", 0, 0)
    bloomBadge.label:SetText("GOBLINTV")

    local greetingFs = H.makeFS(banner, 14, "semibold", "LEFT")
    greetingFs:SetPoint("LEFT", bloomBadge, "RIGHT", 8, 0)
    greetingFs:SetText(H.getGreeting(ctx.opts.getPlayerName and ctx.opts.getPlayerName()))

    local metaPill = H.createBadge(banner, "Normal-Horde | Live", "neutral", { height = 20, fontSize = 10, padX = 12 })
    metaPill.frame:SetPoint("LEFT", greetingFs, "RIGHT", 8, 0)

    local modeSeg = H.createSegmented(banner, {
        { key = "bloomberg", label = "GoblinTV",      width = 88 },
        { key = "brief",     label = "Morning Brief", width = 102 },
        { key = "classic",   label = "Market Pulse",  width = 96 },
    }, {
        height = 26,
        fontSize = 11,
        activeKey = "bloomberg",
        onChange = function(k)
            local m = (k == "classic" or k == "brief") and k or "bloomberg"
            ctx.state.mode = m
            if type(_G.MerchantMasterDB) == "table" then
                _G.MerchantMasterDB.dashboardMode = m
            end
            if type(ctx.opts.onModeChange) == "function" then
                ctx.opts.onModeChange(m)
            end
        end,
    })
    modeSeg.frame:SetPoint("RIGHT", banner, "RIGHT", -2, 0)

    local rangeSeg = H.createSegmented(banner, {
        { key = "24h", label = "24h", width = 34 },
        { key = "7d",  label = "7d",  width = 32 },
        { key = "14d", label = "14d", width = 36 },
        { key = "30d", label = "30d", width = 36 },
    }, {
        height = 26,
        fontSize = 11,
        activeKey = ctx.state.rangeKey,
        onChange = function(k)
            if not C.RANGE_DAYS[k] then return end
            ctx.state.rangeKey = k
            if type(_G.MerchantMasterDB) == "table" then
                _G.MerchantMasterDB.dashboardBriefRange = k
            end
            ctx.view:Refresh(true)
        end,
    })
    rangeSeg.frame:SetPoint("RIGHT", modeSeg.frame, "LEFT", -8, 0)

    ctx.banner = banner
    ctx.bloomBadge = bloomBadge
    ctx.greetingFs = greetingFs
    ctx.metaPill = metaPill
    ctx.modeSeg = modeSeg
    ctx.rangeSeg = rangeSeg
    ctx.view.banner = banner
    ctx.view.bloomBadge = bloomBadge
    ctx.view.greetingFs = greetingFs
    ctx.view.metaPill = metaPill
    ctx.view.modeSeg = modeSeg
    ctx.view.rangeSeg = rangeSeg
end

function Builders.buildStagePanel(ctx)
    local panel = H.createCard(ctx.view, "cardBg", "border", "cyan")

    -- Top broadcast bar (34px)
    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    hdr:SetHeight(34)

    local liveDot = hdr:CreateTexture(nil, "ARTWORK")
    liveDot:SetSize(8, 8)
    liveDot:SetPoint("LEFT", hdr, "LEFT", 10, 0)
    liveDot:SetTexture(H.asset("circle_fill", "circle_fill"))

    local slideBadge = CreateFrame("Frame", nil, hdr)
    slideBadge:SetSize(92, 18)
    slideBadge:SetPoint("LEFT", liveDot, "RIGHT", 6, 0)
    slideBadge.bg = slideBadge:CreateTexture(nil, "BACKGROUND")
    slideBadge.bg:SetAllPoints()
    slideBadge.label = H.makeFS(slideBadge, 9, "semibold", "CENTER")
    slideBadge.label:SetPoint("CENTER", slideBadge, "CENTER", 0, 0)
    slideBadge.label:SetText("PRICE & VOL")

    local autoBtn = H.createMiniButton(hdr, "Auto: On", 62, 20, 10, function()
        ctx.view:ToggleAutoRotate()
    end)
    autoBtn:SetPoint("RIGHT", hdr, "RIGHT", -8, 0)

    local nextBtn = H.createMiniButton(hdr, ">", 20, 20, 10, function()
        ctx.view:NextSlide(true)
    end)
    nextBtn:SetPoint("RIGHT", autoBtn, "LEFT", -4, 0)

    local counterFs = H.makeFS(hdr, 10, "semibold", "CENTER")
    counterFs:SetWidth(28)
    counterFs:SetPoint("RIGHT", nextBtn, "LEFT", -2, 0)
    counterFs:SetText("1/4")

    local prevBtn = H.createMiniButton(hdr, "<", 20, 20, 10, function()
        ctx.view:PrevSlide(true)
    end)
    prevBtn:SetPoint("RIGHT", counterFs, "LEFT", -2, 0)

    local styleBtn = H.createMiniButton(hdr, "Candles", 54, 20, 10, function()
        ctx.view:ToggleChartStyle()
    end)
    styleBtn:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0)
    styleBtn._active = true

    local unpinBtn = H.createMiniButton(hdr, "Unpin", 44, 20, 10, function()
        ctx.state.pinnedKey = nil
        ctx.view:Refresh(false)
    end)
    unpinBtn:SetPoint("RIGHT", styleBtn, "LEFT", -4, 0)
    unpinBtn._accent = true
    unpinBtn._active = true
    unpinBtn:Hide()

    local titleFs = H.makeFS(hdr, 12, "semibold", "LEFT")
    titleFs:SetPoint("LEFT", slideBadge, "RIGHT", 8, 0)
    titleFs:SetPoint("RIGHT", styleBtn, "LEFT", -8, 0)
    titleFs:SetText("Broadcast Stage")

    local hdrSep = panel:CreateTexture(nil, "BORDER")
    hdrSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -34)
    hdrSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -34)
    hdrSep:SetHeight(1)

    -- Main chart canvas
    local canvas = CreateFrame("Frame", nil, panel)
    canvas:EnableMouse(true)
    canvas:SetScript("OnEnter", function() ctx.state.stageHovered = true end)
    canvas:SetScript("OnLeave", function() ctx.state.stageHovered = false end)

    local plotWell = H.createPlotWell(canvas)

    local legendFs = H.makeFS(canvas, 9, "semibold", "RIGHT")
    legendFs:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -64, -2)

    local volMaxFs = H.makeFS(canvas, 9, "semibold", "LEFT")
    volMaxFs:SetPoint("TOPLEFT", canvas, "TOPLEFT", 8, -2)
    volMaxFs:SetPoint("RIGHT", legendFs, "LEFT", -8, 0)

    local refLabelFs = H.makeFS(canvas, 9, "semibold", "LEFT")
    refLabelFs:Hide()

    local emptyFs = H.makeFS(canvas, 11, "regular", "CENTER")
    emptyFs:SetPoint("CENTER", canvas, "CENTER", 0, 4)
    emptyFs:SetWordWrap(true)
    if emptyFs.SetMaxLines then emptyFs:SetMaxLines(2) end
    emptyFs:SetText("No chart data yet - scan the AH or record ledger activity")
    emptyFs:Hide()

    local hGrid, yLabels = {}, {}
    for i = 1, 3 do
        local gl = canvas:CreateTexture(nil, "BACKGROUND", nil, 2)
        gl:SetHeight(1)
        gl:Hide()
        hGrid[i] = gl
        local yl = H.makeFS(canvas, 9, "regular", "RIGHT")
        yl:SetWidth(58)
        yl:Hide()
        yLabels[i] = yl
    end

    local xLabels = {}
    for i = 1, C.MAX_X_LABELS do
        local xl = H.makeFS(canvas, 9, "regular", "CENTER")
        xl:SetWidth(54)
        xl:Hide()
        xLabels[i] = xl
    end

    local volSep = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
    volSep:SetHeight(1)
    volSep:Hide()

    local volPool, fillPool, bodyPool, dotPool, hoverPool = {}, {}, {}, {}, {}
    for i = 1, C.MAX_STAGE_PTS do
        local vb = canvas:CreateTexture(nil, "ARTWORK", nil, 0)
        vb:Hide()
        volPool[i] = vb

        local fs = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
        fs:Hide()
        fillPool[i] = fs

        local bd = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
        bd:Hide()
        bodyPool[i] = bd

        local dt = canvas:CreateTexture(nil, "ARTWORK", nil, 4)
        dt:SetSize(5, 5)
        dt:SetTexture(H.asset("circle_fill", "circle_fill"))
        dt:Hide()
        dotPool[i] = dt

        local hb = CreateFrame("Button", nil, canvas)
        hb:Hide()
        hb:SetScript("OnEnter", function(self)
            ctx.state.stageHovered = true
            Render.showStageTooltip(ctx, self)
        end)
        hb:SetScript("OnLeave", function()
            ctx.state.stageHovered = false
            if canvas.crosshair then canvas.crosshair:Hide() end
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        hoverPool[i] = hb
    end

    local refDots = {}
    for i = 1, C.MAX_REF_DOTS do
        local d = canvas:CreateTexture(nil, "ARTWORK", nil, 2)
        d:SetHeight(1)
        d:Hide()
        refDots[i] = d
    end

    local zeroLine = canvas:CreateTexture(nil, "ARTWORK", nil, 2)
    zeroLine:SetHeight(1)
    zeroLine:Hide()

    local crosshair = canvas:CreateTexture(nil, "OVERLAY", nil, 1)
    crosshair:SetWidth(1)
    crosshair:Hide()
    canvas.crosshair = crosshair

    local wickPool = H.createLinePool(canvas, C.MAX_STAGE_PTS, "ARTWORK", 2)
    local linePool = H.createLinePool(canvas, C.MAX_STAGE_PTS, "ARTWORK", 3)
    local line2Pool = H.createLinePool(canvas, C.MAX_STAGE_PTS, "ARTWORK", 4)

    -- Bottom lower-third tickerStrip (36px)
    local tickerStrip = CreateFrame("Frame", nil, panel)
    tickerStrip:SetHeight(36)
    tickerStrip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 1, 1)
    tickerStrip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
    tickerStrip.bg = tickerStrip:CreateTexture(nil, "BACKGROUND", nil, 2)
    tickerStrip.bg:SetAllPoints()
    tickerStrip.topSep = tickerStrip:CreateTexture(nil, "BORDER", nil, 2)
    tickerStrip.topSep:SetPoint("TOPLEFT", tickerStrip, "TOPLEFT", 0, 0)
    tickerStrip.topSep:SetPoint("TOPRIGHT", tickerStrip, "TOPRIGHT", 0, 0)
    tickerStrip.topSep:SetHeight(1)

    local kpiCells, kpiDivs = {}, {}
    local kpiTitles = { "TODAY PROFIT", "NET WORTH", "TOP MOVER" }
    for idx = 1, 3 do
        local cell = CreateFrame("Button", nil, tickerStrip)
        cell.kLabel = H.makeFS(cell, 9, "semibold", "LEFT")
        cell.kLabel:SetPoint("TOPLEFT", cell, "TOPLEFT", 10, -4)
        cell.kLabel:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -6, -4)
        cell.kLabel:SetText(kpiTitles[idx])

        cell.kVal = H.makeFS(cell, 11, "semibold", "LEFT")
        cell.kVal:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 10, 4)
        cell.kVal:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -6, 4)
        cell.kVal:SetText("--")

        if idx == 3 then
            cell:SetScript("OnClick", function()
                local tm = ctx.state.snap and ctx.state.snap.kpis and ctx.state.snap.kpis.topMover
                if tm and tm.key then
                    ctx.view:SelectStock(tm.key, false)
                end
            end)
        end
        kpiCells[idx] = cell

        if idx < 3 then
            local dv = tickerStrip:CreateTexture(nil, "BORDER", nil, 2)
            dv:SetWidth(1)
            kpiDivs[idx] = dv
        end
    end

    ctx.stage = {
        panel = panel, hdr = hdr, liveDot = liveDot, slideBadge = slideBadge,
        titleFs = titleFs, styleBtn = styleBtn, prevBtn = prevBtn, counterFs = counterFs, nextBtn = nextBtn,
        autoBtn = autoBtn, unpinBtn = unpinBtn, hdrSep = hdrSep,
        canvas = canvas, plotWell = plotWell, volSep = volSep,
        legendFs = legendFs, volMaxFs = volMaxFs, refLabelFs = refLabelFs,
        emptyFs = emptyFs, hGrid = hGrid, yLabels = yLabels, xLabels = xLabels,
        volPool = volPool, fillPool = fillPool, bodyPool = bodyPool, dotPool = dotPool,
        hoverPool = hoverPool, refDots = refDots, zeroLine = zeroLine, crosshair = crosshair,
        wickPool = wickPool, linePool = linePool, line2Pool = line2Pool,
        tickerStrip = tickerStrip, kpiCells = kpiCells, kpiDivs = kpiDivs,
    }
    ctx.view.stagePanel = panel
    ctx.view.stageCanvas = canvas
    ctx.view.tickerStrip = tickerStrip
end

function Builders.buildNewsPanel(ctx)
    local panel = H.createCard(ctx.view, "cardBg", "border", "amber")

    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    hdr:SetHeight(34)

    local titleFs = H.makeFS(hdr, 12, "semibold", "LEFT")
    titleFs:SetPoint("LEFT", hdr, "LEFT", 12, 0)
    titleFs:SetText("MARKET HEADLINES")

    local filterDefs = {
        { key = "all",   label = "All",   w = 34 },
        { key = "costs", label = "Costs", w = 44 },
        { key = "deals", label = "Deals", w = 44 },
        { key = "sales", label = "Sales", w = 44 },
    }
    local filterBtns = {}
    local rightAnchor = nil
    for i = #filterDefs, 1, -1 do
        local def = filterDefs[i]
        local b = H.createMiniButton(hdr, def.label, def.w, 20, 10, function()
            ctx.state.newsFilter = def.key
            ctx.state.newsOffset = 0
            Render.paintNewsFilters(ctx)
            Render.renderNews(ctx)
        end)
        if not rightAnchor then
            b:SetPoint("RIGHT", hdr, "RIGHT", -8, 0)
        else
            b:SetPoint("RIGHT", rightAnchor, "LEFT", -3, 0)
        end
        b._filterKey = def.key
        filterBtns[def.key] = b
        rightAnchor = b
    end
    titleFs:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)

    local hdrSep = panel:CreateTexture(nil, "BORDER")
    hdrSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -34)
    hdrSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -34)
    hdrSep:SetHeight(1)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -37)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    if body.EnableMouseWheel then
        body:EnableMouseWheel(true)
        body:SetScript("OnMouseWheel", function(_, delta)
            local list = ctx.state.filteredNews or {}
            local maxOff = max(0, #list - ctx.state.visibleNewsRows)
            local nextOff = H.clamp(ctx.state.newsOffset - (delta > 0 and 1 or -1), 0, maxOff)
            if nextOff ~= ctx.state.newsOffset then
                ctx.state.newsOffset = nextOff
                Render.renderNews(ctx)
            end
        end)
    end

    local sb = H.createScrollbar(body)
    local emptyFs = H.makeFS(body, 11, "regular", "CENTER")
    emptyFs:SetPoint("CENTER", body, "CENTER", 0, 0)
    emptyFs:SetText("No market headlines for this filter")
    emptyFs:Hide()

    local rows = {}
    for i = 1, C.MAX_NEWS_ROWS do
        local row = CreateFrame("Button", nil, body)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:Hide()

        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(8, 8)
        row.dot:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.dot:SetTexture(H.asset("circle_fill", "circle_fill"))

        row.badge = CreateFrame("Frame", nil, row)
        row.badge:SetSize(60, 17)
        row.badge:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.badge.bg = row.badge:CreateTexture(nil, "BACKGROUND")
        row.badge.bg:SetAllPoints()
        row.badge.label = H.makeFS(row.badge, 9, "semibold", "CENTER")
        row.badge.label:SetPoint("CENTER", row.badge, "CENTER", 0, 0)

        row.titleFs = H.makeFS(row, 11, "semibold", "LEFT")
        row.titleFs:SetPoint("LEFT", row.dot, "RIGHT", 7, 0)
        row.titleFs:SetPoint("RIGHT", row.badge, "LEFT", -8, 0)

        row.sep = row:CreateTexture(nil, "BORDER")
        row.sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
        row.sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
        row.sep:SetHeight(1)

        row:SetScript("OnEnter", function(self)
            local pal = H.getPalette()
            local hv = pal.rowHover or { 1, 1, 1, 0.07 }
            self.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4] or 0.07)
            self.hl:Show()
            Render.showNewsTooltip(ctx, self)
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            local story = self._story
            if not story then return end
            if _G.IsShiftKeyDown and _G.IsShiftKeyDown() and story.cartItemID then
                ctx.addToCart(story.cartItemID, story.cartQty or 1, story.cartName or story.title)
                return
            end
            if story.stockKey then
                ctx.view:SelectStock(story.stockKey, false)
            end
            local id = H.safeNum(story.itemID, 0) or 0
            local sp = H.safeNum(story.spellID, 0) or 0
            if sp > 0 then
                ctx.openDeep({ kind = "recipe", spellID = sp, itemID = id > 0 and id or nil, name = story.cartName or story.title })
            elseif id > 0 then
                ctx.openDeep({ kind = "item", itemID = id, name = story.cartName or story.title })
            end
        end)
        row:Hide()
        rows[i] = row
    end

    ctx.news = {
        panel = panel, hdr = hdr, titleFs = titleFs, filterBtns = filterBtns,
        hdrSep = hdrSep, body = body, sb = sb, emptyFs = emptyFs, rows = rows,
    }
    ctx.view.newsPanel = panel
end

function Builders.buildSpotlightPanel(ctx)
    local panel = H.createCard(ctx.view, "cardBg", "border", "cyan")

    -- Header (36px)
    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    hdr:SetHeight(36)

    local icon = hdr:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", hdr, "LEFT", 10, 0)

    local deepBtn = H.createMiniButton(hdr, "Deep >", 46, 20, 10, function()
        local st = ctx.state.selectedStock
        if not st then return end
        if st.kind == "recipe" and st.spellID then
            ctx.openDeep({ kind = "recipe", spellID = st.spellID, itemID = st.itemID, name = st.name, icon = st.icon })
        elseif st.itemID then
            ctx.openDeep({ kind = "item", itemID = st.itemID, name = st.name, icon = st.icon })
        end
    end)
    deepBtn:SetPoint("RIGHT", hdr, "RIGHT", -8, 0)

    local pinBtn = H.createMiniButton(hdr, "Pin", 38, 20, 10, function()
        local st = ctx.state.selectedStock
        if not st then return end
        if ctx.state.pinnedKey == st.key then
            ctx.state.pinnedKey = nil
            ctx.view:Refresh(false)
        else
            ctx.view:SelectStock(st.key, true)
        end
    end)
    pinBtn:SetPoint("RIGHT", deepBtn, "LEFT", -3, 0)
    pinBtn._accent = true

    local starBtn = CreateFrame("Button", nil, hdr)
    starBtn:SetSize(22, 22)
    starBtn:SetPoint("RIGHT", pinBtn, "LEFT", -3, 0)
    starBtn.icon = starBtn:CreateTexture(nil, "ARTWORK")
    starBtn.icon:SetSize(14, 14)
    starBtn.icon:SetPoint("CENTER", starBtn, "CENTER", 0, 0)
    starBtn.icon:SetTexture(H.asset("icon_star", "icon_star"))
    starBtn:SetScript("OnClick", function()
        local st = ctx.state.selectedStock
        if not st then return end
        local WL = ns.Watchlist
        if WL and type(WL.Toggle) == "function" then
            WL.Toggle({
                key = st.key,
                kind = st.kind,
                itemID = st.itemID,
                spellID = st.spellID,
                name = st.name,
            })
            if ns.DashboardBloombergModel and ns.DashboardBloombergModel.InvalidateCache then
                ns.DashboardBloombergModel.InvalidateCache()
            end
            ctx.view:Refresh(false)
        end
    end)
    starBtn:SetScript("OnEnter", function(self)
        local st = ctx.state.selectedStock
        if not (_G.GameTooltip and st) then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
        _G.GameTooltip:ClearLines()
        _G.GameTooltip:AddLine(st.isWatched and "Remove from Watchlist" or "Add to Watchlist", 1, 0.82, 0.2)
        _G.GameTooltip:Show()
    end)
    starBtn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    local titleFs = H.makeFS(hdr, 12, "semibold", "LEFT")
    titleFs:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    titleFs:SetPoint("RIGHT", starBtn, "LEFT", -4, 0)
    titleFs:SetText("Market Spotlight")

    local hdrSep = panel:CreateTexture(nil, "BORDER")
    hdrSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -36)
    hdrSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -36)
    hdrSep:SetHeight(1)

    -- Price Band (36px)
    local priceFs = H.makeFS(panel, 19, "semibold", "LEFT")
    priceFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -42)
    priceFs:SetText("--")

    local deltaFs = H.makeFS(panel, 11, "semibold", "RIGHT")
    deltaFs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -44)
    deltaFs:SetText("")

    local deltaSubFs = H.makeFS(panel, 10, "regular", "RIGHT")
    deltaSubFs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -58)
    deltaSubFs:SetText("")

    priceFs:SetPoint("RIGHT", deltaFs, "LEFT", -6, 0)

    -- Compact 2x2 Stat Matrix (40px)
    local stat1L = H.makeFS(panel, 10, "regular", "LEFT")
    stat1L:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -76)
    local stat1R = H.makeFS(panel, 10, "regular", "RIGHT")
    stat1R:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -76)

    local stat2L = H.makeFS(panel, 10, "regular", "LEFT")
    stat2L:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -92)
    local stat2R = H.makeFS(panel, 10, "regular", "RIGHT")
    stat2R:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -92)

    local statSep = panel:CreateTexture(nil, "BORDER")
    statSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -109)
    statSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -109)
    statSep:SetHeight(1)

    -- Area Sparkline Canvas
    local canvas = CreateFrame("Button", nil, panel)
    canvas:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -114)
    canvas:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    canvas:SetScript("OnClick", function()
        local st = ctx.state.selectedStock
        if st and st.key then ctx.view:SelectStock(st.key, true) end
    end)
    canvas:SetScript("OnEnter", function(self)
        Render.showStockTooltip(ctx, self, ctx.state.selectedStock, "Click chart to pin to Broadcast Stage")
    end)
    canvas:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    local plotWell = H.createPlotWell(canvas)

    local legendFs = H.makeFS(canvas, 9, "semibold", "LEFT")
    legendFs:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, 0)

    local styleChip = H.createMiniButton(canvas, "Candles", 46, 14, 9, function()
        ctx.view:ToggleChartStyle()
    end)
    styleChip:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -2, 0)
    styleChip._active = true
    legendFs:SetPoint("RIGHT", styleChip, "LEFT", -6, 0)

    local midGrid = canvas:CreateTexture(nil, "BACKGROUND", nil, 2)
    midGrid:SetHeight(1)
    midGrid:Hide()

    local hiFs = H.makeFS(canvas, 9, "regular", "RIGHT")
    hiFs:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -2, -21)
    local loFs = H.makeFS(canvas, 9, "regular", "RIGHT")
    loFs:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -2, 14)

    local xStartFs = H.makeFS(canvas, 8, "regular", "LEFT")
    xStartFs:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 4, 1)
    local xEndFs = H.makeFS(canvas, 8, "regular", "RIGHT")
    xEndFs:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -56, 1)

    local emptyFs = H.makeFS(canvas, 10, "regular", "CENTER")
    emptyFs:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    emptyFs:SetText("Select a stock on the right rail")
    emptyFs:Hide()

    local fillPool, bodyPool, dotPool = {}, {}, {}
    for i = 1, C.MAX_SPOT_SEGS + 1 do
        local f = canvas:CreateTexture(nil, "ARTWORK", nil, 0)
        f:Hide()
        fillPool[i] = f

        local b = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
        b:Hide()
        bodyPool[i] = b

        local dt = canvas:CreateTexture(nil, "ARTWORK", nil, 4)
        dt:SetSize(4, 4)
        dt:SetTexture(H.asset("circle_fill", "circle_fill"))
        dt:Hide()
        dotPool[i] = dt
    end
    local baseDots = {}
    for i = 1, C.MAX_SPOT_BASE do
        local d = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
        d:SetHeight(1)
        d:Hide()
        baseDots[i] = d
    end
    local wickPool = H.createLinePool(canvas, C.MAX_SPOT_SEGS + 1, "ARTWORK", 2)
    local linePool = H.createLinePool(canvas, C.MAX_SPOT_SEGS, "ARTWORK", 3)

    ctx.spot = {
        panel = panel, hdr = hdr, icon = icon, titleFs = titleFs,
        starBtn = starBtn, pinBtn = pinBtn, deepBtn = deepBtn, hdrSep = hdrSep,
        priceFs = priceFs, deltaFs = deltaFs, deltaSubFs = deltaSubFs,
        stat1L = stat1L, stat1R = stat1R, stat2L = stat2L, stat2R = stat2R, statSep = statSep,
        canvas = canvas, plotWell = plotWell, legendFs = legendFs, styleChip = styleChip, midGrid = midGrid,
        hiFs = hiFs, loFs = loFs, xStartFs = xStartFs, xEndFs = xEndFs, emptyFs = emptyFs,
        fillPool = fillPool, bodyPool = bodyPool, dotPool = dotPool,
        baseDots = baseDots, wickPool = wickPool, linePool = linePool,
    }
    ctx.view.spotlightPanel = panel
end

function Builders.buildActivePanel(ctx)
    local panel = H.createCard(ctx.view, "cardBg", "border", "neutral")

    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    hdr:SetHeight(28)

    local titleFs = H.makeFS(hdr, 11, "semibold", "LEFT")
    titleFs:SetPoint("LEFT", hdr, "LEFT", 10, 0)
    titleFs:SetText("MOST ACTIVE")

    local subFs = H.makeFS(hdr, 9, "regular", "RIGHT")
    subFs:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)
    subFs:SetText("30D LEDGER")

    local hdrSep = panel:CreateTexture(nil, "BORDER")
    hdrSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -28)
    hdrSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -28)
    hdrSep:SetHeight(1)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -30)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)

    local emptyFs = H.makeFS(body, 10, "regular", "CENTER")
    emptyFs:SetPoint("CENTER", body, "CENTER", 0, 0)
    emptyFs:SetText("No ledger activity yet")
    emptyFs:Hide()

    local rows = {}
    for i = 1, C.MAX_ACT_ROWS do
        local row = CreateFrame("Button", nil, body)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:Hide()

        row.selBar = row:CreateTexture(nil, "ARTWORK")
        row.selBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.selBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.selBar:SetWidth(2)
        row.selBar:Hide()

        row.deltaFs = H.makeFS(row, 10, "semibold", "RIGHT")
        row.deltaFs:SetWidth(62)
        row.deltaFs:SetPoint("RIGHT", row, "RIGHT", -6, 0)

        row.priceFs = H.makeFS(row, 11, "semibold", "RIGHT")
        row.priceFs:SetWidth(58)
        row.priceFs:SetPoint("RIGHT", row.deltaFs, "LEFT", -6, 0)

        row.nameFs = H.makeFS(row, 11, "semibold", "LEFT")
        row.nameFs:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.nameFs:SetPoint("RIGHT", row.priceFs, "LEFT", -4, 0)

        row.sep = row:CreateTexture(nil, "BORDER")
        row.sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
        row.sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)
        row.sep:SetHeight(1)

        row:SetScript("OnEnter", function(self)
            local pal = H.getPalette()
            local hv = pal.rowHover or { 1, 1, 1, 0.07 }
            self.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4] or 0.07)
            self.hl:Show()
            Render.showStockTooltip(ctx, self, self._stock, "Click to inspect in Market Spotlight")
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            if self._stock and self._stock.key then
                ctx.view:SelectStock(self._stock.key, false)
            end
        end)
        row:Hide()
        rows[i] = row
    end

    ctx.active = {
        panel = panel, hdr = hdr, titleFs = titleFs, subFs = subFs,
        hdrSep = hdrSep, body = body, emptyFs = emptyFs, rows = rows,
    }
    ctx.view.activePanel = panel
end

function Builders.buildTimingPanel(ctx)
    local panel = H.createCard(ctx.view, "cardAltBg", "border", "amber")

    local badge = CreateFrame("Frame", nil, panel)
    badge:SetSize(104, 18)
    badge:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    badge.bg = badge:CreateTexture(nil, "BACKGROUND")
    badge.bg:SetAllPoints()
    badge.label = H.makeFS(badge, 9, "semibold", "CENTER")
    badge.label:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge.label:SetText("MARKET WINDOWS")

    local watchBtn = H.createMiniButton(panel, "Watchlist >", 72, 18, 10, function()
        if type(ctx.opts.onOpenWatchlist) == "function" then
            ctx.opts.onOpenWatchlist()
        elseif ns.app and type(ns.app.setTab) == "function" then
            ns.app.setTab("watchlist")
        end
    end)
    watchBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)

    local line1 = H.makeFS(panel, 10, "semibold", "LEFT")
    line1:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -31)
    line1:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -31)
    line1:SetText("Sell: -- | Buy: --")

    local line2 = H.makeFS(panel, 10, "regular", "LEFT")
    line2:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
    line2:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    line2:SetText("Normal-Horde")

    ctx.timing = {
        panel = panel, badge = badge, watchBtn = watchBtn, line1 = line1, line2 = line2,
    }
    ctx.view.timingPanel = panel
end

function Builders.buildRailPanel(ctx)
    local panel = H.createCard(ctx.view, "cardAltBg", "border", "neutral")

    local filterBar = CreateFrame("Frame", nil, panel)
    filterBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -5)
    filterBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -5)
    filterBar:SetHeight(24)

    local defs = {
        { key = "all",       label = "All" },
        { key = "watchlist", label = "Favs" },
        { key = "crafts",    label = "Crafts" },
        { key = "reagents",  label = "Mats" },
    }
    local filterBtns = {}
    for idx, def in ipairs(defs) do
        local b = H.createMiniButton(filterBar, def.label, 42, 22, 10, function()
            ctx.state.filterKey = def.key
            ctx.state.railOffset = 0
            Render.paintRailFilters(ctx)
            ctx.view:Refresh(false)
        end)
        b._filterKey = def.key
        filterBtns[idx] = b
    end

    local hdrSep = panel:CreateTexture(nil, "BORDER")
    hdrSep:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -32)
    hdrSep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -32)
    hdrSep:SetHeight(1)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -35)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 6)
    if body.EnableMouseWheel then
        body:EnableMouseWheel(true)
        body:SetScript("OnMouseWheel", function(_, delta)
            local list = (ctx.state.snap and ctx.state.snap.stocks) or {}
            local maxOff = max(0, #list - ctx.state.visibleRailTiles)
            local nextOff = H.clamp(ctx.state.railOffset - (delta > 0 and 1 or -1), 0, maxOff)
            if nextOff ~= ctx.state.railOffset then
                ctx.state.railOffset = nextOff
                Render.renderRail(ctx)
            end
        end)
    end

    local sb = H.createScrollbar(body)
    local emptyFs = H.makeFS(body, 11, "regular", "CENTER")
    emptyFs:SetPoint("CENTER", body, "CENTER", 0, 0)
    emptyFs:SetWordWrap(true)
    if emptyFs.SetMaxLines then emptyFs:SetMaxLines(3) end
    emptyFs:SetText("No stocks in this filter.\nStar items in Watchlist.")
    emptyFs:Hide()

    local tiles = {}
    for i = 1, C.MAX_RAIL_TILES do
        local tile = CreateFrame("Button", nil, body)
        tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        tile.selBg = tile:CreateTexture(nil, "BACKGROUND")
        tile.selBg:SetAllPoints()
        tile.selBg:Hide()

        tile.hl = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
        tile.hl:SetAllPoints()
        tile.hl:Hide()

        tile.selBar = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        tile.selBar:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, -2)
        tile.selBar:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 2)
        tile.selBar:SetWidth(3)
        tile.selBar:Hide()

        tile.chgFs = H.makeFS(tile, 10, "semibold", "RIGHT")
        tile.chgFs:SetWidth(66)
        tile.chgFs:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -5)

        tile.nameFs = H.makeFS(tile, 10, "semibold", "LEFT")
        tile.nameFs:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -5)
        tile.nameFs:SetPoint("RIGHT", tile.chgFs, "LEFT", -4, 0)

        tile.pctFs = H.makeFS(tile, 10, "semibold", "RIGHT")
        tile.pctFs:SetWidth(58)
        tile.pctFs:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -20)

        tile.priceFs = H.makeFS(tile, 13, "semibold", "LEFT")
        tile.priceFs:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -19)
        tile.priceFs:SetPoint("RIGHT", tile.pctFs, "LEFT", -4, 0)

        tile.spark = CreateFrame("Frame", nil, tile)
        tile.spark:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 8, 5)
        tile.spark:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 5)
        tile.spark:SetHeight(20)

        tile.baseDots = {}
        for d = 1, C.MAX_RAIL_BASE do
            local dot = tile.spark:CreateTexture(nil, "ARTWORK", nil, 0)
            dot:SetHeight(1)
            dot:Hide()
            tile.baseDots[d] = dot
        end
        tile.linePool = H.createLinePool(tile.spark, C.MAX_RAIL_SEGS, "ARTWORK", 2)

        tile.sep = tile:CreateTexture(nil, "BORDER")
        tile.sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 4, 0)
        tile.sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -4, 0)
        tile.sep:SetHeight(1)

        tile:SetScript("OnEnter", function(self)
            local pal = H.getPalette()
            local hv = pal.rowHover or { 1, 1, 1, 0.07 }
            self.hl:SetColorTexture(hv[1], hv[2], hv[3], hv[4] or 0.07)
            self.hl:Show()
            Render.showStockTooltip(ctx, self, self._stock, "Click: Spotlight | Double-click: Pin Stage | Right-click: Deep")
        end)
        tile:SetScript("OnLeave", function(self)
            self.hl:Hide()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        tile:SetScript("OnClick", function(self, button)
            local st = self._stock
            if not st then return end
            if button == "RightButton" then
                if st.kind == "recipe" and st.spellID then
                    ctx.openDeep({ kind = "recipe", spellID = st.spellID, itemID = st.itemID, name = st.name, icon = st.icon })
                elseif st.itemID then
                    ctx.openDeep({ kind = "item", itemID = st.itemID, name = st.name, icon = st.icon })
                end
            else
                ctx.view:SelectStock(st.key, false)
            end
        end)
        tile:SetScript("OnDoubleClick", function(self)
            if self._stock and self._stock.key then
                ctx.view:SelectStock(self._stock.key, true)
            end
        end)
        tile:Hide()
        tiles[i] = tile
    end

    ctx.rail = {
        panel = panel, filterBar = filterBar, filterBtns = filterBtns,
        hdrSep = hdrSep, body = body, sb = sb, emptyFs = emptyFs, tiles = tiles,
    }
    ctx.view.railPanel = panel
end

---------------------------------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------------------------------
function Render.showStageTooltip(ctx, hitBtn)
    local pt = hitBtn and hitBtn._pt
    local slide = ctx.state.activeSlide
    if not (_G.GameTooltip and pt and slide) then return end
    local pal = H.getPalette()
    if ctx.stage.crosshair and hitBtn._cx then
        local sep = pal.accentOrange or { 1, 0.6, 0.18, 0.7 }
        ctx.stage.crosshair:ClearAllPoints()
        ctx.stage.crosshair:SetPoint("BOTTOMLEFT", ctx.stage.canvas, "BOTTOMLEFT", hitBtn._cx, 18)
        ctx.stage.crosshair:SetPoint("TOPLEFT", ctx.stage.canvas, "TOPLEFT", hitBtn._cx, -16)
        ctx.stage.crosshair:SetColorTexture(sep[1], sep[2], sep[3], 0.55)
        ctx.stage.crosshair:Show()
    end

    local tt = _G.GameTooltip
    tt:SetOwner(hitBtn, "ANCHOR_TOP")
    tt:ClearLines()
    tt:AddLine(tostring(slide.title or "Broadcast Stage"), 1, 0.82, 0.2)
    if pt.label then
        tt:AddDoubleLine("Period", tostring(pt.label), 0.75, 0.78, 0.84, 1, 1, 1)
    end
    local val = H.safeNum(pt.value, 0) or 0
    local isProfit = (slide.kind == "profit" or slide.id == "profit")
    local primaryLbl = isProfit and "AH Profit"
        or ((slide.kind == "wealth" or slide.id == "wealth") and "Net Worth"
        or (slide.series1Label or "Min Price"))
    if slide.kind == "vol_price" and pt.open and pt.high and pt.low and pt.close then
        local isUp = (pt.close >= pt.open)
        local ur, ug, ub = isUp and 0.25 or 1.0, isUp and 0.90 or 0.36, isUp and 0.48 or 0.34
        tt:AddDoubleLine("Open / Close", format("%s -> %s", H.formatCopper(pt.open, false), H.formatCopper(pt.close, false)),
            0.75, 0.78, 0.84, ur, ug, ub)
        tt:AddDoubleLine("Day Range (Lo - Hi)", format("%s - %s", H.formatCopper(pt.low, false), H.formatCopper(pt.high, false)),
            0.75, 0.78, 0.84, 0.92, 0.94, 0.98)
    else
        tt:AddDoubleLine(primaryLbl, H.formatCopper(val, isProfit), 0.75, 0.78, 0.84, 0.3, 0.9, 0.45)
    end

    local v2 = H.safeNum(pt.value2, nil)
    if v2 ~= nil and v2 > 0 then
        tt:AddDoubleLine(slide.series2Label or "Craft Cost", H.formatCopper(v2, false), 0.75, 0.78, 0.84, 1.0, 0.65, 0.25)
        local spread = val - v2
        tt:AddDoubleLine("Spread", H.formatCopper(spread, true), 0.75, 0.78, 0.84, spread >= 0 and 0.3 or 1.0, spread >= 0 and 0.9 or 0.35, 0.35)
    end

    local vol = H.safeNum(pt.volume, 0) or 0
    if vol > 0 then
        tt:AddDoubleLine("Supply Volume", format("%d listed", floor(vol + 0.5)), 0.75, 0.78, 0.84, 0.55, 0.80, 1.0)
    end

    local rv = H.safeNum(slide.refValue, nil)
    if rv and rv > 0 then
        local diffPct = ((val - rv) / rv) * 100
        tt:AddDoubleLine(slide.refLabel or "Reference", format("%s (%s)", H.formatCopper(rv, false), H.formatPct(diffPct)),
            0.75, 0.78, 0.84, 1, 0.82, 0.35)
    end
    tt:Show()
end

function Render.showNewsTooltip(ctx, row)
    local story = row and row._story
    if not (_G.GameTooltip and story) then return end
    local tt = _G.GameTooltip
    tt:SetOwner(row, "ANCHOR_TOP")
    tt:ClearLines()
    tt:AddLine(tostring(story.title or story.headline or ""), 1, 0.82, 0.2, true)
    if story.detail and story.detail ~= "" then
        tt:AddLine(tostring(story.detail), 0.9, 0.92, 0.95, true)
    end
    local hint = story.cartItemID
        and "Left-click: Deep Analysis | Shift-click: Add to Cart"
        or "Left-click: Inspect / Deep Analysis"
    tt:AddLine(hint, 0.6, 0.7, 0.82, true)
    tt:Show()
end

function Render.showStockTooltip(ctx, owner, st, hintText)
    if not (_G.GameTooltip and st) then return end
    local tt = _G.GameTooltip
    tt:SetOwner(owner, "ANCHOR_LEFT")
    tt:ClearLines()
    tt:AddLine(tostring(st.name or st.shortName or "Stock"), 1, 0.82, 0.2)
    local price = H.safeNum(st.primaryPrice, H.safeNum(st.ahPrice, 0)) or 0
    tt:AddDoubleLine("Current Price", H.formatCopper(price, false), 0.75, 0.78, 0.84, 1, 1, 1)
    if st.deltaCopper ~= nil or st.deltaPct ~= nil then
        tt:AddDoubleLine("Change", format("%s (%s)", H.formatCopper(st.deltaCopper or 0, true), H.formatPct(st.deltaPct or 0)),
            0.75, 0.78, 0.84, (st.deltaCopper or 0) >= 0 and 0.3 or 1.0, (st.deltaCopper or 0) >= 0 and 0.9 or 0.35, 0.35)
    end
    local vol = H.safeNum(st.vol, H.safeNum(st.listedQty, 0)) or 0
    if vol > 0 then
        tt:AddDoubleLine("Listed Supply", tostring(floor(vol + 0.5)), 0.75, 0.78, 0.84, 0.55, 0.80, 1.0)
    end
    if st.craftCost and st.craftCost > 0 then
        tt:AddDoubleLine("Craft Cost", H.formatCopper(st.craftCost, false), 0.75, 0.78, 0.84, 1.0, 0.72, 0.30)
    end
    if st.netProfit ~= nil then
        tt:AddDoubleLine("Est. Profit", H.formatCopper(st.netProfit, true), 0.75, 0.78, 0.84,
            st.netProfit >= 0 and 0.3 or 1.0, st.netProfit >= 0 and 0.9 or 0.35, 0.35)
    end
    if st.ledgerAvgBuyPrice and st.ledgerAvgBuyPrice > 0 then
        tt:AddDoubleLine("Your Avg Buy", H.formatCopper(st.ledgerAvgBuyPrice, false), 0.75, 0.78, 0.84, 0.9, 0.9, 0.95)
    elseif st.ledgerAvgCraftCost and st.ledgerAvgCraftCost > 0 then
        tt:AddDoubleLine("Your Avg Craft", H.formatCopper(st.ledgerAvgCraftCost, false), 0.75, 0.78, 0.84, 0.9, 0.9, 0.95)
    end
    if st.bestSellText and st.bestSellText ~= "--" then
        tt:AddDoubleLine("Best Sell", tostring(st.bestSellText), 0.75, 0.78, 0.84, 0.35, 0.9, 0.5)
    end
    if st.bestBuyText and st.bestBuyText ~= "--" then
        tt:AddDoubleLine("Best Buy", tostring(st.bestBuyText), 0.75, 0.78, 0.84, 0.45, 0.8, 1.0)
    end
    if hintText then
        tt:AddLine(hintText, 0.6, 0.7, 0.82, true)
    end
    tt:Show()
end

---------------------------------------------------------------------------------------------------
-- Rendering Routines (Zero Allocations)
---------------------------------------------------------------------------------------------------
function Render.hideStagePools(s)
    if s.plotWell then s.plotWell:Hide() end
    if s.volSep then s.volSep:Hide() end
    for i = 1, C.MAX_STAGE_PTS do
        s.volPool[i]:Hide()
        s.fillPool[i]:Hide()
        s.bodyPool[i]:Hide()
        s.dotPool[i]:Hide()
        s.wickPool[i]:Hide()
        s.linePool[i]:Hide()
        s.line2Pool[i]:Hide()
        s.hoverPool[i]:Hide()
    end
    for i = 1, C.MAX_REF_DOTS do s.refDots[i]:Hide() end
    for i = 1, 3 do s.hGrid[i]:Hide(); s.yLabels[i]:Hide() end
    for i = 1, C.MAX_X_LABELS do s.xLabels[i]:Hide() end
    s.zeroLine:Hide()
    s.refLabelFs:Hide()
    s.crosshair:Hide()
end

function Render.renderStage(ctx)
    local s = ctx.stage
    local pal = H.getPalette()
    local isLight = (pal.mode == "light")
    local snap = ctx.state.snap
    local slides = (snap and type(snap.slides) == "table" and #snap.slides > 0) and snap.slides or {}
    local totalSlides = max(1, #slides)
    ctx.state.slideIndex = H.clamp(ctx.state.slideIndex or 1, 1, totalSlides)
    local slide = slides[ctx.state.slideIndex] or { id = "vol_price", kind = "vol_price", title = "Broadcast Stage", points = {} }
    ctx.state.activeSlide = slide

    local kind = slide.kind or slide.id or "vol_price"
    local chartStyle = (ctx.state.chartStyle == "line") and "line" or "candles"
    local badgeTxt = slide.badge or C.SLIDE_BADGES[kind] or "MARKET"
    s.slideBadge.label:SetText(badgeTxt)
    local bw = max(72, min(116, #badgeTxt * 6 + 14))
    s.slideBadge:SetWidth(bw)

    if s.styleBtn then
        s.styleBtn.label:SetText(chartStyle == "candles" and "Candles" or "Line")
        s.styleBtn._active = (chartStyle == "candles")
        s.styleBtn:Paint(pal)
    end

    local pinned = (ctx.state.pinnedKey ~= nil)
    s.unpinBtn:SetShown(pinned)
    s.titleFs:ClearAllPoints()
    s.titleFs:SetPoint("LEFT", s.slideBadge, "RIGHT", 8, 0)
    s.titleFs:SetPoint("RIGHT", pinned and s.unpinBtn or s.styleBtn, "LEFT", -6, 0)
    s.titleFs:SetText(tostring(slide.title or "Broadcast Stage"))
    s.counterFs:SetText(format("%d/%d", ctx.state.slideIndex, totalSlides))
    s.autoBtn.label:SetText(ctx.state.autoRotate and "Auto: On" or "Auto: Off")
    s.autoBtn._active = ctx.state.autoRotate
    s.autoBtn:Paint(pal)

    local dotCol = (pinned or not ctx.state.autoRotate) and pal.accentOrange or pal.accentGreen
    s.liveDot:SetVertexColor(dotCol[1], dotCol[2], dotCol[3], 1)

    Render.hideStagePools(s)

    local pts = H.samplePoints(slide.points or {}, C.MAX_STAGE_PTS)
    local n = #pts
    if n == 0 then
        s.legendFs:SetText("")
        s.volMaxFs:SetText("")
        s.emptyFs:SetText(tostring(slide.emptyText or "No chart data yet - scan the AH or record ledger activity"))
        s.emptyFs:Show()
        return
    end
    s.emptyFs:Hide()

    local cw = max(160, H.safeNum(s.canvas:GetWidth(), 420) or 420)
    local ch = max(90, H.safeNum(s.canvas:GetHeight(), 160) or 160)
    local padL, padR, padB, padT = 8, 64, 18, 22
    local plotW = max(60, cw - padL - padR)
    local plotH = max(44, ch - padB - padT)

    if s.plotWell then
        s.plotWell:ShowBox(padL, padB, plotW, plotH, pal)
    end

    local isProfit = (kind == "profit")
    local isCraftSpread = (kind == "craft_spread")
    local isVolPrice = (kind == "vol_price")
    local useCandles = isVolPrice and (chartStyle == "candles")

    local minV, maxV, maxVol, hasV2 = nil, nil, 0, false
    for i = 1, n do
        local p = pts[i]
        local v = H.safeNum(p.value, 0) or 0
        local loPt = isVolPrice and (H.safeNum(p.low, v) or v) or v
        local hiPt = isVolPrice and (H.safeNum(p.high, v) or v) or v
        minV = (minV == nil) and min(v, loPt) or min(minV, v, loPt)
        maxV = (maxV == nil) and max(v, hiPt) or max(maxV, v, hiPt)
        local v2 = H.safeNum(p.value2, nil)
        if isCraftSpread and v2 ~= nil and v2 > 0 then
            hasV2 = true
            minV = min(minV, v2)
            maxV = max(maxV, v2)
        end
        if isVolPrice then
            local vol = H.safeNum(p.volume, 0) or 0
            if vol > maxVol then maxVol = vol end
        end
    end

    local refVal = H.safeNum(slide.refValue, nil)
    if refVal and refVal > 0 and not isProfit then
        minV = min(minV, refVal)
        maxV = max(maxV, refVal)
    end
    if isProfit then
        minV = min(0, minV or 0)
        maxV = max(0, maxV or 0)
    end
    if maxV == minV then
        local pad = max(100, floor(abs(maxV or 0) * 0.10))
        minV = (minV or 0) - pad
        maxV = (maxV or 0) + pad
    else
        local span = maxV - minV
        if not isProfit then minV = max(0, minV - span * 0.08) end
        maxV = maxV + span * 0.08
    end
    local spanV = max(1, maxV - minV)

    local hasVolBand = isVolPrice and (maxVol > 0)
    local volH = hasVolBand and max(14, floor(plotH * 0.22)) or 0
    local priceB = hasVolBand and (padB + volH + 5) or padB
    local priceH = max(28, plotH - (priceB - padB))

    local function mapY(v)
        return priceB + floor(((v - minV) / spanV) * priceH + 0.5)
    end

    -- Gridlines + Y-axis labels across price zone
    local gridCol = pal.separator or { 1, 1, 1, 0.14 }
    local axisCol = isLight and pal.textMuted or pal.textSecondary
    local yVals = { minV, minV + spanV * 0.5, maxV }
    for i = 1, 3 do
        local gy = mapY(yVals[i])
        local gl = s.hGrid[i]
        gl:ClearAllPoints()
        gl:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", padL, gy)
        gl:SetWidth(plotW)
        gl:SetColorTexture(gridCol[1], gridCol[2], gridCol[3], isLight and 0.20 or 0.16)
        gl:Show()

        local yl = s.yLabels[i]
        yl:ClearAllPoints()
        yl:SetPoint("BOTTOMRIGHT", s.canvas, "BOTTOMRIGHT", -4, gy - 5)
        yl:SetText(H.formatCopper(yVals[i], isProfit))
        H.setTextColor(yl, axisCol)
        yl:Show()
    end

    if hasVolBand and s.volSep then
        s.volSep:ClearAllPoints()
        s.volSep:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", padL, padB + volH + 2)
        s.volSep:SetWidth(plotW)
        if isLight then
            s.volSep:SetColorTexture(gridCol[1], gridCol[2], gridCol[3], 0.28)
        else
            s.volSep:SetColorTexture(0.28, 0.66, 0.94, 0.30)
        end
        s.volSep:Show()
    end

    local slotCentered = isVolPrice or isProfit
    local slotW = plotW / max(1, n)
    local function mapX(i)
        if n == 1 then return padL + floor(plotW * 0.5) end
        if slotCentered then
            return padL + floor((i - 0.5) * slotW + 0.5)
        end
        return padL + floor(((i - 1) / (n - 1)) * plotW + 0.5)
    end

    -- X-axis labels aligned cleanly to data points / candle slots
    local xCount = min(C.MAX_X_LABELS, n)
    for i = 1, xCount do
        local idx = (xCount == 1) and 1 or H.clamp(floor(((i - 1) / (xCount - 1)) * (n - 1) + 1.5), 1, n)
        local cx = mapX(idx)
        local xl = s.xLabels[i]
        xl:ClearAllPoints()
        xl:SetPoint("BOTTOM", s.canvas, "BOTTOMLEFT", H.clamp(cx, padL + 18, padL + plotW - 18), 2)
        xl:SetText(tostring(pts[idx].label or ""))
        H.setTextColor(xl, axisCol)
        xl:Show()
    end

    local gCol = pal.accentGreen or { 0.19, 0.82, 0.35, 1 }
    local rCol = pal.accentRed or { 1.00, 0.32, 0.30, 1 }
    local secCol = pal.accentOrange or { 1.00, 0.60, 0.18, 1 }
    local neuVolCol = pal.accentBlue or { 0.32, 0.68, 0.98, 1 }
    local greenHex = isLight and "167a36" or "32d964"
    local redHex = isLight and "c02620" or "ff524d"
    local amberHex = isLight and "b85c04" or "ffa63d"
    local blueHex = isLight and "1862b8" or "58a6ff"

    -- Header KPI strip & Ultra-Compact Color Legend
    if isProfit then
        s.volMaxFs:SetText(tostring(slide.subtitle or ""))
        s.legendFs:SetText(format("|cff%sProfit|r   |cff%sLoss|r%s",
            greenHex, redHex, (refVal and refVal ~= 0) and format("   |cff%s-- Avg|r", amberHex) or ""))
    elseif isCraftSpread then
        s.volMaxFs:SetText(tostring(slide.subtitle or ""))
        s.legendFs:SetText(format("|cff%sSale Price|r   |cff%sCraft Cost|r", greenHex, amberHex))
    elseif isVolPrice then
        local dp = H.safeNum(slide.deltaPct, 0) or 0
        local pTxt = slide.price and H.formatCopper(slide.price, false) or H.formatCopper(pts[n].value, false)
        local dHex = (dp > 0) and greenHex or ((dp < 0) and redHex or (isLight and "444852" or "aeb4c0"))
        local volPart = hasVolBand and format("  |  Vol max %d", floor(maxVol + 0.5)) or ""
        s.volMaxFs:SetText(format("Now %s |cff%s(%s)|r%s", pTxt, dHex, H.formatPct(dp), volPart))
        local refPart = (refVal and refVal > 0) and format("   |cff%s-- Avg|r", amberHex) or ""
        local volLeg = hasVolBand and format("   |cff%sBars:Vol|r", blueHex) or ""
        if useCandles then
            s.legendFs:SetText(format("|cff%s+Up|r   |cff%s-Dn|r%s%s", greenHex, redHex, volLeg, refPart))
        else
            s.legendFs:SetText(format("|cff%sAbove|r / |cff%sBelow|r%s%s", greenHex, redHex, volLeg, refPart))
        end
    else
        s.volMaxFs:SetText(tostring(slide.subtitle or ""))
        s.legendFs:SetText(format("|cff%sAbove|r / |cff%sBelow Start|r", greenHex, redHex))
    end

    if isProfit then
        local zy = mapY(0)
        s.zeroLine:ClearAllPoints()
        s.zeroLine:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", padL, zy)
        s.zeroLine:SetWidth(plotW)
        s.zeroLine:SetColorTexture(gridCol[1], gridCol[2], gridCol[3], 0.45)
        s.zeroLine:Show()

        local barW = H.clamp(floor(slotW * 0.62), 3, 28)
        for i = 1, n do
            local v = H.safeNum(pts[i].value, 0) or 0
            local cx = mapX(i)
            local yv = mapY(v)
            local bar = s.volPool[i]
            local bh = max(2, abs(yv - zy))
            local bc = (v >= 0) and gCol or rCol
            bar:ClearAllPoints()
            if v >= 0 then
                bar:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", cx - floor(barW * 0.5), zy)
            else
                bar:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", cx - floor(barW * 0.5), zy - bh)
            end
            bar:SetSize(barW, bh)
            bar:SetColorTexture(bc[1], bc[2], bc[3], 0.86)
            bar:Show()

            local hb = s.hoverPool[i]
            hb._pt = pts[i]
            hb._cx = cx
            hb:ClearAllPoints()
            hb:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", padL + floor((i - 1) * slotW), padB)
            hb:SetSize(max(4, ceil(slotW)), plotH)
            hb:Show()
        end
        return
    end

    -- Neutral Blue Supply Volume Bars inside bottom dedicated 22% sub-zone (never green/red)
    if hasVolBand then
        local barW = H.clamp(floor(slotW * 0.48), 3, 22)
        local maxBarH = max(6, volH - 3)
        local vbCol = isLight and { 0.16, 0.48, 0.82, 1.0 } or { 0.30, 0.68, 0.96, 1.0 }
        for i = 1, n do
            local p = pts[i]
            local vol = H.safeNum(p.volume, 0) or 0
            if vol > 0 then
                local cx = mapX(i)
                local bh = max(2, floor((vol / maxVol) * maxBarH + 0.5))
                local bar = s.volPool[i]
                bar:ClearAllPoints()
                bar:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", H.clamp(cx - floor(barW * 0.5), padL, padL + plotW - barW), padB)
                bar:SetSize(barW, bh)
                bar:SetColorTexture(vbCol[1], vbCol[2], vbCol[3], isLight and 0.42 or 0.48)
                bar:Show()
            end
        end
    end

    -- Dashed reference line (Your Avg Buy / Your Avg Craft Cost / 7d Avg / Period Start)
    if refVal and refVal > 0 then
        local ry = mapY(refVal)
        local dashCol = pal.accentOrange or { 1.0, 0.62, 0.18, 1 }
        local dashStep = plotW / C.MAX_REF_DOTS
        local dashW = max(3, floor(dashStep * 0.56))
        for d = 1, C.MAX_REF_DOTS do
            local dot = s.refDots[d]
            dot:ClearAllPoints()
            dot:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", padL + floor((d - 1) * dashStep), ry)
            dot:SetSize(dashW, 1)
            dot:SetColorTexture(dashCol[1], dashCol[2], dashCol[3], 0.82)
            dot:Show()
        end
        s.refLabelFs:ClearAllPoints()
        local lblY = (ry > priceB + priceH - 16) and max(priceB + 2, ry - 13) or min(priceB + priceH - 12, ry + 3)
        s.refLabelFs:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", padL + 4, lblY)
        s.refLabelFs:SetText(format("%s: %s", slide.refLabel or "Avg", H.formatCopper(refVal, false)))
        H.setTextColor(s.refLabelFs, dashCol)
        s.refLabelFs:Show()
    end

    -- Candlesticks (vol_price + Candles) OR Clean Two-Tone Line / Craft Spread (ZERO sawtooth fillPool blocks)
    local refBase = refVal or H.safeNum(pts[1].value, 0) or 0
    local bodyW = H.clamp(floor(slotW * 0.52), 5, 22)
    local prevX, prevY, prevV, prevY2 = nil, nil, nil, nil
    for i = 1, n do
        local p = pts[i]
        local cx = mapX(i)
        local v = H.safeNum(p.value, 0) or 0
        local cy = mapY(v)

        if useCandles then
            local oV = H.safeNum(p.open, v) or v
            local cV = H.safeNum(p.close, v) or v
            local loV = min(oV, cV, H.safeNum(p.low, v) or v)
            local hiV = max(oV, cV, H.safeNum(p.high, v) or v)
            local yOpen = mapY(oV)
            local yClose = mapY(cV)
            local yLo = H.clamp(mapY(loV), priceB + 1, priceB + priceH - 3)
            local yHi = H.clamp(mapY(hiV), priceB + 3, priceB + priceH - 1)
            if yHi < yLo + 2 then yHi = min(priceB + priceH - 1, yLo + 2) end
            local cCol = (cV > oV) and gCol or ((cV < oV) and rCol or secCol)

            -- Vertical High-Low wick (4-arg CreateLine inside bounds)
            H.setSegmentLine(s.wickPool[i], s.canvas, cx, yLo, cx, yHi, 1.8, cCol, 0.94)

            -- Solid Open-Close candle body
            local bBot = H.clamp(min(yOpen, yClose), priceB + 1, priceB + priceH - 3)
            local bH = max(3, min(priceB + priceH - bBot, abs(yClose - yOpen)))
            local body = s.bodyPool[i]
            body:ClearAllPoints()
            body:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", H.clamp(cx - floor(bodyW * 0.5), padL + 1, padL + plotW - bodyW - 1), bBot)
            body:SetSize(bodyW, bH)
            body:SetColorTexture(cCol[1], cCol[2], cCol[3], 0.94)
            body:Show()
        else
            local segCol
            if isCraftSpread then
                segCol = pal.accentGreen or pal.accentBlue
            else
                local midV = prevV and ((prevV + v) * 0.5) or v
                segCol = (midV >= refBase) and gCol or rCol
            end
            if prevX then
                H.setSegmentLine(s.linePool[i - 1], s.canvas, prevX, prevY, cx, cy, 2.2, segCol, 0.96)
            elseif n == 1 then
                H.setSegmentLine(s.linePool[1], s.canvas, max(padL, cx - 10), cy, min(padL + plotW, cx + 10), cy, 2.4, segCol, 0.96)
            end
            if n <= 14 then
                local dtCol = isCraftSpread and (pal.accentGreen or pal.accentBlue) or ((v >= refBase) and gCol or rCol)
                local dt = s.dotPool[i]
                dt:ClearAllPoints()
                dt:SetPoint("CENTER", s.canvas, "BOTTOMLEFT", cx, cy)
                dt:SetVertexColor(dtCol[1], dtCol[2], dtCol[3], 1)
                dt:Show()
            end

            local v2 = H.safeNum(p.value2, nil)
            local cy2 = (isCraftSpread and hasV2 and v2 and v2 > 0) and mapY(v2) or nil
            if cy2 then
                local spCol = (cy >= cy2) and gCol or rCol
                H.setSegmentLine(s.wickPool[i], s.canvas, cx, min(cy, cy2), cx, max(cy, cy2), 1.2, spCol, 0.34)
                if prevX and prevY2 then
                    H.setSegmentLine(s.line2Pool[i - 1], s.canvas, prevX, prevY2, cx, cy2, 2.0, secCol, 0.92)
                end
            end
            prevY2 = cy2
        end

        local hb = s.hoverPool[i]
        hb._pt = p
        hb._cx = cx
        hb:ClearAllPoints()
        local hx = (n == 1) and padL or (slotCentered and (padL + floor((i - 1) * slotW)) or max(padL, cx - floor(slotW * 0.5)))
        local hw = slotCentered and max(4, ceil(slotW)) or max(4, ceil(plotW / max(1, n - 1)))
        hb:SetPoint("BOTTOMLEFT", s.canvas, "BOTTOMLEFT", H.clamp(hx, padL, padL + plotW - 4), padB)
        hb:SetSize(min(hw, padL + plotW - H.clamp(hx, padL, padL + plotW - 4)), plotH)
        hb:Show()

        prevX, prevY, prevV = cx, cy, v
    end
end

function Render.renderTickerStrip(ctx)
    local s = ctx.stage
    local pal = H.getPalette()
    local k = (ctx.state.snap and ctx.state.snap.kpis) or {}

    -- Cell 1: TODAY PROFIT
    local tp = H.safeNum(k.todayProfit, 0) or 0
    local tc = floor(H.safeNum(k.todaySalesCount, 0) or 0)
    s.kpiCells[1].kVal:SetText(format("%s | %d %s", H.formatCopper(tp, true), tc, tc == 1 and "sale" or "sales"))
    H.setTextColor(s.kpiCells[1].kVal, H.deltaColor(tp, pal, "text"))

    -- Cell 2: NET WORTH
    local nw = H.safeNum(k.netWorth, 0) or 0
    local nwp = H.safeNum(k.netWorthDeltaPct, nil)
    if nwp ~= nil then
        s.kpiCells[2].kVal:SetText(format("%s | %s", H.formatCopper(nw, false), H.formatPct(nwp)))
    else
        s.kpiCells[2].kVal:SetText(H.formatCopper(nw, false))
    end
    H.setTextColor(s.kpiCells[2].kVal, pal.text)

    -- Cell 3: TOP MOVER
    local tm = k.topMover
    if type(tm) == "table" and (tm.shortName or tm.name) then
        local nm = tostring(tm.shortName or tm.name):upper()
        if #nm > 14 then nm = nm:sub(1, 14) end
        local chg = (tm.deltaPct ~= nil and tm.deltaPct ~= 0)
            and H.formatPct(tm.deltaPct)
            or H.formatCopper(tm.deltaCopper or 0, true)
        s.kpiCells[3].kVal:SetText(nm .. " " .. chg)
        H.setTextColor(s.kpiCells[3].kVal, H.deltaColor(tm.deltaPct or tm.deltaCopper or 0, pal, "text"))
    else
        s.kpiCells[3].kVal:SetText("No movers yet")
        H.setTextColor(s.kpiCells[3].kVal, pal.textMuted)
    end
end

function Render.paintNewsFilters(ctx)
    local pal = H.getPalette()
    for k, btn in pairs(ctx.news.filterBtns) do
        btn._active = (k == ctx.state.newsFilter)
        btn:Paint(pal)
    end
end

function Render.renderNews(ctx)
    local np = ctx.news
    local pal = H.getPalette()
    local isLight = (pal.mode == "light")
    local all = (ctx.state.snap and ctx.state.snap.headlines) or {}
    local fKey = ctx.state.newsFilter or "all"
    local filtered = {}
    for _, story in ipairs(all) do
        local cat = story.category or "sales"
        if fKey == "all" or cat == fKey or (fKey == "deals" and cat == "movers") then
            filtered[#filtered + 1] = story
        end
    end
    ctx.state.filteredNews = filtered

    local vis = H.clamp(ctx.state.visibleNewsRows or 6, 1, C.MAX_NEWS_ROWS)
    local maxOff = max(0, #filtered - vis)
    ctx.state.newsOffset = H.clamp(ctx.state.newsOffset or 0, 0, maxOff)
    np.sb:Update(#filtered, vis, ctx.state.newsOffset)

    if #filtered == 0 then
        for i = 1, C.MAX_NEWS_ROWS do np.rows[i]:Hide() end
        np.emptyFs:Show()
        return
    end
    np.emptyFs:Hide()

    local bodyW = max(160, H.safeNum(np.body:GetWidth(), 400) or 400)
    local bodyH = max(80, H.safeNum(np.body:GetHeight(), 160) or 160)
    local rowH = H.clamp(floor(bodyH / vis), 24, 30)
    local sepCol = pal.glassSep or pal.separator or { 1, 1, 1, 0.14 }

    for i = 1, C.MAX_NEWS_ROWS do
        local row = np.rows[i]
        local story = (i <= vis) and filtered[ctx.state.newsOffset + i] or nil
        if story then
            row._story = story
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", np.body, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetSize(bodyW - 6, rowH)

            local cat = story.category or "sales"
            local sev = story.severity or "info"
            local tone = story.tone
            local dotCol = pal.accentBlue
            if tone == "good" then
                dotCol = pal.accentGreen
            elseif tone == "bad" then
                dotCol = pal.accentRed
            elseif tone == "warn" then
                dotCol = pal.accentOrange
            elseif tone == "info" then
                dotCol = pal.accentBlue
            elseif sev == "down" or sev == "positive" or cat == "deals" then
                dotCol = pal.accentGreen
            elseif sev == "up" or sev == "negative" or cat == "costs" then
                dotCol = pal.accentRed
            elseif sev == "alert" or cat == "movers" then
                dotCol = pal.accentOrange
            elseif cat == "sales" then
                dotCol = pal.accentGreen
            end

            row.dot:SetVertexColor(dotCol[1], dotCol[2], dotCol[3], 1)
            row.titleFs:SetText(tostring(story.title or story.headline or ""))
            H.setTextColor(row.titleFs, pal.text)

            local bTxt = story.badge or C.NEWS_BADGES[cat] or "INFO"
            row.badge.label:SetText(bTxt)
            row.badge.bg:SetColorTexture(dotCol[1], dotCol[2], dotCol[3], isLight and 0.14 or 0.22)
            H.setTextColor(row.badge.label, dotCol)
            row.sep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.24 or 0.16)
            row.sep:SetShown(i < vis and (ctx.state.newsOffset + i) < #filtered)
            row:Show()
        else
            row._story = nil
            row:Hide()
        end
    end
end

function Render.renderSpotlight(ctx)
    local sp = ctx.spot
    local pal = H.getPalette()
    local isLight = (pal.mode == "light")
    local st = H.findStock(ctx.state.snap, ctx.state.selectedKey)
    ctx.state.selectedStock = st
    if st and not ctx.state.selectedKey then ctx.state.selectedKey = st.key end

    if sp.plotWell then sp.plotWell:Hide() end
    if sp.midGrid then sp.midGrid:Hide() end
    for i = 1, C.MAX_SPOT_SEGS + 1 do
        sp.fillPool[i]:Hide()
        sp.bodyPool[i]:Hide()
        sp.dotPool[i]:Hide()
        sp.wickPool[i]:Hide()
        if i <= C.MAX_SPOT_SEGS then sp.linePool[i]:Hide() end
    end
    for i = 1, C.MAX_SPOT_BASE do sp.baseDots[i]:Hide() end

    local chartStyle = (ctx.state.chartStyle == "line") and "line" or "candles"
    if sp.styleChip then
        sp.styleChip.label:SetText(chartStyle == "candles" and "Candles" or "Line")
        sp.styleChip._active = (chartStyle == "candles")
        sp.styleChip:Paint(pal)
    end

    if not st then
        sp.icon:SetTexture(H.asset("icon_coins", "icon_coins"))
        sp.titleFs:SetText("Market Spotlight")
        sp.priceFs:SetText("--")
        sp.deltaFs:SetText("")
        sp.deltaSubFs:SetText("")
        sp.stat1L:SetText("Vol: --")
        sp.stat1R:SetText("Activity: 0")
        sp.stat2L:SetText("Avg: --")
        sp.stat2R:SetText("Profit: --")
        sp.hiFs:SetText("")
        sp.loFs:SetText("")
        if sp.legendFs then sp.legendFs:SetText("") end
        if sp.xStartFs then sp.xStartFs:SetText("") end
        if sp.xEndFs then sp.xEndFs:SetText("") end
        sp.emptyFs:Show()
        sp.pinBtn._active = false
        sp.pinBtn.label:SetText("Pin")
        sp.pinBtn:Paint(pal)
        H.setTextColor(sp.priceFs, pal.textMuted)
        local mCol = pal.textMuted
        sp.starBtn.icon:SetVertexColor(mCol[1], mCol[2], mCol[3], 0.7)
        return
    end

    sp.emptyFs:Hide()
    sp.icon:SetTexture(H.resolveIcon(st))
    sp.titleFs:SetText(tostring(st.name or st.shortName or "Item"))

    local starCol = st.isWatched and (pal.gold or { 1, 0.82, 0.2, 1 }) or pal.textMuted
    sp.starBtn.icon:SetVertexColor(starCol[1], starCol[2], starCol[3], st.isWatched and 1 or 0.55)

    local isPinned = (ctx.state.pinnedKey == st.key)
    sp.pinBtn._active = isPinned
    sp.pinBtn.label:SetText(isPinned and "Pinned" or "Pin")
    sp.pinBtn:Paint(pal)

    local price = H.safeNum(st.primaryPrice, H.safeNum(st.ahPrice, 0)) or 0
    local dCop = H.safeNum(st.deltaCopper, 0) or 0
    local dPct = H.safeNum(st.deltaPct, 0) or 0
    sp.priceFs:SetText(H.formatCopper(price, false))
    H.setTextColor(sp.priceFs, pal.text)

    local dCol = H.deltaColor(dPct ~= 0 and dPct or dCop, pal, "textSecondary")
    sp.deltaFs:SetText(H.formatPct(dPct))
    H.setTextColor(sp.deltaFs, dCol)
    sp.deltaSubFs:SetText(H.formatCopper(dCop, true))
    H.setTextColor(sp.deltaSubFs, dCol)

    local vol = floor(H.safeNum(st.vol, H.safeNum(st.listedQty, 0)) or 0)
    sp.stat1L:SetText(format("Vol: %d", vol))
    if (st.craftCount or 0) > 0 then
        sp.stat1R:SetText(format("Crafts: %d", floor(st.craftCount)))
    elseif (st.buyCount or 0) > 0 then
        sp.stat1R:SetText(format("Buys: %d", floor(st.buyCount)))
    else
        sp.stat1R:SetText(format("Sales: %d", floor(st.sellCount or 0)))
    end

    if st.craftCost and st.craftCost > 0 then
        sp.stat2L:SetText("Craft: " .. H.formatCopper(st.craftCost, false))
    elseif st.ledgerAvgBuyPrice and st.ledgerAvgBuyPrice > 0 then
        sp.stat2L:SetText("Avg Buy: " .. H.formatCopper(st.ledgerAvgBuyPrice, false))
    elseif st.baseline and st.baseline > 0 then
        sp.stat2L:SetText("Avg: " .. H.formatCopper(st.baseline, false))
    else
        sp.stat2L:SetText("Avg: --")
    end

    if st.netProfit ~= nil then
        sp.stat2R:SetText("Profit: " .. H.formatCopper(st.netProfit, true))
        H.setTextColor(sp.stat2R, H.deltaColor(st.netProfit, pal, "textSecondary"))
    elseif st.deValue and st.deValue > 0 then
        sp.stat2R:SetText("DE: " .. H.formatCopper(st.deValue, false))
        H.setTextColor(sp.stat2R, pal.accentPurple or pal.textSecondary)
    else
        sp.stat2R:SetText("Hi: " .. H.formatCopper(st.hi or price, false))
        H.setTextColor(sp.stat2R, pal.textSecondary)
    end

    local greenHex = isLight and "167a36" or "32d964"
    local redHex = isLight and "c02620" or "ff524d"
    local mutHex = isLight and "525866" or "b8c4d4"
    if sp.legendFs then
        if chartStyle == "candles" then
            sp.legendFs:SetText(format("|cff%s+Up|r  |cff%s-Dn|r   |cff%s-- Avg|r", greenHex, redHex, mutHex))
        else
            sp.legendFs:SetText(format("|cff%sAbove|r / |cff%sBelow|r   |cff%s-- Avg|r", greenHex, redHex, mutHex))
        end
    end

    -- Spotlight Candlestick / Two-Tone Line Plot inside crisp Dark Studio Plot Well
    local pts = H.samplePoints(st.points or {}, C.MAX_SPOT_SEGS + 1)
    local n = #pts
    local cw = max(80, H.safeNum(sp.canvas:GetWidth(), 220) or 220)
    local ch = max(56, H.safeNum(sp.canvas:GetHeight(), 100) or 100)
    local padL, padR, padB, padT = 4, 54, 14, 22
    local plotW = max(40, cw - padL - padR)
    local plotH = max(28, ch - padB - padT)

    if sp.plotWell then
        sp.plotWell:ShowBox(padL, padB, plotW, plotH, pal)
    end
    local sepCol = pal.textMuted or { 0.6, 0.62, 0.66, 0.6 }
    if sp.midGrid then
        sp.midGrid:ClearAllPoints()
        sp.midGrid:SetPoint("BOTTOMLEFT", sp.canvas, "BOTTOMLEFT", padL, padB + floor(plotH * 0.5))
        sp.midGrid:SetWidth(plotW)
        sp.midGrid:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.16 or 0.14)
        sp.midGrid:Show()
    end

    if n < 2 then
        sp.hiFs:SetText(price > 0 and H.formatCopper(price, false) or "")
        sp.loFs:SetText("")
        if sp.xStartFs then sp.xStartFs:SetText((n == 1 and pts[1].label) and tostring(pts[1].label) or "") end
        if sp.xEndFs then sp.xEndFs:SetText("") end
        if price > 0 then
            local cy = padB + floor(plotH * 0.5)
            local lc = pal.accentOrange or pal.accentBlue
            H.setSegmentLine(sp.linePool[1], sp.canvas, padL + 2, cy, padL + plotW - 2, cy, 2, lc, 0.85)
        end
        return
    end

    local lo, hi = nil, nil
    for i = 1, n do
        local p = pts[i]
        local v = H.safeNum(p.value, 0) or 0
        local pLo = H.safeNum(p.low, v) or v
        local pHi = H.safeNum(p.high, v) or v
        lo = (lo == nil) and min(v, pLo) or min(lo, v, pLo)
        hi = (hi == nil) and max(v, pHi) or max(hi, v, pHi)
    end
    local baseV = H.safeNum(st.baseline, (lo + hi) * 0.5) or lo
    lo = min(lo, baseV)
    hi = max(hi, baseV)
    if hi == lo then
        lo = max(0, lo - 10)
        hi = hi + 10
    end
    local span = max(1, hi - lo)
    sp.hiFs:SetText(H.formatCopper(hi, false))
    sp.loFs:SetText(H.formatCopper(lo, false))
    if sp.xStartFs then
        sp.xStartFs:SetText(tostring(pts[1].label or ""))
        H.setTextColor(sp.xStartFs, isLight and pal.textMuted or pal.textSecondary)
    end
    if sp.xEndFs then
        sp.xEndFs:SetText(tostring(pts[n].label or ""))
        H.setTextColor(sp.xEndFs, isLight and pal.textMuted or pal.textSecondary)
    end

    local function mapY(v)
        return padB + 2 + floor(((v - lo) / span) * max(16, plotH - 4) + 0.5)
    end

    -- Dotted baseline
    local by = mapY(baseV)
    local dStep = plotW / C.MAX_SPOT_BASE
    for d = 1, C.MAX_SPOT_BASE do
        local dot = sp.baseDots[d]
        dot:ClearAllPoints()
        dot:SetPoint("BOTTOMLEFT", sp.canvas, "BOTTOMLEFT", padL + floor((d - 1) * dStep), by)
        dot:SetSize(max(2, floor(dStep * 0.5)), 1)
        dot:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], 0.55)
        dot:Show()
    end

    local gCol = pal.accentGreen or { 0.19, 0.82, 0.35, 1 }
    local rCol = pal.accentRed or { 1.00, 0.32, 0.30, 1 }
    local oCol = pal.accentOrange or { 1.00, 0.60, 0.18, 1 }
    local slotW = plotW / n
    local bodyW = H.clamp(floor(slotW * 0.56), 4, 14)

    if chartStyle == "candles" then
        for i = 1, n do
            local p = pts[i]
            local v = H.safeNum(p.value, 0) or 0
            local oV = H.safeNum(p.open, v) or v
            local cV = H.safeNum(p.close, v) or v
            local loV = min(oV, cV, H.safeNum(p.low, v) or v)
            local hiV = max(oV, cV, H.safeNum(p.high, v) or v)
            local cx = padL + floor((i - 0.5) * slotW + 0.5)
            local yOpen = mapY(oV)
            local yClose = mapY(cV)
            local yLo = H.clamp(mapY(loV), padB + 1, padB + plotH - 3)
            local yHi = H.clamp(mapY(hiV), padB + 3, padB + plotH - 1)
            if yHi < yLo + 2 then yHi = min(padB + plotH - 1, yLo + 2) end
            local cCol = (cV > oV) and gCol or ((cV < oV) and rCol or oCol)

            H.setSegmentLine(sp.wickPool[i], sp.canvas, cx, yLo, cx, yHi, 1.5, cCol, 0.94)

            local bBot = H.clamp(min(yOpen, yClose), padB + 1, padB + plotH - 3)
            local bH = max(3, min(padB + plotH - bBot, abs(yClose - yOpen)))
            local body = sp.bodyPool[i]
            body:ClearAllPoints()
            body:SetPoint("BOTTOMLEFT", sp.canvas, "BOTTOMLEFT", H.clamp(cx - floor(bodyW * 0.5), padL + 1, padL + plotW - bodyW - 1), bBot)
            body:SetSize(bodyW, bH)
            body:SetColorTexture(cCol[1], cCol[2], cCol[3], 0.94)
            body:Show()
        end
    else
        local prevX, prevY, prevV = nil, nil, nil
        for i = 1, n do
            local v = H.safeNum(pts[i].value, 0) or 0
            local cx = padL + floor(((i - 1) / (n - 1)) * plotW + 0.5)
            local cy = mapY(v)
            if prevX then
                local segCol = (((prevV + v) * 0.5) >= baseV) and gCol or rCol
                H.setSegmentLine(sp.linePool[i - 1], sp.canvas, prevX, prevY, cx, cy, 2.0, segCol, 0.96)
            end
            if n <= 12 then
                local dtCol = (v >= baseV) and gCol or rCol
                local dt = sp.dotPool[i]
                dt:ClearAllPoints()
                dt:SetPoint("CENTER", sp.canvas, "BOTTOMLEFT", cx, cy)
                dt:SetVertexColor(dtCol[1], dtCol[2], dtCol[3], 1)
                dt:Show()
            end
            prevX, prevY, prevV = cx, cy, v
        end
    end
end

function Render.renderActive(ctx)
    local ap = ctx.active
    local pal = H.getPalette()
    local isLight = (pal.mode == "light")
    local list = (ctx.state.snap and ctx.state.snap.mostActive) or {}
    if #list == 0 then
        for i = 1, C.MAX_ACT_ROWS do ap.rows[i]:Hide() end
        ap.emptyFs:Show()
        return
    end
    ap.emptyFs:Hide()

    local bw = max(120, H.safeNum(ap.body:GetWidth(), 240) or 240)
    local bh = max(90, H.safeNum(ap.body:GetHeight(), 140) or 140)
    local rowCount = min(C.MAX_ACT_ROWS, #list)
    local rowH = H.clamp(floor(bh / C.MAX_ACT_ROWS), 22, 42)
    local sepCol = pal.glassSep or pal.separator or { 1, 1, 1, 0.14 }
    local accCol = pal.accentOrange or { 1, 0.6, 0.18, 1 }

    for i = 1, C.MAX_ACT_ROWS do
        local row = ap.rows[i]
        local st = list[i]
        if st then
            row._stock = st
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ap.body, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetSize(bw, rowH)

            local actCount = floor(H.safeNum(st.activityScore, 0) or 0)
            local label = tostring(st.name or st.shortName or "Item")
            if actCount > 0 then label = format("%s x%d", label, actCount) end
            row.nameFs:SetText(label)
            H.setTextColor(row.nameFs, pal.text)

            local price = H.safeNum(st.primaryPrice, H.safeNum(st.ahPrice, 0)) or 0
            row.priceFs:SetText(H.formatCopper(price, false))
            H.setTextColor(row.priceFs, pal.text)

            local dPct = H.safeNum(st.deltaPct, 0) or 0
            row.deltaFs:SetText(H.formatPct(dPct))
            H.setTextColor(row.deltaFs, H.deltaColor(dPct, pal, "textSecondary"))

            local isSel = (ctx.state.selectedKey == st.key)
            row.selBar:SetColorTexture(accCol[1], accCol[2], accCol[3], 0.95)
            row.selBar:SetShown(isSel)
            row.sep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.24 or 0.16)
            row.sep:SetShown(i < rowCount)
            row:Show()
        else
            row._stock = nil
            row:Hide()
        end
    end
end

function Render.renderTiming(ctx)
    local tp = ctx.timing
    local tm = (ctx.state.snap and ctx.state.snap.timing) or {}
    local st = ctx.state.selectedStock
    local bestSell = (st and st.bestSellText and st.bestSellText ~= "--" and st.bestSellText)
        or (tm.bestSellText and tm.bestSellText ~= "--" and tm.bestSellText)
        or "Open AH to scan"
    local bestBuy = (st and st.bestBuyText and st.bestBuyText ~= "--" and st.bestBuyText)
        or (tm.bestBuyText and tm.bestBuyText ~= "--" and tm.bestBuyText)
        or "Open AH to scan"

    tp.line1:SetText(format("Sell: %s | Buy: %s", tostring(bestSell), tostring(bestBuy)))
    local wCnt = floor(H.safeNum(tm.watchlistCount, 0) or 0)
    local cCnt = floor(H.safeNum(tm.trackedCraftsCount, 0) or 0)
    tp.line2:SetText(format("%s | %d watched | %d crafts",
        tostring(tm.econKey or "Normal-Horde"), wCnt, cCnt))
end

function Render.paintRailFilters(ctx)
    local pal = H.getPalette()
    for _, btn in ipairs(ctx.rail.filterBtns) do
        btn._active = (btn._filterKey == ctx.state.filterKey)
        btn:Paint(pal)
    end
end

function Render.renderRail(ctx)
    local rp = ctx.rail
    local pal = H.getPalette()
    local isLight = (pal.mode == "light")
    local list = (ctx.state.snap and ctx.state.snap.stocks) or {}

    local vis = H.clamp(ctx.state.visibleRailTiles or 6, 1, C.MAX_RAIL_TILES)
    local maxOff = max(0, #list - vis)
    ctx.state.railOffset = H.clamp(ctx.state.railOffset or 0, 0, maxOff)
    rp.sb:Update(#list, vis, ctx.state.railOffset)

    if #list == 0 then
        for i = 1, C.MAX_RAIL_TILES do rp.tiles[i]:Hide() end
        rp.emptyFs:Show()
        return
    end
    rp.emptyFs:Hide()

    local bw = max(140, H.safeNum(rp.body:GetWidth(), 200) or 200)
    local bh = max(120, H.safeNum(rp.body:GetHeight(), 480) or 480)
    local tileH = H.clamp(floor(bh / vis), 62, 82)
    local sepCol = pal.glassSep or pal.separator or { 1, 1, 1, 0.14 }
    local accCol = pal.accentOrange or { 1, 0.6, 0.18, 1 }
    local gCol = pal.accentGreen or { 0.19, 0.82, 0.35, 1 }
    local rCol = pal.accentRed or { 1.0, 0.32, 0.30, 1 }
    local mCol = pal.textMuted or { 0.6, 0.62, 0.66, 0.6 }

    for i = 1, C.MAX_RAIL_TILES do
        local tile = rp.tiles[i]
        local st = (i <= vis) and list[ctx.state.railOffset + i] or nil
        if st then
            tile._stock = st
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", rp.body, "TOPLEFT", 0, -((i - 1) * tileH))
            tile:SetSize(bw - 5, tileH)

            local isSel = (ctx.state.selectedKey == st.key)
            tile.selBar:SetColorTexture(accCol[1], accCol[2], accCol[3], 0.96)
            tile.selBar:SetShown(isSel)
            if isSel then
                tile.selBg:SetColorTexture(accCol[1], accCol[2], accCol[3], isLight and 0.08 or 0.11)
                tile.selBg:Show()
            else
                tile.selBg:Hide()
            end

            local short = tostring(st.shortName or st.name or "ITEM"):upper()
            tile.nameFs:SetText(short)
            H.setTextColor(tile.nameFs, isSel and accCol or pal.textSecondary)

            local price = H.safeNum(st.primaryPrice, H.safeNum(st.ahPrice, 0)) or 0
            local dCop = H.safeNum(st.deltaCopper, 0) or 0
            local dPct = H.safeNum(st.deltaPct, 0) or 0
            local dCol = H.deltaColor(dPct ~= 0 and dPct or dCop, pal, "textSecondary")

            tile.priceFs:SetText(H.formatCopper(price, false))
            H.setTextColor(tile.priceFs, pal.text)
            tile.chgFs:SetText(H.formatCopper(dCop, true))
            H.setTextColor(tile.chgFs, dCol)
            tile.pctFs:SetText(H.formatPct(dPct))
            H.setTextColor(tile.pctFs, dCol)

            tile.sep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.25 or 0.16)
            tile.sep:SetShown(i < vis and (ctx.state.railOffset + i) < #list)

            -- Mini sparkline: green above baseline, red below baseline
            for s = 1, C.MAX_RAIL_SEGS do tile.linePool[s]:Hide() end
            for d = 1, C.MAX_RAIL_BASE do tile.baseDots[d]:Hide() end
            local sw = max(60, bw - 22)
            local sh = max(14, tileH - 42)
            tile.spark:SetHeight(sh)

            local pts = H.samplePoints(st.points or {}, C.MAX_RAIL_SEGS + 1)
            local pn = #pts
            if pn >= 2 then
                local lo, hi = nil, nil
                for k = 1, pn do
                    local v = H.safeNum(pts[k].value, 0) or 0
                    lo = (lo == nil) and v or min(lo, v)
                    hi = (hi == nil) and v or max(hi, v)
                end
                local baseV = H.safeNum(st.baseline, (lo + hi) * 0.5) or lo
                lo, hi = min(lo, baseV), max(hi, baseV)
                local span = max(1, hi - lo)
                local by = 2 + floor(((baseV - lo) / span) * (sh - 4) + 0.5)
                local dStep = sw / C.MAX_RAIL_BASE
                for d = 1, C.MAX_RAIL_BASE do
                    local dot = tile.baseDots[d]
                    dot:ClearAllPoints()
                    dot:SetPoint("BOTTOMLEFT", tile.spark, "BOTTOMLEFT", floor((d - 1) * dStep), by)
                    dot:SetSize(max(2, floor(dStep * 0.48)), 1)
                    dot:SetColorTexture(mCol[1], mCol[2], mCol[3], 0.45)
                    dot:Show()
                end
                local prevX, prevY, prevV = nil, nil, nil
                for k = 1, pn do
                    local v = H.safeNum(pts[k].value, 0) or 0
                    local cx = floor(((k - 1) / (pn - 1)) * sw + 0.5)
                    local cy = 2 + floor(((v - lo) / span) * (sh - 4) + 0.5)
                    if prevX then
                        local segCol = (((prevV + v) * 0.5) >= baseV) and gCol or rCol
                        H.setSegmentLine(tile.linePool[k - 1], tile.spark, prevX, prevY, cx, cy, 1.6, segCol, 0.94)
                    end
                    prevX, prevY, prevV = cx, cy, v
                end
            else
                local midY = floor(sh * 0.5)
                H.setSegmentLine(tile.linePool[1], tile.spark, 0, midY, sw, midY, 1.4, dCol, 0.65)
            end
            tile:Show()
        else
            tile._stock = nil
            tile:Hide()
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Layout & Theme Repaint
---------------------------------------------------------------------------------------------------
function Render.layoutBanner(ctx, W, bannerH)
    ctx.banner:ClearAllPoints()
    ctx.banner:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", 0, 0)
    ctx.banner:SetSize(W, bannerH)

    local modeW = max(280, ceil(H.safeNum(ctx.modeSeg.frame:GetWidth(), 286) or 286))
    local rangeW = max(136, ceil(H.safeNum(ctx.rangeSeg.frame:GetWidth(), 148) or 148))
    local rightLimit = W - 2 - modeW - 8 - rangeW - 10
    local badgeW = 76
    local leftStart = 2 + badgeW + 8
    local availLeft = max(120, rightLimit - leftStart)

    local metaW = H.clamp(ceil(H.safeNum(ctx.metaPill.frame:GetWidth(), 130) or 130), 76, 185)
    local greetNat = max(90, ceil(H.safeNum(ctx.greetingFs:GetStringWidth(), 170) or 170) + 6)
    local maxGreetW = max(84, availLeft - metaW - 8)
    local greetW = min(greetNat, maxGreetW)
    ctx.greetingFs:SetWidth(greetW)
    if leftStart + greetW + 8 + metaW > rightLimit then
        metaW = max(60, rightLimit - (leftStart + greetW + 8))
        ctx.metaPill.frame:SetWidth(metaW)
    end

    return {
        banner     = { x = 0, y = 0, w = W, h = bannerH },
        bloomBadge = { x = 2, y = 6, w = badgeW, h = 20 },
        greeting   = { x = leftStart, y = 6, w = greetW, h = 20 },
        metaPill   = { x = leftStart + greetW + 8, y = 6, w = metaW, h = 20 },
        rangeSeg   = { x = W - 2 - modeW - 8 - rangeW, y = 3, w = rangeW, h = 26 },
        modeSeg    = { x = W - 2 - modeW, y = 3, w = modeW, h = 26 },
    }
end

function Render.layoutView(ctx, w, h)
    local st = ctx.state
    local W = max(960, floor(H.safeNum(w, H.safeNum(ctx.view:GetWidth(), st.width)) or 1080))
    local Hgt = max(540, floor(H.safeNum(h, H.safeNum(ctx.view:GetHeight(), st.height)) or 642))
    st.width, st.height = W, Hgt
    ctx.view:SetSize(W, Hgt)

    local bannerH = 32
    local bodyTop = 38
    local gap = (Hgt >= 900) and 12 or ((Hgt >= 750) and 10 or 8)
    local bodyH = max(360, Hgt - bodyTop)

    local bannerRects = Render.layoutBanner(ctx, W, bannerH)

    local availW = W - 2 * gap
    local col1W = floor(availW * 0.535)
    local col2W = floor(availW * 0.270)
    local col3W = availW - col1W - col2W
    local col1X = 0
    local col2X = col1W + gap
    local col3X = col1W + col2W + 2 * gap

    -- Column 1: Stage + News
    local stageH = floor((bodyH - gap) * 0.58)
    local newsH = bodyH - gap - stageH

    ctx.stage.panel:ClearAllPoints()
    ctx.stage.panel:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", col1X, -bodyTop)
    ctx.stage.panel:SetSize(col1W, stageH)

    local canvasH = max(84, stageH - 74)
    ctx.stage.canvas:ClearAllPoints()
    ctx.stage.canvas:SetPoint("TOPLEFT", ctx.stage.panel, "TOPLEFT", 8, -36)
    ctx.stage.canvas:SetSize(max(120, col1W - 16), canvasH)

    local stripW = max(120, col1W - 2)
    local cellW = floor(stripW / 3)
    for idx = 1, 3 do
        local cw = (idx == 3) and (stripW - 2 * cellW) or cellW
        local cell = ctx.stage.kpiCells[idx]
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", ctx.stage.tickerStrip, "TOPLEFT", (idx - 1) * cellW, 0)
        cell:SetSize(cw, 36)
        if idx < 3 then
            local dv = ctx.stage.kpiDivs[idx]
            dv:ClearAllPoints()
            dv:SetPoint("TOPLEFT", ctx.stage.tickerStrip, "TOPLEFT", idx * cellW, -5)
            dv:SetPoint("BOTTOMLEFT", ctx.stage.tickerStrip, "BOTTOMLEFT", idx * cellW, 5)
        end
    end

    local newsY = bodyTop + stageH + gap
    ctx.news.panel:ClearAllPoints()
    ctx.news.panel:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", col1X, -newsY)
    ctx.news.panel:SetSize(col1W, newsH)
    ctx.news.body:SetSize(max(120, col1W - 12), max(60, newsH - 43))
    st.visibleNewsRows = H.clamp(floor(max(60, newsH - 43) / 26), 4, C.MAX_NEWS_ROWS)

    -- Column 2: Spotlight + Most Active + Timing
    local col2Avail = bodyH - 2 * gap
    local spotH = floor(col2Avail * 0.48)
    local actH = floor(col2Avail * 0.35)
    local timH = col2Avail - spotH - actH
    if timH < 68 then
        local deficit = 68 - timH
        actH = max(120, actH - deficit)
        timH = col2Avail - spotH - actH
    end

    ctx.spot.panel:ClearAllPoints()
    ctx.spot.panel:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", col2X, -bodyTop)
    ctx.spot.panel:SetSize(col2W, spotH)
    ctx.spot.canvas:SetSize(max(80, col2W - 16), max(48, spotH - 122))

    local actY = bodyTop + spotH + gap
    ctx.active.panel:ClearAllPoints()
    ctx.active.panel:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", col2X, -actY)
    ctx.active.panel:SetSize(col2W, actH)
    ctx.active.body:SetSize(max(100, col2W - 8), max(80, actH - 34))

    local timY = actY + actH + gap
    ctx.timing.panel:ClearAllPoints()
    ctx.timing.panel:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", col2X, -timY)
    ctx.timing.panel:SetSize(col2W, timH)

    -- Column 3: Locked-In Stocks Ticker Rail
    ctx.rail.panel:ClearAllPoints()
    ctx.rail.panel:SetPoint("TOPLEFT", ctx.view, "TOPLEFT", col3X, -bodyTop)
    ctx.rail.panel:SetSize(col3W, bodyH)

    local fbW = max(120, col3W - 12)
    local btnGap = 3
    local eachW = floor((fbW - 3 * btnGap) / 4)
    for idx, b in ipairs(ctx.rail.filterBtns) do
        local bw = (idx == 4) and (fbW - 3 * (eachW + btnGap)) or eachW
        b:ClearAllPoints()
        b:SetPoint("LEFT", ctx.rail.filterBar, "LEFT", (idx - 1) * (eachW + btnGap), 0)
        b:SetSize(bw, 22)
    end

    local railBodyH = max(120, bodyH - 41)
    ctx.rail.body:SetSize(max(120, col3W - 8), railBodyH)
    st.visibleRailTiles = H.clamp(floor(railBodyH / 68), 4, C.MAX_RAIL_TILES)

    ctx.view._geometry = {
        W = W, H = Hgt, gap = gap,
        bannerH = bannerH, bodyTop = bodyTop, bodyH = bodyH,
        col1W = col1W, col2W = col2W, col3W = col3W,
        stageH = stageH, newsH = newsH,
        spotH = spotH, actH = actH, timH = timH,
        banner = bannerRects.banner,
        bloomBadge = bannerRects.bloomBadge,
        greeting = bannerRects.greeting,
        metaPill = bannerRects.metaPill,
        rangeSeg = bannerRects.rangeSeg,
        modeSeg = bannerRects.modeSeg,
        stagePanel = { x = col1X, y = bodyTop, w = col1W, h = stageH },
        stageCanvas = { x = col1X + 8, y = bodyTop + 36, w = max(120, col1W - 16), h = canvasH },
        tickerStrip = { x = col1X + 1, y = bodyTop + stageH - 37, w = stripW, h = 36 },
        newsPanel = { x = col1X, y = newsY, w = col1W, h = newsH },
        spotlightPanel = { x = col2X, y = bodyTop, w = col2W, h = spotH },
        activePanel = { x = col2X, y = actY, w = col2W, h = actH },
        timingPanel = { x = col2X, y = timY, w = col2W, h = timH },
        railPanel = { x = col3X, y = bodyTop, w = col3W, h = bodyH },
    }

    if st.snap then
        Render.renderStage(ctx)
        Render.renderNews(ctx)
        Render.renderSpotlight(ctx)
        Render.renderActive(ctx)
        Render.renderRail(ctx)
    end
end

function Render.applyThemeView(ctx)
    local pal = H.getPalette()
    local isLight = (pal.mode == "light")
    local amber = pal.accentOrange or { 1.0, 0.60, 0.18, 1 }
    local sepCol = pal.glassSep or pal.separator or { 1, 1, 1, 0.14 }

    -- Row 0 Banner
    local bbBg = isLight and { 0.80, 0.36, 0.02, 0.95 } or { 0.95, 0.56, 0.08, 0.95 }
    local bbInk = isLight and { 1, 1, 1, 1 } or { 0.05, 0.05, 0.07, 1 }
    ctx.bloomBadge.bg:SetColorTexture(bbBg[1], bbBg[2], bbBg[3], bbBg[4])
    H.applyFont(ctx.bloomBadge.label, 10, "semibold")
    H.setTextColor(ctx.bloomBadge.label, bbInk)

    H.applyFont(ctx.greetingFs, 14, "semibold")
    H.setTextColor(ctx.greetingFs, pal.text)
    if ctx.modeSeg and ctx.modeSeg.UpdateTheme then ctx.modeSeg:UpdateTheme() end
    if ctx.rangeSeg and ctx.rangeSeg.UpdateTheme then ctx.rangeSeg:UpdateTheme() end

    -- Panels
    ctx.stage.panel:PaintCard(pal)
    ctx.news.panel:PaintCard(pal)
    ctx.spot.panel:PaintCard(pal)
    ctx.active.panel:PaintCard(pal)
    ctx.timing.panel:PaintCard(pal)
    ctx.rail.panel:PaintCard(pal)

    -- Stage chrome
    local s = ctx.stage
    s.slideBadge.bg:SetColorTexture(amber[1], amber[2], amber[3], isLight and 0.16 or 0.22)
    H.applyFont(s.slideBadge.label, 9, "semibold")
    H.setTextColor(s.slideBadge.label, amber)
    H.applyFont(s.titleFs, 12, "semibold")
    H.setTextColor(s.titleFs, pal.text)
    H.applyFont(s.counterFs, 10, "semibold")
    H.setTextColor(s.counterFs, pal.textSecondary)
    H.setTextColor(s.legendFs, pal.textMuted)
    H.setTextColor(s.volMaxFs, pal.textMuted)
    H.setTextColor(s.emptyFs, pal.textMuted)
    if s.styleBtn then s.styleBtn:Paint(pal) end
    s.prevBtn:Paint(pal)
    s.nextBtn:Paint(pal)
    s.autoBtn:Paint(pal)
    s.unpinBtn:Paint(pal)
    s.hdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.30 or 0.22)

    local tsBg = pal.cardAltBg or (isLight and { 0.94, 0.94, 0.96, 1 } or { 0.09, 0.10, 0.12, 0.96 })
    s.tickerStrip.bg:SetColorTexture(tsBg[1], tsBg[2], tsBg[3], 0.92)
    s.tickerStrip.topSep:SetColorTexture(amber[1], amber[2], amber[3], isLight and 0.45 or 0.55)
    for idx = 1, 3 do
        H.applyFont(s.kpiCells[idx].kLabel, 9, "semibold")
        H.setTextColor(s.kpiCells[idx].kLabel, pal.textMuted)
        H.applyFont(s.kpiCells[idx].kVal, 11, "semibold")
        if idx < 3 then
            s.kpiDivs[idx]:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.30 or 0.22)
        end
    end

    -- Headlines chrome
    H.applyFont(ctx.news.titleFs, 12, "semibold")
    H.setTextColor(ctx.news.titleFs, amber)
    ctx.news.hdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.30 or 0.22)
    ctx.news.sb:Paint(pal)
    H.setTextColor(ctx.news.emptyFs, pal.textMuted)
    Render.paintNewsFilters(ctx)

    -- Spotlight chrome
    H.applyFont(ctx.spot.titleFs, 12, "semibold")
    H.setTextColor(ctx.spot.titleFs, pal.text)
    H.applyFont(ctx.spot.priceFs, 19, "semibold")
    H.setTextColor(ctx.spot.priceFs, pal.text)
    H.setTextColor(ctx.spot.stat1L, pal.textSecondary)
    H.setTextColor(ctx.spot.stat1R, pal.textSecondary)
    H.setTextColor(ctx.spot.stat2L, pal.textSecondary)
    H.setTextColor(ctx.spot.hiFs, pal.textMuted)
    H.setTextColor(ctx.spot.loFs, pal.textMuted)
    H.setTextColor(ctx.spot.emptyFs, pal.textMuted)
    ctx.spot.hdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.30 or 0.22)
    ctx.spot.statSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.24 or 0.16)
    if ctx.spot.styleChip then ctx.spot.styleChip:Paint(pal) end
    ctx.spot.pinBtn:Paint(pal)
    ctx.spot.deepBtn:Paint(pal)

    -- Most Active chrome
    H.applyFont(ctx.active.titleFs, 11, "semibold")
    H.setTextColor(ctx.active.titleFs, amber)
    H.setTextColor(ctx.active.subFs, pal.textMuted)
    H.setTextColor(ctx.active.emptyFs, pal.textMuted)
    ctx.active.hdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.30 or 0.22)

    -- Timing footer chrome
    ctx.timing.badge.bg:SetColorTexture(amber[1], amber[2], amber[3], isLight and 0.16 or 0.22)
    H.applyFont(ctx.timing.badge.label, 9, "semibold")
    H.setTextColor(ctx.timing.badge.label, amber)
    ctx.timing.watchBtn:Paint(pal)
    H.applyFont(ctx.timing.line1, 10, "semibold")
    H.setTextColor(ctx.timing.line1, pal.text)
    H.applyFont(ctx.timing.line2, 10, "regular")
    H.setTextColor(ctx.timing.line2, pal.textMuted)

    -- Right Rail chrome
    ctx.rail.hdrSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], isLight and 0.30 or 0.22)
    ctx.rail.sb:Paint(pal)
    H.setTextColor(ctx.rail.emptyFs, pal.textMuted)
    Render.paintRailFilters(ctx)

    if ctx.state.snap then
        Render.renderStage(ctx)
        Render.renderTickerStrip(ctx)
        Render.renderNews(ctx)
        Render.renderSpotlight(ctx)
        Render.renderActive(ctx)
        Render.renderTiming(ctx)
        Render.renderRail(ctx)
    end
end

---------------------------------------------------------------------------------------------------
-- Main View Factory: ns.DashboardBloomberg.Create(parent, opts)
---------------------------------------------------------------------------------------------------
function UI.Create(parent, opts)
    opts = opts or {}
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    local db = (type(_G.MerchantMasterDB) == "table") and _G.MerchantMasterDB or {}
    local savedRange = db.dashboardBriefRange
    if not C.RANGE_DAYS[savedRange] then savedRange = "7d" end
    local savedChartStyle = (db.dashboardChartStyle == "line") and "line" or "candles"

    local state = {
        mode = "bloomberg",
        rangeKey = savedRange,
        chartStyle = savedChartStyle,
        filterKey = "all",
        newsFilter = "all",
        selectedKey = nil,
        selectedStock = nil,
        pinnedKey = nil,
        slideIndex = 1,
        activeSlide = nil,
        autoRotate = true,
        stageHovered = false,
        newsOffset = 0,
        railOffset = 0,
        visibleNewsRows = 6,
        visibleRailTiles = 6,
        filteredNews = {},
        width = max(960, H.safeNum(parent and parent.GetWidth and parent:GetWidth(), 1080) or 1080),
        height = max(540, H.safeNum(parent and parent.GetHeight and parent:GetHeight(), 642) or 642),
        snap = nil,
        lastNowOverride = nil,
    }
    view._state = state

    local ctx = {
        view = view,
        opts = opts,
        state = state,
        autoTimer = nil,
        inTimerSchedule = false,
    }

    function ctx.openDeep(targetSpec)
        if not targetSpec then return end
        local fn = opts.onOpenDeepAnalysis or (ns.app and ns.app.openDeepAnalysis)
        if type(fn) == "function" then
            fn(targetSpec, { tab = "dashboard", mode = "bloomberg" })
        end
    end

    function ctx.addToCart(itemID, qty, name)
        local id = H.safeNum(itemID, 0) or 0
        if id <= 0 then return false end
        local q = max(1, floor(H.safeNum(qty, 1) or 1))
        if type(opts.onAddToCart) == "function" then
            return opts.onAddToCart(id, q, name) ~= false
        end
        local cur = ns.app
        if cur and type(cur.addUnifiedShoppingItem) == "function" then
            cur.addUnifiedShoppingItem({
                key = "item:" .. tostring(id),
                name = name or ("Item #" .. tostring(id)),
                itemID = id,
                qty = q,
                demandList = { { itemID = id, qty = q, role = "GoblinTV Desk" } },
                sourceLabel = "GoblinTV Desk",
            })
            return true
        end
        return false
    end

    -- Auto-rotation timer management (ZERO OnUpdate, NEVER calls app.refresh!)
    local function cancelAutoTimer()
        if ctx.autoTimer and type(ctx.autoTimer.Cancel) == "function" then
            ctx.autoTimer:Cancel()
        end
        ctx.autoTimer = nil
    end

    local function armAutoTimer()
        cancelAutoTimer()
        if not state.autoRotate then return end
        if view.IsVisible and not view:IsVisible() then return end
        if not _G.C_Timer then return end
        if type(_G.C_Timer.NewTimer) == "function" then
            ctx.autoTimer = _G.C_Timer.NewTimer(C.AUTO_ROTATE_SEC, function()
                ctx.autoTimer = nil
                if view.IsVisible and not view:IsVisible() then return end
                view:OnAutoTick()
                if state.autoRotate and (not view.IsVisible or view:IsVisible()) then
                    armAutoTimer()
                end
            end)
        elseif type(_G.C_Timer.After) == "function" and not ctx.inTimerSchedule then
            -- Guard against synchronous C_Timer.After mocks in headless unit harnesses
            ctx.inTimerSchedule = true
            local ranSync = false
            _G.C_Timer.After(C.AUTO_ROTATE_SEC, function()
                ranSync = true
                if ctx.inTimerSchedule then return end
                if view.IsVisible and not view:IsVisible() then return end
                view:OnAutoTick()
                if state.autoRotate and (not view.IsVisible or view:IsVisible()) then
                    armAutoTimer()
                end
            end)
            ctx.inTimerSchedule = false
            if ranSync then return end
        end
    end

    -- Build all UI panels once
    Builders.buildBanner(ctx)
    Builders.buildStagePanel(ctx)
    Builders.buildNewsPanel(ctx)
    Builders.buildSpotlightPanel(ctx)
    Builders.buildActivePanel(ctx)
    Builders.buildTimingPanel(ctx)
    Builders.buildRailPanel(ctx)

    -- Public View API
    function view:Layout(w, h)
        Render.layoutView(ctx, w, h)
    end

    local function getWatchlistSig()
        local WL = ns.Watchlist
        if not (WL and type(WL.GetEntries) == "function") then return "0" end
        local ok, entries = pcall(WL.GetEntries)
        if not (ok and type(entries) == "table") then return "0" end
        local acc = 0
        for i = 1, #entries do
            local e = entries[i]
            if type(e) == "table" then
                acc = acc + ((H.safeNum(e.itemID, 0) or 0) * 3 + (H.safeNum(e.spellID, 0) or 0) * 7) * i
            end
        end
        return tostring(#entries) .. ":" .. tostring(acc)
    end

    function view:ApplyTheme()
        state.lastRenderSig = nil
        Render.applyThemeView(ctx)
    end

    function view:Refresh(force, nowOverride)
        state.lastNowOverride = nowOverride
        local Model = ns.DashboardBloombergModel
        if force then
            state.lastRenderSig = nil
            if Model and type(Model.InvalidateCache) == "function" then Model.InvalidateCache() end
            if ns.DashboardBrief and type(ns.DashboardBrief.InvalidateCache) == "function" then
                ns.DashboardBrief.InvalidateCache()
            end
        end

        local econKey = H.resolveEconKey(opts.getEconKey and opts.getEconKey())
        local freshness = (type(opts.getFreshnessText) == "function" and opts.getFreshnessText())
            or ((ns.Pricing and ns.Pricing.GetSnapshotFreshnessLabel and ns.Pricing.GetSnapshotFreshnessLabel(econKey)) or "Live")
        local priceRev = (type(ns.GetPriceDataRevision) == "function" and ns.GetPriceDataRevision()) or ns.priceCacheEpoch or 0
        local Store = ns.Analytics and ns.Analytics.Store
        local storeVer = (Store and Store.version) or 0
        local ahVer = (Store and Store.ahSalesVersion) or 0
        local accVer = (Store and Store.accountingVersion) or 0
        local gold = (_G.GetMoney and H.safeNum(_G.GetMoney(), 0)) or 0
        local dbRef = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB or nil
        local themeKey = ((ns.Theme and type(ns.Theme.GetKey) == "function") and tostring(ns.Theme.GetKey()))
            or (dbRef and (tostring(dbRef.theme or "") .. ":" .. tostring(dbRef.uiSkin or "")))
            or ""
        local nowSecVal = (Store and type(Store.Now) == "function" and H.safeNum(Store.Now(), nil)) or (_G.time and _G.time()) or 0
        local renderSig = table.concat({
            tostring(econKey),
            tostring(freshness),
            tostring(priceRev),
            tostring(storeVer),
            tostring(ahVer),
            tostring(accVer),
            tostring(gold),
            getWatchlistSig(),
            tostring(state.rangeKey),
            tostring(state.filterKey),
            tostring(state.selectedKey),
            tostring(state.pinnedKey),
            tostring(state.chartStyle),
            tostring(state.mode),
            tostring(state.width),
            tostring(state.height),
            tostring(floor(nowSecVal / 86400)),
            themeKey,
        }, "|")
        if not force and nowOverride == nil and state.snap ~= nil and state.lastRenderSig == renderSig then
            if state.autoRotate and (not self.IsVisible or self:IsVisible()) then
                armAutoTimer()
            end
            return
        end

        ctx.greetingFs:SetText(H.getGreeting(opts.getPlayerName and opts.getPlayerName()))
        ctx.metaPill:SetVariant("neutral", econKey .. " | " .. tostring(freshness))
        Render.layoutBanner(ctx, state.width, 32)

        local snap
        if Model and type(Model.BuildSnapshot) == "function" then
            local ok, res = pcall(Model.BuildSnapshot, econKey, state.rangeKey, state.filterKey,
                state.selectedKey, nowOverride, {
                    priceBank = (type(opts.getPriceBank) == "function") and opts.getPriceBank() or nil,
                    pinnedKey = state.pinnedKey,
                    freshnessText = freshness,
                })
            if ok and type(res) == "table" then snap = res end
        end
        state.snap = snap or H.emptySnapshot(econKey, state.rangeKey, state.filterKey, freshness)
        state.lastPriceRev = priceRev
        state.lastRenderSig = (nowOverride == nil) and renderSig or nil

        local sel = H.findStock(state.snap, state.selectedKey)
        state.selectedStock = sel
        state.selectedKey = sel and sel.key or nil

        Render.renderStage(ctx)
        Render.renderTickerStrip(ctx)
        Render.renderNews(ctx)
        Render.renderSpotlight(ctx)
        Render.renderActive(ctx)
        Render.renderTiming(ctx)
        Render.renderRail(ctx)

        if state.autoRotate and (not self.IsVisible or self:IsVisible()) then
            armAutoTimer()
        end
    end

    function view:GetState()
        return state
    end

    function view:SetMode(mode, silent)
        local m = (mode == "classic" or mode == "brief") and mode or "bloomberg"
        state.mode = m
        if ctx.modeSeg and ctx.modeSeg.SetActive then
            ctx.modeSeg:SetActive(m, silent ~= false)
        end
    end

    function view:SetRange(rangeKey, silent)
        if not C.RANGE_DAYS[rangeKey] then return end
        state.rangeKey = rangeKey
        state.lastRenderSig = nil
        if type(_G.MerchantMasterDB) == "table" then
            _G.MerchantMasterDB.dashboardBriefRange = rangeKey
        end
        if ctx.rangeSeg and ctx.rangeSeg.SetActive then
            ctx.rangeSeg:SetActive(rangeKey, silent == true)
        elseif not silent then
            self:Refresh(true)
        end
    end

    function view:SelectStock(key, pinToStage)
        if not key then return end
        state.selectedKey = key
        if pinToStage == true then
            state.pinnedKey = key
            state.slideIndex = 1
            self:Refresh(false)
            return
        end
        if state.snap then
            state.selectedStock = H.findStock(state.snap, key)
            Render.renderSpotlight(ctx)
            Render.renderActive(ctx)
            Render.renderTiming(ctx)
            Render.renderRail(ctx)
        else
            self:Refresh(false)
        end
    end

    function view:NextSlide(manual)
        local slides = (state.snap and state.snap.slides) or {}
        local count = max(1, #slides)
        state.slideIndex = (state.slideIndex % count) + 1
        Render.renderStage(ctx)
        if manual and state.autoRotate then armAutoTimer() end
        return state.slideIndex
    end

    function view:PrevSlide(manual)
        local slides = (state.snap and state.snap.slides) or {}
        local count = max(1, #slides)
        state.slideIndex = ((state.slideIndex - 2) % count) + 1
        Render.renderStage(ctx)
        if manual and state.autoRotate then armAutoTimer() end
        return state.slideIndex
    end

    function view:ToggleAutoRotate()
        state.autoRotate = not state.autoRotate
        if state.autoRotate then
            armAutoTimer()
        else
            cancelAutoTimer()
        end
        Render.renderStage(ctx)
        return state.autoRotate
    end

    function view:SetChartStyle(style)
        local st = (style == "line") and "line" or "candles"
        state.chartStyle = st
        state.lastRenderSig = nil
        if type(_G.MerchantMasterDB) == "table" then
            _G.MerchantMasterDB.dashboardChartStyle = st
        end
        if state.snap then
            Render.renderStage(ctx)
            Render.renderSpotlight(ctx)
        end
        return st
    end

    function view:ToggleChartStyle()
        return self:SetChartStyle((state.chartStyle == "line") and "candles" or "line")
    end

    function view:OnAutoTick()
        if not state.autoRotate or state.stageHovered then return false end
        if self.IsVisible and not self:IsVisible() then return false end
        if not (state.snap and type(state.snap.slides) == "table" and #state.snap.slides > 1) then
            return false
        end
        self:NextSlide(false)
        return true
    end

    function view:Invalidate()
        state.lastRenderSig = nil
        if ns.DashboardBloombergModel and type(ns.DashboardBloombergModel.InvalidateCache) == "function" then
            ns.DashboardBloombergModel.InvalidateCache()
        end
        if ns.DashboardBrief and type(ns.DashboardBrief.InvalidateCache) == "function" then
            ns.DashboardBrief.InvalidateCache()
        end
    end

    view:HookScript("OnShow", function()
        local curRev = (type(ns.GetPriceDataRevision) == "function" and ns.GetPriceDataRevision()) or ns.priceCacheEpoch or 0
        if state.lastPriceRev ~= nil and state.lastPriceRev ~= curRev then
            view:Invalidate()
            view:Refresh(false, state.lastNowOverride)
        end
        if state.autoRotate then armAutoTimer() end
    end)
    view:HookScript("OnHide", function()
        cancelAutoTimer()
    end)

    local T = ns.Theme
    if T and type(T.RegisterWidget) == "function" then
        T.RegisterWidget(view, function() view:ApplyTheme() end)
    end

    if ns.Watchlist and type(ns.Watchlist.RegisterListener) == "function" then
        ns.Watchlist.RegisterListener(function()
            view:Invalidate()
            if view:IsShown() then view:Refresh(false) end
        end)
    end

    view:Layout(state.width, state.height)
    view:ApplyTheme()
    return view
end
