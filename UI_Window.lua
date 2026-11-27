-- Real window dimensions; scale remains an independent saved preference.
local _, ns = ...
local Window = {}
ns.Window = Window
local MIN_W, MIN_H, MAX_W, MAX_H = 1320, 730, 3840, 2160
local LARGE_SCREEN_W, LARGE_SCREEN_H = 2200, 1200
local LARGE_MAX_W, LARGE_MAX_H = 2240, 1300

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

function Window.IsLargeDisplay(sw, sh)
    if sw == nil or sh == nil then
        local curW, curH = screen()
        sw = sw or curW
        sh = sh or curH
    end
    sw = number(sw, 1920)
    sh = number(sh, 1080)
    return sw >= LARGE_SCREEN_W and sh >= LARGE_SCREEN_H
end

function Window.GetPreferredDefaultSize(baseW, baseH, sw, sh)
    local w = math.floor(clamp(baseW, MIN_W, MAX_W, MIN_W) + 0.5)
    local h = math.floor(clamp(baseH, MIN_H, MAX_H, MIN_H) + 0.5)
    if sw == nil or sh == nil then
        local curW, curH = screen()
        sw = sw or curW
        sh = sh or curH
    end
    sw = number(sw, 1920)
    sh = number(sh, 1080)
    if sw >= LARGE_SCREEN_W and sh >= LARGE_SCREEN_H then
        local capW = math.min(math.floor(sw - 40), LARGE_MAX_W)
        local capH = math.min(math.floor(sh - 40), LARGE_MAX_H)
        w = math.floor(clamp(math.max(w, capW), MIN_W, MAX_W, w) + 0.5)
        h = math.floor(clamp(math.max(h, capH), MIN_H, MAX_H, h) + 0.5)
    end
    return w, h
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
    function c:GetPreferredDefaultSize()
        return Window.GetPreferredDefaultSize(math.max(minWidth, defaultW), defaultH)
    end
    function c:ApplyFull()
        local saved = db()
        local defW, defH = math.max(minWidth, defaultW), defaultH
        if opts.adaptiveLargeDefault == true and saved.width == nil and saved.height == nil then
            defW, defH = self:GetPreferredDefaultSize()
            defW = math.max(minWidth, defW)
        end
        local w = math.floor(clamp(saved.width, minWidth, math.max(MAX_W, minWidth), defW) + 0.5)
        local h = math.floor(clamp(saved.height, MIN_H, MAX_H, defH) + 0.5)
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
    function c:ToggleZoom(comfortable)
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
        local useLargeCap = (comfortable == true or opts.comfortableZoom == true)
            and sw >= LARGE_SCREEN_W and sh >= LARGE_SCREEN_H
        local rawW = useLargeCap and math.min((sw - 40) / scale, LARGE_MAX_W) or ((sw - 24) / scale)
        local rawH = useLargeCap and math.min((sh - 40) / scale, LARGE_MAX_H) or ((sh - 24) / scale)
        local zw = math.floor(clamp(rawW, minWidth, math.max(MAX_W, minWidth), minWidth) + 0.5)
        local zh = math.floor(clamp(rawH, MIN_H, MAX_H, MIN_H) + 0.5)
        self._zoomed = true
        db().width, db().height = zw, zh
        self.applying = true
        panel:ClearAllPoints()
        if useLargeCap then
            panel:SetPoint('CENTER')
        else
            panel:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', 12 / scale, (sh - 12) / scale)
        end
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
            local wasResizing = (self._resizing == true)
            self._resizing = false
            self:SetScript('OnUpdate', nil)
            c.waiting = false
            c:Flush()
            if wasResizing and opts.positionKey and Window.SavePosition and Window.HasSavedPosition then
                if panel.userMoved or Window.HasSavedPosition(opts.positionKey) then
                    Window.SavePosition(panel, opts.positionKey)
                end
            end
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
            self._resizing = true
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

local fallbackPositions = {}
local fallbackModes = {}
Window.VALID_MODES = { snap = true, lock = true, free = true }

local function positionsDB()
    if type(MerchantMasterDB) == 'table' then
        if type(MerchantMasterDB.windowPositions) ~= 'table' then
            MerchantMasterDB.windowPositions = {}
        end
        return MerchantMasterDB.windowPositions
    end
    return fallbackPositions
end

local function modesDB()
    if type(MerchantMasterDB) == 'table' then
        if type(MerchantMasterDB.windowModes) ~= 'table' then
            MerchantMasterDB.windowModes = {}
        end
        return MerchantMasterDB.windowModes
    end
    return fallbackModes
end

function Window.GetMode(key, defaultMode)
    local def = (type(defaultMode) == 'string' and Window.VALID_MODES[defaultMode]) and defaultMode or 'snap'
    if type(key) ~= 'string' or key == '' then return def end
    local mode = modesDB()[key]
    if type(mode) == 'string' and Window.VALID_MODES[mode] then
        return mode
    end
    return def
end

function Window.SetMode(key, mode)
    local norm = (type(mode) == 'string' and Window.VALID_MODES[mode]) and mode or 'snap'
    if type(key) == 'string' and key ~= '' then
        modesDB()[key] = norm
    end
    return norm
end

function Window.CycleMode(key, defaultMode)
    local cur = Window.GetMode(key, defaultMode)
    local nextMode = (cur == 'snap' and 'lock') or (cur == 'lock' and 'free') or 'snap'
    return Window.SetMode(key, nextMode)
end

function Window.ClearMode(key)
    if key == nil then
        local mdb = modesDB()
        for k in pairs(mdb) do mdb[k] = nil end
        if type(MerchantMasterDB) == 'table' then
            MerchantMasterDB.windowModes = {}
        end
        fallbackModes = {}
        return true
    end
    if type(key) == 'string' and key ~= '' then
        modesDB()[key] = nil
        return true
    end
    return false
end

local function isFrameObject(f)
    local t = type(f)
    return t == 'table' or t == 'userdata'
end

local function isFrameShownSafe(f)
    if not isFrameObject(f) or type(f.IsShown) ~= 'function' then return false end
    local ok, v = pcall(f.IsShown, f)
    if not ok or (issecretvalue and issecretvalue(v)) then return false end
    return v == true
end

local function isCombatBlocked(frame)
    if not (frame and frame._mmCombatSafeDrag) then return false end
    if type(InCombatLockdown) == 'function' then
        local ok, inCombat = pcall(InCombatLockdown)
        if ok and not (issecretvalue and issecretvalue(inCombat)) and inCombat == true then
            return true
        end
    end
    return false
end

function Window.HasSavedPosition(key)
    if type(key) ~= 'string' or key == '' then return false end
    local rec = positionsDB()[key]
    if type(rec) ~= 'table' then return false end
    local x = number(rec.x, nil)
    local y = number(rec.y, nil)
    return x ~= nil and y ~= nil
end

function Window.ClearSavedPosition(key)
    if key == nil then
        local db = positionsDB()
        for k in pairs(db) do db[k] = nil end
        if type(MerchantMasterDB) == 'table' then
            MerchantMasterDB.windowPositions = {}
        end
        fallbackPositions = {}
        Window.ClearMode(nil)
        return true
    end
    if type(key) == 'string' and key ~= '' then
        positionsDB()[key] = nil
        return true
    end
    return false
end

function Window.ClampToScreen(frame)
    if not isFrameObject(frame) then return false end
    if isCombatBlocked(frame) then return false end
    local left = frame.GetLeft and number(frame:GetLeft(), nil) or nil
    local top = frame.GetTop and number(frame:GetTop(), nil) or nil
    if left == nil or top == nil then return false end
    local sw, sh = screen()
    local scale = frame.GetScale and number(frame:GetScale(), 1) or 1
    if scale <= 0 then scale = 1 end
    local fw = (frame.GetWidth and number(frame:GetWidth(), 0) or 0) * scale
    local fh = (frame.GetHeight and number(frame:GetHeight(), 0) or 0) * scale
    local uiX = left * scale
    local uiY = top * scale
    local clampedX = clamp(uiX, 0, math.max(0, sw - math.min(fw, sw)), uiX)
    local minTop = math.min(math.max(40, fh), sh)
    local clampedY = clamp(uiY, minTop, sh, uiY)
    if math.abs(clampedX - uiX) > 0.5 or math.abs(clampedY - uiY) > 0.5 then
        if frame.ClearAllPoints then frame:ClearAllPoints() end
        if frame.SetPoint then
            frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', clampedX / scale, clampedY / scale)
        end
    end
    return true
end

function Window.SavePosition(frame, key)
    if not isFrameObject(frame) or type(key) ~= 'string' or key == '' then return nil end
    local scale = frame.GetScale and number(frame:GetScale(), 1) or 1
    if scale <= 0 then scale = 1 end
    local left = frame.GetLeft and number(frame:GetLeft(), nil) or nil
    local top = frame.GetTop and number(frame:GetTop(), nil) or nil
    local db = positionsDB()
    if left ~= nil and top ~= nil then
        local sw, sh = screen()
        local fw = (frame.GetWidth and number(frame:GetWidth(), 0) or 0) * scale
        local fh = (frame.GetHeight and number(frame:GetHeight(), 0) or 0) * scale
        local uiX = clamp(left * scale, 0, math.max(0, sw - math.min(fw, sw)), left * scale)
        local minTop = math.min(math.max(40, fh), sh)
        local uiY = clamp(top * scale, minTop, sh, top * scale)
        local rec = {
            space = 'uiparent',
            point = 'TOPLEFT',
            relPoint = 'BOTTOMLEFT',
            x = math.floor(uiX * 10 + 0.5) / 10,
            y = math.floor(uiY * 10 + 0.5) / 10,
        }
        db[key] = rec
        frame._mmHasSavedPos = true
        return rec
    end
    if frame.GetPoint then
        local pt, rel, relPt, x, y = frame:GetPoint(1)
        local nx, ny = number(x, nil), number(y, nil)
        if type(pt) == 'string' and (rel == nil or rel == UIParent) and nx ~= nil and ny ~= nil then
            local rec = {
                space = 'point',
                point = pt,
                relPoint = (type(relPt) == 'string' and relPt) or pt,
                x = nx,
                y = ny,
            }
            db[key] = rec
            frame._mmHasSavedPos = true
            return rec
        end
    end
    return nil
end

function Window.RestorePosition(frame, key)
    if not isFrameObject(frame) or type(key) ~= 'string' or key == '' then return false end
    if isCombatBlocked(frame) then return false end
    local rec = positionsDB()[key]
    if type(rec) ~= 'table' then return false end
    local rx = number(rec.x, nil)
    local ry = number(rec.y, nil)
    if rx == nil or ry == nil then return false end
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    if rec.space == 'uiparent' or (rec.point == 'TOPLEFT' and rec.relPoint == 'BOTTOMLEFT') then
        local sw, sh = screen()
        local scale = frame.GetScale and number(frame:GetScale(), 1) or 1
        if scale <= 0 then scale = 1 end
        local fw = (frame.GetWidth and number(frame:GetWidth(), 0) or 0) * scale
        local fh = (frame.GetHeight and number(frame:GetHeight(), 0) or 0) * scale
        local uiX = clamp(rx, 0, math.max(0, sw - math.min(fw, sw)), 0)
        local minTop = math.min(math.max(40, fh), sh)
        local uiY = clamp(ry, minTop, sh, sh)
        if frame.ClearAllPoints then frame:ClearAllPoints() end
        if frame.SetPoint then
            frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', uiX / scale, uiY / scale)
        end
    else
        local pt = (type(rec.point) == 'string' and rec.point) or 'CENTER'
        local relPt = (type(rec.relPoint) == 'string' and rec.relPoint) or pt
        if frame.ClearAllPoints then frame:ClearAllPoints() end
        if frame.SetPoint then
            frame:SetPoint(pt, UIParent, relPt, rx, ry)
        end
    end
    frame._mmHasSavedPos = true
    return true
end

function Window.PlaceBeside(frame, anchorFrame, fallbackPoint, fallbackX, fallbackY, gap)
    if not isFrameObject(frame) then return false end
    if isCombatBlocked(frame) then return false end
    if frame.ClearAllPoints then frame:ClearAllPoints() end
    if isFrameShownSafe(anchorFrame) then
        local gapPx = number(gap, 12)
        local sw = screen()
        local scale = frame.GetScale and number(frame:GetScale(), 1) or 1
        if scale <= 0 then scale = 1 end
        local modalW = (frame.GetWidth and number(frame:GetWidth(), 400) or 400) * scale
        local uiEffScale = number(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1)
        if uiEffScale <= 0 then uiEffScale = 1 end
        local anchorEff = anchorFrame.GetEffectiveScale and number(anchorFrame:GetEffectiveScale(), uiEffScale) or uiEffScale
        local anchorScale = anchorEff / uiEffScale
        if anchorScale <= 0 then anchorScale = 1 end
        local rawRight = anchorFrame.GetRight and number(anchorFrame:GetRight(), nil) or nil
        local rawLeft = anchorFrame.GetLeft and number(anchorFrame:GetLeft(), nil) or nil
        local anchorRight = rawRight and (rawRight * anchorScale) or nil
        local anchorLeft = rawLeft and (rawLeft * anchorScale) or nil
        if anchorRight and (anchorRight + modalW + gapPx) > sw and (anchorLeft == nil or (anchorLeft - modalW - gapPx) >= 0) then
            frame:SetPoint('TOPRIGHT', anchorFrame, 'TOPLEFT', -gapPx / scale, 0)
        else
            frame:SetPoint('TOPLEFT', anchorFrame, 'TOPRIGHT', gapPx / scale, 0)
        end
        return true
    end
    local fp = (type(fallbackPoint) == 'string' and fallbackPoint) or 'CENTER'
    frame:SetPoint(fp, UIParent, fp, number(fallbackX, 0), number(fallbackY, 0))
    return false
end

function Window.ApplyPosition(frame, key, defaultFn)
    if Window.RestorePosition(frame, key) then
        return 'saved'
    end
    if type(defaultFn) == 'function' then
        defaultFn(frame)
    end
    return 'default'
end

function Window.DetachToUIParent(frame)
    if not isFrameObject(frame) then return nil, nil end
    if isCombatBlocked(frame) then return nil, nil end
    local left = frame.GetLeft and number(frame:GetLeft(), nil) or nil
    local top = frame.GetTop and number(frame:GetTop(), nil) or nil
    if left ~= nil and top ~= nil then
        if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
        if frame.SetUserPlaced then frame:SetUserPlaced(false) end
        if frame.ClearAllPoints then frame:ClearAllPoints() end
        if frame.SetPoint then
            frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left, top)
        end
        return left, top
    end
    return nil, nil
end

function Window.IsDragging(frame)
    return (isFrameObject(frame) and frame._mmDragging == true) and true or false
end

function Window.MakeDragHandle(handle, target, onStop, opts)
    if not isFrameObject(handle) or not isFrameObject(target) then return false end
    local effOpts = type(opts) == 'table' and opts or target._mmDragOpts
    if handle.EnableMouse then handle:EnableMouse(true) end
    if handle.RegisterForDrag then handle:RegisterForDrag('LeftButton') end

    local function stopDrag(callOnStop)
        local wasDragging = (target._mmDragging == true)
        target._mmDragging = false
        if target._mmDragDriver and target._mmDragDriver.SetScript then
            target._mmDragDriver:SetScript('OnUpdate', nil)
        end
        if target._mmDragUsedNative then
            target._mmDragUsedNative = false
            if target.StopMovingOrSizing then target:StopMovingOrSizing() end
        end
        if not wasDragging then return end
        if callOnStop ~= false then
            local stopFn = (type(onStop) == 'function' and onStop) or (effOpts and effOpts.onStop)
            if type(stopFn) == 'function' then stopFn(target) end
        end
    end

    local function startDrag()
        if isCombatBlocked(target) then return end
        local canFn = (effOpts and effOpts.canDrag) or target._mmCanDrag
        if type(canFn) == 'function' and canFn(target) == false then
            return
        end
        local left0 = target.GetLeft and number(target:GetLeft(), nil) or nil
        local top0 = target.GetTop and number(target:GetTop(), nil) or nil
        local onStartFn = (effOpts and effOpts.onDragStart) or target._mmOnDragStart
        if type(onStartFn) == 'function' then
            onStartFn(target)
        end

        local curFn = _G and _G.GetCursorPosition
        local cx0, cy0 = nil, nil
        if type(curFn) == 'function' then
            cx0, cy0 = curFn()
            cx0 = number(cx0, nil)
            cy0 = number(cy0, nil)
        end

        if cx0 ~= nil and cy0 ~= nil and left0 ~= nil and top0 ~= nil
            and type(target.ClearAllPoints) == 'function' and type(target.SetPoint) == 'function' then
            local effScale = target.GetEffectiveScale and number(target:GetEffectiveScale(), nil) or nil
            if not effScale or effScale <= 0 then
                effScale = target.GetScale and number(target:GetScale(), 1) or 1
            end
            if not effScale or effScale <= 0 then effScale = 1 end
            local scale = target.GetScale and number(target:GetScale(), 1) or 1
            if not scale or scale <= 0 then scale = 1 end

            if target.SetDontSavePosition then target:SetDontSavePosition(true) end
            if target.SetUserPlaced then target:SetUserPlaced(false) end
            -- Pin exact current screen corner BEFORE moving so delta tracking starts at (0, 0).
            target:ClearAllPoints()
            target:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left0, top0)

            local isClamped = (not target.IsClampedToScreen) or (target:IsClampedToScreen() ~= false)
            local sw, sh = screen()
            local fw = (target.GetWidth and number(target:GetWidth(), 0) or 0) * scale
            local minX = math.min(0, left0 * scale)
            local maxX = math.max(math.max(0, sw - math.min(fw, sw)), left0 * scale)
            local minY = math.min(math.min(40, sh), top0 * scale)
            local maxY = math.max(sh, top0 * scale)

            if not target._mmDragDriver and type(_G.CreateFrame) == 'function' then
                target._mmDragDriver = _G.CreateFrame('Frame', nil, target)
            end
            target._mmDragging = true
            target._mmDragUsedNative = false

            if target._mmDragDriver and target._mmDragDriver.SetScript then
                target._mmDragDriver:SetScript('OnUpdate', function()
                    if not target._mmDragging or isCombatBlocked(target) then
                        stopDrag(target._mmDragging)
                        return
                    end
                    if target.IsShown and not target:IsShown() then
                        stopDrag(false)
                        return
                    end
                    if _G and type(_G.IsMouseButtonDown) == 'function' and not _G.IsMouseButtonDown('LeftButton') then
                        stopDrag(true)
                        return
                    end
                    local cur = _G and _G.GetCursorPosition
                    if type(cur) ~= 'function' then return end
                    local cx, cy = cur()
                    cx, cy = number(cx, nil), number(cy, nil)
                    if cx == nil or cy == nil then return end
                    local rawL = left0 + (cx - cx0) / effScale
                    local rawT = top0 + (cy - cy0) / effScale
                    if isClamped then
                        local curW = (target.GetWidth and number(target:GetWidth(), 0) or 0) * scale
                        local curSw, curSh = screen()
                        local hiX = math.max(maxX, math.max(0, curSw - math.min(curW, curSw)))
                        local uiX = clamp(rawL * scale, minX, hiX, rawL * scale)
                        local uiY = clamp(rawT * scale, minY, math.max(maxY, curSh), rawT * scale)
                        rawL = uiX / scale
                        rawT = uiY / scale
                    end
                    target:ClearAllPoints()
                    target:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', rawL, rawT)
                end)
            end
            return
        end

        target._mmDragging = true
        target._mmDragUsedNative = true
        if target.StartMoving then target:StartMoving() end
    end

    if handle.SetScript then
        handle:SetScript('OnDragStart', startDrag)
        handle:SetScript('OnDragStop', function()
            stopDrag(true)
        end)
    end
    if not handle._mmDragHideHooked and type(handle.HookScript) == 'function' then
        handle._mmDragHideHooked = true
        handle:HookScript('OnHide', function()
            stopDrag(false)
        end)
    end
    if target ~= handle and not target._mmDragHideHooked and type(target.HookScript) == 'function' then
        target._mmDragHideHooked = true
        target:HookScript('OnHide', function()
            stopDrag(false)
        end)
    end
    return true
end
