-- Freshness tracks the selected economy's last successful full scan or fresher Local Snapshot.
local ADDON, ns = ...
local Refresh = {}
ns.AHRefresh = Refresh
local darkColors = { red = { 1, 0.259, 0.271 }, orange = { 1, 0.573, 0.188 }, green = { 0.188, 0.820, 0.345 } }
local lightColors = { red = { 0.839, 0.141, 0.161 }, orange = { 0.702, 0.290, 0.000 }, green = { 0.000, 0.478, 0.169 } }
local function safe(value)
    return not (issecretvalue and issecretvalue(value))
        and not (type(value) == 'table' and issecrettable and issecrettable(value))
end
local function isAHOpen()
    local ah = _G.AuctionHouseFrame
    if not safe(ah) or type(ah) ~= 'table' or not safe(ah.IsShown) or type(ah.IsShown) ~= 'function' then return false end
    local ok, shown = pcall(ah.IsShown, ah)
    return ok and safe(shown) and shown == true
end
local function rawScannedAt(economy)
    if not safe(economy) or type(economy) ~= 'table' then return nil end
    local stamp = economy._scannedAt
    if safe(stamp) and type(stamp) == 'number' then return stamp end
end
local function valid(value)
    return safe(value) and type(value) == 'number' and value == value and value > 0 and value < math.huge
end
-- A live browse scan or a deep order-book lot scan is running right now.
-- knownActive / knownText: browse-scan state the caller already read (skips the API round trip).
local function scanStatus(knownActive, knownText)
    local api = _G.MerchantMasterAPI
    local isApiScanning, text = false, nil
    if knownActive ~= nil then
        isApiScanning = knownActive == true
        if isApiScanning and type(knownText) == 'string' then text = knownText end
    elseif safe(api) and type(api) == 'table' then
        if type(api.IsScanning) == 'function' then
            local ok, active = pcall(api.IsScanning)
            isApiScanning = ok and safe(active) and active == true
        end
        if isApiScanning and type(api.GetScanStatus) == 'function' then
            local ok, status = pcall(api.GetScanStatus)
            if ok and safe(status) and type(status) == 'string' then text = status end
        end
    end
    local app = ns.app
    local lots = safe(app) and type(app) == 'table' and safe(app.lotScanTotal) and type(app.lotScanTotal) == 'number' and app.lotScanTotal or 0
    if not text and lots > 0 then
        local done = safe(app.lotScanDone) and type(app.lotScanDone) == 'number' and app.lotScanDone or 0
        text = string.format('Deep scanning order-book lots %d/%d', done, lots)
    end
    return (isApiScanning == true) or lots > 0, text, (isApiScanning ~= true) and lots > 0
end
local function activeColors()
    if ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode() == 'light' then
        return lightColors
    end
    return darkColors
end
local function hasSnapshotsActive()
    if safe(ns.HasSnapshots) and type(ns.HasSnapshots) == 'function' then
        local ok, has = pcall(ns.HasSnapshots)
        if ok and safe(has) and has == true then return true end
    end
    return false
end
local function hasSnapshotCapability()
    if hasSnapshotsActive() then return true end
    if safe(ns.HasSnapshotExtension) and type(ns.HasSnapshotExtension) == 'function' then
        local ok, has = pcall(ns.HasSnapshotExtension)
        if ok and safe(has) and has == true then return true end
    end
    if safe(ns.app) and type(ns.app) == 'table' and ns.app.snapshotExtension ~= nil then
        return true
    end
    return false
end
function Refresh.GetFreshness(stamp, now)
    if not valid(stamp) or not valid(now) or stamp > now then
        return { status = 'red', text = valid(stamp) and 'Invalid scan timestamp' or 'Never scanned' }
    end
    local age = now - stamp
    local status = age < 600 and 'green' or (age <= 1800 and 'orange' or 'red')
    return { status = status, age = age, at = stamp,
        text = (status == 'green' and 'Fresh' or (status == 'orange' and 'Aging' or 'Stale')) .. ' (' .. math.floor(age) .. 's ago)' }
end
function Refresh.GetSnapshotFreshness(meta, now, manualAt)
    local stamp = safe(meta) and type(meta) == 'table' and meta.updatedAt or nil
    if not valid(stamp) or not valid(now) or stamp > now then
        return { status = 'red', text = valid(stamp) and 'Invalid snapshot timestamp' or 'No snapshot', isSnapshot = true }
    end
    local age = now - stamp
    local status = age < 4500 and 'green' or (age <= 10800 and 'orange' or 'red')
    local rawSrc = safe(meta.source) and type(meta.source) == 'string' and meta.source or ''
    local tag = rawSrc:lower():find('blizzard', 1, true) and 'Blizz' or 'Snap'
    local mins = math.floor(age / 60)
    return {
        status = status,
        age = age,
        at = stamp,
        isSnapshot = true,
        source = rawSrc,
        manualAt = manualAt,
        text = string.format('%s %dm', tag, mins),
    }
end
function Refresh.Create(panel, anchor)
    local c = {}
    local button = ns.Theme.CreatePlateButton(panel, 'AH', 24, 24, { variant = 'ghost', pill = true })
    c.button = button
    button:SetSize(24, 24)
    if anchor then button:SetPoint('RIGHT', anchor, 'LEFT', -6, 0) end
    button.accessibilityLabel = 'Refresh AH'
    if panel.GetFrameLevel and button.SetFrameLevel then button:SetFrameLevel(panel:GetFrameLevel() + 25) end

    local addonRoot = 'Interface\\AddOns\\' .. tostring(ADDON or 'MerchantMaster')
    local iconPath = (ns.Theme and ns.Theme.ASSETS and ns.Theme.ASSETS.icon_refresh)
        or (addonRoot .. '\\Assets\\apple\\icon_refresh')
    local closeIconPath = (ns.Theme and ns.Theme.ASSETS and ns.Theme.ASSETS.icon_close)
        or (addonRoot .. '\\Assets\\apple\\icon_close')
    local pillPath = (ns.Theme and ns.Theme.ASSETS and ns.Theme.ASSETS.circle_fill)
        or (addonRoot .. '\\Assets\\apple\\circle_fill')

    local icon = button:CreateTexture(nil, 'OVERLAY')
    icon:SetSize(15, 15); icon:SetPoint('CENTER')
    if icon.SetTexture then icon:SetTexture(iconPath) end
    c.icon = icon
    button:SetText('')
    local function tooltip()
        if not GameTooltip then return end
        GameTooltip:SetOwner(button, 'ANCHOR_TOP')
        if c.ahNotOpen and not c.scanning then
            local red = activeColors().red
            GameTooltip:AddLine('AH not open', red[1], red[2], red[3])
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine('Refresh AH', 1, 1, 1)
        if c.scanning then
            GameTooltip:AddLine(c.scanText or 'Scanning the Auction House...', 0.35, 0.78, 0.98)
        else
            GameTooltip:AddLine(c.state.text, 0.90, 0.90, 0.94)
        end
        local stamp = c.state.at
        local showSnapInfo = hasSnapshotCapability()
        if showSnapInfo and c.state.isSnapshot then
            GameTooltip:AddLine('Last snapshot: ' .. (stamp and (date and date('%Y-%m-%d %H:%M:%S', stamp) or tostring(stamp)) or 'unavailable'), 0.75, 0.76, 0.80)
            if c.state.manualAt then
                GameTooltip:AddLine('Last full scan: ' .. (date and date('%Y-%m-%d %H:%M:%S', c.state.manualAt) or tostring(c.state.manualAt)), 0.75, 0.76, 0.80)
            end
        else
            GameTooltip:AddLine(stamp and ('Last full scan: ' .. (date and date('%Y-%m-%d %H:%M:%S', stamp) or tostring(stamp))) or 'Last full scan: unavailable', 0.75, 0.76, 0.80)
            if showSnapInfo and c.state.snapAt then
                GameTooltip:AddLine('Last snapshot: ' .. (date and date('%Y-%m-%d %H:%M:%S', c.state.snapAt) or tostring(c.state.snapAt)), 0.75, 0.76, 0.80)
            end
        end
        if c.scanning then
            GameTooltip:AddLine('Click to stop AH scan', 0.75, 0.76, 0.80, true)
        else
            GameTooltip:AddLine('Click to refresh. The Auction House must be open.', 0.75, 0.76, 0.80, true)
        end
        GameTooltip:Show()
    end
    local function hideOwnedTooltip()
        local tip = GameTooltip
        local tipType = type(tip)
        if not safe(tip) or (tipType ~= 'table' and tipType ~= 'userdata')
            or not safe(tip.GetOwner) or type(tip.GetOwner) ~= 'function' then return end
        local ok, owner = pcall(tip.GetOwner, tip)
        if ok and safe(owner) and owner == button and safe(tip.Hide) and type(tip.Hide) == 'function' then
            pcall(tip.Hide, tip)
        end
    end
    function c:Update(scanActive, scanText)
        local info = ns.CurrentEconomyInfo and ns.CurrentEconomyInfo()
        local key = safe(info) and type(info) == 'table' and info.effectiveKey
        local prices = safe(MerchantMasterDB) and type(MerchantMasterDB) == 'table' and MerchantMasterDB.ahPrices
        local economy = safe(key) and type(key) == 'string' and safe(prices) and type(prices) == 'table' and prices[key]
        local scanning, lotScanOnly
        scanning, scanText, lotScanOnly = scanStatus(scanActive, scanText)
        local stamp = rawScannedAt(economy)
        local now = time and time()
        local curStamp = valid(stamp) and valid(now) and stamp <= now and stamp or nil
        self._manualStamp = curStamp
        local wasAhNotOpen = self.ahNotOpen == true
        if scanning or isAHOpen() or curStamp ~= self._ahNotOpenStamp then self.ahNotOpen = false end
        local snapCapable = hasSnapshotCapability()
        local snapActive = hasSnapshotsActive()
        local snapMeta = nil
        if snapCapable and safe(key) and type(key) == 'string' and key ~= ''
            and safe(ns.Pricing) and type(ns.Pricing) == 'table'
            and safe(ns.Pricing.GetSnapshotMeta) and type(ns.Pricing.GetSnapshotMeta) == 'function' then
            local ok, meta = pcall(ns.Pricing.GetSnapshotMeta, key)
            if ok and safe(meta) and type(meta) == 'table' then
                local upd = meta.updatedAt
                if valid(upd) and valid(now) and upd <= now then
                    snapMeta = meta
                end
            end
        end
        if snapCapable and snapMeta and (not curStamp or snapMeta.updatedAt > curStamp) then
            self.state = Refresh.GetSnapshotFreshness(snapMeta, now, curStamp)
        else
            self.state = Refresh.GetFreshness(curStamp, now)
            if snapCapable and snapMeta and valid(snapMeta.updatedAt) then
                self.state.snapAt = snapMeta.updatedAt
            end
        end
        local showScanLabel = (curStamp == nil) and (not snapActive) and (not scanning) and (not self.ahNotOpen)
        if showScanLabel then
            if button.SetText then button:SetText('Scan AH') end
            if button.SetSize then button:SetSize(78, 24) end
            if icon.ClearAllPoints then icon:ClearAllPoints() end
            if icon.SetPoint then icon:SetPoint('LEFT', button, 'LEFT', 7, 0) end
            if button.fs and button.fs.ClearAllPoints and button.fs.SetPoint then
                button.fs:ClearAllPoints()
                button.fs:SetPoint('LEFT', icon, 'RIGHT', 4, 0)
            end
            button.accessibilityLabel = 'Scan AH'
        else
            if button.SetText then button:SetText('') end
            if button.SetSize then button:SetSize(24, 24) end
            if icon.ClearAllPoints then icon:ClearAllPoints() end
            if icon.SetPoint then icon:SetPoint('CENTER') end
            if button.fs and button.fs.ClearAllPoints and button.fs.SetPoint then
                button.fs:ClearAllPoints()
                button.fs:SetPoint('CENTER', 0, 0)
            end
            button.accessibilityLabel = 'Refresh AH'
        end
        local isLight = ns.Theme and ns.Theme.GetMode and ns.Theme.GetMode() == 'light'
        local pal = (ns.Theme and ns.Theme.GetActivePalette and ns.Theme.GetActivePalette()) or (ns.Theme and ns.Theme.PALETTES and ns.Theme.PALETTES[isLight and 'light' or 'dark'])
        local neutral = (pal and (pal.textGlass or pal.text)) or (isLight and { 0.102, 0.102, 0.102 } or { 0.929, 0.929, 0.929 })
        local statusColor = activeColors()[self.state.status]
        self.scanning, self.scanText, self.lotScanOnly = scanning, scanText, lotScanOnly
        local scanBlue = (pal and pal.accentBlue) or (isLight and { 0, 0.533, 1 } or { 0, 0.569, 1 })
        local iconColor = (self.ahNotOpen and not scanning) and activeColors().red
            or (scanning and scanBlue or ((self.state.status == 'red' and not self.hovered) and statusColor or neutral))
        if self.ahNotOpen and not scanning then
            if icon.SetTexture then icon:SetTexture(closeIconPath) end
            if icon.SetSize then icon:SetSize(14, 14) end
        else
            if icon.SetTexture then icon:SetTexture(iconPath) end
            if icon.SetSize then icon:SetSize(15, 15) end
        end
        if icon.SetVertexColor then icon:SetVertexColor(iconColor[1], iconColor[2], iconColor[3], 1) end
        if not scanning and (self._spinAngle or 0) ~= 0 then
            self._spinAngle = 0
            if icon.SetRotation then icon:SetRotation(0) end
        end
        if button._mmFreshnessFill == nil then
            button._mmFreshnessFill = button:CreateTexture(nil, 'BACKGROUND')
            button._mmFreshnessFill:SetAllPoints()
            if button._mmFreshnessFill.SetTexture then
                button._mmFreshnessFill:SetTexture(pillPath)
            end
        end
        if self.hovered or scanning then
            if button._mmFreshnessFill.Show then button._mmFreshnessFill:Show() end
            local hCol = (self.ahNotOpen and not scanning) and activeColors().red
                or (scanning and scanBlue or ((self.state.status == 'red') and statusColor or (isLight and { 0, 0, 0 } or { 1, 1, 1 })))
            local hAlpha = (self.ahNotOpen and not scanning) and 0.14 or (scanning and 0.16 or ((self.state.status == 'red') and 0.14 or (isLight and 0.08 or 0.10)))
            if button._mmFreshnessFill.SetTexture and button._mmFreshnessFill.SetVertexColor then
                button._mmFreshnessFill:SetVertexColor(hCol[1], hCol[2], hCol[3], hAlpha)
            elseif button._mmFreshnessFill.SetColorTexture then
                button._mmFreshnessFill:SetColorTexture(hCol[1], hCol[2], hCol[3], hAlpha)
            end
        else
            if button._mmFreshnessFill.Hide then
                button._mmFreshnessFill:Hide()
            elseif button._mmFreshnessFill.SetVertexColor then
                button._mmFreshnessFill:SetVertexColor(0, 0, 0, 0)
            end
        end
        button.freshnessStatus = self.state.status
        button.scanning = scanning
        button.ahNotOpen = self.ahNotOpen == true
        c.iconPath = self.ahNotOpen and closeIconPath or iconPath
        if wasAhNotOpen and not self.ahNotOpen and not self.hovered then hideOwnedTooltip() end
        if self.hovered then tooltip() end
    end
    button:SetScript('OnClick', function()
        local api = _G.MerchantMasterAPI
        local app = ns.app
        if c.lotScanOnly and safe(app) and type(app) == 'table' and type(app.cancelOrderBookScan) == 'function' then
            c.ahNotOpen = false
            app.cancelOrderBookScan() -- "Click to stop AH scan" must stop a deep lot scan, not start a browse scan
        elseif c.scanning then
            c.ahNotOpen = false
            if safe(api) and type(api) == 'table' and safe(api.RefreshMarket) and type(api.RefreshMarket) == 'function' then api.RefreshMarket() end
        elseif safe(api) and type(api) == 'table' and safe(api.RefreshMarket) and type(api.RefreshMarket) == 'function' then
            local ok = api.RefreshMarket()
            if safe(ok) and ok == false and not scanStatus() then
                c.ahNotOpen = true
                c._ahNotOpenStamp = c._manualStamp
            else
                c.ahNotOpen = false
            end
        end
        c:Update()
        if c.ahNotOpen and not c.scanning then tooltip() end
    end)
    button:SetScript('OnEnter', function() c.hovered = true; c:Update() end)
    button:SetScript('OnLeave', function() c.hovered = false; c:Update(); if GameTooltip_Hide then GameTooltip_Hide() end end)
    if ns.Theme and ns.Theme.OnModeChanged then
        ns.Theme.OnModeChanged(function() c:Update() end)
    end
    local function start()
        c:Update()
        local elapsed = 0
        button:SetScript('OnUpdate', function(_, dt)
            dt = dt or 0
            if c.scanning then
                c._spinAngle = ((c._spinAngle or 0) - dt * 6.2831853) % 6.2831853
                if icon.SetRotation then icon:SetRotation(c._spinAngle) end
                local app = ns.app
                if type(app) == 'table' and type(app.stepScanShuttle) == 'function' then app.stepScanShuttle(dt) end
            end
            elapsed = elapsed + dt
            if elapsed >= 1 then elapsed = elapsed % 1; c:Update() end
        end)
    end
    panel:HookScript('OnShow', start)
    panel:HookScript('OnHide', function()
        button:SetScript('OnUpdate', nil)
        c.hovered = false
        local wasAhNotOpen = c.ahNotOpen == true
        c.ahNotOpen = false
        if wasAhNotOpen then hideOwnedTooltip() end
        c:Update()
    end)
    if panel:IsShown() then start() else c:Update() end
    return c
end
