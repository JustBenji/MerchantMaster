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
    presetPage = 1,
    pendingConfirm = nil,
    bypassConfirmRecipient = nil,
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
        presetPage = state.presetPage,
        barShown = (MH.bar ~= nil and MH.bar.IsShown and MH.bar:IsShown()) == true,
        presetsPanelShown = (MH.presetsPanel ~= nil and MH.presetsPanel.IsShown and MH.presetsPanel:IsShown()) == true,
        inboxQuickStripShown = (MH.inboxQuickStrip ~= nil and MH.inboxQuickStrip.IsShown and MH.inboxQuickStrip:IsShown()) == true,
        pendingConfirm = state.pendingConfirm and state.pendingConfirm.recipient or nil,
        bypassConfirmRecipient = state.bypassConfirmRecipient,
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

-- =========================================================================
-- Mail Recipients Presets, Quick-Pick Panels & Unsaved-Recipient Safety Net
-- =========================================================================

MH.UNSAVED_CONFIRM_POPUP = "MERCHANTMASTER_CONFIRM_UNSAVED_MAIL"
MH.PRESET_PAGE_SIZE = 8
MH.DOCK_PANEL_WIDTH = 280
MH.HELPER_PANEL_HEIGHT = 124
MH.STATUS_PILL_MAX_WIDTH = 260
MH.DOCK_GAP_X = 6
MH.DOCK_GAP_Y = 6

MH.PRESET_ROLE_DEFS = {
    { key = "bank",           label = "Bank",           shortLabel = "Bank",      icon = 133784, group = "core" },
    { key = "auction",        label = "Auction",        shortLabel = "AH",        icon = 133785, group = "core" },
    { key = "mainCrafter",    label = "Main Crafter",   shortLabel = "Crafter",   icon = 136241, group = "core" },
    { key = "alchemy",        label = "Alchemy",        shortLabel = "Alch",      icon = 136240, group = "profession" },
    { key = "blacksmithing",  label = "Blacksmithing",  shortLabel = "BS",        icon = 136241, group = "profession" },
    { key = "enchanting",     label = "Enchanting",     shortLabel = "Ench",      icon = 136244, group = "profession" },
    { key = "engineering",    label = "Engineering",    shortLabel = "Eng",       icon = 136243, group = "profession" },
    { key = "leatherworking", label = "Leatherworking", shortLabel = "LW",        icon = 136247, group = "profession" },
    { key = "tailoring",      label = "Tailoring",      shortLabel = "Tailor",    icon = 136249, group = "profession" },
    { key = "cooking",        label = "Cooking",        shortLabel = "Cook",      icon = 133971, group = "profession" },
    { key = "firstaid",       label = "First Aid",      shortLabel = "First Aid", icon = 135966, group = "profession" },
}

MH.PROFESSION_ROLE_KEYS = {
    "alchemy", "blacksmithing", "enchanting", "engineering",
    "leatherworking", "tailoring", "cooking", "firstaid",
}

local CORE_ROLE_MAP = { bank = true, auction = true, mainCrafter = true }
local PROF_ROLE_MAP = {
    alchemy = true, blacksmithing = true, enchanting = true, engineering = true,
    leatherworking = true, tailoring = true, cooking = true, firstaid = true,
}
local DISPLAY_OPTION_KEYS = {
    showIcon = true,
    showName = true,
    showRole = true,
    warnUnsaved = true,
}

local function trimOuter(raw)
    if hasSecret(raw) or type(raw) ~= "string" then return "" end
    return (raw:match("^%s*(.-)%s*$")) or ""
end

local function getCurrentRealmParts()
    local rawRealm = (_G.GetRealmName and _G.GetRealmName()) or ""
    if hasSecret(rawRealm) or type(rawRealm) ~= "string" then
        rawRealm = ""
    end
    rawRealm = trimOuter(rawRealm)
    local compactRealm = rawRealm:gsub("%s+", "")
    return rawRealm, compactRealm
end

-- WoW Forever surname-safe normalization:
-- trims outer spaces only, preserves internal surname space ("First Last"),
-- strips "-CurrentRealm" case-insensitively (both raw and whitespace-compacted realm).
local function normalizeName(raw)
    local trimmed = trimOuter(raw)
    if trimmed == "" then return "" end
    local base, suffix = trimmed:match("^(.-)%-([^%-]+)$")
    if base and base ~= "" and suffix and suffix ~= "" then
        local rawRealm, compactRealm = getCurrentRealmParts()
        if rawRealm ~= "" then
            local sufLow = string.lower(trimOuter(suffix))
            local sufCompact = string.lower(suffix:gsub("%s+", ""))
            if sufLow == string.lower(rawRealm)
                or sufLow == string.lower(compactRealm)
                or sufCompact == string.lower(compactRealm) then
                return trimOuter(base)
            end
        end
    end
    return trimmed
end

MH.NormalizeCharacterName = normalizeName

local function canonicalKey(raw)
    local norm = normalizeName(raw)
    if norm == "" then return "" end
    return string.lower(norm)
end

local function computeInitials(name)
    local norm = normalizeName(name)
    if norm == "" then return "??" end
    local w1, w2 = norm:match("^([^%s]+)%s+([^%s]+)")
    if w1 and w2 then
        return string.upper(w1:sub(1, 1) .. w2:sub(1, 1))
    end
    local base = norm:match("^([^%-]+)") or norm
    if #base >= 2 then
        return string.upper(base:sub(1, 2))
    end
    return string.upper(base:sub(1, 1))
end

local function resolveEconKey(econKey)
    if not hasSecret(econKey) and type(econKey) == "string" and econKey ~= "" then
        return econKey
    end
    if type(ns.CurrentEconomyInfo) == "function" then
        local ok, info = pcall(ns.CurrentEconomyInfo)
        if ok and type(info) == "table" and type(info.key) == "string" and info.key ~= "" then
            return info.key
        end
    end
    if type(ns.DetectActiveEconomy) == "function" then
        local ok, econ = pcall(ns.DetectActiveEconomy)
        if ok and not hasSecret(econ) and type(econ) == "string" and econ ~= "" then
            return econ
        end
    end
    if ns.app and type(ns.app.char) == "table" and type(ns.app.char.economy) == "string" and ns.app.char.economy ~= "" then
        return ns.app.char.economy
    end
    return "Normal-Horde"
end

local function getCurrentPlayerName()
    if type(ns.GetPlayerFullName) == "function" then
        local ok, full = pcall(ns.GetPlayerFullName)
        if ok and not hasSecret(full) and type(full) == "string" and trimOuter(full) ~= "" then
            return normalizeName(full)
        end
    end
    if type(_G.UnitName) == "function" then
        local ok, uName, uSecond = pcall(_G.UnitName, "player")
        if ok and not hasSecret(uName, uSecond) and type(uName) == "string" and trimOuter(uName) ~= "" then
            if _G.RegionalUniqueNamesEnabled and _G.RegionalUniqueNamesEnabled()
                and type(uSecond) == "string" and trimOuter(uSecond) ~= "" then
                return normalizeName(uName .. " " .. uSecond)
            end
            return normalizeName(uName)
        end
    end
    if ns.app and type(ns.app.char) == "table" and type(ns.app.char.name) == "string" and trimOuter(ns.app.char.name) ~= "" then
        return normalizeName(ns.app.char.name)
    end
    return ""
end

local function ensureEconTable(byEcon, econKey)
    local rec = byEcon[econKey]
    if type(rec) ~= "table" then
        rec = {}
        byEcon[econKey] = rec
    end
    if type(rec.bank) ~= "string" then rec.bank = "" end
    if type(rec.auction) ~= "string" then rec.auction = "" end
    if type(rec.mainCrafter) ~= "string" then rec.mainCrafter = "" end
    if type(rec.professions) ~= "table" then rec.professions = {} end
    for _, pk in ipairs(MH.PROFESSION_ROLE_KEYS) do
        if type(rec.professions[pk]) ~= "string" then
            rec.professions[pk] = ""
        end
    end
    return rec
end

function MH.GetMailPresetsConfig()
    if type(_G.MerchantMasterDB) ~= "table" then
        _G.MerchantMasterDB = {}
    end
    local db = _G.MerchantMasterDB
    if type(db.mailPresets) ~= "table" then
        db.mailPresets = {}
    end
    local cfg = db.mailPresets
    if type(cfg.display) ~= "table" then
        cfg.display = {}
    end
    if cfg.display.showIcon == nil then cfg.display.showIcon = true end
    if cfg.display.showName == nil then cfg.display.showName = true end
    if cfg.display.showRole == nil then cfg.display.showRole = true end
    if cfg.display.warnUnsaved == nil then cfg.display.warnUnsaved = true end
    if type(cfg.byEcon) ~= "table" then
        cfg.byEcon = {}
    end
    return cfg
end

function MH.GetActiveEconPresets(econKey)
    local cfg = MH.GetMailPresetsConfig()
    local resolved = resolveEconKey(econKey)
    return ensureEconTable(cfg.byEcon, resolved), resolved
end

function MH.GetDisplayOptions()
    local cfg = MH.GetMailPresetsConfig()
    return cfg.display
end

function MH.SetDisplayOption(key, val)
    if not DISPLAY_OPTION_KEYS[key] then return nil end
    local cfg = MH.GetMailPresetsConfig()
    cfg.display[key] = (val == true)
    MH.RefreshPresetsUI()
    return cfg.display[key]
end

function MH.SetPresetCharacter(roleKey, charName, econKey)
    if type(roleKey) ~= "string" then return "" end
    local econ = MH.GetActiveEconPresets(econKey)
    local norm = normalizeName(charName)
    if CORE_ROLE_MAP[roleKey] then
        econ[roleKey] = norm
    else
        local profKey = roleKey:match("^professions%.(.+)$") or roleKey
        if PROF_ROLE_MAP[profKey] then
            econ.professions[profKey] = norm
        else
            return ""
        end
    end
    MH.RefreshPresetsUI()
    return norm
end

function MH.BuildPresetRecipientEntries(econKey)
    local econ = MH.GetActiveEconPresets(econKey)
    local playerKey = canonicalKey(getCurrentPlayerName())
    local entries = {}
    local byKey = {}

    for _, def in ipairs(MH.PRESET_ROLE_DEFS) do
        local raw = (def.group == "core") and econ[def.key] or (econ.professions and econ.professions[def.key])
        local norm = normalizeName(raw)
        if norm ~= "" then
            local key = string.lower(norm)
            local existing = byKey[key]
            if not existing then
                existing = {
                    key = key,
                    name = norm,
                    icon = def.icon,
                    primaryRole = def.key,
                    roles = { def.label },
                    roleKeys = { def.key },
                    isSelf = (playerKey ~= "" and key == playerKey),
                    initials = computeInitials(norm),
                }
                byKey[key] = existing
                entries[#entries + 1] = existing
            else
                local dup = false
                for _, rk in ipairs(existing.roleKeys) do
                    if rk == def.key then dup = true; break end
                end
                if not dup then
                    existing.roles[#existing.roles + 1] = def.label
                    existing.roleKeys[#existing.roleKeys + 1] = def.key
                end
            end
        end
    end

    for _, e in ipairs(entries) do
        e.allRolesText = table.concat(e.roles, ", ")
        if #e.roles <= 2 then
            e.roleLabel = table.concat(e.roles, " / ")
        else
            e.roleLabel = e.roles[1] .. " / " .. e.roles[2] .. " (+" .. tostring(#e.roles - 2) .. " more)"
        end
    end
    return entries
end

function MH.IsSavedMailRecipient(name, econKey)
    local key = canonicalKey(name)
    if key == "" then return false, nil end
    local entries = MH.BuildPresetRecipientEntries(econKey)
    for _, entry in ipairs(entries) do
        if entry.key == key then
            return true, entry
        end
    end
    return false, nil
end

function MH.GetKnownEconomyCharacters(econKey)
    local econ, resolved = MH.GetActiveEconPresets(econKey)
    local playerName = getCurrentPlayerName()
    local playerKey = canonicalKey(playerName)
    local seen = {}
    local out = {}

    local function addChar(rawName, realm)
        local norm = normalizeName(rawName)
        if norm == "" then return end
        local key = string.lower(norm)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = {
            name = norm,
            key = key,
            isSelf = (playerKey ~= "" and key == playerKey),
            realm = realm,
        }
    end

    if playerName ~= "" then
        addChar(playerName)
    end

    local chars = type(_G.MerchantMasterDB) == "table" and _G.MerchantMasterDB.chars
    if type(chars) == "table" then
        local econPrefix = resolved .. "-"
        for cKey, rec in pairs(chars) do
            if type(rec) == "table" then
                local recEcon = rec.economy
                local matches = (recEcon == resolved)
                    or (recEcon == nil and type(cKey) == "string" and cKey:sub(1, #econPrefix) == econPrefix)
                if matches and type(rec.name) == "string" and rec.name ~= "" then
                    addChar(rec.name, rec.realm)
                end
            end
        end
    end

    for _, def in ipairs(MH.PRESET_ROLE_DEFS) do
        local raw = (def.group == "core") and econ[def.key] or (econ.professions and econ.professions[def.key])
        if type(raw) == "string" and raw ~= "" then
            addChar(raw)
        end
    end

    table.sort(out, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        return a.key < b.key
    end)
    return out
end

function MH.HasSendMailItems()
    local maxSlots = tonumber(_G.ATTACHMENTS_MAX_SEND) or 12
    local getItem = _G.GetSendMailItem
    local getLink = _G.GetSendMailItemLink
    for slot = 1, maxSlots do
        if type(getItem) == "function" then
            local name, itemID, texture, count = getItem(slot)
            if not hasSecret(name, itemID, texture, count) then
                if (type(name) == "string" and name ~= "")
                    or (tonumber(itemID) and tonumber(itemID) > 0)
                    or (tonumber(count) and tonumber(count) > 0) then
                    return true, slot
                end
            end
        end
        if type(getLink) == "function" then
            local link = getLink(slot)
            if not hasSecret(link) and type(link) == "string" and link ~= "" then
                return true, slot
            end
        end
    end
    return false, nil
end

local function clearUnsavedConfirm()
    state.pendingConfirm = nil
    state.bypassConfirmRecipient = nil
    if type(_G.StaticPopup_Hide) == "function" then
        pcall(_G.StaticPopup_Hide, MH.UNSAVED_CONFIRM_POPUP)
    end
end

local function ensureUnsavedConfirmDialog()
    if type(_G.StaticPopupDialogs) ~= "table" then
        _G.StaticPopupDialogs = {}
    end
    _G.StaticPopupDialogs[MH.UNSAVED_CONFIRM_POPUP] = {
        text = "Are you sure you want to send items towards this character?\n\nRecipient: %s\n(Not in your saved Mail Recipients list)",
        button1 = "I am aware",
        button2 = "No",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        exclusive = 1,
        OnAccept = function()
            local pending = state.pendingConfirm
            state.pendingConfirm = nil
            if not pending then return end
            local box = _G.SendMailNameEditBox
            local curRaw = (box and box.GetText and box:GetText()) or ""
            local curTrim = trimOuter(curRaw)
            if curTrim == "" or canonicalKey(curTrim) ~= canonicalKey(pending.recipient) then
                state.bypassConfirmRecipient = nil
                return
            end
            if not MH.HasSendMailItems() then
                state.bypassConfirmRecipient = nil
                return
            end
            local btn = pending.button or _G.SendMailMailButton
            local orig = (btn and btn._mmOrigOnClick) or state.sendButtonOrigOnClick
            state.bypassConfirmRecipient = canonicalKey(curTrim)
            if type(orig) == "function" then
                pcall(orig, btn, "LeftButton")
            end
            state.bypassConfirmRecipient = nil
        end,
        OnCancel = function()
            state.pendingConfirm = nil
            state.bypassConfirmRecipient = nil
        end,
        OnHide = function()
            state.pendingConfirm = nil
            state.bypassConfirmRecipient = nil
        end,
    }
end

local function shouldInterceptUnsavedSend()
    local disp = MH.GetDisplayOptions()
    if not disp or disp.warnUnsaved ~= true then
        return false, nil
    end
    if not MH.HasSendMailItems() then
        return false, nil
    end
    local box = _G.SendMailNameEditBox
    local raw = (box and box.GetText and box:GetText()) or ""
    local trimmed = trimOuter(raw)
    if trimmed == "" then
        return false, nil
    end
    local key = canonicalKey(trimmed)
    if state.bypassConfirmRecipient and state.bypassConfirmRecipient == key then
        return false, nil
    end
    if MH.IsSavedMailRecipient(trimmed) then
        return false, nil
    end
    return true, trimmed
end

local function hookBlizzardMailVisibility()
    local function hookShowHide(frame)
        if not frame or frame._mmPresetsVisHooked then return end
        if type(frame.HookScript) ~= "function" then return end
        frame._mmPresetsVisHooked = true
        frame:HookScript("OnShow", function() MH.RefreshPresetsUI() end)
        frame:HookScript("OnHide", function() MH.RefreshPresetsUI() end)
    end
    hookShowHide(_G.SendMailFrame)
    hookShowHide(_G.InboxFrame)
    hookShowHide(_G.OpenMailFrame)

    local nameBox = _G.SendMailNameEditBox
    if nameBox and not nameBox._mmPresetsTextHooked and type(nameBox.HookScript) == "function" then
        nameBox._mmPresetsTextHooked = true
        nameBox:HookScript("OnTextChanged", function()
            clearUnsavedConfirm()
            MH.RefreshPresetsUI()
        end)
    end

    for _, tabName in ipairs({ "MailFrameTab1", "MailFrameTab2" }) do
        local tabBtn = _G[tabName]
        if tabBtn and not tabBtn._mmPresetsTabHooked and type(tabBtn.HookScript) == "function" then
            tabBtn._mmPresetsTabHooked = true
            tabBtn:HookScript("OnClick", function() MH.RefreshPresetsUI() end)
        end
    end
end

function MH.InstallSendMailGuard()
    ensureUnsavedConfirmDialog()
    hookBlizzardMailVisibility()

    local btn = _G.SendMailMailButton
    if btn and not btn._mmUnsavedHooked and type(btn.GetScript) == "function" and type(btn.SetScript) == "function" then
        local origOnClick = btn:GetScript("OnClick")
        btn._mmUnsavedHooked = true
        btn._mmOrigOnClick = origOnClick
        state.sendButtonOrigOnClick = origOnClick
        btn:SetScript("OnClick", function(self, mouseBtn, down)
            local intercept, recipient = shouldInterceptUnsavedSend()
            if intercept then
                state.pendingConfirm = { recipient = recipient, button = self }
                if type(_G.StaticPopup_Show) == "function" then
                    _G.StaticPopup_Show(MH.UNSAVED_CONFIRM_POPUP, recipient)
                end
                return
            end
            state.bypassConfirmRecipient = nil
            if type(origOnClick) == "function" then
                return origOnClick(self, mouseBtn, down)
            end
        end)
    end
end

local function attachMailTooltip(widget, getTitle, getLines)
    if not widget or type(widget.SetScript) ~= "function" then return end
    local onEnter = function(self)
        local gt = _G.GameTooltip
        if not gt or type(gt.SetOwner) ~= "function" then return end
        local title = type(getTitle) == "function" and getTitle(self) or getTitle
        if not title or title == "" then return end
        local lines = type(getLines) == "function" and getLines(self) or getLines
        gt:SetOwner(self, "ANCHOR_RIGHT")
        gt:AddLine(title, 1, 0.82, 0)
        for _, ln in ipairs(lines or {}) do
            gt:AddLine(tostring(ln), 0.9, 0.92, 0.96, true)
        end
        gt:Show()
    end
    local onLeave = function()
        if type(_G.GameTooltip_Hide) == "function" then
            _G.GameTooltip_Hide()
        elseif _G.GameTooltip and type(_G.GameTooltip.Hide) == "function" then
            _G.GameTooltip:Hide()
        end
    end
    if type(widget.HookScript) == "function" then
        widget:HookScript("OnEnter", onEnter)
        widget:HookScript("OnLeave", onLeave)
    else
        widget:SetScript("OnEnter", onEnter)
        widget:SetScript("OnLeave", onLeave)
    end
end

local function applyPresetRecipient(charName, focusSubject)
    clearUnsavedConfirm()
    local nameBox = _G.SendMailNameEditBox
    if nameBox and type(nameBox.SetText) == "function" then
        nameBox:SetText(charName or "")
    end
    if type(_G.SendMailFrame_CanSend) == "function" then
        pcall(_G.SendMailFrame_CanSend)
    end
    if focusSubject then
        local subj = _G.SendMailSubjectEditBox
        if subj and type(subj.SetFocus) == "function" then
            pcall(subj.SetFocus, subj)
        end
    end
    MH.RefreshPresetsUI()
end

local function openMailSettingsTab()
    if ns.app and type(ns.app.togglePanel) == "function" then
        ns.app.togglePanel("console_mail")
    elseif ns.UIConsole and type(ns.UIConsole.Show) == "function" then
        ns.UIConsole.Show("console_mail")
    end
end

local function safeShow(w)
    if w and type(w.Show) == "function" then w:Show() end
end

local function safeHide(w)
    if w and type(w.Hide) == "function" then w:Hide() end
end

local function paintSurfaceFallback(surf)
    if not surf then return end
    local p = getPalette()
    if type(surf.UpdateTheme) == "function" then
        surf:UpdateTheme()
        return
    end
    if surf.SetFill and p.cardBg then
        surf:SetFill(p.cardBg[1], p.cardBg[2], p.cardBg[3], p.cardBg[4] or 0.96)
    end
    if surf.SetBorder and p.borderStrong then
        surf:SetBorder(p.borderStrong[1], p.borderStrong[2], p.borderStrong[3], p.borderStrong[4] or 0.22)
    end
    if surf.SetColors and p.cardBg and p.borderStrong then
        surf:SetColors(p.cardBg, p.borderStrong)
    end
end

local function measurePillTextWidth(label, text)
    if label then
        if type(label.GetUnboundedStringWidth) == "function" then
            local w = tonumber(label:GetUnboundedStringWidth())
            if w and w > 0 then return w end
        end
        if type(label.GetStringWidth) == "function" then
            local w = tonumber(label:GetStringWidth())
            if w and w > 0 then
                return math.max(w, #(tostring(text or "")) * 5.8)
            end
        end
    end
    return #(tostring(text or "")) * 5.8
end

local function clampPillText(label, rawText, maxInnerPx)
    local s = tostring(rawText or "")
    local limit = tonumber(maxInnerPx) or (MH.STATUS_PILL_MAX_WIDTH - 20)
    if label and type(label.SetText) == "function" then
        label:SetText(s)
    end
    if measurePillTextWidth(label, s) <= limit then
        return s
    end
    local len = #s
    while len > 4 do
        len = len - 1
        local base = s:sub(1, len):gsub("[%s/%-%(%,]+$", "")
        local candidate = base .. "..."
        if label and type(label.SetText) == "function" then
            label:SetText(candidate)
        end
        if measurePillTextWidth(label, candidate) <= limit then
            return candidate
        end
    end
    return "..."
end

local function clampStatusPillBounds(statusPill)
    if not statusPill then return end
    if statusPill.frame then
        if statusPill.frame.ClearAllPoints then statusPill.frame:ClearAllPoints() end
        local parent = statusPill.frame.GetParent and statusPill.frame:GetParent() or statusPill._parent
        if parent then
            statusPill.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -28)
            statusPill.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -28)
        end
        if statusPill.frame.SetWidth then
            statusPill.frame:SetWidth(MH.STATUS_PILL_MAX_WIDTH)
        end
    end
    if statusPill.label and statusPill.frame then
        if statusPill.label.ClearAllPoints then statusPill.label:ClearAllPoints() end
        statusPill.label:SetPoint("LEFT", statusPill.frame, "LEFT", 10, 0)
        statusPill.label:SetPoint("RIGHT", statusPill.frame, "RIGHT", -10, 0)
        if statusPill.label.SetJustifyH then statusPill.label:SetJustifyH("CENTER") end
        if statusPill.label.SetWordWrap then statusPill.label:SetWordWrap(false) end
        if statusPill.label.SetMaxLines then statusPill.label:SetMaxLines(1) end
    end
end

local function createPresetsPanel(mf)
    local panel = _G.CreateFrame("Frame", "MerchantMasterMailPresetsPanel", mf)
    panel:SetWidth(MH.DOCK_PANEL_WIDTH)
    panel:SetHeight(120)
    panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
    panel:Hide()

    local theme = ns.Theme
    if theme and type(theme.NineApple) == "function" then
        panel._bgSurf = theme.NineApple(panel, "glass_r12", "cardBg", "borderStrong", { noSpecular = true })
    end

    local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
    titleFs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, -9)
    if titleFs.SetJustifyH then titleFs:SetJustifyH("LEFT") end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(titleFs, 12, "semibold")
    end
    titleFs:SetText("Mail Recipients")
    panel.titleFs = titleFs

    local gearBtn
    if theme and type(theme.CreatePlateButton) == "function" then
        gearBtn = theme.CreatePlateButton(panel, "", 20, 20, {
            icon = (theme.ASSETS and theme.ASSETS.icon_settings) or nil,
            iconSize = 12,
            variant = "ghost",
            pill = true,
        })
        if not (theme.ASSETS and theme.ASSETS.icon_settings) and gearBtn.fs then
            gearBtn.fs:SetText("*")
        end
    else
        gearBtn = makeBarButton(panel, "Cfg", 28, 20, "secondary", openMailSettingsTab)
    end
    gearBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
    gearBtn:SetScript("OnClick", openMailSettingsTab)
    attachMailTooltip(gearBtn, "Mail Recipients & Safety", {
        "Open Console -> Mail to edit saved recipients, display options, and the unsaved-recipient popup.",
    })
    panel.settingsBtn = gearBtn

    local statusPill
    if theme and type(theme.CreateBadgePill) == "function" then
        statusPill = theme.CreateBadgePill(panel, "Pick a saved recipient", "neutral", {
            height = 20,
            fontSize = 10,
            padX = 10,
            minWidth = MH.STATUS_PILL_MAX_WIDTH,
        })
        statusPill._parent = panel
        clampStatusPillBounds(statusPill)
    end
    panel.statusPill = statusPill

    local statusFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -30)
    statusFs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -30)
    statusFs:SetHeight(16)
    if statusFs.SetJustifyH then statusFs:SetJustifyH("LEFT") end
    if statusFs.SetWordWrap then statusFs:SetWordWrap(false) end
    if statusFs.SetMaxLines then statusFs:SetMaxLines(1) end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(statusFs, 10, "semibold")
    end
    if statusPill then safeHide(statusFs) end
    panel.statusFs = statusFs

    panel.buttons = {}
    local rowW = MH.DOCK_PANEL_WIDTH - 16
    for i = 1, MH.PRESET_PAGE_SIZE do
        local b = _G.CreateFrame("Button", nil, panel)
        b:SetHeight(32)
        if b.SetWidth then b:SetWidth(rowW) end
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(52 + (i - 1) * 35))
        b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -(52 + (i - 1) * 35))
        if theme and type(theme.NineApple) == "function" then
            b._bgSurf = theme.NineApple(b, "glass_r8", "cardAltBg", "border", { noSpecular = true })
        end
        local bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        if bg.SetAllPoints then bg:SetAllPoints(b) else bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) end
        bg:SetColorTexture(0, 0, 0, 0)
        b.bg = bg

        local iconTex = b:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(18, 18)
        iconTex:SetPoint("LEFT", b, "LEFT", 8, 0)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.iconTex = iconTex

        local nameFs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if nameFs.SetJustifyH then nameFs:SetJustifyH("LEFT") end
        if nameFs.SetWordWrap then nameFs:SetWordWrap(false) end
        if nameFs.SetMaxLines then nameFs:SetMaxLines(1) end
        if theme and type(theme.ApplyFont) == "function" then
            theme.ApplyFont(nameFs, 11, "semibold")
        end
        b.nameFs = nameFs

        local roleFs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if roleFs.SetJustifyH then roleFs:SetJustifyH("LEFT") end
        if roleFs.SetWordWrap then roleFs:SetWordWrap(false) end
        if roleFs.SetMaxLines then roleFs:SetMaxLines(1) end
        if theme and type(theme.ApplyFont) == "function" then
            theme.ApplyFont(roleFs, 10, "regular")
        end
        b.roleFs = roleFs

        local initFs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        initFs:SetPoint("CENTER", b, "CENTER", 0, 0)
        if initFs.SetJustifyH then initFs:SetJustifyH("CENTER") end
        if theme and type(theme.ApplyFont) == "function" then
            theme.ApplyFont(initFs, 12, "semibold")
        end
        safeHide(initFs)
        b.initFs = initFs

        local selfTag = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        selfTag:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        if selfTag.SetJustifyH then selfTag:SetJustifyH("RIGHT") end
        if theme and type(theme.ApplyFont) == "function" then
            theme.ApplyFont(selfTag, 10, "regular")
        end
        selfTag:SetText("You")
        safeHide(selfTag)
        b.selfTag = selfTag

        b:SetScript("OnClick", function(self)
            local e = self._entry
            if not e or not e.name then return end
            local sendShown = (_G.SendMailFrame and _G.SendMailFrame.IsShown and _G.SendMailFrame:IsShown()) == true
            if not sendShown then
                local tab2 = _G.MailFrameTab2
                if tab2 and type(tab2.Click) == "function" then
                    pcall(tab2.Click, tab2)
                elseif type(_G.MailFrameTab_OnClick) == "function" then
                    pcall(_G.MailFrameTab_OnClick, tab2, 2)
                end
                applyPresetRecipient(e.name, true)
            else
                applyPresetRecipient(e.name, false)
            end
        end)
        attachMailTooltip(b,
            function(self) return self._entry and self._entry.name or "" end,
            function(self)
                local e = self._entry
                if not e then return {} end
                local lines = { "Roles: " .. tostring(e.allRolesText or e.roleLabel or "") }
                if e.isSelf then
                    lines[#lines + 1] = "Current character (You)"
                elseif not (_G.SendMailFrame and _G.SendMailFrame.IsShown and _G.SendMailFrame:IsShown()) then
                    lines[#lines + 1] = "Click to switch to Send Mail and fill this recipient."
                else
                    lines[#lines + 1] = "Click to fill Send Mail recipient."
                end
                return lines
            end)
        b:Hide()
        panel.buttons[i] = b
    end

    local prevBtn = makeBarButton(panel, "<", 26, 20, "secondary", function()
        state.presetPage = math.max(1, (state.presetPage or 1) - 1)
        MH.RefreshPresetsUI()
    end)
    prevBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 8)
    prevBtn:Hide()
    panel.prevBtn = prevBtn

    local nextBtn = makeBarButton(panel, ">", 26, 20, "secondary", function()
        state.presetPage = (state.presetPage or 1) + 1
        MH.RefreshPresetsUI()
    end)
    nextBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    nextBtn:Hide()
    panel.nextBtn = nextBtn

    local pageFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageFs:SetPoint("CENTER", panel, "BOTTOM", 0, 18)
    if pageFs.SetJustifyH then pageFs:SetJustifyH("CENTER") end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(pageFs, 10, "regular")
    end
    safeHide(pageFs)
    panel.pageFs = pageFs

    local function paintPanel()
        paintSurfaceFallback(panel._bgSurf)
        local p = getPalette()
        if titleFs.SetTextColor and p.text then
            titleFs:SetTextColor(p.text[1], p.text[2], p.text[3], p.text[4] or 1)
        end
        if pageFs.SetTextColor and p.textMuted then
            pageFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3], p.textMuted[4] or 1)
        end
        MH.RefreshPresetsUI()
    end
    if theme and type(theme.RegisterWidget) == "function" then
        theme.RegisterWidget(panel, paintPanel)
    end
    return panel
end

local function createInboxQuickStrip(inboxFrame)
    local strip = _G.CreateFrame("Frame", "MerchantMasterInboxQuickStrip", inboxFrame)
    strip:SetHeight(24)
    strip:SetWidth(30)
    strip:SetPoint("TOPRIGHT", inboxFrame, "TOPRIGHT", -14, -26)
    strip:Hide()

    local theme = ns.Theme
    if theme and type(theme.NineApple) == "function" then
        strip._bgSurf = theme.NineApple(strip, "pill", "cardBg", "borderStrong", { noSpecular = true })
    end

    strip.buttons = {}
    for i = 1, 6 do
        local b = _G.CreateFrame("Button", nil, strip)
        b:SetSize(18, 18)
        b:SetPoint("LEFT", strip, "LEFT", 5 + (i - 1) * 21, 0)
        local tex = b:CreateTexture(nil, "ARTWORK")
        if tex.SetAllPoints then tex:SetAllPoints(b) else tex:SetSize(18, 18); tex:SetPoint("CENTER", 0, 0) end
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.iconTex = tex
        b:SetScript("OnClick", function(self)
            local e = self._entry
            if not e then return end
            local tab2 = _G.MailFrameTab2
            if tab2 and type(tab2.Click) == "function" then
                pcall(tab2.Click, tab2)
            elseif type(_G.MailFrameTab_OnClick) == "function" then
                pcall(_G.MailFrameTab_OnClick, tab2, 2)
            end
            applyPresetRecipient(e.name, true)
        end)
        attachMailTooltip(b,
            function(self) return self._entry and self._entry.name or "" end,
            function(self)
                local e = self._entry
                if not e then return {} end
                return {
                    "Roles: " .. tostring(e.allRolesText or e.roleLabel or ""),
                    "Click to switch to Send Mail and fill this recipient.",
                }
            end)
        b:Hide()
        strip.buttons[i] = b
    end

    local function paintStrip()
        paintSurfaceFallback(strip._bgSurf)
    end
    if theme and type(theme.RegisterWidget) == "function" then
        theme.RegisterWidget(strip, paintStrip)
    end
    return strip
end

function MH.MountPresetPanels()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        state.pendingMount = true
        return false, "combat"
    end
    if type(_G.CreateFrame) ~= "function" then
        return false, "no_create_frame"
    end
    local mf = _G.MailFrame
    if mf and not MH.presetsPanel then
        MH.presetsPanel = createPresetsPanel(mf)
    end
    local inbox = _G.InboxFrame
    if inbox and not MH.inboxQuickStrip then
        MH.inboxQuickStrip = createInboxQuickStrip(inbox)
    end
    hookBlizzardMailVisibility()
    return true
end

function MH.RefreshPresetsUI()
    local entries = MH.BuildPresetRecipientEntries()
    local disp = MH.GetDisplayOptions()
    local pal = getPalette()
    local mf = _G.MailFrame
    local mailFrameVisible = (mf == nil) or (not mf.IsShown) or (mf:IsShown() == true)
    local openMailShown = (_G.OpenMailFrame and _G.OpenMailFrame.IsShown and _G.OpenMailFrame:IsShown()) == true
    local sendMailShown = (_G.SendMailFrame and _G.SendMailFrame.IsShown and _G.SendMailFrame:IsShown()) == true
    local inboxShown = (_G.InboxFrame and _G.InboxFrame.IsShown and _G.InboxFrame:IsShown()) == true
    local effectiveInboxShown = inboxShown
        or (state.mailOpen and mailFrameVisible and _G.InboxFrame == nil and _G.SendMailFrame == nil)

    local dockMode = "hidden"
    if (not openMailShown) and mailFrameVisible then
        if sendMailShown then
            dockMode = "send"
        elseif effectiveInboxShown then
            dockMode = "inbox"
        end
    end

    local rawRecipient = (_G.SendMailNameEditBox and _G.SendMailNameEditBox.GetText and _G.SendMailNameEditBox:GetText()) or ""
    local curTrim = trimOuter(rawRecipient)
    local curKey = canonicalKey(curTrim)

    -- 1. Mail Recipients Preset Panel (280px wide, right-side docked)
    local panel = MH.presetsPanel
    local bar = MH.bar
    local hasEntries = (#entries > 0)
    local showPanel = (dockMode == "send" or dockMode == "inbox") and hasEntries

    if panel then
        if not showPanel then
            panel:Hide()
        else
            -- Status pill (strictly clamped to 260px inside 280px panel)
            local isSaved, savedEntry = MH.IsSavedMailRecipient(curTrim)
            local statusText, statusVariant, statusHex
            if curTrim == "" then
                statusText = "Pick a saved recipient"
                statusVariant = "neutral"
                statusHex = "hexMuted"
            elseif isSaved and savedEntry then
                statusText = "Saved: " .. tostring(savedEntry.roleLabel or savedEntry.name)
                statusVariant = "green"
                statusHex = "hexPositive"
            else
                statusText = "Unsaved recipient"
                statusVariant = "orange"
                statusHex = "hexWarning"
            end
            local clampedStatusText = clampPillText(panel.statusPill and panel.statusPill.label or panel.statusFs, statusText, MH.STATUS_PILL_MAX_WIDTH - 20)
            if panel.statusPill and panel.statusPill.SetVariant then
                panel.statusPill:SetVariant(statusVariant, clampedStatusText)
                clampStatusPillBounds(panel.statusPill)
            end
            if panel.statusFs and panel.statusFs.SetText then
                panel.statusFs:SetText(palHex(statusHex, "98989d") .. clampedStatusText .. "|r")
            end

            -- Pagination
            local total = #entries
            local pageSize = MH.PRESET_PAGE_SIZE
            local totalPages = math.max(1, math.ceil(total / pageSize))
            state.presetPage = math.max(1, math.min(totalPages, tonumber(state.presetPage) or 1))
            local startIdx = (state.presetPage - 1) * pageSize + 1
            local visibleCount = 0

            local showIcon = disp.showIcon == true
            local showName = disp.showName == true
            local showRole = disp.showRole == true
            local initialsOnly = (not showIcon) and (not showName) and (not showRole)

            for i = 1, pageSize do
                local btn = panel.buttons[i]
                local entry = entries[startIdx + i - 1]
                btn._entry = entry
                if entry then
                    visibleCount = visibleCount + 1
                    btn:Show()
                    local isActive = (curKey ~= "" and curKey == entry.key)
                    if btn._bgSurf and btn._bgSurf.UpdateTheme then
                        btn._bgSurf:UpdateTheme()
                    end
                    if btn.bg and btn.bg.SetColorTexture then
                        if isActive then
                            local ab = pal.accentBlue or { 0.2, 0.58, 1.0, 1.0 }
                            btn.bg:SetColorTexture(ab[1], ab[2], ab[3], 0.24)
                        elseif entry.isSelf then
                            btn.bg:SetColorTexture(0.5, 0.5, 0.5, 0.08)
                        else
                            btn.bg:SetColorTexture(0, 0, 0, 0)
                        end
                    end

                    local rightPad = entry.isSelf and -34 or -8
                    if btn.selfTag then
                        if entry.isSelf and not initialsOnly then
                            safeShow(btn.selfTag)
                            if btn.selfTag.SetTextColor and pal.textMuted then
                                btn.selfTag:SetTextColor(pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.85)
                            end
                        else
                            safeHide(btn.selfTag)
                        end
                    end

                    if initialsOnly then
                        safeHide(btn.iconTex)
                        safeHide(btn.nameFs)
                        safeHide(btn.roleFs)
                        safeShow(btn.initFs)
                        btn.initFs:SetText(entry.initials or "??")
                        if btn.initFs.SetTextColor then
                            local tc = entry.isSelf and (pal.textMuted or { 0.65, 0.65, 0.68, 1 }) or (pal.text or { 1, 1, 1, 1 })
                            btn.initFs:SetTextColor(tc[1], tc[2], tc[3], entry.isSelf and 0.7 or (tc[4] or 1))
                        end
                    else
                        safeHide(btn.initFs)
                        local textLeft = 8
                        if showIcon then
                            safeShow(btn.iconTex)
                            btn.iconTex:SetTexture(entry.icon)
                            if btn.iconTex.SetAlpha then
                                btn.iconTex:SetAlpha(entry.isSelf and 0.65 or 1.0)
                            end
                            textLeft = 30
                        else
                            safeHide(btn.iconTex)
                        end

                        if showName then
                            safeShow(btn.nameFs)
                            if btn.nameFs.ClearAllPoints then btn.nameFs:ClearAllPoints() end
                            if showRole then
                                btn.nameFs:SetPoint("TOPLEFT", btn, "TOPLEFT", textLeft, -4)
                                btn.nameFs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", rightPad, -4)
                            else
                                btn.nameFs:SetPoint("LEFT", btn, "LEFT", textLeft, 0)
                                btn.nameFs:SetPoint("RIGHT", btn, "RIGHT", rightPad, 0)
                            end
                            btn.nameFs:SetText(entry.name)
                            if btn.nameFs.SetTextColor then
                                local tc = entry.isSelf and (pal.textMuted or { 0.68, 0.68, 0.70, 1 }) or (pal.text or { 1, 1, 1, 1 })
                                btn.nameFs:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
                            end
                        else
                            safeHide(btn.nameFs)
                        end

                        if showRole then
                            safeShow(btn.roleFs)
                            if btn.roleFs.ClearAllPoints then btn.roleFs:ClearAllPoints() end
                            if showName then
                                btn.roleFs:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", textLeft, 4)
                                btn.roleFs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", rightPad, 4)
                            else
                                btn.roleFs:SetPoint("LEFT", btn, "LEFT", textLeft, 0)
                                btn.roleFs:SetPoint("RIGHT", btn, "RIGHT", rightPad, 0)
                            end
                            btn.roleFs:SetText(entry.roleLabel)
                            if btn.roleFs.SetTextColor then
                                local rc = pal.textMuted or pal.textSecondary or { 0.7, 0.7, 0.72, 1 }
                                btn.roleFs:SetTextColor(rc[1], rc[2], rc[3], rc[4] or 1)
                            end
                        else
                            safeHide(btn.roleFs)
                        end
                    end
                else
                    btn:Hide()
                end
            end

            local hasPager = totalPages > 1
            if panel.prevBtn then
                if hasPager then
                    panel.prevBtn:Show()
                    if panel.prevBtn.SetEnabled then panel.prevBtn:SetEnabled(state.presetPage > 1) end
                else
                    panel.prevBtn:Hide()
                end
            end
            if panel.nextBtn then
                if hasPager then
                    panel.nextBtn:Show()
                    if panel.nextBtn.SetEnabled then panel.nextBtn:SetEnabled(state.presetPage < totalPages) end
                else
                    panel.nextBtn:Hide()
                end
            end
            if panel.pageFs then
                if hasPager then
                    safeShow(panel.pageFs)
                    panel.pageFs:SetText(string.format("%d / %d", state.presetPage, totalPages))
                else
                    safeHide(panel.pageFs)
                end
            end

            local footerH = hasPager and 32 or 8
            panel:SetHeight(52 + visibleCount * 35 + footerH)
        end
    end

    -- 2. Unified Right-Side Vertical Stacking (Zero Bottom Attachment, Auto-Hide on Read Mail)
    if dockMode == "hidden" then
        safeHide(bar)
        safeHide(panel)
    elseif dockMode == "send" then
        if showPanel and panel and mf then
            if panel.ClearAllPoints then panel:ClearAllPoints() end
            panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
            panel:Show()
            if bar then
                if bar.ClearAllPoints then bar:ClearAllPoints() end
                bar:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -MH.DOCK_GAP_Y)
                bar:Show()
            end
        else
            safeHide(panel)
            if bar and mf then
                if bar.ClearAllPoints then bar:ClearAllPoints() end
                bar:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
                bar:Show()
            end
        end
    elseif dockMode == "inbox" then
        if bar and mf then
            if bar.ClearAllPoints then bar:ClearAllPoints() end
            bar:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
            bar:Show()
        end
        if showPanel and panel then
            if panel.ClearAllPoints then panel:ClearAllPoints() end
            if bar then
                panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -MH.DOCK_GAP_Y)
            elseif mf then
                panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
            end
            panel:Show()
        else
            safeHide(panel)
        end
    end

    -- 3. Keep legacy Inbox quick strip hidden (presets panel now stacks cleanly on the right)
    local strip = MH.inboxQuickStrip
    if strip and strip.Hide then
        strip:Hide()
    end

    return entries, disp
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
        MH.MountPresetPanels()
        MH.InstallSendMailGuard()
        MH.UpdateUI()
        MH.RefreshPresetsUI()
        return true, MH.bar
    end

    local bar = _G.CreateFrame("Frame", "MerchantMasterMailHelperBar", mf)
    bar:SetSize(MH.DOCK_PANEL_WIDTH, MH.HELPER_PANEL_HEIGHT)
    bar:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)

    local theme = ns.Theme
    if theme and type(theme.NineApple) == "function" then
        bar._bgSurf = theme.NineApple(bar, "glass_r12", "cardBg", "borderStrong", { noSpecular = true })
    end

    local titleFs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", bar, "TOPLEFT", 10, -10)
    titleFs:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -10, -10)
    if titleFs.SetJustifyH then titleFs:SetJustifyH("LEFT") end
    if titleFs.SetWordWrap then titleFs:SetWordWrap(false) end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(titleFs, 12, "semibold")
    end
    titleFs:SetText("Mail Helper")
    bar.titleFs = titleFs

    local function paintBar()
        paintSurfaceFallback(bar._bgSurf)
        local p = getPalette()
        if titleFs.SetTextColor and p.text then
            titleFs:SetTextColor(p.text[1], p.text[2], p.text[3], p.text[4] or 1)
        end
        MH.UpdateUI()
    end

    if theme and type(theme.RegisterWidget) == "function" then
        theme.RegisterWidget(bar, paintBar)
    end

    -- 2x2 grid of 128x24 action buttons inside 280px right-side panel (10 + 128 + 4 + 128 + 10 = 280).
    local padX, gapX, gapY = 10, 4, 6
    local btnW, btnH = 128, 24
    local gridTopY = -32
    local modeDefs = {
        { mode = "all",        label = "Open All", variant = "primary",   col = 0, row = 0 },
        { mode = "ah_sales",   label = "AH Sales", variant = "secondary", col = 1, row = 0 },
        { mode = "ah_expired", label = "Expired",  variant = "secondary", col = 0, row = 1 },
        { mode = "ah_won",     label = "Won",      variant = "secondary", col = 1, row = 1 },
    }
    bar.modeBtns = {}
    for idx, def in ipairs(modeDefs) do
        local m = def.mode
        local b = makeBarButton(bar, def.label, btnW, btnH, def.variant, function()
            if state.active and state.clickStepper and state.mode == m then
                MH.Step()
            else
                MH.Start(m)
            end
        end)
        local xOff = padX + def.col * (btnW + gapX)
        local yOff = gridTopY - def.row * (btnH + gapY)
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", xOff, yOff)
        bar.modeBtns[idx] = { mode = m, btn = b }
    end

    -- Bottom row (y = -92, height 22px): status FontString (left, ~138px) + Refresh (64px) + Stop (50px).
    local bottomY = -92
    local stopBtn = makeBarButton(bar, "Stop", 50, 22, "secondary", function()
        MH.Stop("user_stop")
    end)
    stopBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -padX, bottomY)
    if stopBtn.SetEnabled then stopBtn:SetEnabled(false) end
    bar.stopBtn = stopBtn

    local refreshBtn = makeBarButton(bar, "Refresh", 64, 22, "secondary", function()
        if state.active and state.clickStepper then
            MH.Step()
        else
            MH.RequestRefresh()
        end
    end)
    refreshBtn:SetPoint("RIGHT", stopBtn, "LEFT", -4, 0)
    bar.refreshBtn = refreshBtn

    local statusFs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("TOPLEFT", bar, "TOPLEFT", padX, bottomY)
    statusFs:SetPoint("BOTTOMRIGHT", refreshBtn, "BOTTOMLEFT", -4, 0)
    statusFs:SetHeight(22)
    if statusFs.SetJustifyH then statusFs:SetJustifyH("LEFT") end
    if statusFs.SetJustifyV then statusFs:SetJustifyV("MIDDLE") end
    if statusFs.SetWordWrap then statusFs:SetWordWrap(false) end
    if statusFs.SetMaxLines then statusFs:SetMaxLines(1) end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(statusFs, 11, "regular")
    end
    bar.statusFs = statusFs

    MH.bar = bar
    paintBar()
    MH.MountPresetPanels()
    MH.InstallSendMailGuard()
    MH.RefreshPresetsUI()
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
        MH.RefreshPresetsUI()
    elseif event == "MAIL_CLOSED" then
        state.mailOpen = false
        clearUnsavedConfirm()
        if state.active then
            MH.Stop("mail_closed")
        end
        if MH.bar and MH.bar.Hide then MH.bar:Hide() end
        if MH.presetsPanel and MH.presetsPanel.Hide then MH.presetsPanel:Hide() end
        if MH.inboxQuickStrip and MH.inboxQuickStrip.Hide then MH.inboxQuickStrip:Hide() end
    elseif event == "MAIL_SEND_INFO_UPDATE" or event == "MAIL_FAILED" or event == "MAIL_SEND_SUCCESS" then
        clearUnsavedConfirm()
        MH.RefreshPresetsUI()
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
        MH.RefreshPresetsUI()
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
    for _, ev in ipairs({
        "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
        "MAIL_SEND_INFO_UPDATE", "MAIL_FAILED", "MAIL_SEND_SUCCESS",
        "ADDON_ACTION_BLOCKED", "PLAYER_REGEN_ENABLED",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end
end
