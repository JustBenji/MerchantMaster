-- MerchantMaster MailHelper.lua
-- Native mailbox batch looter docked to Blizzard's MailFrame.
-- Never writes to Analytics\Store directly; invokes standard global WoW mail
-- APIs (TakeInboxMoney / AutoLootMailItem) so Analytics\Capture logs once.

local ADDON, ns = ...
ns = ns or {}

local MH = ns.MailHelper or {}
ns.MailHelper = MH

MH.MAX_SLOT_RETRIES = 2
MH.STALL_WATCHDOG_SEC = 1.2
MH.REFRESH_COOLDOWN_SEC = 60

local function hasSecret(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if _G.issecrettable and type(v) == "table" and _G.issecrettable(v) then return true end
        if _G.issecretvalue and _G.issecretvalue(v) then return true end
    end
    return false
end

local function nowSec()
    if type(_G.GetTime) == "function" then
        local t = _G.GetTime()
        if not hasSecret(t) and tonumber(t) then return tonumber(t) end
    end
    if type(_G.time) == "function" then
        local t = _G.time()
        if not hasSecret(t) and tonumber(t) then return tonumber(t) end
    end
    return (os and os.time and os.time()) or 0
end

local function getPalette()
    local theme = ns.Theme
    if theme and type(theme.GetActivePalette) == "function" then
        local p = theme.GetActivePalette()
        if type(p) == "table" then return p end
    end
    return {
        mode = "dark",
        cardBg = { 0.149, 0.149, 0.165, 0.96 },
        cardAltBg = { 0.180, 0.180, 0.196, 1.0 },
        border = { 1.0, 1.0, 1.0, 0.14 },
        borderStrong = { 1.0, 1.0, 1.0, 0.22 },
        text = { 1.0, 1.0, 1.0, 1.0 },
        textSecondary = { 0.922, 0.922, 0.961, 0.72 },
        textMuted = { 0.682, 0.682, 0.698, 1.0 },
        hexText = "ffffff",
        hexMuted = "98989d",
        hexPositive = "30d158",
        hexWarning = "ff9230",
        hexDanger = "ff4245",
        hexBlue = "5ac8fa",
    }
end

local function palHex(key, fb)
    local p = getPalette()
    local hex = (type(p) == "table" and type(p[key]) == "string" and p[key] ~= "") and p[key] or (fb or "ffffff")
    return "|cff" .. hex
end

local function matchSubjectPrefix(subject, globalTmpl, fallbackSubstr)
    if type(subject) ~= "string" or subject == "" then return false end
    local subLow = string.lower(subject)
    if not hasSecret(globalTmpl) and type(globalTmpl) == "string" and globalTmpl ~= "" then
        local prefix = string.lower(globalTmpl):match("^(.-)%%s") or string.lower(globalTmpl)
        prefix = prefix:gsub("%s+$", "")
        if prefix ~= "" and subLow:find(prefix, 1, true) then
            return true
        end
    end
    if fallbackSubstr and fallbackSubstr ~= "" and subLow:find(fallbackSubstr, 1, true) then
        return true
    end
    return false
end

local function formatCopperSimple(copper)
    local n = math.max(0, math.floor((tonumber(copper) or 0) + 0.5))
    local g = math.floor(n / 10000)
    local s = math.floor((n % 10000) / 100)
    local c = n % 100
    if g > 0 then
        return string.format("%dg %02ds", g, s)
    elseif s > 0 then
        return string.format("%ds %02dc", s, c)
    end
    return string.format("%dc", c)
end

local state = {
    active = false,
    mode = nil,
    mailOpen = false,
    pendingMount = false,
    waitingServer = false,
    clickStepper = false,
    serial = 0,
    lastSlot = nil,
    slotRetries = {},
    seenCOD = {},
    seenBlocked = {},
    lootedCount = 0,
    lootedCopper = 0,
    skippedCOD = 0,
    skippedBlocked = 0,
    skippedBagsFull = false,
    statusText = "Ready",
    statusKind = "muted",
    lastCheckInboxAt = 0,
}

function MH.IsActive()
    return state.active == true
end

function MH.GetState()
    return {
        active = state.active,
        mode = state.mode,
        mailOpen = state.mailOpen,
        waitingServer = state.waitingServer,
        clickStepper = state.clickStepper,
        lootedCount = state.lootedCount,
        lootedCopper = state.lootedCopper,
        skippedCOD = state.skippedCOD,
        skippedBlocked = state.skippedBlocked,
        skippedBagsFull = state.skippedBagsFull,
        statusText = state.statusText,
        lastCheckInboxAt = state.lastCheckInboxAt,
    }
end

function MH.GetFreeBagSlots()
    local total = 0
    local numBags = tonumber(_G.NUM_BAG_SLOTS) or 4
    local getFree = (_G.C_Container and _G.C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
    if type(getFree) ~= "function" then return 0 end
    for bag = 0, numBags do
        local free, bagFamily = getFree(bag)
        if not hasSecret(free, bagFamily) then
            local f = tonumber(free) or 0
            local fam = tonumber(bagFamily) or 0
            if bag == 0 or fam == 0 then
                total = total + math.max(0, f)
            end
        end
    end
    return total
end

function MH.ClassifySlot(index)
    if hasSecret(index) or not tonumber(index) then
        return "skip_unloaded", { index = index, reason = "invalid_index" }
    end
    if type(_G.GetInboxHeaderInfo) ~= "function" then
        return "skip_unloaded", { index = index, reason = "no_api" }
    end
    local packageIcon, stationeryIcon, sender, subject, money, codAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM = _G.GetInboxHeaderInfo(index)
    local invoiceType
    if type(_G.GetInboxInvoiceInfo) == "function" then
        invoiceType = _G.GetInboxInvoiceInfo(index)
    end
    -- Fail-CLOSED COD and unloaded header guard.
    local retrieving = (type(_G.RETRIEVING_DATA) == "string" and _G.RETRIEVING_DATA ~= "") and _G.RETRIEVING_DATA or "Retrieving data..."
    if hasSecret(packageIcon, stationeryIcon, sender, subject, money, codAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM, invoiceType)
        or subject == nil
        or subject == ""
        or subject == retrieving
        or codAmount == nil then
        return "skip_unloaded", { index = index, reason = "unloaded" }
    end

    local cod = tonumber(codAmount)
    if cod == nil then
        return "skip_unloaded", { index = index, reason = "unloaded_cod" }
    end
    if cod > 0 then
        return "cod", {
            index = index,
            sender = sender,
            subject = subject,
            codAmount = cod,
            money = tonumber(money) or 0,
            itemCount = (hasItem == true and 1) or (tonumber(hasItem) or 0),
        }
    end

    local itemCount = (hasItem == true and 1) or (tonumber(hasItem) or 0)
    local moneyAmt = tonumber(money) or 0
    local info = {
        index = index,
        sender = sender,
        subject = subject,
        money = moneyAmt,
        codAmount = 0,
        itemCount = itemCount,
        invoiceType = invoiceType,
        daysLeft = tonumber(daysLeft),
    }

    if moneyAmt <= 0 and itemCount <= 0 then
        return "empty", info
    end
    if invoiceType == "seller" or invoiceType == "seller_temp_invoice" then
        return "ah_sale", info
    end
    if invoiceType == "buyer" then
        return "ah_won", info
    end
    if matchSubjectPrefix(subject, _G.AUCTION_OUTBID_MAIL_SUBJECT, "outbid") then
        return "ah_outbid", info
    end
    if matchSubjectPrefix(subject, _G.AUCTION_EXPIRED_MAIL_SUBJECT, "expir")
        or matchSubjectPrefix(subject, _G.AUCTION_REMOVED_MAIL_SUBJECT, "cancel") then
        return "ah_expired", info
    end
    if moneyAmt > 0 and matchSubjectPrefix(subject, _G.AUCTION_SOLD_MAIL_SUBJECT, "auction successful:") then
        return "ah_sale", info
    end
    if itemCount > 0 then
        return "items", info
    end
    return "money", info
end

local function modeMatches(kind, mode)
    if mode == "all" or not mode then
        return kind == "ah_sale" or kind == "ah_won" or kind == "ah_outbid"
            or kind == "ah_expired" or kind == "money" or kind == "items"
    elseif mode == "ah_sales" then
        return kind == "ah_sale"
    elseif mode == "ah_expired" then
        return kind == "ah_expired"
    elseif mode == "ah_won" then
        return kind == "ah_won"
    elseif mode == "ah_outbid" then
        return kind == "ah_outbid"
    end
    return false
end

local function slotSignature(info)
    if type(info) ~= "table" then return "" end
    return table.concat({
        tostring(info.sender or ""),
        tostring(info.subject or ""),
        tostring(info.money or 0),
        tostring(info.itemCount or 0),
        tostring(info.codAmount or 0),
    }, "|")
end

local function buildSummaryStatus(reason)
    if reason == "mail_closed" then
        return "Mailbox closed", "muted"
    end
    if reason == "user_stop" then
        return string.format("Stopped (%d looted)", state.lootedCount), "warning"
    end
    local parts = {}
    if state.lootedCount > 0 then
        if state.lootedCopper > 0 then
            parts[#parts + 1] = string.format("Looted %d (%s)", state.lootedCount, formatCopperSimple(state.lootedCopper))
        else
            parts[#parts + 1] = string.format("Looted %d", state.lootedCount)
        end
    else
        parts[#parts + 1] = "Nothing to loot"
    end
    if state.skippedCOD > 0 then
        parts[#parts + 1] = string.format("Skipped %d COD", state.skippedCOD)
    end
    if state.skippedBagsFull then
        parts[#parts + 1] = "Bags full"
    end
    if state.skippedBlocked > 0 then
        parts[#parts + 1] = string.format("%d blocked", state.skippedBlocked)
    end
    local kind = (state.skippedBagsFull or state.skippedCOD > 0 or state.skippedBlocked > 0) and "warning" or "positive"
    return table.concat(parts, " | "), kind
end

local function pauseOrderFlowMail()
    local app = ns.app
    local of = app and app.orderFlow
    if not of then return end
    if type(of.PauseMailCollect) == "function" then
        pcall(of.PauseMailCollect)
        return
    end
    if type(of.GetState) == "function" then
        local ok, st = pcall(of.GetState)
        if ok and type(st) == "table" and st.stages and st.stages.collect and st.stages.collect.pendingTake then
            if st.stages.collect.pendingTake.source == "mail" then
                st.stages.collect.pendingTake = nil
            end
        end
    end
end

local function triggerFinalMailboxScan()
    local app = ns.app
    if app and type(app.QueueMailboxScan) == "function" then
        pcall(app.QueueMailboxScan, "take")
        return
    end
    local cap = ns.Analytics and ns.Analytics.Capture
    if cap and type(cap.ScanMailboxSnapshot) == "function" then
        pcall(cap.ScanMailboxSnapshot, true)
    end
end

function MH.UpdateUI()
    local bar = MH.bar
    if not bar then return end
    local colKey = (state.statusKind == "positive" and "hexPositive")
        or (state.statusKind == "warning" and "hexWarning")
        or (state.statusKind == "danger" and "hexDanger")
        or (state.statusKind == "blue" and "hexBlue")
        or "hexMuted"
    if bar.statusFs and bar.statusFs.SetText then
        bar.statusFs:SetText(palHex(colKey, "98989d") .. tostring(state.statusText or "Ready") .. "|r")
    end
    if bar.modeBtns then
        for _, entry in ipairs(bar.modeBtns) do
            if entry.btn and entry.btn.SetActive then
                entry.btn:SetActive(state.active and state.mode == entry.mode)
            end
        end
    end
    if bar.stopBtn and bar.stopBtn.SetEnabled then
        bar.stopBtn:SetEnabled(state.active == true)
    end
    if bar.refreshBtn and bar.refreshBtn.SetText then
        if state.active and state.clickStepper then
            bar.refreshBtn:SetText("Next")
        else
            bar.refreshBtn:SetText("Refresh")
        end
    end
end

function MH.Stop(reason)
    local wasActive = state.active == true
    state.active = false
    state.waitingServer = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    local text, kind = buildSummaryStatus(reason)
    state.statusText = text
    state.statusKind = kind
    MH.UpdateUI()
    if wasActive and reason ~= "mail_closed" then
        triggerFinalMailboxScan()
    end
    return true
end

function MH.Start(mode)
    if _G.MailFrame and type(_G.MailFrame.IsShown) == "function" and not _G.MailFrame:IsShown() and not state.mailOpen then
        state.statusText = "Open mailbox first"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "mail_closed"
    end
    pauseOrderFlowMail()
    state.active = true
    state.mode = mode or "all"
    state.waitingServer = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    state.slotRetries = {}
    state.seenCOD = {}
    state.seenBlocked = {}
    state.lootedCount = 0
    state.lootedCopper = 0
    state.skippedCOD = 0
    state.skippedBlocked = 0
    state.skippedBagsFull = false
    state.statusText = "Scanning inbox..."
    state.statusKind = "blue"
    MH.UpdateUI()
    return MH.Step()
end

function MH.Step()
    if not state.active then return false, "inactive" end
    if state.waitingServer then return false, "waiting" end
    if type(_G.GetInboxNumItems) ~= "function" then
        MH.Stop("no_api")
        return false, "no_api"
    end
    local numItems, totalItems = _G.GetInboxNumItems()
    if hasSecret(numItems, totalItems) then
        MH.Stop("secret_inbox")
        return false, "secret"
    end
    numItems = tonumber(numItems) or 0
    totalItems = tonumber(totalItems) or numItems
    local freeSlots = MH.GetFreeBagSlots()

    -- Reconcile previous step: only count a retry when the exact same uncollected mail
    -- remained unchanged; clear/retire retries when the take succeeded (inbox shrunk or slot mutated).
    if state.lastSlot then
        local prev = state.lastSlot
        state.lastSlot = nil
        local unchanged = false
        if numItems == prev.numItems and prev.index >= 1 and prev.index <= numItems then
            local _, curInfo = MH.ClassifySlot(prev.index)
            if curInfo and slotSignature(curInfo) == prev.sig
                and (curInfo.money or 0) == (prev.money or 0)
                and (curInfo.itemCount or 0) == (prev.itemCount or 0) then
                unchanged = true
            end
        end
        if unchanged then
            state.slotRetries[prev.instKey] = (state.slotRetries[prev.instKey] or 0) + 1
            state.lootedCount = math.max(0, state.lootedCount - 1)
            state.lootedCopper = math.max(0, state.lootedCopper - (prev.copper or 0))
        else
            state.slotRetries[prev.instKey] = nil
            local removedDelta = (prev.numItems or 0) - numItems
            if removedDelta > 0 then
                -- Shift tracked retry/blocked indices above the removed slot so shifted blocked mails are not retried or double-counted.
                local function shiftIndexedMap(tbl)
                    local updated = {}
                    for k, v in pairs(tbl) do
                        local uIdx = k:match("^unloaded:(%d+)$")
                        if uIdx then
                            local j = tonumber(uIdx)
                            if j and j > prev.index then
                                updated["unloaded:" .. tostring(math.max(1, j - removedDelta))] = v
                            elseif j and j < prev.index then
                                updated[k] = v
                            end
                        else
                            local sIdx, rest = k:match("^(%d+)|(.*)$")
                            local j = tonumber(sIdx)
                            if j and rest then
                                if j > prev.index then
                                    updated[tostring(math.max(1, j - removedDelta)) .. "|" .. rest] = v
                                elseif j < prev.index then
                                    updated[k] = v
                                end
                            else
                                updated[k] = v
                            end
                        end
                    end
                    return updated
                end
                state.slotRetries = shiftIndexedMap(state.slotRetries)
                state.seenBlocked = shiftIndexedMap(state.seenBlocked)
            end
        end
    end

    for i = numItems, 1, -1 do
        local kind, info = MH.ClassifySlot(i)
        if kind == "skip_unloaded" then
            local bKey = "unloaded:" .. tostring(i)
            if not state.seenBlocked[bKey] then
                state.seenBlocked[bKey] = true
                state.skippedBlocked = state.skippedBlocked + 1
            end
        elseif kind == "cod" then
            local sig = slotSignature(info)
            if not state.seenCOD[sig] then
                state.seenCOD[sig] = true
                state.skippedCOD = state.skippedCOD + 1
            end
        elseif kind ~= "empty" and modeMatches(kind, state.mode) then
            local sig = slotSignature(info)
            local instKey = tostring(i) .. "|" .. sig
            local retries = state.slotRetries[instKey] or 0
            if retries >= MH.MAX_SLOT_RETRIES then
                if not state.seenBlocked[instKey] then
                    state.seenBlocked[instKey] = true
                    state.skippedBlocked = state.skippedBlocked + 1
                end
            else
                local hasMoney = (info.money or 0) > 0
                local hasItems = (info.itemCount or 0) > 0
                local action, expectedCopper

                if hasMoney and hasItems and freeSlots == 0 then
                    -- Hybrid mail when bags are full: loot gold first without touching attachments.
                    action = "money"
                    expectedCopper = info.money
                    state.skippedBagsFull = true
                elseif hasMoney and not hasItems then
                    action = "money"
                    expectedCopper = info.money
                elseif hasItems and freeSlots > 0 then
                    action = "item"
                    expectedCopper = info.money
                elseif hasItems and freeSlots == 0 then
                    state.skippedBagsFull = true
                end

                if action then
                    state.waitingServer = true
                    state.lastSlot = {
                        index = i,
                        numItems = numItems,
                        sig = sig,
                        instKey = instKey,
                        money = info.money or 0,
                        itemCount = info.itemCount or 0,
                        action = action,
                        copper = expectedCopper or 0,
                    }
                    state.lootedCount = state.lootedCount + 1
                    state.lootedCopper = state.lootedCopper + (expectedCopper or 0)
                    state.serial = state.serial + 1
                    local stepSerial = state.serial

                    if action == "money" then
                        if type(_G.TakeInboxMoney) == "function" then
                            pcall(_G.TakeInboxMoney, i)
                        end
                    else
                        if type(_G.AutoLootMailItem) == "function" then
                            pcall(_G.AutoLootMailItem, i)
                        elseif type(_G.TakeInboxMoney) == "function" and hasMoney then
                            pcall(_G.TakeInboxMoney, i)
                        end
                    end

                    if state.clickStepper then
                        state.statusText = "Click Next to continue"
                        state.statusKind = "warning"
                    else
                        state.statusText = string.format("Looting #%d (%d done)...", i, state.lootedCount)
                        state.statusKind = "blue"
                    end
                    MH.UpdateUI()

                    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
                        _G.C_Timer.After(MH.STALL_WATCHDOG_SEC, function()
                            if state.active and state.serial == stepSerial and state.waitingServer then
                                state.waitingServer = false
                                if not state.clickStepper then
                                    MH.Step()
                                else
                                    state.statusText = "Click Next to continue"
                                    state.statusKind = "warning"
                                    MH.UpdateUI()
                                end
                            end
                        end)
                    end
                    return true, action, i
                end
            end
        end
    end

    MH.Stop("done")
    if totalItems > numItems then
        state.statusText = state.statusText .. " | More waiting"
        MH.UpdateUI()
    end
    return false, "done"
end

function MH.RequestRefresh()
    local now = nowSec()
    local elapsed = now - (state.lastCheckInboxAt or 0)
    if state.lastCheckInboxAt > 0 and elapsed < MH.REFRESH_COOLDOWN_SEC then
        local rem = math.max(1, math.ceil(MH.REFRESH_COOLDOWN_SEC - elapsed))
        state.statusText = string.format("Refresh ready in %ds", rem)
        state.statusKind = "muted"
        MH.UpdateUI()
        return false, "cooldown", rem
    end
    state.lastCheckInboxAt = now
    if type(_G.CheckInbox) == "function" then
        pcall(_G.CheckInbox)
    end
    state.statusText = "Refreshing inbox..."
    state.statusKind = "blue"
    MH.UpdateUI()
    return true
end

local function makeBarButton(parent, label, w, h, variant, onClick)
    local theme = ns.Theme
    local btn
    if theme and type(theme.CreatePlateButton) == "function" then
        btn = theme.CreatePlateButton(parent, label, w, h, {
            variant = variant or "secondary",
            fontSize = 11,
            radius = 8,
        })
    else
        btn = _G.CreateFrame("Button", nil, parent)
        btn:SetSize(w, h)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(label)
        if btn.SetFontString then btn:SetFontString(fs) end
        btn.fs = fs
    end
    if btn.SetScript then
        btn:SetScript("OnClick", onClick)
    end
    return btn
end

function MH.MountOnMailFrame()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        state.pendingMount = true
        return false, "combat"
    end
    local mf = _G.MailFrame
    if not mf or type(_G.CreateFrame) ~= "function" then
        return false, "no_mail_frame"
    end
    if MH.bar then
        MH.UpdateUI()
        return true, MH.bar
    end

    local bar = _G.CreateFrame("Frame", "MerchantMasterMailHelperBar", mf)
    bar:SetHeight(62)
    bar:SetPoint("TOPLEFT", mf, "BOTTOMLEFT", 0, -4)
    bar:SetPoint("TOPRIGHT", mf, "BOTTOMRIGHT", 0, -4)

    local theme = ns.Theme
    local pal = getPalette()
    if theme and type(theme.NineApple) == "function" then
        bar._bgSurf = theme.NineApple(bar, "glass_r12", pal.cardBg, pal.borderStrong, { noSpecular = true })
    end

    local function paintBar()
        local p = getPalette()
        if bar._bgSurf then
            if bar._bgSurf.SetFill and p.cardBg then
                bar._bgSurf:SetFill(p.cardBg[1], p.cardBg[2], p.cardBg[3], p.cardBg[4] or 0.96)
            end
            if bar._bgSurf.SetBorder and p.borderStrong then
                bar._bgSurf:SetBorder(p.borderStrong[1], p.borderStrong[2], p.borderStrong[3], p.borderStrong[4] or 0.22)
            end
            if bar._bgSurf.SetColors and p.cardBg and p.borderStrong then
                bar._bgSurf:SetColors(p.cardBg, p.borderStrong)
            end
        end
        MH.UpdateUI()
    end

    if theme and type(theme.RegisterWidget) == "function" then
        theme.RegisterWidget(bar, paintBar)
    end

    -- Row 1 (y = -6, height 24px): 4 equal buttons across MailFrame width (~338px).
    local barW = (mf.GetWidth and tonumber(mf:GetWidth())) or 338
    if barW < 260 then barW = 338 end
    local padX, gapX = 6, 4
    local btnW = math.floor((barW - padX * 2 - gapX * 3) / 4)
    local modeDefs = {
        { mode = "all", label = "Open All", variant = "primary" },
        { mode = "ah_sales", label = "AH Sales", variant = "secondary" },
        { mode = "ah_expired", label = "Expired", variant = "secondary" },
        { mode = "ah_won", label = "Won", variant = "secondary" },
    }
    bar.modeBtns = {}
    for idx, def in ipairs(modeDefs) do
        local m = def.mode
        local b = makeBarButton(bar, def.label, btnW, 24, def.variant, function()
            if state.active and state.clickStepper and state.mode == m then
                MH.Step()
            else
                MH.Start(m)
            end
        end)
        local xOff = padX + (idx - 1) * (btnW + gapX)
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", xOff, -6)
        bar.modeBtns[idx] = { mode = m, btn = b }
    end

    -- Row 2 (y = -34, height 22px): status FontString (left) + Refresh/Next + Stop (right).
    local stopBtn = makeBarButton(bar, "Stop", 52, 22, "secondary", function()
        MH.Stop("user_stop")
    end)
    stopBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -padX, -34)
    if stopBtn.SetEnabled then stopBtn:SetEnabled(false) end
    bar.stopBtn = stopBtn

    local refreshBtn = makeBarButton(bar, "Refresh", 62, 22, "secondary", function()
        if state.active and state.clickStepper then
            MH.Step()
        else
            MH.RequestRefresh()
        end
    end)
    refreshBtn:SetPoint("RIGHT", stopBtn, "LEFT", -4, 0)
    bar.refreshBtn = refreshBtn

    local statusFs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("LEFT", bar, "LEFT", padX + 2, -14)
    statusFs:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
    statusFs:SetPoint("TOP", bar, "TOP", 0, -34)
    statusFs:SetHeight(22)
    if statusFs.SetJustifyH then statusFs:SetJustifyH("LEFT") end
    if statusFs.SetJustifyV then statusFs:SetJustifyV("MIDDLE") end
    if statusFs.SetWordWrap then statusFs:SetWordWrap(false) end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(statusFs, 11, "regular")
    end
    bar.statusFs = statusFs

    MH.bar = bar
    paintBar()
    return true, bar
end

local function isMailActionBlocked(addonArg, funcName)
    if type(funcName) == "string" then
        if funcName == "TakeInboxMoney" or funcName == "AutoLootMailItem" or funcName == "TakeInboxItem" then
            return true
        end
    end
    if addonArg == ADDON or addonArg == "MerchantMaster" then
        return true
    end
    return funcName == nil and addonArg == nil
end

function MH.OnEvent(self, event, arg1, arg2)
    if hasSecret(event, arg1, arg2) then return end
    if event == "MAIL_SHOW" then
        state.mailOpen = true
        MH.MountOnMailFrame()
        MH.UpdateUI()
    elseif event == "MAIL_CLOSED" then
        state.mailOpen = false
        if state.active then
            MH.Stop("mail_closed")
        end
    elseif event == "MAIL_INBOX_UPDATE" then
        if state.active and state.waitingServer then
            state.waitingServer = false
            state.serial = state.serial + 1
            if state.clickStepper then
                state.statusText = "Click Next to continue"
                state.statusKind = "warning"
                MH.UpdateUI()
            else
                MH.Step()
            end
        else
            MH.UpdateUI()
        end
    elseif event == "ADDON_ACTION_BLOCKED" then
        if state.active and isMailActionBlocked(arg1, arg2) then
            state.clickStepper = true
            state.waitingServer = false
            state.serial = state.serial + 1
            state.statusText = "Click Next to continue"
            state.statusKind = "warning"
            MH.UpdateUI()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.pendingMount and state.mailOpen then
            state.pendingMount = false
            MH.MountOnMailFrame()
        end
    end
end

if not MH.frame and type(_G.CreateFrame) == "function" then
    local f = _G.CreateFrame("Frame")
    MH.frame = f
    f:SetScript("OnEvent", MH.OnEvent)
    for _, ev in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "ADDON_ACTION_BLOCKED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, ev)
    end
end
