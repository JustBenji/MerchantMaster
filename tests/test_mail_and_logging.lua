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
        GetParent = function(self) return self._parent end,
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
                _shown = true,
                _points = {},
                _wordWrap = true,
                _maxLines = nil,
                SetPoint = function(s, ...) s._points[#s._points + 1] = { ... } end,
                ClearAllPoints = function(s) s._points = {} end,
                SetHeight = function(s, h) s._h = h end,
                SetJustifyH = function(s, j) s._justifyH = j end,
                SetJustifyV = function(s, j) s._justifyV = j end,
                SetWordWrap = function(s, w) s._wordWrap = w and true or false end,
                SetMaxLines = function(s, n) s._maxLines = n end,
                GetStringWidth = function(s) return #(s._text or "") * 6 end,
                GetUnboundedStringWidth = function(s) return #(s._text or "") * 6 end,
                SetText = function(s, t) s._text = tostring(t or "") end,
                GetText = function(s) return s._text end,
                SetTextColor = function(s, r, g, b, a) s._color = { r, g, b, a } end,
                SetFont = function() return true end,
                Show = function(s) s._shown = true end,
                Hide = function(s) s._shown = false end,
                IsShown = function(s) return s._shown end,
            }
            return fs
        end,
        CreateTexture = function(self)
            return {
                _texture = nil,
                _color = nil,
                SetPoint = function() end,
                SetSize = function() end,
                SetHeight = function() end,
                SetTexture = function(s, t) s._texture = t end,
                GetTexture = function(s) return s._texture end,
                SetColorTexture = function(s, r, g, b, a) s._color = { r, g, b, a } end,
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
        ASSETS = {
            icon_gear = "Interface\\AddOns\\MerchantMaster\\Assets\\Apple\\icon_gear",
        },
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
        CreatePlateButton = function(parent, text, w, h, opts)
            local b = makeFrame("Button", nil, parent)
            b:SetSize(w, h)
            b:SetText(text)
            b._opts = opts
            b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.fs:SetText(text or "")
            if opts and opts.icon then
                local ic = b:CreateTexture(nil, "ARTWORK")
                ic:SetTexture(opts.icon)
                b._mmIcon = ic
            end
            b.SetActive = function(self, on) self._active = on and true or false end
            return b
        end,
        CreateBadgePill = function(parent, text, variant, opts)
            opts = opts or {}
            local frame = makeFrame("Frame", nil, parent)
            frame:SetHeight(opts.height or 20)
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("CENTER", 0, 0)
            label:SetWordWrap(false)
            local pill = {
                frame = frame,
                label = label,
                variant = variant or "neutral",
            }
            function pill.SetVariant(selfOrVar, varOrText, maybeText)
                local v, t
                if selfOrVar == pill then
                    v, t = varOrText, maybeText
                else
                    v, t = selfOrVar, varOrText
                end
                if v ~= nil then pill.variant = v end
                if t ~= nil then label:SetText(tostring(t)) end
                local strW = label:GetStringWidth()
                local padX = opts.padX or 18
                local minW = opts.minWidth or 24
                -- Intentionally mirror UI_Theme.CreateBadgePill auto-expansion so tests catch overflow
                frame:SetWidth(math.max(minW, math.ceil(strW) + padX))
            end
            pill:SetVariant(variant or "neutral", text or "")
            return pill
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
-- 1. WS1 Pure Standalone Analytics (Store + Capture - zero TSM reads)
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
eq(MH.bar, nil, "Legacy green Mail Helper bar is removed from MailFrame")
check(MH.itemPickerPanel ~= nil and MH.itemPickerPanel:GetWidth() == 280,
    "MailHelper mounts 280px Mail Items picker panel onto MailFrame")
check(MH.itemPickerPanel._points[1] and MH.itemPickerPanel._points[1][1] == "TOPLEFT"
    and MH.itemPickerPanel._points[1][2] == _G.MailFrame
    and MH.itemPickerPanel._points[1][3] == "TOPRIGHT"
    and MH.itemPickerPanel._points[1][4] == 6 and MH.itemPickerPanel._points[1][5] == 0,
    "Mail Items picker anchors to MailFrame TOPRIGHT (6, 0), never below MailFrame")
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
eq(MH.itemPickerPanel.refreshBtn:GetText(), "Next", "Mail Items Refresh button relabels to Next in clickStepper mode")
-- MAIL_INBOX_UPDATE must NOT auto-advance in clickStepper mode
MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
eq(stepped, 1, "MAIL_INBOX_UPDATE waits for manual click in clickStepper mode")
-- Clicking Next advances manually
MH.itemPickerPanel.refreshBtn:Click()
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
MH.itemPickerPanel = nil
MH.presetsPanel = nil
local inCombat = true
_G.InCombatLockdown = function() return inCombat end
MH.OnEvent(nil, "MAIL_SHOW")
eq(MH.itemPickerPanel, nil, "MountOnMailFrame defers itemPickerPanel during InCombatLockdown")
eq(MH.presetsPanel, nil, "MountOnMailFrame defers presetsPanel during InCombatLockdown")
inCombat = false
MH.OnEvent(nil, "PLAYER_REGEN_ENABLED")
check(MH.itemPickerPanel ~= nil and MH.presetsPanel ~= nil,
    "PLAYER_REGEN_ENABLED mounts deferred Mail Items and Mail Recipients panels")
eq(MH.bar, nil, "PLAYER_REGEN_ENABLED does not mount removed MailHelper bar")

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

-- =========================================================================
-- 7. Feature D: Mail Presets Data Model, Surname Normalization & Deduplication
-- =========================================================================
do
    local savedGetRealm = _G.GetRealmName
    local savedGetPlayer = host.GetPlayerFullName
    local savedDBChars = _G.MerchantMasterDB.chars
    local savedMailPresets = _G.MerchantMasterDB.mailPresets

    _G.GetRealmName = function() return "Wild Growth" end
    host.GetPlayerFullName = function() return "Hero Lightbringer", "Hero" end
    _G.MerchantMasterDB.mailPresets = nil
    _G.MerchantMasterDB.chars = {
        ["Normal-Horde-Wild Growth-Hero Lightbringer"] = { name = "Hero Lightbringer", realm = "Wild Growth", economy = "Normal-Horde" },
        ["Normal-Horde-Wild Growth-Elara Vance"] = { name = "Elara Vance", realm = "Wild Growth", economy = "Normal-Horde" },
        ["Normal-Horde-Wild Growth-Goldbank"] = { name = "Goldbank", realm = "Wild Growth", economy = "Normal-Horde" },
        ["PvP-Alliance-Wild Growth-OtherEcon"] = { name = "OtherEcon", realm = "Wild Growth", economy = "PvP-Alliance" },
    }

    local cfg = MH.GetMailPresetsConfig()
    check(type(cfg) == "table" and type(cfg.display) == "table" and type(cfg.byEcon) == "table",
        "GetMailPresetsConfig initializes MerchantMasterDB.mailPresets")
    eq(cfg.display.showIcon, true, "display.showIcon defaults to true")
    eq(cfg.display.showName, true, "display.showName defaults to true")
    eq(cfg.display.showRole, true, "display.showRole defaults to true")
    eq(cfg.display.warnUnsaved, true, "display.warnUnsaved defaults to true")

    -- WoW Forever surname-safe normalization & realm stripping
    eq(MH.SetPresetCharacter("bank", "  Goldbank-WildGrowth  "), "Goldbank", "Strips compact -CurrentRealm and trims outer spaces")
    eq(MH.SetPresetCharacter("auction", "goldbank-Wild Growth"), "goldbank", "Strips spaced -CurrentRealm case-insensitively")
    eq(MH.SetPresetCharacter("alchemy", "  Goldbank "), "Goldbank", "Same char stored under alchemy")
    eq(MH.SetPresetCharacter("cooking", "Goldbank"), "Goldbank", "Same char stored under cooking")
    eq(MH.SetPresetCharacter("mainCrafter", "  Elara Vance-wildgrowth  "), "Elara Vance", "Preserves internal WoW Forever surname space while stripping realm")
    eq(MH.SetPresetCharacter("enchanting", "Elara Vance"), "Elara Vance", "Deduplicates surname character across roles")
    eq(MH.SetPresetCharacter("tailoring", "Hero Lightbringer-WildGrowth"), "Hero Lightbringer", "Stores current player as tailoring alt")
    eq(MH.SetPresetCharacter("engineering", "CrossAlt-OtherRealm"), "CrossAlt-OtherRealm", "Preserves foreign -OtherRealm suffix")

    -- Investment Storage role preset works alongside Bank, Auction, Main Crafter
    eq(MH.SetPresetCharacter("investmentStorage", "  VaultHold-WildGrowth  "), "VaultHold",
        "Investment Storage normalizes character name and strips current realm")
    local okInv, invRec = MH.IsSavedMailRecipient("vaulthold")
    check(okInv == true and invRec and invRec.roleLabel == "Investment Storage" and invRec.icon == 133786,
        "Investment Storage appears cleanly in quick-pick recipient entries")
    MH.SetPresetCharacter("investmentStorage", "")

    -- Economy isolation
    MH.SetPresetCharacter("bank", "AllyBank", "PvP-Alliance")
    local hordeEntries = MH.BuildPresetRecipientEntries("Normal-Horde")
    local allyEntries = MH.BuildPresetRecipientEntries("PvP-Alliance")
    eq(#allyEntries, 1, "PvP-Alliance economy isolated with 1 entry")
    eq(allyEntries[1].name, "AllyBank", "PvP-Alliance entry preserves its own bank")

    -- Deduplication, priority icon, 2-role cap + (+N more), and isSelf
    eq(#hordeEntries, 4, "Normal-Horde deduplicates 8 role assignments into 4 unique characters")
    eq(hordeEntries[1].name, "Goldbank", "First entry is bank priority")
    eq(hordeEntries[1].icon, 133784, "Bank role wins priority icon 133784")
    eq(hordeEntries[1].roleLabel, "Bank / Auction (+2 more)", "Role label caps at 2 roles + (+N more)")
    eq(hordeEntries[1].allRolesText, "Bank, Auction, Alchemy, Cooking", "Full roles preserved for tooltip")
    eq(hordeEntries[1].isSelf, false, "Bank alt is not marked isSelf")

    eq(hordeEntries[2].name, "Elara Vance", "Second entry preserves surname")
    eq(hordeEntries[2].icon, 136241, "Main Crafter role icon 136241")
    eq(hordeEntries[2].roleLabel, "Main Crafter / Enchanting", "2 roles combined cleanly")
    eq(hordeEntries[2].initials, "EV", "2-letter initials use first+last surname initials")

    eq(hordeEntries[3].name, "CrossAlt-OtherRealm", "Engineering entry keeps foreign realm")
    eq(hordeEntries[3].icon, 136243, "Engineering role icon 136243")

    eq(hordeEntries[4].name, "Hero Lightbringer", "Tailoring entry matches self")
    eq(hordeEntries[4].isSelf, true, "Current player entry marked isSelf = true")

    -- IsSavedMailRecipient checks
    local okSaved1, rec1 = MH.IsSavedMailRecipient("elara vance-WildGrowth")
    check(okSaved1 == true and rec1 and rec1.name == "Elara Vance", "IsSavedMailRecipient matches surname + compact realm case-insensitively")
    local okSaved2 = MH.IsSavedMailRecipient("CrossAlt-OtherRealm")
    eq(okSaved2, true, "IsSavedMailRecipient matches foreign realm exact char")
    local okUnsaved = MH.IsSavedMailRecipient("Random Stranger")
    eq(okUnsaved, false, "IsSavedMailRecipient returns false for unsaved recipient")

    -- Known economy characters
    local known = MH.GetKnownEconomyCharacters("Normal-Horde")
    check(#known >= 4 and known[1].isSelf == true and known[1].name == "Hero Lightbringer",
        "GetKnownEconomyCharacters puts self first and filters by economy")
    local sawOtherEcon = false
    for _, k in ipairs(known) do
        if k.name == "OtherEcon" then sawOtherEcon = true end
    end
    eq(sawOtherEcon, false, "GetKnownEconomyCharacters excludes other economies")

    _G.GetRealmName = savedGetRealm
    host.GetPlayerFullName = savedGetPlayer
    _G.MerchantMasterDB.chars = savedDBChars
    _G.MerchantMasterDB.mailPresets = savedMailPresets
end

-- =========================================================================
-- 8 & 9. Feature D: Mailbox Quick-Pick Panels + Unsaved-Recipient Safety Net
-- =========================================================================
do
    -- Save all globals we mock locally
    local savedMailFrame = _G.MailFrame
    local savedSendMailFrame = _G.SendMailFrame
    local savedInboxFrame = _G.InboxFrame
    local savedOpenMailFrame = _G.OpenMailFrame
    local savedNameBox = _G.SendMailNameEditBox
    local savedSubjBox = _G.SendMailSubjectEditBox
    local savedSendBtn = _G.SendMailMailButton
    local savedTab1 = _G.MailFrameTab1
    local savedTab2 = _G.MailFrameTab2
    local savedCanSend = _G.SendMailFrame_CanSend
    local savedGetSendItem = _G.GetSendMailItem
    local savedGetSendLink = _G.GetSendMailItemLink
    local savedSendMail = _G.SendMail
    local savedPopups = _G.StaticPopupDialogs
    local savedPopupShow = _G.StaticPopup_Show
    local savedPopupHide = _G.StaticPopup_Hide
    local savedGetRealm = _G.GetRealmName
    local savedGetPlayer = host.GetPlayerFullName
    local savedMailPresets = _G.MerchantMasterDB.mailPresets
    local savedBar = MH.bar
    local savedPresetsPanel = MH.presetsPanel
    local savedInboxStrip = MH.inboxQuickStrip
    local savedItemPicker = MH.itemPickerPanel
    local savedOpenMailBtn = MH.openMailBtn
    local savedGetInboxNum = _G.GetInboxNumItems
    local savedGetInboxHeader = _G.GetInboxHeaderInfo
    local savedGetInboxItem = _G.GetInboxItem
    local savedGetInboxLink = _G.GetInboxItemLink
    local savedTakeInboxItem = _G.TakeInboxItem
    local savedGetInboxInvoice = _G.GetInboxInvoiceInfo
    local savedCItem = _G.C_Item
    local savedAttachMax = _G.ATTACHMENTS_MAX_RECEIVE
    local savedOpenMailReplyBtn = _G.OpenMailReplyButton

    _G.GetRealmName = function() return "Forever" end
    host.GetPlayerFullName = function() return "Hero", "Hero" end
    _G.MerchantMasterDB.mailPresets = nil
    MH.bar = nil
    MH.presetsPanel = nil
    MH.inboxQuickStrip = nil
    MH.itemPickerPanel = nil
    MH.openMailBtn = nil

    -- Build local Blizzard MailFrame mocks
    local mailFrame = makeFrame("Frame", "MailFrame", nil)
    local sendFrame = makeFrame("Frame", "SendMailFrame", mailFrame)
    local inboxFrame = makeFrame("Frame", "InboxFrame", mailFrame)
    local openMailFrame = makeFrame("Frame", "OpenMailFrame", mailFrame)
    sendFrame:Hide()
    inboxFrame:Show()
    openMailFrame:Hide()

    local nameBox = makeFrame("EditBox", "SendMailNameEditBox", sendFrame)
    local origSetText = nameBox.SetText
    nameBox.SetText = function(self, t)
        origSetText(self, t)
        if self._scripts.OnTextChanged then
            self._scripts.OnTextChanged(self, false)
        end
    end

    local subjFocusCount = 0
    local subjBox = makeFrame("EditBox", "SendMailSubjectEditBox", sendFrame)
    subjBox.SetFocus = function() subjFocusCount = subjFocusCount + 1 end

    local sendMailCalls = {}
    local sendMailFn = function(recipient, subject, body)
        sendMailCalls[#sendMailCalls + 1] = { recipient = recipient, subject = subject, body = body }
    end
    _G.SendMail = sendMailFn

    local sendBtn = makeFrame("Button", "SendMailMailButton", sendFrame)
    sendBtn:SetScript("OnClick", function()
        _G.SendMail(nameBox:GetText(), subjBox:GetText(), "")
    end)

    local tab2Clicks = 0
    local tab1 = makeFrame("Button", "MailFrameTab1", mailFrame)
    local tab2 = makeFrame("Button", "MailFrameTab2", mailFrame)
    tab2:SetScript("OnClick", function()
        tab2Clicks = tab2Clicks + 1
        inboxFrame:Hide()
        sendFrame:Show()
    end)

    local canSendCalls = 0
    _G.SendMailFrame_CanSend = function() canSendCalls = canSendCalls + 1 end

    local sendAttachments = {}
    _G.GetSendMailItem = function(slot)
        local it = sendAttachments[slot]
        if it then return it.name, it.id, 134400, it.count end
    end
    _G.GetSendMailItemLink = function(slot)
        local it = sendAttachments[slot]
        if it then return "|Hitem:" .. tostring(it.id) .. "|h[" .. it.name .. "]|h" end
    end

    local shownPopups = {}
    local hiddenPopups = {}
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, textArg1)
        shownPopups[#shownPopups + 1] = { which = which, arg1 = textArg1 }
        return { which = which }
    end
    _G.StaticPopup_Hide = function(which)
        hiddenPopups[#hiddenPopups + 1] = which
    end

    _G.MailFrame = mailFrame
    _G.SendMailFrame = sendFrame
    _G.InboxFrame = inboxFrame
    _G.OpenMailFrame = openMailFrame
    openMailFrame.GetLeft = function() return 0 end
    local openMailReplyBtn = makeFrame("Button", "OpenMailReplyButton", openMailFrame)
    openMailReplyBtn.GetLeft = function() return 84 end
    _G.OpenMailReplyButton = openMailReplyBtn
    _G.SendMailNameEditBox = nameBox
    _G.SendMailSubjectEditBox = subjBox
    _G.SendMailMailButton = sendBtn
    _G.MailFrameTab1 = tab1
    _G.MailFrameTab2 = tab2

    -- Configure presets (2 non-self + 1 self)
    MH.SetPresetCharacter("bank", "Goldbank")
    MH.SetPresetCharacter("auction", "Elara Vance")
    MH.SetPresetCharacter("alchemy", "Hero")

    local function hasPoint(widget, pt, relFrame, relPt, x, y)
        for _, p in ipairs((widget and widget._points) or {}) do
            if p[1] == pt and p[2] == relFrame and p[3] == relPt and p[4] == x and p[5] == y then
                return true
            end
        end
        return false
    end
    local function hasBottomMailAnchor(widget)
        for _, p in ipairs((widget and widget._points) or {}) do
            if p[2] == mailFrame and (p[3] == "BOTTOMLEFT" or p[3] == "BOTTOMRIGHT") then
                return true
            end
        end
        return false
    end

    -- Open Mailbox (Inbox visible, SendMail hidden)
    MH.OnEvent(nil, "MAIL_SHOW")
    eq(_G.SendMail, sendMailFn, "MailHelper NEVER wraps _G.SendMail (keeps Analytics Capture hook clean)")
    eq(MH.bar, nil, "Legacy green Mail Helper panel is removed (Open All / AH Sales / Expired / Won not shown)")
    check(MH.itemPickerPanel ~= nil and MH.itemPickerPanel._name == "MerchantMasterMailItemsPanel",
        "Mail Items picker panel created with name MerchantMasterMailItemsPanel")
    eq(MH.itemPickerPanel:GetWidth(), 280, "Mail Items picker width is 280px")
    eq(MH.itemPickerPanel.refreshBtn:GetWidth(), 54, "Mail Items Refresh button width is 54px")
    eq(MH.itemPickerPanel.stopBtn:GetWidth(), 44, "Mail Items Stop button width is 44px")
    check(not hasBottomMailAnchor(MH.itemPickerPanel), "Mail Items picker NEVER anchors below MailFrame")

    check(MH.presetsPanel ~= nil and MH.presetsPanel._name == "MerchantMasterMailPresetsPanel",
        "Send Mail presets panel created with name MerchantMasterMailPresetsPanel")
    eq(MH.presetsPanel:GetWidth(), 280, "Mail Recipients presets panel width is 280px")
    check(MH.presetsPanel.statusPill ~= nil and MH.presetsPanel.statusPill.frame:GetWidth() <= 260,
        "Mail Recipients statusPill width is strictly <= 260px")
    eq(MH.presetsPanel.statusPill.label._wordWrap, false, "statusPill label disables word wrap")
    check(hasPoint(MH.presetsPanel.statusPill.label, "LEFT", MH.presetsPanel.statusPill.frame, "LEFT", 10, 0)
        and hasPoint(MH.presetsPanel.statusPill.label, "RIGHT", MH.presetsPanel.statusPill.frame, "RIGHT", -10, 0),
        "statusPill label is strictly clamped inside pill (+10 LEFT .. -10 RIGHT)")
    check(MH.inboxQuickStrip ~= nil, "Inbox quick-pick struct preserved if referenced")
    eq(MH.inboxQuickStrip:IsShown(), false, "Inbox quick strip stays hidden to avoid duplicate Inbox clutter")

    -- InboxFrame stacking: MH.itemPickerPanel on top (MailFrame TOPRIGHT 6,0), MH.presetsPanel cleanly underneath
    eq(MH.itemPickerPanel:IsShown(), true, "Mail Items picker shown on InboxFrame")
    eq(MH.presetsPanel:IsShown(), true, "Mail Recipients shown below Mail Items on InboxFrame when presets exist")
    check(hasPoint(MH.itemPickerPanel, "TOPLEFT", mailFrame, "TOPRIGHT", 6, 0),
        "On InboxFrame, MH.itemPickerPanel anchors at TOPLEFT -> MailFrame TOPRIGHT (6, 0)")
    check(hasPoint(MH.presetsPanel, "TOPLEFT", MH.itemPickerPanel, "BOTTOMLEFT", 0, -6),
        "On InboxFrame, MH.presetsPanel stacks under MH.itemPickerPanel at BOTTOMLEFT (0, -6)")

    -- Opening an inbox mail hides BOTH MH.itemPickerPanel and MH.presetsPanel
    openMailFrame:Show()
    MH.RefreshPresetsUI()
    eq(MH.itemPickerPanel:IsShown(), false, "OpenMailFrame shown hides MH.itemPickerPanel")
    eq(MH.presetsPanel:IsShown(), false, "OpenMailFrame shown hides MH.presetsPanel")
    eq(MH.inboxQuickStrip:IsShown(), false, "OpenMailFrame shown keeps inboxQuickStrip hidden")
    openMailFrame:Hide()
    MH.RefreshPresetsUI()
    eq(MH.itemPickerPanel:IsShown(), true, "Closing OpenMailFrame restores MH.itemPickerPanel on InboxFrame")
    eq(MH.presetsPanel:IsShown(), true, "Closing OpenMailFrame restores MH.presetsPanel on InboxFrame")

    -- Clicking preset row from Inbox switches to SendMail tab, hides itemPickerPanel, and anchors presetsPanel at top
    MH.presetsPanel.buttons[2]:Click()
    eq(tab2Clicks, 1, "Clicking recipient row from Inbox switches to Send Mail tab via MailFrameTab2:Click()")
    eq(nameBox:GetText(), "Elara Vance", "Clicking recipient row fills SendMailNameEditBox")
    check(canSendCalls >= 1, "Clicking recipient row triggers SendMailFrame_CanSend()")
    eq(subjFocusCount, 1, "Clicking recipient row from Inbox focuses SendMailSubjectEditBox")
    eq(MH.presetsPanel:IsShown(), true, "Presets panel shows when SendMailFrame is active")
    eq(MH.itemPickerPanel:IsShown(), false, "Mail Items picker hides when SendMailFrame is active")
    check(hasPoint(MH.presetsPanel, "TOPLEFT", mailFrame, "TOPRIGHT", 6, 0),
        "On SendMailFrame with presets, MH.presetsPanel anchors at TOPLEFT -> MailFrame TOPRIGHT (6, 0)")
    check(not hasBottomMailAnchor(MH.presetsPanel), "On SendMailFrame, MH.presetsPanel NEVER anchors below MailFrame")
    check((MH.presetsPanel.statusFs:GetText() or ""):find("Saved: Auction", 1, true) ~= nil,
        "Status pill shows Saved: Auction for Elara Vance")
    check(MH.presetsPanel.statusPill.frame:GetWidth() <= 260,
        "Saved status pill stays <= 260px wide")

    -- Verify long multi-role Saved pill clamps cleanly inside 260px without overflowing
    MH.SetPresetCharacter("mainCrafter", "Grommash Hellscream")
    MH.SetPresetCharacter("leatherworking", "Grommash Hellscream")
    MH.SetPresetCharacter("blacksmithing", "Grommash Hellscream")
    MH.SetPresetCharacter("engineering", "Grommash Hellscream")
    nameBox:SetText("Grommash Hellscream")
    check(MH.presetsPanel.statusPill.frame:GetWidth() <= 260,
        "Long multi-role Saved status pill stays strictly <= 260px wide")
    check(MH.presetsPanel.statusPill.label:GetStringWidth() <= 240,
        "Long multi-role Saved status pill text fits within 240px inner bounds without overflowing")
    -- Reset test multi-role character so subsequent index assertions stay clean
    MH.SetPresetCharacter("mainCrafter", "")
    MH.SetPresetCharacter("leatherworking", "")
    MH.SetPresetCharacter("blacksmithing", "")
    MH.SetPresetCharacter("engineering", "")
    nameBox:SetText("Elara Vance")

    -- Verify SendMailFrame and InboxFrame visibility when 0 presets are saved
    local savedPresetsBackup = _G.MerchantMasterDB.mailPresets
    _G.MerchantMasterDB.mailPresets = nil
    MH.RefreshPresetsUI()
    eq(MH.presetsPanel:IsShown(), false, "On SendMailFrame with 0 presets, MH.presetsPanel hides")
    eq(MH.itemPickerPanel:IsShown(), false, "On SendMailFrame with 0 presets, MH.itemPickerPanel stays hidden")
    sendFrame:Hide()
    inboxFrame:Show()
    MH.RefreshPresetsUI()
    eq(MH.presetsPanel:IsShown(), false, "On InboxFrame with 0 presets, MH.presetsPanel hides")
    eq(MH.itemPickerPanel:IsShown(), true, "On InboxFrame with 0 presets, MH.itemPickerPanel stays visible")
    check(hasPoint(MH.itemPickerPanel, "TOPLEFT", mailFrame, "TOPRIGHT", 6, 0),
        "On InboxFrame with 0 presets, MH.itemPickerPanel anchors directly at MailFrame TOPRIGHT (6, 0)")
    _G.MerchantMasterDB.mailPresets = savedPresetsBackup
    inboxFrame:Hide()
    sendFrame:Show()
    MH.RefreshPresetsUI()

    -- Display option toggles & 2-letter initials fallback when all 3 unchecked
    MH.SetDisplayOption("showIcon", false)
    MH.SetDisplayOption("showName", false)
    MH.SetDisplayOption("showRole", false)
    eq(MH.presetsPanel.buttons[2].initFs:IsShown(), true, "All 3 display toggles off falls back to 2-letter initials")
    eq(MH.presetsPanel.buttons[2].initFs:GetText(), "EV", "Initials fallback renders EV for Elara Vance")
    MH.SetDisplayOption("showIcon", true)
    MH.SetDisplayOption("showName", true)
    MH.SetDisplayOption("showRole", true)
    eq(MH.presetsPanel.buttons[2].initFs:IsShown(), false, "Re-enabling display toggles hides initials fallback")

    -- Clicking preset panel button fills recipient
    MH.presetsPanel.buttons[1]:Click()
    eq(nameBox:GetText(), "Goldbank", "Clicking Send Mail preset panel button fills Goldbank")

    -- Pagination when > 8 unique characters saved
    MH.SetPresetCharacter("mainCrafter", "AltThree")
    MH.SetPresetCharacter("blacksmithing", "AltFour")
    MH.SetPresetCharacter("enchanting", "AltFive")
    MH.SetPresetCharacter("engineering", "AltSix")
    MH.SetPresetCharacter("leatherworking", "AltSeven")
    MH.SetPresetCharacter("tailoring", "AltEight")
    MH.SetPresetCharacter("cooking", "AltNine")
    eq(MH.presetsPanel.nextBtn:IsShown(), true, "Pagination next button shown when > 8 presets")
    eq(MH.presetsPanel.pageFs:GetText(), "1 / 2", "Pagination displays page 1 / 2")
    MH.presetsPanel.nextBtn:Click()
    eq(MH.presetsPanel.pageFs:GetText(), "2 / 2", "Clicking next advances to page 2 / 2")
    MH.presetsPanel.prevBtn:Click()
    eq(MH.presetsPanel.pageFs:GetText(), "1 / 2", "Clicking prev returns to page 1 / 2")

    -- Safety Net Test 1: Gold-only / text-only mail to unsaved recipient sends WITHOUT popup
    sendAttachments = {}
    nameBox:SetText("Stranger One")
    check((MH.presetsPanel.statusFs:GetText() or ""):find("Unsaved recipient", 1, true) ~= nil,
        "Status pill shows Unsaved recipient for Stranger One")
    shownPopups = {}
    sendMailCalls = {}
    sendBtn:Click()
    eq(#shownPopups, 0, "Gold-only/text-only mail to unsaved recipient does NOT show popup")
    eq(#sendMailCalls, 1, "Gold-only/text-only mail sends immediately")

    -- Safety Net Test 2: Items mailed to SAVED recipient sends WITHOUT popup
    sendAttachments = { [1] = { name = "Black Lotus", id = 13468, count = 2 } }
    eq(MH.HasSendMailItems(), true, "HasSendMailItems returns true when attachment slot 1 has an item")
    nameBox:SetText("Elara Vance-Forever")
    shownPopups = {}
    sendMailCalls = {}
    sendBtn:Click()
    eq(#shownPopups, 0, "Mailing items to saved surname+realm recipient does NOT show popup")
    eq(#sendMailCalls, 1, "Saved recipient item mail sends immediately")

    -- Safety Net Test 3: Items mailed to UNSAVED recipient intercepts & shows confirmation popup
    nameBox:SetText("Random Buyer")
    shownPopups = {}
    hiddenPopups = {}
    sendMailCalls = {}
    sendBtn:Click()
    eq(#sendMailCalls, 0, "Unsaved item mail is suppressed before SendMail runs (zero phantom Capture records)")
    eq(#shownPopups, 1, "Unsaved item mail shows confirmation StaticPopup")
    eq(shownPopups[1].which, "MERCHANTMASTER_CONFIRM_UNSAVED_MAIL", "Popup key is MERCHANTMASTER_CONFIRM_UNSAVED_MAIL")
    eq(shownPopups[1].arg1, "Random Buyer", "Popup formats recipient name")
    local dlg = _G.StaticPopupDialogs["MERCHANTMASTER_CONFIRM_UNSAVED_MAIL"]
    check(type(dlg) == "table" and dlg.button1 == "I am aware" and dlg.button2 == "No",
        "Popup buttons are 'I am aware' and 'No'")
    check(dlg.text == "Are you sure you want to send items towards this character?\n\nRecipient: %s\n(Not in your saved Mail Recipients list)",
        "Popup dialog text matches specification exactly")
    eq(MH.GetState().pendingConfirm, "Random Buyer", "pendingConfirm tracks unsaved recipient")

    -- Clicking "No" (OnCancel) aborts cleanly
    dlg.OnCancel()
    eq(MH.GetState().pendingConfirm, nil, "OnCancel clears pendingConfirm")
    eq(#sendMailCalls, 0, "Cancelling popup sends 0 mails")

    -- Editing recipient name auto-hides popup and clears pendingConfirm
    sendBtn:Click()
    eq(MH.GetState().pendingConfirm, "Random Buyer", "pendingConfirm set before text edit")
    hiddenPopups = {}
    nameBox:SetText("Other Stranger")
    eq(MH.GetState().pendingConfirm, nil, "Editing SendMailNameEditBox clears pendingConfirm")
    eq(hiddenPopups[#hiddenPopups], "MERCHANTMASTER_CONFIRM_UNSAVED_MAIL", "Editing recipient auto-hides popup")

    -- MAIL_SEND_INFO_UPDATE and MAIL_FAILED auto-hide popup
    sendBtn:Click()
    eq(MH.GetState().pendingConfirm, "Other Stranger", "pendingConfirm set for Other Stranger")
    MH.OnEvent(nil, "MAIL_SEND_INFO_UPDATE")
    eq(MH.GetState().pendingConfirm, nil, "MAIL_SEND_INFO_UPDATE clears pendingConfirm")

    -- Clicking "I am aware" (OnAccept) sends ONCE with one-shot bypass and clears bypass immediately
    sendBtn:Click()
    eq(MH.GetState().pendingConfirm, "Other Stranger", "pendingConfirm armed for OnAccept")
    sendMailCalls = {}
    dlg.OnAccept()
    eq(#sendMailCalls, 1, "OnAccept invokes original SendMail button handler once")
    eq(sendMailCalls[1].recipient, "Other Stranger", "OnAccept sends to confirmed unsaved recipient")
    eq(MH.GetState().bypassConfirmRecipient, nil, "One-shot bypassConfirmRecipient cleared immediately after send")
    eq(MH.GetState().pendingConfirm, nil, "pendingConfirm cleared after OnAccept")

    -- Subsequent click to same unsaved recipient still prompts again (bypass was strictly one-shot)
    shownPopups = {}
    sendBtn:Click()
    eq(#shownPopups, 1, "Second send to same unsaved recipient prompts again (one-shot bypass)")

    -- If items removed before OnAccept, OnAccept refuses to send
    sendAttachments = {}
    sendMailCalls = {}
    dlg.OnAccept()
    eq(#sendMailCalls, 0, "OnAccept refuses if attachments were removed before confirm")

    -- Disabling warnUnsaved allows unsaved item mail to send without popup
    sendAttachments = { [1] = { name = "Black Lotus", id = 13468, count = 1 } }
    MH.SetDisplayOption("warnUnsaved", false)
    shownPopups = {}
    sendMailCalls = {}
    sendBtn:Click()
    eq(#shownPopups, 0, "warnUnsaved = false disables unsaved recipient popup")
    eq(#sendMailCalls, 1, "warnUnsaved = false sends item mail immediately")

    -- Mail Items categorized scanner/fetcher + OpenMailFrame "Get all items" button tests
    local mockInbox = {
        [1] = {
            sender = "The Endboss", subject = "Leather & Herbs", money = 0, cod = 0, hasItem = 2,
            atts = {
                [1] = { name = "Thick Leather", id = 4304, icon = 134254, count = 20, quality = 1, classID = 7 },
                [2] = { name = "Wildvine", id = 8153, icon = 134187, count = 20, quality = 1, classID = 7 },
            },
        },
        [2] = {
            sender = "The Endboss", subject = "Lens + More Leather", money = 0, cod = 0, hasItem = 2,
            atts = {
                [1] = { name = "Green Lens", id = 10504, icon = 133022, count = 1, quality = 3, classID = 4 },
                [2] = { name = "Thick Leather", id = 4304, icon = 134254, count = 10, quality = 1, classID = 7 },
            },
        },
        [3] = {
            sender = "Alchemist", subject = "Potions", money = 0, cod = 0, hasItem = 1,
            atts = {
                [1] = { name = "Major Healing Potion", id = 13446, icon = 134834, count = 5, quality = 1, classID = 0 },
            },
        },
        [4] = {
            sender = "Scammer", subject = "COD Trap", money = 0, cod = 50000, hasItem = 1,
            atts = {
                [1] = { name = "Thick Leather", id = 4304, icon = 134254, count = 5, quality = 1, classID = 7 },
            },
        },
    }
    local classByID = {
        [4304] = 7, -- Trade Goods -> mats
        [8153] = 7, -- Trade Goods -> mats
        [10504] = 4, -- Armor -> gear
        [13446] = 0, -- Consumable -> consumable
    }
    _G.C_Item = _G.C_Item or {}
    _G.C_Item.GetItemInfoInstant = function(spec)
        local id = tonumber(spec)
        if not id and type(spec) == "string" then
            id = tonumber(spec:match("item:(%d+)"))
        end
        if not id or not classByID[id] then return nil end
        return id, "Item", "Sub", "", 134400, classByID[id], 0
    end
    _G.ATTACHMENTS_MAX_RECEIVE = 12
    _G.GetInboxNumItems = function() return #mockInbox, #mockInbox end
    _G.GetInboxHeaderInfo = function(i)
        local m = mockInbox[i]
        if not m then return end
        local count = 0
        for _ in pairs(m.atts or {}) do count = count + 1 end
        return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, 30, count, false, false
    end
    _G.GetInboxInvoiceInfo = function() return nil end
    _G.GetInboxItem = function(i, att)
        local m = mockInbox[i]
        local a = m and m.atts and m.atts[att]
        if not a then return end
        return a.name, a.id, a.icon, a.count, a.quality or 1, true
    end
    _G.GetInboxItemLink = function(i, att)
        local m = mockInbox[i]
        local a = m and m.atts and m.atts[att]
        if not a then return end
        return "|Hitem:" .. tostring(a.id) .. "|h[" .. a.name .. "]|h"
    end
    local takenLog = {}
    _G.TakeInboxItem = function(mailID, attIndex)
        local m = mockInbox[mailID]
        local a = m and m.atts and m.atts[attIndex]
        if a then
            takenLog[#takenLog + 1] = { mailID = mailID, attIndex = attIndex, itemID = a.id, count = a.count }
            m.atts[attIndex] = nil
            local left = false
            for _ in pairs(m.atts) do left = true break end
            if not left and (m.money or 0) == 0 then
                table.remove(mockInbox, mailID)
            end
        end
    end

    -- ScanInboxItems categorizes Mats / Gear / Cons and ignores COD attachments
    local groups, catCounts = MH.ScanInboxItems()
    eq(#groups, 4, "ScanInboxItems finds 4 distinct non-COD items across inbox")
    eq(catCounts.all, 4, "ScanInboxItems All count is 4")
    eq(catCounts.mats, 2, "ScanInboxItems Mats count is 2 (Thick Leather + Wildvine)")
    eq(catCounts.gear, 1, "ScanInboxItems Gear count is 1 (Green Lens)")
    eq(catCounts.consumable, 1, "ScanInboxItems Cons count is 1 (Major Healing Potion)")
    local leatherGrp
    for _, g in ipairs(groups) do
        if g.itemID == 4304 then leatherGrp = g break end
    end
    check(leatherGrp ~= nil and leatherGrp.totalQty == 30 and leatherGrp.stackCount == 2 and leatherGrp.mailCount == 2,
        "ScanInboxItems aggregates Thick Leather totalQty=30 across 2 non-COD mails (ignoring COD mail)")

    MH.SetItemCategory("mats")
    eq(MH.GetState().itemCategory, "mats", "MH.SetItemCategory switches Mail Items category to mats")
    MH.SetItemCategory("all")
    MH.RefreshItemPickerUI()

    -- Clicking Mail Items row collects ONLY 1 stack; clicking per-row "Get All" fetches all stacks
    local leatherRow = nil
    for _, r in ipairs((MH.itemPickerPanel and MH.itemPickerPanel.rows) or {}) do
        if r._group and r._group.itemID == 4304 then leatherRow = r break end
    end
    check(leatherRow ~= nil and leatherRow.getAllBtn ~= nil and leatherRow.getAllBtn:GetText() == "Get All",
        "Mail Items Thick Leather row mounts per-row 'Get All' button")
    takenLog = {}
    freeBagSlots = 10
    leatherRow:Click()
    MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    eq(MH.IsActive(), false, "Clicking Mail Items row stops after taking 1 stack")
    eq(#takenLog, 1, "Single row click took exactly 1 stack")
    eq(MH.GetState().fetchedUnits, 10, "Single row click fetched only 10 units from 1 stack")
    check(mockInbox[1].atts[1] ~= nil and mockInbox[1].atts[1].count == 20,
        "Remaining Thick Leather stack (20x) on Mail 1 was left untouched after 1-stack click")

    -- Restore Mail 2 Thick Leather stack and test clicking per-row "Get All" button
    mockInbox[2].atts[2] = { name = "Thick Leather", id = 4304, icon = 134254, count = 10, quality = 1, classID = 7 }
    MH.RefreshItemPickerUI()
    leatherRow = nil
    for _, r in ipairs((MH.itemPickerPanel and MH.itemPickerPanel.rows) or {}) do
        if r._group and r._group.itemID == 4304 then leatherRow = r break end
    end
    takenLog = {}
    leatherRow.getAllBtn:Click()
    local fGuard = 0
    while MH.IsActive() and fGuard < 20 do
        fGuard = fGuard + 1
        MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    end
    eq(MH.IsActive(), false, "Row Get All button fetch finishes cleanly")
    eq(#takenLog, 2, "Row Get All looted both non-COD Thick Leather attachments")
    eq(MH.GetState().fetchedUnits, 30, "Row Get All fetched all 30 units across stacks")
    -- Mail 4 (COD) and non-matching items remained untouched
    check(mockInbox[#mockInbox].sender == "Scammer", "COD mail remained untouched during item fetch")

    -- OpenMailFrame compact square Baron crimson "Get All" button mounts left of OpenMailReplyButton
    inboxFrame:Show()
    sendFrame:Hide()
    openMailFrame:Show()
    inboxFrame.openMailID = 2
    MH.MountOpenMailButton()
    MH.UpdateOpenMailButton()
    check(MH.openMailBtn ~= nil and MH.openMailBtn:GetText() == "Get All",
        "OpenMailFrame mounts square crimson 'Get All' button")
    eq(MH.openMailBtn:GetHeight(), 21, "OpenMail Get All button height is compact 21px")
    check(MH.openMailBtn:GetWidth() <= 68, "OpenMail Get All button width fits compact <= 68px")
    check(MH.openMailBtn._cushionTex ~= nil, "OpenMail Get All button carries Baron cushion texture layer")
    check(hasPoint(MH.openMailBtn, "RIGHT", openMailReplyBtn, "LEFT", -4, 0),
        "OpenMail Get All button anchors immediately left of OpenMailReplyButton")
    eq(MH.openMailBtn:IsShown(), true, "Get All button shows when open mail has attachments")
    local openSlots, openUnits = MH.CountOpenMailItems(2)
    eq(openSlots, 1, "Mail 2 now has 1 remaining attachment slot (Green Lens)")
    eq(openUnits, 1, "Mail 2 now has 1 remaining attachment unit")

    takenLog = {}
    MH.openMailBtn:Click()
    local omGuard = 0
    while MH.IsActive() and omGuard < 10 do
        omGuard = omGuard + 1
        MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    end
    eq(#takenLog, 1, "Clicking Get All looted the remaining attachment on open mail")
    eq(takenLog[1].itemID, 10504, "Get All looted Green Lens from open mail")

    openMailFrame:Hide()
    inboxFrame.openMailID = nil

    -- MAIL_CLOSED clears confirmation and hides panels
    MH.OnEvent(nil, "MAIL_CLOSED")
    eq(MH.bar, nil, "MAIL_CLOSED keeps removed Mail Helper bar nil")
    eq(MH.itemPickerPanel:IsShown(), false, "MAIL_CLOSED hides Mail Items picker panel")
    eq(MH.presetsPanel:IsShown(), false, "MAIL_CLOSED hides presets panel")
    eq(MH.inboxQuickStrip:IsShown(), false, "MAIL_CLOSED hides inbox quick strip")
    if MH.openMailBtn then
        eq(MH.openMailBtn:IsShown(), false, "MAIL_CLOSED hides OpenMail Get all items button")
    end

    -- Restore all mocked globals cleanly
    _G.MailFrame = savedMailFrame
    _G.SendMailFrame = savedSendMailFrame
    _G.InboxFrame = savedInboxFrame
    _G.OpenMailFrame = savedOpenMailFrame
    _G.SendMailNameEditBox = savedNameBox
    _G.SendMailSubjectEditBox = savedSubjBox
    _G.SendMailMailButton = savedSendBtn
    _G.MailFrameTab1 = savedTab1
    _G.MailFrameTab2 = savedTab2
    _G.SendMailFrame_CanSend = savedCanSend
    _G.GetSendMailItem = savedGetSendItem
    _G.GetSendMailItemLink = savedGetSendLink
    _G.SendMail = savedSendMail
    _G.StaticPopupDialogs = savedPopups
    _G.StaticPopup_Show = savedPopupShow
    _G.StaticPopup_Hide = savedPopupHide
    _G.GetRealmName = savedGetRealm
    host.GetPlayerFullName = savedGetPlayer
    _G.MerchantMasterDB.mailPresets = savedMailPresets
    _G.GetInboxNumItems = savedGetInboxNum
    _G.GetInboxHeaderInfo = savedGetInboxHeader
    _G.GetInboxItem = savedGetInboxItem
    _G.GetInboxItemLink = savedGetInboxLink
    _G.TakeInboxItem = savedTakeInboxItem
    _G.GetInboxInvoiceInfo = savedGetInboxInvoice
    _G.C_Item = savedCItem
    _G.ATTACHMENTS_MAX_RECEIVE = savedAttachMax
    _G.OpenMailReplyButton = savedOpenMailReplyBtn
    MH.bar = savedBar
    MH.presetsPanel = savedPresetsPanel
    MH.inboxQuickStrip = savedInboxStrip
    MH.itemPickerPanel = savedItemPicker
    MH.openMailBtn = savedOpenMailBtn
end

-- =========================================================================
-- 10. Mailbox Fixes: Settings Gear Icon, Refresh Timeout/Reset & Gold Row
-- =========================================================================
do
    local savedMailFrame = _G.MailFrame
    local savedSendMailFrame = _G.SendMailFrame
    local savedInboxFrame = _G.InboxFrame
    local savedOpenMailFrame = _G.OpenMailFrame
    local savedGetInboxNum = _G.GetInboxNumItems
    local savedGetInboxHeader = _G.GetInboxHeaderInfo
    local savedGetInboxItem = _G.GetInboxItem
    local savedGetInboxLink = _G.GetInboxItemLink
    local savedGetInboxInvoice = _G.GetInboxInvoiceInfo
    local savedTakeInboxMoney = _G.TakeInboxMoney
    local savedTakeInboxItem = _G.TakeInboxItem
    local savedCheckInbox = _G.CheckInbox
    local savedCItem = _G.C_Item
    local savedAttachMax = _G.ATTACHMENTS_MAX_RECEIVE
    local savedContainer = _G.C_Container
    local savedNumBagSlots = _G.NUM_BAG_SLOTS
    local savedBar = MH.bar
    local savedPresetsPanel = MH.presetsPanel
    local savedInboxStrip = MH.inboxQuickStrip
    local savedItemPicker = MH.itemPickerPanel
    local savedOpenMailBtn = MH.openMailBtn

    clearTimers()
    advanceTimers(120) -- ensure RequestRefresh 60s cooldown is clear

    local mailFrame = makeFrame("Frame", "MailFrame", nil)
    local inboxFrame = makeFrame("Frame", "InboxFrame", mailFrame)
    local sendFrame = makeFrame("Frame", "SendMailFrame", mailFrame)
    local openMailFrame = makeFrame("Frame", "OpenMailFrame", mailFrame)
    inboxFrame:Show()
    sendFrame:Hide()
    openMailFrame:Hide()
    _G.MailFrame = mailFrame
    _G.InboxFrame = inboxFrame
    _G.SendMailFrame = sendFrame
    _G.OpenMailFrame = openMailFrame

    MH.bar = nil
    MH.presetsPanel = nil
    MH.inboxQuickStrip = nil
    MH.itemPickerPanel = nil
    MH.openMailBtn = nil

    local bagFree = 10
    _G.NUM_BAG_SLOTS = 4
    _G.C_Container = {
        GetContainerNumFreeSlots = function(bag)
            if bag == 0 then return bagFree, 0 end
            return 0, 0
        end,
    }
    _G.ATTACHMENTS_MAX_RECEIVE = 12
    _G.C_Item = {
        GetItemInfoInstant = function(spec)
            local id = tonumber(spec) or (type(spec) == "string" and tonumber(spec:match("item:(%d+)")))
            if id == 4304 or id == 8153 then return id, "Item", "Sub", "", 134400, 7, 0 end
            if id == 10504 then return id, "Item", "Sub", "", 134400, 4, 0 end
            if id == 13446 then return id, "Item", "Sub", "", 134400, 0, 0 end
            return nil
        end,
    }

    -- Item-only inbox still produces #groups == 4 unchanged
    local box = {
        [1] = {
            sender = "The Endboss", subject = "Mats", money = 0, cod = 0,
            atts = {
                [1] = { name = "Thick Leather", id = 4304, icon = 134254, count = 20, quality = 1 },
                [2] = { name = "Wildvine", id = 8153, icon = 134187, count = 10, quality = 1 },
            },
        },
        [2] = {
            sender = "Armorer", subject = "Gear", money = 0, cod = 0,
            atts = {
                [1] = { name = "Green Lens", id = 10504, icon = 133022, count = 1, quality = 3 },
            },
        },
        [3] = {
            sender = "Alchemist", subject = "Pots", money = 0, cod = 0,
            atts = {
                [1] = { name = "Major Healing Potion", id = 13446, icon = 134834, count = 5, quality = 1 },
            },
        },
    }
    _G.GetInboxNumItems = function() return #box, #box end
    _G.GetInboxHeaderInfo = function(i)
        local m = box[i]
        if not m then return end
        local cnt = 0
        for _ in pairs(m.atts or {}) do cnt = cnt + 1 end
        return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, 30, cnt, false, false
    end
    _G.GetInboxInvoiceInfo = function() return nil end
    _G.GetInboxItem = function(i, att)
        local m = box[i]
        local a = m and m.atts and m.atts[att]
        if not a then return end
        return a.name, a.id, a.icon, a.count, a.quality or 1, true
    end
    _G.GetInboxItemLink = function(i, att)
        local m = box[i]
        local a = m and m.atts and m.atts[att]
        if not a then return end
        return "|Hitem:" .. tostring(a.id) .. "|h[" .. a.name .. "]|h"
    end

    local checkCalls = 0
    _G.CheckInbox = function() checkCalls = checkCalls + 1 end

    MH.OnEvent(nil, "MAIL_SHOW")

    -- 10.1. MH.presetsPanel.settingsBtn uses icon_gear (not "*" fallback)
    local gearBtn = MH.presetsPanel and MH.presetsPanel.settingsBtn
    check(gearBtn ~= nil, "presetsPanel.settingsBtn exists")
    eq(gearBtn._opts and gearBtn._opts.icon, host.Theme.ASSETS.icon_gear,
        "presetsPanel.settingsBtn icon option equals ns.Theme.ASSETS.icon_gear")
    check(gearBtn._mmIcon ~= nil and gearBtn._mmIcon:GetTexture() == host.Theme.ASSETS.icon_gear,
        "presetsPanel.settingsBtn._mmIcon texture equals ns.Theme.ASSETS.icon_gear")
    check((gearBtn.fs and gearBtn.fs:GetText() or "") ~= "*",
        "presetsPanel.settingsBtn does NOT fall back to '*' text")

    -- 10.2. RequestRefresh() clears "Refreshing inbox..." on MAIL_INBOX_UPDATE AND on 2.1s timer fallback
    local itemOnlyGroups = MH.ScanInboxItems()
    eq(#itemOnlyGroups, 4, "Item-only inbox keeps ScanInboxItems returning #groups == 4 unchanged")

    local r1 = MH.RequestRefresh()
    eq(r1, true, "RequestRefresh succeeds")
    eq(MH.GetState().refreshPending, true, "RequestRefresh arms state.refreshPending")
    eq(MH.GetState().statusText, "Refreshing inbox...", "RequestRefresh sets 'Refreshing inbox...' status")
    MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    eq(MH.GetState().refreshPending, false, "MAIL_INBOX_UPDATE clears state.refreshPending")
    check(MH.GetState().statusText ~= "Refreshing inbox...",
        "MAIL_INBOX_UPDATE clears 'Refreshing inbox...' status")
    check((MH.GetState().statusText or ""):find("4 items ready", 1, true) ~= nil,
        "MAIL_INBOX_UPDATE restores ready item summary")

    advanceTimers(65)
    local r2 = MH.RequestRefresh()
    eq(r2, true, "Second RequestRefresh after 60s succeeds")
    eq(MH.GetState().refreshPending, true, "Second RequestRefresh arms state.refreshPending")
    eq(MH.GetState().statusText, "Refreshing inbox...", "Second RequestRefresh shows 'Refreshing inbox...'")
    -- Blizzard never fires MAIL_INBOX_UPDATE -> 2.1s watchdog clears it cleanly!
    advanceTimers(2.1)
    eq(MH.GetState().refreshPending, false, "2.1s fallback timer clears state.refreshPending when MAIL_INBOX_UPDATE never fires")
    check(MH.GetState().statusText ~= "Refreshing inbox...",
        "2.1s fallback timer clears 'Refreshing inbox...' (never stuck)")
    check((MH.GetState().statusText or ""):find("4 items ready", 1, true) ~= nil,
        "2.1s fallback timer restores ready summary")

    -- Empty inbox timeout also clears "Refreshing inbox..." to "Inbox up to date"
    local savedBoxBackup = box
    box = {}
    advanceTimers(65)
    MH.RequestRefresh()
    eq(MH.GetState().statusText, "Refreshing inbox...", "Empty inbox RequestRefresh starts with 'Refreshing inbox...'")
    advanceTimers(2.1)
    eq(MH.GetState().refreshPending, false, "Empty inbox 2.1s timer clears refreshPending")
    eq(MH.GetState().statusText, "Inbox up to date", "Empty inbox 2.1s timer sets 'Inbox up to date'")
    eq(MH.itemPickerPanel.emptyFs:GetText(), "No items or gold in inbox",
        "Empty inbox label reads 'No items or gold in inbox'")
    box = savedBoxBackup

    -- MAIL_CLOSED clears refreshPending
    advanceTimers(65)
    MH.RequestRefresh()
    eq(MH.GetState().refreshPending, true, "refreshPending armed before MAIL_CLOSED")
    MH.OnEvent(nil, "MAIL_CLOSED")
    eq(MH.GetState().refreshPending, false, "MAIL_CLOSED clears state.refreshPending")

    -- 10.3. ScanInboxItems detects non-COD gold-only + hybrid mail, ignores COD gold, prepends Gold row
    box = {
        [1] = {
            sender = "Buyer", subject = "Gold Only", money = 123400, cod = 0, -- 12g 34s
            atts = {},
        },
        [2] = {
            sender = "Alt", subject = "Hybrid Mail", money = 50000, cod = 0, -- 5g 00s + Thick Leather
            atts = {
                [1] = { name = "Thick Leather", id = 4304, icon = 134254, count = 20, quality = 1 },
            },
        },
        [3] = {
            sender = "Scammer", subject = "COD Trap", money = 999900, cod = 50000,
            atts = {
                [1] = { name = "Wildvine", id = 8153, icon = 134187, count = 5, quality = 1 },
            },
        },
    }

    MH.OnEvent(nil, "MAIL_SHOW")
    MH.SetItemCategory("all")
    local mixedGroups, mixedCounts, mixedMeta = MH.ScanInboxItems()
    eq(#mixedGroups, 2, "Mixed inbox produces 2 groups (Gold + Thick Leather, ignoring COD mail)")
    eq(mixedGroups[1].isGold, true, "ScanInboxItems prepends Gold row at index 1 under All")
    eq(mixedGroups[1].name, "Gold", "Gold group name is 'Gold'")
    eq(mixedGroups[1].category, "other", "Gold group category is 'other'")
    eq(mixedGroups[1].totalCopper, 173400, "Gold group sums non-COD gold-only + hybrid mail (173400c, ignoring COD)")
    eq(mixedGroups[1].mailCount, 2, "Gold group mailCount is 2 (gold-only + hybrid)")
    eq(mixedCounts.all, 2, "catCounts.all includes Gold + Thick Leather")
    eq(mixedCounts.other, 1, "catCounts.other includes Gold")
    eq(mixedCounts.mats, 1, "catCounts.mats includes Thick Leather")
    eq(mixedMeta.totalGoldCopper, 173400, "meta.totalGoldCopper is 173400")
    eq(mixedMeta.codSkipped, 1, "meta.codSkipped counts 1 COD mail")

    -- Verify Gold row UI styling + mixed Ready status summary
    MH.RefreshItemPickerUI()
    local goldRow = MH.itemPickerPanel.rows[1]
    check(goldRow ~= nil and goldRow._group and goldRow._group.isGold, "Row 1 in picker is Gold row")
    eq(goldRow.iconTex:GetTexture(), 133784, "Gold row icon texture is 133784")
    eq(goldRow.nameFs:GetText(), "Gold", "Gold row name text is 'Gold'")
    check(goldRow.nameFs._color and goldRow.nameFs._color[1] == 1.0 and goldRow.nameFs._color[2] == 0.82,
        "Gold row name colored gold")
    eq(goldRow.qtyFs:GetText(), "17g 34s (2m)", "Gold row qtyFs formats copper + mail count '(2m)'")
    check(goldRow.qtyFs._color and goldRow.qtyFs._color[1] == 1.0 and goldRow.qtyFs._color[2] == 0.82,
        "Gold row qtyFs colored gold")
    check((MH.GetState().statusText or ""):find("1 item + 17g 34s ready", 1, true) ~= nil,
        "Ready status shows mixed '1 item + 17g 34s ready'")

    -- Gold appears under Other category filter too
    MH.SetItemCategory("other")
    local otherRow = MH.itemPickerPanel.rows[1]
    check(otherRow ~= nil and otherRow._group and otherRow._group.isGold,
        "Gold row appears at index 1 under 'Other' category")
    eq(MH.itemPickerPanel.rows[2]:IsShown(), false, "Only Gold row shown under 'Other' category")
    MH.SetItemCategory("all")

    -- 10.4. Clicking Gold row calls TakeInboxMoney ONCE & leaves attached items untouched;
    --       Clicking Gold Get All collects all non-COD gold even when freeBagSlots = 0, leaving items & COD untouched
    local moneyTakeLog, itemTakeLog = {}, {}
    _G.TakeInboxMoney = function(mailID)
        local m = box[mailID]
        moneyTakeLog[#moneyTakeLog + 1] = { mailID = mailID, money = m and m.money or 0 }
        if m then
            m.money = 0
            local hasAtt = false
            for _ in pairs(m.atts or {}) do hasAtt = true break end
            if not hasAtt then
                table.remove(box, mailID)
            end
        end
    end
    _G.TakeInboxItem = function(mailID, attIndex)
        itemTakeLog[#itemTakeLog + 1] = { mailID = mailID, attIndex = attIndex }
    end

    bagFree = 0
    goldRow = MH.itemPickerPanel.rows[1]
    check(goldRow._group and goldRow._group.isGold, "Gold row armed for single-click test")
    goldRow:Click()
    eq(#moneyTakeLog, 1, "Clicking Gold row calls TakeInboxMoney ONCE before MAIL_INBOX_UPDATE")
    eq(#itemTakeLog, 0, "Clicking Gold row NEVER calls TakeInboxItem")
    MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    eq(MH.IsActive(), false, "Clicking Gold row stops after taking gold from 1 mail")
    eq(#moneyTakeLog, 1, "Clicking Gold row took gold from only 1 mail")
    eq(#itemTakeLog, 0, "Clicking Gold row left all item attachments untouched")

    -- Remaining non-COD mail still has its 50,000c (or 123,400c depending on reverse order) + items intact;
    -- test Gold-only ready status and Gold Get All with 2 remaining non-COD gold mails & freeBagSlots = 0!
    box = {
        [1] = {
            sender = "Buyer1", subject = "Gold 1", money = 25000, cod = 0, atts = {},
        },
        [2] = {
            sender = "Alt", subject = "Hybrid Mail", money = 50000, cod = 0,
            atts = {
                [1] = { name = "Thick Leather", id = 4304, icon = 134254, count = 20, quality = 1 },
            },
        },
        [3] = {
            sender = "Scammer", subject = "COD Trap", money = 999900, cod = 50000,
            atts = {
                [1] = { name = "Wildvine", id = 8153, icon = 134187, count = 5, quality = 1 },
            },
        },
    }
    MH.OnEvent(nil, "MAIL_SHOW")
    MH.RefreshItemPickerUI()

    moneyTakeLog, itemTakeLog = {}, {}
    bagFree = 0
    goldRow = MH.itemPickerPanel.rows[1]
    goldRow.getAllBtn:Click()
    local gGuard = 0
    while MH.IsActive() and gGuard < 20 do
        gGuard = gGuard + 1
        MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
    end
    eq(MH.IsActive(), false, "Gold Get All finishes cleanly with freeBagSlots = 0")
    eq(#moneyTakeLog, 2, "Gold Get All collected gold from both non-COD mails (gold-only + hybrid) with freeBagSlots = 0")
    eq(#itemTakeLog, 0, "Gold Get All NEVER called TakeInboxItem")
    eq(MH.GetState().lootedCopper, 75000, "Gold Get All looted exact 75,000c (2g 50s + 5g)")
    -- Both Thick Leather on hybrid mail and COD trap mail remain completely untouched!
    eq(#box, 2, "Gold-only mail removed; hybrid mail and COD mail remain in inbox")
    check(box[1].sender == "Alt" and box[1].money == 0 and box[1].atts[1].count == 20,
        "Hybrid mail had its gold collected and its 20x Thick Leather left untouched")
    check(box[2].sender == "Scammer" and box[2].money == 999900 and box[2].cod == 50000,
        "COD mail gold and items left completely untouched")

    -- Gold-only ready status check (when inbox has only non-COD gold, no items)
    box = {
        [1] = { sender = "Buyer1", subject = "Gold A", money = 30000, cod = 0, atts = {} },
        [2] = { sender = "Buyer2", subject = "Gold B", money = 20000, cod = 0, atts = {} },
    }
    MH.OnEvent(nil, "MAIL_SHOW")
    MH.RefreshItemPickerUI()
    eq(MH.GetState().statusText, "5g 00s in 2 mails ready",
        "Gold-only inbox shows '5g 00s in 2 mails ready'")

    -- Clicking Gold Get All a second time while already active stops via MH.Stop("user_stop")
    goldRow = MH.itemPickerPanel.rows[1]
    goldRow.getAllBtn:Click()
    eq(MH.IsActive(), true, "Gold Get All starts active fetch")
    eq(goldRow.getAllBtn:GetText(), "Stop", "Active Gold Get All button relabels to Stop")
    goldRow.getAllBtn:Click()
    eq(MH.IsActive(), false, "Clicking Gold Stop button cancels active gold_only fetch")

    MH.OnEvent(nil, "MAIL_CLOSED")

    _G.MailFrame = savedMailFrame
    _G.SendMailFrame = savedSendMailFrame
    _G.InboxFrame = savedInboxFrame
    _G.OpenMailFrame = savedOpenMailFrame
    _G.GetInboxNumItems = savedGetInboxNum
    _G.GetInboxHeaderInfo = savedGetInboxHeader
    _G.GetInboxItem = savedGetInboxItem
    _G.GetInboxItemLink = savedGetInboxLink
    _G.GetInboxInvoiceInfo = savedGetInboxInvoice
    _G.TakeInboxMoney = savedTakeInboxMoney
    _G.TakeInboxItem = savedTakeInboxItem
    _G.CheckInbox = savedCheckInbox
    _G.C_Item = savedCItem
    _G.ATTACHMENTS_MAX_RECEIVE = savedAttachMax
    _G.C_Container = savedContainer
    _G.NUM_BAG_SLOTS = savedNumBagSlots
    MH.bar = savedBar
    MH.presetsPanel = savedPresetsPanel
    MH.inboxQuickStrip = savedInboxStrip
    MH.itemPickerPanel = savedItemPicker
    MH.openMailBtn = savedOpenMailBtn
end

-- Section 11: Mail GetAll per-line efficiency & zero-slow-start regression tests
do
    local savedMailFrame = _G.MailFrame
    local savedInboxFrame = _G.InboxFrame
    local savedSendFrame = _G.SendMailFrame
    local savedOpenFrame = _G.OpenMailFrame
    local savedGetNum = _G.GetInboxNumItems
    local savedGetHdr = _G.GetInboxHeaderInfo
    local savedGetInv = _G.GetInboxInvoiceInfo
    local savedGetItem = _G.GetInboxItem
    local savedGetLink = _G.GetInboxItemLink
    local savedGetText = _G.GetInboxText
    local savedTakeItem = _G.TakeInboxItem
    local savedTakeMoney = _G.TakeInboxMoney
    local savedCont = _G.C_Container
    local savedCItem = _G.C_Item
    local savedAttachMax = _G.ATTACHMENTS_MAX_RECEIVE
    local savedPickerFn = MH.RefreshItemPickerUI
    local savedPresetsFn = MH.RefreshPresetsUI

    local function runGetAllPerfCase(buildInbox, mode)
        local inbox = buildInbox()
        local counters = { hdr = 0, inv = 0, item = 0, link = 0, text = 0, picker = 0, presets = 0, looted = 0 }
        MH.RefreshItemPickerUI = function(...)
            counters.picker = counters.picker + 1
            return savedPickerFn(...)
        end
        MH.RefreshPresetsUI = function(...)
            counters.presets = counters.presets + 1
            return savedPresetsFn(...)
        end
        _G.MailFrame = { IsShown = function() return true end }
        _G.InboxFrame = { IsShown = function() return true end }
        _G.SendMailFrame = { IsShown = function() return false end }
        _G.OpenMailFrame = { IsShown = function() return false end }
        _G.ATTACHMENTS_MAX_RECEIVE = 12
        _G.C_Item = {
            GetItemInfoInstant = function(x)
                local id = (type(x) == "number" and x) or (type(x) == "string" and tonumber(x:match("item:(%d+)"))) or 13463
                return id, "Trade Goods", "Herb", "", 134400, 7, 9
            end,
        }
        _G.C_Container = { GetContainerNumFreeSlots = function() return 24, 0 end }
        _G.GetInboxNumItems = function() return #inbox, #inbox end
        _G.GetInboxHeaderInfo = function(i)
            counters.hdr = counters.hdr + 1
            local m = inbox[i]
            if not m then return end
            local c = 0
            for _ in pairs(m.atts or {}) do c = c + 1 end
            return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, 29, c, false, false
        end
        _G.GetInboxInvoiceInfo = function(i)
            counters.inv = counters.inv + 1
            local m = inbox[i]
            return m and m.invoiceType or nil
        end
        _G.GetInboxItem = function(i, s)
            counters.item = counters.item + 1
            local m = inbox[i]
            local a = m and m.atts and m.atts[s]
            if not a then return end
            return a.name, a.itemID, 134400, a.count, 1, true
        end
        _G.GetInboxItemLink = function(i, s)
            counters.link = counters.link + 1
            local m = inbox[i]
            local a = m and m.atts and m.atts[s]
            if not a then return end
            return "|cffffffff|Hitem:" .. tostring(a.itemID) .. "::::::::60:::::|h[" .. a.name .. "]|h|r"
        end
        _G.GetInboxText = function()
            counters.text = counters.text + 1
            return "Body text"
        end
        _G.TakeInboxItem = function(mailIdx, attIdx)
            local m = inbox[mailIdx]
            if m and m.atts and m.atts[attIdx] then
                counters.looted = counters.looted + 1
                m.atts[attIdx] = nil
                local hasLeft = false
                for _ in pairs(m.atts) do hasLeft = true break end
                if not hasLeft and (m.money or 0) <= 0 then table.remove(inbox, mailIdx) end
            end
        end
        _G.TakeInboxMoney = function(mailIdx)
            local m = inbox[mailIdx]
            if m and (m.money or 0) > 0 then
                counters.looted = counters.looted + 1
                m.money = 0
                local hasLeft = false
                for _ in pairs(m.atts) do hasLeft = true break end
                if not hasLeft then table.remove(inbox, mailIdx) end
            end
        end

        clearTimers()
        MH.OnEvent(nil, "MAIL_SHOW")
        for k in pairs(counters) do counters[k] = 0 end
        if mode == "gold" then
            MH.StartGoldFetch()
        else
            MH.StartItemFetch(13463, "Dreamfoil", { totalUnits = 400 })
        end
        local guard = 0
        while MH.IsActive() and guard < 120 do
            guard = guard + 1
            MH.OnEvent(nil, "BAG_UPDATE_DELAYED")
            MH.OnEvent(nil, "MAIL_INBOX_UPDATE")
        end
        counters.rem = #inbox
        clearTimers()
        MH.OnEvent(nil, "MAIL_CLOSED")
        MH.RefreshItemPickerUI = savedPickerFn
        MH.RefreshPresetsUI = savedPresetsFn
        return counters
    end

    local c1 = runGetAllPerfCase(function()
        local t = {}
        for i = 1, 50 do
            t[i] = {
                sender = "Auction House",
                subject = "Auction expired: Dreamfoil (20)",
                money = 0, cod = 0,
                atts = { [1] = { name = "Dreamfoil", itemID = 13463, count = 20 } },
            }
        end
        return t
    end, "item")
    eq(c1.looted, 50, "GetAll perf 50_expired_Dreamfoil looted all 50")
    eq(c1.text, 0, "GetAll perf 50_expired_Dreamfoil makes 0 GetInboxText calls")
    check(c1.picker <= 2, "GetAll perf 50_expired_Dreamfoil refreshes picker <= 2 times, got " .. tostring(c1.picker))
    check(c1.presets <= 1, "GetAll perf 50_expired_Dreamfoil refreshes presets <= 1 time during batch, got " .. tostring(c1.presets))

    local c2 = runGetAllPerfCase(function()
        local t = {}
        for i = 1, 20 do
            t[i] = {
                sender = "Auction House",
                subject = "Auction expired: Dreamfoil (20)",
                money = 0, cod = 0,
                atts = { [1] = { name = "Dreamfoil", itemID = 13463, count = 20 } },
            }
        end
        for i = 21, 50 do
            t[i] = {
                sender = "Auction House",
                subject = "Auction successful: Copper Bar (20)",
                invoiceType = "seller", money = 4750, cod = 0, atts = {},
            }
        end
        return t
    end, "item")
    eq(c2.looted, 20, "GetAll perf 20_Dreamfoil_behind_30_other looted all 20 Dreamfoil")
    eq(c2.rem, 30, "GetAll perf 20_Dreamfoil_behind_30_other left 30 other mails untouched")
    eq(c2.text, 0, "GetAll perf 20_Dreamfoil_behind_30_other makes 0 GetInboxText calls")
    check(c2.hdr < 200, "GetAll perf 20_Dreamfoil_behind_30_other scanCursor keeps headers < 200, got " .. tostring(c2.hdr))
    check(c2.item <= 260, "GetAll perf 20_Dreamfoil_behind_30_other scanCursor keeps item reads <= 260, got " .. tostring(c2.item))
    check(c2.picker <= 2, "GetAll perf 20_Dreamfoil_behind_30_other refreshes picker <= 2 times, got " .. tostring(c2.picker))

    local c3 = runGetAllPerfCase(function()
        local t = {}
        for i = 1, 50 do
            t[i] = {
                sender = "Auction House",
                subject = "Auction successful: Copper Bar (20)",
                invoiceType = "seller", money = 4750, cod = 0, atts = {},
            }
        end
        return t
    end, "gold")
    eq(c3.looted, 50, "GetAll perf 50_gold_only_mails looted all 50 gold mails")
    eq(c3.item, 0, "GetAll perf 50_gold_only_mails makes 0 GetInboxItem calls")
    eq(c3.text, 0, "GetAll perf 50_gold_only_mails makes 0 GetInboxText calls")
    check(c3.picker <= 2, "GetAll perf 50_gold_only_mails refreshes picker <= 2 times, got " .. tostring(c3.picker))

    _G.MailFrame = savedMailFrame
    _G.InboxFrame = savedInboxFrame
    _G.SendMailFrame = savedSendFrame
    _G.OpenMailFrame = savedOpenFrame
    _G.GetInboxNumItems = savedGetNum
    _G.GetInboxHeaderInfo = savedGetHdr
    _G.GetInboxInvoiceInfo = savedGetInv
    _G.GetInboxItem = savedGetItem
    _G.GetInboxItemLink = savedGetLink
    _G.GetInboxText = savedGetText
    _G.TakeInboxItem = savedTakeItem
    _G.TakeInboxMoney = savedTakeMoney
    _G.C_Container = savedCont
    _G.C_Item = savedCItem
    _G.ATTACHMENTS_MAX_RECEIVE = savedAttachMax
end

print(string.format("PASS test_mail_and_logging (%d assertions)", assertions))
