-- Workstream 3 Unit Tests: Native Personal-Gold Logging, Analytics TSM Gating & MailHelper.lua
local root = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")

local assertions = 0
local function check(cond, msg)
    assertions = assertions + 1
    if not cond then
        error("ASSERTION FAILED #" .. assertions .. ": " .. tostring(msg), 2)
    end
end
local function eq(a, b, msg)
    check(a == b, (msg or "value") .. ": got " .. tostring(a) .. ", expected " .. tostring(b))
end

-- Mock clock & deferred timer queue
local mockNow = 1700000000
local mockGetTime = 1000
local timers = {}
_G.time = function() return mockNow end
_G.GetTime = function() return mockGetTime end
_G.date = os.date
_G.C_Timer = {
    After = function(delay, fn)
        timers[#timers + 1] = { at = mockGetTime + (tonumber(delay) or 0), fn = fn }
    end,
}
local function advanceTimers(dt)
    mockNow = mockNow + dt
    mockGetTime = mockGetTime + dt
    local i = 1
    while i <= #timers do
        if timers[i].at <= mockGetTime then
            local fn = table.remove(timers, i).fn
            fn()
        else
            i = i + 1
        end
    end
end
local function clearTimers()
    timers = {}
end

-- Minimal UI frame mock for Capture, Model, UI, MailHelper
local function makeFrame(frameType, name, parent)
    local f = {
        _type = frameType,
        _name = name,
        _parent = parent,
        _shown = true,
        _enabled = true,
        _scripts = {},
        _events = {},
        _points = {},
        _w = 338,
        _h = 62,
        _text = "",
        SetScript = function(self, ev, fn) self._scripts[ev] = fn end,
        GetScript = function(self, ev) return self._scripts[ev] end,
        HookScript = function(self, ev, fn)
            local prev = self._scripts[ev]
            self._scripts[ev] = function(...) if prev then prev(...) end; fn(...) end
        end,
        RegisterEvent = function(self, ev) self._events[ev] = true end,
        SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
        ClearAllPoints = function(self) self._points = {} end,
        SetSize = function(self, w, h) self._w = w; self._h = h end,
        SetWidth = function(self, w) self._w = w end,
        SetHeight = function(self, h) self._h = h end,
        GetWidth = function(self) return self._w end,
        GetHeight = function(self) return self._h end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
        SetEnabled = function(self, v) self._enabled = v and true or false end,
        IsEnabled = function(self) return self._enabled end,
        SetText = function(self, t) self._text = tostring(t or "") end,
        GetText = function(self) return self._text end,
        Click = function(self)
            if self._enabled and self._scripts.OnClick then self._scripts.OnClick(self) end
        end,
        SetFontString = function(self, fs) self._fs = fs end,
        CreateFontString = function(self)
            local fs = {
                _text = "",
                SetPoint = function() end,
                SetHeight = function() end,
                SetJustifyH = function() end,
                SetJustifyV = function() end,
                SetWordWrap = function() end,
                SetText = function(s, t) s._text = tostring(t or "") end,
                GetText = function(s) return s._text end,
                SetTextColor = function() end,
                SetFont = function() return true end,
            }
            return fs
        end,
        CreateTexture = function(self)
            return {
                SetPoint = function() end,
                SetSize = function() end,
                SetHeight = function() end,
                SetTexture = function() end,
                SetColorTexture = function() end,
                SetVertexColor = function() end,
                SetTexCoord = function() end,
                SetAlpha = function() end,
                Show = function() end,
                Hide = function() end,
            }
        end,
    }
    return f
end
_G.CreateFrame = makeFrame

-- Host environment setup
local legacyEnabled = false
local scanCalls = 0
local host
host = {
    Analytics = {},
    UseLegacyPriceAddons = function() return legacyEnabled end,
    DetectActiveEconomy = function() return "Normal-Horde" end,
    ItemName = function(id) return "Item " .. tostring(id) end,
    ItemIcon = function() return 134400 end,
    ITEM_IDS_BY_NAME = { ["Arcane Crystal"] = 12363, ["Black Lotus"] = 13468 },
    Theme = {
        GetActivePalette = function()
            return {
                mode = "dark",
                cardBg = { 0.15, 0.15, 0.16, 0.96 },
                borderStrong = { 1, 1, 1, 0.22 },
                hexText = "ffffff", hexMuted = "98989d", hexGreen = "30d158",
                hexPositive = "30d158", hexRed = "ff4245", hexDanger = "ff4245",
                hexOrange = "ff9230", hexWarning = "ff9230", hexBlue = "5ac8fa",
            }
        end,
        RegisterWidget = function() end,
        NineApple = function()
            return { SetFill = function() end, SetBorder = function() end, SetColors = function() end }
        end,
        ApplyFont = function() end,
        CreatePlateButton = function(parent, text, w, h)
            local b = makeFrame("Button", nil, parent)
            b:SetSize(w, h)
            b:SetText(text)
            b.SetActive = function(self, on) self._active = on and true or false end
            return b
        end,
    },
    app = {
        charKey = "Normal-Horde-Forever-Hero",
        QueueMailboxScan = function() scanCalls = scanCalls + 1 end,
        orderFlow = {
            _paused = false,
            _state = { stages = { collect = { pendingTake = { source = "mail", itemID = 12363 } } } },
            GetState = function(self) return host.app.orderFlow._state end,
        },
        ui = {},
    },
}
_G.MerchantMasterAPI = { ns = host }
_G.MerchantMasterDB = { enableLegacyPriceAddons = false, chars = { ["Normal-Horde-Forever-Hero"] = { name = "Hero", economy = "Normal-Horde" } } }
_G.MerchantMasterLedgerDB = {}

-- Load Analytics modules + MailHelper
assert(loadfile(root .. "Analytics/Store.lua"))("MerchantMaster", host)
assert(loadfile(root .. "Analytics/Model.lua"))("MerchantMaster", host)
assert(loadfile(root .. "Analytics/Capture.lua"))("MerchantMaster", host)
assert(loadfile(root .. "MailHelper.lua"))("MerchantMaster", host)

local Store = host.Analytics.Store
local Model = host.Analytics.Model
local Capture = host.Analytics.Capture
local MH = host.MailHelper

Store.Init()
Capture._testReady = true

local function todayRows()
    local d = Store.db.days[Store.DayKey()]
    return (d and d.r) or {}
end
local function findRows(typ)
    local out = {}
    for _, r in ipairs(todayRows()) do
        if r.type == typ then out[#out + 1] = r end
    end
    return out
end

-- =========================================================================
-- 1. WS1 Pure Standalone Analytics (Store + Capture — zero TSM reads)
-- =========================================================================
_G.TradeSkillMasterDB = {
    ["r@Normal@internalData@auctionSaleHints"] = { ["TSM Exclusive Item\001i:99901"] = true },
    ["r@Normal@internalData@csvSales"] = "itemString,stackSize,quantity,price,otherPlayer,player,time,source\ni:12363,1,1,100000,Buyer,Hero," .. tostring(mockNow - 60) .. ",Trade",
}
Store.db.stats.firstLive["Normal-Horde-Forever-Hero"] = mockNow - 3600

eq(Store.ResolveItemIDByName("Normal-Horde-Forever-Hero", "TSM Exclusive Item"), 0, "ResolveItemIDByName never reads TradeSkillMasterDB")
check(Store.SeedTSM == nil and Store.ReconcileTSMSales == nil, "SeedTSM and ReconcileTSMSales are removed")

_G.GetMoney = function() return 500000 end
clearTimers()
Capture.loggedIn = false
Capture.OnEvent(nil, "PLAYER_LOGIN")
advanceTimers(4)
eq(#todayRows(), 0, "3s PLAYER_LOGIN maintenance does not import any rows from TradeSkillMasterDB")

-- =========================================================================
-- 2. Capture.GetCapabilities().warbank fix
-- =========================================================================
_G.C_Bank = {}
_G.Enum = { BankType = {} }
eq(Capture.GetCapabilities().warbank, false, "warbank is false on Forever 16001 when Enum.BankType.Account is nil")
_G.Enum.BankType.Account = 2
eq(Capture.GetCapabilities().warbank, true, "warbank is true when C_Bank and numeric Enum.BankType.Account exist")
_G.Enum.BankType.Account = nil
_G.C_Bank = nil

-- =========================================================================
-- 3. 5 New Personal-Gold Types in Store, Model, Capture
-- =========================================================================
for _, typ in ipairs({ "TRAINER_FEE", "GUILD_DEPOSIT", "GUILD_WITHDRAW", "AH_BID", "AH_OUTBID" }) do
    check(Store.TYPES[typ] == true, typ .. " registered in Store.TYPES")
    check(Store.TYPE_GROUPS.all[typ] == true, typ .. " registered in Store.TYPE_GROUPS.all")
    check(Store.MatchesTypeGroup(typ, typ), typ .. " matches individual type filter")
    check(type(Model.TYPE_LABELS[typ]) == "string", typ .. " has Model.TYPE_LABELS entry")
end
check(Store.MatchesTypeGroup("TRAINER_FEE", "expenses") and Store.MatchesTypeGroup("TRAINER_FEE", "vendor"), "TRAINER_FEE in expenses & vendor groups")
check(Store.MatchesTypeGroup("GUILD_DEPOSIT", "transfers") and Store.MatchesTypeGroup("GUILD_DEPOSIT", "other"), "GUILD_DEPOSIT in transfers & other groups")
check(Store.MatchesTypeGroup("GUILD_WITHDRAW", "transfers") and Store.MatchesTypeGroup("GUILD_WITHDRAW", "other"), "GUILD_WITHDRAW in transfers & other groups")
check(Store.MatchesTypeGroup("AH_BID", "auctions") and not Store.MatchesTypeGroup("AH_BID", "buys"), "AH_BID in auctions and NOT in buys")
check(Store.MatchesTypeGroup("AH_OUTBID", "auctions") and Store.MatchesTypeGroup("AH_OUTBID", "mail"), "AH_OUTBID in auctions & mail groups")

-- Reset clean store for capture hook tests
_G.MerchantMasterLedgerDB = {}
Store.Init()
local cash = 500000
local bagQty = {}
_G.GetMoney = function() return cash end
_G.GetItemCount = function(id) return bagQty[id] or 0 end
_G.GetGuildInfo = function() return "Ironforge Traders" end
_G.GetRealZoneText = function() return "Orgrimmar" end

-- Mock trainer, guild bank, and AH APIs
local trainerList = {
    { name = "Artisan Alchemy", cost = 50000 },
    { name = "Flask of the Titans", cost = 12000 },
}
_G.GetNumTrainerServices = function() return #trainerList end
_G.GetTrainerServiceInfo = function(i) return trainerList[i] and trainerList[i].name end
_G.GetTrainerServiceCost = function(i) return trainerList[i] and trainerList[i].cost end
_G.BuyTrainerService = function(i)
    -- Simulate Blizzard mutating trainer list immediately on purchase
    local cost = trainerList[i] and trainerList[i].cost or 0
    table.remove(trainerList, i)
    cash = cash - cost
end
_G.DepositGuildBankMoney = function(amt) cash = cash - amt end
_G.WithdrawGuildBankMoney = function(amt) cash = cash + amt end

local mockNeedsConfirm = false
local auctionRows = {
    [401] = { auctionID = 401, itemID = 12363, quantity = 2, buyoutAmount = 100000, itemName = "Arcane Crystal" },
    [402] = { auctionID = 402, itemID = 13468, quantity = 1, buyoutAmount = 200000, itemName = "Black Lotus" },
}
_G.C_AuctionHouse = {
    GetBrowseResults = function()
        local res = {}
        for _, v in pairs(auctionRows) do res[#res + 1] = v end
        return res
    end,
    PlaceBid = function() end,
    PostItem = function() return mockNeedsConfirm end,
    PostCommodity = function() return mockNeedsConfirm end,
    ConfirmPostItem = function() end,
    ConfirmPostCommodity = function() end,
    CalculateCommodityDeposit = function() return 250 end,
    CalculateItemDeposit = function() return 300 end,
    CancelAuction = function() end,
}

Capture.InstallHooks()
Store.InitRecon("Normal-Horde-Forever-Hero", cash)
Capture.OnEvent(nil, "PLAYER_MONEY") -- sync baseline lastMoney

-- 3a. TRAINER_FEE (uses trainerCache captured on TRAINER_SHOW before BuyTrainerService mutates list)
Capture.OnEvent(nil, "TRAINER_SHOW")
_G.BuyTrainerService(1)
Capture.OnEvent(nil, "PLAYER_MONEY")
local trainerRows = findRows("TRAINER_FEE")
eq(#trainerRows, 1, "TRAINER_FEE recorded once")
eq(trainerRows[1].total, -50000, "TRAINER_FEE exact copper spent")
eq(trainerRows[1].extra.name, "Artisan Alchemy", "TRAINER_FEE preserves cached spell name after trainer list mutation")

-- 3b. GUILD_DEPOSIT & GUILD_WITHDRAW
_G.DepositGuildBankMoney(25000)
Capture.OnEvent(nil, "PLAYER_MONEY")
local depRows = findRows("GUILD_DEPOSIT")
eq(#depRows, 1, "GUILD_DEPOSIT recorded")
eq(depRows[1].total, -25000, "GUILD_DEPOSIT negative total")
eq(depRows[1].extra.guild, "Ironforge Traders", "GUILD_DEPOSIT stores guild name")

_G.WithdrawGuildBankMoney(15000)
Capture.OnEvent(nil, "PLAYER_MONEY")
local wdrRows = findRows("GUILD_WITHDRAW")
eq(#wdrRows, 1, "GUILD_WITHDRAW recorded")
eq(wdrRows[1].total, 15000, "GUILD_WITHDRAW positive total")

-- 3c. UI_ERROR_MESSAGE clears pendingMoneyQueue
_G.DepositGuildBankMoney(999999)
cash = cash + 999999 -- undo mock deduction since deposit failed
check(#Capture._pendingMoneyQueue == 1, "pendingMoneyQueue holds staged deposit")
Capture.OnEvent(nil, "UI_ERROR_MESSAGE", 1, "You don't have enough money.")
eq(#Capture._pendingMoneyQueue, 0, "UI_ERROR_MESSAGE clears pendingMoneyQueue")

-- 3d. AH_BID (non-buyout bid excluded from AddBasis) -> Win invoice -> AH_BUY (skipRecon=true, AddBasis updated, zero double recon)
local reconBeforeBid = Store.db.stats.recon["Normal-Horde-Forever-Hero"].recorded
_G.C_AuctionHouse.PlaceBid(401, 60000) -- buyout is 100000, so 60000 is a non-buyout bid!
-- Even if AUCTION_HOUSE_PURCHASE_COMPLETED fired spuriously, isBuyout=false gates it
Capture.OnEvent(nil, "AUCTION_HOUSE_PURCHASE_COMPLETED", 401)
eq(#findRows("AH_BUY"), 0, "AUCTION_HOUSE_PURCHASE_COMPLETED ignored for non-buyout bid")
cash = cash - 60000
Capture.OnEvent(nil, "PLAYER_MONEY")
local bidRows = findRows("AH_BID")
eq(#bidRows, 1, "AH_BID logged on PLAYER_MONEY")
eq(bidRows[1].total, -60000, "AH_BID deducts exact bid copper")
eq(bidRows[1].itemID, 12363, "AH_BID stores itemID")
local basisQtyAfterBid, basisAvgAfterBid = Store.Basis("Normal-Horde", 12363)
eq(basisQtyAfterBid, 0, "AH_BID does NOT pollute Store.AddBasis")
eq(Store.db.stats.recon["Normal-Horde-Forever-Hero"].recorded, reconBeforeBid - 60000, "AH_BID updates recon.recorded once")

-- Nil-guard on unknown auctionID in PlaceBid
_G.C_AuctionHouse.PlaceBid(99999, 5000)
eq(#Capture._pendingMoneyQueue, 0, "PlaceBid nil-guards unknown auction info without crashing or queueing")

-- Now win the bid via buyer invoice mail!
_G.ATTACHMENTS_MAX_RECEIVE = 1
_G.GetInboxNumItems = function() return 1 end
_G.GetInboxHeaderInfo = function(i)
    return nil, nil, "Auction House", "Auction won: Arcane Crystal", 0, 0, 30, 1, false, false
end
_G.GetInboxInvoiceInfo = function()
    return "buyer", "Arcane Crystal", "CrystalSeller", 60000, 100000, 0, 0, 0, 0, 0, 2
end
_G.GetInboxItem = function(_, slot) if slot == 1 then return "Arcane Crystal", 12363, nil, 2 end end
_G.GetInboxItemLink = function(_, slot) if slot == 1 then return "|Hitem:12363|h[Arcane Crystal]|h" end end

Capture._preTakeMail(1)
bagQty[12363] = 2
Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
local buyRows = findRows("AH_BUY")
eq(#buyRows, 1, "Winning bid invoice creates AH_BUY row")
eq(buyRows[1].total, -60000, "Winning AH_BUY has winning price")
check(buyRows[1].extra.reconSkip == true and buyRows[1].extra.fromBid == true, "Winning AH_BUY sets reconSkip & fromBid")
eq(Store.db.stats.recon["Normal-Horde-Forever-Hero"].recorded, reconBeforeBid - 60000, "Winning AH_BUY does NOT double-deduct recon.recorded")
local basisQtyAfterWin, basisAvgAfterWin = Store.Basis("Normal-Horde", 12363)
eq(basisQtyAfterWin, 2, "Winning AH_BUY updates Store.AddBasis qty")
eq(basisAvgAfterWin, 30000, "Winning AH_BUY updates Store.AddBasis avg unit cost")

-- ReconcileGold produces ZERO ADJUST drift across Trainer, Guild, and Bid->Win!
local adj = Store.ReconcileGold("Normal-Horde-Forever-Hero", cash, "Logout Reconciliation")
eq(adj, nil, "Zero ADJUST drift after Trainer, Guild Deposit/Withdraw, and AH_BID -> AH_BUY win")

-- 3e. AH_OUTBID detection (localized AUCTION_OUTBID_MAIL_SUBJECT + fallback) & pendingMailTake FIFO queue
_G.AUCTION_OUTBID_MAIL_SUBJECT = "Auction outbid: %s"
local rapidMails = {
    [1] = { sender = "Auction House", subject = "Auction outbid: Black Lotus", money = 80000, cod = 0, hasItem = 0 },
    [2] = { sender = "Friend", subject = "Gift Gold", money = 10000, cod = 0, hasItem = 0 },
}
_G.GetInboxNumItems = function() return 2 end
_G.GetInboxHeaderInfo = function(i)
    local m = rapidMails[i]
    if not m then return end
    return nil, nil, m.sender, m.subject, m.money, m.cod, 30, m.hasItem, false, false
end
_G.GetInboxInvoiceInfo = function() return nil end
_G.GetInboxItem = function() return nil end
_G.GetInboxItemLink = function() return nil end

-- Rapidly take mail #2 then mail #1 before PLAYER_MONEY fires!
Capture._preTakeMail(2)
Capture._preTakeMail(1)
eq(#Capture._pendingMailTakeQueue, 2, "pendingMailTake FIFO queues both rapid takes without dropping")
cash = cash + 10000 + 80000
Capture.OnEvent(nil, "PLAYER_MONEY")
eq(#Capture._pendingMailTakeQueue, 0, "pendingMailTake FIFO drains both confirmed mails in one tick")
local outbidRows = findRows("AH_OUTBID")
eq(#outbidRows, 1, "AH_OUTBID logged instead of MONEY_TRANSFER")
eq(outbidRows[1].total, 80000, "AH_OUTBID positive refund total")
eq(outbidRows[1].itemID, 13468, "AH_OUTBID resolves itemID from subject")
local xferRows = findRows("MONEY_TRANSFER")
eq(#xferRows, 1, "Second queued mail still logged as MONEY_TRANSFER")
eq(xferRows[1].total, 10000, "Second queued mail preserves exact gold")

-- 3f. Abandoned needsConfirmation AH post NEVER logs phantom AH_POST on 30s timeout!
clearTimers()
mockNeedsConfirm = true
_G.C_AuctionHouse.PostCommodity({ itemID = 12363 }, 1, 5, 50000)
advanceTimers(35)
eq(#findRows("AH_POST"), 0, "Abandoned needsConfirmation post does NOT write phantom AH_POST on 30s timeout")

-- Confirming a needsConfirmation post DOES log AH_POST when created
mockNeedsConfirm = true
_G.C_AuctionHouse.PostCommodity({ itemID = 12363 }, 1, 5, 50000)
_G.C_AuctionHouse.ConfirmPostCommodity({ itemID = 12363 }, 1, 5, 50000)
cash = cash - 250
Capture.OnEvent(nil, "AUCTION_HOUSE_AUCTION_CREATED", 555)
eq(#findRows("AH_POST"), 1, "Confirmed post logs AH_POST once")

-- Verify Model source filter buckets for Guild, AH, Vendor/Other
local guildRes = Model.QueryLedger({ period = "all", source = "Guild" }, 0, 500)
eq(guildRes.totalMatched, 2, "Model source='Guild' matches GUILD_DEPOSIT and GUILD_WITHDRAW")
local ahRes = Model.QueryLedger({ period = "all", source = "AH" }, 0, 500)
local sawBid, sawOutbid = false, false
for _, r in ipairs(ahRes.rows) do
    if r.type == "AH_BID" then sawBid = true end
    if r.type == "AH_OUTBID" then sawOutbid = true end
end
check(sawBid and sawOutbid, "Model source='AH' includes AH_BID and AH_OUTBID")
local trainerRes = Model.QueryLedger({ period = "all", source = "Vendor/Other" }, 0, 500)
local sawTrainer = false
for _, r in ipairs(trainerRes.rows) do
    if r.type == "TRAINER_FEE" and r.typeLabel == "Trainer Fee" then sawTrainer = true end
end
check(sawTrainer, "Model source='Vendor/Other' includes TRAINER_FEE with typeLabel='Trainer Fee'")

-- =========================================================================
-- 4. MailHelper.lua Tests
-- =========================================================================
clearTimers()
local freeBagSlots = 10
_G.NUM_BAG_SLOTS = 4
_G.C_Container = {
    GetContainerNumFreeSlots = function(bag)
        if bag == 0 then return freeBagSlots, 0 end
        if bag == 1 then return 8, 32 end -- herb bag (non-zero family) must NOT count as general slots!
        return 0, 0
    end,
}
eq(MH.GetFreeBagSlots(), 10, "GetFreeBagSlots counts general bag slots only")

-- 4a. Fail-CLOSED COD guard & slot classification
local secretSentinel = "__SECRET__"
_G.issecretvalue = function(v) return v == secretSentinel end
_G.RETRIEVING_DATA = "Retrieving data..."
_G.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
_G.AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
_G.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"

local inbox = {
    [1] = { sender = "Scammer", subject = "Free Gift", money = 0, cod = 50000, hasItem = 1 },
    [2] = { sender = "Lag", subject = "Loading", money = 0, cod = nil, hasItem = 1 },
    [3] = { sender = "Lag2", subject = nil, money = 100, cod = 0, hasItem = 0 },
    [4] = { sender = "Lag3", subject = "Retrieving data...", money = 100, cod = 0, hasItem = 0 },
    [5] = { sender = secretSentinel, subject = "Secret", money = 100, cod = 0, hasItem = 0 },
    [6] = { sender = "Auction House", subject = "Auction outbid: Black Lotus", money = 40000, cod = 0, hasItem = 0 },
    [7] = { sender = "Auction House", subject = "Auction successful: Arcane Crystal", money = 95000, cod = 0, hasItem = 0, inv = "seller" },
    [8] = { sender = "Auction House", subject = "Auction expired: Peacebloom", money = 0, cod = 0, hasItem = true },
    [9] = { sender = "Auction House", subject = "Auction won: Silverleaf", money = 0, cod = 0, hasItem = 1, inv = "buyer" },
    [10] = { sender = "Alt", subject = "Hybrid Mail", money = 5000, cod = 0, hasItem = 2 },
}
_G.GetInboxNumItems = function() return #inbox, #inbox end
_G.GetInboxHeaderInfo = function(i)
    local m = inbox[i]
    if not m then return end
    return nil, nil, m.sender, m.subject, m.money, m.cod, 30, m.hasItem, false, false
end
_G.GetInboxInvoiceInfo = function(i)
    local m = inbox[i]
    return m and m.inv or nil
end

eq(MH.ClassifySlot(1), "cod", "COD mail (codAmount > 0) classified as cod")
eq(MH.ClassifySlot(2), "skip_unloaded", "nil codAmount fails CLOSED as skip_unloaded")
eq(MH.ClassifySlot(3), "skip_unloaded", "nil subject fails CLOSED as skip_unloaded")
eq(MH.ClassifySlot(4), "skip_unloaded", "RETRIEVING_DATA subject fails CLOSED as skip_unloaded")
eq(MH.ClassifySlot(5), "skip_unloaded", "secret value fails CLOSED as skip_unloaded")
eq(MH.ClassifySlot(6), "ah_outbid", "outbid mail classified as ah_outbid")
eq(MH.ClassifySlot(7), "ah_sale", "seller invoice classified as ah_sale")
local expKind, expInfo = MH.ClassifySlot(8)
eq(expKind, "ah_expired", "expired mail classified as ah_expired")
eq(expInfo.itemCount, 1, "boolean hasItem=true normalized to itemCount=1")
eq(MH.ClassifySlot(9), "ah_won", "buyer invoice classified as ah_won")

-- 4b. Hybrid mail loots gold FIRST when freeSlots == 0, skips COD & unloaded, continues pure gold!
local lootLog = {}
_G.TakeInboxMoney = function(i)
    lootLog[#lootLog + 1] = { fn = "TakeInboxMoney", idx = i }
    if inbox[i] then
        inbox[i].money = 0
        if (inbox[i].hasItem == 0 or inbox[i].hasItem == false) then
            table.remove(inbox, i)
        end
    end
end
_G.AutoLootMailItem = function(i)
    lootLog[#lootLog + 1] = { fn = "AutoLootMailItem", idx = i }
    table.remove(inbox, i)
end

freeBagSlots = 0
_G.MailFrame = makeFrame("Frame", "MailFrame", nil)
scanCalls = 0
MH.OnEvent(nil, "MAIL_SHOW")
check(MH.bar ~= nil and MH.bar:GetHeight() == 62, "MailHelper mounts 62px bar onto MailFrame")
MH.Start("all")
-- Step through inbox updates until batch completes
local guard = 0
while MH.IsActive() and guard < 20 do
    guard = guard + 1
    MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
end
eq(MH.IsActive(), false, "Batch finishes cleanly")
eq(scanCalls, 1, "Triggers exactly 1 consolidated ownership scan when batch stops")
eq(host.app.orderFlow._state.stages.collect.pendingTake, nil, "Pauses OrderFlow mail collection when MailHelper starts")

-- Verify hybrid mail (#10) used TakeInboxMoney (NOT AutoLootMailItem) when freeSlots == 0,
-- pure-gold AH sale (#7) and AH outbid (#6) were looted, and COD (#1) was NEVER touched!
local tookHybridGold, tookSale, tookOutbid, touchedCOD, usedAutoLoot = false, false, false, false, false
for _, ev in ipairs(lootLog) do
    if ev.fn == "AutoLootMailItem" then usedAutoLoot = true end
    if ev.fn == "TakeInboxMoney" and ev.idx == 10 then tookHybridGold = true end
    if ev.fn == "TakeInboxMoney" and ev.idx == 7 then tookSale = true end
    if ev.fn == "TakeInboxMoney" and ev.idx == 6 then tookOutbid = true end
    if ev.idx == 1 then touchedCOD = true end
end
check(tookHybridGold, "Hybrid mail loots gold via TakeInboxMoney when bags are full")
check(not usedAutoLoot, "AutoLootMailItem is NOT called when freeSlots == 0")
check(tookSale and tookOutbid, "Pure-gold AH sale and outbid mails are looted while bags are full")
check(not touchedCOD, "COD mail is NEVER looted")
local st = MH.GetState()
eq(st.skippedCOD, 1, "skippedCOD deduplicated to exactly 1")
eq(st.skippedBagsFull, true, "skippedBagsFull flagged")
eq(st.skippedBlocked, 4, "skippedBlocked deduplicated across 4 unloaded slots")
_G.issecretvalue = nil

-- 4c. MAX_SLOT_RETRIES = 2 + 1.2s stall watchdog
clearTimers()
freeBagSlots = 5
inbox = {
    [1] = { sender = "Stuck", subject = "Stuck Gold", money = 100, cod = 0, hasItem = 0 },
}
local stuckAttempts = 0
_G.TakeInboxMoney = function() stuckAttempts = stuckAttempts + 1 end -- server drops response; mail stays!
MH.Start("all")
eq(stuckAttempts, 1, "Initial attempt 1 fires")
advanceTimers(1.25) -- watchdog 1 triggers retry 2
eq(stuckAttempts, 2, "1.2s watchdog triggers retry 2")
advanceTimers(1.25) -- watchdog 2 hits MAX_SLOT_RETRIES=2 and stops
eq(stuckAttempts, 2, "MAX_SLOT_RETRIES=2 stops retrying stuck slot")
eq(MH.IsActive(), false, "Batch stops after stuck slot hits retry cap")
eq(MH.GetState().skippedBlocked, 1, "Stuck slot counted once in skippedBlocked")

-- 4d. ADDON_ACTION_BLOCKED degrades to click-stepper mode
clearTimers()
inbox = {
    [1] = { sender = "A", subject = "Gold 1", money = 100, cod = 0, hasItem = 0 },
    [2] = { sender = "B", subject = "Gold 2", money = 200, cod = 0, hasItem = 0 },
}
local stepped = 0
_G.TakeInboxMoney = function(i) stepped = stepped + 1; table.remove(inbox, i) end
MH.Start("all")
eq(stepped, 1, "First mail taken before action blocked")
MH.OnEvent(nil, "ADDON_ACTION_BLOCKED", "MerchantMaster", "TakeInboxMoney")
check(MH.GetState().clickStepper == true, "ADDON_ACTION_BLOCKED switches to clickStepper mode")
eq(MH.bar.refreshBtn:GetText(), "Next", "Row 2 Refresh button relabels to Next in clickStepper mode")
-- MAIL_INBOX_UPDATE must NOT auto-advance in clickStepper mode
MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
eq(stepped, 1, "MAIL_INBOX_UPDATE waits for manual click in clickStepper mode")
-- Clicking Next advances manually
MH.bar.refreshBtn:Click()
eq(stepped, 2, "Clicking Next advances clickStepper manually")

-- 4e. MAIL_CLOSED aborts active batch immediately
MH.OnEvent(nil, "MAIL_CLOSED")
eq(MH.IsActive(), false, "MAIL_CLOSED aborts active batch")

-- 4f. lastCheckInboxAt 60s throttle
local checkInboxCalls = 0
_G.CheckInbox = function() checkInboxCalls = checkInboxCalls + 1 end
local ok1 = MH.RequestRefresh()
eq(ok1, true, "First RequestRefresh calls CheckInbox")
eq(checkInboxCalls, 1, "CheckInbox called once")
local ok2, reason2 = MH.RequestRefresh()
eq(ok2, false, "Immediate second RequestRefresh throttled")
eq(reason2, "cooldown", "Throttle returns cooldown reason")
eq(checkInboxCalls, 1, "CheckInbox not called during 60s cooldown")
advanceTimers(61)
local ok3 = MH.RequestRefresh()
eq(ok3, true, "RequestRefresh succeeds after 60s cooldown")
eq(checkInboxCalls, 2, "CheckInbox called second time after 60s")

-- 4g. InCombatLockdown defers mounting until PLAYER_REGEN_ENABLED
MH.bar = nil
local inCombat = true
_G.InCombatLockdown = function() return inCombat end
MH.OnEvent(nil, "MAIL_SHOW")
eq(MH.bar, nil, "MountOnMailFrame defers during InCombatLockdown")
inCombat = false
MH.OnEvent(nil, "PLAYER_REGEN_ENABLED")
check(MH.bar ~= nil, "PLAYER_REGEN_ENABLED mounts deferred MailHelper bar")

-- 5. Analytics\UI.lua checks (seedTsmBtn legacy gate, TYPES dropdown, other preset, badge colors)
_G.SlashCmdList = _G.SlashCmdList or {}
host.app.activeTab = "an_ledger"
host.app.ui.makeSidebarDrop = function(opts)
    local b = makeFrame("Button")
    b._opts = opts
    return b
end
host.app.ui.makeSidebarCheck = function()
    local b = makeFrame("CheckButton")
    b.SetChecked = function(self, v) self._checked = v end
    b.GetChecked = function(self) return self._checked end
    return b
end
host.app.ui.makeSidebarBtn = function(label)
    local b = makeFrame("Button")
    b:SetText(label)
    return b
end
assert(loadfile(root .. "Analytics/UI.lua"))("MerchantMaster", host)
local UI = host.Analytics.UI
-- Ensure controls exist (normally built on first Register/Mount; build via UI.GetSidebarControls check)
-- Trigger UI control creation if needed via exposed columns / Filters / GetSidebarControls
local origPreset = _G.MerchantMasterDB.anLedgerPreset
_G.MerchantMasterDB.anLedgerPreset = "other"
local otherF = UI.Filters()
check(otherF.types and otherF.types.TRAINER_FEE and otherF.types.GUILD_DEPOSIT and otherF.types.GUILD_WITHDRAW and otherF.types.AH_OUTBID,
    "UI.Filters preset='other' includes TRAINER_FEE, GUILD_DEPOSIT, GUILD_WITHDRAW, AH_OUTBID")
_G.MerchantMasterDB.anLedgerPreset = origPreset

-- Check ledgerTypeBadge colors via UI.Columns.an_ledger type column renderer
local typeCol
for _, col in ipairs(UI.Columns.an_ledger) do
    if col.key == "type" then typeCol = col; break end
end
check(typeCol and type(typeCol.render) == "function", "an_ledger type column renderer exists")
check(typeCol.render({ type = "TRAINER_FEE", total = -500 }):find("ff4245", 1, true) and typeCol.render({ type = "TRAINER_FEE", total = -500 }):find("Trainer Fee", 1, true),
    "TRAINER_FEE badge renders red with Trainer Fee label")
check(typeCol.render({ type = "GUILD_DEPOSIT", total = -1000 }):find("ff4245", 1, true), "GUILD_DEPOSIT badge renders red")
check(typeCol.render({ type = "AH_BID", total = -2000 }):find("ff4245", 1, true), "AH_BID badge renders red")
check(typeCol.render({ type = "GUILD_WITHDRAW", total = 1000 }):find("30d158", 1, true), "GUILD_WITHDRAW badge renders green")
check(typeCol.render({ type = "AH_OUTBID", total = 2000 }):find("30d158", 1, true), "AH_OUTBID badge renders green")

-- Verify UI.GetSidebarControls omits removed seedTsmBtn in pure standalone mode
UI.charBtn = makeFrame("Button")
UI.periodBtn = makeFrame("Button")
UI.typeBtn = makeFrame("Button")
UI.zoneBtn = makeFrame("Button")
UI.itemModeBtn = makeFrame("Button")
UI.portfolioViewBtn = makeFrame("Button")
UI.knownCostCheck = host.app.ui.makeSidebarCheck()
UI.resetFiltersBtn = makeFrame("Button")
_G.TradeSkillMasterDB = { dummy = true }
_G.MerchantMasterLedgerDB.seed = {}
eq(UI.seedTsmBtn, nil, "UI.seedTsmBtn is removed in pure standalone mode")
eq(#UI.GetSidebarControls("an_ledger"), 5, "UI.GetSidebarControls returns 5 standalone ledger controls")

-- =========================================================================
-- 6. Review Fix Regression Tests (BLOCKER #1, #2, #3 & MAJOR #4)
-- =========================================================================

-- 6a. BLOCKER #3: Model.QueryLedger does NOT double-count cash outflow for AH_BID + won AH_BUY(fromBid)
do
    _G.MerchantMasterLedgerDB = {}
    Store.Init()
    local char = "Normal-Horde-Forever-Hero"
    Store.Append({ type = "AH_BID", char = char, itemID = 12363, qty = 2, unit = 30000, total = -60000, time = mockNow, where = "Auction House", extra = { auctionID = 901, isBid = true } })
    Store.Append({ type = "AH_BUY", char = char, itemID = 12363, qty = 2, unit = 30000, total = -60000, time = mockNow + 60, where = "Auction House Mail", extra = { seller = "SellerX", fromBid = true, auctionID = 901 }, skipRecon = true })
    local q = Model.QueryLedger({ period = "all" }, 0, 500)
    eq(q.totals.outflow, 60000, "QueryLedger counts AH_BID + won AH_BUY(fromBid) outflow once (60000, not 120000)")
    eq(q.totals.net, -60000, "QueryLedger net cashflow counts AH_BID + won AH_BUY(fromBid) once (-60000)")
    local bQty, bAvg = Store.Basis("Normal-Horde", 12363)
    eq(bQty, 2, "Won AH_BUY(fromBid) preserves basis qty=2")
    eq(bAvg, 30000, "Won AH_BUY(fromBid) preserves basis avg=30000")
end

-- 6b. BLOCKER #2: Two identical won-auction mails collected before BAG_UPDATE_DELAYED preserve both invoices & full basis qty=2
do
    _G.MerchantMasterLedgerDB = {}
    Store.Init()
    cash = 500000
    bagQty = { [13468] = 0 }
    local winMails = {
        [1] = { sender = "Auction House", subject = "Auction won: Black Lotus", inv = "buyer", name = "Black Lotus", seller = "LotusSeller", bid = 45000, buyout = 45000, count = 1, id = 13468 },
        [2] = { sender = "Auction House", subject = "Auction won: Black Lotus", inv = "buyer", name = "Black Lotus", seller = "LotusSeller", bid = 45000, buyout = 45000, count = 1, id = 13468 },
    }
    _G.ATTACHMENTS_MAX_RECEIVE = 1
    _G.GetInboxNumItems = function() return #winMails end
    _G.GetInboxHeaderInfo = function(i)
        local m = winMails[i]; if not m then return end
        return nil, nil, m.sender, m.subject, 0, 0, 30, 1, false, false
    end
    _G.GetInboxInvoiceInfo = function(i)
        local m = winMails[i]; if not m then return end
        return m.inv, m.name, m.seller, m.bid, m.buyout, 0, 0, 0, 0, 0, m.count
    end
    _G.GetInboxItem = function(i, slot)
        local m = winMails[i]; if not m or slot ~= 1 then return end
        return m.name, m.id, nil, m.count
    end
    _G.GetInboxItemLink = function(i, slot)
        local m = winMails[i]; if not m or slot ~= 1 then return end
        return "|Hitem:" .. tostring(m.id) .. "|h[" .. m.name .. "]|h"
    end

    -- Collect both identical mails before BAG_UPDATE_DELAYED fires (and verify retrying exact same slot 2 dedupes)
    Capture._preTakeMail(2)
    Capture._preTakeMail(2) -- retry of exact same uncollected instance -> deduped
    Capture._preTakeMail(1) -- distinct second identical won-auction mail -> queued!
    bagQty[13468] = 2
    Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local bQty, bAvg = Store.Basis("Normal-Horde", 13468)
    eq(bQty, 2, "Two identical won-auction mails record full basis qty=2 (no collapse)")
    eq(bAvg, 45000, "Two identical won-auction mails record exact avg unit cost=45000")
    eq(#findRows("AH_BUY"), 2, "Two identical won-auction mails append 2 AH_BUY rows")
end

-- 6c. BLOCKER #1: Live hooksecurefunc PostCommodity/PostItem stays unverified & discards on timeout or replacement; confirms on AUCTION_HOUSE_AUCTION_CREATED / OWNED_AUCTIONS_UPDATED
do
    clearTimers()
    _G.MerchantMasterLedgerDB = {}
    Store.Init()
    local ownedCnt = 1
    local secureAH = {
        PostCommodity = function() return true end, -- return value is invisible to hooksecurefunc!
        PostItem = function() return true end,
        ConfirmPostCommodity = function() end,
        ConfirmPostItem = function() end,
        CalculateCommodityDeposit = function() return 200 end,
        CalculateItemDeposit = function() return 200 end,
        GetNumOwnedAuctions = function() return ownedCnt end,
        GetOwnedAuctionInfo = function(idx) return { auctionID = 7700 + idx, itemID = 12363, quantity = 5 } end,
        CancelAuction = function() end,
    }
    local savedAH = _G.C_AuctionHouse
    local savedHook = _G.hooksecurefunc
    _G.C_AuctionHouse = secureAH
    _G.hooksecurefunc = function(tblOrName, keyOrFn, fn)
        if type(tblOrName) == "table" and type(keyOrFn) == "string" and type(fn) == "function" then
            local orig = tblOrName[keyOrFn]
            tblOrName[keyOrFn] = function(...)
                local r1 = orig(...)
                fn(...) -- secure hook does NOT pass return value r1!
                return r1
            end
        end
    end
    Capture.InstallHooks()

    -- Cancelled confirmation dialog under hooksecurefunc -> 30s timeout discards (0 phantom AH_POST)
    secureAH.PostCommodity({ itemID = 12363 }, 1, 5, 50000)
    advanceTimers(35)
    eq(#findRows("AH_POST"), 0, "Secure-hook unverified post discarded on 30s timeout (no phantom AH_POST)")

    -- Replaced unverified post discards previous instead of flushing phantom AH_POST
    secureAH.PostCommodity({ itemID = 12363 }, 1, 5, 50000)
    secureAH.PostItem({ itemID = 13468 }, 1, 1, 80000, 80000)
    eq(#findRows("AH_POST"), 0, "Replacing unverified secure-hook post does not flush phantom AH_POST")

    -- Confirming via AUCTION_HOUSE_AUCTION_CREATED records exactly 1 AH_POST
    Capture.OnEvent(nil, "AUCTION_HOUSE_AUCTION_CREATED", 7702)
    eq(#findRows("AH_POST"), 1, "AUCTION_HOUSE_AUCTION_CREATED confirms secure-hook post")

    -- Confirming via OWNED_AUCTIONS_UPDATED (owned count increased) records AH_POST
    secureAH.PostCommodity({ itemID = 12363 }, 1, 5, 50000)
    ownedCnt = 2
    Capture.OnEvent(nil, "OWNED_AUCTIONS_UPDATED")
    eq(#findRows("AH_POST"), 2, "Matching OWNED_AUCTIONS_UPDATED count increase confirms secure-hook post")

    _G.hooksecurefunc = savedHook
    _G.C_AuctionHouse = savedAH
end

-- 6d. MAJOR #4: MailHelper loots 4 identical auction-sale mails cleanly without hitting MAX_SLOT_RETRIES=2
do
    clearTimers()
    freeBagSlots = 10
    inbox = {}
    for k = 1, 4 do
        inbox[k] = { sender = "Auction House", subject = "Auction successful: Runecloth", money = 5000, cod = 0, hasItem = 0, inv = "seller" }
    end
    _G.GetInboxNumItems = function() return #inbox, #inbox end
    _G.GetInboxHeaderInfo = function(i)
        local m = inbox[i]; if not m then return end
        return nil, nil, m.sender, m.subject, m.money, m.cod, 30, m.hasItem, false, false
    end
    _G.GetInboxInvoiceInfo = function(i)
        local m = inbox[i]; return m and m.inv or nil
    end
    local lootedIdentical = 0
    _G.TakeInboxMoney = function(i)
        lootedIdentical = lootedIdentical + 1
        table.remove(inbox, i)
    end

    MH.OnEvent(nil, "MAIL_SHOW")
    MH.Start("ah_sales")
    local steps = 0
    while MH.IsActive() and steps < 20 do
        steps = steps + 1
        MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    end
    eq(MH.IsActive(), false, "4 identical AH sales batch finishes")
    eq(lootedIdentical, 4, "All 4 identical AH sale mails looted without false MAX_SLOT_RETRIES block")
    eq(#inbox, 0, "Inbox emptied of all 4 identical AH sale mails")
    eq(MH.GetState().skippedBlocked, 0, "0 identical AH sale mails falsely marked blocked")
    eq(MH.GetState().lootedCount, 4, "lootedCount equals 4 for 4 identical AH sale mails")
end

-- 6e. Re-review BLOCKER: Retrying a 45,000c buyer invoice after wasRead/daysLeft flip dedupes cleanly;
--     a second 90,000c invoice for the same item before BAG_UPDATE_DELAYED yields qty=2, avg=67,500c!
do
    _G.MerchantMasterLedgerDB = {}
    Store.Init()
    cash = 500000
    bagQty = { [13468] = 0 }
    local winMails = {
        [1] = { sender = "Auction House", subject = "Auction won: Black Lotus", inv = "buyer", name = "Black Lotus", seller = "SellerB", bid = 90000, buyout = 90000, count = 1, id = 13468, wasRead = false, daysLeft = 30 },
        [2] = { sender = "Auction House", subject = "Auction won: Black Lotus", inv = "buyer", name = "Black Lotus", seller = "SellerA", bid = 45000, buyout = 45000, count = 1, id = 13468, wasRead = false, daysLeft = 30 },
    }
    _G.ATTACHMENTS_MAX_RECEIVE = 1
    _G.GetInboxNumItems = function() return #winMails end
    _G.GetInboxHeaderInfo = function(i)
        local m = winMails[i]; if not m then return end
        return nil, nil, m.sender, m.subject, 0, 0, m.daysLeft, 1, m.wasRead, false
    end
    _G.GetInboxInvoiceInfo = function(i)
        local m = winMails[i]; if not m then return end
        return m.inv, m.name, m.seller, m.bid, m.buyout, 0, 0, 0, 0, 0, m.count
    end
    _G.GetInboxItem = function(i, slot)
        local m = winMails[i]; if not m or slot ~= 1 then return end
        return m.name, m.id, nil, m.count
    end
    _G.GetInboxItemLink = function(i, slot)
        local m = winMails[i]; if not m or slot ~= 1 then return end
        return "|Hitem:" .. tostring(m.id) .. "|h[" .. m.name .. "]|h"
    end

    Capture._preTakeMail(2)
    -- Mutate wasRead & daysLeft on slot 2, then retry slot 2 before staging slot 1 (90,000c)
    winMails[2].wasRead = true
    winMails[2].daysLeft = 29.99
    Capture._preTakeMail(2)
    Capture._preTakeMail(1)
    bagQty[13468] = 2
    Capture.OnEvent(nil, "BAG_UPDATE_DELAYED")
    local bQty, bAvg = Store.Basis("Normal-Horde", 13468)
    eq(bQty, 2, "45,000c (retried after wasRead/daysLeft flip) + 90,000c records basis qty=2")
    eq(bAvg, 67500, "45,000c + 90,000c records exact avg basis 67,500c (not 45,000c)")
    eq(#findRows("AH_BUY"), 2, "Exactly 2 AH_BUY rows recorded (retry deduped)")
end

-- 6f. Re-review MINOR: Shifted blocked mail does not retry again or inflate skippedBlocked when lower slot is looted
do
    clearTimers()
    freeBagSlots = 10
    inbox = {
        [1] = { sender = "Friend", subject = "Healthy Gold", money = 1000, cod = 0, hasItem = 0 },
        [2] = { sender = "Stuck", subject = "Stuck Mail", money = 5000, cod = 0, hasItem = 0 },
    }
    _G.GetInboxNumItems = function() return #inbox, #inbox end
    _G.GetInboxHeaderInfo = function(i)
        local m = inbox[i]; if not m then return end
        return nil, nil, m.sender, m.subject, m.money, m.cod, 30, m.hasItem, false, false
    end
    _G.GetInboxInvoiceInfo = function() return nil end
    local stuckTries, healthyTries = 0, 0
    _G.TakeInboxMoney = function(i)
        local m = inbox[i]
        if m and m.sender == "Stuck" then
            stuckTries = stuckTries + 1
            -- Stuck mail remains in inbox!
        elseif m then
            healthyTries = healthyTries + 1
            table.remove(inbox, i)
        end
    end

    MH.OnEvent(nil, "MAIL_SHOW")
    MH.Start("all")
    -- Attempt 1 on slot 2 (Stuck) -> watchdog -> Attempt 2 on slot 2 (Stuck) -> watchdog -> skips slot 2 & loots slot 1 (Healthy)!
    advanceTimers(1.25)
    advanceTimers(1.25)
    -- Slot 1 was looted and removed; Stuck shifted from index 2 -> index 1. Fire MAIL_INBOX_UPDATE!
    MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    eq(MH.IsActive(), false, "Batch finishes cleanly after looting lower healthy slot")
    eq(healthyTries, 1, "Healthy slot 1 looted once")
    eq(stuckTries, 2, "Shifted blocked mail is NOT retried after shifting down from index 2 to 1")
    eq(MH.GetState().skippedBlocked, 1, "skippedBlocked stays 1 (not inflated to 2 after shift)")
    eq(MH.GetState().lootedCount, 1, "lootedCount reflects only the 1 healthy mail looted")
end

print(string.format("PASS test_mail_and_logging (%d assertions)", assertions))
