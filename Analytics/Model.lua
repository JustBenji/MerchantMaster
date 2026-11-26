local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
_G.MerchantMasterAnalytics = ns
local function H()
    return host
end

local Model = { generation=1 }; ns.Model = Model
Model.TYPE_LABELS = {
    AH_BUY = "AH Buy", AH_POST = "AH Post", AH_SELL = "AH Sell",
    AH_CANCEL = "AH Cancel", AH_EXPIRE = "AH Expire",
    AH_BID = "AH Bid", AH_OUTBID = "AH Outbid",
    VENDOR_BUY = "Vendor Buy", VENDOR_SELL = "Vendor Sell", VENDOR_BUYBACK = "Buyback",
    TRAINER_FEE = "Trainer Fee",
    GUILD_DEPOSIT = "Guild Deposit", GUILD_WITHDRAW = "Guild Withdraw",
    CRAFT = "Craft", DESTROY = "Destroy",
    DISENCHANT_BROKEN = "DE Broken", DISENCHANT_RECEIVE = "DE Receive",
    WRIT_TURNIN = "Writ Turn-In", CRATE_TURNIN = "Crate Turn-In",
    POUCH_MONEY = "Coin Pouch", QUEST_MONEY = "Quest Gold",
    FAVOR_GAIN = "Favor Gain", FAVOR_SPEND = "Favor Spend",
    STANDING = "Standing", ADJUST = "Adjust",
    REPAIR = "Repair", POSTAGE = "Postage", MONEY_TRANSFER = "Transfer",
    COD_BUY = "COD Buy", COD_SELL = "COD Sell",
    TRADE_BUY = "Trade Buy", TRADE_SELL = "Trade Sell",
    LOOT = "Loot", GATHER = "Gather", MONEY_LOOT = "Loot Gold",
    OTHER_INCOME = "Other Income", OTHER_EXPENSE = "Other Expense",
    AUCTION_LOG = "Auction Log",
}
local Store=ns.Store
local pairs,ipairs,next,type,tonumber,tostring=pairs,ipairs,next,type,tonumber,tostring
local floor,min,max,abs=math.floor,math.min,math.max,math.abs
local strlower,strfind=string.lower,string.find
local tsort,tconcat=table.sort,table.concat
-- Only the deferred aggregate worker yields; synchronous callers share these calculations.
local preparer,workCount
local function checkpoint()
    if preparer and coroutine.running()==preparer then
        workCount=(workCount or 0)+1
        if workCount>=40 then workCount=0; coroutine.yield() end
    end
end
local function sortRows(rows,less)
    if not preparer or coroutine.running()~=preparer then tsort(rows,less); return end
    local width,n=1,#rows
    while width<n do
        local merged={}
        for first=1,n,width*2 do
            local left,right,mid,last=first,first+width,min(n,first+width-1),min(n,first+width*2-1)
            for out=first,last do
                checkpoint()
                if left<=mid and (right>last or not less(rows[right],rows[left])) then merged[out]=rows[left]; left=left+1
                else merged[out]=rows[right]; right=right+1 end
            end
        end
        for i=1,n do checkpoint(); rows[i]=merged[i] end
        width=width*2
    end
end
local function nowSec() return (_G.time and _G.time()) or (os and os.time and os.time()) or 0 end
local function db() return Store.db or _G.MerchantMasterLedgerDB or {} end
local function charMatches(char,f)
    if f.chars and f.chars[char]~=true then return false end
    if f.char and f.char~="all" and f.char~=char then return false end
    if f.econ then
        local meta=_G.MerchantMasterDB and _G.MerchantMasterDB.chars and _G.MerchantMasterDB.chars[char]
        local econ=type(meta)=="table" and (meta.economy or meta.econ) or nil
        if char~=f.econ and econ~=f.econ and Store.DeriveEcon(char)~=f.econ then return false end
    end
    if f.faction and f.faction~="all" then
        local meta=_G.MerchantMasterDB and _G.MerchantMasterDB.chars and _G.MerchantMasterDB.chars[char]
        if not meta or meta.faction~=f.faction then return false end
    end
    return true
end
local function rollKeyMatches(key,f)
    return charMatches(key,f)
end
function Model.CharShort(char)
    if type(char)~="string" or char=="" then return "-" end
    local hostChars=_G.MerchantMasterDB and _G.MerchantMasterDB.chars
    local info=hostChars and hostChars[char]
    if type(info)=="table" and type(info.name)=="string" and info.name~="" then
        local econ=tostring(info.economy or Store.DeriveEcon(char) or ""):gsub("%-","/")
        return econ~="" and (info.name.." ("..econ..")") or info.name
    end
    local econ,_,player=char:match("^([^%-]+%-[^%-]+)%-(.-)%-([^%-]+)$")
    if player and econ then return player.." ("..econ:gsub("%-","/")..")" end
    return char
end
local function contains(s,needle) return needle=="" or strfind(strlower(tostring(s or "")),needle,1,true)~=nil end
local function sortedKeys(t) local keys={}; for k in pairs(t) do keys[#keys+1]=k end; tsort(keys); return keys end
local function professionMatches(itemID,needle)
    local h=H(); local recipes=h and h.RECIPES_BY_OUTPUT and h.RECIPES_BY_OUTPUT[itemID]
    if type(recipes)=="table" then
        if recipes.prof or recipes.profession or recipes.professionName or recipes.profKey or recipes.category then recipes={recipes} end
        for _,recipe in pairs(recipes) do if type(recipe)=="table" and contains(recipe.prof or recipe.profession or recipe.professionName or recipe.profKey or recipe.category,needle) then return true end end
    end
    local writ=Model.GetIndexes().WRIT_BY_ITEM[itemID]
    return type(writ)=="table" and contains(writ.prof or writ.profession or writ.category or writ.tier or "",needle) or false
end
function Model.PeriodBounds(period,now)
    now=now or nowSec(); local today=Store.DayKey(now)
    if period=="all" then return "0000-00-00","9999-99-99" end
    local n=tonumber(tostring(period or ""):match("^(%d+)d$"))
    local days=period=="today" and 0 or (n and n-1) or 29
    return Store.DayKey(now-days*86400),today
end
local indexes,indexHost
function Model.GetIndexes()
    local h=H()
    if indexes and indexHost==h then return indexes end
    indexes={RECIPE_BY_SCROLL={},RECIPE_BY_SPELL={},WRIT_BY_ITEM={},WRIT_BY_QUEST={},CRATE_BY_QUEST={}}; indexHost=h
    if not h then return indexes end
    for _,rec in pairs(h.RECIPES or {}) do
        if rec.recipeItemID and not rec.toolItemID then indexes.RECIPE_BY_SCROLL[rec.recipeItemID]=rec end
        if rec.spellID then indexes.RECIPE_BY_SPELL[rec.spellID]=rec end
    end
    for _,w in pairs(h.WRITS or {}) do
        if w.itemID then indexes.WRIT_BY_ITEM[w.itemID]=w end
        if w.questID then indexes.WRIT_BY_QUEST[w.questID]=w end
    end
    for tier,rewards in pairs(h.DEFAULT_REWARDS or {}) do for idx,r in pairs(rewards) do
        if r.questID then indexes.CRATE_BY_QUEST[r.questID]={tier=tier,idx=idx,tokens=r.tokens,copper=r.copper,sealedID=r.sealedID,unconfirmed=r.unconfirmed} end
    end end
    return indexes
end
function Model.ItemName(itemID)
    local h=H(); return (h and h.ItemName and h.ItemName(itemID)) or (_G.GetItemInfo and _G.GetItemInfo(itemID)) or ("Item #"..tostring(itemID))
end
function Model.ItemIcon(itemID)
    local h=H(); return (h and h.ItemIcon and h.ItemIcon(itemID,134400)) or 134400
end
function Model.MarketOrVendorPrice(itemID)
    local h=H(); if not h then return 0 end
    if h.BeginEval then h.BeginEval(h.app and h.app.getUIPriceBank and h.app.getUIPriceBank()) end
    local ok,value=pcall(function() return (h.GetItemMarketPrice and h.GetItemMarketPrice(itemID)) or (h.GetVendorSellPrice and h.GetVendorSellPrice(itemID)) or 0 end)
    if h.EndEval then h.EndEval() end
    return ok and (tonumber(value) or 0) or 0
end
local function itemRows(f,from,to)
    local totals={}; local now=nowSec(); local last7=Store.DayKey(now-6*86400); local prev7=Store.DayKey(now-13*86400); local prevEnd=Store.DayKey(now-7*86400); local today=Store.DayKey(now)
    local recent={}
    for day,econs in pairs(db().roll or {}) do
        local inPeriod=day>=from and day<=to; local inRecent=day>=prev7 and day<=today
        if inPeriod or inRecent then for ck,items in pairs(econs) do if rollKeyMatches(ck,f) then for id,r in pairs(items) do checkpoint();
            if inPeriod and tonumber(id) and tonumber(id)>0 then
                local row=totals[id]; if not row then row={itemID=id}; totals[id]=row end
                for _,key in ipairs(Store.ROLL_FIELDS) do row[key]=(row[key] or 0)+(r[key] or 0) end
                if r.ahSold then row.ahSold=(row.ahSold or 0)+r.ahSold end
            end
            if inRecent then
                local rr=recent[id] or {last=0,prev=0,ahLast=0,ahPrev=0}; recent[id]=rr
                if day>=last7 then rr.last=rr.last+(r.sold or 0); rr.ahLast=rr.ahLast+(r.ahSold or 0)
                elseif day<=prevEnd then rr.prev=rr.prev+(r.sold or 0); rr.ahPrev=rr.ahPrev+(r.ahSold or 0) end
            end
        end end end end
    end
    local rows={}; local needle=strlower(f.search or "")
    for id,row in pairs(totals) do checkpoint();
        row.name=Model.ItemName(id); row.icon=Model.ItemIcon(id); row.profit=row.gross-row.fee-row.cogs-row.depLost; row.est=row.estUnits>0
        row.knownRankTier=row.est and 1 or 0; row.closedTotal=row.sold+row.expired+row.cancelled; row.n=row.posted
        row.sellThrough=(row.posted>=5 and row.closedTotal>0) and row.sold/row.closedTotal or nil
        row.daysToSell=row.dtUnits>0 and (row.dtSum/row.dtUnits)/86400 or nil
        local rr=recent[id] or {last=0,prev=0,ahLast=0,ahPrev=0}; row.soldLast7=rr.last; row.soldPrev7=rr.prev; row.velocity=rr.last/7; row.prevVelocity=rr.prev/7
        row.slowRatio=rr.prev>0 and rr.last/rr.prev or nil; row.isSlowing=rr.prev>=3 and row.slowRatio~=nil and row.slowRatio<0.6 or false
        row.ahSold=row.ahSold or 0; row.ahSoldLast7=rr.ahLast; row.ahSoldPrev7=rr.ahPrev
        row.ahVelocity=rr.ahLast/7; row.ahPrevVelocity=rr.ahPrev/7
        row.ahSlowRatio=rr.ahPrev>0 and rr.ahLast/rr.ahPrev or nil
        row.ahIsSlowing=rr.ahPrev>=3 and row.ahSlowRatio~=nil and row.ahSlowRatio<0.6 or false
        row.ahSellThrough=row.ahSold+row.expired>=3 and row.ahSold/(row.ahSold+row.expired) or nil
        row.cancelChurn=row.posted>=1 and row.cancelled/row.posted or nil
        row.relists=row.relisted; row.reprices=row.repriced
        if contains(row.name,needle) and (f.knownCostOnly==false or not row.est or f.rankSeparate) then rows[#rows+1]=row end
    end
    sortRows(rows,function(a,b)
        if f.knownCostOnly~=false and f.rankSeparate and a.knownRankTier~=b.knownRankTier then return a.knownRankTier<b.knownRankTier end
        local mode=f.mode or f.itemMode
        if mode=="turnaround" and a.daysToSell~=b.daysToSell then return (a.daysToSell or math.huge)<(b.daysToSell or math.huge)
        elseif mode=="slowing" and a.slowRatio~=b.slowRatio then return (a.slowRatio or math.huge)<(b.slowRatio or math.huge)
        elseif mode=="relists" and a.relists~=b.relists then return a.relists>b.relists end
        if a.profit==b.profit then return a.itemID<b.itemID end; return a.profit>b.profit
    end)
    return {rows=rows}
end

-- Accounting views use transaction records for prices and consecutive auction
-- outcomes, while rollups remain the fast source for the existing item totals.
local function selectedChar(char,f)
    return charMatches(char,f)
end
local function selectedSource(row,f)
    local choices=f.sources or (f.source and { [f.source]=true })
    if not choices or f.source=="all" then return true end
    local source=(row.extra and row.extra.source) or row.where or ""
    local kind=tostring(row.type or "")
    local map={
        AH={AH_BUY=true,AH_POST=true,AH_SELL=true,AH_EXPIRE=true,AH_CANCEL=true,AH_BID=true,AH_OUTBID=true,AUCTION_LOG=true},
        Vendor={VENDOR_BUY=true,VENDOR_SELL=true,VENDOR_BUYBACK=true,REPAIR=true,TRAINER_FEE=true},
        ["Vendor/Other"]={VENDOR_BUY=true,VENDOR_SELL=true,VENDOR_BUYBACK=true,REPAIR=true,TRAINER_FEE=true,OTHER_INCOME=true,OTHER_EXPENSE=true},
        Guild={GUILD_DEPOSIT=true,GUILD_WITHDRAW=true},
        Craft={CRAFT=true,DESTROY=true,DISENCHANT_BROKEN=true,DISENCHANT_RECEIVE=true}, COD={COD_BUY=true,COD_SELL=true},
        Trade={TRADE_BUY=true,TRADE_SELL=true}, Mail={POSTAGE=true,MONEY_TRANSFER=true,AH_OUTBID=true},
        ["Quest/Loot"]={LOOT=true,GATHER=true,MONEY_LOOT=true,QUEST_MONEY=true,WRIT_TURNIN=true,CRATE_TURNIN=true,POUCH_MONEY=true},
    }
    for k,v in pairs(choices) do
        local name=type(k)=="number" and v or k
        local types=map[name]
        if v and ((types and types[kind]) or (source~="" and source:find(name,1,true))) then return true end
    end
    return false
end
local function rowMeta(id,f)
    local result={}; local roll=db().itemStats or db().itemMeta or {}; local economy
    if f.econ then economy=f.econ elseif f.char and f.char~="all" then economy=Store.DeriveEcon(f.char) end
    if economy then return roll[economy] and roll[economy][id] or {} end
    for _,items in pairs(roll) do if items[id] then for k,v in pairs(items[id]) do
        if k=="minBuy" or k=="minSell" then result[k]=result[k] and min(result[k],v) or v
        elseif k=="maxBuy" or k=="maxSell" then result[k]=result[k] and max(result[k],v) or v
        elseif k=="lastSoldTs" or k=="lastBuyTs" then if not result[k] or v>result[k] then result[k]=v end
        elseif result[k]==nil then result[k]=v end
    end end end
    return result
end
local baseItemRows=itemRows
local function richItemRows(f,from,to)
    local baseFilters={}; for k,v in pairs(f) do baseFilters[k]=v end
    local needle=strlower(f.search or ""); baseFilters.search=""
    local old=baseItemRows(baseFilters,from,to); local out,totals={}, {qtySold=0,qtyBought=0,gross=0,spent=0,fee=0,cogs=0,depLost=0,profit=0}
    local details={}; local now=nowSec(); local d180=Store.DayKey(now-179*86400); local scanFrom=from<d180 and from or d180
    local last7,prev7,today=Store.DayKey(now-6*86400),Store.DayKey(now-13*86400),Store.DayKey(now)
    local sourceFiltered=(f.source and f.source~="all") or f.sources~=nil
    local sources=f.sources or {}; local ahOnly=f.source=="AH" or (sources.AH==true or sources[1]=="AH")
    if f.sources then for k,v in pairs(sources) do if v and (type(k)=="number" and v or k)~="AH" then ahOnly=false end end end
    local recent={}
    if not sourceFiltered then
        for day,chars in pairs(db().roll or {}) do if day>=d180 and day<=to then
            for char,items in pairs(chars) do if rollKeyMatches(char,f) then
                for id,r in pairs(items) do checkpoint();
                    local key=tonumber(id)
                    if key and key>0 then
                        local counts=recent[key] or {sold=0,expired=0}; recent[key]=counts
                        counts.sold=counts.sold+(r.sold or 0); counts.expired=counts.expired+(r.expired or 0)
                    end
                end
            end end
        end end
    end
    Store.IterDays(scanFrom,to,function(day,rows) for _,r in ipairs(rows) do checkpoint();
                if selectedChar(r.char,f) and (not f.econ or (r.econ or Store.DeriveEcon(r.char))==f.econ) and selectedSource(r,f) then
                    local id=tonumber(r.itemID); if id and id>0 then
                        local d=details[id] or {sold=0,gross=0,fee=0,cogs=0,depLost=0,bought=0,spent=0,sold180=0,expired180=0,buys={},buyers={},sellers={},variants={},lastSoldTs=0,lastBuyTs=0}; details[id]=d
                        local typ=r.type; local qty=tonumber(r.qty) or 0
                        local sale=typ=="AH_SELL" or typ=="VENDOR_SELL" or typ=="COD_SELL" or typ=="TRADE_SELL"
                        if sale and day>=prev7 and day<=today then
                            local key=day>=last7 and "soldLast7" or "soldPrev7"
                            d[key]=(d[key] or 0)+qty
                            if typ=="AH_SELL" then
                                local ahKey=day>=last7 and "ahSoldLast7" or "ahSoldPrev7"
                                d[ahKey]=(d[ahKey] or 0)+qty
                            end
                        end
                        local extra=r.extra or {}; local variant=tostring(extra.variant or extra.itemString or "base")
                        local level=tonumber(extra.itemLevel)
                        if not level and type(extra.itemString)=="string" and extra.itemString:find("item:",1,true) and _G.GetDetailedItemLevelInfo then
                            local ok,lvl=pcall(_G.GetDetailedItemLevelInfo,extra.itemString)
                            if ok then level=tonumber(lvl) end
                        end
                        if not level and _G.GetItemInfo then
                            local ok,_,_,_,itemLevel=pcall(_G.GetItemInfo,id)
                            if ok then level=tonumber(itemLevel) end
                        end
                        if f.groupBy=="level" then variant="level:"..tostring(level or 0) end
                        local v=d.variants[variant] or {sold=0,gross=0,fee=0,cogs=0,depLost=0,bought=0,spent=0}; d.variants[variant]=v
                        if day>=from and day<=to then
                            if typ=="AH_SELL" then d.ahSold=(d.ahSold or 0)+qty
                            elseif typ=="AH_EXPIRE" then d.expiredPeriod=(d.expiredPeriod or 0)+qty
                            elseif typ=="AH_CANCEL" then d.cancelledPeriod=(d.cancelledPeriod or 0)+qty
                            elseif typ=="AH_POST" then d.postedPeriod=(d.postedPeriod or 0)+qty end
                            if typ=="AH_SELL" or typ=="VENDOR_SELL" or typ=="COD_SELL" or typ=="TRADE_SELL" then
                                local gross=tonumber(r.extra and r.extra.gross) or (tonumber(r.total) or 0)+(tonumber(r.extra and r.extra.fee) or 0)
                                d.sold=d.sold+qty; d.gross=d.gross+gross; d.fee=d.fee+(tonumber(r.extra and r.extra.fee) or 0)
                                d.cogs=d.cogs+(tonumber(r.cogs) or 0); d.depLost=d.depLost+(tonumber(r.depLost) or 0)
                                v.sold=v.sold+qty; v.gross=v.gross+gross; v.fee=v.fee+(tonumber(r.extra and r.extra.fee) or 0); v.cogs=v.cogs+(tonumber(r.cogs) or 0); v.depLost=v.depLost+(tonumber(r.depLost) or 0)
                                local unit=qty>0 and gross/qty or (tonumber(r.unit) or 0); d.minSell=min(d.minSell or unit,unit); d.maxSell=max(d.maxSell or unit,unit)
                                if r.time>=d.lastSoldTs then d.lastSoldTs=r.time; d.lastSoldUnit=qty>0 and gross/qty or r.unit; d.lastSoldTo=r.extra and (r.extra.buyer or r.extra.counterparty) end
                                if r.time>=(d.lastSoldTs or 0) then d.expSinceSale=0; d.canSinceSale=0 end
                                local buyer=r.extra and (r.extra.buyer or r.extra.counterparty); if buyer then local b=d.buyers[buyer] or {name=buyer,qty=0,total=0}; d.buyers[buyer]=b; b.qty=b.qty+qty; b.total=b.total+gross end
                            elseif typ=="AH_BUY" or typ=="VENDOR_BUY" or typ=="COD_BUY" or typ=="TRADE_BUY" or typ=="VENDOR_BUYBACK" then
                                local spent=abs(tonumber(r.total) or 0); d.bought=d.bought+qty; d.spent=d.spent+spent; d.cogs=d.cogs+(tonumber(r.cogs) or 0)
                                v.bought=v.bought+qty; v.spent=v.spent+spent
                                local unit=qty>0 and spent/qty or (tonumber(r.unit) or 0); d.minBuy=min(d.minBuy or unit,unit); d.maxBuy=max(d.maxBuy or unit,unit)
                                d.buys[#d.buys+1]={time=r.time,replayOrder=tonumber(extra.replayOrder or r.replayOrder),sequence=#d.buys+1,qty=qty,total=spent,unit=qty>0 and spent/qty or r.unit,from=r.extra and (r.extra.seller or r.extra.counterparty)}
                                local seller=r.extra and (r.extra.seller or r.extra.counterparty); if seller then local b=d.sellers[seller] or {name=seller,qty=0,total=0}; d.sellers[seller]=b; b.qty=b.qty+qty; b.total=b.total+spent end
                                if r.time>=d.lastBuyTs then d.lastBuyTs=r.time; d.lastBuyUnit=qty>0 and spent/qty or r.unit; d.lastBuyFrom=r.extra and (r.extra.seller or r.extra.counterparty) end
                            elseif typ=="AH_POST" or typ=="AH_CANCEL" or typ=="AH_EXPIRE" then
                                local depLost=tonumber(r.depLost) or tonumber(extra.depLost) or 0
                                d.depLost=d.depLost+depLost; v.depLost=v.depLost+depLost
                            elseif typ=="DISENCHANT_BROKEN" then
                                local estVal=tonumber(extra.estValue) or 0
                                if estVal>0 then
                                    d.sold=d.sold+qty; d.gross=d.gross+estVal; d.cogs=d.cogs+(tonumber(r.cogs) or 0)
                                    v.sold=v.sold+qty; v.gross=v.gross+estVal; v.cogs=v.cogs+(tonumber(r.cogs) or 0)
                                end
                            end
                        elseif typ=="AH_BUY" or typ=="VENDOR_BUY" or typ=="COD_BUY" or typ=="TRADE_BUY" or typ=="VENDOR_BUYBACK" then
                            local spent=abs(tonumber(r.total) or 0)
                            d.buys[#d.buys+1]={time=r.time,replayOrder=tonumber(extra.replayOrder or r.replayOrder),sequence=#d.buys+1,qty=qty,total=spent,unit=qty>0 and spent/qty or r.unit,from=extra.seller or extra.counterparty}
                        end
                        if day>=d180 then
                            if day>=d180 then
                                if typ=="AH_SELL" then d.sold180=d.sold180+qty elseif typ=="AH_EXPIRE" then d.expired180=d.expired180+qty end
                            end
                            if (typ=="AH_EXPIRE" or typ=="AH_CANCEL") and (r.time or 0)>=(d.lastSoldTs or 0) then
                                if typ=="AH_EXPIRE" then d.expSinceSale=(d.expSinceSale or 0)+qty else d.canSinceSale=(d.canSinceSale or 0)+qty end
                            end
                        end
                    end
                end
            end end)
    local byID={}; for _,r in ipairs(old.rows or {}) do byID[tonumber(r.itemID)]=r end
    for id,r in pairs(byID) do checkpoint();
        local d=details[id] or {}; local meta=rowMeta(id,f)
        if sourceFiltered then
            r.sold=d.sold or 0; r.gross=d.gross or 0; r.fee=d.fee or 0; r.cogs=d.cogs or 0; r.depLost=d.depLost or 0; r.bought=d.bought or 0; r.spent=d.spent or 0
            r.profit=r.gross-r.fee-r.cogs-r.depLost
            r.ahSold=d.ahSold or 0; r.expired=d.expiredPeriod or 0; r.cancelled=d.cancelledPeriod or 0; r.posted=d.postedPeriod or 0
            r.soldLast7=d.soldLast7 or 0; r.soldPrev7=d.soldPrev7 or 0
            r.velocity=r.soldLast7/7; r.prevVelocity=r.soldPrev7/7
            r.slowRatio=r.soldPrev7>0 and r.soldLast7/r.soldPrev7 or nil
            r.isSlowing=r.soldPrev7>=3 and r.slowRatio~=nil and r.slowRatio<0.6 or false
            r.ahSoldLast7=d.ahSoldLast7 or 0; r.ahSoldPrev7=d.ahSoldPrev7 or 0
            r.ahVelocity=r.ahSoldLast7/7; r.ahPrevVelocity=r.ahSoldPrev7/7
            r.ahSlowRatio=r.ahSoldPrev7>0 and r.ahSoldLast7/r.ahSoldPrev7 or nil
            r.ahIsSlowing=r.ahSoldPrev7>=3 and r.ahSlowRatio~=nil and r.ahSlowRatio<0.6 or false
            r.ahSellThrough=r.ahSold+r.expired>=3 and r.ahSold/(r.ahSold+r.expired) or nil
            r.cancelChurn=r.posted>=1 and r.cancelled/r.posted or nil
            if ahOnly then r.sellThrough=r.ahSellThrough end
        end
        r.avgBuy=r.bought>0 and r.spent/r.bought or nil
        r.avgSell=r.sold>0 and r.gross/r.sold or nil
        r.netAvgSell=r.sold>0 and (r.gross-r.fee)/r.sold or nil
        if f.char and f.char~="all" then r.curBasisQty,r.curBasis=Store.Basis(Store.DeriveEcon(f.char),id)
        elseif f.econ then r.curBasisQty,r.curBasis=Store.Basis(f.econ,id)
        elseif f.chars then
            local seenEcon={}; local basisQty,basisCost=0,0
            for char,selected in pairs(f.chars) do if selected then local econ=Store.DeriveEcon(char); if not seenEcon[econ] then seenEcon[econ]=true; local qty,unit=Store.Basis(econ,id); basisQty=basisQty+qty; basisCost=basisCost+qty*unit end end end
            r.curBasisQty=basisQty; r.curBasis=basisQty>0 and basisCost/basisQty or 0
        else local _,activeEcon=Store.CurrentCharAndEcon(); r.curBasisQty,r.curBasis=Store.Basis(activeEcon or Store.DeriveEcon(""),id) end
        r.smartAvgBuy=nil
        local needed=r.curBasisQty or 0
        if ns.Inventory and ns.Inventory.GetItemBreakdown then
            local economy=f.econ or (f.char and f.char~="all" and Store.DeriveEcon(f.char))
            local breakdown=ns.Inventory.GetItemBreakdown(id,economy)
            if breakdown then
                local inventoryQty,hasSnapshot=0,false
                for _,entry in ipairs(breakdown.byChar or {}) do if selectedChar(entry.char,f) then
                    if db().inventory and db().inventory[entry.char] then hasSnapshot=true end
                    inventoryQty=inventoryQty+(entry.bags or 0)+(entry.bank or 0)+(entry.mail or 0)+(entry.inTransit or 0)+(entry.ah or 0)+(entry.gear or 0)
                end end
                if hasSnapshot then needed=inventoryQty end
            end
        end
        local paid,covered=0,0; sortRows(d.buys or {},function(a,b)
            if a.time~=b.time then return a.time>b.time end
            local ao,bo=a.replayOrder or 0,b.replayOrder or 0
            if ao~=bo then return ao>bo end
            return (a.sequence or 0)>(b.sequence or 0)
        end)
        for _,b in ipairs(d.buys or {}) do local take=min(max(0,needed-covered),b.qty); if take>0 then paid=paid+take*b.unit; covered=covered+take end; if covered>=needed then break end end
        if covered>0 then r.smartAvgBuy=paid/covered end
        local lifetime=f.period=="all" or (not f.period and from=="0000-00-00")
        r.minBuy=d.minBuy or (lifetime and meta.minBuy); r.maxBuy=d.maxBuy or (lifetime and meta.maxBuy); r.minSell=d.minSell or (lifetime and meta.minSell); r.maxSell=d.maxSell or (lifetime and meta.maxSell)
        r.avgProfit=r.sold>0 and r.profit/r.sold or nil; r.profitPct=r.cogs>0 and r.profit/r.cogs or nil
        local counts=sourceFiltered and {sold=d.sold180 or 0,expired=d.expired180 or 0} or (recent[id] or {sold=0,expired=0})
        r.saleRate=counts.sold+counts.expired>0 and counts.sold/(counts.sold+counts.expired) or nil
        r.expSinceSale=d.expSinceSale or meta.expSinceSale or 0; r.canSinceSale=d.canSinceSale or meta.canSinceSale or 0
        r.lastSoldTs=(d.lastSoldTs or 0)>0 and d.lastSoldTs or meta.lastSoldTs; r.lastSoldUnit=d.lastSoldUnit or meta.lastSoldUnit; r.lastSoldTo=d.lastSoldTo or meta.lastSoldTo
        r.lastBuyTs=(d.lastBuyTs or 0)>0 and d.lastBuyTs or meta.lastBuyTs; r.lastBuyUnit=d.lastBuyUnit or meta.lastBuyUnit; r.lastBuyFrom=d.lastBuyFrom or meta.lastBuyFrom
        if f.minRarity then
            local quality=_G.C_Item and _G.C_Item.GetItemQualityByID and _G.C_Item.GetItemQualityByID(id)
            if not quality and _G.GetItemInfo then local _,_,q=_G.GetItemInfo(id); quality=q end
            if (tonumber(quality) or -1)<tonumber(f.minRarity) then r._excluded=true end
        end
        if f.rarities and not f.rarities[tonumber((_G.C_Item and _G.C_Item.GetItemQualityByID and _G.C_Item.GetItemQualityByID(id)) or 0)] then r._excluded=true end
        if f.groupBy=="level" then r.groupKey=tostring(id)..":"..tostring(meta.itemLevel or 0)
        elseif f.groupBy=="specific" then r.groupKey=meta.variant or tostring(id)
        else r.groupKey=tostring(id) end
        if (f.source and f.source~="all" or f.sources) and not details[id] then r._excluded=true end
        local prof=tostring(f.prof or f.group or "")
        if prof~="" and prof~="all" then
            if not professionMatches(id,strlower(prof)) then r._excluded=true end
        end
        if needle~="" then
            local found=contains(r.name,needle)
            if not found then for name in pairs(d.buyers or {}) do if contains(name,needle) then found=true; break end end end
            if not found then for name in pairs(d.sellers or {}) do if contains(name,needle) then found=true; break end end end
            if not found then r._excluded=true end
        end
        if (f.groupBy=="specific" or f.groupBy=="level") and next(d.variants or {}) then
            local split={}
            for variant,v in pairs(d.variants) do
                local copy={}; for k,value in pairs(r) do copy[k]=value end
                if f.groupBy=="specific" then copy.variant=variant; copy.groupKey=variant else copy.itemLevel=tonumber(variant:match("^level:(%d+)")); copy.groupKey=tostring(id)..":"..tostring(copy.itemLevel or 0) end
                copy.sold=v.sold; copy.gross=v.gross; copy.fee=v.fee; copy.cogs=v.cogs; copy.depLost=v.depLost; copy.bought=v.bought; copy.spent=v.spent
                copy.profit=v.gross-v.fee-v.cogs-v.depLost; copy.avgBuy=v.bought>0 and v.spent/v.bought or nil; copy.avgSell=v.sold>0 and v.gross/v.sold or nil
                copy.avgProfit=v.sold>0 and copy.profit/v.sold or nil; copy.profitPct=v.cogs>0 and copy.profit/v.cogs or nil
                split[#split+1]=copy
            end
            for _,copy in ipairs(split) do if not r._excluded then out[#out+1]=copy; totals.qtySold=totals.qtySold+copy.sold; totals.qtyBought=totals.qtyBought+copy.bought; for _,k in ipairs({"gross","spent","fee","cogs","depLost","profit"}) do totals[k]=totals[k]+(copy[k] or 0) end end end
        elseif not r._excluded then
            out[#out+1]=r; totals.qtySold=totals.qtySold+r.sold; totals.qtyBought=totals.qtyBought+r.bought
            for _,k in ipairs({"gross","spent","fee","cogs","depLost","profit"}) do totals[k]=totals[k]+(r[k] or 0) end
        end
    end
    old.rows=out; old.totals=totals; return old
end
itemRows=richItemRows
local WEALTH_CAT_META={
    {key="gold",title="Liquid Gold"},
    {key="bags",title="Bags"},
    {key="bank",title="Bank"},
    {key="mail",title="Mail"},
    {key="gear",title="Equipped Gear"},
    {key="listed",title="Listed on AH"},
}
local function appendLiveListed(char,cats)
    cats.listed={}
    for itemID,lots in pairs(Store.Lots(char)) do
        local qtySum,valSum=0,0
        for _,lot in ipairs(lots) do local q,u=lot.qty or 0,lot.unit or 0; qtySum=qtySum+q; valSum=valSum+q*u end
        if qtySum>0 then
            cats.listed[#cats.listed+1]={id=itemID,name=Model.ItemName(itemID),qty=qtySum,unit=floor(valSum/qtySum+0.5),total=valSum,basis="AH Listing"}
        end
    end
    tsort(cats.listed,function(a,b) if a.total~=b.total then return a.total>b.total end; return tostring(a.name or "")<tostring(b.name or "") end)
end
local function dedupeWealthList(list,catKey)
    if type(list)~="table" or #list<=1 then return list or {} end
    local out,byKey={},{}
    local hostDB=_G.MerchantMasterDB
    local itemIDs=(catKey=="gear" and type(hostDB)=="table" and type(hostDB.itemIDs)=="table") and hostDB.itemIDs or nil
    for _,it in ipairs(list) do
        if type(it)=="table" then
            local numID=tonumber(it.id)
            if (not numID or numID<=0) and itemIDs and type(it.name)=="string" then
                numID=tonumber(itemIDs[it.name])
            end
            local base=(numID and numID>0 and ("i:"..tostring(numID)) or ("n:"..tostring(it.name or "")))
            local key=(catKey=="gear") and base or (base.."|"..(it.bound and "B" or "T"))
            local existing=byKey[key]
            if existing then
                if (not existing.id or tonumber(existing.id)<=0) and numID and numID>0 then existing.id=numID end
                existing.qty=(existing.qty or 0)+(tonumber(it.qty) or 0)
                existing.total=(existing.total or 0)+(tonumber(it.total) or 0)
                if existing.qty>0 then existing.unit=floor(existing.total/existing.qty+0.5) end
            else
                local copy={}; for k,v in pairs(it) do copy[k]=v end
                if (not copy.id or tonumber(copy.id)<=0) and numID and numID>0 then copy.id=numID end
                if catKey=="gear" then copy.bound=nil end
                byKey[key]=copy; out[#out+1]=copy
            end
        end
    end
    return out
end
local function buildCharWealthDetail(char,snap)
    local wTbl=db().wealth
    local stored=wTbl and wTbl[char]
    if type(stored)=="table" and type(stored.cats)=="table" then
        local liveCats={
            bags=dedupeWealthList(stored.cats.bags,"bags"),
            bank=dedupeWealthList(stored.cats.bank,"bank"),
            mail=dedupeWealthList(stored.cats.mail,"mail"),
            gear=dedupeWealthList(stored.cats.gear,"gear"),
        }
        appendLiveListed(char,liveCats)
        return {at=stored.at,econ=stored.econ,cats=liveCats}
    end
    local h=H(); local hostDB=_G.MerchantMasterDB or {}
    local charTbl=hostDB.chars and hostDB.chars[char]
    local cats={bags={},bank={},mail={},gear={},listed={}}
    local charEcon=Store.DeriveEcon(char,snap and snap.econ)
    if type(charTbl)=="table" and ns.Capture and ns.Capture.CollectCharEntries and ns.Capture.ValueWealthItem then
        local active=(h and h.DetectActiveEconomy and h.DetectActiveEconomy()) or charEcon
        local runFn=function()
            for _,entry in ipairs(ns.Capture.CollectCharEntries(h,hostDB,charTbl)) do
                local unit,basis=ns.Capture.ValueWealthItem(h,hostDB,charEcon,active,entry.id,entry.bound,entry.cat)
                local total=floor(entry.qty*unit+0.5)
                local list=cats[entry.cat]
                if list then list[#list+1]={id=entry.id,name=entry.name,qty=entry.qty,unit=floor(unit+0.5),total=total,basis=basis,bound=entry.bound or nil} end
            end
        end
        local ok=ns.Capture.WithCharEconomy and ns.Capture.WithCharEconomy(h,hostDB,charEcon,runFn) or pcall(runFn)
        if not ok then cats={bags={},bank={},mail={},gear={},listed={}} end
    end
    for _,list in pairs(cats) do
        tsort(list,function(a,b) if a.total~=b.total then return a.total>b.total end; return tostring(a.name or "")<tostring(b.name or "") end)
    end
    appendLiveListed(char,cats)
    return {econ=charEcon,cats=cats,synthetic=true}
end
local function resolveCanonicalPortfolioChars(charSet,f)
    local root=db(); local snapsTbl=root.snaps or {}; local wealthTbl=root.wealth or {}
    local hostChars=_G.MerchantMasterDB and _G.MerchantMasterDB.chars or {}
    local h=H(); local activeKey=h and h.app and h.app.charKey
    local explicitPlaceholder=(f and f.char=="Normal-Horde-Forever-Player") or (f and f.chars and f.chars["Normal-Horde-Forever-Player"]==true)
    local hasRealNH=false
    for c in pairs(charSet) do
        if c~="Normal-Horde-Forever-Player" and Store.DeriveEcon(c)=="Normal-Horde" then hasRealNH=true; break end
    end
    local groups,groupMeta,twoWordByFirst={},{},{}
    local function resolveShort(c)
        local hc=hostChars[c]
        return (type(hc)=="table" and type(hc.name)=="string" and hc.name~="" and hc.name) or c:match("%-([^%-]+)$") or c
    end
    for _,c in ipairs(sortedKeys(charSet)) do
        if c=="Normal-Horde-Forever-Player" and hasRealNH and not explicitPlaceholder then
            -- Skip ghost placeholder alongside real Normal-Horde characters.
        else
            local short=resolveShort(c)
            local econ=Store.DeriveEcon(c)
            local econLow,shortLow=strlower(econ),strlower(short)
            local gk=econLow.."|"..shortLow
            if not groups[gk] then
                groups[gk]={}
                local firstW,restW=shortLow:match("^([^%s]+)%s+(.+)$")
                local isTwo=(firstW~=nil and restW~=nil and restW~="")
                groupMeta[gk]={econLow=econLow,shortLow=shortLow,firstLow=isTwo and firstW or shortLow,isTwoWord=isTwo}
                if isTwo then
                    local fk=econLow.."|"..firstW
                    twoWordByFirst[fk]=twoWordByFirst[fk] or {}; twoWordByFirst[fk][#twoWordByFirst[fk]+1]=gk
                end
            end
            groups[gk][#groups[gk]+1]=c
        end
    end
    -- Fold unambiguous single-word Forever legacy keys (<First>) into matching two-word (<First> <Last>) group in same economy.
    for gk,meta in pairs(groupMeta) do
        if not meta.isTwoWord and groups[gk] then
            local cands=twoWordByFirst[meta.econLow.."|"..meta.shortLow]
            if cands and #cands==1 and groups[cands[1]] then
                local dstList=groups[cands[1]]
                local conflict=false
                local dstGuid
                for _,dc in ipairs(dstList) do
                    local dh=hostChars[dc]
                    if type(dh)=="table" and dh.guid then dstGuid=dh.guid; break end
                end
                if dstGuid then
                    for _,sc in ipairs(groups[gk]) do
                        local sh=hostChars[sc]
                        if type(sh)=="table" and sh.guid and sh.guid~=dstGuid then conflict=true; break end
                    end
                end
                if not conflict then
                    for _,sc in ipairs(groups[gk]) do dstList[#dstList+1]=sc end
                    groups[gk]=nil
                end
            end
        end
    end
    local function rankChar(c)
        local isActive=(activeKey and c==activeKey) and 1 or 0
        local short=resolveShort(c)
        local hasSpace=(type(short)=="string" and short:find("%s")~=nil) and 1 or 0
        local inHost=(type(hostChars[c])=="table") and 1 or 0
        local w=wealthTbl[c]
        local wAt=(type(w)=="table" and tonumber(w.at)) or 0
        local maxDay=""
        for d in pairs(snapsTbl[c] or {}) do if type(d)=="string" and d>maxDay then maxDay=d end end
        return isActive,hasSpace,inHost,wAt,maxDay
    end
    local function betterChar(a,b)
        local a1,a2,a3,a4,a5=rankChar(a); local b1,b2,b3,b4,b5=rankChar(b)
        if a1~=b1 then return a1>b1 end
        if a2~=b2 then return a2>b2 end
        if a3~=b3 then return a3>b3 end
        if a4~=b4 then return a4>b4 end
        if a5~=b5 then return a5>b5 end
        return a<b
    end
    local chars,charSnaps={},{}
    for _,list in pairs(groups) do
        tsort(list,betterChar)
        local canon=list[1]; chars[#chars+1]=canon
        local merged={}
        for _,srcChar in ipairs(list) do
            for day,snap in pairs(snapsTbl[srcChar] or {}) do
                if merged[day]==nil then merged[day]=snap end
            end
        end
        charSnaps[canon]=merged
    end
    tsort(chars)
    return chars,charSnaps
end
local function portfolio(f,from,to,seriesOnly)
    local days,rawCharSet={},{}
    for char,snaps in pairs(db().snaps or {}) do if charMatches(char,f) then rawCharSet[char]=true end end
    for char,byItem in pairs(db().lots or {}) do
        if charMatches(char,f) and next(byItem)~=nil then rawCharSet[char]=true end
    end
    local chars,charSnaps=resolveCanonicalPortfolioChars(rawCharSet,f)
    for _,canon in ipairs(chars) do
        for day in pairs(charSnaps[canon] or {}) do if day<=to then days[day]=true end end
        if db().lots and db().lots[canon] and next(db().lots[canon])~=nil then days[Store.DayKey()]=true end
    end
    local last,series,lastDay={},{},{}; local baseline
    for _,day in ipairs(sortedKeys(days)) do
        local row={day=day,label=day,gold=0,items=0,listed=0,total=0}
        for _,char in ipairs(chars) do
            local snap=charSnaps[char] and charSnaps[char][day]; if snap then last[char]=snap; lastDay[char]=day end
            snap=last[char]
            if snap then row.gold=row.gold+(snap.gold or 0); row.items=row.items+(snap.items or 0); row.listed=row.listed+(snap.listed or 0) end
        end
        row.total=row.gold+row.items+row.listed
        if day>=from then
            if baseline and #series==0 and day>from then baseline.day=from; baseline.label=from; series[#series+1]=baseline end
            series[#series+1]=row
        else baseline=row end
    end
    if #series==0 and baseline then baseline.day=from; baseline.label=from; series[1]=baseline end
    if seriesOnly then
        local headTotal,first=0,series[1] or {}
        for _,char in ipairs(chars) do
            local s=last[char] or (db().lots and db().lots[char] and next(db().lots[char])~=nil and {gold=0,items=0,listed=0,econ=Store.DeriveEcon(char)})
            if s then
                local lVal=s.listed or 0
                if db().lots and db().lots[char]~=nil then
                    lVal=0
                    for _,lots in pairs(Store.Lots(char)) do
                        for _,lot in ipairs(lots) do lVal=lVal+floor((tonumber(lot.qty) or 0)*(tonumber(lot.unit) or 0)+0.5) end
                    end
                end
                headTotal=headTotal+(s.gold or 0)+(s.items or 0)+lVal
            end
        end
        if #series>0 then series[#series].total=headTotal end
        return {series=series,latestTotal=headTotal,firstTotal=first.total or 0}
    end
    local needle=strlower(f.search or "")
    local catMap,categories={},{}
    for order,meta in ipairs(WEALTH_CAT_META) do
        local cat={catKey=meta.key,title=meta.title,order=order,total=0,itemCount=0,unitCount=0,items={}}
        catMap[meta.key]=cat; categories[#categories+1]=cat
    end
    local byChar={}
    local latestBags,latestBank,latestMail,latestGear=0,0,0,0
    local reconciledSynthetic=false
    for _,char in ipairs(chars) do
        local s=last[char] or (db().lots and db().lots[char] and next(db().lots[char])~=nil and {gold=0,items=0,listed=0,econ=Store.DeriveEcon(char)})
        if s then
            local cShort=Model.CharShort(char)
            local detail=buildCharWealthDetail(char,s)
            local cats=detail and detail.cats or {}
            local cGold=s.gold or 0
            if cGold>0 or #chars==1 then
                if needle=="" or contains(cShort,needle) or contains("liquid gold",needle) or contains("character cash",needle) then
                    local gCat=catMap.gold
                    gCat.total=gCat.total+cGold; gCat.itemCount=gCat.itemCount+1; gCat.unitCount=gCat.unitCount+1
                    gCat.items[#gCat.items+1]={char=char,charShort=cShort,owner=cShort,name=cShort,label=cShort,basis="Character Cash",qty=nil,unit=nil,total=cGold,isGoldRow=true}
                end
            end
            local charItemSum={bags=0,bank=0,mail=0,gear=0,listed=0}
            for _,catKey in ipairs({"bags","bank","mail","gear","listed"}) do
                local cat=catMap[catKey]
                for _,it in ipairs(cats[catKey] or {}) do
                    local nm=it.name or (it.id and Model.ItemName(it.id)) or "-"
                    charItemSum[catKey]=charItemSum[catKey]+(it.total or 0)
                    if needle=="" or contains(nm,needle) or contains(cShort,needle) or contains(it.basis,needle) or contains(cat.title,needle) then
                        cat.total=cat.total+(it.total or 0)
                        cat.itemCount=cat.itemCount+1
                        cat.unitCount=cat.unitCount+(it.qty or 0)
                        cat.items[#cat.items+1]={
                            char=char,charShort=cShort,owner=cShort,
                            itemID=it.id,icon=it.id and Model.ItemIcon(it.id) or nil,
                            name=nm,label=nm,basis=it.basis or "-",
                            qty=it.qty or 0,unit=it.unit or 0,total=it.total or 0,
                            bound=it.bound or nil,catKey=catKey,
                        }
                    end
                end
            end
            local cBags=s.bags~=nil and s.bags or charItemSum.bags
            local cBank=s.bank~=nil and s.bank or charItemSum.bank
            local cMail=s.mail~=nil and s.mail or charItemSum.mail
            local cGear=s.gear~=nil and s.gear or charItemSum.gear
            latestBags=latestBags+cBags; latestBank=latestBank+cBank; latestMail=latestMail+cMail; latestGear=latestGear+cGear
            local accountedInv=charItemSum.bags+charItemSum.bank+charItemSum.mail+charItemSum.gear
            local invItems=s.items or 0
            if detail and detail.synthetic and accountedInv>0 and accountedInv~=invItems then
                invItems=accountedInv; reconciledSynthetic=true
            end
            if accountedInv==0 and invItems>0 and needle=="" then
                local bCat=catMap.bags
                bCat.total=bCat.total+invItems; bCat.itemCount=bCat.itemCount+1
                bCat.items[#bCat.items+1]={char=char,charShort=cShort,owner=cShort,name="Legacy Snapshot Inventory ("..cShort..")",label="Legacy Snapshot Inventory ("..cShort..")",basis="Snapshot Aggregate",qty=nil,unit=nil,total=invItems}
            end
            local cListed=s.listed or 0
            local hasLotTable=db().lots and db().lots[char]~=nil
            if (hasLotTable or (detail and detail.synthetic and charItemSum.listed>0)) and charItemSum.listed~=cListed then
                cListed=charItemSum.listed; reconciledSynthetic=true
            end
            if charItemSum.listed==0 and cListed>0 and needle=="" then
                local lCat=catMap.listed
                lCat.total=lCat.total+cListed; lCat.itemCount=lCat.itemCount+1
                lCat.items[#lCat.items+1]={char=char,charShort=cShort,owner=cShort,name="Open AH Lots ("..cShort..")",label="Open AH Lots ("..cShort..")",basis="Snapshot Aggregate",qty=nil,unit=nil,total=cListed}
            end
            byChar[#byChar+1]={
                char=char,charShort=cShort,name=char,gold=cGold,items=invItems,
                bags=cBags,bank=cBank,mail=cMail,gear=cGear,
                listed=cListed,total=cGold+invItems+cListed,econ=s.econ,goldOnly=s.goldOnly,lastDay=lastDay[char],
            }
        end
    end
    for _,cat in ipairs(categories) do
        tsort(cat.items,function(a,b)
            if (a.total or 0)~=(b.total or 0) then return (a.total or 0)>(b.total or 0) end
            return tostring(a.name or "")<tostring(b.name or "")
        end)
    end
    local latest=series[#series] or {}; local first=series[1] or {}
    local headGold,headItems,headListed=latest.gold or 0,latest.items or 0,latest.listed or 0
    if reconciledSynthetic and #byChar>0 then
        headGold,headItems,headListed=0,0,0
        for _,bc in ipairs(byChar) do
            headGold=headGold+(bc.gold or 0); headItems=headItems+(bc.items or 0); headListed=headListed+(bc.listed or 0)
        end
        latest.gold=headGold; latest.items=headItems; latest.listed=headListed; latest.total=headGold+headItems+headListed
    end
    return {
        series=series,byChar=byChar,categories=categories,
        latestTotal=headGold+headItems+headListed,latestGold=headGold,latestItems=headItems,latestListed=headListed,
        latestBags=latestBags,latestBank=latestBank,latestMail=latestMail,latestGear=latestGear,
        firstTotal=first.total or 0,
    }
end
local OVERVIEW_DENSE_MAX=32768
local overviewProfit={}
local overviewEst={}
local overviewIDs={}
for i=1,OVERVIEW_DENSE_MAX do overviewProfit[i]=false end
local function overview(f,from,to)
    local d=db()
    local dayStatsTbl,rollTbl,lootTbl,snapsTbl=d.dayStats or {},d.roll or {},d.loot,d.snaps
    local k={profit=0,sales=0,purchases=0,depLost=0,lootValue=0,wealthChange=0,unexplained=0}; local daily={}
    local sp,sest,sids,nUsed=overviewProfit,overviewEst,overviewIDs,0
    local sparseProfit,sparseEst={},{}
    local minRollDay
    local allChars=(not f.char or f.char=="all")
    local unrestricted=allChars and not f.chars and (not f.faction or f.faction=="all") and not f.econ
    local unrestrictedChars=unrestricted
    local trackEst=(f.knownCostOnly~=false)
    local activityByDay,activityStats,activityDaySet={},{},{}
    local activeCandidates,nTop={},0
    for day,chars in pairs(dayStatsTbl) do
        local selected=false
        if unrestrictedChars then
            for _,d in pairs(chars) do if type(d)=="table" and next(d) then selected=true; break end end
        else
            for char,d in pairs(chars) do if selectedChar(char,f) and type(d)=="table" and next(d) then selected=true; break end end
        end
        if selected and (nTop<7 or day>activeCandidates[nTop]) then
            local i=min(nTop+1,7)
            while i>1 and day>activeCandidates[i-1] do activeCandidates[i]=activeCandidates[i-1]; i=i-1 end
            activeCandidates[i]=day; nTop=min(nTop+1,7)
        end
    end
    for i=1,nTop do
        local day=activeCandidates[i]; activityDaySet[day]=true; activityByDay[day]={}; activityStats[day]={}
        for char,d in pairs(dayStatsTbl[day] or {}) do if unrestrictedChars or selectedChar(char,f) then
            activityByDay[day][char]={soldQty=0,salesNet=0,boughtQty=0,spent=0,expired=0,cancelled=0}
            activityStats[day][char]=d
        end end
    end
    -- Item KPIs stay complete even when estimated-cost rankings are hidden.
    for day,econs in pairs(rollTbl) do
        if not minRollDay or day<minRollDay then minRollDay=day end
        if activityDaySet[day] then
            local acts=activityByDay[day]
            for ck,items in pairs(econs) do local a=acts[ck]; if a and (unrestrictedChars or selectedChar(ck,f)) then
                for _,r in pairs(items) do
                    a.soldQty=a.soldQty+(r.sold or 0); a.salesNet=a.salesNet+(r.gross or 0)-(r.fee or 0)
                    a.boughtQty=a.boughtQty+(r.bought or 0); a.spent=a.spent+(r.spent or 0)
                    a.expired=a.expired+(r.expired or 0); a.cancelled=a.cancelled+(r.cancelled or 0)
                end
            end end
        end
        if day>=from and day<=to then
        local p,sales,buys,deposits=0,0,0,0
        local summary=dayStatsTbl[day]
        local noDepositLoss=false
        if summary then
            if unrestricted then
                for _,d in pairs(summary) do p=p+(d.profitDelta or 0); sales=sales+(d.salesGross or 0); buys=buys+(d.buySpent or 0); deposits=deposits+(d.depLost or 0) end
            else
                for char,d in pairs(summary) do if selectedChar(char,f) then p=p+(d.profitDelta or 0); sales=sales+(d.salesGross or 0); buys=buys+(d.buySpent or 0); deposits=deposits+(d.depLost or 0) end end
            end
            noDepositLoss=deposits==0
            if trackEst then
                for ck,items in pairs(econs) do if unrestricted or selectedChar(ck,f) then for id,r in pairs(items) do
                    local dp=sp[id]
                    local v=(r.gross or 0)-(r.fee or 0)-(r.cogs or 0)-(r.depLost or 0)
                    if dp then
                        sp[id]=dp+v
                    elseif dp==false then
                        nUsed=nUsed+1; sids[nUsed]=id; sp[id]=v
                    else
                        sparseProfit[id]=(sparseProfit[id] or 0)+v
                    end
                    if (r.estUnits or 0)>0 then
                        if dp~=nil then sest[id]=true else sparseEst[id]=true end
                    end
                end end end
            else
                if unrestricted then
                    for _,items in pairs(econs) do
                        if noDepositLoss then
                            for id,r in pairs(items) do
                                local dp=sp[id]
                                local v=(r.gross or 0)-(r.fee or 0)-(r.cogs or 0)
                                if dp then
                                    sp[id]=dp+v
                                elseif dp==false then
                                    nUsed=nUsed+1; sids[nUsed]=id; sp[id]=v
                                else
                                    sparseProfit[id]=(sparseProfit[id] or 0)+v
                                end
                            end
                        else
                            for id,r in pairs(items) do
                                local dp=sp[id]
                                local v=(r.gross or 0)-(r.fee or 0)-(r.cogs or 0)-(r.depLost or 0)
                                if dp then
                                    sp[id]=dp+v
                                elseif dp==false then
                                    nUsed=nUsed+1; sids[nUsed]=id; sp[id]=v
                                else
                                    sparseProfit[id]=(sparseProfit[id] or 0)+v
                                end
                            end
                        end
                    end
                else
                    for ck,items in pairs(econs) do if selectedChar(ck,f) then
                        if noDepositLoss then for id,r in pairs(items) do
                            local dp=sp[id]
                            local v=(r.gross or 0)-(r.fee or 0)-(r.cogs or 0)
                            if dp then
                                sp[id]=dp+v
                            elseif dp==false then
                                nUsed=nUsed+1; sids[nUsed]=id; sp[id]=v
                            else
                                sparseProfit[id]=(sparseProfit[id] or 0)+v
                            end
                        end
                        else for id,r in pairs(items) do
                            local dp=sp[id]
                            local v=(r.gross or 0)-(r.fee or 0)-(r.cogs or 0)-(r.depLost or 0)
                            if dp then
                                sp[id]=dp+v
                            elseif dp==false then
                                nUsed=nUsed+1; sids[nUsed]=id; sp[id]=v
                            else
                                sparseProfit[id]=(sparseProfit[id] or 0)+v
                            end
                        end end
                    end end
                end
            end
        else
            for ck,items in pairs(econs) do if unrestricted or selectedChar(ck,f) then for id,r in pairs(items) do
                local gross,cogs,lost=r.gross or 0,r.cogs or 0,r.depLost or 0
                local v=gross-(r.fee or 0)-cogs-lost; p=p+v
                sales=sales+gross; buys=buys+(r.spent or 0); deposits=deposits+lost
                local dp=sp[id]
                if dp then
                    sp[id]=dp+v
                elseif dp==false then
                    nUsed=nUsed+1; sids[nUsed]=id; sp[id]=v
                else
                    sparseProfit[id]=(sparseProfit[id] or 0)+v
                end
                if (r.estUnits or 0)>0 then
                    if dp~=nil then sest[id]=true else sparseEst[id]=true end
                end
            end end end
        end
        daily[day]=p; k.profit=k.profit+p; k.sales=k.sales+sales; k.purchases=k.purchases+buys; k.depLost=k.depLost+deposits
    end end
    local prices={}
    for day,chars in pairs(lootTbl or {}) do if day>=from and day<=to then for char,counters in pairs(chars) do if charMatches(char,f) then for key,count in pairs(counters) do
        local id=tonumber(key:match("^(%d+)|")) or 0
        if id>0 then if prices[id]==nil then prices[id]=Model.MarketOrVendorPrice(id) end; k.lootValue=k.lootValue+count*prices[id] else k.lootValue=k.lootValue+count end
    end end end end end
    local p=portfolio(f,from,to,true); k.wealthChange=p.latestTotal-p.firstTotal
    local profitByDay={}; for _,day in ipairs(sortedKeys(daily)) do profitByDay[#profitByDay+1]={day=day,label=day,value=daily[day]} end
    local top,nTopItems={},0; local needle=strlower(f.search or "")
    local function considerItem(id,profit,isEst)
        if id==0 or (trackEst and isEst) then return end
        local nm
        if needle~="" then
            nm=Model.ItemName(id)
            if not contains(nm,needle) then return end
        end
        if nTopItems==5 and (profit<top[5].profit or (profit==top[5].profit and id>=top[5].itemID)) then return end
        local t={itemID=id,profit=profit,est=isEst or false,name=nm}
        local i=min(nTopItems+1,5)
        while i>1 and (profit>top[i-1].profit or (profit==top[i-1].profit and id<top[i-1].itemID)) do
            top[i]=top[i-1]; i=i-1
        end
        top[i]=t; nTopItems=min(nTopItems+1,5)
    end
    for i=1,nUsed do
        local id=sids[i]; local profit=sp[id]; local isEst=sest[id]
        sp[id]=false; sest[id]=nil
        considerItem(id,profit,isEst)
    end
    for id,profit in pairs(sparseProfit) do considerItem(id,profit,sparseEst[id]) end
    for i=1,nTopItems do
        local t=top[i]; t.name=t.name or Model.ItemName(t.itemID); t.icon=Model.ItemIcon(t.itemID)
        for _,field in ipairs(Store.ROLL_FIELDS) do t[field]=t[field] or 0 end
    end
    for _,t in ipairs(top) do
        local closed=t.sold+t.expired+t.cancelled; t.n=t.posted
        t.sellThrough=t.posted>=5 and closed>0 and t.sold/closed or nil; t.daysToSell=t.dtUnits>0 and t.dtSum/t.dtUnits/86400 or nil
        t.relists=t.relisted; t.reprices=t.repriced
    end
    local topSingleSale,topSingleBuy
    local saleItemTotals,buyItemTotals={},{}
    local topSaleItemID,topSaleItemTotal,topBuyItemID,topBuyItemTotal=nil,0,nil,0
    local totalSoldQty=0
    Store.IterDays(from,to,function(_,raw) for _,r in ipairs(raw) do if selectedChar(r.char,f) then
        local qty=max(1,tonumber(r.qty) or 1); local total=abs(tonumber(r.total) or 0); local gross=tonumber(r.extra and r.extra.gross) or (total+(tonumber(r.extra and r.extra.fee) or 0))
        local isSale=r.type=="AH_SELL" or r.type=="VENDOR_SELL" or r.type=="COD_SELL" or r.type=="TRADE_SELL"
        local isBuy=r.type=="AH_BUY" or r.type=="VENDOR_BUY" or r.type=="VENDOR_BUYBACK" or r.type=="COD_BUY" or r.type=="TRADE_BUY"
        local unit=isSale and gross/qty or (tonumber(r.unit) or total/qty)
        if isSale then
            totalSoldQty=totalSoldQty+qty
            if r.itemID and r.itemID>0 then
                local sum=(saleItemTotals[r.itemID] or 0)+gross; saleItemTotals[r.itemID]=sum
                if sum>topSaleItemTotal then topSaleItemTotal=sum; topSaleItemID=r.itemID end
            end
            if not topSingleSale or unit>(topSingleSale.unit or 0) or (unit==topSingleSale.unit and total>(topSingleSale.total or 0)) then topSingleSale={itemID=r.itemID,name=Model.ItemName(r.itemID),unit=unit,total=gross,time=r.time,buyer=r.extra and (r.extra.buyer or r.extra.counterparty)} end
        end
        if isBuy then
            if r.itemID and r.itemID>0 then
                local sum=(buyItemTotals[r.itemID] or 0)+total; buyItemTotals[r.itemID]=sum
                if sum>topBuyItemTotal then topBuyItemTotal=sum; topBuyItemID=r.itemID end
            end
            if not topSingleBuy or unit>(topSingleBuy.unit or 0) or (unit==topSingleBuy.unit and total>(topSingleBuy.total or 0)) then topSingleBuy={itemID=r.itemID,name=Model.ItemName(r.itemID),unit=unit,total=total,time=r.time,seller=r.extra and (r.extra.seller or r.extra.counterparty)} end
        end
    end end end)
    local topSaleItem=topSaleItemID and {itemID=topSaleItemID,name=Model.ItemName(topSaleItemID),icon=Model.ItemIcon(topSaleItemID),total=topSaleItemTotal} or nil
    local topBuyItem=topBuyItemID and {itemID=topBuyItemID,name=Model.ItemName(topBuyItemID),icon=Model.ItemIcon(topBuyItemID),total=topBuyItemTotal} or nil
    local timeFn=(os and os.time) or _G.time
    local toTs=timeFn({year=tonumber(to:sub(1,4)),month=tonumber(to:sub(6,7)),day=tonumber(to:sub(9,10))})
    local fromTs=timeFn({year=tonumber(from:sub(1,4)),month=tonumber(from:sub(6,7)),day=tonumber(from:sub(9,10))})
    if f.period=="all" then
        local firstDay=minRollDay or Store.DayKey()
        from=firstDay; fromTs=timeFn({year=tonumber(from:sub(1,4)),month=tonumber(from:sub(6,7)),day=tonumber(from:sub(9,10))})
        to=Store.DayKey(nowSec()); toTs=timeFn({year=tonumber(to:sub(1,4)),month=tonumber(to:sub(6,7)),day=tonumber(to:sub(9,10))})
    end
    local daysInPeriod=max(1,floor((toTs-fromTs)/86400)+1)
    local prevTo=Store.DayKey(fromTs-86400)
    local prevFrom=Store.DayKey((_G.time or os.time)({year=tonumber(prevTo:sub(1,4)),month=tonumber(prevTo:sub(6,7)),day=tonumber(prevTo:sub(9,10))})-(daysInPeriod-1)*86400)
    local prevProfit,prevSales,prevPurchases=0,0,0
    local function snapshotGoldDelta(char,day)
        local snaps=snapsTbl and snapsTbl[char]; local current=snaps and snaps[day]
        if not current or current.gold==nil then return nil end
        local y,m,d=day:match("^(%d+)%-(%d+)%-(%d+)$"); local tf=(os and os.time) or _G.time
        if not tf then return nil end
        local previousDay=Store.DayKey(tf({year=tonumber(y),month=tonumber(m),day=tonumber(d)})-86400)
        local previous=snaps[previousDay]
        if not previous or previous.gold==nil then return nil end
        return (tonumber(current.gold) or 0)-(tonumber(previous.gold) or 0)
    end
    for day,chars in pairs(dayStatsTbl) do
        if unrestrictedChars then
            if day>=from and day<=to then for char,d in pairs(chars) do k.unexplained=k.unexplained+(d.adjustTotal or 0) end end
            if day>=prevFrom and day<=prevTo then for _,d in pairs(chars) do prevProfit=prevProfit+(d.profitDelta or 0); prevSales=prevSales+(d.salesGross or 0); prevPurchases=prevPurchases+(d.buySpent or 0) end end
        else
            if day>=from and day<=to then for char,d in pairs(chars) do if selectedChar(char,f) then k.unexplained=k.unexplained+(d.adjustTotal or 0) end end end
            if day>=prevFrom and day<=prevTo then for char,d in pairs(chars) do if selectedChar(char,f) then prevProfit=prevProfit+(d.profitDelta or 0); prevSales=prevSales+(d.salesGross or 0); prevPurchases=prevPurchases+(d.buySpent or 0) end end end
        end
        local dayActivity=activityByDay[day]
        if dayActivity then for char,a in pairs(dayActivity) do local d=(activityStats[day] or {})[char] or chars[char]; a.netGold=d and tonumber(d.goldDelta) or snapshotGoldDelta(char,day) end end
    end
    k.daysInPeriod=daysInPeriod; k.avgDailyProfit=k.profit/daysInPeriod; k.avgDailySales=k.sales/daysInPeriod; k.avgDailyPurchases=k.purchases/daysInPeriod
    k.totalSoldQty=totalSoldQty; k.avgDailySalesQty=totalSoldQty/daysInPeriod
    k.prevProfit=prevProfit; k.prevSales=prevSales; k.prevPurchases=prevPurchases
    k.profitDeltaPct=prevProfit~=0 and (k.profit-prevProfit)/abs(prevProfit)*100 or nil
    k.salesDeltaPct=prevSales~=0 and (k.sales-prevSales)/abs(prevSales)*100 or nil
    k.purchasesDeltaPct=prevPurchases~=0 and (k.purchases-prevPurchases)/abs(prevPurchases)*100 or nil
    local high,low=nil,nil; local cutoff=Store.DayKey(nowSec()-364*86400); local wealth52=p.series or {}
    if #wealth52==0 or (wealth52[1].day and wealth52[1].day>cutoff) then wealth52=portfolio(f,cutoff,Store.DayKey(nowSec()),true).series or {} end
    for _,w in ipairs(wealth52) do if w.day>=cutoff then local v=w.total or 0; high=max(high or v,v); low=min(low or v,v) end end; k.high52w=high or 0; k.low52w=low or 0
    local nW=#wealth52
    k.dailyChange=nW>=2 and ((wealth52[nW].total or 0)-(wealth52[nW-1].total or 0)) or 0
    local acts={}; local activeDays=sortedKeys(activityByDay)
    for _,day in ipairs(activeDays) do for char,a in pairs(activityByDay[day]) do if selectedChar(char,f) then
        acts[#acts+1]={day=day,char=char,charShort=Model.CharShort(char),soldQty=a.soldQty or 0,salesNet=a.salesNet or 0,boughtQty=a.boughtQty or 0,spent=a.spent or 0,expired=a.expired or 0,cancelled=a.cancelled or 0,netGold=a.netGold}
    end end end
    tsort(acts,function(a,b) if a.day==b.day then return a.char<b.char end return a.day>b.day end); k.activityFeed=acts
    local intradayWealth={}; local intraday=(d.intradaySnaps or {})[Store.DayKey(nowSec())]
    if type(intraday)=="table" then
        local points=intraday.points or intraday
        if type(points)=="table" then for _,point in pairs(points) do if type(point)=="table" then
            local gold,items,listed=tonumber(point.gold),tonumber(point.items),tonumber(point.listed)
            if type(point.chars)=="table" then
                gold,items,listed=0,0,0
                for char,snap in pairs(point.chars) do if selectedChar(char,f) then gold=gold+(tonumber(snap.gold) or 0); items=items+(tonumber(snap.items) or 0); listed=listed+(tonumber(snap.listed) or 0) end end
            end
            if gold or items or listed then
                gold,items,listed=gold or 0,items or 0,listed or 0; local wealth=tonumber(point.total or point.wealth) or gold+items+listed
                intradayWealth[#intradayWealth+1]={time=tonumber(point.time or point.at) or 0,gold=gold,items=items,listed=listed,total=wealth,wealth=wealth}
            end
        end end end
        tsort(intradayWealth,function(a,b)return a.time<b.time end)
        while #intradayWealth>1440 do table.remove(intradayWealth,1) end
    end
    return {kpis=k,profitByDay=profitByDay,wealth=p.series,top=top,activityFeed=acts,topSingleSale=topSingleSale,topSingleBuy=topSingleBuy,
        topSaleItem=topSaleItem,topBuyItem=topBuyItem,intradayWealth=#intradayWealth>0 and intradayWealth or nil}
end
local function dayEnd(day)
    local y,m,d=day:match("^(%d+)%-(%d+)%-(%d+)$"); local tf=_G.time or (os and os.time)
    return tf and tf({year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=23,min=59,sec=59}) or 0
end
local function ledger(f,from,to)
    local rows={}; local totalMatched=0; local needle=strlower(f.search or ""); local keys={}
    for day in pairs(db().days or {}) do if day>=from and day<=to then keys[day]=true end end
    if not f.type or f.type=="all" or f.type=="loot" then for day in pairs(db().loot or {}) do if day>=from and day<=to then keys[day]=true end end end
    local days=sortedKeys(keys)
    local function matches(r)
        local typeOK=Store.MatchesTypeGroup(r.type,f.type) or ((f.type=="trade" or f.ledgerPreset=="trade") and r.type=="MONEY_TRANSFER" and r.where=="Trade")
        return charMatches(r.char,f) and typeOK and (not f.zone or f.zone=="all" or r.where==f.zone or r.zone==f.zone)
            and (needle=="" or contains(Model.ItemName(r.itemID),needle) or contains(r.where,needle) or contains(r.type,needle) or contains(r.char,needle))
    end
    for i=#days,1,-1 do
        local day=days[i]; local chunk={}
        Store.IterDays(day,day,function(_,rs) for _,r in ipairs(rs) do if matches(r) then chunk[#chunk+1]=r end end end,{desc=true})
        if not f.type or f.type=="all" or f.type=="loot" then
            for char,counters in pairs((db().loot or {})[day] or {}) do if charMatches(char,f) then for key,count in pairs(counters) do
                local id,src,zone=key:match("^(%d+)|([^|]+)|(.*)$"); id=tonumber(id)
                if id then local money=src=="Money"; local price=money and count or Model.MarketOrVendorPrice(id)
                    local r={time=dayEnd(day),char=char,econ=Store.DeriveEcon(char),type=money and "MONEY_LOOT" or src=="Mob" and "LOOT" or "GATHER",where=zone.." ("..src..")",zone=zone,itemID=id,qty=money and 1 or count,unit=price,total=money and count or 0,extra={source=src}}
                    if matches(r) then chunk[#chunk+1]=r end
                end
            end end end
        end
        totalMatched=totalMatched+#chunk
        if #rows<500 and #chunk>0 then
            tsort(chunk,function(a,b) return a.time>b.time end)
            for _,r in ipairs(chunk) do
                if #rows>=500 then break end
                local copy={}; for key,value in pairs(r) do copy[key]=value end
                copy.typeLabel=Model.TYPE_LABELS[r.type] or r.type
                copy.charShort=Model.CharShort(r.char)
                copy.itemName=r.itemID>0 and Model.ItemName(r.itemID) or ""; copy.name=copy.itemName
                if r.itemID>0 then copy.icon=Model.ItemIcon(r.itemID) end
                rows[#rows+1]=copy
            end
        end
    end
    return {rows=rows,totalMatched=totalMatched}
end
local function pending(f)
    local count,refund=0,0; local perChar={}; local idx=Model.GetIndexes(); local h=H()
    for char,tiers in pairs(db().pouches or {}) do if charMatches(char,f) then
        local c,v=0,0
        for _,pool in pairs(tiers) do for _,p in ipairs(pool) do
            local w=idx.WRIT_BY_ITEM[p.writItemID]; local value=h and h.GetWritPouchInfo and h.GetWritPouchInfo(w) or 0
            c=c+1; v=v+(tonumber(value) or 0)
        end end
        perChar[char]={count=c,refund=v}; count=count+c; refund=refund+v
    end end
    return count,refund,perChar
end
local function averages(f,from,to)
    local cost,cash,pouch,rep,favorCost,favor=0,0,0,0,0,0; local tiers,daily={},{}
    local totalWrits,totalCrates=0,0
    local trendStart=Store.DayKey(nowSec()-29*86400); local trendEnd=Store.DayKey()
    for day,chars in pairs(db().dayStats or {}) do
        local inPeriod=day>=from and day<=to; local inTrend=day>=trendStart and day<=trendEnd
        if inPeriod or inTrend then for char,d in pairs(chars) do if charMatches(char,f) then
            local net=(d.writCost or 0)-(d.writQuestCash or 0)-(d.pouchCash or 0); local fn=(d.crateCost or 0)-(d.crateCash or 0)
            if inPeriod then
                cost=cost+(d.writCost or 0); cash=cash+(d.writQuestCash or 0); pouch=pouch+(d.pouchCash or 0); rep=rep+(d.writRep or 0); favorCost=favorCost+fn; favor=favor+(d.favorGained or 0)
                totalWrits=totalWrits+(d.writsDone or 0); totalCrates=totalCrates+(d.cratesDone or 0)
                for tier,td in pairs(d.tiers or {}) do
                    local t=tiers[tier] or {cost=0,rep=0,gross=0,refunds=0,writs=0}; tiers[tier]=t
                    t.cost=t.cost+(td.cost or 0)-(td.cash or 0)-(td.refund or 0); t.rep=t.rep+(td.rep or 0)
                    t.gross=t.gross+(td.cost or 0); t.refunds=t.refunds+(td.cash or 0)+(td.refund or 0); t.writs=t.writs+(td.writs or 0)
                end
            end
            if inTrend then local t=daily[day] or {net=0,rep=0,favorCost=0,favor=0}; daily[day]=t; t.net=t.net+net; t.rep=t.rep+(d.writRep or 0); t.favorCost=t.favorCost+fn; t.favor=t.favor+(d.favorGained or 0) end
        end end end
    end
    local perTier={}; for order,tier in ipairs({"Apprentice","Journeyman","Expert","Artisan"}) do
        local t=tiers[tier]; perTier[tier]=t and t.rep>0 and t.cost/t.rep or nil
        perTier[#perTier+1]={tier=tier,tierOrder=order,writs=t and t.writs or 0,rep=t and t.rep or 0,grossCost=t and t.gross or 0,refunds=t and t.refunds or 0,netCost=t and t.cost or 0,perRep=perTier[tier]}
    end
    local trend={}; for _,day in ipairs(sortedKeys(daily)) do local d=daily[day]; trend[#trend+1]={day=day,label=day,perRep=d.rep>0 and d.net/d.rep or nil,favorPrice=d.favor>0 and max(0,d.favorCost/d.favor) or nil} end
    local pc,pv=pending(f)
    return {perRep=rep>0 and (cost-cash-pouch)/rep or nil,perRepByTier=perTier,favorPrice=favor>0 and max(0,favorCost/favor) or 0,trend=trend,pendingPouches=pc,pendingRefundEst=pv,pendingRefund=pv,grossCost=cost,questCash=cash,pouchRefund=pouch,netCost=cost-cash-pouch,repGained=rep,totalFavor=favor,totalFavorNetCost=favorCost,totalWrits=totalWrits,totalCrates=totalCrates}
end
local function investments(f,from,to)
    local idx=Model.GetIndexes(); local pushes,recipes,active={},{},{}; local allRows={}
    -- Standing boundaries require history before the selected window as well.
    Store.IterDays("0000-00-00",to,function(_,rows) for _,r in ipairs(rows) do if charMatches(r.char,f) then allRows[#allRows+1]=r end end end)
    tsort(allRows,function(a,b) return a.time<b.time end)
    local function newPush(char,at,fromStanding) return {char=char,charShort=Model.CharShort(char),name="Active Push",label="Active Push",startTime=at,startedAt=at,fromStanding=fromStanding,toStanding="Active Push",active=true,writsDone=0,grossCost=0,questCash=0,pouchRefund=0,repGained=0,pendingPouches=0,pendingRefund=0} end
    local function finish(p)
        p.netCost=p.grossCost-p.questCash-p.pouchRefund; p.costPerRep=p.repGained>0 and p.netCost/p.repGained or nil
        if (p.writsDone>0 or p.pouchRefund>0) and Store.DayKey(p.endTime or nowSec())>=from then pushes[#pushes+1]=p end
    end
    for _,r in ipairs(allRows) do
        local e=r.extra or {}; local p=active[r.char]
        if r.type=="WRIT_TURNIN" or r.type=="POUCH_MONEY" or r.type=="STANDING" then
            if not p then p=newPush(r.char,r.time); active[r.char]=p end
            if r.type=="WRIT_TURNIN" then
                local w=idx.WRIT_BY_ITEM[r.itemID]; p.writsDone=p.writsDone+(r.qty or 1); p.grossCost=p.grossCost+(r.cogs or 0); p.questCash=p.questCash+r.total; p.repGained=p.repGained+(tonumber(e.rep) or (w and w.rep) or 0)
            elseif r.type=="POUCH_MONEY" then p.pouchRefund=p.pouchRefund+r.total
            else
                p.endTime=r.time; p.name=e.name or r.where; p.label=p.name; p.from=e.from; p.to=e.to
                p.active=false; p.fromStanding=p.fromStanding or e.from; p.toStanding=e.name or e.to; finish(p)
                active[r.char]=newPush(r.char,r.time,e.name or e.to)
            end
        end
        if (r.type=="AH_BUY" or r.type=="VENDOR_BUY" or r.type=="FAVOR_SPEND") and Store.DayKey(r.time)>=from then
            local rec=idx.RECIPE_BY_SCROLL[r.itemID]; local isRecipe=rec~=nil
            if not isRecipe and _G.GetItemInfoInstant then local _,_,_,_,_,classID=_G.GetItemInfoInstant(r.itemID); isRecipe=classID==9 end
            if isRecipe then
                local output=rec and (rec.outputItemID or rec.itemID); local rEcon=r.econ or Store.DeriveEcon(r.char)
                local investment={char=r.char,charShort=Model.CharShort(r.char),itemID=r.itemID,name=Model.ItemName(r.itemID),time=r.time,purchaseDay=Store.DayKey(r.time),investCost=max(0,-r.total)+(tonumber(e.favorCopperValue) or 0),outputItemID=output,realizedProfit=0,unitsSold=0}
                investment.favorSpent=r.type=="FAVOR_SPEND" and (tonumber(e.favor) or 0) or 0
                investment.copperSpent=max(0,-r.total)
                if output then for day,econs in pairs(db().roll or {}) do if day>=investment.purchaseDay and day<=to then
                    for ck,rolls in pairs(econs) do
                        if (ck==rEcon or Store.DeriveEcon(ck)==rEcon) and rollKeyMatches(ck,f) then
                            local rr=rolls[output]
                            if rr then investment.realizedProfit=investment.realizedProfit+(rr.gross or 0)-(rr.fee or 0)-(rr.cogs or 0)-(rr.depLost or 0); investment.unitsSold=investment.unitsSold+(rr.sold or 0) end
                        end
                    end
                end end end
                investment.netPayback=investment.realizedProfit-investment.investCost; investment.isPaidBack=investment.netPayback>=0; recipes[#recipes+1]=investment
                investment.recipeName=investment.name; investment.source=r.type; investment.outputName=output and Model.ItemName(output) or "Unknown"
                investment.paidBackPct=investment.investCost>0 and investment.realizedProfit/investment.investCost or (investment.isPaidBack and 1 or 0)
            end
        end
    end
    local _,_,pc=pending(f)
    for char,p in pairs(active) do local pendingChar=pc[char]; if pendingChar then p.pendingPouches=pendingChar.count; p.pendingRefund=pendingChar.refund end; finish(p) end
    tsort(pushes,function(a,b) return (a.endTime or nowSec())>(b.endTime or nowSec()) end)
    tsort(recipes,function(a,b) return a.time>b.time end)
    return {pushes=pushes,recipes=recipes}
end
local cache,cacheOrder={},{}; local ledgerCache={}
function Model.Invalidate(kind)
    if kind=="snapshot" or kind=="writs" then
        for sig,value in pairs(cache) do if value._view~="items" then cache[sig]=nil end end
        return
    end
    Model.generation=Model.generation+1
    cache={}; cacheOrder={}; ledgerCache={}
end
local function filterSetKey(value)
    if type(value)~="table" then return tostring(value or "") end
    local keys={}; for k,v in pairs(value) do if type(k)=="number" then keys[#keys+1]=tostring(type(v)=="boolean" and k or v) elseif v then keys[#keys+1]=tostring(k) end end; tsort(keys); return tconcat(keys,",")
end
function Model.Compute(view,filters)
    filters=filters or {}; view=view or "overview"; local h=H()
    local priceSrc=_G.MerchantMasterDB and tostring(_G.MerchantMasterDB.priceSource or "auto") or "auto"
    -- These two views value synthetic loot at today's price; item history does not.
    local marketView=view=="overview" or view=="ledger"
    local sig=tconcat({view=="items" and (Store.accountingVersion or Store.version) or Store.version,view,filters.char or "all",filters.type or "all",filters.zone or "all",filters.period or "30d",filters.search or "",tostring(filters.knownCostOnly~=false),marketView and h and tostring(h.priceCacheEpoch or 0) or "0",marketView and priceSrc or ""},"|")
        .."|"..Store.DayKey().."|"..tostring(filters.mode or filters.itemMode or "").."|"..tostring(filters.rankSeparate)
        .."|"..filterSetKey(filters.source or filters.sources).."|"..filterSetKey(filters.types).."|"..tostring(filters.groupBy).."|"..tostring(filters.minRarity).."|"..filterSetKey(filters.rarities)
        .."|"..tostring(filters.prof or filters.group).."|"..tostring(filters.econ).."|"..tostring(filters.faction).."|"..filterSetKey(filters.chars)
        .."|"..tostring(ns.Inventory and ns.Inventory.version or 0)
        .."|"..tostring(filters.offset).."|"..tostring(filters.limit).."|"..tostring(filters.coalesce)
    if cache[sig] then return cache[sig] end
    local from,to=Model.PeriodBounds(filters.period); local value
    if view=="items" then value=itemRows(filters,from,to)
    elseif view=="overview" then value=overview(filters,from,to)
    elseif view=="ledger" then value=ledger(filters,from,to)
    elseif view=="portfolio" then value=portfolio(filters,from,to)
    elseif view=="invest" then value=investments(filters,from,to)
    elseif view=="writs" or view=="averages" then value=averages(filters,from,to)
    else value={rows={}} end
    value._view=view
    if view=="items" then
        value.byItemID={}
        for _,row in ipairs(value.rows or {}) do checkpoint(); local id=tonumber(row.itemID); if id and not value.byItemID[id] then value.byItemID[id]=row end end
    end
    cache[sig]=value; cacheOrder[#cacheOrder+1]=sig
    if #cacheOrder>32 then cache[table.remove(cacheOrder,1)]=nil end
    return value
end

local function ledgerRows(filters)
    local key=tconcat({tostring(Store.version),tostring(filters.char),tostring(filters.econ),tostring(filters.faction),filterSetKey(filters.chars),tostring(filters.period),tostring(filters.type),tostring(filters.ledgerPreset),tostring(filters.zone),tostring(filters.search),filterSetKey(filters.sources or filters.source),filterSetKey(filters.types),tostring(filters.minRarity),filterSetKey(filters.rarities),tostring(filters.prof or filters.group),tostring(filters.coalesce)},"|")
    local cached=ledgerCache[key]; if cached then return cached.rows,cached.totals end
    local from,to=Model.PeriodBounds(filters.period); local rows={}; local needle=strlower(filters.search or "")
    local days={}; for d in pairs(db().days or {}) do if d>=from and d<=to then days[#days+1]=d end end; tsort(days,function(a,b)return a>b end)
    local function add(r)
        local extra=r.extra or {}; local cp=extra.buyer or extra.seller or extra.counterparty or ""
        local sourceOK=selectedSource(r,filters)
        local isTradeGold=(filters.type=="trade" or filters.ledgerPreset=="trade") and r.type=="MONEY_TRANSFER" and r.where=="Trade"
        local typeGroupOK=Store.MatchesTypeGroup(r.type,filters.type) or isTradeGold
        local typeOK=not filters.types or filters.types[r.type]==true or isTradeGold
        local match=selectedChar(r.char,filters) and (not filters.econ or (r.econ or Store.DeriveEcon(r.char))==filters.econ)
            and typeGroupOK and (not filters.zone or filters.zone=="all" or r.zone==filters.zone or r.where==filters.zone)
            and typeOK and sourceOK and (needle=="" or contains(Model.ItemName(r.itemID),needle) or contains(r.where,needle) or contains(r.type,needle) or contains(Model.TYPE_LABELS[r.type] or "",needle) or contains(r.char,needle) or contains(cp,needle))
        local prof=tostring(filters.prof or filters.group or "")
        if match and prof~="" and prof~="all" then
            if not professionMatches(r.itemID,strlower(prof)) then match=false end
        end
        local quality
        if filters.minRarity or filters.rarities then quality=_G.C_Item and _G.C_Item.GetItemQualityByID and _G.C_Item.GetItemQualityByID(r.itemID); if not quality and _G.GetItemInfo then local _,_,q=_G.GetItemInfo(r.itemID); quality=q end end
        if match and filters.minRarity and (tonumber(quality) or -1)<tonumber(filters.minRarity) then match=false end
        if match and filters.rarities and not filters.rarities[tonumber(quality) or 0] then match=false end
        if match then local c={}; for k,v in pairs(r) do c[k]=v end; c.extra=extra; c.typeLabel=Model.TYPE_LABELS[r.type] or r.type; c.counterparty=cp; c.charShort=Model.CharShort(r.char); c.itemName=r.itemID>0 and Model.ItemName(r.itemID) or ""; c.name=c.itemName; c.icon=r.itemID>0 and Model.ItemIcon(r.itemID) or nil; c.eid=extra.eid or r.eid; c.stackSize=extra.stackSize or r.qty; c.auctionsCount=extra.auctionsCount; if r.type=="DISENCHANT_BROKEN" and c.profit==nil then local ev=tonumber(extra.estValue) or 0; c.profit=ev>0 and (ev-(tonumber(r.cogs) or 0)) or 0 end; rows[#rows+1]=c end
    end
    Store.IterDays(from,to,function(_,list) for _,r in ipairs(list) do add(r) end end,{desc=true})
    if not filters.type or filters.type=="all" or filters.type=="loot" then
        for day,chars in pairs(db().loot or {}) do if day>=from and day<=to then for char,counters in pairs(chars) do
            if selectedChar(char,filters) then for key,count in pairs(counters) do
                local id,src,zone=key:match("^(%d+)|([^|]+)|(.*)$"); id=tonumber(id)
                if id then
                    local money=src=="Money"; local unit=money and count or Model.MarketOrVendorPrice(id)
                    add({time=dayEnd(day),char=char,econ=Store.DeriveEcon(char),type=money and "MONEY_LOOT" or src=="Mob" and "LOOT" or "GATHER",where=zone.." ("..src..")",zone=zone,itemID=id,qty=money and 1 or count,unit=unit,total=money and count or 0,extra={source=src}})
                end
            end end
        end end end
    end
    tsort(rows,function(a,b) if a.time==b.time then local ao=(a.extra and a.extra.replayOrder) or 0; local bo=(b.extra and b.extra.replayOrder) or 0; if ao==bo then return tostring(a.eid or "")>tostring(b.eid or "") end; return ao>bo end return a.time>b.time end)
    ledgerCache={}; ledgerCache[key]={rows=rows}; return rows
end
function Model.QueryLedger(filters,cursor,limit)
    filters=filters or {}; cursor=max(0,floor(tonumber(cursor) or tonumber(filters.offset) or 0)); limit=tonumber(limit) or tonumber(filters.limit) or 500
    if limit<0 then limit=0 end
    local matchedRows=ledgerRows(filters); local all=matchedRows
    if filters.coalesce and Store.CoalesceRows then
        local eventCounts,eventStackSizes={},{}
        for _,raw in ipairs(matchedRows) do
            local e=raw.extra or {}; local eventID=tostring(Store.EventID(raw)); local count=tonumber(e.auctionsCount or raw.auctionsCount) or 1
            eventCounts[eventID]=count; eventStackSizes[eventID]=tonumber(e.stackSize) or (tonumber(raw.qty) or 0)/max(1,count)
        end
        all=Store.CoalesceRows(all,300)
        for _,r in ipairs(all) do
            local count=0; for _,eid in ipairs(r.rawEventIDs or {}) do count=count+(eventCounts[tostring(eid)] or 1) end
            r.auctionsCount=count>0 and count or 1; r.stackSize=(r.extra and r.extra.stackSize) or eventStackSizes[tostring((r.rawEventIDs or {})[1])] or r.qty
        end
    end
    local cacheKey=tconcat({tostring(Store.version),tostring(filters.char),tostring(filters.econ),tostring(filters.faction),filterSetKey(filters.chars),tostring(filters.period),tostring(filters.type),tostring(filters.ledgerPreset),tostring(filters.zone),tostring(filters.search),filterSetKey(filters.sources or filters.source),filterSetKey(filters.types),tostring(filters.minRarity),filterSetKey(filters.rarities),tostring(filters.prof or filters.group),tostring(filters.coalesce)},"|")
    local cached=ledgerCache[cacheKey]; local totals=cached and cached.queryTotals
    if not totals then totals={qty=0,inflow=0,outflow=0,net=0,fee=0,cogs=0,profit=0}
    for _,r in ipairs(matchedRows) do
        local isFromBid=(r.type=="AH_BUY" and r.extra and r.extra.fromBid==true)
        local amount=isFromBid and 0 or (tonumber(r.total) or 0); local fee=tonumber(r.extra and r.extra.fee) or 0
        totals.qty=totals.qty+(tonumber(r.qty) or 0); totals.net=totals.net+amount; totals.fee=totals.fee+fee
        totals.cogs=totals.cogs+(tonumber(r.cogs) or 0)
        if amount>0 then totals.inflow=totals.inflow+amount else totals.outflow=totals.outflow-min(0,amount) end
        local sale=r.type=="AH_SELL" or r.type=="VENDOR_SELL" or r.type=="COD_SELL" or r.type=="TRADE_SELL"
        local rowProfit=tonumber(r.profit)
        if rowProfit==nil then
            if sale then rowProfit=amount-(tonumber(r.cogs) or 0)-(tonumber(r.depLost) or 0)
            elseif r.type=="DISENCHANT_BROKEN" then
                local estVal=tonumber(r.extra and r.extra.estValue) or 0
                rowProfit=estVal>0 and (estVal-(tonumber(r.cogs) or 0)) or 0
            elseif r.type=="AH_EXPIRE" or r.type=="AH_CANCEL" then rowProfit=-(tonumber(r.extra and r.extra.depLost) or tonumber(r.depLost) or 0)
            else rowProfit=0 end
        end
        totals.profit=totals.profit+rowProfit
        if r.auctionsCount==nil and r.extra then r.auctionsCount=r.extra.auctionsCount end
    end
    cached=cached or {rows=matchedRows}; cached.queryTotals=totals; ledgerCache[cacheKey]=cached
    end
    local page={}; local stop=limit==math.huge and #all or min(#all,cursor+limit)
    for i=cursor+1,stop do page[#page+1]=all[i] end
    return {rows=page,totalMatched=#matchedRows,cursor=cursor,limit=limit,hasMore=stop<#all,totals=totals}
end
function Model.GetItemStats(itemID,filters)
    itemID=tonumber(itemID); if not itemID or itemID<=0 then return nil end
    filters=filters or {}
    if next(filters)==nil then local _,econ=Store.CurrentCharAndEcon(); filters={char="all",econ=econ,period="all"} end
    local requested={}; for k,v in pairs(filters) do requested[k]=v end
    if requested.knownCostOnly==nil then requested.knownCostOnly=false end
    local result=Model.Compute("items",requested)
    return result.byItemID and result.byItemID[itemID]
end
-- Prime both tooltip query signatures once, with a bounded amount of Lua work per callback.
local prepareCallbacks,prepareKey,tooltipIndexes
local function tooltipIndexKey()
    local _,econ=Store.CurrentCharAndEcon()
    return tconcat({Model.generation,Store.accountingVersion or Store.version,ns.Inventory and ns.Inventory.version or 0,Store.DayKey(),tostring(econ)},"|"),econ
end
function Model.GetPreparedTooltipStats(itemID)
    local key=tooltipIndexKey()
    if not tooltipIndexes or tooltipIndexes.key~=key then return nil,nil,false end
    return tooltipIndexes.all.byItemID[itemID],tooltipIndexes.recent.byItemID[itemID],true
end
function Model.PrepareTooltipIndexes(done)
    local key,econ=tooltipIndexKey()
    if tooltipIndexes and tooltipIndexes.key==key then done(true); return end
    if prepareCallbacks and prepareKey==key then prepareCallbacks[#prepareCallbacks+1]=done; return end
    prepareKey=key; prepareCallbacks={done}
    local callbacks=prepareCallbacks
    local indexes={key=key}
    local worker=coroutine.create(function()
        indexes.all=Model.Compute("items",{char="all",econ=econ,period="all",knownCostOnly=false})
        indexes.recent=Model.Compute("items",{char="all",econ=econ,period="180d",knownCostOnly=false})
    end)
    local function step()
        if prepareCallbacks~=callbacks then return end
        if tooltipIndexKey()~=key then prepareCallbacks=nil; return end
        preparer=worker; workCount=0; Store._prepareCheckpoint=function() coroutine.yield() end
        local ok,err=coroutine.resume(worker)
        preparer=nil; Store._prepareCheckpoint=nil
        if not ok then
            prepareCallbacks=nil
            for _,callback in ipairs(callbacks) do if callback then callback(false) end end
            if _G.geterrorhandler then _G.geterrorhandler()(err) end
            return
        end
        if coroutine.status(worker)=="dead" then
            prepareCallbacks=nil; tooltipIndexes=indexes
            for _,callback in ipairs(callbacks) do if callback then callback(true) end end
        elseif _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.01,step)
        else step() end
    end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0,step) else step() end
end
function Model.GetItemDetail(itemKey,filters)
    filters=filters or {}; local keyText=tostring(type(itemKey)=="table" and itemKey.itemID or itemKey or "")
    local id=tonumber(type(itemKey)=="table" and itemKey.itemID) or tonumber(keyText:match("item:(%d+)")) or tonumber(keyText:match("^(%d+)[|:]")) or tonumber(keyText)
    local itemLevel=tonumber(type(itemKey)=="table" and itemKey.itemLevel) or tonumber(filters.itemLevel)
    local variant=(type(itemKey)=="table" and (itemKey.variant or itemKey.itemString)) or keyText:match("^%d+[|:](.+)$") or filters.variant
    if not id then return nil end
    local statsFilters={}; for k,v in pairs(filters) do statsFilters[k]=v end
    if itemLevel then statsFilters.groupBy="level"; statsFilters.itemLevel=itemLevel
    elseif variant then statsFilters.groupBy="specific" end
    local function levelMatches(candidate) return tonumber(candidate.itemLevel) == itemLevel end
    local s
    if itemLevel then for _,candidate in ipairs((Model.Compute("items",statsFilters).rows or {})) do if tonumber(candidate.itemID)==id and levelMatches(candidate) then s=candidate; break end end
    elseif variant then for _,candidate in ipairs((Model.Compute("items",statsFilters).rows or {})) do if tonumber(candidate.itemID)==id and candidate.variant==variant then s=candidate; break end end
    else s=Model.GetItemStats(id,statsFilters) end
    if not s then s={itemID=id} end
    local detail={itemID=id,name=Model.ItemName(id),icon=Model.ItemIcon(id),curBasis=s.curBasis,basisQty=s.curBasisQty,smartAvgBuy=s.smartAvgBuy,
        expSinceSale=s.expSinceSale or 0,canSinceSale=s.canSinceSale or 0,saleRate=s.saleRate,sellThrough=s.sellThrough,lastSoldTs=s.lastSoldTs,lastSoldUnit=s.lastSoldUnit,
        lastBuyTs=s.lastBuyTs,lastBuyUnit=s.lastBuyUnit,minBuy=s.minBuy,maxBuy=s.maxBuy,minSell=s.minSell,maxSell=s.maxSell,topBuyers={},topSellers={},transactions={}}
    detail.windows={}
    for _,period in ipairs({"7d","30d","all"}) do
        local windowFilters={}; for k,v in pairs(statsFilters) do windowFilters[k]=v end; windowFilters.period=period
        local rows
        if itemLevel then for _,candidate in ipairs((Model.Compute("items",windowFilters).rows or {})) do if tonumber(candidate.itemID)==id and levelMatches(candidate) then rows=candidate; break end end
        elseif variant then for _,candidate in ipairs((Model.Compute("items",windowFilters).rows or {})) do if tonumber(candidate.itemID)==id and candidate.variant==variant then rows=candidate; break end end end
        if not rows then if itemLevel or variant then rows={} else rows=Model.GetItemStats(id,windowFilters) or {} end end
        detail.windows[period=="7d" and "d7" or period=="30d" and "d30" or "all"]={sold=rows.sold or 0,avgSell=rows.avgSell,totalSales=rows.gross or 0,bought=rows.bought or 0,avgBuy=rows.avgBuy,totalSpent=rows.spent or 0,profit=rows.profit or 0,avgProfit=rows.avgProfit}
    end
    local buyers,sellers={},{}; local txFilters={}; for k,v in pairs(filters) do txFilters[k]=v end; txFilters.period=filters.period or "all"; txFilters.type="all"
    local all=ledgerRows(txFilters)
    for _,r in ipairs(all) do if tonumber(r.itemID)==id then
        local e=r.extra or {}; local buyer=e.buyer; local seller=e.seller
        local rowVariant=tostring(e.variant or e.itemString or "base")
        local rowLevel=tonumber(e.itemLevel or e.level)
        if not rowLevel and e.itemString and _G.GetDetailedItemLevelInfo then rowLevel=tonumber(_G.GetDetailedItemLevelInfo(e.itemString)) end
        if not rowLevel and _G.GetItemInfo then local _,_,_,level=_G.GetItemInfo(id); rowLevel=tonumber(level) end
        if (variant and rowVariant~=variant) or (itemLevel and rowLevel~=itemLevel) then -- ignore other item groups
        else
        if buyer then local b=buyers[buyer] or {name=buyer,qty=0,total=0}; buyers[buyer]=b; b.qty=b.qty+(r.qty or 0); b.total=b.total+(r.total or 0) end
        if seller then local b=sellers[seller] or {name=seller,qty=0,total=0}; sellers[seller]=b; b.qty=b.qty+(r.qty or 0); b.total=b.total+abs(r.total or 0) end
        detail.transactions[#detail.transactions+1]={eid=r.eid,time=r.time,type=r.type,charShort=r.charShort,counterparty=r.counterparty,qty=r.qty,unit=r.unit,total=r.total,profit=r.profit}
        end
    end end
    local function top(map,target) for _,v in pairs(map) do target[#target+1]=v end; tsort(target,function(a,b)return a.qty>b.qty end); while #target>3 do table.remove(target) end end
    top(buyers,detail.topBuyers); top(sellers,detail.topSellers)
    detail.inventory=ns.Inventory and ns.Inventory.GetItemBreakdown(id,filters.econ)
    return detail
end
function Model.GetInventoryMatrix(filters)
    filters=filters or {}; local rows={}; local totals={items=0,units=0,value=0}; local inv=ns.Inventory
    if not inv or not inv.GetAllItems then return {rows=rows,totals=totals} end
    local _,activeEconomy=Store.CurrentCharAndEcon()
    local charFilter=filters.char and filters.char~="all" and filters.char or nil
    for _,src in ipairs(inv.GetAllItems({econ=filters.econ,char=charFilter,search=filters.search,includeOffline=true})) do
        local selected=0; local filteredChars={}
        for _,c in ipairs(src.byChar or {}) do
            local keep=selectedChar(c.char,filters)
            local meta=_G.MerchantMasterDB and _G.MerchantMasterDB.chars and _G.MerchantMasterDB.chars[c.char]
            if keep and filters.faction and filters.faction~="all" then keep=meta and meta.faction==filters.faction end
            if keep then selected=selected+1; filteredChars[#filteredChars+1]=c end
        end
        if charFilter or filters.chars or (filters.faction and filters.faction~="all") then
            if selected==0 then src.total=0; src.bags=0; src.bank=0; src.mail=0; src.inTransit=0; src.ah=0; src.gear=0; if not filters.includeGuild then src.guild=0 end
            else src.byChar=filteredChars; src.bags=0; src.bank=0; src.mail=0; src.inTransit=0; src.ah=0; src.gear=0; src.guild=0
                for _,c in ipairs(filteredChars) do for _,key in ipairs({"bags","bank","mail","inTransit","ah","gear"}) do src[key]=src[key]+(tonumber(c[key]) or 0) end end
            end
        end
        local id=src.itemID; local unit=0; local h=H(); local source=filters.valSource or (_G.MerchantMasterDB and _G.MerchantMasterDB.anInvPriceSource) or "market"
        if source=="vendor" then unit=h and h.GetVendorSellPrice and tonumber(h.GetVendorSellPrice(id)) or 0
        elseif source=="basis" then local basisEcon=filters.econ or (filters.char and filters.char~="all" and Store.DeriveEcon(filters.char)) or activeEconomy; local _,v=Store.Basis(basisEcon,id); unit=v or 0
        elseif source=="avgSell" then unit=tonumber(Model.GetPriceSource("AvgSell",id,filters)) or 0
        else unit=Model.MarketOrVendorPrice(id) end
        local gear=tonumber(src.gear) or 0; local bound=gear
        if filters.wealthMode then
            local invRoot=db().inventory or {}
            for _,c in ipairs(src.byChar or {}) do local snapshot=invRoot[c.char] or {}; bound=bound+((snapshot.boundBags and snapshot.boundBags[id]) or 0)+((snapshot.boundBank and snapshot.boundBank[id]) or 0) end
            bound=min(bound,(tonumber(src.bags) or 0)+(tonumber(src.bank) or 0)+gear)
        end
        local totalQty=(tonumber(src.bags) or 0)+(tonumber(src.bank) or 0)+(tonumber(src.mail) or 0)+(tonumber(src.inTransit) or 0)+(tonumber(src.ah) or 0)+gear+(filters.includeGuild and (tonumber(src.guild) or 0) or 0)
        local totalValue=unit*(totalQty-gear)
        if filters.wealthMode and bound>0 and h and h.GetVendorSellPrice then
            totalValue=unit*max(0,totalQty-bound)+(tonumber(h.GetVendorSellPrice(id)) or 0)*bound
        else totalValue=unit*totalQty end
        local weightedUnit=totalQty>0 and totalValue/totalQty or unit
        local stale=false; for _,c in ipairs(src.byChar or {}) do if c.stale and ((c.bags or 0)+(c.bank or 0)+(c.mail or 0)+(c.inTransit or 0)+(c.ah or 0)+(c.gear or 0)>0) then stale=true end end
        local row={itemID=id,name=src.name or Model.ItemName(id),icon=Model.ItemIcon(id),bags=src.bags,bank=src.bank,mail=src.mail,inTransit=src.inTransit,ah=src.ah,gear=gear,guild=filters.includeGuild and src.guild or 0,
            totalQty=totalQty,unitValue=weightedUnit,totalValue=totalValue,charsSummary=src.byChar,updatedAt=src.updatedAt,stale=stale or (nowSec()-(tonumber(src.updatedAt) or 0)>7*86400)}
        if row.totalQty>0 then rows[#rows+1]=row; totals.items=totals.items+1; totals.units=totals.units+row.totalQty; totals.value=totals.value+row.totalValue end
    end
    return {rows=rows,totals=totals}
end
function Model.GetPriceSource(sourceKey,itemID,filters)
    if not filters or next(filters)==nil then local _,econ=Store.CurrentCharAndEcon(); filters={char="all",econ=econ,period="all"} end
    local s=Model.GetItemStats(itemID,filters); if not s then return nil end
    local key=strlower(tostring(sourceKey or "")):gsub("[^a-z]","")
    local fields={avgsell="avgSell",minsell="minSell",maxsell="maxSell",avgbuy="avgBuy",smartavgbuy="smartAvgBuy",curbasis="curBasis",minbuy="minBuy",maxbuy="maxBuy",salerate="saleRate",numexpires="expSinceSale"}
    local field=fields[key]; if not field then return nil end
    local value=s[field]
    if key=="salerate" and value~=nil then return floor(value*100+0.5) end
    return value
end
function Model.GetSaleHint(itemID)
    local _,econ=Store.CurrentCharAndEcon(); local s=Model.GetItemStats(itemID,{char="all",econ=econ,period="180d"}); if not s then return nil end
    local slow=s.isSlowing or (s.expSinceSale or 0)>=5; local action=slow and "liquidate" or ((s.saleRate or 1)<0.25 and "reprice" or "hold")
    return {action=action,reason=slow and "Repeated expires or slowing sales" or "Based on recent sale rate",expSinceSale=s.expSinceSale or 0,saleRate=s.saleRate,isSlowing=not not s.isSlowing}
end
Model.GetAccountingPrice=Model.GetPriceSource
ns.GetPriceSource=Model.GetPriceSource; ns.GetItemStats=Model.GetItemStats; ns.GetItemDetail=Model.GetItemDetail; ns.GetInventoryMatrix=Model.GetInventoryMatrix; ns.GetSaleHint=Model.GetSaleHint
