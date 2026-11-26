-- Real window dimensions; scale remains an independent saved preference.
local _, ns = ...
local Window = {}
ns.Window = Window
local MIN_W, MIN_H, MAX_W, MAX_H = 1320, 730, 3840, 2160

local function number(value, fallback)
    if issecretvalue and issecretvalue(value) then return fallback end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end
local function clamp(value, lo, hi, fallback)
    return math.max(lo, math.min(hi, number(value, fallback)))
end
local function screen()
    return number(UIParent and UIParent.GetWidth and UIParent:GetWidth(), 1920),
        number(UIParent and UIParent.GetHeight and UIParent:GetHeight(), 1080)
end

function Window.Attach(panel, grip, heightGrip, opts)
    opts = opts or {}
    local c = { panel = panel, compact = false, applying = false }
    local minWidth = MIN_W
    local defaultW = clamp(opts.defaultW, minWidth, math.max(MAX_W, minWidth), minWidth)
    local defaultH = clamp(opts.defaultH, MIN_H, MAX_H, MIN_H)
    c.pulse = CreateFrame('Frame', nil, panel)
    local function db()
        if opts.getWindowDB then return opts.getWindowDB() end
        if type(MerchantMasterDB) ~= 'table' then return {} end
        if type(MerchantMasterDB.window) ~= 'table' then MerchantMasterDB.window = {} end
        return MerchantMasterDB.window
    end
    function c:Flush()
        local pending = self.pending
        self.pending, self.waiting = false, false
        self.pulse:SetScript('OnUpdate', nil)
        if pending and not self.compact and panel:IsShown() and opts.onLayout then opts.onLayout() end
    end
    function c:Schedule()
        if self.applying or self.compact then return end
        self.pending = true
        if self.waiting then return end
        self.waiting = true
        local elapsed = 0
        self.pulse:SetScript('OnUpdate', function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.05 then self.waiting = false; self:Flush() end
        end)
    end
    function c:SetCompact(compact)
        self.compact = compact
        if compact then self.pending = false; self.waiting = false; self.pulse:SetScript('OnUpdate', nil) end
    end
    function c:ApplyFull()
        local saved = db()
        local defW = math.max(minWidth, defaultW)
        local w = math.floor(clamp(saved.width, minWidth, math.max(MAX_W, minWidth), defW) + 0.5)
        local h = math.floor(clamp(saved.height, MIN_H, MAX_H, defaultH) + 0.5)
        saved.width, saved.height = w, h
        local sw, sh = screen()
        local preferred = clamp(saved.scale, 0.65, 1.35, 1)
        local scale = math.max(0.1, math.min(preferred, (sw - 24) / w, (sh - 24) / h))
        self.applying = true
        local oldScale = panel:GetScale()
        local left, top = panel:GetLeft(), panel:GetTop()
        panel:SetScale(scale)
        if oldScale ~= scale and left and top then
            panel:ClearAllPoints()
            panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left * oldScale / scale, top * oldScale / scale)
        end
        panel:SetSize(w, h)
        self.applying = false
    end
    function c:GetMinimumWidth() return minWidth end
    function c:SetMinimumWidth(width)
        width = math.ceil(math.max(MIN_W, number(width, MIN_W)))
        if width == minWidth then return end
        minWidth = width
        if not self.compact then self:ApplyFull(); self:Schedule() end
    end
    function c:IsZoomed()
        return self._zoomed == true
    end
    function c:ToggleZoom()
        if self.compact then return false end
        local sw, sh = screen()
        local scale = number(panel:GetScale(), 1)
        if scale <= 0 then scale = 1 end
        if self._zoomed then
            local pre = self._preZoom or {}
            local defW = math.max(minWidth, defaultW)
            local w = math.floor(clamp(pre.width, minWidth, math.max(MAX_W, minWidth), defW) + 0.5)
            local h = math.floor(clamp(pre.height, MIN_H, MAX_H, defaultH) + 0.5)
            self._zoomed = false
            self._preZoom = nil
            db().width, db().height = w, h
            self.applying = true
            panel:ClearAllPoints()
            if pre.left and pre.top then
                panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', pre.left, pre.top)
            else
                panel:SetPoint('CENTER')
            end
            panel:SetSize(w, h)
            self.applying = false
            self.pending = true
            self:Flush()
            return false
        end
        local defW = math.max(minWidth, defaultW)
        self._preZoom = {
            width = number(panel:GetWidth(), defW),
            height = number(panel:GetHeight(), defaultH),
            left = number(panel:GetLeft(), nil),
            top = number(panel:GetTop(), nil),
        }
        local zw = math.floor(clamp((sw - 24) / scale, minWidth, math.max(MAX_W, minWidth), minWidth) + 0.5)
        local zh = math.floor(clamp((sh - 24) / scale, MIN_H, MAX_H, MIN_H) + 0.5)
        self._zoomed = true
        db().width, db().height = zw, zh
        self.applying = true
        panel:ClearAllPoints()
        panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', 12 / scale, (sh - 12) / scale)
        panel:SetSize(zw, zh)
        self.applying = false
        self.pending = true
        self:Flush()
        return true
    end
    function c:SetSize(w, h)
        if self.compact then return end
        local sw, sh = screen()
        local scale = number(panel:GetScale(), 1)
        local left = math.max(0, number(panel:GetLeft(), 0))
        local top = number(panel:GetTop(), sh / scale)
        local maxW = math.max(minWidth, math.min(math.max(MAX_W, minWidth), (sw - 24) / scale, (sw - 12) / scale - left))
        local maxH = math.max(MIN_H, math.min(MAX_H, (sh - 24) / scale, top - 12 / scale))
        w = math.floor(clamp(w, minWidth, maxW, minWidth) + 0.5)
        h = math.floor(clamp(h, MIN_H, maxH, MIN_H) + 0.5)
        db().width, db().height = w, h
        panel:SetSize(w, h)
        self:Schedule()
    end
    panel:HookScript('OnSizeChanged', function(_, w, h)
        if c.applying or c.compact then return end
        local defW = math.max(minWidth, defaultW)
        db().width = math.floor(clamp(w, minWidth, math.max(MAX_W, minWidth), defW) + 0.5)
        db().height = math.floor(clamp(h, MIN_H, MAX_H, defaultH) + 0.5)
        c:Schedule()
    end)
    local function bind(handle, heightOnly)
        if not handle then return end
        local function stop(self)
            self:SetScript('OnUpdate', nil)
            c.waiting = false
            c:Flush()
        end
        handle:SetScript('OnMouseDown', function(self, button)
            if c.compact then return end
            if button == 'RightButton' then
                c._zoomed = false; c._preZoom = nil
                local defW = math.max(minWidth, defaultW)
                c:SetSize(heightOnly and panel:GetWidth() or defW, defaultH); c:Flush(); return
            end
            if button ~= 'LeftButton' or not GetCursorPosition then return end
            c._zoomed = false; c._preZoom = nil
            local startX, startY = GetCursorPosition()
            local w, h = panel:GetWidth(), panel:GetHeight()
            local scale = number(panel:GetEffectiveScale(), 1)
            if scale <= 0 then return end
            local left, top = panel:GetLeft(), panel:GetTop()
            panel:ClearAllPoints()
            panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left, top)
            panel.userMoved = true
            self:SetScript('OnUpdate', function()
                local x, y = GetCursorPosition()
                c:SetSize(heightOnly and w or w + (x - startX) / scale, h + (startY - y) / scale)
            end)
        end)
        handle:SetScript('OnMouseUp', stop)
        handle:SetScript('OnHide', stop)
        handle:SetScript('OnEnter', function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:AddLine(heightOnly and 'Stretch Window Height' or 'Resize Window', 1, 1, 1)
            GameTooltip:AddLine('Drag to resize. Right-click to restore default dimensions.', 0.85, 0.85, 0.88, true)
            GameTooltip:Show()
        end)
        handle:SetScript('OnLeave', GameTooltip_Hide)
    end
    bind(grip, false); bind(heightGrip, true)
    panel:HookScript('OnHide', function()
        c.pending, c.waiting = false, false
        c.pulse:SetScript('OnUpdate', nil)
        if grip then grip:SetScript('OnUpdate', nil) end
        if heightGrip then heightGrip:SetScript('OnUpdate', nil) end
    end)
    return c
end

-- Update geometry only: never invoke a row initializer or an economics provider.
function Window.CopyColumns(columns)
    local result = {}
    for i, column in ipairs(columns) do
        result[i] = {}
        for key, value in pairs(column) do result[i][key] = value end
    end
    return result
end

function Window.LayoutTable(tbl, width, headerY, deferScrollRefresh)
    local columns = tbl.columns
    if not columns or not tbl.headerBar then return end
    if tbl.scrollBox and tbl.scrollBox.GetWidth then
        local sbW = tbl.scrollBox:GetWidth()
        if type(sbW) == 'number' and sbW > 0 then width = math.min(width, sbW) end
    end
    if not tbl.baseWidths then
        tbl.baseWidths = {}
        for i, col in ipairs(columns) do tbl.baseWidths[i] = col.width end
    end
    local nCols = #columns
    local sigParts = {}
    for i = 1, nCols do
        local col = columns[i]
        local bw = tbl.baseWidths[i] or (col and col.width) or 0
        local mw = (col and col.minWidth) or bw
        local gw = (tbl.growWeights and tbl.growWeights[i]) or (col and col.grow) or bw
        local key = (col and col.key) or i
        sigParts[i] = tostring(key) .. ':' .. tostring(bw) .. ':' .. tostring(mw) .. ':' .. tostring(gw)
    end
    local colSig = tostring(nCols) .. '|' .. table.concat(sigParts, ',')
    local firstCol = columns[1]
    local hy = headerY or 0
    local prop = tbl.proportional and true or false
    if not tbl._layoutDirty and tbl._lastLayoutW == width and tbl._lastLayoutHY == hy
        and tbl._lastColSig == colSig and tbl._lastFirstCol == firstCol and tbl._lastProp == prop and tbl.layoutRow then
        if tbl.scrollBox then
            if not deferScrollRefresh and tbl.scrollBox.FullUpdate then
                tbl.scrollBox:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately)
            end
            tbl.scrollBox:ForEachFrame(tbl.layoutRow)
        else
            for _, r in ipairs(tbl.pool or {}) do if r:IsShown() then tbl.layoutRow(r) end end
        end
        return
    end
    tbl._layoutDirty = nil
    tbl._lastLayoutW, tbl._lastLayoutHY, tbl._lastColSig, tbl._lastFirstCol, tbl._lastProp = width, hy, colSig, firstCol, prop
    local budget, weight = 4, 0
    for i = 1, nCols do
        local w = tbl.baseWidths[i] or (columns[i] and columns[i].width) or 0
        budget = budget + (tbl.proportional and (columns[i].minWidth or w) or w) + 5
        local g = (tbl.growWeights and tbl.growWeights[i]) or columns[i].grow or w
        weight = weight + g
    end
    local extra = math.max(0, width - budget)
    local x, used, cumulative = 4, 0, 0
    local hdrList = tbl.headerBtns or tbl.hdrBtns or {}
    for i, col in ipairs(columns) do
        if tbl.proportional then
            local g = (tbl.growWeights and tbl.growWeights[i]) or col.grow or tbl.baseWidths[i]
            cumulative = cumulative + g
            local share = weight > 0 and math.floor(extra * cumulative / weight) or 0
            col.width = (col.minWidth or tbl.baseWidths[i]) + share - used
            used = share
        else col.width = tbl.baseWidths[i] + (i == 1 and extra or 0) end
        tbl.colX[i] = x
        local header = hdrList[i]
        if header then
            header:ClearAllPoints(); header:SetPoint('LEFT', tbl.headerBar, 'LEFT', x + (tbl.professor and 4 or 0), headerY or 0)
            header:SetWidth(col.width)
        end
        x = x + col.width + 5
    end
    if tbl.paintTableChrome then tbl.paintTableChrome() end
    tbl._layoutEpoch=(tbl._layoutEpoch or 0)+1
    local function row(r)
        if tbl.cardMode then
            if r.SetWidth and width and width > 0 then r:SetWidth(width) end
            if tbl.layoutCardRow then tbl.layoutCardRow(r, width) end
            r._layoutEpoch = tbl._layoutEpoch
            return
        end
        if not r.cells or r._layoutEpoch==tbl._layoutEpoch then return end
        for i, cell in ipairs(r.cells) do
            if columns[i] then
                cell:ClearAllPoints(); cell:SetPoint('LEFT', r, 'LEFT', tbl.colX[i], 0)
                cell:SetWidth(columns[i].width)
            end
        end
        r._layoutEpoch=tbl._layoutEpoch
    end
    tbl.layoutRow = row
    if tbl.scrollBox then
        if not deferScrollRefresh and tbl.scrollBox.FullUpdate then
            tbl.scrollBox:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately)
        end
        tbl.scrollBox:ForEachFrame(row)
    else
        for _, r in ipairs(tbl.pool or {}) do if r:IsShown() then row(r) end end
    end
end

function Window.LayoutAnalytics(analytics, width, height)
    local ui = analytics and analytics.UI
    if not ui then return end
    for _, view in pairs(ui.views or {}) do
        if (view.IsVisible and view:IsVisible()) or (not view.IsVisible and view:IsShown()) then
            local cards = view.kpis or {}
            local cardWidth = #cards > 0 and (width - (#cards - 1) * 6) / #cards or 0
            for i, card in ipairs(cards) do
                card:SetWidth(cardWidth); card:ClearAllPoints(); card:SetPoint('TOPLEFT', (i - 1) * (cardWidth + 6), -4)
                card.title:SetWidth(cardWidth - 16); card.value:SetWidth(cardWidth - 16)
            end
            -- Chart's retained points are already evaluated; a redraw uses no ledger queries.
            for _, key in ipairs({ 'profit', 'wealth', 'trend' }) do
                local chart = view[key]
                if chart then
                    local half = view.profit ~= nil
                    local chartWidth = half and (width - 12) / 2 or width
                    local height = chart:GetHeight()
                    chart:SetWidth(chartWidth)
                    if half and key == 'wealth' then chart:ClearAllPoints(); chart:SetPoint('TOPLEFT', chartWidth + 12, -64) end
                    chart.plotWidth, chart.plotHeight = math.max(1, chartWidth - 94), math.max(1, height - 66)
                    chart.plot:SetSize(chart.plotWidth, chart.plotHeight)
                    chart.title:SetWidth(chartWidth * 0.66); chart.summary:SetWidth(chartWidth * 0.28)
                    for i = 1, 3 do
                        local fraction = (i - 1) / 2
                        chart.yLabels[i]:ClearAllPoints()
                        chart.yLabels[i]:SetPoint('RIGHT', chart.plot, 'BOTTOMLEFT', -8, chart.plotHeight * fraction)
                        chart.xLabels[i]:ClearAllPoints()
                        chart.xLabels[i]:SetPoint(i == 1 and 'LEFT' or (i == 3 and 'RIGHT' or 'CENTER'), chart.plot, 'BOTTOMLEFT', chart.plotWidth * fraction, -16)
                    end
                    if chart.Layout then
                        chart:Layout(chartWidth, height)
                    else
                        local data = key == 'profit' and chart._lastBars or chart._lastSeries
                        if data and chart.SetData then chart:SetData(data) end
                    end
                end
            end
            for _, tbl in pairs(ui.tables or {}) do
                local rp = tbl.resizeParent
                if rp and ((rp.IsVisible and rp:IsVisible()) or (not rp.IsVisible and rp:IsShown())) and Window.LayoutTable then
                    Window.LayoutTable(tbl, width, 1)
                end
            end
            for _, tbl in pairs(ui.auxTables or {}) do
                local rp = tbl.resizeParent
                if rp and ((rp.IsVisible and rp:IsVisible()) or (not rp.IsVisible and rp:IsShown())) and Window.LayoutTable then
                    Window.LayoutTable(tbl, width, 1)
                end
            end
        end
    end
    if type(ui.Layout) == 'function' then ui.Layout(width, height) end
end
