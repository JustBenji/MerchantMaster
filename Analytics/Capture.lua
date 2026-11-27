local addonName, host = ...
host.Analytics = host.Analytics or {}
local ns = host.Analytics
_G.MerchantMasterAnalytics = ns
local function H()
    return host
end

local Capture = {}; ns.Capture = Capture
local Store,Model=ns.Store,ns.Model
local hasSecret
local function ensureTable(t,k) t[k]=type(t[k])=="table" and t[k] or {}; return t[k] end
local function nowSec() local v=_G.time and _G.time(); if not hasSecret(v) and tonumber(v) then return tonumber(v) end; return (os and os.time and os.time()) or 0 end
hasSecret=function(...)
    for i=1,select("#",...) do
        local v=select(i,...)
        if _G.issecrettable and type(v)=="table" and _G.issecrettable(v) then return true end
        if _G.issecretvalue and _G.issecretvalue(v) then return true end
    end
    return false
end
Capture.HasSecret=hasSecret
local function safeTable(v) return type(v)=="table" and not hasSecret(v) end
local function ready()
    local h=H()
    return Store.initialized and not Store.readOnly and (Capture._testReady or (h and h.app and h.app.charKey~=nil))
end
local function safeCall(kind,fn,...)
    if Store.IsDisabled(kind) then return end
    local ok,err=pcall(fn,...); if not ok then Store.RecordError(kind,err) end
end
Capture.SafeCall=safeCall
local function money() local v=_G.GetMoney and _G.GetMoney(); return not hasSecret(v) and (tonumber(v) or 0) or 0 end
local function zone() local v=_G.GetRealZoneText and _G.GetRealZoneText(); return not hasSecret(v) and type(v)=="string" and v or "Unknown" end
local function after(delay,fn) if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(delay,fn) end end
local function db() return Store.db or _G.MerchantMasterLedgerDB end
local function itemCount(id)
    local fn=(_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
    local n=fn and fn(id); return not hasSecret(n) and (tonumber(n) or 0) or 0
end
local function merchantOpen()
    local shown=_G.MerchantFrame and _G.MerchantFrame.IsShown and _G.MerchantFrame:IsShown()
    return not hasSecret(shown) and shown or false
end
local function itemID(link) return not hasSecret(link) and type(link)=="string" and tonumber(link:match("item:(%d+)")) or nil end
local function bagInfo(bag,slot)
    if _G.C_Container and _G.C_Container.GetContainerItemInfo then
        local t=_G.C_Container.GetContainerItemInfo(bag,slot)
        if safeTable(t) and not hasSecret(t.itemID,t.stackCount,t.hyperlink) then return t.itemID or itemID(t.hyperlink),t.stackCount or 1 end
    end
    local fn=(_G.C_Container and _G.C_Container.GetContainerItemID) or _G.GetContainerItemID
    local id=fn and fn(bag,slot)
    if _G.GetContainerItemInfo then
        local _,count,_,_,_,_,link=_G.GetContainerItemInfo(bag,slot)
        if not hasSecret(id,count,link) then return id or itemID(link),tonumber(count) or 1 end
    end
    if not hasSecret(id) then return id,1 end
end
local function locationID(loc)
    if _G.C_Item and _G.C_Item.GetItemID then local ok,id=pcall(_G.C_Item.GetItemID,loc); if ok and not hasSecret(id) and id then return id end end
    if type(loc)=="table" then
        if loc.itemID then return loc.itemID end
        local bag,slot=loc.bagID or loc.bag,loc.slotIndex or loc.slot
        if loc.GetBagAndSlot then bag,slot=loc:GetBagAndSlot() end
        if bag~=nil and slot~=nil then return bagInfo(bag,slot) end
    end
end
local function linkName(link)
    if hasSecret(link) or type(link)~="string" or link=="" then return nil end
    local bracket=link:match("%[(.-)%]")
    if bracket and bracket~="" then return bracket end
    local fn=(_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if fn then
        local ok,nm=pcall(fn,link)
        if ok and not hasSecret(nm) and type(nm)=="string" and nm~="" then return nm end
    end
    return nil
end
local function locationItemName(loc)
    if hasSecret(loc) then return nil end
    if _G.C_Item and _G.C_Item.GetItemLink then
        local ok,lnk=pcall(_G.C_Item.GetItemLink,loc)
        if ok and not hasSecret(lnk) and type(lnk)=="string" and lnk~="" then
            local nm=linkName(lnk); if nm then return nm end
        end
    end
    if type(loc)=="table" then
        local bag,slot=loc.bagID or loc.bag,loc.slotIndex or loc.slot
        if loc.GetBagAndSlot then
            local ok,b,s=pcall(loc.GetBagAndSlot,loc)
            if ok and not hasSecret(b,s) then bag,slot=b,s end
        end
        if not hasSecret(bag,slot) and bag~=nil and slot~=nil then
            if _G.C_Container and _G.C_Container.GetContainerItemLink then
                local lnk=_G.C_Container.GetContainerItemLink(bag,slot)
                local nm=linkName(lnk); if nm then return nm end
            end
            if _G.C_Container and _G.C_Container.GetContainerItemInfo then
                local info=_G.C_Container.GetContainerItemInfo(bag,slot)
                if safeTable(info) and not hasSecret(info.hyperlink,info.itemName) then
                    local nm=linkName(info.hyperlink); if nm then return nm end
                    if type(info.itemName)=="string" and info.itemName~="" then return info.itemName end
                end
            end
            if _G.GetContainerItemLink then
                local lnk=_G.GetContainerItemLink(bag,slot)
                local nm=linkName(lnk); if nm then return nm end
            end
            if _G.GetContainerItemInfo then
                local _,_,_,_,_,_,lnk=_G.GetContainerItemInfo(bag,slot)
                local nm=linkName(lnk); if nm then return nm end
            end
        end
        if not hasSecret(loc.itemLink) and type(loc.itemLink)=="string" then
            local nm=linkName(loc.itemLink); if nm then return nm end
        end
        if not hasSecret(loc.hyperlink) and type(loc.hyperlink)=="string" then
            local nm=linkName(loc.hyperlink); if nm then return nm end
        end
        if not hasSecret(loc.itemName) and type(loc.itemName)=="string" and loc.itemName~="" then return loc.itemName end
    end
    if _G.C_Item and _G.C_Item.GetItemName then
        local ok,nm=pcall(_G.C_Item.GetItemName,loc)
        if ok and not hasSecret(nm) and type(nm)=="string" and nm~="" then return nm end
    end
    return nil
end
local lastMoney
local pendingCommodity,pendingBid,pendingPost,pendingVendorBuy,pendingVendorSell,pendingFavorBuy,pendingPouch,pendingCraft,lootSession,questContext,recentGather,recentContainer,recentCrateFavorGain
local pendingCancels,liveSoldNoticeTime,mailCache={},{},{}
local pendingSendMail,pendingRepair,pendingTrade,pendingBuyback,pendingMailTake,pendingDestroy
local ws3={
    pendingMoneyQueue={}, maxPendingMoney=8, pendingMoneyTTL=5,
    pendingMailTakeQueue={}, maxPendingMailTake=16,
    trainerCache={}, recentAHBids={},
}
Capture._pendingMoneyQueue=ws3.pendingMoneyQueue
Capture._pendingMailTakeQueue=ws3.pendingMailTakeQueue
local stagedSendMoney,stagedSendCOD
local pendingBuyerInvoices={}
local pendingSellerMail={}
local ownAlt,stageRepair,transferPairs,pairForIncoming
local lastDurability
local buybackCache={}
local lastConfirmedPost
local auctionCache={}; Capture.auctionCache=auctionCache
local cursorItem
Capture.pendingCancels=pendingCancels; Capture.liveSoldNoticeTime=liveSoldNoticeTime
local pouchIDs={[284583]="Apprentice",[284584]="Journeyman",[284585]="Expert",[284586]="Artisan"}
local hooked=setmetatable({},{__mode="k"})
local function hook(target,key,kind,fn)
    if type(target)~="table" or type(target[key])~="function" then return end
    local registry=hooked[target]; if not registry then registry={}; hooked[target]=registry end
    if registry[key]==target[key] then return end
    local callback=function(...)
        if not ready() or hasSecret(...) then return end
        Store.ProbeLog(kind,"hook "..key.." args="..select("#",...))
        safeCall(kind,fn,...)
    end
    if _G.hooksecurefunc then
        if target==_G then _G.hooksecurefunc(key,callback) else _G.hooksecurefunc(target,key,callback) end
    else
        -- Offline clients without secure hooks still preserve all return values.
        local original=target[key]
        local function pack(...) return {n=select("#",...),...} end
        target[key]=function(...)
            local result=pack(original(...)); callback(...); return unpack(result,1,result.n)
        end
    end
    registry[key]=target[key]
end
local stagedCompose
local offlineBeforeHooks,offlineMailHooks={},{}
local function installBeforeHook(target,key,fn)
    -- In live WoW prefer taint-safe hooksecurefunc backed by compose snapshots; fall back only in offline tests.
    if type(target)~="table" or type(target[key])~="function" then return end
    if _G.hooksecurefunc then
        hook(target,key,"MAIL",fn)
        return
    end
    local token=tostring(target)..":"..key
    local entry=offlineBeforeHooks[token]
    if type(entry)=="table" and target[key]==entry.wrapper then entry.callback=fn; return end
    local original=target[key]; local unpackFn=unpack or table.unpack
    entry={callback=fn}
    local function pack(...) return {n=select("#",...),...} end
    entry.wrapper=function(...)
        local cur=_G.MerchantMasterAnalytics and _G.MerchantMasterAnalytics.Capture
        if cur and ready() and not hasSecret(...) then safeCall("CAPTURE",entry.callback,...) end
        local result=pack(original(...)); return unpackFn(result,1,result.n)
    end
    target[key]=entry.wrapper
    offlineBeforeHooks[token]=entry
end
local function installMailPreHook(key,dispatchField)
    -- In live WoW use taint-safe hooksecurefunc backed by mailCache + lastMoney; fall back only in offline tests.
    if type(_G[key])~="function" then return end
    if _G.hooksecurefunc then
        hook(_G,key,"MAIL",function(...)
            local cur=_G.MerchantMasterAnalytics and _G.MerchantMasterAnalytics.Capture
            local fn=cur and cur[dispatchField]
            local before=lastMoney or money()
            if fn then
                if dispatchField=="_preTakeMail" then
                    local idx,subIdx=...
                    fn(idx,subIdx,before)
                else
                    fn(...)
                end
            end
            local attempt=dispatchField=="_preTakeMail" and cur and cur._sellerMailAttempt
            if cur and cur._confirmMail then safeCall("MAIL",cur._confirmMail,attempt,before) end
            lastMoney=money()
        end)
        return
    end
    if offlineMailHooks[key]==_G[key] then return end
    local original=_G[key]
    local function pack(...) return {n=select("#",...),...} end
    local wrapper=function(...)
        local cur=_G.MerchantMasterAnalytics and _G.MerchantMasterAnalytics.Capture
        local fn=cur and cur[dispatchField]
        local before=money()
        if fn then fn(...) end
        local attempt=dispatchField=="_preTakeMail" and cur and cur._sellerMailAttempt
        local res=pack(original(...))
        if cur and cur._confirmMail then safeCall("MAIL",cur._confirmMail,attempt,before) end
        lastMoney=money()
        return unpack(res,1,res.n)
    end
    _G[key]=wrapper
    offlineMailHooks[key]=wrapper
end
local function append(typ,id,qty,unit,total,where,extra,ref)
    if Store.IsDisabled(typ) then return end
    return Store.Append({type=typ,itemID=id or 0,qty=qty or 0,unit=unit or 0,total=total or 0,where=where or zone(),extra=extra or {},ref=ref})
end
local function bindPostAuctionID(p,aid)
    if not p or not aid or p.auctionID then return end
    p.auctionID=aid
    if p.row then
        p.row.extra=p.row.extra or {}; p.row.extra.auctionID=aid
        if p.row._lot then p.row._lot.auctionID=aid end
    end
end
local function confirmPost(unconfirmed,auctionID)
    local p=pendingPost
    if not p then
        if auctionID and lastConfirmedPost and nowSec()-lastConfirmedPost.at<=30 then bindPostAuctionID(lastConfirmedPost,auctionID) end
        return
    end
    pendingPost=nil; lastConfirmedPost=p
    local delta=math.max(0,p.beforeMoney-money()); local deposit=p.deposit
    if delta>0 then deposit=delta end
    p.auctionID=auctionID or p.auctionID
    p.row=append("AH_POST",p.itemID,p.qty,p.unit,-(deposit or 0),"Auction House",{name=p.name,variant=p.variant,baseName=p.baseName,auctionID=p.auctionID,unconfirmed=unconfirmed and 1 or nil})
end
local function isPendingPostAwaitingConfirm(p)
    if not p then return false end
    if p.needsConfirmation or p.unverified then return true end
    local h=H(); local of=h and h.app and h.app.orderFlow
    local sl=of and of.GetState and of.GetState().stages.sell
    if sl and sl.pendingPost and sl.pendingPost.state=="awaiting_confirm" then return true end
    return false
end
local function queuePost(commodity,needsConfirmation,loc,duration,qty,bid,buyout)
    if loc==nil then return end
    local id=locationID(loc); if not id then return end
    qty=tonumber(qty) or 1
    local unit=commodity and (tonumber(bid) or 0) or math.floor((tonumber(buyout) or tonumber(bid) or 0)/math.max(1,qty)+0.5)
    local ah=_G.C_AuctionHouse
    -- Under live hooksecurefunc (needsConfirmation == nil), Blizzard does not expose the return value
    -- of PostItem/PostCommodity; keep such posts unverified until AUCTION_HOUSE_AUCTION_CREATED,
    -- matching OWNED_AUCTIONS_UPDATED, or ConfirmPost* proves creation.
    local awaitConfirm=(needsConfirmation==true)
    local unverified=(needsConfirmation==nil) or awaitConfirm
    if pendingPost and pendingPost.itemID==id and pendingPost.qty==qty and pendingPost.unit==unit and nowSec()-pendingPost.at<30 then
        if awaitConfirm then pendingPost.needsConfirmation=true; pendingPost.unverified=true end
        return
    end
    if pendingPost then
        if isPendingPostAwaitingConfirm(pendingPost) then pendingPost=nil else confirmPost(true) end
    end
    local deposit
    local calc=commodity and ah.CalculateCommodityDeposit or ah.CalculateItemDeposit
    if calc then local ok,d=pcall(calc,commodity and id or loc,duration,qty); if ok and not hasSecret(d) then deposit=tonumber(d) end end
    local baseName=Model.ItemName(id)
    local hasRealBase=type(baseName)=="string" and baseName~="" and not baseName:match("^Item%s+#?%d+$")
    local fullName=locationItemName(loc)
    local postName=(fullName and fullName~="") and fullName or baseName
    local variant=(hasRealBase and fullName and fullName~="" and fullName~=baseName) and fullName or nil
    local lotBase=variant and baseName or nil
    if Store.IndexItemName then
        if postName and postName~="" then Store.IndexItemName(postName,id) end
        if hasRealBase then Store.IndexItemName(baseName,id) end
    end
    local p={itemID=id,qty=qty,unit=unit,deposit=deposit or 0,beforeMoney=lastMoney or money(),at=nowSec(),name=postName,variant=variant,baseName=lotBase,ownedCount=ah.GetNumOwnedAuctions and ah.GetNumOwnedAuctions(),needsConfirmation=awaitConfirm,unverified=unverified}
    pendingPost=p
    after(30,function()
        if ready() and pendingPost==p then
            if isPendingPostAwaitingConfirm(p) then pendingPost=nil
            else safeCall("AH_POST",confirmPost,true) end
        end
    end)
end
local function ownedAuction(id)
    local ah=_G.C_AuctionHouse; if not ah then return end
    if ah.GetAuctionInfoByID then local info=ah.GetAuctionInfoByID(id); if safeTable(info) then return info end end
    if ah.GetOwnedAuctionInfo then
        if ah.GetNumOwnedAuctions then
            local count=ah.GetNumOwnedAuctions(); if hasSecret(count) then return end
            for i=1,(tonumber(count) or 0) do local info=ah.GetOwnedAuctionInfo(i); if safeTable(info) and not hasSecret(info.auctionID) and info.auctionID==id then return info end end
        end
        local ok,info=pcall(ah.GetOwnedAuctionInfo,id); if ok and safeTable(info) and (not info.auctionID or info.auctionID==id) then return info end
    end
end
local function auctionItem(info)
    if not safeTable(info) or hasSecret(info.itemID,info.itemLink,info.itemKey) then return nil end
    local key=safeTable(info.itemKey) and info.itemKey or nil
    if key and hasSecret(key.itemID) then return nil end
    return info.itemID or (key and key.itemID) or itemID(info.itemLink)
end

local function parseSoldSubject(subject)
    if type(subject)~="string" or subject=="" then return nil,nil end
    local body
    if _G.AUCTION_SOLD_MAIL_SUBJECT then
        local prefix=_G.AUCTION_SOLD_MAIL_SUBJECT:match("^(.-)%%s")
        if prefix and prefix~="" and subject:sub(1,#prefix)==prefix then body=subject:sub(#prefix+1) end
    end
    if not body then body=subject:match("^[Aa]uction successful:%s*(.+)$") end
    if not body or body=="" then return nil,nil end
    local itemNm,qtyStr=body:match("^(.-)%s*%((%d+)%)%s*$")
    if itemNm and itemNm~="" then return itemNm,tonumber(qtyStr) or 1 end
    return body:gsub("%s+$",""),1
end
local function readMail(index,subIndex,identityOnly)
    if not _G.GetInboxHeaderInfo then return end
    local pkgIcon,stationeryIcon,sender,subject,copper,cod,daysLeft,hasItem,wasRead,wasReturned,textCreated,canReply,isGM=_G.GetInboxHeaderInfo(index)
    if hasSecret(pkgIcon,stationeryIcon,sender,subject,copper,cod,daysLeft,hasItem,wasRead,wasReturned,textCreated,canReply,isGM) or subject==nil or subject==_G.RETRIEVING_DATA then return end
    local m={items={},names={},itemIDs={},sender=sender,subject=subject,money=copper,cod=cod,daysLeft=daysLeft,hasItem=hasItem,wasRead=wasRead,pkgIcon=pkgIcon,stationeryIcon=stationeryIcon}
    if _G.GetInboxInvoiceInfo then
        local typ,name,player,bid,buyout,deposit,fee,delay,hour,minute,count,commerce=_G.GetInboxInvoiceInfo(index)
        if hasSecret(typ,name,player,bid,buyout,deposit,fee,delay,hour,minute,count,commerce) then return end
        m.invoiceType=typ; m.itemName=name; m.player=player; m.bid=bid; m.buyout=buyout; m.deposit=deposit; m.fee=fee; m.count=count; m.delay=delay; m.hour=hour; m.minute=minute; m.commerce=commerce
    end
    if (not m.invoiceType or m.invoiceType=="") and (tonumber(copper) or 0)>0 then
        local soldName,soldQty=parseSoldSubject(subject)
        if soldName then
            m.invoiceType="seller"; m.itemName=soldName; m.count=soldQty
        end
    end
    if _G.GetInboxItem and not (identityOnly and (m.invoiceType=="seller" or m.invoiceType=="seller_temp_invoice")) then
        local maxAtt=tonumber(_G.ATTACHMENTS_MAX_RECEIVE) or 12
        local firstNm,firstID,totalAttQty=nil,nil,0
        if subIndex and tonumber(subIndex) then
            local nm,id,_,cnt=_G.GetInboxItem(index,tonumber(subIndex))
            local lnk=_G.GetInboxItemLink and _G.GetInboxItemLink(index,tonumber(subIndex))
            if hasSecret(nm,id,cnt,lnk) then return end
            firstNm=nm; firstID=tonumber(id) or itemID(lnk); totalAttQty=tonumber(cnt) or 0
        else
            local declared=tonumber(hasItem)
            local loaded=0
            for slot=1,maxAtt do
                local nm,id,_,cnt=_G.GetInboxItem(index,slot)
                local lnk=_G.GetInboxItemLink and _G.GetInboxItemLink(index,slot)
                if hasSecret(nm,id,cnt,lnk) then return end
                local sid=tonumber(id) or itemID(lnk)
                if nm or (sid and (hasItem==true or (tonumber(hasItem) or 0)>0)) then
                    if not sid or not nm or nm==_G.RETRIEVING_DATA then return end
                    loaded=loaded+1
                    local quantity=tonumber(cnt) or 1
                    m.items[sid]=(m.items[sid] or 0)+quantity
                    m.names[nm]=(m.names[nm] or 0)+quantity; m.itemIDs[nm]=sid
                    if not firstNm then firstNm=nm; firstID=sid end
                    if (firstID and sid==firstID) or (not firstID and nm==firstNm) then
                        totalAttQty=totalAttQty+(tonumber(cnt) or 1)
                    end
                end
            end
            if (declared and loaded~=declared) or (hasItem==true and loaded==0) then return end
        end
        if not subIndex and hasItem==true and not firstNm and not firstID then return end
        if firstNm or firstID then
            m.attachedName=firstNm; m.attachedID=firstID; m.attachedCount=totalAttQty>0 and totalAttQty or 1
        end
    end
    if _G.GetInboxText then local text=_G.GetInboxText(index); if not hasSecret(text) then m.text=text end end
    return m
end
local function mailSlotSig(char,m)
    local fields={char,m.sender or "",m.subject or "",m.invoiceType or "",m.itemName or m.attachedName or "",m.player or "",m.bid or "",m.buyout or "",m.deposit or "",m.fee or "",m.count or m.attachedCount or "",m.money or "",m.daysLeft or "",tostring(m.wasRead or ""),m.hour or "",m.minute or "",m.delay or "",m.text or ""}
    local out={}; for i,v in ipairs(fields) do v=tostring(v); out[i]=#v..":"..v end
    return table.concat(out,"|")
end
local function mailFingerprint(char,m,occ)
    -- Length prefixes avoid collisions when localized names contain separators.
    -- Exclude m.money and async-streamed m.player for invoices so looting cash (money -> 0) or buyer-name arrival keeps the same identity.
    local isInv=(m.invoiceType=="seller" or m.invoiceType=="seller_temp_invoice")
    local moneyKey=isInv and "" or (m.money or "")
    local playerKey=isInv and "" or (m.player or "")
    local fields={char,m.sender or "",m.subject or "",m.invoiceType or "",m.itemName or m.attachedName or "",playerKey,m.bid or "",m.buyout or "",m.deposit or "",m.fee or "",m.count or m.attachedCount or "",moneyKey,m.text or ""}
    local out={}; for i,v in ipairs(fields) do v=tostring(v); out[i]=#v..":"..v end
    if occ and occ>1 then out[#out+1]="occ:"..occ end
    return table.concat(out,"|")
end
local function mailCollectable(m)
    if not m then return false end
    local typ=m.invoiceType
    if typ=="seller" or typ=="seller_temp_invoice" then
        return (tonumber(m.money) or 0)>0
    end
    local subject=string.lower(m.subject or ""); local expired=subject:find("expir",1,true)~=nil
    if _G.AUCTION_EXPIRED_MAIL_SUBJECT then
        local prefix=string.lower(_G.AUCTION_EXPIRED_MAIL_SUBJECT):match("^(.-)%%s") or string.lower(_G.AUCTION_EXPIRED_MAIL_SUBJECT)
        if prefix~="" and subject:find(prefix,1,true) then expired=true end
    end
    local canceled=subject:find("cancel",1,true)~=nil
    if expired or canceled then
        return (tonumber(m.hasItem) or 0)>0 or m.hasItem==true or m.attachedID~=nil or m.attachedName~=nil
    end
    return false
end
local function mailEmptyShell(m)
    if not m then return false end
    local typ=m.invoiceType
    if (typ=="seller" or typ=="seller_temp_invoice") and (tonumber(m.money) or 0)<=0 then return true end
    local subject=string.lower(m.subject or ""); local expired=subject:find("expir",1,true)~=nil
    if _G.AUCTION_EXPIRED_MAIL_SUBJECT then
        local prefix=string.lower(_G.AUCTION_EXPIRED_MAIL_SUBJECT):match("^(.-)%%s") or string.lower(_G.AUCTION_EXPIRED_MAIL_SUBJECT)
        if prefix~="" and subject:find(prefix,1,true) then expired=true end
    end
    local canceled=subject:find("cancel",1,true)~=nil
    if (expired or canceled) and not ((tonumber(m.hasItem) or 0)>0 or m.hasItem==true or m.attachedID~=nil or m.attachedName~=nil) then return true end
    return false
end
local function pruneSeenMail(seen,now)
    for k,v in pairs(seen) do
        if type(v)=="table" then if (tonumber(v.exp) or 0)<=now then seen[k]=nil end
        elseif (tonumber(v) or 0)<=now then seen[k]=nil end
    end
end
local function countIdenticalSlots(char,baseFp,totalCount)
    local unconsumed,consumed=0,0
    for i=1,totalCount do
        local m=mailCache[i] or readMail(i)
        if m and (m.baseFp or mailFingerprint(char,m,1))==baseFp then
            if m.consumed then consumed=consumed+1
            elseif mailCollectable(m) then unconsumed=unconsumed+1 end
        end
    end
    return unconsumed,consumed
end
local function scanSeenForBase(seen,baseFp,now)
    local pendingForBase,maxOcc,settledShells=0,0,0
    for fpKey,entry in pairs(seen) do
        if type(entry)=="table" then
            if entry.base==baseFp and (tonumber(entry.exp) or 0)>now then
                local occ=tonumber(entry.ord) or tonumber(type(fpKey)=="string" and fpKey:match("|occ:(%d+)$")) or 1
                if occ>maxOcc then maxOcc=occ end
                if not entry.gone then pendingForBase=pendingForBase+1
                elseif entry.shell then settledShells=settledShells+1 end
            end
        elseif type(fpKey)=="string" and (tonumber(entry) or 0)>now then
            if fpKey==baseFp then
                if maxOcc<1 then maxOcc=1 end
                pendingForBase=pendingForBase+1
            elseif fpKey:sub(1,#baseFp+5)==baseFp.."|occ:" then
                local occ=tonumber(fpKey:sub(#baseFp+6))
                if occ then
                    if occ>maxOcc then maxOcc=occ end
                    pendingForBase=pendingForBase+1
                end
            end
        end
    end
    return pendingForBase,maxOcc,settledShells
end
local cacheMail
local lastDeletedMailIndex
function Capture.InspectAndRecordMail(index,subIndex,collectedDelta)
    Capture._standaloneMailAction=true
    if not ready() or hasSecret(index,subIndex) or not tonumber(index) then return end
    index=tonumber(index)
    local totalCount=0; if _G.GetInboxNumItems then totalCount=_G.GetInboxNumItems() end
    if hasSecret(totalCount) then return end
    totalCount=tonumber(totalCount) or 0
    local char=Store.CurrentCharAndEcon(); local now=nowSec()
    if Capture._mailObservedEmpty then
        for _,entry in pairs(db().seenMail or {}) do if type(entry)=="table" then entry.gone=true; entry.shell=nil end end
        mailCache={}; Capture._mailCachedCount=0; Capture._mailObservedEmpty=nil
    end
    local previous=mailCache[index]
    if cacheMail and (not Capture._mailCachedCount or totalCount~=Capture._mailCachedCount or (previous and previous.consumed)) then
        -- Seller identity reconciliation needs invoices only; attachment ownership stays deferred.
        cacheMail(true)
    end
    local live=readMail(index,subIndex)
    local cached=mailCache[index]
    -- Under taint-safe hooksecurefunc, TakeInboxMoney may zero live.money in C before our post-hook runs.
    -- Recover the exact invoice payout when live still carries the seller invoice and player money rose by it.
    if live and (live.invoiceType=="seller" or live.invoiceType=="seller_temp_invoice") and (tonumber(live.money) or 0)<=0 and (tonumber(collectedDelta) or 0)>0 then
        local gross=tonumber(live.bid) or tonumber(live.buyout) or 0
        local fee=tonumber(live.fee) or 0
        local dep=tonumber(live.deposit) or 0
        local expectedCash=(gross>0) and math.max(0,gross-fee+dep) or 0
        if expectedCash>0 and collectedDelta>=expectedCash then
            live.money=expectedCash
        elseif cached and (tonumber(cached.money) or 0)>0 and collectedDelta>=(tonumber(cached.money) or 0) then
            live.money=tonumber(cached.money)
        end
    end
    local m
    if live and mailCollectable(live) then
        live.baseFp=mailFingerprint(char,live,1); live.slotSig=mailSlotSig(char,live)
        if cached and cached.baseFp==live.baseFp then
            if cached.consumed or cached.pendingCash then return end
            -- Refresh dynamic fields (such as async-streamed buyer name or attachments) from live slot before recording.
            cached.player=(live.player and live.player~="") and live.player or cached.player
            cached.itemName=live.itemName or cached.itemName
            cached.attachedID=live.attachedID or cached.attachedID
            cached.attachedName=live.attachedName or cached.attachedName
            cached.attachedCount=live.attachedCount or cached.attachedCount
            cached.money=(live.money and live.money>0) and live.money or cached.money
            cached.slotSig=live.slotSig
            m=cached
        else
            -- Cached slot belonged to a previously deleted mail before inbox indices shifted; use live mail!
            m=live; mailCache[index]=live
        end
    elseif cached and not cached.consumed and mailCollectable(cached) then
        if cached.pendingCash then return end
        if live and live.player and live.player~="" then cached.player=live.player end
        m=cached
    else
        return
    end
    local baseFp=m.baseFp or mailFingerprint(char,m,1); m.baseFp=baseFp
    local seen=db().seenMail
    local inInbox,consumedInCache=countIdenticalSlots(char,baseFp,math.max(totalCount,index))
    local pendingForBase,maxOcc=scanSeenForBase(seen,baseFp,now)
    for _,p in ipairs(pendingSellerMail) do if p.base==baseFp then maxOcc=math.max(maxOcc,p.ord) end end
    local priorSessionPending=math.max(0,pendingForBase-consumedInCache)
    if inInbox<=priorSessionPending then return end
    local fp=mailFingerprint(char,m,maxOcc+1)
    local typ=m.invoiceType
    if typ=="seller" or typ=="seller_temp_invoice" then
        local cash=tonumber(m.money) or 0; if cash<=0 then return end
        local qty=tonumber(m.count) or 1; local dep=tonumber(m.deposit) or 0; local fee=tonumber(m.fee) or 0
        local gross=tonumber(m.bid) or tonumber(m.buyout)
        if not gross or gross<=0 then
            if fee>0 or dep>0 then gross=cash+fee-dep
            else gross=math.floor(cash/0.95+0.5); fee=math.max(0,gross-cash) end
        end
        local id=Store.ResolveItemIDByName(char,m.itemName)
        local saleAt=liveSoldNoticeTime[m.itemName] or math.floor(now-math.max(0,30-(tonumber(m.daysLeft) or 30))*86400)
        local buyer=(m.player and m.player~="") and m.player or nil
        local baseName=(id and id>0 and Model and Model.ItemName) and Model.ItemName(id) or nil
        local variant=(type(m.itemName)=="string" and m.itemName~="" and id and id>0 and m.itemName:find("%s+of%s+") and m.itemName~=baseName) and m.itemName or nil
        m.pendingCash=true; mailCache[index]=m
        pendingSellerMail[#pendingSellerMail+1]={m=m,index=index,fp=fp,base=baseFp,ord=maxOcc+1,batchCount=inInbox+consumedInCache,cashSlots=inInbox+consumedInCache,at=now,before=money(),
            id=id,qty=qty,unit=math.floor(gross/math.max(1,qty)+0.5),cash=cash,extra={gross=gross,fee=fee,depositReturned=dep,saleAt=saleAt,buyer=buyer,name=m.itemName,variant=variant}}
    else
        local id=tonumber(m.attachedID) or Store.ResolveItemIDByName(char,m.attachedName)
        local subj=string.lower(m.subject or ""); local cancel=subj:find("cancel",1,true)~=nil
        local lots=Store.Lots(char,id); local matched=lots and #lots>0
        local row
        if cancel then if matched then row=append("AH_CANCEL",id,tonumber(m.attachedCount) or 1,0,0,"Auction House",{name=m.attachedName,mailFallback=true}) else return end
        else row=append("AH_EXPIRE",id,tonumber(m.attachedCount) or 1,0,0,"Auction House",{name=m.attachedName,mailFallback=true}) end
        if row then m.consumed=true; m.consumedOrder=(Capture._mailConsumedSeq or 0)+1; Capture._mailConsumedSeq=m.consumedOrder; m.slotSig=m.slotSig or mailSlotSig(char,m); seen[fp]={exp=now+31*86400,base=baseFp,ord=maxOcc+1,batchCount=inInbox+consumedInCache}; m.fingerprint=fp; mailCache[index]=m end
    end
end
local function sellerMailCleared(p)
    local char=Store.CurrentCharAndEcon()
    local live=readMail(p.index)
    if live and mailFingerprint(char,live,1)==p.base and (tonumber(live.money) or 0)<=0 then return true end
    local count=_G.GetInboxNumItems and _G.GetInboxNumItems()
    if hasSecret(count) or not tonumber(count) then return false end
    local cashSlots=0
    for index=1,tonumber(count) do
        local m=readMail(index)
        if not m then return false end
        if mailFingerprint(char,m,1)==p.base and mailCollectable(m) then cashSlots=cashSlots+1 end
    end
    return cashSlots<p.cashSlots
end
local function confirmSellerMail(direct,beforeCall)
    local current=money()
    local i=1
    while i<=#pendingSellerMail do
        local p=pendingSellerMail[i]
        local baseline=p==direct and beforeCall or p.before
        local collected=p==direct and current-beforeCall>=p.cash
        if nowSec()-p.at>30 then p.m.pendingCash=nil; table.remove(pendingSellerMail,i)
        elseif current-baseline<p.cash or (not collected and not sellerMailCleared(p)) then i=i+1
        else
            table.remove(pendingSellerMail,i); p.m.pendingCash=nil
            for _,other in ipairs(pendingSellerMail) do
                other.before=math.max(other.before,baseline+p.cash)
                if other.base==p.base then other.cashSlots=math.max(0,other.cashSlots-1) end
            end
            local row=append("AH_SELL",p.id,p.qty,p.unit,p.cash,"Auction House",p.extra)
            if row then
                local m=p.m; m.consumed=true; m.consumedOrder=(Capture._mailConsumedSeq or 0)+1; Capture._mailConsumedSeq=m.consumedOrder
                m.fingerprint=p.fp
                db().seenMail[p.fp]={exp=nowSec()+31*86400,base=p.base,ord=p.ord,batchCount=p.batchCount}
            end
        end
    end
end
local function stageIncomingMail(index,subIndex,beforeMoney)
    local live=readMail(index,subIndex)
    local cached=mailCache[tonumber(index)]
    local m=live
    if not m or (m.invoiceType~="buyer" and (tonumber(m.money) or 0)<=0 and (tonumber(m.cod) or 0)<=0 and (tonumber(m.attachedID) or 0)<=0 and cached and ((tonumber(cached.money) or 0)>0 or (tonumber(cached.cod) or 0)>0 or cached.invoiceType=="buyer")) then
        m=cached or live
    end
    if not m then return end
    if m.invoiceType=="seller" or m.invoiceType=="seller_temp_invoice" then return end
    local id=tonumber(m.attachedID) or Store.ResolveItemIDByName(Store.CurrentCharAndEcon(),m.attachedName or m.itemName)
    local isBuyer=m.invoiceType=="buyer"
    if isBuyer and id and id>0 then
        local qty=tonumber(m.count) or tonumber(m.attachedCount) or 1
        local amount=tonumber(m.bid) or tonumber(m.buyout) or 0
        local now=nowSec()
        local idxNum=tonumber(index) or 0
        local inboxNum=_G.GetInboxNumItems and _G.GetInboxNumItems()
        inboxNum=(not hasSecret(inboxNum) and tonumber(inboxNum)) or 0
        -- Build stable instance key excluding mutable wasRead/daysLeft so retries of the same slot dedupe cleanly.
        local stableSig=table.concat({tostring(m.sender or ""),tostring(m.subject or ""),tostring(id),tostring(qty),tostring(amount),tostring(m.player or "")},"|")
        local instanceKey=tostring(idxNum)..":"..tostring(inboxNum)..":"..stableSig
        local bi=1
        while bi<=#pendingBuyerInvoices do
            if now-(pendingBuyerInvoices[bi].at or 0)>30 then table.remove(pendingBuyerInvoices,bi) else bi=bi+1 end
        end
        for _,existing in ipairs(pendingBuyerInvoices) do
            if existing.instanceKey==instanceKey and now-(existing.at or 0)<=15 then return end
        end
        ws3.buyerInvoiceSeq=(ws3.buyerInvoiceSeq or 0)+1
        pendingBuyerInvoices[#pendingBuyerInvoices+1]={
            seq=ws3.buyerInvoiceSeq, instanceKey=instanceKey, index=idxNum,
            id=id, qty=qty, amount=amount, seller=m.player, before=itemCount(id), at=now,
        }
        while #pendingBuyerInvoices>32 do table.remove(pendingBuyerInvoices,1) end
        return
    end
    local moneyValue=tonumber(m.money) or 0; local cod=tonumber(m.cod) or 0
    if moneyValue<=0 and cod<=0 then return end
    local now=nowSec(); local q=ws3.pendingMailTakeQueue
    local qi=1
    while qi<=#q do if now-(q[qi].at or 0)>15 then table.remove(q,qi) else qi=qi+1 end end
    local idxNum=tonumber(index)
    local prev=q[#q]
    local same=prev and prev.index==idxNum and prev.sender==m.sender and prev.subject==m.subject and prev.id==id and prev.money==moneyValue and prev.cod==cod and now-prev.at<15
    local entry={index=idxNum,sender=m.sender,subject=m.subject,id=id,qty=tonumber(m.attachedCount) or tonumber(m.count) or 1,cod=cod,money=moneyValue,before=same and prev.before or (beforeMoney or money()),beforeItems=same and prev.beforeItems or (id and itemCount(id) or 0),invoiceType=m.invoiceType,at=same and prev.at or now}
    if same then q[#q]=entry
    else
        q[#q+1]=entry
        while #q>ws3.maxPendingMailTake do table.remove(q,1) end
    end
    pendingMailTake=q[#q]
end
local function confirmBuyerInvoices()
    local now=nowSec()
    local idx=1
    while idx<=#pendingBuyerInvoices do
        local p=pendingBuyerInvoices[idx]
        if not p or now-(p.at or 0)>30 then
            table.remove(pendingBuyerInvoices,idx)
        else
            local gained=math.max(0,itemCount(p.id)-(p.before or 0))
            if gained>=p.qty then
                table.remove(pendingBuyerInvoices,idx)
                for _,other in ipairs(pendingBuyerInvoices) do
                    if other.id==p.id then
                        other.before=math.max(other.before or 0,(p.before or 0)+p.qty)
                    end
                end
                local char=Store.CurrentCharAndEcon(); local found
                for dayKey,day in pairs(Store.db.days or {}) do
                    local rows=day.r or (day.s and Store.UnpackDayString(day.s)) or {}
                    for _,row in ipairs(rows) do
                        if row.char==char and row.type=="AH_BUY" and row.itemID==p.id and row.qty==p.qty and math.abs(math.abs(row.total or 0)-p.amount)<=1 and math.abs((row.time or 0)-p.at)<=86400 and not (row.extra and row.extra.seller) then found={row=row,dayKey=dayKey,packed=day.s~=nil,rows=rows}; break end
                    end
                    if found then break end
                end
                if found then
                    found.row.extra=found.row.extra or {}; found.row.extra.seller=p.seller; found.row.extra.counterparty=p.seller
                    if found.packed then local day=Store.db.days[found.dayKey]; day.s=Store.PackRows(found.rows); day.r=nil end
                    local meta=Store.db.itemStats[found.row.econ] and Store.db.itemStats[found.row.econ][p.id]
                    if meta and meta.lastBuyTs==found.row.time then meta.lastBuyFrom=p.seller end
                else
                    local matchedBid,matchedBidRow
                    for bi=#ws3.recentAHBids,1,-1 do
                        local b=ws3.recentAHBids[bi]
                        if now-(b.at or 0)>172800 then table.remove(ws3.recentAHBids,bi)
                        elseif b.itemID==p.id and b.qty==p.qty and math.abs((b.amount or 0)-p.amount)<=1 then
                            matchedBid=table.remove(ws3.recentAHBids,bi); break
                        end
                    end
                    for dayKey,day in pairs(Store.db.days or {}) do
                        local rows=day.r or (day.s and Store.UnpackDayString(day.s)) or {}
                        for _,row in ipairs(rows) do
                            if row.char==char and row.type=="AH_BID" and row.itemID==p.id and row.qty==p.qty and math.abs(math.abs(row.total or 0)-p.amount)<=1 and math.abs((row.time or 0)-p.at)<=172800 and not (row.extra and row.extra.won) then
                                matchedBidRow={row=row,dayKey=dayKey,packed=day.s~=nil,rows=rows}; break
                            end
                        end
                        if matchedBidRow then break end
                    end
                    if matchedBid or matchedBidRow then
                        local bidAid=matchedBid and matchedBid.auctionID or (matchedBidRow and matchedBidRow.row.extra and matchedBidRow.row.extra.auctionID)
                        if matchedBidRow then
                            matchedBidRow.row.extra=matchedBidRow.row.extra or {}; matchedBidRow.row.extra.won=true
                            if matchedBidRow.packed then local day=Store.db.days[matchedBidRow.dayKey]; day.s=Store.PackRows(matchedBidRow.rows); day.r=nil end
                        end
                        if p.amount>0 then
                            Store.Append({type="AH_BUY",char=char,itemID=p.id,qty=p.qty,unit=math.floor(p.amount/math.max(1,p.qty)+0.5),total=-p.amount,time=p.at,where="Auction House Mail",extra={seller=p.seller,counterparty=p.seller,fromBid=true,auctionID=bidAid},skipRecon=true})
                        end
                    elseif p.amount>0 then
                        Store.Append({type="AH_BUY",char=char,itemID=p.id,qty=p.qty,unit=math.floor(p.amount/math.max(1,p.qty)+0.5),total=-p.amount,time=p.at,where="Auction House Mail",extra={seller=p.seller,counterparty=p.seller,nonCash=true,offlineInvoice=true},skipRecon=true})
                    end
                end
            else
                idx=idx+1
            end
        end
    end
end
local function parseOutbidSubject(subject)
    if type(subject)~="string" or subject=="" then return false,nil end
    local subLow=string.lower(subject)
    local tmpl=_G.AUCTION_OUTBID_MAIL_SUBJECT
    if not hasSecret(tmpl) and type(tmpl)=="string" and tmpl~="" then
        local rawPrefix=tmpl:match("^(.-)%%s") or tmpl
        local lowPrefix=string.lower(rawPrefix):gsub("%s+$","")
        if lowPrefix~="" and subLow:find(lowPrefix,1,true) then
            local tail=subject:sub(#rawPrefix+1):gsub("^%s+",""):gsub("%s+$","")
            return true,(tail~="" and tail or nil)
        end
    end
    local pos=subLow:find("outbid",1,true)
    if pos then
        local tail=subject:match(":%s*(.+)$")
        if tail then tail=tail:gsub("%s+$","") end
        return true,(tail and tail~="" and tail or nil)
    end
    return false,nil
end
local function confirmIncomingMail()
    local q=ws3.pendingMailTakeQueue
    local now=nowSec()
    local i=1
    while i<=#q do
        local p=q[i]
        if not p or now-(p.at or 0)>15 then
            table.remove(q,i)
        else
            local curMoney=money()
            local delta=curMoney-(p.before or curMoney)
            local gained=p.id and math.max(0,itemCount(p.id)-(p.beforeItems or 0)) or 0
            if p.cod>0 and delta<0 and gained>0 then
                table.remove(q,i)
                for _,other in ipairs(q) do
                    other.before=math.min(other.before or curMoney,(p.before or curMoney)-p.cod)
                    if other.id==p.id then other.beforeItems=math.max(other.beforeItems or 0,(p.beforeItems or 0)+gained) end
                end
                append("COD_BUY",p.id,gained,math.floor(p.cod/math.max(1,gained)+0.5),-p.cod,"Mail",{seller=p.sender,counterparty=p.sender})
            elseif p.money>0 and delta>=p.money then
                table.remove(q,i)
                for _,other in ipairs(q) do
                    other.before=math.max(other.before or 0,(p.before or 0)+p.money)
                end
                local isOutbid,outbidName=parseOutbidSubject(p.subject)
                local subj=string.lower(p.subject or "")
                if isOutbid then
                    local oid=outbidName and Store.ResolveItemIDByName(Store.CurrentCharAndEcon(),outbidName) or 0
                    append("AH_OUTBID",oid,1,p.money,p.money,"Auction House",{subject=p.subject,name=outbidName})
                elseif subj:find("cod payment",1,true) or subj:find("cod",1,true) then
                    local expectations=ensureTable(db().stats,"codExpectations"); local matched
                    local buyer=ownAlt(p.sender) or (type(p.sender)=="string" and p.sender:lower())
                    for ei,entry in ipairs(expectations) do if entry.sellerChar==Store.CurrentCharAndEcon() and entry.recipient==buyer and entry.cod==p.money then matched=table.remove(expectations,ei); break end end
                    if matched then
                        local quantity=0; for _,it in ipairs(matched.items) do quantity=quantity+it.qty end
                        local remaining=p.money
                        for mi,it in ipairs(matched.items) do
                            local proceeds=mi==#matched.items and remaining or math.floor(p.money*it.qty/math.max(1,quantity))
                            remaining=remaining-proceeds
                            append("COD_SELL",it.itemID,it.qty,math.floor(proceeds/math.max(1,it.qty)+0.5),proceeds,"Mail",{buyer=p.sender,counterparty=p.sender})
                        end
                    else append("COD_SELL",p.id or 0,p.qty,math.floor(p.money/math.max(1,p.qty)+0.5),p.money,"Mail",{buyer=p.sender,counterparty=p.sender}) end
                else
                    local ownChar=ownAlt(p.sender); local internal=ownChar~=nil
                    append("MONEY_TRANSFER",0,0,0,p.money,"Mail",{counterparty=p.sender,direction="in",internal=internal,pairKey=internal and pairForIncoming(p.sender,p.money) or nil})
                end
            else
                i=i+1
            end
        end
    end
    pendingMailTake=q[#q]
    Capture._pendingMailTake=pendingMailTake
end
Capture._confirmMail=function(attempt,beforeCall) if ready() then confirmSellerMail(attempt,beforeCall); confirmIncomingMail() end end
Capture._preTakeMail=function(index,subIndex,beforeMoney)
    if not ready() or hasSecret(index,subIndex) then return end
    Store.ProbeLog("MAIL","prehook take index="..tostring(index))
    confirmSellerMail()
    Capture._sellerMailAttempt=nil
    local prevMoney=beforeMoney or money()
    local collectedDelta=math.max(0,money()-prevMoney)
    stageIncomingMail(index,subIndex,prevMoney)
    Capture._pendingMailTake=pendingMailTake
    safeCall("MAIL",Capture.InspectAndRecordMail,index,subIndex,collectedDelta)
    for _,p in ipairs(pendingSellerMail) do
        if p.m==mailCache[tonumber(index)] then p.before=prevMoney; Capture._sellerMailAttempt=p; break end
    end
end
Capture._preDeleteMail=function(index)
    Capture._standaloneMailAction=true
    if not ready() or hasSecret(index) then return end
    Store.ProbeLog("MAIL","prehook delete index="..tostring(index))
    -- An already empty invoice is retrieval evidence, even before a deferred open scan.
    local live=readMail(tonumber(index)) or mailCache[tonumber(index)]
    if live and mailEmptyShell(live) then
        local char=Store.CurrentCharAndEcon(); local base=mailFingerprint(char,live,1)
        local oldest
        for _,entry in pairs(db().seenMail or {}) do
            if type(entry)=="table" and entry.base==base and not entry.gone and (not oldest or (entry.ord or 1)<(oldest.ord or 1)) then oldest=entry end
        end
        if oldest then oldest.gone=true; oldest.shell=true end
    end
    safeCall("MAIL",function(idx) lastDeletedMailIndex=tonumber(idx); Capture.InspectAndRecordMail(idx) end,index)
end
cacheMail=function(identityOnly,rejectEmpty)
    if not _G.GetInboxNumItems then return end
    local count,total=_G.GetInboxNumItems()
    if hasSecret(count,total) or count==nil then return end
    count=tonumber(count) or 0
    if count==0 and (rejectEmpty or (tonumber(total) or 0)>0) then return end
    local prevIndices={}
    for idx in pairs(mailCache) do if type(idx)=="number" then prevIndices[#prevIndices+1]=idx end end
    table.sort(prevIndices)
    local prevList={}
    local prevByBase={}
    local prevShells={}
    for _,idx in ipairs(prevIndices) do
        local pm=mailCache[idx]
        if pm then
            pm._prevIdx=idx
            prevList[#prevList+1]=pm
            if pm.baseFp then
                if pm.consumed or mailCollectable(pm) then
                    prevByBase[pm.baseFp]=(prevByBase[pm.baseFp] or 0)+1
                elseif mailEmptyShell(pm) then
                    prevShells[pm.baseFp]=(prevShells[pm.baseFp] or 0)+1
                end
            end
        end
    end
    local new={}; local newList={}; local char=Store.CurrentCharAndEcon(); local now=nowSec()
    local seen=db() and db().seenMail
    local rawTotalIdentical={}
    local newShells={}
    local hasUnreadable=false
    local ownership={names={},items={},itemIDs={}}; local ownershipComplete=true
    for i=1,count do
        local m=readMail(i,nil,identityOnly)
        if not m then
            hasUnreadable=true
            if mailCache[i] then
                -- Preserve previous cached slot state while header/invoice data is temporarily retrieving!
                m=mailCache[i]
                if m.baseFp then
                    if m.consumed or mailCollectable(m) then rawTotalIdentical[m.baseFp]=(rawTotalIdentical[m.baseFp] or 0)+1
                    elseif mailEmptyShell(m) then newShells[m.baseFp]=(newShells[m.baseFp] or 0)+1 end
                end
                new[i]=m; newList[#newList+1]=m
            end
        else
            if (m.hasItem==true or (tonumber(m.hasItem) or 0)>0) and not next(m.items or {}) then ownershipComplete=false end
            for id,qty in pairs(m.items or {}) do ownership.items[id]=(ownership.items[id] or 0)+qty end
            for name,qty in pairs(m.names or {}) do ownership.names[name]=(ownership.names[name] or 0)+qty end
            for name,id in pairs(m.itemIDs or {}) do ownership.itemIDs[name]=id end
            local baseFp=mailFingerprint(char,m,1); m.baseFp=baseFp; m.slotSig=mailSlotSig(char,m)
            if mailCollectable(m) then rawTotalIdentical[baseFp]=(rawTotalIdentical[baseFp] or 0)+1
            elseif mailEmptyShell(m) then newShells[baseFp]=(newShells[baseFp] or 0)+1 end
            new[i]=m; newList[#newList+1]=m
        end
    end
    -- If any inbox slot is temporarily unreadable (`RETRIEVING_DATA` / secret / nil), do not overwrite `mailCache` or retire `seenMail` until headers settle!
    if hasUnreadable then return end
    local P,N=#prevList,#newList
    if P>0 and N>0 then
        local prevConsumedByBase={}
        for _,pm in ipairs(prevList) do
            if pm.consumed and pm.baseFp then
                prevConsumedByBase[pm.baseFp]=prevConsumedByBase[pm.baseFp] or {}
                prevConsumedByBase[pm.baseFp][#prevConsumedByBase[pm.baseFp]+1]=pm
            end
        end
        local settledMask={}
        for baseFp,cList in pairs(prevConsumedByBase) do
            local shellRise=math.max(0,(newShells[baseFp] or 0)-(prevShells[baseFp] or 0))
            local delta=math.max(shellRise,(prevByBase[baseFp] or 0)-(rawTotalIdentical[baseFp] or 0))
            delta=math.min(#cList,delta)
            if delta>0 then
                local marked=0
                -- 0) If a consumed slot turned into an empty shell in-place (money -> 0), mark that exact slot settled!
                if shellRise>0 then
                    for _,pm in ipairs(cList) do
                        local curAtIdx=new[pm._prevIdx]
                        if marked<delta and curAtIdx and curAtIdx.baseFp==baseFp and mailEmptyShell(curAtIdx) then
                            settledMask[pm]=true; marked=marked+1
                        end
                    end
                end
                -- 1) Next check if any consumed slot's fine-grained `slotSig` disappeared from `newList`!
                local newSigCounts={}
                for _,nm in ipairs(newList) do if nm.baseFp==baseFp and mailCollectable(nm) then newSigCounts[nm.slotSig]=(newSigCounts[nm.slotSig] or 0)+1 end end
                local prevUnconsumedSigs={}
                for _,pm in ipairs(prevList) do if not pm.consumed and pm.baseFp==baseFp and mailCollectable(pm) then prevUnconsumedSigs[pm.slotSig]=(prevUnconsumedSigs[pm.slotSig] or 0)+1 end end
                local availForConsumed={}
                for sig,cnt in pairs(newSigCounts) do availForConsumed[sig]=math.max(0,cnt-(prevUnconsumedSigs[sig] or 0)) end
                local distinctSigs=false
                local firstSig=cList[1] and cList[1].slotSig
                for k=2,#cList do if cList[k].slotSig~=firstSig then distinctSigs=true; break end end
                if distinctSigs then
                    for _,pm in ipairs(cList) do
                        if marked<delta and not settledMask[pm] and (availForConsumed[pm.slotSig] or 0)<=0 then
                            settledMask[pm]=true; marked=marked+1
                        elseif not settledMask[pm] and (availForConsumed[pm.slotSig] or 0)>0 then
                            availForConsumed[pm.slotSig]=availForConsumed[pm.slotSig]-1
                        end
                    end
                end
                -- 2) If all identical mails share identical `slotSig`, check `lastDeletedMailIndex`, else FIFO `consumedOrder` (earliest action settles first)!
                if marked<delta and lastDeletedMailIndex then
                    for _,pm in ipairs(cList) do
                        if marked<delta and not settledMask[pm] and pm._prevIdx==lastDeletedMailIndex then
                            settledMask[pm]=true; marked=marked+1
                        end
                    end
                end
                if marked<delta then
                    local ordered={}; for k,v in ipairs(cList) do ordered[k]=v end
                    table.sort(ordered,function(a,b) return (a.consumedOrder or 0)<(b.consumedOrder or 0) end)
                    for _,pm in ipairs(ordered) do
                        if marked<delta and not settledMask[pm] then settledMask[pm]=true; marked=marked+1 end
                    end
                end
            end
        end
        -- Filter out settled consumed slots from `prevSurvivors`, then align `prevSurvivors` 1-to-1 per `baseFp` with `newList`!
        local survivorsByBase={}
        for _,pm in ipairs(prevList) do
            if pm.baseFp and (pm.consumed or mailCollectable(pm)) and not settledMask[pm] then
                survivorsByBase[pm.baseFp]=survivorsByBase[pm.baseFp] or {}
                survivorsByBase[pm.baseFp][#survivorsByBase[pm.baseFp]+1]=pm
            end
        end
        for baseFp,surv in pairs(survivorsByBase) do
            local targets={}
            for _,nm in ipairs(newList) do if nm.baseFp==baseFp and mailCollectable(nm) then targets[#targets+1]=nm end end
            -- Exact order-preserving alignment (preferring matching `slotSig` when distinct, otherwise 1-to-1 positional among survivors!)
            local S,T=#surv,#targets
            if S==1 and T==1 then
                local pm,nm=surv[1],targets[1]
                if pm.consumed then nm.consumed=true; nm.fingerprint=pm.fingerprint; nm.consumedOrder=pm.consumedOrder end
                if pm.pendingCash then
                    nm.pendingCash=true
                    for _,p in ipairs(pendingSellerMail) do if p.m==pm then p.m=nm end end
                end
            elseif S>0 and T>0 then
                local stride=T+2
                local dp={}
                for i=0,(S+2)*stride-1 do dp[i+1]=0 end
                for i=S,1,-1 do
                    for j=T,1,-1 do
                        local at=i*stride+j+1
                        local best=math.max(dp[at+stride],dp[at+1])
                        local score=(surv[i].slotSig==targets[j].slotSig and 1001 or 1000)+dp[at+stride+1]
                        if score>best then best=score end
                        dp[at]=best
                    end
                end
                local i,j=1,1
                while i<=S and j<=T do
                    local at=i*stride+j+1
                    local score=(surv[i].slotSig==targets[j].slotSig and 1001 or 1000)+dp[at+stride+1]
                    if dp[at]==score then
                        if surv[i].consumed then targets[j].consumed=true; targets[j].fingerprint=surv[i].fingerprint; targets[j].consumedOrder=surv[i].consumedOrder end
                        if surv[i].pendingCash then
                            targets[j].pendingCash=true
                            for _,p in ipairs(pendingSellerMail) do if p.m==surv[i] then p.m=targets[j] end end
                        end
                        i=i+1; j=j+1
                    elseif dp[at+stride]>=dp[at+1] then i=i+1 else j=j+1 end
                end
            end
        end
    end
    lastDeletedMailIndex=nil
    if seen then
        local activeConsumedFp={}
        for i=1,count do
            local m=new[i]
            if m and m.consumed and m.fingerprint then activeConsumedFp[m.fingerprint]=true end
        end
        local pendingByBase={}
        local shellGoneByBase={}
        for fpKey,entry in pairs(seen) do
            if type(entry)=="table" and (entry.exp or 0)>now and entry.base then
                if not entry.gone then
                    pendingByBase[entry.base]=pendingByBase[entry.base] or {}
                    pendingByBase[entry.base][#pendingByBase[entry.base]+1]={key=fpKey,entry=entry}
                elseif entry.shell then
                    shellGoneByBase[entry.base]=shellGoneByBase[entry.base] or {}
                    shellGoneByBase[entry.base][#shellGoneByBase[entry.base]+1]=entry
                end
            end
        end
        -- If empty shells themselves were later deleted (`shells < #shellGone`), clear excess `.shell` flags so future shells aren't undercounted!
        for baseFp,sList in pairs(shellGoneByBase) do
            local curShells=newShells[baseFp] or 0
            for idx=curShells+1,#sList do sList[idx].shell=nil end
        end
        for baseFp,list in pairs(pendingByBase) do
            table.sort(list,function(a,b) return (a.entry.ord or 0)<(b.entry.ord or 0) end)
            local raw=rawTotalIdentical[baseFp] or 0
            local shells=newShells[baseFp] or 0
            local priorShellGone=math.min(shells,#(shellGoneByBase[baseFp] or {}))
            local maxBatch=0
            for _,item in ipairs(list) do maxBatch=math.max(maxBatch,item.entry.batchCount or item.entry.initCount or 1) end
            -- Every new empty shell (`shells - priorShellGone`) or batch drop (`maxBatch - raw`) settles pending entries in the current batch!
            local newShellSettled=math.max(0,shells-priorShellGone)
            local batchSettled=math.max(newShellSettled,math.max(0,maxBatch-raw))
            local targetPending=math.min(raw,math.max(0,#list-batchSettled))
            local toRetire=math.max(0,#list-targetPending)
            local markShellLeft=newShellSettled
            for _,item in ipairs(list) do
                if toRetire<=0 then break end
                if not activeConsumedFp[item.key] then
                    item.entry.gone=true
                    if markShellLeft>0 then item.entry.shell=true; markShellLeft=markShellLeft-1 end
                    toRetire=toRetire-1
                end
            end
            for _,item in ipairs(list) do
                if toRetire<=0 then break end
                if not item.entry.gone then
                    item.entry.gone=true
                    if markShellLeft>0 then item.entry.shell=true; markShellLeft=markShellLeft-1 end
                    toRetire=toRetire-1
                end
            end
            for _,item in ipairs(list) do
                if not item.entry.gone then item.entry.batchCount=raw end
            end
        end
    end
    mailCache=new; Capture._mailCachedCount=count
    if ownershipComplete then ownership.records=new; return ownership end
end
function Capture.ScanMailboxSnapshot(allowEmpty)
    if not ready() then return end
    confirmSellerMail()
    return cacheMail(nil,allowEmpty==false)
end
local function currencyQuantity()
    local h=H(); local id=h and h.FAVOR_CURRENCY_ID or 3402
    local info=_G.C_CurrencyInfo and _G.C_CurrencyInfo.GetCurrencyInfo and _G.C_CurrencyInfo.GetCurrencyInfo(id)
    if not safeTable(info) then return end
    local value=info.quantity; if not hasSecret(value) then return tonumber(value) end
end
local consumedFavor
local function confirmFavor(spent)
    local p=pendingFavorBuy; if not p then return end
    pendingFavorBuy=nil
    spent=tonumber(spent) or p.favorCost
    if p.isCamp or money()>=(p.beforeMoney or money()) then p.copperCost=0 end
    append("FAVOR_SPEND",p.itemID,p.qty,0,-p.copperCost,p.where,{favor=spent,recipe=p.isRecipe and 1 or nil})
end
local function confirmVendor(paid,unconfirmed)
    local p=pendingVendorBuy; if not p then return end; pendingVendorBuy=nil
    paid=paid or p.expectedCopper
    append("VENDOR_BUY",p.itemID,p.qty,math.floor(paid/math.max(1,p.qty)+0.5),-paid,p.where,{unconfirmed=unconfirmed and 1 or nil})
end
local function buyMerchant(index,quantity)
    local merchantAPI=_G.C_MerchantFrame
    local infoFn=merchantAPI and (merchantAPI.GetItemInfo or merchantAPI.GetMerchantItemInfo)
    local info=infoFn and infoFn(index)
    if hasSecret(info) then return end
    local name,price,stack,extended
    if safeTable(info) then name=info.name; price=info.price or info.buyPrice; stack=info.stackCount or info.quantity or info.stackSize; extended=info.hasExtendedCost end
    if _G.GetMerchantItemInfo and (not name or price==nil) then
        local n,_,p,s,_,_,_,e=_G.GetMerchantItemInfo(index); name=name or n; price=price or p; stack=stack or s; extended=extended or e
    end
    local link=_G.GetMerchantItemLink and _G.GetMerchantItemLink(index); local id=safeTable(info) and info.itemID or nil
    if hasSecret(name,price,stack,link,id,quantity) then return end
    id=id or itemID(link) or Store.ResolveItemIDByName(Store.CurrentCharAndEcon(),name); if not id or id<=0 then return end
    stack=math.max(1,tonumber(stack) or 1)
    local buyUnits=(quantity==nil) and stack or math.max(1,tonumber(quantity) or stack); local stacks=buyUnits/stack
    local copper=(tonumber(price) or 0)*stacks; local favor=0; local h=H(); local favorID=h and h.FAVOR_CURRENCY_ID or 3402
    if _G.GetMerchantItemCostItem then
        local n=_G.GetMerchantItemCostInfo and _G.GetMerchantItemCostInfo(index) or 1
        if hasSecret(n) then return end
        for i=1,n do
            local _,cost,costLink,currencyName,currencyID=_G.GetMerchantItemCostItem(index,i)
            if hasSecret(cost,costLink,currencyName,currencyID) then return end
            local cid=currencyID or (type(costLink)=="string" and tonumber(costLink:match("currency:(%d+)")))
            if cid==favorID or currencyName=="Merchant's Favor" or (type(costLink)=="string" and costLink:find("Merchant's Favor",1,true)) then favor=favor+(tonumber(cost) or 0)*stacks end
        end
    end
    if safeTable(info) then
        if hasSecret(info.currencyID,info.currencyQuantity,info.currencyCost) then return end
        if info.currencyID==favorID then favor=(tonumber(info.currencyQuantity or info.currencyCost) or favor)*stacks end
        for _,c in pairs(info.currencyCosts or {}) do if c.currencyID==favorID then favor=favor+(tonumber(c.quantity or c.amount) or 0)*stacks end end
    end
    if favor>0 then
        if pendingFavorBuy then confirmFavor() end
        local recipe=Model.GetIndexes().RECIPE_BY_SCROLL[id]
        local isRecipe=recipe~=nil
        if not isRecipe and _G.GetItemInfoInstant then local _,_,_,_,_,classID=_G.GetItemInfoInstant(id); isRecipe=classID==9 end
        local isCamp=recipe and (recipe.acqType=="camp" or recipe.source=="camp") or false
        local p={itemID=id,qty=buyUnits,copperCost=copper,favorCost=favor,name=name,at=nowSec(),where=zone(),isRecipe=isRecipe,isCamp=isCamp,beforeMoney=lastMoney or money(),beforeFavor=Capture.lastFavor or currencyQuantity()}
        pendingFavorBuy=p
        local current=currencyQuantity()
        if Capture.lastFavor and current and Capture.lastFavor>current then
            local spent=Capture.lastFavor-current; confirmFavor(spent); consumedFavor={qty=spent,at=nowSec()}
        end
        if current then Capture.lastFavor=current end
    else
        if pendingVendorBuy then confirmVendor(nil,true) end
        local p={itemID=id,qty=buyUnits,expectedCopper=copper,beforeMoney=lastMoney or money(),at=nowSec(),where=zone()}; pendingVendorBuy=p
        local paid=p.beforeMoney-money()
        if paid>0 and (not pendingPost and not pendingPouch) then confirmVendor(paid)
        else after(10,function() if ready() and pendingVendorBuy==p then safeCall("VENDOR_BUY",confirmVendor,nil,true) end end) end
    end
end
local function queueVendorSell(id,qty)
    if not id then return end
    pendingVendorSell={itemID=id,qty=qty or 1,beforeMoney=lastMoney or money(),at=nowSec(),where=zone()}
end
local function queueJunkSale()
    if not merchantOpen() then return end
    local container=_G.C_Container; local entries={}; local expected=0
    if container and container.GetContainerNumSlots and container.GetContainerItemInfo then
        for bag=0,(_G.NUM_BAG_SLOTS or 4) do
            local slots=container.GetContainerNumSlots(bag); if hasSecret(slots) then return end
            for slot=1,(tonumber(slots) or 0) do
            local info=container.GetContainerItemInfo(bag,slot)
            if safeTable(info) and not hasSecret(info.itemID,info.stackCount,info.quality) then
                local quality,value=info.quality,info.sellPrice
                local getter=(_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
                if getter and (quality==nil or value==nil) then
                    local _,_,q,_,_,_,_,_,_,_,v=getter(info.itemID)
                    if not hasSecret(q,v) then quality=quality or q; value=value or v end
                end
                if quality==0 and (tonumber(value) or 0)>0 then
                    local qty=tonumber(info.stackCount) or 1; local amount=qty*value
                    entries[#entries+1]={itemID=info.itemID,qty=qty,amount=amount}; expected=expected+amount
                end
            end
        end end
    end
    queueVendorSell(0,1)
    if #entries>0 then pendingVendorSell.entries=entries; pendingVendorSell.expected=expected end
end
local function repairMode() local v=_G.InRepairMode and _G.InRepairMode(); return not hasSecret(v) and v==true end
local function useBag(bag,slot)
    local id,qty=bagInfo(bag,slot); if not id then return end
    if repairMode() then return end
    if merchantOpen() then queueVendorSell(id,qty)
    elseif pouchIDs[id] then pendingPouch={itemID=id,tier=pouchIDs[id],beforeMoney=lastMoney or money(),at=nowSec()} end
end
local function stashQuest()
    local q={npc=_G.UnitName and _G.UnitName("npc"),zone=zone(),subzone=_G.GetSubZoneText and _G.GetSubZoneText(),at=nowSec()}
    if _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetPlayerMapPosition then
        local map=_G.C_Map.GetBestMapForUnit("player"); if hasSecret(map) then return end
        local pos=map and _G.C_Map.GetPlayerMapPosition(map,"player")
        if safeTable(pos) then if type(pos.GetXY)=="function" then q.x,q.y=pos:GetXY() else q.x,q.y=pos.x,pos.y end end
    end
    if not hasSecret(q.npc,q.zone,q.subzone,q.x,q.y) then questContext=q end
end
ownAlt=function(name)
    if type(name)~="string" or name=="" then return nil end
    local hostDB=_G.MerchantMasterDB or {}; local chars=(hostDB.chars or {}); local stats=(db() and db().stats and db().stats.chars) or {}
    local _,econ=Store.CurrentCharAndEcon()
    local lower=name:lower()
    local bareLower=(name:match("^([^%-]+)%-") or name):lower()
    local function matchesName(canonical, entryName)
        local cLow=canonical:lower()
        local tailShort=(canonical:match("%-([^%-]+)$") or canonical):lower()
        local headShort=(canonical:match("^([^%-]+)%-") or canonical):lower()
        if cLow==lower or tailShort==lower or tailShort==bareLower or headShort==lower or headShort==bareLower then return true end
        if type(entryName)=="string" and (entryName:lower()==lower or entryName:lower()==bareLower) then return true end
        return false
    end
    for key,entry in pairs(chars) do
        local canonical=tostring(key)
        local entryName=type(entry)=="table" and (entry.name or entry.characterName) or nil
        if matchesName(canonical, entryName) and Store.DeriveEcon(canonical)==econ then return canonical end
    end
    for canonical in pairs(stats) do
        local cStr=tostring(canonical)
        if matchesName(cStr, nil) and Store.DeriveEcon(cStr)==econ then return cStr end
    end
end
local function sendMailItems()
    local out={}; local maxSlots=tonumber(_G.ATTACHMENTS_MAX_SEND) or 12
    for slot=1,maxSlots do
        local name,arg2,arg3,arg4,arg5
        if _G.GetSendMailItem then name,arg2,arg3,arg4,arg5=_G.GetSendMailItem(slot) end
        local link=_G.GetSendMailItemLink and _G.GetSendMailItemLink(slot)
        if hasSecret(name,arg2,arg3,arg4,arg5,link) then return {} end
        local idFromLink=tonumber(type(link)=="string" and link:match("item:(%d+)"))
        local id,count
        if type(arg2)=="number" and arg2>0 and (idFromLink==nil or arg2==idFromLink) and tonumber(arg4) then
            id,count=arg2,tonumber(arg4)
        else
            id,count=idFromLink,tonumber(arg3)
        end
        if id and id>0 then out[#out+1]={itemID=id,qty=count or 1} end
    end
    return out
end
local function snapshotCompose()
    local moneySent,cod,postage=0,0,0
    if _G.GetSendMailMoney then moneySent=_G.GetSendMailMoney() elseif stagedSendMoney then moneySent=stagedSendMoney end
    if _G.GetSendMailCOD then cod=_G.GetSendMailCOD() elseif stagedSendCOD then cod=stagedSendCOD end
    if _G.GetSendMailPrice then postage=_G.GetSendMailPrice() end
    if hasSecret(moneySent,cod,postage) then return end
    stagedCompose={money=tonumber(moneySent) or 0,cod=tonumber(cod) or 0,postage=tonumber(postage) or 0,items=sendMailItems(),at=nowSec()}
end
local function stageSendMail(recipient)
    if hasSecret(recipient) then return end
    if type(recipient)~="string" or recipient=="" then return end
    local moneySent,cod,postage=0,0,0
    if _G.GetSendMailMoney then moneySent=_G.GetSendMailMoney() elseif stagedSendMoney then moneySent=stagedSendMoney end
    if _G.GetSendMailCOD then cod=_G.GetSendMailCOD() elseif stagedSendCOD then cod=stagedSendCOD end
    if _G.GetSendMailPrice then postage=_G.GetSendMailPrice() end
    if hasSecret(moneySent,cod,postage) then return end
    local items=sendMailItems()
    local snap=stagedCompose and (nowSec()-(stagedCompose.at or 0)<=60) and stagedCompose or nil
    local mVal=tonumber(moneySent) or 0
    local cVal=tonumber(cod) or 0
    local pVal=tonumber(postage) or 0
    if mVal<=0 then mVal=tonumber(stagedSendMoney) or (snap and snap.money) or 0 end
    if cVal<=0 then cVal=tonumber(stagedSendCOD) or (snap and snap.cod) or 0 end
    if pVal<=0 and snap and (snap.postage or 0)>0 then pVal=snap.postage end
    if #items==0 and snap and snap.items and #snap.items>0 then items=snap.items end
    local p={recipient=recipient,money=mVal,cod=cVal,postage=pVal,items=items,at=nowSec()}
    pendingSendMail=p
    after(60,function() if pendingSendMail==p then pendingSendMail=nil; stagedSendMoney=nil; stagedSendCOD=nil; stagedCompose=nil end end)
end
transferPairs=function()
    local stats=ensureTable(db().stats,"transferPairs"); return stats
end
pairForIncoming=function(sender,amount)
    local current=Store.CurrentCharAndEcon(); local from=ownAlt(sender)
    if not from then return nil end
    for _,entry in ipairs(transferPairs()) do
        if not entry.consumed and entry.toChar==current and entry.fromChar==from and entry.amount==amount and nowSec()-entry.at<=30*86400 then entry.consumed=true; return entry.pairKey end
    end
end
local function completeSendMail()
    local p=pendingSendMail; pendingSendMail=nil; stagedSendMoney=nil; stagedSendCOD=nil; if not p then return end
    local ownChar=ownAlt(p.recipient); local internal=ownChar~=nil; local pair
    if internal then
        local stats=ensureTable(db(),"stats")
        stats.transferSeq=(tonumber(stats.transferSeq) or 0)+1
        pair=tostring(Store.CurrentCharAndEcon())..":"..ownChar..":"..tostring(stats.transferSeq)
    end
    if p.postage>0 then append("POSTAGE",0,0,0,-p.postage,"Mail",{recipient=p.recipient}) end
    if p.money>0 then
        append("MONEY_TRANSFER",0,0,0,-p.money,"Mail",{counterparty=p.recipient,direction="out",internal=internal,pairKey=pair})
        if internal then local from=Store.CurrentCharAndEcon(); transferPairs()[#transferPairs()+1]={fromChar=from,toChar=ownChar,amount=p.money,at=p.at,pairKey=pair} end
    end
    if p.cod>0 and #p.items>0 then local cod=ensureTable(db().stats,"codExpectations"); cod[#cod+1]={sellerChar=Store.CurrentCharAndEcon(),recipient=ownChar or p.recipient:lower(),items=p.items,cod=p.cod,at=p.at} end
    if internal and #p.items>0 and p.cod<=0 and ns.Inventory then
        local char,econ=Store.CurrentCharAndEcon(); ns.Inventory.RecordInTransitMail(ownChar,p.items,p.money,p.at,char,econ)
    end
end
local function durabilitySnapshot()
    if type(_G.GetInventoryItemDurability)~="function" then return nil end
    local values={}
    for slot=1,19 do local current,maximum=_G.GetInventoryItemDurability(slot); if hasSecret(current,maximum) then return nil end; if current~=nil or maximum~=nil then values[#values+1]=slot..":"..tostring(current or "")..":"..tostring(maximum or "") end end
    return table.concat(values,";")
end
stageRepair=function()
    local expected=0; if _G.GetRepairAllCost then expected=_G.GetRepairAllCost() end
    if hasSecret(expected) then return end
    pendingRepair={before=lastMoney or money(),expected=tonumber(expected) or 0,beforeDurability=lastDurability or durabilitySnapshot(),at=nowSec(),guild=false}
end
local function confirmRepair(current)
    local p=pendingRepair
    if not p or nowSec()-p.at>15 then pendingRepair=nil; return end
    local spent=p.before-(tonumber(current) or money())
    local afterDurability=durabilitySnapshot()
    local changedDurability=not p.beforeDurability or not afterDurability or p.beforeDurability~=afterDurability
    if spent>0 and changedDurability and (p.expected<=0 or spent>=p.expected) then append("REPAIR",0,0,0,-(p.expected>0 and p.expected or spent),"Repair",{}) end
    pendingRepair=nil
    if afterDurability then lastDurability=afterDurability end
end
local function readBuyback(index)
    local name,texture,price,quantity
    if _G.GetBuybackItemInfo then name,texture,price,quantity=_G.GetBuybackItemInfo(index) end
    local link=_G.GetBuybackItemLink and _G.GetBuybackItemLink(index)
    if hasSecret(name,texture,price,quantity,link) then return end
    local id=itemID(link)
    if id then return {itemID=id,qty=tonumber(quantity) or 1,cost=tonumber(price) or 0} end
end
local function cacheBuybackItems()
    buybackCache={}
    local count=_G.GetNumBuybackItems and _G.GetNumBuybackItems() or 12
    if hasSecret(count) then return end
    for index=1,tonumber(count) or 0 do
        local entry=readBuyback(index)
        if entry then entry.beforeCount=itemCount(entry.itemID); buybackCache[index]=entry end
    end
end
local function tradeItems(which,prevItems)
    local out,byID,prevBefore={},{},{}
    for _,it in ipairs(prevItems or {}) do
        if it.itemID and prevBefore[it.itemID]==nil then prevBefore[it.itemID]=it.before end
    end
    local countFn=_G.GetNumTradeSlots
    local n=6; if countFn then n=countFn(which) end
    if hasSecret(n) then return out end
    for i=1,tonumber(n) or 6 do
        local name,texture,num,quality,isUsable
        local infoFn=_G[which==1 and "GetTradePlayerItemInfo" or "GetTradeTargetItemInfo"]
        if infoFn then name,texture,num,quality,isUsable=infoFn(i) end
        local link=_G[which==1 and "GetTradePlayerItemLink" or "GetTradeTargetItemLink"] and _G[which==1 and "GetTradePlayerItemLink" or "GetTradeTargetItemLink"](i)
        if hasSecret(name,texture,num,quality,isUsable,link) then return {} end
        local id=tonumber(type(link)=="string" and link:match("item:(%d+)"))
        if id and id>0 then
            local q=tonumber(num) or 1
            local existing=byID[id]
            if existing then
                existing.qty=existing.qty+q
            else
                local entry={itemID=id,qty=q,before=prevBefore[id]~=nil and prevBefore[id] or itemCount(id)}
                byID[id]=entry
                out[#out+1]=entry
            end
        end
    end
    return out
end
local function stageTrade(isNew)
    local previous=not isNew and pendingTrade or nil
    if previous and (previous.closed or previous.confirmed) then return end
    local setting=(_G.MerchantMasterDB or {}).anTrackTrades or "auto"
    if setting=="off" then pendingTrade=nil; return end
    local partner=_G.UnitName and _G.UnitName("NPC")
    local playerGold,targetGold=0,0
    if _G.GetPlayerTradeMoney then playerGold=_G.GetPlayerTradeMoney() end
    if _G.GetTargetTradeMoney then targetGold=_G.GetTargetTradeMoney() end
    if hasSecret(partner,playerGold,targetGold) then return end
    if (not partner or partner=="") and previous then partner=previous.partner end
    playerGold=tonumber(playerGold) or 0; targetGold=tonumber(targetGold) or 0
    pendingTrade={partner=partner,playerGold=playerGold,targetGold=targetGold,give=tradeItems(1,previous and previous.give),take=tradeItems(2,previous and previous.take),beforeMoney=previous and previous.beforeMoney or money(),at=nowSec(),accepted=previous and previous.accepted or false,acceptSeen=previous and previous.acceptSeen or false,confirmed=false,closed=false,closedAt=nil}
end
local function completeTrade(force)
    local p=pendingTrade
    if not p then return end
    local now=nowSec()
    if p.closedAt and now-p.closedAt>15 then pendingTrade=nil; return end
    if not p.closedAt and now-p.at>600 then pendingTrade=nil; return end
    if force then p.confirmed=true end
    if not p.confirmed and not (p.closed and p.accepted) then return end
    local partner=p.partner or ""
    local internal=ownAlt(partner); local delta=money()-p.beforeMoney
    local netSpend=math.max(0,p.playerGold-p.targetGold)
    local netReceive=math.max(0,p.targetGold-p.playerGold)
    local function changedItems(items,gain)
        for _,it in ipairs(items) do
            local afterCount=itemCount(it.itemID)
            if (gain and afterCount>(it.before or 0)) or (not gain and afterCount<(it.before or 0)) then return true end
        end
        return false
    end
    local kind,items,total,negative,party,transferDelta
    if #p.take>0 and netSpend>0 then
        if p.confirmed or delta<=-netSpend or changedItems(p.take,true) then
            kind,items,total,negative,party="TRADE_BUY",p.take,netSpend,true,{seller=partner,counterparty=partner}
        end
    elseif #p.give>0 and netReceive>0 then
        if p.confirmed or delta>=netReceive or changedItems(p.give,false) then
            kind,items,total,negative,party="TRADE_SELL",p.give,netReceive,false,{buyer=partner,counterparty=partner}
        end
    elseif #p.take>0 and #p.give==0 and netReceive>0 then
        if p.confirmed or delta>=netReceive or changedItems(p.take,true) then
            kind,items,total,negative,party="TRADE_BUY",p.take,0,true,{seller=partner,counterparty=partner}
            transferDelta=netReceive
        end
    elseif #p.give>0 and #p.take==0 and netSpend>0 then
        if p.confirmed or delta<=-netSpend or changedItems(p.give,false) then
            kind,items,total,negative,party="TRADE_SELL",p.give,0,false,{buyer=partner,counterparty=partner}
            transferDelta=-netSpend
        end
    elseif #p.take>0 and p.playerGold==p.targetGold and (p.confirmed or changedItems(p.take,true)) then
        kind,items,total,negative,party="TRADE_BUY",p.take,0,true,{seller=partner,counterparty=partner}
    elseif #p.give>0 and (p.confirmed or changedItems(p.give,false)) then
        kind,items,total,negative,party="TRADE_SELL",p.give,0,false,{buyer=partner,counterparty=partner}
    elseif #p.give==0 and #p.take==0 then
        local expected=p.targetGold-p.playerGold
        if p.confirmed and expected~=0 then
            pendingTrade=nil
            append("MONEY_TRANSFER",0,0,0,expected,"Trade",{counterparty=partner,direction=expected<0 and "out" or "in",internal=internal,pairKey=internal and (tostring(Store.CurrentCharAndEcon())..":"..partner..":"..tostring(p.at)) or nil})
            return
        elseif delta~=0 and ((p.playerGold>p.targetGold and delta<0) or (p.targetGold>p.playerGold and delta>0)) then
            pendingTrade=nil
            append("MONEY_TRANSFER",0,0,0,delta,"Trade",{counterparty=partner,direction=delta<0 and "out" or "in",internal=internal,pairKey=internal and (tostring(Store.CurrentCharAndEcon())..":"..partner..":"..tostring(p.at)) or nil})
            return
        end
    end
    if not kind then return end
    pendingTrade=nil
    local weights,sum={},0
    for i,it in ipairs(items) do
        local unit=Store.EstimateCraftOrMarketCost and Store.EstimateCraftOrMarketCost(it.itemID) or 0
        weights[i]=math.max(1,math.floor((tonumber(unit) or 0)*it.qty+0.5)); sum=sum+weights[i]
    end
    local used=0
    for i,it in ipairs(items) do
        local amount=i==#items and total-used or math.floor(total*weights[i]/math.max(1,sum)+0.5); used=used+amount
        local extra={}
        for k,v in pairs(party) do extra[k]=v end
        append(kind,it.itemID,it.qty,math.floor(amount/math.max(1,it.qty)+0.5),negative and -amount or amount,"Trade",extra)
    end
    if transferDelta and transferDelta~=0 then
        append("MONEY_TRANSFER",0,0,0,transferDelta,"Trade",{counterparty=partner,direction=transferDelta<0 and "out" or "in",internal=internal,pairKey=internal and (tostring(Store.CurrentCharAndEcon())..":"..partner..":"..tostring(p.at)) or nil})
    end
end
local function snapshotGuildBank()
    if not Capture.GetCapabilities or not Capture.GetCapabilities().guildBank or not ns.Inventory then return end
    local guild=_G.GetGuildInfo and _G.GetGuildInfo("player")
    local n=_G.GetNumGuildBankTabs and _G.GetNumGuildBankTabs()
    if hasSecret(guild,n) or type(guild)~="string" or guild=="" then return end
    local tabs={}
    for tab=1,tonumber(n) or 0 do
        local slots={}
        for slot=1,98 do
            local texture,count
            if _G.GetGuildBankItemInfo then texture,count=_G.GetGuildBankItemInfo(tab,slot) end
            local link=_G.GetGuildBankItemLink and _G.GetGuildBankItemLink(tab,slot)
            if hasSecret(texture,count,link) then return end
            local id=tonumber(type(link)=="string" and link:match("item:(%d+)"))
            if id and id>0 then slots[id]=(slots[id] or 0)+(tonumber(count) or 1) end
        end
        tabs[tab]=slots
    end
    local _,econ=Store.CurrentCharAndEcon()
    local gold=0; if _G.GetGuildBankMoney then gold=_G.GetGuildBankMoney() end
    if not hasSecret(gold) then ns.Inventory.CaptureGuildSnapshot(guild,econ,tabs,gold) end
end
local function prunePendingMoney(now)
    local q=ws3.pendingMoneyQueue
    local i=1
    while i<=#q do
        if now-(q[i].at or 0)>ws3.pendingMoneyTTL then table.remove(q,i) else i=i+1 end
    end
end
local function enqueuePendingMoney(entry)
    local now=nowSec()
    prunePendingMoney(now)
    entry.at=entry.at or now
    local q=ws3.pendingMoneyQueue
    q[#q+1]=entry
    while #q>ws3.maxPendingMoney do table.remove(q,1) end
end
local function clearPendingMoneyQueue()
    local q=ws3.pendingMoneyQueue
    for i=#q,1,-1 do q[i]=nil end
end
local function cacheTrainerServices()
    ws3.trainerCache={}
    if type(_G.GetNumTrainerServices)~="function" then return end
    local n=_G.GetNumTrainerServices()
    if hasSecret(n) or not tonumber(n) then return end
    for i=1,tonumber(n) do
        local name,subText,category
        if type(_G.GetTrainerServiceInfo)=="function" then name,subText,category=_G.GetTrainerServiceInfo(i) end
        local cost
        if type(_G.GetTrainerServiceCost)=="function" then cost=_G.GetTrainerServiceCost(i) end
        if not hasSecret(name,subText,category,cost) and type(name)=="string" and name~="" then
            ws3.trainerCache[i]={name=name,cost=tonumber(cost) or 0}
        end
    end
end
local function consumePendingMoney(delta)
    if not delta or delta==0 then return false end
    local q=ws3.pendingMoneyQueue
    local now=nowSec()
    prunePendingMoney(now)
    if #q==0 then return false end
    local spent=delta<0 and (-delta) or 0
    local gained=delta>0 and delta or 0
    local function matchesSign(e)
        if delta<0 then return e.kind=="TRAINER_FEE" or e.kind=="GUILD_DEPOSIT" or e.kind=="AH_BID" end
        return e.kind=="GUILD_WITHDRAW"
    end
    local matchIdx
    for i=1,#q do
        local e=q[i]
        if matchesSign(e) then
            local expected=(delta<0) and (tonumber(e.cost) or tonumber(e.amount) or 0) or (tonumber(e.amount) or 0)
            local actual=(delta<0) and spent or gained
            if expected>0 and actual==expected then matchIdx=i; break end
        end
    end
    if not matchIdx then
        for i=1,#q do
            if matchesSign(q[i]) then matchIdx=i; break end
        end
    end
    if not matchIdx then return false end
    local e=table.remove(q,matchIdx)
    if e.kind=="TRAINER_FEE" then
        append("TRAINER_FEE",0,1,spent,-spent,"Trainer",{name=e.name})
    elseif e.kind=="GUILD_DEPOSIT" then
        append("GUILD_DEPOSIT",0,1,spent,-spent,"Guild Bank",{guild=e.guild,direction="out"})
    elseif e.kind=="GUILD_WITHDRAW" then
        append("GUILD_WITHDRAW",0,1,gained,gained,"Guild Bank",{guild=e.guild,direction="in"})
    elseif e.kind=="AH_BID" then
        local qty=math.max(1,tonumber(e.qty) or 1)
        local unit=math.floor(spent/qty+0.5)
        append("AH_BID",e.itemID or 0,qty,unit,-spent,"Auction House",{auctionID=e.auctionID,isBid=true,name=e.name})
        ws3.recentAHBids[#ws3.recentAHBids+1]={itemID=e.itemID or 0,auctionID=e.auctionID,qty=qty,amount=spent,at=now}
        while #ws3.recentAHBids>128 do table.remove(ws3.recentAHBids,1) end
    end
    return true
end
function Capture.GetCapabilities()
    local function exists(tbl,key) return safeTable(tbl) and type(tbl[key])=="function" end
    local bank=_G.C_Bank; local bankEnum
    if safeTable(_G.Enum) and type(_G.Enum)=="table" and safeTable(_G.Enum.BankType) then bankEnum=_G.Enum.BankType end
    local accountBank=bankEnum and bankEnum.Account
    return {craftingOrders=safeTable(_G.C_CraftingOrders) and type(_G.C_CraftingOrders)=="table",garrison=safeTable(_G.C_Garrison) and type(_G.C_Garrison)=="table",warbank=safeTable(bank) and type(bank)=="table" and safeTable(bankEnum) and not hasSecret(accountBank) and type(accountBank)=="number",guildBank=exists(_G,"CanGuildBankRepair") or exists(_G,"GetGuildBankMoney") or (type(_G.GetNumGuildBankTabs)=="function" and type(_G.GetGuildBankItemInfo)=="function")}
end
function Capture._CompleteSendMail() completeSendMail() end
function Capture._StageSendMail(name) stageSendMail(name) end
function Capture._StageRepair() stageRepair() end
function Capture._ConfirmRepair(value) confirmRepair(value) end
function Capture._StageTrade() stageTrade() end
function Capture._CompleteTrade() completeTrade() end
function Capture.InstallHooks()
    lastMoney=lastMoney or money()
    local ah=_G.C_AuctionHouse
    if not ah or (_G.IsUsingLegacyAuctionClient and _G.IsUsingLegacyAuctionClient()) then Capture.ahSkipped=true
    else
        Capture.ahSkipped=false
        hook(ah,"StartCommoditiesPurchase","AH_BUY",function(id,qty) pendingCommodity={itemID=id,qty=qty,unit=0,total=0} end)
        hook(ah,"ConfirmCommoditiesPurchase","AH_BUY",function() end)
        hook(ah,"PlaceBid","AH_BUY",function(id,amount)
            if hasSecret(id,amount) then return end
            local amt=tonumber(amount) or 0
            if amt<=0 then return end
            local info=ownedAuction(id) or auctionCache[id]
            if not info and ah.GetBrowseResults then local results=ah.GetBrowseResults(); if safeTable(results) then for _,r in ipairs(results) do if safeTable(r) and not hasSecret(r.auctionID) and r.auctionID==id then info=r; break end end end end
            if not safeTable(info) then return end
            local iid=auctionItem(info)
            if not iid or hasSecret(iid,info.quantity,info.buyoutAmount) then return end
            local qty=math.max(1,tonumber(info.quantity) or 1)
            local buyout=tonumber(info.buyoutAmount)
            if buyout and buyout>0 and buyout==amt then
                pendingBid={auctionID=id,itemID=iid,qty=qty,amount=amt,isBuyout=true,at=nowSec()}
            else
                pendingBid={auctionID=id,itemID=iid,qty=qty,amount=amt,isBuyout=false,at=nowSec()}
                local nm=(not hasSecret(info.itemName) and type(info.itemName)=="string" and info.itemName~="" and info.itemName)
                    or (not hasSecret(info.itemLink) and linkName(info.itemLink))
                    or (Model and Model.ItemName and Model.ItemName(iid))
                enqueuePendingMoney({kind="AH_BID",amount=amt,cost=amt,auctionID=id,itemID=iid,qty=qty,name=nm})
            end
        end)
        local function hookPost(key,isCommodity)
            if type(ah[key])~="function" then return end
            if _G.hooksecurefunc then
                hook(ah,key,"AH_POST",function(...) queuePost(isCommodity,nil,...) end)
                return
            end
            local registry=hooked[ah]; if not registry then registry={}; hooked[ah]=registry end
            if registry[key]==ah[key] then return end
            local original=ah[key]
            local function pack(...) return {n=select("#",...),...} end
            ah[key]=function(...)
                local result=pack(original(...))
                if ready() and not hasSecret(...) then
                    local nc=(not hasSecret(result[1]) and result[1]==true)
                    Store.ProbeLog("AH_POST","hook "..key.." args="..select("#",...))
                    safeCall("AH_POST",queuePost,isCommodity,nc,...)
                end
                return unpack(result,1,result.n)
            end
            registry[key]=ah[key]
        end
        hookPost("PostItem",false)
        hookPost("PostCommodity",true)
        hook(ah,"ConfirmPostItem","AH_POST",function(...)
            if pendingPost then
                pendingPost.needsConfirmation=false; pendingPost.unverified=false; pendingPost.at=nowSec()
                local p=pendingPost
                after(30,function() if ready() and pendingPost==p and not isPendingPostAwaitingConfirm(p) then safeCall("AH_POST",confirmPost,true) end end)
            elseif not (lastConfirmedPost and nowSec()-lastConfirmedPost.at<30) then queuePost(false,false,...) end
        end)
        hook(ah,"ConfirmPostCommodity","AH_POST",function(...)
            if pendingPost then
                pendingPost.needsConfirmation=false; pendingPost.unverified=false; pendingPost.at=nowSec()
                local p=pendingPost
                after(30,function() if ready() and pendingPost==p and not isPendingPostAwaitingConfirm(p) then safeCall("AH_POST",confirmPost,true) end end)
            elseif not (lastConfirmedPost and nowSec()-lastConfirmedPost.at<30) then queuePost(true,false,...) end
        end)
        hook(ah,"CancelAuction","AH_CANCEL",function(id)
            local info=ownedAuction(id); local iid=auctionItem(info); if not iid then return end
            local cost=ah.GetCancelCost and ah.GetCancelCost(id) or 0
            if hasSecret(iid,info.quantity,cost,info.unitPrice,info.buyoutAmount) then return end
            local qty=info.quantity or 1
            local unit=tonumber(info.unitPrice) or math.floor((tonumber(info.buyoutAmount) or 0)/math.max(1,qty)+0.5)
            pendingCancels[id]={auctionID=id,itemID=iid,qty=qty,unitPrice=unit,cost=tonumber(cost) or 0,at=nowSec()}
        end)
    end
    for _,name in ipairs({"TakeInboxMoney","AutoLootMailItem","TakeInboxItem"}) do installMailPreHook(name,"_preTakeMail") end
    installBeforeHook(_G,"SendMail",function(recipient) stageSendMail(recipient) end)
    hook(_G,"SetSendMailMoney","MAIL",function(amount) if not hasSecret(amount) then stagedSendMoney=tonumber(amount); snapshotCompose() end end)
    hook(_G,"SetSendMailCOD","MAIL",function(amount) if not hasSecret(amount) then stagedSendCOD=tonumber(amount); snapshotCompose() end end)
    hook(_G,"ClickSendMailItemButton","MAIL",function() snapshotCompose() end)
    hook(_G,"RepairAllItems","REPAIR",function(guild) if not guild then stageRepair() end end)
    hook(_G,"BuybackItem","VENDOR_BUYBACK",function(index)
        local entry=buybackCache[index] or readBuyback(index); if not entry then return end
        local id=entry.itemID
        local inventory=(db().inventory or {})[Store.CurrentCharAndEcon()]
        local beforeCount=entry.beforeCount or (inventory and inventory.bags and (inventory.bags[id] or 0)) or itemCount(id)
        pendingBuyback={itemID=id,qty=entry.qty,cost=entry.cost,before=lastMoney or money(),at=nowSec(),beforeCount=beforeCount}
    end)
    hook(_G,"PickupInventoryItem","REPAIR",function(slot) if repairMode() and not hasSecret(slot) then stageRepair() end end)
    installMailPreHook("DeleteInboxItem","_preDeleteMail")
    hook(_G,"BuyMerchantItem","VENDOR_BUY",buyMerchant)
    local function usedContainer(bag,slot,...) if repairMode() then stageRepair() end; recentContainer={at=nowSec()}; useBag(bag,slot,...) end
    hook(_G.C_Container,"UseContainerItem","CONTAINER",usedContainer)
    hook(_G,"UseContainerItem","CONTAINER",usedContainer)
    hook(_G.C_Container,"PickupContainerItem","CONTAINER",function(bag,slot)
        local id,qty=bagInfo(bag,slot); if id then cursorItem={itemID=id,qty=qty} end
    end)
    hook(_G,"SellCursorItem","VENDOR_SELL",function()
        if not merchantOpen() then return end
        if _G.GetCursorInfo then
            local typ,id,link=_G.GetCursorInfo()
            if not hasSecret(typ,id,link) and typ=="item" then queueVendorSell(tonumber(id) or itemID(link),cursorItem and cursorItem.qty or 1); cursorItem=nil; return end
        end
        if cursorItem then queueVendorSell(cursorItem.itemID,cursorItem.qty); cursorItem=nil end
    end)
    hook(_G.C_MerchantFrame,"SellAllJunkItems","VENDOR_SELL",queueJunkSale)
    hook(_G,"GetQuestReward","QUEST",stashQuest)
    hook(_G,"BuyTrainerService","TRAINER_FEE",function(index)
        if hasSecret(index) then return end
        local idx=tonumber(index)
        local cached=idx and ws3.trainerCache[idx] or nil
        local cost=cached and cached.cost or 0
        local name=cached and cached.name or nil
        if (not name or cost<=0) and idx then
            if type(_G.GetTrainerServiceInfo)=="function" then
                local n=_G.GetTrainerServiceInfo(idx)
                if not hasSecret(n) and type(n)=="string" and n~="" then name=name or n end
            end
            if cost<=0 and type(_G.GetTrainerServiceCost)=="function" then
                local c=_G.GetTrainerServiceCost(idx)
                if not hasSecret(c) and tonumber(c) then cost=tonumber(c) end
            end
        end
        if cost>0 then
            enqueuePendingMoney({kind="TRAINER_FEE",cost=cost,amount=cost,name=name or "Trainer Service"})
        end
    end)
    hook(_G,"DepositGuildBankMoney","GUILD_DEPOSIT",function(amount)
        if hasSecret(amount) then return end
        local amt=tonumber(amount) or 0
        if amt<=0 then return end
        local guild=_G.GetGuildInfo and _G.GetGuildInfo("player")
        if hasSecret(guild) then guild=nil end
        enqueuePendingMoney({kind="GUILD_DEPOSIT",amount=amt,cost=amt,guild=guild})
    end)
    hook(_G,"WithdrawGuildBankMoney","GUILD_WITHDRAW",function(amount)
        if hasSecret(amount) then return end
        local amt=tonumber(amount) or 0
        if amt<=0 then return end
        local guild=_G.GetGuildInfo and _G.GetGuildInfo("player")
        if hasSecret(guild) then guild=nil end
        enqueuePendingMoney({kind="GUILD_WITHDRAW",amount=amt,guild=guild})
    end)
end

local function coinText(s)
    if type(s)~="string" then return 0 end
    local gold=tonumber(s:match("(%d+)%s*[Gg]old")) or tonumber(s:match("(%d+)%s*g%f[%A]")) or 0
    local silver=tonumber(s:match("(%d+)%s*[Ss]ilver")) or tonumber(s:match("(%d+)%s*s%f[%A]")) or 0
    local copper=tonumber(s:match("(%d+)%s*[Cc]opper")) or tonumber(s:match("(%d+)%s*c%f[%A]")) or 0
    return gold*10000+silver*100+copper
end
local lootItems
local function lootOpen()
    if lootSession and not lootSession.closedAt and (next(lootSession.items) ~= nil or next(lootSession.slots) ~= nil) then return end
    if lootSession and lootSession.closedAt and lootItems then lootItems() end
    local s=(lootSession and not lootSession.closedAt) and lootSession or {items={},slots={},zone=zone(),beforeMoney=lastMoney or money(),coinRecorded=0,at=nowSec()}
    lootSession=s
    local fishing=_G.IsFishingLoot and _G.IsFishingLoot()
    local n=0; if _G.GetNumLootItems then n=_G.GetNumLootItems() end
    if hasSecret(n) then return end
    n=tonumber(n) or 0
    local moneySlotType=_G.LOOT_SLOT_MONEY or (_G.Enum and _G.Enum.LootSlotType and _G.Enum.LootSlotType.Money) or 2
    local currencySlotType=_G.LOOT_SLOT_CURRENCY or (_G.Enum and _G.Enum.LootSlotType and _G.Enum.LootSlotType.Currency) or 3
    for slot=1,n do
        local typ=_G.GetLootSlotType and _G.GetLootSlotType(slot)
        local link=_G.GetLootSlotLink and _G.GetLootSlotLink(slot)
        local _,name,qty,_,_,_,_,_,_,isCoin=_G.GetLootSlotInfo(slot)
        if not hasSecret(typ,link,name,qty,isCoin) then
            if typ==moneySlotType or isCoin then
                s.slots[slot]={coin=coinText(name)}
            elseif typ~=currencySlotType then
                local id=itemID(link); local source="Mob"
                if fishing then source="Fishing"
                elseif recentGather and nowSec()-recentGather.at<=5 then source=recentGather.source
                elseif recentContainer and nowSec()-recentContainer.at<=3 then source="Container"
                elseif _G.GetLootSourceInfo then
                    local sources={_G.GetLootSourceInfo(slot)}
                    for _,guid in ipairs(sources) do
                        if not hasSecret(guid) and type(guid)=="string" and guid:match("^GameObject%-") then source="Node"; break end
                    end
                end
                if id then
                    if not s.items[id] then s.items[id]={before=itemCount(id),source=source,recorded=0,offered=0} end
                    s.items[id].offered=s.items[id].offered+(tonumber(qty) or 1)
                end
                s.slots[slot]={itemID=id,qty=tonumber(qty) or 1}
            end
        end
    end
end
local recentlyDestroyedOutputs={}
lootItems = function()
    if not lootSession then return end
    if pendingDestroy and nowSec() - pendingDestroy.at <= 10 then return end
    for id,entry in pairs(lootSession.items) do
        if recentlyDestroyedOutputs[id] and nowSec()-recentlyDestroyedOutputs[id]<5 then entry.recorded=entry.offered
        else local gained=math.min(entry.offered,math.max(0,itemCount(id)-entry.before)); local delta=gained-entry.recorded; if delta>0 then Store.AddLoot(id,entry.source,lootSession.zone,delta); entry.recorded=gained end end
    end
end
local function lootMoney(delta)
    if not lootSession or delta<=0 then return end
    Store.AddLoot(0,"Money",lootSession.zone,delta); lootSession.coinRecorded=lootSession.coinRecorded+delta
end
local gatherSources={Herbalism="Herbalism",["Herb Gathering"]="Herbalism",Mining="Mining",Skinning="Skinning",Disenchant="Disenchant",["Pick Pocket"]="Pick Pocket"}
local craftItems
local function parseCreatedLootMessage(msg)
    if hasSecret(msg) or type(msg)~="string" or msg=="" then return nil end
    local matched=msg:find("^You create:")~=nil
    if not matched then
        for _,fmt in ipairs({_G.LOOT_ITEM_CREATED_SELF_MULTIPLE,_G.LOOT_ITEM_CREATED_SELF}) do
            if type(fmt)=="string" and not hasSecret(fmt) then
                local prefix=fmt:match("^(.-)%%s")
                if prefix and prefix~="" and msg:sub(1,#prefix)==prefix then matched=true; break end
            end
        end
    end
    if not matched then return nil end
    local id=tonumber(msg:match("|Hitem:(%d+):"))
    if not id or id<=0 then return nil end
    local qty=tonumber(msg:match("|h|r%s*x(%d+)") or msg:match("%]%s*x(%d+)")) or 1
    return id,math.max(1,math.floor(qty+0.5))
end
local function chatMsgLoot(msg)
    local p=pendingCraft; if not p then return end
    if nowSec()-p.at>5 then pendingCraft=nil; return end
    local id,qty=parseCreatedLootMessage(msg)
    if id and id==p.itemID and qty and qty>0 then
        p.rolls=type(p.rolls)=="table" and p.rolls or {}
        p.rolls[#p.rolls+1]=qty
        p.lootTotal=(tonumber(p.lootTotal) or 0)+qty
        p.at=nowSec()
    end
end
local function castSucceeded(unit,castGUID,spellID)
    if unit~="player" or hasSecret(spellID) then return end
    if spellID==13262 or spellID==51005 or spellID==31252 then
        local snap=ns.Inventory and ns.Inventory.ScanCurrentChar() or nil
        pendingDestroy={spellID=spellID,before=snap and snap.bags or {},at=nowSec()}
        return
    end
    local rec=Model.GetIndexes().RECIPE_BY_SPELL[spellID]
    if rec then
        local id=rec.outputItemID or rec.itemID
        if id then
            if pendingCraft and pendingCraft.spellID==spellID and nowSec()-pendingCraft.at<=5 then
                pendingCraft.casts=(pendingCraft.casts or 1)+1
                pendingCraft.at=nowSec()
            else
                if pendingCraft and craftItems then craftItems() end
                pendingCraft={recipe=rec,spellID=spellID,itemID=id,before=itemCount(id),casts=1,rolls={},lootTotal=0,at=nowSec()}
            end
        end
        return
    end
    local name=(_G.C_Spell and _G.C_Spell.GetSpellName and _G.C_Spell.GetSpellName(spellID)) or (_G.GetSpellInfo and _G.GetSpellInfo(spellID))
    if not hasSecret(name) and gatherSources[name] then recentGather={source=gatherSources[name],at=nowSec()} end
end
local deGroupSeq = 0
local function resolveDEOutputUnitPrice(id)
    local h = H()
    if h and h.GetItemMarketPrice then
        local usedEval = false
        if h.BeginEval then
            pcall(h.BeginEval, h.app and h.app.getUIPriceBank and h.app.getUIPriceBank())
            usedEval = true
        end
        local ok, val = pcall(h.GetItemMarketPrice, id)
        if usedEval and h.EndEval then pcall(h.EndEval) end
        if ok and not hasSecret(val) and type(val) == "number" and val > 0 then
            return val
        end
    end
    if Store.EstimateCraftOrMarketCost then
        local ok, val = pcall(Store.EstimateCraftOrMarketCost, id)
        if ok and not hasSecret(val) and type(val) == "number" and val > 0 then
            return val
        end
    end
    return 0
end
local function destroyItems()
    local p=pendingDestroy; if not p then return end
    if nowSec()-p.at>10 then pendingDestroy=nil; return end
    local snap=ns.Inventory and ns.Inventory.ScanCurrentChar() or nil; if not snap then return end
    local lost, gained={},{}
    for id,qty in pairs(p.before or {}) do local n=math.max(0,qty-((snap.bags or {})[id] or 0)); if n>0 then lost[#lost+1]={itemID=tonumber(id),qty=n} end end
    for id,qty in pairs(snap.bags or {}) do local n=math.max(0,qty-((p.before or {})[id] or 0)); if n>0 then gained[#gained+1]={itemID=tonumber(id),qty=n} end end
    if #lost==0 or #gained==0 then return end
    pendingDestroy=nil
    local source=lost[1]; local outputs={}; local totalWeight=0
    db().destroyHistory=type(db().destroyHistory)=="table" and db().destroyHistory or {}
    if p.spellID==13262 then
        local deItems,totalMarketValue,totalUnits={},0,0
        for _,o in ipairs(gained) do
            local unit=resolveDEOutputUnitPrice(o.itemID)
            local mval=math.floor(unit*o.qty+0.5)
            local weight=math.max(1,mval)
            totalWeight=totalWeight+weight
            totalMarketValue=totalMarketValue+mval
            totalUnits=totalUnits+o.qty
            deItems[#deItems+1]={itemID=o.itemID,qty=o.qty,unit=unit,marketValue=mval,weight=weight}
            outputs[#outputs+1]=tostring(o.itemID)..":"..tostring(o.qty)..":"..tostring(weight)
        end
        local encoded=table.concat(outputs,";")
        deGroupSeq=deGroupSeq+1
        local deGroup="de:"..tostring(nowSec())..":"..tostring(source.itemID)..":"..tostring(deGroupSeq)
        for _,o in ipairs(gained) do recentlyDestroyedOutputs[o.itemID]=nowSec() end
        local row=append("DISENCHANT_BROKEN",source.itemID,source.qty,0,0,"Disenchanting",{spellID=p.spellID,deGroup=deGroup,outputs=encoded,estValue=totalMarketValue,nonCash=true})
        local srcBasis=(row and tonumber(row.cogs)) or 0
        local srcName=(Model and Model.ItemName and Model.ItemName(source.itemID)) or ("Item #"..tostring(source.itemID))
        local usedBasis,histOutputs=0,{}
        for idx,o in ipairs(deItems) do
            local allocBasis=0
            if srcBasis>0 then
                if idx==#deItems then
                    allocBasis=math.max(0,srcBasis-usedBasis)
                else
                    local ratio=(totalMarketValue>0) and (o.marketValue/totalMarketValue) or (o.qty/math.max(1,totalUnits))
                    allocBasis=math.floor(srcBasis*ratio)
                end
                usedBasis=usedBasis+allocBasis
            end
            o.allocBasis=allocBasis
            local unitBasis=math.floor(allocBasis/math.max(1,o.qty)+0.5)
            histOutputs[#histOutputs+1]={itemID=o.itemID,qty=o.qty,allocCost=allocBasis,marketValue=o.marketValue}
            append("DISENCHANT_RECEIVE",o.itemID,o.qty,unitBasis,0,"From: "..srcName,{
                spellID=p.spellID,deGroup=deGroup,srcItemID=source.itemID,srcName=srcName,
                srcQty=source.qty,allocBasis=allocBasis,marketValue=o.marketValue,costCarryover=true,nonCash=true,
            })
        end
        if row then
            local history=db().destroyHistory
            history[#history+1]={time=row.time,spellID=p.spellID,srcItemID=source.itemID,srcQty=source.qty,srcBasis=srcBasis,estValue=totalMarketValue,outputs=histOutputs}
            while #history>100 do table.remove(history,1) end
        end
        return
    end
    for _,o in ipairs(gained) do
        local unit=Store.EstimateCraftOrMarketCost and Store.EstimateCraftOrMarketCost(o.itemID) or 0
        local weight=math.max(1,math.floor(unit*o.qty+0.5)); totalWeight=totalWeight+weight
        outputs[#outputs+1]=tostring(o.itemID)..":"..tostring(o.qty)..":"..tostring(weight)
    end
    local encoded=table.concat(outputs,";")
    for _,o in ipairs(gained) do recentlyDestroyedOutputs[o.itemID]=nowSec() end
    local row=append("DESTROY",source.itemID,source.qty,0,0,"Destroying",{spellID=p.spellID,outputs=encoded,nonCash=true})
    if row then
        local history=db().destroyHistory; history[#history+1]={time=row.time,spellID=p.spellID,srcItemID=source.itemID,srcQty=source.qty,srcBasis=row.cogs or 0,outputs={}}
        for seg in tostring(row.extra.outputs or ""):gmatch("[^;]+") do local id,qty,cost=seg:match("^(%d+):(%d+):(%d+)$"); if id then history[#history].outputs[#history[#history].outputs+1]={itemID=tonumber(id),qty=tonumber(qty),allocCost=tonumber(cost)} end end
        while #history>100 do table.remove(history,1) end
    end
end
craftItems = function()
    local p=pendingCraft; if not p then return end
    if nowSec()-p.at>5 then pendingCraft=nil; return end
    local made=itemCount(p.itemID)-p.before
    if made>0 then
        pendingCraft=nil
        local rec=p.recipe
        local casts=math.max(1,tonumber(p.casts) or 1)
        if type(p.rolls)=="table" and #p.rolls>casts then casts=#p.rolls end
        local batches=casts
        local reagents={}
        for _,r in ipairs(rec.reagents or {}) do reagents[#reagents+1]={itemID=r.itemID or r[1],qty=(r.qty or r[2] or 0)*batches} end
        local sid=p.spellID or rec.spellID
        append("CRAFT",p.itemID,made,0,0,rec.prof or "Crafting",{reagents=reagents,spellID=sid,casts=casts})
        if Store.RecordCraftYield and sid then
            local rolls=(type(p.rolls)=="table" and #p.rolls>0 and p.lootTotal==made) and p.rolls or nil
            Store.RecordCraftYield(sid,p.itemID,made,casts,rolls)
        end
    end
end
function Capture.SanitizeLearnedWritZones(learnedTbl)
    if not safeTable(learnedTbl) then return false end
    local removed=false
    for id,entry in pairs(learnedTbl) do
        if safeTable(entry) and not hasSecret(id,entry.source)
            and (entry.source=="quest_accept" or entry.source=="bettermaps") then
            learnedTbl[id]=nil
            removed=true
        end
    end
    return removed
end
-- The host's ADDON_LOADED handler runs before MerchantMasterAPI is exposed.
host.SanitizeLearnedWritZones=Capture.SanitizeLearnedWritZones
function Capture.SyncActiveWritQuests()
    local hostDB=_G.MerchantMasterDB
    if safeTable(hostDB) and Capture.SanitizeLearnedWritZones(hostDB.learnedWritZones) then
        Model.Invalidate("writs")
    end
    return 0
end
local function normCoord(v)
    v=tonumber(v)
    if not v or v<=0 then return nil end
    if v<=1 then v=math.floor(v*1000+0.5)/10 end
    return v
end
local function questTurnedIn(questID,xpReward,moneyReward)
    local idx=Model.GetIndexes(); local w,cr=idx.WRIT_BY_QUEST[questID],idx.CRATE_BY_QUEST[questID]
    local context=questContext and nowSec()-questContext.at<=5 and questContext or {}; local where=context.zone or zone(); questContext=nil
    local copper=tonumber(moneyReward) or 0; local h=H()
    if w then
        if h and h.RecordWritTurnInCooldown then h.RecordWritTurnInCooldown(questID, nowSec()) end
        local hostDB=_G.MerchantMasterDB
        if hostDB and where and where~="" then
            hostDB.learnedWritZones=hostDB.learnedWritZones or {}
            local prev=hostDB.learnedWritZones[w.itemID]
            hostDB.learnedWritZones[w.itemID]={
                zone=where,
                subzone=context.subzone or (prev and prev.subzone),
                npc=context.npc or (prev and prev.npc),
                x=normCoord(context.x) or (prev and prev.x),
                y=normCoord(context.y) or (prev and prev.y),
                source="turnin",
                at=nowSec(),
            }
        end
        local tier=w.tier; if h and h.GetWritPouchInfo then local _,_,t=h.GetWritPouchInfo(w); tier=t or tier end
        append("WRIT_TURNIN",w.itemID,1,copper,copper,where or "Turn-In",{questID=questID,reqItemID=w.requiredItemID,reqQty=w.qty,rep=w.rep,pouchTier=tier},tostring(questID))
    elseif cr then
        local reward=tonumber(moneyReward) or cr.copper or 0
        recentCrateFavorGain={tokens=cr.tokens,at=nowSec()}
        append("CRATE_TURNIN",cr.sealedID or 0,1,reward,reward,where or "Waylaid Turn-In",{questID=questID,favor=cr.tokens,tier=cr.tier},tostring(questID))
    elseif copper>0 then append("QUEST_MONEY",0,1,copper,copper,where or "Quest",nil,tostring(questID)) end
end
local function currencyUpdate(currencyType,quantity,change,source,reason)
    local h=H(); if currencyType~=(h and h.FAVOR_CURRENCY_ID or 3402) then return end
    -- Some clients omit change; an open vendor purchase can still be confirmed
    -- by the currency balance, without synthesizing unattributed currency rows.
    if change==nil and pendingFavorBuy and nowSec()-pendingFavorBuy.at<=5 then
        local current=tonumber(quantity) or currencyQuantity()
        if current and pendingFavorBuy.beforeFavor and current<pendingFavorBuy.beforeFavor then
            confirmFavor(pendingFavorBuy.beforeFavor-current); Capture.lastFavor=current; return
        end
    end
    change=tonumber(change); Capture.lastFavor=tonumber(quantity) or Capture.lastFavor
    if not change or change==0 then return end
    if change>0 then
        if recentCrateFavorGain and nowSec()-recentCrateFavorGain.at<=2 and change==(tonumber(recentCrateFavorGain.tokens) or 0) then recentCrateFavorGain=nil; return end
        append("FAVOR_GAIN",0,change,0,0,"Merchant's Favor",{favor=change,source=source})
    else
        if consumedFavor and nowSec()-consumedFavor.at<=5 and consumedFavor.qty==-change then consumedFavor=nil; return end
        if pendingFavorBuy and nowSec()-pendingFavorBuy.at<=5 then confirmFavor(-change)
        else pendingFavorBuy=nil; append("FAVOR_SPEND",0,-change,0,0,"Merchant's Favor",{favor=-change,reason=reason}) end
    end
end
local function standing(updateOnly)
    local h=H(); local rep=h and h.GetMerchantReputation and h.GetMerchantReputation()
    if not safeTable(rep) or hasSecret(rep.standingID,rep.standingName,rep.totalFromNeutral) or not rep.standingID then return end
    local char=Store.CurrentCharAndEcon(); local previous=db().stats.lastStanding[char]
    if not updateOnly and previous and rep.standingID>previous then append("STANDING",0,rep.standingID,0,0,rep.standingName or "Standing",{from=previous,to=rep.standingID,name=rep.standingName,totalRep=rep.totalFromNeutral}) end
    db().stats.lastStanding[char]=rep.standingID
end
local function playerMoney()
    local current=money(); local delta=current-(lastMoney or current); lastMoney=current
    if pendingPouch and (not pendingPouch.expires or nowSec()<=pendingPouch.expires) and delta>0 then
        local p=pendingPouch; pendingPouch=nil; append("POUCH_MONEY",p.itemID,1,delta,delta,"Coin Pouch",{tier=p.tier},p.tier)
        if lootSession then lootSession.beforeMoney=lootSession.beforeMoney+delta end
        return
    end
    if delta~=0 and #ws3.pendingMoneyQueue>0 and consumePendingMoney(delta) then return end
    if pendingVendorBuy and nowSec()-pendingVendorBuy.at<=10 and delta<0 then
        local p=pendingVendorBuy; local paid=p.beforeMoney-current
        if paid>0 and (paid==p.expectedCopper or (not pendingPost and not pendingBid and not pendingCommodity and not pendingFavorBuy)) then confirmVendor(paid); return end
    end
    if pendingPost and not isPendingPostAwaitingConfirm(pendingPost) and delta<0 then confirmPost(); return end
    if pendingVendorSell and nowSec()-pendingVendorSell.at<=10 and delta>0 then
        local p=pendingVendorSell; pendingVendorSell=nil; local received=current-p.beforeMoney
        if received>0 then
            if p.entries then
                local left=received
                for i,entry in ipairs(p.entries) do
                    local amount=i==#p.entries and left or math.min(left,math.floor(received*entry.amount/p.expected+0.5)); left=left-amount
                    append("VENDOR_SELL",entry.itemID,entry.qty,math.floor(amount/math.max(1,entry.qty)+0.5),amount,p.where)
                end
            else append("VENDOR_SELL",p.itemID,p.qty,math.floor(received/math.max(1,p.qty)+0.5),received,p.where) end
        end
        return
    end
    if lootSession and delta>0 and not merchantOpen() and not pendingPouch and not pendingFavorBuy and not questContext and not pendingTrade and not (_G.MailFrame and _G.MailFrame.IsShown and _G.MailFrame:IsShown()) then lootMoney(delta) end
end

local POUCH_CASH_AVG={[284583]=1000,[284584]=3536,[284585]=7480,[284586]=7480}
function Capture.ResolveItemID(h,hostDB,name)
    if hasSecret(name) then return nil end
    if type(name)=="number" then return name end
    if type(name)~="string" or name=="" then return nil end
    local id=(hostDB and hostDB.itemIDs and hostDB.itemIDs[name]) or (h and h.ITEM_IDS_BY_NAME and h.ITEM_IDS_BY_NAME[name]) or (h and h.app and h.app.itemIDs and h.app.itemIDs[name])
    if id then return tonumber(id) end
    local instant=(_G.C_Item and _G.C_Item.GetItemInfoInstant and _G.C_Item.GetItemInfoInstant(name)) or (_G.GetItemInfoInstant and _G.GetItemInfoInstant(name))
    if not hasSecret(instant) and tonumber(instant) then return tonumber(instant) end
    local resolved=Store.ResolveItemIDByName and Store.ResolveItemIDByName(Store.CurrentCharAndEcon(),name) or 0
    return (resolved and resolved>0) and resolved or nil
end
Capture._pendingItemIDs={}
function Capture.WithCharEconomy(h,hostDB,charEcon,fn,evalBank)
    local prevEcon=hostDB and hostDB.economy
    local switched=false
    if hostDB and charEcon and charEcon~="" and prevEcon~=charEcon then
        hostDB.economy=charEcon
        switched=true
    end
    local began=false
    if h and h.BeginEval then
        local cache=h.BeginEval(evalBank or (not switched and h.app and h.app.getUIPriceBank and h.app.getUIPriceBank() or nil)); began=true
        if evalBank and safeTable(cache) then for k,v in pairs(cache) do if safeTable(v) then evalBank[k]=v end end end
    end
    local ok,err=pcall(fn)
    if began and h and h.EndEval then h.EndEval() end
    if switched then hostDB.economy=prevEcon end
    return ok,err
end
function Capture.ValueWealthItem(h,hostDB,charEcon,activeEcon,id,isBound,catKey)
    if not id or id<=0 then return 0,"Unscanned" end
    if POUCH_CASH_AVG[id] then return POUCH_CASH_AVG[id],"Pouch Avg" end
    local rawVendor=h and h.GetVendorSellPrice and h.GetVendorSellPrice(id) or nil
    if rawVendor==nil then Capture._pendingItemIDs[id]=true end
    local vendor=tonumber(rawVendor) or 0
    if catKey=="gear" then return vendor,"Vendor (Gear)" end
    if isBound or (h and h.IsItemSellable and h.IsItemSellable(id)==false) then return vendor,"Vendor (Bound)" end
    local mkt,src,listed
    local uiEcon=h and h.CurrentEconomyInfo and h.CurrentEconomyInfo()
    local sameEcon=uiEcon and uiEcon.effectiveKey==charEcon or (activeEcon==charEcon and (not hostDB or not hostDB.economy or hostDB.economy=="auto" or hostDB.economy==charEcon))
    if sameEcon and h and h.GetItemMarketPrice then
        mkt,src=h.GetItemMarketPrice(id)
        listed=h.GetNumListed and h.GetNumListed(id) or nil
    else
        local pool=hostDB and hostDB.ahPrices and hostDB.ahPrices[charEcon]
        local rec=pool and pool[id]
        mkt=type(rec)=="table" and (rec.price or rec.lastPrice) or tonumber(rec)
        src=mkt and "Saved AH" or nil
    end
    mkt=tonumber(mkt) or 0
    if mkt>0 and mkt>=vendor then return mkt,src or "AH Market" end
    if vendor>0 then return vendor,"Vendor" end
    return 0,"No Price"
end
function Capture.CollectCharEntries(h,hostDB,charTbl)
    local entries={}
    local function push(catKey,srcTbl,boundTbl)
        local merged,order,hasBoth={},{},{}
        local function addMerged(id,disp,qty,isBound)
            if qty<=0 then return end
            local baseKey=(id and id>0) and ("i:"..tostring(id)) or ("n:"..tostring(disp))
            local bKey=baseKey.."|"..(isBound and "B" or "T")
            local bucket=hasBoth[baseKey]
            if not bucket then bucket={t=false,b=false}; hasBoth[baseKey]=bucket end
            if isBound then bucket.b=true else bucket.t=true end
            local rec=merged[bKey]
            if rec then
                rec.qty=rec.qty+qty
                if (not rec.id or rec.id<=0) and id and id>0 then rec.id=id end
            else
                rec={cat=catKey,id=id,name=disp,qty=qty,bound=isBound,baseKey=baseKey}
                merged[bKey]=rec
                order[#order+1]=rec
            end
        end
        for name,value in pairs(srcTbl or {}) do
            local qty=tonumber(type(value)=="table" and (value.count or value.qty) or value) or 0
            if qty>0 then
                local id=Capture.ResolveItemID(h,hostDB,name)
                local disp=type(name)=="string" and name or ((h and h.ItemName and id and h.ItemName(id)) or ("Item #"..tostring(id)))
                local bQty=math.min(qty,math.max(0,tonumber(boundTbl and boundTbl[name]) or 0))
                local tQty=qty-bQty
                if tQty>0 then addMerged(id,disp,tQty,false) end
                if bQty>0 then addMerged(id,disp,bQty,true) end
            end
        end
        for _,rec in ipairs(order) do
            local both=hasBoth[rec.baseKey]
            local label=rec.name
            if rec.bound and both and both.t and both.b and type(label)=="string" and not label:find("(Bound)",1,true) then
                label=label.." (Bound)"
            end
            entries[#entries+1]={cat=rec.cat,id=rec.id,name=label,qty=rec.qty,bound=rec.bound}
        end
    end
    push("bags",charTbl.bags,charTbl.boundBags)
    push("bank",charTbl.bank,charTbl.boundBank)
    local mailCombined={}
    for name,v in pairs(charTbl.mail or {}) do
        local q=tonumber(type(v)=="table" and (v.count or v.qty) or v) or 0
        if q>0 then mailCombined[name]=(mailCombined[name] or 0)+q end
    end
    for name,v in pairs(charTbl.bought or {}) do
        local q=tonumber(type(v)=="table" and (v.count or v.qty) or v) or 0
        if q>0 then mailCombined[name]=(mailCombined[name] or 0)+q end
    end
    push("mail",mailCombined,nil)
    push("gear",charTbl.gear,nil)
    return entries
end
local wealthEvalBank,wealthEvalEpoch={},nil
local lastWealthSnapAt
function Capture.QueueWealthSnapshot(opts)
    opts=opts or {}; if not ready() or Store.IsDisabled("SNAPSHOT") then return end
    if Capture._snapshotRunning then Capture._snapshotAgain=true; return end
    local h=H(); if not (h and h.app and h.app.char) then return end
    local priceVersion=h.GetEffectivePriceVersion and h.GetEffectivePriceVersion() or h.priceCacheEpoch or 0
    if wealthEvalEpoch~=h.priceCacheEpoch then wealthEvalBank={}; wealthEvalEpoch=h.priceCacheEpoch end
    Capture._snapshotRunning=true
    lastWealthSnapAt=nowSec()
    if h.app.scanGear then pcall(h.app.scanGear) end
    local char,charEcon=Store.CurrentCharAndEcon(); charEcon=Store.DeriveEcon(char,charEcon)
    local hostDB=_G.MerchantMasterDB or {}
    if not (type(h.app.charKey)=="string" and h.app.charKey~="") and char=="Normal-Horde-Forever-Player" then
        local root=db()
        local skipGhost=(not Capture._testReady and Capture.loggedIn~=true)
        if not skipGhost then
            for _,tbl in ipairs({root and root.snaps,root and root.wealth,root and root.inventory,hostDB.chars}) do
                if type(tbl)=="table" then
                    for k in pairs(tbl) do
                        if type(k)=="string" and k~="" and k~="Normal-Horde-Forever-Player" then skipGhost=true; break end
                    end
                end
                if skipGhost then break end
            end
        end
        if skipGhost then Capture._snapshotRunning=nil; Capture._snapshotAgain=nil; return end
    end
    local allEntries=Capture.CollectCharEntries(h,hostDB,h.app.char)
    local batches,batch={},{}
    for _,e in ipairs(allEntries) do
        batch[#batch+1]=e
        if #batch==25 then batches[#batches+1]=batch; batch={} end
    end
    if #batch>0 then batches[#batches+1]=batch end
    local parts={char,charEcon,tostring(money()),Store.DayKey(),tostring(Store.accountingVersion or Store.version),tostring(priceVersion),tostring(hostDB.priceSource),tostring(hostDB.lastRefreshAt)}
    for _,e in ipairs(allEntries) do parts[#parts+1]=table.concat({tostring(e.cat),tostring(e.id),tostring(e.qty),tostring(e.bound)},":") end
    table.sort(parts)
    local inputSignature=table.concat(parts,"|")
    if not opts.force and not opts.sync and Capture._snapshotSignature==inputSignature then Capture._snapshotRunning=nil; Capture._snapshotAgain=nil; return end
    local catTotals={bags=0,bank=0,mail=0,gear=0}
    local detailCats={bags={},bank={},mail={},gear={},listed={}}
    local itemsVal,failed=0,false
    local function slice(entries)
        local active=(h.DetectActiveEconomy and h.DetectActiveEconomy()) or charEcon
        local ok,err=Capture.WithCharEconomy(h,hostDB,charEcon,function()
            for _,entry in ipairs(entries) do
                local unit,basis=Capture.ValueWealthItem(h,hostDB,charEcon,active,entry.id,entry.bound,entry.cat)
                local total=math.floor(entry.qty*unit+0.5)
                itemsVal=itemsVal+total
                catTotals[entry.cat]=(catTotals[entry.cat] or 0)+total
                local list=detailCats[entry.cat]
                list[#list+1]={id=entry.id,name=entry.name,qty=entry.qty,unit=math.floor(unit+0.5),total=total,basis=basis,bound=entry.bound or nil}
            end
        end,wealthEvalBank)
        if not ok then failed=true; Capture._snapshotRunning=nil; error(err) end
    end
    local function done()
        local listed=0
        for itemID,lots in pairs(Store.Lots(char)) do
            local qtySum,valSum=0,0
            for _,lot in ipairs(lots) do
                local q,u=lot.qty or 0,lot.unit or 0
                qtySum=qtySum+q; valSum=valSum+q*u
            end
            if qtySum>0 then
                listed=listed+valSum
                local nm=(h.ItemName and h.ItemName(itemID)) or ("Item #"..tostring(itemID))
                detailCats.listed[#detailCats.listed+1]={id=itemID,name=nm,qty=qtySum,unit=math.floor(valSum/qtySum+0.5),total=valSum,basis="AH Listing"}
            end
        end
        for _,list in pairs(detailCats) do
            table.sort(list,function(a,b) if a.total~=b.total then return a.total>b.total end; return tostring(a.name or "")<tostring(b.name or "") end)
        end
        if not failed then
            Capture._snapshotSignature=inputSignature
            Store.SaveSnapshot(char,Store.DayKey(),{
                gold=money(),items=math.floor(itemsVal+0.5),
                bags=math.floor(catTotals.bags+0.5),bank=math.floor(catTotals.bank+0.5),
                mail=math.floor(catTotals.mail+0.5),gear=math.floor(catTotals.gear+0.5),
                listed=listed,econ=charEcon,
            },{at=nowSec(),econ=charEcon,cats=detailCats})
        end
        Capture._snapshotRunning=nil
        if Capture._snapshotAgain then Capture._snapshotAgain=nil; after(0,function() safeCall("SNAPSHOT",Capture.QueueWealthSnapshot) end) end
    end
    if opts.sync then for _,entries in ipairs(batches) do slice(entries) end; done()
    else Store.Chunk(batches,1,function(entries) safeCall("SNAPSHOT",slice,entries) end,done) end
end
local function dirtySnapshot(throttle)
    if Capture._snapshotQueued then return end; Capture._snapshotQueued=true
    local delay=throttle and lastWealthSnapAt and math.max(1,30-(nowSec()-lastWealthSnapAt)) or 1
    after(delay,function() Capture._snapshotQueued=nil; if ready() then safeCall("SNAPSHOT",Capture.QueueWealthSnapshot) end end)
end
Capture.MailboxSnapshotCommitted=dirtySnapshot
local handlers={}
handlers.COMMODITY_PRICE_UPDATED=function(unit,total) if pendingCommodity then pendingCommodity.unit=tonumber(unit) or 0; pendingCommodity.total=tonumber(total) or 0 end end
handlers.COMMODITY_PURCHASE_SUCCEEDED=function()
    local p=pendingCommodity; pendingCommodity=nil
    if p then append("AH_BUY",p.itemID,p.qty,p.unit,-p.total,"Auction House") end
end
handlers.COMMODITY_PURCHASE_FAILED=function() pendingCommodity=nil end
local function isBankOpen()
    if ns.Inventory and ns.Inventory.IsBankOpen then return ns.Inventory.IsBankOpen() end
    local h=H()
    if Capture._bankOpen==true or (h and h.app and h.app.atBank==true) then return true end
    local shown=_G.BankFrame and _G.BankFrame.IsShown and _G.BankFrame:IsShown()
    return not hasSecret(shown) and shown==true or false
end
handlers.AUCTION_HOUSE_CLOSED=function()
    pendingCommodity=nil; pendingBid=nil
    if pendingPost and isPendingPostAwaitingConfirm(pendingPost) then pendingPost=nil end
    if ns.Inventory then ns.Inventory.ScanCurrentChar({ skipGear = true }) end; dirtySnapshot()
end
handlers.AUCTION_HOUSE_PURCHASE_COMPLETED=function(id)
    local p=pendingBid
    if p and p.isBuyout~=false and (id==nil or id==p.auctionID) and nowSec()-p.at<=30 then pendingBid=nil; append("AH_BUY",p.itemID,p.qty,math.floor(p.amount/math.max(1,p.qty)+0.5),-p.amount,"Auction House") end
end
handlers.AUCTION_HOUSE_AUCTION_CREATED=function(id) confirmPost(false,not hasSecret(id) and tonumber(id) or nil) end
local function hasCollectableAHMail()
    for _,m in pairs(mailCache) do
        if type(m)=="table" and not m.consumed and mailCollectable(m) then return true end
    end
    return false
end
function Capture.SyncOwnedAuctions()
    local ah=_G.C_AuctionHouse
    if not ah or not ah.GetNumOwnedAuctions or not ah.GetOwnedAuctionInfo then return 0 end
    if not (_G.AuctionHouseFrame and _G.AuctionHouseFrame.IsShown and _G.AuctionHouseFrame:IsShown()) then return 0 end
    if pendingPost or (lastConfirmedPost and nowSec()-lastConfirmedPost.at<=30) then return 0 end
    if not Capture.visitedMailboxThisSession or (_G.HasNewMail and _G.HasNewMail()) or hasCollectableAHMail() then return 0 end
    local n=ah.GetNumOwnedAuctions(); if n==nil or hasSecret(n) then return 0 end
    local activeIDs,counts={},{}
    for i=1,n do
        local info=ah.GetOwnedAuctionInfo(i)
        if safeTable(info) then
            if hasSecret(info.auctionID,info.status,info.quantity) then return 0 end
            local id=auctionItem(info)
            if info.auctionID then activeIDs[info.auctionID]=true end
            -- Both active (0) and sold-awaiting-mail (1) remain open until mail arrives.
            if id and (info.status==nil or info.status==0 or info.status==1) then
                counts[id]=(counts[id] or 0)+(tonumber(info.quantity) or 1)
            end
        end
    end
    local char=Store.CurrentCharAndEcon()
    return Store.PruneMissingLots and Store.PruneMissingLots(char,activeIDs,counts,nowSec()-60) or 0
end
local function ownedAuctionName(info)
    if not safeTable(info) then return nil end
    if not hasSecret(info.itemLink) and type(info.itemLink)=="string" and info.itemLink~="" then
        local nm=linkName(info.itemLink); if nm then return nm end
    end
    local key=safeTable(info.itemKey) and info.itemKey or nil
    if key and not hasSecret(key.itemID,key.itemSuffix) then
        local ah=_G.C_AuctionHouse
        if ah and ah.GetItemKeyInfo then
            local ok,keyInfo=pcall(ah.GetItemKeyInfo,key)
            if ok and safeTable(keyInfo) and not hasSecret(keyInfo.itemName) and type(keyInfo.itemName)=="string" and keyInfo.itemName~="" then
                return keyInfo.itemName
            end
        end
    end
    if not hasSecret(info.itemName) and type(info.itemName)=="string" and info.itemName~="" then return info.itemName end
    return nil
end
local function indexOwnedAuctionNames()
    local ah=_G.C_AuctionHouse
    if not ah or not ah.GetNumOwnedAuctions or not ah.GetOwnedAuctionInfo then return 0 end
    local n=ah.GetNumOwnedAuctions(); if hasSecret(n) or not tonumber(n) then return 0 end
    local indexed=0
    for i=1,tonumber(n) do
        local info=ah.GetOwnedAuctionInfo(i)
        if safeTable(info) then
            local id=auctionItem(info)
            if id and id>0 then
                local nm=ownedAuctionName(info)
                if nm and nm~="" then
                    if Store.IndexItemName then Store.IndexItemName(nm,id) end
                    indexed=indexed+1
                end
            end
        end
    end
    return indexed
end
Capture.IndexOwnedAuctionNames=indexOwnedAuctionNames
handlers.OWNED_AUCTIONS_UPDATED=function()
    indexOwnedAuctionNames()
    local ah=_G.C_AuctionHouse
    local function latestOwnedID(targetItem)
        if ah and ah.GetNumOwnedAuctions and ah.GetOwnedAuctionInfo then
            local n=ah.GetNumOwnedAuctions()
            if hasSecret(n) then return nil end
            local info=n and n>0 and ah.GetOwnedAuctionInfo(n)
            if safeTable(info) and not hasSecret(info.auctionID) and auctionItem(info)==targetItem then return info.auctionID end
        end
    end
    local ownedIncreased=pendingPost and ah and ah.GetNumOwnedAuctions and pendingPost.ownedCount and (tonumber(ah.GetNumOwnedAuctions()) or 0)>(tonumber(pendingPost.ownedCount) or 0)
    if pendingPost and (ownedIncreased or (not isPendingPostAwaitingConfirm(pendingPost) and (not pendingPost.ownedCount or not ah.GetNumOwnedAuctions or ah.GetNumOwnedAuctions()>pendingPost.ownedCount))) then
        confirmPost(false,latestOwnedID(pendingPost.itemID))
    elseif lastConfirmedPost and not lastConfirmedPost.auctionID and nowSec()-lastConfirmedPost.at<=30 then
        local aid=latestOwnedID(lastConfirmedPost.itemID)
        if aid then bindPostAuctionID(lastConfirmedPost,aid) end
    else
        Capture.SyncOwnedAuctions()
    end
end
handlers.AUCTION_CANCELED=function(id)
    local p=pendingCancels[id]; pendingCancels[id]=nil
    if p and nowSec()-p.at<=30 then append("AH_CANCEL",p.itemID,p.qty,p.unitPrice or 0,-p.cost,"Auction House",{auctionID=p.auctionID or id,unitPrice=p.unitPrice}) end
end
handlers.CHAT_MSG_SYSTEM=function(msg)
    if type(msg)~="string" or msg=="" then return end
    local soldName
    if type(_G.ERR_AUCTION_SOLD_S)=="string" and _G.ERR_AUCTION_SOLD_S:find("%%s",1,true) then
        local pat="^".._G.ERR_AUCTION_SOLD_S:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1"):gsub("%%%%s","(.+)").."$"
        soldName=msg:match(pat)
    end
    if not soldName then soldName=msg:match("^A buyer has been found for your auction of (.+)%.$") end
    if soldName and soldName~="" then liveSoldNoticeTime[soldName]=nowSec() end
end
handlers.CLOSE_INBOX_ITEM=function(index,subIndex)
    confirmSellerMail(); Capture.InspectAndRecordMail(index,subIndex)
    local h=H(); local pending=h and h.app and h.app.mailboxScanPending
    local mhActive=h and h.MailHelper and h.MailHelper.IsActive and h.MailHelper.IsActive()
    if h and h.app and h.app.QueueMailboxScan and not mhActive and not (pending and pending.actionPending) then h.app.QueueMailboxScan("take") end
end
handlers.MAIL_INBOX_UPDATE=function()
    -- Retrieval accounting can confirm here; unsolicited notifications never scan ownership.
    confirmSellerMail()
    lastMoney=money()
    local count=_G.GetInboxNumItems and _G.GetInboxNumItems()
    if not hasSecret(count) and count==0 then Capture._mailObservedEmpty=true end
    local h=H()
    if not (h and h.app and h.app.QueueMailboxScan) and Capture._standaloneMailAction then
        Capture._standaloneMailAction=nil; cacheMail()
    end
end
handlers.MAIL_SHOW=function()
    Capture.visitedMailboxThisSession=true
    lastMoney=money()
    local h=H()
    if not (h and h.app and h.app.QueueMailboxScan) then
        local snapshot=Capture.ScanMailboxSnapshot()
        if snapshot and ns.Inventory then local char=Store.CurrentCharAndEcon(); local _,arrived=ns.Inventory.AcceptMailboxSnapshot(snapshot); ns.Inventory.ReceiveTransitMail(char,arrived) end
    end
end
handlers.MAIL_SEND_INFO_UPDATE=function() snapshotCompose() end
handlers.BANKFRAME_OPENED=function()
    Capture._bankOpen=true
    if ns.Inventory then ns.Inventory.ScanBank(); ns.Inventory.ScanCurrentChar({ skipGear = true }) end
    Capture._snapshotSignature=nil
    dirtySnapshot()
end
handlers.BANKFRAME_CLOSED=function()
    if ns.Inventory and isBankOpen() then
        ns.Inventory.ScanBank()
        ns.Inventory.ScanCurrentChar({ skipGear = true })
    elseif ns.Inventory then
        ns.Inventory.ScanCurrentChar({ skipGear = true })
    end
    Capture._bankOpen=false
    Capture._snapshotSignature=nil
    dirtySnapshot()
end
handlers.PLAYERBANKSLOTS_CHANGED=function()
    if not isBankOpen() then return end
    if ns.Inventory then ns.Inventory.ScanBank(); ns.Inventory.ScanCurrentChar({ skipGear = true }) end
    Capture._snapshotSignature=nil
    dirtySnapshot()
end
handlers.GUILDBANKFRAME_OPENED=function() snapshotGuildBank() end
handlers.GUILDBANKBAGSLOTS_CHANGED=function() snapshotGuildBank() end
handlers.PLAYER_EQUIPMENT_CHANGED=function()
    if ns.Inventory and ns.Inventory.ScanCurrentChar then ns.Inventory.ScanCurrentChar() end
    Capture._snapshotSignature=nil
    dirtySnapshot()
end
handlers.GET_ITEM_INFO_RECEIVED=function(itemID)
    local id=not hasSecret(itemID) and tonumber(itemID) or nil
    if id and Capture._pendingItemIDs[id] then
        Capture._pendingItemIDs[id]=nil; Capture._snapshotSignature=nil
        dirtySnapshot()
    end
end
local merchantSession=0
local merchantSlots,merchantUpdateQueued={},false
local function primeMerchantItems()
    if not _G.GetMerchantNumItems then return end
    local count=_G.GetMerchantNumItems(); if hasSecret(count) then return end
    local ids={}
    for slot=1,tonumber(count) or 0 do
        local link=_G.GetMerchantItemLink and _G.GetMerchantItemLink(slot)
        local id=not hasSecret(link) and itemID(link)
        if not id then
            local api=_G.C_MerchantFrame; local fn=api and (api.GetItemInfo or api.GetMerchantItemInfo)
            local info=fn and fn(slot); if safeTable(info) and not hasSecret(info.itemID) then id=tonumber(info.itemID) end
        end
        if id and merchantSlots[slot]~=id then merchantSlots[slot]=id; ids[#ids+1]=id end
    end
    if ns.Tooltips and #ids>0 then local session=merchantSession; ns.Tooltips.PrimeItems(ids,function() return merchantSession==session end) end
end
handlers.MERCHANT_SHOW=function()
    merchantSession=merchantSession+1; merchantSlots={}; merchantUpdateQueued=false
    cacheBuybackItems(); Capture.lastFavor=currencyQuantity() or Capture.lastFavor
    primeMerchantItems()
end
handlers.MERCHANT_UPDATE=function()
    if merchantUpdateQueued then return end
    merchantUpdateQueued=true; local session=merchantSession
    after(1,function() if session~=merchantSession then return end; merchantUpdateQueued=false; primeMerchantItems() end)
end
handlers.MERCHANT_CLOSED=function() pendingVendorSell=nil; merchantSession=merchantSession+1; merchantSlots={}; merchantUpdateQueued=false; if ns.Inventory then ns.Inventory.ScanCurrentChar({ skipGear = true }) end; dirtySnapshot() end
handlers.ITEM_SEARCH_RESULTS_UPDATED=function(itemKey)
    local ah=_G.C_AuctionHouse
    if not ah or not ah.GetNumItemSearchResults or not ah.GetItemSearchResultInfo then return end
    local count=ah.GetNumItemSearchResults(itemKey); if hasSecret(count) then return end
    for i=1,(tonumber(count) or 0) do
        local info=ah.GetItemSearchResultInfo(itemKey,i)
        if safeTable(info) and not hasSecret(info.auctionID) and info.auctionID then
            if not info.itemKey then info.itemKey=itemKey end
            auctionCache[info.auctionID]=info
        end
    end
end
handlers.MAIL_SEND_SUCCESS=function() stagedCompose=nil; completeSendMail() end
handlers.MAIL_FAILED=function() pendingSendMail=nil; stagedSendMoney=nil; stagedSendCOD=nil; stagedCompose=nil end
handlers.MAIL_CLOSED=function()
    pendingSendMail=nil; stagedSendMoney=nil; stagedSendCOD=nil; stagedCompose=nil; lastDeletedMailIndex=nil; Capture._standaloneMailAction=nil
    if ns.Inventory then
        ns.Inventory.ScanCurrentChar({ skipGear = true })
        if Capture._mailObservedEmpty and ns.Inventory.ClearInTransitForChar then
            ns.Inventory.ClearInTransitForChar(Store.CurrentCharAndEcon())
        end
    end
    dirtySnapshot()
end
handlers.TRADE_SHOW=function() stageTrade(true) end
handlers.TRADE_PLAYER_ITEM_CHANGED=function() if pendingTrade and not pendingTrade.closed and not pendingTrade.confirmed then stageTrade(false) end end
handlers.TRADE_TARGET_ITEM_CHANGED=function() if pendingTrade and not pendingTrade.closed and not pendingTrade.confirmed then stageTrade(false) end end
handlers.TRADE_MONEY_CHANGED=function() if pendingTrade and not pendingTrade.closed and not pendingTrade.confirmed then stageTrade(false) end end
handlers.TRADE_ACCEPT_UPDATE=function(player,target)
    local pAcc,tAcc=tonumber(player)==1,tonumber(target)==1
    if pAcc or tAcc then
        if not pendingTrade or (not pendingTrade.closed and not pendingTrade.confirmed) then stageTrade(false) end
        if pendingTrade then pendingTrade.acceptSeen=true; pendingTrade.accepted=(pAcc and tAcc); pendingTrade.at=nowSec() end
    elseif pendingTrade and not pendingTrade.closed and not pendingTrade.confirmed then
        pendingTrade.accepted=false; pendingTrade.acceptSeen=false
    end
end
handlers.TRADE_CLOSED=function()
    if pendingTrade and (pendingTrade.confirmed or pendingTrade.accepted or pendingTrade.acceptSeen) then
        pendingTrade.closed=true; pendingTrade.closedAt=pendingTrade.closedAt or nowSec(); pendingTrade.at=nowSec(); completeTrade(false)
    else
        pendingTrade=nil
    end
    if ns.Inventory then ns.Inventory.ScanCurrentChar({ skipGear = true }) end
    dirtySnapshot()
end
handlers.UI_INFO_MESSAGE=function(errorType,message)
    local isComplete=(_G.LE_GAME_ERR_TRADE_COMPLETE~=nil and errorType==_G.LE_GAME_ERR_TRADE_COMPLETE)
        or (_G.ERR_TRADE_COMPLETE~=nil and message==_G.ERR_TRADE_COMPLETE)
        or (type(message)=="string" and message=="Trade complete.")
    local isCancelled=(_G.LE_GAME_ERR_TRADE_CANCELLED~=nil and errorType==_G.LE_GAME_ERR_TRADE_CANCELLED)
        or (_G.ERR_TRADE_CANCELLED~=nil and message==_G.ERR_TRADE_CANCELLED)
        or (type(message)=="string" and message=="Trade cancelled.")
    if isComplete then
        if pendingTrade then pendingTrade.accepted=true; pendingTrade.acceptSeen=true; pendingTrade.confirmed=true; pendingTrade.at=nowSec() end
        completeTrade(true)
    elseif isCancelled then
        pendingTrade=nil
    end
end
handlers.TRAINER_SHOW=cacheTrainerServices
handlers.TRAINER_UPDATE=cacheTrainerServices
handlers.TRAINER_CLOSED=function() ws3.trainerCache={} end
handlers.UI_ERROR_MESSAGE=function(errorType,message)
    if #ws3.pendingMoneyQueue==0 and not (pendingBid and pendingBid.isBuyout==false) then return end
    local msg=(type(message)=="string") and string.lower(message) or ""
    if msg=="" or msg:find("money",1,true) or msg:find("afford",1,true) or msg:find("bid",1,true)
        or msg:find("auction",1,true) or msg:find("guild",1,true) or msg:find("withdraw",1,true)
        or msg:find("deposit",1,true) or msg:find("train",1,true) or msg:find("skill",1,true)
        or msg:find("learn",1,true) or msg:find("gold",1,true) or msg:find("permission",1,true)
        or msg:find("rank",1,true) or msg:find("fund",1,true) or msg:find("purchase",1,true)
        or msg:find("buy",1,true) or msg:find("fail",1,true) or msg:find("cannot",1,true)
        or msg:find("can't",1,true) or msg:find("invalid",1,true) or msg:find("unavailable",1,true) then
        clearPendingMoneyQueue()
        if pendingBid and pendingBid.isBuyout==false then pendingBid=nil end
    end
end
handlers.PLAYER_MONEY=function()
    local current=money()
    confirmSellerMail()
    if pendingTrade and (pendingTrade.confirmed or pendingTrade.closed) then completeTrade(false) end
    confirmIncomingMail()
    if pendingRepair then confirmRepair(current) else lastDurability=durabilitySnapshot() or lastDurability end
    local b=pendingBuyback; if b and nowSec()-b.at<=10 and b.before-current>=b.cost and itemCount(b.itemID)>b.beforeCount then pendingBuyback=nil; append("VENDOR_BUYBACK",b.itemID,b.qty,math.floor(b.cost/math.max(1,b.qty)+0.5),-b.cost,"Buyback",{}) end
    playerMoney(); dirtySnapshot(true)
end
handlers.BAG_UPDATE_DELAYED=function()
    if pendingTrade and (pendingTrade.confirmed or pendingTrade.closed) then completeTrade(false) end
    destroyItems(); lootItems(); craftItems(); confirmBuyerInvoices(); confirmIncomingMail()
    if pendingBuyback and nowSec()-pendingBuyback.at<=10 and itemCount(pendingBuyback.itemID)>pendingBuyback.beforeCount then local b=pendingBuyback; if b.before-money()>=b.cost then pendingBuyback=nil; append("VENDOR_BUYBACK",b.itemID,b.qty,math.floor(b.cost/math.max(1,b.qty)+0.5),-b.cost,"Buyback",{}) end end
    if ns.Inventory then
        if isBankOpen() then ns.Inventory.ScanBank() end
        ns.Inventory.ScanCurrentChar({ skipGear = true })
    end
    dirtySnapshot(true)
end
handlers.UNIT_SPELLCAST_SUCCEEDED=castSucceeded
handlers.CHAT_MSG_LOOT=chatMsgLoot
handlers.LOOT_READY=lootOpen
handlers.LOOT_OPENED=lootOpen
handlers.LOOT_SLOT_CLEARED=function() lootItems() end
handlers.LOOT_CLOSED=function()
    lootItems(); local s=lootSession
    if s then
        local unrecorded=money()-s.beforeMoney-s.coinRecorded
        if unrecorded>0 and not pendingPouch and not merchantOpen() and not questContext and not (_G.MailFrame and _G.MailFrame.IsShown and _G.MailFrame:IsShown()) then lootMoney(unrecorded) end
        s.closedAt=nowSec(); after(2,function() if lootSession==s then safeCall("LOOT",lootItems); lootSession=nil end end)
    end
    local p=pendingPouch; if p then p.expires=nowSec()+2; after(2,function() if pendingPouch==p then pendingPouch=nil end end) end
end
handlers.QUEST_TURNED_IN=questTurnedIn
handlers.CURRENCY_DISPLAY_UPDATE=currencyUpdate
handlers.UPDATE_FACTION=function() standing(false) end
handlers.PLAYER_LOGOUT=function()
    local char,econ=Store.CurrentCharAndEcon(); Store.ReconcileGold(char,money(),"Logout Reconciliation")
    local h=H()
    if h and h.app and h.app.char then pcall(Capture.QueueWealthSnapshot,{sync=true}) end
    local snap=db().snaps[char] and db().snaps[char][Store.DayKey()] or {items=0,listed=0,econ=econ,goldOnly=true}
    snap.gold=money(); Store.SaveSnapshot(char,Store.DayKey(),snap)
end
local eventKinds={COMMODITY_PRICE_UPDATED="AH_BUY",COMMODITY_PURCHASE_SUCCEEDED="AH_BUY",COMMODITY_PURCHASE_FAILED="AH_BUY",AUCTION_HOUSE_PURCHASE_COMPLETED="AH_BUY",AUCTION_HOUSE_AUCTION_CREATED="AH_POST",OWNED_AUCTIONS_UPDATED="AH_POST",AUCTION_CANCELED="AH_CANCEL",CLOSE_INBOX_ITEM="MAIL",MAIL_INBOX_UPDATE="MAIL",MAIL_SHOW="MAIL",LOOT_READY="LOOT",LOOT_OPENED="LOOT",LOOT_CLOSED="LOOT",LOOT_SLOT_CLEARED="LOOT",QUEST_TURNED_IN="QUEST",CURRENCY_DISPLAY_UPDATE="FAVOR",UPDATE_FACTION="STANDING"}
function Capture.OnEvent(self,event,...)
    if hasSecret(...) then return end
    if event=="ADDON_LOADED" then
        local loaded=...
        if loaded==addonName then Store.Init() end
        return
    elseif event=="PLAYER_LOGIN" then
        Capture.SyncActiveWritQuests()
        if Capture.loggedIn then return end
        Store.Init()
        if Store.MigrateForeverSurnames then
            local h = H()
            Store.MigrateForeverSurnames(_G.MerchantMasterDB and _G.MerchantMasterDB.chars, h and h.app and h.app.charKey)
        end
        Capture.InstallHooks(); if not ready() then return end
        lastDurability=durabilitySnapshot()
        Capture.loggedIn = true
        local char=Store.CurrentCharAndEcon(); Store.InitRecon(char,money()); lastMoney=money(); Capture.lastFavor=currencyQuantity()
        if ns.Inventory then safeCall("INVENTORY",ns.Inventory.ScanCurrentChar) end
        safeCall("STANDING",standing,true)
        after(3,function()
            if not ready() then return end
            safeCall("MAINTENANCE",function()
                pruneSeenMail(db().seenMail,nowSec())
                Store.PackOldDays(1); Capture.QueueWealthSnapshot()
            end)
        end)
        return
    end
    if not ready() then return end
    Store.ProbeLog(event,"args="..select("#",...))
    local fn=handlers[event]
    if fn then safeCall(eventKinds[event] or event,fn,...) end
end
Capture.frame=_G.CreateFrame("Frame")
Capture.frame:SetScript("OnEvent",Capture.OnEvent)
Capture.frame:RegisterEvent("ADDON_LOADED"); Capture.frame:RegisterEvent("PLAYER_LOGIN")
for _,event in ipairs({"MAIL_SEND_SUCCESS","MAIL_FAILED","TRADE_SHOW","TRADE_PLAYER_ITEM_CHANGED","TRADE_TARGET_ITEM_CHANGED","TRADE_MONEY_CHANGED","TRADE_ACCEPT_UPDATE","TRADE_CLOSED","UI_INFO_MESSAGE","GUILDBANKFRAME_OPENED","GUILDBANKBAGSLOTS_CHANGED"}) do handlers[event]=handlers[event] or function() end end
for event in pairs(handlers) do
    -- Event availability differs between modern Forever and legacy clients.
    pcall(Capture.frame.RegisterEvent,Capture.frame,event)
end




