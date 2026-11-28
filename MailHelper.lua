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

local function trimOuter(raw)
    if hasSecret(raw) or type(raw) ~= "string" then return "" end
    return (raw:match("^%s*(.-)%s*$")) or ""
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
    lastAttTake = nil,
    slotRetries = {},
    seenCOD = {},
    seenBlocked = {},
    lootedCount = 0,
    lootedCopper = 0,
    fetchedUnits = 0,
    targetMailID = nil,
    targetMailSig = nil,
    openMailFinished = false,
    targetItemID = nil,
    targetItemName = nil,
    targetTotalUnits = 0,
    targetMaxStacks = nil,
    skippedCOD = 0,
    skippedBlocked = 0,
    skippedBagsFull = false,
    statusText = "Ready",
    statusKind = "muted",
    lastCheckInboxAt = 0,
    refreshPending = false,
    refreshSerial = 0,
    presetPage = 1,
    itemCategory = "all",
    itemPage = 1,
    pendingConfirm = nil,
    bypassConfirmRecipient = nil,
    scanCursor = nil,
    lastScanNumItems = nil,
    hadUnloadedAboveCursor = false,
}

MH.ITEM_CATEGORIES = {
    { key = "all",        label = "All" },
    { key = "mats",       label = "Mats" },
    { key = "gear",       label = "Gear" },
    { key = "consumable", label = "Cons" },
    { key = "other",      label = "Other" },
}
MH.ITEM_PICKER_PAGE_SIZE = 6

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 },
    [1] = { 1.00, 1.00, 1.00 },
    [2] = { 0.12, 1.00, 0.00 },
    [3] = { 0.00, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 },
    [5] = { 1.00, 0.50, 0.00 },
}

local function maxAttachmentsReceive()
    local n = tonumber(_G.ATTACHMENTS_MAX_RECEIVE)
    return (n and n > 0) and math.floor(n) or 12
end

local function readInboxAttachment(mailIdx, attachIdx)
    if type(_G.GetInboxItem) ~= "function" then return nil end
    local ok, aName, a2, a3, a4, a5, a6 = pcall(_G.GetInboxItem, mailIdx, attachIdx)
    if not ok or hasSecret(aName, a2, a3, a4, a5, a6) or type(aName) ~= "string" or aName == "" then
        return nil
    end
    local link, linkID = nil, nil
    if type(_G.GetInboxItemLink) == "function" then
        local okL, rawL = pcall(_G.GetInboxItemLink, mailIdx, attachIdx)
        if okL and not hasSecret(rawL) and type(rawL) == "string" and rawL ~= "" then
            link = rawL
            linkID = tonumber(rawL:match("item:(%d+)"))
        end
    end
    local itemID, icon, count, quality
    if linkID then
        itemID = linkID
        if tonumber(a2) == linkID then
            icon = a3
            count = tonumber(a4) or 1
            quality = tonumber(a5)
        else
            icon = a2
            count = tonumber(a3) or 1
            quality = tonumber(a4)
        end
    elseif a6 ~= nil then
        itemID = tonumber(a2)
        icon = a3
        count = tonumber(a4) or 1
        quality = tonumber(a5)
    elseif type(a2) == "number" and (type(a4) == "number" or (type(a3) == "string" and a3 ~= "")) and type(a5) == "number" then
        itemID = a2
        icon = a3
        count = tonumber(a4) or 1
        quality = tonumber(a5)
    else
        icon = a2
        count = tonumber(a3) or tonumber(a4) or 1
        quality = tonumber(a4) or tonumber(a5)
        if type(a2) == "number" and a2 > 0 and type(a3) ~= "number" and type(a4) == "number" then
            itemID = a2
            icon = a3
            count = tonumber(a4) or 1
            quality = tonumber(a5)
        end
    end
    if not itemID or not icon then
        local instFn = (_G.C_Item and _G.C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
        if type(instFn) == "function" then
            local okI, instID, _, _, _, instIcon = pcall(instFn, link or itemID or aName)
            if okI and not hasSecret(instID, instIcon) then
                if not itemID and tonumber(instID) then itemID = tonumber(instID) end
                if not icon and instIcon then icon = instIcon end
            end
        end
    end
    count = math.max(1, math.floor(tonumber(count) or 1))
    return {
        name = aName,
        itemID = (itemID and tonumber(itemID) and tonumber(itemID) > 0) and math.floor(tonumber(itemID)) or nil,
        icon = icon or 134400,
        count = count,
        quality = quality or 1,
        link = link,
    }
end

local function classifyItemCategory(itemID, itemLink, fallbackName)
    local classID = nil
    local instFn = (_G.C_Item and _G.C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if type(instFn) == "function" then
        local ok, _, _, _, _, _, cid = pcall(instFn, itemLink or itemID or fallbackName)
        if ok and not hasSecret(cid) and tonumber(cid) ~= nil then
            classID = tonumber(cid)
        end
    end
    if classID == nil then
        local infoFn = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
        if type(infoFn) == "function" then
            local ok2, _, _, _, _, _, _, _, _, _, _, _, cid2 = pcall(infoFn, itemLink or itemID or fallbackName)
            if ok2 and not hasSecret(cid2) and tonumber(cid2) ~= nil then
                classID = tonumber(cid2)
            end
        end
    end
    if classID == 7 then return "mats" end
    if classID == 2 or classID == 4 then return "gear" end
    if classID == 0 then return "consumable" end
    return "other"
end

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
        fetchedUnits = state.fetchedUnits,
        targetMailID = state.targetMailID,
        targetItemID = state.targetItemID,
        targetItemName = state.targetItemName,
        itemCategory = state.itemCategory,
        itemPage = state.itemPage,
        skippedCOD = state.skippedCOD,
        skippedBlocked = state.skippedBlocked,
        skippedBagsFull = state.skippedBagsFull,
        statusText = state.statusText,
        refreshPending = state.refreshPending == true,
        lastCheckInboxAt = state.lastCheckInboxAt,
        presetPage = state.presetPage,
        barShown = (MH.bar ~= nil and MH.bar.IsShown and MH.bar:IsShown()) == true,
        presetsPanelShown = (MH.presetsPanel ~= nil and MH.presetsPanel.IsShown and MH.presetsPanel:IsShown()) == true,
        itemPickerShown = (MH.itemPickerPanel ~= nil and MH.itemPickerPanel.IsShown and MH.itemPickerPanel:IsShown()) == true,
        openMailBtnShown = (MH.openMailBtn ~= nil and MH.openMailBtn.IsShown and MH.openMailBtn:IsShown()) == true,
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
    local itemCountExact = (type(hasItem) == "number" and hasItem >= 0) and math.floor(hasItem) or nil
    local moneyAmt = tonumber(money) or 0
    local info = {
        index = index,
        sender = sender,
        subject = subject,
        money = moneyAmt,
        codAmount = 0,
        itemCount = itemCount,
        itemCountExact = itemCountExact,
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
    if reason == "mail_changed" then
        return "Mail changed - stopped", "warning"
    end
    if reason == "user_stop" then
        if state.mode == "item_type" and (state.fetchedUnits or 0) > 0 then
            return string.format("Stopped (%dx %s)", state.fetchedUnits, tostring(state.targetItemName or "item")), "warning"
        elseif state.mode == "gold_only" and (state.lootedCopper or 0) > 0 then
            return string.format("Stopped (%s)", formatCopperSimple(state.lootedCopper)), "warning"
        end
        return string.format("Stopped (%d looted)", state.lootedCount), "warning"
    end
    local parts = {}
    if state.mode == "item_type" then
        if (state.fetchedUnits or 0) > 0 then
            if state.targetMaxStacks == 1 then
                parts[#parts + 1] = string.format("Took 1 stack: %dx %s", state.fetchedUnits, tostring(state.targetItemName or "item"))
            else
                parts[#parts + 1] = string.format("Fetched %dx %s", state.fetchedUnits, tostring(state.targetItemName or "item"))
            end
        else
            parts[#parts + 1] = "No matching items"
        end
    elseif state.mode == "gold_only" then
        if (state.lootedCopper or 0) > 0 then
            if state.lootedCount == 1 then
                parts[#parts + 1] = string.format("Collected %s", formatCopperSimple(state.lootedCopper))
            else
                parts[#parts + 1] = string.format("Collected %s (%d mails)", formatCopperSimple(state.lootedCopper), state.lootedCount)
            end
        else
            parts[#parts + 1] = "No gold to collect"
        end
    elseif state.mode == "open_mail" then
        if state.lootedCount > 0 then
            parts[#parts + 1] = string.format("Looted %d stack%s (%dx)", state.lootedCount, state.lootedCount == 1 and "" or "s", state.fetchedUnits or state.lootedCount)
        else
            parts[#parts + 1] = "No items to loot"
        end
    elseif state.lootedCount > 0 then
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
        pcall(app.QueueMailboxScan, "settled")
        return
    end
    local cap = ns.Analytics and ns.Analytics.Capture
    if cap and type(cap.ScanMailboxSnapshot) == "function" then
        local ok, snap = pcall(cap.ScanMailboxSnapshot, true)
        if ok and type(snap) == "table" then
            if app and type(app.CommitMailboxSnapshot) == "function" then
                pcall(app.CommitMailboxSnapshot, snap)
            elseif ns.Analytics and ns.Analytics.Inventory and type(ns.Analytics.Inventory.AcceptMailboxSnapshot) == "function" then
                pcall(ns.Analytics.Inventory.AcceptMailboxSnapshot, snap)
            end
        end
    end
end

local function armStepWatchdog(stepSerial)
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
end

local function matchesItemTarget(att)
    if not att then return false end
    if state.targetItemID and att.itemID then
        return att.itemID == state.targetItemID
    end
    if state.targetItemName and att.name then
        return string.lower(att.name) == string.lower(state.targetItemName)
    end
    return false
end

local function reconcileLastAttTake(numItems)
    local prev = state.lastAttTake
    if not prev then return end
    state.lastAttTake = nil
    local unchanged = false
    if numItems == prev.numItems and prev.mailIdx >= 1 and prev.mailIdx <= numItems then
        local curAtt = readInboxAttachment(prev.mailIdx, prev.attachIdx)
        if curAtt and curAtt.count == prev.count
            and ((prev.itemID and curAtt.itemID == prev.itemID) or curAtt.name == prev.name) then
            unchanged = true
        end
    end
    if unchanged then
        state.slotRetries[prev.instKey] = (state.slotRetries[prev.instKey] or 0) + 1
        state.lootedCount = math.max(0, state.lootedCount - 1)
        state.fetchedUnits = math.max(0, (state.fetchedUnits or 0) - (prev.count or 0))
    else
        state.slotRetries[prev.instKey] = nil
        if prev.mode == "open_mail" and numItems < (prev.numItems or 0) then
            state.openMailFinished = true
        end
    end
end

local function syncItemPickerRowButtons()
    local picker = MH.itemPickerPanel
    if not (picker and picker.rows) then return end
    local isAllFetch = (state.active == true and state.mode == "item_type" and state.targetMaxStacks == nil)
    local isGoldFetch = (state.active == true and state.mode == "gold_only" and state.targetMaxStacks == nil)
    for _, row in ipairs(picker.rows) do
        local btn = row and row.getAllBtn
        local grp = row and row._group
        if btn then
            local match = false
            if grp then
                if grp.isGold then
                    match = isGoldFetch
                elseif isAllFetch then
                    if state.targetItemID and grp.itemID then
                        match = (grp.itemID == state.targetItemID)
                    elseif state.targetItemName and grp.name then
                        match = (string.lower(grp.name) == string.lower(state.targetItemName))
                    end
                end
            end
            if btn.SetText then btn:SetText(match and "Stop" or "Get All") end
            if btn.SetActiveStyle then btn:SetActiveStyle(match) end
            if btn.SetEnabled then
                btn:SetEnabled(match or not (state.active and state.waitingServer))
            end
        end
    end
end

function MH.UpdateUI()
    local colKey = (state.statusKind == "positive" and "hexPositive")
        or (state.statusKind == "warning" and "hexWarning")
        or (state.statusKind == "danger" and "hexDanger")
        or (state.statusKind == "blue" and "hexBlue")
        or "hexMuted"
    local coloredStatus = palHex(colKey, "98989d") .. tostring(state.statusText or "Ready") .. "|r"

    local bar = MH.bar
    if bar then
        if bar.statusFs and bar.statusFs.SetText then
            bar.statusFs:SetText(coloredStatus)
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
            bar.refreshBtn:SetText((state.active and state.clickStepper) and "Next" or "Refresh")
        end
    end

    local picker = MH.itemPickerPanel
    if picker then
        if picker.statusFs and picker.statusFs.SetText then
            picker.statusFs:SetText(coloredStatus)
        end
        if picker.stopBtn and picker.stopBtn.SetEnabled then
            picker.stopBtn:SetEnabled(state.active == true)
        end
        if picker.refreshBtn and picker.refreshBtn.SetText then
            picker.refreshBtn:SetText((state.active and state.clickStepper) and "Next" or "Refresh")
        end
    end
    syncItemPickerRowButtons()

    if MH.UpdateOpenMailButton then
        MH.UpdateOpenMailButton()
    end
end

function MH.Stop(reason)
    local wasActive = state.active == true
    state.active = false
    state.waitingServer = false
    state.refreshPending = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    state.lastAttTake = nil
    state.targetMailID = nil
    state.targetMailSig = nil
    state.openMailFinished = false
    state.scanCursor = nil
    state.lastScanNumItems = nil
    state.hadUnloadedAboveCursor = false
    local text, kind = buildSummaryStatus(reason)
    state.targetMaxStacks = nil
    state.statusText = text
    state.statusKind = kind
    MH.UpdateUI()
    if MH.RefreshItemPickerUI then
        MH.RefreshItemPickerUI()
    end
    if wasActive and reason ~= "mail_closed" then
        if state.mailOpen and MH.RefreshPresetsUI then
            MH.RefreshPresetsUI({ skipItemPicker = true })
        end
        if ns.app and type(ns.app.flushDeferredMailBagResync) == "function" then
            pcall(ns.app.flushDeferredMailBagResync)
        end
        triggerFinalMailboxScan()
    end
    return true
end

function MH.ScanInboxItems()
    local emptyCounts = { all = 0, mats = 0, gear = 0, consumable = 0, other = 0 }
    if type(_G.GetInboxNumItems) ~= "function" then
        return {}, emptyCounts, { totalUnits = 0, totalMails = 0, codSkipped = 0, totalGoldCopper = 0, goldMails = 0 }
    end
    local numItems = _G.GetInboxNumItems()
    if hasSecret(numItems) then
        return {}, emptyCounts, { totalUnits = 0, totalMails = 0, codSkipped = 0, totalGoldCopper = 0, goldMails = 0 }
    end
    numItems = tonumber(numItems) or 0
    local maxAtt = maxAttachmentsReceive()
    local byKey = {}
    local groups = {}
    local catCounts = { all = 0, mats = 0, gear = 0, consumable = 0, other = 0 }
    local totalUnits, mailWithItems, codSkipped = 0, {}, 0
    local goldCopper, goldMails, goldOnlyMails, goldSlots = 0, 0, 0, {}

    for mailIdx = 1, numItems do
        local kind, info = MH.ClassifySlot(mailIdx)
        if kind == "cod" then
            codSkipped = codSkipped + 1
        elseif kind ~= "skip_unloaded" then
            local money = (info and tonumber(info.money)) or 0
            if money > 0 then
                goldCopper = goldCopper + money
                goldMails = goldMails + 1
                if info and (info.itemCount or 0) == 0 then
                    goldOnlyMails = goldOnlyMails + 1
                end
                mailWithItems[mailIdx] = true
                goldSlots[#goldSlots + 1] = {
                    mailIdx = mailIdx,
                    money = money,
                }
            end
            if info and (info.itemCount or 0) > 0 then
                local foundAtts = 0
                local exactAtts = info.itemCountExact
                for attIdx = 1, maxAtt do
                    local att = readInboxAttachment(mailIdx, attIdx)
                    if att then
                        foundAtts = foundAtts + 1
                        local gKey = att.itemID and ("id:" .. tostring(att.itemID)) or ("name:" .. string.lower(att.name))
                        local grp = byKey[gKey]
                        if not grp then
                            local cat = classifyItemCategory(att.itemID, att.link, att.name)
                            grp = {
                                key = gKey,
                                itemID = att.itemID,
                                name = att.name,
                                icon = att.icon,
                                quality = att.quality,
                                link = att.link,
                                category = cat,
                                totalQty = 0,
                                stackCount = 0,
                                mailCount = 0,
                                _mails = {},
                                slots = {},
                            }
                            byKey[gKey] = grp
                            groups[#groups + 1] = grp
                            catCounts.all = catCounts.all + 1
                            if catCounts[cat] ~= nil then
                                catCounts[cat] = catCounts[cat] + 1
                            end
                        end
                        grp.totalQty = grp.totalQty + att.count
                        grp.stackCount = grp.stackCount + 1
                        if not grp._mails[mailIdx] then
                            grp._mails[mailIdx] = true
                            grp.mailCount = grp.mailCount + 1
                        end
                        mailWithItems[mailIdx] = true
                        totalUnits = totalUnits + att.count
                        grp.slots[#grp.slots + 1] = {
                            mailIdx = mailIdx,
                            attachIdx = attIdx,
                            count = att.count,
                        }
                        if exactAtts and foundAtts >= exactAtts then
                            break
                        end
                    end
                end
            end
        end
    end

    for _, grp in ipairs(groups) do
        grp._mails = nil
    end
    table.sort(groups, function(a, b)
        if a.totalQty ~= b.totalQty then return a.totalQty > b.totalQty end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.itemID or "") < tostring(b.itemID or "")
    end)

    if goldCopper > 0 then
        table.insert(groups, 1, {
            key = "gold",
            isGold = true,
            itemID = nil,
            name = "Gold",
            icon = 133784,
            quality = 1,
            link = nil,
            category = "other",
            totalQty = goldCopper,
            totalCopper = goldCopper,
            stackCount = goldMails,
            mailCount = goldMails,
            goldOnlyCount = goldOnlyMails,
            slots = goldSlots,
        })
        catCounts.all = catCounts.all + 1
        catCounts.other = catCounts.other + 1
    end

    local totalMails = 0
    for _ in pairs(mailWithItems) do totalMails = totalMails + 1 end
    return groups, catCounts, {
        totalUnits = totalUnits,
        totalMails = totalMails,
        codSkipped = codSkipped,
        totalGoldCopper = goldCopper,
        goldMails = goldMails,
    }
end

function MH.CountOpenMailItems(mailID)
    local mid = tonumber(mailID)
        or tonumber(_G.InboxFrame and _G.InboxFrame.openMailID)
        or tonumber(_G.OpenMailFrame and _G.OpenMailFrame.openMailID)
    if not mid or mid < 1 then return 0, 0, "no_mail" end
    local kind = MH.ClassifySlot(mid)
    if kind == "cod" or kind == "skip_unloaded" then
        return 0, 0, kind
    end
    local maxAtt = maxAttachmentsReceive()
    local slots, units = 0, 0
    for attIdx = 1, maxAtt do
        local att = readInboxAttachment(mid, attIdx)
        if att then
            slots = slots + 1
            units = units + att.count
        end
    end
    return slots, units, kind
end

function MH.SetItemCategory(catKey)
    local valid = false
    for _, c in ipairs(MH.ITEM_CATEGORIES) do
        if c.key == catKey then valid = true; break end
    end
    state.itemCategory = valid and catKey or "all"
    state.itemPage = 1
    if MH.RefreshItemPickerUI then MH.RefreshItemPickerUI() end
    return state.itemCategory
end

function MH.StartOpenMailLoot(mailID)
    if _G.MailFrame and type(_G.MailFrame.IsShown) == "function" and not _G.MailFrame:IsShown() and not state.mailOpen then
        state.statusText = "Open mailbox first"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "mail_closed"
    end
    local mid = tonumber(mailID)
        or tonumber(_G.InboxFrame and _G.InboxFrame.openMailID)
        or tonumber(_G.OpenMailFrame and _G.OpenMailFrame.openMailID)
    if not mid or mid < 1 then
        state.statusText = "Open a mail first"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "no_mail"
    end
    local slots, _, kind = MH.CountOpenMailItems(mid)
    if kind == "cod" then
        state.statusText = "Skipped COD mail"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "cod"
    end
    if slots <= 0 then
        state.statusText = "No items in open mail"
        state.statusKind = "muted"
        MH.UpdateUI()
        return false, "no_items"
    end
    pauseOrderFlowMail()
    state.refreshPending = false
    local _, hdrInfo = MH.ClassifySlot(mid)
    state.active = true
    state.mode = "open_mail"
    state.targetMailID = mid
    state.targetMailSig = hdrInfo and (tostring(hdrInfo.sender or "") .. "|" .. tostring(hdrInfo.subject or "")) or nil
    state.openMailFinished = false
    state.targetItemID = nil
    state.targetItemName = nil
    state.targetTotalUnits = 0
    state.targetMaxStacks = nil
    state.waitingServer = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    state.lastAttTake = nil
    state.slotRetries = {}
    state.seenCOD = {}
    state.seenBlocked = {}
    state.lootedCount = 0
    state.lootedCopper = 0
    state.fetchedUnits = 0
    state.skippedCOD = 0
    state.skippedBlocked = 0
    state.skippedBagsFull = false
    state.scanCursor = nil
    state.lastScanNumItems = nil
    state.hadUnloadedAboveCursor = false
    state.statusText = "Taking items from open mail..."
    state.statusKind = "blue"
    MH.UpdateUI()
    return MH.Step()
end

function MH.StartItemFetch(itemID, itemName, opts)
    if _G.MailFrame and type(_G.MailFrame.IsShown) == "function" and not _G.MailFrame:IsShown() and not state.mailOpen then
        state.statusText = "Open mailbox first"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "mail_closed"
    end
    if state.active and state.waitingServer then
        return false, "busy"
    end
    local tid = tonumber(itemID)
    tid = (tid and tid > 0) and math.floor(tid) or nil
    local tname = (type(itemName) == "string" and trimOuter(itemName) ~= "") and trimOuter(itemName) or nil
    if not tid and not tname then
        return false, "no_item"
    end
    local maxStacks = (type(opts) == "table" and tonumber(opts.maxStacks)) or nil
    maxStacks = (maxStacks and maxStacks > 0) and math.floor(maxStacks) or nil
    local hintedTotal = (type(opts) == "table" and tonumber(opts.totalUnits)) or nil
    local totalUnits = 0
    if hintedTotal and hintedTotal > 0 and tname then
        totalUnits = math.floor(hintedTotal)
    else
        local groups = MH.ScanInboxItems()
        for _, grp in ipairs(groups) do
            if (tid and grp.itemID == tid) or (tname and grp.name and string.lower(grp.name) == string.lower(tname)) then
                totalUnits = totalUnits + (grp.totalQty or 0)
                if not tname then tname = grp.name end
            end
        end
    end
    pauseOrderFlowMail()
    state.refreshPending = false
    state.active = true
    state.mode = "item_type"
    state.targetMailID = nil
    state.targetMailSig = nil
    state.openMailFinished = false
    state.scanCursor = nil
    state.lastScanNumItems = nil
    state.hadUnloadedAboveCursor = false
    state.targetItemID = tid
    state.targetItemName = tname or ("Item #" .. tostring(tid))
    state.targetTotalUnits = totalUnits
    state.targetMaxStacks = maxStacks
    state.waitingServer = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    state.lastAttTake = nil
    state.slotRetries = {}
    state.seenCOD = {}
    state.seenBlocked = {}
    state.lootedCount = 0
    state.lootedCopper = 0
    state.fetchedUnits = 0
    state.skippedCOD = 0
    state.skippedBlocked = 0
    state.skippedBagsFull = false
    state.statusText = (maxStacks == 1)
        and ("Taking 1 stack of " .. tostring(state.targetItemName) .. "...")
        or ("Fetching " .. tostring(state.targetItemName) .. "...")
    state.statusKind = "blue"
    MH.UpdateUI()
    return MH.Step()
end

function MH.TakeOneItemStack(itemID, itemName, opts)
    return MH.StartItemFetch(itemID, itemName, {
        maxStacks = 1,
        totalUnits = type(opts) == "table" and opts.totalUnits or nil,
    })
end

function MH.StartGoldFetch(opts)
    if _G.MailFrame and type(_G.MailFrame.IsShown) == "function" and not _G.MailFrame:IsShown() and not state.mailOpen then
        state.statusText = "Open mailbox first"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "mail_closed"
    end
    if state.active and state.waitingServer then
        return false, "busy"
    end
    local maxStacks = (type(opts) == "table" and tonumber(opts.maxStacks)) or nil
    maxStacks = (maxStacks and maxStacks > 0) and math.floor(maxStacks) or nil
    pauseOrderFlowMail()
    state.refreshPending = false
    state.active = true
    state.mode = "gold_only"
    state.targetMailID = nil
    state.targetMailSig = nil
    state.openMailFinished = false
    state.targetItemID = nil
    state.targetItemName = "Gold"
    state.targetTotalUnits = 0
    state.targetMaxStacks = maxStacks
    state.waitingServer = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    state.lastAttTake = nil
    state.slotRetries = {}
    state.seenCOD = {}
    state.seenBlocked = {}
    state.lootedCount = 0
    state.lootedCopper = 0
    state.fetchedUnits = 0
    state.skippedCOD = 0
    state.skippedBlocked = 0
    state.skippedBagsFull = false
    state.scanCursor = nil
    state.lastScanNumItems = nil
    state.hadUnloadedAboveCursor = false
    state.statusText = (maxStacks == 1) and "Taking gold..." or "Collecting gold..."
    state.statusKind = "blue"
    MH.UpdateUI()
    return MH.Step()
end

function MH.TakeOneGoldMail()
    return MH.StartGoldFetch({ maxStacks = 1 })
end

function MH.Start(mode)
    if _G.MailFrame and type(_G.MailFrame.IsShown) == "function" and not _G.MailFrame:IsShown() and not state.mailOpen then
        state.statusText = "Open mailbox first"
        state.statusKind = "warning"
        MH.UpdateUI()
        return false, "mail_closed"
    end
    pauseOrderFlowMail()
    state.refreshPending = false
    state.active = true
    state.mode = mode or "all"
    state.targetMailID = nil
    state.targetMailSig = nil
    state.openMailFinished = false
    state.targetItemID = nil
    state.targetItemName = nil
    state.targetTotalUnits = 0
    state.targetMaxStacks = nil
    state.waitingServer = false
    state.clickStepper = false
    state.serial = state.serial + 1
    state.lastSlot = nil
    state.lastAttTake = nil
    state.slotRetries = {}
    state.seenCOD = {}
    state.seenBlocked = {}
    state.lootedCount = 0
    state.lootedCopper = 0
    state.fetchedUnits = 0
    state.skippedCOD = 0
    state.skippedBlocked = 0
    state.skippedBagsFull = false
    state.scanCursor = nil
    state.lastScanNumItems = nil
    state.hadUnloadedAboveCursor = false
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

    reconcileLastAttTake(numItems)

    if state.mode == "open_mail" then
        local openFrame = _G.OpenMailFrame
        if openFrame and type(openFrame.IsShown) == "function" and not openFrame:IsShown() then
            MH.Stop("mail_closed")
            return false, "mail_closed"
        end
        if state.openMailFinished then
            MH.Stop("done")
            return false, "done"
        end
        local mid = state.targetMailID
        local curOpen = tonumber(_G.InboxFrame and _G.InboxFrame.openMailID) or tonumber(openFrame and openFrame.openMailID)
        if curOpen and mid and curOpen ~= mid then
            MH.Stop("mail_changed")
            return false, "mail_changed"
        end
        if not mid or mid < 1 or mid > numItems then
            MH.Stop("done")
            return false, "done"
        end
        local kind, info = MH.ClassifySlot(mid)
        if kind == "cod" then
            state.skippedCOD = state.skippedCOD + 1
            MH.Stop("done")
            return false, "cod"
        elseif kind == "skip_unloaded" then
            state.skippedBlocked = state.skippedBlocked + 1
            MH.Stop("done")
            return false, "unloaded"
        end
        if state.targetMailSig and info then
            local curSig = tostring(info.sender or "") .. "|" .. tostring(info.subject or "")
            if curSig ~= state.targetMailSig then
                MH.Stop("done")
                return false, "done"
            end
        end
        local maxAtt = maxAttachmentsReceive()
        for attIdx = maxAtt, 1, -1 do
            local att = readInboxAttachment(mid, attIdx)
            if att then
                local instKey = string.format("om:%d:%d:%s:%d", mid, attIdx, tostring(att.itemID or att.name), att.count)
                local retries = state.slotRetries[instKey] or 0
                if retries >= MH.MAX_SLOT_RETRIES then
                    if not state.seenBlocked[instKey] then
                        state.seenBlocked[instKey] = true
                        state.skippedBlocked = state.skippedBlocked + 1
                    end
                else
                    if freeSlots <= 0 then
                        state.skippedBagsFull = true
                        MH.Stop("done")
                        return false, "bags_full"
                    end
                    if type(_G.TakeInboxItem) ~= "function" then
                        MH.Stop("no_api")
                        return false, "no_api"
                    end
                    state.waitingServer = true
                    state.lastAttTake = {
                        mode = "open_mail",
                        mailIdx = mid,
                        attachIdx = attIdx,
                        numItems = numItems,
                        itemID = att.itemID,
                        name = att.name,
                        count = att.count,
                        instKey = instKey,
                    }
                    state.lootedCount = state.lootedCount + 1
                    state.fetchedUnits = (state.fetchedUnits or 0) + att.count
                    state.serial = state.serial + 1
                    local stepSerial = state.serial
                    pcall(_G.TakeInboxItem, mid, attIdx)
                    state.statusText = string.format("Taking %dx %s...", att.count, tostring(att.name))
                    state.statusKind = "blue"
                    MH.UpdateUI()
                    armStepWatchdog(stepSerial)
                    return true, "open_mail_item", mid, attIdx
                end
            end
        end
        MH.Stop("done")
        return false, "done"
    end

    if state.mode == "item_type" then
        if state.targetMaxStacks and (state.lootedCount or 0) >= state.targetMaxStacks then
            MH.Stop("done")
            return false, "done"
        end
        local maxAtt = maxAttachmentsReceive()
        local startIdx = numItems
        if state.scanCursor and not state.hadUnloadedAboveCursor and numItems <= (state.lastScanNumItems or numItems) then
            startIdx = math.min(numItems, state.scanCursor)
        end
        state.hadUnloadedAboveCursor = false
        state.lastScanNumItems = numItems
        for mailIdx = startIdx, 1, -1 do
            local kind, info = MH.ClassifySlot(mailIdx)
            if kind == "cod" then
                local sig = slotSignature(info)
                if not state.seenCOD[sig] then
                    state.seenCOD[sig] = true
                    state.skippedCOD = state.skippedCOD + 1
                end
            elseif kind == "skip_unloaded" then
                state.hadUnloadedAboveCursor = true
            elseif kind ~= "empty" and info and (info.itemCount or 0) > 0 then
                local seenAtts = 0
                local exactAtts = info.itemCountExact
                for attIdx = maxAtt, 1, -1 do
                    local att = readInboxAttachment(mailIdx, attIdx)
                    if att then
                        seenAtts = seenAtts + 1
                        if matchesItemTarget(att) then
                            local instKey = string.format("it:%d:%d:%s:%d", mailIdx, attIdx, tostring(att.itemID or att.name), att.count)
                            local retries = state.slotRetries[instKey] or 0
                            if retries >= MH.MAX_SLOT_RETRIES then
                                if not state.seenBlocked[instKey] then
                                    state.seenBlocked[instKey] = true
                                    state.skippedBlocked = state.skippedBlocked + 1
                                end
                            else
                                if freeSlots <= 0 then
                                    state.skippedBagsFull = true
                                    MH.Stop("done")
                                    return false, "bags_full"
                                end
                                if type(_G.TakeInboxItem) ~= "function" then
                                    MH.Stop("no_api")
                                    return false, "no_api"
                                end
                                state.scanCursor = mailIdx
                                state.waitingServer = true
                                state.lastAttTake = {
                                    mode = "item_type",
                                    mailIdx = mailIdx,
                                    attachIdx = attIdx,
                                    numItems = numItems,
                                    itemID = att.itemID,
                                    name = att.name,
                                    count = att.count,
                                    instKey = instKey,
                                }
                                state.lootedCount = state.lootedCount + 1
                                state.fetchedUnits = (state.fetchedUnits or 0) + att.count
                                state.serial = state.serial + 1
                                local stepSerial = state.serial
                                pcall(_G.TakeInboxItem, mailIdx, attIdx)
                                state.statusText = string.format("Fetching %s (%d/%d)...",
                                    tostring(att.name or state.targetItemName), state.fetchedUnits, math.max(state.fetchedUnits, state.targetTotalUnits or state.fetchedUnits))
                                state.statusKind = "blue"
                                MH.UpdateUI()
                                armStepWatchdog(stepSerial)
                                return true, "item_type", mailIdx, attIdx
                            end
                        elseif exactAtts and seenAtts >= exactAtts then
                            break
                        end
                    end
                end
            end
        end
        MH.Stop("done")
        return false, "done"
    end

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

    if state.mode == "gold_only" then
        if state.targetMaxStacks and (state.lootedCount or 0) >= state.targetMaxStacks then
            MH.Stop("done")
            return false, "done"
        end
        local startIdx = numItems
        if state.scanCursor and not state.hadUnloadedAboveCursor and numItems <= (state.lastScanNumItems or numItems) then
            startIdx = math.min(numItems, state.scanCursor)
        end
        state.hadUnloadedAboveCursor = false
        state.lastScanNumItems = numItems
        for i = startIdx, 1, -1 do
            local kind, info = MH.ClassifySlot(i)
            if kind == "skip_unloaded" then
                state.hadUnloadedAboveCursor = true
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
            elseif info and (info.money or 0) > 0 then
                local sig = slotSignature(info)
                local instKey = tostring(i) .. "|" .. sig
                local retries = state.slotRetries[instKey] or 0
                if retries >= MH.MAX_SLOT_RETRIES then
                    if not state.seenBlocked[instKey] then
                        state.seenBlocked[instKey] = true
                        state.skippedBlocked = state.skippedBlocked + 1
                    end
                else
                    if type(_G.TakeInboxMoney) ~= "function" then
                        MH.Stop("no_api")
                        return false, "no_api"
                    end
                    state.scanCursor = i
                    state.waitingServer = true
                    state.lastSlot = {
                        index = i,
                        numItems = numItems,
                        sig = sig,
                        instKey = instKey,
                        money = info.money or 0,
                        itemCount = info.itemCount or 0,
                        action = "money",
                        copper = info.money or 0,
                    }
                    state.lootedCount = state.lootedCount + 1
                    state.lootedCopper = state.lootedCopper + (info.money or 0)
                    state.serial = state.serial + 1
                    local stepSerial = state.serial
                    pcall(_G.TakeInboxMoney, i)
                    state.statusText = (state.targetMaxStacks == 1)
                        and ("Taking " .. formatCopperSimple(info.money) .. "...")
                        or string.format("Collecting gold (%s)...", formatCopperSimple(state.lootedCopper))
                    state.statusKind = "blue"
                    MH.UpdateUI()
                    armStepWatchdog(stepSerial)
                    return true, "money", i
                end
            end
        end
        MH.Stop("done")
        return false, "done"
    end

    local startIdx = numItems
    if state.scanCursor and not state.hadUnloadedAboveCursor and numItems <= (state.lastScanNumItems or numItems) then
        startIdx = math.min(numItems, state.scanCursor)
    end
    state.hadUnloadedAboveCursor = false
    state.lastScanNumItems = numItems
    for i = startIdx, 1, -1 do
        local kind, info = MH.ClassifySlot(i)
        if kind == "skip_unloaded" then
            state.hadUnloadedAboveCursor = true
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
                    state.scanCursor = i
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
                    armStepWatchdog(stepSerial)
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

local function finishPendingRefresh(fromTimeout)
    if not state.refreshPending then return false end
    state.refreshPending = false
    if state.active then return false end
    state.statusText = "Ready"
    state.statusKind = "muted"
    if MH.RefreshItemPickerUI then
        MH.RefreshItemPickerUI()
    end
    if fromTimeout and state.statusText == "Ready" then
        state.statusText = "Inbox up to date"
        state.statusKind = "muted"
        MH.UpdateUI()
    elseif not MH.itemPickerPanel then
        MH.UpdateUI()
    end
    return true
end

function MH.RequestRefresh()
    local now = nowSec()
    local elapsed = now - (state.lastCheckInboxAt or 0)
    if state.lastCheckInboxAt > 0 and elapsed < MH.REFRESH_COOLDOWN_SEC then
        local rem = math.max(1, math.ceil(MH.REFRESH_COOLDOWN_SEC - elapsed))
        state.statusText = string.format("Refresh ready in %ds", rem)
        state.statusKind = "muted"
        if MH.RefreshItemPickerUI then MH.RefreshItemPickerUI() else MH.UpdateUI() end
        return false, "cooldown", rem
    end
    state.lastCheckInboxAt = now
    state.refreshPending = true
    state.refreshSerial = (state.refreshSerial or 0) + 1
    local rSerial = state.refreshSerial
    state.statusText = "Refreshing inbox..."
    state.statusKind = "blue"
    MH.UpdateUI()
    if type(_G.CheckInbox) == "function" then
        pcall(_G.CheckInbox)
    end
    if state.refreshPending and _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(2.0, function()
            if state.refreshPending and state.refreshSerial == rSerial and not state.active then
                finishPendingRefresh(true)
            end
        end)
    end
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

local function makeBaronCrimsonButton(parent, label, w, h, fontSize, onClick, opts)
    opts = opts or {}
    local bw = w or 74
    local bh = h or 21
    local btn = _G.CreateFrame("Button", nil, parent)
    btn:SetSize(bw, bh)
    btn._enabled = true
    btn._label = tostring(label or "")
    btn._baseCol = opts.subtle and { 0.36, 0.06, 0.10, 0.94 } or { 0.44, 0.06, 0.11, 0.98 }
    btn._activeCol = { 0.64, 0.08, 0.12, 0.98 }

    if parent and parent.GetFrameLevel and btn.SetFrameLevel then
        btn:SetFrameLevel((parent:GetFrameLevel() or 1) + (opts.levelBoost or 2))
    end

    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(btn._baseCol[1], btn._baseCol[2], btn._baseCol[3], btn._baseCol[4])
    btn._bgTex = bg

    local cushion = btn:CreateTexture(nil, "ARTWORK", nil, 0)
    cushion:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    cushion:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    local theme = ns.Theme
    local texPath = (theme and type(theme.GetSkinAsset) == "function") and theme.GetSkinAsset("goblin", "header_tile") or nil
    if texPath then
        cushion:SetTexture(texPath, "REPEAT", "REPEAT")
        if cushion.SetHorizTile then cushion:SetHorizTile(false) end
        if cushion.SetVertTile then cushion:SetVertTile(false) end
        if cushion.SetTexCoord then cushion:SetTexCoord(0, bw / 72, 0, bh / 72) end
        cushion:SetVertexColor(1.0, 0.80, 0.80, opts.subtle and 0.46 or 0.62)
    else
        cushion:SetColorTexture(0.54, 0.09, 0.15, opts.subtle and 0.40 or 0.55)
    end
    btn._cushionTex = cushion

    local bevel = btn:CreateTexture(nil, "ARTWORK", nil, 1)
    bevel:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    bevel:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    bevel:SetHeight(1)
    bevel:SetColorTexture(1.0, 0.92, 0.78, 0.22)

    local gold = opts.borderCol or { 0.83, 0.64, 0.24, 0.92 }
    local topB = btn:CreateTexture(nil, "OVERLAY", nil, 0)
    topB:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    topB:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    topB:SetHeight(1)
    topB:SetColorTexture(gold[1], gold[2], gold[3], gold[4])

    local botB = btn:CreateTexture(nil, "OVERLAY", nil, 0)
    botB:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    botB:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    botB:SetHeight(1)
    botB:SetColorTexture(gold[1], gold[2], gold[3], gold[4])

    local leftB = btn:CreateTexture(nil, "OVERLAY", nil, 0)
    leftB:SetSize(1, 1)
    leftB:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    leftB:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    leftB:SetColorTexture(gold[1], gold[2], gold[3], gold[4])

    local rightB = btn:CreateTexture(nil, "OVERLAY", nil, 0)
    rightB:SetSize(1, 1)
    rightB:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    rightB:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    rightB:SetColorTexture(gold[1], gold[2], gold[3], gold[4])

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1.0, 0.92, 0.72, 0.16)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", btn, "LEFT", 4, 0)
    fs:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(fs, fontSize or 10, "semibold")
    end
    if fs.SetTextColor then
        fs:SetTextColor(1.00, 0.95, 0.82, 1.00)
    end
    fs:SetText(btn._label)
    if btn.SetFontString then btn:SetFontString(fs) end
    btn.fs = fs

    function btn:SetText(txt)
        self._label = tostring(txt or "")
        self.fs:SetText(self._label)
    end
    function btn:GetText()
        return self._label
    end
    local rawSetEnabled = btn.SetEnabled
    function btn:SetEnabled(en)
        self._enabled = (en ~= false)
        if rawSetEnabled then rawSetEnabled(self, self._enabled) end
        if self.SetAlpha then self:SetAlpha(self._enabled and 1.0 or 0.50) end
    end
    function btn:IsEnabled()
        return self._enabled ~= false
    end
    function btn:SetActiveStyle(isActive)
        local c = isActive and self._activeCol or self._baseCol
        self._bgTex:SetColorTexture(c[1], c[2], c[3], c[4])
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
    { key = "bank",              label = "Bank",               shortLabel = "Bank",      icon = 133784, group = "core" },
    { key = "investmentStorage", label = "Investment Storage", shortLabel = "Invest",    icon = 133786, group = "core" },
    { key = "auction",           label = "Auction",            shortLabel = "AH",        icon = 133785, group = "core" },
    { key = "mainCrafter",       label = "Main Crafter",       shortLabel = "Crafter",   icon = 136241, group = "core" },
    { key = "alchemy",           label = "Alchemy",            shortLabel = "Alch",      icon = 136240, group = "profession" },
    { key = "blacksmithing",     label = "Blacksmithing",      shortLabel = "BS",        icon = 136241, group = "profession" },
    { key = "enchanting",        label = "Enchanting",         shortLabel = "Ench",      icon = 136244, group = "profession" },
    { key = "engineering",       label = "Engineering",        shortLabel = "Eng",       icon = 136243, group = "profession" },
    { key = "leatherworking",    label = "Leatherworking",     shortLabel = "LW",        icon = 136247, group = "profession" },
    { key = "tailoring",         label = "Tailoring",          shortLabel = "Tailor",    icon = 136249, group = "profession" },
    { key = "cooking",           label = "Cooking",            shortLabel = "Cook",      icon = 133971, group = "profession" },
    { key = "firstaid",          label = "First Aid",          shortLabel = "First Aid", icon = 135966, group = "profession" },
}

MH.PROFESSION_ROLE_KEYS = {
    "alchemy", "blacksmithing", "enchanting", "engineering",
    "leatherworking", "tailoring", "cooking", "firstaid",
}

local CORE_ROLE_MAP = { bank = true, investmentStorage = true, auction = true, mainCrafter = true }
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
    if type(rec.investmentStorage) ~= "string" then rec.investmentStorage = "" end
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
    local function onVisChange()
        MH.RefreshPresetsUI()
        if MH.UpdateOpenMailButton then MH.UpdateOpenMailButton() end
    end
    local function hookShowHide(frame)
        if not frame or frame._mmPresetsVisHooked then return end
        if type(frame.HookScript) ~= "function" then return end
        frame._mmPresetsVisHooked = true
        frame:HookScript("OnShow", onVisChange)
        frame:HookScript("OnHide", onVisChange)
    end
    hookShowHide(_G.SendMailFrame)
    hookShowHide(_G.InboxFrame)
    hookShowHide(_G.OpenMailFrame)
    if type(_G.OpenMail_Update) == "function" and type(_G.hooksecurefunc) == "function" and not MH._openMailUpdateHooked then
        MH._openMailUpdateHooked = true
        pcall(_G.hooksecurefunc, "OpenMail_Update", onVisChange)
    end

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

    local gearIcon = theme and theme.ASSETS and (theme.ASSETS.icon_gear or theme.ASSETS.icon_settings) or nil
    local gearBtn
    if theme and type(theme.CreatePlateButton) == "function" then
        gearBtn = theme.CreatePlateButton(panel, "", 22, 22, {
            icon = gearIcon,
            iconSize = 13,
            variant = "ghost",
            pill = true,
        })
        if not gearIcon and gearBtn.fs then
            gearBtn.fs:SetText("*")
        end
    else
        gearBtn = makeBarButton(panel, "Cfg", 28, 20, "secondary", openMailSettingsTab)
    end
    gearBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -5)
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

local function createItemPickerPanel(mf)
    local panel = _G.CreateFrame("Frame", "MerchantMasterMailItemsPanel", mf)
    panel:SetWidth(MH.DOCK_PANEL_WIDTH)
    panel:SetHeight(112)
    panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
    panel:Hide()

    local theme = ns.Theme
    if theme and type(theme.NineApple) == "function" then
        panel._bgSurf = theme.NineApple(panel, "glass_r12", "cardBg", "borderStrong", { noSpecular = true })
    end

    local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
    if titleFs.SetJustifyH then titleFs:SetJustifyH("LEFT") end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(titleFs, 12, "semibold")
    end
    titleFs:SetText("Mail Items")
    panel.titleFs = titleFs

    local stopBtn = makeBarButton(panel, "Stop", 44, 20, "danger", function()
        MH.Stop("user_stop")
    end)
    stopBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
    if stopBtn.SetEnabled then stopBtn:SetEnabled(false) end
    attachMailTooltip(stopBtn, "Stop Collection", {
        "Immediately cancels an in-progress Get All, Gold, or Open Mail fetch.",
        "Disabled when idle.",
    })
    panel.stopBtn = stopBtn

    local refreshBtn = makeBarButton(panel, "Refresh", 54, 20, "secondary", function()
        if state.active and state.clickStepper then
            MH.Step()
        else
            MH.RequestRefresh()
            MH.RefreshItemPickerUI()
        end
    end)
    refreshBtn:SetPoint("RIGHT", stopBtn, "LEFT", -4, 0)
    attachMailTooltip(refreshBtn, "Refresh Mail Items", {
        "Re-scan inbox attachments (and request CheckInbox when cooldown allows).",
    })
    panel.refreshBtn = refreshBtn
    titleFs:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)

    -- Category filter pills: All | Mats | Gear | Cons | Other
    panel.catButtons = {}
    local catWidths = { all = 48, mats = 50, gear = 50, consumable = 50, other = 50 }
    local cx = 8
    for _, cat in ipairs(MH.ITEM_CATEGORIES) do
        local cw = catWidths[cat.key] or 48
        local cb = makeBarButton(panel, cat.label, cw, 20, "secondary", function()
            MH.SetItemCategory(cat.key)
        end)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", cx, -30)
        cb._catKey = cat.key
        panel.catButtons[cat.key] = cb
        cx = cx + cw + 4
    end

    -- 6 item rows inside 280px width
    panel.rows = {}
    for i = 1, MH.ITEM_PICKER_PAGE_SIZE do
        local row = _G.CreateFrame("Button", nil, panel)
        row:SetHeight(28)
        row:SetWidth(MH.DOCK_PANEL_WIDTH - 16)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(56 + (i - 1) * 31))
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -(56 + (i - 1) * 31))
        if theme and type(theme.NineApple) == "function" then
            row._bgSurf = theme.NineApple(row, "glass_r8", "cardAltBg", "border", { noSpecular = true })
        end
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        if hl.SetAllPoints then hl:SetAllPoints(row) else hl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0) end
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.hl = hl

        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18)
        ic:SetPoint("LEFT", row, "LEFT", 6, 0)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTex = ic

        local getAllBtn = makeBaronCrimsonButton(row, "Get All", 48, 20, 9, function(self)
            local grp = self:GetParent() and self:GetParent()._group
            if not grp then return end
            if grp.isGold then
                if state.active and state.mode == "gold_only" and state.targetMaxStacks == nil then
                    MH.Stop("user_stop")
                else
                    MH.StartGoldFetch()
                end
                return
            end
            if state.active and state.mode == "item_type" and state.targetMaxStacks == nil then
                local same = false
                if state.targetItemID and grp.itemID then
                    same = (state.targetItemID == grp.itemID)
                elseif state.targetItemName and grp.name then
                    same = (string.lower(state.targetItemName) == string.lower(grp.name))
                end
                if same then
                    MH.Stop("user_stop")
                    return
                end
            end
            MH.StartItemFetch(grp.itemID, grp.name, { totalUnits = grp.totalQty })
        end, { subtle = true, levelBoost = 2 })
        getAllBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        attachMailTooltip(getAllBtn,
            function(self)
                local grp = self:GetParent() and self:GetParent()._group
                return "Get All" .. (grp and grp.name and (": " .. tostring(grp.name)) or "")
            end,
            function(self)
                local grp = self:GetParent() and self:GetParent()._group
                if not grp then return {} end
                if grp.isGold then
                    return {
                        string.format("Collect all %s across %d non-COD mail%s via TakeInboxMoney only.",
                            formatCopperSimple(grp.totalCopper),
                            grp.mailCount or 1, (grp.mailCount or 1) == 1 and "" or "s"),
                        "Does not touch attached items or COD mail.",
                    }
                end
                return {
                    string.format("Fetch all %dx (%d stack%s across %d mail%s) from your inbox.",
                        grp.totalQty or 0,
                        grp.stackCount or 1, (grp.stackCount or 1) == 1 and "" or "s",
                        grp.mailCount or 1, (grp.mailCount or 1) == 1 and "" or "s"),
                    "Never touches COD mail.",
                }
            end)
        row.getAllBtn = getAllBtn

        local qtyFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyFs:SetPoint("RIGHT", getAllBtn, "LEFT", -5, 0)
        if qtyFs.SetJustifyH then qtyFs:SetJustifyH("RIGHT") end
        if qtyFs.SetWordWrap then qtyFs:SetWordWrap(false) end
        if theme and type(theme.ApplyFont) == "function" then
            theme.ApplyFont(qtyFs, 10, "semibold")
        end
        row.qtyFs = qtyFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("LEFT", ic, "RIGHT", 5, 0)
        nameFs:SetPoint("RIGHT", qtyFs, "LEFT", -4, 0)
        if nameFs.SetJustifyH then nameFs:SetJustifyH("LEFT") end
        if nameFs.SetWordWrap then nameFs:SetWordWrap(false) end
        if nameFs.SetMaxLines then nameFs:SetMaxLines(1) end
        if theme and type(theme.ApplyFont) == "function" then
            theme.ApplyFont(nameFs, 11, "semibold")
        end
        row.nameFs = nameFs

        row:SetScript("OnClick", function(self)
            local grp = self._group
            if not grp then return end
            if grp.isGold then
                MH.TakeOneGoldMail()
                return
            end
            MH.TakeOneItemStack(grp.itemID, grp.name, { totalUnits = grp.totalQty })
        end)
        attachMailTooltip(row,
            function(self) return self._group and self._group.name or "" end,
            function(self)
                local grp = self._group
                if not grp then return {} end
                if grp.isGold then
                    return {
                        string.format("In inbox: %s across %d non-COD mail%s",
                            formatCopperSimple(grp.totalCopper),
                            grp.mailCount or 1, (grp.mailCount or 1) == 1 and "" or "s"),
                        "Click row to take gold from 1 mail. Click 'Get All' to collect gold from all non-COD mails while leaving item attachments untouched.",
                    }
                end
                return {
                    string.format("In inbox: %dx across %d stack%s (%d mail%s)",
                        grp.totalQty or 0,
                        grp.stackCount or 1, (grp.stackCount or 1) == 1 and "" or "s",
                        grp.mailCount or 1, (grp.mailCount or 1) == 1 and "" or "s"),
                    "Click row to collect 1 stack. Click 'Get All' on the right to fetch every stack.",
                }
            end)
        row:Hide()
        panel.rows[i] = row
    end

    local emptyFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -64)
    emptyFs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -64)
    if emptyFs.SetJustifyH then emptyFs:SetJustifyH("CENTER") end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(emptyFs, 10, "regular")
    end
    emptyFs:SetText("No item attachments in inbox")
    emptyFs:Hide()
    panel.emptyFs = emptyFs

    local prevBtn = makeBarButton(panel, "<", 26, 20, "secondary", function()
        state.itemPage = math.max(1, (state.itemPage or 1) - 1)
        MH.RefreshItemPickerUI()
    end)
    prevBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 26)
    prevBtn:Hide()
    panel.prevBtn = prevBtn

    local nextBtn = makeBarButton(panel, ">", 26, 20, "secondary", function()
        state.itemPage = (state.itemPage or 1) + 1
        MH.RefreshItemPickerUI()
    end)
    nextBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 26)
    nextBtn:Hide()
    panel.nextBtn = nextBtn

    local pageFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageFs:SetPoint("CENTER", panel, "BOTTOM", 0, 36)
    if pageFs.SetJustifyH then pageFs:SetJustifyH("CENTER") end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(pageFs, 10, "regular")
    end
    pageFs:Hide()
    panel.pageFs = pageFs

    local statusFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 7)
    statusFs:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 7)
    statusFs:SetHeight(14)
    if statusFs.SetJustifyH then statusFs:SetJustifyH("LEFT") end
    if statusFs.SetWordWrap then statusFs:SetWordWrap(false) end
    if statusFs.SetMaxLines then statusFs:SetMaxLines(1) end
    if theme and type(theme.ApplyFont) == "function" then
        theme.ApplyFont(statusFs, 10, "regular")
    end
    statusFs:SetText(palHex("hexMuted", "98989d") .. "Ready|r")
    panel.statusFs = statusFs

    if panel.EnableMouseWheel then panel:EnableMouseWheel(true) end
    if panel.SetScript then
        panel:SetScript("OnMouseWheel", function(_, delta)
            if (delta or 0) > 0 then
                state.itemPage = math.max(1, (state.itemPage or 1) - 1)
            elseif (delta or 0) < 0 then
                state.itemPage = (state.itemPage or 1) + 1
            end
            MH.RefreshItemPickerUI()
        end)
    end

    local function paintPicker()
        paintSurfaceFallback(panel._bgSurf)
        local p = getPalette()
        if titleFs.SetTextColor and p.text then
            titleFs:SetTextColor(p.text[1], p.text[2], p.text[3], p.text[4] or 1)
        end
        if emptyFs.SetTextColor and p.textMuted then
            emptyFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3], p.textMuted[4] or 1)
        end
        if pageFs.SetTextColor and p.textMuted then
            pageFs:SetTextColor(p.textMuted[1], p.textMuted[2], p.textMuted[3], p.textMuted[4] or 1)
        end
        MH.RefreshItemPickerUI()
    end
    if theme and type(theme.RegisterWidget) == "function" then
        theme.RegisterWidget(panel, paintPicker)
    end
    return panel
end

local function anchorOpenMailButton(btn, omf)
    if not (btn and omf) then return end
    if btn.ClearAllPoints then btn:ClearAllPoints() end
    local replyBtn = _G.OpenMailReplyButton
    local w = 68
    if replyBtn then
        if replyBtn.GetLeft and omf.GetLeft then
            local rl, ol = tonumber(replyBtn:GetLeft()), tonumber(omf:GetLeft())
            if rl and ol then
                local avail = rl - ol - 12
                if avail >= 52 then
                    w = math.min(68, math.floor(avail))
                end
            end
        end
        btn:SetSize(w, 21)
        btn:SetPoint("RIGHT", replyBtn, "LEFT", -4, 0)
    else
        btn:SetSize(w, 21)
        btn:SetPoint("BOTTOMLEFT", omf, "BOTTOMLEFT", 8, 6)
    end
    if btn._cushionTex and btn._cushionTex.SetTexCoord then
        btn._cushionTex:SetTexCoord(0, w / 72, 0, 21 / 72)
    end
end

function MH.MountOpenMailButton()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        state.pendingMount = true
        return false, "combat"
    end
    local omf = _G.OpenMailFrame
    if not omf or type(_G.CreateFrame) ~= "function" then
        return false, "no_open_mail"
    end
    if not MH.openMailBtn then
        local btn = makeBaronCrimsonButton(omf, "Get All", 68, 21, 10, function()
            if state.active and state.mode == "open_mail" then
                MH.Stop("user_stop")
            else
                MH.StartOpenMailLoot()
            end
        end, { levelBoost = 5 })
        anchorOpenMailButton(btn, omf)
        attachMailTooltip(btn, "Get all items", {
            "Collects all item attachments from this open mail.",
            "Stops cleanly if your bags become full, and refuses COD mail.",
        })
        btn:Hide()
        MH.openMailBtn = btn
    end
    return true, MH.openMailBtn
end

function MH.UpdateOpenMailButton()
    local btn = MH.openMailBtn
    if not btn then return false end
    local omf = _G.OpenMailFrame
    local openShown = (omf ~= nil and omf.IsShown and omf:IsShown()) == true
    if not openShown then
        if state.active and state.mode == "open_mail" then
            MH.Stop("mail_closed")
        end
        btn:Hide()
        return false
    end
    anchorOpenMailButton(btn, omf)
    local mid = tonumber(_G.InboxFrame and _G.InboxFrame.openMailID) or tonumber(omf and omf.openMailID)
    if state.active and state.mode == "open_mail" and state.targetMailID and mid and state.targetMailID ~= mid then
        MH.Stop("mail_changed")
    end
    local slots, _, kind = MH.CountOpenMailItems(mid)
    if state.active and state.mode == "open_mail" then
        if btn.SetText then btn:SetText("Stop") end
        if btn.SetActiveStyle then btn:SetActiveStyle(true) end
        if btn.SetEnabled then btn:SetEnabled(true) end
        btn:Show()
        return true
    elseif slots > 0 then
        if btn.SetText then btn:SetText("Get All") end
        if btn.SetActiveStyle then btn:SetActiveStyle(false) end
        if btn.SetEnabled then btn:SetEnabled(kind ~= "cod") end
        btn:Show()
        return true
    end
    btn:Hide()
    return false
end

function MH.RefreshItemPickerUI()
    local picker = MH.itemPickerPanel
    if not picker then return nil end
    local groups, catCounts, meta = MH.ScanInboxItems()
    local pal = getPalette()
    local activeCat = state.itemCategory or "all"
    for _, cat in ipairs(MH.ITEM_CATEGORIES) do
        local cb = picker.catButtons and picker.catButtons[cat.key]
        if cb then
            local cnt = (catCounts and catCounts[cat.key]) or 0
            local lbl = (cnt > 0 and cat.key ~= "all") and string.format("%s %d", cat.label, cnt) or cat.label
            if cb.SetText then cb:SetText(lbl) end
            if cb.SetActive then cb:SetActive(activeCat == cat.key) end
        end
    end

    local filtered = {}
    for _, grp in ipairs(groups) do
        if activeCat == "all" or grp.category == activeCat then
            filtered[#filtered + 1] = grp
        end
    end

    local total = #filtered
    local pageSize = MH.ITEM_PICKER_PAGE_SIZE
    local totalPages = math.max(1, math.ceil(total / pageSize))
    state.itemPage = math.max(1, math.min(totalPages, tonumber(state.itemPage) or 1))
    local startIdx = (state.itemPage - 1) * pageSize + 1
    local visibleCount = 0

    local goldCol = pal.gold or { 1.0, 0.82, 0.20, 1 }
    for i = 1, pageSize do
        local row = picker.rows and picker.rows[i]
        if row then
            local grp = filtered[startIdx + i - 1]
            row._group = grp
            if grp then
                visibleCount = visibleCount + 1
                row:Show()
                if row._bgSurf and row._bgSurf.UpdateTheme then row._bgSurf:UpdateTheme() end
                if grp.isGold then
                    if row.iconTex then row.iconTex:SetTexture(133784) end
                    if row.nameFs then
                        row.nameFs:SetText("Gold")
                        if row.nameFs.SetTextColor then
                            row.nameFs:SetTextColor(goldCol[1], goldCol[2], goldCol[3], goldCol[4] or 1)
                        end
                    end
                    if row.qtyFs then
                        local gTxt = formatCopperSimple(grp.totalCopper)
                        if (grp.mailCount or 1) > 1 then
                            gTxt = gTxt .. string.format(" (%dm)", grp.mailCount)
                        end
                        row.qtyFs:SetText(gTxt)
                        if row.qtyFs.SetTextColor then
                            row.qtyFs:SetTextColor(goldCol[1], goldCol[2], goldCol[3], goldCol[4] or 1)
                        end
                    end
                else
                    if row.iconTex then row.iconTex:SetTexture(grp.icon or 134400) end
                    if row.nameFs then
                        row.nameFs:SetText(grp.name or "")
                        local qc = QUALITY_COLORS[grp.quality] or pal.text or { 1, 1, 1 }
                        if row.nameFs.SetTextColor then
                            row.nameFs:SetTextColor(qc[1], qc[2], qc[3], 1)
                        end
                    end
                    if row.qtyFs then
                        local qTxt = (grp.mailCount or 1) > 1
                            and string.format("x%d (%dm)", grp.totalQty or 0, grp.mailCount)
                            or string.format("x%d", grp.totalQty or 0)
                        row.qtyFs:SetText(qTxt)
                        local qCol = pal.accentGreen or { 0.30, 0.85, 0.45, 1 }
                        if row.qtyFs.SetTextColor then
                            row.qtyFs:SetTextColor(qCol[1], qCol[2], qCol[3], 1)
                        end
                    end
                end
            else
                row:Hide()
            end
        end
    end

    if picker.emptyFs then
        if visibleCount == 0 then
            picker.emptyFs:SetText((catCounts and catCounts.all or 0) == 0
                and "No items or gold in inbox"
                or "No items in this category")
            safeShow(picker.emptyFs)
        else
            safeHide(picker.emptyFs)
        end
    end

    local hasPager = totalPages > 1
    if picker.prevBtn then
        if hasPager then
            picker.prevBtn:Show()
            if picker.prevBtn.SetEnabled then picker.prevBtn:SetEnabled(state.itemPage > 1) end
        else
            picker.prevBtn:Hide()
        end
    end
    if picker.nextBtn then
        if hasPager then
            picker.nextBtn:Show()
            if picker.nextBtn.SetEnabled then picker.nextBtn:SetEnabled(state.itemPage < totalPages) end
        else
            picker.nextBtn:Hide()
        end
    end
    if picker.pageFs then
        if hasPager then
            safeShow(picker.pageFs)
            picker.pageFs:SetText(string.format("%d / %d", state.itemPage, totalPages))
        else
            safeHide(picker.pageFs)
        end
    end

    if not state.active and state.statusText == "Ready" and meta then
        local hasGoldInFiltered = false
        for _, grp in ipairs(filtered) do
            if grp.isGold then
                hasGoldInFiltered = true
                break
            end
        end
        local hasGold = hasGoldInFiltered and (meta.totalGoldCopper or 0) > 0
        local itemGroups = total - (hasGold and 1 or 0)
        if hasGold and itemGroups > 0 then
            state.statusText = string.format("%d item%s + %s ready",
                itemGroups, itemGroups == 1 and "" or "s", formatCopperSimple(meta.totalGoldCopper))
            state.statusKind = "muted"
        elseif hasGold then
            state.statusText = string.format("%s in %d mail%s ready",
                formatCopperSimple(meta.totalGoldCopper),
                meta.goldMails or 1, (meta.goldMails or 1) == 1 and "" or "s")
            state.statusKind = "muted"
        elseif itemGroups > 0 then
            state.statusText = string.format("%d item%s ready (%d units)",
                itemGroups, itemGroups == 1 and "" or "s", meta.totalUnits or 0)
            state.statusKind = "muted"
        elseif (meta.codSkipped or 0) > 0 then
            state.statusText = string.format("%d COD mail skipped", meta.codSkipped)
            state.statusKind = "warning"
        end
    end
    MH.UpdateUI()

    local h = (visibleCount == 0) and 112 or (56 + visibleCount * 31 + (hasPager and 26 or 0) + 26)
    picker:SetHeight(h)
    return filtered, catCounts, meta
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
    if mf and not MH.itemPickerPanel then
        MH.itemPickerPanel = createItemPickerPanel(mf)
    end
    if mf and not MH.presetsPanel then
        MH.presetsPanel = createPresetsPanel(mf)
    end
    MH.MountOpenMailButton()
    local inbox = _G.InboxFrame
    if inbox and not MH.inboxQuickStrip then
        MH.inboxQuickStrip = createInboxQuickStrip(inbox)
    end
    hookBlizzardMailVisibility()
    return true
end

function MH.RefreshPresetsUI(opts)
    local skipItemPicker = (type(opts) == "table" and opts.skipItemPicker == true)
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

    -- 2. Dock Mail Items (Inbox tab) and Mail Recipients cleanly at TOPRIGHT of MailFrame
    safeHide(bar)
    local picker = MH.itemPickerPanel
    if dockMode == "inbox" and picker and mf then
        if not skipItemPicker and MH.RefreshItemPickerUI then MH.RefreshItemPickerUI() end
        if picker.ClearAllPoints then picker:ClearAllPoints() end
        picker:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
        picker:Show()
    elseif picker then
        safeHide(picker)
    end

    if dockMode == "hidden" or not showPanel then
        safeHide(panel)
    elseif dockMode == "send" and panel and mf then
        if panel.ClearAllPoints then panel:ClearAllPoints() end
        panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
        panel:Show()
    elseif dockMode == "inbox" and panel and mf then
        if panel.ClearAllPoints then panel:ClearAllPoints() end
        if picker and picker.IsShown and picker:IsShown() then
            panel:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -MH.DOCK_GAP_Y)
        else
            panel:SetPoint("TOPLEFT", mf, "TOPRIGHT", MH.DOCK_GAP_X, 0)
        end
        panel:Show()
    end

    if MH.UpdateOpenMailButton then
        MH.UpdateOpenMailButton()
    end

    -- 3. Keep legacy Inbox quick strip hidden
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
    safeHide(MH.bar)
    MH.MountPresetPanels()
    MH.InstallSendMailGuard()
    MH.RefreshPresetsUI()
    MH.UpdateOpenMailButton()
    return true, MH.presetsPanel
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
        if not state.active then
            state.statusText = "Ready"
            state.statusKind = "muted"
        end
        MH.MountOnMailFrame()
        MH.UpdateUI()
        MH.RefreshPresetsUI()
    elseif event == "MAIL_CLOSED" then
        state.mailOpen = false
        state.refreshPending = false
        clearUnsavedConfirm()
        if state.active then
            MH.Stop("mail_closed")
        end
        if MH.bar and MH.bar.Hide then MH.bar:Hide() end
        if MH.itemPickerPanel and MH.itemPickerPanel.Hide then MH.itemPickerPanel:Hide() end
        if MH.presetsPanel and MH.presetsPanel.Hide then MH.presetsPanel:Hide() end
        if MH.openMailBtn and MH.openMailBtn.Hide then MH.openMailBtn:Hide() end
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
            if state.refreshPending then
                finishPendingRefresh(false)
            elseif MH.RefreshItemPickerUI then
                MH.RefreshItemPickerUI()
            else
                MH.UpdateUI()
            end
            if not state.active then
                MH.RefreshPresetsUI()
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if state.mailOpen and not state.active then
            if MH.RefreshItemPickerUI then MH.RefreshItemPickerUI() end
            MH.UpdateOpenMailButton()
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
    for _, ev in ipairs({
        "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "BAG_UPDATE_DELAYED",
        "MAIL_SEND_INFO_UPDATE", "MAIL_FAILED", "MAIL_SEND_SUCCESS",
        "ADDON_ACTION_BLOCKED", "PLAYER_REGEN_ENABLED",
    }) do
        pcall(f.RegisterEvent, f, ev)
    end
end
