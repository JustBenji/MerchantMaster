-- Real seller/market modules; only the external AH and clock are synthetic.
local A = (((debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./") .. "../")
local checks = 0
local function check(ok, message) checks = checks + 1; assert(ok, message) end
local function key(id, level, suffix, pet)
    return {itemID=id, itemLevel=level or 0, itemSuffix=suffix or 0, battlePetSpeciesID=pet or 0}
end
local function row(names, total, own, price)
    return {owners=names, totalNumberOfOwners=total, containsOwnerItem=own or false,
        buyoutAmount=price or 100, quantity=1, auctionID=123}
end
local function boot(lookupID)
    local ns, clock, pending = {}, 100, {}
    local env = {economy="A", rows={}, full=true, browse={}, browseFull=true, searches=0, more=0, ready=true}
    time=function() return clock end; GetTime=time
    wipe=function(t) for k in pairs(t) do t[k]=nil end end
    issecretvalue=function(v) return type(v)=="table" and rawget(v,"secret")==true end
    UnitFullName=function() return "Me", "Home Realm" end
    GetNormalizedRealmName=function() return "HomeRealm" end
    C_Timer={}
    function C_Timer.NewTimer(delay,fn)
        local t={at=clock+delay,fn=fn,Cancel=function(self) self.cancelled=true end}
        pending[#pending+1]=t; return t
    end
    C_Timer.After=C_Timer.NewTimer
    function env.advance(seconds)
        local untilTime=clock+seconds
        while true do
            local index, nextTimer
            for i,t in ipairs(pending) do
                if not t.cancelled and t.at<=untilTime and (not nextTimer or t.at<nextTimer.at) then index,nextTimer=i,t end
            end
            if not nextTimer then break end
            table.remove(pending,index); clock=nextTimer.at; nextTimer.fn()
        end
        clock=untilTime
    end
    MerchantMasterDB={}; AuctionHouseFrame={IsShown=function() return env.open~=false end}
    hooksecurefunc=function(api, name, cb)
        local original=api[name]
        api[name]=function(...) original(...); cb(...) end
    end
    Enum=nil
    C_AuctionHouse={
        MakeItemKey=key,
        IsThrottledMessageSystemReady=function() return env.ready end,
        HasSearchResults=function() return false end,
        GetItemKeyInfo=function() return {isCommodity=env.commodity or false} end,
        SendSearchQuery=function(k) env.searches=env.searches+1; env.lastKey=k end,
        SendBrowseQuery=function(query) env.lastBrowse=query end,
        SearchForFavorites=function() end,
        SearchForItemKeys=function() end,
        ReplicateItems=function() env.replicated=true end,
        GetBrowseResults=function() return env.browse end,
        HasFullBrowseResults=function() return env.browseFull end,
        RequestMoreBrowseResults=function() end,
        GetNumItemSearchResults=function() return #env.rows end,
        GetItemSearchResultInfo=function(_,i) return env.rows[i] end,
        HasFullItemSearchResults=function() return env.full end,
        RequestMoreItemSearchResults=function(k) env.more=env.more+1; env.moreKey=k end,
        GetNumCommoditySearchResults=function() return 1 end,
        GetCommoditySearchResultInfo=function() return {quantity=9,unitPrice=10,numOwnerItems=0,owners={"Alice-HomeRealm"},totalNumberOfOwners=1} end,
        HasFullCommoditySearchResults=function() return true end,
    }
    ns.DetectActiveEconomy=function() return env.economy end
    ns.ItemName=function(id) return "Item "..id end
    ns.ALL_CATALOG_IDS={[100]=true,[101]=true}
    ns.CaptureActiveEconomySnapshot=function() end
    ns.InvalidatePriceCache=function() end
    ns.RecipeStats={Invalidate=function(reason) env.invalidated=reason end}
    local app={scanning={},costs={},folded={},itemIDs={},lotScanTotal=0,lotScanDone=0}
    app.refresh=function() end
    local function lotsPrice(lots,whole,qty)
        local cost,remaining=0,qty
        for _,lot in ipairs(lots) do
            local n=math.min(remaining,lot.n); cost=cost+n*lot.price/(whole and lot.n or 1); remaining=remaining-n
        end
        return remaining==0 and cost or nil, remaining>0 and remaining or nil
    end
    local seller=loadfile(A.."SellerStats.lua")
    if seller then seller("MerchantMaster",ns) end
    check(ns.SellerStats and type(ns.SellerStats.Get)=="function", "seller provider must exist before scan integration")
    assert(loadfile(A.."MarketScan.lua"))("MerchantMaster",ns)
    ns.MarketScan.Initialize(app,{labels={openAH="open",noAnswer="timeout"},say=function() end,
        lotsPrice=lotsPrice,lotsFor=function(lots) return lots end,lookupID=lookupID or function() return 100 end,
        ownedCounts=function() return {} end,bagCrates=function() return {} end,
        atAH=function() return AuctionHouseFrame:IsShown() end})
    function env.discover(keys)
        env.browse={}
        for _,k in ipairs(keys) do env.browse[#env.browse+1]={itemKey=k,totalQuantity=10,minPrice=100} end
        app.refreshAllMarketValues(); ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end
    function env.start(items, sellers)
        local options
        if sellers~=false then options={sellers=true} end
        app.scanOrderBookItems(items or {100},1,options)
        env.advance(1)
    end
    function env.items(k) ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED",k or env.lastKey) end
    env.ns,env.app=ns,app
    return env
end

-- A missing provider, early pricing stop, or summing bucket counts breaks this.
local e=boot(); local stats=e.ns.SellerStats
check(stats.Get(100,"A").status=="unavailable", "browse-only/never searched is unavailable")
check(e.searches==0, "initialization and getters never search")
e.discover({key(100)})
e.full=false; e.rows={row({"Alice-HomeRealm","player"},2,true,50)}
e.start(); e.items()
check(e.more==1, "seller purpose pages even when pricing quantity is already satisfied")
check(e.moreKey.itemID==100, "paging retains the searched key")
e.full=true; e.rows={row({"Alice-HomeRealm","player"},2,true,50),row({"Alice-HomeRealm","Alice-OtherRealm"},2)}
e.items()
local s=stats.Get(100,"A")
check(s.count==3 and s.status=="complete", "deduplicates across pages and includes own listings and distinct realms")
check(s.display=="3" and s.at==time() and s.scope=="Item variants", "complete result exposes display, time and scope")
check(MerchantMasterDB.ahPrices.A[100].price==100, "own auction is excluded from pricing after seller capture")
check(e.invalidated=="sellers", "publishing invalidates recipe statistics")
e.discover({key(100)})
s=stats.Get(100,"A")
check(s.count==3 and s.status=="complete", "subsequent browse price write preserves nonempty seller metadata")
check(stats.Get(100,"B").count==nil, "economies do not share counts")

-- Truncation, unknown identities, commodity names and browse-only data are not exact.
e=boot(); stats=e.ns.SellerStats; e.discover({key(100)})
e.rows={row({"Alice-HomeRealm"},8),row({"Alice-HomeRealm"},9)}; e.start(); e.items()
s=stats.Get(100,"A")
check(s.count==1 and s.status=="partial" and s.display=="1+", "truncated owners produce a distinct-name lower bound, never summed totals")
check(type(s.reason)=="string" and #s.reason>0, "partial count has an explanation")
e.rows={row({"", "?", "Unknown", "   "},4)}; e.start(); e.items()
s=stats.Get(100,"A")
check(s.count==nil and s.status=="unavailable" and s.display=="n/a", "unreadable identities never fabricate zero")
e.rows={}; e.start(); e.items()
s=stats.Get(100,"A")
check(s.count==0 and s.status=="complete" and s.display=="0", "complete empty item search can report zero")
e.commodity=true; e.start(); e.ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_RECEIVED",100)
s=stats.Get(100,"A")
check(s.count==nil and s.status=="unavailable" and s.display=="n/a", "commodity names are never treated as unique seller evidence")

-- Cancel/time out/switch while a page is pending; late callbacks must stay isolated.
e=boot(); stats=e.ns.SellerStats; e.discover({key(100)})
e.rows={row({"Alice-HomeRealm"},1)}; e.full=false; e.start(); e.items()
e.app.cancelOrderBookScan(); s=stats.Get(100,"A")
check(s.count==1 and s.status=="partial", "cancel preserves only a named lower bound")
local more=e.more; e.advance(30); e.full=true; e.items(key(100))
check(e.more==more and stats.Get(100,"A").status=="partial", "cancelled timers/events cannot publish an exact count")
e.full=false; e.start(); e.items(); e.advance(30)
s=stats.Get(100,"A")
check(s.count==1 and s.status=="partial", "existing timeout policy publishes partial seller observations")
check(not e.ns.MarketScan.GetBagStatus(), "timeout releases the queue")
e.start(); e.items(); e.economy="B"; e.full=true; e.items()
check(stats.Get(100,"B").count==nil, "late old-economy results cannot write the selected economy")
check(stats.Get(100,"A").status=="partial", "economy switch never upgrades abandoned observations to exact")
check(not (MerchantMasterDB.ahLots and MerchantMasterDB.ahLots.B and MerchantMasterDB.ahLots.B[100]), "old-economy prices cannot contaminate the new economy")

-- Full item keys and complete browse coverage are necessary for item aggregation.
e=boot(); stats=e.ns.SellerStats
e.rows={row({"Alice-HomeRealm"},1)}; e.start(); e.items()
s=stats.Get(100,"A")
check(s.count==1 and s.status=="partial", "one exact variant without coverage is only an item-wide lower bound")
local k1,k2=key(100,10,1),key(100,10,2)
e.discover({k1,k2}); e.start()
check(e.lastKey.itemSuffix==1 or e.lastKey.itemSuffix==2, "seller refresh searches a discovered full variant key")
local first=e.lastKey.itemSuffix
e.rows={row({"Alice-HomeRealm","Bob-OtherRealm"},2)}; e.items(); e.advance(1)
check(e.lastKey.itemSuffix~=first, "second discovered variant is queued separately")
s=stats.Get(100,"A")
check(s.status=="partial", "one missing variant prevents exact aggregate")
e.rows={row({"Bob-OtherRealm","Carol-HomeRealm"},2)}; e.items()
s=stats.Get(100,"A")
check(s.count==3 and s.status=="complete", "covered variants union identities rather than summing counts")
e.discover({k1,k2,key(100,10,2,8)})
check(stats.Get(100,"A").status=="partial", "newly discovered pet/variant key removes exact aggregation")

-- Pricing-only work must not acquire extra seller pages; secret fields are excluded.
e=boot(); stats=e.ns.SellerStats; e.discover({key(100)})
e.full=false; e.rows={row({"Alice-HomeRealm"},1)}; e.start(nil,false); e.items()
check(e.more==0 and stats.Get(100,"A").status=="partial", "pricing-only queue captures available sellers without forcing pagination")
e.full=true; e.rows={row({{secret=true},"Alice-HomeRealm"},2)}; e.start(); e.items()
check(stats.Get(100,"A").count==1 and stats.Get(100,"A").status=="partial", "secret owners are excluded and prevent exactness")
e.rows={row({"Alice-HomeRealm"},{secret=true})}; e.start(); e.items()
check(stats.Get(100,"A").status=="partial", "secret owner cardinality prevents exactness")
e.rows={row({"Alice-HomeRealm"},1)}; C_AuctionHouse.HasFullItemSearchResults=nil; e.start(); e.items()
check(stats.Get(100,"A").status=="partial", "missing completion API cannot claim exactness")
e.ns.MarketScan.HandleEvent("ITEM_SEARCH_RESULTS_UPDATED",{secret=true})
check(stats.Get({secret=true},"A").count==nil, "secret item keys cannot index saved data")

e=boot(); stats=e.ns.SellerStats; e.discover({key(100)})
e.rows={row({"Alice-Home Realm","alice-HomeRealm","Bob"},2)}; e.start(); e.items()
check(stats.Get(100,"A").count==2 and stats.Get(100,"A").status=="complete", "normalizes realm spaces/case and qualifies local names")
e.rows={row({"Unknown-HomeRealm","UnknownObject-HomeRealm","Alice-HomeRealm"},3)}; e.start(); e.items()
check(stats.Get(100,"A").count==1 and stats.Get(100,"A").status=="partial", "realm-qualified unknown placeholders are excluded")
e.rows={row({"Alice-HomeRealm"},1,true)}; e.start(); e.items()
check(stats.Get(100,"A").status=="partial", "hidden player identity in an own-listing bucket prevents exactness")
e.rows={row({"Alice-HomeRealm"},1)}; e.start()
e.items(key(100,99)); check(e.ns.MarketScan.GetBagStatus()~=nil, "different variant event does not finish the active query")
e.items(); check(stats.Get(100,"A").status=="complete", "matching full key finishes the query")
e.full={secret=true}; e.rows={}; e.start(); e.items(); e.app.cancelOrderBookScan()
check(stats.Get(100,"A").count==nil, "secret completion flag cannot create a false zero")

e=boot(); stats=e.ns.SellerStats; e.discover({key(100)})
e.ready=false; e.start(); e.app.cancelOrderBookScan(); e.ready=true; e.advance(30)
check(e.searches==0, "cancelled throttle wait never sends a delayed query")
e.ready=false; e.start(); e.economy="B"; e.ready=true; e.advance(1)
check(e.searches==0 and stats.Get(100,"B").count==nil, "economy switch cancels queued throttle callbacks")
e.economy="A"; e.discover({key(100)}); e.commodity=true
C_AuctionHouse.GetCommoditySearchResultInfo=function() return {quantity={secret=true},unitPrice={secret=true},numOwnerItems={secret=true}} end
e.start(); e.ns.MarketScan.HandleEvent("COMMODITY_SEARCH_RESULTS_RECEIVED",100)
check(stats.Get(100,"A").status=="unavailable", "secret commodity pricing fields cannot expose sellers or throw")

e=boot(); e.browseFull=false; e.discover({key(100)}); e.economy="B"; e.browseFull=true
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(not (MerchantMasterDB.ahPrices and MerchantMasterDB.ahPrices.B and MerchantMasterDB.ahPrices.B._scannedAt), "old full browse cannot stamp the newly selected economy")

e=boot(); stats=e.ns.SellerStats; e.discover({key(100,30,1)})
e.rows={row({"Alice-HomeRealm"},1,false,999)}; e.start(); e.items()
check(MerchantMasterDB.ahPrices.A[100].price==100, "a single variant seller query cannot overwrite the aggregate browse price")
check(stats.Get(100,"A").count==1 and stats.Get(100,"A").status=="complete", "single covered variant can provide an exact count")

-- Independent-review regressions: new or unreadable variants invalidate exactness.
e=boot(); stats=e.ns.SellerStats; e.discover({key(100,10,1)})
e.rows={row({"Alice-HomeRealm"},1)}; e.start(); e.items()
e.rows={row({"Bob-OtherRealm"},1)}; e.start({key(100,10,2)}); e.items()
s=stats.Get(100,"A")
check(s.count==2 and s.status=="partial", "explicitly searched new variant joins the union and invalidates earlier coverage")
e.discover({key(100,10,1),key(100,10,2)})
check(stats.Get(100,"A").status=="complete", "a later complete browse can confirm previously observed variants")
e=boot(); stats=e.ns.SellerStats
e.discover({key(100,10,1),{itemID=100,itemLevel={secret=true},itemSuffix=2,battlePetSpeciesID=0}})
e.rows={row({"Alice-HomeRealm"},1)}; e.start(); e.items()
check(stats.Get(100,"A").count==1 and stats.Get(100,"A").status=="partial", "an unreadable browse variant prevents exact aggregate coverage")
e=boot(); stats=e.ns.SellerStats; e.discover({key(100,10,-12)})
check(MerchantMasterDB.ahPrices.A[100].price==100, "signed suffix keys retain the baseline browse-price behavior")
e.rows={row({"Alice-HomeRealm"},1)}; e.start(); e.items()
check(e.lastKey.itemSuffix==-12 and stats.Get(100,"A").status=="complete", "seller scans preserve signed suffix keys")

e=boot(); e.rows={row({"Alice-HomeRealm"},1)}; e.full=false
e.ns.MarketScan.ScanBagCrates({{name="Bag crate",bundles={{name="Item 100",count=1}}}})
e.advance(1)
e.app.scanOrderBookItems({101},1,{sellers=true}); e.items(key(100))
local active=e.ns.MarketScan.GetBagStatus()
check(active and active.itemID==101 and e.more==0, "seller purpose never upgrades unrelated queued bag-pricing work")

e=boot(); stats=e.ns.SellerStats; e.discover({key(100),key(101)})
check(stats.Get(101,"A").count==nil, "unsearched items remain unknown before publication")
e.rows={row({"Alice-HomeRealm"},1)}; e.start(); e.items()
MerchantMasterDB.sellerStats.A.items=nil
check(stats.Get(100,"A").count==1, "item index can be rebuilt from preserved full-key observations")
e.rows={row({"Bob-OtherRealm"},1)}; e.start({101}); e.items()
check(stats.Get(101,"A").count==1 and stats.Get(100,"A").count==1, "publication indexes the selected item without mixing other item identities")
e.rows={row({"?"},1)}; e.start(); e.items()
check(stats.Get(100,"A").at~=nil and stats.Get(999,"A").at==nil, "observed unavailable metadata cannot leak into the missing-data result")

-- Browse completeness is untrusted just like item-search completeness.
e=boot(); e.browseFull={secret=true}; e.discover({key(100)})
check(e.ns.MarketScan.GetState().active, "secret browse completion keeps scan active")
check(not (MerchantMasterDB.ahPrices and MerchantMasterDB.ahPrices.A and MerchantMasterDB.ahPrices.A[101]), "secret browse completion cannot mark unseen items absent")
e.browseFull=1; e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(e.ns.MarketScan.GetState().active, "only literal true completes a browse scan")

local function wantedBrowse(env, id, name)
    local bar = {SetSearchText=function(self, value) self.searchText=value end}
    function bar:StartSearch() C_AuctionHouse.SendBrowseQuery({searchString=self.searchText}) end
    AuctionHouseFrame.SearchBar = bar
    AuctionHouseFrame.SelectBrowseResult = function(_, result) env.selected=result end
    return env.app.searchAH(name or "Item 100",1,id)
end
local function browseUpdated(env)
    env.ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
end

for _, itemKey in ipairs({key(100),key(100,0,9)}) do
    local env=boot()
    local seller=env.ns.SellerStats
    env.discover({itemKey})
    env.start({itemKey}); env.items()
    local empty=seller.Get(100,"A")
    check(empty.count==0 and empty.status=="complete", "seller search starts with a confirmed empty key")
    env.browse={{itemKey=itemKey,totalQuantity=6,minPrice=100}}
    if itemKey.itemSuffix==0 then
        wantedBrowse(env,100)
    else
        env.browseFull=false
        env.app.refreshAllMarketValues()
    end
    browseUpdated(env)
    local pending=seller.Get(100,"A")
    check(pending.count==0 and pending.status=="partial", "positive Browse supply puts the empty key back in seller search")
    if itemKey.itemSuffix~=0 then
        env.browseFull=true
        browseUpdated(env)
        check(seller.Get(100,"A").status=="partial", "finishing full Browse preserves the pending suffix")
    end
    env.rows={row({"Alice-HomeRealm"},1)}
    env.start({itemKey}); env.items()
    local refreshed=seller.Get(100,"A")
    check(refreshed.count==1 and refreshed.status=="complete", "a fresh complete search clears the pending key")
end

for _, search in ipairs({"SearchForFavorites","SearchForItemKeys"}) do
    local env=boot(function() return nil end)
    env.ns.MarketScan.ScanBagCrates({{name="Bag crate",bundles={{name="Unknown item",count=4}}}})
    check(env.lastBrowse and env.lastBrowse.searchString=="Unknown item", "bag Browse is dispatched before "..search)
    if search=="SearchForItemKeys" then C_AuctionHouse[search]({key(101)}) else C_AuctionHouse[search]() end
    browseUpdated(env)
    check(env.ns.MarketScan.GetBagStatus() and not env.app.costs["Bag crate"],
        "empty "..search.." results cannot record a crate shortage")
end

e=boot()
e.ns.ItemName=function() return "Shared Name" end
wantedBrowse(e,100,"Shared Name")
local expensive={itemKey=key(100,10),totalQuantity=4,minPrice=90}
local cheap={itemKey=key(100,20),totalQuantity=7,minPrice=60}
local other={itemKey=key(101),totalQuantity=99,minPrice=1}
e.browse={other,expensive,cheap}
browseUpdated(e)
local prices=e.ns.MarketScan.ActiveEconomyPrices()
check(e.selected==cheap and prices[100].price==60 and prices[100].qty==11 and not prices[101],
    "targeted browse selects the cheapest matching variant and persists only its item-wide aggregate")
local history=MerchantMasterDB.ahHistory.A[100]
check(history[#history].p==60 and history[#history].q==11,"targeted history records the full variant aggregate")
local targetedSnapshot = MerchantMasterDB.ahSnapshots.A[100]
check(#targetedSnapshot == 3 and targetedSnapshot[1] == time() and targetedSnapshot[2] == 60 and targetedSnapshot[3] == 11,
    "Confirmed targeted Browse records its item-wide aggregate as a snapshot triplet")

for _,bad in ipairs({
    {itemKey=key(100,30),minPrice=10},
    {itemKey=key(100,30),minPrice=10,totalQuantity={secret=true}},
    {itemKey=key(100,30),minPrice={secret=true},totalQuantity=2},
    {itemKey={itemID={secret=true}},minPrice=10,totalQuantity=2},
    {itemKey=key(100,30),minPrice=10,totalQuantity=0},
}) do
    local price, historyCount=prices[100],#history
    e.advance(1)
    e.browse={cheap,bad}
    wantedBrowse(e,100); browseUpdated(e)
    check(prices[100]==price and #history==historyCount,"invalid variant data leaves saved price and history intact")
end

local prior=prices[100]
local daily=MerchantMasterDB.ahDaily.A[100][1]
wantedBrowse(e,100)
e.selected=nil
e.browse={cheap}; e.browseFull=false; browseUpdated(e)
check(prices[100]==prior and daily.lastQ==11 and e.app.wanted.open and e.selected==cheap,
    "a partial page can select a matching variant while leaving stock and the search open")
e.browse={}; browseUpdated(e)
check(prices[100]==prior and daily.lastQ==11,"partial empty browse preserves price and daily stock")
e.browseFull=nil; browseUpdated(e)
check(prices[100]==prior and daily.lastQ==11,"unknown empty browse preserves price and daily stock")
e.browse={other}; e.browseFull={secret=true}; browseUpdated(e)
check(prices[100]==prior and e.app.wanted.open,"unreadable completeness cannot mark a missing item absent")
e.advance(1)
e.browseFull=true; browseUpdated(e)
check(prices[100].absent and prices[100].qty==0 and prices[100].price==nil
    and prices[100].lastPrice==60 and not e.app.wanted.open,
    "complete missing result publishes absence and preserves the last known price")
check(history[#history].p==0 and history[#history].q==0,"confirmed absence records zero price and quantity in history")

C_AuctionHouse.HasFullBrowseResults=nil
prior=prices[100]
e.browse={expensive}; wantedBrowse(e,100); browseUpdated(e)
check(prices[100]==prior and daily.lastQ==0 and e.app.wanted.open and e.selected==expensive,
    "a missing completeness API allows selection without publishing stock or closing the search")
C_AuctionHouse.HasFullBrowseResults=function() return e.browseFull end
e.browse={expensive,cheap}; browseUpdated(e)
check(not prices[100].absent and prices[100].qty==11 and daily.lastQ==11 and not e.app.wanted.open,
    "a later confirmed page publishes both variants and closes the search")
prior=prices[100]
C_AuctionHouse.HasFullBrowseResults=nil
e.browse={}; wantedBrowse(e,100); browseUpdated(e)
check(prices[100]==prior and prior.qty==11 and daily.lastQ==11,
    "empty browse without a completeness API preserves the prior listed snapshot")
e.browse={expensive,cheap}
wantedBrowse(e,nil,"sHaReD nAmE"); browseUpdated(e)
check(e.selected==cheap and prices[100]==prior,"exact case-insensitive name lookup selects without writing an item-wide snapshot")

local function deferRecipeSearch(env)
    AuctionHouseFrame.SearchBar = {
        SetSearchText=function(self,text) self.searchText=text end,
        StartSearch=function(self) C_AuctionHouse.SendBrowseQuery({searchString=self.searchText}) end,
    }
    env.app.searchAH("Item 100",1,100,{coalesce=true})
end
e=boot()
e.discover({key(100)})
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
e.open=false
check(wantedBrowse(e,100)==false,"a click with the Auction House closed cannot dispatch")
e.open=true
e.browse={cheap}; browseUpdated(e)
check(not e.selected and prices[100]==prior,"a closed-AH request cannot select a later result")
e.ready=false
check(wantedBrowse(e,100),"throttled search is queued")
e.browse={other}; browseUpdated(e)
check(prices[100]==prior and daily.lastQ==10 and not e.selected,"an older browse cannot consume the queued request")
e.ready=true
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(e.lastBrowse.searchString=="Item 100","throttle-ready still dispatches the wanted search")
e.browse={cheap}; browseUpdated(e)
check(e.selected==cheap and prices[100].qty==7,"the dispatched search selects and saves its matching result")
e.selected=nil
AuctionHouseFrame.SearchBar.StartSearch=function() end
e.app.searchAH("Item 100",1,100)
browseUpdated(e)
check(not e.selected,"a search bar action that sends no browse cannot arm result consumption")

e=boot()
e.discover({key(100)})
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
deferRecipeSearch(e)
local wanted=e.app.wanted
AuctionHouseFrame.SearchBar:SetSearchText("Item 101")
e.advance(0.18)
check(e.lastBrowse.searchString=="Item 101" and not e.app.wanted and not wanted.open and not wanted.dispatched,
    "a changed search string dispatches without claiming the original wanted item")
e.browse={other}; browseUpdated(e)
check(prices[100]==prior and daily.lastQ==10,"the changed query cannot record false absence for the original item")
deferRecipeSearch(e)
AuctionHouseFrame.SearchBar:SetSearchText("  iTeM 100  ")
e.advance(0.18)
check(e.app.wanted.open and e.app.wanted.dispatched,"case and surrounding whitespace still match the wanted search")

for _, restriction in ipairs({
    {itemClassFilters={{classID=4}}}, {filters={1}}, {minLevel=10}, {maxLevel=40},
    {itemClassFilters={secret=true}}, {filters=false}, {sorts={secret=true}},
    {sorts={{sortOrder={secret=true},reverseSort=false}}},
}) do
    e=boot()
    e.browse={expensive,cheap}
    wantedBrowse(e,100); browseUpdated(e)
    prices=e.ns.MarketScan.ActiveEconomyPrices()
    prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
    deferRecipeSearch(e)
    AuctionHouseFrame.SearchBar.StartSearch=function(self)
        restriction.searchString=self.searchText
        C_AuctionHouse.SendBrowseQuery(restriction)
    end
    e.advance(0.18)
    e.browse={}; browseUpdated(e)
    check(prices[100]==prior and prior.qty==11 and daily.lastQ==11,
        "restricted or unreadable queries cannot replace item-wide stock with absence")
end

e=boot()
e.browse={expensive,cheap}
wantedBrowse(e,100); browseUpdated(e)
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
wantedBrowse(e,100)
e.ns.ItemName=function() return "Corrected item name" end
e.browse={}; browseUpdated(e)
check(prices[100]==prior and daily.lastQ==11,"a changed canonical item name invalidates snapshot publishing")
AuctionHouseFrame.SearchBar.StartSearch=function(self)
    C_AuctionHouse.SendBrowseQuery({searchString=self.searchText, filters={}, itemClassFilters={},
        minLevel=0, maxLevel=0, sorts={{sortOrder=1,reverseSort=false}}})
end
check(e.app.searchAH("Wrong display name",1,100) and e.lastBrowse.searchString=="Corrected item name",
    "searchAH resolves the canonical item name for callers with a mismatched display name")
e.browse={cheap}; browseUpdated(e)
check(e.selected==cheap and prices[100].qty==7 and daily.lastQ==7,
    "ordinary sorting with default filters still publishes item-wide stock")

e=boot()
e.browse={expensive,cheap}
e.app.refreshAllMarketValues(); browseUpdated(e)
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
local oldLocale,oldItemInfo,oldCItem=GetLocale,GetItemInfo,C_Item
local localized,requested="Arkanitbarren"
GetLocale=function() return "deDE" end
GetItemInfo=function() return localized end
C_Item={GetItemNameByID=function() end,RequestLoadItemDataByID=function(id) requested=id end}
e.ns.ITEM_NAMES_BY_ID={[100]="Arcanite Bar"}
e.ns.ItemName=function(id) return e.ns.ITEM_NAMES_BY_ID[id] end
e.ns.RequestItemDataLoad=C_Item.RequestLoadItemDataByID
check(wantedBrowse(e,100) and e.lastBrowse.searchString==localized,"localized client name is used for browse")
localized=nil
e.browse={}; browseUpdated(e)
check(prices[100]==prior and prior.qty==11 and daily.lastQ==11,
    "a name that can no longer be resolved cannot publish an item-wide snapshot")
e.lastBrowse,requested=nil,nil
check(not e.app.sendShoppingRowsToBuyer({{itemID=100,name="Arcanite Bar",qty=1}}) and not e.lastBrowse and requested==100,
    "uncached German shopping-list items request data and skip the English browse")
browseUpdated(e)
check(prices[100]==prior and prior.qty==11 and daily.lastQ==11,
    "an uncached German item preserves confirmed stock and daily quantity")
GetLocale,GetItemInfo,C_Item=oldLocale,oldItemInfo,oldCItem

e=boot()
deferRecipeSearch(e)
e.ns.ItemName=function(id) return "Item #"..id end
check(not e.app.searchAH(nil,1,101,{coalesce=true}),"an unresolved item cannot queue a browse")
e.advance(0.18)
check(not e.lastBrowse,"an unresolved item cancels the previous debounced browse")

e=boot()
deferRecipeSearch(e)
C_AuctionHouse.SendBrowseQuery({searchString="Manual browse"})
e.advance(0.18)
check(e.lastBrowse.searchString=="Manual browse","a manual browse supersedes debounce with no full scan running")
e.ready=false
wantedBrowse(e,100)
C_AuctionHouse.ReplicateItems()
e.ready=true
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
e.browse={cheap}; browseUpdated(e)
check(e.replicated and e.lastBrowse.searchString=="Manual browse" and not e.selected,
    "replication cancels a throttled recipe search and subsequent browse results")
wantedBrowse(e,100)
C_AuctionHouse.SendBrowseQuery({searchString="New manual browse"})
browseUpdated(e)
check(not e.selected,"a newer manual browse also supersedes a dispatched recipe query")

e=boot()
e.browse={expensive,cheap}
e.app.refreshAllMarketValues(); browseUpdated(e)
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
e.browse={expensive}; e.browseFull=false
e.app.refreshAllMarketValues(); browseUpdated(e)
check(e.ns.MarketScan.GetState().active,"a readable first page leaves the scan active")
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
check(not e.ns.MarketScan.GetState().active and prices[100]==prior and prices[100].qty==11 and daily.lastQ==11,
    "dropping a readable partial scan preserves confirmed stock across variants")

e=boot()
e.browse={{itemKey=key(100),totalQuantity=25,minPrice=100}}
e.app.refreshAllMarketValues(); browseUpdated(e)
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[100],MerchantMasterDB.ahDaily.A[100][1]
for _,qty in ipairs({false,{secret=true},"unreadable",0}) do
    e.advance(1)
    e.browse={{itemKey=key(100),minPrice=70,totalQuantity=qty or nil},other}
    e.app.refreshAllMarketValues(); browseUpdated(e)
    check(prices[100]==prior and prices[100].qty==25 and not prices[100].absent and daily.lastQ==25,
        "a listed item with invalid stock preserves its prior full-scan snapshot and daily quantity")
    check(prices[101].qty==99,"a readable item still updates in the same full scan")
end
e.browse={cheap,{itemKey=key(100,30),minPrice=20}}
e.app.refreshAllMarketValues(); e.browseFull=false; browseUpdated(e)
e.app.cancelMarketScan(true)
check(prices[100]==prior and daily.lastQ==25,"partial scans cannot replace aggregate stock with an incomplete variant sum")
e.browse={cheap,{itemKey={itemID={secret=true}},totalQuantity=18,minPrice=70}}
e.browseFull=true
e.app.refreshAllMarketValues(); browseUpdated(e)
check(prices[100]==prior and daily.lastQ==25,"an unknown variant cannot publish partial positive stock")
check(prices[101].qty==99,"an unknown item identity cannot establish absence")
e.browseFull=false
e.app.refreshAllMarketValues(); browseUpdated(e)
check(e.ns.MarketScan.GetState().active,"the page with an unreadable item leaves a partial scan active")
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
check(not e.ns.MarketScan.GetState().active and prices[100]==prior and daily.lastQ==25,
    "cancelling a partial scan with an unreadable item preserves confirmed stock")
e.browse={other}; e.browseFull=true
e.app.refreshAllMarketValues(); browseUpdated(e)
check(prices[100].absent and daily.lastQ==0,"a complete scan with no listing still records confirmed absence")

e=boot()
e.discover({key(101)})
prices=e.ns.MarketScan.ActiveEconomyPrices()
prior, daily=prices[101],MerchantMasterDB.ahDaily.A[101][1]
e.ready=false; e.lastBrowse=nil; e.browse={}
e.app.refreshAllMarketValues()
browseUpdated(e)
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED",{expensive})
local waiting=e.ns.MarketScan.GetState()
check(not e.lastBrowse and waiting.active and waiting.page==0 and prices[101]==prior and daily.lastQ==10,
    "stale browse events cannot finish or populate a full scan waiting for its first query")
e.ready=true
e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
check(e.lastBrowse and e.lastBrowse.searchString=="","the full scan sends its query when the throttle clears")
e.browse={other}; browseUpdated(e)
check(not e.ns.MarketScan.GetState().active and prices[101].qty==99 and daily.lastQ==99 and prices[100].absent,
    "the dispatched full scan consumes its own results and ignores stale rows")

e=boot()
local browseQueries=0
C_AuctionHouse.SendBrowseQuery=function() browseQueries=browseQueries+1 end
deferRecipeSearch(e)
e.app.refreshAllMarketValues()
e.advance(0.18)
check(e.ns.MarketScan.GetState().active and browseQueries==1,"delayed recipe search cannot cancel a newer full scan")

e=boot(); browseQueries=0
C_AuctionHouse.SendBrowseQuery=function() browseQueries=browseQueries+1 end
deferRecipeSearch(e); e.app.refreshAllMarketValues(); e.app.cancelMarketScan(false)
e.advance(0.18)
check(browseQueries==1,"superseded recipe search stays cancelled after the full scan stops")
deferRecipeSearch(e); e.open=false; e.ns.MarketScan.HandleEvent("AUCTION_HOUSE_CLOSED"); e.open=true
e.advance(0.18)
check(browseQueries==1,"closing and reopening the same AH frame cancels a pending recipe search")
deferRecipeSearch(e)
e.app.scanOrderBookItems({100},1)
e.advance(0.18)
check(browseQueries==1,"order-book scan supersedes a delayed recipe search")
e.app.cancelOrderBookScan()
deferRecipeSearch(e)
e.ns.MarketScan.ScanBagCrates({{name="Bag crate",bundles={{name="Item 100",count=1}}}})
e.advance(0.18)
check(browseQueries==1,"bag scan supersedes a delayed recipe search")
e.app.cancelOrderBookScan()
local origOpenCart = e.app.openCartBuyer
local buyerOpens = 0
e.app.openCartBuyer = function() buyerOpens = buyerOpens + 1; return true end
deferRecipeSearch(e); e.app.multiSearchBuyer({"Item 101"}); e.advance(0.18)
check(buyerOpens==1 and browseQueries==1,"built-in AH buyer multi-search supersedes a delayed recipe search")
e.app.openCartBuyer = origOpenCart

do
    local base, suffix = key(100), key(100, 0, 9)
    local function withBaseSupply()
        local env = boot()
        env.browse = {{itemKey=base, totalQuantity=12, minPrice=100}}
        env.app.refreshAllMarketValues()
        browseUpdated(env)
        return env, MerchantMasterDB.ahDaily.A[100][1], MerchantMasterDB.ahHistory.A[100]
    end
    local function marked()
        local variants = MerchantMasterDB.ahVariants
        return variants and variants.A and variants.A[100] == true
    end

    do
        local env, bucket, ring = withBaseSupply()
        local baseRow = {itemKey=base, totalQuantity=3, minPrice=110}
        local suffixRow = {itemKey=suffix, totalQuantity=9, minPrice=100}
        env.advance(1200)
        env.browse, env.browseFull = {baseRow}, false
        wantedBrowse(env, 100)
        browseUpdated(env)
        env.browseFull = true
        env.ns.MarketScan.HandleEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {baseRow, suffixRow, suffixRow})
        local quote = MerchantMasterDB.ahPrices.A[100]
        check(quote.itemWide and quote.qty == 12 and quote.price == 100 and env.selected == suffixRow,
            "Slice 14 targeted addition includes each full key once and picks the cheapest")
        check(bucket.lastQ == 12 and (bucket.scanUnits or 0) == 0 and ring[#ring].q == 12,
            "Slice 14 targeted addition leaves confirmed history and sale count correct")

        env.browse, env.browseFull = {baseRow}, false
        wantedBrowse(env, 100)
        browseUpdated(env)
        env.browse = {suffixRow}
        env.browseFull = true
        browseUpdated(env)
        check(MerchantMasterDB.ahPrices.A[100].qty == 9,
            "Slice 14 targeted updated event replaces a previous snapshot")
    end
    do
        local env = withBaseSupply()
        local seller = env.ns.SellerStats
        env.rows = {row({"Alice-HomeRealm"}, 1)}
        env.start({base}); env.items()
        env.rows = {}
        env.start({suffix}); env.items()
        local stale = seller.Begin(suffix, "A")
        seller.Observe(stale, {}, true, false)
        local initial = seller.Get(100, "A")
        check(initial.count == 1 and initial.status == "complete", "Slice 14 previously empty suffix fixture")
        env.browse = {
            {itemKey=base, totalQuantity=3, minPrice=100},
            {itemKey=suffix, totalQuantity=9, minPrice=200},
        }
        wantedBrowse(env, 100)
        browseUpdated(env)
        local pending = seller.Get(100, "A")
        check(pending.count == 1 and pending.status == "partial", "Slice 14 live suffix invalidates its empty seller observation")
        seller.Publish(stale)
        check(seller.Get(100, "A").status == "partial", "An observation from before Browse cannot clear the pending suffix")
        env.rows = {row({"Bob-HomeRealm"}, 1)}
        env.full = false
        env.start({suffix}, false); env.items()
        check(seller.Get(100, "A").status == "partial", "Slice 14 an incomplete suffix observation keeps coverage partial")
        env.full = true
        env.start({suffix}); env.items()
        local fresh = seller.Get(100, "A")
        check(fresh.count == 2 and fresh.status == "complete", "Slice 14 a subsequent complete suffix observation restores coverage")
    end
    local env, bucket, ring = withBaseSupply()
    local moreRequested, markedBeforePaging
    C_AuctionHouse.RequestMoreItemSearchResults = function()
        moreRequested = true
        markedBeforePaging = marked()
    end
    env.advance(1200)
    env.full = false
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 900)}
    env.rows[1].quantity = 9
    env.start({suffix}); env.items(); env.advance(1)
    local stillPaging = env.ns.MarketScan.GetBagStatus() ~= nil
    env.full = true
    env.rows[1].quantity = 3
    env.items(base)
    check(moreRequested and markedBeforePaging and stillPaging
        and bucket.lastQ == 12 and (bucket.scanUnits or 0) == 0 and #ring == 1 and ring[1].q == 12,
        "Active suffix supply is marked before paging and protects all 12 listings from false sales")

    env, bucket, ring = withBaseSupply()
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 900)}
    env.rows[1].quantity, env.rows[1].buyoutAmount = 9, {secret=true}
    env.start({suffix}); env.items()
    check(marked() and not env.ns.MarketScan.GetBagStatus(),
        "Active suffix supply is marked on its first and final page even when its buyout is unreadable")
    env.rows = {}
    env.start({suffix}); env.items()
    check(#env.ns.SellerStats.GetKeys(100, "A") == 2 and marked(),
        "An empty refresh preserves previously observed suffix supply")

    env, bucket, ring = withBaseSupply()
    env.start({suffix}); env.items()
    local signature = env.ns.SellerStats.Key(suffix)
    local empty = MerchantMasterDB.sellerStats.A.keys[signature]
    check(empty and empty.count == 0 and empty.status == "complete" and empty.at == time(),
        "The empty suffix still records a complete seller observation and its timestamp")
    local keys = env.ns.SellerStats.GetKeys(100, "A")
    env.advance(1200)
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 500)}
    env.rows[1].quantity = 5
    env.items(base)
    check(#keys == 1 and keys[1].itemSuffix == 0 and not marked() and MerchantMasterDB.ahPrices.A[100].itemWide == true
        and bucket.lastQ == 5 and bucket.at == time() and #ring == 2 and ring[2].q == 5,
        "An empty active suffix search leaves base supply coverage and lets history update from 12 to 5")
    local snapshots = MerchantMasterDB.ahSnapshots.A[100]
    check(#snapshots == 6 and snapshots[4] == time() and snapshots[5] == 100 and snapshots[6] == 5,
        "Confirmed item-wide order-book results record per-unit price and total stock")

    env, bucket, ring = withBaseSupply()
    local seller, market = env.ns.SellerStats, env.ns.MarketScan
    seller.RecordBrowse("A", {base, suffix}, true)
    local saved = MerchantMasterDB.sellerStats.A
    saved.incompleteItems[100] = true
    check(not marked() and market.HasKnownVariants(100, "A"),
        "Legacy seller coverage identifies the suffix without a market marker")
    local confirmed = MerchantMasterDB.ahPrices.A[100]
    env.advance(1200)
    env.browse = {
        {itemKey=base, totalQuantity=3, minPrice=300},
        {itemKey=key({secret=true}), totalQuantity=9, minPrice=100},
        {itemKey=key(101), totalQuantity=5, minPrice=200},
    }
    env.app.refreshAllMarketValues()
    browseUpdated(env)
    check(MerchantMasterDB.ahPrices.A[100] == confirmed,
        "Browse with an unreadable item ID preserves the confirmed item-wide quote")
    check(market.HasKnownVariants(100, "A"),
        "Browse with an unreadable item ID preserves the known suffix")
    check(not saved.coverageComplete and saved.incompleteItems[100] and #seller.GetKeys(101, "A") == 1,
        "Incomplete Browse merges readable keys and preserves item-level incomplete coverage")
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 900)}
    env.rows[1].quantity = 3
    env.items(base)
    local quote = MerchantMasterDB.ahPrices.A[100]
    check(quote.qty == 3 and quote.price == 300 and quote.itemWide == false,
        "Following base search publishes three listings as base-key only")
    check(bucket.lastQ == 12 and (bucket.scanUnits or 0) == 0 and #ring == 1 and ring[1].q == 12,
        "Following base search keeps the 12 confirmed listings and records no false sales")

    env, bucket, ring = withBaseSupply()
    seller, market = env.ns.SellerStats, env.ns.MarketScan
    env.advance(1200)
    env.browse = {
        {itemKey=base, totalQuantity=3, minPrice=100},
        {itemKey=key({secret=true}), totalQuantity=9, minPrice=100},
    }
    env.app.refreshAllMarketValues()
    browseUpdated(env)
    local markers = MerchantMasterDB.ahVariants and MerchantMasterDB.ahVariants.A
    check(markers and markers._unidentified and not markers[100] and #seller.GetKeys(100, "A") == 1
        and not market.HasKnownVariants(100, "B"),
        "An unidentified Browse row persists uncertainty only in its economy, without a saved suffix")
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 300)}
    env.rows[1].quantity = 3
    env.items(base)
    quote = MerchantMasterDB.ahPrices.A[100]
    check(quote.qty == 3 and quote.itemWide == false and bucket.lastQ == 12
        and (bucket.scanUnits or 0) == 0 and #ring == 1 and ring[1].q == 12,
        "Base search after an unidentified Browse keeps 12 confirmed listings and records no sales")
    env.discover({base, key(101, 0, {secret=true})})
    check(markers and markers._unidentified, "A Browse with incomplete key coverage keeps unidentified-row uncertainty")
    env.discover({base})
    check(markers and not markers._unidentified and not market.HasKnownVariants(100, "A"),
        "Only a complete readable Browse clears unidentified-row uncertainty")

    env, bucket, ring = withBaseSupply()
    saved = MerchantMasterDB.sellerStats.A
    env.advance(1200)
    env.browse = {
        {itemKey=base, totalQuantity=3, minPrice=100},
        {itemKey=key(100, 0, {secret=true}), totalQuantity=9, minPrice=90},
    }
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 300)}
    env.rows[1].quantity = 3
    wantedBrowse(env, 100)
    local markedBeforeSelection
    AuctionHouseFrame.SelectBrowseResult = function(_, result)
        markedBeforeSelection = saved.incompleteItems[100]
        env.selected = result
        env.items(base)
    end
    browseUpdated(env)
    quote = MerchantMasterDB.ahPrices.A[100]
    check(env.selected == env.browse[1] and markedBeforeSelection and saved.coverageComplete,
        "Targeted Browse marks the unreadable variant before selecting the readable base row")
    check(quote.qty == 3 and quote.itemWide == false and bucket.lastQ == 12
        and (bucket.scanUnits or 0) == 0 and #ring == 1 and ring[1].q == 12,
        "Search triggered by targeted Browse keeps 12 confirmed listings and records no sales")
    env.discover({base})
    check(not saved.incompleteItems[100], "Complete readable Browse clears the targeted item marker")

    for _, scenario in ipairs({"pending page", "unreadable item ID", "unreadable unrelated key", "restricted query"}) do
        env, bucket, ring = withBaseSupply()
        seller = env.ns.SellerStats
        saved = MerchantMasterDB.sellerStats.A
        env.advance(1200)
        env.browse = {{itemKey=base, totalQuantity=3, minPrice=100}}
        if scenario == "pending page" then
            env.browseFull = false
        elseif scenario == "unreadable item ID" then
            env.browse[2] = {itemKey=key({secret=true}), totalQuantity=9, minPrice=90}
        elseif scenario == "unreadable unrelated key" then
            env.browse[2] = {itemKey=key(101, 0, {secret=true}), totalQuantity=9, minPrice=90}
        else
            local send = C_AuctionHouse.SendBrowseQuery
            C_AuctionHouse.SendBrowseQuery = function(query)
                query.filters = {1}
                send(query)
            end
        end
        env.rows = {row({"Alice-HomeRealm"}, 1, false, 300)}
        env.rows[1].quantity = 3
        wantedBrowse(env, 100)
        AuctionHouseFrame.SelectBrowseResult = function(_, result)
            markedBeforeSelection = saved.incompleteItems[100]
            env.selected = result
            env.items(base)
        end
        markedBeforeSelection = nil
        browseUpdated(env)
        quote = MerchantMasterDB.ahPrices.A[100]
        check(env.selected == env.browse[1] and markedBeforeSelection and not seller.HasIncompleteCoverage(100, "B"),
            "Targeted Browse saves coverage uncertainty before selection for " .. scenario)
        check(quote.qty == 3 and quote.itemWide == false and bucket.lastQ == 12
            and (bucket.scanUnits or 0) == 0 and #ring == 1 and ring[1].q == 12,
            "Search following " .. scenario .. " preserves 12 confirmed listings and records no sales")
    end

    env = withBaseSupply()
    seller = env.ns.SellerStats
    env.rows = {row({"Alice-HomeRealm"}, 1)}
    env.start(); env.items()
    local before = seller.Get(100, "A")
    check(before.status == "complete" and before.count == 1, "The targeted seller item starts with one complete base observation")
    env.browse = {
        {itemKey=base, totalQuantity=3, minPrice=100},
        {itemKey=suffix, totalQuantity=9, minPrice=200},
    }
    wantedBrowse(env, 100)
    local selectedCoverage
    AuctionHouseFrame.SelectBrowseResult = function(_, result)
        env.selected = result
        selectedCoverage = seller.Get(100, "A")
    end
    browseUpdated(env)
    check(env.selected == env.browse[1] and selectedCoverage.status == "partial" and selectedCoverage.count == 1
        and #seller.GetKeys(100, "A") == 2 and #seller.GetKeys(100, "B") == 0,
        "Before selection, the newly observed suffix joins the seller keys and makes the count partial")
    env.ns.MarketScan.ScanSellers({100})
    env.advance(1)
    check(env.lastKey.itemSuffix == 0, "The seller refresh starts with the base key")
    env.items(); env.advance(1)
    check(env.lastKey.itemSuffix == 9 and seller.Get(100, "A").status == "partial",
        "The seller refresh also queues the new suffix and waits for its observation")
    env.rows = {row({"Bob-HomeRealm"}, 1)}
    env.items()
    local refreshed = seller.Get(100, "A")
    check(refreshed.status == "complete" and refreshed.count == 2,
        "The complete suffix observation restores complete seller coverage")

    env, bucket, ring = withBaseSupply()
    seller, market = env.ns.SellerStats, env.ns.MarketScan
    saved = MerchantMasterDB.sellerStats.A
    check(not market.HasKnownVariants(100, "A"), "Confirmed supply starts with only a base key")
    env.advance(1200)
    env.browse = {
        {itemKey=base, totalQuantity=3, minPrice=100},
        {itemKey=key(100, 0, {secret=true}), totalQuantity=9, minPrice=100},
    }
    env.app.refreshAllMarketValues()
    browseUpdated(env)
    check(saved.incompleteItems[100] and #seller.GetKeys(100, "A") == 1
        and market.HasKnownVariants(100, "A") and not market.HasKnownVariants(100, "B"),
        "Unreadable suffix persists incomplete variant coverage for the identified item and economy")
    env.rows = {row({"Alice-HomeRealm"}, 1, false, 300)}
    env.rows[1].quantity = 3
    env.items(base)
    quote = MerchantMasterDB.ahPrices.A[100]
    check(quote.qty == 3 and quote.itemWide == false and bucket.lastQ == 12
        and (bucket.scanUnits or 0) == 0 and #ring == 1 and ring[1].q == 12,
        "Base-only search after an unreadable suffix retains 12 confirmed listings and records no sales")
    env.browse = {{itemKey=key(101, 0, {secret=true}), totalQuantity=1, minPrice=100}}
    env.browseFull = false
    env.app.refreshAllMarketValues()
    browseUpdated(env)
    env.app.cancelMarketScan(true)
    check(saved.incompleteItems[100] and saved.incompleteItems[101],
        "Cancelling a paged Browse retains both the prior and newly observed item markers")
    env.browseFull = true
    env.discover({base})
    check(saved.coverageComplete and next(saved.incompleteItems) == nil and not market.HasKnownVariants(100, "A"),
        "A complete readable Browse clears incomplete variant coverage")
    env.advance(1200)
    env.items(base)
    check(MerchantMasterDB.ahPrices.A[100].itemWide == true and bucket.lastQ == 3,
        "Base search resumes item-wide history after a complete readable Browse")

    env = boot()
    env.browseFull = false
    env.browse = {{itemKey=base, totalQuantity=3, minPrice=300}}
    env.app.refreshAllMarketValues()
    browseUpdated(env)
    env.app.cancelMarketScan(true)
    local partial = MerchantMasterDB.ahPrices.A[100]
    check(partial and partial.qty == 3 and partial.price == 300 and partial.itemWide == false,
        "A partial Browse cache entry explicitly lacks item-wide coverage")
end

-- Confirmed Browse refreshes write flat intra-day snapshots alongside the legacy histories.
do
    local hour, day = 3600, 86400
    local env = boot()
    local itemKey = key(100)
    local function refresh(price, qty)
        env.browse = { { itemKey = itemKey, minPrice = price, totalQuantity = qty } }
        env.app.refreshAllMarketValues()
        browseUpdated(env)
    end
    local function checkSnapshots(expected, reason)
        local snapshots = MerchantMasterDB.ahSnapshots and MerchantMasterDB.ahSnapshots.A
        local values = snapshots and snapshots[100]
        check(type(values) == "table" and #values == #expected, reason .. " stores the expected number of values")
        local count = 0
        for index, value in pairs(values) do
            check(type(value) == "number" and expected[index] == value,
                reason .. " stores the expected numeric value at " .. tostring(index))
            count = count + 1
        end
        check(count == #expected, reason .. " stores a dense array of triplets")
    end

    local boundary = 3 * day + hour
    local start = boundary - 300
    env.advance(start - time())
    refresh(100, 20)
    env.advance(30)
    refresh(110, 20)
    env.advance(30)
    refresh(110, 17)
    checkSnapshots({ start, 100, 20, start + 30, 110, 20, start + 60, 110, 17 },
        "Price-only and quantity-only refreshes within a minute")
    env.advance(30)
    refresh(110, 17)
    env.advance(30)
    refresh(110, 17)
    checkSnapshots({ start, 100, 20, start + 30, 110, 20, start + 60, 110, 17, start + 120, 110, 17 },
        "Same-hour plateau keeps its first and latest observation")
    local newHourRefresh = boundary + 60
    env.advance(newHourRefresh - time())
    refresh(110, 17)
    local acrossHours = { start, 100, 20, start + 30, 110, 20, start + 60, 110, 17, start + 120, 110, 17,
        newHourRefresh, 110, 17 }
    checkSnapshots(acrossHours, "Identical refresh in a new hour of the same day")
    env.advance(-1)
    refresh(400, 2)
    checkSnapshots(acrossHours, "Stale refresh within the latest hour leaves the snapshot series intact")

    env = boot()
    env.advance(boundary - time())
    refresh(100, 20)
    env.advance(1)
    refresh(105, 19)
    env.advance(36 * hour - 1)
    refresh(110, 18)
    local cutoff = time()
    checkSnapshots({ boundary, 100, 20, boundary + 1, 105, 19, cutoff, 110, 18 },
        "A snapshot exactly 36 hours old is retained")
    env.advance(1)
    refresh(115, 17)
    checkSnapshots({ boundary + 1, 105, 19, cutoff, 110, 18, cutoff + 1, 115, 17 },
        "A snapshot older than 36 hours is pruned")

    env = boot()
    start = time()
    local expected = {}
    for i = 1, 100 do
        refresh(100 + i, 200 - i)
        if i > 4 then
            local n = #expected
            expected[n + 1], expected[n + 2], expected[n + 3] = time(), 100 + i, 200 - i
        end
        if i < 100 then env.advance(600) end
    end
    check(#expected == 288, "Snapshot cap fixture has 96 retained triplets")
    checkSnapshots(expected, "Snapshot cap keeps the newest 96 triplets in order")
    local history = MerchantMasterDB.ahHistory.A[100]
    check(#history == 16 and history[1].t == start + 84 * 600 and history[16].t == time(),
        "Legacy AH history keeps at most 16 refreshes")
    for i = 1, 16 do
        env.advance(day)
        refresh(200 + i, 20)
    end
    local daily = MerchantMasterDB.ahDaily.A[100]
    local today = math.floor(time() / day)
    check(#daily == 14 and daily[1].d == today - 13 and daily[14].d == today and daily[14].lastP == 216,
        "Legacy daily history keeps the newest 14 buckets")
end

-- The 24-hour trend merges only observed hours and estimates sales from chronological pairs.
do
    local market = boot().ns.MarketScan
    local hour, curHour = 3600, 73
    local startHour = curHour - 23
    local first, current = startHour * hour, curHour * hour
    local now = current + 1200
    local db = MerchantMasterDB
    db.ahSnapshots = { A = { [100] = {
        first - 1, 999, 99,
        first, 100, 50,
        current - 300, 130, 20,
        current + 300, 140, 12,
        current + 900, 140, 8,
        now, 130, 3,
        now + 1, 999, 99,
    } } }
    db.ahHistory = { A = { [100] = {
        { t = first + 60, p = 999, q = 99 },
        { t = first + hour + 60, p = 110, q = 40 },
        { t = first + hour + 600, p = 115, q = 35 },
        { t = current + 1000, p = 999, q = 99 },
    } } }
    db.ahDaily = { A = { [100] = {
        { d = 2, at = first + 4 * hour + 60, lastP = 125, lastQ = 27 },
        { d = 3, at = current + 1100, obsP = 999, lastP = 998, lastQ = 99 },
    } } }

    local trend = market.GetItemTrend24h(100, "A", now)
    check(trend.startHour == startHour and trend.curHour == curHour and trend.source == "ahSnapshots",
        "24-hour trend uses the inclusive observation window and prioritizes snapshots")
    local stamps = { first, first + hour + 60, first + hour + 600, first + 4 * hour + 60,
        current - 300, current + 300, current + 900, now }
    check(#trend.rawPoints == #stamps, "Trend excludes old, future, and lower-priority observations in covered hours")
    for i, stamp in ipairs(stamps) do
        check(trend.rawPoints[i].stamp == stamp, "Trend orders observations by timestamp across sources")
    end
    local expectedHours = { startHour, startHour + 1, startHour + 4, curHour - 1, curHour }
    check(trend.hoursCollected == #expectedHours and #trend.points == #expectedHours and not trend.hasFullDay,
        "Trend counts only hours with recorded observations")
    local byHour = {}
    for i, point in ipairs(trend.points) do
        check(point.h == expectedHours[i], "Trend aggregates observations into chronological hours")
        byHour[point.h] = point
    end
    check(byHour[startHour + 2] == nil and byHour[curHour - 2] == nil, "Unobserved hours remain nil gaps")
    local history, daily = byHour[startHour + 1], byHour[startHour + 4]
    check(history.price == 115 and history.qty == 35 and history.at == first + hour + 600,
        "An uncovered hour uses the latest legacy history observation")
    check(daily.price == 125 and daily.qty == 27 and daily.at == first + 4 * hour + 60 and daily.salesPerDay == nil,
        "A daily-only hour uses its recorded timestamp and legacy last price without inventing sales")
    local latest = byHour[curHour]
    check(latest.at == now and latest.price == 130 and latest.observedPrice == 130 and latest.qty == 3,
        "The current hour shows the latest observation instead of the highest price or stock")
    -- The cross-hour drop counts 8 sales, followed by 4 * 0.55 and 5 * 0.20 within the hour.
    check(latest.salesPerDay and math.abs(latest.salesPerDay - 44.8) < 1e-9,
        "Sales per day includes the cross-hour pair and both intra-hour pairs")
    check(trend.startPrice24h == 100 and trend.currentPrice == 130 and trend.trendPct == 30 and trend.direction == "up",
        "Trend compares the first and last observed hourly prices")

    db.ahSnapshots.A[100] = nil
    local legacy = market.GetItemTrend24h(100, "A", now)
    check(legacy.source == "ahHistory" and legacy.hoursCollected == 4 and legacy.points[3].price == 125
        and legacy.points[4].at == current + 1000, "History and daily observations fill a legacy trend with no snapshots")
    db.ahHistory.A[100] = nil
    local dailyOnly = market.GetItemTrend24h(100, "A", now)
    check(dailyOnly.source == "ahDaily" and dailyOnly.hoursCollected == 2 and dailyOnly.currentPrice == 999,
        "A daily-only trend uses each day's observed price and timestamp")

    local fullDay = {}
    for h = startHour, curHour do
        local n = #fullDay
        fullDay[n + 1], fullDay[n + 2], fullDay[n + 3] = h * hour, 200, 10
    end
    db.ahSnapshots.B = { [100] = fullDay }
    local full = market.GetItemTrend24h(100, "B", now)
    check(full.hasFullDay and full.hoursCollected == 24 and full.direction == "flat" and full.currentPrice == 200,
        "A separate economy with a quote in every hour has a full day of data")
    local empty = market.GetItemTrend24h(101, "A", now)
    check(empty.source == "none" and empty.hoursCollected == 0 and #empty.points == 0 and #empty.rawPoints == 0,
        "An item without observations has an empty trend")
end

print("WP4 sellers: "..checks.." assertions, 0 failures")
