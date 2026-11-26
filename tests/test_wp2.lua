-- Reuse every host assertion and its synthetic client mocks without changing them.
local scratch = ((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./")
local addon = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local ns, frames = dofile(scratch .. "host_fixture.lua")
local n = 0
local function check(ok, message) n = n + 1; assert(ok, message) end
local function fire(event, arg)
    for _, frame in ipairs(frames) do
        if frame._events[event] and frame._scripts.OnEvent then frame._scripts.OnEvent(frame, event, arg) end
    end
end
local api, app = MerchantMasterAPI, ns.app
check(type(api.RegisterSuperList) == "function", "Super List registration boundary exists")
check(ns.MarketScan and type(ns.MarketScan.GetState) == "function", "market state boundary exists")
check(ns.TrainerServices and type(ns.TrainerServices.Resolve) == "function", "trainer resolution boundary exists")
local refreshMarket, scanTrainer = app.refreshAllMarketValues, ns.TrainerServices.Scan
ns.MarketScan.Initialize(app, {})
ns.TrainerServices.Initialize(function() error("duplicate trainer binding") end)
check(app.refreshAllMarketValues == refreshMarket and ns.TrainerServices.Scan == scanTrainer, "repeat service binding leaves the original scanner closures intact")
local provider = ns.SuperList
check(provider and app.superListProvider == provider, "one installed Super List provider")
local creates, originalCreate = 0, provider.Create
provider.Create = function(...) creates = creates + 1; return originalCreate(...) end
local view, tbl = app.ui.recipesView, app.ui.recipesTable
check(api.RegisterSuperList(provider) and api.RegisterSuperList(provider), "repeat registration is successful and idempotent")
check(creates == 0 and app.ui.recipesView == view and app.ui.recipesTable == tbl, "repeat registration never recreates widgets")
check(not api.RegisterSuperList({}) and app.superListProvider == provider, "invalid provider cannot replace installed view")
assert(loadfile(addon .. "UI_SuperList.lua"))("MerchantMaster", ns)
check(ns.SuperList == provider and creates == 0, "module reload does not register another provider")
provider.Create = originalCreate
SlashCmdList.MERCHANTMASTER("recipes")
check(app.activeTab == "recipes" and MerchantMasterDB.activeTab == "recipes", "canonical slash command and saved tab remain recipes")

-- Broadcast through every registered event frame: each event reaches one scanner.
app.cancelMarketScan(false); app.cancelOrderBookScan()
AuctionHouseFrame:Show()
app.wanted = nil
local sends, reads, pages = 0, 0, 0
local full = false
C_AuctionHouse.SendBrowseQuery = function() sends = sends + 1 end
C_AuctionHouse.GetBrowseResults = function()
    reads = reads + 1
    return {{ itemKey = { itemID = 2447 }, totalQuantity = 7, minPrice = 111 }}
end
C_AuctionHouse.HasFullBrowseResults = function() return full end
C_AuctionHouse.RequestMoreBrowseResults = function() pages = pages + 1 end
local state = ns.MarketScan.GetState()
local generation = state.generation
SlashCmdList.MERCHANTMASTER("recipes")
check(sends == 0, "opening the recipes list never starts an AH search")
api.RefreshMarket()
check(sends == 1 and api.IsScanning(), "explicit refresh sends one AH query")
check(ns.MarketScan.GetState().generation == generation + 1, "scan generation advances once")
fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(reads == 1 and pages == 1 and ns.MarketScan.GetState().page == 1, "AH event dispatch processes one page once")
full = true
fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {{ itemKey = { itemID = 2447 }, totalQuantity = 7, minPrice = 111 }})
local economy = ns.DetectActiveEconomy()
check(not api.IsScanning() and MerchantMasterDB.ahPrices[economy][2447].qty == 7, "repeated browse key is counted once across pages")
state = ns.MarketScan.GetState()
check(state.economy == economy and state.completedAt == time() and state.partial == false, "full completion exposes selected economy and timestamp")
fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(reads == 1, "completed scanner ignores later results")
api.RefreshMarket(); app.cancelMarketScan(true)
check(ns.MarketScan.GetState().partial == true, "partial cancellation remains distinguishable")
app.cancelOrderBookScan()
GetTime = function() return 1010 end
local searches, lotReads = 0, 0
C_AuctionHouse.SendSearchQuery = function() searches = searches + 1 end
C_AuctionHouse.GetNumCommoditySearchResults = function() lotReads = lotReads + 1; return 1 end
C_AuctionHouse.GetCommoditySearchResultInfo = function() return { quantity = 12, unitPrice = 123 } end
app.scanOrderBookItems({2447, 2447}, 10)
fire("COMMODITY_SEARCH_RESULTS_RECEIVED")
check(searches == 1 and lotReads == 1, "one queued order-book item and one result processing per event")
check(MerchantMasterDB.ahLots[economy][2447].lots[1].qty == 12, "order-book persistence is preserved")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2447)
check(lotReads == 1, "completed order-book job is not processed again")

local scans, infos, costs = 0, 0, 0
local filters = { available = true, unavailable = false, used = false }
GetNumTrainerServices = function() scans = scans + 1; return 2 end
GetTrainerServiceInfo = function(i)
    infos = infos + 1
    if i == 1 then return "Instant Poison", "Rank 2", "available" end
    return "Section", nil, "header"
end
GetTrainerServiceCost = function() costs = costs + 1; return 777 end
GetTrainerServiceSkillReq = function() return "Poisons", 100 end
GetTrainerServiceLevelReq = function() return 30 end
IsTradeskillTrainer = function() return true end
GetTrainerServiceTypeFilter = function(key) return filters[key] end
SetTrainerServiceTypeFilter = function(key, value) filters[key] = value end
local resolved = ns.TrainerServices.Resolve(1)
check(resolved and resolved.recipe.n == "Instant Poison II" and resolved.cost == 777 and resolved.skill == 100 and resolved.level == 30,
    "ranked-name resolution exposes original recipe, cost and requirements")
check(ns.TrainerServices.Resolve(2) == nil, "trainer headers do not resolve")
infos, costs = 0, 0
local savedCaptureReadOnly = ns.Analytics and ns.Analytics.Store and ns.Analytics.Store.readOnly
if ns.Analytics and ns.Analytics.Store then ns.Analytics.Store.readOnly = true end
fire("TRAINER_SHOW")
check(scans == 1 and infos == 2 and costs == 1, "trainer show scans each service once")
check(filters.available == true and filters.unavailable == false and filters.used == false, "initial scan restores trainer filters")
local db = ns.MP.GetDB()
check(db.trainerCosts["Instant Poison"] == 777 and db.trainerCosts["Instant Poison II"] == 777, "base and ranked cost keys remain cached")
check(db.trainerReqs.poisons[resolved.recipe.s].req == 100 and db.trainerReqs.poisons[resolved.recipe.s].rlv == 30,
    "trainer skill and character level persistence is preserved")
fire("TRAINER_UPDATE")
check(scans == 2 and infos == 4 and costs == 2, "trainer update performs one additional scan")
if ns.Analytics and ns.Analytics.Store then ns.Analytics.Store.readOnly = savedCaptureReadOnly end
check(sends == 2 and searches == 1, "trainer resolution and scanning never issue AH searches")
-- A readable selection with no restoration API must not be changed by filter expansion.
local savedGetSelection,savedSelect,savedSetFilter=GetTrainerSelectionIndex,SelectTrainerService,SetTrainerServiceTypeFilter
local selection,filterWrites=1,0
GetTrainerSelectionIndex=function() return selection end; SelectTrainerService=nil
SetTrainerServiceTypeFilter=function(kind,value) filterWrites=filterWrites+1; selection=2; filters[kind]=value end
ns.TrainerServices.Scan(true)
check(filterWrites==0 and selection==1,'partial selection APIs leave trainer selection and filters untouched')
GetTrainerSelectionIndex=nil
ns.TrainerServices.Scan(true)
check(filterWrites==4 and filters.unavailable==false and filters.used==false,'legacy clients without selection APIs still expand and restore initial filters')
GetTrainerSelectionIndex,SelectTrainerService,SetTrainerServiceTypeFilter=savedGetSelection,savedSelect,savedSetFilter
-- Host ownership scanning remains available without writable or embedded Accounting.
do
    local oldAfter=C_Timer.After; local timers={}
    C_Timer.After=function(_,fn) timers[#timers+1]=fn end
    local capture=ns.Analytics.Capture; ns.Analytics.Capture=nil
    local store=ns.Analytics.Store; local wasReadOnly=store and store.readOnly
    if store then store.readOnly=true end
    local oldCount,oldHeader,oldItem,oldLink=GetInboxNumItems,GetInboxHeaderInfo,GetInboxItem,GetInboxItemLink
    local qty,pendingQty=3,nil
    GetInboxNumItems=function() return 1,1 end
    GetInboxHeaderInfo=function() return nil,nil,'Sender','Mailbox retry test',0,0,30,true,false,false end
    GetInboxItem=function(_,slot) if slot==1 then return 'Regression Item',903003,nil,qty end end
    GetInboxItemLink=function(_,slot) if slot==1 then return '|Hitem:903003|h' end end
    app.atMailbox=true; app.mailboxSession=(app.mailboxSession or 0)+1
    app.char.mail={['Regression Item']=3}; app.mailboxItems={[903003]=3}; app.itemIDs['Regression Item']=903003
    pendingQty=2; TakeInboxItem(1)
    check(app.mailboxScanPending~=nil,'host take API queues ownership scan without Capture')
    while #timers>0 do table.remove(timers,1)() end
    check(app.mailboxScanPending and app.mailboxScanPending.attempt==3,'take remains pending after bounded retries')
    check(app.char.mail['Regression Item']==3,'pre-response snapshot leaves totals unchanged')
    qty=pendingQty; fire('MAIL_INBOX_UPDATE'); fire('CLOSE_INBOX_ITEM')
    while #timers>0 do table.remove(timers,1)() end
    check(app.char.mail['Regression Item']==2 and app.mailboxScanPending==nil,'read-only standalone reader commits response ownership')
    check(store.readOnly==true,'ownership scan does not enable Accounting writes')
    app.QueueMailboxScan('open')
    local request=app.mailboxScanPending
    request.inboxReady=true; request.attempt=2
    app.QueueMailboxScan('take')
    check(not request.inboxReady and request.attempt==0,'coalesced take resets response readiness and retry budget')
    fire('MAIL_CLOSED')
    check(app.mailboxScanPending==nil,'closing mailbox cancels pending scan')
    if store then store.readOnly=wasReadOnly end
    ns.Analytics.Capture=capture
    C_Timer.After=oldAfter
    GetInboxNumItems,GetInboxHeaderInfo,GetInboxItem,GetInboxItemLink=oldCount,oldHeader,oldItem,oldLink
end
print("WP2 boundaries: " .. n .. " assertions, 0 failures")
